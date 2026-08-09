"""
FlowAgent - order-flow and positioning context for Binance USDT-M futures.

This agent uses public Binance futures data only:
  - open interest history
  - taker long/short ratio
  - global long/short account ratio

It is best-effort by design. If a public endpoint misses, it returns neutral
instead of stopping the trading loop.
"""

from __future__ import annotations

import logging
import os
import time
from dataclasses import asdict, dataclass
from typing import Any, Dict, Optional, Tuple

import requests

from config import TradingConfig

logger = logging.getLogger(__name__)

BINANCE_DATA_BASE = "https://fapi.binance.com/futures/data"
_FLOW_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "flow_state.json")


@dataclass
class FlowAssessment:
    approved: bool
    vote: bool
    score_adjustment: float
    size_multiplier: float
    hard_block: bool
    reason: str
    metrics: Dict[str, float]


class FlowAgent:
    """Checks whether positioning and taker flow support a candidate trade."""

    def __init__(self, config: TradingConfig, monitor: Optional[Any] = None):
        self.config = config
        self.monitor = monitor
        self.session = requests.Session()
        self._cache: Dict[str, Tuple[float, Dict[str, float]]] = {}
        self._last_snapshot: Dict[str, Any] = {}

    def assess_trade(self, symbol: str, direction: str) -> FlowAssessment:
        if not self.config.flow_agent_enabled:
            return FlowAssessment(True, True, 0.0, 1.0, False, "flow disabled", {})

        symbol = (symbol or "").upper()
        direction = (direction or "LONG").upper()
        try:
            metrics = self._metrics(symbol)
        except Exception as exc:
            logger.debug("Flow assessment unavailable for %s: %s", symbol, exc)
            return FlowAssessment(True, True, 0.0, 1.0, False, "flow unavailable", {})

        oi_change = metrics.get("oi_change_pct", 0.0)
        taker_ratio = metrics.get("taker_buy_sell_ratio", 1.0)
        global_ratio = metrics.get("global_long_short_ratio", 1.0)

        min_oi = self.config.flow_min_oi_change_pct
        score_adj = 0.0
        size_mult = 1.0
        reasons = []
        hard_block = False

        buy_aligned = oi_change >= min_oi and taker_ratio >= self.config.flow_taker_buy_ratio
        sell_aligned = oi_change >= min_oi and taker_ratio <= self.config.flow_taker_sell_ratio
        buy_opposite = oi_change >= min_oi and taker_ratio <= self.config.flow_taker_sell_ratio
        sell_opposite = oi_change >= min_oi and taker_ratio >= self.config.flow_taker_buy_ratio

        if direction == "LONG":
            if buy_aligned:
                score_adj += self.config.flow_score_boost
                reasons.append("OI rising with taker buys")
            elif buy_opposite:
                score_adj -= self.config.flow_score_penalty
                size_mult *= self.config.flow_size_penalty
                reasons.append("OI rising against LONG")
                hard_block = bool(self.config.flow_hard_block_opposite)

            if taker_ratio >= self.config.flow_strong_taker_ratio:
                score_adj += 1.5
                reasons.append("strong taker buy pressure")
            if global_ratio >= self.config.flow_crowded_long_ratio:
                score_adj -= 2.0
                size_mult *= 0.90
                reasons.append("crowded long positioning")
            elif global_ratio <= 0.75:
                score_adj += 1.0
                reasons.append("short crowd can squeeze")

        elif direction == "SHORT":
            if sell_aligned:
                score_adj += self.config.flow_score_boost
                reasons.append("OI rising with taker sells")
            elif sell_opposite:
                score_adj -= self.config.flow_score_penalty
                size_mult *= self.config.flow_size_penalty
                reasons.append("OI rising against SHORT")
                hard_block = bool(self.config.flow_hard_block_opposite)

            if taker_ratio <= 1.0 / max(self.config.flow_strong_taker_ratio, 1e-9):
                score_adj += 1.5
                reasons.append("strong taker sell pressure")
            if global_ratio <= self.config.flow_crowded_short_ratio:
                score_adj -= 2.0
                size_mult *= 0.90
                reasons.append("crowded short positioning")
            elif global_ratio >= 1.35:
                score_adj += 1.0
                reasons.append("long crowd can squeeze")

        if oi_change <= -min_oi:
            score_adj -= 2.0
            size_mult *= 0.90
            reasons.append("open interest falling")

        score_cap = max(self.config.flow_score_boost + 2.0, self.config.flow_score_penalty + 2.0)
        score_adj = max(-score_cap, min(score_cap, score_adj))
        size_mult = max(0.10, min(1.0, size_mult))
        vote = (not hard_block) and score_adj >= -3.0

        reason = "; ".join(reasons) if reasons else "flow neutral"
        assessment = FlowAssessment(
            approved=not hard_block,
            vote=vote,
            score_adjustment=score_adj,
            size_multiplier=size_mult,
            hard_block=hard_block,
            reason=reason,
            metrics=metrics,
        )
        self._publish(symbol, direction, assessment)
        if self.monitor:
            detail = (
                f"{symbol} {direction}: oi={oi_change:+.2%} "
                f"taker={taker_ratio:.2f} global={global_ratio:.2f} | {reason}"
            )
            self.monitor.report(
                "Flow",
                "assess",
                detail,
                symbol=symbol,
                status="active",
                severity="INFO" if vote else "WARNING",
            )
        return assessment

    def _metrics(self, symbol: str) -> Dict[str, float]:
        now = time.time()
        cached = self._cache.get(symbol)
        if cached and now - cached[0] < self.config.flow_refresh_seconds:
            return cached[1]

        lookback = max(2, min(30, int(self.config.flow_lookback)))
        period = self.config.flow_period

        oi_hist = self._get_json(
            "/openInterestHist",
            {"symbol": symbol, "period": period, "limit": lookback},
        )
        taker_hist = self._get_json(
            "/takerlongshortRatio",
            {"symbol": symbol, "period": period, "limit": lookback},
        )
        global_hist = self._get_json(
            "/globalLongShortAccountRatio",
            {"symbol": symbol, "period": period, "limit": lookback},
        )

        if not isinstance(oi_hist, list) or len(oi_hist) < 2:
            raise ValueError("missing open interest history")

        oi_first = self._oi_value(oi_hist[0])
        oi_last = self._oi_value(oi_hist[-1])
        oi_change = (oi_last - oi_first) / oi_first if oi_first > 0 else 0.0

        taker_ratio = self._latest_ratio(taker_hist, "buySellRatio", default=1.0)
        global_ratio = self._latest_ratio(global_hist, "longShortRatio", default=1.0)

        metrics = {
            "oi_change_pct": float(oi_change),
            "open_interest_first": float(oi_first),
            "open_interest_last": float(oi_last),
            "taker_buy_sell_ratio": float(taker_ratio),
            "global_long_short_ratio": float(global_ratio),
        }
        self._cache[symbol] = (now, metrics)
        return metrics

    def _get_json(self, path: str, params: Dict[str, Any]) -> Any:
        url = f"{BINANCE_DATA_BASE}{path}"
        r = self.session.get(url, params=params, timeout=10)
        r.raise_for_status()
        return r.json()

    @staticmethod
    def _oi_value(row: Dict[str, Any]) -> float:
        for key in ("sumOpenInterestValue", "sumOpenInterest"):
            try:
                value = float(row.get(key, 0) or 0)
                if value > 0:
                    return value
            except (TypeError, ValueError):
                continue
        return 0.0

    @staticmethod
    def _latest_ratio(rows: Any, key: str, default: float = 1.0) -> float:
        if not isinstance(rows, list) or not rows:
            return default
        try:
            value = float(rows[-1].get(key, default) or default)
            return value if value > 0 else default
        except (TypeError, ValueError, AttributeError):
            return default

    def _publish(self, symbol: str, direction: str, assessment: FlowAssessment) -> None:
        self._last_snapshot = {
            "updated_at": time.time(),
            "symbol": symbol,
            "direction": direction,
            **asdict(assessment),
        }
        try:
            os.makedirs(os.path.dirname(_FLOW_FILE), exist_ok=True)
            import json

            with open(_FLOW_FILE, "w", encoding="utf-8") as f:
                json.dump(self._last_snapshot, f, ensure_ascii=False, indent=2)
        except Exception as exc:
            logger.debug("flow snapshot write failed: %s", exc)

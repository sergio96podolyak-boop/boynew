"""
MarketRegimeAgent — broad market context for entry gating.

The scanner looks for local opportunities. This agent asks whether the broader
market is friendly to that direction right now: trend, impulse, and volatility.
"""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import asdict, dataclass
from typing import Any, Dict, Optional

import numpy as np
import pandas as pd
import requests

from config import TradingConfig

logger = logging.getLogger(__name__)

BINANCE_FUTURES_BASE = "https://fapi.binance.com"
_REGIME_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "market_regime.json")


@dataclass
class RegimeSnapshot:
    updated_at: float
    symbol: str
    timeframe: str
    price: float
    trend: str
    impulse_4: float
    impulse_12: float
    realized_volatility: float
    atr_pct: float
    risk_state: str
    detail: str


@dataclass
class RegimeAssessment:
    approved: bool
    vote: bool
    score_adjustment: float
    size_multiplier: float
    reason: str


class MarketRegimeAgent:
    """Fetches and evaluates broad crypto market regime."""

    def __init__(self, config: TradingConfig, monitor: Optional[Any] = None):
        self.config = config
        self.monitor = monitor
        self.session = requests.Session()
        self.snapshot: Optional[RegimeSnapshot] = None
        self._last_refresh: float = 0.0

    def maybe_refresh(self) -> Optional[RegimeSnapshot]:
        now = time.time()
        if (
            self.snapshot is not None
            and now - self._last_refresh < self.config.market_regime_refresh_seconds
        ):
            return None
        return self.refresh()

    def refresh(self) -> Optional[RegimeSnapshot]:
        if self.monitor:
            self.monitor.report(
                "Regime",
                "scan",
                f"בודק משטר שוק דרך {self.config.market_regime_symbol}",
                status="working",
            )
        try:
            df = self._fetch_ohlcv(
                self.config.market_regime_symbol,
                self.config.market_regime_timeframe,
                self.config.market_regime_fetch_limit,
            )
            if df is None or len(df) < 30:
                raise ValueError("not enough regime candles")

            close = df["close"]
            price = float(close.iloc[-1])
            ema_fast = close.ewm(span=20, adjust=False).mean().iloc[-1]
            ema_slow = close.ewm(span=50, adjust=False).mean().iloc[-1]
            trend = "UP" if ema_fast > ema_slow else "DOWN" if ema_fast < ema_slow else "RANGE"

            impulse_4 = self._pct_change(close, 4)
            impulse_12 = self._pct_change(close, 12)
            returns = close.pct_change().dropna()
            realized_vol = float(returns.tail(20).std() * np.sqrt(20)) if len(returns) >= 20 else 0.0
            atr_pct = self._atr_pct(df)

            risk_state = "NORMAL"
            if abs(impulse_4) >= self.config.regime_block_longs_drop_pct:
                risk_state = "IMPULSE"
            if realized_vol >= self.config.regime_high_volatility_pct or atr_pct >= self.config.regime_high_volatility_pct:
                risk_state = "HIGH_VOL"

            detail = (
                f"{trend} | impulse4={impulse_4:+.2%} | impulse12={impulse_12:+.2%} | "
                f"vol={realized_vol:.2%} | atr={atr_pct:.2%}"
            )
            snap = RegimeSnapshot(
                updated_at=time.time(),
                symbol=self.config.market_regime_symbol,
                timeframe=self.config.market_regime_timeframe,
                price=price,
                trend=trend,
                impulse_4=impulse_4,
                impulse_12=impulse_12,
                realized_volatility=realized_vol,
                atr_pct=atr_pct,
                risk_state=risk_state,
                detail=detail,
            )
            self.snapshot = snap
            self._last_refresh = time.time()
            self._write_snapshot(snap)
            if self.monitor:
                self.monitor.report("Regime", "state", detail, status="active", force=True)
            return snap
        except Exception as exc:
            logger.debug("Market regime refresh failed: %s", exc)
            if self.monitor:
                self.monitor.report(
                    "Regime",
                    "stale",
                    "משטר שוק לא זמין כרגע",
                    status="paused",
                    severity="WARNING",
                )
            return None

    def assess_trade(self, opportunity: Dict[str, Any]) -> RegimeAssessment:
        """Return how the current broad regime treats a candidate trade."""
        snap = self.snapshot or self.refresh()
        if snap is None:
            return RegimeAssessment(True, False, -2.0, 0.80, "regime unavailable")

        direction = opportunity.get("direction", "LONG")
        score_adj = 0.0
        size_mult = 1.0
        reasons = []
        approved = True

        if direction == "LONG" and snap.impulse_4 <= -self.config.regime_block_longs_drop_pct:
            approved = False
            reasons.append(f"BTC impulse down {snap.impulse_4:.2%}")
        elif direction == "SHORT" and snap.impulse_4 >= self.config.regime_block_shorts_rally_pct:
            approved = False
            reasons.append(f"BTC impulse up {snap.impulse_4:.2%}")

        if direction == "LONG" and snap.trend == "UP":
            score_adj += 1.5
            reasons.append("trend aligned")
        elif direction == "SHORT" and snap.trend == "DOWN":
            score_adj += 1.5
            reasons.append("trend aligned")
        elif snap.trend in ("UP", "DOWN"):
            score_adj -= 2.0
            size_mult *= 0.85
            reasons.append("trend against trade")

        if snap.risk_state == "HIGH_VOL":
            score_adj -= 4.0
            size_mult *= self.config.regime_risk_off_size_mult
            reasons.append("high volatility risk-off")

        vote = approved and score_adj >= -3.0
        reason = "; ".join(reasons) if reasons else snap.detail
        return RegimeAssessment(approved, vote, score_adj, size_mult, reason)

    def _fetch_ohlcv(self, symbol: str, interval: str, limit: int) -> Optional[pd.DataFrame]:
        url = f"{BINANCE_FUTURES_BASE}/fapi/v1/klines"
        params = {"symbol": symbol, "interval": interval, "limit": limit}
        r = self.session.get(url, params=params, timeout=12)
        r.raise_for_status()
        rows = []
        for candle in r.json():
            rows.append(
                {
                    "open": float(candle[1]),
                    "high": float(candle[2]),
                    "low": float(candle[3]),
                    "close": float(candle[4]),
                    "volume": float(candle[7]),
                }
            )
        return pd.DataFrame(rows) if rows else None

    @staticmethod
    def _pct_change(series: pd.Series, periods: int) -> float:
        if len(series) <= periods:
            return 0.0
        base = float(series.iloc[-periods - 1])
        last = float(series.iloc[-1])
        return (last - base) / base if base > 0 else 0.0

    @staticmethod
    def _atr_pct(df: pd.DataFrame, period: int = 14) -> float:
        if len(df) < period + 1:
            return 0.0
        high_low = df["high"] - df["low"]
        high_close = (df["high"] - df["close"].shift()).abs()
        low_close = (df["low"] - df["close"].shift()).abs()
        tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        atr = float(tr.rolling(period).mean().iloc[-1])
        price = float(df["close"].iloc[-1])
        return atr / price if price > 0 else 0.0

    def _write_snapshot(self, snap: RegimeSnapshot) -> None:
        try:
            os.makedirs(os.path.dirname(_REGIME_FILE), exist_ok=True)
            with open(_REGIME_FILE, "w", encoding="utf-8") as f:
                json.dump(asdict(snap), f, ensure_ascii=False, indent=2)
        except Exception as exc:
            logger.debug("market regime snapshot write failed: %s", exc)

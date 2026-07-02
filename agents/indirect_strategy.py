"""
IndirectStrategyAgent - safely routes Grid/DCA/Arbitrage ideas into the
existing protected execution pipeline.

This agent never places orders. It only gives the decision committee a
score/size vote based on patterns that resemble:
  - Grid: range/mean-reversion conditions
  - DCA: staged entry after a pullback, never averaging down an occupied symbol
  - Arbitrage: funding/spread edge proxy
  - Martingale: inverted into risk reduction, not loss-chasing
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional

from config import TradingConfig

logger = logging.getLogger(__name__)


@dataclass
class IndirectStrategyAssessment:
    vote: bool
    score_adjustment: float
    size_multiplier: float
    reason: str
    modes: Dict[str, str]


class IndirectStrategyAgent:
    """Advisory strategy layer for advanced modules that are not direct bots."""

    def __init__(self, config: Optional[TradingConfig] = None, monitor: Optional[Any] = None):
        self.config = config or TradingConfig()
        self.monitor = monitor

    def assess_trade(
        self,
        opportunity: Dict[str, Any],
        *,
        open_positions: Optional[Dict[str, Any]] = None,
        drawdown_pct: float = 0.0,
    ) -> IndirectStrategyAssessment:
        symbol = str(opportunity.get("symbol", ""))
        direction = str(opportunity.get("direction", "LONG")).upper()
        features = opportunity.get("features") or {}
        open_positions = open_positions or {}

        if not self.config.indirect_strategies_enabled:
            return self._publish(
                symbol,
                "off",
                IndirectStrategyAssessment(True, 0.0, 1.0, "indirect strategies off", {}),
                "paused",
            )

        score_adj = 0.0
        size_mult = 1.0
        vote = True
        reasons = []
        modes: Dict[str, str] = {}

        choppiness = self._float(features.get("choppiness_14"), 50.0)
        adx = self._float(features.get("adx_14"), 0.0)
        bbp = self._float(features.get("bb_percent_b"), 0.5)
        pullback = self._float(features.get("pullback_pct"), 0.0)
        spread = self._float(opportunity.get("spread"), 0.0)
        funding = self._float(opportunity.get("funding_rate"), 0.0)
        funding_penalty = self._float(opportunity.get("funding_penalty"), 0.0)

        if self.config.indirect_grid_enabled:
            grid_adj, grid_mult, grid_vote, grid_reason = self._grid_proxy(
                direction=direction,
                choppiness=choppiness,
                adx=adx,
                bbp=bbp,
            )
            score_adj += grid_adj
            size_mult *= grid_mult
            vote = vote and grid_vote
            modes["grid"] = grid_reason
            reasons.append(f"GridProxy: {grid_reason}")

        if self.config.indirect_dca_enabled:
            dca_adj, dca_mult, dca_vote, dca_reason = self._dca_proxy(
                symbol=symbol,
                score=self._float(opportunity.get("score"), 0.0),
                pullback=pullback,
                open_positions=open_positions,
            )
            score_adj += dca_adj
            size_mult *= dca_mult
            vote = vote and dca_vote
            modes["dca"] = dca_reason
            reasons.append(f"DCAProxy: {dca_reason}")

        if self.config.indirect_arb_enabled:
            arb_adj, arb_mult, arb_vote, arb_reason = self._arb_proxy(
                direction=direction,
                funding=funding,
                funding_penalty=funding_penalty,
                spread=spread,
            )
            score_adj += arb_adj
            size_mult *= arb_mult
            vote = vote and arb_vote
            modes["arbitrage"] = arb_reason
            reasons.append(f"ArbProxy: {arb_reason}")

        if self.config.indirect_martingale_inverse_enabled:
            mg_adj, mg_mult, mg_reason = self._anti_martingale_guard(
                drawdown_pct=drawdown_pct,
                open_positions=open_positions,
            )
            score_adj += mg_adj
            size_mult *= mg_mult
            modes["anti_martingale"] = mg_reason
            reasons.append(f"AntiMartingale: {mg_reason}")

        max_boost = max(0.0, self.config.indirect_max_score_boost)
        score_adj = max(-8.0, min(max_boost, score_adj))
        size_mult = max(0.70, min(self.config.indirect_max_size_boost, size_mult))
        reason = " | ".join(reasons) if reasons else "neutral"
        assessment = IndirectStrategyAssessment(vote, score_adj, size_mult, reason, modes)

        action = "boost" if score_adj > 0.5 else "reduce" if score_adj < -0.5 else "neutral"
        return self._publish(symbol, action, assessment, "active")

    def _grid_proxy(self, *, direction: str, choppiness: float, adx: float, bbp: float) -> tuple[float, float, bool, str]:
        range_market = (
            choppiness >= self.config.indirect_grid_min_choppiness
            and adx <= self.config.indirect_grid_max_adx
        )
        if not range_market:
            return 0.0, 1.0, True, f"not range market (CI={choppiness:.1f}, ADX={adx:.1f})"

        aligned_long = direction == "LONG" and bbp <= self.config.indirect_grid_lower_bbp
        aligned_short = direction == "SHORT" and bbp >= self.config.indirect_grid_upper_bbp
        chasing_long = direction == "LONG" and bbp >= self.config.indirect_grid_chase_bbp
        chasing_short = direction == "SHORT" and bbp <= (1.0 - self.config.indirect_grid_chase_bbp)

        if aligned_long or aligned_short:
            return (
                self.config.indirect_grid_score_boost,
                1.03,
                True,
                f"range edge aligned (CI={choppiness:.1f}, BB%={bbp:.2f})",
            )
        if chasing_long or chasing_short:
            return (
                -self.config.indirect_grid_edge_penalty,
                0.86,
                False,
                f"range edge chase blocked (BB%={bbp:.2f})",
            )
        return 0.6, 1.0, True, f"range neutral (CI={choppiness:.1f}, BB%={bbp:.2f})"

    def _dca_proxy(
        self,
        *,
        symbol: str,
        score: float,
        pullback: float,
        open_positions: Dict[str, Any],
    ) -> tuple[float, float, bool, str]:
        if symbol in open_positions:
            return -4.0, 0.75, False, "same symbol already open — no averaging down"
        if pullback >= self.config.indirect_dca_pullback_min_pct and score >= self.config.score_high:
            return (
                self.config.indirect_dca_score_boost,
                1.02,
                True,
                f"staged pullback entry ({pullback:.3%})",
            )
        if pullback < self.config.indirect_dca_pullback_min_pct:
            return -0.8, 0.96, True, f"no staged pullback ({pullback:.3%})"
        return 0.0, 1.0, True, "neutral"

    def _arb_proxy(
        self,
        *,
        direction: str,
        funding: float,
        funding_penalty: float,
        spread: float,
    ) -> tuple[float, float, bool, str]:
        if spread > self.config.max_spread_pct:
            return -2.0, 0.90, False, f"spread too wide ({spread:.3%})"
        if funding_penalty >= 5.0:
            return -2.5, 0.85, False, f"funding penalty high ({funding_penalty:.1f})"

        favorable = (direction == "LONG" and funding < 0) or (direction == "SHORT" and funding > 0)
        if favorable:
            return (
                self.config.indirect_arb_score_boost,
                1.02,
                True,
                f"funding carry favorable ({funding * 100:.3f}%)",
            )
        return 0.2, 1.0, True, f"spread ok, funding neutral ({funding * 100:.3f}%)"

    def _anti_martingale_guard(
        self,
        *,
        drawdown_pct: float,
        open_positions: Dict[str, Any],
    ) -> tuple[float, float, str]:
        if drawdown_pct >= self.config.indirect_martingale_drawdown_cut_pct:
            return -2.0, 0.78, f"drawdown {drawdown_pct:.1%} — cut size"
        if len(open_positions) >= max(1, self.config.hft_max_open_positions - 1):
            return -0.8, 0.92, f"{len(open_positions)} open positions — no loss-chasing"
        return 0.0, 1.0, "loss-chasing disabled"

    def _publish(
        self,
        symbol: str,
        action: str,
        assessment: IndirectStrategyAssessment,
        status: str,
    ) -> IndirectStrategyAssessment:
        if self.monitor:
            self.monitor.report(
                "Indirect",
                action,
                assessment.reason,
                symbol=symbol or None,
                status=status,
                severity="INFO" if assessment.vote else "WARNING",
                force=action in ("boost", "reduce"),
            )
        return assessment

    @staticmethod
    def _float(value: Any, default: float = 0.0) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

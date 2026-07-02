"""
CapitalAllocatorAgent — adaptive sizing vote for high-conviction entries.

This agent does not create trades. It only decides whether an already-approved
candidate deserves normal size, reduced size, or a carefully capped boost.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional

from config import TradingConfig


@dataclass
class CapitalAllocation:
    vote: bool
    size_multiplier: float
    score_adjustment: float
    reason: str


class CapitalAllocatorAgent:
    """Risk-aware capital boost for rare, very strong setups."""

    def __init__(self, config: Optional[TradingConfig] = None, monitor: Optional[Any] = None):
        self.config = config or TradingConfig()
        self.monitor = monitor

    def assess_trade(
        self,
        opportunity: Dict[str, Any],
        *,
        open_positions: Optional[Dict[str, Any]] = None,
        drawdown_pct: float = 0.0,
    ) -> CapitalAllocation:
        symbol = str(opportunity.get("symbol", ""))

        def publish(action: str, decision: CapitalAllocation, status: str = "active") -> CapitalAllocation:
            if self.monitor:
                self.monitor.report(
                    "Capital",
                    action,
                    decision.reason,
                    symbol=symbol,
                    status=status,
                    force=action in ("boost", "reduce"),
                )
            return decision

        if not self.config.capital_allocator_enabled:
            return publish("off", CapitalAllocation(True, 1.0, 0.0, "capital allocator off"), "paused")

        score = float(opportunity.get("score", 0.0) or 0.0)
        funding_penalty = float(opportunity.get("funding_penalty", 0.0) or 0.0)
        positions_count = len(open_positions or {})

        if drawdown_pct > self.config.high_conviction_max_drawdown_pct:
            return publish(
                "reduce",
                CapitalAllocation(
                    True,
                    0.75,
                    -1.0,
                    f"drawdown {drawdown_pct:.1%} — reduce size",
                ),
                "working",
            )
        if positions_count > self.config.capital_allocator_max_open_positions:
            return publish(
                "reserve",
                CapitalAllocation(
                    True,
                    0.85,
                    -0.5,
                    f"{positions_count} open positions — keep powder",
                ),
            )
        if funding_penalty > self.config.capital_allocator_max_funding_penalty:
            return publish(
                "reduce",
                CapitalAllocation(
                    True,
                    0.80,
                    -1.0,
                    f"funding penalty {funding_penalty:.1f}",
                ),
                "working",
            )
        if score < self.config.capital_allocator_min_score:
            return publish(
                "normal",
                CapitalAllocation(
                    True,
                    1.0,
                    0.0,
                    f"normal size: score {score:.1f}",
                ),
            )

        mult = max(1.0, min(2.0, self.config.capital_allocator_size_multiplier))
        return publish(
            "boost",
            CapitalAllocation(
                True,
                mult,
                0.5,
                f"capital boost {mult:.2f}x: score {score:.1f}, funding ok",
            ),
            "working",
        )

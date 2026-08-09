"""
LiveGuardAgent — explicit live-trading safety gate.

This agent does not make market calls. Its job is to prevent accidental real
orders and to keep live-mode exposure inside conservative hard limits.
"""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import asdict, dataclass
from typing import Any, Optional

from config import TradingConfig

logger = logging.getLogger(__name__)

CONFIRMATION_TEXT = "I_ACCEPT_REAL_BINANCE_FUTURES_RISK"
_STATE_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "live_guard.json")


@dataclass
class LiveReadiness:
    ready: bool
    mode: str
    reason: str
    max_leverage: int
    max_margin_fraction: float
    checked_at: float


@dataclass
class LiveTradeCheck:
    approved: bool
    reason: str


class LiveGuardAgent:
    """Startup and per-trade guardrails for real Binance Futures orders."""

    def __init__(self, config: TradingConfig, monitor: Optional[Any] = None):
        self.config = config
        self.monitor = monitor
        self.readiness = self.check_startup()

    def check_startup(self) -> LiveReadiness:
        if self.config.paper_trading:
            state = LiveReadiness(
                ready=True,
                mode="PAPER",
                reason="Paper trading: no real orders",
                max_leverage=self.config.live_max_leverage,
                max_margin_fraction=self.config.live_max_margin_fraction,
                checked_at=time.time(),
            )
            self._publish(state)
            return state

        reasons = []
        if not self.config.live_trading_enabled:
            reasons.append("LIVE_TRADING_ENABLED is not true")
        if self.config.live_trading_confirmation != CONFIRMATION_TEXT:
            reasons.append("LIVE_TRADING_CONFIRMATION is missing or incorrect")
        if self.config.leverage > self.config.live_max_leverage:
            reasons.append(
                f"leverage {self.config.leverage}x > live max {self.config.live_max_leverage}x"
            )
        if self.config.max_margin_fraction > self.config.live_max_margin_fraction:
            reasons.append(
                "max margin fraction exceeds live cap "
                f"({self.config.max_margin_fraction:.2f} > {self.config.live_max_margin_fraction:.2f})"
            )

        ready = not reasons
        state = LiveReadiness(
            ready=ready,
            mode="LIVE",
            reason="Ready for explicitly armed live mode" if ready else "; ".join(reasons),
            max_leverage=self.config.live_max_leverage,
            max_margin_fraction=self.config.live_max_margin_fraction,
            checked_at=time.time(),
        )
        self._publish(state)
        if self.monitor:
            self.monitor.report(
                "LiveGuard",
                "ready" if ready else "locked",
                state.reason,
                status="active" if ready else "stopped",
                severity="INFO" if ready else "ERROR",
                force=True,
            )
        return state

    def require_ready(self) -> None:
        """Raise if real-order mode is not explicitly armed."""
        if not self.readiness.ready:
            raise ValueError(f"Live trading locked: {self.readiness.reason}")

    def pre_trade_check(
        self,
        *,
        symbol: str,
        notional: float,
        required_margin: float,
        live_available: float,
        live_equity: float,
    ) -> LiveTradeCheck:
        if self.config.paper_trading:
            return LiveTradeCheck(True, "paper mode")

        if not self.readiness.ready:
            return LiveTradeCheck(False, self.readiness.reason)
        if live_equity < self.config.live_required_min_equity_usdt:
            return LiveTradeCheck(
                False,
                f"live equity {live_equity:.2f} < required {self.config.live_required_min_equity_usdt:.2f}",
            )
        if required_margin > live_available * 0.90:
            return LiveTradeCheck(
                False,
                f"{symbol}: required margin {required_margin:.2f} > 90% of available {live_available:.2f}",
            )
        if required_margin > live_equity * self.config.live_max_margin_fraction:
            return LiveTradeCheck(
                False,
                f"{symbol}: required margin {required_margin:.2f} exceeds live fraction cap",
            )
        if notional <= 0:
            return LiveTradeCheck(False, f"{symbol}: notional is zero")
        return LiveTradeCheck(True, "live guard approved")

    def _publish(self, state: LiveReadiness) -> None:
        try:
            os.makedirs(os.path.dirname(_STATE_FILE), exist_ok=True)
            with open(_STATE_FILE, "w", encoding="utf-8") as f:
                json.dump(asdict(state), f, ensure_ascii=False, indent=2)
        except Exception as exc:
            logger.debug("live guard state write failed: %s", exc)

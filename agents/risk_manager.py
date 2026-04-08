"""
Risk management: legacy (assess_risk + ExecutionAgent) + aggressive HFT (evaluate + rage).
"""

from __future__ import annotations

import logging
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from agents.market_analysis import MarketData
from agents.strategy import Signal
from config import TradingConfig

logger = logging.getLogger(__name__)


@dataclass
class RiskAssessment:
    symbol: str
    approved: bool
    position_size: float
    sl_price: float
    tp_price: float
    risk_reward_ratio: float
    risk_amount: float
    rejection_reason: str


@dataclass
class RiskDecision:
    approved: bool
    quantity: float
    sl_price: float
    tp_price: float
    reason: str = ""


@dataclass
class Position:
    symbol: str
    side: str
    entry_price: float
    quantity: float
    sl_price: float
    tp_price: float
    opened_at: datetime
    trade_id: Optional[int] = None
    unrealized_pnl: float = 0.0
    peak_price: float = 0.0
    score_at_entry: float = 0.0

    def __post_init__(self) -> None:
        if self.peak_price == 0.0:
            self.peak_price = self.entry_price


class RiskManagerAgent:
    """
    Unified risk: supports classic strategy pipeline and aggressive HFT scoring.
    """

    def __init__(
        self,
        config: Optional[TradingConfig] = None,
        initial_balance: Optional[float] = None,
        session_start_equity: Optional[float] = None,
    ):
        self.config = config or TradingConfig()
        ib = (
            initial_balance
            if initial_balance is not None
            else self.config.paper_initial_balance
        )
        self._current_balance: float = ib
        self.session_start_equity: float = (
            session_start_equity if session_start_equity is not None else ib
        )
        self.peak_balance: float = self.session_start_equity
        self.open_positions: Dict[str, Position] = {}
        self.kill_switch: bool = False
        self._drawdown_pct: float = 0.0

        self._daily_start_equity: float = self.session_start_equity
        self._daily_start_ts: datetime = datetime.now(timezone.utc)

        streak_n = max(3, self.config.rage_streak)
        self._trade_history: deque = deque(maxlen=streak_n * 2)

        # Adaptive score entry from TradeAnalyzer (overridden externally)
        self._adaptive_score_entry: Optional[float] = None
        # Exit reasons that history shows are net-negative (set externally by TradeAnalyzer)
        self._bad_exit_reasons: set = set()
        # Kelly-inspired fraction for position sizing (0.1–1.0, set by TradeAnalyzer)
        self._kelly_fraction: float = 1.0
        # Dynamic SL/TP multipliers from trade history
        self._sl_multiplier: float = 1.0
        self._tp_multiplier: float = 1.0
        # Model health flag — if False, reject all entries
        self._model_healthy: bool = True

    # ------------------------------------------------------------------
    # Legacy pipeline (main.py + ExecutionAgent)
    # ------------------------------------------------------------------

    def should_open_position(
        self,
        signal: Signal,
        open_positions: Dict[str, Any],
        killed: bool,
    ) -> Tuple[bool, str]:
        if killed:
            return False, "Kill switch is active"
        if signal.direction == "NEUTRAL":
            return False, "Signal direction is NEUTRAL"
        max_p = (
            self.config.hft_max_open_positions
            if self.config.aggressive_hft
            else self.config.max_open_positions
        )
        if len(open_positions) >= max_p:
            return False, f"Max open positions reached ({max_p})"
        if signal.symbol in open_positions:
            return False, f"Position already open for {signal.symbol}"
        return True, ""

    def calculate_sl_tp(
        self,
        entry_price: float,
        side: str,
        atr: float,
    ) -> Tuple[float, float]:
        sl_dist = atr * self.config.sl_atr_multiplier
        tp_dist = atr * self.config.tp_atr_multiplier
        if side == "LONG":
            sl_price = entry_price - sl_dist
            tp_price = entry_price + tp_dist
        elif side == "SHORT":
            sl_price = entry_price + sl_dist
            tp_price = entry_price - tp_dist
        else:
            sl_price = entry_price * 0.98
            tp_price = entry_price * 1.03
        # Do not clamp to 0.01 — that breaks SL/TP for sub-$0.05 coins (e.g. TRU).
        # Exchange tick rounding is applied in ExecutionAgent.refine_sl_tp_prices.
        return round(sl_price, 10), round(tp_price, 10)

    def calculate_position_size(
        self,
        balance: float,
        entry_price: float,
        sl_price: float,
    ) -> float:
        if entry_price <= 0 or sl_price <= 0:
            return 0.0
        risk_per_unit = abs(entry_price - sl_price)
        if risk_per_unit < 1e-10:
            return 0.0
        risk_amount = balance * self.config.max_risk_pct
        base_qty = risk_amount / risk_per_unit
        leveraged = base_qty * self.config.leverage
        return max(round(leveraged, 3), 0.0)

    def assess_risk(self, signal: Signal, market_data: MarketData) -> RiskAssessment:
        symbol = signal.symbol
        entry_price = market_data.current_price
        atr = market_data.atr

        can_open, reason = self.should_open_position(
            signal, self.open_positions, self.kill_switch
        )
        if not can_open:
            return RiskAssessment(
                symbol=symbol,
                approved=False,
                position_size=0.0,
                sl_price=0.0,
                tp_price=0.0,
                risk_reward_ratio=0.0,
                risk_amount=0.0,
                rejection_reason=reason,
            )

        side = signal.direction
        sl_price, tp_price = self.calculate_sl_tp(entry_price, side, atr)
        position_size = self.calculate_position_size(
            self._current_balance, entry_price, sl_price
        )

        if position_size <= 0:
            return RiskAssessment(
                symbol=symbol,
                approved=False,
                position_size=0.0,
                sl_price=sl_price,
                tp_price=tp_price,
                risk_reward_ratio=0.0,
                risk_amount=0.0,
                rejection_reason="Position size is zero",
            )

        risk_amount = self._current_balance * self.config.max_risk_pct
        sl_d = abs(entry_price - sl_price)
        tp_d = abs(tp_price - entry_price)
        rr = tp_d / sl_d if sl_d > 0 else 0.0

        if rr < 1.0:
            return RiskAssessment(
                symbol=symbol,
                approved=False,
                position_size=position_size,
                sl_price=sl_price,
                tp_price=tp_price,
                risk_reward_ratio=round(rr, 3),
                risk_amount=round(risk_amount, 4),
                rejection_reason=f"Risk:Reward too low ({rr:.2f} < 1.0)",
            )

        return RiskAssessment(
            symbol=symbol,
            approved=True,
            position_size=position_size,
            sl_price=sl_price,
            tp_price=tp_price,
            risk_reward_ratio=round(rr, 3),
            risk_amount=round(risk_amount, 4),
            rejection_reason="",
        )

    def update_trailing_stop(self, position: Position, current_price: float) -> float:
        trailing_pct = (
            self.config.hft_trailing_pct
            if self.config.aggressive_hft
            else self.config.trailing_stop_pct
        )

        # Adaptive trailing: tighten trail as profit grows
        # If position is up > 2x the trailing %, use half the trailing distance
        # This locks in profit on good trades faster
        if position.side == "LONG":
            profit_pct = (current_price - position.entry_price) / position.entry_price if position.entry_price > 0 else 0
        else:
            profit_pct = (position.entry_price - current_price) / position.entry_price if position.entry_price > 0 else 0

        if profit_pct > trailing_pct * 2:
            trailing_pct *= 0.5  # tighten trailing when well in profit

        if position.side == "LONG":
            if current_price > position.peak_price:
                position.peak_price = current_price
            new_sl = position.peak_price * (1.0 - trailing_pct)
            if new_sl > position.sl_price:
                position.sl_price = new_sl
        elif position.side == "SHORT":
            if current_price < position.peak_price or position.peak_price == position.entry_price:
                position.peak_price = current_price
            new_sl = position.peak_price * (1.0 + trailing_pct)
            if new_sl < position.sl_price:
                position.sl_price = new_sl
        return position.sl_price

    def is_sl_hit(self, position: Position, current_price: float) -> bool:
        if position.side == "LONG":
            return current_price <= position.sl_price
        if position.side == "SHORT":
            return current_price >= position.sl_price
        return False

    def is_tp_hit(self, position: Position, current_price: float) -> bool:
        if position.side == "LONG":
            return current_price >= position.tp_price
        if position.side == "SHORT":
            return current_price <= position.tp_price
        return False

    def register_open_position(self, position: Position) -> None:
        self.open_positions[position.symbol] = position

    def remove_position(self, symbol: str) -> None:
        self.open_positions.pop(symbol, None)

    def update_balance(self, new_balance: float) -> None:
        self._current_balance = new_balance
        if new_balance > self.peak_balance:
            self.peak_balance = new_balance

    def sync_live_equity(self, equity: float, available_balance: float) -> None:
        self._current_balance = available_balance
        if equity > self.peak_balance:
            self.peak_balance = equity

    def check_drawdown(self, current_equity: float) -> Tuple[bool, float]:
        if current_equity > self.peak_balance:
            self.peak_balance = current_equity
        if self.peak_balance > 0:
            dd = (self.peak_balance - current_equity) / self.peak_balance
        else:
            dd = 0.0
        self._drawdown_pct = max(dd, 0.0)

        now = datetime.now(timezone.utc)
        if (now - self._daily_start_ts).total_seconds() > 86400:
            self._daily_start_equity = current_equity
            self._daily_start_ts = now

        daily_dd = (
            (self._daily_start_equity - current_equity) / self._daily_start_equity
            if self._daily_start_equity > 0
            else 0.0
        )
        if daily_dd >= self.config.daily_max_drawdown_pct:
            self.kill_switch = True
            logger.critical(
                "KILL: daily drawdown %.2f%% >= %.2f%%",
                daily_dd * 100,
                self.config.daily_max_drawdown_pct * 100,
            )

        if self._drawdown_pct >= self.config.max_drawdown_pct:
            self.kill_switch = True
            logger.critical(
                "KILL: session drawdown %.2f%% >= %.2f%%",
                self._drawdown_pct * 100,
                self.config.max_drawdown_pct * 100,
            )

        return self.kill_switch, round(self._drawdown_pct, 6)

    @property
    def current_balance(self) -> float:
        return self._current_balance

    @current_balance.setter
    def current_balance(self, v: float) -> None:
        self._current_balance = v

    @property
    def drawdown_pct(self) -> float:
        return self._drawdown_pct

    # ------------------------------------------------------------------
    # Aggressive HFT
    # ------------------------------------------------------------------

    def get_rage_multiplier(self) -> float:
        """
        Adaptive position sizing based on recent trade streak.
        SAFETY: win streaks do NOT increase size (overconfidence trap).
        Loss streaks reduce size to protect capital.
        """
        n = self.config.rage_streak
        if len(self._trade_history) < n:
            return 1.0
        recent = list(self._trade_history)[-n:]
        # Win streak: stay at 1.0 — do NOT increase (learned from losses)
        # Loss streak: reduce size to protect capital
        if not any(recent):
            return self.config.rage_loss_mult
        return 1.0

    def record_trade_result(self, pnl: float) -> None:
        self._trade_history.append(pnl > 0)

    def evaluate(
        self,
        symbol: str,
        score: float,
        direction: str,
        entry_price: float,
        atr: float,
        current_balance: float,
        open_positions: Dict[str, Position],
    ) -> RiskDecision:
        if self.kill_switch:
            return RiskDecision(False, 0.0, 0.0, 0.0, "Kill switch")
        if not self._model_healthy:
            return RiskDecision(False, 0.0, 0.0, 0.0, "Model unhealthy — predictions unreliable")
        if len(open_positions) >= self.config.hft_max_open_positions:
            return RiskDecision(False, 0.0, 0.0, 0.0, "Max positions")
        if symbol in open_positions:
            return RiskDecision(False, 0.0, 0.0, 0.0, "Symbol occupied")

        # Use adaptive threshold from TradeAnalyzer if available
        effective_threshold = self._adaptive_score_entry if self._adaptive_score_entry is not None else self.config.score_entry
        if score < effective_threshold:
            return RiskDecision(
                False, 0.0, 0.0, 0.0, f"Score {score:.1f} < {effective_threshold}"
            )

        if score >= self.config.score_extreme:
            tier_pct = self.config.size_extreme_pct
            tier = "EXTREME"
        elif score >= self.config.score_high:
            tier_pct = self.config.size_high_pct
            tier = "HIGH"
        else:
            tier_pct = self.config.size_base_pct
            tier = "BASE"

        # Portfolio sizing: divide balance equally among max open positions
        max_pos = max(1, self.config.hft_max_open_positions)
        slice_margin = current_balance / max_pos  # equal share per position
        adj_pct = min(
            tier_pct * self.get_rage_multiplier(),
            self.config.size_extreme_pct,
        )
        # Notional = slice × leverage, scaled by tier (extreme gets full slice, base gets less)
        notional = slice_margin * adj_pct * self.config.leverage
        # Apply Kelly fraction — reduce sizing when win rate / R:R is poor
        notional *= self._kelly_fraction
        # Hard-cap: never exceed one full slice × leverage
        max_notional = slice_margin * self.config.leverage
        notional = min(notional, max_notional)

        # Minimum notional (USDT position size) — avoids tiny “penny” trades; still respects cap above.
        min_n = float(self.config.hft_min_notional_usdt or 0.0)
        if min_n > 0 and max_notional > 0:
            if max_notional < min_n - 1e-9:
                return RiskDecision(
                    False,
                    0.0,
                    0.0,
                    0.0,
                    (
                        f"Max notional {max_notional:.2f} USDT < HFT_MIN_NOTIONAL_USDT "
                        f"({min_n:.2f}) — increase balance or raise max_margin / leverage"
                    ),
                )
            notional = max(notional, min(min_n, max_notional))
        notional = min(notional, max_notional)

        qty = notional / entry_price if entry_price > 0 else 0.0

        atr_pct = atr / entry_price if entry_price > 0 else 0.005
        tw = {"BASE": 0.85, "HIGH": 1.0, "EXTREME": 1.15}.get(tier, 1.0)
        scaled = atr_pct * tw
        # Apply dynamic SL/TP multipliers from trade history analysis
        sl_pct = max(self.config.sl_min_pct, min(self.config.sl_max_pct, scaled * self._sl_multiplier))
        tp_pct = max(self.config.tp_min_pct, min(self.config.tp_max_pct, scaled * 1.4 * self._tp_multiplier))

        if direction == "LONG":
            sl_price = entry_price * (1 - sl_pct)
            tp_price = entry_price * (1 + tp_pct)
        else:
            sl_price = entry_price * (1 + sl_pct)
            tp_price = entry_price * (1 - tp_pct)

        logger.info(
            "HFT approve %s %s score=%.1f tier=%s qty=%.6f notional≈%.2f USDT margin≈%.2f USDT SL%%=%.3f TP%%=%.3f",
            symbol,
            direction,
            score,
            tier,
            qty,
            notional,
            notional / self.config.leverage if self.config.leverage else 0.0,
            sl_pct * 100,
            tp_pct * 100,
        )
        return RiskDecision(True, qty, sl_price, tp_price, f"{tier} score={score:.1f}")

    def check_exits(
        self,
        positions: Dict[str, Position],
        prices: Dict[str, float],
    ) -> List[Dict[str, str]]:
        exits: List[Dict[str, str]] = []
        now = datetime.now(timezone.utc)
        for sym, pos in positions.items():
            px = prices.get(sym)
            if px is None:
                continue

            # Update trailing stop
            self.update_trailing_stop(pos, px)

            if self.is_sl_hit(pos, px):
                exits.append({"symbol": sym, "reason": "stop_loss"})
                continue
            if self.is_tp_hit(pos, px):
                exits.append({"symbol": sym, "reason": "take_profit"})
                continue

            age = (now - pos.opened_at).total_seconds()

            # ── Fast exit: no movement in 30-45 seconds ──
            # Skip if trade history shows this exit type loses money
            if "fast_exit_no_move" not in self._bad_exit_reasons:
                fast_sec = self.config.fast_exit_seconds
                if fast_sec > 0 and age >= fast_sec:
                    if pos.side == "LONG":
                        move = (px - pos.entry_price) / pos.entry_price
                    else:
                        move = (pos.entry_price - px) / pos.entry_price
                    if move < self.config.min_favorable_move_pct:
                        exits.append({"symbol": sym, "reason": "fast_exit_no_move"})
                        continue

            # ── Opposite pressure: exit if trade reverses from peak profit ──
            # Skip if trade history shows this exit type loses money
            if "opposite_pressure" not in self._bad_exit_reasons:
                opp_pct = self.config.opposite_pressure_pct
                if opp_pct > 0 and pos.peak_price != pos.entry_price:
                    if pos.side == "LONG":
                        peak_profit = (pos.peak_price - pos.entry_price) / pos.entry_price
                        current_from_peak = (pos.peak_price - px) / pos.peak_price
                        if peak_profit > opp_pct and current_from_peak > opp_pct:
                            exits.append({"symbol": sym, "reason": "opposite_pressure"})
                            continue
                    elif pos.side == "SHORT":
                        peak_profit = (pos.entry_price - pos.peak_price) / pos.entry_price
                        current_from_peak = (px - pos.peak_price) / pos.peak_price if pos.peak_price > 0 else 0
                        if peak_profit > opp_pct and current_from_peak > opp_pct:
                            exits.append({"symbol": sym, "reason": "opposite_pressure"})
                            continue

            # ── Original stale exit (longer timeframe fallback) ──
            # Skip if trade history shows this exit type loses money
            if "stale_no_move" not in self._bad_exit_reasons:
                se = self.config.stale_exit_seconds
                if se > 0 and age >= se:
                    if pos.side == "LONG":
                        move = (px - pos.entry_price) / pos.entry_price
                    else:
                        move = (pos.entry_price - px) / pos.entry_price
                    if move < self.config.min_favorable_move_pct:
                        exits.append({"symbol": sym, "reason": "stale_no_move"})

        return exits

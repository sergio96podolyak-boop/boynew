"""
Trade Analyzer — learns from past trades and feeds insights back into the trading pipeline.

Responsibilities:
  1. Blacklist symbols that consistently lose money
  2. Adapt score entry threshold based on real win rate
  3. Per-symbol score adjustments (bonus for winners, penalty for losers)
  4. Detect which close reasons are profitable vs destructive
  5. Time-of-day performance patterns
  6. Provide actionable insights to scanner + risk manager

Refreshed every N loops (default 50) — not every tick, to keep DB load low.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Set, Optional

from database.repository import TradeRepository

logger = logging.getLogger(__name__)


@dataclass
class TradeInsights:
    """Actionable insights computed from trade history."""

    # Symbols to avoid (win_rate < threshold after N trades)
    symbol_blacklist: Set[str] = field(default_factory=set)

    # Per-symbol score adjustment: {symbol: delta} (e.g. +5 for winners, -10 for losers)
    symbol_score_adj: Dict[str, float] = field(default_factory=dict)

    # Adjusted minimum score for entry (raised when overall win_rate is low)
    adjusted_score_entry: float = 72.0

    # Close reasons that are net negative (e.g. "fast_exit_no_move" loses money)
    bad_close_reasons: Set[str] = field(default_factory=set)

    # Overall recent stats
    recent_win_rate: float = 0.0
    recent_total_pnl: float = 0.0
    recent_trade_count: int = 0

    # Whether we have enough data to act on
    has_enough_data: bool = False


class TradeAnalyzer:
    """
    Queries trade history from DB and produces actionable TradeInsights.
    Designed to be called periodically (every ~50 loops), not every tick.
    """

    def __init__(
        self,
        repo: TradeRepository,
        base_score_entry: float = 72.0,
        min_trades_for_symbol_action: int = 5,
        symbol_blacklist_win_rate: float = 0.30,
        min_trades_overall: int = 10,
        lookback_hours: int = 48,
    ):
        self.repo = repo
        self.base_score_entry = base_score_entry
        self.min_trades_for_symbol_action = min_trades_for_symbol_action
        self.symbol_blacklist_win_rate = symbol_blacklist_win_rate
        self.min_trades_overall = min_trades_overall
        self.lookback_hours = lookback_hours

        self._insights = TradeInsights(adjusted_score_entry=base_score_entry)
        self._refresh_count = 0

    @property
    def insights(self) -> TradeInsights:
        return self._insights

    def refresh(self) -> TradeInsights:
        """
        Re-analyze trade history and update insights. Call every ~50 loops.
        """
        self._refresh_count += 1

        try:
            # 1. Overall recent performance
            overall = self.repo.get_overall_recent_stats(hours_back=self.lookback_hours)
            total_trades = overall.get("total_trades", 0) or 0

            ins = TradeInsights(adjusted_score_entry=self.base_score_entry)
            ins.recent_trade_count = total_trades
            ins.recent_win_rate = overall.get("win_rate", 0) or 0
            ins.recent_total_pnl = overall.get("total_pnl", 0) or 0
            ins.has_enough_data = total_trades >= self.min_trades_overall

            if not ins.has_enough_data:
                logger.info(
                    "TradeAnalyzer: only %d trades in last %dh (need %d) — using defaults",
                    total_trades, self.lookback_hours, self.min_trades_overall,
                )
                self._insights = ins
                return ins

            # 2. Adaptive score threshold based on win rate
            #    If win rate < 45%: raise threshold significantly
            #    If win rate < 50%: raise threshold moderately
            #    If win rate > 55%: can relax threshold slightly
            wr = ins.recent_win_rate
            if wr < 0.35:
                ins.adjusted_score_entry = min(95.0, self.base_score_entry + 15)
                logger.warning(
                    "TradeAnalyzer: win_rate=%.1f%% — VERY LOW, raising score to %.0f",
                    wr * 100, ins.adjusted_score_entry,
                )
            elif wr < 0.45:
                ins.adjusted_score_entry = min(92.0, self.base_score_entry + 10)
                logger.warning(
                    "TradeAnalyzer: win_rate=%.1f%% — LOW, raising score to %.0f",
                    wr * 100, ins.adjusted_score_entry,
                )
            elif wr < 0.50:
                ins.adjusted_score_entry = min(88.0, self.base_score_entry + 5)
                logger.info(
                    "TradeAnalyzer: win_rate=%.1f%% — below target, score raised to %.0f",
                    wr * 100, ins.adjusted_score_entry,
                )
            elif wr > 0.60 and total_trades >= 20:
                # Only relax if we have strong evidence
                ins.adjusted_score_entry = max(65.0, self.base_score_entry - 3)
                logger.info(
                    "TradeAnalyzer: win_rate=%.1f%% — GOOD, score relaxed to %.0f",
                    wr * 100, ins.adjusted_score_entry,
                )
            else:
                ins.adjusted_score_entry = self.base_score_entry

            # 3. Per-symbol analysis: blacklist + score adjustments
            symbol_stats = self.repo.get_symbol_stats(
                min_trades=self.min_trades_for_symbol_action,
                hours_back=self.lookback_hours,
            )
            for ss in symbol_stats:
                sym = ss["symbol"]
                sym_wr = ss.get("win_rate", 0) or 0
                sym_trades = ss.get("trades", 0) or 0
                sym_pnl = ss.get("total_pnl", 0) or 0

                # Blacklist: consistent losers
                if sym_wr <= self.symbol_blacklist_win_rate and sym_trades >= self.min_trades_for_symbol_action:
                    ins.symbol_blacklist.add(sym)
                    logger.warning(
                        "TradeAnalyzer: BLACKLISTING %s (win_rate=%.0f%%, trades=%d, pnl=%.4f)",
                        sym, sym_wr * 100, sym_trades, sym_pnl,
                    )

                # Score adjustment based on historical performance
                # Winners get a small bonus, losers get penalized
                if sym_trades >= self.min_trades_for_symbol_action:
                    if sym_wr >= 0.60 and sym_pnl > 0:
                        ins.symbol_score_adj[sym] = 3.0  # bonus
                    elif sym_wr >= 0.50 and sym_pnl > 0:
                        ins.symbol_score_adj[sym] = 1.0
                    elif sym_wr < 0.40:
                        ins.symbol_score_adj[sym] = -5.0  # penalty (makes threshold harder)
                    elif sym_wr < 0.45:
                        ins.symbol_score_adj[sym] = -3.0

            # 4. Close reason analysis — find which exit types lose money
            reason_stats = self.repo.get_close_reason_stats(hours_back=self.lookback_hours)
            for rs in reason_stats:
                reason = rs.get("close_reason", "")
                reason_pnl = rs.get("total_pnl", 0) or 0
                reason_trades = rs.get("trades", 0) or 0
                reason_wr = rs.get("win_rate", 0) or 0

                if reason and reason_trades >= 5 and reason_wr < 0.30:
                    ins.bad_close_reasons.add(reason)
                    logger.warning(
                        "TradeAnalyzer: exit reason '%s' is net NEGATIVE (wr=%.0f%%, pnl=%.4f, n=%d)",
                        reason, reason_wr * 100, reason_pnl, reason_trades,
                    )

            # 5. Score bracket analysis — log for tuning
            if self._refresh_count % 5 == 1:  # Don't spam logs
                bracket_stats = self.repo.get_score_bracket_stats(hours_back=self.lookback_hours)
                for bs in bracket_stats:
                    bracket = bs.get("score_bracket", "?")
                    b_wr = bs.get("win_rate", 0) or 0
                    b_pnl = bs.get("total_pnl", 0) or 0
                    b_n = bs.get("trades", 0) or 0
                    logger.info(
                        "TradeAnalyzer bracket [%s]: wr=%.0f%% pnl=%.4f n=%d",
                        bracket, b_wr * 100, b_pnl, b_n,
                    )

            # Summary log
            logger.info(
                "TradeAnalyzer refresh #%d: %d trades, wr=%.1f%%, pnl=%.4f, "
                "score_entry=%.0f, blacklist=%d symbols, adjustments=%d symbols",
                self._refresh_count,
                total_trades,
                ins.recent_win_rate * 100,
                ins.recent_total_pnl,
                ins.adjusted_score_entry,
                len(ins.symbol_blacklist),
                len(ins.symbol_score_adj),
            )

            self._insights = ins
            return ins

        except Exception as e:
            logger.error("TradeAnalyzer refresh failed: %s", e, exc_info=True)
            return self._insights

    def should_skip_symbol(self, symbol: str) -> bool:
        """Check if a symbol is blacklisted by trade history."""
        return symbol in self._insights.symbol_blacklist

    def get_score_adjustment(self, symbol: str) -> float:
        """Get per-symbol score adjustment (positive = bonus, negative = penalty)."""
        return self._insights.symbol_score_adj.get(symbol, 0.0)

    def get_effective_score_entry(self) -> float:
        """Get the adaptive score entry threshold."""
        return self._insights.adjusted_score_entry

    def is_bad_exit_reason(self, reason: str) -> bool:
        """Check if an exit reason is historically net-negative."""
        return reason in self._insights.bad_close_reasons

"""
Trade Analyzer — the brain that learns from past trades and makes the bot smarter.

Layer 1 (v1 - exists): Symbol blacklist, adaptive score, per-symbol adjustments, bad exit reasons
Layer 2 (v2 - NEW):
  - Smart cooldown after consecutive losses (pause trading, don't just reduce size)
  - Correlation guard (don't open 2 correlated pairs simultaneously)
  - Time-of-day filter (learn which hours are profitable)
  - Dynamic SL/TP from actual hit rates
  - Model accuracy tracking (stop trading if ML is broken)
  - Kelly-inspired position sizing from real win rate + avg win/loss
  - Regime awareness (trending vs ranging performance)

Refreshed every N loops (default 50) — not every tick, to keep DB load low.
"""

from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, Set, Optional, Tuple

from database.repository import TradeRepository

logger = logging.getLogger(__name__)

# Pairs known to be highly correlated in crypto
_CORRELATION_GROUPS = [
    {"BTCUSDT", "BTCDOMUSDT"},
    {"ETHUSDT", "ETHFIUSDT"},
    {"SOLUSDT", "SOLOUSDT"},
    {"DOGEUSDT", "SHIBUSDT", "FLOKIUSDT", "PEPEUSDT", "BONKUSDT"},  # memecoins
    {"APTUSDT", "SUIUSDT"},  # move-based L1s
    {"OPUSDT", "ARBUSDT"},  # L2 rollups
    {"AVAXUSDT", "NEARUSDT"},  # alt L1s
    {"LINKUSDT", "BANDUSDT"},  # oracles
    {"AAVEUSDT", "COMPUSDT", "MKRUSDT"},  # DeFi blue chips
    {"FILUSDT", "ARUSDT"},  # storage
    {"LTCUSDT", "BCHUSDT"},  # BTC forks
]


@dataclass
class TradeInsights:
    """Actionable insights computed from trade history."""

    # === Layer 1 (v1) ===
    symbol_blacklist: Set[str] = field(default_factory=set)
    symbol_score_adj: Dict[str, float] = field(default_factory=dict)
    adjusted_score_entry: float = 72.0
    bad_close_reasons: Set[str] = field(default_factory=set)
    recent_win_rate: float = 0.0
    recent_total_pnl: float = 0.0
    recent_trade_count: int = 0
    has_enough_data: bool = False

    # === Layer 2 (v2 - NEW) ===

    # Smart cooldown: if True, bot should pause entries (not exits)
    cooldown_active: bool = False
    cooldown_reason: str = ""
    cooldown_until: float = 0.0  # timestamp

    # Time-of-day: hours (UTC) that are historically bad
    bad_hours_utc: Set[int] = field(default_factory=set)
    good_hours_utc: Set[int] = field(default_factory=set)

    # Dynamic SL/TP multipliers (1.0 = no change from config)
    sl_multiplier: float = 1.0
    tp_multiplier: float = 1.0

    # Kelly-inspired sizing fraction (0.0 = don't trade, 1.0 = full size)
    kelly_fraction: float = 1.0

    # Performance escalator: earned aggression. >1 only after the recent
    # window PROVES a positive edge (profit factor); <1 when it's negative.
    performance_size_multiplier: float = 1.0

    # Model health: if False, ML predictions are unreliable
    model_healthy: bool = True

    # Per-direction stats
    long_win_rate: float = 0.5
    short_win_rate: float = 0.5
    preferred_direction: str = ""  # "LONG", "SHORT", or "" (no preference)


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
        self._consecutive_losses = 0
        self._last_loss_ts: float = 0.0
        self.cooldown_enabled = os.getenv("SMART_COOLDOWN_ENABLED", "true").lower() in {
            "1",
            "true",
            "yes",
            "on",
        }
        # Blacklist a symbol whose cumulative loss is deep even when its win
        # rate looks fine — a 50% wr symbol can still bleed via oversized losses.
        self.symbol_blacklist_max_loss = float(
            os.getenv("SYMBOL_BLACKLIST_MAX_LOSS_USDT", "2.0")
        )
        self.cooldown_loss_threshold = int(os.getenv("COOLDOWN_LOSS_THRESHOLD", "3"))
        self.cooldown_minutes = float(os.getenv("COOLDOWN_MINUTES", "3"))
        self.severe_cooldown_loss_threshold = int(os.getenv("SEVERE_COOLDOWN_LOSS_THRESHOLD", "5"))
        self.severe_cooldown_minutes = float(os.getenv("SEVERE_COOLDOWN_MINUTES", "10"))
        self.kelly_enabled = os.getenv("KELLY_SIZING_ENABLED", "true").lower() in {
            "1",
            "true",
            "yes",
            "on",
        }
        # Performance escalator: size follows PROVEN recent results, checked on
        # every analyzer refresh — no calendar waiting, no manual toggling.
        self.perf_escalator_enabled = os.getenv(
            "PERF_ESCALATOR_ENABLED", "true"
        ).lower() in {"1", "true", "yes", "on"}
        self.perf_escalator_hours = float(os.getenv("PERF_ESCALATOR_HOURS", "24"))
        self.perf_escalator_min_trades = int(os.getenv("PERF_ESCALATOR_MIN_TRADES", "20"))

    @property
    def insights(self) -> TradeInsights:
        return self._insights

    def record_realtime_result(self, pnl: float) -> None:
        """
        Called immediately after each trade close (not just on refresh).
        Enables real-time cooldown without waiting for DB refresh.
        """
        if pnl <= 0:
            self._consecutive_losses += 1
            self._last_loss_ts = time.time()
            if not self.cooldown_enabled:
                return
            if (
                self.severe_cooldown_loss_threshold > 0
                and self._consecutive_losses >= self.severe_cooldown_loss_threshold
            ):
                cooldown_minutes = self.severe_cooldown_minutes
                self._insights.cooldown_active = True
                self._insights.cooldown_until = time.time() + cooldown_minutes * 60
                self._insights.cooldown_reason = (
                    f"{self._consecutive_losses} consecutive losses — cooling down {cooldown_minutes}min"
                )
                logger.warning(
                    "COOLDOWN ACTIVATED: %s", self._insights.cooldown_reason
                )
            elif (
                self.cooldown_loss_threshold > 0
                and self._consecutive_losses >= self.cooldown_loss_threshold
            ):
                cooldown_minutes = self.cooldown_minutes
                self._insights.cooldown_active = True
                self._insights.cooldown_until = time.time() + cooldown_minutes * 60
                self._insights.cooldown_reason = (
                    f"{self._consecutive_losses} consecutive losses — cooling down {cooldown_minutes}min"
                )
                logger.warning(
                    "COOLDOWN ACTIVATED: %s", self._insights.cooldown_reason
                )
        else:
            self._consecutive_losses = 0
            # Deactivate cooldown on a win
            if self._insights.cooldown_active:
                self._insights.cooldown_active = False
                self._insights.cooldown_reason = ""
                logger.info("Cooldown deactivated (winning trade)")

    def is_in_cooldown(self) -> bool:
        """Check if cooldown is active (real-time, called every loop)."""
        if not self._insights.cooldown_active:
            return False
        if time.time() >= self._insights.cooldown_until:
            self._insights.cooldown_active = False
            self._insights.cooldown_reason = ""
            logger.info("Cooldown expired — resuming trading")
            return False
        return True

    def check_correlation(self, symbol: str, open_positions: Dict[str, any]) -> Optional[str]:
        """
        Check if opening `symbol` would create a correlated-pair risk.
        Returns the conflicting symbol name, or None if safe.
        """
        if not open_positions:
            return None
        for group in _CORRELATION_GROUPS:
            if symbol in group:
                for open_sym in open_positions:
                    if open_sym in group and open_sym != symbol:
                        return open_sym
        return None

    def is_bad_hour(self) -> bool:
        """Check if current UTC hour is historically bad for trading."""
        current_hour = datetime.now(timezone.utc).hour
        return current_hour in self._insights.bad_hours_utc

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

            # Preserve real-time cooldown state across refreshes
            ins.cooldown_active = self._insights.cooldown_active
            ins.cooldown_until = self._insights.cooldown_until
            ins.cooldown_reason = self._insights.cooldown_reason

            if not ins.has_enough_data:
                logger.info(
                    "TradeAnalyzer: only %d trades in last %dh (need %d) — using defaults",
                    total_trades, self.lookback_hours, self.min_trades_overall,
                )
                self._insights = ins
                return ins

            # 2. Adaptive score threshold based on win rate
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
                ins.adjusted_score_entry = max(65.0, self.base_score_entry - 3)
                logger.info(
                    "TradeAnalyzer: win_rate=%.1f%% — GOOD, score relaxed to %.0f",
                    wr * 100, ins.adjusted_score_entry,
                )
            else:
                ins.adjusted_score_entry = self.base_score_entry

            # 3. Per-symbol analysis: blacklist + score adjustments
            symbol_stats = self.repo.get_symbol_stats(
                min_trades=min(3, self.min_trades_for_symbol_action),
                hours_back=self.lookback_hours,
            )
            for ss in symbol_stats:
                sym = ss["symbol"]
                sym_wr = ss.get("win_rate", 0) or 0
                sym_trades = ss.get("trades", 0) or 0
                sym_pnl = ss.get("total_pnl", 0) or 0

                if sym_wr <= self.symbol_blacklist_win_rate and sym_trades >= self.min_trades_for_symbol_action:
                    ins.symbol_blacklist.add(sym)
                    logger.warning(
                        "TradeAnalyzer: BLACKLISTING %s (win_rate=%.0f%%, trades=%d, pnl=%.4f)",
                        sym, sym_wr * 100, sym_trades, sym_pnl,
                    )
                elif (
                    self.symbol_blacklist_max_loss > 0
                    and sym_pnl <= -self.symbol_blacklist_max_loss
                    and sym_trades >= 3
                ):
                    ins.symbol_blacklist.add(sym)
                    logger.warning(
                        "TradeAnalyzer: BLACKLISTING %s by cumulative loss "
                        "(pnl=%.2f <= -%.2f, trades=%d, win_rate=%.0f%%)",
                        sym, sym_pnl, self.symbol_blacklist_max_loss,
                        sym_trades, sym_wr * 100,
                    )

                if sym_trades >= self.min_trades_for_symbol_action:
                    if sym_wr >= 0.60 and sym_pnl > 0:
                        ins.symbol_score_adj[sym] = 3.0
                    elif sym_wr >= 0.50 and sym_pnl > 0:
                        ins.symbol_score_adj[sym] = 1.0
                    elif sym_wr < 0.40:
                        ins.symbol_score_adj[sym] = -5.0
                    elif sym_wr < 0.45:
                        ins.symbol_score_adj[sym] = -3.0

            # 4. Close reason analysis
            reason_stats = self.repo.get_close_reason_stats(hours_back=self.lookback_hours)
            for rs in reason_stats:
                reason = rs.get("close_reason", "")
                reason_trades = rs.get("trades", 0) or 0
                reason_wr = rs.get("win_rate", 0) or 0

                if reason and reason_trades >= 5 and reason_wr < 0.30:
                    ins.bad_close_reasons.add(reason)
                    logger.warning(
                        "TradeAnalyzer: exit reason '%s' is net NEGATIVE (wr=%.0f%%, n=%d)",
                        reason, reason_wr * 100, reason_trades,
                    )

            # 5. Dynamic SL/TP from close reason hit rates
            self._compute_dynamic_sl_tp(ins, reason_stats)

            # 6. Kelly-inspired position sizing
            self._compute_kelly_fraction(ins, overall)

            # 6b. Performance escalator — earned aggression
            self._compute_performance_multiplier(ins)

            # 7. Time-of-day analysis
            self._compute_hour_stats(ins)

            # 8. Per-direction analysis (LONG vs SHORT performance)
            self._compute_direction_stats(ins)

            # 9. Model health check
            self._check_model_health(ins)

            # 10. Score bracket analysis (log for tuning)
            if self._refresh_count % 5 == 1:
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
                "score=%.0f, blacklist=%d, kelly=%.2f, sl_mult=%.2f, tp_mult=%.2f, "
                "bad_hours=%s, pref_dir=%s",
                self._refresh_count, total_trades, ins.recent_win_rate * 100,
                ins.recent_total_pnl, ins.adjusted_score_entry,
                len(ins.symbol_blacklist), ins.kelly_fraction,
                ins.sl_multiplier, ins.tp_multiplier,
                sorted(ins.bad_hours_utc) if ins.bad_hours_utc else "none",
                ins.preferred_direction or "none",
            )

            self._insights = ins
            return ins

        except Exception as e:
            logger.error("TradeAnalyzer refresh failed: %s", e, exc_info=True)
            return self._insights

    # ------------------------------------------------------------------
    # Layer 2 analytics
    # ------------------------------------------------------------------

    def _compute_dynamic_sl_tp(self, ins: TradeInsights, reason_stats: List[Dict]) -> None:
        """
        Adjust SL/TP multipliers based on which close types actually make money.

        Logic:
        - If stop_loss hits too often → SL is too tight → widen (multiplier > 1)
        - If take_profit rarely hits → TP is too ambitious → tighten (multiplier < 1)
        - If stop_loss has decent win_rate → SL is well calibrated → keep
        """
        # An exit recorded through exchange reconcile (e.g.
        # stop_loss_exchange_reconcile) is the same outcome as its in-loop
        # twin, and profit_lock/profit_take/scalp exits ARE captured profit —
        # counting only the bare reasons made TP look like it "never hits"
        # (because profit_lock fires first) and shrank winners further.
        def _exits(prefixes: tuple) -> int:
            return sum(
                (rs.get("trades", 0) or 0)
                for rs in reason_stats
                if any(str(rs.get("close_reason") or "").startswith(p) for p in prefixes)
            )

        sl_trades = _exits(("stop_loss",))
        tp_trades = _exits(("take_profit", "scalp_take_profit", "profit_lock", "profit_take"))

        total_exits = sum((rs.get("trades", 0) or 0) for rs in reason_stats)
        if total_exits < 10:
            return  # Not enough data

        # SL analysis: if SL hits > 50% of exits, it's too tight
        if sl_trades:
            sl_pct_of_exits = sl_trades / max(total_exits, 1)
            if sl_pct_of_exits > 0.50:
                ins.sl_multiplier = 1.3  # widen SL by 30%
                logger.info("TradeAnalyzer: SL too tight (%.0f%% of exits) → widening 30%%", sl_pct_of_exits * 100)
            elif sl_pct_of_exits > 0.40:
                ins.sl_multiplier = 1.15  # widen SL by 15%
            elif sl_pct_of_exits < 0.15:
                ins.sl_multiplier = 0.9  # tighten SL — rarely hits, can be closer
                logger.info("TradeAnalyzer: SL rarely hits (%.0f%%) → tightening 10%%", sl_pct_of_exits * 100)

        # TP analysis: if profit capture (any form) rarely happens, TP is too ambitious
        if tp_trades:
            tp_pct_of_exits = tp_trades / max(total_exits, 1)
            if tp_pct_of_exits < 0.15:
                ins.tp_multiplier = 0.7  # tighten TP — take profits earlier
                logger.info("TradeAnalyzer: TP too ambitious (only %.0f%% hit) → tightening 30%%", tp_pct_of_exits * 100)
            elif tp_pct_of_exits < 0.25:
                ins.tp_multiplier = 0.85  # slightly tighter
            elif tp_pct_of_exits > 0.50:
                ins.tp_multiplier = 1.2  # TP hitting easily, can be more ambitious
                logger.info("TradeAnalyzer: TP hits often (%.0f%%) → widening 20%%", tp_pct_of_exits * 100)

    def _compute_performance_multiplier(self, ins: TradeInsights) -> None:
        """
        Earned aggression: scale size UP only after the recent window proves a
        positive edge, and DOWN while it is negative. Checked on every refresh,
        so escalation happens the moment results justify it — not on a calendar.

        Ladder (profit factor = gross_profit / |gross_loss| over the window):
          PF >= 2.0 and wr >= 0.55 and n >= 30 -> 2.0x (also opens margin cap to 30%)
          PF >= 1.5 and wr >= 0.50             -> 1.5x (also opens margin cap to 30%)
          PF >= 1.2 and wr >= 0.45             -> 1.25x
          PF <  0.8                            -> 0.7x (bleeding: cut size)
          otherwise                            -> 1.0x
        Hard margin caps in RiskManager still bound the final notional.
        """
        ins.performance_size_multiplier = 1.0
        if not self.perf_escalator_enabled:
            return
        try:
            stats = self.repo.get_overall_recent_stats(hours_back=int(self.perf_escalator_hours))
        except Exception:
            return
        total = int(stats.get("total_trades", 0) or 0)
        if total < self.perf_escalator_min_trades:
            return
        gross_profit = float(stats.get("gross_profit", 0) or 0.0)
        gross_loss = abs(float(stats.get("gross_loss", 0) or 0.0))
        wr = float(stats.get("win_rate", 0) or 0.0)
        pf = gross_profit / gross_loss if gross_loss > 0 else (2.0 if gross_profit > 0 else 0.0)

        if pf >= 2.0 and wr >= 0.55 and total >= 30:
            ins.performance_size_multiplier = 2.0
        elif pf >= 1.5 and wr >= 0.50:
            ins.performance_size_multiplier = 1.5
        elif pf >= 1.2 and wr >= 0.45:
            ins.performance_size_multiplier = 1.25
        elif pf < 0.8:
            ins.performance_size_multiplier = 0.7

        if ins.performance_size_multiplier != 1.0:
            logger.info(
                "TradeAnalyzer: performance escalator %.2fx (PF=%.2f wr=%.0f%% over %d trades/%.0fh)",
                ins.performance_size_multiplier, pf, wr * 100, total, self.perf_escalator_hours,
            )

    def _compute_kelly_fraction(self, ins: TradeInsights, overall: Dict) -> None:
        """
        Kelly Criterion: f* = (p * b - q) / b
        where p = win_rate, q = 1-p, b = avg_win / avg_loss

        We use half-Kelly for safety (f*/2).
        """
        if not self.kelly_enabled:
            ins.kelly_fraction = 1.0
            logger.info("TradeAnalyzer Kelly sizing disabled by config — using full configured size")
            return

        total = overall.get("total_trades", 0) or 0
        if total < 15:
            ins.kelly_fraction = 1.0  # Not enough data, use default sizing
            return

        wins = overall.get("wins", 0) or 0
        losses = overall.get("losses", 0) or 0
        if wins == 0 or losses == 0:
            ins.kelly_fraction = 0.5 if wins == 0 else 1.0
            return

        # Get avg win and avg loss from DB
        conn = self.repo._get_conn()
        cursor = conn.execute(
            """
            SELECT
                AVG(CASE WHEN pnl > 0 THEN pnl END) AS avg_win,
                AVG(CASE WHEN pnl <= 0 THEN ABS(pnl) END) AS avg_loss
            FROM trades
            WHERE status = 'closed' AND pnl IS NOT NULL
              AND closed_at >= datetime('now', '-' || ? || ' hours')
            """,
            (self.lookback_hours,),
        )
        row = cursor.fetchone()
        avg_win = (row["avg_win"] or 0) if row else 0
        avg_loss = (row["avg_loss"] or 0) if row else 0

        if avg_loss <= 0 or avg_win <= 0:
            ins.kelly_fraction = 0.5
            return

        p = wins / total  # win probability
        q = 1 - p
        b = avg_win / avg_loss  # win/loss ratio

        kelly = (p * b - q) / b if b > 0 else 0

        # Half-Kelly for safety, clamped to [0.1, 1.0]
        half_kelly = max(0.1, min(1.0, kelly / 2))
        ins.kelly_fraction = round(half_kelly, 3)

        logger.info(
            "TradeAnalyzer Kelly: p=%.2f, b=%.2f, full_kelly=%.3f, half_kelly=%.3f",
            p, b, kelly, half_kelly,
        )

    def _compute_hour_stats(self, ins: TradeInsights) -> None:
        """
        Analyze which UTC hours are profitable vs losers.
        """
        conn = self.repo._get_conn()
        cursor = conn.execute(
            """
            SELECT
                CAST(strftime('%H', opened_at) AS INTEGER) AS hour_utc,
                COUNT(*) AS trades,
                ROUND(AVG(CASE WHEN pnl > 0 THEN 1.0 ELSE 0.0 END), 4) AS win_rate,
                ROUND(SUM(pnl), 6) AS total_pnl
            FROM trades
            WHERE status = 'closed' AND pnl IS NOT NULL
              AND closed_at >= datetime('now', '-' || ? || ' hours')
            GROUP BY hour_utc
            HAVING COUNT(*) >= 3
            ORDER BY total_pnl ASC
            """,
            (self.lookback_hours,),
        )
        rows = cursor.fetchall()

        for row in rows:
            hour = row["hour_utc"]
            wr = row["win_rate"] or 0
            pnl = row["total_pnl"] or 0
            n = row["trades"] or 0

            # Two tiers: very bad on few trades, or consistently weak on many —
            # hours like 33% wr across 27+ trades were slipping through.
            if (wr < 0.30 and n >= 5 and pnl < 0) or (wr <= 0.35 and n >= 8 and pnl < 0):
                ins.bad_hours_utc.add(hour)
                logger.info(
                    "TradeAnalyzer: hour %02d UTC is BAD (wr=%.0f%%, pnl=%.4f, n=%d)",
                    hour, wr * 100, pnl, n,
                )
            elif wr >= 0.60 and n >= 5 and pnl > 0:
                ins.good_hours_utc.add(hour)

    def _compute_direction_stats(self, ins: TradeInsights) -> None:
        """
        Analyze LONG vs SHORT performance. If one direction is clearly better,
        set a preference that the scanner can use.
        """
        conn = self.repo._get_conn()
        cursor = conn.execute(
            """
            SELECT
                side,
                COUNT(*) AS trades,
                ROUND(AVG(CASE WHEN pnl > 0 THEN 1.0 ELSE 0.0 END), 4) AS win_rate,
                ROUND(SUM(pnl), 6) AS total_pnl
            FROM trades
            WHERE status = 'closed' AND pnl IS NOT NULL
              AND closed_at >= datetime('now', '-' || ? || ' hours')
            GROUP BY side
            HAVING COUNT(*) >= 5
            """,
            (self.lookback_hours,),
        )
        rows = cursor.fetchall()

        for row in rows:
            side = row["side"]
            wr = row["win_rate"] or 0
            if side == "LONG":
                ins.long_win_rate = wr
            elif side == "SHORT":
                ins.short_win_rate = wr

        # If one direction is significantly better (>15% difference), prefer it
        diff = ins.long_win_rate - ins.short_win_rate
        if diff > 0.15 and ins.long_win_rate >= 0.50:
            ins.preferred_direction = "LONG"
            logger.info(
                "TradeAnalyzer: LONG preferred (wr=%.0f%% vs SHORT %.0f%%)",
                ins.long_win_rate * 100, ins.short_win_rate * 100,
            )
        elif diff < -0.15 and ins.short_win_rate >= 0.50:
            ins.preferred_direction = "SHORT"
            logger.info(
                "TradeAnalyzer: SHORT preferred (wr=%.0f%% vs LONG %.0f%%)",
                ins.short_win_rate * 100, ins.long_win_rate * 100,
            )

    def _check_model_health(self, ins: TradeInsights) -> None:
        """
        Check if ML model predictions are actually predictive.
        If recent trades with high scores (85+) have <40% win rate, model is broken.
        """
        bracket_stats = self.repo.get_score_bracket_stats(hours_back=self.lookback_hours)

        high_score_trades = 0
        high_score_wr = 0.0
        for bs in bracket_stats:
            bracket = bs.get("score_bracket", "")
            if bracket in ("85-92", "92+"):
                n = bs.get("trades", 0) or 0
                wr = bs.get("win_rate", 0) or 0
                high_score_trades += n
                high_score_wr += wr * n  # weighted

        if high_score_trades >= 10:
            avg_wr = high_score_wr / high_score_trades
            if avg_wr < 0.40:
                ins.model_healthy = False
                logger.critical(
                    "TradeAnalyzer: MODEL UNHEALTHY — high-score trades (85+) have %.0f%% win rate (n=%d). "
                    "ML predictions are not predictive!",
                    avg_wr * 100, high_score_trades,
                )

    # ------------------------------------------------------------------
    # Public API (used by scanner + risk manager + main loop)
    # ------------------------------------------------------------------

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

    def get_direction_penalty(self, direction: str) -> float:
        """
        Score penalty for non-preferred direction.
        Returns 0 if no preference, or -5 if trading against the trend.
        """
        pref = self._insights.preferred_direction
        if not pref:
            return 0.0
        if direction != pref:
            return -5.0
        return 2.0  # small bonus for preferred direction

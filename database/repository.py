"""
SQLite repository for the Binance Futures Trading System.
Handles persistence for trades, signals, portfolio snapshots, and system events.
"""

import sqlite3
import logging
import math
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)


class TradeRepository:
    """Complete SQLite repository for all trading system data."""

    def __init__(self, db_path: str = "trading.db"):
        self.db_path = db_path
        self._conn: Optional[sqlite3.Connection] = None
        self.create_tables()

    def _get_conn(self) -> sqlite3.Connection:
        """Get or create a thread-local SQLite connection."""
        if self._conn is None:
            self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
            self._conn.row_factory = sqlite3.Row
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.execute("PRAGMA foreign_keys=ON")
        return self._conn

    def create_tables(self) -> None:
        """Create all required tables if they don't exist."""
        conn = self._get_conn()
        cursor = conn.cursor()

        cursor.executescript("""
            CREATE TABLE IF NOT EXISTS trades (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol          TEXT NOT NULL,
                side            TEXT NOT NULL,
                entry_price     REAL NOT NULL,
                exit_price      REAL,
                quantity        REAL NOT NULL,
                sl_price        REAL,
                tp_price        REAL,
                status          TEXT NOT NULL DEFAULT 'open',
                pnl             REAL,
                pnl_pct         REAL,
                opened_at       TEXT NOT NULL,
                closed_at       TEXT,
                close_reason    TEXT,
                confidence      REAL,
                strategy_signal TEXT
            );

            CREATE TABLE IF NOT EXISTS signals (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol          TEXT NOT NULL,
                direction       TEXT NOT NULL,
                confidence      REAL NOT NULL,
                regime          TEXT,
                trend           TEXT,
                volatility      TEXT,
                rf_prob         REAL,
                gb_prob         REAL,
                lr_prob         REAL,
                ensemble_prob   REAL,
                created_at      TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS portfolio_snapshots (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                balance         REAL NOT NULL,
                equity          REAL NOT NULL,
                total_pnl       REAL NOT NULL,
                total_pnl_pct   REAL NOT NULL,
                unrealized_pnl  REAL NOT NULL DEFAULT 0.0,
                open_positions  INTEGER NOT NULL DEFAULT 0,
                win_rate        REAL NOT NULL DEFAULT 0.0,
                timestamp       TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS system_events (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                event_type      TEXT NOT NULL,
                message         TEXT NOT NULL,
                severity        TEXT NOT NULL DEFAULT 'INFO',
                timestamp       TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades(symbol);
            CREATE INDEX IF NOT EXISTS idx_trades_status ON trades(status);
            CREATE INDEX IF NOT EXISTS idx_signals_symbol ON signals(symbol);
            CREATE INDEX IF NOT EXISTS idx_signals_created ON signals(created_at);
            CREATE INDEX IF NOT EXISTS idx_snapshots_ts ON portfolio_snapshots(timestamp);
            CREATE INDEX IF NOT EXISTS idx_events_ts ON system_events(timestamp);
        """)
        conn.commit()

        # Migrate: add unrealized_pnl column if missing (existing DBs)
        try:
            cursor.execute("SELECT unrealized_pnl FROM portfolio_snapshots LIMIT 1")
        except sqlite3.OperationalError:
            cursor.execute(
                "ALTER TABLE portfolio_snapshots ADD COLUMN unrealized_pnl REAL NOT NULL DEFAULT 0.0"
            )
            conn.commit()
            logger.info("Migrated portfolio_snapshots: added unrealized_pnl column")

        logger.info("Database tables created/verified at: %s", self.db_path)

    # -------------------------------------------------------------------------
    # Trade methods
    # -------------------------------------------------------------------------

    def insert_trade(self, trade_dict: Dict[str, Any]) -> int:
        """Insert a new trade record and return its ID."""
        conn = self._get_conn()
        now = datetime.now(timezone.utc).isoformat()
        cursor = conn.execute(
            """
            INSERT INTO trades
                (symbol, side, entry_price, exit_price, quantity, sl_price, tp_price,
                 status, pnl, pnl_pct, opened_at, closed_at, close_reason, confidence, strategy_signal)
            VALUES
                (:symbol, :side, :entry_price, :exit_price, :quantity, :sl_price, :tp_price,
                 :status, :pnl, :pnl_pct, :opened_at, :closed_at, :close_reason, :confidence, :strategy_signal)
            """,
            {
                "symbol": trade_dict.get("symbol", ""),
                "side": trade_dict.get("side", ""),
                "entry_price": trade_dict.get("entry_price", 0.0),
                "exit_price": trade_dict.get("exit_price"),
                "quantity": trade_dict.get("quantity", 0.0),
                "sl_price": trade_dict.get("sl_price"),
                "tp_price": trade_dict.get("tp_price"),
                "status": trade_dict.get("status", "open"),
                "pnl": trade_dict.get("pnl"),
                "pnl_pct": trade_dict.get("pnl_pct"),
                "opened_at": trade_dict.get("opened_at", now),
                "closed_at": trade_dict.get("closed_at"),
                "close_reason": trade_dict.get("close_reason"),
                "confidence": trade_dict.get("confidence"),
                "strategy_signal": trade_dict.get("strategy_signal"),
            },
        )
        conn.commit()
        trade_id = cursor.lastrowid
        logger.debug("Inserted trade id=%d for %s", trade_id, trade_dict.get("symbol"))
        return trade_id

    def update_trade(self, trade_id: int, updates: Dict[str, Any]) -> None:
        """Update fields on an existing trade."""
        if not updates:
            return
        conn = self._get_conn()
        set_clause = ", ".join(f"{k} = :{k}" for k in updates)
        updates["_id"] = trade_id
        conn.execute(
            f"UPDATE trades SET {set_clause} WHERE id = :_id",
            updates,
        )
        conn.commit()
        logger.debug("Updated trade id=%d with %s", trade_id, list(updates.keys()))

    def get_open_trades(self) -> List[Dict[str, Any]]:
        """Return all currently open trades."""
        conn = self._get_conn()
        cursor = conn.execute(
            "SELECT * FROM trades WHERE status = 'open' ORDER BY opened_at DESC"
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_trade_history(self, limit: int = 100) -> List[Dict[str, Any]]:
        """Return the most recent closed/cancelled trades."""
        conn = self._get_conn()
        cursor = conn.execute(
            "SELECT * FROM trades WHERE status != 'open' ORDER BY closed_at DESC LIMIT ?",
            (limit,),
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_all_trades(self) -> List[Dict[str, Any]]:
        """Return all trades regardless of status."""
        conn = self._get_conn()
        cursor = conn.execute("SELECT * FROM trades ORDER BY opened_at DESC")
        return [dict(row) for row in cursor.fetchall()]

    # -------------------------------------------------------------------------
    # Signal methods
    # -------------------------------------------------------------------------

    def insert_signal(self, signal_dict: Dict[str, Any]) -> int:
        """Insert a new signal record and return its ID."""
        conn = self._get_conn()
        now = datetime.now(timezone.utc).isoformat()
        cursor = conn.execute(
            """
            INSERT INTO signals
                (symbol, direction, confidence, regime, trend, volatility,
                 rf_prob, gb_prob, lr_prob, ensemble_prob, created_at)
            VALUES
                (:symbol, :direction, :confidence, :regime, :trend, :volatility,
                 :rf_prob, :gb_prob, :lr_prob, :ensemble_prob, :created_at)
            """,
            {
                "symbol": signal_dict.get("symbol", ""),
                "direction": signal_dict.get("direction", "NEUTRAL"),
                "confidence": signal_dict.get("confidence", 0.0),
                "regime": signal_dict.get("regime", ""),
                "trend": signal_dict.get("trend", ""),
                "volatility": signal_dict.get("volatility", ""),
                "rf_prob": signal_dict.get("rf_prob"),
                "gb_prob": signal_dict.get("gb_prob"),
                "lr_prob": signal_dict.get("lr_prob"),
                "ensemble_prob": signal_dict.get("ensemble_prob"),
                "created_at": signal_dict.get("created_at", now),
            },
        )
        conn.commit()
        return cursor.lastrowid

    def get_recent_signals(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Return the most recent signals."""
        conn = self._get_conn()
        cursor = conn.execute(
            "SELECT * FROM signals ORDER BY created_at DESC LIMIT ?", (limit,)
        )
        return [dict(row) for row in cursor.fetchall()]

    # -------------------------------------------------------------------------
    # Portfolio snapshot methods
    # -------------------------------------------------------------------------

    def insert_portfolio_snapshot(self, snapshot_dict: Dict[str, Any]) -> None:
        """Insert a portfolio snapshot."""
        conn = self._get_conn()
        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            """
            INSERT INTO portfolio_snapshots
                (balance, equity, total_pnl, total_pnl_pct, unrealized_pnl, open_positions, win_rate, timestamp)
            VALUES
                (:balance, :equity, :total_pnl, :total_pnl_pct, :unrealized_pnl, :open_positions, :win_rate, :timestamp)
            """,
            {
                "balance": snapshot_dict.get("balance", 0.0),
                "equity": snapshot_dict.get("equity", 0.0),
                "total_pnl": snapshot_dict.get("total_pnl", 0.0),
                "total_pnl_pct": snapshot_dict.get("total_pnl_pct", 0.0),
                "unrealized_pnl": snapshot_dict.get("unrealized_pnl", 0.0),
                "open_positions": snapshot_dict.get("open_positions", 0),
                "win_rate": snapshot_dict.get("win_rate", 0.0),
                "timestamp": snapshot_dict.get("timestamp", now),
            },
        )
        conn.commit()

    def get_portfolio_snapshots(self, limit: int = 100) -> List[Dict[str, Any]]:
        """Return the most recent portfolio snapshots ordered by time ascending."""
        conn = self._get_conn()
        cursor = conn.execute(
            """
            SELECT * FROM (
                SELECT * FROM portfolio_snapshots ORDER BY timestamp DESC LIMIT ?
            ) ORDER BY timestamp ASC
            """,
            (limit,),
        )
        return [dict(row) for row in cursor.fetchall()]

    # -------------------------------------------------------------------------
    # System event methods
    # -------------------------------------------------------------------------

    def log_event(
        self,
        event_type: str,
        message: str,
        severity: str = "INFO",
    ) -> None:
        """Log a system event to the database."""
        conn = self._get_conn()
        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            """
            INSERT INTO system_events (event_type, message, severity, timestamp)
            VALUES (?, ?, ?, ?)
            """,
            (event_type, message, severity, now),
        )
        conn.commit()

    def get_recent_events(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Return the most recent system events."""
        conn = self._get_conn()
        cursor = conn.execute(
            "SELECT * FROM system_events ORDER BY timestamp DESC LIMIT ?", (limit,)
        )
        return [dict(row) for row in cursor.fetchall()]

    # -------------------------------------------------------------------------
    # Performance statistics
    # -------------------------------------------------------------------------

    def get_performance_stats(self) -> Dict[str, Any]:
        """
        Compute aggregate performance statistics from closed trades.

        Returns:
            dict with keys: total_trades, winning_trades, losing_trades,
            win_rate, total_pnl, avg_pnl, max_drawdown, sharpe_ratio
        """
        conn = self._get_conn()
        cursor = conn.execute(
            "SELECT pnl, pnl_pct, opened_at, closed_at FROM trades WHERE status = 'closed' AND pnl IS NOT NULL"
        )
        rows = cursor.fetchall()

        if not rows:
            return {
                "total_trades": 0,
                "winning_trades": 0,
                "losing_trades": 0,
                "win_rate": 0.0,
                "total_pnl": 0.0,
                "avg_pnl": 0.0,
                "max_drawdown": 0.0,
                "sharpe_ratio": 0.0,
            }

        pnls = [row["pnl"] for row in rows]
        pnl_pcts = [row["pnl_pct"] for row in rows if row["pnl_pct"] is not None]

        total_trades = len(pnls)
        winning = sum(1 for p in pnls if p > 0)
        losing = sum(1 for p in pnls if p <= 0)
        total_pnl = sum(pnls)
        avg_pnl = total_pnl / total_trades if total_trades > 0 else 0.0
        win_rate = winning / total_trades if total_trades > 0 else 0.0

        # Max drawdown from cumulative PnL
        cumulative = 0.0
        peak = 0.0
        max_drawdown = 0.0
        for p in pnls:
            cumulative += p
            if cumulative > peak:
                peak = cumulative
            dd = (peak - cumulative) / peak if peak > 0 else 0.0
            if dd > max_drawdown:
                max_drawdown = dd

        # Sharpe ratio (annualised, assuming hourly trades)
        if len(pnl_pcts) >= 2:
            import statistics
            mean_r = statistics.mean(pnl_pcts)
            std_r = statistics.stdev(pnl_pcts)
            if std_r > 0:
                # Annualise assuming ~8760 hours per year
                sharpe = (mean_r / std_r) * math.sqrt(8760)
            else:
                sharpe = 0.0
        else:
            sharpe = 0.0

        return {
            "total_trades": total_trades,
            "winning_trades": winning,
            "losing_trades": losing,
            "win_rate": round(win_rate, 4),
            "total_pnl": round(total_pnl, 4),
            "avg_pnl": round(avg_pnl, 4),
            "max_drawdown": round(max_drawdown, 4),
            "sharpe_ratio": round(sharpe, 4),
        }

    def close(self) -> None:
        """Close the database connection."""
        if self._conn is not None:
            self._conn.close()
            self._conn = None
            logger.info("Database connection closed")

"""
Main entry point for the Binance Futures Trading System.

Supports two modes:
  1. CLASSIC MODE (aggressive_hft=False):
     - Processes configured symbols on schedule
     - One signal per symbol per poll_interval
     - Risk assessment → Position execution

  2. HFT MODE (aggressive_hft=True):
     - Continuous scanning for top opportunities
     - Rapid entry/exit with capital rotation
     - Market scanner discovers universe
     - ML model scores opportunities
     - Aggressive position sizing based on scores

Usage:
    python main.py                      # Paper trading (HFT mode), with dashboard
    python main.py --paper              # Force paper trading even if .env says live
    python main.py --no-dashboard       # Paper trading, no Streamlit dashboard
    python main.py --live               # Live trading (requires API keys in .env)
    python main.py --symbol BTCUSDT     # Paper trading, single symbol override
    python main.py --hft                # Force aggressive HFT mode
    python main.py --balance 50000      # Override initial balance
"""

import argparse
import fcntl
import logging
import os
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import requests
import pandas as pd

# ---------------------------------------------------------------------------
# Logging setup — must happen before any local imports
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("trading_system.log", encoding="utf-8"),
    ],
)
logger = logging.getLogger("main")

# ---------------------------------------------------------------------------
# Local imports
# ---------------------------------------------------------------------------
from config import TradingConfig, config as _default_config
from database.repository import TradeRepository
from agents.market_analysis import MarketAnalysisAgent, MarketData
from agents.strategy import StrategyAgent
from agents.risk_manager import RiskManagerAgent, Position
from agents.execution import ExecutionAgent
from agents.scanner import MarketScanner
from agents.model import TradingModel
from agents.features import FEATURE_NAMES
from agents.telegram_notifier import init_notifier, TelegramNotifier
from agents.trade_analyzer import TradeAnalyzer
from agents.agent_monitor import init_monitor, get_monitor
from agents.news_agent import NewsAgent
from agents.catalyst_agent import CatalystAgent
from agents.tradingview_signal import TradingViewSignals
from agents.market_regime import MarketRegimeAgent
from agents.decision_committee import DecisionCommitteeAgent
from agents.live_guard import LiveGuardAgent
from agents.flow_agent import FlowAgent
from agents.capital_allocator import CapitalAllocatorAgent
from agents.strategy_lab import StrategyLabAgent
from agents.indirect_strategy import IndirectStrategyAgent
from agents.opportunity_radar import OpportunityRadarAgent


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BINANCE_FUTURES_BASE = "https://fapi.binance.com"
LIVE_LOCK_PATH = os.path.join("data", "live_bot.lock")
LIVE_PID_PATH = os.path.join("data", "live_bot.pid")


class LiveProcessLock:
    """Prevent two live engines from controlling the same Binance account."""

    def __init__(self, lock_path: str = LIVE_LOCK_PATH, pid_path: str = LIVE_PID_PATH) -> None:
        self.lock_path = lock_path
        self.pid_path = pid_path
        self._fh = None

    def acquire(self) -> None:
        os.makedirs(os.path.dirname(self.lock_path), exist_ok=True)
        existing_pid = self._read_pid()
        if (
            existing_pid
            and existing_pid != os.getpid()
            and self._is_live_bot_process(existing_pid)
        ):
            raise RuntimeError(
                f"Live bot already running with PID {existing_pid}. "
                "Stop it before starting another live instance."
            )

        self._fh = open(self.lock_path, "a+", encoding="utf-8")
        try:
            fcntl.flock(self._fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("Another live bot process holds the live lock.") from exc

        with open(self.pid_path, "w", encoding="utf-8") as fh:
            fh.write(f"{os.getpid()}\n")

    def release(self) -> None:
        if self._fh is not None:
            try:
                fcntl.flock(self._fh.fileno(), fcntl.LOCK_UN)
            finally:
                self._fh.close()
                self._fh = None
        try:
            if self._read_pid() == os.getpid():
                os.remove(self.pid_path)
        except OSError:
            pass

    def _read_pid(self) -> Optional[int]:
        try:
            with open(self.pid_path, "r", encoding="utf-8") as fh:
                raw = fh.read().strip()
            return int(raw) if raw else None
        except (OSError, ValueError):
            return None

    @staticmethod
    def _is_live_bot_process(pid: int) -> bool:
        try:
            cmd = subprocess.check_output(
                ["ps", "-p", str(pid), "-o", "command="],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            return False
        return "main.py" in cmd and "--live" in cmd


# ---------------------------------------------------------------------------
# HTTP utilities
# ---------------------------------------------------------------------------

def _http_get_with_retries(
    url: str,
    *,
    params: Optional[dict] = None,
    timeout: int = 15,
    attempts: int = 4,
    backoff_sec: float = 1.5,
) -> Optional[requests.Response]:
    """GET with retries for transient DNS/network failures."""
    last_exc: Optional[Exception] = None
    for attempt in range(attempts):
        try:
            resp = requests.get(url, params=params, timeout=timeout)
            resp.raise_for_status()
            return resp
        except requests.RequestException as exc:
            last_exc = exc
            if attempt < attempts - 1:
                time.sleep(backoff_sec * (attempt + 1))
    logger.warning("HTTP GET failed after %d attempts: %s", attempts, last_exc)
    return None


def fetch_ohlcv(
    symbol: str,
    interval: str = "1h",
    limit: int = 300,
) -> Optional[pd.DataFrame]:
    """
    Fetch OHLCV kline data from Binance Futures public API.

    Returns a DataFrame with columns:
        open_time, open, high, low, close, volume
    or None on failure.
    """
    url = f"{BINANCE_FUTURES_BASE}/fapi/v1/klines"
    params = {
        "symbol": symbol,
        "interval": interval,
        "limit": limit,
    }

    resp = _http_get_with_retries(url, params=params, timeout=15)
    if resp is None:
        return None
    try:
        data = resp.json()
    except Exception as exc:
        logger.warning("Unexpected error parsing OHLCV JSON for %s: %s", symbol, exc)
        return None

    if not data:
        logger.warning("Empty OHLCV response for %s", symbol)
        return None

    try:
        df = pd.DataFrame(
            data,
            columns=[
                "open_time", "open", "high", "low", "close", "volume",
                "close_time", "quote_asset_volume", "num_trades",
                "taker_buy_base", "taker_buy_quote", "ignore",
            ],
        )
        df["open_time"] = pd.to_datetime(df["open_time"], unit="ms", utc=True)
        df.set_index("open_time", inplace=True)
        for col in ("open", "high", "low", "close", "volume"):
            df[col] = pd.to_numeric(df[col], errors="coerce")
        df = df[["open", "high", "low", "close", "volume"]].dropna()
        return df
    except Exception as exc:
        logger.exception("Error parsing OHLCV data for %s: %s", symbol, exc)
        return None


# ---------------------------------------------------------------------------
# Kill switch state machine
# ---------------------------------------------------------------------------

class KillSwitchState:
    """Tracks whether the kill switch is active and why."""

    def __init__(self):
        self._active: bool = False
        self._reason: str = ""
        self._activated_at: Optional[datetime] = None

    @property
    def active(self) -> bool:
        return self._active

    def activate(self, reason: str) -> None:
        if not self._active:
            self._active = True
            self._reason = reason
            self._activated_at = datetime.now(timezone.utc)
            logger.critical("KILL SWITCH ACTIVATED: %s", reason)

    def deactivate(self) -> None:
        self._active = False
        self._reason = ""
        self._activated_at = None
        logger.info("Kill switch deactivated")

    def __str__(self) -> str:
        if self._active:
            return f"ACTIVE since {self._activated_at} — {self._reason}"
        return "INACTIVE"


# ---------------------------------------------------------------------------
# TradingSystem class
# ---------------------------------------------------------------------------

class TradingSystem:
    """
    Orchestrates all agents in the main trading loop.
    Supports both classic mode (per-symbol strategy) and HFT mode (scanner-based).
    """

    def __init__(self, config: TradingConfig):
        self.config = config
        self.running = False
        self.kill_state = KillSwitchState()

        # Repository
        self.repo = TradeRepository(db_path=config.db_path)
        if config.paper_trading and config.paper_reset_open_trades_on_start:
            reset_count = self.repo.cancel_open_paper_trades()
            if reset_count:
                self.repo.log_event(
                    "PAPER_RESET",
                    f"Marked {reset_count} stale paper open trades as cancelled",
                    severity="INFO",
                )
                logger.info("Marked %d stale paper open trades as cancelled", reset_count)

        # Live agent-activity monitor (powers the dashboard control center)
        self.monitor = init_monitor(self.repo)
        self.monitor.report(
            "System", "boot",
            f"מאתחל מערכת | mode={'PAPER' if config.paper_trading else 'LIVE'} | "
            f"hft={config.aggressive_hft}",
            status="active", force=True,
        )
        self.live_guard = LiveGuardAgent(config=config, monitor=self.monitor)
        if not config.paper_trading:
            self.live_guard.require_ready()

        # Agents
        self.market_agent = MarketAnalysisAgent(config=config)
        self.strategy_agent = StrategyAgent(config=config)

        # Determine initial balance (paper or live)
        initial_balance = config.paper_initial_balance
        session_start_equity: Optional[float] = None
        acc_info = None
        if not config.paper_trading:
            try:
                from agents.binance_compat import create_binance_client, live_full_account_info

                _client = create_binance_client(config.api_key, config.api_secret)
                acc_info = live_full_account_info(_client)
                if acc_info is not None:
                    wallet = acc_info["wallet_balance"]
                    available = acc_info["available_balance"]
                    margin = acc_info["margin_balance"]
                    unrealized = acc_info["unrealized_pnl"]
                    # Use margin (total equity) as baseline — using available would give
                    # false drawdown alerts when margin is tied up in existing positions
                    initial_balance = margin if margin > 0 else wallet
                    session_start_equity = margin
                    logger.info(
                        "Live account: wallet=%.2f, available=%.2f, margin=%.2f, unrealized=%.2f",
                        wallet, available, margin, unrealized,
                    )
            except Exception as exc:
                logger.error("Failed to fetch live account info: %s", exc)

        self.risk_agent = RiskManagerAgent(
            config=config,
            initial_balance=initial_balance,
            session_start_equity=session_start_equity,
        )

        self.execution_agent = ExecutionAgent(
            config=config,
            risk_manager=self.risk_agent,
            repository=self.repo,
        )

        # Set up initial leverage
        if not config.paper_trading:
            for symbol in config.symbols:
                self.execution_agent.set_leverage(symbol, config.leverage)

        # Sync existing Binance positions into risk manager to avoid double-entry
        if not config.paper_trading and acc_info is not None:
            from agents.risk_manager import Position
            from datetime import datetime, timezone
            open_trades_by_symbol = {
                str(t.get("symbol", "")): t for t in self.repo.get_open_trades()
            }
            live_symbols = {
                str(p.get("symbol", ""))
                for p in acc_info.get("positions", [])
                if float(p.get("positionAmt", 0) or 0) != 0
            }

            # If Binance is already flat but the DB still has an open row, close
            # the stale DB row from recent account fills so sizing/max-positions
            # are not distorted after restarts.
            for sym, db_trade in list(open_trades_by_symbol.items()):
                if not sym or sym in live_symbols:
                    continue
                try:
                    side = str(db_trade.get("side") or "LONG")
                    opened_at = datetime.now(timezone.utc)
                    if db_trade.get("opened_at"):
                        opened_at = datetime.fromisoformat(
                            str(db_trade["opened_at"]).replace("Z", "+00:00")
                        )
                    self.risk_agent.open_positions[sym] = Position(
                        symbol=sym,
                        side=side,
                        entry_price=float(db_trade.get("entry_price") or 0.0),
                        quantity=abs(float(db_trade.get("quantity") or 0.0)),
                        sl_price=float(db_trade.get("sl_price") or 0.0),
                        tp_price=float(db_trade.get("tp_price") or 0.0),
                        opened_at=opened_at,
                        trade_id=db_trade.get("id"),
                        unrealized_pnl=0.0,
                    )
                    result = self.execution_agent._reconcile_live_flat_position(
                        sym,
                        current_price=0.0,
                        reason="stop_loss",
                    )
                    if result and result.get("trade_id"):
                        self.repo.update_trade(
                            int(result["trade_id"]),
                            {
                                "exit_price": result.get("exit_price"),
                                "status": "closed",
                                "pnl": result.get("pnl"),
                                "pnl_pct": result.get("pnl_pct"),
                                "closed_at": result.get("closed_at"),
                                "close_reason": result.get("close_reason"),
                            },
                        )
                        self.repo.log_event(
                            "LIVE_SYNC",
                            (
                                f"Closed stale DB position {sym}: Binance is flat, "
                                f"reason={result.get('close_reason')}"
                            ),
                            "INFO",
                        )
                    self.risk_agent.remove_position(sym)
                    open_trades_by_symbol.pop(sym, None)
                except Exception as exc:
                    self.risk_agent.remove_position(sym)
                    logger.warning("Could not reconcile stale DB position %s: %s", sym, exc)

            for live_pos in acc_info.get("positions", []):
                sym = live_pos["symbol"]
                amt = live_pos["positionAmt"]
                entry = live_pos["entryPrice"]
                if sym not in self.risk_agent.open_positions and amt != 0 and entry > 0:
                    self.execution_agent.set_leverage(sym, config.leverage, force=True)
                    side = "LONG" if amt > 0 else "SHORT"
                    db_trade = open_trades_by_symbol.get(sym)
                    trade_id = db_trade.get("id") if db_trade else None
                    opened_at = datetime.now(timezone.utc)
                    if db_trade and db_trade.get("opened_at"):
                        try:
                            opened_at = datetime.fromisoformat(
                                str(db_trade["opened_at"]).replace("Z", "+00:00")
                            )
                        except ValueError:
                            opened_at = datetime.now(timezone.utc)

                    sl_price = float(db_trade.get("sl_price") or 0) if db_trade else 0.0
                    tp_price = float(db_trade.get("tp_price") or 0) if db_trade else 0.0
                    if sl_price <= 0 or tp_price <= 0:
                        # Compute SL/TP from ATR like a normal entry.
                        try:
                            klines = self.execution_agent.client.futures_klines(
                                symbol=sym, interval=config.hft_timeframe, limit=20
                            )
                            highs = [float(k[2]) for k in klines]
                            lows = [float(k[3]) for k in klines]
                            trs = [h - l for h, l in zip(highs, lows)]
                            atr = sum(trs[-14:]) / min(len(trs), 14) if trs else entry * 0.005
                            sl_price, tp_price = self.risk_agent.calculate_sl_tp(entry, side, atr)
                        except Exception:
                            sl_price = entry * (0.995 if side == "LONG" else 1.005)
                            tp_price = entry * (1.005 if side == "LONG" else 0.995)

                    if db_trade is None:
                        trade_id = self.repo.insert_trade(
                            {
                                "symbol": sym,
                                "side": side,
                                "entry_price": entry,
                                "exit_price": None,
                                "quantity": abs(amt),
                                "sl_price": sl_price,
                                "tp_price": tp_price,
                                "status": "open",
                                "pnl": None,
                                "pnl_pct": None,
                                "opened_at": opened_at.isoformat(),
                                "closed_at": None,
                                "close_reason": None,
                                "confidence": None,
                                "strategy_signal": "LIVE_SYNC",
                            }
                        )
                        self.repo.log_event(
                            "LIVE_SYNC",
                            f"Imported existing Binance position {side} {sym} qty={abs(amt):.8f} @ {entry:.6f}",
                            "INFO",
                        )

                    self.risk_agent.open_positions[sym] = Position(
                        symbol=sym,
                        side=side,
                        entry_price=entry,
                        quantity=abs(amt),
                        sl_price=sl_price,
                        tp_price=tp_price,
                        opened_at=opened_at,
                        trade_id=trade_id,
                        unrealized_pnl=0.0,
                    )
                    logger.info("Synced existing position: %s %s qty=%.4f entry=%.4f sl=%.4f tp=%.4f",
                                side, sym, abs(amt), entry, sl_price, tp_price)
                    # Ensure a synced position has exchange-side SL/TP protection too
                    try:
                        protective = self.execution_agent.place_protective_orders(
                            sym, side, sl_price, tp_price
                        )
                        if not protective.get("sl_order_id"):
                            logger.critical(
                                "Synced live position %s has no exchange-side stop-loss protection",
                                sym,
                            )
                    except Exception as exc:
                        logger.warning("Could not place protective orders for synced %s: %s", sym, exc)

        # Trade Analyzer — learns from history, feeds insights into scanner + risk
        self.trade_analyzer = TradeAnalyzer(
            repo=self.repo,
            base_score_entry=config.score_entry,
            min_trades_for_symbol_action=5,
            symbol_blacklist_win_rate=0.30,
            min_trades_overall=10,
            lookback_hours=48,
        )
        # Do an initial refresh to load any existing trade history
        self.trade_analyzer.refresh()
        insights = self.trade_analyzer.insights
        if insights.has_enough_data:
            logger.info(
                "TradeAnalyzer loaded: %d recent trades, wr=%.1f%%, score=%.0f, kelly=%.2f, blacklist=%d",
                insights.recent_trade_count, insights.recent_win_rate * 100,
                insights.adjusted_score_entry, insights.kelly_fraction,
                len(insights.symbol_blacklist),
            )
            self.risk_agent._adaptive_score_entry = insights.adjusted_score_entry
            self.risk_agent._kelly_fraction = insights.kelly_fraction
            self.risk_agent._performance_multiplier = insights.performance_size_multiplier
            self.risk_agent._bad_hours_utc = insights.bad_hours_utc
            self.risk_agent._sl_multiplier = insights.sl_multiplier
            self.risk_agent._tp_multiplier = insights.tp_multiplier
            self.risk_agent._model_healthy = insights.model_healthy

        # HFT mode: scanner and model
        self.scanner: Optional[MarketScanner] = None
        self.model: Optional[TradingModel] = None
        self._scanner_universe_cache: List[str] = []
        self._loop_count: int = 0

        if config.aggressive_hft:
            self.model = TradingModel()
            self.scanner = MarketScanner(config=config, model=self.model, trade_analyzer=self.trade_analyzer)
            logger.info("HFT mode enabled: MarketScanner + TradingModel + TradeAnalyzer initialized")
        else:
            logger.info("Classic mode enabled: symbol-based strategy loop")

        # TradingView technical-analysis signals (optional auto-entry source)
        self.tv_signals = TradingViewSignals(interval=config.tradingview_interval)
        self._tv_last_fetch: float = 0.0
        self._tv_cache_opps: Optional[List[Dict]] = None
        if config.tradingview_signals and not self.tv_signals.available:
            logger.warning("TRADINGVIEW_SIGNALS=true but tradingview-ta not installed — "
                           "run: %s -m pip install tradingview-ta", sys.executable)

        # News / sentiment agent (free public sources) — 7th agent in the control center
        self.news_agent = NewsAgent(
            monitor=self.monitor,
            refresh_seconds=config.news_refresh_seconds,
            config=config,
        )
        self.catalyst_agent = CatalystAgent(
            config=config,
            monitor=self.monitor,
            refresh_seconds=config.catalyst_refresh_seconds,
        )
        self.market_regime_agent = MarketRegimeAgent(config=config, monitor=self.monitor)
        self.flow_agent = FlowAgent(config=config, monitor=self.monitor)
        self.capital_allocator = CapitalAllocatorAgent(config=config, monitor=self.monitor)
        self.indirect_strategy = IndirectStrategyAgent(config=config, monitor=self.monitor)
        self.decision_committee = DecisionCommitteeAgent(
            config=config,
            monitor=self.monitor,
            repo=self.repo,
        )
        self.strategy_lab = StrategyLabAgent(
            config=config,
            repo=self.repo,
            monitor=self.monitor,
        )
        self.opportunity_radar = OpportunityRadarAgent(config=config, monitor=self.monitor)
        try:
            self.news_agent.refresh()
        except Exception as exc:
            logger.debug("Initial news refresh failed: %s", exc)
        if config.catalyst_agent_enabled:
            try:
                self.catalyst_agent.refresh()
            except Exception as exc:
                logger.debug("Initial catalyst refresh failed: %s", exc)
        try:
            self.market_regime_agent.refresh()
        except Exception as exc:
            logger.debug("Initial market regime refresh failed: %s", exc)
        if config.strategy_lab_enabled:
            try:
                self.strategy_lab.refresh()
            except Exception as exc:
                logger.debug("Initial strategy lab refresh failed: %s", exc)
        if config.opportunity_radar_enabled:
            try:
                self.opportunity_radar.refresh()
            except Exception as exc:
                logger.debug("Initial opportunity radar refresh failed: %s", exc)

        self._log_safety_rails()
        self.monitor.report(
            "Flow",
            "armed" if config.flow_agent_enabled else "off",
            (
                f"flow={'on' if config.flow_agent_enabled else 'off'} "
                f"period={config.flow_period} lookback={config.flow_lookback} "
                f"oi_min={config.flow_min_oi_change_pct:.2%}"
            ),
            status="active" if config.flow_agent_enabled else "paused",
            force=True,
        )
        self.monitor.report(
            "Capital",
            "armed" if config.capital_allocator_enabled else "off",
            (
                f"allocator={'on' if config.capital_allocator_enabled else 'off'} "
                f"min_score={config.capital_allocator_min_score:.0f} "
                f"boost={config.capital_allocator_size_multiplier:.2f}x"
            ),
            status="active" if config.capital_allocator_enabled else "paused",
            force=True,
        )
        self.monitor.report(
            "Runner",
            "armed" if config.trend_runner_enabled else "off",
            (
                f"runner={'on' if config.trend_runner_enabled else 'off'} "
                f"min_score={config.trend_runner_min_score:.0f} "
                f"tp_mult={config.trend_runner_tp_multiplier:.2f}"
            ),
            status="active" if config.trend_runner_enabled else "paused",
            force=True,
        )
        self.monitor.report(
            "Indirect",
            "armed" if config.indirect_strategies_enabled else "off",
            (
                f"grid={'on' if config.indirect_grid_enabled else 'off'} "
                f"dca={'on' if config.indirect_dca_enabled else 'off'} "
                f"arb={'on' if config.indirect_arb_enabled else 'off'} "
                f"anti_martingale={'on' if config.indirect_martingale_inverse_enabled else 'off'}"
            ),
            status="active" if config.indirect_strategies_enabled else "paused",
            force=True,
        )
        self.monitor.report(
            "StrategyLab",
            "armed" if config.strategy_lab_enabled else "off",
            (
                f"research_gate={'on' if config.strategy_lab_enabled else 'off'} "
                f"lookback={config.strategy_lab_lookback_hours}h "
                f"min_trades={config.strategy_lab_min_live_trades}"
            ),
            status="active" if config.strategy_lab_enabled else "paused",
            force=True,
        )
        self.monitor.report(
            "OpportunityRadar",
            "armed" if config.opportunity_radar_enabled else "off",
            "Spot/Grid/Options/Alpha/Dual/Launchpool במעקב; כניסה ידנית בלבד",
            status="active" if config.opportunity_radar_enabled else "paused",
            force=True,
        )
        self.monitor.report(
            "Catalyst",
            "armed" if config.catalyst_agent_enabled else "off",
            (
                "Binance announcements/RSS/listing/delisting "
                f"refresh={config.catalyst_refresh_seconds:.0f}s"
            ),
            status="active" if config.catalyst_agent_enabled else "paused",
            force=True,
        )

        # Telegram notifier
        self.tg: TelegramNotifier = init_notifier(
            token=config.telegram_token,
            chat_id=config.telegram_chat_id,
            enabled=config.telegram_enabled,
        )
        self._session_pnl: float = 0.0
        self._session_trades: int = 0
        self._last_heartbeat: float = 0.0
        self._refresh_count_tg: int = 0
        self._last_health_check: float = 0.0

        # Dashboard subprocess
        self.dashboard_proc: Optional[subprocess.Popen] = None

    def _log_safety_rails(self) -> None:
        """One-line summary of automatic guardrails (no manual action required)."""
        c = self.config
        max_pos = c.hft_max_open_positions if c.aggressive_hft else c.max_open_positions
        logger.info(
            "Safety rails (automatic) | paper=%s | aggressive_hft=%s | leverage=%dx | "
            "max_open_positions=%s | max_margin_per_position=%.0f%% | "
            "min_notional=%.2f USDT | session_dd_kill=%.0f%% | daily_dd_kill=%.0f%% | stale_exit=%s | "
            "profit_take=%.2f%% | profit_lock=%s | flow_agent=%s | capital_allocator=%s | runner=%s | "
            "indirect=%s | strategy_lab=%s | fallback_strong=%s | "
            "min_price=%.2f USDT | score_entry=%.0f | live_guard=%s | decision_consensus=%.0f%%",
            c.paper_trading,
            c.aggressive_hft,
            c.leverage,
            max_pos,
            c.max_margin_fraction * 100,
            c.hft_min_notional_usdt,
            c.max_drawdown_pct * 100,
            c.daily_max_drawdown_pct * 100,
            (f"{c.stale_exit_seconds:.0f}s" if c.stale_exit_seconds > 0 else "off"),
            c.profit_take_pct * 100,
            "on" if c.profit_lock_enabled else "off",
            "on" if c.flow_agent_enabled else "off",
            f"on/{c.capital_allocator_size_multiplier:.2f}x" if c.capital_allocator_enabled else "off",
            f"on/tp{c.trend_runner_tp_multiplier:.2f}x" if c.trend_runner_enabled else "off",
            "on" if c.indirect_strategies_enabled else "off",
            "on" if c.strategy_lab_enabled else "off",
            f"on/{c.technical_fallback_strong_min_score:.0f}" if c.technical_fallback_strong_mode else "off",
            c.min_symbol_price_usdt,
            c.score_entry,
            "paper" if c.paper_trading else "armed",
            (c.decision_min_consensus if c.paper_trading else c.decision_live_min_consensus) * 100,
        )

    def _tradingview_opportunities(self) -> List[Dict]:
        """
        Build auto-entry opportunities from live TradingView TA ratings.

        Refreshes ratings every tradingview_refresh_sec, then for each symbol
        rated Strong-Buy/Buy (LONG) or Strong-Sell/Sell (SHORT) builds an
        opportunity (current price + ATR) shaped like a scanner opportunity, so
        it flows through the SAME risk checks, sizing and exchange SL/TP.
        """
        if not (self.config.tradingview_signals and self.tv_signals.available):
            return []
        syms = self._scanner_universe_cache[:self.config.scan_top_n]
        if not syms:
            return []

        now = time.time()
        if now - self._tv_last_fetch >= self.config.tradingview_refresh_sec or self._tv_cache_opps is None:
            self.monitor.report("News", "tradingview",
                                f"מושך דירוגי TradingView ל-{len(syms)} מטבעות", status="working")
            sigs = self.tv_signals.fetch(syms)
            self._tv_last_fetch = now
            opps: List[Dict] = []
            for sym, sig in sigs.items():
                if not sig.get("direction") or sig.get("strength", 0.0) < self.config.tradingview_min_strength:
                    continue
                df = fetch_ohlcv(sym, interval=self.config.hft_timeframe, limit=50)
                if df is None or len(df) < 15:
                    continue
                price = float(df["close"].iloc[-1])
                if price < self.config.min_symbol_price_usdt:
                    continue
                highs = df["high"].to_numpy()[-14:]
                lows = df["low"].to_numpy()[-14:]
                atr = float((highs - lows).mean()) if len(highs) else price * 0.005
                opps.append({
                    "symbol": sym,
                    "direction": sig["direction"],
                    "score": sig["strength"] * 100.0,
                    "entry_price": price,
                    "atr": atr,
                    "signal_ts": time.time(),
                    "source": "tradingview",
                })
            opps.sort(key=lambda o: o["score"], reverse=True)
            self._tv_cache_opps = opps
            self.monitor.report("News", "tradingview",
                                f"TradingView: {len(opps)} סיגנלים חזקים לכניסה", status="active", force=True)

        # Drop symbols we're already in
        return [o for o in (self._tv_cache_opps or []) if o["symbol"] not in self.risk_agent.open_positions]

    def run(self, start_dashboard: bool = True) -> None:
        """
        Main trading loop.

        If aggressive_hft is True:
          - Scanner discovers universe once per 100 loops
          - Scans and ranks opportunities
          - Risk assesses and executes entries
          - Checks exits and executes closes
          - Capital rotates immediately after close (no idle time)

        If aggressive_hft is False:
          - Classic pipeline: fetch OHLCV → analyze → signal → risk → execute
          - Process each configured symbol in sequence
          - Update positions and check exits
          - Sleep poll_interval_seconds
        """
        self.running = True
        logger.info("TradingSystem starting (HFT mode: %s)", self.config.aggressive_hft)

        # Signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)

        # Start dashboard if requested
        if start_dashboard:
            self.start_dashboard()

        try:
            if self.config.aggressive_hft:
                self._run_hft_loop()
            else:
                self._run_classic_loop()
        except Exception as exc:
            logger.exception("Unhandled exception in main loop: %s", exc)
        finally:
            self.running = False
            self.stop_dashboard()
            logger.info("TradingSystem stopped")

    def _run_hft_loop(self) -> None:
        """
        HFT mode: rapid scanning and execution with capital rotation.
        Loop frequency: ~20 Hz (50ms sleep).
        """
        logger.info("Entering HFT mode loop (sleep_ms=%d)", self.config.loop_sleep_ms)
        loop_start = time.time()

        # Send startup notification
        mode = "PAPER" if self.config.paper_trading else "LIVE"
        self.tg.startup(
            mode=mode,
            balance=self.risk_agent._current_balance,
            max_positions=self.config.hft_max_open_positions,
        )

        while self.running and not self.kill_state.active:
            loop_iteration_start = time.time()
            self.monitor.set_loop(self._loop_count)

            try:
                # 1. Discover universe once per 100 loops
                if self._loop_count % 100 == 0:
                    logger.info("Discovery cycle (loop %d)", self._loop_count)
                    self.monitor.report(
                        "Scanner", "discover", "מגלה יקום מסחר — מסנן נזילות, מחיר ונפח",
                        status="working", force=True,
                    )
                    self._scanner_universe_cache = self.scanner.discover_universe()
                    self.monitor.report(
                        "Scanner", "discover",
                        f"יקום עודכן: {len(self._scanner_universe_cache)} סימבולים פעילים",
                        status="active", force=True,
                    )
                    if not self._scanner_universe_cache:
                        logger.warning("Failed to discover universe, retrying next cycle")
                        self._loop_count += 1
                        time.sleep(self.config.loop_sleep_ms / 1000.0)
                        continue

                # 1b. Refresh trade analyzer every 50 loops — learn from history
                # News/sentiment refresh (self-throttled to refresh_seconds)
                if self._loop_count % 20 == 0:
                    try:
                        self.news_agent.maybe_refresh()
                    except Exception as exc:
                        logger.debug("news refresh failed: %s", exc)
                    if self.config.catalyst_agent_enabled:
                        try:
                            self.catalyst_agent.maybe_refresh()
                        except Exception as exc:
                            logger.debug("catalyst refresh failed: %s", exc)
                    try:
                        self.market_regime_agent.maybe_refresh()
                    except Exception as exc:
                        logger.debug("market regime refresh failed: %s", exc)

                if (
                    self.config.strategy_lab_enabled
                    and self._loop_count % self.config.strategy_lab_refresh_loops == 0
                ):
                    try:
                        self.strategy_lab.refresh()
                    except Exception as exc:
                        logger.debug("strategy lab refresh failed: %s", exc)

                if (
                    self.config.opportunity_radar_enabled
                    and self._loop_count % self.config.opportunity_radar_refresh_loops == 0
                ):
                    try:
                        self.opportunity_radar.refresh()
                    except Exception as exc:
                        logger.debug("opportunity radar refresh failed: %s", exc)

                # Exchange-side SL/TP can close a live position before the
                # local exit rules fire. Reconcile every HFT pass so closed
                # trades free slots for new opportunities immediately.
                self._reconcile_live_exchange_fills()
                self._run_live_health_check()
                if self.risk_agent.open_positions:
                    self._handle_exits_only(opportunities=[])
                    if not self.running or self.kill_state.active:
                        break

                if self._loop_count % 50 == 0 and self._loop_count > 0:
                    self.monitor.report(
                        "Analyzer", "learn", "לומד מהיסטוריית עסקאות — win-rate, Kelly, רשימה שחורה",
                        status="working", force=True,
                    )
                    insights = self.trade_analyzer.refresh()
                    if insights.has_enough_data:
                        self.monitor.report(
                            "Analyzer", "learn",
                            f"wr={insights.recent_win_rate * 100:.0f}% | "
                            f"score→{insights.adjusted_score_entry:.0f} | "
                            f"kelly={insights.kelly_fraction:.2f} | "
                            f"blacklist={len(insights.symbol_blacklist)} | "
                            f"model={'בריא' if insights.model_healthy else 'חולה'}",
                            status="active",
                            severity="INFO" if insights.model_healthy else "WARNING",
                            force=True,
                        )
                        # Feed all insights into risk manager
                        self.risk_agent._adaptive_score_entry = insights.adjusted_score_entry
                        self.risk_agent._bad_exit_reasons = insights.bad_close_reasons
                        self.risk_agent._kelly_fraction = insights.kelly_fraction
                        self.risk_agent._performance_multiplier = insights.performance_size_multiplier
                        self.risk_agent._bad_hours_utc = insights.bad_hours_utc
                        self.risk_agent._sl_multiplier = insights.sl_multiplier
                        self.risk_agent._tp_multiplier = insights.tp_multiplier
                        self.risk_agent._model_healthy = insights.model_healthy
                        # Log key insights
                        if insights.symbol_blacklist:
                            logger.info(
                                "TradeAnalyzer: blacklisted symbols: %s",
                                ", ".join(sorted(insights.symbol_blacklist)),
                            )
                        if insights.bad_close_reasons:
                            logger.info(
                                "TradeAnalyzer: bad exit reasons: %s",
                                ", ".join(sorted(insights.bad_close_reasons)),
                            )
                        if not insights.model_healthy:
                            if self.config.block_when_model_unhealthy:
                                logger.critical(
                                    "TradeAnalyzer: MODEL UNHEALTHY — entries blocked until model improves"
                                )
                            else:
                                logger.warning(
                                    "TradeAnalyzer: MODEL UNHEALTHY — continuing because "
                                    "BLOCK_WHEN_MODEL_UNHEALTHY=false; committee/guards still apply"
                                )
                        # Telegram intelligence update (every 5th refresh = ~250 loops)
                        if self._refresh_count_tg % 5 == 0:
                            self.tg.intelligence_update(
                                win_rate=insights.recent_win_rate * 100,
                                score_entry=insights.adjusted_score_entry,
                                kelly=insights.kelly_fraction,
                                blacklist_count=len(insights.symbol_blacklist),
                                sl_mult=insights.sl_multiplier,
                                tp_mult=insights.tp_multiplier,
                                model_healthy=insights.model_healthy,
                            )
                        self._refresh_count_tg += 1

                # 1c. Check cooldown (real-time, every loop)
                if self.trade_analyzer.is_in_cooldown():
                    # Send cooldown notification once
                    ins = self.trade_analyzer.insights
                    self.monitor.report(
                        "Analyzer", "cooldown",
                        f"בקירור — {ins.cooldown_reason or 'הגנה אחרי רצף הפסדים'}",
                        status="paused", severity="WARNING",
                    )
                    if ins.cooldown_active and self._loop_count % 50 == 0:
                        remaining_min = max(0, (ins.cooldown_until - time.time()) / 60)
                        self.tg.cooldown(ins.cooldown_reason, remaining_min)
                    # During cooldown: still check exits but don't enter new trades
                    self._handle_exits_only(opportunities=[])
                    self._loop_count += 1
                    time.sleep(self.config.loop_sleep_ms / 1000.0)
                    continue

                # 1d. Check if current hour is historically bad
                if self.trade_analyzer.is_bad_hour():
                    logger.debug("Bad hour (UTC %02d) — skipping entries", datetime.now(timezone.utc).hour)
                    self.monitor.report(
                        "Analyzer", "bad_hour",
                        f"שעה היסטורית חלשה (UTC {datetime.now(timezone.utc).hour:02d}) — רק יציאות",
                        status="paused", severity="WARNING",
                    )
                    self._handle_exits_only(opportunities=[])
                    self._loop_count += 1
                    time.sleep(self.config.loop_sleep_ms / 1000.0)
                    continue

                # 2. Tick throttle cooldowns
                self.scanner.tick_throttles()

                # 3. Scan and rank opportunities (with trade quality filters)
                scan_symbols = list(self._scanner_universe_cache)
                scan_n = len(scan_symbols)
                self.monitor.report(
                    "Scanner", "scan",
                    f"סורק {scan_n} סימבולים — נפח, חדשים, מומנטום, ספרד, pullback",
                    status="working",
                )
                opportunities = self.scanner.scan_and_rank(
                    symbols=scan_symbols
                )
                if not self.running:
                    break
                top = opportunities[0] if opportunities else None
                self.monitor.report(
                    "Scanner", "rank",
                    f"מצא {len(opportunities)} הזדמנויות מדורגות",
                    status="active",
                )
                if top:
                    self.monitor.report(
                        "Model", "score",
                        f"ציון מוביל {top.get('symbol','')}={top.get('score',0):.0f} "
                        f"({top.get('direction','')})",
                        symbol=top.get("symbol", ""),
                        status="active",
                    )

                # Merge TradingView-driven entries (auto-trade on TA ratings)
                tv_opps = self._tradingview_opportunities()
                if not self.running:
                    break
                if tv_opps:
                    have = {o.get("symbol") for o in opportunities}
                    opportunities.extend(o for o in tv_opps if o["symbol"] not in have)
                    opportunities.sort(key=lambda o: o.get("score", 0), reverse=True)

                # 4. Process opportunities: evaluate → enter
                for opp in opportunities:
                    if not self.running:
                        break
                    symbol = opp.get("symbol", "")
                    score = opp.get("score", 0)
                    direction = opp.get("direction", "LONG")
                    entry_price = opp.get("entry_price", 0)
                    atr = opp.get("atr", 0)
                    signal_ts = opp.get("signal_ts", 0)

                    if not symbol or score < self.config.score_entry:
                        continue

                    committee = self.decision_committee.evaluate(
                        opp,
                        news_agent=self.news_agent,
                        catalyst_agent=self.catalyst_agent if self.config.catalyst_agent_enabled else None,
                        regime_agent=self.market_regime_agent,
                        flow_agent=self.flow_agent,
                        capital_agent=self.capital_allocator,
                        indirect_agent=self.indirect_strategy,
                        open_positions=self.risk_agent.open_positions,
                        drawdown_pct=self.risk_agent.drawdown_pct,
                    )
                    if not committee.approved:
                        logger.debug(
                            "%s: committee rejected — consensus=%.0f%% score=%.1f reasons=%s",
                            symbol,
                            committee.consensus * 100,
                            committee.adjusted_score,
                            " | ".join(committee.hard_blocks or committee.reasons[-2:]),
                        )
                        continue
                    score = committee.adjusted_score

                    # Correlation guard: don't open correlated pairs simultaneously
                    corr_conflict = self.trade_analyzer.check_correlation(
                        symbol, self.risk_agent.open_positions
                    )
                    if corr_conflict:
                        logger.debug(
                            "%s: SKIPPED — correlated with open position %s",
                            symbol, corr_conflict,
                        )
                        continue

                    # Risk assessment
                    self.monitor.report(
                        "RiskManager", "evaluate",
                        f"בודק {symbol} (ציון {score:.0f}) — drawdown, מרג'ין, מתאם, Kelly",
                        symbol=symbol, status="working",
                    )
                    decision = self.risk_agent.evaluate(
                        symbol=symbol,
                        score=score,
                        direction=direction,
                        entry_price=entry_price,
                        atr=atr,
                        current_balance=self.risk_agent._current_balance,
                        open_positions=self.risk_agent.open_positions,
                        size_multiplier=committee.size_multiplier,
                    )

                    if not decision.approved:
                        self.monitor.report(
                            "RiskManager", "reject",
                            f"{symbol} נדחה — {getattr(decision, 'rejection_reason', '') or 'מחוץ לכללי הסיכון'}",
                            symbol=symbol, status="active",
                        )

                    if decision.approved:
                        if "runner" in (decision.reason or ""):
                            self.monitor.report(
                                "Runner",
                                "armed_trade",
                                f"{symbol} {direction} runner mode — TP רחב ונעילת רווח מאוחרת",
                                symbol=symbol,
                                status="working",
                                force=True,
                            )
                        order_quantity = decision.quantity
                        self.monitor.report(
                            "RiskManager", "approve",
                            f"{symbol} {direction} אושר — qty={decision.quantity:.4f} "
                            f"SL={decision.sl_price:.6f} TP={decision.tp_price:.6f}",
                            symbol=symbol, status="active", severity="INFO", force=True,
                        )
                        # Refresh live available balance before placing a real order.
                        if not self.config.paper_trading:
                            try:
                                from agents.binance_compat import live_full_account_info

                                rounded_qty = self.execution_agent._round_quantity(
                                    symbol, decision.quantity
                                )
                                filters = self.execution_agent._exchange_filters.get(symbol, {})
                                min_qty = float(filters.get("min_qty", 0) or 0)
                                min_notional = float(
                                    filters.get("min_notional", 0)
                                    or self.config.hft_min_notional_usdt
                                    or 0
                                )
                                rounded_notional = rounded_qty * entry_price
                                if (
                                    rounded_qty <= 0
                                    or (min_qty > 0 and rounded_qty < min_qty)
                                    or (min_notional > 0 and rounded_notional < min_notional)
                                ):
                                    reason = (
                                        f"{symbol}: live qty too small after Binance rounding "
                                        f"(raw={decision.quantity:.8f}, rounded={rounded_qty:.8f}, "
                                        f"notional={rounded_notional:.2f}, min_qty={min_qty:.8f}, "
                                        f"min_notional={min_notional:.2f})"
                                    )
                                    logger.warning("Skipping %s: %s", symbol, reason)
                                    self.monitor.report(
                                        "LiveGuard",
                                        "reject",
                                        reason,
                                        symbol=symbol,
                                        status="active",
                                        severity="WARNING",
                                        force=True,
                                    )
                                    if self.scanner:
                                        self.scanner._runtime_blacklist.add(symbol)
                                    continue
                                order_quantity = rounded_qty

                                _acc = live_full_account_info(self.execution_agent.client)
                                if _acc:
                                    live_avail = _acc["available_balance"]
                                    live_equity = _acc["margin_balance"]
                                    self.risk_agent._current_balance = live_equity
                                    required_margin = (order_quantity * entry_price) / self.config.leverage
                                    notional = order_quantity * entry_price
                                    live_check = self.live_guard.pre_trade_check(
                                        symbol=symbol,
                                        notional=notional,
                                        required_margin=required_margin,
                                        live_available=live_avail,
                                        live_equity=live_equity,
                                    )
                                    if not live_check.approved:
                                        logger.warning("Skipping %s: %s", symbol, live_check.reason)
                                        self.monitor.report(
                                            "LiveGuard",
                                            "reject",
                                            live_check.reason,
                                            symbol=symbol,
                                            status="active",
                                            severity="WARNING",
                                            force=True,
                                        )
                                        continue
                            except Exception as _be:
                                logger.warning("Live balance pre-check failed for %s: %s", symbol, _be)
                                self.monitor.report(
                                    "LiveGuard",
                                    "reject",
                                    f"{symbol}: live balance pre-check failed",
                                    symbol=symbol,
                                    status="active",
                                    severity="ERROR",
                                    force=True,
                                )
                                continue

                        # Execute HFT entry (with slippage/latency tracking)
                        if not self.running:
                            break
                        result = self.execution_agent.hft_open(
                            symbol=symbol,
                            direction="LONG" if direction == "LONG" else "SHORT",
                            quantity=order_quantity,
                            entry_price=entry_price,
                            sl=decision.sl_price,
                            tp=decision.tp_price,
                            confidence=score,
                            signal_ts=signal_ts,
                        )
                        if result:
                            logger.info(
                                "HFT ENTRY: %s @ %.6f | Score=%.1f | Slip=%.4f%% | Lat=%.0fms",
                                symbol, entry_price, score,
                                self.execution_agent._last_slippage * 100,
                                self.execution_agent._last_latency_ms,
                            )
                            self.monitor.report(
                                "Execution", "entry",
                                f"נכנס {direction} {symbol} @ {entry_price:.6f} | "
                                f"slip={self.execution_agent._last_slippage * 100:.3f}% "
                                f"lat={self.execution_agent._last_latency_ms:.0f}ms"
                                + ("" if self.config.paper_trading else " | SL/TP נשלחו לבורסה"),
                                symbol=symbol, status="active", severity="INFO", force=True,
                            )

                            # Track slippage/latency strikes for throttling
                            if (self.execution_agent._last_slippage > self.config.max_slippage_pct or
                                    self.execution_agent._last_latency_ms > self.config.max_latency_ms):
                                self.scanner.record_slippage_strike(symbol)
                                logger.warning(
                                    "Slippage/latency strike on %s: slip=%.4f%% lat=%.0fms",
                                    symbol, self.execution_agent._last_slippage * 100,
                                    self.execution_agent._last_latency_ms,
                                )

                            self.tg.entry(
                                symbol=symbol,
                                direction=direction,
                                qty=order_quantity,
                                price=entry_price,
                                sl=decision.sl_price,
                                tp=decision.tp_price,
                                score=score,
                                balance=self.risk_agent._current_balance,
                            )
                        else:
                            # Check last Binance error code to decide whether to skip or stop
                            last_err = getattr(self.execution_agent, '_last_error_code', None)
                            if last_err in (-4411, -4003, -1121):
                                logger.warning("Blacklisting %s (API code %s), trying next", symbol, last_err)
                                if self.scanner:
                                    self.scanner._runtime_blacklist.add(symbol)
                                continue
                            logger.warning("Order failed for %s (code=%s), skipping scan pass", symbol, last_err)
                            break

                if not self.running:
                    break

                # 5. Check exits for open positions
                positions_to_close: List[Tuple[str, Position, str]] = []
                current_prices = {}
                for opp in opportunities:
                    s = opp.get("symbol", "")
                    if s:
                        current_prices[s] = opp.get("entry_price", 0)

                # Fetch fresh prices for open positions not in scan results
                for sym in self.risk_agent.open_positions:
                    if sym not in current_prices:
                        px = self._get_current_price_from_market(sym)
                        if px > 0:
                            current_prices[sym] = px

                if self.risk_agent.open_positions:
                    self.monitor.report(
                        "RiskManager", "guard",
                        f"שומר על {len(self.risk_agent.open_positions)} פוזיציות — SL/TP, trailing, stale",
                        status="active",
                    )
                exit_signals = self.risk_agent.check_exits(
                    positions=self.risk_agent.open_positions,
                    prices=current_prices,
                )
                for sig in exit_signals:
                    sig_symbol = sig["symbol"]
                    sig_reason = sig["reason"]
                    if sig_symbol in self.risk_agent.open_positions:
                        positions_to_close.append((sig_symbol, self.risk_agent.open_positions[sig_symbol], sig_reason))

                # 6. Execute exits
                for symbol, position, reason in positions_to_close:
                    current_price = self._get_current_price(symbol, opportunities)
                    if current_price > 0:
                        result = self.execution_agent.hft_close(
                            symbol=symbol,
                            current_price=current_price,
                            reason=reason,
                        )
                        if result:
                            self._record_trade_result(symbol, result)
                            self._session_pnl += result.get("pnl", 0)
                            self._session_trades += 1
                            _pnl = result.get("pnl", 0)
                            self.monitor.report(
                                "Execution", "exit",
                                f"סגר {symbol} @ {result.get('exit_price', 0):.6f} | "
                                f"PnL={_pnl:+.4f} ({result.get('pnl_pct', 0) * 100:+.2f}%) | {reason}",
                                symbol=symbol, status="active",
                                severity="INFO" if _pnl >= 0 else "WARNING", force=True,
                            )
                            self.tg.exit(
                                symbol=symbol,
                                direction=result.get("side", ""),
                                entry=result.get("entry_price", 0),
                                exit_price=result.get("exit_price", 0),
                                pnl=result.get("pnl", 0),
                                pnl_pct=result.get("pnl_pct", 0),
                                reason=reason,
                                balance=self.risk_agent._current_balance,
                            )

                # 7. Save portfolio snapshot
                self._save_portfolio_snapshot()

                # 8. Check drawdown and activate kill switch if needed
                self._check_drawdown()
                if self.kill_state.active:
                    self.monitor.report(
                        "RiskManager", "kill_switch",
                        f"KILL SWITCH הופעל — {getattr(self.kill_state, 'reason', '') or 'חריגת drawdown'}",
                        status="stopped", severity="ERROR", force=True,
                    )

                # 9. Update loop counter
                self._loop_count += 1
                self.monitor.report(
                    "System", "heartbeat",
                    f"לולאה #{self._loop_count} | מאזן={self.risk_agent._current_balance:,.2f} | "
                    f"פתוחות={len(self.risk_agent.open_positions)} | PnL סשן={self._session_pnl:+.2f}",
                    status="active",
                )

                # 10. Telegram heartbeat every N seconds
                now_ts = time.time()
                hb_interval = self.config.telegram_heartbeat_interval
                if now_ts - self._last_heartbeat >= hb_interval:
                    self._last_heartbeat = now_ts
                    self.tg.heartbeat(
                        balance=self.risk_agent._current_balance,
                        open_positions=len(self.risk_agent.open_positions),
                        session_pnl=self._session_pnl,
                        n_trades=self._session_trades,
                    )

            except Exception as exc:
                logger.exception("Error in HFT loop iteration: %s", exc)

            # 11. Sleep for loop frequency
            elapsed_ms = (time.time() - loop_iteration_start) * 1000
            sleep_ms = max(1, self.config.loop_sleep_ms - int(elapsed_ms))
            sleep_s = sleep_ms / 1000.0
            time.sleep(sleep_s)

            # Log execution latency every 100 loops
            if self._loop_count % 100 == 0:
                total_elapsed = time.time() - loop_start
                avg_loop_time = (total_elapsed / self._loop_count) * 1000
                logger.info("HFT latency: avg=%.2f ms/loop (total=%d loops)", avg_loop_time, self._loop_count)

    def _run_classic_loop(self) -> None:
        """
        Classic mode: process each configured symbol on poll_interval schedule.
        """
        logger.info("Entering classic mode loop (poll_interval=%ds)", self.config.poll_interval_seconds)
        next_poll = time.time()

        while self.running and not self.kill_state.active:
            try:
                # 1. Process each symbol
                market_data_dict: Dict[str, Optional[MarketData]] = {}
                for symbol in self.config.symbols:
                    if not self.running:
                        break
                    ohlcv = fetch_ohlcv(
                        symbol,
                        interval=self.config.timeframe,
                        limit=self.config.fetch_limit,
                    )
                    if ohlcv is not None:
                        market_data = self.market_agent.analyze(symbol, ohlcv)
                        if market_data:
                            self._process_symbol(symbol, market_data)
                            market_data_dict[symbol] = market_data

                # 2. Update open positions (SL/TP checks)
                if self.risk_agent.open_positions:
                    prices = {
                        symbol: market_data_dict.get(symbol).current_price
                        for symbol in market_data_dict
                        if market_data_dict.get(symbol)
                    }
                    exit_decisions = self.risk_agent.check_exits(
                        positions=self.risk_agent.open_positions,
                        prices=prices,
                    )
                    for exit_sig in (exit_decisions or []):
                        symbol = exit_sig["symbol"]
                        reason = exit_sig["reason"]
                        if symbol in self.risk_agent.open_positions:
                            current_price = prices.get(symbol, 0)
                            if current_price > 0:
                                self.execution_agent.close_position(
                                    symbol=symbol,
                                    reason=reason,
                                    current_price=current_price,
                                )

                # 3. Save portfolio snapshot
                self._save_portfolio_snapshot()

                # 4. Check drawdown
                self._check_drawdown()

                # 5. Sleep until next poll interval
                next_poll += self.config.poll_interval_seconds
                now = time.time()
                if next_poll > now:
                    time.sleep(next_poll - now)

            except Exception as exc:
                logger.exception("Error in classic loop iteration: %s", exc)
                time.sleep(1)

    def _process_symbol(self, symbol: str, market_data: MarketData) -> None:
        """
        Classic mode: process a single symbol through the strategy pipeline.
        """
        try:
            # Generate strategy signal
            signal = self.strategy_agent.generate_signal(market_data)
            if signal is None:
                return

            committee = self.decision_committee.evaluate(
                {
                    "symbol": symbol,
                    "direction": signal.direction,
                    "score": signal.confidence * 100.0,
                    "entry_price": market_data.current_price,
                    "atr": market_data.atr,
                    "source": "classic",
                },
                news_agent=self.news_agent,
                catalyst_agent=self.catalyst_agent if self.config.catalyst_agent_enabled else None,
                regime_agent=self.market_regime_agent,
                flow_agent=self.flow_agent,
                capital_agent=self.capital_allocator,
                indirect_agent=self.indirect_strategy,
                open_positions=self.risk_agent.open_positions,
                drawdown_pct=self.risk_agent.drawdown_pct,
            )
            if not committee.approved:
                return
            signal.confidence = max(0.0, min(1.0, committee.adjusted_score / 100.0))

            # Save signal to DB
            self.repo.insert_signal({
                "symbol": symbol,
                "direction": signal.direction,
                "confidence": signal.confidence,
                "regime": signal.regime,
                "trend": signal.trend,
                "volatility": signal.volatility,
                "rf_prob": signal.rf_prob,
                "gb_prob": signal.gb_prob,
                "lr_prob": signal.lr_prob,
                "ensemble_prob": signal.ensemble_prob,
                "created_at": market_data.timestamp.isoformat(),
            })

            # Check if we should open a position
            should_open, reason = self.risk_agent.should_open_position(
                signal=signal,
                open_positions=self.risk_agent.open_positions,
                killed=self.kill_state.active,
            )

            if not should_open:
                return

            # Risk assessment
            risk_assessment = self.risk_agent.assess_risk(signal, market_data)

            # Execute the trade
            self.execution_agent.execute_signal(
                signal=signal,
                risk_assessment=risk_assessment,
                market_data=market_data,
            )

        except Exception as exc:
            logger.exception("Error processing symbol %s: %s", symbol, exc)

    def _handle_exits_only(self, opportunities: List[Dict]) -> None:
        """
        During cooldown / bad hours: only check and execute exits, no new entries.
        Still protects capital by honoring SL/TP/trailing/stale exits.
        """
        try:
            self._reconcile_live_exchange_fills()
            current_prices = {}
            for opp in opportunities:
                s = opp.get("symbol", "")
                if s:
                    current_prices[s] = opp.get("entry_price", 0)

            for sym in self.risk_agent.open_positions:
                if sym not in current_prices:
                    px = self._get_current_price_from_market(sym)
                    if px > 0:
                        current_prices[sym] = px

            exit_signals = self.risk_agent.check_exits(
                positions=self.risk_agent.open_positions,
                prices=current_prices,
            )
            for sig in exit_signals:
                sig_symbol = sig["symbol"]
                sig_reason = sig["reason"]
                if sig_symbol in self.risk_agent.open_positions:
                    current_price = current_prices.get(sig_symbol, 0)
                    if current_price > 0:
                        result = self.execution_agent.hft_close(
                            symbol=sig_symbol,
                            current_price=current_price,
                            reason=sig_reason,
                        )
                        if result:
                            self._record_trade_result(sig_symbol, result)
                            self._session_pnl += result.get("pnl", 0)
                            self._session_trades += 1
                            self.tg.exit(
                                symbol=sig_symbol,
                                direction=result.get("side", ""),
                                entry=result.get("entry_price", 0),
                                exit_price=result.get("exit_price", 0),
                                pnl=result.get("pnl", 0),
                                pnl_pct=result.get("pnl_pct", 0),
                                reason=sig_reason,
                                balance=self.risk_agent._current_balance,
                            )

            self._save_portfolio_snapshot()
            self._check_drawdown()
        except Exception as exc:
            logger.exception("Error in exits-only handler: %s", exc)

    def _adopt_untracked_live_position(self, live_pos: Dict) -> bool:
        """
        Register a live Binance position that is missing from local risk state
        (loop restart, stall, or manual/external entry) so stale exits,
        drawdown checks and protection repair apply to it — and make sure it
        carries exchange-side SL/TP if it has none.
        """
        sym = str(live_pos.get("symbol", ""))
        amt = float(live_pos.get("positionAmt", 0) or 0)
        entry = float(live_pos.get("entryPrice", 0) or 0)
        if not sym or amt == 0 or entry <= 0:
            return False
        side = "LONG" if amt > 0 else "SHORT"

        db_trade = None
        try:
            for t in self.repo.get_open_trades():
                if t.get("symbol") == sym:
                    db_trade = t
                    break
        except Exception:
            db_trade = None

        trade_id = db_trade.get("id") if db_trade else None
        opened_at = datetime.now(timezone.utc)
        if db_trade and db_trade.get("opened_at"):
            try:
                opened_at = datetime.fromisoformat(
                    str(db_trade["opened_at"]).replace("Z", "+00:00")
                )
            except ValueError:
                pass

        sl_price = float(db_trade.get("sl_price") or 0) if db_trade else 0.0
        tp_price = float(db_trade.get("tp_price") or 0) if db_trade else 0.0
        if sl_price <= 0 or tp_price <= 0:
            try:
                klines = self.execution_agent.client.futures_klines(
                    symbol=sym, interval=self.config.hft_timeframe, limit=20
                )
                highs = [float(k[2]) for k in klines]
                lows = [float(k[3]) for k in klines]
                trs = [h - l for h, l in zip(highs, lows)]
                atr = sum(trs[-14:]) / min(len(trs), 14) if trs else entry * 0.005
                sl_price, tp_price = self.risk_agent.calculate_sl_tp(entry, side, atr)
            except Exception:
                sl_price = entry * (0.995 if side == "LONG" else 1.005)
                tp_price = entry * (1.005 if side == "LONG" else 0.995)

        if db_trade is None:
            try:
                trade_id = self.repo.insert_trade(
                    {
                        "symbol": sym,
                        "side": side,
                        "entry_price": entry,
                        "exit_price": None,
                        "quantity": abs(amt),
                        "sl_price": sl_price,
                        "tp_price": tp_price,
                        "status": "open",
                        "pnl": None,
                        "pnl_pct": None,
                        "opened_at": opened_at.isoformat(),
                        "closed_at": None,
                        "close_reason": None,
                        "confidence": None,
                        "strategy_signal": "HEALTH_ADOPT",
                    }
                )
            except Exception as exc:
                logger.warning("Could not persist adopted position %s: %s", sym, exc)

        self.risk_agent.open_positions[sym] = Position(
            symbol=sym,
            side=side,
            entry_price=entry,
            quantity=abs(amt),
            sl_price=sl_price,
            tp_price=tp_price,
            opened_at=opened_at,
            trade_id=trade_id,
            unrealized_pnl=float(live_pos.get("unrealizedProfit", 0) or 0),
        )
        self.repo.log_event(
            "HEALTH_REPAIR",
            f"Adopted untracked live position {side} {sym} qty={abs(amt):.8f} @ {entry:.6f}",
            "WARNING",
        )
        logger.warning(
            "Adopted untracked live position: %s %s qty=%.4f entry=%.4f sl=%.4f tp=%.4f",
            side, sym, abs(amt), entry, sl_price, tp_price,
        )

        # Keep any protection already resting on the exchange (do not move an
        # existing stop); only place SL/TP when the position has none.
        if self.config.health_repair_protection_enabled:
            try:
                orders = self.execution_agent.get_protective_orders(sym)
                if not (orders.get("ok") and orders.get("sl", 0) > 0):
                    protective = self.execution_agent.place_protective_orders(
                        sym, side, sl_price, tp_price
                    )
                    if not protective.get("sl_order_id"):
                        logger.critical(
                            "Adopted live position %s has no exchange-side stop-loss protection",
                            sym,
                        )
            except Exception as exc:
                logger.warning("Could not protect adopted position %s: %s", sym, exc)
        return True

    def _run_live_health_check(self) -> None:
        """Periodic live health check and protection self-repair."""
        if (
            self.config.paper_trading
            or not self.config.health_check_enabled
            or self.config.health_check_seconds <= 0
        ):
            return
        now = time.time()
        if now - self._last_health_check < self.config.health_check_seconds:
            return
        self._last_health_check = now

        try:
            from agents.binance_compat import live_full_account_info

            acc = live_full_account_info(self.execution_agent.client)
            if not acc:
                self.monitor.report(
                    "Supervisor",
                    "health",
                    "Binance health snapshot unavailable",
                    status="paused",
                    severity="WARNING",
                )
                return

            live_positions = acc.get("positions", [])
            live_symbols = {p.get("symbol", "") for p in live_positions}
            repaired = []
            missing = []

            for live_pos in live_positions:
                symbol = str(live_pos.get("symbol", ""))
                live_leverage = int(live_pos.get("leverage", 0) or 0)
                target_leverage = min(int(self.config.leverage), int(self.config.live_max_leverage))
                if live_leverage and live_leverage != target_leverage:
                    if self.execution_agent.set_leverage(
                        symbol,
                        target_leverage,
                        force=True,
                    ):
                        repaired.append(f"{symbol}:leverage")
                        self.repo.log_event(
                            "HEALTH_REPAIR",
                            (
                                f"Adjusted leverage for {symbol}: "
                                f"{live_leverage}x -> {target_leverage}x"
                            ),
                            "WARNING",
                        )
                    else:
                        missing.append(
                            f"{symbol}: leverage {live_leverage}x != {target_leverage}x"
                        )

                rm_pos = self.risk_agent.open_positions.get(symbol)
                if rm_pos is None:
                    if self._adopt_untracked_live_position(live_pos):
                        repaired.append(f"{symbol}:adopted")
                    else:
                        missing.append(f"{symbol}: live position not in local risk state")
                    continue

                orders = self.execution_agent.get_protective_orders(symbol)
                if not orders.get("ok"):
                    missing.append(f"{symbol}: protection check unavailable")
                    continue

                has_sl = orders.get("sl", 0) > 0
                has_tp = orders.get("tp", 0) > 0
                if has_sl and has_tp:
                    continue

                detail = (
                    f"{symbol}: missing protection "
                    f"SL={orders.get('sl', 0)} TP={orders.get('tp', 0)}"
                )
                missing.append(detail)
                if self.config.health_repair_protection_enabled:
                    protective = self.execution_agent.place_protective_orders(
                        symbol,
                        rm_pos.side,
                        rm_pos.sl_price,
                        rm_pos.tp_price,
                    )
                    if protective.get("sl_order_id") and protective.get("tp_order_id"):
                        repaired.append(symbol)
                        self.repo.log_event(
                            "HEALTH_REPAIR",
                            f"Repaired exchange SL/TP protection for {symbol}",
                            "WARNING",
                        )

            orphan_local = [
                sym for sym in self.risk_agent.open_positions.keys() if sym not in live_symbols
            ]
            if orphan_local:
                self._reconcile_live_exchange_fills()

            detail = (
                f"live={len(live_positions)} local={len(self.risk_agent.open_positions)} "
                f"repaired={len(repaired)} equity={acc.get('margin_balance', 0):.2f}"
            )
            if missing:
                detail += " | " + "; ".join(missing[:3])
            self.monitor.report(
                "Supervisor",
                "health",
                detail,
                status="active",
                severity="WARNING" if missing else "INFO",
                force=True,
            )
            logger.info("Live health check: %s", detail)
        except Exception as exc:
            logger.debug("Live health check failed: %s", exc)

    def _reconcile_live_exchange_fills(self) -> None:
        """Close local/DB rows when Binance already closed them via SL/TP."""
        if self.config.paper_trading or not self.risk_agent.open_positions:
            return
        try:
            from agents.binance_compat import live_full_account_info

            acc = live_full_account_info(self.execution_agent.client)
            if not acc:
                return
            live_symbols = {
                str(p.get("symbol", ""))
                for p in acc.get("positions", [])
                if abs(float(p.get("positionAmt", 0) or 0)) > 0
            }

            for symbol in list(self.risk_agent.open_positions.keys()):
                if symbol in live_symbols:
                    continue
                result = self.execution_agent._reconcile_live_flat_position(
                    symbol,
                    current_price=0.0,
                    reason="stop_loss",
                )
                if result and result.get("trade_id"):
                    self.repo.update_trade(
                        int(result["trade_id"]),
                        {
                            "exit_price": result.get("exit_price"),
                            "status": "closed",
                            "pnl": result.get("pnl"),
                            "pnl_pct": result.get("pnl_pct"),
                            "closed_at": result.get("closed_at"),
                            "close_reason": result.get("close_reason"),
                        },
                    )
                    self.repo.log_event(
                        "LIVE_SYNC",
                        (
                            f"Runtime reconciled {symbol}: Binance is flat, "
                            f"reason={result.get('close_reason')} "
                            f"PnL={result.get('pnl', 0):+.6f}"
                        ),
                        "INFO",
                    )
                    self._record_trade_result(symbol, result)
                    self._session_pnl += float(result.get("pnl", 0) or 0)
                    self._session_trades += 1
                    pnl = float(result.get("pnl", 0) or 0)
                    self.monitor.report(
                        "Execution",
                        "exchange_sync",
                        (
                            f"סונכרן {symbol}: Binance סגרה | "
                            f"PnL={pnl:+.4f} | {result.get('close_reason')}"
                        ),
                        symbol=symbol,
                        status="active",
                        severity="INFO" if pnl >= 0 else "WARNING",
                        force=True,
                    )
                self.risk_agent.remove_position(symbol)
        except Exception as exc:
            logger.debug("Runtime live reconciliation failed: %s", exc)

    def _record_trade_result(self, symbol: str, result: Dict) -> None:
        """
        Record a trade result and update rage mode state.

        NOTE: hft_close() already updates the original trade row in DB (open→closed).
        We do NOT insert a new row here — that would create duplicates.
        We only update internal state (rage, cooldown, analyzer).
        """
        try:
            pnl = result.get("pnl", 0)
            pnl_pct = result.get("pnl_pct", 0)

            # DO NOT insert_trade here — hft_close already updates the original row.
            # Only update rage/analyzer state.

            self.risk_agent._trade_history.append(pnl > 0)

            # Real-time cooldown check (immediate, not waiting for DB refresh)
            self.trade_analyzer.record_realtime_result(pnl)

            # Log with trade analyzer context
            was_blacklisted = self.trade_analyzer.should_skip_symbol(symbol)
            hist_adj = self.trade_analyzer.get_score_adjustment(symbol)
            logger.info(
                "Trade recorded: %s | PnL=%.2f (%.2f%%) | hist_adj=%+.1f%s",
                symbol, pnl, pnl_pct, hist_adj,
                " [WOULD-BE-BLACKLISTED]" if was_blacklisted else "",
            )

        except Exception as exc:
            logger.exception("Error recording trade result: %s", exc)

    def _get_live_account_snapshot(self) -> Optional[Dict[str, Any]]:
        """Return a fresh live-account snapshot and refresh local uPnL fields."""
        if self.config.paper_trading:
            return None
        try:
            client = getattr(self.execution_agent, "client", None)
            if client is None:
                return None

            from agents.binance_compat import live_full_account_info

            acc = live_full_account_info(client)
            if not acc:
                return None

            wallet = float(acc.get("wallet_balance", 0.0) or 0.0)
            available = float(acc.get("available_balance", 0.0) or 0.0)
            equity = float(acc.get("margin_balance", 0.0) or 0.0)
            unrealized = float(acc.get("unrealized_pnl", 0.0) or 0.0)
            if equity <= 0 and wallet > 0:
                equity = wallet + unrealized

            for live_pos in acc.get("positions", []):
                sym = str(live_pos.get("symbol", ""))
                rm_pos = self.risk_agent.open_positions.get(sym)
                if rm_pos is not None:
                    rm_pos.unrealized_pnl = float(
                        live_pos.get("unrealizedProfit", 0.0) or 0.0
                    )

            if equity > self.risk_agent.peak_balance:
                self.risk_agent.peak_balance = equity

            return {
                "wallet_balance": wallet,
                "available_balance": available,
                "equity": equity,
                "unrealized_pnl": unrealized,
                "positions": acc.get("positions", []),
            }
        except Exception as exc:
            logger.debug("Live account snapshot failed: %s", exc)
            return None

    def _save_portfolio_snapshot(self) -> None:
        """Save portfolio snapshot to database."""
        try:
            live = self._get_live_account_snapshot()
            if live:
                balance = float(live["wallet_balance"])
                equity = float(live["equity"])
                unrealized_pnl = float(live["unrealized_pnl"])
                open_positions = len(live.get("positions", []))
            else:
                balance = self.risk_agent._current_balance
                equity = balance
                for pos in self.risk_agent.open_positions.values():
                    equity += pos.unrealized_pnl
                unrealized_pnl = sum(
                    p.unrealized_pnl for p in self.risk_agent.open_positions.values()
                )
                open_positions = len(self.risk_agent.open_positions)

            total_pnl = equity - self.risk_agent.session_start_equity
            total_pnl_pct = (
                total_pnl / self.risk_agent.session_start_equity
                if self.risk_agent.session_start_equity > 0
                else 0
            )

            # Calculate win rate
            closed_trades = self.repo.get_trade_history(limit=100)
            wins = sum(1 for t in closed_trades if t.get("pnl", 0) > 0)
            win_rate = (wins / len(closed_trades) * 100) if closed_trades else 0

            self.repo.insert_portfolio_snapshot({
                "balance": balance,
                "equity": equity,
                "total_pnl": total_pnl,
                "total_pnl_pct": total_pnl_pct,
                "unrealized_pnl": unrealized_pnl,
                "open_positions": open_positions,
                "win_rate": win_rate,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })
        except Exception as exc:
            logger.exception("Error saving portfolio snapshot: %s", exc)

    def _check_drawdown(self) -> None:
        """Check if drawdown threshold is breached and activate kill switch if needed."""
        try:
            live = self._get_live_account_snapshot()
            if live:
                current_equity = float(live["equity"])
            else:
                current_equity = self.risk_agent._current_balance
                for pos in self.risk_agent.open_positions.values():
                    current_equity += pos.unrealized_pnl

            if self.risk_agent.peak_balance <= 0:
                self.risk_agent.peak_balance = current_equity

            drawdown = (
                (self.risk_agent.peak_balance - current_equity)
                / self.risk_agent.peak_balance
                if self.risk_agent.peak_balance > 0
                else 0.0
            )
            drawdown = max(0.0, drawdown)
            self.risk_agent._drawdown_pct = drawdown

            if current_equity > self.risk_agent.peak_balance:
                self.risk_agent.peak_balance = current_equity

            if drawdown >= self.config.max_drawdown_pct:
                reason_ks = f"Drawdown {drawdown:.2%} exceeds max {self.config.max_drawdown_pct:.2%}"
                self.risk_agent.kill_switch = True
                self.kill_state.activate(reason_ks)
                self.tg.kill_switch(reason=reason_ks, balance=current_equity)
                # Close all open positions on kill switch
                for symbol, position in list(self.risk_agent.open_positions.items()):
                    current_price = self._get_current_price_from_market(symbol)
                    if current_price > 0:
                        self.execution_agent.close_position(
                            symbol=symbol,
                            reason="KILL_SWITCH",
                            current_price=current_price,
                        )

        except Exception as exc:
            logger.exception("Error checking drawdown: %s", exc)

    def _get_current_price(self, symbol: str, opportunities: List[Dict]) -> float:
        """Get current price from opportunities list or fetch from API."""
        for opp in opportunities:
            if opp.get("symbol") == symbol:
                return opp.get("entry_price", 0)
        return self._get_current_price_from_market(symbol)

    def _get_current_price_from_market(self, symbol: str) -> float:
        """Fetch current price from Binance API."""
        try:
            ohlcv = fetch_ohlcv(symbol, interval="1m", limit=1)
            if ohlcv is not None and len(ohlcv) > 0:
                return float(ohlcv["close"].iloc[-1])
        except Exception as exc:
            logger.exception("Error fetching current price for %s: %s", symbol, exc)
        return 0

    def _handle_signal(self, signum, frame) -> None:
        """Handle graceful shutdown on SIGINT/SIGTERM."""
        logger.info("Received signal %d, initiating graceful shutdown", signum)
        self.running = False

    def start_dashboard(self) -> None:
        """Start the Streamlit dashboard in a subprocess."""
        try:
            # Use venv streamlit path (bare 'streamlit' may not be on PATH in background)
            streamlit_bin = os.path.join(os.path.dirname(sys.executable), "streamlit")
            if not os.path.exists(streamlit_bin):
                streamlit_bin = "streamlit"  # fallback
            if streamlit_bin == "streamlit" and not shutil.which("streamlit"):
                logger.error(
                    "Dashboard NOT started: streamlit is not installed. "
                    "Run: %s -m pip install -r requirements.txt", sys.executable,
                )
                self.dashboard_proc = None
                return
            cmd = [
                streamlit_bin, "run", "dashboard.py",
                "--logger.level=warning",
                f"--server.port={self.config.dashboard_port}",
                "--server.address=0.0.0.0",
                "--server.headless=true",
            ]
            # Capture streamlit output to a log file so failures are visible
            # (previously DEVNULL — the dashboard could die silently).
            dash_log = open("dashboard.log", "a", encoding="utf-8")
            self.dashboard_proc = subprocess.Popen(
                cmd,
                stdout=dash_log,
                stderr=subprocess.STDOUT,
            )
            # Detect immediate failure (e.g. import error) within a moment
            time.sleep(2.0)
            if self.dashboard_proc.poll() is not None:
                logger.error(
                    "Dashboard process exited immediately (code=%s). See dashboard.log for the traceback.",
                    self.dashboard_proc.returncode,
                )
                self.dashboard_proc = None
                return
            logger.info(
                "Dashboard started on port %d (PID=%d) — open http://localhost:%d "
                "(output → dashboard.log)",
                self.config.dashboard_port, self.dashboard_proc.pid, self.config.dashboard_port,
            )
        except Exception as exc:
            logger.warning("Failed to start dashboard: %s", exc)
            self.dashboard_proc = None

    def stop_dashboard(self) -> None:
        """Terminate the dashboard subprocess."""
        if self.dashboard_proc and self.dashboard_proc.poll() is None:
            try:
                self.dashboard_proc.terminate()
                self.dashboard_proc.wait(timeout=5)
                logger.info("Dashboard stopped")
            except subprocess.TimeoutExpired:
                self.dashboard_proc.kill()
                logger.warning("Dashboard killed (timeout)")
            except Exception as exc:
                logger.warning("Error stopping dashboard: %s", exc)


# ---------------------------------------------------------------------------
# CLI and entry point
# ---------------------------------------------------------------------------

def build_config(args) -> TradingConfig:
    """Build TradingConfig from command-line arguments."""
    cfg = TradingConfig()

    if args.symbol:
        cfg.symbols = [args.symbol.upper()]

    if args.balance:
        cfg.paper_initial_balance = args.balance

    if args.live:
        cfg.paper_trading = False
    if args.paper:
        cfg.paper_trading = True

    if args.hft:
        cfg.aggressive_hft = True

    cfg.validate()
    return cfg


def main():
    parser = argparse.ArgumentParser(
        description="Binance Futures Trading Bot — Classic & HFT modes",
    )
    parser.add_argument(
        "--no-dashboard",
        action="store_true",
        help="Disable Streamlit dashboard",
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="Enable live trading (requires API keys in .env)",
    )
    parser.add_argument(
        "--paper",
        action="store_true",
        help="Force paper trading even if .env has PAPER_TRADING=false",
    )
    parser.add_argument(
        "--hft",
        action="store_true",
        help="Force aggressive HFT mode",
    )
    parser.add_argument(
        "--symbol",
        type=str,
        default=None,
        help="Override symbols (single symbol)",
    )
    parser.add_argument(
        "--interval",
        type=str,
        default="1h",
        help="Override timeframe/interval (e.g. 1h, 4h, 1d)",
    )
    parser.add_argument(
        "--balance",
        type=float,
        default=None,
        help="Override initial paper trading balance",
    )

    args = parser.parse_args()
    if args.live and args.paper:
        parser.error("--live and --paper cannot be used together")
    try:
        config = build_config(args)
    except ValueError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        sys.exit(2)

    logger.info(
        "Starting trading bot | Mode=%s | Paper=%s | Symbols=%s",
        "HFT" if config.aggressive_hft else "CLASSIC",
        config.paper_trading,
        ",".join(config.symbols),
    )

    live_lock = None
    if not config.paper_trading:
        live_lock = LiveProcessLock()
        try:
            live_lock.acquire()
        except RuntimeError as exc:
            logger.error("%s", exc)
            print(f"❌ {exc}", file=sys.stderr)
            sys.exit(3)

    try:
        system = TradingSystem(config)
        system.run(start_dashboard=not args.no_dashboard)
    finally:
        if live_lock is not None:
            live_lock.release()


if __name__ == "__main__":
    main()

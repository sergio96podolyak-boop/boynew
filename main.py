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
    python main.py --no-dashboard       # Paper trading, no Streamlit dashboard
    python main.py --live               # Live trading (requires API keys in .env)
    python main.py --symbol BTCUSDT     # Paper trading, single symbol override
    python main.py --hft                # Force aggressive HFT mode
    python main.py --balance 50000      # Override initial balance
"""

import argparse
import logging
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

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


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BINANCE_FUTURES_BASE = "https://fapi.binance.com"


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
            for live_pos in acc_info.get("positions", []):
                sym = live_pos["symbol"]
                amt = live_pos["positionAmt"]
                entry = live_pos["entryPrice"]
                if sym not in self.risk_agent.open_positions and amt != 0 and entry > 0:
                    side = "LONG" if amt > 0 else "SHORT"
                    # Compute SL/TP from ATR like a normal entry (instead of hardcoded 0.5%)
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
                    self.risk_agent.open_positions[sym] = Position(
                        symbol=sym,
                        side=side,
                        entry_price=entry,
                        quantity=abs(amt),
                        sl_price=sl_price,
                        tp_price=tp_price,
                        opened_at=datetime.now(timezone.utc),
                        unrealized_pnl=0.0,
                    )
                    logger.info("Synced existing position: %s %s qty=%.4f entry=%.4f sl=%.4f tp=%.4f",
                                side, sym, abs(amt), entry, sl_price, tp_price)

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
                "TradeAnalyzer loaded: %d recent trades, wr=%.1f%%, score_entry=%.0f, blacklist=%d",
                insights.recent_trade_count, insights.recent_win_rate * 100,
                insights.adjusted_score_entry, len(insights.symbol_blacklist),
            )
            self.risk_agent._adaptive_score_entry = insights.adjusted_score_entry

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

        self._log_safety_rails()

        # Telegram notifier
        self.tg: TelegramNotifier = init_notifier(
            token=config.telegram_token,
            chat_id=config.telegram_chat_id,
        )
        self._session_pnl: float = 0.0
        self._session_trades: int = 0
        self._last_heartbeat: float = 0.0

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
            "min_price=%.2f USDT | score_entry=%.0f",
            c.paper_trading,
            c.aggressive_hft,
            c.leverage,
            max_pos,
            c.max_margin_fraction * 100,
            c.hft_min_notional_usdt,
            c.max_drawdown_pct * 100,
            c.daily_max_drawdown_pct * 100,
            (f"{c.stale_exit_seconds:.0f}s" if c.stale_exit_seconds > 0 else "off"),
            c.min_symbol_price_usdt,
            c.score_entry,
        )

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

            try:
                # 1. Discover universe once per 100 loops
                if self._loop_count % 100 == 0:
                    logger.info("Discovery cycle (loop %d)", self._loop_count)
                    self._scanner_universe_cache = self.scanner.discover_universe()
                    if not self._scanner_universe_cache:
                        logger.warning("Failed to discover universe, retrying next cycle")
                        self._loop_count += 1
                        time.sleep(self.config.loop_sleep_ms / 1000.0)
                        continue

                # 1b. Refresh trade analyzer every 50 loops — learn from history
                if self._loop_count % 50 == 0 and self._loop_count > 0:
                    insights = self.trade_analyzer.refresh()
                    if insights.has_enough_data:
                        self.risk_agent._adaptive_score_entry = insights.adjusted_score_entry
                        self.risk_agent._bad_exit_reasons = insights.bad_close_reasons
                        # Log key insights for monitoring
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

                # 2. Tick throttle cooldowns
                self.scanner.tick_throttles()

                # 3. Scan and rank opportunities (with trade quality filters)
                opportunities = self.scanner.scan_and_rank(
                    symbols=self._scanner_universe_cache[:self.config.scan_top_n]
                )

                # 4. Process opportunities: evaluate → enter
                for opp in opportunities:
                    symbol = opp.get("symbol", "")
                    score = opp.get("score", 0)
                    direction = opp.get("direction", "LONG")
                    entry_price = opp.get("entry_price", 0)
                    atr = opp.get("atr", 0)
                    signal_ts = opp.get("signal_ts", 0)

                    if not symbol or score < self.config.score_entry:
                        continue

                    # Risk assessment
                    decision = self.risk_agent.evaluate(
                        symbol=symbol,
                        score=score,
                        direction=direction,
                        entry_price=entry_price,
                        atr=atr,
                        current_balance=self.risk_agent._current_balance,
                        open_positions=self.risk_agent.open_positions,
                    )

                    if decision.approved:
                        # Refresh live available balance before placing order
                        try:
                            from agents.binance_compat import create_binance_client, live_full_account_info
                            _c = create_binance_client(self.config.api_key, self.config.api_secret)
                            _acc = live_full_account_info(_c)
                            if _acc:
                                live_avail = _acc["available_balance"]
                                self.risk_agent._current_balance = _acc["margin_balance"]
                                # Reject if required margin exceeds live available balance
                                required_margin = (decision.quantity * entry_price) / self.config.leverage
                                if required_margin > live_avail * 0.9:
                                    logger.warning(
                                        "Skipping %s: required_margin=%.2f > available=%.2f",
                                        symbol, required_margin, live_avail,
                                    )
                                    continue
                        except Exception as _be:
                            logger.debug("Balance pre-check failed: %s", _be)

                        # Execute HFT entry (with slippage/latency tracking)
                        result = self.execution_agent.hft_open(
                            symbol=symbol,
                            direction="LONG" if direction == "LONG" else "SHORT",
                            quantity=decision.quantity,
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
                                qty=decision.quantity,
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

                # 9. Update loop counter
                self._loop_count += 1

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

    def _record_trade_result(self, symbol: str, result: Dict) -> None:
        """Record a trade result and update rage mode state."""
        try:
            pnl = result.get("pnl", 0)
            pnl_pct = result.get("pnl_pct", 0)

            self.repo.insert_trade({
                "symbol": symbol,
                "side": result.get("side", ""),
                "entry_price": result.get("entry_price", 0),
                "exit_price": result.get("exit_price", 0),
                "quantity": result.get("quantity", 0),
                "sl_price": result.get("sl_price", 0),
                "tp_price": result.get("tp_price", 0),
                "status": "closed",
                "pnl": pnl,
                "pnl_pct": pnl_pct,
                "opened_at": result.get("opened_at", datetime.now(timezone.utc).isoformat()),
                "closed_at": datetime.now(timezone.utc).isoformat(),
                "close_reason": result.get("reason", ""),
                "confidence": result.get("score", 0),
                "strategy_signal": "HFT",
            })

            self.risk_agent._trade_history.append(pnl > 0)

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

    def _save_portfolio_snapshot(self) -> None:
        """Save portfolio snapshot to database."""
        try:
            balance = self.risk_agent._current_balance
            equity = balance
            for pos in self.risk_agent.open_positions.values():
                equity += pos.unrealized_pnl

            total_pnl = equity - self.risk_agent.session_start_equity
            total_pnl_pct = (total_pnl / self.risk_agent.session_start_equity * 100) if self.risk_agent.session_start_equity > 0 else 0

            unrealized_pnl = sum(p.unrealized_pnl for p in self.risk_agent.open_positions.values())

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
                "open_positions": len(self.risk_agent.open_positions),
                "win_rate": win_rate,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })
        except Exception as exc:
            logger.exception("Error saving portfolio snapshot: %s", exc)

    def _check_drawdown(self) -> None:
        """Check if drawdown threshold is breached and activate kill switch if needed."""
        try:
            current_equity = self.risk_agent._current_balance
            for pos in self.risk_agent.open_positions.values():
                current_equity += pos.unrealized_pnl

            drawdown = (self.risk_agent.peak_balance - current_equity) / self.risk_agent.peak_balance
            self.risk_agent._drawdown_pct = drawdown

            if current_equity > self.risk_agent.peak_balance:
                self.risk_agent.peak_balance = current_equity

            if drawdown > self.config.max_drawdown_pct:
                reason_ks = f"Drawdown {drawdown:.2%} exceeds max {self.config.max_drawdown_pct:.2%}"
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
            cmd = [
                streamlit_bin, "run", "dashboard.py",
                "--logger.level=warning",
                f"--server.port={self.config.dashboard_port}",
                "--server.address=0.0.0.0",
                "--server.headless=true",
            ]
            self.dashboard_proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            logger.info("Dashboard started on port %d (PID=%d)", self.config.dashboard_port, self.dashboard_proc.pid)
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
    config = build_config(args)

    logger.info(
        "Starting trading bot | Mode=%s | Paper=%s | Symbols=%s",
        "HFT" if config.aggressive_hft else "CLASSIC",
        config.paper_trading,
        ",".join(config.symbols),
    )

    system = TradingSystem(config)
    system.run(start_dashboard=not args.no_dashboard)


if __name__ == "__main__":
    main()

"""
Execution Agent for Binance Futures Trading System.

Supports two execution paths:
  - Path A: Legacy (synchronous) — paper trading or classic live, used by main.py + dashboard
  - Path B: Aggressive HFT — high-frequency trading with hft_open/hft_close when config.aggressive_hft=True

Manages portfolio state, order execution, position lifecycle, and latency tracking.
"""

from __future__ import annotations

import logging
import math
import time
import uuid
import requests
from copy import deepcopy
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from config import TradingConfig
from agents.market_analysis import MarketData
from agents.risk_manager import RiskManagerAgent, Position, RiskAssessment
from agents.strategy import Signal

logger = logging.getLogger(__name__)


class ExecutionAgent:
    """
    Execution gateway for Binance Futures trading.

    Supports two trading paths:
      1. Legacy (paper_trading or classic live): execute_signal, close_position, update_positions
      2. Aggressive HFT (config.aggressive_hft=True): hft_open, hft_close

    In paper trading mode, maintains virtual balance and positions.
    In live mode, uses python-binance to place real orders on Binance Futures USDT-M.
    """

    def __init__(
        self,
        config: Optional[TradingConfig] = None,
        risk_manager: Optional[RiskManagerAgent] = None,
        repository: Optional[Any] = None,
    ):
        """
        Initialize the execution agent.

        Args:
            config: TradingConfig object
            risk_manager: RiskManagerAgent for position tracking and SL/TP logic
            repository: TradeRepository for persistence
        """
        self.config = config or TradingConfig()
        self.risk_mgr = risk_manager
        self.repository = repository

        # Paper trading state
        self._paper_balance: float = self.config.paper_initial_balance
        self._paper_positions: Dict[str, Dict[str, Any]] = {}
        self._paper_trade_id_counter: int = 1

        # Live client (initialized lazily)
        self._client = None
        self._leverage_set: set = set()

        # Slippage/latency tracking
        self._last_slippage: float = 0.0
        self._last_latency_ms: float = 0.0
        self._last_error_code: Optional[int] = None

        if not self.config.paper_trading:
            self._init_live_client()
        else:
            # Paper mode still needs tick/step sizes for SL/TP on low-priced perps
            self._load_exchange_filters_public()

    # ========================================================================
    # Initialization & Live Client Management
    # ========================================================================

    def _init_live_client(self) -> None:
        """Initialize the Binance Futures client for live trading."""
        try:
            from agents.binance_compat import create_binance_client

            self._client = create_binance_client(
                self.config.api_key,
                self.config.api_secret,
            )
            logger.info("Binance live client initialized")
            # Preload exchange filters
            self._load_exchange_filters()
        except Exception as exc:
            logger.exception("Failed to initialize Binance client: %s", exc)
            self._client = None

    # ========================================================================
    # Exchange Filters (step size, tick size, min notional)
    # ========================================================================

    _exchange_filters: Dict[str, Dict[str, Any]] = {}

    def _ingest_symbol_filters(self, sym_info: dict) -> None:
        symbol = sym_info["symbol"]
        filters: Dict[str, Any] = {}
        for f in sym_info.get("filters", []):
            if f["filterType"] == "LOT_SIZE":
                filters["step_size"] = float(f["stepSize"])
                filters["min_qty"] = float(f["minQty"])
                filters["max_qty"] = float(f["maxQty"])
            elif f["filterType"] == "PRICE_FILTER":
                filters["tick_size"] = float(f["tickSize"])
            elif f["filterType"] == "MIN_NOTIONAL":
                filters["min_notional"] = float(f.get("notional", 0))
        filters["quantity_precision"] = sym_info.get("quantityPrecision", 8)
        filters["price_precision"] = sym_info.get("pricePrecision", 8)
        self._exchange_filters[symbol] = filters

    def _load_exchange_filters(self) -> None:
        """Load exchange info and cache filters for all symbols."""
        if self._client is None:
            return
        try:
            info = self._client.futures_exchange_info()
            for sym_info in info.get("symbols", []):
                self._ingest_symbol_filters(sym_info)
            logger.info("Loaded exchange filters for %d symbols", len(self._exchange_filters))
        except Exception as exc:
            logger.warning("Failed to load exchange filters: %s", exc)

    def _load_exchange_filters_public(self) -> None:
        """Public futures exchangeInfo (no API keys) — for paper SL/TP tick alignment."""
        if self._exchange_filters:
            return
        try:
            r = requests.get(
                "https://fapi.binance.com/fapi/v1/exchangeInfo", timeout=45
            )
            r.raise_for_status()
            payload = r.json()
            for sym_info in payload.get("symbols", []):
                self._ingest_symbol_filters(sym_info)
            logger.info(
                "Loaded public exchange filters for %d symbols (paper mode)",
                len(self._exchange_filters),
            )
        except Exception as exc:
            logger.warning("Public exchangeInfo failed: %s", exc)

    def _round_quantity(self, symbol: str, quantity: float) -> float:
        """Round quantity to exchange step size."""
        filters = self._exchange_filters.get(symbol)
        if filters and "step_size" in filters:
            step = filters["step_size"]
            if step > 0:
                precision = max(0, int(round(-math.log10(step))))
                quantity = math.floor(quantity / step) * step
                quantity = round(quantity, precision)
        elif filters and "quantity_precision" in filters:
            precision = filters["quantity_precision"]
            quantity = math.floor(quantity * 10**precision) / 10**precision
        return quantity

    def _round_price(self, symbol: str, price: float) -> float:
        """Round price to exchange tick size."""
        filters = self._exchange_filters.get(symbol)
        if filters and "tick_size" in filters:
            tick = filters["tick_size"]
            if tick > 0:
                precision = max(0, int(round(-math.log10(tick))))
                price = round(round(price / tick) * tick, precision)
        return price

    def _tick_size(self, symbol: str, entry: float) -> float:
        """Effective tick for SL/TP (exchange filter or conservative fallback)."""
        f = self._exchange_filters.get(symbol) or {}
        ts = f.get("tick_size")
        if ts is not None and float(ts) > 0:
            return float(ts)
        pp = int(f.get("price_precision", 8) or 8)
        return max(10 ** (-pp), entry * 1e-6, 1e-8)

    def refine_sl_tp_prices(
        self,
        symbol: str,
        side: str,
        entry: float,
        sl: float,
        tp: float,
    ) -> Tuple[float, float]:
        """
        Snap SL/TP to tick size and keep valid offset from entry (critical for low-priced coins).

        Without this, naive rounding can collapse SL/TP to the same tick as entry (e.g. TRU).
        """
        if entry <= 0:
            return sl, tp
        tick = self._tick_size(symbol, entry)
        sl = self._round_price(symbol, sl)
        tp = self._round_price(symbol, tp)
        steps = max(2, 1)

        if side == "LONG":
            if sl >= entry:
                sl = self._round_price(symbol, entry - tick * steps)
            if sl >= entry:
                sl = entry - tick
            if tp <= entry:
                tp = self._round_price(symbol, entry + tick * steps)
            if tp <= entry:
                tp = entry + tick
        else:  # SHORT
            if sl <= entry:
                sl = self._round_price(symbol, entry + tick * steps)
            if sl <= entry:
                sl = entry + tick
            if tp >= entry:
                tp = self._round_price(symbol, entry - tick * steps)
            if tp >= entry:
                tp = entry - tick

        sl = self._round_price(symbol, sl)
        tp = self._round_price(symbol, tp)
        logger.debug(
            "%s %s refine SL/TP: entry=%.8f tick=%.10g sl=%.8f tp=%.8f",
            symbol,
            side,
            entry,
            tick,
            sl,
            tp,
        )
        return sl, tp

    # ========================================================================
    # Low-level Order Placement & Fill Resolution
    # ========================================================================

    def set_leverage(self, symbol: str, leverage: int = None) -> bool:
        """Set leverage for a futures symbol."""
        if self._client is None:
            return False
        if symbol in self._leverage_set:
            return True

        lev = leverage or self.config.leverage
        try:
            self._client.futures_change_leverage(symbol=symbol, leverage=lev)
            self._leverage_set.add(symbol)
            logger.info("%s leverage set to %dx", symbol, lev)
            return True
        except Exception as exc:
            logger.exception("set_leverage failed for %s: %s", symbol, exc)
            return False

    def place_market_order(
        self, symbol: str, side: str, quantity: float
    ) -> Optional[Dict[str, Any]]:
        """
        Place a futures market order on Binance.
        Rounds quantity to exchange step size before submitting.
        """
        if self._client is None:
            return None

        # Round quantity to exchange precision
        rounded_qty = self._round_quantity(symbol, quantity)
        if rounded_qty <= 0:
            logger.warning("%s: Quantity rounds to 0 (raw=%.10f)", symbol, quantity)
            return None

        # Check min notional
        filters = self._exchange_filters.get(symbol, {})
        min_qty = filters.get("min_qty", 0)
        if rounded_qty < min_qty:
            logger.warning("%s: Quantity %.6f below min %.6f", symbol, rounded_qty, min_qty)
            return None

        try:
            t0 = time.perf_counter()
            order = self._client.futures_create_order(
                symbol=symbol,
                side=side,
                type="MARKET",
                quantity=rounded_qty,
            )
            latency_ms = (time.perf_counter() - t0) * 1000.0
            logger.info(
                "Order latency: %.0fms (symbol=%s side=%s qty=%.6f)",
                latency_ms, symbol, side, rounded_qty
            )

            # CRITICAL FIX: Binance often returns avgPrice="0" for MARKET orders
            avg_price = float(order.get("avgPrice", 0) or 0)
            if avg_price == 0.0:
                order = self._fetch_filled_price(symbol, order, side, quantity)

            return order
        except Exception as exc:
            logger.error("place_market_order failed (%s %s): %s", side, symbol, exc)
            # Store error code for caller to inspect
            try:
                self._last_error_code = exc.code if hasattr(exc, 'code') else None
            except Exception:
                self._last_error_code = None
            return None

    def _fetch_filled_price(
        self, symbol: str, order: Dict[str, Any], side: str, quantity: float
    ) -> Dict[str, Any]:
        """
        Resolve the actual avgPrice when Binance returns avgPrice=0.

        Tries three strategies in order:
          1. Compute from the 'fills' list in the order response
          2. Re-query futures_get_order (3 retries, 300ms apart)
          3. Fallback to current market ticker price

        Args:
            symbol: Trading pair
            order: Original order dict
            side: 'BUY' or 'SELL'
            quantity: Order quantity

        Returns:
            Order dict with avgPrice resolved
        """
        # Strategy 1: Compute from fills array
        fills = order.get("fills") or []
        if fills:
            total_qty = sum(float(f.get("qty", 0)) for f in fills)
            total_cost = sum(
                float(f.get("price", 0)) * float(f.get("qty", 0)) for f in fills
            )
            if total_qty > 0:
                avg = total_cost / total_qty
                if avg > 0:
                    order["avgPrice"] = str(avg)
                    logger.info("Fill price from fills array: %.6f", avg)
                    return order

        # Strategy 2: Re-query the order with retries
        order_id = order.get("orderId")
        if order_id:
            for attempt in range(3):
                time.sleep(0.3 * (attempt + 1))
                try:
                    detail = self._client.futures_get_order(
                        symbol=symbol, orderId=order_id
                    )
                    avg = float(detail.get("avgPrice", 0) or 0)
                    if avg > 0:
                        order["avgPrice"] = str(avg)
                        logger.info("Fill price from order query (attempt %d): %.6f", attempt + 1, avg)
                        return order
                except Exception as exc:
                    logger.debug("Order query attempt %d failed: %s", attempt + 1, exc)

        # Strategy 3: Fallback to current ticker price
        try:
            ticker = self._client.futures_symbol_ticker(symbol=symbol)
            price = float(ticker.get("price", 0))
            if price > 0:
                order["avgPrice"] = str(price)
                logger.warning("Fill price fallback to ticker: %.6f", price)
                return order
        except Exception as exc:
            logger.warning("Ticker fallback failed: %s", exc)

        logger.error("Could not resolve fill price for %s %s order", side, symbol)
        return order

    def _place_reduce_only_order(
        self, symbol: str, side: str, quantity: float
    ) -> Optional[Dict[str, Any]]:
        """Place a reduceOnly market order — bypasses MIN_NOTIONAL for closing small positions."""
        if self._client is None:
            return None
        rounded_qty = self._round_quantity(symbol, quantity)
        if rounded_qty <= 0:
            return None
        try:
            t0 = time.perf_counter()
            order = self._client.futures_create_order(
                symbol=symbol,
                side=side,
                type="MARKET",
                quantity=rounded_qty,
                reduceOnly=True,
            )
            latency_ms = (time.perf_counter() - t0) * 1000.0
            logger.info(
                "reduceOnly order: %.0fms (symbol=%s side=%s qty=%.6f)",
                latency_ms, symbol, side, rounded_qty,
            )
            avg_price = float(order.get("avgPrice", 0) or 0)
            if avg_price == 0.0:
                order = self._fetch_filled_price(symbol, order, side, quantity)
            return order
        except Exception as exc:
            logger.error("reduceOnly order failed (%s %s): %s", side, symbol, exc)
            return None

    def place_protective_orders(
        self,
        symbol: str,
        direction: str,
        sl: float,
        tp: float,
    ) -> Dict[str, Optional[int]]:
        """
        Place exchange-side STOP_MARKET (SL) and TAKE_PROFIT_MARKET (TP) orders.

        These rest on Binance and trigger even if the bot process is stopped,
        crashed, or disconnected — the in-loop SL/TP monitor is only a backup.
        Both use closePosition=true: they close the whole position when hit and
        can never open a new one, so a leftover order is harmless. We still
        cancel them on close (see _cancel_symbol_orders) to keep the book clean.

        Returns {'sl_order_id': int|None, 'tp_order_id': int|None}.
        SL failure is logged CRITICAL — that is the position's safety net.
        """
        result: Dict[str, Optional[int]] = {"sl_order_id": None, "tp_order_id": None}
        if self._client is None:
            return result

        # Closing side is opposite the position direction
        close_side = "SELL" if direction == "LONG" else "BUY"
        sl_price = self._round_price(symbol, sl)
        tp_price = self._round_price(symbol, tp)

        # Clear any stale conditional orders for this symbol first
        self._cancel_symbol_orders(symbol)

        # Stop-loss (the critical safety net)
        try:
            sl_order = self._client.futures_create_order(
                symbol=symbol,
                side=close_side,
                type="STOP_MARKET",
                stopPrice=sl_price,
                closePosition=True,
                workingType="MARK_PRICE",
            )
            result["sl_order_id"] = sl_order.get("orderId")
            logger.info(
                "Protective SL placed: %s %s STOP_MARKET @ %s (orderId=%s)",
                symbol, close_side, sl_price, result["sl_order_id"],
            )
        except Exception as exc:
            logger.critical(
                "FAILED to place protective STOP_MARKET for %s @ %s: %s — "
                "position is NOT protected on the exchange (in-loop monitor only)",
                symbol, sl_price, exc,
            )

        # Take-profit
        try:
            tp_order = self._client.futures_create_order(
                symbol=symbol,
                side=close_side,
                type="TAKE_PROFIT_MARKET",
                stopPrice=tp_price,
                closePosition=True,
                workingType="MARK_PRICE",
            )
            result["tp_order_id"] = tp_order.get("orderId")
            logger.info(
                "Protective TP placed: %s %s TAKE_PROFIT_MARKET @ %s (orderId=%s)",
                symbol, close_side, tp_price, result["tp_order_id"],
            )
        except Exception as exc:
            logger.warning(
                "Failed to place protective TAKE_PROFIT_MARKET for %s @ %s: %s",
                symbol, tp_price, exc,
            )

        return result

    def _cancel_symbol_orders(self, symbol: str) -> None:
        """Cancel all open (incl. conditional SL/TP) orders for a symbol. Best-effort."""
        if self._client is None:
            return
        try:
            self._client.futures_cancel_all_open_orders(symbol=symbol)
            logger.debug("Cancelled all open orders for %s", symbol)
        except Exception as exc:
            logger.warning("Failed to cancel open orders for %s: %s", symbol, exc)

    def get_position(self, symbol: str) -> Optional[Dict[str, Any]]:
        """Fetch the current open position for a symbol from Binance."""
        if self._client is None:
            return None
        try:
            positions = self._client.futures_position_information(symbol=symbol)
            for pos in positions:
                if float(pos.get("positionAmt", 0)) != 0:
                    return pos
            return None
        except Exception as exc:
            logger.exception("get_position failed (%s): %s", symbol, exc)
            return None

    def get_account_balance(self) -> float:
        """Fetch available USDT balance from Binance Futures account."""
        if self._client is None:
            return 0.0
        try:
            balances = self._client.futures_account_balance()
            for asset in balances:
                if asset.get("asset") == "USDT":
                    return float(asset.get("availableBalance", 0.0))
            return 0.0
        except Exception as exc:
            logger.exception("get_account_balance failed: %s", exc)
            return 0.0

    # ========================================================================
    # Paper Trading Helpers
    # ========================================================================

    def _paper_open_position(
        self,
        symbol: str,
        side: str,
        quantity: float,
        entry_price: float,
        sl_price: float,
        tp_price: float,
        trade_id: Optional[int] = None,
        confidence: float = 0.0,
    ) -> Dict[str, Any]:
        """Open a paper trading position and deduct margin from balance."""
        margin = (entry_price * quantity) / self.config.leverage
        self._paper_balance -= margin

        now = datetime.now(timezone.utc)
        position = {
            "symbol": symbol,
            "side": side,
            "entry_price": entry_price,
            "quantity": quantity,
            "sl_price": sl_price,
            "tp_price": tp_price,
            "margin": margin,
            "opened_at": now.isoformat(),
            "unrealized_pnl": 0.0,
            "peak_price": entry_price,
            "trade_id": trade_id,
            "confidence": confidence,
        }
        self._paper_positions[symbol] = position
        logger.info(
            "[PAPER] Opened %s %s: qty=%.4f entry=%.4f sl=%.4f tp=%.4f",
            side, symbol, quantity, entry_price, sl_price, tp_price,
        )
        return position

    def _paper_close_position(
        self, symbol: str, exit_price: float, reason: str
    ) -> Optional[Dict[str, Any]]:
        """Close a paper trading position and return realized PnL info."""
        pos = self._paper_positions.pop(symbol, None)
        if pos is None:
            return None

        qty = pos["quantity"]
        entry = pos["entry_price"]
        margin = pos["margin"]
        side = pos["side"]

        if side == "LONG":
            pnl = (exit_price - entry) * qty
        else:  # SHORT
            pnl = (entry - exit_price) * qty

        pnl_pct = pnl / (entry * qty / self.config.leverage) if entry > 0 else 0.0

        # Return margin + PnL to balance
        self._paper_balance += margin + pnl

        now = datetime.now(timezone.utc).isoformat()
        logger.info(
            "[PAPER] Closed %s %s @ %.4f — PnL: %.4f USDT (%.2f%%) reason=%s",
            side, symbol, exit_price, pnl, pnl_pct * 100, reason,
        )
        return {
            "symbol": symbol,
            "side": side,
            "entry_price": entry,
            "exit_price": exit_price,
            "quantity": qty,
            "pnl": round(pnl, 6),
            "pnl_pct": round(pnl_pct, 6),
            "closed_at": now,
            "close_reason": reason,
            "trade_id": pos.get("trade_id"),
        }

    # ========================================================================
    # PATH A: Legacy Execution (main.py + dashboard)
    # ========================================================================

    def execute_signal(
        self,
        signal: Signal,
        risk_assessment: RiskAssessment,
        market_data: MarketData,
    ) -> Optional[Dict[str, Any]]:
        """
        Execute a trade based on signal + risk assessment (legacy path).

        Returns a trade dict if opened, None otherwise.
        """
        if not risk_assessment.approved:
            logger.info(
                "%s signal rejected: %s", signal.symbol, risk_assessment.rejection_reason
            )
            return None

        symbol = signal.symbol
        side = signal.direction  # 'LONG' or 'SHORT'
        quantity = risk_assessment.position_size
        sl_price = risk_assessment.sl_price
        tp_price = risk_assessment.tp_price
        entry_price = market_data.current_price
        confidence = signal.confidence

        trade_dict: Dict[str, Any] = {
            "symbol": symbol,
            "side": side,
            "entry_price": entry_price,
            "exit_price": None,
            "quantity": quantity,
            "sl_price": sl_price,
            "tp_price": tp_price,
            "status": "open",
            "pnl": None,
            "pnl_pct": None,
            "opened_at": datetime.now(timezone.utc).isoformat(),
            "closed_at": None,
            "close_reason": None,
            "confidence": confidence,
            "strategy_signal": signal.direction,
        }

        trade_id: Optional[int] = None

        if self.config.paper_trading:
            # --- Paper mode ---
            if symbol in self._paper_positions:
                logger.info("%s: Paper position already exists, skipping", symbol)
                return None

            if self.repository:
                trade_id = self.repository.insert_trade(trade_dict)
                self.repository.log_event(
                    "TRADE_OPEN",
                    f"[PAPER] {side} {symbol} qty={quantity:.4f} @ {entry_price:.4f}",
                    "INFO",
                )

            self._paper_open_position(
                symbol, side, quantity, entry_price, sl_price, tp_price,
                trade_id=trade_id, confidence=confidence,
            )

            if self.risk_mgr:
                pos = Position(
                    symbol=symbol,
                    side=side,
                    entry_price=entry_price,
                    quantity=quantity,
                    sl_price=sl_price,
                    tp_price=tp_price,
                    opened_at=datetime.now(timezone.utc),
                    trade_id=trade_id,
                )
                self.risk_mgr.register_open_position(pos)

        else:
            # --- Live mode ---
            if self._client is None:
                logger.error("Live client not initialized")
                return None

            self.set_leverage(symbol, self.config.leverage)
            binance_side = "BUY" if side == "LONG" else "SELL"

            order = self.place_market_order(symbol, binance_side, quantity)
            if order is None:
                return None

            # CRITICAL FIX: Use resolved fill price
            filled_price = float(order.get("avgPrice", 0) or 0)
            if filled_price == 0.0:
                filled_price = entry_price
                logger.warning(
                    "%s: avgPrice still 0 after retries, using market price %.4f",
                    symbol, filled_price
                )
            trade_dict["entry_price"] = filled_price

            # Snap SL/TP to the actual fill and place exchange-side protective
            # orders so the position survives a bot outage.
            sl_price, tp_price = self.refine_sl_tp_prices(
                symbol, side, filled_price, sl_price, tp_price
            )
            trade_dict["sl_price"] = sl_price
            trade_dict["tp_price"] = tp_price
            self.place_protective_orders(symbol, side, sl_price, tp_price)

            if self.repository:
                trade_id = self.repository.insert_trade(trade_dict)
                self.repository.log_event(
                    "TRADE_OPEN",
                    f"[LIVE] {side} {symbol} qty={quantity:.4f} @ {filled_price:.4f}",
                    "INFO",
                )

            if self.risk_mgr:
                pos = Position(
                    symbol=symbol,
                    side=side,
                    entry_price=filled_price,
                    quantity=quantity,
                    sl_price=sl_price,
                    tp_price=tp_price,
                    opened_at=datetime.now(timezone.utc),
                    trade_id=trade_id,
                )
                self.risk_mgr.register_open_position(pos)

        trade_dict["id"] = trade_id
        return trade_dict

    def close_position(
        self,
        symbol: str,
        reason: str,
        current_price: float,
    ) -> Optional[Dict[str, Any]]:
        """
        Close an open position and persist the result (legacy path).

        Returns a result dict with PnL info, or None if no position found.
        """
        if self.config.paper_trading:
            result = self._paper_close_position(symbol, current_price, reason)
        else:
            result = self._live_close_position(symbol, current_price, reason)

        if result is None:
            return None

        trade_id = result.get("trade_id")
        if self.repository and trade_id:
            self.repository.update_trade(
                trade_id,
                {
                    "exit_price": result["exit_price"],
                    "pnl": result["pnl"],
                    "pnl_pct": result["pnl_pct"],
                    "status": "closed",
                    "closed_at": result["closed_at"],
                    "close_reason": reason,
                },
            )
            self.repository.log_event(
                "TRADE_CLOSE",
                f"{result['side']} {symbol} @ {current_price:.4f} PnL={result['pnl']:.4f} reason={reason}",
                "INFO",
            )

        if self.risk_mgr:
            self.risk_mgr.remove_position(symbol)
            self.risk_mgr.update_balance(
                self._paper_balance if self.config.paper_trading else self.get_account_balance()
            )

        return result

    def _live_close_position(
        self, symbol: str, current_price: float, reason: str
    ) -> Optional[Dict[str, Any]]:
        """Close a live position via market order (with reduceOnly for small notionals)."""
        if self._client is None:
            return None

        pos_info = self.get_position(symbol)
        if pos_info is None:
            return None

        qty = abs(float(pos_info.get("positionAmt", 0)))
        side = "SELL" if float(pos_info.get("positionAmt", 0)) > 0 else "BUY"

        # Try normal close first, fall back to reduceOnly for small notionals
        order = self.place_market_order(symbol, side, qty)
        if order is None:
            # Notional too small — use reduceOnly to bypass MIN_NOTIONAL
            order = self._place_reduce_only_order(symbol, side, qty)
        if order is None:
            return None

        # Remove the resting exchange-side SL/TP orders left from the entry
        self._cancel_symbol_orders(symbol)

        exit_price = float(order.get("avgPrice", 0) or 0)
        if exit_price == 0.0:
            exit_price = current_price
        entry_price = float(pos_info.get("entryPrice", 0) or 0)
        if entry_price == 0.0:
            entry_price = exit_price
        is_long = (side == "SELL")

        if is_long:
            pnl = (exit_price - entry_price) * qty
        else:
            pnl = (entry_price - exit_price) * qty

        pnl_pct = pnl / (entry_price * qty / self.config.leverage) if entry_price > 0 else 0.0

        # Find trade_id from risk manager
        rm_pos = self.risk_mgr.open_positions.get(symbol) if self.risk_mgr else None
        trade_id = rm_pos.trade_id if rm_pos else None

        return {
            "symbol": symbol,
            "side": "LONG" if is_long else "SHORT",
            "entry_price": entry_price,
            "exit_price": exit_price,
            "quantity": qty,
            "pnl": round(pnl, 6),
            "pnl_pct": round(pnl_pct, 6),
            "closed_at": datetime.now(timezone.utc).isoformat(),
            "close_reason": reason,
            "trade_id": trade_id,
        }

    def update_positions(
        self, market_data_dict: Dict[str, MarketData]
    ) -> List[Dict[str, Any]]:
        """
        Check all open positions for SL/TP hits and update trailing stops (legacy path).

        Args:
            market_data_dict: Dict mapping symbol -> MarketData

        Returns:
            List of closed trade result dicts.
        """
        closed_trades: List[Dict[str, Any]] = []

        if self.config.paper_trading:
            symbols_to_check = list(self._paper_positions.keys())
        else:
            symbols_to_check = (
                list(self.risk_mgr.open_positions.keys())
                if self.risk_mgr
                else []
            )

        for symbol in symbols_to_check:
            md = market_data_dict.get(symbol)
            if md is None:
                continue

            current_price = md.current_price
            rm_pos = self.risk_mgr.open_positions.get(symbol) if self.risk_mgr else None

            if self.config.paper_trading and symbol in self._paper_positions:
                paper_pos = self._paper_positions[symbol]
                # Sync sl_price from risk manager (which may have trailed it)
                if rm_pos:
                    paper_pos["sl_price"] = rm_pos.sl_price

                # Update unrealized PnL
                qty = paper_pos["quantity"]
                entry = paper_pos["entry_price"]
                side = paper_pos["side"]
                if side == "LONG":
                    paper_pos["unrealized_pnl"] = (current_price - entry) * qty
                else:
                    paper_pos["unrealized_pnl"] = (entry - current_price) * qty

                # Check exits
                if rm_pos:
                    # Update trailing stop first
                    if self.risk_mgr:
                        self.risk_mgr.update_trailing_stop(rm_pos, current_price)
                        paper_pos["sl_price"] = rm_pos.sl_price

                    if self.risk_mgr.is_sl_hit(rm_pos, current_price):
                        result = self.close_position(symbol, "stop_loss", current_price)
                        if result:
                            closed_trades.append(result)
                        continue

                    if self.risk_mgr.is_tp_hit(rm_pos, current_price):
                        result = self.close_position(symbol, "take_profit", current_price)
                        if result:
                            closed_trades.append(result)
                        continue
                else:
                    # Fallback: manual SL/TP check using paper position data
                    sl = paper_pos["sl_price"]
                    tp = paper_pos["tp_price"]
                    side = paper_pos["side"]

                    sl_hit = (side == "LONG" and current_price <= sl) or (
                        side == "SHORT" and current_price >= sl
                    )
                    tp_hit = (side == "LONG" and current_price >= tp) or (
                        side == "SHORT" and current_price <= tp
                    )

                    if sl_hit:
                        result = self.close_position(symbol, "stop_loss", current_price)
                        if result:
                            closed_trades.append(result)
                    elif tp_hit:
                        result = self.close_position(symbol, "take_profit", current_price)
                        if result:
                            closed_trades.append(result)

            elif not self.config.paper_trading and rm_pos:
                # Live mode: update trailing stop
                if self.risk_mgr:
                    self.risk_mgr.update_trailing_stop(rm_pos, current_price)
                    if self.risk_mgr.is_sl_hit(rm_pos, current_price):
                        result = self.close_position(symbol, "stop_loss", current_price)
                        if result:
                            closed_trades.append(result)
                    elif self.risk_mgr.is_tp_hit(rm_pos, current_price):
                        result = self.close_position(symbol, "take_profit", current_price)
                        if result:
                            closed_trades.append(result)

        return closed_trades

    # ========================================================================
    # PATH B: Aggressive HFT Execution (when config.aggressive_hft=True)
    # ========================================================================

    def hft_open(
        self,
        symbol: str,
        direction: str,
        quantity: float,
        entry_price: float,
        sl: float,
        tp: float,
        confidence: float = 0.0,
        signal_ts: float = 0.0,
    ) -> Optional[int]:
        """
        Open a position in aggressive HFT mode.

        For live: places market order, gets fill price, tracks slippage/latency.
        For paper: simulates order, tracks in _paper_positions.
        Saves to repository and returns trade_id.

        Args:
            symbol: Trading pair (e.g., 'BTCUSDT')
            direction: 'LONG' or 'SHORT'
            quantity: Position size
            entry_price: Entry price for simulation/reference
            sl: Stop-loss price
            tp: Take-profit price
            confidence: Signal confidence 0.0-1.0
            signal_ts: Unix timestamp when signal was generated (for latency tracking)

        Returns:
            trade_id (int) on success, None on failure
        """
        order_start_ts = time.perf_counter()

        trade_dict: Dict[str, Any] = {
            "symbol": symbol,
            "side": direction,
            "entry_price": entry_price,
            "exit_price": None,
            "quantity": quantity,
            "sl_price": sl,
            "tp_price": tp,
            "status": "open",
            "pnl": None,
            "pnl_pct": None,
            "opened_at": datetime.now(timezone.utc).isoformat(),
            "closed_at": None,
            "close_reason": None,
            "confidence": confidence,
            "strategy_signal": f"HFT_{direction}",
        }

        trade_id: Optional[int] = None

        if self.config.paper_trading:
            # --- Paper HFT mode ---
            if symbol in self._paper_positions:
                logger.warning("%s: Paper position already open, rejecting HFT entry", symbol)
                return None

            sl, tp = self.refine_sl_tp_prices(symbol, direction, entry_price, sl, tp)
            trade_dict["sl_price"] = sl
            trade_dict["tp_price"] = tp

            if self.repository:
                trade_id = self.repository.insert_trade(trade_dict)
                self.repository.log_event(
                    "HFT_OPEN",
                    f"[PAPER-HFT] {direction} {symbol} qty={quantity:.6f} @ {entry_price:.6f}",
                    "INFO",
                )

            self._paper_open_position(
                symbol, direction, quantity, entry_price, sl, tp,
                trade_id=trade_id, confidence=confidence,
            )
            self._last_slippage = 0.0
            self._last_latency_ms = 0.0

        else:
            # --- Live HFT mode ---
            if self._client is None:
                logger.error("Live client not initialized for HFT")
                return None

            self.set_leverage(symbol, self.config.leverage)
            binance_side = "BUY" if direction == "LONG" else "SELL"

            order = self.place_market_order(symbol, binance_side, quantity)
            if order is None:
                logger.error("HFT market order failed for %s", symbol)
                return None

            # Get actual fill price
            filled_price = float(order.get("avgPrice", 0) or 0)
            if filled_price == 0.0:
                filled_price = entry_price
                logger.warning(
                    "HFT %s: avgPrice=0 after retries, using reference price %.6f",
                    symbol, filled_price
                )
            trade_dict["entry_price"] = filled_price

            # ── Slippage tracking ──
            if entry_price > 0:
                self._last_slippage = abs(filled_price - entry_price) / entry_price
            else:
                self._last_slippage = 0.0

            # ── Latency tracking ──
            order_end_ts = time.perf_counter()
            self._last_latency_ms = (order_end_ts - order_start_ts) * 1000
            signal_to_fill_ms = (time.time() - signal_ts) * 1000 if signal_ts > 0 else 0

            logger.info(
                "HFT EXECUTION %s: slippage=%.4f%% latency=%.0fms signal→fill=%.0fms expected=%.6f actual=%.6f",
                symbol, self._last_slippage * 100, self._last_latency_ms,
                signal_to_fill_ms, entry_price, filled_price,
            )

            sl, tp = self.refine_sl_tp_prices(symbol, direction, filled_price, sl, tp)
            trade_dict["sl_price"] = sl
            trade_dict["tp_price"] = tp

            # Place exchange-side SL/TP so the position is protected even if the
            # bot stops running. The in-loop monitor remains as a backup.
            self.place_protective_orders(symbol, direction, sl, tp)

            if self.repository:
                trade_id = self.repository.insert_trade(trade_dict)
                self.repository.log_event(
                    "HFT_OPEN",
                    (
                        f"[LIVE-HFT] {direction} {symbol} qty={quantity:.6f} @ {filled_price:.6f} "
                        f"slip={self._last_slippage:.4%} lat={self._last_latency_ms:.0f}ms"
                    ),
                    "INFO",
                )

        if self.risk_mgr:
            pos = Position(
                symbol=symbol,
                side=direction,
                entry_price=trade_dict["entry_price"],
                quantity=quantity,
                sl_price=trade_dict["sl_price"],
                tp_price=trade_dict["tp_price"],
                opened_at=datetime.now(timezone.utc),
                trade_id=trade_id,
                score_at_entry=confidence,
            )
            self.risk_mgr.register_open_position(pos)

        logger.info(
            "HFT opened %s: trade_id=%s symbol=%s side=%s qty=%.6f entry=%.6f sl=%.6f tp=%.6f",
            "PAPER" if self.config.paper_trading else "LIVE",
            trade_id, symbol, direction, quantity,
            trade_dict["entry_price"], sl, tp,
        )
        return trade_id

    def hft_close(
        self,
        symbol: str,
        current_price: float,
        reason: str,
    ) -> Optional[Dict[str, Any]]:
        """
        Close a position in aggressive HFT mode.

        Closes position (live market order or paper simulation).
        Computes PnL, updates repository, returns result dict.

        Args:
            symbol: Trading pair
            current_price: Current market price
            reason: Close reason (e.g., 'stale_exit', 'manual_close')

        Returns:
            Dict with {symbol, side, entry_price, exit_price, pnl, pnl_pct, reason, trade_id}
            or None if no position found
        """
        if self.config.paper_trading:
            result = self._paper_close_position(symbol, current_price, reason)
        else:
            result = self._live_close_position(symbol, current_price, reason)

        if result is None:
            logger.warning("HFT close: no position found for %s", symbol)
            return None

        trade_id = result.get("trade_id")
        if self.repository and trade_id:
            self.repository.update_trade(
                trade_id,
                {
                    "exit_price": result["exit_price"],
                    "pnl": result["pnl"],
                    "pnl_pct": result["pnl_pct"],
                    "status": "closed",
                    "closed_at": result["closed_at"],
                    "close_reason": reason,
                },
            )
            self.repository.log_event(
                "HFT_CLOSE",
                f"{result['side']} {symbol} @ {current_price:.6f} PnL={result['pnl']:.6f} ({result['pnl_pct']*100:.2f}%) reason={reason}",
                "INFO",
            )

        if self.risk_mgr:
            self.risk_mgr.remove_position(symbol)
            self.risk_mgr.record_trade_result(result["pnl"])

        logger.info(
            "HFT closed %s: symbol=%s entry=%.6f exit=%.6f pnl=%.6f (%.2f%%) reason=%s",
            "PAPER" if self.config.paper_trading else "LIVE",
            symbol, result["entry_price"], result["exit_price"],
            result["pnl"], result["pnl_pct"] * 100, reason,
        )
        return result

    # ========================================================================
    # Portfolio Status
    # ========================================================================

    def get_portfolio_status(self) -> Dict[str, Any]:
        """Return a snapshot of the current portfolio state."""
        if self.config.paper_trading:
            balance = self._paper_balance
            positions = deepcopy(self._paper_positions)

            # Compute total unrealized PnL and equity
            total_unrealized = sum(
                pos.get("unrealized_pnl", 0.0) for pos in positions.values()
            )
            margin_used = sum(pos.get("margin", 0.0) for pos in positions.values())
            equity = balance + margin_used + total_unrealized

            initial = (
                self.risk_mgr.session_start_equity
                if self.risk_mgr
                else self.config.paper_initial_balance
            )
            total_pnl = equity - initial
            total_pnl_pct = total_pnl / initial if initial > 0 else 0.0

        else:
            # --- Live mode: fetch from Binance API ---
            positions = {}
            balance = 0.0
            equity = 0.0
            total_pnl = 0.0
            total_pnl_pct = 0.0
            total_unrealized = 0.0

            if self._client is not None:
                try:
                    from agents.binance_compat import live_full_account_info

                    acc_info = live_full_account_info(self._client)

                    if acc_info is not None:
                        wallet_balance = acc_info["wallet_balance"]
                        available_balance = acc_info["available_balance"]
                        margin_balance = acc_info["margin_balance"]
                        total_unrealized = acc_info["unrealized_pnl"]

                        balance = wallet_balance
                        equity = margin_balance

                        initial = (
                            self.risk_mgr.session_start_equity
                            if self.risk_mgr
                            else wallet_balance
                        )
                        total_pnl = equity - initial
                        total_pnl_pct = total_pnl / initial if initial > 0 else 0.0

                        if self.risk_mgr:
                            self.risk_mgr.update_balance(available_balance)

                        # Build positions from Binance API data
                        for pos_data in acc_info.get("positions", []):
                            sym = pos_data["symbol"]
                            amt = pos_data["positionAmt"]
                            positions[sym] = {
                                "symbol": sym,
                                "side": "LONG" if amt > 0 else "SHORT",
                                "entry_price": pos_data["entryPrice"],
                                "quantity": abs(amt),
                                "unrealized_pnl": pos_data["unrealizedProfit"],
                                "leverage": pos_data["leverage"],
                            }

                        # Fix stale DB trades with entry_price=0
                        if self.repository and positions:
                            self._backfill_entry_prices(positions)

                        logger.debug(
                            "Live portfolio: wallet=%.4f equity=%.4f unrealized=%.4f pnl=%.4f",
                            wallet_balance, margin_balance, total_unrealized, total_pnl,
                        )
                    else:
                        logger.warning("Failed to fetch account info from Binance")
                except Exception as exc:
                    logger.exception("Error fetching live portfolio status: %s", exc)

            # Fallback: use risk manager data
            if equity == 0.0 and self.risk_mgr:
                balance = self.risk_mgr.current_balance
                equity = balance
                initial = self.risk_mgr.session_start_equity
                total_pnl = equity - initial
                total_pnl_pct = total_pnl / initial if initial > 0 else 0.0
                for sym, rm_pos in self.risk_mgr.open_positions.items():
                    positions[sym] = {
                        "symbol": rm_pos.symbol,
                        "side": rm_pos.side,
                        "entry_price": rm_pos.entry_price,
                        "quantity": rm_pos.quantity,
                        "sl_price": rm_pos.sl_price,
                        "tp_price": rm_pos.tp_price,
                        "unrealized_pnl": rm_pos.unrealized_pnl,
                    }

        return {
            "balance": round(balance, 4),
            "equity": round(equity, 4),
            "unrealized_pnl": round(total_unrealized, 4),
            "total_pnl": round(total_pnl, 4),
            "total_pnl_pct": round(total_pnl_pct, 6),
            "open_positions": len(positions),
            "positions": positions,
            "mode": "PAPER" if self.config.paper_trading else "LIVE",
        }

    def _backfill_entry_prices(self, live_positions: Dict[str, Dict[str, Any]]) -> None:
        """
        Fix open trades in the DB that have entry_price=0 by reading
        the actual entryPrice from Binance position data.
        """
        if not self.repository:
            return
        try:
            open_trades = self.repository.get_open_trades()
            for trade in open_trades:
                if trade.get("entry_price", 0) != 0.0:
                    continue
                sym = trade.get("symbol", "")
                pos_data = live_positions.get(sym)
                if pos_data and pos_data.get("entry_price", 0) > 0:
                    real_price = pos_data["entry_price"]
                    self.repository.update_trade(
                        trade["id"],
                        {"entry_price": real_price},
                    )
                    logger.info(
                        "Backfilled entry_price for trade %d (%s): %.6f",
                        trade["id"], sym, real_price,
                    )
        except Exception as exc:
            logger.warning("backfill_entry_prices error: %s", exc)

    # ========================================================================
    # Properties
    # ========================================================================

    @property
    def client(self):
        """Underlying Binance client in live mode; None in paper mode."""
        return self._client

    @property
    def paper_balance(self) -> float:
        """Current paper trading balance."""
        return self._paper_balance

    @property
    def paper_positions(self) -> Dict[str, Dict[str, Any]]:
        """Current paper trading positions."""
        return self._paper_positions

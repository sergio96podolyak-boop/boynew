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
from decimal import Decimal, ROUND_DOWN, ROUND_HALF_UP
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
        # Once the legacy conditional-order endpoint returns -4120 the account
        # requires the Algo Order API — stop wasting a rejected call per order.
        self._legacy_conditional_unsupported: bool = False

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
            self._client.sync_server_time()
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
                step_d = Decimal(str(step))
                qty_d = Decimal(str(quantity))
                rounded = (qty_d / step_d).to_integral_value(
                    rounding=ROUND_DOWN
                ) * step_d
                precision = max(0, int(round(-math.log10(step))))
                quantity = round(float(rounded), precision)
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
                tick_d = Decimal(str(tick))
                price_d = Decimal(str(price))
                rounded = (price_d / tick_d).to_integral_value(
                    rounding=ROUND_HALF_UP
                ) * tick_d
                precision = max(0, int(round(-math.log10(tick))))
                price = round(float(rounded), precision)
        return price

    @staticmethod
    def _decimal_str(value: float) -> str:
        """Format numeric API params without scientific notation."""
        return f"{float(value):.12f}".rstrip("0").rstrip(".")

    def _price_param_str(self, symbol: str, price: float) -> str:
        """Format a price exactly on the exchange tick grid for API params."""
        filters = self._exchange_filters.get(symbol)
        tick = filters.get("tick_size") if filters else None
        if tick is not None and float(tick) > 0:
            tick_d = Decimal(str(tick))
            price_d = Decimal(str(price))
            rounded = (price_d / tick_d).to_integral_value(
                rounding=ROUND_HALF_UP
            ) * tick_d
            out = format(rounded.normalize(), "f")
            return out.rstrip("0").rstrip(".") if "." in out else out
        return self._decimal_str(price)

    @staticmethod
    def _order_quantity(order: Dict[str, Any], fallback: float) -> float:
        """Best-effort quantity actually accepted by Binance for a submitted order."""
        for key in ("executedQty", "origQty", "submittedQuantity"):
            try:
                qty = float(order.get(key, 0) or 0)
            except (TypeError, ValueError):
                qty = 0.0
            if qty > 0:
                return qty
        return fallback

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

    def set_leverage(self, symbol: str, leverage: int = None, *, force: bool = False) -> bool:
        """Set leverage for a futures symbol."""
        if self._client is None:
            return False
        if symbol in self._leverage_set and not force:
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
            order.setdefault("submittedQuantity", self._decimal_str(rounded_qty))
            latency_ms = (time.perf_counter() - t0) * 1000.0
            logger.info(
                "Order latency: %.0fms (symbol=%s side=%s qty=%.6f)",
                latency_ms, symbol, side, rounded_qty
            )

            # CRITICAL FIX: Binance often returns avgPrice="0" for MARKET orders
            avg_price = float(order.get("avgPrice", 0) or 0)
            if avg_price == 0.0:
                order = self._fetch_filled_price(symbol, order, side, rounded_qty)

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
            order.setdefault("submittedQuantity", self._decimal_str(rounded_qty))
            latency_ms = (time.perf_counter() - t0) * 1000.0
            logger.info(
                "reduceOnly order: %.0fms (symbol=%s side=%s qty=%.6f)",
                latency_ms, symbol, side, rounded_qty,
            )
            avg_price = float(order.get("avgPrice", 0) or 0)
            if avg_price == 0.0:
                order = self._fetch_filled_price(symbol, order, side, rounded_qty)
            return order
        except Exception as exc:
            logger.error("reduceOnly order failed (%s %s): %s", side, symbol, exc)
            return None

    def _emergency_close_unprotected(
        self,
        symbol: str,
        direction: str,
        quantity: float,
    ) -> bool:
        """
        Close a just-opened live position if exchange-side SL placement failed.

        This is deliberately reduceOnly: if Binance has already closed the
        position elsewhere, it must not open a new one in the opposite direction.
        """
        close_side = "SELL" if direction == "LONG" else "BUY"
        order = self._place_reduce_only_order(symbol, close_side, quantity)
        if order is None:
            logger.critical(
                "EMERGENCY CLOSE FAILED for unprotected %s %s qty=%.8f",
                direction,
                symbol,
                quantity,
            )
            return False

        self._cancel_symbol_orders(symbol)
        logger.critical(
            "Emergency closed unprotected %s %s qty=%.8f after SL placement failed",
            direction,
            symbol,
            quantity,
        )
        if self.repository:
            self.repository.log_event(
                "LIVE_PROTECTION_FAILED",
                (
                    f"Emergency closed unprotected {direction} {symbol} "
                    f"qty={quantity:.8f} after SL placement failed"
                ),
                "CRITICAL",
            )
        return True

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
        sl_order = self._place_protective_close_order(
            symbol=symbol,
            close_side=close_side,
            order_type="STOP_MARKET",
            trigger_price=sl_price,
            label="sl",
        )
        if sl_order:
            result["sl_order_id"] = sl_order.get("algoId") or sl_order.get("orderId")
            logger.info(
                "Protective SL placed: %s %s STOP_MARKET @ %s (id=%s)",
                symbol, close_side, sl_price, result["sl_order_id"],
            )
        else:
            logger.critical(
                "FAILED to place protective STOP_MARKET for %s @ %s: "
                "position is NOT protected on the exchange (in-loop monitor only)",
                symbol, sl_price,
            )

        # Take-profit
        tp_order = self._place_protective_close_order(
            symbol=symbol,
            close_side=close_side,
            order_type="TAKE_PROFIT_MARKET",
            trigger_price=tp_price,
            label="tp",
        )
        if tp_order:
            result["tp_order_id"] = tp_order.get("algoId") or tp_order.get("orderId")
            logger.info(
                "Protective TP placed: %s %s TAKE_PROFIT_MARKET @ %s (id=%s)",
                symbol, close_side, tp_price, result["tp_order_id"],
            )
        else:
            logger.warning(
                "Failed to place protective TAKE_PROFIT_MARKET for %s @ %s",
                symbol, tp_price,
            )

        return result

    def _place_protective_close_order(
        self,
        *,
        symbol: str,
        close_side: str,
        order_type: str,
        trigger_price: float,
        label: str,
    ) -> Optional[Dict[str, Any]]:
        """
        Place a close-all conditional order.

        Binance moved USD-M Futures TP/SL conditionals to the Algo Order API for
        some accounts. Try that endpoint first, then fall back to the legacy
        order endpoint for older environments.
        """
        if self._client is None:
            return None

        trigger = self._price_param_str(symbol, trigger_price)
        algo_params = {
            "algoType": "CONDITIONAL",
            "symbol": symbol,
            "side": close_side,
            "type": order_type,
            "triggerPrice": trigger,
            "closePosition": "true",
            "workingType": "MARK_PRICE",
            "newOrderRespType": "ACK",
        }

        algo_exc: Optional[Exception] = None
        for attempt in range(3):
            # Fresh id per attempt so a retry is never rejected as a duplicate
            algo_params["clientAlgoId"] = (
                f"boynew_{label}_{symbol}_{uuid.uuid4().hex[:10]}"[:36]
            )
            try:
                return self._client._request_futures_api(
                    "post",
                    "algoOrder",
                    signed=True,
                    data=algo_params,
                )
            except Exception as exc:
                algo_exc = exc
                code = getattr(exc, "code", None)
                if code == -4509 and attempt < 2:
                    # -4509 "TIF GTE can only be used with open positions":
                    # the just-opened position hasn't propagated to the Algo
                    # API yet — wait for it and retry.
                    time.sleep(0.5 * (attempt + 1))
                    continue
                if code == -2021:
                    # Price is already beyond the trigger; no resting
                    # conditional can exist. The legacy endpoint would reject
                    # it too — return so the caller closes at market instead.
                    logger.warning(
                        "Protective %s for %s @ %s would trigger immediately "
                        "(price already beyond trigger)",
                        order_type, symbol, trigger,
                    )
                    return None
                break

        if self._legacy_conditional_unsupported:
            logger.error(
                "Algo protective %s failed for %s @ %s: %s "
                "(legacy endpoint already known unsupported on this account)",
                order_type, symbol, trigger, algo_exc,
            )
            return None

        logger.warning(
            "Algo protective %s failed for %s @ %s: %s; trying legacy order endpoint",
            order_type, symbol, trigger, algo_exc,
        )
        try:
            return self._client.futures_create_order(
                symbol=symbol,
                side=close_side,
                type=order_type,
                stopPrice=trigger,
                closePosition=True,
                workingType="MARK_PRICE",
            )
        except Exception as legacy_exc:
            if getattr(legacy_exc, "code", None) == -4120:
                self._legacy_conditional_unsupported = True
            logger.error(
                "Legacy protective %s failed for %s @ %s: %s",
                order_type, symbol, trigger, legacy_exc,
            )
            return None

    def _cancel_symbol_orders(self, symbol: str) -> None:
        """Cancel all open (incl. conditional SL/TP) orders for a symbol. Best-effort."""
        if self._client is None:
            return
        try:
            self._client.futures_cancel_all_open_orders(symbol=symbol)
            logger.debug("Cancelled all open orders for %s", symbol)
        except Exception as exc:
            logger.warning("Failed to cancel open orders for %s: %s", symbol, exc)
        try:
            self._client._request_futures_api(
                "delete",
                "algoOpenOrders",
                signed=True,
                data={"symbol": symbol},
            )
            logger.debug("Cancelled all algo open orders for %s", symbol)
        except Exception as exc:
            logger.warning("Failed to cancel algo open orders for %s: %s", symbol, exc)

    def get_protective_orders(self, symbol: str) -> Dict[str, int]:
        """
        Count exchange-side SL/TP orders for a symbol.

        Returns {"sl": n, "tp": n, "total": n, "ok": 1|0}. If Binance order
        queries fail, ok=0 so callers do not make unsafe repair decisions.
        """
        counts = {"sl": 0, "tp": 0, "total": 0, "ok": 0}
        if self._client is None:
            return counts

        try:
            regular_orders = self._client.futures_get_open_orders(symbol=symbol)
        except Exception as exc:
            logger.debug("Could not fetch regular open orders for %s: %s", symbol, exc)
            return counts

        algo_orders = []
        try:
            response = self._client._request_futures_api(
                "get",
                "openAlgoOrders",
                signed=True,
                data={"symbol": symbol, "algoType": "CONDITIONAL"},
            )
            if isinstance(response, list):
                algo_orders = response
            elif isinstance(response, dict):
                algo_orders = response.get("orders", [])
        except Exception as exc:
            logger.debug("Could not fetch algo open orders for %s: %s", symbol, exc)
            return counts

        for order in regular_orders + algo_orders:
            order_type = order.get("type") or order.get("orderType") or ""
            if order_type == "STOP_MARKET":
                counts["sl"] += 1
            elif order_type == "TAKE_PROFIT_MARKET":
                counts["tp"] += 1

        counts["total"] = counts["sl"] + counts["tp"]
        counts["ok"] = 1
        return counts

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
            protective = self.place_protective_orders(symbol, side, sl_price, tp_price)
            if not protective.get("sl_order_id"):
                self._emergency_close_unprotected(symbol, side, quantity)
                return None

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

        # Close with reduceOnly so an exit can never flip into a new position.
        order = self._place_reduce_only_order(symbol, side, qty)
        if order is None:
            order = self.place_market_order(symbol, side, qty)
        if order is None:
            return None

        closed_qty = self._order_quantity(order, qty)
        leftover_info = self.get_position(symbol)
        if leftover_info is not None:
            leftover_amt = float(leftover_info.get("positionAmt", 0) or 0)
            if abs(leftover_amt) > 0:
                cleanup_side = "SELL" if leftover_amt > 0 else "BUY"
                cleanup_qty = abs(leftover_amt)
                cleanup = self._place_reduce_only_order(symbol, cleanup_side, cleanup_qty)
                if cleanup is not None:
                    closed_qty += self._order_quantity(cleanup, cleanup_qty)
                    logger.warning(
                        "Cleaned residual live quantity for %s: qty=%.10f side=%s",
                        symbol,
                        cleanup_qty,
                        cleanup_side,
                    )
                else:
                    logger.critical(
                        "Residual live quantity remains for %s after close: %.10f",
                        symbol,
                        leftover_amt,
                    )

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
            pnl = (exit_price - entry_price) * closed_qty
        else:
            pnl = (entry_price - exit_price) * closed_qty

        pnl_pct = (
            pnl / (entry_price * closed_qty / self.config.leverage)
            if entry_price > 0 and closed_qty > 0
            else 0.0
        )

        # Find trade_id from risk manager
        rm_pos = self.risk_mgr.open_positions.get(symbol) if self.risk_mgr else None
        trade_id = rm_pos.trade_id if rm_pos else None

        return {
            "symbol": symbol,
            "side": "LONG" if is_long else "SHORT",
            "entry_price": entry_price,
            "exit_price": exit_price,
            "quantity": closed_qty,
            "pnl": round(pnl, 6),
            "pnl_pct": round(pnl_pct, 6),
            "closed_at": datetime.now(timezone.utc).isoformat(),
            "close_reason": reason,
            "trade_id": trade_id,
        }

    def _reconcile_live_flat_position(
        self,
        symbol: str,
        current_price: float,
        reason: str,
    ) -> Optional[Dict[str, Any]]:
        """
        Build a close result when Binance is already flat for a tracked position.

        Exchange-side SL/TP can close a trade before the bot's loop asks for an
        exit. In that case get_position() returns None, but the risk manager may
        still hold the symbol. Reconcile from recent account fills so DB and
        memory do not stay stale.
        """
        if self._client is None or self.risk_mgr is None:
            return None

        rm_pos = self.risk_mgr.open_positions.get(symbol)
        if rm_pos is None:
            return None

        close_side = "SELL" if rm_pos.side == "LONG" else "BUY"
        opened_at = rm_pos.opened_at
        if opened_at.tzinfo is None:
            opened_at = opened_at.replace(tzinfo=timezone.utc)
        opened_ms = int(opened_at.timestamp() * 1000)
        start_ms = max(0, opened_ms - 60_000)

        close_fills: List[Dict[str, Any]] = []
        try:
            fills = self._client.futures_account_trades(
                symbol=symbol,
                startTime=start_ms,
                limit=100,
            )
            for fill in fills:
                fill_time = int(fill.get("time", 0) or 0)
                if fill_time + 1000 < opened_ms:
                    continue
                if fill.get("side") == close_side:
                    close_fills.append(fill)
        except Exception as exc:
            logger.warning("Could not fetch account fills for %s reconciliation: %s", symbol, exc)

        qty = 0.0
        exit_price = current_price if current_price > 0 else rm_pos.entry_price
        pnl = 0.0
        closed_at = datetime.now(timezone.utc).isoformat()

        if close_fills:
            qty = sum(float(f.get("qty", 0) or 0) for f in close_fills)
            if qty > 0:
                exit_price = (
                    sum(float(f.get("price", 0) or 0) * float(f.get("qty", 0) or 0) for f in close_fills)
                    / qty
                )
            pnl = sum(float(f.get("realizedPnl", 0) or 0) for f in close_fills)
            last_time = max(int(f.get("time", 0) or 0) for f in close_fills)
            if last_time > 0:
                closed_at = datetime.fromtimestamp(last_time / 1000, tz=timezone.utc).isoformat()
        else:
            qty = rm_pos.quantity
            if rm_pos.side == "LONG":
                pnl = (exit_price - rm_pos.entry_price) * qty
            else:
                pnl = (rm_pos.entry_price - exit_price) * qty

        if qty <= 0:
            qty = rm_pos.quantity

        margin = rm_pos.entry_price * qty / self.config.leverage if rm_pos.entry_price > 0 else 0.0
        pnl_pct = pnl / margin if margin > 0 else 0.0
        reconciled_reason = reason
        profit_exit_reasons = {
            "take_profit",
            "profit_lock",
            "scalp_take_profit",
            "trailing_stop",
        }
        if pnl > 0 and reason == "stop_loss":
            reconciled_reason = "take_profit"
        elif pnl < 0 and reason in profit_exit_reasons:
            reconciled_reason = "stop_loss"

        self._cancel_symbol_orders(symbol)
        logger.info(
            "Reconciled already-flat live position %s: side=%s exit=%.6f pnl=%.6f reason=%s",
            symbol,
            rm_pos.side,
            exit_price,
            pnl,
            reconciled_reason,
        )

        return {
            "symbol": symbol,
            "side": rm_pos.side,
            "entry_price": rm_pos.entry_price,
            "exit_price": exit_price,
            "quantity": qty,
            "pnl": round(pnl, 6),
            "pnl_pct": round(pnl_pct, 6),
            "closed_at": closed_at,
            "close_reason": f"{reconciled_reason}_exchange_reconcile",
            "trade_id": rm_pos.trade_id,
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

            actual_quantity = self._order_quantity(order, quantity)
            trade_dict["quantity"] = actual_quantity

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
            protective = self.place_protective_orders(symbol, direction, sl, tp)
            if not protective.get("sl_order_id"):
                self._emergency_close_unprotected(symbol, direction, actual_quantity)
                return None

            if self.repository:
                trade_id = self.repository.insert_trade(trade_dict)
                self.repository.log_event(
                    "HFT_OPEN",
                    (
                        f"[LIVE-HFT] {direction} {symbol} qty={actual_quantity:.6f} @ {filled_price:.6f} "
                        f"slip={self._last_slippage:.4%} lat={self._last_latency_ms:.0f}ms"
                    ),
                    "INFO",
                )

        position_quantity = float(trade_dict.get("quantity") or quantity)
        if self.risk_mgr:
            pos = Position(
                symbol=symbol,
                side=direction,
                entry_price=trade_dict["entry_price"],
                quantity=position_quantity,
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
            trade_id, symbol, direction, position_quantity,
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
            if not self.config.paper_trading:
                result = self._reconcile_live_flat_position(symbol, current_price, reason)
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
                    "close_reason": result.get("close_reason") or reason,
                },
            )
            self.repository.log_event(
                "HFT_CLOSE",
                f"{result['side']} {symbol} @ {result['exit_price']:.6f} PnL={result['pnl']:.6f} ({result['pnl_pct']*100:.2f}%) reason={result.get('close_reason') or reason}",
                "INFO",
            )

        if self.risk_mgr:
            self.risk_mgr.remove_position(symbol)
            self.risk_mgr.record_trade_result(result["pnl"])

        logger.info(
            "HFT closed %s: symbol=%s entry=%.6f exit=%.6f pnl=%.6f (%.2f%%) reason=%s",
            "PAPER" if self.config.paper_trading else "LIVE",
            symbol, result["entry_price"], result["exit_price"],
            result["pnl"], result["pnl_pct"] * 100, result.get("close_reason") or reason,
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

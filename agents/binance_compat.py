"""
python-binance Client wrapper: skip spot `ping()` on construction so startup
does not fail hard when DNS is flaky or the network is briefly offline, and
keep the local clock synced to Binance server time (fixes APIError -1021
"Timestamp for this request is outside of the recvWindow").
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Any, Dict, Optional

from binance.client import BaseClient, Client as BinanceClient
from binance.exceptions import BinanceAPIException

logger = logging.getLogger(__name__)


class BinanceClientCompat(BinanceClient):
    """
    Same as python-binance `Client`, but:
      - does not call `ping()` in `__init__`
      - on APIError -1021 (local clock drifted outside recvWindow) resyncs
        `timestamp_offset` from the futures server clock and retries once
    """

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        BaseClient.__init__(self, *args, **kwargs)
        self._time_sync_lock = threading.Lock()
        self._last_time_sync: float = 0.0

    def sync_server_time(self) -> None:
        """Set `timestamp_offset` from the futures server clock. Best-effort."""
        with self._time_sync_lock:
            try:
                server_ms = int(self.futures_time()["serverTime"])
                self.timestamp_offset = server_ms - int(time.time() * 1000)
                self._last_time_sync = time.monotonic()
                logger.info(
                    "Binance server time synced (offset %+d ms)", self.timestamp_offset
                )
            except Exception as exc:
                logger.warning("Binance server time sync failed: %s", exc)

    def _request(self, method, uri: str, signed: bool, force_params: bool = False, **kwargs):
        try:
            return super()._request(method, uri, signed, force_params, **kwargs)
        except BinanceAPIException as exc:
            if not (signed and exc.code == -1021):
                raise
            # The request was rejected before execution, so a retry is safe.
            # The base client mutated the shared data dict with the stale
            # timestamp/signature — strip them or the new signature would be
            # computed over the old one and rejected as invalid.
            data = kwargs.get("data")
            if isinstance(data, dict):
                data.pop("timestamp", None)
                data.pop("signature", None)
            logger.warning("Binance -1021 clock drift; resyncing time and retrying once")
            self.sync_server_time()
            return super()._request(method, uri, signed, force_params, **kwargs)


def create_binance_client(
    api_key: Optional[str] = None,
    api_secret: Optional[str] = None,
    **kwargs: Any,
) -> BinanceClientCompat:
    """Construct a Binance REST client without the constructor connectivity check."""
    return BinanceClientCompat(api_key, api_secret, **kwargs)


def futures_account_snapshot(client: BinanceClientCompat) -> Optional[Dict[str, Any]]:
    """Return `futures_account()` or None on failure."""
    try:
        return client.futures_account()
    except Exception:
        return None


def live_initial_balances(client: BinanceClientCompat) -> tuple[float, float]:
    """
    For USDT-M futures: (available_balance, total_margin_balance).

    `available` is used for position sizing; `total_margin` is a better PnL baseline.
    Falls back to futures_account_balance USDT available if account() fails.
    """
    acc = futures_account_snapshot(client)
    if acc:
        avail = float(acc.get("availableBalance", 0) or 0)
        margin = float(acc.get("totalMarginBalance", 0) or 0)
        if margin <= 0:
            margin = float(acc.get("totalWalletBalance", 0) or avail)
        return avail, margin
    try:
        balances = client.futures_account_balance()
        for asset in balances:
            if asset.get("asset") == "USDT":
                v = float(asset.get("availableBalance", 0.0))
                return v, v
    except Exception:
        pass
    return 0.0, 0.0


def live_full_account_info(client: BinanceClientCompat) -> Optional[Dict[str, Any]]:
    """
    Fetch comprehensive Binance Futures account info.

    Returns a dict with:
        wallet_balance:     Total deposited + realized PnL (USDT)
        available_balance:  Free balance for new orders (USDT)
        margin_balance:     Wallet balance + unrealized PnL = total equity (USDT)
        unrealized_pnl:     Total unrealized PnL across all positions (USDT)
        total_pnl:          margin_balance - wallet_balance (unrealized only)
        positions:          List of non-zero position dicts
    """
    acc = futures_account_snapshot(client)
    if acc is None:
        return None

    wallet = float(acc.get("totalWalletBalance", 0) or 0)
    available = float(acc.get("availableBalance", 0) or 0)
    margin = float(acc.get("totalMarginBalance", 0) or 0)
    unrealized = float(acc.get("totalUnrealizedProfit", 0) or 0)

    # If margin is 0 but wallet isn't, use wallet + unrealized
    if margin <= 0 and wallet > 0:
        margin = wallet + unrealized

    # Parse positions with non-zero amounts
    positions = []
    for pos in acc.get("positions", []):
        amt = float(pos.get("positionAmt", 0) or 0)
        if amt != 0:
            positions.append({
                "symbol": pos.get("symbol", ""),
                "positionAmt": amt,
                "entryPrice": float(pos.get("entryPrice", 0) or 0),
                "unrealizedProfit": float(pos.get("unrealizedProfit", 0) or 0),
                "leverage": int(pos.get("leverage", 1) or 1),
                "positionSide": pos.get("positionSide", "BOTH"),
            })

    return {
        "wallet_balance": wallet,
        "available_balance": available,
        "margin_balance": margin,
        "unrealized_pnl": unrealized,
        "total_pnl": margin - wallet,  # unrealized portion
        "positions": positions,
    }

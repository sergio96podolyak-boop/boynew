#!/usr/bin/env python3
"""
Place exchange-side SL/TP protection for existing Binance Futures positions.

This tool does not open new entries. It only syncs current live positions,
calculates ATR-based SL/TP, submits Binance Algo conditional orders, and exits.
"""

from __future__ import annotations

import argparse
import logging
import sys
from typing import Iterable, Optional

from config import TradingConfig
from agents.binance_compat import create_binance_client, live_full_account_info
from agents.execution import ExecutionAgent
from agents.live_guard import LiveGuardAgent
from agents.risk_manager import RiskManagerAgent


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("protect_positions")


def _compute_atr(client, symbol: str, interval: str, fallback_price: float) -> float:
    try:
        klines = client.futures_klines(symbol=symbol, interval=interval, limit=30)
        highs = [float(k[2]) for k in klines]
        lows = [float(k[3]) for k in klines]
        closes = [float(k[4]) for k in klines]
        ranges = []
        for idx, (high, low) in enumerate(zip(highs, lows)):
            prev_close = closes[idx - 1] if idx > 0 else closes[idx]
            ranges.append(max(high - low, abs(high - prev_close), abs(low - prev_close)))
        if ranges:
            return sum(ranges[-14:]) / min(len(ranges), 14)
    except Exception as exc:
        logger.warning("%s ATR fetch failed: %s", symbol, exc)
    return max(fallback_price * 0.005, 1e-8)


def _selected_symbols(raw: Optional[str]) -> Optional[set[str]]:
    if not raw:
        return None
    return {part.strip().upper() for part in raw.split(",") if part.strip()}


def protect_existing_positions(symbols: Optional[Iterable[str]] = None) -> int:
    config = TradingConfig()
    config.paper_trading = False
    config.validate()
    LiveGuardAgent(config).require_ready()

    client = create_binance_client(config.api_key, config.api_secret)
    account = live_full_account_info(client)
    if account is None:
        print("Could not fetch live Binance account info.")
        return 2

    wanted = set(symbols) if symbols else None
    positions = [
        p for p in account.get("positions", [])
        if (wanted is None or p["symbol"] in wanted)
    ]
    if not positions:
        print("No matching live positions found.")
        return 0

    risk = RiskManagerAgent(config=config, initial_balance=account["margin_balance"])
    execution = ExecutionAgent(config=config, risk_manager=risk)

    failures = 0
    for pos in positions:
        symbol = pos["symbol"]
        amount = float(pos["positionAmt"])
        entry = float(pos["entryPrice"])
        if amount == 0 or entry <= 0:
            continue

        side = "LONG" if amount > 0 else "SHORT"
        atr = _compute_atr(execution.client, symbol, config.hft_timeframe, entry)
        sl, tp = risk.calculate_sl_tp(entry, side, atr)
        sl, tp = execution.refine_sl_tp_prices(symbol, side, entry, sl, tp)
        result = execution.place_protective_orders(symbol, side, sl, tp)
        if result.get("sl_order_id"):
            print(
                f"{symbol}: protected {side} qty={abs(amount):.8f} "
                f"SL={sl} TP={tp} sl_id={result.get('sl_order_id')}"
            )
        else:
            failures += 1
            print(f"{symbol}: FAILED to place exchange stop-loss protection")

    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Protect existing live Binance Futures positions with SL/TP."
    )
    parser.add_argument("--live", action="store_true", help="Required: this touches live Binance orders")
    parser.add_argument("--yes", action="store_true", help="Required confirmation")
    parser.add_argument("--symbols", help="Optional comma-separated symbol list, e.g. BTCUSDT,ETHUSDT")
    args = parser.parse_args()

    if not (args.live and args.yes):
        print("Refusing to place live orders without: --live --yes")
        return 2

    return protect_existing_positions(_selected_symbols(args.symbols))


if __name__ == "__main__":
    raise SystemExit(main())

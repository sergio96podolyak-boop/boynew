#!/usr/bin/env python3
"""
One-time fix script: backfill entry_price=0 trades from Binance API.

For OPEN trades: fetches the actual entryPrice from Binance position data.
For CLOSED trades: attempts to compute entry from PnL data if possible.

Usage:
    python fix_entry_prices.py          # dry-run (shows what would change)
    python fix_entry_prices.py --apply  # actually update the database
"""
import argparse
import sqlite3
import sys
from dotenv import load_dotenv

load_dotenv()

from config import config
from agents.binance_compat import create_binance_client, live_full_account_info


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Actually write changes to DB")
    args = parser.parse_args()

    dry_run = not args.apply

    print(f"Mode: {'DRY RUN' if dry_run else 'APPLY CHANGES'}")
    print(f"DB: {config.db_path}")
    print()

    # Connect to DB
    conn = sqlite3.connect(config.db_path)
    conn.row_factory = sqlite3.Row

    # Find trades with entry_price = 0
    cursor = conn.execute(
        "SELECT id, symbol, side, entry_price, exit_price, quantity, pnl, status "
        "FROM trades WHERE entry_price = 0.0 OR entry_price IS NULL"
    )
    bad_trades = [dict(r) for r in cursor.fetchall()]
    print(f"Found {len(bad_trades)} trades with entry_price=0")
    if not bad_trades:
        print("Nothing to fix!")
        return

    # Connect to Binance and get current positions
    client = create_binance_client(config.api_key, config.api_secret)
    acc = live_full_account_info(client)

    position_prices = {}
    if acc and acc.get("positions"):
        for pos in acc["positions"]:
            sym = pos["symbol"]
            entry = pos["entryPrice"]
            if entry > 0:
                position_prices[sym] = entry
        print(f"Live positions with entry prices: {position_prices}")
    print()

    fixed = 0
    skipped = 0

    for trade in bad_trades:
        tid = trade["id"]
        sym = trade["symbol"]
        status = trade["status"]
        side = trade["side"]
        qty = trade["quantity"]
        pnl = trade["pnl"]
        exit_p = trade["exit_price"] or 0

        new_entry = 0.0

        if status == "open" and sym in position_prices:
            # Open trade: use Binance position data
            new_entry = position_prices[sym]
            source = "Binance position"
        elif status == "closed" and pnl is not None and qty > 0 and exit_p > 0:
            # Closed trade: reverse-engineer entry from PnL
            # LONG: pnl = (exit - entry) * qty  =>  entry = exit - pnl/qty
            # SHORT: pnl = (entry - exit) * qty  =>  entry = exit + pnl/qty
            if side == "LONG":
                new_entry = exit_p - (pnl / qty)
            else:
                new_entry = exit_p + (pnl / qty)
            if new_entry <= 0:
                new_entry = 0.0
            source = "reverse from PnL"
        else:
            skipped += 1
            print(f"  SKIP  trade {tid:3d} ({sym:12s} {status:6s}) — insufficient data")
            continue

        if new_entry > 0:
            print(f"  FIX   trade {tid:3d} ({sym:12s} {status:6s} {side:5s}) → entry={new_entry:.6f} [{source}]")
            if not dry_run:
                conn.execute(
                    "UPDATE trades SET entry_price = ? WHERE id = ?",
                    (new_entry, tid),
                )
            fixed += 1
        else:
            skipped += 1
            print(f"  SKIP  trade {tid:3d} ({sym:12s} {status:6s}) — could not determine price")

    if not dry_run:
        conn.commit()

    print()
    print(f"Fixed: {fixed}   Skipped: {skipped}")
    if dry_run:
        print("(Dry run — no changes written. Run with --apply to save.)")

    conn.close()


if __name__ == "__main__":
    main()

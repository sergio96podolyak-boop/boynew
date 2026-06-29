"""
status.py — מצב הבוט במבט אחד.

מציג מה הבוט עשה בפועל: מאזן, עסקאות פתוחות/סגורות, רווח/הפסד, סיבות יציאה,
ואירועי מערכת אחרונים — הכל מתוך trading.db. עם --live (ומפתחות ב-.env) מציג גם
את מצב החשבון האמיתי ב-Binance: יתרה, פוזיציות פתוחות, והוראות SL/TP שפעילות.

הרצה:
    ./venv/bin/python status.py            # סיכום מקומי מה-DB + הלוג
    ./venv/bin/python status.py --live     # + מצב חי מ-Binance (דורש מפתחות ב-.env)
"""

import argparse
import os
import sys
from datetime import datetime

from config import config
from database.repository import TradeRepository


def _hr(title: str) -> None:
    print("\n" + "=" * 64)
    print(f"  {title}")
    print("=" * 64)


def _fmt_money(v) -> str:
    try:
        return f"{float(v):,.2f}"
    except (TypeError, ValueError):
        return str(v)


def show_db(repo: TradeRepository) -> None:
    _hr("ביצועים כוללים (עסקאות סגורות)")
    stats = repo.get_performance_stats()
    if stats["total_trades"] == 0:
        print("  אין עדיין עסקאות סגורות במסד הנתונים.")
    else:
        print(f"  עסקאות סגורות : {stats['total_trades']}")
        print(f"  מנצחות/מפסידות: {stats['winning_trades']} / {stats['losing_trades']}")
        print(f"  אחוז הצלחה    : {stats['win_rate'] * 100:.1f}%")
        print(f"  רווח/הפסד מצטבר: {_fmt_money(stats['total_pnl'])} USDT")
        print(f"  ממוצע לעסקה   : {_fmt_money(stats['avg_pnl'])} USDT")
        print(f"  Max drawdown  : {stats['max_drawdown'] * 100:.1f}%")
        print(f"  Sharpe        : {stats['sharpe_ratio']}")

    _hr("עסקאות פתוחות כרגע")
    open_trades = repo.get_open_trades()
    if not open_trades:
        print("  אין עסקאות פתוחות.")
    for t in open_trades:
        print(
            f"  #{t['id']} {t['side']:5} {t['symbol']:12} "
            f"כניסה={t['entry_price']:.6f} SL={t['sl_price']} TP={t['tp_price']} "
            f"qty={t['quantity']} | נפתחה {t['opened_at']}"
        )

    _hr("20 עסקאות אחרונות שנסגרו")
    history = repo.get_trade_history(limit=20)
    if not history:
        print("  אין היסטוריית עסקאות סגורות.")
    for t in history:
        pnl = t.get("pnl")
        pnl_str = f"{pnl:+.4f}" if pnl is not None else "  —  "
        pct = t.get("pnl_pct")
        pct_str = f"{pct * 100:+.2f}%" if pct is not None else ""
        print(
            f"  #{t['id']} {t['side']:5} {t['symbol']:12} "
            f"כניסה={t['entry_price']:.6f} יציאה={t.get('exit_price')} "
            f"PnL={pnl_str} {pct_str} | {t.get('close_reason')}"
        )

    _hr("פילוח לפי סיבת סגירה (48 שעות)")
    reasons = repo.get_close_reason_stats(hours_back=48)
    if not reasons:
        print("  אין נתונים ב-48 השעות האחרונות.")
    for r in reasons:
        print(
            f"  {str(r['close_reason']):16} | עסקאות={r['trades']:3} "
            f"| win={r['win_rate'] * 100:5.1f}% | PnL={_fmt_money(r['total_pnl'])}"
        )

    _hr("מצב תיק אחרון (snapshot)")
    snaps = repo.get_portfolio_snapshots(limit=1)
    if not snaps:
        print("  אין snapshots של התיק.")
    else:
        s = snaps[-1]
        print(f"  זמן     : {s['timestamp']}")
        print(f"  מאזן    : {_fmt_money(s['balance'])} USDT")
        print(f"  Equity  : {_fmt_money(s['equity'])} USDT")
        print(f"  PnL כולל: {_fmt_money(s['total_pnl'])} ({s['total_pnl_pct'] * 100:.2f}%)")
        print(f"  פתוחות  : {s['open_positions']} | win_rate={s['win_rate'] * 100:.1f}%")

    _hr("10 אירועי מערכת אחרונים")
    for e in repo.get_recent_events(limit=10):
        print(f"  [{e['severity']:5}] {e['timestamp']} {e['event_type']}: {e['message']}")


def show_live() -> None:
    _hr("מצב חי — Binance Futures")
    if config.paper_trading:
        print("  PAPER_TRADING=true — אין חשבון אמיתי לבדוק. שנה ל-false ב-.env ללייב.")
        return
    if not config.api_key or config.api_key == "your_api_key_here":
        print("  אין מפתחות API ב-.env — לא ניתן למשוך מצב חי.")
        return
    try:
        from agents.binance_compat import create_binance_client, live_full_account_info

        client = create_binance_client(config.api_key, config.api_secret)
        acc = live_full_account_info(client)
        if acc is None:
            print("  נכשלה משיכת נתוני חשבון מ-Binance.")
            return
        print(f"  יתרת ארנק   : {_fmt_money(acc['wallet_balance'])} USDT")
        print(f"  פנוי למסחר  : {_fmt_money(acc['available_balance'])} USDT")
        print(f"  Equity כולל : {_fmt_money(acc['margin_balance'])} USDT")
        print(f"  PnL לא ממומש: {_fmt_money(acc['unrealized_pnl'])} USDT")

        positions = acc.get("positions", [])
        print(f"\n  פוזיציות פתוחות: {len(positions)}")
        for p in positions:
            print(
                f"    {p['symbol']:12} amt={p['positionAmt']} "
                f"entry={p['entryPrice']:.6f} uPnL={_fmt_money(p['unrealizedProfit'])} "
                f"lev={p['leverage']}x"
            )

        # Open orders — this is where the new SL/TP protective orders show up
        try:
            open_orders = client.futures_get_open_orders()
        except Exception as exc:
            print(f"  (לא ניתן למשוך הוראות פתוחות: {exc})")
            open_orders = []
        print(f"\n  הוראות הגנה פתוחות (SL/TP על הבורסה): {len(open_orders)}")
        for o in open_orders:
            print(
                f"    {o.get('symbol'):12} {o.get('type'):20} "
                f"side={o.get('side'):4} stop={o.get('stopPrice')} "
                f"closePosition={o.get('closePosition')}"
            )
        if not open_orders and positions:
            print(
                "  ⚠️  יש פוזיציה פתוחה אבל אין הוראות הגנה על הבורסה — "
                "הפוזיציה מוגנת רק כל עוד הבוט רץ."
            )
    except Exception as exc:
        print(f"  שגיאה במשיכת מצב חי: {exc}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Bot status summary")
    parser.add_argument("--live", action="store_true", help="Also fetch live Binance state")
    args = parser.parse_args()

    print(f"\nboynew — status @ {datetime.now().isoformat(timespec='seconds')}")
    print(f"mode: {'PAPER' if config.paper_trading else 'LIVE'} | "
          f"aggressive_hft={config.aggressive_hft} | db={config.db_path}")

    if not os.path.exists(config.db_path):
        print(f"\n⚠️  מסד הנתונים '{config.db_path}' לא קיים — הבוט עוד לא רץ בתיקייה הזו "
              f"(או DB_PATH מצביע למקום אחר).")
    else:
        repo = TradeRepository(db_path=config.db_path)
        show_db(repo)
        repo.close()

    if args.live:
        show_live()

    print()


if __name__ == "__main__":
    sys.exit(main())

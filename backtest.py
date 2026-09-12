#!/usr/bin/env python3
"""
backtest.py — האם לאסטרטגיה יש תוחלת חיובית? מדידה על נתוני שוק אמיתיים.

**זה הכלי שהיה צריך לרוץ לפני שנגענו בכסף אמיתי.** כל השאר — כיול, שערים,
גדלי פוזיציה — הם שיפורים של אסטרטגיה שמעולם לא נמדדה. זה מודד אותה.

השיטה, וכל פרט בה נבחר כדי שלא נשקר לעצמנו:

* **הפרדה בזמן.** המודל מתאמן על 60% הראשונים של ההיסטוריה ונבחן על 40%
  האחרונים, שהוא לא ראה מעולם. בלי זה כל backtest מחזיר תשואות פנטסטיות
  שלא קיימות בשוק.
* **אותם מחירים, אותה לוגיקה.** הפיצ'רים מ-`agents.features`, המודל מ-
  `agents.model`, נוסחת ה-SL/TP מ-`risk_manager`, העמלה מ-`.env` שלך.
  אין כאן אסטרטגיה חדשה — זו האסטרטגיה שלך, נמדדת.
* **סטופ לפני יעד.** אם נר אחד נוגע גם ב-SL וגם ב-TP, נרשם SL. אי אפשר
  לדעת מהנר מה קרה קודם, וההנחה הפסימית היא היחידה שלא מנפחת את התוצאה.
* **עמלה בכל עסקה.** כניסה + יציאה, לפי `ESTIMATED_TAKER_FEE_PCT`.

    ./venv/bin/python backtest.py                # 60 סימבולים, ברירת מחדל
    ./venv/bin/python backtest.py --symbols 120  # מדגם גדול, איטי יותר
    ./venv/bin/python backtest.py --equity 38    # $ לפי ההון האמיתי שלך
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import time
import urllib.parse
import urllib.request

import numpy as np
import pandas as pd

sys.path.insert(0, ".")
from agents.features import FEATURE_NAMES, compute_features  # noqa: E402
from agents.model import TradingModel  # noqa: E402
from config import TradingConfig  # noqa: E402

BASE = "https://fapi.binance.com"
logging.basicConfig(level=logging.WARNING, format="%(message)s")


# ----------------------------------------------------------------------
# נתונים
# ----------------------------------------------------------------------
def _get(path: str, params: dict | None = None, tries: int = 4):
    url = f"{BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=25) as r:
                return json.loads(r.read().decode())
        except Exception as exc:
            if attempt == tries - 1:
                print(f"  ! {path} נכשל: {exc}")
                return None
            time.sleep(2 ** attempt)
    return None


def universe(n: int, min_price: float) -> list[str]:
    """הסימבולים הנזילים ביותר — אותו קריטריון שהסורק משתמש בו."""
    rows = _get("/fapi/v1/ticker/24hr") or []
    out = []
    for r in rows:
        sym = r.get("symbol", "")
        if not sym.endswith("USDT") or "_" in sym:
            continue
        try:
            if float(r.get("lastPrice", 0)) < min_price:
                continue
            out.append((sym, float(r.get("quoteVolume", 0))))
        except (TypeError, ValueError):
            continue
    out.sort(key=lambda t: -t[1])
    return [s for s, _ in out[:n]]


def klines(symbol: str, interval: str, limit: int) -> pd.DataFrame | None:
    data = _get("/fapi/v1/klines", {"symbol": symbol, "interval": interval, "limit": limit})
    if not data or len(data) < 300:
        return None
    rows = []
    for c in data:
        try:
            rows.append({
                "open": float(c[1]), "high": float(c[2]), "low": float(c[3]),
                "close": float(c[4]),
                "volume": float(c[7]),          # נפח בציטוט — כמו fetch_ohlcv
                "taker_buy_quote": float(c[10]),
                "trade_count": float(c[8]),
            })
        except (TypeError, ValueError, IndexError):
            continue
    return pd.DataFrame(rows) if len(rows) >= 300 else None


# ----------------------------------------------------------------------
# סימולציית העסקה — לוגיקת היציאה האמיתית של הבוט
# ----------------------------------------------------------------------
def simulate(df, i, direction, entry, sl_pct, tp_pct, cfg, bars_left):
    """
    מחזיר (תשואה_באחוזים_לפני_עמלה, סיבת_יציאה, נרות_שהוחזקו).

    שלוש היציאות שכיסו ~90% מהעסקאות בפועל: סטופ, יעד, ונעילת רווח.
    """
    lock_on = bool(getattr(cfg, "profit_lock_enabled", True))
    trig = float(getattr(cfg, "profit_lock_trigger_pct", 0.006) or 0.006)
    retr = float(getattr(cfg, "profit_lock_retrace_pct", 0.003) or 0.003)
    min_net = float(getattr(cfg, "profit_lock_min_net_pct", 0.0) or 0.0)

    stale_sec = float(getattr(cfg, "stale_exit_seconds", 0) or 0)
    tf_sec = {"1m": 60, "3m": 180, "5m": 300, "15m": 900, "30m": 1800, "1h": 3600}.get(
        cfg.hft_timeframe, 180)
    stale_bars = int(stale_sec / tf_sec) if stale_sec > 0 else 0

    long = direction == "LONG"
    sl = entry * (1 - sl_pct) if long else entry * (1 + sl_pct)
    tp = entry * (1 + tp_pct) if long else entry * (1 - tp_pct)
    peak = 0.0          # התזוזה הטובה ביותר לטובתנו, באחוזים
    armed = False
    locked = 0.0        # הרווח שהסטופ הנגרר כבר מבטיח

    for k in range(1, bars_left + 1):
        hi, lo, cl = df["high"].iloc[i + k], df["low"].iloc[i + k], df["close"].iloc[i + k]

        # סטופ נבדק ראשון — ההנחה הפסימית
        if (long and lo <= sl) or (not long and hi >= sl):
            # אחרי דריכה זה הסטופ הנגרר, ולכן התוצאה היא הרווח שנעל —
            # `peak - retr` היה מתעלם מרצפת profit_lock_min_net_pct.
            return (locked if armed else -sl_pct), \
                   ("profit_lock" if armed else "stop_loss"), k
        if (long and hi >= tp) or (not long and lo <= tp):
            return tp_pct, "take_profit", k

        fav = (hi - entry) / entry if long else (entry - lo) / entry
        peak = max(peak, fav)
        if lock_on and not armed and peak >= trig:
            armed = True
        if armed:
            # הסטופ עולה אחרי המחיר; הרווח הנעול לא יורד מתחת ל-min_net
            # ולא נסוג — סטופ נגרר זז רק לכיוון אחד.
            locked = max(locked, peak - retr, min_net)
            sl = entry * (1 + locked) if long else entry * (1 - locked)

        if stale_bars and k >= stale_bars:
            return ((cl - entry) / entry if long else (entry - cl) / entry), "stale", k

    cl = df["close"].iloc[i + bars_left]
    return ((cl - entry) / entry if long else (entry - cl) / entry), "end_of_data", bars_left


def notional(cfg, equity: float) -> float:
    """מה שהמנוע באמת ישלח — כולל שתי התקרות (risk_manager.py:541)."""
    pos = max(1, int(cfg.hft_max_open_positions))
    lev = float(cfg.leverage)
    slice_m = equity / pos
    n = slice_m * float(cfg.size_base_pct) * lev
    return min(n, min(equity * float(cfg.live_max_margin_fraction) * lev, slice_m * lev))


# ----------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbols", type=int, default=60)
    ap.add_argument("--candles", type=int, default=1500, help="מקסימום 1500 לבקשה")
    ap.add_argument("--equity", type=float, default=0.0, help="0 = לפי .env")
    ap.add_argument("--train-frac", type=float, default=0.60)
    args = ap.parse_args()

    cfg = TradingConfig()
    equity = args.equity or 38.0
    fee = float(cfg.estimated_taker_fee_pct)
    if getattr(cfg, "maker_entry_enabled", False):
        roundtrip_fee = float(getattr(cfg, "estimated_maker_fee_pct", 0.0002) or 0.0002) + fee
    else:
        roundtrip_fee = fee * 2
    notional_usd = notional(cfg, equity)

    print("=" * 68)
    print("  BACKTEST — נתוני שוק אמיתיים, מחוץ למדגם")
    print("=" * 68)
    print(f"  טווח נרות      : {cfg.hft_timeframe}")
    print(f"  סף כניסה       : {cfg.score_entry}")
    print(f"  SL / TP        : {cfg.sl_min_pct:.3%}-{cfg.sl_max_pct:.3%} / "
          f"{cfg.tp_min_pct:.3%}-{cfg.tp_max_pct:.3%}  (יחס {cfg.tp_sl_ratio})")
    print(f"  נעילת רווח     : {'כן' if cfg.profit_lock_enabled else 'לא'} — "
          f"דריכה {cfg.profit_lock_trigger_pct:.2%}, נסיגה {cfg.profit_lock_retrace_pct:.2%}")
    print(f"  עמלת סבב       : {roundtrip_fee:.4%}")
    print(f"  נוטיונל לפוזיציה: {notional_usd:.2f}$  (הון {equity:.2f}$, מינוף {cfg.leverage}x)")
    print()

    syms = universe(args.symbols, float(cfg.min_symbol_price_usdt))
    if not syms:
        print("  ! לא הצלחתי להביא את היקום מ-Binance. בדוק חיבור/VPN.")
        return 2
    print(f"  מוריד {len(syms)} סימבולים × {args.candles} נרות ...")

    frames = {}
    for n, s in enumerate(syms, 1):
        df = klines(s, cfg.hft_timeframe, args.candles)
        if df is None:
            continue
        f = compute_features(df)
        if f is None or len(f) < 400:
            continue
        frames[s] = f.reset_index(drop=True)
        if n % 20 == 0:
            print(f"    {n}/{len(syms)} ...")
        time.sleep(0.06)          # מתחת למגבלת המשקל של Binance

    if len(frames) < 25:
        print(f"  ! רק {len(frames)} סימבולים שמישים — צריך 25 לפחות.")
        return 2
    print(f"  {len(frames)} סימבולים נטענו.\n")

    # ---------- אימון על העבר בלבד ----------
    horizon = int(getattr(cfg, "ml_label_horizon", 5) or 5)
    thresh = float(getattr(cfg, "ml_label_threshold", 0.0005) or 0.0005)
    model = TradingModel()
    split = {}
    for s, f in frames.items():
        cut = int(len(f) * args.train_frac)
        split[s] = cut
        model.stage(s, f.iloc[:cut], FEATURE_NAMES, horizon=horizon, threshold=thresh)

    print("  מאמן את המודל על 60% הראשונים ...")
    t0 = time.time()
    if not model.train_global(FEATURE_NAMES, n_folds=4, stale_sec=0):
        print("  ! האימון נכשל.")
        return 2
    g = model.get_training_stats("__GLOBAL__") or {}
    print(f"    {g.get('n_samples', 0):,} שורות, {time.time()-t0:.0f}ש | "
          f"יתרון ממוצע {g.get('edge', 0):+.3f}\n")

    # ---------- סימולציה על 40% שהמודל לא ראה ----------
    print("  סוחר על 40% האחרונים (מחוץ למדגם) ...")
    scaler = model.scalers[model.GLOBAL_KEY]
    gm = model.models[model.GLOBAL_KEY]
    labels = g.get("class_labels", [0, 1, 2])
    dir_map = {0: "SHORT", 1: "FLAT", 2: "LONG"}

    trades = []
    for s, f in frames.items():
        rel = float((model.get_training_stats(s) or {}).get("reliability", 0.0) or 0.0)
        mult = TradingModel._edge_multiplier(rel)
        if mult <= 0:
            continue
        cut = split[s]
        test = f.iloc[cut:].reset_index(drop=True)
        X = test[FEATURE_NAMES].to_numpy(dtype=float)
        ok = ~np.isnan(X).any(axis=1)
        if ok.sum() < 50:
            continue
        proba = gm.predict_proba(scaler.transform(X[ok]))
        idx_map = np.where(ok)[0]
        busy_until = -1
        for row, bar in enumerate(idx_map):
            if bar <= busy_until or bar + 5 >= len(test):
                continue
            p = proba[row]
            j = int(p.argmax())
            lab = int(labels[j]) if j < len(labels) else j
            direction = dir_map.get(lab, "FLAT")
            score = float(p[j]) * mult * 100.0
            if direction == "FLAT" or score < cfg.score_entry:
                continue

            entry = float(test["close"].iloc[bar])
            atr = float(test["atr_14"].iloc[bar] or 0.0)
            if entry <= 0 or atr <= 0:
                continue
            # אותה נוסחה בדיוק כמו risk_manager.py:507-516, טייר BASE
            scaled = (atr / entry) * 0.85
            sl_pct = max(cfg.sl_min_pct, min(cfg.sl_max_pct, scaled))
            tp_pct = max(cfg.tp_min_pct, min(cfg.tp_max_pct, scaled * cfg.tp_sl_ratio))
            mr = float(getattr(cfg, "min_tp_sl_ratio", 0) or 0)
            if mr > 0 and tp_pct < sl_pct * mr:
                if sl_pct * mr <= cfg.tp_max_pct:
                    tp_pct = sl_pct * mr
                else:
                    tp_pct = cfg.tp_max_pct
                    sl_pct = max(cfg.sl_min_pct, tp_pct / mr)

            gross, why, held = simulate(
                test, bar, direction, entry, sl_pct, tp_pct, cfg,
                min(200, len(test) - bar - 1))
            trades.append({
                "symbol": s, "dir": direction, "score": score,
                "gross_pct": gross, "net_pct": gross - roundtrip_fee,
                "reason": why, "bars": held,
            })
            busy_until = bar + held

    if not trades:
        print("\n  אפס עסקאות. הסף חוסם הכול — הורד את SCORE_ENTRY או בדוק את היתרון.")
        return 1

    # ---------- תוצאות ----------
    t = pd.DataFrame(trades)
    t["net_usd"] = t["net_pct"] * notional_usd
    wins, losses = t[t.net_usd > 0], t[t.net_usd <= 0]
    gp, gl = wins.net_usd.sum(), -losses.net_usd.sum()
    pf = gp / gl if gl > 0 else float("inf")
    wr = len(wins) / len(t)
    aw = wins.net_usd.mean() if len(wins) else 0.0
    al = -losses.net_usd.mean() if len(losses) else 0.0
    rr = aw / al if al > 0 else float("inf")

    print("\n" + "=" * 68)
    print(f"  {len(t)} עסקאות מחוץ למדגם")
    print("=" * 68)
    print(f"  אחוז הצלחה        : {wr:6.1%}   ({len(wins)}/{len(t)})")
    print(f"  רווח ממוצע למנצחת : {aw:+7.3f}$")
    print(f"  הפסד ממוצע למפסידה: {-al:+7.3f}$")
    print(f"  R:R               : {rr:6.2f}")
    print(f"  סף איזון נדרש     : {1/(1+rr):6.1%}   {'✓ עוברים' if wr > 1/(1+rr) else '✗ לא עוברים'}")
    print(f"  Profit Factor     : {pf:6.2f}")
    print(f"  נטו               : {t.net_usd.sum():+7.2f}$   "
          f"({t.net_usd.sum()/equity:+.1%} מההון)")
    print(f"  לפני עמלות        : {(t.gross_pct*notional_usd).sum():+7.2f}$")
    print(f"  עמלות             : {-roundtrip_fee*notional_usd*len(t):+7.2f}$")

    print("\n  לפי סיבת יציאה:")
    for why, grp in t.groupby("reason"):
        print(f"    {why:<16} {len(grp):4d} | {grp.net_usd.sum():+7.2f}$ | "
              f"ממוצע {grp.net_usd.mean():+.3f}$")

    print("\n  רגישות לסף הכניסה:")
    print(f"    {'סף':>5} {'עסקאות':>8} {'הצלחה':>8} {'PF':>7} {'נטו $':>9}")
    for th in (cfg.score_entry, 65, 70, 75, 80, 85):
        sub = t[t.score >= th]
        if len(sub) < 10:
            print(f"    {th:>5.0f} {len(sub):>8d}  — מדגם קטן מדי")
            continue
        sw = sub[sub.net_usd > 0]
        sl_ = sub[sub.net_usd <= 0]
        spf = sw.net_usd.sum() / max(-sl_.net_usd.sum(), 1e-9)
        print(f"    {th:>5.0f} {len(sub):>8d} {len(sw)/len(sub):>7.1%} "
              f"{spf:>7.2f} {sub.net_usd.sum():>+9.2f}")

    print("\n" + "=" * 68)
    if pf >= 1.20 and len(t) >= 100:
        print("  פסק דין: תוחלת חיובית משמעותית. שווה להריץ בלייב.")
    elif pf >= 1.05:
        print("  פסק דין: תוחלת חיובית גבולית. לא מספיק כדי לסמוך על זה.")
    elif pf >= 0.95:
        print("  פסק דין: אפס תוחלת — העמלות יאכלו את החשבון לאט.")
    else:
        print("  פסק דין: תוחלת שלילית. הרצה בלייב תפסיד כסף בהתמדה.")
        print("  זה לא בעיית כיול — אין לאסטרטגיה יתרון על הנתונים האלה.")
    print("=" * 68)
    return 0


if __name__ == "__main__":
    sys.exit(main())

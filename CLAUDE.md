# boynew — Binance USDT-M Futures Bot

## מה זה
בוט מסחר אוטונומי ל־Binance Futures (USDT-M). שני מסלולים:
- **`AGGRESSIVE_HFT=true` (ברירת מחדל):** לולאה מהירה — סריקת יקום, דירוג הזדמנויות (מודל + פיצ’רים), `risk.evaluate`, כניסה/יציאה (`hft_open` / `hft_close`), רוטציית הון.
- **`AGGRESSIVE_HFT=false`:** מסלול קלאסי — סימבולים מ־`SYMBOLS`, OHLCV → אנליזה → אות → `assess_risk` → `execute_signal`.

## הרצה
```bash
cd boynew
./venv/bin/python main.py              # paper (ברירת מחדל מ-.env)
./venv/bin/python main.py --live       # לייב — דורש מפתחות ב-.env
./venv/bin/python main.py --no-dashboard
```
תבנית משתני סביבה: **`.env.example`** (העתק ל־`.env`, אל תעלה מפתחות לגיט).

## קבצים מרכזיים
| קובץ | תפקיד |
|------|--------|
| `main.py` | נקודת כניסה, `TradingSystem`, `_run_hft_loop` / `_run_classic_loop` |
| `config.py` | `TradingConfig` — כל הפרמטרים מ־env |
| `agents/execution.py` | הזמנות, פילטרי בורסה, `refine_sl_tp_prices`, HFT |
| `agents/risk_manager.py` | `evaluate` (HFT), `assess_risk` (קלאסי), יציאות stale, drawdown |
| `agents/scanner.py` | `discover_universe`, `scan_and_rank`, סינון מחיר מינימלי |
| `agents/binance_compat.py` | לקוח בלי `ping()` בבנייה |
| `database/repository.py` | SQLite |

## פסי בטיחות (אוטומטיים — לא דורשים ניהול ידני)
בהפעלה מודפסת שורה `Safety rails (automatic) | ...` עם: paper/live, HFT, מקס פוזיציות, מקס מרג’ין לפוזיציה, **`min_notional`** (רצפת מינימום לנוטיונל ב-USDT — כדי לא לסחור ב"סנטים"), kill על drawdown יומי/סשן, stale exit, מחיר מינימלי לסימבול, סף ציון.

ב־`.env`: `HFT_MIN_NOTIONAL_USDT` (ברירת מחדל 1). בחלקים בבורסה מינימום 5 USDT — אם הזמנות נדחות, העלה ל־5.

בנוסף: `config.validate()` בודק טווחים ל־`max_margin_fraction`, גדלי טייר, וכו’.

## הערות למפתח/לעוזר AI
- **אין ערובת רווח** — זה כלי מסחר; שוק = סיכון.
- SL/TP למטבעות זולים: `refine_sl_tp_prices` + טעינת `exchangeInfo` גם ב־paper.
- סימבולים מתחת ל־`MIN_SYMBOL_PRICE_USDT` (ברירת מחדל 0.05) נזרקים בסריקה.

## גרסה / מצב
קוד נבדק עם `python -m compileall` ו־`TradingConfig().validate()`. עדכון אחרון של מסמך זה: ידני — שמור סנכרון עם `config.py` כשמוסיפים משתני env.

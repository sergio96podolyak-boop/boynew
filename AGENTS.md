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
| `agents/agent_monitor.py` | באס ניטור — כל סוכן מדווח פעילות (throttle, crash-safe) ל-DB עבור הדשבורד |
| `dashboard.py` | Streamlit — מרכז שליטה חי: כרטיסי סוכנים + זרם פעילות, תיק, עסקאות, גרפים |
| `dashboard_floor.py` | **רצפת המסחר** — תצוגת ה-HTML/SVG הראשית בראש הדשבורד (מודול עצמאי) |
| `dashboard_market.py` | **פאנל שוק חי** — נרות/ספר/סרט מ-Binance WebSocket ישירות לדפדפן |
| `database/repository.py` | SQLite (כולל `agent_activity` לפיד הסוכנים) |

## פסי בטיחות (אוטומטיים — לא דורשים ניהול ידני)
בהפעלה מודפסת שורה `Safety rails (automatic) | ...` עם: paper/live, HFT, מקס פוזיציות, מקס מרג’ין לפוזיציה, **`min_notional`** (רצפת מינימום לנוטיונל ב-USDT — כדי לא לסחור ב"סנטים"), kill על drawdown יומי/סשן, stale exit, מחיר מינימלי לסימבול, סף ציון.

ב־`.env`: `HFT_MIN_NOTIONAL_USDT` (ברירת מחדל 1). בחלקים בבורסה מינימום 5 USDT — אם הזמנות נדחות, העלה ל־5.

בנוסף: `config.validate()` בודק טווחים ל־`max_margin_fraction`, גדלי טייר, וכו’.

**הגנת בורסה (SL/TP אמיתיים):** בלייב, בכל כניסה (`hft_open` / `execute_signal` / סנכרון פוזיציות בהפעלה) נשלחות הוראות `STOP_MARKET` + `TAKE_PROFIT_MARKET` עם `closePosition=true` ל-Binance (`place_protective_orders`). כך הפוזיציה מוגנת גם אם הבוט נעצר/קורס/מתנתק — מוניטור הלולאה הוא רק גיבוי. בסגירה (`_live_close_position`) ההוראות שנשארו מבוטלות (`_cancel_symbol_orders`). כשל ב-SL נרשם כ-CRITICAL בלוג.

## בדיקת מצב
`./venv/bin/python status.py` — סיכום מה-DB (ביצועים, פתוחות/סגורות, סיבות יציאה, snapshot, אירועים). `--live` מוסיף מצב חי מ-Binance: יתרה, פוזיציות, והוראות ההגנה הפעילות.

## מרכז שליטה (דשבורד)
הדשבורד (`http://localhost:8501`, עולה אוטומטית עם `main.py`) מציג בראש כרטיס לכל סוכן — System / Scanner / Model / RiskManager / Execution / Analyzer — עם נורית סטטוס (פעיל/עובד/מושהה/עצור), הפעולה האחרונה, וזמן. מתחת: זרם פעילות חי. הנתונים מגיעים מטבלת `agent_activity` שאליה הלולאה מדווחת דרך `agent_monitor`. רענון כל 4 שניות.

## רצפת המסחר (`dashboard_floor.py`)
התצוגה הראשית בראש הדשבורד — עמוד HTML אחד, סגור, שמוצג ב-iframe יחיד דרך
`components.html`. מודול עצמאי לגמרי: מקבל dict-ים מה-DB ומחזיר `(html, height)`.

**שמונה מקטעים, כולם מנתוני אמת:**
1. **סרגל טיקר** — מצב (נייר/חי), HFT, מנוע, מחזור, זמן פעילות (מ-`System/boot`), דופק אחרון, יקום, פוזיציות
2. **אריחי KPI** — הון, רווח מצטבר, רווח 24ש, אחוז הצלחה + PF, שארפ — עם ספארקליין מ-`portfolio_snapshots`
3. **צינור השלבים** — 7 שלבים (סריקה→מודיעין→ניקוד→החלטה→סיכון→ביצוע→למידה); סטטוס כל שלב נגזר מהסוכנים שבו
4. **ליבת הנחיל** — SVG מונפש: ליבה מרכזית + 8 כרטיסי סוכן (`FEATURED`) במשבצות **קבועות**, קווים חיים לליבה
5. **יומן פעילות** — זרם ממוזג של `agent_activity` + עסקאות שנסגרו (משם מגיע ה-±$ האמיתי)
6. **מסילת סוכנים** — כל 17 הסוכנים, עם היסטוגרמת פעילות אמיתית מהפיד
7. **קונצנזוס** — ממוצע `consensus` מ-`decision_audit` + אושרו/נדחו + מכפיל גודל ממוצע
8. **גרף הון** — עקומת equity + עמודות רווח/הפסד לכל עסקה

**כללי עבודה במודול:**
- **אין נתוני דמו בזרימה האמיתית.** אם המנוע כבוי, המקטעים מציגים "ממתין" ומסבירים
  איך להפעיל — אף פעם לא ממציאים מספרים. נתוני ההדגמה חיים רק ב-`_preview_data()`.
- כל מחרוזת מה-DB עוברת `esc()`. כל מספר עטוף ב-`.num` (LTR מבודד) כדי שסימן
  המינוס לא יקפוץ לסוף בתוך טקסט עברי.
- טקסט עברי ב-SVG מעוגן מימין: `text-anchor="start"` + `direction="rtl"` בקצה הימני
  של הכרטיס. עוגן משמאל גורם לטקסט לזלוג החוצה.
- **גובה ה-iframe מחושב ידנית** (`801 + rail_h + equity_h`) — Streamlit לא מודד תוכן
  בתוך רכיב HTML. הנוסחה כוילה מול מדידה בדפדפן ב-900–1700px. `scrolling=True`
  הוא רשת הביטחון לחלונות צרים. **אם משנים גבהים ב-CSS — לכיל מחדש.**
- הסוכנים ב-`FEATURED` יושבים במשבצות קבועות בכוונה: מיקום שמשתנה בכל רענון
  (כל 4 שניות) הופך את הלוח לבלתי-קריא.

**בדיקה ויזואלית בלי להריץ את המערכת:**
```bash
./venv/bin/python dashboard_floor.py preview.html   # קורא מ-trading.db אם קיים
```

## פאנל השוק החי (`dashboard_market.py`)
נרות, ספר פקודות וסרט עסקאות מגיעים **ישירות מ-Binance אל הדפדפן** דרך WebSocket
ציבורי (`wss://fstream.binance.com`) — בלי מפתחות API, בלי לעבור דרך פייתון.
מעליהם מצוירים קווי הבוט: מחיר כניסה, SL, TP, ומשולשי ביצוע מעסקאות שנסגרו.

**האילוץ שמעצב את כל המודול:** הדשבורד מרונדר מחדש כל 4 שניות. Streamlit מעביר את
ה-HTML כ-prop ל-iframe — אם ה-prop משתנה, ה-iframe נטען מחדש וה-WebSocket מת.
לכן ה-HTML כאן הוא **פונקציה טהורה של מצב הפוזיציות**: אין שעון, אין "לפני X שניות",
חותמות זמן הן epoch במילישניות, מחירים מעוגלים, מפתחות ממוינים. כל עוד הבוט לא פתח
או סגר פוזיציה — ה-HTML זהה בית-בית, React לא נוגע ב-iframe, והזרם ממשיך.

> ⚠️ **כל שינוי כאן חייב לשמור על התכונה הזו.** ערך שמשתנה בכל רענון = הבהוב
> ו-WebSocket שנופל כל 4 שניות. יש בדיקה שמאמתת את זה — הריצו אותה אחרי כל שינוי:
> ```python
> a = render_market_panel(...); b = render_market_panel(...); assert a == b
> ```

- הגרף נשאר **LTR** בכוונה (זמן שמאל→ימין, ציר מחיר מימין) — ככה כל פלטפורמת
  מסחר עובדת; היפוך לטובת RTL רק מבלבל. הטקסט סביבו בעברית.
- כשל רשת (חסימה, VPN, אין אינטרנט) מציג הסבר בעברית ולא שובר את שאר הדשבורד.
- תצוגה מקדימה: `./venv/bin/python dashboard_market.py preview.html`

## הערות למפתח/לעוזר AI
- **אין ערובת רווח** — זה כלי מסחר; שוק = סיכון.
- SL/TP למטבעות זולים: `refine_sl_tp_prices` + טעינת `exchangeInfo` גם ב־paper.
- הגנת SL/TP על הבורסה: `place_protective_orders` (one-way mode, `closePosition=true`).
- סימבולים מתחת ל־`MIN_SYMBOL_PRICE_USDT` (ברירת מחדל 0.05) נזרקים בסריקה.

## גרסה / מצב
קוד נבדק עם `python -m compileall` ו־`TradingConfig().validate()`. עדכון אחרון של מסמך זה: ידני — שמור סנכרון עם `config.py` כשמוסיפים משתני env.

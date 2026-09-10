"""
רצפת המסחר (Trading Floor) — התצוגה הקולנועית של מערכת הסוכנים.

מודול עצמאי שמקבל נתונים אמיתיים מה-DB ומחזיר עמוד HTML אחד, סגור,
שמוצג בתוך iframe יחיד ב-Streamlit. כל המספרים כאן אמיתיים — אין דמו,
אין placeholders. אם המנוע לא רץ, הלוח מציג "ממתין" במקום להמציא נתונים.

מבנה התצוגה (מימין לשמאל):
    1. סרגל טיקר      — מצב מערכת, מחזור, זמן פעילות, שעה
    2. אריחי KPI      — הון, רווח, דיוק, Profit Factor + ספארקליין אמיתי
    3. צינור השלבים   — 7 שלבים מסריקה ועד למידה, עם סטטוס חי לכל שלב
    4. ליבת הנחיל     — SVG מונפש: ליבה מרכזית + סוכנים מסביב, קווים חיים
    5. יומן פעילות    — זרם אירועים ממוזג (פעילות סוכנים + עסקאות שנסגרו)
    6. מסילת סוכנים   — כל 17 הסוכנים ככרטיסים ממוספרים
    7. קונצנזוס       — ממוצע ההסכמה של ועדת ההחלטה
    8. גרף הון        — עקומת הון + עמודות רווח/הפסד

שימוש:
    from dashboard_floor import render_trading_floor, render_floor_component
    render_floor_component(**data)
"""

from __future__ import annotations

import html as _html
import math
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Sequence, Tuple

# ---------------------------------------------------------------------------
# מפרט הסוכנים — סדר, אייקון, שם עברי, צבע, תפקיד
# ---------------------------------------------------------------------------
# הצבע הוא זהות ויזואלית: אותו סוכן מקבל את אותו צבע בליבה, במסילה וביומן.

AGENTS: List[Tuple[str, str, str, str, str]] = [
    # (key,             icon, label,               color,     role)
    ("System",          "🧠", "מערכת",             "#a78bfa", "ליבה"),
    ("LiveGuard",       "🔐", "נעילת לייב",         "#f43f5e", "שמירה"),
    ("Scanner",         "🔭", "סורק שוק",           "#22d3ee", "סריקה"),
    ("OpportunityRadar", "🧭", "רדאר הזדמנויות",    "#60a5fa", "סריקה"),
    ("Regime",          "🌐", "משטר שוק",           "#38bdf8", "מודיעין"),
    ("Flow",            "🌊", "זרימת שוק",          "#2dd4bf", "מודיעין"),
    ("News",            "📰", "חדשות וסנטימנט",     "#fbbf24", "מודיעין"),
    ("Catalyst",        "🧨", "קטליזטורים",         "#fb7185", "מודיעין"),
    ("Model",           "🤖", "מודל ML",            "#818cf8", "ניקוד"),
    ("StrategyLab",     "🧪", "מעבדת אסטרטגיות",    "#e879f9", "ניקוד"),
    ("Decision",        "⚖️", "ועדת החלטה",         "#c084fc", "החלטה"),
    ("Indirect",        "🧩", "אסטרטגיות עקיפות",   "#94a3b8", "החלטה"),
    ("RiskManager",     "🛡️", "ניהול סיכון",        "#f87171", "סיכון"),
    ("Capital",         "💸", "הקצאת הון",          "#34d399", "סיכון"),
    ("Execution",       "⚡", "ביצוע",              "#facc15", "ביצוע"),
    ("Runner",          "🏁", "רווח רץ",            "#4ade80", "ביצוע"),
    ("Analyzer",        "📚", "לומד",               "#a3e635", "למידה"),
]

AGENT_BY_KEY: Dict[str, Tuple[str, str, str, str, str]] = {a[0]: a for a in AGENTS}

# ---------------------------------------------------------------------------
# צינור השלבים — כל שלב וקבוצת הסוכנים ששייכת אליו
# ---------------------------------------------------------------------------

STAGES: List[Tuple[str, str, List[str]]] = [
    ("01", "סריקה",   ["Scanner", "OpportunityRadar"]),
    ("02", "מודיעין", ["Regime", "Flow", "News", "Catalyst"]),
    ("03", "ניקוד",   ["Model", "StrategyLab"]),
    ("04", "החלטה",   ["Decision", "Indirect"]),
    ("05", "סיכון",   ["RiskManager", "Capital"]),
    ("06", "ביצוע",   ["Execution", "Runner"]),
    ("07", "למידה",   ["Analyzer"]),
]

# כמה שניות בלי דיווח עד שסוכן נחשב "לא חי".
# סריקה מלאה של היקום עם אימון מודל לכל סימבול יכולה לקחת דקה — לכן חלון נדיב.
LIVE_WINDOW_SEC = 180
WORKING_WINDOW_SEC = 25

STATUS_COLORS = {
    "active":  "#22e08a",
    "working": "#35d6ff",
    "paused":  "#ffb020",
    "stopped": "#ff4d6a",
    "idle":    "#5b6b7d",
}

STATUS_HE = {
    "active":  "פעיל",
    "working": "עובד",
    "paused":  "מושהה",
    "stopped": "עצור",
    "idle":    "ממתין",
}

# תרגום פעולות נפוצות לעברית ליומן הפעילות
ACTION_HE = {
    "boot": "אתחול", "scan": "סריקה", "rank": "דירוג", "score": "ניקוד",
    "state": "מצב", "sentiment": "סנטימנט", "tradingview": "אות חיצוני",
    "evaluate": "הערכה", "risk": "סיכון", "open": "כניסה", "close": "יציאה",
    "entry": "כניסה", "exit": "יציאה", "hft_open": "כניסה מהירה",
    "hft_close": "יציאה מהירה", "learn": "למידה", "train": "אימון",
    "allocate": "הקצאה", "rotate": "רוטציה", "block": "חסימה",
    "approve": "אישור", "reject": "דחייה", "guard": "שמירה",
    "heartbeat": "דופק", "radar": "רדאר", "lab": "מעבדה",
    "settle": "התחשבנות", "protect": "הגנה", "sync": "סנכרון",
}


# ---------------------------------------------------------------------------
# עזרים
# ---------------------------------------------------------------------------

def esc(value: Any) -> str:
    """בריחת HTML בטוחה לכל ערך שמגיע מה-DB."""
    return _html.escape(str(value if value is not None else ""))


def _f(value: Any, default: float = 0.0) -> float:
    """המרה בטוחה ל-float."""
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def _i(value: Any, default: int = 0) -> int:
    try:
        if value is None:
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def _parse_ts(ts: Any) -> Optional[datetime]:
    """ISO-8601 -> datetime מודע-אזור (UTC). None אם לא ניתן לפענח."""
    if not ts:
        return None
    try:
        dt = datetime.fromisoformat(str(ts))
    except (TypeError, ValueError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def _age_sec(ts: Any) -> Optional[float]:
    """כמה שניות עברו מאז חותמת הזמן."""
    dt = _parse_ts(ts)
    if dt is None:
        return None
    return max(0.0, (datetime.now(timezone.utc) - dt).total_seconds())


def time_ago_he(ts: Any) -> str:
    """'לפני 12 ש׳' / 'לפני 3 דק׳' / 'לפני 2 שע׳'."""
    age = _age_sec(ts)
    if age is None:
        return "—"
    if age < 60:
        return f"לפני {int(age)} ש׳"
    if age < 3600:
        return f"לפני {int(age // 60)} דק׳"
    if age < 86400:
        return f"לפני {int(age // 3600)} שע׳"
    return f"לפני {int(age // 86400)} ימ׳"


def dur_he(seconds: float) -> str:
    """משך זמן קריא: '3ד 12ש' / '5שע 20ד' / '2י 4שע'."""
    seconds = max(0, int(seconds))
    d, rem = divmod(seconds, 86400)
    h, rem = divmod(rem, 3600)
    m, s = divmod(rem, 60)
    if d:
        return f"{d}י {h}שע"
    if h:
        return f"{h}שע {m}ד"
    if m:
        return f"{m}ד {s}ש"
    return f"{s}ש"


def fmt_usd(value: Any, decimals: int = 2) -> str:
    """סכום בדולרים עם סימן ופסיקים."""
    v = _f(value)
    sign = "-" if v < 0 else ""
    return f"{sign}${abs(v):,.{decimals}f}"


def fmt_signed(value: Any, decimals: int = 2) -> str:
    """סכום עם + מפורש לחיוביים — לשימוש ביומן הפעילות."""
    v = _f(value)
    sign = "+" if v >= 0 else "-"
    return f"{sign}${abs(v):,.{decimals}f}"


def fmt_pct(value: Any, decimals: int = 1) -> str:
    return f"{_f(value) * 100:.{decimals}f}%"


def num(text: Any, cls: str = "") -> str:
    """עוטף מספר ב-LTR מונוספייס כדי שלא יישבר בתוך טקסט RTL."""
    klass = f"num {cls}".strip()
    return f'<span dir="ltr" class="{klass}">{esc(text)}</span>'


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def agent_status(row: Optional[Dict[str, Any]]) -> str:
    """
    סטטוס אפקטיבי של סוכן: מה שהוא דיווח, אבל רק אם הדיווח טרי.
    סוכן ששתק יותר מ-LIVE_WINDOW_SEC נחשב 'ממתין' בלי קשר למה שכתב.
    """
    if not row:
        return "idle"
    age = _age_sec(row.get("timestamp"))
    if age is None or age > LIVE_WINDOW_SEC:
        return "idle"
    raw = str(row.get("status") or "active").lower()
    if raw not in STATUS_COLORS:
        raw = "active"
    # דיווח ממש טרי מוצג כ"עובד" גם אם נרשם כ-active — כך רואים את הפעימה.
    if raw == "active" and age <= WORKING_WINDOW_SEC:
        return "working"
    return raw


def action_he(action: Any) -> str:
    key = str(action or "").lower()
    return ACTION_HE.get(key, key or "—")


# ---------------------------------------------------------------------------
# בוני גרפים ב-SVG — הכל מחושב בפייתון מנתונים אמיתיים
# ---------------------------------------------------------------------------

def spark_path(values: Sequence[float], width: float, height: float,
               pad: float = 2.0) -> Tuple[str, str]:
    """
    מחזיר (path של הקו, path של השטח מתחתיו) לספארקליין.
    מחרוזות ריקות אם אין מספיק נתונים.
    """
    pts = [_f(v) for v in values if v is not None]
    if len(pts) < 2:
        return "", ""

    lo, hi = min(pts), max(pts)
    span = hi - lo
    if span <= 0:
        span = abs(hi) * 0.02 or 1.0
        lo -= span / 2

    inner_h = height - pad * 2
    step = width / (len(pts) - 1)

    coords = []
    for i, v in enumerate(pts):
        x = i * step
        y = pad + inner_h * (1 - (v - lo) / span)
        coords.append((x, y))

    line = "M " + " L ".join(f"{x:.1f},{y:.1f}" for x, y in coords)
    area = line + f" L {coords[-1][0]:.1f},{height:.1f} L {coords[0][0]:.1f},{height:.1f} Z"
    return line, area


def bar_series(values: Sequence[float], width: float, height: float,
               color_pos: str = "#22e08a", color_neg: str = "#ff4d6a") -> str:
    """סדרת עמודות דו-כיוונית (רווח/הפסד) כ-SVG rects."""
    pts = [_f(v) for v in values]
    if not pts:
        return ""
    peak = max((abs(v) for v in pts), default=0.0) or 1.0
    slot = width / len(pts)
    bw = max(1.0, slot * 0.62)
    mid = height / 2
    out = []
    for i, v in enumerate(pts):
        h = abs(v) / peak * (mid - 1)
        h = max(h, 0.8)
        x = i * slot + (slot - bw) / 2
        y = mid - h if v >= 0 else mid
        color = color_pos if v >= 0 else color_neg
        out.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw:.1f}" height="{h:.1f}" '
            f'rx="{min(1.0, bw / 3):.1f}" fill="{color}" opacity=".78"/>'
        )
    return "".join(out)


def mini_bars(values: Sequence[float], width: float, height: float, color: str) -> str:
    """עמודות חד-כיווניות קטנות — לכרטיס סוכן."""
    pts = [_f(v) for v in values]
    if not pts:
        return ""
    peak = max(pts) or 1.0
    slot = width / len(pts)
    bw = max(1.0, slot * 0.55)
    out = []
    for i, v in enumerate(pts):
        h = max(0.9, (v / peak) * (height - 1))
        x = i * slot + (slot - bw) / 2
        out.append(
            f'<rect x="{x:.1f}" y="{height - h:.1f}" width="{bw:.1f}" '
            f'height="{h:.1f}" rx=".7" fill="{color}" opacity="{0.35 + 0.5 * (v / peak):.2f}"/>'
        )
    return "".join(out)


def bucket_counts(timestamps: Sequence[Any], buckets: int = 14,
                  window_sec: float = 900.0) -> List[float]:
    """
    מחלק חותמות זמן לסלים לפי גיל — מייצר היסטוגרמת פעילות אמיתית.
    הסל האחרון = הכי עדכני.
    """
    out = [0.0] * buckets
    slot = window_sec / buckets
    for ts in timestamps:
        age = _age_sec(ts)
        if age is None or age > window_sec:
            continue
        idx = buckets - 1 - int(age // slot)
        if 0 <= idx < buckets:
            out[idx] += 1.0
    return out


# ---------------------------------------------------------------------------
# עיצוב — מחרוזת רגילה (לא f-string) כדי שסוגריים מסולסלים יישארו כפי שהם
# ---------------------------------------------------------------------------

FLOOR_CSS = """
<style>
@import url('https://fonts.googleapis.com/css2?family=Heebo:wght@400;500;700;800;900&family=JetBrains+Mono:wght@400;500;700;800&display=swap');

:root{
  --bg:#04060a;
  --panel:rgba(11,17,25,.82);
  --panel-2:rgba(16,23,33,.9);
  --line:rgba(96,140,175,.14);
  --line-2:rgba(96,140,175,.28);
  --text:#e8f2f8;
  --muted:#7f93a6;
  --dim:#54677a;
  --green:#22e08a;
  --red:#ff4d6a;
  --cyan:#35d6ff;
  --amber:#ffb020;
  --violet:#a78bfa;
  --mono:'JetBrains Mono',ui-monospace,'SF Mono',Menlo,monospace;
  --sans:'Heebo',ui-sans-serif,system-ui,'Segoe UI',sans-serif;
}

*{box-sizing:border-box;}
html,body{margin:0;padding:0;background:var(--bg);}

.floor{
  font-family:var(--sans);
  color:var(--text);
  background:
    radial-gradient(1100px 500px at 78% -8%, rgba(53,214,255,.09), transparent 62%),
    radial-gradient(900px 460px at 12% 4%, rgba(167,139,250,.08), transparent 60%),
    linear-gradient(180deg,#04060a 0%,#05080e 46%,#04060a 100%);
  padding:14px;
  display:flex;
  flex-direction:column;
  gap:11px;
  position:relative;
  overflow:hidden;
}
/* רשת עדינה ברקע — נותנת עומק בלי להסיח */
.floor::before{
  content:"";position:absolute;inset:0;pointer-events:none;opacity:.4;
  background-image:linear-gradient(rgba(96,140,175,.05) 1px,transparent 1px),
                   linear-gradient(90deg,rgba(96,140,175,.05) 1px,transparent 1px);
  background-size:46px 46px;
  mask-image:radial-gradient(circle at 50% 30%,#000 0%,transparent 82%);
  -webkit-mask-image:radial-gradient(circle at 50% 30%,#000 0%,transparent 82%);
}
.floor > *{position:relative;z-index:1;}

.num{font-family:var(--mono);font-variant-numeric:tabular-nums;letter-spacing:-.2px;
  direction:ltr;unicode-bidi:isolate;}
.pos{color:var(--green);}
.neg{color:var(--red);}
.acc{color:var(--cyan);}

.panel{
  background:var(--panel);
  border:1px solid var(--line);
  border-radius:11px;
  backdrop-filter:blur(7px);
}
.cap{
  font-size:9.5px;font-weight:800;letter-spacing:1.5px;color:var(--dim);
  text-transform:uppercase;font-family:var(--mono);
}

/* ---------- 1. סרגל טיקר ---------- */
.ticker{
  display:flex;align-items:center;gap:9px;flex-wrap:wrap;
  padding:8px 12px;
  background:linear-gradient(90deg,rgba(16,23,33,.95),rgba(11,17,25,.75));
  border:1px solid var(--line);border-radius:10px;
}
.brand{display:flex;align-items:center;gap:8px;font-weight:900;font-size:14px;letter-spacing:.3px;}
.brand b{color:var(--cyan);}
.brand .dot{
  width:8px;height:8px;border-radius:50%;background:var(--green);
  box-shadow:0 0 0 0 rgba(34,224,138,.6);animation:beat 1.8s ease-out infinite;
}
.brand .dot.off{background:var(--red);animation:none;box-shadow:0 0 8px rgba(255,77,106,.5);}
@keyframes beat{
  0%{box-shadow:0 0 0 0 rgba(34,224,138,.55);}
  70%{box-shadow:0 0 0 9px rgba(34,224,138,0);}
  100%{box-shadow:0 0 0 0 rgba(34,224,138,0);}
}
.tsep{width:1px;height:16px;background:var(--line-2);}
.tchip{display:flex;align-items:center;gap:5px;font-size:10.5px;color:var(--muted);white-space:nowrap;}
.tchip b{color:var(--text);font-family:var(--mono);font-weight:700;font-size:11px;}
.tchip .lbl{font-size:9px;letter-spacing:.8px;text-transform:uppercase;color:var(--dim);font-family:var(--mono);}
.mode{
  padding:3px 9px;border-radius:999px;font-size:10px;font-weight:800;
  border:1px solid;font-family:var(--mono);letter-spacing:.5px;
}
.mode.paper{color:var(--cyan);border-color:rgba(53,214,255,.4);background:rgba(53,214,255,.09);}
.mode.live{color:var(--red);border-color:rgba(255,77,106,.45);background:rgba(255,77,106,.1);}
.push{margin-inline-start:auto;}

/* ---------- 2. אריחי KPI ---------- */
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(168px,1fr));gap:9px;}
.kpi{
  position:relative;overflow:hidden;
  padding:10px 12px 11px;border-radius:11px;
  background:linear-gradient(160deg,rgba(18,26,37,.9),rgba(10,15,22,.85));
  border:1px solid var(--line);
}
.kpi .k{font-size:9.5px;letter-spacing:1.1px;text-transform:uppercase;color:var(--dim);font-family:var(--mono);font-weight:700;}
.kpi .v{font-size:23px;font-weight:800;font-family:var(--mono);margin-top:3px;letter-spacing:-.6px;
  line-height:1.1;position:relative;z-index:2;text-shadow:0 2px 8px rgba(4,6,10,.95);}
.kpi .d{font-size:10.5px;color:var(--muted);margin-top:2px;position:relative;z-index:2;
  text-shadow:0 2px 8px rgba(4,6,10,.95);}
.kpi .spark{position:absolute;inset-inline:0;bottom:0;height:30px;opacity:.34;pointer-events:none;z-index:1;}
.kpi.hero{border-color:rgba(53,214,255,.3);box-shadow:inset 0 0 40px rgba(53,214,255,.06);}

/* ---------- 3. צינור השלבים ---------- */
.pipe{display:flex;gap:6px;padding:9px 10px;overflow-x:auto;}
.stage{
  flex:1 1 0;min-width:104px;padding:7px 9px;border-radius:9px;
  background:rgba(9,14,21,.7);border:1px solid var(--line);
  display:flex;flex-direction:column;gap:5px;position:relative;overflow:hidden;
}
.stage .top{display:flex;align-items:center;justify-content:space-between;gap:6px;}
.stage .no{font-family:var(--mono);font-size:9px;font-weight:800;color:var(--dim);letter-spacing:1px;}
.stage .nm{font-size:12px;font-weight:800;}
.stage .st{font-family:var(--mono);font-size:8.5px;font-weight:800;letter-spacing:1px;padding:1px 5px;border-radius:4px;}
.stage .bar{height:3px;border-radius:3px;background:rgba(96,140,175,.16);overflow:hidden;}
.stage .bar i{display:block;height:100%;border-radius:3px;transition:width .5s ease;}
.stage.run{border-color:rgba(53,214,255,.34);background:rgba(53,214,255,.05);}
.stage.run .bar i{animation:sweep 1.5s ease-in-out infinite;}
@keyframes sweep{0%,100%{opacity:.55;}50%{opacity:1;}}
.stage .agents{font-size:9px;color:var(--dim);font-family:var(--mono);letter-spacing:.2px;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}

/* ---------- 4+5. ליבה + יומן ---------- */
.mid{display:grid;grid-template-columns:1.62fr 1fr;gap:11px;}
@media(max-width:720px){.mid{grid-template-columns:1fr;}}

.corewrap{padding:8px;overflow:hidden;
  background:radial-gradient(circle at 50% 46%,rgba(13,26,44,.95) 0%,rgba(5,8,14,.98) 72%);}
.corewrap svg{display:block;width:100%;height:460px;}

/* אנימציות ה-SVG של הנחיל */
.lnk{stroke-dasharray:4 8;animation:flow 1.05s linear infinite;}
@keyframes flow{to{stroke-dashoffset:-24;}}
.halo{animation:halo 2.6s ease-out infinite;}
@keyframes halo{0%{r:26;opacity:.75;}100%{r:52;opacity:0;}}
.corepulse{animation:corep 2.8s ease-in-out infinite;}
@keyframes corep{0%,100%{opacity:.32;}50%{opacity:.85;}}
.spin{animation:spin 64s linear infinite;transform-origin:500px 262px;}
@keyframes spin{to{transform:rotate(360deg);}}
.eye{animation:blink 5.2s ease-in-out infinite;transform-origin:center;}
@keyframes blink{0%,92%,100%{transform:scaleY(1);}96%{transform:scaleY(.08);}}

.log{display:flex;flex-direction:column;min-height:0;}
.loghead{
  display:flex;align-items:center;justify-content:space-between;gap:8px;
  padding:8px 11px;border-bottom:1px solid var(--line);
}
.logbody{flex:1 1 auto;min-height:0;max-height:396px;overflow-y:auto;padding:3px 0;}
.logbody::-webkit-scrollbar{width:5px;}
.logbody::-webkit-scrollbar-thumb{background:rgba(96,140,175,.28);border-radius:4px;}
.row{
  display:grid;grid-template-columns:auto minmax(58px,auto) auto 1fr auto;
  align-items:center;gap:7px;padding:5px 10px;
  border-bottom:1px solid rgba(96,140,175,.07);font-size:11px;
}
.row:hover{background:rgba(53,214,255,.045);}
.row .led{width:6px;height:6px;border-radius:50%;flex:none;}
.row .ag{font-weight:800;font-size:10.5px;white-space:nowrap;}
.row .act{
  font-family:var(--mono);font-size:8.5px;font-weight:800;letter-spacing:.7px;
  padding:1px 5px;border-radius:4px;background:rgba(96,140,175,.13);
  color:var(--muted);white-space:nowrap;
}
.row .txt{color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
  font-size:10.5px;unicode-bidi:plaintext;}
.row .amt{font-family:var(--mono);font-weight:800;font-size:11px;white-space:nowrap;}
.row .tm{font-family:var(--mono);font-size:9px;color:var(--dim);white-space:nowrap;}
.row.settle{background:rgba(34,224,138,.05);}
.row.settle.loss{background:rgba(255,77,106,.05);}
.row.crit{background:rgba(255,77,106,.1);}
.empty{padding:26px 14px;text-align:center;color:var(--dim);font-size:12px;}

/* ---------- 6. מסילת סוכנים ---------- */
.rail{display:grid;grid-template-columns:repeat(auto-fit,minmax(132px,1fr));gap:7px;}
.acard{
  padding:7px 8px;border-radius:9px;position:relative;overflow:hidden;
  background:linear-gradient(155deg,rgba(17,24,34,.9),rgba(9,14,20,.85));
  border:1px solid var(--line);
}
.acard .hd{display:flex;align-items:center;gap:5px;}
.acard .ix{font-family:var(--mono);font-size:8px;font-weight:800;color:var(--dim);}
.acard .ic{font-size:12px;line-height:1;}
.acard .nm{font-size:10.5px;font-weight:800;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.acard .led{width:6px;height:6px;border-radius:50%;margin-inline-start:auto;flex:none;}
.acard .led.on{animation:beat2 1.6s ease-out infinite;}
@keyframes beat2{0%{box-shadow:0 0 0 0 currentColor;}70%{box-shadow:0 0 0 6px transparent;}100%{box-shadow:0 0 0 0 transparent;}}
.acard .sub{font-size:9px;color:var(--dim);font-family:var(--mono);margin-top:2px;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.acard .mb{margin-top:4px;height:15px;display:block;width:100%;}
.acard.dead{opacity:.42;}

/* ---------- 7. קונצנזוס ---------- */
.cons{display:flex;align-items:center;gap:12px;padding:9px 13px;flex-wrap:wrap;}
.cons .track{
  flex:1;min-width:180px;height:7px;border-radius:7px;
  background:rgba(96,140,175,.14);overflow:hidden;position:relative;
}
.cons .fill{
  height:100%;border-radius:7px;
  background:linear-gradient(90deg,#ff4d6a 0%,#ffb020 38%,#22e08a 100%);
  box-shadow:0 0 14px rgba(34,224,138,.35);transition:width .6s ease;
}
.cons .val{font-family:var(--mono);font-weight:800;font-size:15px;}

/* ---------- 8. גרף הון ---------- */
.eq{padding:10px 12px 6px;}
.eqhead{display:flex;align-items:baseline;justify-content:space-between;gap:10px;flex-wrap:wrap;margin-bottom:6px;}
.eq svg{display:block;width:100%;height:auto;}
</style>
"""


# ---------------------------------------------------------------------------
# 1. סרגל טיקר
# ---------------------------------------------------------------------------

def _ticker(config: Any, engine_live: bool, loop_no: int, uptime_sec: Optional[float],
            last_beat: Any, universe: int, open_n: int, max_n: int) -> str:
    """שורת המצב העליונה — הדופק של המערכת במבט אחד."""
    paper = bool(getattr(config, "paper_trading", True))
    hft = bool(getattr(config, "aggressive_hft", True))

    mode = ('<span class="mode paper">מסחר נייר</span>' if paper
            else '<span class="mode live">מסחר חי</span>')
    engine_txt = "מנוע פעיל" if engine_live else "מנוע מושבת"
    dot_cls = "dot" if engine_live else "dot off"

    def chip(label: str, value: str) -> str:
        return (f'<div class="tchip"><span class="lbl">{esc(label)}</span>'
                f'<b>{value}</b></div>')

    uptime_txt = dur_he(uptime_sec) if uptime_sec is not None else "—"
    now_utc = datetime.now(timezone.utc).strftime("%H:%M:%S")

    return f"""
    <div class="ticker">
      <div class="brand"><span class="{dot_cls}"></span>רצפת המסחר <b>· BOYNEW</b></div>
      <div class="tsep"></div>
      {mode}
      <span class="mode paper">{'HFT אגרסיבי' if hft else 'מסלול קלאסי'}</span>
      <div class="tsep"></div>
      {chip("מנוע", esc(engine_txt))}
      {chip("מחזור", f"#{loop_no:,}")}
      {chip("זמן פעילות", esc(uptime_txt))}
      {chip("דופק אחרון", esc(time_ago_he(last_beat)))}
      {chip("יקום", f"{universe:,}")}
      {chip("פוזיציות", f"{open_n}/{max_n}")}
      <div class="tchip push"><span class="lbl">UTC</span><b>{now_utc}</b></div>
    </div>
    """


# ---------------------------------------------------------------------------
# 2. אריחי KPI
# ---------------------------------------------------------------------------

def _kpi_tile(label: str, value: str, detail: str, cls: str = "",
              series: Optional[Sequence[float]] = None,
              color: str = "#35d6ff", hero: bool = False) -> str:
    """אריח בודד עם ספארקליין אמיתי ברקע (אם יש מספיק נתונים)."""
    spark = ""
    if series and len(list(series)) >= 2:
        line, area = spark_path(list(series), 240.0, 32.0)
        if line:
            uid = f"g{abs(hash((label, len(list(series))))) % 99999}"
            spark = (
                f'<svg class="spark" viewBox="0 0 240 32" preserveAspectRatio="none">'
                f'<defs><linearGradient id="{uid}" x1="0" y1="0" x2="0" y2="1">'
                f'<stop offset="0%" stop-color="{color}" stop-opacity=".42"/>'
                f'<stop offset="100%" stop-color="{color}" stop-opacity="0"/>'
                f'</linearGradient></defs>'
                f'<path d="{area}" fill="url(#{uid})"/>'
                f'<path d="{line}" fill="none" stroke="{color}" stroke-width="1.5" '
                f'stroke-linejoin="round" stroke-linecap="round"/></svg>'
            )
    return (
        f'<div class="kpi{" hero" if hero else ""}">{spark}'
        f'<div class="k">{esc(label)}</div>'
        f'<div class="v {cls}" dir="ltr">{esc(value)}</div>'
        f'<div class="d">{detail}</div></div>'
    )


def _kpis(equity: float, equity_series: List[float], total_pnl: float,
          total_pnl_pct: float, pnl24: float, win_rate: float, trades24: int,
          profit_factor: float, unrealized: float, pnl_series: List[float],
          sharpe: float, max_dd: float) -> str:
    """שורת המדדים הראשית — חמישה אריחים, כולם מנתוני אמת."""
    pnl_cls = "pos" if total_pnl >= 0 else "neg"
    p24_cls = "pos" if pnl24 >= 0 else "neg"
    un_cls = "pos" if unrealized >= 0 else "neg"
    pf_cls = "pos" if profit_factor >= 1.2 else ("neg" if 0 < profit_factor < 0.8 else "acc")
    wr_cls = "pos" if win_rate >= 0.5 else ("neg" if win_rate and win_rate < 0.4 else "")

    tiles = [
        _kpi_tile("הון כולל", fmt_usd(equity), 
                  f'רווח פתוח <span class="num {un_cls}">{esc(fmt_signed(unrealized))}</span>',
                  cls="", series=equity_series, color="#35d6ff", hero=True),
        _kpi_tile("רווח מצטבר", fmt_signed(total_pnl), 
                  f'<span class="num {pnl_cls}">{esc(f"{total_pnl_pct * 100:+.2f}%")}</span> מההון ההתחלתי',
                  cls=pnl_cls, series=pnl_series,
                  color="#22e08a" if total_pnl >= 0 else "#ff4d6a"),
        _kpi_tile("רווח 24 שעות", fmt_signed(pnl24), 
                  f'{num(trades24)} עסקאות נסגרו', cls=p24_cls),
        _kpi_tile("אחוז הצלחה", fmt_pct(win_rate), 
                  f'Profit Factor <span class="num {pf_cls}">{profit_factor:.2f}</span>',
                  cls=wr_cls),
        _kpi_tile("שארפ", f"{sharpe:.2f}", 
                  f'ירידה מקס׳ <span class="num neg">{esc(fmt_pct(max_dd))}</span>',
                  cls="acc" if sharpe > 0 else ""),
    ]
    return f'<div class="kpis">{"".join(tiles)}</div>'


# ---------------------------------------------------------------------------
# 3. צינור השלבים
# ---------------------------------------------------------------------------

def _pipeline(summary: Dict[str, Dict[str, Any]]) -> str:
    """
    שבעה שלבים מסריקה ועד למידה. הסטטוס של כל שלב נגזר מהסוכנים שבו:
    אם לפחות אחד עובד עכשיו — השלב 'רץ'. אם כולם שקטו — 'ממתין'.
    """
    cells = []
    for no, name, keys in STAGES:
        states = [agent_status(summary.get(k)) for k in keys]
        live = [s for s in states if s != "idle"]
        working = any(s == "working" for s in states)

        if working:
            label, color, css = "רץ", "#35d6ff", "run"
        elif live:
            label, color, css = "מוכן", "#22e08a", ""
        else:
            label, color, css = "ממתין", "#5b6b7d", ""

        pct = (len(live) / len(keys) * 100) if keys else 0
        names = " · ".join(AGENT_BY_KEY[k][2] for k in keys if k in AGENT_BY_KEY)

        cells.append(f"""
        <div class="stage {css}">
          <div class="top">
            <span class="no">{esc(no)}</span>
            <span class="nm">{esc(name)}</span>
            <span class="st" style="color:{color};background:{color}1f;">{esc(label)}</span>
          </div>
          <div class="bar"><i style="width:{pct:.0f}%;background:{color};"></i></div>
          <div class="agents">{esc(names)}</div>
        </div>""")

    return f'<div class="panel pipe">{"".join(cells)}</div>'


# ---------------------------------------------------------------------------
# 4. ליבת הנחיל — ה-SVG המונפש
# ---------------------------------------------------------------------------

# שמונה סוכנים בחזית, במשבצות קבועות — כך העין לומדת איפה כל אחד יושב
# ולא צריך לחפש אותו מחדש בכל רענון.
FEATURED = ["Scanner", "Model", "Decision", "RiskManager",
            "Execution", "News", "Regime", "Analyzer"]

# מרכזי הכרטיסים סביב הליבה (viewBox 1000x524, ליבה ב-500,262)
SLOTS: List[Tuple[float, float]] = [
    (168, 96), (500, 58), (832, 96),
    (112, 262), (888, 262),
    (168, 428), (500, 466), (832, 428),
]

CARD_W, CARD_H = 182.0, 60.0
CORE_R = 86.0


def _swarm(summary: Dict[str, Dict[str, Any]], feed: List[Dict[str, Any]],
           engine_live: bool, open_n: int) -> str:
    """
    ליבת הנחיל: ליבה מרכזית + שמונה כרטיסי סוכן, מחוברים בקווים חיים.
    קו מהבהב = הסוכן דיווח ממש עכשיו. עוצמת הזוהר = טריות הדיווח.
    """
    cx, cy = 500.0, 262.0

    # היסטוגרמת פעילות אמיתית לכל סוכן, מתוך הפיד
    per_agent_ts: Dict[str, List[Any]] = {}
    for row in feed:
        per_agent_ts.setdefault(str(row.get("agent") or ""), []).append(row.get("timestamp"))

    links, cards, glows = [], [], []

    for slot_i, key in enumerate(FEATURED):
        if slot_i >= len(SLOTS) or key not in AGENT_BY_KEY:
            continue
        _, icon, label, color, role = AGENT_BY_KEY[key]
        sx, sy = SLOTS[slot_i]
        row = summary.get(key)
        state = agent_status(row)
        live = state != "idle"
        working = state == "working"
        scolor = STATUS_COLORS[state]

        # --- הקו לליבה: מקצה הכרטיס עד קצה הליבה ---
        dx, dy = cx - sx, cy - sy
        dist = math.hypot(dx, dy) or 1.0
        ux, uy = dx / dist, dy / dist
        # נקודת יציאה על גבול הכרטיס (מלבן), לא מהמרכז
        tx = CARD_W / 2 / abs(ux) if abs(ux) > 1e-6 else 1e9
        ty = CARD_H / 2 / abs(uy) if abs(uy) > 1e-6 else 1e9
        edge = min(tx, ty)
        x1, y1 = sx + ux * edge, sy + uy * edge
        x2, y2 = cx - ux * CORE_R, cy - uy * CORE_R

        base_op = 0.5 if live else 0.13
        links.append(
            f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{color}" stroke-width="{1.6 if live else 1.0}" '
            f'opacity="{base_op}" stroke-linecap="round"'
            f'{" class=&quot;lnk&quot;" if working else ""}/>'.replace("&quot;", '"')
        )
        if working:
            glows.append(
                f'<circle cx="{x2:.1f}" cy="{y2:.1f}" r="3.2" fill="{color}">'
                f'<animate attributeName="opacity" values="1;.15;1" dur="1.1s" repeatCount="indefinite"/>'
                f'</circle>'
            )

        # --- הכרטיס עצמו ---
        rx, ry = sx - CARD_W / 2, sy - CARD_H / 2
        bars = mini_bars(bucket_counts(per_agent_ts.get(key, []), buckets=15), 112.0, 15.0, color)
        detail = str(row.get("detail") or row.get("action") or "") if row else ""
        if len(detail) > 26:
            detail = detail[:25] + "…"
        act = action_he(row.get("action")) if row else "—"

        cards.append(f"""
        <g opacity="{1.0 if live else 0.44}">
          <rect x="{rx:.1f}" y="{ry:.1f}" width="{CARD_W}" height="{CARD_H}" rx="9"
                fill="rgba(10,16,24,.94)" stroke="{color}" stroke-opacity="{0.55 if live else 0.2}"/>
          <rect x="{rx + CARD_W - 3:.1f}" y="{ry:.1f}" width="3" height="{CARD_H}"
                rx="1.5" fill="{color}" opacity=".9"/>
          <text x="{rx + CARD_W - 11:.1f}" y="{ry + 18:.1f}" text-anchor="start" direction="rtl"
                font-size="11.5" fill="#e8f2f8" font-family="Heebo,sans-serif"
                font-weight="800">{esc(icon)} {esc(label)}</text>
          <circle cx="{rx + 12:.1f}" cy="{ry + 14:.1f}" r="3.4" fill="{scolor}"/>
          <text x="{rx + CARD_W - 11:.1f}" y="{ry + 33:.1f}" text-anchor="start" direction="rtl"
                font-size="8.5" fill="#7f93a6" font-family="JetBrains Mono,monospace"
                font-weight="700">{esc(act)} · {esc(STATUS_HE[state])}</text>
          <g transform="translate({rx + 11:.1f},{ry + 40:.1f})">{bars}</g>
        </g>""")

    # --- הליבה: יצור לבן פועם, כמו ברפרנס ---
    core_state_color = "#22e08a" if engine_live else "#ff4d6a"
    core_text = "פעילה" if engine_live else "מושבתת"
    ticks = "".join(
        f'<line x1="{cx + 196 * math.cos(math.radians(a)):.1f}" '
        f'y1="{cy + 196 * math.sin(math.radians(a)):.1f}" '
        f'x2="{cx + 205 * math.cos(math.radians(a)):.1f}" '
        f'y2="{cy + 205 * math.sin(math.radians(a)):.1f}" '
        f'stroke="rgba(96,140,175,.45)" stroke-width="1.4"/>'
        for a in range(0, 360, 15)
    )

    return f"""
    <div class="panel corewrap">
      <svg viewBox="0 0 1000 524" role="img" aria-label="ליבת הנחיל">
        <defs>
          <radialGradient id="coreGrad" cx="50%" cy="42%">
            <stop offset="0%" stop-color="#ffffff"/>
            <stop offset="72%" stop-color="#e8f4ff"/>
            <stop offset="100%" stop-color="#a9c6dd"/>
          </radialGradient>
          <radialGradient id="auraGrad" cx="50%" cy="50%">
            <stop offset="0%" stop-color="{core_state_color}" stop-opacity=".30"/>
            <stop offset="100%" stop-color="{core_state_color}" stop-opacity="0"/>
          </radialGradient>
        </defs>

        <circle cx="{cx}" cy="{cy}" r="230" fill="url(#auraGrad)" class="corepulse"/>
        <g class="spin">
          <circle cx="{cx}" cy="{cy}" r="196" fill="none"
                  stroke="rgba(96,140,175,.22)" stroke-width="1" stroke-dasharray="2 10"/>
          {ticks}
        </g>
        <circle cx="{cx}" cy="{cy}" r="150" fill="none"
                stroke="rgba(96,140,175,.14)" stroke-width="1"/>

        {"".join(links)}
        {"".join(glows)}

        <circle cx="{cx}" cy="{cy}" r="26" fill="none" stroke="{core_state_color}"
                stroke-width="1.4" class="halo" opacity=".7"/>
        <ellipse cx="{cx}" cy="{cy}" rx="{CORE_R - 6}" ry="{CORE_R - 12}" fill="url(#coreGrad)"/>
        <g class="eye">
          <ellipse cx="{cx - 24}" cy="{cy - 6}" rx="8" ry="11" fill="#0a1018"/>
          <ellipse cx="{cx + 24}" cy="{cy - 6}" rx="8" ry="11" fill="#0a1018"/>
        </g>
        <text x="{cx}" y="{cy + 44}" text-anchor="middle" font-size="10"
              fill="#0a1018" font-family="JetBrains Mono,monospace" font-weight="800"
              letter-spacing="1.4">CORE</text>

        <text x="{cx}" y="{cy + 116}" text-anchor="middle" font-size="14" fill="#e8f2f8"
              font-family="Heebo,sans-serif" font-weight="900">ליבת הנחיל</text>
        <text x="{cx}" y="{cy + 134}" text-anchor="middle" font-size="10"
              fill="{core_state_color}" font-family="JetBrains Mono,monospace"
              font-weight="700" letter-spacing=".8">{esc(core_text)} · {open_n} פוזיציות</text>

        {"".join(cards)}
      </svg>
    </div>
    """


# ---------------------------------------------------------------------------
# 5. יומן פעילות — זרם ממוזג של דיווחי סוכנים + עסקאות שנסגרו
# ---------------------------------------------------------------------------

def _merge_stream(feed: List[Dict[str, Any]], trade_history: List[Dict[str, Any]],
                  limit: int = 44) -> List[Dict[str, Any]]:
    """
    ממזג שני מקורות לזרם אחד ממוין:
      * דיווחי סוכנים  (agent_activity)
      * עסקאות שנסגרו (trades) — אלה מביאות את ה-±$ האמיתי
    """
    events: List[Dict[str, Any]] = []

    for row in feed:
        events.append({
            "ts": row.get("timestamp"),
            "agent": str(row.get("agent") or "System"),
            "action": row.get("action"),
            "text": row.get("detail") or "",
            "symbol": row.get("symbol"),
            "amount": None,
            "severity": str(row.get("severity") or "INFO").upper(),
            "kind": "activity",
        })

    for tr in trade_history:
        if str(tr.get("status") or "") != "closed" or tr.get("closed_at") is None:
            continue
        pnl = _f(tr.get("pnl"))
        pct = _f(tr.get("pnl_pct"))
        reason = str(tr.get("close_reason") or "")
        events.append({
            "ts": tr.get("closed_at"),
            "agent": "Execution",
            "action": "settle",
            "text": f"{reason} · {pct * 100:+.2f}%" if reason else f"{pct * 100:+.2f}%",
            "symbol": tr.get("symbol"),
            "amount": pnl,
            "severity": "INFO",
            "kind": "settle",
        })

    def sort_key(e: Dict[str, Any]) -> float:
        dt = _parse_ts(e.get("ts"))
        return dt.timestamp() if dt else 0.0

    events.sort(key=sort_key, reverse=True)
    return events[:limit]


def _activity_log(feed: List[Dict[str, Any]], trade_history: List[Dict[str, Any]],
                  resolved_24h: int) -> str:
    """יומן חי — כל שורה בצבע הסוכן שלה, עם הסכום האמיתי כשיש."""
    stream = _merge_stream(feed, trade_history)

    if not stream:
        body = ('<div class="empty">אין עדיין פעילות רשומה.<br>'
                'הפעילי את המנוע עם <span class="num">python main.py</span> '
                'והיומן יתמלא בזמן אמת.</div>')
    else:
        rows = []
        for e in stream:
            key = e["agent"]
            meta = AGENT_BY_KEY.get(key)
            color = meta[3] if meta else "#7f93a6"
            label = meta[2] if meta else key

            cls = "row"
            if e["kind"] == "settle":
                cls += " settle" + ("" if _f(e["amount"]) >= 0 else " loss")
            if e["severity"] in ("CRITICAL", "ERROR"):
                cls += " crit"

            if e["amount"] is None:
                amt = f'<span class="amt" style="color:#54677a;">—</span>'
            else:
                amt_cls = "pos" if _f(e["amount"]) >= 0 else "neg"
                amt = f'<span class="amt {amt_cls}">{esc(fmt_signed(e["amount"]))}</span>'

            sym = f'<span class="num" style="color:{color};">{esc(e["symbol"])}</span> ' if e["symbol"] else ""
            text = esc(e["text"])[:96]

            rows.append(
                f'<div class="{cls}">'
                f'<span class="led" style="background:{color};"></span>'
                f'<span class="ag" style="color:{color};">{esc(label)}</span>'
                f'<span class="act">{esc(action_he(e["action"]))}</span>'
                f'<span class="txt">{sym}{text}</span>'
                f'{amt}'
                f'<span class="tm">{esc(time_ago_he(e["ts"]))}</span>'
                f'</div>'
            )
        body = "".join(rows)

    return f"""
    <div class="panel log">
      <div class="loghead">
        <div>
          <div class="cap">יומן פעילות · כל צעד של כל סוכן</div>
          <div style="font-size:12px;font-weight:800;margin-top:2px;">זרם חי</div>
        </div>
        <div style="text-align:start;">
          <div class="cap">נסגרו 24 שעות</div>
          <div class="num" style="font-size:15px;font-weight:800;">{resolved_24h:,}</div>
        </div>
      </div>
      <div class="logbody">{body}</div>
    </div>
    """


# ---------------------------------------------------------------------------
# 6. מסילת הסוכנים — כל 17, ממוספרים
# ---------------------------------------------------------------------------

def _rail(summary: Dict[str, Dict[str, Any]], feed: List[Dict[str, Any]]) -> str:
    """כרטיס לכל סוכן במערכת, כולל אלה שלא בחזית של ליבת הנחיל."""
    per_agent_ts: Dict[str, List[Any]] = {}
    for row in feed:
        per_agent_ts.setdefault(str(row.get("agent") or ""), []).append(row.get("timestamp"))

    cards = []
    for idx, (key, icon, label, color, role) in enumerate(AGENTS, start=1):
        row = summary.get(key)
        state = agent_status(row)
        live = state != "idle"
        scolor = STATUS_COLORS[state]

        detail = str(row.get("detail") or "") if row else ""
        sub = detail if detail else (STATUS_HE[state] + " · " + role)
        if len(sub) > 30:
            sub = sub[:29] + "…"

        bars = mini_bars(bucket_counts(per_agent_ts.get(key, []), buckets=16), 116.0, 15.0, color)
        led_cls = "led on" if state == "working" else "led"

        cards.append(f"""
        <div class="acard{'' if live else ' dead'}" style="border-color:{color}33;">
          <div class="hd">
            <span class="ix">{idx:02d}</span>
            <span class="ic">{esc(icon)}</span>
            <span class="nm" style="color:{color};">{esc(label)}</span>
            <span class="{led_cls}" style="background:{scolor};color:{scolor}66;"></span>
          </div>
          <div class="sub" dir="auto" title="{esc(detail)}">{esc(sub)}</div>
          <svg class="mb" viewBox="0 0 116 15" preserveAspectRatio="none">{bars}</svg>
        </div>""")

    return f'<div class="rail">{"".join(cards)}</div>'


# ---------------------------------------------------------------------------
# 7. קונצנזוס ועדת ההחלטה
# ---------------------------------------------------------------------------

def _consensus(decisions: List[Dict[str, Any]]) -> str:
    """ממוצע ההסכמה בהחלטות האחרונות + כמה אושרו מול נדחו."""
    if not decisions:
        return f"""
        <div class="panel cons">
          <div class="cap">קונצנזוס הנחיל</div>
          <div class="track"><div class="fill" style="width:0%;"></div></div>
          <div class="val" style="color:#54677a;">—</div>
          <div style="font-size:11px;color:#54677a;">אין עדיין החלטות רשומות</div>
        </div>"""

    vals = [_f(d.get("consensus")) for d in decisions]
    avg = sum(vals) / len(vals) if vals else 0.0
    # ההסכמה נשמרת לעיתים כ-0..1 ולעיתים כ-0..100 — מנרמלים לאחוזים
    pct = clamp(avg * 100 if avg <= 1.0 else avg, 0.0, 100.0)
    approved = sum(1 for d in decisions if _i(d.get("approved")) == 1)
    rejected = len(decisions) - approved
    avg_mult = sum(_f(d.get("size_multiplier"), 1.0) for d in decisions) / len(decisions)

    color = "#22e08a" if pct >= 65 else ("#ffb020" if pct >= 45 else "#ff4d6a")

    return f"""
    <div class="panel cons">
      <div class="cap">קונצנזוס הנחיל</div>
      <div class="track"><div class="fill" style="width:{pct:.1f}%;"></div></div>
      <div class="val" style="color:{color};">{pct:.1f}%</div>
      <div style="font-size:11px;color:#7f93a6;">
        מתוך {num(len(decisions))} החלטות אחרונות ·
        אושרו <span class="num pos">{approved}</span> ·
        נדחו <span class="num neg">{rejected}</span> ·
        מכפיל גודל ממוצע <span class="num acc">×{avg_mult:.2f}</span>
      </div>
    </div>"""


# ---------------------------------------------------------------------------
# 8. גרף ההון
# ---------------------------------------------------------------------------

def _equity(snapshots: List[Dict[str, Any]], trade_history: List[Dict[str, Any]]) -> str:
    """עקומת הון (שטח) מעל עמודות רווח/הפסד לכל עסקה שנסגרה."""
    eq = [_f(s.get("equity")) for s in snapshots if s.get("equity") is not None]

    if len(eq) < 2:
        return f"""
        <div class="panel eq">
          <div class="eqhead"><div class="cap">היסטוריית הון</div></div>
          <div class="empty">צריך לפחות שני snapshots כדי לצייר עקומה.</div>
        </div>"""

    W, H = 1000.0, 150.0
    line, area = spark_path(eq, W, H, pad=8.0)

    first, last = eq[0], eq[-1]
    delta = last - first
    delta_pct = (delta / first * 100) if first else 0.0
    up = delta >= 0
    color = "#22e08a" if up else "#ff4d6a"
    lo, hi = min(eq), max(eq)

    # עמודות הרווח לפי עסקאות שנסגרו, מהישנה לחדשה
    closed = [t for t in trade_history if str(t.get("status") or "") == "closed"
              and t.get("pnl") is not None]
    closed = list(reversed(closed))[-90:]
    bars = bar_series([_f(t.get("pnl")) for t in closed], W, 46.0)

    grid = "".join(
        f'<line x1="0" y1="{H * i / 4:.1f}" x2="{W}" y2="{H * i / 4:.1f}" '
        f'stroke="rgba(96,140,175,.10)" stroke-width="1"/>' for i in range(5)
    )

    return f"""
    <div class="panel eq">
      <div class="eqhead">
        <div>
          <div class="cap">היסטוריית הון · {len(eq)} נקודות</div>
          <div style="font-size:19px;font-weight:800;" class="num">{esc(fmt_usd(last))}</div>
        </div>
        <div style="text-align:start;">
          <div class="cap">שינוי בטווח</div>
          <div class="num" style="font-size:15px;font-weight:800;color:{color};">
            {esc(fmt_signed(delta))} ({delta_pct:+.2f}%)
          </div>
        </div>
        <div style="text-align:start;">
          <div class="cap">מינימום / מקסימום</div>
          <div class="num" style="font-size:12px;color:#7f93a6;">
            {esc(fmt_usd(lo))} … {esc(fmt_usd(hi))}
          </div>
        </div>
      </div>

      <svg viewBox="0 0 {W:.0f} {H:.0f}" preserveAspectRatio="none" style="height:150px;">
        <defs><linearGradient id="eqFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="{color}" stop-opacity=".34"/>
          <stop offset="100%" stop-color="{color}" stop-opacity="0"/>
        </linearGradient></defs>
        {grid}
        <path d="{area}" fill="url(#eqFill)"/>
        <path d="{line}" fill="none" stroke="{color}" stroke-width="2"
              stroke-linejoin="round" stroke-linecap="round"/>
      </svg>

      <div class="cap" style="margin-top:6px;">רווח והפסד לכל עסקה · {len(closed)} אחרונות</div>
      <svg viewBox="0 0 {W:.0f} 46" preserveAspectRatio="none" style="height:46px;">
        <line x1="0" y1="23" x2="{W}" y2="23" stroke="rgba(96,140,175,.18)" stroke-width="1"/>
        {bars}
      </svg>
    </div>"""


# ---------------------------------------------------------------------------
# הרכבה — העמוד השלם
# ---------------------------------------------------------------------------

def render_trading_floor(
    *,
    config: Any,
    snapshots: Optional[List[Dict[str, Any]]] = None,
    open_trades: Optional[List[Dict[str, Any]]] = None,
    trade_history: Optional[List[Dict[str, Any]]] = None,
    agent_summary: Optional[Dict[str, Dict[str, Any]]] = None,
    agent_feed: Optional[List[Dict[str, Any]]] = None,
    recent_decisions: Optional[List[Dict[str, Any]]] = None,
    stats: Optional[Dict[str, Any]] = None,
    stats24: Optional[Dict[str, Any]] = None,
    session_start: Any = None,
    universe: int = 0,
) -> Tuple[str, int]:
    """
    בונה את רצפת המסחר כעמוד HTML אחד ומחזיר (html, גובה מומלץ בפיקסלים).

    כל הפרמטרים אופציונליים — אם משהו חסר, המקטע המתאים מציג "ממתין"
    במקום להישבר. זה חשוב: הדשבורד עולה גם כשהמנוע כבוי.
    """
    snapshots = snapshots or []
    open_trades = open_trades or []
    trade_history = trade_history or []
    agent_summary = agent_summary or {}
    agent_feed = agent_feed or []
    recent_decisions = recent_decisions or []
    stats = stats or {}
    stats24 = stats24 or {}

    # --- מצב המנוע ---
    engine_live = any(
        agent_status(r) != "idle" for r in agent_summary.values()
    )
    loop_no = max((_i(r.get("loop_count")) for r in agent_summary.values()), default=0)
    last_beat = max(
        (r.get("timestamp") for r in agent_summary.values() if r.get("timestamp")),
        default=None,
    )
    uptime = _age_sec(session_start) if session_start else None

    # --- מדדים ---
    snap = snapshots[-1] if snapshots else {}
    equity = _f(snap.get("equity"))
    unrealized = _f(snap.get("unrealized_pnl"))
    total_pnl = _f(snap.get("total_pnl"))
    total_pnl_pct = _f(snap.get("total_pnl_pct"))
    # total_pnl_pct נשמר לעיתים כשבר ולעיתים כאחוז — מנרמלים לשבר
    if abs(total_pnl_pct) > 1.5:
        total_pnl_pct /= 100.0

    equity_series = [_f(s.get("equity")) for s in snapshots][-60:]
    pnl_series = [_f(s.get("total_pnl")) for s in snapshots][-60:]

    trades24 = _i(stats24.get("total_trades"))
    pnl24 = _f(stats24.get("total_pnl"))
    win_rate = _f(stats24.get("win_rate")) or _f(stats.get("win_rate"))
    gross_profit = _f(stats24.get("gross_profit"))
    gross_loss = abs(_f(stats24.get("gross_loss")))
    if gross_loss > 0:
        profit_factor = gross_profit / gross_loss
    else:
        profit_factor = 2.0 if gross_profit > 0 else 0.0

    sharpe = _f(stats.get("sharpe_ratio"))
    max_dd = clamp(_f(stats.get("max_drawdown")), 0.0, 1.0)

    max_pos = _i(getattr(config, "hft_max_open_positions", 0), 0)

    parts = [
        FLOOR_CSS,
        '<div class="floor" dir="rtl">',
        _ticker(config, engine_live, loop_no, uptime, last_beat,
                universe, len(open_trades), max_pos),
        _kpis(equity, equity_series, total_pnl, total_pnl_pct, pnl24, win_rate,
              trades24, profit_factor, unrealized, pnl_series, sharpe, max_dd),
        _pipeline(agent_summary),
        '<div class="mid">',
        _swarm(agent_summary, agent_feed, engine_live, len(open_trades)),
        _activity_log(agent_feed, trade_history, trades24),
        '</div>',
        _rail(agent_summary, agent_feed),
        _consensus(recent_decisions),
        _equity(snapshots, trade_history),
        '</div>',
    ]

    # גובה ה-iframe. Streamlit לא יודע למדוד תוכן בתוך רכיב HTML, לכן
    # מחשבים אותו כאן מהגבהים הקבועים ב-CSS. המספרים כוילו מול מדידה
    # אמיתית בדפדפן ברוחבים 900-1700px (סטייה של פחות מ-30px).
    #   קבוע 801 = ריפוד הדף + טיקר + KPI + צינור + ליבה/יומן + קונצנזוס
    #               כולל המרווח של 11px בין המקטעים.
    rail_rows = math.ceil(len(AGENTS) / 7)       # התרחיש הצפוף ביותר
    rail_h = rail_rows * 62 + (rail_rows - 1) * 7
    equity_h = 282 if len([s for s in snapshots if s.get("equity") is not None]) >= 2 else 112
    height = 801 + rail_h + equity_h

    return "\n".join(parts), int(height)


def render_floor_component(**kwargs: Any) -> None:
    """מציג את רצפת המסחר בתוך Streamlit. בטוח לקריאה גם בלי Streamlit."""
    html_str, height = render_trading_floor(**kwargs)
    try:
        import streamlit.components.v1 as components
        components.html(html_str, height=height, scrolling=True)
    except Exception:  # pragma: no cover — נפילה חיננית אם הרכיב לא זמין
        try:
            import streamlit as st
            st.markdown(html_str, unsafe_allow_html=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# תצוגה מקדימה — לבדיקה ויזואלית בלי להריץ את כל המערכת
#     python dashboard_floor.py [out.html]
# קורא מ-trading.db אם קיים; אחרת בונה נתוני הדגמה מסומנים ככאלה.
# ---------------------------------------------------------------------------

def _preview_data() -> Dict[str, Any]:
    """טוען נתונים אמיתיים מה-DB אם יש, אחרת מייצר סט הדגמה."""
    import os
    import random

    class _Cfg:
        paper_trading = True
        aggressive_hft = True
        hft_max_open_positions = 4

    db = os.environ.get("DB_PATH", "trading.db")
    if os.path.exists(db):
        try:
            from database.repository import TradeRepository
            repo = TradeRepository(db_path=db)
            return {
                "config": _Cfg(),
                "snapshots": repo.get_portfolio_snapshots(limit=200),
                "open_trades": repo.get_open_trades(),
                "trade_history": repo.get_trade_history(limit=200),
                "agent_summary": {r["agent"]: r for r in repo.get_agent_status_summary()},
                "agent_feed": repo.get_recent_agent_activity(limit=200),
                "recent_decisions": repo.get_recent_decisions(limit=40),
                "stats": repo.get_performance_stats(),
                "stats24": repo.get_overall_recent_stats(hours_back=24),
                "universe": 0,
            }
        except Exception as exc:
            print(f"[preview] לא הצלחתי לקרוא מ-{db}: {exc} — עובר לנתוני הדגמה")

    # --- נתוני הדגמה (רק לתצוגה מקדימה מקומית) ---
    rnd = random.Random(7)
    now = datetime.now(timezone.utc)

    def iso(sec_ago: float) -> str:
        return (now - __import__("datetime").timedelta(seconds=sec_ago)).isoformat()

    equity, snaps = 1000.0, []
    for i in range(120):
        equity *= 1 + rnd.gauss(0.0016, 0.006)
        snaps.append({
            "equity": equity, "balance": equity,
            "total_pnl": equity - 1000.0,
            "total_pnl_pct": (equity - 1000.0) / 1000.0,
            "unrealized_pnl": rnd.uniform(-8, 14),
            "open_positions": rnd.randint(0, 3),
            "win_rate": 0.58,
            "timestamp": iso((120 - i) * 90),
        })

    syms = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "ARBUSDT", "SUIUSDT", "TONUSDT", "AVAXUSDT"]
    hist = []
    for i in range(70):
        pnl = rnd.gauss(1.4, 6.0)
        hist.append({
            "symbol": rnd.choice(syms), "side": rnd.choice(["LONG", "SHORT"]),
            "status": "closed", "pnl": pnl, "pnl_pct": pnl / 100.0,
            "close_reason": rnd.choice(["take_profit", "stop_loss", "stale_exit", "trail"]),
            "closed_at": iso(i * 420), "opened_at": iso(i * 420 + 300),
            "entry_price": 100.0, "quantity": 1.0,
        })

    summary, feed = {}, []
    actions = ["scan", "rank", "score", "evaluate", "state", "sentiment",
               "allocate", "learn", "guard", "radar"]
    for i, (key, _ic, _lb, _c, _r) in enumerate(AGENTS):
        age = rnd.uniform(1, 40) if i % 5 != 4 else rnd.uniform(400, 900)
        summary[key] = {
            "agent": key, "action": rnd.choice(actions),
            "detail": rnd.choice([
                "נסרקו 312 סימבולים, 4 מועמדים", "משטר: מגמתי · תנודתיות בינונית",
                "ציון 0.81 מעל הסף", "מרג׳ין 18% מהתיק", "אין חסימות פעילות",
                "עודכן מודל — דיוק 63%", "Fear&Greed 54 · funding שלילי",
            ]),
            "symbol": rnd.choice(syms + [None]),
            "status": rnd.choice(["active", "working", "active"]),
            "severity": "INFO", "loop_count": 1847,
            "timestamp": iso(age),
        }
        for _ in range(rnd.randint(3, 12)):
            feed.append({
                "agent": key, "action": rnd.choice(actions),
                "detail": rnd.choice(["מועמד חדש נכנס לדירוג", "סף ציון עודכן",
                                      "בדיקת סיכון עברה", "נדחה: נזילות נמוכה"]),
                "symbol": rnd.choice(syms), "status": "active",
                "severity": "INFO", "loop_count": 1847,
                "timestamp": iso(rnd.uniform(1, 880)),
            })

    decisions = [{
        "symbol": rnd.choice(syms), "direction": rnd.choice(["LONG", "SHORT"]),
        "approved": rnd.choice([1, 1, 0]), "original_score": rnd.uniform(.6, .95),
        "adjusted_score": rnd.uniform(.6, .95), "consensus": rnd.uniform(.55, .92),
        "size_multiplier": rnd.uniform(.7, 1.6), "created_at": iso(i * 200),
    } for i in range(30)]

    wins = sum(1 for t in hist if t["pnl"] > 0)
    gp = sum(t["pnl"] for t in hist if t["pnl"] > 0)
    gl = sum(t["pnl"] for t in hist if t["pnl"] <= 0)

    return {
        "config": _Cfg(), "snapshots": snaps, "open_trades": hist[:3],
        "trade_history": hist, "agent_summary": summary, "agent_feed": feed,
        "recent_decisions": decisions,
        "stats": {"win_rate": wins / len(hist), "sharpe_ratio": 1.84,
                  "max_drawdown": 0.071, "total_trades": len(hist)},
        "stats24": {"total_trades": 28, "win_rate": 0.607,
                    "total_pnl": sum(t["pnl"] for t in hist[:28]),
                    "gross_profit": gp, "gross_loss": gl},
        "session_start": iso(18_400), "universe": 312,
    }


if __name__ == "__main__":
    import sys

    out = sys.argv[1] if len(sys.argv) > 1 else "floor_preview.html"
    body, h = render_trading_floor(**_preview_data())
    page = (
        '<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>רצפת המסחר</title>'
        '<style>html,body{margin:0;background:#04060a;}</style></head><body>'
        + body + '</body></html>'
    )
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(page)
    print(f"נכתב: {out}  ({len(page):,} bytes, גובה מומלץ {h}px)")

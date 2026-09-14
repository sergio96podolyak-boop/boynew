"""
הפנקס — ארבעת המקטעים שרצפת המסחר לא מכסה, באותה שפה עיצובית.

למה המודול הזה קיים: הדשבורד הציג את הרצפה בראש ואת שאר המידע מתחת
ברכיבי Streamlit סטנדרטיים. זה נראה כמו שתי אפליקציות שהודבקו יחד.
כאן נבנים מחדש רק הדברים שבאמת חסרים, בעיצוב אחד:

    1. פוזיציות פתוחות  — מה פתוח עכשיו, עם SL/TP והרווח הנוכחי
    2. בריאות המודל     — כמה מודלים עברו את סף היתרון, ומה היתרון לכל סימבול
    3. היסטוריית עסקאות — מה נסגר ולמה
    4. יומן מערכת       — שגיאות, kill-switch, אירועי הפעלה

כל השאר (מרכז אסטרטגיות, מחסנית אוטומציה, רדאר, קטליזטורים, סנטימנט,
TradingView, ניתוח שוק, איתותים אחרונים) הוסר: או שהוא תצוגת הגדרות
שמקומה בסיידבר, או שהסוכנים ברצפה ופאנל השוק כבר מציגים אותו.

שימוש:
    from dashboard_ledger import render_ledger_component
    render_ledger_component(open_trades=..., trade_history=..., ...)
"""

from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional, Tuple

from dashboard_floor import (
    _f,
    _i,
    esc,
    fmt_pct,
    fmt_signed,
    fmt_usd,
    time_ago_he,
)

HISTORY_ROWS = 14
EVENT_ROWS = 12

# סף היתרון שמעליו מודל נחשב בעל ערך — חייב להתאים ל-EDGE_FLOOR
# ב-agents/model.py. אם משנים שם, לשנות גם כאן.
EDGE_FLOOR = 0.03

CLOSE_REASON_HE = {
    "take_profit": "לקיחת רווח",
    "stop_loss": "סטופ",
    "stale_exit": "יציאת שהייה",
    "trail": "עצירה נגררת",
    "trailing_stop": "עצירה נגררת",
    "manual": "ידני",
    "kill_switch": "מתג חירום",
    "drawdown_kill": "עצירת הפסד",
    "rotation": "רוטציית הון",
    "paper_session_reset": "איפוס סשן",
}

SEVERITY_COLOR = {
    "CRITICAL": "#ff4d6a",
    "ERROR": "#ff4d6a",
    "WARNING": "#ffb020",
    "INFO": "#35d6ff",
    "DEBUG": "#54677a",
}


def _read_json(path: str) -> Dict[str, Any]:
    """קריאת JSON סלחנית — קובץ חסר או פגום מחזיר dict ריק."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def he_reason(reason: Any) -> str:
    key = str(reason or "").lower()
    return CLOSE_REASON_HE.get(key, key or "—")


def he_side(side: Any) -> str:
    return {"LONG": "לונג", "SHORT": "שורט"}.get(str(side or "").upper(), side or "—")


LEDGER_CSS = """
<style>
@import url('https://fonts.googleapis.com/css2?family=Heebo:wght@400;500;700;800;900\
&family=JetBrains+Mono:wght@400;500;700;800&display=swap');

:root{
  --bg:#04060a; --panel:rgba(11,17,25,.82); --line:rgba(96,140,175,.14);
  --text:#e8f2f8; --muted:#7f93a6; --dim:#54677a;
  --green:#22e08a; --red:#ff4d6a; --cyan:#35d6ff; --amber:#ffb020;
  --mono:'JetBrains Mono',ui-monospace,'SF Mono',Menlo,monospace;
  --sans:'Heebo',ui-sans-serif,system-ui,'Segoe UI',sans-serif;
}
*{box-sizing:border-box;}
html,body{margin:0;padding:0;background:var(--bg);}

.lg{font-family:var(--sans);color:var(--text);display:flex;flex-direction:column;gap:10px;}
.num{font-family:var(--mono);font-variant-numeric:tabular-nums;
  direction:ltr;unicode-bidi:isolate;letter-spacing:-.2px;}
.pos{color:var(--green);} .neg{color:var(--red);} .acc{color:var(--cyan);}
.cap{font-size:9.5px;font-weight:800;letter-spacing:1.5px;color:var(--dim);
  text-transform:uppercase;font-family:var(--mono);}

.card{background:var(--panel);border:1px solid var(--line);border-radius:11px;
  overflow:hidden;display:flex;flex-direction:column;min-width:0;}
.card > .hd{padding:9px 12px;border-bottom:1px solid var(--line);
  display:flex;align-items:baseline;justify-content:space-between;gap:10px;}
.card > .hd .t{font-size:13px;font-weight:800;}

.two{display:grid;grid-template-columns:1fr 1fr;gap:10px;align-items:stretch;}
@media(max-width:820px){.two{grid-template-columns:1fr;}}

/* ---------- טבלאות ---------- */
table{width:100%;border-collapse:collapse;font-size:11px;}
th{font-family:var(--mono);font-size:8.5px;font-weight:800;letter-spacing:1px;
  color:var(--dim);text-transform:uppercase;text-align:start;
  padding:6px 10px;border-bottom:1px solid var(--line);white-space:nowrap;}
td{padding:6px 10px;border-bottom:1px solid rgba(96,140,175,.06);white-space:nowrap;}
tbody tr:hover{background:rgba(53,214,255,.045);}
td.n{font-family:var(--mono);font-variant-numeric:tabular-nums;
  direction:ltr;unicode-bidi:isolate;}
.sym{font-family:var(--mono);font-weight:800;font-size:11px;}
.tag{font-family:var(--mono);font-size:8.5px;font-weight:800;letter-spacing:.6px;
  padding:1px 6px;border-radius:4px;white-space:nowrap;}
.tag.long{color:var(--green);background:rgba(34,224,138,.12);}
.tag.short{color:var(--red);background:rgba(255,77,106,.12);}

.empty{padding:22px 14px;text-align:center;color:var(--dim);font-size:12px;line-height:1.7;}

/* ---------- מד SL/TP: איפה המחיר יושב בין הסטופ ליעד ---------- */
.rng{position:relative;height:5px;border-radius:5px;min-width:96px;
  background:linear-gradient(90deg,rgba(255,77,106,.35),rgba(96,140,175,.18),rgba(34,224,138,.35));}
.rng i{position:absolute;top:-2px;width:2px;height:9px;background:var(--text);
  border-radius:2px;box-shadow:0 0 6px rgba(232,242,248,.8);}

/* ---------- בריאות המודל ---------- */
.mstats{display:grid;grid-template-columns:repeat(auto-fit,minmax(96px,1fr));
  gap:8px;padding:10px 12px;}
.mstat .k{font-size:9px;letter-spacing:1px;text-transform:uppercase;
  color:var(--dim);font-family:var(--mono);font-weight:700;}
.mstat .v{font-size:19px;font-weight:800;font-family:var(--mono);margin-top:2px;
  letter-spacing:-.5px;}
.edges{padding:2px 12px 10px;}
.erow{display:grid;grid-template-columns:74px 1fr auto;gap:8px;align-items:center;
  padding:2.5px 0;font-size:10px;}
.erow .s{font-family:var(--mono);font-weight:700;overflow:hidden;
  text-overflow:ellipsis;}
.erow .track{height:5px;border-radius:5px;background:rgba(96,140,175,.13);
  position:relative;overflow:hidden;}
.erow .track i{position:absolute;inset-block:0;inset-inline-start:0;border-radius:5px;}
.erow .track .gate{position:absolute;inset-block:-2px;width:1.5px;
  background:rgba(255,176,32,.75);}
.erow .v{font-family:var(--mono);font-weight:800;font-size:10px;
  direction:ltr;unicode-bidi:isolate;}

/* ---------- יומן מערכת ---------- */
.ev{display:grid;grid-template-columns:auto 1fr auto;gap:8px;align-items:baseline;
  padding:5px 12px;border-bottom:1px solid rgba(96,140,175,.06);font-size:11px;}
.ev .dot{width:6px;height:6px;border-radius:50%;align-self:center;}
.ev .m{color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
  unicode-bidi:plaintext;}
.ev .t{font-family:var(--mono);font-size:9px;color:var(--dim);white-space:nowrap;}
.ev.bad{background:rgba(255,77,106,.06);}
.ev.bad .m{color:#ffd2da;}
.scroll{overflow-y:auto;}
.scroll::-webkit-scrollbar{width:5px;}
.scroll::-webkit-scrollbar-thumb{background:rgba(96,140,175,.28);border-radius:4px;}
</style>
"""


# ---------------------------------------------------------------------------
# 1. פוזיציות פתוחות
# ---------------------------------------------------------------------------

def _positions(open_trades: List[Dict[str, Any]], max_positions: int) -> str:
    """מה פתוח עכשיו, עם המרחק בין הסטופ ליעד ומיקום מחיר הכניסה בתוכו."""
    if not open_trades:
        body = ('<div class="empty">אין פוזיציות פתוחות.<br>'
                'הבוט סורק וממתין להזדמנות שתעבור את שער הסיכון.</div>')
    else:
        rows = []
        for tr in open_trades:
            side = str(tr.get("side") or "").upper()
            is_long = side == "LONG"
            entry = _f(tr.get("entry_price"))
            sl = _f(tr.get("sl_price"))
            tp = _f(tr.get("tp_price"))
            qty = _f(tr.get("quantity"))
            notional = entry * qty

            # מיקום הכניסה בין הסטופ ליעד — מראה כמה "מקום" יש לכל צד
            gauge = ""
            lo, hi = (sl, tp) if is_long else (tp, sl)
            if lo and hi and hi != lo:
                pct = max(0.0, min(1.0, (entry - lo) / (hi - lo))) * 100
                gauge = (f'<div class="rng"><i style="inset-inline-start:'
                         f'calc({pct:.1f}% - 1px);"></i></div>')

            side_cls = "long" if is_long else "short"
            entry_s = esc(f"{entry:.6g}")
            sl_s = esc(f"{sl:.6g}") if sl else "—"
            tp_s = esc(f"{tp:.6g}") if tp else "—"
            rows.append(
                "<tr>"
                f'<td><span class="sym">{esc(tr.get("symbol"))}</span></td>'
                f'<td><span class="tag {side_cls}">{esc(he_side(side))}</span></td>'
                f'<td class="n acc">{entry_s}</td>'
                f'<td class="n neg">{sl_s}</td>'
                f'<td class="n pos">{tp_s}</td>'
                f'<td>{gauge}</td>'
                f'<td class="n">{esc(fmt_usd(notional))}</td>'
                f'<td class="n" style="color:#7f93a6;">'
                f'{esc(time_ago_he(tr.get("opened_at")))}</td>'
                f"</tr>"
            )
        body = (
            "<table><thead><tr><th>סימבול</th><th>כיוון</th><th>כניסה</th>"
            "<th>סטופ</th><th>יעד</th><th>מרחב</th><th>נוטיונל</th><th>נפתחה</th>"
            f"</tr></thead><tbody>{''.join(rows)}</tbody></table>"
        )

    return f"""
    <div class="card">
      <div class="hd">
        <span class="t">פוזיציות פתוחות</span>
        <span class="cap">{len(open_trades)} מתוך {max_positions} מותרות</span>
      </div>
      {body}
    </div>"""


# ---------------------------------------------------------------------------
# 2. בריאות המודל
# ---------------------------------------------------------------------------

def _model_health(health: Dict[str, Any]) -> str:
    """
    כמה מודלים באמת מצאו יתרון, וכמה גדול הוא לכל סימבול.

    זה המקטע שקובע אם המנוע שווה משהו. `יתרון` הוא lift מעל שכיחות הבסיס
    על ההכרזות שהיינו סוחרים עליהן — לא דיוק כולל. הקו הכתום בכל פס הוא
    סף היתרון: מתחתיו המודל לא מייצר אות בכלל.
    """
    agg = health.get("aggregate") or {}
    symbols = health.get("symbols") or {}

    trained = _i(agg.get("trained_symbols"))
    healthy = _i(agg.get("healthy_symbols"))
    avg_rel = _f(agg.get("avg_reliability"))

    if not symbols:
        return """
        <div class="card">
          <div class="hd"><span class="t">בריאות המודל</span></div>
          <div class="empty">עדיין לא אומן אף מודל.<br>
          הנתונים יופיעו אחרי סבב הסריקה הראשון.</div>
        </div>"""

    # מיון לפי יתרון — הכי טובים למעלה
    ranked = sorted(
        ((s, _f(v.get("reliability"))) for s, v in symbols.items() if isinstance(v, dict)),
        key=lambda t: -t[1],
    )[:14]
    peak = max((e for _, e in ranked), default=0.0) or EDGE_FLOOR * 2
    scale = max(peak, EDGE_FLOOR * 2)

    bars = []
    for sym, edge in ranked:
        pct = max(0.0, min(1.0, edge / scale)) * 100
        gate = min(99.0, (EDGE_FLOOR / scale) * 100)
        color = "#22e08a" if edge > EDGE_FLOOR else "#54677a"
        bars.append(
            f'<div class="erow">'
            f'<span class="s" style="color:{color};">{esc(sym)}</span>'
            f'<span class="track"><i style="width:{pct:.1f}%;background:{color};"></i>'
            f'<span class="gate" style="inset-inline-start:{gate:.1f}%;"></span></span>'
            f'<span class="v" style="color:{color};">{edge:+.3f}</span>'
            f'</div>'
        )

    ratio = (healthy / trained) if trained else 0.0
    hcolor = "#22e08a" if ratio >= 0.25 else ("#ffb020" if ratio >= 0.08 else "#ff4d6a")

    def stat(k: str, v: str, cls: str = "") -> str:
        return (f'<div class="mstat"><div class="k">{esc(k)}</div>'
                f'<div class="v {cls}" dir="ltr">{esc(v)}</div></div>')

    return f"""
    <div class="card">
      <div class="hd">
        <span class="t">בריאות המודל</span>
        <span class="cap">{esc(str(health.get("model_type") or ""))}</span>
      </div>
      <div class="mstats">
        {stat("מודלים בעלי יתרון", f"{healthy}/{trained}")}
        {stat("יתרון ממוצע", f"{avg_rel:+.3f}", "pos" if avg_rel > EDGE_FLOOR else "")}
        {stat("שיעור בריאים", fmt_pct(ratio))}
      </div>
      <div style="height:3px;background:rgba(96,140,175,.13);margin:0 12px;
                  border-radius:3px;overflow:hidden;">
        <div style="height:100%;width:{ratio * 100:.1f}%;background:{hcolor};"></div>
      </div>
      <div class="edges scroll" style="max-height:196px;">
        <div class="cap" style="margin:8px 0 5px;">יתרון לכל סימבול · הקו הכתום = סף האות</div>
        {"".join(bars)}
      </div>
    </div>"""


# ---------------------------------------------------------------------------
# 3. יומן מערכת
# ---------------------------------------------------------------------------

def _events(events: List[Dict[str, Any]]) -> str:
    """אירועי מערכת — שגיאות ו-kill-switch בולטים באדום."""
    if not events:
        body = '<div class="empty">אין אירועי מערכת רשומים.</div>'
    else:
        rows = []
        for ev in events[:EVENT_ROWS]:
            sev = str(ev.get("severity") or "INFO").upper()
            color = SEVERITY_COLOR.get(sev, "#35d6ff")
            bad = " bad" if sev in ("ERROR", "CRITICAL") else ""
            msg = esc(ev.get("message"))[:120]
            rows.append(
                f'<div class="ev{bad}">'
                f'<span class="dot" style="background:{color};"></span>'
                f'<span class="m" title="{esc(ev.get("message"))}">'
                f'<b style="color:{color};font-family:var(--mono);font-size:9px;">'
                f'{esc(ev.get("event_type"))}</b> {msg}</span>'
                f'<span class="t">{esc(time_ago_he(ev.get("timestamp")))}</span>'
                f'</div>'
            )
        body = f'<div class="scroll" style="max-height:266px;">{"".join(rows)}</div>'

    return f"""
    <div class="card">
      <div class="hd"><span class="t">יומן מערכת</span>
        <span class="cap">{len(events)} אירועים</span></div>
      {body}
    </div>"""


# ---------------------------------------------------------------------------
# 4. היסטוריית עסקאות
# ---------------------------------------------------------------------------

def _history(trade_history: List[Dict[str, Any]]) -> str:
    """מה נסגר, למה, ובכמה."""
    closed = [t for t in trade_history
              if str(t.get("status") or "") == "closed" and t.get("pnl") is not None]

    if not closed:
        body = ('<div class="empty">עדיין לא נסגרה אף עסקה.</div>')
        won = tot = 0
        net = 0.0
    else:
        won = sum(1 for t in closed if _f(t.get("pnl")) > 0)
        tot = len(closed)
        net = sum(_f(t.get("pnl")) for t in closed)
        rows = []
        for tr in closed[:HISTORY_ROWS]:
            pnl = _f(tr.get("pnl"))
            pct = _f(tr.get("pnl_pct")) * 100
            side = str(tr.get("side") or "").upper()
            cls = "pos" if pnl >= 0 else "neg"
            side_cls = "long" if side == "LONG" else "short"
            entry_v = _f(tr.get("entry_price"))
            exit_v = _f(tr.get("exit_price"))
            entry_s = esc(f"{entry_v:.6g}") if entry_v else "—"
            exit_s = esc(f"{exit_v:.6g}") if exit_v else "—"
            rows.append(
                "<tr>"
                f'<td><span class="sym">{esc(tr.get("symbol"))}</span></td>'
                f'<td><span class="tag {side_cls}">{esc(he_side(side))}</span></td>'
                f'<td class="n">{entry_s}</td>'
                f'<td class="n">{exit_s}</td>'
                f'<td class="n {cls}">{esc(fmt_signed(pnl))}</td>'
                f'<td class="n {cls}">{pct:+.2f}%</td>'
                f'<td style="color:#7f93a6;">{esc(he_reason(tr.get("close_reason")))}</td>'
                f'<td class="n" style="color:#54677a;">'
                f'{esc(time_ago_he(tr.get("closed_at")))}</td>'
                "</tr>"
            )
        body = (
            "<table><thead><tr><th>סימבול</th><th>כיוון</th><th>כניסה</th>"
            "<th>יציאה</th><th>רווח</th><th>אחוז</th><th>סיבת סגירה</th><th>נסגרה</th>"
            f"</tr></thead><tbody>{''.join(rows)}</tbody></table>"
        )

    wr = (won / tot) if tot else 0.0
    net_cls = "pos" if net >= 0 else "neg"
    return f"""
    <div class="card">
      <div class="hd">
        <span class="t">היסטוריית עסקאות</span>
        <span class="cap">{tot} סגורות · {esc(fmt_pct(wr))} הצלחה ·
          <span class="num {net_cls}">{esc(fmt_signed(net))}</span> נטו</span>
      </div>
      {body}
    </div>"""


# ---------------------------------------------------------------------------
# הרכבה
# ---------------------------------------------------------------------------

def render_ledger(
    *,
    open_trades: Optional[List[Dict[str, Any]]] = None,
    trade_history: Optional[List[Dict[str, Any]]] = None,
    events: Optional[List[Dict[str, Any]]] = None,
    max_positions: int = 0,
    health_path: str = "data/model_health.json",
) -> Tuple[str, int]:
    """בונה את הפנקס ומחזיר (html, גובה מומלץ)."""
    open_trades = open_trades or []
    trade_history = trade_history or []
    events = events or []
    health = _read_json(health_path) if os.path.exists(health_path) else {}

    html = f"""{LEDGER_CSS}
    <div class="lg" dir="rtl">
      {_positions(open_trades, max_positions)}
      <div class="two">
        {_model_health(health)}
        {_events(events)}
      </div>
      {_history(trade_history)}
    </div>"""

    # גובה: פוזיציות (כותרת + שורות) + השורה הכפולה + היסטוריה.
    # נדיב במעט; scrolling=True הוא רשת הביטחון.
    pos_h = 42 + (len(open_trades) * 27 + 28 if open_trades else 64)
    hist_rows = min(HISTORY_ROWS, sum(
        1 for t in trade_history
        if str(t.get("status") or "") == "closed" and t.get("pnl") is not None
    ))
    hist_h = 42 + (hist_rows * 27 + 28 if hist_rows else 64)
    return html, int(pos_h + 10 + 318 + 10 + hist_h + 16)


def render_ledger_component(**kwargs: Any) -> None:
    """מציג את הפנקס ב-Streamlit. בטוח לקריאה גם בלי Streamlit."""
    html_str, height = render_ledger(**kwargs)
    try:
        import streamlit.components.v1 as components
        components.html(html_str, height=height, scrolling=True)
    except Exception:  # pragma: no cover
        pass


if __name__ == "__main__":
    import sys

    demo_open = [{
        "symbol": "BTCUSDT", "side": "LONG", "entry_price": 87000.0,
        "sl_price": 86200.0, "tp_price": 88400.0, "quantity": 0.012,
        "opened_at": "2026-09-10T13:00:00+00:00", "status": "open",
    }, {
        "symbol": "SOLUSDT", "side": "SHORT", "entry_price": 141.5,
        "sl_price": 143.9, "tp_price": 137.2, "quantity": 3.5,
        "opened_at": "2026-09-10T13:22:00+00:00", "status": "open",
    }]
    demo_hist = [{
        "symbol": s, "side": sd, "status": "closed", "entry_price": e,
        "exit_price": x, "pnl": p, "pnl_pct": p / 100,
        "close_reason": r, "closed_at": "2026-09-10T12:%02d:00+00:00" % (i * 4),
    } for i, (s, sd, e, x, p, r) in enumerate([
        ("ETHUSDT", "LONG", 3120.0, 3148.0, 4.20, "take_profit"),
        ("ARBUSDT", "SHORT", 0.812, 0.826, -2.10, "stop_loss"),
        ("TONUSDT", "LONG", 5.44, 5.44, -0.08, "stale_exit"),
        ("SUIUSDT", "LONG", 3.02, 3.09, 3.35, "trail"),
    ])]
    demo_events = [
        {"event_type": "STARTUP", "message": "Trading system started | mode=PAPER",
         "severity": "INFO", "timestamp": "2026-09-10T13:00:00+00:00"},
        {"event_type": "SL_FAILED", "message": "Protective stop rejected by exchange",
         "severity": "CRITICAL", "timestamp": "2026-09-10T13:14:00+00:00"},
        {"event_type": "HEALTH_REPAIR", "message": "Adopted untracked live position",
         "severity": "WARNING", "timestamp": "2026-09-10T13:20:00+00:00"},
    ]

    body, h = render_ledger(open_trades=demo_open, trade_history=demo_hist,
                            events=demo_events, max_positions=3,
                            health_path="data/model_health.json")
    out = sys.argv[1] if len(sys.argv) > 1 else "ledger_preview.html"
    page = ('<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">'
            '<title>פנקס</title><style>html,body{margin:0;background:#04060a;padding:10px;}'
            '</style></head><body>' + body + '</body></html>')
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(page)
    print(f"נכתב: {out} ({len(page):,} bytes, גובה {h}px)")

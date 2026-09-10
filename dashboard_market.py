"""
פאנל שוק חי — הבוט בהקשר של השוק האמיתי.

מה זה עושה: נרות, ספר פקודות וסרט עסקאות מגיעים **ישירות מ-Binance אל
הדפדפן** דרך WebSocket ציבורי (בלי מפתחות API, בלי לעבור דרך פייתון).
מעליהם מצוירים הקווים של הבוט עצמו — מחיר כניסה, SL, TP — והביצועים
שכבר קרו. ככה רואים לא רק "מה השוק עושה" אלא "איפה הבוט עומד בתוכו".

────────────────────────────────────────────────────────────────────────
החלטת התכנון החשובה במודול הזה
────────────────────────────────────────────────────────────────────────
הדשבורד מרונדר מחדש כל 4 שניות (`st_autorefresh`). Streamlit מעביר את
ה-HTML כ-prop ל-iframe; אם ה-prop משתנה — ה-iframe נטען מחדש, וה-WebSocket
מת. כל 4 שניות. זה היה הופך את הפאנל ללא-שמיש.

לכן ה-HTML כאן הוא **פונקציה טהורה של מצב הפוזיציות**:
אין שעון, אין "לפני X שניות", אין מונה רענונים. חותמות זמן נשמרות כ-epoch
במילישניות (מספר קבוע), מחירים מעוגלים, והמפתחות ממוינים.

התוצאה: כל עוד הבוט לא פתח או סגר פוזיציה, ה-HTML זהה בית-בית בין רענונים,
React לא נוגע ב-iframe, וה-WebSocket ממשיך לזרום. חיבור מחדש קורה רק כשמשהו
אמיתי השתנה — כלומר לעיתים רחוקות.

**כל שינוי כאן חייב לשמור על התכונה הזו.** אם תוסיפו ערך שמשתנה בכל רענון,
הפאנל יתחיל להבהב וה-WebSocket ייפול שוב.
────────────────────────────────────────────────────────────────────────

שימוש:
    from dashboard_market import render_market_component
    render_market_component(config=config, open_trades=..., trade_history=...)
"""

from __future__ import annotations

import json
from typing import Any, Dict, List, Optional, Tuple

from dashboard_floor import _f, _parse_ts, esc

# כמה עסקאות סגורות לצייר על הגרף לכל סימבול. מספר קבוע (ולא "24 שעות
# אחרונות") כדי שהמטען יישאר יציב בין רענונים.
FILLS_PER_SYMBOL = 12

# תקרת סימבולים בבורר. יותר מזה והשורה נשברת בלי להוסיף מידע.
MAX_SYMBOLS = 8


def _ms(ts: Any) -> Optional[int]:
    """ISO-8601 -> epoch במילישניות. מספר קבוע, לא תלוי בזמן הנוכחי."""
    dt = _parse_ts(ts)
    return int(dt.timestamp() * 1000) if dt else None


def _round(value: Any, digits: int = 8) -> Optional[float]:
    """מעגל מחיר לערך יציב — מונע רעש צף שישבור את יציבות ה-HTML."""
    v = _f(value, float("nan"))
    if v != v:  # NaN
        return None
    return round(v, digits)


def build_payload(
    open_trades: List[Dict[str, Any]],
    trade_history: List[Dict[str, Any]],
    recent_signals: List[Dict[str, Any]],
    paper: bool,
) -> Dict[str, Any]:
    """
    בונה את המטען שעובר לדפדפן.

    חוזה קשיח: הפלט תלוי אך ורק בתוכן ה-DB, לא בזמן הקריאה. שתי קריאות
    רצופות בלי שינוי במסד חייבות להחזיר מטען זהה — עליו נשענת יציבות
    ה-iframe (ראו את הדוקסטרינג של המודול).
    """
    # --- הסימבולים שמעניינים: קודם כל מה שפתוח עכשיו ---
    symbols: List[str] = []
    for tr in open_trades:
        sym = str(tr.get("symbol") or "").upper()
        if sym and sym not in symbols:
            symbols.append(sym)

    # ואז מה שנסחר או נסרק לאחרונה, לפי סדר הופעה
    for src in (trade_history, recent_signals):
        for row in src:
            sym = str(row.get("symbol") or "").upper()
            if sym and sym not in symbols:
                symbols.append(sym)
            if len(symbols) >= MAX_SYMBOLS:
                break
        if len(symbols) >= MAX_SYMBOLS:
            break

    symbols = symbols[:MAX_SYMBOLS]

    # הבוט עוד לא נגע באף סימבול (DB טרי). מציגים את ברירת המחדל המובנת
    # מאליה כדי שהפאנל יהיה שימושי כבר בהפעלה הראשונה — נתוני השוק
    # אמיתיים בדיוק כמו בכל סימבול אחר, רק הבחירה היא שלנו.
    if not symbols:
        symbols = ["BTCUSDT"]

    # --- פוזיציות פתוחות: הקווים שיצוירו על הגרף ---
    positions: Dict[str, Dict[str, Any]] = {}
    for tr in open_trades:
        sym = str(tr.get("symbol") or "").upper()
        if not sym:
            continue
        positions[sym] = {
            "side": str(tr.get("side") or "").upper(),
            "entry": _round(tr.get("entry_price")),
            "sl": _round(tr.get("sl_price")),
            "tp": _round(tr.get("tp_price")),
            "qty": _round(tr.get("quantity")),
            "openedMs": _ms(tr.get("opened_at")),
        }

    # --- ביצועים שכבר קרו: משולשי כניסה/יציאה על הגרף ---
    per_symbol: Dict[str, int] = {}
    fills: List[Dict[str, Any]] = []
    for tr in trade_history:
        sym = str(tr.get("symbol") or "").upper()
        if sym not in symbols or str(tr.get("status") or "") != "closed":
            continue
        if per_symbol.get(sym, 0) >= FILLS_PER_SYMBOL:
            continue
        per_symbol[sym] = per_symbol.get(sym, 0) + 1

        side = str(tr.get("side") or "").upper()
        entry_ms, exit_ms = _ms(tr.get("opened_at")), _ms(tr.get("closed_at"))
        entry_px, exit_px = _round(tr.get("entry_price")), _round(tr.get("exit_price"))

        if entry_ms and entry_px:
            fills.append({"sym": sym, "kind": "entry", "side": side,
                          "px": entry_px, "ms": entry_ms, "pnl": None})
        if exit_ms and exit_px:
            fills.append({"sym": sym, "kind": "exit", "side": side,
                          "px": exit_px, "ms": exit_ms,
                          "pnl": _round(tr.get("pnl"), 4),
                          "reason": str(tr.get("close_reason") or "")})

    fills.sort(key=lambda f: (f["sym"], f["ms"], f["kind"]))

    return {
        "symbols": symbols,
        "primary": symbols[0] if symbols else "",
        "positions": positions,
        "fills": fills,
        "paper": bool(paper),
    }


# ---------------------------------------------------------------------------
# עיצוב — מחרוזת רגילה, לא f-string
# ---------------------------------------------------------------------------

MARKET_CSS = """
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

.mk{
  font-family:var(--sans);color:var(--text);padding:0;
  display:flex;flex-direction:column;gap:9px;
}
.num{font-family:var(--mono);font-variant-numeric:tabular-nums;
  direction:ltr;unicode-bidi:isolate;letter-spacing:-.2px;}
.pos{color:var(--green);} .neg{color:var(--red);} .acc{color:var(--cyan);}
.cap{font-size:9.5px;font-weight:800;letter-spacing:1.5px;color:var(--dim);
  text-transform:uppercase;font-family:var(--mono);}

/* ---------- שורת הכותרת ---------- */
.mkhead{
  display:flex;align-items:center;gap:9px;flex-wrap:wrap;padding:8px 11px;
  background:linear-gradient(90deg,rgba(16,23,33,.95),rgba(11,17,25,.72));
  border:1px solid var(--line);border-radius:10px;
}
.syms{display:flex;gap:5px;flex-wrap:wrap;}
.sym{
  font-family:var(--mono);font-size:10.5px;font-weight:800;letter-spacing:.4px;
  padding:3px 9px;border-radius:999px;cursor:pointer;user-select:none;
  border:1px solid rgba(96,140,175,.25);background:rgba(96,140,175,.07);
  color:var(--muted);transition:all .16s ease;white-space:nowrap;
}
.sym:hover{border-color:rgba(53,214,255,.45);color:var(--text);}
.sym.on{background:rgba(53,214,255,.14);border-color:rgba(53,214,255,.55);color:var(--cyan);}
.sym.held{box-shadow:inset 0 0 0 1px rgba(34,224,138,.35);}
.sym .hd{color:var(--green);font-size:8px;margin-inline-start:3px;}

.ivs{display:flex;gap:3px;}
.iv{
  font-family:var(--mono);font-size:9.5px;font-weight:800;padding:3px 7px;
  border-radius:6px;cursor:pointer;user-select:none;color:var(--dim);
  border:1px solid transparent;
}
.iv.on{color:var(--cyan);border-color:rgba(53,214,255,.4);background:rgba(53,214,255,.09);}

.last{display:flex;align-items:baseline;gap:7px;margin-inline-start:auto;}
.last .px{font-family:var(--mono);font-size:19px;font-weight:800;letter-spacing:-.5px;}
.last .ch{font-family:var(--mono);font-size:11px;font-weight:800;}
.conn{display:flex;align-items:center;gap:5px;font-size:10px;color:var(--muted);}
.conn .d{width:7px;height:7px;border-radius:50%;background:var(--dim);}
.conn.live .d{background:var(--green);animation:bp 1.9s ease-out infinite;}
.conn.wait .d{background:var(--amber);}
.conn.down .d{background:var(--red);}
@keyframes bp{0%{box-shadow:0 0 0 0 rgba(34,224,138,.5);}
  70%{box-shadow:0 0 0 8px rgba(34,224,138,0);}100%{box-shadow:0 0 0 0 rgba(34,224,138,0);}}

/* ---------- הפריסה ---------- */
.grid{display:grid;grid-template-columns:minmax(0,2.5fr) minmax(190px,.95fr) minmax(168px,.8fr);
  gap:9px;align-items:stretch;}
@media(max-width:900px){.grid{grid-template-columns:1fr;}}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;
  overflow:hidden;display:flex;flex-direction:column;min-width:0;}
.card > .hd{padding:7px 10px;border-bottom:1px solid var(--line);
  display:flex;align-items:center;justify-content:space-between;gap:8px;}

/* הגרף עצמו נשאר LTR: זמן זורם שמאל->ימין וציר המחיר מימין, כמו בכל
   פלטפורמת מסחר. היפוך שלו לטובת RTL רק יבלבל. */
.chartbox{position:relative;flex:1;min-height:200px;direction:ltr;}
.chartbox canvas{display:block;width:100%;height:100%;}
.msg{
  position:absolute;inset:0;display:none;align-items:center;justify-content:center;
  text-align:center;padding:18px;font-size:12px;color:var(--muted);
  background:rgba(4,6,10,.86);direction:rtl;line-height:1.7;
}
.msg.on{display:flex;}
.msg b{color:var(--amber);}

/* ---------- ספר פקודות ---------- */
.book{flex:1;display:flex;flex-direction:column;font-family:var(--mono);font-size:10px;}
.bk{flex:1;display:flex;flex-direction:column;justify-content:flex-end;overflow:hidden;}
.bk.asks{justify-content:flex-start;}
.brow{position:relative;display:grid;grid-template-columns:1fr 1fr;gap:6px;
  padding:1.5px 8px;direction:ltr;}
.brow .bar{position:absolute;top:0;bottom:0;right:0;opacity:.16;}
.brow .p,.brow .q{position:relative;z-index:1;}
.brow .p{text-align:left;font-weight:700;}
.brow .q{text-align:right;color:var(--muted);}
.asks .p{color:var(--red);} .asks .bar{background:var(--red);}
.bids .p{color:var(--green);} .bids .bar{background:var(--green);}
.brow.mine{box-shadow:inset 2px 0 0 var(--cyan);}
.brow.mine .q::after{content:"◂ הבוט";color:var(--cyan);font-size:8px;margin-inline-start:4px;}
.spread{display:flex;align-items:center;justify-content:space-between;gap:6px;
  padding:4px 8px;border-block:1px solid var(--line);background:rgba(53,214,255,.05);
  font-family:var(--mono);font-size:10px;}
.spread .v{font-weight:800;}

/* ---------- סרט עסקאות ---------- */
.tape{flex:1;overflow:hidden;display:flex;flex-direction:column;
  font-family:var(--mono);font-size:10px;}
.trow{display:grid;grid-template-columns:1fr auto auto;gap:6px;padding:2px 8px;
  direction:ltr;border-bottom:1px solid rgba(96,140,175,.05);}
.trow.buy .p{color:var(--green);} .trow.sell .p{color:var(--red);}
.trow .p{font-weight:700;text-align:left;}
.trow .q{color:var(--muted);text-align:right;}
.trow .t{color:var(--dim);font-size:9px;}
.trow.big{background:rgba(255,176,32,.09);}

/* ---------- כרטיס הפוזיציה ---------- */
.poswrap{padding:7px 10px;border-top:1px solid var(--line);
  display:flex;gap:10px;flex-wrap:wrap;align-items:center;font-size:10.5px;}
.pchip{display:flex;align-items:center;gap:5px;}
.pchip .k{font-size:9px;letter-spacing:.8px;text-transform:uppercase;
  color:var(--dim);font-family:var(--mono);font-weight:700;}
.pchip .v{font-family:var(--mono);font-weight:800;font-size:11px;}
.pnone{color:var(--dim);font-size:10.5px;}
</style>
"""


# ---------------------------------------------------------------------------
# הלקוח — כל הלוגיקה החיה רצה בדפדפן. מחרוזת רגילה, לא f-string.
# ---------------------------------------------------------------------------
#
# למה בדפדפן ולא בפייתון: נתוני שוק ציבוריים ב-Binance לא דורשים מפתח API,
# והדפדפן יכול להתחבר אליהם ישירות. ככה הזרם החי מנותק לגמרי ממחזור
# הרענון של Streamlit — הנרות זזים ברציפות גם בין רענון לרענון.

_MK_JS_1 = r"""
<script>
(function () {
  "use strict";

  var REST = "https://fapi.binance.com/fapi/v1/klines";
  var WSBASE = "wss://fstream.binance.com/stream?streams=";
  var CACHE_TTL_MS = 20000;   // כמה זמן להאמין ל-klines שבמטמון
  var TAPE_MAX = 40;
  var GREEN = "#22e08a", RED = "#ff4d6a", CYAN = "#35d6ff", AMBER = "#ffb020";
  var DIM = "#54677a", MUTED = "#7f93a6", GRID = "rgba(96,140,175,.10)";

  var cfg = JSON.parse(document.getElementById("mk-payload").textContent);

  var S = {
    symbol: cfg.primary || "BTCUSDT",
    interval: "1m",
    klines: [],        // [{t,o,h,l,c,v}]
    book: null,        // {bids:[[p,q]], asks:[[p,q]]}
    tape: [],
    last: null,
    chgPct: null,
    ws: null,
    retry: 0,
    seeding: false,
    dead: false,
  };

  // ---------- עזרים ----------
  function $(id) { return document.getElementById(id); }

  function decimals(p) {
    p = Math.abs(p || 0);
    if (p >= 1000) return 2;
    if (p >= 100) return 2;
    if (p >= 1) return 4;
    if (p >= 0.01) return 5;
    return 7;
  }
  function fp(p, d) { return (p == null || isNaN(p)) ? "—" : Number(p).toFixed(d != null ? d : decimals(p)); }
  function fq(q) {
    q = Number(q) || 0;
    if (q >= 1e6) return (q / 1e6).toFixed(2) + "M";
    if (q >= 1e3) return (q / 1e3).toFixed(2) + "K";
    if (q >= 1) return q.toFixed(2);
    return q.toFixed(4);
  }
  function hhmmss(ms) {
    var d = new Date(ms);
    function p2(n) { return (n < 10 ? "0" : "") + n; }
    return p2(d.getHours()) + ":" + p2(d.getMinutes()) + ":" + p2(d.getSeconds());
  }
  function hhmm(ms) {
    var d = new Date(ms);
    function p2(n) { return (n < 10 ? "0" : "") + n; }
    return p2(d.getHours()) + ":" + p2(d.getMinutes());
  }
  function pos() { return cfg.positions[S.symbol] || null; }

  function setConn(kind, text) {
    var el = $("mk-conn");
    el.className = "conn " + kind;
    el.lastElementChild.textContent = text;
  }
  function showMsg(html) {
    var m = $("mk-msg");
    if (!html) { m.className = "msg"; return; }
    m.innerHTML = html;
    m.className = "msg on";
  }

  // ---------- טעינת היסטוריה (REST) ----------
  function cacheKey() { return "mk:" + S.symbol + ":" + S.interval; }

  function readCache() {
    try {
      var raw = sessionStorage.getItem(cacheKey());
      if (!raw) return null;
      var o = JSON.parse(raw);
      if (!o || (Date.now() - o.at) > CACHE_TTL_MS) return null;
      return o.k;
    } catch (e) { return null; }
  }
  function writeCache(k) {
    try { sessionStorage.setItem(cacheKey(), JSON.stringify({ at: Date.now(), k: k })); }
    catch (e) { /* מצב פרטי / אחסון מלא — לא קריטי */ }
  }

  function seed() {
    if (S.seeding) return;
    S.seeding = true;

    var cached = readCache();
    if (cached && cached.length) {
      S.klines = cached;
      S.seeding = false;
      draw();
      return;
    }

    var url = REST + "?symbol=" + encodeURIComponent(S.symbol) +
              "&interval=" + encodeURIComponent(S.interval) + "&limit=200";
    fetch(url)
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (rows) {
        S.klines = rows.map(function (r) {
          return { t: r[0], o: +r[1], h: +r[2], l: +r[3], c: +r[4], v: +r[5] };
        });
        writeCache(S.klines);
        S.seeding = false;
        showMsg(null);
        draw();
      })
      .catch(function (err) {
        S.seeding = false;
        S.dead = true;
        showMsg(
          "<div>לא הצלחתי להגיע ל-Binance מהדפדפן.<br><br>" +
          "<b>" + String(err.message || err) + "</b><br><br>" +
          "נתוני השוק כאן נמשכים ישירות מהדפדפן שלך אל Binance — " +
          "בלי מפתחות API. אם יש חסימה ברשת, VPN או חומת אש, הפאנל " +
          "יישאר ריק.<br>שאר הדשבורד ממשיך לעבוד כרגיל.</div>"
        );
      });
  }

  // ---------- הזרם החי (WebSocket) ----------
  function streams() {
    var s = S.symbol.toLowerCase();
    return [
      s + "@kline_" + S.interval,
      s + "@depth20@100ms",
      s + "@aggTrade",
      s + "@ticker"
    ].join("/");
  }

  function connect() {
    closeWs();
    setConn("wait", "מתחבר…");
    var ws;
    try {
      ws = new WebSocket(WSBASE + streams());
    } catch (e) {
      scheduleRetry();
      return;
    }
    S.ws = ws;

    ws.onopen = function () {
      S.retry = 0;
      setConn("live", "חי");
      if (!S.dead) showMsg(null);
    };
    ws.onmessage = function (ev) {
      var msg;
      try { msg = JSON.parse(ev.data); } catch (e) { return; }
      var d = msg.data;
      if (!d) return;
      if (d.e === "kline") onKline(d.k);
      else if (d.e === "depthUpdate") onDepth(d);
      else if (d.e === "aggTrade") onTrade(d);
      else if (d.e === "24hrTicker") onTicker(d);
    };
    ws.onclose = function () { scheduleRetry(); };
    ws.onerror = function () { try { ws.close(); } catch (e) {} };
  }

  function closeWs() {
    if (S.ws) {
      S.ws.onclose = null;
      try { S.ws.close(); } catch (e) {}
      S.ws = null;
    }
  }

  function scheduleRetry() {
    setConn("down", "מנותק");
    S.retry = Math.min(S.retry + 1, 6);
    var wait = Math.min(1000 * Math.pow(2, S.retry - 1), 30000);
    setTimeout(function () {
      if (document.hidden) return;   // נתחבר מחדש כשהלשונית תחזור
      connect();
    }, wait);
  }

  // ---------- מטפלי הודעות ----------
  function onKline(k) {
    var bar = { t: k.t, o: +k.o, h: +k.h, l: +k.l, c: +k.c, v: +k.v };
    var n = S.klines.length;
    if (n && S.klines[n - 1].t === bar.t) S.klines[n - 1] = bar;
    else {
      S.klines.push(bar);
      if (S.klines.length > 400) S.klines.shift();
      writeCache(S.klines);
    }
    S.last = bar.c;
    paintLast();
    refreshPos();
    scheduleDraw();
  }

  function onTicker(d) {
    S.last = +d.c;
    S.chgPct = +d.P;
    paintLast();
    refreshPos();
  }

  function onDepth(d) {
    // depth20 הוא תצלום של ראש הספר בכל הודעה — פשוט מחליפים
    S.book = { bids: d.b || [], asks: d.a || [] };
    renderBook();
  }

  function onTrade(d) {
    S.tape.unshift({ p: +d.p, q: +d.q, t: d.T, sell: !!d.m });
    if (S.tape.length > TAPE_MAX) S.tape.pop();
    renderTape();
  }

  // ---------- מחיר אחרון בכותרת ----------
  function paintLast() {
    var el = $("mk-px");
    if (S.last == null) { el.textContent = "—"; return; }
    var d = decimals(S.last);
    var prev = parseFloat(el.dataset.v || "0");
    el.textContent = fp(S.last, d);
    el.dataset.v = String(S.last);
    el.style.color = !prev ? "#e8f2f8" : (S.last >= prev ? GREEN : RED);

    var ch = $("mk-ch");
    if (S.chgPct == null) { ch.textContent = ""; return; }
    ch.textContent = (S.chgPct >= 0 ? "+" : "") + S.chgPct.toFixed(2) + "%";
    ch.className = "ch " + (S.chgPct >= 0 ? "pos" : "neg");
  }

  // הרווח הנוכחי בכרטיס הפוזיציה תלוי במחיר החי, לכן הוא מתרענן כאן ולא
  // רק בהחלפת סימבול. מווסת לחצי שנייה — בניית DOM בכל טיק היא בזבוז.
  var lastPosPaint = 0;
  function refreshPos() {
    var now = Date.now();
    if (now - lastPosPaint < 500) return;
    lastPosPaint = now;
    renderPos();
  }
"""


_MK_JS_2 = r"""
  // ---------- ספר הפקודות ----------
  // רמות ה-SL/TP של הבוט מסומנות בתוך הסולם — ככה רואים אם הן יושבות
  // בתוך הנזילות הקיימת או רחוק מעבר לה.
  function renderBook() {
    if (!S.book) return;
    var p = pos();
    var levels = [];
    if (p) {
      if (p.sl) levels.push(p.sl);
      if (p.tp) levels.push(p.tp);
      if (p.entry) levels.push(p.entry);
    }

    var asks = (S.book.asks || []).slice(0, 10);
    var bids = (S.book.bids || []).slice(0, 10);
    var peak = 0;
    asks.concat(bids).forEach(function (r) { peak = Math.max(peak, +r[1]); });
    peak = peak || 1;

    var d = decimals(S.last || (asks[0] && +asks[0][0]) || 1);

    function rows(list, cls, reverse) {
      var arr = list.slice();
      if (reverse) arr.reverse();
      return arr.map(function (r) {
        var price = +r[0], qty = +r[1];
        var w = Math.max(1, (qty / peak) * 100);
        var mine = levels.some(function (lv) {
          return Math.abs(lv - price) / price < 0.0004;   // בתוך 4 נקודות בסיס
        });
        return '<div class="brow ' + cls + (mine ? " mine" : "") + '">' +
               '<span class="bar" style="width:' + w.toFixed(1) + '%"></span>' +
               '<span class="p">' + fp(price, d) + '</span>' +
               '<span class="q">' + fq(qty) + '</span></div>';
      }).join("");
    }

    $("mk-asks").innerHTML = rows(asks, "asks", true);
    $("mk-bids").innerHTML = rows(bids, "bids", false);

    var bestAsk = asks.length ? +asks[0][0] : null;
    var bestBid = bids.length ? +bids[0][0] : null;
    if (bestAsk && bestBid) {
      var sp = bestAsk - bestBid;
      $("mk-spread").innerHTML =
        '<span class="cap">מרווח</span>' +
        '<span class="v">' + fp(sp, d) + " · " + ((sp / bestBid) * 100).toFixed(3) + "%</span>";
    }
  }

  // ---------- סרט העסקאות ----------
  function renderTape() {
    var d = decimals(S.last || 1);
    var big = 0;
    S.tape.forEach(function (t) { big = Math.max(big, t.q); });
    $("mk-tape").innerHTML = S.tape.map(function (t) {
      var cls = t.sell ? "sell" : "buy";
      if (big && t.q >= big * 0.6) cls += " big";
      return '<div class="trow ' + cls + '">' +
             '<span class="p">' + fp(t.p, d) + '</span>' +
             '<span class="q">' + fq(t.q) + '</span>' +
             '<span class="t">' + hhmmss(t.t) + '</span></div>';
    }).join("");
  }

  // ---------- גרף הנרות ----------
  var raf = null;
  function scheduleDraw() {
    if (raf) return;
    raf = requestAnimationFrame(function () { raf = null; draw(); });
  }

  function draw() {
    var cv = $("mk-canvas");
    var box = cv.parentElement;
    var W = box.clientWidth, H = box.clientHeight;
    if (!W || !H) return;

    var dpr = window.devicePixelRatio || 1;
    if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) {
      cv.width = Math.round(W * dpr);
      cv.height = Math.round(H * dpr);
    }
    var ctx = cv.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    if (!S.klines.length) return;

    var padR = 62, padB = 20, padT = 8, padL = 6;
    var plotW = W - padR - padL;
    var volH = Math.max(24, (H - padT - padB) * 0.17);
    var plotH = H - padT - padB - volH - 6;
    if (plotW <= 20 || plotH <= 20) return;

    // כמה נרות נכנסים ברוחב הזה
    var slot = 7;
    var count = Math.max(10, Math.min(S.klines.length, Math.floor(plotW / slot)));
    var vis = S.klines.slice(-count);
    slot = plotW / vis.length;
    var bw = Math.max(1, Math.min(slot * 0.68, 14));

    // --- טווח המחירים ---
    var lo = Infinity, hi = -Infinity, vmax = 0;
    vis.forEach(function (k) {
      if (k.l < lo) lo = k.l;
      if (k.h > hi) hi = k.h;
      if (k.v > vmax) vmax = k.v;
    });

    // הקווים של הבוט נכללים בטווח, אבל רק אם הם קרובים מספיק — רמה
    // רחוקה מאוד הייתה מועכת את הנרות לפס דק.
    var p = pos();
    var span0 = (hi - lo) || (hi * 0.001) || 1;
    var overlays = [];
    if (p) {
      if (p.entry) overlays.push({ v: p.entry, c: CYAN, label: "כניסה" });
      if (p.sl) overlays.push({ v: p.sl, c: RED, label: "SL" });
      if (p.tp) overlays.push({ v: p.tp, c: GREEN, label: "TP" });
      overlays.forEach(function (o) {
        if (o.v > lo - span0 * 2.2 && o.v < hi + span0 * 2.2) {
          lo = Math.min(lo, o.v);
          hi = Math.max(hi, o.v);
        } else {
          o.off = true;   // מחוץ לתצוגה — נסמן בקצה במקום למעוך הכל
        }
      });
    }

    var pad = (hi - lo) * 0.08 || hi * 0.001 || 1;
    lo -= pad; hi += pad;
    var span = (hi - lo) || 1;

    function y(v) { return padT + plotH * (1 - (v - lo) / span); }
    function x(i) { return padL + i * slot + slot / 2; }

    var d = decimals(vis[vis.length - 1].c);

    // --- רשת + ציר מחיר ---
    ctx.font = "10px 'JetBrains Mono',monospace";
    ctx.textBaseline = "middle";
    for (var g = 0; g <= 4; g++) {
      var gv = lo + (span * g) / 4;
      var gy = Math.round(y(gv)) + 0.5;
      ctx.strokeStyle = GRID;
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(padL, gy); ctx.lineTo(padL + plotW, gy); ctx.stroke();
      ctx.fillStyle = DIM;
      ctx.textAlign = "left";
      ctx.fillText(fp(gv, d), padL + plotW + 6, gy);
    }

    // --- ציר זמן ---
    ctx.textAlign = "center";
    ctx.fillStyle = DIM;
    var step = Math.max(1, Math.floor(vis.length / 6));
    for (var ti = 0; ti < vis.length; ti += step) {
      var tx = x(ti);
      if (tx < 18 || tx > padL + plotW - 18) continue;   // לא לחתוך בקצוות
      ctx.fillText(hhmm(vis[ti].t), tx, H - padB / 2);
    }

    // --- עמודות מחזור ---
    var volTop = padT + plotH + 6;
    vis.forEach(function (k, i) {
      var h = vmax ? (k.v / vmax) * volH : 0;
      ctx.fillStyle = k.c >= k.o ? "rgba(34,224,138,.28)" : "rgba(255,77,106,.28)";
      ctx.fillRect(x(i) - bw / 2, volTop + volH - h, bw, h);
    });

    // --- נרות ---
    vis.forEach(function (k, i) {
      var up = k.c >= k.o;
      var col = up ? GREEN : RED;
      var cx = x(i);
      ctx.strokeStyle = col;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(Math.round(cx) + 0.5, y(k.h));
      ctx.lineTo(Math.round(cx) + 0.5, y(k.l));
      ctx.stroke();
      var yo = y(k.o), yc = y(k.c);
      var top = Math.min(yo, yc);
      var bh = Math.max(1, Math.abs(yc - yo));
      ctx.fillStyle = col;
      ctx.fillRect(cx - bw / 2, top, bw, bh);
    });

    // --- הקווים של הבוט ---
    overlays.forEach(function (o) {
      if (o.off) return;
      var ly = Math.round(y(o.v)) + 0.5;
      ctx.save();
      ctx.strokeStyle = o.c;
      ctx.setLineDash(o.label === "כניסה" ? [2, 3] : [6, 4]);
      ctx.lineWidth = 1.2;
      ctx.globalAlpha = 0.85;
      ctx.beginPath(); ctx.moveTo(padL, ly); ctx.lineTo(padL + plotW, ly); ctx.stroke();
      ctx.restore();

      ctx.fillStyle = o.c;
      ctx.fillRect(padL + plotW + 2, ly - 7, padR - 4, 14);
      ctx.fillStyle = "#04060a";
      ctx.font = "700 9px 'JetBrains Mono',monospace";
      ctx.textAlign = "left";
      ctx.fillText(o.label + " " + fp(o.v, d), padL + plotW + 5, ly);
      ctx.font = "10px 'JetBrains Mono',monospace";
    });

    // --- ביצועים שכבר קרו ---
    var t0 = vis[0].t, t1 = vis[vis.length - 1].t;
    var bucket = vis.length > 1 ? (t1 - t0) / (vis.length - 1) : 60000;
    cfg.fills.forEach(function (f) {
      if (f.sym !== S.symbol) return;
      if (f.ms < t0 - bucket || f.ms > t1 + bucket) return;
      if (f.px < lo || f.px > hi) return;
      var fx = padL + ((f.ms - t0) / bucket) * slot + slot / 2;
      var fy = y(f.px);
      var isEntry = f.kind === "entry";
      var col = isEntry ? CYAN : (f.pnl != null && f.pnl >= 0 ? GREEN : RED);
      ctx.fillStyle = col;
      ctx.beginPath();
      if (isEntry) {                 // משולש כלפי מעלה = כניסה
        ctx.moveTo(fx, fy - 5); ctx.lineTo(fx - 4.5, fy + 3); ctx.lineTo(fx + 4.5, fy + 3);
      } else {                       // משולש כלפי מטה = יציאה
        ctx.moveTo(fx, fy + 5); ctx.lineTo(fx - 4.5, fy - 3); ctx.lineTo(fx + 4.5, fy - 3);
      }
      ctx.closePath(); ctx.fill();
      ctx.strokeStyle = "#04060a"; ctx.lineWidth = 1; ctx.stroke();
    });

    // --- קו המחיר האחרון ---
    var lastC = vis[vis.length - 1].c;
    var lyy = Math.round(y(lastC)) + 0.5;
    ctx.save();
    ctx.strokeStyle = "rgba(232,242,248,.45)";
    ctx.setLineDash([3, 3]);
    ctx.beginPath(); ctx.moveTo(padL, lyy); ctx.lineTo(padL + plotW, lyy); ctx.stroke();
    ctx.restore();
    ctx.fillStyle = "#e8f2f8";
    ctx.fillRect(padL + plotW + 2, lyy - 7, padR - 4, 14);
    ctx.fillStyle = "#04060a";
    ctx.font = "800 9.5px 'JetBrains Mono',monospace";
    ctx.textAlign = "left";
    ctx.fillText(fp(lastC, d), padL + plotW + 5, lyy);
  }

  // ---------- כרטיס הפוזיציה מתחת לגרף ----------
  function renderPos() {
    var p = pos();
    var el = $("mk-pos");
    if (!p) {
      el.innerHTML = '<span class="pnone">אין פוזיציה פתוחה בסימבול הזה — ' +
                     'הגרף מציג את השוק בלבד.</span>';
      return;
    }
    var d = decimals(p.entry || S.last || 1);
    var isLong = p.side === "LONG";
    function chip(k, v, cls) {
      return '<span class="pchip"><span class="k">' + k + '</span>' +
             '<span class="v ' + (cls || "") + '">' + v + "</span></span>";
    }
    var live = "";
    if (S.last && p.entry) {
      var pct = ((S.last - p.entry) / p.entry) * 100 * (isLong ? 1 : -1);
      live = chip("רווח נוכחי", (pct >= 0 ? "+" : "") + pct.toFixed(2) + "%",
                  pct >= 0 ? "pos" : "neg");
    }
    el.innerHTML =
      chip("כיוון", isLong ? "לונג" : "שורט", isLong ? "pos" : "neg") +
      chip("כניסה", fp(p.entry, d), "acc") +
      chip("SL", fp(p.sl, d), "neg") +
      chip("TP", fp(p.tp, d), "pos") +
      chip("כמות", fq(p.qty)) +
      live;
  }

  // ---------- החלפת סימבול / טווח ----------
  function switchTo(symbol, interval) {
    S.symbol = symbol || S.symbol;
    S.interval = interval || S.interval;
    S.klines = []; S.book = null; S.tape = []; S.last = null; S.chgPct = null;
    S.dead = false;
    try {
      sessionStorage.setItem("mk:sel", JSON.stringify({ s: S.symbol, i: S.interval }));
    } catch (e) {}

    document.querySelectorAll(".sym").forEach(function (n) {
      n.classList.toggle("on", n.dataset.sym === S.symbol);
    });
    document.querySelectorAll(".iv").forEach(function (n) {
      n.classList.toggle("on", n.dataset.iv === S.interval);
    });

    $("mk-asks").innerHTML = ""; $("mk-bids").innerHTML = "";
    $("mk-tape").innerHTML = ""; $("mk-spread").innerHTML = "";
    renderPos();
    showMsg("<div>טוען " + S.symbol + "…</div>");
    seed();
    connect();
  }

  // ---------- אתחול ----------
  document.querySelectorAll(".sym").forEach(function (n) {
    n.addEventListener("click", function () { switchTo(n.dataset.sym, null); });
  });
  document.querySelectorAll(".iv").forEach(function (n) {
    n.addEventListener("click", function () { switchTo(null, n.dataset.iv); });
  });

  // שחזור הבחירה האחרונה — כך שטעינה מחדש לא מאבדת את מה שהסתכלת עליו
  try {
    var sel = JSON.parse(sessionStorage.getItem("mk:sel") || "null");
    if (sel && cfg.symbols.indexOf(sel.s) >= 0) { S.symbol = sel.s; S.interval = sel.i || "1m"; }
  } catch (e) {}

  window.addEventListener("resize", scheduleDraw);
  document.addEventListener("visibilitychange", function () {
    if (!document.hidden && (!S.ws || S.ws.readyState > 1)) connect();
  });
  window.addEventListener("beforeunload", closeWs);

  switchTo(S.symbol, S.interval);
})();
</script>
"""

MARKET_JS = _MK_JS_1 + _MK_JS_2


# ---------------------------------------------------------------------------
# הרכבה
# ---------------------------------------------------------------------------

# גובה הפאנל בשולחן עבודה: כותרת + מרווח + שורת הכרטיסים.
CARD_H = 362
PANEL_H = 44 + 9 + CARD_H + 10

_LAYOUT_CSS = """
<style>
.card{height:%dpx;}
@media(max-width:900px){.card{height:320px;}}
</style>
""" % CARD_H


def render_market_panel(
    *,
    config: Any,
    open_trades: Optional[List[Dict[str, Any]]] = None,
    trade_history: Optional[List[Dict[str, Any]]] = None,
    recent_signals: Optional[List[Dict[str, Any]]] = None,
) -> Tuple[str, int]:
    """
    בונה את פאנל השוק ומחזיר (html, גובה).

    שימו לב: הפלט חייב להישאר יציב בין רענונים כשמצב הפוזיציות לא השתנה.
    ראו את הדוקסטרינג של המודול — עליו נשענת שרידות ה-WebSocket.
    """
    payload = build_payload(
        open_trades or [],
        trade_history or [],
        recent_signals or [],
        bool(getattr(config, "paper_trading", True)),
    )

    # `</script>` בתוך JSON היה סוגר את התגית מוקדם. אין לזה סיכוי להופיע
    # בשמות סימבולים, אבל הבריחה זולה והכשל שקט מדי מכדי להסתמך על זה.
    blob = json.dumps(payload, ensure_ascii=False, sort_keys=True).replace("<", "\\u003c")

    held = set(payload["positions"].keys())
    chip_parts = []
    for s in payload["symbols"]:
        is_held = s in held
        cls = "sym held" if is_held else "sym"
        dot = '<span class="hd">●</span>' if is_held else ""
        chip_parts.append(
            '<span class="' + cls + '" data-sym="' + esc(s) + '">'
            + esc(s) + dot + '</span>'
        )
    chips = "".join(chip_parts)
    ivs = "".join(
        f'<span class="iv" data-iv="{iv}">{iv}</span>'
        for iv in ("1m", "5m", "15m", "1h")
    )

    html = f"""{MARKET_CSS}{_LAYOUT_CSS}
    <div class="mk" dir="rtl">
      <div class="mkhead">
        <div class="syms">{chips}</div>
        <div class="ivs">{ivs}</div>
        <div class="last">
          <span class="px" id="mk-px">—</span>
          <span class="ch" id="mk-ch"></span>
        </div>
        <div class="conn wait" id="mk-conn"><span class="d"></span><span>מתחבר…</span></div>
      </div>

      <div class="grid">
        <div class="card">
          <div class="hd">
            <span class="cap" id="mk-title">נרות חיים</span>
            <span class="cap">BINANCE FUTURES · זרם ישיר לדפדפן</span>
          </div>
          <div class="chartbox">
            <canvas id="mk-canvas"></canvas>
            <div class="msg" id="mk-msg"></div>
          </div>
          <div class="poswrap" id="mk-pos"></div>
        </div>

        <div class="card">
          <div class="hd"><span class="cap">ספר פקודות</span>
            <span class="cap">20 רמות · 100ms</span></div>
          <div class="book">
            <div class="bk asks" id="mk-asks"></div>
            <div class="spread" id="mk-spread"></div>
            <div class="bk bids" id="mk-bids"></div>
          </div>
        </div>

        <div class="card">
          <div class="hd"><span class="cap">סרט עסקאות</span>
            <span class="cap">aggTrade</span></div>
          <div class="tape" id="mk-tape"></div>
        </div>
      </div>

      <script type="application/json" id="mk-payload">{blob}</script>
    </div>
    {MARKET_JS}"""

    return html, PANEL_H


def render_market_component(**kwargs: Any) -> None:
    """מציג את פאנל השוק ב-Streamlit. בטוח לקריאה גם בלי Streamlit."""
    html_str, height = render_market_panel(**kwargs)
    try:
        import streamlit.components.v1 as components
        components.html(html_str, height=height, scrolling=False)
    except Exception:  # pragma: no cover
        pass


if __name__ == "__main__":
    import sys

    class _Cfg:
        paper_trading = True

    # פוזיציה לדוגמה כדי לראות את קווי הבוט על הגרף
    demo_open = [{
        "symbol": "BTCUSDT", "side": "LONG", "entry_price": 87000.0,
        "sl_price": 86200.0, "tp_price": 88400.0, "quantity": 0.012,
        "opened_at": "2026-09-10T11:00:00+00:00", "status": "open",
    }]
    demo_hist = [{
        "symbol": "BTCUSDT", "side": "LONG", "status": "closed",
        "entry_price": 86500.0, "exit_price": 86950.0, "pnl": 5.4,
        "opened_at": "2026-09-10T10:10:00+00:00",
        "closed_at": "2026-09-10T10:38:00+00:00", "close_reason": "take_profit",
    }]
    demo_sig = [{"symbol": "ETHUSDT"}, {"symbol": "SOLUSDT"}]

    body, h = render_market_panel(config=_Cfg(), open_trades=demo_open,
                                  trade_history=demo_hist, recent_signals=demo_sig)
    out = sys.argv[1] if len(sys.argv) > 1 else "market_preview.html"
    page = ('<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>פאנל שוק</title><style>html,body{margin:0;background:#04060a;padding:10px;}'
            '</style></head><body>' + body + '</body></html>')
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(page)
    print(f"נכתב: {out}  ({len(page):,} bytes, גובה {h}px)")

"""
Streamlit dashboard for the live Binance Futures trading system.
"""

import sys
import os
import html

# Ensure project root is on the path when running via streamlit
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import logging
import json
from datetime import datetime, timezone
from urllib.parse import quote

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Page configuration — must be first Streamlit call
# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="מערכת מסחר חיה",
    page_icon="📈",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# ---------------------------------------------------------------------------
# Auto-refresh every 10 seconds
# ---------------------------------------------------------------------------
_live_refresh = st.sidebar.checkbox("רענון אוטומטי", value=True, key="live_refresh")
if _live_refresh:
    try:
        from streamlit_autorefresh import st_autorefresh
        st_autorefresh(interval=4_000, key="main_refresh")
    except ImportError:
        st.sidebar.button("רענון ידני")

# ---------------------------------------------------------------------------
# Tech / control-center styling
# ---------------------------------------------------------------------------
st.markdown(
    """
    <style>
      @import url('https://fonts.googleapis.com/css2?family=Heebo:wght@400;500;700;800;900&family=JetBrains+Mono:wght@500;700;800&display=swap');
      :root {
        --bg:#05080c;
        --panel:rgba(14,21,24,.78);
        --panel-2:rgba(17,26,29,.85);
        --line:rgba(140,180,165,.16);
        --line-strong:rgba(140,180,165,.30);
        --text:#edf6f1;
        --muted:#8fa39b;
        --green:#22d68a;
        --cyan:#3fc6ff;
        --amber:#f4b953;
        --red:#ff5e7a;
        --purple:#a78bfa;
        --mono:'JetBrains Mono',ui-monospace,Menlo,monospace;
        --radius:14px;
        --glow-green:0 0 26px rgba(34,214,138,.10);
      }
      html, body, .stApp, [data-testid="stAppViewContainer"],
      h1,h2,h3,h4,h5,h6,p,label,span,div,button,input {
        font-family:'Heebo',-apple-system,'Segoe UI',sans-serif;
      }
      html, body, .stApp, [data-testid="stAppViewContainer"] {
        background: var(--bg);
        color: var(--text);
      }
      [data-testid="stAppViewContainer"] > .main {
        background:
          radial-gradient(ellipse at 15% -5%, rgba(34,214,138,.13), transparent 42%),
          radial-gradient(ellipse at 85% 0%, rgba(63,198,255,.09), transparent 38%),
          radial-gradient(ellipse at 50% 110%, rgba(167,139,250,.07), transparent 45%),
          var(--bg);
      }
      [data-testid="stHeader"] {
        background: rgba(5,8,12,.82);
        backdrop-filter: blur(16px);
      }
      [data-testid="stSidebar"] {
        background: rgba(10,15,18,.96);
        border-left: 1px solid var(--line);
        direction: rtl;
        text-align: right;
        backdrop-filter: blur(14px);
      }
      [data-testid="stSidebar"] * { color: var(--text); }
      .block-container {
        direction: rtl;
        text-align: right;
        max-width: 1420px;
        padding-top: 1.2rem;
        padding-bottom: 3rem;
      }
      ::-webkit-scrollbar { width:10px; height:10px; }
      ::-webkit-scrollbar-track { background:transparent; }
      ::-webkit-scrollbar-thumb { background:rgba(140,180,165,.22); border-radius:var(--radius); }
      ::-webkit-scrollbar-thumb:hover { background:rgba(140,180,165,.36); }
      h1, h2, h3, h4, h5, h6, p, label, span, div { letter-spacing: 0; }
      h1, h2, h3 { color: var(--text); font-weight:800; }
      hr { border-color: var(--line); margin: 1.2rem 0; opacity:.6; }
      .page-hero {
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background:
          linear-gradient(135deg, rgba(18,28,26,.92), rgba(8,13,15,.96));
        padding: 22px 26px 20px;
        margin: 0 0 18px;
        position:relative; overflow:hidden;
        box-shadow: 0 18px 44px rgba(0,0,0,.35), var(--glow-green);
      }
      .page-hero::before {
        content:""; position:absolute; inset:0 0 auto; height:2px;
        background:linear-gradient(90deg, transparent, var(--green), var(--cyan), transparent);
        opacity:.85;
      }
      .page-hero .kicker {
        color: var(--green);
        font-size: 0.88rem;
        font-weight: 800;
        letter-spacing:.06em;
      }
      .page-hero h1 {
        margin: 2px 0 0;
        font-size: 2.1rem;
        font-weight: 900;
        line-height: 1.14;
      }
      .page-hero .sub {
        margin-top: 5px;
        color: var(--muted);
        font-size: .98rem;
      }
      .kpi-strip { display:flex; flex-wrap:wrap; gap:10px; margin-top:16px; }
      .kpi-chip {
        border:1px solid var(--line); border-radius:12px;
        background:rgba(10,16,18,.66); padding:10px 16px; min-width:132px;
        transition:border-color .2s ease, transform .2s ease;
      }
      .kpi-chip:hover { border-color:var(--line-strong); transform:translateY(-1px); }
      .kpi-chip .k { color:var(--muted); font-size:.74rem; font-weight:700; letter-spacing:.03em; }
      .kpi-chip .v {
        font-family:var(--mono); font-variant-numeric:tabular-nums;
        font-size:1.18rem; font-weight:800; margin-top:2px; color:var(--text);
      }
      .kpi-chip .v.pos { color:var(--green); }
      .kpi-chip .v.neg { color:var(--red); }
      .kpi-chip .v.acc { color:var(--cyan); }
      .status-pill {
        display:inline-flex; align-items:center; gap:7px;
        border-radius:999px; padding:6px 14px; font-weight:800; font-size:.85rem;
        border:1px solid;
      }
      .status-pill.live { color:var(--green); border-color:rgba(34,214,138,.45); background:rgba(34,214,138,.08); }
      .status-pill.dead { color:var(--red); border-color:rgba(255,94,122,.45); background:rgba(255,94,122,.08); }
      .status-pill.paper { color:var(--amber); border-color:rgba(244,185,83,.45); background:rgba(244,185,83,.08); }
      .status-pill .led { width:8px; height:8px; border-radius:50%; background:currentColor; box-shadow:0 0 10px currentColor; }
      [data-testid="stMetric"] {
        background: linear-gradient(160deg, var(--panel-2), rgba(9,14,16,.92));
        border: 1px solid var(--line);
        border-radius: var(--radius);
        padding: 14px 16px;
        position:relative; overflow:hidden;
        transition:border-color .2s ease, transform .2s ease, box-shadow .2s ease;
      }
      [data-testid="stMetric"]:hover {
        border-color:var(--line-strong);
        transform:translateY(-2px);
        box-shadow:0 12px 30px rgba(0,0,0,.35);
      }
      [data-testid="stMetric"]::before {
        content:""; position:absolute; inset:0 0 auto; height:2px;
        background:linear-gradient(90deg, var(--green), transparent 70%);
        opacity:.5;
      }
      [data-testid="stMetricLabel"] p {
        color: var(--muted);
        font-size: .86rem;
        font-weight:700;
      }
      [data-testid="stMetricValue"] {
        color: var(--text);
        font-family:var(--mono);
        font-variant-numeric:tabular-nums;
      }
      [data-testid="stMetricDelta"] svg { display:none; }
      .stAlert { direction: rtl; border-radius: 12px; }
      div[data-testid="stDataFrame"] {
        border: 1px solid var(--line);
        border-radius: 12px;
        overflow: hidden;
        box-shadow:0 10px 26px rgba(0,0,0,.25);
      }
      button[kind="primary"], .stButton button { border-radius: 10px; }
      .stTabs [data-baseweb="tab-list"] { gap: 8px; }
      .stTabs [data-baseweb="tab"] {
        border-radius: 10px;
        background: var(--panel);
        border: 1px solid var(--line);
        color: var(--text);
      }
      details summary { border-radius:12px; }
      .agent-grid { display:flex; flex-wrap:wrap; gap:12px; margin-bottom:8px; }
      .agent-card {
        flex:1 1 240px;
        background:linear-gradient(160deg, var(--panel-2), rgba(8,13,15,.94));
        border:1px solid var(--line); border-radius:var(--radius); padding:14px 16px;
        box-shadow:var(--glow-green); position:relative;
        transition:border-color .2s ease, transform .2s ease, box-shadow .2s ease;
      }
      .agent-card:hover {
        border-color:var(--line-strong); transform:translateY(-2px);
        box-shadow:0 14px 32px rgba(0,0,0,.4), var(--glow-green);
      }
      .agent-card .name { font-size:1.0em; font-weight:800; color:var(--text); }
      .agent-card .icon { font-size:1.3em; margin-right:6px; }
      .agent-card .action { color:var(--cyan); font-size:0.82em; margin-top:4px; font-weight:600; }
      .agent-card .detail { color:#b9cac1; font-size:0.86em; margin-top:6px;
        min-height:34px; line-height:1.3; }
      .agent-card .meta { font-size:0.74em; margin-top:8px; color:var(--muted);
        font-family:var(--mono); }
      .agent-card .dot { height:10px; width:10px; border-radius:50%;
        display:inline-block; margin-left:6px; box-shadow:0 0 8px currentColor; }
      .pulse { animation:pulse 1.1s infinite; }
      @keyframes pulse { 0%{opacity:1} 50%{opacity:0.35} 100%{opacity:1} }
      .feed-row { font-family:var(--mono); font-size:0.8em;
        padding:4px 6px; border-bottom:1px solid rgba(140,180,165,.08);
        border-radius:6px; transition:background .15s ease; }
      .feed-row:hover { background:rgba(63,198,255,.05); }
      .perf-panel {
        border:1px solid var(--line); border-radius:var(--radius);
        background:linear-gradient(160deg, var(--panel-2), rgba(8,13,15,.95));
        padding:18px 20px; margin:4px 0 10px;
        box-shadow:0 14px 34px rgba(0,0,0,.3);
      }
      .perf-title { font-weight:900; font-size:1.05rem; color:var(--text); }
      .perf-sub { color:var(--muted); font-size:.82rem; margin-top:2px; }
      .perf-row { display:flex; flex-wrap:wrap; gap:18px; margin-top:14px; align-items:stretch; }
      .perf-cell { flex:1 1 150px; }
      .perf-k { color:var(--muted); font-size:.76rem; font-weight:700; }
      .perf-v { font-family:var(--mono); font-variant-numeric:tabular-nums;
        font-size:1.5rem; font-weight:800; margin-top:3px; }
      .perf-bar-track {
        height:10px; border-radius:999px; background:rgba(140,180,165,.12);
        margin-top:10px; overflow:hidden; position:relative;
      }
      .perf-bar-fill {
        height:100%; border-radius:999px;
        background:linear-gradient(90deg, var(--green), var(--cyan));
        box-shadow:0 0 14px rgba(34,214,138,.5);
        transition:width .6s ease;
      }
      .perf-ladder { display:flex; gap:8px; margin-top:12px; flex-wrap:wrap; }
      .perf-step {
        flex:1 1 110px; border:1px solid var(--line); border-radius:10px;
        padding:8px 10px; text-align:center; font-size:.78rem; color:var(--muted);
        background:rgba(10,16,18,.5);
      }
      .perf-step.on {
        border-color:rgba(34,214,138,.55); color:var(--green);
        background:rgba(34,214,138,.08); font-weight:800;
        box-shadow:0 0 16px rgba(34,214,138,.12);
      }
      .perf-step .x { font-family:var(--mono); font-size:1.05rem; font-weight:800; display:block; }
      .strategy-grid { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:12px; margin:10px 0 4px; }
      .strategy-card {
        min-height:126px; border:1px solid var(--line); border-radius:var(--radius);
        background:linear-gradient(145deg,rgba(19,26,23,.96),rgba(8,12,10,.98));
        padding:14px 14px 12px; position:relative; overflow:hidden;
      }
      .strategy-card::before {
        content:""; position:absolute; inset:0 0 auto; height:3px; background:var(--state);
      }
      .strategy-top { display:flex; justify-content:space-between; gap:10px; align-items:flex-start; }
      .strategy-name { color:var(--text); font-weight:800; font-size:1rem; line-height:1.25; }
      .strategy-icon { font-size:1.35rem; }
      .strategy-state { margin-top:10px; color:var(--state); font-weight:800; font-size:.88rem; }
      .strategy-meta { margin-top:8px; color:var(--muted); font-size:.82rem; line-height:1.35; }
      .level-grid { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:12px; margin:12px 0; }
      .level-card {
        min-height:154px; border:1px solid var(--line); border-radius:var(--radius);
        background:linear-gradient(145deg,rgba(16,21,18,.96),rgba(8,12,10,.98));
        padding:14px; position:relative; overflow:hidden;
      }
      .level-card.current { border-color:rgba(53,194,255,.72); box-shadow:0 0 24px rgba(53,194,255,.10); }
      .level-card::before {
        content:""; position:absolute; inset:0 0 auto; height:3px; background:var(--level);
      }
      .level-eyebrow { color:var(--level); font-size:.75rem; font-weight:900; }
      .level-name { color:var(--text); font-size:1rem; font-weight:850; margin-top:5px; line-height:1.25; }
      .level-state { color:#d6e5dc; font-size:.86rem; font-weight:800; margin-top:10px; }
      .level-meta { color:var(--muted); font-size:.82rem; line-height:1.35; margin-top:7px; }
      .gate-grid { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; margin:8px 0 2px; }
      .gate-row {
        border:1px solid var(--line); border-radius:var(--radius); padding:12px 13px;
        background:rgba(16,21,18,.78); min-height:114px;
      }
      .gate-title { color:var(--text); font-weight:850; font-size:.94rem; line-height:1.25; }
      .gate-status { color:var(--gate); font-weight:900; margin-top:8px; font-size:.84rem; }
      .gate-detail { color:var(--muted); margin-top:7px; font-size:.8rem; line-height:1.35; }
      .lab-grid { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; margin:8px 0 14px; }
      .lab-card {
        border:1px solid var(--line); border-radius:var(--radius); padding:12px 13px;
        background:linear-gradient(145deg,rgba(19,26,23,.92),rgba(8,12,10,.98));
        min-height:116px; position:relative; overflow:hidden;
      }
      .lab-card::before { content:""; position:absolute; inset:0 0 auto; height:3px; background:var(--lab); }
      .lab-name { color:var(--text); font-weight:850; font-size:.95rem; line-height:1.25; }
      .lab-state { color:var(--lab); font-weight:900; margin-top:8px; font-size:.83rem; }
      .lab-detail { color:var(--muted); margin-top:7px; font-size:.8rem; line-height:1.35; }
      .rec-list { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:10px; margin-top:8px; }
      .rec-row {
        border:1px solid var(--line); border-radius:var(--radius); padding:11px 12px;
        background:rgba(16,21,18,.68);
      }
      .rec-title { color:var(--text); font-weight:850; font-size:.92rem; }
      .rec-detail { color:var(--muted); margin-top:6px; font-size:.8rem; line-height:1.35; }
      @media (max-width: 640px) {
        .block-container { padding-left: 1rem; padding-right: 1rem; }
        .page-hero { padding: 18px 16px; }
        .page-hero h1 { font-size: 1.9rem; }
        [data-testid="stMetric"] { padding: 12px; }
        .strategy-grid { grid-template-columns:1fr; }
        .level-grid { grid-template-columns:1fr; }
        .gate-grid { grid-template-columns:1fr; }
        .lab-grid { grid-template-columns:1fr; }
        .rec-list { grid-template-columns:1fr; }
      }
      @media (min-width: 641px) and (max-width: 1100px) {
        .strategy-grid { grid-template-columns:repeat(2,minmax(0,1fr)); }
        .level-grid { grid-template-columns:repeat(2,minmax(0,1fr)); }
        .gate-grid { grid-template-columns:repeat(2,minmax(0,1fr)); }
        .lab-grid { grid-template-columns:repeat(2,minmax(0,1fr)); }
      }
    </style>
    """,
    unsafe_allow_html=True,
)


# ---------------------------------------------------------------------------
# DB connection (cached per session)
# ---------------------------------------------------------------------------

@st.cache_resource
def get_repository():
    from config import config
    from database.repository import TradeRepository
    return TradeRepository(db_path=config.db_path)


repo = get_repository()

# ---------------------------------------------------------------------------
# Helper: color formatter
# ---------------------------------------------------------------------------

def pnl_color(val: float) -> str:
    return "green" if val >= 0 else "red"


def direction_color(direction: str) -> str:
    mapping = {"LONG": "green", "SHORT": "red", "NEUTRAL": "gray"}
    return mapping.get(direction, "gray")


def trend_color(trend: str) -> str:
    mapping = {"uptrend": "green", "downtrend": "red", "sideways": "gray"}
    return mapping.get(trend, "gray")


def colored_badge(text: str, color: str) -> str:
    return (
        f'<span style="background-color:{color};color:white;'
        f'padding:2px 8px;border-radius:4px;font-size:0.85em;">{text}</span>'
    )


def render_inline_html(html: str, height: int) -> None:
    st.iframe(f"data:text/html;charset=utf-8,{quote(html)}", height=height, width="stretch")


def he_side(side: str) -> str:
    return {
        "LONG": "לונג",
        "SHORT": "שורט",
        "NEUTRAL": "נייטרלי",
        "BUY": "קנייה",
        "SELL": "מכירה",
    }.get(str(side or "").upper(), side or "—")


def he_yes_no(value) -> str:
    return "כן" if bool(value) else "לא"


def he_reason(reason: str) -> str:
    return {
        "profit_lock": "נעילת רווח",
        "take_profit": "יעד רווח",
        "take_profit_exchange_reconcile": "יעד רווח בבורסה",
        "scalp_take_profit": "מימוש מהיר",
        "scalp_take_profit_exchange_reconcile": "מימוש מהיר בבורסה",
        "stop_loss": "סטופ",
        "stop_loss_exchange_reconcile": "סטופ בבורסה",
        "stop_loss_db_reconcile": "סטופ מסונכרן",
        "stale_no_move": "אין תנועה",
        "fast_exit_no_move": "יציאה מהירה",
        "KILL_SWITCH": "עצירת חירום",
    }.get(str(reason or ""), reason or "—")


def he_action(action: str) -> str:
    key = str(action or "").upper()
    return {
        "ARMED": "פעיל",
        "OFF": "כבוי",
        "SCAN": "סורק",
        "SCANNING": "סורק",
        "ASSESS": "בודק",
        "EVALUATE": "מעריך",
        "APPROVE": "מאשר",
        "REJECT": "דוחה",
        "ENTRY": "כניסה",
        "EXIT": "יציאה",
        "BOOST": "מגדיל",
        "NORMAL": "רגיל",
        "REDUCE": "מצמצם",
        "RESERVE": "שומר הון",
        "ARMED_TRADE": "נותן לרווח לרוץ",
        "STATE": "מצב",
        "READY": "מוכן",
        "WORKING": "עובד",
        "ACTIVE": "פעיל",
    }.get(key, action or "ממתין")


def he_status(status: str) -> str:
    return {
        "active": "פעיל",
        "working": "עובד",
        "paused": "מושהה",
        "stopped": "עצור",
        "idle": "ממתין",
    }.get(str(status or "").lower(), status or "ממתין")


def fmt_usd(value, decimals: int = 2) -> str:
    val = _safe_float(value, 0.0)
    body = f"-${abs(val):,.{decimals}f}" if val < 0 else f"${val:,.{decimals}f}"
    return f"\u2066{body}\u2069"


def _safe_float(value, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _snapshot_pnl_pct(snapshot: dict) -> float:
    """Normalize legacy/new snapshots to a fraction for Streamlit deltas."""
    stored = _safe_float(snapshot.get("total_pnl_pct"), 0.0)
    total = _safe_float(snapshot.get("total_pnl"), 0.0)
    equity = _safe_float(snapshot.get("equity"), 0.0)
    baseline = equity - total
    if baseline > 0:
        return total / baseline
    if abs(stored) > 1.5:
        return stored / 100.0
    return stored


def _decision_reasons(decision: dict) -> list:
    if not decision:
        return []
    for key in ("hard_blocks_json", "reasons_json"):
        raw = decision.get(key)
        if raw:
            try:
                parsed = json.loads(raw)
                if parsed:
                    return parsed
            except Exception:
                pass
    for key in ("hard_blocks", "reasons"):
        parsed = decision.get(key)
        if parsed:
            return parsed
    return []

# ---------------------------------------------------------------------------
# Agent control-center metadata + helpers
# ---------------------------------------------------------------------------

# Display order + icon + Hebrew label for each agent
AGENT_META = [
    ("System",      "🧠", "מערכת"),
    ("LiveGuard",   "🔐", "נעילת לייב"),
    ("Scanner",     "🔭", "סורק שוק"),
    ("Regime",      "🌐", "משטר שוק"),
    ("Flow",        "🌊", "זרימת שוק"),
    ("News",        "📰", "חדשות/סנטימנט"),
    ("Catalyst",    "🧨", "קטליזטורים"),
    ("Decision",    "⚖️", "ועדת החלטה"),
    ("Capital",     "💸", "הקצאת הון"),
    ("Runner",      "🏁", "רווח רץ"),
    ("Indirect",    "🧩", "אסטרטגיות עקיפות"),
    ("OpportunityRadar", "🧭", "רדאר הזדמנויות"),
    ("StrategyLab", "🧪", "מעבדת אסטרטגיות"),
    ("Model",       "🤖", "מודל ML"),
    ("RiskManager", "🛡️", "ניהול סיכון"),
    ("Execution",   "⚡", "ביצוע"),
    ("Analyzer",    "📚", "לומד"),
]

# status -> (color, pulsing?)
STATUS_STYLE = {
    "active":  ("#00e676", False),
    "working": ("#29b6f6", True),
    "paused":  ("#ffa726", False),
    "stopped": ("#ff1744", True),
    "idle":    ("#607d8b", False),
}


def _time_ago(ts_str: str) -> str:
    """Human 'Xs/Xm ago' from an ISO-8601 UTC timestamp."""
    if not ts_str:
        return "—"
    try:
        ts = datetime.fromisoformat(ts_str)
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        delta = (datetime.now(timezone.utc) - ts).total_seconds()
    except (ValueError, TypeError):
        return "—"
    if delta < 0:
        delta = 0
    if delta < 60:
        return f"לפני {int(delta)} ש׳"
    if delta < 3600:
        return f"לפני {int(delta // 60)} דק׳"
    return f"לפני {int(delta // 3600)} שע׳"


def _agent_is_live(ts_str: str, max_sec: int = 180) -> bool:
    """True if the agent reported within max_sec — i.e. the loop is alive.

    A full HFT scan over the whole universe (training a model per symbol) can
    take ~a minute, so an agent may legitimately go quiet between loops — use a
    generous window so a healthy-but-slow engine still reads as alive.
    """
    try:
        ts = datetime.fromisoformat(ts_str)
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - ts).total_seconds() <= max_sec
    except (ValueError, TypeError):
        return False


# Static CSS/markup for the animated constellation (no f-string → braces stay literal)
_CONSTELLATION_CSS = """
<style>
  .cst-wrap { background:radial-gradient(circle at 50% 45%,#0b1830 0%,#060b14 70%);
    border:1px solid #16263c; border-radius:var(--radius); padding:6px; overflow:hidden; }
  .cst-spin { animation: cst-spin 40s linear infinite; transform-origin:450px 250px; }
  @keyframes cst-spin { to { transform: rotate(360deg); } }
  .cst-ring-on { animation: cst-pulse 1.5s ease-out infinite; }
  @keyframes cst-pulse { 0% { r:30; opacity:.9; } 100% { r:52; opacity:0; } }
  .cst-core { animation: cst-core 2.2s ease-in-out infinite; transform-origin:450px 250px; }
  @keyframes cst-core { 0%,100% { opacity:.5; r:52; } 50% { opacity:1; r:60; } }
  .cst-flow { stroke-dasharray:5 9; animation: cst-dash 1s linear infinite; }
  @keyframes cst-dash { to { stroke-dashoffset:-28; } }
  .cst-label { font:600 14px ui-sans-serif,system-ui; }
  .cst-act { font:700 10px ui-monospace,monospace; letter-spacing:.5px; }
</style>
"""


def render_agent_constellation(summary: dict) -> None:
    """Animated agent network: nodes orbiting a core, with flowing links + pulses."""
    import math

    cx, cy, r = 450, 250, 180
    paths, particles, nodes = [], [], []

    for i, (key, icon, label) in enumerate(AGENT_META):
        ang = math.radians(-90 + i * (360 / len(AGENT_META)))
        x = cx + r * math.cos(ang)
        y = cy + r * math.sin(ang)
        row = summary.get(key)
        status = (row or {}).get("status", "idle")
        if not row or not _agent_is_live(row.get("timestamp", ""), 180):
            status = "idle"
        color, _ = STATUS_STYLE.get(status, STATUS_STYLE["idle"])
        flowing = status in ("active", "working")
        action = he_action((row or {}).get("action") or "ממתין")

        # connection line core→node
        line_cls = "cst-flow" if flowing else ""
        line_op = "0.85" if flowing else "0.15"
        paths.append(
            f'<line x1="{cx}" y1="{cy}" x2="{x:.0f}" y2="{y:.0f}" stroke="{color}" '
            f'stroke-width="2" opacity="{line_op}" class="{line_cls}"/>'
        )
        # a data particle traveling core→node when active
        if flowing:
            dur = 1.6 if status == "working" else 2.4
            particles.append(
                f'<circle r="4.5" fill="{color}">'
                f'<animateMotion dur="{dur}s" repeatCount="indefinite" '
                f'path="M{cx},{cy} L{x:.0f},{y:.0f}"/>'
                f'<animate attributeName="opacity" values="0;1;1;0" dur="{dur}s" repeatCount="indefinite"/>'
                f'</circle>'
            )
        # node
        ring = f'<circle r="30" fill="none" stroke="{color}" stroke-width="2.5" class="cst-ring-on"/>' if flowing else ""
        nodes.append(
            f'<g transform="translate({x:.0f},{y:.0f})">'
            f'{ring}'
            f'<circle r="30" fill="#0a1424" stroke="{color}" stroke-width="2"/>'
            f'<circle r="30" fill="{color}" opacity="0.10"/>'
            f'<text text-anchor="middle" dy="9" font-size="26">{icon}</text>'
            f'<text text-anchor="middle" y="50" class="cst-label" fill="#dce8f7">{label}</text>'
            f'<text text-anchor="middle" y="68" class="cst-act" fill="{color}">{action}</text>'
            f'</g>'
        )

    svg = (
        '<svg viewBox="0 0 900 520" width="100%" style="max-height:520px">'
        '<defs><radialGradient id="cstCore" cx="50%" cy="50%" r="50%">'
        '<stop offset="0%" stop-color="#4fc3f7"/><stop offset="100%" stop-color="#0d3b66"/>'
        '</radialGradient></defs>'
        '<g class="cst-spin">'
        f'<circle cx="{cx}" cy="{cy}" r="205" fill="none" stroke="#1e3350" stroke-width="1.5" stroke-dasharray="3 12"/>'
        f'<circle cx="{cx}" cy="{cy}" r="150" fill="none" stroke="#16273f" stroke-width="1" stroke-dasharray="2 14"/>'
        '</g>'
        + "".join(paths)
        + "".join(particles)
        + f'<circle cx="{cx}" cy="{cy}" r="52" fill="none" stroke="#4fc3f7" stroke-width="2" class="cst-core"/>'
        + f'<circle cx="{cx}" cy="{cy}" r="44" fill="url(#cstCore)"/>'
        + f'<text x="{cx}" y="{cy - 4}" text-anchor="middle" font-size="30">🛰️</text>'
        + f'<text x="{cx}" y="{cy + 22}" text-anchor="middle" class="cst-act" fill="#cdeafe">CORE</text>'
        + "".join(nodes)
        + '</svg>'
    )
    render_inline_html(f'<div class="cst-wrap">{_CONSTELLATION_CSS}{svg}</div>', height=540)


def render_agent_holo_3d(summary: dict) -> None:
    """Three.js 3D agent map for the live control center."""
    import json as _json

    agents = []
    for key, icon, label in AGENT_META:
        row = summary.get(key) or {}
        status = row.get("status", "idle")
        if not row or not _agent_is_live(row.get("timestamp", ""), 180):
            status = "idle"
        color, _ = STATUS_STYLE.get(status, STATUS_STYLE["idle"])
        agents.append({
            "key": key,
            "icon": icon,
            "label": label,
            "status": status,
            "statusLabel": he_status(status),
            "color": color,
            "action": he_action(row.get("action") or "ממתין"),
            "detail": row.get("detail") or "—",
            "ago": _time_ago(row.get("timestamp", "")),
        })

    payload = _json.dumps(agents, ensure_ascii=False)
    html = """
    <div id="agent3d">
      <div class="hud">
        <div class="title">מפת סוכנים חיה</div>
        <div class="sub">סורק, חדשות, זרימת שוק, סיכון וביצוע בזמן אמת</div>
      </div>
      <div id="agentTip" class="tip"></div>
    </div>
    <style>
      #agent3d {
        position: relative; height: 560px; width: 100%; overflow: hidden;
        background: #050806; border: 1px solid #27352d; border-radius: 8px;
      }
      #agent3d canvas { display:block; width:100%; height:100%; }
      #agent3d .hud {
        position:absolute; top:14px; left:16px; z-index:4; pointer-events:none;
        color:#dce8f7; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont;
      }
      #agent3d .title { font-size: 13px; font-weight:800; letter-spacing:.12em; color:#8bd8ff; }
      #agent3d .sub { margin-top:4px; font-size: 14px; color:#b9c8dc; }
      #agent3d .tip {
        position:absolute; right:14px; bottom:14px; z-index:4; max-width: 360px;
        padding:10px 12px; border:1px solid #274764; border-radius:var(--radius);
        background:rgba(5,10,18,.82); color:#dce8f7; font-family:ui-sans-serif,system-ui;
        font-size:13px; line-height:1.35;
      }
    </style>
    <script type="module">
      import * as THREE from "https://unpkg.com/three@0.160.0/build/three.module.js";

      const agents = __DATA__;
      const root = document.getElementById("agent3d");
      const tip = document.getElementById("agentTip");
      const scene = new THREE.Scene();
      scene.fog = new THREE.Fog(0x050806, 9, 22);

      const camera = new THREE.PerspectiveCamera(48, root.clientWidth / root.clientHeight, 0.1, 100);
      camera.position.set(0, 2.6, 11);
      camera.lookAt(0, 0, 0);

      const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      renderer.setSize(root.clientWidth, root.clientHeight);
      root.appendChild(renderer.domElement);

      scene.add(new THREE.AmbientLight(0xffffff, 0.55));
      const keyLight = new THREE.PointLight(0x7fd1ff, 1.8, 30);
      keyLight.position.set(0, 5, 7);
      scene.add(keyLight);
      const fillLight = new THREE.PointLight(0x33ff99, 0.8, 24);
      fillLight.position.set(-5, -2, 6);
      scene.add(fillLight);

      const grid = new THREE.GridHelper(18, 18, 0x1c3852, 0x102136);
      grid.position.y = -2.6;
      grid.material.opacity = 0.35;
      grid.material.transparent = true;
      scene.add(grid);

      const core = new THREE.Mesh(
        new THREE.IcosahedronGeometry(1.05, 2),
        new THREE.MeshStandardMaterial({
          color: 0x1d89ff, emissive: 0x0d3b66, metalness: 0.25, roughness: 0.22
        })
      );
      scene.add(core);

      const coreRing = new THREE.Mesh(
        new THREE.TorusGeometry(1.55, 0.018, 12, 128),
        new THREE.MeshBasicMaterial({ color: 0x7fd1ff, transparent:true, opacity:0.8 })
      );
      coreRing.rotation.x = Math.PI / 2.4;
      scene.add(coreRing);

      function hex(c) {
        const clean = String(c || "#607d8b").replace("#", "");
        return parseInt(clean, 16);
      }
      function labelTexture(agent) {
        const canvas = document.createElement("canvas");
        canvas.width = 512; canvas.height = 192;
        const ctx = canvas.getContext("2d");
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.font = "bold 54px Arial";
        ctx.textAlign = "center";
        ctx.fillStyle = "#f7fbff";
        ctx.fillText(agent.icon, 256, 58);
        ctx.direction = "rtl";
        ctx.font = "700 28px Arial";
        ctx.fillStyle = "#e4eefb";
        ctx.fillText(agent.label, 256, 104);
        ctx.direction = "ltr";
        ctx.font = "700 20px Menlo, monospace";
        ctx.fillStyle = agent.color;
        ctx.fillText(agent.action.slice(0, 24), 256, 136);
        const tex = new THREE.CanvasTexture(canvas);
        tex.colorSpace = THREE.SRGBColorSpace;
        return tex;
      }

      const group = new THREE.Group();
      scene.add(group);
      const nodes = [];
      const linkMaterial = new THREE.LineBasicMaterial({ color: 0x315b82, transparent:true, opacity:0.42 });
      agents.forEach((agent, i) => {
        const a = (i / agents.length) * Math.PI * 2;
        const radius = 4.2 + (i % 2) * 0.85;
        const y = ((i % 3) - 1) * 0.9;
        const pos = new THREE.Vector3(Math.cos(a) * radius, y, Math.sin(a) * radius);

        const active = agent.status === "active" || agent.status === "working";
        const mat = new THREE.MeshStandardMaterial({
          color: hex(agent.color), emissive: hex(agent.color),
          emissiveIntensity: active ? 0.42 : 0.08, roughness: 0.25, metalness: 0.35
        });
        const sphere = new THREE.Mesh(new THREE.SphereGeometry(active ? 0.36 : 0.29, 32, 24), mat);
        sphere.position.copy(pos);
        group.add(sphere);

        const halo = new THREE.Mesh(
          new THREE.TorusGeometry(active ? 0.62 : 0.49, 0.012, 8, 96),
          new THREE.MeshBasicMaterial({ color: hex(agent.color), transparent:true, opacity: active ? 0.85 : 0.26 })
        );
        halo.position.copy(pos);
        halo.lookAt(camera.position);
        group.add(halo);

        const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
          map: labelTexture(agent), transparent:true, depthWrite:false
        }));
        sprite.position.set(pos.x, pos.y + 0.88, pos.z);
        sprite.scale.set(2.4, 0.9, 1);
        group.add(sprite);

        const lineGeo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0,0,0), pos]);
        const line = new THREE.Line(lineGeo, linkMaterial.clone());
        line.material.color.setHex(hex(agent.color));
        line.material.opacity = active ? 0.58 : 0.18;
        group.add(line);

        nodes.push({ sphere, halo, sprite, agent, pos, phase: i * 0.62 });
      });

      tip.innerHTML = "<b>מערכת פעילה</b><br/>" + agents.filter(a => a.status !== "idle").length + " סוכנים מדווחים עכשיו";

      const ray = new THREE.Raycaster();
      const mouse = new THREE.Vector2(10, 10);
      root.addEventListener("mousemove", (ev) => {
        const rect = renderer.domElement.getBoundingClientRect();
        mouse.x = ((ev.clientX - rect.left) / rect.width) * 2 - 1;
        mouse.y = -((ev.clientY - rect.top) / rect.height) * 2 + 1;
      });

      function animate(t) {
        const time = t * 0.001;
        core.rotation.x = time * 0.42;
        core.rotation.y = time * 0.63;
        coreRing.rotation.z = time * 0.7;
        group.rotation.y = Math.sin(time * 0.12) * 0.18 + time * 0.035;

        nodes.forEach(n => {
          const active = n.agent.status === "active" || n.agent.status === "working";
          const pulse = active ? (1 + Math.sin(time * 3 + n.phase) * 0.06) : 1;
          n.sphere.scale.setScalar(pulse);
          n.halo.rotation.z = time + n.phase;
          n.halo.lookAt(camera.position);
          n.sprite.lookAt(camera.position);
        });

        ray.setFromCamera(mouse, camera);
        const hit = ray.intersectObjects(nodes.map(n => n.sphere))[0];
        if (hit) {
          const n = nodes.find(x => x.sphere === hit.object);
          if (n) {
            tip.innerHTML =
              `<b>${n.agent.icon} ${n.agent.label}</b><br/>` +
              `<span style="color:${n.agent.color}">${n.agent.statusLabel}</span> · ${n.agent.ago}<br/>` +
              `${n.agent.detail}`;
          }
        }

        renderer.render(scene, camera);
        requestAnimationFrame(animate);
      }
      requestAnimationFrame(animate);

      const ro = new ResizeObserver(() => {
        camera.aspect = root.clientWidth / root.clientHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(root.clientWidth, root.clientHeight);
      });
      ro.observe(root);
    </script>
    """.replace("__DATA__", payload)

    render_inline_html(html, height=580)


def render_live_status_panel(
    *,
    engine_live: bool,
    open_trades: list,
    recent_decisions: list,
    latest_snap: dict,
    stats: dict,
    config,
) -> None:
    """Compact live state: whether the bot is scanning, holding, or waiting."""
    latest_decision = recent_decisions[0] if recent_decisions else _read_json("data/decision_state.json")
    reasons = _decision_reasons(latest_decision)
    approved = bool(latest_decision.get("approved")) if latest_decision else False
    decision_symbol = latest_decision.get("symbol", "—") if latest_decision else "—"
    decision_side = latest_decision.get("direction", "") if latest_decision else ""
    decision_score = _safe_float(latest_decision.get("adjusted_score"), 0.0) if latest_decision else 0.0
    equity = _safe_float(latest_snap.get("equity"), 0.0)
    realized = _safe_float(stats.get("total_pnl"), 0.0)

    st.markdown("#### מצב מסחר עכשיו")
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        st.metric("מנוע", "פעיל" if engine_live else "לא מדווח")
    with c2:
        st.metric("פוזיציות", len(open_trades))
    with c3:
        st.metric("הון כולל", fmt_usd(equity))
    with c4:
        st.metric("רווח ממומש", fmt_usd(realized))

    if open_trades:
        symbols = ", ".join(t.get("symbol", "") for t in open_trades if t.get("symbol"))
        st.success(f"מחזיק עכשיו: {symbols or len(open_trades)}")
    elif latest_decision:
        label = "אושר לאחרונה" if approved else "ממתין לאישור"
        reason = str(reasons[-1]) if reasons else "הסורק מחכה לציון/קונצנזוס מספיק חזק"
        st.info(
            f"{label}: {decision_symbol} {decision_side} | score={decision_score:.1f} | {reason}"
        )
    else:
        st.info("המנוע סורק את השוק ועדיין לא נרשמה החלטת ועדה.")

    capital = "on" if getattr(config, "capital_allocator_enabled", False) else "off"
    runner = "on" if getattr(config, "trend_runner_enabled", False) else "off"
    capital_he = "פעיל" if capital == "on" else "כבוי"
    runner_he = "פעיל" if runner == "on" else "כבוי"
    st.caption(
        f"מגדיל הון: {capital_he}, עד {getattr(config, 'capital_allocator_size_multiplier', 1.0):.2f}x "
        f"מציון {getattr(config, 'capital_allocator_min_score', 0):.0f} | "
        f"נותן לרווח לרוץ: {runner_he}, מציון {getattr(config, 'trend_runner_min_score', 0):.0f}, "
        f"יעד x{getattr(config, 'trend_runner_tp_multiplier', 1.0):.2f}"
    )


def render_strategy_center(config, open_trades: list, recent_decisions: list) -> None:
    """Show which professional-style automation modules are active right now."""
    open_count = len(open_trades or [])
    last_decision = recent_decisions[0] if recent_decisions else {}
    last_symbol = last_decision.get("symbol") or "—"
    last_score = _safe_float(last_decision.get("adjusted_score"), 0.0)

    def item(icon: str, name: str, active: bool, status: str, meta: str, muted: bool = False) -> str:
        color = "#19c37d" if active else "#f2b84b" if not muted else "#607d8b"
        return (
            f'<div class="strategy-card" style="--state:{color}">'
            f'<div class="strategy-top">'
            f'<div class="strategy-name">{html.escape(name)}</div>'
            f'<div class="strategy-icon">{icon}</div>'
            f'</div>'
            f'<div class="strategy-state">{html.escape(status)}</div>'
            f'<div class="strategy-meta">{html.escape(meta)}</div>'
            f'</div>'
        )

    cards = [
        item(
            "🔭",
            "סורק מהיר",
            bool(getattr(config, "aggressive_hft", False)),
            "פעיל" if getattr(config, "aggressive_hft", False) else "כבוי",
            f"סריקה: {getattr(config, 'scan_top_n', 0)} מטבעות · פתוחות: {open_count}",
        ),
        item(
            "📈",
            "איתותים חיצוניים",
            bool(getattr(config, "tradingview_signals", False)),
            "פעיל" if getattr(config, "tradingview_signals", False) else "כבוי",
            f"איתות חיצוני + ועדת החלטה · אחרון: {last_symbol} {last_score:.0f}",
        ),
        item(
            "🛡️",
            "סטופ ויעד חכמים",
            True,
            "פעיל",
            "סטופ ויעד נשלחים לבורסה לכל כניסה חיה",
        ),
        item(
            "🌊",
            "זרימת פקודות",
            bool(getattr(config, "flow_agent_enabled", False)),
            "פעיל" if getattr(config, "flow_agent_enabled", False) else "כבוי",
            "בודק ריבית פתוחה וקוני/מוכרי שוק",
        ),
        item(
            "💸",
            "הגדלת הון חכמה",
            bool(getattr(config, "capital_allocator_enabled", False)),
            "פעיל" if getattr(config, "capital_allocator_enabled", False) else "כבוי",
            f"עד {getattr(config, 'capital_allocator_size_multiplier', 1.0):.2f}x מציון {getattr(config, 'capital_allocator_min_score', 0):.0f}",
        ),
        item(
            "🏁",
            "לתת לרווח לרוץ",
            bool(getattr(config, "trend_runner_enabled", False)),
            "פעיל" if getattr(config, "trend_runner_enabled", False) else "כבוי",
            f"יעד מורחב x{getattr(config, 'trend_runner_tp_multiplier', 1.0):.2f} לעסקאות חזקות",
        ),
        item(
            "▦",
            "מסחר רשת",
            bool(getattr(config, "indirect_grid_enabled", False)),
            "עקיף פעיל" if getattr(config, "indirect_grid_enabled", False) else "לא פעיל",
            "מזהה שוק מדשדש ומשפיע על ועדת ההחלטה",
        ),
        item(
            "Σ",
            "ממוצע קנייה",
            bool(getattr(config, "indirect_dca_enabled", False)),
            "עקיף פעיל" if getattr(config, "indirect_dca_enabled", False) else "לא פעיל",
            "כניסה מדורגת אחרי pullback, בלי להגדיל פוזיציה מפסידה",
        ),
        item(
            "⇄",
            "ארביטראז׳",
            bool(getattr(config, "indirect_arb_enabled", False)),
            "עקיף פעיל" if getattr(config, "indirect_arb_enabled", False) else "לא פעיל",
            "בודק funding/spread כיתרון החלטה, לא ארביטראז׳ בין בורסות",
        ),
        item("👥", "העתקת עסקאות", False, "לא פעיל", "לא מעתיק סוחרים חיצוניים כרגע", muted=True),
    ]

    st.markdown("#### מרכז אסטרטגיות")
    st.markdown(f'<div class="strategy-grid">{"".join(cards)}</div>', unsafe_allow_html=True)


def render_automation_stack(config) -> None:
    """Map the local system against common retail, open-source and institutional tiers."""

    def level(
        eyebrow: str,
        name: str,
        state: str,
        meta: str,
        color: str,
        current: bool = False,
    ) -> str:
        css = "level-card current" if current else "level-card"
        return (
            f'<div class="{css}" style="--level:{color}">'
            f'<div class="level-eyebrow">{html.escape(eyebrow)}</div>'
            f'<div class="level-name">{html.escape(name)}</div>'
            f'<div class="level-state">{html.escape(state)}</div>'
            f'<div class="level-meta">{html.escape(meta)}</div>'
            f'</div>'
        )

    levels = [
        level(
            "רמה 1",
            "בוטים מוכנים",
            "השראה בלבד",
            "SmartTrade, גריד ו-DCA קיימים אצל שירותי SaaS; כאן הם לא מנהלים את הכסף.",
            "#9fb0a7",
        ),
        level(
            "רמה 2",
            "כלים של Binance",
            "מחובר חלקית",
            "פקודות הגנה נשלחות לבורסה, והמערכת קוראת funding ונתוני פיוצ'רס ציבוריים.",
            "#f2b84b",
        ),
        level(
            "רמה 3",
            "קוד פתוח/ML",
            "הליבה הפעילה",
            "מודל פר-סימבול, סורק מהיר, ועדת החלטה, סנטימנט וניתוח זרימת שוק.",
            "#35c2ff",
            current=True,
        ),
        level(
            "רמה 4",
            "מוסדי/Market Making",
            "מחקר בלבד",
            "רעיונות כמו order-flow ו-runner פעילים; latency מוסדי וקו-לוקיישן לא זמינים מקומית.",
            "#ff5c73",
        ),
    ]

    st.markdown("#### מפת יכולות")
    st.markdown(f'<div class="level-grid">{"".join(levels)}</div>', unsafe_allow_html=True)

    def gate(name: str, status: str, detail: str, color: str) -> str:
        return (
            f'<div class="gate-row" style="--gate:{color}">'
            f'<div class="gate-title">{html.escape(name)}</div>'
            f'<div class="gate-status">{html.escape(status)}</div>'
            f'<div class="gate-detail">{html.escape(detail)}</div>'
            f'</div>'
        )

    capital_status = "פעיל" if getattr(config, "capital_allocator_enabled", False) else "כבוי"
    runner_status = "פעיל" if getattr(config, "trend_runner_enabled", False) else "כבוי"
    flow_status = "פעיל" if getattr(config, "flow_agent_enabled", False) else "כבוי"
    indirect_status = "עקיף פעיל" if getattr(config, "indirect_strategies_enabled", False) else "כבוי"
    gates = [
        gate(
            "למידת ML אדפטיבית",
            "פעיל חלקית",
            "מודל XGBoost/סקור אמינות פר-מטבע; הרחבה עתידית: שמירת איכות אימון לכל סימבול.",
            "#35c2ff",
        ),
        gate(
            "Grid / DCA",
            indirect_status,
            "משפיע על ניקוד וגודל דרך ועדת החלטה; לא פותח פקודות עצמאיות.",
            "#35c2ff" if getattr(config, "indirect_strategies_enabled", False) else "#f2b84b",
        ),
        gate(
            "Arbitrage",
            "עקיף פעיל" if getattr(config, "indirect_arb_enabled", False) else "לא פעיל",
            "בודק funding/spread כיתרון החלטה; לא מבצע ארביטראז׳ בין בורסות.",
            "#35c2ff" if getattr(config, "indirect_arb_enabled", False) else "#607d8b",
        ),
        gate(
            "Copy Trading",
            "לא מחובר",
            "אין תלות בסוחרים חיצוניים; המערכת מקבלת החלטות עצמאיות.",
            "#607d8b",
        ),
        gate(
            "הגדלת הון / Runner",
            f"{capital_status} / {runner_status}",
            "מגדיל רק כשיש ציון וקונצנזוס מספיקים, ונותן לעסקאות חזקות יותר מקום לנשום.",
            "#19c37d",
        ),
        gate(
            "Order Flow",
            flow_status,
            "בודק open interest, יחס קונים/מוכרים ו-crowding לפני החלטות.",
            "#19c37d" if getattr(config, "flow_agent_enabled", False) else "#607d8b",
        ),
    ]
    st.markdown("#### שערים לפני הפעלה חיה")
    st.markdown(f'<div class="gate-grid">{"".join(gates)}</div>', unsafe_allow_html=True)


def render_sentiment_panel() -> None:
    """Market sentiment from the NewsAgent snapshot (Fear & Greed, bias, funding, headlines)."""
    import json
    path = "data/sentiment.json"
    if not os.path.exists(path):
        return
    try:
        with open(path, encoding="utf-8") as f:
            snap = json.load(f)
    except Exception:
        return

    st.markdown("#### 📰 סנטימנט שוק — חי")
    fng = snap.get("fear_greed") or {}
    bias = snap.get("bias") or {}
    c1, c2 = st.columns([1, 1.3])

    with c1:
        val = fng.get("value")
        if val is not None:
            if val <= 25:
                bar = "#ff1744"
            elif val <= 45:
                bar = "#ff9100"
            elif val <= 55:
                bar = "#ffd600"
            elif val <= 75:
                bar = "#9ccc65"
            else:
                bar = "#00e676"
            gauge = go.Figure(go.Indicator(
                mode="gauge+number",
                value=val,
                title={"text": f"Fear & Greed — {fng.get('classification','')}", "font": {"size": 14}},
                gauge={
                    "axis": {"range": [0, 100]},
                    "bar": {"color": bar},
                    "steps": [
                        {"range": [0, 25], "color": "rgba(255,23,68,0.25)"},
                        {"range": [25, 45], "color": "rgba(255,145,0,0.20)"},
                        {"range": [45, 55], "color": "rgba(255,214,0,0.18)"},
                        {"range": [55, 75], "color": "rgba(156,204,101,0.20)"},
                        {"range": [75, 100], "color": "rgba(0,230,118,0.22)"},
                    ],
                },
            ))
            gauge.update_layout(height=220, margin=dict(l=10, r=10, t=40, b=0),
                                paper_bgcolor="rgba(0,0,0,0)", font={"color": "#cdd9e8"})
            st.plotly_chart(gauge, width="stretch")
            st.markdown(f"**הטיית שוק:** {bias.get('label','—')}")
        else:
            st.info("מדד הפחד-וחמדנות לא זמין כרגע.")

    with c2:
        funding = snap.get("funding") or {}
        long_rows = funding.get("crowd_long") or []
        short_rows = funding.get("crowd_short") or []
        if long_rows or short_rows:
            st.caption("מיצוב הקהל לפי funding (Binance) — קיצוניות = סיכון להתהפכות")
            fc1, fc2 = st.columns(2)
            with fc1:
                st.markdown("🟢 **קהל בלונג**")
                for r in long_rows:
                    st.markdown(f"<span style='font-size:0.85em'>{r['symbol']} `{r['funding']*100:+.3f}%`</span>",
                                unsafe_allow_html=True)
            with fc2:
                st.markdown("🔴 **קהל בשורט**")
                for r in short_rows:
                    st.markdown(f"<span style='font-size:0.85em'>{r['symbol']} `{r['funding']*100:+.3f}%`</span>",
                                unsafe_allow_html=True)
        headlines = snap.get("headlines") or []
        if headlines:
            st.markdown("**📈 כותרות אחרונות**")
            for h in headlines[:6]:
                link = h.get("link", "")
                title = h.get("title", "")
                if link:
                    st.markdown(f"- [{title}]({link})")
                else:
                    st.markdown(f"- {title}")


def _read_json(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def render_catalyst_panel() -> None:
    """Symbol-specific catalyst radar: Binance announcements, RSS, listing/delisting."""
    cat = _read_json("data/catalyst_radar.json")
    if not cat:
        return

    summary = cat.get("summary") or {}
    events = cat.get("events") or []
    watchlist = cat.get("watchlist") or []
    updated = str(cat.get("updated_at") or "")

    st.markdown("#### רדאר קטליזטורים — אירועים שיכולים להזיז מטבע")
    c1, c2, c3, c4, c5 = st.columns(5)
    with c1:
        st.metric("אירועים", int(_safe_float(summary.get("events"), 0)))
    with c2:
        st.metric("קריטיים", int(_safe_float(summary.get("critical"), 0)))
    with c3:
        st.metric("חיוביים", int(_safe_float(summary.get("positive"), 0)))
    with c4:
        st.metric("שליליים", int(_safe_float(summary.get("negative"), 0)))
    with c5:
        st.metric("מטבעות", int(_safe_float(summary.get("symbols"), 0)))

    impact_color = {
        "critical": "#ff5e7a",
        "high": "#f4b953",
        "medium": "#35c2ff",
        "low": "#607d8b",
    }
    if watchlist:
        cards = []
        for row in watchlist[:6]:
            score = _safe_float(row.get("score"), 0)
            color = "#22d68a" if score > 0 else "#ff5e7a" if score < 0 else "#607d8b"
            ev = (row.get("events") or [{}])[0]
            cards.append(
                f'<div class="lab-card" style="--lab:{color}">'
                f'<div class="lab-name">{html.escape(str(row.get("symbol", "")))}</div>'
                f'<div class="lab-state">ציון קטליזטור {score:+.1f} · '
                f'{len(row.get("events") or [])} אירועים</div>'
                f'<div class="lab-detail">{html.escape(str(ev.get("title", ""))[:130])}</div>'
                f'</div>'
            )
        st.markdown(f'<div class="lab-grid">{"".join(cards)}</div>', unsafe_allow_html=True)

    rows = []
    for ev in events[:30]:
        symbols = ", ".join(ev.get("symbols") or []) or "שוק כללי"
        kind = str(ev.get("kind") or "neutral")
        impact = str(ev.get("impact") or "low")
        rows.append({
            "השפעה": impact,
            "כיוון": kind,
            "ציון": f"{_safe_float(ev.get('score'), 0):+.1f}",
            "מטבעות": symbols,
            "מקור": ev.get("source", ""),
            "כותרת": ev.get("title", ""),
            "קישור": ev.get("link", ""),
        })
    if rows:
        st.caption(f"עדכון קטליזטורים: {updated[:19] if updated else '—'}")
        st.dataframe(pd.DataFrame(rows), width="stretch", hide_index=True)

        critical_links = [
            ev for ev in events[:12]
            if str(ev.get("impact")) == "critical" and ev.get("link")
        ]
        for ev in critical_links[:3]:
            color = impact_color.get(str(ev.get("impact")), "#607d8b")
            st.markdown(
                colored_badge("אירוע קריטי", color)
                + f" [{html.escape(str(ev.get('title', '')))}]({ev.get('link')})",
                unsafe_allow_html=True,
            )


def render_strategy_lab_panel() -> None:
    """Research/readiness snapshot generated by StrategyLabAgent."""
    lab = _read_json("data/strategy_lab.json")
    model_health = _read_json("data/model_health.json")
    if not lab and not model_health:
        return

    st.markdown("#### מעבדת שדרוגים")
    score = int(_safe_float(lab.get("readiness_score"), 0.0)) if lab else 0
    lookback = int(_safe_float(lab.get("lookback_hours"), 0.0)) if lab else 0
    overall = lab.get("overall") or {}
    model_agg = (model_health.get("aggregate") or lab.get("model_aggregate") or {})

    c1, c2, c3, c4 = st.columns(4)
    with c1:
        st.metric("ציון מוכנות", f"{score}/100")
    with c2:
        st.metric("חלון מחקר", f"{lookback} שעות" if lookback else "—")
    with c3:
        st.metric("PnL מחקר", fmt_usd(overall.get("total_pnl", 0.0)))
    with c4:
        healthy = int(_safe_float(model_agg.get("healthy_symbols"), 0.0))
        trained = int(_safe_float(model_agg.get("trained_symbols"), 0.0))
        st.metric("מודלים בריאים", f"{healthy}/{trained}")

    def module_color(state: str) -> str:
        return {
            "LIVE": "#19c37d",
            "WARMING": "#35c2ff",
            "PARTIAL": "#f2b84b",
            "INDIRECT": "#35c2ff",
            "RESEARCH": "#f2b84b",
            "BLOCKED": "#ff5c73",
            "OFF": "#607d8b",
        }.get(str(state or "").upper(), "#607d8b")

    modules = lab.get("modules") or []
    if modules:
        cards = []
        for mod in modules[:9]:
            color = module_color(mod.get("state", ""))
            cards.append(
                f'<div class="lab-card" style="--lab:{color}">'
                f'<div class="lab-name">{html.escape(str(mod.get("name", "")))}</div>'
                f'<div class="lab-state">{html.escape(str(mod.get("status", "")))} · '
                f'{int(_safe_float(mod.get("score"), 0))}/100</div>'
                f'<div class="lab-detail">{html.escape(str(mod.get("detail", "")))}</div>'
                f'</div>'
            )
        st.markdown(f'<div class="lab-grid">{"".join(cards)}</div>', unsafe_allow_html=True)

    recs = lab.get("recommendations") or []
    if recs:
        colors = {"ready": "#19c37d", "risk": "#ff5c73", "research": "#f2b84b"}
        rows = []
        for rec in recs:
            color = colors.get(str(rec.get("level", "")).lower(), "#607d8b")
            rows.append(
                f'<div class="rec-row" style="border-color:{color}66">'
                f'<div class="rec-title">{html.escape(str(rec.get("title", "")))}</div>'
                f'<div class="rec-detail">{html.escape(str(rec.get("detail", "")))}</div>'
                f'</div>'
            )
        st.markdown("##### המלצות חיות")
        st.markdown(f'<div class="rec-list">{"".join(rows)}</div>', unsafe_allow_html=True)

    worst = lab.get("worst_symbols") or []
    if worst:
        rows = []
        for row in worst[:5]:
            rows.append({
                "מטבע": row.get("symbol", ""),
                "עסקאות": row.get("trades", 0),
                "Win": f"{_safe_float(row.get('win_rate')):.0%}",
                "PnL": f"{_safe_float(row.get('total_pnl')):+.2f}",
            })
        st.caption("מטבעות חלשים בחלון המחקר")
        st.dataframe(pd.DataFrame(rows), width="stretch", hide_index=True)


def render_opportunity_radar_panel() -> None:
    """Multi-product Binance opportunity snapshot."""
    radar = _read_json("data/opportunity_radar.json")
    if not radar:
        return

    st.markdown("#### רדאר הזדמנויות Binance")
    summary = radar.get("summary") or {}
    products = radar.get("products") or []
    updated = radar.get("updated_at", "")

    c1, c2, c3, c4 = st.columns(4)
    with c1:
        st.metric("אפיקים במעקב", int(_safe_float(summary.get("products_watched"), 0)))
    with c2:
        st.metric("אפיקים חמים", int(_safe_float(summary.get("watch_ready"), 0)))
    with c3:
        st.metric("Spot", int(_safe_float(summary.get("spot_symbols"), 0)))
    with c4:
        st.metric("Futures", int(_safe_float(summary.get("futures_symbols"), 0)))

    state_he = {
        "WATCH": "במעקב",
        "MANUAL_READY": "ידני מוכן",
        "MANUAL": "ידני",
        "WAIT": "ממתין",
    }
    state_color = {
        "WATCH": "#35c2ff",
        "MANUAL_READY": "#19c37d",
        "MANUAL": "#f2b84b",
        "WAIT": "#607d8b",
    }
    if products:
        cards = []
        for prod in products:
            state = str(prod.get("state", "WAIT")).upper()
            color = state_color.get(state, "#607d8b")
            cards.append(
                f'<div class="lab-card" style="--lab:{color}">'
                f'<div class="lab-name">{html.escape(str(prod.get("name", "")))}</div>'
                f'<div class="lab-state">{html.escape(state_he.get(state, state))} · '
                f'{_safe_float(prod.get("score"), 0):.0f}/100 · '
                f'{html.escape(str(prod.get("risk", "")))}</div>'
                f'<div class="lab-detail">{html.escape(str(prod.get("detail", "")))}</div>'
                f'<div class="lab-detail">{html.escape(str(prod.get("action", "")))}</div>'
                f'</div>'
            )
        st.markdown(f'<div class="lab-grid">{"".join(cards)}</div>', unsafe_allow_html=True)

    rows = []
    for prod in products:
        for c in (prod.get("candidates") or [])[:5]:
            if "on_binance" in c:
                to_scanner = "✓ מוזרם לסורק" if c.get("on_binance") else "צפייה בלבד"
            else:
                to_scanner = ""
            rows.append({
                "אפיק": prod.get("name", ""),
                "מטבע": c.get("symbol", ""),
                "שוק": c.get("market", ""),
                "רעיון": c.get("idea", ""),
                "שינוי 24h": f"{_safe_float(c.get('change_pct'), 0):+.2f}%",
                "טווח 24h": f"{_safe_float(c.get('range_pct'), 0):.2f}%",
                "Funding": f"{_safe_float(c.get('funding_pct'), 0):+.4f}%",
                "נפח": f"{_safe_float(c.get('quote_volume'), 0)/1_000_000:.1f}M",
                "בביננס": to_scanner,
            })
    if rows:
        st.caption(f"עדכון רדאר: {updated[:19] if updated else '—'}")
        st.dataframe(pd.DataFrame(rows), width="stretch", hide_index=True)

    if not bool(radar.get("auto_entry_enabled")):
        st.caption(radar.get("auto_entry_reason", "כניסה אוטומטית לא פעילה לאפיקים אלה."))


def render_intelligence_panels() -> None:
    """Live guard, market regime and latest committee decision."""
    live = _read_json("data/live_guard.json")
    regime = _read_json("data/market_regime.json")
    decision = _read_json("data/decision_state.json")
    if not (live or regime or decision):
        return

    st.markdown("#### 🧭 שכבת החלטה ובטיחות")
    c1, c2, c3 = st.columns(3)
    with c1:
        ready = live.get("ready")
        mode = live.get("mode", "—")
        color = "green" if ready else "red"
        st.markdown(colored_badge(f"שומר לייב: {mode}", color), unsafe_allow_html=True)
        st.caption(live.get("reason", "אין נתונים"))
    with c2:
        if regime:
            risk = regime.get("risk_state", "—")
            rcolor = "green" if risk == "NORMAL" else "orange" if risk == "HIGH_VOL" else "red"
            st.markdown(colored_badge(f"משטר שוק: {risk}", rcolor), unsafe_allow_html=True)
            st.caption(regime.get("detail", "—"))
        else:
            st.caption("משטר שוק טרם זמין")
    with c3:
        if decision:
            approved = bool(decision.get("approved"))
            dcolor = "green" if approved else "orange"
            label = "מאושר" if approved else "נדחה"
            st.markdown(colored_badge(f"החלטה: {label}", dcolor), unsafe_allow_html=True)
            st.caption(
                f"{decision.get('symbol','')} {he_side(decision.get('direction',''))} | "
                f"הסכמה={decision.get('consensus',0):.0%} | "
                f"ציון={decision.get('adjusted_score',0):.1f} | "
                f"גודל={decision.get('size_multiplier',1):.2f}"
            )
            reasons = decision.get("hard_blocks") or decision.get("reasons") or []
            if reasons:
                st.caption(str(reasons[-1]))
        else:
            st.caption("אין עדיין החלטות ועדה")


def render_tradingview(open_positions: list) -> None:
    """Embed a live TradingView chart + technical-analysis rating for a chosen symbol."""
    st.markdown("#### 📈 TradingView — גרף וניתוח טכני חי")
    common = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT",
              "DOGEUSDT", "ADAUSDT", "AVAXUSDT", "LINKUSDT"]
    # surface the bot's open positions first
    for t in (open_positions or []):
        s = (t.get("symbol") or "").upper()
        if s and s not in common:
            common.insert(0, s)
    sym = st.selectbox("מטבע לניתוח", common, index=0, key="tv_symbol")
    tv_sym = f"BINANCE:{sym}.P"

    chart_html = """
    <div class="tradingview-widget-container" style="height:500px;">
      <div id="tvchart" style="height:100%;width:100%;"></div>
      <script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
      <script type="text/javascript">
      new TradingView.widget({
        "autosize": true, "symbol": "__SYM__", "interval": "1",
        "timezone": "Asia/Jerusalem", "theme": "dark", "style": "1",
        "locale": "he_IL", "enable_publishing": false,
        "allow_symbol_change": true, "hide_side_toolbar": false,
        "studies": ["RSI@tv-basicstudies","MASimple@tv-basicstudies"],
        "container_id": "tvchart"
      });
      </script>
    </div>
    """.replace("__SYM__", tv_sym)

    ta_html = """
    <div class="tradingview-widget-container">
      <div class="tradingview-widget-container__widget"></div>
      <script type="text/javascript"
        src="https://s3.tradingview.com/external-embedding/embed-widget-technical-analysis.js" async>
      {"interval":"15m","width":"100%","isTransparent":true,"height":480,
       "symbol":"__SYM__","showIntervalTabs":true,"displayMode":"single",
       "locale":"he_IL","colorTheme":"dark"}
      </script>
    </div>
    """.replace("__SYM__", tv_sym)

    col1, col2 = st.columns([2, 1])
    with col1:
        render_inline_html(chart_html, height=520)
    with col2:
        render_inline_html(ta_html, height=520)

# ---------------------------------------------------------------------------
# Load data from DB
# ---------------------------------------------------------------------------

def load_data():
    open_trades    = repo.get_open_trades()
    trade_history  = repo.get_trade_history(limit=200)
    recent_signals = repo.get_recent_signals(limit=50)
    snapshots      = repo.get_portfolio_snapshots(limit=200)
    events         = repo.get_recent_events(limit=20)
    stats          = repo.get_performance_stats()
    try:
        recent_decisions = repo.get_recent_decisions(limit=30)
    except Exception:
        recent_decisions = []
    return open_trades, trade_history, recent_signals, snapshots, events, stats, recent_decisions


open_trades, trade_history, recent_signals, snapshots, events, stats, recent_decisions = load_data()

# Agent control-center data (latest-per-agent + live feed)
try:
    agent_summary = {row["agent"]: row for row in repo.get_agent_status_summary()}
    agent_feed = repo.get_recent_agent_activity(limit=30)
except Exception:
    agent_summary, agent_feed = {}, []

# ---------------------------------------------------------------------------
# 🔊 Sound alert — plays a beep when a new trade closes (compared to last refresh)
# ---------------------------------------------------------------------------
_SOUND_KEY = "last_trade_count"
current_trade_count = len(trade_history)
prev_trade_count = st.session_state.get(_SOUND_KEY, current_trade_count)

if current_trade_count > prev_trade_count:
    # New trade closed since last refresh — play loud beep
    render_inline_html("""
    <script>
    (function() {
        var ctx = new (window.AudioContext || window.webkitAudioContext)();
        function beep(freq, dur, vol, delay) {
            setTimeout(function() {
                var osc = ctx.createOscillator();
                var gain = ctx.createGain();
                osc.connect(gain);
                gain.connect(ctx.destination);
                gain.gain.setValueAtTime(vol, ctx.currentTime);
                gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + dur);
                osc.frequency.setValueAtTime(freq, ctx.currentTime);
                osc.type = 'sine';
                osc.start(ctx.currentTime);
                osc.stop(ctx.currentTime + dur);
            }, delay);
        }
        beep(880, 0.3, 1.5, 0);
        beep(660, 0.3, 1.5, 200);
        beep(880, 0.5, 1.5, 400);
    })();
    </script>
    """, height=1)

st.session_state[_SOUND_KEY] = current_trade_count

# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------
with st.sidebar:
    st.title("בקרה")

    from config import config
    mode_color = "orange" if config.paper_trading else "red"
    mode_label = "נייר" if config.paper_trading else "חי"
    st.markdown(
        colored_badge(f"מצב: {mode_label}", mode_color),
        unsafe_allow_html=True,
    )

    st.markdown("---")
    st.subheader("הגדרות מסחר")
    if config.aggressive_hft:
        st.write("**סוג פעולה:** HFT")
        st.write(f"**סריקה:** {config.scan_top_n} מטבעות")
        st.write(f"**טווח נרות:** {config.hft_timeframe}")
        st.write(f"**ציון כניסה:** {config.score_entry:.0f}")
        st.write(f"**יציאה מהירה:** {config.fast_exit_seconds:.0f} שניות")
        st.write(f"**ספרד מקסימלי:** {config.max_spread_pct*100:.2f}%")
        st.write(f"**פוזיציות מקסימום:** {config.hft_max_open_positions}")
    else:
        st.write(f"**מטבעות:** {', '.join(config.symbols)}")
        st.write(f"**טווח נרות:** {config.timeframe}")
        st.write(f"**ביטחון:** {config.confidence_threshold:.0%}")
        st.write(f"**פוזיציות מקסימום:** {config.max_open_positions}")
    st.write(f"**מינוף:** {config.leverage}x")
    st.write(f"**סיכון לעסקה:** {config.max_risk_pct:.1%}")
    st.write(f"**ירידה מקסימלית:** {config.max_drawdown_pct:.0%}")
    st.write(f"**סטופ נגרר:** {config.hft_trailing_pct if config.aggressive_hft else config.trailing_stop_pct:.1%}")

    st.markdown("---")
    st.subheader("ביצועים")
    if stats:
        st.metric("עסקאות סגורות", stats.get("total_trades", 0))
        wr = stats.get("win_rate", 0.0)
        st.metric("אחוז הצלחה", f"{wr:.1%}")
        total_realized = stats.get("total_pnl", 0.0)
        pnl_color_str = "normal" if total_realized >= 0 else "inverse"
        st.metric("רווח ממומש", fmt_usd(total_realized))
        sharpe = stats.get("sharpe_ratio", 0.0)
        st.metric("שארפ", f"{sharpe:.2f}")
        max_dd_abs = _safe_float(stats.get("max_drawdown_abs"), 0.0)
        max_dd_pct = min(max(_safe_float(stats.get("max_drawdown"), 0.0), 0.0), 1.0)
        st.metric("ירידה מקסימלית", fmt_usd(max_dd_abs), delta=f"{max_dd_pct:.1%}")

    st.markdown("---")
    st.caption(f"עדכון אחרון: {datetime.now(timezone.utc).strftime('%H:%M:%S UTC')}")

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
def _perf_snapshot_24h() -> dict:
    """Profit factor, win rate and the escalator tier for the last 24h."""
    out = {"pf": 0.0, "wr": 0.0, "trades": 0, "mult": 1.0, "pnl": 0.0}
    try:
        s = repo.get_overall_recent_stats(hours_back=24)
        out["trades"] = int(s.get("total_trades", 0) or 0)
        out["wr"] = _safe_float(s.get("win_rate"), 0.0)
        out["pnl"] = _safe_float(s.get("total_pnl"), 0.0)
        gp = _safe_float(s.get("gross_profit"), 0.0)
        gl = abs(_safe_float(s.get("gross_loss"), 0.0))
        out["pf"] = gp / gl if gl > 0 else (2.0 if gp > 0 else 0.0)
        if out["trades"] >= 20:
            if out["pf"] >= 1.5 and out["wr"] >= 0.50:
                out["mult"] = 1.5
            elif out["pf"] >= 1.2 and out["wr"] >= 0.45:
                out["mult"] = 1.25
            elif out["pf"] < 0.8:
                out["mult"] = 0.7
    except Exception:
        pass
    return out


_hero_snap = snapshots[-1] if snapshots else {}
_hero_equity = _safe_float(_hero_snap.get("equity"), 0.0)
_hero_unreal = _safe_float(_hero_snap.get("unrealized_pnl"), 0.0)
_perf24 = _perf_snapshot_24h()
_engine_live_hero = any(_agent_is_live(r.get("timestamp", "")) for r in agent_summary.values())

_mode_pill = (
    '<span class="status-pill paper"><span class="led"></span>מסחר נייר</span>'
    if config.paper_trading
    else '<span class="status-pill live"><span class="led"></span>מסחר חי</span>'
)
_engine_pill = (
    '<span class="status-pill live"><span class="led"></span>מנוע פעיל</span>'
    if _engine_live_hero
    else '<span class="status-pill dead"><span class="led"></span>מנוע מושבת</span>'
)


def _kpi(label: str, value: str, cls: str = "") -> str:
    return (
        f'<div class="kpi-chip"><div class="k">{label}</div>'
        f'<div class="v {cls}">{value}</div></div>'
    )


_pnl24_cls = "pos" if _perf24["pnl"] >= 0 else "neg"
_pf_cls = "pos" if _perf24["pf"] >= 1.2 else ("neg" if _perf24["pf"] and _perf24["pf"] < 0.8 else "acc")
st.markdown(
    f"""
    <div class="page-hero">
      <div style="display:flex; justify-content:space-between; flex-wrap:wrap; gap:12px; align-items:flex-start;">
        <div>
          <div class="kicker">BINANCE FUTURES · חדר מסחר</div>
          <h1>מערכת מסחר חיה</h1>
          <div class="sub">סוכנים חכמים · סריקה רב-שוקית · ניהול סיכון · הגנה בבורסה</div>
        </div>
        <div style="display:flex; gap:8px; flex-wrap:wrap;">{_mode_pill}{_engine_pill}</div>
      </div>
      <div class="kpi-strip">
        {_kpi("הון כולל", fmt_usd(_hero_equity))}
        {_kpi("רווח 24 שעות", fmt_usd(_perf24["pnl"]), _pnl24_cls)}
        {_kpi("רווח פתוח", fmt_usd(_hero_unreal), "pos" if _hero_unreal >= 0 else "neg")}
        {_kpi("Profit Factor", f"{_perf24['pf']:.2f}", _pf_cls)}
        {_kpi("מכפיל ביצועים", f"×{_perf24['mult']:.2f}", "acc")}
        {_kpi("פוזיציות", f"{len(open_trades)}/{config.hft_max_open_positions}")}
      </div>
    </div>
    """,
    unsafe_allow_html=True,
)

# ---------------------------------------------------------------------------
# Section 0: Agent Control Center — live multi-agent activity
# ---------------------------------------------------------------------------
st.subheader("🛰️ מרכז שליטה — סוכנים פעילים")

# Is the engine alive? (any agent reported recently)
_engine_live = any(
    _agent_is_live(r.get("timestamp", "")) for r in agent_summary.values()
)
if agent_summary:
    live_badge = ("🟢 מנוע פעיל" if _engine_live else "🔴 מנוע מושבת")
    live_color = "green" if _engine_live else "darkred"
    st.markdown(colored_badge(live_badge, live_color), unsafe_allow_html=True)
else:
    st.info("עדיין אין פעילות סוכנים. הרץ את `main.py` — הכרטיסים יתחילו לזוז ברגע שהלולאה עולה.")

# Compact live status: scanning, waiting, holding, and smart sizing state
_latest_snap_for_status = snapshots[-1] if snapshots else {}
render_live_status_panel(
    engine_live=_engine_live,
    open_trades=open_trades,
    recent_decisions=recent_decisions,
    latest_snap=_latest_snap_for_status,
    stats=stats,
    config=config,
)

render_strategy_center(config, open_trades, recent_decisions)
render_strategy_lab_panel()
render_opportunity_radar_panel()
render_catalyst_panel()
render_automation_stack(config)

# 3D agent map, plus the old SVG map as a compact fallback
render_agent_holo_3d(agent_summary)
with st.expander("מפת סוכנים דו-ממדית", expanded=False):
    render_agent_constellation(agent_summary)

# Live market sentiment (Fear & Greed, funding, headlines) from the NewsAgent
render_sentiment_panel()

# Live guard + market regime + latest committee decision
render_intelligence_panels()

# Live TradingView chart + technical-analysis rating
render_tradingview(open_trades)

# Agent cards grid
cards_html = ['<div class="agent-grid">']
for agent_key, icon, label in AGENT_META:
    row = agent_summary.get(agent_key)
    if row:
        status = row.get("status", "idle")
        # An agent that hasn't reported recently is shown as idle regardless
        if not _agent_is_live(row.get("timestamp", ""), max_sec=180):
            status = "idle"
        color, pulsing = STATUS_STYLE.get(status, STATUS_STYLE["idle"])
        action = he_action(row.get("action") or "")
        detail = row.get("detail") or "—"
        count = row.get("action_count", 0)
        ago = _time_ago(row.get("timestamp", ""))
        loop = row.get("loop_count")
        loop_str = f" · לולאה #{loop}" if loop is not None else ""
    else:
        color, pulsing = STATUS_STYLE["idle"]
        action, detail, count, ago, loop_str = "ממתין", "טרם דיווח", 0, "—", ""

    dot_cls = "dot pulse" if pulsing else "dot"
    cards_html.append(
        f'<div class="agent-card">'
        f'<div class="name"><span class="icon">{icon}</span>{label}'
        f'<span class="{dot_cls}" style="color:{color}"></span></div>'
        f'<div class="action">{action}</div>'
        f'<div class="detail">{detail}</div>'
        f'<div class="meta">{ago} · {count} פעולות{loop_str}</div>'
        f'</div>'
    )
cards_html.append("</div>")
st.markdown("".join(cards_html), unsafe_allow_html=True)

# Live activity feed
with st.expander("📡 זרם פעילות חי (30 אחרונות)", expanded=True):
    if agent_feed:
        _sev_color = {"ERROR": "#ff5252", "WARNING": "#ffb300", "INFO": "#7fd1ff", "DEBUG": "#78909c"}
        _icons = {k: v for k, v, _ in AGENT_META}
        feed_html = []
        for r in agent_feed:
            c = _sev_color.get(r.get("severity", "INFO"), "#7fd1ff")
            ic = _icons.get(r.get("agent", ""), "•")
            ago = _time_ago(r.get("timestamp", ""))
            detail = r.get("detail") or r.get("action", "")
            sym = f' <b>{r.get("symbol")}</b>' if r.get("symbol") else ""
            feed_html.append(
                f'<div class="feed-row">'
                f'<span style="color:#6b7d96">{ago:>10}</span> &nbsp; '
                f'{ic} <span style="color:{c}">{r.get("agent","")}</span>{sym} &nbsp; '
                f'<span style="color:#cdd9e8">{detail}</span>'
                f'</div>'
            )
        st.markdown("".join(feed_html), unsafe_allow_html=True)
    else:
        st.caption("אין עדיין אירועים.")

with st.expander("⚖️ החלטות ועדה אחרונות", expanded=False):
    if recent_decisions:
        rows = []
        for d in recent_decisions:
            try:
                reasons = json.loads(d.get("hard_blocks_json") or "[]") or json.loads(d.get("reasons_json") or "[]")
            except Exception:
                reasons = []
            rows.append({
                "זמן": d.get("created_at", "")[11:19],
                "מטבע": d.get("symbol", ""),
                "כיוון": he_side(d.get("direction", "")),
                "אושר": he_yes_no(d.get("approved")),
                "ציון": f"{d.get('adjusted_score', 0):.1f}",
                "הסכמה": f"{d.get('consensus', 0):.0%}",
                "גודל": f"{d.get('size_multiplier', 1):.2f}",
                "סיבה": reasons[-1] if reasons else "",
            })
        st.dataframe(pd.DataFrame(rows), width="stretch", hide_index=True)
    else:
        st.caption("אין החלטות ועדה עדיין.")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 1: Portfolio Metrics Row
# ---------------------------------------------------------------------------
st.subheader("סקירת תיק")

# Derive metrics from latest snapshot
latest_snap = snapshots[-1] if snapshots else {}
balance      = latest_snap.get("balance", config.paper_initial_balance)
equity       = latest_snap.get("equity", config.paper_initial_balance)
total_pnl    = latest_snap.get("total_pnl", 0.0)
total_pnl_pct = _snapshot_pnl_pct(latest_snap)
unrealized   = latest_snap.get("unrealized_pnl", 0.0)
realized_pnl = stats.get("total_pnl", 0.0)
n_positions  = latest_snap.get("open_positions", len(open_trades))
win_rate     = latest_snap.get("win_rate", stats.get("win_rate", 0.0))
if win_rate > 1:  # some snapshots store win_rate as a percent (e.g. 46.0) — normalize to fraction
    win_rate = win_rate / 100.0

m1, m2, m3, m4 = st.columns(4)
with m1:
    st.metric("יתרת ארנק", fmt_usd(balance))
with m2:
    st.metric("הון כולל", fmt_usd(equity),
              delta=f"{total_pnl_pct:.2%}",
              delta_color="normal" if total_pnl >= 0 else "inverse")
with m3:
    st.metric("פוזיציות פתוחות", n_positions)
with m4:
    st.metric("אחוז הצלחה", f"{win_rate:.1%}")

# P&L breakdown row
p1, p2, p3 = st.columns(3)
with p1:
    r_color = "normal" if realized_pnl >= 0 else "inverse"
    st.metric("רווח ממומש", fmt_usd(realized_pnl), delta_color=r_color)
with p2:
    u_color = "normal" if unrealized >= 0 else "inverse"
    st.metric("רווח פתוח", fmt_usd(unrealized), delta_color=u_color)
with p3:
    combined = realized_pnl + unrealized
    c_color = "normal" if combined >= 0 else "inverse"
    st.metric("רווח כולל", fmt_usd(combined),
              delta=f"{total_pnl_pct:.2%}",
              delta_color=c_color)

# ---------------------------------------------------------------------------
# Section 1b: Performance engine — earned-aggression escalator + daily PnL
# ---------------------------------------------------------------------------
_lad = _perf24
_steps = [
    ("0.7", "מדמם", _lad["mult"] == 0.7),
    ("1.0", "ניטרלי", _lad["mult"] == 1.0),
    ("1.25", "מוכח", _lad["mult"] == 1.25),
    ("1.5", "רווחי חזק", _lad["mult"] == 1.5),
]
_steps_html = "".join(
    f'<div class="perf-step{" on" if on else ""}"><span class="x">×{x}</span>{name}</div>'
    for x, name, on in _steps
)
# progress toward PF 1.5 (the top tier), clamped for display
_pf_progress = max(0.0, min(1.0, _lad["pf"] / 1.5))
_trades_note = (
    f'{_lad["trades"]} עסקאות ב-24 שעות'
    if _lad["trades"] >= 20
    else f'{_lad["trades"]}/20 עסקאות — המדרגה תופעל כשיהיו מספיק נתונים'
)
st.markdown(
    f"""
    <div class="perf-panel">
      <div class="perf-title">⚡ מנוע ביצועים — אגרסיביות מורווחת</div>
      <div class="perf-sub">הסייזינג עולה אוטומטית ברגע שהמערכת מוכיחה רווחיות (Profit Factor), ויורד כשהיא מדממת · {_trades_note}</div>
      <div class="perf-row">
        <div class="perf-cell">
          <div class="perf-k">Profit Factor (24h)</div>
          <div class="perf-v" style="color:{'var(--green)' if _lad['pf'] >= 1.2 else ('var(--red)' if _lad['pf'] and _lad['pf'] < 0.8 else 'var(--cyan)')}">{_lad['pf']:.2f}</div>
          <div class="perf-bar-track"><div class="perf-bar-fill" style="width:{_pf_progress*100:.0f}%"></div></div>
        </div>
        <div class="perf-cell">
          <div class="perf-k">אחוז הצלחה (24h)</div>
          <div class="perf-v">{_lad['wr']:.0%}</div>
        </div>
        <div class="perf-cell">
          <div class="perf-k">מכפיל סייזינג פעיל</div>
          <div class="perf-v" style="color:var(--cyan)">×{_lad['mult']:.2f}</div>
        </div>
      </div>
      <div class="perf-ladder">{_steps_html}</div>
    </div>
    """,
    unsafe_allow_html=True,
)

# Daily PnL bars — where the money actually went, day by day
try:
    _daily_rows = repo._get_conn().execute(
        """
        SELECT substr(closed_at, 1, 10) AS day, ROUND(SUM(pnl), 4) AS pnl, COUNT(*) AS n
        FROM trades
        WHERE status = 'closed' AND pnl IS NOT NULL AND closed_at IS NOT NULL
        GROUP BY day ORDER BY day DESC LIMIT 14
        """
    ).fetchall()
    _daily = [dict(r) for r in _daily_rows][::-1]
except Exception:
    _daily = []
if _daily:
    _dfig = go.Figure(go.Bar(
        x=[d["day"] for d in _daily],
        y=[d["pnl"] for d in _daily],
        marker_color=["#22d68a" if d["pnl"] >= 0 else "#ff5e7a" for d in _daily],
        marker_line_width=0,
        text=[f'{d["pnl"]:+.2f}' for d in _daily],
        textposition="outside",
        textfont=dict(family="JetBrains Mono", size=11),
        hovertemplate="%{x}<br>%{y:+.2f} USDT<extra></extra>",
    ))
    _dfig.update_layout(
        title=dict(text="רווח/הפסד יומי (14 ימים)", font=dict(family="Heebo", size=15, color="#edf6f1")),
        height=240,
        margin=dict(l=0, r=0, t=44, b=0),
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
        font=dict(family="Heebo", color="#8fa39b"),
        xaxis=dict(showgrid=False, type="category", tickfont=dict(family="JetBrains Mono", size=11)),
        yaxis=dict(gridcolor="rgba(140,180,165,.1)", zerolinecolor="rgba(140,180,165,.3)"),
        showlegend=False,
    )
    st.plotly_chart(_dfig, width="stretch")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 2: Open Positions + Recent Signals (two columns)
# ---------------------------------------------------------------------------
col_left, col_right = st.columns(2)

with col_left:
    st.subheader(f"פוזיציות פתוחות ({len(open_trades)})")
    if open_trades:
        pos_rows = []
        for t in open_trades:
            entry_p = t.get("entry_price", 0) or 0
            pos_rows.append({
                "מטבע": t.get("symbol", ""),
                "כיוון": he_side(t.get("side", "")),
                "כניסה": fmt_usd(entry_p, 4) if entry_p > 0 else "—",
                "כמות": f"{t.get('quantity', 0):.4f}",
                "סטופ": fmt_usd(t.get("sl_price"), 4) if t.get("sl_price") else "—",
                "יעד": fmt_usd(t.get("tp_price"), 4) if t.get("tp_price") else "—",
                "ציון": (
                    (f"{t['confidence']:.0f}" if (t.get('confidence') or 0) > 1
                     else f"{t.get('confidence', 0):.0%}")
                    if t.get("confidence") else "—"
                ),
                "נפתחה": t.get("opened_at", "")[:16] if t.get("opened_at") else "",
            })
        pos_df = pd.DataFrame(pos_rows)

        def style_side(val):
            color = "color: #19c37d" if val == "לונג" else "color: #ff5c73" if val == "שורט" else ""
            return color

        styled_pos = pos_df.style.map(style_side, subset=["כיוון"])
        st.dataframe(styled_pos, width="stretch", hide_index=True)
    else:
        st.info("אין פוזיציות פתוחות כרגע")

with col_right:
    st.subheader("איתותים אחרונים")
    if recent_signals:
        sig_rows = []
        for s in recent_signals[:15]:
            sig_rows.append({
                "מטבע": s.get("symbol", ""),
                "כיוון": he_side(s.get("direction", "")),
                "ביטחון": f"{s.get('confidence', 0):.1%}",
                "משטר": s.get("regime", ""),
                "מגמה": s.get("trend", ""),
                "זמן": s.get("created_at", "")[:16] if s.get("created_at") else "",
            })
        sig_df = pd.DataFrame(sig_rows)

        def style_direction(val):
            if val == "לונג":
                return "color: #19c37d"
            elif val == "שורט":
                return "color: #ff5c73"
            return "color: gray"

        styled_sig = sig_df.style.map(style_direction, subset=["כיוון"])
        st.dataframe(styled_sig, width="stretch", hide_index=True)
    else:
        st.info("אין איתותים עדיין")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 3: Trade History
# ---------------------------------------------------------------------------
st.subheader("היסטוריית עסקאות")
if trade_history:
    hist_rows = []
    for t in trade_history:
        pnl_val = t.get("pnl", 0.0) or 0.0
        pnl_pct = t.get("pnl_pct", 0.0) or 0.0
        entry_p = t.get("entry_price", 0) or 0
        exit_p = t.get("exit_price", 0) or 0
        hist_rows.append({
            "מטבע": t.get("symbol", ""),
            "כיוון": he_side(t.get("side", "")),
            "כניסה": fmt_usd(entry_p, 4) if entry_p > 0 else "—",
            "יציאה": fmt_usd(exit_p, 4) if exit_p > 0 else "—",
            "כמות": f"{t.get('quantity', 0):.4f}",
            "רווח $": round(pnl_val, 4),
            "רווח %": f"{pnl_pct:.2%}",
            "סגירה": he_reason(t.get("close_reason", "")),
            "נפתחה": t.get("opened_at", "")[:16] if t.get("opened_at") else "",
            "נסגרה": t.get("closed_at", "")[:16] if t.get("closed_at") else "",
        })
    hist_df = pd.DataFrame(hist_rows)

    def style_pnl(val):
        if isinstance(val, (int, float)):
            return "color: #19c37d; font-weight: bold" if val >= 0 else "color: #ff5c73; font-weight: bold"
        return ""

    def style_side_hist(val):
        if val == "לונג":
            return "color: #19c37d"
        elif val == "שורט":
            return "color: #ff5c73"
        return ""

    styled_hist = hist_df.style\
        .map(style_pnl, subset=["רווח $"])\
        .map(style_side_hist, subset=["כיוון"])

    st.dataframe(styled_hist, width="stretch", hide_index=True)
else:
    st.info("אין עסקאות סגורות עדיין")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 4: P&L Equity Curve
# ---------------------------------------------------------------------------
st.subheader("גרף הון לאורך זמן")
if snapshots and len(snapshots) > 1:
    snap_df = pd.DataFrame(snapshots)
    snap_df["timestamp"] = pd.to_datetime(snap_df["timestamp"], utc=True)
    snap_df = snap_df.sort_values("timestamp")

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=snap_df["timestamp"],
        y=snap_df["equity"],
        mode="lines",
        name="הון כולל",
        line=dict(color="#22d68a", width=2.4, shape="spline", smoothing=0.6),
        fill="tozeroy",
        fillcolor="rgba(34,214,138,0.10)",
        hovertemplate="%{x|%d/%m %H:%M}<br>הון: %{y:.2f} USDT<extra></extra>",
    ))
    fig.add_trace(go.Scatter(
        x=snap_df["timestamp"],
        y=snap_df["balance"],
        mode="lines",
        name="יתרת ארנק",
        line=dict(color="#f4b953", width=1.2, dash="dash"),
        hovertemplate="%{x|%d/%m %H:%M}<br>ארנק: %{y:.2f} USDT<extra></extra>",
    ))
    fig.update_layout(
        yaxis_title="USDT",
        legend=dict(yanchor="top", y=0.99, xanchor="left", x=0.01,
                    bgcolor="rgba(0,0,0,0)", font=dict(family="Heebo")),
        height=360,
        margin=dict(l=0, r=0, t=16, b=0),
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
        font=dict(family="Heebo", color="#8fa39b"),
        hovermode="x unified",
        hoverlabel=dict(bgcolor="rgba(10,16,18,.95)", font=dict(family="JetBrains Mono", size=12)),
        xaxis=dict(
            showgrid=False,
            rangeselector=dict(
                buttons=[
                    dict(count=6, label="6h", step="hour", stepmode="backward"),
                    dict(count=24, label="24h", step="hour", stepmode="backward"),
                    dict(count=7, label="7d", step="day", stepmode="backward"),
                    dict(step="all", label="הכול"),
                ],
                bgcolor="rgba(14,21,24,.9)",
                activecolor="rgba(34,214,138,.35)",
                font=dict(color="#edf6f1", family="Heebo"),
            ),
        ),
        yaxis=dict(gridcolor="rgba(140,180,165,.1)", zerolinecolor="rgba(140,180,165,.2)"),
    )
    st.plotly_chart(fig, width="stretch")
else:
    st.info("אין עדיין מספיק נתוני תיק להצגת גרף")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 5: Market Analysis Summary
# ---------------------------------------------------------------------------
st.subheader("ניתוח שוק")

if recent_signals:
    # Show latest signal per symbol
    seen_symbols = set()
    symbol_signals = []
    for sig in recent_signals:
        sym = sig.get("symbol", "")
        if sym and sym not in seen_symbols:
            seen_symbols.add(sym)
            symbol_signals.append(sig)

    cols = st.columns(min(len(symbol_signals), 3))
    for i, sig in enumerate(symbol_signals[:3]):
        with cols[i]:
            symbol    = sig.get("symbol", "")
            direction = sig.get("direction", "NEUTRAL")
            conf      = sig.get("confidence", 0.0)
            regime    = sig.get("regime", "—")
            trend     = sig.get("trend", "—")
            vol       = sig.get("volatility", "—")
            rf_prob   = sig.get("rf_prob")
            gb_prob   = sig.get("gb_prob")
            lr_prob   = sig.get("lr_prob")

            d_color = direction_color(direction)
            t_color = trend_color(trend)

            st.markdown(f"### {symbol}")
            st.markdown(
                colored_badge(he_side(direction), d_color),
                unsafe_allow_html=True,
            )
            st.markdown(f"**ביטחון:** {conf:.1%}")
            st.markdown(
                f"**משטר:** {regime} | **מגמה:** " +
                colored_badge(trend, t_color) +
                f" | **תנודתיות:** {vol}",
                unsafe_allow_html=True,
            )
            if rf_prob is not None and gb_prob is not None and lr_prob is not None:
                prob_df = pd.DataFrame({
                    "מודל": ["יער אקראי", "חיזוק מדורג", "רגרסיה"],
                    "הסתברות": [rf_prob, gb_prob, lr_prob],
                })
                st.bar_chart(prob_df.set_index("מודל"))
else:
    st.info("אין עדיין נתוני איתותים להצגת ניתוח שוק")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 6: System Events Log
# ---------------------------------------------------------------------------
st.subheader("יומן מערכת")
if events:
    ev_rows = []
    for ev in events:
        severity = ev.get("severity", "INFO")
        ev_rows.append({
            "זמן": ev.get("timestamp", "")[:19] if ev.get("timestamp") else "",
            "חומרה": severity,
            "סוג": ev.get("event_type", ""),
            "הודעה": ev.get("message", ""),
        })
    ev_df = pd.DataFrame(ev_rows)

    def style_severity(val):
        mapping = {
            "ERROR":   "color: #ff5c73; font-weight: bold",
            "WARNING": "color: #f2b84b",
            "INFO":    "color: #35c2ff",
            "DEBUG":   "color: gray",
        }
        return mapping.get(val, "")

    styled_ev = ev_df.style.map(style_severity, subset=["חומרה"])
    st.dataframe(styled_ev, width="stretch", hide_index=True)
else:
    st.info("אין אירועי מערכת עדיין")

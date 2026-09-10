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

from dashboard_floor import render_floor_component
from dashboard_market import render_market_component

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


# ---------------------------------------------------------------------------
# Agent control-center metadata + helpers
# ---------------------------------------------------------------------------

# Display order + icon + Hebrew label for each agent
# status -> (color, pulsing?)
# Static CSS/markup for the animated constellation (no f-string → braces stay literal)
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
            if out["pf"] >= 2.0 and out["wr"] >= 0.55 and out["trades"] >= 30:
                out["mult"] = 2.0
            elif out["pf"] >= 1.5 and out["wr"] >= 0.50:
                out["mult"] = 1.5
            elif out["pf"] >= 1.2 and out["wr"] >= 0.45:
                out["mult"] = 1.25
            elif out["pf"] < 0.8:
                out["mult"] = 0.7
    except Exception:
        pass
    return out


# מכפיל הביצועים של 24 השעות עדיין משמש את סולם האגרסיביות בהמשך העמוד
_perf24 = _perf_snapshot_24h()


# ---------------------------------------------------------------------------
# רצפת המסחר — התצוגה הראשית. כל הנתונים אמיתיים, ישירות מה-DB.
# ---------------------------------------------------------------------------

# פיד רחב יותר מזה של הכרטיסים הקלאסיים — משמש להיסטוגרמות הפעילות בכל סוכן.
try:
    _floor_feed = repo.get_recent_agent_activity(limit=250)
except Exception:
    _floor_feed = agent_feed

try:
    _stats24 = repo.get_overall_recent_stats(hours_back=24)
except Exception:
    _stats24 = {}

try:
    _session_start = repo.get_session_start()
except Exception:
    _session_start = None

# גודל היקום הנסרק: כמה סימבולים ייחודיים המערכת נגעה בהם לאחרונה
_universe = len({
    s.get("symbol") for s in recent_signals if s.get("symbol")
} | {
    t.get("symbol") for t in open_trades if t.get("symbol")
})

render_floor_component(
    config=config,
    snapshots=snapshots,
    open_trades=open_trades,
    trade_history=trade_history,
    agent_summary=agent_summary,
    agent_feed=_floor_feed,
    recent_decisions=recent_decisions,
    stats=stats,
    stats24=_stats24,
    session_start=_session_start,
    universe=_universe,
)

# ---------------------------------------------------------------------------
# פאנל שוק חי — נרות, ספר פקודות וסרט עסקאות ישירות מ-Binance אל הדפדפן,
# עם קווי הכניסה/SL/TP של הבוט מצוירים מעליהם.
#
# הפאנל הזה מחזיק WebSocket חי. הוא שורד את הרענון של Streamlit רק כל עוד
# ה-HTML שלו לא משתנה — ולכן הוא מקבל אך ורק מצב פוזיציות, בלי שעונים.
# ראו את הדוקסטרינג של dashboard_market.
# ---------------------------------------------------------------------------
render_market_component(
    config=config,
    open_trades=open_trades,
    trade_history=trade_history,
    recent_signals=recent_signals,
)

# ---------------------------------------------------------------------------
# מרכז מודיעין — הרחבות למה שרצפת המסחר מציגה בתמצית.
#
# מצב המנוע, כרטיסי הסוכנים, זרם הפעילות, מדדי התיק וגרף ההון חיים
# כולם ברצפה שבראש העמוד. מכאן ומטה נשאר רק מה שהיא לא מכסה — אחרת
# העמוד מציג את אותו מידע פעמיים בשני עיצובים שונים.
# ---------------------------------------------------------------------------
st.subheader("🧠 מרכז מודיעין")

render_strategy_center(config, open_trades, recent_decisions)
render_strategy_lab_panel()
render_opportunity_radar_panel()
render_catalyst_panel()
render_automation_stack(config)

# Live market sentiment (Fear & Greed, funding, headlines) from the NewsAgent
render_sentiment_panel()

# Live guard + market regime + latest committee decision
render_intelligence_panels()

# Live TradingView chart + technical-analysis rating
render_tradingview(open_trades)

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
# Section 1b: Performance engine — earned-aggression escalator + daily PnL
# ---------------------------------------------------------------------------
_lad = _perf24
_steps = [
    ("0.7", "מדמם", _lad["mult"] == 0.7),
    ("1.0", "ניטרלי", _lad["mult"] == 1.0),
    ("1.25", "מוכח", _lad["mult"] == 1.25),
    ("1.5", "רווחי חזק", _lad["mult"] == 1.5),
    ("2.0", "מקסימום מורווח", _lad["mult"] == 2.0),
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

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
from dashboard_ledger import render_ledger_component

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
      /* ---- רוחב מלא ----
         Streamlit מגביל את התוכן לעמודה ממורכזת גם ב-layout="wide".
         הלוח הזה הוא חדר מסחר — הוא צריך את כל המסך. */
      .block-container{
        max-width:100% !important;
        padding:0.5rem 0.9rem 1.6rem !important;
      }
      [data-testid="stAppViewContainer"] > .main{padding:0 !important;}
      [data-testid="stHeader"]{background:transparent;}
      [data-testid="stVerticalBlock"]{gap:0.55rem !important;}
      /* ה-iframe-ים של הרצפה/שוק/פנקס — עד הקצה */
      [data-testid="stIFrame"], iframe{width:100% !important;}
    </style>
    """,
    unsafe_allow_html=True,
)

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

def colored_badge(text: str, color: str) -> str:
    return (
        f'<span style="background-color:{color};color:white;'
        f'padding:2px 8px;border-radius:4px;font-size:0.85em;">{text}</span>'
    )


def render_inline_html(html: str, height: int) -> None:
    st.iframe(f"data:text/html;charset=utf-8,{quote(html)}", height=height, width="stretch")


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
# מכפיל הביצועים של 24 השעות עדיין משמש את סולם האגרסיביות בהמשך העמוד
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
# הפנקס — פוזיציות, בריאות המודל, היסטוריה ויומן מערכת.
#
# כאן היו קודם עשרה מקטעים ברכיבי Streamlit סטנדרטיים, שנראו כמו אפליקציה
# אחרת שהודבקה מתחת לרצפה. רובם היו תצוגת הגדרות (מרכז אסטרטגיות, מחסנית
# אוטומציה) או כפילות של מה שהסוכנים ופאנל השוק כבר מציגים (רדאר,
# קטליזטורים, סנטימנט, TradingView, ניתוח שוק, איתותים).
#
# נשארו ארבעה דברים שבאמת חסרים — והם נבנים מחדש באותה שפה עיצובית.
# ---------------------------------------------------------------------------
render_ledger_component(
    open_trades=open_trades,
    trade_history=trade_history,
    events=events,
    max_positions=config.hft_max_open_positions,
    health_path=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "data", "model_health.json"),
)

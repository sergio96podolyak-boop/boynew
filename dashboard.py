"""
Streamlit Dashboard for Binance Futures Trading System.
Auto-refreshes every 10 seconds and shows live portfolio, signals, and trades.
"""

import sys
import os

# Ensure project root is on the path when running via streamlit
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import logging
from datetime import datetime, timezone

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Page configuration — must be first Streamlit call
# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="Binance Futures Trading System",
    page_icon="📈",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ---------------------------------------------------------------------------
# Auto-refresh every 10 seconds
# ---------------------------------------------------------------------------
try:
    from streamlit_autorefresh import st_autorefresh
    st_autorefresh(interval=10_000, key="main_refresh")
except ImportError:
    # Fallback: manual refresh button
    st.sidebar.button("🔄 Refresh")


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
    return open_trades, trade_history, recent_signals, snapshots, events, stats


open_trades, trade_history, recent_signals, snapshots, events, stats = load_data()

# ---------------------------------------------------------------------------
# 🔊 Sound alert — plays a beep when a new trade closes (compared to last refresh)
# ---------------------------------------------------------------------------
import streamlit.components.v1 as components

_SOUND_KEY = "last_trade_count"
current_trade_count = len(trade_history)
prev_trade_count = st.session_state.get(_SOUND_KEY, current_trade_count)

if current_trade_count > prev_trade_count:
    # New trade closed since last refresh — play loud beep
    components.html("""
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
    """, height=0)

st.session_state[_SOUND_KEY] = current_trade_count

# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------
with st.sidebar:
    st.title("⚙️ System Controls")

    from config import config
    mode_color = "orange" if config.paper_trading else "red"
    mode_label = "PAPER" if config.paper_trading else "LIVE"
    st.markdown(
        colored_badge(f"Mode: {mode_label}", mode_color),
        unsafe_allow_html=True,
    )

    st.markdown("---")
    st.subheader("Configuration")
    if config.aggressive_hft:
        st.write(f"**Mode:** ⚡ HFT Execution Edge")
        st.write(f"**Scan Top:** {config.scan_top_n} symbols")
        st.write(f"**Timeframe:** {config.hft_timeframe}")
        st.write(f"**Score Entry:** {config.score_entry:.0f}")
        st.write(f"**Fast Exit:** {config.fast_exit_seconds:.0f}s")
        st.write(f"**Max Spread:** {config.max_spread_pct*100:.2f}%")
        st.write(f"**Max Positions:** {config.hft_max_open_positions}")
    else:
        st.write(f"**Symbols:** {', '.join(config.symbols)}")
        st.write(f"**Timeframe:** {config.timeframe}")
        st.write(f"**Confidence:** {config.confidence_threshold:.0%}")
        st.write(f"**Max Positions:** {config.max_open_positions}")
    st.write(f"**Leverage:** {config.leverage}x")
    st.write(f"**Max Risk/Trade:** {config.max_risk_pct:.1%}")
    st.write(f"**Max Drawdown:** {config.max_drawdown_pct:.0%}")
    st.write(f"**Trailing Stop:** {config.hft_trailing_pct if config.aggressive_hft else config.trailing_stop_pct:.1%}")

    st.markdown("---")
    st.subheader("Performance")
    if stats:
        st.metric("Total Trades", stats.get("total_trades", 0))
        wr = stats.get("win_rate", 0.0)
        st.metric("Win Rate", f"{wr:.1%}")
        total_realized = stats.get("total_pnl", 0.0)
        pnl_color_str = "normal" if total_realized >= 0 else "inverse"
        st.metric("Realized P&L", f"${total_realized:,.2f}")
        sharpe = stats.get("sharpe_ratio", 0.0)
        st.metric("Sharpe Ratio", f"{sharpe:.2f}")
        max_dd = stats.get("max_drawdown", 0.0)
        st.metric("Max Drawdown", f"{max_dd:.1%}")

    st.markdown("---")
    st.caption(f"Last update: {datetime.now(timezone.utc).strftime('%H:%M:%S UTC')}")

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
st.title("📈 Binance Futures Trading System")

col_mode, col_kill = st.columns([3, 1])
with col_mode:
    badge_color = "orange" if config.paper_trading else "red"
    st.markdown(
        colored_badge(f"{'📄 PAPER TRADING' if config.paper_trading else '🔴 LIVE TRADING'}",
                      badge_color),
        unsafe_allow_html=True,
    )
with col_kill:
    kill_active = stats.get("total_pnl", 0) < -(config.paper_initial_balance * config.max_drawdown_pct)
    if kill_active:
        st.markdown(
            colored_badge("⛔ KILL SWITCH ACTIVE", "darkred"),
            unsafe_allow_html=True,
        )
    else:
        st.markdown(
            colored_badge("✅ System Running", "green"),
            unsafe_allow_html=True,
        )

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 1: Portfolio Metrics Row
# ---------------------------------------------------------------------------
st.subheader("Portfolio Overview")

# Derive metrics from latest snapshot
latest_snap = snapshots[-1] if snapshots else {}
balance      = latest_snap.get("balance", config.paper_initial_balance)
equity       = latest_snap.get("equity", config.paper_initial_balance)
total_pnl    = latest_snap.get("total_pnl", 0.0)
total_pnl_pct = latest_snap.get("total_pnl_pct", 0.0)
unrealized   = latest_snap.get("unrealized_pnl", 0.0)
realized_pnl = stats.get("total_pnl", 0.0)
n_positions  = latest_snap.get("open_positions", len(open_trades))
win_rate     = latest_snap.get("win_rate", stats.get("win_rate", 0.0))

m1, m2, m3, m4 = st.columns(4)
with m1:
    st.metric("Wallet Balance (USDT)", f"${balance:,.2f}")
with m2:
    st.metric("Total Equity (USDT)", f"${equity:,.2f}",
              delta=f"{total_pnl_pct:.2%}",
              delta_color="normal" if total_pnl >= 0 else "inverse")
with m3:
    st.metric("Open Positions", n_positions)
with m4:
    st.metric("Win Rate", f"{win_rate:.1%}")

# P&L breakdown row
p1, p2, p3 = st.columns(3)
with p1:
    r_color = "normal" if realized_pnl >= 0 else "inverse"
    st.metric("Realized P&L", f"${realized_pnl:,.2f}", delta_color=r_color)
with p2:
    u_color = "normal" if unrealized >= 0 else "inverse"
    st.metric("Unrealized P&L", f"${unrealized:,.2f}", delta_color=u_color)
with p3:
    combined = realized_pnl + unrealized
    c_color = "normal" if combined >= 0 else "inverse"
    st.metric("Total P&L (R+U)", f"${combined:,.2f}",
              delta=f"{total_pnl_pct:.2%}",
              delta_color=c_color)

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 2: Open Positions + Recent Signals (two columns)
# ---------------------------------------------------------------------------
col_left, col_right = st.columns(2)

with col_left:
    st.subheader(f"Open Positions ({len(open_trades)})")
    if open_trades:
        pos_rows = []
        for t in open_trades:
            entry_p = t.get("entry_price", 0) or 0
            pos_rows.append({
                "Symbol": t.get("symbol", ""),
                "Side": t.get("side", ""),
                "Entry": f"${entry_p:,.4f}" if entry_p > 0 else "N/A",
                "Qty": f"{t.get('quantity', 0):.4f}",
                "SL": f"${t.get('sl_price', 0):,.4f}" if t.get("sl_price") else "—",
                "TP": f"${t.get('tp_price', 0):,.4f}" if t.get("tp_price") else "—",
                "Confidence": f"{t.get('confidence', 0):.1%}" if t.get("confidence") else "—",
                "Opened": t.get("opened_at", "")[:16] if t.get("opened_at") else "",
            })
        pos_df = pd.DataFrame(pos_rows)

        def style_side(val):
            color = "color: green" if val == "LONG" else "color: red" if val == "SHORT" else ""
            return color

        styled_pos = pos_df.style.map(style_side, subset=["Side"])
        st.dataframe(styled_pos, use_container_width=True, hide_index=True)
    else:
        st.info("No open positions")

with col_right:
    st.subheader("Recent Signals")
    if recent_signals:
        sig_rows = []
        for s in recent_signals[:15]:
            sig_rows.append({
                "Symbol": s.get("symbol", ""),
                "Direction": s.get("direction", ""),
                "Confidence": f"{s.get('confidence', 0):.1%}",
                "Regime": s.get("regime", ""),
                "Trend": s.get("trend", ""),
                "Time": s.get("created_at", "")[:16] if s.get("created_at") else "",
            })
        sig_df = pd.DataFrame(sig_rows)

        def style_direction(val):
            if val == "LONG":
                return "color: green"
            elif val == "SHORT":
                return "color: red"
            return "color: gray"

        styled_sig = sig_df.style.map(style_direction, subset=["Direction"])
        st.dataframe(styled_sig, use_container_width=True, hide_index=True)
    else:
        st.info("No signals yet")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 3: Trade History
# ---------------------------------------------------------------------------
st.subheader("Trade History")
if trade_history:
    hist_rows = []
    for t in trade_history:
        pnl_val = t.get("pnl", 0.0) or 0.0
        pnl_pct = t.get("pnl_pct", 0.0) or 0.0
        entry_p = t.get("entry_price", 0) or 0
        exit_p = t.get("exit_price", 0) or 0
        hist_rows.append({
            "Symbol": t.get("symbol", ""),
            "Side": t.get("side", ""),
            "Entry": f"${entry_p:,.4f}" if entry_p > 0 else "N/A",
            "Exit": f"${exit_p:,.4f}" if exit_p > 0 else "N/A",
            "Qty": f"{t.get('quantity', 0):.4f}",
            "P&L ($)": round(pnl_val, 4),
            "P&L %": f"{pnl_pct:.2%}",
            "Reason": t.get("close_reason", ""),
            "Opened": t.get("opened_at", "")[:16] if t.get("opened_at") else "",
            "Closed": t.get("closed_at", "")[:16] if t.get("closed_at") else "",
        })
    hist_df = pd.DataFrame(hist_rows)

    def style_pnl(val):
        if isinstance(val, (int, float)):
            return "color: green; font-weight: bold" if val >= 0 else "color: red; font-weight: bold"
        return ""

    def style_side_hist(val):
        if val == "LONG":
            return "color: green"
        elif val == "SHORT":
            return "color: red"
        return ""

    styled_hist = hist_df.style\
        .map(style_pnl, subset=["P&L ($)"])\
        .map(style_side_hist, subset=["Side"])

    st.dataframe(styled_hist, use_container_width=True, hide_index=True)
else:
    st.info("No closed trades yet")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 4: P&L Equity Curve
# ---------------------------------------------------------------------------
st.subheader("Portfolio Equity Over Time")
if snapshots and len(snapshots) > 1:
    snap_df = pd.DataFrame(snapshots)
    snap_df["timestamp"] = pd.to_datetime(snap_df["timestamp"], utc=True)
    snap_df = snap_df.sort_values("timestamp")

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=snap_df["timestamp"],
        y=snap_df["equity"],
        mode="lines",
        name="Equity",
        line=dict(color="royalblue", width=2),
        fill="tozeroy",
        fillcolor="rgba(65, 105, 225, 0.1)",
    ))
    fig.add_trace(go.Scatter(
        x=snap_df["timestamp"],
        y=snap_df["balance"],
        mode="lines",
        name="Balance",
        line=dict(color="orange", width=1, dash="dash"),
    ))
    fig.add_hline(
        y=config.paper_initial_balance,
        line_dash="dot",
        line_color="gray",
        annotation_text="Initial Balance",
    )
    fig.update_layout(
        xaxis_title="Time",
        yaxis_title="USDT",
        legend=dict(yanchor="top", y=0.99, xanchor="left", x=0.01),
        height=350,
        margin=dict(l=0, r=0, t=30, b=0),
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
    )
    st.plotly_chart(fig, use_container_width=True)
else:
    st.info("Not enough portfolio snapshots yet — run main.py to start collecting data.")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 5: Market Analysis Summary
# ---------------------------------------------------------------------------
st.subheader("Market Analysis")

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
                colored_badge(direction, d_color),
                unsafe_allow_html=True,
            )
            st.markdown(f"**Confidence:** {conf:.1%}")
            st.markdown(
                f"**Regime:** {regime} | **Trend:** " +
                colored_badge(trend, t_color) +
                f" | **Vol:** {vol}",
                unsafe_allow_html=True,
            )
            if rf_prob is not None and gb_prob is not None and lr_prob is not None:
                prob_df = pd.DataFrame({
                    "Model": ["RandomForest", "GradientBoost", "LogisticReg"],
                    "Probability": [rf_prob, gb_prob, lr_prob],
                })
                st.bar_chart(prob_df.set_index("Model"))
else:
    st.info("No signal data yet. Market analysis will appear here after the first loop.")

st.markdown("---")

# ---------------------------------------------------------------------------
# Section 6: System Events Log
# ---------------------------------------------------------------------------
st.subheader("System Events")
if events:
    ev_rows = []
    for ev in events:
        severity = ev.get("severity", "INFO")
        ev_rows.append({
            "Time": ev.get("timestamp", "")[:19] if ev.get("timestamp") else "",
            "Severity": severity,
            "Type": ev.get("event_type", ""),
            "Message": ev.get("message", ""),
        })
    ev_df = pd.DataFrame(ev_rows)

    def style_severity(val):
        mapping = {
            "ERROR":   "color: red; font-weight: bold",
            "WARNING": "color: orange",
            "INFO":    "color: steelblue",
            "DEBUG":   "color: gray",
        }
        return mapping.get(val, "")

    styled_ev = ev_df.style.map(style_severity, subset=["Severity"])
    st.dataframe(styled_ev, use_container_width=True, hide_index=True)
else:
    st.info("No system events recorded yet.")

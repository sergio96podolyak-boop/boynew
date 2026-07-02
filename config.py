"""
Configuration for Binance USDT-M Futures — classic + aggressive HFT modes.
"""

import os
from dataclasses import dataclass, field
from typing import List

from dotenv import load_dotenv

load_dotenv()


def _env_bool(key: str, default: str = "false") -> bool:
    return os.getenv(key, default).lower() in ("1", "true", "yes", "on")


def _env_float(key: str, default: str) -> float:
    return float(os.getenv(key, default))


def _env_int(key: str, default: str) -> int:
    return int(os.getenv(key, default))


@dataclass
class TradingConfig:
    # --- API ---
    api_key: str = field(default_factory=lambda: os.getenv("BINANCE_API_KEY", ""))
    api_secret: str = field(default_factory=lambda: os.getenv("BINANCE_API_SECRET", ""))

    paper_trading: bool = field(default_factory=lambda: _env_bool("PAPER_TRADING", "true"))

    # Live trading is deliberately double-locked. PAPER_TRADING=false is not
    # enough: live mode also requires these explicit acknowledgements.
    live_trading_enabled: bool = field(
        default_factory=lambda: _env_bool("LIVE_TRADING_ENABLED", "false")
    )
    live_trading_confirmation: str = field(
        default_factory=lambda: os.getenv("LIVE_TRADING_CONFIRMATION", "")
    )
    live_max_leverage: int = field(default_factory=lambda: _env_int("LIVE_MAX_LEVERAGE", "5"))
    live_max_margin_fraction: float = field(
        default_factory=lambda: _env_float("LIVE_MAX_MARGIN_FRACTION", "0.10")
    )
    live_required_min_equity_usdt: float = field(
        default_factory=lambda: _env_float("LIVE_REQUIRED_MIN_EQUITY_USDT", "25")
    )

    symbols: List[str] = field(
        default_factory=lambda: os.getenv("SYMBOLS", "BTCUSDT,ETHUSDT").split(",")
    )

    leverage: int = field(default_factory=lambda: _env_int("LEVERAGE", "5"))

    confidence_threshold: float = field(
        default_factory=lambda: _env_float("CONFIDENCE_THRESHOLD", "0.68")
    )

    max_risk_pct: float = field(default_factory=lambda: _env_float("MAX_RISK_PCT", "0.01"))
    max_drawdown_pct: float = field(default_factory=lambda: _env_float("MAX_DRAWDOWN_PCT", "0.10"))
    trailing_stop_pct: float = field(default_factory=lambda: _env_float("TRAILING_STOP_PCT", "0.015"))

    sl_atr_multiplier: float = field(default_factory=lambda: _env_float("SL_ATR_MULTIPLIER", "2.0"))
    tp_atr_multiplier: float = field(default_factory=lambda: _env_float("TP_ATR_MULTIPLIER", "3.0"))

    lookback_candles: int = field(default_factory=lambda: _env_int("LOOKBACK_CANDLES", "200"))
    poll_interval_seconds: int = field(default_factory=lambda: _env_int("POLL_INTERVAL_SECONDS", "60"))

    db_path: str = field(default_factory=lambda: os.getenv("DB_PATH", "trading.db"))
    paper_initial_balance: float = field(default_factory=lambda: _env_float("INITIAL_BALANCE", "10000.0"))
    paper_reset_open_trades_on_start: bool = field(
        default_factory=lambda: _env_bool("PAPER_RESET_OPEN_TRADES_ON_START", "true")
    )

    timeframe: str = field(default_factory=lambda: os.getenv("TIMEFRAME", "1h"))
    max_open_positions: int = field(default_factory=lambda: _env_int("MAX_OPEN_POSITIONS", "3"))
    fetch_limit: int = field(default_factory=lambda: _env_int("FETCH_LIMIT", "300"))
    retrain_interval: int = field(default_factory=lambda: _env_int("RETRAIN_INTERVAL", "50"))
    dashboard_port: int = field(default_factory=lambda: _env_int("DASHBOARD_PORT", "8501"))

    # --- Aggressive HFT (env AGGRESSIVE_HFT=true) ---
    aggressive_hft: bool = field(default_factory=lambda: _env_bool("AGGRESSIVE_HFT", "true"))

    # Skip ultra–low-priced perps (precision / SL-TP issues, e.g. TRU @ $0.01)
    min_symbol_price_usdt: float = field(
        default_factory=lambda: _env_float("MIN_SYMBOL_PRICE_USDT", "0.05")
    )

    scan_top_n: int = field(default_factory=lambda: _env_int("SCAN_TOP_N", "50"))
    new_listing_scan_enabled: bool = field(
        default_factory=lambda: _env_bool("NEW_LISTING_SCAN_ENABLED", "true")
    )
    new_listing_max_age_days: int = field(
        default_factory=lambda: _env_int("NEW_LISTING_MAX_AGE_DAYS", "30")
    )
    new_listing_top_n: int = field(default_factory=lambda: _env_int("NEW_LISTING_TOP_N", "15"))
    new_listing_min_quote_volume_usdt: float = field(
        default_factory=lambda: _env_float("NEW_LISTING_MIN_QUOTE_VOLUME_USDT", "3000000")
    )
    momentum_scan_enabled: bool = field(
        default_factory=lambda: _env_bool("MOMENTUM_SCAN_ENABLED", "true")
    )
    momentum_top_n: int = field(default_factory=lambda: _env_int("MOMENTUM_TOP_N", "20"))
    momentum_min_quote_volume_usdt: float = field(
        default_factory=lambda: _env_float("MOMENTUM_MIN_QUOTE_VOLUME_USDT", "3000000")
    )
    momentum_min_price_change_pct: float = field(
        default_factory=lambda: _env_float("MOMENTUM_MIN_PRICE_CHANGE_PCT", "5")
    )
    # DEX Watch → scanner: inject Hyperliquid hot movers that also trade on
    # Binance futures into the scan universe (all entry gates still apply).
    dex_hot_scan_enabled: bool = field(
        default_factory=lambda: _env_bool("DEX_HOT_SCAN_ENABLED", "true")
    )
    dex_hot_top_n: int = field(default_factory=lambda: _env_int("DEX_HOT_TOP_N", "6"))
    discovery_score_bonus_max: float = field(
        default_factory=lambda: _env_float("DISCOVERY_SCORE_BONUS_MAX", "5")
    )
    hft_timeframe: str = field(default_factory=lambda: os.getenv("HFT_TIMEFRAME", "1m"))
    hft_fetch_limit: int = field(default_factory=lambda: _env_int("HFT_FETCH_LIMIT", "200"))
    min_ml_training_candles: int = field(
        default_factory=lambda: _env_int("MIN_ML_TRAINING_CANDLES", "240")
    )
    technical_fallback_signals: bool = field(
        default_factory=lambda: _env_bool("TECHNICAL_FALLBACK_SIGNALS", "true")
    )
    technical_fallback_min_score: float = field(
        default_factory=lambda: _env_float("TECHNICAL_FALLBACK_MIN_SCORE", "78")
    )
    technical_fallback_strong_mode: bool = field(
        default_factory=lambda: _env_bool("TECHNICAL_FALLBACK_STRONG_MODE", "true")
    )
    technical_fallback_strong_min_score: float = field(
        default_factory=lambda: _env_float("TECHNICAL_FALLBACK_STRONG_MIN_SCORE", "88")
    )
    technical_fallback_volume_mult: float = field(
        default_factory=lambda: _env_float("TECHNICAL_FALLBACK_VOLUME_MULT", "1.25")
    )

    score_entry: float = field(default_factory=lambda: _env_float("SCORE_ENTRY", "72"))
    score_high: float = field(default_factory=lambda: _env_float("SCORE_HIGH", "85"))
    score_extreme: float = field(default_factory=lambda: _env_float("SCORE_EXTREME", "92"))

    size_base_pct: float = field(default_factory=lambda: _env_float("SIZE_BASE_PCT", "0.10"))
    size_high_pct: float = field(default_factory=lambda: _env_float("SIZE_HIGH_PCT", "0.20"))
    size_extreme_pct: float = field(default_factory=lambda: _env_float("SIZE_EXTREME_PCT", "0.30"))
    # Hard cap: max fraction of available balance used as margin per trade
    max_margin_fraction: float = field(
        default_factory=lambda: _env_float("MAX_MARGIN_FRACTION_PER_POSITION", "0.30")
    )
    # HFT: minimum position notional (qty × price) in USDT — avoids “penny” sizes; still capped by max_notional.
    # Many Binance pairs require MIN_NOTIONAL ≥ 5 USDT — raise this if orders are rejected.
    hft_min_notional_usdt: float = field(
        default_factory=lambda: _env_float("HFT_MIN_NOTIONAL_USDT", "5")
    )

    # High-conviction mode: allow bigger entries only when the committee score,
    # consensus, funding and drawdown state all support taking more risk.
    high_conviction_enabled: bool = field(
        default_factory=lambda: _env_bool("HIGH_CONVICTION_ENABLED", "true")
    )
    high_conviction_min_score: float = field(
        default_factory=lambda: _env_float("HIGH_CONVICTION_MIN_SCORE", "96")
    )
    high_conviction_min_consensus: float = field(
        default_factory=lambda: _env_float("HIGH_CONVICTION_MIN_CONSENSUS", "0.85")
    )
    high_conviction_max_funding_penalty: float = field(
        default_factory=lambda: _env_float("HIGH_CONVICTION_MAX_FUNDING_PENALTY", "1.0")
    )
    high_conviction_size_multiplier: float = field(
        default_factory=lambda: _env_float("HIGH_CONVICTION_SIZE_MULTIPLIER", "1.20")
    )
    high_conviction_max_drawdown_pct: float = field(
        default_factory=lambda: _env_float("HIGH_CONVICTION_MAX_DRAWDOWN_PCT", "0.03")
    )
    high_conviction_profit_take_multiplier: float = field(
        default_factory=lambda: _env_float("HIGH_CONVICTION_PROFIT_TAKE_MULTIPLIER", "1.35")
    )
    capital_allocator_enabled: bool = field(
        default_factory=lambda: _env_bool("CAPITAL_ALLOCATOR_ENABLED", "true")
    )
    capital_allocator_min_score: float = field(
        default_factory=lambda: _env_float("CAPITAL_ALLOCATOR_MIN_SCORE", "98")
    )
    capital_allocator_max_funding_penalty: float = field(
        default_factory=lambda: _env_float("CAPITAL_ALLOCATOR_MAX_FUNDING_PENALTY", "1.0")
    )
    capital_allocator_size_multiplier: float = field(
        default_factory=lambda: _env_float("CAPITAL_ALLOCATOR_SIZE_MULTIPLIER", "1.35")
    )
    capital_allocator_max_open_positions: int = field(
        default_factory=lambda: _env_int("CAPITAL_ALLOCATOR_MAX_OPEN_POSITIONS", "1")
    )
    trend_runner_enabled: bool = field(
        default_factory=lambda: _env_bool("TREND_RUNNER_ENABLED", "true")
    )
    trend_runner_min_score: float = field(
        default_factory=lambda: _env_float("TREND_RUNNER_MIN_SCORE", "92")
    )
    trend_runner_profit_take_multiplier: float = field(
        default_factory=lambda: _env_float("TREND_RUNNER_PROFIT_TAKE_MULTIPLIER", "1.80")
    )
    trend_runner_tp_multiplier: float = field(
        default_factory=lambda: _env_float("TREND_RUNNER_TP_MULTIPLIER", "1.45")
    )
    trend_runner_tp_max_pct: float = field(
        default_factory=lambda: _env_float("TREND_RUNNER_TP_MAX_PCT", "0.050")
    )
    trend_runner_lock_trigger_pct: float = field(
        default_factory=lambda: _env_float("TREND_RUNNER_LOCK_TRIGGER_PCT", "0.009")
    )
    trend_runner_retrace_pct: float = field(
        default_factory=lambda: _env_float("TREND_RUNNER_RETRACE_PCT", "0.003")
    )
    trend_runner_min_age_seconds: float = field(
        default_factory=lambda: _env_float("TREND_RUNNER_MIN_AGE_SECONDS", "90")
    )
    drawdown_size_reduction_enabled: bool = field(
        default_factory=lambda: _env_bool("DRAWDOWN_SIZE_REDUCTION_ENABLED", "true")
    )
    drawdown_size_reduction_start_pct: float = field(
        default_factory=lambda: _env_float("DRAWDOWN_SIZE_REDUCTION_START_PCT", "0.06")
    )
    drawdown_size_multiplier: float = field(
        default_factory=lambda: _env_float("DRAWDOWN_SIZE_MULTIPLIER", "0.70")
    )

    tp_min_pct: float = field(default_factory=lambda: _env_float("TP_MIN_PCT", "0.003"))
    tp_max_pct: float = field(default_factory=lambda: _env_float("TP_MAX_PCT", "0.015"))
    sl_min_pct: float = field(default_factory=lambda: _env_float("SL_MIN_PCT", "0.003"))
    sl_max_pct: float = field(default_factory=lambda: _env_float("SL_MAX_PCT", "0.007"))

    hft_trailing_pct: float = field(default_factory=lambda: _env_float("HFT_TRAILING_PCT", "0.002"))

    # Profit capture: bank a good scalp before it can round-trip back to loss.
    profit_lock_enabled: bool = field(
        default_factory=lambda: _env_bool("PROFIT_LOCK_ENABLED", "true")
    )
    profit_lock_trigger_pct: float = field(
        default_factory=lambda: _env_float("PROFIT_LOCK_TRIGGER_PCT", "0.004")
    )
    profit_lock_retrace_pct: float = field(
        default_factory=lambda: _env_float("PROFIT_LOCK_RETRACE_PCT", "0.0015")
    )
    profit_lock_min_net_pct: float = field(
        default_factory=lambda: _env_float("PROFIT_LOCK_MIN_NET_PCT", "0.001")
    )
    profit_take_pct: float = field(
        default_factory=lambda: _env_float("PROFIT_TAKE_PCT", "0.010")
    )
    profit_take_min_age_seconds: float = field(
        default_factory=lambda: _env_float("PROFIT_TAKE_MIN_AGE_SECONDS", "45")
    )
    # Estimated round-trip trading cost, expressed as a fraction of price move.
    # Used to avoid "profit" exits that are likely eaten by fees/slippage.
    estimated_taker_fee_pct: float = field(
        default_factory=lambda: _env_float("ESTIMATED_TAKER_FEE_PCT", "0.0005")
    )
    profit_edge_buffer_pct: float = field(
        default_factory=lambda: _env_float("PROFIT_EDGE_BUFFER_PCT", "0.0005")
    )

    # Minimum ATR as fraction of price to allow entry (e.g. 0.001 = 0.1%).
    # Prevents entering trades in low-volatility / no-movement markets.
    # Set 0 to disable. Env: MIN_ATR_PCT
    min_atr_pct: float = field(default_factory=lambda: _env_float("MIN_ATR_PCT", "0.001"))

    # After this many seconds, if favorable move is still below min_favorable_move_pct, exit (Telegram: "אין תנועה").
    # Default 15m: fewer premature exits than 2m; set 0 to disable (SL/TP still apply).
    stale_exit_seconds: float = field(default_factory=lambda: _env_float("STALE_EXIT_SECONDS", "900"))
    # Minimum move in trade direction (fraction, e.g. 0.0002 = 0.02%) to count as "progress" vs stale.
    min_favorable_move_pct: float = field(
        default_factory=lambda: _env_float("MIN_FAVORABLE_MOVE_PCT", "0.0002")
    )

    hft_max_open_positions: int = field(default_factory=lambda: _env_int("HFT_MAX_OPEN_POSITIONS", "2"))

    daily_max_drawdown_pct: float = field(
        default_factory=lambda: _env_float("DAILY_MAX_DRAWDOWN_PCT", "0.05")
    )
    abnormal_loss_pct_per_trade: float = field(
        default_factory=lambda: _env_float("ABNORMAL_LOSS_PCT_PER_TRADE", "0.02")
    )

    rage_streak: int = field(default_factory=lambda: _env_int("RAGE_STREAK", "3"))
    rage_win_mult: float = field(default_factory=lambda: _env_float("RAGE_WIN_MULT", "1.25"))
    rage_loss_mult: float = field(default_factory=lambda: _env_float("RAGE_LOSS_MULT", "0.5"))

    model_path: str = field(default_factory=lambda: os.getenv("HFT_MODEL_PATH", "models/hft_lgbm.txt"))
    model_retrain_loops: int = field(default_factory=lambda: _env_int("MODEL_RETRAIN_LOOPS", "120"))

    loop_sleep_ms: int = field(default_factory=lambda: _env_int("LOOP_SLEEP_MS", "50"))

    order_retry_max: int = field(default_factory=lambda: _env_int("ORDER_RETRY_MAX", "5"))

    # ── Execution Edge Filters ─────────────────────────────────────────────
    # Volume: require last candle volume >= N × 20-period MA to confirm direction
    min_volume_spike: float = field(default_factory=lambda: _env_float("MIN_VOLUME_SPIKE", "1.2"))
    # Spread: max bid-ask spread as fraction of price (0.001 = 0.1%)
    max_spread_pct: float = field(default_factory=lambda: _env_float("MAX_SPREAD_PCT", "0.001"))
    # Choppiness: skip if choppiness index > threshold (range market, no edge)
    max_choppiness: float = field(default_factory=lambda: _env_float("MAX_CHOPPINESS", "60"))
    # Micro-pullback: require price pulled back >= N% from recent extreme before entry
    min_pullback_pct: float = field(default_factory=lambda: _env_float("MIN_PULLBACK_PCT", "0.0005"))
    # Absorption detection: high volume + low movement = whale activity
    absorption_volume_mult: float = field(default_factory=lambda: _env_float("ABSORPTION_VOL_MULT", "2.5"))
    absorption_move_max_pct: float = field(default_factory=lambda: _env_float("ABSORPTION_MOVE_MAX_PCT", "0.001"))
    # Fast exit: seconds with no favorable move before micro-exit (0 = disabled)
    fast_exit_seconds: float = field(default_factory=lambda: _env_float("FAST_EXIT_SECONDS", "45"))
    # Opposite pressure exit: exit if price reverses N% from peak profit
    opposite_pressure_pct: float = field(default_factory=lambda: _env_float("OPPOSITE_PRESSURE_PCT", "0.002"))
    # Slippage: max acceptable slippage as fraction (0.002 = 0.2%)
    max_slippage_pct: float = field(default_factory=lambda: _env_float("MAX_SLIPPAGE_PCT", "0.002"))
    # Latency: max acceptable order latency in ms before throttling
    max_latency_ms: float = field(default_factory=lambda: _env_float("MAX_LATENCY_MS", "500"))
    # Symbols that exceed slippage/latency N times get throttled for M loops
    throttle_strikes: int = field(default_factory=lambda: _env_int("THROTTLE_STRIKES", "3"))
    throttle_cooldown_loops: int = field(default_factory=lambda: _env_int("THROTTLE_COOLDOWN_LOOPS", "50"))
    # Funding-rate risk: block crowded/unstable perps and avoid settlement windows.
    max_abs_funding_rate: float = field(
        default_factory=lambda: _env_float("MAX_ABS_FUNDING_RATE", "0.0015")
    )
    crowded_funding_rate: float = field(
        default_factory=lambda: _env_float("CROWDED_FUNDING_RATE", "0.0005")
    )
    funding_avoid_minutes: float = field(
        default_factory=lambda: _env_float("FUNDING_AVOID_MINUTES", "20")
    )
    funding_window_score_penalty: float = field(
        default_factory=lambda: _env_float("FUNDING_WINDOW_SCORE_PENALTY", "5")
    )
    funding_size_multiplier: float = field(
        default_factory=lambda: _env_float("FUNDING_SIZE_MULTIPLIER", "0.75")
    )
    block_stock_like_perps_outside_primary_hours: bool = field(
        default_factory=lambda: _env_bool("BLOCK_STOCK_LIKE_PERPS_OUTSIDE_PRIMARY_HOURS", "true")
    )

    # ── TradingView signals (free TA ratings via tradingview-ta) ─────────────
    # When on, the bot also enters trades on TradingView Strong-Buy/Sell ratings
    # (with the same risk checks + exchange SL/TP). Not a profit guarantee.
    tradingview_signals: bool = field(default_factory=lambda: _env_bool("TRADINGVIEW_SIGNALS", "true"))
    tradingview_interval: str = field(default_factory=lambda: os.getenv("TRADINGVIEW_INTERVAL", "15m"))
    tradingview_min_strength: float = field(
        default_factory=lambda: _env_float("TRADINGVIEW_MIN_STRENGTH", "0.65")
    )
    tradingview_refresh_sec: float = field(
        default_factory=lambda: _env_float("TRADINGVIEW_REFRESH_SEC", "45")
    )

    # ── Strategy Lab / research gate ───────────────────────────────────────
    # Converts ideas such as Grid/DCA/FreqAI/market making into a measurable
    # readiness snapshot. It never places orders.
    strategy_lab_enabled: bool = field(
        default_factory=lambda: _env_bool("STRATEGY_LAB_ENABLED", "true")
    )
    strategy_lab_refresh_loops: int = field(
        default_factory=lambda: _env_int("STRATEGY_LAB_REFRESH_LOOPS", "50")
    )
    strategy_lab_lookback_hours: int = field(
        default_factory=lambda: _env_int("STRATEGY_LAB_LOOKBACK_HOURS", "48")
    )
    strategy_lab_min_live_trades: int = field(
        default_factory=lambda: _env_int("STRATEGY_LAB_MIN_LIVE_TRADES", "30")
    )

    # ── Binance multi-product opportunity radar ───────────────────────────
    # Watches Spot/Grid/Options/Alpha/Dual/Launchpool/Copy opportunities for
    # the dashboard. It never subscribes or places non-futures orders.
    opportunity_radar_enabled: bool = field(
        default_factory=lambda: _env_bool("OPPORTUNITY_RADAR_ENABLED", "true")
    )
    opportunity_radar_refresh_loops: int = field(
        default_factory=lambda: _env_int("OPPORTUNITY_RADAR_REFRESH_LOOPS", "25")
    )
    opportunity_radar_top_n: int = field(
        default_factory=lambda: _env_int("OPPORTUNITY_RADAR_TOP_N", "8")
    )
    opportunity_radar_min_quote_volume_usdt: float = field(
        default_factory=lambda: _env_float("OPPORTUNITY_RADAR_MIN_QUOTE_VOLUME_USDT", "2000000")
    )

    # ── Multi-agent entry committee ────────────────────────────────────────
    # Scanner candidates must pass a second layer before RiskManager sizes them:
    # news/sentiment, market regime, freshness, and live safety checks.
    decision_min_consensus: float = field(
        default_factory=lambda: _env_float("DECISION_MIN_CONSENSUS", "0.67")
    )
    decision_live_min_consensus: float = field(
        default_factory=lambda: _env_float("DECISION_LIVE_MIN_CONSENSUS", "0.80")
    )
    decision_min_score_after_guards: float = field(
        default_factory=lambda: _env_float("DECISION_MIN_SCORE_AFTER_GUARDS", "70")
    )
    block_when_model_unhealthy: bool = field(
        default_factory=lambda: _env_bool("BLOCK_WHEN_MODEL_UNHEALTHY", "true")
    )
    health_check_enabled: bool = field(
        default_factory=lambda: _env_bool("HEALTH_CHECK_ENABLED", "true")
    )
    health_check_seconds: float = field(
        default_factory=lambda: _env_float("HEALTH_CHECK_SECONDS", "45")
    )
    health_repair_protection_enabled: bool = field(
        default_factory=lambda: _env_bool("HEALTH_REPAIR_PROTECTION_ENABLED", "true")
    )
    block_on_stale_news: bool = field(
        default_factory=lambda: _env_bool("BLOCK_ON_STALE_NEWS", "false")
    )
    news_max_age_seconds: float = field(
        default_factory=lambda: _env_float("NEWS_MAX_AGE_SECONDS", "900")
    )
    news_refresh_seconds: float = field(
        default_factory=lambda: _env_float("NEWS_REFRESH_SECONDS", "120")
    )
    news_negative_headline_block: bool = field(
        default_factory=lambda: _env_bool("NEWS_NEGATIVE_HEADLINE_BLOCK", "true")
    )
    catalyst_agent_enabled: bool = field(
        default_factory=lambda: _env_bool("CATALYST_AGENT_ENABLED", "true")
    )
    catalyst_refresh_seconds: float = field(
        default_factory=lambda: _env_float("CATALYST_REFRESH_SECONDS", "90")
    )
    catalyst_max_age_seconds: float = field(
        default_factory=lambda: _env_float("CATALYST_MAX_AGE_SECONDS", "900")
    )
    catalyst_score_boost: float = field(
        default_factory=lambda: _env_float("CATALYST_SCORE_BOOST", "3")
    )
    catalyst_max_dated_event_lag_days: float = field(
        default_factory=lambda: _env_float("CATALYST_MAX_DATED_EVENT_LAG_DAYS", "3")
    )
    catalyst_negative_block: bool = field(
        default_factory=lambda: _env_bool("CATALYST_NEGATIVE_BLOCK", "true")
    )
    market_regime_refresh_seconds: float = field(
        default_factory=lambda: _env_float("MARKET_REGIME_REFRESH_SECONDS", "45")
    )
    market_regime_symbol: str = field(
        default_factory=lambda: os.getenv("MARKET_REGIME_SYMBOL", "BTCUSDT")
    )
    market_regime_timeframe: str = field(
        default_factory=lambda: os.getenv("MARKET_REGIME_TIMEFRAME", "15m")
    )
    market_regime_fetch_limit: int = field(
        default_factory=lambda: _env_int("MARKET_REGIME_FETCH_LIMIT", "120")
    )
    regime_block_longs_drop_pct: float = field(
        default_factory=lambda: _env_float("REGIME_BLOCK_LONGS_DROP_PCT", "0.012")
    )
    regime_block_shorts_rally_pct: float = field(
        default_factory=lambda: _env_float("REGIME_BLOCK_SHORTS_RALLY_PCT", "0.012")
    )
    regime_high_volatility_pct: float = field(
        default_factory=lambda: _env_float("REGIME_HIGH_VOLATILITY_PCT", "0.018")
    )
    regime_risk_off_size_mult: float = field(
        default_factory=lambda: _env_float("REGIME_RISK_OFF_SIZE_MULT", "0.50")
    )

    # ── Order-flow / positioning agent ────────────────────────────────────
    flow_agent_enabled: bool = field(
        default_factory=lambda: _env_bool("FLOW_AGENT_ENABLED", "true")
    )
    flow_refresh_seconds: float = field(
        default_factory=lambda: _env_float("FLOW_REFRESH_SECONDS", "45")
    )
    flow_period: str = field(default_factory=lambda: os.getenv("FLOW_PERIOD", "5m"))
    flow_lookback: int = field(default_factory=lambda: _env_int("FLOW_LOOKBACK", "4"))
    flow_min_oi_change_pct: float = field(
        default_factory=lambda: _env_float("FLOW_MIN_OI_CHANGE_PCT", "0.003")
    )
    flow_taker_buy_ratio: float = field(
        default_factory=lambda: _env_float("FLOW_TAKER_BUY_RATIO", "1.08")
    )
    flow_taker_sell_ratio: float = field(
        default_factory=lambda: _env_float("FLOW_TAKER_SELL_RATIO", "0.92")
    )
    flow_strong_taker_ratio: float = field(
        default_factory=lambda: _env_float("FLOW_STRONG_TAKER_RATIO", "1.20")
    )
    flow_score_boost: float = field(
        default_factory=lambda: _env_float("FLOW_SCORE_BOOST", "4")
    )
    flow_score_penalty: float = field(
        default_factory=lambda: _env_float("FLOW_SCORE_PENALTY", "5")
    )
    flow_size_penalty: float = field(
        default_factory=lambda: _env_float("FLOW_SIZE_PENALTY", "0.80")
    )
    flow_crowded_long_ratio: float = field(
        default_factory=lambda: _env_float("FLOW_CROWDED_LONG_RATIO", "2.50")
    )
    flow_crowded_short_ratio: float = field(
        default_factory=lambda: _env_float("FLOW_CROWDED_SHORT_RATIO", "0.40")
    )
    flow_hard_block_opposite: bool = field(
        default_factory=lambda: _env_bool("FLOW_HARD_BLOCK_OPPOSITE", "false")
    )

    # ── Indirect advanced strategies ──────────────────────────────────────
    # Routes Grid/DCA/Arbitrage ideas into the protected committee/risk flow.
    # These modules never place standalone orders.
    indirect_strategies_enabled: bool = field(
        default_factory=lambda: _env_bool("INDIRECT_STRATEGIES_ENABLED", "true")
    )
    indirect_grid_enabled: bool = field(
        default_factory=lambda: _env_bool("INDIRECT_GRID_ENABLED", "true")
    )
    indirect_grid_min_choppiness: float = field(
        default_factory=lambda: _env_float("INDIRECT_GRID_MIN_CHOPPINESS", "48")
    )
    indirect_grid_max_adx: float = field(
        default_factory=lambda: _env_float("INDIRECT_GRID_MAX_ADX", "28")
    )
    indirect_grid_lower_bbp: float = field(
        default_factory=lambda: _env_float("INDIRECT_GRID_LOWER_BBP", "0.35")
    )
    indirect_grid_upper_bbp: float = field(
        default_factory=lambda: _env_float("INDIRECT_GRID_UPPER_BBP", "0.65")
    )
    indirect_grid_chase_bbp: float = field(
        default_factory=lambda: _env_float("INDIRECT_GRID_CHASE_BBP", "0.78")
    )
    indirect_grid_score_boost: float = field(
        default_factory=lambda: _env_float("INDIRECT_GRID_SCORE_BOOST", "2.5")
    )
    indirect_grid_edge_penalty: float = field(
        default_factory=lambda: _env_float("INDIRECT_GRID_EDGE_PENALTY", "4.0")
    )
    indirect_dca_enabled: bool = field(
        default_factory=lambda: _env_bool("INDIRECT_DCA_ENABLED", "true")
    )
    indirect_dca_pullback_min_pct: float = field(
        default_factory=lambda: _env_float("INDIRECT_DCA_PULLBACK_MIN_PCT", "0.0008")
    )
    indirect_dca_score_boost: float = field(
        default_factory=lambda: _env_float("INDIRECT_DCA_SCORE_BOOST", "1.5")
    )
    indirect_arb_enabled: bool = field(
        default_factory=lambda: _env_bool("INDIRECT_ARB_ENABLED", "true")
    )
    indirect_arb_score_boost: float = field(
        default_factory=lambda: _env_float("INDIRECT_ARB_SCORE_BOOST", "1.5")
    )
    indirect_martingale_inverse_enabled: bool = field(
        default_factory=lambda: _env_bool("INDIRECT_MARTINGALE_INVERSE_ENABLED", "true")
    )
    indirect_martingale_drawdown_cut_pct: float = field(
        default_factory=lambda: _env_float("INDIRECT_MARTINGALE_DRAWDOWN_CUT_PCT", "0.025")
    )
    indirect_max_score_boost: float = field(
        default_factory=lambda: _env_float("INDIRECT_MAX_SCORE_BOOST", "5.0")
    )
    indirect_max_size_boost: float = field(
        default_factory=lambda: _env_float("INDIRECT_MAX_SIZE_BOOST", "1.08")
    )

    # ── Telegram ────────────────────────────────────────────────────────────
    telegram_enabled: bool = field(
        default_factory=lambda: _env_bool("TELEGRAM_ENABLED", "false")
    )
    telegram_token: str = field(default_factory=lambda: os.getenv("TELEGRAM_TOKEN", ""))
    telegram_chat_id: str = field(default_factory=lambda: os.getenv("TELEGRAM_CHAT_ID", ""))
    telegram_heartbeat_interval: int = field(
        default_factory=lambda: _env_int("TELEGRAM_HEARTBEAT_INTERVAL", "300")
    )

    def validate(self) -> None:
        if not self.paper_trading:
            if not self.live_trading_enabled:
                raise ValueError(
                    "LIVE trading is locked. Set LIVE_TRADING_ENABLED=true only after "
                    "you intentionally choose to run real Binance Futures orders."
                )
            if self.live_trading_confirmation != "I_ACCEPT_REAL_BINANCE_FUTURES_RISK":
                raise ValueError(
                    "LIVE_TRADING_CONFIRMATION must be exactly "
                    "I_ACCEPT_REAL_BINANCE_FUTURES_RISK for live trading."
                )
            if not self.api_key or self.api_key == "your_api_key_here":
                raise ValueError("BINANCE_API_KEY must be set for live trading")
            if not self.api_secret or self.api_secret == "your_api_secret_here":
                raise ValueError("BINANCE_API_SECRET must be set for live trading")
            if self.leverage > self.live_max_leverage:
                raise ValueError(
                    f"Live leverage {self.leverage}x exceeds LIVE_MAX_LEVERAGE "
                    f"({self.live_max_leverage}x)"
                )
            if self.max_margin_fraction > self.live_max_margin_fraction:
                raise ValueError(
                    f"Live max_margin_fraction {self.max_margin_fraction:.2f} exceeds "
                    f"LIVE_MAX_MARGIN_FRACTION ({self.live_max_margin_fraction:.2f})"
                )

        if not self.symbols and not self.aggressive_hft:
            raise ValueError("At least one symbol must be configured")

        if not 1 <= self.leverage <= 125:
            raise ValueError(f"Leverage must be between 1 and 125, got {self.leverage}")

        if not 0 < self.confidence_threshold < 1:
            raise ValueError(f"confidence_threshold must be between 0 and 1, got {self.confidence_threshold}")

        if not self.aggressive_hft:
            if not 0 < self.max_risk_pct <= 0.05:
                raise ValueError(f"max_risk_pct should be between 0 and 5%, got {self.max_risk_pct}")

        if not 0 < self.max_drawdown_pct <= 1:
            raise ValueError(f"max_drawdown_pct must be between 0 and 1, got {self.max_drawdown_pct}")

        if not 0 < self.max_margin_fraction <= 1:
            raise ValueError(
                f"max_margin_fraction must be in (0,1], got {self.max_margin_fraction}"
            )
        if not 0 < self.daily_max_drawdown_pct <= 1:
            raise ValueError(
                f"daily_max_drawdown_pct must be in (0,1], got {self.daily_max_drawdown_pct}"
            )
        for name, v in (
            ("size_base_pct", self.size_base_pct),
            ("size_high_pct", self.size_high_pct),
            ("size_extreme_pct", self.size_extreme_pct),
        ):
            if not 0 < v <= 1:
                raise ValueError(f"{name} must be in (0,1], got {v}")

        if self.scan_top_n <= 0:
            raise ValueError(f"scan_top_n must be > 0, got {self.scan_top_n}")
        if self.new_listing_max_age_days < 0:
            raise ValueError("new_listing_max_age_days must be >= 0")
        if self.new_listing_top_n < 0:
            raise ValueError("new_listing_top_n must be >= 0")
        if self.new_listing_min_quote_volume_usdt < 0:
            raise ValueError("new_listing_min_quote_volume_usdt must be >= 0")
        if self.momentum_top_n < 0:
            raise ValueError("momentum_top_n must be >= 0")
        if self.momentum_min_quote_volume_usdt < 0:
            raise ValueError("momentum_min_quote_volume_usdt must be >= 0")
        if self.momentum_min_price_change_pct < 0:
            raise ValueError("momentum_min_price_change_pct must be >= 0")
        if self.dex_hot_top_n < 0:
            raise ValueError("dex_hot_top_n must be >= 0")
        if self.discovery_score_bonus_max < 0:
            raise ValueError("discovery_score_bonus_max must be >= 0")
        if self.technical_fallback_min_score < 0:
            raise ValueError("technical_fallback_min_score must be >= 0")
        if self.technical_fallback_strong_min_score < 0:
            raise ValueError("technical_fallback_strong_min_score must be >= 0")
        if self.technical_fallback_volume_mult <= 0:
            raise ValueError("technical_fallback_volume_mult must be > 0")
        if self.hft_min_notional_usdt < 0:
            raise ValueError(f"hft_min_notional_usdt must be >= 0, got {self.hft_min_notional_usdt}")
        if self.high_conviction_min_score < 0:
            raise ValueError("high_conviction_min_score must be >= 0")
        if not 0 < self.high_conviction_min_consensus <= 1:
            raise ValueError("high_conviction_min_consensus must be in (0,1]")
        if self.high_conviction_max_funding_penalty < 0:
            raise ValueError("high_conviction_max_funding_penalty must be >= 0")
        if not 1 <= self.high_conviction_size_multiplier <= 2:
            raise ValueError("high_conviction_size_multiplier must be in [1,2]")
        if self.high_conviction_max_drawdown_pct < 0:
            raise ValueError("high_conviction_max_drawdown_pct must be >= 0")
        if self.high_conviction_profit_take_multiplier <= 0:
            raise ValueError("high_conviction_profit_take_multiplier must be > 0")
        if self.drawdown_size_reduction_start_pct < 0:
            raise ValueError("drawdown_size_reduction_start_pct must be >= 0")
        if not 0 < self.drawdown_size_multiplier <= 1:
            raise ValueError("drawdown_size_multiplier must be in (0,1]")
        if self.max_abs_funding_rate <= 0:
            raise ValueError("max_abs_funding_rate must be > 0")
        if self.crowded_funding_rate < 0:
            raise ValueError("crowded_funding_rate must be >= 0")
        if self.crowded_funding_rate > self.max_abs_funding_rate:
            raise ValueError("crowded_funding_rate must be <= max_abs_funding_rate")
        if self.funding_avoid_minutes < 0:
            raise ValueError("funding_avoid_minutes must be >= 0")
        if self.funding_window_score_penalty < 0:
            raise ValueError("funding_window_score_penalty must be >= 0")
        if not 0 < self.funding_size_multiplier <= 1:
            raise ValueError("funding_size_multiplier must be in (0,1]")
        for name, v in (
            ("profit_lock_trigger_pct", self.profit_lock_trigger_pct),
            ("profit_lock_retrace_pct", self.profit_lock_retrace_pct),
            ("profit_lock_min_net_pct", self.profit_lock_min_net_pct),
            ("profit_take_pct", self.profit_take_pct),
            ("estimated_taker_fee_pct", self.estimated_taker_fee_pct),
            ("profit_edge_buffer_pct", self.profit_edge_buffer_pct),
        ):
            if v < 0:
                raise ValueError(f"{name} must be >= 0")
        if self.profit_take_min_age_seconds < 0:
            raise ValueError("profit_take_min_age_seconds must be >= 0")
        if not 0 < self.decision_min_consensus <= 1:
            raise ValueError("decision_min_consensus must be in (0,1]")
        if not 0 < self.decision_live_min_consensus <= 1:
            raise ValueError("decision_live_min_consensus must be in (0,1]")
        if self.health_check_seconds < 0:
            raise ValueError("health_check_seconds must be >= 0")
        if self.catalyst_refresh_seconds < 0:
            raise ValueError("catalyst_refresh_seconds must be >= 0")
        if self.catalyst_max_age_seconds <= 0:
            raise ValueError("catalyst_max_age_seconds must be > 0")
        if self.catalyst_score_boost < 0:
            raise ValueError("catalyst_score_boost must be >= 0")
        if self.catalyst_max_dated_event_lag_days < 0:
            raise ValueError("catalyst_max_dated_event_lag_days must be >= 0")
        if not 0 < self.regime_risk_off_size_mult <= 1:
            raise ValueError("regime_risk_off_size_mult must be in (0,1]")
        if self.flow_refresh_seconds < 0:
            raise ValueError("flow_refresh_seconds must be >= 0")
        if self.flow_lookback < 2:
            raise ValueError("flow_lookback must be >= 2")
        for name, v in (
            ("flow_min_oi_change_pct", self.flow_min_oi_change_pct),
            ("flow_taker_buy_ratio", self.flow_taker_buy_ratio),
            ("flow_taker_sell_ratio", self.flow_taker_sell_ratio),
            ("flow_strong_taker_ratio", self.flow_strong_taker_ratio),
            ("flow_crowded_long_ratio", self.flow_crowded_long_ratio),
            ("flow_crowded_short_ratio", self.flow_crowded_short_ratio),
        ):
            if v <= 0:
                raise ValueError(f"{name} must be > 0")
        if self.flow_taker_sell_ratio >= 1:
            raise ValueError("flow_taker_sell_ratio should be below 1")
        if self.flow_taker_buy_ratio <= 1:
            raise ValueError("flow_taker_buy_ratio should be above 1")
        if self.flow_score_boost < 0:
            raise ValueError("flow_score_boost must be >= 0")
        if self.flow_score_penalty < 0:
            raise ValueError("flow_score_penalty must be >= 0")
        if not 0 < self.flow_size_penalty <= 1:
            raise ValueError("flow_size_penalty must be in (0,1]")
        if self.indirect_grid_min_choppiness < 0:
            raise ValueError("indirect_grid_min_choppiness must be >= 0")
        if self.indirect_grid_max_adx <= 0:
            raise ValueError("indirect_grid_max_adx must be > 0")
        for name, v in (
            ("indirect_grid_lower_bbp", self.indirect_grid_lower_bbp),
            ("indirect_grid_upper_bbp", self.indirect_grid_upper_bbp),
            ("indirect_grid_chase_bbp", self.indirect_grid_chase_bbp),
        ):
            if not 0 <= v <= 1:
                raise ValueError(f"{name} must be in [0,1]")
        if self.indirect_grid_lower_bbp >= self.indirect_grid_upper_bbp:
            raise ValueError("indirect grid lower BBP must be below upper BBP")
        if self.indirect_dca_pullback_min_pct < 0:
            raise ValueError("indirect_dca_pullback_min_pct must be >= 0")
        for name, v in (
            ("indirect_grid_score_boost", self.indirect_grid_score_boost),
            ("indirect_grid_edge_penalty", self.indirect_grid_edge_penalty),
            ("indirect_dca_score_boost", self.indirect_dca_score_boost),
            ("indirect_arb_score_boost", self.indirect_arb_score_boost),
            ("indirect_max_score_boost", self.indirect_max_score_boost),
        ):
            if v < 0:
                raise ValueError(f"{name} must be >= 0")
        if self.indirect_martingale_drawdown_cut_pct < 0:
            raise ValueError("indirect_martingale_drawdown_cut_pct must be >= 0")
        if not 1 <= self.indirect_max_size_boost <= 1.5:
            raise ValueError("indirect_max_size_boost must be in [1,1.5]")
        if self.strategy_lab_refresh_loops <= 0:
            raise ValueError("strategy_lab_refresh_loops must be > 0")
        if self.strategy_lab_lookback_hours <= 0:
            raise ValueError("strategy_lab_lookback_hours must be > 0")
        if self.strategy_lab_min_live_trades < 0:
            raise ValueError("strategy_lab_min_live_trades must be >= 0")
        if self.opportunity_radar_refresh_loops <= 0:
            raise ValueError("opportunity_radar_refresh_loops must be > 0")
        if self.opportunity_radar_top_n <= 0:
            raise ValueError("opportunity_radar_top_n must be > 0")
        if self.opportunity_radar_min_quote_volume_usdt < 0:
            raise ValueError("opportunity_radar_min_quote_volume_usdt must be >= 0")

    def __post_init__(self) -> None:
        self.symbols = [s.strip().upper() for s in self.symbols if s.strip()]


config = TradingConfig()

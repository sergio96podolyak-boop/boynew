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
    hft_timeframe: str = field(default_factory=lambda: os.getenv("HFT_TIMEFRAME", "1m"))
    hft_fetch_limit: int = field(default_factory=lambda: _env_int("HFT_FETCH_LIMIT", "200"))

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

    tp_min_pct: float = field(default_factory=lambda: _env_float("TP_MIN_PCT", "0.003"))
    tp_max_pct: float = field(default_factory=lambda: _env_float("TP_MAX_PCT", "0.015"))
    sl_min_pct: float = field(default_factory=lambda: _env_float("SL_MIN_PCT", "0.003"))
    sl_max_pct: float = field(default_factory=lambda: _env_float("SL_MAX_PCT", "0.007"))

    hft_trailing_pct: float = field(default_factory=lambda: _env_float("HFT_TRAILING_PCT", "0.002"))

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

    # ── Telegram ────────────────────────────────────────────────────────────
    telegram_token: str = field(default_factory=lambda: os.getenv("TELEGRAM_TOKEN", ""))
    telegram_chat_id: str = field(default_factory=lambda: os.getenv("TELEGRAM_CHAT_ID", ""))
    telegram_heartbeat_interval: int = field(
        default_factory=lambda: _env_int("TELEGRAM_HEARTBEAT_INTERVAL", "300")
    )

    def validate(self) -> None:
        if not self.paper_trading:
            if not self.api_key or self.api_key == "your_api_key_here":
                raise ValueError("BINANCE_API_KEY must be set for live trading")
            if not self.api_secret or self.api_secret == "your_api_secret_here":
                raise ValueError("BINANCE_API_SECRET must be set for live trading")

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

        if self.hft_min_notional_usdt < 0:
            raise ValueError(f"hft_min_notional_usdt must be >= 0, got {self.hft_min_notional_usdt}")

    def __post_init__(self) -> None:
        self.symbols = [s.strip().upper() for s in self.symbols if s.strip()]


config = TradingConfig()

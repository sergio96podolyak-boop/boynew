"""
Real-time feature engineering module for Binance Futures aggressive trading bot.
Computes technical indicators and market microstructure features for ML models.
"""

import numpy as np
import pandas as pd
import ta
from typing import Dict, List, Tuple


# All feature column names for ML input
FEATURE_NAMES = [
    # Momentum indicators
    'rsi_14',
    'rsi_7',
    'macd',
    'macd_signal',
    'macd_histogram',
    'momentum_3',
    'momentum_5',
    'momentum_10',
    'williams_r_14',
    'cci_20',

    # Trend indicators
    'ema_9',
    'ema_21',
    'ema_50',
    'adx_14',
    'di_plus_14',
    'di_minus_14',

    # Volatility indicators
    'atr_14',
    'bb_upper',
    'bb_middle',
    'bb_lower',
    'bb_percent_b',
    'bb_bandwidth',
    'volatility_5',

    # Volume indicators
    'volume_spike_ratio',

    # Stochastic
    'stoch_k',
    'stoch_d',

    # Price action
    'returns_1',
    'returns_3',
    'returns_5',
    'wick_ratio',

    # Price vs EMAs
    'price_ema9_ratio',
    'price_ema21_ratio',
    'price_ema50_ratio',
    'ema9_ema21_ratio',
    'ema21_ema50_ratio',

    # Microstructure / execution edge
    'choppiness_14',
    'absorption_score',
    'pullback_pct',
    'volume_trend_3',
    'wick_trap_score',
]


def compute_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Compute all technical indicators and features from OHLCV data.

    Args:
        df: DataFrame with columns [open, high, low, close, volume]

    Returns:
        DataFrame with all original columns plus computed features.
    """
    df = df.copy()

    # ========== Momentum Indicators ==========

    # RSI (14-period and 7-period)
    df['rsi_14'] = ta.momentum.rsi(df['close'], window=14)
    df['rsi_7'] = ta.momentum.rsi(df['close'], window=7)

    # MACD
    macd = ta.trend.MACD(df['close'], window_fast=12, window_slow=26, window_sign=9)
    df['macd'] = macd.macd()
    df['macd_signal'] = macd.macd_signal()
    df['macd_histogram'] = macd.macd_diff()

    # Momentum (Rate of Change)
    df['momentum_3'] = ta.momentum.roc(df['close'], window=3)
    df['momentum_5'] = ta.momentum.roc(df['close'], window=5)
    df['momentum_10'] = ta.momentum.roc(df['close'], window=10)

    # Williams %R
    df['williams_r_14'] = ta.momentum.williams_r(
        df['high'], df['low'], df['close'], lbp=14
    )

    # CCI (Commodity Channel Index)
    df['cci_20'] = ta.trend.cci(df['high'], df['low'], df['close'], window=20)

    # ========== Trend Indicators ==========

    # EMA
    df['ema_9'] = ta.trend.ema_indicator(df['close'], window=9)
    df['ema_21'] = ta.trend.ema_indicator(df['close'], window=21)
    df['ema_50'] = ta.trend.ema_indicator(df['close'], window=50)

    # ADX + DI+ / DI-
    adx = ta.trend.ADXIndicator(df['high'], df['low'], df['close'], window=14)
    df['adx_14'] = adx.adx()
    df['di_plus_14'] = adx.adx_pos()
    df['di_minus_14'] = adx.adx_neg()

    # ========== Volatility Indicators ==========

    # ATR
    df['atr_14'] = ta.volatility.average_true_range(
        df['high'], df['low'], df['close'], window=14
    )

    # Bollinger Bands
    bb = ta.volatility.BollingerBands(df['close'], window=20, window_dev=2)
    df['bb_upper'] = bb.bollinger_hband()
    df['bb_middle'] = bb.bollinger_mavg()
    df['bb_lower'] = bb.bollinger_lband()
    df['bb_percent_b'] = bb.bollinger_pband()
    df['bb_bandwidth'] = bb.bollinger_wband()

    # Rolling volatility (5-period std of returns)
    df['volatility_5'] = df['close'].pct_change().rolling(window=5).std()

    # ========== Volume Indicators ==========

    # Volume spike ratio
    volume_ma = df['volume'].rolling(window=20).mean()
    df['volume_spike_ratio'] = df['volume'] / volume_ma.replace(0, 1)

    # ========== Stochastic Oscillator ==========

    stoch = ta.momentum.StochasticOscillator(
        df['high'], df['low'], df['close'], window=14, smooth_window=3
    )
    df['stoch_k'] = stoch.stoch()
    df['stoch_d'] = stoch.stoch_signal()

    # ========== Price Action Features ==========

    # Returns
    df['returns_1'] = df['close'].pct_change(periods=1)
    df['returns_3'] = df['close'].pct_change(periods=3)
    df['returns_5'] = df['close'].pct_change(periods=5)

    # Wick ratio (fake breakout detection)
    # wick_ratio = (high - low) / abs(close - open)
    # High value indicates small body relative to wicks
    body = (df['close'] - df['open']).abs()
    wicks = df['high'] - df['low']
    df['wick_ratio'] = wicks / body.replace(0, 1)

    # Price vs EMAs
    df['price_ema9_ratio'] = df['close'] / df['ema_9'].replace(0, 1)
    df['price_ema21_ratio'] = df['close'] / df['ema_21'].replace(0, 1)
    df['price_ema50_ratio'] = df['close'] / df['ema_50'].replace(0, 1)
    df['ema9_ema21_ratio'] = df['ema_9'] / df['ema_21'].replace(0, 1)
    df['ema21_ema50_ratio'] = df['ema_21'] / df['ema_50'].replace(0, 1)

    # ========== Microstructure / Execution Edge Features ==========

    # Choppiness Index (14): high = ranging/choppy, low = trending
    # CI = 100 * LOG10(SUM(ATR,14) / (highest_high - lowest_low)) / LOG10(14)
    atr_sum_14 = df['atr_14'].rolling(14).sum()
    hh_14 = df['high'].rolling(14).max()
    ll_14 = df['low'].rolling(14).min()
    range_14 = (hh_14 - ll_14).replace(0, 1e-10)
    df['choppiness_14'] = 100 * np.log10(atr_sum_14 / range_14) / np.log10(14)

    # Absorption score: high volume + tiny body = whale absorbing
    # Score 0-1: higher = more absorption detected
    vol_ratio = df['volume'] / volume_ma.replace(0, 1)
    body_pct = (df['close'] - df['open']).abs() / df['close'].replace(0, 1)
    # Absorption = volume spike × inverse body size
    raw_absorption = vol_ratio * (1.0 / (body_pct + 0.0001))
    # Normalize to 0-1 via rolling percentile rank
    df['absorption_score'] = raw_absorption.rolling(50, min_periods=10).apply(
        lambda x: (x.iloc[-1] - x.min()) / (x.max() - x.min() + 1e-10) if len(x) > 1 else 0.0,
        raw=False,
    )

    # Pullback from recent extreme (5-bar): how far price pulled back
    recent_high_5 = df['high'].rolling(5).max()
    recent_low_5 = df['low'].rolling(5).min()
    # For longs: pullback = (recent_high - close) / close
    # For shorts: pullback = (close - recent_low) / close
    # We store the minimum (most favorable) pullback opportunity
    df['pullback_pct'] = np.minimum(
        (recent_high_5 - df['close']) / df['close'].replace(0, 1),
        (df['close'] - recent_low_5) / df['close'].replace(0, 1),
    )

    # Volume trend: ratio of last 3 candles avg volume vs prior 3
    vol_recent_3 = df['volume'].rolling(3).mean()
    vol_prior_3 = df['volume'].shift(3).rolling(3).mean()
    df['volume_trend_3'] = vol_recent_3 / vol_prior_3.replace(0, 1)

    # Wick trap score: detects stop hunts / fake breakouts
    # High wick ratio + reversal close = trap
    upper_wick = df['high'] - np.maximum(df['open'], df['close'])
    lower_wick = np.minimum(df['open'], df['close']) - df['low']
    full_range = (df['high'] - df['low']).replace(0, 1e-10)
    # If candle closed in lower half but had big upper wick → bull trap
    # If candle closed in upper half but had big lower wick → bear trap
    df['wick_trap_score'] = np.maximum(upper_wick, lower_wick) / full_range

    return df


def extract_latest_features(df: pd.DataFrame) -> Dict[str, float]:
    """
    Extract the latest feature values as a flat dictionary.

    Args:
        df: DataFrame with computed features (from compute_features)

    Returns:
        Dictionary with feature names as keys and latest values as values.
        NaN values are replaced with 0.0.
    """
    if df.empty:
        return {name: 0.0 for name in FEATURE_NAMES}

    latest = df.iloc[-1]
    features = {}

    for name in FEATURE_NAMES:
        if name in latest.index:
            value = latest[name]
            # Handle NaN values
            features[name] = float(value) if not pd.isna(value) else 0.0
        else:
            features[name] = 0.0

    return features


def compute_orderbook_imbalance(
    bids: List[Tuple[float, float]],
    asks: List[Tuple[float, float]]
) -> float:
    """
    Compute bid/ask pressure ratio from orderbook.

    Args:
        bids: List of (price, volume) tuples for bid side
        asks: List of (price, volume) tuples for ask side

    Returns:
        Float from -1 to 1 indicating imbalance:
        - 1.0 = maximum buy pressure
        - -1.0 = maximum sell pressure
        - 0.0 = balanced
    """
    if not bids or not asks:
        return 0.0

    # Sum volumes at best 5 levels
    bid_volume = sum(vol for _, vol in bids[:5])
    ask_volume = sum(vol for _, vol in asks[:5])

    total = bid_volume + ask_volume
    if total == 0:
        return 0.0

    # Calculate imbalance: (bid - ask) / (bid + ask)
    imbalance = (bid_volume - ask_volume) / total

    # Clamp to [-1, 1]
    return max(-1.0, min(1.0, imbalance))


def compute_funding_rate_bias(funding_rate: float) -> float:
    """
    Convert funding rate to a bias score.

    Args:
        funding_rate: Funding rate as decimal (e.g., 0.0001 for 0.01%)

    Returns:
        Float from -1 to 1:
        - 1.0 = strong long bias (high positive funding)
        - -1.0 = strong short bias (high negative funding)
        - 0.0 = neutral

    Uses tanh sigmoid to smooth the transition and bound values.
    """
    # Scale factor: 8-hour funding rate of 0.01% is moderate bias
    # So we use a scale where 0.001 (0.1%) maps to ~0.5
    scale = 10.0

    bias = np.tanh(funding_rate * scale)

    return float(bias)


if __name__ == '__main__':
    # Example usage for testing
    import yfinance as yf

    # Download sample data
    data = yf.download('BTC-USD', period='100d', interval='1d', progress=False)

    # Rename columns to match expected format
    df = data[['Open', 'High', 'Low', 'Close', 'Volume']].copy()
    df.columns = ['open', 'high', 'low', 'close', 'volume']

    # Compute features
    featured_df = compute_features(df)

    # Extract latest
    latest_features = extract_latest_features(featured_df)

    print("Latest features:")
    for name, value in sorted(latest_features.items()):
        print(f"  {name}: {value:.6f}")

    # Test orderbook imbalance
    sample_bids = [(100, 1.0), (99.9, 2.0), (99.8, 1.5), (99.7, 1.0), (99.6, 0.5)]
    sample_asks = [(100.1, 0.5), (100.2, 1.0), (100.3, 1.5), (100.4, 2.0), (100.5, 1.0)]
    imbalance = compute_orderbook_imbalance(sample_bids, sample_asks)
    print(f"\nOrderbook imbalance: {imbalance:.4f}")

    # Test funding rate bias
    fr_positive = compute_funding_rate_bias(0.0001)
    fr_negative = compute_funding_rate_bias(-0.0001)
    fr_high = compute_funding_rate_bias(0.001)
    print(f"Funding rate bias (0.01%): {fr_positive:.4f}")
    print(f"Funding rate bias (-0.01%): {fr_negative:.4f}")
    print(f"Funding rate bias (0.1%): {fr_high:.4f}")

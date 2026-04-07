"""
Market Analysis Agent for Binance Futures Trading System.
Computes technical indicators, detects market regime, and returns structured MarketData.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, Any, Optional

import numpy as np
import pandas as pd
import ta
from ta.trend import (
    EMAIndicator,
    MACD,
    ADXIndicator,
)
from ta.momentum import RSIIndicator, StochasticOscillator, WilliamsRIndicator
from ta.volatility import BollingerBands, AverageTrueRange
from ta.trend import SMAIndicator as VolumeSMA

logger = logging.getLogger(__name__)


@dataclass
class MarketRegime:
    """Describes the current market regime."""
    trend: str          # 'uptrend', 'downtrend', 'sideways'
    volatility: str     # 'low', 'medium', 'high'
    regime: str         # 'trending', 'ranging', 'volatile'
    strength: float     # 0.0 – 1.0

    def __str__(self) -> str:
        return f"{self.regime}/{self.trend} (str={self.strength:.2f}, vol={self.volatility})"


@dataclass
class MarketData:
    """Full market snapshot for a single symbol."""
    symbol: str
    timeframe: str
    ohlcv: pd.DataFrame                  # Raw OHLCV DataFrame
    indicators: Dict[str, float]         # Latest indicator values
    regime: MarketRegime
    current_price: float
    atr: float
    timestamp: datetime


class MarketAnalysisAgent:
    """
    Fetches OHLCV data and computes a full suite of technical indicators,
    then classifies the current market regime.
    """

    def __init__(self, config=None):
        from config import TradingConfig
        self.config = config or TradingConfig()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def analyze(self, symbol: str, ohlcv: pd.DataFrame) -> Optional[MarketData]:
        """
        Run full technical analysis on the given OHLCV DataFrame.

        Args:
            symbol: Trading pair symbol, e.g. 'BTCUSDT'
            ohlcv:  DataFrame with columns ['open', 'high', 'low', 'close', 'volume']
                    indexed by datetime (or integer).

        Returns:
            MarketData dataclass, or None if the DataFrame is too short.
        """
        if ohlcv is None or len(ohlcv) < 50:
            logger.warning("%s: Not enough OHLCV data (%d rows) for analysis",
                           symbol, 0 if ohlcv is None else len(ohlcv))
            return None

        try:
            df = ohlcv.copy()
            df = self._compute_indicators(df)
            indicators = self._extract_latest(df)
            regime = self._detect_regime(df, indicators)
            current_price = float(df["close"].iloc[-1])
            atr = float(indicators.get("atr", current_price * 0.01))

            return MarketData(
                symbol=symbol,
                timeframe=self.config.timeframe,
                ohlcv=df,
                indicators=indicators,
                regime=regime,
                current_price=current_price,
                atr=atr,
                timestamp=datetime.now(timezone.utc),
            )
        except Exception as exc:
            logger.exception("MarketAnalysisAgent.analyze failed for %s: %s", symbol, exc)
            return None

    # ------------------------------------------------------------------
    # Indicator computation
    # ------------------------------------------------------------------

    def _compute_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """Compute all technical indicators in-place on df."""
        close = df["close"]
        high  = df["high"]
        low   = df["low"]
        volume = df["volume"]

        # --- EMAs ---
        df["ema9"]   = EMAIndicator(close=close, window=9).ema_indicator()
        df["ema21"]  = EMAIndicator(close=close, window=21).ema_indicator()
        df["ema50"]  = EMAIndicator(close=close, window=50).ema_indicator()
        df["ema200"] = EMAIndicator(close=close, window=200).ema_indicator()

        # --- RSI ---
        rsi_ind = RSIIndicator(close=close, window=14)
        df["rsi"] = rsi_ind.rsi()

        # --- MACD ---
        macd_ind = MACD(close=close, window_slow=26, window_fast=12, window_sign=9)
        df["macd"]          = macd_ind.macd()
        df["macd_signal"]   = macd_ind.macd_signal()
        df["macd_hist"]     = macd_ind.macd_diff()

        # --- Bollinger Bands ---
        bb = BollingerBands(close=close, window=20, window_dev=2)
        df["bb_upper"]  = bb.bollinger_hband()
        df["bb_lower"]  = bb.bollinger_lband()
        df["bb_mid"]    = bb.bollinger_mavg()
        df["bb_pct_b"]  = bb.bollinger_pband()
        df["bb_width"]  = bb.bollinger_wband()

        # --- ATR ---
        atr_ind = AverageTrueRange(high=high, low=low, close=close, window=14)
        df["atr"] = atr_ind.average_true_range()

        # --- Stochastic ---
        stoch = StochasticOscillator(high=high, low=low, close=close, window=14, smooth_window=3)
        df["stoch_k"] = stoch.stoch()
        df["stoch_d"] = stoch.stoch_signal()

        # --- ADX ---
        adx_ind = ADXIndicator(high=high, low=low, close=close, window=14)
        df["adx"]     = adx_ind.adx()
        df["adx_pos"] = adx_ind.adx_pos()
        df["adx_neg"] = adx_ind.adx_neg()

        # --- Volume indicators ---
        df["volume_sma20"] = df["volume"].rolling(window=20).mean()
        df["volume_ratio"] = df["volume"] / df["volume_sma20"].replace(0, np.nan)

        # --- CCI ---
        typical_price = (high + low + close) / 3
        tp_mean = typical_price.rolling(window=20).mean()
        tp_std  = typical_price.rolling(window=20).std()
        df["cci"] = (typical_price - tp_mean) / (0.015 * tp_std.replace(0, np.nan))

        # --- Williams %R ---
        wr = WilliamsRIndicator(high=high, low=low, close=close, lbp=14)
        df["williams_r"] = wr.williams_r()

        # --- Returns ---
        df["returns"] = close.pct_change()

        return df

    # ------------------------------------------------------------------
    # Regime detection
    # ------------------------------------------------------------------

    def _detect_regime(self, df: pd.DataFrame, ind: Dict[str, float]) -> MarketRegime:
        """Classify market regime from indicators."""
        price  = ind.get("close", 0.0)
        ema9   = ind.get("ema9", 0.0)
        ema21  = ind.get("ema21", 0.0)
        ema50  = ind.get("ema50", 0.0)
        adx    = ind.get("adx", 0.0)
        atr    = ind.get("atr", 0.0)
        bb_w   = ind.get("bb_width", 0.0)

        # --- Trend ---
        if (ema9 > 0 and ema21 > 0 and ema50 > 0 and
                ema9 > ema21 > ema50 and price > ema9):
            trend = "uptrend"
        elif (ema9 > 0 and ema21 > 0 and ema50 > 0 and
              ema9 < ema21 < ema50 and price < ema9):
            trend = "downtrend"
        else:
            trend = "sideways"

        # --- Volatility ---
        atr_pct = (atr / price * 100) if price > 0 else 0.0
        if atr_pct < 1.0:
            volatility = "low"
        elif atr_pct < 2.5:
            volatility = "medium"
        else:
            volatility = "high"

        # --- Regime ---
        bb_threshold = 0.05  # Narrow band threshold
        if adx > 25:
            regime = "trending"
        elif adx < 20 and bb_w < bb_threshold:
            regime = "ranging"
        else:
            regime = "volatile"

        # --- Strength (0–1) ---
        adx_strength = min(adx / 50.0, 1.0) if adx > 0 else 0.0
        if trend in ("uptrend", "downtrend"):
            rsi = ind.get("rsi", 50.0)
            rsi_strength = abs(rsi - 50) / 50.0
            strength = (adx_strength + rsi_strength) / 2
        else:
            strength = 1.0 - adx_strength  # Weak trend = high ranging strength

        return MarketRegime(
            trend=trend,
            volatility=volatility,
            regime=regime,
            strength=round(float(strength), 4),
        )

    # ------------------------------------------------------------------
    # Helper: extract latest values as flat dict
    # ------------------------------------------------------------------

    def _extract_latest(self, df: pd.DataFrame) -> Dict[str, float]:
        """Return a flat dict of the latest indicator values."""
        indicator_cols = [
            "open", "high", "low", "close", "volume",
            "ema9", "ema21", "ema50", "ema200",
            "rsi",
            "macd", "macd_signal", "macd_hist",
            "bb_upper", "bb_lower", "bb_mid", "bb_pct_b", "bb_width",
            "atr",
            "stoch_k", "stoch_d",
            "adx", "adx_pos", "adx_neg",
            "volume_sma20", "volume_ratio",
            "cci", "williams_r",
            "returns",
        ]

        latest = {}
        last_row = df.iloc[-1]
        for col in indicator_cols:
            if col in df.columns:
                val = last_row[col]
                latest[col] = float(val) if not (pd.isna(val)) else 0.0

        return latest

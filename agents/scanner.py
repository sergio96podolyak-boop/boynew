import logging
import time
from typing import Dict, List, Optional
import pandas as pd
import requests
import numpy as np

from config import TradingConfig
from agents.features import (
    compute_features,
    extract_latest_features,
    FEATURE_NAMES,
    compute_orderbook_imbalance,
    compute_funding_rate_bias,
)
from agents.model import TradingModel

# Optional: TradeAnalyzer for history-based filtering
try:
    from agents.trade_analyzer import TradeAnalyzer
except ImportError:
    TradeAnalyzer = None  # type: ignore

logger = logging.getLogger(__name__)

BINANCE_FUTURES_BASE = "https://fapi.binance.com"
REQUEST_TIMEOUT = 10
MAX_RETRIES = 3
RETRY_BACKOFF = 1.0


class MarketScanner:
    """Market scanner for Binance Futures to discover and rank trading opportunities."""

    def __init__(self, config: TradingConfig, model: TradingModel, trade_analyzer: Optional['TradeAnalyzer'] = None):
        """
        Initialize the market scanner.

        Args:
            config: Trading configuration object
            model: Trained or untrained TradingModel instance
            trade_analyzer: Optional TradeAnalyzer for history-based filtering
        """
        self.config = config
        self.model = model
        self.trade_analyzer = trade_analyzer
        self.universe: list[str] = []
        self.session = requests.Session()
        self._runtime_blacklist: set = set()  # symbols blacklisted at runtime (e.g. API -4411)
        # Throttle tracking: {symbol: loops_remaining}
        self._throttled: Dict[str, int] = {}
        # Slippage/latency strike counters: {symbol: strike_count}
        self._slippage_strikes: Dict[str, int] = {}
        logger.info(
            f"MarketScanner initialized with scan_top_n={config.scan_top_n}, "
            f"hft_timeframe={config.hft_timeframe}, hft_fetch_limit={config.hft_fetch_limit}"
        )

    def discover_universe(self) -> list[str]:
        """
        Discover top trading symbols by 24h quote volume on Binance Futures.

        Filters:
        - Quote asset: USDT
        - Status: TRADING
        - 24h quoteVolume > 5,000,000

        Returns:
            List of top N symbols sorted by volume (descending)
        """
        try:
            url = f"{BINANCE_FUTURES_BASE}/fapi/v1/ticker/24hr"
            data = self._get_json(url, {})

            if not data or not isinstance(data, list):
                logger.error("Failed to fetch 24h ticker data")
                return []

            # Filter: USDT perpetuals, min 24h quote volume
            # Note: Binance Futures ticker/24hr does not include a "status" field
            # Symbols requiring special agreements or with precision issues
            _BLACKLIST = {"BZUSDT", "PAXGUSDT", "XAUUSDT", "XAGUSDT"}
            filtered = [
                ticker
                for ticker in data
                if ticker.get("symbol", "").endswith("USDT")
                and not ticker.get("symbol", "").endswith("_USDT")  # exclude delivery contracts
                and float(ticker.get("quoteVolume", 0)) > 5_000_000
                and ticker.get("symbol", "") not in _BLACKLIST
            ]

            # Sort by quoteVolume descending
            filtered.sort(
                key=lambda x: float(x.get("quoteVolume", 0)), reverse=True
            )

            # Take top N
            symbols = [ticker["symbol"] for ticker in filtered[: self.config.scan_top_n]]

            logger.info(
                f"Discovered {len(symbols)} top symbols from {len(data)} total pairs"
            )
            self.universe = symbols
            return symbols

        except Exception as e:
            logger.error(f"Error discovering universe: {e}", exc_info=True)
            return []

    def fetch_ohlcv(
        self, symbol: str, interval: str = "1m", limit: int = 200
    ) -> Optional[pd.DataFrame]:
        """
        Fetch OHLCV candle data from Binance Futures.

        Args:
            symbol: Trading symbol (e.g., 'BTCUSDT')
            interval: Candle interval (default '1m')
            limit: Number of candles to fetch (default 200)

        Returns:
            DataFrame with columns [open, high, low, close, volume] or None on failure
        """
        try:
            url = f"{BINANCE_FUTURES_BASE}/fapi/v1/klines"
            params = {"symbol": symbol, "interval": interval, "limit": limit}

            data = self._get_json(url, params)
            if not data or not isinstance(data, list):
                logger.warning(f"No OHLCV data for {symbol}")
                return None

            # Parse klines: [time, open, high, low, close, volume, ...]
            rows = []
            for candle in data:
                try:
                    rows.append(
                        {
                            "open": float(candle[1]),
                            "high": float(candle[2]),
                            "low": float(candle[3]),
                            "close": float(candle[4]),
                            "volume": float(candle[7]),  # quote asset volume
                        }
                    )
                except (ValueError, IndexError) as e:
                    logger.warning(f"Failed to parse candle for {symbol}: {e}")
                    continue

            if not rows:
                logger.warning(f"No valid candles parsed for {symbol}")
                return None

            df = pd.DataFrame(rows)
            logger.debug(f"Fetched {len(df)} candles for {symbol}")
            return df

        except Exception as e:
            logger.error(f"Error fetching OHLCV for {symbol}: {e}", exc_info=True)
            return None

    def fetch_funding_rate(self, symbol: str) -> float:
        """
        Fetch current funding rate from Binance Futures.

        Args:
            symbol: Trading symbol (e.g., 'BTCUSDT')

        Returns:
            Funding rate as float, 0.0 on failure
        """
        try:
            url = f"{BINANCE_FUTURES_BASE}/fapi/v1/premiumIndex"
            params = {"symbol": symbol}

            data = self._get_json(url, params)
            if not data:
                logger.warning(f"No premium index data for {symbol}")
                return 0.0

            funding_rate = float(data.get("lastFundingRate", 0.0))
            logger.debug(f"Funding rate for {symbol}: {funding_rate:.6f}")
            return funding_rate

        except Exception as e:
            logger.error(f"Error fetching funding rate for {symbol}: {e}", exc_info=True)
            return 0.0

    def tick_throttles(self) -> None:
        """Decrement throttle cooldowns each loop. Called from main loop."""
        expired = []
        for sym, remaining in self._throttled.items():
            self._throttled[sym] = remaining - 1
            if self._throttled[sym] <= 0:
                expired.append(sym)
        for sym in expired:
            del self._throttled[sym]
            self._slippage_strikes.pop(sym, None)
            logger.info("Throttle expired for %s", sym)

    def record_slippage_strike(self, symbol: str) -> None:
        """Record a slippage/latency strike. Throttle if threshold reached."""
        count = self._slippage_strikes.get(symbol, 0) + 1
        self._slippage_strikes[symbol] = count
        if count >= self.config.throttle_strikes:
            self._throttled[symbol] = self.config.throttle_cooldown_loops
            logger.warning(
                "Throttling %s for %d loops (slippage strikes=%d)",
                symbol, self.config.throttle_cooldown_loops, count,
            )

    def fetch_spread(self, symbol: str) -> float:
        """Fetch bid-ask spread as fraction of mid price. Returns 0.0 on failure."""
        try:
            url = f"{BINANCE_FUTURES_BASE}/fapi/v1/ticker/bookTicker"
            data = self._get_json(url, {"symbol": symbol})
            if data:
                bid = float(data.get("bidPrice", 0))
                ask = float(data.get("askPrice", 0))
                mid = (bid + ask) / 2.0
                if mid > 0:
                    return (ask - bid) / mid
        except Exception as e:
            logger.debug("Spread fetch failed for %s: %s", symbol, e)
        return 0.0

    def _check_trade_quality(
        self, symbol: str, df_features: pd.DataFrame, direction: str
    ) -> Optional[str]:
        """
        Run trade quality filters. Returns rejection reason or None if passed.

        Filters:
        1. Throttled symbols (slippage/latency)
        2. Volume spike (confirms direction)
        3. Choppiness (skip ranging markets)
        4. Micro-pullback (avoid late entries)
        5. Absorption detection (whale activity warning)
        """
        # Throttle check
        if symbol in self._throttled:
            return f"throttled ({self._throttled[symbol]} loops left)"

        latest = df_features.iloc[-1]

        # Volume spike: require recent volume confirms move
        vol_spike = latest.get("volume_spike_ratio", 0)
        if vol_spike < self.config.min_volume_spike:
            return f"low volume (spike={vol_spike:.2f} < {self.config.min_volume_spike})"

        # Choppiness: skip choppy/ranging markets
        chop = latest.get("choppiness_14", 50)
        if not pd.isna(chop) and chop > self.config.max_choppiness:
            return f"choppy market (CI={chop:.1f} > {self.config.max_choppiness})"

        # Micro-pullback: avoid chasing — require a dip before entry
        pullback = latest.get("pullback_pct", 0)
        if not pd.isna(pullback) and pullback < self.config.min_pullback_pct:
            return f"no pullback (pb={pullback:.4%} < {self.config.min_pullback_pct:.4%})"

        # Absorption warning: high volume + no movement = whale absorbing
        absorption = latest.get("absorption_score", 0)
        if not pd.isna(absorption) and absorption > 0.85:
            # Not a hard block — reduce score instead (handled in caller)
            logger.info("%s: high absorption detected (%.2f) — possible whale activity", symbol, absorption)

        return None

    def scan_and_rank(self, symbols: Optional[List[str]] = None) -> List[Dict]:
        """
        Scan universe and rank opportunities by ML score and fundamentals.
        Now includes trade quality filters for execution edge.

        Args:
            symbols: Optional override list of symbols to scan.
                     If None, uses self.universe (populated by discover_universe).

        Returns:
            List of opportunity dicts with keys:
            - symbol, direction, score, probability, atr, entry_price, features, funding_bias
        """
        opportunities = []

        if symbols is not None:
            self.universe = symbols

        if not self.universe:
            logger.warning("Universe is empty, discovering...")
            self.discover_universe()

        if not self.universe:
            logger.error("Failed to discover trading universe")
            return []

        logger.info(
            f"Scanning {len(self.universe)} symbols (hft_timeframe={self.config.hft_timeframe})"
        )

        # Get adaptive score threshold from trade history (if available)
        effective_score_entry = self.config.score_entry
        if self.trade_analyzer:
            effective_score_entry = self.trade_analyzer.get_effective_score_entry()
            if effective_score_entry != self.config.score_entry:
                logger.info(
                    "Scanner using adaptive score_entry=%.0f (base=%.0f, from trade history)",
                    effective_score_entry, self.config.score_entry,
                )

        for symbol in self.universe:
            if symbol in self._runtime_blacklist:
                continue
            if symbol in self._throttled:
                continue
            # History-based blacklist: skip symbols that consistently lose
            if self.trade_analyzer and self.trade_analyzer.should_skip_symbol(symbol):
                logger.debug("%s: SKIPPED — blacklisted by trade history (losing symbol)", symbol)
                continue
            try:
                # Fetch OHLCV
                df = self.fetch_ohlcv(
                    symbol,
                    interval=self.config.hft_timeframe,
                    limit=self.config.hft_fetch_limit,
                )

                if df is None or len(df) < 20:
                    logger.debug(f"Insufficient data for {symbol}")
                    continue

                last_close = float(df["close"].iloc[-1])
                if last_close < self.config.min_symbol_price_usdt:
                    logger.debug(
                        "%s: price %.6f < min_symbol_price_usdt %.4f — skip",
                        symbol,
                        last_close,
                        self.config.min_symbol_price_usdt,
                    )
                    continue

                # Compute features
                df_features = compute_features(df)
                if df_features is None or df_features.empty:
                    logger.debug(f"Failed to compute features for {symbol}")
                    continue

                # Retrain model if needed
                if self.model.should_retrain(symbol) or not self.model.is_trained(symbol):
                    logger.info(f"Retraining model for {symbol} with {len(df_features)} samples")
                    self.model.train(
                        symbol, df_features, FEATURE_NAMES,
                        horizon=5, threshold=0.0005,  # 0.05% for 1m candles
                    )

                # Get ML prediction
                latest_features = extract_latest_features(df_features)
                if not latest_features:
                    logger.debug(f"Failed to extract latest features for {symbol}")
                    continue

                direction, score, probability = self.model.predict(symbol, latest_features, FEATURE_NAMES)

                # Early score filter — skip expensive checks for low scores
                # Use adaptive threshold from trade history
                if score < effective_score_entry:
                    logger.debug(f"{symbol}: score {score:.3f} below threshold {effective_score_entry}")
                    continue

                # ── Trade quality filters (execution edge) ──
                reject_reason = self._check_trade_quality(symbol, df_features, direction)
                if reject_reason:
                    logger.debug("%s: filtered — %s", symbol, reject_reason)
                    continue

                # Spread check (requires API call — only for candidates that passed all other filters)
                spread = self.fetch_spread(symbol)
                if spread > self.config.max_spread_pct:
                    logger.debug(
                        "%s: spread %.4f%% > max %.4f%% — skip",
                        symbol, spread * 100, self.config.max_spread_pct * 100,
                    )
                    continue

                # Fetch funding rate
                funding_rate = self.fetch_funding_rate(symbol)
                funding_bias = compute_funding_rate_bias(funding_rate)

                # Penalize score if funding rate opposes direction
                # High positive funding + LONG = crowded long, reduce score
                # High negative funding + SHORT = crowded short, reduce score
                funding_penalty = 0.0
                if direction == "LONG" and funding_rate > 0.0005:
                    funding_penalty = min(5.0, funding_rate * 5000)
                elif direction == "SHORT" and funding_rate < -0.0005:
                    funding_penalty = min(5.0, abs(funding_rate) * 5000)
                adjusted_score = score - funding_penalty

                # Absorption penalty (soft)
                latest = df_features.iloc[-1]
                absorption = latest.get("absorption_score", 0)
                if not pd.isna(absorption) and absorption > 0.7:
                    adjusted_score -= (absorption - 0.7) * 10  # up to -3 points

                # History-based per-symbol score adjustment
                if self.trade_analyzer:
                    hist_adj = self.trade_analyzer.get_score_adjustment(symbol)
                    if hist_adj != 0:
                        adjusted_score += hist_adj
                        logger.debug("%s: history adjustment %+.1f → score=%.1f", symbol, hist_adj, adjusted_score)

                    # Direction penalty: if history shows one direction wins more
                    dir_adj = self.trade_analyzer.get_direction_penalty(direction)
                    if dir_adj != 0:
                        adjusted_score += dir_adj

                # Calculate ATR
                atr = self._compute_atr(df)

                # Volatility filter
                entry_px = float(df["close"].iloc[-1])
                if self.config.min_atr_pct > 0 and entry_px > 0:
                    atr_pct = atr / entry_px
                    if atr_pct < self.config.min_atr_pct:
                        logger.debug(
                            f"{symbol}: ATR {atr_pct:.4%} below min {self.config.min_atr_pct:.4%} — skipping"
                        )
                        continue

                # Wick trap detection: if recent candle shows trap pattern opposing direction
                wick_trap = latest.get("wick_trap_score", 0)
                if not pd.isna(wick_trap) and wick_trap > 0.7:
                    # Check if trap opposes our direction
                    candle_bullish = float(latest.get("returns_1", 0)) > 0
                    if (direction == "LONG" and not candle_bullish) or (direction == "SHORT" and candle_bullish):
                        logger.debug("%s: wick trap detected opposing %s — skip", symbol, direction)
                        continue

                # Final score filter after adjustments (using adaptive threshold)
                if adjusted_score < effective_score_entry:
                    logger.debug("%s: adjusted score %.1f < threshold %.0f (penalties applied)", symbol, adjusted_score, effective_score_entry)
                    continue

                # Build opportunity dict
                opportunity = {
                    "symbol": symbol,
                    "direction": direction,
                    "score": adjusted_score,
                    "raw_score": score,
                    "probability": probability,
                    "atr": atr,
                    "entry_price": entry_px,
                    "spread": spread,
                    "features": latest_features.to_dict() if hasattr(latest_features, 'to_dict') else dict(latest_features),
                    "funding_bias": funding_bias,
                    "signal_ts": time.time(),  # for slippage tracking
                }

                opportunities.append(opportunity)
                logger.debug(
                    "%s: score=%.1f (raw=%.1f) dir=%s prob=%.3f spread=%.4f%% funding=%.6f",
                    symbol, adjusted_score, score, direction, probability,
                    spread * 100, funding_bias,
                )

            except Exception as e:
                logger.error(f"Error scanning {symbol}: {e}", exc_info=True)
                continue

            # Small delay to avoid rate limiting
            time.sleep(0.1)

        # Sort by adjusted score descending
        opportunities.sort(key=lambda x: x["score"], reverse=True)

        logger.info(
            f"Ranked {len(opportunities)} opportunities (filtered by score >= {self.config.score_entry})"
        )
        return opportunities

    def _get_json(self, url: str, params: dict) -> Optional[dict]:
        """
        Helper method to fetch JSON from Binance with retry logic.

        Args:
            url: Full API endpoint URL
            params: Query parameters dict

        Returns:
            Parsed JSON dict or None on failure
        """
        for attempt in range(MAX_RETRIES):
            try:
                response = self.session.get(
                    url, params=params, timeout=REQUEST_TIMEOUT
                )
                response.raise_for_status()
                return response.json()

            except requests.exceptions.Timeout:
                logger.warning(f"Timeout on {url} (attempt {attempt + 1}/{MAX_RETRIES})")
                if attempt < MAX_RETRIES - 1:
                    time.sleep(RETRY_BACKOFF)
                continue

            except requests.exceptions.ConnectionError as e:
                logger.warning(f"Connection error on {url} (attempt {attempt + 1}/{MAX_RETRIES}): {e}")
                if attempt < MAX_RETRIES - 1:
                    time.sleep(RETRY_BACKOFF)
                continue

            except requests.exceptions.HTTPError as e:
                if response.status_code == 429:
                    # Rate limit: exponential backoff
                    backoff = RETRY_BACKOFF * (2 ** attempt)
                    logger.warning(f"Rate limited, backing off {backoff}s")
                    time.sleep(backoff)
                    continue
                else:
                    logger.error(f"HTTP error {response.status_code} on {url}: {e}")
                    return None

            except Exception as e:
                logger.error(f"Error fetching {url}: {e}", exc_info=True)
                return None

        logger.error(f"Failed to fetch {url} after {MAX_RETRIES} attempts")
        return None

    def _compute_atr(self, df: pd.DataFrame, period: int = 14) -> float:
        """
        Compute Average True Range (ATR) from OHLCV data.

        Args:
            df: DataFrame with OHLC columns
            period: ATR period (default 14)

        Returns:
            ATR value as float
        """
        try:
            if len(df) < period + 1:
                # Fallback: simple range
                return float((df["high"] - df["low"]).mean())

            # Compute True Range
            tr1 = df["high"] - df["low"]
            tr2 = (df["high"] - df["close"].shift()).abs()
            tr3 = (df["low"] - df["close"].shift()).abs()
            tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

            # Compute ATR
            atr = tr.rolling(period).mean().iloc[-1]
            return float(atr) if not np.isnan(atr) else 0.0

        except Exception as e:
            logger.warning(f"Error computing ATR: {e}")
            return float((df["high"] - df["low"]).mean())

    def close(self):
        """Close session and cleanup resources."""
        try:
            self.session.close()
            logger.info("MarketScanner session closed")
        except Exception as e:
            logger.error(f"Error closing session: {e}")

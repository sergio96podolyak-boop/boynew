import json
import logging
import os
import time
from typing import Dict, List, Optional
import pandas as pd
import requests
import numpy as np
from datetime import datetime, time as dt_time
from zoneinfo import ZoneInfo

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
DEX_RADAR_FILE = os.path.join(
    os.path.dirname(__file__), "..", "data", "opportunity_radar.json"
)
DEX_RADAR_MAX_AGE_SECONDS = 1800

US_EQUITY_LIKE_BASES = {
    "AAPL", "AMD", "AMZN", "AVGO", "BABA", "COIN", "CRCL", "GLW",
    "GOOGL", "HOOD", "INTC", "META", "MRVL", "MSFT", "MSTR", "NFLX",
    "NVDA", "ORCL", "PLTR", "QQQ", "SMCI", "SOXL", "SPY", "SQQQ",
    "TQQQ", "TSLA", "UBER", "EWY", "KORU",
}
KR_EQUITY_LIKE_BASES = {"SKHYNIX"}
STATIC_SYMBOL_BLACKLIST = {"BZUSDT", "PAXGUSDT", "XAUUSDT", "XAGUSDT"}


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
        self._discovery_tags: Dict[str, Dict[str, object]] = {}
        # Throttle tracking: {symbol: loops_remaining}
        self._throttled: Dict[str, int] = {}
        # Slippage/latency strike counters: {symbol: strike_count}
        self._slippage_strikes: Dict[str, int] = {}
        logger.info(
            f"MarketScanner initialized with scan_top_n={config.scan_top_n}, "
            f"hft_timeframe={config.hft_timeframe}, hft_fetch_limit={config.hft_fetch_limit}"
        )

    @staticmethod
    def _safe_float(value: object, default: float = 0.0) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    def discover_universe(self) -> list[str]:
        """
        Discover Binance Futures symbols worth scanning.

        The universe is built from three independent buckets:
        - fresh USDT perpetual listings from exchangeInfo/onboardDate
        - high positive 24h momentum with real quote volume
        - established high-volume USDT perpetuals

        Returns:
            Combined symbol list, deduplicated in priority order.
        """
        try:
            ticker_url = f"{BINANCE_FUTURES_BASE}/fapi/v1/ticker/24hr"
            exchange_url = f"{BINANCE_FUTURES_BASE}/fapi/v1/exchangeInfo"
            data = self._get_json(ticker_url, {})

            if not data or not isinstance(data, list):
                logger.error("Failed to fetch 24h ticker data")
                return []

            exchange_info = self._get_json(exchange_url, {}) or {}
            metadata: Dict[str, Dict[str, object]] = {}
            valid_symbols: set[str] = set()
            now_ms = time.time() * 1000.0

            if isinstance(exchange_info, dict):
                for meta in exchange_info.get("symbols", []):
                    symbol = meta.get("symbol", "")
                    if (
                        meta.get("quoteAsset") == "USDT"
                        and meta.get("contractType") == "PERPETUAL"
                        and meta.get("status") == "TRADING"
                        and symbol
                        and symbol not in STATIC_SYMBOL_BLACKLIST
                    ):
                        valid_symbols.add(symbol)
                        onboard_ms = self._safe_float(meta.get("onboardDate"), 0.0)
                        age_days = (now_ms - onboard_ms) / 86_400_000.0 if onboard_ms else 99999.0
                        metadata[symbol] = {
                            "base_asset": meta.get("baseAsset", ""),
                            "onboard_date_ms": onboard_ms,
                            "listing_age_days": max(0.0, age_days),
                        }

            def is_tradable(ticker: dict) -> bool:
                symbol = ticker.get("symbol", "")
                if not symbol.endswith("USDT") or symbol.endswith("_USDT"):
                    return False
                if symbol in STATIC_SYMBOL_BLACKLIST:
                    return False
                if valid_symbols and symbol not in valid_symbols:
                    return False
                return True

            tradable = [ticker for ticker in data if is_tradable(ticker)]
            ticker_by_symbol = {ticker["symbol"]: ticker for ticker in tradable if ticker.get("symbol")}

            volume_candidates = [
                ticker
                for ticker in tradable
                if self._safe_float(ticker.get("quoteVolume")) > 5_000_000
            ]
            volume_candidates.sort(
                key=lambda x: self._safe_float(x.get("quoteVolume")), reverse=True
            )
            top_volume = volume_candidates[: self.config.scan_top_n]

            fresh_listings: list[dict] = []
            if self.config.new_listing_scan_enabled and self.config.new_listing_top_n > 0:
                for symbol, meta in metadata.items():
                    ticker = ticker_by_symbol.get(symbol)
                    if not ticker:
                        continue
                    age_days = self._safe_float(meta.get("listing_age_days"), 99999.0)
                    quote_volume = self._safe_float(ticker.get("quoteVolume"))
                    if (
                        age_days <= self.config.new_listing_max_age_days
                        and quote_volume >= self.config.new_listing_min_quote_volume_usdt
                    ):
                        fresh_listings.append(ticker)
                fresh_listings.sort(
                    key=lambda x: (
                        self._safe_float(metadata.get(x["symbol"], {}).get("listing_age_days"), 99999.0),
                        -self._safe_float(x.get("quoteVolume")),
                    )
                )
                fresh_listings = fresh_listings[: self.config.new_listing_top_n]

            momentum_candidates: list[dict] = []
            if self.config.momentum_scan_enabled and self.config.momentum_top_n > 0:
                # Two-sided: top gainers AND top losers. A -20% dump is as
                # tradable as a +20% pump (the model decides direction).
                momentum_candidates = [
                    ticker
                    for ticker in tradable
                    if self._safe_float(ticker.get("quoteVolume")) >= self.config.momentum_min_quote_volume_usdt
                    and abs(self._safe_float(ticker.get("priceChangePercent"))) >= self.config.momentum_min_price_change_pct
                ]
                momentum_candidates.sort(
                    key=lambda x: (
                        abs(self._safe_float(x.get("priceChangePercent"))),
                        self._safe_float(x.get("quoteVolume")),
                    ),
                    reverse=True,
                )
                momentum_candidates = momentum_candidates[: self.config.momentum_top_n]

            dex_hot: list[dict] = []
            if self.config.dex_hot_scan_enabled and self.config.dex_hot_top_n > 0:
                for binance_symbol in self._read_dex_hot_symbols():
                    ticker = ticker_by_symbol.get(binance_symbol)
                    if ticker is not None:
                        dex_hot.append(ticker)
                    if len(dex_hot) >= self.config.dex_hot_top_n:
                        break

            tags: Dict[str, Dict[str, object]] = {}

            def tag_symbol(ticker: dict, name: str) -> str:
                symbol = ticker.get("symbol", "")
                if not symbol:
                    return ""
                info = tags.setdefault(symbol, {})
                info[name] = True
                info["quote_volume"] = self._safe_float(ticker.get("quoteVolume"))
                info["price_change_pct"] = self._safe_float(ticker.get("priceChangePercent"))
                if symbol in metadata:
                    info.update(metadata[symbol])
                return symbol

            priority_groups = (
                [(tag_symbol(t, "fresh_listing"), t) for t in fresh_listings]
                + [(tag_symbol(t, "hot_momentum"), t) for t in momentum_candidates]
                + [(tag_symbol(t, "dex_hot"), t) for t in dex_hot]
                + [(tag_symbol(t, "top_volume"), t) for t in top_volume]
            )
            symbols: list[str] = []
            seen = set()
            for symbol, _ticker in priority_groups:
                if symbol and symbol not in seen:
                    seen.add(symbol)
                    symbols.append(symbol)

            logger.info(
                "Discovered %d symbols from %d tickers (top_volume=%d, fresh=%d, momentum=%d, dex=%d)",
                len(symbols),
                len(data),
                len(top_volume),
                len(fresh_listings),
                len(momentum_candidates),
                len(dex_hot),
            )
            if dex_hot:
                logger.info(
                    "DEX hot movers injected: %s",
                    ", ".join(t["symbol"] for t in dex_hot),
                )
            if fresh_listings:
                logger.info(
                    "Fresh listings watched: %s",
                    ", ".join(
                        f"{t['symbol']}({self._safe_float(metadata.get(t['symbol'], {}).get('listing_age_days'), 0.0):.1f}d)"
                        for t in fresh_listings[:8]
                    ),
                )
            if momentum_candidates:
                logger.info(
                    "Hot momentum watched: %s",
                    ", ".join(
                        f"{t['symbol']}({self._safe_float(t.get('priceChangePercent')):+.1f}%, "
                        f"{self._safe_float(t.get('quoteVolume')) / 1_000_000:.0f}M)"
                        for t in momentum_candidates[:8]
                    ),
                )
            self._discovery_tags = tags
            self.universe = symbols
            return symbols

        except Exception as e:
            logger.error(f"Error discovering universe: {e}", exc_info=True)
            return []

    def _read_dex_hot_symbols(self) -> list[str]:
        """
        Binance symbols of hot DEX movers from the opportunity radar snapshot.

        Read-only and failure-soft: returns [] when the snapshot is missing,
        stale, or malformed. Injected symbols still pass every normal entry
        gate (min price, blacklist, score threshold, committee, risk caps).
        """
        try:
            with open(DEX_RADAR_FILE, encoding="utf-8") as fh:
                snap = json.load(fh)
            age = time.time() - float(snap.get("updated_ts", 0) or 0)
            if age > DEX_RADAR_MAX_AGE_SECONDS:
                return []
            for product in snap.get("products", []):
                if product.get("key") == "dex_watch":
                    return [
                        str(c.get("binance_symbol", ""))
                        for c in product.get("candidates", [])
                        if c.get("on_binance") and c.get("binance_symbol")
                    ]
        except FileNotFoundError:
            pass
        except Exception as exc:
            logger.debug("DEX hot symbols read failed: %s", exc)
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

    def fetch_funding_context(self, symbol: str) -> Dict[str, float]:
        """Fetch funding rate plus time to the next funding event."""
        try:
            url = f"{BINANCE_FUTURES_BASE}/fapi/v1/premiumIndex"
            data = self._get_json(url, {"symbol": symbol})
            if not data:
                return {"rate": 0.0, "minutes_to_funding": 9999.0, "next_funding_time": 0.0}
            rate = float(data.get("lastFundingRate", 0.0) or 0.0)
            next_ms = float(data.get("nextFundingTime", 0.0) or 0.0)
            now_ms = time.time() * 1000.0
            minutes_to = (next_ms - now_ms) / 60000.0 if next_ms > 0 else 9999.0
            return {
                "rate": rate,
                "minutes_to_funding": max(0.0, minutes_to),
                "next_funding_time": next_ms,
            }
        except Exception as e:
            logger.debug("Funding context fetch failed for %s: %s", symbol, e)
            return {"rate": 0.0, "minutes_to_funding": 9999.0, "next_funding_time": 0.0}

    @staticmethod
    def _base_asset(symbol: str) -> str:
        symbol = (symbol or "").upper()
        for quote in ("USDT", "USDC", "BUSD", "USD"):
            if symbol.endswith(quote):
                return symbol[: -len(quote)]
        return symbol

    def _primary_market_closed_reason(self, symbol: str) -> Optional[str]:
        """Block stock/ETF-like perps when their primary cash market is closed."""
        if not self.config.block_stock_like_perps_outside_primary_hours:
            return None
        base = self._base_asset(symbol)
        if base in US_EQUITY_LIKE_BASES:
            now = datetime.now(ZoneInfo("America/New_York"))
            if now.weekday() >= 5 or not (dt_time(9, 30) <= now.time() <= dt_time(16, 0)):
                return f"{symbol}: primary US market closed ({now.strftime('%H:%M ET')})"
        elif base in KR_EQUITY_LIKE_BASES:
            now = datetime.now(ZoneInfo("Asia/Seoul"))
            if now.weekday() >= 5 or not (dt_time(9, 0) <= now.time() <= dt_time(15, 30)):
                return f"{symbol}: primary KR market closed ({now.strftime('%H:%M KST')})"
        return None

    def _funding_risk_adjustment(
        self,
        symbol: str,
        direction: str,
        funding: Dict[str, float],
    ) -> tuple[Optional[str], float, float, str]:
        """
        Return (hard_reject, score_penalty, size_multiplier, reason).

        Funding can swing around settlement windows and crowded positioning.
        Favorable funding never boosts score; it only avoids penalties.
        """
        rate = float(funding.get("rate", 0.0) or 0.0)
        abs_rate = abs(rate)
        minutes_to = float(funding.get("minutes_to_funding", 9999.0) or 9999.0)
        near_funding = minutes_to <= self.config.funding_avoid_minutes

        if abs_rate >= self.config.max_abs_funding_rate:
            return (
                f"{symbol}: funding {rate * 100:.3f}% exceeds hard cap "
                f"{self.config.max_abs_funding_rate * 100:.3f}%",
                0.0,
                0.0,
                "funding hard cap",
            )

        penalty = 0.0
        size_mult = 1.0
        reasons = []

        crowded_against_trade = (
            (direction == "LONG" and rate > self.config.crowded_funding_rate)
            or (direction == "SHORT" and rate < -self.config.crowded_funding_rate)
        )
        if crowded_against_trade:
            scaled = abs_rate / max(self.config.crowded_funding_rate, 1e-9)
            penalty += min(8.0, scaled * 3.0)
            size_mult *= self.config.funding_size_multiplier
            reasons.append(f"crowded funding {rate * 100:.3f}% against {direction}")

        if near_funding:
            penalty += self.config.funding_window_score_penalty
            size_mult *= self.config.funding_size_multiplier
            reasons.append(f"{minutes_to:.0f}m to funding")
            if abs_rate >= self.config.crowded_funding_rate:
                return (
                    f"{symbol}: funding window risk ({minutes_to:.0f}m, rate={rate * 100:.3f}%)",
                    penalty,
                    size_mult,
                    "; ".join(reasons),
                )

        return None, penalty, max(0.1, min(1.0, size_mult)), "; ".join(reasons)

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

    def _technical_confluence(self, df_features: pd.DataFrame) -> tuple[str, float, str]:
        """
        Fallback signal when ML has no demonstrated edge.

        Scores only plain, inspectable technical agreement. This is intentionally
        conservative and still flows through quality filters, committee, risk and
        live guard before any order can happen.
        """
        if df_features is None or len(df_features) < 60:
            return "FLAT", 0.0, "insufficient features"

        latest = df_features.iloc[-1]
        prev = df_features.iloc[-2]

        def val(name: str, default: float = 0.0) -> float:
            x = latest.get(name, default)
            return default if pd.isna(x) else float(x)

        rsi = val("rsi_14", 50.0)
        adx = val("adx_14", 0.0)
        di_plus = val("di_plus_14", 0.0)
        di_minus = val("di_minus_14", 0.0)
        macd_hist = val("macd_histogram", 0.0)
        prev_macd_value = prev.get("macd_histogram", 0.0)
        prev_macd_hist = 0.0 if pd.isna(prev_macd_value) else float(prev_macd_value)
        price_ema9 = val("price_ema9_ratio", 1.0)
        price_ema21 = val("price_ema21_ratio", 1.0)
        ema9_ema21 = val("ema9_ema21_ratio", 1.0)
        ema21_ema50 = val("ema21_ema50_ratio", 1.0)
        vol_spike = val("volume_spike_ratio", 1.0)
        pullback = val("pullback_pct", 0.0)
        chop = val("choppiness_14", 50.0)
        bbp = val("bb_percent_b", 0.5)
        ret_3 = val("returns_3", 0.0)

        long_score = 45.0
        short_score = 45.0
        long_reasons = []
        short_reasons = []

        if price_ema9 > 1 and price_ema21 > 1 and ema9_ema21 > 1 and ema21_ema50 > 1:
            long_score += 12
            long_reasons.append("EMA stack up")
        if price_ema9 < 1 and price_ema21 < 1 and ema9_ema21 < 1 and ema21_ema50 < 1:
            short_score += 12
            short_reasons.append("EMA stack down")

        if adx >= 18 and di_plus > di_minus:
            long_score += min(12, (adx - 12) * 0.6)
            long_reasons.append("ADX +DI")
        if adx >= 18 and di_minus > di_plus:
            short_score += min(12, (adx - 12) * 0.6)
            short_reasons.append("ADX -DI")

        if macd_hist > 0 and macd_hist >= prev_macd_hist:
            long_score += 8
            long_reasons.append("MACD rising")
        if macd_hist < 0 and macd_hist <= prev_macd_hist:
            short_score += 8
            short_reasons.append("MACD falling")

        if 45 <= rsi <= 68:
            long_score += 7
            long_reasons.append("RSI healthy")
        if 32 <= rsi <= 55:
            short_score += 7
            short_reasons.append("RSI healthy")
        if rsi >= 78:
            long_score -= 10
            short_score += 4
        if rsi <= 22:
            short_score -= 10
            long_score += 4

        if vol_spike >= self.config.min_volume_spike:
            long_score += 5
            short_score += 5
        if pullback >= self.config.min_pullback_pct:
            long_score += 4
            short_score += 4
        if chop <= self.config.max_choppiness:
            long_score += 4
            short_score += 4
        else:
            long_score -= 8
            short_score -= 8
        if 0.15 <= bbp <= 0.85:
            long_score += 2
            short_score += 2
        if ret_3 > 0:
            long_score += 3
        elif ret_3 < 0:
            short_score += 3

        if long_score >= short_score:
            return "LONG", min(100.0, long_score), ", ".join(long_reasons) or "technical long"
        return "SHORT", min(100.0, short_score), ", ".join(short_reasons) or "technical short"

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
            primary_market_reason = self._primary_market_closed_reason(symbol)
            if primary_market_reason:
                logger.debug("%s: filtered — %s", symbol, primary_market_reason)
                continue
            # History-based blacklist: skip symbols that consistently lose
            if self.trade_analyzer and self.trade_analyzer.should_skip_symbol(symbol):
                logger.debug("%s: SKIPPED — blacklisted by trade history (losing symbol)", symbol)
                continue
            try:
                # Fetch OHLCV
                fetch_limit = max(self.config.hft_fetch_limit, self.config.min_ml_training_candles)
                df = self.fetch_ohlcv(
                    symbol,
                    interval=self.config.hft_timeframe,
                    limit=fetch_limit,
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
                signal_source = "ml"
                technical_reason = ""
                ml_score = score
                model_stats = self.model.get_training_stats(symbol) or {}
                model_reliability = self._safe_float(model_stats.get("reliability"), 0.0)

                # Early score filter — skip expensive checks for low scores
                # Use adaptive threshold from trade history
                if score < effective_score_entry:
                    if self.config.technical_fallback_signals:
                        tech_dir, tech_score, technical_reason = self._technical_confluence(df_features)
                        technical_threshold = max(
                            effective_score_entry,
                            self.config.technical_fallback_min_score,
                        )
                        if self.config.technical_fallback_strong_mode and model_reliability < 0.10:
                            technical_threshold = max(
                                technical_threshold,
                                self.config.technical_fallback_strong_min_score,
                            )
                            latest = df_features.iloc[-1]
                            vol_spike = self._safe_float(latest.get("volume_spike_ratio"), 0.0)
                            min_fallback_vol = (
                                self.config.min_volume_spike
                                * self.config.technical_fallback_volume_mult
                            )
                            if vol_spike < min_fallback_vol:
                                logger.debug(
                                    "%s: technical fallback blocked — model reliability %.2f "
                                    "and volume %.2f < %.2f",
                                    symbol,
                                    model_reliability,
                                    vol_spike,
                                    min_fallback_vol,
                                )
                                continue
                            technical_reason = (
                                f"{technical_reason}; strong fallback "
                                f"(ML reliability {model_reliability:.2f}, volume {vol_spike:.2f}x)"
                            )
                        if tech_score >= technical_threshold and tech_dir in ("LONG", "SHORT"):
                            direction = tech_dir
                            score = tech_score
                            probability = tech_score / 100.0
                            signal_source = "technical_confluence"
                            logger.info(
                                "%s: ML score %.1f low, technical fallback %s score=%.1f (%s)",
                                symbol, ml_score, direction, tech_score, technical_reason,
                            )
                        else:
                            logger.debug(
                                f"{symbol}: score {score:.3f} below threshold {effective_score_entry}; "
                                f"technical={tech_score:.1f}"
                            )
                            continue
                    else:
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

                # Fetch funding context and reject/penalize crowded funding risk
                funding_ctx = self.fetch_funding_context(symbol)
                funding_rate = funding_ctx["rate"]
                funding_bias = compute_funding_rate_bias(funding_rate)
                funding_reject, funding_guard_penalty, funding_size_mult, funding_guard_reason = (
                    self._funding_risk_adjustment(symbol, direction, funding_ctx)
                )
                if funding_reject:
                    logger.debug("%s: filtered — %s", symbol, funding_reject)
                    continue

                # Penalize score if funding rate opposes direction
                # High positive funding + LONG = crowded long, reduce score
                # High negative funding + SHORT = crowded short, reduce score
                funding_penalty = funding_guard_penalty
                if direction == "LONG" and funding_rate > 0.0005:
                    funding_penalty += min(5.0, funding_rate * 5000)
                elif direction == "SHORT" and funding_rate < -0.0005:
                    funding_penalty += min(5.0, abs(funding_rate) * 5000)
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

                discovery_tags = self._discovery_tags.get(symbol, {})
                discovery_bonus = 0.0
                if self.config.discovery_score_bonus_max > 0 and direction == "LONG":
                    if discovery_tags.get("hot_momentum"):
                        discovery_bonus += 3.0
                    if discovery_tags.get("fresh_listing"):
                        discovery_bonus += 2.0
                    if self._safe_float(discovery_tags.get("price_change_pct")) >= 20.0:
                        discovery_bonus += 1.0
                    discovery_bonus = min(self.config.discovery_score_bonus_max, discovery_bonus)
                    if discovery_bonus > 0:
                        adjusted_score += discovery_bonus
                        logger.debug(
                            "%s: discovery bonus +%.1f (%s) → score=%.1f",
                            symbol,
                            discovery_bonus,
                            ",".join(k for k, v in discovery_tags.items() if v is True),
                            adjusted_score,
                        )

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
                    "funding_rate": funding_rate,
                    "minutes_to_funding": funding_ctx.get("minutes_to_funding", 9999.0),
                    "funding_penalty": funding_penalty,
                    "funding_size_multiplier": funding_size_mult,
                    "funding_risk": funding_guard_reason,
                    "discovery_tags": discovery_tags,
                    "discovery_bonus": discovery_bonus,
                    "model_reliability": model_reliability,
                    "signal_ts": time.time(),  # for slippage tracking
                    "source": signal_source,
                    "technical_reason": technical_reason,
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

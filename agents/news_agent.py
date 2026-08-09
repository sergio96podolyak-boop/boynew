"""
NewsAgent — סוכן חדשות/סנטימנט שוק.

סורק מקורות ציבוריים חינמיים (בלי מפתחות API) כדי לתת תמונת מצב על "מצב הרוח" של
השוק, ומפרסם אותה גם ל-monitor (כסוכן בקונסטלציה) וגם לקובץ data/sentiment.json
שהדשבורד קורא.

מקורות:
  • Crypto Fear & Greed Index  — api.alternative.me  (סנטימנט כללי 0..100)
  • Binance funding / open interest — fapi.binance.com (מיצוב הקהל לכל מטבע)
  • כותרות חדשות — RSS ציבורי (best-effort, להצגה בלבד)

חשוב: זה שכבת *מידע*, לא מכונת רווח. הוא לא מבטיח רווח — הוא נותן הקשר.
"""

from __future__ import annotations

import json
import logging
import os
import time
import xml.etree.ElementTree as ET
from typing import Any, Dict, List, Optional

import requests

logger = logging.getLogger(__name__)

_FNG_URL = "https://api.alternative.me/fng/?limit=1"
_FUNDING_URL = "https://fapi.binance.com/fapi/v1/premiumIndex"
_RSS_FEEDS = [
    "https://cointelegraph.com/rss",
    "https://www.coindesk.com/arc/outboundfeeds/rss/",
    "https://cryptopotato.com/feed/",
    "https://decrypt.co/feed",
]
_SENTIMENT_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "sentiment.json")

_NEGATIVE_WORDS = {
    "hack", "hacked", "exploit", "stolen", "lawsuit", "sued", "charges",
    "ban", "banned", "crackdown", "investigation", "bankrupt", "bankruptcy",
    "liquidation", "liquidations", "outflow", "outflows", "crash", "plunge",
    "selloff", "sell-off", "fraud", "halt", "outage", "breach", "fine",
}
_POSITIVE_WORDS = {
    "approval", "approved", "inflow", "inflows", "record", "adoption",
    "partnership", "launch", "surge", "rally", "breakout", "institutional",
    "etf", "upgrade", "integrates", "accumulates",
}
_SYMBOL_ALIASES = {
    "BTC": {"btc", "bitcoin"},
    "ETH": {"eth", "ethereum", "ether"},
    "SOL": {"sol", "solana"},
    "BNB": {"bnb", "binance coin"},
    "XRP": {"xrp", "ripple"},
    "DOGE": {"doge", "dogecoin"},
    "ADA": {"ada", "cardano"},
    "AVAX": {"avax", "avalanche"},
    "LINK": {"link", "chainlink"},
    "ZEC": {"zec", "zcash"},
}


class NewsAgent:
    """Aggregates free market-sentiment signals and publishes a snapshot."""

    def __init__(
        self,
        monitor: Optional[Any] = None,
        refresh_seconds: float = 180.0,
        config: Optional[Any] = None,
    ):
        self.monitor = monitor
        self.refresh_seconds = refresh_seconds
        self.config = config
        self._last_refresh: float = 0.0
        self.snapshot: Dict[str, Any] = {}

    # ------------------------------------------------------------------
    # Individual sources (each best-effort, never raises)
    # ------------------------------------------------------------------

    def _fetch_fear_greed(self) -> Optional[Dict[str, Any]]:
        try:
            r = requests.get(_FNG_URL, timeout=10)
            r.raise_for_status()
            d = r.json()["data"][0]
            return {
                "value": int(d["value"]),
                "classification": d.get("value_classification", ""),
            }
        except Exception as exc:
            logger.debug("Fear&Greed fetch failed: %s", exc)
            return None

    def _fetch_funding(self) -> Dict[str, List[Dict[str, Any]]]:
        """Top crowd-positioning extremes from Binance funding rate (USDT perps)."""
        try:
            r = requests.get(_FUNDING_URL, timeout=12)
            r.raise_for_status()
            rows = r.json()
            data = []
            for x in rows:
                sym = x.get("symbol", "")
                if not sym.endswith("USDT"):
                    continue
                fr = float(x.get("lastFundingRate", 0) or 0)
                data.append({"symbol": sym, "funding": fr})
            data.sort(key=lambda v: v["funding"])
            # Most negative funding = crowd heavily short; most positive = crowd heavily long
            return {"crowd_short": data[:5], "crowd_long": data[-5:][::-1]}
        except Exception as exc:
            logger.debug("Funding fetch failed: %s", exc)
            return {"crowd_short": [], "crowd_long": []}

    def _fetch_headlines(self, limit: int = 6) -> List[Dict[str, str]]:
        out: List[Dict[str, str]] = []
        seen = set()
        for feed in _RSS_FEEDS:
            try:
                r = requests.get(feed, timeout=10, headers={"User-Agent": "Mozilla/5.0"})
                r.raise_for_status()
                root = ET.fromstring(r.content)
                items = root.findall(".//item")[:limit]
                for it in items:
                    title = (it.findtext("title") or "").strip()
                    if title and title not in seen:
                        seen.add(title)
                        out.append({"title": title, "link": (it.findtext("link") or "").strip()})
                    if len(out) >= limit:
                        return out
            except Exception as exc:
                logger.debug("RSS %s failed: %s", feed, exc)
        return out

    @staticmethod
    def _base_asset(symbol: str) -> str:
        symbol = (symbol or "").upper()
        for quote in ("USDT", "BUSD", "USDC", "USD"):
            if symbol.endswith(quote):
                return symbol[: -len(quote)]
        return symbol

    @classmethod
    def _symbol_terms(cls, symbol: str) -> set:
        base = cls._base_asset(symbol)
        terms = {base.lower()}
        terms.update(_SYMBOL_ALIASES.get(base, set()))
        return terms

    @staticmethod
    def _tokenize(title: str) -> set:
        clean = "".join(ch.lower() if ch.isalnum() or ch in "- " else " " for ch in title)
        return set(clean.split())

    def _headline_sentiment(self, headlines: List[Dict[str, str]]) -> Dict[str, Any]:
        scored = []
        total = 0
        negative = 0
        positive = 0
        for item in headlines:
            title = item.get("title", "")
            tokens = self._tokenize(title)
            neg = len(tokens & _NEGATIVE_WORDS)
            pos = len(tokens & _POSITIVE_WORDS)
            score = pos - neg
            if neg:
                negative += 1
            if pos:
                positive += 1
            total += score
            scored.append({**item, "score": score, "negative_hits": neg, "positive_hits": pos})
        norm = max(-1.0, min(1.0, total / max(3, len(headlines) * 2)))
        return {
            "score": norm,
            "negative_count": negative,
            "positive_count": positive,
            "items": scored,
        }

    # ------------------------------------------------------------------
    # Derived market bias
    # ------------------------------------------------------------------

    @staticmethod
    def _bias_from_fng(value: int) -> Dict[str, Any]:
        """
        Contrarian read of the Fear & Greed index — a crude, well-known heuristic:
        extreme fear historically precedes bounces, extreme greed precedes pullbacks.
        Returns a label + a small size multiplier (never increases risk above 1.0).
        """
        if value <= 20:
            return {"label": "פחד קיצוני — נטייה קונטרה ללונג", "dir": "LONG", "size_mult": 1.0}
        if value <= 40:
            return {"label": "פחד — זהירות, נטייה קלה ללונג", "dir": "LONG", "size_mult": 0.8}
        if value >= 80:
            return {"label": "חמדנות קיצונית — סיכון לתיקון", "dir": "SHORT", "size_mult": 0.6}
        if value >= 60:
            return {"label": "חמדנות — להדק יציאות", "dir": "SHORT", "size_mult": 0.8}
        return {"label": "ניטרלי", "dir": "NEUTRAL", "size_mult": 1.0}

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------

    def maybe_refresh(self) -> Optional[Dict[str, Any]]:
        """Refresh at most once per refresh_seconds. Returns snapshot if refreshed."""
        now = time.time()
        if now - self._last_refresh < self.refresh_seconds and self.snapshot:
            return None
        self._last_refresh = now
        return self.refresh()

    def refresh(self) -> Dict[str, Any]:
        if self.monitor:
            self.monitor.report("News", "scan", "סורק סנטימנט: Fear&Greed, funding, כותרות", status="working")

        prev = self.snapshot or {}
        # Each source is best-effort; keep the last good value if a fetch misses
        # (e.g. a transient timeout) instead of blanking the panel.
        fng = self._fetch_fear_greed() or prev.get("fear_greed")
        funding = self._fetch_funding()
        if not funding.get("crowd_long") and not funding.get("crowd_short"):
            funding = prev.get("funding") or funding
        headlines = self._fetch_headlines() or prev.get("headlines") or []
        headline_sentiment = self._headline_sentiment(headlines)
        bias = self._bias_from_fng(fng["value"]) if fng else {"label": "—", "dir": "NEUTRAL", "size_mult": 1.0}

        snap = {
            "updated_at": time.time(),
            "fear_greed": fng,
            "bias": bias,
            "funding": funding,
            "headlines": headlines,
            "headline_sentiment": headline_sentiment,
        }
        self.snapshot = snap
        self._write_snapshot(snap)

        if self.monitor:
            if fng:
                detail = f"Fear&Greed {fng['value']} ({fng['classification']}) | {bias['label']}"
            else:
                detail = "מקור סנטימנט לא זמין כרגע"
            self.monitor.report("News", "sentiment", detail, status="active", force=True)
        return snap

    def assess_trade(self, symbol: str, direction: str) -> Dict[str, Any]:
        """
        Return a per-trade news/sentiment assessment.

        The output is intentionally conservative: news can reduce size, reduce
        score, or block obvious high-impact negative headlines, but it cannot
        increase risk above 1.0.
        """
        snap = self.snapshot or self.refresh()
        if not snap:
            return {
                "approved": True,
                "vote": False,
                "score_adjustment": -1.0,
                "size_multiplier": 0.85,
                "hard_block": False,
                "reason": "news unavailable",
            }

        age = time.time() - float(snap.get("updated_at", 0) or 0)
        max_age = float(getattr(self.config, "news_max_age_seconds", 900) or 900)
        if age > max_age:
            hard = bool(getattr(self.config, "block_on_stale_news", False))
            return {
                "approved": not hard,
                "vote": False,
                "score_adjustment": -2.0,
                "size_multiplier": 0.80,
                "hard_block": hard,
                "reason": f"news stale ({age / 60:.0f}m old)",
            }

        score_adj = 0.0
        size_mult = 1.0
        reasons: List[str] = []
        hard_block = False

        fng = snap.get("fear_greed") or {}
        val = fng.get("value")
        if isinstance(val, int):
            if val >= 85 and direction == "LONG":
                score_adj -= 4.0
                size_mult *= 0.70
                reasons.append("extreme greed against LONG")
            elif val <= 15 and direction == "SHORT":
                score_adj -= 4.0
                size_mult *= 0.70
                reasons.append("extreme fear against SHORT")
            elif (val <= 35 and direction == "LONG") or (val >= 65 and direction == "SHORT"):
                score_adj += 1.0
                reasons.append("contrarian sentiment aligned")

        headline_sent = snap.get("headline_sentiment") or {}
        generic_news_score = float(headline_sent.get("score", 0.0) or 0.0)
        if generic_news_score < -0.20:
            score_adj -= min(4.0, abs(generic_news_score) * 8)
            size_mult *= 0.80
            reasons.append("negative crypto headlines")
        elif generic_news_score > 0.25:
            score_adj += min(1.0, generic_news_score * 2)
            reasons.append("positive crypto headlines")

        terms = self._symbol_terms(symbol)
        for item in headline_sent.get("items", []):
            title = item.get("title", "")
            title_l = title.lower()
            related = any(term and term in title_l for term in terms)
            if related and item.get("negative_hits", 0) > 0:
                score_adj -= 8.0
                size_mult *= 0.50
                reasons.append(f"negative headline for {symbol}")
                if bool(getattr(self.config, "news_negative_headline_block", True)):
                    hard_block = True
                break

        approved = not hard_block
        vote = approved and score_adj >= -3.0
        return {
            "approved": approved,
            "vote": vote,
            "score_adjustment": score_adj,
            "size_multiplier": max(0.10, min(1.0, size_mult)),
            "hard_block": hard_block,
            "reason": "; ".join(reasons) if reasons else "news neutral",
        }

    def _write_snapshot(self, snap: Dict[str, Any]) -> None:
        try:
            os.makedirs(os.path.dirname(_SENTIMENT_FILE), exist_ok=True)
            with open(_SENTIMENT_FILE, "w", encoding="utf-8") as f:
                json.dump(snap, f, ensure_ascii=False)
        except Exception as exc:
            logger.debug("sentiment snapshot write failed: %s", exc)

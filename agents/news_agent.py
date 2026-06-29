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
]
_SENTIMENT_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "sentiment.json")


class NewsAgent:
    """Aggregates free market-sentiment signals and publishes a snapshot."""

    def __init__(self, monitor: Optional[Any] = None, refresh_seconds: float = 180.0):
        self.monitor = monitor
        self.refresh_seconds = refresh_seconds
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
        for feed in _RSS_FEEDS:
            try:
                r = requests.get(feed, timeout=10, headers={"User-Agent": "Mozilla/5.0"})
                r.raise_for_status()
                root = ET.fromstring(r.content)
                items = root.findall(".//item")[:limit]
                out = []
                for it in items:
                    title = (it.findtext("title") or "").strip()
                    if title:
                        out.append({"title": title, "link": (it.findtext("link") or "").strip()})
                if out:
                    return out
            except Exception as exc:
                logger.debug("RSS %s failed: %s", feed, exc)
        return []

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

        fng = self._fetch_fear_greed()
        funding = self._fetch_funding()
        headlines = self._fetch_headlines()
        bias = self._bias_from_fng(fng["value"]) if fng else {"label": "—", "dir": "NEUTRAL", "size_mult": 1.0}

        snap = {
            "updated_at": time.time(),
            "fear_greed": fng,
            "bias": bias,
            "funding": funding,
            "headlines": headlines,
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

    def _write_snapshot(self, snap: Dict[str, Any]) -> None:
        try:
            os.makedirs(os.path.dirname(_SENTIMENT_FILE), exist_ok=True)
            with open(_SENTIMENT_FILE, "w", encoding="utf-8") as f:
                json.dump(snap, f, ensure_ascii=False)
        except Exception as exc:
            logger.debug("sentiment snapshot write failed: %s", exc)

"""
CatalystAgent - online event radar for market-moving crypto catalysts.

The agent watches verified-ish public surfaces such as Binance announcements
and major crypto RSS feeds. It does not place orders. Its job is to surface
symbol-specific catalysts and let the decision committee reduce/block risk
around dangerous events or add only a small boost for positive catalysts.
"""

from __future__ import annotations

import json
import logging
import os
import re
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Set
from urllib.parse import quote

import requests

logger = logging.getLogger(__name__)

_CATALYST_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "catalyst_radar.json")
_BINANCE_ANNOUNCEMENT_URL = (
    "https://www.binance.com/bapi/composite/v1/public/cms/article/catalog/list/query"
)

# Public catalog ids used by the Binance announcement website. The endpoint is
# best-effort: if Binance changes it, the RSS sources still keep the agent alive.
_BINANCE_CATALOGS = {
    "futures": 48,
    "latest": 49,
    "delisting": 161,
    "wallet_general": 157,
}

_RSS_FEEDS = [
    "https://cointelegraph.com/rss",
    "https://www.coindesk.com/arc/outboundfeeds/rss/",
    "https://decrypt.co/feed",
    "https://cryptopotato.com/feed/",
]

_STOP_TOKENS = {
    "A", "AN", "AND", "ARE", "AS", "AT", "BY", "FOR", "FROM", "IN", "IS",
    "IT", "NEW", "NO", "OF", "ON", "OR", "THE", "TO", "UP", "USD", "USDT",
    "USDC", "USDⓈ", "WITH", "WILL", "BINANCE", "FUTURES", "SPOT", "MARGIN",
    "MARGined", "COIN", "TOKEN", "TOKENS", "TRADING", "PAIR", "PAIRS",
    "CONTRACT", "CONTRACTS", "PERPETUAL", "NOTICE", "UPDATED", "REMOVAL",
    "REMOVE", "REMOVES", "DELIST", "DELISTS", "DELISTING", "LIST", "LISTS",
    "LAUNCH", "LAUNCHES", "LAUNCHPOOL", "MEGADROP", "HODLER", "AIRDROP",
    "AIRDROPS", "EARN", "LOAN", "ALPHA", "SUPPORT", "SUPPORTS", "ANNOUNCED",
    "INTRODUCING", "COMPLETED",
}

_ALIASES = {
    "BTC": {"btc", "bitcoin"},
    "ETH": {"eth", "ethereum", "ether"},
    "SOL": {"sol", "solana"},
    "BNB": {"bnb", "binance coin"},
    "XRP": {"xrp", "ripple"},
    "DOGE": {"doge", "dogecoin"},
    "ADA": {"ada", "cardano"},
    "AVAX": {"avax", "avalanche"},
    "LINK": {"link", "chainlink"},
    "TON": {"ton", "toncoin"},
}

_CRITICAL_NEGATIVE = {
    "delist", "delisting", "remove", "removal", "cease trading", "trading will cease",
    "halt", "suspend", "suspension", "exploit", "hacked", "hack", "security breach",
    "bankruptcy", "insolvent", "fraud", "rug", "rugpull",
}
_NEGATIVE = {
    "lawsuit", "sued", "charges", "investigation", "probe", "crackdown", "ban",
    "outage", "downtime", "vulnerability", "incident", "stolen", "withdrawals paused",
    "deposits suspended", "warning", "monitoring tag",
}
_POSITIVE = {
    "list", "listing", "lists", "new trading pair", "new trading pairs", "will launch",
    "launches", "launchpool", "megadrop", "hodler airdrop", "airdrop", "support",
    "integrates", "integration", "mainnet", "upgrade completed", "rebranding completed",
    "partnership", "approval", "approved", "etf", "record inflow",
}
_VOLATILITY = {
    "protected mechanism", "volatility", "high volatility", "funding", "leverage update",
}


class CatalystAgent:
    """Fetches and scores market-moving catalysts from public online sources."""

    def __init__(
        self,
        config: Any,
        monitor: Optional[Any] = None,
        refresh_seconds: Optional[float] = None,
    ):
        self.config = config
        self.monitor = monitor
        self.refresh_seconds = float(
            refresh_seconds
            if refresh_seconds is not None
            else getattr(config, "catalyst_refresh_seconds", 90)
        )
        self.snapshot: Dict[str, Any] = {}
        self._last_refresh: float = 0.0

    def maybe_refresh(self) -> Optional[Dict[str, Any]]:
        now = time.time()
        if now - self._last_refresh < self.refresh_seconds and self.snapshot:
            return None
        self._last_refresh = now
        return self.refresh()

    def refresh(self) -> Dict[str, Any]:
        if self.monitor:
            self.monitor.report(
                "Catalyst",
                "scan",
                "סורק קטליזטורים: Binance announcements, RSS, listing/delisting",
                status="working",
            )

        raw_items = self._fetch_binance_announcements()
        raw_items.extend(self._fetch_rss_items())

        events = [self._classify_item(item) for item in raw_items]
        events = self._dedupe_events(events)
        events.sort(key=lambda e: (abs(float(e.get("score", 0))), e.get("received_at", 0)), reverse=True)

        symbol_map: Dict[str, Dict[str, Any]] = {}
        for event in events:
            for sym in event.get("symbols", []):
                row = symbol_map.setdefault(sym, {"symbol": sym, "score": 0.0, "events": []})
                row["score"] += float(event.get("score", 0.0) or 0.0)
                row["events"].append(event)

        watchlist = sorted(
            symbol_map.values(),
            key=lambda r: (abs(float(r.get("score", 0.0))), len(r.get("events", []))),
            reverse=True,
        )[:20]

        critical = [e for e in events if e.get("impact") == "critical"]
        positive = [e for e in events if e.get("kind") == "positive"]
        negative = [e for e in events if e.get("kind") == "negative"]
        snap = {
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "updated_ts": time.time(),
            "summary": {
                "events": len(events),
                "critical": len(critical),
                "positive": len(positive),
                "negative": len(negative),
                "symbols": len(symbol_map),
            },
            "events": events[:80],
            "watchlist": watchlist,
        }
        self.snapshot = snap
        self._write_json(snap)

        if self.monitor:
            best = watchlist[0] if watchlist else {}
            self.monitor.report(
                "Catalyst",
                "scan",
                (
                    f"{len(events)} אירועים | קריטי={len(critical)} | "
                    f"מוביל={best.get('symbol', '—')} {float(best.get('score', 0) or 0):+.1f}"
                ),
                status="active",
                severity="WARNING" if critical else "INFO",
                force=True,
            )
        return snap

    def assess_trade(self, symbol: str, direction: str) -> Dict[str, Any]:
        snap = self.snapshot or self.refresh()
        max_age = float(getattr(self.config, "catalyst_max_age_seconds", 900) or 900)
        age = time.time() - float(snap.get("updated_ts", 0) or 0)
        if age > max_age:
            return {
                "approved": True,
                "vote": False,
                "score_adjustment": -1.5,
                "size_multiplier": 0.85,
                "hard_block": False,
                "reason": f"catalysts stale ({age / 60:.0f}m)",
            }

        base = self._base_asset(symbol)
        related = [
            e for e in snap.get("events", [])
            if self._event_mentions_base(e, base)
        ]
        if not related:
            return {
                "approved": True,
                "vote": True,
                "score_adjustment": 0.0,
                "size_multiplier": 1.0,
                "hard_block": False,
                "reason": "no catalyst",
            }

        score_adj = 0.0
        size_mult = 1.0
        hard_block = False
        reasons: List[str] = []
        max_boost = float(getattr(self.config, "catalyst_score_boost", 3.0) or 3.0)
        negative_block = bool(getattr(self.config, "catalyst_negative_block", True))

        for event in related[:5]:
            kind = event.get("kind")
            impact = event.get("impact")
            title = str(event.get("title", ""))
            if impact == "critical":
                if negative_block:
                    hard_block = True
                score_adj -= 10.0
                size_mult *= 0.25
                reasons.append(f"critical: {title[:70]}")
                continue
            if kind == "negative":
                if direction == "LONG":
                    score_adj -= 6.0 if impact == "high" else 3.0
                    size_mult *= 0.55
                else:
                    score_adj += 1.0
                    size_mult *= 0.85
                reasons.append(f"negative: {title[:70]}")
            elif kind == "positive":
                if direction == "LONG":
                    score_adj += min(max_boost, max(1.0, float(event.get("score", 0) or 0) * 0.55))
                    size_mult *= 1.0
                else:
                    score_adj -= 3.0
                    size_mult *= 0.70
                reasons.append(f"positive: {title[:70]}")
            elif kind == "volatility":
                score_adj -= 1.0
                size_mult *= 0.90
                reasons.append(f"volatile: {title[:70]}")

        approved = not hard_block
        return {
            "approved": approved,
            "vote": approved and score_adj >= -4.0,
            "score_adjustment": score_adj,
            "size_multiplier": max(0.10, min(1.0, size_mult)),
            "hard_block": hard_block,
            "reason": "; ".join(reasons[:3]) if reasons else "catalyst neutral",
        }

    def _fetch_binance_announcements(self) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        headers = {"User-Agent": "Mozilla/5.0"}
        for name, catalog_id in _BINANCE_CATALOGS.items():
            try:
                resp = requests.get(
                    _BINANCE_ANNOUNCEMENT_URL,
                    params={"catalogId": catalog_id, "pageNo": 1, "pageSize": 12},
                    headers=headers,
                    timeout=10,
                )
                resp.raise_for_status()
                payload = resp.json()
                for article in (payload.get("data") or {}).get("articles", []) or []:
                    title = str(article.get("title") or "").strip()
                    code = str(article.get("code") or "").strip()
                    if not title or self._dated_event_is_stale(title):
                        continue
                    link = (
                        f"https://www.binance.com/en/support/announcement/detail/{quote(code)}"
                        if code else "https://www.binance.com/en/support/announcement"
                    )
                    out.append({
                        "source": f"Binance:{name}",
                        "title": title,
                        "link": link,
                        "received_at": time.time(),
                    })
            except Exception as exc:
                logger.debug("Binance catalyst fetch failed (%s): %s", name, exc)
        return out

    def _fetch_rss_items(self) -> List[Dict[str, Any]]:
        feeds = list(_RSS_FEEDS)
        extra = str(os.getenv("CATALYST_EXTRA_RSS_FEEDS", "") or "").strip()
        if extra:
            feeds.extend(x.strip() for x in extra.split(",") if x.strip())

        out: List[Dict[str, Any]] = []
        headers = {"User-Agent": "Mozilla/5.0"}
        for feed in feeds:
            try:
                resp = requests.get(feed, headers=headers, timeout=10)
                resp.raise_for_status()
                root = ET.fromstring(resp.content)
                for item in root.findall(".//item")[:10]:
                    title = (item.findtext("title") or "").strip()
                    if not title:
                        continue
                    out.append({
                        "source": self._source_name(feed),
                        "title": title,
                        "link": (item.findtext("link") or "").strip(),
                        "received_at": time.time(),
                    })
            except Exception as exc:
                logger.debug("RSS catalyst fetch failed (%s): %s", feed, exc)
        return out

    def _classify_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        title = str(item.get("title") or "")
        text = title.lower()
        symbols = sorted(self._extract_symbols(title))

        kind = "neutral"
        impact = "low"
        score = 0.0
        if self._has_keyword(text, _CRITICAL_NEGATIVE):
            kind = "negative"
            impact = "critical"
            score = -10.0
        elif self._has_keyword(text, _NEGATIVE):
            kind = "negative"
            impact = "high"
            score = -5.0
        elif self._has_keyword(text, _POSITIVE):
            kind = "positive"
            impact = (
                "high"
                if self._has_keyword(text, ("listing", "will launch", "launchpool", "megadrop"))
                else "medium"
            )
            score = 4.0 if impact == "high" else 2.0
        elif self._has_keyword(text, _VOLATILITY):
            kind = "volatility"
            impact = "medium"
            score = -1.0

        return {
            "source": item.get("source", "unknown"),
            "title": title,
            "link": item.get("link", ""),
            "symbols": symbols,
            "kind": kind,
            "impact": impact,
            "score": score,
            "received_at": float(item.get("received_at", time.time()) or time.time()),
        }

    def _extract_symbols(self, title: str) -> Set[str]:
        text = title.upper().replace("Ⓢ", "S")
        found: Set[str] = set()

        for token in re.findall(r"\b[A-Z0-9]{2,15}USDT\b", text):
            found.add(token)

        for token in re.findall(r"\(([A-Z0-9]{2,12})\)", text):
            if token not in _STOP_TOKENS:
                found.add(f"{token}USDT")

        for token in re.findall(r"\$([A-Z0-9]{2,12})\b", text):
            if token not in _STOP_TOKENS:
                found.add(f"{token}USDT")

        # Delisting/listing titles often list bare tickers separated by commas.
        if any(word in text.lower() for word in ("delist", "remove", "listing", "airdrop", "launchpool")):
            for token in re.findall(r"\b[A-Z][A-Z0-9]{1,9}\b", text):
                if token not in _STOP_TOKENS and not token.endswith("USD"):
                    found.add(f"{token}USDT")

        return found

    def _dedupe_events(self, events: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
        out = []
        seen = set()
        for event in events:
            key = (event.get("source"), event.get("title"))
            if key in seen:
                continue
            seen.add(key)
            out.append(event)
        return out

    @staticmethod
    def _has_keyword(text: str, keywords: Iterable[str]) -> bool:
        for keyword in keywords:
            pattern = rf"(?<![a-z0-9]){re.escape(keyword.lower())}(?![a-z0-9])"
            if re.search(pattern, text):
                return True
        return False

    def _dated_event_is_stale(self, title: str) -> bool:
        match = re.search(r"\b(20\d{2}-\d{2}-\d{2})\b", title)
        if not match:
            return False
        max_lag_days = float(
            getattr(self.config, "catalyst_max_dated_event_lag_days", 3) or 3
        )
        try:
            event_date = datetime.strptime(match.group(1), "%Y-%m-%d").date()
            lag_days = (datetime.now(timezone.utc).date() - event_date).days
            return lag_days > max_lag_days
        except ValueError:
            return False

    @staticmethod
    def _base_asset(symbol: str) -> str:
        symbol = (symbol or "").upper()
        for quote_asset in ("USDT", "USDC", "BUSD", "USD"):
            if symbol.endswith(quote_asset):
                return symbol[: -len(quote_asset)]
        return symbol

    def _event_mentions_base(self, event: Dict[str, Any], base: str) -> bool:
        base = base.upper()
        if not base:
            return False
        if f"{base}USDT" in set(event.get("symbols") or []):
            return True
        title = str(event.get("title") or "").lower()
        terms = {base.lower(), *(_ALIASES.get(base, set()))}
        return any(re.search(rf"(?<![a-z0-9]){re.escape(term)}(?![a-z0-9])", title) for term in terms)

    @staticmethod
    def _source_name(feed: str) -> str:
        if "cointelegraph" in feed:
            return "Cointelegraph"
        if "coindesk" in feed:
            return "CoinDesk"
        if "decrypt" in feed:
            return "Decrypt"
        if "cryptopotato" in feed:
            return "CryptoPotato"
        return feed

    def _write_json(self, snap: Dict[str, Any]) -> None:
        try:
            os.makedirs(os.path.dirname(_CATALYST_FILE), exist_ok=True)
            with open(_CATALYST_FILE, "w", encoding="utf-8") as fh:
                json.dump(snap, fh, ensure_ascii=False, indent=2)
        except Exception as exc:
            logger.debug("catalyst snapshot write failed: %s", exc)

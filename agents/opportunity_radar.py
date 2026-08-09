"""
OpportunityRadarAgent - Binance multi-product opportunity scanner.

This agent does not place orders. It watches public Binance market/product
surfaces and publishes a dashboard snapshot for non-futures opportunities:
Spot momentum, Spot Grid candidates, Options direction watch, Alpha/new-listing
style momentum, funding/arb watch, Dual Investment, Launchpool/Megadrop.
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional

import requests

logger = logging.getLogger(__name__)

_RADAR_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "opportunity_radar.json")
_SPOT_TICKER_URL = "https://api.binance.com/api/v3/ticker/24hr"
_FUTURES_TICKER_URL = "https://fapi.binance.com/fapi/v1/ticker/24hr"
_FUNDING_URL = "https://fapi.binance.com/fapi/v1/premiumIndex"
_OPTIONS_TICKER_URL = "https://eapi.binance.com/eapi/v1/ticker"
_DEX_INFO_URL = "https://api.hyperliquid.xyz/info"


class OpportunityRadarAgent:
    """Publishes a multi-product opportunity radar without executing trades."""

    def __init__(self, config: Any, monitor: Optional[Any] = None):
        self.config = config
        self.monitor = monitor
        self.snapshot: Dict[str, Any] = {}

    def refresh(self) -> Dict[str, Any]:
        top_n = int(getattr(self.config, "opportunity_radar_top_n", 8) or 8)
        min_quote_volume = float(
            getattr(self.config, "opportunity_radar_min_quote_volume_usdt", 2_000_000) or 0.0
        )

        spot_rows = self._fetch_json(_SPOT_TICKER_URL)
        futures_rows = self._fetch_json(_FUTURES_TICKER_URL)
        funding_rows = self._fetch_json(_FUNDING_URL)
        options_rows = self._fetch_json(_OPTIONS_TICKER_URL)

        spot = self._normalize_tickers(spot_rows, market="spot", min_quote_volume=min_quote_volume)
        futures = self._normalize_tickers(
            futures_rows, market="futures", min_quote_volume=min_quote_volume
        )
        funding = self._normalize_funding(funding_rows)
        options = self._normalize_options(options_rows)

        products = [
            self._spot_momentum(spot, top_n),
            self._spot_grid(spot, top_n),
            self._options_watch(spot, futures, options, top_n),
            self._alpha_watch(spot, futures, top_n),
            self._funding_arb_watch(funding, futures, top_n),
            self._dex_watch(futures, top_n),
            self._dual_investment_watch(spot, top_n),
            self._launchpool_watch(),
            self._copy_trading_watch(),
        ]

        watch_ready = sum(1 for p in products if p.get("state") in {"WATCH", "MANUAL_READY"})
        snap = {
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "updated_ts": time.time(),
            "auto_entry_enabled": False,
            "auto_entry_reason": (
                "אפיקים אלה דורשים בחירה/אישור מוצר בבינאנס או API ייעודי; "
                "המערכת מציגה הזדמנויות ולא נכנסת אליהם אוטומטית."
            ),
            "summary": {
                "products_watched": len(products),
                "watch_ready": watch_ready,
                "spot_symbols": len(spot),
                "futures_symbols": len(futures),
                "options_rows": len(options),
            },
            "products": products,
        }
        self.snapshot = snap
        self._write_json(_RADAR_FILE, snap)

        if self.monitor:
            best = max(products, key=lambda p: float(p.get("score", 0) or 0), default={})
            self.monitor.report(
                "OpportunityRadar",
                "scan",
                (
                    f"{watch_ready}/{len(products)} אפיקים במעקב | "
                    f"מוביל: {best.get('name', '—')} {best.get('score', 0):.0f}/100"
                ),
                status="active",
                severity="INFO",
                force=True,
            )
        return snap

    def _spot_momentum(self, rows: List[Dict[str, Any]], top_n: int) -> Dict[str, Any]:
        candidates = sorted(
            rows,
            key=lambda r: (r["change_pct"], r["quote_volume"]),
            reverse=True,
        )[:top_n]
        score = min(100.0, 35.0 + (candidates[0]["change_pct"] if candidates else 0.0) * 2.5)
        return self._product(
            key="spot_momentum",
            name="Spot Momentum",
            state="WATCH" if candidates else "WAIT",
            risk="גבוה",
            score=score,
            detail="מטבעות ספוט עם מומנטום יומי חזק, בלי liquidation אבל עם תנודתיות גבוהה.",
            action="בדיקה ידנית בספוט; לא מחובר לכניסה אוטומטית.",
            candidates=candidates,
        )

    def _spot_grid(self, rows: List[Dict[str, Any]], top_n: int) -> Dict[str, Any]:
        grid_rows = [
            r for r in rows
            if 2.0 <= r["range_pct"] <= 18.0 and abs(r["change_pct"]) <= max(7.0, r["range_pct"])
        ]
        candidates = sorted(
            grid_rows,
            key=lambda r: (r["range_pct"], r["quote_volume"]),
            reverse=True,
        )[:top_n]
        score = min(100.0, 45.0 + (candidates[0]["range_pct"] if candidates else 0.0) * 2.0)
        return self._product(
            key="spot_grid",
            name="Spot Grid",
            state="MANUAL_READY" if candidates else "WAIT",
            risk="בינוני-גבוה",
            score=score,
            detail="מתאים לשוק שנע בטווח: קנייה נמוך/מכירה גבוה ללא מינוף.",
            action="פתיחה ידנית בבינאנס Spot Grid עם טווח מחושב.",
            candidates=candidates,
        )

    def _options_watch(
        self,
        spot: List[Dict[str, Any]],
        futures: List[Dict[str, Any]],
        options: List[Dict[str, Any]],
        top_n: int,
    ) -> Dict[str, Any]:
        majors = {
            r["symbol"]: r for r in [*spot, *futures]
            if r["symbol"] in {"BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"}
        }
        candidates = sorted(
            majors.values(),
            key=lambda r: (abs(r["change_pct"]) + r["range_pct"], r["quote_volume"]),
            reverse=True,
        )[: min(top_n, 5)]
        for c in candidates:
            c["idea"] = "CALL watch" if c["change_pct"] >= 0 else "PUT watch"
        score = min(100.0, 40.0 + (abs(candidates[0]["change_pct"]) if candidates else 0.0) * 5.0)
        detail = "קניית אופציה מגבילה הפסד לפרמיה, אבל יכולה להימחק מהר אם הכיוון/זמן לא נכון."
        if not options:
            detail += " נתוני Options API לא זמינים כרגע, לכן הכיוון נגזר מספוט/פיוצ'רס."
        return self._product(
            key="options",
            name="Options",
            state="WATCH" if candidates else "WAIT",
            risk="גבוה מאוד",
            score=score,
            detail=detail,
            action="בחירה ידנית של Call/Put, תאריך ופרמיה מקסימלית.",
            candidates=candidates,
        )

    def _alpha_watch(
        self,
        spot: List[Dict[str, Any]],
        futures: List[Dict[str, Any]],
        top_n: int,
    ) -> Dict[str, Any]:
        known_majors = {"BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT"}
        pool = [r for r in [*spot, *futures] if r["symbol"] not in known_majors]
        candidates = sorted(
            pool,
            key=lambda r: (r["change_pct"], r["range_pct"], r["quote_volume"]),
            reverse=True,
        )[:top_n]
        score = min(100.0, 30.0 + (candidates[0]["change_pct"] if candidates else 0.0) * 2.0)
        return self._product(
            key="alpha",
            name="Alpha / New Hot Coins",
            state="WATCH" if candidates else "WAIT",
            risk="גבוה מאוד",
            score=score,
            detail="רדאר למטבעות חמים/חדשים. פוטנציאל תנועה מהירה וגם נפילות חדות.",
            action="בדיקה ידנית ב-Binance Alpha/New Listings לפני כניסה.",
            candidates=candidates,
        )

    def _funding_arb_watch(
        self,
        funding: List[Dict[str, Any]],
        futures: List[Dict[str, Any]],
        top_n: int,
    ) -> Dict[str, Any]:
        by_symbol = {r["symbol"]: r for r in futures}
        rows = []
        for f in funding:
            r = dict(f)
            if f["symbol"] in by_symbol:
                r.update({
                    "change_pct": by_symbol[f["symbol"]]["change_pct"],
                    "quote_volume": by_symbol[f["symbol"]]["quote_volume"],
                })
            rows.append(r)
        candidates = sorted(rows, key=lambda r: abs(r.get("funding_rate", 0.0)), reverse=True)[:top_n]
        top_rate = abs(candidates[0].get("funding_rate", 0.0)) if candidates else 0.0
        score = min(100.0, 35.0 + top_rate * 100000)
        return self._product(
            key="funding_arb",
            name="Funding / Arb Watch",
            state="WATCH" if candidates else "WAIT",
            risk="גבוה",
            score=score,
            detail="בודק funding קיצוני; זה רדאר יתרון, לא ארביטראז' מלא בין בורסות.",
            action="שימוש עקיף בהחלטות או בדיקה ידנית לפני Funding.",
            candidates=candidates,
        )

    def _dex_watch(self, futures: List[Dict[str, Any]], top_n: int) -> Dict[str, Any]:
        """
        Hyperliquid movers radar (read-only, no keys). New/hot coins often move
        on the DEX before Binance — candidates that ALSO trade on Binance
        futures are marked on_binance and can be injected into the scanner
        universe, where every normal gate (score, committee, risk) still applies.
        """
        rows = self._fetch_dex_ctxs()
        binance_symbols = {r["symbol"] for r in futures}
        candidates: List[Dict[str, Any]] = []
        for r in rows:
            if r["volume"] < 1_000_000 or r["prev_day"] <= 0:
                continue
            change_pct = (r["mark"] - r["prev_day"]) / r["prev_day"] * 100.0
            binance_symbol = self._dex_to_binance_symbol(r["coin"])
            candidates.append({
                "symbol": r["coin"],
                "market": "dex",
                "last": r["mark"],
                "change_pct": round(change_pct, 3),
                "quote_volume": round(r["volume"], 2),
                "funding_pct": round(r["funding"] * 100.0, 4),
                "binance_symbol": binance_symbol,
                "on_binance": binance_symbol in binance_symbols,
            })
        candidates.sort(key=lambda c: abs(c["change_pct"]), reverse=True)
        candidates = candidates[:top_n]
        score = min(100.0, 35.0 + (abs(candidates[0]["change_pct"]) if candidates else 0.0) * 2.0)
        return self._product(
            key="dex_watch",
            name="DEX Watch (Hyperliquid)",
            state="WATCH" if candidates else "WAIT",
            risk="גבוה מאוד",
            score=score,
            detail="מטבעות שזזים חזק ב-DEX, לפעמים לפני ביננס. מי שקיים גם בביננס מוזרם לסורק ועובר את כל שערי הסיכון.",
            action="אוטומטי דרך הסורק רק לסימבולים שנסחרים בביננס; השאר לצפייה בלבד.",
            candidates=candidates,
        )

    def _fetch_dex_ctxs(self) -> List[Dict[str, Any]]:
        """Fetch Hyperliquid meta+contexts. Returns [] on any failure."""
        try:
            resp = requests.post(
                _DEX_INFO_URL,
                json={"type": "metaAndAssetCtxs"},
                timeout=10,
            )
            resp.raise_for_status()
            payload = resp.json()
            universe = payload[0].get("universe", [])
            ctxs = payload[1]
            out: List[Dict[str, Any]] = []
            for meta, ctx in zip(universe, ctxs):
                try:
                    out.append({
                        "coin": str(meta.get("name", "")),
                        "mark": self._float(ctx.get("markPx")),
                        "prev_day": self._float(ctx.get("prevDayPx")),
                        "volume": self._float(ctx.get("dayNtlVlm")),
                        "funding": self._float(ctx.get("funding")),
                    })
                except Exception:
                    continue
            return [r for r in out if r["coin"] and r["mark"] > 0]
        except Exception as exc:
            logger.debug("DEX watch fetch failed: %s", exc)
            return []

    @staticmethod
    def _dex_to_binance_symbol(coin: str) -> str:
        """Map a Hyperliquid coin name to its Binance USDT-M futures symbol.

        Hyperliquid prefixes 1000x-denominated coins with 'k' (kPEPE);
        Binance uses a '1000' prefix (1000PEPEUSDT).
        """
        if len(coin) > 1 and coin[0] == "k" and coin[1:].isupper():
            return f"1000{coin[1:]}USDT"
        return f"{coin.upper()}USDT"

    def _dual_investment_watch(self, spot: List[Dict[str, Any]], top_n: int) -> Dict[str, Any]:
        # Real products (with actual APRs) via the authenticated DCI endpoint;
        # falls back to the spot-range proxy when keys/endpoint are unavailable.
        real = self._fetch_dual_investment_products(top_n)
        if real:
            best_apr = max(c.get("apr_pct", 0.0) for c in real)
            return self._product(
                key="dual_investment",
                name="Dual Investment",
                state="MANUAL_READY",
                risk="גבוה",
                score=min(100.0, 30.0 + best_apr),
                detail="מוצרים אמיתיים מ-Binance Earn עם APR בפועל. קנייה-בנמוך = כתיבת PUT: הריבית מובטחת, אבל ייתכן שתקבל את המטבע במקום USDT.",
                action="הרשמה ידנית בלבד דרך Binance Earn — המערכת לא נכנסת אוטומטית.",
                candidates=real,
            )

        majors = [r for r in spot if r["symbol"] in {"BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"}]
        candidates = sorted(majors, key=lambda r: r["range_pct"], reverse=True)[: min(top_n, 4)]
        score = min(100.0, 30.0 + (candidates[0]["range_pct"] if candidates else 0.0) * 3.0)
        return self._product(
            key="dual_investment",
            name="Dual Investment",
            state="MANUAL_READY" if candidates else "WAIT",
            risk="גבוה",
            score=score,
            detail="מוצר מובנה: תשואה גבוהה יחסית, אבל ייתכן שתסיים עם המטבע הפחות רצוי.",
            action="בחירה ידנית של יעד מחיר ותאריך settlement.",
            candidates=candidates,
        )

    def _dci_client(self):
        """Lazy authenticated Binance client for read-only DCI queries."""
        if getattr(self, "_dci_client_cached", None) is not None:
            return self._dci_client_cached
        api_key = getattr(self.config, "api_key", "") or ""
        api_secret = getattr(self.config, "api_secret", "") or ""
        if not api_key or not api_secret:
            return None
        try:
            from agents.binance_compat import create_binance_client

            self._dci_client_cached = create_binance_client(api_key, api_secret)
        except Exception as exc:
            logger.debug("DCI client init failed: %s", exc)
            self._dci_client_cached = None
        return self._dci_client_cached

    def _fetch_dual_investment_products(self, top_n: int) -> List[Dict[str, Any]]:
        """
        READ-ONLY list of live Buy-Low (PUT/USDT) Dual Investment products for
        the majors, ranked by real APR. Never subscribes to anything.
        """
        client = self._dci_client()
        if client is None:
            return []
        out: List[Dict[str, Any]] = []
        for coin in ("BTC", "ETH", "BNB", "SOL"):
            try:
                resp = client._request_margin_api(
                    "get",
                    "dci/product/list",
                    signed=True,
                    data={
                        "optionType": "PUT",
                        "exercisedCoin": coin,
                        "investCoin": "USDT",
                        "pageSize": 20,
                    },
                )
                for p in (resp or {}).get("list", []):
                    if not p.get("canPurchase", True):
                        continue
                    apr = self._float(p.get("apr")) * 100.0
                    settle_ms = int(self._float(p.get("settleDate")))
                    days = max(0.0, (settle_ms / 1000.0 - time.time()) / 86400.0) if settle_ms else 0.0
                    out.append({
                        "symbol": f"{coin} @ {p.get('strikePrice', '?')}",
                        "market": "earn",
                        "idea": f"Buy Low · APR {apr:.1f}% · {days:.0f} ימים",
                        "change_pct": apr,
                        "apr_pct": apr,
                        "quote_volume": self._float(p.get("maxAmount")),
                        "min_amount": self._float(p.get("minAmount")),
                    })
            except Exception as exc:
                logger.debug("DCI product list failed for %s: %s", coin, exc)
                return []
        out.sort(key=lambda c: c.get("apr_pct", 0.0), reverse=True)
        return out[: min(top_n, 6)]

    def _launchpool_watch(self) -> Dict[str, Any]:
        return self._product(
            key="launchpool",
            name="Launchpool / Megadrop",
            state="MANUAL",
            risk="נמוך-בינוני",
            score=42.0,
            detail="מתאים לנכסים פנויים כמו BNB/FDUSD. לא מהיר לחשבון קטן, אבל יכול להוסיף איירדרופים.",
            action="בדיקה ידנית בעמוד Launchpool/Megadrop.",
            candidates=[],
        )

    def _copy_trading_watch(self) -> Dict[str, Any]:
        return self._product(
            key="copy_trading",
            name="Copy Trading",
            state="MANUAL",
            risk="תלוי סוחר",
            score=35.0,
            detail="אין API ציבורי טוב לבחירת Lead Trader אוטומטית; מתאים רק עם תקרת הפסד ברורה.",
            action="בחירה ידנית של Lead Trader עם drawdown נמוך ו-Sharpe גבוה.",
            candidates=[],
        )

    def _fetch_json(self, url: str) -> Any:
        try:
            resp = requests.get(url, timeout=10)
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            logger.debug("Opportunity radar fetch failed for %s: %s", url, exc)
            return []

    def _normalize_tickers(
        self,
        rows: Any,
        *,
        market: str,
        min_quote_volume: float,
    ) -> List[Dict[str, Any]]:
        if not isinstance(rows, list):
            return []
        out: List[Dict[str, Any]] = []
        for r in rows:
            try:
                symbol = str(r.get("symbol", ""))
                if not symbol.endswith("USDT"):
                    continue
                quote_volume = float(r.get("quoteVolume", 0) or 0.0)
                if quote_volume < min_quote_volume:
                    continue
                last = float(r.get("lastPrice", 0) or 0.0)
                high = float(r.get("highPrice", 0) or 0.0)
                low = float(r.get("lowPrice", 0) or 0.0)
                change = float(r.get("priceChangePercent", 0) or 0.0)
                range_pct = ((high - low) / last * 100.0) if last > 0 and high > low else 0.0
                out.append({
                    "symbol": symbol,
                    "market": market,
                    "last": round(last, 8),
                    "change_pct": round(change, 3),
                    "range_pct": round(range_pct, 3),
                    "quote_volume": round(quote_volume, 2),
                    "count": int(float(r.get("count", 0) or 0)),
                })
            except Exception:
                continue
        return out

    def _normalize_funding(self, rows: Any) -> List[Dict[str, Any]]:
        if isinstance(rows, dict):
            rows = [rows]
        if not isinstance(rows, list):
            return []
        out: List[Dict[str, Any]] = []
        for r in rows:
            try:
                symbol = str(r.get("symbol", ""))
                if not symbol.endswith("USDT"):
                    continue
                rate = float(r.get("lastFundingRate", 0) or 0.0)
                out.append({
                    "symbol": symbol,
                    "market": "futures",
                    "funding_rate": rate,
                    "funding_pct": round(rate * 100.0, 4),
                    "next_funding": int(r.get("nextFundingTime", 0) or 0),
                })
            except Exception:
                continue
        return out

    def _normalize_options(self, rows: Any) -> List[Dict[str, Any]]:
        if isinstance(rows, dict):
            rows = [rows]
        if not isinstance(rows, list):
            return []
        out: List[Dict[str, Any]] = []
        for r in rows[:500]:
            try:
                symbol = str(r.get("symbol", ""))
                if not symbol:
                    continue
                out.append({
                    "symbol": symbol,
                    "market": "options",
                    "last": self._float(r.get("lastPrice")),
                    "volume": self._float(r.get("volume")),
                })
            except Exception:
                continue
        return out

    @staticmethod
    def _float(value: Any, default: float = 0.0) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _product(
        *,
        key: str,
        name: str,
        state: str,
        risk: str,
        score: float,
        detail: str,
        action: str,
        candidates: Iterable[Dict[str, Any]],
    ) -> Dict[str, Any]:
        return {
            "key": key,
            "name": name,
            "state": state,
            "risk": risk,
            "score": round(float(score or 0.0), 1),
            "detail": detail,
            "action": action,
            "auto_entry": False,
            "candidates": list(candidates),
        }

    @staticmethod
    def _write_json(path: str, payload: Dict[str, Any]) -> None:
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp = f"{path}.tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, ensure_ascii=False, indent=2)
            os.replace(tmp, path)
        except Exception as exc:
            logger.debug("Opportunity radar write failed: %s", exc)

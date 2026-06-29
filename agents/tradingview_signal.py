"""
TradingViewSignals — דירוג ניתוח טכני חי מ-TradingView (חינם, דרך tradingview-ta).

ממיר את ה-RECOMMENDATION (STRONG_BUY..STRONG_SELL) לכיוון מסחר + עוצמה, כדי
שהבוט יוכל להיכנס לעסקאות לפי TradingView. זה סיגנל סטנדרטי שהרבה סוחרים
משתמשים בו — אבל הוא לא מבטיח רווח, ולכן כל עסקה עדיין מקבלת SL/TP.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

try:
    from tradingview_ta import get_multiple_analysis, Interval
    TV_AVAILABLE = True
except Exception:  # pragma: no cover
    TV_AVAILABLE = False
    logger.warning("tradingview-ta not installed — TradingView signals disabled. "
                   "Run: pip install tradingview-ta")

# recommendation -> (direction, strength 0..1)
_REC_MAP = {
    "STRONG_BUY": ("LONG", 1.0),
    "BUY": ("LONG", 0.65),
    "NEUTRAL": (None, 0.0),
    "SELL": ("SHORT", 0.65),
    "STRONG_SELL": ("SHORT", 1.0),
}


class TradingViewSignals:
    """Batch-fetch TradingView TA ratings and map them to trade direction + strength."""

    def __init__(self, interval: str = "15m", screener: str = "crypto",
                 exchange: str = "BINANCE"):
        self.screener = screener
        self.exchange = exchange
        self.interval = interval
        self.signals: Dict[str, Dict[str, Any]] = {}
        self._interval = None
        if TV_AVAILABLE:
            self._interval = {
                "1m": Interval.INTERVAL_1_MINUTE,
                "5m": Interval.INTERVAL_5_MINUTES,
                "15m": Interval.INTERVAL_15_MINUTES,
                "1h": Interval.INTERVAL_1_HOUR,
                "4h": Interval.INTERVAL_4_HOURS,
            }.get(interval, Interval.INTERVAL_15_MINUTES)

    @property
    def available(self) -> bool:
        return TV_AVAILABLE

    def fetch(self, symbols: List[str]) -> Dict[str, Dict[str, Any]]:
        """Return {symbol: {direction, strength, rec, rsi}} for the given symbols."""
        if not TV_AVAILABLE or not symbols:
            return {}
        tv_symbols = [f"{self.exchange}:{s}" for s in symbols]
        out: Dict[str, Dict[str, Any]] = {}
        try:
            res = get_multiple_analysis(
                screener=self.screener, interval=self._interval, symbols=tv_symbols
            )
        except Exception as exc:
            logger.debug("TradingView fetch failed: %s", exc)
            return {}

        for tv_sym, analysis in (res or {}).items():
            if analysis is None:
                continue
            try:
                sym = tv_sym.split(":")[-1]
                rec = analysis.summary.get("RECOMMENDATION", "NEUTRAL")
                direction, strength = _REC_MAP.get(rec, (None, 0.0))
                out[sym] = {
                    "direction": direction,
                    "strength": strength,
                    "rec": rec,
                    "rsi": analysis.indicators.get("RSI"),
                }
            except Exception:
                continue

        self.signals = out
        return out

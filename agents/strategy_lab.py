"""
StrategyLabAgent - research gate for advanced automation ideas.

This agent does not place orders. It turns the ideas behind SaaS bots,
FreqAI/Hummingbot-style systems and institutional market-making into a live
readiness snapshot so the dashboard can show what is active, what is only
research, and why.
"""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

_LAB_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "strategy_lab.json")
_MODEL_HEALTH_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "model_health.json")


class StrategyLabAgent:
    """Evaluates strategy modules and publishes a research/readiness snapshot."""

    def __init__(self, config: Any, repo: Any, monitor: Optional[Any] = None):
        self.config = config
        self.repo = repo
        self.monitor = monitor
        self.snapshot: Dict[str, Any] = {}

    def refresh(self) -> Dict[str, Any]:
        lookback = int(getattr(self.config, "strategy_lab_lookback_hours", 48))
        min_live_trades = int(getattr(self.config, "strategy_lab_min_live_trades", 30))

        overall = self.repo.get_overall_recent_stats(hours_back=lookback)
        close_reasons = self.repo.get_close_reason_stats(hours_back=lookback)
        score_brackets = self.repo.get_score_bracket_stats(hours_back=lookback)
        symbol_stats = self.repo.get_symbol_stats(min_trades=3, hours_back=lookback)
        model_health = self._read_json(_MODEL_HEALTH_FILE)

        total_trades = int(overall.get("total_trades") or 0)
        total_pnl = self._float(overall.get("total_pnl"))
        avg_pnl = self._float(overall.get("avg_pnl"))
        win_rate = self._float(overall.get("win_rate"))

        profit_capture_pnl = self._reason_pnl(
            close_reasons,
            {
                "profit_lock",
                "take_profit",
                "take_profit_exchange_reconcile",
                "scalp_take_profit",
                "scalp_take_profit_exchange_reconcile",
            },
        )
        stop_pnl = self._reason_pnl(
            close_reasons,
            {"stop_loss", "stop_loss_exchange_reconcile", "stop_loss_db_reconcile"},
        )
        no_move_pnl = self._reason_pnl(
            close_reasons,
            {"stale_no_move", "fast_exit_no_move"},
        )

        model_aggregate = model_health.get("aggregate") or {}
        healthy_symbols = int(model_aggregate.get("healthy_symbols") or 0)
        trained_symbols = int(model_aggregate.get("trained_symbols") or 0)

        live_edge = total_trades >= min_live_trades and total_pnl > 0 and avg_pnl > 0
        runner_ready = bool(getattr(self.config, "trend_runner_enabled", False))
        capital_ready = bool(getattr(self.config, "capital_allocator_enabled", False))
        flow_ready = bool(getattr(self.config, "flow_agent_enabled", False))
        indirect_ready = bool(getattr(self.config, "indirect_strategies_enabled", False))
        grid_indirect = indirect_ready and bool(getattr(self.config, "indirect_grid_enabled", False))
        dca_indirect = indirect_ready and bool(getattr(self.config, "indirect_dca_enabled", False))
        arb_indirect = indirect_ready and bool(getattr(self.config, "indirect_arb_enabled", False))
        anti_martingale = indirect_ready and bool(getattr(self.config, "indirect_martingale_inverse_enabled", False))

        modules = [
            self._module(
                "smart_trade",
                "Smart Trade",
                "LIVE",
                "פעיל",
                "SL/TP נשלחים לבורסה לכל כניסה חיה.",
                95,
            ),
            self._module(
                "hft_ml",
                "HFT + ML",
                "LIVE" if total_trades else "WARMING",
                "פעיל" if total_trades else "מתחמם",
                f"{total_trades} עסקאות ב-{lookback} שעות | PnL {total_pnl:+.2f} USDT.",
                70 if live_edge else 46,
            ),
            self._module(
                "freqai_like",
                "FreqAI-style health",
                "LIVE" if trained_symbols else "WARMING",
                "בריאות ML",
                f"{healthy_symbols}/{trained_symbols} מודלים עם יתרון אמינות.",
                78 if healthy_symbols else 42,
            ),
            self._module(
                "order_flow",
                "Order Flow",
                "LIVE" if flow_ready else "OFF",
                "פעיל" if flow_ready else "כבוי",
                "Open interest, taker ratio ו-crowding לפני כניסה.",
                78 if flow_ready else 0,
            ),
            self._module(
                "capital_runner",
                "Capital + Runner",
                "LIVE" if capital_ready and runner_ready else "PARTIAL",
                "פעיל" if capital_ready and runner_ready else "חלקי",
                "מגדיל רק בקונצנזוס גבוה ונותן לעסקאות חזקות לרוץ.",
                82 if capital_ready and runner_ready else 50,
            ),
            self._module(
                "grid",
                "Grid",
                "INDIRECT" if grid_indirect else "RESEARCH",
                "עקיף פעיל" if grid_indirect else "מחקר בלבד",
                (
                    "מזהה שוק מדשדש וקצוות Bollinger, ומשפיע על ועדת ההחלטה."
                    if grid_indirect
                    else "דורש זיהוי שוק מדשדש ובדיקה נפרדת לפני כסף אמיתי."
                ),
                58 if grid_indirect else 20,
            ),
            self._module(
                "dca",
                "DCA/Martingale",
                "INDIRECT" if dca_indirect or anti_martingale else "BLOCKED",
                "עקיף/הפוך פעיל" if dca_indirect or anti_martingale else "חסום ללייב",
                (
                    "DCA משמש רק ככניסה מדורגת אחרי pullback; Martingale הפוך מקטין סיכון."
                    if dca_indirect or anti_martingale
                    else "ממוצע הפסד בפיוצ'רס יכול להגדיל drawdown מהר מדי."
                ),
                52 if dca_indirect or anti_martingale else 5,
            ),
            self._module(
                "arbitrage",
                "Arbitrage",
                "INDIRECT" if arb_indirect else "BLOCKED",
                "עקיף פעיל" if arb_indirect else "לא מתאים כרגע",
                (
                    "בודק funding/spread כיתרון החלטה; לא פותח עסקאות בין בורסות."
                    if arb_indirect
                    else "דורש כמה בורסות, עמלות מדויקות ומהירות גבוהה."
                ),
                45 if arb_indirect else 8,
            ),
            self._module(
                "copy_trading",
                "Copy Trading",
                "OFF",
                "לא מחובר",
                "אין תלות בסוחרים חיצוניים; החלטות נשארות מקומיות.",
                0,
            ),
        ]

        recommendations = self._recommendations(
            total_trades=total_trades,
            total_pnl=total_pnl,
            avg_pnl=avg_pnl,
            win_rate=win_rate,
            profit_capture_pnl=profit_capture_pnl,
            stop_pnl=stop_pnl,
            no_move_pnl=no_move_pnl,
            score_brackets=score_brackets,
            symbol_stats=symbol_stats,
            healthy_symbols=healthy_symbols,
            trained_symbols=trained_symbols,
            min_live_trades=min_live_trades,
        )

        readiness = self._readiness_score(modules, total_trades, total_pnl, avg_pnl)
        snap = {
            "updated_at": time.time(),
            "lookback_hours": lookback,
            "readiness_score": readiness,
            "live_edge": live_edge,
            "overall": overall,
            "profit_capture_pnl": round(profit_capture_pnl, 6),
            "stop_pnl": round(stop_pnl, 6),
            "no_move_pnl": round(no_move_pnl, 6),
            "modules": modules,
            "recommendations": recommendations,
            "score_brackets": score_brackets,
            "worst_symbols": symbol_stats[:6],
            "model_aggregate": model_aggregate,
        }
        self.snapshot = snap
        self._write_json(_LAB_FILE, snap)

        if self.monitor:
            status = "active" if readiness >= 50 else "working"
            detail = (
                f"readiness={readiness}/100 | {total_trades} trades | "
                f"PnL={total_pnl:+.2f} | modules live="
                f"{sum(1 for m in modules if m['state'] == 'LIVE')}"
            )
            self.monitor.report(
                "StrategyLab",
                "research",
                detail,
                status=status,
                severity="INFO" if total_pnl >= 0 else "WARNING",
                force=True,
            )
        return snap

    @staticmethod
    def _module(
        key: str,
        name: str,
        state: str,
        status: str,
        detail: str,
        score: int,
    ) -> Dict[str, Any]:
        return {
            "key": key,
            "name": name,
            "state": state,
            "status": status,
            "detail": detail,
            "score": max(0, min(100, int(score))),
        }

    @staticmethod
    def _float(value: Any, default: float = 0.0) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    def _reason_pnl(self, rows: List[Dict[str, Any]], reasons: set[str]) -> float:
        total = 0.0
        for row in rows:
            if row.get("close_reason") in reasons:
                total += self._float(row.get("total_pnl"))
        return total

    def _recommendations(
        self,
        *,
        total_trades: int,
        total_pnl: float,
        avg_pnl: float,
        win_rate: float,
        profit_capture_pnl: float,
        stop_pnl: float,
        no_move_pnl: float,
        score_brackets: List[Dict[str, Any]],
        symbol_stats: List[Dict[str, Any]],
        healthy_symbols: int,
        trained_symbols: int,
        min_live_trades: int,
    ) -> List[Dict[str, str]]:
        recs: List[Dict[str, str]] = []

        if total_trades < min_live_trades:
            recs.append({
                "level": "research",
                "title": "לא להפעיל אסטרטגיות חדשות בלייב עדיין",
                "detail": f"נדרשות לפחות {min_live_trades} עסקאות אחרונות למדידה יציבה; כרגע יש {total_trades}.",
            })
        elif total_pnl <= 0 or avg_pnl <= 0:
            recs.append({
                "level": "risk",
                "title": "להקשיח כניסות לפני הגדלת סיכון נוספת",
                "detail": f"החלון האחרון שלילי: PnL {total_pnl:+.2f}, ממוצע {avg_pnl:+.3f} לעסקה.",
            })
        else:
            recs.append({
                "level": "ready",
                "title": "יש יתרון חי ראשוני",
                "detail": f"Win-rate {win_rate:.1%}, PnL {total_pnl:+.2f}; אפשר להמשיך לשפר בהדרגה.",
            })

        if profit_capture_pnl > 0:
            recs.append({
                "level": "ready",
                "title": "מנגנון לקיחת רווח עובד",
                "detail": f"Profit lock / TP תרמו {profit_capture_pnl:+.2f} USDT בחלון המחקר.",
            })
        if stop_pnl < 0 and abs(stop_pnl) > max(2.0, profit_capture_pnl * 1.4):
            recs.append({
                "level": "risk",
                "title": "הסטופים אוכלים את רוב הרווח",
                "detail": f"סגירות סטופ תרמו {stop_pnl:+.2f} USDT; לשפר פילטר כניסה לפני הגדלת גודל.",
            })
        if no_move_pnl < -1:
            recs.append({
                "level": "research",
                "title": "לבדוק יציאות ללא תנועה",
                "detail": f"יציאות no-move תרמו {no_move_pnl:+.2f}; כדאי למדוד זמן אחזקה אופטימלי.",
            })

        best_bracket = self._best_score_bracket(score_brackets)
        if best_bracket:
            recs.append({
                "level": "ready",
                "title": f"בראקט ציון עדיף: {best_bracket.get('score_bracket')}",
                "detail": (
                    f"{best_bracket.get('trades')} עסקאות | "
                    f"PnL {self._float(best_bracket.get('total_pnl')):+.2f} | "
                    f"win {self._float(best_bracket.get('win_rate')):.0%}."
                ),
            })

        if trained_symbols and healthy_symbols == 0:
            recs.append({
                "level": "risk",
                "title": "ה־ML עדיין לא מוכיח יתרון מספיק",
                "detail": "הסורק משתמש בגיבוי טכני, ולכן הגיבוי הוקשח לעסקאות חזקות בלבד.",
            })

        if symbol_stats:
            worst = symbol_stats[0]
            recs.append({
                "level": "research",
                "title": f"לבדוק מטבע חלש: {worst.get('symbol')}",
                "detail": f"{worst.get('trades')} עסקאות | PnL {self._float(worst.get('total_pnl')):+.2f}.",
            })

        return recs[:7]

    def _best_score_bracket(self, rows: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        positive = [r for r in rows if self._float(r.get("total_pnl")) > 0 and int(r.get("trades") or 0) >= 2]
        if not positive:
            return None
        return max(positive, key=lambda r: self._float(r.get("total_pnl")))

    @staticmethod
    def _readiness_score(
        modules: List[Dict[str, Any]], total_trades: int, total_pnl: float, avg_pnl: float
    ) -> int:
        live_scores = [m["score"] for m in modules if m["state"] in {"LIVE", "WARMING", "PARTIAL"}]
        base = sum(live_scores) / max(1, len(live_scores))
        if total_trades < 20:
            base -= 10
        if total_pnl < 0:
            base -= 12
        if avg_pnl < 0:
            base -= 8
        return max(0, min(100, int(round(base))))

    @staticmethod
    def _read_json(path: str) -> Dict[str, Any]:
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    @staticmethod
    def _write_json(path: str, payload: Dict[str, Any]) -> None:
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
        except Exception as exc:
            logger.debug("StrategyLab snapshot write failed: %s", exc)

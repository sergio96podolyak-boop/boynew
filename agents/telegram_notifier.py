"""
Telegram notifier — שולח הודעות בעברית לבוט טלגרם על כל פעולת מסחר.
כל מי שישלח /start לבוט יירשם אוטומטית ויקבל עדכונים.

עיצוב חדש: כרטיסי מסחר מעוצבים עם אמוג'ים וסטטיסטיקות.
"""
import json
import logging
import os
import threading
from datetime import datetime, timezone, timedelta
from typing import Optional, Set

import requests

logger = logging.getLogger(__name__)

TELEGRAM_API = "https://api.telegram.org/bot{token}/{method}"
_SEND_TIMEOUT = 5
_SUBSCRIBERS_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "tg_subscribers.json")


def _load_subscribers(path: str) -> Set[str]:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path):
            with open(path) as f:
                return set(json.load(f))
    except Exception:
        pass
    return set()


def _save_subscribers(path: str, subs: Set[str]) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump(list(subs), f)
    except Exception as e:
        logger.warning("Failed to save subscribers: %s", e)


class TelegramNotifier:
    """שולח הודעות עדכון למסחר בעברית לכל המנויים — עיצוב מקצועי."""

    def __init__(self, token: str, owner_chat_id: str, enabled: bool = True):
        self.token = token
        self._enabled = bool(enabled and token)
        self._subscribers: Set[str] = (
            _load_subscribers(_SUBSCRIBERS_FILE) if enabled else set()
        )
        if enabled and owner_chat_id:
            self._subscribers.add(str(owner_chat_id))
            _save_subscribers(_SUBSCRIBERS_FILE, self._subscribers)
        self._update_offset: int = 0

        # Session stats for heartbeat
        self._session_wins: int = 0
        self._session_losses: int = 0

        if self._enabled:
            logger.info("TelegramNotifier מוכן — %d מנויים", len(self._subscribers))
            t = threading.Thread(target=self._poll_loop, daemon=True)
            t.start()
        elif not enabled:
            logger.info("TelegramNotifier כבוי לפי TELEGRAM_ENABLED=false")
        else:
            logger.warning("TelegramNotifier — לא הוגדר token, הודעות מבוטלות")

    # ------------------------------------------------------------------
    # Public API — עיצוב חדש
    # ------------------------------------------------------------------

    def entry(self, symbol: str, direction: str, qty: float, price: float,
              sl: float, tp: float, score: float, balance: float) -> None:
        is_long = direction == "LONG"
        arrow = "🟢" if is_long else "🔴"
        dir_he = "לונג 📈" if is_long else "שורט 📉"

        # Calculate risk/reward
        if is_long:
            risk = abs(price - sl) if sl > 0 else 0
            reward = abs(tp - price) if tp > 0 else 0
        else:
            risk = abs(sl - price) if sl > 0 else 0
            reward = abs(price - tp) if tp > 0 else 0
        rr = f"{reward/risk:.1f}" if risk > 0 else "—"

        # Notional size
        notional = qty * price

        # Score tier
        if score >= 92:
            tier = "🔥 EXTREME"
        elif score >= 85:
            tier = "⚡ HIGH"
        else:
            tier = "📊 BASE"

        msg = (
            f"{arrow} ═══════════════════\n"
            f"  *כניסה לעסקה — {dir_he}*\n"
            f"═══════════════════════\n\n"
            f"🪙 סימבול: `{symbol}`\n"
            f"💰 מחיר כניסה: `{price:.6g}`\n"
            f"📦 כמות: `{qty:.4g}` (`${notional:.2f}`)\n\n"
            f"🛡 סטופ לוס: `{sl:.6g}`\n"
            f"🎯 טייק פרופיט: `{tp:.6g}`\n"
            f"📐 R:R = `{rr}`\n\n"
            f"🤖 ציון ML: `{score:.1f}` — {tier}\n"
            f"💵 יתרה: `${balance:.2f}`\n\n"
            f"🕐 {self._now()}"
        )
        self._broadcast(msg)

    def exit(self, symbol: str, direction: str, entry: float, exit_price: float,
             pnl: float, pnl_pct: float, reason: str, balance: float) -> None:
        won = pnl >= 0
        if won:
            self._session_wins += 1
        else:
            self._session_losses += 1

        emoji = "💰" if pnl > 0.1 else "✅" if won else "❌"
        result = "רווח" if won else "הפסד"

        reason_map = {
            "take_profit": "🎯 טייק פרופיט",
            "stop_loss": "🛑 סטופ לוס",
            "stale_no_move": "⏱ ללא תנועה (stale)",
            "fast_exit_no_move": "⚡ יציאה מהירה — אין תנועה",
            "opposite_pressure": "🔄 לחץ הפוך — מגמה התהפכה",
            "trailing_stop": "📉 טריילינג סטופ",
            "profit_lock": "🔒 נעילת רווח",
            "scalp_take_profit": "🎯 לקיחת רווח מהירה",
            "KILL_SWITCH": "🚨 קיל סוויץ'",
        }
        reason_he = reason_map.get(reason, reason)

        # P&L bar visualization
        pnl_bar = ""
        if won:
            bars = min(int(abs(pnl_pct) * 1000), 10)
            pnl_bar = "🟩" * max(bars, 1)
        else:
            bars = min(int(abs(pnl_pct) * 1000), 10)
            pnl_bar = "🟥" * max(bars, 1)

        # Session win rate
        total = self._session_wins + self._session_losses
        wr = (self._session_wins / total * 100) if total > 0 else 0

        sign = "+" if pnl >= 0 else ""
        msg = (
            f"{emoji} ═══════════════════\n"
            f"  *סגירת עסקה — {result}*\n"
            f"═══════════════════════\n\n"
            f"🪙 `{symbol}` — {direction}\n"
            f"📊 כניסה: `{entry:.6g}` ➜ יציאה: `{exit_price:.6g}`\n\n"
            f"{'💰' if won else '💸'} P&L: `{sign}{pnl:.4f}$` (`{sign}{pnl_pct*100:.2f}%`)\n"
            f"{pnl_bar}\n\n"
            f"📋 סיבה: {reason_he}\n"
            f"💵 יתרה: `${balance:.2f}`\n\n"
            f"📈 סשן: {self._session_wins}W / {self._session_losses}L ({wr:.0f}%)\n"
            f"🕐 {self._now()}"
        )
        self._broadcast(msg)

    def heartbeat(self, balance: float, open_positions: int,
                  session_pnl: float, n_trades: int) -> None:
        sign = "+" if session_pnl >= 0 else ""
        pnl_emoji = "📈" if session_pnl >= 0 else "📉"

        total = self._session_wins + self._session_losses
        wr = (self._session_wins / total * 100) if total > 0 else 0

        # Position indicator
        pos_dots = "🟢" * open_positions + "⚫" * max(0, 2 - open_positions)

        msg = (
            f"💓 ═══════════════════\n"
            f"  *הבוט חי ועובד*\n"
            f"═══════════════════════\n\n"
            f"💵 יתרה: `${balance:.2f}`\n"
            f"📊 פוזיציות: {pos_dots} ({open_positions})\n"
            f"{pnl_emoji} P&L סשן: `{sign}{session_pnl:.2f}$`\n"
            f"🔄 עסקאות: `{n_trades}` ({self._session_wins}W/{self._session_losses}L — {wr:.0f}%)\n"
            f"👥 מנויים: `{len(self._subscribers)}`\n\n"
            f"🕐 {self._now()}"
        )
        self._broadcast(msg)

    def kill_switch(self, reason: str, balance: float) -> None:
        msg = (
            f"🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨\n"
            f"  *קיל סוויץ' הופעל!*\n"
            f"🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨\n\n"
            f"⛔ סיבה: {reason}\n"
            f"💵 יתרה סופית: `${balance:.2f}`\n"
            f"📊 סשן: {self._session_wins}W / {self._session_losses}L\n\n"
            f"⚠️ כל הפוזיציות נסגרות.\n"
            f"🕐 {self._now()}"
        )
        self._broadcast(msg)

    def startup(self, mode: str, balance: float, max_positions: int) -> None:
        """Send startup notification."""
        mode_emoji = "📄" if mode == "PAPER" else "🔴"
        msg = (
            f"🤖 ═══════════════════\n"
            f"  *הבוט התחיל לרוץ*\n"
            f"═══════════════════════\n\n"
            f"{mode_emoji} מצב: `{mode}`\n"
            f"💵 יתרה: `${balance:.2f}`\n"
            f"📊 מקס פוזיציות: `{max_positions}`\n"
            f"⚡ מנוע: HFT Execution Edge\n\n"
            f"🕐 {self._now()}"
        )
        self._broadcast(msg)

    def cooldown(self, reason: str, minutes: float) -> None:
        """Notify that trading is paused due to consecutive losses."""
        self._broadcast(
            f"⏸ ═══════════════════\n"
            f"  *הבוט בהפסקה*\n"
            f"═══════════════════════\n\n"
            f"🧊 סיבה: {reason}\n"
            f"⏱ משך: `{minutes:.0f}` דקות\n"
            f"🛡 יציאות עדיין פעילות\n"
            f"📊 סשן: {self._session_wins}W / {self._session_losses}L\n\n"
            f"🕐 {self._now()}"
        )

    def intelligence_update(self, win_rate: float, score_entry: float,
                            kelly: float, blacklist_count: int,
                            sl_mult: float, tp_mult: float,
                            model_healthy: bool) -> None:
        """Periodic intelligence insights summary."""
        health = "✅ תקין" if model_healthy else "❌ לא תקין — כניסות חסומות!"
        self._broadcast(
            f"🧠 ═══════════════════\n"
            f"  *עדכון אינטליגנציה*\n"
            f"═══════════════════════\n\n"
            f"📊 Win Rate: `{win_rate:.1f}%`\n"
            f"🎯 סף כניסה: `{score_entry:.0f}`\n"
            f"📐 Kelly: `{kelly:.0%}`\n"
            f"🚫 סימבולים חסומים: `{blacklist_count}`\n"
            f"🛡 SL×`{sl_mult:.2f}` | TP×`{tp_mult:.2f}`\n"
            f"🤖 בריאות מודל: {health}\n\n"
            f"🕐 {self._now()}"
        )

    def error(self, message: str) -> None:
        self._broadcast(
            f"⚠️ *שגיאה בבוט*\n\n"
            f"`{message}`\n\n"
            f"🕐 {self._now()}"
        )

    # ------------------------------------------------------------------
    # Polling — listens for /start from new users
    # ------------------------------------------------------------------

    def _poll_loop(self) -> None:
        """Polls Telegram for new messages and handles /start."""
        while self._enabled:
            try:
                url = TELEGRAM_API.format(token=self.token, method="getUpdates")
                resp = requests.get(
                    url,
                    params={"offset": self._update_offset, "timeout": 30, "allowed_updates": ["message"]},
                    timeout=35,
                )
                if resp.status_code == 401:
                    self._disable("טוקן טלגרם לא תקין (401) — האזנה הופסקה")
                    return
                if not resp.ok:
                    continue
                data = resp.json()
                for update in data.get("result", []):
                    self._update_offset = update["update_id"] + 1
                    msg = update.get("message", {})
                    text = msg.get("text", "").strip()
                    chat_id = str(msg.get("chat", {}).get("id", ""))
                    first_name = msg.get("from", {}).get("first_name", "חבר")
                    if not chat_id:
                        continue
                    if text in ("/start", "/subscribe"):
                        if chat_id not in self._subscribers:
                            self._subscribers.add(chat_id)
                            _save_subscribers(_SUBSCRIBERS_FILE, self._subscribers)
                            logger.info("Telegram: מנוי חדש %s (%s)", first_name, chat_id)
                            welcome = (
                                f"👋 שלום {first_name}!\n\n"
                                f"🤖 נרשמת לעדכוני בוט המסחר\n"
                                f"תקבל עדכון על:\n"
                                f"  🟢 כניסה לעסקה\n"
                                f"  ✅❌ סגירת עסקה\n"
                                f"  💓 דופק (כל 5 דקות)\n"
                                f"  🚨 קיל סוויץ'\n\n"
                                f"שלח /stop להפסקת עדכונים\n"
                                f"שלח /status לבדיקת סטטוס"
                            )
                            self._send_to(chat_id, welcome)
                        else:
                            self._send_to(chat_id, "✅ אתה כבר רשום ומקבל עדכונים!")
                    elif text in ("/stop", "/unsubscribe"):
                        if chat_id in self._subscribers:
                            self._subscribers.discard(chat_id)
                            _save_subscribers(_SUBSCRIBERS_FILE, self._subscribers)
                            self._send_to(chat_id, "👋 הוסרת מרשימת העדכונים.")
                    elif text == "/status":
                        self._send_to(
                            chat_id,
                            f"🤖 הבוט פעיל\n"
                            f"📊 סשן: {self._session_wins}W / {self._session_losses}L\n"
                            f"👥 מנויים: {len(self._subscribers)}\n"
                            f"🕐 {self._now()}",
                        )
            except Exception as exc:
                logger.debug("Telegram poll error: %s", exc)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _disable(self, reason: str) -> None:
        """Permanently disable Telegram for this run (e.g. bad token) — stops the spam."""
        if self._enabled:
            logger.warning("TelegramNotifier מושבת אוטומטית: %s", reason)
        self._enabled = False

    def _now(self) -> str:
        il_time = datetime.now(timezone(timedelta(hours=3)))
        return il_time.strftime("%H:%M:%S") + " 🇮🇱"

    def _broadcast(self, text: str) -> None:
        if not self._enabled or not self._subscribers:
            return
        t = threading.Thread(target=self._do_broadcast, args=(text,), daemon=True)
        t.start()

    def _do_broadcast(self, text: str) -> None:
        for chat_id in list(self._subscribers):
            self._send_to(chat_id, text)

    def _send_to(self, chat_id: str, text: str) -> None:
        try:
            url = TELEGRAM_API.format(token=self.token, method="sendMessage")
            resp = requests.post(
                url,
                json={"chat_id": chat_id, "text": text, "parse_mode": "Markdown"},
                timeout=_SEND_TIMEOUT,
            )
            if resp.status_code == 401:
                self._disable("טוקן טלגרם לא תקין (401) — הודעות בוטלו")
                return
            if not resp.ok:
                logger.warning("Telegram שגיאה ל-%s: %s", chat_id, resp.text[:100])
        except Exception as exc:
            logger.debug("Telegram send to %s failed: %s", chat_id, exc)


# Singleton
_instance: Optional[TelegramNotifier] = None


def get_notifier() -> Optional[TelegramNotifier]:
    return _instance


def init_notifier(token: str, chat_id: str, enabled: bool = True) -> TelegramNotifier:
    global _instance
    _instance = TelegramNotifier(token=token, owner_chat_id=chat_id, enabled=enabled)
    return _instance

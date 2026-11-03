"""
בוט חדשות טלגרם — דיווחים מכל העולם על שיגורי טילים ותקיפות, בעברית ובאנגלית.
Telegram news bot — worldwide missile launch / attack reports, in Hebrew & English.

הרצה:
    python -m war_news_bot.bot                 # לולאה רציפה
    python -m war_news_bot.bot --once          # סבב אחד ויציאה
    python -m war_news_bot.bot --dry-run       # מדפיס למסך במקום לשלוח
    python -m war_news_bot.bot --find-chat-id  # מציג את ה-chat_id של הקבוצה

משתני סביבה (.env):
    NEWS_BOT_TOKEN       טוקן מ-@BotFather
    NEWS_CHAT_ID         מזהה הקבוצה/ערוץ (למשל -1001234567890 או @my_channel)
    NEWS_POLL_SECONDS    כל כמה שניות לסרוק RSS (ברירת מחדל 60)
    NEWS_OREF_ENABLED    true/false — התרעות פיקוד העורף (ברירת מחדל true, עובד רק מ-IP ישראלי)
    NEWS_MAX_AGE_MIN     להתעלם מידיעות ישנות מ-X דקות (ברירת מחדל 90)
    NEWS_CHANNEL_NAME    חתימה בסוף כל הודעה (ברירת מחדל "🚀 מאיפה משגרים | Where From?")
    NEWS_CHANNEL_HANDLE  כתובת הערוץ שתופיע בחתימה, למשל @WhereFromLive (אופציונלי)
"""
from __future__ import annotations

import argparse
import html
import json
import logging
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import Iterable, List, Optional

import requests

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:  # python-dotenv אופציונלי
    pass

if __package__ in (None, ""):
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from war_news_bot.sources import DEFAULT_FEEDS, NewsItem, fetch_feed, fetch_oref_alerts
else:
    from .sources import DEFAULT_FEEDS, NewsItem, fetch_feed, fetch_oref_alerts

logger = logging.getLogger("war_news_bot")

STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "war_news_seen.json")
TELEGRAM_API = "https://api.telegram.org/bot{token}/{method}"
IL_TZ = timezone(timedelta(hours=2))  # שעון ישראל (חורף); לתצוגה בלבד

# --------------------------------------------------------------------------- #
# סינון — רק ידיעות על טילים / רקטות / תקיפות
# --------------------------------------------------------------------------- #

KEYWORDS_EN = [
    r"missile", r"rocket(s)? (fire|attack|launch|barrage|strike)", r"rockets? (were )?fired",
    r"ballistic", r"cruise missile", r"hypersonic", r"icbm", r"air ?strike", r"air raid",
    r"drone (attack|strike)", r"\buav\b", r"shahed", r"intercept(ed|ion|or)", r"iron dome",
    r"sirens? (sound|blar|went off)", r"launch(ed|es)? .{0,30}(toward|at|into)", r"barrage",
    r"bombard", r"shelling", r"explosions? (heard|reported|rock)",
]
KEYWORDS_HE = [
    r"טיל", r"טילים", r"רקט", r"שיגור", r"שוגר", r"ירי", r"יירוט", r"יורט", r"כיפת ברזל",
    r"אזעק", r"צבע אדום", r"כטב\"?ם", r"רחפן נפץ", r"תקיפה", r"תקף", r"הפצצ", r"פיצוצ",
    r"חדירת כלי טיס",
]
# מילים שמסמנות "רעש" (ספורט, בורסה וכו')
EXCLUDE = [
    r"stock", r"shares", r"nasdaq", r"football", r"soccer", r"\bnba\b", r"rocket league",
    r"rocket lab", r"spacex", r"starship", r"satellite launch", r"video game", r"movie",
    r"מניות", r"בורסה", r"כדורגל", r"כדורסל",
]
_INC = re.compile("|".join(KEYWORDS_EN + KEYWORDS_HE), re.IGNORECASE)
_EXC = re.compile("|".join(EXCLUDE), re.IGNORECASE)


def is_relevant(item: NewsItem) -> bool:
    if item.is_alert:
        return True
    text = f"{item.title} {item.summary}"
    return bool(_INC.search(text)) and not _EXC.search(text)


# --------------------------------------------------------------------------- #
# תרגום (Google Translate, ללא מפתח API)
# --------------------------------------------------------------------------- #

def translate(text: str, target: str, source: str = "auto",
              session: Optional[requests.Session] = None) -> str:
    if not text:
        return ""
    s = session or requests
    try:
        r = s.get(
            "https://translate.googleapis.com/translate_a/single",
            params={"client": "gtx", "sl": source, "tl": target, "dt": "t", "q": text[:1500]},
            timeout=10,
        )
        r.raise_for_status()
        return "".join(part[0] for part in r.json()[0] if part and part[0]).strip()
    except (requests.RequestException, ValueError, IndexError, TypeError) as e:
        logger.debug("translate failed: %s", e)
        return ""


# --------------------------------------------------------------------------- #
# עיצוב הודעה
# --------------------------------------------------------------------------- #

def _flag(item: NewsItem) -> str:
    t = f"{item.title} {item.summary}".lower()
    if item.is_alert or "צבע אדום" in t or "siren" in t:
        return "🚨"
    if "ballistic" in t or "בליסטי" in t or "missile" in t or "טיל" in t:
        return "🚀"
    if "drone" in t or "כטב" in t or "uav" in t:
        return "🛩"
    return "💥"


def format_message(item: NewsItem, he_title: str, en_title: str,
                   he_summary: str = "", en_summary: str = "") -> str:
    e = html.escape
    when = (item.published or datetime.now(timezone.utc)).astimezone(IL_TZ).strftime("%H:%M %d/%m")
    icon = _flag(item)
    parts = [f"{icon} <b>{e(he_title or item.title)}</b>"]
    if he_summary:
        parts.append(e(he_summary))
    parts.append("")
    parts.append(f"{icon} <b>{e(en_title or item.title)}</b>")
    if en_summary:
        parts.append(e(en_summary))
    parts.append("")
    footer = f"🕒 {when}  |  📰 {e(item.source)}"
    if item.link and item.link.startswith("http"):
        footer += f'  |  <a href="{e(item.link, quote=True)}">קישור / Link</a>'
    parts.append(footer)
    signature = os.getenv("NEWS_CHANNEL_NAME", "🚀 מאיפה משגרים | Where From?").strip()
    handle = os.getenv("NEWS_CHANNEL_HANDLE", "").strip()
    if handle and not handle.startswith("@"):
        handle = "@" + handle
    if signature or handle:
        parts.append(f"<b>{e(signature)}</b>" + (f"  {e(handle)}" if handle else ""))
    return "\n".join(parts)


def build_message(item: NewsItem, session: Optional[requests.Session] = None) -> str:
    summary = item.summary if item.summary and item.summary not in item.title else ""
    summary = summary[:280]
    if item.lang == "he":
        he_title, he_sum = item.title, summary
        en_title = translate(item.title, "en", "iw", session) or item.title
        en_sum = translate(summary, "en", "iw", session) if summary else ""
    else:
        en_title, en_sum = item.title, summary
        he_title = translate(item.title, "iw", "en", session) or item.title
        he_sum = translate(summary, "iw", "en", session) if summary else ""
    return format_message(item, he_title, en_title, he_sum, en_sum)


# --------------------------------------------------------------------------- #
# טלגרם
# --------------------------------------------------------------------------- #

class Telegram:
    def __init__(self, token: str, chat_id: str, session: requests.Session):
        self.token, self.chat_id, self.s = token, chat_id, session

    def call(self, method: str, **params) -> dict:
        r = self.s.post(TELEGRAM_API.format(token=self.token, method=method), json=params, timeout=15)
        data = r.json()
        if not data.get("ok"):
            # הגבלת קצב — מחכים כמה שטלגרם מבקש ומנסים שוב פעם אחת
            retry = (data.get("parameters") or {}).get("retry_after")
            if retry:
                time.sleep(int(retry) + 1)
                r = self.s.post(TELEGRAM_API.format(token=self.token, method=method), json=params, timeout=15)
                data = r.json()
        if not data.get("ok"):
            raise RuntimeError(f"Telegram {method} failed: {data.get('description')}")
        return data

    def send(self, text: str) -> None:
        self.call("sendMessage", chat_id=self.chat_id, text=text, parse_mode="HTML",
                  disable_web_page_preview=True)


def find_chat_id(token: str) -> None:
    r = requests.get(TELEGRAM_API.format(token=token, method="getUpdates"), timeout=15).json()
    if not r.get("ok"):
        print("שגיאה:", r.get("description"))
        return
    seen = set()
    for upd in r.get("result", []):
        msg = upd.get("message") or upd.get("channel_post") or upd.get("my_chat_member") or {}
        chat = msg.get("chat") or {}
        if chat.get("id") and chat["id"] not in seen:
            seen.add(chat["id"])
            print(f"chat_id={chat['id']}  type={chat.get('type')}  title={chat.get('title') or chat.get('username')}")
    if not seen:
        print("לא נמצאו צ'אטים. הוסף את הבוט לקבוצה, שלח בה הודעה כלשהי, והרץ שוב.")


# --------------------------------------------------------------------------- #
# מצב (ידיעות שכבר נשלחו)
# --------------------------------------------------------------------------- #

class SeenStore:
    def __init__(self, path: str, limit: int = 5000):
        self.path, self.limit = path, limit
        self.items: List[str] = []
        try:
            with open(path) as f:
                self.items = json.load(f)
        except (OSError, ValueError):
            pass
        self._set = set(self.items)

    def __contains__(self, uid: str) -> bool:
        return uid in self._set

    def add(self, uid: str) -> None:
        if uid not in self._set:
            self.items.append(uid)
            self._set.add(uid)
            if len(self.items) > self.limit:
                drop = self.items[: len(self.items) - self.limit]
                self.items = self.items[-self.limit:]
                self._set.difference_update(drop)

    def save(self) -> None:
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        tmp = self.path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.items, f)
        os.replace(tmp, self.path)


# --------------------------------------------------------------------------- #
# לולאה ראשית
# --------------------------------------------------------------------------- #

def _env_bool(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


def collect(session: requests.Session, oref: bool) -> List[NewsItem]:
    items: List[NewsItem] = []
    if oref:
        items.extend(fetch_oref_alerts(session))
    for name, url, lang in DEFAULT_FEEDS:
        items.extend(fetch_feed(name, url, lang, session))
    return items


def select_new(items: Iterable[NewsItem], seen: SeenStore, max_age: timedelta) -> List[NewsItem]:
    now = datetime.now(timezone.utc)
    out, batch = [], set()
    for it in items:
        uid = f"oref:{it.extra.get('id')}" if it.is_alert and it.extra.get("id") else it.uid
        if uid in seen or uid in batch:
            continue
        if it.published and now - it.published > max_age:
            continue
        if not is_relevant(it):
            continue
        batch.add(uid)
        it.extra["uid"] = uid
        out.append(it)
    # התרעות קודם, אח"כ מהישן לחדש
    out.sort(key=lambda i: (not i.is_alert, i.published or now))
    return out


def run(once: bool = False, dry_run: bool = False, warmup: bool = True) -> None:
    token = os.getenv("NEWS_BOT_TOKEN", "").strip()
    chat_id = os.getenv("NEWS_CHAT_ID", "").strip()
    if not dry_run and (not token or not chat_id):
        sys.exit("חסר NEWS_BOT_TOKEN או NEWS_CHAT_ID ב-.env (ראה war_news_bot/README.md)")

    poll = max(20, int(os.getenv("NEWS_POLL_SECONDS", "60")))
    oref = _env_bool("NEWS_OREF_ENABLED", True)
    max_age = timedelta(minutes=int(os.getenv("NEWS_MAX_AGE_MIN", "90")))
    max_per_cycle = int(os.getenv("NEWS_MAX_PER_CYCLE", "15"))

    session = requests.Session()
    tg = Telegram(token, chat_id, session) if not dry_run else None
    seen = SeenStore(STATE_FILE)

    # בהפעלה ראשונה: מסמנים את מה שכבר קיים כ"נראה" כדי לא להציף את הקבוצה
    if warmup and not seen.items and not dry_run:
        for it in collect(session, oref=False):
            seen.add(it.uid)
        seen.save()
        logger.info("Warm-up: marked %d existing items as seen", len(seen.items))

    last_rss = 0.0
    while True:
        started = time.time()
        try:
            if started - last_rss >= poll:
                items = collect(session, oref)
                last_rss = started
            else:  # בין סבבי RSS — בודקים רק פיקוד העורף (כל 5 שניות)
                items = fetch_oref_alerts(session) if oref else []
            new = select_new(items, seen, max_age)[:max_per_cycle]
            for it in new:
                msg = build_message(it, session)
                if dry_run:
                    print(msg, "\n" + "-" * 60)
                else:
                    try:
                        tg.send(msg)
                    except (RuntimeError, requests.RequestException) as e:
                        logger.error("send failed: %s", e)
                        continue
                    time.sleep(1.2)  # מתחת למגבלת 20 הודעות/דקה לקבוצה
                seen.add(it.extra["uid"])
            if new:
                seen.save()
                logger.info("Posted %d new items", len(new))
        except Exception:  # הלולאה לא נופלת על שגיאה בודדת
            logger.exception("cycle error")
        if once:
            break
        time.sleep(5 if oref else poll)


def main() -> None:
    p = argparse.ArgumentParser(description="War/missile news → Telegram (HE + EN)")
    p.add_argument("--once", action="store_true", help="סבב אחד ויציאה")
    p.add_argument("--dry-run", action="store_true", help="הדפסה למסך במקום שליחה")
    p.add_argument("--no-warmup", action="store_true", help="לשלוח גם ידיעות קיימות בהפעלה ראשונה")
    p.add_argument("--find-chat-id", action="store_true", help="הצג chat_id של קבוצות שהבוט בהן")
    a = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if a.find_chat_id:
        token = os.getenv("NEWS_BOT_TOKEN", "").strip()
        if not token:
            sys.exit("הגדר NEWS_BOT_TOKEN ב-.env קודם")
        find_chat_id(token)
        return
    run(once=a.once, dry_run=a.dry_run, warmup=not a.no_warmup)


if __name__ == "__main__":
    main()

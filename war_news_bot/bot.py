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
    NEWS_TG_CHANNELS     ערוצי טלגרם ציבוריים לניטור דיווחי שיגור, מופרדים בפסיק (ch1,ch2)
    NEWS_SOCIAL_MIN_SOURCES  כמה ערוצים שונים צריכים לדווח לפני פרסום (ברירת מחדל 2)
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
    from war_news_bot.social import KEYWORDS_AR, KEYWORDS_RU_UA, detect_event, detect_route, fetch_channel, route_line
else:
    from .sources import DEFAULT_FEEDS, NewsItem, fetch_feed, fetch_oref_alerts
    from .social import KEYWORDS_AR, KEYWORDS_RU_UA, detect_event, detect_route, fetch_channel, route_line

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
    r"\bstrik(e|es|ing) (on|at|in|against|targets?)", r"\bstruck\b", r"\bairstrikes?\b",
    r"\b(strikes?|struck|hits?|bomb(s|ed)?) (\w+ ){0,2}(targets|positions|sites|bases|facilit)",
    r"attack(s|ed)? (on|in|against|targets?)", r"\braids?\b on", r"\bpound(s|ed|ing)\b",
    r"(ukrain|russia)\w* (drone|missile|strike|attack)", r"glide bombs?", r"kamikaze",
    r"forces (strike|struck|hit|attack)", r"strik\w* (\S+ ){0,3}(militia|militants|fighters|commander)",
]
KEYWORDS_HE = [
    r"טיל", r"טילים", r"רקט", r"שיגור", r"שוגר", r"ירי", r"יירוט", r"יורט", r"כיפת ברזל",
    r"אזעק", r"צבע אדום", r"כטב\"?ם", r"רחפן נפץ", r"תקיפה", r"תקף", r"הפצצ", r"פיצוצ",
    r"חדירת כלי טיס", r"הותקף", r"הותקפו", r"מתקפ", r"תקיפות",
]
# מילים שמסמנות "רעש" (ספורט, בורסה וכו')
EXCLUDE = [
    r"stock", r"shares", r"nasdaq", r"football", r"soccer", r"\bnba\b", r"rocket league",
    r"rocket lab", r"spacex", r"starship", r"satellite launch", r"video game", r"movie",
    r"מניות", r"בורסה", r"כדורגל", r"כדורסל",
    r"hunger strike", r"general strike", r"workers? (on )?strike", r"strike action", r"on strike",
    r"heart attack", r"panic attack", r"cyber", r"shark attack", r"lucky strike", r"bowling",
]
_INC = re.compile("|".join(KEYWORDS_EN + KEYWORDS_HE + KEYWORDS_AR + KEYWORDS_RU_UA), re.IGNORECASE)
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
    if any(k in t for k in ("ballistic", "בליסטי", "missile", "טיל", "صاروخ", "صواريخ", "باليستي")):
        return "🚀"
    if "drone" in t or "כטב" in t or "uav" in t or "مسير" in t:
        return "🛩"
    return "💥"


def format_message(item: NewsItem, he_title: str, en_title: str,
                   he_summary: str = "", en_summary: str = "",
                   corroborated_by: int = 1) -> str:
    e = html.escape
    when = (item.published or datetime.now(timezone.utc)).astimezone(IL_TZ).strftime("%H:%M %d/%m")
    icon = _flag(item)
    social = bool(item.extra.get("social"))
    route_he, route_en = route_line(*detect_event(f"{item.title} {item.summary}"))
    if not route_he and en_title:  # גיבוי: זיהוי על התרגום לאנגלית
        route_he, route_en = route_line(*detect_event(f"{en_title} {en_summary}"))
    parts = []
    if social:
        parts.append("⚠️ <b>דיווח ראשוני מהרשת — לא מאומת</b> | <i>Unverified early report</i>")
        if corroborated_by > 1:
            parts.append(f"👥 מדווח ב־{corroborated_by} ערוצים | Reported by {corroborated_by} channels")
        parts.append("")
    parts.append(f"{icon} <b>{e(he_title or item.title)}</b>")
    if he_summary:
        parts.append(e(he_summary))
    if route_he:
        parts.append(route_he)
    parts.append("")
    parts.append(f"{icon} <b>{e(en_title or item.title)}</b>")
    if en_summary:
        parts.append(e(en_summary))
    if route_en:
        parts.append(route_en)
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


def build_message(item: NewsItem, session: Optional[requests.Session] = None,
                  corroborated_by: int = 1) -> str:
    summary = item.summary if item.summary and item.summary not in item.title else ""
    summary = summary[:280]
    if item.lang not in ("he", "en"):  # ערבית / רוסית / אוקראינית → מתרגמים לשתיהן
        src = "ar" if item.lang == "ar" else "auto"
        he_title = translate(item.title, "iw", src, session) or item.title
        en_title = translate(item.title, "en", src, session) or item.title
        he_sum = translate(summary, "iw", src, session) if summary else ""
        en_sum = translate(summary, "en", src, session) if summary else ""
    elif item.lang == "he":
        he_title, he_sum = item.title, summary
        en_title = translate(item.title, "en", "iw", session) or item.title
        en_sum = translate(summary, "en", "iw", session) if summary else ""
    else:
        en_title, en_sum = item.title, summary
        he_title = translate(item.title, "iw", "en", session) or item.title
        he_sum = translate(summary, "iw", "en", session) if summary else ""
    return format_message(item, he_title, en_title, he_sum, en_sum, corroborated_by)


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

    def send(self, text: str) -> Optional[int]:
        data = self.call("sendMessage", chat_id=self.chat_id, text=text, parse_mode="HTML",
                         disable_web_page_preview=True)
        return (data.get("result") or {}).get("message_id")

    def edit(self, message_id: int, text: str) -> None:
        self.call("editMessageText", chat_id=self.chat_id, message_id=message_id, text=text,
                  parse_mode="HTML", disable_web_page_preview=True)


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


def select_new(items: Iterable[NewsItem], seen: SeenStore, max_age: timedelta,
               social_max_age: Optional[timedelta] = None) -> List[NewsItem]:
    now = datetime.now(timezone.utc)
    out, batch = [], set()
    for it in items:
        if it.extra.get("uid"):
            uid = it.extra["uid"]
        elif it.is_alert and it.extra.get("id"):
            uid = f"oref:{it.extra.get('id')}"
        else:
            uid = it.uid
        if uid in seen or uid in batch:
            continue
        limit = social_max_age if (it.extra.get("social") and social_max_age) else max_age
        if it.published and now - it.published > limit:
            continue
        if not is_relevant(it):
            continue
        batch.add(uid)
        it.extra["uid"] = uid
        out.append(it)
    # התרעות קודם, אח"כ מהישן לחדש
    out.sort(key=lambda i: (not i.is_alert, i.published or now))
    return out


class SocialClusters:
    """
    מאחד דיווחי רשת על אותו אירוע: דיווחים מערוצים שונים עם אותו מקור שיגור
    בתוך חלון זמן קצר = אירוע אחד. ההודעה נשלחת כשמגיעים ל-min_sources ערוצים,
    ודיווחים נוספים רק מעדכנים את מונה הערוצים בהודעה הקיימת (עריכה).
    """

    def __init__(self, window: timedelta, min_sources: int):
        self.window, self.min_sources = window, max(1, min_sources)
        self.clusters: List[dict] = []

    def add(self, item: NewsItem, now: Optional[datetime] = None) -> Optional[dict]:
        now = now or datetime.now(timezone.utc)
        self.clusters = [c for c in self.clusters if now - c["started"] <= self.window]
        origin, _ = detect_route(f"{item.title} {item.summary}")
        key = origin or "?"
        c = next((c for c in self.clusters if c["key"] == key), None)
        if c is None:
            c = {"key": key, "started": now, "channels": set(), "item": item, "message_id": None}
            self.clusters.append(c)
        channel = item.extra.get("channel", "")
        if channel in c["channels"]:
            return None  # אותו ערוץ שוב — לא מחזק את הדיווח
        c["channels"].add(channel)
        n = len(c["channels"])
        if n < self.min_sources:
            return None
        if c["message_id"] is None and not c.get("sent"):
            c["sent"] = True
            return {"action": "send", "cluster": c, "item": c["item"], "count": n}
        return {"action": "edit", "cluster": c, "item": c["item"], "count": n}


def run(once: bool = False, dry_run: bool = False, warmup: bool = True) -> None:
    token = os.getenv("NEWS_BOT_TOKEN", "").strip()
    chat_id = os.getenv("NEWS_CHAT_ID", "").strip()
    if not dry_run and (not token or not chat_id):
        sys.exit("חסר NEWS_BOT_TOKEN או NEWS_CHAT_ID ב-.env (ראה war_news_bot/README.md)")

    poll = max(20, int(os.getenv("NEWS_POLL_SECONDS", "60")))
    oref = _env_bool("NEWS_OREF_ENABLED", True)
    max_age = timedelta(minutes=int(os.getenv("NEWS_MAX_AGE_MIN", "90")))
    max_per_cycle = int(os.getenv("NEWS_MAX_PER_CYCLE", "15"))
    channels = [c.strip().lstrip("@") for c in os.getenv("NEWS_TG_CHANNELS", "").split(",") if c.strip()]
    social_poll = max(10, int(os.getenv("NEWS_SOCIAL_POLL_SECONDS", "15")))
    social_max_age = timedelta(minutes=int(os.getenv("NEWS_SOCIAL_MAX_AGE_MIN", "15")))
    clusters = SocialClusters(
        window=timedelta(minutes=int(os.getenv("NEWS_SOCIAL_WINDOW_MIN", "10"))),
        min_sources=int(os.getenv("NEWS_SOCIAL_MIN_SOURCES", "2")),
    )

    session = requests.Session()
    tg = Telegram(token, chat_id, session) if not dry_run else None
    seen = SeenStore(STATE_FILE)

    def fetch_social() -> List[NewsItem]:
        out: List[NewsItem] = []
        for ch in channels:
            out.extend(fetch_channel(ch, session))
        return out

    # בהפעלה ראשונה: מסמנים את מה שכבר קיים כ"נראה" כדי לא להציף את הקבוצה
    if warmup and not seen.items and not dry_run:
        for it in collect(session, oref=False) + fetch_social():
            seen.add(it.extra.get("uid") or it.uid)
        seen.save()
        logger.info("Warm-up: marked %d existing items as seen", len(seen.items))
    if channels:
        logger.info("Watching %d Telegram channels (min %d sources to post)",
                    len(channels), clusters.min_sources)

    def post(text: str) -> Optional[int]:
        if dry_run:
            print(text, "\n" + "-" * 60)
            return None
        mid = tg.send(text)
        time.sleep(1.2)  # מתחת למגבלת 20 הודעות/דקה לקבוצה
        return mid

    last_rss = last_social = 0.0
    while True:
        started = time.time()
        try:
            items: List[NewsItem] = []
            if oref:
                items.extend(fetch_oref_alerts(session))  # כל 5 שניות
            if started - last_rss >= poll:
                items.extend(collect(session, oref=False))
                last_rss = started
            if channels and started - last_social >= social_poll:
                items.extend(fetch_social())
                last_social = started
            new = select_new(items, seen, max_age, social_max_age)[:max_per_cycle]
            sent = 0
            for it in new:
                try:
                    if it.extra.get("social"):
                        act = clusters.add(it)
                        if act and act["action"] == "send":
                            act["cluster"]["message_id"] = post(
                                build_message(act["item"], session, act["count"]))
                            sent += 1
                        elif act and act["action"] == "edit" and act["cluster"]["message_id"]:
                            tg.edit(act["cluster"]["message_id"],
                                    build_message(act["item"], session, act["count"]))
                    else:
                        post(build_message(it, session))
                        sent += 1
                except (RuntimeError, requests.RequestException) as e:
                    logger.error("send failed: %s", e)
                    continue
                seen.add(it.extra["uid"])
            if new:
                seen.save()
            if sent:
                logger.info("Posted %d new items", sent)
        except Exception:  # הלולאה לא נופלת על שגיאה בודדת
            logger.exception("cycle error")
        if once:
            break
        time.sleep(5 if (oref or channels) else poll)


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

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
    NEWS_CHANNEL_NAME    חתימה בסוף כל הודעה (ברירת מחדל "🚨 חדשות חירום")
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
    # קודם קובץ ההגדרות של הבוט עצמו (war_news_bot/.env), אחר כך ה-.env הראשי של הפרויקט
    load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))
    load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))
except ImportError:  # python-dotenv אופציונלי
    pass

if __package__ in (None, ""):
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from war_news_bot.sources import DEFAULT_FEEDS, NewsItem, fetch_alerts, fetch_feed, fetch_oref_alerts
    from war_news_bot import geo
    from war_news_bot.social import KEYWORDS_AR, KEYWORDS_RU_UA, DEFAULT_CHANNELS, KEYWORDS_FA, PLACES, MIDEAST_LAUNCHERS, PRETRANSLATE, apply_hint, is_escalation, is_eyewitness, detect_event, detect_route, fetch_channel, route_line
else:
    from .sources import DEFAULT_FEEDS, NewsItem, fetch_alerts, fetch_feed, fetch_oref_alerts
    from . import geo
    from .social import KEYWORDS_AR, KEYWORDS_RU_UA, DEFAULT_CHANNELS, KEYWORDS_FA, PLACES, MIDEAST_LAUNCHERS, PRETRANSLATE, apply_hint, is_escalation, is_eyewitness, detect_event, detect_route, fetch_channel, route_line

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
    r"forces (strike|struck|hit|attack)", r"\bstrikes? (?:from|by)\b", r"(?:was|were|been) targeted", r"strik\w* (\S+ ){0,3}(militia|militants|fighters|commander)",
]
KEYWORDS_HE = [
    r"טיל", r"טילים", r"רקט", r"שיגור", r"שוגר", r"ירי", r"יירוט", r"יורט", r"כיפת ברזל",
    r"אזעק", r"צבע אדום", r"כטב\"?ם", r"רחפן נפץ", r"תקיפה", r"תקף", r"הפצצ", r"פיצוצ",
    r"חדירת כלי טיס", r"מבצע (?:צבאי|קרקעי|אווירי)", r"הותקף", r"הותקפו", r"מתקפ", r"תקיפות",
]
# מילים שמסמנות "רעש" (ספורט, בורסה וכו')
EXCLUDE = [
    r"stock", r"shares", r"nasdaq", r"football", r"soccer", r"\bnba\b", r"rocket league",
    r"rocket lab", r"spacex", r"starship", r"satellite launch", r"video game", r"movie",
    r"מניות", r"בורסה", r"כדורגל", r"כדורסל",
    r"hunger strike", r"general strike", r"workers? (on )?strike", r"strike action", r"on strike",
    r"heart attack", r"panic attack", r"cyber", r"shark attack", r"lucky strike", r"bowling",
    r"bitcoin", r"crypto", r"price prediction", r"presale", r"ביטקוין", r"קריפטו",
    # פרסומות ומבצעי קניות (לא "מבצע צבאי")
    r"₪", r"\bהנח(?:ה|ות)\b", r"קופון", r"משלוח חינם", r"לרכישה", r"להזמנות", r"פרסומת", r"תוכן ממומן",
    r"שיתוף פעולה בתשלום", r"מבצעי(?:ם)? (?:שלא|מטורפים|ענק|חגיגיים|סוף)", r"shopping", r"black friday",
    r"blue november", r"cyber monday", r"sponsored", r"promo ?code", r"discount", r"\d+% off", r"buy now",
    r"#ad\b", r"#ads\b", r"реклам", r"скидк", r"промокод", r"إعلان", r"خصم", r"عرض خاص", r"تخفيض", r"تخفیف",
    r"آگهی", r"تبلیغ", r"casino", r"הימור", r"\bbetting\b",
]
_INC = re.compile("|".join(KEYWORDS_EN + KEYWORDS_HE + KEYWORDS_AR + KEYWORDS_RU_UA + KEYWORDS_FA), re.IGNORECASE)
_EXC = re.compile("|".join(EXCLUDE), re.IGNORECASE)


def is_relevant(item: NewsItem) -> bool:
    if item.is_alert:
        return True
    text = f"{item.title} {item.summary}"
    if _EXC.search(text):
        return False
    return bool(_INC.search(text)) or is_escalation(text) or is_eyewitness(text)


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


def event_for(item: NewsItem, en_title: str = "", en_summary: str = ""):
    """(סוג, מקור, יעד) — מהטקסט, גיבוי מהתרגום לאנגלית, ותיקון לפי ערוץ המקור."""
    ev = detect_event(f"{item.title} {item.summary}")
    if not ev[1] and en_title:
        ev = detect_event(f"{en_title} {en_summary}")
    if item.extra.get("social"):
        ev = apply_hint(item.extra.get("channel", ""), *ev)
    return ev


def format_message(item: NewsItem, he_title: str, en_title: str,
                   he_summary: str = "", en_summary: str = "",
                   corroborated_by: int = 1) -> str:
    e = html.escape
    when = (item.published or datetime.now(timezone.utc)).astimezone(IL_TZ).strftime("%H:%M %d/%m")
    icon = _flag(item)
    social = bool(item.extra.get("social"))
    ev = event_for(item, en_title, en_summary)
    if ev[0] == "tension":
        icon = "⚔️"
    elif ev[0] == "witness":
        icon = "👂"
    route_he, route_en = route_line(*ev)
    en_on = _env_bool("NEWS_INCLUDE_ENGLISH", False)  # ברירת מחדל: עברית בלבד

    def bi(he: str, en: str) -> str:
        return f"{he} | <i>{en}</i>" if en_on else he
    # רמת אמינות: רשמי (פיקוד העורף) / דיווח רשת / ידיעה שבה לא זוהה מי שיגר-תקף ולאן
    unclear = not item.is_alert and not route_he
    parts = []
    if item.is_alert:
        parts.append(bi("✅ <b>התרעה רשמית — פיקוד העורף</b>", "Official alert"))
        parts.append("")
    elif social:
        parts.append(bi("⚠️ <b>דיווח ראשוני מהרשת — לא מאומת</b>", "Unverified early report"))
        if corroborated_by > 1:
            parts.append(bi(f"👥 מדווח ב־{corroborated_by} ערוצים", f"Reported by {corroborated_by} channels"))
        if unclear:
            parts.append(bi("❓ מקור ויעד לא זוהו", "Origin/target unclear"))
        parts.append("")
    elif unclear:
        parts.append(bi("⚠️ <b>דיווח לא מאומת — פרטים לא ברורים</b>", "Unverified — details unclear"))
        parts.append("")
    parts.append(f"{icon} <b>{e(he_title or item.title)}</b>")
    if he_summary:
        parts.append(e(he_summary))
    if route_he:
        parts.append(route_he)
    for line in item.extra.get("extra_lines", []):
        parts.append(line)
    parts.append("")
    if en_on:
        parts.append(f"{icon} <b>{e(en_title or item.title)}</b>")
        if en_summary:
            parts.append(e(en_summary))
        if route_en:
            parts.append(route_en)
        parts.append("")
    footer = f"🕒 {when}  |  📰 {e(item.source)}"
    if item.link and item.link.startswith("http"):
        footer += f'  |  <a href="{e(item.link, quote=True)}">{"קישור / Link" if en_on else ("לאתר ההתרעות" if item.is_alert else "לכתבה המלאה")}</a>'
    parts.append(footer)
    signature = os.getenv("NEWS_CHANNEL_NAME", DEFAULT_TITLE).strip()
    handle = os.getenv("NEWS_CHANNEL_HANDLE", "").strip()
    if handle and not handle.startswith("@"):
        handle = "@" + handle
    if signature or handle:
        parts.append(f"<b>{e(signature)}</b>" + (f"  {e(handle)}" if handle else ""))
    return "\n".join(parts)


def _strip_outlet(title: str) -> str:
    """Google News מוסיף " - שם האתר" לכותרת; המקור כבר מופיע בשורה התחתונה."""
    return re.sub(r"\s+[-–|]\s+[^-–|]{2,40}$", "", title).strip()


def _norm(t: str) -> str:
    return re.sub(r"[^\w\u0590-\u05FF\u0600-\u06FF\u0400-\u04FF]+", " ", t.lower()).strip()


def build_message(item: NewsItem, session: Optional[requests.Session] = None,
                  corroborated_by: int = 1) -> str:
    if item.source.startswith("Google News"):
        item.title = _strip_outlet(item.title)
    summary = item.summary or ""
    if _norm(summary).startswith(_norm(item.title)[:60]) or _norm(summary) in _norm(item.title):
        summary = ""  # התקציר רק חוזר על הכותרת
    summary = summary[:280]
    if item.lang not in ("he", "en"):  # ערבית / רוסית / אוקראינית → מתרגמים לשתיהן
        src = item.lang if item.lang in ("ar", "fa") else "auto"
        title, summ = item.title, summary
        for rx, repl in PRETRANSLATE:
            title, summ = rx.sub(repl, title), rx.sub(repl, summ)
        he_title = translate(title, "iw", src, session) or item.title
        en_title = translate(title, "en", src, session) or item.title
        he_sum = translate(summ, "iw", src, session) if summ else ""
        en_sum = translate(summ, "en", src, session) if summ else ""
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

    def send_photo(self, png: bytes, caption: str) -> Optional[int]:
        """תמונה + כיתוב. כיתוב ארוך מ-1024 תווים נשלח כהודעה נפרדת."""
        api = TELEGRAM_API.format(token=self.token, method="sendPhoto")
        data = {"chat_id": self.chat_id, "parse_mode": "HTML"}
        long = len(caption) > 1000
        if not long:
            data["caption"] = caption
        r = self.s.post(api, data=data, files={"photo": ("map.png", png, "image/png")}, timeout=30).json()
        if not r.get("ok"):
            raise RuntimeError(f"Telegram sendPhoto failed: {r.get('description')}")
        mid = (r.get("result") or {}).get("message_id")
        return self.send(caption) if long else mid

    def edit_caption(self, message_id: int, caption: str) -> None:
        self.call("editMessageCaption", chat_id=self.chat_id, message_id=message_id,
                  caption=caption[:1024], parse_mode="HTML")

    def edit(self, message_id: int, text: str) -> None:
        self.call("editMessageText", chat_id=self.chat_id, message_id=message_id, text=text,
                  parse_mode="HTML", disable_web_page_preview=True)


DEFAULT_TITLE = "🚨 חדשות חירום"

CHANNEL_DESCRIPTION = (
    "🚨 חדשות חירום בזמן אמת: שיגורי טילים, רקטות, כטב\"מים, אזעקות ותקיפות — "
    "ישראל, איראן, ארה\"ב, לבנון, תימן, עזה, רוסיה ואוקראינה. "
    "מבזקים מעשרות מקורות, מתורגמים לעברית.\n"
    "⚠️ ערוץ אוטומטי — אינו מחליף את פיקוד העורף"
)

WELCOME = (
    "🚨 <b>ברוכים הבאים לחדשות חירום</b>\n\n"
    "כאן מתפרסמים <b>אוטומטית ובזמן אמת</b> מבזקי חירום: שיגורי טילים ורקטות, כטב\"מים, אזעקות, "
    "תקיפות והסלמה — מישראל, איראן, ארה\"ב, לבנון, תימן, עזה, רוסיה, אוקראינה ועוד. הכול בעברית.\n\n"
    "<b>מקורות:</b> התרעות פיקוד העורף, אתרי חדשות בעולם, וכ־40 ערוצי טלגרם בעברית, ערבית, פרסית, רוסית ואוקראינית — "
    "מתורגמים אוטומטית לעברית.\n\n"
    "<b>מה אומרים הסימונים:</b>\n"
    "✅ <b>התרעה רשמית</b> — פיקוד העורף\n"
    "⚠️ <b>דיווח ראשוני מהרשת — לא מאומת</b> (👥 = כמה ערוצים דיווחו)\n"
    "⚠️ <b>פרטים לא ברורים</b> — לא זוהה מי שיגר/תקף ולאן\n"
    "📍 מקור ויעד שיגור  |  🎯 תוקף ויעד  |  ⚔️ הסלמה\n"
    "🚨 אזעקה  🚀 טילים  🛩 כטב\"מים  💥 תקיפות\n\n"
    "⚠️ <b>הערוץ אוטומטי ואינו מחליף את אפליקציית פיקוד העורף.</b> בזמן אזעקה — פעלו לפי הנחיות פיקוד העורף."
)


def _welcome(tg: "Telegram", chat_id: str) -> None:
    """עורך את הודעת הפתיחה הנעוצה הקיימת, או שולח חדשה."""
    pinned = ((tg.call("getChat", chat_id=chat_id).get("result") or {}).get("pinned_message") or {})
    if pinned.get("message_id"):
        try:
            tg.edit(pinned["message_id"], WELCOME)
        except RuntimeError as e:
            if "not modified" not in str(e):
                raise
        tg._welcome_existing = True
        return
    tg._welcome = tg.send(WELCOME)


def setup_channel(token: str, chat_id: str, logo_path: str) -> None:
    """מגדיר את הערוץ: שם, תמונה, תיאור, הודעת פתיחה נעוצה (מעדכן את הקיימת אם יש)."""
    s = requests.Session()
    tg = Telegram(token, chat_id, s)
    title = os.getenv("NEWS_CHANNEL_TITLE", DEFAULT_TITLE).strip()
    try:
        tg.call("setChatTitle", chat_id=chat_id, title=title)
        print("שם ערוץ: ✅", title)
    except (RuntimeError, requests.RequestException) as e:
        print(f"שם ערוץ: {'✅ (ללא שינוי)' if 'not modified' in str(e) else '❌ ' + str(e)}")
    api = TELEGRAM_API.format(token=token, method="setChatPhoto")
    try:
        with open(logo_path, "rb") as f:
            r = s.post(api, data={"chat_id": chat_id}, files={"photo": f}, timeout=30).json()
        print("תמונת ערוץ:", "✅" if r.get("ok") else f"❌ {r.get('description')}")
    except OSError as e:
        print("תמונת ערוץ: ❌", e)
    for label, fn in [
        ("תיאור ערוץ", lambda: tg.call("setChatDescription", chat_id=chat_id, description=CHANNEL_DESCRIPTION)),
        ("הודעת פתיחה", lambda: _welcome(tg, chat_id)),
    ]:
        try:
            fn()
            print(f"{label}: ✅")
        except (RuntimeError, requests.RequestException) as e:
            print(f"{label}: ❌ {e}")
    mid = None if getattr(tg, "_welcome_existing", False) else getattr(tg, "_welcome", None)
    if mid:
        try:
            tg.call("pinChatMessage", chat_id=chat_id, message_id=mid, disable_notification=True)
            print("נעיצת הודעה: ✅")
        except (RuntimeError, requests.RequestException) as e:
            print(f"נעיצת הודעה: ❌ {e}")


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
        items.extend(fetch_alerts(session))
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


class AlertTracker:
    """בזמן מטח פיקוד העורף מוסיף יישובים לאותה התרעה — מפרסמים רק יישובים חדשים (חלון 3 דקות)."""

    def __init__(self, window_s: int = 180):
        self.window_s, self.last = window_s, {}

    def new_areas(self, areas: List[str]) -> List[str]:
        now = time.time()
        self.last = {a: t for a, t in self.last.items() if now - t < self.window_s}
        fresh = [a for a in areas if a not in self.last]
        for a in areas:
            self.last[a] = now
        return fresh


class RecentLaunches:
    """דיווחי שיגור אחרונים לישראל — כדי לדעת "מאיפה" כשמגיעה התרעה."""

    def __init__(self, window_s: int = 1200):
        self.window_s, self.items = window_s, []

    def add(self, origin: str) -> None:
        self.items.append((time.time(), origin))

    def latest(self) -> Optional[str]:
        now = time.time()
        self.items = [(t, o) for t, o in self.items if now - t < self.window_s]
        return self.items[-1][1] if self.items else None


def enrich_alert(item: NewsItem, recent: Optional["RecentLaunches"], session=None) -> Optional[bytes]:
    """מוסיף להתרעה זמן התגוננות + כיוון משוער, ומחזיר מפה (PNG) אם אפשר."""
    pts = geo.city_points(item.extra.get("areas", []), session)
    lines = []
    if pts:
        cd = min(p[2] for p in pts)
        lines.append(f"⏱ זמן להגעה למרחב מוגן: {'מיידי' if cd <= 15 else f'{cd} שניות'}")
    origin, how = (recent.latest() if recent else None), "לפי דיווח שיגור"
    if not origin:
        origin, how = geo.estimate_origin(pts), "הערכה לפי מיקום ההתרעות"
    if origin and origin != "IL" and origin in PLACES:
        f, he = PLACES[origin][0], PLACES[origin][1]
        lines.append(f"🧭 כיוון משוער: {f} {he} ← 🇮🇱 ישראל ({how})")
    else:
        origin = None
    item.extra["extra_lines"] = lines
    if not _env_bool("NEWS_MAPS", True):
        return None
    try:
        return geo.render_map(pts, origin, "IL", session)
    except Exception:  # noqa: BLE001 — מפה היא תוספת; לא מפילים התרעה בגללה
        logger.exception("map render failed")
        return None


def launch_map(item: NewsItem, session=None) -> Optional[bytes]:
    """מפת "מאיפה לאיפה" לדיווח שיגור עם מקור ידוע."""
    if not _env_bool("NEWS_MAPS", True):
        return None
    kind, origin, target = event_for(item)
    if kind != "launch" or not origin or not target or origin == target:
        return None  # בלי מקור ויעד ברורים — אין מפה (לא מנחשים יעד)
    try:
        return geo.render_map([], origin, target, session)
    except Exception:  # noqa: BLE001
        logger.exception("map render failed")
        return None


class SocialClusters:
    """
    מאחד דיווחי רשת על אותו אירוע: דיווחים מערוצים שונים עם אותו מקור שיגור
    בתוך חלון זמן קצר = אירוע אחד. ההודעה נשלחת כשמגיעים ל-min_sources ערוצים,
    ודיווחים נוספים רק מעדכנים את מונה הערוצים בהודעה הקיימת (עריכה).
    """

    def __init__(self, window: timedelta, min_sources: int):
        self.window, self.min_sources = window, max(1, min_sources)
        self.clusters: List[dict] = []
        self.trusted: set = set()  # ערוצים שמספיק דיווח אחד מהם

    def add(self, item: NewsItem, now: Optional[datetime] = None) -> Optional[dict]:
        now = now or datetime.now(timezone.utc)
        self.clusters = [c for c in self.clusters if now - c["started"] <= self.window]
        kind, origin, target = event_for(item)
        channel = item.extra.get("channel", "")
        if kind == "tension":
            key = "T:" + "-".join(sorted([origin, target]))
        elif kind == "witness" and origin:
            key = "W:" + origin  # דיווחי תושבים מאותו מקום — אירוע אחד
        elif origin:
            key = origin
        elif channel.lower() in self.trusted:
            key = "?" + item.extra.get("uid", item.uid)  # לא ברור, אבל מערוץ מהימן — הודעה נפרדת
        else:
            return None  # לא ברור ומערוץ לא מהימן — לא מפרסמים
        c = next((c for c in self.clusters if c["key"] == key), None)
        if c is None:
            c = {"key": key, "started": now, "channels": set(), "item": item, "message_id": None}
            self.clusters.append(c)
        if channel in c["channels"]:
            return None  # אותו ערוץ שוב — לא מחזק את הדיווח
        c["channels"].add(channel)
        n = len(c["channels"])
        if n < self.min_sources and channel.lower() not in self.trusted:
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
    env_ch = os.getenv("NEWS_TG_CHANNELS", "default").strip()
    if env_ch.lower() in ("", "default"):
        channels = [c for c, _, _ in DEFAULT_CHANNELS]
    elif env_ch.lower() in ("none", "off", "false"):
        channels = []
    else:
        channels = [c.strip().lstrip("@") for c in env_ch.split(",") if c.strip()]
    trusted = {c.lower() for c, _, t in DEFAULT_CHANNELS if t}
    trusted |= {c.strip().lstrip("@").lower() for c in os.getenv("NEWS_TG_TRUSTED", "").split(",") if c.strip()}
    social_poll = max(10, int(os.getenv("NEWS_SOCIAL_POLL_SECONDS", "15")))
    social_max_age = timedelta(minutes=int(os.getenv("NEWS_SOCIAL_MAX_AGE_MIN", "15")))
    clusters = SocialClusters(
        window=timedelta(minutes=int(os.getenv("NEWS_SOCIAL_WINDOW_MIN", "10"))),
        min_sources=int(os.getenv("NEWS_SOCIAL_MIN_SOURCES", "2")),
    )
    clusters.trusted = trusted

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
        logger.info("Watching %d Telegram channels (min %d sources to post, trusted: %s)",
                    len(channels), clusters.min_sources, ", ".join(sorted(trusted)) or "-")

    alerts_seen = AlertTracker()
    recent = RecentLaunches()

    def post(text: str, png: Optional[bytes] = None) -> Optional[int]:
        if dry_run:
            print(text, "\n" + ("[+ מפה]" if png else "") + "-" * 60)
            if png and os.getenv("NEWS_DRY_RUN_MAP_DIR"):
                with open(os.path.join(os.getenv("NEWS_DRY_RUN_MAP_DIR"), f"map_{int(time.time()*1000)}.png"), "wb") as f:
                    f.write(png)
            return None
        mid = tg.send_photo(png, text) if png else tg.send(text)
        time.sleep(1.2)  # מתחת למגבלת 20 הודעות/דקה לקבוצה
        return mid

    last_rss = last_social = 0.0
    while True:
        started = time.time()
        try:
            items: List[NewsItem] = []
            if oref:  # התרעות — כל 5 שניות, מטופלות מיד ובנפרד
                for al in fetch_alerts(session):
                    fresh = alerts_seen.new_areas(al.extra.get("areas", []))
                    if not fresh:
                        continue
                    al = NewsItem(**{**al.__dict__, "extra": dict(al.extra)})
                    al.extra["areas"] = fresh
                    al.title = al.title.split(":")[0] + ": " + ", ".join(fresh[:25]) + (
                        f" ועוד {len(fresh) - 25}" if len(fresh) > 25 else "")
                    try:
                        png = enrich_alert(al, recent, session)
                        post(build_message(al, session), png)
                        logger.info("Alert posted: %d areas", len(fresh))
                    except (RuntimeError, requests.RequestException) as e:
                        logger.error("alert send failed: %s", e)
            if started - last_rss >= poll:
                items.extend(collect(session, oref=False))
                last_rss = started
            if channels and started - last_social >= social_poll:
                items.extend(fetch_social())
                last_social = started
            new = select_new(items, seen, max_age, social_max_age)[:max_per_cycle]
            sent = 0
            for it in new:
                if it.is_alert:
                    seen.add(it.extra["uid"])
                    continue  # התרעות מטופלות למעלה
                ev = event_for(it)
                if ev[0] == "launch" and ev[2] == "IL" and ev[1] in MIDEAST_LAUNCHERS:
                    recent.add(ev[1])  # רק שיגור מפורש לישראל משמש לכיוון של התרעה
                try:
                    if it.extra.get("social"):
                        act = clusters.add(it)
                        if act and act["action"] == "send":
                            png = launch_map(act["item"], session)
                            act["cluster"]["is_photo"] = bool(png)
                            act["cluster"]["message_id"] = post(
                                build_message(act["item"], session, act["count"]), png)
                            sent += 1
                        elif act and act["action"] == "edit" and act["cluster"]["message_id"]:
                            text = build_message(act["item"], session, act["count"])
                            if act["cluster"].get("is_photo"):
                                tg.edit_caption(act["cluster"]["message_id"], text)
                            else:
                                tg.edit(act["cluster"]["message_id"], text)
                    else:
                        post(build_message(it, session), launch_map(it, session))
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


def check_channels() -> None:
    """מדפיס לכל ערוץ: נגיש? כמה פוסטים, כמה רלוונטיים, ודוגמה."""
    env_ch = os.getenv("NEWS_TG_CHANNELS", "default").strip()
    chans = ([c for c, _, _ in DEFAULT_CHANNELS] if env_ch.lower() in ("", "default")
             else [c.strip().lstrip("@") for c in env_ch.split(",") if c.strip()])
    s = requests.Session()
    for ch in chans:
        posts = fetch_channel(ch, s)
        rel = [p for p in posts if is_relevant(p)]
        last = max((p.published for p in posts if p.published), default=None)
        status = "✅" if posts else "❌ לא נגיש / אין תצוגה ציבורית"
        print(f"{status} @{ch}: {len(posts)} פוסטים, {len(rel)} רלוונטיים"
              + (f", אחרון: {last.astimezone(IL_TZ):%d/%m %H:%M}" if last else ""))
        if rel:
            print("    לדוגמה:", rel[-1].title[:100])


def main() -> None:
    p = argparse.ArgumentParser(description="War/missile news → Telegram (HE + EN)")
    p.add_argument("--once", action="store_true", help="סבב אחד ויציאה")
    p.add_argument("--dry-run", action="store_true", help="הדפסה למסך במקום שליחה")
    p.add_argument("--no-warmup", action="store_true", help="לשלוח גם ידיעות קיימות בהפעלה ראשונה")
    p.add_argument("--find-chat-id", action="store_true", help="הצג chat_id של קבוצות שהבוט בהן")
    p.add_argument("--check-channels", action="store_true", help="בדוק אילו ערוצי טלגרם נגישים ומה הם מפרסמים")
    p.add_argument("--setup-channel", action="store_true", help="הגדר לערוץ תמונה, תיאור והודעת פתיחה נעוצה")
    a = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if a.find_chat_id:
        token = os.getenv("NEWS_BOT_TOKEN", "").strip()
        if not token:
            sys.exit("הגדר NEWS_BOT_TOKEN ב-.env קודם")
        find_chat_id(token)
        return
    if a.setup_channel:
        token, chat = os.getenv("NEWS_BOT_TOKEN", "").strip(), os.getenv("NEWS_CHAT_ID", "").strip()
        if not token or not chat:
            sys.exit("חסר NEWS_BOT_TOKEN או NEWS_CHAT_ID")
        setup_channel(token, chat, os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "logo.png"))
        return
    if a.check_channels:
        check_channels()
        return
    run(once=a.once, dry_run=a.dry_run, warmup=not a.no_warmup)


if __name__ == "__main__":
    main()

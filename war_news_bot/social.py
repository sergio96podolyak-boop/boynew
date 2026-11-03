"""
דיווחי רשת — ערוצי טלגרם ציבוריים (בעיקר בערבית) שבהם מדווחים על שיגורים בזמן אמת,
וזיהוי מקור/יעד השיגור מתוך הטקסט.

Social reports — public Telegram channels where people post launch sightings,
plus launch origin/target extraction from free text (HE / EN / AR).

קריאת ערוץ: דרך תצוגת הרשת הציבורית https://t.me/s/<channel> — בלי חשבון ובלי מפתחות.
עובד רק לערוצים ציבוריים שהפעילו תצוגה מקדימה (רוב ערוצי החדשות).
"""
from __future__ import annotations

import html
import logging
import re
from datetime import datetime, timezone
from typing import List, Optional, Tuple

import requests

from .sources import NewsItem

logger = logging.getLogger(__name__)

_UA = "Mozilla/5.0 (compatible; WarNewsBot/1.0)"

# --------------------------------------------------------------------------- #
# זיהוי שפה
# --------------------------------------------------------------------------- #

_AR = re.compile(r"[؀-ۿ]")
_HE = re.compile(r"[֐-׿]")


def detect_lang(text: str) -> str:
    ar, he = len(_AR.findall(text)), len(_HE.findall(text))
    if ar > he and ar > 5:
        return "ar"
    if he > 5:
        return "he"
    return "en"


# --------------------------------------------------------------------------- #
# מילות מפתח בערבית (נוספות לעברית/אנגלית שב-bot.py)
# --------------------------------------------------------------------------- #

KEYWORDS_AR = [
    r"صاروخ", r"صواريخ", r"إطلاق", r"اطلاق", r"انطلاق", r"رشقة", r"رشقات", r"باليستي",
    r"مسيرة", r"مسيّرة", r"مسيرات", r"طائرة مسيرة", r"صفارات الإنذار", r"صافرات الإنذار",
    r"اعتراض", r"قصف", r"غارة", r"غارات", r"انفجار", r"انفجارات", r"دوي",
]

# --------------------------------------------------------------------------- #
# מקור / יעד
# --------------------------------------------------------------------------- #

# קוד → (דגל, שם בעברית, שם באנגלית, ביטויים לזיהוי)
PLACES = {
    "IR": ("🇮🇷", "איראן", "Iran", [r"iran", r"איראן", r"إيران", r"ايران"]),
    "YE": ("🇾🇪", "תימן", "Yemen", [r"yemen", r"houthi", r"תימן", r"חות'?י", r"اليمن", r"الحوثي", r"صنعاء"]),
    "LB": ("🇱🇧", "לבנון", "Lebanon", [r"lebanon", r"hezbollah", r"לבנון", r"חיזבאללה", r"لبنان", r"حزب الله"]),
    "GZ": ("🇵🇸", "עזה", "Gaza", [r"gaza", r"hamas", r"עזה", r"חמאס", r"غزة", r"حماس"]),
    "IQ": ("🇮🇶", "עיראק", "Iraq", [r"iraq", r"עיראק", r"العراق"]),
    "SY": ("🇸🇾", "סוריה", "Syria", [r"syria", r"סוריה", r"سوريا", r"سورية"]),
    "RU": ("🇷🇺", "רוסיה", "Russia", [r"russia", r"רוסיה", r"روسيا"]),
    "UA": ("🇺🇦", "אוקראינה", "Ukraine", [r"ukrain", r"kyiv", r"אוקראינה", r"קייב", r"أوكرانيا", r"كييف"]),
    "IL": ("🇮🇱", "ישראל", "Israel", [r"israel", r"tel aviv", r"ישראל", r"תל אביב", r"إسرائيل", r"اسرائيل",
                                     r"الأراضي المحتلة", r"تل أبيب", r"الكيان", r"حيفا", r"إيلات", r"ایلات",
                                     r"אילת", r"חיפה", r"באר שבע", r"ירושלים", r"הגליל", r"גוש דן",
                                     r"eilat", r"haifa", r"jerusalem", r"القدس", r"الجليل"]),
    "SA": ("🇸🇦", "סעודיה", "Saudi Arabia", [r"saudi", r"סעודיה", r"السعودية"]),
    "KP": ("🇰🇵", "צפון קוריאה", "North Korea", [r"north korea", r"pyongyang", r"צפון קוריאה"]),
}

# תבניות "מ־X" / "לעבר X" בכל שפה. {p} = ביטוי המקום.
_FROM = [r"\bfrom (?:the )?(?:{p})", r"(?:{p})\w*\s+(?:launch|fire)", r"\bמ(?:{p})",
         r"من (?:{p})", r"انطلاق[^.\n]{{0,25}}(?:{p})"]
_TO = [r"\b(?:toward|towards|at|on|into|over) (?:the )?(?:{p})", r"(?:לעבר|לכיוון|אל|על|ב)\s?(?:{p})",
       r"(?:نحو|باتجاه|على|إلى|الى) (?:{p})"]


def _match(text: str, templates: List[str]) -> Optional[str]:
    best: Tuple[int, Optional[str]] = (10 ** 9, None)
    for code, (_, _, _, pats) in PLACES.items():
        p = "|".join(pats)
        for t in templates:
            m = re.search(t.format(p=p), text, re.IGNORECASE)
            if m and m.start() < best[0]:
                best = (m.start(), code)
    return best[1]


def detect_route(text: str) -> Tuple[Optional[str], Optional[str]]:
    """מחזיר (מקור, יעד) כקודים, או None. מבוסס על הטקסט בלבד — "לפי הדיווח"."""
    origin = _match(text, _FROM)
    target = _match(text, _TO)
    if target == origin:
        target = None
    if origin and not target and origin != "IL":
        # שיגור מהמזרח התיכון בלי יעד מפורש — אם ישראל מוזכרת, היא כנראה היעד
        if re.search("|".join(PLACES["IL"][3]), text, re.IGNORECASE):
            target = "IL"
    return origin, target


def route_line(origin: Optional[str], target: Optional[str]) -> Tuple[str, str]:
    """שורת מסלול בעברית ובאנגלית, או מחרוזות ריקות."""
    if not origin:
        return "", ""
    fo, ho, eo, _ = PLACES[origin]
    he = f"📍 מקור לפי הדיווח: {fo} {ho}"
    en = f"📍 Reported origin: {fo} {eo}"
    if target:
        ft, ht, et, _ = PLACES[target]
        he += f"  ←  יעד: {ft} {ht}"
        en += f"  →  target: {ft} {et}"
    return he, en


# --------------------------------------------------------------------------- #
# קריאת ערוץ טלגרם ציבורי
# --------------------------------------------------------------------------- #

_POST = re.compile(r'data-post="([\w]+/\d+)"(.*?)(?=data-post="|\Z)', re.S)
_TEXT = re.compile(r'<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>', re.S)
_TIME = re.compile(r'<time[^>]*datetime="([^"]+)"')


def _html_to_text(s: str) -> str:
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"[ \t]+", " ", s).strip()


def parse_channel_page(page: str, channel: str) -> List[NewsItem]:
    items: List[NewsItem] = []
    for m in _POST.finditer(page):
        post_id, body = m.group(1), m.group(2)
        tm = _TEXT.search(body)
        if not tm:
            continue  # פוסט בלי טקסט (תמונה בלבד וכו')
        text = _html_to_text(tm.group(1))
        if not text:
            continue
        published = None
        dm = _TIME.search(body)
        if dm:
            try:
                published = datetime.fromisoformat(dm.group(1).replace("Z", "+00:00"))
            except ValueError:
                pass
        first, _, rest = text.partition("\n")
        items.append(NewsItem(
            title=first[:220],
            summary=rest.strip()[:400],
            link=f"https://t.me/{post_id}",
            source=f"טלגרם @{channel}",
            published=published or datetime.now(timezone.utc),
            lang=detect_lang(text),
            extra={"social": True, "channel": channel, "uid": f"tg:{post_id}", "full_text": text},
        ))
    return items


def fetch_channel(channel: str, session: requests.Session) -> List[NewsItem]:
    channel = channel.strip().lstrip("@")
    if not channel:
        return []
    try:
        r = session.get(f"https://t.me/s/{channel}", timeout=15, headers={"User-Agent": _UA})
        r.raise_for_status()
        return parse_channel_page(r.text, channel)
    except requests.RequestException as e:
        logger.warning("Telegram channel failed @%s: %s", channel, e)
        return []

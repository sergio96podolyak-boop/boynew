"""
מקורות חדשות — RSS עולמיים + התרעות פיקוד העורף.
News sources — global RSS feeds + Israel Home Front Command (Pikud HaOref) alerts.

כל מקור מחזיר רשימת NewsItem. אין תלויות חוץ מ-requests (פענוח RSS ב-xml.etree).
"""
from __future__ import annotations

import email.utils
import hashlib
import html
import json
import logging
import re
import urllib.parse
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional

import requests

logger = logging.getLogger(__name__)

_HTTP_TIMEOUT = 15
_UA = "Mozilla/5.0 (compatible; WarNewsBot/1.0)"


@dataclass
class NewsItem:
    title: str
    link: str
    source: str
    summary: str = ""
    published: Optional[datetime] = None
    lang: str = "en"  # שפת המקור: "en" / "he"
    is_alert: bool = False  # התרעה רשמית (פיקוד העורף) — נשלחת תמיד, ללא סינון מילים
    extra: dict = field(default_factory=dict)

    @property
    def uid(self) -> str:
        # Google News מוסיף " - שם האתר" בסוף הכותרת — מסירים לפני נרמול
        base = re.sub(r"\s+[-–|]\s+[^-–|]{2,40}$", "", self.title)
        norm = re.sub(r"[^\w\u0590-\u05FF]+", " ", base.lower()).strip()
        return hashlib.sha1(norm.encode("utf-8")).hexdigest()


# --------------------------------------------------------------------------- #
# RSS
# --------------------------------------------------------------------------- #

def _google_news(query: str, lang: str) -> str:
    q = urllib.parse.quote(f"{query} when:1h")
    if lang == "he":
        return f"https://news.google.com/rss/search?q={q}&hl=iw&gl=IL&ceid=IL:he"
    if lang == "ar":
        return f"https://news.google.com/rss/search?q={q}&hl=ar&gl=EG&ceid=EG:ar"
    return f"https://news.google.com/rss/search?q={q}&hl=en-US&gl=US&ceid=US:en"


# (שם, כתובת, שפה)
DEFAULT_FEEDS = [
    # חיפושי Google News — מכסים אלפי אתרים בכל העולם
    ("Google News", _google_news('"missile launch" OR "missiles launched" OR "ballistic missile"', "en"), "en"),
    ("Google News", _google_news('"rocket attack" OR "rockets fired" OR "drone attack" OR airstrike', "en"), "en"),
    ("Google News", _google_news('"missile strike" OR "air raid" OR "sirens sounded" OR "intercepted"', "en"), "en"),
    ("Google News", _google_news('שיגור טילים OR ירי רקטות OR אזעקות OR יירוט', "he"), "he"),
    ("Google News", _google_news('תקיפה אווירית OR כטב"ם OR טיל בליסטי', "he"), "he"),
    ("Google News", _google_news('"Russian strike" OR "Russian missile" OR "Russian drones" OR "Shahed drones"', "en"), "en"),
    ("Google News", _google_news('"Ukrainian drones" OR "Ukrainian strike" OR "Ukraine attacks" OR "air raid alert" Ukraine', "en"), "en"),
    ("Google News", _google_news('"Israeli strike" OR "Israeli airstrike" OR "US strike" OR "strikes on"', "en"), "en"),
    ("Google News", _google_news('רוסיה תקפה OR מתקפה על אוקראינה OR מתקפת רחפנים OR צה"ל תקף', "he"), "he"),
    # ארה"ב / איראן / ישראל — הסלמה ומלחמה
    ("Google News", _google_news('Iran (Israel OR "United States" OR US) (war OR escalation OR retaliation OR strike OR threat)', "en"), "en"),
    ("Google News", _google_news('IRGC OR "Revolutionary Guard" OR "aircraft carrier" Iran OR "Iran nuclear"', "en"), "en"),
    ("Google News", _google_news('איראן ארה"ב OR איראן ישראל OR הסלמה מול איראן OR משמרות המהפכה', "he"), "he"),
    # ערבית
    ("Google News", _google_news('صواريخ OR غارة OR قصف OR مسيرة إسرائيل OR إيران OR اليمن OR لبنان', "ar"), "ar"),
    ("Google News", _google_news('إيران أمريكا OR إيران إسرائيل تصعيد OR الحرس الثوري', "ar"), "ar"),
    ("BBC Arabic", "https://feeds.bbci.co.uk/arabic/rss.xml", "ar"),
    ("Iran International", "https://www.iranintl.com/en/feed", "en"),
    # אתרי חדשות ישירים
    ("Times of Israel", "https://www.timesofisrael.com/feed/", "en"),
    ("BBC World", "https://feeds.bbci.co.uk/news/world/rss.xml", "en"),
    ("Kyiv Independent", "https://kyivindependent.com/news-archive/rss/", "en"),
    ("Ukrainska Pravda", "https://www.pravda.com.ua/eng/rss/", "en"),
    ("Meduza", "https://meduza.io/rss/en/all", "en"),
    ("ynet מבזקים", "https://www.ynet.co.il/Integration/StoryRss1854.xml", "he"),
    ("וואלה חדשות", "https://rss.walla.co.il/feed/1?type=main", "he"),
]


def _strip_html(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def _parse_date(value: str) -> Optional[datetime]:
    if not value:
        return None
    try:
        dt = email.utils.parsedate_to_datetime(value)
    except (TypeError, ValueError):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def parse_rss(xml_text: str, source: str, lang: str) -> List[NewsItem]:
    """מפענח RSS 2.0 או Atom."""
    items: List[NewsItem] = []
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as e:
        logger.warning("RSS parse error (%s): %s", source, e)
        return items

    atom = "{http://www.w3.org/2005/Atom}"
    entries = root.findall(".//item") or root.findall(f".//{atom}entry")
    for el in entries:
        def txt(tag: str) -> str:
            node = el.find(tag)
            if node is None:
                node = el.find(atom + tag)
            return (node.text or "") if node is not None else ""

        title = _strip_html(txt("title"))
        link = txt("link").strip()
        if not link:
            node = el.find(atom + "link")
            if node is not None:
                link = node.get("href", "")
        summary = _strip_html(txt("description") or txt("summary"))
        published = _parse_date(txt("pubDate") or txt("published") or txt("updated"))
        src_node = el.find("source")
        src = source
        if src_node is not None and src_node.text:
            src = f"{source} / {src_node.text.strip()}"
        if title:
            items.append(NewsItem(title=title, link=link, source=src,
                                  summary=summary[:400], published=published, lang=lang))
    return items


def fetch_feed(name: str, url: str, lang: str, session: requests.Session) -> List[NewsItem]:
    try:
        r = session.get(url, timeout=_HTTP_TIMEOUT, headers={"User-Agent": _UA})
        r.raise_for_status()
        return parse_rss(r.text, name, lang)
    except requests.RequestException as e:
        logger.warning("Feed failed %s: %s", name, e)
        return []


# --------------------------------------------------------------------------- #
# פיקוד העורף — התרעות בזמן אמת (עובד רק מכתובת IP בישראל)
# --------------------------------------------------------------------------- #

OREF_URL = "https://www.oref.org.il/warningMessages/alert/Alerts.json"
TZOFAR_URL = "https://api.tzevaadom.co.il/notifications"
_BROWSER_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
               "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")

# קודי איום של צופר
TZOFAR_THREATS = {
    0: "ירי רקטות וטילים", 1: "חומרים מסוכנים", 2: "חשש לחדירת מחבלים", 3: "רעידת אדמה",
    4: "חשש לצונאמי", 5: "חדירת כלי טיס עוין", 6: "אירוע רדיולוגי", 7: "ירי בלתי קונבנציונלי",
}


def _alert_item(title: str, areas: List[str], desc: str, source: str, link: str, extra: dict) -> NewsItem:
    shown = ", ".join(areas[:25]) + (f" ועוד {len(areas) - 25}" if len(areas) > 25 else "")
    return NewsItem(
        title=f"{title}: {shown}", link=link, source=source, summary=desc,
        published=datetime.now(timezone.utc), lang="he", is_alert=True,
        extra={"areas": list(areas), **extra},
    )


def fetch_oref_alerts(session: requests.Session) -> List[NewsItem]:
    """התרעות פיקוד העורף (עובד מכתובת IP בישראל)."""
    headers = {"User-Agent": _BROWSER_UA, "Referer": "https://www.oref.org.il/",
               "X-Requested-With": "XMLHttpRequest", "Accept": "application/json, text/plain, */*"}
    try:
        r = session.get(OREF_URL, timeout=10, headers=headers)
        r.raise_for_status()
        body = r.content.decode("utf-8-sig").strip()
        if not body:
            return []  # אין התרעה פעילה
        data = json.loads(body)
    except (requests.RequestException, ValueError) as e:
        logger.debug("Oref fetch failed: %s", e)
        return []
    areas = data.get("data") or []
    if not areas:
        return []
    return [_alert_item(data.get("title") or "התרעה", areas, data.get("desc") or "", "פיקוד העורף",
                        "https://www.oref.org.il/", {"id": str(data.get("id") or ""), "cat": data.get("cat")})]


def fetch_tzofar_alerts(session: requests.Session) -> List[NewsItem]:
    """גיבוי: התרעות פעילות מצופר (tzevaadom)."""
    try:
        r = session.get(TZOFAR_URL, timeout=10, headers={"User-Agent": _BROWSER_UA})
        r.raise_for_status()
        data = r.json()
    except (requests.RequestException, ValueError) as e:
        logger.debug("Tzofar fetch failed: %s", e)
        return []
    out = []
    for n in data if isinstance(data, list) else []:
        if not isinstance(n, dict) or n.get("isDrill"):
            continue
        areas = n.get("cities") or []
        if not areas:
            continue
        title = TZOFAR_THREATS.get(n.get("threat"), "התרעה")
        out.append(_alert_item(title, areas, "", "פיקוד העורף (דרך צופר)", "https://www.tzevaadom.co.il/",
                               {"id": str(n.get("notificationId") or n.get("time") or ""), "threat": n.get("threat")}))
    return out


def fetch_alerts(session: requests.Session) -> List[NewsItem]:
    """פיקוד העורף, ואם אין — צופר."""
    return fetch_oref_alerts(session) or fetch_tzofar_alerts(session)

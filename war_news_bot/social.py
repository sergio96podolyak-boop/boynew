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
_CY = re.compile(r"[Ѐ-ӿ]")


_FA = re.compile(r"[پچژگ]|ی|ک")  # אותיות שקיימות בפרסית ולא בערבית


def detect_lang(text: str) -> str:
    """he / en / ar / fa / ru (ru = כל טקסט בקירילית — רוסית או אוקראינית; התרגום מזהה לבד)."""
    counts = {"ar": len(_AR.findall(text)), "he": len(_HE.findall(text)), "ru": len(_CY.findall(text))}
    lang, n = max(counts.items(), key=lambda kv: kv[1])
    if n <= 5:
        return "en"
    if lang == "ar" and len(_FA.findall(text)) >= 3:
        return "fa"
    return lang


# --------------------------------------------------------------------------- #
# מילות מפתח בערבית, רוסית ואוקראינית (נוספות לעברית/אנגלית שב-bot.py)
# --------------------------------------------------------------------------- #

KEYWORDS_AR = [
    r"صاروخ", r"صواريخ", r"إطلاق", r"اطلاق", r"انطلاق", r"رشقة", r"رشقات", r"باليستي",
    r"مسيرة", r"مسيّرة", r"مسيرات", r"طائرة مسيرة", r"صفارات الإنذار", r"صافرات الإنذار",
    r"اعتراض", r"قصف", r"غارة", r"غارات", r"انفجار", r"انفجارات", r"دوي", r"هجوم", r"استهداف",
]
KEYWORDS_FA = [
    r"موشک", r"پهپاد", r"حمله", r"شلیک", r"انفجار", r"پدافند", r"رهگیری", r"بمباران", r"آژیر",
]
KEYWORDS_RU_UA = [
    r"ракет", r"обстрел", r"обстріл", r"удар", r"шахед", r"дрон", r"бпла", r"беспилотн",
    r"безпілотн", r"тревог", r"тривог", r"пво", r"ппо", r"взрыв", r"вибух", r"атак", r"сбит", r"збит",
]

# --------------------------------------------------------------------------- #
# מקור / יעד / תוקף
# --------------------------------------------------------------------------- #

# קוד → (דגל, שם בעברית, שם באנגלית, ביטויים לזיהוי — כולל שמות תואר וערים מרכזיות)
PLACES = {
    "IL": ("🇮🇱", "ישראל", "Israel", [
        r"israel", r"\bidf\b", r"tel aviv", r"eilat", r"haifa", r"jerusalem",
        r"ישראל", r"צה\"?ל", r"תל אביב", r"אילת", r"חיפה", r"באר שבע", r"ירושלים", r"הגליל", r"גוש דן",
        r"إسرائيل", r"اسرائيل", r"الأراضي المحتلة", r"تل أبيب", r"الكيان", r"حيفا", r"إيلات", r"القدس",
        r"الجليل", r"Израил", r"اسرائیل", r"صهیونیست", r"رژیم صهیونی", r"تل‌آویو"]),
    "IR": ("🇮🇷", "איראן", "Iran", [r"iran", r"tehran", r"hormuz", r"qeshm", r"bandar abbas", r"הורמוז", r"هرمز", r"איראן", r"טהרן", r"إيران", r"ايران", r"طهران", r"Иран", r"ایران", r"تهران", r"سپاه",
                                   r"irgc", r"revolutionary guard", r"משמרות המהפכה", r"الحرس الثوري"]),
    "YE": ("🇾🇪", "תימן", "Yemen", [r"yemen", r"houthi", r"sanaa", r"תימן", r"חות'?י", r"צנעא",
                                    r"اليمن", r"الحوثي", r"صنعاء", r"Йемен"]),
    "LB": ("🇱🇧", "לבנון", "Lebanon", [r"lebanon", r"hezbollah", r"beirut", r"לבנון", r"חיזבאללה", r"ביירות",
                                       r"لبنان", r"حزب الله", r"بيروت", r"Ливан"]),
    "GZ": ("🇵🇸", "עזה", "Gaza", [r"gaza", r"hamas", r"עזה", r"חמאס", r"غزة", r"حماس", r"Газ[аеы]"]),
    "IQ": ("🇮🇶", "עיראק", "Iraq", [r"iraq", r"baghdad", r"עיראק", r"בגדד", r"العراق", r"بغداد", r"Ирак"]),
    "SY": ("🇸🇾", "סוריה", "Syria", [r"syria", r"damascus", r"סוריה", r"דמשק", r"سوريا", r"سورية", r"دمشق", r"Сири"]),
    "JO": ("🇯🇴", "ירדן", "Jordan", [r"jordan", r"amman", r"ירדן", r"עמאן", r"الأردن", r"عمان"]),
    "EG": ("🇪🇬", "מצרים", "Egypt", [r"egypt", r"cairo", r"מצרים", r"קהיר", r"مصر", r"القاهرة"]),
    "SA": ("🇸🇦", "סעודיה", "Saudi Arabia", [r"saudi", r"riyadh", r"סעודיה", r"ריאד", r"السعودية", r"الرياض"]),
    "AE": ("🇦🇪", "איחוד האמירויות", "UAE", [r"\buae\b", r"emirates", r"abu dhabi", r"dubai", r"אמירויות",
                                            r"דובאי", r"الإمارات", r"دبي", r"أبوظبي"]),
    "QA": ("🇶🇦", "קטאר", "Qatar", [r"qatar", r"doha", r"קטאר", r"דוחה", r"قطر", r"الدوحة"]),
    "TR": ("🇹🇷", "טורקיה", "Turkey", [r"turkey", r"t[üu]rkiye", r"turkish", r"טורקיה", r"تركيا", r"Турци"]),
    "US": ("🇺🇸", "ארה\"ב", "USA", [r"\bu\.?s\.?(?= (?:strikes?|struck|forces|military|navy|army|air|attack|bomb|warplanes|jets|missile|launch))",
                                    r"united states", r"american", r"pentagon", r"ארה\"?ב", r"אמריק",
                                    r"الولايات المتحدة", r"أمريك", r"الأمريكي", r"США", r"американ", r"آمریکا",
                                    r"(?-i:\bUS\b)", r"\bu\.s\.", r"centcom", r"פנטגון", r"البنتاغون", r"واشنطن", r"washington", r"וושינגטון",
                                    r"trump", r"טראמפ", r"ترامب", r"ترامپ", r"carrier strike group"]),
    "RU": ("🇷🇺", "רוסיה", "Russia", [r"russia", r"moscow", r"kremlin", r"belgorod", r"kursk", r"bryansk",
                                     r"רוסי", r"מוסקבה", r"בלגורוד", r"קורסק", r"روسيا", r"روسي", r"موسكو",
                                     r"Росси", r"российск", r"Москв", r"Белгород", r"Курск", r"Брянск",
                                     r"Росі", r"російськ"]),
    "UA": ("🇺🇦", "אוקראינה", "Ukraine", [r"ukrain", r"kyiv", r"kiev", r"kharkiv", r"odesa", r"odessa",
                                         r"lviv", r"dnipro", r"zaporizh", r"אוקראינ", r"קייב", r"חרקוב",
                                         r"אודסה", r"לבוב", r"دنيبرو", r"أوكرانيا", r"أوكراني", r"كييف",
                                         r"Украин", r"Україн", r"Киев", r"Київ", r"Харк[оі]в", r"Одес", r"Льв[оі]в",
                                         r"Днепр", r"Дніпр", r"Запор"]),
    "BY": ("🇧🇾", "בלארוס", "Belarus", [r"belarus", r"minsk", r"בלארוס", r"بيلاروس", r"Беларус", r"Білорус"]),
    "PL": ("🇵🇱", "פולין", "Poland", [r"poland", r"polish", r"פולין", r"بولندا", r"Польш", r"Польщ"]),
    "KP": ("🇰🇵", "צפון קוריאה", "North Korea", [r"north korea", r"pyongyang", r"צפון קוריאה", r"كوريا الشمالية",
                                                 r"КНДР", r"Северн\w* Коре"]),
    "KR": ("🇰🇷", "דרום קוריאה", "South Korea", [r"south korea", r"seoul", r"דרום קוריאה", r"كوريا الجنوبية"]),
    "JP": ("🇯🇵", "יפן", "Japan", [r"japan", r"tokyo", r"יפן", r"اليابان", r"Япони"]),
    "CN": ("🇨🇳", "סין", "China", [r"china", r"chinese", r"beijing", r"סין", r"الصين", r"Кита"]),
    "TW": ("🇹🇼", "טייוואן", "Taiwan", [r"taiwan", r"טייוואן", r"تايوان", r"Тайван"]),
    "IN": ("🇮🇳", "הודו", "India", [r"\bindia", r"new delhi", r"הודו", r"الهند"]),
    "PK": ("🇵🇰", "פקיסטן", "Pakistan", [r"pakistan", r"פקיסטן", r"باكستان"]),
    "SD": ("🇸🇩", "סודן", "Sudan", [r"sudan", r"khartoum", r"סודן", r"السودان", r"الخرطوم"]),
}
_PAT = {code: "|".join(v[3]) for code, v in PLACES.items()}

# שיגור: "מ־X" / "לעבר Y". {p} = ביטויי המקום.
_FROM = [r"\bfrom (?:the )?(?:{p})", r"(?:{p})\w*\s+(?:launch|fire)", r"\bמ(?:{p})",
         r"من (?:{p})", r"انطلاق[^.\n]{{0,25}}(?:{p})", r"(?:из|з|со) (?:{p})"]
_TO = [r"\b(?:toward|towards|at|on|into|over|against) (?:the )?(?:{p})",
       r"(?:לעבר|לכיוון|אל|על|ב)\s?(?:{p})",
       r"(?:نحو|باتجاه|على|إلى|الى|في) (?:{p})",
       r"(?:по|на|в|над) (?:{p})"]

# תקיפה: "X תקף את Y" / "Israeli strikes on Lebanon" / "غارات إسرائيلية على لبنان"
_STRIKE_VERB = (r"(?:strikes?|struck|attack(?:s|ed)?|bomb(?:s|ed|ing)?|hits?|shell(?:s|ed|ing)?|"
                r"pounds?|raids?|airstrikes?|drones? (?:hit|attack|strike)|missiles? (?:hit|strike))")
_STRIKE = [
    r"(?:{a})\w*\s+(?:\w+\s+){{0,3}}?" + _STRIKE_VERB + r"\s+(?:\w+\s+){{0,4}}?(?:in |on |at |against )?(?:the )?(?:{t})(?![\w-]*-backed)",
    r"(?:{a})\w*\s+(?:תקף|תקפה|תקפו|הפציץ|הפציצה|הפציצו|תוקף|תוקפת|תוקפים)\s+(?:\S+\s+){{0,4}}?(?:את |ב|ב־|ב-)?(?:{t})",
    r"(?:תקיפ\w*|הפצצ\w*)\s+(?:\S+\s+){{0,2}}?(?:של |)(?:{a})\w*\s+(?:\S+\s+){{0,3}}?(?:ב|על |ב־|ב-)(?:{t})",
    r"(?:غارة|غارات|قصف|هجوم|ضربة|ضربات)\s+(?:\S+\s+){{0,1}}?(?:{a})\S*\s+(?:\S+\s+){{0,2}}?(?:على|في|ضد) (?:\S+\s+){{0,2}}?(?:{t})",
    r"(?:{a})\S*\s+(?:\S+\s+){{0,4}}?(?:удар|атак|обстрел|обстріл)\S*\s+(?:\S+\s+){{0,3}}?(?:по|на|в) (?:\S+\s+){{0,1}}?(?:{t})",
]


def _match(text: str, templates: List[str]) -> Optional[str]:
    best: Tuple[int, Optional[str]] = (10 ** 9, None)
    for code, p in _PAT.items():
        for t in templates:
            m = re.search(t.format(p=p), text, re.IGNORECASE)
            if m and m.start() < best[0]:
                best = (m.start(), code)
    return best[1]


def _match_strike(text: str) -> Tuple[Optional[str], Optional[str]]:
    best: Tuple[int, Optional[str], Optional[str]] = (10 ** 9, None, None)
    for a, pa in _PAT.items():
        if not re.search(pa, text, re.IGNORECASE):
            continue
        for t, pt in _PAT.items():
            if a == t or not re.search(pt, text, re.IGNORECASE):
                continue
            for tpl in _STRIKE:
                m = re.search(tpl.format(a=pa, t=pt), text, re.IGNORECASE)
                if m and m.start() < best[0]:
                    best = (m.start(), a, t)
    return best[1], best[2]


# הסלמה / מתיחות (איומים, נקמה, תזוזות כוחות) — בין ארה"ב, איראן וישראל (ומעורבים נוספים)
ESCALATION = re.compile("|".join([
    r"escalat", r"retaliat", r"revenge", r"vows? (?:to )?(?:respond|retaliate|revenge)", r"\bthreat(?:en|ens|ened)?\b",
    r"\bwarn(?:s|ed|ing)?\b", r"\bvow", r"aggression", r"consequences", r"ultimatum", r"high alert", r"mobiliz", r"\bdeploy", r"aircraft carrier",
    r"carrier strike group", r"\bb-2\b", r"bombers?", r"war (?:with|against|on)", r"all-out war", r"nuclear (?:site|facilit|program|deal)",
    r"enrichment", r"\bwar\b", r"ceasefire", r"seiz(?:e|ed|ure) (?:of )?(?:a |an )?(?:tanker|ship|vessel)",
    r"הסלמה", r"נקמה", r"איום", r"איים", r"מאיים", r"כוננות", r"נושאת מטוסים", r"מפציצ", r"גרעין", r"מלחמה", r"הפסקת אש",
    r"תגובה", r"אולטימטום", r"תוגבר", r"פריסת",
    r"تصعيد", r"انتقام", r"تهديد", r"يهدد", r"توعد", r"حاملة طائرات", r"قاذفات", r"النووي", r"حرب", r"استنفار",
    r"وقف إطلاق النار", r"الرد",
    r"تهدید", r"انتقام", r"جنگ", r"هسته‌ای", r"ناو هواپیمابر", r"پاسخ",
    r"эскалац", r"угрож", r"ядерн", r"войн",
]), re.IGNORECASE)
TENSION_PARTIES = ("US", "IR", "IL")


def _parties(text: str) -> List[str]:
    """המעורבים מתוך ארה\"ב/איראן/ישראל לפי סדר ההופעה בטקסט."""
    found = []
    for code in TENSION_PARTIES:
        m = re.search(_PAT[code], text, re.IGNORECASE)
        if m:
            found.append((m.start(), code))
    return [c for _, c in sorted(found)]


def is_escalation(text: str) -> bool:
    return bool(ESCALATION.search(text)) and len(_parties(text)) >= 2


def detect_event(text: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    מחזיר (סוג, מקור/תוקף, יעד): סוג = "launch" (שיגור) / "strike" (תקיפה) /
    "tension" (הסלמה בין ארה"ב/איראן/ישראל) / None.
    מבוסס על הטקסט בלבד — "לפי הדיווח".
    """
    attacker, victim = _match_strike(text)
    origin = _match(text, _FROM)
    if attacker and (not origin or origin == attacker):
        return "strike", attacker, victim
    if origin:
        target = _match(text, _TO)
        if target == origin:
            target = None
        if not target and origin != "IL" and re.search(_PAT["IL"], text, re.IGNORECASE):
            # שיגור מהמזרח התיכון בלי יעד מפורש — אם ישראל מוזכרת, היא כנראה היעד
            target = "IL"
        return "launch", origin, target
    if is_escalation(text):
        p = _parties(text)
        return "tension", p[0], p[1]
    return None, None, None


def detect_route(text: str) -> Tuple[Optional[str], Optional[str]]:
    """(מקור/תוקף, יעד) — לתאימות לאחור."""
    _, a, b = detect_event(text)
    return a, b


def route_line(kind: Optional[str], origin: Optional[str], target: Optional[str]) -> Tuple[str, str]:
    """שורת מסלול בעברית ובאנגלית, או מחרוזות ריקות."""
    if not kind or not origin:
        return "", ""
    fo, ho, eo, _ = PLACES[origin]
    if kind == "tension":
        ft, ht, et, _ = PLACES[target]
        return (f"⚔️ הסלמה: {fo} {ho}  ·  {ft} {ht}", f"⚔️ Escalation: {fo} {eo}  ·  {ft} {et}")
    if kind == "strike":
        he, en = f"🎯 תוקף לפי הדיווח: {fo} {ho}", f"🎯 Reported attacker: {fo} {eo}"
    else:
        he, en = f"📍 מקור לפי הדיווח: {fo} {ho}", f"📍 Reported origin: {fo} {eo}"
    if target:
        ft, ht, et, _ = PLACES[target]
        he += f"  ←  יעד: {ft} {ht}"
        en += f"  →  target: {ft} {et}"
    return he, en



# --------------------------------------------------------------------------- #
# ערוצי ברירת מחדל (נמצאו בחיפוש — מומלץ לבדוק שהם פעילים; אפשר להחליף ב-NEWS_TG_CHANNELS)
# --------------------------------------------------------------------------- #

# (ערוץ, תיאור, מהימן?) — "מהימן" = מספיק ערוץ אחד כדי לפרסם (לא צריך אימות מערוץ נוסף)
DEFAULT_CHANNELS = [
    # --- ישראל / המזרח התיכון (עברית/אנגלית) ---
    ("abualiexpress", "אבו עלי אקספרס — הזירה הערבית בעברית", True),
    ("manniefabian", "עמנואל פביאן (Times of Israel) — שיגורים לפני האזעקות", True),
    ("ILRedAlertNews", "ILRedAlert News — שיגורים, פיצוצים, התרעות מוקדמות", False),
    ("ramreports", "מבזקי רעם — מבזקים בזמן אמת", False),
    ("amitsegal", "עמית סגל — חדשות ופוליטיקה", False),
    ("OSINTdefender", "OSINTdefender — OSINT עולמי", False),
    ("osint613", "OSINT613 — המזרח התיכון", False),
    # --- ערבית ---
    ("almayadeen", "الميادين — חדשות עאג'ל (לבנון/תימן)", False),
    ("ajanews", "الجزيرة — מבזקי אל-ג'זירה", False),
    ("alyemenchannel", "قناة اليمن الفضائية — תימן", False),
    ("Alyemennet", "اليمن نت — תימן, לבנון, איראן", False),
    ("newsyemn", "أخبار اليمن العاجلة — תימן/לבנון/עזה/איראן", False),
    ("alarabiya", "العربية — מבזקים", False),
    ("AlHadath", "الحدث — מבזקים", False),
    ("asharqnews", "الشرق — חדשות", False),
    ("arabi21news", "عربي21 — חדשות", False),
    ("france24_ar", "فرانس 24 — ערבית", False),
    ("MTVLebanonNews", "MTV Lebanon — לבנון", False),
    ("alakhbar_news", "الأخبار — לבנון", False),
    ("qudsn", "شبكة قدس — עזה והגדה", False),
    # --- איראן (פרסית/אנגלית) — כולל כלי תקשורת ממשלתיים ---
    ("iranintltv", "איראן אינטרנשיונל — אופוזיציה, פרסית", False),
    ("iranintl_en", "Iran International English", False),
    ("presstv", "PressTV — שופר המשטר, אנגלית", False),
    ("FarsNewsInt", "פארס — סוכנות ממשלתית (משמרות המהפכה)", False),
    ("farsna", "פארס — פרסית", False),
    ("irna_1313", "אירנ\"א — סוכנות הידיעות הרשמית", False),
    ("mehrnews", "מהר — סוכנות ממשלתית", False),
    ("iribnews", "IRIB — השידור הממלכתי", False),
    # --- OSINT עולמי ---
    ("clashreport", "Clash Report — מבזקי עימותים", False),
    ("warmonitors", "War Monitors — מבזקים", False),
    # --- אוקראינה ---
    ("kpszsu", "חיל האוויר של אוקראינה — רשמי", True),
    ("war_monitor", "War Monitor — ניטור טילים ורחפנים בזמן אמת", True),
    ("monitoring_kyiv", "ניטור קייב", False),
    ("truexanewsua", "Труха Україна — מבזקים", False),
    ("UkraineNow", "Ukraine NOW — ערוץ חדשות", False),
    ("suspilnenews", "Суспільне — השידור הציבורי האוקראיני", False),
    ("uniannet", "УНИАН — סוכנות ידיעות", False),
    ("noel_reports", "NOELREPORTS — עדכוני המלחמה", False),
    # --- רוסיה ---
    ("tass_agency", "ТАСС — סוכנות הידיעות הרשמית", False),
    ("rian_ru", "РИА Новости — סוכנות ידיעות רשמית", False),
    ("bbbreaking", "Раньше всех — מבזקים", False),
    ("milinfolive", "Военный осведомитель — בלוגר צבאי", False),
    ("astrapress", "ASTRA — עיתונות עצמאית", False),
    ("meduzalive", "Медуза — עיתונות עצמאית", False),
]

# ערוצים שמדווחים כמעט תמיד על אותו כיוון — משמש כשהטקסט לא מציין מקור (או מציין רק אזור בתוך המדינה)
CHANNEL_HINTS = {
    c: ("launch", "RU", "UA")
    for c in ("kpszsu", "war_monitor", "monitoring_kyiv", "truexanewsua")
}

# קיצורים שהמתרגם לא מכיר — מחליפים לפני התרגום
PRETRANSLATE = [
    (re.compile(r"\bБпЛА\b|\bБПЛА\b", re.I), "дронів"),
    (re.compile(r"\bКР\b"), "крилаті ракети"),
]


def apply_hint(channel: str, kind, origin, target):
    """מתקן מסלול לפי ערוץ המקור (למשל: ערוצי ניטור אוקראיניים → רוסיה ← אוקראינה)."""
    hint = CHANNEL_HINTS.get((channel or "").lower()) or CHANNEL_HINTS.get(channel or "")
    if hint and (origin is None or origin == hint[2]):
        return hint
    return kind, origin, target


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

"""
מפות — "מאיפה לאיפה": אזורי התרעה בישראל + חץ מכיוון השיגור.

- קואורדינטות וזמני התגוננות ליישובים: cities.json של צופר (נשמר ב-data/ ומתרענן פעם בשבוע)
- רקע מפה: אריחי Esri (Dark Gray Canvas) בלי שמות; שמות המדינות/ערים מצוירים בעברית עם Pillow
- כיוון השיגור: מדיווח שיגור אחרון (אם היה ב-20 הדקות האחרונות) או הערכה גאוגרפית לפי מיקום ההתרעות
"""
from __future__ import annotations

import io
import json
import logging
import math
import os
import time
from typing import Dict, Iterable, List, Optional, Tuple

import requests

logger = logging.getLogger(__name__)

CITIES_URL = "https://www.tzevaadom.co.il/static/cities.json"
CITIES_CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "tzofar_cities.json")
TILE_URL = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}"
_UA = "Mozilla/5.0 (compatible; EmergencyNewsBot/1.0)"
TILE = 256

# נקודת ייחוס לכל מקור שיגור (מרכז אזור השיגור הנפוץ)
ORIGIN_POINTS: Dict[str, Tuple[float, float]] = {
    "IR": (33.5, 49.5), "YE": (15.4, 44.2), "LB": (33.5, 35.72), "GZ": (31.45, 34.36), "IQ": (33.3, 44.4),
    "SY": (33.5, 36.3), "IL": (31.8, 34.9), "JO": (31.95, 35.9), "EG": (30.05, 31.25), "SA": (24.7, 46.7),
    "AE": (24.45, 54.4), "QA": (25.3, 51.5), "TR": (39.9, 32.85), "US": (25.6, 51.2), "RU": (51.3, 37.0),
    "UA": (50.45, 30.5), "BY": (53.9, 27.55), "PL": (52.2, 21.0), "KP": (39.0, 125.75), "KR": (37.55, 126.98),
    "JP": (35.68, 139.7), "CN": (39.9, 116.4), "TW": (25.03, 121.56), "IN": (28.6, 77.2), "PK": (33.7, 73.05),
    "SD": (15.6, 32.5),
}

_cities: Dict[str, dict] = {}

# שמות בעברית שמצוירים על המפה (במקום שכבת השמות האנגלית)
# (שם, lat, lng, סוג): country / sea / city
HE_LABELS = [
    ("ישראל", 30.9, 34.85, "country"), ("לבנון", 34.0, 35.85, "country"), ("סוריה", 35.0, 38.5, "country"),
    ("ירדן", 30.9, 36.8, "country"), ("מצרים", 26.8, 30.8, "country"), ("עיראק", 33.0, 43.5, "country"),
    ("איראן", 32.5, 54.0, "country"), ("ערב הסעודית", 24.0, 45.0, "country"), ("תימן", 15.8, 47.5, "country"),
    ("טורקיה", 39.0, 35.0, "country"), ("קפריסין", 35.05, 33.2, "country"), ("כווית", 29.3, 47.6, "country"),
    ("קטאר", 25.3, 51.2, "country"), ("איחוד האמירויות", 23.6, 54.3, "country"), ("עומאן", 21.0, 57.0, "country"),
    ("סודן", 15.5, 30.0, "country"), ("לוב", 27.0, 17.0, "country"), ("רוסיה", 54.5, 40.0, "country"),
    ("אוקראינה", 49.0, 31.5, "country"), ("בלארוס", 53.6, 28.0, "country"), ("פולין", 52.0, 19.5, "country"),
    ("רומניה", 45.9, 24.9, "country"), ("מולדובה", 47.2, 28.5, "country"), ("גאורגיה", 42.2, 43.5, "country"),
    ("הים התיכון", 34.0, 30.0, "sea"), ("ים סוף", 20.5, 38.8, "sea"), ("המפרץ הפרסי", 27.0, 51.0, "sea"),
    ("הים השחור", 43.3, 34.5, "sea"), ("ים כנרת", 32.82, 35.59, "lake"), ("ים המלח", 31.5, 35.5, "lake"),
    ("תל אביב", 32.08, 34.78, "city"), ("ירושלים", 31.77, 35.21, "city"), ("חיפה", 32.79, 34.99, "city"),
    ("באר שבע", 31.25, 34.79, "city"), ("אילת", 29.56, 34.95, "city"), ("עזה", 31.5, 34.45, "city"),
    ("ביירות", 33.89, 35.5, "city"), ("דמשק", 33.51, 36.29, "city"), ("עמאן", 31.95, 35.93, "city"),
    ("קהיר", 30.04, 31.24, "city"), ("בגדד", 33.31, 44.36, "city"), ("טהרן", 35.69, 51.39, "city"),
    ("איספהאן", 32.65, 51.67, "city"), ("צנעא", 15.37, 44.19, "city"), ("ריאד", 24.71, 46.68, "city"),
    ("קייב", 50.45, 30.52, "city"), ("מוסקבה", 55.75, 37.62, "city"), ("אודסה", 46.48, 30.72, "city"),
    ("חרקוב", 49.99, 36.23, "city"), ("צור", 33.27, 35.2, "city"), ("צידון", 33.56, 35.37, "city"),
    ("נהריה", 33.0, 35.1, "city"), ("קריית שמונה", 33.21, 35.57, "city"), ("טבריה", 32.79, 35.53, "city"),
    ("אשקלון", 31.67, 34.57, "city"), ("אשדוד", 31.8, 34.65, "city"), ("נתניה", 32.33, 34.86, "city"),
]
_FONT_PATHS = [
    "/System/Library/Fonts/ArialHB.ttc", "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial Unicode.ttf", "/System/Library/Fonts/SFHebrew.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def _font(size: int):
    from PIL import ImageFont
    for path in _FONT_PATHS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return None


def _draw_he(draw, xy, text: str, font, fill, anchor="mm"):
    """טקסט עברי מימין לשמאל (עם raqm אם יש; אחרת הופכים את סדר האותיות)."""
    from PIL import features
    kw = {"font": font, "fill": fill, "anchor": anchor, "stroke_width": 3, "stroke_fill": (10, 12, 16)}
    if features.check_feature("raqm"):
        draw.text(xy, text, direction="rtl", **kw)
    else:
        draw.text(xy, text[::-1], **kw)


# --------------------------------------------------------------------------- #
# יישובים
# --------------------------------------------------------------------------- #

def load_cities(session: Optional[requests.Session] = None) -> Dict[str, dict]:
    global _cities
    if _cities:
        return _cities
    fresh = os.path.exists(CITIES_CACHE) and time.time() - os.path.getmtime(CITIES_CACHE) < 7 * 86400
    if not fresh:
        try:
            r = (session or requests).get(CITIES_URL, timeout=20, headers={"User-Agent": _UA})
            r.raise_for_status()
            os.makedirs(os.path.dirname(CITIES_CACHE), exist_ok=True)
            with open(CITIES_CACHE, "w", encoding="utf-8") as f:
                f.write(r.text)
        except (requests.RequestException, OSError) as e:
            logger.warning("cities.json download failed: %s", e)
    try:
        with open(CITIES_CACHE, encoding="utf-8") as f:
            _cities = json.load(f).get("cities", {})
    except (OSError, ValueError):
        _cities = {}
    return _cities


def city_points(names: Iterable[str], session=None) -> List[Tuple[float, float, int]]:
    """(lat, lng, countdown) ליישובים שנמצאו."""
    cities = load_cities(session)
    out = []
    for n in names:
        c = cities.get(n) or cities.get(n.strip())
        if c and c.get("lat") and c.get("lng"):
            out.append((float(c["lat"]), float(c["lng"]), int(c.get("countdown") or 0)))
    return out


def city_names_found(names: Iterable[str], session=None) -> List[str]:
    """שמות היישובים (בעברית) שנמצאו להם קואורדינטות — באותו סדר כמו city_points."""
    cities = load_cities(session)
    return [n for n in names if (cities.get(n) or cities.get(n.strip()) or {}).get("lat")]


def estimate_origin(points: List[Tuple[float, float, int]]) -> Optional[str]:
    """הערכה גאוגרפית (גסה!) של מקור הירי לפי מיקום ההתרעות בישראל."""
    if not points:
        return None
    lats = [p[0] for p in points]
    lngs = [p[1] for p in points]
    lat_c, lng_c = sum(lats) / len(lats), sum(lngs) / len(lngs)
    spread = max(lats) - min(lats)
    if spread > 1.2 or (len(points) > 60 and spread > 0.6):
        return "IR"  # התרעות בכל הארץ — בדרך כלל טילים בליסטיים מאיראן
    if lat_c < 30.2:
        return "YE"  # אילת והערבה — לרוב מתימן
    if lat_c > 32.75:
        return "LB"  # הצפון — לרוב מלבנון
    if lat_c < 31.75 and lng_c < 34.75:
        return "GZ"  # עוטף עזה והדרום
    return None


# --------------------------------------------------------------------------- #
# ציור מפה
# --------------------------------------------------------------------------- #

def _px(lat: float, lng: float, z: int) -> Tuple[float, float]:
    n = TILE * 2 ** z
    x = (lng + 180.0) / 360.0 * n
    s = math.sin(math.radians(max(min(lat, 85), -85)))
    y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n
    return x, y


def _fit_zoom(pts: List[Tuple[float, float]], w: int, h: int, max_z: int) -> int:
    for z in range(max_z, 2, -1):
        xs, ys = zip(*[_px(a, b, z) for a, b in pts])
        if max(xs) - min(xs) <= w * 0.7 and max(ys) - min(ys) <= h * 0.7:
            return z
    return 3


def _fetch_tile(session, z, x, y, url_tpl: str = TILE_URL):
    from PIL import Image
    n = 2 ** z
    url = url_tpl.format(z=z, x=x % n, y=y)
    if not 0 <= y < n:
        return None
    try:
        r = session.get(url, timeout=10, headers={"User-Agent": _UA})
        r.raise_for_status()
        return Image.open(io.BytesIO(r.content)).convert("RGBA")
    except Exception:  # noqa: BLE001 — רקע הוא לא קריטי
        return None


def render_map(alert_pts: List[Tuple[float, float, int]], origin: Optional[str] = None,
               target: Optional[str] = None, session: Optional[requests.Session] = None,
               size: Tuple[int, int] = (1000, 720), alert_names: Optional[List[str]] = None) -> Optional[bytes]:
    """
    מצייר מפה: נקודות התרעה (אדום), ומקור שיגור (כתום) עם חץ קשתי ליעד.
    מחזיר PNG או None (אם אין Pillow או אין מה לצייר).
    """
    try:
        from PIL import Image, ImageDraw, ImageFilter
    except ImportError:
        return None
    session = session or requests.Session()
    W, H = size
    tgt: Optional[Tuple[float, float]] = None
    if alert_pts:
        tgt = (sum(p[0] for p in alert_pts) / len(alert_pts), sum(p[1] for p in alert_pts) / len(alert_pts))
    elif target in ORIGIN_POINTS:
        tgt = ORIGIN_POINTS[target]
    src = ORIGIN_POINTS.get(origin) if origin else None
    if not tgt and not src:
        return None
    pts = [(p[0], p[1]) for p in alert_pts] or ([tgt] if tgt else [])
    if src:
        pts.append(src)
    # מרווח מינימלי: לפחות ~1.2 מעלות, כדי לראות את האזור ולא רק נקודה
    la, lo = [p[0] for p in pts], [p[1] for p in pts]
    clat, clng = (max(la) + min(la)) / 2, (max(lo) + min(lo)) / 2
    half = 0.3
    pts += [(clat + half, clng + half), (clat - half, clng - half)]
    z = _fit_zoom(pts, W, H, max_z=10)
    xs, ys = zip(*[_px(a, b, z) for a, b in pts])
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    left, top = cx - W / 2, cy - H / 2

    img = Image.new("RGB", (W, H), (14, 18, 26))
    for tx in range(int(left // TILE), int((left + W) // TILE) + 1):
        for ty in range(int(top // TILE), int((top + H) // TILE) + 1):
            pos = (int(tx * TILE - left), int(ty * TILE - top))
            t = _fetch_tile(session, z, tx, ty)
            if t is not None:
                img.paste(t.convert("RGB"), pos)

    def xy(lat, lng):
        x, y = _px(lat, lng, z)
        return x - left, y - top

    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    r = 7 if len(alert_pts) < 80 else 5

    if src and tgt:
        (x0, y0), (x1, y1) = xy(*src), xy(*tgt)
        dx, dy = x1 - x0, y1 - y0
        dist = math.hypot(dx, dy) or 1
        # קשת: נקודת בקרה מוסטת הצידה
        mx, my = (x0 + x1) / 2 - dy * 0.25, (y0 + y1) / 2 + dx * 0.25
        curve = [((1 - t) ** 2 * x0 + 2 * (1 - t) * t * mx + t * t * x1,
                  (1 - t) ** 2 * y0 + 2 * (1 - t) * t * my + t * t * y1) for t in [i / 60 for i in range(61)]]
        # עוצרים ~26 פיקסלים לפני היעד, כדי שראש החץ יצביע על אזור ההתרעה
        end = len(curve)
        while end > 2 and math.hypot(curve[end - 1][0] - x1, curve[end - 1][1] - y1) < 26:
            end -= 1
        for i in range(0, end - 1, 2):  # קו מקווקו
            d.line([curve[i], curve[i + 1]], fill=(255, 159, 10, 235), width=6)
        g.line(curve[:end], fill=(255, 120, 0, 140), width=18)
        # ראש חץ
        ax, ay = curve[end - 1]
        bx, by = curve[max(0, end - 4)]
        ang = math.atan2(ay - by, ax - bx)
        head = [(ax + 22 * math.cos(ang), ay + 22 * math.sin(ang)),
                (ax + 16 * math.cos(ang + 2.5), ay + 16 * math.sin(ang + 2.5)),
                (ax + 16 * math.cos(ang - 2.5), ay + 16 * math.sin(ang - 2.5))]
        d.polygon(head, fill=(255, 159, 10, 255))
        g.ellipse([x0 - 22, y0 - 22, x0 + 22, y0 + 22], fill=(255, 120, 0, 200))
        d.ellipse([x0 - 11, y0 - 11, x0 + 11, y0 + 11], fill=(255, 159, 10, 255), outline=(255, 255, 255, 255), width=3)

    for lat, lng, _ in alert_pts:
        x, y = xy(lat, lng)
        g.ellipse([x - r * 3, y - r * 3, x + r * 3, y + r * 3], fill=(255, 40, 40, 150))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 59, 48, 255), outline=(255, 255, 255, 230), width=2)
    if not alert_pts and tgt and src:
        x, y = xy(*tgt)
        g.ellipse([x - 30, y - 30, x + 30, y + 30], fill=(255, 40, 40, 160))
        d.ellipse([x - 12, y - 12, x + 12, y + 12], fill=(255, 59, 48, 255), outline=(255, 255, 255, 255), width=3)

    img = Image.alpha_composite(img.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(10)))
    img = Image.alpha_composite(img, over)
    # שמות בעברית
    td = ImageDraw.Draw(img)
    f_country, f_sea, f_city, f_alert = _font(26), _font(20), _font(19), _font(18)
    if f_country:
        taken: List[Tuple[float, float, float, float]] = []

        def put(text, x, y, font, fill, dy=0):
            if not (20 < x < W - 20 and 20 < y + dy < H - 30):
                return
            bw = font.getlength(text) / 2 + 6
            box = (x - bw, y + dy - 14, x + bw, y + dy + 14)
            if any(not (box[2] < b[0] or box[0] > b[2] or box[3] < b[1] or box[1] > b[3]) for b in taken):
                return  # לא מעמיסים שמות אחד על השני
            taken.append(box)
            _draw_he(td, (x, y + dy), text, font, fill)

        # יישובי ההתרעה (עד 6) — הכי חשובים, נכתבים ראשונים
        if 0 < len(alert_pts) <= 6 and z >= 8:
            for name, lat, lng in [(n, p[0], p[1]) for n, p in zip(alert_names or [], alert_pts)]:
                x, y = xy(lat, lng)
                put(name, x, y, f_alert, (255, 225, 225, 255), dy=-20)
        for name, lat, lng, kind in HE_LABELS:
            if (kind == "city" and z < 6) or (kind == "lake" and z < 8):
                continue
            if kind == "country" and z > 9:
                continue
            x, y = xy(lat, lng)
            if kind == "country":
                put(name, x, y, f_country, (205, 210, 220, 255))
            elif kind in ("sea", "lake"):
                put(name, x, y, f_sea, (120, 160, 205, 255))
            else:
                td.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(200, 200, 210, 255))
                put(name, x, y, f_city, (235, 235, 240, 255), dy=-16)
    td.text((W - 60, H - 16), "Esri ©", fill=(150, 155, 165, 255))
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "PNG", optimize=True)
    return buf.getvalue()

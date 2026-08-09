from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BASE_DIR = Path(__file__).resolve().parent
OUT_DIR = BASE_DIR / "overlays"
OUT_DIR.mkdir(exist_ok=True)

WIDTH, HEIGHT = 1080, 1920
FONT_PATH = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
WHITE = (255, 255, 255, 255)
YELLOW = (255, 229, 0, 255)
PINK = (255, 47, 167, 255)
BLACK = (10, 6, 16, 235)

CAPTIONS = [
    ("GTA 6 PHYSICAL EDITION…", "ФИЗИЧЕСКАЯ ВЕРСИЯ GTA 6…", WHITE, 68),
    ("HAS NO DISC!\nYES, REALLY.", "БЕЗ ДИСКА! ДА, СЕРЬЁЗНО.", YELLOW, 72),
    ("THE BOX ONLY HAS A\nDOWNLOAD CODE", "В КОРОБКЕ — ТОЛЬКО КОД", WHITE, 70),
    ("PRELOAD: NOVEMBER 12\n2026", "ПРЕДЗАГРУЗКА: 12 НОЯБРЯ 2026", WHITE, 70),
    ("LAUNCH: NOVEMBER 19\n2026", "РЕЛИЗ: 19 НОЯБРЯ 2026", YELLOW, 76),
    ("IS THAT STILL A\nPHYSICAL EDITION?", "ЭТО ЕЩЁ ФИЗИЧЕСКАЯ ВЕРСИЯ?", WHITE, 70),
    ("COMMENT BELOW!", "ПИШИ В КОММЕНТАРИЯХ!", WHITE, 70),
]


def centered_multiline(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    stroke_width: int,
    stroke_fill: tuple[int, int, int, int],
    spacing: int = 10,
) -> tuple[int, int, int, int]:
    box = draw.multiline_textbbox(
        (0, 0),
        text,
        font=font,
        align="center",
        spacing=spacing,
        stroke_width=stroke_width,
    )
    text_w = box[2] - box[0]
    text_h = box[3] - box[1]
    x = xy[0] - text_w // 2
    y = xy[1] - text_h // 2
    draw.multiline_text(
        (x, y),
        text,
        font=font,
        fill=fill,
        align="center",
        spacing=spacing,
        stroke_width=stroke_width,
        stroke_fill=stroke_fill,
    )
    return (x, y, x + text_w, y + text_h)


for index, (caption, russian_caption, color, font_size) in enumerate(CAPTIONS, start=1):
    image = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")

    draw.rounded_rectangle((55, 70, 1025, 195), radius=24, fill=(0, 0, 0, 150))
    draw.rounded_rectangle((55, 70, 70, 195), radius=7, fill=PINK)
    header_font = ImageFont.truetype(FONT_PATH, 54)
    centered_multiline(
        draw,
        (540, 132),
        "GTA 6: NO DISC IN THE BOX?!",
        header_font,
        WHITE,
        3,
        (0, 0, 0, 230),
        spacing=0,
    )

    caption_font = ImageFont.truetype(FONT_PATH, font_size)
    measure = draw.multiline_textbbox(
        (0, 0),
        caption,
        font=caption_font,
        align="center",
        spacing=10,
        stroke_width=7,
    )
    caption_w = measure[2] - measure[0]
    caption_h = measure[3] - measure[1]
    center_y = 1385 if index != 7 else 1415
    left = max(45, 540 - caption_w // 2 - 34)
    right = min(1035, 540 + caption_w // 2 + 34)
    top = center_y - caption_h // 2 - 28
    bottom = center_y + caption_h // 2 + 28
    border_color = (225, 0, 145, 245) if index == 7 else (0, 0, 0, 0)
    if index == 7:
        draw.rounded_rectangle(
            (left - 6, top - 6, right + 6, bottom + 6),
            radius=26,
            fill=border_color,
        )
    draw.rounded_rectangle((left, top, right, bottom), radius=22, fill=BLACK)
    centered_multiline(
        draw,
        (540, center_y),
        caption,
        caption_font,
        color,
        7,
        (0, 0, 0, 255),
    )

    russian_font = ImageFont.truetype(FONT_PATH, 42)
    russian_box = draw.textbbox(
        (0, 0),
        russian_caption,
        font=russian_font,
        stroke_width=4,
    )
    russian_w = russian_box[2] - russian_box[0]
    russian_h = russian_box[3] - russian_box[1]
    russian_y = 1595
    russian_left = max(65, 540 - russian_w // 2 - 26)
    russian_right = min(1015, 540 + russian_w // 2 + 26)
    draw.rounded_rectangle(
        (
            russian_left,
            russian_y - russian_h // 2 - 18,
            russian_right,
            russian_y + russian_h // 2 + 18,
        ),
        radius=18,
        fill=(4, 6, 18, 215),
        outline=(37, 218, 255, 145),
        width=2,
    )
    centered_multiline(
        draw,
        (540, russian_y),
        russian_caption,
        russian_font,
        (220, 235, 255, 255),
        4,
        (0, 0, 0, 255),
        spacing=0,
    )

    image.save(OUT_DIR / f"overlay-{index:02d}.png")

print(f"Rendered {len(CAPTIONS)} overlays to {OUT_DIR}")

#!/usr/bin/env python3
"""Build typography, branding and thumbnail assets for Habibi Groove."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
FONT = "/System/Library/Fonts/Avenir Next Condensed.ttc"
WHITE = (242, 246, 255, 255)
BLUE = (65, 130, 255, 255)
VIOLET = (128, 74, 255, 255)
GOLD = (224, 174, 91, 255)


def font(size: int, index: int = 8) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size=size, index=index)


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    source = image.convert("RGB")
    scale = max(size[0] / source.width, size[1] / source.height)
    resized = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def letter_spaced_width(
    draw: ImageDraw.ImageDraw,
    text: str,
    face: ImageFont.FreeTypeFont,
    spacing: int,
) -> int:
    widths = [draw.textlength(char, font=face) for char in text]
    return round(sum(widths) + max(0, len(text) - 1) * spacing)


def draw_letter_spaced(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    face: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    spacing: int,
    anchor: str = "mm",
) -> tuple[int, int, int, int]:
    x, y = xy
    width = letter_spaced_width(draw, text, face, spacing)
    if anchor == "mm":
        cursor = x - width / 2
    elif anchor == "lm":
        cursor = x
    else:
        raise ValueError(f"Unsupported anchor: {anchor}")
    top = y - face.size / 2
    for char in text:
        draw.text((round(cursor), y), char, font=face, fill=fill, anchor="lm")
        cursor += draw.textlength(char, font=face) + spacing
    return (round(x - width / 2), round(top), round(x + width / 2), round(top + face.size))


def glow_text(
    canvas: Image.Image,
    xy: tuple[int, int],
    text: str,
    face: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    spacing: int,
    glow: tuple[int, int, int, int] = BLUE,
    blur: int = 20,
    anchor: str = "mm",
) -> None:
    glow_layer = Image.new("RGBA", canvas.size)
    glow_draw = ImageDraw.Draw(glow_layer)
    draw_letter_spaced(glow_draw, xy, text, face, glow, spacing, anchor)
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(glow_layer)
    draw = ImageDraw.Draw(canvas)
    draw_letter_spaced(draw, xy, text, face, fill, spacing, anchor)


def add_vignette(image: Image.Image, strength: float = 0.62) -> Image.Image:
    width, height = image.size
    vignette = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(vignette)
    inset_x, inset_y = round(width * 0.10), round(height * 0.08)
    draw.ellipse(
        (inset_x, inset_y, width - inset_x, height - inset_y),
        fill=255,
    )
    vignette = vignette.filter(ImageFilter.GaussianBlur(round(min(width, height) * 0.22)))
    dark = Image.new("RGB", image.size, "black")
    mask = ImageEnhance.Brightness(ImageChops.invert(vignette)).enhance(strength)
    return Image.composite(dark, image, ImageChops.invert(mask))


def make_banner() -> None:
    background = cover(Image.open(ROOT / "scene-01-portal.png"), (2560, 1440))
    background = ImageEnhance.Brightness(background).enhance(0.66)
    background = ImageEnhance.Contrast(background).enhance(1.12)
    canvas = add_vignette(background).convert("RGBA")

    safe = Image.new("RGBA", canvas.size)
    safe_draw = ImageDraw.Draw(safe)
    safe_draw.rounded_rectangle(
        (505, 525, 2055, 915),
        radius=42,
        fill=(2, 6, 20, 88),
        outline=(75, 123, 255, 70),
        width=2,
    )
    safe = safe.filter(ImageFilter.GaussianBlur(2))
    canvas.alpha_composite(safe)

    glow_text(
        canvas,
        (1280, 660),
        "SERGIO",
        font(215, 8),
        WHITE,
        spacing=28,
        blur=26,
    )
    draw = ImageDraw.Draw(canvas)
    draw.line((840, 803, 1720, 803), fill=(77, 129, 255, 155), width=3)
    draw_letter_spaced(
        draw,
        (1280, 850),
        "AFRO-TECHNO  •  AFRO HOUSE  •  ORIGINAL MUSIC",
        font(42, 5),
        (224, 231, 255, 238),
        spacing=5,
    )
    canvas.convert("RGB").save(
        ROOT / "channel-banner-2560x1440.jpg", quality=94, subsampling=0
    )


def make_profile() -> None:
    size = 1024
    canvas = Image.new("RGBA", (size, size), (2, 5, 16, 255))
    pixels = canvas.load()
    for y in range(size):
        for x in range(size):
            dx, dy = x - size / 2, y - size / 2
            radius = min(1.0, (dx * dx + dy * dy) ** 0.5 / (size * 0.67))
            blue = round(35 * (1 - radius))
            violet = round(24 * (1 - radius))
            pixels[x, y] = (2 + violet // 4, 5 + blue // 5, 16 + blue, 255)

    draw = ImageDraw.Draw(canvas)
    for radius, color, width in [
        (350, (52, 112, 255, 70), 4),
        (300, (132, 75, 255, 105), 7),
        (250, (225, 174, 91, 150), 3),
    ]:
        box = (
            size // 2 - radius,
            size // 2 - radius,
            size // 2 + radius,
            size // 2 + radius,
        )
        draw.ellipse(box, outline=color, width=width)

    glow_text(
        canvas,
        (size // 2, size // 2 - 5),
        "S",
        font(520, 8),
        WHITE,
        spacing=0,
        glow=(54, 115, 255, 220),
        blur=34,
    )
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((492, 816, 532, 856), fill=GOLD)
    canvas.save(ROOT / "channel-profile-1024.png")


def make_thumbnail() -> None:
    background = cover(Image.open(ROOT / "scene-03-drop.png"), (1280, 720))
    background = ImageEnhance.Contrast(background).enhance(1.12).convert("RGBA")

    gradient = Image.new("RGBA", background.size)
    gradient_pixels = gradient.load()
    for x in range(background.width):
        alpha = round(225 * max(0.0, 1.0 - x / (background.width * 0.72)))
        for y in range(background.height):
            vertical = 1.0 - abs(y - background.height / 2) / (background.height / 2)
            gradient_pixels[x, y] = (1, 4, 17, round(alpha * (0.82 + 0.18 * vertical)))
    background.alpha_composite(gradient)

    draw = ImageDraw.Draw(background)
    draw_letter_spaced(
        draw,
        (88, 128),
        "SERGIO",
        font(74, 8),
        GOLD,
        spacing=11,
        anchor="lm",
    )
    glow_text(
        background,
        (87, 295),
        "HABIBI",
        font(146, 8),
        WHITE,
        spacing=4,
        glow=BLUE,
        blur=18,
        anchor="lm",
    )
    glow_text(
        background,
        (87, 432),
        "GROOVE",
        font(146, 8),
        WHITE,
        spacing=4,
        glow=VIOLET,
        blur=18,
        anchor="lm",
    )
    draw.rounded_rectangle((88, 562, 480, 622), radius=30, fill=(17, 30, 75, 220))
    draw_letter_spaced(
        draw,
        (284, 594),
        "OFFICIAL VISUALIZER",
        font(30, 5),
        (226, 234, 255, 255),
        spacing=3,
    )
    background.convert("RGB").save(
        ROOT / "youtube-thumbnail-1280x720.jpg", quality=95, subsampling=0
    )


def make_video_overlays() -> None:
    title = Image.new("RGBA", (1920, 1080))
    glow_text(
        title,
        (960, 395),
        "SERGIO",
        font(168, 8),
        WHITE,
        spacing=28,
        blur=26,
    )
    title_draw = ImageDraw.Draw(title)
    title_draw.line((665, 526, 1255, 526), fill=(71, 128, 255, 190), width=3)
    draw_letter_spaced(
        title_draw,
        (960, 602),
        "HABIBI GROOVE",
        font(86, 8),
        (236, 241, 255, 255),
        spacing=9,
    )
    draw_letter_spaced(
        title_draw,
        (960, 688),
        "OFFICIAL VISUALIZER",
        font(34, 5),
        GOLD,
        spacing=7,
    )
    title.save(ROOT / "title-card.png")

    outro = Image.new("RGBA", (1920, 1080))
    glow_text(
        outro,
        (960, 462),
        "SERGIO",
        font(144, 8),
        WHITE,
        spacing=24,
        blur=24,
    )
    outro_draw = ImageDraw.Draw(outro)
    draw_letter_spaced(
        outro_draw,
        (960, 595),
        "RHYTHM WITHOUT BORDERS",
        font(43, 5),
        (224, 232, 255, 255),
        spacing=7,
    )
    draw_letter_spaced(
        outro_draw,
        (960, 684),
        "SUBSCRIBE FOR NEW MUSIC",
        font(29, 5),
        GOLD,
        spacing=6,
    )
    outro.save(ROOT / "outro-card.png")

    bug = Image.new("RGBA", (420, 120))
    bug_draw = ImageDraw.Draw(bug)
    draw_letter_spaced(
        bug_draw,
        (28, 60),
        "SERGIO",
        font(42, 8),
        (240, 244, 255, 188),
        spacing=6,
        anchor="lm",
    )
    bug_draw.line((26, 94, 280, 94), fill=(70, 126, 255, 145), width=2)
    bug.save(ROOT / "corner-bug.png")


def make_contact_sheet() -> None:
    items = [
        ("SCENE 01", ROOT / "scene-01-portal.png"),
        ("SCENE 02", ROOT / "scene-02-corridor.png"),
        ("SCENE 03", ROOT / "scene-03-drop.png"),
        ("SCENE 04", ROOT / "scene-04-finale.png"),
        ("CHANNEL BANNER", ROOT / "channel-banner-2560x1440.jpg"),
        ("THUMBNAIL", ROOT / "youtube-thumbnail-1280x720.jpg"),
        ("PROFILE", ROOT / "channel-profile-1024.png"),
    ]
    cell_w, cell_h = 640, 410
    sheet = Image.new("RGB", (cell_w * 2, cell_h * 4), (6, 8, 18))
    draw = ImageDraw.Draw(sheet)
    for index, (label, path) in enumerate(items):
        column, row = index % 2, index // 2
        x, y = column * cell_w, row * cell_h
        preview = cover(Image.open(path), (600, 338))
        sheet.paste(preview, (x + 20, y + 48))
        draw.text(
            (x + 22, y + 17),
            label,
            font=font(22, 5),
            fill=(225, 232, 250),
        )
    sheet.save(ROOT / "visual-contact-sheet.jpg", quality=92)


def main() -> None:
    make_banner()
    make_profile()
    make_thumbnail()
    make_video_overlays()
    make_contact_sheet()
    print("Created branding, thumbnail and video overlay assets.")


if __name__ == "__main__":
    main()

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


BASE_DIR = Path(__file__).resolve().parent
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_w, target_h = size
    scale = max(target_w / image.width, target_h / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


banner = Image.open(BASE_DIR / "banner-background.png").convert("RGB")
banner = cover(banner, (2560, 1440))
banner = ImageEnhance.Contrast(banner).enhance(1.05)
banner = ImageEnhance.Color(banner).enhance(1.08)

overlay = Image.new("RGBA", banner.size, (0, 0, 0, 0))
draw = ImageDraw.Draw(overlay, "RGBA")

# YouTube's cross-device text-safe zone is centered in the 2560×1440 banner.
safe = (507, 508, 2053, 931)
draw.rounded_rectangle(safe, radius=52, fill=(3, 5, 19, 145), outline=(124, 54, 255, 115), width=3)
draw.rounded_rectangle((590, 575, 608, 854), radius=9, fill=(37, 218, 255, 255))
draw.rounded_rectangle((1952, 575, 1970, 854), radius=9, fill=(255, 46, 170, 255))

title = "GAMEPULSE"
tagline = "GAMING • NEWS • NO FLUFF"
title_font = ImageFont.truetype(FONT_BOLD, 158)
tag_font = ImageFont.truetype(FONT_BOLD, 56)

title_box = draw.textbbox((0, 0), title, font=title_font, stroke_width=2)
title_w = title_box[2] - title_box[0]
title_x = 1280 - title_w // 2
title_y = 585

glow = Image.new("RGBA", banner.size, (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow)
glow_draw.text((title_x - 5, title_y), title, font=title_font, fill=(35, 218, 255, 220))
glow_draw.text((title_x + 5, title_y), title, font=title_font, fill=(255, 46, 170, 220))
glow = glow.filter(ImageFilter.GaussianBlur(18))
overlay.alpha_composite(glow)

draw = ImageDraw.Draw(overlay, "RGBA")
draw.text(
    (title_x, title_y),
    title,
    font=title_font,
    fill=(255, 255, 255, 255),
    stroke_width=3,
    stroke_fill=(30, 12, 55, 255),
)

tag_box = draw.textbbox((0, 0), tagline, font=tag_font)
tag_w = tag_box[2] - tag_box[0]
tag_x = 1280 - tag_w // 2
tag_y = 795
draw.rounded_rectangle((tag_x - 34, tag_y - 14, tag_x + tag_w + 34, tag_y + 70), radius=24, fill=(0, 0, 0, 125))
draw.text((tag_x, tag_y), tagline, font=tag_font, fill=(213, 226, 255, 255))

final_banner = Image.alpha_composite(banner.convert("RGBA"), overlay).convert("RGB")
final_banner.save(BASE_DIR / "channel-banner-2560x1440.jpg", quality=94, optimize=True)

profile = Image.open(BASE_DIR / "profile-source.png").convert("RGB")
profile = cover(profile, (1024, 1024))
profile.save(BASE_DIR / "channel-profile-1024.png", optimize=True)

print("Rendered YouTube banner and profile image.")

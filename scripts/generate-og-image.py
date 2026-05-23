#!/usr/bin/env python3
"""
docs/assets/og-image.png üretir — GitHub repo OpenGraph önizleme görseli
(1280x640). Sosyal paylaşımda (Twitter/X, Slack, Discord, LinkedIn,
HackerNews preview) bu image görünür.

Layout:
  [ MASCOT ] | [ pixel-agent ]
             | [ Personal AI agent for macOS ]
             | [ Multi-LLM CLI · Subagents · iOS remote · MCP server ]
             | [ github.com/ErkutYavuzer/pixel-agent ]

Aynı palette + grid generate-app-icon.py ile bire bir aynı (Sources/PixelMascot
ile senkron). Font fallback chain: Helvetica-Bold → Helvetica → Arial.

Setup: GitHub repo Settings → General → Social preview → Upload an image.
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

# generate-app-icon.py ile aynı grid + palette (Sources/PixelMascot ile senkron)
IDLE_FRAME = [
    "............",
    "....XXXX....",
    "...HXXXXS...",
    "..HXXXXXXS..",
    "..XOXXXXOX..",
    "..XOXXXXOX..",
    "..XXX__XXX..",
    "..XSXXXXSX..",
    "...SXXXXS...",
    "....SXXS....",
    "............",
    "............",
]

PALETTE = {
    "X": (115, 76, 217),    # body         (0.45, 0.30, 0.85)
    "H": (153, 115, 242),   # bodyHighlight (0.60, 0.45, 0.95)
    "S": (76, 46, 166),     # bodyShadow   (0.30, 0.18, 0.65)
    "O": (255, 255, 255),   # eye
    "_": (0, 0, 0),         # mouth
}

BACKGROUND = (28, 20, 46)        # #1C142E — derin koyu mor (icon ile aynı)
TEXT_PRIMARY = (255, 255, 255)
TEXT_SECONDARY = (210, 195, 240)
TEXT_TERTIARY = (153, 130, 200)
ACCENT = (153, 115, 242)         # bodyHighlight — küçük decoratif vurgu

OG_WIDTH = 1280
OG_HEIGHT = 640


def render_mascot_at(img: Image.Image, *, center: tuple[int, int], mascot_size: int) -> None:
    """Mascot'u verilen merkez koordinatına çiz. mascot_size grid'in toplam pixel boyutu."""
    grid_size = 12
    cell = mascot_size // grid_size
    grid_pixels = cell * grid_size
    cx, cy = center
    offset_x = cx - grid_pixels // 2
    offset_y = cy - grid_pixels // 2
    draw = ImageDraw.Draw(img)
    for y, row in enumerate(IDLE_FRAME):
        for x, ch in enumerate(row):
            color = PALETTE.get(ch)
            if color is None:
                continue
            x0 = offset_x + x * cell
            y0 = offset_y + y * cell
            draw.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], fill=color)


def font_for(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    """macOS sistem font'larından en yakın eşleşmeyi yükle; başarısızsa PIL default'u."""
    if bold:
        candidates = [
            "/System/Library/Fonts/Helvetica.ttc",   # Helvetica-Bold collection içinde
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/Library/Fonts/Arial Bold.ttf",
        ]
    else:
        candidates = [
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/Library/Fonts/Arial.ttf",
        ]
    for path in candidates:
        try:
            # .ttc collection'da index=1 genelde bold; bold istiyorsak deneyelim
            if bold and path.endswith(".ttc"):
                try:
                    return ImageFont.truetype(path, size=size, index=1)
                except (OSError, IOError):
                    pass
            return ImageFont.truetype(path, size=size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default(size=size)


def render_og_image() -> Image.Image:
    img = Image.new("RGB", (OG_WIDTH, OG_HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(img)

    # Sağ yarı için ince accent çubuğu (mor) — visual hiyerarşi
    accent_x = 620
    draw.rectangle([accent_x, 180, accent_x + 4, 460], fill=ACCENT)

    # Mascot — sol yarıda merkezli, 420px (12x12 grid → 35px cell)
    render_mascot_at(img, center=(310, OG_HEIGHT // 2), mascot_size=420)

    # Sağ yarı text
    text_x = 670

    # Title
    title_font = font_for(78, bold=True)
    draw.text((text_x, 195), "pixel-agent", fill=TEXT_PRIMARY, font=title_font)

    # Subtitle (USP'nin ilk yarısı)
    subtitle_font = font_for(30, bold=False)
    draw.text((text_x, 295), "Personal AI agent for macOS", fill=TEXT_SECONDARY, font=subtitle_font)

    # Feature tags
    tag_font = font_for(22, bold=False)
    draw.text((text_x, 350), "Multi-LLM CLI  ·  Subagents  ·  iOS remote  ·  MCP server",
              fill=TEXT_TERTIARY, font=tag_font)

    # Repo URL
    url_font = font_for(20, bold=False)
    draw.text((text_x, 432), "github.com/ErkutYavuzer/pixel-agent",
              fill=TEXT_TERTIARY, font=url_font)

    return img


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent.parent
    out_path = repo_root / "docs/assets/og-image.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img = render_og_image()
    img.save(out_path, format="PNG", optimize=True)
    print(f"✓ {out_path} ({img.size[0]}x{img.size[1]}, {out_path.stat().st_size // 1024} KB)")
    print()
    print("Setup:")
    print("  GitHub repo → Settings → General → Social preview → Upload an image")
    print(f"  Upload: {out_path.relative_to(repo_root)}")

#!/usr/bin/env python3
"""
PixelMascot idle frame'inden iOS asset'leri üretir:
- `AppIcon-1024.png` (1024x1024, sRGB, no alpha — App Store)
- `LaunchIcon{,@2x,@3x}.png` (240/480/720, alpha kanalı ile)

ASCII grid + palette `Sources/PixelMascot/PixelMascot.swift` ile bire bir aynı.
"""
from PIL import Image, ImageDraw
import sys
from pathlib import Path

# PixelMascot.idleFrame — 12x12 ASCII grid
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

# MascotPalette.default (Swift Color → 0-255 RGB)
PALETTE = {
    "X": (115, 76, 217),    # body         (0.45, 0.30, 0.85)
    "H": (153, 115, 242),   # bodyHighlight (0.60, 0.45, 0.95)
    "S": (76, 46, 166),     # bodyShadow   (0.30, 0.18, 0.65)
    "O": (255, 255, 255),   # eye
    "_": (0, 0, 0),         # mouth
}

# Arkaplan: koyu mor (icon görünür kontrast için)
BACKGROUND = (28, 20, 46)   # #1C142E — derin koyu mor
ICON_SIZE = 1024


def render_mascot(size: int, *, transparent: bool, padding_ratio: float = 0.75) -> Image.Image:
    grid_size = 12
    cell = int(size * padding_ratio / grid_size)
    grid_pixels = cell * grid_size
    offset = (size - grid_pixels) // 2

    if transparent:
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    else:
        img = Image.new("RGB", (size, size), BACKGROUND)
    draw = ImageDraw.Draw(img)

    for y, row in enumerate(IDLE_FRAME):
        for x, ch in enumerate(row):
            color = PALETTE.get(ch)
            if color is None:
                continue
            x0 = offset + x * cell
            y0 = offset + y * cell
            draw.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], fill=color)
    return img


def write_png(img: Image.Image, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path, format="PNG", optimize=True)
    print(f"✓ {out_path} ({img.size[0]}x{img.size[1]}, {out_path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent.parent
    assets = repo_root / "ios/PixelAgentRemote/Assets.xcassets"

    write_png(render_mascot(ICON_SIZE, transparent=False),
              assets / "AppIcon.appiconset/AppIcon-1024.png")

    for scale, suffix in [(1, ""), (2, "@2x"), (3, "@3x")]:
        write_png(render_mascot(240 * scale, transparent=True, padding_ratio=0.9),
                  assets / f"LaunchIcon.imageset/LaunchIcon{suffix}.png")

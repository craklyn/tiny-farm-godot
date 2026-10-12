#!/usr/bin/env python3
"""Build the Industrial Barn's palette-locked exterior and interior kit.

The exterior is reduced from the selected Retro Diffusion source. The interior,
a hand-drawn 12 by 8 room, is built by `tools/build_barn_room_art.py`.
"""
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
from postprocess import check_no_white_edges, erase_white_edges, key_background

RAW = ROOT / "assets/raw/2026-10-08-w8081d9bfb69-industrial-barn-exterior/industrial-barn-exterior_1.png"
OUT = ROOT / "assets/sprites/generated"
EXTERIOR = OUT / "industrial_barn.png"

COLORS = {
    "red_dark": "#94371f", "red": "#c84e39", "wood_light": "#c39a6c",
    "wood": "#a97959", "wood_dark": "#90625d", "cream": "#f8f4e6",
    "steel": "#8d8e92", "deep": "#2f2b3d", "straw_light": "#e8cfa6",
    "straw": "#dcb98a", "tile": "#c9a06b", "warm_shadow": "#8b7c63",
    "cheese_dark": "#cca13c", "cheese_light": "#e9e178", "cheese": "#f0cf5a",
}
RGB = {name: tuple(int(value[i:i + 2], 16) for i in (1, 3, 5)) for name, value in COLORS.items()}
PALETTE = tuple(RGB.values())
PRODUCT_COLORS = frozenset((RGB["cream"], RGB["cheese_light"], RGB["cheese"], RGB["cheese_dark"]))


def nearest(rgb):
    return min(PALETTE, key=lambda c: sum((rgb[i] - c[i]) ** 2 for i in range(3)))


def px(im, x, y, color):
    im.putpixel((x, y), RGB[color] + (255,))


def rect(im, x0, y0, x1, y1, color):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(im, x, y, color)


def line(im, points, color):
    for x, y in points:
        px(im, x, y, color)


def build_exterior():
    raw = Image.open(RAW).convert("RGBA")
    cleaned = erase_white_edges(key_background(raw))
    cleaned.thumbnail((48, 32), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (48, 32), (0, 0, 0, 0))
    out.alpha_composite(cleaned, ((48 - cleaned.width) // 2, 32 - cleaned.height))
    data = out.load()
    for y in range(32):
        for x in range(48):
            if data[x, y][3]:
                data[x, y] = nearest(data[x, y][:3]) + (255,)
    # Keep a 16px clear cow entrance after the 4:1 reduction. The posts sit
    # outside the opening so their braces do not reduce the usable width.
    rect(out, 16, 22, 31, 29, "deep")
    rect(out, 15, 21, 32, 21, "wood_dark")
    rect(out, 15, 22, 15, 29, "wood_dark")
    rect(out, 32, 22, 32, 29, "wood_dark")
    check_no_white_edges(out)
    out.save(EXTERIOR)


def check(im, size):
    assert im.size == size, (im.size, size)
    assert all(p[3] in (0, 255) for p in im.getdata())
    assert all(p[3] == 0 or p[:3] in PALETTE for p in im.getdata())


def check_cow_doorway(exterior):
    """Keep the exterior's opening exactly one cow frame wide."""
    deep = RGB["deep"] + (255,)
    # The exterior opening is exactly one cow frame wide, with its posts outside.
    for y in range(22, 30):
        assert all(exterior.getpixel((x, y)) == deep for x in range(16, 32)), y
        assert exterior.getpixel((15, y))[:3] == RGB["wood_dark"], y
        assert exterior.getpixel((32, y))[:3] == RGB["wood_dark"], y


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    build_exterior()
    exterior = Image.open(EXTERIOR).convert("RGBA")
    check(exterior, (48, 32))
    check_cow_doorway(exterior)
    print("wrote industrial_barn.png (48x32); the room is `tools/build_barn_room_art.py`")


if __name__ == "__main__":
    main()

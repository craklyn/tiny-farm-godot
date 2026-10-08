#!/usr/bin/env python3
"""Build the Industrial Barn's palette-locked exterior and interior kit.

The exterior is reduced from the selected Retro Diffusion source.  The interior
is a hand-drawn 6 by 4 atlas because the room needs exact station placement,
an unobstructed cow route, and cells that fit the nested-grid renderer.
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
INTERIOR = OUT / "industrial_barn_interior_kit.png"

COLORS = {
    "red_dark": "#94371f", "red": "#c84e39", "wood_light": "#c39a6c",
    "wood": "#a97959", "wood_dark": "#90625d", "cream": "#f8f4e6",
    "steel": "#8d8e92", "deep": "#2f2b3d", "straw_light": "#e8cfa6",
    "straw": "#dcb98a", "tile": "#c9a06b", "warm_shadow": "#8b7c63",
    "cheese_dark": "#cca13c", "cheese_light": "#e9e178", "cheese": "#f0cf5a",
}
RGB = {name: tuple(int(value[i:i + 2], 16) for i in (1, 3, 5)) for name, value in COLORS.items()}
PALETTE = tuple(RGB.values())


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
    # Keep the cow entrance unmistakable after the 4:1 reduction.
    rect(out, 17, 22, 30, 29, "deep")
    rect(out, 16, 21, 31, 21, "wood_dark")
    rect(out, 16, 22, 16, 29, "wood_dark")
    rect(out, 31, 22, 31, 29, "wood_dark")
    for x in (19, 28):
        line(out, [(x, y) for y in range(23, 29)], "wood")
    check_no_white_edges(out)
    out.save(EXTERIOR)


def floor(im, x, y, warm):
    base = "straw_light" if warm else "cream"
    seam = "straw" if warm else "steel"
    rect(im, x, y, x + 15, y + 15, base)
    line(im, [(x + i, y + 11) for i in range(16)], seam)
    line(im, [(x + 3, y + i) for i in range(2, 11)], seam)
    line(im, [(x + 11, y + i) for i in range(12, 16)], seam)


def stall(im, x, y, lower=False):
    floor(im, x, y, True)
    rect(im, x, y, x + 15, y + 2, "tile")
    rect(im, x, y + 2, x + 1, y + 12, "wood_dark")
    rect(im, x + 14, y + 2, x + 15, y + 12, "wood_dark")
    rect(im, x + 2, y + 4, x + 13, y + 5, "wood_light")
    rect(im, x + 4, y + 8, x + 11, y + 10, "straw")
    # Low steel connection at the outer edge, never inside a cow silhouette.
    rect(im, x + 13, y + 11, x + 15, y + 12, "steel")
    px(im, x + 12, y + 12, "steel")
    if lower:
        rect(im, x + 3, y + 13, x + 6, y + 14, "wood")


def build_interior():
    im = Image.new("RGBA", (96, 64), (0, 0, 0, 0))
    # Four open stalls occupy the warm, door-side half of the room.
    stall(im, 0, 0)
    stall(im, 16, 0)
    stall(im, 0, 16, True)
    stall(im, 16, 16, True)
    # Wide open threshold / clear cow exit route.
    for yy in range(0, 32, 16):
        floor(im, 32, yy, True)
    rect(im, 32, 0, 33, 31, "wood_dark")
    rect(im, 34, 4, 35, 27, "wood_light")
    # The four low lines converge in the shared receiver.
    line(im, [(14, 12), (15, 12), (16, 12), (17, 12), (30, 12), (31, 12), (32, 12), (33, 12),
              (34, 12), (35, 12), (36, 12), (37, 12), (38, 12), (39, 12), (40, 12), (41, 12),
              (42, 12), (43, 12), (44, 12), (45, 12), (46, 12), (47, 12), (48, 12), (49, 12)], "steel")
    line(im, [(14, 28), (15, 28), (16, 28), (17, 28), (30, 28), (31, 28), (32, 28), (33, 28),
              (34, 28), (35, 28), (36, 28), (37, 28), (38, 28), (39, 28), (40, 28), (41, 28),
              (42, 28), (43, 28), (44, 28), (45, 28), (46, 28), (47, 28), (48, 28), (49, 28)], "steel")
    # Receiver, warm set vat with cutter/rake rail, then drain table.
    for col in range(3, 6):
        floor(im, col * 16, 0, False)
        floor(im, col * 16, 16, False)
    rect(im, 50, 5, 61, 14, "steel")
    rect(im, 52, 3, 59, 4, "cream")
    rect(im, 53, 7, 58, 12, "deep")
    px(im, 57, 6, "red")
    rect(im, 64, 5, 94, 14, "steel")
    rect(im, 66, 7, 92, 12, "tile")
    rect(im, 68, 8, 90, 11, "cheese_light")
    rect(im, 65, 3, 94, 4, "deep")
    rect(im, 73, 3, 74, 14, "steel")
    rect(im, 84, 3, 85, 14, "steel")
    line(im, [(66, 15), (67, 16), (68, 16), (69, 17), (70, 17), (71, 18), (72, 18)], "steel")
    rect(im, 50, 20, 61, 29, "steel")
    rect(im, 52, 21, 59, 23, "cheese_light")
    rect(im, 62, 25, 70, 28, "steel")
    line(im, [(59, 29), (60, 30), (61, 30), (62, 31), (63, 31), (64, 31)], "steel")
    # Repeated presses and their coiled yellow air hoses.
    for x in (74, 81, 88):
        rect(im, x, 20, x + 4, 30, "steel")
        rect(im, x + 1, 21, x + 3, 27, "cream")
        line(im, [(x, 19), (x + 1, 18), (x + 2, 19), (x + 3, 18), (x + 4, 19)], "cheese")
    # Winding mesh belt and visible finished cheese at the outfeed.
    line(im, [(65, 30), (66, 30), (67, 30), (68, 30), (69, 30), (70, 30), (71, 30), (72, 30),
              (72, 29), (72, 28), (72, 27), (73, 27), (74, 27), (75, 27), (76, 27), (77, 27),
              (78, 27), (79, 27), (80, 27), (81, 27), (82, 27), (83, 27), (84, 27), (85, 27),
              (86, 27), (87, 27), (88, 27), (89, 27), (90, 27), (91, 27), (92, 27), (93, 27)], "deep")
    rect(im, 88, 24, 91, 26, "cheese_dark")
    rect(im, 92, 24, 95, 26, "cheese")
    # Bottom row: straw door threshold, open crossing, and clean factory floor.
    for col in range(6):
        floor(im, col * 16, 32, col < 3)
        floor(im, col * 16, 48, col < 3)
    rect(im, 2, 48, 29, 50, "red_dark")
    rect(im, 5, 51, 26, 63, "deep")
    rect(im, 30, 48, 33, 63, "wood_dark")
    # White-tile processing wall reads separately without closing the crossing.
    for x in range(48, 96, 8):
        line(im, [(x, y) for y in range(33, 48)], "steel")
    for y in (39, 47):
        line(im, [(x, y) for x in range(48, 96)], "steel")
    return im


def check(im, size):
    assert im.size == size, (im.size, size)
    assert all(p[3] in (0, 255) for p in im.getdata())
    assert all(p[3] == 0 or p[:3] in PALETTE for p in im.getdata())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    build_exterior()
    interior = build_interior()
    check(Image.open(EXTERIOR).convert("RGBA"), (48, 32))
    check(interior, (96, 64))
    interior.save(INTERIOR)
    print("wrote industrial_barn.png (48x32) and industrial_barn_interior_kit.png (96x64)")


if __name__ == "__main__":
    main()

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


def hay_rack(im, x, y):
    floor(im, x, y, True)
    rect(im, x + 2, y + 2, x + 13, y + 4, "wood_dark")
    rect(im, x + 3, y + 5, x + 12, y + 12, "straw")
    rect(im, x + 4, y + 6, x + 11, y + 9, "straw_light")
    rect(im, x + 2, y + 13, x + 13, y + 14, "wood")


def feed_bin(im, x, y):
    floor(im, x, y, True)
    rect(im, x + 3, y + 4, x + 12, y + 12, "wood_dark")
    rect(im, x + 4, y + 3, x + 11, y + 5, "wood_light")
    rect(im, x + 5, y + 7, x + 10, y + 10, "straw")
    rect(im, x + 2, y + 13, x + 13, y + 14, "wood")


def receiver(im, x, y):
    floor(im, x, y, False)
    rect(im, x + 3, y + 5, x + 12, y + 13, "steel")
    rect(im, x + 4, y + 3, x + 11, y + 5, "cream")
    # A broad pale fill makes the first product state legible, not just a lamp.
    rect(im, x + 5, y + 7, x + 10, y + 11, "cream")
    line(im, [(x + xx, y + 7) for xx in range(5, 11)], "cheese_light")
    rect(im, x + 7, y + 1, x + 8, y + 2, "steel")
    px(im, x + 11, y + 6, "red")


def vat(im, x, y):
    floor(im, x, y, False)
    rect(im, x + 1, y + 5, x + 14, y + 13, "steel")
    rect(im, x + 3, y + 4, x + 12, y + 6, "cream")
    rect(im, x + 4, y + 7, x + 11, y + 11, "tile")
    rect(im, x + 5, y + 8, x + 10, y + 10, "cream")


def cutter(im, x, y):
    floor(im, x, y, False)
    rect(im, x + 1, y + 2, x + 14, y + 3, "deep")
    rect(im, x + 6, y + 3, x + 9, y + 5, "steel")
    rect(im, x + 3, y + 7, x + 12, y + 13, "steel")
    for xx in (5, 7, 9, 11):
        line(im, [(x + xx, y + 5), (x + xx, y + 10)], "cream")
    # Curds fill the tray as a cluster; each is more than a lone decorative pixel.
    for xx, yy in ((4, 11), (5, 11), (7, 12), (8, 12), (10, 11), (11, 11), (12, 12)):
        px(im, x + xx, y + yy, "cheese_light")


def rake(im, x, y):
    floor(im, x, y, False)
    rect(im, x + 1, y + 2, x + 14, y + 3, "deep")
    rect(im, x + 7, y + 3, x + 8, y + 7, "steel")
    rect(im, x + 3, y + 8, x + 12, y + 13, "steel")
    rect(im, x + 4, y + 7, x + 11, y + 8, "cream")
    for xx in (5, 7, 9, 11):
        line(im, [(x + xx, y + 8), (x + xx - 1, y + 10)], "steel")
    rect(im, x + 5, y + 11, x + 10, y + 12, "cheese_light")
    px(im, x + 6, y + 10, "cheese_light")
    px(im, x + 9, y + 10, "cheese_light")


def drain_table(im, x, y):
    floor(im, x, y, False)
    rect(im, x + 1, y + 6, x + 14, y + 8, "steel")
    rect(im, x + 3, y + 4, x + 11, y + 6, "cream")
    # The broad slab touches both the incoming trough and the outgoing belt.
    rect(im, x + 5, y + 4, x + 10, y + 6, "cheese_light")
    rect(im, x + 2, y + 9, x + 3, y + 13, "steel")
    rect(im, x + 12, y + 9, x + 13, y + 13, "steel")
    line(im, [(x + 14, y + 8), (x + 14, y + 9), (x + 13, y + 10)], "steel")


def press_bank(im, x, y):
    floor(im, x, y, False)
    # Three 4-pixel forming hoops read as rings at native size, under distinct presses.
    for xx in (2, 7, 12):
        rect(im, x + xx, y + 4, x + xx + 3, y + 5, "steel")
        rect(im, x + xx + 1, y + 6, x + xx + 2, y + 8, "steel")
        line(im, [(x + xx + 1, y + 9), (x + xx + 2, y + 9)], "cheese")
        line(im, [(x + xx, y + 10), (x + xx + 3, y + 10)], "cheese")
        line(im, [(x + xx, y + 11), (x + xx + 3, y + 11)], "cheese")
        line(im, [(x + xx + 1, y + 12), (x + xx + 2, y + 12)], "cheese")
        px(im, x + xx + 1, y + 11, "cheese_light")
        px(im, x + xx + 2, y + 11, "cheese_light")
    # A low mesh belt visibly takes the formed cheese toward the outfeed.
    line(im, [(x + xx, y + 14) for xx in range(1, 15)], "deep")
    line(im, [(x + xx, y + 13) for xx in range(2, 14)], "steel")


def outfeed(im, x, y):
    floor(im, x, y, False)
    rect(im, x + 1, y + 10, x + 14, y + 12, "deep")
    rect(im, x + 2, y + 9, x + 13, y + 10, "steel")
    rect(im, x + 3, y + 13, x + 4, y + 14, "steel")
    rect(im, x + 11, y + 13, x + 12, y + 14, "steel")
    # Two compact round wheels: pointed top/bottom, wide middle, pale face.
    for xx in (4, 9):
        line(im, [(x + xx + 1, y + 3), (x + xx + 2, y + 3)], "cheese_dark")
        rect(im, x + xx, y + 4, x + xx + 3, y + 6, "cheese")
        line(im, [(x + xx + 1, y + 7), (x + xx + 2, y + 7)], "cheese_dark")
        rect(im, x + xx + 1, y + 4, x + xx + 2, y + 6, "cheese_light")


def build_interior():
    im = Image.new("RGBA", (96, 64), (0, 0, 0, 0))
    # Warm supplies and open stalls make care read before machinery.
    hay_rack(im, 0, 0)
    feed_bin(im, 16, 0)
    stall(im, 32, 0)
    stall(im, 48, 0)
    stall(im, 32, 16, True)
    stall(im, 48, 16, True)
    # A clean, uninterrupted route reaches every stall and the open door.
    for x, y in ((0, 16), (16, 16), (0, 32), (16, 32), (32, 32), (48, 32), (0, 48), (16, 48)):
        floor(im, x, y, True)
    rect(im, 2, 48, 29, 50, "red_dark")
    rect(im, 5, 51, 26, 63, "deep")
    rect(im, 30, 32, 31, 47, "wood_dark")
    # The seven stations form a single, readable serpentine route on the steel side.
    receiver(im, 64, 0)
    vat(im, 80, 0)
    cutter(im, 80, 16)
    rake(im, 64, 16)
    drain_table(im, 64, 32)
    press_bank(im, 80, 32)
    outfeed(im, 80, 48)
    for x, y in ((32, 48), (48, 48), (64, 48)):
        floor(im, x, y, False)
    # Low pipes travel above the stall fronts and turn into the receiver; none cross the route.
    line(im, [(46, 12), (47, 12), (48, 12), (49, 12), (50, 12), (51, 12), (52, 12), (53, 12),
              (54, 12), (55, 12), (56, 12), (57, 12), (58, 12), (59, 12), (60, 12), (61, 12),
              (62, 12), (63, 12), (64, 12), (65, 12), (66, 12), (67, 12)], "steel")
    line(im, [(62, 28), (63, 28), (64, 28), (65, 28), (66, 28), (67, 28), (67, 27), (67, 26),
              (67, 25), (67, 24), (67, 23), (67, 22), (67, 21), (67, 20), (67, 19), (67, 18)], "steel")
    # Product joins touch the product areas, so the sequence reads as one continuous run.
    # Receiver milk enters the vat, then becomes curds in the cutter and rake.
    line(im, [(x, 9) for x in range(75, 85)], "cream")
    # Start on the vat's fill at y=11: leaving this one pixel blank breaks the route.
    line(im, [(88, y) for y in range(11, 28)], "cheese_light")
    line(im, [(x, 28) for x in range(75, 89)], "cheese_light")
    # The rake's curds descend into the table slab, then reach the first forming hoop.
    line(im, [(72, y) for y in range(28, 37)], "cheese_light")
    line(im, [(x, 37) for x in range(72, 83)], "cheese_light")
    line(im, [(82, y) for y in range(37, 43)], "cheese")
    # A formed hoop leaves the press belt and enters the first round wheel on the outfeed.
    # This crosses the belt at y=45, so the press has no one-pixel gap before the outfeed.
    line(im, [(x, 45) for x in range(83, 89)], "cheese")
    line(im, [(88, y) for y in range(45, 52)], "cheese")
    line(im, [(86, 51), (87, 51), (88, 51)], "cheese")
    # Processing wall tiles frame the line without closing the livestock crossing.
    for x in range(64, 96, 8):
        line(im, [(x, y) for y in range(49, 64)], "steel")
    for y in (55, 63):
        line(im, [(x, y) for x in range(64, 96)], "steel")
    # The wall grid sits behind the outfeed join, never over the travelling cheese.
    line(im, [(x, 45) for x in range(83, 89)], "cheese")
    line(im, [(88, y) for y in range(45, 52)], "cheese")
    line(im, [(86, 51), (87, 51), (88, 51)], "cheese")
    return im


def check(im, size):
    assert im.size == size, (im.size, size)
    assert all(p[3] in (0, 255) for p in im.getdata())
    assert all(p[3] == 0 or p[:3] in PALETTE for p in im.getdata())


def check_interior_readability(im):
    """Keep the hand-drawn route and its native-size forms from quietly regressing."""
    # Each coordinate is where a join meets the product area of its next station.
    for point, color in (
        ((75, 9), "cream"), ((84, 9), "cream"),
        ((88, 27), "cheese_light"), ((75, 28), "cheese_light"),
        ((72, 36), "cheese_light"), ((82, 41), "cheese"),
        ((88, 46), "cheese"), ((86, 51), "cheese"),
    ):
        assert im.getpixel(point)[:3] == RGB[color], (point, color)
    # Hoops and wheels have pointed ends and a four-pixel-wide middle, not square marks.
    for x in (82, 87, 92):
        assert all(im.getpixel((x + dx, 41))[:3] == RGB["cheese"] for dx in (1, 2))
        assert all(im.getpixel((x + dx, 42))[:3] == RGB["cheese"] for dx in (0, 3))
        assert all(im.getpixel((x + dx, 44))[:3] == RGB["cheese"] for dx in (1, 2))
    for x in (84, 89):
        assert all(im.getpixel((x + dx, 52))[:3] in (RGB["cheese"], RGB["cheese_light"])
                   for dx in range(4))
        assert all(im.getpixel((x + dx, 54))[:3] in (RGB["cheese"], RGB["cheese_light"])
                   for dx in range(4))


def check_cow_doorways(exterior, interior):
    """Keep the 16px cow clearances aligned between the two barn views."""
    deep = RGB["deep"] + (255,)
    # The exterior opening is exactly one cow frame wide, with its posts outside.
    for y in range(22, 30):
        assert all(exterior.getpixel((x, y)) == deep for x in range(16, 32)), y
        assert exterior.getpixel((15, y))[:3] == RGB["wood_dark"], y
        assert exterior.getpixel((32, y))[:3] == RGB["wood_dark"], y
    # The interior's threshold remains wider than the exterior opening.
    for y in range(51, 64):
        assert all(interior.getpixel((x, y)) == deep for x in range(5, 27)), y


def check_connected_product_path(im):
    """Assert that the visible route is a four-neighbour-connected run of product pixels."""
    # This is the ordered travel path, including its entrances and exits at every station.
    # Each pixel must carry a product colour and touch the next one, which catches a gap even
    # when the surrounding machinery happens to use the same floor or steel colours.
    route = []
    route += [(x, 9) for x in range(69, 89)]
    route += [(88, y) for y in range(10, 29)]
    route += [(x, 28) for x in range(87, 71, -1)]
    route += [(72, y) for y in range(29, 38)]
    route += [(x, 37) for x in range(73, 83)]
    route += [(82, y) for y in range(38, 44)]
    route += [(83, 43)]
    route += [(x, 44) for x in range(83, 85)]
    route += [(84, 45)]
    route += [(x, 45) for x in range(83, 89)]
    route += [(88, y) for y in range(46, 52)]
    route += [(x, 51) for x in range(87, 84, -1)]

    for point in route:
        assert im.getpixel(point)[:3] in PRODUCT_COLORS, point
    for before, after in zip(route, route[1:]):
        assert abs(before[0] - after[0]) + abs(before[1] - after[1]) <= 1, (before, after)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    build_exterior()
    interior = build_interior()
    exterior = Image.open(EXTERIOR).convert("RGBA")
    check(exterior, (48, 32))
    check(interior, (96, 64))
    check_interior_readability(interior)
    check_cow_doorways(exterior, interior)
    check_connected_product_path(interior)
    interior.save(INTERIOR)
    print("wrote industrial_barn.png (48x32) and industrial_barn_interior_kit.png (96x64)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build the barn cow's four calm 16px walking frames.

She is black and white (Daniel's pick, 2026-10-10). The first cow's tan hide was the
creamery's straw floor colour, #e8cfa6, which is also tilled soil, so inside the barn
she showed only her outline (design/17, "Cows on the straw").
"""
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "assets/sprites/generated/cow.png"
COLORS = {"ink": (47, 43, 61), "cream": (248, 244, 230), "pink": (200, 78, 57)}
# Two broad patches, each wider than a pixel or two, so the pattern survives play scale.
PATCHES = [(4, 7), (5, 7), (4, 8), (5, 8), (6, 8), (5, 9),
           (8, 9), (9, 9), (8, 10), (9, 10), (10, 9), (10, 7)]


def put(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), COLORS[c] + (255,))


def frame(im, ox, lift, step):
    # A generous body and open feet read as a relaxed animal, never as a restraint.
    for y in range(6, 12):
        for x in range(2, 12):
            if not (x == 2 and y in (6, 11)):
                put(im, ox + x, y - lift, "cream")
    for x, y in [(2, 7), (3, 6), (10, 6), (11, 7), (12, 8), (12, 9), (1, 9), (0, 8), (13, 5), (14, 4), (14, 6)]:
        put(im, ox + x, y - lift, "ink")
    for x, y in PATCHES: put(im, ox + x, y - lift, "ink")
    put(im, ox + 14, 5 - lift, "cream"); put(im, ox + 13, 7 - lift, "ink")
    put(im, ox + 14, 7 - lift, "pink")
    for x in (4, 9):
        put(im, ox + x + step, 12 - lift, "ink")
        put(im, ox + x + step, 13 - lift, "ink")
    put(im, ox + 1, 6 - lift, "ink")


im = Image.new("RGBA", (64, 16), (0, 0, 0, 0))
for i, (lift, step) in enumerate(((0, 0), (1, 1), (0, 1), (1, 0))):
    frame(im, i * 16, lift, step)
assert all(p[3] in (0, 255) for p in im.getdata())
assert all(p[3] == 0 or p[:3] in COLORS.values() for p in im.getdata())
# The creamery's straw floor and tilled soil: a cow drawn in it vanishes on both.
assert all(p[3] == 0 or p[:3] != (232, 207, 166) for p in im.getdata())
im.save(OUT)
print(OUT)

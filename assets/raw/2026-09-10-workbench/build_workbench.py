#!/usr/bin/env python3
"""Compose assets/sprites/generated/workbench.png (16x32) from this batch's raws.

WI-7 of docs/V0_2_2_PLAN.md. Two generations, composed locally — the pixel-art
skill's standing rule is never to pay the model for layout, so the batch bought
two subjects and the arrangement is drawn here:

  bench_1.png  the wooden bench with the steel vice   -> the lower mass
  rack_0.png   the row of brass plates on a rail      -> the part rising above

Steps, in order:
  1. key_background      flood the flat cream to alpha (free; more predictable
                         than the API's remove_bg)
  2. drop_pocket         the enclosed cream between the bench legs survives (1),
                         because the flood never reaches it from a corner
  3. strip_slab          the generator bakes a wide ground slab under the bench;
                         below the feet line only the leg columns survive
  4. NEAREST downscale   about 4:1, nearest only, never up
  5. compose             bench on the cell floor, rack planted on the bench top
  6. snap_palette        THE PALETTE LOCK: every opaque pixel to the nearest
                         colour in LOCK (hexes the shipped sprites already use),
                         alpha forced to 0 or 255
  7. touch_ups           four rules that make the object read at 16 px: outline
                         the brass, close the rack's rail, shade the bench's
                         front apron, and keep the steel ramp to the vice
  8. check               16x32, binary alpha, nothing off the lock — asserted

Run:  python3 assets/raw/2026-09-10-workbench/build_workbench.py
It rewrites the sprite and this directory's contact_sheet.png, and nothing else.
"""
import os
import sys

from PIL import Image

sys.path.insert(0, "/home/daniel/.claude/skills/retro-diffusion-pixel-art/scripts")
from postprocess import contact_sheet, key_background  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
OUT = os.path.join(REPO, "assets", "sprites", "generated", "workbench.png")

CELL_W, CELL_H = 16, 32

# The palette lock. Every one of these already appears in the shipped sprites
# (well.png, seed_box.png, robot_stall.png, crops.png), so the bench cannot
# introduce a colour the game does not already use.
LOCK = [
    "#c39a6c", "#a97959", "#90625d",   # wood: base, mid, outline/shadow
    "#b8b2ac", "#8f8880", "#6f6862",   # steel: light, mid, outline
    "#f0cf5a", "#cba13c", "#997a2e",   # brass: highlight, mid, outline
]
# The cream #f8f4e6 the well and the seed box use is deliberately NOT in the
# lock. Downscaled, the bench top's highlight line became a solid cream stripe
# across the sprite and pulled the eye off the plates; snapping it to the light
# wood leaves the brass as the only bright note, which is what this object is.
LOCK_RGB = [tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) for h in LOCK]

DARK = {(0x90, 0x62, 0x5d), (0x6f, 0x68, 0x62), (0xa8, 0x79, 0x59)}

# Forced before the nearest-colour snap. The generation's cream highlight line
# along the bench top is nearer the brass highlight than the light wood in any
# plain colour metric, so left to the snap it painted a gold stripe across the
# bench. It belongs to the wood.
REMAP = {(0xf8, 0xf4, 0xe6): (0xc3, 0x9a, 0x6c)}

# The vice's box in the finished cell (x0, y0, x1, y1, inclusive) — the only
# part of the sprite allowed to keep the steel ramp.
VICE = (0, 21, 5, 26)


def load(name):
    return key_background(Image.open(os.path.join(HERE, name + ".png")))


def drop_pocket(im, seed, tol=10):
    """Flood the enclosed background pocket between the bench legs to alpha."""
    from collections import deque

    px = im.load()
    w, h = im.size
    base = px[seed][:3]
    queue, seen = deque([seed]), set()
    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        r, g, b, a = px[x, y]
        if a and all(abs(c - c0) <= tol for c, c0 in zip((r, g, b), base)):
            px[x, y] = (0, 0, 0, 0)
            queue.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return im


def strip_slab(im, floor, legs, stretcher):
    """Below the bench top's shadow line the generator painted a ground slab.

    Keep only what is structurally the bench: the two leg columns all the way
    down, and the dark lower stretcher between them.
    """
    px = im.load()
    w, h = im.size
    lo, hi = stretcher
    for y in range(floor, h):
        for x in range(w):
            if not px[x, y][3]:
                continue
            in_leg = any(a <= x <= b for a, b in legs)
            in_str = lo <= y <= hi and px[x, y][:3] in DARK
            if not (in_leg or in_str):
                px[x, y] = (0, 0, 0, 0)
    return im


def shrink(im, width, height=None):
    """NEAREST downscale to an exact width, height by aspect unless given."""
    box = im.getbbox()
    im = im.crop(box)
    if height is None:
        height = max(1, round(im.height * width / im.width))
    return im.resize((width, height), Image.NEAREST)


def snap_palette(im):
    """The palette lock: nearest LOCK colour for every opaque pixel, alpha binary."""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
                continue
            r, g, b = REMAP.get((r, g, b), (r, g, b))
            best = min(LOCK_RGB, key=lambda c: (c[0] - r) ** 2 * 2 + (c[1] - g) ** 2 * 4 + (c[2] - b) ** 2)
            px[x, y] = best + (255,)
    return im


def touch_ups(im, rail_y, rail_x, apron_y):
    """The few pixels the downscale cannot get right on its own. Three rules:

    1. Outline the brass outward in the brass outline colour — the style file's
       "golden heads with dark amber outlines". Undrawn, the plates met the
       grass with no edge at all.
    2. Close the rail, so three plates read as one rack and not three signs.
    3. Give the bench's front apron the mid wood. The yard grass (#c0d470) and
       the light wood (#c39a6c) sit at almost the same value, so a bench face
       in light wood alone dissolves into the lawn; shading the apron also
       reads as the top being the lit surface.
    """
    px = im.load()
    w, h = im.size
    brass = {(0xf0, 0xcf, 0x5a), (0xcb, 0xa1, 0x3c)}
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3]:
                continue
            if any(0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][:3] in brass
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge.append((x, y))
    for x, y in edge:
        px[x, y] = (0x99, 0x7a, 0x2e, 255)
    lo, hi = rail_x
    for x in range(lo, hi + 1):
        if not px[x, rail_y][3]:
            px[x, rail_y] = (0x90, 0x62, 0x5d, 255)
    for x in range(w):
        if px[x, apron_y][:3] in ((0xc3, 0x9a, 0x6c), (0xb8, 0xb2, 0xac)):
            px[x, apron_y] = (0xa9, 0x79, 0x59, 255)   # the second also kills a steel speck
    # 4. The steel family belongs to the vice and to nothing else. The
    #    generation shaded the bench's underside and legs in the same greys it
    #    used for the vice, which left a wooden bench with cold grey legs and
    #    no metal object to look at. Outside the vice's box the steels go back
    #    to the wood ramp (the style file's per-material outline anchors), so
    #    the vice becomes the one steel thing on the sprite.
    steel_to_wood = {(0x6f, 0x68, 0x62): (0x90, 0x62, 0x5d),
                     (0x8f, 0x88, 0x80): (0xa9, 0x79, 0x59),
                     (0xb8, 0xb2, 0xac): (0xc3, 0x9a, 0x6c)}
    for y in range(h):
        for x in range(w):
            if VICE[0] <= x <= VICE[2] and VICE[1] <= y <= VICE[3]:
                continue
            swap = steel_to_wood.get(px[x, y][:3])
            if swap and px[x, y][3]:
                px[x, y] = swap + (255,)
    return im


def build():
    # --- the bench ------------------------------------------------------
    bench = load("bench_1")
    drop_pocket(bench, (30, 36))               # cream trapped between the legs
    # Only the legs survive below the feet line: the generation's lower
    # stretcher became a second horizontal bar and read as clutter at 16 px.
    strip_slab(bench, floor=43, legs=[(11, 20), (43, 52)], stretcher=(0, -1))
    bench = shrink(bench, 16)

    # --- the rack of brass plates ---------------------------------------
    # Three plates and their two posts out of the generation's seven: a
    # narrower crop scales to a taller cell, which is what buys the plates
    # enough rows to still read as plates at 16 px.
    rack = load("rack_0")
    rack = rack.crop((9, 27, 28, 45))
    rack = shrink(rack, 11, 10)

    # --- compose --------------------------------------------------------
    # Rack first, so the bench top draws over the feet of its posts; and set
    # right of centre, clear of the vice, which owns the bench's left end.
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    bench_y = CELL_H - bench.height
    rack_y = bench_y - rack.height + 1
    cell.alpha_composite(rack, (4, rack_y))
    cell.alpha_composite(bench, ((CELL_W - bench.width) // 2, bench_y))

    cell = snap_palette(cell)
    cell = touch_ups(cell, rail_y=rack_y + rack.height - 1, rail_x=(4, 14),
                     apron_y=CELL_H - 7)
    return cell


def check(img):
    """The two things that must hold before this ships."""
    assert img.size == (CELL_W, CELL_H), img.size
    seen = set()
    for count, (r, g, b, a) in img.getcolors(9999):
        assert a in (0, 255), "alpha must be 0 or 255, saw %d" % a
        if a:
            seen.add("#%02x%02x%02x" % (r, g, b))
    stray = seen - set(LOCK)
    assert not stray, "off-lock colours: %s" % sorted(stray)
    return sorted(seen)


if __name__ == "__main__":
    img = build()
    print("palette:", " ".join(check(img)))
    img.save(OUT)
    print("wrote", OUT, img.size)
    sheet_src = [os.path.join(HERE, n + ".png")
                 for n in ("bench_0", "bench_1", "rack_0", "rack_1")] + [OUT]
    sheet = contact_sheet(sheet_src, cell=160, cols=5)
    sheet.save(os.path.join(HERE, "contact_sheet.png"))
    print("contact sheet", os.path.join(HERE, "contact_sheet.png"))

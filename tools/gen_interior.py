#!/usr/bin/env python3
"""Derive the home interior's placeholder art (T-37).

The designer's directive of 2026-09-01: *"create an indoor space representing
the player's home. The home should have the bed, windows, and very few
furnishings initially."* These are the pictures of that space:

  assets/sprites/generated/terrain_floor.png  48x48 — 3x3 of one seamless
      16px wood-plank tile (the terrain_grass.png format, so the renderer
      treats it exactly like the other grounds)
  assets/sprites/generated/interior.png       32x16 — cell 0 wall, cell 1
      window (a wall cell with a pane)

Derived, not generated, in the yard-ground tradition (tools/gen_yard_ground.py):
the planks and trim take their browns from the fence cell of obstacles.png, so
indoor wood and outdoor wood are the same wood. The wall plaster is the fence's
lightest brown mixed toward cream; the window pane is the one new colour (a
quiet blue — no ambient tile in the game is blue, so it reads as sky through
glass). All placeholder, pending the Q-14 style-guide reskin.

Idempotent, deterministic, no network.

    python3 tools/gen_interior.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "assets", "sprites", "generated")


def luminance(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def fence_palette():
    """The fence cell's browns: darkest, median, lightest by luminance."""
    img = Image.open(os.path.join(SPRITES, "obstacles.png")).convert("RGBA")
    colors = {}
    for y in range(16):
        for x in range(64, 80):  # cell 4: the fence
            r, g, b, a = img.getpixel((x, y))
            if a > 0:
                colors[(r, g, b)] = colors.get((r, g, b), 0) + 1
    # The fence sprite carries baked-in grass tufts; keep only the warm wood
    # colours (greens have g outrunning r).
    woods = [c for c in colors if c[0] >= c[1] * 0.95 and c[1] >= c[2] * 0.8]
    ranked = sorted(woods, key=luminance)
    return ranked[0], ranked[len(ranked) // 2], ranked[-1]


def floor_tile(dark, mid, light):
    """One seamless 16px plank tile: four 4px plank bands, staggered seams."""
    t = Image.new("RGBA", (16, 16))
    seam = mix(dark, (0, 0, 0), 0.35)
    band_shade = [
        mix(mid, light, 0.20), mix(mid, light, 0.45),
        mix(mid, light, 0.30), mix(mid, dark, 0.12),
    ]
    for y in range(16):
        band = y // 4
        for x in range(16):
            t.putpixel((x, y), band_shade[band])
    # plank underside seams (bottom row of each band)
    for band in range(4):
        for x in range(16):
            t.putpixel((x, band * 4 + 3), seam)
    # staggered vertical butt-joints, one per band, seamless across the wrap
    for band in range(4):
        jx = (band * 7 + 2) % 16
        for dy in range(3):
            t.putpixel((jx, band * 4 + dy), seam)
    # sparse deterministic grain flecks
    for i, (fx, fy) in enumerate([(4, 1), (11, 5), (2, 9), (13, 13), (7, 14)]):
        t.putpixel((fx, fy), mix(dark, mid, 0.5))
    return t


def wall_cell(dark, mid, light):
    """A plaster wall with a wood baseboard."""
    plaster = mix(light, (250, 244, 228), 0.62)
    plaster_dim = mix(plaster[:3], mid, 0.18)
    c = Image.new("RGBA", (16, 16))
    for y in range(16):
        for x in range(16):
            c.putpixel((x, y), plaster)
    # quiet plaster texture
    for fx, fy in [(3, 2), (10, 4), (6, 7), (13, 9), (2, 11), (9, 12)]:
        c.putpixel((fx, fy), plaster_dim)
    # top shadow line (ceiling edge) and wood baseboard
    for x in range(16):
        c.putpixel((x, 0), mix(mid, dark, 0.4))
        c.putpixel((x, 13), mid + (255,))
        c.putpixel((x, 14), mix(mid, dark, 0.3))
        c.putpixel((x, 15), dark + (255,))
    return c


def window_cell(wall, dark, mid):
    """The wall cell with a paned window set into it."""
    c = wall.copy()
    pane = (128, 162, 184, 255)     # sky through glass — the one new colour
    pane_lo = (108, 140, 162, 255)
    frame = mix(mid, dark, 0.25)
    for y in range(3, 11):
        for x in range(4, 12):
            c.putpixel((x, y), pane if (x + y) % 5 else pane_lo)
    for x in range(3, 13):          # frame
        c.putpixel((x, 2), frame)
        c.putpixel((x, 11), frame)
    for y in range(2, 12):
        c.putpixel((3, y), frame)
        c.putpixel((12, y), frame)
    for y in range(3, 11):          # cross mullions
        c.putpixel((7, y), frame)
        c.putpixel((8, y), frame)
    for x in range(4, 12):
        c.putpixel((x, 6), frame)
        c.putpixel((x, 7), frame)
    # sill
    for x in range(3, 13):
        c.putpixel((x, 12), mid + (255,))
    return c


def main():
    dark, mid, light = fence_palette()
    tile = floor_tile(dark, mid, light)
    floor = Image.new("RGBA", (48, 48))
    for ty in range(3):
        for tx in range(3):
            floor.paste(tile, (tx * 16, ty * 16))
    floor.save(os.path.join(SPRITES, "terrain_floor.png"))

    wall = wall_cell(dark, mid, light)
    window = window_cell(wall, dark, mid)
    sheet = Image.new("RGBA", (32, 16))
    sheet.paste(wall, (0, 0))
    sheet.paste(window, (16, 0))
    sheet.save(os.path.join(SPRITES, "interior.png"))
    print("wrote terrain_floor.png (48x48) and interior.png (32x16)"
          f" from fence browns {dark} / {mid} / {light}")


if __name__ == "__main__":
    main()

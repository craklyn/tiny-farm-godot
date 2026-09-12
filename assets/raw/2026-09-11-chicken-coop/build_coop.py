#!/usr/bin/env python3
"""Compose assets/sprites/generated/chicken_coop.png (32x48) from this batch's raw.

The chicken coop (2026-09-11) — the first structure in the game that stands two
cells deep as well as two wide, so its cell is 32 wide (two tiles of ground) by 48
tall (those two tiles, plus 16 pixels of roof rising behind the block).

One generation, one subject. The pixel-art skill's standing rule is never to pay
the model for layout: the batch bought a hen house and the arrangement is drawn
here.

  coop_0.png  the hutch with the open arch and the ramp  -> the whole sprite
  coop_1.png  a closed shed with a small round hole      -> rejected: a hen who
              goes inside has to be visible inside, and a coin-sized hole at 32px
              is a dark dot rather than a doorway

Steps, in order:
  1. key_background   flood the flat cream to alpha (free; more predictable than
                      the API's remove_bg)
  2. drop_pockets     the cream trapped under the eaves and between the ramp rails
                      survives (1), because the flood never reaches it from a corner
  3. keep_largest     the run's left post comes away under the downscale; only the
                      mass the hut is part of survives
  4. trim + scale     crop to content and downscale 3:1, nearest only, never up
  5. compose          stood on the floor of the cell and centred, so the hut's feet
                      are on the front row of the block
  6. snap_palette     THE PALETTE LOCK: every opaque pixel to the nearest colour in
                      LOCK (hexes the shipped sprites already use), alpha binary
  7. tidy_skirt       below the eaves the sprite is only as wide as the hut; the
                      run's rails survive the downscale as lint on one side only
  8. darken_doorway   the arch is where the hen sits; forced to the darkest wood so
                      she reads against it at 32px rather than merging into it
  9. check            32x48, binary alpha, nothing off the lock — asserted

Run:  python3 assets/raw/2026-09-11-chicken-coop/build_coop.py
It rewrites the sprite and this directory's contact_sheet.png, and nothing else.
"""
import os
import sys
from collections import deque

from PIL import Image

sys.path.insert(0, "/home/daniel/.claude/skills/retro-diffusion-pixel-art/scripts")
from postprocess import key_background  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
OUT = os.path.join(REPO, "assets", "sprites", "generated", "chicken_coop.png")

CELL_W, CELL_H = 32, 48
SCALE = 3

# The palette lock. Every one of these already appears in the shipped sprites
# (well.png, seed_box.png, robot_stall.png, workbench.png), so the coop cannot
# introduce a colour the game does not already use. Wood for the hutch, the roof
# and the run's rail; the rose accent for the roof ridge, which is the one note
# that tells the coop apart from the stall at a glance across a yard.
LOCK = [
    "#c39a6c", "#a97959", "#90625d",   # wood: base, mid, outline/shadow
    "#6f4a45",                          # the dark of the open doorway
    "#d99a9a", "#b87a7a",               # rose: the roof ridge and its shade
]
LOCK_RGB = [tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) for h in LOCK]
DOOR_DARK = (0x6f, 0x4a, 0x45)


def key(name):
    return key_background(Image.open(os.path.join(HERE, name + ".png")))


def drop_pockets(im, tol=14):
    """Flood every enclosed cream pocket to alpha, from the inside out.

    key_background floods from the corners, so cream the silhouette encloses —
    under the eaves, between the ramp's rails — survives it as opaque background.
    Rather than guess seeds, every remaining pixel that is still the flat cream is
    cleared, which is safe here because nothing in the locked palette is that
    colour.
    """
    px = im.load()
    cream = (0xf8, 0xf4, 0xe6)
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and max(abs(r - cream[0]), abs(g - cream[1]), abs(b - cream[2])) <= tol:
                px[x, y] = (0, 0, 0, 0)
    return im


def keep_largest(im):
    """Drop everything the hut is not joined to.

    The generation stands the hutch inside a low run, and the run's left-hand post
    comes away from the rest of it under a 3:1 downscale — a two-by-five rose speck
    floating beside the coop's feet, which at 32 pixels reads as dirt on the lens
    rather than as fencing. Only the connected mass the hut itself is part of
    survives.
    """
    px = im.load()
    w, h = im.size
    seen = [[False] * w for _ in range(h)]
    best, best_size = None, 0
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or px[sx, sy][3] < 128:
                continue
            comp, q = [], deque([(sx, sy)])
            seen[sy][sx] = True
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] \
                            and px[nx, ny][3] >= 128:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) > best_size:
                best, best_size = comp, len(comp)
    keep = set(best or [])
    for y in range(h):
        for x in range(w):
            if px[x, y][3] and (x, y) not in keep:
                px[x, y] = (0, 0, 0, 0)
    return im


def content_box(im):
    px = im.load()
    w, h = im.size
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 8:
                xs.append(x)
                ys.append(y)
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def snap(im):
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
                continue
            best = min(LOCK_RGB, key=lambda c: (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2)
            px[x, y] = best + (255,)
    return im


def darken_doorway(im):
    """The arch is where the hen sits, so it has to read as a hole.

    The doorway is the one enclosed dark region in the middle of the hut, and the
    downscale muddies it towards the mid wood. Every opaque pixel inside the box
    below that is darker than the base wood is forced to the door's own dark.
    """
    px = im.load()
    x0, y0, x1, y1 = DOORWAY
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a and (r + g + b) < (0xc3 + 0x9a + 0x6c):
                px[x, y] = DOOR_DARK + (255,)
    return im


# The doorway's box in the finished cell (x0, y0, x1, y1), found by eye on the
# first build and pinned here so a rerun cannot drift.
DOORWAY = (11, 27, 22, 44)

# Below the eaves, the sprite is only as wide as the hut itself. The generation
# stands the hutch inside a low rail run whose posts stick out past it on both
# sides; three pixels of rose survive the downscale on the left and two of wood on
# the right, which at 32px is not a fence, it is lint — and lint that is on one
# side and not the other. The roof above this line keeps the full width, because
# the overhanging eaves are the shape of the thing.
SKIRT_TOP = 40
SKIRT = (4, 28)  # the columns the hut's own body occupies


def tidy_skirt(im):
    px = im.load()
    for y in range(SKIRT_TOP, CELL_H):
        for x in range(CELL_W):
            if not (SKIRT[0] <= x < SKIRT[1]):
                px[x, y] = (0, 0, 0, 0)
    return im


def main():
    src = keep_largest(drop_pockets(key(os.path.join("coop_0"))))
    x0, y0, x1, y1 = content_box(src)
    body = src.crop((x0, y0, x1, y1))
    small = body.resize((round(body.width / SCALE), round(body.height / SCALE)), Image.NEAREST)
    assert small.width <= CELL_W and small.height <= CELL_H, small.size

    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    cell.paste(small, ((CELL_W - small.width) // 2, CELL_H - small.height), small)
    cell = darken_doorway(tidy_skirt(snap(cell)))

    assert cell.size == (CELL_W, CELL_H)
    seen = set()
    for y in range(CELL_H):
        for x in range(CELL_W):
            r, g, b, a = cell.getpixel((x, y))
            assert a in (0, 255), (x, y, a)
            if a:
                seen.add((r, g, b))
    off = seen - set(LOCK_RGB)
    assert not off, "off-lock colours: %s" % sorted(off)
    cell.save(OUT)

    sheet = Image.new("RGBA", (CELL_W * 8, CELL_H * 8), (0, 0, 0, 0))
    sheet.paste(cell.resize((CELL_W * 8, CELL_H * 8), Image.NEAREST))
    sheet.save(os.path.join(HERE, "contact_sheet.png"))
    print("wrote %s (%dx%d, %d colours)" % (OUT, CELL_W, CELL_H, len(seen)))


if __name__ == "__main__":
    main()

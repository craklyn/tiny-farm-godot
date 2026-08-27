#!/usr/bin/env python3
"""Generate assets/sprites/generated/terrain_dirt.png — the tilled/watered autotile.

Why this exists: the previous sheet mapped 256 neighbour masks onto 13 tiles, so 35 of
the 47 reachable configurations drew edges that did not match their neighbours (visible
seams along tilled plots). This generates one tile per mask instead, so the lookup is the
identity `Vector2i(mask % 16, mask / 16)` and cannot drift out of sync with the renderer.

Layout: 32x16 cells of 16px = 512x256.
  columns  0-15 : tilled,  cell (mask % 16, mask / 16)
  columns 16-31 : watered, same cell + 16 columns

Neighbour bits (must match world/autotile.gd):
  N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128
A corner bit is only meaningful when both of its adjacent sides are set; the renderer
gates them that way, so unreachable combinations are generated but never sampled.

Usage: python3 tools/gen_terrain_autotile.py [--check]
"""
import sys

from PIL import Image

TILE = 16
N, NE, E, SE, S, SW, W, NW = 1, 2, 4, 8, 16, 32, 64, 128

# Soil ramps (docs/design/09 art direction). Watered is deliberately far darker and
# cooler than tilled so "is this tile watered?" is answerable at a glance on a tablet.
TILLED = [(0xE8, 0xCF, 0xA6), (0xDC, 0xB9, 0x8A), (0xC9, 0xA0, 0x6B), (0xED, 0xDA, 0xB5)]
WATERED = [(0x8A, 0x6A, 0x52), (0x77, 0x5A, 0x45), (0x63, 0x4A, 0x39), (0x9C, 0x7C, 0x60)]


def base_tile(ramp, seed):
    """A small deterministic dirt texture: base with scattered mid/highlight speckle."""
    im = Image.new("RGBA", (TILE, TILE), ramp[0] + (255,))
    px = im.load()
    state = seed
    for y in range(TILE):
        for x in range(TILE):
            state = (1103515245 * state + 12345) & 0x7FFFFFFF
            r = state % 100
            if r < 14:
                px[x, y] = ramp[1] + (255,)
            elif r < 20:
                px[x, y] = ramp[2] + (255,)
            elif r < 24:
                px[x, y] = ramp[3] + (255,)
    # furrow rows read as tilled soil rather than plain dirt
    for y in range(2, TILE, 5):
        for x in range(TILE):
            px[x, y] = ramp[2] + (255,)
    return im


def shade(color, factor):
    return tuple(min(255, int(c * factor)) for c in color[:3]) + (255,)


def render(tile, mask):
    """Apply edge treatment for one neighbour mask: darker rim on open sides, rounded
    outer corners, notched inner corners."""
    t = tile.copy()
    px = t.load()
    last = TILE - 1
    body = px[TILE // 2, TILE // 2]
    edge = shade(body, 0.60)
    lip = shade(body, 1.16)

    if not mask & N:
        for x in range(TILE):
            px[x, 0] = edge
            px[x, 1] = lip
    if not mask & S:
        for x in range(TILE):
            px[x, last] = edge
    if not mask & W:
        for y in range(TILE):
            px[0, y] = edge
    if not mask & E:
        for y in range(TILE):
            px[last, y] = edge

    # Outer corners: both sides open -> clip the pixel so the plot reads rounded.
    for cx, cy, a, b in ((0, 0, mask & N, mask & W), (last, 0, mask & N, mask & E),
                         (0, last, mask & S, mask & W), (last, last, mask & S, mask & E)):
        if not a and not b:
            px[cx, cy] = (0, 0, 0, 0)
            px[1 if cx == 0 else last - 1, cy] = edge
            px[cx, 1 if cy == 0 else last - 1] = edge

    # Inner corners: both sides present but the diagonal is not -> notch it.
    if mask & N and mask & E and not mask & NE:
        px[last, 0] = edge
    if mask & S and mask & E and not mask & SE:
        px[last, last] = edge
    if mask & S and mask & W and not mask & SW:
        px[0, last] = edge
    if mask & N and mask & W and not mask & NW:
        px[0, 0] = edge
    return t


def build():
    sheet = Image.new("RGBA", (32 * TILE, 16 * TILE), (0, 0, 0, 0))
    tilled, watered = base_tile(TILLED, 7), base_tile(WATERED, 7)
    for mask in range(256):
        cx, cy = mask % 16, mask // 16
        sheet.alpha_composite(render(tilled, mask), (cx * TILE, cy * TILE))
        sheet.alpha_composite(render(watered, mask), ((cx + 16) * TILE, cy * TILE))
    return sheet


def check(sheet):
    """Every mask's rendered edges must agree with its bits — the invariant the old
    13-tile table broke."""
    px = sheet.load()
    failures = []
    for mask in range(256):
        for wet in (0, 1):
            ox, oy = (mask % 16 + 16 * wet) * TILE, (mask // 16) * TILE
            body = px[ox + TILE // 2, oy + TILE // 2]
            edge = shade(body, 0.60)
            # sample mid-edge pixels, away from corners
            probes = {
                "N": (px[ox + TILE // 2, oy], not mask & N),
                "S": (px[ox + TILE // 2, oy + TILE - 1], not mask & S),
                "W": (px[ox, oy + TILE // 2], not mask & W),
                "E": (px[ox + TILE - 1, oy + TILE // 2], not mask & E),
            }
            for side, (got, want_edge) in probes.items():
                is_edge = got == edge
                if is_edge != want_edge:
                    failures.append((mask, wet, side, want_edge, got))
    return failures


def contrast(sheet):
    px = sheet.load()
    def lum(x, y):
        r, g, b, _ = px[x, y]
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    t = lum(8, 8)
    w = lum(16 * TILE + 8, 8)
    return t, w, (t + 0.05) / (w + 0.05)


if __name__ == "__main__":
    sheet = build()
    fails = check(sheet)
    t, w, ratio = contrast(sheet)
    print(f"tilled luminance {t:.1f}  watered {w:.1f}  contrast ratio {ratio:.2f}:1")
    if fails:
        print(f"FAIL: {len(fails)} edge mismatches, e.g. {fails[:3]}")
        sys.exit(1)
    print("OK: all 256 masks x 2 variants have edges matching their bits")
    if "--check" not in sys.argv:
        out = "assets/sprites/generated/terrain_dirt.png"
        sheet.save(out)
        print("wrote", out, sheet.size)

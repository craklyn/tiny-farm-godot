#!/usr/bin/env python3
"""Derive the worm's elbow — the corner cell his bends never had.

**Not generated, $0.00.** Since the M2.5 art bench the worm's bends have drawn
the vertical-body cell as a knuckle (worm.gd carried the IOU in its header:
"a dedicated corner cell is still one more cell whenever the art bench comes
back"). At 16px on a farm that read as acceptable; in HQ's sprite editor,
zoomed, a bend is visibly two disconnected runs with a gap where the corner
should be. The CEO called it (2026-09-07): "turning a corner looks weird".

So the elbow is derived, in the droplet-and-basket tradition: a quarter-turn
tube joining the horizontal body's left opening (rows 6-13) to the vertical
body's bottom opening (cols 4-11), swept about C=(0,17) at centerline radius
7.5, half-width 4. The radial shading mirrors the horizontal body's own slice,
read from the sheet rather than typed here — outline, rose shadow x2, pink x3,
cream highlight, outline — with the highlight on the outer curve, where the
body art keeps its light.

The base cell opens LEFT and DOWN; worm.gd rotates it for the other three
bend orientations. Written as cell 4 of worm.png (widening 64x16 to 80x16).

Idempotent: run it as often as you like. Costs nothing and needs no network.

    python3 tools/gen_worm_elbow.py
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "..", "assets", "sprites", "generated", "worm.png")

CELL = 16
BODY_COL = 1      # the horizontal body, whose slice the shading mirrors
ELBOW_COL = 4
C = (0.0, 17.0)   # center of the sweep, just past the bottom-left corner
R = 7.5           # centerline radius
HALF = 4          # tube half-width


def body_slice(sheet):
    """The horizontal body's vertical cross-section colors, top to bottom."""
    xs = 4  # a plain (unringed) slice of the body cell
    col = []
    for y in range(CELL):
        p = sheet.getpixel((BODY_COL * CELL + xs, y))
        if p[3] > 0:
            col.append(p)
    return col


def main() -> int:
    sheet = Image.open(os.path.normpath(SHEET)).convert("RGBA")
    slice_colors = body_slice(sheet)
    if len(slice_colors) != 2 * HALF:
        print("body slice is %d px, expected %d — sheet changed shape, refusing to guess"
              % (len(slice_colors), 2 * HALF))
        return 1
    # Inner edge of the curve is the body's bottom (shadow side), outer its top.
    bands = list(reversed(slice_colors))

    if sheet.width < (ELBOW_COL + 1) * CELL:
        wider = Image.new("RGBA", ((ELBOW_COL + 1) * CELL, sheet.height), (0, 0, 0, 0))
        wider.paste(sheet, (0, 0))
        sheet = wider

    for y in range(CELL):
        for x in range(CELL):
            r = math.hypot(x + 0.5 - C[0], y + 0.5 - C[1])
            b = r - (R - HALF)
            sheet.putpixel((ELBOW_COL * CELL + x, y),
                           bands[int(b)] if 0 <= b < 2 * HALF else (0, 0, 0, 0))

    sheet.save(os.path.normpath(SHEET))
    print("wrote %s (%dx%d), cell %d = the elbow"
          % (os.path.normpath(SHEET), sheet.width, sheet.height, ELBOW_COL))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

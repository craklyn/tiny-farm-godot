#!/usr/bin/env python3
"""Derive the turned-down cot cell from the made one (T-27 box 5, treatment C).

Not generated. `objects.png` cell 0 is the cot as the Retro Diffusion run of
2026-08-31 left it; cell 7 is that same cell with its blanket pulled down, edited
here from the cell's own nine colours. This is the house pattern for a second
state of one object — the sprinkler's idle frame is its spraying frame with the
droplets dropped, and the worm's body is one repeated cross-section of the worm's
own ramp (CREDITS.md, M2.5 art bench) — and the reason is that two cells swapped
at a threshold must not drift: a generated second bed would have its posts and
pillows in slightly different places and the swap would pop.

The edit, in the cot's own vocabulary: the blanket's rust trim sat at row 11,
right under the pillows. It moves to rows 16-17, and the five rows it vacates
become the cream sheet that was already showing above it. Nothing outside
x=2..12 is touched, so the frame, posts, pillows, teal hem and feet are the
originals, pixel for pixel.

Idempotent: run it as often as you like. Costs nothing and needs no network.

    python3 tools/gen_cot_turndown.py
"""
import os
import sys

from PIL import Image

SHEET = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "generated", "objects.png")
SRC_COL = 0          # the made bed
DST_COL = 7          # the turned-down bed
CELL_W, CELL_H = 16, 32

CREAM = (248, 244, 230, 255)   # the sheet
RUST = (200, 78, 57, 255)      # the blanket's trim

SHEET_ROWS = range(11, 16)     # blanket pulled back off these
TRIM_ROWS = range(16, 18)      # where its trim now lies
INTERIOR = range(2, 13)        # never touch the frame, posts or rails


def main() -> int:
    path = os.path.normpath(SHEET)
    sheet = Image.open(path).convert("RGBA")
    w, h = sheet.size

    need = (DST_COL + 1) * CELL_W
    if w < need:
        wider = Image.new("RGBA", (need, h), (0, 0, 0, 0))
        wider.paste(sheet, (0, 0))
        sheet = wider
        w = need

    cell = sheet.crop((SRC_COL * CELL_W, 0, SRC_COL * CELL_W + CELL_W, CELL_H)).copy()
    px = cell.load()
    for y in SHEET_ROWS:
        for x in INTERIOR:
            px[x, y] = CREAM
    for y in TRIM_ROWS:
        for x in INTERIOR:
            px[x, y] = RUST

    sheet.paste(cell, (DST_COL * CELL_W, 0))

    # Palette lock: the new cell may introduce no colour the sheet did not already
    # have, and alpha stays binary (the shipped-sheet rule, CREDITS.md).
    before = {p for p in Image.open(path).convert("RGBA").getdata()}
    after = {p for p in sheet.getdata()}
    new = after - before
    if new:
        print("refusing to write: new colours %s" % sorted(new), file=sys.stderr)
        return 1
    if any(p[3] not in (0, 255) for p in after):
        print("refusing to write: non-binary alpha", file=sys.stderr)
        return 1

    sheet.save(path)
    print("wrote %s (%dx%d), cell %d = the cot, turned down" % (path, w, h, DST_COL))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

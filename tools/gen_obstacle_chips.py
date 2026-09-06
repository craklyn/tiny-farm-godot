#!/usr/bin/env python3
"""Derive the chip stages a multi-beat clear shrinks an obstacle through.

**Not generated, $0.00.** Q-50 made clearing read as exertion — a log is two
chops, a rock or tree three — but the sim clears the tile at the tap, so the
obstacle vanished on the first swing and the farmer mimed the rest at bare
ground. The CEO asked (2026-09-07) for the obstacle to visibly reduce with
each impact, so the beats explain themselves.

The stages are derived from the obstacles' own cells: each damage stage is the
base cell k-centroid-shrunk and re-seated on the ground (a rock at three
quarters, then half, reads instantly as "being reduced" at 16px), in the same
derive-don't-generate tradition as the glyphs and the critters. Appended to
obstacles.png as cells 8-12:

    8  rock, first chip     9  rock, second chip
    10 log, first chip
    11 tree, first chip     12 tree, second chip

Idempotent: stages are recomputed from the base cells every run.

    python3 tools/gen_obstacle_chips.py
"""
import os

from rederive_critters import k_centroid, trim

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "..", "assets", "sprites", "generated", "obstacles.png")
CELL = 16

# (source cell, target cell, fraction of the base subject's size)
STAGES = [
    (0, 8, 0.75), (0, 9, 0.5),    # rock
    (1, 10, 0.68),                # log
    (3, 11, 0.75), (3, 12, 0.5),  # tree
]


def main() -> int:
    sheet = Image.open(os.path.normpath(SHEET)).convert("RGBA")
    cells_needed = max(dst for _, dst, _ in STAGES) + 1
    if sheet.width < cells_needed * CELL:
        wider = Image.new("RGBA", (cells_needed * CELL, sheet.height), (0, 0, 0, 0))
        wider.paste(sheet, (0, 0))
        sheet = wider
    for src, dst, frac in STAGES:
        base = trim(sheet.crop((src * CELL, 0, (src + 1) * CELL, CELL)))
        tw = max(2, round(base.width * frac))
        th = max(2, round(base.height * frac))
        small = trim(k_centroid(base, tw, th))
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        cell.paste(small, ((CELL - small.width) // 2, CELL - small.height), small)
        sheet.paste(cell, (dst * CELL, 0))
    sheet.save(os.path.normpath(SHEET))
    print("wrote %s (%dx%d): chip stages in cells 8-12"
          % (os.path.normpath(SHEET), sheet.width, sheet.height))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

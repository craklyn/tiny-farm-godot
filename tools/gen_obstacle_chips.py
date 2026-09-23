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
derive-don't-generate tradition as the glyphs and the critters. Each stage sits
beside its base cell on the matching per-thing sheet:

    obstacle_rock.png: 1 first chip, 2 second chip
    obstacle_log.png:  1 first chip
    obstacle_tree.png: 1 first chip, 2 second chip

Idempotent: stages are recomputed from the base cells every run.

    python3 tools/gen_obstacle_chips.py
"""
import os

from rederive_critters import k_centroid, trim

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(HERE, "..", "assets", "sprites", "generated")
CELL = 16

# (target cell, fraction of the base subject's size)
STAGES = {
    "obstacle_rock.png": [(1, 0.75), (2, 0.5)],
    "obstacle_log.png": [(1, 0.68)],
    "obstacle_tree.png": [(1, 0.75), (2, 0.5)],
}


def main() -> int:
    for name, stages in STAGES.items():
        path = os.path.normpath(os.path.join(SPRITES, name))
        sheet = Image.open(path).convert("RGBA")
        cells_needed = max(dst for dst, _ in stages) + 1
        if sheet.width < cells_needed * CELL:
            wider = Image.new("RGBA", (cells_needed * CELL, sheet.height), (0, 0, 0, 0))
            wider.paste(sheet, (0, 0))
            sheet = wider
        base = trim(sheet.crop((0, 0, CELL, CELL)))
        for dst, frac in stages:
            tw = max(2, round(base.width * frac))
            th = max(2, round(base.height * frac))
            small = trim(k_centroid(base, tw, th))
            cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
            cell.paste(small, ((CELL - small.width) // 2, CELL - small.height), small)
            sheet.paste(cell, (dst * CELL, 0))
        sheet.save(path)
        print("wrote %s (%dx%d): chip stages" % (path, sheet.width, sheet.height))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

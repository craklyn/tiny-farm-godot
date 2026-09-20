#!/usr/bin/env python3
"""Draw the stripped stage of each crop — what a bird leaves standing (Q-110 b).

    python3 tools/gen_stripped_crops.py

Writes assets/sprites/generated/<crop>_stripped.png, one 16px cell each, beside
the crop's own four-stage sheet.

The designer ruled on 2026-09-19 that a square a bird emptied keeps a bitten
stalk on it rather than going to bare earth, so the loss reads as a loss and the
square says which plant was taken. That means one stripped stage per crop, and
they are drawn here rather than generated: each is built out of its own crop
sheet's exact colours, because the whole point is that the square still looks
like the plant that was standing on it. A generated one matched no crop in the
game — both attempts came back as a plant standing in a pool of red (the raws
are archived at assets/raw/2026-09-19-ransack-mark/ as the reference they became).

**The pictures are the grids below and nothing else.** Edit a grid, run this, and
the game draws what you typed; there is no processing in between to reason about.
Each letter is a key into that crop's PALETTE, and every colour in every palette
is lifted from the crop's own shipped sheet, so a stripped tomato is made of
tomato pixels.

What they have in common is what makes a raided square readable at a glance: a
stalk bent over and broken off where the head or the fruit was, one or two torn
leaf stubs still clinging to it, and a little debris on the ground at its base.
Each keeps its own crop's base tuft exactly where that crop's sheet puts it, so
the stripped plant stands in the same footprint the living one did.
"""

import os

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "sprites", "generated")

# Every colour here appears in that crop's own sheet. Keep it that way: a
# stripped plant in a colour the crop never had reads as a different object.
CROPS = {
    # Tomato — the one the designer picked from, unchanged since he saw it. The
    # fruit is gone and one scrap of its skin is on the ground (D/F, the sheet's
    # two reds), which is the only thing that says tomato once the fruit is off.
    "tomato": {
        "palette": {"A": "#78a158", "B": "#a3c263", "C": "#4e6e3a",
                    "D": "#c84e39", "E": "#8db15d", "F": "#9b3527"},
        "rows": [
            "................",
            "................",
            "................",
            "..........CCC...",
            ".........CCA.C..",
            "........CC...C..",
            ".......CCA......",
            ".....BCCC.......",
            ".......CCA......",
            ".......CCBB.....",
            ".......CCA.C....",
            ".......CC.......",
            "......CCCA......",
            ".....BCCC.......",
            "..B...CCCA..B...",
            "..EB.BBECBB.FD..",
        ],
    },
    # Wheat — the head is what a bird comes for, so the stalk is headless and a
    # few loose grains (B/D, the sheet's golds) lie where it was shaken out. The
    # gold base tuft is the shipped sheet's own, cell for cell.
    "wheat": {
        "palette": {"B": "#e9e178", "C": "#4e6e3a", "D": "#cca13c",
                    "G": "#a3c263", "H": "#78a158"},
        "rows": [
            "................",
            "................",
            "................",
            "..........CCC...",
            ".........CCH.C..",
            "........CC...C..",
            ".......CCH......",
            ".....GCCC.......",
            ".......CCH......",
            ".......CCGG.....",
            ".......CCH.C....",
            ".......CC.......",
            "......CCCH......",
            ".....GCCC.......",
            "..B...CCCH..D...",
            "..D..DDCDD.BD...",
        ],
    },
    # Pea — a climber, so what is left is the curled tendril it was holding on
    # with, and the pods are gone. Nothing red: a pea's own scraps are green.
    "pea": {
        "palette": {"A": "#78a158", "B": "#a3c263", "C": "#4e6e3a",
                    "E": "#8db15d"},
        "rows": [
            "................",
            "................",
            ".........CC.....",
            "........CC.CC...",
            ".......CCA.C.C..",
            ".......CC...CC..",
            ".......CCA......",
            ".....BCCC.......",
            ".......CCA......",
            ".......CCBB.....",
            ".......CCA.C....",
            ".......CC.......",
            "......CCCA......",
            ".....BCCC.......",
            "..B...CCCA..B...",
            "..EB.BBECBB.EB..",
        ],
    },
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def build(spec):
    palette = {k: rgb(v) + (255,) for k, v in spec["palette"].items()}
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = im.load()
    for y, row in enumerate(spec["rows"]):
        if len(row) != 16:
            raise SystemExit(f"row {y} is {len(row)} cells wide, not 16: {row!r}")
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            if ch not in palette:
                raise SystemExit(f"row {y} uses '{ch}', which is not in the palette")
            px[x, y] = palette[ch]
    return im


def main():
    for crop, spec in CROPS.items():
        path = os.path.join(OUT, f"{crop}_stripped.png")
        build(spec).save(path)
        print(f"drew -> {os.path.relpath(path, REPO)}")


if __name__ == "__main__":
    main()

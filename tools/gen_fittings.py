#!/usr/bin/env python3
"""Draw the two room fittings (S-22) from colours the game already ships.

    python3 tools/gen_fittings.py

Writes assets/sprites/generated/nest_box.png and rug.png, 16x16 each: one room
cell, the size every room's floor is drawn at. No model is called. The pixels are
the two maps below, which are the editable source: change a letter, re-run.

Every colour is one a shipped sheet already uses — the nest box takes the chicken
coop's wood and the bed's pale straw, the rug the bed's reds and creams — and the
script refuses to write if a map names a colour missing from its source sheets,
so the fittings cannot drift off the palette they sit beside.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "assets" / "sprites" / "generated"

# A low wooden box full of straw, seen from the front and a little above.
NEST_BOX = [
    "................",
    "................",
    "................",
    "................",
    "....s..h...s....",
    "..DDhsShhSshDD..",
    ".DshShhssShhsSD.",
    ".DhSshSShhsSShD.",
    ".DDDDDDDDDDDDDD.",
    ".DLLLDLLLLDLLLD.",
    ".DMMMDMMMMDMMMD.",
    ".DLLLDLLLLDLLLD.",
    ".DMMMDMMMMDMMMD.",
    ".DDDDDDDDDDDDDD.",
    "..D..........D..",
    "................",
]
NEST_BOX_KEY = {
    "D": (111, 74, 69),    # the coop's darkest wood: outline and plank seams
    "M": (144, 98, 93),    # its mid wood
    "L": (169, 121, 89),   # its light wood
    "S": (195, 154, 108),  # its straw-coloured boards: the straw's body
    "s": (169, 121, 89),   # straw in shadow
    "h": (232, 207, 166),  # the bed's pale straw tone (cot.png), as lit straw
}

# A small woven rug with a fringe at each end, lying flat on the floorboards.
RUG = [
    "................",
    "................",
    "................",
    "................",
    ".RRRRRRRRRRRRRR.",
    "WRPPPPPPPPPPPPRW",
    ".RPCCCCCCCCCCPR.",
    "WRPCPPPRRPPPCPRW",
    ".RPCPPRPPRPPCPR.",
    "WRPCPPPRRPPPCPRW",
    ".RPCCCCCCCCCCPR.",
    "WRPPPPPPPPPPPPRW",
    ".RRRRRRRRRRRRRR.",
    "..DDDDDDDDDDDD..",
    "................",
    "................",
]
RUG_KEY = {
    "R": (200, 78, 57),    # the bed's red trim
    "P": (217, 154, 154),  # its pink blanket
    "C": (248, 244, 230),  # its cream sheet
    "W": (248, 244, 230),  # the fringe, the same cream
    "D": (144, 98, 93),    # its brown frame, as the rug's shadow edge
}


def draw(rows, key, sources):
    shipped = set()
    for source in sources:
        sheet = Image.open(SPRITES / source).convert("RGBA")
        w, h = sheet.size
        for y in range(h):
            for x in range(w):
                px = sheet.getpixel((x, y))
                if px[3] > 0:
                    shipped.add(px[:3])
    missing = {name: rgb for name, rgb in key.items() if rgb not in shipped}
    if missing:
        raise SystemExit(f"{sources} do not use {missing}; refusing to leave their palette")
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    assert len(rows) == 16
    for y, row in enumerate(rows):
        row = row.ljust(16, ".")
        assert len(row) == 16, (y, row)
        for x, ch in enumerate(row):
            if ch in key:
                img.putpixel((x, y), key[ch] + (255,))
    return img


def main():
    draw(NEST_BOX, NEST_BOX_KEY, ["chicken_coop.png", "cot.png"]).save(SPRITES / "nest_box.png")
    draw(RUG, RUG_KEY, ["cot.png"]).save(SPRITES / "rug.png")
    print("wrote nest_box.png and rug.png")


if __name__ == "__main__":
    main()

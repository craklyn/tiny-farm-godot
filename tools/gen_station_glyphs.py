#!/usr/bin/env python3
"""Derive T-28's two missing nouns into shop_icons.png, the iconography row.

**No art was generated for T-28.** The stations' drafts need pictures for the
things the player is being told about, and the game already owns most of them:
the coin (shop_icons.png col 3, added for T-12), the watering can and the seed
packet (tool_icons cells 4 and 5, which the refusal table already uses — see
`world/farm.gd` REFUSE_ICONS). Two nouns had no picture anywhere:

  * **water itself** — a droplet. The can is *her tool*; the droplet is the
    *state of the tile*, and "this crop already has its water" is a sentence
    about the tile. Drawn in the watering can's own four colours, lifted from
    tool_icons cell 4, so the can and the water it carries read as one family.
  * **an empty basket** — what she is holding when the shipping bin has nothing
    to take. Drawn in the shipping bin's own three wood colours, lifted from
    shipping_bin.png, for the same reason: the bin and the basket you
    bring to it must not look like they come from different games.

Both land in **shop_icons.png**, which is the shop's iconography row by
existing convention ("wheat packet, tomato packet, scarecrow, and a coin" —
`ui/menus.gd`). Columns 4 and 5 were empty; they are now the droplet and the
basket. No sheet grows, no new import is created, and nothing that was already
drawn moves by a pixel.

Idempotent: run it as often as you like. Costs nothing and needs no network.

    python3 tools/gen_station_glyphs.py [--preview]
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "..", "assets", "sprites", "generated", "shop_icons.png")
CAN_SHEET = os.path.join(HERE, "..", "assets", "sprites", "tool_icons.png")
BIN_SHEET = os.path.join(HERE, "..", "assets", "sprites", "generated", "shipping_bin.png")

CELL = 16
ICON_ROW = 0      # shop_icons.png is one row
DROPLET_COL = 4
BASKET_COL = 5

CLEAR = (0, 0, 0, 0)


def palette_of(path, col, row, cell_w=CELL, cell_h=CELL):
    """Every distinct opaque colour in one cell, most-used first.

    The point of reading them rather than typing them is that a re-generated
    sheet cannot silently leave these glyphs behind in last month's colours.
    """
    im = Image.open(path).convert("RGBA")
    cell = im.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
    counts = {}
    for p in cell.getdata():
        if p[3] > 40:
            counts[p] = counts.get(p, 0) + 1
    return [c for c, _ in sorted(counts.items(), key=lambda kv: -kv[1])]


def sort_by_luma(colours):
    return sorted(colours, key=lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])


# --- the droplet -------------------------------------------------------------
#
# A teardrop is an exact shape, so it is described rather than hand-plotted: a
# disc of radius R centred at (CX, CY), and above it a cone narrowing to a point
# at (CX, TOP). Every pixel whose centre is inside gets ink; the outermost ring
# of those gets the dark colour. That keeps the silhouette symmetrical, which a
# hand-plotted 16px teardrop almost never is.
D_CX, D_CY, D_R, D_TOP, D_TAPER = 7.5, 9.6, 4.5, 2.0, 0.8


def _in_droplet(x, y):
    px, py = x + 0.5, y + 0.5
    if py >= D_CY:
        return (px - D_CX) ** 2 + (py - D_CY) ** 2 <= D_R * D_R
    if py < D_TOP:
        return False
    half = D_R * ((py - D_TOP) / (D_CY - D_TOP)) ** D_TAPER
    return abs(px - D_CX) <= half


def droplet_cell(can_palette):
    dark, mid, light, cream = sort_by_luma(can_palette)[:4]
    img = Image.new("RGBA", (CELL, CELL), CLEAR)
    solid = [[_in_droplet(x, y) for x in range(CELL)] for y in range(CELL)]
    for y in range(CELL):
        for x in range(CELL):
            if not solid[y][x]:
                continue
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < CELL and 0 <= ny < CELL) or not solid[ny][nx]:
                    edge = True
            img.putpixel((x, y), dark if edge else mid)
    # The shine: water is the only thing in this game that is allowed to look
    # wet, and a droplet without a highlight reads as a leaf.
    for x, y in ((5, 8), (6, 8), (5, 9), (6, 9), (5, 10), (6, 10)):
        if solid[y][x]:
            img.putpixel((x, y), light)
    for x, y in ((5, 8), (5, 9)):
        if solid[y][x]:
            img.putpixel((x, y), cream)
    return img


# --- the empty basket --------------------------------------------------------
#
# Plotted rather than described, because a basket is a made object and its weave
# is the whole picture. Read it as a picture: `.` empty, `d` dark (rim, shadow,
# the mouth she can see is empty), `m` mid, `l` light (the lit face of the weave).
#
# Row 6 is the load-bearing one: it is the mouth, in the darkest wood, and it is
# what makes this an *empty* basket rather than merely a basket. You are looking
# into it, and there is nothing in there.
BASKET = [
    "................",
    ".....dddddd.....",
    "....dd....dd....",
    "....d......d....",
    "....d......d....",
    "..dlllllllllld..",
    "..dddddddddddd..",
    "..dlmlmlmlmlmd..",
    "..dmlmlmlmlmld..",
    "...dlmlmlmlmd...",
    "...dmlmlmlmld...",
    "....dlmlmlmd....",
    "....dmlmlmld....",
    "....dddddddd....",
    "................",
    "................",
]


def basket_cell(bin_palette):
    dark, mid, light = sort_by_luma(bin_palette)[:3]
    ink = {"d": dark, "m": mid, "l": light}
    for row in BASKET:
        assert len(row) == CELL, "basket row is not %d wide: %r" % (CELL, row)
    img = Image.new("RGBA", (CELL, CELL), CLEAR)
    for y, row in enumerate(BASKET):
        for x, ch in enumerate(row):
            if ch in ink:
                img.putpixel((x, y), ink[ch])
    return img


def preview(img, title):
    print("===", title, "===")
    keys = {}
    for y in range(img.height):
        line = ""
        for x in range(img.width):
            p = img.getpixel((x, y))
            if p[3] < 40:
                line += "."
            else:
                if p not in keys:
                    keys[p] = "0123456789abcdef"[len(keys)]
                line += keys[p]
        print(line)
    for k, v in keys.items():
        print(" ", v, k)


def main():
    can = palette_of(CAN_SHEET, 4, 0)
    wood = palette_of(BIN_SHEET, 0, 0)
    if len(can) < 4 or len(wood) < 3:
        print("source cells lost their colours — refusing to guess", file=sys.stderr)
        return 1
    # The bin cell carries one teal pixel group from whatever is sitting in it;
    # the basket wants wood only, so the teal family is dropped by hue.
    wood = [c for c in wood if c[0] >= c[2]][:3]

    drop = droplet_cell(can)
    bask = basket_cell(wood)

    if "--preview" in sys.argv:
        preview(drop, "droplet")
        preview(bask, "empty basket")

    sheet = Image.open(SHEET).convert("RGBA")
    for col, cell in ((DROPLET_COL, drop), (BASKET_COL, bask)):
        box = (col * CELL, ICON_ROW * CELL)
        # Paste, do not composite: these cells are ours and are rewritten whole.
        sheet.paste(cell, box)
    sheet.save(SHEET)
    print("wrote %s (%dx%d), row %d cells %d=droplet %d=empty basket"
          % (os.path.normpath(SHEET), sheet.width, sheet.height,
             ICON_ROW, DROPLET_COL, BASKET_COL))
    return 0


if __name__ == "__main__":
    sys.exit(main())

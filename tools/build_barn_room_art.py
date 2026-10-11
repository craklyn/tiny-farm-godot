#!/usr/bin/env python3
"""Build the Industrial Barn's room: 12 by 8 cells of 16 pixels, 192x128, hand drawn.

The first room (design/17, 2026-10-09) was 6 by 4 cells, 96x64 pixels, and held four
stalls, seven cheese stations, pipes and a shelf in that space, so each station got one
16-pixel square and Daniel called it stick drawings (2026-10-11). This one is twice as
wide and twice as deep, drawn as a few large pieces:

    x 0..111  the cow side, west pens and east pens facing a central aisle, a lobby below
    x 112..191  the cheese line, one steel machine for each station, top to bottom

Every pen is three cells wide and two deep (48x32 px), so a cow's 24x20 frame stands in it
with 12 px each side. Cells (x, y) in the room are these pixels /16; the numbers the game
reads (stall cells, door, shelf, blocked cells) are in `systems/machine_defs.gd` and the
pixel marks the animation draws on are in `world/barn_presentation.gd`. The checks at the
bottom of this file hold the two to the picture, so a redraw cannot quietly move a station.

Every opaque pixel is a colour the game already ships (`SHIPPED_PALETTE` is scanned from
`assets/sprites/` when this runs), and every pixel is opaque or fully transparent.

    python3 tools/build_barn_room_art.py            # writes the PNG and previews
    python3 tools/build_barn_room_art.py --check    # builds in memory and runs the checks
"""
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/sprites/generated/industrial_barn_interior_kit.png"
CELL = 16
CELLS = (12, 8)
SIZE = (CELLS[0] * CELL, CELLS[1] * CELL)

HEX = {
    # steel and tile, dark to light
    "ink": "2f2b3d", "ink2": "3f3f4d", "s1": "565564", "s2": "72727b", "s3": "8d8e92",
    "s4": "a5a6a7", "s5": "bdbfbe", "s6": "e0d9c4", "s7": "f3efe3", "cream": "f8f4e6",
    # wood
    "w0": "523f31", "w1": "634a39", "w2": "775a45", "w3": "8a6a52", "w4": "a97959",
    "w5": "c39a6c", "w6": "bd936a",
    # straw, tile and warm masonry
    "t0": "8b7c63", "t1": "c9a06b", "t2": "dcb98a", "t3": "e8cfa6", "t4": "eddab5",
    "t5": "fff0c0",
    # the barn's red
    "r0": "94371f", "r1": "c84e39",
    # product: curds, cheese and the coiled hoses
    "c0": "997a2e", "c1": "cca13c", "c2": "f0cf5a", "c3": "e9e178",
}
RGB = {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) for k, v in HEX.items()}
PRODUCT = {RGB[k] for k in ("c0", "c1", "c2", "c3")}


class Canvas:
    def __init__(self, w, h):
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.im.load()
        self.width, self.height = w, h

    def p(self, x, y, c):
        if 0 <= x < self.width and 0 <= y < self.height:
            self.px[x, y] = RGB[c] + (255,)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.p(x, y, c)

    def h(self, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            self.p(x, y, c)

    def v(self, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            self.p(x, y, c)

    def box(self, x0, y0, x1, y1, c):
        self.h(x0, x1, y0, c)
        self.h(x0, x1, y1, c)
        self.v(x0, y0, y1, c)
        self.v(x1, y0, y1, c)

    def get(self, x, y):
        return self.px[x, y][:3]


def noise(x, y, salt=0):
    """A fixed pseudo-random value in 0..99 for a pixel, so a rebuild never moves a fleck."""
    n = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
    n = (n ^ (n >> 13)) * 1274126177
    return (n ^ (n >> 16)) % 100


# --- floors ----------------------------------------------------------------------------

def straw_blocks(c, x0, y0, x1, y1):
    """The cow side's aisle and lobby: straw-coloured floor blocks, laid in running bond."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            row = (y - y0) // 8
            seam_y = (y - y0) % 8 == 7
            seam_x = (x - x0 + (8 if row % 2 else 0)) % 16 == 15
            if seam_y or seam_x:
                c.p(x, y, "t2")
            else:
                r = noise(x, y, 1)
                c.p(x, y, "t4" if r < 4 else "t3")
            if (y - y0) % 8 == 0 and not seam_x:
                c.p(x, y, "t4")


def loose_straw(c, x0, y0, x1, y1):
    """A pen's bedding: darker than the aisle so the cow stands out, with strands of straw."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            r = noise(x, y, 2)
            c.p(x, y, "t2")
            if r < 10:
                c.p(x, y, "t1")
            elif r > 92:
                c.p(x, y, "t3")
    # a few two-pixel strands, laid along the pen
    for i in range(((x1 - x0 + 1) * (y1 - y0 + 1)) // 28):
        sx = x0 + noise(i, 7, 3) * (x1 - x0 - 2) // 100
        sy = y0 + noise(i, 11, 3) * (y1 - y0) // 100
        c.p(sx, sy, "t3")
        c.p(sx + 1, sy, "t3")
        c.p(sx + 2, sy + 1, "t1")


def steel_tiles(c, x0, y0, x1, y1):
    """The cheese side's floor: white tile, grey grout, one small chip in a few tiles."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            gx = (x - x0) % 16 == 15
            gy = (y - y0) % 16 == 15
            c.p(x, y, "s5" if (gx or gy) else "s7")
            if not (gx or gy) and (x - x0) % 16 == 0 and (y - y0) % 16 == 0:
                c.p(x, y, "cream")
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if c.get(x, y) == RGB["s7"] and noise(x, y, 4) < 3:
                c.p(x, y, "s6")


# --- the cow side -----------------------------------------------------------------------

def pen(c, x0, y0, west):
    """One pen: 48x32 px, open on the aisle side, feed trough on the far wall.

    `west` pens open east (the trough is on their west wall), east pens open west.
    A cow's 24x20 frame stands in the middle cell of the row below the back board and has
    12 px of straw each side of her.
    """
    x1, y1 = x0 + 47, y0 + 31
    loose_straw(c, x0, y0, x1, y1)
    # back board along the north: dark timber with a lit top edge
    c.rect(x0, y0, x1, y0 + 3, "w2")
    c.h(x0, x1, y0, "w5")
    c.h(x0, x1, y0 + 1, "w4")
    c.h(x0, x1, y0 + 3, "w1")
    for bx in range(x0 + 7, x1, 12):
        c.v(bx, y0 + 1, y0 + 2, "w1")
    # front sill along the south: a low board the pens share
    c.rect(x0, y1 + 1, x1, y1 + 3, "w3")
    c.h(x0, x1, y1 + 1, "w5")
    c.h(x0, x1, y1 + 3, "w1")
    # the feed trough against the far wall: a wooden box heaped with hay
    tx0 = x0 + 3 if west else x1 - 12
    tx1 = x0 + 12 if west else x1 - 3
    c.rect(tx0, y0 + 6, tx1, y1 - 3, "w4")
    c.box(tx0, y0 + 6, tx1, y1 - 3, "w1")
    c.rect(tx0 + 2, y0 + 8, tx1 - 2, y1 - 5, "t2")
    for yy in range(y0 + 8, y1 - 4, 3):
        c.h(tx0 + 2, tx1 - 2, yy, "t4")
    c.h(tx0 + 3, tx1 - 3, y0 + 9, "c1") if False else None
    # the wall behind the trough: a post and a lit board edge on the aisle-facing side
    ex0 = x1 - 3 if west else x0
    ex1 = x1 if west else x0 + 3
    # posts at the open edge: tall timber, two of them, marking the pen's mouth
    for py0, py1 in ((y0, y0 + 5), (y1 - 3, y1 + 3)):
        c.rect(ex0, py0, ex1, py1, "w3")
        c.v(ex0 if west else ex1, py0, py1, "w1")
        c.v(ex1 if west else ex0, py0, py1, "w5")
        c.h(ex0, ex1, py0, "w5")
    # a dark floor shadow under the back board
    c.h(x0 + 1, x1 - 1, y0 + 4, "t1")


def hay_stack(c, x0, y0):
    """Two bales and one more on top, in straw tones with twine, on the floor blocks."""
    def bale(bx, by, bw, bh):
        c.rect(bx, by, bx + bw - 1, by + bh - 1, "t2")
        c.box(bx, by, bx + bw - 1, by + bh - 1, "w3")
        c.h(bx + 1, bx + bw - 2, by + 1, "t4")
        c.h(bx + 1, bx + bw - 2, by + 2, "t3")
        for sx in range(bx + 3, bx + bw - 2, 4):
            c.v(sx, by + 1, by + bh - 2, "t1")
        # twine
        tw = bx + bw // 3
        c.v(tw, by, by + bh - 1, "w2")
        c.v(bx + 2 * bw // 3, by, by + bh - 1, "w2")
        for yy in range(by + 3, by + bh - 1, 3):
            c.p(bx + 4, yy, "t5")
    bale(x0, y0 + 14, 15, 10)
    bale(x0 + 15, y0 + 14, 15, 10)
    bale(x0 + 7, y0 + 4, 15, 10)


def feed_bin(c, x0, y0):
    c.rect(x0 + 1, y0 + 4, x0 + 30, y0 + 25, "w4")
    c.box(x0 + 1, y0 + 4, x0 + 30, y0 + 25, "w1")
    c.h(x0 + 2, x0 + 29, y0 + 5, "w6")
    c.rect(x0 + 3, y0 + 7, x0 + 28, y0 + 14, "w1")
    c.rect(x0 + 4, y0 + 8, x0 + 27, y0 + 13, "t1")
    for sx in range(x0 + 5, x0 + 27, 3):
        c.p(sx, y0 + 9, "c1")
        c.p(sx + 1, y0 + 11, "c0")
    for yy in (y0 + 17, y0 + 21):
        c.h(x0 + 2, x0 + 29, yy, "w3")
    c.v(x0 + 10, y0 + 15, y0 + 24, "w2")
    c.v(x0 + 21, y0 + 15, y0 + 24, "w2")
    # a bucket beside it
    c.rect(x0 + 33, y0 + 14, x0 + 41, y0 + 25, "s4")
    c.box(x0 + 33, y0 + 14, x0 + 41, y0 + 25, "s1")
    c.h(x0 + 34, x0 + 40, y0 + 15, "s7")
    c.h(x0 + 34, x0 + 40, y0 + 16, "s2")
    c.v(x0 + 36, y0 + 17, y0 + 24, "s5")


def door(c, x0, y0):
    """The livestock doorway at the foot of the central aisle: a dark opening, wide enough
    for a cow, framed in the barn's red timber."""
    c.rect(x0 - 5, y0, x0 + 20, y0 + 15, "ink")
    c.rect(x0 - 6, y0 - 3, x0 + 21, y0, "r0")
    c.h(x0 - 6, x0 + 21, y0 - 3, "r1")
    c.v(x0 - 7, y0 - 3, y0 + 15, "w1")
    c.v(x0 + 22, y0 - 3, y0 + 15, "w1")
    c.v(x0 - 6, y0 - 2, y0 + 15, "w3")
    c.v(x0 + 21, y0 - 2, y0 + 15, "w3")


# --- the cheese side --------------------------------------------------------------------

def shadow(c, x0, x1, y):
    """A two-pixel shadow on the floor tile under a machine, so it sits on the floor."""
    for x in range(x0, x1 + 1):
        if c.get(x, y) in (RGB["s7"], RGB["cream"]):
            c.p(x, y, "s5")
        if c.get(x, y + 1) in (RGB["s7"], RGB["cream"]):
            c.p(x, y + 1, "s6")


def disc(c, cx, cy, r, color):
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + r // 2:
                c.p(x, y, color)


def pipe_h(c, x0, x1, y, thick=3):
    """A steel pipe along a wall: lit top, shaded underside, joint rings."""
    c.rect(x0, y, x1, y + thick - 1, "s4")
    c.h(x0, x1, y, "s7")
    c.h(x0, x1, y + thick - 1, "s2")
    for jx in range(x0 + 6, x1, 24):
        c.v(jx, y, y + thick - 1, "s1")
        c.p(jx + 1, y, "cream")


def pipe_v(c, x, y0, y1, thick=3):
    c.rect(x, y0, x + thick - 1, y1, "s4")
    c.v(x, y0, y1, "s7")
    c.v(x + thick - 1, y0, y1, "s2")
    for jy in range(y0 + 6, y1, 24):
        c.h(x, x + thick - 1, jy, "s1")
        c.p(x, jy + 1, "cream")


def receiver(c, x0, y0):
    """Station 1: a lidded steel vessel, 32x32. The milk pipe drops into its lid."""
    # body: a vertical cylinder lit from the left, shaded in six bands
    bands = ["s6"] * 2 + ["s5"] * 3 + ["s4"] * 5 + ["s3"] * 6 + ["s2"] * 5 + ["s1"] * 3
    for i, x in enumerate(range(x0 + 4, x0 + 28)):
        c.v(x, y0 + 9, y0 + 28, bands[i])
    c.v(x0 + 3, y0 + 10, y0 + 28, "ink2")
    c.v(x0 + 28, y0 + 10, y0 + 28, "ink2")
    c.h(x0 + 4, x0 + 27, y0 + 29, "ink2")
    # two rolled rings round the body
    for ry in (y0 + 11, y0 + 26):
        c.h(x0 + 4, x0 + 27, ry, "s7")
        c.h(x0 + 4, x0 + 27, ry + 1, "s2")
        c.h(x0 + 4, x0 + 27, ry + 2, "s1")
    # the lid: a pale cap with a lit rim, corners clipped
    c.rect(x0 + 4, y0 + 5, x0 + 27, y0 + 9, "s7")
    c.h(x0 + 5, x0 + 26, y0 + 4, "ink2")
    c.v(x0 + 3, y0 + 5, y0 + 9, "ink2")
    c.v(x0 + 28, y0 + 5, y0 + 9, "ink2")
    c.h(x0 + 5, x0 + 26, y0 + 5, "cream")
    c.h(x0 + 4, x0 + 27, y0 + 8, "s5")
    c.h(x0 + 4, x0 + 27, y0 + 9, "s3")
    # the pipe collar on the lid, where the north pipe drops in
    c.rect(x0 + 8, y0 + 1, x0 + 11, y0 + 5, "s4")
    c.v(x0 + 8, y0 + 1, y0 + 5, "s7")
    c.v(x0 + 11, y0 + 1, y0 + 5, "s2")
    c.h(x0 + 7, x0 + 12, y0 + 5, "ink2")
    # a lamp socket on the lid; the arrival light is drawn over it while milk waits
    c.rect(x0 + 21, y0 + 5, x0 + 23, y0 + 6, "ink2")
    # a brass-framed sight glass for the milk inside
    c.rect(x0 + 10, y0 + 14, x0 + 21, y0 + 24, "c1")
    c.box(x0 + 10, y0 + 14, x0 + 21, y0 + 24, "c0")
    c.h(x0 + 11, x0 + 20, y0 + 15, "c3")
    c.rect(x0 + 12, y0 + 16, x0 + 19, y0 + 23, "ink2")
    c.rect(x0 + 13, y0 + 16, x0 + 19, y0 + 23, "s1")
    c.v(x0 + 13, y0 + 16, y0 + 23, "s2")
    # legs
    for lx in (x0 + 6, x0 + 23):
        c.rect(lx, y0 + 29, lx + 2, y0 + 31, "s1")
        c.p(lx, y0 + 29, "s5")


def vat(c, x0, y0):
    """Stations 2-4: the set vat, with the cutter's rail across its back and the rake's rail
    across its front, 48x32. Empty here; the game fills it while a batch is in it."""
    # the steel body
    c.rect(x0, y0 + 3, x0 + 47, y0 + 31, "s3")
    c.box(x0, y0 + 3, x0 + 47, y0 + 31, "ink2")
    # a rolled rim round the open top, lit from the top left
    c.rect(x0 + 1, y0 + 4, x0 + 46, y0 + 7, "s6")
    c.h(x0 + 1, x0 + 46, y0 + 4, "cream")
    c.h(x0 + 1, x0 + 46, y0 + 7, "s4")
    # the front face: a lit band with rivets, a gauge and a drain valve
    c.rect(x0 + 1, y0 + 26, x0 + 46, y0 + 30, "s4")
    c.h(x0 + 1, x0 + 46, y0 + 26, "s6")
    c.h(x0 + 1, x0 + 46, y0 + 30, "s2")
    for rx in range(x0 + 4, x0 + 46, 6):
        if abs(rx - (x0 + 9)) > 4 and abs(rx - (x0 + 23)) > 5:
            c.p(rx, y0 + 28, "s6")
    disc(c, x0 + 9, y0 + 28, 2, "ink2")
    c.rect(x0 + 8, y0 + 27, x0 + 10, y0 + 29, "s7")
    c.p(x0 + 9, y0 + 28, "r1")
    c.rect(x0 + 20, y0 + 27, x0 + 26, y0 + 30, "s1")
    c.rect(x0 + 21, y0 + 28, x0 + 25, y0 + 29, "s4")
    # the open top: a copper inner wall inside the rim, an empty pale basin
    c.rect(x0 + 4, y0 + 8, x0 + 43, y0 + 25, "ink2")
    c.rect(x0 + 5, y0 + 9, x0 + 42, y0 + 24, "t1")
    c.h(x0 + 5, x0 + 42, y0 + 9, "t0")
    c.h(x0 + 5, x0 + 42, y0 + 10, "t0")
    c.rect(x0 + 6, y0 + 11, x0 + 41, y0 + 23, "t3")
    c.rect(x0 + 6, y0 + 11, x0 + 41, y0 + 12, "t2")
    c.h(x0 + 6, x0 + 41, y0 + 23, "t4")
    for sx in range(x0 + 9, x0 + 41, 7):
        c.h(sx, sx + 2, y0 + 16, "t4")
        c.h(sx + 3, sx + 4, y0 + 20, "t4")
    # overhead rails: the cutter's across the back, the rake's across the front
    c.rect(x0 + 2, y0 + 7, x0 + 45, y0 + 8, "ink")
    c.h(x0 + 3, x0 + 44, y0 + 8, "s2")
    c.rect(x0 + 2, y0 + 24, x0 + 45, y0 + 25, "ink")
    c.h(x0 + 3, x0 + 44, y0 + 24, "s2")
    for bx in (x0 + 2, x0 + 44):
        c.rect(bx, y0 + 6, bx + 1, y0 + 9, "s1")
        c.rect(bx, y0 + 23, bx + 1, y0 + 26, "s1")
    # the inlet where the receiver's pipe enters, on the west rim
    c.rect(x0, y0 + 10, x0 + 3, y0 + 13, "s4")
    c.v(x0, y0 + 10, y0 + 13, "s7")
    c.h(x0, x0 + 3, y0 + 13, "s2")


def drain_table(c, x0, y0):
    """Station 5: a steel table that whey drains off, 48x32. Empty here."""
    # legs, each lit on its left edge, with a cross brace
    for lx in (x0 + 3, x0 + 42):
        c.rect(lx, y0 + 22, lx + 2, y0 + 31, "s2")
        c.v(lx, y0 + 22, y0 + 31, "s5")
    c.h(x0 + 5, x0 + 41, y0 + 31, "s2")
    # the whey trough along the foot, with an outlet pipe to the floor on the west
    c.rect(x0 + 2, y0 + 25, x0 + 45, y0 + 29, "s1")
    c.h(x0 + 3, x0 + 44, y0 + 25, "s3")
    c.rect(x0 + 4, y0 + 26, x0 + 43, y0 + 28, "s6")
    c.h(x0 + 4, x0 + 43, y0 + 26, "s5")
    c.rect(x0, y0 + 26, x0 + 2, y0 + 28, "s4")
    # the table top: a slab with a raised rim and long drain slots
    c.rect(x0 + 1, y0 + 4, x0 + 46, y0 + 22, "s4")
    c.box(x0 + 1, y0 + 4, x0 + 46, y0 + 22, "ink2")
    c.h(x0 + 2, x0 + 45, y0 + 5, "s7")
    c.v(x0 + 2, y0 + 5, y0 + 21, "s7")
    c.h(x0 + 2, x0 + 45, y0 + 21, "s2")
    c.v(x0 + 45, y0 + 5, y0 + 21, "s3")
    c.rect(x0 + 4, y0 + 7, x0 + 43, y0 + 19, "s6")
    c.h(x0 + 4, x0 + 43, y0 + 7, "s5")
    c.v(x0 + 4, y0 + 7, y0 + 19, "s5")
    for yy in (y0 + 10, y0 + 13, y0 + 16):
        for xx in range(x0 + 7, x0 + 42, 7):
            c.h(xx, xx + 3, yy, "s4")
    # the turning arm: a hub on a post at the back, and a bar across the slab
    c.rect(x0 + 22, y0 + 1, x0 + 25, y0 + 6, "s2")
    c.rect(x0 + 20, y0 + 1, x0 + 27, y0 + 3, "s5")
    c.box(x0 + 20, y0 + 1, x0 + 27, y0 + 3, "ink2")
    c.h(x0 + 21, x0 + 26, y0 + 2, "cream")


def press_bank(c, x0, y0):
    """Station 6: three presses over forming hoops, hoses coiled above, 48x32. Empty here."""
    c.rect(x0, y0 + 2, x0 + 47, y0 + 31, "s5")
    c.box(x0, y0 + 2, x0 + 47, y0 + 31, "ink2")
    c.rect(x0 + 1, y0 + 3, x0 + 46, y0 + 5, "s7")
    c.h(x0 + 1, x0 + 46, y0 + 3, "cream")
    c.h(x0 + 1, x0 + 46, y0 + 6, "s3")
    c.rect(x0 + 1, y0 + 27, x0 + 46, y0 + 30, "s3")
    c.h(x0 + 1, x0 + 46, y0 + 27, "s6")
    c.h(x0 + 1, x0 + 46, y0 + 30, "s2")
    # the hose rail and the coiled hoses
    c.h(x0 + 2, x0 + 45, y0 + 7, "s1")
    for hx in (x0 + 8, x0 + 24, x0 + 40):
        for k in range(3):
            c.h(hx - 2, hx + 2, y0 + 8 + k * 2, "c1" if k % 2 == 0 else "c2")
            c.p(hx - 3, y0 + 9 + k * 2, "c0")
            c.p(hx + 3, y0 + 9 + k * 2, "c0")
    # three presses: two posts, a head at rest, a ring on a dark well below
    for hx in (x0 + 3, x0 + 19, x0 + 35):
        c.rect(hx, y0 + 16, hx + 9, y0 + 26, "s7")
        c.box(hx, y0 + 16, hx + 9, y0 + 26, "ink2")
        c.rect(hx + 2, y0 + 18, hx + 7, y0 + 24, "ink2")
        c.rect(hx + 3, y0 + 19, hx + 6, y0 + 23, "s1")
        c.v(hx + 1, y0 + 17, y0 + 25, "cream")
        c.rect(hx + 1, y0 + 11, hx + 8, y0 + 14, "s4")
        c.box(hx + 1, y0 + 11, hx + 8, y0 + 14, "ink2")
        c.h(hx + 2, hx + 7, y0 + 12, "s7")
        c.rect(hx + 4, y0 + 8, hx + 5, y0 + 10, "s2")
        c.v(hx, y0 + 8, y0 + 15, "s2")
        c.v(hx + 9, y0 + 8, y0 + 15, "s2")


def outfeed(c, x0, y0):
    """Station 7: a long low belt carrying cheese west toward the shelf, 48x32. Empty here."""
    c.rect(x0, y0 + 12, x0 + 47, y0 + 24, "s3")
    c.box(x0, y0 + 12, x0 + 47, y0 + 24, "ink2")
    c.h(x0 + 1, x0 + 46, y0 + 13, "s7")
    c.rect(x0 + 1, y0 + 14, x0 + 46, y0 + 21, "ink2")
    c.rect(x0 + 1, y0 + 15, x0 + 46, y0 + 20, "s1")
    c.h(x0 + 1, x0 + 46, y0 + 15, "s2")
    for bx in range(x0 + 2, x0 + 46, 4):
        c.v(bx, y0 + 15, y0 + 20, "ink2")
        c.p(bx + 1, y0 + 16, "s2")
    c.h(x0 + 1, x0 + 46, y0 + 22, "s5")
    c.h(x0 + 1, x0 + 46, y0 + 23, "s4")
    for lx in (x0 + 3, x0 + 22, x0 + 41):
        c.rect(lx, y0 + 25, lx + 2, y0 + 30, "s2")
        c.v(lx, y0 + 25, y0 + 30, "s5")
    # the end roller at the shelf side, lit
    c.rect(x0, y0 + 14, x0 + 2, y0 + 21, "s5")
    c.v(x0, y0 + 14, y0 + 21, "s7")


def shelf(c, x0, y0):
    """The cheese shelf: low open timber shelving that ends the belt, 32x32. Bare when empty."""
    c.rect(x0 + 2, y0 + 6, x0 + 29, y0 + 29, "w4")
    c.box(x0 + 2, y0 + 6, x0 + 29, y0 + 29, "w1")
    for by0, by1 in ((y0 + 8, y0 + 14), (y0 + 17, y0 + 23)):
        c.rect(x0 + 4, by0, x0 + 27, by1, "w1")
        c.rect(x0 + 5, by0 + 1, x0 + 26, by1, "w2")
        c.h(x0 + 5, x0 + 26, by0 + 1, "w3")
        for nx in range(x0 + 8, x0 + 26, 6):
            c.v(nx, by0 + 2, by1, "w1")
    c.h(x0 + 3, x0 + 28, y0 + 15, "w6")
    c.h(x0 + 3, x0 + 28, y0 + 24, "w6")
    c.h(x0 + 3, x0 + 28, y0 + 7, "w5")
    c.v(x0 + 3, y0 + 7, y0 + 28, "w5")
    # the brass coin disc that pulses when cheese waits
    c.rect(x0 + 13, y0 + 1, x0 + 18, y0 + 5, "c1")
    c.box(x0 + 13, y0 + 1, x0 + 18, y0 + 5, "c0")
    c.h(x0 + 14, x0 + 17, y0 + 2, "c2")
    c.rect(x0 + 3, y0 + 30, x0 + 6, y0 + 31, "w1")
    c.rect(x0 + 25, y0 + 30, x0 + 28, y0 + 31, "w1")


def drain_grate(c, x0, y0):
    """A floor drain in the cheese side's walkway, under the table's whey outlet."""
    c.rect(x0, y0, x0 + 9, y0 + 7, "s2")
    c.box(x0, y0, x0 + 9, y0 + 7, "ink2")
    for gx in range(x0 + 2, x0 + 8, 2):
        c.v(gx, y0 + 1, y0 + 6, "ink")


def bucket(c, x0, y0):
    c.rect(x0, y0, x0 + 8, y0 + 10, "s4")
    c.box(x0, y0, x0 + 8, y0 + 10, "s1")
    c.h(x0 + 1, x0 + 7, y0 + 1, "s7")
    c.h(x0 + 1, x0 + 7, y0 + 2, "s2")
    c.v(x0 + 2, y0 + 3, y0 + 9, "s5")


def milk_cans(c, x0, y0):
    """Two steel milk cans on the lobby floor, the kind every dairy has by its door."""
    for dx in (0, 11):
        cx = x0 + dx
        c.rect(cx + 1, y0 + 4, cx + 8, y0 + 13, "s4")
        c.v(cx + 1, y0 + 4, y0 + 13, "s6")
        c.v(cx + 2, y0 + 4, y0 + 13, "s5")
        c.v(cx + 7, y0 + 4, y0 + 13, "s2")
        c.v(cx + 8, y0 + 4, y0 + 13, "s1")
        c.box(cx + 1, y0 + 4, cx + 8, y0 + 13, "ink2") if False else None
        c.h(cx + 1, cx + 8, y0 + 9, "s2")
        c.h(cx + 1, cx + 8, y0 + 10, "s6")
        c.rect(cx + 2, y0 + 1, cx + 7, y0 + 3, "s5")      # the neck
        c.rect(cx, y0, cx + 9, y0 + 1, "cream")             # the lid
        c.h(cx, cx + 9, y0 + 2, "s3")
        c.h(cx + 1, cx + 8, y0 + 14, "ink2")


def pitchfork(c, x0, y0):
    """A pitchfork leaning on the lobby's west wall: a timber shaft and three tines."""
    c.v(x0 + 3, y0, y0 + 9, "w4")
    c.v(x0 + 4, y0, y0 + 9, "w2")
    c.v(x0 + 3, y0, y0 + 2, "w5")
    c.h(x0, x0 + 7, y0 + 10, "s3")
    for tx in (x0, x0 + 3, x0 + 7):
        c.v(tx, y0 + 10, y0 + 15, "s4")
    c.v(x0 + 4, y0 + 10, y0 + 15, "s5")


def build():
    c = Canvas(*SIZE)
    # floors first
    straw_blocks(c, 0, 0, 111, 127)
    steel_tiles(c, 112, 0, 191, 127)
    # the four pens, two each side of the aisle at x 48..63
    pen(c, 0, 0, True)
    pen(c, 0, 32, True)
    pen(c, 64, 0, False)
    pen(c, 64, 32, False)
    # supplies in the lobby
    hay_stack(c, 0, 80)
    feed_bin(c, 64, 72)
    pitchfork(c, 4, 64)
    milk_cans(c, 2, 112)
    door(c, 48, 112)
    # the sill between the cow side and the cheese side, with the way through left open
    c.v(109, 64, 111, "w5")
    c.v(110, 64, 111, "w3")
    c.v(111, 64, 111, "w1")
    # the line, top to bottom down the east side, then west along the foot to the shelf
    receiver(c, 112, 0)
    vat(c, 144, 0)
    drain_table(c, 144, 32)
    press_bank(c, 144, 64)
    outfeed(c, 144, 96)
    shelf(c, 112, 96)
    for x0, x1, y in ((117, 138, 32), (145, 190, 32), (145, 190, 64)):
        shadow(c, x0, x1, y)
    # the receiver's inlet from the north pipe, and its feed to the vat
    pipe_h(c, 140, 147, 10)
    # the vat's drain valve feeds the table's top rim
    pipe_v(c, 166, 30, 38)
    # whey goes from the table's outlet to a floor drain in the walkway
    pipe_h(c, 127, 146, 58)
    pipe_v(c, 127, 58, 66)
    drain_grate(c, 122, 67)
    bucket(c, 130, 76)
    # milk pipes: along the north wall from the west pens, down the partition from the east
    pipe_v(c, 0, 0, 63)
    pipe_v(c, 109, 0, 63)
    pipe_h(c, 4, 123, 0)
    return c.im


# Where everything is, in room pixels (x, y, width, height). Written beside the PNG so the
# picture's layout is a file a person can read, and so a test can hold the game's cells
# (`systems/machine_defs.gd`) to it.
LAYOUT = {
    "pens": [[0, 0, 48, 32], [0, 32, 48, 32], [64, 0, 48, 32], [64, 32, 48, 32]],
    "aisle": [48, 0, 16, 64],
    "lobby": [0, 64, 112, 64],
    "door": [48, 112, 16, 16],
    "hay": [0, 80, 30, 24],
    "feed_bin": [64, 72, 42, 26],
    "receiver": [112, 0, 32, 32],
    "vat": [144, 0, 48, 32],
    "table": [144, 32, 48, 32],
    "presses": [144, 64, 48, 32],
    "belt": [144, 96, 48, 32],
    "shelf": [112, 96, 32, 32],
}


def write_layout():
    import json
    regions = ",\n".join('    "%s": %s' % (k, json.dumps(v)) for k, v in LAYOUT.items())
    note = ("A 12 by 8 room: the cow side (columns 0 to 6) and the cheese line (columns 7 to 11). "
            "Every machine is drawn empty; the game draws the line's work on them. Rectangles "
            "are x, y, width, height in room pixels. Built by tools/build_barn_room_art.py.")
    OUT.with_suffix(".json").write_text(
        '{\n  "image": %s,\n  "cell_size": [%d, %d],\n  "grid_size": [%d, %d],\n  "note": %s,\n'
        '  "product_route": %s,\n  "regions": {\n%s\n  }\n}\n' % (
            json.dumps(OUT.name), CELL, CELL, CELLS[0], CELLS[1], json.dumps(note),
            json.dumps(["receiver", "vat", "table", "presses", "belt", "shelf"]), regions))


def check(im):
    assert im.size == SIZE, im.size
    px = im.load()
    for y in range(SIZE[1]):
        for x in range(SIZE[0]):
            a = px[x, y][3]
            assert a == 255, ("not opaque", x, y)
    shipped = shipped_palette()
    bad = {px[x, y][:3] for y in range(SIZE[1]) for x in range(SIZE[0])} - shipped
    assert not bad, ["#%02x%02x%02x" % c for c in bad]


_SHIPPED = None


def shipped_palette():
    global _SHIPPED
    if _SHIPPED is None:
        found = set()
        for f in (ROOT / "assets/sprites").rglob("*.png"):
            if "industrial_barn_interior" in f.name:
                continue
            im = Image.open(f).convert("RGBA")
            found |= {p[:3] for p in im.get_flattened_data() if p[3] == 255} \
                if hasattr(im, "get_flattened_data") else {p[:3] for p in im.getdata() if p[3] == 255}
        _SHIPPED = found
    return _SHIPPED


def main():
    im = build()
    check(im)
    if "--check" not in sys.argv:
        im.save(OUT)
        write_layout()
        print("wrote", OUT.relative_to(ROOT), im.size)


if __name__ == "__main__":
    main()

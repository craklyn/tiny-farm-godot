#!/usr/bin/env python3
"""Build the sheep's five coats, four 32x28 frames each, every frame facing right.

The joke (Daniel, 2026-10-13): sheep grow wool and there is no shearing yet, so they
get fluffier and fluffier until they cannot take another step, and they are perfectly
happy about it. Rows, top to bottom: freshly sheared, mid-growth, full coat, extra
full coat, extreme coat. Rows 1-4 are a four-frame walk; row 5 is a happy idle, since
she can no longer walk. Every face is content: eyes shut in a smile, pink cheeks.

Every sheep wears one of several LOOKS (Daniel, 2026-10-13: "each sheep [should] have
distinct visuals"): a fleece colour, a face colour, a topknot, sometimes horns or
spots, and its own lumps along the fleece's edge. The looks stack down one sheet,
five coat rows each, so a sheep's row is look x 5 + coat.

All rows share one cell, sized for the extreme coat. Her feet touch the cell's bottom
row in every frame and her body is centred on it, so the game stands every coat the
way it stands the cow (`entities/grazer.gd`, cell_dest): on the middle of her square's
bottom edge. The wool is drawn as overlapping puffs, back to front, each with a shaded
lower rim, which is what makes it read as wool rather than a cream ellipse.

    python3 tools/build_sheep_art.py                 # writes the shipped sheet + json
    python3 tools/build_sheep_art.py --out=DIR --looks=all   # every candidate look
"""
import json
import math
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CELL = (32, 28)
FRAMES = 4
ROWS = ["sheared", "mid", "full", "extra_full", "extreme"]


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


# Every colour is one the game already ships (checked when the sheet is built): the
# cream fleece is the hen's cream, shades and outline; the faces are the farmer's skin,
# the cow's ink and the fence's browns; the cheeks the farmer's pink.
WOOL = {  # base, shade, deep shade, outline
    "cream": ("#f8f4e6", "#e0d9c4", "#c9bfa4", "#8f8880"),
    "grey": ("#b8b2ac", "#a09288", "#8f8880", "#4f4e5d"),
    "brown": ("#c39a6c", "#a97959", "#90625d", "#5e403c"),
    "black": ("#736161", "#5d4b4c", "#4d3c3d", "#2f2b3d"),
}
FACES = {  # face, face outline (None: the face is dark enough alone), eyes, nose and smile, ear rim
    "light": ("#f6ddc4", "#a09288", "#2f2b3d", "#2f2b3d", "#a09288"),
    "black": ("#2f2b3d", None, "#f8f4e6", "#ef91b6", "#2f2b3d"),
    "brown": ("#a97959", "#5e403c", "#2f2b3d", "#2f2b3d", "#5e403c"),
}
PINK, INK = "#ef91b6", "#2f2b3d"
HORN = ("#dcb98a", "#90625d")  # horn, horn outline
SPOTS = ("#736161", "#5d4b4c")  # a spotted fleece's patches: the dark fleece's colours

# The candidates. tuft: "topknot" (two puffs), "pompom" (one big ball), "fringe" (over
# the brow), "none". lumps: which way round the fleece's lumps fall, so no two looks
# share a silhouette.
LOOKS = [
    {"name": "cream_light", "wool": "cream", "face": "light", "tuft": "topknot", "lumps": 0},
    {"name": "cream_black", "wool": "cream", "face": "black", "tuft": "fringe", "lumps": 3},
    {"name": "cream_brown", "wool": "cream", "face": "brown", "tuft": "pompom", "lumps": 6},
    {"name": "brown_light", "wool": "brown", "face": "light", "tuft": "pompom", "lumps": 9},
    {"name": "black_light", "wool": "black", "face": "light", "tuft": "topknot", "lumps": 2},
    {"name": "grey_black", "wool": "grey", "face": "black", "tuft": "none", "lumps": 5},
    {"name": "spotted_black_horns", "wool": "cream", "face": "black", "tuft": "none",
     "lumps": 11, "horns": True, "spots": True},
    {"name": "cream_light_horns", "wool": "cream", "face": "light", "tuft": "fringe",
     "lumps": 7, "horns": True},
]
SHIPPED = [look["name"] for look in LOOKS]  # Daniel approved all eight, 2026-10-13
LOOK = dict(LOOKS[0])


def palette(look):
    w, f = WOOL[look["wool"]], FACES[look["face"]]
    return {
        "W": w[0], "S": w[1], "D": w[2], "O": w[3],
        "F": f[0], "B": f[1] or f[0], "E": f[2], "M": f[3], "R": f[4],
        "P": PINK, "K": INK, "H": HORN[0], "h": HORN[1], "X": SPOTS[0], "Y": SPOTS[1],
    }


class Canvas:
    def __init__(self):
        self.px = {}

    def put(self, x, y, c):
        if 0 <= x < CELL[0] and 0 <= y < CELL[1]:
            self.px[(x, y)] = c

    def get(self, x, y):
        return self.px.get((x, y))


def wool_cloud(cv, puffs, floor_shade_y, curls=()):
    """Puffs are (cx, cy, r), drawn in order; later puffs cover earlier ones. Curls are
    puffs of which only the shaded lower rim is drawn: wool texture inside the fleece."""
    def disc(cx, cy, r, rim_only):
        for y in range(math.floor(cy - r) - 1, math.ceil(cy + r) + 2):
            for x in range(math.floor(cx - r) - 1, math.ceil(cx + r) + 2):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                d = math.hypot(dx, dy)
                if d > r:
                    continue
                # The puff's lower rim is in shade; the rest is lit wool.
                rim = d > r - 1.05 and dy > 0.1 * r and dx > -0.75 * r
                if rim:
                    cv.put(x, y, "S")
                elif not rim_only:
                    cv.put(x, y, "W")
    for cx, cy, r in puffs:
        disc(cx, cy, r, False)
    for cx, cy, r in curls:
        if cv.get(round(cx), round(cy)) is not None:
            disc(cx, cy, r, True)
    # The underside of the whole fleece sits in the shade of the body above it.
    for (x, y), c in list(cv.px.items()):
        if y >= floor_shade_y and c in "WS":
            cv.put(x, y, "D" if cv.get(x, y + 1) is None or cv.get(x, y + 2) is None else "S")


# A spotted fleece's spots, in the fleece's own measure: centre across (-1 back, +1
# front) and down (-1 top, +1 bottom), radius as a share of the fleece's size, and
# how much wider than tall. The same spots in the same places at every coat; they only
# grow as the fleece grows, so they keep their shape and their share of her
# (Daniel, 2026-10-13: "grow between sizes, but don't change shape").
SPOTS_LAYOUT = [
    (-0.45, -0.30, 0.26, 1.35),
    (0.10, -0.50, 0.17, 1.2),
    (-0.10, 0.32, 0.20, 1.3),
    (-0.85, 0.15, 0.15, 1.0),
]


def spots(cv, cx, cy, a, b):
    """Dark oval spots over the wool, keeping its shading underneath."""
    if not LOOK.get("spots"):
        return
    # Measured on the fleece as drawn, lumps and all, so a big lumpy coat and a
    # smooth sheared one carry the same share of spots.
    fleece = [p for p, c in cv.px.items() if c in ("W", "S", "D")]
    x0, x1 = min(x for x, _ in fleece), max(x for x, _ in fleece) + 1
    y0, y1 = min(y for _, y in fleece), max(y for _, y in fleece) + 1
    cx, cy, a, b = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    size = math.sqrt(a * b)
    for u, v, r, wide in SPOTS_LAYOUT:
        px, py, ry = cx + u * a, cy + v * b, r * size
        rx = ry * wide
        for (x, y), c in list(cv.px.items()):
            if c in ("W", "S", "D") and ((x + 0.5 - px) / rx) ** 2 + ((y + 0.5 - py) / ry) ** 2 <= 1.0:
                # Solid spots: only the fleece's shaded underside shows through.
                cv.put(x, y, "Y" if c == "D" else "X")


def outline(cv, color, keep=()):
    """A one-pixel outline round everything drawn so far (4-neighbour), into empty
    pixels only."""
    inside = set(cv.px)
    for x, y in list(inside):
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in inside and (nx, ny) not in keep:
                cv.put(nx, ny, color)


# Faces, facing right, drawn by hand. F face, E the eye shut in a smile, P pink (cheek,
# inside of the ear), N nose, M the smile, e the ear's rim. Two sizes: the small one for
# a sheared or half-grown sheep, the big one once the fleece is full. The ear sticks out
# backwards over the wool, which more than anything says "sheep" at play scale.
HEADS = {
    "small": """
.....FFFF...
....FFFFFF..
.eeFFFFEFFF.
ePPFFFEFEFFF
.ee.FFFPFFFN
.....FFFFMM.
""",
    "big": """
......FFFFF...
.....FFFFFFF..
....FFFFFFFFF.
.eeeFFFFFEFFFF
ePPPFFFFEFEFFF
.eee.FFFFFFFFFF
.....FFFFPFFFFN
......FFFFFMMF.
.......FFFFF...
""",
}


def head(cv, hx, hy, kind, tuft=None):
    """The face with its top-left corner at (hx, hy), then any topknot of wool."""
    dark = FACES[LOOK["face"]][1] is None
    face = {"F": "F", "E": "E", "P": "P", "N": "M", "M": "M", "e": "R"}
    rows = HEADS[kind].strip("\n").split("\n")
    shape = set()
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c != ".":
                cv.put(hx + x, hy + y, face[c])
                shape.add((hx + x, hy + y))
    if not dark:
        for x, y in list(shape):
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) not in shape:
                    cv.put(nx, ny, "B")
    tuft = style_tuft(tuft, hx, hy)
    if tuft:
        top = Canvas()
        for tx, ty, r in tuft:
            for y in range(math.floor(ty - r) - 1, math.ceil(ty + r) + 2):
                for x in range(math.floor(tx - r) - 1, math.ceil(tx + r) + 2):
                    dx, dy = x + 0.5 - tx, y + 0.5 - ty
                    d = math.hypot(dx, dy)
                    if d <= r:
                        top.put(x, y, "S" if d > r - 1.05 and dy > 0.1 * r else "W")
        for (x, y), c in top.px.items():
            cv.put(x, y, c)
        # Outline the topknot wherever it meets the face or the open air.
        for x, y in list(top.px):
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) in top.px:
                    continue
                if cv.get(nx, ny) is None or (nx, ny) in shape:
                    cv.put(nx, ny, "O")
    # Horns go on last: even the extreme coat's wool cannot hide them.
    if LOOK.get("horns"):
        horns(cv, hx, hy, kind)


# A ram's horn curls down over his ear. H horn, h its outline.
HORNS = {
    "small": (1, -1, """
.hhh.
hHHHh
hHhHh
hHh.h
.hh..
"""),
    "big": (1, -1, """
..hhhh.
.hHHHHh
hHHhhHh
hHh.hHh
hHHhHHh
.hHHHh.
..hhh..
"""),
}


def horns(cv, hx, hy, kind):
    ox, oy, art = HORNS[kind]
    for y, row in enumerate(art.strip("\n").split("\n")):
        for x, c in enumerate(row):
            if c != ".":
                cv.put(hx + ox + x, hy + oy + y, c)


def style_tuft(tuft, hx, hy):
    """Turn the coat's topknot (puffs relative to nothing: absolute) into this look's
    hairstyle. The extreme coat passes a third puff, the fleece swallowing the back of
    her head, which every look keeps."""
    if not tuft:
        return tuft
    main, rest, keep = tuft[0], tuft[1:2], tuft[2:]
    style = LOOK["tuft"]
    if style == "topknot":
        return tuft
    if style == "pompom":
        return [(main[0] + 0.6, main[1] - 1.1, main[2] + 0.5)] + keep
    if style == "fringe":
        # Puffs pushed forward over the brow, sitting just above her shut eyes.
        return [(main[0] + 2.0, main[1] - 0.1, main[2] * 0.85),
                (main[0] + 4.2, main[1] + 0.3, main[2] * 0.6)] + keep
    return keep


def legs(cv, xs, top, step):
    """Thin ink legs from `top` down to the floor, drawn under the fleece; on a
    stepping frame alternate legs swing their hooves a pixel forward or back."""
    floor = CELL[1] - 1
    for i, lx in enumerate(xs):
        d = 0 if step == 0 else (step if i % 2 == 0 else -step)
        for y in range(top, floor + 1):
            swing = d if y >= floor - 1 and floor - top >= 3 else 0
            if cv.get(lx + swing, y) is None:
                cv.put(lx + swing, y, "K")


# --- the five coats ---------------------------------------------------------------
# Each takes the frame index and returns a Canvas. `lift` bobs the body a pixel on
# the passing frames of the walk, the way the cow's does.

WALK = ((0, 0), (1, 1), (0, 1), (1, -1))
LUMPS = [0.0, 0.6, -0.4, 0.9, -0.2, 0.4, -0.6, 0.7, 0.1, -0.3, 0.5, -0.5, 0.8, -0.1]


def ellipse_puffs(cx, cy, a, b, r, n, jitter, start=0.0):
    """Puffs round the rim of an ellipse over a filled core, their radii varied so the
    edge is lumpy rather than a regular scallop; plus curls for the inside."""
    core = []
    steps = max(1, int((a - b) // 2) + 1)
    for i in range(steps):
        t = -1 + 2 * i / max(1, steps - 1) if steps > 1 else 0
        core.append((cx + t * (a - b), cy, b - 0.3))
    ring = []
    start += 0.37 * LOOK["lumps"]
    for i in range(n):
        t = start + 2 * math.pi * i / n
        rr = r + jitter * LUMPS[(i + LOOK["lumps"]) % len(LUMPS)]
        ring.append((cx + (a - rr * 0.6) * math.cos(t), cy + (b - rr * 0.6) * math.sin(t), rr))
    # Top puffs first, so lower ones overlap them: the fleece hangs down.
    ring.sort(key=lambda p: p[1])
    curls = []
    m = max(3, n // 2)
    for i in range(m):
        t = start + 0.5 + 2 * math.pi * i / m
        rr = r * 0.75 + 0.4 * jitter * LUMPS[(i + 3 + LOOK["lumps"]) % len(LUMPS)]
        curls.append((cx + (a * 0.5) * math.cos(t), cy + (b * 0.45) * math.sin(t) - 0.5, rr))
    curls.sort(key=lambda p: p[1])
    return core + ring, curls


def coat(f, body, legs_x, head_at, kind, tuft=None, tail=None):
    lift, step = WALK[f]
    cv = Canvas()
    cx, cy, a, b, r, n, jit = body
    cy -= lift
    puffs, curls = ellipse_puffs(cx, cy, a, b, r, n, jit)
    if tail:
        puffs.insert(0, (tail[0], tail[1] - lift, tail[2]))
    wool_cloud(cv, puffs, round(cy + b * 0.55), curls)
    spots(cv, cx, cy, a, b)
    outline(cv, "O")
    legs(cv, legs_x, round(cy + b) - 1, step)
    hx, hy = head_at
    head(cv, hx, hy - lift, kind, [(tx, ty - lift, tr) for tx, ty, tr in tuft] if tuft else None)
    return cv


def sheared(f):
    lift, step = WALK[f]
    cv = Canvas()
    floor = CELL[1] - 1
    # A skinny, freshly clipped body: a smooth short-cropped ellipse, a few stubble
    # flecks, legs that look long now there is nothing round them.
    cx, cy, a, b = 13.5, floor - 7.5 - lift, 6.0, 3.3
    for y in range(CELL[1]):
        for x in range(CELL[0]):
            dx, dy = (x + 0.5 - cx) / a, (y + 0.5 - cy) / b
            if dx * dx + dy * dy <= 1.0:
                cv.put(x, y, "S" if dy > 0.4 else "W")
    for x, y in ((10, -1), (13, 0), (16, -1), (11, 1), (15, 1)):
        cv.put(x, round(cy) + y, "S")
    spots(cv, cx, cy, a, b)
    outline(cv, "O")
    cv.put(round(cx - a) - 1, round(cy) - 2, "W")  # a stub of tail
    cv.put(round(cx - a) - 2, round(cy) - 2, "O")
    legs(cv, [9, 11, 16, 18], round(cy + b), step)
    head(cv, 14, floor - 12 - lift, "small")
    return cv


def mid(f):
    floor = CELL[1] - 1
    return coat(f, (13.5, floor - 8.0, 8.0, 4.8, 3.0, 6, 0.6), [9, 11, 16, 18],
                (15, floor - 14), "small", tuft=[(21.0, floor - 14.9, 1.8)],
                tail=(5.5, floor - 10.0, 1.6))


def full(f):
    floor = CELL[1] - 1
    return coat(f, (13.0, floor - 9.0, 10.0, 6.2, 3.9, 7, 0.8), [8, 10, 16, 18],
                (14, floor - 15), "big", tuft=[(21.5, floor - 15.9, 2.3), (24.0, floor - 15.9, 1.8)],
                tail=(3.5, floor - 11.5, 2.0))


def extra_full(f):
    floor = CELL[1] - 1
    return coat(f, (15.6, floor - 10.0, 11.0, 8.2, 4.8, 8, 1.0), [9, 11, 17, 19],
                (15, floor - 13), "big", tuft=[(22.0, floor - 14.3, 2.8), (25.0, floor - 14.2, 2.2)],
                tail=(4.0, floor - 13.0, 2.4))


# The extreme coat's idle: rest, a breath in (the fleece swells a pixel), rest with a
# contented sway, then a hoof paddles at the ground to no effect whatsoever.
IDLE = ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))


def extreme(f):
    swell, sway, paddle = IDLE[f]
    cv = Canvas()
    floor = CELL[1] - 1
    # The fleece sits almost on the ground: all four hooves only just poke out under
    # it, less than the extra full coat's legs do, the front pair splayed forward and
    # the hind pair back (Daniel, 2026-10-13). The paddle frame lifts the front hoof.
    cx, cy = 15.6 + sway * 0.5, floor - 11.8 - swell * 0.3
    a, b = 11.9 + swell * 0.4, 9.4 + swell * 0.3
    puffs, curls = ellipse_puffs(cx, cy, a, b, 5.8, 8, 1.2, start=0.3)
    wool_cloud(cv, puffs, round(cy + b * 0.6), curls)
    spots(cv, cx, cy, a, b)
    outline(cv, "O")
    # Each leg is hidden in the wool; only its hoof shows on the floor, two pixels
    # pointing the way it splays. On the paddle frame the front hoof kicks a pixel
    # further forward.
    for x, out, kick in ((7, -1, False), (11, -1, False), (20, 1, False), (24, 1, paddle)):
        x += round(sway * 0.5)
        for y in range(floor - 6, floor):
            if cv.get(x, y) is None:
                cv.put(x, y, "K")
        for px in (x, x + out) + ((x + 2 * out,) if kick else ()):
            if cv.get(px, floor) is None:
                cv.put(px, floor, "K")
    # The face, sunk into the front of the fleece, wool down to her eyes.
    hx, hy = 15 + sway, floor - 15 - swell
    head(cv, hx, hy, "big", [(hx + 7.0, hy - 1.4, 3.0), (hx + 10.0, hy - 0.9, 2.4), (hx + 4.5, hy - 0.2, 2.6)])
    return cv


BUILDERS = [sheared, mid, full, extra_full, extreme]


def shipped_colours():
    """Opaque colours in every other checked-in sprite sheet."""
    seen = set()
    for path in sorted((ROOT / "assets/sprites").rglob("*.png")):
        if path.name != "sheep.png":
            seen.update(p[:3] for p in Image.open(path).convert("RGBA").get_flattened_data() if p[3] == 255)
    return seen


def build(looks):
    sheet = Image.new("RGBA", (CELL[0] * FRAMES, CELL[1] * len(ROWS) * len(looks)), (0, 0, 0, 0))
    sizes = {}
    for li, look in enumerate(looks):
        LOOK.clear()
        LOOK.update(look)
        pal = {k: rgb(v) for k, v in palette(look).items()}
        edges = {pal[k] for k in ("O", "K", "B", "R", "h")}
        for ri, fn in enumerate(BUILDERS):
            row = li * len(ROWS) + ri
            boxes = []
            for f in range(FRAMES):
                cv = fn(f)
                for (x, y), c in cv.px.items():
                    if c is not None:
                        sheet.putpixel((f * CELL[0] + x, row * CELL[1] + y), pal[c] + (255,))
                cell = sheet.crop((f * CELL[0], row * CELL[1], (f + 1) * CELL[0], (row + 1) * CELL[1]))
                box = cell.getbbox()
                # She stands on the cell's floor in every frame, never floating off her square.
                assert box[3] == CELL[1], (look["name"], ROWS[ri], f, box)
                # Nothing is cut off by the cell's edge: only an outline or a hoof touches it.
                edge = [(x, y) for x in range(CELL[0]) for y in range(CELL[1])
                        if x in (0, CELL[0] - 1) or y == 0]
                assert all(cell.getpixel(p)[3] == 0 or cell.getpixel(p)[:3] in edges for p in edge), \
                    (look["name"], ROWS[ri], f, "drawing clipped by the cell")
                boxes.append(box)
            if li == 0:
                sizes[ROWS[ri]] = {"w": max(b[2] for b in boxes) - min(b[0] for b in boxes),
                                   "h": CELL[1] - min(b[1] for b in boxes)}
    pixels = sheet.get_flattened_data()
    assert all(p[3] in (0, 255) for p in pixels)
    # No colour the game does not already ship.
    stray = {p[:3] for p in pixels if p[3]} - shipped_colours()
    assert not stray, ["#%02x%02x%02x" % c for c in stray]
    return sheet, sizes


def main():
    out = ROOT / "assets/sprites/generated"
    names = SHIPPED
    for arg in sys.argv[1:]:
        if arg.startswith("--out="):
            out = Path(arg[6:])
        elif arg.startswith("--looks="):
            names = [l["name"] for l in LOOKS] if arg[8:] == "all" else arg[8:].split(",")
    looks = [next(l for l in LOOKS if l["name"] == n) for n in names]
    out.mkdir(parents=True, exist_ok=True)
    sheet, sizes = build(looks)
    sheet.save(out / "sheep.png")
    meta = {
        "cell_w": CELL[0], "cell_h": CELL[1], "rows": len(ROWS), "frames": FRAMES,
        "looks": names,
        "row_of": "look index x rows + coat index",
        "row_names": ROWS,
        "row_kinds": ["walk", "walk", "walk", "walk", "idle"],
        "drawn_size": sizes,
        "anchor": "feet on the cell's bottom row, body centred: stand it like the cow",
        "facing": "right",
        "idle_frames": "rest, breathe in, sway, paddle a hoof: holds best at about 0.25 s a frame",
    }
    (out / "sheep.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(out / "sheep.png", len(looks), "looks")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Compose the sheep look sheets under docs/design/mockups/sheep/.

Two kinds of picture:
- the line-up: the cow and the five coats standing on one strip of the farm's own
  grass, at play size and enlarged, one strip per candidate face;
- the in-game sheets: crops of what `tools/capture_cow_readability.tscn` shot with
  each candidate sheet swapped in for the cows (`--variants`), on the grass beside the
  farmer and in the creamery's pens, one row per candidate.

    python3 tools/build_sheep_art.py --out=DIR_A --face=cream   (and so on per candidate)
    python3 tools/compose_sheep_mockups.py lineup NAME=DIR/sheep.png ...
    python3 tools/compose_sheep_mockups.py ingame SHOTS_DIR ROWLABEL=PREFIX ...
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/design/mockups/sheep"
CELL = (32, 28)
STAGES = ["sheared", "mid-growth", "full coat", "extra full", "extreme"]
GRASS = ROOT / "assets/sprites/generated/terrain_grass.png"


def grass_strip(w, h):
    tile = Image.open(GRASS).convert("RGBA").crop((0, 0, 16, 16))
    strip = Image.new("RGBA", (w, h))
    for y in range(0, h, 16):
        for x in range(0, w, 16):
            strip.alpha_composite(tile, (x, y))
    return strip


def lineup(named_sheets):
    cow = Image.open(ROOT / "assets/sprites/generated/cow.png").convert("RGBA").crop((0, 0, 24, 20))
    gap = 4
    w = 6 + 24 + gap + 5 * (CELL[0] + gap)
    h = CELL[1] + 6
    rows = []
    for name, path in named_sheets:
        sheet = Image.open(path).convert("RGBA")
        strip = grass_strip(w, h)
        strip.alpha_composite(cow, (6, h - 3 - 20))
        for r in range(5):
            strip.alpha_composite(sheet.crop((0, r * CELL[1], CELL[0], (r + 1) * CELL[1])),
                                  (6 + 24 + gap + r * (CELL[0] + gap), h - 3 - CELL[1]))
        rows.append((name, strip))
    big = 6
    label_h = 22
    sheet_w = max(s.width for _, s in rows) * big
    canvas = Image.new("RGBA", (sheet_w + 20, sum((s.height * big + label_h + 2 * s.height + 14) for _, s in rows) + 30),
                       (250, 248, 240, 255))
    d = ImageDraw.Draw(canvas)
    d.text((10, 8), "cow, then: " + " / ".join(STAGES), fill=(47, 43, 61))
    y = 28
    for name, strip in rows:
        d.text((10, y), name + "  (play size, then enlarged x6)", fill=(47, 43, 61))
        y += label_h - 6
        canvas.alpha_composite(strip.resize((strip.width * 2, strip.height * 2), Image.NEAREST), (10, y))
        y += strip.height * 2 + 4
        canvas.alpha_composite(strip.resize((strip.width * big, strip.height * big), Image.NEAREST), (10, y))
        y += strip.height * big + 14
    return canvas


def ingame(shots, rows, moment, box, titles=None):
    """rows: [(label, [variant names or None per column])]; columns are the coats."""
    titles = titles or STAGES
    x0, y0, x1, y1 = box
    cw, ch = x1 - x0, y1 - y0
    cols = 1 + len(titles)
    pad, label_w, head = 6, 215, 20
    canvas = Image.new("RGBA", (label_w + cols * (cw + pad), head + len(rows) * (ch + pad)), (250, 248, 240, 255))
    d = ImageDraw.Draw(canvas)
    for c, title in enumerate(["the cow today"] + titles):
        d.text((label_w + c * (cw + pad) + 4, 4), title, fill=(47, 43, 61))
    for r, (label, names) in enumerate(rows):
        y = head + r * (ch + pad)
        d.text((6, y + ch // 2 - 6), label, fill=(47, 43, 61))
        for c, name in enumerate(["shipped"] + names):
            if name is None:
                continue
            f = Path(shots) / f"{moment}_{name}.png"
            if not f.exists():
                continue
            canvas.alpha_composite(Image.open(f).convert("RGBA").crop(box), (label_w + c * (cw + pad), y))
    return canvas


LABELS = {
    "cream_light": "cream fleece, light face",
    "cream_black": "cream fleece, black face",
    "cream_brown": "cream fleece, brown face",
    "brown_light": "brown fleece, light face",
    "black_light": "black fleece, light face",
    "grey_black": "grey fleece, black face",
    "spotted_black_horns": "spotted fleece, black face, horns",
    "cream_light_horns": "cream fleece, light face, horns",
}


def looks(sheet_path, scale=5):
    """Every look down the side, every coat across, on the farm's grass beside a cow."""
    import json
    sheet = Image.open(sheet_path).convert("RGBA")
    names = json.loads(Path(sheet_path).with_suffix(".json").read_text())["looks"]
    cow = Image.open(ROOT / "assets/sprites/generated/cow.png").convert("RGBA").crop((0, 0, 24, 20))
    w, h = 30 + 5 * (CELL[0] + 2) + 2, len(names) * (CELL[1] + 2) + 2
    strip = grass_strip(w, h)
    for li in range(len(names)):
        strip.alpha_composite(cow, (3, 1 + li * (CELL[1] + 2) + CELL[1] - 20))
        for r in range(5):
            row = li * 5 + r
            strip.alpha_composite(sheet.crop((0, row * CELL[1], CELL[0], (row + 1) * CELL[1])),
                                  (30 + r * (CELL[0] + 2), 1 + li * (CELL[1] + 2)))
    big = strip.resize((w * scale, h * scale), Image.NEAREST)
    label_w, head = 230, 22
    canvas = Image.new("RGBA", (label_w + big.width + 10, head + big.height + 10), (250, 248, 240, 255))
    d = ImageDraw.Draw(canvas)
    for c, title in enumerate(["cow"] + STAGES):
        x = label_w + (3 if c == 0 else 30 + (c - 1) * (CELL[0] + 2)) * scale
        d.text((x + 4, 4), title, fill=(47, 43, 61))
    for li, n in enumerate(names):
        d.text((8, head + (li * (CELL[1] + 2) + CELL[1] // 2) * scale - 6), "%d  %s" % (li + 1, LABELS.get(n, n)),
               fill=(47, 43, 61))
    canvas.alpha_composite(big, (label_w, head))
    return canvas


def flock(sheet_path, scale=4):
    """A mixed flock grazing together: every look once or twice, at a mix of coats,
    with the farmer and a cow for scale, drawn back to front."""
    import json
    sheet = Image.open(sheet_path).convert("RGBA")
    n = len(json.loads(Path(sheet_path).with_suffix(".json").read_text())["looks"])
    cow = Image.open(ROOT / "assets/sprites/generated/cow.png").convert("RGBA").crop((0, 0, 24, 20))
    farmer = Image.open(ROOT / "assets/sprites/generated/characters.png").convert("RGBA").crop((0, 0, 48, 48))
    w, h = 220, 120
    strip = grass_strip(w, h)
    # (x, feet y, look, coat, flip)
    spots = [(20, 40, 0, 2, False), (70, 36, 1, 4, True), (120, 42, 2, 1, False), (165, 38, 3, 3, True),
             (30, 78, 4, 4, False), (85, 72, 5, 0, False), (140, 80, 6, 2, True), (185, 76, 7, 3, False),
             (55, 112, 1 % n, 3, True), (110, 116, 4 % n, 1, False), (165, 112, 0, 4, True)]
    items = [(y, "sheep", x, li % n, coat, flip) for x, y, li, coat, flip in spots]
    items += [(100, "farmer", 192, 0, 0, False), (58, "cow", 196, 0, 0, True)]
    for y, kind, x, li, coat, flip in sorted(items):
        if kind == "sheep":
            row = li * 5 + coat
            im = sheet.crop((0, row * CELL[1], CELL[0], (row + 1) * CELL[1]))
        elif kind == "cow":
            im = cow
        else:
            im = farmer
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        strip.alpha_composite(im, (x - im.width // 2, y - im.height + (8 if kind == "farmer" else 0)))
    return strip.resize((w * scale, h * scale), Image.NEAREST)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    kind, args = sys.argv[1], sys.argv[2:]
    if kind == "lineup":
        out = args[0]
        named = [a.split("=", 1) for a in args[1:]]
        lineup(named).save(OUT / out)
        print(OUT / out)
    elif kind == "flock":
        flock(args[1]).save(OUT / args[0])
        print(OUT / args[0])
    elif kind == "looks":
        looks(args[1]).save(OUT / args[0])
        print(OUT / args[0])
    elif kind == "ingame_looks":
        # ingame_looks SHOTS OUT_PREFIX: variants named cow_<n><look>_3full / _5extreme
        import re
        shots, prefix = args[0], args[1]
        found = sorted({re.match(r"grass_cow_(\d+)(.+)_3full", f.stem).groups()
                        for f in Path(shots).glob("grass_cow_*_3full.png")}, key=lambda g: int(g[0]))
        rows = [("%s  %s" % (i, LABELS.get(n, n)), ["cow_%s%s_3full" % (i, n), "cow_%s%s_5extreme" % (i, n)])
                for i, n in found]
        for moment, box in (("grass", (150, 90, 380, 340)), ("pens", (105, 105, 445, 310))):
            ingame(shots, rows, moment, box, ["full coat", "extreme"]).save(OUT / f"{prefix}_{moment}.png")
            print(OUT / f"{prefix}_{moment}.png")
    elif kind == "ingame":
        # ingame SHOTS OUT_PREFIX LABEL=PREFIX[:only5] ...
        shots, prefix = args[0], args[1]
        rows = []
        for a in args[2:]:
            label, spec = a.split("=", 1)
            if spec.endswith(":only5"):
                rows.append((label, [None] * 4 + ["cow_" + spec[:-6]]))
            else:
                rows.append((label, ["cow_%s%s" % (spec, n) for n in
                                     ("1sheared", "2mid", "3full", "4extra", "5extreme")]))
        for moment, box in (("grass", (150, 90, 380, 340)), ("pens", (105, 105, 445, 310))):
            ingame(shots, rows, moment, box).save(OUT / f"{prefix}_{moment}.png")
            print(OUT / f"{prefix}_{moment}.png")


if __name__ == "__main__":
    main()

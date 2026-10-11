#!/usr/bin/env python3
"""Build the barn cow's four calm walking frames, 24x20 pixels each.

She is black and white (Daniel's pick, 2026-10-10). The first cow's tan hide was the
creamery's straw floor colour, #e8cfa6, which is also tilled soil, so inside the barn
she showed only her outline (design/17, "Cows on the straw").

She is half again a square (Daniel's pick, 2026-10-11, design/17 "How big a cow is"):
the 16px cow was shorter than the hen and under half the farmer's height. She still
stands on one square; `entities/grazer.gd` sizes her picture from this sheet and stands
it on the middle of her square's bottom edge, so she overhangs it like the farmer does.
"""
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "assets/sprites/generated/cow.png"
CELL = (24, 20)
# Every colour is one the game already ships: ink and cream from the barn's brief, the
# belly shade from the hen, the muzzle pink and the horn colour from the farmer.
COLORS = {
    "K": (47, 43, 61),     # ink: outline, patches, head (barn brief #2f2b3d)
    "W": (248, 244, 230),  # cream hide (barn brief #f8f4e6)
    "S": (224, 217, 196),  # belly shade (the hen's #e0d9c4)
    "P": (239, 145, 182),  # muzzle and udder (the farmer's #ef91b6)
    "H": (246, 221, 196),  # horn tips (the farmer's #f6ddc4)
}
# Facing right, without legs. The head is black with a white blaze down its front and
# one cream eye; two broad patches on the body survive play scale.
BODY = """
...................H..H.
..................KKKKK.
................KKKKKKWK
..KKKKKKKKKKKKKKKKKWKKWK
.KWWWWWKKKWWWWWWKKKKKWWK
KKWWWWKKKKKWWWKKWKKKKWWK
K.KWWWWKKKWWWWKKKWKKWWWK
K.KWWWWWWWWWWWWWWWKKPPPP
K.KKKWWWWWWWWWWKKWKKPKPK
K.KKKKWWWWWWWWKKKWWKKPPK
.KKKKSWWWWWWWSSKKWWSKKK.
..KSSSSSSSSSSSSSSSSK....
..KKKKKSSPPSSKKKKKK.....
"""
LEGS = [3, 6, 13, 16]   # left column of each two-pixel leg: hind pair, fore pair
LEG_LEN = 5


def frame(im, ox, lift, step):
    rows = BODY.strip("\n").split("\n")
    assert all(len(r) == CELL[0] for r in rows)
    top = CELL[1] - len(rows) - LEG_LEN - lift
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c != ".":
                im.putpixel((ox + x, top + y), COLORS[c] + (255,))
    # Legs reach the ground in every frame: a lifted body has longer legs, and a
    # stepping frame swings the hooves of alternate legs one pixel forward or back.
    base = top + len(rows)
    for i, lx in enumerate(LEGS):
        d = 0 if (lift == 0 and step) else (step if i % 2 == 0 else -step)
        length = LEG_LEN + lift
        for y in range(length):
            for dx in (0, 1):
                swing = d if y >= length - 2 else 0
                im.putpixel((ox + lx + dx + swing, base + y), COLORS["K"] + (255,))


im = Image.new("RGBA", (CELL[0] * 4, CELL[1]), (0, 0, 0, 0))
for i, (lift, step) in enumerate(((0, 0), (1, 1), (0, 1), (1, 0))):
    frame(im, i * CELL[0], lift, step)
assert all(p[3] in (0, 255) for p in im.getdata())
assert all(p[3] == 0 or p[:3] in COLORS.values() for p in im.getdata())
# The creamery's straw floor and tilled soil: a cow drawn in it vanishes on both.
assert all(p[3] == 0 or p[:3] != (232, 207, 166) for p in im.getdata())
# She stands on the cell's floor in every frame, so she never floats off her square.
for i in range(4):
    assert im.crop((i * CELL[0], 0, (i + 1) * CELL[0], CELL[1])).getbbox()[3] == CELL[1]
im.save(OUT)
print(OUT)

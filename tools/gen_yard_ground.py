#!/usr/bin/env python3
"""Derive the yard's ground tile from the field's grass tile (T-32).

The designer's directive of 2026-09-01: *"create a separate form of ground that
cannot be tilled, and fill the initial fenced space with it."* This is the
picture of that ground.

Not generated — **derived**, and deliberately, for the reason the turned-down cot
is derived (tools/gen_cot_turndown.py): the yard is drawn edge to edge with the
field across a one-tile fence line, so the two tiles must be the same tile in a
different colour or the seam will read as a rendering fault instead of as a
boundary. `terrain_grass.png` is three flat colours arranged as a noise pattern;
this keeps the pattern pixel for pixel and remaps only the three colours.

The remap, in words: the same turf, kept. Each colour moves a step deeper and
cooler — greener, not greyer — so the yard reads as tended lawn against the
paler, drier field beyond the fence. Three candidates were rendered side by side
against the grass tile before this one was picked; the two rejected were a
desaturated sage that read as *dead* ground and a halfway shade that vanished.
Subtlety is the requirement here, not decoration: the yard is most of the early
screen, so it has to survive being looked at for ten minutes.

Idempotent: run it as often as you like. Costs nothing and needs no network.

    python3 tools/gen_yard_ground.py
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "assets", "sprites", "generated", "terrain_grass.png")
DST = os.path.join(HERE, "..", "assets", "sprites", "generated", "terrain_yard.png")

# grass colour -> yard colour. The keys are exactly the three colours
# terrain_grass.png contains; anything else in the source is a signal that the
# grass tile was regenerated and this mapping needs redoing, so it is an error
# rather than a passthrough.
REMAP = {
    (209, 224, 119, 255): (190, 211, 124, 255),   # highlight
    (191, 212, 112, 255): (173, 197, 117, 255),   # mid
    (163, 194,  99, 255): (147, 178, 104, 255),   # shadow
}


def main() -> int:
    src = Image.open(SRC).convert("RGBA")
    out = Image.new("RGBA", src.size)
    px_in = src.load()
    px_out = out.load()
    unknown = set()
    for y in range(src.height):
        for x in range(src.width):
            c = px_in[x, y]
            if c not in REMAP:
                unknown.add(c)
                px_out[x, y] = c
            else:
                px_out[x, y] = REMAP[c]
    if unknown:
        print("FAIL: %s holds colours this remap does not know: %s"
              % (os.path.basename(SRC), sorted(unknown)), file=sys.stderr)
        return 1
    out.save(DST)
    print("wrote %s (%dx%d, %d colours)" % (DST, out.width, out.height, len(REMAP)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

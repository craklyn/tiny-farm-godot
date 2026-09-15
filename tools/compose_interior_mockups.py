#!/usr/bin/env python3
"""Draw the interior candidates for Q-108 and Q-109 as pictures.

P-18 says a building dilates in place rather than cutting to a room, and that the farm
stays visible through the walls. Two things about that are open, and both are questions
about how something looks:

  Q-108  is the outside registered to the doorway — so it magnifies by the same whole
         number the room grew by — or drawn as a backdrop at its ordinary size?
  Q-109  how much bigger is a room than the building it stands in?

Q-108 is drawn over a **photograph of the real game**: tools/capture_interior_plate.tscn
walks the farmer in through her own front door and photographs the room, and everything
outside its walls is black there today, which is exactly the area P-18 proposes filling
with the farm. The farm that goes into it is a second real capture. So every pixel in
those two panels is the running game's, at the running game's scale, and the only thing
drawn here is which farm goes in the dark and how big it is.

Q-109 cannot be photographed — no room but the farmhouse's exists — so those panels are
drawn from the same shipped art the game draws them from: terrain_floor.png,
interior_wall.png, cot.png and characters.png, every one at the size the game uses.

    python3 tools/compose_interior_mockups.py

Writes docs/design/mockups/interiors/. Needs no display; both plates carry the game's
own rendering. Regenerate the plates with:

    godot --path . res://tools/capture_interior_plate.tscn

Two rules kept from tools/compose_overnight_frames.py, because they are the studio's
rules for anything that reaches the screen:

* **Nothing is smoothed.** The haze beyond the walls is an ordered dither of one added
  colour on the art's own three-pixel grid, not a blur. A real implementation may well
  blur; a mockup that blurred would be showing a treatment nobody has ruled on.
* **Every scale is a whole number.** The magnified farm is nearest-neighbour at exactly
  k times, which is what P-18 requires of it.
"""

import os

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(REPO, "assets", "sprites", "generated")
OUT = os.path.join(REPO, "docs", "design", "mockups", "interiors")

TILE = 16                 # the art's tile
CAM = 3                   # main.gd's CAMERA_SCALE — so a tile is 48 screen pixels
SCREEN = (800, 600)
HUD_TOP, HUD_BOTTOM = 39, 45

# The one colour these sheets add, dithered over everything beyond the walls: the pale
# stone from the style guide's measured ramp, so the haze is a colour the game already
# draws with.
HAZE = (184, 178, 172)
INK = (232, 228, 220)
BACKING = (24, 22, 23)

LABEL_H = 26
GAP = 10


def art(name):
    return Image.open(os.path.join(ART, name + ".png")).convert("RGBA")


def shot(name):
    return Image.open(os.path.join(REPO, "tools", name + ".png")).convert("RGBA")


# --- the haze -----------------------------------------------------------------------

def hazed(im, block=CAM, darken=0.82):
    """Ordered dither of HAZE over the image, on the art's own pixel grid.

    At camera scale 3 a one-pixel dither is invisible and moires against the tiles, so
    the checker is three screen pixels square — one art pixel — which is the same grain
    the overnight's edge dissolve uses.
    """
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            r, g, b = int(r * darken), int(g * darken), int(b * darken)
            if ((x // block) + (y // block)) % 2 == 0:
                # Mixed toward the haze rather than replaced by it. A solid checker
                # of one colour hides the farm completely, and a panel that argues
                # "you cannot see out" by painting over the view is not evidence.
                r = int(r + (HAZE[0] - r) * 0.55)
                g = int(g + (HAZE[1] - g) * 0.55)
                b = int(b + (HAZE[2] - b) * 0.55)
            px[x, y] = (r, g, b, a)
    return im


def tiled(src, w, h):
    out = Image.new("RGBA", (w, h))
    for y in range(0, h, src.height):
        for x in range(0, w, src.width):
            out.paste(src, (x, y))
    return out


# --- Q-108: over the real photograph ------------------------------------------------

def farm_at_screen_scale():
    """The running farm, photographed with the HUD hidden. Tiles are 48 pixels, as on screen."""
    # Cropped to the clean middle of the photograph: the camera letterboxes the top
    # of the farm page with a grey strip and the build stamps its version across the
    # bottom, and both would tile into the haze as furniture that is not the farm.
    plate = shot("shot_outdoor_plate")
    return plate.crop((0, 30, plate.width, plate.height - 66))


def q108_panel(k):
    """The photographed room, with the dark outside its walls replaced by the farm.

    k = 3 magnifies the farm three-fold and is what registering it to the doorway costs;
    k = 1 is the backdrop, the farm at the size it is drawn outdoors.
    """
    plate = shot("shot_interior_plate")
    # The build watermark lives in the dark and is not part of the room.
    ImageDraw.Draw(plate).rectangle([0, 520, SCREEN[0], SCREEN[1]], fill=(0, 0, 0, 255))

    farm = farm_at_screen_scale()
    if k > 1:
        farm = farm.resize((farm.width * k, farm.height * k), Image.NEAREST)
    outside = hazed(tiled(farm, *SCREEN))

    # The black is the mask: anything the game drew as VOID becomes farm.
    room_px, out_px = plate.load(), outside.load()
    for y in range(SCREEN[1]):
        for x in range(SCREEN[0]):
            r, g, b, a = room_px[x, y]
            if a and r + g + b > 60:
                out_px[x, y] = (r, g, b, 255)
    return outside


# --- Q-109: drawn, because no room but this one exists ------------------------------

def room_block(rw, rh, occupant="house"):
    """A room rw x rh inside a one-tile wall ring, furnished with what lives in it.

    The furniture is the point of these panels rather than decoration on them: a bed is
    16x32 and a farmer's cell is 48x48, both at the size the game draws them, so what
    the picture shows is how much floor is left once the things that have to be in the
    room are in it. The coop gets a hen and an egg instead of a bed, because a panel
    that put a bed in a hen house would be measuring the wrong room.
    """
    floor = art("terrain_floor").crop((TILE, TILE, TILE * 2, TILE * 2))
    wall = art("interior_wall")
    block = Image.new("RGBA", ((rw + 2) * TILE, (rh + 2) * TILE))
    for ty in range(rh + 2):
        for tx in range(rw + 2):
            edge = tx in (0, rw + 1) or ty in (0, rh + 1)
            block.paste(wall if edge else floor, (tx * TILE, ty * TILE))
    block.paste(floor, (((rw + 2) // 2) * TILE, (rh + 1) * TILE))   # the doorway

    if occupant == "house":
        cot = art("cot").crop((0, 0, TILE, TILE * 2))
        block.paste(cot, (TILE, TILE), cot)
    else:
        hen = art("chicken").crop((0, 0, TILE, TILE))               # cell 0, facing right
        block.paste(hen, (TILE, TILE * 2), hen)
        egg = art("egg")
        block.paste(egg, (TILE * 2, TILE * 2), egg)
        block.paste(egg, (TILE, TILE * 3), egg)

    her = art("characters").crop((0, 0, 48, 48))
    block.paste(her, (TILE + (rw * TILE) // 2 - 24, TILE + (rh * TILE) // 2 - 24), her)
    return block.resize((block.width * CAM, block.height * CAM), Image.NEAREST)


def q109_panel(rw, rh, cell, occupant):
    """One room, on a fixed canvas so the panels compare room and not zoom."""
    canvas = Image.new("RGBA", cell, BACKING + (255,))
    block = room_block(rw, rh, occupant)
    canvas.paste(block, ((cell[0] - block.width) // 2, (cell[1] - block.height) // 2), block)
    return canvas


# --- sheets -------------------------------------------------------------------------

def sheet(panels, captions, path, note=""):
    w = sum(p.width for p in panels) + GAP * (len(panels) - 1)
    h = panels[0].height + LABEL_H + (LABEL_H if note else 0)
    out = Image.new("RGBA", (w, h), BACKING + (255,))
    d = ImageDraw.Draw(out)
    x = 0
    for p, text in zip(panels, captions):
        out.paste(p, (x, LABEL_H))
        d.text((x + 6, 8), text, fill=INK)
        x += p.width + GAP
    if note:
        d.text((6, panels[0].height + LABEL_H + 8), note, fill=HAZE)
    out.save(path)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    written = []

    written.append(sheet(
        [q108_panel(3), q108_panel(1)],
        ["(a) REGISTERED - the farm magnified 3x, true to the doorway",
         "(b) BACKDROP - the farm at the size it is drawn outdoors"],
        os.path.join(OUT, "q108_outside_treatment.png"),
        note="Her real room, photographed. Everything outside its walls is black in the game today; "
             "that black is what each panel fills."))

    # Both buildings, at each multiplier, every panel on the same canvas at the same
    # zoom — so what differs between them is how much room there is, and nothing else.
    for name, fp, label in (("farmhouse", (3, 2), "farmhouse, 3x2 outside, with her bed in it"),
                            ("coop", (2, 2), "coop, 2x2 outside, with the hen in it")):
        # Wide enough that the largest room still has air around it — a panel whose
        # walls run off its own edge reads as cramped for a reason that is the
        # panel's rather than the room's.
        cell = (16 * TILE * CAM, 12 * TILE * CAM)
        panels = [q109_panel(fp[0] * k, fp[1] * k, cell, name) for k in (2, 3, 4)]
        caps = ["x%d - a %dx%d room" % (k, fp[0] * k, fp[1] * k) for k in (2, 3, 4)]
        written.append(sheet(panels, caps,
            os.path.join(OUT, "q109_%s_multipliers.png" % name),
            note="%s. Everything at the size the game draws it. "
                 "The same number also sets how hard the farm magnifies behind the walls "
                 "(see the Q-108 sheet)." % label))

    for p in written:
        print("wrote", os.path.relpath(p, REPO))


if __name__ == "__main__":
    main()

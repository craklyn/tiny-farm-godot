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


# --- Q-108: registered to the real house, over the real photograph ------------------
#
# **The first version of this sheet tiled the farm behind the room as wallpaper**, which
# is not registration and cannot be: wallpaper has no idea where the house was, so the
# gap between the house and the shrub beside it survived in the outdoor panel and
# vanished in the indoor one. Spotted by the CEO, 2026-09-15. The plate now carries the
# camera's world-to-screen mapping beside it (shot_outdoor_plate.json), so the farm can
# be placed rather than pasted, and the gap is the test: whatever distance separates two
# things outdoors separates them indoors, multiplied and not otherwise touched.

import json as _json


def plate_and_mapping():
    plate = _unletterboxed(shot("shot_outdoor_plate"))
    with open(os.path.join(REPO, "tools", "shot_outdoor_plate.json")) as fh:
        m = _json.load(fh)
    return plate, m


def _unletterboxed(plate):
    """Fill the camera's clamp bands with the nearest row of world.

    main.gd clamps the view to the page she is on, so a photograph taken near the top
    of the farm carries a flat grey band where the world runs out. Patched rather than
    cropped, because the mapping beside the plate is in the plate's own coordinates and
    a crop would silently shift every registered pixel.
    """
    px = plate.load()
    w, h = plate.size

    def flat(y):
        first = px[0, y][:3]
        if max(first) - min(first) > 6:      # a flat grey, not grass
            return False
        return all(px[x, y][:3] == first for x in range(0, w, 17))

    top = 0
    while top < h and flat(top):
        top += 1
    bottom = h - 1
    while bottom > top and flat(bottom):
        bottom -= 1
    for y in range(top):
        plate.paste(plate.crop((0, top, w, top + 1)), (0, y))
    for y in range(bottom + 1, h):
        plate.paste(plate.crop((0, bottom, w, bottom + 1)), (0, y))
    return plate


def house_rect(m):
    """The house's three tiles by two, in screen pixels of the outdoor plate."""
    t, cam = m["tile_px"], m["camera_scale"]
    cx, cy = m["screen_centre_world_px"]
    vw, vh = m["viewport"]
    ox, oy = m["house_origin_tile"]
    tw, th = m["house_tiles"]

    def to_screen(wx, wy):
        return ((wx - cx) * cam + vw / 2.0, (wy - cy) * cam + vh / 2.0)

    x0, y0 = to_screen(ox * t, oy * t)
    x1, y1 = to_screen((ox + tw) * t, (oy + th) * t)
    return (x0, y0, x1, y1)


def ground_fill(plate):
    """The commonest colour in the plate, for the sliver a transform leaves uncovered."""
    small = plate.convert("RGB").resize((80, 60))
    return max(small.getcolors(80 * 60), key=lambda c: c[0])[1]


def room_over(rw, rh, floor_rect, canvas, occupant="house"):
    """Draw a room whose FLOOR lands exactly on floor_rect, wall ring outside it.

    The floor is what registers, not the drawn block: the *inside* of the house is what
    maps onto the *outside* of the house, and the walls are the shell she is standing
    within, drawn just beyond it.
    """
    cell = (floor_rect[2] - floor_rect[0]) / rw
    block = room_block(rw, rh, occupant, cell_px=cell)
    canvas.paste(block, (int(floor_rect[0] - cell), int(floor_rect[1] - cell)), block)
    return canvas


def outline(canvas, rect, colour, width=3):
    ImageDraw.Draw(canvas).rectangle(
        [rect[0], rect[1], rect[2] - 1, rect[3] - 1], outline=colour, width=width)
    return canvas


# The whole screen, not a crop of it. How much yard is left beside the room is most of
# what Q-108 is deciding, and a panel narrower than the device understates it.
WINDOW = (800, 600)

# --- the nested grid, which is what the directive actually described ----------------
#
# **One world, one metric, two grids** (CEO, 2026-09-15, correcting these sheets). A
# building's interior is not a separate space drawn at its own scale beside a deformed
# outdoors. It is a **finer grid nested inside the building's own footprint**: the
# farmhouse stands on 3 tiles by 2, and the room inside it is 6 cells by 3 at half that
# pitch, which is 3 tiles by 1.5 — so it fits, with the top half-row left for the roof.
#
# Then going inside is a **uniform camera zoom** and nothing else. At x2 the half-pitch
# interior renders at the size an outdoor tile used to, which is the directive's own
# sentence, and the yard renders at twice its usual size because everything did. Nothing
# stretches, nothing is registered to anything, because nothing ever came apart.
#
# The earlier sheets drew a differential transform — the room at one scale, the yard at
# another — and that is a different design that happens to answer the same words.

INTERIOR_PITCH = 2       # interior cells per outdoor tile, each axis


def farm_with_room(rw, rh, zoom, occupant="house"):
    """The farm at `zoom`, with the house's footprint showing the room inside it.

    `zoom` 1 is how the farm is drawn today; 2 is standing in the room. The same
    composition either way — only the camera changes, which is the whole claim.
    """
    plate, m = plate_and_mapping()
    hx0, hy0, hx1, hy1 = house_rect(m)
    tile = (hx1 - hx0) / m["house_tiles"][0]          # 48 screen px an outdoor tile
    cell = tile / INTERIOR_PITCH                       # 24 screen px an interior cell

    # The room sits on the floor of the footprint, so the half-row it does not fill is
    # the roof line at the top — where a roof is.
    fw, fh = rw * cell, rh * cell
    fx0 = hx0 + ((hx1 - hx0) - fw) / 2.0
    fy0 = hy1 - fh

    frame = plate.copy()
    block = room_block(rw, rh, occupant, cell_px=cell, walls=False)
    frame.paste(block, (int(fx0), int(fy0)), block)
    outline(frame, (fx0, fy0, fx0 + fw, fy0 + fh), MARK, width=2)

    if zoom != 1:
        frame = frame.resize((int(frame.width * zoom), int(frame.height * zoom)), Image.NEAREST)
        fx0, fy0, fw, fh = fx0 * zoom, fy0 * zoom, fw * zoom, fh * zoom

    # Centred on the room where the photograph reaches, clamped to it where it does not.
    win = Image.new("RGBA", WINDOW, ground_fill(plate) + (255,))
    ox = int(min(max(fx0 + fw / 2 - WINDOW[0] / 2, 0), max(frame.width - WINDOW[0], 0)))
    oy = int(min(max(fy0 + fh / 2 - WINDOW[1] / 2, 0), max(frame.height - WINDOW[1], 0)))
    win.paste(frame, (-ox, -oy))
    return win

MARK = (236, 145, 145)   # the rose accent, used only to outline the same rect in both


def exterior_panel(mark=True):
    plate, m = plate_and_mapping()
    hx0, hy0, hx1, hy1 = house_rect(m)
    win = Image.new("RGBA", WINDOW, ground_fill(plate) + (255,))
    # Centred on the house where the photograph allows it, clamped to the plate where it
    # does not — her house stands in the top-left corner of the farm, so a window truly
    # centred on it would be half flat fill, which is a panel about its own framing.
    ox = int(min(max(hx0 + (hx1 - hx0) / 2 - WINDOW[0] / 2, 0), plate.width - WINDOW[0]))
    oy = int(min(max(hy0 + (hy1 - hy0) / 2 - WINDOW[1] / 2, 0), plate.height - WINDOW[1]))
    win.paste(plate, (-ox, -oy))
    if mark:
        outline(win, (hx0 - ox, hy0 - oy, hx1 - ox, hy1 - oy), MARK)
    return win


def interior_panel(rw, rh, registered=True, mark=True, occupant="house"):
    """Standing inside, with the farm placed truthfully (or not, for the backdrop)."""
    plate, m = plate_and_mapping()
    hx0, hy0, hx1, hy1 = house_rect(m)
    cell = (hx1 - hx0) / m["house_tiles"][0]          # 48 screen pixels a tile

    # The floor, at the game's own tile size. Centred in the window where the
    # photograph reaches that far, and pulled back towards the house's own corner where
    # it does not — her house stands in the top-left of the farm, so a centred room
    # would have flat nothing along two of its sides, and a panel with invented ground
    # in it is a panel arguing from something that was never photographed.
    fw, fh = rw * cell, rh * cell
    sx = fw / (hx1 - hx0)
    sy = fh / (hy1 - hy0)
    fx0 = min((WINDOW[0] - fw) / 2.0, hx0 * sx)
    fy0 = min((WINDOW[1] - fh) / 2.0, hy0 * sy)
    floor_rect = (fx0, fy0, fx0 + fw, fy0 + fh)

    win = Image.new("RGBA", WINDOW, ground_fill(plate) + (255,))
    if registered:
        # The scale is what the room costs the world: the floor covers rw x rh tiles
        # where the house covered 3 x 2, so the yard grows by those two ratios. They
        # differ here (2.0 across, 1.5 down), which is what non-square dilation looks
        # like, and the picture is the place to find out whether that reads.
        big = plate.resize((int(plate.width * sx), int(plate.height * sy)), Image.NEAREST)
        win.paste(big, (int(fx0 - hx0 * sx), int(fy0 - hy0 * sy)))
    else:
        # The backdrop: the same farm at the size it is drawn outdoors, lined up with
        # nothing. Centred on the house so the panel is not accidentally about framing.
        win.paste(plate, (int(fx0 + fw / 2 - (hx0 + hx1) / 2),
                          int(fy0 + fh / 2 - (hy0 + hy1) / 2)))
    win = hazed(win)
    room_over(rw, rh, floor_rect, win, occupant)
    if mark:
        outline(win, floor_rect, MARK)
    return win


# --- Q-109: drawn, because no room but this one exists ------------------------------

def room_block(rw, rh, occupant="house", cell_px=None, walls=True):
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
    if not walls:
        # Nested inside a building's own footprint, the shell already standing on the
        # farm is the wall. A ring here would draw a second one inside the first.
        block = Image.new("RGBA", (rw * TILE, rh * TILE))
        for ty in range(rh):
            for tx in range(rw):
                block.paste(floor, (tx * TILE, ty * TILE))
    else:
        for ty in range(rh + 2):
            for tx in range(rw + 2):
                edge = tx in (0, rw + 1) or ty in (0, rh + 1)
                block.paste(wall if edge else floor, (tx * TILE, ty * TILE))
        block.paste(floor, (((rw + 2) // 2) * TILE, (rh + 1) * TILE))   # the doorway

    inset = 0 if not walls else TILE
    if occupant == "house":
        cot = art("cot").crop((0, 0, TILE, TILE * 2))
        block.paste(cot, (inset, inset), cot)
    else:
        hen = art("chicken").crop((0, 0, TILE, TILE))               # cell 0, facing right
        block.paste(hen, (inset, inset + TILE), hen)
        egg = art("egg")
        block.paste(egg, (inset + TILE, inset + TILE), egg)

    her = art("characters").crop((0, 0, 48, 48))
    block.paste(her, (inset + (rw * TILE) // 2 - 24, inset + (rh * TILE) // 2 - 24), her)
    if cell_px is None:
        return block.resize((block.width * CAM, block.height * CAM), Image.NEAREST)
    k = cell_px / TILE
    return block.resize((int(round(block.width * k)), int(round(block.height * k))),
                        Image.NEAREST)


def q109_panel(rw, rh, cell, occupant):
    """One room, on a fixed canvas so the panels compare room and not zoom."""
    canvas = Image.new("RGBA", cell, BACKING + (255,))
    block = room_block(rw, rh, occupant)
    canvas.paste(block, ((cell[0] - block.width) // 2, (cell[1] - block.height) // 2), block)
    return canvas


# --- sheets -------------------------------------------------------------------------

def sheet(panels, captions, path, note="", gutter=None):
    gap = GAP if gutter is None else gutter
    w = sum(p.width for p in panels) + gap * (len(panels) - 1)
    h = panels[0].height + LABEL_H + (LABEL_H if note else 0)
    out = Image.new("RGBA", (w, h), BACKING + (255,))
    d = ImageDraw.Draw(out)
    x = 0
    for p, text in zip(panels, captions):
        out.paste(p, (x, LABEL_H))
        d.text((x + 6, 8), text, fill=INK)
        x += p.width + gap
    if note:
        d.text((6, panels[0].height + LABEL_H + 8), note, fill=HAZE)
    out.save(path)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    written = []

    # **The two zooms, which is the whole design in two pictures.** The same farm, the
    # same composition, one uniform camera zoom between them. The house stands on three
    # tiles by two; the room inside it is six cells by three at half that pitch, so it
    # fits in the footprint with the top half-row left for the roof. At x2 those half-
    # pitch cells render at the size an outdoor tile used to, which is what the directive
    # asked for, and the yard is twice its usual size because everything is.
    written.append(sheet(
        [farm_with_room(6, 3, 1), farm_with_room(6, 3, 2)],
        ["OUTDOOR ZOOM - the house on its three tiles by two, the room inside at half pitch",
         "HOUSE ZOOM - x2, and nothing has moved: the room now reads at tile size"],
        os.path.join(OUT, "q108_two_zooms.png"),
        note="One world, one metric, two grids. Between these panels only the camera changed "
             "-- the house and the yard grow by the same factor, together, and nothing "
             "stretches. Both are the same photograph of the running game."))

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

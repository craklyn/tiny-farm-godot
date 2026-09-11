#!/usr/bin/env python3
"""Draw the candidate overnight frames over real captures of the overnight.

The overnight plays an Animation Lab loop on the night the farm changed, today with
no frame around it (design/09, "How a loop is shown"). Three frames were asked for as
candidates — a postcard, a viewfinder and a dream — and this draws each of them over
the screens tools/capture_overnight_plates.tscn photographed, plus the unframed screen
that ships today, so the four are compared as pictures rather than as descriptions.

    python3 tools/compose_overnight_frames.py

Reads docs/design/mockups/overnight_frames/plate_*.png and writes the eight option
sheets beside them. Needs no display; the plates carry the game's own rendering.

Two rules the drawing keeps, because they are the studio's rules for anything that
reaches the screen:

* **Every colour is one the game already uses.** The frames add exactly two: the
  dirt base and the teal accent from the style guide (docs/design/09). Every other
  colour on these sheets is either a loop pixel or the Lab's night.
* **Nothing is smoothed.** There is no blur and no half-transparency anywhere. Round
  corners step on the picture's own pixel grid, and every soft edge is an ordered
  dither — the same 4×4 matrix the overnight already uses to dissolve a loop's
  canvas edge into the night (systems/day_cycle.gd).
"""

import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "design", "mockups", "overnight_frames")

# The Lab's night, and the colour every fade in the overnight goes to.
SKY = (33, 31, 32)

# The two colours the frames add, both off the style guide's measured ramps
# (docs/design/09, "Palette discipline"): the dirt base, which is the warm light
# the farm's own ground is drawn in, and the teal accent.
#
# The teal is the one that needs saying out loud. Cyan is reserved for the
# repellent scent overlay (P-10/D-4) and must never appear in the ambient world;
# this is the accent teal, a different hue, and it only appears here because the
# overnight is the one screen with no world on it.
CREAM = (232, 207, 166)
TEAL = (140, 191, 194)

# The ordered-dither matrix day_cycle.gd dissolves a loop's canvas edge with.
BAYER4 = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=np.float64) / 16.0

SCREEN_W, SCREEN_H = 800, 600


class Plate:
    """One captured screen, and where the loop sits inside it.

    The loop is centred at the largest whole-number scale that fits the screen
    (day_cycle.gd), so its rectangle follows from the sheet's cell size and needs
    no measuring. `scale` may be forced for a plate captured one step smaller.
    """

    def __init__(self, name, slug, scale=None):
        self.name = name
        self.slug = slug
        self.img = Image.open(os.path.join(OUT, name)).convert("RGB")
        manifest_path = os.path.join(REPO, "assets", "anim", slug, "manifest.json")
        with open(manifest_path) as fh:
            manifest = json.load(fh)
        cw, ch = int(manifest["cell_width"]), int(manifest["cell_height"])
        self.unit = scale or max(1, min(SCREEN_W // cw, SCREEN_H // ch))
        self.w, self.h = cw * self.unit, ch * self.unit
        self.x = (SCREEN_W - self.w) // 2
        self.y = (SCREEN_H - self.h) // 2

    def pixels(self):
        return np.array(self.img, dtype=np.uint8)

    def cell_grid(self):
        """Column and row index of every screen pixel on the loop's own pixel grid.

        Counted from the loop's top-left corner, so a frame drawn in these cells
        lines up with the picture's pixels instead of cutting across them.
        """
        xs = (np.arange(SCREEN_W) - self.x) // self.unit
        ys = (np.arange(SCREEN_H) - self.y) // self.unit
        return np.meshgrid(xs, ys)


def bayer_of(cols, rows):
    return BAYER4[np.mod(rows, 4), np.mod(cols, 4)]


def save(arr, option, plate):
    path = os.path.join(OUT, "%s_%s.png" % (option, plate.slug))
    Image.fromarray(arr.astype(np.uint8)).save(path)
    print("wrote -> %s" % os.path.relpath(path, REPO))


# --- A, what ships today -----------------------------------------------------

def option_none(plate):
    save(plate.pixels(), "a_none", plate)


# --- B, the postcard ---------------------------------------------------------
#
# A card of night behind the loop with a thin light border and rounded corners, and
# the Day-N type beneath it. The border is one of the picture's own pixels thick and
# its corners step on the picture's own grid, so it reads as part of the image rather
# than as a window the operating system drew.

PAD_CELLS = 3      # night between the picture and the border
BORDER_CELLS = 1   # the border itself
RADIUS_CELLS = 4   # how far the corner is cut back


def _rounded_mask(cols, rows, left, top, right, bottom, radius):
    """Cells inside a rounded rectangle, with the corners stepped, not smoothed."""
    inside = (cols >= left) & (cols <= right) & (rows >= top) & (rows <= bottom)
    for cx, cy, sx, sy in (
        (left + radius, top + radius, -1, -1),
        (right - radius, top + radius, 1, -1),
        (left + radius, bottom - radius, -1, 1),
        (right - radius, bottom - radius, 1, 1),
    ):
        corner = ((cols - cx) * sx > 0) & ((rows - cy) * sy > 0)
        far = (cols - cx) ** 2 + (rows - cy) ** 2 > radius ** 2
        inside &= ~(corner & far)
    return inside


def option_postcard(plate, type_crop):
    arr = plate.pixels()
    cols, rows = plate.cell_grid()
    cw = plate.w // plate.unit
    ch = plate.h // plate.unit

    reach = PAD_CELLS + BORDER_CELLS
    outer = _rounded_mask(cols, rows, -reach, -reach, cw - 1 + reach, ch - 1 + reach,
                          RADIUS_CELLS)
    inner = _rounded_mask(cols, rows, -PAD_CELLS, -PAD_CELLS,
                          cw - 1 + PAD_CELLS, ch - 1 + PAD_CELLS,
                          RADIUS_CELLS)
    arr[outer & ~inner] = CREAM

    # The Day-N type beneath the card, in the band the card leaves free: the game's
    # own label, lifted off a capture rather than redrawn in a lookalike font.
    card_bottom = plate.y + plate.h + reach * plate.unit
    band = SCREEN_H - card_bottom
    th, tw = type_crop.shape[0], type_crop.shape[1]
    ty = card_bottom + (band - th) // 2
    tx = (SCREEN_W - tw) // 2
    if ty >= 0 and ty + th <= SCREEN_H:
        arr[ty:ty + th, tx:tx + tw] = type_crop
    else:
        print("  note: no room under the card for the Day-N type on %s" % plate.slug,
              file=sys.stderr)
    save(arr, "b_postcard", plate)


# --- C, the viewfinder -------------------------------------------------------
#
# Four corner brackets just outside the picture and a faint scan line across it. The
# scan line adds no colour at all: every fourth row of the picture has half its pixels
# replaced by the night behind it, in a checker, which dims the row without tinting it.

ARM_CELLS = 8
SCAN_EVERY = 4


def option_viewfinder(plate):
    arr = plate.pixels()
    cols, rows = plate.cell_grid()
    cw = plate.w // plate.unit
    ch = plate.h // plate.unit

    picture = (cols >= 0) & (cols < cw) & (rows >= 0) & (rows < ch)
    scan = picture & (np.mod(rows, SCAN_EVERY) == 0) & (np.mod(cols + rows, 2) == 0)
    arr[scan] = SKY

    # Inside the picture's corners, not outside them. The crow gorge fills the screen
    # to within sixteen pixels, so brackets set outside it would be half off the
    # screen on that night and comfortably clear on the other.
    for ox, oy, toward_x, toward_y in ((1, 1, 1, 1),
                                       (cw - 2, 1, -1, 1),
                                       (1, ch - 2, 1, -1),
                                       (cw - 2, ch - 2, -1, -1)):
        horizontal = (rows == oy) & _between(cols, ox, ox + toward_x * (ARM_CELLS - 1))
        vertical = (cols == ox) & _between(rows, oy, oy + toward_y * (ARM_CELLS - 1))
        arr[horizontal | vertical] = TEAL
    save(arr, "c_viewfinder", plate)


def _between(values, a, b):
    return (values >= min(a, b)) & (values <= max(a, b))


# --- D, the dream ------------------------------------------------------------
#
# The picture keeps its middle and dissolves into the night towards its edges, along a
# boundary that wanders instead of running true, so the edge reads as cloud rather than
# as an ellipse. The dissolve is the ordered dither, so there is no partial colour
# anywhere: a pixel is the loop's or it is the night's.

INNER = 0.74   # kept whole out to this share of the half-width
OUTER = 1.16   # fully night past this


def option_dream(plate):
    arr = plate.pixels()
    cols, rows = plate.cell_grid()
    cw = plate.w // plate.unit
    ch = plate.h // plate.unit

    dx = (cols + 0.5 - cw / 2.0) / (cw / 2.0)
    dy = (rows + 0.5 - ch / 2.0) / (ch / 2.0)
    radius = np.sqrt(dx * dx + dy * dy)
    angle = np.arctan2(dy, dx)
    # Three slow waves around the circle, no two in step, so the boundary never
    # repeats itself on the way round.
    wander = (1.0
              + 0.10 * np.sin(3.0 * angle + 0.7)
              + 0.07 * np.sin(5.0 * angle + 2.1)
              + 0.05 * np.sin(7.0 * angle + 4.3))
    t = (radius - INNER * wander) / ((OUTER - INNER) * wander)
    t = np.clip(t, 0.0, 1.0)
    arr[t > bayer_of(cols, rows)] = SKY
    save(arr, "d_dream", plate)


# --- the type ----------------------------------------------------------------

def day_type_crop():
    """The Day-N label's own pixels, cut off the capture of the card."""
    img = np.array(Image.open(os.path.join(OUT, "plate_day_type.png")).convert("RGB"))
    ink = np.any(img != np.array(SKY, dtype=np.uint8), axis=2)
    ys, xs = np.nonzero(ink)
    if ys.size == 0:
        raise SystemExit("plate_day_type.png has no type on it — re-run the capture")
    return img[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def main():
    type_crop = day_type_crop()
    shipped = [Plate("plate_crow_night.png", "crow_gorge"),
               Plate("plate_robot_night.png", "seeder_bot")]
    # The postcard needs room outside the picture for its border and the type. The
    # seeder robot already has it; the crow gorge does not at the scale it ships at,
    # so its postcard is drawn over the plate taken one whole step smaller.
    postcard = [Plate("plate_crow_night_x5.png", "crow_gorge", scale=5),
                Plate("plate_robot_night.png", "seeder_bot")]

    for plate in shipped:
        option_none(plate)
    for plate in postcard:
        option_postcard(plate, type_crop)
    for plate in shipped:
        option_viewfinder(plate)
    for plate in shipped:
        option_dream(plate)


if __name__ == "__main__":
    main()

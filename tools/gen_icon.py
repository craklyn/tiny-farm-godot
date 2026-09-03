#!/usr/bin/env python3
"""Compose the app icon at every size the platforms ask for (T-38).

The tablet showed a plain blue box on the taskbar for months, and the cause was
not a missing file: `icon.svg` existed and was wired up. It was a rounded blue
rectangle with the letters "TF" in an SVG `<text>` element, and **Godot's SVG
rasteriser does not render text**. The rectangle drew, the letters did not, and
nothing anywhere reported an error. Any icon that ships from here on is a PNG
for exactly that reason.

## What the picture is

The designer's brief, in their own words: the farmer, and "at least one piece of
iconography that's more clearly farmer — either a farm implement, or a farm
identifier, or a piece of clothing", with the note that a near-future read is
welcome because "late game there will be many elements of technology" and the
farm learns to defend itself. So: her face under a wide straw hat, goggles
pushed up on the brim, an axe leaning at her shoulder, and a drone hovering off
the hat.

Four things is one thing too many for an icon, and the layout below is the
result of testing that claim rather than asserting it. Every candidate was
rendered at 48 pixels — the size a launcher actually draws — before being
judged, because at that size only the silhouette survives:

- **The straw hat is doing the work.** Overalls and a face read as "a person";
  the brim is what reads as "a farm". It changes the outline, and outline is all
  that is left when the icon is shrunk.
- **A hoe was tried first and abandoned.** The generator would not produce one
  (it returned spades for three differently-worded prompts), and the two drawn
  by hand — one upright, one leaning — both read as a fencepost at small size: a
  long thin handle is a line, and a line is not a tool. The designer then opened
  the door to any implement, and an axe settled it. A wedge head is a *mass*,
  and mass survives being shrunk.
- **A terracotta watering can lost to the axe** for a reason worth writing down:
  it was perfectly legible on its own and vanished in place, because its warm
  orange sat on top of her rust jumpsuit. Contrast against the *background* is
  not enough; a companion element needs contrast against whatever it overlaps.

## Sizes, and why the two icons are not the same picture

Android draws two different things and masks them differently, so this composes
the layout per size rather than scaling one master:

- **Legacy 192** is the flat icon. The subject fills about 63% of it.
- **Adaptive 432** is masked to a circle or squircle by the launcher, and only
  the centre ~66% is guaranteed visible. Its foreground is inset into that safe
  zone and its background is a separate full-bleed layer, which is why the
  subject is deliberately *smaller* here rather than a bug.

Every part is scaled by a whole number (NEAREST) so the pixel grid never lands
half on a pixel. That is also why the subject fraction differs slightly between
sizes: the factor is rounded to an integer, and a blurred icon is a worse
outcome than a subject three percent off its mark.

Sources in `assets/icon/parts/` are Retro Diffusion generations, already
background-keyed and trimmed so this script needs nothing but Pillow (see
CREDITS.md for prompts, rights and cost).

    python3 tools/gen_icon.py
"""
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = os.path.join(ROOT, "assets", "icon", "parts")
OUT = os.path.join(ROOT, "assets", "icon")

# The field the icon sits on. Deeper and more saturated than the game's own
# grass (#c0d470): the in-game pale is right for a screen you stare at for ten
# minutes and wrong for a 48-pixel tile competing with a wallpaper.
FIELD_TOP = "#6d9a52"
FIELD_BOTTOM = "#3f5f33"
VIGNETTE = 0.22  # corners darkened, so the subject holds up under a round mask

# Layout, in fractions of the content box. Anchors are top-left corners; the
# farmer is centred horizontally, so only her vertical anchor is given. The
# parts carry their own proportions — they are drawn at the size the art is,
# times the box's shared factor — so there is nothing here to keep in sync.
FARMER_Y = 0.28
AXE_XY = (0.00, 0.44)
DRONE_XY = (0.52, 0.05)

# How much of an adaptive canvas the arrangement uses. Android guarantees only
# the central 66%, but an icon built to that is visibly timid next to its
# neighbours, and no shipping launcher mask actually crops to it. 78% is the
# width at which the axe head and the drone's outer rotors still clear a circle.
SAFE_BOX = 0.78


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def part(name):
    return Image.open(os.path.join(PARTS, f"{name}.png")).convert("RGBA")


def upscale(im, factor):
    return im.resize((im.width * factor, im.height * factor), Image.NEAREST)


def box_factor(box):
    """The one whole-number scale every part shares inside a content box.

    Scaling each part to its own fraction independently looks equivalent and is
    not: the factors round in different directions, and the parts drift out of
    proportion with each other. The first cut of this script did that, and at
    432 the axe rounded up far enough to land across her face. The layout was
    drawn and approved on a 192 box with the parts at 1:1, so every other box is
    that same arrangement at a whole multiple.
    """
    return max(1, round(box / 192))


def field(size, vignette=VIGNETTE):
    top, bottom = _hex(FIELD_TOP), _hex(FIELD_BOTTOM)
    im = Image.new("RGBA", (size, size))
    px = im.load()
    centre = (size - 1) / 2
    longest = math.hypot(centre, centre)
    for y in range(size):
        q = y / (size - 1)
        base = tuple(int(top[i] + (bottom[i] - top[i]) * q) for i in range(3))
        for x in range(size):
            if vignette:
                d = math.hypot(x - centre, y - centre) / longest
                k = 1.0 - vignette * max(0.0, (d - 0.55) / 0.45)
                px[x, y] = tuple(int(c * k) for c in base) + (255,)
            else:
                px[x, y] = base + (255,)
    return im


def subject(size, box_frac=1.0):
    """The farmer, her axe and the drone on transparency.

    `box_frac` is how much of the canvas the arrangement is allowed to use. The
    flat icon takes all of it; an adaptive foreground takes a centred slice, so
    the launcher's mask cannot cut a wing off the drone or the head off the axe.
    """
    canvas = Image.new("RGBA", (size, size))
    box = size * box_frac
    origin = (size - box) / 2
    f = box_factor(box)

    def at(fx, fy):
        return (int(origin + box * fx), int(origin + box * fy))

    farmer = upscale(part("farmer"), f)
    axe = upscale(part("axe"), f)
    drone = upscale(part("drone"), f)

    _, fy = at(0, FARMER_Y)
    canvas.alpha_composite(farmer, ((size - farmer.width) // 2, fy))
    # The axe goes on *top* of her: behind the brim it was swallowed whole.
    canvas.alpha_composite(axe, at(*AXE_XY))
    canvas.alpha_composite(drone, at(*DRONE_XY))
    return canvas


def icon(size):
    """The flat, full-bleed icon: subject on its field."""
    out = field(size)
    out.alpha_composite(subject(size))
    return out


def adaptive_foreground(size=432):
    """The subject on transparency, kept inside the launcher mask's safe zone."""
    return subject(size, box_frac=SAFE_BOX)


def resample(im, size):
    """Down to an awkward size (PWA asks for 180) — BOX, and only ever downward."""
    return im.resize((size, size), Image.BOX)


def main():
    os.makedirs(OUT, exist_ok=True)
    master = icon(432)

    written = []

    def write(im, path):
        im.save(path)
        written.append((os.path.relpath(path, ROOT), im.size))

    # Godot's own project icon (window and editor). PNG, never SVG — see above.
    write(icon(192), os.path.join(ROOT, "icon.png"))

    # Android: the flat legacy icon plus the two adaptive layers.
    write(icon(192), os.path.join(OUT, "launcher_192.png"))
    write(adaptive_foreground(432), os.path.join(OUT, "adaptive_foreground_432.png"))
    write(field(432, vignette=0.0), os.path.join(OUT, "adaptive_background_432.png"))

    # Web / PWA. 144 is a clean third of 432; 180 and 512 are not, so they are
    # resampled from the master rather than composed at an off-grid scale.
    write(resample(master, 144), os.path.join(OUT, "pwa_144.png"))
    write(resample(master, 180), os.path.join(OUT, "pwa_180.png"))
    write(icon(512), os.path.join(OUT, "pwa_512.png"))

    for path, size in written:
        print(f"  {path:44s} {size[0]}x{size[1]}")


if __name__ == "__main__":
    sys.exit(main())

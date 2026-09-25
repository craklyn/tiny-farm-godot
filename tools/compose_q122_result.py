#!/usr/bin/env python3
"""Draw the Q-122 before/after board from the real in-game captures.

    xvfb-run -a godot --path . res://tools/capture_q122_result.tscn -- --tag=before
    xvfb-run -a godot --path . res://tools/capture_q122_result.tscn -- --tag=after
    python3 tools/compose_q122_result.py

Reads `docs/design/mockups/q122_result/farm_before.png` and `farm_after.png` (both
the same seeded world, same camera, same tile positions — `tools/capture_q122_result.gd`)
and crops the rock and the fox out of each, enlarged side by side. Needs no display;
the captures carry the game's own rendering.
"""
import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "design", "mockups", "q122_result")

GROUND = (33, 31, 32)
INK = (232, 207, 166)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SCALE = 5

# (label, crop box in the 800x600 capture)
ROCK_BOX = (550, 380, 670, 480)
FOX_BOX = (360, 230, 460, 330)


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def crop(tag, box):
    im = Image.open(os.path.join(OUT, f"farm_{tag}.png")).convert("RGB")
    return im.crop(box)


def board(name, box, captions):
    size = ((box[2] - box[0]) * SCALE, (box[3] - box[1]) * SCALE)
    before = crop("before", box).resize(size, Image.NEAREST)
    after = crop("after", box).resize(size, Image.NEAREST)

    strip = 34
    gap = 16
    w = before.width + after.width + gap * 3
    h = max(before.height, after.height) + strip + gap * 2
    sheet = Image.new("RGB", (w, h), GROUND)
    draw = ImageDraw.Draw(sheet)
    f = font(18)
    draw.text((gap, gap), captions[0], font=f, fill=INK)
    sheet.paste(before, (gap, gap + strip))
    x2 = gap * 2 + before.width
    draw.text((x2, gap), captions[1], font=f, fill=INK)
    sheet.paste(after, (x2, gap + strip))

    path = os.path.join(OUT, f"{name}_before_after.png")
    sheet.save(path)
    print(f"composed -> {os.path.relpath(path, REPO)}")


def main():
    if not os.path.isfile(os.path.join(OUT, "farm_before.png")):
        raise SystemExit(
            "missing farm_before.png / farm_after.png — run capture_q122_result.tscn "
            "with --tag=before and --tag=after first (see this script's docstring)")
    board("rock", ROCK_BOX, ("rock — before (55 colours)", "rock — after (10 colours)"))
    board("fox", FOX_BOX, ("fox — before (24 colours, as shipped)", "fox — after (4 colours, redrawn)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

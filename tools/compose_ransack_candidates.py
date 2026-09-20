#!/usr/bin/env python3
"""Put the four things a raided square could look like side by side, labelled.

    python3 tools/compose_ransack_candidates.py

Reads the plates photographed in the running game on 2026-09-19 and writes two
comparison boards beside them in docs/design/mockups/ransack_mark/:

    candidates.png           the four squares close up, blown up ×3
    candidates_in_place.png  the same four at the size the game is played at

Needs no display — the plates carry the game's own rendering, and this only crops,
tiles and labels them. Every panel is the same farm, the same camera and the same
morning; the only difference between them is what is drawn on the one square a
crow emptied.

The rig that took the plates is gone. It could only exist while three of the four
pictures were candidates, and it drew them through the renderer's insides to keep
them out of `world/`; once the designer picked (b) on 2026-09-19 those insides
changed and the rig could no longer run. The plates are kept as the record of
what the winner was picked over, this rebuilds the boards from them, and
`tools/capture_ransack_mark.tscn` photographs what actually ships.
"""

import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "design", "mockups", "ransack_mark")

# Left to right, top to bottom. The mark that ships leads, because what the
# designer is choosing between is three replacements for it.
PANELS = [
    ("ships", "What ships today: three clods of earth"),
    ("clods_v2", "(c) The same clods, sat down and darkened"),
    ("feather", "(a) A crow's feather left on the square"),
    ("stalk", "(b) The tomato left as a stripped stalk"),
]

# The board's own furniture, in the game's own colours: the night every fade in
# the overnight goes to, and the dirt base the farm's ground is drawn in.
INK = (232, 207, 166)
GROUND = (33, 31, 32)
GAP = 16
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def label_font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def board(suffix, out_name, font_size):
    plates = [(Image.open(os.path.join(OUT, f"{key}_{suffix}.png")).convert("RGB"), text)
              for key, text in PANELS]
    w, h = plates[0][0].size
    font = label_font(font_size)
    strip = font_size * 2
    sheet = Image.new("RGB", (w * 2 + GAP * 3, (h + strip) * 2 + GAP * 3), GROUND)
    draw = ImageDraw.Draw(sheet)
    for i, (plate, text) in enumerate(plates):
        x = GAP + (i % 2) * (w + GAP)
        y = GAP + (i // 2) * (h + strip + GAP)
        draw.text((x, y + font_size * 0.35), text, font=font, fill=INK)
        sheet.paste(plate, (x, y + strip))
    path = os.path.join(OUT, out_name)
    sheet.save(path)
    print(f"composed -> {os.path.relpath(path, REPO)}")


def main():
    board("close", "candidates.png", 34)
    board("in_place", "candidates_in_place.png", 28)


if __name__ == "__main__":
    main()

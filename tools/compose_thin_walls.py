#!/usr/bin/env python3
"""Put every candidate room edge side by side, from the real-game captures (Q-135).

    python3 tools/compose_thin_walls.py

Reads docs/design/mockups/thin_walls/<room>_<style>.png and <room>_frame.json, which
tools/capture_thin_walls.tscn writes, and writes comparison.png beside them: one
column per style, one row per room, every cell cropped around the room with the same
margin and enlarged by the same whole number (nearest neighbour, so no pixel is
smoothed). Needs no display.
"""

import json
import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(REPO, "docs", "design", "mockups", "thin_walls")

STYLES = [
    ("plain", "Today: plain line"),
    ("stone", "A. Low stone course"),
    ("timber", "B. Post and rail"),
    ("hedge", "C. Clipped hedge"),
    ("plaster", "D. Whitewashed lip"),
]
# Room, row label, margin around the room in screen pixels, enlargement.
ROWS = [
    ("tower", "Spiral Tower\n2x2 room, the\nyard at half size", 60, 3),
    ("coop", "Coop-sized room\n6x6, the yard at\nthree times size", 24, 2),
]
BG = (246, 241, 229)
INK = (60, 52, 48)
GAP = 12
LABEL_W = 270
HEAD_H = 56


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for d in ("/usr/share/fonts/truetype/dejavu",):
        path = os.path.join(d, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def crop(room, style, margin, scale):
    with open(os.path.join(DIR, f"{room}_frame.json")) as f:
        box = json.load(f)["room"]
    img = Image.open(os.path.join(DIR, f"{room}_{style}.png")).convert("RGB")
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    # Square, centred on the room, so both rows' cells line up.
    side = max(x1 - x0, y1 - y0) + margin * 2
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    cell = img.crop((cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side))
    return cell.resize((side * scale, side * scale), Image.NEAREST)


def main():
    rows = [[crop(room, s, m, k) for s, _ in STYLES] for room, _, m, k in ROWS]
    cell_w = max(c.width for row in rows for c in row)
    heights = [max(c.height for c in row) for row in rows]
    width = LABEL_W + len(STYLES) * (cell_w + GAP) + GAP
    height = HEAD_H + sum(h + GAP for h in heights) + GAP
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    for i, (_, title) in enumerate(STYLES):
        x = LABEL_W + i * (cell_w + GAP)
        draw.text((x, 10), title, fill=INK, font=font(30, bold=True))
    y = HEAD_H
    for (room, label, _, _), row, h in zip(ROWS, rows, heights):
        draw.multiline_text((GAP, y + 8), label, fill=INK, font=font(26), spacing=6)
        for i, c in enumerate(row):
            x = LABEL_W + i * (cell_w + GAP)
            sheet.paste(c, (x + (cell_w - c.width) // 2, y + (h - c.height) // 2))
        y += h + GAP
    out = os.path.join(DIR, "comparison.png")
    sheet.save(out, optimize=True)
    print(f"wrote {out} ({width}x{height})")


if __name__ == "__main__":
    main()

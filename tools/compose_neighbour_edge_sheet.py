#!/usr/bin/env python3
"""Turns the neighbour edge captures into the pair Q-14 asks for.

    godot --path . res://tools/capture_neighbour_edge.tscn   # stage and photograph
    python3 tools/compose_neighbour_edge_sheet.py             # label and publish

Reads the four raw exposures `tools/capture_neighbour_edge.gd` writes to
`tools/looks/neighbour_edge/` (gitignored, disposable) and writes the committed
pair into `hq/data/looks/edge/`, following the storage convention
`hq/data/looks/world_colour_station/` set (raw frames kept alongside a labelled
`sheet.png`): the two full frames, the two close-ups side by side so the edge
is visible without squinting, and one combined sheet carrying both plus the
question. Idempotent, costs nothing, needs no network.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "tools", "looks", "neighbour_edge")
OUT = os.path.join(ROOT, "hq", "data", "looks", "edge")

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
GAP = 20
PAD = 24
BG = (18, 22, 20)
INK = (238, 240, 234)
DIM = (150, 165, 152)
ACCENT = (255, 219, 115)

QUESTION = "A sprite's edge: hard cut, or one soft feathered pixel?"
NOTE = ("Same neighbour sheet, same frame, seed and camera — only the outline's "
        "outer ring differs. Left is the shipped sheet (binary alpha). Right is "
        "the same pixels with that ring's alpha halved (tools/derive_soft_edge_sprite.py).")


def font(name, size):
    path = os.path.join(FONT_DIR, name)
    if os.path.exists(path):
        return ImageFont.truetype(path, size)
    return ImageFont.load_default()


F_Q = font("DejaVuSans-Bold.ttf", 24)
F_NOTE = font("DejaVuSans.ttf", 15)
F_NAME = font("DejaVuSans-Bold.ttf", 18)


def wrap(draw, text, fnt, width):
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = (line + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def side_by_side(left_path, right_path, left_label, right_label, out_path):
    """Two images, same height, pasted beside each other with a caption row."""
    left = Image.open(left_path).convert("RGB")
    right = Image.open(right_path).convert("RGB")
    h = max(left.height, right.height)
    cap_h = 30
    total_w = left.width + GAP + right.width
    sheet = Image.new("RGB", (total_w, h + cap_h), BG)
    sheet.paste(left, (0, 0))
    sheet.paste(right, (left.width + GAP, 0))
    draw = ImageDraw.Draw(sheet)
    draw.text((0, h + 4), left_label, font=F_NAME, fill=ACCENT)
    draw.text((left.width + GAP, h + 4), right_label, font=F_NAME, fill=ACCENT)
    sheet.save(out_path)
    return sheet


def combined_sheet(close_pair, out_path):
    scratch = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    q_lines = wrap(scratch, QUESTION, F_Q, close_pair.width)
    note_lines = wrap(scratch, NOTE, F_NOTE, close_pair.width)
    head_h = PAD + len(q_lines) * 30 + 8 + len(note_lines) * 20 + 16
    sheet = Image.new("RGB", (close_pair.width + PAD * 2, head_h + close_pair.height + PAD),
                       BG)
    draw = ImageDraw.Draw(sheet)
    y = PAD
    for line in q_lines:
        draw.text((PAD, y), line, font=F_Q, fill=INK)
        y += 30
    y += 8
    for line in note_lines:
        draw.text((PAD, y), line, font=F_NOTE, fill=DIM)
        y += 20
    sheet.paste(close_pair, (PAD, head_h))
    sheet.save(out_path)


def main():
    needed = ["hard_edge.png", "hard_edge_close.png", "soft_edge.png", "soft_edge_close.png"]
    missing = [n for n in needed if not os.path.exists(os.path.join(RAW, n))]
    if missing:
        sys.exit("missing capture(s) %s in %s — run: "
                  "godot --path . res://tools/capture_neighbour_edge.tscn"
                  % (missing, os.path.relpath(RAW, ROOT)))

    os.makedirs(OUT, exist_ok=True)
    for n in ["hard_edge.png", "soft_edge.png"]:
        Image.open(os.path.join(RAW, n)).convert("RGB").save(os.path.join(OUT, n))

    close_pair = side_by_side(
        os.path.join(RAW, "hard_edge_close.png"), os.path.join(RAW, "soft_edge_close.png"),
        "Hard edge (shipped)", "Soft edge (derived)",
        os.path.join(OUT, "close_up.png"))
    combined_sheet(close_pair, os.path.join(OUT, "sheet.png"))

    for name in ["hard_edge.png", "soft_edge.png", "close_up.png", "sheet.png"]:
        print("wrote %s" % os.path.relpath(os.path.join(OUT, name), ROOT))


if __name__ == "__main__":
    main()

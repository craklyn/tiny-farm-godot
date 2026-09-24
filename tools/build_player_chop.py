#!/usr/bin/env python3
"""Derive the four clearing poses from the shipped farmer and axe pixels.

This is one held beat per direction, used only for obstacle clearing. The body
and tool are separate source layers; the up-facing axe passes behind the body.
Run from any directory: python3 tools/build_player_chop.py [--check]
"""

from pathlib import Path
import sys

from PIL import Image

from spritesmith import (Layer, Layout, cell, compose_cells, depth_compose,
                         rotate_pivot, shipped_palette, verify_sheet)


ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets" / "sprites"
OUT = SPRITES / "generated" / "player_chop.png"
SIZE = (48, 48)
DIRECTIONS = ("down", "up", "left", "right")
LAYOUT = Layout(SIZE, 1, 4, {name: (0, row) for row, name in enumerate(DIRECTIONS)},
                {"chop": DIRECTIONS})


def build() -> Image.Image:
    bodies = Image.open(SPRITES / "generated" / "characters.png")
    axe = cell(Image.open(SPRITES / "tool_icons.png"), (16, 16), 1, 0)
    palette = sorted(shipped_palette(exclude=(OUT,)))
    frames = {}
    for row, direction in enumerate(DIRECTIONS):
        body = Layer(cell(bodies, SIZE, 0, row))
        angle = -55 if direction == "left" else 55
        swung = rotate_pivot(axe, pivot="handle_butt", points={"handle_butt": (8, 14)},
                             degrees=angle, palette=palette)
        position = (10, 22) if direction == "left" else (20, 22)
        tool = Layer(swung, position)
        frames[direction] = depth_compose(SIZE,
            behind=(tool,) if direction == "up" else (), body=body,
            front=() if direction == "up" else (tool,))
    sheet = compose_cells(LAYOUT, frames)
    verify_sheet(sheet, LAYOUT, palette)
    return sheet


def main() -> int:
    sheet = build()
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or Image.open(OUT).convert("RGBA").tobytes() != sheet.tobytes():
            print(f"out of date: {OUT}", file=sys.stderr)
            return 1
        print(f"verified {OUT}")
        return 0
    if sys.argv[1:]:
        print("usage: build_player_chop.py [--check]", file=sys.stderr)
        return 2
    sheet.save(OUT)
    print(f"wrote {OUT} ({sheet.width}x{sheet.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

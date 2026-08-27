#!/usr/bin/env python3
"""Rescale the player sprite inside characters.png without regenerating art.

The sheet is 4x4 cells of 48px (rows: down/up/left/right). This resizes the drawn
content of every cell to a target height in pixels and re-anchors it to the cell
floor, so the character's size relative to the 16px tile grid can be tuned in one
step. 16px = one tile.

    python3 tools/rescale_character.py 24          # 1.5 tiles
    python3 tools/rescale_character.py 24 --dry-run

Run the visual suite afterwards; the baseline will need regenerating.
"""
import sys

from PIL import Image

SHEET = "assets/sprites/generated/characters.png"
CELL = 48
LIFT = 3  # pixels of empty space below the feet, matching the original assembly


def content_box(cell):
    return cell.getbbox()


def rescale(path, target_h, dry_run=False):
    im = Image.open(path).convert("RGBA")
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    reported = False
    for row in range(im.height // CELL):
        for col in range(im.width // CELL):
            cell = im.crop((col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL))
            box = content_box(cell)
            if box is None:
                continue
            art = cell.crop(box)
            if not reported:
                print(f"current content: {art.width}x{art.height}px "
                      f"({art.height / 16:.2f} tiles) -> {target_h}px ({target_h / 16:.2f} tiles)")
                reported = True
            scale = target_h / art.height
            nw = max(1, round(art.width * scale))
            art = art.resize((nw, target_h), Image.NEAREST)
            dest = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
            dest.alpha_composite(art, ((CELL - nw) // 2, CELL - target_h - LIFT))
            out.paste(dest, (col * CELL, row * CELL))
    if dry_run:
        print("dry run - not written")
        return
    out.save(path)
    print("wrote", path)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    rescale(SHEET, int(sys.argv[1]), "--dry-run" in sys.argv)

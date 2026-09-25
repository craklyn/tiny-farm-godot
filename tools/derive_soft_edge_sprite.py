#!/usr/bin/env python3
"""derive_soft_edge_sprite.py — a soft-edge copy of a sprite sheet, for the
Q-14 edge-treatment comparison (card wfd1109745a0, parent w59c6ab05678).

design/09-art-direction.md's hand-edits section found that every generated
sheet ships with binary alpha only — a pixel is fully opaque or fully
transparent, never in between — so there is nothing on screen today for
Daniel to judge a "soft edge" against. This derives one without a generation
call: it takes a shipped sheet exactly as it is and halves the alpha of the
outermost ring of opaque pixels, the ones with a fully transparent neighbour.
Colour is untouched everywhere; alpha is touched only at the silhouette's own
edge. No new pixels, no new colours — only the one channel the guide is silent
on (docs/design/09-art-direction.md, hand-edits section).

Usage:
    python3 tools/derive_soft_edge_sprite.py \\
        assets/sprites/generated/neighbour.png assets/sprites/looks/neighbour_soft_edge.png

Reproducible: run it again and it writes the same bytes, since it only reads
from the shipped source and a fixed feather value.
"""
import sys

from PIL import Image

FEATHER_ALPHA = 128  # about half of 255 — a two-step ramp, not a full gradient
NEIGHBOURS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def soften(src_path: str, dst_path: str, feather_alpha: int = FEATHER_ALPHA) -> int:
    """Write `dst_path` as `src_path` with its silhouette's outer ring feathered
    to `feather_alpha`. Returns how many pixels were touched."""
    img = Image.open(src_path).convert("RGBA")
    width, height = img.size
    px = img.load()

    edge_pixels = []
    for y in range(height):
        for x in range(width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue  # already background; nothing to feather
            is_edge = False
            for dx, dy in NEIGHBOURS:
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= width or ny >= height:
                    is_edge = True
                    break
                if px[nx, ny][3] == 0:
                    is_edge = True
                    break
            if is_edge and a > feather_alpha:
                edge_pixels.append((x, y, r, g, b))

    for x, y, r, g, b in edge_pixels:
        px[x, y] = (r, g, b, feather_alpha)

    img.save(dst_path)
    return len(edge_pixels)


def main(argv: list) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 1
    src, dst = argv[1], argv[2]
    n = soften(src, dst)
    print(f"{dst}: {n} silhouette-edge pixels feathered to alpha={FEATHER_ALPHA} (source: {src})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

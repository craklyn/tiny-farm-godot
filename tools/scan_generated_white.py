#!/usr/bin/env python3
"""Inventory opaque light pixels connected to transparency in generated PNGs.

This is diagnostic only: an edge-connected light pixel may be intentional paint.
Print JSON to stdout so the scan does not alter any shipped sprite.
"""

import json
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets/sprites/generated"


def frame_size(name, width, height):
    if name in {"characters.png", "neighbour.png"}:
        return 48, 48
    if name == "robot_job_icons.png":
        return 104, 32
    if height == 16 and width % 16 == 0:
        return 16, 16
    return width, height


def light(pixel):
    r, g, b, a = pixel
    # Includes the shipped cream #f8f4e6 and interior cream #f9f4e5.
    return a == 255 and r >= 245 and g >= 240 and b >= 225


def scan(path):
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    fw, fh = frame_size(path.name, width, height)
    if width % fw or height % fh:
        raise ValueError(f"Frame dimensions do not divide {path.name}: {image.size}")
    frames = []
    for top in range(0, height, fh):
        for left in range(0, width, fw):
            visited = set()
            queue = deque()

            def visit(x, y):
                if (x, y) in visited:
                    return
                pixel = image.getpixel((left + x, top + y))
                if pixel[3] == 0 or light(pixel):
                    visited.add((x, y))
                    queue.append((x, y))

            # All transparency is a seed, including enclosed gaps in a shape.
            for y in range(fh):
                for x in range(fw):
                    if image.getpixel((left + x, top + y))[3] == 0:
                        visit(x, y)
            while queue:
                x, y = queue.popleft()
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < fw and 0 <= ny < fh:
                        visit(nx, ny)
            pixels = sorted(
                ([x, y] for x, y in visited if light(image.getpixel((left + x, top + y)))),
                key=lambda xy: (xy[1], xy[0]),
            )
            if pixels:
                frames.append({"index": top // fh * (width // fw) + left // fw,
                               "count": len(pixels), "coordinates": pixels})
    return {"file": path.relative_to(ROOT).as_posix(), "size": [width, height],
            "frame_size": [fw, fh], "frames": frames}


def main():
    paths = sorted(SPRITES.glob("*.png"))
    sheets = [scan(path) for path in paths]
    print(json.dumps({"sheets_scanned": len(paths), "candidate_sheets":
                      [sheet for sheet in sheets if sheet["frames"]]}, indent=2))


if __name__ == "__main__":
    main()

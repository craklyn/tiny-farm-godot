#!/usr/bin/env python3
"""Run the workbench shelf capture and verify its four finished pictures."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import struct
import tempfile
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", "godot")
CAPTURES = ("1_shelf.png", "2_short.png", "3_bought.png", "4_normal.png")
GOLD = (255, 217, 51)
RED = (230, 77, 77)
BRASS_BACK = (138, 111, 44)
PACE_BUTTONS = ((180, 184, 276, 256), (292, 184, 388, 256), (404, 184, 500, 256))


def read_png(path: Path) -> tuple[tuple[int, int], list[bytes]]:
    """Read the 8-bit RGBA PNGs Godot writes, without an external image package."""
    data = path.read_bytes()
    width, height, depth, colour, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", data[16:29]
    )
    if (depth, colour, compression, filtering, interlace) != (8, 6, 0, 0, 0):
        raise AssertionError(f"unexpected PNG format in {path.name}")
    at = 8
    compressed = bytearray()
    while at < len(data):
        length = struct.unpack(">I", data[at : at + 4])[0]
        kind = data[at + 4 : at + 8]
        if kind == b"IDAT":
            compressed.extend(data[at + 8 : at + 8 + length])
        at += length + 12
    raw = zlib.decompress(compressed)
    stride = width * 4
    rows: list[bytes] = []
    offset = 0
    for _ in range(height):
        filter_kind = raw[offset]
        scanline = bytearray(raw[offset + 1 : offset + 1 + stride])
        previous = rows[-1] if rows else bytes(stride)
        for x in range(stride):
            left = scanline[x - 4] if x >= 4 else 0
            above = previous[x]
            upper_left = previous[x - 4] if x >= 4 else 0
            if filter_kind == 1:
                scanline[x] = (scanline[x] + left) & 255
            elif filter_kind == 2:
                scanline[x] = (scanline[x] + above) & 255
            elif filter_kind == 3:
                scanline[x] = (scanline[x] + ((left + above) // 2)) & 255
            elif filter_kind == 4:
                estimate = left + above - upper_left
                nearest = min((left, above, upper_left), key=lambda value: abs(estimate - value))
                scanline[x] = (scanline[x] + nearest) & 255
            elif filter_kind != 0:
                raise AssertionError(f"unknown PNG filter {filter_kind} in {path.name}")
        rows.append(bytes(scanline))
        offset += stride + 1
    return (width, height), rows


def pixels(rows: list[bytes], box: tuple[int, int, int, int]):
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            yield tuple(rows[y][x * 4 : x * 4 + 3])


def count_colour(rows: list[bytes], box: tuple[int, int, int, int], colour: tuple[int, int, int]) -> int:
    return sum(pixel == colour for pixel in pixels(rows, box))


class WorkbenchShelfCaptureTests(unittest.TestCase):
    def test_scene_exits_after_writing_every_capture(self) -> None:
        with tempfile.TemporaryDirectory(prefix="tiny-farm-shelf-capture-") as tmp:
            command = [
                "xvfb-run",
                "-a",
                GODOT,
                "--rendering-driver",
                "opengl3",
                "--path",
                str(ROOT),
                "res://tools/capture_workbench_shelf.tscn",
                "--",
                f"--out-dir={tmp}",
            ]
            result = subprocess.run(
                command,
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=30,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("captured ->", output)
            pictures: dict[str, list[bytes]] = {}
            for name in CAPTURES:
                picture = Path(tmp, name)
                self.assertTrue(picture.is_file(), f"missing {name}\n{output}")
                self.assertGreater(picture.stat().st_size, 100, f"empty {name}")
                self.assertEqual(picture.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
                size, pictures[name] = read_png(picture)
                self.assertEqual(size, (800, 600), name)

            # The for-sale number occupies the bottom of calm's button. It is
            # gold when affordable, red when short, and gone after purchase.
            price_box = (180, 232, 276, 256)
            self.assertGreater(count_colour(pictures["1_shelf.png"], price_box, GOLD), 20)
            self.assertGreater(count_colour(pictures["2_short.png"], price_box, RED), 20)
            for name in ("3_bought.png", "4_normal.png"):
                self.assertEqual(count_colour(pictures[name], price_box, GOLD), 0, name)
                self.assertEqual(count_colour(pictures[name], price_box, RED), 0, name)

            # Normal is the starting selection and stays visibly selected after
            # calm is bought, and after the capture presses calm then normal.
            for name in CAPTURES:
                selected = [
                    count_colour(pictures[name], box, BRASS_BACK) > 1000
                    for box in PACE_BUTTONS
                ]
                self.assertEqual(selected, [False, True, False], name)

            # The robot picture ends before x=125. Any pale strokes in the rest
            # of its picture are the removed decorative chevrons, which looked
            # like a fourth control beside the three real buttons.
            decoration_box = (125, 184, 166, 256)
            for name, picture in pictures.items():
                pale_pixels = sum(
                    r > 180 and g > 180 and b > 180
                    for r, g, b in pixels(picture, decoration_box)
                )
                self.assertEqual(pale_pixels, 0, name)


if __name__ == "__main__":
    unittest.main(verbosity=2)

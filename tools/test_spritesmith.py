#!/usr/bin/env python3
"""Focused regression tests for the derived-pixel lane."""

from pathlib import Path
import tempfile
import unittest

from PIL import Image

from spritesmith import (Layer, Layout, cell, compose_cells, depth_compose,
                         mirror_row, remap_ramp, rotate_pivot, shipped_palette,
                         verify_sheet)
from build_player_chop import build, LAYOUT, OUT


ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets" / "sprites"


class SpriteSmithTests(unittest.TestCase):
    def test_bot_mk2_exact_png_bytes(self):
        source = Image.open(SPRITES / "generated" / "bot.png")
        expected = (SPRITES / "generated" / "bot_mk2.png").read_bytes()
        ramps = {
            "violet_body": [(92, 78, 146, 255), (113, 99, 137, 255),
                            (63, 63, 77, 255), (79, 78, 93, 255)],
            "copper_body": [(146, 67, 72, 255), (137, 93, 95, 255),
                            (77, 60, 61, 255), (93, 75, 76, 255)],
        }
        result = remap_ramp(source, source="violet_body", target="copper_body", ramps=ramps)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bot_mk2.png"
            result.save(path)
            self.assertEqual(path.read_bytes(), expected)
        verify_sheet(result, Layout((48, 48), 4, 4,
            {f"{col},{row}": (col, row) for row in range(4) for col in range(4)}),
            shipped_palette())

    def test_named_pivot_rotation_is_nearest_and_keeps_pivot(self):
        red, blue = (200, 0, 0, 255), (0, 0, 200, 255)
        source = Image.new("RGBA", (5, 5))
        source.putpixel((2, 2), red)
        source.putpixel((2, 1), blue)
        result = rotate_pivot(source, pivot="butt", points={"butt": (2, 2)},
                              degrees=90, palette=[red, blue])
        self.assertEqual(result.getpixel((2, 2)), red)
        self.assertEqual(result.getpixel((3, 2)), blue)
        self.assertEqual(set(result.getdata()), {(0, 0, 0, 0), red, blue})

    def test_compose_mirror_and_per_frame_depth(self):
        body = Image.new("RGBA", (2, 2), (5, 5, 5, 255))
        held = Image.new("RGBA", (1, 1), (10, 10, 10, 255))
        back = depth_compose((2, 2), behind=[Layer(held)], body=Layer(body))
        front = depth_compose((2, 2), body=Layer(body), front=[Layer(held)])
        self.assertEqual(back.getpixel((0, 0)), (5, 5, 5, 255))
        self.assertEqual(front.getpixel((0, 0)), (10, 10, 10, 255))
        layout = Layout((2, 2), 2, 2, {"back": (0, 0), "front": (1, 0),
                                        "left": (0, 1), "right": (1, 1)},
                        {"hold": ("back", "front")})
        sheet = compose_cells(layout, {"back": back, "front": front,
                                       "left": back, "right": front})
        mirrored = mirror_row(sheet, (2, 2), 0, 1)
        self.assertEqual(cell(mirrored, (2, 2), 1, 1).getpixel((1, 0)),
                         (10, 10, 10, 255))
        verify_sheet(mirrored, layout, [body.getpixel((0, 0)), held.getpixel((0, 0))])

    def test_verifier_rejects_wrong_grid_partial_alpha_and_new_colour(self):
        layout = Layout((2, 2), 1, 1, {"only": (0, 0)})
        palette = [(1, 2, 3, 255)]
        with self.assertRaisesRegex(ValueError, "sheet size"):
            verify_sheet(Image.new("RGBA", (3, 2)), layout, palette)
        image = Image.new("RGBA", (2, 2), (1, 2, 3, 255))
        image.putpixel((0, 0), (1, 2, 3, 128))
        with self.assertRaisesRegex(ValueError, "partial alpha"):
            verify_sheet(image, layout, palette)
        image.putpixel((0, 0), (3, 2, 1, 255))
        with self.assertRaisesRegex(ValueError, "off-palette"):
            verify_sheet(image, layout, palette)

    def test_shipped_chop_is_rebuildable_and_locked(self):
        rebuilt = build()
        self.assertEqual(rebuilt.tobytes(), Image.open(OUT).convert("RGBA").tobytes())
        verify_sheet(rebuilt, LAYOUT, shipped_palette(exclude=(OUT,)))


if __name__ == "__main__":
    unittest.main()

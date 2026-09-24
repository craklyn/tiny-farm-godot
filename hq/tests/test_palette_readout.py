"""The art readout includes shipped RGB sheets and distinguishes near colors."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class PaletteReadoutTests(unittest.TestCase):
    def test_shipped_rgb_hillside_is_decoded(self):
        width, height, rgba = server._png_rgba(
            Path(server.REPO) / "assets/sprites/generated/window_hillside.png")
        self.assertEqual((width, height, len(rgba)), (320, 240, 320 * 240 * 4))
        self.assertEqual(set(rgba[3::4]), {255})

    def test_near_colours_are_reported_without_claiming_exact_matches(self):
        server._PALETTE_CACHE.update(key=None, data=None)
        data = server.palette_union()
        self.assertEqual(data["failed"], [])
        self.assertEqual(data["named_total"], 16)
        self.assertEqual(data["named_present"], 13)
        self.assertEqual(data["named_near"], {
            "d2e077": "d1e077", "c49a6c": "c39a6c", "aa7959": "a97959"})


if __name__ == "__main__":
    unittest.main()

"""The art readout counts runtime sheets and current measured anchors."""
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

    def test_measured_anchors_match_runtime_sheets_exactly(self):
        server._PALETTE_CACHE.update(key=None, data=None)
        data = server.palette_union()
        self.assertEqual(data["failed"], [])
        self.assertEqual(data["sheets"], 50)  # 49 runtime generated + tool icons
        self.assertIn("player_chop.png", data["sheet_names"])
        self.assertTrue({"terrain_field.png", "terrain_yard.png", "wheat.png"}
                        <= set(data["sheet_names"]))
        self.assertFalse({"duck.png", "fox.png", "squirrel.png", "terrain_grass.png"}
                         & set(data["sheet_names"]))
        self.assertEqual(data["named_total"], 32)
        self.assertEqual(data["named_present"], 32)
        self.assertEqual(data["named_missing"], [])
        self.assertEqual(data["named_near"], {})


if __name__ == "__main__":
    unittest.main()

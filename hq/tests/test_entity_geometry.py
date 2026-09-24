"""Catalogue references must match the PNGs and the frame pool."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class EntityGeometryTests(unittest.TestCase):
    def test_catalogue_and_bad_references(self):
        self.assertEqual(server.check_entity_geometry(), [])

        with tempfile.TemporaryDirectory() as root:
            base = Path(root)
            (base / "assets").mkdir()
            (base / "assets" / "sheet.png").write_bytes(
                b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                + struct.pack(">II", 16, 16)
            )
            (base / "entities.json").write_text(json.dumps({"groups": [{"entities": [{
                "id": "sample", "sheet": "assets/sheet.png",
                "frames": [[8, 0, 16, 16]],
                "anims": [{"id": "bad", "frames": [1, {"parts": [{"f": -1}]}]}],
            }]}]}))
            with patch.object(server, "DATA", root), patch.object(server, "REPO", root):
                warnings = server.check_entity_geometry()
        self.assertEqual(len(warnings), 3)
        self.assertTrue(any("outside 16x16" in warning for warning in warnings))
        self.assertTrue(any("frame 1" in warning for warning in warnings))
        self.assertTrue(any("frame -1" in warning for warning in warnings))


if __name__ == "__main__":
    unittest.main()

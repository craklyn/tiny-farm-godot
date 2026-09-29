#!/usr/bin/env python3
"""The asset-rights reading counts assets, not its candidate index."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import server


class AssetRightsTests(unittest.TestCase):
    def test_candidate_index_is_not_an_asset(self):
        with tempfile.TemporaryDirectory() as root:
            assets = os.path.join(root, "assets", "audio", "sfx")
            os.makedirs(assets)
            with open(os.path.join(assets, "CANDIDATES.json"), "w", encoding="utf-8") as out:
                out.write("[]")
            with open(os.path.join(root, "CREDITS.md"), "w", encoding="utf-8") as out:
                out.write("# Credits\n")

            old_repo = server.REPO
            server.REPO = root
            try:
                reading = server.eval_measure({
                    "kind": "orphan_files",
                    "dir": "assets/audio/sfx",
                    "exts": [".json"],
                    "referenced_in": ["CREDITS.md"],
                })
            finally:
                server.REPO = old_repo

        self.assertEqual(reading["value"], 0)
        self.assertEqual(reading["orphans"], [])
        self.assertEqual(reading["total_shipped"], 0)


if __name__ == "__main__":
    unittest.main()

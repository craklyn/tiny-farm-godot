#!/usr/bin/env python3
"""Sprite saves and reverts make a narrow local commit immediately.

    python3 hq/tests/test_sprite_commits.py
"""
import base64
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import server  # noqa: E402
import studio  # noqa: E402


# A complete one-pixel PNG. The server only needs its IHDR dimensions for this
# boundary test; appending a byte changes the saved file without changing them.
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9J"
    "WJ0AAAAASUVORK5CYII="
)
SHEET = "assets/sprites/generated/test.png"
KEY = "assets_sprites_generated_test"


class NoBackgroundThread:
    """Keep the test local: the commit is synchronous; push is not under test."""
    def __init__(self, *args, **kwargs):
        pass

    def start(self):
        pass


class SpriteCommits(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        sheet = self.repo / SHEET
        sheet.parent.mkdir(parents=True)
        sheet.write_bytes(PNG)
        (self.repo / "hq" / "data").mkdir(parents=True)
        (self.repo / "unrelated.txt").write_text("committed\n", encoding="utf-8")
        self.git("init", "-q")
        self.git("config", "user.name", "Sprite test")
        self.git("config", "user.email", "sprite-test@example.invalid")
        self.git("add", ".")
        self.git("commit", "-qm", "Initial files")
        # An artist's save must not sweep up somebody else's worktree change.
        (self.repo / "unrelated.txt").write_text("still uncommitted\n", encoding="utf-8")

        self.old_repo, self.old_data = server.REPO, server.DATA
        self.old_user_workspace = server.USER_WORKSPACE
        self.old_host, self.old_edits = studio.HOST, studio.EDITS
        server.REPO = str(self.repo)
        server.DATA = str(self.repo / "hq" / "data")
        server.USER_WORKSPACE = str(self.repo)
        studio.bind(server)
        self.patches = [
            patch.object(server, "run_cmd", self.run_cmd),
            patch.object(server, "signals_dirty", lambda: None),
            patch.object(server.threading, "Thread", NoBackgroundThread),
            patch.object(server, "load_org", return_value={"employees": []}),
            patch.object(studio, "file_to_art", return_value={}),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        server.REPO, server.DATA = self.old_repo, self.old_data
        server.USER_WORKSPACE = self.old_user_workspace
        studio.HOST, studio.EDITS = self.old_host, self.old_edits
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout.strip()

    def run_cmd(self, args, timeout=10, cwd=None):
        result = subprocess.run(args, cwd=self.repo, capture_output=True, text=True,
                                timeout=timeout)
        return result.stdout.strip() if result.returncode == 0 else ""

    def committed_paths(self):
        return set(filter(None, self.git("show", "--format=", "--name-only", "HEAD").splitlines()))

    def test_save_and_revert_commit_only_the_sheet_and_its_ledger(self):
        saved = server.save_sprite({
            "sheet": SHEET,
            "data_url": "data:image/png;base64," + base64.b64encode(PNG + b"x").decode(),
            "entity_name": "Test farmer",
            "note": "A test edit.",
        })
        self.assertTrue(saved["landed"]["ok"])
        self.assertEqual(self.committed_paths(), {
            SHEET,
            f"hq/data/sprite_edits/{KEY}/0000.json",
            f"hq/data/sprite_edits/{KEY}/0000.png",
            f"hq/data/sprite_edits/{KEY}/0001.json",
            f"hq/data/sprite_edits/{KEY}/0001.png",
        })
        self.assertEqual(self.git("status", "--short"), "M unrelated.txt")

        reverted = server.revert_sprite({"sheet": SHEET, "seq": 0})
        self.assertTrue(reverted["landed"]["ok"])
        self.assertEqual(self.committed_paths(), {
            SHEET,
            f"hq/data/sprite_edits/{KEY}/0002.json",
            f"hq/data/sprite_edits/{KEY}/0002.png",
        })
        self.assertEqual(self.git("status", "--short"), "M unrelated.txt")


if __name__ == "__main__":
    unittest.main()

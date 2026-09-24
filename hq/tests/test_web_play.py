"""Web-play claims use only a throwaway Git repository and data directory."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class WebPlayTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="hq-web-play-")
        self.repo = os.path.join(self.tmp, "repo")
        self.data = os.path.join(self.tmp, "data")
        os.makedirs(os.path.join(self.repo, "ui"))
        os.makedirs(os.path.join(self.repo, "docs"))
        os.makedirs(self.data)
        self.old = (server.REPO, server.DATA)
        server.REPO, server.DATA = self.repo, self.data
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Scratch test")
        self.write("ui/game.gd", "first")
        self.write("docs/DEPLOY.md", "instructions")
        self.git("add", ".")
        self.git("commit", "-qm", "initial")
        with open(os.path.join(self.data, "releases.json"), "w") as out:
            json.dump({"releases": [{"tag_intent": "v1", "name": "First"},
                                    {"tag_intent": "v2", "name": "Second"}]}, out)

    def tearDown(self):
        server.REPO, server.DATA = self.old
        shutil.rmtree(self.tmp)

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.repo, check=True,
                       capture_output=True)

    def write(self, path, content):
        with open(os.path.join(self.repo, path), "w") as out:
            out.write(content)

    def test_no_record_holds_and_lapses_for_committed_or_dirty_game(self):
        self.assertEqual(server.web_play_status()["state"], "none")
        self.assertFalse(os.path.exists(os.path.join(self.data, "attestations.json")))
        record = server.record_web_play({"of": "web_play", "played": True})["record"]
        self.assertEqual(record["for_tag"], "v1")
        self.assertEqual(server.web_play_status()["state"], "holds")
        self.write("docs/DEPLOY.md", "new instructions")
        self.git("add", ".")
        self.git("commit", "-qm", "docs only")
        self.assertEqual(server.web_play_status()["state"], "holds")
        self.write("ui/game.gd", "dirty game")
        self.assertEqual(server.web_play_status()["state"], "lapsed")
        with self.assertRaisesRegex(ValueError, "uncommitted"):
            server.record_web_play({"of": "web_play", "played": True})
        self.git("add", ".")
        self.git("commit", "-qm", "game changed")
        self.assertEqual(server.web_play_status()["state"], "lapsed")

    def test_dirty_game_refuses_first_record_and_tag_spends_record(self):
        self.write("ui/game.gd", "dirty")
        with self.assertRaisesRegex(ValueError, "uncommitted"):
            server.record_web_play({"of": "web_play", "played": True})
        self.assertFalse(os.path.exists(os.path.join(self.data, "attestations.json")))
        self.git("checkout", "--", "ui/game.gd")
        with self.assertRaisesRegex(ValueError, "Confirm"):
            server.record_web_play({"of": "web_play"})
        server.record_web_play({"of": "web_play", "played": True})
        self.git("tag", "v1")
        status = server.web_play_status()
        self.assertEqual((status["tag"], status["state"]), ("v2", "none"))

    def test_untracked_game_file_lapses_record(self):
        server.record_web_play({"of": "web_play", "played": True})
        self.write("ui/new_scene.gd", "new untracked game script")
        status = server.web_play_status()
        self.assertEqual((status["state"], status["dirty_game"]), ("lapsed", True))


if __name__ == "__main__":
    unittest.main()

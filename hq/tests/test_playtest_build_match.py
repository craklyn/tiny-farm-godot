"""A session whose build was lost but which replays on a pushed commit is tied to that commit."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server

LOST = "v0.2.0.1-591-g894089c"
PUSHED = "0903cfee02e265141ae10629a0c622bbe3470806"


class PlaytestBuildMatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.saved_workspace = server.USER_WORKSPACE
        server.USER_WORKSPACE = self.tmp.name
        self.addCleanup(setattr, server, "USER_WORKSPACE", self.saved_workspace)

    def session(self, name, conditions=None):
        folder = os.path.join(self.tmp.name, "playtests", name)
        os.makedirs(folder)
        with open(os.path.join(folder, "session_trace.jsonl"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"version": 1, "gen_seed": 0, "continued": True}) + "\n")
            f.write(json.dumps({"kind": "tap", "out": "walk", "t": 0}) + "\n")
        with open(os.path.join(folder, "session_replay.json"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"build_id": LOST}) + "\n")
        if conditions is not None:
            with open(os.path.join(folder, "session.json"), "w", encoding="utf-8") as f:
                json.dump(conditions, f)

    def test_matched_commit_stands_in_and_the_recorded_label_is_kept(self):
        self.session("matched", {"build_matched": {"commit": PUSHED, "why": "replays exactly"}})
        row = server.parse_playtest("matched")
        self.assertEqual(row["build_id"], PUSHED)
        self.assertEqual(row["recorded_build_id"], LOST)
        self.assertEqual(row["build_matched"]["why"], "replays exactly")
        self.assertIsNone(row["build_lost"])

    def test_without_a_match_the_recorded_label_is_the_build(self):
        self.session("plain")
        self.session("attested_only", {"tester": "daniel", "fresh": False})
        for name in ("plain", "attested_only"):
            row = server.parse_playtest(name)
            self.assertEqual(row["build_id"], LOST)
            self.assertEqual(row["recorded_build_id"], LOST)
            self.assertIsNone(row["build_matched"])


if __name__ == "__main__":
    unittest.main()

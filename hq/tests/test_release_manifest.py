"""Release features follow the actual project plan and player reachability."""
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class ReleaseManifestTests(unittest.TestCase):
    def setUp(self):
        server._MANIFEST_CACHE.update(head=None, data=None)
        self.doc = {"releases": [{"id": "test", "name": "Test", "features": [
            {"id": "feature", "evidence": "S-10", "project": "project"}]}]}

    def manifest_state(self, status, steps, after="abc123\x1fBuild feature", before=""):
        project = {"id": "project", "name": "Project", "status": status,
                   "plan": [{"step": str(i), "done": done} for i, done in enumerate(steps)]}

        def command(args):
            if args[:3] == ["git", "rev-parse", "HEAD"]:
                return "head"
            if args[:3] == ["git", "tag", "-l"]:
                return "v0.1.0"
            if "--grep" in args:
                return after if "v0.1.0..HEAD" in args else before
            return ""

        with patch.object(server, "run_cmd", side_effect=command), \
             patch.object(server, "load_json", return_value=self.doc), \
             patch.object(server, "load_projects", return_value=[project]):
            return server.release_manifest("test")["releases"][0]["features"][0]

    def test_unfinished_plan_overrules_done_label_and_commit(self):
        feature = self.manifest_state("done", [True, False])
        self.assertEqual(feature["state"], "in_progress")
        self.assertEqual((feature["steps_done"], feature["steps_total"]), (1, 2))

    def test_completed_plan_is_ready_despite_stale_label(self):
        self.assertEqual(self.manifest_state("planned", [True, True])["state"], "ready")

    def test_unstarted_plan_is_not_built_despite_commit_mention(self):
        self.assertEqual(self.manifest_state("done", [False, False])["state"], "not_built")

    def test_multiple_evidence_ids_match_either_commit(self):
        self.doc["releases"][0]["features"][0].update(evidence="P-13, S-11", project=None)
        seen = []

        def command(args):
            seen.append(args)
            if args[:3] == ["git", "rev-parse", "HEAD"]:
                return "head"
            if args[:3] == ["git", "tag", "-l"]:
                return "v0.2.0"
            if "v0.2.0..HEAD" in args:
                return "abc123\x1fBuild robot" if "P-13" in args else ""
            return ""

        with patch.object(server, "run_cmd", side_effect=command), \
             patch.object(server, "load_json", return_value=self.doc):
            feature = server.release_manifest("test")["releases"][0]["features"][0]
        self.assertEqual(feature["state"], "ready")
        self.assertTrue(any(args.count("--grep") == 2 for args in seen))

    def test_verified_build_commit_beats_later_planning_mention(self):
        self.doc["releases"][0]["features"][0].update(
            project=None, built_commit="built123")

        def command(args):
            if args[:3] == ["git", "rev-parse", "HEAD"]:
                return "head"
            if args[:3] == ["git", "tag", "-l"]:
                return "v0.2.0"
            if args[:3] == ["git", "rev-list", "HEAD"]:
                return "built123\nplanning456"
            if args[:3] == ["git", "rev-list", "v0.2.0"]:
                return "built123"
            if "--grep" in args:
                return "planning456\x1fMention decision"
            return ""

        with patch.object(server, "run_cmd", side_effect=command), \
             patch.object(server, "load_json", return_value=self.doc):
            feature = server.release_manifest("test")["releases"][0]["features"][0]
        self.assertEqual(feature["state"], "shipped")
        self.assertEqual(feature["commits"], 0)

    def test_current_player_feature_list_excludes_unreachable_work(self):
        releases = json.loads((Path(server.__file__).parent / "data/releases.json").read_text())
        update, *_, parked = releases["releases"]
        self.assertNotIn("home", {f["id"] for f in update["features"]})
        self.assertEqual(len(update["features"]), 11)
        self.assertFalse(parked.get("features"))


if __name__ == "__main__":
    unittest.main()

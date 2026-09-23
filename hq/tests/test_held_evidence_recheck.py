"""A new verification record rechecks the same patch without a coding worker."""

import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import drain  # noqa: E402
import work  # noqa: E402


class HeldEvidenceRecheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.item = {"id": "wtest", "title": "Weather", "owner": "grace", "tier": 1,
                     "last_recorded_attempt": "old-attempt",
                     "attempt_outcome": {"patch_id": work.evidence_id("patch"),
                                         "candidate": {"base": "main-head", "tree": "tree"}}}
        self.evidence = {"completed_runs": 10, "requested_runs": 10,
                         "passing_suites": 10, "assertion_passes": 10,
                         "assertion": "even though the sim washed it dry at the tap",
                         "candidate_tree": "tree", "patch_id": work.evidence_id("patch")}
        self.old = {"attempt_id": "old-attempt", "candidate": self.item["attempt_outcome"]["candidate"],
                    "patch": "patch", "patch_artifact": None, "result": "ten completed integration runs; Scenario W passed 10/10.\n"
                    "WHAT FOLLOWS: {\"outcome\": {\"status\": \"complete\", \"reason\": \"done\"}}",
                    "execution_evidence": {"completed_integration_runs": 1, "scenario_w_passes": 1,
                                           "run": "old-run", "attempt_id": "old-attempt"},
                    "seat": "grace", "model": "gpt-5.6-terra", "files": ["systems/game_state.gd"],
                    "stat": "one file", "usage": []}
        self.tx = os.path.join(self.tmp.name, "old-run")
        os.mkdir(self.tx)
        with open(os.path.join(self.tx, "wtest.json"), "w", encoding="utf-8") as sink:
            json.dump({"record": self.old}, sink)

    def test_source_requires_exact_green_evidence_and_recorded_candidate(self):
        with patch.object(drain, "TRANSACTIONS", self.tmp.name), \
             patch.object(drain.verification_evidence, "lookup", return_value=self.evidence), \
             patch.object(drain.integration, "main_head", return_value="main-head"):
            source = drain.held_recheck_source(self.item)
            self.assertEqual(source[0]["attempt_id"], "old-attempt")
            self.assertEqual(source[1]["passing_suites"], 10)
            incomplete = {**self.evidence, "passing_suites": 9}
            with patch.object(drain.verification_evidence, "lookup", return_value=incomplete):
                self.assertIsNone(drain.held_recheck_source(self.item))
            with patch.object(drain.integration, "main_head", return_value="new-head"):
                self.assertIsNone(drain.held_recheck_source(self.item))
            self.item["attempt_outcome"]["patch_id"] = "changed"
            self.assertIsNone(drain.held_recheck_source(self.item))

    def test_recheck_only_calls_checker_and_keeps_candidate_identity(self):
        verdict = json.dumps({"verdict": "pass", "complete": True, "summary": "verified",
                              "findings": [], "unrelated_generated_files": [],
                              "lesson_for_owner": None, "escalates": None,
                              "escalation_reason": None})
        green = {"unit": {"ok": True}, "integration": {"ok": True}}
        with patch.object(drain, "prepare_integration", return_value=(self.tmp.name, "", "")), \
             patch.object(drain, "preflight_godot_import"), \
             patch.object(drain, "record_phase"), \
             patch.object(drain, "checkpoint"), \
             patch.object(drain, "run_cli", return_value=(verdict, {"tokens": 5}, None)) as cli, \
             patch.object(drain, "run_suites", return_value=green), \
             patch.object(drain, "restore_test_generated", return_value=True), \
             patch.object(drain, "candidate_unchanged", return_value=True), \
             patch.object(drain.integration, "remove_candidate"), \
             patch.object(drain.server, "seat_model", return_value="gpt-5.6-sol"):
            rec = drain.recheck_held_candidate(self.item, {}, "new-run", (self.old, self.evidence))
        self.assertEqual(cli.call_count, 1)
        self.assertEqual(cli.call_args.args[7], "drain-check")
        self.assertNotEqual(rec["attempt_id"], "old-attempt")
        self.assertEqual(rec["candidate"], self.old["candidate"])
        self.assertTrue(rec["review_only"])
        self.assertEqual(rec["check"]["verdict"], "pass")
        self.assertEqual(rec["candidate_suites"], green)
        self.assertTrue(rec["candidate_unchanged"])


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""A review sees bounded command evidence, and unsupported run claims cannot pass."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain


CLAIM = ("Ten complete integration runs passed: 969 assertions each; "
         "Scenario W dry-at-tap passed 10 times, failed 0 times.")
PASS = {"verdict": "pass", "complete": True, "findings": [], "read": True}
COMMAND = ("python3 tools/run_godot_test.py -- godot --headless "
           "--fixed-fps 20 --path . res://tools/test_runner.tscn")
OUTPUT = ("--- Scenario W: the cot presents itself (T-27) ---\n"
          "  ✓ even though the sim washed it dry at the tap\n"
          "Results: 969 PASSED, 0 FAILED\n")


def events(call_id, *, status="completed", exit_code=0, output=OUTPUT, command=COMMAND):
    return [
        {"type": "assistant", "message": {"content": [{"type": "tool_use",
            "id": call_id, "input": {"command": command}}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result",
            "tool_use_id": call_id, "command": command, "status": status,
            "exit_code": exit_code, "content": output}]}},
    ]


class CheckerExecutionEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hq-checker-evidence-")
        self.addCleanup(self.temp.cleanup)
        self.log = Path(self.temp.name) / "owner.jsonl"

    def write(self, rows):
        self.log.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")

    def manifest(self):
        return drain.owner_execution_evidence(
            str(self.log), run="run-1", attempt_id="attempt-1",
            candidate={"tree": "exact-candidate-tree"})

    def test_claim_without_completed_logs_fails_even_if_reviewer_says_pass(self):
        self.write([{"type": "assistant", "message": {"content": [
            {"type": "text", "text": CLAIM}]}}] + events("started-only")[:1])
        evidence = self.manifest()
        check = drain.enforce_execution_claims({**PASS, "findings": []}, CLAIM, evidence)
        self.assertEqual(evidence["completed_integration_runs"], 0)
        self.assertEqual(evidence["scenario_w_passes"], 0)
        self.assertEqual(check["verdict"], "fail")
        self.assertFalse(check["complete"])
        self.assertEqual(len(check["findings"]), 2)

    def test_ten_exact_completed_results_are_available_to_checker(self):
        rows = []
        for index in range(10):
            rows.extend(events(f"call-{index}"))
        rows.extend(events("failed", exit_code=1))
        rows.extend(events("unfinished", status="in_progress", exit_code=None))
        rows.extend(events("echo", command="echo Results: 969 PASSED, 0 FAILED"))
        self.write(rows)
        evidence = self.manifest()
        self.assertEqual(evidence["run"], "run-1")
        self.assertEqual(evidence["attempt_id"], "attempt-1")
        self.assertEqual(evidence["candidate_tree"], "exact-candidate-tree")
        self.assertEqual(evidence["log_sha256"], hashlib.sha256(self.log.read_bytes()).hexdigest())
        self.assertEqual(evidence["completed_integration_runs"], 10)
        self.assertEqual(evidence["scenario_w_passes"], 10)
        self.assertEqual(len(evidence["commands"]), 12)
        self.assertEqual(drain.enforce_execution_claims(dict(PASS), CLAIM, evidence), PASS)
        record = {"result": CLAIM, "patch": "diff", "candidate": {"tree": "exact-candidate-tree"},
                  "execution_evidence": evidence}
        bound = drain.check_evidence_id(record)
        record["execution_evidence"] = {**evidence, "log_sha256": "tampered"}
        self.assertNotEqual(drain.check_evidence_id(record), bound)
        prompt = drain.check_prompt({"title": "Weather", "owner": "grace"},
                                    CLAIM, "diff --git a/a b/a", execution_evidence=evidence)
        self.assertIn("exact-candidate-tree", prompt)
        self.assertIn(str(self.log), prompt)
        self.assertIn('"completed_integration_runs": 10', prompt)
        self.assertNotIn("echo Results", prompt)

    def test_output_without_successful_command_does_not_count(self):
        self.write(events("nonzero", exit_code=1) +
                   events("failed", status="failed") +
                   events("no-scenario", output="Results: 969 PASSED, 0 FAILED\n") +
                   events("red", output="Results: 968 PASSED, 1 FAILED\n"))
        evidence = self.manifest()
        self.assertEqual(evidence["completed_integration_runs"], 1)
        self.assertEqual(evidence["scenario_w_passes"], 0)
        self.assertEqual(drain.enforce_execution_claims(dict(PASS), CLAIM, evidence)["verdict"], "fail")

    def test_ten_of_ten_wording_also_needs_command_evidence(self):
        self.write([])
        check = drain.enforce_execution_claims(dict(PASS),
                    "Scenario W passed 10/10 repeated integration runs.", self.manifest())
        self.assertEqual(check["verdict"], "fail")

    def test_durable_external_evidence_reaches_brief_review_and_check_id(self):
        external = {"id": "manifest-id", "candidate_tree": "tree", "patch_id": "patch",
                    "assertion": "even though the sim washed it dry at the tap",
                    "requested_runs": 10, "completed_runs": 10, "passing_suites": 10,
                    "assertion_passes": 10, "passing_assertions": 10, "assertion_failures": 0}
        item = {"id": "w123", "title": "Weather", "owner": "grace", "ask": "Repair it",
                "first_action": "Check the dry tap"}
        with patch.object(drain.verification_evidence, "lookup", return_value=external):
            brief = drain.task_prompt(item, {"employees": []})
        self.assertIn("manifest-id", brief)
        prompt = drain.check_prompt(item, CLAIM, "diff", external_evidence=external)
        self.assertIn('"passing_suites": 10', prompt)
        evidence = {"completed_integration_runs": 0, "scenario_w_passes": 0,
                    "external_verification": external}
        self.assertEqual(drain.enforce_execution_claims(dict(PASS), CLAIM, evidence), PASS)
        rec = {"result": CLAIM, "patch": "diff", "candidate": {"tree": "tree"},
               "execution_evidence": evidence, "external_verification": external}
        before = drain.check_evidence_id(rec)
        rec["external_verification"] = {**external, "id": "different"}
        self.assertNotEqual(drain.check_evidence_id(rec), before)

    def test_overlapping_owner_and_external_runs_are_not_added(self):
        external = {"assertion": "even though the sim washed it dry at the tap",
                    "passing_suites": 5, "assertion_passes": 5}
        evidence = {"completed_integration_runs": 5, "scenario_w_passes": 5,
                    "external_verification": external}
        check = drain.enforce_execution_claims({**PASS, "findings": []}, CLAIM, evidence)
        self.assertEqual(check["verdict"], "fail")
        self.assertEqual(len(check["findings"]), 2)
        self.assertTrue(all("supports 5" in finding["what"] for finding in check["findings"]))


if __name__ == "__main__":
    unittest.main()

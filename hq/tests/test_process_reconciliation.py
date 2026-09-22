#!/usr/bin/env python3
"""The process-card audit closes only unchanged work and holds unsafe overlap."""
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain
import work
from test_drain import fake_host


class ProcessReconciliation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.host = fake_host(self.tmp.name)
        self.host.load_json = lambda path: json.loads(Path(path).read_text())
        work.bind(self.host)
        self.repo = Path(__file__).resolve().parents[2]
        self.manifest = json.loads((self.repo / "hq/data/process_completion_reconciliation.json").read_text())
        for entry in self.manifest["cards"]:
            item = {"id": entry["id"], "title": "Immutable reconciliation fixture",
                    "owner": "claude", "tier": 1, "state": "waiting_session",
                    "ask": "Do the bounded work.", "first_action": "Read the fixture.",
                    "result": "", "attempts": 0, "created": "2026-09-22T00:00",
                    "created_ts": 1, "_revision": 0}
            if entry["id"] == "wecd05a982cc":
                item.update(result="A rejected result.", attempts=1, revising=True,
                            prior_results=[{"result": "Earlier result."}],
                            prior_checks=[{"verdict": "fail", "findings": ["missing linkage"]}])
            work._write_json(work._item_path(entry["id"]), item)
            if entry["classification"] == "hold_for_linkage":
                stable = dict(item)
                stable.pop("_revision", None)
                stable.pop("waiting_for", None)
                entry["expected_snapshots"] = [{"state": item["state"],
                                                "stable_fingerprint": work.evidence_id(stable)}]
            else:
                entry["expected_snapshots"] = [{"state": item["state"], "revision": 0,
                                                "fingerprint": work.reconciliation_fingerprint(item)}]
        self.manifest_path = Path(self.tmp.name) / "process-manifest.json"
        self.manifest_path.write_text(json.dumps(self.manifest))

    def tearDown(self):
        self.tmp.cleanup()

    def test_apply_is_idempotent_and_never_fabricates_a_checker_or_acceptance(self):
        report = work.reconcile_process_completion(self.manifest, apply=True)
        self.assertTrue(report["applied"])
        self.assertEqual(report["totals"], {"safe_to_close": 9, "leave_open": 2,
                                            "hold_for_linkage": 1})
        for entry in self.manifest["cards"]:
            item = work.load_item(entry["id"])
            if entry["classification"] == "safe_to_close":
                self.assertEqual(item["state"], "landed")
                self.assertEqual(item["completion"]["kind"], "operator_audit")
                self.assertEqual(item["completion"]["evidence"]["evidence_commits"],
                                 entry["evidence_commits"])
                self.assertEqual(item["landed"]["sha"], "",
                                 "one card must not offer to revert a shared historical commit")
                self.assertNotIn("check", item)
                self.assertNotIn("accepted", item)
        for ident in ("w9b453fb70c7", "w8e71933a1a9"):
            item = work.load_item(ident)
            self.assertEqual(item["state"], "waiting_session")
            self.assertNotIn("completion", item)
            self.assertTrue(item["repair_brief"])
            self.assertEqual(item["process_completion_reconciliation"]["classification"], "leave_open")
        first = {p.name: p.read_bytes() for p in Path(work.WORK).glob("*.json")}
        self.assertTrue(work.reconcile_process_completion(self.manifest, apply=True)["applied"])
        self.assertEqual(first, {p.name: p.read_bytes() for p in Path(work.WORK).glob("*.json")})

    def test_changed_record_blocks_every_write(self):
        changed = work.load_item("wbbbcc2086a1f")
        changed["ask"] += " New instruction."
        work.save_item(changed)
        before = {p.name: p.read_bytes() for p in Path(work.WORK).glob("*.json")}
        report = work.reconcile_process_completion(self.manifest, apply=True)
        self.assertFalse(report["applied"])
        self.assertIn("wbbbcc2086a1f: state or reviewed evidence changed", report["errors"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in Path(work.WORK).glob("*.json")})

    def test_apply_resumes_when_a_closure_was_recorded_before_landed_state(self):
        original = work.land_item
        failed = False
        def interrupt_once(*args, **kwargs):
            nonlocal failed
            if not failed:
                failed = True
                raise RuntimeError("interrupted")
            return original(*args, **kwargs)
        with patch.object(work, "land_item", side_effect=interrupt_once):
            with self.assertRaises(RuntimeError):
                work.reconcile_process_completion(self.manifest, apply=True)
        self.assertTrue(work.reconcile_process_completion(self.manifest, apply=True)["applied"])
        closed = [work.load_item(entry["id"])["state"]
                  for entry in self.manifest["cards"] if entry["classification"] == "safe_to_close"]
        self.assertEqual(closed, ["landed"] * 9)

    def test_decision_card_is_held_out_of_the_scheduler_without_erasing_revision_state(self):
        original = work.load_item("wecd05a982cc")
        original["waiting_for"] = {"reason": "a live scheduler refresh", "at": "later"}
        work.save_item(original)
        original = work.load_item("wecd05a982cc")
        work.reconcile_process_completion(self.manifest, apply=True)
        held = work.load_item("wecd05a982cc")
        for field in ("ask", "result", "attempts", "revising", "prior_checks", "prior_results", "waiting_for"):
            self.assertEqual(held.get(field), original.get(field))
        self.assertEqual(held["state"], "waiting_session")
        self.assertIn("Do not schedule another implementation attempt", held["repair_hold"])
        self.assertEqual(held["process_completion_reconciliation"]["classification"],
                         "hold_for_linkage")
        with patch.object(drain, "_parked_by_tree", return_value=False), \
             patch.object(drain, "_parked_by_cost", return_value=False):
            eligible, excluded = drain.classified_queue()
        self.assertNotIn("wecd05a982cc", {item["id"] for item in eligible})
        self.assertIn("wecd05a982cc", {item["id"] for item, _reason in excluded})

    def test_operator_command_is_read_only_until_apply(self):
        data = Path(self.tmp.name)
        (data / "org.json").write_text(json.dumps({"employees": []}))
        before = {p.name: p.read_bytes() for p in (data / "work").glob("*.json")}
        command = [sys.executable, str(self.repo / "hq/reconcile_process_completion.py"),
                   "--data-root", str(data), "--manifest", str(self.manifest_path)]
        preview = subprocess.run(command, cwd=self.repo, text=True, capture_output=True)
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        self.assertTrue(json.loads(preview.stdout)["applicable"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in (data / "work").glob("*.json")})
        applied = subprocess.run(command + ["--apply"], cwd=self.repo, text=True, capture_output=True)
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        self.assertTrue(json.loads(applied.stdout)["applied"])
        self.assertEqual(json.loads((data / "work/wecd05a982cc.json").read_text())["state"],
                         "waiting_session")
        self.assertEqual(json.loads((data / "work/we11c4a7b3f92.json").read_text())["state"],
                         "landed")
        after = subprocess.run(command, cwd=self.repo, text=True, capture_output=True)
        self.assertEqual(after.returncode, 0, after.stdout + after.stderr)
        self.assertTrue(json.loads(after.stdout)["applicable"],
                        "the fixture remains valid after the same audit has already been applied")


if __name__ == "__main__":
    unittest.main()

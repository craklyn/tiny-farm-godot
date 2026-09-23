#!/usr/bin/env python3
"""Focused tests for isolated, candidate-bound repeat verification."""

import json
import os
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HQ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HQ)
import drain
import verify_held_patch
import verification_evidence
import work


def git(repo, *args):
    return subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, check=True).stdout.strip()


class SuiteTests(unittest.TestCase):
    def test_logged_timeout_keeps_log_and_returns_incomplete(self):
        with tempfile.TemporaryDirectory() as temp:
            log_path = os.path.join(temp, "timeout.log")
            code = verify_held_patch._run_logged(
                [sys.executable, "-c", "import time; print('started', flush=True); time.sleep(30)"],
                temp, log_path, timeout=0.1)
            self.assertEqual(code, 124)
            with open(log_path) as source:
                self.assertIn("verification timed out", source.read())

    def test_timeout_kills_group_after_wrapper_leader_exits(self):
        with tempfile.TemporaryDirectory() as temp:
            leader = unittest.mock.Mock(pid=12345)
            leader.wait.side_effect = [subprocess.TimeoutExpired("check", 1), 0]
            leader.poll.return_value = 0  # leader exited on TERM; child may remain
            with patch.object(verify_held_patch.subprocess, "Popen", return_value=leader), \
                 patch.object(verify_held_patch.os, "killpg") as kill_group:
                code = verify_held_patch._run_logged(["fake"], temp,
                    os.path.join(temp, "run.log"), timeout=1)
            self.assertEqual(code, 124)
            self.assertEqual(kill_group.call_args_list,
                             [unittest.mock.call(12345, signal.SIGTERM),
                              unittest.mock.call(12345, signal.SIGKILL)])

    def test_wrapper_isolates_data_and_rejects_missing_result(self):
        wrapper = os.path.join(os.path.dirname(HQ), "tools/run_godot_test.py")
        command = [sys.executable, wrapper, "--", sys.executable, "-c",
                   "import os; print(os.environ['XDG_DATA_HOME']); print('Results: 1 PASSED, 0 FAILED')"]
        one = subprocess.run(command, capture_output=True, text=True)
        two = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual((one.returncode, two.returncode), (0, 0))
        self.assertNotEqual(one.stdout.splitlines()[0], two.stdout.splitlines()[0])
        missing = subprocess.run([sys.executable, wrapper, "--", sys.executable, "-c",
                                  "print('exited without result')"], capture_output=True, text=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("without a Results line", missing.stderr)

    def test_suite_uses_wrapper_and_requires_results(self):
        seen = []
        def fake_sh(cmd, cwd=None, timeout=None):
            seen.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, "noise only\n", "")
        with patch.object(drain, "sh", fake_sh):
            result = drain.run_suites("/fake")
        self.assertFalse(result["unit"]["ok"])
        self.assertFalse(result["integration"]["ok"])
        self.assertTrue(all(cmd[:2] == [sys.executable, "tools/run_godot_test.py"] for cmd in seen))

    def test_failed_result_is_not_success(self):
        result_line = "Results: 3 PASSED, 1 FAILED\n"
        with patch.object(drain, "sh", return_value=subprocess.CompletedProcess([], 0, result_line, "")):
            self.assertFalse(drain.run_suites("/fake")["integration"]["ok"])


class HeldPatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = self.temp.name
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "user.email", "test@example.invalid")
        os.makedirs(os.path.join(self.repo, "hq/data/work"))
        os.makedirs(os.path.join(self.repo, "hq/data/patches"))
        with open(os.path.join(self.repo, "example.txt"), "w") as sink:
            sink.write("before\n")
        git(self.repo, "add", "example.txt")
        git(self.repo, "commit", "-qm", "base")
        self.base = git(self.repo, "rev-parse", "HEAD")
        base_files = drain.git_blobs(self.repo, self.base, ["example.txt"])
        with open(os.path.join(self.repo, "example.txt"), "w") as sink:
            sink.write("after\n")
        self.patch_text = git(self.repo, "diff", "--binary") + "\n"
        files = drain.git_blobs(self.repo, "", ["example.txt"])
        git(self.repo, "add", "example.txt")
        tree = git(self.repo, "write-tree")
        git(self.repo, "reset", "-q", "--hard", self.base)
        self.item_id = "w0f78d0a7d2d"  # A real generated card ID: w + 11 hex digits.
        card = {"id": self.item_id, "diff": {"applied": False},
                "last_recorded_attempt": "attempt-1", "attempt_outcome": {
                    "patch_id": work.evidence_id(self.patch_text),
                    "candidate": {"base": self.base, "tree": tree,
                                  "files": files, "base_files": base_files}}}
        with open(os.path.join(self.repo, "hq/data/work", self.item_id + ".json"), "w") as sink:
            json.dump(card, sink)
        with open(os.path.join(self.repo, "hq/data/patches", self.item_id + ".patch"), "w") as sink:
            sink.write(self.patch_text)

    def tearDown(self):
        self.temp.cleanup()

    def test_exact_patch_and_counts_without_worker(self):
        command = [sys.executable, "-c", "print('  ✓ known assertion'); print('Results: 2 PASSED, 0 FAILED')"]
        with patch.object(drain, "run_cli", side_effect=AssertionError("worker called")):
            path = verify_held_patch.verify(self.item_id, 3, "known assertion", repo=self.repo,
                                            runner=command)
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual((evidence["completed_runs"], evidence["assertion_passes"],
                          evidence["assertion_failures"]), (3, 3, 0))
        self.assertEqual(git(self.repo, "status", "--porcelain"), "?? hq/")

    def _card(self):
        with open(os.path.join(self.repo, "hq/data/work", self.item_id + ".json")) as source:
            return json.load(source)

    def _evidence(self, runs=2, *, complete=True):
        script = ("print('  ✓ known assertion'); print('Results: 2 PASSED, 0 FAILED')"
                  if complete else "print('unfinished')")
        return verify_held_patch.verify(self.item_id, runs, "known assertion", repo=self.repo,
                                        runner=[sys.executable, "-c", script])

    def test_attached_manifest_is_bounded_and_candidate_bound(self):
        path = self._evidence()
        card = self._card()
        summary = verification_evidence.attach(card, path, os.path.join(self.repo, "hq/data"))
        self.assertEqual(summary["passing_suites"], 2)
        self.assertEqual(summary["assertion_passes"], 2)
        self.assertEqual(verification_evidence.lookup(card, os.path.join(self.repo, "hq/data")), summary)
        card["last_recorded_attempt"] = "attempt-2"
        self.assertIsNone(verification_evidence.lookup(card, os.path.join(self.repo, "hq/data")))
        card["last_recorded_attempt"] = "attempt-1"
        card["attempt_outcome"]["candidate"]["tree"] = "different"
        self.assertIsNone(verification_evidence.lookup(card, os.path.join(self.repo, "hq/data")))

    def test_attachment_is_saved_on_card_with_manifest_id(self):
        path = self._evidence()
        card = self._card()
        card.setdefault("_revision", 0)
        with patch.object(work, "WORK", os.path.join(self.repo, "hq/data/work")):
            verification_evidence.attach(card, path, os.path.join(self.repo, "hq/data"))
            work.save_item(card)
        saved = self._card()
        self.assertEqual(saved["verification_evidence"]["id"],
                         verification_evidence.lookup(saved, os.path.join(self.repo, "hq/data"))["id"])

    def test_tampered_log_and_manifest_are_rejected(self):
        path = self._evidence()
        card = self._card()
        verification_evidence.attach(card, path, os.path.join(self.repo, "hq/data"))
        with open(os.path.join(os.path.dirname(path), "run-01.log"), "a") as sink:
            sink.write("extra\n")
        self.assertIsNone(verification_evidence.lookup(card, os.path.join(self.repo, "hq/data")))
        path = self._evidence()
        verification_evidence.attach(card, path, os.path.join(self.repo, "hq/data"))
        with open(path) as source:
            manifest = json.load(source)
        manifest["completed_runs"] = 99
        with open(path, "w") as sink:
            json.dump(manifest, sink)
        self.assertIsNone(verification_evidence.lookup(card, os.path.join(self.repo, "hq/data")))

    def test_incomplete_manifest_reports_only_completed_runs(self):
        path = self._evidence(runs=10, complete=False)
        card = self._card()
        summary = verification_evidence.attach(card, path, os.path.join(self.repo, "hq/data"))
        self.assertEqual((summary["requested_runs"], summary["run_count"],
                          summary["completed_runs"], summary["passing_suites"]), (10, 1, 0, 0))

    def test_assertion_pass_in_red_suite_is_not_a_green_suite(self):
        path = verify_held_patch.verify(self.item_id, 10, "known assertion", repo=self.repo,
            runner=[sys.executable, "-c", "import sys; print('  ✓ known assertion'); "
                    "print('Results: 2 PASSED, 1 FAILED'); sys.exit(1)"])
        summary = verification_evidence.attach(self._card(), path, os.path.join(self.repo, "hq/data"))
        self.assertEqual((summary["requested_runs"], summary["completed_runs"],
                          summary["assertion_passes"], summary["passing_suites"]), (10, 1, 1, 0))

    def test_opt_in_continues_target_passes_through_red_suites(self):
        path = verify_held_patch.verify(self.item_id, 3, "known assertion", repo=self.repo,
            runner=[sys.executable, "-c", "import sys; print('  ✓ known assertion'); "
                    "print('Results: 2 PASSED, 1 FAILED'); sys.exit(1)"],
            continue_on_unrelated_failure=True)
        summary = verification_evidence.attach(self._card(), path, os.path.join(self.repo, "hq/data"))
        self.assertEqual((summary["requested_runs"], summary["completed_runs"],
                          summary["assertion_passes"], summary["passing_suites"]), (3, 3, 3, 0))
        with patch.object(sys, "argv", ["verify_held_patch.py", self.item_id, "--runs", "3",
                                        "--assertion", "known assertion"]), \
             patch.object(verify_held_patch, "verify", return_value=path):
            self.assertEqual(verify_held_patch.main(), 1)

    def test_refuses_changed_patch(self):
        with open(os.path.join(self.repo, "hq/data/patches", self.item_id + ".patch"), "a") as sink:
            sink.write("changed")
        with self.assertRaisesRegex(ValueError, "differs"):
            verify_held_patch.verify(self.item_id, 1, "known assertion", repo=self.repo,
                                     runner=[sys.executable, "-c", "print('Results: 1 PASSED, 0 FAILED')"])

    def test_refuses_path_like_ids(self):
        with self.assertRaisesRegex(ValueError, "work-card ID"):
            verify_held_patch.verify("w../other", 1, "known assertion", repo=self.repo)

    def test_missing_result_is_incomplete(self):
        path = verify_held_patch.verify(self.item_id, 2, "known assertion", repo=self.repo,
                                        runner=[sys.executable, "-c", "print('  ✓ known assertion')"])
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual(evidence["completed_runs"], 0)
        self.assertEqual(evidence["assertion_passes"], 0)

    def test_timeout_never_counts_as_completed(self):
        path = verify_held_patch.verify(self.item_id, 2, "known assertion", repo=self.repo,
                                        runner=[sys.executable, "-c",
                                                "import sys; print('  ✓ known assertion'); "
                                                "print('Results: 2 PASSED, 0 FAILED'); sys.exit(124)"])
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual(evidence["completed_runs"], 0)
        self.assertEqual([row["completed"] for row in evidence["runs"]], [False])

    def test_default_wrapper_is_current_checkout_not_historical_candidate(self):
        seen = []
        def fake_logged(args, cwd, log_path, timeout):
            seen.append((args, cwd))
            with open(log_path, "w") as sink:
                if args[0] == "godot":
                    sink.write("imported\n")
                else:
                    sink.write("  ✓ known assertion\nResults: 2 PASSED, 0 FAILED\n")
            return 0
        with patch.object(verify_held_patch, "_run_logged", side_effect=fake_logged):
            path = verify_held_patch.verify(self.item_id, 1, "known assertion", repo=self.repo)
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual(evidence["assertion_passes"], 1)
        self.assertEqual(len(seen), 2)
        self.assertTrue(os.path.isabs(seen[1][0][1]))
        self.assertTrue(seen[1][0][1].startswith(os.path.dirname(HQ)))
        self.assertNotEqual(seen[1][1], os.path.dirname(HQ))

    def test_incomplete_first_run_stops_and_keeps_partial_evidence(self):
        command = [sys.executable, "-c", "import sys; print('no result'); sys.exit(124)"]
        path = verify_held_patch.verify(self.item_id, 10, "known assertion", repo=self.repo,
                                        runner=command)
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual(evidence["requested_runs"], 10)
        self.assertEqual(len(evidence["runs"]), 1)
        self.assertEqual(evidence["completed_runs"], 0)
        with open(os.path.join(os.path.dirname(path), "run-01.log")) as source:
            self.assertIn("no result", source.read())
        self.assertFalse(os.path.exists(os.path.join(os.path.dirname(path), "run-02.log")))

    def test_import_failure_stops_before_suite_and_keeps_log(self):
        def fail_import(args, cwd, log_path, timeout):
            with open(log_path, "w") as sink:
                sink.write("SCRIPT ERROR: missing class\n")
            self.assertEqual(args[0], "godot")
            return 1
        with patch.object(verify_held_patch, "_run_logged", side_effect=fail_import):
            path = verify_held_patch.verify(self.item_id, 10, "known assertion", repo=self.repo)
        with open(path) as source:
            evidence = json.load(source)
        self.assertFalse(evidence["import"]["ok"])
        self.assertEqual(evidence["runs"], [])
        self.assertTrue(os.path.exists(os.path.join(os.path.dirname(path), "import.log")))

    def test_rejects_multiple_summaries_and_stray_assertion_after_summary(self):
        command = [sys.executable, "-c", "print('  ✓ known assertion'); "
                   "print('Results: 2 PASSED, 0 FAILED'); "
                   "print('Results: 2 PASSED, 0 FAILED')"]
        path = verify_held_patch.verify(self.item_id, 1, "known assertion", repo=self.repo,
                                        runner=command)
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual(evidence["completed_runs"], 0)
        stray = [sys.executable, "-c", "print('Results: 2 PASSED, 0 FAILED'); "
                 "print('  ✓ known assertion')"]
        path = verify_held_patch.verify(self.item_id, 1, "known assertion", repo=self.repo,
                                        runner=stray)
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual(evidence["completed_runs"], 1)
        self.assertEqual(evidence["assertion_passes"], 0)


if __name__ == "__main__":
    unittest.main()

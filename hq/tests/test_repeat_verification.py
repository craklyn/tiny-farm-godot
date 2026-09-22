#!/usr/bin/env python3
"""Focused tests for isolated, candidate-bound repeat verification."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HQ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HQ)
import drain
import verify_held_patch
import work


def git(repo, *args):
    return subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, check=True).stdout.strip()


class SuiteTests(unittest.TestCase):
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
        self.item_id = "w123456789abc"
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

    def test_refuses_changed_patch(self):
        with open(os.path.join(self.repo, "hq/data/patches", self.item_id + ".patch"), "a") as sink:
            sink.write("changed")
        with self.assertRaisesRegex(ValueError, "differs"):
            verify_held_patch.verify(self.item_id, 1, "known assertion", repo=self.repo,
                                     runner=[sys.executable, "-c", "print('Results: 1 PASSED, 0 FAILED')"])

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
        self.assertEqual([row["completed"] for row in evidence["runs"]], [False, False])

    def test_default_wrapper_is_current_checkout_not_historical_candidate(self):
        original = verify_held_patch._command
        seen = []
        def fake_command(args, cwd, timeout=120, input=None):
            if len(args) > 1 and args[0] == sys.executable and args[1].endswith("run_godot_test.py"):
                seen.append((args, cwd))
                return subprocess.CompletedProcess(args, 0,
                    "  ✓ known assertion\nResults: 2 PASSED, 0 FAILED\n", "")
            return original(args, cwd, timeout=timeout, input=input)
        with patch.object(verify_held_patch, "_command", side_effect=fake_command):
            path = verify_held_patch.verify(self.item_id, 1, "known assertion", repo=self.repo)
        with open(path) as source:
            evidence = json.load(source)
        self.assertEqual(evidence["assertion_passes"], 1)
        self.assertEqual(len(seen), 1)
        self.assertTrue(os.path.isabs(seen[0][0][1]))
        self.assertTrue(seen[0][0][1].startswith(os.path.dirname(HQ)))
        self.assertNotEqual(seen[0][1], os.path.dirname(HQ))

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

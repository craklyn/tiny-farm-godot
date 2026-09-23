#!/usr/bin/env python3
"""The user checkout is never the landing surface; main moves by exact CAS."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import integration


def git(repo, *args):
    return subprocess.run(["git", *args], cwd=repo, capture_output=True,
                          text=True, check=True).stdout.strip()


class IntegrationHandoff(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hq-integration-")
        self.repo = Path(self.tmp.name, "repo")
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.name", "HQ Fixture")
        git(self.repo, "config", "user.email", "fixture@example.invalid")
        (self.repo / "kept.txt").write_bytes(b"original\n")
        git(self.repo, "add", "kept.txt")
        git(self.repo, "commit", "-qm", "Initial")
        self.base = git(self.repo, "rev-parse", "main")

    def tearDown(self):
        self.tmp.cleanup()

    def test_handoff_preserves_staged_unstaged_and_untracked_bytes(self):
        (self.repo / "kept.txt").write_bytes(b"staged\n")
        git(self.repo, "add", "kept.txt")
        (self.repo / "kept.txt").write_bytes(b"unstaged\x00bytes\n")
        (self.repo / "untracked.bin").write_bytes(b"\x00\xff\x80")
        before = integration._checkout_fingerprint(str(self.repo))
        self.assertFalse(integration.handoff_main(str(self.repo), "codex/user")[0])
        self.assertEqual(git(self.repo, "symbolic-ref", "HEAD"), "refs/heads/main")
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        self.assertEqual(integration._checkout_fingerprint(str(self.repo)), before)
        self.assertEqual(git(self.repo, "symbolic-ref", "HEAD"), "refs/heads/codex/user")
        self.assertEqual(integration.main_head(str(self.repo)), self.base)
        self.assertEqual(integration.handoff_status(str(self.repo)), (True, ""))

    def test_candidate_is_detached_and_main_cas_rejects_second_old_parent(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        self.assertEqual(git(tree, "rev-parse", "HEAD"), self.base)
        self.assertNotEqual(subprocess.run(["git", "symbolic-ref", "--quiet", "HEAD"],
                                          cwd=tree, capture_output=True).returncode, 0)
        (Path(tree) / "candidate.txt").write_text("checked\n")
        git(tree, "add", "candidate.txt")
        git(tree, "commit", "-qm", "Candidate")
        commit = git(tree, "rev-parse", "HEAD")
        self.assertTrue(integration.advance_main(str(self.repo), commit, self.base))
        self.assertFalse(integration.advance_main(str(self.repo), self.base, self.base))
        self.assertEqual(integration.main_head(str(self.repo)), commit)
        self.assertFalse((self.repo / "candidate.txt").exists())

    def test_checkout_still_on_main_blocks_candidate(self):
        ready, reason = integration.handoff_status(str(self.repo))
        self.assertFalse(ready)
        self.assertIn("handoff", reason)
        with self.assertRaises(RuntimeError):
            integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        self.assertEqual(integration.main_head(str(self.repo)), self.base)

    def test_legacy_apply_is_refused_before_store_or_git_mutation(self):
        command = [sys.executable, str(Path(__file__).resolve().parents[1] / "drain.py"),
                   "--apply", "wfixture"]
        before = integration._checkout_fingerprint(str(self.repo))
        result = subprocess.run(command, cwd=self.repo, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("retired", result.stdout)
        self.assertEqual(integration._checkout_fingerprint(str(self.repo)), before)
        self.assertEqual(integration.main_head(str(self.repo)), self.base)


if __name__ == "__main__":
    unittest.main()

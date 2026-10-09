#!/usr/bin/env python3
"""The user checkout is never the landing surface; main moves by exact CAS."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

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
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        self.assertEqual(git(tree, "rev-parse", "HEAD"), self.base)
        self.assertEqual(integration.main_head(str(self.repo)), self.base)

    def test_clean_dedicated_main_owner_advances_with_exact_candidate(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        self.assertEqual(integration.handoff_status(str(self.repo)), (True, ""))
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        (Path(tree) / "candidate.txt").write_text("checked\n")
        git(tree, "add", "candidate.txt")
        git(tree, "commit", "-qm", "Candidate")
        commit = git(tree, "rev-parse", "HEAD")
        self.assertTrue(integration.advance_main(str(self.repo), commit, self.base))
        self.assertEqual(git(owner, "rev-parse", "HEAD"), commit)
        self.assertEqual((owner / "candidate.txt").read_text(), "checked\n")
        self.assertEqual(git(owner, "status", "--porcelain"), "")

    def test_rescued_playtest_stays_put_while_clean_main_owner_advances(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        session = owner / "playtests" / "2026-09-30_004036" / "session_trace.jsonl"
        session.parent.mkdir(parents=True)
        session.write_bytes(b'{"kind":"tap"}\n')
        self.assertEqual(integration.handoff_status(str(self.repo)), (True, ""))
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        (Path(tree) / "candidate.txt").write_text("checked\n")
        git(tree, "add", "candidate.txt")
        git(tree, "commit", "-qm", "Candidate")
        commit = git(tree, "rev-parse", "HEAD")
        self.assertTrue(integration.advance_main(str(self.repo), commit, self.base))
        self.assertEqual(session.read_bytes(), b'{"kind":"tap"}\n')
        self.assertEqual((owner / "candidate.txt").read_text(), "checked\n")
        self.assertEqual(integration.handoff_status(str(self.repo)), (True, ""))

    def test_unrelated_untracked_file_does_not_block_dedicated_main_owner(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        (owner / "scratch.txt").write_text("keep me\n")
        self.assertEqual(integration.handoff_status(str(self.repo)), (True, ""))

    def test_local_commit_not_on_origin_main_blocks_dedicated_owner(self):
        git(self.repo, "update-ref", "refs/remotes/origin/main", self.base)
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        (owner / "local.txt").write_text("local commit\n")
        git(owner, "add", "local.txt")
        git(owner, "commit", "-qm", "Local only")
        self.assertFalse(integration.handoff_status(str(self.repo))[0])

    def test_candidate_cannot_replace_untracked_rescued_playtest(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        relative = Path("playtests/2026-09-30_004036/session_trace.jsonl")
        session = owner / relative
        session.parent.mkdir(parents=True)
        session.write_text("tablet evidence\n")
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        candidate_file = Path(tree) / relative
        candidate_file.parent.mkdir(parents=True)
        candidate_file.write_text("candidate data\n")
        git(tree, "add", str(relative))
        git(tree, "commit", "-qm", "Candidate")
        commit = git(tree, "rev-parse", "HEAD")
        self.assertFalse(integration.advance_main(str(self.repo), commit, self.base))
        self.assertEqual(integration.main_head(str(self.repo)), self.base)
        self.assertEqual(session.read_text(), "tablet evidence\n")

    def test_candidate_directory_cannot_replace_untracked_file(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        collision = owner / "evidence"
        collision.write_text("keep this file\n")
        before = integration._checkout_fingerprint(str(owner))
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        candidate_file = Path(tree) / "evidence" / "session.jsonl"
        candidate_file.parent.mkdir()
        candidate_file.write_text("candidate data\n")
        git(tree, "add", "evidence/session.jsonl")
        git(tree, "commit", "-qm", "Candidate")
        commit = git(tree, "rev-parse", "HEAD")

        self.assertFalse(integration.advance_main(str(self.repo), commit, self.base))
        self.assertEqual(integration.main_head(str(self.repo)), self.base)
        self.assertEqual(integration._checkout_fingerprint(str(owner)), before)

    def test_candidate_file_cannot_replace_untracked_directory(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        collision = owner / "evidence" / "session.jsonl"
        collision.parent.mkdir()
        collision.write_text("keep this directory\n")
        before = integration._checkout_fingerprint(str(owner))
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        candidate_file = Path(tree) / "evidence"
        candidate_file.write_text("candidate data\n")
        git(tree, "add", "evidence")
        git(tree, "commit", "-qm", "Candidate")
        commit = git(tree, "rev-parse", "HEAD")

        self.assertFalse(integration.advance_main(str(self.repo), commit, self.base))
        self.assertEqual(integration.main_head(str(self.repo)), self.base)
        self.assertEqual(integration._checkout_fingerprint(str(owner)), before)

    def test_dirty_dedicated_main_owner_blocks_cas_without_overwrite(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        (owner / "kept.txt").write_text("user edit\n")
        self.assertFalse(integration.handoff_status(str(self.repo))[0])
        self.assertFalse(integration.advance_main(str(self.repo), self.base, self.base))
        self.assertEqual((owner / "kept.txt").read_text(), "user edit\n")

    def test_checkout_sync_can_resume_after_ref_cas_interruption(self):
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "--", str(owner), "main")
        tree = integration.candidate_checkout(str(self.repo), self.tmp.name, "a1", self.base)
        (Path(tree) / "candidate.txt").write_text("checked\n")
        git(tree, "add", "candidate.txt")
        git(tree, "commit", "-qm", "Candidate")
        commit = git(tree, "rev-parse", "HEAD")
        with patch.object(integration, "synchronize_main", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "needs safe synchronization"):
                integration.advance_main(str(self.repo), commit, self.base)
        self.assertEqual(integration.main_head(str(self.repo)), commit)
        self.assertFalse((owner / "candidate.txt").exists())
        self.assertTrue(integration.synchronize_main(str(self.repo), commit, self.base))
        self.assertTrue(integration.synchronize_main(str(self.repo), commit, self.base))
        self.assertEqual((owner / "candidate.txt").read_text(), "checked\n")

    def test_legacy_apply_is_refused_before_store_or_git_mutation(self):
        command = [sys.executable, str(Path(__file__).resolve().parents[1] / "drain.py"),
                   "--apply", "wfixture"]
        before = integration._checkout_fingerprint(str(self.repo))
        result = subprocess.run(command, cwd=self.repo, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("retired", result.stdout)
        self.assertEqual(integration._checkout_fingerprint(str(self.repo)), before)
        self.assertEqual(integration.main_head(str(self.repo)), self.base)


    def _owner_behind_origin(self):
        """A dedicated main checkout, and a newer main pushed from elsewhere."""
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user",
                                                  confirmed_idle=True), (True, ""))
        owner = Path(self.tmp.name, "main-owner")
        git(self.repo, "worktree", "add", "-q", "--", str(owner), "main")
        side = Path(self.tmp.name, "elsewhere")
        git(self.repo, "worktree", "add", "-q", "--detach", "--", str(side), self.base)
        (side / "pushed.txt").write_text("from another session\n")
        (side / "docs").mkdir()
        (side / "docs" / "writing_verdicts.json").write_text("{}\n")
        git(side, "add", "pushed.txt", "docs/writing_verdicts.json")
        git(side, "commit", "-qm", "Pushed from elsewhere")
        return owner, git(side, "rev-parse", "HEAD")

    def test_a_clean_main_owner_catches_up_with_work_pushed_elsewhere(self):
        owner, pushed = self._owner_behind_origin()
        self.assertEqual(integration.catch_up_main(str(self.repo), pushed), "advanced")
        self.assertEqual(integration.main_head(str(self.repo)), pushed)
        self.assertEqual(git(owner, "rev-parse", "HEAD"), pushed)
        self.assertTrue((owner / "pushed.txt").exists())
        self.assertEqual(integration.catch_up_main(str(self.repo), pushed), "current")
        self.assertEqual(integration.handoff_status(str(self.repo)), (True, ""))

    def test_only_the_regenerable_cache_is_cleared_before_catching_up(self):
        owner, pushed = self._owner_behind_origin()
        # One more commit so the owner has the cache file tracked, then dirty it.
        side = Path(self.tmp.name, "elsewhere")
        integration.catch_up_main(str(self.repo), pushed)
        (side / "pushed.txt").write_text("second\n")
        git(side, "commit", "-qam", "Second push")
        second = git(side, "rev-parse", "HEAD")
        (owner / "docs" / "writing_verdicts.json").write_text('{"cached": 1}\n')
        self.assertEqual(integration.catch_up_main(str(self.repo), second), "advanced")
        self.assertEqual((owner / "docs" / "writing_verdicts.json").read_text(), "{}\n")
        # Anything else edited in the checkout is someone's work: never touched.
        (side / "pushed.txt").write_text("third\n")
        git(side, "commit", "-qam", "Third push")
        third = git(side, "rev-parse", "HEAD")
        (owner / "kept.txt").write_text("somebody's edit\n")
        self.assertEqual(integration.catch_up_main(str(self.repo), third), "dirty")
        self.assertEqual(integration.main_head(str(self.repo)), second)
        self.assertEqual((owner / "kept.txt").read_text(), "somebody's edit\n")

    def test_main_that_has_diverged_from_origin_is_left_alone(self):
        owner, pushed = self._owner_behind_origin()
        (owner / "local.txt").write_text("landed here, not pushed\n")
        git(owner, "add", "local.txt")
        git(owner, "commit", "-qm", "Local landing")
        local = integration.main_head(str(self.repo))
        self.assertEqual(integration.catch_up_main(str(self.repo), pushed), "diverged")
        self.assertEqual(integration.main_head(str(self.repo)), local)


if __name__ == "__main__":
    unittest.main()

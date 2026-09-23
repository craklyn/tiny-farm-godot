#!/usr/bin/env python3
"""Undo uses the serialized, recoverable main integration lane."""
from pathlib import Path
from unittest import mock
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain
import integration
import server
import work


def git(repo, *args):
    return subprocess.run(["git", *args], cwd=repo, check=True,
                          capture_output=True, text=True).stdout.strip()


class UndoIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.user = root / "user"
        self.user.mkdir()
        subprocess.run(["git", "init", "-b", "main", str(self.user)],
                       check=True, capture_output=True)
        git(self.user, "config", "user.name", "Fixture")
        git(self.user, "config", "user.email", "fixture@example.test")
        (self.user / "sample.txt").write_text("before\n")
        git(self.user, "add", "sample.txt")
        git(self.user, "commit", "-m", "Base")
        git(self.user, "switch", "-c", "codex/user")
        self.main = root / "main"
        git(self.user, "worktree", "add", str(self.main), "main")
        (self.main / "sample.txt").write_text("landed\n")
        git(self.main, "add", "sample.txt")
        git(self.main, "commit", "-m", "Landed work")
        self.landed = git(self.main, "rev-parse", "HEAD")
        (self.user / "private.txt").write_text("Daniel's unfinished work\n")
        self.user_bytes = (self.user / "private.txt").read_bytes()

        self.old = (server.DATA, server.REPO, drain.WORKTREES)
        server.DATA = str(root / "data")
        server.REPO = str(self.main)
        drain.WORKTREES = str(root / "scratch")
        work.bind(server)
        self.card = work.save_item({
            "id": "wabcdef123456", "title": "Fixture landing", "owner": "sam",
            "tier": 1, "state": "landed", "ask": "Change the sample.",
            "attempt_outcome": {"id": "attempt-1", "landing_verified": True},
            "completion": {"sha": self.landed, "at": "2026-09-22T00:00:00"},
            "landed": {"sha": self.landed, "at": "2026-09-22T00:00:00"},
        })

    def tearDown(self):
        server.DATA, server.REPO, drain.WORKTREES = self.old
        work.bind(server)
        self.tmp.cleanup()

    def undo(self):
        return work.api_post("/api/work/undo", {"id": self.card["id"],
                                              "_revision": self.card["_revision"]})

    def test_busy_drain_refuses_undo_without_touching_main_or_card(self):
        before = integration.main_head(self.main)
        lock = drain.take_lock()
        try:
            response = self.undo()
        finally:
            lock.close()
        self.assertFalse(response["ok"])
        self.assertIn("busy", response["why"])
        self.assertEqual(integration.main_head(self.main), before)
        self.assertNotIn("pending_undo", work.load_item(self.card["id"]))

    def test_undo_reverts_only_in_clean_main_and_preserves_user_checkout(self):
        response = self.undo()
        self.assertTrue(response["ok"], response)
        card = work.load_item(self.card["id"])
        self.assertEqual(card["state"], "for_review")
        self.assertNotIn("pending_undo", card)
        self.assertEqual(card["landing_undone"]["reverted"], self.landed)
        self.assertEqual((self.main / "sample.txt").read_text(), "before\n")
        self.assertEqual((self.user / "private.txt").read_bytes(), self.user_bytes)
        self.assertEqual(git(self.main, "rev-list", "--count", "main"), "3")

    def test_crash_after_main_advance_recovers_once(self):
        original = integration.advance_main

        def crash_after_advance(repo, commit, parent):
            self.assertTrue(original(repo, commit, parent))
            raise RuntimeError("process interrupted after ref update")

        with mock.patch.object(integration, "advance_main", side_effect=crash_after_advance):
            with self.assertRaisesRegex(RuntimeError, "interrupted"):
                self.undo()
        after = integration.main_head(self.main)
        self.assertNotEqual(after, self.landed)
        self.assertIn("pending_undo", work.load_item(self.card["id"]))
        self.assertEqual(work.recover_completion_work(), [self.card["id"]])
        self.assertEqual(integration.main_head(self.main), after)
        self.assertEqual(git(self.main, "rev-list", "--count", "main"), "3")
        self.assertEqual(work.load_item(self.card["id"])["state"], "for_review")
        self.assertEqual(work.recover_completion_work(), [])
        self.assertEqual((self.user / "private.txt").read_bytes(), self.user_bytes)

    def test_crash_after_detached_commit_recovers_without_duplicate_revert(self):
        with mock.patch.object(integration, "advance_main",
                               side_effect=RuntimeError("process interrupted before ref update")):
            with self.assertRaisesRegex(RuntimeError, "interrupted"):
                self.undo()
        self.assertEqual(integration.main_head(self.main), self.landed)
        pending = work.load_item(self.card["id"])["pending_undo"]
        candidate = Path(pending["checkout"])
        committed = git(candidate, "rev-parse", "HEAD")
        self.assertNotEqual(committed, self.landed)
        self.assertEqual(work.recover_completion_work(), [self.card["id"]])
        self.assertEqual(integration.main_head(self.main), committed)
        self.assertEqual(git(self.main, "rev-list", "--count", "main"), "3")

    def test_changed_main_does_not_reuse_old_undo_evidence(self):
        with mock.patch.object(integration, "advance_main",
                               side_effect=RuntimeError("pause after detached commit")):
            with self.assertRaisesRegex(RuntimeError, "pause"):
                self.undo()
        (self.main / "other.txt").write_text("another independent landing\n")
        git(self.main, "add", "other.txt")
        git(self.main, "commit", "-m", "Another landing")
        changed_head = integration.main_head(self.main)
        self.assertEqual(work.recover_completion_work(), [])
        self.assertEqual(integration.main_head(self.main), changed_head)
        self.assertEqual(work.load_item(self.card["id"])["state"], "landed")


if __name__ == "__main__":
    unittest.main()

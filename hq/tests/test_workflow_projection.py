#!/usr/bin/env python3
"""The queue is a read-only projection; recovery is a durable, unique action."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain
import integration
import server
import work
from test_drain import fake_host


class WorkflowProjection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.repo / "sample.txt").write_text("base\n")
        self.git("add", "sample.txt")
        self.git("commit", "-qm", "base")
        self.data = self.root / "data"
        host = fake_host(str(self.data))
        host.load_json = lambda path: json.loads(Path(path).read_text())
        host.token_window = lambda: {"tokens": 0, "calls": 0}
        host.drain_state = lambda: None
        work.bind(host, sanitize=False)
        self.patches = self.root / "patches"
        self.workers = self.root / "workers"
        self.patches.mkdir()
        self.patches_patch = patch.object(drain, "PATCHES", str(self.patches)); self.patches_patch.start()
        self.workers_patch = patch.object(drain, "WORKERS", str(self.workers)); self.workers_patch.start()
        self.repo_patch = patch.object(drain, "REPO", str(self.repo)); self.repo_patch.start()
        self.state_patch = patch.object(server, "drain_state", return_value=None); self.state_patch.start()

    def tearDown(self):
        self.state_patch.stop()
        self.repo_patch.stop()
        self.workers_patch.stop()
        self.patches_patch.stop()
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, text=True,
                              capture_output=True, check=True).stdout.strip()

    def card(self, ident="w111111111111", **fields):
        item = {"id": ident, "title": "Weather", "owner": "grace", "tier": 1,
                "state": "waiting_session", "ask": "Fix weather", "first_action": "Read weather",
                "created": "2026-09-22T00:00:00+00:00", "created_ts": 1,
                "attempts": 0, "started": ""}
        item.update(fields)
        return work.save_item(item)

    def test_reads_do_not_write_or_refresh_card_revision(self):
        item = self.card()
        drain.save_patch(item["id"], "diff --git a/sample.txt b/sample.txt\n--- a/sample.txt\n+++ b/sample.txt\n@@ -1 +1 @@\n-base\n+new\n")
        (self.repo / "sample.txt").write_text("someone else's edit\n")
        before = Path(work._item_path(item["id"])).read_bytes()
        first = drain.queue_view()
        second = drain.queue_view()
        snap = work.snapshot()
        self.assertEqual(first, second)
        self.assertEqual(before, Path(work._item_path(item["id"])).read_bytes())
        self.assertEqual(snap["items"][0]["_revision"], item["_revision"])
        self.assertEqual(snap["items"][0]["workflow_view"], first["eligible"][0]["workflow_view"])
        self.assertEqual(first["eligible"][0]["action_type"], "reconcile")
        self.assertEqual(first["eligible"][0]["work_id"], item["id"])
        self.assertEqual(first["held"][0]["id"], item["id"])
        self.assertEqual(first["held"][0]["workflow_view"]["blocker"]["type"], "code_conflict")

    def test_review_hold_has_reconciliation_not_daniel_decision(self):
        item = self.card(state="for_review", repair_hold="Candidate needs fresh verification")
        view = drain.project_work(item)
        self.assertEqual(view["phase"], "reconciliation")
        self.assertEqual(view["availability"], "runnable")
        self.assertEqual(view["next_action"]["type"], "reconcile")
        self.assertEqual(view["next_action"]["owner"], "grace")
        self.assertEqual(view["blocker"]["type"], "missing_evidence")
        self.assertIn(item["id"], [row["work_id"] for row in drain.queue_view()["eligible"]])

    def test_dirty_user_branch_after_handoff_does_not_block_clean_main(self):
        item = self.card()
        drain.save_patch(item["id"], "diff --git a/sample.txt b/sample.txt\n--- a/sample.txt\n+++ b/sample.txt\n@@ -1 +1 @@\n-base\n+new\n")
        (self.repo / "sample.txt").write_text("someone else's uncommitted edit\n")
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/user-fixture",
                                                  confirmed_idle=True), (True, ""))
        view = drain.project_work(item)
        self.assertIsNone(view["blocker"])
        self.assertEqual(view["next_action"]["type"], "build")
        self.assertIn(item["id"], [row["work_id"] for row in drain.queue_view()["eligible"]])
        self.assertEqual((self.repo / "sample.txt").read_text(),
                         "someone else's uncommitted edit\n")

    def test_action_id_claim_and_blocker_are_idempotent(self):
        item = self.card()
        first = work.ensure_action(item, "reconcile", input_id="candidate-a", summary="Rebase")
        rev = item["_revision"]
        same = work.ensure_action(item, "reconcile", input_id="candidate-a", summary="Rebase")
        self.assertEqual(first, same)
        self.assertEqual(item["_revision"], rev)
        blocker = work.ensure_blocker(item, "stale_base", input_id="candidate-a", reason="Main moved")
        rev = item["_revision"]
        self.assertEqual(blocker, work.ensure_blocker(item, "stale_base", input_id="candidate-a", reason="Main moved"))
        self.assertEqual(item["_revision"], rev)
        claimed = work.claim_action(item, first["id"], "claim-a", now=100, lease_seconds=10)
        rev = item["_revision"]
        self.assertEqual(claimed, work.claim_action(item, first["id"], "claim-a", now=101))
        self.assertEqual(item["_revision"], rev)
        self.assertIsNone(work.claim_action(item, first["id"], "claim-b", now=105))
        self.assertEqual(work.work_view(item, now=105)["availability"], "waiting_event",
                         "a lease alone is not proof of a live agent")
        self.assertEqual(work.work_view(item, now=111)["availability"], "runnable")
        self.assertEqual(work.claim_action(item, first["id"], "claim-b", now=111)["claim"]["id"], "claim-b")
        work.finish_action(item, first["id"], "claim-b")
        self.assertIsNone(work.claim_action(item, first["id"], "claim-c", now=112))
        view = work.work_view(item, now=112)
        self.assertEqual(next(a for a in view["actions"]
                              if a["id"] == first["id"])["availability"], "terminal")
        self.assertEqual(view["next_action"]["type"], "recover")
        self.assertEqual(len({a["id"] for a in view["actions"]}), len(view["actions"]))
        self.assertEqual(len(item["workflow"]["actions"]), 1)
        self.assertEqual(len(item["workflow"]["blockers"]), 1)

    def test_metadata_never_changes_instruction_identity(self):
        item = self.card()
        original = work.instruction_fingerprint(item)
        work.ensure_action(item, "reconcile", input_id="candidate-a")
        work.ensure_blocker(item, "stale_base", input_id="candidate-a")
        self.assertEqual(original, work.instruction_fingerprint(item))

    def test_patch_replacement_keeps_both_immutable_bodies(self):
        first = "diff --git a/a b/a\nfirst\n"
        second = "diff --git a/a b/a\nsecond\n"
        drain.save_patch("w111111111111", first)
        older = drain.patch_artifact(first)
        drain.save_patch("w111111111111", second)
        newer = drain.patch_artifact(second)
        self.assertNotEqual(older["id"], newer["id"])
        self.assertEqual(Path(older["path"]).read_text(), first)
        self.assertEqual(Path(newer["path"]).read_text(), second)
        self.assertEqual(drain.load_patch("w111111111111"), second)

    def test_immutable_candidate_body_must_match_its_reviewed_record(self):
        patch_text = "diff --git a/a b/a\nreviewed body\n"
        drain.save_patch("w111111111111", patch_text)
        reference = drain.patch_artifact(patch_text)
        self.assertEqual(drain.checked_patch({"patch": patch_text,
                                              "patch_artifact": reference}), patch_text)
        Path(reference["path"]).write_text("changed after review\n")
        with self.assertRaises(ValueError):
            drain.checked_patch({"patch": patch_text, "patch_artifact": reference})

    def test_ordinary_work_ages_ahead_of_newer_start(self):
        self.card("w111111111111", created_ts=1)
        self.card("w222222222222", created_ts=2)
        self.assertEqual([row["work_id"] for row in drain.queue_view()["eligible"]],
                         ["w111111111111", "w222222222222"])


if __name__ == "__main__":
    unittest.main()

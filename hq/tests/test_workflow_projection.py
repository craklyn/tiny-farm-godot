#!/usr/bin/env python3
"""The queue is a read-only projection; recovery is a durable, unique action."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
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
        # Age is a live projection. Keep the clock fixed while comparing these
        # separate reads so crossing a whole second cannot change age_seconds.
        with patch.object(time, "time", return_value=time.time()):
            first = drain.queue_view()
            second = drain.queue_view()
            snap = work.snapshot()
        self.assertEqual(first, second)
        self.assertEqual(before, Path(work._item_path(item["id"])).read_bytes())
        self.assertEqual(snap["items"][0]["_revision"], item["_revision"])
        self.assertEqual(snap["items"][0]["workflow_view"], first["eligible"][0]["workflow_view"])
        self.assertEqual(first["eligible"][0]["action_type"], "reconcile")
        self.assertEqual(first["eligible"][0]["work_id"], item["id"])
        # One row per card: the blocked build is folded into its repair's row
        # instead of also being listed under Held.
        self.assertEqual(first["held"], [])
        self.assertEqual(len([row for row in first["eligible"] if row["work_id"] == item["id"]]), 1)
        self.assertEqual(first["eligible"][0]["workflow_view"]["blocker"]["type"], "code_conflict")
        self.assertEqual(first["eligible"][0]["supersedes"]["action_type"], "build")
        self.assertEqual(first["eligible"][0]["supersedes"]["reason"],
                         first["eligible"][0]["workflow_view"]["blocker"]["reason"])
        self.assertIn("replaces the earlier attempt", first["eligible"][0]["why"])

    def test_review_hold_has_reconciliation_not_daniel_decision(self):
        item = self.card(state="for_review", repair_hold="Candidate needs fresh verification")
        view = drain.project_work(item)
        self.assertEqual(view["phase"], "reconciliation")
        self.assertEqual(view["availability"], "runnable")
        self.assertEqual(view["next_action"]["type"], "reconcile")
        self.assertEqual(view["next_action"]["owner"], "grace")
        self.assertEqual(view["blocker"]["type"], "missing_evidence")
        self.assertIn(item["id"], [row["work_id"] for row in drain.queue_view()["eligible"]])

    def test_exhausted_repair_waits_until_one_explicit_supervised_retry(self):
        item = self.card(state="for_review", automatic_repairs=1,
                         last_recorded_attempt="failed-repair",
                         repair_hold="The repair still needs verification.")
        prior = work.ensure_action(item, "reconcile", input_id="failed-repair")
        work.claim_action(item, prior["id"], "prior-claim")
        work.finish_action(item, prior["id"], "prior-claim")
        before = Path(work._item_path(item["id"])).read_bytes()
        held = drain.project_work(item)
        self.assertEqual(held["availability"], "waiting_event")
        self.assertEqual(held["blocker"]["type"], "missing_evidence")
        self.assertIn("explicit supervised retry", held["blocker"]["wake"])
        self.assertNotIn(item["id"], [row["work_id"] for row in drain.queue_view()["eligible"]])
        self.assertEqual(before, Path(work._item_path(item["id"])).read_bytes())

        with patch.object(drain, "RETRY_ONCE_IDS", {item["id"]}):
            trial = drain.project_work(item)
            self.assertEqual(trial["next_action"]["type"], "reconcile")
            self.assertEqual(trial["availability"], "runnable")
            self.assertNotEqual(trial["next_action"]["id"], prior["id"])
            self.assertEqual(trial["next_action"], drain.project_work(item)["next_action"])
            self.assertEqual([row["work_id"] for row in drain.queue_view()["eligible"]], [item["id"]])
            capped = work.work_view(item, repo_facts={"supervised_retry": True,
                                                      "cost_reason": "Cost cap reached"})
            self.assertEqual(capped["availability"], "waiting_event")
        self.assertEqual(drain.project_work(item)["availability"], "waiting_event")
        self.assertEqual(before, Path(work._item_path(item["id"])).read_bytes())

    def test_a_revision_after_completed_steps_is_new_work_not_a_stall(self):
        # 2026-10-09: the seed-clarity card's owner replied "revise", but its next
        # step reused the id of a step already done, so it read as a stalled
        # recovery and sat in the held lane. Its last result changed no files, so
        # every step took the same recorded candidate as its input.
        item = self.card(workflow={"version": 1, "actions": [], "blockers": [],
                                   "candidates": [{"id": "candidate-without-files"}],
                                   "verifications": [], "integrations": []})
        for _ in range(4):
            view = drain.project_work(work.load_item(item["id"]))
            if (view.get("blocker") or {}).get("type") == "recovery":
                break
            fresh = work.load_item(item["id"])
            step = dict(view["next_action"]); step.pop("virtual", None); step["state"] = "done"
            work._workflow(fresh)["actions"].append(step)
            work.save_item(fresh)
        self.assertEqual((view.get("blocker") or {}).get("type"), "recovery", "the fixture reaches the stall")
        fresh = work.load_item(item["id"])
        fresh["revising"] = True
        fresh["prior_results"] = [{"at": "2026-10-09T00:00:00", "attempt": 1, "result": "Blocked."}]
        work.save_item(fresh)
        view = drain.project_work(work.load_item(item["id"]))
        self.assertNotEqual((view.get("blocker") or {}).get("type"), "recovery")
        self.assertEqual(view["next_action"]["availability"], "runnable")

    def test_newly_stale_candidate_has_runnable_reconciliation(self):
        old_head = self.git("rev-parse", "HEAD")
        item = self.card(attempt_outcome={"candidate": {"base": old_head, "tree": "candidate-tree",
                                                        "files": {"sample.txt": "100644 blob fixture"}}})
        (self.repo / "second.txt").write_text("main moved\n")
        self.git("add", "second.txt")
        self.git("commit", "-qm", "move main")
        view = drain.project_work(item)
        self.assertEqual(view["candidate_status"], "stale")
        self.assertEqual(view["blocker"]["type"], "stale_base")
        self.assertEqual(view["next_action"]["type"], "reconcile")
        self.assertEqual(view["next_action"]["availability"], "runnable")
        self.assertIn(item["id"], [row["work_id"] for row in drain.queue_view()["eligible"]])

    def test_cost_cap_holds_build_until_its_rebrief_wake(self):
        item = self.card()
        view = work.work_view(item, repo_facts={"cost_reason": "The attempt exceeded its cost cap."})
        self.assertEqual(view["blocker"]["type"], "capacity")
        self.assertEqual(view["blocker"]["owner"], "claude")
        self.assertIn("cap above the amount already spent", view["blocker"]["wake"])
        self.assertEqual(view["next_action"]["type"], "rebrief")
        self.assertEqual(view["next_action"]["owner"], "claude")
        self.assertEqual(view["next_action"]["availability"], "waiting_event")
        with patch.object(drain, "_item_spend", return_value=(1000, 3, 0, 0)):
            queue = drain.queue_view()
            self.assertNotIn(item["id"], [row["work_id"] for row in queue["eligible"]])
            self.assertNotIn(item["id"], [card["id"] for card in drain.classified_queue()[0]])
            self.assertNotIn(item["id"], [card["id"] for card, _ in drain.classified_actions()])
        self.assertEqual(queue["held"][0]["action_type"], "rebrief")
        self.assertIn("cap above the amount already spent", queue["held"][0]["workflow_view"]["next_action"]["wake"])
        work.ensure_action(item, "rebrief", input_id="legacy", owner="grace", summary="Review cap")
        held_saved = work.work_view(item, repo_facts={"cost_reason": "The attempt exceeded its cost cap."})
        self.assertEqual(held_saved["next_action"]["owner"], "claude")
        self.assertEqual(held_saved["next_action"]["availability"], "waiting_event")
        item["ask"] = "A smaller first step"
        work.save_item(item)
        with patch.object(drain, "_item_spend", return_value=(1000, 3, 0, 0)):
            still_held = drain.project_work(item)
        self.assertEqual(still_held["blocker"]["type"], "capacity")
        self.assertEqual(still_held["next_action"]["availability"], "waiting_event")
        item["cost_cap_usd"] = 1200.0
        work.save_item(item)
        with patch.object(drain, "_item_spend", return_value=(1000, 3, 0, 0)):
            after_wake = drain.project_work(item)
        self.assertEqual(after_wake["next_action"]["type"], "build")
        self.assertEqual(after_wake["next_action"]["availability"], "runnable")

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

    # -- Cards stranded 2026-09-26..28 by a wrong next step ----------------------

    def move_main(self):
        old_head = self.git("rev-parse", "HEAD")
        (self.repo / "moved.txt").write_text("main moved\n")
        self.git("add", "moved.txt")
        self.git("commit", "-qm", "move main")
        return old_head

    def test_filesless_candidate_is_not_stale_and_its_open_build_runs(self):
        # w4afc0d9982d: a tier-0 reading produced no files, was raised to a
        # build, and its empty candidate read as stale — a reconcile whose id
        # was already done, which the drain could never claim.
        old_head = self.move_main()
        empty = work.evidence_id("")
        done_reconcile = work.action_key("w4afc0d9982d", "reconcile", empty)
        item = self.card("w4afc0d9982d", tier=1, tier_raised={"from": 0}, attempts=2,
                         last_recorded_attempt="6fff1f0d", finished="2026-09-26T22:11:23-07:00",
                         attempt_outcome={"version": 1, "status": "blocked", "id": "6fff1f0d",
                                          "patch_id": empty,
                                          "candidate": {"tree": "c994c5fa", "base": old_head,
                                                        "files": {}, "base_files": {}}},
                         check={"read": True, "complete": False, "verdict": "fail", "findings": [{"what": "x"}]},
                         workflow={"version": 1, "candidates": [], "verifications": [], "integrations": [],
                                   "actions": [
                                       {"id": done_reconcile, "type": "reconcile", "input_id": empty,
                                        "state": "done", "created_at": "2026-09-26T21:51:36-07:00"},
                                       {"id": work.action_key("w4afc0d9982d", "recover", done_reconcile),
                                        "type": "recover", "input_id": done_reconcile, "state": "done",
                                        "created_at": "2026-09-26T22:11:23-07:00"},
                                       {"id": work.action_key("w4afc0d9982d", "build", "6fff1f0d"),
                                        "type": "build", "input_id": "6fff1f0d", "owner": "grace",
                                        "summary": "Run the visual check", "priority": "ordinary",
                                        "state": "open", "created_at": "2026-09-26T23:43:06-07:00"}],
                                   "blockers": [{"id": "blk_x", "type": "tooling", "state": "resolved",
                                                 "reason": "No recoverable landing transaction remains."}]})
        view = drain.project_work(item)
        self.assertIsNone(view["blocker"])
        self.assertNotEqual(view["candidate_status"], "stale")
        self.assertEqual(view["next_action"]["type"], "build")
        self.assertEqual(view["next_action"]["id"], work.action_key(item["id"], "build", "6fff1f0d"))
        self.assertEqual(view["next_action"]["availability"], "runnable")
        self.assertEqual([(card["id"], action["type"]) for card, action in drain.classified_actions()],
                         [(item["id"], "build")])

    def held_for_approval(self, ident="wbc6377da200", **over):
        """The shape of Milo's Q-130 card: a clean, reviewed docs/design change
        whose only landing gate is Daniel's yes, carrying an earlier attempt's
        open repair build and reconcile, a finished run's `started`, a stale
        base and a blown fresh-token cap."""
        old_head = self.move_main()
        files = ["docs/DECISION_LOG.md", "docs/design/06-bots-and-training.md"]
        patch_id = work.evidence_id("reviewed docs patch")
        stale_input = work.evidence_id(["e38fd850", old_head])
        fields = dict(
            state="for_review", owner="milo", tier=1, attempts=2, automatic_repairs=1,
            started="2026-09-27T23:44:11-07:00", finished="2026-09-27T23:54:01-07:00",
            last_recorded_attempt="e38fd850",
            deliverable={"name": "Mark III worm practice ruling recorded"}, recommend={},
            follow_ups=[{"title": "Measure worm practice energy costs", "owner": "milo",
                         "level": "task", "tier": 0, "first_action": "Measure it."}],
            diff={"files": files, "applied": False, "why_not": "",
                  "why_not_landed": work.approval_hold_reason("docs/design/06-bots-and-training.md")},
            check={"read": True, "complete": True, "verdict": "pass", "findings": [],
                   "summary": "The ruling is consistently recorded.", "attempt_id": "e38fd850"},
            attempt_outcome={"version": 1, "status": "complete", "id": "e38fd850", "patch_id": patch_id,
                             "candidate": {"tree": "ed866174", "base": old_head,
                                           "files": {f: "100644 blob new" for f in files},
                                           "base_files": {f: "100644 blob old" for f in files}}},
            workflow={"version": 1, "candidates": [], "verifications": [], "integrations": [],
                      "actions": [
                          {"id": work.action_key(ident, "build", "legacy"), "type": "build",
                           "input_id": "legacy", "state": "done", "created_at": "2026-09-27T14:24:02-07:00"},
                          {"id": work.action_key(ident, "reconcile", "older"), "type": "reconcile",
                           "input_id": "older", "state": "done", "created_at": "2026-09-27T14:32:10-07:00"},
                          {"id": work.action_key(ident, "build", "repair:40674322"), "type": "build",
                           "input_id": "repair:40674322", "owner": "milo", "priority": "retry",
                           "summary": "Repair the last attempt", "state": "open",
                           "created_at": "2026-09-27T23:44:02-07:00"},
                          {"id": work.action_key(ident, "reconcile", stale_input), "type": "reconcile",
                           "input_id": stale_input, "owner": "milo", "priority": "reconciliation",
                           "summary": "Rebuild this candidate on current main", "state": "open",
                           "created_at": "2026-09-27T23:54:01-07:00"}],
                      "blockers": [{"id": "blk_y", "type": "missing_evidence", "input_id": stale_input,
                                    "state": "open", "owner": "milo",
                                    "reason": work.approval_hold_reason("docs/design/06-bots-and-training.md"),
                                    "action_id": work.action_key(ident, "reconcile", stale_input)}]})
        fields.update(over)
        return self.card(ident, **fields)

    def test_clean_result_held_for_his_yes_is_his_decision(self):
        item = self.held_for_approval()
        over_cap = (0.0, 2, 1_539_006, 221_886)
        with patch.object(drain, "_item_spend", return_value=over_cap):
            view = drain.project_work(item)
            self.assertIsNone(view["blocker"])
            self.assertEqual(view["next_action"]["type"], "decide")
            self.assertEqual(view["next_action"]["owner"], "daniel")
            self.assertIn("docs/design/06-bots-and-training.md", view["next_action"]["summary"])
            self.assertEqual(view["candidate_status"], "awaiting_approval")
            # The leftovers from earlier attempts start no model work.
            self.assertEqual(drain.classified_actions(), [])
            self.assertEqual(drain.queued(), [])
            queue = drain.queue_view()
            self.assertEqual(queue["eligible"] + queue["held"] + queue["working"], [])
            self.assertEqual(work.card_lanes(item, view), ["daniel"])
            self.assertTrue(work.work_ready_for_daniel(item, view))
            with patch.object(server, "api_queue", return_value={"curated": [], "decided": [], "rulings": {}}):
                waiting = server.waiting_on_you()
        self.assertEqual([row["source_id"] for row in waiting["ready"]], [item["id"]])
        # A session already running an older step is shown as running, not as
        # a decision nobody can make while it works.
        running = item["workflow"]["actions"][3]["id"]
        work.claim_action(item, running, "run:1")
        live = work.work_view(item, {"active_session": "run"})
        self.assertEqual((live["next_action"]["id"], live["availability"]), (running, "running"))

    def test_a_hold_that_no_file_needs_any_more_leaves_his_page(self):
        item = self.held_for_approval()
        self.assertTrue(work.landing_awaits_approval(item))
        shots = ["docs/design/mockups/industrial_barn/review_interior.png"]
        outcome = dict(item["attempt_outcome"])
        outcome["candidate"] = {**outcome["candidate"],
                                "files": {f: "100644 blob new" for f in shots},
                                "base_files": {f: "100644 blob old" for f in shots}}
        item = {**item, "attempt_outcome": outcome,
                "diff": {**item["diff"], "files": shots,
                         "why_not_landed": work.approval_hold_reason(shots[0])}}
        self.assertFalse(work.landing_awaits_approval(item))
        view = drain.project_work(item)
        self.assertNotEqual(view["next_action"]["owner"], "daniel")
        self.assertFalse(work.work_ready_for_daniel(item, view))
        self.assertEqual((view["next_action"]["type"], view["next_action"]["availability"]),
                         ("reconcile", "runnable"))

    def test_his_yes_merges_that_patch_with_no_model_call(self):
        item = self.held_for_approval()
        before = item["_revision"]
        saved = work.api_post("/api/work/accept", {"id": item["id"]})
        self.assertEqual(saved["state"], "for_review", "a yes to merge is not a close")
        self.assertEqual(saved["landing_approved"]["patch_id"], item["attempt_outcome"]["patch_id"])
        self.assertGreater(saved["_revision"], before)
        view = drain.project_work(saved)
        self.assertEqual(view["next_action"]["type"], "reconcile")
        self.assertEqual(view["next_action"]["owner"], "claude")
        self.assertEqual(view["next_action"]["availability"], "runnable")
        self.assertEqual(view["candidate_status"], "reviewed")
        self.assertFalse(work.work_ready_for_daniel(saved, view))
        self.assertEqual([(card["id"], action["type"]) for card, action in drain.classified_actions()],
                         [(item["id"], "reconcile")])
        ctx = {"item": saved, "action": view["next_action"], "claim_id": ""}
        record = {"attempt_id": "e38fd850", "result": "Done.", "patch": "reviewed docs patch",
                  "check": saved["check"], "candidate": saved["attempt_outcome"]["candidate"]}
        with patch.object(drain, "recorded_candidate_attempt", return_value=record) as found, \
                patch.object(drain, "approved_files_moved", return_value=False), \
                patch.object(drain, "do_item", side_effect=AssertionError("no model session")):
            rec = drain._work_item(ctx, {}, "run", print)
        found.assert_called_once_with(saved, current_base=False)
        self.assertTrue(rec["verification_only"])
        self.assertEqual(rec["usage"], [])
        with patch.object(drain, "recorded_candidate_attempt", return_value=None), \
                patch.object(drain, "approved_files_moved", return_value=False), \
                patch.object(drain, "do_item", side_effect=AssertionError("no model session")):
            missing = drain._work_item(ctx, {}, "run", print)
        self.assertTrue(missing["held"])
        self.assertIn("approved", missing["error"])
        # Once main has changed one of its files the exact patch can never land
        # (2026-10-09: five hours of zero-cost retries); it is merged and read again.
        with patch.object(drain, "approved_files_moved", return_value=True), \
                patch.object(drain, "held_recheck_source", return_value=None), \
                patch.object(drain, "verified_landing_source", return_value=None), \
                patch.object(drain, "do_item", return_value={"merged": True}) as merged:
            again = drain._work_item(ctx, {}, "run", print)
        self.assertEqual(again, {"merged": True})
        merged.assert_called_once()

    def test_leftover_build_on_a_card_in_review_starts_nothing(self):
        item = self.card(state="for_review", tier=0, started="2026-09-27T10:00:00+00:00",
                         finished="2026-09-27T10:05:00+00:00",
                         check={"read": True, "complete": True, "verdict": "pass", "findings": []},
                         workflow={"version": 1, "candidates": [], "verifications": [], "integrations": [],
                                   "blockers": [],
                                   "actions": [{"id": work.action_key("w111111111111", "build", "repair:a"),
                                                "type": "build", "input_id": "repair:a", "state": "open",
                                                "priority": "retry", "created_at": "2026-09-27T09:00:00+00:00"}]})
        view = drain.project_work(item)
        self.assertIsNone(view["blocker"], "a finished run's start stamp is not a lost claim")
        self.assertEqual(view["next_action"]["type"], "decide")
        self.assertEqual(drain.classified_actions(), [])

    def test_stalled_transition_is_held_with_a_reason(self):
        item = self.card(last_recorded_attempt="a1", attempt_outcome={"patch_id": "a1"})
        build = work.ensure_action(item, "build", input_id="a1")
        work.claim_action(item, build["id"], "c1")
        work.finish_action(item, build["id"], "c1")
        recover = work.ensure_action(item, "recover", input_id=build["id"])
        work.claim_action(item, recover["id"], "c2")
        work.finish_action(item, recover["id"], "c2")
        view = drain.project_work(item)
        self.assertEqual(view["next_action"]["availability"], "blocked")
        self.assertEqual(drain.classified_actions(), [])
        held = drain.queue_view()["held"]
        self.assertEqual([row["work_id"] for row in held], [item["id"]])
        self.assertIn("did not advance this card", held[0]["reason"])
        self.assertEqual(work.card_lanes(item, view), ["held"])

    def test_repair_beside_an_open_build_is_never_an_already_finished_step(self):
        old_head = self.move_main()
        item = self.card(attempt_outcome={"patch_id": "p1", "candidate": {
            "base": old_head, "tree": "t", "files": {"sample.txt": "100644 blob x"}}})
        done = work.ensure_action(item, "reconcile", input_id="p1")
        work.claim_action(item, done["id"], "c1")
        work.finish_action(item, done["id"], "c1")
        work.ensure_action(item, "build", input_id="retry")
        view = drain.project_work(item)
        self.assertNotEqual(view["next_action"]["id"], done["id"])
        self.assertEqual(drain.classified_actions(), [])
        self.assertIn("Local main changed", drain.queue_view()["held"][0]["reason"])


if __name__ == "__main__":
    unittest.main()

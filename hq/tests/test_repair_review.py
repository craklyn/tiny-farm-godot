#!/usr/bin/env python3
"""The chief of staff reviews a card whose automatic repairs are used up.

Before this (2026-09-28) a card the reviewer failed again after its automatic
repair waited for a "supervised retry" nothing ever gave; six cards sat that way
for a day or more. Now the chief of staff gives it one more supervised try with a
sharper brief, brings it to Daniel with a recommendation his yes enacts, or closes
work that is no longer needed. No model runs here: the review call is stubbed.
"""
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("HQ_TEST_SCRATCH", tempfile.mkdtemp(prefix="hq-repair-review-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import action_dispatch  # noqa: E402
import drain  # noqa: E402
import server  # noqa: E402
import work  # noqa: E402
from test_drain import fake_host, ORG  # noqa: E402

BRIEF = "Add a test that buys the second pace upgrade and asserts its price is 40 coins."
RETRY = json.dumps({"outcome": "retry", "brief": BRIEF,
                    "reason": "One concrete finding remains: the second price has no test."})
DANIEL = json.dumps({"outcome": "daniel", "reason": "The same finding came back three times.",
                     "recommend": {"question": "Should the pace upgrade have a second tier at all?",
                                   "answer": "Drop the second tier and ship one upgrade.",
                                   "why": "Every attempt failed on the second tier's price.",
                                   "instead": "Keep both tiers and set the price yourself."}})
CLOSE = json.dumps({"outcome": "close", "reason": "Commit abc123 on main already adds both purchases."})
HOLD = "The repair still needs verification; the owner must resolve the remaining findings."


class RepairReview(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.host = fake_host(self.tmp.name)
        self.host.load_json = lambda path: json.loads(Path(path).read_text())
        self.host.limited_until = lambda: None
        work.bind(self.host)
        self.workers = os.path.join(self.tmp.name, "workers")
        os.makedirs(os.path.join(self.workers, "run1"))
        self.calls = []
        self.reply = (RETRY, False)
        self.active = {}
        stubs = [
            patch.object(drain, "WORKERS", self.workers),
            patch.object(drain.server, "drain_state", lambda: self.active),
            patch.object(work.execution, "launch_allowed", lambda **kw: True),
            patch.object(work, "_run_cli", self.fake_cli),
            # His comment on a yes is answered on the card by a model; not here.
            patch.object(work, "_begin_answering", lambda item: None),
        ]
        for stub in stubs:
            stub.start()
            self.addCleanup(stub.stop)
        work._REPAIR_SCAN["at"] = 0.0

    def tearDown(self):
        self.tmp.cleanup()

    def fake_cli(self, *args, **kwargs):
        self.calls.append((args, kwargs))
        return self.reply

    def card(self, item_id="wdef000000001", **over):
        base = {"id": item_id, "title": "Build separate pace purchases", "level": "task",
                "owner": "sam", "tier": 1, "tier_reason": "code behind tests",
                "ask": "Sell the pace upgrade in two steps.", "first_action": "Read the shop.",
                "state": "for_review", "thread": "sam", "source": "chat", "source_message": "",
                "result": "Both purchases work; the second price is untested.", "started": "",
                "attempts": 3, "created": "2026-09-20T01:00", "created_ts": 1.0,
                "automatic_repairs": 2, "repair_hold": HOLD,
                "repair_brief": "The price test is missing.\n[]",
                "last_recorded_attempt": "att3",
                "attempt_outcome": {"id": "att3", "status": "complete"},
                "recommend": {"question": "Q", "answer": "A", "why": "W", "instead": "I"},
                "attempt_history": [{"status": "complete", "reason": "first try"}],
                "check": {"verdict": "fail", "summary": "The second price has no test.",
                          "findings": [{"what": "No test buys the second pace upgrade."}],
                          "attempt_id": "att3"},
                "prior_checks": [{"verdict": "fail", "summary": "Two purchases untested."}]}
        base.update(over)
        return work.save_item(base)

    def view(self, item):
        return drain.project_work(work.load_item(item["id"]), head="", active=self.active)

    def step(self, item):
        action = self.view(item).get("next_action") or {}
        return action.get("type"), action.get("availability")

    def test_retry_gives_one_supervised_try_the_drain_runs(self):
        item = self.card()
        self.assertEqual(self.step(item), ("reconcile", "waiting_event"))
        self.assertEqual(action_dispatch.choose(drain), [])
        self.assertEqual([i["id"] for i in work.exhausted_repairs_due()], [item["id"]])
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        got = work.load_item(item["id"])
        self.assertEqual(got["repair_brief"], BRIEF)
        self.assertIs(got["supervised_retry"], True)
        self.assertEqual(got["repair_hold"], HOLD)
        self.assertEqual(got["state"], "for_review")
        review = got["repair_reviews"][-1]
        self.assertEqual((review["by"], review["decision"], review["attempt_id"]),
                         ("claude", "retry", "att3"))
        self.assertIn("second price has no test", review["reason"])
        self.assertEqual(review["brief"], BRIEF)
        self.assertNotIn("repair_review_tries", got)
        # The next step is a distinct supervised action the drain selects.
        self.assertEqual(self.step(got), ("reconcile", "runnable"))
        chosen = action_dispatch.choose(drain)
        self.assertEqual([(i["id"], a["type"]) for i, a in chosen], [(item["id"], "reconcile")])
        self.assertIn(work.action_key(item["id"], "supervised_retry", "att3"), chosen[0][1]["input_id"])
        # The owner's next brief carries the sharper instruction.
        self.assertIn("REPAIR YOUR OWN RESULT: " + BRIEF, work.revision_brief(got))
        # Nothing reviews it again while that try is pending.
        self.assertEqual(work.exhausted_repairs_due(), [])
        args, kwargs = self.calls[0]
        self.assertEqual((args[2], args[3], args[4]), ("Read,Glob,Grep", 8, 300))
        self.assertEqual((kwargs["phase"], kwargs["seat"], kwargs["item"]),
                         ("repair-review", "claude", item["id"]))
        self.assertIn("Build separate pace purchases", args[0])
        self.assertIn("No test buys the second pace upgrade.", args[0])
        self.assertIn("Two purchases untested.", args[0])
        self.assertIn("WHAT THE STUDIO CHANGED ABOUT THIS CARD", args[0])

    def test_a_new_failed_attempt_can_be_reviewed_again_until_the_hard_limit(self):
        item = self.card()
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        # The supervised try ran and failed: the drain pops the flag and records
        # a new attempt; the reviewer's hold is back.
        got = work.load_item(item["id"])
        got.pop("supervised_retry")
        got.update(last_recorded_attempt="att4", attempt_outcome={"id": "att4", "status": "complete"})
        work.save_item(got)
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        got = work.load_item(item["id"])
        self.assertEqual([r["attempt_id"] for r in got["repair_reviews"]], ["att3", "att4"])
        got.pop("supervised_retry")
        got.update(last_recorded_attempt="att5", attempt_outcome={"id": "att5", "status": "complete"})
        work.save_item(got)
        # Two of the chief of staff's own retries: the third goes to Daniel unasked.
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        self.assertEqual(len(self.calls), 2)
        got = work.load_item(item["id"])
        self.assertEqual(got["state"], "needs_approval")
        self.assertFalse(work.recommendation_gaps(got["recommend"]))
        self.assertIn("2 more tries", got["recommend"]["question"])
        self.assertEqual(got["repair_reviews"][-1]["decision"], "daniel")

    def test_daniel_path_is_ready_for_him_and_his_yes_requeues_one_try(self):
        # A persisted blocker from the failed attempt must not hide his question.
        item = self.card(workflow={"version": work.WORKFLOW_VERSION, "actions": [],
                                   "blockers": [{"id": "blk_x", "type": "missing_evidence",
                                                 "reason": HOLD, "state": "open", "files": [],
                                                 "owner": "sam", "input_id": "att3"}],
                                   "candidates": [], "verifications": [], "integrations": []})
        self.reply = (DANIEL, False)
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        got = work.load_item(item["id"])
        self.assertEqual(got["state"], "needs_approval")
        self.assertNotIn("repair_hold", got)
        self.assertEqual(got["repair_checkpoint"]["repair_hold"], HOLD)
        self.assertEqual(got["recommend"]["answer"], "Drop the second tier and ship one upgrade.")
        self.assertFalse(work.recommendation_gaps(got["recommend"]))
        self.assertEqual(got["repair_reviews"][-1]["decision"], "daniel")
        view = drain.project_work(got, head="", active={})
        self.assertEqual((view["next_action"] or {}).get("type"), "decide")
        self.assertIsNone(view["blocker"])
        self.assertTrue(work.work_ready_for_daniel(got, view))
        self.assertEqual(work.card_lanes(got, view), ["daniel"])
        with patch.object(server, "api_queue", lambda **kw: {"curated": [], "decided": [], "rulings": {}}):
            waiting = server.waiting_on_you()
        self.assertIn(item["id"], {row["source_id"] for row in waiting["ready"]})
        # Nothing reviews it again while it waits on him.
        self.calls.clear()
        self.assertFalse(work.review_next_exhausted_repair(ORG))
        self.assertEqual(self.calls, [])
        # His yes: one supervised try, his answer as the owner's instruction.
        saved = work.api_post("/api/work/approve", {"id": item["id"], "_revision": got["_revision"],
                                                     "comment": "Keep the shop layout as it is."})
        self.assertEqual(saved["state"], "for_review")
        self.assertNotIn("repair_checkpoint", saved)
        self.assertEqual(saved["repair_hold"], HOLD)
        self.assertIs(saved["supervised_retry"], True)
        self.assertEqual(saved["recommend"], {"question": "Q", "answer": "A", "why": "W", "instead": "I"})
        self.assertIn("Drop the second tier and ship one upgrade.", saved["repair_brief"])
        self.assertIn("Keep the shop layout as it is.", saved["repair_brief"])
        self.assertEqual(saved["decided"]["answer"], "Drop the second tier and ship one upgrade.")
        self.assertEqual((saved["repair_reviews"][-1]["by"], saved["repair_reviews"][-1]["decision"]),
                         ("daniel", "retry"))
        self.assertEqual(self.step(saved), ("reconcile", "runnable"))
        self.assertEqual([i["id"] for i, _a in action_dispatch.choose(drain)], [item["id"]])

    def test_close_closes_ordinary_work_but_never_a_ruling_or_tier_two(self):
        self.reply = (CLOSE, False)
        plain = self.card()
        self.assertTrue(work.review_exhausted_repair(work.load_item(plain["id"]), ORG))
        got = work.load_item(plain["id"])
        self.assertEqual(got["state"], "dropped")
        self.assertTrue(got["closed"])
        self.assertIn("abc123", got["result"])
        self.assertEqual(got["repair_reviews"][-1]["decision"], "close")
        self.assertEqual(self.view(got)["next_action"], None)

        for item_id, over in (("wdef000000002", {"ruling_id": "Q-130"}), ("wdef000000003", {"tier": 2})):
            card = self.card(item_id, **over)
            self.assertTrue(work.review_exhausted_repair(work.load_item(card["id"]), ORG))
            got = work.load_item(card["id"])
            self.assertEqual(got["state"], "needs_approval", item_id)
            self.assertFalse(work.recommendation_gaps(got["recommend"]))
            self.assertIn("abc123", got["recommend"]["why"])
            self.assertEqual(got["repair_reviews"][-1]["decision"], "daniel")

    def test_paused_or_dry_does_nothing(self):
        item = self.card()
        before = work.load_item(item["id"])
        with patch.object(work.execution, "launch_allowed", lambda **kw: False):
            self.assertFalse(work.review_next_exhausted_repair(ORG))
            self.assertFalse(work.review_exhausted_repair(before, ORG))
        self.host.limited_until = lambda: 1e12
        self.assertFalse(work.review_next_exhausted_repair(ORG))
        self.assertEqual(self.calls, [])
        self.assertEqual(work.load_item(item["id"])["_revision"], before["_revision"])

    def test_a_dry_allowance_never_uses_up_a_try(self):
        item = self.card()
        self.reply = ("", True)
        for _ in range(5):
            self.assertFalse(work.review_next_exhausted_repair(ORG))
        got = work.load_item(item["id"])
        self.assertEqual((got["state"], got.get("repair_review_tries", 0)), ("for_review", 0))
        self.assertNotIn("supervised_retry", got)
        self.assertEqual(len(self.calls), 5)

    def test_a_failing_review_retries_then_goes_to_daniel(self):
        item = self.card()
        self.reply = ("not json", False)
        for tries in (1, 2):
            self.assertFalse(work.review_next_exhausted_repair(ORG))
            got = work.load_item(item["id"])
            self.assertEqual((got["state"], got["repair_review_tries"]), ("for_review", tries))
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        got = work.load_item(item["id"])
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(got["state"], "needs_approval")
        self.assertFalse(work.recommendation_gaps(got["recommend"]))
        self.assertEqual(got["repair_reviews"][-1]["decision"], "daniel")
        self.assertNotIn("repair_review_tries", got)

    def test_cards_that_are_someone_elses_are_never_reviewed(self):
        held = self.card("wdef000000011", repair_hold="",
                         diff={"applied": False, "why_not_landed": work.approval_hold_reason("project.godot")},
                         attempt_outcome={"status": "complete", "id": "att3", "patch_id": "p1",
                                          "candidate": {"files": {"project.godot": "blob"}}},
                         check={"read": True, "verdict": "pass", "complete": True,
                                "findings": [], "attempt_id": "att3"})
        self.assertTrue(work.landing_awaits_approval(held))
        checkpoint = self.card("wdef000000012", state="needs_approval",
                               spending_checkpoint={"at": "x", "return_state": "for_review"})
        outside = self.card("wdef000000013", outside_claim={"by": "a session",
                                                            "expires_ts": time.time() + 3600})
        running = self.card("wdef000000014")
        self.active = {"run": "run1", "items": [running["id"]]}
        with patch.object(drain.server, "drain_entry",
                          lambda active, item_id: item_id == running["id"]):
            self.assertEqual(self.view(running)["availability"], "running")
            closed = self.card("wdef000000015", state="landed")
            granted = self.card("wdef000000016", supervised_retry=True)
            # Over its spending cap: the spending review's first, not this one.
            capped = self.card("wdef000000017", token_cap=1000)
            with open(os.path.join(self.workers, "run1", f"{capped['id']}-drain-work.json"), "w",
                      encoding="utf-8") as sink:
                json.dump({"usage": {"tokens": 5000, "fresh": 100, "list_usd": None}}, sink)
            self.assertEqual(work.exhausted_repairs_due(), [])
            self.assertFalse(work.review_next_exhausted_repair(ORG))
            for card in (held, checkpoint, closed, granted):
                self.assertFalse(work.review_exhausted_repair(work.load_item(card["id"]), ORG), card["id"])
            self.assertEqual(self.calls, [])
            self.assertEqual([i["id"] for i in work.spending_checkpoints_due()], [capped["id"]])
            self.assertNotIn(outside["id"], [i["id"] for i in work.exhausted_repairs_due()])


if __name__ == "__main__":
    unittest.main()

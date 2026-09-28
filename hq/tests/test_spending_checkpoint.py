#!/usr/bin/env python3
"""The chief of staff reviews a card stopped at its per-card spending cap.

Daniel's policy (2026-09-28): the cap is a checkpoint, not a wall. Spending that
buys progress runs on one bounded step; a card that is not converging goes to
him with what it spent. No model runs here: the review call is stubbed.
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("HQ_TEST_SCRATCH", tempfile.mkdtemp(prefix="hq-cap-review-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain  # noqa: E402
import server  # noqa: E402
import work  # noqa: E402
from test_drain import fake_host, ORG  # noqa: E402

EXTEND = '{"outcome":"extend","reason":"The last check narrowed to one missing test; that is all that remains."}'
DANIEL = json.dumps({"outcome": "daniel", "reason": "The same failure repeated three times.",
                     "recommend": {"question": "Keep going?", "answer": "Rework the approach first.",
                                   "why": "Three checks failed on the same point.",
                                   "instead": "Give it one more step as it stands.",
                                   "move": "rethink"}})


class SpendingCheckpoint(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.host = fake_host(self.tmp.name)
        self.host.load_json = lambda path: json.loads(Path(path).read_text())
        self.host.limited_until = lambda: None
        work.bind(self.host)
        self.workers = os.path.join(self.tmp.name, "workers")
        os.makedirs(os.path.join(self.workers, "run1"))
        self.calls = []
        self.reply = (EXTEND, False)
        stubs = [
            patch.object(drain, "WORKERS", self.workers),
            patch.object(drain.server, "drain_state", lambda: {}),
            patch.object(work.execution, "launch_allowed", lambda **kw: True),
            patch.object(work, "_run_cli", self.fake_cli),
        ]
        for stub in stubs:
            stub.start()
            self.addCleanup(stub.stop)
        work._CAP_SCAN["at"] = 0.0

    def tearDown(self):
        self.tmp.cleanup()

    def fake_cli(self, *args, **kwargs):
        self.calls.append((args, kwargs))
        return self.reply

    def spend(self, item_id, tokens, fresh, session="drain-work"):
        with open(os.path.join(self.workers, "run1", f"{item_id}-{session}.json"), "w",
                  encoding="utf-8") as sink:
            json.dump({"usage": {"tokens": tokens, "fresh": fresh, "list_usd": None}}, sink)

    def card(self, item_id="wcab000000001", **over):
        base = {"id": item_id, "title": "Record the worm ruling", "level": "task", "owner": "sam",
                "tier": 1, "tier_reason": "docs", "ask": "Record it.", "first_action": "Read it.",
                "state": "waiting_session", "thread": "sam", "source": "chat",
                "source_message": "", "result": "Checks narrowed each time.", "started": "",
                "attempts": 2, "created": "2026-09-20T01:00", "created_ts": 1.0,
                "recommend": {"question": "Q", "answer": "A", "why": "W", "instead": "I"},
                "prior_checks": [{"verdict": "fail", "summary": "Two contradictions."},
                                 {"verdict": "fail", "summary": "One contradiction."}]}
        base.update(over)
        return work.save_item(base)

    def next_step(self, item):
        return (drain.project_work(work.load_item(item["id"]), head="", active={})
                .get("next_action") or {}).get("type")

    def test_extend_raises_only_the_exceeded_cap_by_one_step(self):
        item = self.card()
        self.spend(item["id"], 1_200_000, 100_000)
        self.assertEqual(self.next_step(item), "rebrief")
        self.assertEqual([i["id"] for i in work.spending_checkpoints_due()], [item["id"]])
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        got = work.load_item(item["id"])
        self.assertEqual(got["token_cap"], 2_200_000)
        self.assertNotIn("fresh_token_cap", got)
        self.assertNotIn("cost_cap_usd", got)
        review = got["cap_reviews"][-1]
        self.assertEqual((review["by"], review["decision"]), ("claude", "extend"))
        self.assertEqual((review["spent_tokens"], review["spent_fresh"]), (1_200_000, 100_000))
        self.assertEqual(review["old_caps"]["token_cap"], 1_000_000)
        self.assertEqual(review["new_caps"]["token_cap"], 2_200_000)
        self.assertIn("one missing test", review["reason"])
        self.assertEqual(got["state"], "waiting_session")
        self.assertEqual(self.next_step(got), "build")
        self.assertEqual(work.spending_checkpoints_due(), [])
        args, kwargs = self.calls[0]
        self.assertEqual((args[2], args[3], args[4]), ("Read,Glob,Grep", 8, 300))
        self.assertEqual((kwargs["phase"], kwargs["seat"]), ("cap-review", "claude"))
        self.assertIn("Record the worm ruling", args[0])
        self.assertIn("One contradiction.", args[0])

    def test_fresh_cap_is_raised_alone(self):
        item = self.card()
        self.spend(item["id"], 500_000, 200_000)
        self.assertTrue(work.review_spending_checkpoint(work.load_item(item["id"]), ORG))
        got = work.load_item(item["id"])
        self.assertEqual(got["fresh_token_cap"], 350_000)
        self.assertNotIn("token_cap", got)

    def test_not_converging_goes_to_daniel_and_his_yes_requeues(self):
        item = self.card()
        self.spend(item["id"], 4_900_000, 120_000)
        work.save_item(dict(work.load_item(item["id"]), token_cap=4_000_000))
        self.reply = (DANIEL, False)
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        got = work.load_item(item["id"])
        self.assertEqual(got["state"], "needs_approval")
        self.assertFalse(work.recommendation_gaps(got["recommend"]))
        self.assertTrue(got["recommend"]["question"].startswith("This card has spent 4.9 million tokens"))
        self.assertEqual(got["cap_reviews"][-1]["decision"], "daniel")
        view = drain.project_work(got, head="", active={})
        self.assertTrue(work.work_ready_for_daniel(got, view))
        self.assertEqual(work.card_lanes(got, view), ["daniel"])
        with patch.object(server, "api_queue", lambda **kw: {"curated": [], "decided": [], "rulings": {}}):
            waiting = server.waiting_on_you()
        self.assertIn(item["id"], {row["source_id"] for row in waiting["ready"]})
        # Nothing reviews it again while it waits on him.
        self.calls.clear()
        self.assertFalse(work.review_next_spending_checkpoint(ORG))
        self.assertEqual(self.calls, [])
        # His yes grants one bounded step and puts the card back in the queue.
        saved = work.api_post("/api/work/approve", {"id": item["id"], "_revision": got["_revision"]})
        self.assertEqual(saved["state"], "waiting_session")
        self.assertEqual(saved["token_cap"], 5_900_000)
        self.assertEqual(saved["recommend"], {"question": "Q", "answer": "A", "why": "W", "instead": "I"})
        self.assertNotIn("spending_checkpoint", saved)
        self.assertIn("Rework the approach first.", saved["ask"])
        self.assertEqual((saved["cap_reviews"][-1]["by"], saved["cap_reviews"][-1]["decision"]),
                         ("daniel", "extend"))
        self.assertEqual(self.next_step(saved), "build")

    def test_hard_limits_skip_the_model(self):
        three = [{"decision": "extend", "by": "claude"}] * 3
        item = self.card(cap_reviews=three, token_cap=4_000_000)
        self.spend(item["id"], 4_100_000, 100_000)
        self.assertTrue(work.review_spending_checkpoint(work.load_item(item["id"]), ORG))
        self.assertEqual(self.calls, [])
        got = work.load_item(item["id"])
        self.assertEqual(got["state"], "needs_approval")
        self.assertFalse(work.recommendation_gaps(got["recommend"]))
        self.assertIn("3 extensions", got["recommend"]["question"])

        high = self.card("wcab000000002", token_cap=9_500_000)
        self.spend(high["id"], 9_600_000, 100_000)
        self.assertTrue(work.review_spending_checkpoint(work.load_item(high["id"]), ORG))
        self.assertEqual(self.calls, [])
        high = work.load_item(high["id"])
        self.assertEqual((high["state"], high["token_cap"]), ("needs_approval", 9_500_000))
        self.assertIn("most the studio may allow", high["recommend"]["question"])

    def test_paused_or_dry_does_nothing(self):
        item = self.card()
        self.spend(item["id"], 1_200_000, 100_000)
        before = work.load_item(item["id"])
        with patch.object(work.execution, "launch_allowed", lambda **kw: False):
            self.assertFalse(work.review_next_spending_checkpoint(ORG))
            self.assertFalse(work.review_spending_checkpoint(before, ORG))
        self.host.limited_until = lambda: 1e12
        self.assertFalse(work.review_next_spending_checkpoint(ORG))
        self.assertEqual(self.calls, [])
        self.assertEqual(work.load_item(item["id"])["_revision"], before["_revision"])

    def test_approval_held_and_closed_cards_are_never_reviewed(self):
        held = self.card(state="for_review",
                         diff={"applied": False, "why_not_landed": work.approval_hold_reason("project.godot")},
                         attempt_outcome={"status": "complete", "id": "a1", "patch_id": "p1",
                                          "candidate": {"files": {"project.godot": "blob"}}},
                         check={"read": True, "verdict": "pass", "complete": True,
                                "findings": [], "attempt_id": "a1"})
        self.assertTrue(work.landing_awaits_approval(held))
        closed = self.card("wcab000000003", state="landed")
        for card in (held, closed):
            self.spend(card["id"], 3_000_000, 400_000)
            self.assertFalse(work.review_spending_checkpoint(work.load_item(card["id"]), ORG))
        self.assertEqual(work.spending_checkpoints_due(), [])
        self.assertFalse(work.review_next_spending_checkpoint(ORG))
        self.assertEqual(self.calls, [])

    def test_a_failing_review_retries_then_goes_to_daniel(self):
        item = self.card()
        self.spend(item["id"], 1_200_000, 100_000)
        self.reply = ("", True)
        for tries in (1, 2):
            self.assertFalse(work.review_next_spending_checkpoint(ORG))
            got = work.load_item(item["id"])
            self.assertEqual((got["state"], got["cap_review_tries"]), ("waiting_session", tries))
        self.reply = ("not json", False)
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        got = work.load_item(item["id"])
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(got["state"], "needs_approval")
        self.assertFalse(work.recommendation_gaps(got["recommend"]))
        self.assertEqual(got["cap_reviews"][-1]["decision"], "daniel")
        self.assertNotIn("cap_review_tries", got)


if __name__ == "__main__":
    unittest.main()

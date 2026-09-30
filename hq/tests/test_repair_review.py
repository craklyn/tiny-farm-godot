#!/usr/bin/env python3
"""The chief of staff reviews a card whose automatic repairs are used up.

Before this (2026-09-28) a card the reviewer failed again after its automatic
repair waited for a "supervised retry" nothing ever gave; six cards sat that way
for a day or more. Now the chief of staff gives it one more supervised try with a
sharper brief or closes work that is no longer needed. Where the automatic review
stops, the card waits in the queue's held lane for the chief of staff (S-38,
extended to repairs 2026-09-29) and never reaches Daniel's page; `hq/card.py
extend` or `retry` gives it one more try. No model runs here: the review call is
stubbed.
"""
import re
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
HOLD_ANSWER = json.dumps({"outcome": "hold", "reason": "The same finding came back three times.",
                          "suggest": "Drop the second tier and ship one upgrade."})
CLOSE = json.dumps({"outcome": "close", "reason": "Commit abc123 on main already adds both purchases."})
HOLD = "The repair still needs verification; the owner must resolve the remaining findings."
HELD_TAIL = "waiting for the chief of staff to give one more try, rescope or close it."
COS = "Claude chief-of-staff session"


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

    def waiting(self):
        with patch.object(server, "api_queue", lambda **kw: {"curated": [], "decided": [], "rulings": {}}):
            return server.waiting_on_you()

    def assert_held_for_chief_of_staff(self, item_id, tries, reason_has):
        """Held in the queue with a plain reason, owned by the chief of staff:
        one lane (held), a healthy lane check, and nothing on Daniel's page."""
        got = work.load_item(item_id)
        self.assertIn(got["state"], work.REPAIR_REVIEW_STATES)
        self.assertTrue(work.repair_held(got))
        self.assertEqual(got["repair_hold"], HOLD, "the repair hold stays on the card")
        view = drain.project_work(got, head="", active={})
        self.assertEqual(view["blocker"]["type"], "repairs_used_up")
        self.assertEqual(view["blocker"]["owner"], "claude")
        reason = view["blocker"]["reason"]
        self.assertTrue(reason.startswith(f"Its repairs are used up after {tries} tries; " + HELD_TAIL), reason)
        self.assertIn(reason_has, reason)
        self.assertEqual(view["next_action"]["type"], "repairs_used_up")
        self.assertEqual(view["next_action"]["owner"], "claude")
        self.assertNotEqual(view["next_action"]["availability"], "runnable")
        self.assertEqual(work.card_lanes(got, view), ["held"])
        health = work.card_health([(got, view)], ["sam", "claude"])
        self.assertTrue(health["ok"], health["problems"])
        self.assertEqual(health["counts"]["held"], 1)
        self.assertFalse(work.work_ready_for_daniel(got, view))
        waiting = self.waiting()
        self.assertNotIn(item_id, {row["source_id"] for row in waiting["ready"]})
        self.assertEqual(waiting["count"], 0)
        with patch.object(drain.server, "drain_entry", lambda active, item_id: False):
            queue = drain.queue_view()
        held = {row["work_id"]: row["reason"] for row in queue["held"]}
        self.assertEqual(held.get(item_id), reason)
        self.assertNotIn(item_id, [row["work_id"] for row in queue["eligible"]])
        self.assertEqual(action_dispatch.choose(drain), [])
        # Neither automatic review picks it up again while it waits.
        self.assertNotIn(item_id, [i["id"] for i in work.exhausted_repairs_due()])
        self.assertNotIn(item_id, [i["id"] for i in work.spending_checkpoints_due()])
        self.assertEqual((got["repair_reviews"][-1]["by"], got["repair_reviews"][-1]["decision"]),
                         ("claude", "hold"))
        return got

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
        # Two of the chief of staff's own retries: the third is held for the
        # chief of staff unasked, never sent to Daniel (S-38).
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        self.assertEqual(len(self.calls), 2)
        got = self.assert_held_for_chief_of_staff(item["id"], 4, "already given it 2 more tries")
        self.assertEqual(got["state"], "for_review")
        self.assertEqual(got["recommend"], {"question": "Q", "answer": "A", "why": "W", "instead": "I"})

    def test_a_hold_answer_waits_for_the_chief_of_staff_not_daniel(self):
        # S-38 (2026-09-29): this used to put a "give its owner one more
        # attempt?" question on his page, which then kept it off because its
        # code was unverified, so it sat in no lane. A persisted blocker from
        # the failed attempt must not hide the hold's own reason.
        item = self.card(workflow={"version": work.WORKFLOW_VERSION, "actions": [],
                                   "blockers": [{"id": "blk_x", "type": "missing_evidence",
                                                 "reason": HOLD, "state": "open", "files": [],
                                                 "owner": "sam", "input_id": "att3"}],
                                   "candidates": [], "verifications": [], "integrations": []})
        for answer in (HOLD_ANSWER, DANIEL):   # the old prompt's answer is read as a hold
            self.reply = (answer, False)
            got = work.load_item(item["id"])
            got.pop("repair_checkpoint", None)
            work.save_item(got)
            self.assertTrue(work.review_next_exhausted_repair(ORG))
            got = self.assert_held_for_chief_of_staff(item["id"], 2, "The same finding came back three times")
            self.assertEqual(got["repair_checkpoint"]["suggestion"], "Drop the second tier and ship one upgrade.")
            self.assertEqual(got["recommend"], {"question": "Q", "answer": "A", "why": "W", "instead": "I"})
            self.assertNotIn("supervised_retry", got)
        # Nothing reviews it again while it waits on the chief of staff.
        self.calls.clear()
        self.assertFalse(work.review_next_exhausted_repair(ORG))
        self.assertEqual(self.calls, [])

    def test_the_chief_of_staff_retry_records_claude_and_requeues_one_try(self):
        self.reply = (HOLD_ANSWER, False)
        item = self.card()
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        self.assert_held_for_chief_of_staff(item["id"], 2, "same finding")
        brief = "Drop the second tier; keep one upgrade and its price test."
        saved = work.retry_repairs_used_up(item["id"], by=COS, reason=brief)
        self.assertEqual(saved["state"], "for_review")
        self.assertNotIn("repair_checkpoint", saved)
        self.assertEqual(saved["repair_hold"], HOLD)
        self.assertIs(saved["supervised_retry"], True)
        self.assertEqual(saved["repair_brief"], "The chief of staff approved one more supervised try; "
                                                "do this before anything else:\n" + brief)
        review = saved["repair_reviews"][-1]
        self.assertEqual((review["by"], review["decision"], review["reason"], review["via"]),
                         ("claude", "retry", brief, COS))
        self.assertNotIn("decided", saved)
        self.assertNotIn("Daniel", saved["repair_brief"])
        # Back in the runner lane, as the one supervised try the drain runs.
        view = self.view(saved)
        self.assertEqual(work.card_lanes(saved, view), ["runner"])
        self.assertEqual(self.step(saved), ("reconcile", "runnable"))
        self.assertEqual([i["id"] for i, _a in action_dispatch.choose(drain)], [item["id"]])
        self.assertIn("REPAIR YOUR OWN RESULT: " + saved["repair_brief"], work.revision_brief(saved))
        # A second grant is refused: the try is already waiting to run.
        with self.assertRaisesRegex(ValueError, "already has a supervised try waiting"):
            work.retry_repairs_used_up(item["id"], by=COS, reason=brief)

    def test_extend_on_a_card_whose_repairs_are_used_up_gives_one_more_try(self):
        # One "keep going" command for the chief of staff: `extend` settles
        # whichever checkpoint holds the card.
        self.reply = (HOLD_ANSWER, False)
        item = self.card()
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        granted, saved = work.keep_going(item["id"], by=COS, reason="Fix the price test and nothing else.")
        self.assertEqual(granted, "repair")
        self.assertIs(saved["supervised_retry"], True)
        self.assertEqual((saved["repair_reviews"][-1]["by"], saved["repair_reviews"][-1]["decision"]),
                         ("claude", "retry"))
        self.assertNotIn("cap_reviews", saved)

    def test_retry_refuses_what_it_cannot_honestly_do(self):
        self.reply = (HOLD_ANSWER, False)
        item = self.card()
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        cases = [
            (dict(by="Daniel", reason="Fix the price test first."), "may not claim Daniel"),
            (dict(by="CEO session", reason="Fix the price test first."), "may not claim Daniel"),
            (dict(by="the checker", reason="Fix the price test first."), "may not claim Daniel"),
            (dict(by="x", reason="Fix the price test first."), "Say who"),
            (dict(by=COS, reason=""), "Give the brief"),
        ]
        for kwargs, said in cases:
            with self.assertRaisesRegex(ValueError, re.escape(said)):
                work.retry_repairs_used_up(item["id"], **kwargs)
        self.assertTrue(work.repair_held(work.load_item(item["id"])), "a refusal changes nothing")
        closed = self.card("wdef000000021", state="landed")
        with self.assertRaisesRegex(ValueError, "already landed"):
            work.retry_repairs_used_up(closed["id"], by=COS, reason="Fix the price test first.")
        fine = self.card("wdef000000022", repair_hold="", automatic_repairs=0)
        with self.assertRaisesRegex(ValueError, "not at a repair checkpoint: it has not used up its repairs"):
            work.retry_repairs_used_up(fine["id"], by=COS, reason="Fix the price test first.")

    # -- The cards an earlier HQ sent to Daniel (S-38 migration) -------------

    def legacy_card(self, item_id="wdef000000009"):
        """A card in the shape the old path left: a repairs-used-up question on
        his page, with the repair hold set aside and the question's fields borrowed."""
        return self.card(item_id, state="needs_approval", repair_hold="",
                         attempt_outcome={"id": "att3", "status": "complete",
                                          "candidate": {"tree": "t1", "base": "b1",
                                                        "files": ["systems/shop_defs.gd"]}},
                         recommend={"question": "The reviewer has failed it again. Give its owner one more attempt?",
                                    "answer": "Drop the second tier and ship one upgrade.",
                                    "why": "W2", "instead": "I2"},
                         deliverable={"name": "Repairs used up: Build separate pace purchases", "evidence": []},
                         follow_ups=[],
                         repair_checkpoint={"at": "2026-09-29T08:00", "return_state": "for_review",
                                            "attempt_id": "att3", "repair_hold": HOLD,
                                            "restore": {"recommend": {"question": "Q", "answer": "A",
                                                                      "why": "W", "instead": "I"}},
                                            "yes_starts": "Gives the owner one more attempt..."},
                         repair_reviews=[{"by": "claude", "decision": "daniel", "attempt_id": "att3",
                                          "reason": "The same finding came back."}])

    def test_the_migration_holds_cards_left_on_daniels_page_and_is_idempotent(self):
        card = self.legacy_card()
        before = self.view(card)
        self.assertEqual(work.card_lanes(work.load_item(card["id"]), before), [],
                         "the broken shape: in no lane")
        self.assertEqual(work.hold_repair_checkpoints_for_chief_of_staff(), [card["id"]])
        got = self.assert_held_for_chief_of_staff(card["id"], 2, "sent to Daniel before")
        self.assertEqual(got["state"], "for_review")
        self.assertEqual(got["recommend"], {"question": "Q", "answer": "A", "why": "W", "instead": "I"},
                         "the borrowed fields are put back")
        self.assertNotIn("deliverable", got)
        self.assertNotIn("follow_ups", got)
        self.assertEqual(got["repair_checkpoint"]["moved_from"], "needs_approval")
        self.assertEqual(got["repair_checkpoint"]["asked_at"], "2026-09-29T08:00")
        revision = got["_revision"]
        self.assertEqual(work.hold_repair_checkpoints_for_chief_of_staff(), [])
        self.assertEqual(work.load_item(card["id"])["_revision"], revision, "a second run changes nothing")
        # The spending migration leaves it alone, and it leaves spending cards alone.
        self.assertEqual(work.hold_checkpoints_for_chief_of_staff(), [])

    def test_retry_on_a_card_still_in_the_old_shape_moves_it_first(self):
        card = self.legacy_card()
        saved = work.retry_repairs_used_up(card["id"], by=COS, reason="Ship one upgrade with its price test.")
        self.assertEqual((saved["state"], saved["repair_hold"]), ("for_review", HOLD))
        self.assertIs(saved["supervised_retry"], True)
        self.assertEqual(saved["recommend"], {"question": "Q", "answer": "A", "why": "W", "instead": "I"})
        self.assertNotIn("deliverable", saved)
        self.assertEqual([(r["by"], r["decision"]) for r in saved["repair_reviews"]],
                         [("claude", "daniel"), ("claude", "hold"), ("claude", "retry")])

    def test_daniels_own_yes_on_an_old_question_is_still_recorded_as_his(self):
        # Before the migration runs, his page may still show an old question;
        # his yes there is his, and the record says so.
        card = self.legacy_card()
        got = work.load_item(card["id"])
        saved = work.api_post("/api/work/approve", {"id": card["id"], "_revision": got["_revision"],
                                                     "comment": "Keep the shop layout as it is."})
        self.assertEqual(saved["state"], "for_review")
        self.assertNotIn("repair_checkpoint", saved)
        self.assertEqual(saved["repair_hold"], HOLD)
        self.assertIs(saved["supervised_retry"], True)
        self.assertEqual(saved["recommend"], {"question": "Q", "answer": "A", "why": "W", "instead": "I"})
        self.assertIn("Daniel approved this after the repairs were used up; do it before anything else:\n"
                      "Drop the second tier and ship one upgrade.", saved["repair_brief"])
        self.assertIn("Keep the shop layout as it is.", saved["repair_brief"])
        self.assertEqual(saved["decided"]["answer"], "Drop the second tier and ship one upgrade.")
        review = saved["repair_reviews"][-1]
        self.assertEqual((review["by"], review["decision"]), ("daniel", "retry"))
        self.assertTrue(review["reason"].startswith("Daniel approved: "))
        self.assertNotIn("via", review)
        self.assertEqual(self.step(saved), ("reconcile", "runnable"))
        self.assertEqual([i["id"] for i, _a in action_dispatch.choose(drain)], [card["id"]])

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

        # A ruling's work or tier-2 work is held for the chief of staff, who
        # decides whether closing it is worth a decision card for Daniel.
        for item_id, over, why in (("wdef000000002", {"ruling_id": "Q-130"}, "one of Daniel's rulings"),
                                   ("wdef000000003", {"tier": 2}, "needs Daniel's approval")):
            card = self.card(item_id, **over)
            self.assertTrue(work.review_exhausted_repair(work.load_item(card["id"]), ORG))
            got = self.assert_held_for_chief_of_staff(card["id"], 2, "abc123")
            self.assertIn(why, got["repair_checkpoint"]["reason"])
            self.assertIn("decision card", got["repair_checkpoint"]["suggestion"])
            self.assertNotEqual(got["state"], "dropped")

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

    def test_a_failing_review_retries_then_is_held_for_the_chief_of_staff(self):
        item = self.card()
        self.reply = ("not json", False)
        for tries in (1, 2):
            self.assertFalse(work.review_next_exhausted_repair(ORG))
            got = work.load_item(item["id"])
            self.assertEqual((got["state"], got["repair_review_tries"]), ("for_review", tries))
        self.assertTrue(work.review_next_exhausted_repair(ORG))
        self.assertEqual(len(self.calls), 3)
        got = self.assert_held_for_chief_of_staff(item["id"], 2, "no usable answer after 3 tries")
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

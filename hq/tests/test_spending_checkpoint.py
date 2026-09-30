#!/usr/bin/env python3
"""The chief of staff reviews a card stopped at its per-card spending cap.

Daniel's policy (2026-09-28): the cap is a checkpoint, not a wall. Spending that
buys progress runs on one bounded step. His ruling of 2026-09-29 (S-38): a card
the automatic review does not extend is the chief of staff's to extend, rescope
or close. It waits in the queue's held lane with its reason and never reaches his
page. No model runs here: the review call is stubbed.
"""
import json
import os
import re
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


HOLD_TAIL = "Waiting for the chief of staff to extend, rescope or close it."


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

    RECOMMEND = {"question": "Q", "answer": "A", "why": "W", "instead": "I"}

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

    def lanes(self, item):
        got = work.load_item(item["id"])
        return work.card_lanes(got, drain.project_work(got, head="", active={}))

    def waiting(self):
        with patch.object(server, "api_queue", lambda **kw: {"curated": [], "decided": [], "rulings": {}}):
            return server.waiting_on_you()

    def assert_held_for_chief_of_staff(self, item_id, reason_has):
        """Held in the queue with a plain reason, owned by the chief of staff:
        one lane (held), a healthy lane check, and nothing on Daniel's page."""
        got = work.load_item(item_id)
        self.assertIn(got["state"], work.CAP_REVIEW_STATES)
        self.assertTrue(work.cap_held(got))
        view = drain.project_work(got, head="", active={})
        self.assertEqual(view["blocker"]["type"], "spending_hold")
        self.assertEqual(view["blocker"]["owner"], "claude")
        self.assertTrue(view["blocker"]["reason"].startswith("Over its token budget"), view["blocker"]["reason"])
        self.assertTrue(view["blocker"]["reason"].endswith(HOLD_TAIL), view["blocker"]["reason"])
        self.assertIn(reason_has, view["blocker"]["reason"])
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
        # The drain's queue lists it as held with the same reason, and neither
        # the drain nor the automatic review picks it up again.
        with patch.object(drain.server, "drain_entry", lambda active, item_id: False):
            queue = drain.queue_view()
        held = {row["work_id"]: row["reason"] for row in queue["held"]}
        self.assertEqual(held.get(item_id), view["blocker"]["reason"])
        self.assertNotIn(item_id, [row["work_id"] for row in queue["eligible"]])
        self.assertNotIn(item_id, [i["id"] for i in work.spending_checkpoints_due()])
        self.assertEqual(got["cap_reviews"][-1]["by"], "claude")
        self.assertEqual(got["cap_reviews"][-1]["decision"], "hold")
        return got

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

    def test_the_review_is_told_what_the_studio_fixed(self):
        # 2026-09-28: the first live review read read-only failures as not
        # converging, not knowing the card had just been given a writable copy.
        item = self.card(tier_raised={"at": "2026-09-26T23:43", "from": 0},
                         tier_reason="A read-only attempt showed this needs a writable copy")
        self.spend(item["id"], 1_200_000, 100_000)
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        prompt = self.calls[0][0][0]
        self.assertIn("WHAT THE STUDIO CHANGED ABOUT THIS CARD", prompt)
        self.assertIn("writable copy", prompt)
        self.assertIn("is not the owner failing to converge", prompt)

    def test_fresh_cap_is_raised_alone(self):
        item = self.card()
        self.spend(item["id"], 500_000, 200_000)
        self.assertTrue(work.review_spending_checkpoint(work.load_item(item["id"]), ORG))
        got = work.load_item(item["id"])
        self.assertEqual(got["fresh_token_cap"], 350_000)
        self.assertNotIn("token_cap", got)

    def test_not_converging_is_held_for_the_chief_of_staff_not_daniel(self):
        # S-38 (2026-09-29): this used to put a "keep spending?" question on his page.
        item = self.card()
        self.spend(item["id"], 4_900_000, 120_000)
        work.save_item(dict(work.load_item(item["id"]), token_cap=4_000_000))
        self.reply = (DANIEL, False)
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        got = self.assert_held_for_chief_of_staff(item["id"], "The same failure repeated three times.")
        self.assertEqual(got["state"], "waiting_session")
        self.assertEqual(got["token_cap"], 4_000_000)
        self.assertEqual(got["recommend"], self.RECOMMEND, "the card's own recommendation is untouched")
        self.assertEqual(got["spending_checkpoint"]["suggestion"], "Rework the approach first.")
        # Nothing reviews it again while it waits on the chief of staff.
        self.calls.clear()
        self.assertFalse(work.review_next_spending_checkpoint(ORG))
        self.assertEqual(self.calls, [])

    def test_a_hold_answer_is_held_too(self):
        item = self.card()
        self.spend(item["id"], 1_200_000, 100_000)
        self.reply = ('{"outcome":"hold","reason":"Each check fails on the missing display.",'
                      '"suggest":"Close it; the capture needs a display."}', False)
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        got = self.assert_held_for_chief_of_staff(item["id"], "Each check fails on the missing display")
        self.assertEqual(got["spending_checkpoint"]["suggestion"], "Close it; the capture needs a display.")

    def test_a_card_held_for_repair_keeps_its_repair_hold_while_held(self):
        # w3b629423e60, 2026-09-28: the old path took the repair hold off the
        # card and sent it to Daniel. Held for the chief of staff, the card
        # keeps the hold; the spending hold is what the queue shows.
        hold = "This worker cannot reach itch.io, so the comparison cannot be recorded."
        item = self.card(state="for_review", repair_hold=hold, automatic_repairs=1)
        self.spend(item["id"], 4_900_000, 120_000)
        work.save_item(dict(work.load_item(item["id"]), token_cap=4_000_000))
        self.reply = (DANIEL, False)
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        got = self.assert_held_for_chief_of_staff(item["id"], "not converging")
        self.assertEqual((got["state"], got["repair_hold"]), ("for_review", hold))
        self.assertEqual(work.exhausted_repairs_due(), [], "the spending hold is settled first")
        # The chief of staff's extension gives the spending back; the repair
        # hold then goes to its own review, not straight to another try.
        saved = work.extend_over_budget(item["id"], by="Claude chief-of-staff session",
                                        reason="Give it one step to record why itch.io is unreachable.")
        self.assertEqual((saved["state"], saved["repair_hold"]), ("for_review", hold))
        self.assertNotIn("supervised_retry", saved)
        self.assertNotIn("spending_checkpoint", saved)

    def test_a_checkpoint_on_code_that_has_not_landed_stays_with_the_studio(self):
        # wbecb4f98af1, 2026-09-29: the navbar badge counted a checkpoint card
        # whose change had not landed, while the Decisions page (correctly) did
        # not list it. Both now read work_ready_for_daniel the same way.
        hold = "The rendered capture test needs a display this worker does not have."
        outcome = {"version": 1, "status": "blocked", "reason": hold, "id": "attempt-1",
                   "candidate": {"tree": "t1", "base": "b1", "files": ["systems/shelf_defs.gd"]}}
        item = self.card(state="for_review", repair_hold=hold, automatic_repairs=1,
                         attempt_outcome=outcome)
        self.spend(item["id"], 4_900_000, 120_000)
        work.save_item(dict(work.load_item(item["id"]), token_cap=4_000_000))
        self.reply = (DANIEL, False)
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        # 2026-09-29: six cards sat in exactly this shape in no lane. Held for
        # the chief of staff, the lane check counts it held with its reason.
        got = self.assert_held_for_chief_of_staff(item["id"], "not converging")
        view = drain.project_work(got, head="", active={})
        self.assertEqual(view.get("candidate_status"), "held")
        waiting = self.waiting()
        self.assertNotIn(item["id"], {row["source_id"] for row in waiting["ready"]})
        self.assertEqual(waiting["count"], 0)
        row = next(r for r in waiting["items"] if r["source_id"] == item["id"])
        self.assertEqual((row["status"], row["reason"]), (
            "verification_pending", "The code result still needs verification and a commit on main."))

    def test_hard_limits_skip_the_model(self):
        three = [{"decision": "extend", "by": "claude"}] * 3
        item = self.card(cap_reviews=three, token_cap=4_000_000)
        self.spend(item["id"], 4_100_000, 100_000)
        self.assertTrue(work.review_spending_checkpoint(work.load_item(item["id"]), ORG))
        self.assertEqual(self.calls, [])
        got = self.assert_held_for_chief_of_staff(item["id"], "after 3 extensions")
        self.assertEqual(got["spending_checkpoint"]["reason"],
                         "Over its token budget; after 3 extensions. " + HOLD_TAIL)
        self.assertEqual(got["token_cap"], 4_000_000)

        high = self.card("wcab000000002", token_cap=9_500_000)
        self.spend(high["id"], 9_600_000, 100_000)
        self.assertTrue(work.review_spending_checkpoint(work.load_item(high["id"]), ORG))
        self.assertEqual(self.calls, [])
        high = self.assert_held_for_chief_of_staff(high["id"], "most the studio lets a card spend")
        self.assertEqual(high["token_cap"], 9_500_000)

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

    def test_a_dry_allowance_never_uses_up_a_try(self):
        # Nothing was judged, so an empty window must not push the card toward Daniel.
        item = self.card()
        self.spend(item["id"], 1_200_000, 100_000)
        self.reply = ("", True)
        for _ in range(5):
            self.assertFalse(work.review_next_spending_checkpoint(ORG))
        got = work.load_item(item["id"])
        self.assertEqual((got["state"], got.get("cap_review_tries", 0)), ("waiting_session", 0))
        self.assertEqual(len(self.calls), 5)

    def test_a_failing_review_retries_then_is_held_for_the_chief_of_staff(self):
        item = self.card()
        self.spend(item["id"], 1_200_000, 100_000)
        self.reply = ("not json", False)
        for tries in (1, 2):
            self.assertFalse(work.review_next_spending_checkpoint(ORG))
            got = work.load_item(item["id"])
            self.assertEqual((got["state"], got["cap_review_tries"]), ("waiting_session", tries))
        self.assertTrue(work.review_next_spending_checkpoint(ORG))
        self.assertEqual(len(self.calls), 3)
        got = self.assert_held_for_chief_of_staff(item["id"], "no usable answer after 3 tries")
        self.assertNotIn("cap_review_tries", got)

    # -- The cards an earlier HQ sent to Daniel (S-38 migration) -------------

    def legacy_card(self, item_id="wcab000000009"):
        """A card in the shape the old path left: a spending question on his page."""
        hold = "The rendered capture test needs a display this worker does not have."
        card = self.card(item_id, state="needs_approval", attempt_outcome={
            "version": 1, "status": "blocked", "reason": hold, "id": "attempt-1",
            "candidate": {"tree": "t1", "base": "b1", "files": ["systems/shelf_defs.gd"]}},
            token_cap=4_000_000, automatic_repairs=1,
            recommend={"question": "This card has spent 4.9 million tokens. Keep going?",
                       "answer": "Rework the approach first.", "why": "W2", "instead": "I2"},
            deliverable={"name": "Spending checkpoint: Record the worm ruling", "evidence": []},
            follow_ups=[],
            spending_checkpoint={"at": "2026-09-29T08:00", "return_state": "for_review",
                                 "move": "rethink", "exceeded": ["tokens"],
                                 "restore": {"recommend": self.RECOMMEND}, "repair_hold": hold,
                                 "yes_starts": "Raises this card's spending limit..."},
            cap_reviews=[{"by": "claude", "decision": "daniel", "reason": "Not converging."}])
        self.spend(card["id"], 4_900_000, 120_000)
        return card, hold

    def test_the_migration_holds_cards_left_on_daniels_page_and_is_idempotent(self):
        card, hold = self.legacy_card()
        before = drain.project_work(work.load_item(card["id"]), head="", active={})
        self.assertEqual(work.card_lanes(work.load_item(card["id"]), before), [],
                         "the broken shape: in no lane")
        self.assertEqual(work.hold_checkpoints_for_chief_of_staff(), [card["id"]])
        got = self.assert_held_for_chief_of_staff(card["id"], "sent to Daniel before")
        self.assertEqual((got["state"], got["repair_hold"]), ("for_review", hold))
        self.assertEqual(got["recommend"], self.RECOMMEND, "the borrowed fields are put back")
        self.assertNotIn("deliverable", got)
        self.assertNotIn("follow_ups", got)
        self.assertEqual(got["spending_checkpoint"]["moved_from"], "needs_approval")
        revision = got["_revision"]
        self.assertEqual(work.hold_checkpoints_for_chief_of_staff(), [])
        self.assertEqual(work.load_item(card["id"])["_revision"], revision, "a second run changes nothing")

    def test_extend_on_a_card_still_in_the_old_shape_moves_it_first(self):
        card, _hold = self.legacy_card()
        saved = work.extend_over_budget(card["id"], by="Claude chief-of-staff session",
                                        reason="Split the capture test out; land the rest.")
        self.assertEqual(saved["state"], "for_review")
        self.assertEqual(saved["token_cap"], 5_900_000)
        self.assertEqual(saved["recommend"], self.RECOMMEND)
        self.assertEqual((saved["cap_reviews"][-1]["by"], saved["cap_reviews"][-1]["decision"]),
                         ("claude", "extend"))

    # -- The chief of staff's extension (hq/card.py extend) -----------------

    def test_extend_through_the_work_api_puts_the_card_back_in_the_runner_lane(self):
        three = [{"decision": "extend", "by": "claude"}] * 3
        item = self.card(cap_reviews=three, token_cap=4_000_000)
        self.spend(item["id"], 4_100_000, 100_000)
        self.assertTrue(work.review_spending_checkpoint(work.load_item(item["id"]), ORG))
        self.assert_held_for_chief_of_staff(item["id"], "after 3 extensions")
        brief = "Drop the second capture and land the doc change alone."
        saved = work.extend_over_budget(item["id"], by="Claude chief-of-staff session", reason=brief)
        self.assertEqual(saved["state"], "waiting_session")
        self.assertEqual(saved["token_cap"], 5_100_000)
        self.assertNotIn("spending_checkpoint", saved)
        review = saved["cap_reviews"][-1]
        self.assertEqual((review["by"], review["decision"], review["reason"]), ("claude", "extend", brief))
        self.assertEqual(review["via"], "Claude chief-of-staff session")
        self.assertEqual((review["old_caps"]["token_cap"], review["new_caps"]["token_cap"]),
                         (4_000_000, 5_100_000))
        self.assertTrue(saved["ask"].endswith("The chief of staff's brief for this step: " + brief))
        self.assertNotIn("Daniel", saved["ask"])
        self.assertNotIn("decided", saved)
        self.assertEqual(self.lanes(saved), ["runner"])
        self.assertEqual(self.next_step(saved), "build")

    def test_extend_refuses_what_it_cannot_honestly_do(self):
        item = self.card()
        self.spend(item["id"], 200_000, 10_000)
        cases = [
            (dict(by="Daniel", reason="Keep going on this card."), "may not claim Daniel"),
            (dict(by="CEO session", reason="Keep going on this card."), "may not claim Daniel"),
            (dict(by="x", reason="Keep going on this card."), "Say who"),
            (dict(by="Claude chief-of-staff session", reason=""), "Give the brief"),
            (dict(by="Claude chief-of-staff session", reason="Keep going on this card."),
             "not over its spending limit"),
        ]
        for kwargs, said in cases:
            with self.assertRaisesRegex(ValueError, re.escape(said)):
                work.extend_over_budget(item["id"], **kwargs)
        closed = self.card("wcab000000004", state="landed")
        with self.assertRaisesRegex(ValueError, "already landed"):
            work.extend_over_budget(closed["id"], by="Claude chief-of-staff session",
                                    reason="Keep going on this card.")
        self.assertEqual(work.load_item(item["id"]).get("cap_reviews"), None)

    def test_daniels_own_yes_on_an_old_checkpoint_is_still_recorded_as_his(self):
        # Before the migration runs, his page may still show an old question;
        # his yes there is his, and the record says so.
        card, hold = self.legacy_card()
        got = work.load_item(card["id"])
        saved = work.api_post("/api/work/approve", {"id": card["id"], "_revision": got["_revision"],
                                                    "comment": "Only the doc change."})
        self.assertEqual(saved["state"], "for_review")
        self.assertEqual(saved["token_cap"], 5_900_000)
        self.assertEqual(saved["recommend"], self.RECOMMEND)
        self.assertEqual(saved["repair_hold"], hold)
        self.assertTrue(saved["supervised_retry"])
        review = saved["cap_reviews"][-1]
        self.assertEqual((review["by"], review["decision"]), ("daniel", "extend"))
        self.assertTrue(review["reason"].startswith("Daniel approved: "))
        self.assertIn("Rework the approach first.", saved["ask"])
        self.assertIn("Daniel attached this when he approved it:\nOnly the doc change.", saved["ask"])
        self.assertNotIn("chief of staff's brief", saved["ask"])


if __name__ == "__main__":
    unittest.main()

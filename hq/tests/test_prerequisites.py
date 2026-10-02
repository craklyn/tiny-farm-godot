#!/usr/bin/env python3
"""A card that needs another card's work first waits for it, and starts once it
lands; a follow-up that only carries out a decision is worked, not parked.

Both are the pea feature's stall of 2026-10-01. Four cards whose first step said
"check the decision card is closed on main" were started at 12:32 while that
card was still open; each came back "Blocked: not closed on origin/main" and sat
in Daniel's list as a dead result until the decision landed at 14:08. When it
did, the two follow-ups it promised (put the pea on the shelf, draw its packet)
were filed at tier 2, parked as questions for Daniel nobody could write, and
never ran. Here the decision card is "the pea decision", the shelf card waits
on it in `after`, and the landing's follow-ups are the same two.

    python3 hq/tests/test_prerequisites.py
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain  # noqa: E402
import server  # noqa: E402
import work  # noqa: E402
from test_drain import fake_host  # noqa: E402

ORG = {"employees": [
    {"id": "daniel", "name": "Daniel", "title": "CEO", "level": "L10", "team": "HQ",
     "responsibilities": ["everything"], "persona": ""},
    {"id": "claude", "name": "Adam", "title": "Chief of staff", "level": "L8", "team": "HQ",
     "responsibilities": ["routing"], "persona": ""},
    {"id": "milo", "name": "Milo", "title": "Game designer", "level": "L6", "team": "Design",
     "responsibilities": ["economy"], "persona": ""},
    {"id": "anna", "name": "Anna", "title": "Gameplay engineer", "level": "L5", "team": "Engineering",
     "responsibilities": ["crops"], "persona": ""},
    {"id": "yuki", "name": "Yuki", "title": "Artist", "level": "L5", "team": "Art",
     "responsibilities": ["icons"], "persona": ""},
]}

DECISION = "w132c09f8d600"
SHELF = "w72862019a790"


class Prerequisites(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        self.repo.mkdir()
        for args in (("init", "-q", "-b", "main"), ("config", "user.name", "Fixture"),
                     ("config", "user.email", "fixture@example.invalid")):
            subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)
        (self.repo / "sample.txt").write_text("base\n")
        subprocess.run(["git", "add", "sample.txt"], cwd=self.repo, check=True)
        subprocess.run(["git", "commit", "-qm", "base"], cwd=self.repo, check=True)
        host = fake_host(str(root / "data"))
        host.load_json = lambda path: json.loads(Path(path).read_text())
        host.load_org = lambda: ORG
        host.token_window = lambda: {"tokens": 0, "calls": 0}
        host.drain_state = lambda: None
        work.bind(host, sanitize=False)
        (root / "patches").mkdir()
        self.patches = [patch.object(drain, "PATCHES", str(root / "patches")),
                        patch.object(drain, "WORKERS", str(root / "workers")),
                        patch.object(drain, "REPO", str(self.repo)),
                        patch.object(server, "drain_state", return_value=None)]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def card(self, ident, title, owner, **fields):
        item = {"id": ident, "title": title, "owner": owner, "level": "task", "tier": 1,
                "state": "waiting_session", "ask": title, "first_action": title,
                "created": "2026-10-01T12:25:41-07:00", "created_ts": 1, "attempts": 0,
                "started": ""}
        item.update(fields)
        return work.save_item(item)

    def queued_ids(self):
        return [item["id"] for item in drain.queued()]

    def land(self, ident):
        item = work.load_item(ident)
        item["state"] = "landed"
        item["landed"] = {"at": "2026-10-01T14:08:47-07:00", "by": "drain", "sha": "d453eac"}
        work.save_item(item)

    def test_a_card_waits_for_its_prerequisite_and_starts_once_it_lands(self):
        self.card(DECISION, "Peas: decide when pea seeds go on the shelf and what they cost", "milo",
                  created_ts=0)
        self.card(SHELF, "Peas: put pea seeds on the shop shelf", "anna", after=[DECISION])

        # The decision is worked; the shelf is not started early.
        self.assertEqual(self.queued_ids(), [DECISION])
        view = drain.project_work(work.load_item(SHELF))
        self.assertEqual(view["blocker"]["type"], "prerequisite")
        self.assertEqual(view["blocker"]["owner"], "anna")
        self.assertIn("Peas: decide when pea seeds go on the shelf", view["blocker"]["reason"])
        self.assertEqual(view["next_action"]["availability"], "blocked")
        held = drain.queue_view()["held"]
        self.assertEqual([row["id"] for row in held], [SHELF])
        self.assertIn("starts on its own", held[0]["reason"])
        # It waits with the studio: nothing about the wait is Daniel's move.
        self.assertNotIn("daniel", work.card_lanes(work.load_item(SHELF), view))

        # The decision lands, and the shelf is next with nobody touching it.
        self.land(DECISION)
        self.assertEqual(self.queued_ids(), [SHELF])
        self.assertIsNone(drain.project_work(work.load_item(SHELF))["blocker"])

    def test_every_prerequisite_must_land(self):
        self.card(DECISION, "the pea decision", "milo", state="landed")
        self.card("w99a67c978c30", "the pea packet art", "yuki")
        self.card(SHELF, "the pea shelf", "anna", after=[DECISION, "w99a67c978c30"])
        reason = drain.project_work(work.load_item(SHELF))["blocker"]["reason"]
        self.assertIn("the pea packet art", reason)
        self.assertNotIn("the pea decision", reason)
        self.assertNotIn(SHELF, self.queued_ids())

    def test_a_dropped_prerequisite_goes_to_the_chief_of_staff(self):
        self.card(DECISION, "the pea decision", "milo", state="dropped")
        self.card(SHELF, "the pea shelf", "anna", after=[DECISION])
        view = drain.project_work(work.load_item(SHELF))
        self.assertEqual(view["blocker"]["type"], "prerequisite_dropped")
        self.assertEqual(view["next_action"]["type"], "chief_hold")
        self.assertEqual(view["next_action"]["owner"], "claude")
        self.assertNotIn(SHELF, self.queued_ids())

    def test_the_chief_of_staffs_own_waiting_card_is_not_a_chief_hold(self):
        self.card(DECISION, "the pea decision", "milo")
        self.card(SHELF, "the pea shelf", "claude", after=[DECISION])
        view = drain.project_work(work.load_item(SHELF))
        self.assertEqual(view["blocker"]["type"], "prerequisite")
        self.assertEqual(view["next_action"]["type"], "build")

    def test_a_card_already_running_or_back_with_a_result_is_not_held(self):
        self.card(DECISION, "the pea decision", "milo")
        self.card(SHELF, "the pea shelf", "anna", after=[DECISION], state="for_review",
                  result="done")
        self.assertIsNone(drain.project_work(work.load_item(SHELF))["blocker"])

    def test_unstarted_reading_work_waits_too(self):
        self.card(DECISION, "the pea decision", "milo")
        reading = self.card(SHELF, "Read how the pea sells", "anna", tier=0, state="doing",
                            after=[DECISION])
        view = drain.project_work(reading)
        self.assertEqual(view["blocker"]["type"], "prerequisite")
        self.assertNotIn("runner", work.card_lanes(reading, view))
        self.assertEqual(work.prerequisites(reading)[0][0]["id"], DECISION)
        self.land(DECISION)
        self.assertEqual(work.prerequisites(work.load_item(SHELF)), ([], []))

    def test_filing_by_hand_names_its_prerequisite(self):
        self.card(DECISION, "the pea decision", "milo")
        got = work.api_post("/api/work/new", {"title": "Peas: put pea seeds on the shop shelf",
                                              "owner": "anna", "tier": 1, "after": DECISION})
        self.assertEqual(got["after"], [DECISION])
        self.assertEqual(drain.project_work(got)["blocker"]["type"], "prerequisite")
        refused = work.api_post("/api/work/new", {"title": "x", "owner": "anna", "tier": 1,
                                                  "after": ["w000000000bad"]})
        self.assertIn("not a work card", refused["error"])

    def test_the_landed_decisions_follow_ups_are_worked_in_order(self):
        """The two cards w132c09f8d60's landing filed at tier 2 on 2026-10-01."""
        decision = self.card(DECISION, "Peas: decide when pea seeds go on the shelf and what they cost",
                             "milo", state="landed")
        tail = json.dumps({"items": [
            {"title": "Draw a pea seed packet for the shop", "owner": "yuki", "level": "task",
             "tier": 2, "first_action": "Add a pea seed-packet icon to shop_icons.png.",
             "why": "The current pea icon cell shows a coin."},
            {"title": "Put pea seed packets on the shop shelf", "owner": "anna", "level": "task",
             "tier": 2, "after": ["Draw a pea seed packet for the shop"],
             "first_action": "Add pea after tomato in CropDefs.ORDER and use Yuki's icon cell.",
             "why": "This applies the documented unlock, price, and shelf order in the game."},
        ]})
        follows, _amend, _rec, _move = work._parse_follows(tail, ORG, "milo")
        self.assertEqual([fu["tier"] for fu in follows], [1, 1])
        started = work._file_follow_ups(decision, follows, ORG, "follow", "Landed without Daniel.")
        art, shelf = (work.load_item(entry["id"]) for entry in started)
        self.assertEqual((art["state"], shelf["state"]), ("waiting_session", "waiting_session"))
        self.assertEqual(shelf["after"], [art["id"]])
        self.assertEqual(self.queued_ids(), [art["id"]])
        self.land(art["id"])
        self.assertEqual(self.queued_ids(), [shelf["id"]])

    def test_a_named_ask_first_reason_still_parks_the_follow_up(self):
        decision = self.card(DECISION, "the pea decision", "milo", state="landed")
        started = work._file_follow_ups(decision, [
            {"title": "Put the pea build on the tablet", "owner": "anna", "tier": 2,
             "ask_first": "deploy", "why": "a deploy"}], ORG, "follow", "Landed.")
        self.assertEqual(work.load_item(started[0]["id"])["state"], "prepping")


if __name__ == "__main__":
    unittest.main()

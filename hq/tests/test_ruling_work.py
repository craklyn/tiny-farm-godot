#!/usr/bin/env python3
"""A ruling files its own work the moment Daniel records it (Q-125 a).

Before this, a ruling sat as "pending integration" until a session happened to
look in the rulings folder. Now recording it files an "Act on your ruling"
card owned by the decision's owner, rulings that were already waiting when HQ
starts get theirs too, and the queue page lists each ruling until it is
integrated — read from the ruling's own status, not from whether a card exists.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server  # noqa: E402


class RulingWork(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="hq-ruling-work-")
        self.saved = (server.DATA, server.work.WORK, server.work.HOST)
        server.DATA = self.tmp
        server.work.WORK = os.path.join(self.tmp, "work")
        server.work.HOST = server
        for folder in ("work", "rulings", "decisions"):
            os.makedirs(os.path.join(self.tmp, folder))
        Path(self.tmp, "org.json").write_text(json.dumps({"employees": [
            {"id": "claude", "name": "Adam"}, {"id": "rin", "name": "Rin"}]}))
        self.decision("Q-950", owner="rin", subject="The planting sound")
        self.decision("Q-951", owner="nobody-here", title="Should the fence be lighter?")

    def tearDown(self):
        server.DATA, server.work.WORK, server.work.HOST = self.saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def decision(self, qid, **fields):
        doc = {"id": qid, "title": fields.get("title", "A question?"), "question": "?",
               "options": [{"key": "a", "label": "The first way (Recommended)"},
                           {"key": "b", "label": "The second way"}], **fields}
        Path(self.tmp, "decisions", f"{qid}.json").write_text(json.dumps(doc))

    def ruling(self, qid):
        return json.loads(Path(self.tmp, "rulings", f"{qid}.json").read_text())

    def cards(self, qid):
        return [i for i in server.work.items() if i.get("ruling_id") == qid]

    def test_recording_a_choice_files_the_work_it_unblocks(self):
        out = server.record_ruling({"id": "Q-950", "intent": "choose", "option": "a",
                                    "submission_id": "sub-q950-000000001",
                                    "judgment": "Quieter than the watering can."})
        [card] = self.cards("Q-950")
        self.assertEqual(out["integration_work_id"], card["id"])
        self.assertEqual(self.ruling("Q-950")["integration_work_id"], card["id"])
        self.assertEqual(card["title"], "Act on your ruling: The planting sound — you chose The first way")
        self.assertEqual(card["owner"], "rin")
        self.assertEqual(card["state"], "waiting_session")
        self.assertEqual(card["tier"], 1)
        self.assertIn("“Quieter than the watering can.”", card["ask"])
        self.assertNotIn("decision_id", card)   # reserved for revisions, which return to him
        again = server.record_ruling({"id": "Q-950", "intent": "choose", "option": "a",
                                      "submission_id": "sub-q950-000000001",
                                      "judgment": "Quieter than the watering can."})
        self.assertEqual(again["integration_work_id"], card["id"])
        self.assertEqual(len(self.cards("Q-950")), 1, "a retried post files nothing new")
        with open(os.path.join(self.tmp, "rulings", "RULINGS.md"), encoding="utf-8") as f:
            self.assertIn(f"- Integration work: {card['id']}", f.read())

    def test_an_ownerless_decision_goes_to_the_chief_of_staff(self):
        server.record_ruling({"id": "Q-951", "intent": "choose", "option": "b",
                              "submission_id": "sub-q951-000000001"})
        [card] = self.cards("Q-951")
        self.assertEqual(card["owner"], "claude")
        self.assertEqual(card["title"], "Act on your ruling: Should the fence be lighter — you chose The second way")

    def test_a_revision_files_no_integration_card(self):
        server.record_ruling({"id": "Q-950", "intent": "revise", "judgment": "Show me both first.",
                              "submission_id": "sub-q950-000000002"})
        self.assertEqual(self.cards("Q-950"), [])
        self.assertEqual(server.rulings_waiting(), [], "a request for revision is not a ruling to act on")

    def test_rulings_waiting_before_start_are_backfilled_once(self):
        Path(self.tmp, "rulings", "Q-950.json").write_text(json.dumps({
            "id": "Q-950", "option": "b", "option_label": "The second way", "intent": "choose",
            "submission_id": "old-submission-001", "ruled_at": "2026-09-20T09:00:00",
            "status": "pending_integration", "earlier": []}))
        Path(self.tmp, "rulings", "Q-951.json").write_text(json.dumps({
            "id": "Q-951", "option": "a", "option_label": "The first way", "intent": "choose",
            "submission_id": "old-submission-002", "ruled_at": "2026-09-19T09:00:00",
            "status": "integrated", "earlier": []}))
        filed = server.backfill_ruling_work()
        [card] = self.cards("Q-950")
        self.assertEqual(filed, [card["id"]])
        self.assertEqual(self.cards("Q-951"), [], "an integrated ruling needs no card")
        self.assertEqual(self.ruling("Q-950")["integration_work_id"], card["id"])
        self.assertEqual(server.backfill_ruling_work(), [], "a second start files nothing new")

    def test_the_queue_lists_a_ruling_until_it_is_integrated(self):
        server.record_ruling({"id": "Q-950", "intent": "choose", "option": "a",
                              "submission_id": "sub-q950-000000003", "judgment": "Soft."})
        [row] = server.rulings_waiting()
        self.assertEqual((row["id"], row["judgment"], row["owner"], row["work_state"]),
                         ("Q-950", "Soft.", "rin", "waiting_session"))
        card = server.work.load_item(row["work_id"])
        card["state"] = "dropped"
        server.work.save_item(card)
        [row] = server.rulings_waiting()
        self.assertEqual(row["work_state"], "dropped",
                         "dropping the card does not hide a ruling nobody acted on")
        ruling = self.ruling("Q-950")
        ruling["status"] = "integrated"
        Path(self.tmp, "rulings", "Q-950.json").write_text(json.dumps(ruling))
        self.assertEqual(server.rulings_waiting(), [])


if __name__ == "__main__":
    unittest.main()

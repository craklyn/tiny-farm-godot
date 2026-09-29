#!/usr/bin/env python3
"""Recurring duties enter the queue on their schedule, and only then (Q-134)."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import schedules
import work
from test_drain import fake_host

DAY = 86400.0
ORG = {"employees": [{"id": "marcus"}, {"id": "fatima"}, {"id": "claude"}]}


def duty(**fields):
    entry = {"id": "weekly-review", "owner": "marcus", "title": "Write this week's review",
             "every_days": 7, "priority": "ordinary", "tier": 1, "follows": "/pillar/product",
             "ask": "Review the week.", "first_action": "List the numbers."}
    entry.update(fields)
    return entry


class Schedules(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        host = fake_host(str(Path(self.tmp.name) / "data"))
        host.load_json = lambda path: json.loads(Path(path).read_text())
        host.load_org = lambda: ORG
        work.bind(host, sanitize=False)

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_duty_never_filed_is_filed_once_at_its_regular_priority(self):
        cards = schedules.file_due({"schedules": [duty()]}, [], ORG, now=100 * DAY)
        self.assertEqual(len(cards), 1)
        card = work.load_item(cards[0]["id"])
        self.assertEqual((card["source"], card["source_ref"], card["owner"], card["state"]),
                         ("schedule", "schedule:weekly-review", "marcus", "waiting_session"))
        self.assertFalse(card.get("urgent"))
        # Filed again straight away: the open card holds it.
        self.assertEqual(schedules.file_due({"schedules": [duty()]}, [], ORG, now=100 * DAY), [])

    def test_an_urgent_duty_is_filed_urgent(self):
        card = schedules.file_due({"schedules": [duty(priority="urgent")]}, [], ORG)[0]
        self.assertTrue(work.load_item(card["id"])["urgent"])

    def test_a_closed_duty_comes_back_only_after_its_interval(self):
        card = schedules.file_due({"schedules": [duty()]}, [], ORG)[0]
        card = work.load_item(card["id"])
        card["state"] = "landed"
        work.save_item(card)
        filed = float(card["created_ts"])
        self.assertEqual(schedules.file_due({"schedules": [duty()]}, [], ORG, now=filed + 6 * DAY), [])
        self.assertEqual(len(schedules.file_due({"schedules": [duty()]}, [], ORG, now=filed + 7 * DAY)), 1)

    def test_a_duty_of_a_switched_off_function_or_with_an_off_reason_is_not_filed(self):
        doc = {"schedules": [duty(), duty(id="digest", owner="fatima", follows="/pillar/ops"),
                             duty(id="kpi", off="No KPI is defined yet.")]}
        ready, skipped = schedules.due(doc["schedules"], [], ["/pillar/ops", "/pillar/product"])
        self.assertEqual(ready, [])
        self.assertEqual(skipped["digest"], "/pillar/ops is switched off")
        self.assertEqual(skipped["kpi"], "No KPI is defined yet.")
        ready, _ = schedules.due(doc["schedules"], [], ["/pillar/ops"])
        self.assertEqual([e["id"] for e in ready], ["weekly-review"])

    def test_nothing_is_filed_because_the_queue_is_empty(self):
        # The ruling: an empty queue is fine. Filing depends on the schedule alone.
        self.assertEqual(schedules.file_due({"schedules": []}, [], ORG), [])
        self.assertEqual(work.items(), [])

    def test_the_checked_in_schedule_is_well_formed(self):
        # Well-formed only: switching a function back on must not turn this red.
        here = Path(__file__).resolve().parents[1] / "data"
        doc = json.loads((here / "schedules.json").read_text())
        seats = {e["id"] for e in json.loads((here / "org.json").read_text())["employees"]}
        ids = [entry["id"] for entry in doc["schedules"]]
        self.assertEqual(len(ids), len(set(ids)))
        for entry in doc["schedules"]:
            self.assertIn(entry["owner"], seats)
            self.assertIn(entry["priority"], schedules.PRIORITY_FLAGS)
            self.assertGreater(entry["every_days"], 0)
            self.assertIn(entry.get("tier", 1), (0, 1, 2))
            self.assertTrue(entry["title"] and entry["ask"])

if __name__ == "__main__":
    unittest.main()

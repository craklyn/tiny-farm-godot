#!/usr/bin/env python3
"""A task card derives its history from durable worker and review evidence."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server
import drain
import work


class WorkTimeline(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hq-work-timeline-")
        self.root = Path(self.temp.name)
        self.workers = self.root / "workers"
        self.transactions = self.root / "transactions"
        run = self.workers / "20260922-test"
        run.mkdir(parents=True)
        base = {"item": "we6190884f9a", "attempt_id": "attempt-1",
                "started": "2026-09-22T16:36:09-07:00", "finished": "2026-09-22T16:37:17-07:00"}
        (run / "we6190884f9a-drain-work.json").write_text(json.dumps({
            **base, "seat": "yuki", "phase": "drain-work"}), encoding="utf-8")
        (run / "we6190884f9a-drain-work.jsonl").write_text("", encoding="utf-8")
        (run / "we6190884f9a-drain-check.json").write_text(json.dumps({
            **base, "seat": "claude", "phase": "drain-check",
            "started": "2026-09-22T16:37:17-07:00", "finished": "2026-09-22T16:37:36-07:00"}), encoding="utf-8")
        finding = {"verdict": "concerns", "complete": False,
                   "summary": "The page was not opened.", "findings": [{
                       "what": "The HQ page was not opened in a browser.",
                       "fix": "Open it and confirm the animation renders."}]}
        event = {"type": "assistant", "message": {"content": [{
            "type": "text", "text": json.dumps(finding)}]}}
        (run / "we6190884f9a-drain-check.jsonl").write_text(
            json.dumps(event) + "\n", encoding="utf-8")
        self.item = {"id": "we6190884f9a", "state": "waiting_session", "started": "2026-09-22T16:36",
                     "conversation": [{"role": "daniel", "text": "Where is it?",
                                       "at": "2026-09-19T23:48"}]}

    def tearDown(self):
        self.temp.cleanup()

    def test_review_is_visible_when_card_writeback_never_happened(self):
        with patch.object(server, "WORKERS_DIR", str(self.workers)), \
             patch.object(server, "TRANSACTIONS_DIR", str(self.transactions)), \
             patch.object(server.work, "load_item", return_value=self.item), \
             patch.object(server, "drain_state", return_value=None):
            detail = server.work_detail("we6190884f9a")
        self.assertEqual(detail["effective"]["state"], "repair_needed")
        self.assertTrue(detail["effective"]["record_is_behind"])
        self.assertEqual([row["kind"] for row in detail["timeline"]],
                         ["comment", "work_finished", "review_finding", "run_interrupted"])
        finding = next(row for row in detail["timeline"] if row["kind"] == "review_finding")
        self.assertIn("not opened", finding["summary"])
        self.assertEqual(finding["session"]["name"], "we6190884f9a-drain-check")

    def test_sessions_do_not_age_out_of_a_card(self):
        with patch.object(server, "WORKERS_DIR", str(self.workers)), \
             patch.object(server, "TRANSACTIONS_DIR", str(self.transactions)), \
             patch.object(server.work, "load_item", return_value={**self.item, "started": "", "check": {"verdict": "concerns"}}):
            detail = server.work_detail("we6190884f9a")
        self.assertTrue(any(row["kind"] == "work_finished" for row in detail["timeline"]))

    def test_dead_transaction_records_review_without_another_model(self):
        directory = self.transactions / "dead-run"
        directory.mkdir(parents=True)
        transaction = directory / "we6190884f9a.json"
        transaction.write_text(json.dumps({
            "version": 2, "run": "dead-run", "item": "we6190884f9a", "pid": 99999999,
            "phase": "review_finished", "at": "2026-09-22T16:37:36-07:00",
            "scope_id": work.instruction_fingerprint(self.item),
            "item_revision": self.item.get("_revision", 0),
            "record": {"attempt_id": "attempt-1", "check": {"verdict": "concerns", "findings": [{"what": "Verify it."}]},
                       "seat": "yuki", "model": "test", "usage": [], "result": "Done", "patch": "", "stat": "", "files": [],
                       "error": "", "limited": False, "resume": ""}},
        ), encoding="utf-8")
        with patch.object(drain, "TRANSACTIONS", str(self.transactions)), \
             patch.object(drain.work, "load_item", return_value=self.item), \
             patch.object(drain, "write_back", return_value=self.item) as write_back:
            self.assertEqual(drain.recover_interrupted_transactions({}), 1)
            self.assertEqual(drain.recover_interrupted_transactions({}), 0)
        write_back.assert_called_once()
        self.assertEqual(json.loads(transaction.read_text())["phase"], "written_back")


if __name__ == "__main__":
    unittest.main()

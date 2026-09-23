#!/usr/bin/env python3
"""Accepted drain lessons become durable once, and rejected work leaves none."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain
import server
import work


ORG = {"employees": [
    {"id": "daniel", "name": "Daniel", "title": "CEO", "level": "L10",
     "team": "Executive", "responsibilities": [], "persona": ""},
    {"id": "sam", "name": "Sam", "title": "Engineer", "level": "L5",
     "team": "Engineering", "responsibilities": [], "persona": ""},
]}


def result(note="Keep fixtures deterministic."):
    return ("The requested work is complete.\n"
            f"<remember>{note}</remember>\n"
            + work.FOLLOW_MARK + "\n"
            + json.dumps({"outcome": {"status": "complete", "reason": ""}, "items": []}))


def record(attempt="attempt-1", *, files=False, lesson=None, note="Keep fixtures deterministic."):
    check = {"verdict": "pass", "complete": True, "read": True,
             "findings": [], "lesson_for_owner": lesson}
    rec = {"id": "wabcdef123456", "attempt_id": attempt, "seat": "sam",
           "model": "fixture", "usage": [], "result": result(note),
           "patch": "fixture patch" if files else "", "files": ["sample.txt"] if files else [],
           "stat": "sample.txt | 1 +" if files else "", "error": "", "limited": False,
           "check": check, "candidate_unchanged": True}
    rec["candidate"] = {"tree": "fixture-tree", "base": "fixture-base",
                        "files": {}, "base_files": {}}
    rec["candidate_suites"] = ({"unit": {"ok": True}, "integration": {"ok": True}}
                                if files else None)
    rec["candidate_test_evidence"] = work.evidence_id([rec["candidate"], rec["candidate_suites"]])
    rec["check_evidence"] = work.evidence_id([rec["result"], rec["patch"], rec["candidate"]])
    return rec


class DurableMemory(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old_data, self.old_repo, self.old_load_org = server.DATA, server.REPO, server.load_org
        self.old_worktrees = drain.WORKTREES
        server.DATA = self.tmp.name
        server.REPO = self.tmp.name
        drain.WORKTREES = str(Path(self.tmp.name, "worktrees"))
        server.load_org = lambda: ORG
        work.bind(server)

    def tearDown(self):
        server.DATA, server.REPO, server.load_org = self.old_data, self.old_repo, self.old_load_org
        drain.WORKTREES = self.old_worktrees
        self.tmp.cleanup()

    def card(self, *, tier=1):
        return work.save_item({"id": "wabcdef123456", "title": "Make the fixture deterministic",
            "owner": "sam", "tier": tier, "state": "waiting_session", "ask": "Fix it.",
            "first_action": "Read the fixture.", "attempts": 0})

    def pending(self, *, attempt="attempt-1", note="Keep fixtures deterministic.", lesson=None):
        item = self.card()
        return drain.write_back(item, record(attempt, files=True, note=note, lesson=lesson),
                                False, "the candidate was not applied", None, ORG)

    def memory(self):
        path = Path(server.staff_memory_path("sam"))
        return path.read_text() if path.exists() else ""

    def test_parser_and_attributed_format_are_idempotent_and_exactly_removable(self):
        visible, notes = server.parse_remembered(
            "Before <remember>  Keep this   rule. </remember> after <REMEMBER>x</REMEMBER>")
        self.assertEqual(visible, "Before  after")
        self.assertEqual(notes, ["Keep this rule.", "x"])
        server.append_staff_memory("sam", "An unrelated chat note.")
        proposals = [{"source": "owner", "text": notes[0]}, {"source": "checker", "text": notes[1]}]
        self.assertTrue(server.commit_attributed_staff_memory("sam", "wabcdef123456", "attempt-1", proposals))
        self.assertFalse(server.commit_attributed_staff_memory("sam", "wabcdef123456", "attempt-1", proposals))
        text = self.memory()
        self.assertEqual(text.count("hq:owner-memory:v1 key="), 1)
        self.assertIn("accepted work wabcdef123456; owner", text)
        self.assertIn("accepted work wabcdef123456; checker", text)
        self.assertTrue(server.remove_attributed_staff_memory("sam", "wabcdef123456", "attempt-1"))
        self.assertIn("An unrelated chat note.", self.memory())
        self.assertNotIn("Keep this rule.", self.memory())
        self.assertFalse(server.remove_attributed_staff_memory("sam", "wabcdef123456", "attempt-1"))

    def test_checker_schema_is_explicit_and_malformed_lessons_fail_completeness(self):
        base = {"verdict": "pass", "complete": True, "summary": "Checked.", "findings": [],
                "escalates": None, "escalation_reason": None}
        parsed = drain.parse_check(json.dumps({**base,
            "lesson_for_owner": {"text": "  Test the persisted boundary.  "}}))
        self.assertTrue(parsed["complete"])
        self.assertEqual(parsed["lesson_for_owner"], {"text": "Test the persisted boundary."})
        malformed = drain.parse_check(json.dumps({**base, "lesson_for_owner": "hide this in prose"}))
        self.assertFalse(malformed["complete"])
        self.assertIsNone(malformed["lesson_for_owner"])

    def test_worker_result_stays_pending_in_main_tree_until_manual_acceptance(self):
        worker_memory = Path(self.tmp.name, "worker-worktree", "hq/data/staff/sam/memory.md")
        worker_memory.parent.mkdir(parents=True)
        worker_memory.write_text("worker copy\n")
        item = self.pending(lesson={"text": "Review the persisted result, not the claim."})
        self.assertEqual(item["state"], "for_review")
        self.assertNotIn("<remember>", item["result"])
        self.assertNotIn("lesson_for_owner", item["check"])
        self.assertEqual(self.memory(), "")
        self.assertEqual(worker_memory.read_text(), "worker copy\n")
        accepted = work.api_post("/api/work/accept", {"id": item["id"], "_revision": item["_revision"]})
        self.assertEqual(accepted["state"], "accepted")
        self.assertIn("Keep fixtures deterministic.", self.memory())
        self.assertIn("Review the persisted result, not the claim.", self.memory())
        again = work.api_post("/api/work/accept", {"id": item["id"], "_revision": accepted["_revision"]})
        self.assertEqual(again["state"], "accepted")
        self.assertEqual(self.memory().count("hq:owner-memory:v1 key="), 1)

    def test_clean_auto_land_commits_once_and_undo_removes_only_its_note(self):
        server.append_staff_memory("sam", "Keep this unrelated note.")
        item = self.card(tier=0)
        rec = record(lesson={"text": "A clean review may teach a reusable boundary."})
        landed = drain.write_back(item, rec, False, "nothing changed", None, ORG)
        self.assertEqual(landed["state"], "landed")
        self.assertTrue(landed["owner_memory"]["committed"])
        self.assertIn("A clean review may teach", self.memory())
        drain.write_back(landed, rec, False, "nothing changed", None, ORG)
        self.assertEqual(self.memory().count("hq:owner-memory:v1 key="), 1)
        undone = work.api_post("/api/work/undo", {"id": landed["id"], "_revision": landed["_revision"]})
        self.assertTrue(undone["ok"])
        self.assertIn("Keep this unrelated note.", self.memory())
        self.assertNotIn("A clean review may teach", self.memory())

    def test_revision_replaces_proposals_and_drop_rejects_both_pending_and_committed(self):
        item = self.pending(note="Old rule.")
        work.requeue_for_revision(item)
        revised = drain.write_back(item, record("attempt-2", files=True, note="Replacement rule."),
                                   False, "not applied", None, ORG)
        self.assertEqual(revised["owner_memory"]["attempt_id"], "attempt-2")
        self.assertEqual([p["text"] for p in revised["owner_memory"]["proposals"]], ["Replacement rule."])
        dropped = work.api_post("/api/work/drop", {"id": revised["id"], "_revision": revised["_revision"]})
        self.assertEqual(dropped["state"], "dropped")
        self.assertEqual(self.memory(), "")

        Path(work._item_path(item["id"])).unlink()
        committed = self.pending(note="Accepted then rejected.")
        committed = work.api_post("/api/work/accept", {"id": committed["id"], "_revision": committed["_revision"]})
        self.assertIn("Accepted then rejected.", self.memory())
        rejected = work.api_post("/api/work/drop", {"id": committed["id"], "_revision": committed["_revision"]})
        self.assertEqual(rejected["state"], "dropped")
        self.assertNotIn("Accepted then rejected.", self.memory())

    def test_superseding_a_result_removes_its_attributed_note(self):
        item = self.pending(note="Duplicate result rule.")
        item = work.api_post("/api/work/accept", {"id": item["id"], "_revision": item["_revision"]})
        self.assertIn("Duplicate result rule.", self.memory())
        superseded = work.supersede_item(item, "w111111111111")
        self.assertEqual(superseded["superseded_by"], "w111111111111")
        self.assertNotIn("Duplicate result rule.", self.memory())


if __name__ == "__main__":
    unittest.main()

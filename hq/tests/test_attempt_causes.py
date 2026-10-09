#!/usr/bin/env python3
"""Failed work attempts retain one cause and their own token cost."""
import io
import sys
import json
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import work  # noqa: E402
import server  # noqa: E402
import action_dispatch  # noqa: E402
import migrate_attempt_records  # noqa: E402


class AttemptCauses(unittest.TestCase):
    def test_failed_outcomes_get_one_stable_cause(self):
        self.assertEqual(work.attempt_outcome("", "sandbox failed")["cause"], "environment")
        self.assertEqual(work.attempt_outcome("", limited=True)["cause"], "capability")
        blocked = 'Done\n---WHAT FOLLOWS---\n{"outcome":{"status":"blocked","reason":"needs a decision"}}'
        unfinished = 'Done\n---WHAT FOLLOWS---\n{"outcome":{"status":"unfinished","reason":"tests fail"}}'
        blocked_environment = ('Done\n---WHAT FOLLOWS---\n'
                               '{"outcome":{"status":"blocked","reason":"sandbox denied the write",'
                               '"cause":"environment"}}')
        self.assertEqual(work.attempt_outcome(blocked)["cause"], "scope")
        self.assertEqual(work.attempt_outcome(unfinished)["cause"], "code")
        self.assertEqual(work.attempt_outcome(blocked_environment)["cause"], "environment")

    def test_preservation_keeps_each_attempt_immutable(self):
        item = {"attempt_outcome": {"id": "a1", "status": "unfinished",
                                    "reason": "tests fail", "cause": "code", "tokens": 120}}
        work.preserve_attempt(item)
        work.preserve_attempt(item)
        work.preserve_attempt(item, cause="review")
        self.assertEqual(item["attempt_history"], [{"id": "a1", "status": "unfinished",
                                                     "reason": "tests fail", "cause": "code",
                                                     "tokens": 120}])

    def test_totals_count_history_and_the_current_attempt_once(self):
        rows = work.attempt_cause_totals([{
            "attempt_history": [
                {"id": "a1", "cause": "environment", "tokens": 30},
                {"id": "a2", "cause": "review", "tokens": 70},
            ],
            "attempt_outcome": {"id": "a2", "cause": "review", "tokens": 70},
        }, {
            "attempt_outcome": {"id": "a3", "cause": "code", "tokens": 50},
        }])
        got = {row["cause"]: (row["attempts"], row["tokens"]) for row in rows}
        self.assertEqual(got["environment"], (1, 30))
        self.assertEqual(got["review"], (1, 70))
        self.assertEqual(got["code"], (1, 50))
        self.assertEqual(got["capability"], (0, 0))

    def test_legacy_attempts_are_classified_and_filled_before_counting(self):
        item = {
            "usage": {"tokens": 90},
            "attempt_history": [
                {"id": "a1", "status": "blocked", "reason": "sandbox denied the write"},
                {"id": "a2", "status": "unfinished", "reason": "the token limit ended"},
            ],
            "attempt_outcome": {"id": "a3", "status": "blocked", "reason": "needs a decision"},
        }
        rows = work.attempt_cause_totals([item])
        got = {row["cause"]: (row["attempts"], row["tokens"], row["unknown_tokens"]) for row in rows}
        # The card's 90 tokens belong to all three attempts together; none of
        # them is given that total, and none is given zero.
        self.assertEqual(got["environment"], (1, 0, 1))
        self.assertEqual(got["capability"], (1, 0, 1))
        self.assertEqual(got["scope"], (1, 0, 1))
        self.assertEqual(item["attempt_history"][0]["cause"], "environment")
        self.assertIsNone(item["attempt_outcome"]["tokens"])

    def test_a_finished_attempt_is_not_counted_as_one_that_did_not_land(self):
        text = ("Done.\n" + work.FOLLOW_MARK + "\n" + json.dumps(
            {"items": [], "outcome": {"status": "complete", "reason": "", "cause": "code"}}))
        outcome = work.attempt_outcome(text)
        self.assertEqual(outcome["status"], "complete")
        self.assertNotIn("cause", outcome)
        rows = work.attempt_cause_totals([{"attempt_outcome": {**outcome, "id": "a1", "tokens": 40}}])
        self.assertEqual(sum(row["attempts"] for row in rows), 0)

    def test_legacy_current_attempt_uses_its_matching_review(self):
        item = {
            "attempt_outcome": {"id": "a1", "status": "unfinished", "reason": "changes made"},
            "check": {"attempt_id": "a1", "verdict": "fail", "findings": ["wrong result"]},
        }
        work.normalize_attempt_records(item)
        self.assertEqual(item["attempt_outcome"]["cause"], "review")

    def test_engineering_health_classifies_without_changing_card_revision(self):
        item = {"id": "w1", "_revision": 0,
                "attempt_outcome": {"id": "a1", "status": "blocked",
                                    "reason": "sandbox denied the write"}}
        with (mock.patch.object(work, "items", return_value=[item]),
              mock.patch.object(work, "save_item") as save,
              mock.patch.object(work, "card_health", return_value={"checked": 1}),
              mock.patch.object(server, "load_org", return_value={"employees": []}),
              mock.patch("drain.sh", return_value=mock.Mock(returncode=1, stdout="")),
              mock.patch("drain.server.drain_state", return_value={}),
              mock.patch("drain.project_work", return_value={})):
            result = server.work_health()
            again = server.work_health()
        save.assert_not_called()
        self.assertEqual(item["_revision"], 0)
        self.assertEqual(item["attempt_outcome"]["cause"], "environment")
        causes = {row["cause"]: row for row in result["attempt_causes"]}
        self.assertEqual(causes["environment"]["attempts"], 1)
        self.assertEqual(again["attempt_causes"], result["attempt_causes"])

    def test_explicit_legacy_migration_dispatches_each_card_once(self):
        item = {"id": "w1", "_revision": 0, "state": "for_review",
                "attempt_outcome": {"id": "a1", "status": "blocked",
                                    "reason": "sandbox denied the write"}}

        def save(saved):
            saved["_revision"] += 1

        with (mock.patch.object(work, "items", return_value=[item]),
              mock.patch.object(work, "load_item", return_value=item),
              mock.patch.object(work, "mutation_lock", return_value=mock.MagicMock()),
              mock.patch.object(work, "save_item", side_effect=save) as save_item):
            self.assertEqual(action_dispatch.migrate_attempt_records(work), ["w1"])
            self.assertEqual(action_dispatch.migrate_attempt_records(work), [])
        save_item.assert_called_once_with(item)
        self.assertEqual(item["_revision"], 1)

    def test_migration_command_uses_the_dispatcher(self):
        with (mock.patch.object(migrate_attempt_records.action_dispatch,
                                "migrate_attempt_records", return_value=["w1"]),
              mock.patch("sys.stdout", new_callable=io.StringIO) as output):
            self.assertEqual(migrate_attempt_records.main(), 0)
        self.assertEqual(output.getvalue(), '{"migrated": ["w1"], "count": 1}\n')


if __name__ == "__main__":
    unittest.main()

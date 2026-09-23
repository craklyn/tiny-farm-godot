#!/usr/bin/env python3
"""Runnable recovery actions, crash leases, and exact-commit CI evidence."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import action_dispatch
import drain
import server
import work
from test_drain import fake_host


class ActionDispatch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.repo / "weather.gd").write_text("before\n")
        self.git("add", "weather.gd")
        self.git("commit", "-qm", "base")
        self.data = self.root / "data"
        host = fake_host(str(self.data))
        host.load_json = lambda path: json.loads(Path(path).read_text())
        host.token_window = lambda: {"tokens": 0, "calls": 0}
        work.bind(host, sanitize=False)
        self.patches = self.root / "patches"
        self.patches.mkdir()
        self.p1 = patch.object(drain, "PATCHES", str(self.patches)); self.p1.start()
        self.p2 = patch.object(drain, "REPO", str(self.repo)); self.p2.start()
        self.p3 = patch.object(server, "drain_state", return_value=None); self.p3.start()

    def tearDown(self):
        for p in (self.p3, self.p2, self.p1):
            p.stop()
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo,
                              capture_output=True, text=True, check=True).stdout.strip()

    def card(self, **fields):
        item = {"id": "w123456789abc", "title": "Weather replay", "owner": "grace",
                "tier": 1, "state": "for_review", "ask": "Fix the weather replay",
                "first_action": "Repair the assertion", "created": "2026-09-22T00:00:00+00:00",
                "created_ts": 1, "attempts": 1, "started": "",
                "repair_hold": "The prior candidate needs fresh tests."}
        item.update(fields)
        return work.save_item(item)

    def test_weather_reconciliation_is_selected_once_and_has_specific_brief(self):
        item = self.card()
        selected = action_dispatch.choose(drain)
        self.assertEqual(len(selected), 1)
        picked, action = selected[0]
        self.assertEqual(picked["id"], item["id"])
        self.assertEqual(action["type"], "reconcile")
        brief = drain.task_prompt(item, {"employees": []}, action=action,
                                  blocker=drain.project_work(item)["blocker"])
        self.assertIn("NEW completed owner result", brief)
        self.assertIn("fresh checker verdict", brief)
        claim = action_dispatch.claim(work, picked, action, "run-1")
        self.assertTrue(claim)
        self.assertEqual(action_dispatch.claim(work, picked, action, "run-2"), "")
        self.assertEqual(len(work.load_item(item["id"])["workflow"]["actions"]), 1)
        self.assertEqual(action_dispatch.choose(drain), [])

    def test_weather_action_enters_owner_checker_lane_once(self):
        item = self.card()
        action = action_dispatch.choose(drain)[0][1]
        observed = []

        def owner_lane(selected, org, run_id, log, *, action=None):
            observed.append((selected["id"], action["type"], action["owner"]))
            return {"id": selected["id"], "held": True, "error": "Fixture paused",
                    "usage": [], "check": None, "applied": False}

        with patch.object(drain.integration, "handoff_status", return_value=(True, "")), \
             patch.object(drain, "resolve_handoff_action"), \
             patch.object(drain, "record_phase"), \
             patch.object(drain, "do_item", side_effect=owner_lane):
            records, done = drain.run_verified_batch([item], {"employees": []},
                                                     "run-weather", lambda _: None,
                                                     actions={item["id"]: action})
        self.assertEqual(observed, [(item["id"], "reconcile", "grace")])
        self.assertEqual(done, [])
        self.assertTrue(records[item["id"]]["held"])
        self.assertEqual(work.load_item(item["id"])["workflow"]["actions"][0]["state"],
                         "blocked")

    def test_capacity_rebrief_never_enters_code_landing_lane(self):
        item = self.card()
        rebrief = {"id": "act-rebrief", "type": "rebrief", "owner": "claude",
                   "availability": "runnable", "input_id": "cap-1"}
        with patch.object(drain, "classified_actions", return_value=[(item, rebrief)]), \
             patch.object(drain, "do_item") as owner_lane:
            selected = action_dispatch.choose(drain)
            self.assertEqual(selected, [])
            owner_lane.assert_not_called()

    def test_interrupted_claim_reopens_and_completed_result_closes(self):
        item = self.card()
        action = action_dispatch.choose(drain)[0][1]
        action_dispatch.claim(work, item, action, "run-1")
        self.assertEqual(action_dispatch.recover_orphaned_claims(work), 1)
        fresh = work.load_item(item["id"])
        self.assertEqual(fresh["workflow"]["actions"][0]["state"], "open")
        claim = action_dispatch.claim(work, fresh, action, "run-2")
        self.assertTrue(claim)
        # Transaction recovery has written a newer result after the claim.
        fresh["finished"] = "2099-01-01T00:00:00+00:00"
        work.save_item(fresh)
        self.assertEqual(action_dispatch.recover_orphaned_claims(work), 1)
        self.assertEqual(work.load_item(item["id"])["workflow"]["actions"][0]["state"], "done")

    def test_ci_requires_matching_completed_sha_and_does_not_rewrite_on_poll(self):
        item = self.card(state="landed", repair_hold="", completion={"sha": "abc123"})
        wrong = {"headSha": "other", "status": "completed", "conclusion": "success",
                 "databaseId": 4, "url": "https://example.invalid/4"}
        self.assertFalse(action_dispatch.record_ci(work, item, wrong))
        self.assertEqual(action_dispatch.poll_ci(work, [item], lambda: [wrong], now=100), 1)
        fresh = work.load_item(item["id"])
        self.assertEqual(fresh["workflow"]["ci"]["status"], "unavailable")
        self.assertFalse(fresh["workflow"]["ci"]["confirmed"])
        poll = fresh["workflow"]["actions"][0]
        self.assertEqual(poll["type"], "poll_ci")
        before = fresh["_revision"]
        self.assertEqual(action_dispatch.poll_ci(work, [fresh], lambda: [wrong], now=101), 0)
        self.assertEqual(work.load_item(item["id"])["_revision"], before)
        right = {**wrong, "headSha": "abc123", "databaseId": 5}
        self.assertEqual(action_dispatch.poll_ci(work, [fresh], lambda: [right], now=1400), 1)
        ci = work.load_item(item["id"])["workflow"]["ci"]
        self.assertTrue(ci["confirmed"])
        self.assertEqual(ci["commit_sha"], "abc123")
        self.assertEqual(ci["run_id"], 5)

    def test_failed_ci_can_be_superseded_by_successful_rerun_on_same_sha(self):
        item = self.card(state="landed", repair_hold="", completion={"sha": "abc123"})
        failure = {"headSha": "abc123", "status": "completed", "conclusion": "failure",
                   "databaseId": 40, "url": "https://example.invalid/40",
                   "updatedAt": "2026-09-22T10:00:00Z"}
        self.assertEqual(action_dispatch.poll_ci(work, [item], lambda: [failure], now=100), 1)
        fresh = work.load_item(item["id"])
        self.assertEqual(fresh["workflow"]["ci"]["status"], "failed")
        self.assertFalse(fresh["workflow"]["ci"]["confirmed"])
        self.assertEqual(fresh["workflow"]["actions"][0]["state"], "open")
        revision = fresh["_revision"]
        self.assertEqual(action_dispatch.poll_ci(work, [fresh], lambda: [failure], now=1301), 0)
        self.assertEqual(work.load_item(item["id"])["_revision"], revision)
        rerun = {**failure, "databaseId": 41, "conclusion": "success",
                 "updatedAt": "2026-09-22T10:20:00Z"}
        wrong_newer = {**rerun, "headSha": "another", "databaseId": 42,
                       "updatedAt": "2026-09-22T10:30:00Z"}
        self.assertEqual(action_dispatch.poll_ci(work, [fresh],
                                                 lambda: [failure, wrong_newer, rerun],
                                                 now=1302), 1)
        final = work.load_item(item["id"])
        self.assertTrue(final["workflow"]["ci"]["confirmed"])
        self.assertEqual(final["workflow"]["ci"]["run_id"], 41)
        self.assertEqual(final["workflow"]["actions"][0]["state"], "done")


if __name__ == "__main__":
    unittest.main()

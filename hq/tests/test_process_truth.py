#!/usr/bin/env python3
"""Truthful project waits, consistency reads, and lossless plan writes."""
import copy
import datetime
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class ConsistencyTests(unittest.TestCase):
    def _sources(self, work_rows):
        project = {"id": "project-one", "owner": "owner", "contributors": []}
        goal = {"id": "goal-one", "measure": {"kind": "fixture"},
                "path_to_green": {"route": {"kind": "work", "id": "work-one"}}}
        return (
            patch.object(server, "load_org", return_value={"employees": [{"id": "owner"}]}),
            patch.object(server, "load_projects", return_value=[project]),
            patch.object(server, "parse_queue", return_value={"items": []}),
            patch.object(server, "load_looks", return_value=[]),
            patch.object(server, "load_dir_json", return_value=[]),
            patch.object(server, "load_json", return_value={"pillars": [{"id": "product"}]}),
            patch.object(server, "load_goals", return_value={"goals": [goal]}),
            patch.object(server, "seat_for", return_value={"id": "owner"}),
            patch.object(server.work, "items", side_effect=work_rows),
        )

    def test_valid_invalid_repeat_and_unavailable_work_references(self):
        patches = self._sources(lambda **kwargs: [{"id": "work-one"}])
        with patches[0], patches[1], patches[2], patches[3], patches[4], \
             patches[5], patches[6], patches[7], patches[8]:
            self.assertEqual(server.check_consistency(), [])
            server.load_goals.return_value["goals"][0]["path_to_green"]["route"]["id"] = "missing"
            first = server.check_consistency()
            self.assertEqual(sum("does not exist" in row for row in first), 1)
            server.load_goals.return_value["goals"][0]["path_to_green"]["route"]["id"] = "work-one"
            self.assertEqual(server.check_consistency(), [])
            self.assertEqual(server._CONSISTENCY, [])
            server.work.items.side_effect = OSError("store offline")
            unavailable = server.check_consistency()
            self.assertEqual(sum("work references unavailable" in row for row in unavailable), 1)
            self.assertFalse(any("work-one'" in row and "does not exist" in row
                                 for row in unavailable))

    def test_main_binds_work_before_checking_references(self):
        order = []
        class StopServer(Exception):
            pass
        thread = Mock()
        with patch.object(server.work, "bind", side_effect=lambda host: order.append("bind")), \
             patch.object(server, "check_consistency", side_effect=lambda: order.append("check")), \
             patch.object(server, "sanitize_runs"), patch.object(server, "sanitize_outbox"), \
             patch.object(server.studio, "bind"), patch.object(server.anim, "bind"), \
             patch.object(server.threading, "Thread", return_value=thread), \
             patch.object(server.work, "start"), \
             patch.object(server, "ThreadingHTTPServer", side_effect=StopServer):
            with self.assertRaises(StopServer):
                server.main()
        self.assertEqual(order, ["bind", "check"])


class WaitingTests(unittest.TestCase):
    def project(self, event, **wait_changes):
        waiting = {"authorized_by": {"kind": "decision", "id": "Q-90"},
                   "wake_event": event, "resume_status": "planned"}
        waiting.update(wait_changes)
        return {"id": "waiter", "status": "waiting", "waiting": waiting}

    def test_valid_unsatisfied_release_wait_stays_quiet(self):
        project = self.project({"type": "release_reached", "release_id": "later"})
        plan = {"releases": [
            {"id": "now", "stories": [{"id": "s1", "done": False}]},
            {"id": "later", "stories": [{"id": "s1", "done": False}]},
        ]}
        result = server.evaluate_waiting_project(project, {"waiter": project}, plan, {"Q-90"})
        self.assertEqual(result["state"], "waiting")
        self.assertEqual(server._blocked_projects([{**project, "wake_evaluation": result}]), [])

    def test_satisfied_wait_returns_to_actionable_state(self):
        project = self.project({"type": "release_reached", "release_id": "later"})
        plan = {"releases": [
            {"id": "done", "stories": [{"id": "s1", "done": True}]},
            {"id": "later", "stories": [{"id": "s1", "done": False}]},
        ]}
        result = server.evaluate_waiting_project(project, {"waiter": project}, plan, {"Q-90"})
        self.assertEqual(result["state"], "satisfied")
        self.assertEqual(project["waiting"]["resume_status"], "planned")

    def test_project_reader_keeps_satisfied_wait_visible_and_blocks_invalid_wait(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            (data / "projects").mkdir()
            (data / "rulings").mkdir()
            (data / "rulings" / "Q-90.json").write_text(
                json.dumps({"id": "Q-90", "option": "a"}), encoding="utf-8")
            (data / "release_plan.json").write_text(json.dumps({"releases": [
                {"id": "current", "stories": [{"id": "s1", "done": False}]},
            ]}), encoding="utf-8")
            satisfied = self.project({"type": "release_reached", "release_id": "current"})
            invalid = {**self.project({"type": "project_status", "project_id": "gone",
                                      "status": "done"}), "id": "broken"}
            (data / "projects" / "waiter.json").write_text(json.dumps(satisfied), encoding="utf-8")
            (data / "projects" / "broken.json").write_text(json.dumps(invalid), encoding="utf-8")
            with patch.object(server, "DATA", str(data)), patch.object(server, "_last_touched", return_value="now"):
                rows = {row["id"]: row for row in server.load_projects()}
        self.assertEqual(rows["waiter"]["status"], "waiting")
        self.assertEqual(rows["waiter"]["wake_evaluation"]["state"], "satisfied")
        self.assertEqual(rows["broken"]["status"], "blocked")
        self.assertEqual(rows["broken"]["wake_evaluation"]["state"], "invalid")

    def test_reached_wait_is_a_fire_without_becoming_a_blocker(self):
        patient = {"id": "waiter", "name": "A planned pause", "status": "waiting",
                   "wake_evaluation": {"state": "satisfied", "reason": "the date arrived"}}
        asleep = {**patient, "id": "not-yet",
                  "wake_evaluation": {"state": "waiting", "reason": "not yet"}}
        fires = server._stale_wait_fires([patient, asleep])
        self.assertEqual(len(fires), 1)
        self.assertEqual(fires[0]["kind"], "fire")
        self.assertEqual(fires[0]["href"], "#/project/waiter")
        self.assertNotIn("unblocks", fires[0])
        self.assertEqual(server._blocked_projects([patient, asleep]), [])

    def test_invalid_reference_and_date_are_errors(self):
        missing = self.project({"type": "project_status", "project_id": "gone", "status": "done"})
        result = server.evaluate_waiting_project(missing, {"waiter": missing}, {}, {"Q-90"})
        self.assertEqual(result["state"], "invalid")
        self.assertIn("does not exist", result["reason"])
        dated = self.project({"type": "date_reached", "date": "not-a-date"})
        result = server.evaluate_waiting_project(dated, {"waiter": dated}, {}, {"Q-90"},
                                                 today=datetime.date(2026, 9, 22))
        self.assertEqual(result["state"], "invalid")

    def test_only_real_blockage_gates_a_release(self):
        projects = [
            {"id": "patient", "status": "waiting", "release": "r1", "release_critical": True,
             "plan": []},
            {"id": "stuck", "status": "blocked", "release": "r1", "release_critical": True,
             "plan": []},
        ]
        with patch.object(server, "load_projects", return_value=projects), \
             patch.object(server, "load_json", return_value={"releases": [{"id": "r1"}]}):
            release = server.api_program()["releases"][0]
        self.assertEqual(release["gating"], ["stuck"])


class ProductPlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.data = Path(self.temp.name)
        self.base = {
            "note": "keep", "capacity_days_per_week": 5, "top_unknown": {"keep": True},
            "releases": [{
                "id": "r1", "release_id": "train", "name": "Release", "codename": "v1",
                "contains": "Things", "release_unknown": [1, 2],
                "stories": [
                    {"id": "s1", "title": "First", "estimate_days": 1, "done": False,
                     "why": "important", "story_unknown": {"keep": True}},
                    {"id": "s2", "title": "Second", "estimate_days": 2, "done": False},
                ],
            }],
        }
        (self.data / "release_plan.json").write_text(json.dumps(self.base), encoding="utf-8")
        (self.data / "releases.json").write_text(json.dumps({"releases": []}), encoding="utf-8")
        self.data_patch = patch.object(server, "DATA", str(self.data))
        self.run_patch = patch.object(server, "run_cmd", return_value="")
        self.data_patch.start()
        self.run_patch.start()

    def tearDown(self):
        self.run_patch.stop()
        self.data_patch.stop()
        self.temp.cleanup()

    def stored(self):
        return json.loads((self.data / "release_plan.json").read_text(encoding="utf-8"))

    def payload(self, revision=None, stories=None, **release_changes):
        release = {"id": "r1", "release_id": "train", "name": "Release",
                   "codename": "v1", "contains": "Things",
                   "stories": stories if stories is not None else [
                       {"id": "s1", "title": "First changed", "estimate_days": 1.5, "done": True},
                   ],
                   "add_story_ids": [], "delete_story_ids": []}
        release.update(release_changes)
        return {"revision": revision or server._plan_revision(self.stored()),
                "capacity_days_per_week": 4, "releases": [release]}

    def test_save_preserves_unknown_fields_at_every_level_and_omitted_story(self):
        result = server.save_product_plan(self.payload())
        self.assertNotIn("error", result)
        stored = self.stored()
        self.assertEqual(stored["top_unknown"], {"keep": True})
        self.assertEqual(stored["releases"][0]["release_unknown"], [1, 2])
        self.assertEqual(stored["releases"][0]["stories"][0]["why"], "important")
        self.assertEqual(stored["releases"][0]["stories"][0]["story_unknown"], {"keep": True})
        self.assertEqual([s["id"] for s in stored["releases"][0]["stories"]], ["s1", "s2"])

    def test_add_and_delete_are_explicit(self):
        new_story = {"id": "s3", "title": "Third", "estimate_days": None, "done": False}
        rejected = server.save_product_plan(self.payload(stories=[new_story]))
        self.assertEqual(rejected["code"], "invalid_plan")
        self.assertEqual(self.stored(), self.base)

        added = self.payload(stories=[new_story], add_story_ids=["s3"])
        self.assertNotIn("error", server.save_product_plan(added))
        self.assertEqual([s["id"] for s in self.stored()["releases"][0]["stories"]],
                         ["s1", "s2", "s3"])

        revision = server._plan_revision(self.stored())
        omitted = self.payload(revision=revision, stories=[])
        self.assertNotIn("error", server.save_product_plan(omitted))
        self.assertEqual([s["id"] for s in self.stored()["releases"][0]["stories"]],
                         ["s1", "s2", "s3"])

        revision = server._plan_revision(self.stored())
        deleted = self.payload(revision=revision, stories=[], delete_story_ids=["s1"])
        self.assertNotIn("error", server.save_product_plan(deleted))
        self.assertEqual([s["id"] for s in self.stored()["releases"][0]["stories"]], ["s2", "s3"])

    def test_duplicate_missing_and_invalid_ids_do_not_write(self):
        cases = [
            self.payload(stories=[{"title": "No id", "done": False}]),
            self.payload(stories=[{"id": "bad id", "title": "Bad", "done": False}],
                         add_story_ids=["bad id"]),
            {**self.payload(), "releases": [self.payload()["releases"][0],
                                             self.payload()["releases"][0]]},
            self.payload(id="missing-release"),
        ]
        for payload in cases:
            before = self.stored()
            result = server.save_product_plan(payload)
            self.assertEqual(result["code"], "invalid_plan")
            self.assertEqual(self.stored(), before)

    def test_stale_revision_cannot_overwrite_newer_save(self):
        first = self.payload()
        stale = copy.deepcopy(first)
        stale["releases"][0]["stories"][0]["title"] = "Stale title"
        self.assertNotIn("error", server.save_product_plan(first))
        after_first = self.stored()
        rejected = server.save_product_plan(stale)
        self.assertEqual(rejected["code"], "stale_revision")
        self.assertEqual(self.stored(), after_first)


if __name__ == "__main__":
    unittest.main()

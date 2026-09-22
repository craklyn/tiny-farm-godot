#!/usr/bin/env python3
"""Focused, dependency-free checks for Animation Lab process boundaries."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import time
import types
import unittest
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim  # noqa: E402


class FakeHost:
    def note_limit(self, *_args, **_kwargs):
        pass

    def clear_limit(self, *_args, **_kwargs):
        pass

    def record_model_usage(self, *_args, **_kwargs):
        pass


class StoppedThread:
    starts = 0

    def __init__(self, target, args=(), daemon=None):
        self.target = target
        self.args = args
        self.daemon = daemon

    def start(self):
        type(self).starts += 1


class AnimationLabTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tiny-farm-anim-test-")
        root = Path(self.temp.name)
        self.repo = root / "repo"
        self.data = root / "data"
        self.repo.mkdir()
        self.data.mkdir()
        (self.data / "work").mkdir()
        (self.repo / "tools" / "experiments" / "out").mkdir(parents=True)
        (self.repo / "tools" / "experiments" / "ANIMATION_PROMPT.md").write_text(
            "rules\n---\n**SUBJECT:** old subject\n\nDraw it.", encoding="utf-8"
        )
        (self.repo / "tools" / "experiments" / "ANIMATION_NOTES.md").write_text(
            "notes", encoding="utf-8"
        )
        anim.REPO = str(self.repo)
        anim.DATA = str(self.data)
        anim.PREVIEWS = str(self.data / "loop_previews")
        anim.RUNS = str(self.data / "anim_runs")
        anim.HOST = FakeHost()
        anim._SRC_CACHE.clear()
        anim._INDEX_CACHE.update(key=None, data=None)
        StoppedThread.starts = 0

    def tearDown(self):
        self.temp.cleanup()

    def script(self, slug="sprout"):
        path = self.repo / "tools" / "experiments" / f"vfx_{slug}.py"
        path.write_text("# loop\n", encoding="utf-8")
        return path

    def review(self, slug="sprout", work_id="wr123", state="for_review", source="anim_lab"):
        item = {
            "id": work_id,
            "anim_slug": slug,
            "title": f"Say whether the {slug} loop is any good",
            "first_action": f"Open #/design/anim/{slug} and watch it at both sizes",
            "source": source,
            "state": state,
            "created_ts": time.time(),
            "conversation": [],
        }
        path = self.data / "work" / f"{work_id}.json"
        path.write_text(json.dumps(item), encoding="utf-8")
        return path

    def read_json(self, path):
        return json.loads(Path(path).read_text(encoding="utf-8"))

    def test_bad_slug_is_refused_before_execution(self):
        with mock.patch.object(anim.subprocess, "run") as run:
            result = anim.loop_render({"slug": "../sprout", "values": {"speed": 2}})
        self.assertEqual(result, {"error": "bad loop name"})
        run.assert_not_called()

    def test_render_clamps_values_to_declared_range(self):
        self.script()
        known = {"loops": [{"slug": "sprout", "params": [["speed", "Speed", 1, 4]],
                            "values": {"speed": 2}}]}

        def render(command, **_kwargs):
            out, overrides = Path(command[-2]), Path(command[-1])
            values = json.loads(overrides.read_text(encoding="utf-8"))
            out.mkdir(parents=True, exist_ok=True)
            (out / "params.json").write_text(json.dumps({"values": values}), encoding="utf-8")
            (out / "sprout_sheet.png").write_bytes(b"png")
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        with mock.patch.object(anim, "loops_index", return_value=known), \
                mock.patch.object(anim.subprocess, "run", side_effect=render):
            result = anim.loop_render({"slug": "sprout", "values": {"speed": 99}})
        self.assertEqual(result["values"]["speed"], 4)
        self.assertEqual(result["ignored"], [])

    def test_render_reports_an_ignored_override(self):
        self.script()
        known = {"loops": [{"slug": "sprout", "params": [["speed", "Speed", 1, 4]],
                            "values": {"speed": 2}}]}

        def ignore(command, **_kwargs):
            out = Path(command[-2])
            out.mkdir(parents=True, exist_ok=True)
            (out / "params.json").write_text(json.dumps({"values": {"speed": 2}}),
                                                   encoding="utf-8")
            (out / "sprout_sheet.png").write_bytes(b"png")
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        with mock.patch.object(anim, "loops_index", return_value=known), \
                mock.patch.object(anim.subprocess, "run", side_effect=ignore):
            result = anim.loop_render({"slug": "sprout", "values": {"speed": 4}})
        self.assertEqual(result["ignored"], ["speed"])

    def test_index_uses_source_and_render_mtimes_for_staleness(self):
        source = self.repo / "assets" / "sprites" / "generated" / "bird.png"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"bird")
        script = self.script()
        script.write_text('SOURCE = "assets/sprites/generated/bird.png"\n', encoding="utf-8")
        out = self.repo / "tools" / "experiments" / "out" / "sprout"
        out.mkdir()
        meta = out / "params.json"
        meta.write_text(json.dumps({"params": [], "values": {}}), encoding="utf-8")
        (out / "sprout_sheet.png").write_bytes(b"png")
        now = time.time()
        os.utime(meta, (now, now))
        os.utime(source, (now + 10, now + 10))
        result = anim.loops_index()["loops"][0]
        self.assertEqual(result["stale"], ["assets/sprites/generated/bird.png"])

    def test_start_run_records_work_before_launch_without_running_session(self):
        with mock.patch.object(anim.execution, "launch_allowed", return_value=True), \
                mock.patch.object(anim.threading, "Thread", StoppedThread), \
                mock.patch.object(anim.execution, "run_session") as paid:
            result = anim.start_run({"subject": "A seed pod opens and settles"})
        self.assertTrue(result["ok"])
        self.assertEqual(StoppedThread.starts, 1)
        self.assertEqual(self.read_json(anim._run_path(result["run"]["id"]))["state"], "drawing")
        paid.assert_not_called()

    def test_failed_run_files_no_work_item(self):
        run_id = "r123abc"
        anim._save_run({"id": run_id, "state": "drawing", "kind": "draw", "slug": ""})
        failed = {
            "exit_code": 1, "error": "agent failed", "text": "", "usage": None,
            "limited": False, "provider": "stub", "model": "stub",
        }
        with mock.patch.object(anim.execution, "run_session", return_value=failed):
            anim._draw(run_id, "prompt")
        self.assertEqual(anim._load_run(run_id)["state"], "failed")
        self.assertEqual(list((self.data / "work").iterdir()), [])

    def test_keep_and_drop_persist_reason_on_exact_review(self):
        for verdict, state in (("keep", "accepted"), ("drop", "dropped")):
            work_id = "wr" + verdict
            path = self.review(work_id=work_id)
            anim._INDEX_CACHE["key"] = "cached"
            result = anim.record_verdict(
                {"work_id": work_id, "slug": "sprout", "verdict": verdict,
                 "why": f"reason for {verdict}"}
            )
            saved = self.read_json(path)
            self.assertEqual(result["state"], state)
            self.assertEqual(saved["state"], state)
            self.assertIn(f"reason for {verdict}", saved["result"])
            self.assertEqual(saved["conversation"][-1]["text"], f"reason for {verdict}")
            self.assertIsNone(anim._INDEX_CACHE["key"])

    def test_verdict_without_exact_work_identity_has_no_side_effect(self):
        self.review()
        with mock.patch.object(anim.threading, "Thread", StoppedThread), \
                mock.patch.object(anim.execution, "run_session") as paid:
            result = anim.record_verdict(
                {"slug": "sprout", "verdict": "rework", "why": "Change the timing curve"}
            )
        self.assertIn("work item", result["error"])
        self.assertEqual(StoppedThread.starts, 0)
        paid.assert_not_called()

    def test_verdict_rejects_wrong_source_state_and_slug(self):
        cases = [
            ("wrsource", "for_review", "manual", "sprout"),
            ("wrstate", "accepted", "anim_lab", "sprout"),
            ("wrslug", "for_review", "anim_lab", "other"),
        ]
        for work_id, state, source, slug in cases:
            self.review(slug=slug, work_id=work_id, state=state, source=source)
            result = anim.record_verdict(
                {"work_id": work_id, "slug": "sprout", "verdict": "keep", "why": "It reads well"}
            )
            self.assertIn("error", result)

    def test_rework_transitions_exact_review_before_launch(self):
        self.script()
        path = self.review()
        with mock.patch.object(anim.execution, "launch_allowed", return_value=True), \
                mock.patch.object(anim.threading, "Thread", StoppedThread), \
                mock.patch.object(anim.execution, "run_session") as paid:
            result = anim.record_verdict(
                {"work_id": "wr123", "slug": "sprout", "verdict": "rework",
                 "why": "Slow the opening and hold the final pose"}
            )
        self.assertEqual(result["state"], "doing")
        self.assertEqual(result["work_id"], "wr123")
        self.assertEqual(self.read_json(path)["state"], "doing")
        self.assertEqual(result["run"]["work_item"], "wr123")
        self.assertEqual(StoppedThread.starts, 1)
        paid.assert_not_called()

    def test_review_filing_writes_slug_and_index_exposes_work_identity(self):
        self.script()
        out = self.repo / "tools" / "experiments" / "out" / "sprout"
        out.mkdir()
        (out / "params.json").write_text(json.dumps({"params": [], "values": {}}),
                                               encoding="utf-8")
        (out / "sprout_sheet.png").write_bytes(b"png")
        rec = {"id": "r456", "slug": "sprout", "subject": "A sprout opens",
               "started": "now", "cost": None}
        anim._save_run(rec)
        self.assertTrue(anim._file_for_review(rec))
        work_id = "wr456"
        self.assertEqual(self.read_json(self.data / "work" / f"{work_id}.json")["anim_slug"],
                         "sprout")
        anim._INDEX_CACHE.update(key=None, data=None)
        self.assertEqual(anim.loops_index()["loops"][0]["work_item"], work_id)


if __name__ == "__main__":
    unittest.main(verbosity=2)

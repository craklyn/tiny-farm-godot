#!/usr/bin/env python3
"""Focused, dependency-free checks for Animation Lab process boundaries."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim  # noqa: E402


class FakeHost:
    def load_json(self, path):
        return json.loads(Path(path).read_text(encoding="utf-8"))

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
        anim.work.HOST = FakeHost()
        anim.work.WORK = str(self.data / "work")
        anim.PREVIEWS = str(self.data / "loop_previews")
        anim.RUNS = str(self.data / "anim_runs")
        anim.HOST = FakeHost()
        anim._SRC_CACHE.clear()
        anim._INDEX_CACHE.update(key=None, data=None)
        StoppedThread.starts = 0
        # The owner's answer is a model call; record that it was asked for.
        self.replies = []
        self._real_start_reply = anim.work.start_reply
        anim.work.start_reply = self.replies.append

    def tearDown(self):
        anim.work.start_reply = self._real_start_reply
        self.temp.cleanup()

    def script(self, slug="sprout"):
        path = self.repo / "tools" / "experiments" / f"vfx_{slug}.py"
        path.write_text("# loop\n", encoding="utf-8")
        return path

    def review(self, slug="sprout", work_id="wa12345", state="for_review", source="anim_lab"):
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
            for name in ("sprout.gif", "sprout_contact.png", "sprout_1x.png"):
                (out / name).write_bytes(name.encode())
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        with mock.patch.object(anim, "loops_index", return_value=known), \
                mock.patch.object(anim.subprocess, "run", side_effect=render):
            result = anim.loop_render({"slug": "sprout", "values": {"speed": 99}})
            low = anim.loop_render({"slug": "sprout", "values": {"speed": -99}})
        self.assertEqual(result["values"]["speed"], 4)
        self.assertEqual(result["ignored"], [])
        self.assertEqual(low["values"]["speed"], 1)
        self.assertEqual(low["ignored"], [])

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
            for name in ("sprout.gif", "sprout_contact.png", "sprout_1x.png"):
                (out / name).write_bytes(name.encode())
            return types.SimpleNamespace(returncode=0, stdout="", stderr="")

        with mock.patch.object(anim, "loops_index", return_value=known), \
                mock.patch.object(anim.subprocess, "run", side_effect=ignore):
            result = anim.loop_render({"slug": "sprout", "values": {"speed": 4}})
        self.assertEqual(result["error"], "the script did not produce the requested complete preview")
        self.assertEqual(result["ignored"], ["speed"])

    def test_promote_copies_inspected_preview_and_records_change(self):
        self.script()
        target = self.repo / "tools" / "experiments" / "out" / "sprout"
        target.mkdir()
        for name in anim._render_names("sprout"):
            (target / name).write_bytes(b"old")
        (target / "params.json").write_text(json.dumps({"values": {"speed": 2}}))
        preview_id = "a" * 32
        preview = self.data / "loop_previews" / "sprout" / preview_id
        preview.mkdir(parents=True)
        for name in anim._render_names("sprout"):
            (preview / name).write_bytes(b"new")
        (preview / "params.json").write_text(json.dumps({"values": {"speed": 3}}))
        record = {"id": preview_id, "slug": "sprout", "values": {"speed": 3},
                  "source_sha256": anim._hash(str(self.repo / "tools/experiments/vfx_sprout.py")),
                  "base": anim._manifest(str(target), anim._render_names("sprout")),
                  "files": anim._manifest(str(preview), anim._render_names("sprout"))}
        (preview / "preview.json").write_text(json.dumps(record))
        clean = types.SimpleNamespace(returncode=0, stdout="")
        with mock.patch.object(anim.subprocess, "run", return_value=clean):
            result = anim.loop_promote({"slug": "sprout", "preview_id": preview_id})
        self.assertEqual(result["changes"], {"speed": {"from": 2, "to": 3}})
        self.assertEqual((target / "sprout_sheet.png").read_bytes(), b"new")
        history = [json.loads(line) for line in (target / "promotions.jsonl").read_text().splitlines()]
        self.assertEqual(history[0]["preview_id"], preview_id)
        with mock.patch.object(anim.subprocess, "run", return_value=clean):
            again = anim.loop_promote({"slug": "sprout", "preview_id": preview_id})
        self.assertIn("changed since this preview", again["error"])

    def test_promote_refuses_unfinished_target(self):
        self.script()
        preview_id = "b" * 32
        preview = self.data / "loop_previews" / "sprout" / preview_id
        preview.mkdir(parents=True)
        for name in anim._render_names("sprout"):
            (preview / name).write_bytes(b"new")
        record = {"id": preview_id, "slug": "sprout", "values": {"speed": 3},
                  "source_sha256": anim._hash(str(self.repo / "tools/experiments/vfx_sprout.py")),
                  "base": anim._manifest(str(self.repo / "tools/experiments/out/sprout"),
                                         anim._render_names("sprout")),
                  "files": anim._manifest(str(preview), anim._render_names("sprout"))}
        (preview / "preview.json").write_text(json.dumps(record))
        dirty = types.SimpleNamespace(returncode=0, stdout="?? tools/experiments/out/sprout/sprout_sheet.png\n")
        with mock.patch.object(anim.subprocess, "run", return_value=dirty):
            result = anim.loop_promote({"slug": "sprout", "preview_id": preview_id})
        self.assertIn("unfinished local changes", result["error"])

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
        sheet = out / "sprout_sheet.png"
        sheet.write_bytes(b"png")
        now = time.time()
        os.utime(meta, (now, now))
        os.utime(source, (now + 10, now + 10))
        os.utime(sheet, (now + 20, now + 20))
        result = anim.loops_index()["loops"][0]
        self.assertEqual(result["stale"], ["assets/sprites/generated/bird.png"])
        os.utime(source, (now - 10, now - 10))
        anim._INDEX_CACHE["key"] = None
        self.assertEqual(anim.loops_index()["loops"][0]["stale"], [])

    def test_showcase_save_invalidates_loop_index(self):
        source = self.repo / "assets" / "showcase" / "watering_beam" / "can.png"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"can")
        self.script().write_text('CAN = "assets/showcase/watering_beam/can.png"\n', encoding="utf-8")
        out = self.repo / "tools" / "experiments" / "out" / "sprout"
        out.mkdir()
        meta = out / "params.json"
        meta.write_text(json.dumps({"params": [], "values": {}}), encoding="utf-8")
        now = time.time()
        os.utime(source, (now - 10, now - 10))
        os.utime(meta, (now, now))
        self.assertEqual(anim.loops_index()["loops"][0]["stale"], [])
        os.utime(source, (now + 10, now + 10))
        self.assertEqual(anim.loops_index()["loops"][0]["stale"],
                         ["assets/showcase/watering_beam/can.png"])

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

    def test_success_without_a_loop_name_files_no_work_item(self):
        run_id = "r123abd"
        anim._save_run({"id": run_id, "state": "drawing", "kind": "draw", "slug": ""})
        unnamed = {
            "exit_code": 0, "error": "", "text": "Finished without a slug", "usage": None,
            "limited": False, "provider": "stub", "model": "stub",
        }
        with mock.patch.object(anim.execution, "run_session", return_value=unnamed):
            anim._draw(run_id, "prompt")
        self.assertEqual(anim._load_run(run_id)["state"], "failed")
        self.assertEqual(list((self.data / "work").iterdir()), [])

    def test_timed_out_run_files_no_work_item(self):
        run_id = "r123abe"
        anim._save_run({"id": run_id, "state": "drawing", "kind": "draw", "slug": ""})
        with mock.patch.object(anim.execution, "run_session",
                               side_effect=subprocess.TimeoutExpired("stub", 1)):
            anim._draw(run_id, "prompt")
        self.assertEqual(anim._load_run(run_id)["state"], "failed")
        self.assertEqual(list((self.data / "work").iterdir()), [])

    def test_keep_and_drop_persist_reason_on_exact_review(self):
        for verdict, state in (("keep", "accepted"), ("drop", "dropped")):
            work_id = "wa12345" if verdict == "keep" else "wa56789"
            path = self.review(work_id=work_id)
            anim._INDEX_CACHE["key"] = "cached"
            result = anim.record_verdict(
                {"work_id": work_id, "slug": "sprout", "verdict": verdict,
                 "why": f"reason for {verdict}", "values": {"speed": 2.5}}
            )
            saved = self.read_json(path)
            self.assertEqual(result["state"], state)
            self.assertEqual(saved["state"], state)
            self.assertTrue(saved["closed"])
            # The queue's own verdict path: the reason is his turn on the card's
            # conversation, tagged with the button, and the owner is asked to
            # answer it there.
            turn = saved["conversation"][-1]
            self.assertEqual((turn["role"], turn["text"]), ("daniel", f"reason for {verdict}"))
            self.assertEqual(turn["with"], "accept" if verdict == "keep" else "drop")
            self.assertTrue(saved["awaiting_reply"])
            self.assertEqual(self.replies[-1], work_id)
            self.assertEqual(saved.get("result", ""), "")
            self.assertEqual(saved["anim_verdicts"][-1]["values"], {"speed": 2.5})
            self.assertEqual(saved["anim_verdicts"][-1]["slug"], "sprout")
            self.assertTrue(saved["anim_verdicts"][-1]["at"].endswith("Z"))
            followup = self.read_json(self.data / "work" / f"{result['followup_work_id']}.json")
            self.assertEqual(followup["owner"], "ingrid")
            self.assertEqual(followup["state"], "waiting_session")
            self.assertEqual(followup["anim_verdict"], saved["anim_verdicts"][-1])
            self.assertEqual(followup["parent"], work_id)
            self.assertIn("speed", followup["ask"])
            self.assertEqual([c["id"] for c in saved["spawned"]], [followup["id"]])
            self.assertEqual(anim.work.load_item(followup["id"])["id"], followup["id"])
            if verdict == "drop":
                acted = anim.work.api_post("/api/work/approve", {"id": followup["id"]})
                self.assertEqual(acted["id"], followup["id"])
                self.assertEqual(acted["_revision"], followup["_revision"] + 1)
            self.assertIsNone(anim._INDEX_CACHE["key"])

    def test_verdict_without_exact_work_identity_has_no_side_effect(self):
        self.review()
        with mock.patch.object(anim.threading, "Thread", StoppedThread), \
                mock.patch.object(anim.execution, "run_session") as paid:
            result = anim.record_verdict(
                {"slug": "sprout", "verdict": "rework", "why": "Change the timing curve",
                 "values": {"speed": 2}}
            )
        self.assertIn("review card", result["error"])
        self.assertEqual(StoppedThread.starts, 0)
        paid.assert_not_called()

    def test_existing_run_review_can_still_receive_a_verdict(self):
        path = self.review(work_id="wr1788991284fa19")
        result = anim.record_verdict(
            {"work_id": "wr1788991284fa19", "slug": "sprout", "verdict": "drop",
             "why": "The motion obscures the crop", "values": {"speed": 2}}
        )
        self.assertEqual(result["state"], "dropped")
        self.assertEqual(self.read_json(path)["anim_verdicts"][-1]["reason"],
                         "The motion obscures the crop")

    def test_lab_verdict_and_queue_verdict_are_one_act(self):
        """A card judged in the Lab is closed for the queue too, and a legacy
        `wr` card the Lab can judge is one the queue can act on and open."""
        self.review(work_id="wr17889769879f89")
        queue = anim.work.api_post("/api/work/respond",
                                   {"id": "wr17889769879f89", "message": "Is the hop too fast?"})
        self.assertEqual(queue["conversation"][-1]["text"], "Is the hop too fast?")
        result = anim.record_verdict(
            {"work_id": "wr17889769879f89", "slug": "sprout", "verdict": "keep",
             "why": "The hop reads at game size", "values": {"speed": 1.5}})
        self.assertEqual(result["state"], "accepted")
        saved = anim.work.load_item("wr17889769879f89")
        self.assertEqual([t["text"] for t in saved["conversation"]],
                         ["Is the hop too fast?", "The hop reads at game size"])
        again = anim.record_verdict(
            {"work_id": "wr17889769879f89", "slug": "sprout", "verdict": "drop",
             "why": "Second thoughts", "values": {"speed": 1.5}})
        self.assertIn("no longer awaiting", again["error"])
        self.assertEqual(len(list((self.data / "work").iterdir())), 2)

    def test_verdict_rejects_wrong_source_state_and_slug(self):
        cases = [
            ("wa11111", "for_review", "manual", "sprout"),
            ("wa22222", "accepted", "anim_lab", "sprout"),
            ("wa33333", "for_review", "anim_lab", "other"),
        ]
        for work_id, state, source, slug in cases:
            self.review(slug=slug, work_id=work_id, state=state, source=source)
            result = anim.record_verdict(
                {"work_id": work_id, "slug": "sprout", "verdict": "keep", "why": "It reads well",
                 "values": {"speed": 2}}
            )
            self.assertIn("error", result)

    def test_rework_transitions_exact_review_before_launch(self):
        self.script()
        path = self.review()
        with mock.patch.object(anim.execution, "launch_allowed", return_value=True), \
                mock.patch.object(anim.threading, "Thread", StoppedThread), \
                mock.patch.object(anim.execution, "run_session") as paid:
            result = anim.record_verdict(
                {"work_id": "wa12345", "slug": "sprout", "verdict": "rework",
                 "why": "Slow the opening and hold the final pose", "values": {"speed": 2}}
            )
        self.assertEqual(result["state"], "doing")
        self.assertEqual(result["work_id"], "wa12345")
        self.assertEqual(self.read_json(path)["state"], "doing")
        self.assertEqual(self.read_json(path)["anim_verdicts"][-1]["values"], {"speed": 2})
        self.assertEqual(result["run"]["work_item"], "wa12345")
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
        work_id = rec["work_item"]
        self.assertRegex(work_id, r"^w[0-9a-f]{6,32}$")
        self.assertEqual(self.read_json(self.data / "work" / f"{work_id}.json")["anim_slug"],
                         "sprout")
        anim._INDEX_CACHE.update(key=None, data=None)
        self.assertEqual(anim.loops_index()["loops"][0]["work_item"], work_id)

    def rendered(self, slug="sprout"):
        out = self.repo / "tools" / "experiments" / "out" / slug
        out.mkdir(parents=True)
        (out / "params.json").write_text(json.dumps({"params": [], "values": {}}),
                                         encoding="utf-8")
        (out / f"{slug}_sheet.png").write_bytes(b"png")

    def test_hand_drawn_loop_verdict_files_its_review_card(self):
        """A loop with no Lab run behind it never had a card. Its first verdict
        files one to the art director and lands on it like any other."""
        self.rendered()
        self.assertIsNone(anim.loops_index()["loops"][0]["work_item"])
        result = anim.record_verdict(
            {"slug": "sprout", "verdict": "drop", "why": "It fights the crop for attention",
             "values": {"speed": 3}})
        self.assertTrue(result["filed"])
        card = anim.work.load_item(result["work_id"])
        self.assertEqual((card["source"], card["owner"], card["anim_slug"], card["state"]),
                         ("anim_lab", "ingrid", "sprout", "dropped"))
        self.assertEqual(card["conversation"][-1]["text"], "It fights the crop for attention")
        self.assertEqual(card["anim_verdicts"][-1]["values"], {"speed": 3})
        self.assertEqual(self.replies, [result["work_id"]])
        # Once judged, the page shows the verdict rather than filing a second card.
        again = anim.record_verdict(
            {"slug": "sprout", "verdict": "keep", "why": "Changed my mind", "values": {"speed": 3}})
        self.assertIn("already been judged", again["error"])
        missing = anim.record_verdict(
            {"slug": "nothing_here", "verdict": "keep", "why": "Fine", "values": {}})
        self.assertIn("no drawn loop", missing["error"])

    def test_page_shows_the_verdict_and_the_owners_answer_after_judging(self):
        """After a verdict the Lab shows the card's conversation — his words,
        then the owner's answer — including a verdict given on the Work page."""
        self.rendered()
        self.review(work_id="wa12345")
        self.assertEqual(anim.loops_index()["loops"][0]["work_item"], "wa12345")
        # Judged from the queue, not the Lab: the Lab must still notice.
        anim.work.api_post("/api/work/accept", {"id": "wa12345", "comment": "The hop reads"})
        loop = anim.loops_index()["loops"][0]
        self.assertIsNone(loop["work_item"])
        self.assertEqual((loop["review"]["id"], loop["review"]["verdict"], loop["review"]["reason"]),
                         ("wa12345", "keep", "The hop reads"))
        self.assertIsNone(loop["review"]["answer"])
        card = anim.work.load_item("wa12345")
        card["conversation"].append({"role": "ingrid", "text": "Landing it now.", "at": "t"})
        card["awaiting_reply"] = False
        anim.work.save_item(card)
        self.assertEqual(anim.loops_index()["loops"][0]["review"]["answer"]["text"],
                         "Landing it now.")


if __name__ == "__main__":
    unittest.main(verbosity=2)

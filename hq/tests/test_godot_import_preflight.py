#!/usr/bin/env python3
"""The build worker starts only after a clean, bounded Godot import."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain


def git(root, *args):
    return subprocess.run(["git", *args], cwd=root, check=True,
                          capture_output=True, text=True).stdout.strip()


class GodotImportPreflight(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hq-godot-import-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.name", "HQ Test")
        git(self.repo, "config", "user.email", "hq-test@example.invalid")
        (self.repo / "project.godot").write_text("config_version=5\n")
        (self.repo / "weather.gd").write_text("class_name Weather\n")
        (self.repo / "docs").mkdir()
        (self.repo / "docs/writing_verdicts.json").write_text("{}\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "Base")

    def fake_import(self, *args, **kwargs):
        self.assertEqual(kwargs["cwd"], str(self.repo))
        self.assertEqual(kwargs["timeout"], drain.GODOT_IMPORT_TIMEOUT)
        (self.repo / "weather.gd.uid").write_text("generated\n")
        (self.repo / "docs/writing_verdicts.json").write_text("changed\n")
        return subprocess.CompletedProcess(args, 0, "import complete", "")

    def test_import_cleans_generated_files_without_changing_candidate(self):
        before = git(self.repo, "write-tree")
        original = drain.sh

        def run(args, **kwargs):
            if args[0] == "godot":
                return self.fake_import(args, **kwargs)
            return original(args, **kwargs)

        with patch.object(drain, "sh", side_effect=run):
            drain.preflight_godot_import(str(self.repo))
        self.assertFalse((self.repo / "weather.gd.uid").exists())
        self.assertEqual((self.repo / "docs/writing_verdicts.json").read_text(), "{}\n")
        self.assertTrue(drain.candidate_unchanged(str(self.repo), before))

    def test_import_failure_and_unrelated_change_hold(self):
        original = drain.sh

        def failed(args, **kwargs):
            if args[0] == "godot":
                return subprocess.CompletedProcess(args, 1, "", "SCRIPT ERROR: Parse Error: bad class")
            return original(args, **kwargs)

        with patch.object(drain, "sh", side_effect=failed):
            with self.assertRaisesRegex(drain.GodotImportHold, "parse/import error"):
                drain.preflight_godot_import(str(self.repo))

        def drift(args, **kwargs):
            if args[0] == "godot":
                (self.repo / "weather.gd").write_text("unrelated mutation\n")
                return subprocess.CompletedProcess(args, 0, "", "")
            return original(args, **kwargs)

        with patch.object(drain, "sh", side_effect=drift):
            with self.assertRaisesRegex(drain.GodotImportHold, "outside known generated"):
                drain.preflight_godot_import(str(self.repo))

    def test_import_timeout_holds(self):
        original = drain.sh

        def timeout(args, **kwargs):
            if args[0] == "godot":
                raise subprocess.TimeoutExpired(args, kwargs["timeout"])
            return original(args, **kwargs)

        with patch.object(drain, "sh", side_effect=timeout):
            with self.assertRaisesRegex(drain.GodotImportHold, "TimeoutExpired"):
                drain.preflight_godot_import(str(self.repo))

    def test_only_game_builds_require_import(self):
        self.assertTrue(drain.needs_godot_import({"tier": 1, "ask": "Change systems/sim/weather.gd"}))
        self.assertFalse(drain.needs_godot_import({"tier": 0, "ask": "Review systems/sim/weather.gd"}))
        self.assertFalse(drain.needs_godot_import({"tier": 1, "ask": "Update the HQ decision card"}))

    def test_new_script_sidecar_is_in_the_candidate_and_landed_commit(self):
        base = git(self.repo, "rev-parse", "HEAD")
        (self.repo / "new_weather.gd").write_text("class_name NewWeather\n")
        original = drain.sh

        def run(args, **kwargs):
            if args[0] == "godot":
                (self.repo / "new_weather.gd.uid").write_text("uid://new-weather\n")
                return subprocess.CompletedProcess(args, 0, "import complete", "")
            return original(args, **kwargs)

        with patch.object(drain, "sh", side_effect=run):
            captured = drain.capture_added_godot_sidecars(str(self.repo), base)
        self.assertEqual(captured, ["new_weather.gd.uid"])
        candidate = git(self.repo, "write-tree")
        self.assertEqual(git(self.repo, "ls-tree", "--name-only", candidate,
                             "new_weather.gd", "new_weather.gd.uid"),
                         "new_weather.gd\nnew_weather.gd.uid")

        git(self.repo, "commit", "-qm", "Land candidate")
        self.assertEqual(git(self.repo, "ls-tree", "--name-only", "HEAD",
                             "new_weather.gd.uid"), "new_weather.gd.uid")

    def test_failed_preflight_never_launches_owner(self):
        item = {"id": "wimport", "owner": "sam", "model": "sonnet", "tier": 1,
                "title": "Weather", "ask": "Change weather.gd", "started": ""}
        org = {"employees": []}
        with patch.object(drain.execution, "launch_allowed", return_value=True), \
             patch.object(drain.execution, "resolve_model", return_value={"model": "sonnet"}), \
             patch.object(drain, "checkpoint"), patch.object(drain, "record_phase"), \
             patch.object(drain.work, "save_item"), patch.object(drain, "make_worktree", return_value=str(self.repo)), \
             patch.object(drain, "drop_worktree"), patch.object(drain, "resume_held_patch", return_value=""), \
             patch.object(drain, "resume_for_revision", return_value=(False, "")), \
             patch.object(drain, "preflight_godot_import", side_effect=drain.GodotImportHold("import failed")), \
             patch.object(drain, "run_cli") as owner:
            record = drain.do_item(item, org, "trial", lambda _msg: None)
        self.assertTrue(record["held"])
        self.assertEqual(record["error"], "import failed")
        self.assertEqual(item["started"], "")
        owner.assert_not_called()

    def test_successful_preflight_precedes_owner_and_non_game_skips_it(self):
        for ask, expected in (("Change weather.gd", True),
                              ("Update the HQ decision card", False)):
            item = {"id": "wimport", "owner": "sam", "model": "sonnet", "tier": 1,
                    "title": "Work", "ask": ask, "started": ""}
            calls = []

            def imported(_tree):
                calls.append("import")

            def owner(*_args, **_kwargs):
                calls.append("owner")
                return "", None, "HELD"

            with patch.object(drain.execution, "launch_allowed", return_value=True), \
                 patch.object(drain.execution, "resolve_model", return_value={"model": "sonnet"}), \
                 patch.object(drain, "checkpoint"), patch.object(drain, "record_phase"), \
                 patch.object(drain.work, "save_item"), patch.object(drain, "make_worktree", return_value=str(self.repo)), \
                 patch.object(drain, "drop_worktree"), patch.object(drain, "resume_held_patch", return_value=""), \
                 patch.object(drain, "resume_for_revision", return_value=(False, "")), \
                 patch.object(drain, "task_prompt", return_value="task"), \
                 patch.object(drain, "seat_prompt", return_value="seat"), \
                 patch.object(drain, "preflight_godot_import", side_effect=imported), \
                 patch.object(drain, "run_cli", side_effect=owner):
                drain.do_item(item, {"employees": []}, "trial", lambda _msg: None)
            self.assertEqual(calls, ["import", "owner"] if expected else ["owner"])


    def test_suites_import_a_checkout_that_was_never_imported(self):
        # 2026-09-26: docs-only revisions skipped the owner's import, then their
        # suites idled on an unimported worktree until the 14-minute timeout.
        calls = []
        suite = subprocess.CompletedProcess([], 0, "Results: 3 PASSED, 0 FAILED\n", "")

        def imported(tree):
            calls.append("import")
            (Path(tree) / ".godot" / "imported").mkdir(parents=True)

        def ran(args, **_kwargs):
            calls.append("suite")
            return suite

        with patch.object(drain, "preflight_godot_import", side_effect=imported), \
             patch.object(drain, "sh", side_effect=ran):
            first = drain.run_suites(cwd=str(self.repo))
            again = drain.run_suites(cwd=str(self.repo))
        self.assertEqual(calls, ["import", "suite", "suite", "suite", "suite"])
        self.assertTrue(first["unit"]["ok"] and again["integration"]["ok"])

    def test_suites_report_a_failed_import_instead_of_hanging(self):
        hold = drain.GodotImportHold("Godot import tooling hold: Godot exited 1.")
        with patch.object(drain, "preflight_godot_import", side_effect=hold), \
             patch.object(drain, "sh") as ran:
            out = drain.run_suites(cwd=str(self.repo))
        ran.assert_not_called()
        self.assertFalse(out["unit"]["ok"] or out["integration"]["ok"])
        self.assertIn("import tooling hold", out["integration"]["tail"])

if __name__ == "__main__":
    unittest.main()

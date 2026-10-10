#!/usr/bin/env python3
"""Focused process tests for unattended Godot checks."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools" / "run_godot_test.py"
GODOT = os.environ.get("GODOT", "godot")


def command(mode: str, *args: str, grace: str = "0.25") -> list[str]:
    return [
        sys.executable,
        str(RUNNER),
        "--timeout",
        "8",
        "--result-grace",
        grace,
        "--",
        GODOT,
        "--headless",
        "--path",
        str(ROOT),
        "--script",
        "res://tools/process_integrity_fixture.gd",
        "--",
        mode,
        *args,
    ]


class ProcessIntegrityTests(unittest.TestCase):
    def test_concurrent_processes_have_private_user_data(self) -> None:
        with tempfile.TemporaryDirectory(prefix="tiny-farm-rendezvous-") as rendezvous:
            children = [
                subprocess.Popen(
                    command("isolation", token, rendezvous, grace="2"),
                    cwd=ROOT,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                for token in ("first", "second")
            ]
            results = [child.communicate(timeout=10) for child in children]
        self.assertEqual(
            [child.returncode for child in children],
            [0, 0],
            "\n".join(output for output, _ in results),
        )

    def test_green_result_fails_if_godot_does_not_exit(self) -> None:
        started = time.monotonic()
        result = subprocess.run(
            command("green_hang"), cwd=ROOT, capture_output=True, text=True, timeout=5
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertLess(time.monotonic() - started, 3)
        self.assertIn("did not exit", result.stdout + result.stderr)

    def test_status_result_fails_if_godot_does_not_exit(self) -> None:
        result = subprocess.run(
            command("status_green_hang"), cwd=ROOT, capture_output=True, text=True, timeout=5
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("did not exit", result.stdout + result.stderr)

    def test_failed_status_is_nonzero(self) -> None:
        result = subprocess.run(
            command("status_failure"), cwd=ROOT, capture_output=True, text=True, timeout=5
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_known_timing_failure_is_nonzero_and_prompt(self) -> None:
        started = time.monotonic()
        result = subprocess.run(
            command("timing_failure"), cwd=ROOT, capture_output=True, text=True, timeout=5
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertLess(time.monotonic() - started, 3)

    def test_every_frame_is_the_same_length_of_game_time(self) -> None:
        result = subprocess.run(
            command("frame_step"), cwd=ROOT, capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_command_keeps_its_own_frame_step(self) -> None:
        sys.path.insert(0, str(RUNNER.parent))
        import run_godot_test

        mine = ["godot", "--fixed-fps", "20", "--path", "."]
        self.assertEqual(run_godot_test.with_fixed_frame_step(mine), mine)
        self.assertEqual(
            run_godot_test.with_fixed_frame_step(["godot", "--path", ".", "--", "--seed=3"]),
            ["godot", "--fixed-fps", "60", "--path", ".", "--", "--seed=3"],
        )
        self.assertEqual(
            run_godot_test.with_fixed_frame_step(
                ["/opt/godot/Godot_v4.7.2-stable_linux.x86_64", "--path", "."]),
            ["/opt/godot/Godot_v4.7.2-stable_linux.x86_64", "--fixed-fps", "60", "--path", "."],
        )
        python = [sys.executable, "-c", "print('Results: PASSED')"]
        self.assertEqual(run_godot_test.with_fixed_frame_step(python), python)

    def test_script_error_overrules_green_partial_count(self) -> None:
        result = subprocess.run(
            command("script_error_green"), cwd=ROOT, capture_output=True, text=True, timeout=5
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SCRIPT ERROR:", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)

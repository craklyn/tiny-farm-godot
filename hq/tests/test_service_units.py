#!/usr/bin/env python3
"""The two replacement services must target one code and data authority."""

from pathlib import Path
import unittest


UNITS = Path(__file__).resolve().parents[1] / "systemd"
ROOT = "/home/daniel/dev/tiny-farm-godot-main"
DATA = "/home/daniel/tiny-farm-hq-data"  # HQ's own store since Q-125 (a)
USER = "/home/daniel/dev/tiny-farm-godot"


def entries(path):
    rows = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line and not line.startswith(("#", "[")):
            key, value = line.split("=", 1)
            rows.setdefault(key, []).append(value)
    return rows


class ServiceUnits(unittest.TestCase):
    def test_replacements_share_explicit_roots_and_not_canary_paths(self):
        hq = entries(UNITS / "convergence/tiny-farm-hq.service")
        drain = entries(UNITS / "convergence/tiny-farm-drain.service")
        expected = {"HQ_REQUIRE_EXPLICIT_ROOTS": "1", "HQ_DATA_ROOT": DATA,
                    "HQ_USER_WORKSPACE_ROOT": USER, "HQ_MAIN_ROOT": ROOT}
        for unit, command in ((hq, "server.py"), (drain, "drain.py --unattended")):
            self.assertEqual(unit["WorkingDirectory"], [ROOT])
            env = dict(row.split("=", 1) for row in unit["Environment"])
            for key, value in expected.items():
                self.assertEqual(env[key], value)
            self.assertNotIn("HQ_CANARY_MODE", env)
            self.assertNotIn("HQ_TEST_SCRATCH", env)
            self.assertEqual(unit["ExecStart"],
                             [f"/usr/bin/python3 {ROOT}/hq/{command}"])
        self.assertIn("Restart", hq)
        self.assertEqual(drain["Type"], ["oneshot"])
        self.assertNotIn("/tmp/", (UNITS / "convergence/tiny-farm-hq.service").read_text())
        self.assertNotIn("/tmp/", (UNITS / "convergence/tiny-farm-drain.service").read_text())

    def test_existing_timer_keeps_the_drain_unit_name(self):
        timer = entries(UNITS / "tiny-farm-drain.timer")
        self.assertEqual(timer["Unit"], ["tiny-farm-drain.service"])


if __name__ == "__main__":
    unittest.main()

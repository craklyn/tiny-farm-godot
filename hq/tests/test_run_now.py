#!/usr/bin/env python3
"""The task queue's "Start now" and the scheduler reading behind its status.

Daniel, 2026-09-29: telling a queue that is waiting for its next run from one
that is stuck meant comparing timestamps. The controls now say when the next
run starts, whether one is running, and whether "Start now" would begin anything.
No systemctl runs here: every call to it is stubbed.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("HQ_TEST_SCRATCH", tempfile.mkdtemp(prefix="hq-run-now-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server  # noqa: E402

NEXT, LAST = 1790695261, 1790694661   # 08:21:01 and 08:11:01 on 2026-09-29, PDT


def systemctl(timer_state="active\nwaiting\n", service_state="inactive\n\n", listed=None, start_code=0):
    calls = []
    rows = listed if listed is not None else [{"next": NEXT * 1_000_000, "last": LAST * 1_000_000,
                                               "unit": "tiny-farm-drain.timer"}]

    def run(argv, **kwargs):
        calls.append(argv)
        if "list-timers" in argv:
            out = json.dumps(rows)
        elif "start" in argv:
            return subprocess.CompletedProcess(argv, start_code, "", "refused" if start_code else "")
        elif server.DRAIN_TIMER in argv:
            out = timer_state
        else:
            out = service_state
        return subprocess.CompletedProcess(argv, 0, out, "")
    return run, calls


def eligible(*types):
    return {"working": [], "held": [], "eligible": [{"action_type": t} for t in types]}


class RunNow(unittest.TestCase):
    def setUp(self):
        self.policy = {"background_paused": False, "background_pause": {}, "mode": "codex", "mappings": {}}
        stubs = [
            patch.object(server.execution, "load_policy", lambda: dict(self.policy)),
            patch.object(server, "drain_state", lambda: None),
            patch.object(server, "_provider_dry_until", lambda provider: ""),
        ]
        for stub in stubs:
            stub.start()
            self.addCleanup(stub.stop)

    def snapshot(self, queue, **systemd):
        run, calls = systemctl(**systemd)
        with patch.object(server, "execution_queue_snapshot", lambda: queue), \
                patch.object(server.subprocess, "run", run):
            return server.execution_control_snapshot(), calls

    def test_the_status_knows_when_the_next_run_starts(self):
        got, _ = self.snapshot(eligible("build"))
        self.assertEqual(got["timer"]["next_at"], server._iso_local(NEXT))
        self.assertEqual(got["timer"]["last_at"], server._iso_local(LAST))
        self.assertEqual(got["interval_minutes"], 10)
        self.assertFalse(got["service"]["running"])
        self.assertEqual(got["run_now"], {"allowed": True, "why": ""})

    def test_run_now_starts_the_timers_own_service(self):
        run, calls = systemctl()
        with patch.object(server, "execution_queue_snapshot", lambda: eligible("build")), \
                patch.object(server.subprocess, "run", run):
            status, body = server.request_run_now()
        self.assertEqual(status, 200)
        self.assertTrue(body["started"])
        self.assertIn(["systemctl", "--user", "start", "--no-block", "tiny-farm-drain.service"], calls)

    def test_steps_only_a_session_can_take_do_not_count(self):
        # 2026-09-29: three handoff steps sat "waiting to start" while every run
        # said "Nothing queued"; a button counting them would start nothing.
        import integration
        with patch.object(integration, "handoff_status", return_value=(False, "main is held")):
            got, _ = self.snapshot(eligible("handoff", "handoff", "handoff"))
        self.assertEqual((got["queued"], got["startable"]), (3, 0))
        self.assertFalse(got["run_now"]["allowed"])
        self.assertIn("for the chief of staff", got["run_now"]["why"])
        # Once main can take landings, a run clears them and works the cards.
        with patch.object(integration, "handoff_status", return_value=(True, "")):
            got, _ = self.snapshot(eligible("handoff", "handoff", "handoff"))
        self.assertEqual((got["queued"], got["startable"]), (3, 3))
        self.assertTrue(got["run_now"]["allowed"])

    def test_it_refuses_with_a_reason_and_never_starts_a_second_run(self):
        run, calls = systemctl(service_state="activating\n@1790694661\n")
        with patch.object(server, "execution_queue_snapshot", lambda: eligible("build")), \
                patch.object(server.subprocess, "run", run):
            status, body = server.request_run_now()
        self.assertEqual(status, 409)
        self.assertEqual(body["error"], "The task queue is already working.")
        self.assertTrue(body["service"]["running"])
        self.assertEqual(body["service"]["since"], server._iso_local(1790694661))
        self.assertFalse(any("start" in argv for argv in calls))

    def test_paused_and_dry_windows_say_so(self):
        self.policy["background_paused"] = True
        got, _ = self.snapshot(eligible("build"))
        self.assertIn("paused", got["run_now"]["why"])
        self.policy["background_paused"] = False
        with patch.object(server, "_provider_dry_until", lambda provider: "2026-09-29T04:45:00"):
            got, _ = self.snapshot(eligible("build"))
        self.assertFalse(got["run_now"]["allowed"])
        self.assertIn("until 04:45", got["run_now"]["why"])

    def test_an_unreadable_scheduler_is_not_mistaken_for_a_schedule(self):
        got, _ = self.snapshot(eligible("build"), listed=[])
        self.assertEqual((got["timer"]["next_at"], got["timer"]["interval_minutes"]), ("", None))
        self.assertEqual(got["interval_minutes"], 10)


if __name__ == "__main__":
    unittest.main()

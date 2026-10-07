#!/usr/bin/env python3
"""The task queue lists a card HQ's own worker is running, as the bullpen does.

2026-10-07: Milo's barn card was being worked by HQ's worker (state "doing");
the bullpen showed his session while the task queue said nothing was being
worked, because the queue only read cards waiting for the drain.

    python3 hq/tests/test_queue_shows_hq_worker.py
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain  # noqa: E402
import server  # noqa: E402
import work  # noqa: E402
from test_drain import fake_host  # noqa: E402
from test_prerequisites import ORG  # noqa: E402

CARD = "w57cc64dbba8"


class QueueShowsHqWorker(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        repo = root / "repo"
        repo.mkdir()
        for args in (("init", "-q", "-b", "main"), ("config", "user.name", "Fixture"),
                     ("config", "user.email", "fixture@example.invalid"),
                     ("commit", "-q", "--allow-empty", "-m", "base")):
            subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)
        host = fake_host(str(root / "data"))
        host.load_json = lambda path: json.loads(Path(path).read_text())
        host.load_org = lambda: ORG
        work.bind(host, sanitize=False)
        work.save_item({"id": CARD, "title": "Propose the industrial barn", "owner": "milo",
                        "level": "story", "tier": 0, "state": "doing", "ask": "Propose it.",
                        "first_action": "Read the rules.", "created": "2026-10-07T12:25:07-07:00",
                        "created_ts": 1, "attempts": 0, "started": ""})
        self.patch = patch.object(drain, "REPO", str(repo))
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def rows(self, live):
        with patch.object(server, "drain_state", return_value=live):
            view = drain.queue_view()
        return {lane: [row["work_id"] for row in rows] for lane, rows in view.items()}

    def test_running_card_is_listed_as_worked_now(self):
        live = {"run": "reading-test", "pid": os.getpid(), "phase": "worker",
                "items": [{"item": CARD, "phase": "worker"}]}
        self.assertEqual(self.rows(live), {"working": [CARD], "eligible": [], "held": []})

    def test_unstarted_card_is_not_given_a_place_in_line(self):
        self.assertEqual(self.rows(None), {"working": [], "eligible": [], "held": []})


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""The restart cleanup leaves alone a card that a live process is working.

2026-10-07: every drain process binds with the cleanup, including the recovery
run HQ starts each minute. It cleared the start mark of Milo's barn card while
HQ's own worker was running it, so that run's result conflicted, was dropped,
and the card started over about every ninety seconds without counting an
attempt.

    python3 hq/tests/test_sanitize_spares_live_run.py
"""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server  # noqa: E402
import work  # noqa: E402
from test_drain import fake_host  # noqa: E402
from test_prerequisites import ORG  # noqa: E402

LIVE, ORPHAN = "w57cc64dbba8", "w000000000aa"


class SanitizeSparesLiveRun(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.host = fake_host(str(Path(self.tmp.name) / "data"))
        self.host.load_json = lambda path: json.loads(Path(path).read_text())
        self.host.load_org = lambda: ORG
        self.host.drain_entry = server.drain_entry
        self.host.drain_state = lambda: {"run": "reading-test", "pid": os.getpid(), "phase": "worker",
                                         "items": [{"item": LIVE, "phase": "worker"}]}
        work.bind(self.host, sanitize=False)
        for ident in (LIVE, ORPHAN):
            work.save_item({"id": ident, "title": ident, "owner": "milo", "level": "story", "tier": 0,
                            "state": "doing", "ask": "a", "first_action": "a", "created_ts": 1,
                            "attempts": 0, "started": "2026-10-07T12:41:50-07:00"})

    def tearDown(self):
        self.tmp.cleanup()

    def test_live_card_keeps_its_start_and_orphan_is_reset(self):
        before = work.load_item(LIVE)["_revision"]
        work.bind(self.host, sanitize=True)
        live = work.load_item(LIVE)
        self.assertTrue(live["started"])
        self.assertEqual(live["_revision"], before)
        self.assertEqual(work.load_item(ORPHAN)["started"], "")


if __name__ == "__main__":
    unittest.main()

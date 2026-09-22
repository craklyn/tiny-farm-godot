#!/usr/bin/env python3
"""A failed main build becomes one urgent Engineering repair."""
import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import server  # noqa: E402
import work  # noqa: E402


def main():
    failures = []

    def check(value, label):
        print(("ok   " if value else "FAIL ") + label)
        if not value:
            failures.append(label)

    with tempfile.TemporaryDirectory() as td:
        data = Path(td) / "data"
        (data / "work").mkdir(parents=True)
        org = {"employees": [{"id": "elena"}, {"id": "ravi"}]}
        old_data, old_history = server.DATA, server.CI_HISTORY_PATH
        old_host, old_work = work.HOST, work.WORK
        server.DATA = str(data)
        server.CI_HISTORY_PATH = str(data / "ci_history.json")
        work.WORK = str(data / "work")
        work.HOST = type("Host", (), {
            "load_org": staticmethod(lambda: org),
            "load_json": staticmethod(lambda p: json.loads(Path(p).read_text())),
        })()
        runs = [{
            "status": "completed", "conclusion": "failure",
            "displayTitle": "A broken push", "updatedAt": "2026-09-21T20:00:00Z",
            "url": "https://github.example/runs/42",
        }]
        try:
            with patch.object(server, "run_cmd", return_value=json.dumps(runs)):
                server._refresh_ci_history()
                server._refresh_ci_history()
            cards = work.items()
            check(len(cards) == 1, "polling one failed run twice files one card")
            check(cards[0]["owner"] == "elena", "the VP of Engineering owns the repair")
            check(cards[0]["urgent"] and cards[0]["state"] == "waiting_session",
                  "the repair is urgent and ready for an unattended worker")
            check(cards[0]["source_ref"] == "ci:https://github.example/runs/42",
                  "the card records which failed run created it")
            cards[0]["state"] = "landed"
            work.save_item(cards[0])
            with patch.object(server, "run_cmd", return_value=json.dumps(runs)):
                server._refresh_ci_history()
            closed = work.items()
            check(len(closed) == 1 and closed[0]["state"] == "landed",
                  "polling the old failure while its replacement run finishes does not reopen it")
        finally:
            server.DATA, server.CI_HISTORY_PATH = old_data, old_history
            work.HOST, work.WORK = old_host, old_work

    if failures:
        raise SystemExit(1)
    print("\nall green.")


if __name__ == "__main__":
    main()

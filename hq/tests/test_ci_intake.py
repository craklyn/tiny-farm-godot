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
            print("an in-progress push does not steal the failed run's identity")
            in_progress = [{**runs[0], "status": "in_progress", "conclusion": "",
                            "url": "https://github.example/runs/43"}, runs[0]]
            with patch.object(server, "run_cmd", return_value=json.dumps(in_progress)):
                reading = server.eval_measure({"kind": "ci_state"})
            check(reading["value"] == "failure" and reading["url"].endswith("/42"),
                  "the verdict and link both name the newest finished run")

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

            print("a later failure cannot rewrite work already in flight")
            closed[0]["state"] = "waiting_session"
            closed[0]["started"] = "2026-09-21T20:01"
            closed[0]["attempts"] = 1
            work.save_item(closed[0])
            newer = [{**runs[0], "url": "https://github.example/runs/43",
                      "displayTitle": "A later broken push"}]
            with patch.object(server, "run_cmd", return_value=json.dumps(newer)):
                server._refresh_ci_history()
            cards = work.items()
            check(len(cards) == 2, "a later failed run gets its own incident")
            check({c["source_ref"] for c in cards} == {
                      "ci:https://github.example/runs/42",
                      "ci:https://github.example/runs/43"},
                  "the active brief keeps the run it was created to repair")

            print("a stale page from GitHub files nothing and keeps the history")
            # 2026-09-28: GitHub three times answered with runs ending 18 days
            # earlier; each old failure became a repair card that cost 1-2M tokens.
            before = json.loads(Path(server.CI_HISTORY_PATH).read_text())
            stale = [{**runs[0], "updatedAt": "2026-09-10T05:00:00Z",
                      "url": "https://github.example/runs/10", "displayTitle": "An old broken push"}]
            with patch.object(server, "run_cmd", return_value=json.dumps(stale)):
                server._refresh_ci_history()
            check(len(work.items()) == 2 and not any(c["source_ref"].endswith("/10") for c in work.items()),
                  "an answer older than what HQ already recorded files no repair")
            check(json.loads(Path(server.CI_HISTORY_PATH).read_text()) == before,
                  "and does not overwrite the recorded history")

            print("a filed repair makes the failing goal Engineering's move")
            old_eval, old_escalation = server.eval_measure, server._escalation
            old_route, old_sessions, old_drain = server._route_target, server.worker_sessions, server.drain_state
            try:
                server.eval_measure = lambda _spec: {
                    "value": "failure", "url": "https://github.example/runs/43",
                    "source_human": "the newest finished tests workflow on main"}
                server._escalation = lambda _goal, _state, _reading: None
                server.worker_sessions = lambda: []
                server.drain_state = lambda: None
                goal = server.eval_goal({
                    "id": "build-branch-builds-green", "statement": "Builds pass",
                    "owner": "vp-engineering", "severity": "blocking",
                    "measure": {"kind": "ci_state"},
                    "compare": {"direction": "in_set", "green_set": ["success"]},
                    "path_to_green": {"action": {"label": "File it"}},
                })
                check(goal["state"] == "amber" and goal["ours"] and not goal["needs_you"],
                      "a queued repair is failing but belongs to Engineering")
                latest = next(c for c in cards if c["source_ref"].endswith("/43"))
                check(goal["path_to_green"]["route"] == {"kind": "work", "id": latest["id"]},
                      "the goal links to the existing repair instead of offering to file another")
            finally:
                server.eval_measure, server._escalation = old_eval, old_escalation
                server._route_target, server.worker_sessions, server.drain_state = old_route, old_sessions, old_drain

            print("a green interval resets the age of a later failure")
            old_read = server.read_history
            try:
                server._GOAL_JOURNAL = {"at": 0.0, "by_id": {}}
                server.read_history = lambda _name, _limit: [
                    {"at": "2026-09-05T10:00:00", "states": {"build": "red"}},
                    {"at": "2026-09-06T10:00:00", "states": {}},
                    {"at": "2026-09-21T23:00:00", "states": {"build": "red"}},
                ]
                check(server._goal_journal()["build"]["since"] == "2026-09-21T23:00:00",
                      "the new incident starts when red returned, not at the old failure")
            finally:
                server.read_history = old_read
                server._GOAL_JOURNAL = {"at": 0.0, "by_id": {}}

            print("a repair still open when main passes again is dropped, naming the green run")
            fresh = Path(td) / "fresh"
            (fresh / "work").mkdir(parents=True)
            work.WORK = str(fresh / "work")
            server.CI_HISTORY_PATH = str(fresh / "ci_history.json")
            red = [{**runs[0], "url": "https://github.example/runs/50", "updatedAt": "2026-10-09T22:46:00Z"}]
            log = "tests\tUNKNOWN STEP\t2026-10-09T22:49:45Z   \u2717 FAIL: choosing an item recorded nothing\n"
            with patch.object(server, "run_cmd", side_effect=[json.dumps(red), log]):
                server._refresh_ci_history()
            filed = [c for c in work.items() if (c.get("incident") or {}).get("kind") == "ci_failure"]
            check(len(filed) == 1 and "choosing an item recorded nothing" in filed[0]["ask"],
                  "the repair card names the failing check, not only a link workers cannot open")
            green = [{**runs[0], "conclusion": "success", "url": "https://github.example/runs/51",
                      "updatedAt": "2026-10-09T22:56:00Z", "displayTitle": "The next push"}] + red
            with patch.object(server, "run_cmd", return_value=json.dumps(green)):
                server._refresh_ci_history()
            after = work.load_item(filed[0]["id"])
            check(after["state"] == "dropped" and "/runs/51" in after["drop_reason"]["reason"],
                  "a later green run on main drops the open repair and says which run passed")
        finally:
            server.DATA, server.CI_HISTORY_PATH = old_data, old_history
            work.HOST, work.WORK = old_host, old_work

    if failures:
        raise SystemExit(1)
    print("\nall green.")


if __name__ == "__main__":
    main()

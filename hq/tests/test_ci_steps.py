#!/usr/bin/env python3
"""A goal can read named steps of CI's newest run on main, not only its verdict.

"Games deterministically replayable" read four rules and never whether a game
replayed (2026-10-09). The `ci_steps` measure reads the replay steps themselves,
polled off the request path like the CI history strip.
"""
import json
import os
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import server  # noqa: E402

ROBOT = "Robot session (end-to-end)"
MANY = "Many generated games replay exactly"
SPEC = {"kind": "ci_steps", "job": "tests",
        "steps": [{"name": ROBOT, "proves": "played a fresh game and its replay matched"}]}


def run(rid, conclusion, steps):
    return {"databaseId": rid, "status": "completed", "conclusion": conclusion,
            "displayTitle": f"push {rid}", "updatedAt": f"2026-10-09T2{rid % 10}:00:00Z",
            "url": f"https://github.example/runs/{rid}", "_steps": steps}


def fake_gh(runs, calls):
    """run_cmd standing in for gh: the run list, and each run's jobs."""
    def answer(args, timeout=10, cwd=None):
        calls.append(args)
        if args[:3] == ["gh", "run", "list"]:
            return json.dumps([{k: v for k, v in r.items() if k != "_steps"} for r in runs])
        if args[:3] == ["gh", "run", "view"]:
            r = next(r for r in runs if str(r["databaseId"]) == args[3])
            return json.dumps({"jobs": [{"name": "tests", "steps": [
                {"name": n, "conclusion": c} for n, c in r["_steps"].items()]}]})
        return ""
    return answer


def main():
    failures = []

    def check(value, label):
        print(("ok   " if value else "FAIL ") + label)
        if not value:
            failures.append(label)

    with tempfile.TemporaryDirectory() as td:
        old = server.CI_STEPS_PATH
        server.CI_STEPS_PATH = str(Path(td) / "ci_steps.json")
        try:
            print("GitHub never reached")
            with patch.object(server, "run_cmd", return_value=""):
                server._refresh_ci_steps()
            r = server.eval_measure(SPEC)
            check(r["value"] is None and "GitHub" in (r["error"] or ""),
                  "with nothing polled the reading is an error naming GitHub, not a pass")
            check(server._state_from(r, {"direction": "must_be_true"}) != "green",
                  "and the goal cannot read green on it")

            print("the newest run passed its replay step")
            calls = []
            runs = [run(3, "success", {"Unit tests": "success", ROBOT: "success"}),
                    run(2, "failure", {"Unit tests": "failure", ROBOT: "skipped"})]
            with patch.object(server, "run_cmd", side_effect=fake_gh(runs, calls)):
                server._refresh_ci_steps()
            r = server.eval_measure(SPEC)
            check(r["value"] is True and not r["stale"], "a passed replay step reads true and fresh")
            check(r["source_human"] == "the newest finished run on main played a fresh game "
                                       "and its replay matched", "in plain words")
            check(r["url"].endswith("/3"), "linked to the run it read")
            check(server._state_from(r, {"direction": "must_be_true"}) == "green", "the member is green")

            print("a finished run's steps are fetched once")
            calls.clear()
            with patch.object(server, "run_cmd", side_effect=fake_gh(runs, calls)):
                server._refresh_ci_steps()
            check(not [c for c in calls if c[:3] == ["gh", "run", "view"]],
                  "a second poll asks GitHub only for the run list")

            print("a run that stopped before the replay step is passed over")
            runs = [run(4, "failure", {"Unit tests": "failure", ROBOT: "skipped"})] + runs
            with patch.object(server, "run_cmd", side_effect=fake_gh(runs, calls)):
                server._refresh_ci_steps()
            r = server.eval_measure(SPEC)
            check(r["value"] is True and r["url"].endswith("/3"),
                  "the reading comes from the newest run that reached the step")
            check("newest run on main to get that far" in r["source_human"],
                  "and says it is not the newest run")

            print("a failed replay step")
            runs = [run(5, "failure", {"Unit tests": "success", ROBOT: "failure"})] + runs
            with patch.object(server, "run_cmd", side_effect=fake_gh(runs, calls)):
                server._refresh_ci_steps()
            r = server.eval_measure(SPEC)
            check(r["value"] is False and ROBOT in r["source_human"],
                  "reads false and names the step that failed")
            check(server._state_from(r, {"direction": "must_be_true"}) == "red", "the member is red")

            print("a step the newest run does not have")
            two = {**SPEC, "steps": SPEC["steps"] + [MANY]}
            r = server.eval_measure(two)
            check(r["value"] is None and MANY in (r["error"] or ""),
                  "a step named in the goal but missing from CI is an error, not a pass")
            runs = [run(6, "success", {ROBOT: "success", MANY: "success"})] + runs
            with patch.object(server, "run_cmd", side_effect=fake_gh(runs, calls)):
                server._refresh_ci_steps()
            r = server.eval_measure(two)
            check(r["value"] is True and "and passed" in r["source_human"],
                  "once CI has the step, adding its name to the goal is all it takes")

            print("GitHub unreachable after a good poll")
            before = Path(server.CI_STEPS_PATH).read_text()
            with patch.object(server, "run_cmd", return_value=""):
                server._refresh_ci_steps()
            check(Path(server.CI_STEPS_PATH).read_text() == before,
                  "a failed poll keeps the last known results")
            doc = json.loads(before)
            doc["polled_at"] = time.strftime("%Y-%m-%dT%H:%M:%S",
                                             time.localtime(time.time() - server.CI_HISTORY_TTL * 4))
            Path(server.CI_STEPS_PATH).write_text(json.dumps(doc))
            r = server.eval_measure(SPEC)
            check(r["value"] is True and r["stale"], "an old poll is still shown, marked stale")
            check(server._state_from(r, {"direction": "must_be_true"}) == "red",
                  "and a stale pass is not a green")

            print("no step named")
            r = server.eval_measure({"kind": "ci_steps"})
            check(r["error"], "a measure with no steps is an error")

            print("a session puts the measure on a goal through HQ's goal endpoint")
            goals = Path(td) / "goals"
            goals.mkdir()
            goal = {"id": "replays", "statement": "Games replay", "owner": "vp-engineering",
                    "severity": "blocking", "why_it_matters": "training data",
                    "measure": {"kind": "unchecked"}}
            (goals / "engineering.json").write_text(json.dumps({"goals": [goal]}))
            base = {"area": "engineering", "id": "replays", "statement": "Games replay",
                    "owner": "vp-engineering", "severity": "blocking",
                    "why_it_matters": "training data"}
            with patch.object(server, "GOALS_DIR", str(goals)), \
                    patch.object(server, "load_seats", return_value=[{"id": "vp-engineering"}]):
                bad = server.save_goal({**base, "measure": {"kind": "composite", "op": "all_of",
                                                             "members": [{"kind": "ci_stepz"}]}})
                check("no such measurement kind" in (bad.get("error") or ""),
                      "a member HQ cannot evaluate is refused")
                composite = {"kind": "composite", "op": "all_of", "members": [SPEC]}
                ok = server.save_goal({**base, "measure": composite})
                saved = json.loads((goals / "engineering.json").read_text())["goals"][0]
                check(ok.get("ok") and saved["measure"] == composite, "a valid measure is saved")
                server.save_goal(base)
                saved = json.loads((goals / "engineering.json").read_text())["goals"][0]
                check(saved["measure"] == composite, "a save without a measure keeps the one it had")
        finally:
            server.CI_STEPS_PATH = old

    if failures:
        print(f"\n{len(failures)} failed")
        sys.exit(1)
    print("\nall passed")


if __name__ == "__main__":
    main()

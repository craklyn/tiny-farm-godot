#!/usr/bin/env python3
"""What a second attempt at a work item is told about the first one.

A worker that runs out of turns is picked up again later. Its files come with
it — the held patch is applied into the new worktree — but until now what it
did and what it concluded did not, so the second attempt planned the item again
from nothing and the studio paid twice for the same reading.

Every session is written down as it runs, so these tests pin the part of that
record the retry is given: the newest session that actually did something, the
last of its lines, the last thing it said, and a block small enough not to
crowd out the item itself.

    python3 hq/tests/test_drain_resume.py
"""
import json
import os
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
HQ = os.path.dirname(HERE)
sys.path.insert(0, HQ)

import drain  # noqa: E402


FAILS = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)


def ev_said(text):
    return {"type": "assistant", "message": {"id": "m" + str(time.time()),
            "content": [{"type": "text", "text": text}]}}


def ev_tool(name, inp):
    return {"type": "assistant", "message": {"id": "t" + str(time.time()),
            "content": [{"type": "tool_use", "name": name, "input": inp}]}}


def ev_result_text(body):
    return {"type": "user", "message": {"content":
            [{"type": "tool_result", "content": body}]}}


def write_session(root, run, item_id, events, error="", when=None):
    """One recorded session: the event stream and the record beside it."""
    d = os.path.join(root, run)
    os.makedirs(d, exist_ok=True)
    stem = os.path.join(d, f"{item_id}-drain-work")
    with open(stem + ".jsonl", "w", encoding="utf-8") as f:
        for ev in events:
            f.write(json.dumps(ev) + "\n")
    with open(stem + ".json", "w", encoding="utf-8") as f:
        json.dump({"item": item_id, "error": error}, f)
    if when is not None:
        os.utime(stem + ".jsonl", (when, when))
    return stem + ".jsonl"


def main():
    tmp = tempfile.mkdtemp(prefix="drain-resume-")
    real_workers, real_run = drain.WORKERS, drain.RUN_ID
    drain.WORKERS = tmp
    try:
        item = {"id": "w111", "title": "A title", "ask": "An ask",
                "first_action": "A first action"}

        print("an item nobody has attempted yet gets no record")
        check(drain.prior_session(item) == "", "no sessions, no block")

        print("the attempt that did something is the one carried forward")
        worked = [ev_said("I'll start by reading the brain."),
                  ev_tool("Read", {"file_path": os.path.join(
                      drain.WORKTREES, "20260101-aaa", "w111",
                      "systems/sim/brains/crow_brain.gd")}),
                  ev_result_text("func raid(): pass"),
                  ev_tool("Bash", {"command": "godot --headless --path . --script "
                                   "res://tests/test_runner.gd"}),
                  ev_tool("Edit", {"file_path": "systems/sim/brains/crow_brain.gd",
                                   "old_string": "a", "new_string": "b"}),
                  ev_said("Halfway: the brain is edited, the tests are not written yet.")]
        base = time.time() - 4000
        write_session(tmp, "20260101-aaa", "w111", worked,
                      error="it used all 60 of its turns", when=base)
        # Eleven refusals at the usage ceiling, each newer than the real attempt.
        for i in range(11):
            write_session(tmp, f"20260102-{i:03d}", "w111",
                          [ev_said("You've hit your session limit")],
                          error="LIMITED", when=base + 100 + i)
        block = drain.prior_session(item)
        check("crow_brain.gd" in block and "Halfway" in block,
              "the thirteen-minute attempt is read, not the ceiling stubs on top of it")
        check("it used all 60 of its turns" in block,
              "the brief says why that attempt stopped")
        check(block.strip().endswith(
            "Halfway: the brain is edited, the tests are not written yet."),
            "the last thing it said closes the block, in full")
        check("this is that attempt's own record" in block,
              "the brief says whose record this is")
        check("func raid(): pass" not in block,
              "tool output is left out — the line naming the call is the record")
        check(drain.WORKTREES not in block and "20260101-aaa/w111" not in block,
              "the dead worktree's paths are taken out")
        check("res://tests/test_runner.gd" in block, "what it ran is kept")

        print("the session running now is not read back to itself")
        drain._set_run("20260103-live")
        write_session(tmp, "20260103-live", "w111",
                      [ev_said("Reading the item."), ev_tool("Read", {"file_path": "x.gd"}),
                       ev_tool("Read", {"file_path": "y.gd"}),
                       ev_said("A live line nobody should be handed.")],
                      when=base + 500)
        block = drain.prior_session(item)
        check("A live line nobody should be handed" not in block and "Halfway" in block,
              "the current run is skipped and the previous attempt is still found")

        print("the retry's prompt carries it")
        org = {"employees": [{"id": "tomas", "name": "T", "title": "Engineer", "level": "L6",
                              "team": "Engineering", "responsibilities": [], "persona": ""}]}
        prompt = drain.task_prompt({"id": "w111", "title": "A title", "ask": "An ask",
                                    "first_action": "A first action", "owner": "tomas"}, org)
        check("WHAT YOUR EARLIER ATTEMPT DID" in prompt and "Halfway" in prompt,
              "the worker's brief contains the earlier attempt's record")
        check(prompt.index("What Daniel asked for") < prompt.index("WHAT YOUR EARLIER ATTEMPT"),
              "the item is still the first thing in the brief")
        drain._set_run("")

        print("a long session is cut to fit")
        big = [ev_tool("Bash", {"command": "echo " + "x" * 500}) for _ in range(200)]
        big.append(ev_said("A final word. " * 900))
        write_session(tmp, "20260104-big", "w222", big, when=base + 600)
        block = drain.prior_session({"id": "w222"})
        check(len(block) <= drain.RESUME_CHARS,
              f"the block fits the cap ({len(block)} characters)")
        check(block.count("\n  Ran: echo") >= 4,
              "a long last word still leaves room for what it did")
        check("A final word. A final word." in block, "the last word is there, cut to fit")
    finally:
        drain.WORKERS, drain.RUN_ID = real_workers, real_run
        shutil.rmtree(tmp, ignore_errors=True)

    if FAILS:
        print(f"\n{len(FAILS)} failed.")
        return 1
    print("\nall green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

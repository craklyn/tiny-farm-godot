#!/usr/bin/env python3
"""What the drain does with a worker that ran out of turns, without a model or
a worktree in the loop.

Running short of turns is a budget the drain set wrong, not a call for Daniel.
So an attempt that used every turn and left edits behind goes back into the
queue — its patch as the next attempt's base, twice the turns — and reaches
him only when the drain has given up: after its share of attempts, or when an
attempt ran out having changed nothing. These tests pin that at the card's
JSON, where it is cheapest to check.

    python3 hq/tests/test_drain.py
"""
import json
import os
import shutil
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
HQ = os.path.dirname(HERE)
sys.path.insert(0, HQ)

import drain  # noqa: E402
import work  # noqa: E402


ORG = {"employees": [
    {"id": "daniel", "name": "Daniel", "title": "CEO", "level": "L10", "team": "HQ",
     "responsibilities": ["everything"], "persona": ""},
    {"id": "claude", "name": "Claude", "title": "Chief of staff", "level": "L7", "team": "HQ",
     "responsibilities": ["filing work"], "persona": ""},
    {"id": "sam", "name": "Sam Ortega", "title": "Engineer", "level": "L5", "team": "Engineering",
     "responsibilities": ["the boot"], "persona": ""},
]}

FAILS = []


def check(cond, what):
    print(("  ok      " if cond else "  FAILED  ") + what)
    if not cond:
        FAILS.append(what)


def fake_host(data_dir):
    host = types.SimpleNamespace()
    host.DATA = data_dir
    host.REPO = data_dir
    host.load_json = lambda p: json.load(open(p, encoding="utf-8"))
    host.load_org = lambda: ORG
    host.seat_model = lambda org, who, override=None: ""
    return host


def card(**over):
    base = {
        "id": "w0123456789ab", "title": "The sprite editor opens the whole sheet",
        "level": "story", "owner": "sam", "tier": 1, "tier_reason": "code behind tests",
        "ask": "Open the whole sheet.", "first_action": "Read the editor.",
        "state": "waiting_session", "thread": "sam", "source": "chat", "source_message": "",
        "result": "", "started": "", "attempts": 0,
        "created": "2026-09-20T01:00", "created_ts": 1.0,
    }
    base.update(over)
    return work.save_item(base)


def rec(**over):
    base = {"id": "w0123456789ab", "seat": "sam", "model": "", "usage": [],
            "patch": "diff --git a/hq/anim.py b/hq/anim.py\n", "stat": "hq/anim.py | 3 +",
            "files": ["hq/anim.py"], "result": "", "check": None,
            "error": f"it used all {drain.WORKER_TURNS} of its turns mid-edit",
            "limited": False, "resume": ""}
    base.update(over)
    return base


def main():
    tmp = tempfile.mkdtemp(prefix="hq-drain-test-")
    try:
        work.bind(fake_host(tmp))
        org = ORG

        print("recognising the reason")
        check(drain.ran_out_of_turns("it used all 60 of its turns"), "max_turns is the turn budget")
        check(drain.ran_out_of_turns("it used all 120 of its turns mid-edit"),
              "tool_use is the turn budget")
        check(not drain.ran_out_of_turns("the model declined the task"), "a refusal is not")
        check(not drain.ran_out_of_turns(""), "a clean finish is not")

        print("an attempt that ran out with edits in hand is tried again, not shown to him")
        it = card()
        r = rec()
        check(drain.auto_resume_reason(it, r) == r["error"], "the first attempt is resumed")
        it = drain.write_back(it, r, False, "held for another attempt", None, org)
        check(it["state"] == "waiting_session", "the card is back in the queue")
        check(it["resume"]["turns"] == drain.WORKER_TURNS * 2, "the next attempt has twice the turns")
        check(it["spent"]["attempts"] == 1 and it["attempts"] == 1, "the attempt is still counted")
        check("tries again" in it["result"] and "Nothing has landed" in it["result"],
              "the card says what happens next while it waits")
        check(not it["diff"]["applied"], "its edits did not land on the tree")
        prompt = drain.task_prompt(it, org, continuing=True, turns=it["resume"]["turns"])
        check("RAN OUT OF TURNS" in prompt and str(drain.WORKER_TURNS * 2) in prompt
              and "already in your worktree" in prompt,
              "the worker is told it is continuing, and with how many turns")
        prompt = drain.task_prompt(it, org, continuing=False, turns=it["resume"]["turns"])
        check("starting from main" in prompt,
              "when the patch no longer applies the worker is told it starts from main")

        print("a card being tried again goes to the front of the queue")
        card(id="w0000000000b2", created_ts=9.0)
        ids = [i["id"] for i in drain.queued()]
        check(ids[0] == "w0123456789ab" and ids[1] == "w0000000000b2",
              "the resumed card is picked up before the newer one")

        print("the dashboard sees the exact drain order and its holds")
        card(id="w0000000000f6", created_ts=12.0, repair_hold="the checker needs a smaller repair")
        view = drain.queue_view()
        check([row["id"] for row in view["eligible"] if row["action_type"] == "build"]
              == [i["id"] for i in drain.queued()],
              "visible build positions are the build worker's positions")
        held = next(row for row in view["held"] if row["id"] == "w0000000000f6")
        check(held["reason"] == "the checker needs a smaller repair",
              "excluded work carries the reason it cannot start")
        card(id="w0000000000a1", created_ts=14.0, started="2026-09-21T23:00")
        view = drain.queue_view()
        check("w0000000000a1" not in [row["id"] for row in view["eligible"]],
              "a claimed card is not still offered as eligible")
        check("w0000000000a1" not in [row["id"] for row in view["working"]]
              and any(row["work_id"] == "w0000000000a1" and row["action_type"] == "recover"
                      for row in view["eligible"]),
              "a stale started stamp creates recovery, never a false live session")

        print("the second run-out is tried once more; the third goes to him")
        it = drain.write_back(it, rec(), False, "held for another attempt", None, org)
        check(it["state"] == "waiting_session" and it["spent"]["attempts"] == 2,
              "attempt two ran out — one more try")
        r = rec()
        check(drain.auto_resume_reason(it, r) == "", "attempt three is the last the drain gives it")
        it = drain.write_back(it, r, False, "the check said it should not land as it stands",
                              None, org)
        check(it["state"] == "for_review", "after three attempts the card reaches him")
        check("resume" not in it, "and no further attempt is queued")
        check(it["result"].startswith("This attempt did not finish — it used all")
              and "attempt 3" in it["result"],
              "the result says it ran out and that the studio stopped trying")

        print("an attempt that ran out having changed nothing goes to him at once")
        it = card(id="w0000000000c3")
        r = rec(id="w0000000000c3", patch="", stat="", files=[])
        check(drain.auto_resume_reason(it, r) == "", "no files, no retry")
        it = drain.write_back(it, r, False, "nothing changed", None, org)
        check(it["state"] == "for_review" and "changed no files" in it["result"],
              "the card says why there was no second attempt")

        print("a clean finish after a resume clears the retry")
        it = card(id="w0000000000d4", resume={"why": "x", "turns": 120, "attempt": 1},
                  spent={"attempts": 1, "tokens": 0, "fresh": 0, "list_usd": 0})
        it = drain.write_back(it, rec(id="w0000000000d4", error="", result="Done: the sheet opens."),
                              True, "", None, org)
        check(it["state"] == "for_review" and "resume" not in it
              and it["result"] == "Done: the sheet opens.",
              "the finished result reaches him with nothing left queued")

        print("a review keeps its own short name")
        evidence = [{"label": "Open it", "href": "/review/sheet"}]
        it = card(id="w0000000000d5", deliverable={"name": "Earlier name", "evidence": evidence})
        named_result = ("The editor now opens every cell.\n"
                        + work.FOLLOW_MARK + "\n"
                        + '{"deliverable": {"name": "The full sprite sheet editor"}, "items": []}')
        it = drain.write_back(it, rec(id="w0000000000d5", error="", result=named_result),
                              False, "nothing changed", None, org)
        check(it.get("deliverable") == {"name": "The full sprite sheet editor", "evidence": evidence},
              "the build queue records a review name without replacing the original ask or evidence")

        print("a partial reply is kept beneath the failure, never in its place")
        it = card(id="w0000000000e5", spent={"attempts": 2, "tokens": 0, "fresh": 0, "list_usd": 0})
        it = drain.write_back(it, rec(id="w0000000000e5", result="I opened the sheet and"),
                              False, "held", None, org)
        check(it["result"].startswith("This attempt did not finish")
              and it["result"].rstrip().endswith("I opened the sheet and"),
              "the failure leads and what the worker said follows")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if FAILS:
        print(f"\n{len(FAILS)} failed.")
        return 1
    print("\nall green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""What a decision card counts as settled, and what happens to what he said.

Two rules, both learned the hard way on Q-110 (2026-09-19).

**Answering a card is not settling it.** He replied to Q-110 asking to see the
three candidates built rather than described, and HQ read "there is a ruling
file" as "he decided" — the card left his inbox for a collapsed fold and the
dashboard told him it needed nothing from him, while it was in fact waiting on
him. Only a ruling that picked an option settles a card.

**Nothing he has said is overwritten.** The ruling file kept the latest ruling
only, so the moment he picked an option his earlier words were gone from it and
survived only in the prose log. A card is a conversation and the file keeps
every turn.

    python3 hq/tests/test_decisions.py
"""
import json
import os
import shutil
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
HQ = os.path.dirname(HERE)
sys.path.insert(0, HQ)

import server  # noqa: E402

FAILS = []


def check(ok, what):
    print(f"  {'ok  ' if ok else 'FAIL'}    {what}")
    if not ok:
        FAILS.append(what)


def ruling(qid):
    with open(os.path.join(server.DATA, "rulings", f"{qid}.json"), encoding="utf-8") as f:
        return json.load(f)


def submission(n):
    return f"decision-test-{n:016d}"


def main():
    tmp = tempfile.mkdtemp(prefix="hq-decisions-test-")
    was = server.DATA
    was_work = server.work.WORK
    was_host = server.work.HOST
    server.DATA = tmp
    server.work.WORK = os.path.join(tmp, "work")
    server.work.HOST = server
    try:
        os.makedirs(os.path.join(tmp, "decisions"))
        os.makedirs(os.path.join(tmp, "work"))
        with open(os.path.join(tmp, "org.json"), "w", encoding="utf-8") as f:
            json.dump({"employees": [{"id": "rin", "name": "Rin Nakamura"},
                                      {"id": "claude", "name": "Adam"}]}, f)
        for qid, title in [("Q-900", "A card he has not touched"),
                           ("Q-901", "A card he answered without picking"),
                           ("Q-902", "A card he settled")]:
            with open(os.path.join(tmp, "decisions", f"{qid}.json"), "w", encoding="utf-8") as f:
                json.dump({"id": qid, "title": title, "question": "?", "owner": "rin",
                           "options": [{"key": "a", "label": "A feather"},
                                       {"key": "b", "label": "The stripped plant"},
                                       {"key": "c", "label": "The clods"}]}, f)

        print("answering a card is not settling it")
        server.record_ruling({"id": "Q-901", "intent": "revise", "submission_id": submission(1), "judgment": "Show me all three built first."})
        server.record_ruling({"id": "Q-902", "intent": "choose", "submission_id": submission(2), "option": "b", "option_label": "not trusted"})
        q = server.api_queue()
        check(set(q["rulings"]) == {"Q-901", "Q-902"}, "both rulings are on file")
        check(q["decided"] == ["Q-902"],
              "only the one that picked an option counts as decided")
        check(ruling("Q-902")["option_label"] == "The stripped plant",
              "the server records the label belonging to the submitted option key")
        check("Q-901" not in q["decided"],
              "a card he answered without picking is still his to settle")
        check("Q-900" not in q["decided"], "and a card he never touched is not decided either")

        print("a settled decision hands its linked goal to the studio")
        target = server._route_target({"kind": "decision", "id": "Q-902"})
        check(target["state"] == "pending integration",
              "a decision route reports the recorded integration hand-off")
        old_eval_measure, old_state_from = server.eval_measure, server._state_from
        old_goal_response, old_escalation = server._goal_response, server._escalation
        try:
            server.eval_measure = lambda measure: {"value": False}
            server._state_from = lambda reading, compare: "red"
            server._goal_response = lambda goal, state, reading: (state, {"link": None})
            server._escalation = lambda goal, state, reading: {"reason": "age"}
            goal = server.eval_goal({"id": "linked-goal", "statement": "Ship it",
                                     "owner": "rin", "measure": {}, "compare": {},
                                     "path_to_green": {"route": {"kind": "decision", "id": "Q-902"}}})
            check(not goal["needs_you"] and goal["ours"] and goal["escalation"] is None,
                  "a red goal cannot ask Daniel again while its chosen ruling awaits integration")
        finally:
            server.eval_measure, server._state_from = old_eval_measure, old_state_from
            server._goal_response, server._escalation = old_goal_response, old_escalation

        print("nothing he has said is overwritten")
        server.record_ruling({"id": "Q-901", "intent": "choose", "submission_id": submission(3), "option": "a", "option_label": "A feather",
                              "judgment": "Going with the feather after all."})
        r = ruling("Q-901")
        check(r["option"] == "a" and r["judgment"] == "Going with the feather after all.",
              "the latest ruling is the top-level one")
        check(len(r["earlier"]) == 1, "the earlier answer is kept, not replaced")
        check(r["earlier"][0]["judgment"] == "Show me all three built first.",
              "and it is kept word for word")
        check(r["earlier"][0]["option"] is None,
              "with the fact that it picked nothing, which is what made it a question")
        check("earlier" not in r["earlier"][0],
              "an earlier turn does not carry a copy of the turns before it")

        server.record_ruling({"id": "Q-901", "intent": "choose", "submission_id": submission(4), "option": "c", "option_label": "The clods"})
        r = ruling("Q-901")
        check([e.get("option") for e in r["earlier"]] == [None, "a"],
              "a third ruling keeps both of the first two, in the order he made them")
        check(server.api_queue()["decided"] == ["Q-901", "Q-902"],
              "and the card is settled on the latest pick")

        print("the prose log still gets every turn")
        with open(os.path.join(tmp, "rulings", "RULINGS.md"), encoding="utf-8") as f:
            log = f.read()
        check(log.count("## Q-901") == 3, "one entry per ruling, appended")
        check("Show me all three built first." in log, "including the one with no pick")

        print("a revision is durable work, not a hidden non-answer")
        missing_id = server.record_ruling({"id": "Q-900", "intent": "choose", "option": "a"})
        check("submission id" in missing_id.get("error", ""), "a legacy request without a submission id is rejected clearly")
        bad = server.record_ruling({"id": "Q-900", "intent": "choose", "submission_id": submission(5), "option": "z"})
        check(bad.get("error") == "that option is not on this decision", "an option key must exist on its decision")
        blank = server.record_ruling({"id": "Q-900", "intent": "revise", "submission_id": submission(6), "judgment": " "})
        check(blank.get("error") == "tell the studio what to revise", "revision needs feedback")
        first = server.record_ruling({"id": "Q-900", "intent": "revise", "submission_id": submission(7),
                                      "judgment": "Show the smaller-room option beside the others."})
        retry = server.record_ruling({"id": "Q-900", "intent": "revise", "submission_id": submission(7),
                                      "judgment": "Show the smaller-room option beside the others."})
        conflict = server.record_ruling({"id": "Q-900", "intent": "revise", "submission_id": submission(7),
                                         "judgment": "Use a different evidence sheet."})
        children = server.work.items()
        check(first.get("revision_work_id") == retry.get("revision_work_id") and len(children) == 2,
              "a retried revision creates exactly one linked work item")
        check("different decision content" in conflict.get("error", ""),
              "a reused submission id cannot silently accept edited content")
        child = next(i for i in children if i.get("decision_id") == "Q-900")
        check(child["owner"] == "rin" and child["parent"] == "Q-900"
              and child["return_to_decision"]["id"] == "Q-900",
              "revision work is assigned and linked back to its decision")
        check(not ruling("Q-900").get("option") and "Q-900" not in server.api_queue()["decided"],
              "a revision neither records a substantive option nor settles the decision")
        with open(os.path.join(tmp, "decisions", "Q-900.json"), "r+", encoding="utf-8") as f:
            returned = json.load(f)
            returned["replies"] = [{"at": "9999-01-01T00:00:00", "text": "Here is the revised card."}]
            f.seek(0); json.dump(returned, f); f.truncate()
        ready = {row["source_id"] for row in server.waiting_on_you()["ready"]}
        check("Q-900" in ready, "an owner reply after the revision ruling returns the decision to readiness")
        second_round = server.record_ruling({"id": "Q-900", "intent": "revise", "submission_id": submission(8),
                                             "judgment": "Show the smaller-room option beside the others."})
        q900_tasks = [i for i in server.work.items() if i.get("decision_id") == "Q-900"]
        check(second_round["revision_work_id"] != first["revision_work_id"] and len(q900_tasks) == 2
              and ruling("Q-900")["submission_id"] == submission(8),
              "identical feedback in a later revision round creates a new ruling and task")
        with open(os.path.join(tmp, "decisions", "Q-903.json"), "w", encoding="utf-8") as f:
            json.dump({"id": "Q-903", "title": "Legacy card", "options": []}, f)
        legacy = server.record_ruling({"id": "Q-903", "intent": "revise", "submission_id": submission(9), "judgment": "Name an owner and revise this."})
        legacy_work = next(i for i in server.work.items() if i.get("id") == legacy.get("revision_work_id"))
        check(legacy_work["owner"] == "claude", "an ownerless legacy decision routes to Adam for triage")

        print("overlapping retries are one revision")
        with open(os.path.join(tmp, "decisions", "Q-904.json"), "w", encoding="utf-8") as f:
            json.dump({"id": "Q-904", "title": "Concurrent card", "owner": "rin", "options": []}, f)
        gate = threading.Barrier(8)
        results = []
        def post_same_revision():
            gate.wait()
            results.append(server.record_ruling({"id": "Q-904", "intent": "revise",
                                                 "submission_id": submission(10),
                                                 "judgment": "Build the comparison first."}))
        threads = [threading.Thread(target=post_same_revision) for _ in range(8)]
        [thread.start() for thread in threads]
        [thread.join() for thread in threads]
        q904_tasks = [i for i in server.work.items() if i.get("decision_id") == "Q-904"]
        with open(os.path.join(tmp, "rulings", "RULINGS.md"), encoding="utf-8") as f:
            log = f.read()
        check(len(results) == 8 and len({r.get("revision_work_id") for r in results}) == 1
              and len(q904_tasks) == 1 and not ruling("Q-904")["earlier"]
              and log.count("## Q-904") == 1,
              "same-id overlapping requests produce one task and one history entry")

        print("an edited retry is a new action")
        with open(os.path.join(tmp, "decisions", "Q-905.json"), "w", encoding="utf-8") as f:
            json.dump({"id": "Q-905", "title": "Lost response card", "owner": "rin", "options": []}, f)
        lost_response = server.record_ruling({"id": "Q-905", "intent": "revise", "submission_id": submission(11),
                                              "judgment": "Show the rooms side by side."})
        edited_retry = server.record_ruling({"id": "Q-905", "intent": "revise", "submission_id": submission(12),
                                             "judgment": "Show the coop beside it too."})
        q905_tasks = [i for i in server.work.items() if i.get("decision_id") == "Q-905"]
        check(lost_response["revision_work_id"] != edited_retry["revision_work_id"]
              and len(q905_tasks) == 2 and len(ruling("Q-905")["earlier"]) == 1,
              "a lost response followed by edited feedback records a new revision")

        print("Q-109's recorded ruling agrees with the queue and card")
        with open(os.path.join(server.REPO, "hq", "data", "decisions", "Q-109.json"), encoding="utf-8") as f:
            q109 = json.load(f)
        with open(os.path.join(server.REPO, "docs", "DESIGNER_QUEUE.md"), encoding="utf-8") as f:
            queue_doc = f.read()
        chosen = next(o["key"] for o in q109["options"] if "(Chosen)" in o["label"])
        check(chosen == q109["ruled"]["option"] == "d" and
              "**Chosen: (d)**" in queue_doc,
              "Q-109's curated card and design queue record the chosen per-building rule")
    finally:
        server.DATA = was
        server.work.WORK = was_work
        server.work.HOST = was_host
        shutil.rmtree(tmp, ignore_errors=True)

    if FAILS:
        print(f"\n{len(FAILS)} failed.")
        return 1
    print("\nall green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

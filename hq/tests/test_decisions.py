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


def main():
    tmp = tempfile.mkdtemp(prefix="hq-decisions-test-")
    was = server.DATA
    server.DATA = tmp
    try:
        os.makedirs(os.path.join(tmp, "decisions"))
        for qid, title in [("Q-900", "A card he has not touched"),
                           ("Q-901", "A card he answered without picking"),
                           ("Q-902", "A card he settled")]:
            with open(os.path.join(tmp, "decisions", f"{qid}.json"), "w", encoding="utf-8") as f:
                json.dump({"id": qid, "title": title, "question": "?", "options": []}, f)

        print("answering a card is not settling it")
        server.record_ruling({"id": "Q-901", "judgment": "Show me all three built first."})
        server.record_ruling({"id": "Q-902", "option": "b", "option_label": "The stripped plant"})
        q = server.api_queue()
        check(set(q["rulings"]) == {"Q-901", "Q-902"}, "both rulings are on file")
        check(q["decided"] == ["Q-902"],
              "only the one that picked an option counts as decided")
        check("Q-901" not in q["decided"],
              "a card he answered without picking is still his to settle")
        check("Q-900" not in q["decided"], "and a card he never touched is not decided either")

        print("nothing he has said is overwritten")
        server.record_ruling({"id": "Q-901", "option": "a", "option_label": "A feather",
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

        server.record_ruling({"id": "Q-901", "option": "c", "option_label": "The clods"})
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
    finally:
        server.DATA = was
        shutil.rmtree(tmp, ignore_errors=True)

    if FAILS:
        print(f"\n{len(FAILS)} failed.")
        return 1
    print("\nall green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

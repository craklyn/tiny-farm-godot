#!/usr/bin/env python3
"""What lets a finished piece of work go in without Daniel reading it.

His rule, 2026-09-20 (S-16, `docs/QUEUE_TO_ZERO.md` §4): work he would only
rubber-stamp should never have reached him. So the drain commits a finished
card on its own when four things hold at once — the work is revertable, both
test suites ran green over it, the chief of staff read the diff and found
nothing, and nothing in the diff is of a kind that undoing a commit would not
put back. Anything else goes to him with the sentence saying which of the four
stopped it.

These tests break each of the four in turn and read the sentence back, because
a bar whose refusals cannot be explained is one nobody can act on.

    python3 hq/tests/test_landing_bar.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HQ = os.path.dirname(HERE)
sys.path.insert(0, HQ)

import drain  # noqa: E402
import work
import json


FAILS = []


def check(cond, what):
    print(("  ok      " if cond else "  FAILED  ") + what)
    if not cond:
        FAILS.append(what)


def item(**over):
    base = {"id": "w0123456789ab", "title": "The crow leaves by the fence gap",
            "tier": 1, "owner": "tomas"}
    base.update(over)
    return base


def rec(**over):
    base = {"files": ["entities/crow.gd"], "patch": "fixture diff",
            "result": "Finished.\n" + work.FOLLOW_MARK + '\n{"outcome":{"status":"complete"},"follow_ups":[]}',
            "check": {"verdict": "pass", "summary": "does what was asked",
                      "findings": [], "read": True, "complete": True}}
    base.update(over)
    return base


GREEN = {"unit": {"ok": True, "tail": ""}, "integration": {"ok": True, "tail": ""}}


def bar(it=None, r=None, applied=True, suites=GREEN):
    r = r or rec()
    r["candidate"] = {"tree":"fixture-tree", "files":drain.git_blobs(drain.server.REPO,"",r["files"])}
    r["candidate_unchanged"] = True
    r["candidate_suites"] = GREEN if r["files"] else None
    r["candidate_test_evidence"] = work.evidence_id([r["candidate"],r["candidate_suites"]])
    r["check_evidence"] = work.evidence_id([r["result"], r["patch"],r["candidate"]])
    r["test_evidence"] = work.evidence_id([r["patch"], suites])
    r["tree_evidence"] = drain.tree_evidence(r["files"])
    return drain.meets_landing_bar(it or item(), r, applied, suites)


def main():
    print("work that clears all four goes in on its own")
    ok, why = bar()
    check(ok and why == "", "a green, read, revertable change lands with no reason to give")
    ok, why = bar(it=item(tier=0), r=rec(files=[]), applied=False, suites=None)
    check(ok, "a reading changes no file, so it has no suites to answer for and lands")

    print("how hard it would be to walk back")
    ok, why = bar(it=item(tier=2))
    check(not ok and "needed your yes" in why,
          "work that needed his yes to start still needs his answer")
    ok, why = bar(it=item(tier=2, tier_checked=1))
    check(ok, "the re-read of what the diff actually touched is what counts")
    ok, why = bar(it=item(tier=1), r=rec(check={"verdict": "pass", "findings": [],
                                                "read": True, "tier_checked": 2}))
    check(not ok, "and a re-read that raises it stops the landing")
    ok, why = bar(it=item(tier=None))
    check(not ok, "a card with no record of how risky it is does not land")

    print("the test suites, over this diff")
    ok, why = bar(applied=False)
    check(not ok and "could not be applied" in why,
          "a change that never reached the repository has nothing to land")
    ok, why = bar(suites=None)
    check(not ok and "not run" in why, "no run at all is not a green run")
    ok, why = bar(suites={"unit": {"ok": True}, "integration": {"ok": False}})
    check(not ok and "integration test suite is failing" in why,
          "a red suite is named, so the reason says what to go and look at")
    ok, why = bar(suites={"unit": {"ok": False}, "integration": {"ok": False}})
    check(not ok and "integration and unit test suites are" in why,
          "two red suites read as a sentence, not as a list")
    ok, why = bar(it=item(tier=0), r=rec(files=[]), applied=False, suites=None)
    check(ok, "only a card with no diff at all skips this")

    print("somebody has to have read the diff")
    ok, why = bar(r=rec(check={"verdict": "concerns", "findings": [], "read": True}))
    check(not ok, "concerns cannot certify completion even with no listed findings")
    ok, why = bar(r=rec(check={"verdict": "concerns", "read": True, "findings": [
        {"what": "the crow can leave through a closed gate", "where": "crow.gd", "fix": ""}]}))
    check(not ok and "something you should see" in why,
          "a read that found something sends the card to him")
    ok, why = bar(r=rec(check={"verdict": "fail", "findings": [], "read": True}))
    check(not ok and "should not go in" in why, "a failed read never lands")
    ok, why = bar(r=rec(check=None))
    check(not ok, "no read at all never lands")
    ok, why = bar(r=rec(check={"verdict": "concerns", "findings": [], "read": False,
                               "summary": "nobody checked this"}))
    check(not ok and "nobody read" in why,
          "the record of a read that never happened is not a clean read")

    print("what reverting a commit would not put back")
    for path, what in (("docs/design/06-robots.md", "a design document"),
                       ("docs/DEPLOY.md", "the deploy runbook"),
                       ("ITCH_PAGE.md", "the store page"),
                       (".github/workflows/tests.yml", "the build pipeline"),
                       ("hq/data/releases.json", "the release record")):
        ok, why = bar(r=rec(files=["hq/work.py", path]))
        check(not ok and path in why, f"{what} goes to him whatever else is green")
    ok, why = bar(r=rec(files=["docs/QUEUE_TO_ZERO.md", "docs/WRITING.md"]))
    check(ok, "an ordinary document beside them is not one of them")

    if FAILS:
        print(f"\n{len(FAILS)} failed.")
        return 1
    print("\nall green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

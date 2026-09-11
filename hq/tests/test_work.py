#!/usr/bin/env python3
"""What a comment on a Work card does, without a model in the loop.

His rule, 2026-09-11: a comment is not a verdict, and he should not have to
pick the path it takes. The owner reads it and makes one of three moves —
answer, revise, follow-up — and the card says which. These tests pin that
contract at the seam where it is cheapest to check: the card's JSON before and
after each API call and each (stubbed) reply.

    python3 hq/tests/test_work.py
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

import work  # noqa: E402


ORG = {"employees": [
    {"id": "daniel", "name": "Daniel", "title": "CEO", "level": "L10", "team": "HQ",
     "responsibilities": ["everything"], "persona": ""},
    {"id": "claude", "name": "Claude", "title": "Chief of staff", "level": "L7", "team": "HQ",
     "responsibilities": ["filing work"], "persona": ""},
    {"id": "sam", "name": "Sam Ortega", "title": "Engineer", "level": "L5", "team": "Engineering",
     "responsibilities": ["the boot"], "persona": ""},
    {"id": "rin", "name": "Rin Sato", "title": "Artist", "level": "L5", "team": "Art",
     "responsibilities": ["sprites"], "persona": ""},
]}


def fake_host(data_dir):
    """The slice of server.py that work.py touches, with no server in it."""
    host = types.SimpleNamespace()
    host.DATA = data_dir
    host.REPO = data_dir
    host.MAX_TURNS = 5
    host.load_json = lambda p: json.load(open(p, encoding="utf-8"))
    host.load_org = lambda: ORG
    host.build_system_prompt = lambda org, who: f"you are {who}"
    host.seat_model = lambda org, who, override=None: ""
    host.limited_until = lambda: 0.0
    host.token_window = lambda: {"tokens": 0, "calls": 0, "hours": 5}
    host.record_model_usage = lambda *a, **k: None
    host.usage_from_cli = lambda doc: None
    host._looks_like_limit = lambda text: False
    host.note_limit = lambda text: None
    host.clear_limit = lambda: None
    host.cli_failure = lambda proc: "failed"
    host.CHAT_LOCK = __import__("threading").Semaphore(2)
    return host


FAILS = []


def check(cond, what):
    print(("  ok      " if cond else "  FAILED  ") + what)
    if not cond:
        FAILS.append(what)


def card(**over):
    base = {
        "id": "w0123456789ab", "title": "The sunflower bloom opens the game",
        "level": "story", "owner": "sam", "tier": 1, "tier_reason": "players see it",
        "ask": "Build the bloom as the splash.", "first_action": "Read the title screen.",
        "state": "for_review", "thread": "sam", "source": "chat", "source_message": "",
        "result": "The boot now plays the bloom.", "started": "", "attempts": 1,
        "created": "2026-09-10T22:21", "created_ts": 1.0, "finished": "2026-09-10T23:52",
        "follow_ups": [{"title": "Give the bloom a closed-bud first frame", "owner": "rin",
                        "level": "task", "tier": 1, "first_action": "Regenerate the loop.",
                        "why": "the boot opens on a closed bud"}],
        "recommend": {},
        "diff": {"stat": "main.gd | 29 ++", "files": ["main.gd"], "applied": True, "why_not": ""},
        "check": {"verdict": "concerns", "summary": "replays on every return", "findings": []},
        "suites": {"unit": {"ok": True, "tail": ""}},
    }
    base.update(over)
    return base


def reply(text, tail):
    return f"{text}\n{work.FOLLOW_MARK}\n{tail}"


def stub_cli(text):
    """The owner's next reply, whatever the prompt."""
    work._run_cli = lambda *a, **k: (text, False)


def captures():
    return [n for n in os.listdir(work.CAPTURES) if n.endswith(".json")]


def main():
    tmp = tempfile.mkdtemp(prefix="hq-work-test-")
    try:
        work.bind(fake_host(tmp))
        org = ORG

        print("parsing the move")
        got, amend, rec, move = work._parse_follows('{"items": [], "move": "Follow_Up"}', org, "sam")
        check(move == "follow-up", "follow_up in any spelling is the follow-up move")
        got, amend, rec, move = work._parse_follows('{"items": [], "move": "revise"}', org, "sam")
        check(move == "revise", "revise is read as revise")
        got, amend, rec, move = work._parse_follows('{"items": [], "move": "shrug"}', org, "sam")
        check(move is None, "an unknown move is no move")
        parts = work._split_result("just prose", org, "sam")
        check(len(parts) == 5 and parts[1] is None and parts[4] is None,
              "a reply with no block yields five parts, all unknown")

        print("a comment on Accept is answered, and travels into what the yes starts")
        work.save_item(card())
        out = work.api_post("/api/work/accept", {"id": "w0123456789ab",
                                                 "comment": "Could the player rise out of the bud?"})
        check(out["state"] == "accepted", "the card closes")
        check(out.get("awaiting_reply") is True, "the owner is asked to answer the comment")
        last = out["conversation"][-1]
        check(last["role"] == "daniel" and last.get("with") == "accept",
              "the comment is on the card, marked as riding on the accept")
        kids = [i for i in work.items() if i.get("parent") == "w0123456789ab"]
        check(len(kids) == 1 and "rise out of the bud" in kids[0]["ask"],
              "the follow-up is filed with his comment in its brief")
        check(kids[0]["state"] == "waiting_session", "a tier-1 follow-up waits for the build queue")
        check(not captures(), "nothing is read twice: the reply, not the accept, is what gets read")

        print("the owner's reply on a closed card can answer or file, never revise")
        stub_cli(reply("Yes — the bud opens over the title.",
                       '{"items": [], "move": "revise"}'))
        work._process_response(work.HOST.load_json(work._item_path("w0123456789ab")), org)
        it = work.HOST.load_json(work._item_path("w0123456789ab"))
        check(it["state"] == "accepted" and not it.get("revising"),
              "a closed card stays closed — revise is read as answer")
        check(it["conversation"][-1].get("move") == "answer", "the reply is marked as an answer")
        check(it.get("awaiting_reply") is False, "the card is no longer waiting")
        check(len(captures()) == 1, "an answer is still read for the work it implies")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("a comment on an open result: revise")
        work.save_item(card(id="w0000000000e1"))
        work.api_post("/api/work/respond", {"id": "w0000000000e1",
                                            "message": "Make her rise out of the top of the bud."})
        it = work.HOST.load_json(work._item_path("w0000000000e1"))
        check(it.get("awaiting_reply") is True, "a comment with no button asks the owner")
        stub_cli(reply("I will draw her rising from the top.",
                       '{"items": [], "move": "revise"}'))
        work._process_response(it, org)
        it = work.HOST.load_json(work._item_path("w0000000000e1"))
        check(it["state"] == "waiting_session" and it.get("revising") is True,
              "a tier-1 revise goes back to the build queue, marked as a revision")
        check(it["conversation"][-1].get("move") == "revise", "the reply is marked as revising")
        check(it["prior_results"][-1]["result"] == "The boot now plays the bloom.",
              "the earlier result is kept for the worker and the card")
        check(it["result"] == "The boot now plays the bloom.",
              "the card keeps showing the earlier result while the revision runs")
        check("check" not in it and it["prior_checks"][-1]["summary"] == "replays on every return",
              "the earlier check goes with the brief")
        check(it["diff"]["applied"] is True, "the landed diff is kept — the revision builds on it")
        check("suites" not in it, "the suite results are dropped — they described the old tree")
        check(not captures(), "a revise is the work; it is not read for work again")
        brief = work.revision_brief(it)
        check("REVISING YOUR OWN EARLIER RESULT" in brief and "The boot now plays the bloom." in brief,
              "the revision brief carries the earlier result")
        it["state"] = "for_review"
        work.finish_revision(it)
        check(it.get("revisions") == 1 and "revising" not in it, "a landed revision is counted")

        print("a comment on an open result: follow-up")
        work.save_item(card(id="w0000000000f1"))
        work.api_post("/api/work/respond", {"id": "w0000000000f1",
                                            "message": "The crow should also react to the bloom."})
        stub_cli(reply("That is Rin's — filing it.",
                       '{"items": [{"title": "Draw the crow noticing the bloom", "owner": "rin", '
                       '"level": "task", "tier": 1, "first_action": "Sketch it.", '
                       '"why": "he asked"}], "move": "follow-up"}'))
        work._process_response(work.HOST.load_json(work._item_path("w0000000000f1")), org)
        it = work.HOST.load_json(work._item_path("w0000000000f1"))
        kids = [i for i in work.items() if i.get("parent") == "w0000000000f1"]
        check(len(kids) == 1 and kids[0]["owner"] == "rin",
              "the follow-up is filed now, to the person named")
        check(it["state"] == "for_review" and it["follow_ups"] == [],
              "this card stands, and accepting it will not file the same work again")
        check(it["conversation"][-1].get("move") == "follow-up"
              and it["conversation"][-1]["filed"][0]["owner"] == "rin",
              "the reply says what it filed and to whom")
        check(it["spawned"][0]["id"] == kids[0]["id"], "the card shows what it set in motion")
        check(not captures(), "a follow-up is filed by the reply; it is not read for work again")

        print("a comment on an open result: answer")
        work.save_item(card(id="w0000000000a1"))
        work.api_post("/api/work/respond", {"id": "w0000000000a1", "message": "Does it loop?"})
        stub_cli(reply("No — it plays once.",
                       '{"items": [{"title": "Loop the bloom", "owner": "sam", "tier": 1, '
                       '"first_action": "x", "why": "if he wants it"}], "move": "answer"}'))
        work._process_response(work.HOST.load_json(work._item_path("w0000000000a1")), org)
        it = work.HOST.load_json(work._item_path("w0000000000a1"))
        check(it["state"] == "for_review" and not it.get("revising"), "an answer changes no state")
        check(len(it["follow_ups"]) == 1 and not [i for i in work.items() if i.get("parent") == "w0000000000a1"],
              "what an answer names is shown on the card and filed only on his yes")
        check(len(captures()) == 1, "an answer is read for the work it implies")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("tier 0 revises in the read-only lane")
        work.save_item(card(id="w0000000000d0", tier=0, diff=None, check=None, suites=None))
        work.api_post("/api/work/respond", {"id": "w0000000000d0", "message": "Shorter."})
        stub_cli(reply("Will do.", '{"items": [], "move": "revise"}'))
        work._process_response(work.HOST.load_json(work._item_path("w0000000000d0")), org)
        it = work.HOST.load_json(work._item_path("w0000000000d0"))
        check(it["state"] == "doing" and it["started"] == "" and it.get("revising") is True,
              "a tier-0 revise goes straight back to the worker")
        check("REVISING YOUR OWN EARLIER RESULT" in work._do_prompt(it, org),
              "the tier-0 brief tells the owner to extend, not redo")

        print("a question is filed as thinking, not as the thing asked about")
        prompt = work._capture_prompt(org, {"to": "sam", "message": "Could she rise out of it?",
                                           "reply": "Accepted."})
        check("A QUESTION IS ITS OWN WORK" in prompt and "is tier-0 work" in prompt,
              "the intake is told a question files at tier 0")
        spec = work._follows_spec(org, amendable=True, moves="open")
        check('"move": "answer|revise|follow-up"' in spec and "revise" in spec,
              "the reply block asks for the move")
        spec = work._follows_spec(org, amendable=False, moves="closed")
        check("this card is closed" in spec and '"revise"     —' not in spec,
              "a closed card offers answer and follow-up only")
        spec = work._follows_spec(org)
        check('"move"' not in spec, "a result (not a reply) is not asked for a move")

        print("the old send-back path is gone")
        out = work.api_post("/api/work/redo", {"id": "w0000000000a1", "comment": "again"})
        check(out.get("error") == "not found", "there is no redo any more — a comment is the way back")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if FAILS:
        print(f"\n{len(FAILS)} failed.")
        return 1
    print("\nall green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

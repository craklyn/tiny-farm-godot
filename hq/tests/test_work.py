#!/usr/bin/env python3
"""What a comment on a Work card does, and what a card may put in his queue,
without a model in the loop.

His rule, 2026-09-11: a comment is not a verdict, and he should not have to
pick the path it takes. The owner reads it and makes one of four moves —
answer, revise, follow-up, or "this needs work" — and the card says which.
docs/QUEUE_TO_ZERO.md §8 adds the clock: the reply starts when he sends it, and
thirty seconds later the card hands back and stops being his move. §5 (S-17)
adds what a finished card may start: an untiered follow-up is tier 1, one that
is hard to walk back is a question somebody has to write before he sees it, one
subject files one card, and a follow-up he already said yes to says so. These
tests pin all three contracts at the seam where it is cheapest to check: the
card's JSON before and after each API call and each (stubbed) reply.

    python3 hq/tests/test_work.py
"""
import json
import os
import shutil
import sys
import tempfile
import time
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


# A complete recommendation: the choice, the answer, the reason that decides
# it, and the alternative. A card needs one of these before it may ask him for
# a yes, so most of the cards below carry it.
REC = {"question": "Does the bloom open the game?", "answer": "Yes, keep it.",
       "why": "it is the only thing on the boot a four-year-old reads",
       "instead": "cut to the farm and lose the opening"}


def reply(text, tail):
    return f"{text}\n{work.FOLLOW_MARK}\n{tail}"


def stub_cli(text):
    """The owner's next reply, whatever the prompt."""
    work._run_cli = lambda *a, **k: (text, False)


def captures():
    return [n for n in os.listdir(work.CAPTURES) if n.endswith(".json")]


def item(item_id):
    return work.HOST.load_json(work._item_path(item_id))


def until(cond, seconds=5.0):
    """Wait for something a background thread is doing, or give up. Used only
    where the thing under test IS the background start — everywhere else the
    tests drive the reply by hand."""
    end = time.time() + seconds
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.02)
    return False


def main():
    tmp = tempfile.mkdtemp(prefix="hq-work-test-")
    try:
        work.bind(fake_host(tmp))
        org = ORG
        # Writing on a card now starts the owner's reply immediately, on its own
        # thread. Every test below drives the reply by hand so it can say what
        # came back, so the automatic start is held off until the section that
        # is about the automatic start.
        real_start_reply = work.start_reply
        work.start_reply = lambda item_id: None

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
        named = reply("The bloom is ready.",
                      '{"deliverable": {"name": "The sunflower bloom animation"}, "items": []}')
        check(work.result_deliverable(named) == {"name": "The sunflower bloom animation"},
              "a completed result keeps Daniel's short deliverable name separate from its ask")
        check(work.result_deliverable("just prose") is None,
              "an older result without a recorded deliverable is not given an invented one")

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
        spec = work._follows_spec(org, amendable=True, moves="open", wait="waiting")
        check('"move": "answer|revise|follow-up|needs-work"' in spec,
              "a card he is waiting in front of offers the move that ends the wait")
        spec = work._follows_spec(org, amendable=True, moves="open", wait="owed")
        check('"move": "answer|revise|follow-up"' in spec and "STOPPED WAITING" in spec,
              "a card that already handed back cannot defer him a second time")
        spec = work._follows_spec(org, amendable=False, moves="closed")
        check("this card is closed" in spec and '"revise"     —' not in spec,
              "a closed card offers answer and follow-up only")
        spec = work._follows_spec(org)
        check('"move"' not in spec, "a result (not a reply) is not asked for a move")

        print("thirty seconds, then the card hands back")
        check("owed" in work.STATES, "handed back is a state the page can show")
        check(work.reply_seconds() == 30, "the thirty seconds comes from the policy file")
        work.save_item(card(id="w00000000c01"))
        work.api_post("/api/work/respond", {"id": "w00000000c01", "message": "Why once?"})
        it = item("w00000000c01")
        check(round(it["reply_due_ts"] - it["asked_ts"]) == 30,
              "the card carries the deadline, so the page and the machine keep one clock")
        it["asked_ts"] -= 31
        it["reply_due_ts"] -= 31
        work.save_item(it)
        work.hand_back_if_late("w00000000c01")
        it = item("w00000000c01")
        check(it["state"] == "owed" and it["owed_from"] == "for_review",
              "a question nobody answered in thirty seconds leaves his list")
        check(it.get("owed_to") == "sam" and it.get("owed_since"),
              "the strip can name who it is coming back from, and since when")
        check(it.get("awaiting_reply") is True,
              "the studio still owes the answer — handing back is not dropping it")
        snap = work.snapshot()
        check(not any(i["state"] == "owed" and work._in_his_list(i) for i in snap["items"])
              and snap["waiting_on_you"] + snap["unprepped"]
              == sum(1 for i in snap["items"] if work.work_reviewable(
                  i, i.get("workflow_view"))),
              "a handed-back card is not counted as waiting on him")
        check(snap["owed"] == 1 and snap["reply_seconds"] == 30 and snap["now"] > 0,
              "the page is told what is coming back, and on what clock")

        print("the answer brings it back to the top of his list")
        stub_cli(reply("It plays once — looping it costs the quiet.", "NONE"))
        work._process_response(item("w00000000c01"), org)
        it = item("w00000000c01")
        check(it["state"] == "for_review" and "owed_from" not in it and "owed_to" not in it,
              "the card returns to the list it left")
        check(it.get("returned_at") and it.get("returned_ts", 0) > 0,
              "and returns at the top, not where it was")
        check([m["role"] for m in it["conversation"][-2:]] == ["daniel", "sam"],
              "it reads as a conversation: his comment, then the answer")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("a card cannot put him off twice on one question")
        work.save_item(card(id="w00000000c04"))
        work.api_post("/api/work/respond", {"id": "w00000000c04", "message": "Why this way?"})
        it = item("w00000000c04")
        it["asked_ts"] -= 31
        it["reply_due_ts"] -= 31
        work.save_item(it)
        work.hand_back_if_late("w00000000c04")
        check(item("w00000000c04")["state"] == "owed", "it hands back the first time")
        stub_cli(reply("Still looking into it.", '{"items": [], "move": "needs-work"}'))
        work._process_response(item("w00000000c04"), org)
        it = item("w00000000c04")
        check(it["state"] == "for_review",
              "a second request for more time is read as the answer, not as another deferral")
        check(it["conversation"][-1].get("move") != "needs-work",
              "and the card does not record it as handing back again")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("an owed card is still the card it was")
        work.save_item(card(id="w00000000c02"))
        work.api_post("/api/work/respond", {"id": "w00000000c02", "message": "Make it slower."})
        prompt = work._response_prompt(item("w00000000c02"), org)
        check("THIRTY SECONDS" in prompt and '"needs-work"' in prompt,
              "the owner is told he is waiting, and how to say the answer needs work")
        it = item("w00000000c02")
        it["asked_ts"] -= 31
        it["reply_due_ts"] -= 31
        work.save_item(it)
        work._sweep_hand_backs()
        check(item("w00000000c02")["state"] == "owed",
              "the sweep catches a question no live timer is watching")
        prompt = work._response_prompt(item("w00000000c02"), org)
        check("THIRTY SECONDS" not in prompt and "STOPPED WAITING" in prompt,
              "once the card has handed back the owner is told to answer, not to defer")
        stub_cli(reply("Slowing it to four seconds.", '{"items": [], "move": "revise"}'))
        work._process_response(item("w00000000c02"), org)
        it = item("w00000000c02")
        check(it["state"] == "waiting_session" and it.get("revising") is True,
              "a revise on a handed-back card still revises — owed is not what the card is")

        print("a reply that is only 'this needs work' hands back too")
        work.save_item(card(id="w00000000c03"))
        work.api_post("/api/work/respond", {"id": "w00000000c03", "message": "What does it cost?"})
        stub_cli(reply("I have to measure it on the tablet first.",
                       '{"items": [], "move": "needs-work"}'))
        work._process_response(item("w00000000c03"), org)
        it = item("w00000000c03")
        check(it["state"] == "owed" and it["owed_from"] == "for_review",
              "a one-line 'not yet' does not put the card back in front of him")
        check("measure it on the tablet" in it.get("owed_why", ""),
              "the strip can say what it is waiting for")
        check(it.get("returned_at") is None, "nothing came back, so nothing returns")
        check(it.get("awaiting_reply") is True,
              "the answer is still owed, so the card is still asking for it")
        check(not captures(), "one line saying it is not done yet is not read for work")
        stub_cli(reply("It costs 1.4 ms a frame on the tablet.", "NONE"))
        work._process_response(item("w00000000c03"), org)
        it = item("w00000000c03")
        check(it["state"] == "for_review" and it.get("returned_at"),
              "and the answer, when it comes, brings the card back as any other does")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("a second question is not swallowed by the answer to the first")
        work.save_item(card(id="w00000000c06"))
        work.api_post("/api/work/respond", {"id": "w00000000c06", "message": "Why once?"})
        stale = item("w00000000c06")
        work.api_post("/api/work/respond", {"id": "w00000000c06", "message": "And how long is it?"})
        stub_cli(reply("It plays once.", "NONE"))
        work._process_response(stale, org)
        it = item("w00000000c06")
        check(it.get("awaiting_reply") is True,
              "he wrote again while the answer was being written, so one is still owed")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("a card that is not his move never hands back")
        work.save_item(dict(item("w00000000c04"), state="accepted"))
        work.api_post("/api/work/respond", {"id": "w00000000c04", "message": "Nice one."})
        check(work._arm_deadline(item("w00000000c04")) is None,
              "a closed card has no wait to end, so no clock runs on it")
        stub_cli(reply("Thanks — it needs work before I can say more.",
                       '{"items": [], "move": "needs-work"}'))
        work._process_response(item("w00000000c04"), org)
        it = item("w00000000c04")
        check(it["state"] == "accepted" and it["conversation"][-1]["move"] == "answer",
              "an accepted card does not reopen itself to say it needs longer")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("the reply starts when he sends it, not on the next tick")
        work.start_reply = real_start_reply
        work.save_item(card(id="w00000000c05"))
        stub_cli(reply("Yes — it opens over the title.", "NONE"))
        work.api_post("/api/work/respond", {"id": "w00000000c05", "message": "Does it open over the title?"})
        check(until(lambda: item("w00000000c05").get("awaiting_reply") is False),
              "his POST starts the owner writing; no worker tick is involved")
        check(item("w00000000c05")["conversation"][-1]["role"] == "sam",
              "the answer is on the card")
        work.start_reply = lambda item_id: None
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("a follow-up that names no tier is tier 1")
        got, _a, _r, _m = work._parse_follows(
            '{"items": [{"title": "Trim the fade", "owner": "rin", '
            '"first_action": "x", "why": "y"}]}', org, "sam")
        check(got[0]["tier"] == 1, "silence about the tier is read as tier 1, not as ask-him-first")
        got, _a, _r, _m = work._parse_follows(
            '{"items": [{"title": "Trim the fade", "owner": "rin", "tier": "soon", '
            '"first_action": "x", "why": "y"}]}', org, "sam")
        check(got[0]["tier"] == 1, "a tier that is not a number is read the same way")
        got, _a, _r, _m = work._parse_follows(
            '{"items": [{"title": "Ship the build", "owner": "rin", "tier": 2, '
            '"first_action": "x", "why": "y"}]}', org, "sam")
        check(got[0]["tier"] == 2, "a tier that is named is kept")

        print("work that is hard to walk back files as a question to be written")
        work.save_item(card(id="w0000000b0001", recommend=REC, follow_ups=[
            {"title": "Put the bloom on the store page", "owner": "rin", "level": "task",
             "tier": 2, "first_action": "Swap the hero image.", "why": "players see it"}]))
        work.api_post("/api/work/accept", {"id": "w0000000b0001"})
        kid = [i for i in work.items() if i.get("parent") == "w0000000b0001"][0]
        check(kid["state"] == "prepping" and kid["owner"] == "rin",
              "a tier-2 follow-up waits with the seat that owns it, not in his list")
        check(kid.get("prep_attempts") == 0 and kid.get("prepping_since"),
              "the card says the question has not been written yet")
        snap = work.snapshot()
        check(snap["prepping"] == 1 and not work._in_his_list(kid),
              "it is counted as a question being written, and not as one he has been asked")

        print("the question comes back short, and is written again")
        stub_cli(reply("It should go up.",
                       '{"items": [], "recommend": {"question": "Hero image?", '
                       '"answer": "Use the bloom."}}'))
        work.prep_question(item(kid["id"]), org)
        it = item(kid["id"])
        check(it["state"] == "prepping" and it["prep_short"] == ["why", "instead"],
              "a recommendation missing the reason and the alternative does not reach him")
        check(it["prep_draft"]["answer"] == "Use the bloom.",
              "what was written is kept, so the second draft is not written from nothing")
        check("came back short of why, instead" in work._prep_prompt(it, org),
              "and the seat is told what its draft was missing")
        for _ in range(work.PREP_TRIES):
            work.prep_question(item(kid["id"]), org)
        it = item(kid["id"])
        check(it["state"] == "prepping" and it.get("prep_stalled"),
              "after three short drafts it stops rewriting and says a person has to write it")
        check(work.snapshot()["prep_stalled"] == 1, "and the page can show that it stopped")

        print("a complete question joins his list")
        work.save_item(card(id="w0000000b0002", recommend=REC, follow_ups=[
            {"title": "Raise the seed price", "owner": "rin", "level": "task", "tier": 2,
             "first_action": "Edit the shop table.", "why": "the economy is loose"}]))
        work.api_post("/api/work/accept", {"id": "w0000000b0002"})
        kid2 = [i for i in work.items() if i.get("parent") == "w0000000b0002"][0]
        stub_cli(reply("Seeds are too cheap by half.",
                       '{"items": [], "recommend": {"question": "Raise the seed price?", '
                       '"answer": "Raise it to 12.", "why": "a day of play buys the whole shop", '
                       '"instead": "leave it and cut the harvest payout"}}'))
        work.prep_question(item(kid2["id"]), org)
        it = item(kid2["id"])
        check(it["state"] == "needs_approval" and it["recommend"]["instead"],
              "a question with all four parts is what reaches him")
        check(it["prep_note"] == "Seeds are too cheap by half." and it["prepped"]["by"] == "rin",
              "the paragraph the seat wrote is kept, and the card says who wrote it")
        check(not it.get("result"),
              "and it is not filed as a result — nobody has done anything here yet")
        check("prep_short" not in it and "prep_draft" not in it,
              "the drafting is over and the card stops showing it")
        check(work.has_recommendation(it) and work._in_his_list(it),
              "and it is now counted as waiting on him")

        print("one subject, one card")
        check(work.merge_key("The Record the crow landing.") == work.merge_key("Record the crow landing"),
              "capitals, punctuation and a leading article are not part of a subject")
        work.save_item(card(id="w0000000e0001", owner="rin", state="waiting_session",
                            title="Record the crow landing", ask="Record it.", follow_ups=[]))
        work.save_item(card(id="w0000000e0002", recommend=REC, follow_ups=[
            {"title": "The Record the crow landing.", "owner": "rin", "level": "task",
             "tier": 1, "first_action": "Record it in the coop.", "why": "the coop needs it too"}]))
        work.api_post("/api/work/accept", {"id": "w0000000e0002"})
        check(not [i for i in work.items() if i.get("parent") == "w0000000e0002"],
              "the same subject, same owner, does not file a twin")
        twin = item("w0000000e0001")
        check("the coop needs it too" in twin["ask"] and twin["ask"].startswith("Record it."),
              "the second ask is added to the card that already holds the subject")
        check(twin["merged_from"][0]["id"] == "w0000000e0002",
              "and the card records where it grew from")
        check(item("w0000000e0002")["spawned"][0]["merged"] is True,
              "the card he accepted says its work joined a card already open")

        print("one explicit decision, every source retained")
        legacy = card(id="w0000000d0001", owner="rin", state="waiting_session",
                      title="Choose the sound", decision_key="sound-choice",
                      parent="w0000000d0000", merged_from=[
                          {"id": "w0000000d0002", "card": "First sound request", "title": "Choose the sound"}])
        work.save_item(legacy)
        work._merge_into(legacy, {"id": "w0000000d0003", "title": "Second sound request"},
                         {"title": "Pick the take", "decision_key": "sound-choice"}, "Pick the take.")
        got = item("w0000000d0001")
        check({s["id"] for s in got["source_work"]} == {
            "w0000000d0000", "w0000000d0002", "w0000000d0003"},
            "a new merge retains the parent and every legacy merged source")
        check(len(got["merged_from"]) == 2,
              "the original merge history remains in the stored record")
        check(work._open_twin("rin", work.merge_key("A different title"),
                              decision_key="sound-choice")["id"] == got["id"],
              "an explicit shared decision finds one open card across title changes")
        check(work._open_twin("rin", work.merge_key("Choose the sound")) is None,
              "matching words do not silently merge a separately keyed decision")
        shared_parent = card(id="w0000000d0004", owner="rin", title="Sound review")
        work.save_item(shared_parent)
        shared = work._file_follow_ups(shared_parent, [
            {"title": "Pick the field recording", "owner": "rin", "tier": 2,
             "decision_key": "field-sound", "why": "the field needs one sound"},
            {"title": "Choose the field sound take", "owner": "rin", "tier": 2,
             "decision_key": "field-sound", "why": "the mixer needs the same choice"},
        ], ORG, "follow", "Choose one field sound.")
        check(len({s["id"] for s in shared}) == 1,
              "two outcome names tied to one explicit decision file one card")
        check(item(shared[0]["id"])["source_work"][0]["id"] == shared_parent["id"],
              "the single filed card links back to its source request")

        print("a restart in the middle of writing a question does not spend a try")
        work.save_item(card(id="w00000000m10", owner="milo", state="prepping",
                            prep_attempts=1, prep_in_flight=True))
        work._sanitize()
        it = item("w00000000m10")
        check(it.get("prep_attempts") == 0 and not it.get("prep_in_flight"),
              "the try is given back, so restarts cannot retire a question nobody wrote")

        print("a finished card is not merged into")
        work.save_item(card(id="w00000000m09", owner="ravi", state="for_review",
                            title="Sweep the sheets for background fill"))
        before = len(work.items())
        twin = work._open_twin("ravi", work.merge_key("Sweep the sheets for background fill"))
        check(twin is None,
              "a card already finished and waiting on him is never a merge target")

        print("what does not merge")
        work.save_item(card(id="w0000000e0003", recommend=REC, follow_ups=[
            {"title": "Record the crow landing", "owner": "sam", "level": "task", "tier": 1,
             "first_action": "x", "why": "a different person"}]))
        work.api_post("/api/work/accept", {"id": "w0000000e0003"})
        check(len([i for i in work.items() if i.get("parent") == "w0000000e0003"]) == 1,
              "the same subject for a different person is a different piece of work")
        work.save_item(card(id="w0000000e0004", owner="rin", state="accepted",
                            title="Paint the dusk sky", follow_ups=[]))
        work.save_item(card(id="w0000000e0005", recommend=REC, follow_ups=[
            {"title": "Paint the dusk sky", "owner": "rin", "level": "task", "tier": 1,
             "first_action": "x", "why": "again"}]))
        work.api_post("/api/work/accept", {"id": "w0000000e0005"})
        check(len([i for i in work.items() if i.get("parent") == "w0000000e0005"]) == 1,
              "a closed card is not a twin — work after a finished piece is new work")
        work.save_item(card(id="w0000000e0007", owner="rin", state="done",
                            title="Tune the rooster call", follow_ups=[]))
        work.save_item(card(id="w0000000e0008", recommend=REC, follow_ups=[
            {"title": "Tune the rooster call", "owner": "rin", "level": "task", "tier": 1,
             "first_action": "x", "why": "again"}]))
        work.api_post("/api/work/accept", {"id": "w0000000e0008"})
        check(len([i for i in work.items() if i.get("parent") == "w0000000e0008"]) == 1,
              "a card left in a state the page no longer writes cannot swallow new work either")

        print("the same work named twice in one result files once")
        work.save_item(card(id="w0000000e0006", recommend=REC, follow_ups=[
            {"title": "Shorten the dawn fade", "owner": "rin", "level": "task", "tier": 1,
             "first_action": "x", "why": "it drags"},
            {"title": "shorten the dawn fade", "owner": "rin", "level": "task", "tier": 1,
             "first_action": "x", "why": "and it drags at dusk too"}]))
        work.api_post("/api/work/accept", {"id": "w0000000e0006"})
        kids = [i for i in work.items() if i.get("parent") == "w0000000e0006"]
        check(len(kids) == 1 and "and it drags at dusk too" in kids[0]["ask"],
              "a result that names one piece of work twice files one card, carrying both asks")

        print("a follow-up says which card promised it")
        work.save_item(card(id="w0000000f0001", recommend=REC, follow_ups=[
            {"title": "Fade the title card out", "owner": "rin", "level": "task", "tier": 1,
             "first_action": "x", "why": "it cuts hard"}]))
        work.api_post("/api/work/accept", {"id": "w0000000f0001"})
        kid = [i for i in work.items() if i.get("parent") == "w0000000f0001"][0]
        check(kid["promised_by"] == "w0000000f0001"
              and kid["promised"]["title"] == "Fade the title card out",
              "what his yes covered is on the child, so doing it does not come back for a second yes")
        work.save_item(card(id="w0000000f0002"))
        work.api_post("/api/work/respond", {"id": "w0000000f0002", "message": "The dusk sky is flat."})
        stub_cli(reply("That is Rin's.",
                       '{"items": [{"title": "Repaint the dusk gradient", "owner": "rin", '
                       '"tier": 1, "first_action": "x", "why": "he said it is flat"}], '
                       '"move": "follow-up"}'))
        work._process_response(item("w0000000f0002"), org)
        kid = [i for i in work.items() if i.get("parent") == "w0000000f0002"][0]
        check("promised_by" not in kid,
              "work filed from a conversation was promised by nothing, so it comes back as new")
        for n in captures():
            os.remove(os.path.join(work.CAPTURES, n))

        print("only a question with an answer counts as waiting on him")
        deliverable = {"name": "The revised result", "evidence": [{"href": "/review/result"}]}
        work.save_item(card(id="w0000000a0001", tier=0, recommend={}, follow_ups=[], deliverable=deliverable))
        work.save_item(card(id="w0000000a0002", tier=0, recommend=REC, follow_ups=[], deliverable=deliverable))
        snap = work.snapshot()
        mine = {i["id"] for i in snap["items"] if work._in_his_list(i)}
        check("w0000000a0002" in mine and "w0000000a0001" in mine,
              "both are still on the page with their buttons")
        check(snap["waiting_on_you"] == 1,
              "the count is of cards with a recommendation and complete decision material")
        check(snap["unprepped"] == sum(1 for i in snap["items"]
                                       if work.work_reviewable(i, i.get("workflow_view"))
                                       and not work.work_preparation(i)["ready"]),
              "and the rest are counted separately rather than dropped")

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
    # These workflow fixtures stub model execution; use an enabled launch policy.
    from unittest.mock import patch
    with patch.object(work.execution, "launch_allowed", return_value=True):
        sys.exit(main())

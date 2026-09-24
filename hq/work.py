"""Tiny Farm HQ — how work originates.

The org used to be advice-only: a persona could tell Daniel what should happen
and then nothing did, because chat is read-only and no one but him could start
anything. That made him the bottleneck for every follow-up — the micromanagement
he is explicitly designing out of the company.

So every exchange in HQ chat is now read for the work it creates, and the work is
filed automatically. Nothing waits on his permission to *exist*. What waits on him
is calibrated to one question: how bad is it to get this wrong with nobody looking?

    tier 0  nothing to walk back (read, draft, analyse, render, run the suites)
            -> it happens immediately and he approves the RESULT, not the task
    tier 1  changes the repo, but git can revert it (docs, code behind tests)
            -> queued for a build session, which shows him the diff afterwards
    tier 2  hard to walk back or his taste to settle (ship, spend, delete,
            anything players see, any design direction) -> he says yes first

The rule that produced those tiers is the CEO's, 2026-09-02: "we should not delay
steps that have no downside waiting for human feedback", with the guardrail being
the risk of getting a task wrong without human review. docs/HOW_WORK_ORIGINATES.md
is the prose version; data/work_policy.json is the version this file reads, so the
norms can be edited without touching code.

This module owns its own files and one worker thread; server.py binds it in and
routes /api/work* here. It never blocks a chat reply — capture happens after.
"""
import execution

from contextlib import contextmanager
import fcntl
import tempfile
import hashlib
import datetime
import json
import os
import re
import subprocess
import threading
import time
import uuid

HOST = None          # the server module, injected by bind()
WORK = None          # data/work
CAPTURES = None      # data/captures — exchanges waiting to be read for work
POLICY_PATH = None

_LOCK = threading.Lock()

DEFAULT_POLICY = {
    "rule": ("Approval attaches to results, not to tasks. Work is filed without "
             "asking; only acting on it is gated, and only by how hard it is to "
             "walk back."),
    "tiers": {
        "0": {
            "name": "Just do it",
            "means": "Nothing to walk back — reading, drafting, analysing, rendering, running the suites.",
            "gate": "none; the result is what he reviews",
            "auto": True,
        },
        "1": {
            "name": "Do it, show the diff",
            "means": "Changes files, but git reverts it — doc edits, code behind tests, a new decision card.",
            "gate": "a build session does it and shows the diff afterwards",
            "auto": False,
        },
        "2": {
            "name": "Ask first",
            "means": "Hard to walk back or his taste to settle — shipping, spending, deleting, anything players see, any change of design direction.",
            "gate": "his yes, before anything happens",
            "auto": False,
        },
    },
    # His rule, 2026-09-11, after a question he attached to a card came back as
    # a tier-2 title waiting for his yes: a request to *think* is its own piece
    # of work, at the tier of thinking, and the thing being thought about is
    # filed only once the thinking has been accepted.
    "consider": ("A question from Daniel, or anything he asks the studio to consider, "
                 "look into, weigh, or think about, is tier-0 work: reading, analysing "
                 "and recommending, which nobody needs permission for. File the "
                 "consideration, owned by whoever holds the answer, with a first step "
                 "that produces a recommendation. Never file the action he is asking "
                 "about as if he had asked for it — that is filed later, at its own "
                 "tier, when he accepts the recommendation."),
    # How long he may be kept waiting for an answer to something he wrote on a
    # card. Past it the card stops being his move: docs/QUEUE_TO_ZERO.md §8.
    "reply_seconds": 30,
    "states": {
        "owed": ("He asked something on a card and no answer came within thirty "
                 "seconds, or the owner replied that the answer needs work. The "
                 "studio's move: it leaves his list, shows in the strip of what "
                 "is coming back to him, and returns to the top of his list when "
                 "the answer lands."),
        "prepping": ("Work that is hard to walk back, filed but not yet put to "
                     "him. The seat that owns it is writing the question — the "
                     "choice in his terms, the real options and what each costs, "
                     "and the answer recommended — and the card joins his list "
                     "the day that question is written. The studio's move, not "
                     "his."),
    },
}

# The promise the page makes him, in seconds. The file is the real one; this is
# what a machine with no policy file yet still honours.
REPLY_SECONDS = 30


def reply_seconds():
    try:
        got = int(policy().get("reply_seconds", REPLY_SECONDS))
    except Exception:
        return REPLY_SECONDS
    return got if got > 0 else REPLY_SECONDS


LEVELS = ("task", "story", "epic", "project", "goal")

# What a state means, in the order the Work page shows them. Two of them are not
# his move. `owed`: he asked something on a card, nobody answered within the
# thirty seconds, and the card left his list until the answer lands.
# `prepping`: work hard to walk back has been filed, and the seat that owns it
# is writing the question he will be asked — it reaches his list only once the
# question carries a recommended answer (S-17).
STATES = ("needs_approval", "for_review", "owed", "prepping", "doing",
          "waiting_session", "accepted", "dropped", "landed")

# The tier a follow-up files at when it names none (S-17, §5.3).
UNTIERED_FOLLOW = 1

# What a recommendation has to say before the card carrying it may ask him for
# a yes: the choice, the answer, the one reason that decides it, and the
# alternative he might reasonably prefer. Three of the four is a briefing he
# cannot act on without asking a question back.
REC_PARTS = ("question", "answer", "why", "instead")

# How many times the studio rewrites a question that comes back incomplete
# before it stops and says a person has to write this one. Without a stop, a
# seat that cannot answer the question loops on it for as long as HQ runs.
PREP_TRIES = 3


def bind(server_module, *, sanitize=True):
    """server.py hands us itself: org/personas, the CLI lock, the token-limit
    state from the intake queue. Keeps this file importable and testable on its
    own, and keeps server.py's diff to a handful of lines."""
    global HOST, WORK, CAPTURES, POLICY_PATH
    HOST = server_module
    WORK = os.path.join(HOST.DATA, "work")
    CAPTURES = os.path.join(HOST.DATA, "captures")
    POLICY_PATH = os.path.join(HOST.DATA, "work_policy.json")
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(CAPTURES, exist_ok=True)
    if not os.path.isfile(POLICY_PATH):
        _write_json(POLICY_PATH, DEFAULT_POLICY)
    if sanitize:
        _sanitize()


# ---------------------------------------------------------------------------
# storage
# ---------------------------------------------------------------------------

def _write_json(path, doc):
    tmp = path + ".tmp"
    with _LOCK:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)   # a half-written record must never be readable
    return doc


def _read_dir(d, *, strict=False):
    out = []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        if strict:
            raise
        return out
    for n in names:
        if not n.endswith(".json") or n.startswith("_"):
            continue
        try:
            record = HOST.load_json(os.path.join(d, n))
            if strict and (not isinstance(record, dict) or not record.get("id") or not record.get("state")):
                raise ValueError(f"Malformed work record: {n}")
            if d == WORK and isinstance(record, dict):
                record.setdefault("_revision", 0)
            out.append(record)
        except Exception:
            if strict:
                raise
            continue
    return out


def policy():
    try:
        return HOST.load_json(POLICY_PATH)
    except Exception:
        return DEFAULT_POLICY


def items(*, strict=False):
    got = _read_dir(WORK, strict=strict)
    got.sort(key=lambda i: i.get("created_ts", 0), reverse=True)
    return got


def _item_path(item_id):
    return os.path.join(WORK, f"{item_id}.json")


_MUTATION_THREADS = threading.RLock()
_MUTATION_LOCAL = threading.local()
_MUTATION_PID = os.getpid()


@contextmanager
def mutation_lock():
    """All work-record writes share the same reentrant, process-safe boundary."""
    global _MUTATION_PID, _MUTATION_THREADS, _MUTATION_LOCAL
    if _MUTATION_PID != os.getpid():
        _MUTATION_PID = os.getpid()
        _MUTATION_THREADS = threading.RLock()
        _MUTATION_LOCAL = threading.local()
    with _MUTATION_THREADS:
        if getattr(_MUTATION_LOCAL, "depth", 0):
            _MUTATION_LOCAL.depth += 1
            try:
                yield
            finally:
                _MUTATION_LOCAL.depth -= 1
            return
        identity = hashlib.sha256(os.fsencode(os.path.realpath(WORK))).hexdigest()
        lock_path = os.path.join(tempfile.gettempdir(), "tiny-farm-work-" + identity + ".lock")
        with open(lock_path, "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            _MUTATION_LOCAL.depth = 1
            try:
                yield
            finally:
                _MUTATION_LOCAL.depth = 0
                fcntl.flock(lock, fcntl.LOCK_UN)


def load_item(item_id):
    item = HOST.load_json(_item_path(item_id))
    item.setdefault("_revision", 0)
    return item


class RecordConflict(RuntimeError):
    def __init__(self, item_id, expected, actual):
        self.item_id, self.expected, self.actual = item_id, expected, actual
        super().__init__("This work card changed while the request was running. Reload it before trying again.")


def validate_revision(item):
    """Check a loaded record before any dependent mutation, under the shared lock."""
    with mutation_lock():
        try:
            with open(_item_path(item["id"]), encoding="utf-8") as source:
                current = json.load(source)
        except FileNotFoundError:
            current = {}
        if current and "_revision" not in item:
            raise RecordConflict(item["id"], None, current.get("_revision", 0))
        actual, expected = current.get("_revision", 0), item.get("_revision", 0)
        if type(actual) is not int or actual < 0 or type(expected) is not int or expected != actual:
            raise RecordConflict(item["id"], expected, actual)
        return actual


def save_item(item):
    """Compare-and-swap the durable revision; never merge a stale whole record."""
    with mutation_lock():
        # A response projection is not durable workflow state, even if a
        # caller round-trips a record fetched from an API.
        item.pop("workflow_view", None)
        path = _item_path(item["id"])
        actual = validate_revision(item)
        # Repository work stays in the build lane even if a producer files it as doing.
        if int(item.get("tier") or 0) == 1 and item.get("state") == "doing":
            item["state"] = "waiting_session"
        saved = dict(item, _revision=actual + 1)
        _write_json(path, saved)
        item["_revision"] = saved["_revision"]
        return item


def file_decision_revision(decision, feedback, ruled_at, submission_id):
    """File one durable owner handoff for a decision Daniel sent back.

    Decision cards predate work ownership, so an older card without an owner is
    triaged by the Chief of Staff.  ``decision_id`` and ``return_to_decision``
    make the return contract explicit: the decision stays open until its owner
    adds a reply after this ruling's timestamp.
    """
    decision_id = str(decision.get("id") or "")
    for item in items():
        if (item.get("decision_id") == decision_id
                and item.get("revision_submission_id") == submission_id):
            return item
    try:
        org = HOST.load_org()
    except Exception:
        org = {"employees": []}
    owner = str(decision.get("owner") or "")
    people = {e.get("id") for e in org.get("employees", [])}
    if owner not in people:
        try:
            seat = HOST.seat_for(owner)
            owner = seat.get("held_by", "") if seat else ""
        except Exception:
            owner = ""
    if owner not in people:
        owner = "claude"
    now = _now_iso()
    item = {
        "id": "w" + uuid.uuid4().hex[:11],
        "title": f"Revise decision {decision_id}: {decision.get('title') or 'untitled decision'}"[:160],
        "level": "task", "owner": owner, "tier": 1,
        "tier_reason": "Daniel asked for the decision to be revised before he chooses.",
        "ask": ("Revise this decision using Daniel's feedback, then add a reply to the "
                f"decision card {decision_id} so it returns to his queue.\n\n"
                f"Daniel's feedback:\n{feedback}")[:2400],
        "first_action": "Read the decision card and Daniel's feedback; revise the choices or evidence, then reply on the card.",
        "state": "waiting_session", "thread": owner, "source": "decision_revision",
        "source_message": feedback[:2000], "result": "", "started": "", "attempts": 0,
        "created": now, "created_ts": time.time(), "parent": decision_id,
        "decision_id": decision_id, "revision_feedback": feedback,
        "revision_submission_id": submission_id,
        "return_to_decision": {"id": decision_id, "after": ruled_at},
    }
    return save_item(item)


def _sanitize():
    """A restart mid-run leaves an item claiming to be in progress. Say the true
    thing instead: it never finished, and it is due to run again."""
    for it in items():
        if it.get("state") == "doing" and it.get("started"):
            it["state"] = "doing"
            it["started"] = ""     # the worker picks it up again
            save_item(it)
        # A prep that was in flight when HQ stopped never came back, so the try
        # it counted was never taken. Give it back, or a few restarts would
        # retire a question nobody ever wrote.
        elif it.get("prep_in_flight"):
            it.pop("prep_in_flight", None)
            it["prep_attempts"] = max(0, it.get("prep_attempts", 1) - 1)
            save_item(it)


# ---------------------------------------------------------------------------
# capture: every exchange gets read for the work it creates
# ---------------------------------------------------------------------------

def capture_exchange(to_id, message, reply, origin=None):
    """Called after a chat reply lands. Parks the exchange; the worker reads it.
    Deliberately does no model work inline — chat must never get slower because
    the company is taking notes.

    `origin` is the work item the exchange happened on, when it happened on a
    card rather than on the chat page. Without it the stories a conversation
    files land on the page with no visible connection to the thing he was
    reading when he asked for them — which reads as nothing having happened."""
    if not message or not reply:
        return None
    cid = uuid.uuid4().hex[:12]
    return _write_json(os.path.join(CAPTURES, f"{cid}.json"), {
        "id": cid,
        "to": to_id,
        "message": message,
        "reply": reply,
        "origin": origin or "",
        "created": _now_iso(),
        "created_ts": time.time(),
        "attempts": 0,
    })


def _now_iso():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def _roster_line(org):
    return "\n".join(
        f"- {e['id']}: {e['name']}, {e['title']} — {'; '.join(e['responsibilities'][:2])}"
        for e in org["employees"] if e["id"] != "daniel")


def _capture_prompt(org, cap):
    emp = next((e for e in org["employees"] if e["id"] == cap["to"]), None)
    who = f"{emp['name']} ({emp['title']})" if emp else cap["to"]
    pol = policy()
    return f"""You read exchanges inside Tiny Farm HQ and file the work they create.

THE EXCHANGE — Daniel (CEO & Game Director) with {who}:

Daniel: {cap['message'][:4000]}

{who}: {cap['reply'][:6000]}

Decide what follow-up work this exchange actually creates. Most exchanges create
none: a question answered is not work, an opinion offered is not work, and a
possibility raised that he did not take up is not work. File something only when
he asked for something to happen, agreed to something happening, or the reply
commits someone to a concrete next step.

Studio rule: {pol['rule']}

Tier each item by how bad it is to get wrong with nobody reviewing it first:
0 — {pol['tiers']['0']['means']}
1 — {pol['tiers']['1']['means']}
2 — {pol['tiers']['2']['means']}

A QUESTION IS ITS OWN WORK: {pol.get('consider') or DEFAULT_POLICY['consider']}
So "will the bloom animate, and could the player rise out of it?" files as
"Work out whether the player can rise out of the bloom, and recommend" at tier
0 — never as "Raise the player out of the bloom" at tier 2. If the exchange
already contains the answer and he has not taken it up, it files nothing.

Pick the owner from this roster by id — the person whose job it actually is:
{_roster_line(org)}

Reply with raw JSON and nothing else (no prose, no code fence):
{{"items": [{{"title": "short and plain", "level": "task|story|epic|project|goal", "owner": "<roster id>", "ask": "one sentence in Daniel's own terms", "first_action": "the single next concrete step, specific enough to just do", "tier": 0, "tier_reason": "why that tier"}}]}}

TITLES: Daniel reads the queue title-first, so a title is read with nothing around it to settle what it means: no ticket IDs, and no verb that could mean its own opposite. "Hold the foley session" was read as both delay it and run it. Prefer the longer unambiguous verb — "Take the foley session off the schedule". The ask and first_action below are read by the agent that does the work, so write those for efficiency. A title must survive four tests, which are the shapes of every writing call Daniel has actually made (docs/writing_rulings.json holds them, docs/WRITING.md holds the principle, and the commit-msg hook and tools/check_writing.py judge against both): (1) no internal term where the thing has a plain name — say where it came from, not provenance; the four test suites, not the suites; recorded, not stamped; (2) no metaphor standing where the fact should be — "a frame she would feel" says nothing, "won't make the tablet stutter" says it; (3) no mechanism where the symptom belongs — he wants to know the game stutters, not that a budget was exceeded; (4) no name or pronoun he has not been given in that same sentence. Do not treat those examples as a banned list: a word wrong in one sentence is right in another, and the rule is the principle, not the vocabulary. Say the literal thing.

{{"items": []}} if this exchange created no work. Be strict: a wrongly filed item
costs him attention, which is the thing this system exists to protect."""


def _parse_items(raw):
    """The model is asked for bare JSON; accept the usual near-misses too."""
    txt = (raw or "").strip()
    if txt.startswith("```"):
        txt = re.sub(r"^```[a-z]*\n?|```$", "", txt).strip()
    start, end = txt.find("{"), txt.rfind("}")
    if start < 0 or end <= start:
        return []
    try:
        doc = json.loads(txt[start:end + 1])
    except Exception:
        return []
    out = []
    for raw_item in (doc.get("items") or [])[:6]:
        title = str(raw_item.get("title") or "").strip()
        if not title:
            continue
        try:
            tier = int(raw_item.get("tier", 2))
        except Exception:
            tier = 2
        level = str(raw_item.get("level") or "task").lower()
        out.append({
            "title": title[:160],
            "level": level if level in LEVELS else "task",
            "owner": str(raw_item.get("owner") or "claude"),
            "ask": str(raw_item.get("ask") or "")[:600],
            "first_action": str(raw_item.get("first_action") or "")[:600],
            # Unknown tier means unknown blast radius: that is a 2, never a 0.
            "tier": tier if tier in (0, 1, 2) else 2,
            "tier_reason": str(raw_item.get("tier_reason") or "")[:300],
        })
    return out


# The CEO's rule, 2026-09-03: an approval must show its own consequence before
# he decides — "it would be better if it already knows what it would build if
# this is accepted and can show me". So a finished result carries the one piece
# of work its acceptance would start, worked out in the same call that produced
# the result (no extra tokens) and shown on the card before he presses anything.
#   key absent  -> nobody has been asked yet; the worker backfills it
#   {}          -> asked, and nothing follows: accepting simply closes it
#   {...}       -> exactly what accepting will file, in full, in advance
FOLLOW_MARK = "---WHAT FOLLOWS---"

RECOMMEND_NOTE = """If your result leaves a real choice that is his to make, you must recommend an
answer — his yes has to settle something. Ending on an open question and then
offering him an accept button is a decision point that decides nothing, which
is exactly what he has told us not to build. Add:

 "recommend": {"question": "the choice, in one line and in his terms", "answer": "what you recommend he does", "why": "the one reason that decides it", "instead": "the alternative he might reasonably prefer, named honestly"}

and make the items above the work that carries that recommendation out, so that
accepting the card IS taking it. Leave "recommend" out entirely when the result
raises no choice — a manufactured question costs him more than a missing one."""

AMEND_NOTE = (
    "\nIf what you have just said changes what this card itself is — its title,\n"
    "what it is asking for, or the next step — add an \"amend\" object saying what\n"
    "it should now read. Use it when the card has genuinely moved on, not to\n"
    "reword it.\n"
)

# His rule, 2026-09-11: a comment on a card is not a verdict, and he should not
# have to pick the path it takes. The owner reads it and makes one of three
# moves, named in the same call that writes the reply, so the card can say
# which happened:
#   answer     the comment was a question or a decision; the reply settles it
#   revise     the comment changes what the result should be; the owner extends
#              the existing result (never starts over) and it comes back for
#              his verdict again
#   follow-up  the comment is really new work, for this owner or another seat;
#              it is filed now, linked to this card, and this card stands
#   needs-work the answer is not at hand: the owner says so in one line and the
#              card hands back to the studio instead of holding him there
#              (docs/QUEUE_TO_ZERO.md §8)
MOVES = ("answer", "revise", "follow-up", "needs-work")
MOVE_NOTE_OPEN = """
WHICH MOVE YOU ARE MAKING: add "move" to the block — one of
  "answer"     — what he wrote is a question or a call to make, and your reply
                 settles it. Nothing else changes.
  "revise"     — what he wrote changes what this result should be. Say in your
                 reply what you will change, and the studio has you extend the
                 result you already produced — not redo it — and brings it back
                 to him. A comment that finds fault with the result is a revise
                 unless you can show the result already does what he asked.
  "follow-up"  — what he wrote is really a new piece of work, for you or for
                 someone else on the roster. Name it in "items" with its owner;
                 it is filed the moment you reply, linked to this card, and this
                 card stays as it is. Use it for anything that is not this
                 card's job.
One move per reply. If he asked a question AND wants a change, the change is the
move ("revise") and the answer goes in your reply.
"""
MOVE_NOTE_CLOSED = """
WHICH MOVE YOU ARE MAKING: this card is closed, so add "move" to the block as
one of
  "answer"     — what he wrote is a question or a remark, and your reply settles it.
  "follow-up"  — what he wrote is really a new piece of work. Name it in "items"
                 with its owner; it is filed the moment you reply, linked to
                 this card.
"""
# Added to either note when the card is sitting in his list while he waits for
# this reply. docs/QUEUE_TO_ZERO.md §8: he is never kept waiting past thirty
# seconds, so an owner who cannot answer now says so and hands the card back
# rather than holding him there.
MOVE_NOTE_LATE = """
  "needs-work"  — you cannot answer him now: the answer needs reading, building
                 or a call you are not in a position to make in this reply. Say
                 that in ONE line, name what you will do, and stop. The card
                 leaves his list, he moves straight on to the next question, and
                 it comes back to him when the answer does. Never use this to
                 buy time on something you could answer here.

He is looking at this card with a clock running and has THIRTY SECONDS to give
you. Answer in place if the answer is at hand; otherwise make your move
"needs-work" in one line. A long reply that arrives late is worth less to him
than a short one that arrives now.
"""
# Added instead, once the card has handed back. The wait is over, so there is
# nothing left to buy by saying the answer needs work — this reply is the
# answer, and it is what puts the card back in front of him.
MOVE_NOTE_OWED = """
HE HAS STOPPED WAITING FOR THIS ONE. The card left his list when nobody
answered in thirty seconds, and it is listed to him as coming back. Take the
time you need, do the reading the answer wants, and answer him properly: this
reply is what returns the card to the top of his list, so there is no move here
that defers it again.
"""


def _clean_follow(raw, org, fallback_owner):
    if not isinstance(raw, dict):
        return None
    title = str(raw.get("title") or "").strip()
    if not title:
        return None
    # S-17, docs/QUEUE_TO_ZERO.md §5.3: a follow-up that names no tier is tier 1,
    # never 2. Tier 2 is "ask him first", so defaulting to it spends his
    # attention on the model's silence rather than on any judged risk. What the
    # work actually turned out to be is decided by the checker reading the diff.
    try:
        tier = int(raw.get("tier", UNTIERED_FOLLOW))
    except Exception:
        tier = UNTIERED_FOLLOW
    level = str(raw.get("level") or "task").lower()
    owner = str(raw.get("owner") or "").strip()
    if not any(e["id"] == owner for e in org["employees"]):
        owner = fallback_owner
    return {
        "title": title[:160],
        "owner": owner,
        "level": level if level in LEVELS else "task",
        "tier": tier if tier in (0, 1, 2) else UNTIERED_FOLLOW,
        "first_action": str(raw.get("first_action") or "")[:600],
        "why": str(raw.get("why") or "")[:300],
    }


def _follow_doc(tail):
    """The JSON object a reply ends with, or None if there is not one. Kept
    apart from reading it because the prep worker needs the raw
    `recommend` — including a half-written one, which is exactly what it has to
    name back to its author."""
    txt = (tail or "").strip()
    if not txt or txt.upper().startswith("NONE"):
        return None
    if txt.startswith("```"):
        txt = re.sub(r"^```[a-z]*\n?|```$", "", txt).strip()
    start, end = txt.find("{"), txt.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        doc = json.loads(txt[start:end + 1])
    except Exception:
        return None
    return doc if isinstance(doc, dict) else None


def _parse_follows(tail, org, fallback_owner):
    """(everything accepting would file, an amendment to this item or None, the
    recommendation his yes takes or None).

    One result can imply several pieces of work — a reply naming a fix for the
    tool, a sweep for the artist and a pipeline check for the engineer is three
    items, and filing only the first would quietly drop two. Four is the cap:
    past that it is a plan, and a plan is its own item."""
    doc = _follow_doc(tail)
    if doc is None:
        return [], None, None, None
    raw = doc.get("items")
    if raw is None and doc.get("title"):
        raw = [doc]                      # a lone object is still one item
    got = [_clean_follow(r, org, fallback_owner) for r in (raw or [])[:4]]
    amend = doc.get("amend")
    if isinstance(amend, dict):
        amend = {k: str(amend[k])[:600].strip()
                 for k in ("title", "ask", "first_action") if amend.get(k)}
        if amend.get("title"):
            amend["title"] = amend["title"][:160]
    else:
        amend = None
    # A choice he is being asked to make arrives with the answer proposed, so
    # that accepting the card settles it. A card that ends on an open question
    # and offers him an accept button decides nothing.
    rec = doc.get("recommend")
    if isinstance(rec, dict) and str(rec.get("answer") or "").strip():
        rec = {k: str(rec.get(k) or "").strip()[:400]
               for k in ("question", "answer", "why", "instead")}
    else:
        rec = None
    move = str(doc.get("move") or "").strip().lower().replace("_", "-")
    if move == "followup":
        move = "follow-up"
    return [g for g in got if g], (amend or None), rec, (move if move in MOVES else None)


def evidence_id(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


WORKFLOW_VERSION = 1
ACTION_LEASE_SECONDS = 30 * 60
TERMINAL_STATES = frozenset(("landed", "accepted", "dropped", "done"))


def _iso_seconds(value):
    if not value:
        return 0.0
    try:
        return datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except (TypeError, ValueError, OverflowError):
        return 0.0


def action_key(item_id, kind, input_id=""):
    """A stable identity for one action on one immutable input."""
    return "act_" + hashlib.sha256(f"{item_id}\0{kind}\0{input_id}".encode()).hexdigest()[:20]


def _workflow(item):
    workflow = item.setdefault("workflow", {"version": WORKFLOW_VERSION, "actions": [],
                                             "blockers": [], "candidates": [],
                                             "verifications": [], "integrations": []})
    if workflow.get("version") != WORKFLOW_VERSION:
        raise ValueError("Unknown work workflow version")
    for key in ("actions", "blockers", "candidates", "verifications", "integrations"):
        workflow.setdefault(key, [])
    return workflow


def ensure_action(item, kind, *, input_id="", owner=None, summary="", priority="ordinary",
                  created_at=None, wake=None):
    """Persist an action once. Call only from an explicit transition, never a GET."""
    with mutation_lock():
        fresh = load_item(item["id"])
        workflow = _workflow(fresh)
        ident = action_key(fresh["id"], kind, input_id)
        action = next((a for a in workflow["actions"] if a.get("id") == ident), None)
        if action is None:
            action = {"id": ident, "type": kind, "input_id": input_id,
                      "owner": owner or fresh.get("owner") or "claude",
                      "summary": summary, "priority": priority,
                      "created_at": created_at or _now_iso(), "state": "open"}
            if wake:
                action["wake"] = wake
            workflow["actions"].append(action)
            save_item(fresh)
        item.clear()
        item.update(fresh)
        return dict(action)


def ensure_blocker(item, kind, *, input_id="", owner=None, reason="", files=(),
                   action_id="", wake=None):
    """Record a stable cause without refreshing its first-seen timestamp."""
    with mutation_lock():
        fresh = load_item(item["id"])
        workflow = _workflow(fresh)
        ident = "blk_" + hashlib.sha256(f"{fresh['id']}\0{kind}\0{input_id}".encode()).hexdigest()[:20]
        blocker = next((b for b in workflow["blockers"] if b.get("id") == ident), None)
        if blocker is None:
            blocker = {"id": ident, "type": kind, "input_id": input_id,
                       "owner": owner or fresh.get("owner") or "claude",
                       "reason": reason, "files": sorted(set(files)),
                       "action_id": action_id, "observed_at": _now_iso(), "state": "open"}
            if wake:
                blocker["wake"] = wake
            workflow["blockers"].append(blocker)
            save_item(fresh)
        item.clear()
        item.update(fresh)
        return dict(blocker)


def claim_action(item, action_id, claim_id, *, now=None, lease_seconds=ACTION_LEASE_SECONDS):
    """Idempotent claim; an expired lease can be recovered by a new claimant."""
    with mutation_lock():
        fresh = load_item(item["id"])
        action = next((a for a in _workflow(fresh)["actions"] if a.get("id") == action_id), None)
        if action is None:
            raise KeyError(action_id)
        instant = time.time() if now is None else float(now)
        claim = action.get("claim") or {}
        if claim.get("id") == claim_id and claim.get("expires_at", 0) > instant:
            item.clear(); item.update(fresh)
            return dict(action)
        if claim.get("expires_at", 0) > instant or action.get("state") == "done":
            return None
        action["claim"] = {"id": claim_id, "claimed_at": instant,
                           "expires_at": instant + lease_seconds}
        action["state"] = "running"
        save_item(fresh)
        item.clear(); item.update(fresh)
        return dict(action)


def finish_action(item, action_id, claim_id, *, state="done"):
    if state not in ("done", "open", "blocked"):
        raise ValueError("Invalid action state")
    with mutation_lock():
        fresh = load_item(item["id"])
        action = next((a for a in _workflow(fresh)["actions"] if a.get("id") == action_id), None)
        if action is None:
            raise KeyError(action_id)
        if action.get("state") == state and not action.get("claim"):
            item.clear(); item.update(fresh)
            return dict(action)
        if (action.get("claim") or {}).get("id") != claim_id:
            raise RecordConflict(item["id"], claim_id, (action.get("claim") or {}).get("id"))
        action["state"] = state
        action.pop("claim", None)
        action["finished_at" if state == "done" else "updated_at"] = _now_iso()
        save_item(fresh)
        item.clear(); item.update(fresh)
        return dict(action)


def work_view(item, repo_facts=None, now=None):
    """Pure canonical work/eligibility projection for cards, queue and dashboard.

    repo_facts may contain blocked_files, cost_reason, active_session and head.
    No filesystem or clock reads occur when `now` is supplied.
    """
    facts = repo_facts or {}
    instant = time.time() if now is None else float(now)
    workflow = item.get("workflow") or {}
    actions = [dict(action) for action in workflow.get("actions") or []]
    active_actions = [a for a in actions if a.get("state") != "done"]
    blocked_files = sorted(set(facts.get("blocked_files") or []))
    repair = str(item.get("repair_hold") or "")
    exhausted_repair = bool(repair and item.get("automatic_repairs", 0) >= 1)
    cost_reason = str(facts.get("cost_reason") or "")
    supervised_retry = exhausted_repair and not cost_reason and bool(facts.get("supervised_retry"))
    # A saved rebrief is a capacity hold, not a coding job. Once a reviewed
    # cap increase clears recorded spend, project the normal build again.
    if not cost_reason:
        active_actions = [a for a in active_actions if a.get("type") != "rebrief"]
    waiting = item.get("waiting_for") or {}
    pending = item.get("pending_landing") or item.get("pending_followups")
    patch = (item.get("attempt_outcome") or {}).get("patch_id") or ""
    candidate = (item.get("attempt_outcome") or {}).get("candidate") or {}
    candidate_base = candidate.get("base") or ((workflow.get("candidates") or [{}])[-1].get("base"))
    input_id = (patch or candidate.get("tree") or
                ((workflow.get("candidates") or [{}])[-1].get("id")) or
                ((actions or [{}])[-1].get("input_id")) or
                str(item.get("last_recorded_attempt") or "legacy"))
    if supervised_retry:
        # One explicit invocation gets a distinct action for this failed attempt.
        # Repeating a queue read must never mint another repair action.
        input_id = action_key(item["id"], "supervised_retry",
                              str(item.get("last_recorded_attempt") or input_id))
    terminal = item.get("state") in TERMINAL_STATES
    blocker = None
    if blocked_files:
        blocker = {"type": "code_conflict", "reason": facts.get("tree_reason") or
                   "The candidate overlaps uncommitted repository files.",
                   "files": blocked_files, "owner": item.get("owner") or "claude"}
    elif not terminal and candidate_base and facts.get("head") and candidate_base != facts["head"]:
        reason = "Local main changed since this candidate was checked; it needs fresh review and tests."
        if repair:
            reason += " Earlier gate: " + repair
        blocker = {"type": "stale_base", "reason": reason,
                   "files": [], "owner": item.get("owner") or "claude"}
    elif repair:
        blocker = {"type": "missing_evidence", "reason": repair, "files": [],
                   "owner": item.get("owner") or "claude"}
        if exhausted_repair:
            blocker["wake"] = "An explicit supervised retry of this card after reviewing the failed repair."
    elif cost_reason:
        blocker = {"type": "capacity", "reason": cost_reason, "files": [],
                   "owner": "claude", "wake": "A reviewed, bounded cost cap above the amount already spent."}
    elif pending:
        blocker = {"type": "recovery", "reason": "An interrupted transaction needs recovery.",
                   "files": [], "owner": "claude"}
    elif item.get("started") and not facts.get("active_session"):
        blocker = {"type": "recovery", "reason": "The previous session no longer has a live claim.",
                   "files": [], "owner": "claude"}
    elif waiting.get("reason") and facts.get("waiting_for_valid", True):
        blocker = {"type": "dependency", "reason": waiting["reason"],
                   "files": waiting.get("files") or [], "owner": item.get("owner") or "claude"}
    persisted_open = next((b for b in reversed(workflow.get("blockers") or [])
                           if b.get("state") == "open"), None)
    if blocker and persisted_open and persisted_open.get("type") == blocker["type"]:
        blocker = {**persisted_open, **blocker}
    elif not blocker and persisted_open:
        blocker = dict(persisted_open)
    stalled_transition = False
    if not terminal and not active_actions:
        if blocker and blocker["type"] in ("code_conflict", "stale_base", "missing_evidence", "dependency"):
            kind = "reconcile"
            summary = "Reconcile the candidate with current main and obtain fresh review and tests."
            priority = "reconciliation"
        elif blocker and blocker["type"] == "recovery":
            kind, summary, priority = "recover", "Recover the interrupted transaction.", "reconciliation"
        elif blocker and blocker["type"] == "capacity":
            kind, summary, priority = "rebrief", "Review a bounded usage-cap increase before more work starts.", "reconciliation"
        elif item.get("state") in ("for_review", "needs_approval"):
            kind, summary, priority = "decide", "Review the prepared result or decision.", "decision"
        elif item.get("state") == "prepping":
            kind, summary, priority = "prepare", "Prepare the question for Daniel.", "ordinary"
        elif item.get("state") == "owed":
            kind, summary, priority = "reply", "Answer the card's outstanding question.", "ordinary"
        else:
            kind = "build"
            summary = item.get("first_action") or "Continue the work."
            priority = "urgent" if item.get("urgent") else "retry" if item.get("resume") else "ordinary"
        proposed_id = action_key(item["id"], kind, input_id)
        if any(a.get("id") == proposed_id for a in actions):
            # A completed action cannot be claimed again under its old ID.
            # Recover the missing card transition once, without inventing an
            # infinite sequence of nominally new attempts.
            kind, summary, priority, input_id = (
                "recover", "Recover the completed action's missing card transition.",
                "reconciliation", proposed_id)
            proposed_id = action_key(item["id"], kind, input_id)
            if any(a.get("id") == proposed_id for a in actions):
                stalled_transition = True
                blocker = {"type": "recovery", "reason": "A completed recovery did not advance this card; inspect its transaction.",
                           "owner": "claude", "files": [], "wake": "operator review"}
        if not stalled_transition:
            active_actions = [{"id": proposed_id, "type": kind,
                           "input_id": input_id, "owner": ("daniel" if kind == "decide" else "claude" if kind == "rebrief" else item.get("owner") or "claude"),
                           "summary": summary, "priority": priority,
                           "created_at": item.get("finished") or item.get("created") or "",
                           "state": "open", "virtual": True}]
    if not terminal and not stalled_transition and blocker and blocker["type"] in ("code_conflict", "stale_base", "missing_evidence", "dependency") \
            and not any(a.get("type") in ("reconcile", "recover") for a in active_actions):
        active_actions.append({"id": action_key(item["id"], "reconcile", input_id),
                               "type": "reconcile", "input_id": input_id,
                               "owner": item.get("owner") or "claude",
                               "summary": "Reconcile the candidate with current main and obtain fresh review and tests.",
                               "priority": "reconciliation", "created_at": item.get("finished") or item.get("created") or "",
                               "state": "open", "virtual": True})
    if not terminal and not stalled_transition and blocker and blocker["type"] == "recovery" \
            and not any(a.get("type") == "recover" for a in active_actions):
        active_actions.append({"id": action_key(item["id"], "recover", input_id),
                               "type": "recover", "input_id": input_id, "owner": "claude",
                               "summary": "Recover the interrupted transaction before another build.",
                               "priority": "reconciliation", "created_at": item.get("started") or item.get("created") or "",
                               "state": "open", "virtual": True})
    if not terminal and blocker and blocker["type"] == "capacity" and not any(a.get("type") == "rebrief" for a in active_actions):
        active_actions.append({"id": action_key(item["id"], "rebrief", input_id),
                               "type": "rebrief", "input_id": input_id, "owner": "claude",
                               "summary": "Review a bounded usage-cap increase before more work starts.",
                               "wake": blocker["wake"], "priority": "reconciliation",
                               "created_at": item.get("finished") or item.get("created") or "",
                               "state": "open", "virtual": True})
    if facts.get("active_session") and not terminal:
        if not active_actions:
            active_actions = [{"id": action_key(item["id"], "build", input_id),
                               "type": "build", "input_id": input_id,
                               "owner": item.get("owner") or "claude", "summary": "The owner is working.",
                               "priority": "ordinary", "created_at": item.get("started") or "",
                               "state": "open", "virtual": True}]
        active_actions[0]["state"] = "running"
        active_actions[0]["claim"] = {"id": str(facts["active_session"]),
                                      "expires_at": instant + 1}
    for action in active_actions:
        if action.get("type") == "rebrief":
            action["owner"] = "claude"
            action["wake"] = "A reviewed, bounded usage cap above the amount already spent."
        claim = action.get("claim") or {}
        lease_live = claim.get("expires_at", 0) > instant
        running = lease_live and bool(facts.get("active_session")) and action.get("state") == "running"
        action["availability"] = ("running" if running else "waiting_event" if lease_live else "waiting_event" if
                                  action.get("type") in ("decide", "rebrief") else "blocked" if
                                  action.get("state") == "blocked" or
                                  (blocker and action.get("type") == "build") or
                                  (blocker and blocker["type"] == "capacity" and action.get("type") != "rebrief") else
                                  "waiting_event" if exhausted_repair and not supervised_retry else "runnable")
        if claim and not running:
            action["lease_expired"] = not lease_live
        action["age_seconds"] = max(0, int(instant - _iso_seconds(action.get("created_at")))) if _iso_seconds(action.get("created_at")) else 0
        action["priority_reason"] = ("Main or a release gate is at risk." if action.get("priority") == "urgent" else
                                     "Finishes reviewed work before new starts." if action.get("priority") == "reconciliation" else
                                     "An earlier attempt has reusable work." if action.get("priority") == "retry" else
                                     "Ordinary work ages ahead of newer work.")
    priority_order = {"urgent": 0, "reconciliation": 1, "retry": 2, "ordinary": 3, "decision": 4}
    active_actions.sort(key=lambda a: (priority_order.get(a.get("priority"), 3),
                                       str(a.get("created_at") or ""), a.get("id") or ""))
    completed_actions = [a for a in actions if a.get("state") == "done"]
    for action in completed_actions:
        action["availability"] = "terminal"
        action["age_seconds"] = 0
    all_actions = sorted(active_actions + completed_actions,
                         key=lambda a: (str(a.get("finished_at") or a.get("updated_at") or
                                            a.get("created_at") or ""), a.get("id") or ""))
    next_action = next((a for a in active_actions if a["availability"] == "running"), None)
    if next_action is None:
        next_action = next((a for a in active_actions if a["availability"] == "runnable"), None)
    if next_action is None and active_actions:
        next_action = active_actions[0]
    if terminal:
        phase = item.get("state")
    elif next_action and next_action["availability"] == "running":
        phase = "working"
    elif next_action and next_action["type"] in ("reconcile", "recover", "rebrief"):
        phase = "reconciliation"
    elif item.get("state") == "for_review":
        phase = "review"
    elif item.get("state") == "prepping":
        phase = "preparation"
    elif item.get("state") == "owed":
        phase = "reply"
    elif item.get("state") == "needs_approval":
        phase = "decision"
    else:
        phase = "ready"
    availability = "terminal" if terminal else (next_action or {}).get("availability") or "waiting_event"
    latest = max((str(a.get("finished_at") or a.get("updated_at") or a.get("created_at") or "") for a in actions), default="")
    last_moved = max(latest, str(item.get("finished") or ""), str(item.get("started") or ""), str(item.get("created") or ""))
    completed = item.get("completion") or {}
    landed_sha = completed.get("sha") or (item.get("landed") or {}).get("sha") or ""
    ci = workflow.get("ci") or {}
    shipped = {"landed_sha": landed_sha,
               "ci_confirmed": bool(landed_sha and ci.get("confirmed") and ci.get("commit_sha") == landed_sha)}
    candidate_status = ("landed" if shipped["landed_sha"] else
                        "stale" if candidate_base and facts.get("head") and candidate_base != facts["head"] else
                        "held" if blocker else "reviewed" if (item.get("check") or {}).get("verdict") == "pass" else
                        "unverified" if candidate else "none")
    return {"version": WORKFLOW_VERSION, "phase": phase, "availability": availability,
            "next_action": next_action, "actions": all_actions, "blocker": blocker,
            "last_moved": last_moved, "candidate_status": candidate_status,
            "shipped_evidence": shipped}


def attempt_outcome(text, error="", limited=False):
    body, _, tail = (text or "").partition(FOLLOW_MARK)
    doc = _follow_doc(tail) or {}
    outcome = doc.get("outcome") if isinstance(doc, dict) else None
    status = outcome.get("status") if isinstance(outcome, dict) else "unknown"
    reason = str(outcome.get("reason") or "") if isinstance(outcome, dict) else ""
    try:
        envelope = json.loads(body)
    except (ValueError, TypeError):
        envelope = None
    if error or limited:
        status, reason = "unfinished", error or "The model allowance ended before completion."
    elif not body.strip() or isinstance(envelope, dict):
        status, reason = "unknown", "No usable result was returned."
    if status not in ("complete", "blocked", "unfinished"):
        status, reason = "unknown", reason or "The owner did not record whether the work finished."
    return {"version": 1, "status": status, "reason": reason,
            "result_id": evidence_id(body.strip())}


def completion_assessment(item):
    attempt = item.get("attempt_outcome") or {}
    completion = item.get("completion") or {}
    if completion.get("version") == 1 and completion.get("attempt_id") == attempt.get("id"):
        return "completed", "Completion was verified and recorded."
    if item.get("repair_hold"):
        return "verification_pending", item["repair_hold"]
    if attempt.get("version") != 1:
        return "verification_pending", "This older result needs completion verified."
    if attempt.get("status") != "complete":
        return "verification_pending", attempt.get("reason") or "The owner has not finished the work."
    check = item.get("check") or {}
    if (check.get("verdict") != "pass" or check.get("findings") or check.get("read") is not True
            or check.get("complete") is not True or check.get("attempt_id") != attempt.get("id")):
        return "verification_pending", "The result needs a clean check of this attempt."
    if attempt.get("result_id") != evidence_id(item.get("result", "")):
        return "verification_pending", "The result changed after it was checked."
    if not attempt.get("landing_verified"):
        return "verification_pending", ((item.get("diff") or {}).get("why_not_landed")
                                         or "The current changes still need landing evidence.")
    return "ready_to_apply", "Completion was verified; recording the landing remains."


def queue_one_repair(item):
    check = item.get("check") or {}
    attempt = item.get("attempt_outcome") or {}
    if check.get("verdict") not in ("concerns", "fail") and not check.get("findings"):
        return False
    if attempt.get("status") in ("blocked", "unknown") or check.get("escalates"):
        item["repair_hold"] = ((item.get("diff") or {}).get("why_not_landed")
                               if check.get("read") is True and check.get("verdict") == "fail"
                               else None) or attempt.get("reason") or "The owner needs a dependency or decision before continuing."
        return False
    if item.get("automatic_repairs", 0) >= 1:
        item["repair_hold"] = "The repair still needs verification; the owner must resolve the remaining findings."
        return False
    item["automatic_repairs"] = 1
    item["repair_brief"] = check.get("summary", "") + "\n" + json.dumps(check.get("findings") or [])
    item.setdefault("attempt_history", []).append(dict(attempt))
    requeue_for_revision(item)
    # The checked drain also handles read-only repairs; the intake worker must not claim them.
    item["state"] = "waiting_session"
    save_item(item)
    return True


def result_deliverable(text):
    """The short name Daniel sees when reviewing a completed result.

    The agent's ask remains the durable instruction on the card.  This is a
    separate, deliberately small name for the thing that came back; it must
    never be inferred from an old ask because that can name work rather than
    the result Daniel is judging.  Evidence belongs to the existing readiness
    check and is intentionally not manufactured here.
    """
    _, _, tail = (text or "").partition(FOLLOW_MARK)
    raw = (_follow_doc(tail) or {}).get("deliverable")
    if not isinstance(raw, dict):
        return None
    name = str(raw.get("name") or "").strip()[:160]
    return {"name": name} if name else None


def _split_result(text, org, fallback_owner):
    """(the deliverable he reads, what accepting it would file or None if the
    reply never said, any amendment to the item itself, the recommendation his
    yes takes, the move a reply makes or None). The block is stripped from the
    result — it is machinery for the card, not part of the work."""
    raw = text or ""
    if FOLLOW_MARK not in raw:
        return raw.strip(), None, None, None, None
    body, _, tail = raw.partition(FOLLOW_MARK)
    got, amend, rec, move = _parse_follows(tail, org, fallback_owner)
    return body.strip(), got, amend, rec, move


def follow_ups(item):
    """Normalised: cards written before one result could imply several stored a
    single object under `follow_up`."""
    got = item.get("follow_ups")
    if isinstance(got, list):
        return [g for g in got if isinstance(g, dict) and g.get("title")]
    one = item.get("follow_up")
    return [one] if isinstance(one, dict) and one.get("title") else []


def _asked_what_follows(item):
    return "follow_ups" in item or "follow_up" in item


_ARTICLE = re.compile(r"^(?:the|a|an)\s+")


def merge_key(title):
    """What makes two cards the same subject. Capitals, punctuation and a
    leading article are not part of a subject: "Record the crow landing" and
    "The Record the crow landing." are one piece of work, and filing both is how
    three cards end up asking one person to read the same edit (§5.4)."""
    t = re.sub(r"[^a-z0-9 ]+", " ", (title or "").lower())
    t = re.sub(r"\s+", " ", t).strip()
    return _ARTICLE.sub("", t)


# The states a card can still be merged into: everything that is live work.
# Named as what counts rather than as what does not, so a card left in a state
# this file no longer writes — the queue holds a few, filed before the states
# had their present names — cannot quietly swallow new work.
OPEN_STATES = ("needs_approval", "for_review", "owed", "prepping", "doing",
               "waiting_session")
# Where a twin may be merged: only a card whose work has not run yet. Appending
# an ask to a card that is finished and sitting in Daniel's list would file work
# nobody will ever do — the run it would have joined is over (2026-09-21).
MERGEABLE_STATES = ("prepping", "doing", "waiting_session")


def _open_twin(owner, key, exclude_id=""):
    """A card of the same owner and the same subject whose work has not run
    yet, or None. A finished or closed card is not a twin: work that follows a
    finished piece is new work, and an ask appended to a card whose run is over
    is an ask nobody will ever carry out."""
    for other in items():
        if other.get("id") == exclude_id or other.get("owner") != owner:
            continue
        if other.get("state") not in MERGEABLE_STATES:
            continue
        if merge_key(other.get("title")) == key:
            return other
    return None


def recommendation_gaps(rec):
    """Which of the four parts a recommendation is missing, in reading order."""
    rec = rec if isinstance(rec, dict) else {}
    return [p for p in REC_PARTS if not str(rec.get(p) or "").strip()]


def has_recommendation(item):
    """True when the card carries a question he can act on without asking one
    back. Nothing without this may be counted as waiting on him (§5.2)."""
    return not recommendation_gaps(item.get("recommend"))


def work_preparation(item):
    """Return the recorded material Daniel needs before a work verdict."""
    missing = []
    deliverable = item.get("deliverable")
    if not isinstance(deliverable, dict) or not str(deliverable.get("name") or "").strip():
        missing.append("deliverable")
    evidence = deliverable.get("evidence") if isinstance(deliverable, dict) else None
    if not isinstance(evidence, list) or not any(
            isinstance(entry, dict) and str(entry.get("href") or entry.get("path") or "").strip()
            for entry in evidence):
        missing.append("evidence")
    question = ((item.get("recommend") or {}).get("question")
                if isinstance(item.get("recommend"), dict) else "")
    question = question or item.get("review_question")
    if not str(question or "").strip():
        missing.append("question")
    if item.get("recommendation_required") is not False:
        if not has_recommendation(item):
            missing.append("recommendation")
    elif not str(item.get("recommendation_reason") or "").strip():
        missing.append("recommendation_explanation")

    def concrete_follow_up(value):
        if not isinstance(value, dict):
            return False
        if not all(isinstance(value.get(key), str) and value[key].strip()
                   for key in ("title", "owner", "first_action")):
            return False
        return ("tier" not in value or
                type(value["tier"]) is int and value["tier"] in (0, 1, 2))

    if "follow_ups" in item:
        values = item["follow_ups"]
        consequences = isinstance(values, list) and all(concrete_follow_up(v) for v in values)
        if "follow_up" in item:
            consequences = consequences and concrete_follow_up(item["follow_up"])
    elif "follow_up" in item:
        consequences = concrete_follow_up(item["follow_up"])
    else:
        consequences = False
    if not consequences:
        missing.append("consequences")
    labels = {
        "deliverable": "a short name for the deliverable",
        "evidence": "inspectable evidence for that deliverable",
        "question": "the specific question for Daniel",
        "recommendation": "the owner's recommendation",
        "recommendation_explanation": "why no recommendation is appropriate",
        "consequences": "what Daniel's answer will do next",
    }
    return {"ready": not missing, "missing": missing,
            "missing_labels": [labels[code] for code in missing]}


def work_reviewable(item, workflow_view=None):
    """Canonical gate for whether the studio has actually handed back a verdict."""
    view = workflow_view or {}
    if item.get("state") not in HIS_STATES or _held_back(item):
        return False
    if (item.get("awaiting_reply") or item.get("repair_hold") or item.get("pending_landing")
            or item.get("pending_followups") or view.get("blocker")):
        return False
    shipped = view.get("shipped_evidence") or {}
    unlanded_code = (item.get("state") == "for_review" and item.get("tier") in (1, 2)
                     and not shipped.get("landed_sha"))
    return not unlanded_code


def work_ready_for_daniel(item, workflow_view=None, preparation=None):
    """Single readiness predicate shared by the Work page and verdict inbox."""
    prep = preparation if preparation is not None else work_preparation(item)
    return work_reviewable(item, workflow_view) and prep["ready"]


def _file_item(fields, cap, org):
    owner = fields["owner"]
    if not any(e["id"] == owner for e in org["employees"]):
        owner = cap["to"]
    tier = fields["tier"]
    state = {0: "doing", 1: "waiting_session", 2: "needs_approval"}[tier]
    if cap.get("completion_key") and tier == 2:
        state = "prepping"
    return save_item({
        "id": cap.get("child_id") or "w" + uuid.uuid4().hex[:11],
        **({"completion_key": cap["completion_key"], "parent": cap["parent"]}
           if cap.get("completion_key") else {}),
        "title": fields["title"],
        "level": fields["level"],
        "owner": owner,
        "tier": tier,
        "tier_reason": fields["tier_reason"],
        "ask": fields["ask"],
        "first_action": fields["first_action"],
        "state": state,
        "thread": cap["to"],
        "source": "chat",
        "source_message": cap["message"][:2000],
        "result": "",
        "started": "",
        "attempts": 0,
        "created": _now_iso(),
        "created_ts": time.time(),
    })


def file_automatic(fields, source_ref):
    """File one machine-detected repair, once, and put it ahead of routine work."""
    org = HOST.load_org()
    title = str(fields.get("title") or "").strip()[:160]
    owner = str(fields.get("owner") or "elena")
    existing = next((i for i in items() if i.get("source_ref") == source_ref), None)
    # A closed repair still consumes its run. Until GitHub finishes the next
    # run, the poller will keep seeing the old failure; that must not reopen
    # work which already landed.
    if existing is not None and existing.get("state") not in OPEN_STATES:
        return existing
    if existing is None:
        key = merge_key(title)
        existing = next((i for i in items()
                         if merge_key(i.get("title")) == key
                         and i.get("state") in MERGEABLE_STATES
                         # Once a session has begun, its brief is immutable.
                         # A later failed run is a later incident, not permission
                         # to make the worker solve a different failure mid-run.
                         and not i.get("started")
                         and not i.get("attempts")), None)
    if existing is not None:
        existing["source_ref"] = source_ref
        existing["source"] = "automatic"
        existing["urgent"] = True
        existing["owner"] = owner
        existing["thread"] = owner
        existing["ask"] = str(fields.get("ask") or existing.get("ask") or "")[:600]
        existing["first_action"] = str(
            fields.get("first_action") or existing.get("first_action") or "")[:600]
        existing["source_message"] = existing["ask"]
        existing["incident"] = {"kind": "ci_failure", "identity": source_ref,
                                "detected": existing.get("created") or _now_iso()}
        return save_item(existing)

    clean = {
        "title": title or "Repair the failed build on main",
        "level": str(fields.get("level") or "task"),
        "owner": owner,
        "tier": 1,
        "tier_reason": "A failed build on main blocks every release and is safe to repair without a product ruling.",
        "ask": str(fields.get("ask") or "")[:600],
        "first_action": str(fields.get("first_action") or "")[:600],
    }
    item = _file_item(clean, {"to": owner, "message": clean["ask"], "id": source_ref}, org)
    item["source_ref"] = source_ref
    item["source"] = "automatic"
    item["urgent"] = True
    item["incident"] = {"kind": "ci_failure", "identity": source_ref,
                        "detected": item.get("created") or _now_iso()}
    return save_item(item)


def _follows_spec(org, amendable=False, moves=None, wait="", completion=False):
    """`moves` is None for a result, "open" for a reply on a card that can still
    change, "closed" for a reply on a card that has been accepted or dropped.
    `wait` says where he is: "waiting" is a card in his list with the clock
    running, which adds the one move that ends the wait; "owed" is a card that
    already handed back, where the wait is over and this reply is the answer."""
    pol = policy()
    t0, t1, t2 = (pol["tiers"][k]["means"] for k in ("0", "1", "2"))
    amend = AMEND_NOTE if amendable else ""
    amend_field = (',\n "amend": {"title": ..., "ask": ..., "first_action": ...}'
                   if amendable else "")
    move_note = {"open": MOVE_NOTE_OPEN, "closed": MOVE_NOTE_CLOSED}.get(moves or "", "")
    allowed = {"open": ["answer", "revise", "follow-up"],
               "closed": ["answer", "follow-up"]}.get(moves or "", [])
    if allowed and wait == "waiting":
        move_note += MOVE_NOTE_LATE
        allowed.append("needs-work")
    elif allowed and wait == "owed":
        move_note += MOVE_NOTE_OWED
    move_field = ',\n "move": "%s"' % "|".join(allowed) if allowed else ""
    none_line = ("the single word NONE — if nothing more should\nhappen — or "
                 if not moves else
                 "NONE — only when nothing more should happen AND your move is "
                 "\"answer\" — or\n")
    outcome_field = (', "outcome": {"status": "complete|blocked|unfinished", "reason": "concrete reason if unfinished"}'
                     if completion else "")
    if completion:
        none_line = ""
    return f"""End your reply with this line exactly:

{FOLLOW_MARK}

and on the next line either {none_line}raw JSON, no fence and no prose, naming every piece of work his
acceptance should start. One result often implies several: a fix to a tool, a
sweep for the artist and a check in the pipeline are three items with three
owners, and naming only the first quietly drops the other two. Four at most —
past that it is a plan, and a plan is its own item.
{amend}{move_note}
{{"deliverable": {{"name": "the short name of the finished result Daniel reviews"}}, "items": [{{"title": "short and plain", "owner": "<roster id>", "level": "task|story|epic|project|goal", "tier": 0|1|2, "first_action": "the single next concrete step, specific enough to just do", "why": "one sentence: why this follows"}}]{amend_field}{move_field}{outcome_field}}}

`deliverable.name` is for Daniel, not a rewrite of the ask: name the finished
thing he can inspect in a few plain words. Keep the original ask in the card.

TITLES: Daniel reads the queue title-first, so a title is read with nothing around it to settle what it means: no ticket IDs, and no verb that could mean its own opposite. "Hold the foley session" was read as both delay it and run it. Prefer the longer unambiguous verb — "Take the foley session off the schedule". The ask and first_action below are read by the agent that does the work, so write those for efficiency. Never put these words in a title — each is exact inside this studio and empty three feet away: suite (say "test suite"), stamp (say "record"), prove or proof (say "test" or "evidence"), attestation, invariant, provenance, cadence, parity, plumbing, orphan, manifest, harness, hygiene, tier, trace, gate, instrument, surface. Say the literal thing. docs/glossary.json is the full list and the build fails on it.

Tier each by how bad it is to get wrong with nobody reviewing it first:
0 — {t0}
1 — {t1}
2 — {t2}
Unknown blast radius is a 2, never a 0. Each item goes to the person whose job
it actually is, by id, from this roster:
{_roster_line(org)}

{("Use items: [] when nothing follows; always include the outcome object." if completion else "NONE is the honest answer more often than not.")} Inventing work to look busy
costs him the attention this system exists to protect. But a gap you noticed
and did not file is a gap he has to remember for you — name it.

{RECOMMEND_NOTE}"""


# ---------------------------------------------------------------------------
# doing the tier-0 work
# ---------------------------------------------------------------------------

def _do_prompt(item, org):
    emp = next((e for e in org["employees"] if e["id"] == item["owner"]), None)
    name = emp["name"] if emp else "you"
    spec = _follows_spec(org, completion=True)
    # Anything he said on the card outranks the original brief — a second
    # attempt that ignores what he told you is not a second attempt.
    convo = _convo_lines(item, org)
    said = (f"""
WHAT HE HAS SAID ABOUT THIS ON THE CARD — this is the most recent word on it
and it overrides the brief above wherever they disagree:

{convo}
""" if convo else "")
    return f"""Daniel asked for this, and the studio norm is that you do reversible
work now and show him the result — you do not ask permission to start.

WORK ITEM: {item['title']}
What he asked for: {item['ask']}
The next step, which is yours to take now: {item['first_action']}

Take that step and reply with the deliverable itself — the draft, the analysis,
the recommendation, the answer — not a description of how you would do it. Read
the repository for anything you need; it is the source of truth and you have
read-only access to all of it. Plain language, no ticket IDs, no preamble. Keep it
as short as the work allows.

If the step genuinely cannot be finished read-only, say in one line what is
blocking it and exactly what you would need — that is a useful result too, and
{name} saying so beats a plausible guess.
{said}{revision_brief(item)}


Then say what your result implies, because Daniel decides whether to accept
it and he is entitled to know what his yes starts before he gives it.

{spec}"""


def revision_brief(item):
    """What a worker is told when it is extending its own earlier result rather
    than producing one. Shared with the drain, so the two lanes revise the same
    way. Empty unless the card is mid-revision."""
    if item.get("repair_brief"):
        return ("\nREPAIR YOUR OWN RESULT: " + item["repair_brief"]
                + "\nPreserve what still stands. Earlier result:\n" + item.get("result", "")[:6000])
    if not item.get("revising"):
        return ""
    prior = (item.get("prior_results") or [{}])[-1].get("result") or item.get("result") or ""
    return f"""

YOU ARE REVISING YOUR OWN EARLIER RESULT, NOT STARTING OVER. Daniel read what
you produced and wrote back (his words are above, and they are the brief for
this revision). Keep everything that still stands, change what he asked to have
changed, and reply with the whole result as it now stands — he reads the card
top to bottom, not a list of edits. Say near the top, in one line, what changed.

THE RESULT YOU GAVE HIM LAST TIME:
{prior[:6000]}
"""


def _memory_writer(name):
    """The bound main-tree server owns the sole durable-memory writer."""
    writer = getattr(HOST, name, None)
    return writer if callable(writer) else None


def forget_owner_memory(item):
    """Remove this card's attributed note without touching unrelated memory."""
    record = item.get("owner_memory")
    if not isinstance(record, dict):
        return False
    writer = _memory_writer("remove_attributed_staff_memory")
    if writer:
        writer(record.get("owner") or item.get("owner", ""), item["id"],
               record.get("attempt_id", ""))
    item.pop("owner_memory", None)
    return True


def replace_owner_memory(item, attempt_id, proposals):
    """Bind proposed lessons to the exact attempt, replacing any older one."""
    old = item.get("owner_memory")
    if old and old.get("attempt_id") != attempt_id:
        forget_owner_memory(item)
    cleaned = [{"source": p.get("source") if p.get("source") in ("owner", "checker") else "owner",
                "text": " ".join(str(p.get("text") or "").split())[:600]}
               for p in (proposals or [])
               if isinstance(p, dict) and str(p.get("text") or "").strip()]
    if cleaned:
        item["owner_memory"] = {"version": 1, "attempt_id": attempt_id,
                                "owner": item.get("owner", ""), "proposals": cleaned,
                                "committed": False}
    elif item.get("owner_memory", {}).get("attempt_id") == attempt_id:
        forget_owner_memory(item)


def commit_owner_memory(item):
    """Make the exact attempt's proposals durable, once acceptance is earned."""
    record = item.get("owner_memory")
    if not isinstance(record, dict) or record.get("committed"):
        return False
    writer = _memory_writer("commit_attributed_staff_memory")
    if not writer:
        return False
    writer(record.get("owner") or item.get("owner", ""), item["id"],
           record.get("attempt_id", ""), record.get("proposals") or [])
    record["committed"] = True
    return True


def supersede_item(item, canonical_id):
    """Close a duplicate and remove any lesson attributed to its result."""
    forget_owner_memory(item)
    item["state"] = "dropped"
    item["closed"] = _now_iso()
    item["superseded_by"] = canonical_id
    return save_item(item)


def withdraw_reverted_sprite(item_id, revert_step):
    """Close an unanswered sprite-edit request after its edit is undone."""
    if not re.fullmatch(r"w[a-f0-9]{11}", item_id or ""):
        return False
    with mutation_lock():
        try:
            item = load_item(item_id)
        except (OSError, ValueError):
            return False
        if item.get("state") not in OPEN_STATES:
            return False
        forget_owner_memory(item)
        item["state"] = "dropped"
        item["closed"] = _now_iso()
        item["withdrawn"] = {"at": item["closed"],
                             "reason": f"reverted at step {revert_step}"}
        save_item(item)
        return True


def requeue_for_revision(item):
    """The owner said "revise": the card goes back to the lane that can carry
    it out, carrying its earlier result, its diff and the conversation, so the
    second pass extends the first rather than repeating it.

    Tier 0 goes to the read-only worker; anything that changes files goes to
    the build queue, because the read-only worker would hand back a description
    of the change a second time. The earlier check is kept for the worker to
    read; the suites are not, because they described a tree that is about to
    change. The applied diff stays as it is: it is on the tree, and the
    revision builds on it."""
    # The next attempt replaces this attempt's proposal. This also removes a
    # committed note if a previously accepted result is explicitly reopened.
    forget_owner_memory(item)
    item["revising"] = True
    item["state"] = "doing" if int(item.get("tier") or 0) == 0 else "waiting_session"
    item["started"] = ""
    item.setdefault("prior_results", []).append({
        "at": item.get("finished", ""), "attempt": item.get("attempts", 0),
        "result": item.get("result", "")})
    # The card keeps showing the earlier result while the revision runs — a
    # blank card mid-revision reads as the work having been thrown away.
    prior = item.pop("check", None)
    if prior:
        item.setdefault("prior_checks", []).append(prior)
    item.pop("suites", None)
    item.pop("error", None)
    return item


def finish_revision(item):
    """Called when a revised result lands: the card counts it and stops saying
    it is mid-revision."""
    if item.pop("revising", None):
        item["revisions"] = int(item.get("revisions") or 0) + 1
    return item


def _run_cli(prompt, sys_prompt, tools, turns, timeout, model="", phase="", seat="", item=""):
    """One CLI call, with the intake queue's token-limit accounting. Returns
    (text, limited); the call's cost is appended to the token ledger, because
    work the company does on its own spends the same allotment Daniel does and
    nothing used to say how much."""
    if not execution.launch_allowed(item=item, phase=phase):
        return "", True
    with HOST.CHAT_LOCK:
        result = execution.run_session(prompt, sys_prompt, tools, model, HOST.REPO,
            timeout, turns, phase=phase or "work", seat=seat, item=item)
    if result.get("held"):
        return "", True
    if result.get("limited"):
        HOST.note_limit(result.get("error", ""), provider=result["provider"])
        return "", True
    HOST.record_model_usage(phase or "work", seat, result["model"], result.get("usage"), item)
    if result.get("error"):
        return result["error"], False
    HOST.clear_limit(provider=result["provider"])
    return result.get("text", ""), False


def _read_cli_json(stdout):
    """(the reply, what the call cost). A CLI that stops answering in JSON must
    not cost us the reply, so the raw text is the fallback and the price is
    simply unknown — an unpriced call is a record, not a silent zero."""
    raw = (stdout or "").strip()
    try:
        doc = json.loads(raw)
    except ValueError:
        return raw, None
    if not isinstance(doc, dict):
        return raw, None
    return str(doc.get("result") or "").strip(), HOST.usage_from_cli(doc)


# ---------------------------------------------------------------------------
# the worker
# ---------------------------------------------------------------------------

def _process_capture(cap, org):
    if not execution.launch_allowed():
        return False
    text, limited = _run_cli(_capture_prompt(org, cap),
                             "You file work items for a small game studio. You "
                             "answer with JSON only.", "", 1, 180,
                             phase="filing", seat=cap.get("to", ""))
    if limited:
        return False                      # tokens are dry; try again later
    for fields in _parse_items(text):
        child = _file_item(fields, cap, org)
        if cap.get("origin"):
            child["parent"] = cap["origin"]
            save_item(child)
    try:
        os.remove(os.path.join(CAPTURES, f"{cap['id']}.json"))
    except OSError:
        pass
    return True


def _process_item(item, org):
    if not execution.launch_allowed():
        return False
    # Read-only work uses the same checked completion path as changes.
    import drain
    record = drain.do_item(item, org, "reading-" + uuid.uuid4().hex[:12], lambda message: None)
    if record.get("held") or record.get("limited"):
        item["started"] = ""
        save_item(item)
        return False
    drain.write_back(item, record, False, "nothing changed", None, org)
    return True


def _convo_lines(item, org):
    """The card's conversation, as the owner will read it back."""
    out = []
    for m in item.get("conversation", []):
        if m.get("role") == "daniel":
            out.append(f"Daniel: {m.get('text', '')}")
        else:
            emp = next((e for e in org["employees"] if e["id"] == m.get("role")), None)
            out.append(f"{emp['name'] if emp else 'You'}: {m.get('text', '')}")
    return "\n\n".join(out)


CLOSED_STATES = ("accepted", "dropped")
# The two states that mean the card is sitting in his list wanting something
# from him — and so the two he can be kept waiting on.
HIS_STATES = ("needs_approval", "for_review")


def _live_state(item):
    """What the card really is. `owed` is not a kind of work, it is where a
    card waits out an answer it owes him, so its real state is the one it
    returns to when the answer lands."""
    if item.get("state") == "owed":
        return item.get("owed_from") or item.get("state")
    return item.get("state")


def _where_he_is(item):
    """Whether he is in front of this card waiting for the reply, has already
    been handed it back, or is nowhere near it — which is the difference
    between an owner who may say the answer needs work and one who may not."""
    if item.get("state") in HIS_STATES:
        return "waiting"
    if item.get("state") == "owed":
        return "owed"
    return ""


def _can_revise(item):
    """A revision extends a finished result. A card that is closed has nothing
    to reopen; one not yet done, or still in flight, is changed by amending its
    brief rather than by revising a result it does not have."""
    return _live_state(item) == "for_review"


def _response_prompt(item, org):
    result = (item.get("result") or "").strip()
    closed = _live_state(item) in CLOSED_STATES
    spec = _follows_spec(org, amendable=not closed,
                         moves="open" if _can_revise(item) else "closed",
                         wait=_where_he_is(item))
    last = next((m for m in reversed(item.get("conversation", []))
                 if m.get("role") == "daniel"), {})
    how = {"accept": "He wrote it while ACCEPTING the card, which is now closed.",
           "drop": "He wrote it while DROPPING the card, which is now closed.",
           "approve": "He wrote it while APPROVING the card, so the work is allowed "
                      "and queued; what he wrote is already part of its brief."
           }.get(last.get("with") or "", "")
    standing = ("This card is closed; nothing on it can be revised. "
                if closed else
                "This card has not been done yet; if what he wrote changes what it should "
                "be, amend it. " if not _can_revise(item) else "")
    return f"""Daniel is looking at this piece of work on HQ's Work page and has
written back to you about it. Answer him on the card, in your own voice.

WORK ITEM: {item['title']}
WHAT HE ASKED FOR: {item.get('ask', '')}
THE STEP THAT WAS YOURS TO TAKE: {item.get('first_action', '')}
{("THE RESULT YOU GAVE HIM:" + chr(10) + result[:6000]) if result else "This has not been done yet."}

THE CONVERSATION ON THIS CARD SO FAR:
{_convo_lines(item, org)}
{how}

Reply to his last message and nothing else. Plain language, short as the answer
allows, no preamble and no ticket IDs. The repository is read-only to you and is
the source of truth — check it rather than guessing.

{standing}If he is asking for something that can be settled by reading, drafting or
analysing, do it here and give him the answer: the studio norm is that you do
reversible work now rather than promising it. If what he wants changes the
result, say plainly what you will change and make your move "revise" — the
studio has you extend the result and bring it back to him; do not promise it in
prose and leave it there. If he has told you the result was wrong, say what you
now think is right, briefly, without apologising at length. If what he wants is
really someone else's job, say whose and file it as a follow-up.

A gap you name in prose is a gap he has to remember for you — so anything your
answer commits to belongs in the block below.

{spec}"""


# ---------------------------------------------------------------------------
# the thirty seconds
#
# What he wrote on a card used to wait for the worker's next fifteen-second
# tick and then for however long the model took, with the card locked and
# nothing on the page promising it would ever come back. docs/QUEUE_TO_ZERO.md
# §8: the reply starts the moment he sends it, and thirty seconds later — by
# the machine, not by his patience — the card stops being his move. It goes to
# `owed`, leaves his list, shows in the strip of what is coming back to him,
# and returns to the top of the list when the answer lands.
# ---------------------------------------------------------------------------

_REPLYING = set()            # item ids whose owner is writing back right now
_REPLY_LOCK = threading.Lock()


def _claim(item_id):
    with _REPLY_LOCK:
        if item_id in _REPLYING:
            return False
        _REPLYING.add(item_id)
        return True


def _release(item_id):
    with _REPLY_LOCK:
        _REPLYING.discard(item_id)


def ask_owner(item):
    """He has written on the card. The owner owes an answer and the clock is
    running from now — the card carries the deadline so the page can show the
    same clock the machine is keeping."""
    item["awaiting_reply"] = True
    item["asked_ts"] = time.time()
    item["reply_due_ts"] = item["asked_ts"] + reply_seconds()
    # Whatever brought it back last time is spent: this is a fresh question.
    item.pop("returned_at", None)
    item.pop("returned_ts", None)
    return item


def _hand_back(item, why=""):
    """The card becomes the studio's move. Called on a card in hand, by the
    deadline and by an owner who says the answer needs work. `owed_to` and
    `owed_since` are what the strip says out loud: who is coming back to him,
    and how long ago it left."""
    if item.get("state") == "owed" or item.get("state") in CLOSED_STATES:
        return item
    item["owed_from"] = item.get("state")
    item["state"] = "owed"
    item["owed_to"] = item.get("owner")
    item["owed_since"] = _now_iso()
    item["owed_ts"] = time.time()
    item["owed_why"] = why[:400]
    return item


def hand_back_if_late(item_id):
    """The deadline, fired against the card on disk. Does nothing if the answer
    beat it, if the card already handed back, or if it is not his move."""
    if not execution.launch_allowed():
        return None
    try:
        item = load_item(item_id)
    except Exception:
        return None
    if not item.get("awaiting_reply") or item.get("state") not in HIS_STATES:
        return None
    return save_item(_hand_back(item))


def _arm_deadline(item):
    """One timer per question. It is cheap, it fires once, and it does nothing
    if the answer arrived first — so an extra one costs nothing either. A card
    that is not in his list has no wait to end and gets no timer."""
    if not execution.launch_allowed() or item.get("state") not in HIS_STATES:
        return None
    left = max(0.0, (item.get("reply_due_ts") or 0) - time.time())
    t = threading.Timer(left, hand_back_if_late, args=(item["id"],))
    t.daemon = True
    t.start()
    return t


def start_reply(item_id):
    """Start the owner's reply now. The page returns from his POST while this
    runs; the worker's tick is no longer what decides when the studio answers."""
    if not execution.launch_allowed():
        return False
    if HOST.limited_until():
        return None           # no tokens: the worker picks it up when there are
    if not _claim(item_id):
        return None           # already being answered
    t = threading.Thread(target=_reply_now, args=(item_id,), daemon=True)
    t.start()
    return t


def _begin_answering(item):
    """Both halves of the promise, made where he pressed the button: the reply
    runs from now, and the deadline that ends his wait is armed whether or not
    the reply ever comes back."""
    _arm_deadline(item)
    return start_reply(item["id"])


def _reply_now(item_id):
    try:
        item = load_item(item_id)
        _process_response(item, HOST.load_org())
    except Exception:
        pass                  # the card keeps `awaiting_reply`; the worker retries
    finally:
        _release(item_id)


def _sweep_hand_backs():
    """The fallback for questions no live timer is watching — asked before a
    restart, or picked up by the worker rather than by his POST."""
    now = time.time()
    for it in items():
        if (it.get("awaiting_reply") and it.get("state") in HIS_STATES
                and now >= (it.get("reply_due_ts")
                            or (it.get("asked_ts") or now) + reply_seconds())):
            hand_back_if_late(it["id"])


def _process_response(item, org):
    """He asked something on a card; the owner answers on the card. Runs off the
    page's thread so his POST never blocks on a model call."""
    if not execution.launch_allowed():
        return False
    asked = item.get("asked_ts")
    raw, limited = _run_cli(_response_prompt(item, org),
                            HOST.build_system_prompt(org, item["owner"]),
                            "Read,Glob,Grep", HOST.MAX_TURNS, 300,
                            model=item.get("model") or HOST.seat_model(org, item["owner"]),
                            phase="reply", seat=item["owner"], item=item["id"])
    if limited:
        return False
    text, got, amend, rec, move = _split_result(raw, org, item["owner"])
    # Re-read: he may have typed again while the owner was thinking, and his
    # message must not be lost to a stale copy of the item.
    fresh = load_item(item["id"])
    # The answer he was owed has arrived. The card is his move again and comes
    # back at the top of his list, not at the place in it that it left from.
    was_owed = fresh.get("state") == "owed"
    if was_owed:
        fresh["state"] = fresh.pop("owed_from", None) or "for_review"
        for k in ("owed_to", "owed_since", "owed_ts", "owed_why"):
            fresh.pop(k, None)
        fresh["returned_at"] = _now_iso()
        fresh["returned_ts"] = time.time()
    # A move the card cannot make is read as the nearest one it can: a closed
    # card has nothing to revise, and a card with no result yet is changed by
    # amending it, which the block already carries.
    if move == "revise" and not _can_revise(fresh):
        move = "answer"
    # Nor can a card that is not in his list hand back — there is no wait to
    # end, and an accepted card must not reopen itself to say it needs longer.
    # A card that already handed back once cannot hand back on the answer it
    # came back with: that would put him off twice on the same question, which
    # is the thing the thirty seconds exists to stop.
    if move == "needs-work" and (was_owed or fresh.get("state") not in HIS_STATES):
        move = "answer"
    if move is None and got is not None:
        move = "answer"
    msg = {"role": item["owner"], "text": text or "(no reply came back)",
           "at": _now_iso()}
    if move:
        msg["move"] = move
    convo = fresh.get("conversation", [])
    convo.append(msg)
    fresh["conversation"] = convo
    # Answered — unless he wrote again while this was being written, in which
    # case the newer question is still unanswered and the card must keep saying
    # so. The reply now starts the moment he sends it, so two questions in quick
    # succession is an ordinary thing to do rather than a rare race.
    fresh["awaiting_reply"] = fresh.get("asked_ts") != asked
    # A conversation can change what the card is, not just what follows it. An
    # amendment is recorded rather than applied silently: he must be able to see
    # that the thing he is judging moved, and what it used to say.
    if amend:
        changed = {k: [fresh.get(k, ""), v] for k, v in amend.items()
                   if str(fresh.get(k, "")).strip() != v.strip()}
        if changed:
            fresh.setdefault("amendments", []).append({
                "at": _now_iso(), "by": item["owner"],
                "changed": {k: v[0] for k, v in changed.items()},
            })
            for k, v in changed.items():
                fresh[k] = v[1]
    fresh.pop("follow_up", None)
    if move == "follow-up" and got:
        # New work, filed now rather than on his acceptance: the owner has said
        # it is not this card's job, and a card that stands open holding
        # somebody else's work is how a follow-up waits on the wrong yes.
        filed = _file_follow_ups(fresh, got, org, cap_id="reply", message=text or "",
                                 lead=f"Filed from the conversation on “{fresh['title']}”.")
        msg["filed"] = [{"id": f["id"], "title": f["title"], "owner": f["owner"]}
                        for f in filed]
        fresh["follow_ups"] = []
        fresh["recommend"] = {}
    else:
        # What he was told may have changed what should follow, so the card
        # never keeps showing a consequence worked out before the conversation.
        fresh["follow_ups"] = got or []
        fresh["recommend"] = rec or {}
    if move == "revise":
        requeue_for_revision(fresh)
    if move == "needs-work":
        # He asked, the answer is not at hand, and the owner said so in one
        # line. That line is not an answer, so the card does not go back into
        # his list on the strength of it: it hands back and returns with the
        # answer, exactly as a card that ran out of time does. The answer is
        # still owed, so the card keeps asking for it and the worker writes it
        # on a later tick — this time with no clock on him and no move that
        # defers it again.
        _hand_back(fresh, why=text or "")
        fresh["awaiting_reply"] = True
        fresh.pop("returned_at", None)
        fresh.pop("returned_ts", None)
    save_item(fresh)
    if move in ("revise", "follow-up", "needs-work"):
        # The reply IS the work, or has filed it, or is one line saying it is
        # not done yet; reading any of those for work would file it twice.
        return True
    last_from_him = next((m["text"] for m in reversed(convo)
                          if m.get("role") == "daniel"), "")
    capture_exchange(fresh.get("thread") or fresh["owner"], last_from_him, text or "",
                     origin=fresh["id"])
    return True


# Where a follow-up was filed from, and whether the card it came from had
# already promised it. A card he accepted, and a card that landed under the
# arrival rule that stands in for his yes (S-16), both showed him what they
# would start; work an owner files mid-conversation was promised by nothing.
PROMISING = ("follow", "landed")


def _file_follow_ups(item, fus, org, cap_id, message, said="", lead=""):
    """File the follow-ups a card names, each at its own tier and linked back
    to the card. Returns the children. `said` is anything he attached, which
    becomes part of every child's brief; `lead` opens each child's ask when
    the message itself (a whole reply, say) is not the right opening.

    Three of the spawn rules live here (S-17, docs/QUEUE_TO_ZERO.md §5): one
    subject files one card, work hard to walk back is filed as a question to be
    written rather than as an ask in his list, and a follow-up the card promised
    says which card promised it."""
    started = []
    seen = {}            # subject -> the card this block already filed it into
    for fu in fus:
        completion_key = (evidence_id([item["id"], item.get("completion", {}).get("attempt_id"), fu])
                          if cap_id == "landed" else "")
        if completion_key:
            previous = next((child for child in items() if child.get("completion_key") == completion_key
                             or completion_key in child.get("completion_keys", [])), None)
            if previous:
                started.append({"id": previous["id"], "title": previous["title"],
                                "state": previous["state"], "owner": previous["owner"]})
                continue
        cap = {"to": item.get("thread") or item["owner"], "id": cap_id,
               "message": message[:2000]}
        if completion_key:
            cap.update(child_id="w" + completion_key[:11], completion_key=completion_key, parent=item["id"])
        ask = (f"{lead or message} {fu.get('why', '')}".strip())[:600]
        if said:
            ask += ("\n\nDaniel attached this, and it is part of the brief:\n" + said)
        owner = fu.get("owner") or item["owner"]
        key = merge_key(fu["title"])
        # §5.4, one subject one card: the same work named twice in one result,
        # or named again while the first card is still open, joins that card
        # instead of filing a twin for the same person to read twice.
        twin = seen.get((owner, key)) or _open_twin(owner, key, exclude_id=item["id"])
        if twin:
            if completion_key:
                twin.setdefault("completion_keys", []).append(completion_key)
            _merge_into(twin, item, fu, ask)
            started.append({"id": twin["id"], "title": twin["title"],
                            "state": twin["state"], "owner": twin["owner"],
                            "merged": True})
            seen[(owner, key)] = twin
            continue
        child = _file_item({
            "title": fu["title"],
            "level": fu.get("level", "task"),
            "owner": owner,
            "tier": fu.get("tier", UNTIERED_FOLLOW),
            "tier_reason": fu.get("why", "follows from this card"),
            "ask": ask,
            "first_action": fu.get("first_action", ""),
        }, cap, org)
        child["parent"] = item["id"]
        # §5.2: a follow-up that is hard to walk back is not an ask in his list.
        # It is a question somebody has to write first, and it waits with the
        # studio until that question carries a recommended answer.
        if child["tier"] == 2:
            child["state"] = "prepping"
            child["prepping_since"] = _now_iso()
            child["prep_attempts"] = 0
        # §5.1: his yes covers what the card said it would start, so a result
        # that does what was promised can land instead of coming back for a
        # second yes. What differs from the promise is what returns.
        if cap_id in PROMISING:
            child["promised_by"] = item["id"]
            child["promised"] = {"card": item["title"],
                                 "title": fu["title"],
                                 "why": fu.get("why", "")}
        save_item(child)
        seen[(owner, key)] = child
        started.append({"id": child["id"], "title": child["title"],
                        "state": child["state"], "owner": child["owner"]})
    if started:
        item["spawned"] = list({child["id"]: child for child in (item.get("spawned") or []) + started}.values())
    return started


def _merge_into(twin, parent, fu, ask):
    """Fold a follow-up into the open card that already holds its subject. The
    ask is appended rather than replacing what is there — the second naming of
    a piece of work usually says something the first did not — and the card
    records where the addition came from, so its owner can see why it grew."""
    twin["ask"] = (twin.get("ask", "").rstrip()
                   + f"\n\nAlso asked, from “{parent['title']}”:\n{ask}")[:2400]
    twin.setdefault("merged_from", []).append({
        "id": parent["id"], "card": parent["title"], "title": fu["title"],
        "at": _now_iso(),
    })
    save_item(twin)
    return twin


def _prep_prompt(item, org):
    emp = next((e for e in org["employees"] if e["id"] == item["owner"]), None)
    short = item.get("prep_short") or []
    again = ""
    if short:
        again = (
            "\n\nYou wrote this question once already and it came back short of "
            + ", ".join(short)
            + ". Write it again, complete this time, rather than defending the "
              "last one.\n\nWhat you wrote last time:\n"
            + json.dumps(item.get("prep_draft") or {}, ensure_ascii=False))
    return f"""This is work you own, and it is hard to walk back, so Daniel has to say
yes before anything happens. He will not see it as a task; he sees one question
with a recommended answer, and his yes is him taking that recommendation, after
which this same card goes into the build queue and is carried out. Your job
right now is to write that question. Do not do the work.

THE WORK: {item['title']}
WHY IT FOLLOWS: {item.get('tier_reason', '')}
WHAT IT ASKS FOR: {item.get('ask', '')}
THE FIRST STEP AS FILED: {item.get('first_action', '')}
YOU ARE: {emp['name'] if emp else item['owner']}{again}

Read whatever you need in the repository to make the question real — the numbers,
the options that actually exist, what each would cost and what it would take to
undo each. Then answer with one short paragraph he reads first (the choice in
front of him, in his terms, no jargon and no ticket ids), and end with the block.

The block must carry "recommend" with all four parts filled in. A recommendation
missing any part comes straight back to you.

{FOLLOW_MARK}
{{"items": [], "recommend": {{"question": "the choice, in one line and in his terms", "answer": "what you recommend he does", "why": "the one reason that decides it", "instead": "the alternative he might reasonably prefer, named honestly"}}}}"""


def prep_question(item, org):
    """Have the owner write the question a tier-2 follow-up puts to him.

    Complete, it joins his list. Short, it stays with the studio, says what it
    is short of, and is written again — up to PREP_TRIES, after which it stops
    and says a person has to write this one. Looping forever on a question the
    model cannot write is the failure mode this counter exists for."""
    if not execution.launch_allowed():
        return False
    item["prep_attempts"] = item.get("prep_attempts", 0) + 1
    # An attempt is only spent once it comes back. Marked in flight here so a
    # restart in the middle of one can give the try back rather than burning it
    # on a call that never ran.
    item["prep_in_flight"] = True
    save_item(item)
    model = item.get("model") or HOST.seat_model(org, item["owner"])
    text, limited = _run_cli(_prep_prompt(item, org),
                             HOST.build_system_prompt(org, item["owner"]),
                             "Read,Glob,Grep", HOST.MAX_TURNS, 420, model=model,
                             phase="prep", seat=item["owner"], item=item["id"])
    item.pop("prep_in_flight", None)
    if limited:
        item["prep_attempts"] -= 1      # the tokens were dry; that is not a try
        save_item(item)
        return False
    body, _got, _amend, _rec, _move = _split_result(text, org, item["owner"])
    _, _, tail = (text or "").partition(FOLLOW_MARK)
    draft = (_follow_doc(tail) or {}).get("recommend")
    draft = {k: str((draft or {}).get(k) or "").strip()[:400] for k in REC_PARTS}
    gaps = recommendation_gaps(draft)
    if gaps:
        item["prep_draft"] = draft
        item["prep_short"] = gaps
        if item["prep_attempts"] >= PREP_TRIES:
            item["prep_stalled"] = (
                f"Written {item['prep_attempts']} times and still missing "
                f"{', '.join(gaps)}. A person has to write this one.")
        save_item(item)
        return True
    item["recommend"] = draft
    # Kept apart from `result`: nothing has been done here, and a card headed
    # "did it — here's the result" over a question nobody has answered yet is a
    # false sentence on his page. The Work page shows this once it has a place
    # for a question that was written rather than a piece of work that was done.
    item["prep_note"] = body
    item["state"] = "needs_approval"
    item["prepped"] = {"at": _now_iso(), "by": item["owner"],
                       "attempts": item["prep_attempts"]}
    for k in ("prep_short", "prep_draft", "prep_stalled", "prepping_since"):
        item.pop(k, None)
    save_item(item)
    return True


def _propose_follow_up(item, org):
    """Backfill for results that landed before the card showed consequences.
    New work answers this inside the call that does it and never reaches here."""
    if not execution.launch_allowed():
        return False
    prompt = f"""A piece of work in Tiny Farm HQ is finished and waiting for the
CEO's verdict. He is about to accept or reject it, and he is entitled to know
what his yes starts before he gives it.

THE WORK: {item['title']}
WHAT HE ASKED FOR: {item.get('ask', '')}
THE RESULT HE IS LOOKING AT:
{(item.get('result') or '')[:6000]}

{_convo_lines(item, org)}

{_follows_spec(org)}"""
    text, limited = _run_cli(prompt, "You answer with NONE or one line of JSON.",
                             "", 1, 180, phase="consequence", seat=item["owner"],
                             item=item["id"])
    if limited:
        return False
    body, got, _amend, rec, _move = _split_result(text, org, item["owner"])
    if got is None:
        # No marker came back; the whole reply is the block.
        got, _amend, rec, _move = _parse_follows(text, org, item["owner"])
    item.pop("follow_up", None)
    item["follow_ups"] = got or []
    item["recommend"] = rec or {}
    save_item(item)
    return True


# Nothing here deletes a work item. These files are the company's record of what
# it did and why, they are a few hundred bytes each, and the page already folds
# closed ones away — so age is not a reason to destroy one. An earlier draft aged
# them out after 60 days and would have read a record with no timestamp as
# infinitely old and deleted it: exactly the fail-open that makes automated
# cleanup untrustworthy. Keep them, and let git hold the history.


def worker():
    """One thread, one thing at a time: read new exchanges for work, then do the
    work that needs no permission. Yields to the token limit exactly like the
    intake queue does — a dry window delays the company, it does not lose it."""
    while True:
        time.sleep(15)
        try:
            # Before anything that can block for minutes: a question past its
            # thirty seconds stops being his, whatever else the studio is doing.
            recover_completion_work()
            if not execution.launch_allowed():
                continue
            _sweep_hand_backs()
            if HOST.limited_until():
                continue
            org = HOST.load_org()
            # His POST starts the reply itself now, so what is left here is the
            # stragglers: questions asked while the tokens were out, or asked
            # before a restart took their thread with it.
            waiting = [i for i in items()
                       if i.get("awaiting_reply") and i["id"] not in _REPLYING]
            if waiting:
                waiting.sort(key=lambda i: i.get("asked_ts", 0))
                if _claim(waiting[0]["id"]):
                    try:
                        _process_response(waiting[0], org)
                    finally:
                        _release(waiting[0]["id"])
                continue
            pending = sorted(_read_dir(CAPTURES), key=lambda c: c.get("created_ts", 0))
            if pending:
                _process_capture(pending[0], org)
                continue
            todo = [i for i in items() if i.get("state") == "doing" and not i.get("started")]
            todo.sort(key=lambda i: i.get("created_ts", 0))
            if todo:
                _process_item(todo[0], org)
                continue
            # A question waiting to be written is a piece of his queue that has
            # not arrived yet. Oldest first, and one that has already stopped
            # is left alone rather than rewritten forever.
            unprepped = [i for i in items() if i.get("state") == "prepping"
                         and not i.get("prep_stalled")]
            unprepped.sort(key=lambda i: i.get("created_ts", 0))
            if unprepped:
                prep_question(unprepped[0], org)
                continue
            # No card should sit in front of him with its consequence unknown.
            blind = [i for i in items()
                     if i.get("state") == "for_review" and not _asked_what_follows(i)]
            if blind:
                _propose_follow_up(blind[0], org)
        except Exception:
            continue      # the company outlives any one bad item


def start():
    if not execution.launch_allowed():
        threading.Thread(target=worker, daemon=True).start()
        return
    # A restart takes the live deadlines with it. Anything already past its
    # thirty seconds hands back here rather than fifteen seconds into the
    # worker's first tick, and anything still inside its thirty seconds gets
    # its deadline back, so the promise survives a restart to the second.
    try:
        _sweep_hand_backs()
        for it in items():
            if it.get("awaiting_reply") and it.get("state") in HIS_STATES:
                _arm_deadline(it)
    except Exception:
        pass
    threading.Thread(target=worker, daemon=True).start()


# ---------------------------------------------------------------------------
# API — server.py routes /api/work* straight here
# ---------------------------------------------------------------------------

def _held_back(item):
    """True when a finished card's changes never reached the repository, so
    there is nothing in the tree for Daniel to approve."""
    d = item.get("diff") or {}
    if not d or d.get("applied"):
        return False
    return (d.get("why_not") or "") not in ("", "nothing changed")


def land_item(item, by, sha="", note=""):
    """A finished card that met the landing bar goes in without a verdict.

    It is closed, not queued: the work is committed and reported, and the Undo
    on the page reverts that commit and gives the card back. Nothing here asks
    Daniel anything, which is the point — work he would only rubber-stamp is
    work he should never have been shown (S-16)."""
    status, reason = completion_assessment(item)
    if status not in ("ready_to_apply", "completed"):
        raise ValueError(reason)
    memory_pending = (isinstance(item.get("owner_memory"), dict)
                      and not item["owner_memory"].get("committed"))
    if (status == "completed" and item.get("state") == "landed"
            and not item.get("pending_followups") and not memory_pending):
        return item
    item.setdefault("completion", {"version": 1, "attempt_id": item["attempt_outcome"]["id"],
                          "at": _now_iso(), "sha": sha, "by": by,
                          "kind": "change" if sha else "reading",
                          "evidence": dict(item["attempt_outcome"])})
    item.setdefault("pending_followups", {"version": 1, "attempt_id": item["completion"]["attempt_id"],
                                         "items": follow_ups(item)})
    # Persist the recoverable obligation before publishing the completed state.
    save_item(item)
    item["state"] = "landed"
    item["closed"] = item["completion"]["at"]
    item.setdefault("landed", {"at": item["completion"]["at"], "by": by, "sha": sha, "note": note})
    save_item(item)
    if commit_owner_memory(item):
        save_item(item)
    finish_pending_followups(item)
    return item


def finish_pending_followups(item):
    pending = item.get("pending_followups")
    if not pending:
        return
    # Read/deduplicate/file is one cross-process operation, including closed children.
    with mutation_lock():
        fresh = load_item(item["id"])
        if fresh["_revision"] != item.get("_revision", 0):
            raise RecordConflict(item["id"], item.get("_revision", 0), fresh["_revision"])
        _file_follow_ups(item, pending["items"], HOST.load_org(), cap_id="landed",
                         message=f"Landed without Daniel: “{item['title']}”.")
        item.pop("pending_followups", None)
        save_item(item)


def recover_completion_work():
    """Select recoverable obligations independently of model launch permission."""
    import drain
    # A live drain owns pending transactions until it releases this same lock.
    lock = drain.take_lock()
    if lock is None:
        return []
    try:
        recovered = []
        for item in items():
            if item.get("pending_undo"):
                try:
                    ok, _ = recover_pending_undo(item)
                    if ok:
                        recovered.append(item["id"])
                except RecordConflict:
                    continue
            elif item.get("pending_landing"):
                try:
                    drain.recover_pending_landing(item)
                    recovered.append(item["id"])
                except RecordConflict:
                    continue
            elif item.get("completion") and (item.get("pending_followups")
                    or (isinstance(item.get("owner_memory"), dict)
                        and not item["owner_memory"].get("committed"))):
                try:
                    land_item(item, item["completion"].get("by", "recovery"),
                              sha=item["completion"].get("sha", ""))
                    recovered.append(item["id"])
                except RecordConflict:
                    continue
        return recovered
    finally:
        lock.close()


def undo_landing(item):
    """Put back what a landing changed, and give the card back to Daniel.

    The commit is reverted rather than reset: other work has landed on top of
    it since, and rewriting history under a shared tree is how a second
    person's work disappears."""
    import drain
    import integration

    if item.get("pending_undo"):
        return recover_pending_undo(item)
    if item.get("state") != "landed":
        return False, "Only a landed card can be undone."
    sha = (item.get("landed") or {}).get("sha") or ""
    if not sha:
        item.pop("completion", None)
        if item.get("attempt_outcome"):
            item["attempt_outcome"]["landing_verified"] = False
        forget_owner_memory(item)
        item["state"] = "for_review"
        item.pop("landed", None)
        save_item(item)
        return True, "there was no commit to undo, so the card is back with you"
    ready, reason = integration.handoff_status(HOST.REPO)
    if not ready:
        return False, reason
    parent = integration.main_head(HOST.REPO)
    if integration.git(HOST.REPO, "merge-base", "--is-ancestor", sha, parent,
                       check=False).returncode:
        return False, "The landing commit is not on local main."
    marker = "HQ-Undo: " + item["id"] + ":" + sha
    checkout = os.path.join(drain.WORKTREES, "integration-undo-" + item["id"])
    item["pending_undo"] = {"version": 1, "reverted": sha, "parent": parent,
                            "checkout": checkout, "marker": marker,
                            "at": _now_iso()}
    # The obligation is durable before any Git side effect. The drain lock
    # held by the API or startup recovery serializes this with normal landings.
    save_item(item)
    return recover_pending_undo(item)


def recover_pending_undo(item):
    """Finish one exact-parent revert after a process interruption.

    Caller holds the drain lock before the work-record lock. Only the named
    detached scratch checkout may be discarded after an interrupted revert.
    """
    import drain
    import integration

    tx = item.get("pending_undo")
    if not tx:
        return False, "There is no undo transaction to recover."
    repo, parent, checkout = HOST.REPO, tx["parent"], tx["checkout"]
    head = integration.main_head(repo)
    commit = ""
    if os.path.isdir(checkout):
        commit = integration.git(checkout, "rev-parse", "HEAD").stdout.strip()
        if commit == parent:
            # A crash may leave a half-applied revert in this private checkout.
            # Recreate only this transaction's named worktree from the exact base.
            integration.remove_candidate(repo, checkout, drain.WORKTREES)
            commit = ""
    if commit:
        message = integration.git(repo, "show", "-s", "--format=%B", commit).stdout
        actual_parent = integration.git(repo, "rev-parse", commit + "^").stdout.strip()
        if tx["marker"] not in message.splitlines() or actual_parent != parent:
            return False, "The undo checkout contains a different commit; inspect it before retrying."
    elif head == parent:
        try:
            checkout = integration.candidate_checkout(repo, drain.WORKTREES,
                                                      "undo-" + item["id"], parent)
            reverted = integration.git(checkout, "revert", "--no-commit", tx["reverted"],
                                       check=False)
            if reverted.returncode:
                reason = (reverted.stderr or reverted.stdout or "The revert did not apply.").strip()[:200]
                integration.remove_candidate(repo, checkout, drain.WORKTREES)
                item.pop("pending_undo", None)
                save_item(item)
                return False, reason
            if integration.git(checkout, "diff", "--cached", "--quiet",
                               check=False).returncode == 0:
                integration.remove_candidate(repo, checkout, drain.WORKTREES)
                item.pop("pending_undo", None)
                save_item(item)
                return False, "The landing has no changes left to revert on local main."
            integration.git(checkout, "-c", "user.name=Tiny Farm HQ",
                            "-c", "user.email=hq@tiny-farm.local", "commit",
                            "-m", "Revert landed work " + item["id"],
                            "-m", tx["marker"])
            commit = integration.git(checkout, "rev-parse", "HEAD").stdout.strip()
        except RuntimeError as exc:
            # Leave the durable transaction for recovery. An exception can
            # occur after commit or ref update; never guess that nothing ran.
            return False, str(exc)[:200]
    else:
        return False, "Local main moved before the undo could be prepared; the landing remains in review."

    if head == parent:
        if not integration.advance_main(repo, commit, parent):
            return False, "Local main moved before the undo commit could land."
    elif head == commit:
        if integration.main_checkout(repo) and not integration.synchronize_main(repo, commit, parent):
            return False, "The undo commit landed, but its main checkout needs synchronization."
    else:
        return False, "Local main moved before the undo commit could land."

    item.pop("completion", None)
    if item.get("attempt_outcome"):
        item["attempt_outcome"]["landing_verified"] = False
    forget_owner_memory(item)
    item["state"] = "for_review"
    item["landing_undone"] = {"at": _now_iso(), "reverted": tx["reverted"],
                              "commit": commit}
    item.setdefault("conversation", []).append(
        {"role": "daniel", "text": "Undid this landing.", "at": _now_iso(), "with": "undo"})
    item.pop("landed", None)
    item.pop("pending_undo", None)
    save_item(item)
    if os.path.isdir(checkout):
        integration.remove_candidate(repo, checkout, drain.WORKTREES)
    return True, "reverted"


def _in_his_list(item):
    """A card sitting in front of him with something to give. A finished card
    whose changes never reached the repository is not one: there is nothing in
    the tree to approve."""
    return (item.get("state") in HIS_STATES
            and not (item.get("state") == "for_review" and _held_back(item)))


def snapshot():
    got = items()
    import drain
    head_result = drain.sh(["git", "rev-parse", "main"], cwd=drain.REPO, timeout=10)
    head = head_result.stdout.strip() if head_result.returncode == 0 else ""
    active = HOST.drain_state() if hasattr(HOST, "drain_state") else None
    for item in got:
        item["workflow_view"] = drain.project_work(item, head=head, active=active)
    return {
        "policy": policy(),
        "items": got,
        "capturing": len(_read_dir(CAPTURES)),
        # A card that handed back is not in this count: it is the studio's move
        # until the answer lands, and it says so in its own strip on the page.
        # A finished card whose patch never reached the tree is waiting on
        # whoever holds those files, not on him, and the page shows it in its
        # own section with no verdict to give. And a card with no recommended
        # answer is not a question yet, so it is not counted as one (S-17): it
        # is still on the page with its buttons, its owner is the seat that
        # owes the recommendation, and `unprepped` says how many there
        # are — uncounted rather than hidden.
        "waiting_on_you": sum(1 for i in got if work_ready_for_daniel(
            i, i.get("workflow_view"), work_preparation(i))),
        "unprepped": sum(1 for i in got if work_reviewable(i, i.get("workflow_view"))
                         and not work_preparation(i)["ready"]),
        "prepping": sum(1 for i in got if i["state"] == "prepping"),
        "prep_stalled": sum(1 for i in got if i.get("prep_stalled")),
        "owed": sum(1 for i in got if i["state"] == "owed"),
        # The page keeps the same clock the machine does, against the same
        # deadline, rather than starting its own when the card happened to load.
        "now": time.time(),
        "reply_seconds": reply_seconds(),
        "in_progress": sum(1 for i in got if i["workflow_view"]["availability"] == "running"),
        "queued": sum(1 for i in got if i["workflow_view"]["availability"] == "runnable"),
        # What the company's unattended work has cost lately. It shares one
        # allotment with him, so a result he is reading should be able to say
        # what producing it spent, and the page should say what the whole of it
        # has spent since the current window opened.
        "tokens": HOST.token_window(),
    }


def api_get(path):
    if path == "/api/work":
        return snapshot()
    return {"error": "not found"}


def api_post(path, payload):
    if path == "/api/work/undo":
        import drain
        lock = drain.take_lock()
        if lock is None:
            return {"ok": False, "why": "The integration lane is busy; retry after it finishes.",
                    "id": payload.get("id") or ""}
        try:
            with mutation_lock():
                return _api_post(path, payload)
        finally:
            lock.close()
    with mutation_lock():
        return _api_post(path, payload)


def _api_post(path, payload):
    if path == "/api/work/request":
        words = str(payload.get("words") or "").strip()
        kind = str(payload.get("kind") or "work")
        request_id = str(payload.get("request_id") or "")
        if not words or len(words) > 4000:
            return {"error": "Describe the request in 1–4000 characters."}
        if kind not in ("work", "priority", "discussion"):
            return {"error": "Unknown request kind."}
        if not re.fullmatch(r"[a-zA-Z0-9_-]{8,100}", request_id):
            return {"error": "Missing submission id; reload and try again."}
        previous = next((i for i in items() if i.get("request_id") == request_id), None)
        if previous:
            if previous.get("source_message") != words or previous.get("request_kind") != kind:
                return {"error": "This submission id was already used for another request."}
            return previous
        owner = "priya" if kind == "priority" else "claude"
        if not any(e["id"] == owner for e in HOST.load_org()["employees"]):
            owner = "claude"
        first = {
            "work": "Identify the accountable owner and safe execution tier, file the requested work as a linked follow-up, and report the route here.",
            "priority": "Read the current priorities, identify the accountable owner, file the priority edit as linked work at its proper execution tier, and report the route here.",
            "discussion": "Respond to Daniel's question here and file follow-up work only if the discussion calls for it.",
        }[kind]
        title = words.splitlines()[0][:160] or "New request"
        return save_item({
            "id": "w" + uuid.uuid4().hex[:11], "title": title, "level": "task",
            "owner": owner, "tier": 0,
            "tier_reason": "Read, route, and discuss first; any later action gets its own execution tier.",
            "ask": words, "first_action": first, "state": "doing", "thread": owner,
            "source": "request", "source_message": words, "request_kind": kind,
            "request_id": request_id, "result": "", "started": "", "attempts": 0,
            "created": _now_iso(), "created_ts": time.time(),
        })
    if path == "/api/work/reopen":
        old_id = str(payload.get("id") or "")
        if not re.fullmatch(r"w[0-9a-f]{6,32}", old_id) or not os.path.isfile(_item_path(old_id)):
            return {"error": "No such work card."}
        original = load_item(old_id)
        if original.get("source") != "request":
            return {"error": "Only requests can be reopened here."}
        if original.get("state") not in ("accepted", "dropped", "landed"):
            return {"error": "This request is still open; add a comment on its card."}
        words = str(payload.get("words") or "").strip()
        if not words or len(words) > 4000:
            return {"error": "Describe what needs another look in 1–4000 characters."}
        request_id = str(payload.get("request_id") or "")
        previous = next((i for i in items() if i.get("request_id") == request_id), None)
        if previous and previous.get("reopens") != old_id:
            return {"error": "This submission id was already used for another request."}
        created = _api_post("/api/work/request", {"words": words,
            "kind": original.get("request_kind", "work"), "request_id": request_id})
        if created.get("error"):
            return created
        if created.get("reopens") and created["reopens"] != old_id:
            return {"error": "This submission id was already used for another reopening."}
        if not created.get("reopens"):
            created["reopens"] = old_id
            created["parent"] = old_id
            save_item(created)
        return created
    if path == "/api/work/new":
        org = HOST.load_org()
        try:
            tier = int(payload.get("tier", 2))
        except Exception:
            tier = 2
        fields = {
            "title": (payload.get("title") or "").strip()[:160] or "Untitled",
            "level": (payload.get("level") or "task").lower(),
            "owner": payload.get("owner") or "claude",
            "ask": (payload.get("ask") or "").strip()[:600],
            "first_action": (payload.get("first_action") or "").strip()[:600],
            "tier": tier if tier in (0, 1, 2) else 2,
            "tier_reason": "filed by hand",
        }
        if fields["level"] not in LEVELS:
            fields["level"] = "task"
        cap = {"to": fields["owner"], "message": fields["ask"], "id": "manual"}
        return _file_item(fields, cap, org)

    item_id = payload.get("id") or ""
    if not re.match(r"^w[0-9a-f]{6,32}$", item_id):
        return {"error": "bad id"}
    p = _item_path(item_id)
    if not os.path.isfile(p):
        return {"error": "no such item"}
    item = load_item(item_id)
    # Reject stale actions before comments, child filing, merges or Git side effects.
    actual = validate_revision(item)
    if "_revision" in payload:
        expected = payload["_revision"]
        if type(expected) is not int or expected != actual:
            raise RecordConflict(item_id, expected, actual)

    # Every verdict may carry a reason, and the reason is recorded on the card
    # before the verdict is applied — so a second attempt knows why it is a
    # second attempt, and an acceptance teaches a standard rather than leaving
    # one to be guessed. His rule, 2026-09-04: a control that disposes of work
    # without asking why is a control he cannot use.
    # The comment is the primitive and the verdict rides on it. Whatever he
    # writes is answered on the card by its owner — whichever button it came in
    # with, or none — and the owner's reply names the move it makes: an answer,
    # a revision of the result, or a follow-up filed to the right person. His
    # rule, 2026-09-11, after a question attached to an acceptance came back as
    # a title waiting for his yes: he should not have to know which button
    # gets a note read and which gets it answered.
    said = (payload.get("comment") or "").strip()[:4000]
    verdicts = ("/api/work/accept", "/api/work/drop", "/api/work/approve")
    if said and path in verdicts:
        item.setdefault("conversation", []).append(
            {"role": "daniel", "text": said, "at": _now_iso(),
             "with": path.rsplit("/", 1)[-1]})
        ask_owner(item)

    if path == "/api/work/respond":
        # Writing back to a card is a conversation, not a verdict: it changes
        # no state and closes nothing by itself. The owner answers on the card,
        # and what the answer commits to is filed from there — so he never has
        # to leave the thing he was reading in order to say something about it.
        msg = (payload.get("message") or "").strip()[:4000]
        if not msg:
            return {"error": "empty message"}
        convo = item.get("conversation", [])
        convo.append({"role": "daniel", "text": msg, "at": _now_iso()})
        item["conversation"] = convo
        ask_owner(item)
        saved = save_item(item)
        _begin_answering(item)
        return saved

    if path == "/api/work/undo":
        ok, why = undo_landing(item)
        return {"ok": ok, "why": why, "id": item["id"], "state": item["state"]}
    if path == "/api/work/accept":
        commit_owner_memory(item)
        item["state"] = "accepted"
        item["closed"] = _now_iso()
        # His yes starts exactly the work the card showed him and nothing else.
        # The follow-up enters at its own tier, so a risky one still comes back
        # to him rather than riding in on the acceptance of something safe.
        # A yes on a card that recommended something is the answer to the
        # question, and the record has to say so even when no work follows.
        rec = item.get("recommend") or {}
        if rec.get("answer"):
            item["decided"] = {"question": rec.get("question", ""),
                               "answer": rec["answer"], "at": _now_iso()}
        # A condition he attached to the yes travels into everything the yes
        # starts. Without this the note sits on a card that is now closed
        # while the work it was meant to steer runs on the old brief — which
        # is how "accept, but do it this way" becomes "accept".
        fus = follow_ups(item)
        if fus:
            _file_follow_ups(item, fus, HOST.load_org(), cap_id="follow",
                             message=f"Accepted “{item['title']}”.", said=said)
    elif path == "/api/work/drop":
        forget_owner_memory(item)
        item["state"] = "dropped"
        item["closed"] = _now_iso()
    elif path == "/api/work/approve":
        # His yes on a tier-2 item does not make it reversible; it makes it
        # allowed. A build session still carries it out — with whatever he
        # attached to the yes, since a condition on an approval is a condition
        # on the work, not a note about it.
        item["state"] = "waiting_session"
        item["approved"] = _now_iso()
        if said:
            item["ask"] = (item.get("ask", "").rstrip()
                           + "\n\nDaniel attached this when he approved it:\n" + said)
    else:
        return {"error": "not found"}
    saved = save_item(item)
    # After the verdict is on disk, never before: the reply re-reads the card
    # when it lands, and a reply that started first could be answering a card
    # this call is still in the middle of closing.
    if item.get("awaiting_reply"):
        _begin_answering(item)
    return saved


LEGACY_COMPLETION_IDS = "w2d226ab695b,w72dee30012f,w8fd8d88b290,w59c6ab05678,w6ef64f2e6dd,wd191fa66a85,wabb24f97efa,w554baab1271,w56a634c94f6,w2d641a31a52,wae35fb20cb7,w8e71933a1a9,w6ff2240c1fb,wfce637ce465,w3169ae0d4da,wcd3806bc3a4,wc1886486f14,w5a4005536e1,wf1b3b951813".split(",")

PROCESS_COMPLETION_IDS = "wecd05a982cc,we11c4a7b3f92,wbbbcc2086a1f,w559bf20d689,wd2ac4cb762d,w41fdcfcaf59,wd3ce6b6f4db,wa81b250c0180,we22d5b8c4a03,w9b453fb70c7,w8e71933a1a9,w37ca945abca2".split(",")


def instruction_fingerprint(item):
    outcome_fields = {"_revision", "state", "result", "check", "prior_checks", "prior_results",
        "attempts", "done_by", "diff", "suites", "usage", "spent", "resume", "attempt_outcome",
        "completion", "pending_landing", "pending_followups", "closed", "landed", "finished",
        "revising", "revisions", "spawned", "last_recorded_attempt", "repair_hold", "landing_recovery",
        "owner_memory", "workflow", "workflow_view", "waiting_for", "pending_undo",
        "landing_undone"}
    return evidence_id({key: value for key, value in item.items() if key not in outcome_fields})


def reconciliation_fingerprint(item):
    # Freeze the entire reviewed record, including every instruction, reply,
    # ownership, risk and conversation field, rather than guessing which matters.
    return evidence_id(dict(item, _revision=item.get("_revision", 0)))


def pending_conversation(item, *, include_revision=True):
    conversation = item.get("conversation") or []
    return bool(item.get("awaiting_reply") or (include_revision and item.get("revising")) or item.get("state") == "owed"
                or (conversation and conversation[-1].get("role") == "daniel")
                or item["id"] in _REPLYING)


def reconcile_legacy_completion(manifest=None, *, apply=False):
    with mutation_lock():
        return _reconcile_legacy_completion(manifest, apply=apply)


def _reconcile_legacy_completion(manifest=None, *, apply=False):
    """Apply only the reviewed historical manifest; preflight every card first."""
    if manifest is None:
        manifest = os.path.join(HOST.DATA, "completion_reconciliation.json")
    if isinstance(manifest, (str, os.PathLike)):
        with open(manifest, encoding="utf-8") as source:
            manifest = json.load(source)
    manifest_id = evidence_id(manifest)
    by_id = {item["id"]: item for item in items(strict=True)}
    report, errors = [], []
    classifications = {"safe_to_close": 8, "return_to_owner": 9,
                       "superseded/duplicate": 1, "needs_operator_judgment": 1}
    entries = manifest.get("cards", [])
    if (len(entries) != 19 or {entry["id"] for entry in entries} != set(LEGACY_COMPLETION_IDS)
            or any(sum(e["classification"] == k for e in entries) != n for k, n in classifications.items())):
        raise ValueError("The reviewed manifest must contain the exact nineteen classified cards.")
    for entry in entries:
        item = by_id.get(entry["id"])
        done = item and (item.get("completion_reconciliation") or {}).get("manifest_id") == manifest_id
        if not item:
            errors.append(entry["id"] + ": record missing")
        elif pending_conversation(item, include_revision=not done):
            errors.append(entry["id"] + ": a conversation or reply is still pending")
        elif not done and (item.get("state") != entry.get("expected_state")
                           or item.get("_revision", 0) != entry.get("expected_revision", 0)
                           or reconciliation_fingerprint(item) != entry.get("expected_fingerprint")):
            errors.append(entry["id"] + ": state or reviewed evidence changed")
        if item and not done and entry["classification"] == "return_to_owner" and item.get("owner") != entry.get("owner"):
            errors.append(entry["id"] + ": reviewed owner changed")
        if entry["classification"] == "superseded/duplicate" and entry.get("canonical_id") not in by_id:
            errors.append(entry["id"] + ": canonical card missing")
        report.append({"id": entry["id"], "classification": entry["classification"], "already_applied": bool(done)})
    if errors or not apply:
        return {"applicable": not errors, "applied": False, "errors": errors,
                "totals": classifications, "cards": report}
    # Re-read every target under the shared write lock before the first mutation.
    # Thus any stale preflight aborts without changing even the first card.
    for entry in entries:
        fresh = load_item(entry["id"])
        if reconciliation_fingerprint(fresh) != reconciliation_fingerprint(by_id[entry["id"]]):
            return {"applicable": False, "applied": False, "errors": [entry["id"] + ": changed during preflight"],
                    "totals": classifications, "cards": report}
    for entry in entries:
        item = load_item(entry["id"])
        if reconciliation_fingerprint(item) != reconciliation_fingerprint(by_id[entry["id"]]):
            raise RuntimeError("A work record was written outside the shared mutation lock")
        if (item.get("completion_reconciliation") or {}).get("manifest_id") == manifest_id:
            if item.get("completion") and item.get("pending_followups"):
                land_item(item, item["completion"].get("by", manifest["audit_attribution"]),
                          note=entry["evidence_summary"])
            continue
        attribution = entry.get("audit_attribution") or manifest["audit_attribution"]
        audit = {"version": 1, "manifest_id": manifest_id, "at": _now_iso(),
                 "classification": entry["classification"], "by": attribution,
                 "evidence_summary": entry["evidence_summary"]}
        action = entry["classification"]
        item["completion_reconciliation"] = audit
        if action == "safe_to_close":
            attempt_id = "historical-" + manifest_id + "-" + item["id"]
            item["attempt_outcome"] = {"version": 1, "id": attempt_id, "status": "complete",
                                       "result_id": evidence_id(item.get("result", ""))}
            # An attributed operator audit, explicitly distinct from a native checker pass.
            item["completion"] = {"version": 1, "attempt_id": attempt_id, "at": audit["at"],
                                  "kind": "historical_review", "by": attribution, "evidence": audit}
            item["pending_followups"] = {"version": 1, "attempt_id": attempt_id, "items": [fu for fu in follow_ups(item) if not any(
                    merge_key(old.get("title", "")) == merge_key(fu.get("title", ""))
                    and old.get("owner") == (fu.get("owner") or item["owner"])
                    for old in (item.get("spawned") or []))]}
            save_item(item)
        elif action == "return_to_owner":
            if item["owner"] != entry["owner"]:
                raise ValueError("Reviewed repair owner differs from the recorded owner")
            item["repair_brief"] = entry["repair_ask"]
            item["automatic_repairs"] = 1
            item.pop("repair_hold", None)
            requeue_for_revision(item)
            item["state"] = "waiting_session"
            save_item(item)
        elif action == "superseded/duplicate":
            supersede_item(item, entry["canonical_id"])
        else:
            item["repair_hold"] = entry["operator_judgment"]["action"]
            item["operator_judgment"] = entry["operator_judgment"]
            save_item(item)
    for entry in entries:
        if entry["classification"] == "safe_to_close":
            item = load_item(entry["id"])
            if item.get("pending_followups"):
                land_item(item, item["completion"]["by"], note=entry["evidence_summary"])
    return {"applicable": True, "applied": True, "errors": [], "totals": classifications, "cards": report}


def reconcile_process_completion(manifest=None, *, apply=False):
    """Reconcile the reviewed process build without inventing drain evidence.

    The manifest distinguishes code already on main from the three assignments
    that remain open.  Safe closures carry an attributed operator audit, never
    a synthetic checker verdict or Daniel acceptance.  The decision-action card
    is held, not closed: its rejected candidate must be explicitly linked to the
    separately-landed implementation before anyone may call it complete.
    """
    with mutation_lock():
        return _reconcile_process_completion(manifest, apply=apply)


def _reconcile_process_completion(manifest=None, *, apply=False):
    if manifest is None:
        manifest = os.path.join(HOST.DATA, "process_completion_reconciliation.json")
    if isinstance(manifest, (str, os.PathLike)):
        with open(manifest, encoding="utf-8") as source:
            manifest = json.load(source)
    manifest_id = evidence_id(manifest)
    entries = manifest.get("cards", [])
    classifications = {"safe_to_close": 9, "leave_open": 2, "hold_for_linkage": 1}
    if (manifest.get("schema_version") != 1
            or len(entries) != 12
            or {entry.get("id") for entry in entries} != set(PROCESS_COMPLETION_IDS)
            or any(sum(entry.get("classification") == name for entry in entries) != count
                   for name, count in classifications.items())
            or any(any("stable_fingerprint" in snapshot for snapshot in entry.get("expected_snapshots", []))
                   and entry.get("classification") != "hold_for_linkage" for entry in entries)):
        raise ValueError("The reviewed process manifest must contain the exact twelve classified cards.")

    by_id = {item["id"]: item for item in items(strict=True)}
    report, errors = [], []
    for entry in entries:
        item = by_id.get(entry["id"])
        audit = (item or {}).get("process_completion_reconciliation") or {}
        done = audit.get("manifest_id") == manifest_id
        snapshots = entry.get("expected_snapshots") or []
        stable = dict(item or {})
        stable.pop("_revision", None)
        stable.pop("waiting_for", None)
        matches = item and any(
            item.get("state") == snapshot.get("state")
            and (("stable_fingerprint" in snapshot
                  and evidence_id(stable) == snapshot["stable_fingerprint"])
                 or (item.get("_revision", 0) == snapshot.get("revision", 0)
                     and reconciliation_fingerprint(item) == snapshot.get("fingerprint")))
            for snapshot in snapshots)
        if not item:
            errors.append(entry["id"] + ": record missing")
        elif not done and not matches:
            errors.append(entry["id"] + ": state or reviewed evidence changed")
        elif (not done and entry["classification"] in ("safe_to_close", "hold_for_linkage")
              and pending_conversation(item, include_revision=False)):
            errors.append(entry["id"] + ": a conversation or reply is still pending")
        report.append({"id": entry["id"], "classification": entry["classification"],
                       "already_applied": bool(done), "evidence_commits": entry.get("evidence_commits", []),
                       "remaining_work": entry.get("remaining_work", "")})
    if errors or not apply:
        return {"applicable": not errors, "applied": False, "errors": errors,
                "totals": classifications, "cards": report}

    # Re-read all twelve under the process-wide write lock before mutating any
    # one card.  Open-card progress invalidates the audit just as surely as a
    # changed closure target does.
    for entry in entries:
        fresh = load_item(entry["id"])
        original = by_id[entry["id"]]
        if ((fresh.get("process_completion_reconciliation") or {}).get("manifest_id") != manifest_id
                and reconciliation_fingerprint(fresh) != reconciliation_fingerprint(original)):
            return {"applicable": False, "applied": False,
                    "errors": [entry["id"] + ": changed during preflight"],
                    "totals": classifications, "cards": report}

    for entry in entries:
        item = load_item(entry["id"])
        existing = item.get("process_completion_reconciliation") or {}
        if existing.get("manifest_id") == manifest_id:
            if entry["classification"] == "safe_to_close" and item.get("state") != "landed":
                land_item(item, item["completion"]["by"], note=entry["evidence_summary"])
            continue
        if reconciliation_fingerprint(item) != reconciliation_fingerprint(by_id[entry["id"]]):
            raise RuntimeError("A work record was written outside the shared mutation lock")
        attribution = entry.get("audit_attribution") or manifest["audit_attribution"]
        audit = {"version": 1, "manifest_id": manifest_id, "at": _now_iso(),
                 "classification": entry["classification"], "by": attribution,
                 "evidence_commits": entry["evidence_commits"],
                 "test_proof": entry["test_proof"],
                 "evidence_summary": entry["evidence_summary"],
                 "limitations": entry.get("limitations") or manifest.get("limitations", "")}
        item["process_completion_reconciliation"] = audit
        if entry["classification"] == "leave_open":
            item["repair_brief"] = entry["remaining_work"]
            save_item(item)
            continue
        if entry["classification"] == "hold_for_linkage":
            item["repair_hold"] = entry["remaining_work"]
            save_item(item)
            continue
        attempt_id = "process-audit-" + manifest_id + "-" + item["id"]
        item["attempt_outcome"] = {"version": 1, "id": attempt_id, "status": "complete",
                                   "reason": entry["evidence_summary"],
                                   "result_id": evidence_id(item.get("result", "")),
                                   "landing_verified": True,
                                   "operator_audit": audit}
        item["completion"] = {"version": 1, "attempt_id": attempt_id, "at": audit["at"],
                              "by": attribution, "kind": "operator_audit", "evidence": audit}
        item["pending_followups"] = {"version": 1, "attempt_id": attempt_id, "items": []}
        save_item(item)
        land_item(item, attribution, note=entry["evidence_summary"])
    return {"applicable": True, "applied": True, "errors": [],
            "totals": classifications, "cards": report}

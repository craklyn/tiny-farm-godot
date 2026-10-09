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
    tier 2  hard to walk back or his taste to settle (release, deploy, spend,
            delete, the store page, a change of design direction) -> he says yes
            first. Carrying out a decided change players will see is tier 1.

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
            "means": "Changes files, but git reverts it — doc edits, code and art behind tests (players' game changes included, until they ship), a new decision card.",
            "gate": "a build session does it and shows the diff afterwards",
            "auto": False,
        },
        "2": {
            "name": "Ask first",
            "means": "Hard to walk back or his taste to settle — a release, a deploy, spending, deleting, the store page, any change of design direction.",
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
# A work card's id. The `wr` form is what the Animation Lab's first unattended
# runs filed; those cards are still live, so the queue must be able to act on them.
WORK_ID = r"w(?:r)?[0-9a-f]{6,32}"

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

# What may make a follow-up tier 2: S-16's tier-2 list, and a question of his
# taste. A follow-up asking for his yes first says which of these it is, and
# one that names none files at tier 1 (2026-10-02). Before this, the policy's
# "anything players see" put every game change at tier 2, so the two pea cards
# a landed decision promised (the shelf, the packet art) parked as questions
# nobody could write — "a person has to write this one" — when both were
# revertable code and art that S-16 lands without him.
ASK_FIRST = {
    "release": "publishing a release",
    "deploy": "a deploy to the tablet or the web",
    "spending": "spending money, beyond the art the queue may generate on its own",
    "deleting": "deleting something git cannot bring back",
    "store_page": "the store page, or anything else said in public",
    "design_direction": "changing a design direction, rather than carrying one out",
    "taste": "a choice only Daniel can make, which nothing on main has settled",
}


def follow_tier(fu):
    """The tier a follow-up files at: its own, except that tier 2 must name
    what on ASK_FIRST it is."""
    try:
        tier = int(fu.get("tier", UNTIERED_FOLLOW))
    except (TypeError, ValueError):
        return UNTIERED_FOLLOW
    if tier not in (0, 1, 2):
        return UNTIERED_FOLLOW
    if tier == 2 and fu.get("ask_first") not in ASK_FIRST:
        return 1
    return tier

# What a recommendation has to say before the card carrying it may ask him for
# a yes: the choice, the answer, the one reason that decides it, and the
# alternative he might reasonably prefer. Three of the four is a briefing he
# cannot act on without asking a question back.
REC_PARTS = ("question", "answer", "why", "instead")

# A choice among named options shows him every option, not only the pick and
# one alternative (2026-10-07: the barn's three looks reached his page as "C,
# instead A", with B and every description only inside the diff).
OPTIONS_SPEC = ('"options": [{"label": "A. the option\'s short name", "summary": "what choosing it means, '
                'in one or two plain sentences"}] — every option he is choosing between, the recommended '
                'one included; leave it out when the choice is a plain yes or no')


def rec_options(raw):
    """At most eight {label, summary} options, each a short plain string."""
    if not isinstance(raw, list):
        return []
    out = []
    for o in raw[:8]:
        if isinstance(o, dict) and str(o.get("label") or "").strip():
            out.append({"label": str(o["label"]).strip()[:120],
                        "summary": str(o.get("summary") or "").strip()[:400]})
    return out if len(out) >= 2 else []

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
    POLICY_PATH = _host_cfg("work_policy.json")
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(CAPTURES, exist_ok=True)
    # The policy is checked-in configuration; seed a default only into a data
    # root that still holds its own configuration, never into the code checkout.
    if not os.path.isfile(POLICY_PATH) and os.path.dirname(POLICY_PATH) == HOST.DATA:
        _write_json(POLICY_PATH, DEFAULT_POLICY)
    if sanitize:
        _sanitize()


def _host_cfg(name):
    """A checked-in HQ file: beside the code when the host says so (Q-125 a)."""
    cfg = getattr(HOST, "cfg", None)
    return cfg(name) if callable(cfg) else os.path.join(HOST.DATA, name)


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


class UnknownState(ValueError):
    def __init__(self, item_id, state):
        self.item_id, self.state = item_id, state
        super().__init__(f"Work card {item_id} cannot be saved in state {state!r}; "
                         f"a card's state must be one of: {', '.join(STATES)}.")


_NO_RECORD = object()


def _stored_state(item_id):
    try:
        with open(_item_path(item_id), encoding="utf-8") as source:
            return json.load(source).get("state")
    except (OSError, ValueError, AttributeError):
        return _NO_RECORD


def save_item(item):
    """Compare-and-swap the durable revision; never merge a stale whole record."""
    with mutation_lock():
        # A response projection is not durable workflow state, even if a
        # caller round-trips a record fetched from an API.
        item.pop("workflow_view", None)
        item.pop("lanes", None)
        path = _item_path(item["id"])
        # A state outside STATES sits in no lane: nothing runs it and nothing
        # shows it to Daniel (2026-09-25: fourteen 'queued' and 'done' cards).
        # Refuse to write one. A record already on disk in such a state may be
        # saved unchanged in state, so an unrelated write to it cannot take the
        # service down before hq/migrate_card_states.py has moved it.
        if item.get("state") not in STATES and item.get("state") != _stored_state(item["id"]):
            raise UnknownState(item["id"], item.get("state"))
        actual = validate_revision(item)
        # Repository work stays in the build lane even if a producer files it as doing.
        if int(item.get("tier") or 0) == 1 and item.get("state") == "doing":
            item["state"] = "waiting_session"
        saved = dict(item, _revision=actual + 1)
        _write_json(path, saved)
        item["_revision"] = saved["_revision"]
        return item


def _decision_owner(decision):
    """The person who owns a decision card; an unowned card falls to the Chief of Staff."""
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
    return owner if owner in people else "claude"


def file_ruling_integration(decision, ruling):
    """File the work a ruling unblocks the moment Daniel records it (Q-125 a).

    Before this a ruling sat as ``pending_integration`` until some session
    happened to look in the rulings folder.  Now recording the ruling puts an
    "integrate ruling" card in the queue, owned by the decision's owner, with
    his words on it.  Closing that card (``hq/card.py close``) marks the ruling
    integrated.  One card per submission: a repeated post files nothing new.
    """
    with mutation_lock():   # the look-up and the filing are one step across processes
        return _file_ruling_integration(decision, ruling)


def _file_ruling_integration(decision, ruling):
    decision_id = str(decision.get("id") or "")
    submission_id = str(ruling.get("submission_id") or "")
    for item in items():
        if (item.get("ruling_id") == decision_id
                and item.get("ruling_submission_id") == submission_id):
            return item
    owner = _decision_owner(decision)
    item = {"id": "w" + uuid.uuid4().hex[:11], "title": ruling_work_title(decision, ruling)}
    words = str(ruling.get("judgment") or "").strip()
    label = re.sub(r"\s*\(recommended\)\s*$", "", str(ruling.get("option_label") or ""), flags=re.I)
    ruling_text = (f"Daniel chose ({ruling.get('option')}) {label}."
                   + (f"\nIn his words: “{words}”" if words else ""))
    item.update({
        "level": "task", "owner": owner, "tier": 1,
        "tier_reason": ("Folding a ruling into the design docs and building what it "
                        "unblocks changes the repository; git can revert it."),
        "ask": (f"Daniel ruled on decision {decision_id}. Integrate the ruling: strike or annotate "
                f"{decision_id} in docs/DESIGNER_QUEUE.md (and docs/DECISION_LOG.md if it settles a "
                "decision), then do or file the work it unblocks. Do not close this card "
                "yourself: when your change lands, HQ closes it and marks the ruling "
                "integrated.\n\n"
                f"{ruling_text}")[:2400],
        "first_action": (f"Read decision card {decision_id} and the ruling, then find its entry "
                         "in docs/DESIGNER_QUEUE.md."),
        "state": "waiting_session", "thread": owner, "source": "ruling",
        "source_message": ruling_text[:2000], "result": "", "started": "", "attempts": 0,
        "created": _now_iso(), "created_ts": time.time(), "parent": decision_id,
        # ``decision_id`` stays reserved for revision hand-offs, which return
        # the decision to him; this card closes the ruling instead.
        "ruling_id": decision_id, "ruling_submission_id": submission_id,
    })
    return save_item(item)


def ruling_work_title(decision, ruling):
    """The queue row Daniel reads: which of his rulings, and what he chose."""
    subject = str(decision.get("subject") or decision.get("title") or decision.get("id") or "a decision")
    label = re.sub(r"\s*\(recommended\)\s*$", "", str(ruling.get("option_label") or ""), flags=re.I)
    title = f"Act on your ruling: {subject.rstrip('.?')} — you chose {label or ruling.get('option')}"
    return title if len(title) <= 160 else title[:157].rstrip() + "..."


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
    owner = _decision_owner(decision)
    now = _now_iso()
    item = {
        "id": "w" + uuid.uuid4().hex[:11],
        "title": f"Revise decision {decision_id}: {decision.get('title') or 'untitled decision'}"[:160],
        "level": "task", "owner": owner, "tier": 1,
        "tier_reason": "Daniel asked for the decision to be revised before he chooses.",
        "ask": ("Revise this decision using Daniel's feedback, then add a reply to the "
                f"decision card {decision_id} so it returns to his queue. Change only "
                f"hq/data/decisions/{decision_id}.json and its entry in "
                "docs/DESIGNER_QUEUE.md. Do not edit docs/design/: the design documents "
                "change after he rules, and a revision that touches them is held back "
                "instead of returning to his queue.\n\n"
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
    # Every drain process binds with this, including the recovery run HQ starts
    # each minute, so a card a live process is working is not a restart's
    # leftover. Resetting it made that run's result conflict and the card start
    # over every minute without counting an attempt (2026-10-07, Milo's barn).
    live = HOST.drain_state() if hasattr(HOST, "drain_state") else None
    entry = getattr(HOST, "drain_entry", None)
    for it in items():
        if it.get("state") == "doing" and it.get("started"):
            if live and entry and entry(live, it["id"]):
                continue
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

ONE STORY PER ITEM: each item asks for one finished outcome its owner can hand
back for review. Independent outcomes are separate items, even when they share
an owner; an implementation and its own tests are one outcome. Its first_action
names where the work starts — `path/to/file:line` or a function — whenever the
exchange makes that knowable, so the worker does not spend a session finding it.

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
{{"items": [{{"title": "short and plain", "level": "task|story|epic|project|goal", "owner": "<roster id>", "ask": "one sentence in Daniel's own terms", "first_action": "the single next concrete step, starting at path/to/file:line or a named function when known", "tier": 0, "tier_reason": "why that tier"}}]}}

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
raises no choice — a manufactured question costs him more than a missing one.

When the choice is among named options, also put inside "recommend": """ + OPTIONS_SPEC + "."

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
    # And tier 2 holds only with a named reason from ASK_FIRST.
    tier = follow_tier(raw)
    level = str(raw.get("level") or "task").lower()
    owner = str(raw.get("owner") or "").strip()
    if not any(e["id"] == owner for e in org["employees"]):
        owner = fallback_owner
    after = raw.get("after")
    after = [after] if isinstance(after, str) else after if isinstance(after, list) else []
    return {
        "title": title[:160],
        "owner": owner,
        "level": level if level in LEVELS else "task",
        "tier": tier,
        **({"ask_first": raw["ask_first"]} if tier == 2 else {}),
        **({"after": [str(a).strip()[:160] for a in after[:4] if str(a).strip()]} if after else {}),
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
        options = rec_options(rec.get("options"))
        rec = {k: str(rec.get(k) or "").strip()[:400]
               for k in ("question", "answer", "why", "instead")}
        if options:
            rec["options"] = options
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
# 'done' is not a state (it is not in STATES and save_item refuses to write it)
# but hand-written records carried it until 2026-09-25, so readers still treat
# it as closed rather than as open work. FINAL_STATES are the recognised ones.
TERMINAL_STATES = frozenset(("landed", "accepted", "dropped", "done"))
FINAL_STATES = ("landed", "accepted", "dropped")


# A card that names others in `after` waits for them (2026-10-02). Before this a
# prerequisite lived only as prose in the first step, so the drain started four
# pea cards at 12:32 that each came back "Blocked: not closed on origin/main"
# and sat in Daniel's list as dead results, while the card they waited on
# landed at 14:08. A prerequisite is met once that card is closed with its work
# done; a dropped one never will be, so the dependent goes to the chief of staff.
PREREQUISITE_MET = frozenset(("landed", "accepted", "done"))


def prerequisites(item, cards=None):
    """(waiting, dropped): the cards named in the item's `after` that have not
    landed, and those closed without landing, each as {"id", "title"}. `cards`
    maps id to card; without it each one is read from the store. A name the
    store does not hold is not waited for: filing checks every name, so a
    missing one is a card since archived, and waiting on it would be forever."""
    waiting, dropped = [], []
    for ident in item.get("after") or []:
        if not isinstance(ident, str) or ident == item.get("id"):
            continue
        card = (cards or {}).get(ident)
        if card is None and cards is None:
            try:
                card = load_item(ident)
            except (OSError, ValueError):
                card = None
        if card is None or card.get("state") in PREREQUISITE_MET:
            continue
        entry = {"id": ident, "title": str(card.get("title") or ident)}
        (dropped if card.get("state") == "dropped" else waiting).append(entry)
    return waiting, dropped


def clean_after(raw, own_id=""):
    """The `after` list a filer gave, as card ids the store holds, or an error.
    Accepts one id or a list."""
    names = [raw] if isinstance(raw, str) else list(raw or []) if isinstance(raw, (list, tuple)) else None
    if names is None:
        return None, "after must be a card id or a list of them."
    out = []
    for name in names:
        name = str(name or "").strip()
        if not name or name in out or name == own_id:
            continue
        if not re.fullmatch(WORK_ID, name) or not os.path.isfile(_item_path(name)):
            return None, f"after names {name!r}, which is not a work card."
        out.append(name)
    return out, ""


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


# The landing bar's last gate (drain.NEVER_LANDS): a clean result that touches
# the design documents, the deploy runbook, the store page or the build
# pipeline waits for Daniel's yes. The drain writes this sentence and the
# projection recognises it, so both live here. The earlier wording ("which
# undoing a commit would not put back the way it was") was muddled and not
# true of a document; cards held under it are still recognised.
APPROVAL_HOLD = "which records the studio's direction, so it needs Daniel's OK"
_OLD_APPROVAL_HOLD = "which undoing a commit would not put back the way it was"


def approval_hold_reason(path):
    return f"it changes {path}, {APPROVAL_HOLD}"


_PLAIN_FILES = {"docs/DECISION_LOG.md": "the decision log",
                "docs/DESIGNER_QUEUE.md": "the list of open design questions",
                "docs/DEPLOY.md": "the deploy runbook", "ITCH_PAGE.md": "the store page text",
                "hq/data/releases.json": "the release list"}


def plain_file(path):
    """A file named the way Daniel would say it."""
    if path in _PLAIN_FILES:
        return _PLAIN_FILES[path]
    if path.startswith("docs/design/") and path.endswith(".md"):
        stem = os.path.basename(path)[:-3]
        stem = re.sub(r"^\d+-", "", stem).replace("-", " ")
        return f"the {stem} design doc"
    if path.startswith("hq/data/decisions/"):
        return f"decision card {os.path.basename(path)[:-5]}"
    if path.startswith(".github/"):
        return "the build pipeline"
    return path


def _plain_list(names):
    names = list(dict.fromkeys(names))
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]


def approval_brief(item, org=None):
    """What Daniel needs on the page to answer a change held for his yes.

    2026-09-28, on the Q-131 card: "What does the title mean?" It read "Merge
    this reviewed change into the main code branch? It changes docs/design/
    06-bots-and-training.md, which undoing a commit would not put back the way
    it was." This says instead what the change is, where, what the review
    found, and what yes and no each do, in his words."""
    if not landing_awaits_approval(item):
        return None
    files = list((item.get("diff") or {}).get("files") or
                 ((item.get("attempt_outcome") or {}).get("candidate") or {}).get("files") or [])
    names = list(dict.fromkeys(plain_file(f) for f in files))
    # One or two documents are named; more are "the design docs", listed below
    # the question under "What changes".
    where = (_plain_list(names) if 0 < len(names) <= 2 else
             "the design docs" if names else "the project")
    people = {e.get("id"): e for e in ((org or {}).get("employees") or [])}
    who = str((people.get(item.get("owner")) or {}).get("name") or item.get("owner") or "The studio").split()[0]
    title = str(item.get("title") or "")
    if item.get("ruling_id"):
        chose = title.split("you chose", 1)[1].strip(" :—") if "you chose" in title else ""
        what = f"your {item['ruling_id']} ruling" + (f" (you chose: {chose})" if chose else "")
        question = f"Add {who}'s write-up of {what} to {where}?"
    else:
        question = f"Add {who}'s change to {where}? It is for: {title}"
    body = str(item.get("result") or "").partition(FOLLOW_MARK)[0].strip()
    summary = body.split("\n\n")[0][:700]
    check = (item.get("check") or {}).get("summary") or ""
    return {
        "question": question,
        "summary": summary,
        "files": [{"path": f, "name": plain_file(f)} for f in files],
        "why": ("The reviewer read it and found nothing wrong: " + check) if check else
               "The reviewer read it and found nothing wrong.",
        "reason": ("Design documents record your direction for the game, so the studio never "
                   "changes them without your OK."),
        "yes": (f"{who}'s edits become the official version of {where} within about ten minutes, "
                "once the tests pass. It can be undone later with one revert."),
        "no": (f"Nothing in {where} changes, and the card closes. To send it back to {who} "
               "instead, write a comment."),
        "changes_link": f"/work-change/{item['id']}",
    }


def landing_awaits_approval(item):
    """A finished, cleanly reviewed change whose only landing gate is Daniel's
    yes. Pure. Its next step is his decision, whatever older actions, blockers,
    run stamps or cost caps the card still carries (2026-09-28: the Q-130 and
    Q-131 ruling cards were projected as studio repairs and never reached him)."""
    if item.get("state") != "for_review" or item.get("completion") or item.get("pending_landing"):
        return False
    held = str((item.get("diff") or {}).get("why_not_landed") or "")
    if item.get("repair_hold") or not held.endswith((APPROVAL_HOLD, _OLD_APPROVAL_HOLD)):
        return False
    attempt = item.get("attempt_outcome") or {}
    check = item.get("check") or {}
    return (attempt.get("status") == "complete" and bool((attempt.get("candidate") or {}).get("files"))
            and check.get("read") is True and check.get("verdict") == "pass"
            and check.get("complete") is True and not check.get("findings")
            and check.get("attempt_id") == attempt.get("id"))


def _stable_patch_id_of(item_id, patch_id):
    """Git's line-position-free id of the held patch he is approving, so his yes
    still covers it after it is merged onto a main that moved around it. Empty
    when the stored patch is not the one the card showed him."""
    path = os.path.join(os.path.dirname(WORK), "patches", item_id + ".patch")
    try:
        with open(path, encoding="utf-8") as f:
            patch = f.read()
    except OSError:
        return ""
    if not patch or evidence_id(patch) != patch_id:
        return ""
    got = subprocess.run(["git", "patch-id", "--stable"], input=patch, capture_output=True,
                         text=True, timeout=60)
    return (got.stdout.split() or [""])[0]


def landing_approved(item):
    """Daniel's yes, bound to the exact reviewed patch it was given for."""
    patch = (item.get("attempt_outcome") or {}).get("patch_id")
    return bool(patch and (item.get("landing_approved") or {}).get("patch_id") == patch)


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

    repo_facts may contain blocked_files, cost_reason, active_session, head and
    prerequisites ({"waiting": [...], "dropped": [...]}, from `prerequisites`).
    No filesystem or clock reads occur when `now` is supplied.
    """
    facts = repo_facts or {}
    instant = time.time() if now is None else float(now)
    # A session HQ did not launch can claim a card (hq/card.py claim, Q-125).
    # While its lease is live the card is being worked exactly as if the drain
    # held it: the queue shows it as working and the drain does not start it.
    outside = item.get("outside_claim") if isinstance(item.get("outside_claim"), dict) else {}
    try:
        outside_live = float(outside.get("expires_ts") or 0) > instant
    except (TypeError, ValueError):
        outside_live = False
    if outside_live and not facts.get("active_session"):
        facts = {**facts, "active_session": "outside: " + str(outside.get("by") or "a session")}
    workflow = item.get("workflow") or {}
    actions = [dict(action) for action in workflow.get("actions") or []]
    active_actions = [a for a in actions if a.get("state") != "done"]
    blocked_files = sorted(set(facts.get("blocked_files") or []))
    repair = str(item.get("repair_hold") or "")
    exhausted_repair = bool(repair and item.get("automatic_repairs", 0) >= 1)
    cost_reason = str(facts.get("cost_reason") or "")
    supervised_retry = exhausted_repair and not cost_reason and bool(facts.get("supervised_retry"))
    # A saved rebrief is a capacity hold, not a coding job. The chief of staff
    # acts on it (review_spending_checkpoint): one bounded cap increase, or the
    # card goes to Daniel. Once a raised cap clears recorded spend, project the
    # normal build again.
    if not cost_reason:
        active_actions = [a for a in active_actions if a.get("type") != "rebrief"]
    waiting = item.get("waiting_for") or {}
    # Prerequisites hold only a card about to start: one already running, or
    # back with a result, is past the point where waiting would help.
    prereqs = facts.get("prerequisites") or {}
    prereq_waiting = list(prereqs.get("waiting") or [])
    prereq_dropped = list(prereqs.get("dropped") or [])
    not_started = (item.get("state") in ("waiting_session", "doing") and not item.get("started")
                   and not facts.get("active_session"))
    pending = item.get("pending_landing") or item.get("pending_followups")
    patch = (item.get("attempt_outcome") or {}).get("patch_id") or ""
    candidate = (item.get("attempt_outcome") or {}).get("candidate") or {}
    last_candidate = (workflow.get("candidates") or [{}])[-1]
    candidate_base = candidate.get("base") or last_candidate.get("base")
    # A candidate that changes no files has nothing to rebuild on a newer main,
    # as the drain's landing path already says. Reading it as stale projected a
    # reconcile whose id was already done, and a tier-0 reading raised to a
    # build was skipped every ten minutes (2026-09-27, w4afc0d9982d).
    stale = bool((candidate.get("files") if candidate else last_candidate.get("files"))
                 and candidate_base and facts.get("head") and candidate_base != facts["head"])
    input_id = (patch or candidate.get("tree") or
                ((workflow.get("candidates") or [{}])[-1].get("id")) or
                ((actions or [{}])[-1].get("input_id")) or
                str(item.get("last_recorded_attempt") or "legacy"))
    if item.get("revising"):
        # A revision asked for in the card's conversation is new input even when
        # no new patch exists yet. Without this its next step reused the id of a
        # step already done and the card read as a stalled recovery (2026-10-09,
        # the seed-clarity card after a "revise" reply).
        input_id = f"{input_id}:revision-{len(item.get('prior_results') or [])}"
    if supervised_retry:
        # One explicit invocation gets a distinct action for this failed attempt.
        # Repeating a queue read must never mint another repair action.
        input_id = action_key(item["id"], "supervised_retry",
                              str(item.get("last_recorded_attempt") or input_id))
    terminal = item.get("state") in TERMINAL_STATES
    ci_undo_hold = next((dict(b) for b in reversed(workflow.get("blockers") or [])
                         if b.get("type") == "ci_undo" and b.get("state") == "open"), None)
    if ci_undo_hold and not terminal:
        # The old CI poll is evidence, not the next step on a card whose
        # automatic revert could not be completed safely.
        active_actions = []
    # A clean result held only for Daniel's yes: earlier attempts' build and
    # reconcile actions, their blockers, the finished run's `started`, a stale
    # base (the merge rebuilds it) and the cost cap (his yes starts no model)
    # are all moot. Before his yes the next step is his; after it, the merge.
    awaiting_approval = not terminal and landing_awaits_approval(item)
    # A chief-of-staff checkpoint in his list (spending, or repairs used up)
    # asks him one question; the earlier attempt's steps, blockers and stale
    # base are what that question is about, not something holding it. Left in,
    # a stale candidate hid the question from his page.
    checkpoint_pending = (not terminal and item.get("state") == "needs_approval"
                          and bool(item.get("spending_checkpoint") or item.get("repair_checkpoint")))
    if checkpoint_pending:
        active_actions = [a for a in active_actions
                          if facts.get("active_session") and a.get("state") == "running"]
    if awaiting_approval:
        # Kept: the approved merge itself, and a step a live session is running.
        active_actions = [a for a in active_actions
                          if (landing_approved(item) and a.get("input_id") == "approved:" + patch)
                          or (facts.get("active_session") and a.get("state") == "running")]
    elif item.get("state") in HIS_STATES:
        # A new build is filed with the card back in the queue, so an open
        # build on a card in review is a leftover from an earlier attempt and
        # must not start model work again (2026-09-27, wbc6377da200).
        active_actions = [a for a in active_actions if a.get("type") != "build"]
    # A run that finished wrote its result; its `started` stamp is history,
    # not a claim that was lost.
    run_finished = (item.get("state") in HIS_STATES or
                    _iso_seconds(item.get("finished")) >= _iso_seconds(item.get("started")) > 0)
    blocker = None
    # Art the drain refused to generate (hq/art_requests.py, S-37) holds the card
    # for the chief of staff ahead of everything else: any other step would run
    # the owner again, who would only ask for the same art.
    art_hold = next((dict(b) for b in workflow.get("blockers") or []
                     if b.get("type") == "art_budget" and b.get("state") == "open"), None)
    # A card over its budget that the automatic review did not extend waits for
    # the chief of staff (S-38), ahead of every other step: each of them would
    # spend more, which is the question the hold is about.
    spending_hold = (not terminal and not checkpoint_pending
                     and isinstance(item.get("spending_checkpoint"), dict)
                     and item["spending_checkpoint"].get("held_for") == "claude")
    # Its sibling: a card whose repairs are used up and that the automatic
    # repair review did not retry or close waits for the chief of staff too
    # (S-38, extended 2026-09-29), ahead of every step that would run the owner.
    repairs_held = not terminal and not checkpoint_pending and not spending_hold and repair_held(item)
    if ci_undo_hold and not terminal:
        blocker = ci_undo_hold
    elif awaiting_approval or checkpoint_pending:
        pass
    elif spending_hold:
        blocker = {"type": "spending_hold", "files": [], "owner": "claude", "wake": CAP_HOLD_WAKE,
                   "reason": str(item["spending_checkpoint"].get("reason") or "").strip()
                   or "Over its token budget. Waiting for the chief of staff to extend, rescope or close it."}
    elif repairs_held:
        blocker = {"type": "repairs_used_up", "files": [], "owner": "claude", "wake": REPAIR_HOLD_WAKE,
                   "reason": str(item["repair_checkpoint"].get("reason") or "").strip()
                   or _repair_hold_reason(item, "")}
    elif art_hold and not terminal:
        blocker = art_hold
    elif blocked_files:
        blocker = {"type": "code_conflict", "reason": facts.get("tree_reason") or
                   "The candidate overlaps uncommitted repository files.",
                   "files": blocked_files, "owner": item.get("owner") or "claude"}
    elif not terminal and stale:
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
    elif prereq_dropped and not_started:
        names = ", ".join(f"“{p['title']}”" for p in prereq_dropped)
        blocker = {"type": "prerequisite_dropped", "files": [], "owner": "claude",
                   "reason": f"Waits for {names}, which was dropped, so it will never land.",
                   "wake": "The chief of staff rescopes this card, points it at other work, or closes it."}
    elif prereq_waiting and not_started:
        names = ", ".join(f"“{p['title']}”" for p in prereq_waiting)
        blocker = {"type": "prerequisite", "files": [], "owner": item.get("owner") or "claude",
                   "reason": f"Waits for {names} to land. It starts on its own once that work is on main.",
                   "wake": f"{names} lands.", "after": [p["id"] for p in prereq_waiting]}
    elif cost_reason:
        blocker = {"type": "capacity", "reason": cost_reason, "files": [],
                   "owner": "claude", "wake": "A reviewed, bounded cost cap above the amount already spent."}
    elif pending:
        blocker = {"type": "recovery", "reason": "An interrupted transaction needs recovery.",
                   "files": [], "owner": "claude"}
    elif item.get("started") and not facts.get("active_session") and not run_finished:
        blocker = {"type": "recovery", "reason": "The previous session no longer has a live claim.",
                   "files": [], "owner": "claude"}
    elif waiting.get("reason") and facts.get("waiting_for_valid", True):
        blocker = {"type": "dependency", "reason": waiting["reason"],
                   "files": waiting.get("files") or [], "owner": item.get("owner") or "claude"}
    persisted_open = next((b for b in reversed(workflow.get("blockers") or [])
                           if b.get("state") == "open"), None)
    if awaiting_approval:
        # Only a blocker on the approved merge itself still holds the card.
        blocker = next((dict(b) for b in reversed(workflow.get("blockers") or [])
                        if b.get("state") == "open"
                        and b.get("action_id") in {a.get("id") for a in active_actions}), None)
    elif checkpoint_pending:
        blocker = None
    elif blocker and persisted_open and persisted_open.get("type") == blocker["type"]:
        blocker = {**persisted_open, **blocker}
    elif not blocker and persisted_open:
        blocker = dict(persisted_open)
    if terminal:
        # Nothing holds a closed card. A landed card keeps its old `started`,
        # which read as a lost claim and put ~58 finished cards under
        # "awaiting verification" (w134a7424547).
        blocker = None
    stalled_transition = False
    # The generic landing-failure hold; the spending, repair and art holds each
    # project their own step and take precedence.
    chief_of_staff_hold = (blocker and blocker.get("owner") == "claude"
                           and not blocker.get("action_id") and blocker.get("wake")
                           and blocker.get("type") not in ("spending_hold", "repairs_used_up", "art_budget",
                                                           "prerequisite"))
    if not terminal and not active_actions:
        if chief_of_staff_hold:
            # A landing failure the chief of staff inspects: a visible, blocked
            # step of its own, so the card is held with its reason, never in no
            # lane (the same shape as the spending hold, S-38).
            kind, summary, priority = ("chief_hold", "The chief of staff inspects this landing failure and decides.",
                                       "reconciliation")
        elif blocker and blocker["type"] in ("code_conflict", "stale_base", "missing_evidence", "dependency"):
            kind = "reconcile"
            summary = "Reconcile the candidate with current main and obtain fresh review and tests."
            priority = "reconciliation"
        elif blocker and blocker["type"] == "recovery":
            kind, summary, priority = "recover", "Recover the interrupted transaction.", "reconciliation"
        elif blocker and blocker["type"] == "capacity":
            kind, summary, priority = "rebrief", "Review a bounded usage-cap increase before more work starts.", "reconciliation"
        elif blocker and blocker["type"] == "spending_hold":
            kind, summary, priority = ("spending_hold", "The chief of staff extends, rescopes or closes this card.",
                                       "reconciliation")
        elif blocker and blocker["type"] == "repairs_used_up":
            kind, summary, priority = ("repairs_used_up", "The chief of staff gives this card one more try, "
                                       "rescopes it or closes it.", "reconciliation")
        elif awaiting_approval and landing_approved(item):
            kind, summary, priority = "reconcile", "Merge the change Daniel approved into main.", "reconciliation"
            input_id = "approved:" + patch
        elif awaiting_approval:
            kind, summary, priority = "decide", "Approve merging this reviewed change: " + \
                str(item["diff"]["why_not_landed"]) + ".", "decision"
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
                # Held in plain sight: with no next action the card fell out of
                # every queue row and lane and stalled silently.
                active_actions = [{"id": action_key(item["id"], "recover", "stalled:" + proposed_id),
                                   "type": "recover", "input_id": proposed_id, "owner": "claude",
                                   "summary": "Inspect why a finished recovery did not move this card.",
                                   "priority": "reconciliation", "wake": "operator review",
                                   "created_at": item.get("finished") or item.get("created") or "",
                                   "state": "blocked", "virtual": True}]
        if not stalled_transition:
            active_actions = [{"id": proposed_id, "type": kind,
                           "input_id": input_id, "owner": ("daniel" if kind == "decide" else "claude" if kind in ("rebrief", "spending_hold", "chief_hold", "repairs_used_up")
                                                           or (awaiting_approval and kind == "reconcile") else item.get("owner") or "claude"),
                           "summary": summary, "priority": priority,
                           "created_at": item.get("finished") or item.get("created") or "",
                           "state": "open", "virtual": True}]
    # A repair step added beside an open action gets the same guard: an id
    # already finished cannot be claimed, so offering it as runnable made the
    # drain skip the card every tick (2026-09-27, w4afc0d9982d). Without it the
    # card stays held with its blocker's reason.
    finished_ids = {a.get("id") for a in actions if a.get("state") == "done"}
    if not terminal and not stalled_transition and blocker and not chief_of_staff_hold \
            and blocker["type"] in ("code_conflict", "stale_base", "missing_evidence", "dependency") \
            and not any(a.get("type") in ("reconcile", "recover") for a in active_actions) \
            and action_key(item["id"], "reconcile", input_id) not in finished_ids:
        active_actions.append({"id": action_key(item["id"], "reconcile", input_id),
                               "type": "reconcile", "input_id": input_id,
                               "owner": item.get("owner") or "claude",
                               "summary": "Reconcile the candidate with current main and obtain fresh review and tests.",
                               "priority": "reconciliation", "created_at": item.get("finished") or item.get("created") or "",
                               "state": "open", "virtual": True})
    if not terminal and not stalled_transition and blocker and blocker["type"] == "recovery" \
            and not any(a.get("type") == "recover" for a in active_actions) \
            and action_key(item["id"], "recover", input_id) not in finished_ids:
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
                                  (blocker and blocker["type"] == "capacity" and action.get("type") != "rebrief") or
                                  (blocker and blocker["type"] in ("art_budget", "spending_hold", "repairs_used_up")) or
                                  action.get("type") == "chief_hold" else
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
    elif next_action and next_action["type"] in ("reconcile", "recover", "rebrief", "spending_hold",
                                                 "chief_hold", "repairs_used_up"):
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
    if item.get("state") == "landed" and not landed_sha:
        # Landed with no commit: a reading changes no code, so there is no CI
        # to wait for. Anything else closed without its commit says so.
        shipped["no_code"] = (str(item.get("tier") or 0) == "0"
                              or completed.get("kind") == "reading")
    candidate_status = ("landed" if shipped["landed_sha"] else "none" if terminal else
                        ("reviewed" if landing_approved(item) else "awaiting_approval") if awaiting_approval else
                        "stale" if stale else
                        "held" if blocker else "reviewed" if (item.get("check") or {}).get("verdict") == "pass" else
                        "unverified" if candidate else "none")
    return {"version": WORKFLOW_VERSION, "phase": phase, "availability": availability,
            "next_action": next_action, "actions": all_actions, "blocker": blocker,
            "last_moved": last_moved, "candidate_status": candidate_status,
            "shipped_evidence": shipped,
            **({"outside_claim": {k: outside.get(k) for k in ("by", "since", "heartbeat", "expires")}}
               if outside_live and not terminal else {})}


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
    repairs = int(item.get("automatic_repairs", 0) or 0)
    if repairs >= 2:
        if check.get("verdict") == "concerns":
            # Two owner passes are enough. The chief of staff now turns the
            # remaining concern into a prepared decision if Daniel is truly
            # needed, or closes the handoff issue without spending his time.
            item.pop("repair_hold", None)
            item["state"] = "prepping"
            item["started"] = ""
            item["concern_review"] = {"owner": "claude", "attempts": 0}
            item["first_action"] = (
                "Read the remaining reviewer concern. Resolve it within the studio, or prepare "
                "the result for Daniel with the exact question, recommendation, evidence, and "
                "work his yes starts.")
            save_item(item)
            return True
        item["repair_hold"] = "The repair still needs verification; the owner must resolve the remaining findings."
        return False
    item["automatic_repairs"] = repairs + 1
    item["repair_brief"] = check.get("summary", "") + "\n" + json.dumps(check.get("findings") or [])
    item.setdefault("attempt_history", []).append(dict(attempt))
    requeue_for_revision(item)
    # The checked drain also handles read-only repairs; the intake worker must not claim them.
    item["state"] = "waiting_session"
    # A repair is a new build, so it gets a step of its own. Without one the
    # queue named the next build after the attempt just made, found that step
    # already done, and offered a "recover" that did nothing, so a repaired card
    # only moved again if main happened to change first (2026-09-27).
    attempt_key = str(item.get("last_recorded_attempt") or attempt.get("id") or "")
    ident = action_key(item["id"], "build", "repair:" + attempt_key)
    actions = _workflow(item)["actions"]
    if not any(a.get("id") == ident for a in actions):
        actions.append({"id": ident, "type": "build", "input_id": "repair:" + attempt_key,
                        "owner": item.get("owner") or "claude",
                        "summary": "Repair the last attempt using the reviewer's findings.",
                        "priority": "retry", "created_at": _now_iso(), "state": "open"})
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


def _open_twin(owner, key, exclude_id="", decision_key=""):
    """A card of the same owner and the same subject whose work has not run
    yet, or None. A finished or closed card is not a twin: work that follows a
    finished piece is new work, and an ask appended to a card whose run is over
    is an ask nobody will ever carry out."""
    for other in items():
        if other.get("id") == exclude_id or other.get("owner") != owner:
            continue
        if other.get("state") not in MERGEABLE_STATES:
            continue
        if decision_key and other.get("decision_key") == decision_key:
            return other
        if not decision_key and not other.get("decision_key") and merge_key(other.get("title")) == key:
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
    # A change held only for his yes carries its own question (merge it?),
    # recommendation (the clean review) and evidence (the reviewed diff).
    approval = landing_awaits_approval(item)
    deliverable = item.get("deliverable")
    if not isinstance(deliverable, dict) or not str(deliverable.get("name") or "").strip():
        missing.append("deliverable")
    evidence = deliverable.get("evidence") if isinstance(deliverable, dict) else None
    if not approval and (not isinstance(evidence, list) or not any(
            isinstance(entry, dict) and str(entry.get("href") or entry.get("path") or "").strip()
            for entry in evidence)):
        missing.append("evidence")
    question = ((item.get("recommend") or {}).get("question")
                if isinstance(item.get("recommend"), dict) else "")
    question = question or item.get("review_question")
    if not str(question or "").strip() and not approval:
        missing.append("question")
    if approval:
        pass
    elif item.get("recommendation_required") is not False:
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
            or item.get("pending_followups") or view.get("blocker") or cap_held(item)
            or repair_held(item)):
        return False
    if landing_awaits_approval(item):
        # Unlanded on purpose: the merge waits for exactly this verdict.
        return not landing_approved(item)
    # Code the studio has not yet verified or landed is the studio's, whatever
    # question a checkpoint put on the card: the Decisions page already read it
    # that way (queue.js, candidateNeedsLanding), and the navbar badge, which
    # asks here, counted a card the page did not show (wbecb4f98af1,
    # 2026-09-29). A change that waits only for his yes reads awaiting_approval
    # and is handled above.
    if int(item.get("tier") or 0) > 0 and view.get("candidate_status") in (
            "unverified", "reviewed", "held", "stale"):
        return False
    shipped = view.get("shipped_evidence") or {}
    unlanded_code = (item.get("state") == "for_review" and item.get("tier") in (1, 2)
                     and not shipped.get("landed_sha"))
    return not unlanded_code


def work_ready_for_daniel(item, workflow_view=None, preparation=None):
    """Single readiness predicate shared by the Work page and verdict inbox."""
    prep = preparation if preparation is not None else work_preparation(item)
    return work_reviewable(item, workflow_view) and prep["ready"]


# ---------------------------------------------------------------------------
# Every card in exactly one lane (the guard filed as w134a7424547, 2026-09-25).
#
# On 2026-09-25 twenty for_review cards sat in no lane: the drain skipped them
# because their next action was Daniel's verdict, and his page left them off
# because their code had no commit on main. Fourteen more carried states HQ
# does not know. Nothing said so. This projection names the lane each open
# card is in, and the health check below fails when a card is in none, in two,
# carries an unknown state, or is owned by nobody the org chart knows.
# ---------------------------------------------------------------------------

LANES = ("terminal", "running", "runner", "daniel", "held")
LANE_LABELS = {
    "terminal": "closed",
    "running": "being worked now",
    "runner": "next for a studio worker",
    "daniel": "on Daniel's Work page",
    "held": "held, with the reason shown on the task queue",
}
# The drain's scope (drain._queue_entries; 'doing' only on a --thinking run)
# and the actions its dispatcher runs (action_dispatch.MODEL_ACTIONS and
# RECOVERY_ACTIONS). Kept here so this module stays importable without drain.
_RUNNER_SCOPE = ("waiting_session", "for_review", "doing")
_DISPATCHED = ("build", "reconcile", "recover")


def card_lanes(item, view, preparation=None):
    """Every lane this card is in, given its workflow projection. Pure.

    A healthy card is in exactly one. 'held' means the task queue lists the
    card with a blocker's stated reason; a card whose next action is only
    somebody's verdict is not held, it is in Daniel's lane or in none.
    """
    state = item.get("state")
    if state in FINAL_STATES:
        return ["terminal"]
    view = view or {}
    action = view.get("next_action") or {}
    lanes = []
    if view.get("availability") == "running":
        lanes.append("running")
    else:
        in_scope = state in _RUNNER_SCOPE and action.get("type") not in (None, "decide")
        # HQ's own worker (work.worker): unstarted tier-0 work, questions being
        # prepared, and replies owed to him.
        prerequisite_hold = str((view.get("blocker") or {}).get("type") or "").startswith("prerequisite")
        hq_worker = ((state == "doing" and not item.get("started") and not prerequisite_hold)
                     or (state == "prepping" and not item.get("prep_stalled"))
                     or state == "owed" or bool(item.get("awaiting_reply")))
        if hq_worker or (in_scope and action.get("availability") == "runnable"
                         and action.get("type") in _DISPATCHED):
            lanes.append("runner")
        elif in_scope and str((view.get("blocker") or {}).get("reason") or "").strip():
            lanes.append("held")
    if work_reviewable(item, view):
        lanes.append("daniel")
    return lanes


def card_health(entries, org_ids):
    """Check every card: a known state, exactly one lane, one owner the org knows.

    `entries` is an iterable of (card, workflow projection) pairs; `org_ids`
    the employee ids in org.json. Returns counts per lane and one row per card
    that fails, each saying in plain words what is wrong. Reads only.
    """
    org_ids = set(org_ids)
    counts = {lane: 0 for lane in LANES}
    problems = []
    total = 0
    for item, view in entries:
        total += 1
        wrong = []
        state = item.get("state")
        if state not in STATES:
            wrong.append(f"its state {state!r} is not one HQ knows, so nothing runs it "
                         "and it never reaches Daniel")
        lanes = card_lanes(item, view) if state in STATES else []
        if state in STATES and not lanes:
            wrong.append("it is in no lane: no worker will pick it up, it is not on "
                         "Daniel's page, and nothing records why it is held")
        elif len(lanes) > 1:
            wrong.append("it is in two lanes at once: "
                         + " and ".join(LANE_LABELS[lane] for lane in lanes))
        if state not in FINAL_STATES:
            owner = item.get("owner")
            if not isinstance(owner, str) or not owner.strip():
                wrong.append("it has no single owner")
            elif owner not in org_ids:
                wrong.append(f"its owner {owner!r} is not anyone in the org chart")
        if len(lanes) == 1 and not wrong:
            counts[lanes[0]] += 1
        if wrong:
            problems.append({"id": item.get("id"), "title": item.get("title") or "Untitled",
                             "owner": item.get("owner") or "", "state": state,
                             "lanes": lanes, "problem": "; ".join(wrong) + "."})
    problems.sort(key=lambda row: str(row["id"]))
    return {"ok": not problems, "checked": total, "counts": counts, "problems": problems}


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
        **({"after": list(fields["after"])} if fields.get("after") else {}),
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
    ask_keys = "|".join(ASK_FIRST)
    ask_lines = "\n".join(f"  {key} — {means}" for key, means in ASK_FIRST.items())
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
past that it is a plan, and a plan is its own item. Each item is one finished
outcome (an implementation and its own tests count as one); its first_action
names where the work starts — `path/to/file:line` or a function — when you know it.
{amend}{move_note}
{{"deliverable": {{"name": "the short name of the finished result Daniel reviews"}}, "items": [{{"title": "short and plain", "owner": "<roster id>", "level": "task|story|epic|project|goal", "tier": 0|1|2, "ask_first": "only at tier 2: {ask_keys}", "after": ["the title of another item in this list that must land first"], "first_action": "the single next concrete step, starting at path/to/file:line or a named function when known", "why": "one sentence: why this follows"}}]{amend_field}{move_field}{outcome_field}}}

`deliverable.name` is for Daniel, not a rewrite of the ask: name the finished
thing he can inspect in a few plain words. It does not replace the ask of the
card you are finishing, which stays as it is.

TITLES: Daniel reads the queue title-first, so a title is read with nothing around it to settle what it means: no ticket IDs, and no verb that could mean its own opposite. "Hold the foley session" was read as both delay it and run it. Prefer the longer unambiguous verb — "Take the foley session off the schedule". The ask and first_action below are read by the agent that does the work, so write those for efficiency. Never put these words in a title — each is exact inside this studio and empty three feet away: suite (say "test suite"), stamp (say "record"), prove or proof (say "test" or "evidence"), attestation, invariant, provenance, cadence, parity, plumbing, orphan, manifest, harness, hygiene, tier, trace, gate, instrument, surface. Say the literal thing. docs/glossary.json is the full list and the build fails on it.

Tier each by how bad it is to get wrong with nobody reviewing it first:
0 — {t0}
1 — {t1}
2 — {t2}
Unknown blast radius is a 2, never a 0. Carrying out something already decided
is a 1 even when players will see it — putting a ruled price in the game,
adding a crop to the shop, drawing the art a design calls for: it lands behind
the test suites and one revert undoes it (S-16). A 2 names which of these it
is in `ask_first`, and one that names none is filed as a 1:
{ask_lines}
When an item cannot start until another item in this list has landed (code
that uses art not yet drawn, say), name that item's title in `after`: the card
waits in the queue and starts on its own once the other lands. Leave `after`
out otherwise. Each item goes to the person whose job
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
    run_id = "reading-" + uuid.uuid4().hex[:12]
    try:
        record = drain.do_item(item, org, run_id, lambda message: None)
    finally:
        # do_item records the card as being worked in runs/drain.json under
        # this process's pid. The drain's loop releases each item it finishes;
        # this path must too, because HQ's own pid never dies, and a card left
        # there reads as running forever, so its repair never reaches the drain.
        drain.release_phase(run_id, item)
        if not drain._PHASES:
            drain.record_phase(run_id, None, "finished", "HQ's own worker finished the card.")
    if record.get("held") or record.get("limited"):
        item["started"] = ""
        save_item(item)
        return False
    drain.write_back(item, record, False, "nothing changed", None, org)
    return True


def lineage_brief(item, limit=8000):
    """Daniel's own words from the cards above this one, for a worker that reads
    only its own card: the request at the top of the chain, and what he said on
    each card in between. A follow-up's ask is a one-line summary, so without
    this the owner of a grandchild never sees the spec (2026-10-07: the barn's
    design card was filed two steps below the request and held none of it)."""
    parent = item.get("parent")
    if not parent or WORK is None:
        return ""
    parts, seen = [], {item.get("id")}
    ask = item.get("ask") or ""
    while parent and parent not in seen and os.path.isfile(_item_path(parent)):
        seen.add(parent)
        card = load_item(parent)
        said = [m.get("text", "") for m in card.get("conversation", []) if m.get("role") == "daniel"]
        files = (card.get("diff") or {}).get("files") or []
        patch = os.path.join(os.path.dirname(WORK), "patches", card["id"] + ".patch")
        if files and not (card.get("diff") or {}).get("applied") and card.get("state") not in FINAL_STATES \
                and os.path.isfile(patch):
            parts.append(f"“{card.get('title', '')}” finished work that is not on main yet, so your copy "
                         f"does not have it: {', '.join(files[:8])}. Read it, without applying it, in {patch}.")
        if said:
            parts.append(f"What Daniel said on the card “{card.get('title', '')}”:\n" + "\n\n".join(said))
        if card.get("source") == "request" and card.get("source_message"):
            if card["source_message"] not in ask:
                parts.append("Daniel's request, in his words:\n" + card["source_message"])
            break
        parent = card.get("parent")
    if not parts:
        return ""
    text = "\n\n".join(reversed(parts))
    return ("\n\nWHERE THIS CARD COMES FROM — Daniel's own words from the cards above it. "
            "This card's ask summarises them; where the summary leaves something out, these govern:\n\n"
            + text[:limit] + "\n")


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
    filed = []           # (new card, the follow-up it came from), for `after`
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
        # A request card only routes his words; the work is in the child, and
        # a worker reads only its own card, so the child carries them whole.
        if item.get("source") == "request" and item.get("source_message"):
            ask += "\n\nDaniel's request, in his words:\n" + item["source_message"]
        if said:
            ask += ("\n\nDaniel attached this, and it is part of the brief:\n" + said)
        owner = fu.get("owner") or item["owner"]
        key = merge_key(fu["title"])
        # A shared decision must be identified by the filer. Similar wording
        # alone is insufficient evidence that two outcomes have one verdict.
        decision_key = str(fu.get("decision_key") or "").strip()
        # §5.4, one subject one card: the same work named twice in one result,
        # or named again while the first card is still open, joins that card
        # instead of filing a twin for the same person to read twice.
        twin = seen.get((owner, decision_key or key)) or _open_twin(
            owner, key, exclude_id=item["id"], decision_key=decision_key)
        if twin:
            if completion_key:
                twin.setdefault("completion_keys", []).append(completion_key)
            _merge_into(twin, item, fu, ask)
            started.append({"id": twin["id"], "title": twin["title"],
                            "state": twin["state"], "owner": twin["owner"],
                            "merged": True})
            seen[(owner, decision_key or key)] = twin
            continue
        child = _file_item({
            "title": fu["title"],
            "level": fu.get("level", "task"),
            "owner": owner,
            "tier": follow_tier(fu),
            "tier_reason": fu.get("why", "follows from this card"),
            "ask": ask,
            "first_action": fu.get("first_action", ""),
        }, cap, org)
        child["parent"] = item["id"]
        child["source_work"] = [{"id": item["id"], "card": item["title"], "title": fu["title"]}]
        if decision_key:
            child["decision_key"] = decision_key
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
        seen[(owner, decision_key or key)] = child
        filed.append((child, fu))
        started.append({"id": child["id"], "title": child["title"],
                        "state": child["state"], "owner": child["owner"]})
    # A follow-up that needs another one's work first names it in `after`, by
    # its title in this same list (or by card id), and waits for it in the
    # queue: the pea shelf needs the pea packet's picture before it can use it.
    by_title = {merge_key(entry["title"]): entry["id"] for entry in started}
    for child, fu in filed:
        after = []
        for name in fu.get("after") or []:
            ident = by_title.get(merge_key(name)) or (
                name if re.fullmatch(WORK_ID, name) and os.path.isfile(_item_path(name)) else "")
            if ident and ident != child["id"] and ident not in after:
                after.append(ident)
        if after:
            child["after"] = after
            save_item(child)
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
    source = {"id": parent["id"], "card": parent["title"], "title": fu["title"]}
    # Legacy cards may have only parent/merged_from. Preserve that lineage
    # when the first new source_work entry is added, and deduplicate by ID.
    sources = list(twin.get("source_work") or [])
    if twin.get("parent"):
        sources.insert(0, {"id": twin["parent"], "card": twin.get("title", ""),
                           "title": twin.get("title", "")})
    sources.extend(twin.get("merged_from") or [])
    sources.append(source)
    twin["source_work"] = list({s["id"]: s for s in sources if isinstance(s, dict) and s.get("id")}.values())
    if fu.get("decision_key") and not twin.get("decision_key"):
        twin["decision_key"] = str(fu["decision_key"]).strip()
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
missing any part comes straight back to you. When the choice is among named
options, also put inside "recommend": {OPTIONS_SPEC}.

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


def _concern_recommendation(item):
    """A complete, conservative decision when the studio cannot clear a concern."""
    check = item.get("check") or {}
    concern = str(check.get("summary") or "The reviewer concern remains unresolved.").strip()
    return {
        "question": f"Accept this work with the unresolved concern: {concern}",
        "answer": "Send it back for a supervised studio repair.",
        "why": "The chief of staff could not establish that the concern is limited to internal handoff notes.",
        "instead": "Accept the result with the reviewer concern still recorded.",
    }


def resolve_review_concern(item, org):
    """Let the chief of staff clear an internal concern or send a real choice to Daniel."""
    if not execution.launch_allowed():
        return False
    review = item.setdefault("concern_review", {"owner": "claude", "attempts": 0})
    review["owner"] = "claude"
    review["attempts"] = int(review.get("attempts", 0) or 0) + 1
    save_item(item)
    check = item.get("check") or {}
    prompt = f"""You are Adam, Tiny Farm Studio's chief of staff. Two owner repairs left
this reviewer concern. Decide whether it concerns only internal handoff notes, which you
may clear, or whether Daniel must decide. Do not clear a concern about the deliverable,
player experience, money, schedule, or technical correctness.

WORK: {item.get('title', '')}
RESULT: {(item.get('result') or '')[:6000]}
CONCERN: {check.get('summary', '')}
FINDINGS: {json.dumps(check.get('findings') or [])}

Return JSON only. For an internal handoff issue:
{{"outcome":"resolved","reason":"why Daniel is not needed"}}
For anything Daniel must decide, include all four recommendation fields:
{{"outcome":"daniel","reason":"why only he can decide","recommend":{{"question":"...","answer":"...","why":"...","instead":"..."}}}}
"""
    text, limited = _run_cli(prompt, HOST.build_system_prompt(org, "claude"),
                             "Read,Glob,Grep", HOST.MAX_TURNS, 420,
                             model=HOST.seat_model(org, "claude"), phase="concern-review",
                             seat="claude", item=item["id"])
    doc = None
    if not limited:
        try:
            doc = json.loads((text or "").strip())
        except (TypeError, ValueError):
            doc = None
    if isinstance(doc, dict) and doc.get("outcome") == "resolved" and str(doc.get("reason") or "").strip():
        item["concern_resolution"] = {"by": "claude", "reason": str(doc["reason"]).strip()[:800]}
        item["check"] = {**check, "verdict": "pass", "complete": True, "findings": []}
        item["repair_hold"] = "The chief of staff cleared the remaining internal handoff concern; re-run the landing check."
        item["supervised_retry"] = True
        item["state"] = "for_review"
        item.pop("concern_review", None)
        save_item(item)
        return True
    draft = doc.get("recommend") if isinstance(doc, dict) else None
    if not recommendation_gaps(draft):
        item["recommend"] = {key: str(draft[key]).strip()[:400] for key in REC_PARTS}
        item["concern_resolution"] = {"by": "claude", "reason": str(doc.get("reason") or "").strip()[:800]}
        item["state"] = "needs_approval"
        item.pop("concern_review", None)
        save_item(item)
        return True
    if review["attempts"] < PREP_TRIES and limited:
        save_item(item)
        return False
    item["recommend"] = _concern_recommendation(item)
    item["concern_resolution"] = {"by": "claude", "reason": "The chief-of-staff review did not produce a safe internal ruling."}
    item["state"] = "needs_approval"
    item.pop("concern_review", None)
    item.pop("prep_stalled", None)
    save_item(item)
    return True


# ---------------------------------------------------------------------------
# The per-card spending checkpoint (drain.item_capacity_reason).
#
# Daniel's policy, 2026-09-28: the cap is a checkpoint, not a wall. A card whose
# spending is buying progress runs on past it. Before this, the projected
# "rebrief" step had no runner and capped cards sat for days. The chief of staff
# reviews one card per background pass; each extension is one bounded step on
# the cap that was actually exceeded, recorded on the card.
#
# His ruling of 2026-09-29 (S-38): a card over its budget is the chief of
# staff's to extend, rescope or close. It never goes to Daniel's page as a "keep
# spending?" question. Where the automatic review stops (extensions used up, a
# cap past its ceiling, a review that judges it is not converging, or a review
# that gave no usable answer) the card stays in the queue, held for the chief of
# staff with the reason shown, until `hq/card.py extend` or a close settles it.
# On 2026-09-29 six cards sat in no lane: sent to his page, then kept off it
# because their code had not landed.
# ---------------------------------------------------------------------------

CAP_FIELDS = {"tokens": "token_cap", "fresh": "fresh_token_cap", "usd": "cost_cap_usd"}
CAP_STEPS = {"tokens": 1_000_000, "fresh": 150_000, "usd": 20.0}
# Past these, or after CAP_AUTO_EXTENSIONS extensions, no model is asked: the
# card is held for the chief of staff.
CAP_CEILINGS = {"tokens": 10_000_000, "fresh": 1_500_000, "usd": 200.0}
CAP_AUTO_EXTENSIONS = 3
CAP_REVIEW_TRIES = 3
CHIEF_AUTOMATIC_TRIES = 2
CAP_REVIEW_STATES = ("waiting_session", "for_review")
# How often the background worker looks for a card at its checkpoint.
CAP_SCAN_SECONDS = 120
_CAP_SCAN = {"at": 0.0}


def _count_words(n):
    n = int(n or 0)
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f} million"
    return f"{n:,}"


def spending_checkpoint_state(item):
    """(spent, caps, exceeded) measured from the card's recorded model sessions."""
    import drain
    dollars, attempts, tokens, fresh = drain._item_spend(item["id"])
    caps = {"tokens": int(item.get("token_cap") or drain.ITEM_TOKEN_CAP),
            "fresh": int(item.get("fresh_token_cap") or drain.ITEM_FRESH_TOKEN_CAP),
            "usd": float(item.get("cost_cap_usd") or drain.ITEM_COST_CAP_USD)}
    spent = {"tokens": int(tokens), "fresh": int(fresh), "usd": round(float(dollars), 2),
             "attempts": int(attempts or item.get("attempts") or 0)}
    # The same comparisons drain.item_capacity_reason makes.
    exceeded = [k for k in ("tokens", "fresh") if spent[k] >= caps[k]]
    if dollars > caps["usd"]:
        exceeded.insert(0, "usd")
    return spent, caps, exceeded


def raised_caps(spent, caps, exceeded):
    """One bounded step above what was spent, on the exceeded caps only."""
    new = dict(caps)
    for key in exceeded:
        step = max(caps[key], spent[key]) + CAP_STEPS[key]
        new[key] = round(float(step), 2) if key == "usd" else int(step)
    return new


def _cap_record(caps):
    return {CAP_FIELDS[k]: caps[k] for k in CAP_FIELDS}


def _spend_sentence(spent):
    tries = spent["attempts"]
    dollars = f", about ${spent['usd']:.0f} at API list price," if spent["usd"] >= 1 else ""
    return (f"This card has spent {_count_words(spent['tokens'])} tokens "
            f"({_count_words(spent['fresh'])} of them new){dollars} over {tries} "
            f"attempt{'' if tries == 1 else 's'}.")


def _cap_review_entry(by, decision, spent, old, new, reason):
    return {"at": _now_iso(), "by": by, "decision": decision,
            "spent_tokens": spent["tokens"], "spent_fresh": spent["fresh"],
            "spent_usd": spent["usd"], "attempts": spent["attempts"],
            "old_caps": _cap_record(old), "new_caps": _cap_record(new),
            "reason": str(reason or "").strip()[:800]}


def _apply_caps(item, new, exceeded):
    for key in exceeded:
        item[CAP_FIELDS[key]] = new[key]


def _cap_review_prompt(item, spent, caps, exceeded):
    history = [{"status": a.get("status"), "reason": str(a.get("reason") or "")[:400]}
               for a in (item.get("attempt_history") or [])[-4:]]
    checks = [{"verdict": c.get("verdict"), "summary": str(c.get("summary") or "")[:400],
               "findings": [str((f or {}).get("what") if isinstance(f, dict) else f)[:300]
                            for f in (c.get("findings") or [])[:4]]}
              for c in ((item.get("prior_checks") or []) + ([item["check"]] if item.get("check") else []))[-4:]]
    over = ", ".join(f"{CAP_FIELDS[k]} {caps[k]:,} (spent {spent[k]:,})" for k in exceeded)
    # What the studio itself changed about the card. On 2026-09-28 the first review
    # read four read-only failures as "not converging", though the card had just
    # been moved to a writable copy and had never tried with one.
    changed = [str(x) for x in (
        item.get("tier_raised") and f"Moved to a build worker with write access at {item['tier_raised'].get('at')}: {item.get('tier_reason')}",
        *[f"Earlier spending review ({r.get('by')}, {r.get('decision')}): {r.get('reason')}" for r in (item.get("cap_reviews") or [])[-2:]],
    ) if x]
    return f"""You are the chief of staff of Tiny Farm Studio. A work card has reached its
per-card spending checkpoint. Daniel's policy: the cap is a checkpoint, not a wall. If the
spending is buying progress, let it run one more bounded step. If the card burned tokens
without converging (the same failure repeating), it needs a rethink: it is held in the
queue for the chief of staff to extend with a new brief, rescope or close. It never goes
to Daniel.

WORK: {item.get('title', '')}
ASK: {str(item.get('ask') or '')[:1500]}
ATTEMPTS: {spent['attempts']}
SPENT: {spent['tokens']:,} tokens, {spent['fresh']:,} of them fresh, ${spent['usd']:.2f} list price
CAPS NOW: token_cap {caps['tokens']:,}, fresh_token_cap {caps['fresh']:,}, cost_cap_usd {caps['usd']:.0f}
EXCEEDED: {over}
ATTEMPT HISTORY (oldest first): {json.dumps(history)}
REVIEWER CHECKS (oldest first): {json.dumps(checks)}
LATEST RESULT: {str(item.get('result') or '')[:3000]}
WHAT THE STUDIO CHANGED ABOUT THIS CARD: {json.dumps(changed) if changed else "nothing recorded"}

A failure the studio has since fixed (for example a card moved to a writable copy after
attempts that could only read) is not the owner failing to converge.
Choose "extend" only if the attempts are converging: later checks narrower or closer
than earlier ones, or the remaining work concrete and small. If the same failure
repeats, or the checks show no convergence, choose "hold".

Return JSON only. To extend by one bounded step:
{{"outcome":"extend","reason":"why the spending is buying progress and what concrete work remains"}}
To hold it for the chief of staff, in plain words: what keeps failing, and what you would
change before any more is spent. The queue shows your reason beside the card.
{{"outcome":"hold","reason":"what keeps failing","suggest":"what the rework should be, or why it should close"}}
"""


def _json_reply(text):
    raw = (text or "").strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        raw = raw[raw.find("{"):] if "{" in raw else raw
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        pass
    start, end = raw.find("{"), raw.rfind("}")
    if start >= 0 and end > start:
        try:
            return json.loads(raw[start:end + 1])
        except ValueError:
            return None
    return None


CAP_HOLD_WAKE = ("The chief of staff extends it one bounded step (python3 hq/card.py extend), "
                 "rescopes it, or closes it.")


def _over_what(exceeded):
    return "cost limit" if list(exceeded) == ["usd"] else "token budget"


def _cap_hold_reason(exceeded, why):
    """The sentence the queue shows beside a card held at its spending checkpoint."""
    why = str(why or "").strip().rstrip(".")
    return (f"Over its {_over_what(exceeded)}{'; ' + why if why else ''}. Waiting for the "
            "chief of staff to extend, rescope or close it.")


def cap_held(item):
    """True when the card waits on the chief of staff at its spending checkpoint."""
    pending = item.get("spending_checkpoint")
    return isinstance(pending, dict) and pending.get("held_for") == "claude"


def _cap_hold(item, spent, caps, exceeded, why, suggestion=""):
    """Hold the card in the queue for the chief of staff (S-38): the limit is left
    as it is, the reason is shown on the queue, and nothing goes to Daniel. The
    card keeps its queue state, so the lane check reads it as held, not lost."""
    state = item.get("state")
    item["spending_checkpoint"] = {
        "at": _now_iso(), "held_for": "claude",
        "return_state": state if state in CAP_REVIEW_STATES else "waiting_session",
        "exceeded": list(exceeded), "reason": _cap_hold_reason(exceeded, why),
        **({"suggestion": str(suggestion).strip()[:800]} if str(suggestion or "").strip() else {}),
        "restore": {}, "repair_hold": None}
    item.setdefault("cap_reviews", []).append(
        _cap_review_entry("claude", "hold", spent, caps, caps, why))
    item.pop("cap_review_tries", None)
    return save_item(item)


def hold_checkpoints_for_chief_of_staff():
    """Move every card the old path sent to Daniel as a "keep spending?" question
    into the held-for-the-chief-of-staff state (S-38). Idempotent: a held card is
    no longer in needs_approval, so a second run finds nothing. Run by each drain
    and at HQ's start. Returns the ids moved."""
    moved = []
    for item in items():
        if item.get("state") != "needs_approval" or not isinstance(item.get("spending_checkpoint"), dict):
            continue
        with mutation_lock():
            fresh = load_item(item["id"])
            if _hold_legacy_checkpoint(fresh):
                save_item(fresh)
                moved.append(fresh["id"])
    return moved


def _hold_legacy_checkpoint(item):
    """In memory: a needs_approval spending checkpoint becomes a hold for the
    chief of staff. The fields the question borrowed are put back as they were,
    and a repair hold it set aside returns to the card."""
    pending = item.get("spending_checkpoint")
    if item.get("state") != "needs_approval" or not isinstance(pending, dict):
        return False
    for key in ("recommend", "deliverable", "follow_ups"):
        item.pop(key, None)
    item.update(pending.get("restore") or {})
    if pending.get("repair_hold") and not item.get("repair_hold"):
        item["repair_hold"] = pending["repair_hold"]
    exceeded = [k for k in pending.get("exceeded") or [] if k in CAP_FIELDS] or ["tokens"]
    back = pending.get("return_state")
    item["state"] = back if back in CAP_REVIEW_STATES else "waiting_session"
    why = "it had been sent to Daniel before over-budget cards became the chief of staff's call"
    item["spending_checkpoint"] = {
        "at": _now_iso(), "held_for": "claude", "return_state": item["state"],
        "exceeded": exceeded, "moved_from": "needs_approval", "asked_at": pending.get("at"),
        "reason": _cap_hold_reason(exceeded, why),
        "restore": {}, "repair_hold": None}
    spent, caps, _exceeded = spending_checkpoint_state(item)
    item.setdefault("cap_reviews", []).append(_cap_review_entry("claude", "hold", spent, caps, caps, why))
    return True


def _cap_extend(item, spent, caps, exceeded, reason, by="claude"):
    new = raised_caps(spent, caps, exceeded)
    _apply_caps(item, new, exceeded)
    item.setdefault("cap_reviews", []).append(
        _cap_review_entry(by, "extend", spent, caps, new, reason))
    item.pop("cap_review_tries", None)
    return save_item(item)


def _cap_reviewable(item):
    return (item.get("state") in CAP_REVIEW_STATES and item.get("state") not in TERMINAL_STATES
            and not item.get("spending_checkpoint") and not repair_held(item)
            and not landing_awaits_approval(item))


def review_spending_checkpoint(item, org):
    """The chief of staff's review of one card stopped at its spending cap."""
    if not execution.launch_allowed() or not _cap_reviewable(item):
        return False
    spent, caps, exceeded = spending_checkpoint_state(item)
    if not exceeded:
        return False
    extensions = sum(1 for r in item.get("cap_reviews") or [] if r.get("decision") == "extend")
    raised = raised_caps(spent, caps, exceeded)
    past = [k for k in exceeded if raised[k] > CAP_CEILINGS[k]]
    # Hard limits: decided here, with no model call.
    if extensions >= CAP_AUTO_EXTENSIONS or past:
        why = (f"after {extensions} extensions" if extensions >= CAP_AUTO_EXTENSIONS else
               "one more step would take it past the most the studio lets a card spend on its own")
        _cap_hold(item, spent, caps, exceeded, why)
        return True
    item["cap_review_tries"] = int(item.get("cap_review_tries") or 0) + 1
    save_item(item)
    text, limited = _run_cli(_cap_review_prompt(item, spent, caps, exceeded),
                             HOST.build_system_prompt(org, "claude"), "Read,Glob,Grep", 8, 300,
                             model=HOST.seat_model(org, "claude"), phase="cap-review",
                             seat="claude", item=item["id"])
    doc = None if limited else _json_reply(text)
    doc = doc if isinstance(doc, dict) else {}
    reason = str(doc.get("reason") or "").strip()
    with mutation_lock():
        # The call took minutes; decide on the card as it is now.
        fresh = load_item(item["id"])
        if not _cap_reviewable(fresh):
            item.clear(); item.update(fresh)
            return False
        if limited:
            # The allowance ran dry mid-review: nothing was judged, so the try is
            # given back. An empty window must never put a card in front of Daniel.
            fresh["cap_review_tries"] = max(0, int(fresh.get("cap_review_tries") or 1) - 1)
            save_item(fresh)
            item.clear(); item.update(fresh)
            return False
        if doc.get("outcome") == "extend" and reason:
            _cap_extend(fresh, spent, caps, exceeded, reason)
        elif doc.get("outcome") in ("hold", "daniel") and reason:
            # "daniel" is the answer the old prompt asked for; it is read as a
            # hold too, since nothing over budget goes to him any more (S-38).
            rec = doc.get("recommend") if isinstance(doc.get("recommend"), dict) else {}
            _cap_hold(fresh, spent, caps, exceeded,
                      "the automatic spending review found it is not converging: " + reason,
                      doc.get("suggest") or rec.get("answer") or "")
        elif int(fresh.get("cap_review_tries") or 0) < CAP_REVIEW_TRIES:
            item.clear(); item.update(fresh)
            return False              # tried again on a later pass
        else:
            _cap_hold(fresh, spent, caps, exceeded,
                      f"the automatic spending review gave no usable answer after "
                      f"{CAP_REVIEW_TRIES} tries")
        item.clear(); item.update(fresh)
    return True


def spending_checkpoints_due():
    """Cards whose projected next step is the capacity rebrief, oldest first.
    The same projection the queue uses, so it names the cards the queue holds."""
    import drain
    candidates = [i for i in items() if _cap_reviewable(i) and drain.item_capacity_reason(i)]
    if not candidates:
        return []
    got = drain.sh(["git", "rev-parse", "main"], cwd=drain.REPO, timeout=10)
    head = got.stdout.strip() if got.returncode == 0 else ""
    active = drain.server.drain_state()
    due = []
    for item in candidates:
        action = drain.project_work(item, head=head, active=active).get("next_action") or {}
        # A card whose repairs are used up and that is also over its cap waits
        # on the repair hold, not a rebrief step; its spending is still this
        # review's to settle first, or no review ever reaches it.
        if action.get("availability") != "running" and (
                action.get("type") == "rebrief"
                or (exhausted_repair(item) and action.get("availability") == "waiting_event")):
            due.append(item)
    due.sort(key=lambda i: i.get("created_ts", 0))
    return due


def review_next_spending_checkpoint(org):
    """One card per pass, and nothing while he has paused the studio or the
    model allowance is dry."""
    if not execution.launch_allowed() or HOST.limited_until():
        return False
    due = spending_checkpoints_due()
    return review_spending_checkpoint(due[0], org) if due else False


def _chief_review_prompt(item):
    pending = item.get("spending_checkpoint") or item.get("repair_checkpoint") or {}
    findings = ((item.get("check") or {}).get("findings") or [])[-6:]
    return f"""You are Tiny Farm Studio's chief of staff, running automatically on Codex.
This card is held for your judgement. Move it if an engineering-management answer is possible.
Taste, player-facing direction, dates, money, and credentials belong to Daniel: identify those as taste.

WORK: {item.get('title', '')}
ASK: {str(item.get('ask') or '')[:2400]}
HOLD: {str(pending.get('reason') or '')[:1200]}
SUGGESTION: {str(pending.get('suggestion') or '')[:800]}
REVIEWER FINDINGS: {json.dumps(findings)}
LATEST RESULT: {str(item.get('result') or '')[:2400]}

Return JSON only, one of:
{{"outcome":"extend","reason":"why","brief":"instruction quoting the concrete reviewer finding"}}
{{"outcome":"rescope","reason":"why","ask":"complete narrower ask that can pass","brief":"first concrete step"}}
{{"outcome":"close","reason":"why it is superseded or landed","evidence":"the current landing SHA or superseding card ID recorded on this card"}}
{{"outcome":"taste","reason":"why only Daniel can decide","question":"the choice in Daniel's terms","recommend":"recommended answer","why":"one deciding reason","instead":"honest alternative"}}
"""


def _file_taste_decision(item, doc):
    """Keep a draft on the live work card until normal curation can review it."""
    item["decision_draft"] = {
        "by": "claude", "at": _now_iso(), "source_work": item["id"],
        "finding": _chief_finding(item),
        "question": str(doc["question"]).strip()[:500],
        "reason": str(doc["reason"]).strip()[:800],
        "options": [str(doc["recommend"]).strip()[:500],
                    str(doc["instead"]).strip()[:500]],
        "recommend": str(doc["recommend"]).strip()[:500],
        "why": str(doc["why"]).strip()[:800],
    }
    return item["decision_draft"]


def _chief_finding(item):
    check = item.get("check") or {}
    findings = check.get("findings") or []
    for finding in findings:
        value = finding.get("what") if isinstance(finding, dict) else finding
        if str(value or "").strip():
            return str(value).strip()[:400]
    return str(check.get("summary") or item.get("repair_hold") or
               (item.get("spending_checkpoint") or {}).get("reason") or
               (item.get("repair_checkpoint") or {}).get("reason") or "").strip()[:400]


def _chief_brief_grounded(item, brief):
    finding = _chief_finding(item)
    return bool(finding and finding.lower() in brief.lower())


def _chief_close_evidence(item, doc):
    evidence = str(doc.get("evidence") or "").strip()
    # Prose in an old result or check is not proof that this card's work is on
    # current main. Require a durable landing SHA, or a named canonical card
    # that has itself landed.
    completion = item.get("completion") or {}
    sha = str(completion.get("sha") or (item.get("landed") or {}).get("sha") or "").strip()
    if sha and evidence == sha:
        return _chief_sha_on_main(sha)
    canonical_id = str(item.get("superseded_by") or "").strip()
    if canonical_id and evidence == canonical_id and canonical_id != item["id"]:
        try:
            canonical = load_item(canonical_id)
        except (OSError, ValueError):
            return False
        canonical_sha = str((canonical.get("completion") or {}).get("sha") or "").strip()
        return canonical.get("state") == "landed" and _chief_sha_on_main(canonical_sha)
    return False


def _chief_sha_on_main(sha):
    """Check a recorded full commit ID against main, not a prose claim."""
    if not re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", str(sha or "")):
        return False
    import drain
    return drain.sh(["git", "merge-base", "--is-ancestor", sha, "main"],
                    cwd=drain.REPO, timeout=10).returncode == 0


def _chief_hold_matches(item, hold_kind):
    if item.get("state") in TERMINAL_STATES or item.get("decision_draft"):
        return False
    if hold_kind == "spending_hold":
        return cap_held(item)
    if hold_kind == "repairs_used_up":
        return repair_held(item)
    if hold_kind in ("chief_hold", "art_budget"):
        return any(b.get("state") == "open" and
                   (b.get("type") == "art_budget" if hold_kind == "art_budget" else
                    b.get("owner") == "claude" and b.get("wake") and not b.get("action_id")
                    and b.get("type") not in ("spending_hold", "repairs_used_up", "art_budget", "ci_undo"))
                   for b in _workflow(item).get("blockers") or [])
    return not hold_kind and (cap_held(item) or repair_held(item))


def _chief_spending_step_allowed(item):
    spent, caps, exceeded = spending_checkpoint_state(item)
    exceeded = exceeded or [k for k in (item.get("spending_checkpoint") or {}).get("exceeded") or []
                            if k in CAP_FIELDS]
    extensions = sum(r.get("decision") == "extend" for r in item.get("cap_reviews") or [])
    raised = raised_caps(spent, caps, exceeded)
    return (extensions < CAP_AUTO_EXTENSIONS
            and all(raised[key] <= CAP_CEILINGS[key] for key in exceeded))


def review_chief_hold(item, org, hold_kind=""):
    """Give a Codex chief-of-staff review a held card's ordinary moves.

    Two unusable reviews leave the card held for a live session. Taste always
    stays held and receives a decision-card draft rather than an invented call.
    """
    if not execution.launch_allowed() or hold_kind in ("no_lane", "ci_undo"):
        return False
    with mutation_lock():
        fresh = load_item(item["id"])
        if (fresh.get("_revision") != item.get("_revision")
                or not _chief_hold_matches(fresh, hold_kind)
                or int(fresh.get("chief_review_tries") or 0) >= CHIEF_AUTOMATIC_TRIES):
            item.clear(); item.update(fresh)
            return False
        fresh["chief_review_tries"] = int(fresh.get("chief_review_tries") or 0) + 1
        save_item(fresh)
        item.clear(); item.update(fresh)
        launched_revision = fresh["_revision"]
    text, limited = _run_cli(_chief_review_prompt(item), HOST.build_system_prompt(org, "claude"),
                             "Read,Glob,Grep", 8, 300, model="gpt-6-astra",
                             phase="chief-review", seat="claude", item=item["id"])
    doc = {} if limited else (_json_reply(text) or {})
    with mutation_lock():
        fresh = load_item(item["id"])
        if (fresh.get("_revision") != launched_revision
                or not _chief_hold_matches(fresh, hold_kind)):
            item.clear(); item.update(fresh)
            return False
        if limited:
            item.clear(); item.update(fresh)
            return False
        outcome = doc.get("outcome")
        reason, brief = str(doc.get("reason") or "").strip(), str(doc.get("brief") or "").strip()
        moved = False
        if (outcome == "extend" and reason and _chief_brief_grounded(fresh, brief)
                and (not cap_held(fresh) or _chief_spending_step_allowed(fresh))):
            if cap_held(fresh):
                grant_spending_checkpoint(fresh, by="claude", reason=brief, via="automatic chief-of-staff review (Codex)")
            elif repair_held(fresh):
                grant_repair_checkpoint(fresh, by="claude", brief=brief, via="automatic chief-of-staff review (Codex)")
            else:
                release_chief_hold_for_capability(fresh, brief, decision="extend")
            fresh.pop("chief_review_tries", None)
            save_item(fresh)
            moved = True
        elif (outcome == "rescope" and reason and str(doc.get("ask") or "").strip()
              and _chief_brief_grounded(fresh, brief)
              and (not cap_held(fresh) or _chief_spending_step_allowed(fresh))):
            fresh["ask"] = str(doc["ask"]).strip()[:6000]
            fresh["first_action"] = brief[:1200]
            if cap_held(fresh):
                grant_spending_checkpoint(fresh, by="claude", reason=brief, via="automatic chief-of-staff review (Codex)")
                fresh.setdefault("cap_reviews", []).append(_cap_review_entry("claude", "rescope", *spending_checkpoint_state(fresh)[:2], spending_checkpoint_state(fresh)[1], reason))
            elif repair_held(fresh):
                grant_repair_checkpoint(fresh, by="claude", brief=brief, via="automatic chief-of-staff review (Codex)")
                fresh.setdefault("repair_reviews", []).append(_repair_review_entry("claude", "rescope", fresh, reason, brief))
            else:
                release_chief_hold_for_capability(fresh, brief, decision="rescope")
            fresh.pop("chief_review_tries", None)
            save_item(fresh)
            moved = True
        elif (outcome == "close" and reason and _repair_closable(fresh)
              and _chief_close_evidence(fresh, doc)):
            evidence = str(doc["evidence"]).strip()
            if cap_held(fresh):
                spent, caps, _ = spending_checkpoint_state(fresh)
                fresh.setdefault("cap_reviews", []).append(_cap_review_entry("claude", "close", spent, caps, caps, reason + " Evidence: " + evidence))
            if repair_held(fresh):
                fresh.setdefault("repair_reviews", []).append(_repair_review_entry("claude", "close", fresh, reason + " Evidence: " + evidence))
            fresh.setdefault("chief_reviews", []).append({"at": _now_iso(), "by": "claude",
                "decision": "close", "reason": reason[:800], "evidence": evidence[:800],
                "via": "automatic chief-of-staff review (Codex)"})
            forget_owner_memory(fresh)
            fresh["result"] = ((fresh.get("result") or "").rstrip() +
                "\n\nClosed by the chief of staff: " + reason[:800] + " Evidence: " + evidence[:800]).strip()
            fresh["state"] = "dropped"
            fresh["closed"] = _now_iso()
            fresh.pop("chief_review_tries", None)
            save_item(fresh)
            moved = True
        elif outcome == "taste" and all(str(doc.get(k) or "").strip()
                                          for k in ("reason", "question", "recommend", "why", "instead")):
            _file_taste_decision(fresh, doc)
            fresh.setdefault("chief_reviews", []).append({"at": _now_iso(), "by": "claude",
                                                            "decision": "taste", "reason": reason})
            fresh.pop("chief_review_tries", None)
            save_item(fresh)
            moved = True
        else:
            save_item(fresh)
        item.clear(); item.update(fresh)
    return moved


def release_chief_hold_for_capability(item, brief, decision="capability"):
    """Make a held capability card runnable through the ordinary drain lane.

    This only removes the queue hold that prevented an owner attempt. The
    ordinary review and landing checks still decide whether its candidate can
    reach main.
    """
    if cap_held(item):
        if not _chief_spending_step_allowed(item):
            raise ValueError("This card has reached its automatic spending extension limit.")
        grant_spending_checkpoint(item, by="claude", reason=brief,
                                  via="automatic chief-of-staff capability dispatch (Codex)")
        save_item(item)
    elif repair_held(item):
        grant_repair_checkpoint(item, by="claude", brief=brief,
                                via="automatic chief-of-staff capability dispatch (Codex)")
        save_item(item)
    else:
        flow = _workflow(item)
        open_blockers = [b for b in flow["blockers"] if b.get("state") == "open"]
        if any(b.get("type") not in ("art_budget", "chief_hold") for b in open_blockers):
            return item
        for blocker in flow["blockers"]:
            generic_chief_hold = (blocker.get("owner") == "claude" and blocker.get("wake")
                                  and not blocker.get("action_id"))
            if blocker.get("state") == "open" and (blocker.get("type") == "art_budget"
                                                     or generic_chief_hold):
                blocker["state"] = "resolved"
                blocker["resolved_at"] = _now_iso()
        item["state"] = "waiting_session"
        item["started"] = ""
        item.setdefault("chief_reviews", []).append({
            "at": _now_iso(), "by": "claude", "decision": decision,
            "reason": str(brief).strip()[:1200]})
        save_item(item)
    return item


def grant_spending_checkpoint(item, said="", by="daniel", reason="", via=""):
    """One bounded step past the card's spending limit, then back to the queue.

    `by` is whoever actually granted it, and the record says so: "daniel" for
    his yes on a checkpoint that reached his page before S-38, "claude" for the
    chief of staff's extension of a held card (`hq/card.py extend`, where `via`
    names the session that ran it). A card with no checkpoint record is
    extended where it stands. The fields a question borrowed are put back."""
    pending = item.pop("spending_checkpoint", None) or {}
    spent, caps, exceeded = spending_checkpoint_state(item)
    exceeded = exceeded or [k for k in pending.get("exceeded") or [] if k in CAP_FIELDS]
    new = raised_caps(spent, caps, exceeded)
    _apply_caps(item, new, exceeded)
    # Only a question that reached his page borrowed the card's recommendation.
    asked = bool(pending) and not pending.get("held_for")
    rec = (item.get("recommend") or {}) if asked else {}
    item["cap_reviews"] = item.get("cap_reviews") or []
    if by == "daniel":
        item["decided"] = {"question": rec.get("question", ""), "answer": rec.get("answer", ""),
                           "at": _now_iso()}
        entry = _cap_review_entry("daniel", "extend", spent, caps, new,
                                  "Daniel approved: " + str(rec.get("answer") or "keep going"))
    else:
        entry = _cap_review_entry(by, "extend", spent, caps, new, reason)
        if via:
            entry["via"] = str(via)[:160]
    item["cap_reviews"].append(entry)
    if asked:
        for key in ("recommend", "deliverable", "follow_ups"):
            item.pop(key, None)
        item.update(pending.get("restore") or {})
    if pending.get("repair_hold"):
        # The hold comes back with the card, and his yes is what lets it run
        # past it, as with grant_repair_checkpoint.
        item["repair_hold"] = pending["repair_hold"]
        item["supervised_retry"] = True
    notes = []
    if by == "daniel" and pending.get("move") == "rethink" and rec.get("answer"):
        notes.append("Daniel approved this at the spending checkpoint; do it before anything else:\n"
                     + str(rec["answer"]))
    if by == "daniel" and said:
        notes.append("Daniel attached this when he approved it:\n" + said)
    if by != "daniel" and str(reason or "").strip():
        notes.append("The chief of staff's brief for this step: " + str(reason).strip())
    if notes:
        item["ask"] = (item.get("ask", "").rstrip() + "\n\n" + "\n\n".join(notes))
    back = pending.get("return_state") or item.get("state")
    item["state"] = back if back in CAP_REVIEW_STATES else "waiting_session"
    item.pop("cap_review_tries", None)
    return item


# Attributions an extension may not borrow: nobody but Daniel grants as Daniel.
_BORROWED_ACTOR = re.compile(r"\b(daniel|ceo|checker)\b", re.I)


def extend_over_budget(item_id, *, by, reason):
    """The chief of staff's extension of a card at its spending checkpoint
    (`hq/card.py extend`, S-38): one bounded step exactly as the automatic review
    grants one, recorded as the chief of staff's with the brief, the brief added
    to the card's ask, the hold cleared and the card back in its queue lane.
    Raises ValueError, in plain words, when the card cannot be extended."""
    by, reason = _chief_of_staff_grant_args(
        by, reason, "what the owner should do with the extra spending")
    with mutation_lock():
        item = _load_open_card(item_id)
        _hold_legacy_checkpoint(item)
        if not cap_held(item):
            if item.get("spending_checkpoint") or item.get("repair_checkpoint"):
                raise ValueError(f"Work card {item_id} is waiting on another checkpoint, not its spending limit.")
            if item.get("state") not in CAP_REVIEW_STATES or landing_awaits_approval(item):
                raise ValueError(f"Work card {item_id} is not in the queue ({item.get('state')}), "
                                 "so there is no spending to extend.")
            if not spending_checkpoint_state(item)[2]:
                raise ValueError(f"Work card {item_id} is not over its spending limit.")
        grant_spending_checkpoint(item, by="claude", reason=reason, via=by)
        return save_item(item)


# ---------------------------------------------------------------------------
# The chief of staff's review of a card whose automatic repairs are used up.
#
# A card the reviewer failed again after its automatic repair holds on
# `repair_hold` until "an explicit supervised retry" (work_view). Nothing ever
# gave one: on 2026-09-28 six cards had sat that way for a day or more. Daniel
# approved (2026-09-28) the same shape as the spending checkpoint: the chief of
# staff reviews one card per background pass and gives it one more supervised
# try with a sharper brief, or closes work that is no longer needed. Each
# decision is recorded on the card under `repair_reviews`.
#
# S-38 (2026-09-29) applies here as it does to spending: whether to try again,
# rescope or close is engineering management, not taste, so where the automatic
# review stops the card is held in the queue for the chief of staff with the
# reason shown, and never goes to Daniel's page. Sent there, such a card was
# also kept off it, because its code had not been verified, and sat in no lane.
# `hq/card.py extend` (or its alias `retry`) grants the one more supervised try.
# ---------------------------------------------------------------------------

# Past this many of the chief of staff's own retries on one card, no model is
# asked: the card is held for the chief of staff.
REPAIR_AUTO_RETRIES = 2
REPAIR_REVIEW_TRIES = 3
REPAIR_REVIEW_STATES = CAP_REVIEW_STATES
REPAIR_SCAN_SECONDS = 120
_REPAIR_SCAN = {"at": 0.0}
REPAIR_HOLD_WAKE = ("The chief of staff gives it one more supervised try (python3 hq/card.py extend), "
                    "rescopes it, or closes it.")


def exhausted_repair(item):
    """The same test work_view makes: a repair hold after an automatic repair."""
    return bool(str(item.get("repair_hold") or "") and int(item.get("automatic_repairs") or 0) >= 1)


def _repair_attempt(item):
    return str(item.get("last_recorded_attempt") or (item.get("attempt_outcome") or {}).get("id") or "")


def _repair_reviewable(item):
    """Open, used up its repairs, and not already somebody else's to act on."""
    if item.get("state") not in REPAIR_REVIEW_STATES or item.get("state") in TERMINAL_STATES:
        return False
    if item.get("spending_checkpoint") or item.get("repair_checkpoint") or landing_awaits_approval(item):
        return False
    if not exhausted_repair(item) or item.get("supervised_retry"):
        return False
    # One supervised retry per failed attempt: a retry already granted for this
    # attempt is the drain's to run, not another review's to repeat.
    attempt = _repair_attempt(item)
    return not (attempt and any(r.get("decision") == "retry" and r.get("attempt_id") == attempt
                                for r in item.get("repair_reviews") or []))


def _repair_review_entry(by, decision, item, reason, brief=""):
    entry = {"at": _now_iso(), "by": by, "decision": decision,
             "attempt_id": _repair_attempt(item), "reason": str(reason or "").strip()[:800]}
    if brief:
        entry["brief"] = str(brief).strip()[:2000]
    return entry


def _repair_review_prompt(item, spent):
    history = [{"status": a.get("status"), "reason": str(a.get("reason") or "")[:400]}
               for a in (item.get("attempt_history") or [])[-4:]]
    checks = [{"verdict": c.get("verdict"), "summary": str(c.get("summary") or "")[:400],
               "findings": [str((f or {}).get("what") if isinstance(f, dict) else f)[:300]
                            for f in (c.get("findings") or [])[:4]]}
              for c in ((item.get("prior_checks") or []) + ([item["check"]] if item.get("check") else []))[-4:]]
    changed = [str(x) for x in (
        item.get("tier_raised") and f"Moved to a build worker with write access at {item['tier_raised'].get('at')}: {item.get('tier_reason')}",
        *[f"Earlier spending review ({r.get('by')}, {r.get('decision')}): {r.get('reason')}" for r in (item.get("cap_reviews") or [])[-2:]],
        *[f"Earlier repair review ({r.get('by')}, {r.get('decision')}): {r.get('reason')}" for r in (item.get("repair_reviews") or [])[-2:]],
    ) if x]
    ruling = (f"\nThis card carries out Daniel's ruling {item['ruling_id']}; it cannot be closed "
              "without him.") if item.get("ruling_id") else ""
    return f"""You are the chief of staff of Tiny Farm Studio. A work card's reviewer failed
it again after its automatic repair, so the studio stopped trying on its own. Nothing moves it
until you decide. Daniel's policy: his attention is only for taste and direction; anything the
owner can fix with a clearer instruction should go back to the owner.

WORK: {item.get('title', '')}
ASK: {str(item.get('ask') or '')[:1500]}
TIER: {item.get('tier')}{ruling}
ATTEMPTS: {spent['attempts']}
SPENT: {spent['tokens']:,} tokens, {spent['fresh']:,} of them fresh, ${spent['usd']:.2f} list price
WHY IT IS HELD: {str(item.get('repair_hold') or '')[:600]}
ATTEMPT HISTORY (oldest first): {json.dumps(history)}
REVIEWER CHECKS (oldest first): {json.dumps(checks)}
LATEST RESULT: {str(item.get('result') or '')[:3000]}
WHAT THE STUDIO CHANGED ABOUT THIS CARD: {json.dumps(changed) if changed else "nothing recorded"}

You may read the repository to see whether the work is already on main or superseded.
A failure the studio has since fixed (for example a card moved to a writable copy after
attempts that could only read) is not the owner failing.

Return JSON only, one of:
When the reviewer's remaining findings are concrete and the owner can fix them:
{{"outcome":"retry","brief":"a sharper instruction for the owner's next attempt that names each remaining finding concretely and what done looks like","reason":"why one more try should work"}}
When one more try as it stands would not settle it (the same failure repeating, so the
approach needs rethinking, or a missing decision), hold it: the card waits in the queue for
the chief of staff to give one more try with a new brief, rescope or close it. It never goes
to Daniel; if it truly needs his taste, say so in "suggest" and the chief of staff will put
the question to him on a decision card.
{{"outcome":"hold","reason":"what keeps failing","suggest":"what the rework should be, or why it should close"}}
When the work is no longer needed (superseded, or already done on main):
{{"outcome":"close","reason":"what makes it unnecessary, with the evidence you found"}}
"""


def _repair_tries(item):
    """How many repairs the card has had: the automatic ones, then each
    supervised try the chief of staff or Daniel gave it."""
    return int(item.get("automatic_repairs") or 0) + sum(
        1 for r in item.get("repair_reviews") or [] if r.get("decision") == "retry")


def _repair_hold_reason(item, why):
    """The sentence the queue shows beside a card held because its repairs are used up."""
    tries = _repair_tries(item)
    said = (f"Its repairs are used up after {tries} {'try' if tries == 1 else 'tries'}; waiting for "
            "the chief of staff to give one more try, rescope or close it.")
    why = str(why or "").strip().rstrip(".")
    return said + (f" {why[0].upper()}{why[1:]}." if why else "")


def repair_held(item):
    """True when the card waits on the chief of staff because its repairs are used up."""
    pending = item.get("repair_checkpoint")
    return isinstance(pending, dict) and pending.get("held_for") == "claude"


def _repair_hold(item, why, suggestion=""):
    """Hold the card in the queue for the chief of staff (S-38): the repair hold
    stays on the card, the reason is shown on the queue, and nothing goes to
    Daniel. The card keeps its queue state, so the lane check reads it as held."""
    state = item.get("state")
    item["repair_checkpoint"] = {
        "at": _now_iso(), "held_for": "claude",
        "return_state": state if state in REPAIR_REVIEW_STATES else "for_review",
        "attempt_id": _repair_attempt(item), "reason": _repair_hold_reason(item, why),
        **({"suggestion": str(suggestion).strip()[:800]} if str(suggestion or "").strip() else {}),
        "restore": {}, "repair_hold": None}
    item.setdefault("repair_reviews", []).append(_repair_review_entry("claude", "hold", item, why))
    item.pop("repair_review_tries", None)
    return save_item(item)


def hold_repair_checkpoints_for_chief_of_staff():
    """Move every card the old path sent to Daniel as a "give its owner one more
    attempt?" question into the held-for-the-chief-of-staff state (S-38).
    Idempotent: a held card carries `held_for`, so a second run finds nothing.
    Run by each drain and at HQ's start. Returns the ids moved."""
    moved = []
    for item in items():
        pending = item.get("repair_checkpoint")
        if not isinstance(pending, dict) or pending.get("held_for"):
            continue
        with mutation_lock():
            fresh = load_item(item["id"])
            if _hold_legacy_repair_checkpoint(fresh):
                save_item(fresh)
                moved.append(fresh["id"])
    return moved


def _hold_legacy_repair_checkpoint(item):
    """In memory: a repair checkpoint routed to Daniel becomes a hold for the
    chief of staff. The fields the question borrowed are put back as they were,
    and the repair hold it set aside returns to the card."""
    pending = item.get("repair_checkpoint")
    state = item.get("state")
    if not isinstance(pending, dict) or pending.get("held_for") or state in TERMINAL_STATES:
        return False
    if state != "needs_approval" and state not in REPAIR_REVIEW_STATES:
        return False
    for key in ("recommend", "deliverable", "follow_ups"):
        item.pop(key, None)
    item.update(pending.get("restore") or {})
    item["repair_hold"] = pending.get("repair_hold") or item.get("repair_hold") or \
        "The repair still needs verification; the owner must resolve the remaining findings."
    back = pending.get("return_state") if state == "needs_approval" else state
    item["state"] = back if back in REPAIR_REVIEW_STATES else "for_review"
    why = "it had been sent to Daniel before cards whose repairs are used up became the chief of staff's call"
    item["repair_checkpoint"] = {
        "at": _now_iso(), "held_for": "claude", "return_state": item["state"],
        "attempt_id": pending.get("attempt_id") or _repair_attempt(item),
        "moved_from": state, "asked_at": pending.get("at"),
        "reason": _repair_hold_reason(item, why), "restore": {}, "repair_hold": None}
    item.setdefault("repair_reviews", []).append(_repair_review_entry("claude", "hold", item, why))
    return True


def _repair_retry(item, brief, reason, by="claude"):
    """One supervised try on this attempt, carrying the sharper brief."""
    item["repair_brief"] = str(brief).strip()[:4000]
    item["supervised_retry"] = True
    item.setdefault("repair_reviews", []).append(_repair_review_entry(by, "retry", item, reason, brief))
    item.pop("repair_review_tries", None)
    return save_item(item)


def _repair_close(item, reason):
    """Close work that is no longer needed, the way /api/work/drop does."""
    forget_owner_memory(item)
    item.setdefault("repair_reviews", []).append(_repair_review_entry("claude", "close", item, reason))
    item["result"] = ((item.get("result") or "").rstrip() + "\n\nClosed by the chief of staff after "
                      "its repairs were used up: " + str(reason).strip()[:800]).strip()
    item["state"] = "dropped"
    item["closed"] = _now_iso()
    item.pop("repair_review_tries", None)
    return save_item(item)


def _repair_closable(item):
    """A ruling's integration or tier-2 work is never closed without Daniel."""
    return not item.get("ruling_id") and int(item.get("tier") or 0) != 2


def review_exhausted_repair(item, org):
    """The chief of staff's review of one card whose automatic repairs are used up."""
    if not execution.launch_allowed() or not _repair_reviewable(item):
        return False
    retries = sum(1 for r in item.get("repair_reviews") or []
                  if r.get("by") == "claude" and r.get("decision") == "retry")
    # Hard limit: decided here, with no model call.
    if retries >= REPAIR_AUTO_RETRIES:
        _repair_hold(item, f"the automatic repair review has already given it {retries} more tries "
                           "without it passing")
        return True
    attempt = _repair_attempt(item)
    spent, _caps, _exceeded = spending_checkpoint_state(item)
    item["repair_review_tries"] = int(item.get("repair_review_tries") or 0) + 1
    save_item(item)
    text, limited = _run_cli(_repair_review_prompt(item, spent),
                             HOST.build_system_prompt(org, "claude"), "Read,Glob,Grep", 8, 300,
                             model=HOST.seat_model(org, "claude"), phase="repair-review",
                             seat="claude", item=item["id"])
    doc = None if limited else _json_reply(text)
    doc = doc if isinstance(doc, dict) else {}
    reason = str(doc.get("reason") or "").strip()
    brief = str(doc.get("brief") or "").strip()
    with mutation_lock():
        # The call took minutes; decide on the card as it is now.
        fresh = load_item(item["id"])
        if not _repair_reviewable(fresh) or _repair_attempt(fresh) != attempt:
            item.clear(); item.update(fresh)
            return False
        if limited:
            # The allowance ran dry mid-review: nothing was judged, so the try is
            # given back. An empty window must never hold a card for a person.
            fresh["repair_review_tries"] = max(0, int(fresh.get("repair_review_tries") or 1) - 1)
            save_item(fresh)
            item.clear(); item.update(fresh)
            return False
        outcome = doc.get("outcome")
        if outcome == "retry" and brief and reason:
            _repair_retry(fresh, brief, reason)
        elif outcome in ("hold", "daniel") and reason:
            # "daniel" is the answer the old prompt asked for; it is read as a
            # hold too, since nothing whose repairs are used up goes to him (S-38).
            rec = doc.get("recommend") if isinstance(doc.get("recommend"), dict) else {}
            _repair_hold(fresh, "the automatic repair review found one more try as it stands "
                                "would not settle it: " + reason,
                         doc.get("suggest") or rec.get("answer") or "")
        elif outcome == "close" and reason and _repair_closable(fresh):
            _repair_close(fresh, reason)
        elif outcome == "close" and reason:
            # A ruling's work or tier-2 work closes only with Daniel's yes; the
            # chief of staff decides whether that question is worth his time.
            why = ("it carries out one of Daniel's rulings" if fresh.get("ruling_id")
                   else "it is work that needs Daniel's approval")
            _repair_hold(fresh, f"the automatic repair review thinks it may no longer be needed, but "
                                f"{why}, so it cannot close it on its own: " + reason,
                         "Check whether the work is already on main; if so, ask Daniel on a decision "
                         "card to close it, otherwise give it one more try.")
        elif int(fresh.get("repair_review_tries") or 0) < REPAIR_REVIEW_TRIES:
            item.clear(); item.update(fresh)
            return False              # tried again on a later pass
        else:
            _repair_hold(fresh, f"the automatic repair review gave no usable answer after "
                                f"{REPAIR_REVIEW_TRIES} tries")
        item.clear(); item.update(fresh)
    return True


def exhausted_repairs_due():
    """Cards held only because their repairs are used up, oldest first. The same
    projection the queue uses, so it names the cards the queue holds. A card
    also over its spending cap is the spending review's first."""
    import drain
    candidates = [i for i in items() if _repair_reviewable(i)]
    if not candidates:
        return []
    got = drain.sh(["git", "rev-parse", "main"], cwd=drain.REPO, timeout=10)
    head = got.stdout.strip() if got.returncode == 0 else ""
    active = drain.server.drain_state()
    due = []
    for item in candidates:
        if drain.item_capacity_reason(item):
            continue
        view = drain.project_work(item, head=head, active=active)
        action = view.get("next_action") or {}
        if (view.get("availability") != "running" and action.get("availability") == "waiting_event"
                and action.get("type") not in ("rebrief", "decide")):
            due.append(item)
    due.sort(key=lambda i: i.get("created_ts", 0))
    return due


def review_next_exhausted_repair(org):
    """One card per pass, and nothing while he has paused the studio or the
    model allowance is dry."""
    if not execution.launch_allowed() or HOST.limited_until():
        return False
    due = exhausted_repairs_due()
    return review_exhausted_repair(due[0], org) if due else False


def grant_repair_checkpoint(item, said="", by="daniel", brief="", via=""):
    """One more supervised try for a card whose repairs are used up, then back
    to its place in the queue.

    `by` is whoever actually granted it, and the record says so: "daniel" for
    his yes on a question that reached his page before S-38 covered repairs
    (his recommended answer and comment become the owner's instruction),
    "claude" for the chief of staff's try on a held card (`hq/card.py extend`
    or `retry`, where `brief` is the instruction and `via` names the session
    that ran it). The fields a question borrowed are put back."""
    pending = item.pop("repair_checkpoint", None) or {}
    # Only a question that reached his page borrowed the card's recommendation.
    asked = bool(pending) and not pending.get("held_for")
    rec = (item.get("recommend") or {}) if asked else {}
    if asked:
        for key in ("recommend", "deliverable", "follow_ups"):
            item.pop(key, None)
        item.update(pending.get("restore") or {})
    item["repair_hold"] = pending.get("repair_hold") or item.get("repair_hold") or \
        "The repair still needs verification; the owner must resolve the remaining findings."
    if by == "daniel":
        item["decided"] = {"question": rec.get("question", ""), "answer": rec.get("answer", ""),
                           "at": _now_iso()}
        notes = []
        if rec.get("answer"):
            notes.append("Daniel approved this after the repairs were used up; do it before anything else:\n"
                         + str(rec["answer"]))
        if said:
            notes.append("Daniel attached this when he approved it:\n" + said)
        text = "\n\n".join(notes) or "Daniel approved one more supervised try."
        entry = _repair_review_entry("daniel", "retry", item,
                                     "Daniel approved: " + str(rec.get("answer") or "one more try"), text)
    else:
        text = ("The chief of staff approved one more supervised try; do this before anything else:\n"
                + str(brief).strip())
        entry = _repair_review_entry(by, "retry", item, str(brief).strip(), text)
        if via:
            entry["via"] = str(via)[:160]
    back = pending.get("return_state") or item.get("state")
    item["state"] = back if back in REPAIR_REVIEW_STATES else "for_review"
    item["repair_brief"] = text
    item["supervised_retry"] = True
    item.setdefault("repair_reviews", []).append(entry)
    item.pop("repair_review_tries", None)
    return item


def _chief_of_staff_grant_args(by, reason, what):
    """The checks every chief-of-staff grant makes on who and why, in plain words."""
    by = " ".join(str(by or "").split())[:160]
    reason = str(reason or "").strip()[:2000]
    if len(by) < 3:
        raise ValueError("Say who is granting it, for example 'Claude chief-of-staff session'.")
    if _BORROWED_ACTOR.search(by):
        raise ValueError("The attribution names the session that ran the command; it may not "
                         "claim Daniel or a checker, because the chief of staff made this call.")
    if len(reason) < 10:
        raise ValueError(f"Give the brief for this step: {what}.")
    return by, reason


def _load_open_card(item_id):
    try:
        item = load_item(item_id)
    except (OSError, ValueError):
        raise ValueError(f"There is no work card {item_id}.")
    if item.get("state") in TERMINAL_STATES:
        raise ValueError(f"Work card {item_id} is already {item['state']}.")
    return item


def _at_repair_checkpoint(item):
    """Held for the chief of staff after its repairs were used up, or used up
    with no supervised try waiting (the automatic review has not reached it)."""
    if repair_held(item):
        return True
    return (not item.get("repair_checkpoint") and item.get("state") in REPAIR_REVIEW_STATES
            and exhausted_repair(item) and not item.get("supervised_retry")
            and not landing_awaits_approval(item))


def retry_repairs_used_up(item_id, *, by, reason):
    """The chief of staff's one more supervised try on a card whose repairs are
    used up (`hq/card.py retry`, or `extend` on such a card; S-38): recorded as
    the chief of staff's with the brief, the brief made the owner's repair
    instruction, the hold cleared and the card back in its queue lane. Raises
    ValueError, in plain words, when the card cannot be retried."""
    by, reason = _chief_of_staff_grant_args(
        by, reason, "what the owner must do on the next try, before anything else")
    with mutation_lock():
        item = _load_open_card(item_id)
        _hold_legacy_repair_checkpoint(item)
        _hold_legacy_checkpoint(item)
        if cap_held(item) or item.get("spending_checkpoint"):
            raise ValueError(f"Work card {item_id} is waiting at its spending limit first; "
                             "extend that before giving it another try.")
        if not _at_repair_checkpoint(item):
            why = ("already has a supervised try waiting to run" if item.get("supervised_retry")
                   else "has not used up its repairs")
            raise ValueError(f"Work card {item_id} is not at a repair checkpoint: it {why}.")
        grant_repair_checkpoint(item, by="claude", brief=reason, via=by)
        return save_item(item)


def keep_going(item_id, *, by, reason):
    """`hq/card.py extend`: the chief of staff's "keep going" on a card held for
    them, whichever checkpoint holds it. A spending limit is settled first,
    since any try would spend; otherwise a card whose repairs are used up gets
    one more supervised try. Returns (what was granted, the saved card)."""
    with mutation_lock():
        item = _load_open_card(item_id)
        _hold_legacy_checkpoint(item)
        _hold_legacy_repair_checkpoint(item)
        spending = cap_held(item) or not (
            repair_held(item) or (_at_repair_checkpoint(item) and not spending_checkpoint_state(item)[2]))
        if spending:
            return "spending", extend_over_budget(item_id, by=by, reason=reason)
        return "repair", retry_repairs_used_up(item_id, by=by, reason=reason)


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
            cards = {i["id"]: i for i in items()}
            todo = [i for i in cards.values() if i.get("state") == "doing" and not i.get("started")
                    and not any(prerequisites(i, cards))]
            todo.sort(key=lambda i: i.get("created_ts", 0))
            if todo:
                _process_item(todo[0], org)
                continue
            # A question waiting to be written is a piece of his queue that has
            # not arrived yet. Oldest first, and one that has already stopped
            # is left alone rather than rewritten forever.
            concerns = [i for i in items() if i.get("state") == "prepping"
                        and i.get("concern_review")]
            concerns.sort(key=lambda i: i.get("created_ts", 0))
            if concerns:
                resolve_review_concern(concerns[0], org)
                continue
            # A card stopped at its spending cap: the chief of staff extends it
            # one bounded step or holds it for a considered call (S-38). Looked
            # for every couple of minutes, not every tick, since it reads each
            # card's sessions.
            if time.time() - _CAP_SCAN["at"] >= CAP_SCAN_SECONDS:
                _CAP_SCAN["at"] = time.time()
                if review_next_spending_checkpoint(org):
                    continue
            # A card the reviewer failed again after its automatic repairs: the
            # chief of staff gives it one more supervised try, brings it to
            # Daniel, or closes it. Same cadence, one card per pass.
            if time.time() - _REPAIR_SCAN["at"] >= REPAIR_SCAN_SECONDS:
                _REPAIR_SCAN["at"] = time.time()
                if review_next_exhausted_repair(org):
                    continue
            unprepped = [i for i in items() if i.get("state") == "prepping"
                         and not i.get("prep_stalled") and not i.get("concern_review")]
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
            # The company outlives any one bad item, but not silently: a swallowed
            # conflict here hid a card rerunning every minute (2026-10-07).
            import sys, traceback
            print("HQ worker: " + traceback.format_exc(), file=sys.stderr, flush=True)
            continue


def start():
    # Cards an earlier HQ sent to Daniel as a "keep spending?" or "one more
    # attempt?" question are the chief of staff's now (S-38); the drain does the
    # same at each start.
    for migrate in (hold_checkpoints_for_chief_of_staff, hold_repair_checkpoints_for_chief_of_staff):
        try:
            migrate()
        except Exception:
            pass
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
    there is nothing in the tree for Daniel to approve. A spending or repair
    checkpoint asks him about the card, not the tree, so it is never held back."""
    if (item.get("spending_checkpoint") or item.get("repair_checkpoint")) \
            and item.get("state") == "needs_approval":
        return False
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
    mark_ruling_integrated(item, item["completion"].get("sha") or sha)
    return item


def mark_ruling_integrated(item, sha):
    """A ruling's own card landing is what integrates the ruling.

    It used to happen only when a session closed the card by hand, and the card
    told its worker to do that; a worker in a sandbox cannot reach HQ, and a
    card closes only after its work is on main, so on 2026-09-27 three ruling
    cards failed review for a step they could never take."""
    ruling_id = item.get("ruling_id")
    if not ruling_id:
        return
    path = os.path.join(HOST.DATA, "rulings", f"{ruling_id}.json")
    try:
        with open(path, encoding="utf-8") as fh:
            ruling = json.load(fh)
    except (OSError, ValueError):
        return
    if ruling.get("status") == "integrated":
        return
    ruling["status"] = "integrated"
    ruling["integrated"] = {"at": _now_iso(), "work_id": item["id"], "sha": sha}
    _write_json(path, ruling)


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


def undo_landing(item, *, actor="daniel", run_id=None):
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
    if actor == "ci" and (parent != sha or
            (item.get("completion") or {}).get("sha") != sha):
        return False, "Main or the work card moved since the failed CI commit."
    marker = "HQ-Undo: " + item["id"] + ":" + sha
    checkout = os.path.join(drain.WORKTREES, "integration-undo-" + item["id"])
    item["pending_undo"] = {"version": 1, "reverted": sha, "parent": parent,
                            "checkout": checkout, "marker": marker,
                            "at": _now_iso(), "actor": actor, "run_id": run_id}
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
                              "commit": commit, "actor": tx.get("actor", "daniel"),
                              "run_id": tx.get("run_id")}
    if tx.get("actor") == "ci":
        for blocker in _workflow(item).get("blockers") or []:
            if blocker.get("type") == "ci_undo" and blocker.get("state") == "open":
                blocker["state"], blocker["resolved_at"] = "resolved", _now_iso()
    item.setdefault("conversation", []).append(
        {"role": tx.get("actor", "daniel"),
         "text": (f"CI run {tx['run_id']} failed; reverted this landing."
                  if tx.get("actor") == "ci" else "Undid this landing."),
         "at": _now_iso(), "with": "undo"})
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
    org = HOST.load_org() if hasattr(HOST, "load_org") else None
    for item in got:
        item["workflow_view"] = drain.project_work(item, head=head, active=active)
        brief = approval_brief(item, org)
        if brief:
            item["approval"] = brief
        # The lanes the health check counts (card_lanes), so the queue page
        # sorts a card by the same verdict instead of re-deriving it.
        item["lanes"] = card_lanes(item, item["workflow_view"])
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
            "work": "Identify the accountable owner and safe execution tier, name the requested work as a follow-up on this card, and report the route here. You cannot file cards yourself: HQ files each named follow-up as a linked card when this card closes.",
            "priority": "Read the current priorities, identify the accountable owner, name the priority edit as a follow-up at its proper execution tier, and report the route here. You cannot file cards yourself: HQ files each named follow-up as a linked card when this card closes.",
            "discussion": "Respond to Daniel's question here and name follow-up work only if the discussion calls for it; HQ files each named follow-up as a linked card when this card closes.",
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
        # Work that needs another card's work first names it here, and waits
        # for it in the queue instead of starting and reporting it missing.
        if payload.get("after"):
            after, why = clean_after(payload["after"])
            if why:
                return {"error": why}
            fields["after"] = after
        cap = {"to": fields["owner"], "message": fields["ask"], "id": "manual"}
        return _file_item(fields, cap, org)

    item_id = payload.get("id") or ""
    if not re.fullmatch(WORK_ID, item_id):
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
    if path == "/api/work/accept" and landing_awaits_approval(item):
        # His yes on a change held only for it is permission to merge that
        # exact patch, not a close: closing it would leave the change unmerged.
        # The drain merges it with no model call; landing files the follow-ups.
        outcome = item.get("attempt_outcome") or {}
        item["landing_approved"] = {"patch_id": outcome.get("patch_id"),
                                    "stable_patch_id": _stable_patch_id_of(item["id"], outcome.get("patch_id")),
                                    "attempt_id": outcome.get("id"), "at": _now_iso()}
    elif path in ("/api/work/accept", "/api/work/approve") and item.get("state") == "needs_approval" \
            and item.get("spending_checkpoint"):
        # His yes at a spending checkpoint grants one bounded step and puts the
        # card back where it was; it does not close it.
        grant_spending_checkpoint(item, said)
    elif path in ("/api/work/accept", "/api/work/approve") and item.get("state") == "needs_approval" \
            and item.get("repair_checkpoint"):
        # His yes when the repairs are used up is one more supervised try, not
        # a close; the card goes back where it was with his answer as the brief.
        grant_repair_checkpoint(item, said)
    elif path == "/api/work/accept":
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
        "landing_undone", "landing_approved"}
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
        manifest = _host_cfg("completion_reconciliation.json")
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
        manifest = _host_cfg("process_completion_reconciliation.json")
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

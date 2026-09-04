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
import datetime
import json
import os
import re
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
}

LEVELS = ("task", "story", "epic", "project", "goal")

# What a state means, in the order the Work page shows them.
STATES = ("needs_approval", "for_review", "doing", "waiting_session", "accepted", "dropped")


def bind(server_module):
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


def _read_dir(d):
    out = []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return out
    for n in names:
        if not n.endswith(".json") or n.startswith("_"):
            continue
        try:
            out.append(HOST.load_json(os.path.join(d, n)))
        except Exception:
            continue
    return out


def policy():
    try:
        return HOST.load_json(POLICY_PATH)
    except Exception:
        return DEFAULT_POLICY


def items():
    got = _read_dir(WORK)
    got.sort(key=lambda i: i.get("created_ts", 0), reverse=True)
    return got


def _item_path(item_id):
    return os.path.join(WORK, f"{item_id}.json")


def save_item(item):
    return _write_json(_item_path(item["id"]), item)


def _sanitize():
    """A restart mid-run leaves an item claiming to be in progress. Say the true
    thing instead: it never finished, and it is due to run again."""
    for it in items():
        if it.get("state") == "doing" and it.get("started"):
            it["state"] = "doing"
            it["started"] = ""     # the worker picks it up again
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
    return datetime.datetime.now().isoformat(timespec="minutes")


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

Pick the owner from this roster by id — the person whose job it actually is:
{_roster_line(org)}

Reply with raw JSON and nothing else (no prose, no code fence):
{{"items": [{{"title": "short and plain", "level": "task|story|epic|project|goal", "owner": "<roster id>", "ask": "one sentence in Daniel's own terms", "first_action": "the single next concrete step, specific enough to just do", "tier": 0, "tier_reason": "why that tier"}}]}}

TITLES: Daniel reads the queue title-first, so a title is read with nothing around it to settle what it means: no ticket IDs, and no verb that could mean its own opposite. "Hold the foley session" was read as both delay it and run it. Prefer the longer unambiguous verb — "Take the foley session off the schedule". The ask and first_action below are read by the agent that does the work, so write those for efficiency.

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


def _clean_follow(raw, org, fallback_owner):
    if not isinstance(raw, dict):
        return None
    title = str(raw.get("title") or "").strip()
    if not title:
        return None
    try:
        tier = int(raw.get("tier", 2))
    except Exception:
        tier = 2
    level = str(raw.get("level") or "task").lower()
    owner = str(raw.get("owner") or "").strip()
    if not any(e["id"] == owner for e in org["employees"]):
        owner = fallback_owner
    return {
        "title": title[:160],
        "owner": owner,
        "level": level if level in LEVELS else "task",
        "tier": tier if tier in (0, 1, 2) else 2,
        "first_action": str(raw.get("first_action") or "")[:600],
        "why": str(raw.get("why") or "")[:300],
    }


def _parse_follows(tail, org, fallback_owner):
    """(everything accepting would file, an amendment to this item or None, the
    recommendation his yes takes or None).

    One result can imply several pieces of work — a reply naming a fix for the
    tool, a sweep for the artist and a pipeline check for the engineer is three
    items, and filing only the first would quietly drop two. Four is the cap:
    past that it is a plan, and a plan is its own item."""
    txt = (tail or "").strip()
    if not txt or txt.upper().startswith("NONE"):
        return [], None, None
    if txt.startswith("```"):
        txt = re.sub(r"^```[a-z]*\n?|```$", "", txt).strip()
    start, end = txt.find("{"), txt.rfind("}")
    if start < 0 or end <= start:
        return [], None, None
    try:
        doc = json.loads(txt[start:end + 1])
    except Exception:
        return [], None, None
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
    return [g for g in got if g], (amend or None), rec


def _split_result(text, org, fallback_owner):
    """(the deliverable he reads, what accepting it would file or None if the
    reply never said, any amendment to the item itself, the recommendation his
    yes takes). The block is stripped from the result — it is machinery for the
    card, not part of the work."""
    raw = text or ""
    if FOLLOW_MARK not in raw:
        return raw.strip(), None, None, None
    body, _, tail = raw.partition(FOLLOW_MARK)
    got, amend, rec = _parse_follows(tail, org, fallback_owner)
    return body.strip(), got, amend, rec


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


def _file_item(fields, cap, org):
    owner = fields["owner"]
    if not any(e["id"] == owner for e in org["employees"]):
        owner = cap["to"]
    tier = fields["tier"]
    state = {0: "doing", 1: "waiting_session", 2: "needs_approval"}[tier]
    return save_item({
        "id": "w" + uuid.uuid4().hex[:11],
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


def _follows_spec(org, amendable=False):
    pol = policy()
    t0, t1, t2 = (pol["tiers"][k]["means"] for k in ("0", "1", "2"))
    amend = AMEND_NOTE if amendable else ""
    amend_field = (',\n "amend": {"title": ..., "ask": ..., "first_action": ...}'
                   if amendable else "")
    return f"""End your reply with this line exactly:

{FOLLOW_MARK}

and on the next line either the single word NONE — if nothing more should
happen — or raw JSON, no fence and no prose, naming every piece of work his
acceptance should start. One result often implies several: a fix to a tool, a
sweep for the artist and a check in the pipeline are three items with three
owners, and naming only the first quietly drops the other two. Four at most —
past that it is a plan, and a plan is its own item.
{amend}
{{"items": [{{"title": "short and plain", "owner": "<roster id>", "level": "task|story|epic|project|goal", "tier": 0|1|2, "first_action": "the single next concrete step, specific enough to just do", "why": "one sentence: why this follows"}}]{amend_field}}}

TITLES: Daniel reads the queue title-first, so a title is read with nothing around it to settle what it means: no ticket IDs, and no verb that could mean its own opposite. "Hold the foley session" was read as both delay it and run it. Prefer the longer unambiguous verb — "Take the foley session off the schedule". The ask and first_action below are read by the agent that does the work, so write those for efficiency.

Tier each by how bad it is to get wrong with nobody reviewing it first:
0 — {t0}
1 — {t1}
2 — {t2}
Unknown blast radius is a 2, never a 0. Each item goes to the person whose job
it actually is, by id, from this roster:
{_roster_line(org)}

NONE is the honest answer more often than not, and inventing work to look busy
costs him the attention this system exists to protect. But a gap you noticed
and did not file is a gap he has to remember for you — name it.

{RECOMMEND_NOTE}"""


# ---------------------------------------------------------------------------
# doing the tier-0 work
# ---------------------------------------------------------------------------

def _do_prompt(item, org):
    emp = next((e for e in org["employees"] if e["id"] == item["owner"]), None)
    name = emp["name"] if emp else "you"
    spec = _follows_spec(org)
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
{said}


Then say what your result implies, because Daniel decides whether to accept
it and he is entitled to know what his yes starts before he gives it.

{spec}"""


def _run_cli(prompt, sys_prompt, tools, turns, timeout, model="", phase="", seat="", item=""):
    """One CLI call, with the intake queue's token-limit accounting. Returns
    (text, limited); the call's cost is appended to the token ledger, because
    work the company does on its own spends the same allotment Daniel does and
    nothing used to say how much."""
    import subprocess
    cmd = ["claude", "-p", prompt, "--append-system-prompt", sys_prompt,
           "--allowedTools", tools, "--max-turns", str(turns),
           "--output-format", "json"]
    if model:
        cmd += ["--model", model]
    try:
        with HOST.CHAT_LOCK:
            proc = subprocess.run(
                cmd, cwd=HOST.REPO, capture_output=True, text=True, timeout=timeout,
                env={**os.environ, "CLAUDE_CODE_DISABLE_AUTOUPDATE": "1"})
    except Exception as e:
        return f"[{type(e).__name__}] {e}"[:300], False
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")
    if proc.returncode != 0:
        if HOST._looks_like_limit(out):
            HOST.note_limit(out)
            return "", True
        return HOST.cli_failure(proc), False
    HOST.clear_limit()
    text, usage = _read_cli_json(proc.stdout)
    HOST.record_model_usage(phase or "work", seat, model, usage, item)
    return text, False


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
    item["started"] = _now_iso()
    item["attempts"] = item.get("attempts", 0) + 1
    save_item(item)
    sys_prompt = HOST.build_system_prompt(org, item["owner"])
    model = item.get("model") or HOST.seat_model(org, item["owner"])
    text, limited = _run_cli(_do_prompt(item, org), sys_prompt, "Read,Glob,Grep",
                             HOST.MAX_TURNS, 420, model=model,
                             phase="tier0", seat=item["owner"], item=item["id"])
    if limited:
        item["started"] = ""
        save_item(item)
        return False
    body, got, _amend, rec = _split_result(text, org, item["owner"])
    item["result"] = body or "(no result came back)"
    if got is not None:
        item.pop("follow_up", None)
        item["follow_ups"] = got
        item["recommend"] = rec or {}
    item["state"] = "for_review"
    item["finished"] = _now_iso()
    save_item(item)
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


def _response_prompt(item, org):
    result = (item.get("result") or "").strip()
    spec = _follows_spec(org, amendable=True)
    return f"""Daniel is looking at this piece of work on HQ's Work page and has
written back to you about it. Answer him on the card, in your own voice.

WORK ITEM: {item['title']}
WHAT HE ASKED FOR: {item.get('ask', '')}
THE STEP THAT WAS YOURS TO TAKE: {item.get('first_action', '')}
{("THE RESULT YOU GAVE HIM:" + chr(10) + result[:6000]) if result else "This has not been done yet."}

THE CONVERSATION ON THIS CARD SO FAR:
{_convo_lines(item, org)}

Reply to his last message and nothing else. Plain language, short as the answer
allows, no preamble and no ticket IDs. The repository is read-only to you and is
the source of truth — check it rather than guessing.

If he is asking for something that can be settled by reading, drafting or
analysing, do it here and give him the answer: the studio norm is that you do
reversible work now rather than promising it. If what he wants changes files,
say plainly what you would change and leave it — a build session carries that
out. If he has told you the result was wrong, say what you now think is right,
briefly, without apologising at length.

A gap you name in prose is a gap he has to remember for you — so anything your
answer commits to belongs in the block below, where his acceptance files it.

{spec}"""


def _process_response(item, org):
    """He asked something on a card; the owner answers on the card. Runs on the
    worker so the page never blocks on a model call."""
    raw, limited = _run_cli(_response_prompt(item, org),
                            HOST.build_system_prompt(org, item["owner"]),
                            "Read,Glob,Grep", HOST.MAX_TURNS, 300,
                            model=item.get("model") or HOST.seat_model(org, item["owner"]),
                            phase="reply", seat=item["owner"], item=item["id"])
    if limited:
        return False
    text, got, amend, rec = _split_result(raw, org, item["owner"])
    # Re-read: he may have typed again while the owner was thinking, and his
    # message must not be lost to a stale copy of the item.
    fresh = HOST.load_json(_item_path(item["id"]))
    convo = fresh.get("conversation", [])
    convo.append({"role": item["owner"], "text": text or "(no reply came back)",
                  "at": _now_iso()})
    fresh["conversation"] = convo
    fresh["awaiting_reply"] = False
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
    # What he was told may have changed what should follow, so the card never
    # keeps showing a consequence worked out before the conversation.
    fresh.pop("follow_up", None)
    fresh["follow_ups"] = got or []
    fresh["recommend"] = rec or {}
    save_item(fresh)
    last_from_him = next((m["text"] for m in reversed(convo)
                          if m.get("role") == "daniel"), "")
    capture_exchange(fresh.get("thread") or fresh["owner"], last_from_him, text or "",
                     origin=fresh["id"])
    return True


def _propose_follow_up(item, org):
    """Backfill for results that landed before the card showed consequences.
    New work answers this inside the call that does it and never reaches here."""
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
    body, got, _amend, rec = _split_result(text, org, item["owner"])
    if got is None:
        # No marker came back; the whole reply is the block.
        got, _amend, rec = _parse_follows(text, org, item["owner"])
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
            if HOST.limited_until():
                continue
            org = HOST.load_org()
            waiting = [i for i in items() if i.get("awaiting_reply")]
            if waiting:
                waiting.sort(key=lambda i: i.get("asked_ts", 0))
                _process_response(waiting[0], org)
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
            # No card should sit in front of him with its consequence unknown.
            blind = [i for i in items()
                     if i.get("state") == "for_review" and not _asked_what_follows(i)]
            if blind:
                _propose_follow_up(blind[0], org)
        except Exception:
            continue      # the company outlives any one bad item


def start():
    threading.Thread(target=worker, daemon=True).start()


# ---------------------------------------------------------------------------
# API — server.py routes /api/work* straight here
# ---------------------------------------------------------------------------

def snapshot():
    got = items()
    return {
        "policy": policy(),
        "items": got,
        "capturing": len(_read_dir(CAPTURES)),
        "waiting_on_you": sum(1 for i in got if i["state"] in ("needs_approval", "for_review")),
        "in_progress": sum(1 for i in got if i["state"] == "doing"),
        "queued": sum(1 for i in got if i["state"] == "waiting_session"),
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
    item = HOST.load_json(p)
    if path == "/api/work/respond":
        # Writing back to a card is a conversation, not a verdict: it changes
        # no state and closes nothing. The owner answers on the card, and the
        # exchange is read for work exactly like a conversation on the chat
        # page — so what it commits to gets filed, and he never has to leave
        # the thing he was reading in order to say something about it.
        msg = (payload.get("message") or "").strip()[:4000]
        if not msg:
            return {"error": "empty message"}
        convo = item.get("conversation", [])
        convo.append({"role": "daniel", "text": msg, "at": _now_iso()})
        item["conversation"] = convo
        item["awaiting_reply"] = True
        item["asked_ts"] = time.time()
        return save_item(item)

    if path == "/api/work/accept":
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
        started = []
        for fu in follow_ups(item):
            org = HOST.load_org()
            cap = {"to": item.get("thread") or item["owner"], "id": "follow",
                   "message": f"Accepted “{item['title']}”. {fu.get('why', '')}".strip()}
            child = _file_item({
                "title": fu["title"],
                "level": fu.get("level", "task"),
                "owner": fu.get("owner") or item["owner"],
                "tier": fu.get("tier", 2),
                "tier_reason": fu.get("why", "follows from an accepted result"),
                "ask": cap["message"][:600],
                "first_action": fu.get("first_action", ""),
            }, cap, org)
            child["parent"] = item["id"]
            save_item(child)
            started.append({"id": child["id"], "title": child["title"],
                            "state": child["state"], "owner": child["owner"]})
        if started:
            item["spawned"] = started
    elif path == "/api/work/drop":
        item["state"] = "dropped"
        item["closed"] = _now_iso()
    elif path == "/api/work/approve":
        # His yes on a tier-2 item does not make it reversible; it makes it
        # allowed. A build session still carries it out.
        item["state"] = "waiting_session"
        item["approved"] = _now_iso()
    elif path == "/api/work/redo":
        # Back to whichever lane can actually carry it out. Tier 0 goes to the
        # read-only worker; anything that changes the repo goes back to the
        # build-session queue, because the tier-0 worker cannot write and would
        # simply hand back a description of the work a second time.
        item["state"] = "doing" if item.get("tier") == 0 else "waiting_session"
        item["started"] = ""
        item["result"] = ""
        # A second attempt is only a second attempt if it knows why the first
        # was sent back. The check that held it is kept and given to the worker
        # as part of the brief; the diff and the suite results are not, because
        # they described a change that no longer exists.
        prior = item.pop("check", None)
        if prior:
            item.setdefault("prior_checks", []).append(prior)
        item.pop("diff", None)
        item.pop("suites", None)
        item.pop("error", None)
    else:
        return {"error": "not found"}
    return save_item(item)

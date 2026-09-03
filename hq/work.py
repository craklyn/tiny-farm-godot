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

def capture_exchange(to_id, message, reply):
    """Called after a chat reply lands. Parks the exchange; the worker reads it.
    Deliberately does no model work inline — chat must never get slower because
    the company is taking notes."""
    if not message or not reply:
        return None
    cid = uuid.uuid4().hex[:12]
    return _write_json(os.path.join(CAPTURES, f"{cid}.json"), {
        "id": cid,
        "to": to_id,
        "message": message,
        "reply": reply,
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
{{"items": [{{"title": "short, plain, no ticket IDs", "level": "task|story|epic|project|goal", "owner": "<roster id>", "ask": "one sentence in Daniel's own terms", "first_action": "the single next concrete step, specific enough to just do", "tier": 0, "tier_reason": "why that tier"}}]}}

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


# ---------------------------------------------------------------------------
# doing the tier-0 work
# ---------------------------------------------------------------------------

def _do_prompt(item, org):
    emp = next((e for e in org["employees"] if e["id"] == item["owner"]), None)
    name = emp["name"] if emp else "you"
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
{name} saying so beats a plausible guess."""


def _run_cli(prompt, sys_prompt, tools, turns, timeout):
    """One CLI call, with the intake queue's token-limit accounting. Returns
    (text, limited)."""
    import subprocess
    cmd = ["claude", "-p", prompt, "--append-system-prompt", sys_prompt,
           "--allowedTools", tools, "--max-turns", str(turns)]
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
    return proc.stdout.strip(), False


# ---------------------------------------------------------------------------
# the worker
# ---------------------------------------------------------------------------

def _process_capture(cap, org):
    text, limited = _run_cli(_capture_prompt(org, cap),
                             "You file work items for a small game studio. You "
                             "answer with JSON only.", "", 1, 180)
    if limited:
        return False                      # tokens are dry; try again later
    for fields in _parse_items(text):
        _file_item(fields, cap, org)
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
    text, limited = _run_cli(_do_prompt(item, org), sys_prompt, "Read,Glob,Grep",
                             HOST.MAX_TURNS, 420)
    if limited:
        item["started"] = ""
        save_item(item)
        return False
    item["result"] = text or "(no result came back)"
    item["state"] = "for_review"
    item["finished"] = _now_iso()
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
            pending = sorted(_read_dir(CAPTURES), key=lambda c: c.get("created_ts", 0))
            if pending:
                _process_capture(pending[0], org)
                continue
            todo = [i for i in items() if i.get("state") == "doing" and not i.get("started")]
            todo.sort(key=lambda i: i.get("created_ts", 0))
            if todo:
                _process_item(todo[0], org)
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
    if path == "/api/work/accept":
        item["state"] = "accepted"
        item["closed"] = _now_iso()
    elif path == "/api/work/drop":
        item["state"] = "dropped"
        item["closed"] = _now_iso()
    elif path == "/api/work/approve":
        # His yes on a tier-2 item does not make it reversible; it makes it
        # allowed. A build session still carries it out.
        item["state"] = "waiting_session"
        item["approved"] = _now_iso()
    elif path == "/api/work/redo":
        item["state"] = "doing"
        item["started"] = ""
        item["result"] = ""
    else:
        return {"error": "not found"}
    return save_item(item)

"""Tiny Farm HQ — the drain: the studio working its own queue.

Tier 1 is "do it, show the diff". Until now the second half of that sentence had
no machinery behind it: a tier-1 item was filed, marked `waiting_session`, and
then waited for a human to notice. Twenty-two of them accumulated, which made a
pillar reporting "N things are ours to fix" a claim that work was in hand when
nothing was touching it. A queue nothing drains is a design problem wearing a
to-do list.

So this is the drain, and it is the same shape the pilot ran by hand on 2026-09-03:

    worker   the seat that owns the item, on that seat's default model from
             org.json, holding only its own context — its org record, its own
             notes, the card. Not the conversation that filed the work, and not
             this session. It works in a private git worktree, so several seats
             can be wrong at the same time without standing on each other.
    checker  the chief of staff, reading the diff against the brief. The pilot's
             most useful result came from here: a worker's overclaim and a card's
             false premise were both caught by the seat that files the work.
    apply    patches that survive the check land on the working tree, one at a
             time. A patch that no longer applies is recorded as needing another
             pass rather than forced.
    prove    both suites, once, if any applied patch touched the game.

Nothing is committed. The item goes back to `for_review` with the diff, the
check, the suites and the bill, and Daniel approves the result — which is the
studio's rule, not a limitation of this file.

One failure never reaches him as a result: a worker that used every turn it
was given and left edits behind. That is a budget this file set wrong, so the
item goes back into the queue (write_back) with its held patch as the next
attempt's base and twice the turns, at most AUTO_RESUMES times; only when the
drain has given up — the attempts are spent, or an attempt ran out having
changed nothing — does the card reach him, saying so.

    python3 hq/drain.py --list
    python3 hq/drain.py --dry-run
    python3 hq/drain.py --all --jobs 3
    python3 hq/drain.py w5a4005536e1 wc1886486f14
    python3 hq/drain.py --unattended      # what the timer runs; see hq/systemd/

Every model call is priced into hq/data/history/tokens.jsonl and totalled onto
the item, because unattended work spends the allotment Daniel spends and he is
entitled to see what a result cost before he accepts it.

Since 2026-09-11 the drain also runs on a timer (hq/systemd/tiny-farm-drain.*),
because a queue a human has to remember to run is the bottleneck this whole
file exists to remove: a revision Daniel asked for on a card sat behind
forty-three items until somebody typed the command. `--unattended` is the shape
the timer runs — a handful of items, two seats, and it does nothing at all when
the token window is dry or when the studio's own work has already spent most of
the last measured ceiling. Only one drain runs at a time; a manual run and the
timer take the same lock.
"""
import execution

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import server                      # noqa: E402  (path set above)
import work                        # noqa: E402

WORKTREES = os.path.expanduser("~/.cache/tiny-farm-drain")
PATCHES = os.path.join(REPO, "hq", "data", "patches")
# Every model session the drain runs is written here as it happens — one event
# per line, the CLI's own stream — with a small record beside it. That is what
# HQ's bullpen page (#/chat/bullpen) reads while a worker runs, and what a card's
# "How it was done" fold reads afterwards. Gitignored with the rest of runs/.
WORKERS = os.path.join(REPO, "hq", "data", "runs", "workers")
RUN_ID = ""


def _set_run(run_id):
    global RUN_ID
    RUN_ID = run_id
# A worker's turn budget. 60 is enough for most items; a sim item that has to
# write four tests on top of the code is not, and a worker cut off mid-edit
# costs a whole second attempt. DRAIN_TURNS=120 in the environment raises it for
# one run without editing this file.
WORKER_TURNS = int(os.environ.get("DRAIN_TURNS") or 60)
# A worker that used every turn and left edits behind is a budget the drain set
# wrong, not a result for Daniel to judge. Such an attempt is queued again from
# its held patch with twice the turns, at most this many times per card, and
# only ever to be picked up by a later run — so each retry faces the token
# window guard like any other item and its cost lands in the same ledger.
AUTO_RESUMES = 2
WORKER_TIMEOUT = 3600
CHECK_TIMEOUT = 900
# The checker's turns. Eight read a small diff; a 650-line sim change with four
# new tests ran the checker out of turns before it answered, and a check that
# does not come back is a diff nobody read.
CHECK_TURNS = 20
# Anything under these paths is the game rather than the office, so a patch that
# touches one has to face the suites before it is worth anybody reading.
GAME_PATHS = ("world/", "player/", "entities/", "systems/", "ui/", "effects/",
              "crops/", "tests/", "tools/", "assets/", "project.godot", "main.gd",
              "main.tscn")
# WebSearch is here because the studio's own sourcing rule needs it: free-to-use
# assets are searched for before anything is made by hand, and a worker that
# cannot search cannot do that job. Anything it brings back carries its source
# and its licence into CREDITS.md in the same change, or it does not come back.
WRITE_TOOLS = ("Read,Glob,Grep,Edit,Write,MultiEdit,NotebookEdit,Bash,TodoWrite,"
               "WebFetch,WebSearch")
# Tier 0 has nothing to walk back, so it gets nothing that could: the seat reads
# the repo and answers. The one executor runs both lanes, because two executors
# with different context is how a studio ends up with two answers.
READ_TOOLS = "Read,Glob,Grep"


def sh(args, cwd=REPO, timeout=120, check=False):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}\n{p.stdout}\n{p.stderr}"[:800])
    return p


# ---------------------------------------------------------------------------
# the seat, as the worker holds it
# ---------------------------------------------------------------------------

def seat_prompt(org, seat_id, thinking=False):
    """The seat's own context and nothing else. Deliberately not
    build_system_prompt: that one frames the persona as chatting with Daniel,
    and a worker that thinks it is chatting will describe the work instead of
    doing it."""
    emp = next((e for e in org["employees"] if e["id"] == seat_id), None)
    if emp is None:
        emp = next(e for e in org["employees"] if e["id"] == "claude")
    roster = "\n".join(
        f"- {e['name']} — {e['title']} ({e['level']}, {e['team']})"
        for e in org["employees"] if e["id"] != "daniel")
    text = f"""{server.GAME_CONTEXT}

You are {emp['name']}, {emp['title']} ({emp['level']}) on the {emp['team']} team.
Persona: {emp['persona']}
Your responsibilities: {'; '.join(emp['responsibilities'])}

You are not chatting with anybody. You are in a build session, working one item
the studio filed to you, on your own. You hold your seat's context only: you did
not see the conversation that created this item and must not assume what it said
beyond the brief you are given.

{"You are reading, not building. The repository is open to you and is the source of truth; you cannot change it, and you are not being asked to. What you produce is the answer itself — the verdict, the recommendation, the survey — written so that somebody can act on it without asking you a follow-up question." if thinking else "You have write access to a private copy of the repository — your own git worktree. Nothing you change here reaches main until the chief of staff has read your diff and the test suites have run, so make the change properly rather than hedging. Change only what this item asks for: a diff that also tidies three other things is a diff nobody can review."}

House rules that bind you:
- The design docs in docs/ are the source of truth for intent, and a change to a
  design is made in the same commit as the design doc that records it.
- Anything a human will read follows docs/WRITING.md. Written for a reader with
  no context: introduce a name before using it, state the fact rather than the
  observation about it, and never explain your own encoding on the surface.
- The load-bearing engine rules are in CLAUDE.md and docs/ARCHITECTURE.md — one
  action gateway, a pure simulation layer, all randomness through SimRng, and
  replays that still reproduce. Breaking one of those is worse than not doing
  the item.
- Do not commit, do not touch git history, and do not push. Leave your work in
  the working tree; the session applies it.
- Do not start servers or any long-running process. HQ is already running on
  this machine and the ports it uses are not yours to take — one worker started
  its own copy of the dashboard and knocked the real one off its port. Read the
  code, or run something that exits.
- If the item needs Daniel — his taste, a direction, a date, money, a
  credential, or anything a player would see — do not guess it. Stop and say
  exactly what you need and why only he can give it. That is a real result.

The rest of the roster, for naming the right owner of anything you find:
{roster}"""
    memory = server.load_staff_memory(emp["id"])
    if memory.strip():
        text += ("\n\nWHAT YOU REMEMBER from your own earlier work. These are your notes; "
                 "treat them as recollection to check against the repo, not as fact:\n"
                 + memory.strip())
    return text


def prior_checks(item):
    """Why earlier attempts were sent back. Without this a second attempt is a
    repeat, and the studio pays twice for the same mistake."""
    rows = item.get("prior_checks") or []
    if not rows:
        return ""
    out = []
    for i, c in enumerate(rows[-2:], 1):
        lines = [f"Attempt {i} was held: {c.get('summary', '')}"]
        for f in (c.get("findings") or [])[:6]:
            lines.append(f"  - {f.get('what', '')}"
                         + (f" ({f.get('where')})" if f.get("where") else "")
                         + (f" — fix: {f.get('fix')}" if f.get("fix") else ""))
        out.append("\n".join(lines))
    return ("\n\nWHY YOUR EARLIER ATTEMPT WAS SENT BACK — this is the brief now, as much "
            "as the item is. Do not hand back the same work:\n\n" + "\n\n".join(out) + "\n"
            "\nIf `git status` in your worktree shows uncommitted changes when you start, "
            "they are your earlier attempt's edits, applied for you so you continue from "
            "them rather than from main. Read them first; fix what was sent back; commit "
            "early and often.\n")


def resume_brief(item, continuing, turns):
    """What a worker is told when its earlier attempt ran out of turns and the
    drain is trying again on its own. `continuing` says whether that attempt's
    edits made it back into the worktree; when they did not, the worker starts
    from main and is told so rather than left to look for edits that are not
    there."""
    resume = item.get("resume") or {}
    if not resume:
        return ""
    why = resume.get("why") or "it used all of its turns"
    where = ("Its edits are already in your worktree, uncommitted — `git status` and "
             "`git diff` show them. Read them first, finish what the item asks for, "
             "and do not start over."
             if continuing else
             "Its edits could not be put back onto today's tree, so you are starting "
             "from main.")
    return (f"\n\nYOUR EARLIER ATTEMPT RAN OUT OF TURNS — {why}. This attempt has {turns} "
            f"turns, and there may not be another. {where} Commit early; reply with the "
            "whole result as it now stands.\n")


# The tail of an earlier attempt's own session, for the worker that picks the
# item up next. Forty lines is roughly the last stretch of what it was doing
# when it stopped — enough to continue from, short enough to be read rather
# than skimmed. The whole block is capped so a long session cannot crowd out
# the item itself.
RESUME_LINES = 40
RESUME_CHARS = 4000
RESUME_SAID = 2000
# One tool call per line; a line that runs past this is cut.
RESUME_LINE_CHARS = 200


def _session_streams(item_id):
    """Every worker session recorded for this item, newest first.

    The run happening now is skipped: the current session is writing its own
    file while this prompt is being built, and a worker handed its own opening
    lines back would be reading a mirror."""
    out = []
    try:
        runs = os.listdir(WORKERS)
    except OSError:
        return out
    for run in runs:
        if RUN_ID and run == RUN_ID:
            continue
        path = os.path.join(WORKERS, run, f"{item_id}-drain-work.jsonl")
        if os.path.isfile(path):
            out.append(path)
    out.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return out


# A worker reads and writes inside its own worktree, so every path it touched
# is recorded under that worktree's directory. The next attempt is somewhere
# else entirely, and a wall of absolute paths naming a directory that no longer
# exists is both noise and a trap.
_WORKTREE_PATH = re.compile(re.escape(WORKTREES) + r"/[^/\s]+/[^/\s]+/?")


def _trim(text, limit):
    """Shortened to fit, with the dead worktree paths taken out of it."""
    text = _WORKTREE_PATH.sub("", str(text or "").strip()).replace(REPO + "/", "")
    return text[:limit] + "…" if len(text) > limit else text


def _squeeze(text, limit):
    """The same, on one line — for the record's one-line-per-call part."""
    return _trim(" ".join(str(text or "").split()), limit)


def _stream_lines(path):
    """One session's events as the plain lines HQ shows: what it read, edited,
    ran and said. Tool output is dropped — the line above each result already
    names the call, and forty lines of file contents is not a record of what an
    attempt was doing. What failed is kept, because that is. So are the session's
    own bookkeeping lines, which say nothing about the item."""
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(ev, dict):
                    continue
                for c in server._compact_event(ev):
                    if c["kind"] in ("result", "note", "start"):
                        continue
                    rows.append(c)
    except OSError:
        return []
    return rows


def _stopped_because(path):
    """Why that session ended, from the record written beside its stream."""
    meta_path = path[:-len(".jsonl")] + ".json"
    try:
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, ValueError):
        return ""
    err = str((meta or {}).get("error") or "").strip()
    if err == "LIMITED":
        return "it was cut off at the account's usage ceiling"
    return err[:200]


def prior_session(item):
    """What the last attempt on this item actually did, in its own words.

    A retry already gets that attempt's files — the held patch is applied into
    its worktree — but not its reasoning, so it re-derives a plan the studio
    has already paid for once. Every session is written down as it runs, so the
    record exists; this is the part of it worth carrying forward.

    The newest stream is not always the one to read. An attempt refused at the
    usage ceiling writes a file two lines long, and eleven of those in a row
    would otherwise hide the thirteen-minute attempt underneath them, so the
    newest session that actually did something wins."""
    for path in _session_streams(item["id"])[:12]:
        rows = _stream_lines(path)
        doing = [r for r in rows if r["kind"] in ("said", "tool", "error")]
        if len(doing) < 3:
            continue
        said = ""
        for r in rows:
            if r["kind"] == "said":
                said = r["text"]
        why = _stopped_because(path)
        head = ("\n\nWHAT YOUR EARLIER ATTEMPT DID — this is that attempt's own record, "
                "written down as it worked, not a summary anybody wrote for you. "
                + (f"It stopped before it finished: {why}. " if why else "")
                + "Read it before you plan, and continue its work instead of starting "
                "the item again from the beginning.\n\nThe last things it read, changed, "
                "ran and said:\n\n")
        # A session that ends in a long reply must not eat the whole cap: what
        # it did and what it concluded are both wanted, so the last word is
        # trimmed to leave room for the lines under any circumstances.
        room = RESUME_CHARS - len(head) - 4 * RESUME_LINE_CHARS - 60
        said = _trim(said, max(400, min(RESUME_SAID, room)))
        tail = "\nThe last thing it said:\n\n" + (said or "(it said nothing)") + "\n"
        budget = RESUME_CHARS - len(head) - len(tail)
        picked = []
        for r in reversed(rows[-RESUME_LINES:]):
            text = _squeeze(r["text"], RESUME_LINE_CHARS)
            if r["kind"] == "said":
                text = "said: " + text
            if budget - (len(text) + 3) < 0:
                break
            budget -= len(text) + 3
            picked.append(text)
        if not picked:
            continue
        body = "\n".join("  " + t for t in reversed(picked))
        return head + body + "\n" + tail
    return ""


def task_prompt(item, org, resumed="", continuing=False, turns=WORKER_TURNS):
    convo = work._convo_lines(item, org)
    said = (f"\n\nWHAT DANIEL HAS SAID ABOUT THIS ON THE CARD — the most recent word on it, "
            f"and it overrides the brief wherever they disagree:\n\n{convo}\n") if convo else ""
    revising = work.revision_brief(item)
    if revising:
        revising += ("\nYour earlier changes are already in your worktree"
                     + (" — applied and committed as \"earlier attempt\", so `git diff` "
                        "shows only what you change now." if resumed else
                        ", because they are on main.")
                     + " Read them first and build on them. Do not undo what still stands.\n")
    return f"""WORK ITEM: {item['title']}

What Daniel asked for: {item.get('ask', '')}

The next step, which is yours to take now: {item.get('first_action', '')}
{said}{prior_checks(item)}{prior_session(item)}{revising}{resume_brief(item, continuing, turns)}
Do the work in your worktree. Then reply with the deliverable Daniel reads: what
you changed, what it now does, and anything you found that he should know.
Plain language, no preamble, no ticket IDs, as short as the work allows. Do not
paste the diff — he can see it.

If you could not finish it, say in one line what is blocking it and who has to
unblock it. A blocked item honestly reported beats a plausible guess, and if the
blocker is Daniel himself, name what you need from him.

{work._follows_spec(org)}"""


CHECK_SYSTEM = """You are Daniel's chief of staff at Tiny Farm Studio, checking work another
seat did on its own before it reaches him. You are the last reader between an
unattended agent and the CEO's attention.

Check three things and nothing else. First, does the diff do what the item asked
for — not something adjacent, not half of it? Second, does anything in it break a
house rule: the one action gateway, the pure simulation layer, randomness outside
SimRng, a design doc left contradicting the code, or writing aimed at a reader who
already knows the context? Third, does the reply overclaim — does it say something
the diff does not support, or measure something it did not measure? The pilot's
most valuable finding was exactly that: a worker's "fails in seconds" was true of
the wrong step.

Be specific and be brief. Findings are for the person who has to act on them.
You answer with raw JSON and nothing else."""


def check_prompt(item, result, diff, org=None):
    revising = ""
    if item.get("revising"):
        prior = (item.get("prior_results") or [{}])[-1].get("result") or ""
        convo = work._convo_lines(item, org) if org else ""
        revising = f"""
THIS IS A REVISION. Daniel read an earlier result and wrote back; the owner is
extending that result, and the diff below is only what changed this time — the
earlier changes are already in the tree. Check it against what he asked for in
the conversation, not only against the original brief.

WHAT HE SAID ON THE CARD:
{convo[:6000]}

THE EARLIER RESULT HE WAS READING:
{prior[:4000]}
"""
    return f"""THE ITEM: {item['title']}
What Daniel asked for: {item.get('ask', '')}
The step that was theirs to take: {item.get('first_action', '')}
Who did it: {item['owner']}
{revising}
WHAT THEY SAID THEY DID:
{(result or '(no reply came back)')[:8000]}

THE DIFF THEY PRODUCED:
{diff[:60000] if diff else '(no files changed)'}

Reply with raw JSON, no fence and no prose:
{{"verdict": "pass|concerns|fail",
 "summary": "one sentence Daniel can read: what landed, and what to watch",
 "findings": [{{"what": "the problem in one line", "where": "file or file:line", "fix": "what to do about it"}}],
 "escalates": null,
 "escalation_reason": null}}

"pass" means it did what was asked and you found nothing worth his time. "concerns"
means it is usable but you found something he or the owner should know. "fail"
means it should not land as it stands.

If — and only if — this genuinely needs Daniel himself, set "escalates" to one
sentence saying what you need from him and "escalation_reason" to whichever of
these it is: "authority" (only he can settle it: his taste, a direction, a
commitment, a date), "external_commitment" (we have told someone outside the
studio something that is not true, or owe them something), "exposure" (a player or
an outsider can be hit by this now), "age" (it is ours, but it has waited long
enough that the delay is itself the news). Approving a piece of work is NOT an
escalation — that is what the work queue is for. Leave both null unless one of
the four really applies."""


# ---------------------------------------------------------------------------
# one CLI call
# ---------------------------------------------------------------------------

def _session_paths(phase, item_id):
    """Where one session is written as it runs: the event stream and the record
    beside it, under hq/data/runs/workers/<run>/<item>-<phase>."""
    run = RUN_ID or (time.strftime("%Y%m%d-%H%M%S") + "-byhand")
    d = os.path.join(WORKERS, run)
    os.makedirs(d, exist_ok=True)
    stem = os.path.join(d, f"{item_id or 'none'}-{phase}")
    return stem + ".jsonl", stem + ".json"


def _last_assistant_text(lines):
    """What the model last said, from a stream that never produced a result
    event — the reply is kept even when the envelope is lost."""
    text = ""
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if not isinstance(ev, dict) or ev.get("type") != "assistant":
            continue
        for block in ((ev.get("message") or {}).get("content") or []):
            if isinstance(block, dict) and block.get("type") == "text" and block.get("text"):
                text = block["text"]
    return text.strip()


def run_cli(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id):
    """One model session, streamed to disk as it runs.

    Every event the CLI emits is appended to the session's file the moment it
    arrives, so a session can be watched while it runs and read back afterwards.
    The final `result` event carries the same fields the one-shot JSON envelope
    did, so what this returns is unchanged: (text, usage, error)."""
    context = _launch_context(item_id)
    adapter_phase = {"drain-work": "build-worker", "drain-check": "checker"}.get(phase, phase)
    if not execution.launch_allowed(launch_context=context, item=item_id, phase=adapter_phase):
        return "", None, "HELD"
    started = time.time()
    events_path, meta_path = _session_paths(phase, item_id)
    meta = {"item": item_id, "seat": seat, **execution.resolve_model(model),
            "phase": phase, "cwd": cwd, "turns": turns, "timeout": timeout,
            "run": RUN_ID, "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "started_ts": started, "pid": None, "finished": None, "usage": None}
    def save_meta():
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f)
    def on_start(pid):
        meta["pid"] = pid
        save_meta()
    def on_event(event):
        with open(events_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")
    save_meta()
    result = execution.run_session(prompt, system, tools, model, cwd, timeout, turns,
        phase=adapter_phase, seat=seat, item=item_id, on_event=on_event, on_start=on_start,
        launch_context=context)
    usage = result.get("usage")
    if usage:
        server.record_model_usage(phase, seat, result["model"], usage, item_id)
    err = "HELD" if result.get("held") else "LIMITED" if result.get("limited") else result.get("error", "")
    if not result.get("held") and not result.get("limited") and ran_out_of_turns(result):
        err = f"it used all {turns} of its turns"
    if result.get("limited"):
        server.note_limit(result.get("error", ""), provider=result["provider"])
    elif not err:
        server.clear_limit(provider=result["provider"])
    meta.update({key: result[key] for key in ("provider", "requested_model", "model")})
    meta.update({"usage": usage, "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
                 "exit": result.get("exit_code"), "error": err,
                 "stop_reason": result.get("stop_reason"), "subtype": result.get("subtype")})
    save_meta()
    return result.get("text", ""), usage, err

SUPERVISED_IDS = set()


def _launch_context(item_id):
    policy = execution.load_policy()
    if (policy["background_paused"] and item_id in SUPERVISED_IDS
            and item_id == policy["trial_item"]):
        return "supervised"
    return "automatic"


def ran_out_of_turns(err):
    """Whether run_cli's reason is the turn budget — the one failure that is
    the drain's own to fix."""
    if isinstance(err, dict):
        return (err.get("stop_reason") in ("max_turns", "tool_use")
                or err.get("subtype") == "error_max_turns"
                or ran_out_of_turns(err.get("error", "")))
    return (err in ("max_turns", "error_max_turns")
            or bool(re.match(r"it used all \d+ of its turns", err or "")))


def auto_resume_reason(item, rec):
    """Why this attempt goes back into the queue instead of to Daniel, or "".

    Three things have to hold: the worker ran out of turns, it changed files
    (an attempt that ran out having touched nothing would only run out again),
    and the card has not already had its share of attempts — `spent.attempts`
    counts every attempt the card has been paid for, this one included."""
    if rec.get("limited") or not ran_out_of_turns(rec.get("error")):
        return ""
    if not rec.get("files"):
        return ""
    attempts = int((item.get("spent") or {}).get("attempts") or 0) + 1
    if attempts > AUTO_RESUMES:
        return ""
    return rec["error"]


# ---------------------------------------------------------------------------
# worktrees
# ---------------------------------------------------------------------------

_WT_LOCK = __import__("threading").Lock()


def make_worktree(run_id, item_id):
    """Serialised: `git worktree add` writes .git/worktrees, and three seats
    starting at once would race for it."""
    path = os.path.join(WORKTREES, run_id, item_id)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with _WT_LOCK:
        sh(["git", "worktree", "add", "--detach", path, "HEAD"], check=True, timeout=600)
    return path


def drop_worktree(path):
    sh(["git", "worktree", "remove", "--force", path], timeout=120)
    shutil.rmtree(path, ignore_errors=True)


def worktree_patch(path):
    """Everything the worker changed, as one patch, including files it added
    and anything it already committed in its worktree.

    The diff is taken against the commit the worktree was cut from, not its
    HEAD: every brief tells a worker to commit early, and on 2026-09-21 a
    worker that had committed its work and then run out of turns was held with
    a patch holding only the one file it had not committed — the rest survived
    only as loose objects in git."""
    sh(["git", "add", "-A"], cwd=path, timeout=120)
    fork = sh(["git", "merge-base", "HEAD", "main"], cwd=path, timeout=60)
    base = [fork.stdout.strip()] if fork.returncode == 0 and fork.stdout.strip() else []
    p = sh(["git", "diff", "--cached", "--binary"] + base, cwd=path, timeout=120)
    stat = sh(["git", "diff", "--cached", "--stat"] + base, cwd=path, timeout=120).stdout.strip()
    files = [ln.split("\t")[-1] for ln in
             sh(["git", "diff", "--cached", "--name-only"] + base, cwd=path,
                timeout=120).stdout.splitlines() if ln.strip()]
    return p.stdout, stat, files


def save_patch(item_id, patch):
    """A held patch is kept on disk so it can be tried again when whatever was
    in its way has moved. Re-running the seat costs a model call; re-applying a
    patch costs nothing, and a drain that discards its own output makes the
    expensive half of the work the disposable half."""
    if not patch.strip():
        return ""
    os.makedirs(PATCHES, exist_ok=True)
    path = os.path.join(PATCHES, item_id + ".patch")
    with open(path, "w", encoding="utf-8") as f:
        f.write(patch)
    return path


def resume_held_patch(item, tree, thinking):
    """A second attempt starts from what the first one wrote, not from main.

    A worker that runs out of turns mid-edit leaves its diff in PATCHES (the
    check read it, and said what was missing). Throwing that away and paying
    for the same edits again is the one cost the retry brief cannot recover on
    its own, so the held patch is applied into the fresh worktree, uncommitted,
    and the brief tells the worker it is there. Only for held work: an applied
    patch is already on main. Returns the patch's stat line, or "" if nothing
    was resumed."""
    if thinking or (item.get("diff") or {}).get("applied"):
        return ""
    patch = load_patch(item["id"])
    if not patch.strip():
        return ""
    r = subprocess.run(["git", "apply", "--3way"], cwd=tree, input=patch,
                       capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        subprocess.run(["git", "checkout", "--", "."], cwd=tree, capture_output=True, timeout=120)
        subprocess.run(["git", "clean", "-fd"], cwd=tree, capture_output=True, timeout=120)
        return ""
    stat = subprocess.run(["git", "diff", "--stat"], cwd=tree, capture_output=True,
                          text=True, timeout=120).stdout.strip().splitlines()
    return stat[-1].strip() if stat else "applied"


def load_patch(item_id):
    try:
        with open(os.path.join(PATCHES, item_id + ".patch"), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _tree_dirty(tree):
    return bool(sh(["git", "status", "--porcelain"], cwd=tree, timeout=120).stdout.strip())


def resume_for_revision(item, tree, thinking):
    """A revision extends the earlier result, so the worktree has to start
    from it. Three cases, and the caller must know which it got:

      * the earlier patch landed and was then committed — it is in HEAD already;
      * the earlier patch landed but is uncommitted in the real tree — it is
        not in HEAD, so it is applied here (a patch that applies cleanly is
        proof it is not there yet; one that only applies in reverse is proof
        it is);
      * the earlier patch was held (never landed) — resume_held_patch has
        already put it in the tree.

    Whatever is in the tree after that is committed as "earlier attempt", so
    that the worker's own diff, and the patch the drain lands, cover only what
    changed this time. Returns (True if something was committed here, a stat
    line for the log)."""
    if thinking or not item.get("revising"):
        return False, ""
    patch = load_patch(item["id"])
    applied_before = bool((item.get("diff") or {}).get("applied"))
    if patch.strip() and applied_before:
        check = subprocess.run(["git", "apply", "--check"], cwd=tree, input=patch,
                               capture_output=True, text=True, timeout=180)
        if check.returncode == 0:
            subprocess.run(["git", "apply"], cwd=tree, input=patch,
                           capture_output=True, text=True, timeout=180)
        # else: it no longer applies, which for a landed patch means it is in
        # HEAD (or has since been changed on main — either way main is the
        # honest starting point, and the brief says the changes are on main).
    if not _tree_dirty(tree):
        return False, ""
    sh(["git", "add", "-A"], cwd=tree, timeout=120)
    stat = sh(["git", "diff", "--cached", "--stat"], cwd=tree, timeout=120).stdout.strip().splitlines()
    sh(["git", "-c", "user.name=Tiny Farm HQ", "-c", "user.email=hq@tiny-farm.local",
        "commit", "-q", "-m", "earlier attempt"], cwd=tree, timeout=120)
    return True, (stat[-1].strip() if stat else "applied")


def cumulative_patch(tree, base):
    """Everything in the worktree that is not on `base` — the earlier attempt
    (committed here) plus this one — for the case where the earlier attempt
    never landed on the real tree and both have to."""
    sh(["git", "add", "-A"], cwd=tree, timeout=120)
    p = sh(["git", "diff", "--cached", "--binary", base], cwd=tree, timeout=120)
    stat = sh(["git", "diff", "--cached", "--stat", base], cwd=tree, timeout=120).stdout.strip()
    files = [ln.split("\t")[-1] for ln in
             sh(["git", "diff", "--cached", "--name-only", base], cwd=tree,
                timeout=120).stdout.splitlines() if ln.strip()]
    return p.stdout, stat, files


def touches_game(files):
    return any(f.startswith(g) or f == g for f in files for g in GAME_PATHS)


# ---------------------------------------------------------------------------
# the phases
# ---------------------------------------------------------------------------

def do_item(item, org, run_id, log):
    """Worker then checker, both in the item's own worktree. Returns the record
    the session applies and writes back."""
    context = _launch_context(item["id"])
    if not execution.launch_allowed(launch_context=context, item=item["id"], phase="build-worker"):
        return {"id": item["id"], "held": True, "error": "HELD", "usage": [], "files": [], "limited": False, "patch": "", "check": None}
    seat = item["owner"]
    model = item.get("model") or server.seat_model(org, seat)
    thinking = int(item.get("tier") or 0) == 0
    rec = {"id": item["id"], "seat": seat, **execution.resolve_model(model), "usage": [],
           "patch": "", "stat": "", "files": [], "result": "", "check": None,
           "error": "", "limited": False, "resume": ""}
    # A card queued again after running out of turns carries the budget for
    # this attempt; everything else gets the standing one.
    turns = int((item.get("resume") or {}).get("turns") or 0) or WORKER_TURNS
    tree = None
    try:
        if thinking:                      # claim it before the server's worker can
            item["started"] = work._now_iso()
            work.save_item(item)
        tree = make_worktree(run_id, item["id"])
        base = sh(["git", "rev-parse", "HEAD"], cwd=tree, timeout=60).stdout.strip()
        log(f"{item['id']} · {seat} on {model or 'the default model'} · {item['title'][:60]}")
        resumed = resume_held_patch(item, tree, thinking)
        if resumed:
            log(f"{item['id']} · starts from its held patch ({resumed})")
        # A revision starts from the earlier attempt, committed in the worktree
        # so that what comes out is only what changed this time.
        committed_prior, prior_stat = resume_for_revision(item, tree, thinking)
        if committed_prior:
            log(f"{item['id']} · revises its earlier attempt ({prior_stat})")
        elif item.get("revising") and not thinking:
            log(f"{item['id']} · revises its earlier attempt (already on main)")
        if item.get("resume"):
            log(f"{item['id']} · tries again with {turns} turns"
                + ("" if resumed else " — the held patch no longer applies, so from main"))
        text, usage, err = run_cli(task_prompt(item, org, resumed=committed_prior,
                                               continuing=bool(resumed), turns=turns),
                                   seat_prompt(org, seat, thinking),
                                   READ_TOOLS if thinking else WRITE_TOOLS,
                                   model, tree, WORKER_TIMEOUT,
                                   turns, "drain-work", seat, item["id"])
        if usage:
            rec["usage"].append(dict(usage, phase="drain-work", seat=seat))
        if err == "HELD":
            rec["held"] = True
            if thinking:
                item["started"] = ""
                work.save_item(item)
            return rec
        if err == "LIMITED":
            rec["limited"] = True
            return rec
        rec["result"] = text
        rec["error"] = err
        # What the drain lands is what the real tree does not have yet. After a
        # revision of an attempt that already landed, that is this pass alone;
        # after a revision of a held attempt, it is both passes together.
        prior_landed = bool((item.get("diff") or {}).get("applied"))
        if committed_prior and not prior_landed:
            rec["patch"], rec["stat"], rec["files"] = cumulative_patch(tree, base)
        else:
            rec["patch"], rec["stat"], rec["files"] = worktree_patch(tree)
        save_patch(item["id"], rec["patch"])
        # An attempt the drain will try again is not read: nobody acts on a
        # check of half-done work, and the check is a call on the chief of
        # staff's model that the retry would only repeat.
        rec["resume"] = auto_resume_reason(item, rec)
        if rec["resume"]:
            log(f"{item['id']} · {rec['resume']} — held for another attempt")
            return rec
        # The chief of staff reads the diff, on his own seat's model.
        cmodel = server.seat_model(org, "claude")
        ctext, cusage, cerr = run_cli(check_prompt(item, text, rec["patch"], org), CHECK_SYSTEM,
                                      "Read,Glob,Grep", cmodel, tree, CHECK_TIMEOUT,
                                      CHECK_TURNS, "drain-check", "claude", item["id"])
        if cusage:
            rec["usage"].append(dict(cusage, phase="drain-check", seat="claude"))
        if cerr == "HELD":
            rec["held"] = True
            return rec
        if cerr == "LIMITED":
            rec["limited"] = True
        rec["check"] = parse_check(ctext) if ctext else None
        if rec["check"] is None and not rec["limited"]:
            rec["check"] = {"verdict": "concerns", "summary": "nobody checked this — the "
                            "check call did not come back", "findings": [], "escalates": None,
                            # `read` is False because this record stands for a read
                            # that never happened. Work may land on a clean read, so
                            # "found nothing" and "looked at nothing" have to be
                            # different facts on the record, not a turn of phrase.
                            "escalation_reason": None, "read": False}
    except Exception as e:
        rec["error"] = f"{type(e).__name__}: {e}"[:400]
    finally:
        if tree:
            drop_worktree(tree)
    return rec


def parse_check(raw):
    txt = (raw or "").strip()
    if txt.startswith("```"):
        txt = re.sub(r"^```[a-z]*\n?|```$", "", txt).strip()
    a, b = txt.find("{"), txt.rfind("}")
    if a < 0 or b <= a:
        return None
    try:
        doc = json.loads(txt[a:b + 1])
    except ValueError:
        return None
    if not isinstance(doc, dict):
        return None
    verdict = str(doc.get("verdict") or "concerns").lower()
    findings = []
    for f in (doc.get("findings") or [])[:8]:
        if isinstance(f, dict) and f.get("what"):
            findings.append({k: str(f.get(k) or "")[:400] for k in ("what", "where", "fix")})
    reason = str(doc.get("escalation_reason") or "").lower().strip()
    return {
        # This record came from a read that actually happened, which is one of
        # the four things work has to have before it may land without Daniel.
        "read": True,
        "verdict": verdict if verdict in ("pass", "concerns", "fail") else "concerns",
        "summary": str(doc.get("summary") or "")[:600],
        "findings": findings,
        "escalates": str(doc.get("escalates") or "").strip()[:600] or None,
        "escalation_reason": reason if reason in
        ("authority", "external_commitment", "exposure", "age") else None,
    }


# Files Godot regenerates whenever anything opens the project. A worker that
# ran the suites leaves these behind, they have nothing to do with the item, and
# one of them colliding with an untracked copy in the real tree held three
# otherwise-good patches on the first drain. They may be dropped from a patch;
# nothing else may.
EDITOR_NOISE = re.compile(r"(^|/)\.godot/|\.uid$|\.import$")


def _failed_paths(stderr):
    """The paths git named when it refused. Only editor noise is ever dropped —
    a substantive file that will not apply is a hold, not something to skip."""
    out = []
    for m in re.finditer(r"^error: ([^:\n]+):", stderr or "", re.M):
        path = m.group(1).strip()
        if EDITOR_NOISE.search(path):
            out.append(path)
    return sorted(set(out))


def _snapshot(files):
    """The exact bytes of the files a patch is about to touch."""
    shot = {}
    for f in files or []:
        full = os.path.join(REPO, f)
        try:
            with open(full, "rb") as fh:
                shot[f] = fh.read()
        except OSError:
            shot[f] = None            # did not exist; putting it back means removing it
    return shot


def _restore(shot):
    """Put those exact bytes back, and nothing else.

    The first draft of this used `git checkout --merge -- <paths>`, which
    restores from the INDEX — so when one item's patch failed, it silently threw
    away the working-tree changes two earlier items had already applied to the
    same file. A visual-regression job registered by one seat vanished that way
    and was only noticed because the goal pointing at it had nothing to read.
    Recovery has to mean "undo what I just did", never "reset this file"."""
    for f, data in (shot or {}).items():
        full = os.path.join(REPO, f)
        try:
            if data is None:
                if os.path.exists(full):
                    os.remove(full)
            else:
                os.makedirs(os.path.dirname(full), exist_ok=True)
                with open(full, "wb") as fh:
                    fh.write(data)
        except OSError:
            pass


def _drop_generated(patch):
    """The patch without its changes to files every run rewrites anyway."""
    import re as _re
    parts = _re.split(r"(?=^diff --git )", patch or "", flags=_re.M)
    keep = []
    for part in parts:
        m = _re.match(r"^diff --git a/(\S+)", part)
        if m and _is_generated(m.group(1)):
            continue
        keep.append(part)
    return "".join(keep)


def _patch_paths(patch):
    """The paths a patch touches, from its own headers."""
    return sorted({m.group(1) for m in re.finditer(r"^\+\+\+ b/(.+)$", patch or "", re.M)})


# Files every run rewrites on its own: the writing check's ledger of what it has
# read, and the engine's regenerated sidecars. They are always dirty in somebody's
# tree, and holding a whole patch because of one of them holds it forever — so a
# patch's changes to them are dropped and the rest goes in.
GENERATED = ("docs/writing_verdicts.json",)
GENERATED_SUFFIXES = (".uid", ".import")


def _is_generated(path):
    return path in GENERATED or path.endswith(GENERATED_SUFFIXES)


def _held_by_tree(paths):
    """Which of these paths another session holds changed and uncommitted in the
    working tree. A patch onto such a file either fails or, worse, lands on top of
    somebody's half-finished edit — so the drain does not try, and says whose
    change is in the way instead of spending a worker to find out again."""
    paths = [p for p in (paths or []) if not _is_generated(p)]
    if not paths:
        return []
    got = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all", "--"] + list(paths),
                         cwd=REPO, capture_output=True, text=True, timeout=60)
    busy = set()
    for line in got.stdout.splitlines():
        if len(line) < 4:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        busy.add(path.strip().strip('"'))
    return [p for p in paths if p in busy]


def _tree_reason(blocked):
    """Whose change is in the way is not knowable from here — the drain shares
    this tree with whoever is working in it, this session included — so the
    sentence names the files and not a culprit."""
    shown = ", ".join(blocked[:3]) + (f" and {len(blocked) - 3} more" if len(blocked) > 3 else "")
    return (f"{shown} {'is' if len(blocked) == 1 else 'are'} changed and unsaved in the "
            f"repository, so writing this in would write over that work; it goes in once "
            f"those files are committed or put away")


# What one item may cost across every attempt before the drain stops trying it
# on its own. On 2026-09-21 three items were retried hourly at $15 a run,
# landing nothing, because a misread hold was never counted as an attempt.
ITEM_COST_CAP_USD = 20.0


def _item_spend(item_id):
    """Dollars every recorded session of this item has cost, from the session
    records under hq/data/runs/workers/."""
    total = 0.0
    n = 0
    try:
        runs = os.listdir(WORKERS)
    except OSError:
        return 0.0, 0
    for run in runs:
        for name in os.listdir(os.path.join(WORKERS, run)):
            if not name.startswith(item_id + "-") or not name.endswith(".json"):
                continue
            try:
                with open(os.path.join(WORKERS, run, name), encoding="utf-8") as f:
                    meta = json.load(f)
            except (OSError, ValueError):
                continue
            cost = ((meta.get("usage") or {}).get("list_usd")) or 0.0
            if not cost:
                try:
                    with open(os.path.join(WORKERS, run, name[:-5] + ".jsonl"), encoding="utf-8") as f:
                        for line in f:
                            if '"type": "result"' in line or '"type":"result"' in line:
                                ev = json.loads(line)
                                if ev.get("type") == "result":
                                    cost = ev.get("total_cost_usd") or 0.0
                except (OSError, ValueError):
                    pass
            total += float(cost or 0.0)
            # A session the window guard stopped before it began costs nothing
            # and is not an attempt.
            n += 1 if (name.endswith("-drain-work.json") and cost) else 0
    return total, n


def _parked_by_cost(item):
    spent, attempts = _item_spend(item["id"])
    # A card whose brief was rewritten after it was parked carries its own cap,
    # set by whoever rewrote it, so the rewrite is tried once more.
    cap = float(item.get("cost_cap_usd") or ITEM_COST_CAP_USD)
    if spent <= cap:
        return False
    note = {"reason": (f"this has already cost ${spent:.0f} across {attempts} attempts without a result, "
                       f"more than the ${cap:.0f} it may spend on its own; "
                       f"it needs a smaller brief before it is tried again"),
            "spent_usd": round(spent, 2), "attempts": attempts, "at": work._now_iso()}
    old = item.get("waiting_for") or {}
    if (old.get("spent_usd"), old.get("attempts")) != (note["spent_usd"], note["attempts"]):
        item["waiting_for"] = note
        work.save_item(item)
    return True


def _parked_by_tree(item):
    """True when the item's held patch cannot land until a neighbour commits.
    Stamps the card so the queue says what it is waiting for, and clears the
    stamp the moment the way is free."""
    patch = load_patch(item["id"])
    if not patch:
        return False
    files = (item.get("diff") or {}).get("files") or _patch_paths(patch)
    blocked = _held_by_tree(files)
    if blocked:
        note = {"files": blocked[:8], "reason": _tree_reason(blocked), "at": work._now_iso()}
        if item.get("waiting_for") != note:
            item["waiting_for"] = note
            work.save_item(item)
        return True
    if item.get("waiting_for"):
        item.pop("waiting_for", None)
        work.save_item(item)
    return False


def apply_patch(patch, files):
    """Onto the real working tree, one item at a time.

    Plain apply first, because it never touches the index: Daniel and other
    sessions work in this tree, and a drain that stages or reverts files it was
    not given is a drain that eats somebody's in-flight work. Only when a patch
    no longer applies cleanly — a neighbour changed the same file — is --3way
    tried, and then only the patch's own paths are unstaged afterwards, so the
    tree is left exactly as shaped as it was found."""
    if not patch.strip():
        return True, "nothing to apply"
    patch = _drop_generated(patch)
    if not patch.strip():
        return True, "nothing to apply"
    files = [f for f in (files or _patch_paths(patch)) if not _is_generated(f)]
    blocked = _held_by_tree(files)
    if blocked:
        return False, _tree_reason(blocked)
    before = _snapshot(files)
    plain = subprocess.run(["git", "apply", "--whitespace=nowarn", "-"], cwd=REPO,
                           input=patch, capture_output=True, text=True, timeout=180)
    if plain.returncode == 0:
        return True, ""
    three = subprocess.run(["git", "apply", "--3way", "--whitespace=nowarn", "-"], cwd=REPO,
                           input=patch, capture_output=True, text=True, timeout=180)
    if three.returncode == 0:
        if files:
            subprocess.run(["git", "restore", "--staged", "--"] + files, cwd=REPO,
                           capture_output=True, text=True, timeout=120)
        return True, ""
    # One retry, with Godot's regenerated files dropped. Nothing substantive is
    # ever excluded: if the patch still will not apply, that is a real conflict.
    noise = _failed_paths(three.stderr) or _failed_paths(plain.stderr)
    if noise:
        again = subprocess.run(
            ["git", "apply", "--3way", "--whitespace=nowarn"]
            + [f"--exclude={n}" for n in noise] + ["-"],
            cwd=REPO, input=patch, capture_output=True, text=True, timeout=180)
        if again.returncode == 0:
            keep = [f for f in (files or []) if f not in noise]
            if keep:
                subprocess.run(["git", "restore", "--staged", "--"] + keep, cwd=REPO,
                               capture_output=True, text=True, timeout=120)
            return True, ""
    # A real conflict. Put back exactly the bytes that were there before this
    # patch was tried — not the index's idea of them.
    _restore(before)
    return False, _held_reason(three.stderr or plain.stderr or "")


def _held_reason(stderr):
    """One sentence Daniel can read, not a wall of git output. The paths are
    what matter — they say whose change is in the way."""
    paths = sorted({m.group(1).strip() for m in
                    re.finditer(r"^error: ([^:\n]+):", stderr or "", re.M)})
    if not paths:
        return "the patch no longer applies to the tree as it stands"
    shown = ", ".join(paths[:3]) + (f" and {len(paths) - 3} more" if len(paths) > 3 else "")
    return (f"the patch no longer applies — {shown} "
            f"{'has' if len(paths) == 1 else 'have'} changed since it was written")


def run_suites():
    """Both headless suites, once, in the real tree."""
    out = {}
    for name, cmd in (
        ("unit", ["godot", "--headless", "--path", ".", "--script",
                  "res://tests/test_runner.gd"]),
        ("integration", ["godot", "--headless", "--path", ".",
                         "res://tools/test_runner.tscn"]),
    ):
        try:
            p = sh(cmd, timeout=900)
            tail = (p.stdout or "").strip().splitlines()[-6:]
            failed = bool(re.search(r"(\d+) failed", p.stdout or "") and
                          not re.search(r"\b0 failed", p.stdout or ""))
            out[name] = {"ok": p.returncode == 0 and not failed,
                         "tail": "\n".join(tail)[-600:]}
        except Exception as e:
            out[name] = {"ok": False, "tail": f"{type(e).__name__}: {e}"[:300]}
    return out


# ---------------------------------------------------------------------------
# writing the result back onto the card
# ---------------------------------------------------------------------------

# Work that cannot be undone by reverting a commit, wherever it appears in a
# diff: a release, the deploy runbook, the store page, the build pipeline, and
# the design documents that hold the studio's direction. A patch touching any
# of these goes to Daniel however green everything else is.
NEVER_LANDS = ("docs/design/", "docs/DEPLOY.md", "ITCH_PAGE.md", ".github/",
               "hq/data/releases.json")


def _checked_tier(item, rec):
    """How hard this work is to walk back, by the best reading available. The
    chief of staff re-judges it from the diff actually produced, because the
    tier on the card was assigned before anybody knew what the work would
    touch, and an unknown blast radius is filed as the worst case."""
    check = rec.get("check") or {}
    for got in (check.get("tier_checked"), item.get("tier_checked"), item.get("tier")):
        if got is not None:
            try:
                return int(got)
            except (TypeError, ValueError):
                return 2
    return 2


def meets_landing_bar(item, rec, applied, suites):
    """Whether this finished card may go in without Daniel reading it, and if
    not, the sentence that says why (S-16, docs/QUEUE_TO_ZERO.md §4).

    All four have to hold, and none of them is the worker's own word for it:
    the work is revertable, the test suites ran green over exactly this diff,
    the chief of staff read the diff and found nothing, and nothing in the diff
    is of a kind that reverting would not undo."""
    files = list(rec.get("files") or [])

    tier = _checked_tier(item, rec)
    if tier not in (0, 1):
        return False, ("this needed your yes before it happened, so it needs your "
                       "answer now that it has")

    # A reading produces no diff, so there is nothing for the suites to run
    # over and nothing to land; everything else has to have been applied to
    # the tree and proved there.
    if not (tier == 0 and not files):
        if not applied:
            return False, "the change it wrote could not be applied to the repository"
        if not isinstance(suites, dict) or not suites:
            return False, "the test suites were not run over it"
        red = sorted(name for name, got in suites.items() if not (got or {}).get("ok"))
        if red:
            return False, (f"the {' and '.join(red)} test suite"
                           f"{'s are' if len(red) > 1 else ' is'} failing with this change in")

    check = rec.get("check") or {}
    verdict = check.get("verdict")
    # A record saying nobody read the diff is not a clean read of it. The
    # check writes that down itself when its call does not come back, so this
    # asks the record rather than guessing from the words in it.
    if check.get("read") is False:
        return False, "nobody read the change it made"
    if verdict == "pass":
        pass
    elif verdict == "concerns" and not check.get("findings"):
        pass
    elif verdict == "concerns":
        return False, "the read of it raised something you should see"
    else:
        return False, "the read of it says this should not go in as it stands"

    blocked = sorted({f for f in files
                      if any(f == n or f.startswith(n) for n in NEVER_LANDS)})
    if blocked:
        return False, (f"it changes {blocked[0]}, which undoing a commit would not put back "
                       "the way it was")

    return True, ""


def land(item, rec):
    """Commit exactly the files this card changed. Never `git add -A`: other
    sessions work in this same tree, and a landing that swept up somebody
    else's half-finished file would be a second person's work committed under
    a title that does not describe it. Returns the commit, or "" and why not."""
    files = [f for f in (rec.get("files") or []) if f]
    if not files:
        return "", "there was nothing to commit"
    add = sh(["git", "add", "--"] + files)
    if add.returncode != 0:
        return "", (add.stderr or add.stdout or "git add failed").strip()[:200]
    made = sh(["git", "commit", "-m", item["title"], "--"] + files)
    if made.returncode != 0:
        sh(["git", "restore", "--staged", "--"] + files)
        return "", (made.stderr or made.stdout or "git commit failed").strip()[:200]
    got = sh(["git", "rev-parse", "HEAD"])
    return got.stdout.strip(), ""


def plain_failure(text, applied=None, why=""):
    """A card is something Daniel reads. A raw CLI envelope pasted into the
    result field — session ids, cache counters, a `duration_api_ms` — tells him
    nothing and buries the one fact that matters, which is that the attempt did
    not finish. Recognise it and say the fact instead. When the caller already
    knows the reason (`why`, as run_cli words it), the sentence is built from
    that and the text is not inspected."""
    raw = (text or "").strip()
    if not why:
        if not raw:
            return ""
        # An envelope that was truncated on its way into the card is still an
        # envelope, and is the common case: it was clipped to fit an error field.
        if not (raw.startswith("{") and '"duration_api_ms"' in raw[:400]):
            return raw
        stop = re.search(r'"stop_reason"\s*:\s*"([a-z_]+)"', raw)
        why = {"max_turns": "it used all the turns it was given",
               "tool_use": "it used all the turns it was given, mid-edit",
               "refusal": "the model declined the task"}.get(
                   stop.group(1) if stop else "", "it did not finish cleanly")
    tail = ("What it had already changed did land, and the check below is what "
            "the chief of staff made of it." if applied else
            "Nothing it left behind was applied.")
    return f"This attempt did not finish — {why}. {tail}"


def _turns_result(item, rec, applied, body):
    """The card's text when a worker ran out of turns and the drain is not
    trying again: the fact, why the drain stopped, and whatever the worker
    managed to say before it stopped."""
    attempts = int((item.get("spent") or {}).get("attempts") or 0)
    if not rec.get("files"):
        stopped = "It changed no files, so trying again with more turns would only run out again."
    else:
        stopped = (f"That was attempt {attempts} on this card; the studio stops trying on its "
                   f"own after {AUTO_RESUMES + 1}.")
    text = plain_failure("", applied, why=rec["error"]) + " " + stopped
    if body:
        text += "\n\nWhat it said before it stopped:\n\n" + body
    return text


def write_back(item, rec, applied, why_not, suites, org):
    """The attempt onto the card. Almost always that means `for_review`, with
    whatever came back. The exception is a worker that ran out of turns with
    edits in hand (auto_resume_reason): the card goes back into the queue
    with the held patch as the next attempt's base and twice the standing
    turn budget, because a budget the drain set wrong is the drain's to fix,
    not Daniel's to judge. Either way the attempt is counted and billed."""
    body, follows, _amend, recommend, _move = work._split_result(rec["result"], org, item["owner"])
    deliverable = work.result_deliverable(rec["result"])
    # do_item decides this before the patch is held; a record that skipped
    # do_item gets the same answer here. Edits that landed are never retried.
    resume = "" if applied else (rec.get("resume") or auto_resume_reason(item, rec))
    item["attempts"] = item.get("attempts", 0) + 1
    item["done_by"] = {"seat": rec["seat"], "model": rec["model"], "lane": "drain"}
    # Whether this goes in on its own or comes to Daniel. Work he would only
    # rubber-stamp is work he should never have been shown, so the default is
    # that it lands; what sends it to him is a named reason, written on the card
    # so the next person can see which of the four things stopped it.
    landed_ok, why_not_landed = meets_landing_bar(item, rec, applied, suites)
    sha = ""
    if landed_ok and (rec.get("files") or []):
        sha, trouble = land(item, rec)
        if not sha:
            landed_ok, why_not_landed = False, trouble
    item["diff"] = {"stat": rec["stat"], "files": rec["files"][:40],
                    "applied": applied, "why_not": why_not,
                    "why_not_landed": why_not_landed}
    if landed_ok:
        work.land_item(item, "drain", sha=sha)

    if rec["check"]:
        item["check"] = rec["check"]
    if suites:
        item["suites"] = suites
    this = server.sum_usage(rec["usage"])
    item["usage"] = {"calls_detail": rec["usage"], **this}
    # What the card has cost in total, not just this time round. A card sent
    # back twice has been paid for three times, and the running total is the
    # number that answers whether it was worth having.
    prev = item.get("spent") or {}
    item["spent"] = {
        "attempts": int(prev.get("attempts") or 0) + 1,
        "tokens": int(prev.get("tokens") or 0) + this["tokens"],
        "fresh": int(prev.get("fresh") or 0) + this["fresh"],
        "list_usd": round(float(prev.get("list_usd") or 0.0) + this["list_usd"], 4),
        "unknown_cost_calls": int(prev.get("unknown_cost_calls") or 0) + this["unknown_cost_calls"],
    }
    if resume:
        turns = WORKER_TURNS * 2
        item["resume"] = {"why": resume, "turns": turns, "attempt": item["spent"]["attempts"],
                          "at": work._now_iso()}
        item["result"] = (f"This attempt did not finish — {resume}. Its edits are kept, and "
                          f"the next run of the build queue tries again from them with "
                          f"{turns} turns. Nothing has landed yet.")
        item["state"] = "waiting_session"
        item["started"] = ""
        work.save_item(item)
        return item
    item.pop("resume", None)
    if ran_out_of_turns(rec["error"]):
        item["result"] = _turns_result(item, rec, applied, body)
    else:
        item["result"] = (plain_failure(body, applied)
                          or (f"This attempt did not finish — {rec['error']}." if rec["error"]
                              else "(no result came back)"))
    if follows is not None:
        item.pop("follow_up", None)
        item["follow_ups"] = follows
        item["recommend"] = recommend or {}
    if deliverable:
        # Naming a revised result must not remove evidence already attached by
        # the deliverable path.
        item["deliverable"] = {**(item.get("deliverable") if isinstance(item.get("deliverable"), dict) else {}),
                               **deliverable}
    if not landed_ok:
        item["state"] = "for_review"
    item["finished"] = work._now_iso()
    work.finish_revision(item)
    work.save_item(item)
    return item


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

# The unattended run's own limits. Three items every two hours is a day's
# worth of results without ever being the reason a window ran dry; the window
# guard is what actually protects Daniel's own use of the allotment.
UNATTENDED_LIMIT = 3
UNATTENDED_JOBS = 2
# Skip a run when the studio's unattended work has already spent this share of
# what had been spent the last time a window ran dry.
UNATTENDED_WINDOW_SHARE = 0.6


def take_lock():
    """One drain at a time. The timer and a person at the keyboard must never
    apply patches to the same tree at once. Returns the open file (keep it
    alive) or None if another drain holds it."""
    import fcntl
    os.makedirs(WORKTREES, exist_ok=True)
    fh = open(os.path.join(WORKTREES, "drain.lock"), "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.close()
        return None
    fh.write(str(os.getpid()))
    fh.flush()
    return fh


def unattended_hold():
    """Why an unattended run should do nothing right now, or "" to go ahead.
    A dry window is the intake queue's own reading; the spend guard is the
    Work page's own number, so what the timer respects is what he can see."""
    if not execution.launch_allowed():
        return "automatic work is paused"
    if server.limited_until():
        return "the token window is dry"
    win = server.token_window()
    ceiling = win.get("dry_spend") or 0
    if ceiling and win.get("tokens", 0) >= UNATTENDED_WINDOW_SHARE * ceiling:
        return (f"the studio has spent {win['tokens']:,} tokens in the last {win['hours']} "
                f"hours, against a measured ceiling of {ceiling:,}")
    return ""


def queued(include_thinking=False):
    """What the drain may pick up. Tier 1 always; tier 0 on request, and then it
    is claimed by stamping `started` — the HQ server runs its own tier-0 worker
    and skips anything already claimed, so the two never take the same item."""
    out = [i for i in work.items() if i.get("state") == "waiting_session"]
    # A retry whose held patch waits on another session's uncommitted file is
    # not picked up: it would cost a worker and be held again for the same
    # reason. The card says what it waits for (`waiting_for`).
    out = [i for i in out if not _parked_by_tree(i)]
    # An item that has already cost more than its cap across attempts without
    # landing is not tried again on its own: it needs a smaller brief, and
    # the card says so.
    out = [i for i in out if not _parked_by_cost(i)]
    if include_thinking:
        out += [i for i in work.items()
                if i.get("state") == "doing" and not i.get("started")]
    # A card the drain is trying again is work already half paid for; it goes
    # ahead of the backlog rather than behind fifty newer items.
    out.sort(key=lambda i: 0 if i.get("resume") else 1)
    return out


def cost_summary(bill):
    """Describe known prices without turning unpriced calls into free calls."""
    calls = int(bill.get("calls") or 0)
    unknown = int(bill.get("unknown_cost_calls") or 0)
    label = "call" if unknown == 1 else "calls"
    if unknown and unknown >= calls:
        return f"dollar cost unavailable for {unknown} {label}"
    dollars = f"${bill['list_usd']:.2f}"
    if unknown:
        return f"{dollars} known plus {unknown} {label} with unknown dollar cost"
    return (f"{dollars} at API list price — this is a subscription, so that "
            "is a size, not a bill")


def main():
    ap = argparse.ArgumentParser(description="Drain HQ's build-session queue.")
    ap.add_argument("ids", nargs="*", help="work item ids; default is every queued item")
    ap.add_argument("--all", action="store_true", help="every queued item")
    ap.add_argument("--thinking", action="store_true",
                    help="also run tier-0 items (analysis and drafting, read-only)")
    ap.add_argument("--limit", type=int, default=0, help="stop after N items")
    ap.add_argument("--jobs", type=int, default=3, help="seats working at once")
    ap.add_argument("--list", action="store_true", help="what is queued, and nothing else")
    ap.add_argument("--brief", metavar="ID",
                    help="print the brief the next attempt at this item would be given, "
                         "and run nothing")
    ap.add_argument("--dry-run", action="store_true", help="say what would run")
    ap.add_argument("--apply", action="store_true",
                    help="re-apply held patches from hq/data/patches/, without running any model")
    ap.add_argument("--repair", action="store_true",
                    help="rewrite any card whose result is a raw CLI envelope, and nothing else")
    ap.add_argument("--no-suites", action="store_true", help="skip the suites (they run by default "
                                                            "when a patch touches the game)")
    ap.add_argument("--unattended", action="store_true",
                    help=f"the timer's shape: --all, at most {UNATTENDED_LIMIT} items, "
                         f"{UNATTENDED_JOBS} seats, and nothing at all when the token window "
                         "is dry or mostly spent")
    args = ap.parse_args()

    work.bind(server)
    org = server.load_org()

    if args.unattended:
        args.all = True
        args.limit = args.limit or UNATTENDED_LIMIT
        args.jobs = min(args.jobs, UNATTENDED_JOBS)
        hold = unattended_hold()
        if hold:
            print(f"Not draining: {hold}.")
            return 0

    lock = None
    if not (args.list or args.dry_run):
        lock = take_lock()
        if lock is None:
            print("Another drain is running; not starting a second one.")
            return 0

    if args.apply:
        want = set(args.ids)
        n = 0
        for it in work.items():
            if want and it["id"] not in want:
                continue
            if (it.get("diff") or {}).get("applied") or not load_patch(it["id"]):
                continue
            patch = load_patch(it["id"])
            ok, why = apply_patch(patch, (it.get("diff") or {}).get("files") or [])
            print(f"  {'applied ' if ok else 'still held'} {it['id']}  {why or it['title'][:50]}")
            if ok:
                it.setdefault("diff", {})["applied"] = True
                it["diff"]["why_not"] = ""
                work.save_item(it)
                n += 1
        print(f"{n} held patch(es) applied.")
        return 0

    if args.repair:
        n = 0
        for it in work.items():
            fixed = plain_failure(it.get("result") or "",
                                  (it.get("diff") or {}).get("applied"))
            if fixed and fixed != it.get("result"):
                it["result"] = fixed
                work.save_item(it)
                print(f"  repaired {it['id']}  {it['title'][:60]}")
                n += 1
        print(f"{n} card(s) repaired.")
        return 0

    pool = queued(args.thinking)
    if args.ids:
        want = set(args.ids)
        pool = [i for i in pool if i["id"] in want]
        missing = want - {i["id"] for i in pool}
        if missing:
            print(f"not queued: {', '.join(sorted(missing))}")
    if args.limit:
        pool = pool[:args.limit]

    if args.brief:
        for it in work.items():
            if it["id"] == args.brief:
                print(task_prompt(it, org))
                return 0
        print(f"No work item {args.brief}.")
        return 1

    if args.list or args.dry_run:
        for i in pool:
            print(f"{i['id']}  {i['owner']:9} {server.seat_model(org, i['owner']) or '-':7} "
                  f"{i['title'][:66]}")
        print(f"\n{len(pool)} queued.")
        return 0
    if not pool:
        print("Nothing queued.")
        return 0

    SUPERVISED_IDS.update(args.ids)
    pool = [i for i in pool if execution.launch_allowed(launch_context=_launch_context(i["id"]), item=i["id"], phase="build-worker")]
    if not pool:
        print("Automatic work is paused; no permitted items selected.")
        return 0

    run_id = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:4]
    _set_run(run_id)
    started = time.time()
    print(f"Draining {len(pool)} item(s), {args.jobs} at a time. Run {run_id}.\n", flush=True)

    def log(msg):
        print(f"  [{time.strftime('%H:%M:%S')}] {msg}", flush=True)

    records = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        futures = {ex.submit(do_item, i, org, run_id, log): i for i in pool}
        for fut in concurrent.futures.as_completed(futures):
            it = futures[fut]
            try:
                records[it["id"]] = fut.result()
            except Exception as e:
                records[it["id"]] = {"id": it["id"], "seat": it["owner"], "model": "",
                                     "usage": [], "patch": "", "stat": "", "files": [],
                                     "result": "", "check": None, "limited": False,
                                     "error": f"{type(e).__name__}: {e}"[:300]}
            r = records[it["id"]]
            v = (r.get("check") or {}).get("verdict", "—")
            log(f"done {it['id']} · {v} · {len(r['files'])} file(s) changed"
                + (f" · {r['error'][:80]}" if r["error"] else ""))
    shutil.rmtree(os.path.join(WORKTREES, run_id), ignore_errors=True)

    # Apply sequentially, in the order they were queued, so the tree only ever
    # moves one item at a time and a conflict names the item that caused it.
    applied_files = []
    for it in pool:
        rec = records.get(it["id"])
        if not rec or rec.get("held"):
            continue
        ok, why = (False, "the check said it should not land as it stands")
        if rec["limited"]:
            ok, why = False, "the token window ran dry before this finished"
        elif rec.get("resume"):
            # Its edits are the next attempt's starting point, not the tree's.
            ok, why = False, f"held for another attempt — {rec['resume']}"
        elif rec["error"] and not rec["patch"]:
            ok, why = False, rec["error"]
        elif not rec["patch"].strip():
            ok, why = False, "nothing changed"
        elif (rec["check"] or {}).get("verdict") != "fail":
            ok, why = apply_patch(rec["patch"], rec["files"])
            if ok:
                applied_files += rec["files"]
        rec["applied"], rec["why_not"] = ok, ("" if ok else why)
        print(f"  {'applied ' if ok else 'held    '} {it['id']}  {why}", flush=True)

    suites = None
    if applied_files and not args.no_suites:
        # Run whenever anything was applied, not only when the game itself was
        # touched: a green run over the change is one of the four things that
        # lets work go in without Daniel reading it, so a change that never
        # faced the suites has no evidence to land on.
        print("\n  running both suites over what was applied…", flush=True)
        suites = run_suites()
        for k, v in suites.items():
            print(f"  {k}: {'green' if v['ok'] else 'RED'}", flush=True)

    done = []
    for it in pool:
        rec = records.get(it["id"])
        if not rec or rec.get("held") or rec["limited"]:
            continue          # still queued; the window will come back
        fresh = server.load_json(work._item_path(it["id"]))
        done.append(write_back(fresh, rec, rec.get("applied", False), rec.get("why_not", ""),
                               suites if rec.get("applied") else None, org))

    bill = server.sum_usage([u for r in records.values() for u in r["usage"]])
    esc = [(i, records[i["id"]]["check"]) for i in pool
           if (records.get(i["id"]) or {}).get("check")
           and records[i["id"]]["check"].get("escalates")]
    went_in = [i for i in done if i.get("state") == "landed"]
    print(f"\nDrained in {int(time.time() - started) // 60} min. "
          f"{sum(1 for r in records.values() if r.get('applied'))} of {len(pool)} applied to "
          f"the tree; {len(went_in)} committed without Daniel, "
          f"{sum(1 for i in done if i.get('state') == 'for_review')} waiting for him.")
    for i in done:
        if i.get("state") == "for_review":
            print(f"  to Daniel: {i['id']}  {(i.get('diff') or {}).get('why_not_landed') or '—'}")
    print(f"Cost: {bill['calls']} model calls, {bill['tokens']:,} tokens "
          f"({cost_summary(bill)}).")
    if esc:
        print("\nEscalated to Daniel:")
        for it, ch in esc:
            print(f"  {it['id']} [{ch['escalation_reason'] or 'unstated'}] {ch['escalates']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

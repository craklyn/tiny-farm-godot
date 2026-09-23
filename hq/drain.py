"""Tiny Farm HQ — isolated worker, checker, and clean integration lane.

Tier-1 workers edit only private Git worktrees. The checker reads the diff.
The integration lane rebuilds the reviewed candidate in a detached worktree
at local main, tests that exact prospective tree, and atomically advances
local main from the expected parent. It never edits the user's checkout or
pushes a remote ref. A candidate that cannot pass receives an owned recovery
action; the shared-checkout --apply path is retired.

    worker   the seat that owns the item, on that seat's default model from
             org.json, holding only its own context — its org record, its own
             notes, the card. Not the conversation that filed the work, and not
             this session. It works in a private git worktree, so several seats
             can be wrong at the same time without standing on each other.
    checker  the chief of staff, reading the diff against the brief. The pilot's
             most useful result came from here: a worker's overclaim and a card's
             false premise were both caught by the seat that files the work.
    integrate  commit only the exact checked prospective tree on local main.
    prove      both suites run on that prospective tree before its commit.

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
import integration
import roots
import verification_evidence

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid

HERE = roots.ROOTS["code"]
REPO = roots.ROOTS["main"]
sys.path.insert(0, HERE)

import server                      # noqa: E402  (path set above)
import work                        # noqa: E402
import action_dispatch             # noqa: E402

TEST_SCRATCH = os.environ.get("HQ_TEST_SCRATCH", "")
WORKTREES = (os.path.join(TEST_SCRATCH, "worktrees") if TEST_SCRATCH
             else os.path.expanduser("~/.cache/tiny-farm-drain"))
PATCHES = (os.path.join(TEST_SCRATCH, "patches") if TEST_SCRATCH
           else os.path.join(roots.ROOTS["data"], "patches"))
# Every model session the drain runs is written here as it happens — one event
# per line, the CLI's own stream — with a small record beside it. That is what
# HQ's bullpen page (#/chat/bullpen) reads while a worker runs, and what a card's
# "How it was done" fold reads afterwards. Gitignored with the rest of runs/.
WORKERS = (os.path.join(TEST_SCRATCH, "workers") if TEST_SCRATCH
           else os.path.join(roots.ROOTS["data"], "runs", "workers"))
DRAIN_STATE = (os.path.join(TEST_SCRATCH, "drain.json") if TEST_SCRATCH
               else os.path.join(roots.ROOTS["data"], "runs", "drain.json"))
TRANSACTIONS = (os.path.join(TEST_SCRATCH, "transactions") if TEST_SCRATCH
                else os.path.join(roots.ROOTS["data"], "runs", "transactions"))
RUN_ID = ""


def _set_run(run_id):
    global RUN_ID
    RUN_ID = run_id


def record_phase(run_id, item=None, phase="idle", detail=""):
    """One live fact for the parts of a drain run that are not model sessions."""
    os.makedirs(os.path.dirname(DRAIN_STATE), exist_ok=True)
    doc = {"run": run_id, "pid": os.getpid(), "item": (item or {}).get("id", ""),
           "title": (item or {}).get("title", ""), "phase": phase,
           "detail": detail, "at": work._now_iso()}
    tmp = DRAIN_STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f)
    os.replace(tmp, DRAIN_STATE)


def checkpoint(item, rec, phase):
    """Persist the attempt before the next fallible phase begins.

    Session streams keep the prose; this record keeps the joins and verdict
    needed to recover a card without paying for either model call again.
    """
    run = RUN_ID or rec.get("run") or "byhand"
    directory = os.path.join(TRANSACTIONS, run)
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, item["id"] + ".json")
    doc = {"version": 2, "run": run, "item": item["id"], "pid": os.getpid(),
           "phase": phase, "at": work._now_iso(), "record": rec,
           "scope_id": work.instruction_fingerprint(item),
           "item_revision": item.get("_revision", 0)}
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as target:
        json.dump(doc, target)
    os.replace(tmp, path)
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
GODOT_IMPORT_TIMEOUT = 180
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


def sh(args, cwd=None, timeout=120, check=False):
    # Resolve the repository at call time. The process canary binds REPO to an
    # isolated temporary Git repository; a definition-time default would send
    # otherwise-unqualified Git commands back to the live checkout.
    if cwd is None:
        cwd = REPO
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
        doing = [r for r in rows if r["kind"] in
                 ("said", "tool", "command-failure", "terminal-failure", "finding")]
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


def task_prompt(item, org, resumed="", continuing=False, turns=WORKER_TURNS,
                action=None, blocker=None):
    convo = work._convo_lines(item, org)
    said = (f"\n\nWHAT DANIEL HAS SAID ABOUT THIS ON THE CARD — the most recent word on it, "
            f"and it overrides the brief wherever they disagree:\n\n{convo}\n") if convo else ""
    revising = work.revision_brief(item)
    external = verification_evidence.lookup(item, roots.ROOTS["data"])
    verification_brief = ("\nVALIDATED HELD-CANDIDATE VERIFICATION (same recorded attempt, tree and patch):\n"
                          + json.dumps(external, sort_keys=True) +
                          "\nThese runs describe that candidate only. If your edit changes its tree, repeat the checks.\n") if external else ""
    if revising:
        revising += ("\nYour earlier changes are already in your worktree"
                     + (" — applied and committed as \"earlier attempt\", so `git diff` "
                        "shows only what you change now." if resumed else
                        ", because they are on main.")
                     + " Read them first and build on them. Do not undo what still stands.\n")
    return f"""WORK ITEM: {item['title']}

What Daniel asked for: {item.get('ask', '')}

The next step, which is yours to take now: {item.get('first_action', '')}
{said}{prior_checks(item)}{prior_session(item)}{verification_brief}{revising}{resume_brief(item, continuing, turns)}{action_dispatch.reconcile_brief(action or {}, blocker)}
Include outcome: {{"status": "complete|blocked|unfinished", "reason": "concrete reason"}} in the final WHAT FOLLOWS JSON object. Use items: [] rather than NONE.
Do the work in your worktree. Then reply with the deliverable Daniel reads: what
you changed, what it now does, and anything you found that he should know.
Plain language, no preamble, no ticket IDs, as short as the work allows. Do not
paste the diff — he can see it.

If you could not finish it, say in one line what is blocking it and who has to
unblock it. A blocked item honestly reported beats a plausible guess, and if the
blocker is Daniel himself, name what you need from him.

{work._follows_spec(org, completion=True)}"""


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


def check_prompt(item, result, diff, org=None, execution_evidence=None, external_evidence=None):
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
    evidence = json.dumps(execution_evidence or {"status": "no completed owner command evidence"},
                          ensure_ascii=False, sort_keys=True)
    external = json.dumps(external_evidence or {"status": "no validated external verification"},
                          ensure_ascii=False, sort_keys=True)
    return f"""THE ITEM: {item['title']}
What Daniel asked for: {item.get('ask', '')}
The step that was theirs to take: {item.get('first_action', '')}
Who did it: {item['owner']}
{revising}
WHAT THEY SAID THEY DID:
{(result or '(no reply came back)')[:8000]}

OWNER EXECUTION EVIDENCE (recorded by HQ's session adapter, not the owner's reply):
{evidence}
VALIDATED EXTERNAL VERIFICATION (only for this exact candidate tree and patch):
{external}
The owner record names its original run, attempt and candidate tree. An
evidence-only re-review may have a later review run for that same tree. A command's
output proves only what that command reported at that point in the session;
inspect the candidate diff and do not assume a later edit was tested. The full
stream is at log_path. Claims need completed command results or validated external evidence.

THE DIFF THEY PRODUCED:
{diff[:60000] if diff else '(no files changed)'}

Reply with raw JSON, no fence and no prose:
{{"verdict": "pass|concerns|fail", "complete": true,
 "summary": "one sentence Daniel can read: what landed, and what to watch",
 "findings": [{{"what": "the problem in one line", "where": "file or file:line", "fix": "what to do about it"}}],
 "unrelated_generated_files": [],
 "lesson_for_owner": null,
 "escalates": null,
 "escalation_reason": null}}

When the review itself establishes a reusable rule for the owner, replace
lesson_for_owner with {{"text": "the durable lesson"}}. This is the only place
for that lesson; do not hide memory instructions in summary or findings. Leave
it null when the review established no durable lesson.
List docs/writing_verdicts.json in unrelated_generated_files only when you
specifically found it in this diff, found it unrelated to the requested work,
and recorded a finding that asks to remove it. Otherwise leave the list empty.

Set complete true only when the entire requested result is finished, not blocked or a partial attempt.
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


_SUITE_RESULT = re.compile(r"Results: (\d+) PASSED, (\d+) FAILED")
_SCENARIO_W_PASS = "✓ even though the sim washed it dry at the tap"
_INTEGRATION_COMMAND = ("tools/run_godot_test.py", "res://tools/test_runner.tscn")


def owner_execution_evidence(log_path, *, run, attempt_id, candidate):
    """Summarize completed tool results from this attempt's session stream.

    This is evidence for the checker to inspect, not a substitute for the
    prospective-main suites. Failed, started-only and prose events never count.
    The SHA allows a later reader to detect a changed stream; the candidate
    identity says which proposed tree this review concerns, without claiming
    that every earlier command ran on its final bytes.
    """
    evidence = {"version": 1, "run": run, "attempt_id": attempt_id,
                "candidate_tree": (candidate or {}).get("tree", ""),
                "log_path": os.path.abspath(log_path), "log_sha256": "",
                "completed_integration_runs": 0, "scenario_w_passes": 0,
                "commands": []}
    try:
        digest = hashlib.sha256()
        starts = {}
        seen = set()
        with open(log_path, "rb") as source:
            for raw in source:
                digest.update(raw)
                try:
                    event = json.loads(raw)
                except (UnicodeDecodeError, ValueError):
                    continue
                if not isinstance(event, dict):
                    continue
                for block in ((event.get("message") or {}).get("content") or []):
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_use":
                        starts[str(block.get("id") or "")] = str(
                            (block.get("input") or {}).get("command") or "")
                    if block.get("type") != "tool_result":
                        continue
                    call_id = str(block.get("tool_use_id") or "")
                    if not call_id or call_id in seen:
                        continue
                    seen.add(call_id)
                    command = str(block.get("command") or starts.get(call_id) or "")
                    if not all(part in command for part in _INTEGRATION_COMMAND):
                        continue
                    output = block.get("content")
                    if not isinstance(output, str):
                        continue
                    matches = list(_SUITE_RESULT.finditer(output))
                    result = matches[-1] if matches else None
                    exit_code = block.get("exit_code")
                    complete = (block.get("status") == "completed"
                                and type(exit_code) is int and exit_code == 0)
                    passing = (complete and result is not None
                               and int(result.group(2)) == 0)
                    scenario_w = passing and _SCENARIO_W_PASS in output
                    if passing:
                        evidence["completed_integration_runs"] += 1
                    if scenario_w:
                        evidence["scenario_w_passes"] += 1
                    if len(evidence["commands"]) < 20:
                        evidence["commands"].append({
                            "call_id": call_id, "exit_code": exit_code,
                            "status": block.get("status"),
                            "command": command[:300],
                            "result": result.group(0) if result else "",
                            "scenario_w_pass": bool(scenario_w),
                        })
        evidence["log_sha256"] = digest.hexdigest()
    except OSError:
        evidence["status"] = "owner session log missing"
    return evidence


def enforce_execution_claims(check, result, evidence):
    """A reviewer cannot pass an explicit repeat-run claim on prose alone."""
    if not check:
        return check
    words = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
             "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}
    claims = []
    text = str(result or "")
    for match in re.finditer(r"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+"
                             r"(?:complete(?:d)?\s+)?integration runs?\b", text, re.I):
        token = match.group(1).lower()
        claims.append((int(token) if token.isdigit() else words[token],
                       "completed_integration_runs", "integration runs"))
    for match in re.finditer(r"Scenario W[^\n.]*?passed\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+times", text, re.I):
        token = match.group(1).lower()
        claims.append((int(token) if token.isdigit() else words[token],
                       "scenario_w_passes", "Scenario W passes"))
    for match in re.finditer(r"Scenario W[^\n.]*?\b(\d+)\s*/\s*(\d+)\b", text, re.I):
        if match.group(1) == match.group(2):
            claims.append((int(match.group(2)), "scenario_w_passes", "Scenario W passes"))
    for expected, key, label in claims:
        actual = int((evidence or {}).get(key) or 0)
        external = (evidence or {}).get("external_verification") or {}
        # The owner's session may have recorded the same invocation as the
        # attached manifest. Without shared run IDs, only the larger count is
        # safe to credit toward one claim.
        if key == "completed_integration_runs":
            actual = max(actual, int(external.get("passing_suites") or 0))
        elif key == "scenario_w_passes" and external.get("assertion") == "even though the sim washed it dry at the tap":
            actual = max(actual, int(external.get("assertion_passes") or 0))
        if actual >= expected:
            continue
        check["verdict"] = "fail"
        check["complete"] = False
        check.setdefault("findings", []).append({
            "what": f"The reply claims {expected} {label}; the evidence supports {actual} completed passing results.",
            "where": (evidence or {}).get("log_path") or "owner session log",
            "fix": "Provide completed command results for this attempt or correct the claim.",
        })
    return check


def check_evidence_id(rec):
    parts = [rec.get("result"), rec.get("patch", ""), rec.get("candidate")]
    if rec.get("execution_evidence") is not None:
        parts.append(rec["execution_evidence"])
    if rec.get("external_verification") is not None:
        parts.append(rec["external_verification"])
    return work.evidence_id(parts)


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


def run_cli(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id,
            attempt_id=""):
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
    meta = {"item": item_id, "attempt_id": attempt_id, "seat": seat, **execution.resolve_model(model),
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
RETRY_ONCE_IDS = set()
FINISH_VERIFIED_IDS = set()


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
    if item.get("automatic_repairs") or item.get("repair_hold"):
        return ""
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
        sh(["git", "worktree", "add", "--detach", path, "main"], check=True, timeout=600)
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
    # The legacy name is a pointer to the latest attempt. Keep each input to
    # review/integration reconstructable even after a later attempt replaces it.
    digest = work.hashlib.sha256(patch.encode("utf-8")).hexdigest()
    archive = os.path.join(PATCHES, "candidates")
    os.makedirs(archive, exist_ok=True)
    immutable = os.path.join(archive, digest + ".patch")
    if not os.path.exists(immutable):
        tmp = immutable + "." + uuid.uuid4().hex + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(patch)
        try:
            os.link(tmp, immutable)
        except FileExistsError:
            pass
        finally:
            os.unlink(tmp)
    path = os.path.join(PATCHES, item_id + ".patch")
    tmp = path + "." + uuid.uuid4().hex + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(patch)
    os.replace(tmp, path)
    return path


def patch_artifact(patch):
    if not patch or not patch.strip():
        return None
    digest = work.hashlib.sha256(patch.encode("utf-8")).hexdigest()
    return {"id": digest, "path": os.path.join(PATCHES, "candidates", digest + ".patch")}


def checked_patch(rec):
    """Prefer the immutable candidate body; refuse altered or missing archives."""
    artifact = rec.get("patch_artifact")
    patch = rec.get("patch") or ""
    if not artifact:
        return patch
    digest = artifact.get("id") or ""
    expected = os.path.realpath(os.path.join(PATCHES, "candidates", digest + ".patch"))
    if artifact.get("path") != expected or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Invalid immutable candidate patch reference")
    with open(expected, encoding="utf-8") as source:
        archived = source.read()
    if work.hashlib.sha256(archived.encode()).hexdigest() != digest or archived != patch:
        raise ValueError("Immutable candidate patch differs from the checked record")
    return archived


def recover_prior_check(item, transaction, attempt_id):
    """Restore one lost review from a finished transaction onto its own card.

    The caller saves the card after inspecting it. The attempt, checked patch,
    and candidate must all match the card's durable workflow record.
    """
    rec = transaction.get("record") or {}
    candidate = rec.get("candidate") or {}
    artifact = rec.get("patch_artifact") or {}
    if (transaction.get("phase") != "written_back"
            or transaction.get("item") != item.get("id")
            or rec.get("id") != item.get("id")
            or rec.get("attempt_id") != attempt_id
            or not rec.get("check") or not rec.get("check_evidence")
            or rec["check_evidence"] != check_evidence_id(rec)):
        raise ValueError("Transaction does not contain this card's finished, checked attempt")
    checked_patch(rec)
    if not any(row.get("attempt_id") == attempt_id
               and row.get("tree") == candidate.get("tree")
               and (row.get("patch") or {}).get("id") == artifact.get("id")
               for row in (item.get("workflow") or {}).get("candidates", [])):
        raise ValueError("Checked candidate is not recorded on this card")
    if (item.get("check") or {}).get("attempt_id") == attempt_id:
        return False
    if any(row.get("attempt_id") == attempt_id for row in item.get("prior_checks") or []):
        return False
    restored = {key: value for key, value in rec["check"].items()
                if key != "lesson_for_owner"}
    restored["attempt_id"] = attempt_id
    item.setdefault("prior_checks", []).append(restored)
    return True


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
    _remove_reviewed_generated_file(item, tree, patch)
    stat = subprocess.run(["git", "diff", "--stat"], cwd=tree, capture_output=True,
                          text=True, timeout=120).stdout.strip().splitlines()
    return stat[-1].strip() if stat else ("applied" if _tree_dirty(tree) else "")


def _remove_reviewed_generated_file(item, tree, patch):
    """Undo only a generated path the last reviewer explicitly rejected.

    The held patch and its immutable archive remain untouched. This changes the
    retry worktree, so its next cumulative patch is a new reviewed candidate.
    """
    path = "docs/writing_verdicts.json"
    if path not in _patch_paths(patch):
        return False
    if not any(_review_explicitly_removed_generated_file(check, path)
               for check in reversed(item.get("prior_checks") or [])):
        return False
    sh(["git", "restore", "--source=HEAD", "--staged", "--worktree", "--", path],
       cwd=tree, check=True, timeout=120)
    return True


def _review_explicitly_removed_generated_file(check, path):
    if not isinstance(check, dict) or check.get("verdict") not in ("concerns", "fail"):
        return False
    marked = path in (check.get("unrelated_generated_files") or [])
    return any(re.fullmatch(re.escape(path) + r"(?::\d+)?", f.get("where") or "")
               and re.search(r"\b(remove|drop|revert|exclude)\b", f.get("fix") or "", re.I)
               and (marked or re.search(r"\bunrelated\b", " ".join(
                   (f.get("what") or "", f.get("fix") or "")), re.I))
               for f in (check.get("findings") or []) if isinstance(f, dict))


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
    # This is a private bookkeeping commit, not the reviewed result. The
    # commit-msg hook writes a verdict for its synthetic subject into the
    # worktree; without this override that verdict becomes part of the
    # worker's next patch even though the worker never touched it.
    made = sh(["git", "-c", "user.name=Tiny Farm HQ", "-c", "user.email=hq@tiny-farm.local",
               "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "earlier attempt"],
              cwd=tree, timeout=120)
    if made.returncode:
        raise RuntimeError((made.stderr or made.stdout or "The held patch could not be committed.").strip())
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


def candidate_unchanged(tree, expected_tree):
    """The index, tracked files, and untracked files still describe one tree."""
    return (sh(["git", "write-tree"], cwd=tree).stdout.strip() == expected_tree
            and sh(["git", "diff", "--quiet", expected_tree, "--"], cwd=tree).returncode == 0
            and not sh(["git", "ls-files", "--others", "--exclude-standard"], cwd=tree).stdout.strip())


def restore_test_generated(tree, expected_tree):
    """Discard only generated byproducts produced after the candidate snapshot.

    The candidate index must still be exact. An authored verdict or sidecar
    already in that snapshot is restored to its reviewed bytes, not removed.
    Any non-generated drift remains visible to candidate_unchanged.
    """
    if sh(["git", "write-tree"], cwd=tree).stdout.strip() != expected_tree:
        return False
    changed = sh(["git", "diff", "--name-only", "-z", expected_tree, "--"], cwd=tree)
    if changed.returncode:
        return False
    for name in changed.stdout.split("\0"):
        if name and _is_generated(name):
            restored = sh(["git", "restore", "--source=" + expected_tree,
                           "--worktree", "--", name], cwd=tree)
            if restored.returncode:
                return False
    untracked = sh(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=tree)
    if untracked.returncode:
        return False
    for name in untracked.stdout.split("\0"):
        if name and _is_generated(name):
            path = os.path.join(tree, name)
            if not os.path.isfile(path) and not os.path.islink(path):
                return False
            os.unlink(path)
    return True


def touches_game(files):
    return any(f.startswith(g) or f == g for f in files for g in GAME_PATHS)


class GodotImportHold(RuntimeError):
    """The owner cannot safely test this checkout until Godot has indexed it."""


def needs_godot_import(item):
    """Only build cards that point at game code need the engine's class cache."""
    if int(item.get("tier") or 0) < 1:
        return False
    brief = "\n".join(str(item.get(key) or "") for key in
                      ("ask", "first_action", "title"))
    return bool(re.search(r"\.(?:gd|tscn|tres)\b|\bproject\.godot\b|"
                          r"\b(?:world|player|entities|systems|ui|effects|crops|tests)/|"
                          r"\b(?:Godot|GDScript|gameplay|simulation)\b", brief, re.I))


def preflight_godot_import(tree):
    """Index a private checkout, then remove only known generated sidecars.

    This runs after a held patch has been applied, so Godot sees the classes
    the owner will test. The reviewed candidate remains the exact authored tree.
    """
    staged = sh(["git", "add", "-A"], cwd=tree, timeout=120)
    if staged.returncode:
        raise GodotImportHold("Godot import tooling hold: could not snapshot the worktree index.")
    snapshot = sh(["git", "write-tree"], cwd=tree, timeout=120)
    if snapshot.returncode or not snapshot.stdout.strip():
        raise GodotImportHold("Godot import tooling hold: could not snapshot the worktree tree.")
    expected = snapshot.stdout.strip()
    try:
        result = sh(["godot", "--headless", "--path", ".", "--import"],
                    cwd=tree, timeout=GODOT_IMPORT_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GodotImportHold(f"Godot import tooling hold: {type(exc).__name__} after at most "
                              f"{GODOT_IMPORT_TIMEOUT} seconds.") from exc
    restored = restore_test_generated(tree, expected)
    clean = restored and candidate_unchanged(tree, expected)
    output = (result.stdout or "") + "\n" + (result.stderr or "")
    parse_error = re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:|Parse Error:)", output)
    if result.returncode or parse_error or not clean:
        detail = ("Godot reported a parse/import error" if parse_error else
                  f"Godot exited {result.returncode}" if result.returncode else
                  "import changed files outside known generated sidecars")
        tail = " ".join(output.strip().split())[-240:]
        raise GodotImportHold(f"Godot import tooling hold: {detail}. {tail}"[:400])


# ---------------------------------------------------------------------------
# the phases
# ---------------------------------------------------------------------------

def do_item(item, org, run_id, log, action=None):
    """Worker then checker, both in the item's own worktree. Returns the record
    the session applies and writes back."""
    context = _launch_context(item["id"])
    if not execution.launch_allowed(launch_context=context, item=item["id"], phase="build-worker"):
        return {"id": item["id"], "held": True, "error": "HELD", "usage": [], "files": [], "limited": False, "patch": "", "check": None}
    seat = item["owner"]
    model = item.get("model") or server.seat_model(org, seat)
    thinking = int(item.get("tier") or 0) == 0
    rec = {"id": item["id"], "attempt_id": work.uuid.uuid4().hex, "seat": seat, **execution.resolve_model(model), "usage": [],
           "patch": "", "stat": "", "files": [], "result": "", "check": None,
           "error": "", "limited": False, "resume": ""}
    checkpoint(item, rec, "started")
    # A card queued again after running out of turns carries the budget for
    # this attempt; everything else gets the standing one.
    turns = int((item.get("resume") or {}).get("turns") or 0) or WORKER_TURNS
    tree = None
    try:
        # The card and the bullpen must agree on whether this is queued or
        # running. Tier-0 also needs this claim before the server's own worker
        # can see it; tier-1 needs it so the page has real start evidence.
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
        if needs_godot_import(item):
            record_phase(run_id, item, "importing", "Godot is indexing the isolated game checkout.")
            preflight_godot_import(tree)
        record_phase(run_id, item, "worker", "The owner is repairing it.")
        text, usage, err = run_cli(task_prompt(item, org, resumed=committed_prior,
                                               continuing=bool(resumed), turns=turns,
                                               action=action,
                                               blocker=project_work(item).get("blocker") if action else None),
                                   seat_prompt(org, seat, thinking),
                                   READ_TOOLS if thinking else WRITE_TOOLS,
                                   model, tree, WORKER_TIMEOUT,
                                   turns, "drain-work", seat, item["id"], rec["attempt_id"])
        if usage:
            rec["usage"].append(dict(usage, phase="drain-work", seat=seat))
        if err == "HELD":
            rec["held"] = True
            item["started"] = ""
            work.save_item(item)
            return rec
        if err == "LIMITED":
            rec["limited"] = True
            return rec
        rec["result"] = text
        rec["error"] = err
        checkpoint(item, rec, "worker_finished")
        # What the drain lands is what the real tree does not have yet. After a
        # revision of an attempt that already landed, that is this pass alone;
        # after a revision of a held attempt, it is both passes together.
        prior_landed = bool((item.get("diff") or {}).get("applied"))
        if committed_prior and not prior_landed:
            rec["patch"], rec["stat"], rec["files"] = cumulative_patch(tree, base)
        else:
            rec["patch"], rec["stat"], rec["files"] = worktree_patch(tree)
        save_patch(item["id"], rec["patch"])
        rec["patch_artifact"] = patch_artifact(rec["patch"])
        # An attempt the drain will try again is not read: nobody acts on a
        # check of half-done work, and the check is a call on the chief of
        # staff's model that the retry would only repeat.
        rec["resume"] = auto_resume_reason(item, rec)
        if rec["resume"]:
            log(f"{item['id']} · {rec['resume']} — held for another attempt")
            return rec
        rec["candidate"] = {
            "tree": sh(["git", "write-tree"], cwd=tree, check=True).stdout.strip(),
            "base": base,
            "files": git_blobs(tree, "", rec["files"]),
            "base_files": git_blobs(tree, base, rec["files"]),
        }
        rec["execution_evidence"] = owner_execution_evidence(
            os.path.join(WORKERS, RUN_ID or "byhand", f"{item['id']}-drain-work.jsonl"),
            run=RUN_ID or "byhand", attempt_id=rec["attempt_id"],
            candidate=rec["candidate"])
        external = verification_evidence.lookup(item, roots.ROOTS["data"])
        if external and (external["candidate_tree"] != rec["candidate"]["tree"] or
                         external["patch_id"] != work.evidence_id(rec["patch"])):
            external = None
        rec["external_verification"] = external
        if external:
            rec["execution_evidence"]["external_verification"] = external
        # The chief of staff reads the diff, on his own seat's model.
        record_phase(run_id, item, "reviewing", "The chief of staff is reading the proposed change.")
        cmodel = server.seat_model(org, "claude")
        ctext, cusage, cerr = run_cli(check_prompt(item, text, rec["patch"], org,
                                                  rec["execution_evidence"], external), CHECK_SYSTEM,
                                      "Read,Glob,Grep", cmodel, tree, CHECK_TIMEOUT,
                                      CHECK_TURNS, "drain-check", "claude", item["id"], rec["attempt_id"])
        if cusage:
            rec["usage"].append(dict(cusage, phase="drain-check", seat="claude"))
        if cerr == "HELD":
            rec["held"] = True
            return rec
        if cerr == "LIMITED":
            rec["limited"] = True
        rec["check"] = enforce_execution_claims(
            parse_check(ctext) if ctext else None, text, rec["execution_evidence"])
        if rec["check"] and not cerr:
            rec["check_evidence"] = check_evidence_id(rec)
        checkpoint(item, rec, "review_finished")
        if rec["files"] and rec["check"] and not cerr:
            record_phase(run_id, item, "checking_candidate", "The proposed change is running its tests.")
            rec["candidate_suites"] = run_suites(cwd=tree)
            restore_test_generated(tree, rec["candidate"]["tree"])
            checkpoint(item, rec, "candidate_tested")
        rec["candidate_unchanged"] = candidate_unchanged(tree, rec["candidate"]["tree"])
        rec["candidate_test_evidence"] = work.evidence_id([rec["candidate"], rec.get("candidate_suites")])
        if rec["check"] is None and not rec["limited"]:
            rec["check"] = {"verdict": "concerns", "summary": "nobody checked this — the "
                            "check call did not come back", "findings": [], "escalates": None,
                            # `read` is False because this record stands for a read
                            # that never happened. Work may land on a clean read, so
                            # "found nothing" and "looked at nothing" have to be
                            # different facts on the record, not a turn of phrase.
                            "escalation_reason": None, "read": False}
    except GodotImportHold as e:
        rec["held"] = True
        rec["tooling_hold"] = True
        rec["error"] = str(e)
        item["started"] = ""
        work.save_item(item)
        checkpoint(item, rec, "tooling_hold")
    except Exception as e:
        rec["error"] = f"{type(e).__name__}: {e}"[:400]
        checkpoint(item, rec, "interrupted")
    finally:
        if tree:
            drop_worktree(tree)
    return rec


def recorded_candidate_attempt(item):
    """The last card attempt's immutable transaction, if it is still this patch."""
    outcome = item.get("attempt_outcome") or {}
    candidate = outcome.get("candidate") or {}
    if not candidate or candidate.get("base") != integration.main_head(server.REPO):
        return None
    attempt_id = item.get("last_recorded_attempt")
    try:
        runs = sorted(os.listdir(TRANSACTIONS), reverse=True)
    except OSError:
        return None
    for run in runs:
        path = os.path.join(TRANSACTIONS, run, item["id"] + ".json")
        try:
            with open(path, encoding="utf-8") as source:
                tx = json.load(source)
        except (OSError, ValueError):
            continue
        old = tx.get("record") or {}
        if (old.get("attempt_id") != attempt_id or
                old.get("candidate") != candidate or
                work.evidence_id(old.get("patch", "")) != outcome.get("patch_id") or
                not old.get("result")):
            continue
        return old
    return None


def held_recheck_source(item):
    """A new complete test manifest reopens only the unchanged review step."""
    evidence = verification_evidence.lookup(item, roots.ROOTS["data"])
    if (not evidence or evidence["completed_runs"] != evidence["requested_runs"] or
            evidence["passing_suites"] != evidence["requested_runs"] or
            evidence["assertion_passes"] != evidence["requested_runs"]):
        return None
    old = recorded_candidate_attempt(item)
    return (old, evidence) if old and old.get("execution_evidence") else None


def verified_landing_source(item):
    """Reuse a passing review when only an unimported checkout stopped landing."""
    old = recorded_candidate_attempt(item)
    if not old:
        return None
    check = old.get("check") or {}
    suites = old.get("suites") or {}
    candidate = old.get("candidate") or {}
    external = old.get("external_verification") or {}
    if (check.get("verdict") != "pass" or check.get("complete") is not True or
            check.get("findings") or old.get("check_evidence") != check_evidence_id(old) or
            old.get("candidate_unchanged") is not True or
            old.get("candidate_test_evidence") != work.evidence_id([candidate, old.get("candidate_suites")]) or
            any(not (old.get("candidate_suites") or {}).get(name, {}).get("ok")
                for name in ("unit", "integration")) or
            not suites or any(row.get("ok") for row in suites.values()) or
            not all("Parse Error:" in str(row.get("tail") or "") for row in suites.values())):
        return None
    # The manifest belongs to the original owner attempt, not this later
    # review. Validate its hashed logs against that original candidate again.
    if item.get("state") == "landed" or (item.get("attempt_outcome") or {}).get("landing_verified"):
        return None
    # `diff.applied` means the isolated prospective tree was prepared, not
    # that local main received the patch. The old manifest was attached while
    # this same candidate was held; validate it against that held snapshot.
    historical = {**item, "last_recorded_attempt": external.get("attempt_id"),
                  "diff": {**(item.get("diff") or {}), "applied": False}}
    try:
        validated = verification_evidence.validate(
            historical, external.get("path", ""), roots.ROOTS["data"])
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        return None
    if validated != external:
        return None
    return old


def resume_verified_landing(item, run_id, old):
    """Retry only the prospective checkout and suites; use zero model calls."""
    rec = {**old, "attempt_id": uuid.uuid4().hex, "usage": [], "error": "",
           "limited": False, "held": False, "resume": "", "applied": False,
           "verification_only": True, "suites": None, "tree_evidence": None,
           "integration_checkout": ""}
    record_phase(run_id, item, "preparing_verification",
                 "The unchanged reviewed patch is retrying its local-main test gate.")
    return rec


def recheck_held_candidate(item, org, run_id, source):
    """Fresh independent review of an unchanged candidate; no owner model call."""
    old, external = source
    rec = {**old, "attempt_id": uuid.uuid4().hex, "usage": [], "error": "",
           "limited": False, "held": False, "resume": "", "applied": False,
           "review_only": True, "check": None, "check_evidence": None,
           "candidate_suites": None, "suites": None, "tree_evidence": None,
           "integration_checkout": "", "external_verification": external}
    rec["execution_evidence"] = {**old["execution_evidence"],
                                 "external_verification": external}
    tree = ""
    try:
        record_phase(run_id, item, "preparing_review", "The verified held patch is being reconstructed exactly.")
        tree, kind, why = prepare_integration(rec)
        if kind:
            rec["held"], rec["error"] = True, why
            return rec
        if touches_game(rec.get("files") or []):
            preflight_godot_import(tree)
        record_phase(run_id, item, "reviewing", "The chief of staff is re-reading the unchanged candidate and new test evidence.")
        cmodel = server.seat_model(org, "claude")
        ctext, cusage, cerr = run_cli(check_prompt(item, rec["result"], rec["patch"], org,
                                                  rec["execution_evidence"], external), CHECK_SYSTEM,
                                      "Read,Glob,Grep", cmodel, tree, CHECK_TIMEOUT,
                                      CHECK_TURNS, "drain-check", "claude", item["id"], rec["attempt_id"])
        if cusage:
            rec["usage"].append(dict(cusage, phase="drain-check", seat="claude"))
        if cerr:
            rec["held"], rec["error"] = True, cerr
            return rec
        rec["check"] = enforce_execution_claims(parse_check(ctext) if ctext else None,
                                                rec["result"], rec["execution_evidence"])
        if rec["check"]:
            rec["check_evidence"] = check_evidence_id(rec)
        checkpoint(item, rec, "review_finished")
        if rec["files"] and rec["check"]:
            record_phase(run_id, item, "checking_candidate", "The re-reviewed candidate is running both game suites.")
            rec["candidate_suites"] = run_suites(cwd=tree)
            restore_test_generated(tree, rec["candidate"]["tree"])
            checkpoint(item, rec, "candidate_tested")
        rec["candidate_unchanged"] = candidate_unchanged(tree, rec["candidate"]["tree"])
        rec["candidate_test_evidence"] = work.evidence_id([rec["candidate"], rec.get("candidate_suites")])
        if rec["check"] is None:
            rec["check"] = {"verdict": "concerns", "complete": False,
                            "summary": "The evidence-only review did not return a readable verdict.",
                            "findings": [], "escalates": None, "escalation_reason": None, "read": False}
    except GodotImportHold as exc:
        rec["held"], rec["tooling_hold"], rec["error"] = True, True, str(exc)
    except Exception as exc:
        rec["held"], rec["error"] = True, f"{type(exc).__name__}: {exc}"[:400]
    finally:
        if tree:
            integration.remove_candidate(server.REPO, tree, WORKTREES)
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
    raw_findings = doc.get("findings")
    valid_findings = isinstance(raw_findings, list) and all(isinstance(f, dict) and f.get("what") for f in raw_findings)
    raw_lesson = doc.get("lesson_for_owner")
    valid_lesson = ("lesson_for_owner" not in doc or raw_lesson is None
                    or (isinstance(raw_lesson, dict)
                        and set(raw_lesson) == {"text"}
                        and bool(str(raw_lesson.get("text") or "").strip())))
    lesson = None
    if valid_lesson and isinstance(raw_lesson, dict):
        lesson = {"text": " ".join(str(raw_lesson["text"]).split())[:600]}
    for f in (raw_findings if isinstance(raw_findings, list) else [])[:8]:
        if isinstance(f, dict) and f.get("what"):
            findings.append({k: str(f.get(k) or "")[:400] for k in ("what", "where", "fix")})
    reason = str(doc.get("escalation_reason") or "").lower().strip()
    unrelated = doc.get("unrelated_generated_files")
    unrelated = (["docs/writing_verdicts.json"] if isinstance(unrelated, list)
                 and "docs/writing_verdicts.json" in unrelated else [])
    return {
        # This record came from a read that actually happened, which is one of
        # the four things work has to have before it may land without Daniel.
        "read": True,
        "complete": doc.get("complete") is True and valid_findings and valid_lesson,
        "verdict": verdict if verdict in ("pass", "concerns", "fail") else "concerns",
        "summary": str(doc.get("summary") or "")[:600],
        "findings": findings,
        "unrelated_generated_files": unrelated,
        "lesson_for_owner": lesson,
        "escalates": str(doc.get("escalates") or "").strip()[:600] or None,
        "escalation_reason": reason if reason in
        ("authority", "external_commitment", "exposure", "age") else None,
    }


def _patch_paths(patch):
    """The paths a patch touches, from its own headers."""
    return sorted({m.group(1) for m in re.finditer(r"^\+\+\+ b/(.+)$", patch or "", re.M)})


# Files every run rewrites on its own: the writing check's ledger of what it has
# read, and the engine's regenerated sidecars. They are always dirty in somebody's
# tree. Legacy overlap classification ignores them; the clean integration lane
# still requires every reviewed candidate byte, including generated sidecars.
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
# Codex subscription sessions do not report a dollar price. A dollar-only cap
# therefore reads a multi-million-token attempt as free. The per-card token
# limits are the guard for every provider, priced or not; an explicit reviewed
# card override may raise them for exceptional work.
ITEM_TOKEN_CAP = 1_000_000
ITEM_FRESH_TOKEN_CAP = 150_000


def _item_spend(item_id):
    """Measured dollar and token spend from every recorded model session."""
    total = 0.0
    tokens = fresh = 0
    n = 0
    try:
        runs = os.listdir(WORKERS)
    except OSError:
        return 0.0, 0, 0, 0
    for run in runs:
        for name in os.listdir(os.path.join(WORKERS, run)):
            if not name.startswith(item_id + "-") or not name.endswith(".json"):
                continue
            try:
                with open(os.path.join(WORKERS, run, name), encoding="utf-8") as f:
                    meta = json.load(f)
            except (OSError, ValueError):
                continue
            usage = meta.get("usage") or {}
            tokens += int(usage.get("tokens") or 0)
            fresh += int(usage.get("fresh") or
                         (int(usage.get("input_tokens") or 0) + int(usage.get("output_tokens") or 0)))
            cost = usage.get("list_usd") or 0.0
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
            n += int(name.endswith("-drain-work.json") and bool(usage.get("tokens") or cost))
    return total, n, tokens, fresh


def item_capacity_reason(item):
    """One human-readable hold, including unpriced subscription usage."""
    dollars, attempts, tokens, fresh = _item_spend(item["id"])
    dollar_cap = float(item.get("cost_cap_usd") or ITEM_COST_CAP_USD)
    token_cap = int(item.get("token_cap") or ITEM_TOKEN_CAP)
    fresh_cap = int(item.get("fresh_token_cap") or ITEM_FRESH_TOKEN_CAP)
    if dollars > dollar_cap:
        return (f"this has already cost ${dollars:.0f} across {attempts} build attempts, "
                f"above its ${dollar_cap:.0f} cap; a reviewed cap increase is required")
    if tokens >= token_cap:
        return (f"this has used {tokens:,} model tokens, above its {token_cap:,} cap; "
                "review the result and set a bounded token cap before another model session")
    if fresh >= fresh_cap:
        return (f"this has used {fresh:,} fresh model tokens, above its {fresh_cap:,} cap; "
                "review the result and set a bounded fresh-token cap before another model session")
    return ""


def _parked_by_cost(item):
    return bool(item_capacity_reason(item))


def _parked_by_tree(item):
    """Pure check: a held patch overlaps an uncommitted file."""
    patch = load_patch(item["id"])
    if not patch:
        return False
    files = (item.get("diff") or {}).get("files") or _patch_paths(patch)
    return bool(_held_by_tree(files))


def apply_patch(patch, files):
    """Retired shared-checkout path. Never land a patch through this function."""
    raise RuntimeError("Shared-checkout patch application is retired; use prepare_integration.")


def run_suites(cwd=REPO):
    """Both headless suites, once, with private Godot user data."""
    out = {}
    for name, cmd in (
        ("unit", ["godot", "--headless", "--path", ".", "--script",
                  "res://tests/test_runner.gd"]),
        ("integration", ["godot", "--headless", "--path", ".",
                         "res://tools/test_runner.tscn"]),
    ):
        try:
            p = sh([sys.executable, "tools/run_godot_test.py", "--timeout", "840", "--"] + cmd,
                   cwd=cwd, timeout=900)
            tail = ((p.stdout or "") + (p.stderr or "")).strip().splitlines()[-6:]
            matches = re.findall(r"Results:\s*(\d+) PASSED,\s*(\d+) FAILED", p.stdout or "")
            out[name] = {"ok": p.returncode == 0 and bool(matches) and int(matches[-1][1]) == 0,
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


def git_blobs(repo, revision, files):
    """Exact Git blob and mode identities, including deletion and symlink changes."""
    result = {}
    for name in sorted(files):
        if revision:
            line = sh(["git", "ls-tree", revision, "--", name], cwd=repo, check=True).stdout.strip()
            result[name] = line.split("\t", 1)[0] if line else None
        else:
            path = os.path.join(repo, name)
            if not os.path.lexists(path):
                result[name] = None
                continue
            if os.path.islink(path):
                raw = os.readlink(path).encode()
                blob = subprocess.run(["git", "hash-object", "--stdin"], cwd=repo,
                                      input=raw, capture_output=True, check=True).stdout.decode().strip()
                mode = "120000"
            else:
                blob = sh(["git", "hash-object", "--", name], cwd=repo, check=True).stdout.strip()
                mode = "100755" if os.stat(path).st_mode & 0o111 else "100644"
            result[name] = mode + " blob " + blob
    return result


def committed_candidate(repo, sha, transaction):
    candidate = transaction["candidate"]
    files = transaction["files"]
    parents = sh(["git", "rev-list", "--parents", "-n", "1", sha], cwd=repo, check=True).stdout.split()
    if len(parents) != 2 or parents[1] != transaction["parent"]:
        return False
    paths = sh(["git", "diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd=repo, check=True).stdout.splitlines()
    committed_tree = sh(["git", "rev-parse", sha + "^{tree}"], cwd=repo, check=True).stdout.strip()
    return (committed_tree == candidate["tree"] and set(paths) == set(files)
            and git_blobs(repo, sha, files) == candidate["files"]
            and git_blobs(repo, parents[1], files) == candidate["base_files"])


def record_landed_integration(item, transaction, sha):
    """Persist local landing separately from a push or CI confirmation."""
    workflow = work._workflow(item)
    ident = work.evidence_id([transaction["attempt_id"], sha])
    if not any(row.get("id") == ident for row in workflow["integrations"]):
        workflow["integrations"].append({"id": ident, "attempt_id": transaction["attempt_id"],
                                          "candidate_tree": transaction["candidate"]["tree"],
                                          "parent": transaction["parent"], "commit": sha,
                                          "state": "landed_local", "at": work._now_iso(),
                                          "origin": integration.origin_tracking(server.REPO)})
    for action in workflow["actions"]:
        if action.get("state") != "done" and action.get("type") in ("reconcile", "recover", "handoff"):
            action["state"] = "done"
            action.pop("claim", None)
            action["finished_at"] = work._now_iso()
    for blocker in workflow["blockers"]:
        if blocker.get("state") == "open":
            blocker["state"] = "resolved"
            blocker["resolved_at"] = work._now_iso()


def recover_pending_landing(item):
    """Resolve a durable transaction from Git history without rerunning an agent."""
    tx = item.get("pending_landing")
    if not tx:
        return False
    found = sh(["git", "log", "--all", "--format=%H", "--fixed-strings", "--grep=HQ-Attempt: " + tx["attempt_id"]],
               cwd=server.REPO, check=True).stdout.splitlines()
    # A crash after detached commit but before the main ref update leaves the
    # commit reachable from this worktree's HEAD, not necessarily --all.
    checkout = tx.get("checkout")
    if checkout and os.path.isdir(checkout):
        got = sh(["git", "rev-parse", "HEAD"], cwd=checkout)
        if got.returncode == 0:
            found.append(got.stdout.strip())
    found = list(dict.fromkeys(found))
    matches = [sha for sha in found if ("HQ-Attempt: " + tx["attempt_id"]) in
               sh(["git", "show", "-s", "--format=%B", sha], cwd=server.REPO, check=True).stdout.splitlines()]
    exact_commit = len(matches) == 1 and committed_candidate(server.REPO, matches[0], tx)
    if tx.get("scope_id") != work.instruction_fingerprint(item):
        on_main = bool(exact_commit and sh(["git", "merge-base", "--is-ancestor", matches[0],
                                            "refs/heads/main"], cwd=server.REPO).returncode == 0)
        if on_main and tx.get("version") == 2 and integration.main_head(server.REPO) == matches[0] \
                and integration.main_checkout(server.REPO):
            if not integration.synchronize_main(server.REPO, matches[0], tx["parent"]):
                item["repair_hold"] = "Local main advanced, but its owner checkout needs safe synchronization."
                work.save_item(item)
                return False
        reason = "The instructions changed during the commit attempt; the owner must reassess it."
        item["repair_hold"] = reason
        item["landing_recovery"] = {**tx, "matches": matches,
                                    "exact_commit": bool(exact_commit), "on_main": on_main,
                                    "reason": reason}
        if on_main and tx.get("version") == 2:
            record_landed_integration(item, tx, matches[0])
        item.pop("pending_landing", None)
        work.save_item(item)
        if tx.get("version") == 2:
            record_integration_blocker(item, tx, "missing_evidence", reason)
        return False
    if exact_commit:
        head = integration.main_head(server.REPO)
        if tx.get("version") == 1 and sh(["git", "merge-base", "--is-ancestor",
                                           matches[0], "refs/heads/main"], cwd=server.REPO).returncode != 0:
            item["repair_hold"] = "The legacy commit is not local main; reconcile its exact files before closing this card."
            item["landing_recovery"] = {**tx, "reason": item["repair_hold"]}
            item.pop("pending_landing", None)
            work.save_item(item)
            return False
        if tx.get("version") == 2 and head == tx["parent"]:
            if not integration.advance_main(server.REPO, matches[0], tx["parent"]):
                head = integration.main_head(server.REPO)
            else:
                head = matches[0]
        if tx.get("version") == 2 and head == matches[0] and integration.main_checkout(server.REPO):
            if not integration.synchronize_main(server.REPO, matches[0], tx["parent"]):
                item["repair_hold"] = "Local main advanced, but its clean owner checkout needs safe synchronization."
                item["landing_recovery"] = {**tx, "reason": item["repair_hold"]}
                work.save_item(item)
                return False
        if tx.get("version") == 2 and head != matches[0]:
            item["repair_hold"] = "Local main moved before the checked commit could be recovered."
            item["landing_recovery"] = {**tx, "reason": item["repair_hold"]}
            item.pop("pending_landing", None)
            work.save_item(item)
            record_integration_blocker(item, tx, "stale_base", item["repair_hold"])
            return False
        item["attempt_outcome"]["landing_verified"] = True
        item["pending_landing"]["resolved"] = "committed"
        if tx.get("version") == 2:
            record_landed_integration(item, tx, matches[0])
        work.land_item(item, "drain-recovery", sha=matches[0])
        item.pop("pending_landing", None)
        work.save_item(item)
        if tx.get("version") == 2 and checkout and os.path.isdir(checkout):
            integration.remove_candidate(server.REPO, checkout, WORKTREES)
        return True
    item["state"] = "for_review"
    item["attempt_outcome"]["landing_verified"] = False
    if matches:
        reason = "The commit differs from the checked candidate; the owner must inspect it."
    else:
        head = integration.main_head(server.REPO)
        reason = ("The commit did not happen; the checked changes remain available for the operator."
                  if head == tx["parent"] else "Repository history changed before the commit could be recovered.")
    item["repair_hold"] = reason
    item["landing_recovery"] = {**tx, "matches": matches, "reason": reason}
    item.pop("pending_landing", None)
    work.save_item(item)
    if tx.get("version") == 2:
        record_integration_blocker(item, tx, "missing_evidence", reason)
    return True


def tree_evidence(files, repo=None):
    repo = repo or server.REPO
    values = []
    for name in sorted(files):
        path = os.path.join(repo, name)
        try:
            with open(path, "rb") as source:
                values.append([name, work.hashlib.sha256(source.read()).hexdigest()])
        except FileNotFoundError:
            values.append([name, None])
    return work.evidence_id(values)


def prospective_tree_intact(rec):
    """Recheck the whole tested tree, not just paths named by the patch."""
    checkout = rec.get("integration_checkout")
    candidate = rec.get("candidate") or {}
    files = list(rec.get("files") or [])
    if not checkout or not os.path.isdir(checkout) or not candidate.get("tree"):
        return False
    try:
        return (integration.main_head(server.REPO) == candidate.get("base") and
                sh(["git", "rev-parse", "HEAD"], cwd=checkout, check=True).stdout.strip() == candidate.get("base") and
                sh(["git", "diff", "--quiet"], cwd=checkout).returncode == 0 and
                sh(["git", "ls-files", "--others", "--exclude-standard"], cwd=checkout).stdout.strip() == "" and
                sh(["git", "write-tree"], cwd=checkout, check=True).stdout.strip() == candidate["tree"] and
                git_blobs(checkout, "", files) == candidate.get("files") and
                tree_evidence(files, repo=checkout) == rec.get("tree_evidence"))
    except (OSError, RuntimeError):
        return False


def meets_landing_bar(item, rec, applied, suites, *, repo=None):
    """Whether this finished card may go in without Daniel reading it, and if
    not, the sentence that says why (S-16, docs/QUEUE_TO_ZERO.md §4).

    All four have to hold, and none of them is the worker's own word for it:
    the work is revertable, the test suites ran green over exactly this diff,
    the chief of staff read the diff and found nothing, and nothing in the diff
    is of a kind that reverting would not undo."""
    repo = repo or server.REPO
    files = list(rec.get("files") or [])
    if rec.get("check_evidence") != check_evidence_id(rec):
        return False, "the check does not describe this result and diff"
    check = rec.get("check") or {}
    if check.get("read") is True and check.get("verdict") in ("concerns", "fail"):
        return False, ("the read of it raised something you should see" if check["verdict"] == "concerns"
                       else "the read of it says this should not go in as it stands")
    outcome = work.attempt_outcome(rec.get("result", ""), rec.get("error"), rec.get("limited"))
    if outcome["status"] != "complete":
        return False, outcome["reason"] or "the attempt did not finish"

    candidate = rec.get("candidate") or {}
    if not candidate.get("tree") or rec.get("candidate_unchanged") is not True:
        return False, "the checked candidate changed before verification finished"
    if rec.get("candidate_test_evidence") != work.evidence_id([candidate, rec.get("candidate_suites")]):
        return False, "the test record does not identify the checked candidate"
    if files:
        candidate_suites = rec.get("candidate_suites") or {}
        if any(not (candidate_suites.get(name) or {}).get("ok") for name in ("unit", "integration")):
            return False, "the checked candidate did not pass both test suites"
        if git_blobs(repo, "", files) != candidate.get("files"):
            return False, "the applied files differ from the checked candidate"
    tier = _checked_tier(item, rec)
    if tier == 0 and files:
        return False, "a reading unexpectedly changed files and needs its risk checked"
    if tier == 1 and not files:
        return False, "no change was produced for this build task"
    if tier not in (0, 1):
        return False, ("this needed your yes before it happened, so it needs your "
                       "answer now that it has")

    # A reading produces no diff, so there is nothing for the suites to run
    # over and nothing to land; everything else has to have been applied to
    # the tree and proved there.
    if not (tier == 0 and not files):
        if not applied:
            return False, "the change it wrote could not be applied to the repository"
        if rec.get("tree_evidence") != tree_evidence(files, repo=repo):
            return False, "the files changed after the tests ran"
        if rec.get("test_evidence") != work.evidence_id([rec.get("patch", ""), suites]):
            return False, "the tests do not describe this diff"
        if not isinstance(suites, dict) or not suites:
            return False, "the test suites were not run over it"
        red = sorted(name for name in set(suites) | {"unit", "integration"}
                     if not (suites.get(name) or {}).get("ok"))
        if red:
            return False, (f"the {' and '.join(red)} test suite"
                           f"{'s are' if len(red) > 1 else ' is'} failing with this change in")

    check = rec.get("check") or {}
    verdict = check.get("verdict")
    # A record saying nobody read the diff is not a clean read of it. The
    # check writes that down itself when its call does not come back, so this
    # asks the record rather than guessing from the words in it.
    if check.get("read") is not True:
        return False, "nobody read the change it made"
    if verdict == "pass" and check.get("complete") is True and not check.get("findings"):
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


def land(item, rec, *, repo=None):
    """Commit the exact checked prospective tree in a detached clean checkout.

    The drain lock supplies the single writer. A compare-and-swap of local
    main is the only publishing operation; origin/main is never pushed here.
    """
    files = [f for f in (rec.get("files") or []) if f]
    if not files:
        return "", "there was nothing to commit"
    if not repo or os.path.realpath(repo) == os.path.realpath(server.REPO):
        return "", "clean integration checkout is unavailable; the shared checkout is never a landing target"
    ready, reason = integration.handoff_status(server.REPO)
    if not ready:
        return "", reason
    parent = integration.main_head(server.REPO)
    candidate = rec["candidate"]
    if (parent != candidate.get("base")
            or sh(["git", "rev-parse", "HEAD"], cwd=repo).stdout.strip() != parent
            or git_blobs(repo, "", files) != candidate["files"]
            or git_blobs(repo, parent, files) != candidate["base_files"]):
        return "", "the repository changed after the candidate was checked"
    item["pending_landing"] = {"version": 2, "attempt_id": item["attempt_outcome"]["id"],
                               "parent": parent, "files": files, "candidate": candidate,
                               "scope_id": work.instruction_fingerprint(item), "checkout": repo}
    work.save_item(item)
    add = sh(["git", "add", "--"] + files, cwd=repo)
    if add.returncode != 0:
        return "", (add.stderr or add.stdout or "git add failed").strip()[:200]
    if sh(["git", "write-tree"], cwd=repo).stdout.strip() != candidate["tree"]:
        return "", "the staged prospective tree differs from the reviewed candidate"
    made = sh(["git", "commit", "-m", item["title"], "-m", "HQ-Attempt: " + item["attempt_outcome"]["id"], "--"] + files, cwd=repo)
    if made.returncode != 0:
        return "", (made.stderr or made.stdout or "git commit failed").strip()[:200]
    got = sh(["git", "rev-parse", "HEAD"], cwd=repo)
    sha = got.stdout.strip()
    if not committed_candidate(server.REPO, sha, item["pending_landing"]):
        return "", "the committed files differ from the checked candidate"
    if not integration.advance_main(server.REPO, sha, parent):
        return "", "local main moved after verification; the candidate needs a new base"
    return sha, ""


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
    with work.mutation_lock():
        current = work.load_item(item["id"]) if os.path.exists(work._item_path(item["id"])) else {}
        if current.get("_revision", 0) != item.get("_revision", 0):
            raise work.RecordConflict(item["id"], item.get("_revision", 0), current.get("_revision", 0))
        return _write_back(item, rec, applied, why_not, suites, org)


def record_landing_verdict(item, rec, landed_ok, why_not_landed, suites):
    """Make a failed prospective gate a held candidate, never an applied patch."""
    if not landed_ok and suites:
        failing = [name for name in ("unit", "integration")
                   if not (suites.get(name) or {}).get("ok")]
        if failing:
            detail = ""
            for name in failing:
                tail = str((suites.get(name) or {}).get("tail") or "")
                match = re.search(r"FAIL:\s*([^\n]+)", tail)
                if match:
                    detail = f"{name}: {match.group(1).strip()}"
                    break
                if "Parse Error:" in tail:
                    detail = f"{name}: script parse error"
                    break
            why_not_landed = ("The prospective " + ", ".join(failing) +
                              " suite failed" + (f" at {detail}" if detail else "") + ".")
    item["attempt_outcome"]["landing_verified"] = landed_ok
    # Preparing a detached prospective tree is not applying the patch to main.
    # A held candidate must remain resumable from its recorded patch.
    item["diff"]["applied"] = bool(landed_ok and rec.get("files"))
    item["diff"]["why_not_landed"] = why_not_landed
    if (not landed_ok and suites and (rec.get("check") or {}).get("verdict") == "pass" and
            any(not (suites.get(name) or {}).get("ok")
                for name in ("unit", "integration"))):
        item["repair_hold"] = (why_not_landed + " The owner must diagnose the failure "
                               "against current main before this candidate can land.")
    return why_not_landed


def _write_back(item, rec, applied, why_not, suites, org):
    """The attempt onto the card. Almost always that means `for_review`, with
    whatever came back. The exception is a worker that ran out of turns with
    edits in hand (auto_resume_reason): the card goes back into the queue
    with the held patch as the next attempt's base and twice the standing
    turn budget, because a budget the drain set wrong is the drain's to fix,
    not Daniel's to judge. Either way the attempt is counted and billed."""
    if item.get("pending_landing"):
        recover_pending_landing(item)
        return item
    if rec.get("attempt_id") and item.get("last_recorded_attempt") == rec["attempt_id"]:
        if item.get("completion"):
            work.land_item(item, "drain", sha=item["completion"].get("sha", ""))
        return item
    visible_result, owner_notes = server.parse_remembered(rec["result"])
    body, follows, _amend, recommend, _move = work._split_result(visible_result, org, item["owner"])
    deliverable = work.result_deliverable(visible_result)
    # do_item decides this before the patch is held; a record that skipped
    # do_item gets the same answer here. Edits that landed are never retried.
    resume = "" if applied or item.get("automatic_repairs") else (rec.get("resume") or auto_resume_reason(item, rec))
    previous_check = item.get("check") or {}
    previous_id = previous_check.get("attempt_id") or (item.get("attempt_outcome") or {}).get("id")
    if previous_check and previous_id and previous_id != rec.get("attempt_id"):
        prior = item.setdefault("prior_checks", [])
        if not any(row.get("attempt_id") == previous_id for row in prior):
            prior.append({**previous_check, "attempt_id": previous_id})
    item["last_recorded_attempt"] = rec.get("attempt_id")
    item["attempts"] = item.get("attempts", 0) + 1
    item["done_by"] = {"seat": rec["seat"], "model": rec["model"], "lane": "drain"}
    # Whether this goes in on its own or comes to Daniel. Work he would only
    # rubber-stamp is work he should never have been shown, so the default is
    # that it lands; what sends it to him is a named reason, written on the card
    # so the next person can see which of the four things stopped it.
    integration_repo = rec.get("integration_checkout")
    landed_ok, why_not_landed = meets_landing_bar(
        item, rec, applied, suites, repo=integration_repo)
    if landed_ok and rec.get("files") and not integration_repo:
        landed_ok, why_not_landed = False, "clean integration checkout is unavailable"
    sha = ""
    item["diff"] = {"stat": rec["stat"], "files": rec["files"][:40],
                    "applied": applied, "why_not": why_not,
                    "why_not_landed": why_not_landed}

    item.pop("check", None)
    item.pop("completion", None)
    item.pop("repair_hold", None)
    checker_lesson = None
    if rec["check"]:
        item["check"] = {key: value for key, value in rec["check"].items()
                         if key != "lesson_for_owner"}
        checker_lesson = rec["check"].get("lesson_for_owner")
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
    item["attempt_outcome"] = work.attempt_outcome(visible_result, rec.get("error"), rec.get("limited"))
    item["attempt_outcome"].update({"id": rec.get("attempt_id") or work.evidence_id([item["id"], item["attempts"], rec["result"]]),
                                    "landing_verified": landed_ok,
                                    "patch_id": work.evidence_id(rec.get("patch", "")),
                                    "check_evidence": rec.get("check_evidence"),
                                    "test_evidence": rec.get("test_evidence"),
                                    "tree_evidence": rec.get("tree_evidence"),
                                    "candidate": rec.get("candidate"),
                                    "candidate_tests": rec.get("candidate_suites"),
                                    "candidate_test_evidence": rec.get("candidate_test_evidence")})
    if rec.get("patch_artifact") and rec.get("candidate"):
        workflow = work._workflow(item)
        ident = work.evidence_id([rec["patch_artifact"]["id"], rec["candidate"]])
        if not any(c.get("id") == ident for c in workflow["candidates"]):
            workflow["candidates"].append({"id": ident, "attempt_id": item["attempt_outcome"]["id"],
                                            "base": rec["candidate"].get("base"),
                                            "tree": rec["candidate"].get("tree"),
                                            "files": list(rec.get("files") or []),
                                            "patch": rec["patch_artifact"]})
    if item.get("check"):
        item["check"]["attempt_id"] = item["attempt_outcome"]["id"]
    proposals = [{"source": "owner", "text": note} for note in owner_notes]
    if isinstance(checker_lesson, dict) and checker_lesson.get("text"):
        proposals.append({"source": "checker", "text": checker_lesson["text"]})
    work.replace_owner_memory(item, item["attempt_outcome"]["id"], proposals)
    if landed_ok and (rec.get("files") or []):
        sha, trouble = land(item, rec, repo=integration_repo)
        if not sha:
            landed_ok, why_not_landed = False, trouble
    why_not_landed = record_landing_verdict(item, rec, landed_ok, why_not_landed, suites)
    if landed_ok:
        if sha and item.get("pending_landing", {}).get("version") == 2:
            record_landed_integration(item, item["pending_landing"], sha)
        work.land_item(item, "drain", sha=sha)
        item.pop("pending_landing", None)
    else:
        item["state"] = "for_review"
    item["finished"] = work._now_iso()
    work.finish_revision(item)
    if not landed_ok:
        work.queue_one_repair(item)
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
    out, _held = classified_queue(include_thinking)
    return out


def project_work(item, *, head=None, active=None, now=None):
    """Resolve external facts once, then use the pure work projection."""
    if head is None:
        got = sh(["git", "rev-parse", "main"], cwd=REPO, timeout=10)
        head = got.stdout.strip() if got.returncode == 0 else ""
    if active is None:
        active = server.drain_state()
    patch = load_patch(item["id"]) if not (item.get("diff") or {}).get("applied") else ""
    files = (item.get("diff") or {}).get("files") or _patch_paths(patch)
    # Dirty bytes in a separate user branch are not part of prospective main.
    # Before the handoff they do block the old shared checkout; afterward the
    # integration lane never writes that checkout and must not inherit its hold.
    main_holder = integration.main_checkout(REPO)
    blocked = _held_by_tree(files) if patch and main_holder and \
        os.path.realpath(main_holder) == os.path.realpath(REPO) else []
    cost_reason = (item_capacity_reason(item) if item.get("state") in
                   ("waiting_session", "for_review") else "")
    waiting = item.get("waiting_for") or {}
    waiting_valid = not ((waiting.get("files") and not blocked) or
                         ("spent_usd" in waiting and not cost_reason))
    return work.work_view(item, {"blocked_files": blocked, "tree_reason": _tree_reason(blocked) if blocked else "",
                                 "cost_reason": cost_reason, "active_session":
                                 (active or {}).get("run") if (active or {}).get("item") == item["id"] else None,
                                 "head": head, "waiting_for_valid": waiting_valid,
                                 "supervised_retry": item["id"] in RETRY_ONCE_IDS}, now=now)


def _queue_entries(include_thinking=False):
    """The only eligibility calculation used by scheduling and every queue read."""
    got = work.items()
    head_result = sh(["git", "rev-parse", "main"], cwd=REPO, timeout=10)
    head = head_result.stdout.strip() if head_result.returncode == 0 else ""
    active = server.drain_state()
    now = time.time()
    entries = []
    for item in got:
        if item.get("state") in work.TERMINAL_STATES:
            continue
        if item.get("state") not in ("waiting_session", "for_review") and not (
                include_thinking and item.get("state") == "doing"):
            continue
        view = project_work(item, head=head, active=active, now=now)
        action = view["next_action"]
        if action and action.get("type") != "decide":
            entries.append((item, view, action))
    rank = {"urgent": 0, "reconciliation": 1, "retry": 2, "ordinary": 3}
    entries.sort(key=lambda entry: (rank.get(entry[2].get("priority"), 3),
                                    _as_created(entry[0]), entry[0]["id"]))
    return entries


def _as_created(item):
    try:
        return float(item.get("created_ts") or 0)
    except (TypeError, ValueError):
        return 0.0


def classified_actions(include_thinking=False):
    """All runnable studio actions, including recovery, with their work item."""
    return [(item, action) for item, _view, action in _queue_entries(include_thinking)
            if action["availability"] == "runnable"]


def classified_queue(include_thinking=False):
    """Legacy build-worker selector over the canonical action projection."""
    out, held = [], []
    for item, view, action in _queue_entries(include_thinking):
        if item.get("state") not in ("waiting_session", "doing"):
            continue
        if action["type"] == "build" and action["availability"] == "runnable" and not item.get("started"):
            out.append(item)
        elif view["blocker"] or action["availability"] == "blocked":
            held.append((item, (view["blocker"] or {}).get("reason") or action.get("summary") or "held"))
    return out, held


def queue_view():
    """Action rows and held outcomes from the scheduler's one projection."""
    working, eligible, held = [], [], []
    for item, view, action in _queue_entries():
        base = {"id": action["id"] if action["type"] != "build" else item["id"],
                "work_id": item["id"], "title": item.get("title", "Untitled"),
                "owner": action["owner"], "created": item.get("created", ""),
                "action_id": action["id"], "action_type": action["type"],
                "priority": action.get("priority"), "why": action.get("priority_reason"),
                "age_seconds": action.get("age_seconds"), "workflow_view": view}
        if action["availability"] == "running":
            working.append({**base, "position": None, "reason": ""})
        elif action["availability"] == "runnable":
            eligible.append({**base, "position": len(eligible) + 1, "reason": ""})
        else:
            held.append({**base, "id": item["id"], "position": None,
                         "reason": (view["blocker"] or {}).get("reason") or action.get("summary") or "held"})
        # A blocked implementation and its runnable reconciliation are two
        # distinct actions. Show both without offering the old build again.
        if view["blocker"] and action["type"] in ("reconcile", "recover", "rebrief") and action["availability"] == "runnable":
            held.append({**base, "id": item["id"], "action_id": work.action_key(item["id"], "build", action.get("input_id", "")),
                         "action_type": "build", "position": None,
                         "reason": view["blocker"]["reason"]})
    return {"working": working, "eligible": eligible, "held": held}


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


def prepare_integration(rec):
    """Reconstruct the reviewed candidate on local main, without user-tree writes.

    A changed base is not automatically rebased: that would produce a new tree
    whose old checker verdict and candidate tests do not describe it.
    """
    candidate = rec.get("candidate") or {}
    try:
        patch = checked_patch(rec)
    except (ValueError, OSError) as exc:
        return "", "missing_evidence", str(exc)
    parent = integration.main_head(server.REPO)
    if candidate.get("base") != parent:
        return "", "stale_base", "Local main changed; obtain a new candidate, review, and tests."
    try:
        tree = integration.candidate_checkout(server.REPO, WORKTREES,
                                              rec.get("attempt_id") or "", parent)
    except (RuntimeError, ValueError) as exc:
        return "", "tooling", str(exc)
    applied = subprocess.run(["git", "apply", "--check"], cwd=tree,
                             input=patch, capture_output=True,
                             text=True, timeout=180)
    if applied.returncode:
        return tree, "code_conflict", (applied.stderr or applied.stdout or
                                        "The reviewed patch no longer applies to local main.").strip()[:500]
    applied = subprocess.run(["git", "apply"], cwd=tree,
                             input=patch, capture_output=True,
                             text=True, timeout=180)
    if applied.returncode:
        return tree, "code_conflict", (applied.stderr or applied.stdout or
                                        "The reviewed patch could not be applied.").strip()[:500]
    files = list(rec.get("files") or [])
    staged = sh(["git", "add", "--"] + files, cwd=tree)
    if staged.returncode:
        return tree, "missing_evidence", (staged.stderr or staged.stdout or
                                           "The candidate paths could not be staged.").strip()[:500]
    actual_tree = sh(["git", "write-tree"], cwd=tree).stdout.strip()
    actual_files = set(sh(["git", "diff", "--cached", "--name-only"], cwd=tree).stdout.splitlines())
    if actual_tree != candidate.get("tree") or actual_files != set(files):
        return tree, "missing_evidence", "The reconstructed tree differs from the reviewed candidate."
    if git_blobs(tree, "", files) != candidate.get("files"):
        return tree, "missing_evidence", "The reconstructed file blobs differ from the reviewed candidate."
    return tree, "", ""


def record_integration_blocker(item, rec, kind, reason):
    """One owned recovery action per immutable candidate, never a blind retry."""
    candidate = rec.get("candidate") or {}
    input_id = work.evidence_id([rec.get("attempt_id"), candidate.get("base"),
                                 candidate.get("tree"), rec.get("patch_artifact")])
    action = work.ensure_action(item, "reconcile", input_id=input_id,
                                owner=item.get("owner") or "claude",
                                summary="Rebuild this candidate on current main, then obtain fresh review and both suites.",
                                priority="reconciliation")
    work.ensure_blocker(item, kind, input_id=input_id,
                        owner=item.get("owner") or "claude", reason=reason,
                        files=rec.get("files") or [], action_id=action["id"])
    with work.mutation_lock():
        fresh = work.load_item(item["id"])
        changed = False
        for older in work._workflow(fresh)["actions"]:
            if (older.get("id") != action["id"] and older.get("type") == "reconcile"
                    and older.get("state") == "open"):
                older["state"], older["finished_at"] = "done", work._now_iso()
                changed = True
        for older in work._workflow(fresh)["blockers"]:
            if older.get("action_id") != action["id"] and older.get("state") == "open":
                older["state"], older["resolved_at"] = "resolved", work._now_iso()
                changed = True
        if changed:
            work.save_item(fresh)
        item.clear(); item.update(fresh)


def record_handoff_blocker(item, reason):
    """A process action, not another costly owner build attempt."""
    action = work.ensure_action(item, "handoff", input_id=integration.main_head(server.REPO),
                                owner="claude", priority="reconciliation",
                                summary="Confirm the checkout is idle and transfer its dirty files to a named branch.")
    work.ensure_blocker(item, "tooling", input_id=action["input_id"], owner="claude",
                        reason=reason, action_id=action["id"],
                        wake="The primary checkout is confirmed idle.")


def resolve_handoff_action(item):
    with work.mutation_lock():
        fresh = work.load_item(item["id"])
        workflow = fresh.get("workflow") or {}
        handoffs = set()
        changed = False
        for action in workflow.get("actions") or []:
            if action.get("type") == "handoff" and action.get("state") == "open":
                action["state"], action["finished_at"] = "done", work._now_iso()
                handoffs.add(action["id"])
                changed = True
        for blocker in workflow.get("blockers") or []:
            if blocker.get("action_id") in handoffs and blocker.get("state") == "open":
                blocker["state"], blocker["resolved_at"] = "resolved", work._now_iso()
                changed = True
        if changed:
            work.save_item(fresh)
        item.clear(); item.update(fresh)


def run_verified_batch(pool, org, run_id, log, *, no_suites=False, actions=None):
    """Finish one candidate before creating the next, retaining exact parent identity."""
    records, done = {}, []
    for selected in pool:
        item = work.load_item(selected["id"])
        action = (actions or {}).get(item["id"])
        claim_id = ""
        if action:
            claim_id = action_dispatch.claim(work, item, action, run_id)
            if not claim_id:
                records[item["id"]] = {"id": item["id"], "held": True,
                                       "error": "Action was already claimed", "usage": [],
                                       "check": None, "applied": False}
                continue
            if action["type"] == "recover":
                progressed = bool(item.get("pending_landing") and recover_pending_landing(item))
                action_dispatch.finish(work, item, action, claim_id,
                                       progressed=progressed,
                                       reason="No recoverable landing transaction remains.")
                records[item["id"]] = {"id": item["id"], "usage": [], "check": None,
                                       "applied": progressed}
                if progressed:
                    done.append(work.load_item(item["id"]))
                continue
        if int(item.get("tier") or 0) >= 1:
            ready, reason = integration.handoff_status(server.REPO)
            if not ready:
                rec = {"id": item["id"], "held": True, "error": reason,
                       "usage": [], "check": None, "applied": False}
                records[item["id"]] = rec
                record_handoff_blocker(item, reason)
                if claim_id:
                    action_dispatch.finish(work, item, action, claim_id,
                                           progressed=False, reason=reason)
                continue
            resolve_handoff_action(item)
        record_phase(run_id, item, "starting", "The task queue is preparing its isolated checkout.")
        source = (held_recheck_source(item) if action and action.get("type") == "reconcile"
                  else None)
        if source:
            rec = recheck_held_candidate(item, org, run_id, source)
        elif (item["id"] in FINISH_VERIFIED_IDS or action and action.get("type") == "reconcile") \
                and (previous := verified_landing_source(item)):
            rec = resume_verified_landing(item, run_id, previous)
        elif item["id"] in FINISH_VERIFIED_IDS:
            rec = {"id": item["id"], "held": True, "error": "The verified landing source changed before retry.",
                   "usage": [], "check": None, "applied": False}
        else:
            rec = do_item(item, org, run_id, log, action=action) if action else \
                do_item(item, org, run_id, log)
        records[item["id"]] = rec
        if rec.get("held") or rec.get("limited"):
            if claim_id:
                action_dispatch.finish(work, item, action, claim_id,
                                       progressed=False,
                                       reason=rec.get("error") or "The owner session did not finish.")
            elif rec.get("tooling_hold"):
                work.ensure_blocker(item, "tooling", input_id=rec["attempt_id"],
                                    owner="claude", reason=rec["error"],
                                    wake="Inspect the failed Godot import before retrying this build.")
            continue
        ok, why = False, "the check said it should not land as it stands"
        blocker_kind = ""
        integration_repo = ""
        fresh = work.load_item(item["id"])
        if fresh.get("_revision", 0) != item.get("_revision", 0):
            rec["held"], rec["error"] = True, "the work card changed during execution; the result needs reassessment"
            continue
        candidate = rec.get("candidate") or {}
        head = integration.main_head(server.REPO)
        if candidate and candidate.get("base") != head:
            why = "the candidate is stale; repository history changed before application"
            blocker_kind = "stale_base"
        elif rec.get("resume"):
            why = "held for another attempt — " + rec["resume"]
        elif not rec.get("patch", "").strip():
            why = rec.get("error") or "nothing changed"
        elif (not rec.get("error") and work.attempt_outcome(rec["result"])["status"] == "complete"
              and (rec.get("check") or {}).get("verdict") == "pass"
              and (rec.get("check") or {}).get("complete") is True
              and not (rec.get("check") or {}).get("findings")
              and rec.get("candidate_unchanged") is True):
            record_phase(run_id, item, "applying", "The reviewed change is being prepared on local main.")
            integration_repo, blocker_kind, why = prepare_integration(rec)
            ok = not blocker_kind
            if ok:
                rec["integration_checkout"] = integration_repo
        rec["applied"], rec["why_not"] = ok, "" if ok else why
        checkpoint(item, rec, "applied" if ok else "reviewed")
        suites = None
        if ok and not no_suites:
            rec["tree_evidence"] = tree_evidence(rec["files"], repo=integration_repo)
            record_phase(run_id, item, "verifying", "The exact prospective main tree is running both game test suites.")
            try:
                if touches_game(rec.get("files") or []):
                    preflight_godot_import(integration_repo)
                suites = run_suites(cwd=integration_repo)
                rec["suites"] = suites
                restore_test_generated(integration_repo, rec["candidate"]["tree"])
                # A test or hook that changed tracked files invalidates the tested
                # tree, even if the named candidate files still happen to match.
                if not prospective_tree_intact(rec):
                    ok, blocker_kind = False, "missing_evidence"
                    why = "The prospective tree changed while its tests ran."
                    rec["applied"], rec["why_not"] = False, why
            except GodotImportHold as exc:
                ok, blocker_kind, why = False, "tooling", str(exc)
                rec["applied"], rec["why_not"] = False, why
            checkpoint(item, rec, "verified")
        rec["test_evidence"] = work.evidence_id([rec.get("patch", ""), suites])
        fresh = work.load_item(item["id"])
        if fresh.get("_revision", 0) != item.get("_revision", 0):
            rec["held"], rec["error"] = True, "the work card changed during validation; reassessment is required"
            if integration_repo:
                integration.remove_candidate(server.REPO, integration_repo, WORKTREES)
            continue
        try:
            record_phase(run_id, item, "recording", "The result and its evidence are being recorded.")
            done.append(write_back(fresh, rec, ok, rec["why_not"], suites, org))
            checkpoint(item, rec, "written_back")
            if blocker_kind:
                record_integration_blocker(done[-1], rec, blocker_kind, why)
            elif done[-1].get("state") != "landed" and rec.get("files") and ok:
                record_integration_blocker(done[-1], rec, "missing_evidence",
                                           (done[-1].get("diff") or {}).get("why_not_landed") or
                                           "The candidate needs new landing evidence.")
            if integration_repo and os.path.isdir(integration_repo) and not done[-1].get("pending_landing"):
                integration.remove_candidate(server.REPO, integration_repo, WORKTREES)
        except work.RecordConflict:
            rec["held"], rec["error"] = True, "the work card changed before completion was saved; reassessment is required"
            if integration_repo and not work.load_item(item["id"]).get("pending_landing"):
                integration.remove_candidate(server.REPO, integration_repo, WORKTREES)
            continue
        if claim_id:
            action_dispatch.finish(work, item, action, claim_id,
                                   progressed=True)
        log(f"finished {item['id']} · {done[-1]['state']}")
    return records, done


def recover_interrupted_transactions(org):
    """Finish bookkeeping from a dead drain without rerunning a model.

    A live drain owns its transaction. Once its PID is gone, the checkpoint is
    the newest durable evidence and may safely repair the card exactly once.
    """
    recovered = 0
    if not os.path.isdir(TRANSACTIONS):
        return recovered
    for run in sorted(os.listdir(TRANSACTIONS)):
        directory = os.path.join(TRANSACTIONS, run)
        if not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            if not name.endswith(".json"):
                continue
            path = os.path.join(directory, name)
            try:
                with open(path, encoding="utf-8") as source:
                    tx = json.load(source)
            except (OSError, ValueError):
                continue
            if tx.get("phase") in ("written_back", "abandoned"):
                continue
            try:
                pid = int(tx.get("pid") or 0)
                if pid > 0:
                    os.kill(pid, 0)
                    continue
            except (OSError, TypeError, ValueError):
                pass
            rec = tx.get("record") or {}
            item_id = tx.get("item") or ""
            try:
                item = work.load_item(item_id)
            except Exception:
                continue
            if item.get("last_recorded_attempt") == rec.get("attempt_id"):
                tx["phase"] = "written_back"
            elif (tx.get("version", 0) < 2 or
                  tx.get("scope_id") != work.instruction_fingerprint(item) or
                  tx.get("item_revision") != item.get("_revision", 0)):
                tx["phase"] = "abandoned"
                tx["abandon_reason"] = "The work card changed since this transaction's checkpoint."
            elif rec.get("check"):
                rec.setdefault("applied", False)
                rec.setdefault("why_not", "the build session stopped before recording its review")
                if rec["applied"] and not prospective_tree_intact(rec):
                    rec["applied"] = False
                    rec["why_not"] = "The prospective tree changed after verification; new evidence is required."
                try:
                    finished = write_back(item, rec, bool(rec["applied"]), rec["why_not"],
                                          rec.get("suites"), org)
                    if rec.get("files") and finished.get("state") != "landed":
                        record_integration_blocker(finished, rec, "missing_evidence",
                                                   (finished.get("diff") or {}).get("why_not_landed") or
                                                   "Interrupted verification needs a new checked candidate.")
                    tx["phase"] = "written_back"
                    recovered += 1
                except work.RecordConflict:
                    continue
            else:
                # There is no reviewed result to publish. Make the existing
                # card honest and let its normal queue retry the work.
                if item.get("started"):
                    item["started"] = ""
                    if item.get("state") == "doing":
                        item["state"] = "waiting_session"
                    work.save_item(item)
                tx["phase"] = "interrupted"
            tx["at"] = work._now_iso()
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as target:
                json.dump(tx, target)
            os.replace(tmp, path)
    return recovered


def main():
    ap = argparse.ArgumentParser(description="Drain HQ's build-session queue.")
    ap.add_argument("ids", nargs="*", help="work item ids; default is every queued item")
    ap.add_argument("--all", action="store_true", help="every queued item")
    ap.add_argument("--thinking", action="store_true",
                    help="also run tier-0 items (analysis and drafting, read-only)")
    ap.add_argument("--limit", type=int, default=0, help="stop after N items")
    ap.add_argument("--jobs", type=int, default=3, help="retained for compatibility; verified items run sequentially")
    ap.add_argument("--list", action="store_true", help="what is queued, and nothing else")
    ap.add_argument("--list-json", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--brief", metavar="ID",
                    help="print the brief the next attempt at this item would be given, "
                         "and run nothing")
    ap.add_argument("--dry-run", action="store_true", help="say what would run")
    ap.add_argument("--apply", action="store_true",
                    help="retired: unsafe shared-checkout patch application is refused")
    ap.add_argument("--repair", action="store_true",
                    help="rewrite any card whose result is a raw CLI envelope, and nothing else")
    ap.add_argument("--recover-only", action="store_true",
                    help="record interrupted attempts from durable checkpoints and run no work")
    ap.add_argument("--no-suites", action="store_true", help="skip the suites (they run by default "
                                                            "when a patch touches the game)")
    ap.add_argument("--unattended", action="store_true",
                    help=f"the timer's shape: --all, at most {UNATTENDED_LIMIT} items, "
                         f"{UNATTENDED_JOBS} seats, and nothing at all when the token window "
                         "is dry or mostly spent")
    ap.add_argument("--retry-once", metavar="ID",
                    help="run one supervised retry of the nominated trial card's exhausted repair")
    ap.add_argument("--finish-verified", metavar="ID",
                    help="retry only the already reviewed local-main test gate; no model sessions")
    args = ap.parse_args()

    if args.apply:
        print("--apply is retired: it writes into the shared checkout. Use the clean integration lane and a reviewed reconciliation action.")
        return 2

    if args.retry_once:
        policy = execution.load_policy()
        if (args.unattended or args.all or args.ids or args.repair or args.recover_only or args.brief
                or args.no_suites
                or args.limit not in (0, 1)
                or not policy["background_paused"] or args.retry_once != policy["trial_item"]):
            print("--retry-once requires the single nominated trial card while background work is paused.")
            return 2
        args.ids = [args.retry_once]
        RETRY_ONCE_IDS.add(args.retry_once)
    if args.finish_verified:
        policy = execution.load_policy()
        if (args.retry_once or args.unattended or args.all or args.ids or args.repair or
                args.recover_only or args.brief or args.no_suites or args.thinking or
                args.limit not in (0, 1) or not policy["background_paused"] or
                args.finish_verified != policy["trial_item"]):
            print("--finish-verified requires the nominated paused trial card and both suites.")
            return 2

    work.bind(server, sanitize=not (args.list or args.list_json or args.dry_run or args.brief))
    if args.retry_once:
        trial = next((item for item in work.items() if item["id"] == args.retry_once), None)
        if not trial or not trial.get("repair_hold") or trial.get("automatic_repairs", 0) < 1:
            RETRY_ONCE_IDS.clear()
            print("--retry-once requires a nominated trial card with an exhausted repair hold.")
            return 2
    org = server.load_org()
    # Recovery is local bookkeeping and must run even while models are paused.
    if not (args.list or args.list_json or args.dry_run or args.brief):
        work.recover_completion_work()

    if args.unattended:
        args.all = True
        args.limit = args.limit or UNATTENDED_LIMIT
        args.jobs = min(args.jobs, UNATTENDED_JOBS)
        hold = unattended_hold()
        if hold:
            print(f"Not draining: {hold}.")
            return 0

    lock = None
    if not (args.list or args.list_json or args.dry_run):
        lock = take_lock()
        if lock is None:
            print("Another drain is running; not starting a second one.")
            return 0

    recovered = recover_interrupted_transactions(org) if lock else 0
    if lock:
        recovered += action_dispatch.recover_orphaned_claims(work)
    if args.recover_only:
        print(f"Recovered {recovered} interrupted attempt(s).")
        return 0
    if lock:
        action_dispatch.poll_ci(work, work.items(), action_dispatch.fetch_tests_runs)

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

    if args.list_json:
        print(json.dumps(queue_view()))
        return 0

    if args.finish_verified:
        trial = work.load_item(args.finish_verified)
        if not verified_landing_source(trial):
            print("No unchanged, reviewed patch with an import-only failed landing gate remains.")
            return 2
        FINISH_VERIFIED_IDS.add(trial["id"])
        selected_actions = [(trial, None)]
    else:
        selected_actions = action_dispatch.choose(
            sys.modules[__name__], include_thinking=args.thinking,
            ids=args.ids, limit=args.limit)
    RETRY_ONCE_IDS.clear()
    if args.retry_once and (len(selected_actions) != 1 or selected_actions[0][1]["type"] != "reconcile"):
        print("The nominated trial card has no runnable reconciliation action.")
        return 2
    pool = [item for item, _action in selected_actions]
    action_map = {item["id"]: action for item, action in selected_actions}
    if args.ids:
        want = set(args.ids)
        pool = [i for i in pool if i["id"] in want]
        missing = want - {i["id"] for i in pool}
        if missing:
            print(f"not queued: {', '.join(sorted(missing))}")
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
    if not args.finish_verified:
        pool = [i for i in pool if execution.launch_allowed(launch_context=_launch_context(i["id"]), item=i["id"], phase="build-worker")]
    if not pool:
        print("Automatic work is paused; no permitted items selected.")
        return 0

    run_id = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:4]
    _set_run(run_id)
    started = time.time()
    print(f"Draining {len(pool)} item(s), one verified item at a time. Run {run_id}.\n", flush=True)

    def log(msg):
        print(f"  [{time.strftime('%H:%M:%S')}] {msg}", flush=True)

    records, done = run_verified_batch(pool, org, run_id, log,
                                       no_suites=args.no_suites, actions=action_map)
    record_phase(run_id, None, "finished", "The selected batch finished.")
    shutil.rmtree(os.path.join(WORKTREES, run_id), ignore_errors=True)

    bill = server.sum_usage([u for r in records.values() for u in r["usage"]])
    esc = [(i, records[i["id"]]["check"]) for i in pool
           if (records.get(i["id"]) or {}).get("check")
           and records[i["id"]]["check"].get("escalates")]
    went_in = [i for i in done if i.get("state") == "landed"]
    print(f"\nDrained in {int(time.time() - started) // 60} min. "
          f"{sum(1 for r in records.values() if r.get('applied'))} of {len(pool)} prepared "
          f"on a clean prospective tree; {len(went_in)} committed to local main, "
          f"{sum(1 for i in done if i.get('state') == 'for_review')} held for review or recovery.")
    for i in done:
        if i.get("state") == "for_review":
            print(f"  held: {i['id']}  {(i.get('diff') or {}).get('why_not_landed') or '—'}")
    print(f"Cost: {bill['calls']} model calls, {bill['tokens']:,} tokens "
          f"({cost_summary(bill)}).")
    if esc:
        print("\nEscalated to Daniel:")
        for it, ch in esc:
            print(f"  {it['id']} [{ch['escalation_reason'] or 'unstated'}] {ch['escalates']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

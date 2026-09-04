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

    python3 hq/drain.py --list
    python3 hq/drain.py --dry-run
    python3 hq/drain.py --all --jobs 3
    python3 hq/drain.py w5a4005536e1 wc1886486f14

Every model call is priced into hq/data/history/tokens.jsonl and totalled onto
the item, because unattended work spends the allotment Daniel spends and he is
entitled to see what a result cost before he accepts it.
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import server                      # noqa: E402  (path set above)
import work                        # noqa: E402

WORKTREES = os.path.expanduser("~/.cache/tiny-farm-drain")
PATCHES = os.path.join(REPO, "hq", "data", "patches")
WORKER_TURNS = 60
WORKER_TIMEOUT = 3600
CHECK_TIMEOUT = 900
# Anything under these paths is the game rather than the office, so a patch that
# touches one has to face the suites before it is worth anybody reading.
GAME_PATHS = ("world/", "player/", "entities/", "systems/", "ui/", "effects/",
              "crops/", "tests/", "tools/", "assets/", "project.godot", "main.gd",
              "main.tscn")
WRITE_TOOLS = "Read,Glob,Grep,Edit,Write,MultiEdit,NotebookEdit,Bash,TodoWrite,WebFetch"
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
            "as the item is. Do not hand back the same work:\n\n" + "\n\n".join(out) + "\n")


def task_prompt(item, org):
    convo = work._convo_lines(item, org)
    said = (f"\n\nWHAT DANIEL HAS SAID ABOUT THIS ON THE CARD — the most recent word on it, "
            f"and it overrides the brief wherever they disagree:\n\n{convo}\n") if convo else ""
    return f"""WORK ITEM: {item['title']}

What Daniel asked for: {item.get('ask', '')}

The next step, which is yours to take now: {item.get('first_action', '')}
{said}{prior_checks(item)}
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


def check_prompt(item, result, diff):
    return f"""THE ITEM: {item['title']}
What Daniel asked for: {item.get('ask', '')}
The step that was theirs to take: {item.get('first_action', '')}
Who did it: {item['owner']}

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

def run_cli(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id):
    cmd = ["claude", "-p", prompt, "--append-system-prompt", system,
           "--allowedTools", tools, "--max-turns", str(turns),
           "--permission-mode", "acceptEdits", "--output-format", "json"]
    if model:
        cmd += ["--model", model]
    started = time.time()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout,
                           env={**os.environ, "CLAUDE_CODE_DISABLE_AUTOUPDATE": "1"})
    except subprocess.TimeoutExpired:
        return "", None, f"the {phase} call ran past {timeout // 60} minutes and was stopped"
    except Exception as e:
        return "", None, f"{type(e).__name__}: {e}"[:300]
    raw = (p.stdout or "").strip()
    doc = None
    try:
        doc = json.loads(raw)
    except ValueError:
        pass
    usage = server.usage_from_cli(doc) if isinstance(doc, dict) else None
    if usage:
        server.record_model_usage(phase, seat, model, usage, item_id)
    if p.returncode != 0:
        blob = raw + "\n" + (p.stderr or "")
        if server._looks_like_limit(blob):
            return "", usage, "LIMITED"
    if isinstance(doc, dict):
        text = str(doc.get("result") or "").strip()
        if p.returncode == 0 and not doc.get("is_error"):
            return text, usage, ""
        # A JSON envelope carries the reason; pasting the whole envelope into the
        # error is how a card ends up showing Daniel a wall of session ids.
        why = {"max_turns": f"it used all {turns} of its turns",
               "tool_use": f"it used all {turns} of its turns mid-edit",
               "refusal": "the model declined the task"}.get(
                   str(doc.get("stop_reason") or ""), "")
        return text, usage, (why or str(doc.get("subtype") or "the call did not "
                                        "finish cleanly"))[:300]
    if p.returncode != 0:
        return "", usage, (p.stderr or raw or "the CLI exited non-zero").strip()[:300]
    # No JSON came back: keep the reply, lose only the price.
    return raw, usage, "" if raw else "the CLI produced nothing"


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
    """Everything the worker changed, as one patch, including files it added."""
    sh(["git", "add", "-A"], cwd=path, timeout=120)
    p = sh(["git", "diff", "--cached", "--binary"], cwd=path, timeout=120)
    stat = sh(["git", "diff", "--cached", "--stat"], cwd=path, timeout=120).stdout.strip()
    files = [ln.split("\t")[-1] for ln in
             sh(["git", "diff", "--cached", "--name-only"], cwd=path,
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


def load_patch(item_id):
    try:
        with open(os.path.join(PATCHES, item_id + ".patch"), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def touches_game(files):
    return any(f.startswith(g) or f == g for f in files for g in GAME_PATHS)


# ---------------------------------------------------------------------------
# the phases
# ---------------------------------------------------------------------------

def do_item(item, org, run_id, log):
    """Worker then checker, both in the item's own worktree. Returns the record
    the session applies and writes back."""
    seat = item["owner"]
    model = item.get("model") or server.seat_model(org, seat)
    thinking = int(item.get("tier") or 0) == 0
    rec = {"id": item["id"], "seat": seat, "model": model, "usage": [],
           "patch": "", "stat": "", "files": [], "result": "", "check": None,
           "error": "", "limited": False}
    tree = None
    try:
        if thinking:                      # claim it before the server's worker can
            item["started"] = work._now_iso()
            work.save_item(item)
        tree = make_worktree(run_id, item["id"])
        log(f"{item['id']} · {seat} on {model or 'the default model'} · {item['title'][:60]}")
        text, usage, err = run_cli(task_prompt(item, org), seat_prompt(org, seat, thinking),
                                   READ_TOOLS if thinking else WRITE_TOOLS,
                                   model, tree, WORKER_TIMEOUT,
                                   WORKER_TURNS, "drain-work", seat, item["id"])
        if usage:
            rec["usage"].append(dict(usage, phase="drain-work", model=model, seat=seat))
        if err == "LIMITED":
            rec["limited"] = True
            return rec
        rec["result"] = text
        rec["error"] = err
        rec["patch"], rec["stat"], rec["files"] = worktree_patch(tree)
        save_patch(item["id"], rec["patch"])
        # The chief of staff reads the diff, on his own seat's model.
        cmodel = server.seat_model(org, "claude")
        ctext, cusage, cerr = run_cli(check_prompt(item, text, rec["patch"]), CHECK_SYSTEM,
                                      "Read,Glob,Grep", cmodel, tree, CHECK_TIMEOUT,
                                      8, "drain-check", "claude", item["id"])
        if cusage:
            rec["usage"].append(dict(cusage, phase="drain-check", model=cmodel, seat="claude"))
        if cerr == "LIMITED":
            rec["limited"] = True
        rec["check"] = parse_check(ctext) if ctext else None
        if rec["check"] is None and not rec["limited"]:
            rec["check"] = {"verdict": "concerns", "summary": "nobody checked this — the "
                            "check call did not come back", "findings": [], "escalates": None,
                            "escalation_reason": None}
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

def plain_failure(text, applied=None):
    """A card is something Daniel reads. A raw CLI envelope pasted into the
    result field — session ids, cache counters, a `duration_api_ms` — tells him
    nothing and buries the one fact that matters, which is that the attempt did
    not finish. Recognise it and say the fact instead."""
    raw = (text or "").strip()
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


def write_back(item, rec, applied, why_not, suites, org):
    body, follows, _amend, recommend = work._split_result(rec["result"], org, item["owner"])
    item["result"] = (plain_failure(body, applied)
                      or (f"This attempt did not finish — {rec['error']}." if rec["error"]
                          else "(no result came back)"))
    if follows is not None:
        item.pop("follow_up", None)
        item["follow_ups"] = follows
        item["recommend"] = recommend or {}
    item["state"] = "for_review"
    item["finished"] = work._now_iso()
    item["attempts"] = item.get("attempts", 0) + 1
    item["done_by"] = {"seat": rec["seat"], "model": rec["model"], "lane": "drain"}
    item["diff"] = {"stat": rec["stat"], "files": rec["files"][:40],
                    "applied": applied, "why_not": why_not}
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
    }
    work.save_item(item)
    return item


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def queued(include_thinking=False):
    """What the drain may pick up. Tier 1 always; tier 0 on request, and then it
    is claimed by stamping `started` — the HQ server runs its own tier-0 worker
    and skips anything already claimed, so the two never take the same item."""
    out = [i for i in work.items() if i.get("state") == "waiting_session"]
    if include_thinking:
        out += [i for i in work.items()
                if i.get("state") == "doing" and not i.get("started")]
    return out


def main():
    ap = argparse.ArgumentParser(description="Drain HQ's build-session queue.")
    ap.add_argument("ids", nargs="*", help="work item ids; default is every queued item")
    ap.add_argument("--all", action="store_true", help="every queued item")
    ap.add_argument("--thinking", action="store_true",
                    help="also run tier-0 items (analysis and drafting, read-only)")
    ap.add_argument("--limit", type=int, default=0, help="stop after N items")
    ap.add_argument("--jobs", type=int, default=3, help="seats working at once")
    ap.add_argument("--list", action="store_true", help="what is queued, and nothing else")
    ap.add_argument("--dry-run", action="store_true", help="say what would run")
    ap.add_argument("--apply", action="store_true",
                    help="re-apply held patches from hq/data/patches/, without running any model")
    ap.add_argument("--repair", action="store_true",
                    help="rewrite any card whose result is a raw CLI envelope, and nothing else")
    ap.add_argument("--no-suites", action="store_true", help="skip the suites (they run by default "
                                                            "when a patch touches the game)")
    args = ap.parse_args()

    work.bind(server)
    org = server.load_org()

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

    if args.list or args.dry_run:
        for i in pool:
            print(f"{i['id']}  {i['owner']:9} {server.seat_model(org, i['owner']) or '-':7} "
                  f"{i['title'][:66]}")
        print(f"\n{len(pool)} queued.")
        return 0
    if not pool:
        print("Nothing queued.")
        return 0

    run_id = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:4]
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
        if not rec:
            continue
        ok, why = (False, "the check said it should not land as it stands")
        if rec["limited"]:
            ok, why = False, "the token window ran dry before this finished"
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
    if applied_files and touches_game(applied_files) and not args.no_suites:
        print("\n  running both suites (an applied patch touched the game)…", flush=True)
        suites = run_suites()
        for k, v in suites.items():
            print(f"  {k}: {'green' if v['ok'] else 'RED'}", flush=True)

    for it in pool:
        rec = records.get(it["id"])
        if not rec or rec["limited"]:
            continue          # still queued; the window will come back
        fresh = server.load_json(work._item_path(it["id"]))
        write_back(fresh, rec, rec.get("applied", False), rec.get("why_not", ""),
                   suites if rec.get("applied") else None, org)

    bill = server.sum_usage([u for r in records.values() for u in r["usage"]])
    esc = [(i, records[i["id"]]["check"]) for i in pool
           if (records.get(i["id"]) or {}).get("check")
           and records[i["id"]]["check"].get("escalates")]
    print(f"\nDrained in {int(time.time() - started) // 60} min. "
          f"{sum(1 for r in records.values() if r.get('applied'))} of {len(pool)} landed.")
    print(f"Cost: {bill['calls']} model calls, {bill['tokens']:,} tokens "
          f"(${bill['list_usd']:.2f} at API list price — this is a subscription, so that "
          f"is a size, not a bill).")
    if esc:
        print("\nEscalated to Daniel:")
        for it, ch in esc:
            print(f"  {it['id']} [{ch['escalation_reason'] or 'unstated'}] {ch['escalates']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

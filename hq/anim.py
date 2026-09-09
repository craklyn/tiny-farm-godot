"""Tiny Farm HQ — the Animation Lab's server side.

Three jobs, kept out of server.py the way studio.py and work.py are, so this is
importable and testable on its own:

  * finding the parametric loops that have been drawn, and what art each one
    reads, so the page can play a loop it has never heard of and say when the
    art beneath it has moved;
  * re-running one loop's own script at values dialled in on the page;
  * starting a new loop from a sentence — composing the standing prompt around
    the subject, running it in the background, and filing the finished thing to
    the art director for a verdict.

Nothing here is on a page-load path except `loops_index`, which reads a handful
of small files and caches on their timestamps. Drawing costs money and is only
ever started by a button.
"""

import json
import os
import re
import subprocess
import sys
import types
import threading
import time

HOST = None
REPO = None
DATA = None

LOOPS_DIR = "tools/experiments/out"
SCRIPTS_DIR = "tools/experiments"
PROMPT_FILE = "tools/experiments/ANIMATION_PROMPT.md"
NOTES_FILE = "tools/experiments/ANIMATION_NOTES.md"

PREVIEWS = None          # scratch renders from the sliders
RUNS = None              # one record per drawing run

RENDER_LOCK = threading.Semaphore(2)     # cheap, but not free
DRAW_LOCK = threading.Semaphore(1)       # drawing is not cheap; one at a time
DRAW_TIMEOUT = 45 * 60                   # six passes with contact sheets is slow
DRAW_MODEL = "opus"
DRAW_TOOLS = "Read,Write,Edit,Glob,Grep,Bash"

_SRC_CACHE = {}          # script path -> (mtime, [asset paths])
_INDEX_CACHE = {"key": None, "data": None}


def bind(server_module):
    """server.py hands us itself, matching studio.py and work.py."""
    global HOST, REPO, DATA, PREVIEWS, RUNS
    HOST = server_module
    REPO = server_module.REPO
    DATA = server_module.DATA
    PREVIEWS = os.path.join(DATA, "loop_previews")
    RUNS = os.path.join(DATA, "anim_runs")


def _repo(*parts):
    return os.path.join(REPO, *parts)


def _read(rel):
    try:
        with open(_repo(rel), encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


# ---------------------------------------------------------------------------
# what has been drawn
# ---------------------------------------------------------------------------

def loop_sources(script_rel):
    """The sprite sheets a loop's script draws from, read out of the script.

    Taken from the source rather than declared, so it stays true for scripts
    written before anybody thought to ask — including whatever an agent wrote
    ten minutes ago. It only sees literal paths, which is why the prompt
    requires them written as literals."""
    full = _repo(script_rel)
    try:
        m = os.path.getmtime(full)
    except OSError:
        return []
    hit = _SRC_CACHE.get(script_rel)
    if hit and hit[0] == m:
        return hit[1]
    src = _read(script_rel)
    found = sorted({p for p in re.findall(r"assets/[A-Za-z0-9_/.-]+\.png", src)
                    if os.path.isfile(_repo(p))})
    _SRC_CACHE[script_rel] = (m, found)
    return found


def _index_key():
    """Cheap signature of everything loops_index reads, so a page polling every
    few seconds re-walks the tree only when it has actually changed."""
    parts = []
    for d in (LOOPS_DIR, SCRIPTS_DIR, "assets/sprites/generated"):
        full = _repo(d)
        try:
            parts.append((d, os.path.getmtime(full)))
            for name in sorted(os.listdir(full)):
                parts.append((name, os.path.getmtime(os.path.join(full, name))))
        except OSError:
            parts.append((d, 0))
    try:
        parts.append(("runs", os.path.getmtime(RUNS)))
    except OSError:
        pass
    return tuple(parts)


def loops_index():
    """Every parametric loop rendered into tools/experiments/out/, plus the runs
    currently drawing one.

    Discovery is the whole point: a loop appears because it was drawn, not
    because anybody registered it. Each directory carries a params.json written
    by the script that made it, so the page can play and describe a loop it has
    never seen.

    Each loop also reports the sheets its script draws from and which of them
    have changed since the render was made. The scripts read the live sheets, so
    a loop is never wrong for long — but the PNG on disk is a snapshot, and
    without this a repainted crow would leave every crow animation quietly
    showing the old bird."""
    key = _index_key()
    if _INDEX_CACHE["key"] == key:
        return _INDEX_CACHE["data"]

    root = _repo(LOOPS_DIR)
    out = []
    if not os.path.isdir(root):
        data = {"loops": [], "dir": LOOPS_DIR, "runs": runs_index(), "pending": 0,
                "looked": time.strftime("%H:%M:%S")}
        _INDEX_CACHE.update(key=key, data=data)
        return data

    try:
        scripts = {f[len("vfx_"):-len(".py")] for f in os.listdir(_repo(SCRIPTS_DIR))
                   if f.startswith("vfx_") and f.endswith(".py")}
    except OSError:
        scripts = set()

    for slug in sorted(set(os.listdir(root)) | scripts):
        d = os.path.join(root, slug)
        meta = os.path.join(d, "params.json")
        if not os.path.isfile(meta):
            # A script with no finished render, or a directory an agent has made
            # but not filled: say so rather than showing nothing. "Still being
            # drawn" and "the page has not looked lately" are different answers
            # to "where is my animation", and only one of them means wait.
            if slug in scripts or os.path.isdir(d):
                out.append({"slug": slug, "pending": True,
                            "script": f"{SCRIPTS_DIR}/vfx_{slug}.py" if slug in scripts else None})
            continue
        try:
            with open(meta, encoding="utf-8") as fh:
                m = json.load(fh)
        except Exception as e:
            out.append({"slug": slug, "error": f"params.json unreadable: {e}"})
            continue
        files = set(os.listdir(d))

        def pick(suffix):
            return next((f for f in sorted(files) if f.endswith(suffix)), None)

        sheet = pick("_sheet.png")
        script = f"{SCRIPTS_DIR}/vfx_{slug}.py"
        has_script = os.path.isfile(_repo(script))
        drawn_at = os.path.getmtime(meta)
        sources = loop_sources(script) if has_script else []
        stale = [p for p in sources if os.path.getmtime(_repo(p)) > drawn_at]
        gif, contact = pick(".gif"), pick("_contact.png")
        out.append({
            "slug": slug,
            "sheet": f"/loops/{slug}/{sheet}" if sheet else None,
            "gif": f"/loops/{slug}/{gif}" if gif else None,
            "contact": f"/loops/{slug}/{contact}" if contact else None,
            "frames": m.get("frames"), "canvas": m.get("canvas"),
            "colours": m.get("colours"),
            "params": m.get("params", []), "values": m.get("values", {}),
            "script": script if has_script else None,
            "sources": sources, "stale": stale,
            "drawn": time.strftime("%Y-%m-%d %H:%M", time.localtime(drawn_at)),
        })

    # Newest finished first; anything still being drawn sits at the top, because
    # the thing you are waiting for is what you came to the page to see.
    out.sort(key=lambda x: (bool(x.get("pending")), x.get("drawn") or ""), reverse=True)
    data = {"loops": out, "dir": LOOPS_DIR, "runs": runs_index(),
            "looked": time.strftime("%H:%M:%S"),
            "pending": sum(1 for x in out if x.get("pending"))}
    _INDEX_CACHE.update(key=key, data=data)
    return data


# ---------------------------------------------------------------------------
# re-running one loop at dialled-in values
# ---------------------------------------------------------------------------

def loop_render(payload):
    """Re-draw one loop at the values just dialled in on the page.

    This runs the loop's OWN script, with the same override argument a person
    would pass on the command line, so what the dashboard shows and what the
    repo produces cannot drift apart.

    It is one of only two things here that execute project code, so it is
    fenced: the slug must name a loop that already exists, the script path is
    derived rather than accepted, every override must be a number whose key that
    loop declares and is clamped to that key's own range, and the output lands
    in a scratch directory unless `keep` is set. No model is called and nothing
    is billed — the cost is about a second of CPU."""
    slug = str(payload.get("slug") or "")
    if not re.fullmatch(r"[a-z0-9_]{1,64}", slug):
        return {"error": "bad loop name"}
    known = {L["slug"]: L for L in loops_index()["loops"]}
    L = known.get(slug)
    if not L:
        return {"error": f"no loop called {slug}"}
    script = _repo(f"{SCRIPTS_DIR}/vfx_{slug}.py")
    if not os.path.isfile(script):
        return {"error": "this loop has no script to re-run"}

    declared = {row[0]: row for row in (L.get("params") or [])}
    values, bad = {}, []
    for k, v in (payload.get("values") or {}).items():
        row = declared.get(k)
        try:
            x = float(v)
        except (TypeError, ValueError):
            row = None
        if not row:
            bad.append(k)
            continue
        values[k] = min(max(x, float(row[2])), float(row[3]))    # clamped, never trusted
    if bad:
        return {"error": "unknown or non-numeric parameters: " + ", ".join(sorted(bad)[:5])}
    if not values:
        # Redrawing after the base art moved asks no question about the numbers:
        # keep the ones it was drawn at and let the new sheets through.
        values = {k: v for k, v in (L.get("values") or {}).items() if k in declared}
    if not values:
        return {"error": "no parameters given"}

    keep = bool(payload.get("keep"))
    out = _repo(LOOPS_DIR, slug) if keep else os.path.join(PREVIEWS, slug)
    os.makedirs(out, exist_ok=True)
    os.makedirs(os.path.join(PREVIEWS, slug), exist_ok=True)
    # The overrides file always lives in scratch, never beside a render: a loop's
    # directory holds the loop, and only what the script itself puts there.
    ov = os.path.join(PREVIEWS, slug, "overrides.json")
    with open(ov, "w", encoding="utf-8") as fh:
        json.dump(values, fh)

    # These scripts are written by agents that may still be working on them, so a
    # render can execute a file that is being rewritten underneath it. Let a very
    # recent write settle, then note the version we ran, so a failure can say
    # whether it was the values or the moment.
    def stamp():
        try:
            st = os.stat(script)
            return (st.st_mtime, st.st_size)
        except OSError:
            return None

    before = stamp()
    if before and time.time() - before[0] < 1.5:
        time.sleep(1.5)
        before = stamp()

    t0 = time.time()
    try:
        with RENDER_LOCK:
            p = subprocess.run([sys.executable, script, out, ov], cwd=REPO,
                               capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return {"error": "the script ran for over a minute and was stopped"}
    if p.returncode != 0:
        tail = (p.stderr or p.stdout or "").strip().splitlines()
        detail = "\n".join(tail[-6:])[:600]
        if stamp() != before:
            return {"error": "the script was being edited while it ran, so this says nothing "
                             "about your values — try again",
                    "detail": detail, "raced": True}
        blew = next((ln for ln in reversed(tail) if "Error" in ln), "")
        if "AssertionError" in blew:
            # The script's own guard, not a crash: it checked its work and refused.
            return {"error": "the script refused these values: "
                             + blew.split("AssertionError:", 1)[-1].strip()[:200],
                    "detail": detail, "refused": True}
        return {"error": "the script failed", "detail": detail}

    meta = os.path.join(out, "params.json")
    if not os.path.isfile(meta):
        return {"error": "the script wrote no params.json, so its output cannot be read"}
    with open(meta, encoding="utf-8") as fh:
        m = json.load(fh)
    sheet = next((f for f in sorted(os.listdir(out)) if f.endswith("_sheet.png")), None)
    if not sheet:
        return {"error": "the script wrote no sprite sheet"}
    # A script that ignores its overrides argument renders its defaults and exits
    # cleanly, which would let the page report a redraw that never happened.
    wrote = m.get("values") or {}
    ignored = sorted(k for k, v in values.items()
                     if k in wrote and abs(float(wrote[k]) - float(v)) > 1e-9)
    base = "/loops" if keep else "/loop-preview"
    if keep:
        _INDEX_CACHE["key"] = None
    return {
        "slug": slug, "values": wrote or values, "kept": keep,
        "frames": m.get("frames"), "canvas": m.get("canvas"), "colours": m.get("colours"),
        "sheet": f"{base}/{slug}/{sheet}?t={int(time.time() * 1000)}",
        "seconds": round(time.time() - t0, 2),
        "ignored": ignored,
    }


# ---------------------------------------------------------------------------
# drawing a new one from a sentence
# ---------------------------------------------------------------------------

def _runs_dir():
    os.makedirs(RUNS, exist_ok=True)
    return RUNS


def _run_path(run_id):
    return os.path.join(_runs_dir(), f"{run_id}.json")


def _save_run(rec):
    tmp = _run_path(rec["id"]) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(rec, fh, indent=2)
    os.replace(tmp, _run_path(rec["id"]))
    _INDEX_CACHE["key"] = None
    return rec


def runs_index():
    """Every drawing run, newest first. Finished ones age out of the page but
    stay on disk, because what a run cost is a record."""
    out = []
    try:
        names = sorted(os.listdir(_runs_dir()))
    except OSError:
        return out
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(RUNS, name), encoding="utf-8") as fh:
                out.append(json.load(fh))
        except Exception:
            continue
    out.sort(key=lambda r: r.get("started") or "", reverse=True)
    live = [r for r in out if r.get("state") == "drawing"]
    recent = [r for r in out if r.get("state") != "drawing"][:4]
    return live + recent


def _compose(subject):
    """The standing prompt with this subject in it.

    The prompt file is the single source: it is what the manual runs were given,
    it is version-controlled, and improving it improves what the button does.
    Everything after the marker line is the instruction; the subject is
    substituted into the slot the file already carries."""
    prompt = _read(PROMPT_FILE)
    if not prompt.strip():
        return None, "the animation prompt is missing from the repo"
    body = prompt.split("\n---\n", 1)[-1] if "\n---\n" in prompt else prompt
    slot = re.search(r"\*\*SUBJECT:\*\*.*?(?=\n\n)", body, re.S)
    if not slot:
        return None, "the prompt has no SUBJECT slot to fill"
    filled = body.replace(slot.group(0), f"**SUBJECT:** {subject.strip()}")
    return (
        filled
        + "\n\n## Before you start\n\n"
        + f"Read `{NOTES_FILE}` first — it is what earlier loops learned, including "
        + "which of their choices were local and should not be copied. Treat it as "
        + "precedent, not as a style guide.\n\n"
        + "You are running unattended from the dashboard: nobody is watching to "
        + "answer a question, so make the judgement, write down what you decided "
        + "and why in the docstring, and finish. End your reply with a line "
        + "`SLUG: <slug>` naming what you drew."
    ), None


def start_run(payload):
    """Begin drawing a loop from a sentence. Returns immediately; the work
    happens on a thread and the page watches it."""
    subject = str(payload.get("subject") or "").strip()
    if len(subject) < 12:
        return {"error": "say a sentence or two about what should happen"}
    if len(subject) > 600:
        return {"error": "keep the subject to a couple of sentences"}
    if any(r.get("state") == "drawing" for r in runs_index()):
        return {"error": "one is already being drawn — they run one at a time so "
                         "they do not fight over the working tree"}
    prompt, err = _compose(subject)
    if err:
        return {"error": err}

    run_id = f"r{int(time.time())}{os.urandom(2).hex()}"
    rec = _save_run({
        "id": run_id, "subject": subject, "state": "drawing",
        "step": "", "turns": 0,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "started_ts": time.time(), "finished": "", "slug": "",
        "error": "", "cost": None, "note": "",
    })
    threading.Thread(target=_draw, args=(run_id, prompt), daemon=True).start()
    return {"ok": True, "run": rec}


def _step_of(event):
    """One line of a streamed run, as something a person would recognise.

    A run is otherwise a black box for its whole life: alive and stuck look
    identical from outside, which is exactly the question the page is asked while
    one is in flight."""
    if event.get("type") != "assistant":
        return None
    for block in (event.get("message") or {}).get("content") or []:
        if block.get("type") != "tool_use":
            continue
        name = block.get("name") or "working"
        arg = block.get("input") or {}
        target = arg.get("file_path") or arg.get("path") or arg.get("pattern") or ""
        if name == "Bash":
            target = (arg.get("description") or arg.get("command") or "")[:60]
        if target:
            target = str(target).replace(REPO + "/", "")
        return f"{name.lower()} {target}".strip()[:80]
    return None


def _draw(run_id, prompt):
    """One drawing run, on its own thread. Never raises into the server."""
    started = time.time()
    try:
        with DRAW_LOCK:
            cmd = ["claude", "-p", prompt,
                   "--allowedTools", DRAW_TOOLS,
                   "--permission-mode", "acceptEdits",
                   "--output-format", "stream-json", "--verbose",
                   "--model", DRAW_MODEL]
            p = subprocess.Popen(cmd, cwd=REPO, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, bufsize=1,
                                 env={**os.environ, "CLAUDE_CODE_DISABLE_AUTOUPDATE": "1"})
            doc, turns, last_write = {}, 0, 0.0
            for line in p.stdout:
                if time.time() - started > DRAW_TIMEOUT:
                    p.kill()
                    raise subprocess.TimeoutExpired(cmd, DRAW_TIMEOUT)
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if event.get("type") == "result":
                    doc = event
                    continue
                step = _step_of(event)
                if not step:
                    continue
                turns += 1
                # Throttled: the page polls every few seconds, and a record
                # rewritten per tool call would be all disk and no more truth.
                if time.time() - last_write > 3:
                    last_write = time.time()
                    rec = _load_run(run_id)
                    if rec.get("state") != "drawing":
                        break
                    rec.update({"step": step, "turns": turns})
                    _save_run(rec)
            p.wait(timeout=60)
        stderr = (p.stderr.read() or "") if p.stderr else ""
        p = types.SimpleNamespace(returncode=p.returncode, stderr=stderr, stdout="")
        reply = str(doc.get("result") or "")
        cost = HOST.usage_from_cli(doc) if hasattr(HOST, "usage_from_cli") else None
        slug = ""
        m = re.search(r"SLUG:\s*([a-z0-9_]{1,64})", reply)
        if m:
            slug = m.group(1)
        if not slug:
            # It did not say, so find the loop that appeared while it worked.
            for L in loops_index()["loops"]:
                if L.get("drawn") and L.get("script"):
                    try:
                        if os.path.getmtime(_repo(L["script"])) >= started:
                            slug = L["slug"]
                            break
                    except OSError:
                        pass
        ok = p.returncode == 0 and bool(slug)
        rec = _load_run(run_id)
        rec.update({
            "state": "done" if ok else "failed",
            "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "slug": slug,
            "cost": cost,
            "note": reply.strip()[-600:],
            "error": "" if ok else (
                "the run ended without naming a loop it drew"
                if p.returncode == 0 else
                ((p.stderr or "").strip().splitlines()[-1:] or ["the run failed"])[0][:300]),
        })
        _save_run(rec)
        if ok:
            _file_for_review(rec)
    except subprocess.TimeoutExpired:
        rec = _load_run(run_id)
        rec.update({"state": "failed", "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "error": f"ran past {DRAW_TIMEOUT // 60} minutes and was stopped"})
        _save_run(rec)
    except Exception as e:
        rec = _load_run(run_id)
        rec.update({"state": "failed", "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "error": f"{type(e).__name__}: {e}"[:300]})
        _save_run(rec)


def _load_run(run_id):
    try:
        with open(_run_path(run_id), encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {"id": run_id}


def _file_for_review(rec):
    """A finished loop wants a verdict, and a verdict is Daniel's to give — so it
    goes to his queue rather than being announced and forgotten. The art
    director owns whether a loop is good."""
    cost = rec.get("cost") or {}
    spent = cost.get("list_usd")
    bill = (f"It cost ${spent:.2f} and {cost.get('turns', '?')} turns."
            if isinstance(spent, (int, float)) else
            "Its cost was not reported by the CLI.")
    wid = f"w{rec['id']}"
    item = {
        "id": wid,
        "title": f"Say whether the {rec['slug'].replace('_', ' ')} loop is any good",
        "level": "story", "owner": "ingrid", "tier": 2,
        "tier_reason": "A finished loop is waiting on a verdict only Daniel can give.",
        "ask": (
            f"The Animation Lab drew a loop from this subject, unattended:\n\n"
            f"    {rec['subject']}\n\n"
            f"It is on the Lab's page as `{rec['slug']}` — play it at true size as well "
            f"as zoomed, and move its instruments to see what the numbers do. {bill}\n\n"
            "What is wanted is a verdict and a reason: keep it, send it back, or drop "
            "it. The reason is the part that helps whoever picks it up, so it matters "
            "more than the verdict.\n\n"
            "If it is kept, the loop and its script still have to be landed on main; "
            "if it is sent back, say which of its parameters or beats is wrong rather "
            "than that it needs work."
        ),
        "first_action": f"Open #/design/anim/{rec['slug']} and watch it at both sizes",
        "state": "for_review", "thread": "ingrid", "source": "anim_lab",
        "source_message": f"Drawn unattended by the Animation Lab from: {rec['subject'][:200]}",
        "result": "", "started": rec.get("started", ""), "attempts": 1,
        "created": time.strftime("%Y-%m-%dT%H:%M"), "created_ts": time.time(),
        "conversation": [],
    }
    try:
        path = os.path.join(DATA, "work", f"{wid}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(item, fh, indent=2)
        rec["work_item"] = wid
        _save_run(rec)
    except OSError as e:
        rec["note"] = (rec.get("note") or "") + f"\n(could not file for review: {e})"
        _save_run(rec)

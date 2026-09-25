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

import execution
import work

import hashlib
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import types
import threading
import time
import uuid

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
PROMOTE_LOCK = threading.Lock()
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
    REPO = getattr(server_module, "USER_WORKSPACE", server_module.REPO)
    DATA = server_module.DATA
    PREVIEWS = os.path.join(DATA, "loop_previews")
    RUNS = os.path.join(DATA, "anim_runs")


def _repo(*parts):
    return os.path.join(REPO, *parts)


def _hash(path):
    if not os.path.isfile(path):
        return None
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _render_names(slug):
    return ["params.json", f"{slug}_sheet.png", f"{slug}.gif",
            f"{slug}_contact.png", f"{slug}_1x.png"]


def _manifest(directory, names):
    return {name: _hash(os.path.join(directory, name)) for name in names}


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
    # Source art is nested by loop. Directory mtimes alone do not change when
    # an existing PNG is repainted, so include each file's own mtime.
    showcase = _repo("assets/showcase")
    for base, _, files in os.walk(showcase):
        for name in sorted(files):
            if name.endswith(".png"):
                path = os.path.join(base, name)
                parts.append((path, os.path.getmtime(path)))
    for extra in (RUNS, os.path.join(DATA, "anim_asks"), os.path.join(DATA, "work")):
        try:
            parts.append((extra, os.path.getmtime(extra)))
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

    reviews = _anim_reviews()
    try:
        org = HOST.load_org() if hasattr(HOST, "load_org") else None
    except Exception:
        org = None
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
        active = _active_review_for_slug(slug, reviews)
        closed = next((item for item in reviews.get(slug, [])
                       if item.get("state") in work.CLOSED_STATES), None)

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
            "asks": asks_for(slug),
            "work_item": (active or {}).get("id"),
            "review": (_review_summary(closed, org) if closed and not active else None),
            "cost": _cost_of(slug),
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
    in a unique scratch directory. No model is called and nothing
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
        if row and not math.isfinite(x):
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

    if payload.get("keep"):
        return {"error": "use preview promotion to save a render"}
    preview_id = uuid.uuid4().hex
    out = os.path.join(PREVIEWS, slug, preview_id)
    target = _repo(LOOPS_DIR, slug)
    names = _render_names(slug)
    baseline = _manifest(target, names)
    source_hash = _hash(script)
    source_revision = None
    if os.path.exists(_repo(".git")):
        revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                                  capture_output=True, text=True)
        source_revision = revision.stdout.strip() if revision.returncode == 0 else None
    os.makedirs(out, exist_ok=True)
    ov = os.path.join(out, "overrides.json")
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
                     if k not in wrote or abs(float(wrote[k]) - float(v)) > 1e-9)
    if ignored or any(_hash(os.path.join(out, name)) is None for name in names):
        return {"error": "the script did not produce the requested complete preview",
                "ignored": ignored}
    record = {"slug": slug, "id": preview_id, "values": wrote,
              "source_sha256": source_hash, "source_revision": source_revision,
              "base": baseline,
              "files": _manifest(out, names), "created": time.time()}
    with open(os.path.join(out, "preview.json"), "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
    return {
        "slug": slug, "preview_id": preview_id, "values": wrote,
        "frames": m.get("frames"), "canvas": m.get("canvas"), "colours": m.get("colours"),
        "sheet": f"/loop-preview/{slug}/{preview_id}/{sheet}",
        "seconds": round(time.time() - t0, 2),
        "ignored": ignored,
    }


def loop_promote(payload):
    """Copy exactly the inspected preview into the committed render directory."""
    slug = str(payload.get("slug") or "")
    preview_id = str(payload.get("preview_id") or "")
    if not re.fullmatch(r"[a-z0-9_]{1,64}", slug) or not re.fullmatch(r"[0-9a-f]{32}", preview_id):
        return {"error": "bad preview identity"}
    preview = os.path.join(PREVIEWS, slug, preview_id)
    try:
        with open(os.path.join(preview, "preview.json"), encoding="utf-8") as fh:
            record = json.load(fh)
    except (OSError, ValueError):
        return {"error": "preview is missing"}
    if record.get("slug") != slug or record.get("id") != preview_id:
        return {"error": "preview identity changed"}
    names = _render_names(slug)
    target = _repo(LOOPS_DIR, slug)
    script = _repo(SCRIPTS_DIR, f"vfx_{slug}.py")
    with PROMOTE_LOCK:
        if _hash(script) != record.get("source_sha256"):
            return {"error": "loop script changed since this preview; render it again"}
        if _manifest(preview, names) != record.get("files"):
            return {"error": "preview files changed; render it again"}
        if _manifest(target, names) != record.get("base"):
            return {"error": "committed render changed since this preview; render it again"}
        paths = [os.path.join(LOOPS_DIR, slug, name) for name in names]
        status = subprocess.run(["git", "status", "--porcelain", "--", *paths],
                                cwd=REPO, capture_output=True, text=True)
        if status.returncode or status.stdout.strip():
            return {"error": "render has unfinished local changes; preserve them before promoting"}
        for path in paths:
            if os.path.exists(_repo(path)):
                tracked = subprocess.run(["git", "ls-files", "--error-unmatch", "--", path],
                                         cwd=REPO, capture_output=True, text=True)
                if tracked.returncode:
                    return {"error": "render contains an untracked file; preserve it before promoting"}
        try:
            with open(os.path.join(target, "params.json"), encoding="utf-8") as fh:
                previous = json.load(fh).get("values") or {}
        except (OSError, ValueError):
            previous = {}
        new_values = record.get("values") or {}
        changes = {k: {"from": previous.get(k), "to": v} for k, v in new_values.items()
                   if previous.get(k) != v}
        os.makedirs(target, exist_ok=True)
        staged = []
        try:
            for name in names:
                dst = os.path.join(target, f".{name}.{preview_id}.tmp")
                shutil.copyfile(os.path.join(preview, name), dst)
                staged.append((dst, os.path.join(target, name)))
            for src, dst in staged:
                os.replace(src, dst)
        finally:
            for src, _ in staged:
                if os.path.exists(src):
                    os.remove(src)
        entry = {"preview_id": preview_id, "promoted": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                 "source_sha256": record["source_sha256"],
                 "source_revision": record.get("source_revision"), "changes": changes,
                 "before": record["base"], "after": record["files"], "values": new_values}
        with open(os.path.join(target, "promotions.jsonl"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, sort_keys=True) + "\n")
        _INDEX_CACHE["key"] = None
    return {"slug": slug, "values": new_values, "changes": changes,
            "sheet": f"/loops/{slug}/{slug}_sheet.png?t={int(time.time() * 1000)}"}


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


def runs_index_all():
    """Every run ever recorded, newest first."""
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
    return out


def runs_index():
    """What the page shows: everything live, and the last few that finished.
    Older ones stay on disk, because what a run cost is a record."""
    out = runs_index_all()
    live = [r for r in out if r.get("state") == "drawing"]
    return live + [r for r in out if r.get("state") != "drawing"][:4]


# ---------------------------------------------------------------------------
# what has been asked of a loop
# ---------------------------------------------------------------------------
#
# A loop is not just pixels; it is the sentence that made it and every sentence
# since. That chain is what a rework needs so it does not undo an earlier
# request, what Daniel needs so he does not ask twice, and what says later why
# the art looks the way it does. Runs record execution — cost, state, whether it
# finished. This records intent, and the two cross-reference by run id.

def _asks_path(slug):
    d = os.path.join(DATA, "anim_asks")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, f"{slug}.json")


def asks_for(slug):
    try:
        with open(_asks_path(slug), encoding="utf-8") as fh:
            return json.load(fh).get("entries", [])
    except Exception:
        return []


def _append_ask(slug, entry):
    entries = asks_for(slug)
    entries.append(entry)
    tmp = _asks_path(slug) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"slug": slug, "entries": entries}, fh, indent=2)
    os.replace(tmp, _asks_path(slug))
    _INDEX_CACHE["key"] = None
    return entry


def _ask_history(slug):
    """The chain as a rework has to read it: numbered, oldest first, verbatim."""
    lines = []
    n = 0
    for e in asks_for(slug):
        if e.get("kind") not in ("draw", "rework"):
            continue
        n += 1
        what = "originally asked for" if e["kind"] == "draw" else f"change {n - 1} asked for"
        lines.append(f"{n}. {what}:\n\n    " + (e.get("text") or "").strip().replace("\n", "\n    "))
    return "\n\n".join(lines)


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


def _compose_rework(slug, note):
    """The standing rules, plus this loop's whole history, plus the new ask.

    A rework revises what is there rather than starting again: the loop already
    passed a verdict on everything except what is being complained about, and
    redrawing would silently throw that away along with any tuning."""
    prompt = _read(PROMPT_FILE)
    if not prompt.strip():
        return None, "the animation prompt is missing from the repo"
    body = prompt.split("\n---\n", 1)[-1] if "\n---\n" in prompt else prompt
    slot = re.search(r"\*\*SUBJECT:\*\*.*?(?=\n\n)", body, re.S)
    if slot:
        body = body.replace(slot.group(0), "")
    return (
        f"# Revise the {slug} loop\n\n"
        f"`{SCRIPTS_DIR}/vfx_{slug}.py` already exists and already draws. **Edit it in "
        f"place.** Keep its slug, its output directory, its parameter contract and every "
        f"part nobody has complained about — a rework that starts again throws away the "
        f"parts that were already right, along with any values they were tuned to.\n\n"
        f"## What has been asked of this loop so far\n\n{_ask_history(slug)}\n\n"
        f"## What is being asked now\n\n    {note.strip()}\n\n"
        f"Address every point in it. Where a request cannot be met, say so in your reply "
        f"and say why, rather than quietly doing something else. Where one is a question "
        f"rather than an instruction, answer it with the pixels and say what you chose.\n\n"
        f"Re-render to `{LOOPS_DIR}/{slug}/` when you are done, so the page picks it up.\n\n"
        f"---\n\n## The standing rules, unchanged\n{body}\n\n"
        f"## Before you start\n\nRead `{NOTES_FILE}` — what earlier loops learned, "
        f"including which of their choices were local and should not be copied. Treat it "
        f"as precedent, not as a style guide.\n\n"
        f"You are running unattended from the dashboard: nobody is watching to answer a "
        f"question, so make the judgement, write down what you decided and why, and "
        f"finish. End your reply with `SLUG: {slug}`."
    ), None


def record_verdict(payload):
    """Keep it, send it back, or drop it — with the reason, always.

    A verdict without a reason is not recorded, because the reason is the only
    part of this that helps whoever picks it up next."""
    slug = str(payload.get("slug") or "")
    work_id = str(payload.get("work_id") or "")
    verdict = str(payload.get("verdict") or "")
    why = str(payload.get("why") or "").strip()
    values = payload.get("values")
    if not re.fullmatch(r"[a-z0-9_]{1,64}", slug):
        return {"error": "bad loop name"}
    if verdict not in ("keep", "rework", "drop"):
        return {"error": "unknown verdict"}
    if not why:
        return {"error": "say why first — that sentence is what reaches the next person"}
    if (not isinstance(values, dict) or len(values) > 64
            or any(not isinstance(k, str) or not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]{0,63}", k)
                   or isinstance(v, bool) or not isinstance(v, (int, float))
                   or not math.isfinite(v) for k, v in values.items())):
        return {"error": "the judged slider values are missing or invalid"}
    with work.mutation_lock():
        filed = False
        if not work_id:
            work_id, error = _file_review_for_verdict(slug)
            if error:
                return {"error": error}
            filed = True
        result = _record_verdict_locked(slug, work_id, verdict, why, values)
        if filed and not result.get("error"):
            result["filed"] = True
        return result


def _file_review_for_verdict(slug):
    """A loop drawn by hand has no Lab run behind it, so nothing filed a review
    card when it finished. Judging it on the page files that card first, so the
    verdict travels the same way as one on a drawn loop: onto a card the art
    director owns, and from there into the queue. Only a loop that has never
    had a card gets one; anything else means the page is out of date."""
    reviews = _anim_reviews().get(slug, [])
    if any(_judgeable(item) or item.get("state") == "doing" for item in reviews):
        return None, "this loop already has a review card waiting; reload the page so your verdict goes on it"
    if reviews:
        return None, "this loop has already been judged; write on its review card to change that"
    if not os.path.isfile(_repo(LOOPS_DIR, slug, "params.json")):
        return None, "there is no drawn loop by that name"
    item = _review_item(
        "w" + uuid.uuid4().hex[:12], slug,
        f"`{slug}` was drawn by hand rather than by an Animation Lab run, so no review card "
        f"was filed when it finished. Daniel judged it on the Lab's page, which filed this "
        f"card to carry his verdict; the verdict and his reason are in its conversation.",
        "Filed by a verdict given on the Animation Lab's page", "")
    work.save_item(item)
    _INDEX_CACHE["key"] = None
    return item["id"], None


def _record_verdict_locked(slug, work_id, verdict, why, values):
    """Check the live review and save its handoff under the shared work lock."""
    item, path, error = _review_record(work_id, slug)
    if error:
        return {"error": error}
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    decision = {"slug": slug, "verdict": verdict, "reason": why,
                "values": values, "at": stamp, "review_work_id": work_id}
    if verdict == "rework":
        result = start_rework(slug, why, work_id, item, path, decision)
        return result
    followup_id = "w" + uuid.uuid4().hex[:12]
    name = slug.replace("_", " ")
    title = (f"Land the kept {name} animation" if verdict == "keep"
             else f"Retire the dropped {name} animation")
    followup = {
        "id": followup_id, "title": title,
        "level": "story", "owner": "ingrid", "tier": 1,
        "tier_reason": "The art director must carry Daniel's recorded loop verdict into the project.",
        "ask": (f"Daniel judged `{slug}` at {values}: {verdict}. Reason: {why}\n\n"
                + ("Land its approved script and render through the normal review path."
                   if verdict == "keep" else
                   "Record this loop as dropped and keep it out of the shipping animation set; preserve its files and history.")),
        "first_action": (f"Review the kept {slug} loop and its render for landing"
                         if verdict == "keep" else
                         f"Record why {slug} was dropped and check shipping references"),
        "state": "waiting_session", "thread": "ingrid", "source": "anim_verdict",
        "source_message": f"Animation Lab verdict on {work_id}", "result": "",
        "started": "", "attempts": 0, "created": stamp[:16],
        "created_ts": time.time(), "conversation": [],
        "anim_slug": slug, "anim_verdict": decision,
        "parent": work_id,
        "source_work": [{"id": work_id, "card": item.get("title", ""), "title": title}],
    }
    followup_path = os.path.join(DATA, "work", f"{followup_id}.json")
    applied = False
    try:
        os.makedirs(os.path.join(DATA, "work"), exist_ok=True)
        work.save_item(followup)
        # The verdict itself goes through the queue's own accept/drop path, so a
        # verdict given here and one given on the Work page are the same act: his
        # reason lands on the card's conversation, the card closes, and its owner
        # is asked to answer him there (ask_owner). Only what the queue cannot
        # know — the slider values he judged at and the loop's own history — is
        # added by the Lab.
        acted = work._api_post("/api/work/accept" if verdict == "keep" else "/api/work/drop",
                               {"id": work_id, "comment": why})
        if not isinstance(acted, dict) or acted.get("error"):
            raise ValueError((acted or {}).get("error") or "the review card did not change")
        applied = True
        item = work.load_item(work_id)
        item.setdefault("anim_verdicts", []).append(decision)
        item["spawned"] = (item.get("spawned") or []) + [
            {"id": followup_id, "title": followup["title"],
             "state": followup["state"], "owner": followup["owner"]}]
        _write_review(item, path)
    except (OSError, ValueError, work.RecordConflict) as exc:
        # Once the card has closed, the follow-up is the only thing still
        # carrying the judged values to the art director, so it stays.
        if not applied:
            try:
                os.remove(followup_path)
            except OSError:
                pass
        return {"error": f"could not save the verdict: {exc}"}
    _append_ask(slug, {"at": time.strftime("%Y-%m-%dT%H:%M:%S"), "kind": verdict,
                       "text": why, "run_id": ""})
    return {"ok": True, "verdict": verdict, "work_id": work_id,
            "state": item["state"], "followup_work_id": followup_id,
            "note": ("Kept. Your reason is on the loop's review card, where the art director "
                     "will answer it. Landing the loop is now her next piece of work."
                     if verdict == "keep" else
                     "Dropped. Your reason is on the loop's review card, where the art director "
                     "will answer it. Nothing was deleted.")}


def start_rework(slug, note, work_id="", review=None, review_path="", decision=None):
    """Send a loop back with an instruction. Same machinery as drawing one, a
    different prompt and the same slug."""
    if not execution.launch_allowed():
        return {"error": "Automatic work is paused", "held": True}
    if len(note) < 12:
        return {"error": "say what should change"}
    if len(note) > 4000:
        return {"error": "that is longer than a rework note should need to be"}
    if any(r.get("state") == "drawing" for r in runs_index()):
        return {"error": "one is already being drawn — they run one at a time so "
                         "they do not fight over the working tree"}
    if not os.path.isfile(_repo(f"{SCRIPTS_DIR}/vfx_{slug}.py")):
        return {"error": f"{slug} has no script to revise"}
    prompt, err = _compose_rework(slug, note)
    if err:
        return {"error": err}
    run_id = f"r{int(time.time())}{os.urandom(2).hex()}"
    rec = _save_run({
        "id": run_id, "subject": note, "state": "drawing", "kind": "rework",
        "slug": slug, "work_item": work_id, "step": "", "turns": 0,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "started_ts": time.time(), "finished": "", "error": "", "cost": None, "note": "",
    })
    try:
        _append_ask(slug, {"at": rec["started"], "kind": "rework", "text": note,
                           "run_id": run_id})
        if review is not None:
            review["state"] = "doing"
            review["result"] = f"Animation Lab rework started: {note}"
            review.setdefault("conversation", []).append(
                {"role": "daniel", "text": note,
                 "at": time.strftime("%Y-%m-%dT%H:%M"), "with": "rework"})
            if decision is not None:
                review.setdefault("anim_verdicts", []).append(decision)
            _write_review(review, review_path)
        threading.Thread(target=_draw, args=(run_id, prompt, slug), daemon=True).start()
    except Exception as exc:
        rec.update(state="failed", finished=time.strftime("%Y-%m-%dT%H:%M:%S"),
                   error=f"could not start rework: {exc}"[:300])
        _save_run(rec)
        if review is not None:
            review["state"] = "for_review"
            review["result"] = rec["error"]
            try:
                _write_review(review, review_path)
            except OSError:
                pass
        return {"error": rec["error"]}
    return {"ok": True, "verdict": "rework", "work_id": work_id,
            "state": "doing", "run": rec}


def _work_slug(item):
    """Explicit on new records; exact route parsing keeps old reviews usable."""
    if item.get("anim_slug"):
        return item["anim_slug"]
    match = re.fullmatch(r"Open #/design/anim/([a-z0-9_]{1,64}) and watch it at both sizes",
                         item.get("first_action") or "")
    return match.group(1) if match else ""


def _review_record(work_id, slug):
    # Older unattended runs filed `wr...` reviews. Keep their in-page verdicts
    # usable; every new review and follow-up now gets a standard work ID.
    if not re.fullmatch(work.WORK_ID, work_id):
        return None, "", "a work item is required for this verdict"
    path = os.path.join(DATA, "work", f"{work_id}.json")
    try:
        item = work.load_item(work_id)
    except (OSError, ValueError):
        return None, path, "that Animation Lab review no longer exists"
    if item.get("id") != work_id or item.get("source") != "anim_lab":
        return None, path, "that work item is not an Animation Lab review"
    if not _judgeable(item):
        return None, path, "that Animation Lab review is no longer awaiting a verdict"
    if _work_slug(item) != slug:
        return None, path, "that work item belongs to a different animation"
    return item, path, None


def _write_review(item, path):
    work.save_item(item)
    _INDEX_CACHE["key"] = None


def _judgeable(item):
    """Waiting for his verdict — including a card parked while its owner owes
    him an answer to something he wrote on it, which is still his to judge."""
    return work._live_state(item) == "for_review"


def _anim_reviews():
    """Every Animation Lab review card, by loop, newest first — one pass over
    the work directory however many loops the page shows."""
    wdir = os.path.join(DATA, "work")
    try:
        names = os.listdir(wdir)
    except OSError:
        return {}
    found = {}
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(wdir, name), encoding="utf-8") as fh:
                text = fh.read()
            if '"anim_lab"' not in text:
                continue
            item = json.loads(text)
        except Exception:
            continue
        slug = _work_slug(item) if item.get("source") == "anim_lab" else ""
        if slug:
            found.setdefault(slug, []).append(item)
    for items in found.values():
        items.sort(key=lambda item: item.get("created_ts") or 0, reverse=True)
    return found


def _active_review_for_slug(slug, reviews=None):
    """Newest exact review identity for the Lab page to send back on verdict."""
    reviews = _anim_reviews() if reviews is None else reviews
    return next((item for item in reviews.get(slug, [])
                 if _judgeable(item) or item.get("state") == "doing"), None)


def _review_summary(item, org=None):
    """What the page shows once a loop has been judged: the verdict he gave, in
    his words, and the owner's answer to it — the same turns the review card's
    conversation holds, so the Lab and the queue tell one story."""
    convo = item.get("conversation") or []
    at = next((n for n in range(len(convo) - 1, -1, -1)
               if convo[n].get("role") == "daniel"
               and convo[n].get("with") in ("accept", "drop", "keep")), None)
    said = convo[at] if at is not None else {}
    answer = next((m for m in convo[at + 1:] if m.get("role") not in ("daniel", "assistant")),
                  None) if at is not None else None
    owner = item.get("owner") or ""
    person = next((e for e in (org or {}).get("employees", []) if e.get("id") == owner), {})
    judged = (item.get("anim_verdicts") or [{}])[-1]
    return {
        "id": item.get("id"), "state": item.get("state"),
        "owner": owner, "owner_name": person.get("name") or owner,
        "verdict": "keep" if item.get("state") == "accepted" else "drop",
        "reason": said.get("text", ""), "at": said.get("at") or item.get("closed", ""),
        "values": judged.get("values"),
        "answer": ({"text": answer.get("text", ""), "at": answer.get("at", "")}
                   if answer else None),
        "awaiting_reply": bool(item.get("awaiting_reply")),
    }


def start_run(payload):
    """Begin drawing a loop from a sentence. Returns immediately; the work
    happens on a thread and the page watches it."""
    if not execution.launch_allowed():
        return {"error": "Automatic work is paused", "held": True}
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
        "id": run_id, "subject": subject, "state": "drawing", "kind": "draw",
        "step": "", "turns": 0, "slug": "",
        "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "started_ts": time.time(), "finished": "", "slug": "",
        "error": "", "cost": None, "note": "",
    })
    threading.Thread(target=_draw, args=(run_id, prompt), daemon=True).start()
    return {"ok": True, "run": rec}


def _step_of(event):
    """One line of a streamed run, phrased the way a person would say it.

    A run is otherwise a black box for its whole life: alive and stuck look
    identical from outside. The tool's own name is jargon — "edit" and a full
    repository path tell you a machine did something, not what is going on — so
    this says it in words instead."""
    if event.get("type") != "assistant":
        return None
    for block in (event.get("message") or {}).get("content") or []:
        if block.get("type") != "tool_use":
            continue
        name = block.get("name") or ""
        arg = block.get("input") or {}
        path = arg.get("file_path") or arg.get("path") or ""
        short = os.path.basename(str(path)) if path else ""
        if name in ("Edit", "Write", "NotebookEdit"):
            return f"editing {short}" if short else "editing a file"
        if name == "Read":
            return f"reading {short}" if short else "reading a file"
        if name in ("Glob", "Grep"):
            pat = " ".join(str(arg.get("pattern") or "").split())[:40]
            return f"searching for {pat}" if pat else "searching the repo"
        if name == "Bash":
            # A heredoc'd script describes nothing; prefer the model's own words.
            desc = " ".join(str(arg.get("description") or "").split())
            return f"running {desc[:52]}" if desc else "running the script"
        return (name or "working").lower()
    return None


def _cost_of(slug):
    """What one loop has cost, across the run that drew it and every rework.

    List price, which is what the CLI reports — not necessarily money that left
    an account. Sliders are free: re-rendering runs the script, not a model."""
    runs = [r for r in runs_index_all() if r.get("slug") == slug and r.get("cost")]
    if not runs:
        return None
    usd = sum(float(r["cost"].get("list_usd") or 0) for r in runs)
    return {
        "runs": len(runs),
        "draws": sum(1 for r in runs if r.get("kind") != "rework"),
        "reworks": sum(1 for r in runs if r.get("kind") == "rework"),
        "list_usd": round(usd, 2),
        "unknown_cost_calls": sum(1 for r in runs if r["cost"].get("list_usd") is None),
        "tokens": sum(int(r["cost"].get("tokens") or 0) for r in runs),
        "fresh": sum(int(r["cost"].get("fresh") or 0) for r in runs),
        "minutes": round(sum(float(r["cost"].get("seconds") or 0) for r in runs) / 60),
    }


def _draw(run_id, prompt, known_slug=""):
    """One drawing or reworking run, on its own thread. Never raises into the
    server. A rework already knows its slug; a first draw learns it from the
    reply, or from whichever loop appeared while it worked."""
    started = time.time()
    try:
        with DRAW_LOCK:
            def on_start(pid):
                rec = _load_run(run_id)
                rec.update(pid=pid, **execution.resolve_model(DRAW_MODEL))
                _save_run(rec)
            def on_event(event):
                step = _step_of(event)
                if step:
                    rec = _load_run(run_id)
                    rec.update(step=step, turns=rec.get("turns", 0) + 1)
                    _save_run(rec)
            result = execution.run_session(prompt, "", DRAW_TOOLS, DRAW_MODEL,
                REPO, DRAW_TIMEOUT, 80, phase="anim-rework" if known_slug else "anim-draw",
                seat="claude", item=known_slug or run_id, on_start=on_start, on_event=on_event)
        if result.get("held"):
            rec = _load_run(run_id)
            rec.update(state="held", error="Automatic work is paused")
            _save_run(rec)
            _reopen_review(rec)
            return
        p = types.SimpleNamespace(returncode=result.get("exit_code") or (1 if result.get("error") else 0),
                                  stderr=result.get("error", ""))
        reply = result.get("text", "")
        cost = result.get("usage")
        if result.get("limited"):
            HOST.note_limit(result.get("error", ""), provider=result["provider"])
        elif not result.get("error"):
            HOST.clear_limit(provider=result["provider"])
        HOST.record_model_usage("anim-rework" if known_slug else "anim-draw",
                                "claude", result["model"], cost, known_slug or run_id)
        slug = known_slug
        m = re.search(r"SLUG:\s*([a-z0-9_]{1,64})", reply)
        if m and not known_slug:
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
        rec = _load_run(run_id)
        if rec.get("state") == "cancelled":
            return                      # somebody stopped it; its record is already written
        ok = p.returncode == 0 and bool(slug)
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
            if not known_slug and not any(
                    e.get('run_id') == run_id for e in asks_for(slug)):
                # A first draw only learns its slug at the end, so its own ask
                # can only be filed under the loop now.
                _append_ask(slug, {'at': rec.get('started', ''), 'kind': 'draw',
                                   'text': rec.get('subject', ''), 'run_id': run_id})
            _file_for_review(rec)
        else:
            _reopen_review(rec)
    except subprocess.TimeoutExpired:
        rec = _load_run(run_id)
        rec.update({"state": "failed", "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "error": f"ran past {DRAW_TIMEOUT // 60} minutes and was stopped"})
        _save_run(rec)
        _reopen_review(rec)
    except Exception as e:
        rec = _load_run(run_id)
        rec.update({"state": "failed", "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "error": f"{type(e).__name__}: {e}"[:300]})
        _save_run(rec)
        _reopen_review(rec)


def cancel_run(payload):
    """Stop a run in flight.

    The only action that makes sense while one is going: its loop cannot be
    judged and cannot be tuned, because the script behind it is being rewritten
    as you look at it. What it leaves behind is whatever the run had written by
    the time it stopped, which may be a half-edited script — so say so rather
    than implying a clean undo."""
    run_id = str(payload.get("run") or "")
    if not re.fullmatch(r"r[0-9a-f]{1,32}", run_id):
        return {"error": "bad run id"}
    rec = _load_run(run_id)
    if rec.get("state") != "drawing":
        return {"error": "that run is not running"}
    pid = rec.get("pid")
    stopped = False
    if pid:
        try:
            os.kill(int(pid), signal.SIGTERM)
            stopped = True
        except (OSError, ValueError, TypeError):
            pass
    if not stopped:
        return {"error": "could not find the process to stop — it may have been started "
                         "before the server last restarted"}
    rec.update({"state": "cancelled", "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "error": "stopped on request"})
    _save_run(rec)
    _reopen_review(rec)
    if rec.get("slug"):
        _append_ask(rec["slug"], {"at": rec["finished"], "kind": "cancelled",
                                  "text": "The rework was stopped before it finished. "
                                          "Whatever it had already written is still on disk.",
                                  "run_id": run_id})
    return {"ok": True, "note": "Stopped. Whatever it had written by then is still on disk, "
                                "so the script may be part-way through an edit."}


def _load_run(run_id):
    try:
        with open(_run_path(run_id), encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {"id": run_id}


def _reopen_review(rec):
    """A failed rework puts its exact review back; it never disappears in doing."""
    work_id = rec.get("work_item") or ""
    if not work_id:
        return
    path = os.path.join(DATA, "work", f"{work_id}.json")
    try:
        with open(path, encoding="utf-8") as fh:
            item = json.load(fh)
        if (item.get("id") != work_id or item.get("source") != "anim_lab"
                or _work_slug(item) != rec.get("slug")):
            return
        item["state"] = "for_review"
        item["result"] = "Animation Lab rework did not finish: " + (rec.get("error") or "unknown error")
        _write_review(item, path)
    except (OSError, ValueError):
        return


def _file_for_review(rec):
    """A finished loop wants a verdict, and a verdict is Daniel's to give — so it
    goes to his queue rather than being announced and forgotten. The art
    director owns whether a loop is good."""
    cost = rec.get("cost") or {}
    spent = cost.get("list_usd")
    bill = (f"It cost ${spent:.2f} and {cost.get('turns', '?')} turns."
            if isinstance(spent, (int, float)) else
            "Its cost was not reported by the CLI.")
    wid = rec.get("work_item") or "w" + uuid.uuid4().hex[:12]
    if rec.get("work_item"):
        path = os.path.join(DATA, "work", f"{wid}.json")
        try:
            with open(path, encoding="utf-8") as fh:
                item = json.load(fh)
            if (item.get("id") != wid or item.get("source") != "anim_lab"
                    or _work_slug(item) != rec["slug"]):
                raise ValueError("review identity does not match this animation")
            item["state"] = "for_review"
            item["result"] = "Animation Lab rework finished and is ready for another verdict."
            item.setdefault("conversation", []).append(
                {"role": "assistant", "text": item["result"],
                 "at": time.strftime("%Y-%m-%dT%H:%M"), "with": "rework_done"})
            _write_review(item, path)
            rec["work_item"] = wid
            _save_run(rec)
            return True
        except (OSError, ValueError) as exc:
            rec["state"] = "failed"
            rec["error"] = f"could not return rework for review: {exc}"
            _save_run(rec)
            _reopen_review(rec)
            return False
    item = _review_item(
        wid, rec["slug"],
        f"The Animation Lab drew a loop from this subject, unattended:\n\n"
        f"    {rec['subject']}\n\n"
        f"It is on the Lab's page as `{rec['slug']}` — play it at true size as well "
        f"as zoomed, and move its instruments to see what the numbers do. {bill}",
        f"Drawn unattended by the Animation Lab from: {rec['subject'][:200]}",
        rec.get("started", ""))
    try:
        path = os.path.join(DATA, "work", f"{wid}.json")
        work.save_item(item)
        rec["work_item"] = wid
        _save_run(rec)
        return True
    except OSError as e:
        rec["state"] = "failed"
        rec["error"] = f"could not file for review: {e}"
        _save_run(rec)
        return False


def _review_item(wid, slug, opening, source_message, started):
    """The card a loop waits on for Daniel's verdict, owned by the art director."""
    name = slug.replace("_", " ")
    return {
        "id": wid,
        "anim_slug": slug,
        "title": f"Say whether the {name} loop is any good",
        # The work title records why this card exists.  The short deliverable
        # name is what the shared review renderer puts after "Review:".
        "deliverable": {"name": f"The {name} animation"},
        "level": "story", "owner": "ingrid", "tier": 2,
        "tier_reason": "A finished loop is waiting on a verdict only Daniel can give.",
        "ask": (
            f"{opening}\n\n"
            "What is wanted is a verdict and a reason: keep it, send it back, or drop "
            "it. The reason is the part that helps whoever picks it up, so it matters "
            "more than the verdict.\n\n"
            "If it is kept, the loop and its script still have to be landed on main; "
            "if it is sent back, say which of its parameters or beats is wrong rather "
            "than that it needs work."
        ),
        "first_action": f"Open #/design/anim/{slug} and watch it at both sizes",
        "state": "for_review", "thread": "ingrid", "source": "anim_lab",
        "source_message": source_message,
        "result": "", "started": started, "attempts": 1,
        "created": time.strftime("%Y-%m-%dT%H:%M"), "created_ts": time.time(),
        "conversation": [],
    }

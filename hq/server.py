#!/usr/bin/env python3
"""Tiny Farm HQ — the CEO's local operating surface.

Zero-dependency stdlib server:
  /                     -> static/index.html (single-page app)
  /static/*             -> static files
  /assets/*             -> game assets from the repo (sprites, audio) for the gallery
  /api/org              -> org chart + personas
  /api/entities         -> entity gallery data
  /api/projects         -> program report (prioritized)
  /api/project/<id>     -> one project
  /api/queue            -> open decision items parsed live from docs/DESIGNER_QUEUE.md
  /api/chat  (POST)     -> {to, message, history} routed through the local `claude` CLI
  /api/health           -> liveness

Run: python3 hq/server.py   (or via the tiny-farm-hq systemd user service)
"""
import json
import os
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

HQ_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HQ_DIR)
STATIC = os.path.join(HQ_DIR, "static")
DATA = os.path.join(HQ_DIR, "data")
PORT = 8642

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".ico": "image/x-icon",
}

CHAT_LOCK = threading.Semaphore(2)  # at most 2 concurrent claude subprocesses


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_org():
    return load_json(os.path.join(DATA, "org.json"))


def load_projects():
    pdir = os.path.join(DATA, "projects")
    projects = [load_json(os.path.join(pdir, f)) for f in sorted(os.listdir(pdir)) if f.endswith(".json")]
    projects.sort(key=lambda p: p.get("priority", 999))
    return projects


def load_dir_json(sub):
    d = os.path.join(DATA, sub)
    if not os.path.isdir(d):
        return []
    return [load_json(os.path.join(d, f)) for f in sorted(os.listdir(d)) if f.endswith(".json")]


QID_RE = re.compile(r"^Q-\d+[a-z]?$")


def record_ruling(payload):
    """Persist a CEO ruling from the decision inbox. Future work sessions pick
    these up (status pending_integration) and fold them into the design docs."""
    qid = str(payload.get("id", ""))
    if not QID_RE.match(qid):
        return {"error": "bad decision id"}
    judgment = str(payload.get("judgment", "")).strip()
    option = str(payload.get("option", "")).strip()
    option_label = str(payload.get("option_label", "")).strip()
    if not judgment and not option:
        return {"error": "pick an option or write a judgment"}
    import datetime
    ruling = {
        "id": qid,
        "option": option or None,
        "option_label": option_label or None,
        "judgment": judgment or None,
        "ruled_at": datetime.datetime.now().isoformat(timespec="seconds"),
        "status": "pending_integration",
    }
    rdir = os.path.join(DATA, "rulings")
    os.makedirs(rdir, exist_ok=True)
    with open(os.path.join(rdir, f"{qid}.json"), "w", encoding="utf-8") as f:
        json.dump(ruling, f, indent=2, ensure_ascii=False)
    with open(os.path.join(rdir, "RULINGS.md"), "a", encoding="utf-8") as f:
        f.write(f"\n## {qid} — ruled {ruling['ruled_at']}\n")
        if option_label:
            f.write(f"- Picked: **({option}) {option_label}**\n")
        if judgment:
            f.write(f"- In his words: {judgment}\n")
        f.write("- Status: pending integration into docs/DESIGNER_QUEUE.md\n")
    return {"ok": True, "ruling": ruling}


def api_queue():
    """Raw queue parse + curated decision cards + any recorded rulings."""
    out = parse_queue()
    out["curated"] = load_dir_json("decisions")
    out["rulings"] = {r["id"]: r for r in load_dir_json("rulings")}
    return out


def check_consistency():
    """Warn (journal-visible) about dangling people/decision references."""
    try:
        ids = {e["id"] for e in load_org()["employees"]}
        for p in load_projects():
            for pid in [p.get("owner")] + list(p.get("contributors", [])):
                if pid and pid not in ids:
                    print(f"[consistency] project {p['id']}: unknown person '{pid}'")
        open_ids = {i["id"] for i in parse_queue()["items"]}
        for c in load_dir_json("decisions"):
            if c["id"] not in open_ids:
                print(f"[consistency] curated decision {c['id']} not found in DESIGNER_QUEUE.md")
    except Exception as e:
        print(f"[consistency] check failed: {e}")


ITEM_RE = re.compile(r"^- \*\*(Q-\d+[a-z]?)\s*(?:\(([^)]*)\))?\*\*\s*(.*)$")


def parse_queue():
    """Parse docs/DESIGNER_QUEUE.md into open/answered decision items."""
    path = os.path.join(REPO, "docs", "DESIGNER_QUEUE.md")
    items = []
    section = ""
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return {"items": [], "error": "DESIGNER_QUEUE.md not found"}
    current = None
    for line in lines:
        if line.startswith("#"):
            section = line.strip("# \n")
            continue
        m = ITEM_RE.match(line.rstrip())
        if m:
            qid, qtype, rest = m.group(1), m.group(2) or "", m.group(3)
            answered = ("~~" in rest) or ("✅" in rest)
            title = rest.replace("~~", "").strip()
            # Trim ruling annotations from the title for display.
            title = re.split(r"—\s*✅", title)[0].strip().rstrip("—").strip()
            title = re.sub(r"\*\*", "", title)
            current = {
                "id": qid,
                "type": qtype,
                "title": title[:220],
                "answered": answered,
                "section": section,
                "body": "",
            }
            items.append(current)
        elif current is not None and (line.startswith("  ") or line.strip() == ""):
            if len(current["body"]) < 1200:
                current["body"] += line.lstrip()
        else:
            current = None
    for it in items:
        it["body"] = it["body"].strip()[:1000]
    return {"items": items}


# ---------- Design Studio: the living GDD, parsed live from docs/ ----------

STATUS_RE = re.compile(r"^\*Status:\s*\**([A-Za-z][A-Za-z -]*[A-Za-z])")
MILESTONE_RE = re.compile(r"^## (M[0-9.]+) — (.+)$")

CORE_DOCS = [
    ("docs/GAME_VISION.md", "The north star — vision, five phases, pillars"),
    ("docs/ROADMAP.md", "Milestones, state of play, standing rules"),
    ("docs/DECISION_LOG.md", "Every decision, tiered: settled / provisional / deferred"),
    ("docs/DESIGNER_QUEUE.md", "The single inbox of things waiting on the CEO"),
    ("docs/ARCHITECTURE.md", "Technical design: the deterministic sim and its layers"),
    ("docs/DEPLOY.md", "The release runbook"),
]


def _doc_meta(rel, blurb=""):
    """Title + maturity status for one markdown doc (first heading, first *Status:* line)."""
    path = os.path.join(REPO, rel)
    title, status = os.path.basename(rel), ""
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if s.startswith("# ") and title == os.path.basename(rel):
                    title = s[2:].strip()
                if not status:
                    m = STATUS_RE.match(s)
                    if m:
                        status = m.group(1).strip().lower()
                    elif s.startswith("*Stub"):
                        status = "stub"
    except OSError:
        return None
    return {"path": rel, "title": title, "status": status, "blurb": blurb}


def _decision_counts():
    """S/P/D tier counts, live from DECISION_LOG.md."""
    try:
        with open(os.path.join(REPO, "docs", "DECISION_LOG.md"), "r", encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return {}
    return {
        "settled": len(re.findall(r"^### S-\d", text, re.M)),
        "provisional": len(re.findall(r"^### P-\d", text, re.M)),
        "deferred": len(re.findall(r"^### D-\d", text, re.M)),
    }


def _milestones():
    """Milestone strip, live from ROADMAP.md headings."""
    try:
        with open(os.path.join(REPO, "docs", "ROADMAP.md"), "r", encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return []
    out = []
    for line in lines:
        m = MILESTONE_RE.match(line.rstrip())
        if m:
            title = re.sub(r"[✅—-]*\s*✅.*$", "", m.group(2)).strip(" —-")
            out.append({"id": m.group(1), "title": title, "done": "✅" in m.group(2)})
    return out


def api_docs():
    """Index of the whole design-doc system, grouped, with live statuses."""
    def listing(sub):
        d = os.path.join(REPO, "docs", sub)
        try:
            names = sorted(f for f in os.listdir(d) if f.endswith(".md") and f != "README.md")
        except OSError:
            return []
        return [m for m in (_doc_meta(f"docs/{sub}/{f}") for f in names) if m]

    groups = [
        {"name": "North star & records", "docs": [m for m in (_doc_meta(p, b) for p, b in CORE_DOCS) if m]},
        {"name": "Design chapters — the living GDD", "docs": listing("design")},
        {"name": "Phase experience docs", "docs": listing("phases")},
    ]
    return {"groups": groups, "decisions": _decision_counts(), "milestones": _milestones()}


def api_doc(rel):
    """One markdown doc, raw, for client-side rendering. Whitelisted to docs/*.md."""
    full = os.path.realpath(os.path.join(REPO, rel))
    droot = os.path.realpath(os.path.join(REPO, "docs"))
    if not (full.startswith(droot + os.sep) and full.endswith(".md") and os.path.isfile(full)):
        return None
    with open(full, "r", encoding="utf-8") as f:
        return {"path": os.path.relpath(full, REPO), "markdown": f.read()}


# ---------------------------------------------------------------------------
# Job runner: long-running verifications (suites, robot session) run in a
# background thread; results persist so freshness survives restarts. This is
# what lets a status say "green as of 12 minutes ago" instead of "trust me".
# ---------------------------------------------------------------------------

JOBS = {
    "unit": {
        "label": "Unit suite",
        "cmd": ["godot", "--headless", "--path", ".", "--script", "res://tests/test_runner.gd"],
        "verdict": re.compile(r"Results:\s*(\d+) PASSED, (\d+) FAILED"),
    },
    "integration": {
        "label": "Integration suite",
        "cmd": ["godot", "--headless", "--path", ".", "res://tools/test_runner.tscn"],
        "verdict": re.compile(r"Results:\s*(\d+) PASSED, (\d+) FAILED"),
    },
    "robot": {
        "label": "Robot session",
        "cmd": ["godot", "--headless", "--path", ".", "res://tools/robot_session.tscn"],
        "verdict": re.compile(r"replay (MATCHES|MISMATCH)"),
    },
    "benchmark": {
        "label": "Sim benchmark",
        "cmd": ["godot", "--headless", "--path", ".", "--script", "res://tools/benchmark_sim.gd"],
        "verdict": re.compile(r"plan gate \(>=\d+x\):\s+(PASS|FAIL)\s+\((\d+)x\)"),
    },
}
_JOB_LOCK = threading.Lock()
_RUNNING_JOBS = set()
# One godot at a time: two engines contending for CPU skews the benchmark and
# slows the suites — queued jobs wait their turn instead.
_GODOT_LOCK = threading.Lock()


def _job_path(job):
    return os.path.join(DATA, "runs", f"{job}.json")


def latest_job_result(job):
    try:
        return load_json(_job_path(job))
    except Exception:
        return None


def _run_job(job):
    import datetime
    spec = JOBS[job]
    started = datetime.datetime.now().isoformat(timespec="seconds")
    result = {"job": job, "label": spec["label"], "state": "failed",
              "summary": "job thread died before running", "started": started}
    try:
        os.makedirs(os.path.join(DATA, "runs"), exist_ok=True)
        with open(_job_path(job), "w", encoding="utf-8") as f:
            json.dump({**result, "state": "running", "summary": ""}, f)
        with _GODOT_LOCK:
            p = subprocess.run(spec["cmd"], cwd=REPO, capture_output=True, text=True, timeout=600,
                               env={**os.environ, "PATH": os.environ.get("PATH", "") + ":" + os.path.expanduser("~/.local/bin")})
        out = (p.stdout or "") + (p.stderr or "")
        m = spec["verdict"].search(out)
        tail = "\n".join(out.strip().splitlines()[-12:])
        # The exit code is the primary verdict for every job: the robot session's
        # FAIL line contains its own success label ("✗ FAIL: ... replay MATCHES
        # its autosave"), so pattern-matching alone can be fooled — the
        # adversarial review caught exactly that. Text only adds detail.
        base_ok = p.returncode == 0
        if job == "robot":
            ok = base_ok and bool(m) and "✗" not in out
            summary = "replay MATCHES its autosave" if ok else "replay verification FAILED"
        elif job == "benchmark":
            ok = base_ok and bool(m and m.group(1) == "PASS")
            summary = f"{int(m.group(2)):,}x realtime (gate ≥100,000x): {m.group(1)}" if m else "no verdict line found"
        else:
            ok = base_ok and bool(m and m.group(2) == "0")
            summary = f"{m.group(1)} passed, {m.group(2)} failed" if m else "no verdict line found"
        if not base_ok and ok is False and m and "FAILED" not in summary:
            summary += f" (exit code {p.returncode})"
        result = {"job": job, "label": spec["label"],
                  "state": "green" if ok else "failed",
                  "summary": summary, "started": started,
                  "finished": datetime.datetime.now().isoformat(timespec="seconds"),
                  "tail": tail}
    except subprocess.TimeoutExpired:
        result = {"job": job, "label": spec["label"], "state": "failed",
                  "summary": "timed out after 10 minutes", "started": started}
    except Exception as e:
        result = {"job": job, "label": spec["label"], "state": "failed",
                  "summary": str(e)[:200], "started": started}
    finally:
        # Everything here is best-effort, and the discard is unconditional:
        # a wedged 'already running' job with no thread behind it is worse
        # than any individual write failing.
        try:
            with open(_job_path(job), "w", encoding="utf-8") as f:
                json.dump(result, f)
        except OSError:
            pass
        with _JOB_LOCK:
            _RUNNING_JOBS.discard(job)
        signals_dirty()


def start_job(job):
    if job not in JOBS:
        return {"error": "unknown job"}
    with _JOB_LOCK:
        if job in _RUNNING_JOBS:
            return {"ok": True, "already": True}
        _RUNNING_JOBS.add(job)
    threading.Thread(target=_run_job, args=(job,), daemon=True).start()
    return {"ok": True, "started": job}


# ---------------------------------------------------------------------------
# Playtest analytics: parses session_trace.jsonl with the game's OWN formulas
# (systems/session_trace.gd / tools/read_trace.gd) — dead = none/unreachable,
# wasted = dead + refused (taps AND failed acts), satisfied never counts
# against her (T-18), stalls are >=8s inter-tap gaps, active time skips >2min
# breaks. Validated against 2026-08-30_221027: 437 taps, wasted 22 (5%).
# ---------------------------------------------------------------------------

def parse_playtest(name):
    tdir = os.path.join(REPO, "playtests", name)
    trace = os.path.join(tdir, "session_trace.jsonl")
    if not os.path.isfile(trace):
        return {"name": name, "error": "no trace"}
    taps, acts = [], []
    header = {}
    dropped = 0
    with open(trace, "r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                dropped += 1
                continue
            if i == 0 and "version" in e and "kind" not in e:
                header = e
                continue
            if e.get("kind") == "tap":
                taps.append(e)
            elif e.get("kind") == "act":
                acts.append(e)
    outcomes = {}
    for t in taps:
        outcomes[t.get("out", "?")] = outcomes.get(t.get("out", "?"), 0) + 1
    dead = outcomes.get("none", 0) + outcomes.get("unreachable", 0)
    refused = outcomes.get("refused", 0) + sum(1 for a in acts if not a.get("ok", True))
    satisfied = outcomes.get("satisfied", 0)
    wasted = dead + refused
    reasons = {}
    for t in taps:
        if t.get("out") == "refused":
            reasons[t.get("why", "?")] = reasons.get(t.get("why", "?"), 0) + 1
    for a in acts:
        if not a.get("ok", True):
            reasons[a.get("why", "?")] = reasons.get(a.get("why", "?"), 0) + 1
    # stalls: consecutive tap-time gaps >= 8s
    stalls, longest = 0, 0
    tt = [t["t"] for t in taps if "t" in t]
    for a, b in zip(tt, tt[1:]):
        gap = b - a
        if gap >= 8000:
            stalls += 1
        longest = max(longest, gap)
    # active time: skip breaks > 2min
    active = sum(min(b - a, 999999) for a, b in zip(tt, tt[1:]) if b - a <= 120000)
    first_use = {}
    for a in acts:
        if a.get("ok") and a.get("actor") == "player" and a.get("verb"):
            first_use.setdefault(a["verb"], a.get("t", 0))
    days = sum(1 for a in acts if a.get("verb") == "sleep" and a.get("ok"))
    # per-minute timeline: ok vs wasted vs satisfied tap counts
    timeline = []
    if tt:
        minutes = int(max(tt) / 60000) + 1
        timeline = [{"ok": 0, "wasted": 0, "satisfied": 0} for _ in range(minutes)]
        for t in taps:
            b = int(t.get("t", 0) / 60000)
            o = t.get("out", "")
            key = "wasted" if o in ("none", "unreachable", "refused") else \
                  "satisfied" if o == "satisfied" else "ok"
            timeline[b][key] += 1
    unknown_outcomes = sum(n for o, n in outcomes.items()
                           if o not in ("none", "walk", "queued", "acted", "refused", "satisfied", "unreachable"))
    mislabelled = sum(1 for t in taps if t.get("out") == "unreachable"
                      and "at" in t and "tile" in t
                      and abs(t["at"][0] - t["tile"][0]) + abs(t["at"][1] - t["tile"][1]) <= 1)
    return {
        "name": name,
        "build_id": _replay_build_id(tdir),
        "gen_seed": header.get("gen_seed") if isinstance(header.get("gen_seed"), int) else None,
        "continued": header.get("continued", False),
        "taps": len(taps),
        "acts": len(acts),
        "outcomes": outcomes,
        "dead": dead, "refused": refused, "satisfied": satisfied,
        "wasted": wasted,
        "wasted_pct": round(100 * wasted / len(taps)) if taps else 0,
        "reasons": reasons,
        "stalls": stalls, "longest_stall_ms": longest,
        "active_ms": active,
        "first_use": first_use,
        "days_played": days,
        "timeline": timeline,
        "mislabelled": mislabelled,
        "dropped_lines": dropped,
        "unknown_outcomes": unknown_outcomes,
    }


def _replay_build_id(tdir):
    try:
        with open(os.path.join(tdir, "session_replay.json"), "r", encoding="utf-8") as f:
            return json.loads(f.readline()).get("build_id", "")
    except Exception:
        return ""


_PT_CACHE = {}


def list_playtests():
    root = os.path.join(REPO, "playtests")
    out = []
    for name in sorted(os.listdir(root), reverse=True) if os.path.isdir(root) else []:
        tdir = os.path.join(root, name)
        if not os.path.isdir(tdir):
            continue
        key = (name, os.path.getmtime(tdir))
        if key not in _PT_CACHE:
            _PT_CACHE[key] = parse_playtest(name)
        out.append(_PT_CACHE[key])
    return out


GAME_CONTEXT = """You work at Tiny Farm Studio. The product is Tiny Farm: a touch-first cozy
farming game in Godot 4, phase 1 of a five-phase arc where the player gradually delegates
farming to machines, towers, and trainable bots (on-device ML in phase 4). It is designed
for pre-readers: no required reading in the core loop, chunky touch targets, no punishing
fail states. The sim is deterministic; every world change goes through one action gateway;
sessions record as replayable logs that double as future ML training data. Design docs live
in docs/ (DECISION_LOG.md, DESIGNER_QUEUE.md, ROADMAP.md, design/). The CEO and Game
Director is Daniel — every taste call terminates with him."""


def build_system_prompt(org, to_id):
    emp = next((e for e in org["employees"] if e["id"] == to_id), None)
    if emp is None or to_id == "daniel":
        emp = next(e for e in org["employees"] if e["id"] == "claude")
    roster = "\n".join(
        f"- {e['name']} — {e['title']} ({e['level']}, {e['team']}): {'; '.join(e['responsibilities'][:2])}"
        for e in org["employees"] if e["id"] not in ("daniel",)
    )
    prompt = f"""{GAME_CONTEXT}

You are {emp['name']}, {emp['title']} ({emp['level']}) on the {emp['team']} team.
Persona: {emp['persona']}
Your responsibilities: {'; '.join(emp['responsibilities'])}

You are chatting with Daniel (CEO & Game Director) inside Tiny Farm HQ, the company's
internal tool. Stay in character as {emp['name']}. Be direct, warm, and useful. Plain
language — no internal ticket IDs or jargon unless he uses them first. Keep replies
conversational and reasonably short unless he asks for depth. You may read the repository
(read-only) to answer questions about the actual state of the game, docs, or code.

If a request belongs to a different member of the team, say so and name them — the full
roster:
{roster}

Never invent facts about the game's state; check the repo or say you're unsure."""
    # Collapse source-code line wraps into flowing paragraphs (single \n -> space);
    # keeps the prompt clean for the CLI and readable in the HQ "what defines them" view.
    return re.sub(r"(?<!\n)\n(?!\n)", " ", prompt)


def png_size(raw):
    """Width/height from a PNG's IHDR chunk."""
    if len(raw) < 24 or not raw.startswith(b"\x89PNG"):
        return None
    return (int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big"))


def save_sprite(payload):
    """Write an edited sprite sheet back into assets/. The browser composites
    edited frames into the full sheet; we validate and persist, backing up the
    original bytes once per day into hq/data/sprite_backups/."""
    import base64
    import datetime
    import shutil
    sheet = str(payload.get("sheet", ""))
    data_url = str(payload.get("data_url", ""))
    full = os.path.realpath(os.path.join(REPO, sheet))
    root = os.path.realpath(os.path.join(REPO, "assets", "sprites"))
    if not (full.startswith(root + os.sep) and full.endswith(".png") and os.path.isfile(full)):
        return {"error": "sheet must be an existing PNG under assets/sprites/"}
    prefix = "data:image/png;base64,"
    if not data_url.startswith(prefix):
        return {"error": "expected a PNG data URL"}
    raw = base64.b64decode(data_url[len(prefix):])
    if len(raw) > 8_000_000 or not raw.startswith(b"\x89PNG"):
        return {"error": "not a plausible PNG"}
    with open(full, "rb") as f:
        old = f.read()
    if png_size(raw) != png_size(old):
        return {"error": f"sheet dimensions changed ({png_size(old)} -> {png_size(raw)}) — refusing"}
    bdir = os.path.join(DATA, "sprite_backups")
    os.makedirs(bdir, exist_ok=True)
    stamp = datetime.date.today().isoformat()
    bak = os.path.join(bdir, f"{os.path.basename(full)}.{stamp}.png")
    if not os.path.exists(bak):
        shutil.copyfile(full, bak)
    with open(full, "wb") as f:
        f.write(raw)
    return {"ok": True, "bytes": len(raw), "backup": os.path.relpath(bak, REPO)}


MAP_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,39}$")


# ---------------------------------------------------------------------------
# Signals: everything on the dashboard is DERIVED — git, CI, files, docs —
# so status can't go stale and "not on fire" is trustworthy.
# ---------------------------------------------------------------------------

_SIG_CACHE = {"at": 0.0, "data": None}
SIG_TTL = 60.0
_SIG_LOCK = threading.Lock()   # single-flight: one recompute at a time
_SIG_VER = [0]                 # bumped when reality changes mid-compute


def signals_dirty():
    """A job finished (or similar): whatever compute is in flight is already
    stale, and the version bump stops it from stamping the cache."""
    _SIG_VER[0] += 1
    _SIG_CACHE["at"] = 0


def run_cmd(args, timeout=10, cwd=REPO):
    try:
        p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.stdout.strip() if p.returncode == 0 else ""
    except Exception:
        return ""


def _git_commits(since, paths=None):
    args = ["git", "log", f"--since={since}", "--pretty=%H"]
    if paths:
        args += ["--"] + list(paths)
    out = run_cmd(args)
    return len([l for l in out.splitlines() if l.strip()])


def _git_last(paths=None, n=5):
    args = ["git", "log", f"-{n}", "--pretty=%h\x1f%ad\x1f%s", "--date=relative"]
    if paths:
        args += ["--"] + list(paths)
    rows = []
    for line in run_cmd(args).splitlines():
        bits = line.split("\x1f")
        if len(bits) == 3:
            rows.append({"hash": bits[0], "when": bits[1], "subject": bits[2]})
    return rows


_CI_LAST = {}


def _ci_status():
    import time as _t
    # Scoped to the tests workflow (a failed release dispatch must not read as
    # red checks) and a 10-run window (rapid pushes must not scroll a red
    # completed run out of sight — the review's scenario).
    out = run_cmd(["gh", "run", "list", "--branch", "main", "--workflow", "tests.yml",
                   "--limit", "10",
                   "--json", "status,conclusion,displayTitle,updatedAt,url"], timeout=20)
    try:
        runs = json.loads(out) if out else []
    except ValueError:
        runs = []
    if not runs and _CI_LAST:
        # Transient gh failure: better a labeled stale answer than a false one.
        return {**_CI_LAST, "stale": True}
    latest = runs[0] if runs else None
    # Green/red reads the newest COMPLETED run, so a push that is still running
    # neither hides an existing red nor claims an unearned green.
    done = next((r for r in runs if r.get("status") == "completed"), None)
    result = {
        "available": bool(runs),
        "latest": latest,
        "has_completed": bool(done),
        "green": bool(done and done.get("conclusion") == "success"),
        "in_progress": bool(latest and latest.get("status") != "completed"),
        "stale": False,
        "polled_at": _t.strftime("%m-%d %H:%M"),
    }
    if done:
        # Only a snapshot that actually carries a verdict is worth falling
        # back on — a completed-free window would poison the stale path.
        _CI_LAST.update(result)
    return result


def _newest(path_glob_dir, exts=None):
    """Newest file (name, age-days) under a directory."""
    best = None
    root = os.path.join(REPO, path_glob_dir)
    if not os.path.isdir(root):
        return None
    for f in os.listdir(root):
        full = os.path.join(root, f)
        if os.path.isfile(full) and (not exts or os.path.splitext(f)[1] in exts):
            m = os.path.getmtime(full)
            if best is None or m > best[1]:
                best = (f, m)
    if best is None:
        return None
    import time as _t
    return {"file": best[0], "age_days": round((_t.time() - best[1]) / 86400, 1)}


def compute_signals():
    import time as _t
    with _SIG_LOCK:
        if _SIG_CACHE["data"] and _t.time() - _SIG_CACHE["at"] < SIG_TTL:
            return _SIG_CACHE["data"]
        ver = _SIG_VER[0]
        data = _compute_signals_now()
        if ver == _SIG_VER[0]:
            _SIG_CACHE["data"] = data
            _SIG_CACHE["at"] = _t.time()
        return data


def _compute_signals_now():
    import time as _t
    pillars = load_json(os.path.join(DATA, "pillars.json"))["pillars"]
    queue = api_queue()
    open_items = [q for q in queue["items"] if not q["answered"]]
    curated_fresh = [c for c in queue["curated"] if c["id"] not in queue["rulings"]]
    pending_rulings = [r for r in queue["rulings"].values()
                       if r.get("status") == "pending_integration"]
    projects = load_projects()
    blocked = [p for p in projects if p["status"] == "blocked"]
    _pt_root = os.path.join(REPO, "playtests")
    sessions = sorted(d for d in os.listdir(_pt_root)
                      if os.path.isdir(os.path.join(_pt_root, d))) \
        if os.path.isdir(_pt_root) else []
    last_session = sessions[-1] if sessions else None
    days_since_session = None
    if last_session:
        import datetime
        try:
            d = datetime.datetime.strptime(last_session.split("_")[0], "%Y-%m-%d")
            days_since_session = (datetime.datetime.now() - d).days
        except ValueError:
            pass
    ci = _ci_status()
    tags = [t for t in run_cmd(["git", "tag", "-l", "v*"]).splitlines() if t]
    suite = latest_job_result("unit")
    job_results = {j: latest_job_result(j) for j in JOBS}
    failed_jobs = [(j, r) for j, r in job_results.items() if r and r.get("state") == "failed"]
    green_jobs = [(j, r) for j, r in job_results.items() if r and r.get("state") == "green"]

    per_pillar = {}
    for p in pillars:
        per_pillar[p["id"]] = {
            "commits_7d": _git_commits("7 days ago", p["git_paths"]),
            "commits_24h": _git_commits("24 hours ago", p["git_paths"]),
            "recent": _git_last(p["git_paths"], 5),
        }

    # Status per pillar: fire > attention > ok > dormant. Reasons are sentences.
    status = {}

    def set_status(pid, level, reasons):
        status[pid] = {"level": level, "reasons": reasons}

    eng_reasons = []
    eng_level = "ok"
    if ci["available"] and ci.get("has_completed") and not ci["green"]:
        eng_level = "fire"
        eng_reasons.append("CI is red on main — the newest completed run failed its checks"
                           + (" (a newer run is still in progress)." if ci["in_progress"] else "."))
    for j, r in failed_jobs:
        eng_level = "fire"
        eng_reasons.append(f"Local {r.get('label', j)} run failed: {r.get('summary', '')} (re-run it on the Engineering page — a loaded machine can skew the benchmark).")
    if not eng_reasons:
        def _age(r):
            fin = r.get("finished", "")
            return f"{fin[5:10]} {fin[11:16]}" if fin else "?"
        fresh = "; ".join(f"{r['label']} {r.get('summary', '')} ({_age(r)})"
                          for _, r in green_jobs[:2])
        if ci["available"] and ci["green"]:
            base = "CI green on main" \
                + (f" (last known verdict, polled {ci.get('polled_at', '?')} — GitHub unreachable just now)" if ci.get("stale") else "") \
                + "; every push runs both suites, the robot session, and the benchmark."
        elif ci["available"] and not ci.get("has_completed"):
            base = "CI runs on the latest pushes are still in progress — no completed verdict yet, no green claimed."
        else:
            base = "CI status unreachable right now — no green claimed; the local runs below are the evidence."
        eng_reasons.append(base + (f" Local: {fresh}." if fresh else ""))
    set_status("engineering", eng_level, eng_reasons)

    # Attention-level notes that must ALSO reach the eye queue: the dashboard
    # claims the queue is complete, so an attention reason that never surfaces
    # there would be a quiet lie (the adversarial review's finding).
    watch_notes = []

    prod_reasons = []
    prod_level = "ok"
    if blocked:
        prod_level = "attention"
        for b in blocked:
            prod_reasons.append(f"'{b['name']}' is blocked: {b['current_status'].split('.')[0]}.")
    if days_since_session is not None and days_since_session > 7:
        prod_level = "attention"
        note = f"No playtest session in {days_since_session} days — the gate re-evidence is waiting on one."
        prod_reasons.append(note)
        watch_notes.append(("product", note))
    if not prod_reasons:
        prod_reasons.append("Nothing blocked; playtest cadence healthy.")
    set_status("product", prod_level, prod_reasons)

    newest_sprite = _newest("assets/sprites/generated", {".png"})
    credits_when = run_cmd(["git", "log", "-1", "--format=%ad", "--date=relative", "--", "CREDITS.md"]) or "unknown"
    set_status("art", "ok", [
        (f"Derived: newest sheet {newest_sprite['file']} ({newest_sprite['age_days']}d old); " if newest_sprite else "")
        + f"CREDITS.md last updated {credits_when}. "
        + "Policy, not auto-checked: assets stay license-clean and ledgered; placeholders by design until the style guide signs."])

    set_status("marketing", "dormant", ["Dormant by your ruling (marketing waits until the game picks up speed). Readiness work is tracked in the program report."])

    sales_level = "ok"
    sales_reasons = []
    if not tags:
        sales_level = "attention"
        note = "No public release tag yet — 'ship early and often' is the standing ruling, and nothing has shipped."
        sales_reasons.append(note)
        watch_notes.append(("sales", note))
    else:
        sales_reasons.append(f"{len(tags)} release tag(s); latest {tags[-1]}.")
    set_status("sales", sales_level, sales_reasons)

    set_status("ops", "ok", [
        f"Derived: CREDITS.md last updated {credits_when}. "
        "Policy, not auto-checked: every asset's rights and cost recorded at landing; no automated spend audit exists yet."])

    # The Eye of Sauron: one ordered queue of what deserves the CEO's look.
    eye = []
    for pid, s in status.items():
        if s["level"] == "fire":
            eye.append({"kind": "fire", "pillar": pid, "text": s["reasons"][0]})
    # One entry per DISTINCT unblocking action (Rin's dedupe rule): projects
    # sharing a blocker merge into one item, and projects blocked on inbox
    # decisions fold into the decisions line instead of echoing it.
    seen_blockers = set()
    decision_blocked = []
    for b in blocked:
        key = str(b.get("blocked_on") or b["id"])
        if key.startswith("decisions:"):
            decision_blocked.append(b)
            continue
        if key in seen_blockers:
            continue
        seen_blockers.add(key)
        siblings = [o["name"] for o in blocked
                    if o["id"] != b["id"] and o.get("blocked_on") == key]
        if b["id"] == "close-m15-gate":
            text = "Recruit one fresh adult playtester — it closes the milestone" \
                + (" and unblocks replay hardening with the same session" if siblings else "") \
                + ". Only you can cast this."
        else:
            text = f"Unblock '{b['name']}'." \
                + (f" The same action frees: {', '.join(siblings)}." if siblings else "")
        eye.append({"kind": "action", "pillar": "product", "text": text,
                    "href": f"#/project/{b['id']}"})
    for pid, note in watch_notes:
        eye.append({"kind": "watch", "pillar": pid, "text": note, "href": f"#/pillar/{pid}"})
    if pending_rulings:
        eye.append({"kind": "info", "pillar": "product",
                    "text": f"{len(pending_rulings)} ruling(s) you recorded await integration by the next work session — no action needed from you.",
                    "href": "#/inbox"})
    if curated_fresh:
        text = f"Rule on {len(curated_fresh)} prepped decision(s) — oldest first: {curated_fresh[0]['id']} ({curated_fresh[0]['title']})."
        if decision_blocked:
            text += " Ruling also unblocks: " + ", ".join(f"'{b['name']}'" for b in decision_blocked) + "."
        eye.append({"kind": "decide", "pillar": "product", "text": text, "href": "#/inbox"})

    data = {
        "generated_at": _t.strftime("%H:%M:%S"),
        "status": status,
        "per_pillar": per_pillar,
        "ci": ci,
        "tags": tags,
        "queue": {"open": len(open_items), "prepped": len(curated_fresh),
                  "pending_integration": len(pending_rulings)},
        "projects": {"total": len(projects), "blocked": len(blocked),
                     "in_progress": len([p for p in projects if p["status"] == "in_progress"])},
        "playtests": {"count": len(sessions), "latest": last_session,
                      "days_since": days_since_session},
        "art": {"newest_sprite": _newest("assets/sprites/generated", {".png"}),
                "sfx_count": len([f for f in os.listdir(os.path.join(REPO, "assets/audio/sfx")) if f.endswith(".wav")])},
        "suite": suite,
        "eye": eye,
    }
    return data


def list_maps():
    mdir = os.path.join(DATA, "maps")
    out = []
    for f in sorted(os.listdir(mdir)) if os.path.isdir(mdir) else []:
        if f.endswith(".json"):
            out.append({"name": f[:-5]})
    return out


def save_map(payload):
    """Save a map layout definition. Maps are the seeded generator's *input*
    (WorldLayout-shaped) — the editor never paints generated worlds. 'default'
    is read-only: its source of truth is systems/world_layout.gd."""
    name = str(payload.get("name", ""))
    doc = payload.get("doc")
    if not MAP_NAME_RE.match(name):
        return {"error": "map name: lowercase letters, digits, - and _ only"}
    existing = os.path.join(DATA, "maps", f"{name}.json")
    if os.path.isfile(existing) and "world_layout.gd" in str(load_json(existing).get("source", "")):
        return {"error": f"'{name}' mirrors systems/world_layout.gd — save under a new name"}
    if not isinstance(doc, dict) or not isinstance(doc.get("layout"), dict):
        return {"error": "doc must carry a layout object"}
    if not isinstance(doc["layout"].get("parcels"), list):
        return {"error": "layout needs a parcels list"}
    mdir = os.path.join(DATA, "maps")
    os.makedirs(mdir, exist_ok=True)
    doc["name"] = name
    with open(os.path.join(mdir, f"{name}.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
    return {"ok": True, "name": name}


def api_persona(pid):
    """The exact system prompt that defines this worker in chat — shown in the UI."""
    org = load_org()
    emp = next((e for e in org["employees"] if e["id"] == pid), None)
    if emp is None:
        return {"error": "no such person"}
    if pid == "daniel":
        return {"id": pid, "system_prompt": None, "note": "The CEO is not a persona — that's you."}
    return {"id": pid, "system_prompt": build_system_prompt(org, pid)}


_STANDUP_LOCK = threading.Lock()


def make_standup():
    """The chief of staff's brief: the live signals handed to the CoS persona,
    who writes what changed, what's under control, and where the eye goes.
    Cached against a fingerprint of the inputs, so it regenerates only when
    reality changed — the right cadence, automatically."""
    import hashlib
    sig = compute_signals()
    projects = load_projects()
    finger_src = json.dumps({"v": 2, "s": sig["status"], "e": sig["eye"], "q": sig["queue"],
                             "p": [(p["id"], p["status"]) for p in projects]}, sort_keys=True)
    finger = hashlib.sha1(finger_src.encode()).hexdigest()[:12]
    spath = os.path.join(DATA, "runs", "standup.json")
    try:
        cached = load_json(spath)
        if cached.get("fingerprint") == finger:
            return cached
    except Exception:
        pass
    with _STANDUP_LOCK:
        # A concurrent regeneration finished while we waited? Serve it.
        try:
            cached = load_json(spath)
            if cached.get("fingerprint") == finger:
                return cached
        except Exception:
            pass
        return _make_standup_locked(finger, spath, sig, projects)


def _make_standup_locked(finger, spath, sig, projects):
    org = load_org()
    sys_prompt = build_system_prompt(org, "claude")
    prompt = f"""Write Daniel's standup brief from this live data (signals derived from the repo/CI just now). Rules:
- Plain language, no internal ticket IDs unless naming a decision he can rule on.
- The dashboard already shows the #1 action in a hero card — do NOT repeat it as a section. Structure: 1) "Since you last looked" — 2-4 bullets of what actually shipped (from the commit subjects). 2) "Under control" — one line per quiet pillar, honest. 3) "Waiting on you" — decisions/approvals, oldest first, one line each.
- Max ~200 words. No preamble, start with the content.

SIGNALS: {json.dumps(sig["status"])}
EYE QUEUE: {json.dumps(sig["eye"])}
RECENT COMMITS BY PILLAR: {json.dumps({k: [c["subject"] for c in v["recent"][:3]] for k, v in sig["per_pillar"].items()})}
QUEUE: {json.dumps(sig["queue"])}
PROJECTS: {json.dumps([{"name": p["name"], "status": p["status"], "priority": p["priority"]} for p in projects])}"""
    cmd = ["claude", "-p", prompt, "--append-system-prompt", sys_prompt,
           "--allowedTools", "", "--max-turns", "3"]
    try:
        with CHAT_LOCK:  # honor the at-most-2-claude-subprocesses invariant
            proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=180,
                                  env={**os.environ, "CLAUDE_CODE_DISABLE_AUTOUPDATE": "1"})
        brief = proc.stdout.strip() if proc.returncode == 0 else ""
    except Exception:
        brief = ""
    if not brief:
        return {"error": "brief generation failed", "fingerprint": finger}
    import datetime
    doc = {"fingerprint": finger, "brief": brief,
           "generated": datetime.datetime.now().isoformat(timespec="minutes")}
    os.makedirs(os.path.join(DATA, "runs"), exist_ok=True)
    with open(spath, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False)
    return doc


def run_chat(payload):
    org = load_org()
    to_id = payload.get("to", "claude")
    message = (payload.get("message") or "").strip()
    history = payload.get("history") or []
    if not message:
        return {"error": "empty message"}
    convo = ""
    for h in history[-12:]:
        who = "Daniel" if h.get("role") == "user" else h.get("name", "Assistant")
        convo += f"{who}: {h.get('text', '')}\n\n"
    convo += f"Daniel: {message}"
    sys_prompt = build_system_prompt(org, to_id)
    cmd = [
        "claude", "-p", convo,
        "--append-system-prompt", sys_prompt,
        "--allowedTools", "Read,Glob,Grep",
        "--max-turns", "12",
    ]
    with CHAT_LOCK:
        try:
            proc = subprocess.run(
                cmd, cwd=REPO, capture_output=True, text=True, timeout=300,
                env={**os.environ, "CLAUDE_CODE_DISABLE_AUTOUPDATE": "1"},
            )
        except subprocess.TimeoutExpired:
            return {"error": "The team member took too long to reply (timeout)."}
        except FileNotFoundError:
            return {"error": "claude CLI not found on PATH for the service user."}
    if proc.returncode != 0:
        return {"error": (proc.stderr or "claude CLI failed").strip()[:500]}
    return {"reply": proc.stdout.strip()}


class Handler(BaseHTTPRequestHandler):
    server_version = "TinyFarmHQ/1.0"

    def log_message(self, fmt, *args):
        pass  # quiet; systemd journal doesn't need per-request noise

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store" if ctype.startswith("application/json") else "max-age=3600")
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, root, rel):
        full = os.path.realpath(os.path.join(root, rel))
        if not full.startswith(os.path.realpath(root) + os.sep) and full != os.path.realpath(root):
            return self._send(403, {"error": "forbidden"})
        if not os.path.isfile(full):
            return self._send(404, {"error": "not found"})
        ext = os.path.splitext(full)[1].lower()
        ctype = MIME.get(ext, "application/octet-stream")
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        # Static app files change with the repo; only heavy game assets are worth caching.
        self.send_header("Cache-Control", "max-age=3600" if root.endswith("assets") else "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        try:
            if path in ("/", "/index.html"):
                return self._send_file(STATIC, "index.html")
            if path.startswith("/static/"):
                return self._send_file(STATIC, path[len("/static/"):])
            if path.startswith("/assets/"):
                return self._send_file(os.path.join(REPO, "assets"), path[len("/assets/"):])
            if path == "/api/org":
                return self._send(200, load_org())
            if path == "/api/entities":
                return self._send(200, load_json(os.path.join(DATA, "entities.json")))
            if path == "/api/projects":
                return self._send(200, load_projects())
            if path.startswith("/api/project/"):
                pid = path[len("/api/project/"):]
                for p in load_projects():
                    if p["id"] == pid:
                        return self._send(200, p)
                return self._send(404, {"error": "no such project"})
            if path == "/api/queue":
                return self._send(200, api_queue())
            if path.startswith("/api/persona/"):
                return self._send(200, api_persona(path[len("/api/persona/"):]))
            if path == "/api/signals":
                return self._send(200, compute_signals())
            if path == "/api/standup":
                # GET returns only what's cached — instant; POST regenerates.
                return self._send(200, latest_job_result("standup") or
                                  (load_json(os.path.join(DATA, "runs", "standup.json"))
                                   if os.path.isfile(os.path.join(DATA, "runs", "standup.json")) else {}))
            if path == "/api/playtests":
                return self._send(200, list_playtests())
            if path == "/api/audio":
                sfx_dir = os.path.join(REPO, "assets", "audio", "sfx")
                music_dir = os.path.join(REPO, "assets", "audio", "music")
                return self._send(200, {
                    "sfx": sorted(f for f in os.listdir(sfx_dir) if f.endswith(".wav")),
                    "music": sorted(f for f in os.listdir(music_dir) if f.endswith((".ogg", ".wav"))),
                })
            if path == "/api/pillars":
                return self._send(200, load_json(os.path.join(DATA, "pillars.json")))
            if path == "/api/runs":
                return self._send(200, {j: latest_job_result(j) for j in JOBS})
            if path.startswith("/api/rootdoc/"):
                name = path[len("/api/rootdoc/"):]
                if name not in ("ITCH_PAGE.md", "CREDITS.md", "README.md"):
                    return self._send(403, {"error": "not whitelisted"})
                with open(os.path.join(REPO, name), "r", encoding="utf-8") as f:
                    return self._send(200, {"path": name, "markdown": f.read()})
            if path == "/api/maps":
                return self._send(200, list_maps())
            if path.startswith("/api/map/"):
                name = path[len("/api/map/"):]
                if not MAP_NAME_RE.match(name):
                    return self._send(400, {"error": "bad map name"})
                mp = os.path.join(DATA, "maps", f"{name}.json")
                if not os.path.isfile(mp):
                    return self._send(404, {"error": "no such map"})
                return self._send(200, load_json(mp))
            if path == "/api/docs":
                return self._send(200, api_docs())
            if path.startswith("/api/doc/"):
                doc = api_doc(unquote(path[len("/api/doc/"):]))
                if doc is None:
                    return self._send(404, {"error": "no such doc"})
                return self._send(200, doc)
            if path == "/api/health":
                return self._send(200, {"ok": True})
            return self._send(404, {"error": "not found"})
        except Exception as e:  # keep the service alive whatever happens
            return self._send(500, {"error": str(e)[:300]})

    def do_POST(self):
        path = self.path.split("?")[0]
        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return self._send(400, {"error": "bad JSON"})
        if path == "/api/standup":
            try:
                return self._send(200, make_standup())
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        if path.startswith("/api/run/"):
            return self._send(200, start_job(path[len("/api/run/"):]))
        if path == "/api/map/save":
            try:
                return self._send(200, save_map(payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        if path == "/api/sprite/save":
            try:
                return self._send(200, save_sprite(payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        if path == "/api/ruling":
            try:
                return self._send(200, record_ruling(payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        if path == "/api/chat":
            try:
                return self._send(200, run_chat(payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        return self._send(404, {"error": "not found"})


def sanitize_runs():
    """A service restart orphans in-flight jobs; their files still say
    'running'. Truth first: mark them interrupted."""
    rdir = os.path.join(DATA, "runs")
    if not os.path.isdir(rdir):
        return
    for f in os.listdir(rdir):
        if not f.endswith(".json"):
            continue
        try:
            doc = load_json(os.path.join(rdir, f))
        except Exception:
            continue
        if doc.get("state") == "running":
            doc["state"] = "failed"
            doc["summary"] = "interrupted by a service restart — run it again"
            with open(os.path.join(rdir, f), "w", encoding="utf-8") as fh:
                json.dump(doc, fh)


def main():
    check_consistency()
    sanitize_runs()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Tiny Farm HQ on http://localhost:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()

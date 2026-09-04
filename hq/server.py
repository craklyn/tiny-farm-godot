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
  /api/chat/queue       -> parked requests + token-limit state (POST enqueues)
  /api/chat/cancel|retry (POST) -> {id} for one parked request
  /api/work             -> work items the org filed from chat (POST: new/approve/accept/drop)
  /api/sprite/save (POST) -> an edited sheet; appends a step to its ledger (studio.py)
  /api/sprite/history   -> ?sheet=<path>: every step that sheet has been through
  /api/sprite/revert (POST) -> {sheet, seq} back to a step; itself recorded as a step
  /ledger/*             -> historical sheet bytes, for the before/after strip
  /api/looks            -> look sheets published to decision cards (Q-86)
  /looks/*              -> the sheet bytes themselves
  /api/deploy           -> live state of the tablet deploy; POST starts one
  /api/deploy/pair (POST) -> {address, code} one-time adb pairing with the tablet
  /api/health           -> liveness

Run: python3 hq/server.py   (or via the tiny-farm-hq systemd user service)
"""
import json
import os
import re
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

import studio  # sibling module: the ledger of hand edits to sprites
import work  # sibling module: how work originates (see its docstring)

HQ_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HQ_DIR)
STATIC = os.path.join(HQ_DIR, "static")
DATA = os.path.join(HQ_DIR, "data")
LOOKS = os.path.join(DATA, "looks")
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


_PROJ_TOUCH_CACHE = {}


def _last_touched(path):
    """When this project's file last changed, per git — honest 'last movement'
    for drift detection. Cached by mtime so the git calls don't repeat."""
    try:
        m = os.path.getmtime(path)
    except OSError:
        return ""
    hit = _PROJ_TOUCH_CACHE.get(path)
    if hit and hit[0] == m:
        return hit[1]
    rel = os.path.relpath(path, REPO)
    when = run_cmd(["git", "log", "-1", "--format=%ad", "--date=relative", "--", rel]) or "uncommitted"
    _PROJ_TOUCH_CACHE[path] = (m, when)
    return when


def load_projects():
    pdir = os.path.join(DATA, "projects")
    projects = []
    for f in sorted(os.listdir(pdir)):
        if not f.endswith(".json"):
            continue
        full = os.path.join(pdir, f)
        p = load_json(full)
        p["last_touched"] = _last_touched(full)
        p["next_step"] = next((s["step"] for s in p.get("plan", []) if not s.get("done")), None)
        projects.append(p)
    projects.sort(key=lambda p: p.get("priority", 999))
    return projects


def api_program():
    """The macro view: release trains composed from project declarations.
    Gates-not-dates on purpose — readiness is done-steps over total-steps on
    the CRITICAL set, and risk is the blocked critical chain, never a date."""
    releases = load_json(os.path.join(DATA, "releases.json"))["releases"]
    projects = load_projects()

    def steps(p):
        plan = p.get("plan", [])
        return sum(1 for s in plan if s.get("done")), len(plan)

    out = []
    for r in releases:
        members = [p for p in projects if p.get("release") == r["id"]]
        critical = [p for p in members if p.get("release_critical")]
        riding = [p for p in members if not p.get("release_critical")]
        done = total = 0
        for p in critical:
            a, b = steps(p)
            done += a
            total += b
        out.append({**r,
                    "critical": [p["id"] for p in critical],
                    "riding": [p["id"] for p in riding],
                    "gating": [p["id"] for p in critical if p["status"] == "blocked"],
                    "readiness": {"done": done, "total": total}})
    assigned = {pid for r in out for pid in r["critical"] + r["riding"]}
    return {"releases": out,
            "unassigned": [p["id"] for p in projects if p["id"] not in assigned]}


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


def load_looks():
    """The look sheets that decision cards can attach (Q-86).

    A look session stages one question in the real game, photographs every draft
    of it and composes a labelled sheet; `tools/compose_look_sheets.py` then
    copies the sheets a card actually cites into `data/looks/<scenario>/`. The
    working captures under `tools/looks/` stay gitignored — what is committed is
    what is attached — so this reads the published copies and never the rig's
    output directory.
    """
    out = {}
    if not os.path.isdir(LOOKS):
        return out
    for name in sorted(os.listdir(LOOKS)):
        doc = os.path.join(LOOKS, name, "look.json")
        if os.path.isfile(doc):
            out[name] = load_json(doc)
    return out


def api_queue():
    """Raw queue parse + curated decision cards + any recorded rulings."""
    out = parse_queue()
    out["curated"] = load_dir_json("decisions")
    out["rulings"] = {r["id"]: r for r in load_dir_json("rulings")}
    return out


_CONSISTENCY = []


def check_consistency():
    """Dangling people, decisions, and goal routes.

    These used to be printed to the journal and nowhere else, which meant a
    broken reference was invisible on the surface that depends on it. They are
    collected now and rendered on the pillar page too: a dashboard that hides
    its own broken references has stopped being trustworthy."""
    warn = []

    def note(msg):
        warn.append(msg)
        print("[consistency] " + msg)

    try:
        ids = {e["id"] for e in load_org()["employees"]}
        for p in load_projects():
            for pid in [p.get("owner")] + list(p.get("contributors", [])):
                if pid and pid not in ids:
                    note(f"project {p['id']}: unknown person '{pid}'")
        open_ids = {i["id"] for i in parse_queue()["items"]}
        published = set(load_looks())
        for c in load_dir_json("decisions"):
            if c["id"] not in open_ids:
                note(f"curated decision {c['id']} not found in DESIGNER_QUEUE.md")
            for att in c.get("attachments", []):
                if att.get("type") == "look" and att.get("scenario") not in published:
                    note(f"decision {c['id']} attaches look '{att.get('scenario')}' "
                         f"but no sheet is published — run tools/compose_look_sheets.py")
        # Goal routes: a red goal whose way back points at nothing is worse than
        # a red goal with no route at all, because it looks answered.
        pools = {"project": {p["id"] for p in load_projects()},
                 "work": {i["id"] for i in (work.items() if hasattr(work, "items") else [])},
                 "decision": {c["id"] for c in load_dir_json("decisions")}}
        pillars = load_json(os.path.join(DATA, "pillars.json"))["pillars"]
        people = {e["id"] for e in load_org()["employees"]}
        for pl in pillars:
            doc = load_goals(pl["id"]) or {}
            for g in doc.get("goals", []):
                if not g.get("measure"):
                    note(f"goal {pl['id']}/{g.get('id')} declares no measurement — "
                         "a statement with no measurement is a wish, not a goal")
                if g.get("owner") and g["owner"] not in people:
                    note(f"goal {pl['id']}/{g.get('id')}: unknown owner '{g['owner']}'")
                p2g = g.get("path_to_green") or {}
                for label, ref in (("route", p2g.get("route")),
                                   ("blocker surface", (p2g.get("ceo_blocker") or {}).get("surface"))):
                    if not ref or ref.get("kind") in (None, "none"):
                        continue
                    if ref.get("id") not in pools.get(ref["kind"], set()):
                        note(f"goal {pl['id']}/{g.get('id')}: {label} points at "
                             f"{ref['kind']} '{ref.get('id')}', which does not exist")
    except Exception as e:
        note(f"check failed: {e}")
    _CONSISTENCY[:] = warn
    return warn


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

# The phase → milestone / phase-native-chapter joins are structural facts of the
# roadmap that change once per phase, not per commit; a hardcoded map beats a
# fragile parse (Milo's rule: don't over-parse what never moves).
PHASE_MILESTONES = {1: ["M1", "M1.5"], 2: ["M3"], 3: ["M4"], 4: ["M5"], 5: ["M6"]}
PHASE_CHAPTERS = {
    1: ["docs/design/02-farming-system.md"],
    2: ["docs/design/03-automation-system.md"],
    3: ["docs/design/05-defense-system.md"],
    4: ["docs/design/06-bots-and-training.md"],
    5: ["docs/design/07-expedition-system.md"],
}
CITE_RE = re.compile(r"\b(?:S|P|D|Q)-\d+\b")


def _read(rel):
    try:
        with open(os.path.join(REPO, rel), "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _doc_meta(rel, blurb=""):
    """Title, maturity status, and git recency for one markdown doc
    (first heading, first *Status:* line, last commit that touched it)."""
    text = _read(rel)
    if not text:
        return None
    title, status = os.path.basename(rel), ""
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("# ") and title == os.path.basename(rel):
            title = s[2:].strip()
        if not status:
            m = STATUS_RE.match(s)
            if m:
                status = m.group(1).strip().lower()
            elif s.startswith("*Stub"):
                status = "stub"
        if status and title != os.path.basename(rel):
            break
    return {"path": rel, "title": title, "status": status, "blurb": blurb,
            "changed": _last_touched(os.path.join(REPO, rel))}


def _decision_counts():
    """S/P/D tier counts, live from DECISION_LOG.md. An entry that files under
    Tier 2/3 but whose body records '✅ Settled' counts as settled (e.g. D-9) —
    the page must never claim more open deferrals than the log actually holds."""
    text = _read("docs/DECISION_LOG.md")
    if not text:
        return {}
    counts = {"settled": 0, "provisional": 0, "deferred": 0}
    tier = {"S": "settled", "P": "provisional", "D": "deferred"}
    for m in re.finditer(r"^### ([SPD])-\d+.*\n((?:(?!^### ).*\n?)*)", text, re.M):
        letter, body = m.group(1), m.group(2)
        if letter != "S" and "✅ Settled" in body:
            counts["settled"] += 1
        else:
            counts[tier[letter]] += 1
    return counts


def _milestones():
    """Milestone list, live from ROADMAP.md: the `## M… — …` headings, plus the
    phase-gated milestones (M5/M6) that live as bullets under 'Phase-gated
    beyond this point' — without them the page claims the game ends at M4."""
    text = _read("docs/ROADMAP.md")
    out, seen = [], set()
    for line in text.splitlines():
        m = MILESTONE_RE.match(line.rstrip())
        if m and m.group(1) not in seen:
            seen.add(m.group(1))
            title = re.sub(r"[✅—-]*\s*✅.*$", "", m.group(2)).strip(" —-")
            out.append({"id": m.group(1), "title": title, "done": "✅" in m.group(2)})
    for m in re.finditer(r"^- \*\*(M[0-9.]+) — ([^:*]+)", text, re.M):
        if m.group(1) not in seen:
            seen.add(m.group(1))
            out.append({"id": m.group(1), "title": m.group(2).strip(), "done": False, "gated": True})
    return out


def _queue_state():
    """Open designer questions, grouped by the milestone horizon they block.

    The answered/open grammar is NOT re-implemented here: it delegates to
    `parse_queue()`, which is canonical. Two parsers meant two counts — this
    page said 21 open questions while the dashboard said 20, because a ruling
    marked ✅ without ~~strikethrough~~ (Q-83) read as open to one and answered
    to the other. One grammar, one number."""
    parsed = parse_queue()["items"]
    order, sections = [], {}
    for it in parsed:
        name = it["section"]
        if name not in sections:
            sections[name] = {"name": name, "open": []}
            order.append(name)
        if not it["answered"]:
            sections[name]["open"].append(it["id"])
    open_ids = {i["id"] for i in parsed if not i["answered"]}
    return {"sections": [sections[n] for n in order if sections[n]["open"]],
            "open": sorted(open_ids)}


def _chapter_blurbs():
    """Per-chapter one-liners from the Covers table in docs/design/README.md —
    written for exactly this purpose, previously unused by the page."""
    out = {}
    for m in re.finditer(r"^\| \S+ \| `(.+?)` \| (.+?) \|", _read("docs/design/README.md"), re.M):
        out[m.group(1)] = m.group(2).strip()
    return out


def _delegation_cells():
    """Per-phase 'what gets delegated away', from the spine table in
    design/01-game-loops.md — the vision's best one-line-per-phase artifact."""
    out = {}
    for m in re.finditer(r"^\| ([1-5]) \|(.+)\|", _read("docs/design/01-game-loops.md"), re.M):
        cells = [c.strip() for c in m.group(2).split("|") if c.strip()]
        if cells and int(m.group(1)) not in out:
            out[int(m.group(1))] = cells[-1]
    return out


def _pitch():
    """The one-sentence pitch, live from GAME_VISION.md."""
    m = re.search(r"^## One-sentence pitch\n+((?:(?!^#).+\n?)+)", _read("docs/GAME_VISION.md"), re.M)
    return " ".join(m.group(1).split()) if m else ""


def _premise(text):
    """The **Premise:** paragraph of a phase doc."""
    m = re.search(r"^\*\*Premise:\*\*\s*((?:.+\n?)+?)(?:\n\s*\n|\Z)", text, re.M)
    return " ".join(m.group(1).split()) if m else ""


def _open_cites(rel, open_qs):
    """Q-items this doc cites that are still open — the 'blocked on' signal."""
    cited = set(CITE_RE.findall(_read(rel)))
    return sorted(q for q in cited if q in open_qs)


def api_docs():
    """Index of the whole design-doc system, grouped, with live statuses,
    recency, open-question joins, and the five-phase rail."""
    queue = _queue_state()
    open_qs = set(queue["open"])
    blurbs = _chapter_blurbs()

    def listing(sub):
        d = os.path.join(REPO, "docs", sub)
        try:
            names = sorted(f for f in os.listdir(d) if f.endswith(".md") and f != "README.md")
        except OSError:
            return []
        docs = []
        for f in names:
            m = _doc_meta(f"docs/{sub}/{f}", blurbs.get(f, ""))
            if m:
                m["open_qs"] = _open_cites(m["path"], open_qs)
                docs.append(m)
        return docs

    milestones = _milestones()
    mile_by_id = {m["id"]: m for m in milestones}
    chapters = {d["path"]: d for d in listing("design")}
    delegation = _delegation_cells()
    phases = []
    phase_docs = {d["path"]: d for d in listing("phases")}
    for n in range(1, 6):
        rel = next((p for p in phase_docs if f"phase-{n}-" in p), None)
        if not rel:
            continue
        meta = phase_docs[rel]
        phases.append({
            "n": n, "path": rel, "title": meta["title"], "status": meta["status"],
            "changed": meta["changed"], "open_qs": meta["open_qs"],
            "premise": _premise(_read(rel)),
            "delegated": delegation.get(n, ""),
            "milestones": [mile_by_id[i] for i in PHASE_MILESTONES.get(n, []) if i in mile_by_id],
            "chapters": [chapters[c] for c in PHASE_CHAPTERS.get(n, []) if c in chapters],
        })

    groups = [
        {"name": "North star & records", "docs": [m for m in (_doc_meta(p, b) for p, b in CORE_DOCS) if m]},
        {"name": "Design chapters — the living GDD", "docs": list(chapters.values())},
    ]
    return {"pitch": _pitch(), "phases": phases, "groups": groups,
            "decisions": _decision_counts(), "milestones": milestones, "queue": queue}


def api_doc(rel):
    """One markdown doc, raw, for client-side rendering, plus its index meta
    (title/status/recency) so a deep-linked doc can identify itself.
    Whitelisted to docs/*.md."""
    full = os.path.realpath(os.path.join(REPO, rel))
    droot = os.path.realpath(os.path.join(REPO, "docs"))
    if not (full.startswith(droot + os.sep) and full.endswith(".md") and os.path.isfile(full)):
        return None
    rel = os.path.relpath(full, REPO)
    meta = _doc_meta(rel) or {}
    with open(full, "r", encoding="utf-8") as f:
        return {"path": rel, "markdown": f.read(), "title": meta.get("title", ""),
                "status": meta.get("status", ""), "changed": meta.get("changed", "")}


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
    # The commit this run proves. Without it "green" has no shelf life: a verdict
    # from 80 commits ago and one from this commit look identical on the page,
    # and freshness is the whole question Engineering's wall answers.
    head = run_cmd(["git", "rev-parse", "HEAD"])
    result = {"job": job, "label": spec["label"], "state": "failed",
              "summary": "job thread died before running", "started": started,
              "head": head}
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
                  "head": head, "tail": tail}
    except subprocess.TimeoutExpired:
        result = {"job": job, "label": spec["label"], "state": "failed",
                  "summary": "timed out after 10 minutes", "started": started,
                  "head": head}
    except Exception as e:
        result = {"job": job, "label": spec["label"], "state": "failed",
                  "summary": str(e)[:200], "started": started, "head": head}
    finally:
        # Everything here is best-effort, and the discard is unconditional:
        # a wedged 'already running' job with no thread behind it is worse
        # than any individual write failing.
        try:
            with open(_job_path(job), "w", encoding="utf-8") as f:
                json.dump(result, f)
        except OSError:
            pass
        append_history("runs", result)
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
# Tablet deploy: build the debug APK and put it on the tablet, from a button.
#
# This is the one surface in HQ that must work with NO model in the loop, which
# is the whole reason it exists: it is for the days the token budget is spent
# and there is nobody to ask what a red line means. So every failure this can
# hit has to answer itself on screen — hence the plain-language hints below,
# the address box, and the pairing form. Wireless debugging turns itself off
# when the tablet reboots and picks a NEW port every time it is toggled, so
# "no device" is the normal failure, not an exotic one, and a dead end there
# would make the button worthless exactly when it is needed.
#
# tools/deploy_android.sh stays the single source of deploy truth (docs/DEPLOY.md
# section 2). This runs it and narrates it; it does not reimplement any of it.
# ---------------------------------------------------------------------------

DEPLOY_SCRIPT = os.path.join(REPO, "tools", "deploy_android.sh")
DEPLOY_FILE = os.path.join(DATA, "runs", "deploy.json")
DEPLOY_TIMEOUT = 1500  # a cold export plus install; generous on purpose
DEPLOY_LOG_LINES = 400
# Both are shell arguments, so they are validated rather than trusted, and the
# messages are what the CEO reads when he mistypes one.
ADDR_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}:\d{1,5}$")
CODE_RE = re.compile(r"^\d{6}$")

_DEPLOY_LOCK = threading.Lock()
_DEPLOY = None  # live state of the running/last deploy this process ran
# Godot's exporter colours its progress lines, and those escapes render as
# literal garbage in an HTML <pre>. Strip them on the way in, so what is stored
# is what a person can read.
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")

# Ordered: the first pattern that matches the output wins, so put the specific
# device faults above the generic "no device".
DEPLOY_HINTS = [
    (re.compile(r"INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match", re.I),
     "The tablet already has a Tiny Farm that was signed with a different key. "
     "Uninstall Tiny Farm on the tablet (long-press the icon \u2192 Uninstall), then press "
     "Deploy again. Nothing is lost that a pulled session hasn't already saved."),
    (re.compile(r"INSTALL_FAILED_INSUFFICIENT_STORAGE", re.I),
     "The tablet is out of space. Free some up on the tablet, then press Deploy again."),
    (re.compile(r"device unauthorized|failed to authenticate", re.I),
     "The tablet has not authorised this computer. Unlock the tablet \u2014 there should be "
     "a permission dialog waiting on it \u2014 accept it, then press Deploy again. If no "
     "dialog appears, pair again using the form below."),
    (re.compile(r"No device\.|failed to connect|cannot connect to|more than one device", re.I),
     "The tablet was not reachable. On the tablet: Settings \u2192 Developer options \u2192 "
     "Wireless debugging \u2192 ON. It shows an \u201cIP address & Port\u201d \u2014 type that into the "
     "address box and press Deploy again. That port changes every single time "
     "wireless debugging is switched on, so a stale one is the usual cause. If it "
     "still will not connect, pair again with the form below."),
    (re.compile(r"No export template|export_templates|Unable to find the Android SDK|"
                r"JAVA_HOME|Android SDK path|keystore", re.I),
     "This is a build-tools problem on this computer, not a tablet problem: the "
     "Android SDK, the JDK or the Godot export templates are missing or moved. "
     "docs/DEPLOY.md section 2 covers the setup. This one genuinely needs a hand."),
    (re.compile(r"adb: (command )?not found|godot: (command )?not found|No such file or directory", re.I),
     "A tool the deploy needs is not on this computer's PATH (adb from the Android "
     "SDK, or godot). Nothing on the tablet needs fixing. docs/DEPLOY.md section 2 "
     "covers the setup."),
]
DEPLOY_HINT_DEFAULT = (
    "The deploy stopped and the reason is not one this page recognises. The last "
    "lines of the log below are the real answer \u2014 they can be pasted verbatim into "
    "a chat here later. The tablet is untouched unless the log says otherwise.")


def _deploy_hint(out, code):
    for pat, hint in DEPLOY_HINTS:
        if pat.search(out):
            return hint
    if code is not None and code < 0:
        return ("The deploy was still running after 25 minutes and was stopped. That "
                "usually means it was waiting on a tablet that never answered. Check "
                "wireless debugging is on, then press Deploy again.")
    return DEPLOY_HINT_DEFAULT


def _deploy_env():
    return {**os.environ,
            "PATH": os.environ.get("PATH", "") + ":" + os.path.expanduser("~/.local/bin")}


def _deploy_write(doc):
    # Best-effort, exactly like the job runner: a failed write must never be
    # what stops a deploy that is otherwise fine.
    try:
        os.makedirs(os.path.join(DATA, "runs"), exist_ok=True)
        with open(DEPLOY_FILE, "w", encoding="utf-8") as f:
            json.dump(doc, f)
    except OSError:
        pass


def _run_deploy(doc, address):
    import datetime
    cmd = [DEPLOY_SCRIPT] + ([address] if address else [])
    code = None
    try:
        # One Godot at a time, same lock the suites take: the export is a full
        # engine run, and a benchmark racing it is neither fast nor honest.
        with _GODOT_LOCK:
            doc["step"] = "Waiting for the other job to finish"
            p = subprocess.Popen(cmd, cwd=REPO, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, bufsize=1,
                                 env=_deploy_env())
            doc["step"] = "Starting"
            # A watchdog, not a deadline checked per line: the way this hangs is
            # adb waiting forever on a tablet that went to sleep, which produces
            # no output at all, so a check that only runs when a line arrives
            # would never fire.
            watchdog = threading.Timer(DEPLOY_TIMEOUT, p.kill)
            watchdog.daemon = True
            watchdog.start()
            try:
                for line in p.stdout:
                    line = ANSI_RE.sub("", line).rstrip("\r\n")
                    doc["log"].append(line)
                    del doc["log"][:-DEPLOY_LOG_LINES]
                    if line.startswith(">>> "):
                        doc["step"] = line[4:]
                        doc["steps"].append(line[4:])
                code = p.wait()
            finally:
                watchdog.cancel()
        out = "\n".join(doc["log"])
        ok = code == 0 and "Installed and launched" in out
        doc["state"] = "green" if ok else "failed"
        doc["summary"] = ("Installed and launched on the tablet \u2014 go and look at it"
                          if ok else
                          "Stopped at: " + (doc.get("step") or "the very start"))
        doc["hint"] = "" if ok else _deploy_hint(out, code)
    except Exception as e:
        doc["state"] = "failed"
        doc["summary"] = "The deploy could not be started"
        doc["hint"] = str(e)[:300]
    finally:
        doc["finished"] = datetime.datetime.now().isoformat(timespec="seconds")
        if doc["state"] == "running":  # belt and braces: never leave it spinning
            doc["state"] = "failed"
        _deploy_write(doc)
        append_history("deploys", {"state": doc["state"], "summary": doc.get("summary", ""),
                                   "started": doc.get("started", "")})


def start_deploy(payload):
    import datetime
    global _DEPLOY
    address = str(payload.get("address") or "").strip()
    if address and not ADDR_RE.match(address):
        return {"error": "That address does not look right. It should read like "
                         "192.168.1.34:37129 \u2014 copy it from the tablet's Wireless "
                         "debugging screen, port included."}
    with _DEPLOY_LOCK:
        if _DEPLOY is not None and _DEPLOY.get("state") == "running":
            return {"ok": True, "already": True}
        doc = {"kind": "deploy", "state": "running", "step": "Starting",
               "steps": [], "log": [], "summary": "", "hint": "",
               "address": address,
               "started": datetime.datetime.now().isoformat(timespec="seconds")}
        _DEPLOY = doc
        _deploy_write(doc)
        threading.Thread(target=_run_deploy, args=(doc, address), daemon=True).start()
    return {"ok": True, "started": True}


def deploy_status():
    if _DEPLOY is not None:
        return _DEPLOY
    if os.path.isfile(DEPLOY_FILE):
        try:
            return load_json(DEPLOY_FILE)
        except Exception:
            pass
    return {"kind": "deploy", "state": "idle", "steps": [], "log": [],
            "summary": "", "hint": ""}


def deploy_pair(payload):
    """Pairing is quick and interactive, so it runs inline and answers straight
    away. It is needed once per machine+device, and again whenever the tablet
    stops recognising this computer."""
    address = str(payload.get("address") or "").strip()
    code = str(payload.get("code") or "").strip()
    if not ADDR_RE.match(address):
        return {"error": "The pairing address should read like 192.168.1.34:41234. "
                         "Use the one in the tablet's \u201cPair device with pairing code\u201d "
                         "box \u2014 it is a DIFFERENT port from the one on the main "
                         "wireless debugging screen."}
    if not CODE_RE.match(code):
        return {"error": "The pairing code is the six digits shown on the tablet right now."}
    try:
        p = subprocess.run([DEPLOY_SCRIPT, "pair", address, code], cwd=REPO,
                           capture_output=True, text=True, timeout=120,
                           env=_deploy_env())
    except subprocess.TimeoutExpired:
        return {"ok": False, "output": "",
                "message": "Pairing timed out. The pairing dialog on the tablet closes "
                           "itself after a while \u2014 open it again for a fresh code and "
                           "address, and try once more."}
    out = ((p.stdout or "") + (p.stderr or "")).strip()
    ok = p.returncode == 0 and "uccessfully paired" in out
    return {"ok": ok, "output": out[-2000:],
            "message": ("Paired. Now copy the IP and port from the main Wireless "
                        "debugging screen into the address box above and press Deploy."
                        if ok else
                        "Pairing failed. The address and the code both come from the "
                        "tablet's pairing dialog while it is open, and both change every "
                        "time it is reopened \u2014 open it again and use the fresh pair.")}


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


def playtest_events(name):
    """The full indexed event stream of one session, for the scrubber: every
    tap and act in file order (chronological — single writer), untouched
    except for an index. Renders only what was recorded; no simulation."""
    tdir = os.path.join(REPO, "playtests", name)
    trace = os.path.join(tdir, "session_trace.jsonl")
    if not os.path.isfile(trace):
        return {"name": name, "error": "no trace"}
    events = []
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
                continue
            if e.get("kind") in ("tap", "act"):
                e["i"] = len(events)
                events.append(e)
    return {"name": name, "events": events, "dropped": dropped}


_PT_CACHE = {}


SHELF_RE = re.compile(r'^\s*"(\d{4}-\d{2}-\d{2}_\d+)"\s*:', re.M)


def shelf_names():
    """The sessions tests/test_runner.gd pins by name.

    A session on the shelf but not in SHELF is *unclassified*: the suite skips
    it and stays green (it is paperwork, not breakage — 2026-09-02), which is
    precisely why it has to surface somewhere Daniel actually looks. Here.
    Parsed rather than duplicated, so the test file stays the single source.
    """
    try:
        with open(os.path.join(REPO, "tests", "test_runner.gd"), encoding="utf-8") as f:
            body = f.read()
    except OSError:
        return None
    start = body.find("const SHELF")
    if start < 0:
        return None
    end = body.find("\n}", start)
    return set(SHELF_RE.findall(body[start:end if end > 0 else None]))


def list_playtests():
    root = os.path.join(REPO, "playtests")
    out = []
    shelf = shelf_names()
    for name in sorted(os.listdir(root), reverse=True) if os.path.isdir(root) else []:
        tdir = os.path.join(root, name)
        if not os.path.isdir(tdir):
            continue
        key = (name, os.path.getmtime(tdir))
        if key not in _PT_CACHE:
            _PT_CACHE[key] = parse_playtest(name)
        # Not cached with the parse: SHELF lives in another file, and editing it
        # does not change this folder's mtime.
        out.append(dict(_PT_CACHE[key],
                        classified=(None if shelf is None else name in shelf)))
    return out


GAME_CONTEXT = """You work at Tiny Farm Studio. The product is Tiny Farm: a touch-first cozy
farming game in Godot 4, phase 1 of a five-phase arc where the player gradually delegates
farming to machines, towers, and trainable bots (on-device ML in phase 4). It is designed
for pre-readers: no required reading in the core loop, chunky touch targets, no punishing
fail states. The sim is deterministic; every world change goes through one action gateway;
sessions record as replayable logs that double as future ML training data. Design docs live
in docs/ (DECISION_LOG.md, DESIGNER_QUEUE.md, ROADMAP.md, design/). The CEO and Game
Director is Daniel — every taste call terminates with him."""


# ---------------------------------------------------------------------------
# What a persona carries between conversations.
#
# Chat used to be amnesiac: each reply was a fresh read-only CLI session, so a
# thing Daniel told Ingrid on Tuesday was gone by Wednesday and nothing filed to
# anyone could be acted on. Two files close that: a memory the persona writes for
# itself, and the work already filed to them by work.py.
# ---------------------------------------------------------------------------

STAFF_MEMORY_MAX = 6000          # tail of the file that rides in the prompt
REMEMBER_RE = re.compile(r"<remember>(.*?)</remember>", re.S | re.I)


def staff_memory_path(pid):
    d = os.path.join(DATA, "staff", pid)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "memory.md")


def load_staff_memory(pid):
    p = staff_memory_path(pid)
    if not os.path.isfile(p):
        return ""
    with open(p, "r", encoding="utf-8") as f:
        return f.read()[-STAFF_MEMORY_MAX:]


def append_staff_memory(pid, note):
    import datetime
    note = " ".join(str(note).split())[:600]
    if not note:
        return
    with open(staff_memory_path(pid), "a", encoding="utf-8") as f:
        f.write(f"- ({datetime.date.today().isoformat()}) {note}\n")


def take_remembered(pid, reply):
    """Personas keep their own notes: anything a reply wraps in <remember> is
    appended to that person's memory file and stripped from what Daniel sees.
    Cheaper than a second model call, and needs no write tools — the CLI these
    replies come from runs read-only on purpose."""
    text = reply or ""
    notes = REMEMBER_RE.findall(text)
    for n in notes:
        append_staff_memory(pid, n)
    return REMEMBER_RE.sub("", text).strip(), len(notes)


def staff_open_work(pid, limit=8):
    """The items work.py has filed to this person and nobody has closed."""
    try:
        return [i for i in work.items()
                if i.get("owner") == pid
                and i.get("state") not in ("accepted", "dropped")][:limit]
    except Exception:
        return []


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

What you agree on here becomes real work without either of you filing anything: HQ reads
every exchange and files the follow-up automatically, owned by whoever it belongs to. So do
not try to carry the work out inside this reply, and never imply it is already done. Say
what should happen and who owns it — that is what gets filed. Reversible work (reading,
drafting, analysing, rendering, running the suites) then starts on its own and Daniel
reviews the result; work that changes the repo goes to a build session; anything hard to
walk back — shipping, spending, deleting, anything players see, any change of design
direction — waits for his yes. He can see all of it on the Work page. Because of that, keep
replies short: answer him, name the next step and its owner, and let the filing happen.

If a request belongs to a different member of the team, say so and name them — the full
roster:
{roster}

Never invent facts about the game's state; check the repo or say you're unsure."""
    # Collapse source-code line wraps into flowing paragraphs (single \n -> space);
    # keeps the prompt clean for the CLI and readable in the HQ "what defines them" view.
    prompt = re.sub(r"(?<!\n)\n(?!\n)", " ", prompt)
    # Appended AFTER the collapse: these are real lists and must keep their lines.
    memory = load_staff_memory(emp["id"])
    if memory.strip():
        prompt += ("\n\nWHAT YOU REMEMBER from earlier conversations and from work you "
                   "have done. These are your own notes, written by you; treat them as "
                   "recollection to check against the repo, not as fact:\n" + memory.strip())
    plate = staff_open_work(emp["id"])
    if plate:
        rows = "\n".join(f"- [{i.get('state', '?')}] {i.get('title', '')} — {i.get('ask', '')[:220]}"
                          for i in plate)
        prompt += ("\n\nON YOUR PLATE right now, filed to you by the studio (say so if he "
                   "asks what you are working on, and use it — this is how things reach "
                   "you when he is not in the room):\n" + rows)
    prompt += ("\n\nTO REMEMBER SOMETHING for next time, end your reply with a "
               "<remember>...</remember> block: one or two sentences of durable, useful "
               "recollection (a standing preference of his, a decision, a pattern you "
               "noticed). It is stripped out before he reads the reply and appended to "
               "your memory. Do not use it for chit-chat or for restating this "
               "conversation — only for what your future self would be worse off not "
               "knowing.")
    return prompt


def png_size(raw):
    """Width/height from a PNG's IHDR chunk."""
    if len(raw) < 24 or not raw.startswith(b"\x89PNG"):
        return None
    return (int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big"))


def save_sprite(payload):
    """Write an edited sheet back into assets/ and append the edit to that sheet's
    ledger (studio.py): every step kept in sequence, with his own one-line answer
    to "what were you fixing?" and the browser's measurement of what moved. The
    step is then filed to the art director as work, so a hand edit reaches the
    people whose job it is to read the pattern instead of dying as a pixel diff.

    The old once-a-day backup is gone — it lost every edit after the first each
    day. Step 0 of the ledger is the pristine sheet, and nothing is overwritten."""
    import base64
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
    if raw == old:
        return {"error": "nothing changed — no step recorded"}
    rec = studio.record(sheet, old, raw, {
        "kind": "edit",
        "group": str(payload.get("group", ""))[:60],
        "entity": str(payload.get("entity", ""))[:60],
        "entity_name": str(payload.get("entity_name", ""))[:80],
        "note": payload.get("note", ""),
        "diff": payload.get("diff") or {},
    })
    with open(full, "wb") as f:
        f.write(raw)
    filed = studio.file_to_art(rec, work, load_org())
    if filed.get("work_id"):
        studio.attach_filing(rec["key"], rec["seq"], filed)
    signals_dirty()
    return {"ok": True, "bytes": len(raw), "step": rec["seq"], "key": rec["key"],
            "summary": studio.describe(rec), "filed": filed}


def revert_sprite(payload):
    """Go back to any step in a sheet's ledger. A revert is itself a step — it
    appends rather than rewinding, so the history stays a straight line and the
    edit he reverted is still there to look at."""
    sheet = str(payload.get("sheet", ""))
    try:
        seq = int(payload.get("seq"))
    except (TypeError, ValueError):
        return {"error": "which step?"}
    full = os.path.realpath(os.path.join(REPO, sheet))
    root = os.path.realpath(os.path.join(REPO, "assets", "sprites"))
    if not (full.startswith(root + os.sep) and full.endswith(".png") and os.path.isfile(full)):
        return {"error": "sheet must be an existing PNG under assets/sprites/"}
    key = studio.sheet_key(sheet)
    want = studio.png_at(key, seq)
    if want is None:
        return {"error": f"no step {seq} for this sheet"}
    with open(full, "rb") as f:
        old = f.read()
    if want == old:
        return {"error": "already at that step"}
    if png_size(want) != png_size(old):
        return {"error": "that step has different dimensions — refusing"}
    rec = studio.record(sheet, old, want, {
        "kind": "revert",
        "reverted_to": seq,
        "group": str(payload.get("group", ""))[:60],
        "entity": str(payload.get("entity", ""))[:60],
        "entity_name": str(payload.get("entity_name", ""))[:80],
        "note": f"Reverted to step {seq}." + (
            f' {str(payload.get("note", "")).strip()}' if payload.get("note") else ""),
        "diff": {},
    })
    with open(full, "wb") as f:
        f.write(want)
    signals_dirty()
    return {"ok": True, "step": rec["seq"], "reverted_to": seq, "key": key}


MAP_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,39}$")


# ---------------------------------------------------------------------------
# History: the recorder.
#
# Every chart HQ will ever draw honestly depends on somebody having written the
# number down at the time. Three of the studio's most interesting quantities —
# how fast the sim runs, how many assertions exist, how often a deploy works —
# have exactly one datapoint each, ever, because `hq/data/runs/` is overwritten
# on every run and gitignored besides. This is the fix, and it is deliberately
# dull: append a line, drop it if nothing changed.
#
# Nothing here is written by a request handler. A tracked file written on page
# render leaves the tree permanently dirty, and `git describe --dirty` is where
# playtest build ids come from — that is exactly how two recorded sessions
# already stamped `-dirty` and became impossible to tie to a build.
# ---------------------------------------------------------------------------

HISTORY = os.path.join(DATA, "history")
_HIST_LOCK = threading.Lock()


def append_history(name, record):
    """Append one JSON line to hq/data/history/<name>.jsonl. Best-effort."""
    import datetime
    try:
        with _HIST_LOCK:
            os.makedirs(HISTORY, exist_ok=True)
            rec = {"at": datetime.datetime.now().isoformat(timespec="seconds"), **record}
            with open(os.path.join(HISTORY, name + ".jsonl"), "a", encoding="utf-8") as f:
                f.write(json.dumps(rec) + "\n")
    except OSError:
        pass


def read_history(name, limit=500):
    rows = []
    try:
        with open(os.path.join(HISTORY, name + ".jsonl"), "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    continue
    except OSError:
        return []
    return rows[-limit:]


# ---------------------------------------------------------------------------
# What the studio's own work costs.
#
# Every model call the company makes on its own — reading an exchange for the
# work it creates, a seat doing a tier-0 task, a build-session worker draining
# the queue — spends the same Claude allotment Daniel spends when he talks to
# HQ. Nothing recorded that. `limits.jsonl` records the moment a five-hour
# window ran dry and never what emptied it, so "is the studio's autonomous work
# eating my allotment?" had no answer at all, let alone one attributed to the
# work that caused it.
#
# One line per call, so a finished result can carry its own price and a window
# can be attributed to the work that spent it. There is no dollar budget to
# report against: this is a subscription, so `list_usd` is what the same tokens
# would have cost at API list price — an order-of-magnitude figure, never a bill.
# The quantity that actually runs out is tokens in a window.
# ---------------------------------------------------------------------------

TOKEN_WINDOW_HOURS = 5.0     # the subscription window; what runs dry is this


def usage_from_cli(doc):
    """The bill for one `claude -p --output-format json` call."""
    u = (doc or {}).get("usage") or {}

    def n(key):
        try:
            return int(u.get(key) or 0)
        except (TypeError, ValueError):
            return 0

    out = {
        "input": n("input_tokens"),
        "output": n("output_tokens"),
        "cache_read": n("cache_read_input_tokens"),
        "cache_write": n("cache_creation_input_tokens"),
        "turns": int((doc or {}).get("num_turns") or 0),
        "seconds": round(((doc or {}).get("duration_ms") or 0) / 1000.0, 1),
        "list_usd": round(float((doc or {}).get("total_cost_usd") or 0.0), 4),
    }
    out["tokens"] = out["input"] + out["output"] + out["cache_read"] + out["cache_write"]
    # Most of a long agent session's tokens are the same context read back from
    # cache on every turn. Both numbers are facts and neither alone is honest:
    # the total is what went through the model, `fresh` is what was new to it.
    out["fresh"] = out["input"] + out["output"] + out["cache_write"]
    return out


def record_model_usage(phase, seat, model, usage, item=""):
    """Append one call to hq/data/history/tokens.jsonl. Best-effort: a failure
    to record must never fail the work it was measuring."""
    if not usage:
        return usage
    append_history("tokens", {"phase": phase, "seat": seat or "", "model": model or "",
                              "item": item or "", **usage})
    return usage


def _fresh_of(row):
    """What was new to the model in this call. Rows recorded before `fresh`
    existed still carry its three parts, so it is derived rather than lost."""
    row = row or {}
    if row.get("fresh"):
        return row["fresh"]
    return (row.get("input") or 0) + (row.get("output") or 0) + (row.get("cache_write") or 0)


def sum_usage(rows):
    """Several calls billed as one result."""
    total = {k: 0 for k in ("input", "output", "cache_read", "cache_write",
                           "tokens", "fresh", "turns")}
    total["seconds"] = 0.0
    total["list_usd"] = 0.0
    for r in rows or []:
        for k in total:
            try:
                total[k] += _fresh_of(r) if k == "fresh" else ((r or {}).get(k) or 0)
            except TypeError:
                pass
    total["calls"] = len(rows or [])
    total["seconds"] = round(total["seconds"], 1)
    total["list_usd"] = round(total["list_usd"], 4)
    return total


def token_window(hours=TOKEN_WINDOW_HOURS):
    """What the studio's own work has spent in the trailing window, and the only
    honest denominator this machine holds: what it had spent in the window that
    last ran dry. A subscription publishes no token cap, so a bar we invented
    would be fiction — but the amount that has actually exhausted a window is a
    measured fact, and it is the number that answers 'are we close?'."""
    import time as _t
    now = _t.time()
    span = hours * 3600.0
    rows = []
    for r in read_history("tokens", 20000):
        ts = _parse_iso(r.get("at"))
        if ts:
            rows.append((ts, r))
    recent = [r for ts, r in rows if now - ts <= span]
    by_phase = {}
    for r in recent:
        p = r.get("phase") or "other"
        by_phase[p] = by_phase.get(p, 0) + (r.get("tokens") or 0)
    # The last time a window ran dry, how much had the studio's own work spent
    # in the five hours before it? Absent that, we have no denominator and say so.
    dry_at, dry_spend = "", None
    for ev in read_history("limits", 500):
        if ev.get("event") != "hit":
            continue
        ts = _parse_iso(ev.get("at"))
        if not ts:
            continue
        spend = sum(r.get("tokens") or 0 for t, r in rows if 0 <= ts - t <= span)
        if spend:
            dry_at, dry_spend = ev.get("at", ""), spend
    return {
        "hours": hours,
        "tokens": sum(r.get("tokens") or 0 for r in recent),
        "fresh": sum(_fresh_of(r) for r in recent),
        "calls": len(recent),
        "list_usd": round(sum(r.get("list_usd") or 0.0 for r in recent), 2),
        "by_phase": by_phase,
        "dry_at": dry_at,
        "dry_spend": dry_spend,
        "recorded_since": (rows[0][1].get("at", "") if rows else ""),
    }


def _parse_iso(text):
    import datetime as _dt
    try:
        return _dt.datetime.fromisoformat(str(text)).timestamp()
    except (TypeError, ValueError):
        return 0.0


# ---------------------------------------------------------------------------
# CI history: the 100-run window, refreshed off the request path.
#
# `_ci_status()` stays at --limit 10 on purpose. Measured on this repo: the gh
# call costs 0.98s at limit 10 and 3.90s at limit 100, against a cold signals
# recompute of ~1.4s — widening the call in the render path would roughly
# triple every post-TTL page visit for a strip nobody is looking at yet.
# ---------------------------------------------------------------------------

CI_HISTORY_PATH = os.path.join(DATA, "ci_history.json")
CI_HISTORY_TTL = 600


def _refresh_ci_history():
    import time as _t
    out = run_cmd(["gh", "run", "list", "--branch", "main", "--workflow", "tests.yml",
                   "--limit", "100", "--json",
                   "status,conclusion,displayTitle,updatedAt,url"], timeout=45)
    if not out:
        return
    try:
        runs = json.loads(out)
    except ValueError:
        return
    done = [r for r in runs if r.get("status") == "completed"]
    streak = 0
    for r in done:
        if r.get("conclusion") == "success":
            streak += 1
        else:
            break
    passed = sum(1 for r in done if r.get("conclusion") == "success")
    doc = {
        "polled_at": _t.strftime("%Y-%m-%dT%H:%M:%S"),
        "window": len(done),
        "passed": passed,
        "failed": len(done) - passed,
        "pass_rate": round(100 * passed / len(done)) if done else None,
        "green_streak": streak,
        # Oldest first, so the strip reads left-to-right like time.
        "ticks": [{"ok": r.get("conclusion") == "success",
                   "title": (r.get("displayTitle") or "")[:80],
                   "at": (r.get("updatedAt") or "")[:10],
                   "url": r.get("url")} for r in reversed(done)],
    }
    try:
        with open(CI_HISTORY_PATH, "w", encoding="utf-8") as f:
            json.dump(doc, f)
    except OSError:
        pass


def ci_history():
    try:
        return load_json(CI_HISTORY_PATH)
    except Exception:
        return None


def _ci_history_thread():
    import time as _t
    while True:
        try:
            _refresh_ci_history()
        except Exception:
            pass
        _t.sleep(CI_HISTORY_TTL)


# ---------------------------------------------------------------------------
# Goals: the one status pipeline.
#
# A pillar's status used to be six hand-written blocks in _compute_signals_now:
# engineering, product and sales derived theirs, art, marketing and ops carried
# hardcoded literals. Two of the six could therefore never light up, and nothing
# on the page distinguished a derived "under control" from a typed one.
#
# Now every pillar declares GOALS in hq/data/goals/<pillar>.json, one evaluator
# reads them, and the pillar's level is the rollup of its goals. The goal's
# statement and its target are AUTHORED — a commitment cannot be derived, and
# pretending otherwise would be the lie. Its current value is MEASURED, by a
# small declarative vocabulary that maps onto things this repo really holds.
#
# The load-bearing honesty rule: a goal nothing can measure does not get to look
# measured. It renders `unchecked` with the reason and the specific recording
# that would make it real, and it counts AGAINST the pillar's assurance
# fraction rather than for it. A measurement that fails to run renders `broken`,
# never green — a broken instrument is a fact about the instrument.
# ---------------------------------------------------------------------------

GOALS_DIR = os.path.join(DATA, "goals")
# Closed enum. Anything that maps a level (LEVEL_META in pillars.js, the nav's
# exception filter, the dashboard rows) must be extended in the same commit.
LEVELS = ("fire", "attention", "unassured", "ok", "dormant")
ASSURED_STATES = ("green", "amber", "red")


def _safe(rel):
    """Repo-relative path, no escapes. Every kind that takes a path calls this,
    which is why no goal file can read /etc/passwd however it is written."""
    if not isinstance(rel, str) or not rel or os.path.isabs(rel):
        raise ValueError(f"path must be repo-relative: {rel!r}")
    full = os.path.normpath(os.path.join(REPO, rel))
    if not (full == REPO or full.startswith(REPO + os.sep)):
        raise ValueError(f"path escapes the repo: {rel!r}")
    return full


def _reading(value, unit="", human="", machine="", cost="cheap", stale=False, error=None, extra=None):
    import time as _t
    r = {"value": value, "unit": unit, "as_of": _t.strftime("%Y-%m-%dT%H:%M:%S"),
         "source_human": human, "source_machine": machine, "cost": cost,
         "stale": stale, "error": error}
    if extra:
        r.update(extra)
    return r


def _iter_files(paths, exts=None, exclude=None):
    exclude = [os.path.normpath(e) for e in (exclude or [])]
    for rel in paths:
        full = _safe(rel)
        if os.path.isfile(full):
            cands = [(rel, full)]
        elif os.path.isdir(full):
            cands = []
            for root, dirs, files in os.walk(full):
                dirs[:] = [d for d in dirs if d not in (".godot", ".git", "__pycache__")]
                for f in files:
                    fp = os.path.join(root, f)
                    cands.append((os.path.relpath(fp, REPO), fp))
        else:
            continue
        for r2, f2 in cands:
            if exts and os.path.splitext(f2)[1] not in exts:
                continue
            if any(os.path.normpath(r2) == e or os.path.normpath(r2).startswith(e + os.sep) or os.path.normpath(r2) == os.path.normpath(e)
                   for e in exclude):
                continue
            yield r2, f2


_BUILD_ID_CACHE = {}


def _norm_build_id(bid):
    """A recorded build id → a commit git can resolve, or None.

    `git describe --always --dirty` produces `v0.1.0-90-g7866bbb-dirty`. The
    `-dirty` suffix is not part of any object name, and the tag-relative form is
    only resolvable while the tag exists — so strip the suffix, try it, and fall
    back to the short hash the description embeds."""
    if not bid or not isinstance(bid, str):
        return None
    if bid in _BUILD_ID_CACHE:
        return _BUILD_ID_CACHE[bid]
    cand = bid[:-6] if bid.endswith("-dirty") else bid
    tries = [cand]
    m = re.search(r"g([0-9a-f]{7,40})$", cand)
    if m:
        tries.append(m.group(1))
    out = None
    for c in tries:
        if subprocess.run(["git", "cat-file", "-e", c + "^{commit}"], cwd=REPO,
                          capture_output=True).returncode == 0:
            out = c
            break
    _BUILD_ID_CACHE[bid] = out
    return out


_PT_CACHE = {"at": 0.0, "data": None}


def _playtests_cached():
    import time as _t
    if _PT_CACHE["data"] and _t.time() - _PT_CACHE["at"] < 60:
        return _PT_CACHE["data"]
    rows = []
    root = os.path.join(REPO, "playtests")
    if os.path.isdir(root):
        for name in sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d))):
            rows.append(parse_playtest(name))
    _PT_CACHE["data"] = rows
    _PT_CACHE["at"] = _t.time()
    return rows


def _pt_select(sel):
    rows = [r for r in _playtests_cached() if not r.get("error")]
    if sel.startswith("id:"):
        want = sel[3:]
        return [r for r in rows if r["name"] == want]
    if sel == "all_with_trace":
        return rows
    if sel == "newest_with_trace":
        return rows[-1:] if rows else []
    if sel == "newest_substantial":
        # 60 taps is the line between a session and a resumed tablet blip. Ten
        # folders, nine traces, six real sessions — the denominator is never
        # "how many directories are there".
        sub = [r for r in rows if r.get("taps", 0) >= 60]
        return sub[-1:] if sub else []
    if sel == "all_substantial":
        return [r for r in rows if r.get("taps", 0) >= 60]
    return rows[-1:] if rows else []


def _days_since_name(name):
    import datetime
    try:
        d = datetime.datetime.strptime(name.split("_")[0], "%Y-%m-%d")
        return (datetime.datetime.now() - d).days
    except (ValueError, TypeError, AttributeError):
        return None


def _pt_metric(row, metric):
    if metric == "days_since":
        return _days_since_name(row["name"])
    if metric.startswith("first_use."):
        return (row.get("first_use") or {}).get(metric.split(".", 1)[1])
    return row.get(metric)


# ---------------------------------------------------------------------------
# The palette instrument.
#
# Art's central question — "is this still one thing to look at?" — has no answer
# in git or in a doc. It is in the pixels, so the pixels are what gets read.
# This decodes the shipped sheets and counts every opaque colour in them, then
# asks how many of the colours the style guide names are still present.
#
# Decoded with zlib and struct rather than an imaging library, because HQ runs
# on the standard library and nothing else, and because the sheets are all 8-bit
# RGBA — the one PNG shape this needs to understand. Cached on the sheets' own
# mtimes: it costs about a second the first time and nothing afterwards.
# ---------------------------------------------------------------------------

PALETTE_SHEETS_DIR = "assets/sprites/generated"
PALETTE_EXTRA = ["assets/sprites/tool_icons.png"]
_PALETTE_CACHE = {"key": None, "data": None}


def _png_rgba(path):
    """Decode an 8-bit RGBA PNG to a flat bytes buffer. Returns (w, h, buf)."""
    import struct
    import zlib
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, w = 8, bytearray(), None
    while pos < len(raw):
        ln = struct.unpack(">I", raw[pos:pos + 4])[0]
        typ = raw[pos + 4:pos + 8]
        body = raw[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype != 6:
                raise ValueError(f"unsupported PNG shape depth={depth} colortype={ctype}")
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
        pos += 12 + ln
    if w is None:
        raise ValueError("no IHDR")
    data = zlib.decompress(bytes(idat))
    stride = w * 4
    out = bytearray(stride * h)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = data[p]
        p += 1
        line = bytearray(data[p:p + stride])
        p += stride
        if ft == 1:
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                b = prev[i]
                c = prev[i - 4] if i >= 4 else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, bytes(out)


def _sheet_paths():
    paths = []
    d = os.path.join(REPO, PALETTE_SHEETS_DIR)
    if os.path.isdir(d):
        paths += [os.path.join(PALETTE_SHEETS_DIR, f) for f in sorted(os.listdir(d))
                  if f.endswith(".png")]
    paths += [p for p in PALETTE_EXTRA if os.path.isfile(os.path.join(REPO, p))]
    return paths


def _guide_named_colours():
    """The hexes the style guide names, in the order it names them."""
    seen, out = set(), []
    for m in re.finditer(r"#([0-9a-fA-F]{6})\b", _read("docs/design/09-art-direction.md")):
        h = m.group(1).lower()
        if h not in seen:
            seen.add(h)
            out.append(h)
    return out


def palette_union():
    """Every opaque colour across the shipped sheets, with its pixel count."""
    paths = _sheet_paths()
    key = tuple((p, os.path.getmtime(os.path.join(REPO, p))) for p in paths)
    if _PALETTE_CACHE["key"] == key:
        return _PALETTE_CACHE["data"]
    counts, failed = {}, []
    for rel in paths:
        try:
            w, h, buf = _png_rgba(os.path.join(REPO, rel))
        except Exception as e:
            failed.append(f"{rel}: {e}")
            continue
        for i in range(0, len(buf), 4):
            if buf[i + 3] < 255:
                continue
            counts[buf[i:i + 3]] = counts.get(buf[i:i + 3], 0) + 1
    named = _guide_named_colours()
    present = {c.hex() for c in counts}
    swatches = sorted(({"hex": c.hex(), "pixels": n, "named": c.hex() in named}
                       for c, n in counts.items()),
                      key=lambda s: -s["pixels"])
    data = {
        "sheets": len(paths) - len(failed), "sheet_names": [os.path.basename(p) for p in paths],
        "failed": failed,
        "colours": len(counts),
        "named_total": len(named),
        "named_present": sum(1 for h in named if h in present),
        "named_missing": [h for h in named if h not in present],
        "swatches": swatches[:140],
    }
    _PALETTE_CACHE["key"] = key
    _PALETTE_CACHE["data"] = data
    return data


# ---------------------------------------------------------------------------
# The release manifest — what a release OFFERS A PLAYER.
#
# Sales was reading a commit count, which is an engineering-internal number: it
# says how much work happened, not what any of it gives anybody. A VP of Sales
# cannot take 177 commits to a player. They take "a shop that sells everything"
# and "robots you buy and teach".
#
# So the release declares its features in the player's language, and each one
# cites the decision or story that carries it. Whether it is actually in the
# public build is then DERIVED, not claimed: trace that id through git either
# side of the newest tag. A feature whose id appears only after the tag is built
# and unshipped — that is inventory Sales is sitting on. One that appears before
# it is already out. One that appears nowhere is promised and not built, and
# saying so is the point: it is the difference between a release plan and a wish.
# ---------------------------------------------------------------------------

_MANIFEST_CACHE = {"head": None, "data": None}


def gate_scorecard():
    """The onboarding gate's scored bars, parsed from the roadmap's own table.

    These were five rows hardcoded in the page's JavaScript — the exact thing
    this whole system exists to prevent. Transcribing a scored table into the
    view means it can never change, cannot say which session produced it, and
    goes quietly stale the moment anybody scores the gate again. It is authored
    data wearing the costume of a measurement.

    The roadmap's table is the real record (it is what the designer attested
    against), so it gets parsed rather than copied, and the session it was scored
    from comes with it so every row can lead somewhere."""
    text = _read("docs/ROADMAP.md")
    m = re.search(r"^\*\*Gate run recorded ([0-9-]+)\.\*\*(.*?)(?=^\*\*[A-Z])", text, re.M | re.S)
    if not m:
        return {"error": "no gate run is recorded in the roadmap"}
    when, body = m.group(1), m.group(2)
    sess = re.search(r"playtests/([0-9_-]+)", body)
    rows = []
    for line in body.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.strip().startswith("|") else []
        if len(cells) != 4 or cells[0] in ("Criterion", "---") or set(cells[0]) <= set("-: "):
            continue
        verdict = cells[3]
        rows.append({
            "criterion": _demd(cells[0]), "bar": _demd(cells[1]),
            "measured": _demd(cells[2]), "verdict": _demd(verdict),
            "met": "✅" in verdict, "void": "void" in verdict.lower(),
        })
    return {"scored_on": when, "session": sess.group(1) if sess else None,
            "bars": rows, "met": sum(1 for r in rows if r["met"]), "total": len(rows)}


def _demd(t):
    """Strip the markdown a table cell carries so a page can print it plainly."""
    return re.sub(r"\*\*|`", "", t).strip()


def release_manifest(release_id=None):
    head = run_cmd(["git", "rev-parse", "HEAD"])
    key = (head, release_id)
    if _MANIFEST_CACHE["head"] == key:
        return _MANIFEST_CACHE["data"]
    doc = load_json(os.path.join(DATA, "releases.json"))
    tags = [t for t in run_cmd(["git", "tag", "-l", "v*", "--sort=creatordate"]).splitlines() if t]
    newest = tags[-1] if tags else None
    out = []
    for r in doc["releases"]:
        if release_id and r["id"] != release_id:
            continue
        feats = []
        for f in r.get("features", []):
            ev = f.get("evidence", "")
            after = before = 0
            landed = []
            if ev:
                rng = f"{newest}..HEAD" if newest else "HEAD"
                rows = run_cmd(["git", "log", rng, "--grep", ev, "--pretty=%h\x1f%s"]).splitlines()
                after = len(rows)
                landed = [{"hash": l.split("\x1f")[0], "subject": l.split("\x1f")[1]}
                          for l in rows if "\x1f" in l][:3]
                if newest:
                    before = len(run_cmd(["git", "log", newest, "--grep", ev,
                                          "--pretty=%h"]).splitlines())
            state = ("ready" if after else "shipped" if before else "not_built")
            # A commit that MENTIONS a decision is not a commit that BUILT it —
            # recording S-10 in the log made the grep read "ready" for a feature
            # with no code behind it at all. So a feature may name the project
            # carrying it, and an unfinished project overrules the git evidence:
            # what we decided and what a player can do are different facts.
            # Structured, not a sentence. The page used to be handed
            # "1 of 5 steps done on A stuck machine says so" — a project's name
            # jammed into a clause with nothing marking where the clause ended,
            # which reads as garbage. The server reports the facts; the page
            # writes the sentence and can make the project's name a link.
            proj_id = f.get("project")
            proj_name = proj_done = proj_total = None
            broken_ref = None
            if proj_id:
                proj = next((x for x in load_projects() if x["id"] == proj_id), None)
                if proj is None:
                    broken_ref = proj_id
                    state = "not_built"
                elif proj["status"] != "done":
                    proj_name = proj["name"]
                    proj_done = sum(1 for st in proj.get("plan", []) if st.get("done"))
                    proj_total = len(proj.get("plan", []))
                    state = "in_progress" if proj_done else "not_built"
                elif proj["status"] == "done":
                    proj_name = proj["name"]
            feats.append({**f, "state": state, "commits": after, "landed": landed,
                          "project": proj_id, "project_name": proj_name,
                          "steps_done": proj_done, "steps_total": proj_total,
                          "broken_ref": broken_ref})
        # Sort so the wall reads as inventory: what we can sell, then what we
        # still owe. Never declaration order.
        rank = {"ready": 0, "in_progress": 1, "not_built": 2, "shipped": 3}
        feats.sort(key=lambda f: rank.get(f["state"], 9))
        ready = [f for f in feats if f["state"] == "ready"]
        out.append({
            "id": r["id"], "name": r["name"], "subtitle": r.get("subtitle", ""),
            "tag_intent": r.get("tag_intent"),
            "goal": r.get("goal", ""), "definition_of_done": r.get("definition_of_done", ""),
            "features": feats,
            "ready": len(ready),
            "shipped": len([f for f in feats if f["state"] == "shipped"]),
            "not_built": len([f for f in feats if f["state"] == "not_built"]),
            "in_progress": len([f for f in feats if f["state"] == "in_progress"]),
            "total": len(feats),
            "since_tag": newest,
        })
    data = {"releases": out, "newest_tag": newest}
    _MANIFEST_CACHE["head"] = key
    _MANIFEST_CACHE["data"] = data
    return data


# ---------------------------------------------------------------------------
# The platform ladder.
#
# The other half of what Sales & Platforms owns. The manifest says what we have
# to sell; this says where we can sell it, and what each storefront we are not
# on yet would actually cost. Each requirement is a real measurement against the
# repo where one is possible and an honest "nobody has established this" where
# it is not — a store account and an age rating are facts about the world, and
# no amount of reading export_presets.cfg will find them.
#
# `pursuing` is deliberately null on the ones nobody has ruled on. The ladder's
# job is to price the next storefront before anyone commits to it, not to imply
# a strategy the CEO has never stated.
# ---------------------------------------------------------------------------

def platform_ladder():
    doc = load_json(os.path.join(DATA, "platforms.json"))
    out = []
    for p in doc["platforms"]:
        reqs = []
        for r in p.get("requirements", []):
            reading = eval_measure(r.get("check") or {})
            if reading.get("unchecked"):
                state = "unknown"
            elif reading.get("error"):
                state = "unknown"
            elif reading.get("value") is True:
                state = "have"
            else:
                state = "missing"
            reqs.append({
                "label": r["label"], "state": state, "note": r.get("note", ""),
                "blocks_publish": r.get("blocks_publish", True),
                "detail": (reading.get("says_true") if reading.get("value") is True
                           else reading.get("says_false")) or reading.get("reason")
                          or reading.get("error") or "",
                "would_need": reading.get("would_need", ""),
            })
        have = sum(1 for r in reqs if r["state"] == "have")
        out.append({**{k: v for k, v in p.items() if k != "requirements"},
                    "requirements": reqs, "have": have, "total": len(reqs),
                    "missing": sum(1 for r in reqs if r["state"] == "missing"),
                    "blocking": sum(1 for r in reqs
                                    if r["state"] == "missing" and r["blocks_publish"]),
                    "unknown": sum(1 for r in reqs if r["state"] == "unknown")})
    return {"platforms": out}


def eval_measure(spec, depth=0):
    """One declarative measurement -> one normalized Reading."""
    kind = (spec or {}).get("kind")
    if depth > 3:
        return _reading(None, error="composite nested too deep")

    if kind == "unchecked":
        return _reading(None, human=spec.get("reason", ""),
                        extra={"unchecked": True,
                               "reason": spec.get("reason", ""),
                               "would_need": spec.get("would_need", "")})

    if kind == "manual_attest":
        import datetime
        who = spec.get("attested_by")
        if who != "daniel":
            # The other org members are personas, not people. A persona cannot
            # vouch for something nothing measured — that would be inventing
            # studio activity, which is the one thing HQ may never do.
            return _reading(None, error="only Daniel may attest; the rest of the org are personas")
        on = spec.get("attested_on", "")
        exp = spec.get("expires_days")
        age = None
        try:
            age = (datetime.datetime.now() - datetime.datetime.strptime(on, "%Y-%m-%d")).days
        except (ValueError, TypeError):
            pass
        expired = bool(exp and age is not None and age > exp)
        return _reading(spec.get("value"), human=f"verified by you on {on}",
                        extra={"attested": True, "attested_by": who, "attested_on": on,
                               "attested_days": age, "expired": expired,
                               "note": spec.get("note", "")})

    try:
        if kind == "git_commits":
            paths = list(spec.get("paths") or [])
            for p in paths:
                _safe(p)
            excl = [f":(exclude){p}" for p in (spec.get("exclude_paths") or [])]
            args = ["git", "log", f"--since={spec.get('since', '7 days ago')}", "--pretty=%H"]
            if paths or excl:
                args += ["--"] + paths + excl
            out = run_cmd(args)
            n = len([l for l in out.splitlines() if l.strip()])
            return _reading(n, "commits", f"commits touching {', '.join(paths) or 'the repo'} since {spec.get('since')}",
                            " ".join(args), "git")

        if kind == "git_file_age":
            rel = spec["path"]
            _safe(rel)
            ct = run_cmd(["git", "log", "-1", "--format=%ct", "--", rel])
            if not ct:
                return _reading(None, error=f"{rel} has no commits")
            import time as _t
            days = round((_t.time() - int(ct)) / 86400, 1)
            return _reading(days, "days", f"{rel} last changed", f"git log -1 -- {rel}", "git")

        if kind == "git_tag":
            pattern = spec.get("pattern", "v*")
            tags = [t for t in run_cmd(["git", "tag", "-l", pattern, "--sort=creatordate"]).splitlines() if t]
            field = spec.get("field", "count")
            if field == "count":
                return _reading(len(tags), "tags", f"tags matching {pattern}", f"git tag -l {pattern}", "git")
            if not tags:
                return _reading(None, error="no tag matches — nothing has ever been published")
            newest = tags[-1]
            import time as _t
            _ct = run_cmd(["git", "log", "-1", "--format=%ct", newest])
            # Daily commit counts since the tag. The strip used to draw a bar
            # whose length was days while the number beside it was commits —
            # two different quantities, nothing saying so. This is the series
            # that makes them one story: the work piling up, day by day, since
            # the last release, against the date the next one is due.
            daily = {}
            for line in run_cmd(["git", "log", f"{newest}..HEAD",
                                 "--date=short", "--pretty=%ad"]).splitlines():
                line = line.strip()
                if line:
                    daily[line] = daily.get(line, 0) + 1
            common = {
                "tag": newest,
                "tag_date": run_cmd(["git", "log", "-1", "--format=%ad", "--date=short", newest]),
                "tag_age_days": round((_t.time() - int(_ct)) / 86400) if _ct else None,
                "commits_since": int(run_cmd(["git", "rev-list", "--count", f"{newest}..HEAD"]) or 0),
                "daily": [{"date": d, "n": n} for d, n in sorted(daily.items())],
            }
            if field == "newest":
                return _reading(newest, "", "the newest published tag", f"git tag -l {pattern}", "git",
                                extra=common)
            if field == "commits_since":
                return _reading(common["commits_since"], "commits",
                                f"commits on main since {newest}",
                                f"git rev-list --count {newest}..HEAD", "git", extra=common)
            if field == "age_days":
                return _reading(round((_t.time() - int(_ct)) / 86400, 1) if _ct else None, "days",
                                f"days since {newest} went out", "git log -1", "git", extra=common)

        if kind == "git_build_lag":
            src = spec.get("build_id_from", "")
            bid = None
            if src.startswith("playtest:"):
                rows = _pt_select(src.split(":", 1)[1])
                bid = rows[0].get("build_id") if rows else None
            elif src.startswith("literal:"):
                bid = src.split(":", 1)[1]
            elif src.startswith("job:"):
                r = latest_job_result(src.split(":", 1)[1]) or {}
                bid = r.get("head")
            if not bid:
                return _reading(None, error="no build id was recorded")
            norm = _norm_build_id(bid)
            if not norm:
                return _reading(None, error=f"the build it was recorded on ({bid}) is not in this history")
            n = run_cmd(["git", "rev-list", "--count", f"{norm}..HEAD"])
            return _reading(int(n or 0), "commits", f"commits between {bid} and what you would ship today",
                            f"git rev-list --count {norm}..HEAD", "git", extra={"build_id": bid})

        if kind == "file_exists":
            there = os.path.isfile(_safe(spec["path"]))
            return _reading(there, "", f"whether {spec['path']} exists", f"stat {spec['path']}",
                            extra={"says_true": f"{spec['path']} is in the repo",
                                   "says_false": f"{spec['path']} does not exist"})

        if kind == "file_count":
            import glob as _glob
            d = _safe(spec.get("dir", "."))
            pat = spec.get("glob")
            if pat:
                n = len(_glob.glob(os.path.join(d, pat), recursive=True))
            else:
                exts = set(spec.get("exts") or [])
                n = sum(1 for _r, f in _iter_files([spec.get("dir", ".")])
                        if not exts or os.path.splitext(f)[1] in exts)
            return _reading(n, spec.get("unit", "files"),
                            f"files under {spec.get('dir')}", "", "cheap")

        if kind == "file_grep":
            rx = re.compile(spec["pattern"])
            hits, files = 0, []
            for rel, full in _iter_files(spec.get("paths") or [], set(spec.get("exts") or []) or None,
                                         spec.get("exclude_paths")):
                try:
                    with open(full, "r", encoding="utf-8", errors="replace") as f:
                        for i, line in enumerate(f, 1):
                            if spec.get("skip_comments") and line.lstrip().startswith("#"):
                                continue
                            if rx.search(line):
                                hits += 1
                                if len(files) < 12:
                                    files.append(f"{rel}:{i}")
                except OSError:
                    continue
            expect = spec.get("expect", "absent")
            if spec.get("field", "bool") == "count":
                val = hits
            else:
                val = (hits == 0) if expect == "absent" else (hits > 0)
            return _reading(val, spec.get("unit", ""),
                            spec.get("label") or f"/{spec['pattern']}/ across {', '.join(spec.get('paths') or [])}",
                            f"grep -rE '{spec['pattern']}'", "cheap",
                            extra={"hits": hits, "where": files,
                                   "unit_plural": spec.get("unit_plural"),
                                   "says_true": spec.get("says_true"),
                                   "says_false": spec.get("says_false")})

        if kind == "orphan_files":
            refs = ""
            for rel in spec.get("referenced_in") or []:
                refs += _read(rel)
            names = []
            for rel, full in _iter_files([spec["dir"]], set(spec.get("exts") or []) or None):
                base = os.path.basename(full)
                if base not in refs:
                    names.append(base)
            total = sum(1 for _r, _f in _iter_files(
                spec.get("count_dirs") or [spec["dir"]], set(spec.get("exts") or []) or None))
            return _reading(len(names), spec.get("unit", "files"),
                            f"files in {spec['dir']} named nowhere in {', '.join(spec.get('referenced_in') or [])}",
                            "", "cheap", extra={"orphans": sorted(names),
                                                "total_shipped": total,
                                                "unit_plural": spec.get("unit_plural")})

        if kind == "ci_state":
            field = spec.get("field", "newest_completed")
            if field in ("newest_completed", "in_progress"):
                ci = _ci_status()
                if not ci.get("available"):
                    return _reading(None, error="GitHub is unreachable right now")
                if field == "in_progress":
                    return _reading(bool(ci.get("in_progress")), "", "whether a run is in flight",
                                    "gh run list --limit 10", "network", stale=ci.get("stale", False))
                if not ci.get("has_completed"):
                    return _reading("in_progress", "verdict",
                                    "the newest finished run of the tests workflow on main",
                                    "gh run list --limit 10", "network", stale=ci.get("stale", False))
                return _reading("success" if ci["green"] else "failure", "verdict",
                                "the newest finished run of the tests workflow on main",
                                "gh run list --limit 10", "network", stale=ci.get("stale", False),
                                extra={"url": (ci.get("latest") or {}).get("url")})
            h = ci_history()
            if not h:
                return _reading(None, error="the 100-run window has not been polled yet")
            import datetime
            stale = False
            try:
                age = (datetime.datetime.now()
                       - datetime.datetime.strptime(h["polled_at"], "%Y-%m-%dT%H:%M:%S")).total_seconds()
                stale = age > CI_HISTORY_TTL * 3
            except (ValueError, KeyError):
                pass
            val = h.get({"pass_rate": "pass_rate", "green_streak": "green_streak"}.get(field, field))
            if val is None:
                return _reading(None, error=f"no such CI field: {field}")
            return _reading(val, "%" if field == "pass_rate" else "runs",
                            f"the last {h.get('window')} finished runs on main",
                            "gh run list --limit 100 (polled off the page)", "cached", stale=stale)

        if kind == "job_state":
            r = latest_job_result(spec["job"])
            field = spec.get("field", "state")
            if not r:
                return _reading("never_run", "verdict", f"the {spec['job']} suite", "", "cheap")
            if field == "state":
                return _reading(r.get("state", "never_run"), "verdict",
                                f"the last local run of {r.get('label', spec['job'])}", "", "cheap",
                                extra={"summary": r.get("summary"), "finished": r.get("finished")})
            if field == "age_commits":
                head = r.get("head")
                if not head:
                    return _reading(None, error="this run did not record the commit it proved")
                n = run_cmd(["git", "rev-list", "--count", f"{head}..HEAD"])
                if n == "":
                    return _reading(None, error="the commit it proved is not in this history")
                return _reading(int(n), "commits",
                                f"commits since {r.get('label', spec['job'])} last ran", "git rev-list", "git")
            if field in ("passed", "failed", "metric"):
                m = re.search(r"([\d,]+)\s+passed" if field == "passed" else
                              r"([\d,]+)\s+failed" if field == "failed" else r"([\d,]+)x",
                              r.get("summary", ""))
                if not m:
                    return _reading(None, error="the run's summary carries no such number")
                return _reading(int(m.group(1).replace(",", "")), field, r.get("summary", ""), "", "cheap")

        if kind == "count_json":
            rows = []
            if spec.get("dir"):
                d = _safe(spec["dir"])
                for f in sorted(os.listdir(d)):
                    if f.endswith(".json"):
                        try:
                            rows.append(load_json(os.path.join(d, f)))
                        except Exception:
                            continue
            elif spec.get("path"):
                doc = load_json(_safe(spec["path"]))
                rows = doc if isinstance(doc, list) else doc.get(spec.get("key", "items"), [])
            matched = [r for r in rows if _where_ok(r, spec.get("where") or [])]
            if spec.get("field") == "bool":
                return _reading(bool(matched), "", spec.get("label", ""), "", "cheap",
                                extra={"says_true": spec.get("label", ""),
                                       "says_false": spec.get("says_false", spec.get("label", ""))})
            return _reading(len(matched), spec.get("unit", "records"),
                            spec.get("label") or f"records in {spec.get('dir') or spec.get('path')}",
                            "", "cheap",
                            extra={"names": [r.get("name") or r.get("id") or r.get("title")
                                             for r in matched][:8],
                                   "unit_plural": spec.get("unit_plural")})

        if kind == "project_field":
            projects = load_projects()
            sel = spec.get("project", "*")
            if sel != "*":
                projects = [p for p in projects if p["id"] == sel]
            projects = [p for p in projects if _where_ok(p, spec.get("where") or [])]
            derive = spec.get("derive")
            field = spec.get("field")
            if derive in ("days_since", "max_days_since"):
                ages = []
                for p in projects:
                    d = _days_since_date(p.get(field))
                    if d is not None:
                        ages.append((d, p))
                if not ages:
                    return _reading(None, "days", "nothing matches — there is nothing to measure",
                                    "", "cheap", extra={"empty_ok": True})
                ages.sort(reverse=True)
                return _reading(ages[0][0], "days",
                                f"the longest any project has held {field}", "", "cheap",
                                extra={"worst": ages[0][1]["name"], "worst_id": ages[0][1]["id"]})
            if derive == "plan_ratio":
                done = sum(1 for p in projects for st in p.get("plan", []) if st.get("done"))
                total = sum(len(p.get("plan", [])) for p in projects)
                return _reading(round(done / total, 3) if total else None, "ratio",
                                "plan steps done over total", "", "cheap",
                                extra={"done": done, "total": total})
            return _reading(len(projects), "projects", "matching projects", "", "cheap")

        if kind == "program_readiness":
            prog = api_program()
            rel = next((r for r in prog["releases"] if r["id"] == spec["release"]), None)
            if not rel:
                return _reading(None, error=f"no release called {spec['release']}")
            field = spec.get("field", "done")
            if field == "gating_count":
                return _reading(len(rel["gating"]), "projects", f"{rel['name']}'s blocked critical work",
                                "", "cheap", extra={"gating": rel["gating"]})
            r = rel["readiness"]
            if field == "ratio":
                return _reading(round(r["done"] / r["total"], 3) if r["total"] else None, "ratio",
                                f"{rel['name']} readiness", "", "cheap", extra=r)
            return _reading(r.get(field), "steps", f"{rel['name']} readiness", "", "cheap", extra=r)

        if kind == "playtest_metric":
            rows = _pt_select(spec.get("select", "newest_with_trace"))
            metric = spec["metric"]
            if metric == "build_resolvable_ratio":
                allr = _pt_select("all_with_trace")
                if not allr:
                    return _reading(None, error="no recorded sessions")
                ok = sum(1 for r in allr if _norm_build_id(r.get("build_id")))
                return _reading(round(ok / len(allr), 3), "ratio",
                                f"{ok} of {len(allr)} recorded sessions can still be tied to a build",
                                "", "cheap", extra={"resolvable": ok, "total": len(allr)})
            if not rows:
                return _reading(None, error="no session matches that selection")
            row = rows[-1]
            val = _pt_metric(row, metric)
            if val is None:
                return _reading(None, error=f"the session records no {metric}")
            return _reading(val, spec.get("unit", ""),
                            f"{metric} in the session of {row['name'][:10]}", "", "cheap",
                            extra={"session": row["name"]})

        if kind == "doc_section":
            text = _read(spec["path"])
            if not text:
                return _reading(None, error=f"{spec['path']} could not be read")
            sec = spec.get("section")
            if sec:
                # A section is a heading OR a bold lead-in paragraph. The roadmap
                # writes its most quotable facts as the latter ("**Gate run
                # recorded 2026-08-31.**"), and a parser that only knows headings
                # would report "no such section" for the one thing worth reading.
                m = re.search(r"^(#{1,6})\s*.*" + re.escape(sec) + r".*$", text, re.M | re.I)
                if m:
                    level = len(m.group(1))
                    rest = text[m.end():]
                    nxt = re.search(r"^#{1," + str(level) + r"}\s", rest, re.M)
                    text = rest[:nxt.start()] if nxt else rest
                else:
                    m = re.search(r"^\*\*.*" + re.escape(sec) + r".*$", text, re.M | re.I)
                    if not m:
                        return _reading(None, error=f"no section matching '{sec}' in {spec['path']}")
                    rest = text[m.end():]
                    nxt = re.search(r"^(#{1,6}\s|\*\*[A-Z])", rest, re.M)
                    text = rest[:nxt.start()] if nxt else rest
            field = spec.get("field", "count")
            if field == "unchecked_count":
                return _reading(len(re.findall(r"^\s*-\s*\[ \]", text, re.M)), "boxes",
                                f"unticked boxes under '{sec}' in {spec['path']}", "", "cheap")
            if field == "bool":
                return _reading(bool(re.search(spec["pattern"], text)), "",
                                f"whether {spec['path']} says so", "", "cheap")
            return _reading(len(re.findall(spec["pattern"], text, re.M)), spec.get("unit", "matches"),
                            spec.get("label") or f"/{spec.get('pattern')}/ in {spec['path']}", "", "cheap")

        if kind == "queue_state":
            parsed = parse_queue()["items"]
            q = api_queue()
            field = spec.get("field", "open")
            if field == "open":
                return _reading(len([i for i in parsed if not i["answered"]]), "questions",
                                "open questions in the designer queue", "", "cheap")
            if field == "prepped":
                return _reading(len([c for c in q["curated"] if c["id"] not in q["rulings"]]),
                                "cards", "decision cards prepped and waiting on you", "", "cheap")
            if field == "pending_rulings":
                return _reading(len([r for r in q["rulings"].values()
                                     if r.get("status") == "pending_integration"]), "rulings",
                                "rulings recorded but not yet worked in", "", "cheap")
            if field == "oldest_pending_days":
                ds = [_days_since_date((r.get("ruled_at") or "")[:10])
                      for r in q["rulings"].values() if r.get("status") == "pending_integration"]
                ds = [d for d in ds if d is not None]
                if not ds:
                    return _reading(None, "days", "nothing is waiting", "", "cheap",
                                    extra={"empty_ok": True})
                return _reading(max(ds), "days", "the oldest ruling still waiting to be worked in",
                                "", "cheap")

        if kind == "probe_cache":
            path = os.path.join(DATA, "probes", spec["probe"] + ".json")
            if not os.path.isfile(path):
                return _reading(None, error="not polled yet — no credential or no poller")
            doc = load_json(path)
            return _reading(doc.get(spec.get("field", "value")), spec.get("unit", ""),
                            doc.get("source_human", spec["probe"]), "", "cached",
                            extra={"polled_at": doc.get("polled_at")})

        if kind == "env_present":
            # Which declared credentials this machine actually has. Reads KEY
            # NAMES only — the line is split at the first '=' and the value is
            # dropped on the floor, never stored, never returned, never logged.
            # This replaces a row of pills where three separate "keys" were all
            # wired to one check for whether .env.example exists: one
            # measurement rendered three times and presented as three facts.
            def _keys(rel):
                out = []
                try:
                    with open(_safe(rel), "r", encoding="utf-8") as f:
                        for line in f:
                            line = line.strip()
                            if not line or line.startswith("#") or "=" not in line:
                                continue
                            out.append(line.split("=", 1)[0].strip())
                except OSError:
                    return None
                return out
            declared = _keys(spec.get("example", ".env.example"))
            if declared is None:
                return _reading(None, error="no .env.example declares what this studio needs")
            have = _keys(spec.get("path", ".env"))
            if have is None:
                return _reading(len(declared), spec.get("unit", "credentials missing on this machine"),
                                "no .env on this machine at all", "", "cheap",
                                extra={"declared": declared, "present": [], "missing": declared})
            missing = [k for k in declared if k not in have]
            return _reading(len(missing), spec.get("unit", "credentials missing on this machine"),
                            f"{len(declared) - len(missing)} of {len(declared)} declared credentials are present",
                            "key names only; no value is ever read", "cheap",
                            extra={"declared": declared, "missing": missing,
                                   "present": [k for k in declared if k in have]})

        if kind == "copy_drift":
            # How many things a player would notice have landed since the store
            # copy was last written. This replaces a check that counted English
            # strings in the build against a bar of zero — which was aimed at the
            # wrong thing entirely: S-7 binds phase 1's *core loop*, not the whole
            # game, and the arc runs to programmable bots that will need words.
            # A game that grows text by design makes the COPY the thing that goes
            # stale, not the build.
            rel = (release_manifest(spec.get("release"))["releases"] or [None])[0]
            if not rel:
                return _reading(None, error=f"no release called {spec.get('release')}")
            copy_ct = run_cmd(["git", "log", "-1", "--format=%ct", "--", spec["path"]])
            if not copy_ct:
                return _reading(None, error=f"{spec['path']} has no commits")
            copy_ct = int(copy_ct)
            stale = []
            for f in rel["features"]:
                for c in f.get("landed", []):
                    ct = run_cmd(["git", "log", "-1", "--format=%ct", c["hash"]])
                    if ct and int(ct) > copy_ct:
                        stale.append(f["headline"])
                        break
            return _reading(len(stale), spec.get("unit", "features the page has never mentioned"),
                            f"features that landed since {spec['path']} was last written",
                            "git log -1 per landing commit", "git",
                            extra={"stale": stale[:8], "copy_path": spec["path"]})

        if kind == "platform_ladder":
            lad = platform_ladder()["platforms"]
            live = [p for p in lad if p.get("live")]
            field = spec.get("field", "shippable")
            if field == "live_are_shippable":
                # Anything we claim to be live on, we must actually be able to
                # ship to. A storefront we cannot publish to is worse than one
                # we are not on: it looks like a channel and is not.
                # Only what actually stops a build reaching a player. Counting
                # everything we would merely like made a live, perfectly
                # publishable storefront read as broken.
                broken = [p for p in live if p["blocking"]]
                return _reading(len(broken), spec.get("unit", "live storefronts we can no longer publish to"),
                                f"{len(live)} storefront(s) live", "", "cheap",
                                extra={"broken": [p["name"] for p in broken]})
            if field == "live_count":
                return _reading(len(live), "storefronts a player can reach us on",
                                "platforms marked live", "", "cheap")
            return _reading(None, error=f"no such platform field: {field}")

        if kind == "release_manifest":
            m = release_manifest(spec.get("release"))
            rel = (m["releases"] or [None])[0]
            if not rel:
                return _reading(None, error=f"no release called {spec.get('release')}")
            field = spec.get("field", "ready")
            if field == "traceable":
                # Every feature we claim has to resolve to something in the
                # history. One that resolves to nothing is a claim, not a feature.
                n = rel["ready"] + rel["shipped"]
                return _reading(round(n / rel["total"], 3) if rel["total"] else None, "ratio",
                                f"{n} of {rel['total']} declared features can be traced to the build",
                                "git log --grep per feature", "git",
                                extra={"numerator": n, "denominator": rel["total"]})
            if field == "declared":
                return _reading(rel["total"], "features a player would notice",
                                f"what {rel['name']} says it offers", "", "cheap")
            return _reading(rel.get(field), spec.get("unit", "features"),
                            f"{rel['name']}: {field}", "", "git", extra=rel)

        if kind == "palette_named_present":
            pal = palette_union()
            if not pal["named_total"]:
                return _reading(None, error="the style guide names no colours")
            return _reading(round(pal["named_present"] / pal["named_total"], 3), "ratio",
                            f"{pal['named_present']} of {pal['named_total']} colours the guide names "
                            f"are still somewhere in the {pal['sheets']} shipped sheets",
                            "decoded from the PNGs", "cached",
                            extra={"numerator": pal["named_present"],
                                   "denominator": pal["named_total"],
                                   "missing": pal["named_missing"]})

        if kind == "composite":
            members = [eval_measure(m, depth + 1) for m in (spec.get("members") or [])]
            op = spec.get("op", "worst_of")
            if op == "ratio":
                if len(members) != 2:
                    return _reading(None, error="a ratio needs exactly two members")
                n, d = members[0]["value"], members[1]["value"]
                if not d:
                    return _reading(None, error="the denominator is zero")
                return _reading(round(n / d, 3), "ratio", spec.get("label", ""), "", "cheap",
                                extra={"numerator": n, "denominator": d})
            return _reading(None, "", spec.get("label", ""), "", "cheap",
                            extra={"members": members, "op": op})

        return _reading(None, error=f"no such measurement kind: {kind!r}")
    except Exception as e:
        return _reading(None, error=f"{type(e).__name__}: {str(e)[:160]}")


def _where_ok(row, clauses):
    for field, op, want in clauses:
        got = row
        for part in field.split("."):        # dotted paths reach nested records
            got = got.get(part) if isinstance(got, dict) else None
        if op == "eq" and got != want:
            return False
        if op == "ne" and got == want:
            return False
        if op == "in" and got not in want:
            return False
        if op == "contains" and (not isinstance(got, (list, str)) or want not in got):
            return False
        if op == "empty":
            isempty = got in (None, "", [], {})
            if isempty != bool(want):
                return False
        if op in ("lt", "lte", "gt", "gte"):
            try:
                if op == "lt" and not got < want:
                    return False
                if op == "lte" and not got <= want:
                    return False
                if op == "gt" and not got > want:
                    return False
                if op == "gte" and not got >= want:
                    return False
            except TypeError:
                return False
    return True


def _days_since_date(datestr):
    import datetime
    try:
        return (datetime.datetime.now()
                - datetime.datetime.strptime(str(datestr)[:10], "%Y-%m-%d")).days
    except (ValueError, TypeError):
        return None


def _state_from(reading, compare):
    """Reading + the authored bar -> one of the six goal states.

    The two rules that matter: a reading that errored is `broken`, never green —
    a failed measurement is a fact about the instrument, not a pass. And an
    absence is only green where absence genuinely is the answer (no blocked
    projects means nothing has been stuck), which the reading has to say for
    itself via empty_ok."""
    if reading.get("unchecked"):
        return "unchecked"
    if reading.get("attested"):
        return "unchecked" if reading.get("expired") else "attested"
    if reading.get("error"):
        return "broken"
    v = reading.get("value")
    if v is None:
        return "green" if reading.get("empty_ok") else "broken"
    d = (compare or {}).get("direction")
    t, a = (compare or {}).get("target"), (compare or {}).get("amber_at")
    try:
        if d in ("higher_is_better",):
            if v >= t:
                return "green"
            return "amber" if (a is not None and v >= a) else "red"
        if d in ("lower_is_better", "fresher_than"):
            if v <= t:
                return "green"
            return "amber" if (a is not None and v <= a) else "red"
        if d == "must_be_true":
            return "green" if v is True else "red"
        if d == "must_equal":
            return "green" if v == t else "red"
        if d == "in_set":
            if v in (compare.get("green_set") or []):
                return "green"
            if v in (compare.get("amber_set") or []):
                return "amber"
            return "red"
        if d == "ratio":
            if v >= t:
                return "green"
            return "amber" if (a is not None and v >= a) else "red"
    except TypeError:
        return "broken"
    return "broken"


_STATE_RANK = {"red": 0, "broken": 1, "amber": 2, "unchecked": 3, "attested": 4, "green": 5}


def _composite_state(reading, compare):
    """A composite's state is a fact about its members, and the honest rule is
    that an unassured member poisons an `all_of`: nine gates with one machine
    check must read mostly-unknown, not mostly-fine."""
    members = reading.get("members") or []
    op = reading.get("op", "worst_of")
    states = []
    for m in members:
        # A member may carry its own compare; otherwise it inherits the goal's.
        states.append(_state_from(m, m.get("compare") or compare))
    if not states:
        return "broken"
    if op == "any_of":
        return "green" if "green" in states else min(states, key=lambda s: _STATE_RANK[s])
    # all_of and worst_of agree: the page reports the worst thing it knows.
    return min(states, key=lambda s: _STATE_RANK[s])


def _measured_human(reading, compare, state):
    """The '<measured> against <target>' half of a goal row, in words."""
    if reading.get("members") is not None:
        # A composite reports its members, because "nothing to measure" is the
        # wrong sentence for a check that measured three things and found one of
        # them watched by nobody.
        parts = []
        for m in reading["members"]:
            st = _state_from(m, m.get("compare") or compare)
            lab = (m.get("source_human") or "").strip()
            if m.get("unchecked"):
                parts.append(("unchecked", lab or m.get("reason", "")))
            elif m.get("error"):
                parts.append(("broken", lab or m["error"]))
            else:
                parts.append((st, lab))
        n_ok = sum(1 for st, _ in parts if st == "green")
        bad = [(st, lab) for st, lab in parts if st != "green"]
        head = f"{n_ok} of {len(parts)} hold"
        if bad:
            st0, lab0 = bad[0]
            word = {"unchecked": "not monitored", "broken": "could not check",
                    "red": "fails", "amber": "is slipping", "attested": "is attested only"}.get(st0, "fails")
            head += f" — {word}: {lab0[:110]}"
            if len(bad) > 1:
                head += f" (and {len(bad) - 1} more)"
        return head
    if reading.get("unchecked"):
        return "not monitored yet"
    if reading.get("attested"):
        who = reading.get("attested_on") or "?"
        return (f"verified by you {who} — lapsed" if reading.get("expired")
                else f"verified by you, {who}")
    if reading.get("error"):
        return "could not be measured: " + str(reading["error"])
    v, unit = reading.get("value"), reading.get("unit") or ""
    d = (compare or {}).get("direction")
    t = (compare or {}).get("target")
    if v is None:
        return "nothing to measure"
    if isinstance(v, bool):
        where = reading.get("where") or []
        phrase = reading.get("says_true" if v else "says_false")
        if phrase:
            return ("yes — " if v else "no — ") + phrase
        if not v and where:
            return f"no — found at {', '.join(where[:3])}" + (f" and {len(where) - 3} more" if len(where) > 3 else "")
        label = (reading.get("source_human") or "").strip()
        return ("yes" if v else "no") + (f" — {label}" if label else "")
    if d == "in_set":
        return str(v)
    if d in ("lower_is_better", "fresher_than"):
        # "1 records against a bar of 0 records" is arithmetic homework. A bar of
        # zero is a sentence about whether any exist at all, so say that.
        if t == 0:
            # A bar of zero is a sentence about whether any exist at all. Units
            # here are authored as singular noun phrases so the count reads like
            # English rather than like a spreadsheet cell.
            if not v:
                return "none"
            noun = unit or "of them"
            if v != 1 and reading.get("unit_plural"):
                noun = reading["unit_plural"]
            else:
                noun = _plural(v, noun)
            return f"{v} {noun} — there should be none"
        return f"{v}{_u(unit)} against a bar of {t}{_u(unit)}"
    if d == "higher_is_better":
        n, dd = _counts(reading)
        if n is not None and (unit == "ratio" or (isinstance(t, float) and t <= 1.0)):
            return f"{n} of {dd}" + (" — the bar is all of them" if t == 1.0 and n != dd else "")
        return f"{v}{_u(unit)} against a target of {t}{_u(unit)}"
    if d == "ratio":
        n, dd = reading.get("numerator"), reading.get("denominator")
        if n is None:
            n, dd = _counts(reading)
        if n is not None and dd:
            return f"{n} of {dd}" + (" — the bar is all of them" if t == 1.0 and n != dd else "")
        return f"{round(v * 100)}% against a bar of {round((t or 0) * 100)}%"
    return f"{v}{_u(unit)}"


def _u(unit):
    if not unit:
        return ""
    if unit == "%":
        return "%"
    return " " + unit


def _plural(n, noun):
    """Pluralize a unit's HEAD noun. Units are authored singular ("blocked
    project with no way out"); appending the s to the end of the phrase gives
    "blocked project with no way outs", and leaving it off gives "3 blocked
    project". Both were bugs the page shipped before this."""
    if n == 1 or not noun:
        return noun
    head, sep, rest = noun.partition(" ")
    head = head if head.endswith("s") else head + "s"
    return head + sep + rest


def _counts(reading):
    """The (n, d) a ratio was computed from, whatever the kind called them."""
    for a, b in (("numerator", "denominator"), ("resolvable", "total"),
                 ("done", "total"), ("named_present", "named_total")):
        n, d = reading.get(a), reading.get(b)
        if n is not None and d:
            return n, d
    return None, None


# ---------------------------------------------------------------------------
# Escalation: what earns the CEO's dot
#
# The dot used to answer "is anything wrong on this pillar?" — so a pillar went
# red for work the studio could simply have done, and the twenty-two-item queue
# nobody was draining lit up his dashboard as if it were his to fix. Wrong is
# not the same as his. The dot answers one question now: does this pillar need
# HIM? Everything else is still on the pillar's page, in the scoreboard, where a
# person looking for it will find it — and reaches the dashboard as a count.
#
# Four tests, and a failing goal reaches him only by passing one:
#
#   authority            only he can settle it — his taste, a direction, a
#                        commitment, a date, money, a credential. A recorded
#                        ceo_blocker is this test, already written down. So is an
#                        expired attestation, because only Daniel may attest.
#   external_commitment  we have told somebody outside the studio something that
#                        is not true, or we owe an outsider something.
#   exposure             a player or an outsider can be hit by this now.
#   age                  ours to fix, but it has waited long enough — or is
#                        getting worse fast enough — that the delay is the news.
#
# Deliberately NOT a test: needing an approval. A tier-2 item and a prepped
# decision card serve Daniel as an approver, and approvals belong on the Work
# page and in the decision inbox where he answers them one after another. Firing
# a pillar red because something is waiting on a yes turns his whole board into a
# second copy of those two queues, which is how the board stops meaning anything.
# ---------------------------------------------------------------------------

ESCALATION_REASONS = ("authority", "external_commitment", "exposure", "age")

# What the reason means, in his words, on the page. No HQ vocabulary.
ESCALATION_WORDS = {
    "authority": "Only you can settle this",
    "external_commitment": "We have told people outside the studio something this contradicts",
    "exposure": "Somebody outside the studio can hit this right now",
    "age": "This is ours, but it has waited long enough that the delay is the news",
}

# How long ours-to-fix may sit before the waiting is itself worth his attention.
AGE_LIMIT_DAYS = {"blocking": 7, "important": 14, "watch": 30}


def _days_since(text):
    """Whole days since an ISO date or timestamp, or None if there is no date."""
    import datetime as _dt
    if not text:
        return None
    try:
        when = _dt.datetime.fromisoformat(str(text)[:19])
    except (TypeError, ValueError):
        return None
    return max(0, (_dt.datetime.now() - when).days)


_OPEN_SINCE = {"at": 0.0, "by_route": {}}


def _open_since_index():
    """When each record a goal routes to was opened. Cheap, and rebuilt at most
    twice a minute: this runs once per goal per signals recompute."""
    import time as _t
    if _t.time() - _OPEN_SINCE["at"] < 30 and _OPEN_SINCE["by_route"]:
        return _OPEN_SINCE["by_route"]
    idx = {}
    try:
        for it in work.items():
            if it.get("state") in ("accepted", "dropped"):
                continue
            idx[("work", it.get("id"))] = it.get("created", "")
    except Exception:
        pass
    try:
        for name in os.listdir(os.path.join(DATA, "projects")):
            if not name.endswith(".json"):
                continue
            doc = load_json(os.path.join(DATA, "projects", name))
            if doc.get("blocked_since"):
                idx[("project", doc.get("id"))] = doc["blocked_since"]
    except Exception:
        pass
    _OPEN_SINCE.update({"at": _t.time(), "by_route": idx})
    return idx


def _goal_open_since(goal):
    """The oldest honest start date for 'how long has this been failing?': what
    the CEO blocker says it has been waiting, when the work filed against it was
    filed, and when the goal-state journal first saw it non-green. A goal nothing
    has been filed against and that nothing has journalled yet has no clock, and
    says so rather than guessing at one."""
    p2g = goal.get("path_to_green") or {}
    dates = [(p2g.get("ceo_blocker") or {}).get("waiting_since")]
    route = p2g.get("route") or {}
    if route.get("kind") and route.get("id"):
        dates.append(_open_since_index().get((route["kind"], route["id"])))
    dates.append(_goal_journal().get(goal.get("id"), {}).get("since"))
    days = [d for d in (_days_since(x) for x in dates) if d is not None]
    return max(days) if days else None


def _escalation(goal, state, reading):
    """Which of the four tests this failing goal passes, or None — in which case
    it is ours, and it reaches him as a count and not as an alarm."""
    if state == "green":
        return None
    p2g = goal.get("path_to_green") or {}
    decl = goal.get("escalates") or {}
    days = _goal_open_since(goal)
    since = {"days": days, "worsening": _goal_journal().get(goal.get("id"), {}).get("worsening", False)}

    # Authored: whether a promise is one we made outside the studio, or one only
    # Daniel can keep, is a property of the promise. It cannot be derived, so it
    # is written on the goal exactly as its statement and target are.
    reason = str(decl.get("reason") or "").strip().lower()
    if reason not in ("authority", "external_commitment", "exposure"):
        reason = ""
    # A recorded CEO blocker IS the authority test, in the field the pages
    # already read. So is an attestation that has run out: only Daniel attests,
    # so only Daniel can renew one.
    if not reason and (p2g.get("ceo_blocker") or (reading or {}).get("expired")):
        reason = "authority"
    if reason:
        return {"reason": reason, "why": decl.get("because", "") or ESCALATION_WORDS[reason],
                **since}

    # Measured: ours, but the waiting has become the story. A goal that is
    # getting worse rather than merely sitting escalates at half the patience.
    limit = decl.get("after_days")
    try:
        limit = int(limit)
    except (TypeError, ValueError):
        limit = AGE_LIMIT_DAYS.get(goal.get("severity"), 14)
    if since["worsening"]:
        limit = max(1, limit // 2)
    if days is not None and days >= limit:
        return {"reason": "age", "why": ESCALATION_WORDS["age"], "limit": limit, **since}
    return None


# ---------------------------------------------------------------------------
# The goal journal: how long a promise has been failing, and which way it is
# going. Written by a background thread, never by a request — a tracked file
# written on page render leaves the tree dirty, and `git describe --dirty` is
# where playtest build ids come from. Until a goal appears here its age comes
# from the work filed against it, and a goal with neither says "not known".
# ---------------------------------------------------------------------------

GOAL_JOURNAL_TTL = 300
_GOAL_JOURNAL = {"at": 0.0, "by_id": {}}


def _goal_journal():
    """{goal_id: {"since": iso, "worsening": bool}} from the journal's tail."""
    import time as _t
    if _t.time() - _GOAL_JOURNAL["at"] < GOAL_JOURNAL_TTL and _GOAL_JOURNAL["by_id"]:
        return _GOAL_JOURNAL["by_id"]
    out = {}
    rows = read_history("goals", 4000)
    for row in rows:
        for gid, state in (row.get("states") or {}).items():
            seen = out.setdefault(gid, {"since": "", "last": "green", "worsening": False})
            if state == "green":
                seen["since"], seen["worsening"] = "", False
            else:
                if not seen["since"]:
                    seen["since"] = row.get("at", "")
                if _STATE_RANK.get(state, 9) < _STATE_RANK.get(seen["last"], 9):
                    seen["worsening"] = True      # amber -> red, or red -> broken
            seen["last"] = state
    _GOAL_JOURNAL.update({"at": _t.time(), "by_id": out})
    return out


def _journal_goals():
    """One line per sweep: every non-green goal and the state it is in. Two of
    the four escalation tests are about time, and time cannot be measured from a
    single reading."""
    try:
        sig = compute_signals()
    except Exception:
        return
    states = {}
    for pid, block in (sig.get("goals") or {}).items():
        for g in block.get("goals", []):
            if g.get("state") != "green":
                states[g["id"]] = g["state"]
    append_history("goals", {"states": states})
    _GOAL_JOURNAL["at"] = 0.0


def _goal_journal_thread():
    import time as _t
    while True:
        _journal_goals()
        _t.sleep(3600)     # hourly: the quantity is days, not minutes


def eval_goal(goal):
    """One declared goal -> the row the page renders. Never raises: a malformed
    goal renders `broken` rather than taking down the pillar it lives on."""
    out = dict(goal)
    try:
        reading = eval_measure(goal.get("measure") or {})
        compare = goal.get("compare") or {}
        if (goal.get("measure") or {}).get("kind") == "composite" and reading.get("members") is not None:
            state = _composite_state(reading, compare)
        else:
            state = _state_from(reading, compare)
        out["state"] = state
        out["reading"] = reading
        out["measured"] = reading.get("value")
        out["measured_human"] = _measured_human(reading, compare, state)
        out["assured"] = state in ASSURED_STATES
        out["attestation_expired"] = bool(reading.get("expired"))
        out["stale"] = bool(reading.get("stale"))
        # Whose problem is this? A goal reaches him only by passing one of the
        # four escalation tests above; everything else is ours, and reaches him
        # as a count. Note what is gone: a tier-2 action used to make a goal
        # his, which meant every pillar holding something awaiting a yes glowed
        # at him. Approvals are the Work page's job and the inbox's job — they
        # serve him as an approver, and the board is not a third copy of them.
        out["escalation"] = _escalation(goal, state, reading)
        out["needs_you"] = bool(out["escalation"])
        out["ours"] = state not in ("green",) and not out["needs_you"]
    except Exception as e:
        out["state"] = "broken"
        out["reading"] = _reading(None, error=str(e)[:160])
        out["measured_human"] = "could not be measured"
        out["assured"] = False
    return out


def load_goals(pillar_id):
    path = os.path.join(GOALS_DIR, pillar_id + ".json")
    if not os.path.isfile(path):
        return None
    try:
        return load_json(path)
    except Exception:
        return None


def rollup(pillar_id, goals, dormant_decl, pillar_name=""):
    """Goal states -> the pillar's level, its reasons, and its queue entries.

    Three things this gets right that a naive 'red else ok' would not:
    a broken measurement is attention (we could not check, which is not the same
    as fine); a blocking goal nothing watches is `unassured`, not `ok`; and
    dormancy is a separate flag, never a level that could swallow a fire."""
    red_blocking = [g for g in goals if g["state"] == "red" and g.get("severity") == "blocking"]
    red_other = [g for g in goals if g["state"] == "red" and g.get("severity") != "blocking"]
    broken_real = [g for g in goals if g["state"] == "broken" and g.get("severity") in ("blocking", "important")]
    unchecked_blocking = [g for g in goals
                          if g["state"] in ("unchecked", "attested") and g.get("severity") == "blocking"]

    # The dot is his, so it is built from what escalated to him and nothing
    # else. A pillar can hold six failing goals and still be quiet here — they
    # are on its own page, in the scoreboard, and counted on the dashboard row.
    escalated = [g for g in goals if g.get("escalation")]
    # Fire is reserved for a reading that is actually bad AND either aimed
    # outward or blocking. An attestation that has merely lapsed, or a promise
    # nothing watches, still needs him — but it is not the building burning, and
    # a dot that cannot tell those apart teaches him to stop reading it.
    loud = [g for g in escalated
            if g["state"] in ("red", "broken")
            and (g["escalation"]["reason"] in ("external_commitment", "exposure")
                 or g.get("severity") == "blocking")]

    if not goals:
        level = "unassured"          # a pillar with no goals is not a healthy pillar
    elif loud:
        level = "fire"
    elif escalated:
        level = "attention"
    elif unchecked_blocking or broken_real:
        # Nothing is asking for him, but the board cannot vouch for itself here:
        # either a promise nothing watches, or a reading that failed. Both are
        # facts about the instrument, and neither may read as "under control".
        level = "unassured"
    else:
        level = "ok"

    dormant = bool(dormant_decl)
    if dormant and level in ("ok", "unassured"):
        level = "dormant"

    assured = sum(1 for g in goals if g["assured"])
    rank = lambda g: (_STATE_RANK[g["state"]], 0 if g.get("severity") == "blocking" else 1)
    yours = sorted([g for g in goals if g.get("needs_you") and g["state"] != "green"], key=rank)
    ours = sorted([g for g in goals if g.get("ours")], key=rank)
    failing = sorted([g for g in goals if g["state"] in ("red", "amber", "broken")], key=rank)

    ours_phrase = ""
    if ours:
        n = len(ours)
        ours_phrase = (f"{n} thing{'' if n == 1 else 's'} here need doing and "
                       f"{'it is' if n == 1 else 'they are'} ours, not yours — "
                       + ours[0]["statement_short"]
                       + (", and the rest are on the pillar's page." if n > 1 else "."))
    if yours:
        # His reasons first, and never more than two: the rest of what is wrong
        # is on the pillar's own page, which is where somebody looking for it
        # goes. A pillar whose problems are all ours says so plainly instead of
        # handing him a list he cannot act on.
        reasons = [f"{g['statement_short']} — {g['measured_human']}." for g in yours[:2]]
        if ours:
            reasons.append(f"{len(ours)} more, all of them ours to fix.")
    elif level == "unassured":
        broken_n = len(broken_real)
        n = len([g for g in goals if not g["assured"]])
        head = (f"{broken_n} check{'' if broken_n == 1 else 's'} here could not be read at "
                "all, so this pillar cannot vouch for itself." if broken_n else
                f"Nothing here needs you; monitoring is still landing on {n} of {len(goals)} "
                "areas, and the plans are filed.")
        reasons = [head + (" " + ours_phrase if ours_phrase else "")]
    elif ours:
        reasons = ["Nothing here needs you. " + ours_phrase]
    elif level == "dormant":
        why = (dormant_decl or {}).get("reason", "Dormant by your standing instruction.")
        src = (dormant_decl or {}).get("ruling")
        reasons = [why + ("" if src else
                          " Policy, not auto-checked: no ruling records this in the decision log.")]
    elif goals:
        unassured_n = len(goals) - assured
        reasons = [f"All {assured} measured goals on this pillar are passing"
                   + (f"; monitoring plans are filed for {unassured_n} more."
                      if unassured_n else ".")]
    else:
        reasons = [f"{pillar_name or pillar_id} declares no goals — its goal file is missing."]
    if not reasons:
        reasons = [f"{pillar_name or pillar_id} reports {level} with no stated reason — "
                   "its goal file is malformed."]

    notes = []
    # Everything that escalated, not everything that is failing: an attestation
    # that has run out is not a red reading, and only he can renew it, so it
    # belongs in his queue even though it never shows up as a failure.
    for g in yours:
        kind = "fire" if g in loud else "watch"
        notes.append({"kind": kind, "pillar": pillar_id,
                      "text": f"{g['statement_short']} — {g['measured_human']}",
                      "why_you": ESCALATION_WORDS.get(g["escalation"]["reason"], ""),
                      "href": f"#/pillar/{pillar_id}",
                      "signal_key": g.get("signal_key") or f"{pillar_id}:{g['id']}"})
    # The rest reach him as a count and nothing more: he should know the pillar
    # has work outstanding without being handed work he cannot act on.
    if ours:
        notes.append({"kind": "ours", "pillar": pillar_id, "count": len(ours),
                      "name": pillar_name or pillar_id,
                      "href": f"#/pillar/{pillar_id}",
                      "signal_key": f"{pillar_id}:ours"})
    if level == "unassured" and not yours:
        notes.append({"kind": "watch", "pillar": pillar_id, "text": reasons[0],
                      "href": f"#/pillar/{pillar_id}",
                      "signal_key": f"{pillar_id}:unassured"})

    return {
        "level": level,
        "reasons": reasons,
        "dormant": dormant,
        "dormant_reason": (dormant_decl or {}).get("reason", ""),
        "red_count": len(red_blocking) + len(red_other),
        "needs_you": len(yours),
        "ours": len(ours),
        "escalations": [{"goal": g["id"], "statement_short": g.get("statement_short", ""),
                         "reason": g["escalation"]["reason"],
                         "days": g["escalation"].get("days")} for g in escalated],
        "assured": assured,
        "total": len(goals),
    }, notes


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

    per_pillar = {}
    for p in pillars:
        per_pillar[p["id"]] = {
            "commits_7d": _git_commits("7 days ago", p["git_paths"]),
            "commits_24h": _git_commits("24 hours ago", p["git_paths"]),
            "recent": _git_last(p["git_paths"], 5),
        }

    # Status per pillar: computed from the pillar's declared goals, not written
    # here. Until this change, engineering/product/sales derived their level and
    # art/marketing/ops carried hardcoded literals — so two of the six could
    # never light up, and nothing on the page told a derived "under control"
    # apart from a typed one. One evaluator now reads hq/data/goals/<pillar>.json
    # and every pillar's level is the rollup of its own goals. A pillar with no
    # goal file is `unassured`, never `ok`: a pillar nobody has written goals for
    # is not a healthy pillar, it is an unexamined one.
    #
    # `status[pid]` keeps its {level, reasons} contract exactly — the dashboard,
    # the nav dots, the standup brief and the chat personas all read it — and
    # gains additive fields (dormant, assured, total, red_count) that only the
    # new bands look at.
    status, all_goals, watch_notes = {}, {}, []
    for p in pillars:
        pid = p["id"]
        doc = load_goals(pid) or {}
        evaluated = [eval_goal(g) for g in doc.get("goals", [])]
        # Worst first, so the page, the reasons and the queue agree on what matters.
        evaluated.sort(key=lambda g: (_STATE_RANK[g["state"]],
                                      0 if g.get("severity") == "blocking" else
                                      1 if g.get("severity") == "important" else 2))
        roll, notes = rollup(pid, evaluated, p.get("dormant_by_ruling"), p.get("name"))
        status[pid] = roll
        all_goals[pid] = dict(roll, goals=evaluated,
                              scoreboard_title=doc.get("scoreboard_title", ""),
                              verdict_template=doc.get("verdict_template", {}),
                              question=p.get("question", ""),
                              tagline=p.get("tagline", ""))
        watch_notes.extend(notes)

    # The Eye of Sauron: one ordered queue of what deserves the CEO's look.
    eye = []
    # Fires used to be appended here, one per burning pillar, reading that
    # pillar's first reason. The goals emit their own now — with the goal's
    # signal_key, so one artifact that unblocks three pillars reaches him once —
    # and appending both put every fire on the dashboard twice.
    # One entry per DISTINCT unblocking action (Rin's dedupe rule): projects
    # sharing a blocker merge into one item, and projects blocked on inbox
    # decisions fold into the decisions line instead of echoing it. Entries are
    # STRUCTURED — a headline plus resolvable project rows (link, blocked-since
    # age, owner) — never prose that mentions a thing without referencing it.
    def _days_since(datestr):
        import datetime
        try:
            d = datetime.datetime.strptime(str(datestr), "%Y-%m-%d")
            return (datetime.datetime.now() - d).days
        except (ValueError, TypeError):
            return None

    def _proj_row(o):
        return {"id": o["id"], "name": o["name"], "href": f"#/project/{o['id']}",
                "priority": o.get("priority"), "owner": o.get("owner"),
                "blocked_since": o.get("blocked_since"),
                "days_blocked": _days_since(o.get("blocked_since"))}

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
        group = [b] + [o for o in blocked
                       if o["id"] != b["id"] and o.get("blocked_on") == key]
        headline = b.get("unblock_action") or f"Unblock: {b['name']}"
        why = (b.get("current_status") or "").split(".")[0]
        eye.append({"kind": "action", "pillar": "product",
                    "headline": headline, "why_you": why,
                    "unblocks": [_proj_row(o) for o in group],
                    "text": headline + " — unblocks " + ", ".join(o["name"] for o in group) + ".",
                    "href": f"#/project/{b['id']}"})
    # Goal notes. Deduped by signal_key first, so one artifact that unblocks
    # three pillars reaches him once rather than three times: the fresh-session
    # sitting is claimed by both Engineering and Product and belongs in the queue
    # as one line saying so.
    by_key = {}
    for n in watch_notes:
        k = n.get("signal_key")
        prior = by_key.get(k)
        if prior is None:
            by_key[k] = dict(n, claimants=[n["pillar"]])
        else:
            prior["claimants"].append(n["pillar"])
            if n["kind"] == "fire":
                prior["kind"] = "fire"
                prior["text"] = n["text"]
                prior["href"] = n["href"]
    # Work the studio can do on its own reaches him as ONE line, not one per
    # pillar. Six rows all saying "no decision needed from you" is a different
    # way of spending the attention this split exists to save.
    ours_notes = [n for n in by_key.values() if n["kind"] == "ours"]
    for n in by_key.values():
        if n["kind"] == "ours":
            continue
        if len(n["claimants"]) > 1:
            n["text"] += f" (the same thing is holding {len(n['claimants'])} pillars)"
        eye.append(n)
    if ours_notes:
        total = sum(n["count"] for n in ours_notes)
        where = ", ".join(f"{n['name'].split(' &')[0]} {n['count']}"
                          for n in sorted(ours_notes, key=lambda x: -x["count"]))
        eye.append({"kind": "info", "pillar": "product",
                    "text": f"{total} other thing{'' if total == 1 else 's'} need doing across "
                            f"{len(ours_notes)} pillar{'' if len(ours_notes) == 1 else 's'} — all of "
                            f"them the studio's own work, none of them a decision for you ({where}).",
                    "href": "#/"})
    if pending_rulings:
        eye.append({"kind": "info", "pillar": "product",
                    "text": f"{len(pending_rulings)} ruling(s) you recorded await integration by the next work session — no action needed from you.",
                    "href": "#/inbox"})
    if curated_fresh:
        eye.append({"kind": "decide", "pillar": "product",
                    "headline": f"Rule on {len(curated_fresh)} prepped decisions",
                    "why_you": f"Oldest first: {curated_fresh[0]['id']} — {curated_fresh[0]['title']}",
                    "unblocks": [_proj_row(b) for b in decision_blocked],
                    "text": f"Rule on {len(curated_fresh)} prepped decision(s); ruling also unblocks "
                            + ", ".join(b["name"] for b in decision_blocked) + "." if decision_blocked
                            else f"Rule on {len(curated_fresh)} prepped decision(s).",
                    "href": "#/inbox"})

    # Finished work waiting on his verdict. It reaches him as ONE line pointing
    # at the page built for answering these in a row — never as a pillar going
    # red, because approving a result is a thing he does as the approver and not
    # as the CEO, and a board that cannot tell those apart is a second copy of
    # this queue. Without the line the drain could finish twenty results and the
    # dashboard would say nothing at all.
    try:
        work_items = work.items()
    except Exception:
        work_items = []
    verdicts = [i for i in work_items if i.get("state") in ("for_review", "needs_approval")]
    work_queued = sum(1 for i in work_items if i.get("state") == "waiting_session")
    if verdicts:
        done = [i for i in verdicts if i.get("state") == "for_review"]
        eye.append({"kind": "decide", "pillar": "product",
                    "headline": f"Give your verdict on {len(verdicts)} piece"
                                f"{'' if len(verdicts) == 1 else 's'} of work",
                    "why_you": (f"{len(done)} finished and waiting to be accepted or sent back"
                                if done else "none of it has started — each one wants your yes"),
                    "text": f"{len(verdicts)} piece(s) of work want your verdict.",
                    "href": "#/work"})

    # One explicit ranking, applied once, rather than an order that falls out of
    # the sequence things happen to be appended in. Fires first — the dashboard
    # promotes eye[0] to "the one thing", and it has to be the worst thing, not
    # whatever block of code ran first. Stable, so within a rank the order each
    # producer chose survives.
    _EYE_RANK = {"fire": 0, "decide": 1, "action": 2, "watch": 3, "info": 4}
    eye.sort(key=lambda e: _EYE_RANK.get(e.get("kind"), 5))

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
        "work": {"waiting_on_you": len(verdicts), "queued": work_queued},
        "goals": all_goals,
        "consistency": check_consistency(),
        "eye": eye,
    }
    data["brief_fingerprint"] = brief_fingerprint(status, eye, data["queue"], projects)
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


def api_needs(pillar_id):
    """What this pillar needs from the CEO.

    A projection, not a store. Every ask already lives in one of two queues —
    the decision cards he rules on, and the tier-2 work items he approves — and
    a third would be a second inbox competing with the first. So this reads
    those, filters to the pillar by the owner's team, adds the goals whose route
    back runs through him, ranks, and caps at three. Nothing is recorded here,
    and no ruling is ever given here: a ruling recorded in two places diverges.

    The cap is the point. A band that can grow into a backlog stops being read.
    """
    pillars = load_json(os.path.join(DATA, "pillars.json"))["pillars"]
    p = next((x for x in pillars if x["id"] == pillar_id), None)
    if not p:
        return {"needs": [], "error": "no such pillar"}
    org = load_org()
    team_of = {e["id"]: e.get("team") for e in org["employees"]}
    pillar_team = p.get("team")
    mine = {e["id"] for e in org["employees"] if e.get("team") == pillar_team}

    needs = []
    sig = compute_signals()
    goals = (sig.get("goals") or {}).get(pillar_id, {}).get("goals", [])

    # 1. Goals whose route back runs through him. These rank first: they are the
    #    only asks that carry a measured consequence already on the page.
    for g in goals:
        cb = (g.get("path_to_green") or {}).get("ceo_blocker")
        if not cb or g["state"] in ("green",):
            continue
        surface = cb.get("surface") or {"kind": "none"}
        waiting = _days_since_date(cb.get("waiting_since"))
        needs.append({
            "kind": cb.get("kind", "ruling"),
            "ask": (g.get("path_to_green") or {}).get("narrative", ""),
            "because": g["statement"],
            "state": g["state"],
            "consequence": cb.get("consequence", ""),
            "waiting_days": waiting,
            "surface": surface,
            "href": _need_href(surface),
            "sittings": cb.get("sittings"),
            "duration_minutes": cb.get("duration_minutes"),
            "goal": g["id"],
            "rank": 0 if g["state"] == "red" else 1,
        })

    # 2. Decision cards this pillar's people own that he has not ruled on.
    q = api_queue()
    ruled = set(q["rulings"])
    for c in q["curated"]:
        if c["id"] in ruled:
            continue
        owner = c.get("owner")
        card_pillar = c.get("pillar")
        if card_pillar and card_pillar != pillar_id:
            continue
        if not card_pillar and (owner not in mine if owner else True):
            continue
        needs.append({
            "kind": "ruling", "ask": c.get("title", c["id"]),
            "because": (c.get("why_now") or "")[:220],
            "consequence": "", "waiting_days": None,
            "surface": {"kind": "decision", "id": c["id"]},
            "href": "#/inbox", "rank": 2,
        })

    # 3. Tier-2 work this pillar's people are waiting on him to approve.
    try:
        items = work.items()
    except Exception:
        items = []
    for it in items:
        if it.get("state") != "needs_approval" or it.get("tier") != 2:
            continue
        owner = it.get("owner")
        if it.get("pillar"):
            if it["pillar"] != pillar_id:
                continue
        elif team_of.get(owner) != pillar_team:
            continue
        needs.append({
            "kind": "budget", "ask": it.get("title", ""),
            "because": (it.get("ask") or "")[:220],
            "consequence": "", "waiting_days": _days_since_date((it.get("created") or "")[:10]),
            "surface": {"kind": "work", "id": it["id"]},
            "href": "#/work", "rank": 1,
        })

    needs.sort(key=lambda n: (n["rank"], -(n.get("waiting_days") or 0)))
    # Dedupe by what the ask actually points at: two goals blocked on the same
    # sitting are one ask, not two.
    seen, out = set(), []
    for n in needs:
        key = (n["surface"].get("kind"), n["surface"].get("id"), n["kind"])
        if key in seen and key[1]:
            continue
        seen.add(key)
        out.append(n)
    return {"needs": out[:3], "overflow": max(0, len(out) - 3),
            "note": "Every ask here lives in the decision inbox or the work queue. "
                    "This band carries you to it; it never records a ruling of its own."}


def _need_href(surface):
    kind = (surface or {}).get("kind")
    if kind == "decision":
        return f"#/inbox/{surface.get('id')}" if surface.get("id") else "#/inbox"
    if kind == "work":
        return f"#/work/{surface.get('id')}" if surface.get("id") else "#/work"
    if kind == "project":
        return f"#/project/{surface.get('id')}"
    return None


def brief_fingerprint(status, eye, queue, projects):
    """One formula, used by both the signals payload and the brief cache, so
    'is the brief stale?' has exactly one answer."""
    import hashlib
    src = json.dumps({"v": 2, "s": status, "e": eye, "q": queue,
                      "p": [(p["id"], p["status"]) for p in projects]}, sort_keys=True)
    return hashlib.sha1(src.encode()).hexdigest()[:12]


def make_standup():
    """The chief of staff's brief: the live signals handed to the CoS persona,
    who writes what changed, what's under control, and where the eye goes.
    Cached against a fingerprint of the inputs, so it regenerates only when
    reality changed — the right cadence, automatically."""
    sig = compute_signals()
    projects = load_projects()
    finger = sig.get("brief_fingerprint") or brief_fingerprint(
        sig["status"], sig["eye"], sig["queue"], projects)
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
        if proc.returncode == 0:
            brief = proc.stdout.strip()
            clear_limit()
        else:
            brief = ""
            # Out of tokens shows up here first as often as in chat; recording
            # it means the chat page can warn before he types a word.
            if _looks_like_limit((proc.stderr or "") + (proc.stdout or "")):
                note_limit((proc.stderr or "") + (proc.stdout or ""))
    except Exception:
        brief = ""
    if not brief:
        return {"error": "brief generation failed", "fingerprint": finger,
                "limited": bool(limited_until())}
    import datetime
    doc = {"fingerprint": finger, "brief": brief,
           "generated": datetime.datetime.now().isoformat(timespec="minutes")}
    os.makedirs(os.path.join(DATA, "runs"), exist_ok=True)
    with open(spath, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False)
    return doc


# ---------------------------------------------------------------------------
# Intake queue — the out-of-tokens outbox.
#
# The subscription's 5-hour window can run dry mid-session. The `claude` CLI
# then exits non-zero and chat used to dead-end on "⚠️ claude CLI failed": the
# CEO's page went unreactive at exactly the moment he still had things to hand
# off. Instead we park the message on disk, say when the window reopens, and a
# background thread sends it and holds the reply until a browser collects it.
#
# Delivery does NOT depend on parsing the CLI's reset time — the drainer just
# retries on a backoff — so a reworded limit message can delay an answer but
# can never lose a request. The parsed time is only used to say "back at 6:20".
# ---------------------------------------------------------------------------
OUTBOX = os.path.join(DATA, "outbox")
OUTBOX_STATE = os.path.join(OUTBOX, "_limit.json")
OUTBOX_KEEP_DAYS = 7
_OUTBOX_LOCK = threading.Lock()   # guards the item files
_LIMIT_LOCK = threading.Lock()    # guards _LIMIT (never taken with the above)
_LIMIT = {"until": 0.0, "detail": ""}   # epoch seconds; 0 == not limited

# Only ever matched against the output of a FAILED claude run, so breadth here
# costs nothing worse than a queued-and-retried message.
_LIMIT_HINTS = re.compile(
    r"usage limit reached|rate.?limit|too many requests|5-?hour limit|"
    r"limit will reset|limit reached|out of (?:tokens|credits)|"
    r"quota (?:exceeded|exhausted)|\b429\b", re.I)
_LIMIT_EPOCH = re.compile(r"(?:reached|resets?[ _]?at)\D{0,12}(1[0-9]{9})\b", re.I)
_LIMIT_CLOCK = re.compile(r"resets?\s+at\s+(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m", re.I)


def _looks_like_limit(text):
    return bool(_LIMIT_HINTS.search(text or ""))


def _parse_reset(text, now):
    """Best-effort reset moment from the CLI's message; 0.0 when it says
    nothing useful. Cosmetic only — see the section note."""
    m = _LIMIT_EPOCH.search(text or "")
    if m:
        ts = float(m.group(1))
        if now < ts < now + 24 * 3600:
            return ts
    m = _LIMIT_CLOCK.search(text or "")
    if m:
        import datetime
        hour = int(m.group(1)) % 12 + (12 if m.group(3).lower() == "p" else 0)
        ts = datetime.datetime.fromtimestamp(now).replace(
            hour=hour, minute=int(m.group(2) or 0), second=0, microsecond=0).timestamp()
        if ts < now:
            ts += 24 * 3600
        return ts
    return 0.0


def _save_limit_locked():
    try:
        os.makedirs(OUTBOX, exist_ok=True)
        with open(OUTBOX_STATE, "w", encoding="utf-8") as f:
            json.dump(_LIMIT, f)
    except OSError:
        pass  # the queue still drains; we'd just re-learn the limit the hard way


def note_limit(text):
    """Record that Claude is out of tokens — from any CLI call, chat or brief."""
    import time as _t
    now = _t.time()
    guess = _parse_reset(text, now) or (now + 20 * 60)
    with _LIMIT_LOCK:
        cur = _LIMIT["until"] if _LIMIT["until"] > now else 0.0
        _LIMIT["until"] = max(cur, guess)
        _LIMIT["detail"] = " ".join((text or "").split())[:200]
        _save_limit_locked()
        until = _LIMIT["until"]
    if not cur:
        # cur is 0 only on the call that opens a fresh outage — later calls
        # while it's still in force just refine the guess and must not each
        # log a line, or the history would grow one row per failed retry.
        append_history("limits", {"event": "hit", "until": until})
    return until


def clear_limit():
    """A successful call is proof the window is open again."""
    with _LIMIT_LOCK:
        if not _LIMIT["until"]:
            return
        _LIMIT["until"] = 0.0
        _LIMIT["detail"] = ""
        _save_limit_locked()
    parked = sum(1 for i in list_outbox() if i["state"] in ("queued", "sending"))
    append_history("limits", {"event": "clear", "parked": parked})


def limited_until():
    import time as _t
    return _LIMIT["until"] if _LIMIT["until"] > _t.time() else 0.0


def _outbox_path(item_id):
    return os.path.join(OUTBOX, f"{item_id}.json")


def _write_item(item):
    os.makedirs(OUTBOX, exist_ok=True)
    path = _outbox_path(item["id"])
    tmp = path + ".tmp"
    with _OUTBOX_LOCK:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(item, f, ensure_ascii=False)
        os.replace(tmp, path)  # a half-written item must never be readable
    return item


def list_outbox():
    try:
        names = sorted(os.listdir(OUTBOX))
    except OSError:
        return []
    items = []
    for n in names:
        if not n.endswith(".json") or n.startswith("_"):
            continue
        try:
            items.append(load_json(os.path.join(OUTBOX, n)))
        except Exception:
            continue
    items.sort(key=lambda i: i.get("created_ts", 0))
    return items


def enqueue_chat(to_id, message, history, reason="limit"):
    import datetime
    import time as _t
    import uuid
    return _write_item({
        "id": uuid.uuid4().hex[:12],
        "to": to_id,
        "message": message,
        "history": (history or [])[-12:],
        "state": "queued",
        "reason": reason,            # "limit" (auto) or "manual"
        "created": datetime.datetime.now().isoformat(timespec="seconds"),
        "created_ts": _t.time(),
        "attempts": 0,
        "next_try": 0,
        "reply": "",
        "error": "",
    })


def set_queue_state(item_id, state):
    """Cancel a parked request, or push a failed one back onto the queue."""
    if state not in ("cancelled", "queued"):
        return {"error": "bad state"}
    if not re.match(r"^[0-9a-f]{6,32}$", item_id or ""):
        return {"error": "bad id"}
    path = _outbox_path(item_id)
    if not os.path.isfile(path):
        return {"error": "no such item"}
    item = load_json(path)
    if item["state"] == "sending":
        return {"error": "already sending"}
    if state == "queued":
        item["attempts"] = 0
        item["next_try"] = 0
        item["error"] = ""
    item["state"] = state
    _write_item(item)
    return {"ok": True, "item": item}


def queue_snapshot():
    items = list_outbox()
    return {
        "limited": bool(limited_until()),
        "limit_until": limited_until(),
        "limit_detail": _LIMIT["detail"] if limited_until() else "",
        "pending": sum(1 for i in items if i["state"] in ("queued", "sending")),
        "items": items,
    }


def _prune_outbox():
    """Answered requests stay collectable for a week (long enough for the other
    machine to pick them up), then go."""
    import time as _t
    cutoff = _t.time() - OUTBOX_KEEP_DAYS * 86400
    for item in list_outbox():
        if item["state"] in ("done", "cancelled", "failed") and item.get("created_ts", 0) < cutoff:
            try:
                os.remove(_outbox_path(item["id"]))
            except OSError:
                pass


def sanitize_outbox():
    """A restart orphans an in-flight send; requeue it rather than lose it."""
    for item in list_outbox():
        if item.get("state") == "sending":
            item["state"] = "queued"
            item["next_try"] = 0
            _write_item(item)
    try:
        saved = load_json(OUTBOX_STATE)
        _LIMIT["until"] = float(saved.get("until") or 0)
        _LIMIT["detail"] = saved.get("detail") or ""
    except Exception:
        pass


def _drain_outbox():
    """Send parked requests once the window reopens — one at a time, oldest
    first, so a backlog can't stampede a freshly reset token budget."""
    import datetime
    import time as _t
    while True:
        _t.sleep(20)
        try:
            _prune_outbox()
            if limited_until():
                continue
            now = _t.time()
            due = [i for i in list_outbox()
                   if i["state"] == "queued" and i.get("next_try", 0) <= now]
            if not due:
                continue
            item = due[0]
            item["state"] = "sending"
            item["attempts"] = item.get("attempts", 0) + 1
            _write_item(item)
            res = _chat_once(item["to"], item["message"], item["history"])
            if res.get("limited"):
                item["state"] = "queued"
                item["next_try"] = _t.time() + 60
            elif res.get("reply"):
                item["state"] = "done"
                item["reply"] = res["reply"]
                work.capture_exchange(item["to"], item["message"], res["reply"])
                item["error"] = ""
                item["answered"] = datetime.datetime.now().isoformat(timespec="minutes")
            else:
                item["error"] = res.get("error", "no reply")[:300]
                # Three honest tries, then it waits for the CEO rather than
                # spinning: a non-limit failure won't fix itself.
                item["state"] = "failed" if item["attempts"] >= 3 else "queued"
                item["next_try"] = _t.time() + 120 * item["attempts"]
            _write_item(item)
        except Exception:
            continue  # the drainer outlives any single bad item


MAX_TURNS = 24   # 12 was too few: a persona told to go do something spends
                 # turns reading the repo and dies before it answers.


def cli_failure(proc):
    """What actually went wrong, in his words not ours. The CLI reports some
    failures on stdout with an empty stderr, so a stderr-only message reads as
    'claude CLI failed' — which tells him nothing and looks like a dead app."""
    err = (proc.stderr or "").strip()
    out = (proc.stdout or "").strip()
    if "max turns" in out.lower() or "max turns" in err.lower():
        return (f"Ran out of steps ({MAX_TURNS} tool turns) before finishing the "
                f"answer — this one needs narrowing, or a bigger step budget.")
    detail = err or out
    if not detail:
        return f"The assistant exited with code {proc.returncode} and said nothing."
    return " ".join(detail.split())[:400]


def seat_model(org, to_id, override=None):
    """The model a persona runs on: an explicit override for this occasion wins,
    else the seat's default from its org record. The default is never binding —
    that is the ruling, not an accident of the plumbing."""
    if override:
        return str(override)
    emp = next((e for e in org["employees"] if e["id"] == to_id), None)
    return (emp or {}).get("model") or ""


def _chat_once(to_id, message, history, model=None):
    """One real call to the CLI. Returns {"reply"} or {"error"[, "limited"]}."""
    org = load_org()
    convo = ""
    for h in (history or [])[-12:]:
        who = "Daniel" if h.get("role") == "user" else h.get("name", "Assistant")
        convo += f"{who}: {h.get('text', '')}\n\n"
    convo += f"Daniel: {message}"
    sys_prompt = build_system_prompt(org, to_id)
    cmd = [
        "claude", "-p", convo,
        "--append-system-prompt", sys_prompt,
        "--allowedTools", "Read,Glob,Grep",
        "--max-turns", str(MAX_TURNS),
    ]
    m = seat_model(org, to_id, model)
    if m:
        cmd += ["--model", m]
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
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")
    if proc.returncode != 0:
        if _looks_like_limit(out):
            note_limit(out)
            return {"error": "out of tokens", "limited": True,
                    "detail": " ".join(out.split())[:200]}
        return {"error": cli_failure(proc)}
    clear_limit()
    reply, kept = take_remembered(to_id, proc.stdout.strip())
    return {"reply": reply, "remembered": kept}


def run_chat(payload):
    """Send now if we can; park it if we can't (or if he asked us to)."""
    to_id = payload.get("to", "claude")
    message = (payload.get("message") or "").strip()
    history = payload.get("history") or []
    if not message:
        return {"error": "empty message"}
    if payload.get("queue") or limited_until():
        item = enqueue_chat(to_id, message, history,
                            "manual" if payload.get("queue") else "limit")
        return {"queued": item["id"], "resume_at": limited_until(),
                "reason": item["reason"]}
    res = _chat_once(to_id, message, history, model=payload.get("model"))
    if res.get("reply"):
        work.capture_exchange(to_id, message, res["reply"])
    if res.get("limited"):
        # He typed it before we knew; it is not his job to retype it later.
        item = enqueue_chat(to_id, message, history)
        return {"queued": item["id"], "resume_at": limited_until(),
                "reason": "limit"}
    return res


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
        parts = urlparse(self.path)
        path, query = parts.path, parse_qs(parts.query)
        try:
            if path in ("/", "/index.html"):
                return self._send_file(STATIC, "index.html")
            if path.startswith("/static/"):
                return self._send_file(STATIC, path[len("/static/"):])
            if path.startswith("/assets/"):
                return self._send_file(os.path.join(REPO, "assets"), path[len("/assets/"):])
            if path.startswith("/ledger/"):
                # Historical sheet bytes, for the before/after strip in the editor.
                return self._send_file(os.path.join(DATA, "sprite_edits"), path[len("/ledger/"):])
            if path.startswith("/looks/"):
                # Look-session sheets, attached to decision cards.
                return self._send_file(LOOKS, path[len("/looks/"):])
            if path == "/api/sprite/history":
                return self._send(200, studio.api_get(path, query))
            if path == "/api/org":
                return self._send(200, load_org())
            if path == "/api/entities":
                return self._send(200, load_json(os.path.join(DATA, "entities.json")))
            if path == "/api/projects":
                return self._send(200, load_projects())
            if path == "/api/program":
                return self._send(200, api_program())
            if path.startswith("/api/project/"):
                pid = path[len("/api/project/"):]
                for p in load_projects():
                    if p["id"] == pid:
                        return self._send(200, p)
                return self._send(404, {"error": "no such project"})
            if path == "/api/queue":
                return self._send(200, api_queue())
            if path == "/api/looks":
                return self._send(200, load_looks())
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
            if path.startswith("/api/playtest-events/"):
                name = path[len("/api/playtest-events/"):]
                if not re.match(r"^[0-9_-]{1,40}$", name):
                    return self._send(400, {"error": "bad session name"})
                return self._send(200, playtest_events(name))
            if path == "/api/audio":
                sfx_dir = os.path.join(REPO, "assets", "audio", "sfx")
                music_dir = os.path.join(REPO, "assets", "audio", "music")
                return self._send(200, {
                    "sfx": sorted(f for f in os.listdir(sfx_dir) if f.endswith(".wav")),
                    "music": sorted(f for f in os.listdir(music_dir) if f.endswith((".ogg", ".wav"))),
                })
            if path == "/api/spend":
                # The money ledger, as written. Absent until the art pipeline has
                # something to record, and half-written while it appends — both
                # answer 200 with `missing`, so the page frames the absence
                # rather than showing a broken tile or, worse, a made-up number.
                sp = os.path.join(DATA, "spend.json")
                if not os.path.isfile(sp):
                    return self._send(200, {"missing": True})
                try:
                    return self._send(200, load_json(sp))
                except Exception as e:
                    return self._send(200, {"missing": True, "unreadable": str(e)[:200]})
            if path == "/api/goals":
                return self._send(200, compute_signals().get("goals", {}))
            if path.startswith("/api/goals/"):
                pid = unquote(path[len("/api/goals/"):])
                return self._send(200, compute_signals().get("goals", {}).get(pid) or {})
            if path.startswith("/api/needs/"):
                return self._send(200, api_needs(unquote(path[len("/api/needs/"):])))
            if path == "/api/ci/history":
                return self._send(200, ci_history() or {"error": "not polled yet"})
            if path == "/api/gate":
                return self._send(200, gate_scorecard())
            if path == "/api/platforms":
                return self._send(200, platform_ladder())
            if path.startswith("/api/manifest"):
                rid = path[len("/api/manifest/"):] if len(path) > len("/api/manifest") else ""
                return self._send(200, release_manifest(unquote(rid) or None))
            if path == "/api/palette":
                return self._send(200, palette_union())
            if path == "/api/history":
                q = parse_qs(parts.query)
                return self._send(200, {"rows": read_history(q.get("name", ["runs"])[0])})
            if path == "/api/pillars":
                return self._send(200, load_json(os.path.join(DATA, "pillars.json")))
            if path == "/api/runs":
                return self._send(200, {j: latest_job_result(j) for j in JOBS})
            if path == "/api/deploy":
                return self._send(200, deploy_status())
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
            if path == "/api/chat/queue":
                return self._send(200, queue_snapshot())
            if path.startswith("/api/work"):
                return self._send(200, work.api_get(path))
            if path == "/api/health":
                return self._send(200, {"ok": True, "limit_until": limited_until()})
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
        if path == "/api/deploy":
            try:
                return self._send(200, start_deploy(payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        if path == "/api/deploy/pair":
            try:
                return self._send(200, deploy_pair(payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
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
        if path == "/api/sprite/revert":
            try:
                return self._send(200, revert_sprite(payload))
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
        if path == "/api/chat/queue":
            try:
                item = enqueue_chat(payload.get("to", "claude"),
                                    (payload.get("message") or "").strip(),
                                    payload.get("history") or [], "manual")
                return self._send(200, {"queued": item["id"],
                                        "resume_at": limited_until()})
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        if path.startswith("/api/work"):
            try:
                return self._send(200, work.api_post(path, payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        if path in ("/api/chat/cancel", "/api/chat/retry"):
            state = "cancelled" if path.endswith("cancel") else "queued"
            return self._send(200, set_queue_state(payload.get("id", ""), state))
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
    sanitize_outbox()
    threading.Thread(target=_drain_outbox, daemon=True).start()
    # The 100-run CI window, polled off the request path: at --limit 100 the gh
    # call costs about four seconds against a one-second call at --limit 10, so
    # widening it in the render path would triple every post-TTL page visit for
    # a strip nobody is looking at yet.
    threading.Thread(target=_ci_history_thread, daemon=True).start()
    # Two of the four escalation tests are about time, which needs more than one
    # reading. Hourly, off the request path, because it writes a tracked file.
    threading.Thread(target=_goal_journal_thread, daemon=True).start()
    work.bind(sys.modules[__name__])
    studio.bind(sys.modules[__name__])
    work.start()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Tiny Farm HQ on http://localhost:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()

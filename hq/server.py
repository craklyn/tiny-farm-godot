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


def main():
    check_consistency()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Tiny Farm HQ on http://localhost:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()

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
    return prompt


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
        self.send_header("Cache-Control", "max-age=300")
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
                return self._send(200, parse_queue())
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
        if path == "/api/chat":
            try:
                return self._send(200, run_chat(payload))
            except Exception as e:
                return self._send(500, {"error": str(e)[:300]})
        return self._send(404, {"error": "not found"})


def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Tiny Farm HQ on http://localhost:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()

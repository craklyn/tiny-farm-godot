# Phase 1 — The blueprint: 0 → 1 in one session

The goal of the first session is a walking skeleton the leader can open in a
browser and never think about again operationally: it boots with the machine,
serves instantly, and already shows real data. Resist scaffolding a "proper"
web app; the constraints below are the feature.

## Architecture

```
hq/
├── server.py          # one stdlib-only HTTP server: static files + JSON APIs
├── static/
│   ├── index.html     # single page, hash routing (#/org, #/program, ...)
│   ├── app.js         # router + one render function per page
│   ├── style.css
│   └── vendor/        # the few libs you vendor, fetched once, committed
└── data/
    ├── org.json           # org chart + personas
    ├── projects/*.json    # program report, one file per project
    ├── decisions/*.json   # curated decision cards
    └── rulings/           # decisions the leader records on-page
```

Hard constraints, each with its reason:

- **Zero dependencies on the server** (Python stdlib `http.server` or
  equivalent). There is no virtualenv to rot, no lockfile to update. The
  app must still start in two years untouched.
- **No build step on the frontend.** Plain JS/CSS, hash-based routing.
  Editing a file and reloading is the whole dev loop.
- **No runtime network dependency.** Anything third-party is vendored into
  `static/vendor/` once and committed. The dashboard works on a plane.
- **Serve static files with no-cache headers.** Hours have been lost to
  "my edit isn't showing" that was a stale browser cache.
- **A supersede guard in the router.** Renders are async (they fetch);
  keep a sequence counter so only the latest in-flight navigation paints.
  Without it, a slow earlier page overwrites the one the user just opened.
- **Keep it out of the product build.** `.gdignore`, `.dockerignore`,
  whatever the project uses — the HQ is dev tooling and must never ship or
  be a dependency of product code.

## Runs at boot

Install as a user service so the URL is simply always alive:

```ini
# ~/.config/systemd/user/<name>-hq.service
[Unit]
Description=Project HQ dashboard
[Service]
ExecStart=/usr/bin/python3 %h/path/to/hq/server.py
Restart=on-failure
# PATH pitfall: CLI tools the server shells out to (gh, claude) may live in
# /snap/bin or ~/.local/bin — absent from systemd's default PATH. Set
# Environment=PATH=... explicitly or signals that shell out will silently fail.
[Install]
WantedBy=default.target
```

Then `systemctl --user enable --now <name>-hq` and
`loginctl enable-linger <user>` so it starts without a login. Document the
three ops commands (status / logs / restart) in the HQ's README.

## The starter page set

Five pages cover most leaders' day one. Build them thin — each is one API
endpoint plus one render function.

1. **Dashboard** — for now, just links plus whatever is already derivable.
   It becomes the "eye queue" in phase 2; don't over-invest yet.
2. **Program report** — one JSON file per project: name, priority, owner,
   definition of done, status, plan (a list of steps with done flags),
   `blocked_on`. One file per project keeps diffs clean and lets "last
   moved" be derived from git later.
3. **Decision inbox** — parse the project's *existing* decision document
   live at request time (never import/copy it). Even read-only, this page
   earns trust immediately because it always matches the repo. It becomes
   two-way in phase 2.
4. **Org chart with chattable personas** — `org.json` holds personas with
   real-feeling titles, mandates, and a system prompt each. `/api/chat`
   shells out to the local `claude` CLI with the persona's system prompt
   and **read-only** repo tools. Two hard-won details: render replies
   through a vendored markdown parser + HTML sanitizer (never hand-roll
   either — vendor e.g. marked + DOMPurify), and cap concurrent claude
   subprocesses with a small semaphore.
   Why personas instead of one chat box: each persona accumulates a
   charter (watches, escalation rules, working rules), which later phases
   use — delegation becomes "ask the owner", and design rules get an owner.
5. **Artifact gallery** — render the project's real artifacts (sprites,
   schemas, sample outputs) from their real files, with code references.
   The gallery is the seed of phase 3's editors: a leader who can *see*
   an artifact next asks to *change* it.

## Data conventions that pay off later

- Personas, projects, and decisions cross-reference by id. Add a startup
  consistency check that warns on dangling references — cheap, and it
  catches most data-editing mistakes.
- Give projects `blocked_on`, `blocked_since`, and an `unblock_action`
  name from early on; phase 2's queue-deduplication and phase 4's
  drift-detection need them.
- Anything the server writes (rulings, run verdicts, editor saves) gets its
  own directory under `data/`, and generated/high-churn output
  (run verdicts, backups) is gitignored while curated data is committed.

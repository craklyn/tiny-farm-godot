# Tiny Farm HQ

The CEO's local operating surface. The design contract: **everything is derived
from real sources (git, CI, files, docs, traces) at request time** — no page
maintains its own status, so "not marked on fire" is trustworthy, and the
dashboard's eye queue is the ordered list of what actually needs the CEO.

Surfaces: the Eye of Sauron dashboard (derived pillar statuses + the chief of
staff's brief), six pillar pages (scoped commit feeds, living demos, team
charters with escalation rules), org chart with chattable personas, the
animated/editable entity gallery, the map editor (layout definitions), the
playtest viewer (traces scored by the game's own formulas), the program
report, and the decision inbox (curated cards + on-page rulings). The Engineering & QA
pillar page carries **The tablet** — build the code as it stands and install it on the
device, beside the "run it yourself" suites. It is the one control built to work with no
model in the loop at all, so it explains its own failures on screen (`docs/DEPLOY.md`
section 2).

- **URL:** http://localhost:8642 (on the desktop)
- **From the laptop / anywhere:** https://daniel-maco.tail445099.ts.net — the same
  server, shared tailnet-only via `tailscale serve` (set up 2026-09-02; the serve
  rule and the service both survive reboots). HQ itself stays bound to 127.0.0.1
  so the chat endpoint is never exposed beyond the tailnet. To stop sharing:
  `tailscale serve --https=443 off`.
- **Run by hand:** `python3 hq/server.py` (stdlib only, no dependencies)
- **Runs at boot:** systemd user service `tiny-farm-hq` (`~/.config/systemd/user/tiny-farm-hq.service`),
  with `loginctl enable-linger` so it starts without a login.
  - status: `systemctl --user status tiny-farm-hq`
  - logs: `journalctl --user -u tiny-farm-hq`
  - restart after editing server/data: `systemctl --user restart tiny-farm-hq`

## Layout

- `server.py` — zero-dependency HTTP server (static app, JSON APIs, game-asset
  serving, live designer-queue parsing, and `/api/chat` which shells out to the
  local `claude` CLI with a per-persona system prompt, read-only repo tools).
  - **The intake queue.** When the subscription's 5-hour window runs dry the CLI
    can't answer, and the chat page used to dead-end on "claude CLI failed".
    Now a dry window parks the request in `data/outbox/<id>.json`, the page says
    when tokens come back, and a background thread sends it and holds the reply
    until a browser collects it — so an idea he has at 9pm isn't lost because the
    tokens are. Anything that fails for another reason offers "Queue it for
    later" on the same terms. Delivery never depends on parsing the CLI's reset
    message: the drainer just retries, so a reworded limit can delay an answer
    but can't lose a request. `/api/chat/queue` (GET state, POST enqueue),
    `/api/chat/cancel`, `/api/chat/retry`. Answered items are collectable for
    seven days, which is what lets the laptop pick up what the desktop queued.
- `static/` — the single-page frontend. `design.js`/`design.css` are the Design
  Studio tab: the living GDD browsed live from `docs/` via `/api/docs` +
  `/api/doc/<path>` — served from the repo on every request, never copied. The
  index leads with the vision (the one-sentence pitch, a five-phase rail with
  premise/maturity/milestones per phase, and a computed "design frontier" card
  joining the next undone phase milestone to its design debt); every doc is a
  real route (`#/design/doc/<path>[@anchor]`), and rendered docs get heading
  anchors, a contents rail, and live S-/P-/D-/Q- citation links.
- `static/vendor/` — vendored third-party libs, fetched once from jsdelivr so the
  app has no runtime network dependency: `marked` 16.4.1 (MIT, markdown parsing)
  and `DOMPurify` 3.2.7 (Apache-2.0/MPL-2.0, HTML sanitization) for chat replies.
- `work.py` — **how work originates.** Every chat exchange is read afterwards for the
  follow-up it creates, and the follow-up is filed automatically: owner, level, and a tier
  set by how hard the work is to walk back. Tier 0 (nothing to walk back) is carried out
  immediately and the CEO reviews the *result*; tier 1 (repo changes) queues for a build
  session; tier 2 (hard to reverse, or his taste) waits for his yes. Nothing waits on
  permission to *exist*. `docs/HOW_WORK_ORIGINATES.md` is the norm in prose, S-9 in the
  decision log settles it, and `data/work_policy.json` is the copy the server reads — edit
  that to change the norms without touching code. Items live in `data/work/`, the Work page
  in `static/work.js`.
- `data/org.json` — org chart + personas (Amazon titles/levels).
- `data/entities.json` — entity gallery: sprite-sheet frame rects, fps, sounds,
  code refs. Update when a new species/crop/object ships (the Zoo's roster and
  `systems/species_defs.gd` are the source of truth to mirror).
- `data/projects/*.json` — the program report, one file per project, ordered by
  `priority`.
- `data/decisions/*.json` — curated decision cards for the inbox: plain-language
  question, options with a recommendation, attachments (image/audio/sprite/video),
  links. Keep in sync with open items in `docs/DESIGNER_QUEUE.md`.
- `data/rulings/` — rulings the CEO records in the inbox (`<Q-id>.json`, plus a
  running `RULINGS.md` ledger). `status: pending_integration` means a work session
  still needs to fold it into the design docs — see CLAUDE.md "Docs and process".
- `data/sprite_backups/` — pre-edit copies of any sheet saved from the in-app
  sprite editor (one per sheet per day).

The `.gdignore` keeps Godot from scanning this directory. The chat feature and
project data are dev-facing; nothing here ships with the game.

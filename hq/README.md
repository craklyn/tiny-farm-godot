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
report, and the decision inbox (curated cards + on-page rulings).

- **URL:** http://localhost:8642
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

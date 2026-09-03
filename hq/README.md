# Tiny Farm HQ

The CEO's local operating surface. The design contract: **everything is derived
from real sources (git, CI, files, docs, traces) at request time** — no page
maintains its own status, so "not marked on fire" is trustworthy, and the
dashboard's eye queue is the ordered list of what actually needs the CEO.

Surfaces: the Eye of Sauron dashboard (derived pillar statuses + the chief of
staff's brief), six pillar pages (each one the wall its VP would brief the CEO
from — see **Goals** below), org chart with chattable personas, the
animated/editable entity gallery (whose sprite editor keeps a full per-sheet
edit history and files each edit to the art director), the map editor (layout
definitions), the playtest viewer (traces scored by the game's own formulas),
the program report, and the decision inbox (curated cards + on-page rulings). The Engineering & QA
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

## Goals — the one status pipeline

Every pillar's status is computed from goals it declares in
`data/goals/<pillar>.json`. There is exactly one evaluator (`eval_measure` /
`eval_goal` / `rollup` in `server.py`) and no second status system anywhere.

Before this, three pillars derived their status and three carried hardcoded
`ok` strings, so half the board could never light up however wrong things got,
and nothing on screen distinguished a measured verdict from a typed one. Sales
had a subtler version of the same bug: it only went amber when there were *zero*
release tags, so the moment `v0.1.0` existed it was structurally green forever.

**The honesty rule.** A goal's *statement* and its *target* are authored — a
commitment cannot be derived, and pretending otherwise would be the lie. Its
*current value* is measured, by a small declarative vocabulary that maps onto
things this repo really holds. A goal nothing can measure does not get to look
measured: it renders `unchecked` with the reason and the specific recording that
would make it real, and it counts **against** the pillar's assurance fraction
rather than for it. Hence the "4 of 6 checked by machine" on every pillar page —
it is what makes a green pillar with two checks visually different from a green
pillar with seven.

The six goal states: `green`, `amber`, `red` (measured), `unchecked` (nothing
watches it), `broken` (the measurement itself failed — never green; a failed
reading is a fact about the instrument), `attested` (a human declared it, with a
date, expiring). Only Daniel may attest — the rest of the org are personas, and
a persona vouching for something nothing measured would be inventing studio
activity.

**Measurement kinds** (each maps to something the audit verified exists):
`git_commits`, `git_file_age`, `git_tag`, `git_build_lag`, `file_exists`,
`file_count`, `file_grep`, `orphan_files`, `ci_state`, `job_state`,
`count_json`, `project_field`, `program_readiness`, `playtest_metric`,
`doc_section`, `queue_state`, `probe_cache`, `palette_named_present`,
`composite`, `manual_attest`, `unchecked`.

Two safety properties are structural, not conventions: **no kind executes a
shell command or opens a socket** (network readings come from `probe_cache`,
which reads a file a named background poller writes), and **every path-taking
kind goes through `_safe()`**, so a goal file cannot read outside the repo.

A `composite` with `op: all_of` is green only if every member is green *and
assured* — one unwatched member makes the whole thing unchecked. That is what
stops a nine-gate launch check from reading green because eight of the gates
were never automated.

**Rollup:** a red blocking goal is `fire`; a red important one, an amber
blocking one, a broken one, or an expired attestation is `attention`; an
unwatched blocking goal is `unassured` (never `ok`); a pillar with no goal file
is `unassured` too, because a pillar nobody has written goals for is not a
healthy pillar. Dormancy is a **flag, not a level**, so a dormant pillar with a
failing promise still reaches the nav's exception group.

`status[pid]` keeps its `{level, reasons}` contract exactly — the dashboard, the
nav dots, the standup brief and the chat personas all read it — and only gains
additive fields.

## The pillar pages

Five bands, invariant in order so the CEO learns the page once, with band 2
entirely the pillar's own because an engineering wall and an art director's wall
are not the same object:

0. identity + the assurance fraction + when it was derived
1. **the verdict** — one sentence, generated from the goals, never authored. It
   may be a *permission* rather than a status ("You cannot tag today").
2. **the instrument** — the thing only this page has. Capped at `30vh` and
   scrolling inside itself: when the screen is short the picture yields, because
   the goals and the asks matter more than the picture.
3. **the goal scoreboard** — the one band rendered identically everywhere, since
   it is what lets him compare pillars. Rows past the third fold.
4. **what I need from you** — capped at three.

Then the fold, and below it: what nobody is checking, the commit feed (demoted,
and relabelled per pillar to say what it actually measures), and the team.

**The needs band creates no records.** It is a projection over the two queues
that already exist — the decision cards and the tier-2 work items — filtered to
the pillar, ranked, capped. No ruling is ever *given* from a pillar page: a
ruling recorded in two places diverges, so every control carries him to the one
place it is recorded.

| Pillar | Its one question | Its instrument | Its verb |
|---|---|---|---|
| Engineering | Is the proof that main works fresh enough to believe? | the evidence strip, aged in **commits behind main**, never a clock; plus 100 CI runs as ticks | RUN |
| Product | What stands in front of the next thing the player gets? | the gate scorecard welded to its build-decay stamp | CUT |
| Art | Is the game still one thing to look at? | the palette ribbon, decoded from the shipped PNGs | EDIT (gated) |
| Marketing | If people showed up tomorrow, would we know? | the promise checker: the store page vs. the build | FILL IN THE BLANK |
| Sales | What holds the next tag? | the gap, and the launch check at three-state weight | **none — no publish control, ever** |
| Ops | Can we afford what's next? | three tiles, one of which counts *down* | APPROVE |

Art's palette ribbon is the single licensed exception to *colour = semantics*,
and it says so on the page. The PNG decoding is stdlib `zlib` + `struct`, cached
on the sheets' mtimes.

## Recording

Anything HQ wants to chart later has to be written down at the time, and three
of the studio's most interesting quantities had exactly one datapoint each. So:
runs stamp the commit they proved and append to `data/history/runs.jsonl`, and
the 100-run CI window is polled onto `data/ci_history.json` by a background
thread — deliberately **off** the request path, since `gh --limit 100` costs
~4s against ~1s at `--limit 10`.

Nothing here is written by a request handler. A tracked file written on page
render leaves the tree dirty, and `git describe --dirty` is where playtest build
ids come from — which is exactly how two recorded sessions became impossible to
tie to a build.

## Layout

- `server.py` — zero-dependency HTTP server (static app, JSON APIs, game-asset
  serving, live designer-queue parsing, and `/api/chat` which shells out to the
  local `claude` CLI with a per-persona system prompt, read-only repo tools).
  A persona's prompt now also carries two things that make chat additive rather
  than amnesiac: their own memory file, and the work already filed to them by
  `work.py` — so "what are you working on?" has a real answer, and something
  filed to Ingrid while the CEO is elsewhere is waiting for her when he arrives.
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
- `studio.py` — the art studio's memory of hand edits. Every save from the sprite
  editor lands as a step in that sheet's ledger (see `data/sprite_edits/` below)
  and is filed to the art director as tier-0 work: reading his edit against the
  style guide and writing down what it says about the direction. A hand edit is
  the purest taste signal the project gets — this is what stops it dying as a
  pixel diff in git with the reasoning gone. It deliberately does **not** propose
  style-guide amendments yet; the guide is unsigned (the CEO asked for a look
  session first), so until then this accumulates as the evidence that session
  will be run from.
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
  question, options with a recommendation, attachments
  (image/audio/sprite/video/look), links. Keep in sync with open items in
  `docs/DESIGNER_QUEUE.md`.
- `data/looks/<scenario>/` — a look sheet delivered to a card (Q-86): the question
  staged in the real game with every draft photographed under identical conditions,
  composed into `sheet.png` (and `motion.png` where the argument is that it moves)
  with a `look.json` describing it. A card asks for one with
  `{"type": "look", "scenario": "<id>"}`; `tools/compose_look_sheets.py` reads the
  cards and copies in exactly the sheets they cite, which is why these are the only
  look captures in git — the rig's own output under `tools/looks/` is gitignored.
- `data/rulings/` — rulings the CEO records in the inbox (`<Q-id>.json`, plus a
  running `RULINGS.md` ledger). `status: pending_integration` means a work session
  still needs to fold it into the design docs — see CLAUDE.md "Docs and process".
- `data/sprite_edits/<sheet>/` — the sprite editor's ledger, written by
  `studio.py`. `0000.png` is the sheet before anyone edited it here; every save
  after that appends `NNNN.png` (the sheet at that step) and `NNNN.json` (what
  changed, and the CEO's own one-line answer to "what were you fixing?"). Nothing
  is ever overwritten, so any step can be inspected or reverted to — and a revert
  is itself a step, so the history only grows. Replaces the old
  `data/sprite_backups/` (one copy per sheet per day, so a second edit the same
  day had no recorded "before" at all); that directory is no longer written to and
  is kept only for the one copy it already holds.
- `data/staff/<person>/memory.md` — what a persona carries between conversations.
  Chat is a fresh read-only CLI session every time, so anything told to Ingrid on
  Tuesday used to be gone by Wednesday. A reply may end with a
  `<remember>...</remember>` block: the server strips it before the CEO sees the
  reply and appends it here, and the tail of the file rides in that person's
  system prompt next time. No extra model call, no write tools.

The `.gdignore` keeps Godot from scanning this directory. The chat feature and
project data are dev-facing; nothing here ships with the game.

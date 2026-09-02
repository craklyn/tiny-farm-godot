# Phase 2 — Adapting to the company: signals, honesty, and the decision loop

A generic dashboard shows generic things and gets ignored. This phase wires
the HQ into the specific company: its pillars, its decision process, its
artifacts. The output is a front page that can honestly claim *everything
not listed here is under control*.

## Find the company's real structure

Mine the repo and docs before inventing anything:

- **Pillars** — the 4–7 functional areas the leader actually thinks in
  (engineering, product, art, ops, sales...). Define each in a
  `pillars.json` with `git_paths`: the directories whose commits belong to
  it. This one mapping powers per-pillar commit feeds, commit-velocity
  signals, and scoped pillar pages.
- **The decision process** — wherever decisions already queue (a
  DECISIONS.md, an issues label, a designer queue), that document is the
  inbox's source of truth. Parse it live; never fork it.
- **Artifacts** — every recorded artifact class (sprites, traces, saves,
  reports) is a candidate gallery now and a candidate work surface in
  phase 3.

## Derive the signals

One endpoint (`/api/signals`) computes everything, with a short cache
(~60s) since several sources are subprocess calls:

| Signal | Derived from |
|---|---|
| Pillar activity | git commit velocity over the pillar's `git_paths` |
| CI health | `gh` CLI: newest **completed** run of the tests workflow on main |
| Test/benchmark verdicts | jobs run from the HQ itself, verdicts persisted to disk |
| Artifact freshness | mtime of newest trace / report / release tag |
| Load on the leader | count of prepped decision cards; blocked projects and their ages |

Each pillar gets a level — `ok / attention / fire / dormant` — where
`dormant` is only legitimate when a recorded ruling says the area is
intentionally paused. The dashboard orders its "eye queue" by
**fire > action > decide > info**.

## Honesty rules (learned the hard way)

The trust model dies on its first unearned green. These rules all come from
real bugs found in review:

- **A job verdict requires exit code 0 first**; parsing output text only
  adds detail. A regex that matches a "FAIL:" line's own wording can turn a
  failure green — the exact lie the system exists to prevent.
- **CI reads the newest *completed* run**, scoped to the tests workflow
  over a window of recent runs. An in-progress push must neither hide a red
  nor claim a green; an unrelated failed workflow (a release dispatch) is
  not "red checks"; rapid pushes must not scroll a red out of the window.
- **Degrade, don't guess.** When a source is transiently unreachable, show
  last-known-good explicitly labeled stale with its poll time. When it's
  genuinely unreachable, say so and lean on local signals — never default
  to green.
- **Separate derived from policy.** If a status is "fine by policy, not
  auto-checked", label it that way; don't let it wear the same green as a
  verified signal.
- **Parsers count what they drop.** A trace parser that skips malformed
  lines silently is quietly lying about totals; count drops and banner them.
- **Attention-level notes must reach the queue.** If a pillar page knows a
  reason for concern, the front page must list it — otherwise the
  "everything not listed is under control" claim is false.
- **Concurrency:** give the signals cache a single-flight lock and a
  version counter (a job finishing mid-computation must not have its
  invalidation overwritten); run cleanup in `finally` so a wedged
  "already running" state can't survive an error; on startup, sanitize
  orphaned "running" state files as "interrupted by restart".

## The two-way decision loop

This is what turns the dashboard from a viewer into an operating surface:

1. **Curate decision cards** (`data/decisions/*.json`) for items awaiting
   the leader: a plain-language question (no internal IDs or jargon — write
   it like people talking), 2–4 options with a recommendation, attachments
   (images, audio, live artifact previews), and links. Un-curated queue
   items still render raw, collapsed — nothing is hidden, but prepped cards
   lead.
2. **Capture rulings on-page**: choosing an option POSTs a ruling file
   (`data/rulings/<id>.json`) with `status: "pending_integration"`, plus a
   human-readable running ledger.
3. **Close the loop in the dev process**: the project's agent instructions
   (CLAUDE.md or equivalent) direct every work session to check for pending
   rulings at session start, integrate each into the real docs, do or file
   the unblocked work, then mark the ruling `"integrated"`.
4. **Badge what's ready for the leader**, not raw queue size — the raw
   queue is staff's backlog, and a badge that includes it nags the leader
   about work that isn't theirs.

## The chief-of-staff brief

A persona-generated situation brief belongs on the dashboard, but only
under self-maintenance rules: generate it from the live signals, cache it
against a **fingerprint of those signals**, and rewrite it automatically in
the background when the fingerprint changes (with an "updating…" label
meanwhile). Serve only the cache on GET so the page is instant. There
should never be a "regenerate" button the system isn't already pressing
itself — and the brief should auto-expand only when reality changed since
the leader last read it.

---
name: hq-builder
description: >-
  Build and iteratively refine a local "HQ" — a personal executive operating
  surface for the leader of a project or company: a zero-dependency localhost
  dashboard that derives every status from real sources (git, CI, files, docs)
  and grows bespoke in-browser work tools (asset editors, trace/replay viewers,
  test runners, decision inboxes) that beat talking to an AI in chat. Use this
  whenever the user wants a CEO dashboard, mission control, command center,
  program report, status page for their own project, a "decision inbox", or a
  custom in-browser tool for hands-on work with their project's artifacts —
  even if they only say "I want one place to see everything" or "a dashboard
  for my repo". Also use it when evolving or reviewing an existing HQ-style
  dashboard.
---

# HQ Builder

How to take a leader from zero to a personal operating surface they actually
run their project from — and keep refining it until it earns their trust.
This skill was distilled from building Tiny Farm HQ, a real CEO dashboard
that went through ~20 recorded design iterations; the worked example with the
actual feedback → rule moments is in `references/case-study.md`.

## The one contract everything hangs on

**Every status is derived from real sources at request time.** Git, CI,
files on disk, the project's own docs, recorded artifacts — never a field a
human (or agent) maintains by hand. A hand-maintained status goes stale the
day after it's written, and one stale green poisons every other green on the
page. The payoff of the derived-only rule is the product's core promise:
*anything not marked on fire is trustably under control*, so the leader's
attention goes only where it's needed.

Hold this contract from the first commit. Every later phase — signals,
trust hardening, the attention model — builds on it.

## Where this skill earns its keep

An A/B trial (skill vs. no skill, same task) showed a capable model builds a
respectable *status page* unaided: derived signals, live doc parsing, honest
log stats. What the unaided build lacked — and what you must therefore never
treat as optional garnish — are the parts that turn a viewer into an
operating surface: **two-way decision capture** (rulings recorded on-page
that flow back into the dev process), **write-safety guardrails** on every
editor (validation, backups, refusing destructive saves), and the
**attention model** (a ranked queue deduped by unblocking action, not an
unranked health board). If effort must be rationed, ration it away from the
basics and toward these.

## The four phases

Work through these in order for a new HQ; jump to the matching phase when
evolving an existing one.

### Phase 1 — Blueprint (0 → 1)

Ship a walking skeleton in one session: one stdlib-only server, one
single-page frontend, one JSON data directory, installed as a user service so
it's simply *always there* at its localhost port. No framework, no build
step, no runtime network dependency — this thing must still boot in two
years with zero maintenance.

Start with the five pages almost every project leader needs: a dashboard,
a program report (one JSON file per project), a decision inbox parsed live
from wherever decisions already live, an org chart of chattable personas
(each shelling out to the local `claude` CLI with a per-persona system
prompt and read-only repo tools), and a gallery of the project's real
artifacts. Details, endpoint shapes, and the service setup:
read `references/blueprint.md` before writing code.

### Phase 2 — Adapt to the company

Generic dashboards die of vagueness. Mine the repo and docs to find *this*
company's real structure: its pillars (map git paths to each), its decision
process (wire the inbox into it two-way, so rulings recorded on the page
flow back into the dev process), its artifacts (they become galleries and
later work surfaces). Then derive live signals per pillar and rank the
front page as an "eye queue": fire > action > decide > info.
Read `references/signals-and-trust.md` for the signal catalog, the honesty
rules, and the two-way decision loop.

### Phase 3 — Work surfaces that beat chat

Some of the leader's work is visual, spatial, or iterates in sub-second
loops — for that, a direct-manipulation page beats any conversation.
The test: **if describing the change in words is slower than doing it, build
a tool.** Editing one pixel, dragging a map parcel, scrubbing a replay to
the moment a playtest went wrong — none of these survive translation into
prose. Read `references/work-surfaces.md` for when to build bespoke vs.
vendor a library vs. stay in chat, and for the write-safety guardrails
(server-side validation, automatic backups, read-only mirrors of
code-owned data) that make an in-browser editor safe to hand a CEO.

### Phase 4 — The refinement loop

The blueprint gets you a dashboard; the loop gets you one the leader
actually lives in. Iterate on their verbatim feedback, one complaint at a
time, under one organizing principle: **the leader's attention is the
scarcest resource in the system.** One hero card for the single thing only
they can do; badges mark exceptions only; queue items dedupe by *unblocking
action*, not topic; every row answers "what's next, when did it last move,
what is it stuck on, who do I chase" — with the chase being one click.
Somewhere mid-life, run one adversarial review of the whole surface and fix
everything confirmed; the worst bugs in a trust product are the ones that
show green during a failure. Read `references/refinement.md` for the full
playbook.

## Process rules that held up

- **Derived beats maintained, everywhere.** "Moved 12d ago" computed from
  git beats a `last_updated` field nobody updates. Before adding any field
  a human must maintain, look for a source to derive it from.
- **Turn feedback into rules, not fixes.** When the leader says something
  load-bearing ("my job is to unblock my org"), don't just patch the
  screen they complained about — adopt the sentence as a design rule and
  re-apply it across the app. Record it (commit message, design doc) so it
  keeps governing later work.
- **Borrow learned vocabularies.** Status glyphs, colors, and layout
  patterns the leader already knows from GitHub/CI tools beat any invented
  vocabulary, however elegant. Color must never be the only channel.
- **Grow axes, not length.** When a page accumulates content, add a second
  way to slice it (by release, by priority, by blocked-age) instead of
  making the default view longer. Persist the chosen axis — leaders form
  habitual views.
- **Verify by observed behavior, not by code intent.** A toggle that sets
  `hidden` while CSS overrides `display` looks correct in the diff and does
  nothing on screen. Check the computed style, the actual pixels, the
  actual HTTP response.
- **The dashboard is dev tooling, not product.** Keep it out of the
  product build (`.gdignore`, ignore patterns) and never let product code
  depend on it.

## Reference files

| File | Read when |
|---|---|
| `references/blueprint.md` | Starting phase 1: architecture, starter pages, service install |
| `references/signals-and-trust.md` | Phase 2: deriving signals, honesty rules, decision loop |
| `references/work-surfaces.md` | Phase 3: building editors/viewers/runners safely |
| `references/refinement.md` | Phase 4: attention model, review passes, feedback → rules |
| `references/case-study.md` | Any phase, for grounding: the real Tiny Farm HQ journey |

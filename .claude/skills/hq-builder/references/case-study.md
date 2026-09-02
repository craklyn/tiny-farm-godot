# Case study — Tiny Farm HQ, the real journey

The skill's rules were distilled from building "Tiny Farm HQ": a local
operating surface for the CEO of a one-person game studio (a Godot farming
game built almost entirely by AI agents, with the human as CEO/designer).
This is the actual sequence, kept because the *order* matters: what was
built first, what feedback arrived, and what each round taught.

## 0 → 1 (one session)

First commit shipped the whole skeleton: stdlib-only `server.py` on
localhost:8642, systemd user service with linger, and five pages —
dashboard, org chart (29 personas with Amazon-style titles, each chattable
via the local `claude` CLI with read-only repo tools), an animated entity
gallery drawn from the real sprite sheets, a program report (one JSON per
project), and a decision inbox parsed live from the repo's existing
`DESIGNER_QUEUE.md`. Nothing copied, everything served from real sources.

## Early truthfulness fixes

- The org chart's wrapped rows drew connector stubs implying reporting
  lines that didn't exist → redrawn so lines are only ever true (CEO on
  top, chief of staff as a dashed *staff seat* outside the chain).
  Lesson: even decorative UI must not lie.
- Chat replies showed raw markdown → vendored marked + DOMPurify rather
  than hand-rolling a renderer/sanitizer.
- Static files got no-cache headers after a stale-cache hunt.

## The inbox becomes a decision surface; the first work tool

The read-only queue view grew into curated decision cards — plain-language
question, options with a recommendation, attachments (image/audio/live
sprite) — with on-page ruling capture writing
`data/rulings/<id>.json (pending_integration)`, and the project's CLAUDE.md
instructing every work session to integrate pending rulings at session
start. That closed the loop: a click on the dashboard reliably changes the
design docs.

The same round shipped the first direct-work tool, a sprite editor in the
artifact's own grammar (frame stepping, onion skin, palette from the
sprite's own colors, per-frame undo), with server-side path whitelist,
dimension validation, and daily backups. Embeddable pixel-editor libraries
were evaluated and declined as heavier than the problem. Next rounds added
synced before/after looping previews, composite-entity assembly mirroring
the game renderer, and a map editor that edits the world generator's
*input* (layout definitions) — never painted tiles — keeping worldgen
deterministic, with code-exported maps read-only.

## The command-center rework ("Eye of Sauron")

The CEO's directive: *attention goes only where needed; everything unmarked
must be trustably under control.* That produced `/api/signals` (every
status derived live: commit velocity per pillar via `git_paths`, CI via
`gh`, playtest freshness, job verdicts), the eye queue ordered
fire > action > decide > info, pillar pages with scoped commit feeds and
team charters, a playtest viewer scoring traces with the game's own
formulas (validated against a hand-verified session), a verification runner
for the real test suites (serialized — parallel runs had skewed the
benchmark into a false FAIL), and a chief-of-staff brief cached against a
signal fingerprint.

Trust hardening followed as its own pass: CI reads the newest *completed*
run scoped to the tests workflow, transient failures degrade to
last-known-good labeled stale, unreachable says so instead of guessing
green, and the sidebar badge counts decisions *prepped for the CEO* rather
than raw queue size. Root cause of one silent outage: `gh` lived in
`/snap/bin`, absent from the systemd unit's PATH.

## The adversarial review

A commissioned skeptical review confirmed 13 findings. The headline: the
robot job's verdict regex matched the failure line's own label
(`✗ FAIL: ... replay MATCHES its autosave`), so a determinism regression
would have shown **green** — the exact lie the trust model exists to
prevent. Fix class: exit code 0 required first, text only adds detail.
The rest were races (signals cache lost-invalidation, dedup locks),
honesty gaps (stale labels without poll times, parsers dropping lines
silently, attention notes not reaching the queue), and unescaped
artifact-sourced strings.

## The CEO feedback rounds (verbatim → rule)

1. *"The eye cards are wide, same-looking, unreadable as a hierarchy"* →
   a designer persona ("Rin, Sr. Design Technologist") was hired into the
   org with a mandate, and her first-principles pass restructured the
   landing page: one hero card for the single thing only the CEO can do,
   a dense ranked list with kind chips, pillars as a glanceable side strip.
2. *"FOR YOU and DECIDE are both for me"* → pills mark exceptions only;
   and the deeper fix: projects declare `blocked_on`, the queue merges by
   distinct *unblocking action* — four echoing items collapsed to the two
   real actions the day contained.
3. The CEO sketched business-notation items → every eye item became an
   imperative headline plus resolvable rows (link, priority, blocked-since
   age, owner). The brief lost its buttons: it rewrites itself when the
   signal fingerprint changes, because "there is never a reason to ask for
   a rewrite the system isn't already doing."
4. *"Do pillars belong under Dashboard?"* → yes to the grouping, no to
   folding: the status dots are the point, so the sidebar became an
   always-visible status board.
5. Two CEO catches in one round: the submenu collapse didn't actually
   collapse (the `hidden` attribute lost to a `display:flex` rule — fixed
   and verified by computed style, not by attribute), and the invented
   circle/square/ring status shapes had to be learned → replaced with the
   GitHub-taught grammar (check / ! / x / dash-in-ring), color redundant
   with glyph.
6. *"My job is to unblock my org"* — adopted verbatim: exception pillars
   pin themselves in the nav and never fold; the vague roll-up dot was
   deleted because with exceptions pinned it had nothing left to say.
7. The program report was rethought "as a Principal TPM would" for a
   gates-not-dates program: release trains, critical sets, cut lines
   ("a cut line is a kindness"), four slicing axes (grow axes, not
   length), NEXT on every row, "moved N ago" derived from git, stuck-on
   chips, and one-click delegation into the owner's chat with the question
   pre-drafted.

## What to take from the shape of it

The 0→1 was one session; everything after was feedback-driven, one
complaint per round, each fix generalized into a rule and reapplied. The
derived-only contract set on day one is what made every later feature
cheap: the eye queue, drift detection, the self-maintaining brief, and the
honest nav are all just new views over sources that were already truthful.

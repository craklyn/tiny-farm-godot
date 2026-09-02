# Phase 3 — Work surfaces that beat chat

The highest-leverage HQ pages aren't dashboards at all: they're tools where
the leader does direct work on the project's artifacts. Chat with an AI is a
great default interface, but it loses badly wherever the work is visual,
spatial, or iterates in sub-second loops.

## When to build a tool instead of talking

Build a bespoke page when **describing the change in words is slower than
doing it**:

- *Pixel/asset edits* — "make that pixel one shade darker" has no good
  sentence; a pencil tool is instant.
- *Spatial layout* — dragging a parcel or placing an object beats
  coordinates in prose.
- *Scrubbing recorded sessions* — finding the moment a playtest went wrong
  is a timeline interaction, not a question.
- *Pushing the big red button* — running the real test suites from the page
  the leader is already on, with persisted verdicts.

Stay in chat when the work is judgment, synthesis, or one-off — that's what
the persona chat pages are for.

## Build vs. vendor: the sizing rule

Evaluate libraries honestly against the actual problem:

- **Vendor small, treacherous things.** Markdown rendering and HTML
  sanitization are notoriously easy to get wrong — vendor a tiny
  established pair (e.g. marked + DOMPurify) rather than hand-rolling.
  Same for a single layout algorithm (d3-hierarchy's tidy tree) when only
  the algorithm is needed.
- **Decline heavy frameworks when the bespoke tool is smaller than the
  integration.** An embeddable pixel-editor library brings its own UI,
  state model, and theme; a canvas, a palette bar, and five tools is a few
  hundred lines that match the app exactly. Evaluate, then decide — and
  record the decision so it isn't relitigated.
- Everything vendored is fetched once, committed, and served locally — the
  no-runtime-network rule from the blueprint still holds.

## Design moves that made the editors good

From the sprite editor:

- **Edit in the artifact's own grammar.** Borrow the interaction grammar of
  the tool the domain already uses (Aseprite, in this case): frame-at-a-time
  editing with wrap-around stepping, onion skin, pencil/eraser/eyedropper,
  per-frame undo.
- **Palette from the artifact itself.** The color bar is built from the
  sprite's own colors, which keeps edits on-palette by default; a `+`
  swatch opens a native picker for deliberate additions (shown dashed until
  actually painted).
- **Live before/after, in sync.** Keep an untouched load-time copy and show
  two looping previews — as opened vs. as edited — driven by the same frame
  clock, so differences read instantly.
- **Render composites assembled, not faked.** If the game assembles an
  entity from parts, the gallery and editor must mirror the renderer's own
  assembly rules rather than cycling parts as a fake animation.

From the map editor:

- **Edit the generator's input, never its output.** The editor works on
  layout *definitions* (the same generalization the game itself uses), not
  painted tiles — so determinism and worldgen stay intact.
- **Source-of-truth mirrors are read-only.** Any map exported from code is
  displayed but not editable; edits happen on copies. The leader can look
  at anything, but the tool can't silently fork what code owns.

From the playtest viewer:

- **Score with the product's own formulas**, imported or faithfully
  mirrored, and **validate the parser against a known session** (a recorded
  session with hand-verified totals) before trusting any chart.

From the verification runner:

- **Serialize resource-contended jobs** (one engine process at a time —
  parallel runs skewed a benchmark into a false FAIL), persist verdicts to
  disk so freshness survives restarts, and let any failed job set its
  pillar on fire.

## Write-safety guardrails (non-negotiable for editors)

An in-browser editor that writes into the repo needs server-side discipline;
the browser is untrusted input:

1. **Path whitelist** — the save endpoint accepts only known artifact
   paths, never a client-supplied arbitrary path.
2. **Invariant validation** — reject saves that change what must not change
   (image dimensions, schema shape) so a buggy client can't corrupt the
   atlas/format.
3. **Automatic backups** — before the first overwrite of an artifact each
   day, copy the original to a backup directory (gitignored). Cheap
   insurance, zero ceremony.
4. **Escape everything sourced from artifacts** when rendering — trace
   fields, session names, and seeds are data, not HTML.

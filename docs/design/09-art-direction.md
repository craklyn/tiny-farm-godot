# 09 — Art Direction

*Status: skeleton. `[Designer]`-taste-led with `[Claude]` consolidation. First
deliverable: style guide + licensing audit (Q-7, Q-14).*

## Current state
Sprout Lands-style 16px pixel art (`assets/sprites/sprout_lands/`), 3× scale. Cozy,
readable, kid-friendly. P-6 commits to the 8/16-bit lane for scope reasons (five
genre-shifting phases are only affordable at low asset cost per phase).

## Asset plan (Q-7 ruling, 2026-08-18)
Current Sprout Lands art is **placeholder**. Full reskin happens once art style is
aligned (Q-14 below); sourcing then: an openly released image dataset or original work.
Residual check (Q-7b): before the *first public release*, sanity-check that placeholder
assets permit free public distribution with credit — Q-6 makes releases public early.

## Immediate actions
1. `[Claude]` **Style guide consolidation (Q-14):** extract the de-facto rules from
   existing assets (palette, tile conventions, outline style, animation frame counts)
   into a one-page guide new assets must match — this doubles as the spec the eventual
   reskin must satisfy. `[Designer]` approves.

## Sections to fill
1. **Palette & readability** — including functional colors: scent-overlay channels
   (P-10/D-4) need colorblind-safe, theme-consistent mapping; tile-state legibility at
   phone size is a hard requirement (S-6/S-7).
2. **Phase evolution** — how the look matures across acts without breaking unity (P-6
   allows local fidelity raises: phase-4 dashboards, phase-5 tactical views). The
   delegation arc could read visually: the farm gets *neater* as bots take over.
3. **Animation budget** — frames per entity tier; hundreds of on-screen entities
   (ARCHITECTURE budgets) cap per-entity animation cost.
4. **UI art language** — with 11-ux-ui: iconography-first (no-reading constraint),
   touch-target sizes.
5. **Bot design** — silhouette variation for individuality (06); wear/personality
   expressed visually.

## Open items
- `[Designer]` at Q-14 time: the actual style ruling the reskin targets (palette
  personality, fidelity level, how far from the placeholder look to move).

## Hand edits are evidence (2026-09-02)
The designer's own strokes in HQ's sprite editor are the only *uncontaminated*
statement of the intended look — everything else in this chapter is intent
reconstructed from conversation. So the editor now records them rather than just
writing the PNG: each save is a step in that sheet's ledger
(`hq/data/sprite_edits/`) carrying his one-line answer to "what were you fixing?"
alongside a measurement of what actually moved (frames, pixels, colors
introduced, whether the silhouette or only the interior shading changed), and is
filed to the art director to read against this guide.

Deliberately **no automatic amendments to the style guide below**: it is a draft
the designer has not signed (he ruled "not yet — I want a look session" on
2026-09-02), and a loop that edits an unsigned guide would be proposing changes to
a document that does not yet have force. Until the look session, the accumulated
edits are the material that session is run from — his taste, shown rather than
described. Amendment proposals turn on once the guide is approved.

---

## Style guide v1 — extracted from current assets (Q-14 draft, 2026-08-18)

*Measured from the sheets in `assets/sprites/sprout_lands/` (visual inspection +
pixel-count palette analysis). This is the de-facto style new placeholder-era assets
must match, and the baseline spec the eventual reskin either honors or deliberately
diverges from.*

**Grid & sheets.** 16×16 px tiles; atlas sheets in 16px cells. Characters live in
48×48 cells (visual body much smaller — generous padding for swings), 4 rows =
down/up/left/right, 4 frames per row (frame 3 doubles as the action pose). Tall props
(cot, well, seed box) are 16×32, occupying one walkable footprint tile plus one
overhang tile.

**Palette discipline (the load-bearing rule).** Each material family uses a tiny
ramp — grass renders the entire ground in *six* colors, dirt likewise. Measured
anchors:
- Grass ramp: `#c0d470` (base) → `#a4c263` (mid) → `#78a158` (shadow), highlight
  `#d2e077`.
- Dirt/tilled ramp: `#e8cfa6` (base) → `#dcb98a` (mid), highlight `#eddab5`.
- Crop greens reuse the grass mids (`#a4c263`, `#8db15d`); wheat gold `#eae178`.
- Wood/furniture: `#c49a6c` → `#aa7959` → `#90625d`; accent pastels: rose `#d99a9a`,
  teal `#8cbfc2`.
- Character: cream body `#f3f2c0` with a *deep violet* outline `#5c4e92` — outlines
  are colored, never black, and sit 2+ ramp steps darker than their fill.

**Shape language.** Rounded silhouettes, no hard right angles on organic things;
chibi proportions (~1.5 heads); shadows are hue-shifted (green→darker-warmer green),
never grey/black.

**Contrast model.** Ambient world is low-contrast pastel; *interactables pop by
saturation, not outline weight* (crops and accent props carry the most saturated
pixels on screen). Preserve this: it is why tap targets read at arm's length on a
tablet (S-6/S-7).

**Reserved functional hues (scent overlay & UI, P-10/D-4).** The ambient palette
occupies yellow-green / warm-tan / soft-brown space. Reserve for overlays: magenta
(pest pheromone), cyan (repellent), warm orange (lure), plus a pattern/hatch
variant per channel for colorblind safety — none of these hues appear in the ambient
world, so overlay reads instantly. UI cursor colors already in use (white/green/red)
stay reserved.

**Animation budget.** 4 frames per walk cycle at ~0.15s/frame; single-frame props;
effects carry the motion (particles), not sprite frames — hundreds of entities stay
cheap (ARCHITECTURE budgets).

**Reskin spec implication (Q-7 ruling).** Whatever art replaces the placeholders must
keep: 16px grid, tiny per-material ramps, colored outlines, saturation-pop for
interactables, and the reserved functional hues. Everything else (palette personality,
fidelity, resolution multiplier) is the designer's Q-14 style ruling.

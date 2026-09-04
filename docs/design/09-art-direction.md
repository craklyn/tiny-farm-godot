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

## The look session — the four looks (2026-09-04)

**What this settles:** which treatments get rendered for the designer to choose
between, and which do not. Four captures, and the list is closed.

The designer declined to sign the style guide below on 2026-09-02 and asked to see
it working first — rendered captures of the real game, side by side, before he
rules on palette personality and fidelity (Q-14). This section is the list those
captures are made from. It replaces the strawman of four treatments circulated on
2026-09-02: one is dropped, and the reason is written down here.

**Staging, identical across all four.** The field at mid-morning on day three,
random seed 12345 (the seed the visual-regression check already uses), crops at
mixed growth, the player and one station in frame, same camera, same frame. A
difference the designer sees has to be a difference of treatment and nothing else.

**1. The game as it looks today.** No grading. Every other capture is judged
against this one, and "today" is a legitimate answer to the session.

**2. Quiet world, bright things you can touch.** The ambient world — grass, soil,
fences — pulled toward grey-green and drained of saturation, so the crops, tools
and stations hold every saturated pixel on screen. This is the contrast rule in
the style guide below taken to its end. It is also the treatment that matters most
to test: finding the tappable thing at arm's length on a tablet, without being
told, is this game's hardest readability requirement (S-6/S-7), and this is the
strongest version of the answer to it.

**3. Cold light.** The same drained ambient, but the light turns cold — shadows
shift blue-violet instead of the warmer green the guide specifies, and cyan and
magenta, currently held back for the pest and repellent overlays, come forward
into the machines and meters. This is what a near-future, lightly military
identity looks like from across a room, in colour alone. Shape — hard angles,
panel lines — is not tested here; shape follows a direction rather than the other
way round.

**4. More detail per surface.** More shading steps per material and softer edges,
on the same 16-pixel grid. This is the only one of the four that cannot be graded
out of the captured frame: it needs sheets regenerated through the image pipeline,
which is why it costs money and the other three do not. It is also the only one
that answers how detailed this game should be, which is half of what Q-14 asks.

**What was dropped, and why.** The circulated strawman offered a warmer, cosier
grade — richer saturation, deeper shadows — in the slot cold light now holds. It
went for two reasons. It is barely a different picture: the game today is already
the warm cosy end, so that capture reads as today turned up rather than as a
direction, and a session with two near-identical captures in it spends half its
screen twice. And it works against the contrast rule below — saturating the
ambient world means the crops and tools stop being the most saturated pixels in
it, which is the whole mechanism that makes them read as tappable. If the designer
sees the four and wants warmer, that grade is an hour's work on a frame already
captured.

**One caution for whoever renders capture 1.** The style guide below was measured
from a bought sprite set (Sprout Lands) that this repository no longer contains;
the build ships generated sheets instead. The captures are of the real game, so
the session does not depend on the guide being current — but "the guide's rules,
applied" is no longer something anyone can render, and re-measuring the guide
against the shipping sheets is filed as its own work. Related and separate: four
of the sixteen colours named below read as absent from the build, and all four are
in fact present one step darker in red and identical in green and blue. That is
the asset pipeline shifting a channel by one, not the art drifting, and it is also
filed.

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

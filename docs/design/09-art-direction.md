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

## The ripe crop, and what colour is left (2026-09-07, ruled 2026-09-08)

*Ruled at Q-94: **a ready plant sways gently and gives off its own ripe colour.**
Five candidates were built and switched on the tablet; the losers are deleted and
the two sheets on the decision card are the record of what was compared. This
section keeps the reasoning, because the reasoning outlives the pick.*

**The problem, measured.** Reported from play: nothing on the farm says loudly
enough that a plant is ready to pick, so she has to go looking. The state is
there and so is the picture — a crop has four cells and the fourth is ripe — but
counted off the shipping sheet, **wheat's ready cell differs from the one before
it by nine pixels**, three of them a pale gold highlight, on a 16x16 square. A
tomato is better and still small. That is a real difference on one plant at
arm's length and nothing at all on a plot of thirty, which is exactly what the
report describes.

**The three drafts, and why they are three.** Each spends a different channel,
because they fail in different places and one tuned treatment cannot tell you
which failure matters:

| | Draft | Reads through | Fails where |
|---|---|---|---|
| A | the ripe ones nod | movement — the strongest signal for an eye looking elsewhere | a still picture: a screenshot, a trailer frame, or a decision made from a photograph |
| B | the ripe ones stand up | silhouette — survives grey, distance, a small screen, colourblindness | loudness: it is the quietest of the three in the hand |
| C | the ripe ones give off their own colour | light and saturation — the contrast rule below, taken to its end | colour, which this game has little of left (see the ledger) |
| **D** | **a gentler sway, and the glow — the pick** | both at once — movement finds the eye, light holds it | it pays C's colour bill in full, and it is the one draft a still picture cannot show at all |

**D is what ships.** It was added on 2026-09-08 at the designer's request, looking
at the first sheet:
*"make the ripe ones dance slightly more subtly, but also have their glow."* It is
A at half the travel and a third again as slow, over C's light unchanged. It is a
*fifth position* rather than a replacement, because A, B and C are the isolated
channels and that is the whole reason the sheet can answer anything — a
combination that swallowed its components would leave nobody able to say which
half was doing the work.

**The ruling's own reasoning.** Movement finds an eye that is looking somewhere
else; light holds it once it arrives. Halving the sway is not timidity, it is what
stops the two competing to be the thing you notice — with the light doing half
the work, the motion only has to catch, not to hold. That division of labour is
the transferable part: **when two channels carry one cue, the one that catches
should be quieter than the one that holds.**

**The colour ledger.** A hue is not free here, and this is what each one is
already spending itself on. Anything new has to survive being read against this
table before it is drawn.

| Colour | Already means | Where |
|---|---|---|
| Gold on a dark backing ring | *do this now* | the teaching highlight and its chevron (`main.gd`) |
| Gold | the hour | the sun-arc's token in the HUD (T-29) |
| Blue-white | *done*, and *this square is on the machine's list* | the tap acknowledgement and the mark-1's order rings |
| Magenta / cyan / warm orange | reserved, unspent | the scent overlays (P-10, D-4) |
| White / green / red | the cursor's own states | `main.gd`'s tile cursor |

Draft C therefore spends **no new hue**: it emits the crop's *own* ripe colour,
sampled off the sheets the build actually ships rather than copied out of the
guide below — gold under wheat, red under tomato. The honest costs are on the
card: wheat's own ripe colour is a gold, so a field of ripe wheat is a field of
gold with the teaching gold somewhere inside it, and the pea's ready cell is all
leaf green with no ripe colour to emit.

### Open beside it: should each crop move in its own way? (2026-09-08)

The designer, on being told the sway is one global number: *"I thought we'd just
need to make different crops sway different amounts."* He is right, and the
reason is already half-built — C and D emit the crop's **own** ripe colour, so
*the cue takes on the character of the plant wearing it* is a principle this
feature already follows in the light channel. Motion is the same principle
unapplied: a wheat ear whips, a tomato on a heavy vine nods slowly, and today
they move identically because one constant serves all three.

The shape it would take is a per-crop multiplier looked up exactly as the ripe
colours are, setting the centre that the per-square hash then varies around —
crop character first, plant-to-plant variation on top. Cheap, and it would make
the sprite editor's per-crop page the right home for that crop's number, beside
its frames, which is where the designer went looking for it.

**The constraint that comes with it.** This is a *state* cue, not decoration. A
per-crop difference in how loudly a cue speaks can be read as a difference in
what it is saying — a tomato that barely moves reads as less ready rather than as
a heavier plant, and a cue that means the wrong thing is the failure this project
guards hardest against. So the floor is fixed and asserted: **every ripe plant
moves enough to be obviously moving**, and the per-crop number varies character
above that floor without ever deciding legibility.

Held until Q-94 is ruled, for one reason: only two of the five drafts move at
all, so this is either a small piece of work or a deletion depending on his pick,
and changing what the drafts look like underneath an open decision moves the
thing he is deciding on. Filed to the art director.

### Two rules this produced, whichever draft wins

**A light has to be added to the picture, not painted over it.** C's first
version laid the crop's colour on the tile in ordinary alpha and the capture came
back with the ripe squares indistinguishable from the rest of the plot. That is
arithmetic, not tuning: tilled soil is already a light warm tan, so a pale wash
on it can only ever approach the brightness it has. This is the same wall the
teaching highlight hit — *"pale-on-pale was invisible in practice"* — and the
cot's lamp solved it the same way, on a canvas that blends additively. Any glow
in this game goes on such a layer, and its colour is sampled from the saturated
body of what is glowing rather than from its pale highlight, or the core clips to
white and the colour that was the whole idea is gone.

**Square-to-square variation must be irregular, not periodic.** The ground tiling
picks its cell with `tx % 3` — pure, which is what determinism needs, and also
*predictable*, which is what the CEO rejected on 2026-09-07: a repeat the eye can
predict stops being texture and becomes wallpaper. A cue arriving on a
three-square beat would fail the same way and worse, because a pattern that
regular starts to read as a rule about the farm rather than a fact about each
plant. So every per-square difference in the ripe cue comes from a hash of the
square's coordinates — still a pure function of position, so a save, a replay and
a screenshot land on the same farm, but with no beat in it. Asserted in the unit
suite rather than left as an intention.

**How it was asked.** Two look questions rather than one (`tools/look_scenarios.gd`):
the same plot at the same mid-morning, ten ripe plants among thirty-one, shot once
from the ground and once from the height the camera rises to when the player is
directing a robot (design/11, "Altitude"). A cue that carries in the hand and dies
at that height is not a fix, and neither is one loud enough to carry that shouts up
close — and no single sheet can show both.

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

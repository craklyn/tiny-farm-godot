# What five loops taught

Evidence, not instructions. `ANIMATION_PROMPT.md` holds the rules you must follow;
this file holds what four runs happened to learn while following them.

## How to read this

**These are precedents, not a style guide.** They came from five subjects — a girl
in a spiral of seeds, a crow gorging, a crow hopping, a watering can, a scarecrow
firing beams. Five is not enough to generalise from, and every run that added to
this file also wrote down which of its choices should *not* be copied. Read both
halves.

If your decomposition leads somewhere this file does not cover, that is the
expected case and not an error. Do that, and say why in your docstring. A future
reader is better served by a note explaining why you departed than by a fifth loop
that looks like the first four.

**The cap.** "What the medium does" and "How to work" hold at most twelve entries
each. To add one, remove one and say in your commit which you displaced and why.
A list nobody finishes reading teaches nothing.

**Provenance.** Every entry names the loop it came from. The summary is not the
source — go and read that script if the entry matters to your subject.

---

## What the medium does

Claims about perception and arithmetic at this pixel scale. These travel further
than technique, because they are about the eye and the grid rather than the
subject.

**The governing one, which four separate findings turned out to be instances of:
a curved or repeated form has a threshold below which the eye resolves it as the
simpler shape.** Under it you do not get a weak version of the form, you get a
different form. Measured cases:

- A helix under about **1.5 turns** reads as a ribbon, not a column. At half a turn
  it hugs what it wraps and reads as one line. *(sunflower_bloom, confirmed
  independently by watering_beam)*
- An arc under about **60° of sweep** reads as a line, not a ring. Shorten the
  range before widening the fan. *(scarecrow_mind_beams)*
- Twenty-four beads on a spiral are **not** a spiral — the eye needs a continuous
  line with beads riding it. *(watering_beam)*
- Single columns of ground dust read as a **picket fence** at six pixels apart.
  *(crow_hop_gorge)*

The rest:

- **A secondary element larger than its source becomes the subject.** Ringlets at
  14px around a 16px crow read as a cage she was in, not a strike on her.
  *(scarecrow_mind_beams)*
- **Never put an accent on the pixels carrying the read.** A white flash on the
  scarecrow's face hid the flaring eyes it existed to sell. *(scarecrow_mind_beams)*
- **A blow-up is a blockier small thing, not a big thing.** Enlarging a 16px plant
  2× beside one-pixel effects got "a fully blooming plant shouldn't be six inches
  tall". *(watering_beam)*
- **A light form over a light core is a blob.** A hoop crossing a lit core must be
  a shade darker where it crosses and white only where it stands proud.
  *(watering_beam)*
- **Dark on dark vanishes.** The Lab draws every loop on a near-black sky; a dark
  actor or dark debris disappears on it. *(scarecrow_mind_beams, watering_beam)*
- **At 16px-source scale, drawn connective tissue in the body colour erases the
  silhouette.** A neck drawn to join head to body merged all three into a log.
  *(crow_gorge)*
- **Mirrored x coordinates on a W-wide canvas must sum to W−1, not W.** Every
  symmetric element inherits a one-pixel error until they are pinned to it.
  *(crow_hop_gorge)*
- **The lowest opaque pixel of a sprite is a corner, not a tip.** Water leaving it
  looked like it came from beside the spout. *(watering_beam)*

---

## How to work

Method rather than material. This is where the runs agreed most, and where the
agreement was reached independently.

- **Measure; do not trust your eye on a contact sheet.** All four runs arrived
  here separately. Per-frame bounding boxes caught two intersections and a 40px
  one-frame body swing the sheet hid *(crow_hop_gorge)*. A "missing" tomato was
  counted and found present — 116 red pixels — and a pattern-matched fix would
  have broken a working frame *(crow_gorge)*. Follow one moving front frame to
  frame numerically before showing anyone; the water was climbing back into the
  can and no one saw it *(watering_beam)*.
- **Write each invariant into the script as an assertion, and run them at the
  slider extremes rather than the defaults.** *(crow_hop_gorge)*
- **Derive anchor points from the sprite's own pixels** — the rose's centre, the
  soil line, the eye. Constants go stale the moment the art is edited or swapped,
  and the Lab now tells you when that has happened. *(watering_beam)*
- **One coordinate map for pixels and landmarks alike.** Deriving a beak root
  separately from the pixel move detached it for two passes. *(crow_gorge)*
- **Re-pose at 1× first, then enlarge.** Moving pixels inside the small source
  cell preserves the character by construction; cutting an already-enlarged sprite
  destroys the silhouette immediately. *(crow_gorge)*
- **Any transform that can push pixels past the source cell needs a wider working
  canvas**, with the margin computed from the extreme pose. A mirrored lunge
  clipped silently and left a faceless bird for a whole pass while the code looked
  correct. *(crow_gorge)*
- **Compute the extreme position a control allows, not the default one**, when
  checking for clipping — for rings, at the last dotted frame at maximum spread.
  *(scarecrow_mind_beams)*
- **Derive reaction beats from the parameter they react to.** The strike frame is
  computed from the beam speed, so dragging the speed cannot make her flinch
  before the ring arrives. Otherwise the instruments lie. *(scarecrow_mind_beams)*
- **Age anything emitted late as `(frame − emit) mod N`** so a slow dial crosses
  the loop seam without popping. *(scarecrow_mind_beams)*
- **Rotate the pattern, do not translate it.** A phase that advances one full turn
  per loop is seamless for any number of turns; a translating thread only closes
  on whole ones. *(watering_beam)*
- **Aim particle fans back toward the actor near a canvas edge.** An outward fan
  gets edge-culled within a frame or two and reads as no splatter at all — it
  looks like an amplitude problem and is a direction problem. *(crow_gorge)*
- **Dump the source cell as ASCII art, one character per palette colour, before
  planning any cut.** It is how the crow's head rows, beak pixel and legs were
  found. *(crow_gorge)*

---

## What did not travel

Given equal billing on purpose. Each of these worked, and each is wrong to copy.
The runs volunteered them when asked, which is itself the finding: the person who
made a thing usually knows which parts were local.

- **Head-only motion on a frozen body** reads as a perched bird. On most subjects
  a moving cut-region over a still body reads as paralysis. *(crow_gorge)*
- **A one-frame 180° mirror** reads as bird behaviour because crows really do snap
  round. On a mammal or the girl it reads as broken. *(crow_gorge)*
- **A world that resets** — eaten fruit falling away, a fresh one swinging in —
  belongs to a subject that consumes the world. A loop that consumes nothing
  should not inherit a regrow mechanic. *(crow_gorge)*
- **4× enlargement and a 128×96 canvas** are gross-up choices. So is staying at
  1×. Neither is a default; decide from what has to act, because a one-pixel eye
  cannot act. *(crow_gorge, scarecrow_mind_beams)*
- **Building the anchor from the farmer's own cell** worked because a scarecrow
  literally is her clothes on a pole. Reskinning her into any other prop is wrong.
  *(scarecrow_mind_beams)*
- **The panic vocabulary** — exclamation, spinning swirl, sparks, sweat — is
  comic-strip shorthand for a joke loop. A cozy or serious subject should not
  inherit it. *(scarecrow_mind_beams)*
- **Splitting depth on the beam axis** works because the beam is horizontal and
  the actors are in profile. Vertical motion needs a different plane.
  *(scarecrow_mind_beams)*
- **Generating new source art** was right only because the subject needed a plant
  at true scale and no shipped sheet has one. Anything with a shipped source stays
  its own pixels. *(watering_beam)*
- **The lossless quarter turn of the can** works because that sprite's spout
  happened to point up-right. It is a property of the sprite, not a technique.
  *(watering_beam)*
- **A five-step teal ramp** exists because the can, well and bot are teal. Another
  material may have no such ramp and needs dither or fewer bands. *(watering_beam)*
- **Two beats per loop, 32 frames, 2×8 windup/strike/tear/gulp** — every one of
  these is a subject's own rhythm. Find yours. *(crow_gorge, crow_hop_gorge)*
- **"Busy" as a goal** was true for one subject only. *(watering_beam)*
- **A corner-nibbling softening pass** exists solely to make 4× NEAREST blocks
  read as drawn. At world scale it is pointless and mildly destructive.
  *(crow_gorge)*

---

## Questions each run had to answer for itself

Not answers. If you find yourself inheriting one of these rather than deciding it,
stop and decide it.

- Where does the loop's reset live — does the world cycle, or only the motion?
- How many beats does this subject have, and how many frames does a beat need?
- What scale is this drawn at, and does anything here need to act at one pixel?
- Where on the source sprite does the effect originate, and what does that
  sprite's own geometry dictate?
- What one thing changes to signal depth, and when does its step land? Only one
  thing may, and its change must land under motion.
- What is any mirror flipped *about*? A flip is a discontinuity of whatever is
  farthest from the axis.
- Should the motion follow physics or Daniel's eye? He has decided both ways
  within an hour. Show him; do not assume.
- Which five to seven numbers are worth a slider *for this subject*?
- What is the worst-case ground this will be judged on?
- How much of the schedule hangs off a parameter, and how much is fixed?

---

## Where the map ends

Nobody has done these. If you are first, say so in your docstring, and add what
you learn.

- **A light ground.** Every loop so far assumes a dark sky, and the depth-by-
  brightness convention leans on it. On a light ground it may invert or fail.
- **A loop the game actually plays.** All five are gallery pieces. None has been
  wired to an entity, a state, or an event, and nothing is known about frame
  budgets, memory, or how a loop behaves next to the real world's tiles.
- **A loop that must tile or repeat spatially**, rather than in time.
- **A subject with more than two actors**, or actors that occlude each other
  through the whole loop rather than at a moment.
- **Whether 16 or 32 frames is right, and why.** Both exist; no run has compared
  them on the same subject.
- **Sound.** Nothing here has ever been made to land on a beat.

---

## The precedents

Read the script, not this summary, when an entry matters to your subject. Each
carries its own decomposition in its docstring.

| Loop | What it is worth reading for |
|---|---|
| `vfx_sunflower_bloom.py` | The simplest case: one anchor, one parametric motion, three life stages. Start here. |
| `vfx_crow_gorge.py` | A close-up built by enlarging a shipped sprite, and the silhouette discipline that requires. |
| `vfx_crow_hop_gorge.py` | Assertions as invariants, mirrored geometry, and a subject that moves its whole body. |
| `vfx_watering_beam.py` | Curves with arc-length tables, seamless rotating patterns, and the `prep_` step that derives editable source art. |
| `vfx_scarecrow_mind_beams.py` | Two actors, a reaction schedule derived from a parameter, and emission that survives the loop seam. |

`prep_watering_beam.py` is worth reading separately: it is the pattern for a
subject whose art does not exist yet, and it produces hand-editable files under
`assets/showcase/<slug>/` that the Lab watches for changes like any shipped sheet.

# 15 — Interiors: buildings you walk into without leaving the farm

*Status: directive received 2026-09-14, nothing built. This chapter is the analysis
the directive asked for, not a specification. What it settles is recorded as P-18;
what it cannot settle is filed as Q-items and D-items and named here.*

---

## 1. The directive

The CEO, 2026-09-14, answering a question about the chicken coop and replacing it
with a larger one:

> "Inside the coop and inside the house should obey a new game design
> principle/style… A house outside that's three by three looks pretty big, and it
> takes a while to walk past and just kind of gets in the way of other stuff you
> want on the screen when you're outside. On the other hand, the inside of a three
> by three house is very small… So what I want is the following. When a player
> enters an enclosed space like this, we will zoom in the character a certain
> amount so that the grid size in the new space is drawn at the same size as the
> grid space was drawn in the overworld. However, each inside space can be an
> arbitrary dimension that we set… And while inside the house, we can still see
> outside the house."

Two complaints and one idea. The complaints are real and worth stating in their own
words, because they are what any answer has to fix:

- **Outside, a building is too big.** It occupies screen the farm wants for farming,
  and walking around it is dead time.
- **Inside, the same building is too small.** A 3×3 room loses one tile to a bed
  (two, at the size the bed is actually drawn) and there is nothing left to furnish.

The conventional fix is a hard cut: tap the door, the screen swaps to a room drawn
at whatever size the room wants to be, and the two sizes never meet. Every game in
this genre does it that way. The idea here is to **refuse the cut** — to let the
building dilate in place, so the player watches the small thing become the big
thing and never loses the farm.

---

## 2. The principle, stated once

> **A tile is always the same size on screen. Entering a building changes which
> space the camera measures in; the rest of the world is then drawn at whatever
> scale keeps the doorway where it was.**

That is the whole of it, and every consequence below follows from it mechanically.

It is worth noticing what the principle does *not* say: it does not say the
character changes size. She does not. She is one tile tall inside and one tile tall
outside, and one tile is one tile's worth of pixels in both. What changes size is
**everything outside the building she is standing in**.

### The arithmetic

| symbol | meaning | today |
|---|---|---|
| `T` | screen pixels per tile | 48 (16 px art × `main.gd`'s `CAMERA_SCALE` of 3) |
| `F` | the building's footprint, in overworld tiles | coop 2×2, farmhouse 3×2 |
| `R` | the room inside it, in interior tiles | to be chosen per building |
| `k` | dilation factor, `R / F` | to be chosen |

Standing inside, the room fills `R × T` pixels where the footprint used to fill
`F × T`. So the world outside, if it is to stay registered with the doorway, must be
drawn at **`k` times its normal scale**. A 3×3 house with a 9×9 room magnifies the
farm behind it three-fold.

**Constrain `k` to a whole number.** Nothing forces this and everything is better
for it:

- Integer scaling of pixel art is exact — no filtering, no shimmer, no half-pixel
  seams on the magnified farm. Non-integer scaling of a 16-pixel tile is the single
  most reliable way to make this look cheap.
- `k` the same in both axes means the outside is *dilated*, not *stretched*. A room
  that is 8 wide and 6 deep inside a 3×3 footprint needs two different scale factors
  and the farm behind it is squashed.
- The transition animates cleanly from 1 to `k`.

So a room is its building's footprint multiplied: the 2×2 coop at `k = 3` is a 6×6
room; the 3×2 farmhouse at `k = 4` is a 12×8 room. Both are enormous next to what
they replace, and neither needs the footprint outside to grow by a single tile.

### The CEO's own numbers, and what they cost (2026-09-15)

> "please make the house 3-wide by 2-tall. And when the player is inside, please make
> it 6-wide by 3-tall."

Those are much less extreme than the ×3 and ×4 this section reached for, and the
pictures say the restraint was right — see §3. They also break the whole-number rule
above, and it is worth being exact about how much that costs rather than arguing from
the rule:

- Across, 6 tiles of floor over a 3-tile footprint is **×2**, which is clean: one art
  pixel becomes six screen pixels.
- Down, 3 tiles over 2 is **×1.5**, which is not: one art pixel becomes four and a half
  screen pixels, so every other row of the magnified farm is doubled and the rest are
  not. On the hen standing in the yard outside, visible at this scale, the effect is a
  slight squatness and a ragged comb. It is a blemish rather than a disaster.
- The two factors also differ, so the yard beyond the walls is *stretched* rather than
  dilated — wider than it is tall by a third.

**A 6×4 room fixes both for the price of one row of floor**: ×2 in each axis, integer
scaling everywhere, no stretch. Recorded as the cheap alternative rather than as a
correction, because a 6×3 room is a shape and the shape may be the point.

---

## 3. What the player experiences

**Going in.** She taps the door and the building opens outward over about a third
of a second — the hut's walls sliding out past the edges of the screen, the yard
swelling behind them, her own body never changing size. She ends up standing in a
room several times larger than the hut she tapped, with the farm still there,
magnified and softened, beyond the walls.

**Being in.** The farm is present but out of reach, which is the correct feeling and is
achieved by geometry rather than by a fade. **How much of it she can see is the thing to
measure, and it was measured wrong here first.** On an 800×600 screen at camera scale 3:

| room | dilation | yard visible each side |
|---|---|---|
| 3×2 house → 6×3 (the CEO's numbers) | ×2.0 across, ×1.5 down | 2.7 tiles across, 3.2 down |
| 3×3 house → 9×9 | ×3 | about 1 tile |
| 3×2 house → 12×8 | ×4 | none worth the name |

The multiplier eats the view twice over — a bigger room leaves less margin *and*
magnifies harder into it — so this falls away faster than it looks like it should. At
the CEO's numbers there is a real amount of farm out there: in
`mockups/interiors/q108_registered.png` the hen, the shipping bin, the fence and the
neighbour's plot are all legible through the walls. At ×3 there is a field of green and
one enormous soft shape. **The restraint is what makes the registered option viable at
all**, which is the opposite of what an earlier draft of this chapter assumed.

**Coming out.** The reverse, anchored on the same doorway, so the world contracts
back to exactly where she left it.

### The perceptual risk, honestly

Registering the outside to the doorway **magnifies** it, and magnification normally
reads as *nearer*. There is a real chance that standing in a room and seeing the yard
loom larger reads as wrong — the opposite of the "I am inside, the world is out there"
feeling the design is chasing.

Two answers, and this is a taste call rather than an engineering one (**Q-108**):

- **(a) Registered dilation.** The outside is geometrically true relative to the
  doorway, magnified by `k`, behind fog. Honest; the transition is a real continuous
  zoom; risks reading as "the world got closer".

  **"Registered" has to mean registered.** The first version of the Q-108 sheet pasted
  a farm capture behind the room as *wallpaper*, which cannot keep a relationship it
  never had — the gap between the house and the shipping bin beside it survived in the
  outdoor panel and vanished in the indoor one. The CEO caught it on 2026-09-15. The
  plate now carries the camera's world-to-screen mapping beside it and the farm is
  placed rather than pasted, and that gap is the test the picture has to pass.
- **(b) Unregistered backdrop.** The outside is drawn at its ordinary scale behind
  fog, as scenery that does not line up with anything. Reads the way a window reads;
  the transition has nothing to animate, so the cut comes back in spirit if not in
  fact.

The fog is not decoration in either case. It is what makes the seam between two
scales legible as *wall* rather than as a rendering artefact, and the directive
already anticipated it.

---

## 4. How the world is represented

The directive asks the question directly: one master grid with sub-coordinates, or
a coordinate system per room with a mapping between them?

### The three candidates

**Model A — one master grid, as today.** The world is a single `SimWorld` whose rows
are stacked in 20-row pages: page 0 is the farm, page 1 is the home interior, and a
door is the only way between them (`WorldLayout.compose`, `PAGE_ROWS`).

- *For:* one grid, one save format, one pathfinder, one renderer, no translation
  anywhere, determinism free. It is what exists and it works.
- *Against:* **distance is meaningless across spaces and the code does not know it**
  (§5). And rooms of arbitrary size do not tile into fixed pages, so a farm with
  buildings that come and go needs a region allocator whose state is saved, replayed,
  and must agree with itself on reload.

**Model B — a coordinate system per space.** Each room is its own grid with its own
origin. A portal maps `(space, tile) → (space, tile)`. Every tile reference in the
game becomes a pair.

- *For:* rooms are naturally any size; creating and destroying them is creating and
  destroying a grid; **distance across spaces is undefined by construction**, which is
  the correct semantics rather than a rule somebody has to remember.
- *Against:* every `Vector2i` in the sim, in Actions, in the replay log, in saves and
  in the renderer grows a companion. It is a mechanical change but a wide one, and the
  replay format is the one thing the project has committed not to break casually.

**Model C — one master grid, plus a space predicate.** Keep the single grid exactly as
it is. Add one derived question — *which space is this tile in?* — read off the grid
the way `is_parcel_open` and `is_coop_tile` already are, kept nowhere and saved never.
Then define: **a measurement between two tiles in different spaces has no answer.**

- *For:* the grid, the saves, the replays, the pathfinder and the renderer are
  untouched. Routing already cannot leak between spaces, because the dark between pages
  is not walkable. The change is one predicate plus a guard at each of the handful of
  places that measure (§5). It is small, and it has Model B's semantics where it counts.
- *Against:* it inherits Model A's allocator problem for rooms that come and go, and it
  is a discipline rather than a type — nothing stops the next radius check from
  forgetting the guard, where in Model B it could not compile.

### Recommendation

**Model C now, Model B when rooms become dynamic.** The distinction that matters is not
where the numbers live, it is whether the game believes in one global metric. Model C
stops it believing that, today, for the cost of an afternoon. Model B is what to build
the day a building the player can place gets an interior — because that is the day rooms
start being created and destroyed at runtime, and an allocator over a fixed grid is a
worse version of the thing Model B is.

That gives a clean sequencing: **the farmhouse and the coop get interiors under Model C
on the existing pages; anything the player can place and pick up waits for Model B.**

---

## 5. Distance between spaces, and why it must be undefined

The directive asks what happens when two entities in two different buildings need to
know how far apart they are.

**The answer is that the distance does not exist — not that it is large.** Three reasons,
and the third is the one that settles it:

1. A sense is about a shared local frame. A crow does not flee because the farmer is
   forty steps away through two doors; it flees because she is *near and visible*.
2. Measuring through the portal graph costs a route search per sense check per tick,
   against a rule that per-tick cost scales with actors and not with the map.
3. **There is no consistent number to return.** A 3×3 hut with a 9×9 room means walking
   nine tiles indoors moves you three tiles in the world. Whichever metric a cross-space
   distance picked, it would be wrong in the other space — and §6 shows that this is not
   a choice that can be made well, it is a choice that cannot be made at all.

So: anything that needs a relationship across spaces uses a different primitive — *are
we in the same room?*, or a portal-graph route — and never a subtraction.

### What is measuring today, and what it would cost

This is not hypothetical. The audit of the current build, 2026-09-14:

| what | where | guarded? |
|---|---|---|
| scarecrow protection, ±4 tiles | `sim_world.gd` `is_protected_by_scarecrow` | **no** — raw grid scan |
| the player's spook radius, 3 tiles | `entities/crow.gd` `_player_is_near` | **no** — pixel distance between two nodes |
| grazer `crop_sense`, 5 tiles | `species_defs.gd` rows | **no** |
| the nearest actor to a tile | `sim_world.gd` `nearest` | **no** |
| scent blob radius | `sim/scent.gd` `deposit_blob` | **no** |
| sprinkler radius, shoo radius, follow distance | `sprinkler_brain.gd`, `bot_brain.gd` | **no** |
| a crow leaving the world | `crow_brain.gd` `_off_the_map` | **yes** — and it had to be taught |

Every one of these is correct today by **coincidence of layout, not by rule**: the home's
floor begins six rows below the farm's last row, and the largest radius in the game is
four. Move a room one page closer, or allocate a coop's interior next to the farm, and a
scarecrow in the yard starts frightening birds through the floorboards.

The last row is the tell. `crow_brain._off_the_map` carries a comment dated 2026-09-06 —
*"the farm's bottom edge is where a bird leaves the world, not where the home's
floorboards start"* — which is this exact bug, found once, fixed in one place, by hand.
A `space_of` predicate is that fix generalised before the other seven copies of it have
to be found the same way.

---

## 6. Cycles, and the one theorem in this chapter

The directive asks whether four rooms linked in a ring — A to B to C to D to A — can
end up with metrics that disagree, and whether there is a theoretical limit here or
whether it is straightforward.

**It is not straightforward, there is a real theorem, and the design has to respect it.**

Gluing flat pieces together along their edges makes a *piecewise-flat surface*. Walking a
closed loop across such a surface and composing the transition maps need not return the
identity — the leftover is called **holonomy**, and it is the same fact that says a sphere
cannot be flattened onto a page without tearing. Three flavours can leak out of a loop:

- **Displacement** — you return to A somewhere other than where you left.
- **Rotation** — you return facing differently, if portals may turn you.
- **Scale** — and this is the one that bites here. Every portal into a building carries a
  factor `k`; every portal out carries `1/k`. Around a loop the factors multiply, and if
  the product is not 1, **a creature can walk a circuit and come back a different size.**

No amount of care avoids this. It is a property of the gluing, not of the implementation.
What can be done is to make sure nothing ever *needs* the product to be 1. Two rules do
that, and they are the design's real load-bearing constraints:

### Rule 1 — no global metric (§5, restated as geometry)

Holonomy is only a contradiction if the game claims a single flat coordinate system that
all spaces embed in. It does not have to claim that. A cycle whose scale factor is 6
is perfectly consistent as long as nothing ever asks "how far is it, really" — it is just
a building that is a shortcut one way and a longcut the other, which players read as
ordinary and even pleasant. **The cyclic-rooms worry and the cross-space distance worry
are the same worry, and Rule 1 answers both at once.**

A useful consequence: **multi-door buildings are fine.** A hut with a front and a back
door is a cycle (out → in → out), its holonomy is real, and it costs nothing, because
nothing measures across it.

### Rule 2 — transparency is one level deep

Here is where the directive's own feature re-introduces the thing Rule 1 just abolished.
**Drawing two spaces in one picture is exactly claiming they embed in one flat frame.**
If, standing in hut B, the player could see into hut C's interior through two walls, the
renderer would have to embed B and C and the farm simultaneously — and around a cycle that
picture cannot be made to close.

So: from inside a space you see **your own space at 1×, and its parent at `k`×, and
nothing deeper**. Siblings are never visible as interiors; a neighbouring hut seen from
inside your own is a hut, closed, the way it looks from the yard. The drawn scene is
always a tree of depth two, and a tree always embeds.

This is not a limitation grudgingly accepted. It is what keeps the feature coherent, and
it happens to be exactly what a player would expect anyway.

### Rule 3 — the portal graph is rooted

Not forced by the theorem, but it makes everything easier and costs nothing yet: the
overworld is the root, and every building hangs off it. Building-to-building portals are
possible under Rules 1 and 2 and should simply wait until something wants one.

---

## 7. Custom exits

The directive asks whether a staircase, a lift, or some other non-edge exit belongs in
this system or needs its own.

**It is already in the system, and the codebase picked the right primitive before the
question came up.** A door today is not "walk off the edge of a room". It is a named pair
— `WorldLayout.door_at` returns `{from, to}`, and `use_door` resolves the pair and puts
her down on the far side. A staircase is that primitive with a different sprite and a
different sound. Nothing about a portal's geometry cares whether it sits in a wall, in the
middle of a floor, or at the top of a ladder.

Two extensions, neither of which disturbs the above:

- **A portal with more than two ends** (a lift that serves three floors) is a chooser
  after the tap. That is UI, not geometry.
- **A portal whose far end depends on state** (a floor not yet unlocked) is a lookup at
  resolve time.

What would *not* fit is an exit that moves the player continuously between spaces — a ramp
she walks up, crossing the seam mid-stride, rather than a threshold she steps through. That
needs two spaces drawn at two scales with a creature in both at once, which is Rule 2's
forbidden picture. **Portals are discrete.** If a continuous ramp is ever wanted, it is a
new chapter, not an extension of this one.

---

## 8. Implementation notes, Godot

Recorded so the estimate is honest. Nothing here has been built.

- **The sim barely changes.** This is a presentation feature plus one predicate. Layer 2
  gains `space_of(tile)` and a guard on each measurement in §5; it gains no verb, no new
  state, and nothing that could desync a replay. That is the strongest argument for the
  whole approach.
- **The camera already knows about pages.** `main.gd` clamps `camera.limit_*` to the page
  the player is on and refreshes it as she moves (`_refresh_camera_limits`, 2026-09-06).
  This becomes: limits come from her current space, and `camera.zoom` is `CAMERA_SCALE`
  multiplied by that space's own factor.
- **Two canvas layers, not a viewport.** The parent space is drawn by a node carrying its
  own `Transform2D` — scale `k`, translated so the doorway registers — with a fog or blur
  over it; the current space is drawn at 1× on top. `world/farm.gd` already draws
  everything through one render queue, so this is a second queue with a transform, not a
  rewrite. A `SubViewport` would also work and costs more for nothing.
- **The transition is a `Tween`** on the camera's zoom and the parent transform together,
  around 300–400 ms, eased, anchored on the doorway tile. This animation *is* the feature;
  it deserves the same care as the boot bloom.
- **Integer `k` is what makes it cheap.** With `k` a whole number the magnified parent needs
  no filtering and produces no seams, and the fog is then a choice rather than a cover-up.

---

## 9. What is settled, what is not

**Settled by the directive and recorded as P-18:** the principle in §2; interiors larger
than their footprint; the outside remains visible; entering is continuous rather than a cut.

**Settled by analysis, recorded in P-18 as consequences:** distance across spaces is
undefined (§5); transparency is one level deep (§6, Rule 2); portals are discrete and a
staircase is an ordinary portal (§7); `k` is a whole number (§2).

**Open, and filed:**

- **Q-108** — registered dilation or unregistered backdrop (§3). A taste call that decides
  whether the transition animates. Drawn as pictures over a photograph of the real room, in
  `mockups/interiors/q108_outside_treatment.png`, and they carry a finding the prose above
  did not: at `k = 3` the registered option leaves about **one tile of yard a side**,
  magnified past recognition. The view out is not a detail of that option, it is most of
  what is being traded.
- **Q-109** — what `k` is for the farmhouse and for the coop, which is really the question
  of how much room a room should have, in `mockups/interiors/q109_*_multipliers.png`. It is
  **coupled to Q-108**: the same number sets the room's size and the yard's magnification, so
  under the registered option every step up is paid for out of the window.
- **D-16** — when the sim moves from Model C to Model B (§4). The trigger is the first
  interior belonging to a building the player can place and pick up.

**Deliberately not answered here:** what is *in* a room. This chapter is about the shape of
the space and nothing else; furnishing, chores, and what the coop's inside says about the
hen are the coop's own questions and live with P-17.

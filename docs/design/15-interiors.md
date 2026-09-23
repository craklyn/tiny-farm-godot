# 15 — Interiors: buildings you walk into without leaving the farm

*Status: directive received 2026-09-14, corrected 2026-09-15, **first version built the same
day** — the chicken coop has an inside, and you walk into it. What is in the game and what is
not is §9. What this chapter settles is recorded as P-18; what it cannot settle is filed as
Q-items and named here.*

---

## 1. The directive

The CEO, 2026-09-14:

> "Inside the coop and inside the house should obey a new game design principle/style… A
> house outside that's three by three looks pretty big, and it takes a while to walk past
> and just kind of gets in the way of other stuff you want on the screen when you're
> outside. On the other hand, the inside of a three by three house is very small… So what
> I want is the following. When a player enters an enclosed space like this, we will zoom
> in the character a certain amount so that the grid size in the new space is drawn at the
> same size as the grid space was drawn in the overworld. However, each inside space can be
> an arbitrary dimension that we set… And while inside the house, we can still see outside
> the house."

And the numbers, 2026-09-15: **the house is 3 wide by 2 tall; the room inside it is 6 wide
by 3 tall.**

Two complaints and one idea. The complaints are worth stating in their own words, because
they are what any answer has to fix:

- **Outside, a building is too big.** It occupies screen the farm wants for farming, and
  walking around it is dead time.
- **Inside, the same building is too small.** A 3×3 room loses two tiles to a bed, at the
  size the bed is actually drawn, and there is nothing left to furnish.

The conventional fix is a hard cut: tap the door, the screen swaps to a room at whatever
size the room wants to be, and the two sizes never meet. Every game in this genre does it
that way. This refuses the cut.

---

## 2. The principle

> **One world, one metric, two grids.** A building's interior is a **finer grid nested
> inside the building's own footprint**. Going inside is a **uniform camera zoom** and
> nothing else.

The house stands on 3 tiles by 2. The room inside it is 6 cells by 3 **at half that
pitch** — which is 3 tiles by 1.5, so it fits inside the footprint with the top half-row
left over for the roof. Zoom the camera ×2 and those half-pitch cells render at exactly
the size an outdoor tile used to, which is the directive's own sentence. The yard renders
at twice its usual size, because everything did.

Nothing stretches. Nothing is registered to anything, because nothing ever came apart.

`mockups/interiors/q108_two_zooms.png` is those two panels: the same photograph of the
running game, the same composition, one uniform zoom between them.

### The leftover band, and the rule that follows

A uniform pitch is set by the **tighter** axis. Six cells across three tiles wants two
cells per tile; three cells down two tiles only wants one and a half. The room has to fit
across, so the pitch is two — and the room is then three tiles by one and a half, leaving
**half a tile of footprint unused at the top**. The CEO spotted the strip on 2026-09-15 and
asked the right question: constrain the shapes so it never appears, or spend it?

**Spend it, and the rule is this:**

> Pick an integer pitch `k` (interior cells per outdoor tile). The room's **width is the
> footprint's width × `k`**, exactly — so it fills across and the pitch is clean. Its
> **height is free**, anything up to the footprint's height × `k`. Whatever height is not
> used is a band of whole cell rows at the top, and that band is the **roof**.

The house at `k = 2` therefore has a room six cells wide and anything from one to four
cells deep. Six by three is the CEO's choice and leaves one cell row of eaves.

Three reasons this beats matching the shapes (`mockups/interiors/q108_leftover_band.png`
draws both):

1. **It is the only place a building's identity can be.** Under the nested grid every
   interior is a rectangle of floor with edge cells, so a house and a hen house look
   identical from inside except for the furniture. The band is where the roofline goes, and
   the roofline is what says which building she is standing in.
2. **It keeps the freedom the directive asked for** — *"each inside space can be an
   arbitrary dimension that we set"*. Matching the shapes takes that away: the room's
   proportions become the building's proportions, and a 3×2 house can only ever hold a 6×4,
   a 9×6, a 12×8.
3. **The asymmetry is correct rather than tolerated.** The band lands at the top, which in
   this projection is where a roof is. The bottom edge is the wall the door is in.

What it costs is floor: at `k = 2` a 6×3 room is one row smaller than the 6×4 that would
fill the footprint exactly. That is the price of the roof, and it is the same trade the
game already makes outdoors, where a house's top half is roof rather than room.

**The constraint this implies**, worth stating because it is the only thing the rule
forbids: a room may not be a *narrower* shape than its building. Rooms are as wide as their
footprint and as deep as they like, up to it.

### What this corrects

An earlier draft of this chapter read the directive as a **differential transform** — the
room drawn at one scale with the outdoors deformed around it by another, anchored on the
doorway. That is a different design that answers the same words, and it is worse in every
respect: it stretches the yard when the two axes disagree, it needs the outside registered
to a doorway by hand, and it makes distance between two spaces meaningless. The CEO
corrected it on 2026-09-15 with two pictures showing the house and the yard growing *by the
same factor, together*.

Three sections of this chapter existed only to manage problems that design created. They
are kept below, marked, because the reasoning is sound and the day something really does
glue two spaces together it will be wanted again — but **none of it applies to the nested
grid**, and reading it as though it does would be reading the wrong design.

---

## 3. What the player experiences

**Going in.** She taps the door and the view zooms in over about a third of a second. The
house does not open or dissolve; it simply gets nearer, and at the end of the move the room
that was a smudge inside its walls is a floor she is standing on at full size. Her own body
grows with everything else, because it is one world.

**Being in.** The farm is present, out of reach, and twice its usual size. On an 800×600
screen at camera scale 3 the room fills 288×144 pixels and there are **2.7 tiles of yard
visible across and 3.2 down** — the hen, the shipping bin, the fence and the neighbour's
plot all read through the walls. Enough to know the weather and notice a crow. Not enough
to farm.

**Coming out.** The reverse zoom, on the same centre.

**What it costs to see out.** The zoom is what decides this, and it falls away fast: a room
twice the size needs twice the zoom, which leaves a quarter of the yard on screen. The
CEO's numbers are modest and that is what makes the outside worth looking at; the ×3 and ×4
rooms an earlier draft reached for leave about one tile of yard, magnified past recognition.

### The perceptual question that remains (Q-108)

Under a uniform zoom there is no geometric lie to catch, so what is left is a question of
grain rather than of truth: at ×2 the yard is drawn at six screen pixels per art pixel, and
whether that reads as *outside, seen through a window* or as *the world came closer* is a
matter of treatment — haze, desaturation, how hard the walls cut. That is what Q-108 now
asks, and it wants captures rather than paragraphs.

---

## 4. How the world is represented

Two ways to build this, and the difference between them is the whole cost of the feature.
Measured 2026-09-15 rather than estimated.

### A — one global fine grid

Every outdoor tile becomes `k` cells and the whole world is stored at cell resolution. One
grid, one metric, nothing nested — conceptually the cleanest thing there is.

| what it touches | count |
|---|---|
| files reasoning in tiles | 55 |
| call sites indexing `tiles[y][x]` / `objects[y][x]` directly | 83 |
| verbs whose target tile changes meaning | 37 |
| **unit-test assertions naming explicit tile coordinates** | **538** |
| save format | v3 → v4, every farm migrated |
| replay format | every logged target re-interpreted |

The 538 is the one that settles it. Those assertions are not scaffolding; they are the
record of what the game actually does, written coordinate by coordinate over months, and
re-deriving them all is both enormous and exactly the operation most likely to launder a
real regression into a "fixed" test. **This is not the way.**

### B — an anchored sub-grid per interior  ← recommended

The farm is untouched. A building with an interior owns a **small grid of its own**, which
declares two things:

- an **anchor**: the building's footprint on the farm;
- a **pitch**: how many of its cells fit in one farm tile.

Those two facts are what make it more than a second map. Every interior cell has an exact
world position — `anchor + cell / pitch` — so:

- **Distance is well defined** between anything inside and anything outside, without a
  global resolution change. The senses work; nothing needs a guard.
- **Rendering is exactly registered** by construction: draw the farm at zoom `Z` and the
  room at `Z × pitch` about the anchor, and the room sits in its building because that is
  what the anchor says.
- **Going in is a camera zoom** of `pitch`, and nothing else moves.
- **A room is created and destroyed with its building**, so the coop can still be picked up.
- **Saves grow by a field.** Old farms have no rooms; the format is additive.

What it reuses, all of it shipped and proven:

| the room needs | what already does it |
|---|---|
| walls that block | `WorldLayout.WALL` + `is_boundary_state`, refused by `is_walkable` |
| a doorway cut in a wall | `GATE_OPEN`, exactly how the home's south wall works |
| a floor | `WorldLayout.FLOOR` |
| a declared threshold pair | `WorldLayout.door_at` returns `{from, to}` |
| movement over a grid | `Movement` is already `(world, mode, tile)` throughout |
| a camera that zooms and pans smoothly, clamped | `main.gd`'s altitude gesture, shipped for robot teaching |

**And it is re-implementable.** Anchor plus pitch is precisely the information needed to
flatten every room into option A later, if a future requirement ever wants one global grid.
Choosing B now forecloses nothing; choosing A now cannot be undone.

### What B costs

Two coordinate spaces exist again, so an actor's position is `(space, cell)` rather than a
bare tile. That is contained — the registry already stores a position per actor, and the
mapping above turns any of them into a world position on demand — but it is the one place
where the design is genuinely more complicated than a single grid, and it is the price of
not touching 538 assertions.

---

## 4a. The wall and the threshold

The invention the CEO asked for on 2026-09-15, and it turns out to need less inventing than
feared, because the game already contains a room with walls and a door cut in one of them.

**A room is its building's footprint at the room's own pitch, with a one-cell boundary ring.**

For the chicken coop, at pitch 3:

```
    footprint  2 x 2 tiles          room grid  6 x 6 cells
    +-----------+                   # # # # # #      #  WALL   - blocks, and is the
    |           |                   # . . . . #                building's own shell
    |           |   zoom x3          # . . . . #      .  FLOOR  - 4 x 4 of it
    |           |  ----------->     # . . . . #      +  GATE_OPEN - the doorway,
    |           |                   # . . . . #                one cell of the south wall
    +-----------+                   # # + # # #
```

Why a ring of cells rather than a rule about edges:

1. **No new blocking concept.** `is_walkable` already refuses boundary states. A wall cell
   is a wall the same way the home's walls are walls, and every mover — farmer, hen, a
   future bot — obeys it without being told.
2. **The ring is the building**, seen from inside. Its top row is the roofline the band
   question was about; its bottom row is the wall the door is cut in. The shell and the
   blocker are one thing rather than two that can disagree.
3. **It fails visibly.** A room that lost its ring is a hole you can see, not a silent leak.

**The threshold** is a declared pair, `door_at`'s existing shape: the `GATE_OPEN` cell in
the south wall ↔ the farm tile immediately below the footprint. Crossing it is the one place
the pitch changes, and it is one named edge rather than a property of the boundary in
general.

**The ring is why the pitch is 3 and not 2.** At pitch 2 a 2×2 coop is 4×4 cells and a ring
leaves a 2×2 floor, which is not a room. At pitch 3 it is 6×6 cells and the floor is 4×4 —
"a bit bigger", as asked, with the walls paid for.

---

## 5. ~~Distance between spaces~~ — superseded

*This section answered the differential-transform design, where a 3×3 hut with a 9×9 room
meant nine tiles indoors was three tiles outdoors and no single distance could be right in
both. Under the nested grid there is one metric and the question does not arise.*

**One finding in it survives and is now an ordinary bug**, because it is about the page
layout the game has today rather than about interiors: seven measurements in the current
build — `is_protected_by_scarecrow`, `entities/crow.gd`'s `_player_is_near`, the grazers'
`crop_sense`, `nearest`, `scent.deposit_blob`, the sprinkler radius and the shoo radius —
measure on raw grid coordinates with no idea the home page exists below the farm. They are
correct only by coincidence of layout: the home's floor begins six rows below the farm's
last row and the largest radius is four. `crow_brain._off_the_map` is the one that was
taught about pages, by hand, on 2026-09-06. Filed as work, and worth doing whatever happens
to interiors.

---

## 6. ~~Cycles and holonomy~~ — superseded

*This section proved that gluing flat spaces edge to edge makes a piecewise-flat surface
whose scale factors multiply around a cycle, so a creature could walk a loop of rooms and
come back a different size. It is true, and it is about a design the studio is not
building: the nested grid glues nothing, so there is no holonomy to accumulate. Kept
because the day two spaces really are stitched together — a portal to somewhere that is
not inside a building, a lift between floors that are not nested — it is the first thing
to re-read.*

The one rule from it that still earns its place, for a different reason: **transparency is
one level deep.** Not because a deeper picture could not be made to close — under the
nested grid it could — but because a room inside a room inside a room at quarter pitch is
four screen pixels wide and says nothing. A limit of legibility rather than of geometry.

---

## 7. Custom exits

A staircase, a lift, or any exit that is not a door in a wall.

Under the nested grid most of these stop being a question. A ladder to a loft is another
nested rectangle and a zoom; a door between two rooms of one building is walking. What is
genuinely still a portal is an exit to somewhere that is **not inside the building** — a
cellar that goes down rather than in, a lift between two buildings — and the codebase
already has the right primitive for it: a door today is a named pair of tiles
(`WorldLayout.door_at`), not an edge you walk off, so those cost a sprite and a sound.

Section 6's warning applies to exactly those and to nothing else: the moment two spaces are
linked that are not nested inside one another, the world stops being one flat grid and the
reasoning there comes back.

---

## 8. Implementation notes, Godot

Recorded so the estimate is honest. Nothing here has been built.

- **The sim's change is a coordinate change, not a structural one.** Positions move from
  tiles to cells at twice the resolution. No new space concept, no portal graph, no guards
  on measurement. The save format's grid grows; the replay format is untouched in shape.
- **The camera already knows about pages** — `main.gd` clamps `camera.limit_*` to the page
  she is on and refreshes it as she moves (`_refresh_camera_limits`, 2026-09-06). This
  becomes: the zoom is a function of which space she is standing in, and the limits come
  from that space.
- **The transition is a `Tween` on `camera.zoom` alone**, about 300–400 ms, eased. There is
  no second transform to keep in step with it, which is the largest single saving over the
  discarded design.
- **Interior art is drawn at half pitch**, so a bed inside a room is an 8×16 sprite where
  the farm's are 16×16. That is the real art cost of the feature and it is worth pricing
  before committing: either interiors get their own smaller art, or shipped art is used at
  half scale and looks it.

---

## 9. What is settled, what is not

**Settled by the directive and recorded as P-18:** the principle in §2; interiors nested in
their building's footprint at finer pitch; entering is a uniform zoom; the farm stays
visible throughout; the farmhouse is 3×2 outside and 6×3 inside.

**Proposed, awaiting the CEO's yes:** the leftover-band rule in §2 — room width is the
footprint's width times the pitch, room depth is free under it, and the strip that leaves is
the roofline. Recommended over matching the shapes.

**Settled by analysis:** one grid and one metric (§4); D-16 closed; transparency one level
deep, on grounds of legibility (§6); portals survive only for exits that are not nested (§7).

**Built 2026-09-15, the coop's inside:**

- The world gained a third page, the **rooms page**, dark until something has an inside
  (`WorldLayout.ROOMS_PAGE`, fifteen 6×6 slots).
- A coop put down opens a room in a slot and records its **anchor** and **pitch**
  (`SimWorld.open_room`); picking it back up closes the room and returns the slot to
  darkness. Both are ordinary consequences of `place` and `collect`.
- The room is a one-cell ring of `WALL` around a **4×4 floor**, with one cell of the south
  wall cut out as `GATE_OPEN` — the home's own vocabulary, so `is_walkable` refuses the walls
  and `Movement` walks the floor with nothing new to learn.
- A tap on any square of the hut is `use_door`; a tap on the doorway brings her out.
- `world_pos_of_cell` turns any interior cell into a true position on the farm, which is the
  whole of what the anchor and the pitch are for.
- Saves carry the room registry (v3 → v4; an old farm is padded with a dark page and keeps
  playing). The observation vector's vertical scale was **frozen** at the height it had, so
  growing the world cannot silently re-scale every weight a robot has learned.
- Going through the door zooms: the camera arrives at the other side's scale and tweens to
  this one, so walking in is one continuous zoom in and walking out is one zoom out
  (~~`main.gd`'s `_zoom_through_door`~~ — since 2026-09-16 a glide of position and zoom
  together from the picture she was looking at, §8a; `main.gd`'s `_step_door_glide`).

**Built the same day, the second pass:**

- **The farm is drawn through the walls.** `farm.gd`'s `_draw_room_backdrop` takes the two
  numbers on the room record and uses them as a transform: scale the farm by the pitch, put
  the anchor where the room's origin is, and the yard lands around the room in the place it
  really occupies. Registration by construction rather than by hand — whatever separates the
  hut from the shipping bin outdoors separates the room from the bin in here, multiplied by
  the pitch and not otherwise touched. ~~Ground and objects only~~ — since 2026-09-16 the
  whole live farm, rendered by a second view of the same canvas (§8a); her own building is
  skipped, because she is standing in it. The camera stops clamping to the page while she is
  inside and clamps to the room plus that ring of farm instead.
- **The hen lets herself in.** `use_door` stopped being the player's alone — it is a verb she
  already had, so nothing has a private one (S-3 read from the other side). On a wet day the
  hen walks to the coop's doorstep and through it; on a dry one she walks to the doorway and
  back out. A coop with no room under it still gets the front-row shelter P-17 shipped, so
  the fallback is a fallback rather than a failure.
- **A tap on the coop opens its panel** — *go inside* or *pick it up* — which is the machine
  panel's shape keyed on a tile rather than an actor, since a building cannot walk off while
  the panel is coming up. Both rows are ordinary Actions through the one gateway.

**And what a room holds is deliberately nothing, for now** (2026-09-16). A room's floor is
ordinary walkable ground, so before this a coop could be set down inside another coop — and
a sprinkler in the bedroom, since the home is a room too. Picking the host up then wiped the
inner thing's squares and left its room holding a slot: the coop was simply gone. Everything
about that needs rules nobody has written — what the inner thing is anchored to, where it
goes when its host is picked up, and where a hen sheltering in it is standing once the room
she was in has stopped existing. So `placeable_at` refuses the whole class, which is what
P-13's deliberately weak first version is for, and a farm that already got into that state
comes out of it: picking a hut up takes every hut nested inside it and pays the crate for
each. **What may go in a room is filed as a design question**, not answered by accident here.

## 8a. Going through a door is still a cut, and it should not be

*Reported in play 2026-09-16, handed to Tomas as `hq/data/work/w2b7e51c9d0af.json`.*

The CEO: *"the camera position can jump a bit… things in the outer world suddenly hop to a
new position and then zoom. This makes it feel like we've switched scenes and are doing a
fake zoom."*

**Two faults, and they are the same fault seen twice.**

**The camera jumps.** `use_door` moves her tens of tiles in world coordinates and the camera,
parented to her, snaps with her; only then does the zoom start. The fix is exact arithmetic
rather than a feel: the backdrop already maps farm space into room space as
`room_px = offset + farm_px × pitch`, so putting the camera at `offset + camera_farm_pos ×
pitch` with `zoom ÷ pitch` at the instant of the swap shows a pixel-identical view, and one
tween of position *and* zoom from there is continuous by construction.

**And the world outside stops being itself.** The backdrop is a hand-written second pass
drawing ground, boundaries and objects — so crops, effects and every actor pop out of
existence on the swap frame. Fixing the camera alone moves the seam rather than removing it.

**The correction worth keeping**, because it is the opposite of what it looks like: *the
world is already alive*. `SimWorld` never pauses at a door — brains tick, the hen wanders,
crows arrive, crops advance at the day turn. This is a drawing gap, not a simulation gap.

**The mechanism to try** is a `SubViewport` sharing the main viewport's `World2D` with its
own camera over the farm: the same canvas world, drawn by the code that already draws it,
with no parallel renderer to keep honest. Two things are unknown and are to be spiked before
anything is wired in — whether Godot does what that expects, and what it costs to draw the
world twice a frame on a tablet. **A frame-rate regression on the device is not an agreed
price**, and the fallback (re-implementing autotiled soil, growth stages, the watered chip,
the ripe glow and every actor draw in a second pass) is a design decision rather than an
implementation one.

**And the bar the CEO set on it:** *"can you verify that it works as described before showing
it to me again?"* By measurement, not by eye — a per-frame log of the camera path against a
fixed world landmark, and a consecutive-frame image diff, baselined against the current build
so the fault is measured before it is fixed.

### Measured, then built (2026-09-16)

**The harness came first.** `tools/measure_door_transition.tscn` walks her through both doors
the game has, both ways, and on every frame records the camera, where a fence corner at a
known farm tile landed on the screen, and the frame itself; `tools/measure_door_transition.py`
judges the four trips on three questions — did the landmark's screen path jump, did any frame's
picture change out of line with its neighbours, and did the first frame on the far side differ
from the last frame on the near side anywhere outside the threshold (the building, its roof, and
the square she stepped onto). The bar: no step ≥ 4 px that is 3× its neighbours; no frame diff
3× the frames around it; the swap frame within 1.5 levels of the one before, outside the threshold.

**The build as it stood failed all three, on every door.** The landmark jumped 118–234 px on the
swap frame; the swap frame differed from the one before by 37–45 levels across the whole picture;
and the home's door also slid the view for six frames after the swap, the page clamp and the
position smoothing pulling against each other.

**The camera.** `main.gd` no longer tweens the zoom from a view that has already jumped. On the
swap frame it puts the camera where the arithmetic above says the last frame's picture is —
`offset + eye × pitch` at `zoom ÷ pitch`, the inverse coming out — with smoothing off and the
limits stood aside, and holds it there for that one frame. From the next it glides position and
zoom together, on the cubic ease-out the zoom always had, to wherever the room's (or the page's)
limits would rest the camera, recomputed each frame from where she stands; a hitch advances it by
at most a thirtieth of a second, so a slow frame cannot make it leap. It lands by handing the
camera back — offset zero, limits on, smoothing on — on exactly the view those limits produce,
so the hand-over is not a move. Two things fell out of writing the limits as numbers: a page's
refresh now writes all four sides (a coop visit and the teaching glide each used to leave their
horizontal pair behind), and the farmhouse's zoom is read off its room record like any other.

**The yard.** The hand-written second pass is gone. The farm is drawn as two items — the farm
page by one, everything above it by the other, the same pass over two row ranges — and a
`SubViewport` sharing the world's canvas, with its own camera parked over the farm page at 1:1,
renders the farm-page item every frame she is indoors: soil, crops, the ripe glow, the hen, a
crow, the neighbour, the day tint, drawn by the code that already draws them. The main view culls
that item while she is inside (a visibility layer), so page 0 exists exactly once on the screen —
in the room's space, at the room's pitch — and never also at its own world position a few hundred
pixels above her room, which the low zoom of a door used to reach into. The texture is drawn on a
canvas layer of its own that follows the camera, because the sub-view renders the day tint and an
item in the world's canvas would be tinted a second time on the way to the screen (measured: the
yard came back 8% darker, most in green, on the first attempt). The dim — still Q-108's
placeholder — ramps with the glide instead of popping: none of it on the swap frame going in,
all of it going out until the walls have fallen away, and on the way out it leaves the building
and her doorstep as lit as the room was.

**The two unknowns, answered.** A `SubViewport` with `world_2d` shared and a `Camera2D` inside it
renders the farm in 4.7; `CanvasLayer` content — the HUD, the build stamp — does not reach it,
and a node on a culled visibility layer does not either. What it costs, measured by
`tools/profile_door_backdrop.tscn` (and `tools/profile_android.sh`, which builds a profile APK
under its own package name so the tablet's game and its saves are never touched):

| where | draw calls | GPU ms/frame | frames/s |
|---|---|---|---|
| desktop, outdoors | 165 | 1.73 | 59.9 |
| desktop, indoors | 178 | 2.26 | 59.9 |
| tablet (Mali-G57), outdoors | 164 | 9.6 | 35.3 |
| tablet (Mali-G57), indoors | 177 | 12.1 | 38.4 |

No frame-rate regression on the device; the extra pass is 0.8 ms of its GPU. (The tablet runs the
game at about 35 frames a second in the yard already, which this tool made visible and which is
its own question.)

**After.** All four trips pass the bar: the worst step in the landmark's path is 1.1–1.3× its
neighbour, no frame spikes, and the swap frame differs from the one before by 0.10–0.34 levels
outside the threshold — the one place the picture is allowed to change, because the hut becomes
the room there. Headless, Scenario AY in `tools/test_runner.gd` asserts the same arithmetic
through a tap: the glide starts from the mapped view, lands on the limits' own rest with no hop,
and comes back out the same way.

**What the swap still changes, on purpose:** the building itself. Outside it is a hut with a roof;
inside it is a room with walls; the frame she steps through trades one for the other on the
footprint. §3's picture — *"the room that was a smudge inside its walls"* — would need the hut
drawn open from outside, which is art and taste, not camera work, and sits with Q-108.

**Still a placeholder:** the treatment of the yard through the walls, a flat dim pending
**Q-108**.

**Open, and filed:**

- **Q-108** — the treatment of the yard seen through the walls at ×2: haze, desaturation,
  how hard the walls cut. A question about grain, now that it is no longer a question about
  geometry.
- **Q-109, ruled 2026-09-21** — each building may have its own whole-number room
  multiplier. The farmhouse keeps its provisional dimensions. Size the coop when its
  room becomes playable; a single multiplier need not fit both buildings.

**Not designed, and load-bearing.** Three of these would have to be guessed at to start
building, which is what makes this chapter a design and not a specification:

1. ~~How big is the farmer indoors?~~ **Ruled 2026-09-15: she keeps her screen size.** She
   is the same number of pixels tall in both, which means her world size divides by the
   pitch when she steps inside. The CEO accepted the visible consequence — *"they'll see her
   size appear to change when zooming into or out of a different area"*. In grid units she
   is unchanged, about two units tall wherever she stands; it is the unit that shrinks. This
   is the roomier of the two answers: a 4×4 coop floor is two farmers across, where keeping
   her world size would have made it one.
2. ~~Where is the wall?~~ **Designed, §4a: a one-cell boundary ring of the room's own grid**,
   reusing the `WALL` / `GATE_OPEN` / `FLOOR` vocabulary the home already uses, with the
   threshold a declared `door_at` pair.
3. ~~What the resolution change costs.~~ **Measured 2026-09-15, and it is why the design
   changed**: 538 unit-test assertions name explicit tile coordinates, plus 83 direct grid
   indexings and 37 verbs. §4 option A is off the table; the anchored sub-grid does not pay
   any of it.

**Not designed, and smaller:**

4. **The existing home.** Today it is page 1, a 10×7 room behind a door. Under the nested
   grid it becomes an interior of its own house — and 10 is not a multiple of the
   farmhouse's 3, so the room the game ships cannot survive the rule in §2 unchanged. P-16's
   window view lives in that room and moves with it.
5. **When the zoom triggers and how it behaves.** On the tap, on crossing the threshold, or
   on arriving? What does the camera do while she is standing *in* the doorway? §8 calls the
   transition a tween and does not say what starts it.
6. **Art at half pitch.** Every object inside a room needs art at half the farm's pitch, or
   the farm's art used at half scale and looking it — plus a roofline strip per building
   type for the band. Unpriced.

**Deliberately not answered here:** what is *in* a room. This chapter is about the shape of
the space; furnishing, chores, and what the coop's inside says about the hen live with P-17.

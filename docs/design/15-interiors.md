# 15 — Interiors: buildings you walk into without leaving the farm

*Status: directive received 2026-09-14, corrected 2026-09-15, nothing built. This chapter
is the analysis the directive asked for, not a specification. What it settles is recorded
as P-18; what it cannot settle is filed as Q-items and named here.*

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

**One grid, in the finest pitch any space uses.** That is the whole answer, and it is
simpler than any of the three models an earlier draft weighed.

- A tile of farm is 2×2 interior cells. Sim positions are in cells; the farm's own objects
  occupy cells in twos.
- A building's interior is a rectangle of cells **inside the building's footprint**. It is
  created when the building is placed and destroyed when it is picked up, and it needs no
  allocator, no page, and no region table, because it lives where the building lives.
- There is no portal. A door is a door in the ordinary sense — she walks through it — and
  the camera zoom is a presentation response to which space she is standing in.

Consequences worth stating, because they are all improvements on the discarded design:

- **Distance is well defined everywhere**, in cells. A crow four tiles from the house is
  eight cells from it, and eight cells from the farmer standing inside it. Nothing has to
  be undefined and no measurement needs a guard.
- **Nothing can be created or destroyed at runtime except cells**, so saves and replays keep
  the shape they have.
- **Pathfinding is one search on one grid.** Walking in through the door is walking.
- **The cost is resolution.** Every sim coordinate doubles, so the grid is 4× the cells for
  the same farm — 64×40 rather than 32×20 for page 0. That is arithmetic on a small number
  and it is the price of the whole feature.

### D-16 is closed by this

The deferred question of when to move from one grid to a grid per space does not arise:
there is one grid and there are no spaces to give coordinates to. Recorded as closed
2026-09-15 rather than deleted, so the reasoning is findable.

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

**Settled by analysis:** one grid and one metric (§4); D-16 closed; transparency one level
deep, on grounds of legibility (§6); portals survive only for exits that are not nested (§7).

**Open, and filed:**

- **Q-108** — the treatment of the yard seen through the walls at ×2: haze, desaturation,
  how hard the walls cut. A question about grain, now that it is no longer a question about
  geometry.
- **Q-109** — whether the farmhouse's ratio holds for the coop and everything after it.

**Deliberately not answered here:** what is *in* a room. This chapter is about the shape of
the space; furnishing, chores, and what the coop's inside says about the hen live with P-17.

# 17 — Industrial Barn and Cheese Line

*Status: visual direction selected. This is a phase-2 livestock building; its economy,
acquisition, art, and implementation remain unplanned.*

## The building at a glance

The **Industrial Barn** is a 3-wide by 2-tall building on the farm. Its large front livestock doors stay open: cows can walk in and out whenever they choose. Entering opens a 6-wide by 4-tall interior. The larger inside is part of the same farm view, following the interior rule in [15 — Interiors](15-interiors.md): it is not a separate scene.

Four voluntary milk stalls sit along one long wall. The opposite side holds a small cheese factory. Steel pipes carry milk from each occupied stall to the first factory station. The player can see the whole journey from milk to finished cheese without needing to read a label.

The barn is a place cows choose to use, not a place that confines them. Each cow may remain outside, walk through the large doors, visit an empty stall when ready to give milk, and leave again. No picture, animation, or game rule shows a cow being forced, distressed, restrained, or treated as a machine.

## The cow milk cycle

Each cow has a hidden milk amount measured in units.

- At each new day, the amount rises by a random 0.4 to 1.0 units (Daniel confirmed this reading on 2026-10-07: 20% to 50% of the cow's 2-unit capacity, not of one unit). The future simulation uses [SimRng](../ARCHITECTURE.md) for this draw so a saved replay gives the same result.
- A cow stores no more than 2 units.
- A cow is ready to give milk at 1 unit or more. When she freely enters an empty stall, she gives exactly 1 unit, leaving any amount above 1 unit in her body.
- The stall sends that unit into the steel pipe immediately. The cow then remains free to leave through the front doors.
- Four empty stalls allow four cows to give milk at the same time. A fifth cow waits outside or returns later; she is never pushed out of a stall or made to queue in a way that reads as distress.

The amount remains invisible. The player learns readiness from the cow's choice: a cow walking calmly into an open stall starts the line. This keeps the core interaction understandable without reading and avoids turning an animal's body into a meter the player must manage.

The future implementation records each daily gain, voluntary stall visit, milk transfer, and factory state change as ordinary actions through [the simulation's one action gateway](../ARCHITECTURE.md). A barn action must name the cow, stall, and amount transferred. The factory's visual motion may be continuous, but its completed world changes stay deterministic and replayable.

## The cheese line

One milk unit starts one batch. The line runs automatically after a cow gives milk. Each station makes a distinct, watchable change, so a pre-reader can follow the product by its colour and shape rather than by a recipe.

The four stall pipes meet at one shared receiver. If several cows give milk together, each visible unit arrives in a fixed order and waits there until the vat is ready. Only one batch occupies a station at a time; a batch moves forward as soon as the next station is clear. This preserves the pleasure of four simultaneous stall visits without making the player read or manage a factory queue.

| Order | Station | What the player sees | Connection to the next station |
|---|---|---|---|
| 1 | Milk receiver | A steel pipe reaches a lidded steel vessel; a small red display may blink as milk arrives. | Fixed steel pipe |
| 2 | Set vat | A round or long stainless-steel vat warms the milk. Its open top shows a warm copper-orange interior against the steel shell. | Fixed steel pipe |
| 3 | Curd cutter | An overhead carriage moves a wire harp through the set milk, making clear pale-yellow curds. | Overhead rail within the vat |
| 4 | Stirring rake | A second carriage slowly stirs the curds. The player can see a rake travel the vat rather than a hidden process finish. | Overhead rail within the vat |
| 5 | Whey drain and curd table | Whey leaves through a low pipe while curd lands in slabs on a steel table. A fixed turning arm divides or mills the slabs. | Short trough or enclosed belt |
| 6 | Hoops and presses | Curds fill white forming hoops. Cylindrical presses lower and rise; coiled yellow air hoses make the motion easy to spot. | Mesh conveyor belt |
| 7 | Outfeed conveyor | Yellow wheels or blocks travel on a long, winding belt toward the exit. | Conveyor belt to the collection point |

The early version uses fixed machinery throughout. It does not need a robot that chooses tasks, because the player has not yet earned that level of autonomy elsewhere. A later upgrade can replace one fixed station with a directed robot only when it creates a new player decision rather than making the first barn more capable than its role needs.

## Selected visual direction: red dairy works

**Outside.** A familiar red-painted timber barn has a pale metal roof, broad dark door openings, and short steel vent stacks. The front still reads as a barn before the player enters.

**Cow section.** The cow side is a warm, dry livestock space with red brick and terracotta
tile, timber-faced open stalls, straw-coloured flooring, and visible hay and other cow
supplies. It occupies the side nearest the large doors, so a cow can enter, choose an empty
stall, turn, and leave at any time. A low, clean steel milk connection sits at each stall's
edge; it reads as building equipment, never something attached to the cow.

**Industrial section.** A separate, clean processing space contains the stainless-steel
receiver, vats, cutters, rakes, drains, presses, and conveyor. White tile walls, steel
pipes, and clear floor space distinguish it from the cow section. Copper-orange vat
interiors and finished yellow cheese remain the warm moving focal points.

**Boundary and readability.** A wide, open division separates the two sections without
blocking the player’s view of the milk path. The fixed steel pipes visibly cross from the
cow stalls into the processing equipment. The player can see cows cared for on one side and
milk becoming cheese on the other without needing a label.

The selected direction is **A, red dairy works**, ruled by Daniel on 2026-10-07. No art is
attached to this design. The supplied photographs are third-party mood reference only and
must not be added to the repository or shipped. An art director will prepare a game-owned
visual brief before original pixel art is made.

## What remains for later design

- The barn's acquisition, price, and progression gate are not proposed here. They are player-facing economy and pacing decisions Daniel has not made.
- The number of cows that can be owned, cheese values, batch duration, storage, and collection interaction are not proposed here. They need the phase-2 livestock economy to be designed as one loop.
- The exact action vocabulary and the factory's saved state need an engineering design before implementation, using the action gateway and replay tests described above.

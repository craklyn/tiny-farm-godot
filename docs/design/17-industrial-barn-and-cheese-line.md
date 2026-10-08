# 17 — Industrial Barn and Cheese Line

*Status: proposal. Blocking: Daniel's choice of visual direction. This is a phase-2 livestock building; implementation starts only after that choice.*

## The building at a glance

The **Industrial Barn** is a 3-wide by 2-tall building on the farm. Its large front livestock doors stay open: cows can walk in and out whenever they choose. Entering opens a 6-wide by 4-tall interior. The larger inside is part of the same farm view, following the interior rule in [15 — Interiors](15-interiors.md): it is not a separate scene.

Four voluntary milk stalls sit along one long wall. The opposite side holds a small cheese factory. Steel pipes carry milk from each occupied stall to the first factory station. The player can see the whole journey from milk to finished cheese without needing to read a label.

The barn is a place cows choose to use, not a place that confines them. Each cow may remain outside, walk through the large doors, visit an empty stall when ready to give milk, and leave again. No picture, animation, or game rule shows a cow being forced, distressed, restrained, or treated as a machine.

## The cow milk cycle

Each cow has a hidden milk amount measured in units.

- At each new day, the amount rises by a deterministic random 20% to 50% of the cow's 2-unit capacity: 0.4 to 1.0 units. The future simulation uses [SimRng](../ARCHITECTURE.md) for this draw so a saved replay gives the same result.
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

## Three visual directions

All directions keep the same happy, voluntary cow behaviour and the same seven stations. They differ only in how the building makes the player feel while looking at it.

### A. Red dairy works

**Outside.** A familiar red-painted timber barn has a pale metal roof, broad dark door openings, and short steel vent stacks. The front still reads as a barn before the player enters.

**Inside.** Red brick and terracotta tile warm the floor under white tile walls. Stainless-steel pipe runs cross the ceiling and down the stall wall. Copper-orange vat interiors supply the line's warm focal points.

**Animal handling.** Each stall is timber-faced with a clean steel milk connection low on the side. A cow steps onto dry straw-coloured floor and can turn back toward the open doors at any time.

**Machinery.** The steel line is sturdy and workshop-like: exposed valves, milk churns beside the receiver, long vats, and a direct outfeed belt.

### B. Blue-and-cream creamery

**Outside.** A pale cream masonry building with a blue tile band and tall clerestory windows reads as a small local dairy. The livestock doors are framed in blue steel.

**Inside.** Blue-and-cream wall tile meets wet ochre floor tile. The room is bright, orderly, and reflective; stainless machines and red digital readouts give it a clean factory rhythm.

**Animal handling.** White-tiled stall fronts and rounded steel rails make each open stall look like a calm wash bay rather than a pen. The route from doors to stalls stays wide and unobstructed.

**Machinery.** Enclosed pipes and tidy panel boxes make the process read as a compact modern plant. Yellow cheese wheels provide the strongest moving colour.

### C. Pine visitor gallery — recommended

**Outside.** A warm knotty-pine public front sits under a simple barn roof. Large livestock doors remain at ground level, while broad upper windows reveal bright steel within. From the farm, it reads as both a welcoming barn and something special worth entering.

**Inside.** The player stands in a narrow pine-floored visitor gallery along the front wall, looking through large safety-glass windows into the bright steel cheese room. Terracotta and red-brick tile under the machines keeps the plant warm rather than clinical. The cow stalls remain visible beside the gallery, with the open doors beyond them.

**Animal handling.** Four open, timber-trimmed stalls face the easy path from the doors. Steel pipes connect at the stall edge, where they read as equipment in the building rather than something attached to a cow. The cows are always shown with space to enter, turn, and leave.

**Machinery.** The gallery frames the whole line as a show: overhead harps and rakes cross the copper-lit vat, then yellow cheese wheels or blocks travel on a long winding conveyor behind the glass. The player sees warm wood on their side and stainless steel on the factory side.

## Recommendation and open decision

Choose **C, the pine visitor gallery**. It gives the player a clear, warm place to stand while watching the automated reward happen, and its wood-versus-steel contrast makes the barn feel like a Tiny Farm building rather than an opaque industrial box. Direction A is the reasonable alternative if Daniel wants the barn to read first as a traditional farm building from the yard.

No art is requested with this proposal. The supplied photographs are third-party mood reference only and must not be added to the repository or shipped. Once Daniel chooses a direction, the art director can make a game-owned visual brief and the pixel artist can make the required original assets.

## What remains for later design

- The barn's acquisition, price, and progression gate are not proposed here. They are player-facing economy and pacing decisions Daniel has not made.
- The number of cows that can be owned, cheese values, batch duration, storage, and collection interaction are not proposed here. They need the phase-2 livestock economy to be designed as one loop.
- The exact action vocabulary and the factory's saved state need an engineering design before implementation, using the action gateway and replay tests described above.

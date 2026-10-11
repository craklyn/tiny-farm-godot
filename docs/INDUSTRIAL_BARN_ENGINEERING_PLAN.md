# Industrial Barn Engineering Plan

*Written 2026-10-08 from the approved design in [17 — Industrial Barn and Cheese
Line](design/17-industrial-barn-and-cheese-line.md). This plan defines the simulation,
save, replay, building, test, and tablet work. The approved first barn costs 500 gold and
includes the first cow. Each barn holds up to four cows. Finished-cheese capacity remains a
named parameter until Milo Fern's livestock-economy decision settles it.*

## Purpose and boundaries

The Industrial Barn is a placeable three-tile by two-tile building with one six-cell by
four-cell room. Up to four cows may use its open stalls at once. A cow gains milk each
morning, chooses whether to walk into the barn, gives one unit when ready, and remains free
to leave. Fixed machinery moves that unit through seven visible cheese-making stations.

This plan adds no private ability for a cow or machine. Movement uses the same ground route
search as other registered actors, door crossing uses `use_door`, and every state change is
an Action accepted by `SimWorld.apply_action`. Presentation reads simulation state and
animates it; an animation never completes a batch or changes a cow.

The first build uses fixed machinery, not a humanoid robot. It contains no failure state,
forced stall visit, restraint, sickness, breeding, feed management, or player-visible milk
meter. The line waits when blocked and resumes when its next station is free. Nothing is
lost and no cow is penalized.

This build ends when the barn holds a finished-cheese count. It does not add cheese
collection, player inventory transfer, storage outside the barn, shipping, or sale. The settled
collection-and-sale design extends the gateway in the follow-up implementation: cheese waits on
the barn shelf, and one player action sells every stored batch for 20 gold.

## Decisions and named parameters

The implementation must collect unresolved economy values in one data row rather than
spreading placeholders through the simulation:

| Parameter | Meaning | Owner before release |
| --- | --- | --- |
| `BARN_PRICE` | Price of one Industrial Barn, including the first cow | Settled: 500 gold |
| `HERD_LIMIT` | Cows allowed for each placed barn | Settled: 4 cows per barn |
| `FINISHED_CHEESE_CAPACITY` | Maximum finished units held inside one barn | Milo Fern's livestock-economy decision |
| `STATION_DURATION_TICKS` | Visible duration of each cheese-making step | Settled: every station shows its work for 5 seconds |

The shop and acquisition flow expose the settled 500-gold barn-plus-first-cow bundle and the
four-cow ownership limit. The later collection design must add a `CHEESE_BATCH_VALUE` data value
of 20 gold with the action that pays it. Code and tests may inject explicit values for the
remaining unresolved parameters. Their settled values belong in the same data definitions that
existing shops use. Station durations live in one ordered table and tests replace them with short
values; production timing is not an engineering guess because the player watches it to understand
the process.

The following values are already settled and are not tuning parameters:

- a cow stores 2.0 milk units;
- a cow becomes ready at 1.0 unit and gives exactly 1.0 unit;
- each cow gains 0.4–1.0 units at the start of a day;
- one milk unit becomes one cheese batch;
- one barn has four stalls;
- one station holds one batch, while the receiver may queue waiting batches in arrival
  order;
- a full finished-cheese count blocks the outfeed without discarding or transferring a
  batch.

## Simulation model

`SimWorld` gains a `barns` dictionary keyed by the room identifier. Each value is
JSON-plain and contains the building anchor, four stall records, a receiver queue, seven
station slots, the next batch number, and a capped `finished_cheese_count`. A stall
record contains only its index and occupying cow identifier. A batch record contains its
stable identifier, source cow, amount in thousandths of a unit, and current station.

The actor registry remains the source of truth for cows. The barn record owns equipment and
batch state because fixed machinery is building state, not an actor. The simulation clock
holds a `barn_line` event for each next station completion. Dispatch derives the next line
Action from the barn record and sends it through `SimWorld.apply_action`; it does not
register a controller, run a brain, or carry energy. Picking up the building is refused
while a cow occupies a stall, a batch is in the line, or its finished-cheese count is
nonzero. This prevents a room removal from deleting living actors or product. The existing
rule that empties room fittings applies after those checks and cancels the barn's pending
clock event.

### Cow actor

Add `cow` to `systems/species_defs.gd` as a persistent ground actor with the `cow_barn`
brain. Each cow has the standard registry fields `species`, `pos`, `facing`, `energy`, and
`extra`. Its JSON-plain `extra` contains:

- `milk_milliunits`, an integer from 0 through 2,000;
- `barn_id` and `stall_index`, empty and `-1` while not in a stall;
- the ordinary movement path, step, wake, and job fields used by `Movement`;
- a short state from `outside`, `to_door`, `to_stall`, `giving`, `leaving_stall`, and
  `leaving_barn`.

The cow has its own daily energy meter in the registry. `COW_MAX_ENERGY` and movement costs
live in the species row beside its speed. Add a `SpeciesDefs.max_energy_of()` lookup and
change `SimWorld.advance_day` to restore each registered non-player actor from that lookup.
Existing species rows receive the current `ACTOR_MAX_ENERGY`, preserving their behavior;
the cow row receives `COW_MAX_ENERGY`. The accepted `sleep` Action reaches this pass before
day Actions run and before the cow chooses work. The cow brain does not restore its own
energy. Each tile step spends the normal actor movement cost and giving milk spends a named
`COW_GIVE_MILK_ENERGY` cost. An exhausted cow rests where she is until the next day; the
line never moves her, replenishes her energy, or borrows the player's energy.

The cow's allowed verbs are `gain_milk`, `use_door`, `enter_milk_stall`, `give_milk`,
and `leave_milk_stall`. The player does not need to emit the animal-choice verbs in the
first interface, but the gateway validates them as ordinary world operations rather than
granting the brain a mutation path. A future player command must call these same verbs.

### Daily milk gain

`CowBrain.day_actions()` returns one `gain_milk` Action for every cow, sorted by actor
identifier through the existing `Brains.day_actions()` ordering. The brain draws an integer
from 400 through 1,000 with `SimRng`, keyed by world seed, day, cow identifier, and the
`cow_milk_gain` channel. The Action carries that exact integer as `amount_milliunits`.
`SimWorld.apply_action` clamps the stored total to 2,000.

Using integer thousandths makes 0.4–1.0 units exact in saves and JSON. `gain_milk` is an
ordinary gateway Action, but it is not a separate replay entry: `Brains.day_actions()` runs
inside the accepted `sleep` Action. A live sleep and a replayed sleep derive the same amount
from the saved world seed, new day, cow identifier, and channel, then apply it once. Loading
and replaying cannot draw from mutable random state or apply a second gain.

### Movement and stalls

The cow brain considers barns only when the cow holds at least 1,000 milk milliunits and has
energy to reach an available stall. It sorts candidate barns by route length and room
identifier, then sorts stalls by index. These tie-breaks make the choice independent of
dictionary insertion order.

The cow uses the simulation-side `Movement` path search for outdoor travel, the declared
door pair for `use_door`, and the same search inside the room. This is the pure simulation
equivalent of the shared Pathfinding behavior; the Node-based `Pathfinding` autoload remains
presentation-only and must not be called from `systems/sim/`. The brain plans only when it
chooses a destination or a route becomes blocked. It never searches once per frame.

`enter_milk_stall` atomically reserves an empty stall for the cow after she reaches its
approach cell. It refuses an occupied stall, a cow below the milk threshold, the wrong room,
or a cow already assigned elsewhere. After `give_milk` succeeds, the brain emits
`leave_milk_stall`, walks to the open livestock door, and may continue wandering outside.
An occupied cow may always leave; factory congestion never locks a stall or door.

Outside, an idle cow grazes (2026-10-10): each decision draws up to eight squares within
`CowBrain.PASTURE_RADIUS` of the nearest barn's doorstep with `SimRng.stateless` (her id and
the tick, so no other actor's draws move), keeps the first that is open farm ground with no
object or crop, clear of every room's doorstep and its neighbours, and not where another cow
stands or is heading, and plans to it — at most two route searches per decision. She rests
`GRAZE_SECONDS` there before the next decision. Her walks are brain decisions with no Action;
a replay recomputes them, as it does every brain but the hen's.

### Milk and cheese actions

Every accepted Action names `actor`, `verb`, and `barn_id`. Stall Actions also name
`stall_index`; batch Actions name `batch_id`. Values stay flat at the Action's top level so
the existing replay encoder and action signatures compare them directly.

| Verb | Actor | Deterministic world change |
| --- | --- | --- |
| `gain_milk` | Cow | Adds the recorded `amount_milliunits`, capped at 2,000. |
| `enter_milk_stall` | Cow | Reserves one empty stall for that cow. |
| `give_milk` | Cow | Subtracts 1,000, creates the next batch identifier, and appends it to the receiver queue. |
| `leave_milk_stall` | Cow | Clears the matching stall reservation. |
| `set_curd` | Barn building | Moves the oldest receiver batch into the empty set vat. |
| `cut_curd` | Barn building | Moves the named batch from the set vat into the cutter state. |
| `stir_curd` | Barn building | Moves the named batch from the cutter into the rake state. |
| `drain_whey` | Barn building | Moves the named batch from the rake to the drain table. |
| `fill_cheese_hoops` | Barn building | Moves the named batch from the drain table to the press bank. |
| `press_cheese` | Barn building | Moves the named batch from the press bank to the outfeed conveyor. |
| `finish_cheese` | Barn building | Removes the named batch from outfeed and increments the barn's finished count when it is below capacity. |

`give_milk` is the visible milk-receiver station: the subtraction and receiver insertion are
one atomic transfer, so a crash or rejected Action cannot duplicate milk. Every later verb
checks that the named batch occupies the required previous station and that the destination
is free. `finish_cheese` also refuses when `finished_cheese_count` equals
`FINISHED_CHEESE_CAPACITY`; the batch remains visible on the outfeed and upstream stations
wait. Refusals change nothing. Factory Actions use the stable source identifier
`barn:<room_id>` for replay signatures, but that identifier is not present in the actor
registry and has no energy field.

The follow-up collection implementation adds `collect_cheese` at the action gateway. The
settled design defines the shelf destination, 20-gold batch value, validation, and replay
contract. This production build does not yet accept the verb or decrement
`finished_cheese_count`. Each production row is 50 simulation ticks, which is five seconds at
the simulation clock's rate of 10 ticks per second.

### Cheese line state

The barn-line dispatcher schedules one clock event only when a batch arrives or a station
completion becomes due. The event derives the next station Action; only the gateway advances
state. Each batch stores `ready_tick`, computed from
`STATION_DURATION_TICKS` when it enters a station. Tests inject short durations, while the
production table uses the approved wordless animation timing.

When several moves are ready on one tick, the line checks stations from outfeed back toward
the receiver. This lets downstream work clear space before upstream work moves. Within the
receiver, batches remain ordered by their monotonically increasing identifier. The chosen
Action and tick are recorded as clock-generated replay entries and recomputed when replay
advances the same simulation clock.

Presentation derives all activity from the saved station slots and their entry and ready
ticks. It may interpolate milk, tools, presses, and belts, but it cannot call a completion
verb because an animation ended. As built, `world/barn_presentation.gd` computes every moving
part, including a walking cow's position and frame, from the saved records and the simulation
clock's tick. It never reads the wall clock, so the same saved tick draws the same barn after
any amount of real time or a reload.

## Building and interior

Add an Industrial Barn catalogue row with a three-by-two outdoor footprint and a room row
whose declared usable grid is six by four, following [15 — Interiors](design/15-interiors.md).
The room remains anchored to the building and rendered in the same world. Its exterior
doors and interior threshold form one declared door pair; cows and the player cross it with
`use_door`.

The room layout data names four stall approach cells, the seven factory station positions,
the finished-product outfeed, and an unobstructed route from the livestock doors through every
stall turn area. Placement uses the existing general building path: it validates every cell
of the three-by-two footprint, creates the anchored room with the building, and removes both
together only after the barn-state checks above pass.

As built (2026-10-08), the room's layout follows the redrawn interior picture
(`industrial_barn_interior_kit.png`). All 24 cells are inside the walls, as in the Spiral
Tower. The livestock doorway is the south-west cell (0, 3), and the outdoor doorstep is under
the barn's middle doors. The hay rack and feed bin occupy the left supply cells (0, 0) and
(1, 0). The four stalls form the central two-by-two block at (2, 0), (3, 0), (2, 1), and
(3, 1), numbered deepest first. The open route runs from the doorway through the left and
central floor cells to every stall, so a near stall never shuts in a cow at the back. The
processing cells (4, 0), (5, 0), (4, 1), (5, 1), (4, 2), (5, 2), (4, 3), and (5, 3) are
fixed machinery for the visible cheese route and cannot be walked through. Picking the barn up
is refused while a cow holds a stall or any milk or cheese is inside. Otherwise the barn
record, its pending line event and the room come up together.

The building and room must support the approved red dairy works art without encoding visual
details in simulation. Open doors, stall occupancy, station state, product shape, and
finished-cheese count are presentation views of saved state. There is no per-tile scan to decide
which frame to draw.

## Action gateway and replay

All verbs in this plan enter through `SimWorld.apply_action`. Cow brains and barn clock
events return Actions; they never edit actor extras, barn dictionaries, rooms, or tiles. The
presentation calls `farm.apply_action` only for player requests such as placing the barn.

Morning energy restoration remains part of the existing `sleep` verb instead of adding a
second reset verb that a cow could choose during the day. `SimWorld.apply_action` accepts
`sleep`, advances the day, restores each registered non-player actor to its species maximum,
and applies the sorted Actions from `Brains.day_actions()`. That list includes the cow's
`gain_milk` Action. Replay therefore reaches both morning changes by reapplying the one
recorded `sleep` Action: the sleep handler restores energy, recomputes the same seeded milk
gain, and sends that nested Action through `apply_action`. The replay log does not record or
compare `gain_milk` as a separate brain entry.

Replay format 3 already records ticks, clock-driven autonomous Actions, and flat parameters,
so this work does not change its schema or version. Add every new field to replay encoding
and signature tests as necessary, without omitting `barn_id`, `stall_index`, or `batch_id`
from recorded Actions. Validate `amount_milliunits` on the nested morning Action even though
that Action has no separate replay entry. Replaying advances the clock, recomputes
clock-driven cow decisions and barn-line Actions, and compares those Actions before comparing the
canonical final state. The morning milk gain is instead covered by the replayed `sleep` and
final-state comparison.

The robot-session replay must include at least one morning milk gain, door crossing, stall
visit, milk transfer, and full cheese batch. A mismatch in final milk, batch order, station,
tick, cow, stall, or finished-cheese count is a replay divergence, not a tolerated
presentation difference.

## Save format and migration

Bump `SaveGame.VERSION` from 6 to 7. Version 7 adds `world.barns` and makes the cow and line
state explicit members of the saved simulation. Capture and canonical capture sort barn
identifiers, stall indexes, queue order, batch identifiers, and station keys before
serialization so insertion order cannot change a comparison.

The version-6-to-7 migration deep-copies the save, writes an empty `world.barns` dictionary,
and sets version 7. Version 6 cannot contain an Industrial Barn or cow, so the empty value is
the only honest migration. Version 7 restore validates:

- every barn points to an existing Industrial Barn room and matching outdoor anchor;
- every pending `barn_line` clock event points to an existing barn, and each active barn has
  no more than one pending line event;
- there are exactly four uniquely indexed stalls and no cow occupies two stalls;
- every occupying cow exists, names the same barn and stall, and has milk within 0–2,000;
- batch identifiers are unique across the receiver and station slots, and the finished count
  is between zero and `FINISHED_CHEESE_CAPACITY`;
- each batch amount is 1,000 and each `ready_tick` is at or after its station-entry tick;
- no unknown station or non-JSON value is accepted.

A malformed barn block refuses the save rather than discarding animals or product. A valid
version-7 save restored mid-route or mid-batch schedules cow brains and barn-line events
from the saved clock and resumes from the saved job and ready ticks. The save migration does
not bump the replay format.

## Performance

No barn code scans the farm, room, cows, stalls, or stations per rendered frame. Brains wake
on scheduled simulation ticks. A cow runs route search only when selecting a barn, entering
a room, choosing a stall, leaving, or recovering from a blocked route. The line examines its
seven fixed station slots only on arrival or a scheduled completion.

Rendering iterates the four stalls and seven station slots for a visible barn. Farms with no
barn pay no barn update cost. Multiple barns scale with active cows and active batches, not
with map area. The simulation fast-forward benchmark records the cost of the ruled herd
limit before the work lands; a regression must be explained rather than hidden by widening
the benchmark threshold.

## Test plan

### Simulation tests

Add named tests to `tests/test_runner.gd` and call them from `_init`:

- the cow species row binds to a real pure brain, has ground movement, its own energy, and
  exactly the intended verbs, including `gain_milk`;
- an accepted `sleep` Action restores a tired cow to `COW_MAX_ENERGY` before the cow's
  `gain_milk` day Action runs; calling the cow brain's new-day hook alone changes neither
  energy nor milk;
- the species energy lookup returns the current `ACTOR_MAX_ENERGY` for every existing
  species, and sleeping restores those actors exactly as before while restoring a cow to
  `COW_MAX_ENERGY`;
- fixed seeds and days produce inclusive 400–1,000 gains, cap at 2,000, sort by cow id, and
  repeat byte-for-byte across two identical runs;
- a cow below 1,000 does not seek a stall; a ready cow chooses the shortest reachable barn,
  then the lowest stable tie-break, and uses the declared door route;
- four cows reserve four distinct stalls; a fifth waits without losing milk or energy to a
  refused reservation; every cow can leave while the receiver is blocked;
- `give_milk` is atomic, subtracts exactly 1,000, and creates exactly one ordered batch;
- each station verb accepts only the required source and open destination, refuses stale or
  duplicate batch identifiers, and a full line drains downstream first;
- `finish_cheese` increments the saved count only below capacity; at capacity it leaves the
  batch on the outfeed and schedules no futile per-tick work;
- the factory has no actor-registry entry, brain, or energy field, and sleeping changes only
  cow energy among the new barn state;
- cow brains and the barn-line dispatcher contain no mutation outside `apply_action`, and
  the gateway checker remains clean;
- capture and restore at each cow state and each of the seven station states are canonical
  equals, including energy, paths, queue order, and ticks;
- version 6 migrates to an empty version-7 barn block; corrupt cross-references refuse load;
- a two-day replay with at least two cows records only the outer sleep for each morning and
  reproduces the recomputed milk totals, stall order, clock-driven Actions, line timing,
  species-specific energy restoration, finished-cheese count, and canonical state with no
  divergence;
- the existing save fixtures, legacy replay fixtures, actor registry tests, interior tests,
  and robot tests remain unchanged and green.

### Integration tests

Add scenarios to `tools/test_runner.gd` and call them from `_run_scenarios`:

- place the three-by-two barn only on a valid footprint, enter its six-by-four room, and
  return through the same door without moving the outdoor building;
- watch a ready cow walk from outdoors through the livestock doors into an empty stall,
  give milk, turn, and leave; the hidden amount never appears as text or a meter;
- stage four ready cows and confirm all four stalls read independently while a fifth cow
  remains free outside;
- follow one unit through every distinct machine state into the capped finished count;
  pausing or changing frame rate cannot advance the line early, and a full count leaves the
  visible outfeed batch in place;
- save and reload while a cow crosses the door, while four stalls are occupied, and at each
  line station; each resumes without a jump, duplicate, or loss;
- run the complete session replay and require `MATCH`, then run the normal robot session so
  existing player and robot behavior remains reproducible;
- run the unit test suite, integration test suite, robot session, gateway check, writing
  check, and simulation benchmark on the same candidate tree.

## Delivery stories

Each story is at most two engineering days. The owner is the studio seat responsible for
the work, not the person who wrote this plan.

| Story | Estimate | Owner seat | Result |
| --- | ---: | --- | --- |
| Add the barn state and save migration | 2 days | Tomás Herrera | Save format 7 captures, validates, migrates, restores, and canonically compares empty and active barns. |
| Add cow milk and energy rules | 1.5 days | Tomás Herrera | The registered cow gains deterministic milk through Actions and carries its own daily energy. |
| Make cows choose open stalls and leave freely | 2 days | Tomás Herrera | The cow brain paths through barn doors, reserves one of four stalls, gives milk, and exits without confinement. |
| Run milk through the cheese line | 2 days | Tomás Herrera | Scheduled gateway Actions move ordered batches through all seven stations into a capped, saved finished-cheese count. |
| Add the placeable barn and six-by-four room | 2 days | Jade Okafor | The three-by-two building places, opens its anchored interior, and renders saved stall and line state. |
| Draw the barn, cows, and working cheese line | 2 days | Yuki Tanaka | Approved palette-locked production sprites cover the exterior, happy cows, stalls, seven stations, and product states. |
| Add the cheese shelf sale action | 1 day | Tomás Herrera | `collect_cheese` validates the farmer at a nonempty shelf, atomically removes every stored batch, pays 20 gold for each, and reproduces in saves and replays. |
| Draw the cheese shelf and sale feedback | 0.5 day | Yuki Tanaka | Original art shows an empty shelf, growing cheese stack, pulsing coin disc, handcart, and coin flight without required text. |
| Add wordless barn controls | 1 day | Sam Kowalski | Touch targets place, enter, and inspect the barn without required reading or exposing the milk amount. |
| Connect barn animation to simulation state | 2 days | Jade Okafor | Door, cow, pipe, vat, tool, press, and belt motion follows saved ticks without mutating the simulation. |
| Add the cheese shelf touch and sale feedback | 1 day | Jade Okafor | A tap walks the farmer to the shelf and shows the shelf, handcart, and coin feedback only after the accepted sale Action. |
| Settle the remaining barn build value | 1 day | Milo Fern | A decision card gives Daniel a concrete recommendation for finished-cheese capacity. |
| Apply the remaining barn build value | 0.5 day | Tomás Herrera | The ruled finished-cheese capacity replaces the remaining named parameter used by this build. |
| Settle the cheese station timings | 1 day | Sam Kowalski | A wordless timing proposal shows each station long enough to read, and Daniel approves the production durations. |
| Test saves, replays, touch flow, and performance | 2 days | Grace Ademola | Both test suites, the gateway check, benchmark, migration cases, and full cheese replay pass on one candidate tree. |
| Prepare the Android barn build | 1 day | Ravi Nair | Main contains the finished barn, both test suites and the robot session pass, and the clean Android debug build is ready for the approved tablet. |
| Deploy the finished barn to the tablet | 0.5 day | Ravi Nair | Following [the deploy runbook](DEPLOY.md), rescue and verify the existing tablet session, install the clean main build, launch it, and preserve the session receipt. |

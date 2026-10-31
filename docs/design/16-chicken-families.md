# Chicken families — design for Daniel's review

Status: Daniel authorized implementation on 2026-10-30 and requested tablet deployment. The review build was installed on his tablet on 2026-10-31 at 1:29pm Pacific. After playing it he requested the separate in-coop store described below. That store update is awaiting verification and a tablet refresh. No public release is authorized.

## The experience

The farm's chicken can become a mother. The player deliberately makes this possible by placing an egg in a coop nest and supplying feed. The mother does the sitting, then demonstrates foraging and raises her chick without further help. Chickens remain healthy when ignored. The dispenser gathers birds near home. Named birds acquire lasting familiarity through direct attention and sometimes wander toward the player. Surplus chickens leave in a neighbor's arms for another farm.

## Daniel's approved rules

### Eggs, nests, incubation

- Preserve the existing morning egg-laying chance and normal egg price. Eggs stay where laid; the hen does not seek a nest to lay. Gathering near a dispenser naturally concentrates some eggs near home.
- Collected inventory eggs can be selected and placed in an empty nest inside a coop. One nest holds one egg. Either available hen may adopt it; provenance is unnecessary in this version.
- An egg in a nest plus positive dispenser feed in that coop lets an available hen begin incubation. Incubation is an actual maternal behavior, not an offscreen egg timer: she approaches the nest and sits there when possible.
- Five game days of fed incubation hatch one chick. Partial progress is supported and inspection shows it explicitly.
- A hen lays no new eggs while incubating or raising a dependent chick.
- When feed runs out, she goes foraging. Incubation retreats at half its forward rate: 2.5 accumulated days takes five unfed game days to lose. Refill resumes remaining progress.
- At zero progress she releases her commitment and the farm's incubation slot, resumes normal laying, and leaves the egg usable in the nest. Positive feed permits an available hen to try again.
- Eggs never spoil, lose value, or become impossible to sell. Removing a nested egg resets progress immediately, frees the slot, and releases its hen. The egg returns to inventory and can be sold normally through the mailbox or nested again.
- One active incubation across the farm. No new incubation while any chick is present, including an independent chick whose adulthood is blocked. Other eggs remain collectable and sellable.

### Buying coop fittings

Daniel ruled after tablet play on 2026-10-31 that nest boxes and dispensers are bought
inside the coop, from their own store. The outdoor shop no longer offers these two
items. A small shelf on the coop's north wall pictures both goods; tapping it from
inside opens the same wordless cards used by the outdoor shop. Each costs 30g and
enters inventory for ordinary floor placement. Bought feed remains in the outdoor shop.

The wall shelf takes no floor space and is derived from every coop's room geometry.
Existing saved coops gain access without moving their fittings or changing the save.
Purchasing either fitting still uses `buy_machine`, with an explicit coop-shop context
that the gateway checks against the buyer's current room. Older uncontextualized
outdoor purchase actions keep their historical meaning so existing sessions replay.
Opening the shelf changes no simulation state and records no action.

### Feed and cozy gathering

- One wheat or one bought chicken-feed unit adds one day of incubation supply. Capacity is seven units. Partial top-ups are allowed; no overfilling or silent ingredient loss.
- Only incubation consumes the measured contents. Other birds' pecking is cosmetic and never consumes the sitting hen's feed.
- A positive dispenser attracts idle hens toward the coop, with occasional pecking/rests. It does not teleport birds or override maternal duties. Ordinary feeding gives cozy gathering, not growth, learning, egg-production, or familiarity bonuses.
- Empty dispensers do not threaten birds' welfare. The mother and chick forage after hatch without requiring any supplied feed.
- Inspection shows remaining feed; the ordinary dispenser picture visibly distinguishes full/partial/empty.

### Mother and chick

- One egg, then one chick per maternal cycle. No father, mating, fertility, or rooster requirement exists in this game.
- Seven game days of maternal care make the chick self-sufficient. During this time mother demonstrates scratching/pecking, calls her chick, and it approaches and copies. As care progresses it increasingly forages independently.
- The mother notices and attends the chick rather than wandering independently without regard for it. Calls, pauses, copying, searching, and settling make her care observable. No mandatory player rescue, feeding, or training.
- At night they return to a reachable coop and settle together. If no route exists, they settle together outside safely. Rain shelter remains compatible with these priorities.
- Separation is strictly Euclidean distance greater than six world tiles within an area, or being in different areas. No line-of-sight rule.
- Mother and chick each draw an independent seeded random delay of 2–30 seconds after separation. Either may seek first; both may seek by the end. Rejoining cancels pending searches.
- A seeker knows the other's exact current position and area; follows accessible door connections; updates the route if the target moves between areas. Never compare unrelated room-local coordinates as if they were the same area.
- When both become seekers, mother retrieves while the chick waits and peeps. If the chick starts first it walks toward mother. Purposeful paths never inherit player-attraction noise.
- Independence ends following and maternal care. Mother resumes laying; no enduring family-gathering preference.

### Temporary population limits

- At most two adults and one chick. Two adults do NOT prevent incubation or hatching of the single chick.
- At age seven days the chick becomes independent even when two adults are present. With both adult places full, it retains its chick appearance/stage. It neither keeps mother parenting nor blocks her laying.
- If an adult place subsequently opens, a chick whose seven days are complete becomes an adult. If a place was already free it matures at independence.
- This perpetual-chick rule is intentional and temporary for Daniel's daughter's enjoyment. Do not replace it with reservation of an adult place, selling requirements before hatch, hidden death, or forced departure.

### Names, familiarity, inspection

- Every chicken, including the original hen and hatched chicks, automatically gets a cute farm-animal name, stable across save/load/replay. Names show on inspection and sale confirmation.
- Direct individual greeting or treat builds lasting familiarity. The dispenser does not. There is no familiarity decay or practical productivity/handling reward.
- At maximum familiarity, approximately one idle wandering destination choice in five favors an accessible step/destination toward the player. This is a 20% mixture, not a 1.2-times weight multiplier, and not a steering correction on every physical step.
- Attraction stops comfortably near the player and never overrides incubation, maternal care, doors, searching, shelter, or sale collection.
- Explicit nest inspection shows progress and distinguishes advancing, retreating, waiting for feed, waiting for the chick slot, and inaccessible nest states without turning them into mandatory animal-welfare alarms.
- Simple chicken inspection shows name, adult/chick stage, ordinary care/activity, greeting, and selling. No trait ratings or inherited-habit display.

### Selling to other farmers

- Inspection offers selling, then a confirmation with the chicken's name, picture, and price. A dependent mother/chick pair is one clearly named sale and leaves together. An independent chick can be sold separately even if still small.
- Confirming brings an actual neighbor onto the farm. The neighbor walks to the selected chicken wherever it currently is, uses doors, collects it, and visibly carries it away before departing. Never substitute immediate disappearance or require player herding.
- Payment occurs at collection, not while a blocked buyer is still approaching. Pending sales can be canceled before pickup. Confirmed price and exact bird IDs are recorded, so unrelated birds cannot be sold or charged accidentally.
- If paths are blocked, the neighbor waits/retries and inspection permits cancellation; no teleporting or loss of birds. A dependent pair must stay together.

### Moving the coop

- Picking up the coop resets its incubation and releases the hen/slot. Its egg comes out intact under the existing building-removal egg rules.
- Unused feed returns to inventory without losing wheat/feed contributions or fractional remaining supply.
- Living chickens remain outside. A dependent mother/chick pair remains together, with its relationship and age intact. Moving a coop does not reset a chicken's name, age, or familiarity.

## Explicitly deferred

- Inherited behavioral variation, phenotype selection, genetics, and productivity breeding. No trait pictures/ratings, ancestry menu, or family-history display. Mother identity persists only for care, save safety, and pairing a dependent sale.
- Lasting family bonds after independence; fathers, roosters, fertility; growth/productivity benefits from feed; practical rewards from familiarity.
- Story-based population expansion, complex rehoming, and animal harm/death from player inattention.

## Completion choices made under overnight authorization

These are reviewable implementation defaults, not earlier rulings from Daniel. Validate economy and interaction details against the current code before finalizing them.

- Reunion completes in the same area within two tiles, giving hysteresis below the six-tile separation boundary. Delays reset after reunion; neither search teleports the pair. If the mother cannot route to a waiting chick, the chick may resume a reachable reunion route after a bounded retry rather than deadlock forever. Fully blocked routes produce safe waiting/replanning, not a welfare penalty.
- Deterministic scheduling: all within-day delays use the simulation's existing ticks; incubation and age use its actual day/progression mechanism. Do not assume elapsed wall seconds advance a game day. Sleeping/day turns count once, and explicit fast-forward and save/reload produce the same state as ordinary play. No offline real-clock growth.
- A nest/dispenser are coop room fittings on the existing shop shelf and touch-placement path. Place an inventory egg through the same selected-item interaction as other placeable items; inspect a nested egg to retrieve it. Feed from a contextual dispenser control choosing wheat or bought feed. Reject ineligible/overfull operations without consuming inventory or energy.
- Select an eligible nest deterministically, then the nearest reachable available hen with actor ID as a stable tiebreaker. A hen parenting, incubating, carried away, or already promised in a pending sale cannot begin another family.
- Sale button shows plain-language named confirmation and dependency pairing, allows cancellation until collection, and keeps sale participants reserved against duplicate sales/incubation. Buyer identity and transport survive saves/replays. If dependency changes before pickup, revalidate the confirmed group; never sell an unconfirmed extra chick or strand a dependent one.
- Familiarity starts at zero, caps at one internally, and a deliberate greeting increases it by 0.1. Debounce greetings so one held touch cannot generate repeat actions. Friendly stepping is cosmetic within the deterministic movement rules. No numerical friendship meter is required.
- Chick appearance develops visibly across the seven-day care period, retaining the final small-chick look when adulthood is blocked. Reuse shipped pixels via spritesmith/composition before any new art calls. No paid generation is authorized or needed for this implementation.
- Feed and sale prices are fixed, modest values grounded in the existing shop economy; record exact chosen values and rationale in the final implementation appendix. The nest/dispenser must be attainable during ordinary early play. No silent economy overhaul.
- Dispensers keep saved FIFO ingredient lots in half-day units. Recovering one returns whole unused wheat/feed units to inventory and any remaining half-day as one `saved_chicken_feed` portion (half a day's supply, shown as saved feed in its dispenser control). This preserves exact supply without rounding up or discarding it. Filling accepts those saved portions too. This is a completion detail under overnight authorization.

## Required acceptance scenarios

1. Existing farm migrates with its hen, eggs, decor nests, rooms, crops, and replay behavior intact. New hen gets a stable name, no free bonus eggs/stock.
2. Egg collected from ground, nested, then incubated by either eligible hen; five supplied days hatch exactly one registered chick, with a saved caregiver relationship.
3. At 2.5 progress, five unfed days reduce to zero; intermediate refill resumes remaining progress; zero releases mother and slot. Never spoil/devalue the egg.
4. Removing an egg, nest, dispenser, or coop handles progress/slots/contents without duplication, loss, ghost actors, or trapped dependent pairs. Coop feed recovery is exact.
5. A seven-day chick becomes independent, releases mother to lay, and matures only when adult count is below two. Two adults plus one independent chick persists safely across days/saves.
6. No hatch/second incubation can exceed the one-chick/one-incubation limit, including competing hens/nests and pending buyer arrivals.
7. Mother demonstrates foraging and chick approaches/copies; later chick independently forages. Feed is optional after hatch. Reachable nighttime coop return and safe outside fallback both work.
8. Euclidean six-tile boundary and different-area separation are distinguished from path distance/line of sight. Independent seeded 2–30s delays yield mother-first, chick-first, and both-seeking cases across seeds.
9. Reunion follows doors both ways, target area changes, blocked exits/retries, save/load mid-search, and both-seeker wait rule without doorway oscillation.
10. Direct greeting increments stable familiarity; normal idle wandering can favor player up to20%; no decay, dispenser familiarity, egg bonus, or interruption of parenting/incubation.
11. Named sale confirmation spawns physical neighbor, who collects a moving bird inside/outside and departs carrying it. Dependent pair stays together; independent small chick can sell alone; blocked buyer can cancel; payment/removal happen exactly once.
12. Save/load at mid-incubation, partial feed, independent blocked chick, mother/chick in separate areas, buyer walking and carrying; deterministic replay matches each resulting state.
13. Touch-first walkthrough and screenshots demonstrate dispenser states, egg inventory-to-nest, explicit progress, named inspection, maternal foraging/search, family nighttime settle, and neighbor carrying chicken.
14. Gateway, unit, integration, robot/replay, and benchmark checks pass on the feature branch. Record real output and limitations. No deployment.

## Implementation status

- Design rulings captured from this conversation. Source survey completed on `bbee9a9c`; isolated branch starts from newer main `6226c3fc`. Worker confirms cited contracts on this base before editing, without a second general survey.
- Isolated managed worktree created at `/home/daniel/.codex/worktrees/chicken-families/tiny-farm-godot-main`, branch `codex/chicken-families`, base `6226c3fc`.
- Execution tool's final response decoder is broken; `notify(await tools.exec_command(...))` returns usable output through progress. Initial apparent execution outage recovered with this workaround.

## Source findings (cite; do not re-survey)

| Contract | Source | Implication |
|---|---|---|
| Registry supports arbitrary persistent actor extras | `systems/sim/sim_world.gd:2277`, `:2307`; `systems/sim/save_game.gd:1237` | Multiple chicken IDs and stable names/relationships are possible; despawn through registry. |
| Scheduled chicken brain, morning lay decision | `systems/sim/brains/chicken_brain.gd:36`, `:61` | Extend scheduled behavior; change remote random egg position to actual laying tile, postponing if occupied. |
| Mutation gateway and brain dispatch | `systems/sim/sim_world.gd:3316`, `:3167` | All lifecycle, player and buyer mutations are recorded actions; one action per thought. |
| Motion time differs from days | `systems/sim/sim_clock.gd:17`, `systems/tools.gd:60` | Day lifecycle belongs to day progression hooks, not arbitrary seconds of real waiting. |
| Day actions already use gateway | `systems/sim/sim_world.gd:5487`, `:5584` | Insert daily incubation/care action once at rollover. |
| Rooms identify area, doors usable by actors | `systems/sim/sim_world.gd:1442`, `:1455`, `:3708`, `:3756` | Area-aware routes; door resets `extra.state`, so lifecycle fields stay separate. |
| Navigation example | `systems/sim/brains/cow_brain.gd:58`, `:121`, `:201` | Staged doorway walking and on_result recovery are established patterns. |
| Fittings and shop | `systems/machine_defs.gd:116`, `:464`; `ui/menus.gd:1763` | Nest is inert now, one grid object per cell; store nested egg separately, add dispenser row. |
| Egg inventory and sale | `systems/sim/sim_world.gd:3512`; `systems/game_state.gd:522`, `:556` | Preserve inventory items.egg and shipping-bin sale price. |
| Room removal | `systems/sim/sim_world.gd:3630`, `:4837` | Recover nested eggs/feed alongside fittings, eject living actors safely. |
| Room saves whitelist fields | `systems/sim/save_game.gd:793`, `:836`, `:1018` | Explicitly capture/restore poultry state; canonical comparison then includes it. |
| Neighbor cold-open is presentation-driven | `systems/species_defs.gd:186`; `entities/neighbour.gd:68` | Add separate sale-collector species/brain; reuse appearance, never hijack onboarding. |
| Chicken renderer supports arbitrary IDs | `world/farm.gd:267`; `entities/chicken.gd:101` | Extend for stage/activity; collector gets renderer registration. |
| Routing and inspection | `systems/action_router.gd:288`, `:105`; `ui/menus.gd:343`, `:389` | Route actors/fittings to shared style inspections before plain collection. |
| Modular test runners | `tests/test_runner.gd:4`, `:157` | Add explicit poultry module calls; stale AGENTS single-file description is not authoritative code. |
| Captures use scratch | `tools/capture_coop_inside.gd:19`, `:60` | Capture design evidence without autosaving into suite data. |

## Exact implementation contracts

Pure helper `systems/sim/poultry.gd` (`class_name Poultry`, RefCounted), with these static methods:

```gdscript
static func chicken_ids(world: SimWorld) -> Array[String]
static func adult_count(world: SimWorld) -> int
static func chick_id(world: SimWorld) -> String
static func incubating_id(world: SimWorld) -> String
static func chicken_at(world: SimWorld, tile: Vector2i) -> String
static func ensure_chicken(world: SimWorld, actor_id: String) -> void
static func nest_info(world: SimWorld, tile: Vector2i) -> Dictionary
static func dispenser_info(world: SimWorld, tile: Vector2i) -> Dictionary
static func sale_group(world: SimWorld, actor_id: String) -> Array[String]
static func sale_price(world: SimWorld, actor_id: String) -> int
static func apply(world: SimWorld, action: Dictionary, gs) -> Dictionary
static func day_actions(world: SimWorld, gs) -> Array[Dictionary]
static func before_room_removed(world: SimWorld, room_id: String, gs) -> Array
```

Use the repository's current action keys (`actor`, `verb`, `target`, `params`) and ordinary gateway result (`ok`, `reason`) conventions. Player verbs: `nest_egg`, `take_nest_egg`, `fill_chicken_feed`, `buy_chicken_feed`, `greet_chicken`, `request_chicken_sale`, `cancel_chicken_sale`. Lifecycle verbs: `start_incubation`, `poultry_day`, `collect_chicken_sale`, `depart_chicken_sale`. Supplement only for a necessary, documented recorded behavior; validate species, payload, inventory, area, capacity, participants, and target for every gateway verb.

Chicken species is shared by adult/chick. JSON extra fields: `name`, `stage` (`adult`/`chick`), `care_days`, `mother_id`, `chick_id`, `nest` (coordinate array or empty), `familiarity` (0..1), `seek_due_tick`, `seeking`, `sale_id`. More navigation/behavior state may be namespaced; never overload the movement `state` field. Record stable IDs with collision-safe allocation, saved across removed/sold actors.

Room `poultry` holds `nests` and `dispensers` dictionaries keyed `"x,y"`. A nest record includes `egg` bool, `hen_id`, `progress` measured in half-days, and optional stable status; dispenser `feed` measured in half-day units plus FIFO `lots` of `{item, units}` (units are half-days). Target incubation10; full fed rollover+2 and consumes2; unfed rollover−1; capacity14; each wheat or shop feed adds2; a `saved_chicken_feed` portion adds1. A partly filled last half-day can advance1 at cost1; no free full day from fractional food. Zero releases hen. This daily resolution is an agent-selected implementation detail: displays must use days/half-days, not suggest continuous progress that code does not simulate.

At end of seventh daily care update, release mother, mark chick independent, and convert stage only if adult_count<2. On subsequent adult-slot changes or daily reconciliation, eligible independent chick matures. No new incubation while chick_id is nonempty. Exactly one `poultry_day` action updates the whole flock per day, guarded against duplicate application for the same day. Persist the guard and ID allocation in world-level poultry metadata, not in an individual hen. Save canonical records include this guard and all persistent collections. Apply the daily action centrally inside the sleep/day rollover, not once for each chicken's day hook and not as an extra replay entry: current replay recomputes brain ticks AND nested sleep actions. A hatch-day chick starts care_days0 and does not also receive its first care day in that same rollover.

Feed advancement requires hen attendance at the adopted nest (same area, on or adjacent to it, reachable fitting interaction). If food is unavailable OR attendance is interrupted, do not consume food; retreat progress by1 per day, with the same zero-release rule. The hen continues seeking the nest while committed, but a blocked path cannot yield invisible incubation. This is an agent-selected default for review.

Feed economy default for review: one shop feed unit costs2g; dispenser30g; existing nest-box price unchanged. Adult sale30g, independent chick15g, dependent pair45g. Keep these constants centralized; no phenotype premiums. Existing egg price unchanged. All prices are agent-selected under overnight authorization, not Daniel's settled taste. The initial20g dispenser proposal was raised to30g during integration to preserve the settled25g coop as the cheapest building and first shelf item.

Familiarity greeting+0.1 with at most one accepted greeting per individual per game day (prevents tap farming/held input). Use preexisting interaction audio where possible. Optional treat can use the same greeting without consuming an unspecified crop; do not invent a second resource or feeding bonus.

Door routing shared by chicken and collector must route from room→yard→target room with current target re-evaluation, no teleport. Movement phase and lifecycle/care intent separate. Buyer collectors use their own explicitly persistent species so onboarding neighbor remains unaffected. Payment, exact participants, carried names/appearance, payment-complete flag and exit destination travel in recorded sale state. Show pending sale/cancel in actor inspection; once collected no cancellation or second payment. Requesting a sale of an incubating hen resets her egg intact and reserves her against resuming incubation, avoiding a hatch racing the buyer. Confirmed dependent pairs remain the same exact pair even if independence occurs before arrival. Do not add an unconfirmed actor. Pickup requires buyer adjacent (Euclidean<=1.5 tiles) to the named chicken and both dependent participants physically in the same area within two tiles before atomic removal/payment. If participants are separated, buyer waits while ordinary mother/chick reunion proceeds; never remotely remove an unseen chick. A full blockage permits safe retry or cancellation.

Add pure `before_fitting_removed(world, tile, gs)` cleanup alongside room removal for collecting a nest/dispenser directly. Feed refunds and egg ejection must run before removal without duplicating the building-level hook; tests cover each operation. Name allocation and world poultry metadata survive sale of all actors.

Explicitly classify `greet_chicken`, sale request/cancel, buyer collection/departure and informational inspection as non-work actions: no player-energy/pest-pressure increase from affectionate taps. Inventory egg/feed placement and retrieval follow existing fitting/inventory action conventions, documented by worker. Renderer never writes sim state, and all mutable lifecycle/sale/feed/greeting changes use gateway actions or existing deterministic brain scratch conventions.

## Work items and gates

1. **Plan review (read-only), completed.** Reviewer identified stale replay comments, duplicated per-actor day ownership, fractional ingredient refunds, direct-fitting cleanup, collector persistence/atomic pickup, nest attendance, and non-work classification. Root incorporated all eight findings above before implementation.
2. **Simulation worker.** Own pure helper, action dispatch, lifecycle/actor/name/feed data, save migration/canonical state, scheduled hen/chick/collector brains, deterministic cross-area navigation, recovery and unit/replay tests. No UI code. Own isolated worktree based on plan commit; commit but do not push. Required gateway check and full unit suite; include precise failing results instead of loosening assertions. Provide API/schema handoff for presentation.
3. **Presentation worker.** Own machine catalogue/shop/input routing/menus, chicken and buyer rendering, contextual feed/nest/name controls and local/procedural art. Program against this plan; simulation worker owns `systems/sim/`, `systems/species_defs.gd`, unit tests. Coordinate catalogue definitions by keeping new dispenser definition in presentation branch and simulation tolerating that known item string until integration. Do not touch sim source. Add capture scene/tool with scratch data; integration tests after simulation merge. Own separate worktree; commit but do not push.
4. **Integration and independent review.** Root cherry-picks workers into feature worktree, resolving overlap through workers. A read-only reviewer checks high-risk sim/save/actions and design fidelity; workers fix findings. Root runs actual full unit/integration/robot/benchmark/gateway after combination, reviews PNGs, and records results/limitations. No merge to main/deploy. Open PR and attach it, leave reviewable branch and evidence.

Workers read AGENTS supplied in this chat, docs/WRITING, this plan, and named source files only. Confirm base includes plan and current main. Other shared checkout work/media stay untouched. Git metadata is outside sandbox; use approved escalated git commands where necessary, never resets/stash/clean. Every report lists files, actual suite results/counts, decisions/deviations, worktree, branch, commit, and evidence paths in under300 words. Do not loosen assertions to pass.

## Review build — 2026-10-31

Implementation is complete for review on `codex/chicken-families`. Commit `7350a2aa`
was installed on Daniel's tablet on 2026-10-31 at 1:29pm Pacific. It has not been
merged to main or published as a release. The separate in-coop store requested after
that play-through is awaiting its verification and tablet refresh.
The working review checkout is `/tmp/tiny-farm-chicken-final`; the shared checkout
and its video work were preserved. [Pictures from the running game](mockups/chicken_families/README.md)
show inventory, feeding, incubation, the named family, and the visiting farmer.

### Completion details to review

- Dispenser 30g, bought feed 2g per day, adult 30g, independent chick 15g,
  dependent pair 45g. The dispenser was raised from the first 20g proposal to
  preserve the existing 25g coop as the cheapest structure. Nest and egg prices
  remain unchanged. These prices are provisional choices, not earlier rulings.
- Incubation and maternal age advance at game-day rollover, not while the game
  is closed or merely left running. Progress uses half-day units and exact feed
  refunds; a partly consumed ingredient can return as a saved half-day portion.
- Greetings are accepted once per chicken per game day, add 0.1 familiarity,
  and never increase work/pest pressure. Familiarity stays after absence and
  biases at most one in five idle wander choices toward the player.
- Same-area reunion completes within two tiles. A blocked route safely waits
  and retries. Feed does not advance incubation while its hen cannot attend.
- Selling a sitting hen resets her egg intact and reserves her against another
  incubation. Pickup is local and atomic; both dependent birds must be present.
  Confirmed participants and price are validated, and collection pays once.
- No inherited traits, trait display, ancestry interface, father, compulsory
  animal-care task, feed-dependent chick growth, or practical friendship bonus.

### Verification on the combined implementation

| Check | Result |
|---|---|
| Full unit suite | 3915 passed, 0 failed |
| Full integration suite | 1454 passed, 0 failed |
| End-to-end robot session | Passed; replay matches autosave over 689 entries and 4823 ticks |
| Gateway check | Passed |
| Simulation benchmark | Passed; 19,617 ticks/sec against minimum 5,000, 192 microseconds/tick against maximum 441 |
| Graphical family walkthrough | 29 passed, 0 failed; eight real-game pictures reviewed |
| Offline writing verification | Passed; existing baseline suggestions outside this feature remain |

Independent simulation review found and verified fixes for refused actions
changing saved state, families failing to leave the coop, and older chicks
foraging while their mother settled. Regression tests cover these cases.
Historical playtest classifications were not changed. A refusal fixture that
depended on eggs being placed remotely was replaced with a deterministic
blocked-door refusal, retaining the exact replay assertion.

The first combined unit run also caught the dispenser undercutting the coop's
settled shelf role. Its price was corrected and the full unit suite rerun.
Visual review caught a camera framing the wrong room; the capture now follows
the subjects' actual area and asserts real renderers are visible and unobstructed.

The headless suites still print resource-leak diagnostics seen in the baseline;
the required checks above exit successfully. No animal biology claims are made:
the timing, inheritance exclusions, and perpetual-chick limit are game rules.

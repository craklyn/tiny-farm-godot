# 04 — Pests & Ecology

*Status: outlined (scent-layer mechanics settled, P-10). Blocking: enemy identity (D-3)
for fiction; M3 planning for phase-2 tuning.*

## Core mechanism: the scent layer (P-10)
Pest group behavior is trail dynamics — scouts mark, foragers follow, success
reinforces, decay erases. Full mechanics in `../ARCHITECTURE.md` ("The scent layer").
Difficulty tuning = decay/reinforcement constants, not spawn counts.

## Roster structure (fiction TBD under D-3)
| Phase | Behavioral archetype | Mechanical role |
|---|---|---|
| 1 | Individual opportunist (crow exists) | Teaches attention + response |
| 2 | Trail-laying foragers (scouts + followers) | Teaches the scent layer + counterplay |
| 3 | Wave variants: scent-sensitivity/speed/armor axes | TD variety via *different noses* |
| 4 | Persistent pressure at fleet scale | Bots' training curriculum |
| 5 | Nest ecology + defenders (+ queen — leading hypothesis, D-3) | Expedition content |

## Species table (tier 1 — started M2.5 WI-8; `systems/species_defs.gd` is the data)
Per species: verbs used (pests use player-verb *subsets*, P-9), scent behaviors (what it
lays, what it follows, what repels), senses, speed. Rows below exist in code and are
**not spawned in the live game** — their debut is content sequencing, not engineering.

| Species | Verbs | Scent | Senses | Speed | Counterplay |
|---|---|---|---|---|---|
| Ant scout | *none* — it walks and it marks | **lays** `pest_trail` on every tile of its walk home | crops within 3 tiles | 10 px/s | **stomp** (a clear-class tap on its tile). A stomped scout never gets home, so the column never forms. |
| Ant forager | `eat_crop` (the crow's, reused) | **follows** the strongest neighbouring `pest_trail` (excluding the tile it came from); **reinforces** it on the way home | trail only — it carries no map | 8 px/s | **wash** (`water` on a trail tile erases the cell). A hole in the trail disperses the column. A rainy day turn washes the whole field (Q-58). |
| Rabbit | `eat_crop` (the same one again) | none — it neither lays nor follows | crops within 5 tiles; **flees the player's `spook_radius`** | 30 px/s | **stand near it.** No tap, no tool, no verb: it bolts inside her radius and comes back outside it. |
| Kangaroo | `eat_crop` | none | the rabbit's, exactly — the same table entry | 45 px/s | the rabbit's. It **crosses fence-class tiles** (fence, hedge, closed gate), so a hedge is not counterplay against this one. |
| Songbird | *none at all* | none | none | 35 px/s (flies) | none needed — it never touches anything. |
| Mole | `eat_crop`, on a **sown** tile — it steals the seed and leaves the soil tilled | none | none at all; it is not frightened of anything | 20 px/s (**burrows**) | **be standing there.** It will not surface where the player is, so guarding a seedbed works; and it is stompable *only* in the second or two it is above ground. |
| Worm | `eat_crop` | none | crops within 4 tiles | 6 px/s — the slowest thing in the game | **stomp**, on any tile it occupies (a tap on the tail is a tap on the worm). |

A raid is: one scout → one completed trail → a column of 3 foragers → one crop each,
carried home. That bounds a raid's cost at the column size and a day's at
`raids scheduled x column size`, which is the crow's T-15/T-20 daily-loss identity
extended to a new mouth. The **difficulty dial is `pest_trail`'s half-life**, per §1
above — turn it down and a column starves before it forms, without changing a
spawn count.

A grazer's visit is: arrive at a gap in the boundary → wander → find a crop → take a bite
→ repeat until full → leave the way it came. Its cost is bounded by **bites per visit**
(2 today, `SimWorld.GRAZER_BITES`), counted by the animal itself and re-checked every time
it grazes, so frightening a full rabbit off its way home cannot buy it thirds. That extends
the daily-loss identity again: `crows + raids x column size + grazer visits x bites`.

**The rabbit and the kangaroo are the same brain.** They differ by one field of the species
table — the movement capability — and that difference is the whole kangaroo: it clears
fences, hedges and closed gates, so the boundary that says "not yet" to the player and to
every walker says nothing to this one — **ruled 2026-08-31 (Q-57): wild things hop anything,
closed gates included, because a boundary is the player's rule and not nature's**. Whether
fleeing is the whole of a grazer's answer is now the row's own `fright_ends_visit` field
(Q-63), false for both of them today.
If the two ever need to *feel* different, that is a behaviour to add on purpose, not a
difference to preserve; today the honest statement is that a kangaroo is a rabbit that
does not care about your fence.

**And she can put up fences of her own now** (Q-92, built 2026-09-07). Bought as a card of
ten at the seed box, one post per tap on bare ground, taken back up by tapping it and
refunded — so a run she regrets costs her nothing, which is what makes a long line safe to
try. Drawn with the game's own fence cell, because the **hedge** is the word for "not yours
yet" and the fence already means "yours"; hers is a separate tile state only so the world's
own boundaries stay hers to look at rather than to dismantle.

**Ruled 2026-09-10 (Q-92, on the dashboard): the starting fence is hers too, once fencing is
unlocked.** Until then it stays what it is today — the boundary of the cold open, which she
cannot dismantle. After the unlock, tapping a fence the world laid picks it up into her crate
like one she built, and she can lay it again wherever a fence may go. Hedges are untouched:
they remain the lock on land she has not earned. Converting home turf to farmland and back is
a later update (D-15).

It changes exactly one row of the table above, and that is the design rather than a
shortfall: **a fence answers the rabbit and nothing else.** The crow flies over it, the
kangaroo clears it by the ruling that made it a kangaroo (Q-57), and the mole tunnels in
underneath. One counter for one pest, bought and placed by hand — the ecology was written
as though player fences already existed, and this is that assumption arriving.

**The mole steals seed, and that is a different loss from a bite.** Its visit is: tunnel in
under the boundary → surface on a tile somebody has sown → take the seed (the soil is left
tilled, which is what `eat_crop` has always done to a sown tile) → go back down → do it once
more, or leave. Its cost is bounded by **steals per visit** (2 today, `SimWorld.MOLE_STEALS`),
so the daily-loss identity gains a term denominated in *seeds*: `crows + raids x column size
+ grazer visits x bites + mole visits x steals + worm visits x meals`. A seed has always
counted as planted, so this is a subset of the same loss rather than a new kind of it — but
it is the loss the player paid gold for and has nothing to show for, which is a different
feeling from losing a head of wheat she watched grow. It is also the first critter whose
counterplay is a **reaction**: while it is under the farm nothing on the surface can reach
it and nothing frightens it, so the answer is the moment it comes up (`[Designer]` Q-64).

**The worm is the multi-tile animal, and its own body is its problem.** It crawls from crop
to crop and grows one segment per meal (`extra.body_len`), its segments occupy the tiles
behind it, and the movement engine refuses to let its head enter a tile it is already lying
on — so a long worm has to go *round* itself to reach anything behind it, and a long enough
one can curl up with all four ways out being worm, at which point it gives up and goes back
into the soil. That is the classic snake constraint, and it is the whole of the design: the
growth is spectacle rather than mechanic today. `[Designer]` Q-65 — whether a worm should be
a pest at all in a cozy farming game, and whether its length should ever mean anything — was
**parked unruled on 2026-08-31 by the designer's explicit choice**: the worm stays a
zero-dial proof that the movement engine carries a body, and its meaning is left for a phase
that wants it.

**A crow on a crop flaps and turns left and right while it eats** (2026-09-10, the
designer's call): the bird taking a crop is the farm's alarm, so it must not sit still —
the meal used to hold a single frame for its whole five seconds, which made the most
expensive thing on screen the only thing on it not moving. Wings on a quick beat, a turn
every third one, and a pixel of bob on the open wing, all in `entities/crow.gd`: the
animation is presentation and the meal itself is untouched. The richer **crow gorge** loop
drafted in the Animation Lab (`tools/experiments/out/crow_gorge/`) is the candidate for a
later, drawn version of the same moment.

**The night the acorns run out** (2026-09-10, P-15): the sleep after the last acorn leaves
the ground plays the crow gorge loop once, inside the fade — a wordless warning that the
crows turn to crops next. She can bring that night on herself by picking the acorns up
(Q-48), which is what makes it a consequence rather than a cutscene.

**The morning after: the crows come for the tomatoes** (designer, 2026-09-10). The night
loop is a warning, and the next morning keeps its word. On a day the player has four or
more tomato plants, she leaves the house and, as the plants come into view, three crows are
already on three of her tomatoes, eating. Reach them quickly and they are shooed as normal;
dawdle and those tomatoes are eaten. The shape in the sim, so it stays deterministic and
replayable: **one trigger** decides both the night and the morning — the first sleep where
the last acorn is gone *and* four or more tomatoes stand — so the warning and the raid are
one event and never days apart; the day turn places the three crows on three tomatoes; their
meal clocks start on her `use_door`, not at dawn, because "as the plants come into view" is a
thing the sim can only know by the door; and the shoo is the ordinary one. **Deliberately
small first:** no special camera, the crows are the 1× birds with their eating animation, and
a scarecrow already on the field does what it always does.

**The race, measured** (2026-09-10, rebuilt 2026-09-11). An ordinary crow's meal is five
seconds and she walks three tiles a second, and how many tomatoes a direct walk out of the
door saves is the whole of what the raid teaches: losing none teaches nothing, losing all
three punishes a morning she had no part in. The raid first shipped with a meal of its own
— **3.7 seconds**, measured rather than guessed on the farm the game generates, which saved
two of the three on the nearest ground she can plant. Its limit was that one meal length
meets a distance the player chooses: on a bed ten tiles further out the same meal saved
none, because she was still six seconds away when the birds finished. **Ruled 2026-09-11
(Q-105): the meal lasts as long as her walk.** The last bird takes its tomato the moment
she has seen off the second one, so the raid costs exactly one tomato wherever the bed is —
over in three and a half seconds beside the house, in six ten tiles out, and the same
lesson at both. The only clock left in it is the birds' patience, a minute from the door:
what a player who comes out, sees three crows on her tomatoes and does nothing loses the
bed to. `tools/measure_raid_race.gd` now walks her out onto both beds and plays the morning
through the gateway rather than reasoning about it, so what it prints — two saved of three
on each — is what the game does, and the unit suite asserts on the same two runs.

**A ransacked plot says so** (designer, 2026-09-11; what it looks like ruled 2026-09-19). A square a bird emptied is
turned soil with nothing on it, which is also what a row she hoed and has not sown looks
like, so a loss read as a chore she forgot. The square now carries the fact that something
ate a plant off it — saved with the world, cleared the moment she works it again — and
**does not go to bare earth at all**: it keeps the plant, stripped. What is left standing is
a bitten, broken-off stalk of whatever was growing there — the head or the fruit gone, one or
two torn leaf stubs still on it, and a little of it scattered on the ground at its base. The
loss reads as a loss rather than as ground, and the square says which plant it lost.

That is **Q-110**, ruled 2026-09-19. The designer opened it on 15 September after looking at a
raided square on a real farm and asking whether it was a fault — the first version's mark,
three clods of earth cut from the tilled-soil sheet, failing at the only job it had. He then
declined to choose between four descriptions and asked for all of them built: a crow's
feather, the stripped plant, and the clods sat down and darkened were each drawn and
photographed on a real raided square at the size the game draws it (boards under
`docs/design/mockups/ransack_mark/`), and **the stripped plant won**.

How it is put together:

- **The square remembers what it lost.** `eat_crop` writes `ransacked_crop` beside the mark,
  read off the tile before the state is cleared to soil. It is saved with the world and it
  comes off with the mark, by the same line that clears the mark.
- **One stripped stage per crop**, drawn from that crop's own colours by
  `tools/gen_stripped_crops.py` — wheat left headless with a few grains shaken out, the tomato
  with a scrap of skin at its base, the pea with the tendril it was climbing by. The pictures
  in that file are grids of letters, so changing one is editing the grid.
- **It is drawn with the crops, in the crop pass, on the square's own y.** That is not a
  detail. The first version's mark was a node of its own so it could animate, and on
  2026-09-16 the farm page moved into a child of the farm and painted over every one of those
  nodes: a raided square drew nothing at all for four days, in public, with both suites green,
  because the tests asserted the shape the mark would draw and never that anything could see
  it. A picture drawn where the crops are drawn cannot be covered by its own ground, and it
  sorts under whoever is standing on the square for free. The check that a raided square does
  not look like bare soil now lives in `tools/capture_ransack_mark.tscn`, beside the visual
  regression, because only a real screen can answer it.

**Clearing it costs her nothing extra** (**Q-112**, ruled 2026-09-19). The stalk is a
picture, not an obstacle: tilling or sowing the square takes it away in one verb, exactly as
the clods went. The alternatives were put to the designer the night the stalk shipped — a beat
to clear it like a weed, a seed handed back for pulling it, or a block on sowing until it is
gone — and he kept it free. A raid already costs her a tomato and the walk out to the bed, and
charging her a second time for the same bird taxes the player who was already unlucky.

**What "planted" means** is settled by the crow's own appetite: the four are counted with
the same rule a bird picks its target by, so a tile the crow could not eat does not count,
and a bed can never pass the test and then leave a bird with nothing on the tile. A sown
tomato does count — a crow that lands on one takes it, and the soil is left turned.

## Sections to fill
2. **Nests** — where they spawn relative to the farm, growth over time, visibility
   `[Designer]` Q-18 (early visibility foreshadows phase 5's trail-tracking).
3. **Raid lifecycle** — scout phase → trail formation → forage column → satiation or
   repulsion. **Built for the ant pair at M2.5 WI-8** (arrival on the day's action clock
   like the crow's, one raid at a time, scout despawns into the nest as the column
   leaves it); readability targets are still `[Designer]` Q-17 (a forming raid must be
   *seen*) — nothing in the game telegraphs one yet beyond the ants themselves.
4. **Counterplay catalog** — wash (watering can), stomp scouts, dig breaks (hoe) are
   settled (P-10). **Wash and stomp are implemented** (M2.5 WI-8a/8b), both on verbs
   the player already has; the hoe dig is unbuilt. **Presence is now counterplay too**
   (M2.5 WI-8c): the grazers flee the player's `spook_radius`, which is the first answer
   in the game that is not a verb at all — she walks over and the animal goes. **Presence
   is also what protects a seedbed** (M2.5 WI-8d): a mole refuses to surface anywhere near
   her, so standing in the sown row is counterplay against a critter no tap can reach.
   Whether a fright *ends* a visit rather than pausing it is now a **field on the species
   row** (`fright_ends_visit`, Q-63 ruled 2026-08-31), false for both grazers today, so
   ruling it for a given animal is a data edit rather than a code change. **The weather is
   counterplay she does not perform** (Q-58 ruled 2026-08-31): a rainy day turn washes every
   scent channel on the whole farm, because water is water — a raid does not survive a wet
   night. The stomp now has two qualifiers, both from the critters that needed them: a
   burrower is unanswerable while it is under the ground (so the mole's window is the seconds
   it is up, and Q-64 ruled 2026-08-31 that its mound stays visible while it travels), and a
   multi-tile animal answers on any tile it occupies (so a tap on a worm's tail is a tap on
   the worm). Additional verbs `[Designer]` Q-16 (swat/chase, thrown objects, dog?). Q-61 is
   ruled (2026-08-31): a tap that targets a *critter* rather than a tile is blessed as the
   stomp's shape, with a device pass owed when ants debut.
5. **Neutral wildlife** — chicken exists; role of harmless fauna (charm, eggs, ambient
   life for the kid layer; also negative training examples for bots: *don't* attack the
   chicken). **The songbird is the first one built for this and nothing else** (M2.5
   WI-8g): it has no verbs, its brain has no path that can return an Action, and a
   recorded session containing one contains not a single entry naming it. It drifts,
   perches, and goes. That is a design entry as much as an engineering one — it says the
   roster may contain animals whose entire contribution is that the farm is inhabited, and
   it gives a phase-4 bot a second thing that must not be chased. It is currently silent;
   whether ambient fauna make noise is `design/10`'s question, not this chapter's.

   **The hen answers the weather** (P-17, CEO 2026-09-11). She is the first animal in the
   game whose behaviour the sky reaches: buy a chicken coop from the shop and on a rainy
   day she walks into it and sits there instead of pottering about the yard. Nothing else
   changes — she lays as she always did, her brain costs the clock the same one thought per
   decision, and on a farm with no coop on it a wet day is an ordinary day. The point is
   that the farm is *inhabited*: an animal that answers the weather is doing something for
   its own sake, which is the same claim the songbird makes and a stronger one, because a
   player can watch the cause.

   What this leaves open for this chapter is the table behind it. Today the rule is one
   animal, one shelter and one bad sky, written in `ChickenBrain`. A second sheltering
   animal, or a second kind of weather to shelter from, turns that into a fact about a
   species row — which animals shelter, in what, from what — and is the moment to write it.
   The trigger is recorded on P-17.
6. **Ecology depth** — do pests exist when unobserved (persistent nests with populations)
   or spawn per-raid? Leans on decision LOD (`ARCHITECTURE.md`); `[Joint]` at M3.

## Constraints from decisions
All pest behavior runs in the deterministic sim (S-5) — raids are reproducible for tests
and training. Pests are candidate observation content for bot sensors (vision/audio/
smell ladders).

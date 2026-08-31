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
6. **Ecology depth** — do pests exist when unobserved (persistent nests with populations)
   or spawn per-raid? Leans on decision LOD (`ARCHITECTURE.md`); `[Joint]` at M3.

## Constraints from decisions
All pest behavior runs in the deterministic sim (S-5) — raids are reproducible for tests
and training. Pests are candidate observation content for bot sensors (vision/audio/
smell ladders).

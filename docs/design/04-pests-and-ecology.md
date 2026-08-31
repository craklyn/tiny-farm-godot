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
| Ant forager | `eat_crop` (the crow's, reused) | **follows** the strongest neighbouring `pest_trail` (excluding the tile it came from); **reinforces** it on the way home | trail only — it carries no map | 8 px/s | **wash** (`water` on a trail tile erases the cell). A hole in the trail disperses the column. |

A raid is: one scout → one completed trail → a column of 3 foragers → one crop each,
carried home. That bounds a raid's cost at the column size and a day's at
`raids scheduled x column size`, which is the crow's T-15/T-20 daily-loss identity
extended to a new mouth. The **difficulty dial is `pest_trail`'s half-life**, per §1
above — turn it down and a column starves before it forms, without changing a
spawn count.

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
   the player already has; the hoe dig is unbuilt. Additional verbs `[Designer]` Q-16
   (swat/chase, thrown objects, dog?), plus Q-61 (a tap that targets a *critter* rather
   than a tile is new, and it is the stomp's whole shape).
5. **Neutral wildlife** — chicken exists; role of harmless fauna (charm, eggs, ambient
   life for the kid layer; also negative training examples for bots: *don't* attack the
   chicken).
6. **Ecology depth** — do pests exist when unobserved (persistent nests with populations)
   or spawn per-raid? Leans on decision LOD (`ARCHITECTURE.md`); `[Joint]` at M3.

## Constraints from decisions
All pest behavior runs in the deterministic sim (S-5) — raids are reproducible for tests
and training. Pests are candidate observation content for bot sensors (vision/audio/
smell ladders).

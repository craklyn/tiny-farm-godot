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

## Sections to fill
1. **Species table** — per species: verbs used (pests use player-verb *subsets*, P-9),
   scent behaviors (what it lays, what it follows, what repels), senses, HP/speed.
2. **Nests** — where they spawn relative to the farm, growth over time, visibility
   `[Designer]` Q-18 (early visibility foreshadows phase 5's trail-tracking).
3. **Raid lifecycle** — scout phase → trail formation → forage column → satiation or
   repulsion; readability targets `[Designer]` Q-17 (a forming raid must be *seen*).
4. **Counterplay catalog** — wash (watering can), stomp scouts, dig breaks (hoe) are
   settled (P-10). Additional verbs `[Designer]` Q-16 (swat/chase, thrown objects, dog?).
5. **Neutral wildlife** — chicken exists; role of harmless fauna (charm, eggs, ambient
   life for the kid layer; also negative training examples for bots: *don't* attack the
   chicken).
6. **Ecology depth** — do pests exist when unobserved (persistent nests with populations)
   or spawn per-raid? Leans on decision LOD (`ARCHITECTURE.md`); `[Joint]` at M3.

## Constraints from decisions
All pest behavior runs in the deterministic sim (S-5) — raids are reproducible for tests
and training. Pests are candidate observation content for bot sensors (vision/audio/
smell ladders).

# 02 — Farming System

*Status: outlined (phase-1 baseline is implemented in the prototype). Blocking: crop
breadth and seasons rulings (Q-20).*

## Implemented baseline (prototype, phase-1 scale)
32×20 grid, 16px tiles (`world/farm.gd`); tile states (obstacle → cleared → tilled →
seeded → growing → ready); tools: hands, axe, pickaxe, hoe, watering can, seeds
(`systems/tools.gd`); crops: wheat, tomato (`crops/crop_defs.gd`); energy 20/day,
watering-can charges, well refill; shipping bin → gold overnight; day/weather scaffold
(`systems/game_state.gd`, `systems/day_cycle.gd`).

## Sections to fill
1. **Crop roster & growth math** — growth stages/days, water sensitivity, price curves.
   Breadth target `[Designer]`: a handful of iconic crops vs. a wide catalog.
2. **Soil & tile states** — degradation? fertilizer? (keep phase 1 simple per S-7).
3. **Weather & seasons** — `[Designer]` seasons yes/no is a scope fork: seasons add
   rhythm and replay depth but multiply art, balancing, and pest-behavior work. Weather
   already exists as a variable; minimum viable is rain-waters-crops.
4. **Energy & time economy** — energy costs per action exist; tuning is `[Playtest]`
   with the kid constraint bounding phase-1 friction (Q-11).
   **Settled 2026-08-29 (designer): energy is per actor, and only the player's is the
   clock.** Every actor — the player, the departing neighbour, and every bot phase 4
   eventually adds — has its own meter (`SimWorld.actor_energy`, sim truth, saved and
   replayed). Spending the *player's* is what advances the time of day (Q-38), but that
   is a property of her meter rather than a licence for everyone else to work for free.
   An NPC simply gets tired, under the same Q-11 soft floor: the meter clamps at zero and
   the action still resolves. Everyone wakes rested when the day turns. Open and
   `[Playtest]`: whether NPCs should instead recover *during* a day as the player's own
   clock advances, and what `ACTOR_MAX_ENERGY` should be per actor type.
   *This was found by building it — the cold open (T-13) puts an NPC through the player's
   own action gateway, and the first fix made non-player actors cost-free, which is wrong
   in the same way for the opposite reason.* Only energy is metered per actor; NPC seeds
   and water are not modelled, because an NPC pouch would be state to save, replay and
   keep coherent for no phase-1 gain.
5. **Money economy** — sources (shipping) and sinks (seeds, machines, towers, bots) per
   phase; the economy must fund each phase's new system. `[Claude]` first-pass
   spreadsheet model at M3 planning.
6. **Land expansion** — how new rings unlock (gold? proofs?), tying into world scale
   plan (`ARCHITECTURE.md`).

## Constraints from decisions
Grid is truth (S-4); every farm interaction is an Action verb (S-3); phase-1 loop must
satisfy S-7; desire-path wear channel renders on farmed land (P-10).

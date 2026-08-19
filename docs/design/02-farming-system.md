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
5. **Money economy** — sources (shipping) and sinks (seeds, machines, towers, bots) per
   phase; the economy must fund each phase's new system. `[Claude]` first-pass
   spreadsheet model at M3 planning.
6. **Land expansion** — how new rings unlock (gold? proofs?), tying into world scale
   plan (`ARCHITECTURE.md`).

## Constraints from decisions
Grid is truth (S-4); every farm interaction is an Action verb (S-3); phase-1 loop must
satisfy S-7; desire-path wear channel renders on farmed land (P-10).

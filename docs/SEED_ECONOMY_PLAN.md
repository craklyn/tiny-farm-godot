# Harvest-as-seed prototype implementation

Date: 2026-09-23. Owner: Adam, Chief of Staff. Status: plan under review; no game code landed.

## 1. Ground rules

- Build from clean `main` (`68a8a0f` when surveyed), in isolated worktrees. Do not copy the dirty shared checkout or apply the stale 26-file patch whole. Reuse its tested parts selectively.
- Every gameplay mutation, including deposits and withdrawals, goes through `SimWorld.apply_action`. Preserve deterministic replay and the pure simulation layer. Do not add per-tile frame work.
- Update the design record with code. Do not mark an HQ ruling integrated or a work card done until code, docs, and verification agree.
- Do not silently trim stock from existing saves. Do not weaken failing assertions to make a build green.
- Broad HQ draining stays paused; this plan covers one seed-economy landing, not the whole backlog.

## 2. Surveyed facts (cite; do not re-survey)

| Fact | Source |
|---|---|
| Main has separate `seeds`, `crops`, and `shipping_bin`; it starts with five wheat seeds. | `systems/game_state.gd:21-25,196-199` |
| Current bin sale consumes all carried crops; machine sale immediately converts one crop to gold; sleep clears legacy `shipping_bin`. | `systems/game_state.gd:436-476` |
| All actions enter `SimWorld.apply_action(action, gs)`; current sell and seed-purchase branches are there. | `systems/sim/sim_world.gd:2387,2424-2449,2518` |
| Plant spends seed stock; harvest gives one crop and clears the tile. | `systems/sim/sim_world.gd:3220-3233,3277,3293-3314` |
| Save schema is v4; capture, restore, and ordered migrations are in one module. | `systems/sim/save_game.gd:24,35,225,431-446` |
| Tapping the bin currently resolves to `sell`; there is no withdraw action or UI. | `systems/action_router.gd:41,165-182,440,507-517`; `main.gd:991-1006`; `ui/menus.gd:215,587-612` |
| HUD and other consumers still read separate crop and seed maps. | `ui/hud.gd:824,1023`; `systems/action_router.gd:348-355,473,513-517` |
| The old patch is held and unapplied. It keeps three in the pouch, which conflicts with the new bin-reserve ruling; it also conflicts with current tests and a generated `.uid`. | `hq/data/work/we49bc7771da.json`; `hq/data/patches/we49bc7771da.patch` |
| No grain silo is currently defined in the catalogue. The 40-capacity rule is a future-building contract, not a playable upgrade yet. | `systems/machine_defs.gd` (surveyed 2026-09-23) |

## 3. Settled prototype decisions

- Q-113: capacity is **per species**: 10 carried of each species, or 40 of each once a grain silo exists. No current silo is to be invented for this change. Numbers are `[Playtest]`.
- Q-115: every successful harvest of one planted crop grants exactly **three** plantable units of that species.
- Q-116: the shipping bin holds a persistent, separate reserve of up to **ten plantable units per species**. Deposits fill this reserve first. Only excess of that species sells. The reserve does not count against carrying capacity. Numbers are `[Playtest]`.
- A carried crop and a seed are the same plantable unit. Use one canonical carried-stock map for plantable species, not independently mutable `seeds` and `crops` balances. Inventory entries that are not plantable crops (notably eggs and scarecrows) retain their existing sale/use behavior but never count toward crop capacity or enter the replanting reserve. `CropDefs.TYPES`/`ORDER` membership alone is not a plantability test: define an explicit crop-kind predicate or metadata.
- The reserve must be usable without magical remote planting: tapping the bin opens a small menu to **deposit carried stock** or **take reserved stock** by species. Planting consumes carried stock only. The take action transfers as many of the chosen species as will fit (up to its per-species cap). If none fits, it refuses without changing either balance. The menu states reserve counts and the quantity sold by the last deposit in plain language; no new art is required.
- Harvest is atomic at carrying capacity. If carried stock plus three exceeds that species' cap, refuse before energy, crop, or RNG state changes; leave the crop ripe. Buying a plantable seed and withdrawing reserve stock obey the same per-species cap. Existing over-cap saved stock remains intact but cannot increase until under cap.
- Machine harvest also yields three units. Extend the machine hand to retain a count (defaulting to one for old saves/replays); its sell action delivers all held units through the same reserve-first-then-sell allocator. Machines are not subject to the player's pouch cap. No units may disappear between harvest and delivery.
- Existing saves migrate by summing legacy seed and crop counts **only for plantable species** into carried stock, without clipping. Preserve eggs and scarecrows with their old behavior and counts. Existing `shipping_bin` pending-sale state remains distinct and clears/pays at sleep under its old semantics; new reserve starts empty. Save/replay formats change only through a versioned migration.
- Deposit and withdrawal at the bin are non-work errands: neither advances the action clock or charges energy. Add `withdraw_seed` to the same non-work-verb treatment as `sell`.

## 4. Interfaces and work item

One implementation owner owns this cohesive change because sim, save, UI, and both test runners share state. Start at current main's tip; do not use the dirty shared checkout. Preserve the action gateway:

- `SimWorld.apply_action(action: Dictionary, gs = null) -> Dictionary` accepts existing `plant`, `harvest`, `sell` (bin deposit), and a new `withdraw_seed` action with `params.crop_type: String`. A withdraw result reports moved units; a deposit result reports units reserved and sold by species, so UI can tell the truth. Replays use these actions, not direct menu mutation.
- Change `GameState.sell_crops_to_bin() -> Dictionary` and `sell_one_crop(crop_type: String, count: int = 1) -> Dictionary` to return `{ok, reserved, sold, gold}` counts (per species for a mixed player deposit). Update every caller. Both use one internal `allocate_bin_delivery(crop_type: String, count: int) -> Dictionary` so machine and player sales cannot drift.
- `GameState.withdraw_reserved_crop(crop_type: String) -> int` transfers from reserve into carried stock up to that species' cap. The exact carried-stock field name is chosen once and used consistently in sim, consumers, and save schema.
- `SaveGame.capture/restore/migrate` moves v4 to v5 with one canonical carried plantable-stock map, preserved noncrop inventory, a separate reserve map, and backward-compatible machine-hand count. Unit tests lock the migration and replay behavior, including a v4 save with pending `shipping_bin` sale through sleep.
- `ActionRouter.resolve(...)` routes bin tap to a menu-open intent (UI-only, no world mutation), and the menu dispatches `sell` or `withdraw_seed` through the normal action gateway. Remove the old `basket_empty` satisfied result that would prevent opening the menu when the pouch is empty; update the contextual keyboard/tap hint. Keep machine actor behavior deterministic.
- The shop card must not look affordable when a plantable species' pouch is at its cap. A rejected purchase leaves the shop visible and shows a clear full-pouch cue consistent with the shop's existing visual, pre-reader interaction; do not put an English-only refusal label into that wordless surface. Gold and stock do not change. The integration test must check the visible shop state **after** the failed press, without clearing the feedback first.
- The bin's “last deposit” display reports the last **player** deposit. Machine delivery must not overwrite that claim; if machine delivery is shown, label its source distinctly.

Acceptance criteria:

1. A fresh farm starts with five plantable wheat units. Wheat starter packets no longer need to be bought; other species retain their existing unlock/purchase rules unless an existing ruling says otherwise. Buying at a full pouch refuses before charging gold.
2. One planted wheat or tomato yields three plantable units on harvest. Planting consumes one carried unit. A second species does not consume the first species' 10-unit capacity.
3. At 8/10 carried of one species, harvesting its ripe crop refuses atomically; the tile remains ripe, energy unchanged, and a useful full-pouch cue appears. At 7/10, harvest reaches 10 exactly. The 40 cap is tested with a temporary silo fixture or equivalent pure-sim setup, not advertised as playable.
4. Depositing five units of a species into an empty bin reserve stores five and earns zero. Depositing another eight stores five and sells three. Depositing or machine-delivering another unit sells one. Other species have independent reserves. An egg sale retains its current economics without entering crop reserve.
5. A player can open the bin with an empty pouch, take reserve stock back through its interface within that species' carry cap, then plant it. The same sequence survives save/load and action replay. No invisible direct mutation in UI; deposit and withdrawal do not advance time or cost energy.
6. A pre-v5 save with both seed and crop stock loads the sum of plantable counts without loss, even above the new cap; future harvests refuse until room exists. Eggs, scarecrows, and nonzero legacy pending `shipping_bin` sales also survive with their old behavior.
7. A machine harvest carries three counted units and delivers all three through the bin allocator; old one-unit hand state loads as one. A real-scene integration test reaches deposit, withdrawal, planting, and full-pouch refusal by simulated input, not by calling only the renderer. Existing robot session and replay still pass or any intentional fixture change is documented.
8. Design docs accurately state the three rulings and mark them `[Playtest]`. HQ cards remain open until this is actually landed and verified.
9. Tests exercise cap boundaries for the future 40-capacity silo at 37/38 carried stock (three-unit harvest all-or-nothing), a real-scene deposit that sells excess after the reserve reaches ten, and the actual visible full-pouch refusal cue. Do not count trace-only refusals as UI coverage.

Verification before landing: Godot import if assets changed; headless unit suite; full integration suite; robot session; benchmark; `python3 tools/check_gateway.py`; any relevant writing check. Record exact pass/fail counts and logs. Do not push or close cards on a partial run.

## 5. Execution status

- 2026-09-23: Daniel settled Q-113, Q-115, Q-116 in HQ. Old candidate remains held and unapplied.
- 2026-09-23: Read-only survey completed against main `68a8a0f`. Independent review found seven gaps; all folded into sections 3–4 before implementation.
- 2026-09-23: First worker commit `2e12e52` passed its suites. Independent diff review found shop-cap and “last deposit” truth defects plus three coverage gaps. These are required before landing.
- 2026-09-23: Correction `144d8bf` resolved those findings, but a second review found the shop's English-only “Pouch full” label violates its existing pre-reader UI pattern. Require a visual cue and a test of the live failed-press state.

# First two robot unlocks — implementation plan

## Ground rules

- The design is `design/06-bots-and-training.md`, “Earning the first two robots” (Q-88). S-12 keeps shop purchases after a proof opens each card.
- All world changes run through `SimWorld.apply_action`. Save and replay must give the same shelf. Shop display and purchase use the same `SimWorld.offers` answer.
- Preserve the player's existing saves and the work already in this shared checkout. Add only focused tests that exercise the proof, save/load, and purchase guard; then run both full suites.

## Findings from read-only survey (2026-09-23)

| Fact | Source |
|---|---|
| SimWorld already keeps latched rungs and provides the shop offer guard | `systems/sim/sim_world.gd:190`, `:450`, `:2464` |
| The shop draws its cards from that offer guard | `ui/menus.gd:1178-1201` |
| The first two robot catalogue rows have no earned requirement yet | `systems/machine_defs.gd:196`, `:214` |
| Successful player actions finish in the gateway; day turn is available for counter reset | `systems/sim/sim_world.gd:2387-2410`, `:3000-3006`, `:3452` |
| Mark-1 dispatch targets taught tiles; the taught list has a query | `systems/sim/brains/bot_brain.gd:587-634`, `:718` |
| Saves already persist rungs but need the daily tally and old-owner migration | `systems/sim/save_game.gd:94`, `:294`, `:320-340`, `:372` |
| Restore loads rungs before actors and crate inventory; ownership migration belongs after both. A save can have existing upper rungs but lack the two new flags | `systems/sim/save_game.gd:310`, `:332`, `:372` |
| Species fallback calls a model-less bot Mk I; migration needs explicit robot model | `systems/sim/sim_world.gd:2055`, `systems/machine_defs.gd:373` |
| The gateway accepts both empty and `player` actor IDs as the player | `systems/sim/sim_world.gd:1609-1612` |
| Old robot ownership can also be stored as a boxed snapshot | `systems/sim/save_game.gd:186-198`, `:372-373` |
| Current Mk I/Mk II shop pictures are idle robot frames | `systems/machine_defs.gd:207-210`, `:234-236` |
| A direct water Action can return `ok` yet leave a tile unchanged; the router normally filters it out | `systems/sim/sim_world.gd:1466-1477`, `:3169-3220`, `systems/action_router.gd:343-346` |
| Existing robot tests assume open day-one offers | `tests/test_runner.gd:11188`, `:11818`, `:13719-13876` |

## Decisions

- `RUNG_MK1_EARNED = "mk1_earned"` and `RUNG_MK2_EARNED = "mk2_earned"` are permanent world flags, separate from the existing upper rungs.
- `player_water_actions_today` is a nonnegative world integer, saved and reset only at day turn. A successful `_is_player(actor)` `water` Action that actually wets a previously dry, wettable tile increments it once even when the energy meter is already at zero. At 11, earn Mk I. A direct/replayed no-op `water` must not count even if the current gateway reports `ok`.
- A successful `water` or `till` Action from a placed Mk I on one of its taught tiles earns Mk II. Identify Mk I by explicit `extra.model == "bot_mk1"`, and require the target in `BotBrain.orders_of(extra)`. Water must actually wet a previously dry, wettable tile; till must change ground. Failed and no-op rounds do not earn it.
- Both robot catalogue rows stay in `ORDER` at 150g and 400g. Before proof their cards are locked; after proof the existing `buy_machine` path handles payment and crate placement. A save that already owns Mk I earns Mk I; one that owns Mk II earns both, including robots in the crate, boxed snapshots, or yard. Reconcile ownership after restoring all three, even when the save already has a `rungs` field; use explicit model to identify placed robots. An existing upper rung implies the lower rungs. Keep migration idempotent for replay.
- Use existing shop art to pair the relevant robot with a watering cue or worked-tile cue on its locked card, and give an unobtrusive unlock cue when the action fires. New art generation is outside this implementation.
- If a save has already bought a higher rung of the ladder, preserve its purchase access. Never make an existing owner lose shop access during migration.

## Work item

The first implementation worker owns the sim, catalogue, save migration, focused tests, fixture updates, and shop presentation. A second worker closes presentation findings after review. Each uses an isolated worktree, commits on its branch, and does not push.

Acceptance: 10 player waters in one day leave Mk I locked; the 11th opens it; sleep clears an incomplete tally; machine and rain water do not count. Direct no-op water on already wet ground does not count. Buying/placing/teaching Mk I leaves Mk II locked; a completed taught water or till opens it. Direct purchase fails before proof and succeeds at the catalogue price after proof. Both unlocks persist through save/load and replay, and old ownership migrates. Locked cards show the proof's work using existing art; the action that earns a robot gives an unobtrusive cue. Full unit and integration suites pass. Do not loosen assertions to make them pass; report measurements and plan mistakes.

Presentation follow-up from code review: consume `result.unlocked` at the existing player-visible action presentation seam, so the moment of work draws attention to the new shop card without interrupting play. The locked Mk II card must show a working Mk I, not Mk II beside a wheat packet. Use existing art. Verify the cue from both a player water Action and a robot's completed taught Action. Do not change unlock rules.

## Execution status

- 2026-09-23: read-only survey and independent review complete; five gaps corrected before implementation.
- 2026-09-23: first worker committed `baabd9b` in an isolated checkout. Reported unit 2,871/0, integration 977/0, gateway passed. Read-only code review found two presentation gaps; the second worker took them.
- 2026-09-23: second worker committed `5f341bf`; both patches are in the shared checkout. Verified there: unit 2,877/0, integration 980/0, gateway passed, end-to-end robot session replay matched its autosave. The shared checkout also contains unrelated uncommitted work, preserved during the merge.
- 2026-09-23: implementation committed on the shared branch as `df5fc46`, with only the nine worker-touched code files staged. The earlier plan and design commit is `d930dce`.
- 2026-09-23: cherry-picked onto GitHub main at `f2e821a`, `35714f2`, `b82fb20`; mainline verification passed unit 2,937/0, integration 1,008/0, gateway, and end-to-end replay. Pushed as a fast-forward update.

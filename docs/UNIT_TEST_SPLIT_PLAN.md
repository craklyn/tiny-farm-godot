# Split the unit tests by engineering area

`tests/test_runner.gd` is 18,946 lines. It contains 144 top-level test functions,
the process entry point, assertion accounting, and fixtures shared across unrelated
systems. A worker changing one system therefore has to read the tests for every
system.

The current entry point makes 135 explicit test calls. `test_barn_simulation()`
then makes nine barn subtest calls, so all 144 test functions run exactly once.
The baseline command completed with 3,365 passed assertions and no failures on
2026-10-09.

The implemented split leaves the command, test order, assertion text, exit status,
and final summary unchanged. It changes only where the existing tests live.

## Current sections

The file already has eight contiguous chapters. The boundaries below follow the
current helpers and comments rather than dividing a test body.

| Current lines | Lines | Tests | Area |
|---|---:|---:|---|
| 1–282 | 282 | — | Process entry point, shared constants, assertion accounting |
| 283–1,060 | 778 | 14 | Core data, input, routing, random numbers, and basic simulation actions |
| 1,061–1,440 | 380 | 7 | Saves and replay basics |
| 1,441–5,454 | 4,014 | 46 | Homestead progression, teaching, economy, crow story, and session analysis |
| 5,455–9,689 | 4,235 | 14 | Actor brains, movement, ecology, and bot behavior |
| 9,690–11,034 | 1,345 | 13 | Farm and actor presentation, yard generation, and soil behavior |
| 11,035–15,025 | 3,991 | 18 | Machines, Mark I and Mark III robots, learning, and the workbench |
| 15,026–18,143 | 3,118 | 21 | World pages, rooms, fences, saves, robot upgrades, and inventories |
| 18,144–18,946 | 803 | 11 | Industrial barn and room-edge behavior |

The largest source chapter was 4,235 lines, 22% of the former file. Extracting
shared helpers reduced every area file further; the largest resulting area file
is under 4,000 lines.

## Proposed files

Keep `tests/test_runner.gd` as the only `SceneTree` script and the only code that
prints `Results:`. Move each current chapter into one script under `tests/unit/`:

| File | Tests it owns |
|---|---|
| `tests/unit/core_tests.gd` | Core data, player and farm basics, pathfinding, input, routing, random numbers, milestones, weather, and basic actions |
| `tests/unit/persistence_tests.gd` | Save, interrupted-write, slot, migration, replay-from-save, and replay-flush tests |
| `tests/unit/homestead_tests.gd` | Phase-one progression, teaching, economy, crow story, trace analysis, parcels, tools, energy, clock, and pre-M1.5 compatibility |
| `tests/unit/actor_tests.gd` | `LiveSession`, brains, movement identity, scent, pests, animals, and bot behavior |
| `tests/unit/presentation_tests.gd` | Cot, crop, home, yard, station, world tint, zoo, soil, and parcel-introduction presentation |
| `tests/unit/automation_tests.gd` | Machines, Mark I, Mark III, policy, learning, workbench simulation, unlocks, upgrades, and training measurements |
| `tests/unit/interior_tests.gd` | World pages, fences, doors, windows, coop and tower interiors, inventory limits, assigned tiles, and the workbench shelf |
| `tests/unit/barn_tests.gd` | Industrial barn simulation, acquisition, saves, gateway refusals, cows, migration, and room-edge drawing |

`tests/unit/test_area.gd` is a `RefCounted` base used by all eight area scripts. It
owns assertion accounting and every helper used by more than one area. Tests call
the base class's `_assert` method; they do not print their own summary.

The shared base also owns the existing fixtures and private helper functions. This
keeps area scripts independent: no area file must preload another area merely to
use a fixture. Test bodies remain in their owning area files.

## Runner contract

`tests/test_runner.gd` preloads the eight area scripts, instantiates them, makes
the same 135 ordered calls, and aggregates their counts and failure messages. It
retains the existing heading, the single final line in this exact shape, and the
current nonzero exit on failure:

```text
Results: <passed> PASSED, <failed> FAILED
```

`tools/run_godot_test.py`, HQ verification, and CI all parse that line. No area
script may print another line beginning with `Results:`.

The runner order follows the current calls, not the physical order of functions in
the monolith. Near the end, that means it runs the interior group through
`test_one_pouch()`, the barn simulation and its nine subtests, the rest of the
interior group through `test_farm_page_draw_order_merge()`, and finally the barn
room-edge test. The interior and barn objects remain alive across those calls so
this interleaving does not require duplicate fixtures or reordered tests.

The split must also retain these behavior contracts:

1. Run every existing test once, in the current order. `test_barn_simulation`
   currently calls all nine barn subtests; preserve those call relationships rather
   than adding separate runner calls.
2. Create fresh area objects for a run. Do not share mutable fixtures or random
   state between area scripts beyond the same deliberate global state used today.
3. Keep every world mutation in test scenarios on its present path. Moving a test
   must not replace an action-gateway call with direct simulation mutation.
4. Keep replay comparisons and seeds byte-for-byte equivalent. File movement does
   not justify updating expected state, recorded sessions, or random seeds.
5. Keep the existing shell command and `res://tests/test_runner.gd` entry point so
   CI and local tools require no command change.

## Implementation checks

Before moving code, save the current ordered list of 135 direct test calls. The
baseline pass total is 3,365. After the split:

1. Compare the runner's ordered call inventory with the baseline: no missing,
   added, duplicated, or reordered call.
2. Run the unit test command and require the same pass total, zero failures, one
   `Results:` line, and exit status 0.
3. Run `python3 tools/check_gateway.py`; test movement must not conceal a gateway
   violation.
4. Run the integration and robot-session commands because the shared autoloads and
   replay state are exercised in the same Godot project process.
5. Update `CLAUDE.md` only after the new paths exist. Its test note should direct a
   contributor to add a function and its call in the matching `tests/unit/*_tests.gd`
   file, and should continue to say that running the complete unit test command is
   normal.

## Completed verification

The final candidate completed these checks on 2026-10-09:

- A normalized function-body comparison read the original monolith from
  `HEAD:tests/test_runner.gd` and all eight `tests/unit/*_tests.gd` files. It found
  144 original and 144 extracted `test_*` bodies, with no missing, added, or
  changed bodies.
- `python3 tools/run_godot_test.py -- godot --headless --path .
  res://tools/test_runner.tscn` completed alone with 1,274 passed assertions, no
  failures, and exit status 0.
- `python3 tools/run_godot_test.py -- godot --headless --path .
  res://tools/robot_session.tscn` completed with a replay match across 696 entries
  and 4,770 ticks, printed `Results: PASSED`, and exited with status 0.

One earlier integration run overlapped the robot-session run in the same project.
It completed with 1,271 passed assertions and three failures in the late barn tap
scenario. The required isolated integration run above passed all 1,274 assertions;
the overlapping run is not the landing result.

# Replay brain-decision record sizing

Every clock-driven brain can return no Action after changing replay-relevant state:

- The hen changes its route, position, idle timing, and shelter plan.
- The crow changes its flight position, visit state, and departure reason.
- The ant scout and ant forager change their route, position, trail state, and
  presence in the world.
- The rabbit and kangaroo change their route, position, feeding state, and fleeing
  state.
- The songbird changes its flight position, perch target, and perch timing.
- The mole changes its tunnel route, position, target, and visit state.
- The worm changes its route, body position, detours, target, and visit state.
- Robots configured for orders, following, circling, shooing, or learning change
  their route, position, work index, target, learning state, or retry timing. An
  idle robot changes only its next wake time, which is excluded from comparison.
- The cow changes its route, position, stall stage, and retry state.

The neighbour is not clock-driven. Her empty result ends the opening without
changing state. The sprinkler only emits Actions during the day turn. Player
decisions are already recorded as Actions.

## Observed fixed-session records

`tools/measure_brain_decision_records.gd` executes the real `SimWorld` clock and
the registered brain for each row. It applies the recording predicate to every
returned decision: the decision emitted no Action, and its before/after actor
rows differ after the scheduling-only `wake` field is removed. Each accepted
decision is passed to `ReplayLog.record_brain_decision`; the byte count is the
resulting JSONL entry plus its newline.

The deterministic scenario gives resident animals and each robot configuration
five active minutes and each visiting animal one minute. Each animal is isolated
on the same cleared farm with six reachable wheat crops. The ant forager also
gets a ten-tile scent trail. The cow gets a working industrial barn. The orders
robot gets four taught tiles and is sent on its round; the player stands on the
farm so every robot is awake. These are controlled active windows, not a claim
about how often optional visitors or unreleased robots occur in a shipping
session.

| Brain or configuration | Observed decisions | Observed JSONL bytes | Observed JSONL KiB |
|---|---:|---:|---:|
| Hen | 325 | 50,576 | 49.39 |
| Crow | 77 | 12,279 | 11.99 |
| Ant scout | 27 | 4,447 | 4.34 |
| Ant forager | 10 | 1,664 | 1.63 |
| Rabbit | 31 | 5,001 | 4.88 |
| Kangaroo | 52 | 8,502 | 8.30 |
| Songbird | 262 | 42,892 | 41.89 |
| Mole | 1 | 158 | 0.15 |
| Worm | 22 | 3,515 | 3.43 |
| Robot: orders | 7 | 1,097 | 1.07 |
| Robot: idle | 0 | 0 | 0.00 |
| Robot: follow | 18 | 2,824 | 2.76 |
| Robot: circle | 600 | 95,178 | 92.95 |
| Robot: shoo | 599 | 93,821 | 91.62 |
| Robot: learn | 50 | 7,844 | 7.66 |
| Cow | 16 | 2,529 | 2.47 |
| **Total** | **2,097** | **332,327** | **324.54** |

The total describes this deliberately crowded set of isolated active windows;
it is useful for comparing implementations, not as a forecast of a normal
player session. The shipping game currently schedules none of the optional
bestiary visits and does not make robots available.

## Conservative upper-bound model

The Python calculation is an upper-bound model for one 20-minute session at 10 simulation ticks per
second. The hen, one cow, and one robot of each configuration spend five minutes
changing state. Each visiting species spends one 60-second visit changing state.
All measured windows start at tick 6,000, halfway through the session. This fixes
the number of decimal tick digits in every record without assuming that all actors
start moving when the session starts.

Movement changes comparable state once per movement step. Ground-movement step
intervals come from `Movement.ticks_per_tile`: hen and cow 8 ticks, ant scout 16,
ant forager 20, rabbit 5, kangaroo 4, mole 8, worm 27, and robot 5. The crow and
songbird change continuous flight state every tick. Counts round up when a window
ends between steps. This is why the rabbit has exactly 120 decisions and the worm
has 23.

Unlike the observed run above, this calculation assumes every scheduled movement
interval produces a changed no-Action decision. It does not execute a brain and
therefore does not exclude intervals that emit Actions or leave comparable state
unchanged. Each hypothetical JSONL line has
the five fields written by `ReplayLog.record_brain_decision`, a 64-character SHA-256
fingerprint, the actor identifier shown by the calculation, compact JSON separators,
and one newline.

| Brain or configuration | Added decisions | Added JSONL bytes | Added JSONL KiB |
|---|---:|---:|---:|
| Hen | 375 | 58,500 | 57.13 |
| Crow | 600 | 91,800 | 89.65 |
| Ant scout | 38 | 6,004 | 5.86 |
| Ant forager | 30 | 4,800 | 4.69 |
| Rabbit | 120 | 18,600 | 18.16 |
| Kangaroo | 150 | 23,550 | 23.00 |
| Songbird | 600 | 94,200 | 91.99 |
| Mole | 75 | 11,475 | 11.21 |
| Worm | 23 | 3,519 | 3.44 |
| Robot: orders | 600 | 95,400 | 93.16 |
| Robot: idle | 0 | 0 | 0.00 |
| Robot: follow | 600 | 95,400 | 93.16 |
| Robot: circle | 600 | 95,400 | 93.16 |
| Robot: shoo | 600 | 94,200 | 91.99 |
| Robot: learn | 600 | 94,800 | 92.58 |
| Cow | 375 | 57,000 | 55.66 |
| Neighbour | 0 | 0 | 0.00 |
| Sprinkler | 0 | 0 | 0.00 |
| **Total** | **5,386** | **844,648** | **824.85** |

The total is the direct sum of the displayed rows. Actor identifiers affect the
size by one byte per character per record, so a generated identifier longer than
the fixed identifier in the calculation adds that length difference once per
record.

## Reproduction

Run the observed scenario twice from the repository root. The two completed runs
on 2026-10-08 returned the same per-row values and total:

```text
$ godot --headless --path . --script res://tools/measure_brain_decision_records.gd
actor  decisions  bytes
Hen  325  50576
Crow  77  12279
Ant scout  27  4447
Ant forager  10  1664
Rabbit  31  5001
Kangaroo  52  8502
Songbird  262  42892
Mole  1  158
Worm  22  3515
Robot: orders  7  1097
Robot: idle  0  0
Robot: follow  18  2824
Robot: circle  600  95178
Robot: shoo  599  93821
Robot: learn  50  7844
Cow  16  2529
TOTAL  2097  332327
```

The older Python command remains as the explicitly labeled conservative model:

```text
$ python3 tools/measure_brain_decision_records.py
UPPER-BOUND MODEL; this does not execute brain steps
actor  decisions  bytes
Hen  375  58500
Crow  600  91800
Ant scout  38  6004
Ant forager  30  4800
Rabbit  120  18600
Kangaroo  150  23550
Songbird  600  94200
Mole  75  11475
Worm  23  3519
Robot: orders  600  95400
Robot: idle  0  0
Robot: follow  600  95400
Robot: circle  600  95400
Robot: shoo  600  94200
Robot: learn  600  94800
Cow  375  57000
Neighbour  0  0
Sprinkler  0  0
TOTAL  5386  844648
SHA256  4db0e177331f9f1520723a9990a702f4734106ef3c74e4151e2cfa7e48a3e643

$ python3 tools/measure_brain_decision_records.py
UPPER-BOUND MODEL; this does not execute brain steps
actor  decisions  bytes
Hen  375  58500
Crow  600  91800
Ant scout  38  6004
Ant forager  30  4800
Rabbit  120  18600
Kangaroo  150  23550
Songbird  600  94200
Mole  75  11475
Worm  23  3519
Robot: orders  600  95400
Robot: idle  0  0
Robot: follow  600  95400
Robot: circle  600  95400
Robot: shoo  600  94200
Robot: learn  600  94800
Cow  375  57000
Neighbour  0  0
Sprinkler  0  0
TOTAL  5386  844648
SHA256  4db0e177331f9f1520723a9990a702f4734106ef3c74e4151e2cfa7e48a3e643
```

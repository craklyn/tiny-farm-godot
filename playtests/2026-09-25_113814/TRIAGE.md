# Manual triage, 2026-09-25 — replay MISMATCH, installed over deliberately

Checked under its exact recording build (a04429a, clean) with
`tools/verify_replay.gd`:

    MISMATCH: recomputation diverged from the recording.
    entry 653: recorded @58205 {actor=bot_mk3,seed_type=tomato,target=12,8,verb=plant},
               recomputed @58175 {actor=bot_mk3,target=10,9,verb=till}

The Mark III's recomputed brain chose differently from the live one — a
determinism break in the sim, not damage to the farm. The autosave on the
tablet is untouched by an install, and all three files are kept here.

`verification.sha256` beside this note is therefore a triage receipt, not a
passed verification: it lets the deploy install today's build (Daniel was
blocked on the Spiral Tower having no way in) without re-litigating this
session. The divergence is filed as its own follow-up.

## Resolved the same day — the checker was wrong, not the robot

The robot's brain never diverged. Stepped through by hand under a04429a, the
recomputed Mark III does exactly what the live one did: it tills its own stall
floor at @58175 and @58185, is refused both times ("occupied" — the stall wins
over the soil), and plants the tomato on 12,8 at @58205. `session_trace.jsonl`
shows the same two refusals from the tablet.

The mismatch came from the comparison. The game records only the actions the
gateway accepted, but the replay compared that recording against every action
a brain *attempted*, refusals included. So the first refused brain action in any
session read as a desync. `ReplayLog._collect` now leaves refusals out of the
comparison (they still run during the replay, so the robot's own bookkeeping
stays in step), and `test_refused_brain_action_replays` rebuilds this farm in
miniature. That test fails without the fix.

With only that change applied to a04429a, `tools/verify_replay.gd` on this
session reports **MATCH: replay reproduces the autosave state exactly**. The
recording itself was sound, and nothing in it needed to change.

## Later the same day — the robot no longer tills its stall floor

The refusals themselves are gone. The Mark III's square scan, and her own tap,
now skip a building's floor before consulting the tool table, which is the rule
the gateway already applied (`test_stall_floor_is_not_ground`). Two consequences
for this folder:

- Replay this session under its recording build (a04429a plus the checker fix),
  not a newer one. From this change on, the recomputed robot never makes those
  two refused tills, so its later choices differ from the recording.
- `test_refused_brain_action_replays` no longer produces a refusal, because the
  robot is no longer refused. It now checks that this farm replays with no
  refusals, and checks the checker's rule on a hand-built list.

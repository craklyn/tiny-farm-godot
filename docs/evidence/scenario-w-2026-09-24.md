Research report · Tiny Farm Godot
# Scenario W weather verification

Date: 2026-09-24

Status: FINAL

Last updated: 2026-09-24

Repo/location: `docs/evidence/scenario-w-2026-09-24.*`

## Background & motivation

Scenario W previously depended on a weather roll from the shared seeded stream. Actor draws between the start of a frame and the cot tap could change that stream's position. The held candidate had passed ten earlier integration runs, but that evidence covered an older source tree. This record qualifies the reconciled weather patch against main commit `3e49aeba8806083c9187220063003ef13bd0d214`.[^card]

## Context and method

Godot 4.7.2 ran in the isolated worktree. The weather patch derives the next day's rain result from `SimRng.stateless(day, 9000)` and keeps the 20% threshold. Each integration process used `tools/run_godot_test.py`, which assigns a fresh `XDG_DATA_HOME`. A run counted only when its child process exited zero and its output contained one final `Results: N PASSED, 0 FAILED` line. Scenario W counted as a pass only when its exact tap-time weather assertion appeared once. The command, patch hash, per-run exit codes, and SHA-256 log hashes are in the JSON record.[^data]

The first parallel retry was interrupted. A later ten-run parent command returned 143 after writing its tenth child's output. Its tenth result is excluded from the count to avoid relying on the parent command's ambiguous exit. A separate tenth suite finished with exit zero and supplies run 10 in the archived logs.[^data]

## Findings

Ten completed integration suites passed, each with 999 passed assertions and zero failed. Scenario W passed 10 times and failed zero. The unit suite passed 2,951 assertions with zero failed. The robot session replay matched its autosave. The benchmark, gateway check, and demo replay generator passed; the regenerated replay fixture had no diff.[^data][^checks]

## Conclusion

The day-keyed weather patch satisfies the local repeat-run criterion on the reconciled game tree. This is a local verification result; it does not assert that GitHub CI has run on the eventual pushed commit.[^data]

## Next steps

Fast-forward the patch onto current main, push it, and inspect the CI run for that exact commit. Update the live HQ card only with landing and CI evidence that actually exists.

[^card]: Live HQ card `w0f78d0a7d2d`; prior candidate evidence is retained in the HQ data store.
[^data]: `docs/evidence/scenario-w-2026-09-24.json`; full raw outputs are in `docs/evidence/scenario-w-2026-09-24-logs.tar.gz`.
[^checks]: Local logs: `/tmp/scenario-w-rebase-unit.log`, `/tmp/scenario-w-rebase-robot.log`, `/tmp/scenario-w-rebase-benchmark.log`, `/tmp/scenario-w-rebase-gateway.log`, and `/tmp/scenario-w-rebase-demo.log` on the verification host.

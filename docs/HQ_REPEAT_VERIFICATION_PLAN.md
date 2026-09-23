# Verify repeated tests without rerunning the worker

Date: 2026-09-22
Status: implementation in progress
Owner: Chief of Staff

## Ground rules

- A timed-out or interrupted suite is not a completed pass or failure.
- All Godot checks use a fresh `user://` directory. Their reported outcome must
  come from a parsed `Results: N PASSED, 0 FAILED` line, not merely a zero
  process exit. Keep timeout/failure logs outside the temporary user data.
- Evidence belongs to the exact candidate patch/tree. Never convert an old
  review to a pass without a new check of that evidence.
- A held patch must not overwrite unrelated working-tree edits. No model call is
  needed merely to run the same unchanged patch through longer verification.

## Findings

| Fact | Source |
| --- | --- |
| Both candidate and landing suites use `run_suites`; it launches raw Godot once with a 900-second timeout. | `hq/drain.py:866-871`, `hq/drain.py:1191-1210`, `hq/drain.py:1769` |
| The existing wrapper isolates `user://` under a temporary `XDG_DATA_HOME`, bounds runtime, and waits briefly after a result line. | `tools/run_godot_test.py:1-100` |
| The integration suite explicitly rejects another session's autosave. | `tools/test_runner.gd:31` |
| The queue keeps a rejected patch and can replay it into a fresh worktree. | `hq/drain.py:675-756` |
| Candidate identity and suite results are already tied to the recorded candidate. | `hq/drain.py:795-871`, `hq/drain.py:1327-1353` |
| A failed review queues one worker repair, even if the sole gap is verification; dirty overlapping files park the item. | `hq/work.py:699-715`, `hq/drain.py:1017-1127`, `hq/drain.py:1660-1688` |

## Interfaces and decisions

1. `run_suites(cwd=REPO)` keeps its existing return shape, but invokes each
   Godot command via `tools/run_godot_test.py` so every suite uses private user
   data. Require the suite result line; missing or timed-out results fail.
2. Provide an explicit evidence-only command for a selected held work item.
   It must refuse cards without a saved patch, use a fresh worktree at the
   recorded candidate base, apply the saved patch, and check the patch hash and
   changed-file blobs against the recorded candidate. A different base or
   changed patch is stale and requires renewed review. For the selected card it
   runs ten integration suites, records each completed Scenario W outcome and
   the total count, and retains logs and machine-readable evidence. Killed
   attempts never count as passes.
3. The evidence-only command does not summon a worker, alter Grace's previous
   `unfinished` outcome, apply the patch to the shared tree, or mark the card
   complete. It records evidence for a subsequent fresh review. Only after
   that review and today's ordinary suites may the normal landing transaction
   be used; `--apply` is not a substitute because it bypasses those gates.
4. Apply this to `w0f78d0a7d2d`: keep `state: waiting_session` but add a
   precise `repair_hold` for the evidence-only verification. The existing
   queue excludes held cards from worker dispatch and Daniel's decision queue,
   even after its separate dirty-file hold clears. Preserve the patch, prior
   attempt, and existing dirty-file hold; reload the card before writing so
   its revision check catches concurrent changes.
   Do not mark the weather change shipped before the ten-run and normal gates
   actually pass.

## Acceptance

- Tests prove isolated user data, honest timeout/result parsing, exact counts,
  unchanged-patch identity, and no worker call on evidence-only verification.
- The card shows one named next action and owner; no false completion or green.
- Unit, integration, and gateway checks pass for any landed game patch. A failed
  check remains attached as evidence rather than erased by a retry.

## Execution status

- 2026-09-22: read-only survey and adversarial plan review completed; the plan
  now accounts for the unfinished prior outcome, a stale candidate base,
  missing-result parsing, and worker-queue reentry risk.
- 2026-09-22: isolated suite runner and evidence-only command landed locally.
  The first real canary exposed a missing Godot import and slow, incomplete
  runs; import preflight, per-run progress, durable partial evidence, fail-fast,
  and process-group cleanup are now covered by 14 focused tests. Ten completed
  integration runs on Grace's unchanged saved candidate each passed Scenario W
  (969 passed, zero failed per run); evidence is under
  `hq/data/runs/verification/w0f78d0a7d2d-nitaquqf/`.
- 2026-09-22: the card is held for Adam, not requeued to Grace or put before
  Daniel. Its patch still overlaps unsaved save-lineage edits in the shared
  checkout. Reconcile those edits, then rerun tests and independent review on
  the exact combined candidate before landing; the ten passes above do not
  prove that combined change. Pushing local commits to origin was blocked by
  the environment's external-write approval rule.

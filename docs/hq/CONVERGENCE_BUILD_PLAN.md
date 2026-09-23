# Build the finish line for studio work

Date: 2026-09-22
Status: LIVING
Last updated: 2026-09-22
Owner: Chief of Staff
Design: `docs/hq/CONVERGENCE_QUEUE_DESIGN.md`

## Outcome and boundary

Build the narrow convergence spine, then run the held weather fix (`w0f78d0a7d2d`) through it as a live canary. A worker's finished session must become either (a) a candidate verified against prospective current main and safely landed, or (b) one owned, runnable recovery action with an explicit blocker/wake condition. Do not rewrite HQ wholesale or alter unrelated game work.

Current user checkout is dirty across many paths, including the weather patch's files. Every existing edit belongs to its current author. Never stash, reset, overwrite, stage, or commit those edits as part of integration. A weather canary that safely stops at an explicit blocker is better than a forced green, though the goal is to reconcile and ship if the evidence supports it.

## Ground rules

- `docs/DECISION_LOG.md` S-16/S-17 still govern autonomous landings and Daniel's inbox. Tier-2 decisions stay with Daniel. The Q-4 straight-to-main rule permits a branch/PR process once concurrent code is risky; this build records the narrow process change here rather than modifying the dirty ruling file.
- One source of truth for eligibility: the scheduler, queue API, work card, Bullpen, and dashboard read one projection. Reads do not write cards, change revisions, or refresh an “observed at” timestamp.
- A session, review, candidate, verification, integration, and CI outcome are distinct records. “Running” requires a live claimed session. “Landed” requires the exact checked prospective tree and a commit; “CI confirmed” requires a matching CI run.
- Candidate/content/evidence IDs are immutable. A changed base produces a new candidate and new checks. Existing evidence remains visible but is labeled stale for the new base.
- Only one integration writer advances main. **Local `refs/heads/main` is authoritative until an explicit push/sync policy is adopted; `origin/main` is not silently substituted.** The writer operates in a clean isolated checkout, never in Daniel's dirty worktree; never auto-stashes. A linked worktree cannot update `main` while the dirty checkout has that branch checked out. At cutover, first verify no other worker is using the checkout, create a named `codex/` branch at the identical HEAD for Daniel's existing dirty files, verify byte hashes and index state remain unchanged, then let the clean integration worktree own `main`. If that handoff is unsafe, persist a typed blocker and ask for the missing choice; do not force-update the branch or fall back to legacy `--apply`.
- Claims/retries are idempotent. A crashed worker or integration transaction recovers without duplicate actions or commits.
- No new “Needs you” for studio-owned code conflicts. Every nonterminal card has a critical next action or external wake event and accountable owner. Multiple independent actions may coexist.
- Preserve existing fields and revision CAS; add schema-versioned fields and migration compatibility. No second competing data store in this increment.
- Tests must exercise behavior and persisted state, not source strings. Do not loosen failing assertions to make a check green. Report any plan assumption that is wrong.

## Survey findings and seams

| Fact | Source |
|---|---|
| Cards have coarse states, newest-first listing, process lock, and revision CAS. | `hq/work.py:124-126`, `204-207`, `220-286` |
| Automatic repair caps at one and then records prose `repair_hold`. | `hq/work.py:698-718` |
| The queue selects unstarted `waiting_session`, excludes held states, then sorts resume → urgent → ordinary. The projection uses the same classifier. | `hq/drain.py:1682-1747` |
| `_parked_by_tree` compares a freshly timestamped `waiting_for` dict on every read, so a queue request may increment card revision. This was observed on the weather card during the survey. | `hq/drain.py:1134-1153`; `/api/execution/queue` at `hq/server.py:2194-2210` |
| Worker worktrees and candidate creation already exist; apply and land still use the shared checkout. Exact-base/blob and evidence checks are strong. | `hq/drain.py:647`, `793-875`, `1155-1215`, `1351-1470` |
| Weather card is `waiting_session`, its patch is not applied, and the 10/10 repeat runs are against the prior candidate/base. A four-file patch is saved. | `hq/data/work/w0f78d0a7d2d.json`; `hq/data/patches/w0f78d0a7d2d.patch` |
| Weather's latest owner attempt is unfinished; its old integration result was red. The overlapping save-lineage edits are uncommitted. The ten repeat passes are diagnostic evidence, not S-16 landing evidence or proof of the combined working tree. | Same card and patch; `hq/drain.py:1359-1402` |
| Saved patches are replaced on new attempts; an immutable candidate must preserve reconstructable patch content, not only a hash. | `hq/drain.py:682-693` |
| The queue endpoint's max-mtime cache misses dirty-tree changes and some card changes; workflow additions can perturb the instruction fingerprint unless excluded. Legacy `--apply` still touches the shared checkout. | `hq/server.py:2194-2210`; `hq/work.py:2129-2135`; `hq/drain.py:1934-1950` |
| Work/queue/Bullpen/dashboard each render state separately today. | `hq/static/work.js:220-240`, `360-365`, `875-980`; `hq/static/workers.js:20-35`, `135-187`, `257-274`; `hq/static/app.js:398-505` |
| Other raw-state consumers include “waiting on you,” dashboard counts, person plates, and queue composition. | `hq/server.py:613-645`, `5210`; `hq/static/app.js:662-704`; `hq/static/queue.js:251-275` |
| Holds also live outside `waiting_session`: at review, 21 of 64 `for_review` cards carried `repair_hold`. `/api/work` uses a raw snapshot and work detail builds a separate timeline. | `hq/work.py:1993-1996`; `hq/server.py:2544-2620` |
| Existing recovery and canary fixtures give bounded regression seams. | `hq/tests/test_completion_recovery.py:58-176`; `test_process_canary.py:109-220`; `test_repeat_verification.py:79-125` |

## Decisions and interfaces

1. Add a versioned `workflow` object to the existing work-card JSON. It holds append-only actions, immutable candidate/verification references, typed blockers, and integration transactions. Store immutable patch bodies under content-addressed artifact names before any new attempt can replace the legacy patch. Keep old fields readable until migration; one helper constructs a canonical `work_view(item, repo_facts, now)` with `phase`, `availability`, `next_action`, `blocker`, `last_moved`, `candidate_status`, and `shipped_evidence`. Exclude `workflow` from the instruction fingerprint so bookkeeping does not invalidate a candidate. Define exact names in code and tests; do not let each UI consumer independently infer them.
2. Make queue classification pure. Resolve Git/dirty-path facts separately from projection; do not call `save_item` in GET/list paths. Remove the endpoint's max-mtime cache or replace it with a key that includes every card revision and relevant Git state. If a blocker observation must be persisted, do so in an explicit transition, idempotently comparing stable cause and files while preserving first-seen time. The public queue result returns `working`, `eligible`, and `held`, with action ID, owner, age, and priority rationale. Ordinary items age; a reviewed reconciliation/integration action ranks ahead of new ordinary work, below main/CI emergencies.
3. Use a dedicated clean integration checkout under a configured HQ scratch location, never the shared user checkout. Prepare a candidate on latest local main plus earlier queued changes; rerun both suites and review over its exact tree; advance local main only with an exact expected parent. Do not bypass S-16's checker/risk bar. Report origin/main divergence explicitly; pushing is a distinct operation and outcome. Gate or retire legacy `--apply` so it cannot quietly bypass the clean lane. The branch handoff above is part of activation, not an assumed prerequisite already satisfied.
4. On conflict, stale base, missing evidence, tool failure, or lost lease, create/reuse one typed action with owner and idempotency key. Never automatically rerun the same old patch as though it were fresh. The weather action should say exactly which files/changes conflict and what candidate/evidence it will regenerate.
5. Default UI groups by work outcome, most recently updated first. An action view remains available. Show the true critical next action and owner, whether running or held, age, stale evidence, and why priority/position differs. Daniel's decision inbox stays separate. A seat name is accountability, not proof of an active agent.

## Work items, in dependency order

### A. Canonical workflow and pure queue projection

Own: `hq/work.py`, scheduler classification in `hq/drain.py`, queue and work API projections, Python tests. Introduce schema/versioned action and blocker helpers with stable IDs; preserve patch artifacts; build the canonical projection over all nonterminal states, including held `for_review` cards; remove read-side card writes and invalid cache (especially timestamp churn); add priority/aging and idempotent action claim/lease recovery. Keep legacy cards compatible. Acceptance: repeated queue GET/list leaves every card byte-for-byte and revision unchanged; a held weather-like item is excluded from eligible while its distinct reconciliation action is eligible; held review cards receive a real next action; one action is not duplicated across retries/reloads; scheduler, `/api/work`, detail, and queue API agree; adding workflow metadata does not change the instruction fingerprint.

### B. Clean integration lane and reconciliation

Own: new integration module and the landing path in `hq/drain.py`, plus recovery/process canary Python tests. Integrate A's data/projection contract, preserve the exact existing landing bar, and move preparation/tests/commit out of the dirty shared checkout. Never invoke legacy `--apply` for held weather. Implement the clean-main branch handoff with pre/post byte and index checks, only when the live checkout is idle; report origin divergence without auto-pushing. Acceptance: two stale-base candidates cannot both land on old evidence; a conflict creates an owned action; a clean rebased candidate is tested on prospective main and lands once; failed/incomplete checks leave main untouched; crash recovery is idempotent; dirty user files remain byte-identical. If local-main ownership cannot be safely transferred, make the lane stop truthfully at an explicit blocker rather than inventing a workaround.

### C. HQ presentation

Own: `hq/static/work.js`, `workers.js`, `app.js`, `queue.js` and their JS/browser tests, with minimal CSS/server rendering as needed. Render A's projection, do not recompute it in frontend prose. Include dashboard counts, person plates, and waiting-on-you filtering. Preserve grouped-by-work default with action timeline switch. Acceptance: held items say “blocked” with owner/next action, never “queued to run”; “running” requires active claim; reviewed/verified/landed/CI-confirmed are distinct; Daniel sees no code-conflict “Needs you”; links open evidence and the actual recovery action. Verify real browser behavior after server reload, including narrow width and keyboard where controls change.

### D. Live weather canary and closeout

After A–C land and HQ reloads, inspect weather patch and current dirty overlaps. The save-lineage edits are an external uncommitted dependency: do not declare a weather-only HEAD test to be reconciliation. Use the new path to create/reuse its reconciliation action; once those edits are committed or an owner explicitly supplies a reviewed snapshot, have Grace execute in isolation, obtain a **completed** new owner attempt and checker pass, rerun both suites on the prospective combined tree, and land only if S-16 and exact-base checks pass. Otherwise leave a precise owner/action/blocker, not generic repair_hold. Observe the Queue, card, and Bullpen after reload; record actual timestamps, candidate/tree IDs, result, and any remaining human decision. Do not treat 10/10 old-base reruns as new-base proof.

## Verification and execution status

- Run focused tests after each component, then all discovered HQ Python/JS tests, frontend static checks, both Godot suites in isolated user-data paths, and an offline end-to-end canary. Run actual browser interactions for changed controls. After integration, inspect `git diff` only for owned paths, check shared dirty-file hashes, and confirm persisted cards after restart.
- 2026-09-22 — Design committed as `d919d54`. Build survey complete. At start, five `pending_integration` rulings and 26 legacy drain-eligible cards were observed; they are unrelated and must not be silently folded into this process build. Shared checkout had 155 dirty paths. No production implementation has landed yet.

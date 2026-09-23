# A work system that finishes what it starts

Date: 2026-09-22
Status: DRAFT — proposed design
Last updated: 2026-09-22
Repo: Tiny Farm (`/home/daniel/dev/tiny-farm-godot`)
Owner: Chief of Staff; Engineering owns the integration lane, Rin owns the HQ presentation

## Recommendation in one minute

Build a **small convergence spine now, before the next unattended code-work batch**: a first-class reconciliation action, a single clean integration lane, and an honest queue projection. Do not spend another two days rebuilding HQ. Defer a database migration, predictive scheduling, and a broad visual redesign until **after the v0.2.1 Mark III release tag**, then judge them against measured flow. This is a design recommendation, not an implementation or a change to the current queue.

The current system is strong at protecting a candidate from unsafe landing, but weak at turning a protected hold into the next owned action. That is why a verified fix can sit still while new work starts. Reconciliation should usually outrank new work *when it unlocks already-checked value*, but a held card is not itself runnable; the dependency or integration action must become runnable. The system cannot promise that work is “always moving” when there is no capacity, a broken tool, or a real human decision. It can promise that every nonterminal item has a named critical next action or external wake event, an accountable owner, and visible age.

## Question, method, and current evidence

Question: how should Tiny Farm turn independent agent sessions into verified changes on one advancing codebase without making Daniel manage the collisions?

Method: read the queue, landing, card, and UI code; inspect the 2026-09-22 local queue projection; compare the design with official documentation for merge queues, merge trains, Kanban, and issue relationships. This is an architectural assessment, not a throughput experiment. The live counts below are a point-in-time observation and may change while the scheduler runs.

At inspection, `python3 hq/drain.py --list-json` projected **2 working, 27 eligible, and 16 held** items. The weather card `w0f78d0a7d2d` was held because `systems/game_state.gd` and `tests/test_runner.gd` had unsaved changes; the queue would not overwrite them. That protection is correct. What is missing is a separate, owned job to reconcile its checked candidate with the current tree. The scheduler's ordinary class runs newest first (`hq/drain.py:1682-1746`), so older non-urgent work has no aging protection.

Existing strengths should survive: isolated worker worktrees, card revision compare-and-swap (`hq/work.py:275`), exact candidate/evidence checks (`hq/drain.py:1351`), a guarded commit of only card-owned files (`hq/drain.py:1427`), and the S-16/S-17 rules that keep reversible work and unprepared questions off Daniel's desk (`docs/DECISION_LOG.md`, S-16 and S-17). The recent process stabilization also added a real end-to-end canary (`docs/hq/PROCESS_STABILIZATION_PLAN.md`).

The debt is in the joins between those strengths:

| Debt | Observed mechanism | Consequence |
|---|---|---|
| One overloaded card state | `waiting_session` can also carry `repair_hold`, `waiting_for`, or `pending_landing` (`hq/work.py:698`; `hq/drain.py:1682`); the work page calls it “queued for a build session” (`hq/static/work.js:361`). | A held result can look like work waiting for a worker. Eligibility must be inferred from flags and code path, not the visible label. |
| Shared mutable landing surface | Workers use worktrees, but `apply_patch` and `land` operate on the real working tree (`hq/drain.py:1150`, `1427`). Landing requires the checked base and file blobs still match. | Safety is good, but any intervening change can strand a valid candidate; many dirty files become a global integration bottleneck. |
| Holds are prose, not work | `_parked_by_tree` records file names/reason; `queue_one_repair` stops after one automatic retry with `repair_hold` (`hq/drain.py:1134`; `hq/work.py:698`). | A named person in a sentence is not a runnable, prioritized assignment with a completion contract. |
| Start order is not finish order | Retries then urgent items then newest ordinary work; no explicit integration/reconciliation class or WIP/aging policy (`hq/drain.py:1710-1746`). | New starts can outpace landings; old work may age invisibly. |
| Session, candidate, and shipment blur together | Attempts, check records, patch data, landing recovery, and item state coexist in a growing card record (`hq/work.py:2132`; `hq/drain.py:1302`). | UI can celebrate a finished session while the change is unmerged, and recovery logic is hard to reason about. |

These are deductions from the cited implementation and snapshot, not evidence that every held card is usable or that every unsaved file is a conflict. The weather candidate still needs review against current main; a repeated pass on its old base does not establish that it is ready to ship on a new base.

## What established systems teach us

- [GitHub's merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) and [GitLab's merge trains](https://docs.gitlab.com/ci/pipelines/merge_trains/) test a candidate combined with the latest target and earlier queued changes. If a candidate fails, it leaves the train and following candidates are rebuilt/retested. The valuable pattern is **test the exact prospective integrated tree**, not merely each independent patch. GitHub notes that jumping priority to the front rebuilds in-progress queue entries, so expedites have a real cost. Native GitHub merge queue eligibility is limited to organization-owned repositories under its stated plan conditions; it must not be assumed available here.
- The [Kanban Guide](https://kanbanguides.org/the-kanban-guide/) calls for explicit workflow policies, controlled work in progress, and measuring age, cycle time, throughput, and WIP. Applied here: count **landed outcomes**, not sessions or tokens, and stop opening more parallel code work when the integration lane is the bottleneck.
- [Linear's issue relationships](https://linear.app/docs/issue-relations) distinguish blocked/blocking dependencies and duplicates; its [triage workflow](https://linear.app/docs/triage) separates intake from committed work. Applied here: “blocked” is a typed relationship and recovery assignment, not another status label or a note Daniel must interpret.

The inference is not “install a large project-management suite.” Those systems split *intent*, *execution*, *dependency*, and *integration*; HQ should adopt the separation while retaining its small, local, source-derived form.

## Target model

Give each concept one identity and one authority. JSON files may remain the durable store for the first increment; a wholesale SQLite/event-sourcing migration is not required to obtain this model.

| Record | Stable identity and essential fields | Invariant |
|---|---|---|
| Work item | Outcome, accountable seat, risk tier, acceptance contract, release/gate, priority class, dependency IDs | A work item is not done because an agent session ended. The accountable seat remains named if execution is delegated. |
| Action | `type` (build, review, verify, reconcile, integrate, decide), owner seat, executor/engine if assigned, required input artifact IDs, next step, wake condition, timestamps, claim/lease ID and expiry | Every nonterminal item has a critical next action or external wake event; independent actions may run in parallel, but a held action is not eligible to run. |
| Attempt | Action ID, session ID, executor/model, start/end, result, log reference, cost | Append-only history. A review is an action, not an “attempt” at coding. |
| Candidate | Immutable artifact ID, base commit, content/tree hash, changed paths, source branch/patch, supersedes ID | A rebased or edited candidate gets a new ID. Old evidence remains attributable to the old candidate. |
| Verification | Candidate ID, **tested integrated tree hash**, environment/command, test results, reviewer verdict, evidence location, time | Green evidence is invalid for a different tree. Distinguish old-candidate passes from prospective-main passes. |
| Blocker | Typed cause (`code_conflict`, `stale_base`, `missing_evidence`, `dependency`, `tooling`, `capacity`, `human_decision`), owner, blocking relation, unblocking action ID, observed time | A blocker is either attached to a runnable recovery action or has an explicit external wake event. Only genuine design/risk decisions go to Daniel. |
| Integration transaction | Candidate ID, expected base, queue position, prepared tree, checks, commit/push result, final SHA | One writer advances main; a changed base forces reconstruct-and-reverify, never an unsafe reuse of old evidence. |

`work phase` (intake / ready / working / review / integration / done / cancelled) and `availability` (runnable / blocked / waiting-event) are separate dimensions. “Shipped” is derived from a landed commit and the appropriate CI/release evidence; a finished session is only activity. The event timeline records transitions and their causes, while the current view is a projection. For the first increment, add a schema-versioned `workflow` section and immutable child IDs to the existing card files, with one transition function and migration tests; preserve legacy fields read-only until migrated. If multi-record atomic updates and crash recovery remain complicated after the v0.2.1 release, evaluate SQLite with WAL and a one-way migration. Do not maintain JSON and SQLite as competing authorities.

### Scheduler and integration rules

1. Intake deduplicates by outcome, defines acceptance, dependency edges, risk tier, and a feasible next action. A tool/environment preflight precedes expensive work. The scheduler never spends a worker on an action already known to be blocked by the checkout or a missing capability. A claim uses an idempotency key and an expiring lease; on worker loss, recovery checks for a persisted candidate before retrying so it neither strands nor duplicates the action.
2. Parallel worker sessions may create candidates only in isolated worktrees/branches. Keep a small, explicit code-work WIP cap; start with at most **two** concurrent code-producing actions as a policy experiment, not a measured optimum. Review and non-code preparation may proceed independently.
3. A single integration lane owns a **clean, dedicated checkout or clone**, not Daniel's dirty working tree. It takes a reviewed candidate, reconstructs it on the latest main plus earlier queued integrations, runs the required suites against that exact tree, and advances main only if its expected parent still matches. A rejected push/base change requeues integration; it does not silently “land” a stale patch. Preserve post-push CI as a separate signal. Do not auto-stash or mutate Daniel's files.
4. If reconstruction conflicts, create or reuse one reconciliation action linked to the candidate and the blocking change. Supply both diffs, acceptance and prior evidence; assign the accountable engineering seat, with a reviewer. The output is a new candidate and fresh evidence. If no runnable solution exists, record a typed blocker and wake condition. Do not auto-retry the same failed patch indefinitely.
5. Priority is **main/CI red or release gate → reconciliation/integration of reviewed work → finish active WIP → new work**, with explicit age and dependency-unblocking value within a class. This is not a blanket preference for all “reconciliation” titles: obsolete or low-value candidates can be closed, and an unready reconciliation cannot jump the queue. Show any expedite and its displacement cost. Aging prevents the newest-first tail from starving.
6. When post-landing CI fails, make one urgent owned repair action linked to the offending commit and pause conflicting integration until main is recovered. A red build is not a fresh feature request or a Daniel decision by default.

The repository's Q-4 ruling permits branches/PRs “when code changes get risky” (`docs/DESIGNER_QUEUE.md:458`). Concurrent candidates and blocked landings are evidence that this condition now merits reconsideration. Record a focused process decision before moving main ownership to a dedicated integration checkout or remote merge lane. Prefer the simplest available implementation; do not move hosting providers or assume GitHub's native merge queue is available solely to acquire a queue.

### Presentation: one glance, truthful drill-down

The default HQ surface answers: **What shipped? What is moving? What is stuck, who owns the unblock, and do you need me?** Group all actions under one work outcome, ordered by most recently updated; retain a switch to an action-by-action timeline. A worker's build, Adam's review, and Engineering's reconciliation appear as distinct actions, not “attempt 1/2/3.”

Suggested compact work row:

> **Weather replay flake** · Reconciliation needed · Grace owns next action
>
> Candidate verified on old base; current main has overlapping edits. Next: rebuild it on latest main and rerun the suite. Waiting 12 hours.
>
> [Open work] [See blocker and evidence]

The top of the dashboard has only three studio bands: **landed since last visit**, **currently running / ready to integrate**, and **blocked with an owned next action**. Daniel's decision inbox is separate and contains only S-16/S-17-eligible asks. “Needs you” appears only if his actual judgment or authority is required. Queue rows show eligibility, priority reason, position, owner, and age. A held item never appears under “queued to run.” An owner seat is accountability and routing, **not proof a person or agent is presently working**; only a live claimed session earns “running.” Bullpen activity can show session and token detail, but the default status is about outcomes: session finished, review passed, candidate awaiting integration, landed, CI confirmed. Green is earned only at the relevant evidence boundary.

No timer or dashboard color should imply a worker is running when only the scheduler is enabled. If nothing can run, show “No runnable action” and the top blocking chain, rather than a reassuring idle green or a generic red.

## Delivery boundary and acceptance

**Immediate, narrow increment (before another unattended batch):** inventory current candidates and dirty-file ownership without changing or stashing them; introduce typed next actions/blockers and an explicit reconciliation priority; make queue/card/dashboard labels derive from the same eligibility projection; create a clean, single-writer integration lane after the focused Q-4 process ruling. Start with existing JSON plus schema/version tests. Keep feature starts constrained until the integration backlog drains.

Acceptance is behavioral, not merely a new label:

- A synthetic checked candidate that conflicts with a newer commit is never applied to a dirty user checkout; it creates one owned reconciliation action, then a new candidate tested on the reconstructed tree can land exactly once.
- Two independent candidates cannot both claim the same old base as tested main. If the first lands, the second is revalidated; if its checks fail, main stays green and the card explains the next action.
- A blocked weather-like card appears in **blocked**, not runnable; the runnable reconciliation action and its owner are visible. A later wake/landing updates both projections after reload.
- Every visible session, review, test, and landing state is backed by the corresponding persisted record. An interrupted integration recovers without a double commit or lost card.
- A real Daniel decision still reaches the decision inbox with options and a recommendation; a code conflict does not.

Measure a baseline, then review after the v0.2.1 tag: landed outcomes per week, median and upper-tail time from worker finish to landed commit, active WIP, blocked age by cause/owner, stale-candidate rework, main-CI recovery time, and Daniel interruptions for non-decisions. These are measures to collect, not current performance claims or targets invented without a baseline. If landing remains the bottleneck, then invest in a transactional store, richer dependency planning, or native merge-queue infrastructure. Otherwise freeze HQ and return effort to the game.

## Conclusion

The system does not need a smarter-looking queue; it needs a reliable **finish line**. Build the convergence spine immediately and narrowly, then defer further HQ architecture until after the v0.2.1 Mark III release tag. Its success criterion is that a completed worker session becomes either a verified landed change or an owned, runnable recovery action without Daniel discovering the gap.

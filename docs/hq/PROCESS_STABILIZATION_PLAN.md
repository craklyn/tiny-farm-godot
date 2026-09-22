# Bring HQ's work process to a known-good state

Date: 2026-09-22
Status: IN PROGRESS
Owner: Chief of Staff

## Outcome

Daniel can return his attention to the game because HQ can be trusted to accept work, run it, review it, retain accepted lessons, land the exact checked change, and describe the resulting state without silently losing data or asking him to interpret process noise.

This pass covers the machinery of work: intake, task state, worker and reviewer handoff, verification, landing, durable learning, and the truthfulness and write safety of the HQ surfaces that operate that machinery. It does not absorb gameplay, art, audio, release-content, or ordinary feature-polish work merely because those items pass through the queue.

## Ground rules

- A visible status is derived from the underlying record or execution evidence. No manually maintained green may substitute for it.
- Interactive behavior is verified by performing the user action and asserting the resulting persisted state. Rendered words and source-code searches are supporting checks, not behavioral proof.
- A worker may call work complete; only the reviewer and landing checks may make it complete in HQ.
- The exact candidate the reviewer checked is the candidate that may land.
- A durable personal lesson is written only after Daniel accepts the work that produced it. Rejected work leaves no memory behind.
- Every HQ write preserves fields it does not own.
- Worker logs distinguish environment warnings, corrected development failures, and findings that block acceptance.
- Existing changes in the shared working tree are somebody's work. No implementation may overwrite, discard, or sweep them into an unrelated commit.

## Findings

| Area | Current fact | Evidence |
|---|---|---|
| Decision actions | The acceptance text explicitly requires recommended Yes and No, next-question navigation, revision, Queue and direct-card behavior, keyboard use, and narrow-width coverage. The rejected candidate checked only rendered strings for part of that behavior. | `docs/hq/HUMAN_INTERFACE_PLAN.md:38`; `hq/data/work/wecd05a982cc.json` |
| Duplicate verdict surface | The animation page still presents verdict controls separate from the queue's authoritative decision flow. | `hq/static/anim.js:501` |
| Retry learning | Reviewer findings are retained on the work item and inserted into the next attempt's prompt. | `hq/drain.py:201`; `hq/drain.py:389`; `hq/work.py:700` |
| Durable seat learning | The drain reads a seat's memory, but accepted drain work has no path that safely appends a worker's proposed memory in the main tree. Chat has the only parser-and-append path. | `hq/server.py:1569`; `hq/data/work/wbbbcc2086a1f.json` |
| False consistency warning | Startup checks references before work items are bound, while the checker reads the bound work-item collection. | `hq/server.py:669`; `hq/server.py:6102` |
| Intentional waiting | HQ has no first-class waiting-with-a-wake-event state, so deliberate waits can read as blockage or disappear from truthful planning. | `hq/data/work/wd2ac4cb762d.json` |
| Destructive HQ save | Saving a release plan rebuilds story objects and drops fields the editor does not know about. | `hq/server.py:5068`; `hq/data/work/w41fdcfcaf59.json` |
| Conflicting labels | The server and visible HQ prose use different names for the same test checks. | `hq/data/work/w9b453fb70c7.json` |
| Per-run logs | The current suite runner already captures subprocess output per invocation in memory and judges its own exit status. The old shared-log implementation request is obsolete. | `hq/drain.py:1165`; `hq/data/work/w37ca945abca2.json` |

## Decisions

1. The queue is the authoritative decision state machine. Other pages may either invoke that same recorded transition or link to it; they may not display a successful-looking local verdict that records nothing.
2. Behavioral acceptance for HQ controls means submitting the action through the same handler the browser uses and asserting the persisted response and next visible state. Keyboard and narrow-width acceptance require browser-observable behavior, not a source-string assertion.
3. Worker and reviewer notes use the existing `<remember>...</remember>` contract. Tags are stripped from Daniel's result immediately, but proposed notes remain pending until the corresponding item is accepted. The accepted transition appends them through the single existing memory writer in the main tree. Rejection deletes the pending proposal.
4. Intentional waiting carries both a concrete wake event and the ruling that authorized the wait. It is neither blocked nor actionable until that event occurs.
5. HQ editors merge owned fields into stored records by stable identity. They never recreate a record from only the fields shown in the form.
6. The shared visible names are “Unit tests” and “Integration tests.” Internal identifiers may remain stable where changing them would break stored data.

## Work items

### A. Make decision actions authoritative and behaviorally verified

Cards: `wecd05a982cc`, then `we11c4a7b3f92`.

- Finish the existing revision without discarding its candidate: exercise recommended Yes, recommended No, revision feedback, persisted outcome, and automatic selection of the next question in both Queue and direct-card flows.
- Verify keyboard operation and the narrow-width layout through observed browser behavior.
- Make the animation page use the same recorded transition, or replace its controls with a clear route to the authoritative review when no safe identity mapping exists. It must never appear to record a verdict when it did not.
- Acceptance: one recorded answer produces the same stored state from every supported surface; every promised transition has a behavioral test; no local-only verdict remains.

### B. Retain lessons from accepted work

Card: `wbbbcc2086a1f`.

- Reuse the chat memory parser and memory writer rather than adding a second tag format.
- Store proposed drain memories with the work result, stripped from Daniel's visible prose.
- Append them in the main tree only when the item reaches accepted. Rejecting or superseding the result removes the proposal without changing personal memory.
- Acceptance: tests cover parsing, visible-result stripping, acceptance, rejection, idempotence, and a worker-worktree/main-tree boundary.

### C. Restore truthful state and write safety

Cards in order: `w559bf20d689`, `wd2ac4cb762d`, `w41fdcfcaf59`.

- Bind work items before running the broken-reference consistency check. Prove a valid reference stays quiet and an invalid reference is reported.
- Add intentional waiting with a wake event and authorizing ruling; exclude it from unblock actions, overdue-blocked signals, and program gates until the event occurs. Migrate only the two records named by the card.
- Make release-plan saves merge fields by story id. Prove an unknown field survives a read/edit/save/read round trip.
- Acceptance: focused regression tests pass and no unrelated record changes are included.

### D. Align the visible vocabulary and close obsolete verification work

Cards: `w9b453fb70c7`, `w8e71933a1a9`, `w37ca945abca2`.

- Use “Unit tests” and “Integration tests” consistently in server output and visible pillar prose.
- Run the plain-writing check after all preceding text settles. Resolve new findings caused by this pass; do not fold the unrelated writing backlog into this stabilization build.
- Reconcile the per-run-log card as obsolete: cite the current isolated subprocess evidence and record the shared rule that each run judges only its own output.
- Acceptance: no newly introduced MUST FIX writing finding, the focused label tests pass, and the two non-build cards accurately record why no implementation session is needed.

## Final verification

1. Run every focused HQ regression added by the work above.
2. Run the full HQ Python and JavaScript test inventory, then the repository's static frontend check.
3. Run both Godot suites sequentially with isolated user-data paths so concurrent sessions cannot poison them.
4. Run the offline writing verification, then the live writing judge only if its environment is available and authorized.
5. Restart HQ and observe the real Queue, direct-card, Bullpen, waiting-state, and release-plan behaviors in the browser.
6. Resume automatic task starts only after the current process cards are reconciled and the working tree contains no unowned overlap in their files.

## Execution status

- 2026-09-22 10:35 PDT — Paused new automatic task starts. One already-running candidate check was allowed to continue.
- 2026-09-22 — Surveyed 52 queued items: nine are in scope; seven require implementation; two require evidence reconciliation. Foundational landing, retry-context, attention-count, and hand-back cards are already solved and will not be rerun.
- Next — Review this plan against the code, then implement clusters A through D in isolated worktrees.

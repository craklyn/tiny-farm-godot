# Bring HQ's work process to a known-good state

Date: 2026-09-22
Status: VERIFIED; THREE HISTORICAL CARD FOLLOW-UPS REMAIN
Owner: Chief of Staff

## Outcome

Daniel can return his attention to the game because HQ can be trusted to accept work, run it, review it, retain accepted lessons, land the exact checked change, and describe the resulting state without silently losing data or asking him to interpret process noise.

This pass covers the machinery of work: intake, task state, worker and reviewer handoff, verification, landing, durable learning, and the truthfulness and write safety of the HQ surfaces that operate that machinery. It does not absorb gameplay, art, audio, release-content, or ordinary feature-polish work merely because those items pass through the queue.

## Ground rules

- A visible status is derived from the underlying record or execution evidence. No manually maintained green may substitute for it.
- Interactive behavior is verified by performing the user action and asserting the resulting persisted state. Rendered words and source-code searches are supporting checks, not behavioral proof.
- A worker may call work complete; only the reviewer and landing checks may make it complete in HQ.
- The exact candidate the reviewer checked is the candidate that may land.
- A durable personal lesson is written only after the exact work that produced it is accepted by Daniel or passes clean review and exact-candidate landing. Rejected or undone work leaves no memory behind.
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
3. Owner sessions continue to propose lessons with `<remember>...</remember>`. The checker may propose a lesson for the owner in a dedicated JSON field; it may not hide one in prose. Proposals are bound to an attempt id and stripped from Daniel's result. A later clean check decides which still apply.
4. Accepted and cleanly auto-landed work commit applicable pending lessons idempotently through the single memory writer in the main tree. Drop, rejection, supersession, or Undo removes that work's attributed memory. A revision replaces proposals from the superseded attempt rather than accumulating contradictory notes.
5. Intentional waiting carries both a concrete, machine-evaluable wake event and the ruling that authorized the wait. The evaluator records when the event becomes satisfied or invalid; satisfied waits return to the ordinary actionable state, and broken references surface as errors rather than hiding the project.
6. HQ editors merge owned fields into stored records by stable identity and reject a stale revision. They never recreate a record from only the fields shown in the form. Addition and deletion are explicit operations, not side effects of omission.
7. The shared visible names are “Unit tests” and “Integration tests.” Internal identifiers may remain stable where changing them would break stored data. The larger glossary card is split: this stabilization owns the two conflicting test names; its remaining prose sweep stays open with that narrower remainder recorded.

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
- Let the checker return an optional, explicit lesson for the owner when its review establishes a reusable rule.
- Commit the applicable proposals in the main tree only when the exact attempt is accepted or cleanly auto-landed. Rejecting, superseding, dropping, or undoing that result removes its attributed proposal or committed note.
- Acceptance: tests cover parsing, checker schema, visible-result stripping, revision replacement, manual acceptance, clean auto-landing, rejection/drop/Undo, idempotence, and the worker-worktree/main-tree boundary.

### C. Restore truthful state and write safety

Cards in order: `w559bf20d689`, `wd2ac4cb762d`, `w41fdcfcaf59`.

- Bind work items before running the broken-reference consistency check. Prove a valid reference stays quiet, an invalid reference is reported, repeated checks replace rather than accumulate warnings, and a read failure reports unavailable rather than inventing missing references.
- Add intentional waiting with an authorizing ruling and a typed wake event that the server can evaluate. Exclude it from unblock actions, overdue-blocked signals, and program gates only while the event is valid and unsatisfied. Surface invalid references; return satisfied waits to the ordinary actionable state. Migrate only the two records named by the card.
- Make release-plan saves merge owned fields by story id and reject stale revisions. Preserve unknown story, release, and top-level fields. Define and test explicit add/delete behavior, duplicate or missing ids, and concurrent stale payloads.
- Acceptance: focused regression tests pass and no unrelated record changes are included.

### D. Make verification trustworthy under unattended execution

Cards: `wd3ce6b6f4db`, `wa81b250c0180`, `we22d5b8c4a03`.

- Give every Godot suite invocation an isolated `user://` location so concurrent or abandoned sessions cannot read another run's autosave. Prove two concurrent fixtures cannot see one another's files.
- Make the integration runner exit deterministically after success and fail fast on its known timing fault. Prove a green result returns control to the drain rather than hanging until timeout.
- Add focused tests around Animation Lab's work-launching and verdict path, including keep, drop, rework, missing work identity, persisted reason, and no silent success.
- Acceptance: unattended commands finish with trustworthy exit codes, concurrent canaries remain isolated, and Animation Lab cannot spend work or claim a verdict without a tested record transition.

### E. Tell the truth in logs and visible vocabulary

Cards: `w9b453fb70c7`, `w8e71933a1a9`, `w37ca945abca2`.

- Use “Unit tests” and “Integration tests” consistently in server output and visible pillar prose.
- Classify a command by its exit result and structured event, not by a line beginning with “Failed.” Present sandbox/environment warnings separately from corrected development failures and findings that block acceptance. Add fixtures for the stream-fd warning, a real non-zero command, a later-passing retry, and a checker failure.
- Narrow the remaining glossary card to its still-unfinished prose sweep instead of falsely closing the entire original ask.
- Run the plain-writing check after all preceding text settles. Resolve new findings caused by this pass; do not fold the unrelated writing backlog into this stabilization build.
- Reconcile the per-run-log card as obsolete: cite the current isolated subprocess evidence and record the shared rule that each run judges only its own output.
- Acceptance: no newly introduced MUST FIX writing finding, the focused label tests pass, and the two non-build cards accurately record why no implementation session is needed.

## Final verification

1. Run every focused HQ regression added by the work above.
2. Add one repository test runner that discovers every `hq/tests/test_*.py` and `test_*.js`, runs Python tests then Node tests in a documented order with isolated scratch paths, fails if a discovered test was skipped or unrecognized, and prints the count and result of every file. Run it, then the static frontend check.
3. Run both Godot suites sequentially with isolated user-data paths so concurrent sessions cannot poison them.
4. Run the offline writing verification, then the live writing judge only if its environment is available and authorized.
5. Run a controlled end-to-end canary against fixture records in a temporary data root: file work, run owner and checker, force one reviewer revision, confirm the next owner receives the finding, cleanly check and land the exact candidate, verify grouped sessions and the final card state, and verify that the accepted lesson appears only after landing. Restart/reload at each persisted boundary and clean up the fixture root.
6. Restart HQ and observe the Queue and direct-card behavior at desktop and narrow viewports using reversible fixture records; verify persisted decisions and next-card selection after reload. Observe Bullpen classification and waiting-state presentation without mutating real work. Exercise release-plan save only against the temporary data root.
7. Resume automatic task starts only after the current process cards are reconciled and the working tree contains no unowned overlap in their files.

## Execution status

- 2026-09-22 10:35 PDT — Paused new automatic task starts. One already-running candidate check was allowed to continue.
- 2026-09-22 — Initial survey found nine in-scope cards. Plan review added three verification-integrity cards and one unfiled Bullpen classification defect necessary for the stated outcome. Foundational landing, retry-context, attention-count, and hand-back cards are already solved and will not be rerun.
- 2026-09-22 — Plan review corrected lifecycle gaps around auto-landing, reviewer lessons, Undo, wake events, stale writes, test discovery, and safe end-to-end verification.
- 2026-09-22 — Implemented clusters A through E in isolated worktrees and landed reviewed commits `459e9c5`, `63c875c`, `ba68a69`, `64399ce`, `0733f41`, and `ede6356` on main. The queue remains paused while the historical cards are reconciled.
- 2026-09-22 — The complete HQ runner passed 27/27 locally discovered test files with no skips or failures; Animation Lab passed 11/11; the frontend static check and offline end-to-end process canary passed. Both isolated Godot suites passed (2,853 unit assertions and 969 integration assertions, zero failures). HQ was restarted and the live Bullpen showed the paused state and grouped work items.
- 2026-09-22 — Offline writing verification still reports four MUST FIX titles on unrelated local work-card data, plus existing advisory notes. This does not establish a new code failure or a clean writing pass. The live writing judge was not run because its external submission was not authorized in this environment.
- 2026-09-22 — CI could not be queried from this sandbox: the installed `gh` command is blocked by snap confinement and direct GitHub DNS is unavailable. The local suite results above are the verification evidence, not a claim about remote CI.
- 2026-09-22 — Live Bullpen inspection found a grouped disclosure whose nested card link stole the expand action. Landed `329499d` to separate those actions, restarted HQ, and observed the row expand in place and its separate “Open work card” link navigate. The full HQ runner then passed 28/28 locally discovered files with browser access; its two Chrome fixtures cannot start under the restricted shell sandbox alone.
- 2026-09-22 — Applied the guarded process-card audit. Nine bounded cards closed with operator-attributed commit and test evidence; the wider language sweep and writing verification remain queued; the old decision-action card retains its failed-review and revision history but is held out of scheduling until its independently-landed implementation is explicitly linked. No native checker approval or Daniel acceptance was inferred. The dry-run remained applicable after application.
- 2026-09-22 — The first reconciliation fixture incorrectly copied live cards and failed after the real audit changed them. Replaced it with synthetic immutable fixtures in `d59d66c`; the full HQ runner passed 29/29 locally discovered test files with browser access after the live audit.
- 2026-09-22 — Landed `da7f27e` so the held decision-action card no longer promises an automatic retry or offers actions that cannot resolve the operator hold. Restarted HQ and observed the preserved result/history and explicit “Nothing starts automatically” message. HQ runner passed 29/29 again; frontend collision check passed.
- 2026-09-22 — A Queue navigation once displayed “Running” while the policy and Bullpen said “Paused.” A hard reload and a direct-card-to-Queue browser reproduction both showed the correct Paused state; the local `/api/execution` endpoint also reported paused. No reproducible code defect was found, so no speculative patch was made.
- Follow-ups — The wider rendered-language sweep and writing verification remain open. The decision-action card remains held from scheduling until its rejected candidate and separately-landed implementation are explicitly linked. This audit is a process-state reconciliation, not a substitute for that provenance or a claim that those three cards are done.
- Next — Reconcile historical process cards against the landed commits, inspect the final live state, and resume automatic starts only when no process card can relaunch obsolete or overlapping work.

# Land drain-triggered chief-of-staff work

## Ground rules

- HQ's live work cards are in its separate store. Use HQ commands to claim and close a card; never commit a card file.
- The drain discovers held work with code before action selection. Discovery alone must not start a model session.
- A capability worker may need full host access for the display or adb. Dispatch it only for a recorded `needs` value, pass only the environment values required for that need, strip every key in `execution.SECRET_ENV`, never touch the normal tablet app or its saves, and send its candidate through the ordinary review, test, secret, and CI gates. Report the actual sandbox mode; do not claim that a full-access session is limited by the `needs` label.
- Taste decisions remain for Daniel. An automatic review may prepare a question but may not choose its answer.
- Tests use scratch stores and no real model calls. A real smoke uses a harmless capture and the configured host devices; it must not deploy a game build.
- Treat the saved patch for work card `w7d132b52f9f` as a candidate. Review its behavior on the current main tree; do not trust its earlier test claims.

## Findings at main `ec412ca`

| Fact | Source |
| --- | --- |
| Startup migrates spending and repair holds before selecting actions, but does not route every chief-of-staff hold. | `hq/drain.py:3408-3424`, `hq/drain.py:3499` |
| The card's blocker and lane come from the work projection. The selector accepts only runnable build, reconcile, or recovery work. | `hq/work.py:989-1297`, `hq/work.py:1644-1680`, `hq/action_dispatch.py:19-32` |
| Automatic spending and repair reviews have hard limits. | `hq/work.py:2979-3036`, `hq/work.py:3368-3437` |
| The existing candidate gate, landing, and secret scan must remain in charge of capability output. CI polling records red but does not automatically revert; safe undo transactions already exist for manual use. | `hq/drain.py:2075-2170`, `hq/drain.py:2300-2500`, `hq/action_dispatch.py:210-257`, `hq/work.py:3858-3979` |
| The saved patch adds routing and capability scaffolding, but lacks proof of every decision outcome, attribution, normal dispatch through landing gates, and real host capability execution. | Saved candidate patch; work card's reviewer findings |
| The candidate would run capability sessions with `danger-full-access`, while stripping only one named key. It also releases some spending and repair holds before chief review, and routes in maintenance modes. | Saved candidate patch:229-244,288-317; `hq/drain.py:3399,3430-3480` |
| The candidate's model-driven close and taste draft need independent validation of the reason and persisted state. Its taste path writes directly into checked-in `hq/data/decisions`, outside candidate review and CI, and its filename scan can race. | Saved candidate patch:514-632; `hq/server.py:96-108`; `hq/work.py:3351` |
| The first repaired candidate still allows a stale model review to overwrite a resolved card, extends spending without the original ceilings, treats any no-lane card as a closable chief hold, infers full-host tablet access from incidental words, and accepts weak closure evidence. | Independent review of candidate branch, `hq/work.py:3125-3213`, `hq/drain.py:2997-3034` |

## Decisions and interfaces

- Keep the candidate's plain-code entry points `chief_of_staff_queue()`, `mark_capability_needs(item, view)`, and `route_chief_of_staff_queue(org)`. Call routing before `action_dispatch.choose(drain, *, include_thinking=False, ids=(), limit=0)`.
- Use `review_chief_hold(item, org, hold_kind="")` for the held card's automatic extend, rescope, close, or taste result. Do not release a spending or repair hold merely because the card has a capability need. Attribute recorded decisions to seat id `claude` and include the reviewer's finding and the resulting brief or reason. Close only with evidence that the work is superseded or sufficiently complete; a taste question remains held after a valid decision draft is filed.
- Use `release_chief_hold_for_capability(item, brief, decision="capability")` before selection only after the relevant chief review has cleared the hold and no other blocker remains. `needs` values are `display`, `tablet`, or `network`.
- Extend `execution.command_for(prompt, system, tools, route, turns, mcp=None)` and `execution.run_session` with an explicit capability profile. The drain's `run_cli(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id, attempt_id="", mcp=None)` passes profile and narrowly selected environment values. Determine the narrowest tested sandbox mode; if it is `danger-full-access`, record that full-host scope honestly. Strip the complete `execution.SECRET_ENV` set and any credential-like keys exposed by the host environment.
- Only normal drain startup routes held cards. `--brief`, `--repair`, `--recover-only`, and read-only modes must not quietly start an automatic review. There is no live-store Q-card API or collision-safe Q-ID allocator (`hq/server.py:88-108`, `hq/work.py:4045-4062`). For a taste question, persist a `decision_draft` on the held work card, containing the review finding, question, options, and recommended answer; show it to the chief of staff on that card. Do not allocate a Q-ID or write checked-in decision configuration during startup. A later curated Q-card must pass the normal code review and CI path.
- Automatic review gets two failed attempts to move a held card before a human fallback. A taste result does not count as permission to change the game design.
- Re-read the live card after every model call and require the same revision, hold type, and nonterminal state before saving a decision. Spending extensions must keep the existing ceilings and extension count. A no-lane condition is a structural fault for review, not permission for a model to close work. Only a structured, positive `needs` value may authorize the full-host capability profile; free text, including negations, never grants it. Closing needs current landing or explicit supersession evidence, not a keyword in old text.
- For a superseding card, `state="landed"` alone is insufficient: its recorded completion SHA must still be an ancestor of current main. An empty, malformed, reverted, or off-branch SHA cannot justify closing the held card.
- A display smoke may read `DISPLAY=:0.0`; a tablet smoke may inspect adb target without installing or overwriting anything. The capability worker never pushes or commits to main.
- A red CI run may trigger automatic undo only when its exact commit is still main HEAD, the card is still landed on that SHA, and there is no later green run. Reuse the durable undo transaction and record `ci` as actor with the run ID. On a race, conflict, unknown CI, or newer main, hold for chief review. Never reset or force-push; scan the revert commit for secrets before pushing. `hq/tests/test_undo_integration.py:18-140` supplies scratch Git fixtures.

## Work items and acceptance

1. **Candidate repair.** Port the saved candidate onto current main, confirm every hold kind routes to review or a runnable capability action in the intended drain mode, and repair the six findings above. Add scratch tests that run startup for empty work (zero model calls), each hold kind, extend, rescope, close, taste, recorded seat/brief, two-failure fallback, and persisted state. Run `python3 hq/tests/test_chief_codex.py` and affected HQ tests. Do not loosen an assertion to make it pass; report a failing measurement and stop.
2. **Gate proof and CI recovery.** Add a scratch-store test that enters `action_dispatch.choose`, claims and dispatches a capability card, and proves it cannot skip candidate review, both game suites, and the secret scan before push. Implement the exact-head red-CI undo rule above with tests for one revert, repeated poll/crash recovery, green/wrong-SHA/newer-main refusal, and preserved user bytes. Verify the exact process environment and live-card decision draft. Run a real harmless capability smoke on this host and record the command and result. Do not touch the normal tablet app. Do not loosen an assertion to make it pass; report a failing measurement and stop.
3. **Landing.** Review the worker results, run `python3 hq/run_tests.py` three times on the exact final tree (all discovered files pass), run both Godot suites and static checks, commit and push only the task's files, verify CI, then close the card through `hq/card.py` with its commit and successful CI run. Report the status of the paused desktop scheduled task; do not activate a duplicate.

## Execution status

- 2026-09-30: Adam's saved candidate stopped on stale-main review and incomplete host acceptance. No part of that candidate has landed.
- 2026-10-01: Chief of staff claimed the card and surveyed current main. Candidate repair, gate proof, and landing remain.
- 2026-10-01: Independent plan review found six safety and acceptance gaps in the saved candidate. They are now explicit requirements above.
- 2026-10-01: Gate review found no automatic CI rollback in current code. The exact-head, durable undo rule above is required for this card.
- 2026-10-01: First repair candidate passed 83/83 HQ test files on the host, but independent review found five safety gaps. It remains off main pending repair and targeted tests.
- 2026-10-01: The safety repair passed 83/83 HQ files; review found one remaining supersession check. It remains off main pending that fix.

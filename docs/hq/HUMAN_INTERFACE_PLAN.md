# Make Tiny Farm HQ easier to understand and use

Date: 2026-09-21
Status: LIVING
Last updated: 2026-09-21
Owner: Rin (HQ design); Chief of Staff owns preparation and acceptance.

## Purpose and authorization

Daniel authorized preserving all changes proposed in the September 21 HQ review as work cards, then implementing provider routing and observing one real backend run. This document preserves the interface work; it does not claim that the redesign is implemented. The backend plan is MODEL_ROUTING_PLAN.md.

The human should arrive without yesterday's context, identify the question, inspect the result, act, and understand what happens next. Agent instructions and execution records remain available as details, but are not the default human brief. Support deciding, directing new work, and exploring the game without demanding a verdict.

## Observed starting point

Live inspection on September 21 found the Dashboard counting 24 things waiting on Daniel, navigation counting 15, and Your Queue counting 9 questions; four queue entries lacked recommendations; two seeder entries had identical wording; an animation review showed conversation and filenames ahead of playable results; a recommended No had a Yes button; the completed-work group included prospective completions; and a dated dashboard brief exposed internal remember markup. These are observations from that visit, not promises that the mutable queue still has those counts. Source: task 01a0c60d-2a78-7880-afd7-a34175409645, live http://127.0.0.1:8642/.

## Work packages and acceptance

Each section below is independently preserved by a work card listed in WORK_INDEX.json. Existing card w44ff2049d9a owns the missing-deliverable gate; do not implement a rival gate.

### 1. Use one truthful definition of work waiting on Daniel

Derive Dashboard, navigation, and Decisions counts from the same ready-for-human set. Distinguish completed, ready to apply, awaiting verification, preparing, scheduled, and genuinely awaiting human action. A known incomplete result is not a human verdict. Preserve source history and expose what each count counts. Verify with fixtures for all states and a live cross-page comparison.

### 2. Prepare a decision before putting it in the human queue

Extend the existing deliverable gate (w44ff2049d9a) to require a specific human question, actual owner recommendation where a recommendation is appropriate, relevant inspectable evidence, and concrete consequences. Return incomplete preparation to the owner with a machine-readable reason. A real unresolved question can escalate with an explicit explanation; do not fabricate recommendations. An owner preparation failure must not remove Daniel's ability to give an informed explicit verdict on a finished result. Keep unprepared work out of the default ready queue, but allow him to open it deliberately and accept or request changes with the missing preparation clearly stated. Do not hide missing work from Work status. Coordinate with section 3.

### 3. Present a short human brief separately from the agent record

The selected view leads with the question, relevant artifact, actual recommendation and tradeoff, then the consequence of the action. Technical briefs, paths, execution logs and full discussion remain discoverable below. Remove procedural boilerplate, invalid owner placeholders, and internal markup. Prototype an animation review, a design choice and an incomplete result using actual cards before broad rollout. Never summarize away a material warning.

### 4. Show the result in the form Daniel needs to judge

Animation reviews have playable current/proposed results at normal game size; audio choices have listenable rivals; copy has a readable comparison; numeric choices have a comparison table. Required evidence is visible by default, not a filename in a paragraph. Distinguish artifact creation from display and from actual reviewed version. Reuse attachment handling and the existing deliverable gate.

### 5. Give every decision an unambiguous action and outcome

Replace generic Yes with the actual action, including negative recommendations. Keep real alternatives visible, distinguish request changes from cancel/drop, allow explanatory comments, and confirm what was recorded and which work starts next. Do not require a comment when a prepared alternative exists. Verify both a recommended Yes and recommended No and successful navigation to the next question.

### 6. Combine duplicate requests without losing distinct decisions

One human action should produce one queue entry even if it unblocks several tasks. Identical titles need deduplication or distinct outcome names, never silent data deletion. Preserve links to all source work and prior decisions. Include stable ordering and return-to-list/selected-item behavior.

### 7. Make the dashboard current and trustworthy

Use the shared attention count, show current actionable information first, remove raw agent instructions and stale NEW labels, and state timestamps/freshness plainly. Cached briefs remain on-demand (no paid generation on navigation). Do not conflate unmeasured, failing, and passing checks. An issue must name its owner and available next action. Full status and historical briefs remain accessible.

### 8. Organize navigation around what Daniel wants to do

Prototype Overview, Decisions, Work, Studio with a persistent New request action. Compare a compact labeled sidebar with a top bar rather than predetermining one. Move disabled routes out of primary navigation. Keep existing tools reachable and old deep links working. Daniel can browse artifacts and initiate direction without first knowing a persona or tier.

### 9. Make the decision layout readable at desktop and narrow widths

Simplify list rows to recognizable title and short reason; remove duplicated approval controls and full briefs from the list. Prototype a 300–360 px desktop list, roomy artifact pane, controlled prose measure, 16 px body text, comfortable leading, sentence-case labels, fewer borders, and accent reserved for selection/action. These are prototype values, not fixed constraints. At narrow widths show list then selected detail with Back, not a detail pane below the entire backlog. Validate keyboard use, focus, readable contrast, and actual screenshots at 1440, 1280, and a narrow viewport.

### 10. Let Daniel request work without knowing the org chart

Provide a general request entry point that captures his words, resolves owner and execution policy, returns a durable linked work card, and shows progress and outcome. Editing priorities or initiating discussion must not require opening an unrelated decision. Roles remain accountable ownership; model/provider choice is independent. Verify submit, refresh, status, and reopen paths.

### 11. Judge the interface by real tasks

On the prototype, have Daniel identify a question, inspect evidence, choose an alternative, request a change, create a request, and return to his place. Record observed confusion, missing context, and completion—not invented precision about decision minutes. Validate count agreement, no unprepared approvals, and that durable decisions start the intended work. Keep a full record accessible without making him read it to operate HQ.

## Delivery order

First truthful states and readiness; then the human brief, evidence and actions; then navigation, layout and request intake. Validate three representative cases before broad rollout. Independent checks inspect outcomes rather than trusting persona agreement. Clear ownership is useful; biographies and titles do not establish quality. Reducing meaningful human effort is the goal, not maximizing agent activity or mechanically emptying the queue.

## Execution record

2026-09-21: design work preserved; implementation pending. Existing deliverable card reused. Backend routing is the current interactive task. No redesign item is claimed complete.

2026-09-21: section 1 implemented and verified; final review resolution and commit remain pending. Live checks confirm equal totals across Dashboard, navigation and Queue, and exact rendered Queue membership. Code review and fixtures establish the shared membership source for the numeric summaries. Unavailable-data and verdict-refresh transitions are fixture-tested, not live user-data mutations. Dashboard, navigation and the decision queue now consume the stable ready IDs and total from `server.waiting_on_you()`. The projection also reports why non-ready work is preparing, awaiting an owner reply, awaiting verification, scheduled or completed; an unavailable reading is not rendered as zero. Backend fixtures cover shared membership and status; operator browser checks compare live totals and ready IDs. The existing deliverable gate remains unchanged.

2026-09-21 update from Daniel: a concurrent Claude session reports renaming the queue-row Ask button to Open, showing reply countdown and routing outcome near the composer, restoring an explicit verdict on finished results without recommendations, and adding a duplicate merge rule. Verify the current implementation before building those sections; reuse those fixes. Shared-tree ownership, staged writing checks, and restarting the live service remain required.

2026-09-21 review wording from Daniel: prefer “Review: The revised seeder-bot animation” (alternative: “To approve: The revised seeder-bot animation”) over owner/build narration. Proposed response labels: “Approve, Comment, Reject and Close”. Recommended interpretation for implementation review: Approve accepts the displayed version; Comment sends feedback without recording approval or rejection; Reject and close rejects this version and closes its review, without deleting the artifact. Confirm this distinction in the UI; do not confuse closing the panel with rejecting work. Put a working link or playable preview of the exact reviewed artifact next to the heading. These are recorded requirements, not shipped behavior.

2026-09-21 implementation rule: review-card creation must preserve a short deliverable name separately from the agent request; the shared review renderer adds “Review:” for the human decision. Keep original asks in the brief. This must apply across card entry paths, not only to one persona prompt. Legacy cards need a safe readable fallback without inventing an artifact or erasing history.

2026-09-21 execution authorized: after repairing the integration fixture and completing the supervised routing trial, run these redesign cards in delivery order, with one active implementation at a time. Inspect each result and resolve failures before advancing. Keep unrelated backlog paused.

## First-card implementation contract (reviewed 2026-09-21)

Extend the existing server.waiting_on_you() read-only projection as the single source of ready membership: stable source IDs, status/reason and counts consumed by dashboard, navigation and queue. Current competing paths are server.py waiting_reading, work.py _in_his_list/snapshot, queue.js qClassify/qLoadData and app.js badge arithmetic. Survey found queue.js places work plus decisions into queueCounts.work while app.js adds decisions again; work.js also subtracts held cards already excluded by snapshot. Remove competing arithmetic, not useful rendering. Resolve send-back/owner-return consistently; a prior judgment alone must not permanently hide a returned decision.

Fixtures cover prepared decisions, send-back/owner-return, preparing, owed/awaiting reply, held patches, verification pending, scheduled and actually landed work. Green suites are not recorded completion. Keep missing preparation and all checker/test warnings discoverable; explicit informed verdicts remain possible on finished results. Read operations must neither mutate records nor launch models, and an unavailable count is not zero. Verify that all three consumers derive membership/counts from the shared projection. Compare live totals across Dashboard, navigation and Queue, and compare the Queue's rendered ready IDs exactly with the projection. Dashboard and navigation render numeric summaries, so they have no rendered item-ID set to compare; verify those source paths in code and fixtures.

The subsequent deliverable gate extends this backend projection, not a separate frontend-only gate. Do not invent artifact requirements in the count card. Readiness, evidence and human brief requirements remain separate packages that share this projection.

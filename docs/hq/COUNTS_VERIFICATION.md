# Verify the shared count of decisions waiting for Daniel

Date: 2026-09-21
Status: FINAL — verified and committed by operator acceptance
Owner: Adam, Chief of Staff

## Context and method

The first redesign card is w5696f096a3e. Its native worker run was 20260921-165721-918c. The original checker inferred that held work remained ready. Independent reproduction and an actual real-helper check disproved both original findings: _in_his_list excludes _held_back, and the new fixture passed all 11 original checks. The original verdict remains recorded. Checker-only run 20260921-170752-recheck-8523 correctly required live verification and stronger consumer coverage. No worker implementation call was repeated.

## Actual verification

Before the change, live dashboard data reported 24 waiting while navigation displayed 20. After applying the code and restarting HQ with background work paused, the live /api/waiting-on-you projection, dashboard and navigation all reported 25 (23 work results and 2 design decisions). The main queue displayed 25 questions. All 25 rendered Open-button source IDs matched the shared API exactly, not only its total. Final browser observations (with exact source hashes), ready IDs and API responses are saved under /tmp/hq-routing-checks/counts-live-final/; the browser check is also recorded in task 01a0c60d-2a78-7880-afd7-a34175409645.

The legacy direct-card page now shows Waiting on you 23 plus Waiting for your ruling 2; 28 other results are separately labelled Preparation and verification. The main queue now shows 9 recorded landed results separately from 9 awaiting completion, instead of claiming all 18 landed. These counts describe this observation, not fixed expectations for future queue state.

The main queue's Back with the studio fold has explicit Open result links with preparation and checker warnings. Following the seeder-bot link opened /#/work/wr1788991284fa19 with its missing-recommendation warning and existing Good — accept, Drop it and Comment controls intact. No verdict was submitted during testing.

Independent final review found stale API caching, inaccessible folded results and unavailable-data text claiming an empty queue. The correction bypasses cache for the shared projection, adds the explicit review links, and distinguishes unavailable data from an actually empty queue. A subsequent focused independent review found those three defects resolved.

## Tests and evidence

All nine HQ Python test scripts passed on main. The shared-count fixture now has 30 checks, including owner return, held work, preparation, scheduled work, recorded completion, read-only behavior and unavailable data. Three JavaScript regression scripts execute the real API helper, loaders and renderers: test_queue_completion.js, test_work_attention.js and test_queue_refresh.js. They verify group membership/counts, warnings, refreshing changed responses after approval or owner return, deliberate review links and unavailable versus empty states. These passed on main after the final JavaScript corrections. Syntax checks and git diff --check passed.

Main game suites: 2853 unit and 968 integration passed, zero failures. Logs: /tmp/hq-routing-checks/counts-main/. The final full suite rerun followed the status-centralization correction. No test assertion was weakened. Existing shutdown resource warnings remain.

## Limits and next step

This completes the count/readiness-projection implementation, not the later artifact gate, title/action redesign, or layout. No approval/rejection was performed on a real user card to test refresh; changing-response regression fixtures exercised those transitions. Operator acceptance and the completed commit are recorded below. Existing CI failure is the separately filed demo replay build-label mismatch.

## Final status centralization and live evidence

A further native review identified remaining client-side completion classification. That policy now lives entirely in server.waiting_on_you; qClassify and qGreen were removed. Recorded completion, ready_to_apply, verification_pending, preparing, scheduled, closed and unknown remain distinct, with no loss of historical records. Final read-only API results are 9 completed, 9 ready_to_apply, 23 ready work, 57 scheduled, 11 verification_pending, 8 preparing, 62 closed and 14 unknown legacy states. The main queue shows 90 non-ready studio items plus separate closed history, while retaining the same 25 ready IDs. Focused independent review found no actionable issue in this correction.

After the final source change and service restart, CUA rechecked Dashboard, main Queue, and the actual Open result link into the seeder direct-card page. Final evidence is /tmp/hq-routing-checks/counts-live-final/browser-observations.json with source hashes in source.json. The observation records the 25/25/25 totals, Queue’s exact 25 ready IDs, 9 completed versus 9 pending, legacy 23+2 with 28 preparation/verification, and the clicked seeder link leading to its warning and accept/drop/comment controls. Refresh transitions and unavailable-response behavior are fixture-tested, not claimed as live mutations of user data.

## Legacy unavailable-state correction

Final checker run 20260921-173242-final-check-abf9 found that the legacy direct-card renderer still showed a zero ready count when the shared projection was unavailable. The renderer now says Queue count unavailable, explains that the count cannot be confirmed, and retains existing results without claiming the queue is empty. The legacy renderer regression covers both unavailable and genuinely empty responses. All three JavaScript regression scripts and the work.js syntax check passed after this correction. Backend and game code are unchanged from the previously verified suites.

The subsequent checker confirmed the full behavior and evidence, requesting only consistent queue wording because the shared list includes both work and design decisions. Both renderers now say Queue count unavailable; the three client regressions passed again after that wording-only change.

## Scope of membership verification

The Dashboard and navigation display numeric summaries, not lists of source IDs. Live browser checks established equal totals across Dashboard, navigation and Queue; only Queue renders individual review controls, and its exact 25 IDs were compared with the API. Shared-source membership is established by code review and backend fixtures: Dashboard reads /api/signals through waiting_block and waiting_reading into waiting_on_you; navigation reads /api/waiting-on-you and displays count; Queue uses that same projection to select items. No three live DOM ID sets are claimed. The plan now states this verification method explicitly. An independent read-only review confirmed these paths and the distinction; another API request alongside a Dashboard visit would not prove what that page consumed.

## Required-source read completeness

Native review found that permissive legacy readers could silently omit unreadable work records. The projection now requests strict reads of work, curated decisions and rulings, with all required reads and classification inside its availability boundary. Legacy callers retain permissive defaults. Real malformed/missing/not-directory fixtures and simulated permission failures cover all three required sources; nested-data failures are also covered. The fixture now passes 30 checks. Independent focused review found no actionable issue. All nine HQ scripts, three JavaScript regressions and syntax checks were rerun on main after this correction and passed. A full game-suite rerun followed this backend change. Live API evidence and exact source hashes after restart are in /tmp/hq-routing-checks/counts-live-strict/.

## Acceptance and commit

Committed as 2f281054c0cb1295d171c15206aac9df1798ffae. Tests and live verification passed. The final native reviewer rejected the clarification of the count-only surfaces’ verification method and identified a stale execution note. The stale note was corrected. Two independent reviews confirmed that shared-source code/fixtures plus live totals and exact Queue membership satisfy the product requirement; numeric summaries do not render item-ID sets. Adam accepted on that basis through an explicit operator adjudication. The native fail and both findings remain unchanged in the card. This was not automatic approval or a native checker pass. Normal writing hooks ran on the scoped commit.

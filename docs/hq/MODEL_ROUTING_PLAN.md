# Let HQ execute work with Claude or Codex

Date: 2026-09-21
Status: LIVING
Last updated: 2026-09-21
Owner: Chief of Staff; backend implementation delegated to isolated workers.

## 1. Ground rules and authorization

Daniel authorized filing the interface changes, implementing either-provider execution in this session, temporarily mapping Fable to Astra, Opus to Sol, Sonnet to Terra, Haiku to Luna, then supervising ONE backend run visible in the Bullpen. Do not drain the whole backlog or silently fall back to Claude. Keep the original assignment and actual provider/model visible in records. Current org assignment wins: the Chief of Staff is currently Opus, so its checker resolves to Sol. Do not silently restore old Fable assignments.

Keep determinism/game code untouched. Preserve existing dirty work and explicitly stage only this change's files. Workers use isolated git worktrees and commit without pushing. Python stdlib only; no runtime network dependency beyond provider CLI. Existing tests remain authoritative. Run suites before landing. Do not weaken assertions. Unknown dollar cost is unknown, never reported as a verified zero. Aggregates show known USD plus unknown-call count; nullable costs cannot break formatting, budget guards or parking. Token guard filters provider and cache tokens are not double-counted. No unbounded retry of quotas or failures.

## 2. Survey findings (cite, do not re-survey)

Read-only survey by survey_execution, 2026-09-21. Lines refer to the starting tree.

| Area | Starting evidence |
|---|---|
| Seat selection | hq/server.py:5288 seat_model; requested model is separate from provider |
| Build/checker | hq/drain.py:787 do_item, :850 checker, :497 run_cli |
| Tier0/capture/replies/prep | hq/work.py:773 _run_cli; capture :821 has no explicit model |
| Chat/brief | hq/server.py:5298 _chat_once; :4974 _make_standup_locked has no model |
| Animation | hq/anim.py:649 _draw, :598 stream parser, :44 Opus |
| Writing judge | tools/check_writing.py:560 judge, :505 availability, :88 Haiku |
| Bullpen | hq/server.py:1820 sessions, :1877 events, :1746 compact events, :1785 progress |
| Resume/accounting | hq/drain.py:280–368 transcript readers; server.py:1900 usage and :1926 ledger |
| Global limits | server.py:5080–5111; provider-scoped state needed |
| Autonomous jobs | work.py:1401 tick every 15 sec, :1454 startup/deadline launches; drain.py:1434 unattended guard |
| Controlled run | drain explicit ID --limit 1 --jobs 1; worker + checker + patch + suites + commit |
| Card schema | work.py:596 _file_item; POST /api/work/new at :1574; 600-character ask/action cap |
| Hook | .githooks/pre-commit:76 staged snapshot manifest must include adapter/config; commit-msg:13 runs writing judge |

Systemctl inspection found timer every 20 minutes (actual live configuration; overrides documented 2h). Timer stopped and HQ service stopped before filing/implementation to protect Claude allowance. Restart HQ under the background hold before the trial; leave the timer stopped.

## 3. Exact routing and adapter contract

Add hq/execution.py with no imports of server/work/drain. hq/data/execution_policy.json is the persisted routing policy. Version 1:
- mode: "codex" initially, or "claude" for original-model execution.
- default_model: "opus" for previous empty-model calls.
- mappings: fable -> gpt-6-astra; opus -> gpt-5.6-sol; sonnet -> gpt-5.6-terra; haiku -> gpt-5.6-luna.
- background_paused: true initially. Explicit supervised nominated item can run; all automatic tier0/capture/prep/reply/deadline/animation/drain launches respect the hold. Manual diagnostic/read-only page fetches do not launch models.
- trial_item: set to the card listed in WORK_INDEX.json.

resolve_model(requested: str = "", *, provider: str | None = None) -> dict returns provider (claude/codex), requested_model, model. Explicit recognized GPT names select Codex; preserve recognized Claude names for native mode. Unknown mappings fail with an actionable error, never silently choosing Claude. Policy is read dynamically to allow rollback without rewriting org/card assignments. Validate policy fields and paths.

run_session(prompt, system, tools, model, cwd, timeout, turns, *, phase="", seat="", item="", on_event=None, on_start=None, launch_context="automatic") -> dict returns text, usage, error, limited, provider, requested_model, model, exit_code. Exact callbacks: on_event(normalized_event_dict), on_start(pid). launch_context is automatic, interactive, supervised, or writing_hook. Paused automatic calls return held=true before starting a subprocess; consumers check launch permission before marking/claiming work. Supervised context requires the nominated trial item and a build-worker or checker phase. Interactive calls are explicit user-triggered work, never a background reply merely labeled interactive. Writing hooks are allowed while paused to enable reviewed commits. A held result does not consume an attempt, set quota errors or strand a doing state. Implementation may add optional keyword-only controls, documented here before consumers use them. Model resolution is internal. Usage carries actual provider/model and available token data; unknown USD is explicit. Avoid server import cycles.

Claude adapter preserves current tool allowlist/turn behavior. Codex adapter uses codex exec --json with explicit model and sandbox: read-only for checker/thinking; workspace-write for implementation. Do not bypass approvals/sandbox. Codex does not share Claude max-turn semantics: enforce wall clock/process cleanup and bounded retries; disclose unsupported exact turn caps. Translate tool restrictions explicitly: no-tools writers/judges disable shell, image, browsing, apps, plugins, MCP, multi-agent and other execution capabilities as supported by installed CLI; read-only profiles may use local read commands under read-only sandbox but cannot gain connectors or write tools. Document that this differs from Claude Read/Glob/Grep. Reject unsupported restrictive profiles rather than silently widening them. Use --ignore-user-config and verified explicit CLI configuration to avoid inheriting enabled connectors; preserve account auth. The installed CLI supports --disable shell_tool, view_image, apps, plugins, multi_agent, browser_use, computer_use, image_generation and hooks (codex features list). Verify any added configuration key before relying on it. Capture stdout and stderr concurrently; terminate/reap subprocess group on timeout; failed/no-final/malformed result cannot masquerade as success. Never fall back to Claude after a Codex failure.

Normalize Codex started, text, command/tool start and completion, final usage and error to the existing Claude-shaped event consumers for compatibility. Keep actual provider/model/requested_model in metadata. Preserve raw events separately or as named payloads where useful, never expose secrets. Rate-limit classification must inspect actual terminal errors rather than matching harmless event type names. Session usage must not double count cached tokens. Scope quota state and unattended budget guard by resolved provider. Codex success cannot clear a Claude exhaustion state; Claude limits cannot block a Codex trial.

## 4. Bounded work items and interfaces

### A. Shared adapter, policy, writing-hook integration

Files: hq/execution.py, hq/data/execution_policy.json, tools/check_writing.py, .githooks/pre-commit, focused hq/tests/test_execution.py. Implement section 3, preserve judge parsing, staged snapshot dependencies and usage recording. Tests use fake subprocesses: four mappings/native rollback/default model; text+tool+usage; no final; failure and real limit vs harmless rate_limit_event; timeout cleanup; no automatic fallback; read/write sandbox; hook snapshot importability. No real Claude calls during tests or commits. Bootstrap commits use the hook-documented --no-verify escape with manual writing review to avoid invoking Claude before routing exists. After integration, run the routed writing check. Do not copy/stage pre-existing dirty verdict data wholesale: merge only new verdict entries from the staged snapshot into both working and staged versions, retaining unrelated unstaged differences. Test actual staged-snapshot imports and judge invocation with a fake CLI.

### B. All HQ consumers, live records and trial hold

Files: hq/drain.py, hq/work.py, hq/server.py, hq/anim.py, hq/static/bullpen.js or actual existing bullpen UI file, focused tests. Consume A's exact contract, cover every survey call site. Preserve resume/review behavior and provider-scoped quota state. Respect hold at automatic launch boundaries AND before model execution; checker for nominated trial remains permitted. Expose provider/model to Bullpen and preserve incremental text/tool progress. Unknown cost stays unknown. Single-ID dry-run proves only nominated work is selected. Tests cover hold, provider independence, transcript compatibility, no orphaned work after hold, and existing deterministic suites.

### C. Independent review and main verification

Inspect A+B diffs for missing call sites, permission increases, retry loops, actual metadata and cost handling, hook recursion, exact event parsing and any false completion. Fix confirmed findings before live run. Run python3 hq/tests/test_execution.py and existing test_drain.py, test_drain_resume.py, test_landing_bar.py, test_work.py, test_queue_night.py, test_decisions.py; relevant new tests; both Godot suites with scratch HOME/XDG paths if supported. No --no-suites live trial.

### D. Supervised real run

Use the new small routing-documentation card owned by Ravi (Sonnet -> Terra), checker current Chief of Staff (Opus -> Sol), writing judge Haiku -> Luna. Commit implementation and policy before the trial worktree is created from HEAD. Persist final trial card state separately after its result. Start HQ with background_paused=true, keep timer stopped, open Bullpen for Daniel. Announce exact start. Run only nominated ID with --limit 1 --jobs 1. Monitor events/metadata and process at bounded intervals; do not narrate unchanged polls. Verify real output file, worker/checker models, independent checker finding, suites, applied diff, commit and durable final card state. Failure is recorded honestly and repaired before any retry. Keep unrelated backlog paused until explicitly expanded; report that state. A successful trial proves only the exercised path/models, not all four live endpoints.

## 5. Execution status

- Survey complete; cards and policy recorded. Adapter 411b027 and consumers 2156049 are integrated on main.
- Timer stopped; HQ stopped during change; no active drain observed.
- Plan review complete. The independent implementation review confirmed its three defects fixed in ea39228/3c10c6c; adapter 10 and consumer 8 offline tests passed before integration. Main-tree verification and live trial completed; evidence in MODEL_ROUTING_VERIFICATION.md.

## 6. Sources and evidence

Survey file:line table above; live systemctl status captured in this task. Future raw run evidence belongs in hq/data/runs/ and linked final card fields. Live verification report will distinguish implemented, fixture-tested, and actually exercised provider/model paths.

## 7. Review corrections before the live run

Independent review of the two implementation worktrees found three interoperation defects before any real provider call: Codex commentary was concatenated into the returned final response and could break checker JSON parsing; Claude max-turn termination lost its structured reason and would break continuation; and named nontrial card execution remained blocked even after unpausing. Repair requirements: retain commentary only in the event stream, preserve and consume stop_reason/subtype, and test explicit nontrial IDs with the hold off as well as the nominated trial with the hold on. These are correctness fixes, not changes to the user-authorized routing rule.

## 8. Resume after the trial test failure

Daniel authorized fixing the test and then starting the redesign work on 2026-09-21. Read-only review found Scenario AH stages row 11 only at x=13..19 (tools/test_runner.gd:3571), while the later unmarked-tile search uses x=20..23 (:3782). Generated obstacles can invalidate every candidate. Extend the fixture through x=20, retain all assertions, and verify both suites. This changes test setup only. Retry the existing reviewed card’s checks and landing if supported, preserving the failed run. Then execute redesign cards in delivery order, one at a time, leaving unrelated backlog held.

2026-09-21: fixture repair f38efa5 verified; trial landed automatically through the existing backend land function at 6778c51 after 2853 unit / 968 integration passes. Worker/checker results and usage reused unchanged after artifact-byte verification. Start redesign counts next under single-card nomination; unrelated backlog stays paused.

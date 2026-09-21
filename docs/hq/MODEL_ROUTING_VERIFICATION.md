# Verify HQ's temporary model routing

Engineering verification · Tiny Farm HQ

Date: 2026-09-21
Status: LIVING
Last updated: 2026-09-21
Repo/location: /home/daniel/dev/tiny-farm-godot

## 1. Background and motivation

Daniel authorized temporarily executing Fable/Opus/Sonnet/Haiku assignments with Astra/Sol/Terra/Luna because the weekly Claude allowance was nearly exhausted. The requested first trial is one real card, observed programmatically and in the Bullpen. Interface redesign work is separately preserved in HUMAN_INTERFACE_PLAN.md and WORK_INDEX.json.

The execution plan is MODEL_ROUTING_PLAN.md. This record distinguishes fixture tests from actual model execution. A passing simulated event stream does not prove that an account can execute a model.

## 2. Context under test

| Item | Observed state |
|---|---|
| Starting code | 312c710; record/plan commits 9953097, 396c15a, 6ead93b |
| Codex CLI | 0.155.1; `codex login status` says logged in using ChatGPT |
| Runtime | Local Linux desktop, Python stdlib HQ, localhost port 8642 |
| Trial owner | Ravi; recorded Sonnet assignment should resolve to gpt-5.6-terra |
| Trial checker | Chief of Staff; recorded Opus assignment should resolve to gpt-5.6-sol |
| Writing judge | Haiku assignment should resolve to gpt-5.6-luna |
| Trial card | w85a6cc7505a; one new Markdown quickstart file only |
| Background launch control | Timer stopped; HQ stopped during implementation; restart HQ under persisted pause for trial |

## 3. Questions and method

1. Does every execution entry point resolve the requested policy without accidental Claude fallback? Review call sites and run subprocess fixtures.
2. Are read-only/no-tool profiles, failure handling, quota boundaries and unknown costs represented accurately? Exercise normal, failed, limited, malformed and timed-out fake sessions.
3. Does a real card progress through worker, independent checker, visible Bullpen events, suites, patch application, commit, and durable completion? Run only the nominated ID with `--limit 1 --jobs 1`, no suite bypass, after committing implementation.

Poll local metadata/events at bounded intervals. Retain actual error output and invalid attempts. No timing/cost superiority claims or model-quality comparison will be inferred from this one task. The other model routes are fixture-tested unless explicitly recorded as exercised.

## 4. Findings and results

### Baseline — COMPLETE

All six existing HQ scripts returned exit 0 before implementation: test_drain.py, test_drain_resume.py, test_landing_bar.py, test_work.py, test_queue_night.py, test_decisions.py. Command output is retained in the interactive task. Game suite logs are `/tmp/hq-routing-checks/baseline-unit.log` and `/tmp/hq-routing-checks/baseline-integration.log`; unit results 2853 passed, 0 failed; integration results 968 passed, 0 failed. Both logs include existing shutdown resource-leak warnings; these are recorded rather than represented as new routing regressions.

### Adapter and integration — RUNNING

Implementation was interrupted by an account usage limit; Daniel increased the limit and both workers resumed the same preserved worktrees. Deterministic tests, independent review and main-tree verification remain pending. No live trial was started before this interruption.

### Supervised live run — RUNNING

Run 20260921-161543-474c: Terra worker completed successfully in 46.7 seconds; Sol checker completed in 29.8 seconds and flagged a real documentation error: the guide described supervised trial work as the only launch exception, omitting explicit interactive calls and writing hooks. The patch was applied and suites started, but acceptance is correctly withheld. A same-card revision will preserve this finding. Final acceptance/commit are TK. Luna writing-check calls also succeeded and recorded provider=codex with unknown dollar price, rather than a fabricated zero.

### Separate pre-existing CI failure — RECORDED

CI run 35665001793 reports a demo replay freshness failure: regeneration changes only the header build_id. The prior main run 35664411769 was also failed. The bootstrap run additionally lacked verdicts for the newly filed card text; the routed writing hook has now judged that text. The demo-label problem is separately preserved as work card w1e498ecc2a0, not silently included in the provider change. Source: https://github.com/craklyn/tiny-farm-godot/actions/runs/35665001793 (failed job logs).

## 5. Conclusions

The starting HQ Python tests pass, and the installed Codex CLI has ChatGPT authentication. Provider routing and the live trial are not yet verified. The new design cards are durable; they are not completed UI changes.

## 6. Next steps

Complete and review the adapter and caller integration; verify on main; restore HQ with background work held; announce and execute the single trial; inspect its actual result and commit; record the final card state and leave unrelated automation paused.

Raw evidence: current task 01a0c60d-2a78-7880-afd7-a34175409645; baseline logs above; live records will be under hq/data/runs/ with the exact run identifier recorded here.

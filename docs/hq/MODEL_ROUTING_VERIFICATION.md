# Verify HQ's temporary model routing

Engineering verification · Tiny Farm HQ

Date: 2026-09-21
Status: FINAL
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
| Background launch control | Timer stopped; HQ running with persisted background pause; only nominated work may run |

## 3. Questions and method

1. Does every execution entry point resolve the requested policy without accidental Claude fallback? Review call sites and run subprocess fixtures.
2. Are read-only/no-tool profiles, failure handling, quota boundaries and unknown costs represented accurately? Exercise normal, failed, limited, malformed and timed-out fake sessions.
3. Does a real card progress through worker, independent checker, visible Bullpen events, suites, patch application, commit, and durable completion? Run only the nominated ID with `--limit 1 --jobs 1`, no suite bypass, after committing implementation.

Poll local metadata/events at bounded intervals. Retain actual error output and invalid attempts. No timing/cost superiority claims or model-quality comparison will be inferred from this one task. The other model routes are fixture-tested unless explicitly recorded as exercised.

## 4. Findings and results

### Baseline — COMPLETE

All six existing HQ scripts returned exit 0 before implementation: test_drain.py, test_drain_resume.py, test_landing_bar.py, test_work.py, test_queue_night.py, test_decisions.py. Command output is retained in the interactive task. Game suite logs are `/tmp/hq-routing-checks/baseline-unit.log` and `/tmp/hq-routing-checks/baseline-integration.log`; unit results 2853 passed, 0 failed; integration results 968 passed, 0 failed. Both logs include existing shutdown resource-leak warnings; these are recorded rather than represented as new routing regressions.

### Adapter and integration — COMPLETE

Implementation was interrupted by an account usage limit; Daniel increased the limit and both workers resumed the same preserved worktrees. Adapter and consumers are committed as 411b027 and 2156049. Independent review caught and verified repairs for final-response parsing, native Claude continuation metadata, and explicit-card permissions after unpausing. All eight HQ test scripts passed on main; adapter has 10 tests and consumer coverage now has 9. Both main game suites initially passed (2853 unit, 968 integration). The live CLI cost summary exposed a misleading zero-dollar total; c63bd51 fixes all-unknown and mixed-cost formatting. Actual USD remains unavailable for these Codex calls.

### Supervised live run — COMPLETE

Run 20260921-161543-474c: Terra worker completed successfully in 46.7 seconds; Sol checker completed in 29.8 seconds and flagged a real documentation error: the guide described supervised trial work as the only launch exception, omitting explicit interactive calls and writing hooks. The patch was applied and suites started, but acceptance is correctly withheld. A same-card revision will preserve this finding. The same-card revision (20260921-162202-876b) passed independent model review, but its integration suite finished 967 passed and 1 failed: “there is an unmarked square to drag over.” The backend withheld the automatic commit. Read-only investigation found the scenario prepares x=13…19 on row 11 but searches unprepared random terrain at x=20…23; fixture repair f38efa5 subsequently supplied a prepared candidate and passed verification. The subsequent verification retry succeeded and landed the reviewed guide. Luna writing-check calls also succeeded and recorded provider=codex with unknown dollar price, rather than a fabricated zero.

### Separate pre-existing CI failure — RECORDED

CI run 35665001793 reports a demo replay freshness failure: regeneration changes only the header build_id. The prior main run 35664411769 was also failed. The bootstrap run additionally lacked verdicts for the newly filed card text; the routed writing hook has now judged that text. The demo-label problem is separately preserved as work card w1e498ecc2a0, not silently included in the provider change. Source: https://github.com/craklyn/tiny-farm-godot/actions/runs/35665001793 (failed job logs).

## 5. Conclusions

The adapter and consumer integration pass offline checks. Terra, Sol and Luna have executed real calls through the adapter; Astra and native Claude routing are fixture-tested only. Live worker and independent checker completed, including one requested correction. Verification retry passed both suites and the backend landed the guide as 6778c514f6996397b25380be918048cd2bc9ffca. The design cards are durable; they are not completed UI changes.

## 6. Next steps

Execute authorized redesign cards one at a time. Keep unrelated automation paused.

Raw evidence: current task 01a0c60d-2a78-7880-afd7-a34175409645; baseline logs above; live records will be under hq/data/runs/ with the exact run identifier recorded here.

### Verification retry after fixture repair — COMPLETE

The isolated fixture repair passed 2853 unit and 968 integration checks. Main unit verification also passed 2853 checks. The operator retry uses the existing drain.run_suites, meets_landing_bar and land functions, verifying the guide equals the exact bytes captured in the successful Sol review (Git blob 90701c56895246cda62c936bbe8a37470d097255). It preserves the prior failed suites and does not repeat model calls or increment attempt/token accounting. Evidence: /tmp/hq-routing-checks/reverify-trial.log and the card verification_history.

Final outcome: backend card state is landed; commit 6778c514f6996397b25380be918048cd2bc9ffca contains the reviewed quickstart. Main verification returned 2853 unit and 968 integration checks passed, zero failures. Original attempts (2), token accounting and independent review are preserved; verification_history retains the failed suites and successful retry. No redesign completion is implied.

Follow-up validation: changing the supervised nomination exposed a test-only dependency on the original pilot ID in test_execution.py. The fixture now supplies an isolated policy through the real loader, including snapshot/hook tests; all 10 adapter tests pass with both the normal and an alternate external policy. Production policy behavior is unchanged. Latest CI run 35669925386 confirms the remaining failure is only the separately recorded demo replay build_id mismatch.

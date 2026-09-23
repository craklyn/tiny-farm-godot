# Activate the convergence queue without splitting HQ's records

Date: 2026-09-22  
Status: LIVING — cutover not yet performed  
Owner: Chief of Staff  
Design: `docs/hq/CONVERGENCE_BUILD_PLAN.md`, Work Item E

## Contract

One HQ process uses four explicit filesystem roles:

| Role | Configured by | During this cutover |
|---|---|---|
| Checked-in HQ code and static files | The `hq/server.py` or `hq/drain.py` path in the service command | The durable clean integration checkout, not a `/tmp` test worktree |
| HQ records | `HQ_DATA_ROOT` | The **existing** `/home/daniel/dev/tiny-farm-godot/hq/data`; never a copied or empty store |
| Daniel's unfinished workspace | `HQ_USER_WORKSPACE_ROOT` | `/home/daniel/dev/tiny-farm-godot`, with every dirty file preserved |
| Authoritative local main / Git and test facts | `HQ_MAIN_ROOT` | The clean checkout whose local `refs/heads/main` the integration lane advances |

Without overrides, code, data, and both repositories keep their historical
locations. A relocated service must set all three roots and
`HQ_REQUIRE_EXPLICIT_ROOTS=1`; startup refuses a missing root or a data root
without `org.json`. `HQ_TEST_SCRATCH` is incompatible with explicit activation
roots. `HQ_PORT` defaults to 8642. The isolated canary uses `HQ_CANARY_MODE=1`
and `HQ_PORT=0`; it starts no worker, timer, CI, or recovery threads.

The server's main/Engineering Git facts and test-run buttons use
`HQ_MAIN_ROOT`. The sprite editor and animation lab use the user workspace for
unfinished assets. When those roots differ, a sprite edit is saved in the
user workspace and the live HQ ledger, but its old automatic commit/push is
disabled: a commit spanning two roots would be incomplete and a push of
Daniel's dirty branch would be unsafe. HQ's policy, cards, patches, worker
logs, transactions, rulings, and reconciliation manifests use `HQ_DATA_ROOT`.

## Gate before touching the live service

1. The integration-lane contract must match the checkout arrangement.
   `integration.handoff_status()` currently refuses any worktree with `main`
   checked out. A clean main-owning service checkout therefore cannot both
   serve current `HEAD`-based signals and pass the integration gate. Resolve
   this with a tested lane change; do **not** choose a detached stale service
   checkout and call its `HEAD` the current main.
2. Create an explicitly named durable clean checkout outside the dirty game
   project. Confirm its `HEAD`, local `main`, and the intended authoritative
   branch agree. Confirm the current user checkout is idle before the
   exact-HEAD branch handoff. Do not stash, reset, or edit its files.
3. Run `python3 hq/tests/test_activation_roots.py` and the full HQ suite.
   The test's data, repositories, and ephemeral HTTP port are disposable; it
   does not bind 8642 or read/write live cards. Repeat an offline canary with
   a **copy** of the live data root if schema compatibility needs proof.

## One-service-at-a-time cutover

The installed HQ service is currently
`/home/daniel/.config/systemd/user/tiny-farm-hq.service`; the installed drain
service is linked to `hq/systemd/tiny-farm-drain.service` in the original
checkout. Both must point at the same new code and environment. A live server
and a second server must never share the live data root concurrently.

Record before cutover: UTC time; card count in the live `work/` directory;
the weather card's `_revision` and SHA-256; the execution policy's
`background_paused` value; active drain/session state; `main` and
`origin/main` SHAs; the HQ service health response; and the exact old unit
contents. Keep automatic starts paused. Wait for a live drain to finish rather
than interrupting it; stop the timer, then stop the HQ service.

Configure **both** service commands to run `hq/server.py` and `hq/drain.py`
from the durable clean code checkout. Set, in both units:

```text
HQ_REQUIRE_EXPLICIT_ROOTS=1
HQ_DATA_ROOT=/home/daniel/dev/tiny-farm-godot/hq/data
HQ_USER_WORKSPACE_ROOT=/home/daniel/dev/tiny-farm-godot
HQ_MAIN_ROOT=<verified durable clean main checkout>
```

Do not set `HQ_CANARY_MODE` or `HQ_TEST_SCRATCH` in either live unit. Reload
systemd and start **one** HQ service. Read `/api/health`: its four root paths
must match the intended values. Recheck card count, the weather card's
revision/hash, and the paused queue from the live endpoint. Confirm that the
server's main SHA and the verified local-main SHA agree before treating an
Engineering signal or Run-button result as current. Only then consider
re-enabling the drain timer; the execution-policy pause remains the final
brake until the weather canary is deliberately dispatched.

Write the actual pre/post values and the unit revision in the build-plan
closeout. An offline green is not evidence that this live cutover happened.

## Rollback

If startup, root identity, card count/hash, or main identity differs from the
recorded preflight, leave automatic starts paused. Stop the new HQ service;
restore the saved original HQ and drain unit contents/links; reload systemd;
start only the original HQ service and recheck the same card count, weather
revision/hash, and health. Do not move or copy data: the store never migrated.
Do not resume unattended draining until the integration/main-root mismatch is
resolved. The original service may again describe the dirty user branch in
Engineering signals; treat that as a known rollback limitation, not a green
main verdict.

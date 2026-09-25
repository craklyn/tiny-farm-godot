# Activate the convergence queue without splitting HQ's records

Date: 2026-09-22  
Status: LIVING — cutover performed; unattended work remains paused
Owner: Chief of Staff  
Design: `docs/hq/CONVERGENCE_BUILD_PLAN.md`, Work Item E

> **Superseded for the data root, 2026-09-25.** Q-125 (a) moves `HQ_DATA_ROOT` from
> the shared checkout to HQ's own store, `/home/daniel/tiny-farm-hq-data`, and the
> checked-in unit templates now name it. `docs/hq/HQ_DATA_MIGRATION.md` is the runbook
> for that cut-over. The rest of this document still describes the other three roots.

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

1. The clean-main integration lane must already be in the code being
   installed. It now permits a **clean linked worktree** to own `main` and
   synchronizes that checkout after an exact-parent commit. It still refuses
   the dirty primary checkout or a stale/dirty main owner. Do not choose a
   detached service checkout and call its `HEAD` current main.
2. Use the durable path `/home/daniel/dev/tiny-farm-godot-main`, outside the
   dirty game project. The primary checkout must have completed its
   confirmed-idle, exact-HEAD branch handoff first. If the durable path does
   not yet exist, confirm no other worktree owns `main`, then create it with
   `git -C /home/daniel/dev/tiny-farm-godot worktree add
   /home/daniel/dev/tiny-farm-godot-main main`. Never stash, reset, or edit
   Daniel's files. Verify the new checkout is clean and that `HEAD` equals
   `refs/heads/main` before proceeding.
3. Run `python3 hq/tests/test_activation_roots.py` and the full HQ suite.
   The test's data, repositories, and ephemeral HTTP port are disposable; it
   does not bind 8642 or read/write live cards. Repeat an offline canary with
   a **copy** of the live data root if schema compatibility needs proof.

## One-service-at-a-time cutover

The installed HQ service is currently
`/home/daniel/.config/systemd/user/tiny-farm-hq.service`; the installed drain
service is linked to `hq/systemd/tiny-farm-drain.service` in the original
checkout. The checked-in replacement templates are
`hq/systemd/convergence/tiny-farm-hq.service` and
`hq/systemd/convergence/tiny-farm-drain.service`. The old drain unit and the
existing timer remain unchanged in the repository. Both installed service
units must point at the same new code and environment. A live server and a
second server must never share the live data root concurrently.

Record before cutover: UTC time; card count in the live `work/` directory;
the weather card's `_revision` and SHA-256; the execution policy's
`background_paused` value; active drain/session state; `main` and
`origin/main` SHAs; the HQ service health response; and the exact old unit
contents. Keep automatic starts paused. Wait for a live drain to finish rather
than interrupting it; stop the timer, then stop the HQ service.

The replacement units set these same three roots, use the durable clean
checkout for code and working directory, and require explicit roots:

```text
HQ_REQUIRE_EXPLICIT_ROOTS=1
HQ_DATA_ROOT=/home/daniel/dev/tiny-farm-godot/hq/data
HQ_USER_WORKSPACE_ROOT=/home/daniel/dev/tiny-farm-godot
HQ_MAIN_ROOT=/home/daniel/dev/tiny-farm-godot-main
```

Do not set `HQ_CANARY_MODE` or `HQ_TEST_SCRATCH` in either live unit. The
following commands are the **historical installation sequence, performed once
on 2026-09-22**. Do not rerun them: the backup directory now exists and the
new units are installed. They remain here to document the exact cutover and
rollback boundary. Do not stop an active drain midway through a worker
session—wait for it to finish first.

```bash
(
set -e
python3 -c 'import json; p="/home/daniel/dev/tiny-farm-godot/hq/data/execution_policy.json"; assert json.load(open(p))["background_paused"], "Pause automatic starts before cutover"'
test "$(git -C /home/daniel/dev/tiny-farm-godot-main symbolic-ref --short HEAD)" = main
test "$(git -C /home/daniel/dev/tiny-farm-godot-main rev-parse HEAD)" = "$(git -C /home/daniel/dev/tiny-farm-godot-main rev-parse refs/heads/main)"
test -z "$(git -C /home/daniel/dev/tiny-farm-godot-main status --porcelain)"
systemctl --user stop tiny-farm-drain.timer
if systemctl --user is-active --quiet tiny-farm-drain.service; then echo 'Drain still active; wait for it to finish.' >&2; exit 1; fi
test ! -e /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922
mkdir /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922
systemctl --user stop tiny-farm-hq.service
mv /home/daniel/.config/systemd/user/tiny-farm-hq.service /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922/tiny-farm-hq.service
mv /home/daniel/.config/systemd/user/tiny-farm-drain.service /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922/tiny-farm-drain.service
install -m 0644 /home/daniel/dev/tiny-farm-godot-main/hq/systemd/convergence/tiny-farm-hq.service /home/daniel/.config/systemd/user/tiny-farm-hq.service
install -m 0644 /home/daniel/dev/tiny-farm-godot-main/hq/systemd/convergence/tiny-farm-drain.service /home/daniel/.config/systemd/user/tiny-farm-drain.service
systemctl --user daemon-reload
systemctl --user start tiny-farm-hq.service
)
```

The existing `tiny-farm-drain.timer` stays stopped during validation. Read
`/api/health`: its four root paths
must match the intended values. Recheck card count, the weather card's
revision/hash, and the paused queue from the live endpoint. Confirm that the
clean checkout's `HEAD` equals `refs/heads/main` and the server's root is that
checkout before treating an Engineering signal or Run-button result as current.
Only then consider starting the drain timer; the execution-policy pause
remains the final brake until the weather canary is deliberately dispatched.
Do not start the old and new HQ commands at the same time.

The live cutover happened at 20:00:38 PDT on 2026-09-22. The post-cutover
`/api/health` named the durable main checkout, original data store, original
user workspace and durable main as their respective roots. The weather card
was read-stable under the new server. Three supervised worker/checker attempts,
one evidence-only review, and one zero-model landing retry all left the weather
game-code candidate unlanded. The last prospective full integration suite
failed outside Scenario W; five unmodified-main baseline repetitions passed.
None of these attempts altered Daniel's dirty game files. The measured values,
verification incidents and raw evidence are in
`docs/hq/CONVERGENCE_ACTIVATION_REPORT.md`. The timer remains stopped and the
policy remains paused until the canary's remaining verification is resolved.

## Rollback

If startup, root identity, card count/hash, or main identity differs from the
recorded preflight, leave automatic starts paused. Stop the new HQ service,
move the two new installed unit copies into the same backup directory, and
restore the saved originals:

```bash
(
set -e
systemctl --user stop tiny-farm-drain.timer
systemctl --user stop tiny-farm-hq.service
if test -e /home/daniel/.config/systemd/user/tiny-farm-hq.service; then mv /home/daniel/.config/systemd/user/tiny-farm-hq.service /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922/new-tiny-farm-hq.service; fi
if test -e /home/daniel/.config/systemd/user/tiny-farm-drain.service; then mv /home/daniel/.config/systemd/user/tiny-farm-drain.service /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922/new-tiny-farm-drain.service; fi
mv /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922/tiny-farm-hq.service /home/daniel/.config/systemd/user/tiny-farm-hq.service
mv /home/daniel/.config/systemd/user/tiny-farm-convergence-backup-20260922/tiny-farm-drain.service /home/daniel/.config/systemd/user/tiny-farm-drain.service
systemctl --user daemon-reload
systemctl --user start tiny-farm-hq.service
)
```

Recheck the same card count, weather revision/hash, and health. Do not move or
copy data: the store never migrated. Do not resume unattended draining on
rollback. The original service may again describe the dirty user branch in
Engineering signals; treat that as a known rollback limitation, not a green
main verdict.

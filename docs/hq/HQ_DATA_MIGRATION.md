# Move HQ's records into their own store, and close cards only through HQ

Date: 2026-09-25
Status: BUILT — the live cut-over below has not been performed yet
Owner: Chief of Staff
Ruling: Q-125 (a), "Keep HQ's records in a separate folder, and close cards only through HQ"

## Why

Every HQ work card existed twice. HQ read and wrote one copy in the shared checkout
(`/home/daniel/dev/tiny-farm-godot/hq/data`, on an old branch). Sessions that
finished work edited the other copy on main. Nothing copied changes between them, so
finished work kept showing as unfinished: on 2026-09-25, 23 of 26 held cards were
already done on main and had to be closed by hand.

After this change there is one copy of each record, and one way to close a card:

- **HQ's live records live in their own folder, `~/tiny-farm-hq-data`,** which is its
  own Git repository. HQ commits its own writes there, one commit per burst of writes,
  so the history is kept without anyone remembering (`hq/store.py`).
- **Main no longer carries live records.** `hq/.gitignore` ignores them, and
  `hq/tests/test_live_records.py` fails CI if a commit adds one back.
- **A session closes a card with `python3 hq/card.py close`.** HQ checks the evidence
  itself and refuses without it (`hq/closing.py`).
- **A session HQ did not launch can claim a card** with `python3 hq/card.py claim`, so
  the task queue shows it under "Working now" instead of "Next".
- **A ruling files its own work.** When Daniel picks an option on a decision card, HQ
  files an "Act on your ruling" card for the decision's owner at once. The task queue
  page lists every ruling not yet integrated until its status changes.

## What lives where

`hq/roots.py` holds these lists. The table gives the reason for each entry. "Writer"
is what writes the file while the studio runs, per the reader/writer survey of
`hq/*.py` and `tools/` done for this change.

### Live records: the store only (untracked on main)

| Entry | Writer | Why it is live |
|---|---|---|
| `work/` | HQ: `work.save_item` (server, drain, anim lab, close command) | The records Q-125 is about. |
| `rulings/` | HQ: `record_ruling` (POST /api/ruling); the close command marks one integrated | Daniel's words, written only by HQ. |
| `goals/` | HQ: `save_goal`, `set_commitment`, `park_goal`, `delete_goal` (POST /api/goal/*) | Edited on HQ's goal pages. Sessions change a goal through the same endpoints. |
| `staff/` | HQ: chat "remember", and owner-memory commits when a card lands or is accepted | HQ appends seat notes on its own. The chief of staff edits `staff/claude/memory.md` in the store. |
| `sprite_edits/` | HQ: `studio.record` (sprite editor save and revert) | Ledger of HQ edits. Its automatic commit is already off when the roots differ. |
| `anim_asks/`, `anim_runs/` | HQ: Animation Lab | Runtime state of the lab. |
| `maps/` | HQ: map editor (`save_map`) | HQ writes it. `tools/export_layout.gd` still writes into the repository path; copy an export into the store to use it. |
| `release_plan.json` | HQ: product plan (POST /api/product/plan) | Edited on HQ's product page. |
| `attestations.json` | HQ: web-play attestation (POST /api/web-play) | Written by HQ. |

### Runtime output: the store only (already ignored on main before this change)

`runs/`, `history/`, `patches/`, `outbox/`, `probes/`, `captures/`, `loop_previews/`,
`sprite_backups/` and `ci_history.json`. The store keeps `runs/workers/` (162 MB of
worker logs), `loop_previews/` and `sprite_backups/` on disk but out of its history.

### Checked in on main, read beside the code (one copy)

HQ never writes these. Sessions author them and commit them, so the one copy is main's.
In service HQ reads them from the checkout its code runs from
(`/home/daniel/dev/tiny-farm-godot-main/hq/data`). That checkout must be current,
which the deploy step already requires for code.

| Entry | Writer | Why it stays in the repository |
|---|---|---|
| `org.json`, `seats.json`, `pillars.json`, `surface.json`, `platforms.json` | Sessions, by hand | Configuration. `platforms.json` was already read beside the code. |
| `entities.json`, `releases.json` | Sessions, by hand | Static reference. The release manifest test checks `releases.json`. |
| `work_policy.json` | Sessions, by hand (HQ writes a default only when the file is missing) | The tiers as data. Seeded only into a data root that still holds its configuration. |
| `spend.json` | `tools/record_spend.py`, committed | A goal measures it through the repository path. |
| `decisions/` | Sessions and `tools/record_sound_candidates.py`, committed | HQ never writes decision cards, and CI checks their wording. HQ records Daniel's answer as a ruling in the store. HQ's "cards filed" count already reads their Git history on main. |
| `projects/` | Sessions, committed | HQ only reads them. Pillar feeds and "last touched" use their Git history on main. |
| `looks/` | `tools/compose_look_sheets.py`, committed | Design material attached to decision cards. |
| `completion_reconciliation.json`, `process_completion_reconciliation.json`, `card_state_migration.json`, `landed_commit_backfill.json` | Reviewed once, committed | Inputs to one-off reconciliation commands. |

**A deviation from the ruling's wording.** Option (a) listed "decisions" and
"projects" among the records to move. Neither has an HQ writer. Moving them would give
sessions a second place to write, which is the problem the ruling removes, and would
take decision-card wording out of CI's writing check. They stay on main as the one
copy. Daniel's answers to decisions (`rulings/`) do move.

### Seeded: tracked as a default, the store keeps its own copy

`execution_policy.json`. The pre-commit writing check, CI and a fresh clone need the
model routing, so the file stays on main. The running HQ reads and writes only the
store's copy. Its one live field, the automatic-work brake, changes through HQ's Pause
control. Committing the file does nothing to the running service.

### How HQ tells the two apart

`server.cfg()` resolves every checked-in entry. When the data root is its own Git
repository (the store), the checked-in entries come from beside the code. Otherwise,
as with the old in-repository data root and every test scratch store, they come from
the data root as before. So the code can deploy before the cut-over and behave exactly
as today until the service points at the store.

## Closing a card

```bash
python3 hq/card.py close w0123456789a --by "Codex session" \
    --sha 5ec460b --ci-run 36157944103 \
    --result "What changed, in plain sentences, with the commit."
```

The command posts to `POST /api/work/close`. HQ then does all of the following:

- **Checks the commit.** It fetches `origin/main` in its main checkout and refuses a
  commit that is not an ancestor of it.
- **Checks the CI run.** It reads the run from GitHub (`gh run view`) and refuses
  unless all three hold:
  - the run is the `tests` workflow;
  - the run has finished with conclusion `success`;
  - the run tested that commit, or a later main that contains it.
- **Checks the words.** It refuses an empty result. It refuses an attribution that
  claims Daniel or a checker.
- **Records the close.**
  - It sets `completion.kind: "session_close"` with the commit, the run and
    `"no checker or Daniel approval was recorded for this card"`.
  - It lands the card through `work.land_item`.
  - If the card is an "Act on your ruling" card, it marks the ruling `integrated`.

Follow-ups are filed as their own cards; the close command does not parse them from
prose.

## Claiming a card

```bash
python3 hq/card.py claim   w0123456789a --by "Codex session"            # default 120 minutes
python3 hq/card.py claim   w0123456789a --by "Codex session"            # again = still working
python3 hq/card.py release w0123456789a --by "Codex session"
```

A claim is a lease on the card (`outside_claim`: who, since, the last check-in, the
expiry).

- **While it is live:** the card is "Working now" on the task queue, and the drain
  does not start a worker on it.
- **When it lapses:** a session that stops checking in loses the claim, and the card
  returns to "Next".
- **Another session:** it cannot take a live claim, but it can take a lapsed one.
- **Closing:** closing the card clears the claim.

## Rulings file their own work

`record_ruling` files an "Act on your ruling: <decision> — you chose <option>" card.
The card is owned by the decision's owner, or by the chief of staff when the decision
has no owner. His comment is quoted on it.

- **Rulings from before a start:** HQ files the missing cards when it starts
  (`backfill_ruling_work`).
- **The queue page:** `/api/execution/queue` carries `rulings_waiting`. The task queue
  page (`#/work/queue`) opens with "N of your decisions are waiting to be acted on". The
  list is read from each ruling's status. A ruling leaves it only when it is integrated,
  not when a card exists or is dropped.
- **A revision request:** it files no card of this kind. It keeps its existing
  hand-off.

## Every card has a place

Added 2026-09-25 (work card w134a7424547). On the day of the cut-over, 36 open cards
were in no place at all, and nothing said so:

- 20 finished cards waited for review. The runner skipped them, because their next
  step was Daniel's verdict. His page left them off, because their code had no commit
  on main.
- 16 cards carried `queued` or `done`. HQ does not know either state, so nothing ran
  them and none reached him.
- About 60 closed cards were reported to him as still waiting for verification.

What changed:

- **Every card is checked.** `work.card_health` checks that every card:
  - has a state HQ knows;
  - is in exactly one place: closed, being worked, next for a worker, on Daniel's
    Work page, or held with a stated reason on the task queue;
  - if open, has one owner who is in `org.json`.
- **Failures go to the Engineering page.** `/api/work-health` lists them there, under
  "Work cards nobody will pick up". They are the studio's to fix, so Daniel's page
  never counts them.
- **An unknown state cannot be saved.** `work.save_item` refuses one. A legacy record
  already in such a state can still be saved without changing its state, so the
  service keeps running until the migration below has moved it.
- **Closed cards read as closed.** Daniel's queue checks for a closed card before
  anything else.
- **A `done` card can be closed with evidence.** `hq/card.py close` accepts one, and
  closing it makes it `landed`.
- **A one-time migration moves the unknown states.** `hq/migrate_card_states.py`
  applies the reviewed table in `hq/data/card_state_migration.json`. A card on main
  becomes `landed`, through the same evidence checks as `hq/card.py close`. A card
  whose ask later work already did becomes `dropped`, naming that work. A stranded
  review card whose work never reached main goes back to its owner's queue, with a
  brief saying what remains. An ask-first card becomes runnable only with Daniel's
  recorded yes. Without `--apply` the command writes nothing.

### Landed cards were counted as the studio's (2026-09-26)

The Engineering page's check counted 28 landed cards as closed. Daniel's queue page
listed the same 28 under "Back with the studio", marked "automated checks are not
confirmed". The page put a landed card under "Landed without you" only when the card
named its commit. These 28 had been closed by hand before HQ required evidence, so none
named one.

- **The page sorts closed cards by the check's own verdict.** `/api/work` now sends
  each card's lanes from `work.card_lanes`. A card in the closed lane never counts as
  the studio's. A landed card goes under "Landed without you" whatever evidence it
  carries, and its status line says what is missing. A reading says it changed no
  code. Any other card closed without a commit says that no commit is recorded.
- **A green run on a later main confirms a commit.** A push of several commits runs the
  tests once, on the last one, so most landed commits never got a run of their own.
  The CI poller now takes the earliest green run on main that contains the commit.
  `hq/card.py close` already accepted that run, and a close now records it where the
  page reads CI.
- **A one-time command adds the missing commits.** `hq/confirm_landed_commits.py` reads
  the reviewed table in `hq/data/landed_commit_backfill.json`. For each of 22 cards, it
  gives the commit that landed the card's work, found through the card's own history on
  main. It also gives a green `tests` run that contains that commit. The command checks
  both against Git and GitHub, then records them on the card. The table lists the six
  readings, which changed no code, and the command writes nothing to them. Without
  `--apply` it writes nothing.

## Cut-over

The live cut-over is the chief of staff's to perform. Before starting:

1. **Land the checked-in edits that exist only in the shared checkout.** The dry run
   on 2026-09-25 found the "ruled" annotations on decision cards Q-111, Q-117, Q-118,
   Q-119, Q-120 and Q-121 in the shared checkout only. After the cut-over HQ reads
   main's copies, so commit those annotations to main first. The migration also
   archives them under `archive/checked-in-at-migration/` in the store, so they cannot
   be lost.
2. **Do not switch the shared checkout's branch before the migration.** Main no longer
   tracks `hq/data/work`, `rulings`, and the rest. Checking out main in the shared
   checkout while it still holds the live store would delete every unmodified live card
   from disk. After the migration those files are stale copies, and switching is
   harmless.
3. Record the drain timer's state (`systemctl --user is-active tiny-farm-drain.timer`),
   the card count, and the HQ health response.

```bash
(
set -e
SRC=/home/daniel/dev/tiny-farm-godot/hq/data
DEST=/home/daniel/tiny-farm-hq-data
MAIN=/home/daniel/dev/tiny-farm-godot-main
BK=/home/daniel/.config/systemd/user/tiny-farm-q125-backup-20260925
test ! -e "$DEST"
test ! -e "$BK"
test -z "$(git -C "$MAIN" status --porcelain)"
git -C "$MAIN" fetch origin
git -C "$MAIN" merge --ff-only origin/main        # refuses if local main has diverged
test -f "$MAIN/hq/migrate_store.py"
python3 "$MAIN/hq/migrate_store.py" --source "$SRC" --dest "$DEST" --main "$MAIN" --dry-run
systemctl --user stop tiny-farm-drain.timer
if systemctl --user is-active --quiet tiny-farm-drain.service; then echo 'Drain still active; wait for it to finish.' >&2; exit 1; fi
systemctl --user stop tiny-farm-hq.service
python3 "$MAIN/hq/migrate_store.py" --source "$SRC" --dest "$DEST" --main "$MAIN"
mkdir "$BK"
cp ~/.config/systemd/user/tiny-farm-hq.service ~/.config/systemd/user/tiny-farm-drain.service "$BK/"
install -m 0644 "$MAIN/hq/systemd/convergence/tiny-farm-hq.service" ~/.config/systemd/user/tiny-farm-hq.service
install -m 0644 "$MAIN/hq/systemd/convergence/tiny-farm-drain.service" ~/.config/systemd/user/tiny-farm-drain.service
systemctl --user daemon-reload
systemctl --user start tiny-farm-hq.service
)
```

The only change to the installed units is one line in each:
`Environment=HQ_DATA_ROOT=/home/daniel/tiny-farm-hq-data`, replacing
`/home/daniel/dev/tiny-farm-godot/hq/data`. The migration never changes its source.

**Check it worked:**

- **Roots and records.** `curl -s localhost:8642/api/health` names the store as
  `data`, and the card count matches the one recorded before.
- **Waiting rulings.** On `#/work/queue`, the rulings not yet integrated are listed at
  the top.
- **The start-up log.** `journalctl --user -u tiny-farm-hq` shows `[rulings] filed
  work for N ruling(s)` when there were any.
- **History.** `git -C ~/tiny-farm-hq-data log --oneline` shows the import commit.
  About 25 seconds after any write, a `Record …` commit follows.
- **The drain timer.** Restart it only if it was active before:
  `systemctl --user start tiny-farm-drain.timer`.

**Right after the cut-over,** HQ files "Act on your ruling" cards for any ruling still
pending. On 2026-09-25 those were Q-122 to Q-125, which sessions were already building
under their own cards. When that work lands, close each ruling card with
`hq/card.py close`, using the same commit and CI run. That also marks the ruling
integrated. Do not drop them: the ruling stays on the page until it is integrated.

## Rollback

The source store is untouched, so rolling back only needs to carry back what was
written since the cut-over:

```bash
(
set -e
SRC=/home/daniel/dev/tiny-farm-godot/hq/data
DEST=/home/daniel/tiny-farm-hq-data
BK=/home/daniel/.config/systemd/user/tiny-farm-q125-backup-20260925
systemctl --user stop tiny-farm-drain.timer
systemctl --user stop tiny-farm-hq.service
rsync -a --exclude .git --exclude .gitignore --exclude .hq-store --exclude archive/ "$DEST/" "$SRC/"
cp "$BK/tiny-farm-hq.service" "$BK/tiny-farm-drain.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user start tiny-farm-hq.service
)
```

The new code runs unchanged against the old data root: that root is not its own
repository, so HQ reads checked-in files from it as before and commits nothing. Leave
`~/tiny-farm-hq-data` in place until the rollback is confirmed.

## Dry run, 2026-09-25

The dry run was made against a copy of the live store, taken at 10:20 PDT, with main
at 5ec460b.

- **Files:** 1,268 files, 176 MB, 162 MB of them worker logs.
- **Copied:**
  - live: `anim_asks`, `anim_runs`, `attestations.json`, `goals`, `maps`,
    `release_plan.json`, `rulings`, `sprite_edits`, `staff`, `work`
  - runtime: `captures`, `ci_history.json`, `history`, `loop_previews`, `outbox`,
    `patches`, `probes`, `runs`, `sprite_backups`
  - seeded: `execution_policy.json`
  - one unrecognised entry, `server.nohup.log`, copied as it was and kept out of
    history
- **Archived and read from main instead:** the 14 checked-in entries.
- **Different from main:** 7 checked-in files. The decision cards Q-111 and Q-117 to
  Q-121 carry "ruled" annotations that were never committed. `platforms.json` differs
  too, but HQ already read it from main.
- **Cards and rulings where main and the live copy disagree:** 46. In every one the
  live copy is further on: 42 cards closed in HQ and still open on main, and 4 rulings
  integrated in HQ and still pending on main. Nothing is finished on main and open in
  HQ, so dropping main's copies loses nothing.
- **The real run into scratch:** import commit, 1,268 files, 0 checksum mismatches,
  7.5 MB of history.
- **This worktree's HQ served against that store** on a spare port, in canary mode:
  - It filed four "Act on your ruling" cards at start (Q-122 to Q-125).
  - Two claimed cards showed under "Working now".
  - The close command refused, in turn: a failed CI run, an empty result, an
    attribution of "Daniel", and a commit that does not exist. It then landed a card
    with commit 5ec460b and run 36157944103, which marked Q-125 integrated in the
    copy.
  - A ruling posted to `/api/ruling` filed its card at once.
  - The store recorded each burst as its own commit.

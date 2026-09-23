Investigation · Tiny Farm

# Reconcile the shared checkout

- Date: 2026-09-23
- Status: LIVING
- Last updated: 2026-09-23
- Repo/location: `/home/daniel/dev/tiny-farm-godot` (`codex/shared-work-20260922`)

## Background

Parallel work left the Local checkout on a divergent branch with committed and
uncommitted changes. New work can start from the clean `main` checkout, but the
shared checkout cannot be reset until its distinct work and records have been
accounted for. The rule for this reconciliation is to move one verified result
at a time onto current `main`, preserving the source checkout throughout.

## Context and questions

At the first inventory, `main` and `origin/main` both pointed to `4357f42`.
The shared branch pointed to `a9bc15c`, with 18 branch-only commits and 77
main-only commits. Its working tree had 101 changed tracked paths and 129
untracked files. Of those, 71 changed and 23 new paths were HQ work cards.
Four rulings still said `pending_integration`: Q-108, Q-109, Q-111, Q-92.
[^inventory]

1. Which branch commits contain work absent from `main`?
2. Which uncommitted changes are complete, verified, and authorized to land?
3. Which files are generated, historical evidence, or still active work?

[^inventory]: `git rev-list --left-right --count main...HEAD`, `git status
    --porcelain=v1 -uall`, `git diff --name-only`, `git ls-files --others
    --exclude-standard`, and `hq/data/rulings/*.json` in the shared checkout,
    2026-09-23. The original state is preserved in
    `/tmp/tiny-farm-shared-reconcile-20260923.patch` and
    `/tmp/tiny-farm-shared-reconcile-20260923-untracked.tar.gz`.

## Method

`git cherry main HEAD` identifies nine patch-equivalent branch commits and
nine with patches not matched by Git on `main`. Patch equivalence alone is
not a product verdict: the branch-only commits are compared against current
files and their HQ cards. Each candidate is applied to an isolated checkout
at `/tmp/tiny-farm-reconcile-main`, checked, then committed there. No bulk
merge or reset is part of this method. [^cherry]

[^cherry]: `git cherry main HEAD` in the shared checkout, 2026-09-23.

## Findings

### Branch-only commits — RUNNING

| Commit | Change | Disposition |
| --- | --- | --- |
| `58aae22`, `224c715` | Work-card text wrapping and stylesheet reference | Already present: the final `index.html` and `work.css` on the shared branch are byte-identical to `main`. |
| `2d699fe` | Integration waits for movement and placement | Reconciled as `9529228`; 1,010 integration assertions passed with fresh save data. |
| `b1887f5` | Shared animation-file reader for watering and night | Reconciled as `9b9c299`; 2,943 unit and 1,009 integration assertions passed, plus gateway |
| `9a9b4ad`, `13f13bd` | Remove the retired obstacle atlas from the HQ map and playtest view | Reconciled as `e93714a`; every old atlas cell matches its individual replacement, the chip generator reproduces its sheets, and game and HQ suites pass. |
| `dbe3529`, `2d0a4ea` | Ground-sheet sprite editor changes, including a restore after concurrent edits | Reconciled as `9e46edd`; the editor now shows and saves the nine cells the renderer uses. HQ 45/45 and both game suites passed. |
| `df5fc46` | Earned robot unlocks | Already represented by `35714f2` and later mainline code; the shared branch uses the older seed/crop save schema and cannot supply this patch directly. |

The card for the shared animation reader was copied to the isolated checkout
and updated with current verification. The original branch remains unchanged.
[^animation]

[^animation]: `git show b1887f5`, `git show 9b9c299`,
    `/tmp/tiny-farm-reconcile-unit.log`,
    `/tmp/tiny-farm-reconcile-integration.log`, and
    `python3 tools/check_gateway.py` in the isolated checkout.

The first run of the test-wait patch reused the earlier suite's save-data
directory. Its startup isolation check failed while all 1,009 scenarios
passed. A fresh `XDG_DATA_HOME` run passed 1,010/1,010; only that fresh run
is valid evidence for the patch. [^waits]

[^waits]: `git show 2d699fe`, `git show 9529228`,
    `/tmp/tiny-farm-reconcile-integration-waits.log` (invalid fixture), and
    `/tmp/tiny-farm-reconcile-integration-waits-fresh.log` (valid run).

The retired atlas's thirteen 16×16 cells match the corresponding cells in
`obstacle_rock.png`, `obstacle_log.png`, `obstacle_weed.png`,
`obstacle_tree.png`, `fence.png`, `hedge.png`, and `gate.png`. The revised
generator left all three chip sheets byte-identical. Current tests passed:
2,943 unit, 1,010 integration, and 44 of 44 HQ test files. [^obstacles]

[^obstacles]: `/tmp/tiny-farm-old-obstacles.png`, `git show e93714a`,
    `/tmp/tiny-farm-reconcile-unit-obstacles.log`,
    `/tmp/tiny-farm-reconcile-integration-obstacles.log`, and
    `/tmp/tiny-farm-reconcile-hq-obstacles.log`.

### Uncommitted work — RUNNING

| Area | Evidence | Disposition |
| --- | --- | --- |
| Save build history | The focused change is on `main` as `4357f42`, with a green GitHub Actions rerun. | Code already present; the later HQ card record is reconciled as `9a9ce71`. |
| Store-page rewrite [^store] | `ITCH_PAGE.md` is claimed by an accepted card, but the draft says the unreleased v0.2.2 text is live. | TK — compare copy with actual release state before landing. |
| White-edge sprite processing [^white] | The helper and four synthetic checks exist in `tools/asset_pipeline/`, but the two builders import only `key_background`; neither invokes the new removal or final check. | Incomplete; wire and verify before landing. |
| Ground-sheet sprite editor [^ground] | The original card said to copy the center cell over all nine, but the current renderer selects all nine by tile position. | Reconciled against current behavior; the card retains its stale earlier claim and records the corrected result. |
| Returning-work list | The shared checkout added spacing and labels for the existing return strip, with four focused assertions. | Recovered as `3c0886d`; all 45 HQ test files pass. The broader reader card was already landed and has separate open concerns. |
| Five playtest sessions [^playtests] | Each replay is distinct; all fifteen files parse as JSON lines and match the shared checkout by SHA-256. | Preserved as `9dc003b`, with the older-version note in `playtests/README.md`; the blocked card now records the successful recovery. |
| Rulings, HQ ledger, art, experiments | 71 modified work cards, 23 new work cards, plus untracked assets. | TK — reconcile decisions and records by owner; preserve raw evidence. |

[^store]: `hq/data/work/wadf051cd6c7.json`, `ITCH_PAGE.md`, and
    `docs/RELEASE_NOTES.md` in the shared checkout.
[^white]: `hq/data/work/w6ef64f2e6dd.json`,
    `tools/asset_pipeline/postprocess.py`,
    `tools/asset_pipeline/check_postprocess.py`, and the two
    `assets/raw/*/build_*.py` scripts in the shared checkout.
[^ground]: `hq/data/work/wf6c0837f914.json`, `git show dbe3529`,
    `git show 9e46edd`, and `world/farm.gd`'s `tx % GROUND_VARIANTS` draw path.
[^playtests]: `git show 9dc003b`, `playtests/README.md`, and
    `hq/data/work/w9b3289d1a04.json` in the isolated checkout. The five
    session folders are named in that card.

## Conclusion and next steps

The checkout contains recoverable work. The first distinct branch change is
verified against current `main`; the white-edge item shows why an HQ state or a
plausible helper file cannot by itself establish completion. Continue with
the remaining candidates in small groups. Keep the shared checkout and its
snapshot until every source path and untracked artifact has a disposition.

1. **DONE:** All nine branch-only commits have a disposition: their result is
   already on `main`, or the distinct work has been recovered and tested.
2. **TK:** Finish or hold the uncommitted code and content by work card;
   distinguish accepted copy from a published release.
3. **TK:** Reconcile rulings and HQ records, then classify raw assets,
   experiments, playtest evidence, and generated sidecars.
4. **TK:** After verification, align the Local checkout with `main` and
   confirm a clean status. Only then retire the shared branch and snapshot.

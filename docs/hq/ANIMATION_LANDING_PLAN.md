# Land finished Animation Lab loops without a handoff

Date: 2026-09-24 (revised from the reviewed 2026-09-22 candidate)
Status: DECIDED; IMPLEMENTATION NOT STARTED
Owner: HQ Engineering (Ravi for the asset pipeline; Adam for work-state wording)

## Outcome

A standard Animation Lab run will record exactly what it finished. The scheduled work drain will verify those files, export the game sheet and manifest, commit them to local main, and push that commit to origin/main without a person collecting them. Daniel still judges the animation in the Animation Lab; that judgment is about whether the studio keeps using the work, not whether somebody remembers to save it.

This extends the drain's existing exact-candidate landing path. Animation runs do not create branches. They share one working tree so they can run in parallel, and branches would add a second landing system while leaving pasted prompt sessions outside it.

## Current gap

The animation prompt correctly forbids `git add` and `git commit` because several drawing sessions may edit the same working tree. A finished run leaves its script and rendered directory in place and says that the Chief of Staff will land them. Nothing performs that handoff.

The work drain already solves the nearest problem: it names the files owned by one result, checks the exact candidate, stages only those files, and commits only after the candidate still matches. Animation landing should use that machinery rather than teach drawing sessions to operate Git. `hq/integration.py` advances **local** main by compare-and-swap; it does not push origin/main. `hq/anim.py` currently calls a run done after a successful agent exit and a reported slug, then files an art review. It does not snapshot, validate, export, or land that run.

## Decision

Each run calls a shared finish helper after its final render and checks succeed. Dashboard draws and reworks must call it before marking the run done or filing review; a manual prompt session must call the same helper explicitly. It atomically writes a versioned completion receipt keyed by run ID and generation. The receipt names the slug, script, complete owned file list, recorded parameter values, prior generation for rework, source revision, and SHA-256 of each file. The helper copies the exact bytes into a durable content-addressed spool under HQ data, checking each source hash before and after copying. A changed file aborts capture. A later edit in the shared checkout cannot silently change a completed receipt. Failed or cancelled runs write no receipt. Directory discovery or `params.json` alone never signals completion.

The allowlist includes `tools/experiments/vfx_<slug>.py`, every regular file in `tools/experiments/out/<slug>/`, and, when the script uses them, its editable `prep_<slug>.py` and `assets/showcase/<slug>/` source files. Reject symlinks, path escapes, missing literal asset dependencies, or a path another active run is changing. Shared notes, credits, raw generations, and spend records remain ordinary isolated work items, not files a collector silently scoops up.

The scheduled drain collects unlanded receipts before selecting ordinary work cards. For each receipt it:

1. Rejects any path outside the exact script, render, and optional editable source allowlist above.
2. Confirms the animation name, script path, output path, and recorded hashes agree.
3. Recreates a candidate in an isolated checkout using the receipt's spooled bytes. Runs the script into scratch with its recorded values; checks a successful exit, `params.json`, required sheet/GIF/contact sheet, frame count, palette, binary alpha, seam and deterministic output hashes. Runs `tools/export_anim_loop.py <slug>` in that candidate, verifies the exported sheet against the source sheet and the manifest against params and GIF timing, and includes `assets/anim/<slug>/sheet.png` and `manifest.json` in the exact candidate. Any game splash or extra derived file must be named and verified by the export contract.
4. Checks the receipt's source revision against each path on main. If a main-side path changed to a different blob, hold it as a same-path conflict; never overwrite that edit. The shared checkout may be dirty on unrelated paths without affecting capture or landing.
5. Fetches origin/main and requires local main to contain it. Builds a candidate from current local main plus the receipt's fixed blobs and derived export, binds it to that HEAD and its resulting tree, then runs the applicable import and test gates on that exact tree. The existing exact-candidate transaction creates one revertable local commit only if main and the validated tree still match. It then makes an ordinary fast-forward push while holding the single-writer lock. The receipt is `landed` only after origin/main is observed to contain that SHA. Repeated passes are idempotent.

The receipt fixes finished file contents, not the eventual parent commit. For each receipt, the drain starts a temporary index from current main, inserts only its fixed blobs and regenerated export, and writes a candidate tree. A changed HEAD invalidates that temporary candidate: discard it, reconstruct against the new HEAD, and rerun validation before committing. This lets an earlier receipt land first without weakening the fixed-HEAD check. A missing or corrupt spool blob holds the receipt. Diverged local and remote history, rejected push, or a network failure leaves a named `push_pending`/reconciliation state with its local commit SHA; retry fetches and checks ancestry before pushing, never resets or force-pushes.

Landing happens when the run is technically complete, before Daniel's art verdict. The exported sheet is stored in `assets/anim/` but is not wired into a player scene by this transaction. A rejected loop therefore remains a revertable, inspectable record instead of uncommitted work that another landing can accidentally sweep up. Daniel's keep, rework, or drop action continues through the Animation Lab's recorded review flow.

## Boundaries

- A drawing session never runs Git commands.
- A directory with `params.json` but no completion receipt is not finished. The script writes that file during iteration, so directory discovery alone can collect a partial pass.
- The drain stages receipt files by exact name. It never stages `tools/experiments/`, an animation output parent directory, or the whole working tree.
- Two unfinished receipts that name the same path conflict unless they are successive generations of one slug. A rework waits for its predecessor to land or be explicitly superseded; it cannot overtake it.
- `ANIMATION_NOTES.md`, `CREDITS.md`, spend records, raw generations, and unrelated shared or shipped paths are not part of this automatic lane. A subject that needs those files runs as an ordinary isolated work item through the existing drain. The loop's own `assets/showcase/<slug>/` editable source is included only when the receipt names and hashes it.
- A failed render, missing file, changed hash, malformed receipt, overlapping path, failed commit, or failed push leaves the receipt unlanded with a concrete reason. It does not start another model run or claim a remote landing.
- Rework produces a new receipt for the same animation. It may land only after the earlier receipt has landed or been explicitly superseded, and its hashes must describe the whole new candidate.

## Implementation

Ravi owns this because it is an asset-pipeline handoff built on the drain's deploy machinery. Adam owns the work-state wording and confirms that the Animation Lab review does not imply that an unlanded candidate is safely stored.

The implementation changes `hq/anim.py`, `hq/drain.py`, `tools/export_anim_loop.py`, the animation prompt, and focused tests. Keep receipt parsing and candidate validation in a small shared module so the Animation Lab writer and drain reader use one schema without importing the server. Persist checkpoints before commit and push; recovery checks commit trailers and ancestry by run ID and generation before creating anything again.

Tests cover a new loop, rework, repeated drain pass, stale or corrupted spool hash, partial directory without a receipt, malformed or escaping paths, two runs claiming one path, unrelated dirty file, render and export failure, changed main, commit and push failures, and crash recovery. The acceptance run starts fixture animations A and B against one dirty working tree, then completes B before A. The collector deliberately lands A first, opposite completion order. It then rebuilds B from A's new commit plus B's recorded blobs and lands B separately. Each commit must contain its own exact source, render and export blobs, B must retain A, neither may contain the unrelated edit, and origin must contain both. A companion race test moves HEAD after candidate binding and requires revalidation on the new base.

## Completion record

The automation is complete when the scheduled drain has landed the two-animation acceptance run on origin/main without an operator command, each Animation Lab run links to its commit, and restarting the drain creates no duplicate commit. This document completes only the design requested by card `wca6d418ab35`; it is not evidence that automation is operating.

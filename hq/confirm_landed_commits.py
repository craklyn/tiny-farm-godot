#!/usr/bin/env python3
"""Record the commit and the green CI run on landed cards that were closed without them.

On 2026-09-25 twenty-eight landed cards showed on Daniel's queue page under
"Back with the studio", marked "automated checks are not confirmed". They had
been closed by hand before HQ required evidence, so none carried the commit that
landed the work, and HQ's CI poller only confirms a card that names its commit.
Each was traced to its commit on origin/main through the card's own history on
main, and paired with the earliest green ``tests`` run on main that contains it.
The reviewed table is hq/data/landed_commit_backfill.json; this command applies
it once.

Read-only unless --apply. Every entry is checked before the first write:

* the card is landed, and records no commit or this same one;
* the commit is on origin/main and the CI run is the ``tests`` workflow,
  finished with success on it or on a later main that contains it — both read
  from Git and GitHub the way ``hq/card.py close`` reads them (hq/closing.py).

Applying adds the commit to the card's landed record, with an audit saying who
recorded it and why, and records the run through the same path a session close
uses (action_dispatch.record_verified_ci), so the page shows the checks as
confirmed. Nothing else on the card changes, and no checker or Daniel approval
is claimed. The manifest also lists the landed readings, which changed no code:
they are reported, never written.

  HQ_DATA_ROOT=/home/daniel/tiny-farm-hq-data \\
  HQ_MAIN_ROOT=/home/daniel/dev/tiny-farm-godot-main \\
      python3 hq/confirm_landed_commits.py            # preview
      python3 hq/confirm_landed_commits.py --apply    # write
"""
import argparse
import json
from pathlib import Path

import action_dispatch
import closing
import roots
import work
from reconcile_process_completion import FileHost

MANIFEST = "landed_commit_backfill.json"


def _load_manifest(manifest):
    if manifest is None:
        manifest = work._host_cfg(MANIFEST)
    if isinstance(manifest, (str, Path)):
        with open(manifest, encoding="utf-8") as source:
            manifest = json.load(source)
    return manifest


def _applied(item, sha):
    ci = (item.get("workflow") or {}).get("ci") or {}
    return bool(sha and action_dispatch.landed_sha(item) == sha
                and ci.get("confirmed") and ci.get("commit_sha") == sha)


def confirm(manifest=None, *, apply=False, main_root=None, run=None, fetch=True):
    """Preview (default) or apply the reviewed table. Returns a report."""
    run = run or closing._run
    manifest = dict(_load_manifest(manifest))
    manifest_id = work.evidence_id(manifest)
    by = closing._attribution(manifest.get("by"))
    entries = manifest.get("cards") or []
    errors, rows, verified = [], [], {}
    if fetch and main_root:
        got = run(["git", "fetch", "--quiet", "origin", "main"], main_root)
        if got.returncode:
            errors.append("could not fetch origin/main: " + (got.stderr or "").strip()[:200])
    ids = [e.get("id") for e in entries] + [e.get("id") for e in manifest.get("no_code") or []]
    if len(set(ids)) != len(ids):
        errors.append("the manifest lists a card twice")
    by_id = {item["id"]: item for item in work.items(strict=True)}
    for entry in entries:
        cid = entry.get("id")
        item = by_id.get(cid)
        if item is None:
            errors.append(f"{cid}: no such card")
            continue
        if item.get("state") != "landed":
            errors.append(f"{cid}: is {item.get('state')!r}, not landed")
            continue
        if not str(entry.get("reason") or "").strip():
            errors.append(f"{cid}: give the reason this commit is the card's")
            continue
        try:
            full = closing.verify_commit(entry.get("sha"), main_root, run=run, fetch=False)
            ci = closing.verify_ci(entry.get("ci_run"), full, main_root, run=run)
        except closing.Refused as exc:
            errors.append(f"{cid}: {exc}")
            continue
        recorded = action_dispatch.landed_sha(item)
        if recorded and recorded != full:
            errors.append(f"{cid}: already records commit {recorded[:12]}, not {full[:12]}")
            continue
        verified[cid] = (full, ci)
        rows.append({"id": cid, "title": item.get("title", ""), "sha": full[:12],
                     "ci_run": ci["id"], "ci_head": ci["head_sha"][:12],
                     "already_applied": _applied(item, full)})
    readings = []
    for entry in manifest.get("no_code") or []:
        cid = entry.get("id")
        item = by_id.get(cid)
        if item is None or item.get("state") != "landed" or action_dispatch.landed_sha(item):
            errors.append(f"{cid}: listed as a reading, but it is not a landed card without a commit")
            continue
        view = work.work_view(item, {}, now=0)
        if not (view.get("shipped_evidence") or {}).get("no_code"):
            errors.append(f"{cid}: listed as a reading, but HQ does not read it as one "
                          "(tier 0 or a reading completion)")
            continue
        readings.append({"id": cid, "title": item.get("title", ""), "reason": entry.get("reason", "")})
    report = {"applicable": not errors, "applied": False, "errors": errors,
              "manifest_id": manifest_id, "cards": rows, "readings": readings}
    if errors or not apply:
        return report
    for cid, (full, ci) in verified.items():
        with work.mutation_lock():
            item = work.load_item(cid)
            if item.get("state") != "landed":
                raise closing.Refused(f"{cid} changed state during the run")
            if not action_dispatch.landed_sha(item):
                landed = dict(item.get("landed") or {})
                landed.setdefault("at", item.get("closed") or work._now_iso())
                landed.setdefault("by", by)
                landed["sha"] = full
                item["landed"] = landed
                item["commit_backfill"] = {
                    "version": 1, "manifest_id": manifest_id, "at": work._now_iso(), "by": by,
                    "sha": full, "ci_run": ci["id"], "ci_head": ci["head_sha"],
                    "reason": next(e["reason"] for e in entries if e.get("id") == cid),
                    "limitations": "Recorded after the card closed; no checker or Daniel "
                                   "approval was recorded for this card."}
                work.save_item(item)
            action_dispatch.record_verified_ci(work, cid, full, ci)
    report["applied"] = True
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true",
                        help="write the reviewed commits and runs; without this flag nothing is written")
    parser.add_argument("--data-root", type=Path, default=Path(roots.ROOTS["data"]),
                        help="HQ's store (default: HQ_DATA_ROOT)")
    parser.add_argument("--main-root", default=roots.ROOTS["main"],
                        help="the checkout whose origin/main the commits are checked against")
    parser.add_argument("--manifest", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    work.bind(FileHost(args.data_root), sanitize=False)
    report = confirm(args.manifest, apply=args.apply, main_root=args.main_root)
    print(json.dumps(report, indent=2))
    return 0 if report["applicable"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

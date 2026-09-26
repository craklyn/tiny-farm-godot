#!/usr/bin/env python3
"""Move work cards out of states HQ does not know, per a reviewed manifest.

On 2026-09-25 sixteen cards carried 'queued' or 'done', neither of which is in
work.STATES: nothing ran them and none reached Daniel (w134a7424547). Each was
reviewed against origin/main and given a target in
hq/data/card_state_migration.json. This command applies that table once. The
same table may send a stranded review card back to its owner's queue: a
'for_review' card in no lane (work.card_lanes) whose work never reached main.

Read-only unless --apply. Every card is checked before the first write:

* it is still in the state the manifest reviewed, or already migrated by it;
* the target is a state HQ knows, and no card in an unknown state is left
  out of the manifest;
* 'landed' carries a commit on origin/main and a green ``tests`` run that
  contains it, checked the same way ``hq/card.py close`` checks them — the
  card is then closed through ``closing.close``, so it records that no checker
  or Daniel approval was given;
* an ask-first (tier 2) card never becomes runnable without a recorded yes;
* a stranded review card goes back only at the revision it was reviewed at,
  and only with the brief that says what remains.

  HQ_DATA_ROOT=/home/daniel/tiny-farm-hq-data \\
  HQ_MAIN_ROOT=/home/daniel/dev/tiny-farm-godot-main \\
      python3 hq/migrate_card_states.py            # preview
      python3 hq/migrate_card_states.py --apply    # write
"""
import argparse
import json
from pathlib import Path

import closing
import roots
import work
from reconcile_process_completion import FileHost

MANIFEST = "card_state_migration.json"
TARGETS = ("landed", "dropped", "prepping", "waiting_session")
_RUNNABLE = ("waiting_session", "doing")


def _load_manifest(manifest):
    if manifest is None:
        manifest = work._host_cfg(MANIFEST)
    if isinstance(manifest, (str, Path)):
        with open(manifest, encoding="utf-8") as source:
            manifest = json.load(source)
    return manifest


def _applied(item, entry, manifest):
    """Moved by this manifest already: its audit is on the card and the card is
    in the target state (a close that failed half-way is not 'applied')."""
    return bool(item and item.get("state") == entry.get("to")
                and (item.get("state_migration") or {}).get("manifest_id") == manifest["_id"])


def _check_entry(entry, item, manifest, main_root, verify, run):
    """Errors that stop this entry, or [] when it may be applied."""
    card_id, target = entry.get("id"), entry.get("to")
    if item is None:
        return [f"{card_id}: no such card"]
    if _applied(item, entry, manifest):
        return []
    errors = []
    if entry.get("expected_state") == "for_review":
        if target != "waiting_session" or not str(entry.get("repair_brief") or "").strip():
            errors.append(f"{card_id}: a stranded review card may only go back to its owner's "
                          "queue, with the brief that says what remains")
        if item.get("_revision", 0) != entry.get("expected_revision"):
            errors.append(f"{card_id}: changed since it was reviewed (revision "
                          f"{item.get('_revision', 0)}, reviewed at {entry.get('expected_revision')})")
    elif entry.get("expected_state") in work.STATES:
        errors.append(f"{card_id}: the manifest may only move cards out of unknown states")
    if item.get("state") != entry.get("expected_state"):
        errors.append(f"{card_id}: is now {item.get('state')!r}, not the reviewed "
                      f"{entry.get('expected_state')!r}")
    if target not in TARGETS:
        errors.append(f"{card_id}: target {target!r} is not one of {', '.join(TARGETS)}")
    if not str(entry.get("reason") or "").strip():
        errors.append(f"{card_id}: give the reason for the move")
    if work.pending_conversation(item):
        errors.append(f"{card_id}: a reply to Daniel is still pending on this card")
    if target in _RUNNABLE and str(item.get("tier")) == "2" and not item.get("approved"):
        errors.append(f"{card_id}: an ask-first card cannot become runnable without his yes")
    if target == "waiting_session" and str(item.get("tier") or 0) == "0":
        errors.append(f"{card_id}: a reading card (tier 0) is run by HQ's own worker, not the build queue")
    if target == "landed":
        if len(str(entry.get("result") or "").strip()) < 20:
            errors.append(f"{card_id}: a landed card needs its result text")
        if verify and not errors:
            try:
                full = closing.verify_commit(entry.get("sha"), main_root, run=run, fetch=False)
                closing.verify_ci(entry.get("ci_run") or manifest.get("ci_run"), full, main_root, run=run)
            except closing.Refused as exc:
                errors.append(f"{card_id}: {exc}")
    return errors


def migrate(manifest=None, *, apply=False, main_root=None, verify=True, run=None):
    """Preview (default) or apply the reviewed moves. Returns a report."""
    run = run or closing._run
    manifest = dict(_load_manifest(manifest))
    manifest["_id"] = work.evidence_id({k: v for k, v in manifest.items() if k != "_id"})
    by = manifest.get("by") or ""
    entries = manifest.get("cards") or []
    with work.mutation_lock():
        by_id = {item["id"]: item for item in work.items(strict=True)}
        listed = {entry.get("id") for entry in entries}
        errors = [f"{card_id}: in unknown state {item.get('state')!r} but not in the manifest"
                  for card_id, item in sorted(by_id.items())
                  if item.get("state") not in work.STATES and card_id not in listed]
        if len(listed) != len(entries):
            errors.append("the manifest lists a card twice")
        if verify and main_root and any(e.get("to") == "landed" for e in entries):
            got = run(["git", "fetch", "--quiet", "origin", "main"], main_root)
            if got.returncode:
                errors.append("could not fetch origin/main: " + (got.stderr or "").strip()[:200])
        rows = []
        for entry in entries:
            item = by_id.get(entry.get("id"))
            errors += _check_entry(entry, item, manifest, main_root, verify, run)
            rows.append({"id": entry.get("id"), "title": (item or {}).get("title", ""),
                         "from": entry.get("expected_state"), "to": entry.get("to"),
                         "already_applied": _applied(item, entry, manifest)})
        if errors or not apply:
            return {"applicable": not errors, "applied": False, "errors": errors,
                    "manifest_id": manifest["_id"], "cards": rows}
        for entry in entries:
            item = work.load_item(entry["id"])
            if _applied(item, entry, manifest):
                continue
            audit = {"version": 1, "manifest_id": manifest["_id"], "at": work._now_iso(),
                     "by": by, "from": item.get("state"), "to": entry["to"],
                     "reason": entry["reason"]}
            if entry["to"] == "landed":
                # The same close a session makes, so the card carries the same
                # evidence and the same "no checker or Daniel approval" line.
                item = closing.close(entry["id"], sha=entry["sha"],
                                     ci_run=entry.get("ci_run") or manifest.get("ci_run"),
                                     result=entry["result"], by=by, main_root=main_root,
                                     run=run, fetch=False)
                item["state_migration"] = audit
                work.save_item(item)
                continue
            item["state_migration"] = audit
            item["state"] = entry["to"]
            if entry["to"] == "dropped":
                item["closed"] = audit["at"]
                if entry.get("superseded_by"):
                    item["superseded_by"] = entry["superseded_by"]
            elif entry["to"] == "prepping":
                # HQ's worker has the owner write the question, with a
                # recommendation, before it reaches his page (S-17).
                item["prepping_since"] = audit["at"]
                for key in ("prep_attempts", "prep_stalled", "prep_short", "prep_draft"):
                    item.pop(key, None)
            elif entry["to"] == "waiting_session":
                if audit["from"] == "for_review":
                    # Back to the lane that can carry it out, keeping the earlier
                    # result and check for the owner to read (as a "revise" does).
                    work.requeue_for_revision(item)
                    item.pop("repair_hold", None)
                item["state"], item["started"] = "waiting_session", ""
                if entry.get("repair_brief"):
                    item["repair_brief"] = entry["repair_brief"]
            work.save_item(item)
        return {"applicable": True, "applied": True, "errors": [],
                "manifest_id": manifest["_id"], "cards": rows}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true",
                        help="write the reviewed moves; without this flag nothing is written")
    parser.add_argument("--data-root", type=Path, default=Path(roots.ROOTS["data"]),
                        help="HQ's store (default: HQ_DATA_ROOT)")
    parser.add_argument("--main-root", default=roots.ROOTS["main"],
                        help="the checkout whose origin/main the commits are checked against")
    parser.add_argument("--manifest", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    work.bind(FileHost(args.data_root), sanitize=False)
    report = migrate(args.manifest, apply=args.apply, main_root=args.main_root)
    print(json.dumps(report, indent=2))
    return 0 if report["applicable"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

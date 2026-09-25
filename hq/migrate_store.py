#!/usr/bin/env python3
"""Copy HQ's live records into their own store with history (Q-125 a).

    python3 hq/migrate_store.py --source /home/daniel/dev/tiny-farm-godot/hq/data \\
        --dest ~/tiny-farm-hq-data --main /home/daniel/dev/tiny-farm-godot-main --dry-run

Without --dry-run it copies and commits; with it, it only reports. Either way
the source is never changed. What it does:

1. Copies every live record and runtime file from the source, uncommitted
   ones included, preserving times (``shutil.copy2``).
2. Does not copy checked-in configuration (org, pillars, decision cards,
   projects, look sheets...): HQ reads those from main. Any of them that differ
   from main's copy are listed, and the source's copies are kept under
   ``archive/checked-in-at-migration/`` in the store so nothing is lost.
3. Keeps any entry it does not recognise, and says so.
4. Makes the store its own Git repository (``store.init``) and records the
   import as its first commit, then checks every copied file's SHA-256
   against the source.
5. Lists the work cards and rulings whose copy on main says something the
   live copy does not (the drift Q-125 is about), so they can be closed with
   ``hq/card.py close`` after the cut-over rather than lost.

docs/hq/HQ_DATA_MIGRATION.md is the runbook this belongs to.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roots  # noqa: E402
import store  # noqa: E402

ARCHIVE = Path("archive") / "checked-in-at-migration"
CLOSED = ("landed", "accepted", "dropped", "done")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def files_under(path):
    path = Path(path)
    if path.is_file() or path.is_symlink():
        return [path]
    return sorted(p for p in path.rglob("*") if p.is_file() or p.is_symlink())


def plan(source, main):
    """What would be copied where, and what differs from main.  Reads only."""
    source = Path(source)
    rows = {"live": [], "runtime": [], "seeded": [], "unknown": [], "archived": [],
            "config_differs": [], "config_same": []}
    for entry in sorted(os.listdir(source)):
        path = source / entry
        if entry in roots.LIVE_RECORDS:
            rows["live"].append(entry)
        elif entry in roots.RUNTIME:
            rows["runtime"].append(entry)
        elif entry in roots.SEEDED:
            rows["seeded"].append(entry)
        elif entry in roots.REPO_OWNED:
            rows["archived"].append(entry)
            ours = Path(main) / "hq" / "data" / entry if main else None
            for f in files_under(path):
                rel = f.relative_to(source).as_posix()
                twin = (Path(main) / "hq" / "data" / rel) if main else None
                same = bool(twin and twin.is_file() and sha256(twin) == sha256(f))
                rows["config_same" if same else "config_differs"].append(rel)
            if ours and ours.is_dir():
                for twin in files_under(ours):
                    rel = twin.relative_to(Path(main) / "hq" / "data").as_posix()
                    if not (source / rel).exists():
                        rows["config_differs"].append(rel + " (only on main)")
        else:
            rows["unknown"].append(entry)
    return rows


def _git_show(main, ref, rel):
    got = subprocess.run(["git", "-C", str(main), "show", f"{ref}:hq/data/{rel}"],
                         capture_output=True, text=True)
    if got.returncode:
        return None
    try:
        return json.loads(got.stdout)
    except ValueError:
        return None


def last_tracked_ref(main, ref="origin/main"):
    """``ref`` if it still tracks cards, else the last commit before main stopped tracking them."""
    has = subprocess.run(["git", "-C", str(main), "ls-tree", "--name-only", ref, "hq/data/work"],
                         capture_output=True, text=True).stdout.strip()
    if has:
        return ref
    removed = subprocess.run(["git", "-C", str(main), "rev-list", "-1", ref, "--", "hq/data/work"],
                             capture_output=True, text=True).stdout.strip()
    return removed + "^" if removed else ref


def drift(source, main, ref="origin/main"):
    """Cards and rulings whose copy on main disagrees with the live copy."""
    out = []
    if not main:
        return out
    ref = last_tracked_ref(main, ref)
    listed = subprocess.run(["git", "-C", str(main), "ls-tree", "-r", "--name-only", ref,
                             "--", "hq/data/work", "hq/data/rulings"],
                            capture_output=True, text=True).stdout.split()
    for path in listed:
        rel = path[len("hq/data/"):]
        if not rel.endswith(".json"):
            continue
        theirs = _git_show(main, ref, rel)
        mine_path = Path(source) / rel
        mine = json.loads(mine_path.read_text()) if mine_path.is_file() else None
        if not isinstance(theirs, dict):
            continue
        key = "state" if rel.startswith("work/") else "status"
        live, on_main = (mine or {}).get(key), theirs.get(key)
        if mine is None:
            out.append({"record": rel, "live": "missing", "main": on_main,
                        "note": "only on main; not copied"})
        elif live != on_main:
            closed_on_main = on_main in CLOSED or on_main == "integrated"
            out.append({"record": rel, "live": live, "main": on_main,
                        "note": ("finished on main but open here: close it with hq/card.py"
                                 if closed_on_main else "differs")})
    return out


def copy(source, dest, rows):
    source, dest = Path(source), Path(dest)
    copied = []
    for entry in rows["live"] + rows["runtime"] + rows["seeded"] + rows["unknown"]:
        for f in files_under(source / entry):
            target = dest / f.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, target, follow_symlinks=False)
            copied.append((f, target))
    for entry in rows["archived"]:
        for f in files_under(source / entry):
            target = dest / ARCHIVE / f.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, target, follow_symlinks=False)
            copied.append((f, target))
    return copied


def verify(copied):
    bad = [str(t) for s, t in copied
           if not s.is_symlink() and sha256(s) != sha256(t)]
    return bad


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, type=Path, help="the live data root today")
    parser.add_argument("--dest", required=True, type=Path, help="the new store (must not exist)")
    parser.add_argument("--main", type=Path, help="a checkout of main, to compare configuration and cards against")
    parser.add_argument("--ref", default="origin/main", help="the main ref to compare cards against")
    parser.add_argument("--dry-run", action="store_true", help="report only; write nothing")
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    args = parser.parse_args(argv)
    source, dest = args.source.expanduser().resolve(), args.dest.expanduser()
    if not (source / "org.json").is_file():
        parser.error(f"{source} has no org.json; it is not an HQ data root")
    if dest.exists() and any(dest.iterdir()):
        parser.error(f"{dest} already exists and is not empty; refusing to mix stores")
    rows = plan(source, args.main)
    report = {"source": str(source), "dest": str(dest), "dry_run": args.dry_run,
              "copy": {k: rows[k] for k in ("live", "runtime", "seeded", "unknown")},
              "archived_not_read": rows["archived"],
              "config_differs_from_main": rows["config_differs"],
              "files_to_copy": sum(len(files_under(source / e))
                                   for k in ("live", "runtime", "seeded", "unknown", "archived")
                                   for e in rows[k]),
              "drift": drift(source, args.main, args.ref)}
    if not args.dry_run:
        dest.mkdir(parents=True, exist_ok=True)
        copied = copy(source, dest, rows)
        store.init(dest)
        stamp = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
        store._git(dest, "add", "-A")
        store._git(dest, "commit", "-q", "-m",
                   f"Import HQ's live records from {source} at {stamp}\n\n"
                   f"{len(copied)} files copied; checked-in configuration archived under "
                   f"{ARCHIVE} and read from main instead (Q-125 a).\n")
        report["copied"] = len(copied)
        report["mismatched"] = verify(copied)
        report["commit"] = store._git(dest, "rev-parse", "HEAD").stdout.strip()
        report["uncommitted_after_import"] = store.changed_paths(dest)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(human(report))
    return 1 if report.get("mismatched") else 0


def human(r):
    lines = [("Would copy" if r["dry_run"] else "Copied") + f" HQ records from {r['source']} to {r['dest']}"]
    for kind, names in r["copy"].items():
        if names:
            lines.append(f"  {kind}: {', '.join(names)}")
    lines.append(f"  checked-in configuration, archived and read from main instead: "
                 f"{', '.join(r['archived_not_read']) or 'none'}")
    lines.append(f"  files: {r['files_to_copy']}")
    if r["copy"]["unknown"]:
        lines.append("  NOTE: unrecognised entries are copied as they are; classify them in hq/roots.py")
    differs = r["config_differs_from_main"]
    lines.append(f"Checked-in files that differ from main: {len(differs)}")
    lines += [f"  {p}" for p in differs[:40]] + (["  ..."] if len(differs) > 40 else [])
    lines.append(f"Cards and rulings whose copy on main disagrees with the live copy: {len(r['drift'])}")
    for d in r["drift"][:60]:
        lines.append(f"  {d['record']}: live {d['live']}, main {d['main']} — {d['note']}")
    if len(r["drift"]) > 60:
        lines.append("  ...")
    if not r["dry_run"]:
        lines.append(f"Import commit {r['commit'][:12]}; {r['copied']} files; "
                     f"{len(r['mismatched'])} mismatched; "
                     f"{len(r['uncommitted_after_import'])} left uncommitted (ignored bulk logs are not listed)")
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())

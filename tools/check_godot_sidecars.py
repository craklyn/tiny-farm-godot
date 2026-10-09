#!/usr/bin/env python3
"""Fail when a tracked Godot source is missing its tracked sidecar."""
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
IMPORTED_SUFFIXES = (".png", ".wav", ".ogg", ".csv", ".ttf")


def tracked_files(root=ROOT):
    result = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True,
                            capture_output=True, text=True)
    return {name for name in result.stdout.split("\0") if name}


def godot_ignores(root, name):
    parent = Path(name).parent
    while str(parent) != ".":
        if (root / parent / ".gdignore").is_file():
            return True
        parent = parent.parent
    return False


def missing_sidecars(root=ROOT):
    tracked = tracked_files(root)
    missing = []
    for name in sorted(tracked):
        if godot_ignores(root, name):
            continue
        sidecar = (name + ".uid" if name.endswith(".gd") else
                   name + ".import" if name.endswith(IMPORTED_SUFFIXES) else "")
        if sidecar and sidecar not in tracked:
            missing.append((name, sidecar))
    return missing


def main():
    missing = missing_sidecars()
    if not missing:
        print("Every tracked Godot source has its tracked sidecar.")
        return 0
    print("Tracked Godot sources are missing sidecars:", file=sys.stderr)
    for source, sidecar in missing:
        print(f"  {source} -> {sidecar}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

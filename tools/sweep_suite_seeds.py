#!/usr/bin/env python3
"""Play the integration suite and the robot session on many farms at once.

Each played suite boots one fixed farm (``tools/suite_seed.gd``), so on any one
commit it either passes or fails, every time. That fixed farm is one sample:
a check that only holds on some farms can still pass there and fail on the next
commit that moves the dice. This sweeps a range of seeds instead and prints, per
failing check, the seeds it failed on, each of which replays exactly with
``-- --seed=N``.

    python3 tools/sweep_suite_seeds.py --seeds 1-40 --jobs 6
    python3 tools/sweep_suite_seeds.py --suite robot --seeds 1-200 --jobs 8

``--fps 20`` gives every frame three times the game time CI's 60 does, the way
a slow, loaded runner did before frames were fixed: a test that only passes
because little happens between two of its frames fails here, reproducibly.
``--cores 0-1`` pins every copy onto those CPUs with ``taskset``, which is how
a loaded CI runner is imitated. Each copy holds about 250 MB.
"""

from __future__ import annotations

import argparse
import collections
import concurrent.futures
import os
import re
import subprocess
import sys

SUITES = {
    "integration": "res://tools/test_runner.tscn",
    "robot": "res://tools/robot_session.tscn",
}
FAIL = re.compile(r"✗ FAIL: (.*)")
RESULT = re.compile(r"Results: (?:(\d+) PASSED, (\d+) FAILED|(PASSED|FAILED))")


def _seeds(spec: str) -> list[int]:
    out: list[int] = []
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def _play(godot: str, suite: str, seed: int, fps: int, cores: str | None,
          log_dir: str | None) -> tuple[str, int, list[str], bool]:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cmd = [sys.executable, os.path.join(root, "tools", "run_godot_test.py"), "--timeout", "3600", "--",
           godot, "--headless", "--fixed-fps", str(fps), "--path", root, SUITES[suite], "--", f"--seed={seed}"]
    if cores:
        cmd = ["taskset", "-c", cores] + cmd
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=root)
    text = proc.stdout + proc.stderr
    if log_dir:
        with open(os.path.join(log_dir, f"{suite}_{seed}_fps{fps}.log"), "w") as fh:
            fh.write(text)
    fails = FAIL.findall(text)
    finished = RESULT.search(text) is not None
    if proc.returncode != 0 and not fails:
        fails = [f"exit {proc.returncode} without a failed check" + ("" if finished else " (no result line)")]
    return suite, seed, fails, proc.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--suite", choices=["integration", "robot", "both"], default="both")
    ap.add_argument("--seeds", default="1-20", help="e.g. 1-40 or 3,17,90")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--cores", help="taskset CPU list every copy shares, e.g. 0-1")
    ap.add_argument("--fps", type=int, default=60,
                    help="game time per frame; CI uses 60, and 20 is a slow, loaded runner's step")
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--logs", help="directory to keep each run's full output in")
    args = ap.parse_args()

    if args.logs:
        os.makedirs(args.logs, exist_ok=True)
    suites = ["integration", "robot"] if args.suite == "both" else [args.suite]
    jobs = [(s, n) for n in _seeds(args.seeds) for s in suites]
    by_check: dict[tuple[str, str], list[int]] = collections.defaultdict(list)
    runs = collections.Counter()
    red = collections.Counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(_play, args.godot, s, n, args.fps, args.cores, args.logs) for s, n in jobs]
        for fut in concurrent.futures.as_completed(futures):
            suite, seed, fails, ok = fut.result()
            runs[suite] += 1
            if not ok:
                red[suite] += 1
            for f in dict.fromkeys(fails):
                by_check[(suite, f)].append(seed)
            print(f"{suite:<12} seed {seed:<8} {'pass' if ok else 'FAIL'}"
                  + ("" if ok else f"  ({len(fails)} checks)"), flush=True)

    print()
    for suite in suites:
        print(f"{suite}: {red[suite]} of {runs[suite]} farms failed")
    for (suite, check), seeds in sorted(by_check.items(), key=lambda kv: -len(kv[1])):
        print(f"  {suite:<12} {len(seeds):>3}x  {check[:110]}")
        print(f"  {'':<12}       seeds {sorted(seeds)}")
    return 1 if sum(red.values()) else 0


if __name__ == "__main__":
    sys.exit(main())

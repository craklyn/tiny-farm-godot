#!/usr/bin/env python3
"""Run one Godot check with private user data and bounded shutdown.

Godot 4.7 has no ``--user-data-dir`` flag.  On Linux, ``user://`` lives below
``XDG_DATA_HOME``, so giving each child a fresh value is the process boundary we
need: simultaneous suites cannot share saves, replays, or logs.
"""

from __future__ import annotations

import argparse
import os
import re
import selectors
import subprocess
import sys
import tempfile
import time


RESULT = re.compile(r"Results:\s*(\d+) PASSED,\s*(\d+) FAILED")


def _stop(proc: subprocess.Popen[str]) -> None:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def run(command: list[str], timeout: float, result_grace: float) -> int:
    started = time.monotonic()
    result_deadline = None
    result = None
    with tempfile.TemporaryDirectory(prefix="tiny-farm-godot-test-") as user_data:
        env = os.environ.copy()
        env["XDG_DATA_HOME"] = user_data
        proc = subprocess.Popen(
            command,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert proc.stdout is not None
        selector = selectors.DefaultSelector()
        selector.register(proc.stdout, selectors.EVENT_READ)
        while proc.poll() is None:
            now = time.monotonic()
            if now - started >= timeout:
                print(
                    f"ERROR: Godot check exceeded {timeout:g}s before returning a result",
                    file=sys.stderr,
                    flush=True,
                )
                _stop(proc)
                return 124
            if result_deadline is not None and now >= result_deadline:
                passed, failed = result
                print(
                    "WARNING: Godot printed its final result but did not exit; "
                    f"stopping it after {result_grace:g}s",
                    file=sys.stderr,
                    flush=True,
                )
                _stop(proc)
                return 1 if failed else 0
            wait = min(0.1, timeout - (now - started))
            if result_deadline is not None:
                wait = min(wait, result_deadline - now)
            for key, _ in selector.select(max(0, wait)):
                line = key.fileobj.readline()
                if not line:
                    continue
                print(line, end="", flush=True)
                match = RESULT.search(line)
                if match:
                    result = (int(match.group(1)), int(match.group(2)))
                    result_deadline = time.monotonic() + result_grace

        for line in proc.stdout:
            print(line, end="", flush=True)
            match = RESULT.search(line)
            if match:
                result = (int(match.group(1)), int(match.group(2)))

        code = proc.returncode or 0
        if result is None:
            print("ERROR: Godot check exited without a Results line", file=sys.stderr, flush=True)
            return 1
        if result is not None and result[1] > 0:
            return 1
        return code


def main() -> int:
    parser = argparse.ArgumentParser()
    # CI's job limit is fifteen minutes; leave a minute for this runner to
    # report the fault instead of having the platform erase the diagnosis.
    parser.add_argument("--timeout", type=float, default=840)
    parser.add_argument("--result-grace", type=float, default=5)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required after --")
    return run(command, args.timeout, args.result_grace)


if __name__ == "__main__":
    raise SystemExit(main())

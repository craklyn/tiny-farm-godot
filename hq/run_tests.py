#!/usr/bin/env python3
"""Run every focused HQ regression in a clean per-file scratch directory.

Discovery is deliberate: Python files run first, then Node files, with names
sorted inside each group. A new ``hq/tests/test_*`` file cannot silently fall
out of the suite: unknown file types, skipped tests, timeouts and empty
discovery are failures.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
TESTS = Path(__file__).resolve().parent / "tests"
SKIP = re.compile(r"(?:\bskipped\s*=\s*[1-9]\d*\b|#\s*SKIP\b|\b[1-9]\d*\s+skipped\b)", re.I)


class RunnerError(RuntimeError):
    pass


def discover(folder: Path = TESTS) -> list[Path]:
    found = sorted(path for path in folder.glob("test_*") if path.is_file())
    if not found:
        raise RunnerError(f"No HQ tests found in {folder}")
    unknown = [path.name for path in found if path.suffix not in (".py", ".js")]
    if unknown:
        raise RunnerError("Unrecognized HQ test file(s): " + ", ".join(unknown))
    return (sorted((path for path in found if path.suffix == ".py"), key=lambda p: p.name)
            + sorted((path for path in found if path.suffix == ".js"), key=lambda p: p.name))


def command_for(path: Path) -> list[str]:
    if path.suffix == ".py":
        return [sys.executable, str(path)]
    if path.suffix == ".js":
        return ["node", str(path)]
    raise RunnerError(f"Unrecognized HQ test file: {path}")


def run_files(files: list[Path], timeout: float, scratch: Path) -> bool:
    passed = 0
    failed = 0
    for number, path in enumerate(files, 1):
        test_scratch = scratch / f"{number:02d}-{path.stem}"
        test_scratch.mkdir(parents=True)
        home = test_scratch / "home"
        home.mkdir()
        env = {**os.environ, "TMPDIR": str(test_scratch), "TEMP": str(test_scratch),
               "TMP": str(test_scratch), "HOME": str(home),
               "XDG_CACHE_HOME": str(test_scratch / "cache"),
               "XDG_CONFIG_HOME": str(test_scratch / "config"),
               "XDG_DATA_HOME": str(test_scratch / "data"),
               "HQ_TEST_SCRATCH": str(test_scratch)}
        started = time.monotonic()
        try:
            proc = subprocess.run(command_for(path), cwd=ROOT, env=env, text=True,
                                  capture_output=True, timeout=timeout)
            output = (proc.stdout or "") + (proc.stderr or "")
            reason = (f"exit {proc.returncode}" if proc.returncode else
                      "reported a skipped test" if SKIP.search(output) else "")
        except subprocess.TimeoutExpired as exc:
            def as_text(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
            output = as_text(exc.stdout) + as_text(exc.stderr)
            reason = f"timed out after {timeout:g} s"
        except OSError as exc:
            output = str(exc)
            reason = "could not start"
        elapsed = time.monotonic() - started
        if reason:
            print(f"FAIL {number}/{len(files)} {path.name} ({elapsed:.2f}s): {reason}")
            if output.strip():
                print(output.rstrip())
            failed += 1
        else:
            passed += 1
            print(f"PASS {number}/{len(files)} {path.name} ({elapsed:.2f}s)")
    print(f"HQ tests: {passed}/{len(files)} files passed; {failed} failed; 0 skipped.")
    return failed == 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=120,
                        help="seconds allowed for each test file (default: 120)")
    parser.add_argument("--tests-dir", type=Path, default=TESTS, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        files = discover(args.tests_dir)
    except RunnerError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    py_count = sum(path.suffix == ".py" for path in files)
    print(f"HQ tests: discovered {len(files)} files ({py_count} Python, "
          f"{len(files) - py_count} Node); Python runs first, then Node.")
    with tempfile.TemporaryDirectory(prefix="hq-test-run-") as folder:
        return 0 if run_files(files, args.timeout, Path(folder)) else 1


if __name__ == "__main__":
    raise SystemExit(main())

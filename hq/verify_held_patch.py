#!/usr/bin/env python3
"""Collect repeat-suite evidence for an unchanged held patch; never land it.

Example: python3 hq/verify_held_patch.py WORK_ID --runs 10 \
  --assertion "even though the sim washed it dry at the tap"
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

import drain
import work


RESULT = re.compile(r"Results:\s*(\d+) PASSED,\s*(\d+) FAILED")


def _command(args, cwd, timeout=120, input=None):
    return subprocess.run(args, cwd=cwd, input=input, capture_output=True, text=True, timeout=timeout)


def _run_logged(args, cwd, log_path, timeout):
    """Stream a check to durable storage and stop its entire child group."""
    with open(log_path, "w", encoding="utf-8") as sink:
        proc = subprocess.Popen(args, cwd=cwd, stdout=sink, stderr=subprocess.STDOUT,
                                start_new_session=True)
        try:
            return proc.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as exc:
            code = 130 if isinstance(exc, KeyboardInterrupt) else 124
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            sink.write(f"\nERROR: verification {'interrupted' if code == 130 else 'timed out'}\n")
            sink.flush()
            return code


def _save_evidence(path, evidence):
    pending = path + ".pending"
    with open(pending, "w", encoding="utf-8") as sink:
        json.dump(evidence, sink, indent=2)
        sink.write("\n")
        sink.flush()
        os.fsync(sink.fileno())
    os.replace(pending, path)


def verify(item_id, runs, assertion, repo=drain.REPO, output_root=None, runner=None):
    """Return evidence path, preserving every completed and incomplete attempt."""
    # New cards use eleven hex characters after w; older imported cards also
    # have readable alphanumeric IDs. Validate the path, not a guessed length.
    if not re.fullmatch(r"w[a-zA-Z0-9]+", item_id):
        raise ValueError("expected a work-card ID")
    if runs < 1 or runs > 100:
        raise ValueError("runs must be between 1 and 100")
    if not assertion:
        raise ValueError("an exact assertion phrase is required")
    card_path = os.path.join(repo, "hq", "data", "work", item_id + ".json")
    with open(card_path, encoding="utf-8") as source:
        item = json.load(source)
    candidate = (item.get("attempt_outcome") or {}).get("candidate") or {}
    base = candidate.get("base")
    files = candidate.get("files")
    if item.get("diff", {}).get("applied") or not base or not files or not candidate.get("tree"):
        raise ValueError("card has no held, identified candidate patch")
    patch_path = os.path.join(repo, "hq", "data", "patches", item_id + ".patch")
    with open(patch_path, encoding="utf-8") as source:
        patch = source.read()
    if not patch.strip() or work.evidence_id(patch) != item["attempt_outcome"].get("patch_id"):
        raise ValueError("saved patch is missing or differs from the reviewed patch")
    if _command(["git", "cat-file", "-e", base + "^{commit}"], repo).returncode:
        raise ValueError("recorded candidate base is unavailable")
    if drain.git_blobs(repo, base, files) != candidate.get("base_files"):
        raise ValueError("recorded candidate base files no longer match")
    root = output_root or os.path.join(repo, "hq", "data", "runs", "verification")
    os.makedirs(root, exist_ok=True)
    evidence_dir = tempfile.mkdtemp(prefix=item_id + "-", dir=root)
    worktree = tempfile.mkdtemp(prefix="hq-held-verify-")
    added = _command(["git", "worktree", "add", "--detach", worktree, base], repo, timeout=600)
    if added.returncode:
        shutil.rmtree(worktree, ignore_errors=True)
        raise ValueError("cannot make candidate worktree: " + added.stderr[:300])
    try:
        applied = _command(["git", "apply", "--index", "--binary", "-"], worktree,
                           timeout=180, input=patch)
        if applied.returncode:
            raise ValueError("saved patch does not apply to its recorded base: " + applied.stderr[:300])
        tree = _command(["git", "write-tree"], worktree)
        if tree.returncode or tree.stdout.strip() != candidate["tree"]:
            raise ValueError("saved patch produces a different candidate tree")
        if drain.git_blobs(worktree, "", files) != files:
            raise ValueError("saved patch changed-file blobs differ from the reviewed candidate")
        evidence = {"card": item_id, "attempt": item.get("last_recorded_attempt"),
                    "base": base, "candidate_tree": candidate["tree"],
                    "patch_id": item["attempt_outcome"]["patch_id"],
                    "assertion": assertion, "requested_runs": runs, "completed_runs": 0,
                    "assertion_passes": 0, "assertion_failures": 0, "runs": [],
                    "created": datetime.now(timezone.utc).isoformat()}
        evidence_path = os.path.join(evidence_dir, "evidence.json")
        _save_evidence(evidence_path, evidence)
        print(f"Evidence: {evidence_path}", flush=True)
        # A detached historical worktree has no imported Godot class cache.
        # The suite can otherwise emit hundreds of parse errors and sit until
        # timeout, which says nothing about the proposed game change.
        if runner is None:
            print("Importing candidate before tests...", flush=True)
            import_log = os.path.join(evidence_dir, "import.log")
            import_code = _run_logged(["godot", "--headless", "--path", ".", "--import"],
                                      worktree, import_log, timeout=300)
            with open(import_log, encoding="utf-8") as source:
                import_output = source.read()
            evidence["import"] = {"exit_code": import_code, "log": "import.log",
                                  "ok": import_code == 0 and "SCRIPT ERROR:" not in import_output}
            _save_evidence(evidence_path, evidence)
            if not evidence["import"]["ok"]:
                print(f"Candidate import failed; see {import_log}", flush=True)
                return evidence_path
        wrapper = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                               "tools", "run_godot_test.py")
        run_cmd = runner or [sys.executable, wrapper, "--timeout", "840", "--",
                             "godot", "--headless", "--path", ".", "res://tools/test_runner.tscn"]
        for number in range(1, runs + 1):
            print(f"Integration run {number}/{runs} starting...", flush=True)
            log_name = f"run-{number:02d}.log"
            log_path = os.path.join(evidence_dir, log_name)
            code = _run_logged(run_cmd, worktree, log_path, timeout=900)
            with open(log_path, encoding="utf-8") as source:
                output = source.read()
            matches = list(RESULT.finditer(output))
            # Exit 1 is a completed failing suite; timeouts, kills, and other
            # abnormal exits cannot count even if output contained a result.
            completed = len(matches) == 1 and code in (0, 1)
            # Read only the assertion in this single completed suite. A wrapper
            # diagnostic or earlier run fragment after the summary cannot turn
            # this run into a pass, nor can contradictory marks be resolved by
            # choosing the more convenient one.
            suite_output = output[:matches[0].start()] if completed else ""
            assertion_lines = [line for line in suite_output.splitlines() if assertion in line]
            failures = [line for line in assertion_lines if "FAIL:" in line]
            passes = [line for line in assertion_lines if re.search(r"^\s*[✓✔]\s", line)]
            failed_assertion = len(failures) > 0 and not passes
            passed_assertion = len(passes) == 1 and not failures
            row = {"number": number, "exit_code": code, "completed": completed,
                   "passed": int(matches[0].group(1)) if completed else None,
                   "failed": int(matches[0].group(2)) if completed else None,
                   "assertion": "fail" if failed_assertion else "pass" if passed_assertion else "unknown",
                   "log": log_name}
            evidence["runs"].append(row)
            if completed:
                evidence["completed_runs"] += 1
                evidence["assertion_failures"] += int(failed_assertion)
                evidence["assertion_passes"] += int(passed_assertion)
            _save_evidence(evidence_path, evidence)
            print(f"Integration run {number}/{runs}: "
                  f"{'complete' if completed else 'incomplete'}, exit {code}, "
                  f"assertion {row['assertion']}; log {log_path}", flush=True)
            if not completed or code != 0 or row["failed"] != 0 or row["assertion"] != "pass":
                print("Stopping after unsuccessful run; no further runs will start.", flush=True)
                break
        return evidence_path
    finally:
        _command(["git", "worktree", "remove", "--force", worktree], repo)
        shutil.rmtree(worktree, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("item_id")
    parser.add_argument("--runs", type=int, required=True)
    parser.add_argument("--assertion", required=True)
    args = parser.parse_args()
    try:
        path = verify(args.item_id, args.runs, args.assertion)
    except KeyboardInterrupt:
        print("Verification interrupted; completed evidence remains in the printed directory.",
              file=sys.stderr)
        return 130
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"Verification refused: {exc}", file=sys.stderr)
        return 1
    with open(path, encoding="utf-8") as source:
        evidence = json.load(source)
    print(f"Evidence: {path}")
    print(f"Completed {evidence['completed_runs']}/{evidence['requested_runs']}; "
          f"assertion {evidence['assertion_passes']} pass, {evidence['assertion_failures']} fail")
    return 0 if (evidence["completed_runs"] == evidence["requested_runs"] and
                 evidence["assertion_passes"] + evidence["assertion_failures"] == evidence["requested_runs"] and
                 evidence["assertion_failures"] == 0 and
                 all(row["exit_code"] == 0 and row["failed"] == 0 for row in evidence["runs"])) else 1


if __name__ == "__main__":
    raise SystemExit(main())

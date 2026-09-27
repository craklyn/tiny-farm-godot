#!/usr/bin/env python3
"""Stop a credential from entering a commit or leaving this machine in a push.

The repository is public, so a key that reaches origin is compromised the
moment it lands; rewriting history afterwards does not help. Two checks, both
on what is being ADDED only:

  1. The exact values of the keys the studio holds, read from every `.env` in
     this repository's worktrees. GitHub's push protection knows provider token
     shapes, but not Retro Diffusion's, Freesound's or itch.io's — the three
     keys the project actually holds — so this is the check that covers them.
     It names the variable, never the value.
  2. gitleaks (https://github.com/gitleaks/gitleaks), for every credential
     shape it knows, configured by .gitleaks.toml.

    python3 tools/check_secrets.py --staged              # what is about to be committed
    python3 tools/check_secrets.py --range origin/main..main   # what a push would publish

Exit 0 clean, 1 on a finding. For --range (a push) a missing gitleaks fails
closed; for --staged it warns and runs the exact-value check alone, because a
commit is still local and a missing tool must not stop every session working.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

MIN_VALUE = 12   # shorter values are too likely to appear by accident
BLOCKED_NAMES = (".env",)
BLOCKED_SUFFIXES = (".pem", ".key", ".p12", ".keystore", ".jks")


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True).stdout


def env_files(cwd=None):
    """`.env` at the root of every worktree of this repository."""
    roots = [line[len("worktree "):] for line in
             git("worktree", "list", "--porcelain", cwd=cwd).splitlines()
             if line.startswith("worktree ")]
    return [Path(r) / ".env" for r in roots if (Path(r) / ".env").is_file()]


def secret_values(files):
    values = {}
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, _, value = line.removeprefix("export ").partition("=")
            value = value.strip().strip("'\"")
            if len(value) >= MIN_VALUE:
                values[value] = name.strip()
    return values


def added(staged, rng, cwd=None):
    """(lines added, paths added or changed) in the commit or push range."""
    base = ["diff", "--cached"] if staged else ["diff", rng]
    lines = [l[1:] for l in git(*base, "-U0", "--no-color", cwd=cwd).splitlines()
             if l.startswith("+") and not l.startswith("+++")]
    paths = git(*base, "--name-only", "--diff-filter=ACMR", cwd=cwd).split()
    return lines, paths


def check(staged=False, rng="", cwd=None, env=None):
    findings = []
    lines, paths = added(staged, rng, cwd)
    values = secret_values(env if env is not None else env_files(cwd))
    for value, name in values.items():
        if any(value in line for line in lines):
            findings.append(f"the value of {name} from .env is in the added lines")
    for p in paths:
        base = os.path.basename(p)
        if base in BLOCKED_NAMES or base.endswith(BLOCKED_SUFFIXES):
            findings.append(f"{p} is a credential file")
    tool = shutil.which("gitleaks")
    if tool:
        mode = (["git", "--pre-commit", "--staged"] if staged
                else ["git", f"--log-opts={rng}"])
        run = subprocess.run([tool, *mode, "--redact", "--no-banner", "--log-level", "error"],
                             cwd=cwd, capture_output=True, text=True)
        if run.returncode == 1:
            findings.append("gitleaks found a credential:\n" + (run.stdout + run.stderr).strip())
        elif run.returncode != 0:
            findings.append("gitleaks could not run: " + (run.stderr or "").strip()[-300:])
    elif staged:
        print("check_secrets: gitleaks is not installed; checked the known key values only.",
              file=sys.stderr)
    else:
        findings.append("gitleaks is not installed, so a push cannot be checked")
    return findings


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--staged", action="store_true")
    group.add_argument("--range")
    args = ap.parse_args()
    findings = check(staged=args.staged, rng=args.range or "")
    for f in findings:
        print("check_secrets: " + f, file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())

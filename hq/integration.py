"""Clean, single-writer local-main integration for HQ candidates.

The caller holds the drain lock. This module never pushes, switches the user's
branch implicitly, or edits the user's checkout. A candidate checkout is a
detached linked worktree; local refs/heads/main is advanced only after its
exact tree has been reviewed and tested and only from the expected parent.
"""

import hashlib
import os
import subprocess
from pathlib import Path


def git(repo, *args, input=None, check=True):
    result = subprocess.run(["git", *args], cwd=repo, input=input,
                            capture_output=True, text=True, timeout=180)
    if check and result.returncode:
        raise RuntimeError((result.stderr or result.stdout or "Git failed").strip()[:500])
    return result


def main_head(repo):
    return git(repo, "rev-parse", "refs/heads/main").stdout.strip()


def main_checkout(repo):
    """Path currently checking out main, or None after the safe handoff."""
    path = ""
    for line in git(repo, "worktree", "list", "--porcelain").stdout.splitlines():
        if line.startswith("worktree "):
            path = line[9:]
        elif line == "branch refs/heads/main":
            return path
    return None


def handoff_status(repo):
    holder = main_checkout(repo)
    if holder:
        return False, ("Local main is still checked out at " + holder + "; a confirmed-idle "
                       "branch handoff is required before clean integration.")
    return True, ""


def _checkout_fingerprint(repo):
    """Content, mode and index identity; excludes only Git's own metadata."""
    root = Path(repo)
    files = []
    for base, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not (base == str(root) and d == ".git"))
        for name in sorted(names):
            path = Path(base, name)
            relative = str(path.relative_to(root))
            if path.is_symlink():
                value = os.readlink(path).encode()
            elif path.is_file():
                value = path.read_bytes()
            else:
                continue
            files.append((relative, path.lstat().st_mode, hashlib.sha256(value).hexdigest()))
    index = git(repo, "ls-files", "--stage", "-z").stdout
    return files, hashlib.sha256(index.encode()).hexdigest()


def handoff_main(repo, branch, *, confirmed_idle=False):
    """One-time, explicit transfer of a dirty checkout off main.

    The caller must establish no other worker uses this checkout. The branch
    starts at the identical HEAD. The function refuses an unsafe transfer and
    verifies every file and index entry afterward; it never stashes or resets.
    """
    if not confirmed_idle:
        return False, "The user checkout has not been confirmed idle."
    if not branch.startswith("codex/") or git(repo, "check-ref-format", "--branch", branch, check=False).returncode != 0:
        return False, "The handoff branch must be a valid codex/ branch."
    if git(repo, "show-ref", "--verify", "--quiet", "refs/heads/" + branch,
           check=False).returncode == 0:
        return False, "The handoff branch already exists."
    current = git(repo, "symbolic-ref", "--quiet", "HEAD", check=False).stdout.strip()
    if current != "refs/heads/main" or main_checkout(repo) != str(Path(repo).resolve()):
        return False, "The requested checkout does not own local main."
    if any(git(repo, "rev-parse", "-q", "--verify", name, check=False).returncode == 0
           for name in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REBASE_HEAD")):
        return False, "Finish the in-progress Git operation before handoff."
    before_head = main_head(repo)
    before = _checkout_fingerprint(repo)
    switched = git(repo, "switch", "-c", branch, check=False)
    if switched.returncode:
        return False, (switched.stderr or switched.stdout).strip()[:500]
    after = _checkout_fingerprint(repo)
    if before != after or git(repo, "rev-parse", "HEAD").stdout.strip() != before_head:
        return False, "Handoff changed file bytes, index state, or HEAD; stop and inspect."
    return True, ""


def candidate_checkout(repo, scratch, attempt_id, expected_parent):
    """Create one detached checkout after proving local main is unowned."""
    ready, reason = handoff_status(repo)
    if not ready:
        raise RuntimeError(reason)
    if main_head(repo) != expected_parent:
        raise RuntimeError("Local main changed; this candidate needs fresh review and tests.")
    safe_id = "".join(c for c in attempt_id if c.isalnum() or c in "-_")[:80]
    if not safe_id:
        raise ValueError("A candidate attempt ID is required")
    path = Path(scratch, "integration-" + safe_id)
    if path.exists():
        raise RuntimeError("The candidate checkout already exists; recover its transaction first.")
    path.parent.mkdir(parents=True, exist_ok=True)
    git(repo, "worktree", "add", "--detach", "--", str(path), expected_parent)
    return str(path)


def remove_candidate(repo, path, scratch):
    """Remove only our named linked checkout under the configured scratch root."""
    candidate = Path(path).resolve()
    if candidate.parent != Path(scratch).resolve() or not candidate.name.startswith("integration-"):
        raise ValueError("Refusing to remove a path outside the integration scratch root")
    linked = {Path(line[9:]).resolve() for line in
              git(repo, "worktree", "list", "--porcelain").stdout.splitlines()
              if line.startswith("worktree ")}
    if candidate not in linked:
        raise ValueError("The candidate path is not a linked Git worktree")
    git(repo, "worktree", "remove", "--force", "--", path)


def advance_main(repo, commit, parent):
    """Atomic expected-parent update; never auto-pushes origin/main."""
    updated = git(repo, "update-ref", "refs/heads/main", commit, parent, check=False)
    return updated.returncode == 0


def origin_tracking(repo):
    """Last-fetched tracking fact only; never claims the remote is current."""
    origin = git(repo, "rev-parse", "--verify", "refs/remotes/origin/main",
                 check=False)
    if origin.returncode:
        return {"last_fetched_sha": "", "relation": "unknown", "push": "not_attempted"}
    remote = origin.stdout.strip()
    local = main_head(repo)
    if local == remote:
        relation = "same_at_last_fetch"
    elif git(repo, "merge-base", "--is-ancestor", remote, local,
             check=False).returncode == 0:
        relation = "local_ahead_at_last_fetch"
    elif git(repo, "merge-base", "--is-ancestor", local, remote,
             check=False).returncode == 0:
        relation = "origin_ahead_at_last_fetch"
    else:
        relation = "diverged_at_last_fetch"
    return {"last_fetched_sha": remote, "relation": relation,
            "push": "not_attempted"}

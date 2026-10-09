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


def _primary_checkout(repo):
    for line in git(repo, "worktree", "list", "--porcelain").stdout.splitlines():
        if line.startswith("worktree "):
            return os.path.realpath(line[9:])
    return ""


def _untracked_collision(holder, parent, commit):
    """Refuse when a landing path overlaps an untracked file or its parents."""
    untracked = set(git(holder, "ls-files", "--others", "--exclude-standard", "-z").stdout.split("\0")) - {""}
    if not untracked:
        return False
    changed = set(git(holder, "diff-tree", "--no-commit-id", "--name-only", "-r",
                      "-z", parent, commit).stdout.split("\0")) - {""}
    return any(untracked_path == changed_path or
               untracked_path.startswith(changed_path + "/") or
               changed_path.startswith(untracked_path + "/")
               for untracked_path in untracked for changed_path in changed)


def _owner_state(holder, parent):
    """A dedicated main checkout with no uncommitted build input."""
    if git(holder, "rev-parse", "HEAD").stdout.strip() != parent:
        return False
    if git(holder, "diff", "--quiet", check=False).returncode or \
            git(holder, "diff", "--cached", "--quiet", check=False).returncode:
        return False
    return True


def _origin_matches(holder, parent):
    """A fetched origin/main, when present, must name the same commit."""
    origin = git(holder, "rev-parse", "--verify", "refs/remotes/origin/main", check=False)
    return origin.returncode != 0 or origin.stdout.strip() == parent


# The start of handoff_status's refusal, so a hold it caused can be recognised.
HANDOFF_REFUSAL = "Local main is still checked out at "


def handoff_status(repo):
    holder = main_checkout(repo)
    if holder:
        # The primary checkout can carry Daniel's unfinished files. A linked
        # worktree deliberately assigned main may own it, but only while clean
        # and synchronized with the ref it claims to represent.
        if os.path.realpath(holder) != _primary_checkout(repo) and \
                _owner_state(holder, main_head(repo)) and \
                _origin_matches(holder, main_head(repo)):
            return True, ""
        return False, (HANDOFF_REFUSAL + holder + "; a confirmed-idle "
                       "branch handoff or clean main-worktree synchronization is required before integration.")
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
    """Create a detached candidate; the shared-checkout guard belongs at landing."""
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
    """CAS local main and synchronize its clean dedicated owner, if present."""
    holder = main_checkout(repo)
    if holder:
        if os.path.realpath(holder) == _primary_checkout(repo) or not _owner_state(holder, parent) \
                or not _origin_matches(holder, parent):
            return False
        if _untracked_collision(holder, parent, commit):
            return False
    updated = git(repo, "update-ref", "refs/heads/main", commit, parent, check=False)
    if updated.returncode:
        return False
    if holder and not synchronize_main(repo, commit, parent, holder):
        raise RuntimeError("Local main advanced, but its dedicated checkout needs safe synchronization.")
    return True


# Files the writing check rewrites in whatever checkout a commit is made from: a
# cache of verdicts it can recompute, never anyone's work.
REGENERABLE = ("docs/writing_verdicts.json",)


def catch_up_main(repo, target):
    """Fast-forward local main, and its clean dedicated checkout, to `target`.

    Work pushed from anywhere but the drain (a chief-of-staff session, a Codex
    session) leaves local main behind origin. Until 2026-10-09 nothing caught it
    up, so every landing waited on handoff_status's "clean main-worktree
    synchronization" for a person to pull by hand, and cards sat at "waiting to
    start" for hours. This is that synchronization, done only when it is a pure
    fast-forward over a checkout whose only changes are the regenerable cache.
    Returns what happened: current, advanced, diverged, primary, dirty or raced."""
    parent = main_head(repo)
    if not target or target == parent:
        return "current"
    if git(repo, "merge-base", "--is-ancestor", parent, target, check=False).returncode:
        return "diverged"
    holder = main_checkout(repo)
    if holder:
        if os.path.realpath(holder) == _primary_checkout(repo):
            return "primary"
        if git(holder, "rev-parse", "HEAD").stdout.strip() != parent or \
                git(holder, "diff", "--cached", "--quiet", check=False).returncode:
            return "dirty"
        changed = [p for p in git(holder, "diff", "--name-only").stdout.splitlines() if p]
        if any(p not in REGENERABLE for p in changed):
            return "dirty"
        if changed:
            git(holder, "restore", "--source=HEAD", "--worktree", "--", *changed)
        if _untracked_collision(holder, parent, target):
            return "dirty"
    if git(repo, "update-ref", "refs/heads/main", target, parent, check=False).returncode:
        return "raced"
    if holder and not synchronize_main(repo, target, parent, holder):
        raise RuntimeError("Local main caught up with origin, but its dedicated checkout needs safe synchronization.")
    return "advanced"


def synchronize_main(repo, commit, parent, holder=None):
    """Repair only the known-stale index/worktree of a dedicated main owner.

    This may run again after a crash between the ref CAS and checkout update.
    It never overwrites a user edit: index must still be the old tree, worktree
    must equal that index. Rescued play sessions may remain untracked, but any
    other untracked file blocks synchronization.
    """
    holder = holder or main_checkout(repo)
    if not holder or os.path.realpath(holder) == _primary_checkout(repo):
        return False
    if main_head(repo) != commit or git(holder, "rev-parse", "HEAD").stdout.strip() != commit:
        return False
    target_tree = git(repo, "rev-parse", commit + "^{tree}").stdout.strip()
    indexed_tree = git(holder, "write-tree").stdout.strip()
    if indexed_tree == target_tree and _owner_state(holder, commit):
        return True
    old_tree = git(repo, "rev-parse", parent + "^{tree}").stdout.strip()
    if indexed_tree != old_tree or \
            git(holder, "diff", "--quiet", check=False).returncode or \
            _untracked_collision(holder, parent, commit):
        return False
    # Merge the known old and new trees into the clean dedicated checkout.
    # read-tree refuses an unexpected worktree change rather than forcing it.
    git(holder, "read-tree", "-m", "-u", parent, commit)
    return _owner_state(holder, commit)


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

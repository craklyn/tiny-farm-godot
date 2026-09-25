"""HQ's live records keep their own history, saved without anyone remembering.

Q-125 (a), ruled 2026-09-25: HQ's live records (work cards, rulings, goals,
seat notes and the rest of what HQ writes while it runs; ``roots.LIVE_RECORDS``)
live in one folder outside the game repository, and that folder is its own Git
repository.  Checked-in configuration and curated design material (decision
cards, projects, look sheets; ``roots.REPO_OWNED``) stay on main.
Before the ruling every card existed twice — HQ's copy in the shared checkout
and main's tracked copy — and nothing kept them in step, so finished work kept
showing as unfinished.

This module is the history half.  One background thread in the server watches
the store and commits once per burst of writes: it waits until the set of
changed files has stopped changing for ``QUIET_SECONDS`` and then records them
in one commit whose subject names what changed ("Record 2 work cards (w12…
landed), ruling Q-125").  It watches Git status rather than hooking each
writer, so writes by the drain, the close command and hand edits are all kept,
not only the server's own.

It commits only when the data root is itself the top of a Git repository.  An
in-repository data root (the historical ``hq/data`` default, and every test
scratch store without ``git init``) is left alone: HQ must never commit into
the game repository on its own.
"""

import json
import os
import subprocess
import threading
import time
from pathlib import Path

import roots

QUIET_SECONDS = 20
POLL_SECONDS = 5
AUTHOR = ("Tiny Farm HQ", "hq@tiny-farm.local")

# Written into a new store by the migration and kept there.  Bulk worker logs
# and regenerable previews stay on disk but outside history, so the history
# stays small enough to read.
GITIGNORE = """\
# Written by hq/store.py. Bulk run logs and regenerable previews are kept on
# disk but not in history.
runs/workers/
loop_previews/
sprite_backups/
server.nohup.log
*.tmp
*.lock
__pycache__/
"""


def _git(root, *args, check=True):
    return subprocess.run(
        ["git", "-C", str(root), "-c", "core.hooksPath=/dev/null",
         "-c", f"user.name={AUTHOR[0]}", "-c", f"user.email={AUTHOR[1]}", *args],
        capture_output=True, text=True, check=check)


def is_own_repository(root):
    """True only when ``root`` is the top of its own Git repository."""
    try:
        top = _git(root, "rev-parse", "--show-toplevel").stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return False
    return bool(top) and os.path.realpath(top) == os.path.realpath(root)


def init(root):
    """Make ``root`` a store with history.  Idempotent; returns True if created."""
    root = Path(root)
    if is_own_repository(root):
        return False
    _git(root, "init", "-q", "-b", "main")
    marker = root / roots.STORE_MARKER
    if not marker.exists():
        marker.write_text("Tiny Farm HQ's live records (Q-125 a). "
                          "See docs/hq/HQ_DATA_MIGRATION.md in the game repository.\n")
    ignore = root / ".gitignore"
    if not ignore.exists():
        ignore.write_text(GITIGNORE)
    return True


def changed_paths(root):
    """Paths with uncommitted changes, relative to the store, sorted."""
    out = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all").stdout
    paths, entries, i = [], out.split("\0"), 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        status, path = entry[:2], entry[3:]
        if "R" in status or "C" in status:
            i += 1      # the rename's source follows as its own entry
        paths.append(path)
    return sorted(set(paths))


def _card_state(root, rel):
    try:
        doc = json.loads((Path(root) / rel).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "removed"
    return str(doc.get("state") or "") if isinstance(doc, dict) else ""


def describe(root, paths):
    """A commit message a reader with no context can follow: subject, then every path."""
    groups = {}
    for rel in paths:
        head = rel.split("/", 1)[0] if "/" in rel else ""
        groups.setdefault(head, []).append(rel)
    parts = []
    work = groups.pop("work", [])
    if work:
        named = []
        for rel in work[:3]:
            stem = Path(rel).stem
            state = _card_state(root, rel)
            named.append(f"{stem} {state}".strip())
        more = f", {len(work) - 3} more" if len(work) > 3 else ""
        noun = "work card" if len(work) == 1 else "work cards"
        parts.append(f"{len(work)} {noun} ({', '.join(named)}{more})")
    for folder, singular in (("rulings", "ruling"), ("decisions", "decision card")):
        rows = groups.pop(folder, [])
        if rows:
            ids = ", ".join(Path(r).stem for r in rows[:4]) + (" and more" if len(rows) > 4 else "")
            parts.append(f"{singular}{'s' if len(rows) > 1 else ''} {ids}")
    for folder in sorted(k for k in groups if k):
        rows = groups[folder]
        parts.append(f"{folder} ({len(rows)} file{'s' if len(rows) > 1 else ''})")
    loose = groups.get("", [])
    if loose:
        parts.append(", ".join(loose[:3]) + (" and more" if len(loose) > 3 else ""))
    subject = "Record " + "; ".join(parts)
    if len(subject) > 100:
        subject = subject[:97].rstrip() + "..."
    body = "\n".join(paths[:200]) + ("\n..." if len(paths) > 200 else "")
    return subject + "\n\n" + body + "\n"


def commit(root):
    """Commit everything pending as one record; returns the message or ''."""
    paths = changed_paths(root)
    if not paths:
        return ""
    message = describe(root, paths)
    _git(root, "add", "-A")
    if not _git(root, "diff", "--cached", "--quiet", check=False).returncode:
        return ""
    _git(root, "commit", "-q", "-m", message)
    return message


def _fingerprint(root, paths):
    marks = []
    for rel in paths:
        try:
            st = os.stat(Path(root) / rel)
            marks.append((rel, st.st_mtime_ns, st.st_size))
        except OSError:
            marks.append((rel, 0, -1))
    return tuple(marks)


class AutoCommitter:
    """Commit once per burst: when the pending set has been still for a quiet spell."""

    def __init__(self, root, quiet=QUIET_SECONDS, clock=time.monotonic):
        self.root, self.quiet, self.clock = str(root), quiet, clock
        self._seen, self._since = None, None

    def tick(self):
        paths = changed_paths(self.root)
        if not paths:
            self._seen, self._since = None, None
            return ""
        mark = _fingerprint(self.root, paths)
        now = self.clock()
        if mark != self._seen:
            self._seen, self._since = mark, now
            return ""
        if now - self._since < self.quiet:
            return ""
        self._seen, self._since = None, None
        return commit(self.root)


def start(root, poll=POLL_SECONDS):
    """Start the background committer when ``root`` is a store with history."""
    if not is_own_repository(root):
        return None
    committer = AutoCommitter(root)

    def loop():
        while True:
            try:
                committer.tick()
            except (OSError, subprocess.CalledProcessError):
                pass
            time.sleep(poll)

    thread = threading.Thread(target=loop, name="hq-store-history", daemon=True)
    thread.start()
    return thread

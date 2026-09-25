#!/usr/bin/env python3
"""Main carries no copy of HQ's live records (Q-125 a).

Every HQ work card used to exist twice: HQ's copy and main's tracked copy,
which sessions edited when they closed work. Nothing kept them in step, so
finished work kept showing as unfinished. The live records now live only in
HQ's own store. This test fails the build if a commit puts one back on main —
a worker that edits a card file instead of running `python3 hq/card.py close`
turns CI red here — and makes every checked-in entry of hq/data say which kind
it is, so a new file cannot quietly start a second copy.
"""

from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "hq"))
import roots  # noqa: E402


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


class LiveRecords(unittest.TestCase):
    def test_no_live_record_is_tracked_on_main(self):
        paths = [f"hq/data/{name}" for name in roots.LIVE_RECORDS + roots.RUNTIME]
        tracked = git("ls-files", "--", *paths).stdout.split()
        self.assertEqual(tracked, [], "Live HQ records are committed. Close cards with "
                         "`python3 hq/card.py close` and remove these from the commit: "
                         + ", ".join(tracked[:10]))

    def test_every_live_record_is_ignored(self):
        for name in roots.LIVE_RECORDS + roots.RUNTIME:
            probe = f"hq/data/{name}/probe.json" if "." not in name else f"hq/data/{name}"
            got = git("check-ignore", "-q", "--no-index", probe)
            self.assertEqual(got.returncode, 0, f"{probe} is not ignored by git")

    def test_every_checked_in_entry_is_classified(self):
        tracked = git("ls-files", "--", "hq/data").stdout.split()
        tops = {p.split("/")[2] for p in tracked}
        allowed = set(roots.REPO_OWNED) | set(roots.SEEDED)
        self.assertEqual(sorted(tops - allowed), [],
                         "Classify each new hq/data entry in hq/roots.py (checked-in or live)")

    def test_the_kinds_do_not_overlap(self):
        kinds = [set(roots.REPO_OWNED), set(roots.LIVE_RECORDS), set(roots.RUNTIME), set(roots.SEEDED)]
        seen = set()
        for kind in kinds:
            self.assertFalse(seen & kind, f"{sorted(seen & kind)} is listed as two kinds")
            seen |= kind


if __name__ == "__main__":
    unittest.main()

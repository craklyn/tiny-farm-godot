#!/usr/bin/env python3
"""The one-time copy of HQ's live records into their own store (Q-125 a).

The dry run writes nothing; the real run copies every live and runtime file
(uncommitted ones included), keeps the checked-in files it will no longer read
in an archive, starts the store's history, checks every copy, and lists the
cards whose copy on main disagrees with the live one. The source is never touched.
"""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import migrate_store  # noqa: E402
import roots  # noqa: E402
import store  # noqa: E402


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), "-c", "user.name=T", "-c", "user.email=t@t",
                           "-c", "core.hooksPath=/dev/null", *args],
                          capture_output=True, text=True, check=True).stdout.strip()


def write(path, doc):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(doc if isinstance(doc, str) else json.dumps(doc))


class MigrateStore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.src, self.dest, self.main = base / "live", base / "store", base / "main"
        write(self.src / "org.json", {"employees": []})
        write(self.src / "decisions" / "Q-1.json", {"id": "Q-1", "ruled": {"option": "a"}})
        write(self.src / "work" / "w1.json", {"id": "w1", "state": "landed"})
        write(self.src / "work" / "w2.json", {"id": "w2", "state": "waiting_session"})
        write(self.src / "rulings" / "Q-1.json", {"id": "Q-1", "status": "integrated"})
        write(self.src / "staff" / "claude" / "memory.md", "notes\n")
        write(self.src / "runs" / "workers" / "r" / "log.jsonl", "{}\n")
        write(self.src / "execution_policy.json", {"version": 1})
        write(self.src / "mystery.txt", "keep me\n")
        # main: tracks the same cards, one of them finished only there
        write(self.main / "hq" / "data" / "org.json", {"employees": []})
        write(self.main / "hq" / "data" / "decisions" / "Q-1.json", {"id": "Q-1"})
        write(self.main / "hq" / "data" / "work" / "w1.json", {"id": "w1", "state": "for_review"})
        write(self.main / "hq" / "data" / "work" / "w2.json", {"id": "w2", "state": "landed"})
        write(self.main / "hq" / "data" / "rulings" / "Q-1.json", {"id": "Q-1", "status": "pending_integration"})
        git(self.main.parent, "init", "-q", "-b", "main", str(self.main))
        git(self.main, "add", "-A")
        git(self.main, "commit", "-q", "-m", "tracked cards")
        self.before = {p: p.read_bytes() for p in self.src.rglob("*") if p.is_file()}

    def tearDown(self):
        self.tmp.cleanup()

    def run_it(self, *extra):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = migrate_store.main(["--source", str(self.src), "--dest", str(self.dest),
                                       "--main", str(self.main), "--ref", "main", "--json", *extra])
        return code, json.loads(out.getvalue())

    def test_dry_run_reports_and_writes_nothing(self):
        code, report = self.run_it("--dry-run")
        self.assertEqual(code, 0)
        self.assertFalse(self.dest.exists())
        self.assertEqual(report["copy"]["live"], ["rulings", "staff", "work"])
        self.assertEqual(report["copy"]["unknown"], ["mystery.txt"])
        self.assertEqual(report["archived_not_read"], ["decisions", "org.json"])
        self.assertEqual(report["config_differs_from_main"], ["decisions/Q-1.json"])
        drift = {d["record"]: d for d in report["drift"]}
        self.assertEqual(set(drift), {"work/w1.json", "work/w2.json", "rulings/Q-1.json"})
        self.assertIn("close it with hq/card.py", drift["work/w2.json"]["note"],
                      "a card finished only on main is called out, not silently dropped")

    def test_the_real_run_copies_everything_and_starts_history(self):
        code, report = self.run_it()
        self.assertEqual(code, 0)
        self.assertEqual(report["mismatched"], [])
        self.assertTrue(store.is_own_repository(self.dest))
        self.assertTrue((self.dest / roots.STORE_MARKER).is_file())
        self.assertEqual(json.loads((self.dest / "work" / "w2.json").read_text())["state"],
                         "waiting_session", "the live copy is what moves")
        self.assertTrue((self.dest / "runs" / "workers" / "r" / "log.jsonl").is_file())
        self.assertTrue((self.dest / "mystery.txt").is_file())
        self.assertFalse((self.dest / "org.json").exists(), "configuration is read from main")
        self.assertTrue((self.dest / migrate_store.ARCHIVE / "decisions" / "Q-1.json").is_file(),
                        "a checked-in edit found only in the live folder is archived, not lost")
        tracked = git(self.dest, "ls-files").split()
        self.assertIn("work/w1.json", tracked)
        self.assertNotIn("runs/workers/r/log.jsonl", tracked)
        self.assertEqual(git(self.dest, "rev-list", "--count", "HEAD"), "1")
        self.assertEqual(report["uncommitted_after_import"], [])
        after = {p: p.read_bytes() for p in self.src.rglob("*") if p.is_file()}
        self.assertEqual(after, self.before, "the source is never changed")
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(io.StringIO()):
                self.run_it()          # a second run refuses to mix into a non-empty store


if __name__ == "__main__":
    unittest.main()

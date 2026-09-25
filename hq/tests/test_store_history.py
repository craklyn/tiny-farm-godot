#!/usr/bin/env python3
"""HQ's live store keeps its own history: one commit per burst of writes (Q-125 a)."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import store  # noqa: E402


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                          text=True, check=True).stdout


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class StoreHistory(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "store"
        (self.root / "work").mkdir(parents=True)
        (self.root / "org.json").write_text("{}")

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, cid, state):
        (self.root / "work" / f"{cid}.json").write_text(json.dumps({"id": cid, "state": state}))

    def test_a_folder_inside_another_repository_is_never_committed(self):
        outer = Path(self.tmp.name) / "game"
        (outer / "hq" / "data").mkdir(parents=True)
        git(outer, "init", "-q")
        inner = outer / "hq" / "data"
        (inner / "org.json").write_text("{}")
        self.assertFalse(store.is_own_repository(inner))
        self.assertIsNone(store.start(inner))
        self.assertEqual(git(outer, "rev-list", "--all", "--count").strip(), "0")

    def test_a_burst_is_committed_once_after_it_goes_quiet(self):
        self.assertTrue(store.init(self.root))
        self.assertFalse(store.init(self.root))
        self.assertIn("runs/workers/", (self.root / ".gitignore").read_text())
        store.commit(self.root)
        base = int(git(self.root, "rev-list", "--count", "HEAD"))
        clock = Clock()
        committer = store.AutoCommitter(self.root, quiet=20, clock=clock)
        self.card("w111111111aa", "landed")
        self.assertEqual(committer.tick(), "")          # first sight of the burst
        clock.now = 5
        self.card("w222222222bb", "waiting_session")     # the burst keeps going
        (self.root / "rulings").mkdir()
        (self.root / "rulings" / "Q-9.json").write_text("{}")
        self.assertEqual(committer.tick(), "")
        clock.now = 15
        self.assertEqual(committer.tick(), "")           # still inside the quiet spell
        clock.now = 30
        message = committer.tick()
        self.assertTrue(message.startswith("Record 2 work cards (w111111111aa landed, "
                                           "w222222222bb waiting_session); ruling Q-9"),
                        message)
        self.assertEqual(int(git(self.root, "rev-list", "--count", "HEAD")), base + 1)
        self.assertEqual(store.changed_paths(self.root), [])
        clock.now = 60
        self.assertEqual(committer.tick(), "")           # nothing new, no empty commit
        self.assertEqual(int(git(self.root, "rev-list", "--count", "HEAD")), base + 1)

    def test_bulk_worker_logs_stay_out_of_history(self):
        store.init(self.root)
        (self.root / "runs" / "workers" / "run1").mkdir(parents=True)
        (self.root / "runs" / "workers" / "run1" / "log.txt").write_text("x" * 100)
        (self.root / "runs" / "drain.json").write_text("{}")
        paths = store.changed_paths(self.root)
        self.assertIn("runs/drain.json", paths)
        self.assertFalse(any(p.startswith("runs/workers/") for p in paths))

    def test_message_names_removed_cards_and_other_folders(self):
        store.init(self.root)
        self.card("w333333333cc", "doing")
        store.commit(self.root)
        os.remove(self.root / "work" / "w333333333cc.json")
        (self.root / "projects").mkdir()
        (self.root / "projects" / "p.json").write_text("{}")
        message = store.commit(self.root)
        self.assertTrue(message.startswith("Record 1 work card (w333333333cc removed); projects (1 file)"),
                        message)
        self.assertIn("work/w333333333cc.json", message)


class ConfigurationStaysOnMain(unittest.TestCase):
    """With a store that has its own history, checked-in files are read beside the code."""

    def test_reads_split_by_kind(self):
        import server
        tmp = tempfile.TemporaryDirectory()
        saved = server.DATA
        try:
            root = Path(tmp.name)
            (root / "rulings").mkdir()
            (root / "rulings" / "Q-1.json").write_text(json.dumps({"id": "Q-1"}))
            (root / "decisions").mkdir()
            (root / "decisions" / "Q-1.json").write_text(json.dumps({"id": "Q-1", "title": "stale copy"}))
            server.DATA = str(root)
            self.assertEqual(server.cfg("org.json"), str(root / "org.json"),
                             "a data root without its own history still holds its configuration")
            store.init(root)
            server.DATA = str(root) + os.sep + "."   # a fresh key for the cached look-up
            code_data = Path(server.HQ_DIR) / "data"
            self.assertEqual(Path(server.cfg("org.json")), code_data / "org.json")
            self.assertEqual({r["id"] for r in server.load_dir_json("rulings")}, {"Q-1"},
                             "live records come from the store")
            curated = server.load_dir_json("decisions")
            self.assertNotIn("stale copy", [d.get("title") for d in curated],
                             "decision cards come from main, never a copy left in the store")
            self.assertEqual(len(curated), len(list((code_data / "decisions").glob("*.json"))))
            with self.assertRaises(ValueError):
                server.cfg("work")
        finally:
            server.DATA = saved
            tmp.cleanup()


if __name__ == "__main__":
    unittest.main()

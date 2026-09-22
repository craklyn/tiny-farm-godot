#!/usr/bin/env python3
"""The HQ runner discovers, isolates and refuses to hide incomplete tests."""
from pathlib import Path
import contextlib
import io
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_tests


class HqTestRunnerTests(unittest.TestCase):
    def test_discovery_orders_python_before_node_and_rejects_unknown_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("test_z.js", "test_b.py", "test_a.py"):
                (root / name).write_text("")
            self.assertEqual([path.name for path in run_tests.discover(root)],
                             ["test_a.py", "test_b.py", "test_z.js"])
            (root / "test_unrecognized.txt").write_text("")
            with self.assertRaisesRegex(run_tests.RunnerError, "Unrecognized"):
                run_tests.discover(root)

    def test_each_file_gets_its_own_scratch_path(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            scratch = root / "scratch"
            scratch.mkdir()
            tests = []
            for name in ("test_one.py", "test_two.py"):
                path = root / name
                path.write_text("import os\nfrom pathlib import Path\nPath(os.environ['HQ_TEST_SCRATCH'], 'seen').write_text(os.environ['TMPDIR'])\n")
                tests.append(path)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertTrue(run_tests.run_files(tests, 2, scratch))
            seen = sorted(path.parent for path in scratch.glob("*/seen"))
            self.assertEqual(len(seen), 2)
            self.assertNotEqual(seen[0], seen[1])

    def test_skip_timeout_and_nonzero_exit_fail(self):
        cases = {
            "test_skip.py": "print('OK (skipped=1)')\n",
            "test_timeout.py": "import time; time.sleep(2)\n",
            "test_failure.py": "raise SystemExit(3)\n",
        }
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, source in cases.items():
                path = root / name
                path.write_text(source)
                scratch = root / (name + "-scratch")
                scratch.mkdir()
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertFalse(run_tests.run_files([path], .05, scratch), name)


if __name__ == "__main__":
    unittest.main()

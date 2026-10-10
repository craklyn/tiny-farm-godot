"""The tablet deploy keeps each installed commit on GitHub, and never stops for it.

Runs tools/save_build_marker.sh in a scratch repository whose "GitHub" is a bare
repository on disk, so nothing here touches the network or the tablet.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "save_build_marker.sh"
ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
           GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, check=True,
                          capture_output=True, text=True).stdout.strip()


class BuildMarkerTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.remote = os.path.join(tmp.name, "github.git")
        self.repo = os.path.join(tmp.name, "game")
        git(tmp.name, "init", "-q", "--bare", self.remote)
        git(tmp.name, "init", "-q", self.repo)
        os.makedirs(os.path.join(self.repo, "tools"))
        shutil.copy(SCRIPT, os.path.join(self.repo, "tools", "save_build_marker.sh"))
        git(self.repo, "remote", "add", "origin", self.remote)
        self.pending = Path(self.repo, "build", "unsaved_build_markers.txt")

    def commit(self, message):
        git(self.repo, "commit", "-q", "--allow-empty", "-m", message)
        return git(self.repo, "rev-parse", "HEAD")

    def save(self):
        return subprocess.run(["bash", "tools/save_build_marker.sh", "HEAD"], cwd=self.repo,
                              env=ENV, capture_output=True, text=True, timeout=120)

    def marker(self, sha):
        return subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"refs/builds/{sha}"],
                              cwd=self.remote, env=ENV, capture_output=True, text=True).stdout.strip()

    def test_an_unpushed_commit_is_kept_on_the_remote_under_refs_builds(self):
        sha = self.commit("a tablet try on an unmerged branch")
        run = self.save()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.marker(sha), sha)
        self.assertFalse(self.pending.exists())
        # No tag of any kind, so no release can be published by it.
        self.assertEqual(git(self.remote, "tag"), "")

    def test_no_network_warns_records_and_does_not_stop_the_deploy(self):
        git(self.repo, "remote", "set-url", "origin", os.path.join(self.repo, "nowhere.git"))
        first = self.commit("built with the network down")
        run = self.save()
        self.assertEqual(run.returncode, 0)
        self.assertIn("WARNING", run.stderr)
        self.assertIn(first, run.stderr)
        self.assertEqual(self.pending.read_text().split(), [first])

        # The next deploy, with the network back, saves both.
        git(self.repo, "remote", "set-url", "origin", self.remote)
        second = self.commit("the next tablet build")
        run = self.save()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.marker(first), first)
        self.assertEqual(self.marker(second), second)
        self.assertFalse(self.pending.exists())


if __name__ == "__main__":
    unittest.main()

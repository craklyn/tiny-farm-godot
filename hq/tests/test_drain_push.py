#!/usr/bin/env python3
"""What the drain landed reaches origin/main on its own, and only safely."""
from pathlib import Path
import os
import random
import shutil
import string
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain

CHECK = Path(__file__).resolve().parents[2] / "tools" / "check_secrets.py"
# Publishing needs gitleaks; the desktop has it and CI installs the same build
# (tests.yml). HQ's runner fails a skipped test, so these never skip.


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class PushLanded(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="hq-push-")
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.origin, self.main, self.other = root / "origin.git", root / "main", root / "other"
        git(root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        for clone in (self.main, self.other):
            git(root, "clone", "-q", str(self.origin), str(clone))
            git(clone, "config", "user.email", "t@example.com")
            git(clone, "config", "user.name", "T")
            git(clone, "config", "core.hooksPath", "/dev/null")
        self.commit(self.main, "a.txt", "first\n")
        git(self.main, "push", "-q", "origin", "main")
        git(self.other, "pull", "-q", "origin", "main")

    def commit(self, repo, name, text):
        (repo / name).write_text(text)
        git(repo, "add", name)
        git(repo, "commit", "-q", "-m", f"add {name}")

    def origin_head(self):
        return git(self.origin, "rev-parse", "main")

    def test_a_landed_commit_is_pushed(self):
        self.commit(self.main, "b.txt", "landed work\n")
        self.assertEqual(drain.push_landed(str(self.main)), "")
        self.assertEqual(self.origin_head(), git(self.main, "rev-parse", "main"))

    def test_nothing_to_push_is_quiet(self):
        self.assertEqual(drain.push_landed(str(self.main)), "")

    def test_a_credential_shaped_line_is_never_pushed(self):
        before = self.origin_head()
        # A realistic GitHub token shape: gitleaks rightly ignores low-entropy repeats.
        rng = random.Random(11)
        token = "ghp_" + "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(36))
        self.commit(self.main, "c.txt", f"github_token: {token}\n")
        self.assertIn("credential", drain.push_landed(str(self.main)))
        self.assertEqual(self.origin_head(), before)

    def test_an_env_file_is_never_pushed(self):
        before = self.origin_head()
        self.commit(self.main, ".env", "X=1\n")
        self.assertIn("credential", drain.push_landed(str(self.main)))
        self.assertEqual(self.origin_head(), before)

    def test_a_planted_key_from_env_is_never_pushed(self):
        # The keys the studio holds (Retro Diffusion, Freesound, itch.io) have no
        # shape GitHub or gitleaks knows; only their exact values catch them.
        fake = "rdk_" + "Zq7Lp2Xw9Vt4" * 3
        (self.main / ".env").write_text(f'RETRODIFFUSION_API_KEY="{fake}"\n')
        (self.main / ".gitignore").write_text(".env\n")
        before = self.origin_head()
        self.commit(self.main, "prompt.txt", f"curl -H 'X-RD-Token: {fake}' ...\n")
        why = drain.push_landed(str(self.main))
        self.assertIn("RETRODIFFUSION_API_KEY", why)
        self.assertNotIn(fake, why)
        self.assertEqual(self.origin_head(), before)

    def test_staged_check_catches_the_key_before_it_is_committed(self):
        fake = "fsk_" + "Hn3Rb8Qm5Ty1" * 3
        (self.main / ".env").write_text(f"FREESOUND_API_KEY={fake}\n")
        (self.main / "notes.txt").write_text(f"key is {fake}\n")
        git(self.main, "add", "notes.txt")
        run = subprocess.run([sys.executable, str(CHECK), "--staged"], cwd=self.main,
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertIn("FREESOUND_API_KEY", run.stderr)
        self.assertNotIn(fake, run.stderr + run.stdout)

    def test_without_gitleaks_nothing_is_pushed(self):
        # Fails closed: a push the scanner could not check never happens.
        bare = Path(self.main).parent / "bin"
        bare.mkdir()
        os.symlink(shutil.which("git"), bare / "git")
        before = self.origin_head()
        self.commit(self.main, "b.txt", "landed work\n")
        with patch.dict(os.environ, {"PATH": str(bare)}):
            why = drain.push_landed(str(self.main))
        self.assertIn("gitleaks is not installed", why)
        self.assertEqual(self.origin_head(), before)

    def test_origin_that_moved_is_left_alone(self):
        self.commit(self.other, "d.txt", "someone else\n")
        git(self.other, "push", "-q", "origin", "main")
        theirs = self.origin_head()
        self.commit(self.main, "e.txt", "landed work\n")
        self.assertIn("moved", drain.push_landed(str(self.main)))
        self.assertEqual(self.origin_head(), theirs)


if __name__ == "__main__":
    unittest.main()

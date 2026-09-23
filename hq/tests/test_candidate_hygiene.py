#!/usr/bin/env python3
"""Private revision commits and generated files must not change reviewed candidates."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain


def git(root, *args):
    return subprocess.run(["git", *args], cwd=root, check=True,
                          capture_output=True, text=True).stdout.strip()


class CandidateHygiene(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hq-candidate-hygiene-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.name", "HQ Test")
        git(self.repo, "config", "user.email", "hq-test@example.invalid")
        (self.repo / "docs").mkdir()
        (self.repo / "docs/writing_verdicts.json").write_text('{"verdicts": {}}\n')
        (self.repo / "game.gd").write_text("base\n")
        git(self.repo, "add", "docs/writing_verdicts.json", "game.gd")
        git(self.repo, "commit", "-qm", "Base")
        self.base = git(self.repo, "rev-parse", "HEAD")

        # The real commit-msg hook judges the subject and writes this ledger.
        # The synthetic commit must not invoke it or collect its side effect.
        hooks = Path(self.temp.name) / "hooks"
        hooks.mkdir()
        hook = hooks / "commit-msg"
        hook.write_text("#!/bin/sh\nprintf '%s\\n' '{\"verdicts\": {\"synthetic\": {\"verdict\": \"ok\"}}' > docs/writing_verdicts.json\n")
        hook.chmod(0o755)
        git(self.repo, "config", "core.hooksPath", str(hooks))

    def test_held_patch_revision_does_not_collect_synthetic_commit_verdict(self):
        (self.repo / "game.gd").write_text("held patch\n")
        committed, _ = drain.resume_for_revision(
            {"id": "w0123456789ab", "revising": True, "diff": {"applied": False}},
            str(self.repo), False)
        self.assertTrue(committed)
        self.assertEqual((self.repo / "docs/writing_verdicts.json").read_text(),
                         '{"verdicts": {}}\n')
        self.assertEqual(git(self.repo, "show", "--format=", "--name-only", "HEAD"), "game.gd")

        (self.repo / "game.gd").write_text("revised patch\n")
        patch, _stat, files = drain.cumulative_patch(str(self.repo), self.base)
        self.assertEqual(files, ["game.gd"])
        self.assertNotIn("writing_verdicts", patch)
        tree = git(self.repo, "write-tree")
        self.assertTrue(drain.candidate_unchanged(str(self.repo), tree))

        # Godot can generate a new sidecar after the candidate is recorded.
        # An untracked file must make the candidate stale, even though git diff
        # against a tree alone would incorrectly say it is unchanged.
        (self.repo / "game.gd.uid").write_text("generated\n")
        self.assertFalse(drain.candidate_unchanged(str(self.repo), tree))
        self.assertTrue(drain.restore_test_generated(str(self.repo), tree))
        self.assertFalse((self.repo / "game.gd.uid").exists())
        self.assertTrue(drain.candidate_unchanged(str(self.repo), tree))
        (self.repo / "docs/writing_verdicts.json").write_text("generated after test\n")
        self.assertFalse(drain.candidate_unchanged(str(self.repo), tree))
        self.assertTrue(drain.restore_test_generated(str(self.repo), tree))
        self.assertEqual((self.repo / "docs/writing_verdicts.json").read_text(),
                         '{"verdicts": {}}\n')
        self.assertTrue(drain.candidate_unchanged(str(self.repo), tree))

        # Do not disguise changes that are not known test byproducts.
        (self.repo / "game.gd").write_text("changed after test\n")
        self.assertTrue(drain.restore_test_generated(str(self.repo), tree))
        self.assertFalse(drain.candidate_unchanged(str(self.repo), tree))

    def test_authored_verdict_in_candidate_is_preserved(self):
        authored = '{"verdicts": {"approved": {"verdict": "ok"}}}\n'
        (self.repo / "docs/writing_verdicts.json").write_text(authored)
        git(self.repo, "add", "docs/writing_verdicts.json")
        tree = git(self.repo, "write-tree")
        (self.repo / "docs/writing_verdicts.json").write_text("test byproduct\n")
        self.assertTrue(drain.restore_test_generated(str(self.repo), tree))
        self.assertEqual((self.repo / "docs/writing_verdicts.json").read_text(), authored)
        self.assertTrue(drain.candidate_unchanged(str(self.repo), tree))

    def test_reviewed_unrelated_verdict_is_removed_only_from_retry(self):
        (self.repo / "game.gd").write_text("held patch\n")
        (self.repo / "docs/writing_verdicts.json").write_text('{"verdicts": {"synthetic": {}}}\n')
        held = git(self.repo, "diff", "--binary") + "\n"
        with patch.object(drain, "PATCHES", str(Path(self.temp.name) / "patches")):
            drain.save_patch("w0123456789ab", held)
            original = drain.patch_artifact(held)
            self.assertEqual(Path(original["path"]).read_text(), held)
            git(self.repo, "restore", "--", "game.gd", "docs/writing_verdicts.json")

            item = {"id": "w0123456789ab", "revising": True,
                    "diff": {"applied": False}, "prior_checks": [{
                        "verdict": "fail", "unrelated_generated_files": ["docs/writing_verdicts.json"],
                        "findings": [{"where": "docs/writing_verdicts.json", "fix": "Remove this unrelated ledger."}]}]}
            self.assertTrue(drain.resume_held_patch(item, str(self.repo), False))
            self.assertEqual((self.repo / "docs/writing_verdicts.json").read_text(),
                             '{"verdicts": {}}\n')
            self.assertTrue(drain.resume_for_revision(item, str(self.repo), False)[0])
            revised, _stat, files = drain.cumulative_patch(str(self.repo), self.base)
            self.assertEqual(files, ["game.gd"])
            self.assertNotIn("writing_verdicts", revised)
            drain.save_patch(item["id"], revised)
            self.assertNotEqual(drain.patch_artifact(revised), original)
            self.assertEqual(Path(original["path"]).read_text(), held)

    def test_unreviewed_generated_file_remains_in_held_patch(self):
        (self.repo / "docs/writing_verdicts.json").write_text("authored change\n")
        held = git(self.repo, "diff", "--binary") + "\n"
        with patch.object(drain, "PATCHES", str(Path(self.temp.name) / "patches")):
            drain.save_patch("w0123456789ab", held)
            git(self.repo, "restore", "--", "docs/writing_verdicts.json")
            for prior in ([], [{"verdict": "fail", "unrelated_generated_files": ["docs/writing_verdicts.json"],
                               "findings": [{"where": "docs/writing_verdicts.json", "fix": "Check this."}]}]):
                item = {"id": "w0123456789ab", "prior_checks": prior}
                self.assertTrue(drain.resume_held_patch(item, str(self.repo), False))
                self.assertEqual((self.repo / "docs/writing_verdicts.json").read_text(), "authored change\n")
                git(self.repo, "restore", "--", "docs/writing_verdicts.json")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""A card closes only through HQ, and only with evidence (Q-125 a).

A session closes a card with the commit that landed the work and the CI run
that passed on it. HQ checks both itself — the commit must be on origin/main,
the run must be the tests workflow, finished, successful, on that commit or a
later main — and refuses otherwise. The closed card says who closed it and that
no checker or Daniel approval was recorded. A claim from an outside session
shows the card as being worked, and lapses when the session stops renewing it.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HQ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HQ))

import closing  # noqa: E402
import work  # noqa: E402
from reconcile_process_completion import FileHost  # noqa: E402


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), "-c", "user.name=T", "-c", "user.email=t@t",
                           "-c", "core.hooksPath=/dev/null", *args],
                          capture_output=True, text=True, check=True).stdout.strip()


class FakeGitHub:
    """Real git; ``gh run view`` answered from a table of runs."""

    def __init__(self):
        self.runs = {}

    def __call__(self, cmd, cwd):
        if cmd[:3] == ["gh", "run", "view"]:
            doc = self.runs.get(cmd[3])
            if doc is None:
                return subprocess.CompletedProcess(cmd, 1, "", "run not found")
            return subprocess.CompletedProcess(cmd, 0, json.dumps(doc), "")
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


class CardClose(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        origin, self.repo = base / "origin.git", base / "main"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(origin), str(self.repo)], check=True,
                       capture_output=True)
        git(self.repo, "checkout", "-q", "-b", "main")
        (self.repo / "a.txt").write_text("1")
        git(self.repo, "add", "a.txt")
        git(self.repo, "commit", "-q", "-m", "first")
        self.landed = git(self.repo, "rev-parse", "HEAD")
        (self.repo / "a.txt").write_text("2")
        git(self.repo, "commit", "-q", "-am", "second")
        self.later = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "push", "-q", "origin", "main")
        (self.repo / "a.txt").write_text("3")
        git(self.repo, "commit", "-q", "-am", "local only")
        self.unpushed = git(self.repo, "rev-parse", "HEAD")

        self.data = base / "data"
        (self.data / "work").mkdir(parents=True)
        (self.data / "rulings").mkdir()
        (self.data / "org.json").write_text(json.dumps({"employees": [{"id": "claude"}]}))
        work.bind(FileHost(self.data), sanitize=False)
        self.gh = FakeGitHub()
        self.gh.runs["100"] = {"workflowName": "tests", "status": "completed",
                               "conclusion": "success", "headSha": self.later, "url": "u"}
        self.gh.runs["101"] = {"workflowName": "tests", "status": "completed",
                               "conclusion": "failure", "headSha": self.later}
        self.gh.runs["102"] = {"workflowName": "tests", "status": "in_progress",
                               "conclusion": "", "headSha": self.later}
        self.gh.runs["103"] = {"workflowName": "release", "status": "completed",
                               "conclusion": "success", "headSha": self.later}
        self.card("w0000000000a")

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, cid, **extra):
        doc = {"id": cid, "title": "Do a thing", "owner": "claude", "tier": 1,
               "state": "waiting_session", "created_ts": 1, **extra}
        (self.data / "work" / f"{cid}.json").write_text(json.dumps(doc))

    def close(self, cid="w0000000000a", **kw):
        args = {"sha": self.landed[:9], "ci_run": "100", "by": "Codex session",
                "result": "The thing is done and on main, with its tests."}
        args.update(kw)
        return closing.close(cid, main_root=str(self.repo), run=self.gh, **args)

    def refused(self, fragment, **kw):
        with self.assertRaises(closing.Refused) as caught:
            self.close(**kw)
        self.assertIn(fragment, str(caught.exception))
        self.assertEqual(work.load_item("w0000000000a")["state"], "waiting_session")

    def test_every_missing_piece_of_evidence_is_refused(self):
        self.refused("hexadecimal", sha="")
        self.refused("does not exist", sha="deadbeef")
        self.refused("not on origin/main", sha=self.unpushed)
        self.refused("CI run id", ci_run="")
        self.refused("Could not read CI run", ci_run="999")
        self.refused("concluded failure", ci_run="101")
        self.refused("has not finished", ci_run="102")
        self.refused("'release' workflow", ci_run="103")
        self.refused("Write the result", result="done")
        self.refused("Say who", by="")
        self.refused("may not claim Daniel", by="Daniel")
        self.refused("may not claim Daniel", by="the checker")

    def test_a_run_that_did_not_contain_the_commit_is_refused(self):
        self.gh.runs["104"] = {"workflowName": "tests", "status": "completed",
                               "conclusion": "success", "headSha": self.landed}
        with self.assertRaises(closing.Refused) as caught:
            closing.close("w0000000000a", sha=self.later, ci_run="104", by="Codex session",
                          result="The thing is done and on main, with its tests.",
                          main_root=str(self.repo), run=self.gh)
        self.assertIn("does not contain", str(caught.exception))

    def test_a_close_with_evidence_lands_the_card_honestly(self):
        closing.claim("w0000000000a", by="Codex session")
        item = self.close()
        self.assertEqual(item["state"], "landed")
        self.assertEqual(item["landed"]["sha"], self.landed)
        self.assertEqual(item["landed"]["by"], "Codex session")
        evidence = item["completion"]["evidence"]
        self.assertEqual(item["completion"]["kind"], "session_close")
        self.assertEqual(evidence["ci_run"]["conclusion"], "success")
        self.assertEqual(evidence["ci_run"]["head_sha"], self.later)
        self.assertIn("no checker or Daniel approval", evidence["limitations"])
        self.assertIsNone(item.get("check"))
        self.assertNotIn("outside_claim", item)
        self.assertEqual(work.completion_assessment(item)[0], "completed")
        with self.assertRaises(closing.Refused):
            self.close()

    def test_closing_an_integrate_ruling_card_integrates_the_ruling(self):
        (self.data / "rulings" / "Q-7.json").write_text(
            json.dumps({"id": "Q-7", "option": "a", "status": "pending_integration"}))
        self.card("w0000000000b", ruling_id="Q-7")
        self.close("w0000000000b")
        ruling = json.loads((self.data / "rulings" / "Q-7.json").read_text())
        self.assertEqual(ruling["status"], "integrated")
        self.assertEqual(ruling["integrated"]["work_id"], "w0000000000b")

    def test_a_claim_is_a_lease_that_its_holder_renews_or_releases(self):
        first = closing.claim("w0000000000a", by="Codex session", seconds=600, now=1000)
        held = first["outside_claim"]
        self.assertEqual(held["expires_ts"], 1600)
        self.assertIs(closing.live_claim(first, now=1500), held)
        self.assertIsNone(closing.live_claim(first, now=1700))
        with self.assertRaises(closing.Refused):
            closing.claim("w0000000000a", by="Another session", now=1100)
        renewed = closing.claim("w0000000000a", by="Codex session", seconds=600, now=1500)
        self.assertEqual(renewed["outside_claim"]["since"], held["since"])
        self.assertEqual(renewed["outside_claim"]["expires_ts"], 2100)
        taken = closing.claim("w0000000000a", by="Another session", seconds=600, now=2200)
        self.assertEqual(taken["outside_claim"]["by"], "Another session")
        with self.assertRaises(closing.Refused):
            closing.release("w0000000000a", by="Codex session", now=2300)
        self.assertNotIn("outside_claim",
                         closing.release("w0000000000a", by="Another session", now=2300))
        with self.assertRaises(closing.Refused):
            closing.claim("w0000000000a", by="Codex session", seconds=5)


if __name__ == "__main__":
    unittest.main()

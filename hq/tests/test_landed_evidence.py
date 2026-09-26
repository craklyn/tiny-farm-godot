#!/usr/bin/env python3
"""A landed card is closed, names its commit, and shows the green run that tested it.

On 2026-09-25 the queue page listed 28 landed cards under "Back with the studio"
while the Engineering page's check counted them as closed. None named its commit, so
the page never put them under "Landed without you", and HQ's CI poller, which only
confirmed a run on the exact commit, had nothing to confirm. These tests pin the
fixes: the lanes the check counts travel with each card to the page, a green run on
a later main that contains the commit confirms it, a session close records its run
where the page reads CI, and the one-time command that adds the missing commits
(hq/confirm_landed_commits.py) previews, applies once, and refuses what it cannot
verify.
"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HQ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HQ))
sys.path.insert(0, str(HQ / "tests"))

import action_dispatch  # noqa: E402
import closing  # noqa: E402
import confirm_landed_commits  # noqa: E402
import work  # noqa: E402
from reconcile_process_completion import FileHost  # noqa: E402
from test_card_lanes import ORG, FakeGitHub, git  # noqa: E402


class LandedEvidence(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        origin, self.repo = base / "origin.git", base / "main"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(origin), str(self.repo)], check=True,
                       capture_output=True)
        git(self.repo, "checkout", "-q", "-b", "main")
        self.shas = []
        for n in range(3):
            (self.repo / "a.txt").write_text(str(n))
            git(self.repo, "add", "a.txt")
            git(self.repo, "commit", "-q", "-m", f"change {n}")
            self.shas.append(git(self.repo, "rev-parse", "HEAD"))
        git(self.repo, "push", "-q", "origin", "main")
        # One push of three commits: GitHub runs the tests once, on the last.
        tip = self.shas[-1]
        self.gh = FakeGitHub({
            "300": {"workflowName": "tests", "status": "completed", "conclusion": "success",
                    "headSha": tip, "url": "https://example.invalid/300"},
            "301": {"workflowName": "tests", "status": "completed", "conclusion": "failure",
                    "headSha": tip, "url": "https://example.invalid/301"},
        })
        self.data = base / "data"
        (self.data / "work").mkdir(parents=True)
        (self.data / "rulings").mkdir()
        (self.data / "org.json").write_text(json.dumps({"employees": [{"id": i} for i in ORG]}))
        work.bind(FileHost(self.data), sanitize=False)

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, cid, state="landed", **extra):
        doc = {"id": cid, "title": "A card", "owner": "tomas", "tier": 1, "state": state,
               "created_ts": 1, "closed": "2026-09-21T14:39", **extra}
        (self.data / "work" / f"{cid}.json").write_text(json.dumps(doc))
        return doc

    def shipped(self, cid):
        return work.work_view(work.load_item(cid), {}, now=0)["shipped_evidence"]

    # -- the CI poller -------------------------------------------------------

    def run_row(self, run_id, head, conclusion="success", at="2026-09-21T15:00:00Z"):
        return {"databaseId": run_id, "headSha": head, "status": "completed",
                "conclusion": conclusion, "url": f"https://example.invalid/{run_id}",
                "updatedAt": at}

    def test_a_green_run_on_a_later_main_confirms_the_commit_under_it(self):
        self.card("w000000000f1", completion={"sha": self.shas[0]})
        runs = [self.run_row(9, "f" * 40, at="2026-09-21T14:00:00Z"),
                self.run_row(10, self.shas[-1], at="2026-09-21T15:00:00Z"),
                self.run_row(11, self.shas[-1], at="2026-09-21T16:00:00Z")]
        # Without a way to check history the poller keeps to the exact commit.
        self.assertEqual(action_dispatch.poll_ci(work, work.items(), lambda: runs, now=100), 1)
        self.assertEqual(work.load_item("w000000000f1")["workflow"]["ci"]["status"], "unavailable")
        self.assertFalse(self.shipped("w000000000f1")["ci_confirmed"])
        contains = action_dispatch.repo_contains(str(self.repo))
        self.assertTrue(contains(self.shas[0], self.shas[-1]))
        self.assertFalse(contains(self.shas[-1], self.shas[0]))
        self.assertFalse(contains(self.shas[0], "f" * 40), "an unknown head never contains it")
        got = action_dispatch.poll_ci(work, work.items(), lambda: runs, now=100 + 21 * 60,
                                      contains=contains)
        self.assertEqual(got, 1)
        ci = work.load_item("w000000000f1")["workflow"]["ci"]
        self.assertEqual((ci["status"], ci["run_id"], ci["head_sha"]),
                         ("confirmed", 10, self.shas[-1]), "the earliest green run that contains it")
        self.assertTrue(self.shipped("w000000000f1")["ci_confirmed"])
        revision = work.load_item("w000000000f1")["_revision"]
        self.assertEqual(action_dispatch.poll_ci(work, work.items(), lambda: runs, now=10 ** 6,
                                                 contains=contains), 0)
        self.assertEqual(work.load_item("w000000000f1")["_revision"], revision, "confirmed once")

    def test_a_failed_later_run_confirms_nothing(self):
        self.card("w000000000f2", landed={"sha": self.shas[0]})
        runs = [self.run_row(12, self.shas[-1], conclusion="failure")]
        action_dispatch.poll_ci(work, work.items(), lambda: runs, now=100,
                                contains=action_dispatch.repo_contains(str(self.repo)))
        self.assertFalse(self.shipped("w000000000f2")["ci_confirmed"])

    # -- a session close -----------------------------------------------------

    def test_a_close_records_its_run_where_the_page_reads_ci(self):
        self.card("w000000000f3", state="waiting_session", closed="")
        closing.close("w000000000f3", sha=self.shas[0], ci_run="300", by="Test session",
                      result="The change is on main with its tests.",
                      main_root=str(self.repo), run=self.gh)
        ci = work.load_item("w000000000f3")["workflow"]["ci"]
        self.assertEqual((ci["run_id"], ci["commit_sha"], ci["head_sha"]),
                         (300, self.shas[0], self.shas[-1]))
        self.assertTrue(self.shipped("w000000000f3")["ci_confirmed"])

    # -- the one-time command ------------------------------------------------

    def manifest(self, cards, no_code=()):
        return {"by": "Test session", "cards": cards, "no_code": list(no_code)}

    def confirm(self, manifest, apply=False):
        return confirm_landed_commits.confirm(manifest, apply=apply, main_root=str(self.repo),
                                              run=self.gh, fetch=False)

    def test_the_backfill_previews_then_records_each_commit_once(self):
        self.card("w000000000g1", landed={"at": "2026-09-21T14:39", "by": "chief-of-staff",
                                          "note": "done"})
        self.card("w000000000g2", landed=None)
        self.card("w000000000g3", tier=0, completion={"kind": "reading", "sha": ""},
                  landed={"sha": ""})
        manifest = self.manifest(
            [{"id": "w000000000g1", "sha": self.shas[0][:9], "ci_run": "300", "reason": "its commit"},
             {"id": "w000000000g2", "sha": self.shas[1], "ci_run": "300", "reason": "its commit"}],
            [{"id": "w000000000g3", "reason": "a reading"}])
        before = {p.name: p.read_text() for p in (self.data / "work").iterdir()}
        preview = self.confirm(manifest)
        self.assertTrue(preview["applicable"], preview["errors"])
        self.assertFalse(preview["applied"])
        self.assertEqual([r["id"] for r in preview["readings"]], ["w000000000g3"])
        self.assertEqual(before, {p.name: p.read_text() for p in (self.data / "work").iterdir()},
                         "a preview writes nothing")
        self.assertTrue(self.confirm(manifest, apply=True)["applied"])
        first = work.load_item("w000000000g1")
        self.assertEqual(first["landed"]["sha"], self.shas[0])
        self.assertEqual(first["landed"]["note"], "done", "the rest of the landed record stays")
        self.assertIn("no checker or Daniel approval", first["commit_backfill"]["limitations"])
        self.assertEqual(work.load_item("w000000000g2")["landed"]["at"], "2026-09-21T14:39")
        for cid in ("w000000000g1", "w000000000g2"):
            self.assertTrue(self.shipped(cid)["ci_confirmed"], cid)
        self.assertEqual(work.load_item("w000000000g3"), json.loads(
            before["w000000000g3.json"]) | {"_revision": work.load_item("w000000000g3")["_revision"]},
            "a reading is reported, never written")
        self.assertTrue(self.shipped("w000000000g3")["no_code"])
        again = self.confirm(manifest, apply=True)
        self.assertTrue(again["applicable"])
        self.assertTrue(all(row["already_applied"] for row in again["cards"]))

    def test_the_backfill_refuses_what_it_cannot_verify(self):
        self.card("w000000000h1", landed={"sha": self.shas[1]})
        self.card("w000000000h2", state="waiting_session")
        self.card("w000000000h3")
        self.card("w000000000h4")
        self.card("w000000000h5", tier=1)
        got = self.confirm(self.manifest([
            {"id": "w000000000h1", "sha": self.shas[0], "ci_run": "300", "reason": "r"},
            {"id": "w000000000h2", "sha": self.shas[0], "ci_run": "300", "reason": "r"},
            {"id": "w000000000h3", "sha": "deadbeef", "ci_run": "300", "reason": "r"},
            {"id": "w000000000h4", "sha": self.shas[0], "ci_run": "301", "reason": "r"},
        ], [{"id": "w000000000h5", "reason": "not a reading"}]), apply=True)
        self.assertFalse(got["applicable"])
        self.assertFalse(got["applied"])
        text = "\n".join(got["errors"])
        self.assertIn("w000000000h1: already records commit", text)
        self.assertIn("w000000000h2: is 'waiting_session', not landed", text)
        self.assertIn("w000000000h3: Commit deadbeef does not exist", text)
        self.assertIn("w000000000h4: CI run 301 concluded failure", text)
        self.assertIn("w000000000h5: listed as a reading, but HQ does not read it as one", text)
        self.assertNotIn("workflow", work.load_item("w000000000h4"), "nothing was written")

    def test_the_reviewed_table_is_checked_in_and_complete(self):
        table = json.loads((HQ / "data" / confirm_landed_commits.MANIFEST).read_text())
        ids = [e["id"] for e in table["cards"]] + [e["id"] for e in table["no_code"]]
        self.assertEqual(len(ids), 28)
        self.assertEqual(len(set(ids)), 28)
        self.assertTrue(all(e["reason"].strip() and e["ci_run"].isdigit() for e in table["cards"]))


class LanesReachThePage(unittest.TestCase):
    def test_the_work_snapshot_carries_each_cards_lanes(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        data = Path(tmp.name)
        (data / "work").mkdir()
        (data / "org.json").write_text(json.dumps({"employees": [{"id": i} for i in ORG]}))
        host = FileHost(data)
        host.drain_state = lambda: None
        host.token_window = lambda: {}
        work.bind(host, sanitize=False)
        for cid, state in (("w000000000i1", "landed"), ("w000000000i2", "waiting_session")):
            (data / "work" / f"{cid}.json").write_text(json.dumps(
                {"id": cid, "title": "A card", "owner": "tomas", "tier": 1, "state": state,
                 "created_ts": 1}))
        import drain
        with patch.object(drain, "project_work",
                          side_effect=lambda item, **kw: work.work_view(item, {}, now=0)), \
                patch.object(work, "policy", return_value={}), \
                patch.object(work, "reply_seconds", return_value=30):
            snap = work.snapshot()
        lanes = {item["id"]: item["lanes"] for item in snap["items"]}
        self.assertEqual(lanes, {"w000000000i1": ["terminal"], "w000000000i2": ["runner"]})
        # The lanes are a reading of the card, never saved back into it.
        item = next(i for i in snap["items"] if i["id"] == "w000000000i2")
        work.save_item(item)
        self.assertNotIn("lanes", json.loads((data / "work" / "w000000000i2.json").read_text()))


if __name__ == "__main__":
    unittest.main()

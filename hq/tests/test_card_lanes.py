#!/usr/bin/env python3
"""Every work card is in exactly one lane, with a known state and one owner.

On 2026-09-25 twenty for_review cards sat in no lane (the drain left them for
Daniel's verdict, his page left them for the studio's verification), fourteen
more carried 'queued' or 'done', which HQ does not know, and about sixty closed
cards were reported to him as awaiting verification. These tests pin the
guard (work.card_health, shown on the Engineering page), the refusal to save an
unknown state, the terminal-first status on his page, and the one-time command
that moves the unknown states (hq/migrate_card_states.py).
"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HQ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HQ))

import closing  # noqa: E402
import migrate_card_states  # noqa: E402
import work  # noqa: E402
from reconcile_process_completion import FileHost  # noqa: E402

ORG = ["claude", "tomas", "daniel"]
REC = {"question": "Keep it?", "answer": "Keep it", "why": "It works", "instead": "Send it back"}
PREPARED = {"recommend": REC, "follow_ups": [],
            "deliverable": {"name": "The result", "evidence": [{"label": "Open", "href": "/r"}]}}


def action(kind, availability="runnable"):
    return {"type": kind, "availability": availability}


def view(kind=None, availability="runnable", blocker=None, running=False, landed_sha=""):
    return {"availability": "running" if running else availability,
            "next_action": action(kind, "running" if running else availability) if kind else None,
            "blocker": blocker, "shipped_evidence": {"landed_sha": landed_sha}}


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), "-c", "user.name=T", "-c", "user.email=t@t",
                           "-c", "core.hooksPath=/dev/null", *args],
                          capture_output=True, text=True, check=True).stdout.strip()


class FakeGitHub:
    def __init__(self, runs):
        self.runs = runs

    def __call__(self, cmd, cwd):
        if cmd[:3] == ["gh", "run", "view"]:
            doc = self.runs.get(cmd[3])
            if doc is None:
                return subprocess.CompletedProcess(cmd, 1, "", "run not found")
            return subprocess.CompletedProcess(cmd, 0, json.dumps(doc), "")
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


class Lanes(unittest.TestCase):
    def lanes(self, item, v):
        return work.card_lanes({"owner": "tomas", **item}, v)

    def test_each_kind_of_card_has_exactly_one_lane(self):
        cases = [
            ({"state": "landed", "started": "x"}, view(blocker={"reason": "lost claim"}), ["terminal"]),
            ({"state": "waiting_session"}, view("build", running=True), ["running"]),
            ({"state": "waiting_session"}, view("build"), ["runner"]),
            ({"state": "for_review", "tier": 1}, view("reconcile", blocker={"reason": "stale"}), ["runner"]),
            ({"state": "doing", "started": ""}, view("build"), ["runner"]),
            ({"state": "prepping"}, view("prepare", "runnable"), ["runner"]),
            ({"state": "owed"}, view("reply"), ["runner"]),
            ({"state": "waiting_session"}, view("build", "blocked", {"reason": "waits for Q-9"}), ["held"]),
            ({"state": "for_review", "tier": 0, **PREPARED}, view("decide", "waiting_event"), ["daniel"]),
            ({"state": "needs_approval", "tier": 2}, view("decide", "waiting_event"), ["daniel"]),
        ]
        for item, v, want in cases:
            self.assertEqual(self.lanes(item, v), want, item)

    def test_the_twenty_stranded_cards_are_in_no_lane(self):
        # Code finished before 2026-09-21 with no commit on main: the drain
        # skips a 'decide' action, and his page will not show unlanded code.
        stranded = {"state": "for_review", "tier": 1, **PREPARED}
        self.assertEqual(self.lanes(stranded, view("decide", "waiting_event")), [])
        # A stalled question and a blocker with no stated reason are no lane either.
        self.assertEqual(self.lanes({"state": "prepping", "prep_stalled": "gave up"},
                                    view("prepare")), [])
        self.assertEqual(self.lanes({"state": "waiting_session"},
                                    view("build", "blocked", {"reason": " "})), [])

    def test_health_names_every_failure_in_plain_words(self):
        entries = [
            ({"id": "w1", "state": "landed", "owner": "gone"}, view()),
            ({"id": "w2", "state": "waiting_session", "owner": "tomas"}, view("build")),
            ({"id": "w3", "state": "done", "owner": "tomas"}, view()),
            ({"id": "w4", "state": "queued", "owner": "tomas", "tier": 2}, view("build")),
            ({"id": "w5", "state": "for_review", "owner": "tomas", "tier": 1, **PREPARED},
             view("decide", "waiting_event")),
            ({"id": "w6", "state": "waiting_session", "owner": "vp-engineering"}, view("build")),
            ({"id": "w7", "state": "waiting_session", "owner": ""}, view("build")),
            ({"id": "w8", "state": "awaiting", "owner": "tomas", "awaiting_reply": True}, view()),
        ]
        got = work.card_health(entries, ORG)
        self.assertFalse(got["ok"])
        self.assertEqual(got["checked"], 8)
        self.assertEqual(got["counts"]["terminal"], 1, "a closed card's owner may have left")
        self.assertEqual(got["counts"]["runner"], 1)
        problems = {row["id"]: row["problem"] for row in got["problems"]}
        self.assertEqual(sorted(problems), ["w3", "w4", "w5", "w6", "w7", "w8"])
        self.assertIn("'done' is not one HQ knows", problems["w3"])
        self.assertIn("'queued' is not one HQ knows", problems["w4"])
        self.assertIn("in no lane", problems["w5"])
        self.assertIn("not anyone in the org chart", problems["w6"])
        self.assertIn("no single owner", problems["w7"])
        clean = work.card_health(entries[:2], ORG)
        self.assertTrue(clean["ok"])
        self.assertEqual(clean["problems"], [])

    def test_a_card_in_two_lanes_is_reported(self):
        # A reply owed on a prepared card: HQ's worker is answering it and it
        # would also be offered to him — the guard must say so, not pick one.
        item = {"id": "w9", "state": "for_review", "owner": "tomas", "tier": 0, **PREPARED}
        original = work.work_reviewable
        work.work_reviewable = lambda *_: True
        try:
            got = work.card_health([({**item, "awaiting_reply": True}, view("decide"))], ORG)
        finally:
            work.work_reviewable = original
        self.assertIn("two lanes at once", got["problems"][0]["problem"])


class StoreGuards(unittest.TestCase):
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
        self.sha = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "push", "-q", "origin", "main")
        self.gh = FakeGitHub({"200": {"workflowName": "tests", "status": "completed",
                                      "conclusion": "success", "headSha": self.sha, "url": "u"}})
        self.data = base / "data"
        (self.data / "work").mkdir(parents=True)
        (self.data / "rulings").mkdir()
        (self.data / "org.json").write_text(json.dumps({"employees": [{"id": i} for i in ORG]}))
        work.bind(FileHost(self.data), sanitize=False)

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, cid, state, **extra):
        doc = {"id": cid, "title": "A card", "owner": "tomas", "tier": 1, "state": state,
               "created_ts": 1, **extra}
        (self.data / "work" / f"{cid}.json").write_text(json.dumps(doc))
        return doc

    def test_save_refuses_a_state_hq_does_not_know(self):
        with self.assertRaises(work.UnknownState):
            work.save_item({"id": "w000000000a1", "state": "queued"})
        with self.assertRaises(work.UnknownState):
            work.save_item({"id": "w000000000a2"})
        self.card("w000000000a3", "waiting_session")
        item = work.load_item("w000000000a3")
        item["state"] = "done"
        with self.assertRaises(work.UnknownState):
            work.save_item(item)
        self.assertEqual(work.load_item("w000000000a3")["state"], "waiting_session")
        # A legacy record may still be saved without changing its state, so an
        # unrelated write cannot fail before the migration has run.
        self.card("w000000000a4", "done")
        legacy = work.load_item("w000000000a4")
        legacy["note"] = "touched"
        self.assertEqual(work.save_item(legacy)["_revision"], 1)

    def test_a_done_card_can_be_closed_with_evidence(self):
        self.card("w000000000b1", "done")
        item = closing.close("w000000000b1", sha=self.sha, ci_run="200", by="Test session",
                             result="The thing is on main with its tests.",
                             main_root=str(self.repo), run=self.gh)
        self.assertEqual(item["state"], "landed")
        with self.assertRaises(closing.Refused):
            closing.close("w000000000b1", sha=self.sha, ci_run="200", by="Test session",
                          result="The thing is on main with its tests.",
                          main_root=str(self.repo), run=self.gh)

    def manifest(self, cards):
        return {"by": "Test session", "ci_run": "200", "cards": cards}

    def migrate(self, manifest, apply=False):
        return migrate_card_states.migrate(manifest, apply=apply, main_root=str(self.repo),
                                           run=self.gh)

    def test_the_migration_previews_then_moves_each_card_once(self):
        self.card("w000000000c1", "done")
        self.card("w000000000c2", "done")
        self.card("w000000000c3", "queued", tier=2)
        self.card("w000000000c4", "queued", tier=2)
        manifest = self.manifest([
            {"id": "w000000000c1", "expected_state": "done", "to": "landed", "sha": self.sha[:9],
             "result": "The measurement is on main as a report.", "reason": "on main"},
            {"id": "w000000000c2", "expected_state": "done", "to": "dropped",
             "reason": "overtaken", "superseded_by": "w000000000c1"},
            {"id": "w000000000c3", "expected_state": "queued", "to": "prepping",
             "reason": "ask-first work nobody asked him about"},
            {"id": "w000000000c4", "expected_state": "queued", "to": "dropped", "reason": "moot"},
        ])
        before = {p.name: p.read_text() for p in (self.data / "work").iterdir()}
        preview = self.migrate(manifest)
        self.assertTrue(preview["applicable"], preview["errors"])
        self.assertFalse(preview["applied"])
        self.assertEqual(before, {p.name: p.read_text() for p in (self.data / "work").iterdir()},
                         "a preview writes nothing")
        done = self.migrate(manifest, apply=True)
        self.assertTrue(done["applied"])
        states = {cid: work.load_item(cid)["state"] for cid in
                  ("w000000000c1", "w000000000c2", "w000000000c3", "w000000000c4")}
        self.assertEqual(states, {"w000000000c1": "landed", "w000000000c2": "dropped",
                                  "w000000000c3": "prepping", "w000000000c4": "dropped"})
        landed = work.load_item("w000000000c1")
        self.assertEqual(landed["completion"]["kind"], "session_close")
        self.assertIn("no checker or Daniel approval", landed["completion"]["evidence"]["limitations"])
        self.assertEqual(landed["state_migration"]["from"], "done")
        self.assertEqual(work.load_item("w000000000c2")["superseded_by"], "w000000000c1")
        again = self.migrate(manifest, apply=True)
        self.assertTrue(again["applicable"])
        self.assertTrue(all(row["already_applied"] for row in again["cards"]))

    def test_a_stranded_review_card_goes_back_to_its_owners_queue(self):
        self.card("w000000000e1", "for_review", tier="1", result="The section, written.",
                  check={"verdict": "concerns"}, _revision=3)
        entry = {"id": "w000000000e1", "expected_state": "for_review", "expected_revision": 3,
                 "to": "waiting_session", "reason": "its patch no longer applies",
                 "repair_brief": "Write the section again against today's file."}
        self.assertTrue(self.migrate(self.manifest([entry]), apply=True)["applied"])
        item = work.load_item("w000000000e1")
        self.assertEqual(item["state"], "waiting_session")
        self.assertEqual(item["repair_brief"], entry["repair_brief"])
        self.assertTrue(item["revising"])
        self.assertEqual(item["prior_results"][-1]["result"], "The section, written.")
        self.assertEqual(item["prior_checks"][-1]["verdict"], "concerns")
        self.card("w000000000e2", "for_review", tier=1, _revision=4)
        stale = dict(entry, id="w000000000e2", expected_revision=2)
        dropped = dict(entry, id="w000000000e2", expected_revision=4, to="dropped")
        text = "\n".join(self.migrate(self.manifest([stale]))["errors"]
                         + self.migrate(self.manifest([dropped]))["errors"])
        self.assertIn("changed since it was reviewed", text)
        self.assertIn("may only go back to its owner's queue", text)

    def test_the_migration_refuses_what_was_not_reviewed(self):
        self.card("w000000000d1", "done")
        self.card("w000000000d2", "queued", tier=2)
        self.card("w000000000d3", "queued")
        bad = self.manifest([
            {"id": "w000000000d1", "expected_state": "done", "to": "landed", "sha": "deadbeef",
             "result": "The measurement is on main as a report.", "reason": "on main"},
            {"id": "w000000000d2", "expected_state": "queued", "to": "waiting_session",
             "reason": "run it"},
        ])
        got = self.migrate(bad, apply=True)
        self.assertFalse(got["applicable"])
        self.assertFalse(got["applied"])
        text = "\n".join(got["errors"])
        self.assertIn("w000000000d1: Commit deadbeef does not exist", text)
        self.assertIn("w000000000d2: an ask-first card cannot become runnable", text)
        self.assertIn("w000000000d3: in unknown state 'queued' but not in the manifest", text)
        self.assertEqual(work.load_item("w000000000d1")["state"], "done", "nothing was written")
        self.card("w000000000d4", "waiting_session")
        moved = self.manifest([{"id": "w000000000d4", "expected_state": "done",
                                "to": "dropped", "reason": "x"}])
        self.assertIn("is now 'waiting_session'", "\n".join(self.migrate(moved)["errors"]))


class WaitingOnYou(unittest.TestCase):
    def test_a_closed_card_is_closed_whatever_its_projection_says(self):
        import server
        lost_claim = {"blocker": {"type": "recovery", "reason": "The previous session no longer has a live claim."},
                      "shipped_evidence": {}}
        fixtures = [{"id": "wl", "state": "landed", "started": "x", "workflow_view": lost_claim},
                    {"id": "wa", "state": "accepted", "started": "x", "workflow_view": lost_claim},
                    {"id": "wd", "state": "dropped", "started": "x", "workflow_view": lost_claim}]
        old = server.api_queue, server.work.items
        server.api_queue = lambda **kwargs: {"curated": [], "decided": [], "rulings": {}}
        server.work.items = lambda **kwargs: fixtures
        try:
            got = {row["source_id"]: row["status"] for row in server.waiting_on_you()["items"]}
        finally:
            server.api_queue, server.work.items = old
        self.assertEqual(got, {"wl": "completed", "wa": "closed", "wd": "closed"})

    def test_nothing_holds_a_closed_card_in_the_projection(self):
        for state in ("landed", "accepted", "dropped"):
            got = work.work_view({"id": "wx", "state": state, "started": "2026-09-01T00:00",
                                  "owner": "tomas"}, {"head": "abc"}, now=1)
            self.assertIsNone(got["blocker"], state)
            self.assertEqual(got["availability"], "terminal")
            self.assertEqual(got["candidate_status"], "none")
        open_card = work.work_view({"id": "wy", "state": "waiting_session", "owner": "tomas",
                                    "started": "2026-09-01T00:00"}, {"head": "abc"}, now=1)
        self.assertEqual(open_card["blocker"]["type"], "recovery",
                         "an open card whose session died still needs recovery")

    def test_the_engineering_page_shows_the_guard(self):
        import server
        self.assertTrue(callable(server.work_health))
        source = (HQ / "server.py").read_text()
        self.assertIn('"/api/work-health"', source)
        pillars = (HQ / "static" / "pillars.js").read_text()
        engineering = pillars[pillars.index("async function instEngineering"):]
        self.assertIn('api("/api/work-health")', engineering[:engineering.index("async function mountVerify")])
        for page in ("app.js", "queue.js", "work.js"):
            self.assertNotIn("/api/work-health", (HQ / "static" / page).read_text(),
                             "the guard's failures are never counted on Daniel's pages")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Offline canary for one rejected, repaired, checked, and landed HQ item.

The model/provider boundary and the two Godot commands are deterministic
fixtures. Everything between them is production code: work filing, prompts,
private Git worktrees, worker/checker session records, repair requeue, patch
application, candidate identity, landing transaction, card persistence, and
accepted-memory persistence.

    python3 hq/tests/test_process_canary.py
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain
import execution
import integration
import server
import work


ORG = {"company": "Canary Studio", "employees": [
    {"id": "daniel", "name": "Daniel", "title": "CEO", "level": "L10",
     "team": "Executive", "responsibilities": [], "persona": ""},
    {"id": "claude", "name": "Adam", "title": "Chief of Staff", "level": "L8",
     "team": "Executive", "responsibilities": ["check work"], "persona": "Check evidence."},
    {"id": "sam", "name": "Sam", "title": "Engineer", "level": "L5",
     "team": "Engineering", "responsibilities": ["build fixtures"],
     "persona": "Make the smallest verified change.", "model": "sonnet"},
]}

FINDING = "The artifact omits the required stable marker."
OWNER_LESSON = "Carry reviewer findings into the persisted fixture before declaring it complete."
CHECKER_LESSON = "Compare the landed blob with the reviewed candidate, not only the worker summary."


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True).stdout.strip()


def answer(note):
    return ("The canary artifact contains the stable marker.\n"
            f"<remember>{note}</remember>\n"
            + work.FOLLOW_MARK + "\n"
            + json.dumps({"outcome": {"status": "complete", "reason": ""}, "items": []}))


class ProcessCanary(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hq-process-canary-")
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.data = self.root / "data"
        self.repo.mkdir()
        self.data.mkdir()
        run(["git", "init", "-q", "-b", "main"], self.repo)
        run(["git", "config", "user.name", "HQ Canary"], self.repo)
        run(["git", "config", "user.email", "canary@example.invalid"], self.repo)
        (self.repo / "README.md").write_text("offline process canary\n", encoding="utf-8")
        run(["git", "add", "README.md"], self.repo)
        run(["git", "commit", "-qm", "Canary base"], self.repo)
        self.base = run(["git", "rev-parse", "HEAD"], self.repo)
        self.assertEqual(integration.handoff_main(str(self.repo), "codex/canary-user",
                                                  confirmed_idle=True), (True, ""))

        (self.data / "org.json").write_text(json.dumps(ORG), encoding="utf-8")
        self.policy = self.root / "execution_policy.json"
        self.policy.write_text(json.dumps({
            "version": 1, "mode": "codex", "default_model": "sonnet",
            "background_paused": False, "trial_item": "", "mappings": execution.MODELS,
        }), encoding="utf-8")

        names = ["DATA", "REPO", "WORKERS_DIR"]
        self.server_old = {name: getattr(server, name) for name in names}
        server.DATA = str(self.data)
        server.REPO = str(self.repo)
        server.WORKERS_DIR = str(self.data / "runs" / "workers")

        names = ["REPO", "WORKTREES", "PATCHES", "WORKERS", "DRAIN_STATE", "RUN_ID"]
        self.drain_old = {name: getattr(drain, name) for name in names}
        drain.REPO = str(self.repo)
        drain.WORKTREES = str(self.root / "worktrees")
        drain.PATCHES = str(self.data / "patches")
        drain.WORKERS = server.WORKERS_DIR
        drain.DRAIN_STATE = str(self.data / "runs" / "drain.json")
        drain._set_run("")

        self.policy_old = execution.POLICY_PATH
        execution.POLICY_PATH = self.policy
        self.work_old = {name: getattr(work, name, None)
                         for name in ("HOST", "WORK", "CAPTURES", "POLICY_PATH")}
        work.bind(server)

    def tearDown(self):
        drain._set_run("")
        execution.POLICY_PATH = self.policy_old
        for name, value in self.drain_old.items():
            setattr(drain, name, value)
        for name, value in self.server_old.items():
            setattr(server, name, value)
        for name, value in self.work_old.items():
            setattr(work, name, value)
        self.temp.cleanup()

    def test_reviewer_revision_lands_the_exact_candidate_and_only_then_memory(self):
        filed = work.api_post("/api/work/new", {
            "title": "Write the process canary artifact", "owner": "sam", "tier": 1,
            "ask": "Write artifact.txt with the exact line stable=yes.",
            "first_action": "Create the artifact and verify its exact contents.",
        })
        item_id = filed["id"]
        memory_path = self.data / "staff" / "sam" / "memory.md"
        worker_prompts = []
        session_calls = []
        suite_calls = []
        landing_suite_saw_no_memory = []
        owner_n = 0
        checker_n = 0

        def fake_session(prompt, system, tools, model, cwd, timeout, turns, **kwargs):
            nonlocal owner_n, checker_n
            phase = kwargs["phase"]
            route = execution.resolve_model(model)
            session_calls.append({"phase": phase, "item": kwargs["item"], "cwd": cwd})
            if phase == "build-worker":
                owner_n += 1
                worker_prompts.append(prompt)
                content = "draft=yes\n" if owner_n == 1 else "stable=yes\n"
                Path(cwd, "artifact.txt").write_text(content, encoding="utf-8")
                text = answer("Discarded first-attempt lesson." if owner_n == 1 else OWNER_LESSON)
            elif phase == "checker":
                checker_n += 1
                if checker_n == 1:
                    text = json.dumps({"verdict": "fail", "complete": True,
                        "summary": "The artifact is missing its stable marker.",
                        "findings": [{"what": FINDING, "where": "artifact.txt:1",
                                      "fix": "Replace draft=yes with stable=yes."}],
                        "lesson_for_owner": {"text": "Discarded checker lesson."},
                        "escalates": None, "escalation_reason": None})
                else:
                    text = json.dumps({"verdict": "pass", "complete": True,
                        "summary": "The reviewed artifact is exact and ready to land.",
                        "findings": [], "lesson_for_owner": {"text": CHECKER_LESSON},
                        "escalates": None, "escalation_reason": None})
            else:
                raise AssertionError(f"unexpected phase {phase}")
            if kwargs.get("on_start"):
                kwargs["on_start"](os.getpid())
            if kwargs.get("on_event"):
                kwargs["on_event"]({"type": "assistant", "message": {
                    "id": f"{phase}-{len(session_calls)}", "content": [{"type": "text", "text": text}]}})
                kwargs["on_event"]({"type": "result", "result": text,
                                     "provider": route["provider"], "usage": {}})
            return {**route, "text": text, "usage": None, "error": "", "held": False,
                    "limited": False, "exit_code": 0, "stop_reason": None, "subtype": "success"}

        green = {"unit": {"ok": True, "tail": "canary unit boundary"},
                 "integration": {"ok": True, "tail": "canary integration boundary"}}

        def fake_suites(cwd=None):
            suite_cwd = str(Path(cwd or drain.REPO).resolve())
            suite_calls.append(suite_cwd)
            if Path(suite_cwd).name.startswith("integration-"):
                # The candidate is applied and facing the landing checks, but
                # it has not earned a commit or a durable lesson yet.
                self.assertFalse(memory_path.exists())
                self.assertEqual(run(["git", "rev-parse", "main"], self.repo), self.base)
                landing_suite_saw_no_memory.append(True)
            return json.loads(json.dumps(green))

        with patch.object(execution, "run_session", side_effect=fake_session), \
             patch.object(drain, "run_suites", side_effect=fake_suites):
            drain._set_run("canary-first")
            first_records, first_done = drain.run_verified_batch(
                [filed], ORG, "canary-first", lambda _message: None)

            first = work.load_item(item_id)  # persisted boundary: process reload reads the file
            self.assertEqual(first_done[0]["state"], "waiting_session")
            self.assertEqual(first["state"], "waiting_session")
            self.assertEqual(first["automatic_repairs"], 1)
            self.assertEqual(first["prior_checks"][-1]["findings"][0]["what"], FINDING)
            self.assertFalse(first_records[item_id]["applied"])
            self.assertFalse(memory_path.exists())
            self.assertEqual(run(["git", "rev-parse", "main"], self.repo), self.base)

            # Rebind exactly as an HQ restart does, then select the persisted card.
            work.bind(server)
            second_input = work.load_item(item_id)
            drain._set_run("canary-second")
            second_records, second_done = drain.run_verified_batch(
                [second_input], ORG, "canary-second", lambda _message: None)

        rec = second_records[item_id]
        final = work.load_item(item_id)  # persisted boundary after landing
        head = run(["git", "rev-parse", "main"], self.repo)
        tree = run(["git", "rev-parse", "main^{tree}"], self.repo)

        self.assertEqual(owner_n, 2)
        self.assertEqual(checker_n, 2)
        self.assertIn(FINDING, worker_prompts[1])
        self.assertIn("artifact.txt:1", worker_prompts[1])
        self.assertIn("Replace draft=yes with stable=yes.", worker_prompts[1])
        self.assertEqual(run(["git", "show", "main:artifact.txt"], self.repo), "stable=yes")
        self.assertFalse((self.repo / "artifact.txt").exists())
        self.assertEqual(rec["candidate"]["tree"], tree)
        self.assertTrue(rec["candidate_unchanged"])
        self.assertEqual(rec["candidate_suites"], green)
        self.assertEqual(rec["test_evidence"], work.evidence_id([rec["patch"], green]))
        transaction = {"parent": self.base, "files": rec["files"], "candidate": rec["candidate"]}
        self.assertTrue(drain.committed_candidate(str(self.repo), head, transaction))
        self.assertEqual(second_done[0]["completion"]["sha"], head)
        self.assertEqual(final["state"], "landed")
        self.assertEqual(final["completion"]["sha"], head)
        self.assertEqual(len(final["workflow"]["integrations"]), 1)
        self.assertEqual(final["workflow"]["integrations"][0]["commit"], head)
        self.assertEqual(final["workflow"]["integrations"][0]["state"], "landed_local")
        self.assertEqual(final["workflow"]["integrations"][0]["origin"]["push"], "not_attempted")
        self.assertTrue(final["owner_memory"]["committed"])
        memory = memory_path.read_text(encoding="utf-8")
        self.assertIn(OWNER_LESSON, memory)
        self.assertIn(CHECKER_LESSON, memory)
        self.assertNotIn("Discarded first-attempt lesson", memory)
        self.assertNotIn("Discarded checker lesson", memory)
        self.assertEqual(len(suite_calls), 3)  # rejected candidate, repaired candidate, landed tree
        self.assertEqual(landing_suite_saw_no_memory, [True])

        sessions = server.worker_sessions()
        matching = [row for row in sessions if row["item"] == item_id]
        self.assertEqual(len(matching), 4)
        self.assertEqual({row["run"] for row in matching}, {"canary-first", "canary-second"})
        self.assertEqual({row["phase"] for row in matching}, {"worker", "checker"})
        self.assertEqual({row["item"] for row in matching}, {item_id})  # Bullpen grouping key
        self.assertEqual([call["phase"] for call in session_calls],
                         ["build-worker", "checker", "build-worker", "checker"])


if __name__ == "__main__":
    unittest.main()

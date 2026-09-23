#!/usr/bin/env python3
"""A relocated HQ must use one explicit data store and a distinct main tree."""

import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import tempfile
import unittest
from urllib.request import urlopen


HQ = Path(__file__).resolve().parents[1]


def git(repo, *args):
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True)


class ActivationRoots(unittest.TestCase):
    @staticmethod
    def stop(proc):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        if proc.stdout:
            proc.stdout.close()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hq-activation-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.main = root / "authoritative-main"
        self.user = root / "user-workspace"
        self.data = root / "live-data-copy"
        for repo in (self.main, self.user):
            repo.mkdir()
            git(repo, "init", "-q", "-b", "main")
            git(repo, "config", "user.name", "HQ fixture")
            git(repo, "config", "user.email", "hq@example.invalid")
            (repo / "identity.txt").write_text(repo.name + "\n")
            git(repo, "add", "identity.txt")
            git(repo, "commit", "-qm", "Fixture base")
        self.data.mkdir()
        (self.data / "org.json").write_text(json.dumps({"employees": [
            {"id": "daniel", "name": "Fixture Daniel", "title": "CEO"},
            {"id": "claude", "name": "Fixture Adam", "title": "Chief of Staff"},
        ]}))
        (self.data / "execution_policy.json").write_text(json.dumps({
            "version": 1, "mode": "codex", "default_model": "sonnet",
            "background_paused": True, "trial_item": "", "mappings": {
                "fable": "gpt-6-astra", "opus": "gpt-5.6-sol",
                "sonnet": "gpt-5.6-terra", "haiku": "gpt-5.6-luna"},
        }))
        (self.data / "work").mkdir()
        self.card = self.data / "work" / "wfixture001.json"
        self.card.write_text(json.dumps({
            "id": "wfixture001", "title": "Prove the copied data root",
            "state": "waiting_session", "owner": "claude", "tier": 1,
            "ask": "Read the fixture", "first_action": "Check the fixture",
            "created_ts": 1, "created": "2026-09-22T00:00:00", "_revision": 7,
        }))
        (self.data / "patches").mkdir()
        (self.data / "runs" / "workers").mkdir(parents=True)
        (self.data / "runs" / "transactions").mkdir()

    def environment(self):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("HQ_")}
        env.update({"HQ_DATA_ROOT": str(self.data),
                    "HQ_USER_WORKSPACE_ROOT": str(self.user),
                    "HQ_MAIN_ROOT": str(self.main),
                    "HQ_REQUIRE_EXPLICIT_ROOTS": "1", "HQ_CANARY_MODE": "1",
                    "HQ_PORT": "0"})
        return env

    def test_incomplete_explicit_configuration_fails_closed(self):
        env = self.environment()
        del env["HQ_DATA_ROOT"]
        result = subprocess.run([sys.executable, str(HQ / "server.py")],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HQ_DATA_ROOT", result.stderr)
        self.assertFalse((self.data / "work_policy.json").exists())

    def test_all_modules_use_the_same_overridden_paths(self):
        script = ("import json,sys; sys.path.insert(0,sys.argv[1]); "
                  "import drain,execution,server; "
                  "print(json.dumps({'repo':drain.REPO,'patches':drain.PATCHES,"
                  "'workers':drain.WORKERS,'transactions':drain.TRANSACTIONS,"
                  "'policy':str(execution.POLICY_PATH),'main_head':"
                  "server.run_cmd(['git','rev-parse','HEAD'])}))")
        result = subprocess.run([sys.executable, "-c", script, str(HQ)],
                                env=self.environment(), capture_output=True,
                                text=True, check=True, timeout=10)
        paths = json.loads(result.stdout)
        self.assertEqual(paths["repo"], str(self.main))
        self.assertEqual(paths["patches"], str(self.data / "patches"))
        self.assertEqual(paths["workers"], str(self.data / "runs" / "workers"))
        self.assertEqual(paths["transactions"], str(self.data / "runs" / "transactions"))
        self.assertEqual(paths["policy"], str(self.data / "execution_policy.json"))
        self.assertEqual(paths["main_head"], subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=self.main, check=True,
            capture_output=True, text=True).stdout.strip())

    def test_disposable_http_startup_uses_one_data_root_and_clean_main(self):
        before = self.card.read_bytes()
        proc = subprocess.Popen([sys.executable, "-u", str(HQ / "server.py")],
                                env=self.environment(), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.addCleanup(self.stop, proc)
        port = None
        output = []
        for _ in range(30):
            ready, _, _ = select.select([proc.stdout], [], [], 1)
            if not ready:
                continue
            line = proc.stdout.readline()
            output.append(line)
            match = re.search(r"http://localhost:(\d+)", line)
            if match:
                port = int(match.group(1))
                break
            if proc.poll() is not None:
                break
        self.assertIsNotNone(port, "HQ canary did not start: " + "".join(output))

        def get(path):
            with urlopen(f"http://127.0.0.1:{port}{path}", timeout=10) as response:
                return json.load(response)

        health = get("/api/health")
        self.assertEqual(health["roots"], {
            "code": str(HQ), "data": str(self.data),
            "user_workspace": str(self.user), "main": str(self.main)})
        self.assertEqual(get("/api/org")["employees"][0]["name"], "Fixture Daniel")
        cards = get("/api/work")["items"]
        self.assertEqual([card["id"] for card in cards], ["wfixture001"])
        queue = get("/api/execution/queue")
        self.assertEqual([row["work_id"] for row in queue["eligible"]], ["wfixture001"])
        self.assertTrue(get("/api/execution")["paused"])
        self.assertEqual(self.card.read_bytes(), before)
        self.assertFalse((self.main / "hq" / "data").exists())


if __name__ == "__main__":
    unittest.main()

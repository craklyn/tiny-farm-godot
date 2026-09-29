#!/usr/bin/env python3
"""Art the work queue generates for a card (S-37), with the art service stubbed out.

A worker writes requests into its worktree; the drain prices them, holds the card
for the chief of staff when a round would pass $2 for the card or $10 for the day,
otherwise generates, archives the raws, records the spend and gives the worker one
more session. Nothing here may reach the network, and the key must never appear in
anything a worker or a card can read.
"""
import base64
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import art_requests  # noqa: E402
import drain  # noqa: E402
import execution  # noqa: E402
import work  # noqa: E402
from test_drain import ORG, fake_host  # noqa: E402

KEY = "FAKE_ART_SERVICE_VALUE_FOR_TESTS"
PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDRfake").decode()
DAY = "2026-09-29"


class FakeRD:
    """Stands in for tools/rd_client.py: prices every image at `price` dollars."""

    def __init__(self, price=0.03, key=KEY):
        self.price, self.key = price, key
        self.priced, self.generated = [], []

    def find_key(self, *paths):
        self.key_paths = paths
        return self.key

    def cost(self, key, params):
        assert key == KEY
        self.priced.append(params)
        return {"balance_cost": self.price * params.get("num_images", 1)}

    def generate(self, key, name, params, out_dir):
        assert key == KEY
        self.generated.append((name, params))
        os.makedirs(out_dir, exist_ok=True)
        meta = {"balance_cost": self.price * params.get("num_images", 1),
                "remaining_balance": 2.5, "model": params["prompt_style"]}
        with open(os.path.join(out_dir, f"{name}_meta.json"), "w") as f:
            json.dump(meta, f)
        for i in range(params.get("num_images", 1)):
            with open(os.path.join(out_dir, f"{name}_{i}.png"), "wb") as f:
                f.write(base64.b64decode(PNG))
        return meta


def no_network(*_args, **_kwargs):
    raise AssertionError("a test tried to open a network connection")


class ArtRequests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hq-art-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.data = root / "data"
        self.data.mkdir()
        work.bind(fake_host(str(self.data)), sanitize=False)
        self.tree = root / "tree"
        (self.tree / "hq" / "data").mkdir(parents=True)
        (self.tree / "hq" / "data" / "spend.json").write_text(
            json.dumps({"note": "kept", "currency": "USD", "entries": []}))
        for args in (["init", "-q", "-b", "main"], ["config", "user.name", "T"],
                     ["config", "user.email", "t@example.invalid"], ["add", "-A"],
                     ["commit", "-qm", "base"]):
            subprocess.run(["git", *args], cwd=self.tree, check=True, capture_output=True)
        for p in (patch.object(art_requests, "STORE", str(root / "store")),
                  patch.object(socket.socket, "connect", no_network),
                  patch.object(art_requests, "today", return_value=DAY)):
            p.start()
            self.addCleanup(p.stop)

    def card(self, **over):
        item = {"id": "wart00000001", "title": "Tomato sprite", "owner": "sam", "tier": 1,
                "state": "waiting_session", "ask": "Draw the tomato", "first_action": "Ask for art",
                "created": "2026-09-29T08:00", "created_ts": 1.0, "started": "", "attempts": 0}
        item.update(over)
        try:
            item["_revision"] = work.load_item(item["id"]).get("_revision", 0)
        except (OSError, KeyError, ValueError):
            pass
        return work.save_item(item)

    def ask(self, name, **fields):
        body = {"what": "tomato", "prompt": "a ripe tomato plant", "width": 64, "height": 64,
                "num_images": 2, "palette": ["#a4c263", "#c15a3a"], **fields}
        folder = self.tree / "art_requests"
        folder.mkdir(exist_ok=True)
        (folder / name).write_text(body if isinstance(body, str) else json.dumps(body))

    def seed_ledger(self, card, dollars, day=DAY):
        art_requests._record({"work_item": card, "date": day, "dollars": dollars,
                              "recorded_by": "drain"})

    def everything_readable(self, *extra):
        """What a worker, a card or a reviewer could ever read."""
        texts = [p.read_text(errors="ignore") for p in self.tree.rglob("*") if p.is_file()
                 and ".git" not in p.parts]
        texts += [p.read_text(errors="ignore") for p in Path(art_requests.STORE).rglob("*")
                  if p.is_file()]
        texts += [p.read_text(errors="ignore") for p in self.data.rglob("*") if p.is_file()]
        return "\n".join(texts + [json.dumps(x, default=str) for x in extra])

    # -- a round that runs -------------------------------------------------

    def test_request_is_generated_archived_recorded_and_removed(self):
        item = self.card()
        self.ask("tomato.json")
        rd = FakeRD()
        art = art_requests.run_round(item, str(self.tree), "/main/checkout", rd=rd)
        self.assertEqual(rd.key_paths[0], "/main/checkout/.env",
                         "the key is read from the main checkout's .env first")
        self.assertFalse(any(p.startswith(str(self.tree)) for p in rd.key_paths),
                         "never from the worktree")
        self.assertEqual(len(rd.priced), 1, "priced before generating")
        self.assertEqual(rd.priced[0]["palette_hex"], ["#a4c263", "#c15a3a"])
        raw = self.tree / "assets" / "raw" / f"{DAY}-wart00000001-tomato"
        self.assertEqual(sorted(p.name for p in raw.iterdir()),
                         ["tomato_0.png", "tomato_1.png", "tomato_meta.json"])
        self.assertTrue((Path(art_requests.STORE) / raw.name / "tomato_meta.json").is_file(),
                        "a durable copy survives the worktree")
        self.assertFalse((self.tree / "art_requests").exists(), "requests never land")
        [entry] = art_requests.ledger()
        self.assertEqual((entry["work_item"], entry["recorded_by"], entry["dollars"]),
                         ("wart00000001", "drain", 0.06))
        ledger = json.loads((self.tree / "hq/data/spend.json").read_text())
        self.assertEqual(ledger["note"], "kept")
        self.assertEqual(ledger["entries"][0]["work_item"], "wart00000001")
        self.assertEqual(ledger["entries"][0]["recorded_by"], "drain")
        self.assertEqual(ledger["entries"][0]["balance_after"], 2.5)
        self.assertIsNone(art["hold"])
        brief = art_requests.continuation_brief(art, "Waiting for the tomato art.")
        self.assertIn(f"assets/raw/{DAY}-wart00000001-tomato/", brief)
        self.assertIn("tomato_0.png, tomato_1.png", brief)
        self.assertIn("CREDITS.md", brief)
        self.assertIn("$0.06", art_requests.result_note(art))
        self.assertNotIn(KEY, self.everything_readable(art, brief))

    def test_do_item_gives_the_worker_a_continuation_naming_the_files(self):
        item = self.card()
        prompts = []

        def session(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id,
                    attempt_id="", suffix=""):
            prompts.append((phase, suffix, prompt, system))
            if phase == "drain-work" and not suffix:
                self.ask("tomato.json")
                return "I need a tomato sprite; requested it.", None, ""
            if suffix == "-art":
                self.ask("more.json", what="more")
                return "Placed the tomato.", None, ""
            return "", None, "HELD"          # stop at the checker

        rd = FakeRD()
        with patch.object(drain.execution, "launch_allowed", return_value=True), \
             patch.object(drain, "checkpoint"), patch.object(drain, "record_phase"), \
             patch.object(drain, "make_worktree", return_value=str(self.tree)), \
             patch.object(drain, "drop_worktree"), \
             patch.object(drain, "resume_held_patch", return_value=""), \
             patch.object(drain, "resume_for_revision", return_value=(False, "")), \
             patch.object(drain, "needs_godot_import", return_value=False), \
             patch.object(drain, "PATCHES", str(Path(self.tmp.name) / "patches")), \
             patch.object(drain, "WORKERS", str(Path(self.tmp.name) / "workers")), \
             patch.object(drain, "seat_prompt", return_value="seat"), \
             patch.object(art_requests, "client", return_value=rd), \
             patch.object(drain, "run_cli", side_effect=session):
            rec = drain.do_item(item, ORG, "run", lambda _m: None)
        self.assertEqual(rec["error"], "", rec)
        phases = [(p, s) for p, s, _, _ in prompts]
        self.assertEqual(phases, [("drain-work", ""), ("drain-work", "-art"), ("drain-check", "")])
        self.assertIn("art_requests/<name>.json", prompts[0][2], "the worker is told the format")
        continuation = prompts[1][2]
        self.assertIn(f"assets/raw/{DAY}-wart00000001-tomato/", continuation)
        self.assertIn("I need a tomato sprite", continuation)
        self.assertEqual(rec["result"], "Placed the tomato.")
        self.assertTrue(rec["art"]["second_round"], "a second round waits for the next run")
        self.assertEqual(len(rd.generated), 1, "one round per run")
        self.assertIn(f"assets/raw/{DAY}-wart00000001-tomato/tomato_0.png", rec["patch"])
        self.assertIn("hq/data/spend.json", rec["files"])
        self.assertFalse(any(f.startswith("art_requests/") for f in rec["files"]))
        self.assertNotIn(KEY, json.dumps(prompts) + json.dumps(rec, default=str))

    # -- the caps ----------------------------------------------------------

    def test_card_cap_refuses_and_holds_the_card_for_the_chief_of_staff(self):
        item = self.card()
        self.seed_ledger("wart00000001", 1.90)
        self.ask("tomato.json", num_images=4)            # 4 x $0.03 = $0.12 -> $2.02
        rd = FakeRD()
        art = art_requests.run_round(item, str(self.tree), "/main", rd=rd)
        self.assertEqual(rd.generated, [], "nothing is generated past the cap")
        self.assertEqual(art["hold"]["kind"], "card")
        reason = ("This card asked for $0.12 of art generation; it has spent $1.90 of its $2 "
                  "and the studio $1.90 of today's $10.")
        self.assertEqual(art["hold"]["reason"], reason)
        self.assertFalse((self.tree / "art_requests").exists())
        self.assertIn(reason, art_requests.continuation_brief(art, ""))

        # The worker's reply comes back and the result is written: the card is held.
        item = self.card(state="for_review", result="Everything but the sprite is done.",
                         repair_hold="The owner needs art.",
                         attempt_outcome={"candidate": {"base": "old", "files": ["a.gd"]}})
        art_requests.after_write_back(item, {"art": art, "attempt_id": "a1"})
        item = work.load_item("wart00000001")
        self.assertEqual(item["state"], "waiting_session")
        self.assertIn(reason, item["result"])
        view = work.work_view(item, {"head": "new"}, now=1e10)
        self.assertEqual(view["blocker"]["type"], "art_budget")
        self.assertEqual(view["blocker"]["owner"], "claude")
        self.assertEqual(view["blocker"]["reason"], reason)
        self.assertEqual(view["next_action"]["owner"], "claude")
        self.assertNotEqual(view["next_action"]["availability"], "runnable")
        self.assertEqual(work.card_lanes(item, view), ["held"])
        health = work.card_health([(item, view)], {e["id"] for e in ORG["employees"]})
        self.assertTrue(health["ok"], health["problems"])

        # Still held the same day; released once the chief of staff raises its limit.
        self.assertEqual(art_requests.settle_holds(day=DAY), [])
        self.assertEqual(art_requests.settle_holds(day="2026-09-30"), [], "a new day does not lift a card cap")
        item["art_cap_usd"] = 3.0
        work.save_item(item)
        self.assertEqual(art_requests.settle_holds(day=DAY), ["wart00000001"])
        item = work.load_item("wart00000001")
        view = work.work_view(item, {"head": "old"}, now=1e10)
        self.assertIsNone(view["blocker"])
        self.assertEqual(work.card_lanes(item, view), ["runner"])

    def test_day_cap_counts_every_card(self):
        self.seed_ledger("wother000001", 6.00)
        self.seed_ledger("wother000002", 3.95)
        self.seed_ledger("wother000003", 5.00, day="2026-09-28")   # yesterday does not count
        item = self.card()
        self.ask("tomato.json")                                     # $0.06 -> $10.01 today
        rd = FakeRD()
        art = art_requests.run_round(item, str(self.tree), "/main", rd=rd)
        self.assertEqual(rd.generated, [])
        self.assertEqual(art["hold"]["kind"], "day")
        self.assertEqual(art["hold"]["reason"],
                         "This card asked for $0.06 of art generation; it has spent $0 of its $2 "
                         "and the studio $9.95 of today's $10.")
        art_requests.after_write_back(self.card(state="for_review"), {"art": art, "attempt_id": "a1"})
        item = work.load_item("wart00000001")
        self.assertEqual(work.card_lanes(item, work.work_view(item, {}, now=1e10)), ["held"])
        self.assertEqual(art_requests.settle_holds(day=DAY), [])
        self.assertEqual(art_requests.settle_holds(day="2026-09-30"), ["wart00000001"])

    def test_a_landed_card_is_not_held(self):
        self.seed_ledger("wart00000001", 2.00)
        self.ask("tomato.json")
        art = art_requests.run_round(self.card(), str(self.tree), "/main", rd=FakeRD())
        item = self.card(state="landed", result="Shipped without the sprite.")
        art_requests.after_write_back(item, {"art": art})
        item = work.load_item("wart00000001")
        self.assertEqual(item["state"], "landed")
        self.assertIn("asked for $0.06", item["result"])
        self.assertFalse(item.get("art_hold"))

    # -- what is refused without spending ----------------------------------

    def test_malformed_requests_are_rejected_with_a_reason(self):
        self.ask("broken.json", body=None)
        (self.tree / "art_requests" / "broken.json").write_text("{not json")
        self.ask("extra.json", model="rd_fast")
        self.ask("many.json", num_images=9)
        self.ask("huge.json", width=4096)
        self.ask("escape.json", input_image="../../etc/passwd.png")
        rd = FakeRD()
        art = art_requests.run_round(self.card(), str(self.tree), "/main", rd=rd)
        reasons = {r["file"]: r["reason"] for r in art["rejected"]}
        self.assertIn("not readable JSON", reasons["broken.json"])
        self.assertIn("model", reasons["extra.json"])
        self.assertIn("num_images", reasons["many.json"])
        self.assertIn("width", reasons["huge.json"])
        self.assertIn("inside the worktree", reasons["escape.json"])
        self.assertEqual(rd.priced, [], "a malformed request costs nothing")
        self.assertFalse((self.tree / "art_requests").exists())
        self.assertIn("did not follow the request format", art_requests.result_note(art))

    def test_a_missing_key_holds_without_calling_the_service(self):
        self.ask("tomato.json")
        rd = FakeRD(key=None)
        art = art_requests.run_round(self.card(), str(self.tree), "/main", rd=rd)
        self.assertEqual(art["hold"]["kind"], "failed")
        self.assertIn("could not find the art service key", art["hold"]["reason"])
        self.assertEqual(rd.priced, [])

    def test_an_unreadable_spend_record_generates_nothing(self):
        os.makedirs(art_requests.STORE, exist_ok=True)
        Path(art_requests._ledger_path()).write_text("{broken")
        self.ask("tomato.json")
        rd = FakeRD()
        art = art_requests.run_round(self.card(), str(self.tree), "/main", rd=rd)
        self.assertEqual(rd.generated, [], "an unreadable ledger must not read as $0 spent")
        self.assertEqual(art["hold"]["kind"], "failed")

    def test_a_service_error_never_repeats_the_key(self):
        class Failing(FakeRD):
            def cost(self, key, params):
                raise RuntimeError(f"401 for token {key}")
        self.ask("tomato.json")
        art = art_requests.run_round(self.card(), str(self.tree), "/main", rd=Failing())
        self.assertEqual(art["hold"]["kind"], "failed")
        self.assertIn("[key]", art["hold"]["reason"])
        self.assertNotIn(KEY, json.dumps(art))

    def test_the_key_is_stripped_from_every_model_session(self):
        seen = {}

        def popen(*_args, **kwargs):
            seen.update(kwargs["env"])
            raise OSError("stop here")

        with patch.dict(os.environ, {"RETRODIFFUSION_API_KEY": KEY}), \
             patch.object(execution, "launch_allowed", return_value=True), \
             patch.object(execution, "check_mcp_config"), \
             patch.object(execution.subprocess, "Popen", side_effect=popen):
            execution.run_session("p", "s", "Read", "sonnet", str(self.tree), 10, 1)
        self.assertTrue(seen, "the session was launched")
        self.assertNotIn("RETRODIFFUSION_API_KEY", seen)

    def test_only_build_workers_are_told_about_art(self):
        base = {"id": "w1", "title": "T", "ask": "A", "first_action": "F", "owner": "sam"}
        self.assertIn("art_requests/", drain.task_prompt({**base, "tier": 1}, ORG))
        self.assertIn("$2 of art per card", drain.task_prompt({**base, "tier": 1}, ORG))
        self.assertNotIn("art_requests/", drain.task_prompt({**base, "tier": 0}, ORG))


if __name__ == "__main__":
    unittest.main()

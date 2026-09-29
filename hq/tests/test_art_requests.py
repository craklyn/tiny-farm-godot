#!/usr/bin/env python3
"""Art the work queue generates for a card (S-37), with the art service stubbed out.

A build worker calls the `generate_art` tool (hq/art_mcp.py) mid-session. Each
call is priced, refused with the amounts when it would pass $2 for the card or
$10 for the day, otherwise generated, archived and recorded in both ledgers, and
the paths come straight back to the worker. A refusal holds the card for the
chief of staff after the session. Nothing here may reach the network, and the
key must never appear in anything a worker, a card or a process listing shows.
"""
import base64
import contextlib
import json
import multiprocessing
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import art_mcp  # noqa: E402
import art_requests  # noqa: E402
import drain  # noqa: E402
import execution  # noqa: E402
import work  # noqa: E402
from test_drain import ORG, fake_host  # noqa: E402

KEY = "FAKE_ART_SERVICE_VALUE_FOR_TESTS"
PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDRfake").decode()
DAY = "2026-09-29"
CODEX = {"provider": "codex", "requested_model": "haiku", "model": "gpt-5.6-luna"}
CLAUDE = {"provider": "claude", "requested_model": "haiku", "model": "haiku"}


class FakeRD:
    """Stands in for tools/rd_client.py: prices every image at `price` dollars."""

    def __init__(self, price=0.03, key=KEY, pause=0.0):
        self.price, self.key, self.pause = price, key, pause
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
        time.sleep(self.pause)
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


def request(**fields):
    return {"what": "tomato", "prompt": "a ripe tomato plant", "width": 64, "height": 64,
            "num_images": 2, "palette": ["#a4c263", "#c15a3a"], **fields}


def call(server, name, arguments=None, mid=7):
    """One tools/call through the server's own protocol handler: (text, isError)."""
    out = server.handle({"jsonrpc": "2.0", "id": mid, "method": "tools/call",
                         "params": {"name": name, "arguments": arguments or {}}})
    assert out["id"] == mid, out
    return out["result"]["content"][0]["text"], out["result"]["isError"]


def _race(store, tree, out):
    """One parallel drain worker's tool server, in its own process."""
    art_requests.STORE = store
    card = {"id": f"wrace{os.getpid()}", "title": "Race"}
    outcome = art_requests.generate_one(card, request(num_images=1), tree, (),
                                        rd=FakeRD(price=0.04, pause=0.3), day=DAY)
    out.put(outcome["status"])


class ArtTool(unittest.TestCase):
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
        self.store = str(root / "store")
        for p in (patch.object(art_requests, "STORE", self.store),
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

    def server(self, rd, item=None, attempt="att1"):
        spec = art_requests.mcp_server(item or self.card(), str(self.tree), "run1", attempt,
                                       "/main/checkout")
        return art_mcp.build(spec["args"][1:], rd=rd), spec

    def seed_ledger(self, card, dollars, day=DAY):
        art_requests._record({"work_item": card, "date": day, "dollars": dollars,
                              "recorded_by": "drain"})

    def everything_readable(self, *extra):
        """What a worker, a card or a reviewer could ever read."""
        texts = [p.read_text(errors="ignore") for p in self.tree.rglob("*") if p.is_file()
                 and ".git" not in p.parts]
        texts += [p.read_text(errors="ignore") for p in Path(self.store).rglob("*") if p.is_file()]
        texts += [p.read_text(errors="ignore") for p in self.data.rglob("*") if p.is_file()]
        return "\n".join(texts + [json.dumps(x, default=str) for x in extra])

    def drain_patches(self, session):
        stack = contextlib.ExitStack()
        for p in (patch.object(drain.execution, "launch_allowed", return_value=True),
                  patch.object(drain, "checkpoint"), patch.object(drain, "record_phase"),
                  patch.object(drain, "make_worktree", return_value=str(self.tree)),
                  patch.object(drain, "drop_worktree"),
                  patch.object(drain, "resume_held_patch", return_value=""),
                  patch.object(drain, "resume_for_revision", return_value=(False, "")),
                  patch.object(drain, "needs_godot_import", return_value=False),
                  patch.object(drain, "PATCHES", str(Path(self.tmp.name) / "patches")),
                  patch.object(drain, "WORKERS", str(Path(self.tmp.name) / "workers")),
                  patch.object(drain, "seat_prompt", return_value="seat"),
                  patch.object(drain, "run_cli", side_effect=session)):
            stack.enter_context(p)
        return stack

    # -- the protocol --------------------------------------------------------

    def test_the_server_speaks_mcp_and_lists_its_two_tools(self):
        server, _ = self.server(FakeRD())
        init = server.handle({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                              "params": {"protocolVersion": "2025-06-18", "capabilities": {}}})
        self.assertEqual(init["result"]["protocolVersion"], "2025-06-18")
        self.assertIn("tools", init["result"]["capabilities"])
        self.assertIsNone(server.handle({"jsonrpc": "2.0", "method": "notifications/initialized"}))
        tools = server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})["result"]["tools"]
        self.assertEqual([t["name"] for t in tools], ["generate_art", "art_budget"])
        schema = tools[0]["inputSchema"]
        self.assertEqual(schema["type"], "object")
        self.assertEqual(set(schema["properties"]), set(art_requests.ALLOWED),
                         "the tool takes exactly the fields validation accepts")
        self.assertEqual(schema["required"], ["what", "prompt", "width", "height"])
        self.assertEqual(server.handle({"jsonrpc": "2.0", "id": 2, "method": "nope"})["error"]["code"],
                         -32601)
        self.assertEqual(server.handle({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                        "params": {"name": "nope"}})["error"]["code"], -32602)
        text, is_error = call(server, "art_budget")
        self.assertFalse(is_error)
        self.assertEqual(text, "This card has spent $0 of its $2; the studio has spent $0 of "
                               "today's $10. A call may cost up to $2.")

    def test_the_real_server_answers_over_stdio_without_the_key(self):
        """The process the CLI starts: argv from the drain, a bare environment,
        a key file with no key. Nothing it does here reaches the network."""
        empty = Path(self.tmp.name) / "empty.env"
        empty.write_text("OTHER=1\n")
        spec = art_requests.mcp_server(self.card(), str(self.tree), "run1", "attstdio", "/nowhere")
        keys = art_requests.key_files("/nowhere")
        args = [str(empty) if a in keys else a for a in spec["args"]]
        lines = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {}},
                 {"jsonrpc": "2.0", "method": "notifications/initialized"},
                 {"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
                 {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                  "params": {"name": "generate_art", "arguments": request(model="x")}},
                 {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                  "params": {"name": "generate_art", "arguments": request()}}]
        env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp")}
        proc = subprocess.run([spec["command"], *args],
                              input="".join(json.dumps(m) + "\n" for m in lines),
                              capture_output=True, text=True, env=env, timeout=60)
        replies = [json.loads(line) for line in proc.stdout.splitlines()]
        self.assertEqual([r["id"] for r in replies], [0, 1, 2, 3], proc.stderr)
        self.assertIn("does not take: model", replies[2]["result"]["content"][0]["text"])
        self.assertIn("key could not be found", replies[3]["result"]["content"][0]["text"])
        self.assertTrue(replies[3]["result"]["isError"])
        record = json.loads(Path(art_requests.session_path("attstdio")).read_text())
        self.assertEqual((record["calls"], record["hold"]["kind"]), (2, "failed"))

    # -- a call within the caps ----------------------------------------------

    def test_a_call_within_the_caps_generates_archives_records_and_returns_paths(self):
        rd = FakeRD()
        server, spec = self.server(rd)
        text, is_error = call(server, "generate_art", request())
        self.assertFalse(is_error, text)
        raw = f"assets/raw/{DAY}-wart00000001-tomato"
        self.assertEqual(text, f"Generated 2 image(s) for $0.06: {raw}/tomato_0.png, "
                               f"{raw}/tomato_1.png (metadata {raw}/tomato_meta.json). This card "
                               "has now spent $0.06 of its $2; the next call may cost up to $1.94.")
        self.assertEqual(rd.key_paths[0], "/main/checkout/.env",
                         "the key is read from the main checkout's .env first")
        self.assertFalse(any(p.startswith(str(self.tree)) for p in rd.key_paths),
                         "never from the worktree")
        self.assertEqual(len(rd.priced), 1, "priced before generating")
        self.assertEqual(rd.priced[0]["palette_hex"], ["#a4c263", "#c15a3a"])
        self.assertEqual(sorted(p.name for p in (self.tree / raw).iterdir()),
                         ["tomato_0.png", "tomato_1.png", "tomato_meta.json"])
        self.assertTrue((Path(self.store) / Path(raw).name / "tomato_meta.json").is_file(),
                        "a durable copy survives the worktree")
        [entry] = art_requests.ledger()
        self.assertEqual((entry["work_item"], entry["recorded_by"], entry["dollars"]),
                         ("wart00000001", "drain", 0.06))
        self.assertNotIn("reservation", entry, "the reservation became the real record")
        ledger = json.loads((self.tree / "hq/data/spend.json").read_text())
        self.assertEqual(ledger["note"], "kept")
        self.assertEqual((ledger["entries"][0]["work_item"], ledger["entries"][0]["recorded_by"],
                          ledger["entries"][0]["balance_after"]), ("wart00000001", "drain", 2.5))

        # The worker looks, does not like it, and asks again in the same session.
        text, _ = call(server, "generate_art", request(num_images=1, prompt="a greener tomato"))
        self.assertIn(f"{raw}/tomato-2_0.png", text)
        art = art_requests.session_outcome("att1")
        self.assertEqual((art["calls"], len(art["generated"]), art["spent"], art["hold"]),
                         (2, 2, 0.09, None))
        self.assertIn("$0.09", art_requests.result_note(art))
        self.assertNotIn(KEY, self.everything_readable(art, spec, text))

    def test_do_item_gives_a_build_worker_the_tool_and_runs_one_session(self):
        item = self.card()
        seen = []
        rd = FakeRD()

        def session(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id,
                    attempt_id="", suffix="", mcp=None):
            seen.append((phase, suffix, prompt, mcp))
            if phase == "drain-work":
                text, _ = call(art_mcp.build(mcp["args"][1:], rd=rd), "generate_art", request())
                return "Placed the tomato: " + text, None, ""
            return "", None, "HELD"          # stop at the checker

        with self.drain_patches(session):
            rec = drain.do_item(item, ORG, "run", lambda _m: None)
        self.assertEqual(rec["error"], "", rec)
        self.assertEqual([(p, s) for p, s, _, _ in seen], [("drain-work", ""), ("drain-check", "")],
                         "no second owner session")
        self.assertEqual(seen[0][3]["tools"], ["generate_art", "art_budget"])
        self.assertIsNone(seen[1][3], "the checker gets no art tool")
        self.assertIn("generate_art", seen[0][2], "the worker is told about the tool")
        self.assertEqual(len(rd.generated), 1)
        self.assertEqual(rec["art"]["generated"][0]["folder"],
                         f"assets/raw/{DAY}-wart00000001-tomato")
        self.assertIn(f"assets/raw/{DAY}-wart00000001-tomato/tomato_0.png", rec["patch"])
        self.assertIn("hq/data/spend.json", rec["files"])
        self.assertNotIn(KEY, json.dumps(seen, default=str) + json.dumps(rec, default=str))

    def test_a_read_only_session_gets_no_tool(self):
        seen = []

        def session(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id,
                    attempt_id="", suffix="", mcp=None):
            seen.append((phase, mcp, prompt))
            return "", None, "HELD"

        with self.drain_patches(session):
            drain.do_item(self.card(tier=0), ORG, "run", lambda _m: None)
        self.assertEqual(seen[0][:2], ("drain-work", None))
        self.assertNotIn("generate_art", seen[0][2])
        base = {"id": "w1", "title": "T", "ask": "A", "first_action": "F", "owner": "sam"}
        self.assertIn("generate_art", drain.task_prompt({**base, "tier": 1}, ORG))
        self.assertIn("$2 of art", drain.task_prompt({**base, "tier": 1}, ORG))
        self.assertNotIn("generate_art", drain.task_prompt({**base, "tier": 0}, ORG))
        spec = art_requests.mcp_server(self.card(), str(self.tree), "r", "a", "/main")
        with self.assertRaises(ValueError):
            execution.command_for("p", "s", "Read,Glob,Grep", CODEX, 1, spec)

    # -- attaching it to a session -------------------------------------------

    def test_codex_and_claude_sessions_attach_the_server_without_the_key(self):
        spec = art_requests.mcp_server(self.card(), str(self.tree), "run1", "att1", "/main/checkout")
        self.assertEqual(spec["command"], sys.executable)
        self.assertTrue(spec["args"][0].endswith("hq/art_mcp.py"))
        cmd = execution.command_for("p", "s", drain.WRITE_TOOLS, CODEX, 1, spec)
        config = {}
        for flag, value in zip(cmd, cmd[1:]):
            if flag == "-c" and value.startswith("mcp_servers.art."):
                key, raw = value[len("mcp_servers.art."):].split("=", 1)
                config[key] = tomllib.loads("v = " + raw)["v"]
        self.assertEqual(config["command"], sys.executable)
        self.assertEqual(config["args"], spec["args"])
        self.assertEqual(config["default_tools_approval_mode"], "approve",
                         "nobody is there to answer an approval prompt")
        self.assertEqual(config["enabled_tools"], ["generate_art", "art_budget"])
        self.assertGreaterEqual(config["tool_timeout_sec"], 600)
        self.assertNotIn("required", config, "a server that fails to start must not stop the session")
        self.assertIn("workspace-write", cmd)
        claude = execution.command_for("p", "s", drain.WRITE_TOOLS, CLAUDE, 1, spec)
        allowed = claude[claude.index("--allowedTools") + 1]
        self.assertTrue(allowed.endswith(",mcp__art__generate_art,mcp__art__art_budget"))
        server = json.loads(claude[claude.index("--mcp-config") + 1])["mcpServers"]["art"]
        self.assertEqual(server["args"], spec["args"])

        seen = {}

        def popen(command, **kwargs):
            seen.update(command=command, env=kwargs["env"])
            raise OSError("stop here")

        with patch.dict(os.environ, {"RETRODIFFUSION_API_KEY": KEY}), \
             patch.object(execution, "resolve_model", return_value=CODEX), \
             patch.object(execution, "launch_allowed", return_value=True), \
             patch.object(execution, "check_mcp_config"), \
             patch.object(execution.subprocess, "Popen", side_effect=popen):
            execution.run_session("p", "s", drain.WRITE_TOOLS, "haiku", str(self.tree), 10, 1,
                                  mcp=spec)
        self.assertIn("mcp_servers.art.command=" + json.dumps(sys.executable), seen["command"])
        self.assertNotIn("RETRODIFFUSION_API_KEY", seen["env"])
        self.assertNotIn(KEY, json.dumps(seen))

    def test_the_session_log_keeps_what_the_tool_answered(self):
        """Codex reports a tool server call without shell output; its reply text
        is what a reviewer of the session needs to see."""
        normalizer = execution.Normalizer(CODEX)
        [event] = normalizer.feed({"type": "item.completed", "item": {
            "id": "item_3", "type": "mcp_tool_call", "server": "art", "tool": "generate_art",
            "arguments": request(), "status": "completed", "error": None,
            "result": {"content": [{"type": "text", "text": "Generated 2 image(s) for $0.06"}]}}})
        block = event["message"]["content"][0]
        self.assertEqual((block["type"], block["content"], block["is_error"]),
                         ("tool_result", "Generated 2 image(s) for $0.06", False))

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

    # -- the caps ----------------------------------------------------------

    def test_card_cap_refuses_and_holds_the_card_after_the_session(self):
        self.seed_ledger("wart00000001", 1.90)
        rd = FakeRD()
        server, _ = self.server(rd)
        text, is_error = call(server, "generate_art", request(num_images=4))   # $0.12 -> $2.02
        self.assertTrue(is_error)
        reason = ("This card has spent $1.90 of its $2 and the studio $1.90 of today's $10; "
                  "this request would cost $0.12.")
        self.assertTrue(text.startswith("Nothing was generated. " + reason), text)
        self.assertEqual(rd.generated, [], "nothing is generated past the cap")
        self.assertEqual(art_requests.spent(), 1.90, "a refusal costs nothing")
        art = art_requests.session_outcome("att1")
        self.assertEqual((art["hold"]["kind"], art["hold"]["reason"], art["hold"]["asked"]),
                         ("card", reason, 0.12))

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
        self.assertEqual(art_requests.settle_holds(day="2026-09-30"), [],
                         "a new day does not lift a card cap")
        item["art_cap_usd"] = 3.0
        work.save_item(item)
        self.assertEqual(art_requests.settle_holds(day=DAY), ["wart00000001"])
        item = work.load_item("wart00000001")
        view = work.work_view(item, {"head": "old"}, now=1e10)
        self.assertIsNone(view["blocker"])
        self.assertEqual(work.card_lanes(item, view), ["runner"])

    def test_a_refusal_in_the_session_reaches_the_card_through_do_item(self):
        self.seed_ledger("wart00000001", 2.00)
        rd = FakeRD()

        def session(prompt, system, tools, model, cwd, timeout, turns, phase, seat, item_id,
                    attempt_id="", suffix="", mcp=None):
            if phase == "drain-work":
                call(art_mcp.build(mcp["args"][1:], rd=rd), "generate_art", request())
                return "Done except the sprite, which the art limit refused.", None, ""
            return "", None, "HELD"

        with self.drain_patches(session):
            rec = drain.do_item(self.card(), ORG, "run", lambda _m: None)
        self.assertEqual(rd.generated, [])
        self.assertEqual(rec["art"]["hold"]["kind"], "card")
        art_requests.after_write_back(self.card(state="for_review"), rec)
        item = work.load_item("wart00000001")
        self.assertEqual(work.card_lanes(item, work.work_view(item, {}, now=1e10)), ["held"])

    def test_day_cap_counts_every_card(self):
        self.seed_ledger("wother000001", 6.00)
        self.seed_ledger("wother000002", 3.95)
        self.seed_ledger("wother000003", 5.00, day="2026-09-28")   # yesterday does not count
        rd = FakeRD()
        outcome = art_requests.generate_one(self.card(), request(), str(self.tree), (), rd=rd)
        self.assertEqual(rd.generated, [])
        self.assertEqual(outcome["hold"]["kind"], "day")
        self.assertEqual(outcome["reason"],
                         "This card has spent $0 of its $2 and the studio $9.95 of today's $10; "
                         "this request would cost $0.06.")
        art = art_requests.note_call(art_requests.new_session(DAY), outcome)
        art_requests.after_write_back(self.card(state="for_review"), {"art": art, "attempt_id": "a1"})
        item = work.load_item("wart00000001")
        self.assertEqual(work.card_lanes(item, work.work_view(item, {}, now=1e10)), ["held"])
        self.assertEqual(art_requests.settle_holds(day=DAY), [])
        self.assertEqual(art_requests.settle_holds(day="2026-09-30"), ["wart00000001"])

    def test_parallel_workers_cannot_overspend_the_day(self):
        """Four tool servers in four processes, each asking for $0.04 while the
        studio has $0.10 left: the lock and the reservation let exactly two through."""
        self.seed_ledger("wother000001", 9.90)
        ctx = multiprocessing.get_context("fork")
        out = ctx.Queue()
        procs = [ctx.Process(target=_race, args=(self.store, str(self.tree), out)) for _ in range(4)]
        for p in procs:
            p.start()
        for p in procs:
            p.join(30)
        statuses = sorted(out.get(timeout=5) for _ in procs)
        self.assertEqual(statuses, ["generated", "generated", "refused", "refused"])
        self.assertEqual(art_requests.spent(day=DAY), 9.98)
        self.assertFalse(any(e.get("reservation") for e in art_requests.ledger()))

    def test_a_landed_card_is_not_held(self):
        self.seed_ledger("wart00000001", 2.00)
        outcome = art_requests.generate_one(self.card(), request(), str(self.tree), (), rd=FakeRD())
        art = art_requests.note_call(art_requests.new_session(DAY), outcome)
        item = self.card(state="landed", result="Shipped without the sprite.")
        art_requests.after_write_back(item, {"art": art})
        item = work.load_item("wart00000001")
        self.assertEqual(item["state"], "landed")
        self.assertIn("would cost $0.06", item["result"])
        self.assertFalse(item.get("art_hold"))

    # -- what is refused without spending ----------------------------------

    def test_malformed_requests_are_rejected_with_a_reason(self):
        rd = FakeRD()
        server, _ = self.server(rd)
        cases = {"model": request(model="rd_fast"), "num_images": request(num_images=9),
                 "width": request(width=4096),
                 "inside the worktree": request(input_image="../../etc/passwd.png"),
                 "slug": request(what="Tomato!")}
        for expected, args in cases.items():
            text, is_error = call(server, "generate_art", args)
            self.assertTrue(is_error)
            self.assertIn(expected, text)
            self.assertTrue(text.startswith("Nothing was generated or charged."), text)
        self.assertEqual(rd.priced, [], "a malformed request costs nothing")
        art = art_requests.session_outcome("att1")
        self.assertEqual((len(art["rejected"]), art["hold"]), (5, None))
        self.assertIn("did not follow the request format", art_requests.result_note(art))

    def test_a_missing_key_holds_without_calling_the_service(self):
        rd = FakeRD(key=None)
        outcome = art_requests.generate_one(self.card(), request(), str(self.tree), (), rd=rd)
        self.assertEqual(outcome["hold"]["kind"], "failed")
        self.assertIn("key could not be found", outcome["hold"]["reason"])
        self.assertEqual(rd.priced, [])

    def test_an_unreadable_spend_record_generates_nothing(self):
        os.makedirs(self.store, exist_ok=True)
        Path(art_requests._ledger_path()).write_text("{broken")
        rd = FakeRD()
        outcome = art_requests.generate_one(self.card(), request(), str(self.tree), (), rd=rd)
        self.assertEqual(rd.generated, [], "an unreadable ledger must not read as $0 spent")
        self.assertEqual(outcome["hold"]["kind"], "failed")

    def test_a_service_error_never_repeats_the_key(self):
        class Failing(FakeRD):
            def cost(self, key, params):
                raise RuntimeError(f"401 for token {key}")
        server, _ = self.server(Failing())
        text, is_error = call(server, "generate_art", request())
        self.assertTrue(is_error)
        self.assertIn("[key]", text)
        art = art_requests.session_outcome("att1")
        self.assertEqual(art["hold"]["kind"], "failed", "a session whose art all failed is held")
        self.assertNotIn(KEY, json.dumps(art) + text + self.everything_readable())

    def test_a_call_that_dies_mid_generation_stays_counted(self):
        class Dies(FakeRD):
            def generate(self, key, name, params, out_dir):
                raise TimeoutError("read timed out")

        class Refused(FakeRD):
            def generate(self, key, name, params, out_dir):
                return None
        item = self.card()
        art_requests.generate_one(item, request(), str(self.tree), (), rd=Dies())
        [entry] = art_requests.ledger()
        self.assertEqual((entry["dollars"], entry["unconfirmed"]), (0.06, True),
                         "a timed-out call may have been billed, so its price stays counted")
        art_requests.generate_one(item, request(), str(self.tree), (), rd=Refused())
        self.assertEqual(art_requests.spent(), 0.06, "a call the service refused was not charged")


if __name__ == "__main__":
    unittest.main()

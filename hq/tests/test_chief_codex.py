import json
import argparse
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

os.environ.setdefault("HQ_TEST_SCRATCH", tempfile.mkdtemp(prefix="hq-chief-codex-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain  # noqa: E402
import execution  # noqa: E402
import work  # noqa: E402
from test_drain import ORG, fake_host  # noqa: E402
from test_landing_bar import GREEN, bar, item as landing_item, rec as landing_rec  # noqa: E402


class ChiefCodex(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.host = fake_host(self.tmp.name)
        self.host.load_json = lambda path: json.loads(Path(path).read_text())
        self.host.build_system_prompt = lambda *_: "system"
        self.host.cfg = lambda name: os.path.join(self.tmp.name, name)
        work.bind(self.host)

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, item_id="wc0dec0000001", **over):
        card = {"id": item_id, "title": "Capture the room", "level": "task",
                "owner": "jade", "tier": 1, "tier_reason": "code", "ask": "Capture it.",
                "first_action": "Open the room.", "state": "waiting_session", "thread": "jade",
                "source": "chat", "source_message": "", "result": "", "started": "",
                "attempts": 0, "created": "2026-09-29T01:00", "created_ts": 1.0}
        card.update(over)
        return work.save_item(card)

    def test_no_held_work_starts_nothing(self):
        self.assertEqual(drain.chief_of_staff_queue(), [])
        with patch.object(work, "review_chief_hold") as review:
            self.assertEqual(drain.route_chief_of_staff_queue(ORG), [])
        review.assert_not_called()

    def test_only_normal_drain_routes_reviews(self):
        modes = ("brief", "repair", "recover_only", "retry_once", "finish_verified",
                 "dry_run", "list", "list_json")
        args = argparse.Namespace(**{name: False for name in modes})
        self.assertTrue(drain.chief_routing_enabled(args))
        for name in modes:
            setattr(args, name, True)
            self.assertFalse(drain.chief_routing_enabled(args), name)
            setattr(args, name, False)

    def test_each_hold_kind_and_no_lane_are_selected(self):
        cards = [self.card(f"wc0dec000000{i}") for i in range(1, 6)]
        kinds = ["spending_hold", "repairs_used_up", "chief_hold", "art_budget", None]
        views = {card["id"]: {"blocker": ({"type": kind} if kind else None)}
                 for card, kind in zip(cards, kinds)}
        with patch.object(drain, "project_work", side_effect=lambda item: views[item["id"]]), \
             patch.object(work, "card_lanes", side_effect=lambda item, view: [] if not view["blocker"] else ["held"]):
            got = drain.chief_of_staff_queue()
        self.assertEqual([row["reason"] for row in got], kinds[:-1] + ["no_lane"])

    def test_structured_reviewer_need_marks_display(self):
        card = self.card(check={"summary": "captures not produced", "needs": ["display"],
                                "findings": []})
        self.assertTrue(drain.mark_capability_needs(card, {"blocker": {}}))
        self.assertEqual(work.load_item(card["id"])["needs"], ["display"])

    def test_negated_adb_and_incidental_words_never_grant_host_access(self):
        card = self.card(check={"summary": "No adb or tablet access is needed.",
                                "findings": [{"what": "Display tests already passed."}]})
        self.assertFalse(drain.mark_capability_needs(card, {"blocker": {
            "reason": "Do not run adb on the tablet or use a display."}}))
        self.assertEqual(drain.capability_needs(work.load_item(card["id"])), [])

    def test_capability_hold_requires_review_before_action_selection(self):
        card = self.card(check={"summary": "captures not produced", "needs": ["display"], "findings": []},
                         spending_checkpoint={"held_for": "claude", "return_state": "waiting_session",
                                              "exceeded": ["tokens"], "reason": "No display."})
        view = {"blocker": {"type": "spending_hold", "reason": "No display."}}
        with patch.object(drain, "chief_of_staff_queue", return_value=[
                {"item": card, "view": view, "path": "judgement", "reason": "spending_hold"}]), \
             patch.object(work, "review_chief_hold", return_value=False) as review:
            routed = drain.route_chief_of_staff_queue(ORG)
        saved = work.load_item(card["id"])
        self.assertEqual(routed, [(card["id"], "held")])
        review.assert_called_once()
        self.assertEqual(saved["needs"], ["display"])
        self.assertTrue(work.cap_held(saved))
        self.assertNotIn("cap_reviews", saved)

    def test_startup_accounts_for_every_scanned_kind(self):
        cards = [self.card(f"wc0dec000001{i}") for i in range(5)]
        rows = [{"item": card, "view": {"blocker": {"type": kind} if kind else {}},
                 "path": "judgement", "reason": kind or "no_lane"}
                for card, kind in zip(cards,
                    ["spending_hold", "repairs_used_up", "chief_hold", "art_budget", None])]
        with patch.object(drain, "chief_of_staff_queue", return_value=rows), \
             patch.object(work, "cap_held", side_effect=[True, False, False, False, False]), \
             patch.object(work, "repair_held", side_effect=[True, True, False, False, False]), \
             patch.object(work, "review_chief_hold", return_value=True) as review:
            routed = drain.route_chief_of_staff_queue(ORG)
        self.assertEqual(len(routed), 5)
        self.assertEqual(review.call_count, 4)
        self.assertEqual([path for _card, path in routed], ["reviewed"] * 4 + ["structural_fault"])

    def test_no_lane_cannot_authorize_model_close(self):
        card = self.card()
        with patch.object(work.execution, "launch_allowed", return_value=True), \
             patch.object(work, "_run_cli") as model:
            self.assertFalse(work.review_chief_hold(card, ORG, hold_kind="no_lane"))
        model.assert_not_called()
        self.assertEqual(work.load_item(card["id"])["state"], "waiting_session")

    def test_capability_profile_is_codex_unsandboxed(self):
        route = execution.resolve_model("haiku")
        command = execution.command_for("p", "s", drain.WRITE_TOOLS, route, 1,
                                        profile="capability")
        self.assertIn("danger-full-access", command)
        self.assertEqual(command[0], "codex")

    def test_capability_candidate_uses_the_ordinary_landing_bar(self):
        card = landing_item(needs=["display"])
        self.assertFalse(bar(it=card, suites=None)[0])
        self.assertFalse(bar(it=card, r=landing_rec(check=None))[0])
        self.assertFalse(bar(it=card, applied=False, suites=GREEN)[0])
        self.assertTrue(bar(it=card, suites=GREEN)[0])

    def _review(self, card, answer):
        with patch.object(work.execution, "launch_allowed", return_value=True), \
             patch.object(work, "_run_cli", return_value=(json.dumps(answer), False)):
            return work.review_chief_hold(work.load_item(card["id"]), ORG)

    def _held_card(self, **over):
        return self.card(check={"summary": "captures not produced", "findings": [
            {"what": "captures not produced"}]},
            spending_checkpoint={"held_for": "claude", "return_state": "waiting_session",
                                 "exceeded": ["tokens"], "reason": "No display."}, **over)

    def test_extend_records_finding_and_attribution(self):
        card = self._held_card()
        answer = {"outcome": "extend", "reason": "A display is available now.",
                  "brief": "Resolve captures not produced with a fresh capture."}
        self.assertTrue(self._review(card, answer))
        saved = work.load_item(card["id"])
        self.assertFalse(work.cap_held(saved))
        self.assertEqual(saved["cap_reviews"][-1]["by"], "claude")
        self.assertIn("captures not produced", saved["cap_reviews"][-1]["reason"])
        self.assertIn("Codex", saved["cap_reviews"][-1]["via"])

    def test_rescope_persists_narrow_ask_and_review(self):
        card = self._held_card()
        answer = {"outcome": "rescope", "reason": "The room is enough.",
                  "ask": "Capture only the room.",
                  "brief": "Fix captures not produced for the room."}
        self.assertTrue(self._review(card, answer))
        saved = work.load_item(card["id"])
        self.assertIn("Capture only the room", saved["ask"])
        self.assertEqual(saved["cap_reviews"][-1]["decision"], "rescope")
        self.assertEqual(saved["cap_reviews"][-1]["by"], "claude")

    def test_close_needs_recorded_completion_evidence(self):
        canonical = self.card("wc0dec0000099", state="landed",
                              completion={"sha": "abc", "at": "2026-09-29T02:00"})
        card = self._held_card(result="The reviewed capture already landed on main.",
                               superseded_by=canonical["id"])
        bad = {"outcome": "close", "reason": "It is done.", "evidence": "I guessed it is done."}
        self.assertFalse(self._review(card, bad))
        self.assertTrue(work.cap_held(work.load_item(card["id"])))
        good = {"outcome": "close", "reason": "The canonical card landed.",
                "evidence": canonical["id"]}
        self.assertTrue(self._review(card, good))
        saved = work.load_item(card["id"])
        self.assertEqual(saved["state"], "dropped")
        self.assertIn(good["evidence"], saved["result"])
        self.assertEqual(saved["chief_reviews"][-1]["by"], "claude")
        self.assertIn("Codex", saved["chief_reviews"][-1]["via"])

    def test_old_result_keyword_cannot_close(self):
        card = self._held_card(result="Work was done and merged last week.")
        self.assertFalse(self._review(card, {"outcome": "close", "reason": "Done",
                                               "evidence": "Work was done and merged last week."}))
        self.assertTrue(work.cap_held(work.load_item(card["id"])))

    def test_spending_ceiling_and_extension_count_remain_enforced(self):
        answer = {"outcome": "extend", "reason": "Small remaining work",
                  "brief": "Resolve captures not produced."}
        ceiling = self._held_card(token_cap=work.CAP_CEILINGS["tokens"])
        self.assertFalse(self._review(ceiling, answer))
        saved = work.load_item(ceiling["id"])
        self.assertTrue(work.cap_held(saved))
        self.assertEqual(saved["token_cap"], work.CAP_CEILINGS["tokens"])
        counted = self._held_card(item_id="wc0dec0000088", cap_reviews=[
            {"decision": "extend"} for _ in range(work.CAP_AUTO_EXTENSIONS)])
        self.assertFalse(self._review(counted, answer))
        self.assertTrue(work.cap_held(work.load_item(counted["id"])))
        with self.assertRaisesRegex(ValueError, "spending extension limit"):
            work.release_chief_hold_for_capability(work.load_item(counted["id"]),
                                                   "Resolve captures not produced.")
        self.assertTrue(work.cap_held(work.load_item(counted["id"])))

    def test_unrelated_card_revision_discards_model_answer(self):
        card = self._held_card()
        answer = {"outcome": "extend", "reason": "A display is ready.",
                  "brief": "Resolve captures not produced."}
        def concurrent_edit(*_args, **_kwargs):
            fresh = work.load_item(card["id"])
            fresh["ask"] = "The owner refined this ask while the model was running."
            work.save_item(fresh)
            return json.dumps(answer), False
        with patch.object(work.execution, "launch_allowed", return_value=True), \
             patch.object(work, "_run_cli", side_effect=concurrent_edit):
            self.assertFalse(work.review_chief_hold(work.load_item(card["id"]), ORG))
        saved = work.load_item(card["id"])
        self.assertTrue(work.cap_held(saved))
        self.assertEqual(saved["ask"], "The owner refined this ask while the model was running.")

    def test_concurrent_hold_resolution_discards_model_answer(self):
        card = self._held_card()
        answer = {"outcome": "extend", "reason": "A display is ready.",
                  "brief": "Resolve captures not produced."}
        def concurrent_resolution(*_args, **_kwargs):
            fresh = work.load_item(card["id"])
            fresh.pop("spending_checkpoint")
            fresh["state"] = "accepted"
            work.save_item(fresh)
            return json.dumps(answer), False
        with patch.object(work.execution, "launch_allowed", return_value=True), \
             patch.object(work, "_run_cli", side_effect=concurrent_resolution):
            self.assertFalse(work.review_chief_hold(work.load_item(card["id"]), ORG))
        saved = work.load_item(card["id"])
        self.assertEqual(saved["state"], "accepted")
        self.assertFalse(work.cap_held(saved))
        self.assertEqual(saved.get("cap_reviews"), None)

    def test_two_unusable_answers_leave_hold_and_no_third_call(self):
        card = self._held_card()
        answer = {"outcome": "extend", "reason": "Maybe", "brief": "Try again."}
        self.assertFalse(self._review(card, answer))
        self.assertFalse(self._review(card, answer))
        with patch.object(work, "_run_cli") as model:
            self.assertFalse(work.review_chief_hold(work.load_item(card["id"]), ORG))
        model.assert_not_called()
        saved = work.load_item(card["id"])
        self.assertEqual(saved["chief_review_tries"], 2)
        self.assertTrue(work.cap_held(saved))

    def test_two_limited_answers_also_leave_hold(self):
        card = self._held_card()
        with patch.object(work.execution, "launch_allowed", return_value=True), \
             patch.object(work, "_run_cli", return_value=("", True)) as model:
            self.assertFalse(work.review_chief_hold(work.load_item(card["id"]), ORG))
            self.assertFalse(work.review_chief_hold(work.load_item(card["id"]), ORG))
            self.assertFalse(work.review_chief_hold(work.load_item(card["id"]), ORG))
        self.assertEqual(model.call_count, 2)
        self.assertEqual(work.load_item(card["id"])["chief_review_tries"], 2)

    def test_capability_env_strips_all_secret_and_credential_keys(self):
        with patch.dict(os.environ, {"RETRODIFFUSION_API_KEY": "a", "OTHER_API_KEY": "b",
                                     "SESSION_TOKEN": "c", "PASSWORD": "d", "DISPLAY": ":9"}):
            env = execution._session_env({"DISPLAY": ":0.0"}, profile="capability")
        self.assertEqual(env["DISPLAY"], ":0.0")
        for key in ("RETRODIFFUSION_API_KEY", "OTHER_API_KEY", "SESSION_TOKEN", "PASSWORD"):
            self.assertNotIn(key, env)
        self.assertEqual(set(env) - {"CLAUDE_CODE_DISABLE_AUTOUPDATE"},
                         set(env).intersection(execution._CAPABILITY_ENV))
        with self.assertRaises(ValueError):
            execution._session_env({"OTHER_API_KEY": "oops"})

    def test_taste_stays_held_and_files_a_draft(self):
        card = self.card(spending_checkpoint={"held_for": "claude", "return_state": "waiting_session",
                                              "exceeded": ["tokens"], "reason": "Taste call."})
        answer = json.dumps({"outcome": "taste", "reason": "The player sees it.",
                             "question": "Which room shape should ship?", "recommend": "Round",
                             "why": "It reads clearly.", "instead": "Square"})
        with patch.object(work.execution, "launch_allowed", return_value=True), \
             patch.object(work, "_run_cli", return_value=(answer, False)):
            self.assertTrue(work.review_chief_hold(work.load_item(card["id"]), ORG))
        saved = work.load_item(card["id"])
        self.assertTrue(work.cap_held(saved))
        self.assertEqual(saved["decision_draft"]["source_work"], card["id"])
        self.assertEqual(saved["decision_draft"]["by"], "claude")
        self.assertEqual(saved["decision_draft"]["options"], ["Round", "Square"])
        self.assertFalse(Path(self.tmp.name, "decisions").exists())


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""A pillar's "What I need from you" lists only what his decisions page shows.

2026-09-29: the Engineering page listed a tier-2 card as "What I need from you ·
Approve or decline" while the studio still held it (a repair hold, an
out-of-date change), and the button led to a decisions page that, correctly,
did not have it (w3b629423e60). The band now takes its asks from
server.waiting_on_you(), the decisions page's own readiness test.
"""
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("HQ_TEST_SCRATCH", tempfile.mkdtemp(prefix="hq-pillar-needs-"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import drain  # noqa: E402
import server  # noqa: E402
import work  # noqa: E402
from test_drain import fake_host, ORG  # noqa: E402

PILLARS = {"pillars": [{"id": "engineering", "team": "Engineering", "name": "Engineering"}]}


class PillarNeeds(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        work.bind(fake_host(self.tmp.name))
        real_load_json = server.load_json
        stubs = [
            patch.object(server, "load_org", lambda: ORG),
            patch.object(server, "compute_signals", lambda *a, **k: {"goals": {}}),
            patch.object(server, "api_queue", lambda **kw: {"curated": [], "decided": [], "rulings": {}}),
            patch.object(server, "load_json",
                         lambda p: PILLARS if str(p).endswith("pillars.json") else real_load_json(p)),
            patch.object(drain.server, "drain_state", lambda: {}),
        ]
        for stub in stubs:
            stub.start()
            self.addCleanup(stub.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, **over):
        base = {"id": "wbad000000001", "title": "Fill in the store page during a tagged release",
                "level": "task", "owner": "sam", "tier": 2, "tier_reason": "publishes",
                "ask": "Build the release step.", "first_action": "Read release.yml.",
                "state": "needs_approval", "thread": "sam", "source": "chat",
                "source_message": "", "result": "Built and tested.", "started": "",
                "attempts": 1, "created": "2026-09-25T00:39", "created_ts": 1.0,
                "finished": "2026-09-28T22:44",
                "recommend": {"question": "Add the read-only store-page check to releases?",
                              "answer": "Yes.", "why": "It reads the public page and publishes nothing.",
                              "instead": "Keep pasting by hand."},
                "deliverable": {"name": "Store-page check",
                                "evidence": [{"label": "The release step", "path": ".github/workflows/release.yml"}]},
                "follow_ups": []}
        base.update(over)
        return work.save_item(base)

    def ready_ids(self):
        return {row["source_id"] for row in server.waiting_on_you()["ready"]}

    def test_a_card_the_studio_still_holds_is_not_listed(self):
        item = self.card(repair_hold="This worker cannot reach itch.io, so the comparison was not recorded.")
        self.assertNotIn(item["id"], self.ready_ids())
        self.assertEqual(server.api_needs("engineering")["needs"], [])

    def test_a_card_ready_for_his_verdict_is_listed_and_leads_to_his_page(self):
        item = self.card()
        self.assertIn(item["id"], self.ready_ids())
        needs = server.api_needs("engineering")["needs"]
        self.assertEqual([n["surface"]["id"] for n in needs], [item["id"]])
        self.assertEqual(needs[0]["href"], "#/work")
        # Counted from when the result came back, not from when the card was filed.
        self.assertEqual(needs[0]["waiting_days"], server._days_since_date("2026-09-28"))

    def test_another_teams_ready_card_stays_on_its_own_page(self):
        self.card(owner="claude")
        self.assertEqual(server.api_needs("engineering")["needs"], [])

    def test_a_goal_row_says_waiting_on_your_yes_only_when_his_page_shows_it(self):
        # The goal row's link falls back to "waiting on your yes" for a card in
        # needs_approval; a card the studio still holds must say so instead.
        with patch.object(server, "worker_sessions", lambda *a, **k: []):
            item = self.card(repair_hold="This worker cannot reach itch.io.")
            held = server._route_target({"kind": "work", "id": item["id"]})
            self.assertEqual(held["state_human"], "held by the studio, not yet ready for you")
            ready = self.card(id="wbad000000002")
            shown = server._route_target({"kind": "work", "id": ready["id"]})
            self.assertEqual(shown["state_human"], "")


if __name__ == "__main__":
    unittest.main()

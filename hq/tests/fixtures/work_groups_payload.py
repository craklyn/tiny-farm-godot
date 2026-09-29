#!/usr/bin/env python3
"""Print the Work page's cards and the task queue, both as HQ's backend builds them.

Used by hq/tests/test_work_tabs.js so the Work tab's groups are checked against
the real projection the task queue reads, for a scratch store holding one card
in each situation that matters: ready, being worked, blocked, waiting on
Daniel, prepared by HQ itself, stalled outside the queue, and closed.
"""
import json
import os
import shutil
from pathlib import Path
import sys
import tempfile

store = Path(tempfile.mkdtemp(prefix="hq-work-groups-"))
for folder in ("work", "rulings", "decisions"):
    (store / folder).mkdir()
(store / "org.json").write_text(json.dumps({"employees": [
    {"id": "claude", "name": "Adam"}, {"id": "rin", "name": "Rin Nakamura"}]}))
os.environ["HQ_DATA_ROOT"] = str(store)
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import server  # noqa: E402
import closing  # noqa: E402
import drain  # noqa: E402

server.work.bind(server, sanitize=False)
# The spending window is not what this fixture is about, and reads a policy file
# a scratch store does not have.
server.token_window = lambda *args, **kwargs: {}
base = {"owner": "rin", "tier": 1, "created": "2026-09-25T08:00:00", "created_ts": 1}
cards = {
    "w00000000001": {"title": "Ready to build", "state": "waiting_session",
                     "first_action": "Read the shelf code."},
    "w00000000002": {"title": "Claimed from outside", "state": "waiting_session",
                     "first_action": "Fix the shelf."},
    "w00000000003": {"title": "Waits on art", "state": "waiting_session",
                     "first_action": "Paint.", "waiting_for": {"reason": "Waits on the shop art."}},
    "w00000000004": {"title": "Tests failed twice", "state": "for_review",
                     "repair_hold": "The suites failed twice.", "automatic_repairs": 1},
    "w00000000005": {"title": "A reading to review", "state": "for_review", "tier": 0,
                     "finished": "2026-09-25T09:00:00"},
    "w00000000006": {"title": "A question for Daniel", "state": "needs_approval", "tier": 2},
    "w00000000007": {"title": "A question being prepared", "state": "prepping", "tier": 2},
    "w00000000008": {"title": "A question nobody can prepare", "state": "prepping", "tier": 2,
                     "prep_stalled": "A person has to write this one."},
    "w00000000009": {"title": "Shipped", "state": "landed"},
}
for card_id, fields in cards.items():
    (store / "work" / f"{card_id}.json").write_text(json.dumps({"id": card_id, **base, **fields}))
closing.claim("w00000000002", by="Codex session", seconds=3600)

try:
    doc = {"items": server.work.snapshot()["items"], "queue": drain.queue_view()}
finally:
    shutil.rmtree(store, ignore_errors=True)
print(json.dumps(doc))

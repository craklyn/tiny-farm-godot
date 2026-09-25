#!/usr/bin/env python3
"""Print the task queue's JSON exactly as HQ's backend builds it for a scratch store.

Used by hq/tests/test_queue_rulings_browser.js so the page is tested against the
real projection, not a hand-written fixture: two rulings recorded through
``record_ruling`` (one of them before start-up, backfilled), one integrated,
one card claimed by an outside session.
"""
import json
import os
import shutil
from pathlib import Path
import sys
import tempfile

store = Path(tempfile.mkdtemp(prefix="hq-ruling-queue-"))
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
decisions = {
    "Q-901": {"subject": "Where HQ keeps its work cards", "owner": "claude",
              "options": [{"key": "a", "label": "A separate folder (Recommended)"}]},
    "Q-902": {"subject": "The planting sound", "owner": "rin",
              "options": [{"key": "b", "label": "The two soft beats"}]},
    "Q-903": {"subject": "An already integrated ruling", "owner": "rin",
              "options": [{"key": "a", "label": "Anything"}]},
}
for qid, card in decisions.items():
    (store / "decisions" / f"{qid}.json").write_text(json.dumps(
        {"id": qid, "title": card["subject"] + "?", "question": "?", **card}))
# Recorded before HQ started: the start-up backfill must file its card.
(store / "rulings" / "Q-901.json").write_text(json.dumps({
    "id": "Q-901", "option": "a", "option_label": "A separate folder (Recommended)",
    "judgment": None, "intent": "choose", "submission_id": "early-submission-0001",
    "ruled_at": "2026-09-25T10:01:43", "status": "pending_integration", "earlier": []}))
(store / "rulings" / "Q-903.json").write_text(json.dumps({
    "id": "Q-903", "option": "a", "option_label": "Anything", "intent": "choose",
    "submission_id": "done-submission-0001", "ruled_at": "2026-09-20T09:00:00",
    "status": "integrated", "earlier": []}))
server.backfill_ruling_work()
server.record_ruling({"id": "Q-902", "intent": "choose", "option": "b",
                      "submission_id": "live-submission-00002",
                      "judgment": "Keep it quiet under the music."})
# A card an outside session is working, so the page shows it under Working now.
claimed = {"id": "w0000000000c", "title": "Fix the shop shelf", "owner": "rin", "tier": 1,
           "state": "waiting_session", "created": "2026-09-25T08:00:00", "created_ts": 1,
           "first_action": "Read the shelf code."}
(store / "work" / "w0000000000c.json").write_text(json.dumps(claimed))
closing.claim("w0000000000c", by="Codex session", seconds=3600)

try:
    doc = drain.queue_view()
    doc["rulings_waiting"] = server.rulings_waiting()
finally:
    shutil.rmtree(store, ignore_errors=True)
print(json.dumps(doc))

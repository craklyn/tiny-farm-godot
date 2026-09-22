#!/usr/bin/env python3
"""Fixtures for the one ready-for-Daniel projection."""
import os
import json
import tempfile
from pathlib import Path
from unittest.mock import patch
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import server  # noqa: E402


REC = {"question": "Keep it?", "answer": "Keep it", "why": "It works",
       "instead": "Send it back"}


def card(card_id, state, **extra):
    out = {
        "id": card_id,
        "state": state,
        "recommend": REC,
        "deliverable": {
            "name": "The revised result",
            "evidence": [{"label": "Review it", "href": "/review/result"}],
        },
        "follow_ups": [],
    }
    out.update(extra)
    if out.get("follow_ups") is None:
        out.pop("follow_ups")
    return out


def main():
    failures = []

    def check(value, label):
        print(("ok   " if value else "FAIL ") + label)
        if not value:
            failures.append(label)

    decisions = [
        {"id": "q-ready", "title": "Ready", "options": []},
        {"id": "q-returned", "title": "Returned", "options": [],
         "replies": [{"at": "2026-09-21T12:01:00Z"}]},
        {"id": "q-studio", "title": "With studio", "options": []},
        {"id": "q-done", "title": "Done", "options": []},
    ]
    queue = {"curated": decisions, "decided": ["q-done"], "rulings": {
        "q-returned": {"judgment": "More detail", "ruled_at": "2026-09-21T12:00:00Z"},
        "q-studio": {"judgment": "More detail", "ruled_at": "2026-09-21T12:00:00Z"},
    }}
    fixtures = [
        card("w-ready", "for_review"),
        card("w-approval", "needs_approval"),
        card("w-unprepared", "for_review", recommend={}),
        card("w-no-question", "for_review", recommend={}, recommendation_required=False,
             recommendation_reason="Daniel must judge the result."),
        card("w-no-recommendation", "for_review", recommend={"question": "Keep it?"}),
        card("w-no-recommendation-explanation", "for_review", recommend={},
             review_question="Keep it?", recommendation_required=False),
        card("w-no-deliverable", "for_review", deliverable={}),
        card("w-no-evidence", "for_review", deliverable={"name": "The revised result"}),
        card("w-no-consequences", "for_review", follow_ups=None),
        card("w-explicit-verdict", "for_review", recommend={},
             review_question="Does this finished result stand?",
             recommendation_required=False,
             recommendation_reason="Only Daniel can judge whether this animation reads clearly."),
        card("w-reply", "for_review", awaiting_reply=True),
        card("w-held", "for_review", held_patch="/tmp/patch"),
        card("w-preparing", "prepping"),
        card("w-doing", "doing"),
        card("w-scheduled", "waiting_session"),
        card("w-accepted", "accepted"),
        card("w-landed", "landed", suites={"unit": {"ok": True}}),
        card("w-reading", "for_review", tier=0, recommend={}),
        card("w-green", "for_review", tier=1, recommend={}, suites={"unit": {"ok": True}}),
        card("w-failed", "for_review", tier=0, recommend={}, check={"verdict": "fail"}),
        card("w-risky", "for_review", tier=0, recommend={}, follow_ups=[{"tier": 2}]),
        card("w-old", "for_review", tier=0, recommend={}, source="chief-of-staff", created="2026-09-10"),
        card("w-unknown", "unrecognized"),
    ]
    old_queue, old_items, old_held = server.api_queue, server.work.items, server.work._held_back
    server.api_queue = lambda **kwargs: queue
    server.work.items = lambda **kwargs: fixtures
    server.work._held_back = lambda item: item["id"] == "w-held"
    try:
        got = server.waiting_on_you()
        ids = {row["source_id"] for row in got["ready"]}
        check(ids == {"q-ready", "q-returned", "w-ready", "w-approval", "w-explicit-verdict"},
              "prepared decisions, returned decisions, reviews, approvals and explicit verdicts share one ready set")
        check(got["count"] == 5 and got["counts"] == {"total": 5, "work": 3, "decisions": 2},
              "the total and its split are derived from that set")
        reading = server.waiting_reading()
        dashboard = server.waiting_block()
        check(reading["count"] == dashboard["count"] == len(ids),
              "dashboard and navigation totals match the ready IDs shown by the queue")
        states = {row["source_id"]: row["status"] for row in got["items"]}
        preparation = {row["source_id"]: row.get("preparation") for row in got["items"]}
        for card_id, code in (("w-no-question", "question"),
                              ("w-no-recommendation", "recommendation"),
                              ("w-no-recommendation-explanation", "recommendation_explanation")):
            check(preparation[card_id]["missing"] == [code] and card_id not in ids,
                  f"{code} has its own preparation gap and cannot enter the ready queue")
        check(preparation["w-no-deliverable"]["missing"] == ["deliverable", "evidence"],
              "a work card without its named deliverable stays out of the ready queue")
        check(preparation["w-no-evidence"]["missing"] == ["evidence"],
              "a named deliverable needs inspectable evidence")
        check(preparation["w-no-consequences"]["missing"] == ["consequences"],
              "a review records what Daniel's answer does next")
        check(preparation["w-explicit-verdict"]["ready"],
              "a finished result can ask for an informed verdict without a fabricated recommendation")
        check(states["q-studio"] == "awaiting_owner_reply" and states["w-reply"] == "awaiting_owner_reply",
              "send-backs stay with the studio until an owner returns them")
        check(states["w-held"] == "verification_pending", "held patches await verification")
        check(states["w-preparing"] == states["w-doing"] == "preparing", "unfinished work is preparing")
        check(states["w-scheduled"] == "scheduled" and states["w-accepted"] == "closed", "queued work is scheduled; acceptance is recorded separately")
        check(states["w-reading"] == states["w-green"] == "ready_to_apply", "readings and green reversible work await completion, not landed")
        check(states["w-failed"] == states["w-old"] == "verification_pending", "failed checks and old completion claims need verification")
        check(states["w-risky"] == "preparing" and states["w-unknown"] == "unknown", "risky follow-ups and unknown states cannot imply completion")
        check(states["w-landed"] == "completed", "green tests do not replace recorded landing")

        before = repr((queue, fixtures))
        server.waiting_on_you()
        check(repr((queue, fixtures)) == before, "reading the projection changes no records")

        static = os.path.join(os.path.dirname(HERE), "static")
        with open(os.path.join(static, "app.js"), encoding="utf-8") as f:
            app_js = f.read()
        with open(os.path.join(static, "queue.js"), encoding="utf-8") as f:
            queue_js = f.read()
        with open(os.path.join(static, "work.js"), encoding="utf-8") as f:
            work_js = f.read()
        check("/api/waiting-on-you" in app_js and "/api/waiting-on-you" in queue_js
              and "/api/waiting-on-you" in work_js,
              "navigation and both queue readers consume the shared API")

        server.work.items = lambda **kwargs: (_ for _ in ()).throw(OSError("unreadable"))
        unavailable = server.waiting_on_you()
        check(unavailable["available"] is False and unavailable["count"] is None,
              "an unavailable work reading is not reported as zero")
    finally:
        server.api_queue, server.work.items, server.work._held_back = old_queue, old_items, old_held

    concrete = {"title": "Fix the preview", "owner": "rin",
                "first_action": "Render the revised animation at game size", "tier": 1}
    for field, value in (("follow_ups", []), ("follow_ups", [concrete]), ("follow_up", concrete)):
        sample = card("w-valid-consequence", "for_review")
        sample.pop("follow_ups")
        sample[field] = value
        check(server.work_preparation(sample)["ready"],
              f"{field} accepts concrete next work or canonical explicit no-work")
    for field in ("follow_ups", "follow_up"):
        malformed = [None, "", " ", {}, False, 0, "NONE", [None], [""], [{}],
                     {"title": "Incomplete"}, [concrete, None],
                     {**concrete, "first_action": " "}, {**concrete, "tier": "1"}]
        if field == "follow_up":
            malformed.append([])
        else:
            malformed.extend([concrete, [{**concrete, "title": {}}], [{**concrete, "owner": ""}]])
        for value in malformed:
            sample = card("w-bad-consequence", "for_review")
            sample.pop("follow_ups")
            sample[field] = value
            check(server.work_preparation(sample)["missing"] == ["consequences"],
                  f"{field} rejects malformed consequence {value!r}")
            with patch.object(server, "api_queue", return_value={"curated": [], "rulings": {}, "decided": []}), \
                 patch.object(server.work, "items", return_value=[sample]):
                projected = server.waiting_on_you()
            check(projected["available"] and projected["count"] == 0
                  and projected["items"][0]["preparation"]["missing"] == ["consequences"],
                  "malformed consequences stay visible as preparation gaps, not ready work")
    sample = card("w-conflicting-consequence", "for_review", follow_up=None)
    check(server.work_preparation(sample)["missing"] == ["consequences"],
          "an explicit empty list does not mask a malformed singular consequence")

    # Exercise production readers rather than replacing them with throwing stubs.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for directory in ("work", "decisions", "rulings"):
            (root / directory).mkdir()
        good = card("w-good", "for_review")
        (root / "work" / "good.json").write_text(json.dumps(good))
        (root / "decisions" / "q.json").write_text(json.dumps({"id": "Q-1"}))
        (root / "rulings" / "q.json").write_text(json.dumps({"id": "Q-1", "option": "yes"}))
        with patch.object(server, "DATA", tmp), patch.object(server.work, "WORK", str(root / "work")), \
             patch.object(server.work, "HOST", server), patch.object(server, "parse_queue", side_effect=OSError("raw Markdown unavailable")):
            check(server.waiting_on_you()["count"] == 1, "real complete readers exclude a settled decision")
            for directory in ("work", "decisions", "rulings"):
                bad = root / directory / "bad.json"
                bad.write_text("{invalid json")
                got = server.waiting_on_you()
                check(got["available"] is False and got["count"] is None,
                      f"malformed {directory} record makes the complete reading unavailable")
                if directory == "work":
                    check(len(server.work.items()) == 1, "legacy work reader still exposes the valid record")
                bad.unlink()
                folder = root / directory
                absent = root / (directory + "-saved")
                folder.rename(absent)
                got = server.waiting_on_you()
                check(got["available"] is False and got["count"] is None,
                      f"missing {directory} directory cannot publish a partial count")
                folder.write_text("not a directory")
                check(server.waiting_on_you()["available"] is False,
                      f"a file replacing {directory} is unavailable")
                folder.unlink()
                absent.rename(folder)
                listdir = os.listdir
                def denied(path, blocked=str(folder)):
                    if str(path) == blocked:
                        raise PermissionError("fixture denies the required directory")
                    return listdir(path)
                with patch("os.listdir", side_effect=denied):
                    check(server.waiting_on_you()["available"] is False,
                          f"unreadable {directory} directory is unavailable")
            (root / "work" / "bad.json").write_text(json.dumps({
                "id": "w-nested", "state": "for_review", "diff": "not a mapping"}))
            check(server.waiting_on_you()["available"] is False,
                  "invalid nested work data is caught inside the availability boundary")
            (root / "work" / "bad.json").unlink()
            (root / "decisions" / "bad.json").write_text(json.dumps({
                "id": "Q-2", "replies": [None]}))
            (root / "rulings" / "bad.json").write_text(json.dumps({
                "id": "Q-2", "judgment": "revise", "ruled_at": "2026-09-21"}))
            check(server.waiting_on_you()["available"] is False,
                  "invalid nested decision data is caught inside the availability boundary")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

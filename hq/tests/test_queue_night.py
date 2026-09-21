#!/usr/bin/env python3
"""One reading of Daniel's queue a night, and never two.

The goal in hq/data/goals/executive.json is that nothing waits on him
overnight. A goal measured only when somebody opens the page has no history,
so HQ writes the evening's reading to hq/data/history/queue.jsonl and the
burn-down becomes a record on disk.

The recorder wakes every quarter of an hour, which means it finds that it has
already written far more often than it writes. Three rules are checked here,
against a temporary history folder with no model and no dashboard in the loop:
it writes nothing before nine in the evening, it writes once after nine, and a
second wake-up the same night adds no second line.

    python3 hq/tests/test_queue_night.py
"""
import datetime
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HQ = os.path.dirname(HERE)
sys.path.insert(0, HQ)

import server  # noqa: E402

FAILS = []


def check(ok, what):
    print(f"  {'ok  ' if ok else 'FAIL'}    {what}")
    if not ok:
        FAILS.append(what)


def lines():
    path = os.path.join(server.HISTORY, "queue.jsonl")
    if not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def main():
    tmp = tempfile.mkdtemp(prefix="queue-night-")
    real = server.HISTORY
    server.HISTORY = os.path.join(tmp, "history")
    # A fixed reading, so the test is about when a line is written rather than
    # about what the queue happened to hold while it ran.
    server.waiting_reading = lambda: {"count": 7, "work": 5, "decisions": 2,
                                      "oldest_days": 16}
    try:
        day = datetime.datetime(2026, 9, 21)

        print("Before nine in the evening")
        server.record_queue_night(day.replace(hour=20, minute=59))
        check(lines() == [], "nothing is written during the day")

        print("After nine")
        wrote = server.record_queue_night(day.replace(hour=21, minute=0))
        rows = lines()
        check(wrote is not None and len(rows) == 1, "the evening's reading is written once")
        r = rows[0] if rows else {}
        check(r.get("count") == 7 and r.get("work") == 5 and r.get("decisions") == 2,
              "the line carries the count and what the count is made of")
        check(r.get("oldest_days") == 16, "the line carries how long the oldest has waited")
        check(r.get("target") == 0, "the line carries the target it is read against")
        check(r.get("night") == "2026-09-21", "the line names the night it is for")

        print("Later the same night")
        again = server.record_queue_night(day.replace(hour=23, minute=45))
        check(again is None and len(lines()) == 1, "a second wake-up adds no second line")

        print("The next evening")
        server.record_queue_night(day.replace(day=22, hour=21))
        rows = lines()
        check(len(rows) == 2 and rows[1].get("night") == "2026-09-22",
              "a new night is written on its own line")

        print("Reading the record back")
        nights = server.queue_nights()
        check(len(nights) == 2 and nights[0]["count"] == 7,
              "the oldest evening on file is the one the dashboard compares against")
    finally:
        server.HISTORY = real
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if FAILS:
        print(f"FAILED ({len(FAILS)}):")
        for f in FAILS:
            print("  - " + f)
        return 1
    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

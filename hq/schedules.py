"""Recurring studio duties enter the work queue on their own schedule (Q-134).

Daniel's ruling, 2026-09-29: scheduled processes are added to the queue at their
regular intervals and at their regular priority, and an empty queue is left
empty — nothing is filed to use up spare allowance. hq/data/schedules.json
lists the duties; each drain run calls file_due(), which files one card per duty
that has come due.

A duty is due when its last card was filed at least `every_days` ago, or it has
never been filed. It is skipped while its last card is still open (a slow duty
must not stack copies of itself), while the route it `follows` is parked in
surface.json (the function is switched off, so its duties are too), and while it
carries an `off` reason.
"""
import time

import work

PRIORITY_FLAGS = {"urgent": {"urgent": True}, "retry": {"resume": True}, "ordinary": {}}


def source_ref(entry):
    return "schedule:" + entry["id"]


def _parked(route, parked):
    return any(route == p or route.startswith(p.rstrip("/") + "/") for p in parked)


def due(entries, items, parked, now=None):
    """The entries to file now, each with the reason others were skipped.

    Pure: returns (due_entries, skipped) where skipped maps id -> reason."""
    instant = time.time() if now is None else float(now)
    filed = {}
    for item in items:
        ref = item.get("source_ref") or ""
        if ref.startswith("schedule:"):
            filed.setdefault(ref, []).append(item)
    out, skipped = [], {}
    for entry in entries:
        if entry.get("off"):
            skipped[entry["id"]] = entry["off"]
            continue
        if entry.get("follows") and _parked(entry["follows"], parked):
            skipped[entry["id"]] = entry["follows"] + " is switched off"
            continue
        earlier = sorted(filed.get(source_ref(entry), []), key=lambda i: float(i.get("created_ts") or 0))
        if earlier:
            last = earlier[-1]
            if last.get("state") not in work.FINAL_STATES:
                skipped[entry["id"]] = "its last card " + last["id"] + " is still open"
                continue
            if instant - float(last.get("created_ts") or 0) < float(entry["every_days"]) * 86400:
                skipped[entry["id"]] = "not due yet"
                continue
        out.append(entry)
    return out, skipped


def file_entry(entry, org):
    fields = {"title": entry["title"], "level": "task", "owner": entry["owner"],
              "tier": int(entry.get("tier", 1)),
              "tier_reason": "A recurring duty from the seat's charter, filed on its schedule (Q-134).",
              "ask": entry["ask"], "first_action": entry.get("first_action") or ""}
    item = work._file_item(fields, {"to": entry["owner"], "message": entry["ask"]}, org)
    item["source"] = "schedule"
    item["source_ref"] = source_ref(entry)
    item.update(PRIORITY_FLAGS.get(entry.get("priority") or "ordinary", {}))
    return work.save_item(item)


def file_due(schedule_doc, parked, org, now=None):
    """File every due duty. Returns the new cards."""
    entries = (schedule_doc or {}).get("schedules") or []
    with work.mutation_lock():
        ready, _skipped = due(entries, work.items(), parked, now)
        return [file_entry(entry, org) for entry in ready]

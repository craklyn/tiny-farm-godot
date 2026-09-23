"""Dispatch durable workflow actions through the existing verified drain lane.

The drain process lock is the single writer and limits model work to one card at
a time. The action claim survives a process crash; a later tick may reclaim it
only after its lease expires and transaction recovery has run.
"""
import time
import uuid
import json
import subprocess


MODEL_ACTIONS = frozenset(("build", "reconcile"))
RECOVERY_ACTIONS = frozenset(("recover",))
LEASE_SECONDS = 6 * 60 * 60


def choose(drain, *, include_thinking=False, ids=(), limit=0):
    """Select the same projected actions the Queue shows, with bounded WIP."""
    wanted = set(ids)
    selected = []
    for item, action in drain.classified_actions(include_thinking):
        if wanted and item["id"] not in wanted:
            continue
        if action["type"] not in MODEL_ACTIONS | RECOVERY_ACTIONS:
            continue
        selected.append((item, action))
        if limit and len(selected) >= limit:
            break
    return selected


def claim(work, item, action, run_id):
    """Materialize a virtual action once, then atomically acquire its lease."""
    if action.get("virtual"):
        persisted = work.ensure_action(
            item, action["type"], input_id=action.get("input_id", ""),
            owner=action.get("owner"), summary=action.get("summary", ""),
            priority=action.get("priority", "ordinary"),
            created_at=action.get("created_at") or None)
        if persisted["id"] != action["id"]:
            raise RuntimeError("The projected action changed before it was claimed")
    claim_id = f"{run_id}:{uuid.uuid4().hex}"
    claimed = work.claim_action(item, action["id"], claim_id,
                                lease_seconds=LEASE_SECONDS)
    return claim_id if claimed else ""


def recover_orphaned_claims(work):
    """Called only while holding the drain process lock, after tx recovery.

    A dead process cannot retain the six-hour lease. If transaction recovery
    already recorded an outcome, close its action; otherwise reopen it once.
    """
    recovered = 0
    for item in work.items():
        actions = (item.get("workflow") or {}).get("actions") or []
        orphaned = [a for a in actions if a.get("state") == "running" and
                    (a.get("claim") or {}).get("id", "").count(":") == 1]
        if not orphaned:
            continue
        with work.mutation_lock():
            fresh = work.load_item(item["id"])
            changed = False
            for action in (fresh.get("workflow") or {}).get("actions") or []:
                claim = action.get("claim") or {}
                if action.get("state") != "running" or claim.get("id", "").count(":") != 1:
                    continue
                finished = work._iso_seconds(fresh.get("finished"))
                advanced = fresh.get("state") in work.TERMINAL_STATES or \
                    finished > claim.get("claimed_at", 0)
                action["state"] = "done" if advanced else "open"
                action.pop("claim", None)
                action["updated_at"] = work._now_iso()
                changed = True
                recovered += 1
            if changed:
                work.save_item(fresh)
    return recovered


def reconcile_brief(action, blocker):
    """Give the owner the actual recovery task and its immutable input."""
    kind = action.get("type")
    if kind == "rebrief":
        return ("\n\nACTION TO COMPLETE: Rewrite this work into a smaller bounded brief. "
                "Record the new scope on the card; do not retry the same expensive build.\n")
    if kind != "reconcile":
        return ""
    files = ", ".join((blocker or {}).get("files") or []) or "the candidate files"
    return ("\n\nRECOVERY ACTION: Reconcile the saved candidate with current local main. "
            f"The prior result is held because: {(blocker or {}).get('reason') or action.get('summary')}. "
            f"Inspect {files} and the prior patch and worklog. Reuse sound work, repair conflicts "
            "or missing evidence, and produce a NEW completed owner result. The previous "
            "checker verdict and tests cannot verify a changed tree; the drain will obtain "
            "a fresh checker verdict and run tests on the new candidate.\n")


def finish(work, item, action, claim_id, *, progressed, reason=""):
    """Close only a progressed action; leave a concrete wake for failed dispatch."""
    fresh = work.load_item(item["id"])
    current = next((a for a in (fresh.get("workflow") or {}).get("actions", [])
                    if a.get("id") == action["id"]), None)
    if current is None or current.get("state") == "done":
        return fresh
    if not progressed:
        # A failed launch must not immediately spin on the next timer tick.
        work.finish_action(fresh, action["id"], claim_id, state="blocked")
        work.ensure_blocker(fresh, "tooling", input_id=action["id"], owner="claude",
                            reason=reason or "The action did not start; inspect its execution record.",
                            action_id=action["id"], wake="operator review")
        return fresh
    work.finish_action(fresh, action["id"], claim_id)
    return fresh


def record_ci(work, item, run, *, now=None, provider_available=True):
    """Accept only a completed tests run whose head SHA is this landed commit."""
    sha = ((item.get("completion") or {}).get("sha") or
           (item.get("landed") or {}).get("sha") or "")
    if not sha:
        return False
    if run and (run.get("headSha") != sha or run.get("status") != "completed"):
        return False
    instant = time.time() if now is None else now
    with work.mutation_lock():
        fresh = work.load_item(item["id"])
        workflow = work._workflow(fresh)
        old = workflow.get("ci") or {}
        if run:
            ci = {"status": "confirmed" if run.get("conclusion") == "success" else "failed",
                  "confirmed": run.get("conclusion") == "success", "commit_sha": sha,
                  "run_id": run.get("databaseId"), "url": run.get("url", ""),
                  "conclusion": run.get("conclusion"), "observed_at": work._now_iso()}
            if not ci["confirmed"]:
                ci["next_poll_after"] = instant + 20 * 60
        else:
            ci = {"status": "unavailable", "confirmed": False, "commit_sha": sha,
                  "reason": ("No completed tests workflow run matches this local commit."
                             if provider_available else "The tests workflow could not be read."),
                  "next_poll_after": instant + 20 * 60}
        if old.get("commit_sha") == sha and old.get("status") == ci["status"] and \
                old.get("reason") == ci.get("reason") and \
                (not run or old.get("run_id") == ci.get("run_id")):
            return False
        workflow["ci"] = ci
        poll_id = work.action_key(fresh["id"], "poll_ci", sha)
        poll = next((a for a in workflow["actions"] if a.get("id") == poll_id), None)
        if poll is None:
            poll = {"id": poll_id, "type": "poll_ci", "input_id": sha,
                    "owner": "claude", "summary": "Check the tests workflow for this exact commit.",
                    "priority": "ordinary", "created_at": work._now_iso(), "state": "open"}
            workflow["actions"].append(poll)
        if ci["confirmed"]:
            poll["state"] = "done"
            poll["finished_at"] = work._now_iso()
            poll.pop("wake", None)
        else:
            poll["state"] = "open"
            poll["wake"] = "a later successful run for this commit or the next scheduled CI poll"
        work.save_item(fresh)
        return True


def poll_ci(work, items, fetch_runs, *, now=None):
    """One bounded batch poll, with exact-SHA matching and no guessed green."""
    pending = [i for i in items if i.get("state") == "landed" and
               ((i.get("completion") or {}).get("sha") or (i.get("landed") or {}).get("sha"))]
    if not pending:
        return 0
    runs = fetch_runs()
    provider_available = runs is not None
    runs = runs or []
    changed = 0
    instant = time.time() if now is None else now
    for item in pending:
        sha = ((item.get("completion") or {}).get("sha") or
               (item.get("landed") or {}).get("sha"))
        ci = (item.get("workflow") or {}).get("ci") or {}
        if ci.get("commit_sha") == sha and ci.get("status") == "confirmed":
            continue
        if ci.get("commit_sha") == sha and ci.get("status") in ("unavailable", "failed") \
                and ci.get("next_poll_after", 0) > instant:
            continue
        matching = [r for r in runs if r.get("headSha") == sha and
                    r.get("status") == "completed"]
        matched = max(matching, key=lambda r: (str(r.get("updatedAt") or ""),
                                               int(r.get("databaseId") or 0)), default=None)
        changed += bool(record_ci(work, item, matched, now=instant,
                                  provider_available=provider_available))
    return changed


def fetch_tests_runs():
    """Fetch recent main workflow runs; a failed fetch is unavailable evidence."""
    try:
        done = subprocess.run(
            ["gh", "run", "list", "--branch", "main", "--workflow", "tests.yml",
             "--limit", "30", "--json",
             "headSha,status,conclusion,databaseId,url,updatedAt"],
            capture_output=True, text=True, timeout=20)
        rows = json.loads(done.stdout) if done.returncode == 0 else None
        return rows if isinstance(rows, list) else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None

"""Close a work card with evidence, and mark one as being worked from outside HQ.

Q-125 (a), ruled 2026-09-25: workers never edit card files.  When work lands
they call one HQ command, which closes the card with its evidence — the commit
on main and the automated check that ran on it.  Before this, a session closed
cards by editing main's tracked copy, which HQ never read, so finished work
kept showing as unfinished; then the chief of staff closed 23 of them by hand
with a one-off script.  This module is that script made permanent and strict:

* the commit must exist and be an ancestor of ``origin/main`` (fetched first);
* the CI run must be the ``tests`` workflow, completed with conclusion
  ``success``, on that commit or a later main that contains it — read from
  GitHub, never taken from the caller's word;
* a result text and an attribution are required, and the attribution may not
  claim Daniel or a checker: the card records that neither approved it.

``claim``/``release`` let a session that HQ did not launch say it is working a
card, so the queue shows it under "working" instead of "next".  A claim is a
lease: it lapses on its own when the session stops renewing it.

Everything here mutates cards under ``work.mutation_lock`` and is reached from
the HQ API (``/api/work/close``, ``/api/work/claim``, ``/api/work/release``) and
the ``hq/card.py`` command, which calls that API.
"""

import datetime
import json
import os
import re
import subprocess
import time

import work

CI_WORKFLOW = "tests"
CLAIM_DEFAULT_SECONDS = 2 * 60 * 60
CLAIM_MAX_SECONDS = 12 * 60 * 60
CLOSED = ("landed", "accepted", "dropped", "done")
_SHA = re.compile(r"[0-9a-f]{7,40}")
# The attribution names who closed the card.  It must not borrow the authority
# of a review that did not happen.
_BORROWED = re.compile(r"\b(daniel|ceo|checker)\b", re.I)


class Refused(ValueError):
    """The close or claim was refused; the message says what evidence is missing."""


def _run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=60)


def verify_commit(sha, main_root, *, run=_run, fetch=True):
    """The full SHA of ``sha`` if it is on origin/main; otherwise Refused."""
    sha = str(sha or "").strip().lower()
    if not _SHA.fullmatch(sha):
        raise Refused("Give the commit that landed the work (a hexadecimal SHA).")
    if fetch:
        got = run(["git", "fetch", "--quiet", "origin", "main"], main_root)
        if got.returncode:
            raise Refused("Could not fetch origin/main to check the commit: "
                          + (got.stderr or got.stdout).strip()[:300])
    full = run(["git", "rev-parse", "--verify", "--quiet", sha + "^{commit}"], main_root)
    if full.returncode or not full.stdout.strip():
        raise Refused(f"Commit {sha} does not exist in this repository.")
    full_sha = full.stdout.strip()
    on_main = run(["git", "merge-base", "--is-ancestor", full_sha, "origin/main"], main_root)
    if on_main.returncode:
        raise Refused(f"Commit {full_sha[:12]} is not on origin/main; push it before closing the card.")
    return full_sha


def verify_ci(run_id, sha, main_root, *, run=_run):
    """GitHub's own record of the run, if it passed on ``sha`` or a later main."""
    run_id = str(run_id or "").strip()
    if not run_id.isdigit():
        raise Refused("Give the CI run id of the tests workflow that ran on the commit.")
    got = run(["gh", "run", "view", run_id, "--json",
               "status,conclusion,headSha,workflowName,url,event,headBranch"], main_root)
    if got.returncode:
        raise Refused(f"Could not read CI run {run_id} from GitHub: "
                      + (got.stderr or got.stdout).strip()[:300])
    try:
        doc = json.loads(got.stdout)
    except ValueError:
        raise Refused(f"GitHub returned an unreadable record for CI run {run_id}.")
    if doc.get("workflowName") != CI_WORKFLOW:
        raise Refused(f"CI run {run_id} is the '{doc.get('workflowName')}' workflow, "
                      f"not '{CI_WORKFLOW}'.")
    if doc.get("status") != "completed":
        raise Refused(f"CI run {run_id} has not finished (status {doc.get('status')}).")
    if doc.get("conclusion") != "success":
        raise Refused(f"CI run {run_id} concluded {doc.get('conclusion') or 'nothing'}, not success.")
    head = str(doc.get("headSha") or "")
    if head != sha:
        covers = run(["git", "merge-base", "--is-ancestor", sha, head], main_root)
        if not head or covers.returncode:
            raise Refused(f"CI run {run_id} tested {head[:12] or 'no commit'}, "
                          f"which does not contain {sha[:12]}.")
    return {"id": run_id, "workflow": doc["workflowName"], "status": doc["status"],
            "conclusion": doc["conclusion"], "head_sha": head, "url": doc.get("url", "")}


def _attribution(by):
    by = " ".join(str(by or "").split())
    if len(by) < 3:
        raise Refused("Say who is closing the card (for example 'Codex session' or "
                      "'Claude chief-of-staff session').")
    if _BORROWED.search(by):
        raise Refused("The attribution names who closed the card; it may not claim Daniel "
                      "or a checker, because neither reviewed this close.")
    return by[:160]


def _mark_ruling_integrated(item, sha):
    """An 'integrate ruling' card closing is what integrates the ruling."""
    ruling_id = item.get("ruling_id")
    if not ruling_id:
        return
    path = os.path.join(work.HOST.DATA, "rulings", f"{ruling_id}.json")
    try:
        with open(path, encoding="utf-8") as fh:
            ruling = json.load(fh)
    except (OSError, ValueError):
        return
    if ruling.get("status") == "integrated":
        return
    ruling["status"] = "integrated"
    ruling["integrated"] = {"at": work._now_iso(), "work_id": item["id"], "sha": sha}
    work._write_json(path, ruling)


def close(item_id, *, sha, ci_run, result, by, note="", main_root, run=_run, fetch=True):
    """Land one card with verified evidence.  Returns the saved card."""
    result = str(result or "").strip()
    if len(result) < 20:
        raise Refused("Write the result: what changed, in a few plain sentences.")
    by = _attribution(by)
    full_sha = verify_commit(sha, main_root, run=run, fetch=fetch)
    ci = verify_ci(ci_run, full_sha, main_root, run=run)
    with work.mutation_lock():
        try:
            item = work.load_item(item_id)
        except (OSError, ValueError):
            raise Refused(f"There is no work card {item_id}.")
        if item.get("state") in CLOSED:
            raise Refused(f"Work card {item_id} is already {item['state']}.")
        at = work._now_iso()
        limitations = ("Closed from a session with commit and CI evidence; "
                       "no checker or Daniel approval was recorded for this card.")
        summary = str(note or "").strip() or result.split("\n", 1)[0][:200]
        evidence = {"version": 1, "at": at, "by": by, "evidence_commits": [full_sha],
                    "ci_run": ci, "evidence_summary": summary, "limitations": limitations}
        attempt_id = f"session-close-{item_id}-{full_sha[:7]}"
        item["result"] = result
        item["attempt_outcome"] = {"version": 1, "id": attempt_id, "status": "complete",
                                   "reason": summary, "result_id": work.evidence_id(result),
                                   "landing_verified": True, "session_close": evidence}
        item["completion"] = {"version": 1, "attempt_id": attempt_id, "at": at,
                              "sha": full_sha, "by": by, "kind": "session_close",
                              "evidence": evidence}
        # Follow-ups are filed by the session as their own cards, not parsed from prose.
        item["pending_followups"] = {"version": 1, "attempt_id": attempt_id, "items": []}
        item.pop("outside_claim", None)
        work.save_item(item)
        landed = work.land_item(item, by, sha=full_sha, note=summary)
        _mark_ruling_integrated(landed, full_sha)
        return landed


def _now():
    return time.time()


def claim(item_id, *, by, seconds=CLAIM_DEFAULT_SECONDS, now=None):
    """Mark a card as worked by an outside session until the lease lapses.

    Claiming again with the same attribution renews the lease (the heartbeat);
    a live claim held by someone else is refused, an expired one is replaced.
    """
    by = _attribution(by)
    try:
        seconds = int(seconds)
    except (TypeError, ValueError):
        raise Refused("The claim length must be a whole number of seconds.")
    if not 60 <= seconds <= CLAIM_MAX_SECONDS:
        raise Refused(f"A claim lasts between 60 and {CLAIM_MAX_SECONDS} seconds.")
    instant = _now() if now is None else float(now)
    with work.mutation_lock():
        try:
            item = work.load_item(item_id)
        except (OSError, ValueError):
            raise Refused(f"There is no work card {item_id}.")
        if item.get("state") in CLOSED:
            raise Refused(f"Work card {item_id} is already {item['state']}.")
        held = item.get("outside_claim") or {}
        if held and held.get("by") != by and float(held.get("expires_ts") or 0) > instant:
            raise Refused(f"Work card {item_id} is being worked by {held.get('by')} "
                          f"until {held.get('expires')}.")
        since = held.get("since") if held.get("by") == by and float(
            held.get("expires_ts") or 0) > instant else None
        stamp = lambda ts: datetime.datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds")
        item["outside_claim"] = {"by": by, "since": since or stamp(instant),
                                 "heartbeat": stamp(instant),
                                 "expires": stamp(instant + seconds),
                                 "expires_ts": instant + seconds}
        return work.save_item(item)


def release(item_id, *, by, now=None):
    """Give a claim back.  Only its holder can, and a lapsed claim is simply cleared."""
    by = _attribution(by)
    with work.mutation_lock():
        try:
            item = work.load_item(item_id)
        except (OSError, ValueError):
            raise Refused(f"There is no work card {item_id}.")
        held = item.get("outside_claim")
        if not held:
            return item
        instant = _now() if now is None else float(now)
        if held.get("by") != by and float(held.get("expires_ts") or 0) > instant:
            raise Refused(f"Work card {item_id} is claimed by {held.get('by')}, not {by}.")
        item.pop("outside_claim", None)
        return work.save_item(item)


def live_claim(item, now=None):
    """The outside claim if it has not lapsed, else None.  Pure; used by the queue view."""
    held = item.get("outside_claim")
    if not isinstance(held, dict):
        return None
    instant = _now() if now is None else float(now)
    try:
        return held if float(held.get("expires_ts") or 0) > instant else None
    except (TypeError, ValueError):
        return None

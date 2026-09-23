"""Validate and attach durable verification of one held candidate."""

import hashlib
import json
import os
import re

import work

RESULT = re.compile(r"Results:\s*(\d+) PASSED,\s*(\d+) FAILED")
_CARD = re.compile(r"w[a-zA-Z0-9]+\Z")
_HASH = re.compile(r"[0-9a-f]{64}\Z")


def _inside(root, path):
    root = os.path.realpath(root)
    path = os.path.realpath(path)
    if os.path.commonpath((root, path)) != root:
        raise ValueError("verification path is outside the evidence store")
    return path


def _read_log(path, assertion):
    with open(path, "rb") as source:
        raw = source.read()
    output = raw.decode("utf-8")
    matches = list(RESULT.finditer(output))
    complete = len(matches) == 1
    lines = output[:matches[0].start()].splitlines() if complete else []
    marked = [line for line in lines if assertion in line]
    failures = [line for line in marked if "FAIL:" in line]
    passes = [line for line in marked if re.search(r"^\s*[✓✔]\s", line)]
    return hashlib.sha256(raw).hexdigest(), matches, (
        "fail" if failures and not passes else
        "pass" if len(passes) == 1 and not failures else "unknown")


def validate(item, path, data_root):
    """Return a small trusted summary; reject stale identity or changed results."""
    card = item.get("id")
    if not isinstance(card, str) or not _CARD.fullmatch(card):
        raise ValueError("invalid work card")
    root = os.path.join(data_root, "runs", "verification")
    path = _inside(root, os.path.join(data_root, path) if not os.path.isabs(path) else path)
    if os.path.basename(path) != "evidence.json" or not os.path.basename(os.path.dirname(path)).startswith(card + "-"):
        raise ValueError("invalid verification manifest path")
    with open(path, encoding="utf-8") as source:
        manifest = json.load(source)
    outcome = item.get("attempt_outcome") or {}
    candidate = outcome.get("candidate") or {}
    identity = (card, item.get("last_recorded_attempt"), candidate.get("base"),
                candidate.get("tree"), outcome.get("patch_id"))
    recorded = tuple(manifest.get(key) for key in
                     ("card", "attempt", "base", "candidate_tree", "patch_id"))
    if not all(identity) or recorded != identity or item.get("diff", {}).get("applied"):
        raise ValueError("verification belongs to another attempt or candidate")
    patch_path = os.path.join(data_root, "patches", card + ".patch")
    with open(patch_path, encoding="utf-8") as source:
        if work.evidence_id(source.read()) != outcome["patch_id"]:
            raise ValueError("held patch changed")
    assertion = manifest.get("assertion")
    requested = manifest.get("requested_runs")
    rows = manifest.get("runs")
    if (not isinstance(assertion, str) or not assertion or len(assertion) > 300 or
            type(requested) is not int or not 1 <= requested <= 100 or
            not isinstance(rows, list) or len(rows) > requested):
        raise ValueError("invalid verification manifest")
    if any(not isinstance(row, dict) or row.get("number") != i for i, row in enumerate(rows, 1)):
        raise ValueError("invalid verification run order")
    completed = passes = failures = passing_suites = passing_assertions = 0
    for i, row in enumerate(rows, 1):
        name = f"run-{i:02d}.log"
        if row.get("log") != name or not _HASH.fullmatch(str(row.get("log_sha256") or "")):
            raise ValueError("verification log identity missing")
        digest, matches, assertion_result = _read_log(_inside(os.path.dirname(path), os.path.join(os.path.dirname(path), name)), assertion)
        code = row.get("exit_code")
        is_complete = len(matches) == 1 and type(code) is int and code in (0, 1)
        expected = {"number": i, "exit_code": code, "completed": is_complete,
                    "passed": int(matches[0].group(1)) if is_complete else None,
                    "failed": int(matches[0].group(2)) if is_complete else None,
                    "assertion": assertion_result if is_complete else "unknown",
                    "log": name, "log_sha256": digest}
        if row != expected:
            raise ValueError("verification log and result differ")
        completed += int(is_complete)
        passes += int(is_complete and assertion_result == "pass")
        failures += int(is_complete and assertion_result == "fail")
        passing_suites += int(is_complete and code == 0 and expected["failed"] == 0)
        passing_assertions += int(is_complete and code == 0 and expected["failed"] == 0 and assertion_result == "pass")
    if (manifest.get("completed_runs") != completed or
            manifest.get("assertion_passes") != passes or
            manifest.get("assertion_failures") != failures):
        raise ValueError("verification totals differ from logs")
    if manifest.get("import"):
        imported = manifest["import"]
        name = imported.get("log")
        if name != "import.log" or not _HASH.fullmatch(str(imported.get("log_sha256") or "")):
            raise ValueError("import log identity missing")
        with open(_inside(os.path.dirname(path), os.path.join(os.path.dirname(path), name)), "rb") as source:
            raw = source.read()
        if hashlib.sha256(raw).hexdigest() != imported["log_sha256"] or imported.get("ok") != (imported.get("exit_code") == 0 and b"SCRIPT ERROR:" not in raw):
            raise ValueError("import log and result differ")
    return {"id": work.evidence_id(manifest), "path": os.path.relpath(path, data_root),
            "attempt_id": identity[1], "candidate_tree": identity[3], "patch_id": identity[4],
            "assertion": assertion, "requested_runs": requested, "completed_runs": completed,
            "passing_suites": passing_suites, "assertion_passes": passes,
            "passing_assertions": passing_assertions,
            "assertion_failures": failures, "run_count": len(rows)}


def attach(item, path, data_root):
    """Set the card pointer only after checking the complete manifest."""
    summary = validate(item, path, data_root)
    item["verification_evidence"] = {key: summary[key] for key in
                                     ("path", "id", "attempt_id", "candidate_tree", "patch_id")}
    return summary


def lookup(item, data_root):
    pointer = item.get("verification_evidence") or {}
    if not isinstance(pointer, dict) or not pointer.get("id"):
        return None
    try:
        summary = validate(item, pointer.get("path", ""), data_root)
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        return None
    if any(pointer.get(key) != summary[key] for key in
           ("path", "id", "attempt_id", "candidate_tree", "patch_id")):
        return None
    return summary

"""Private social-video library, immutable publications and cut-specific review.

Curated imports are code-owned. All new decisions live in DATA/social, under a
process and thread lock with revision checks, fsynced replaces and backups.
No media producer or external account is invoked here.
"""
from __future__ import annotations

import contextlib
import copy
import datetime as dt
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
import threading
from urllib.parse import urlsplit
import uuid

HOST = None
_LOCK = threading.RLock()
_HASHES = {}
ID = re.compile(r"[a-z][a-z0-9-]{0,63}\Z")
VERSION = re.compile(r"v([1-9][0-9]{0,5})\Z")
FIELDS = {"title": 160, "promise": 3000, "hook": 2000, "script": 18000,
          "shots": 10000, "source_comment": 4000, "source_url": 2048,
          "ask": 2000, "caption": 4000}
MAX_BODY = 100_000
# The documented tailscale serve endpoint. Forwarded host values are never used.
TRUSTED_PROXY_ORIGINS = {"https://daniel-maco.tail445099.ts.net"}


class SocialError(ValueError):
    def __init__(self, message, status=400, code="invalid"):
        super().__init__(message)
        self.status, self.code = status, code


def bind(server_module):
    global HOST
    HOST = server_module


def _now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def _ident(value):
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise SocialError("Invalid video identifier.")
    return value


def _text(value, field, maximum, required=False):
    if not isinstance(value, str) or len(value) > maximum or "\x00" in value:
        raise SocialError(f"{field} must be text of at most {maximum} characters.")
    value = value.strip()
    if required and not value:
        raise SocialError(f"Enter {field}.")
    return value


def _url(value, *, publication=False, required=False):
    value = _text(value, "URL", 2048, required)
    if not value:
        return ""
    p = urlsplit(value)
    if (p.scheme != "https" or not p.hostname or p.username or p.password
            or any(c.isspace() or ord(c) < 32 for c in value) or "\\" in value):
        raise SocialError("Use an HTTPS URL.")
    try:
        if p.port not in (None, 443):
            raise SocialError("Use a standard HTTPS URL.")
    except ValueError:
        raise SocialError("Invalid URL.")
    if publication:
        host = p.hostname.lower().removeprefix("www.")
        supported = ((host == "tiktok.com" and re.fullmatch(r"/@[^/]+/video/\d+/?", p.path))
                     or (host in ("vm.tiktok.com", "vt.tiktok.com") and re.fullmatch(r"/[A-Za-z0-9]+/?", p.path))
                     or (host == "instagram.com" and re.fullmatch(r"/(?:p|reel)/[A-Za-z0-9_-]+/?", p.path))
                     or (host == "youtube.com" and (re.fullmatch(r"/shorts/[A-Za-z0-9_-]+/?", p.path)
                                                   or (p.path == "/watch" and re.search(r"(?:^|&)v=[A-Za-z0-9_-]+(?:&|$)", p.query))))
                     or (host == "youtu.be" and re.fullmatch(r"/[A-Za-z0-9_-]+/?", p.path)))
        if not supported:
            raise SocialError("Use a TikTok, Instagram or YouTube post URL.")
    return value


def _date(value):
    value = _text(value, "Posting date", 10)
    if value:
        try:
            dt.date.fromisoformat(value)
        except ValueError:
            raise SocialError("Use a real posting date in YYYY-MM-DD form.")
    return value


def _catalog():
    # Configuration is always read beside this implementation, including scratch previews.
    return json.loads((Path(HOST.HQ_DIR) / "data/social_catalog.json").read_text())


def _store():
    return Path(HOST.DATA) / "social"


@contextlib.contextmanager
def _locked():
    with _LOCK:
        directory = _store()
        directory.mkdir(parents=True, exist_ok=True)
        with (directory / ".mutation.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)


def _load(ident):
    ident = _ident(ident)
    path = _store() / (ident + ".json")
    if path.is_file():
        return json.loads(path.read_text())
    for seed in _catalog()["projects"]:
        if seed["id"] == ident:
            return copy.deepcopy({"revision": 0, "notes": [], "approvals": [],
                                  "requests": [], "observations": [], "posting_details": [], **seed})
    raise SocialError("No such video.", 404, "missing")


def _atomic(path, data):
    raw = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode()
    fd, name = tempfile.mkstemp(prefix=".social-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def _save(record):
    path = _store() / (record["id"] + ".json")
    if path.exists():
        old = json.loads(path.read_text())
        backups = _store() / "backups"
        backups.mkdir(exist_ok=True)
        _atomic(backups / f'{record["id"]}-{old["revision"]}.json', old)
    record["revision"] += 1
    record["updated_at"] = _now()
    _atomic(path, record)


def _media_root():
    return Path(os.environ.get("HQ_SOCIAL_MEDIA_ROOT", str(Path(HOST.REPO) / "video"))).resolve()


def _inside(root, relative):
    path = root / relative
    # Reject every symlink, even an in-root one: known filenames must mean the same file.
    cursor = root
    for part in Path(relative).parts:
        if part in (".", "..") or Path(part).is_absolute():
            raise SocialError("Invalid media path.", 403)
        cursor = cursor / part
        if cursor.is_symlink():
            raise SocialError("Media symlinks are unavailable.", 403)
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        raise SocialError("Invalid media path.", 403)
    return path


@contextlib.contextmanager
def _open_known(root, relative):
    """Open every path component without following symlinks, even during a rename."""
    parts = Path(relative).parts
    if not parts or any(p in (".", "..") for p in parts) or Path(relative).is_absolute():
        raise SocialError("Invalid media path.", 403)
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=descriptor)
        with os.fdopen(fd, "rb") as stream:
            yield stream
    except OSError as exc:
        raise SocialError("This media file is unavailable.", 404, "media_missing") from exc
    finally:
        os.close(descriptor)


def _identity(st):
    return st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns


def _hash(path):
    st = path.stat()
    identity = _identity(st)
    hit = _HASHES.get(str(path))
    if hit and hit[0] == identity:
        return hit[1]
    h = hashlib.sha256()
    with _open_known(_media_root(), path.relative_to(_media_root())) as f:
        if identity != _identity(os.fstat(f.fileno())):
            raise SocialError("The cut changed. Refresh it.", 409, "media_changed")
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
        if identity != _identity(os.fstat(f.fileno())):
            raise SocialError("The cut changed while it was being read. Refresh it.", 409, "media_changed")
    _HASHES[str(path)] = (identity, h.hexdigest())
    return h.hexdigest()


def _cuts(record):
    root = _media_root()
    folder, prefix = record["folder"], record["render_prefix"]
    try:
        directory = _inside(root, folder + "/renders")
        if not directory.is_dir():
            return []
        result = []
        for p in directory.iterdir():
            match = re.fullmatch(re.escape(prefix) + r"_v([1-9][0-9]{0,5})\.mp4", p.name)
            if not match:
                continue
            try:
                p = _inside(root, f"{folder}/renders/{p.name}")
                if not p.is_file():
                    continue
                version = "v" + match[1]
                sha = _hash(p)
                subs = p.with_suffix(".en.srt")
                has_subs = subs.is_file() and not subs.is_symlink()
                result.append({"version": version, "number": int(match[1]), "sha256": sha,
                               "bytes": p.stat().st_size, "modified_at": dt.datetime.fromtimestamp(p.stat().st_mtime, dt.timezone.utc).isoformat(),
                               "url": f'/social-media/{record["id"]}/{version}/video?sha256={sha}',
                               "subtitles_url": f'/social-media/{record["id"]}/{version}/subtitles?sha256={sha}' if has_subs else ""})
            except (OSError, SocialError):
                continue
        return sorted(result, key=lambda cut: cut["number"])
    except (OSError, SocialError):
        return []


def _source(record):
    result = []
    for rel in record.get("sources", []):
        try:
            p = _inside(Path(HOST.HQ_DIR).parent, rel)
            if p.is_file() and p.stat().st_size <= 256_000:
                result.append({"path": rel, "text": p.read_text()})
        except (OSError, SocialError, UnicodeError):
            pass
    return result


def _detail(record, *, sources=True):
    result = copy.deepcopy(record)
    cuts = _cuts(record)
    result["cuts"] = cuts
    current = cuts[-1] if cuts else None
    result["current_cut"] = current
    publication = record.get("publication")
    result["published"] = bool(publication)
    result["approved"] = bool(current and any(a["sha256"] == current["sha256"] and a["version"] == current["version"] and not a.get("invalidated_at") for a in record["approvals"]))
    if publication:
        fixed = next((c for c in cuts if c["version"] == publication["version"]
                      and publication.get("sha256") and c["sha256"] == publication["sha256"]), None)
        result["published_cut"] = fixed
        result["status"] = "Published"
        result["next_action"] = "Read audience responses"
    elif current:
        open_notes = _open_notes(record, current)
        result["status"] = "Approved cut" if result["approved"] and not open_notes else "Ready for your review"
        result["next_action"] = "Prepare the post" if result["status"] == "Approved cut" else "Review " + current["version"]
        last_request = next((r for r in reversed(record["requests"]) if r.get("work_id")), None)
        if last_request and last_request["snapshot"].get("cut") and not result["approved"]:
            sent_cut = last_request["snapshot"]["cut"]
            if sent_cut["sha256"] == current["sha256"] and sent_cut["version"] == current["version"]:
                result["status"] = "Revision requested"
                result["next_action"] = "View production request"
        if open_notes and result["status"] != "Revision requested":
            result["next_action"] = f'{len(open_notes)} open review note' + ("s" if len(open_notes) != 1 else "")
    else:
        result["status"] = "Production requested" if any(r.get("work_id") for r in record["requests"]) else "Request not filed" if record["requests"] else "Idea"
        result["next_action"] = "Open production request" if any(r.get("work_id") for r in record["requests"]) else "Retry the saved request" if record["requests"] else "Develop the brief"
    result["output_path"] = f'video/{record["folder"]}/renders/{record["render_prefix"]}_vN.mp4'
    if sources:
        result["source_documents"] = _source(record)
    # A filing receipt is historical; the linked card's current owner and state
    # are read live so later routing cannot leave a stale "actual owner" claim.
    people = {e["id"]: e for e in HOST.load_org().get("employees", [])}
    for request in result["requests"]:
        if request.get("work_id"):
            try:
                item = HOST.work.load_item(request["work_id"])
                owner = item.get("owner", "")
                request.update(work_available=True, work_owner=owner, work_state=item.get("state", ""),
                               work_owner_name=("Chief of Staff" if owner == "claude" else people.get(owner, {}).get("name", owner)))
            except (OSError, ValueError, KeyError):
                request["work_available"] = False
    # Return full production snapshots only in detail; these are the durable brief receipt.
    result["preview"] = os.environ.get("HQ_SOCIAL_PREVIEW") == "1"
    return result


def list_content():
    ids = [r["id"] for r in _catalog()["projects"]]
    if _store().exists():
        ids += [p.stem for p in _store().glob("*.json") if ID.fullmatch(p.stem) and p.stem not in ids]
    with _LOCK:
        return {"projects": [_detail(_load(i), sources=False) for i in ids],
                "preview": os.environ.get("HQ_SOCIAL_PREVIEW") == "1"}


def content_detail(content_id):
    with _LOCK:
        return _detail(_load(content_id))


def _selected(record, payload, *, latest=False, optional=False):
    version, sha = payload.get("version"), payload.get("sha256")
    cuts = _cuts(record)
    if optional and not cuts and version is None and sha is None:
        return None
    cut = next((c for c in cuts if c["version"] == version and c["sha256"] == sha), None)
    if not cut or (latest and cut != cuts[-1]):
        raise SocialError("The cut has changed. Refresh and review the current file.", 409, "media_changed")
    return cut


def _open_notes(record, cut):
    def applies(note):
        if note.get("resolved_at"):
            return False
        if note.get("sha256"):
            return note.get("version") == cut["version"] and note["sha256"] == cut["sha256"]
        return not any(t["source_note_id"] == note["id"] and t["version"] == cut["version"] and t["sha256"] == cut["sha256"] for t in record.get("review_transfers", []))
    return [n for n in record["notes"] if applies(n)]


def _brief(payload, existing=None):
    if not isinstance(payload, dict) or set(payload) - set(FIELDS):
        raise SocialError("Unknown brief fields.")
    result = copy.deepcopy(existing or {})
    for k, v in payload.items():
        result[k] = _text(v, k, FIELDS[k], required=(k == "title"))
        if k == "source_url":
            result[k] = _url(result[k])
    if not result.get("title"):
        raise SocialError("Enter a title.")
    return result


def _request(record, payload):
    key = _text(payload.get("submission_id", ""), "Submission identifier", 100, True)
    if not re.fullmatch(r"[A-Za-z0-9_-]{8,100}", key):
        raise SocialError("Invalid submission identifier.")
    original = {k: v for k, v in payload.items() if k != "revision"}
    previous = next((r for r in record["requests"] if r["submission_id"] == key), None)
    if previous:
        if original != previous["payload"]:
            raise SocialError("This submission was already used. Start a new request.", 409, "conflict")
        if previous.get("work_id"):
            return _detail(record)
        request = previous
    else:
        _check_revision(record, payload)
        cut = _selected(record, payload, optional=True)
        snapshot = {"project_id": record["id"], "brief": copy.deepcopy(record["brief"]), "cut": cut,
                    "notes": copy.deepcopy(record["notes"]), "sources": record.get("sources", []),
                    "folder": f'video/{record["folder"]}/',
                    "output_path": f'video/{record["folder"]}/renders/{record["render_prefix"]}_vN.mp4',
                    "source_project": record.get("source_project", ""), "editing_source": record.get("editing_source"), "workflow": "video/README.md; video-editing skill"}
        digest = hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()
        ident = "social-" + record["id"][:40] + "-" + digest[:32]
        # Same content snapshot deduplicates even if a user double-click creates another key.
        same = next((r for r in record["requests"] if r["request_id"] == ident), None)
        if same:
            if same.get("work_id"):
                return _detail(record)
            request = same
        else:
            words = (f'Produce the next cut: {record["brief"]["title"]}\n'
                     f'Production responsibility: Jordan Lee. Chief of Staff: route this request to Jordan.\n'
                     f'Full saved production brief: HQ #/social/{record["id"]} (request {ident}).\n'
                     f'Durable snapshot: {Path(HOST.DATA) / "social" / (record["id"] + ".json")} → requests[{ident}].snapshot.\n'
                     f'Project source folder: {snapshot["folder"]}\nOutput: {snapshot["output_path"]}\n'
                     f'Cut to revise: {cut["version"] + " SHA-256 " + cut["sha256"] if cut else "No cut yet"}.\n'
                     'Read video/README.md and the video-editing skill. Read the COMPLETE saved snapshot before working: '
                     'it contains the brief, script direction, all review notes and exact source paths. '
                     'Retain earlier renders, document new inputs, and return a numerically versioned cut for Daniel to review. '
                     'Do not change game design or publish externally. Use the recorded editing branch and inputs where supplied; rebuild its generated intermediates before rendering.')
            if len(words) > 4000:
                raise SocialError("The routing request is too long; the saved brief is unchanged.")
            request = {"request_id": ident, "submission_id": key, "payload": original,
                       "snapshot": snapshot, "intake_payload": {"kind": "work", "request_id": ident, "words": words},
                       "created_at": _now(), "state": "Awaiting intake"}
            record["requests"].append(request)
            _save(record)  # Persist exact retry arguments before the external-to-this-record write.
    try:
        result = HOST.work.api_post("/api/work/request", request["intake_payload"])
    except Exception as exc:
        raise SocialError("The production request was saved, but intake failed. Retry to file it once.", 502, "intake_failed") from exc
    if not isinstance(result, dict) or result.get("error") or not result.get("id"):
        raise SocialError("Work intake could not file this request. Retry the saved request.", 502, "intake_failed")
    request.update(work_id=result["id"], owner=result.get("owner", "claude"), state="Filed for routing to Jordan", filed_at=_now())
    _save(record)
    return _detail(record)


def _check_revision(record, payload):
    revision = payload.get("revision")
    if type(revision) is not int or revision != record["revision"]:
        raise SocialError("Someone saved a newer version. Your unsaved text is still here; copy it or reload the latest record.", 409, "conflict")


def mutate(command, payload):
    if command not in {"idea", "save", "note", "resolve", "approve", "publication", "observation", "request"}:
        raise SocialError("Unknown social command.", 404)
    if not isinstance(payload, dict):
        raise SocialError("Expected a JSON object.")
    with _locked():
        if command == "idea":
            brief = _brief(payload.get("brief"))
            source = payload.get("source_project", "")
            if source:
                parent = _load(source)
                if not brief.get("source_comment"):
                    brief["source_comment"] = parent["brief"].get("source_comment", "")
            ident = "idea-" + uuid.uuid4().hex[:16]
            record = {"id": ident, "folder": "drafts/" + ident, "render_prefix": ident,
                      "brief": brief, "source_project": source, "sources": [], "evidence": [],
                      "revision": 0, "notes": [], "approvals": [], "requests": [],
                      "observations": [], "posting_details": [], "created_at": _now()}
            _save(record)
            return _detail(record)
        record = _load(payload.get("id"))
        published = bool(record.get("publication"))
        if published and command in {"save", "note", "resolve", "approve", "request"}:
            raise SocialError("This published creative record is fixed. Start a follow-up idea.", 409, "published")
        if command == "request":
            return _request(record, payload)
        _check_revision(record, payload)
        if command == "save":
            record["brief"] = _brief(payload.get("brief"), record["brief"])
        elif command == "note":
            cut = _selected(record, payload, optional=True)
            seconds = payload.get("seconds")
            if seconds is not None and (type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds < 0 or seconds > 86400 or not cut):
                raise SocialError("Enter a valid playback time for this cut.")
            record["notes"].append({"id": "n" + uuid.uuid4().hex[:16], "text": _text(payload.get("text"), "a review note", 8000, True),
                                    "version": cut["version"] if cut else None, "sha256": cut["sha256"] if cut else None,
                                    "seconds": seconds, "created_at": _now()})
            # Any new unresolved feedback makes this cut need another approval.
            if cut:
                for approval in record["approvals"]:
                    if approval["version"] == cut["version"] and approval["sha256"] == cut["sha256"]:
                        approval["invalidated_at"] = _now()
        elif command == "resolve":
            note = next((n for n in record["notes"] if n["id"] == payload.get("note_id")), None)
            if not note:
                raise SocialError("No such note.", 404)
            disposition = payload.get("disposition")
            if disposition is not None:
                if disposition not in ("addressed", "carry_forward"):
                    raise SocialError("Unknown review decision.")
                cut = _selected(record, payload, latest=True)
                if note.get("sha256") == cut["sha256"] and note.get("version") == cut["version"]:
                    raise SocialError("This note already belongs to the selected cut.")
                events = record.setdefault("review_transfers", [])
                if any(e["source_note_id"] == note["id"] and e["sha256"] == cut["sha256"] and e["version"] == cut["version"] for e in events):
                    raise SocialError("This note already has a review decision for this cut.", 409)
                event = {"source_note_id": note["id"], "source_version": note.get("version"), "source_sha256": note.get("sha256"),
                         "version": cut["version"], "sha256": cut["sha256"], "disposition": disposition, "created_at": _now()}
                if disposition == "carry_forward":
                    carried = {"id": "n" + uuid.uuid4().hex[:16], "text": note["text"], "version": cut["version"],
                               "sha256": cut["sha256"], "seconds": None, "created_at": _now(), "carried_from": note["id"]}
                    record["notes"].append(carried)
                    event["carried_note_id"] = carried["id"]
                    for approval in record["approvals"]:
                        if approval["version"] == cut["version"] and approval["sha256"] == cut["sha256"]:
                            approval["invalidated_at"] = _now()
                events.append(event)
            else:
                if note.get("sha256"):
                    if note["version"] != payload.get("version") or note["sha256"] != payload.get("sha256"):
                        raise SocialError("Select the cut this note belongs to.", 409)
                    _selected(record, payload)
                note["resolved_at"] = _now()
        elif command == "approve":
            cut = _selected(record, payload, latest=True)
            if _open_notes(record, cut):
                raise SocialError("Address the open review notes before approving this cut.", 409, "open_notes")
            record["approvals"].append({"version": cut["version"], "sha256": cut["sha256"], "by": "daniel", "at": _now()})
        elif command == "publication":
            url, date = _url(payload.get("url", ""), publication=True, required=not published), _date(payload.get("date", ""))
            if not url and not date:
                raise SocialError("Add a post URL or posting date.")
            if published:
                record["posting_details"].append({"url": url, "date": date, "recorded_at": _now()})
            else:
                cut = _selected(record, payload, latest=True)
                if _open_notes(record, cut) or not any(a["version"] == cut["version"] and a["sha256"] == cut["sha256"] and not a.get("invalidated_at") for a in record["approvals"]):
                    raise SocialError("Approve the current cut before recording its publication.", 409, "approval_required")
                record["publication"] = {"version": cut["version"], "sha256": cut["sha256"],
                                         "caption": record["brief"].get("caption", ""), "brief": copy.deepcopy(record["brief"]),
                                         "url": url, "date": date, "recorded_at": _now(), "platform": _platform(url)}
        elif command == "observation":
            if not published:
                raise SocialError("Audience responses belong to a published video.")
            record["observations"].append({"id": "o" + uuid.uuid4().hex[:16], "text": _text(payload.get("text"), "an audience response", 8000, True),
                                          "url": _url(payload.get("url", "")), "created_at": _now()})
        _save(record)
        return _detail(record)


def _platform(url):
    host = urlsplit(url).hostname or ""
    return "TikTok" if "tiktok" in host else "Instagram" if "instagram" in host else "YouTube"


def resolve_media(content_id, version, kind):
    record = _load(content_id)
    if not isinstance(version, str) or not VERSION.fullmatch(version) or kind not in ("video", "subtitles"):
        raise SocialError("No such media.", 404)
    suffix = ".mp4" if kind == "video" else ".en.srt"
    path = _inside(_media_root(), f'{record["folder"]}/renders/{record["render_prefix"]}_{version}{suffix}')
    if not path.is_file():
        raise SocialError("This file is unavailable on this computer.", 404, "media_missing")
    return path


def serve_media(handler, content_id, version, kind, expected_hash):
    """Serve bounded chunks with byte ranges; never load the movie into memory."""
    path = resolve_media(content_id, version, kind)
    video = resolve_media(content_id, version, "video")
    sha = _hash(video)
    if not expected_hash or sha != expected_hash:
        raise SocialError("This cut has changed. Refresh before playing it.", 409, "media_changed")
    record = _load(content_id)
    pub = record.get("publication")
    if pub and (pub["version"] != version or not pub.get("sha256") or pub["sha256"] != sha):
        raise SocialError("The published movie is unavailable; no replacement is served.", 404, "media_missing")
    with _open_known(_media_root(), path.relative_to(_media_root())) as f:
        st = os.fstat(f.fileno())
        # Recheck identity after open to refuse a replaced file between hashing and streaming.
        if kind == "video" and _hash(path) != sha:
            raise SocialError("This cut changed. Refresh it.", 409, "media_changed")
        pst = path.stat()
        if _identity(st) != _identity(pst):
            raise SocialError("This cut changed. Refresh it.", 409, "media_changed")
        size, start, end, code = st.st_size, 0, st.st_size - 1, 200
        value = handler.headers.get("Range")
        if value:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", value)
            if len(value) > 128 or not match or not any(match.groups()) or not size:
                return _range_error(handler, size)
            a, b = match.groups()
            if a:
                start = int(a)
                end = min(int(b), size - 1) if b else size - 1
            else:
                amount = int(b)
                if amount <= 0:
                    return _range_error(handler, size)
                start, end = max(0, size - amount), size - 1
            if start >= size or start > end:
                return _range_error(handler, size)
            code = 206
        handler.send_response(code)
        handler.send_header("Content-Type", "video/mp4" if kind == "video" else "application/x-subrip; charset=utf-8")
        handler.send_header("Content-Length", str(max(0, end - start + 1)))
        handler.send_header("Accept-Ranges", "bytes")
        handler.send_header("Cache-Control", "private, no-store")
        handler.send_header("X-Content-Type-Options", "nosniff")
        if code == 206:
            handler.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        handler.end_headers()
        f.seek(start)
        remaining = end - start + 1
        try:
            while remaining > 0:
                chunk = f.read(min(256 * 1024, remaining))
                if not chunk or _identity(os.fstat(f.fileno())) != _identity(st):
                    break
                handler.wfile.write(chunk)
                remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass


def _range_error(handler, size):
    handler.send_response(416)
    handler.send_header("Content-Range", f"bytes */{size}")
    handler.send_header("Content-Length", "0")
    handler.send_header("Cache-Control", "private, no-store")
    handler.end_headers()


def guard_write(handler):
    """Social-only write guard before reading the request body."""
    if handler.headers.get("Content-Type", "").split(";")[0].strip().lower() != "application/json":
        raise SocialError("Send JSON for social changes.", 415)
    if handler.headers.get("Transfer-Encoding"):
        raise SocialError("Chunked requests are unsupported.", 400)
    try:
        length = int(handler.headers.get("Content-Length", "0"))
    except ValueError:
        raise SocialError("Invalid body length.")
    if length <= 0 or length > MAX_BODY:
        raise SocialError("The request is too large or empty.", 413)
    origin = handler.headers.get("Origin")
    host = handler.headers.get("Host", "")
    try:
        p = urlsplit("http://" + host)
        if not host or p.netloc != host or p.path or p.username or p.password or any(c.isspace() for c in host):
            raise ValueError()
        p.port
    except ValueError:
        raise SocialError("Invalid request host.", 403)
    scheme = "https" if getattr(handler.connection, "cipher", None) else "http"
    actual = scheme + "://" + host
    # Tailscale serve preserves Host and supplies X-Forwarded-Proto; trust only
    # its single documented authority and a loopback transport.
    if (getattr(handler, "client_address", ("",))[0] in ("127.0.0.1", "::1")
            and handler.headers.get("X-Forwarded-Proto") == "https"
            and "https://" + host in TRUSTED_PROXY_ORIGINS):
        actual = "https://" + host
    if origin is not None and origin != actual:
        raise SocialError("This page cannot write to this HQ origin.", 403, "origin")
    return length


def serve_artwork(handler, content_id):
    record = _load(content_id)
    rel = record.get("artwork")
    if not rel:
        raise SocialError("No artwork is available.", 404)
    path = _inside(Path(HOST.HQ_DIR).parent / "video", record["folder"] + "/" + rel)
    if not path.is_file():
        raise SocialError("This artwork is unavailable.", 404)
    return handler._send_file(str(path.parent), path.name)

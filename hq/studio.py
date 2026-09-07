"""Tiny Farm HQ — the art studio's memory of hand edits.

Every stroke Daniel makes in the sprite editor is a taste signal, and it used to
evaporate: the editor overwrote the atlas in place, kept one backup per calendar
day, and recorded nothing about *what* changed or *why*. The pixel diff in git was
the only trace, and the reasoning behind it was gone the moment the tab closed.

So this module keeps a per-sheet ledger instead of a backup:

    data/sprite_edits/<key>/0000.png    the pristine sheet, captured once
    data/sprite_edits/<key>/0001.png    the sheet after edit 1
    data/sprite_edits/<key>/0001.json   what changed in edit 1, and why
    ...

Every save appends; nothing is ever overwritten, so any edit can be inspected,
compared or reverted to, and "my second edit today" is no longer a lost before.
A revert is itself an edit (it appends a new step) — history only grows.

The record carries the CEO's own one-line answer to "what were you fixing?"
alongside a mechanical diff the browser computes (which frames, how many pixels,
which colors he introduced, whether the silhouette moved). That pairing — his
intent plus the measurement — is the raw material the art director reads when she
looks for patterns worth promoting into the style guide.
"""
import json
import os
import re
import threading
import time

HOST = None      # the server module, injected by bind()
EDITS = None     # data/sprite_edits

_LOCK = threading.Lock()
KEY_RE = re.compile(r"^[a-z0-9_]{1,120}$")
SEQ_RE = re.compile(r"^\d{4}\.(png|json)$")
MAX_NOTE = 400


def bind(server_module):
    """server.py hands us itself, the same handshake work.py uses."""
    global HOST, EDITS
    HOST = server_module
    EDITS = os.path.join(HOST.DATA, "sprite_edits")
    os.makedirs(EDITS, exist_ok=True)


# ---------------------------------------------------------------------------
# storage
# ---------------------------------------------------------------------------

def sheet_key(sheet):
    """A repo-relative sheet path as one flat directory name."""
    return re.sub(r"[^a-z0-9]+", "_", sheet.lower().removesuffix(".png")).strip("_")


def _dir(key):
    return os.path.join(EDITS, key)


def _write_json(path, doc):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)       # a half-written record must never be readable
    return doc


def history(sheet):
    """Every step for one sheet, oldest first. Step 0 is the pristine capture."""
    key = sheet_key(sheet)
    d = _dir(key)
    out = []
    try:
        names = sorted(n for n in os.listdir(d) if n.endswith(".json"))
    except OSError:
        return out
    for n in names:
        try:
            out.append(HOST.load_json(os.path.join(d, n)))
        except Exception:
            continue
    return out


def _next_seq(key):
    d = _dir(key)
    try:
        seqs = [int(n[:4]) for n in os.listdir(d) if SEQ_RE.match(n)]
    except OSError:
        return 0
    return max(seqs) + 1 if seqs else 0


def png_at(key, seq):
    """Bytes of the sheet as it stood after a given step, or None."""
    if not KEY_RE.match(key or ""):
        return None
    p = os.path.join(_dir(key), f"{int(seq):04d}.png")
    if not os.path.isfile(p):
        return None
    with open(p, "rb") as f:
        return f.read()


# ---------------------------------------------------------------------------
# recording
# ---------------------------------------------------------------------------

def record(sheet, old_bytes, new_bytes, meta):
    """Append one step to a sheet's ledger. `old_bytes` seeds step 0 the first
    time we ever see this sheet, so the pristine state is never lost even though
    we only start watching at the first edit."""
    key = sheet_key(sheet)
    d = _dir(key)
    with _LOCK:
        os.makedirs(d, exist_ok=True)
        seq = _next_seq(key)
        if seq == 0:
            # First edit ever: bank the untouched sheet as step 0, then land
            # this edit as step 1. The pristine bytes are the one thing we can
            # never reconstruct later.
            with open(os.path.join(d, "0000.png"), "wb") as f:
                f.write(old_bytes)
            _write_json(os.path.join(d, "0000.json"), {
                "seq": 0, "kind": "original", "sheet": sheet, "key": key,
                "note": "The sheet before anyone edited it here.",
                "bytes": len(old_bytes), "png": "0000.png",
                "created": _now(), "created_ts": time.time(),
            })
            seq = 1
        rec = {
            "seq": seq,
            "kind": meta.get("kind", "edit"),
            "sheet": sheet,
            "key": key,
            "group": meta.get("group", ""),
            "entity": meta.get("entity", ""),
            "entity_name": meta.get("entity_name", ""),
            "note": (meta.get("note") or "").strip()[:MAX_NOTE],
            "diff": meta.get("diff") or {},
            "reverted_to": meta.get("reverted_to"),
            "bytes": len(new_bytes),
            "png": f"{seq:04d}.png",
            "created": _now(),
            "created_ts": time.time(),
            "filed": None,
        }
        with open(os.path.join(d, rec["png"]), "wb") as f:
            f.write(new_bytes)
        _write_json(os.path.join(d, f"{seq:04d}.json"), rec)
    return rec


def attach_filing(key, seq, filed):
    """Record which work item carried this edit to the art team."""
    p = os.path.join(_dir(key), f"{int(seq):04d}.json")
    if not os.path.isfile(p):
        return
    try:
        rec = HOST.load_json(p)
    except Exception:
        return
    rec["filed"] = filed
    with _LOCK:
        _write_json(p, rec)


def commit_of(key, seq):
    """Which commit carries this step, asked of git rather than remembered.

    Storing the answer was the obvious version and the wrong one: the record of
    where a step landed cannot be inside the commit it describes, so writing it
    back left every step's json dirty forever — an automatic commit whose own
    bookkeeping is the thing left uncommitted. The step's PNG is in exactly one
    commit and git already knows which, so ask it."""
    if not KEY_RE.match(key or ""):
        return ""
    rel = os.path.relpath(os.path.join(_dir(key), f"{int(seq):04d}.png"), HOST.REPO)
    return HOST.run_cmd(["git", "log", "-1", "--format=%h", "--", rel])


def _now():
    import datetime
    return datetime.datetime.now().isoformat(timespec="minutes")


# ---------------------------------------------------------------------------
# what the art team is told
# ---------------------------------------------------------------------------

def commit_subject(rec):
    """The one line a commit gets. His own answer to "what were you fixing?" is
    the subject, because it is the only sentence in the record that says *why* —
    the measurement below it says what moved, and a subject made of pixel counts
    tells a reader nothing they could not get from the diff.

    Written to the studio's rules (docs/WRITING.md): plain, for a reader who
    arrives with no context, so the sheet is named rather than assumed."""
    what = (rec.get("entity_name") or rec.get("entity") or "").strip()
    note = " ".join((rec.get("note") or "").split()).strip(" .")
    if rec.get("kind") == "revert":
        back = rec.get("reverted_to")
        head = f"{what}: back to step {back}" if what else f"Back to step {back}"
        return (head + (f" — {note}" if note else ""))[:72]
    if not note:
        d = rec.get("diff") or {}
        px = d.get("pixels") or 0
        n = len(d.get("frames") or [])
        body = f"{px} pixel{'s' if px != 1 else ''} changed by hand across {n} frame{'s' if n != 1 else ''}"
        return (f"{what}: {body}" if what else body.capitalize())[:72]
    # His sentence, joined to the thing it is about. Lower-cased at the join so
    # the subject reads as one sentence rather than two stuck together.
    if what and not note.lower().startswith(what.lower()):
        note = note[0].lower() + note[1:] if note[:1].isupper() and not note[:2].isupper() else note
        line = f"{what}: {note}"
    else:
        line = note[0].upper() + note[1:] if note else what
    return _fit(line)


# Words that must not be the last thing a subject says. Cutting a sentence to
# length lands on one of these often enough to be worth undoing — "…supposed to
# be transparent in order to" is a worse line than "…transparent in order".
_DANGLING = {"a", "an", "and", "as", "at", "be", "but", "by", "for", "from", "in",
             "into", "is", "it", "of", "on", "or", "so", "that", "the", "then",
             "to", "was", "were", "with"}


def _fit(line, limit=72):
    """Cut to length at a word, never mid-word, and say that it was cut. The
    whole sentence is the next paragraph of the message, so the ellipsis costs
    a reader nothing — it just stops the subject ending in the middle of one."""
    line = line.strip()
    if len(line) <= limit:
        return line.rstrip(" ,;:—-")
    words = line[:limit - 1].split(" ")[:-1]
    while words and words[-1].strip(",;:.—-").lower() in _DANGLING:
        words.pop()
    cut = " ".join(words).rstrip(" ,;:—-")
    return (cut + "…") if cut else line[:limit - 1] + "…"


def commit_message(rec, work_id=""):
    """Subject, his words, the measurement, and where to read the rest. Composed
    from the record we already hold, so making an edit never waits on a model —
    the art director's reading of what the edit *means* arrives separately, on
    the work item this points at."""
    lines = [commit_subject(rec), ""]
    note = " ".join((rec.get("note") or "").split())
    summary = describe(rec)
    if note and note not in lines[0]:
        lines += [note, ""]
    if summary:
        lines += [summary, ""]
    where = f"Hand edit in HQ's sprite editor, step {rec.get('seq')} of {rec.get('sheet', '')}'s ledger."
    if work_id:
        where += f" Filed to the art director to read as {work_id}."
    lines.append(where)
    return "\n".join(lines).strip() + "\n"


def describe(rec):
    """The plain-language version of a diff — what a person would say about it.
    Written for the art director's prompt and the ledger UI alike."""
    d = rec.get("diff") or {}
    frames = d.get("frames") or []
    bits = []
    what = rec.get("entity_name") or rec.get("entity") or "a sprite"
    n = len(frames)
    px = d.get("pixels") or sum(f.get("changed", 0) for f in frames)
    named = [f.get("name") for f in frames if f.get("name")]
    where = f" ({', '.join(named[:4])})" if named else ""
    bits.append(f"{what}: {px} pixel{'s' if px != 1 else ''} across "
                f"{n} frame{'s' if n != 1 else ''}{where}.")
    if d.get("anims"):
        bits.append("The change shows up in: " + ", ".join(d["anims"][:8]) + ".")
    if d.get("colors_added"):
        fresh = d.get("new_to_sheet") or []
        tail = (" (all already used on this sheet)" if not fresh
                else " — one of them appears nowhere else on this sheet" if len(fresh) == 1
                else f" — {len(fresh)} of them appear nowhere else on this sheet")
        bits.append("Colors introduced: " + ", ".join(d["colors_added"][:8]) + tail + ".")
    if d.get("colors_removed"):
        bits.append("Colors dropped: " + ", ".join(d["colors_removed"][:8]) + ".")
    if any(f.get("silhouette") for f in frames):
        bits.append("The silhouette moved, not just the interior shading.")
    else:
        bits.append("Interior shading only — the silhouette is untouched.")
    return " ".join(bits)


def file_to_art(rec, work, org):
    """Put the edit in front of the art director as real work, using the studio's
    existing pipeline rather than a second inbox. Tier 0: reading and looking for
    a pattern has nothing to walk back, so it does not wait on his approval.

    Nothing here proposes a style-guide change yet — that starts once the guide is
    signed (he asked for a look session first). Until then this accumulates as the
    evidence that session will be run from."""
    note = rec.get("note") or ""
    what = rec.get("entity_name") or rec.get("entity") or rec.get("sheet")
    # The note is optional by design: he skips it when he is tidying rather than
    # making a call about the look. So an absent note is itself information —
    # read it as "routine", and do not squeeze significance out of it.
    said = (f' and said he was fixing: "{note}"' if note
            else ". He left no note, which usually means routine cleanup rather than "
                 "a decision about the look")
    ask = (
        f"Daniel hand-edited {what} in the sprite editor{said}"
        + f". The measurement: {describe(rec)} "
        "Look at it against the style guide draft and the rest of the sheet, and say "
        "in a few lines what his edit is telling you about the direction — whether it "
        "agrees with the guide, quietly contradicts it, or repeats something he has "
        "done before. If it is just tidying and there is nothing to learn, say exactly "
        "that in one line; a short honest answer beats manufactured significance. Do "
        "not propose amendments to the guide yet; he wants a look session before it is "
        "signed. This is evidence-gathering for that session."
    )
    owner = "ingrid" if any(e["id"] == "ingrid" for e in org["employees"]) else "claude"
    fields = {
        "title": f"Read Daniel's hand edit to {what}",
        "level": "task",
        "owner": owner,
        "ask": ask,
        "first_action": (
            f"Open {rec['sheet']} and the ledger entry (step {rec['seq']}) in HQ, "
            "compare it with the style guide in docs/design/09-art-direction.md, and "
            "write down what the edit says about his taste."
        ),
        "tier": 0,
        "tier_reason": "reading his edit and writing down what it implies — nothing to walk back",
    }
    cap = {"to": owner, "message": ask, "id": f"sprite:{rec['key']}:{rec['seq']}"}
    try:
        item = work._file_item(fields, cap, org)
    except Exception as e:      # filing must never cost him a save
        return {"error": str(e)[:200]}
    return {"work_id": item["id"], "owner": owner, "title": item["title"]}


# ---------------------------------------------------------------------------
# HTTP surface
# ---------------------------------------------------------------------------

def api_get(path, query):
    if path == "/api/sprite/history":
        sheet = (query.get("sheet") or [""])[0]
        if not sheet:
            return {"error": "sheet required"}
        return {"sheet": sheet, "key": sheet_key(sheet), "steps": history(sheet)}
    return {"error": "not found"}

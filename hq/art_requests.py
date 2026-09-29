"""Pixel art the work queue generates for a card, as a service the drain runs (S-37).

A queue worker runs in a sandbox with no network and never holds the Retro
Diffusion key. When a card needs new art the worker writes requests into
`art_requests/<name>.json` at its worktree root and ends its session. After the
session the drain (outside the sandbox) takes the files out of the worktree so
they never land, prices every request with the free cost check, applies the
caps below, generates what fits, archives the raw output, records the spend,
and runs the worker once more with the results (hq/drain.py do_item).

A round the caps refuse is not run at all: the card is held for the chief of
staff with the reason in plain words, and the rest of its work still goes
through the normal check. The key is read here, from the main checkout's
gitignored .env, and passed only to tools/rd_client.py; it never enters a
prompt, patch, log or card field.
"""
import base64
import contextlib
import datetime
import io
import json
import os
import re
import shutil
import sys
import threading

import roots
import work

# Ruled by Daniel in chat 2026-09-29 (S-37). The one place the art caps live.
# A card may carry `art_cap_usd` to raise its own limit; only the chief of staff
# sets it, as the answer to the hold below.
CARD_CAP_USD = 2.00
DAY_CAP_USD = 10.00           # per calendar day, local time, across every card
MAX_IMAGES = 4                # per request
MAX_REQUESTS = 8              # per round; one round per drain run

REQUEST_DIR = "art_requests"
DEFAULT_STYLE = "rd_plus__default"
ALLOWED = ("what", "prompt", "width", "height", "num_images", "prompt_style",
           "palette", "input_image", "seed")
HOLD_KIND = "art_budget"      # the blocker and action type on a held card

TOOLS = os.path.join(os.path.dirname(roots.CODE_ROOT), "tools")
STORE = os.path.join(os.environ.get("HQ_TEST_SCRATCH") or roots.ROOTS["data"], "art_generations")
_LOCK = threading.Lock()      # pricing, the cap check and the spend record are one step


def _tool(name):
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    return __import__(name)


def client():
    return _tool("rd_client")


def _money(x):
    return f"${x:.0f}" if float(x).is_integer() else f"${x:.2f}"


# ---------------------------------------------------------------------------
# requests
# ---------------------------------------------------------------------------

def take_requests(tree):
    """Every request file in the worktree, read and then removed, so none lands."""
    folder = os.path.join(tree, REQUEST_DIR)
    if not os.path.isdir(folder):
        return []
    out = []
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        stem = re.sub(r"[^a-z0-9_-]+", "-", os.path.splitext(name)[0].lower()).strip("-") or "request"
        entry = {"file": name, "name": stem[:40]}
        if not name.endswith(".json") or not os.path.isfile(path):
            entry["error"] = "it is not a .json file"
        else:
            try:
                with open(path, encoding="utf-8") as f:
                    entry["data"] = json.load(f)
            except (OSError, ValueError) as exc:
                entry["error"] = f"it is not readable JSON ({type(exc).__name__})"
        out.append(entry)
    shutil.rmtree(folder, ignore_errors=True)
    return out


def validate(entry, tree):
    """(params for the API, error). Unknown fields are refused so a worker learns
    the format instead of having a field silently ignored."""
    if entry.get("error"):
        return None, entry["error"]
    data = entry.get("data")
    if not isinstance(data, dict):
        return None, "it is not a JSON object"
    unknown = sorted(set(data) - set(ALLOWED))
    if unknown:
        return None, f"it has fields the format does not take: {', '.join(unknown)}"
    what = data.get("what")
    if not isinstance(what, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,39}", what):
        return None, "`what` must be a short lowercase slug (letters, digits, hyphens)"
    prompt = data.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 2000:
        return None, "`prompt` must be text of at most 2000 characters"
    params = {"prompt": prompt.strip()}
    for field in ("width", "height"):
        value = data.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or not 16 <= value <= 512:
            return None, f"`{field}` must be a whole number of pixels from 16 to 512"
        params[field] = value
    images = data.get("num_images", 1)
    if not isinstance(images, int) or isinstance(images, bool) or not 1 <= images <= MAX_IMAGES:
        return None, f"`num_images` must be 1 to {MAX_IMAGES}"
    params["num_images"] = images
    style = data.get("prompt_style", DEFAULT_STYLE)
    if not isinstance(style, str) or not re.fullmatch(r"[a-z0-9_]{1,80}", style):
        return None, "`prompt_style` must be a Retro Diffusion style name such as rd_plus__default"
    params["prompt_style"] = style
    if "seed" in data:
        if not isinstance(data["seed"], int) or isinstance(data["seed"], bool):
            return None, "`seed` must be a whole number"
        params["seed"] = data["seed"]
    if "palette" in data:
        palette = data["palette"]
        if (not isinstance(palette, list) or not 1 <= len(palette) <= 64 or
                not all(isinstance(c, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", c) for c in palette)):
            return None, "`palette` must be a list of 1 to 64 colours written #rrggbb"
        params["palette_hex"] = palette
    if "input_image" in data:
        rel = data["input_image"]
        base = os.path.realpath(tree)
        path = os.path.realpath(os.path.join(base, rel)) if isinstance(rel, str) else ""
        if (not path or not path.startswith(base + os.sep) or not path.endswith(".png")
                or not os.path.isfile(path) or os.path.getsize(path) > 2_000_000):
            return None, "`input_image` must be the path of a PNG under 2 MB inside the worktree"
        with open(path, "rb") as f:
            params["input_image"] = base64.b64encode(f.read()).decode()
    return params, ""


# ---------------------------------------------------------------------------
# the ledger the caps are counted from
# ---------------------------------------------------------------------------

def _ledger_path():
    return os.path.join(STORE, "ledger.json")


def ledger():
    try:
        with open(_ledger_path(), encoding="utf-8") as f:
            return json.load(f).get("entries") or []
    except (OSError, ValueError):
        return []


def _record(entry):
    os.makedirs(STORE, exist_ok=True)
    entries = ledger() + [entry]
    tmp = _ledger_path() + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"entries": entries}, f, indent=2)
        f.write("\n")
    os.replace(tmp, _ledger_path())


def spent(*, card=None, day=None):
    """Drain-run art spend, counted from the drain's own ledger in HQ's store.
    That ledger, not hq/data/spend.json, is what the caps read: a card's spend
    reaches spend.json only when its patch lands."""
    return round(sum(float(e.get("dollars") or 0) for e in ledger()
                     if (card is None or e.get("work_item") == card)
                     and (day is None or e.get("date") == day)), 4)


def card_cap(item):
    try:
        return float(item.get("art_cap_usd") or CARD_CAP_USD)
    except (TypeError, ValueError):
        return CARD_CAP_USD


def today():
    return datetime.date.today().isoformat()


# ---------------------------------------------------------------------------
# one round
# ---------------------------------------------------------------------------

def _scrub(text, key):
    text = str(text or "")
    return text.replace(key, "[key]") if key else text


def _failure(exc, key):
    detail = _scrub(exc, key)[:160]
    return f"the art service call failed ({type(exc).__name__}{': ' + detail if detail else ''})"


def run_round(item, tree, repo, *, rd=None, day=None):
    """Take the worktree's requests and run them within the caps. Returns None
    when there were none, otherwise what happened, for the continuation brief,
    the card's result and the hold."""
    requests = take_requests(tree)
    if not requests:
        return None
    day = day or today()
    art = {"requests": len(requests), "day": day, "generated": [], "rejected": [],
           "failed": [], "hold": None, "spent": 0.0}
    valid = []
    for entry in requests[:MAX_REQUESTS]:
        params, error = validate(entry, tree)
        if error:
            art["rejected"].append({"file": entry["file"], "reason": error})
        else:
            valid.append({**entry, "params": params, "what": entry["data"]["what"]})
    for entry in requests[MAX_REQUESTS:]:
        art["rejected"].append({"file": entry["file"],
                                "reason": f"a round runs at most {MAX_REQUESTS} requests"})
    if not valid:
        return art
    rd = rd or client()
    key = rd.find_key(os.path.join(repo, ".env"))
    if not key:
        art["hold"] = {"kind": "failed", "day": day, "asked": None,
                       "reason": "The drain could not find the art service key on this machine, "
                                 "so the art this card asked for was not generated."}
        return art
    with _LOCK:
        priced = []
        for entry in valid:
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    quote = rd.cost(key, entry["params"])
                priced.append({**entry, "price": float(quote.get("balance_cost"))})
            except Exception as exc:  # noqa: BLE001 - any failure is reported, none is fatal
                art["failed"].append({"file": entry["file"], "reason": _failure(exc, key)})
        asked = round(sum(p["price"] for p in priced), 4)
        card_spent, day_spent, cap = spent(card=item["id"]), spent(day=day), card_cap(item)
        if priced and (card_spent + asked > cap + 1e-9 or day_spent + asked > DAY_CAP_USD + 1e-9):
            kind = "card" if card_spent + asked > cap + 1e-9 else "day"
            art["hold"] = {"kind": kind, "day": day, "asked": asked,
                           "reason": (f"This card asked for {_money(asked)} of art generation; it has "
                                      f"spent {_money(card_spent)} of its {_money(cap)} and the studio "
                                      f"{_money(day_spent)} of today's {_money(DAY_CAP_USD)}.")}
            return art
        for entry in priced:
            _generate(item, tree, rd, key, entry, art, day)
    if not art["generated"] and art["failed"]:
        art["hold"] = {"kind": "failed", "day": day, "asked": None,
                       "reason": "The art service did not generate any of the art this card asked "
                                 "for: " + "; ".join(f["reason"] for f in art["failed"][:3]) + "."}
    return art


def _generate(item, tree, rd, key, entry, art, day):
    folder = f"{day}-{item['id']}-{entry['what']}"
    store = os.path.join(STORE, folder)
    name, n = entry["name"], 2
    while os.path.exists(os.path.join(store, f"{name}_meta.json")):
        name, n = f"{entry['name']}-{n}", n + 1
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            meta = rd.generate(key, name, entry["params"], store)
    except Exception as exc:  # noqa: BLE001
        art["failed"].append({"file": entry["file"], "reason": _failure(exc, key)})
        return
    if not meta:
        art["failed"].append({"file": entry["file"], "reason": "the art service refused it after retries"})
        return
    dollars = float(meta.get("balance_cost") if meta.get("balance_cost") is not None else entry["price"])
    files = sorted(f for f in os.listdir(store) if f.startswith(name + "_"))
    raw = f"assets/raw/{folder}"
    purpose = (f"{entry['what']} for the work card \"{item.get('title', '')[:80]}\" "
               f"({name}, {entry['params']['num_images']} image(s)), generated by the work queue")
    record = _tool("record_spend").make_entry(
        purpose, dollars, credits=round(dollars * 100, 4), balance_after=meta.get("remaining_balance"),
        work_item=item["id"], date=day, recorded_by="drain")
    _record({**record, "raw_folder": raw, "request": entry["file"]})
    # Into the worktree: the raws and the spend record land with the card's patch.
    os.makedirs(os.path.join(tree, raw), exist_ok=True)
    for f in files:
        shutil.copy2(os.path.join(store, f), os.path.join(tree, raw, f))
    _tool("record_spend").append(record, os.path.join(tree, "hq", "data", "spend.json"))
    art["spent"] = round(art["spent"] + dollars, 4)
    art["generated"].append({"file": entry["file"], "folder": raw, "dollars": dollars,
                             "images": [f for f in files if not f.endswith("_meta.json")],
                             "meta": f"{name}_meta.json"})


# ---------------------------------------------------------------------------
# what the worker, the card and the chief of staff are told
# ---------------------------------------------------------------------------

WORKER_BRIEF = f"""
NEW PIXEL ART: you cannot call the art service (no network, no key). If the card needs new
art, write one request per subject to {REQUEST_DIR}/<name>.json at the worktree root, then end
your session saying you are waiting for art. Fields: "what" (short slug), "prompt", "width",
"height" (16-512; sprites 64+, generate at 4x the cell), optional "num_images" (1-{MAX_IMAGES}),
"prompt_style" (default {DEFAULT_STYLE}), "palette" (["#rrggbb", ...] from
docs/design/09-art-direction.md), "input_image" (a worktree PNG path), "seed". After your
session the drain prices and generates them — at most {_money(CARD_CAP_USD)} of art per card and
{_money(DAY_CAP_USD)} a day across the studio — saves the raws under assets/raw/, records the
spend, and starts one more session for you to post-process, place and credit them.
"""


def continuation_brief(art, earlier_reply):
    lines = ["ART ROUND. This is your second session on this card in this run. Your earlier "
             "session's changes are in the worktree (see `git status`). After it ended, the drain "
             f"ran the art requests it wrote and removed {REQUEST_DIR}/, which never lands."]
    for g in art["generated"]:
        lines.append(f"- generated {g['file']}: {', '.join(g['images'])} in {g['folder']}/ "
                     f"(metadata {g['meta']}), {_money(g['dollars'])}")
    for r in art["rejected"]:
        lines.append(f"- not run, {r['file']}: {r['reason']}")
    for f in art["failed"]:
        lines.append(f"- failed, {f['file']}: {f['reason']}")
    if art["hold"]:
        lines.append(f"Not generated: {art['hold']['reason']} The card is held for the chief of "
                     "staff for that art. Finish everything else the card needs and say in your "
                     "reply what is still waiting for art.")
    if art["generated"]:
        lines.append("The spend is already in hq/data/spend.json; do not record it again, and do "
                     "not edit or delete anything in those raw folders. Continue the card: "
                     "post-process the raws (key the background, trim, fit the cell, lock to the "
                     "game's palette), place the result where the card needs it, and record "
                     "provenance in CREDITS.md (generator, prompt, date, raw folder, cost).")
    lines.append(f"A new request written to {REQUEST_DIR}/ now is not run in this run; the drain "
                 "runs one round of art per run.")
    if earlier_reply:
        lines.append("YOUR EARLIER SESSION'S REPLY:\n" + earlier_reply.strip()[-3000:])
    return "\n".join(lines) + "\n\n"


def result_note(art):
    """The plain sentences added to the card's result."""
    said = []
    if art["generated"]:
        count = sum(len(g["images"]) for g in art["generated"])
        folders = ", ".join(sorted({g["folder"] for g in art["generated"]}))
        said.append(f"The work queue generated {count} image{'s' if count != 1 else ''} of pixel art "
                    f"for this card for {_money(art['spent'])}; the raw files are in {folders}.")
    if art["hold"]:
        said.append(art["hold"]["reason"])
    if art["rejected"]:
        said.append(f"{len(art['rejected'])} art request{'s were' if len(art['rejected']) != 1 else ' was'} "
                    "not run because it did not follow the request format: "
                    + "; ".join(r["reason"] for r in art["rejected"][:3]) + ".")
    if art.get("second_round"):
        said.append("After the first images came back it asked for more art; the work queue runs "
                    "one round of art per run, so that waits for this card's next run.")
    return " ".join(said)


def hold_wake(hold):
    if hold["kind"] == "card":
        return ("The chief of staff raises this card's art limit (art_cap_usd) above what it has "
                "spent plus what it asked for, or turns the request down.")
    return "The next calendar day, when the drain tries the art again."


def after_write_back(item, rec):
    """Put the art round on the card once its result is written: the note on the
    result and, when art was refused, the hold. Only a card still in the queue's
    hands is held; a card that landed without the art says so and closes."""
    art = rec.get("art")
    if not art:
        return item
    note = result_note(art)
    hold = art.get("hold")
    with work.mutation_lock():
        fresh = work.load_item(item["id"])
        if note and note not in (fresh.get("result") or ""):
            fresh["result"] = ((fresh.get("result") or "").rstrip() + "\n\n" + note).strip()
        held = hold and fresh.get("state") in ("for_review", "waiting_session")
        if held:
            # Back in the queue, held: a refused round is the chief of staff's to
            # settle, not a verdict for Daniel and not a repair for the owner, which
            # would only ask for the same art again.
            fresh["state"], fresh["started"] = "waiting_session", ""
            fresh.pop("repair_hold", None)
            fresh["art_hold"] = hold
        work.save_item(fresh)
        item.clear(); item.update(fresh)
    if held:
        input_id = f"{hold['kind']}:{hold['day']}:{rec.get('attempt_id') or ''}"
        action = work.ensure_action(item, HOLD_KIND, input_id=input_id, owner="claude",
                                    summary="Decide whether this card's art may cost more, then release it.",
                                    priority="reconciliation", wake=hold_wake(hold))
        with work.mutation_lock():
            fresh = work.load_item(item["id"])
            for a in work._workflow(fresh)["actions"]:
                if a.get("id") == action["id"] and a.get("state") == "open":
                    a["state"], a["updated_at"] = "blocked", work._now_iso()
            work.save_item(fresh)
            item.clear(); item.update(fresh)
        work.ensure_blocker(item, HOLD_KIND, input_id=input_id, owner="claude",
                            reason=hold["reason"], action_id=action["id"], wake=hold_wake(hold))
    return item


def hold_cleared(item, day=None):
    hold = item.get("art_hold") or {}
    if hold.get("kind") == "card":
        return spent(card=item["id"]) + float(hold.get("asked") or 0) <= card_cap(item) + 1e-9
    return (day or today()) != hold.get("day")


def settle_holds(day=None):
    """Release every card whose art hold no longer binds: its limit was raised,
    or a new day began. Called at the start of each drain run."""
    released = []
    for item in work.items():
        if item.get("state") in work.TERMINAL_STATES or not item.get("art_hold"):
            continue
        if not hold_cleared(item, day):
            continue
        with work.mutation_lock():
            fresh = work.load_item(item["id"])
            flow = work._workflow(fresh)
            for b in flow["blockers"]:
                if b.get("type") == HOLD_KIND and b.get("state") == "open":
                    b["state"], b["resolved_at"] = "resolved", work._now_iso()
            for a in flow["actions"]:
                if a.get("type") == HOLD_KIND and a.get("state") != "done":
                    a["state"], a["finished_at"] = "done", work._now_iso()
            fresh.pop("art_hold", None)
            work.save_item(fresh)
        released.append(item["id"])
    return released

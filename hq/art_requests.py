"""Pixel art the work queue generates for a card, as a tool its worker calls (S-37).

A queue worker runs in a sandbox with no network and never holds the Retro
Diffusion key. For tier-1+ build sessions the drain attaches hq/art_mcp.py, a
small tool server that runs outside the sandbox beside the worker's session.
When the worker calls its `generate_art` tool, this module validates the
request, prices it with the free cost check, applies the caps below, generates
it, archives the raws (in HQ's store and in the worktree, so they land with the
patch), records the spend in both ledgers and hands back the file paths — all
inside the same session, so the worker can look at the result and ask again
within the card's budget.

A call the caps refuse generates nothing: the worker is told the amounts in
plain words and carries on with the rest of the card, and after the session the
drain holds the card for the chief of staff (after_write_back). The key is read
here, from a gitignored .env outside any worktree (key_files), and passed only
to tools/rd_client.py; it never enters a prompt, patch, log, tool reply or card
field. Concurrent calls from parallel drain workers are serialised by a file
lock on the ledger, and a call's price is reserved in the ledger before it
generates, so the day cap cannot be overspent.
"""
import base64
import contextlib
import datetime
import fcntl
import io
import json
import os
import re
import shutil
import sys
import uuid

import roots
import work

# Ruled by Daniel in chat 2026-09-29 (S-37). The one place the art caps live.
# A card may carry `art_cap_usd` to raise its own limit; only the chief of staff
# sets it, as the answer to the hold below.
CARD_CAP_USD = 2.00
DAY_CAP_USD = 10.00           # per calendar day, local time, across every card
MAX_IMAGES = 4                # per call

DEFAULT_STYLE = "rd_plus__default"
ALLOWED = ("what", "prompt", "width", "height", "num_images", "prompt_style",
           "palette", "input_image", "seed")
HOLD_KIND = "art_budget"      # the blocker and action type on a held card
MCP_NAME = "art"              # the tool server's name in a session's config
MCP_TOOLS = ("generate_art", "art_budget")

TOOLS = os.path.join(os.path.dirname(roots.CODE_ROOT), "tools")
STORE = os.path.join(os.environ.get("HQ_TEST_SCRATCH") or roots.ROOTS["data"], "art_generations")


def _tool(name):
    if TOOLS not in sys.path:
        sys.path.insert(0, TOOLS)
    return __import__(name)


def client():
    return _tool("rd_client")


def _money(x):
    return f"${x:.0f}" if float(x).is_integer() else f"${x:.2f}"


# ---------------------------------------------------------------------------
# one request
# ---------------------------------------------------------------------------

def validate(data, tree):
    """(params for the API, error). Unknown fields are refused so a worker learns
    the format instead of having a field silently ignored."""
    if not isinstance(data, dict):
        return None, "the request is not an object"
    unknown = sorted(set(data) - set(ALLOWED))
    if unknown:
        return None, f"it has fields the tool does not take: {', '.join(unknown)}"
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


@contextlib.contextmanager
def ledger_lock():
    """One writer at a time across every process: each drain worker's tool
    server is its own process, and the drain runs up to three at once."""
    os.makedirs(STORE, exist_ok=True)
    with open(os.path.join(STORE, "ledger.lock"), "a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def ledger():
    """Every drain-run generation, and every price reserved for one in flight.
    A missing file is an empty ledger; an unreadable one raises, because reading
    it as empty would lift both caps."""
    try:
        with open(_ledger_path(), encoding="utf-8") as f:
            return json.load(f).get("entries") or []
    except FileNotFoundError:
        return []


def _write(entries):
    os.makedirs(STORE, exist_ok=True)
    tmp = _ledger_path() + f".{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"entries": entries}, f, indent=2)
        f.write("\n")
    os.replace(tmp, _ledger_path())


def _record(entry):
    with ledger_lock():
        _write(ledger() + [entry])


def _settle(reservation, entry):
    """Replace a reservation with what the call really cost, or drop it (None)."""
    with ledger_lock():
        entries = [e for e in ledger() if e.get("reservation") != reservation]
        _write(entries + ([entry] if entry else []))


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


def budget(item, day=None):
    """What this card and the studio have spent, and what one more call may cost."""
    day = day or today()
    card_spent, day_spent, cap = spent(card=item["id"]), spent(day=day), card_cap(item)
    return {"card_spent": card_spent, "card_cap": cap, "day_spent": day_spent,
            "day_cap": DAY_CAP_USD, "day": day,
            "remaining": round(max(0.0, min(cap - card_spent, DAY_CAP_USD - day_spent)), 4)}


def key_files(repo):
    """Where the key is looked for: the main checkout's .env, then the user
    workspace's (on 2026-09-29 only the workspace had one). Never a worktree."""
    paths = [os.path.join(repo, ".env"), os.path.join(roots.ROOTS["user_workspace"], ".env")]
    return tuple(dict.fromkeys(os.path.realpath(p) for p in paths))


def _scrub(text, key):
    text = str(text or "")
    return text.replace(key, "[key]") if key else text


def _failure(exc, key):
    detail = _scrub(exc, key)[:160]
    return f"the art service call failed ({type(exc).__name__}{': ' + detail if detail else ''})"


def refusal(card_spent, cap, day_spent, asked):
    return (f"This card has spent {_money(card_spent)} of its {_money(cap)} and the studio "
            f"{_money(day_spent)} of today's {_money(DAY_CAP_USD)}; this request would cost "
            f"{_money(asked)}.")


# ---------------------------------------------------------------------------
# one tool call
# ---------------------------------------------------------------------------

def generate_one(item, data, tree, key_paths, *, rd=None, day=None):
    """Run one generate_art call within the caps. `item` needs id and title, and
    may carry art_cap_usd. Returns the outcome: status is generated, refused (over
    a cap; nothing generated), rejected (malformed; nothing priced) or failed. A
    refusal, or a failure only the chief of staff can fix, carries `hold`."""
    day = day or today()
    params, error = validate(data, tree)
    if error:
        what = data.get("what") if isinstance(data, dict) else None
        return {"status": "rejected", "what": what, "reason": error}
    what = data["what"]
    rd = rd or client()
    key = rd.find_key(*key_paths)
    if not key:
        reason = ("The art service key could not be found on this machine, so the art this card "
                  "asked for was not generated.")
        return {"status": "failed", "what": what, "reason": reason,
                "hold": {"kind": "failed", "day": day, "asked": None, "reason": reason}}
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            quote = rd.cost(key, params)
        price = float(quote.get("balance_cost"))
    except Exception as exc:  # noqa: BLE001 - any failure is reported, none is fatal
        return {"status": "failed", "what": what, "reason": _failure(exc, key)}
    reservation = uuid.uuid4().hex
    try:
        with ledger_lock():
            try:
                money = budget(item, day)
            except (OSError, ValueError, AttributeError):
                reason = ("The record of art spending could not be read, so no art was generated "
                          "for this card.")
                return {"status": "failed", "what": what, "reason": reason,
                        "hold": {"kind": "failed", "day": day, "asked": None, "reason": reason}}
            card_over = money["card_spent"] + price > money["card_cap"] + 1e-9
            if card_over or money["day_spent"] + price > DAY_CAP_USD + 1e-9:
                reason = refusal(money["card_spent"], money["card_cap"], money["day_spent"], price)
                return {"status": "refused", "what": what, "reason": reason, "asked": price, **money,
                        "hold": {"kind": "card" if card_over else "day", "day": day,
                                 "asked": price, "reason": reason}}
            # The price is held in the ledger before the call so a parallel
            # worker's check counts it; a crash leaves it counted, never lifted.
            _write(ledger() + [{"work_item": item["id"], "date": day, "dollars": price,
                                "recorded_by": "drain", "request": what,
                                "reservation": reservation, "unconfirmed": True}])
    except OSError as exc:
        return {"status": "failed", "what": what, "reason": _failure(exc, key)}
    return _generate(item, tree, rd, key, what, params, price, reservation, day)


def _generate(item, tree, rd, key, what, params, price, reservation, day):
    folder = f"{day}-{item['id']}-{what}"
    store = os.path.join(STORE, folder)
    name, n = what, 2
    while os.path.exists(os.path.join(store, f"{name}_meta.json")):
        name, n = f"{what}-{n}", n + 1
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            meta = rd.generate(key, name, params, store)
    except Exception as exc:  # noqa: BLE001
        # A call that died mid-way may still have been charged (a timed-out read
        # is billed), so its reservation stays in the ledger at the quoted price.
        return {"status": "failed", "what": what, "reason": _failure(exc, key)}
    if not meta:
        _settle(reservation, None)     # refused by the service: nothing was charged
        return {"status": "failed", "what": what, "reason": "the art service refused it after retries"}
    dollars = float(meta.get("balance_cost") if meta.get("balance_cost") is not None else price)
    files = sorted(f for f in os.listdir(store) if f.startswith(name + "_"))
    raw = f"assets/raw/{folder}"
    purpose = (f"{what} for the work card \"{str(item.get('title', ''))[:80]}\" "
               f"({name}, {params['num_images']} image(s)), generated by the work queue")
    record = _tool("record_spend").make_entry(
        purpose, dollars, credits=round(dollars * 100, 4), balance_after=meta.get("remaining_balance"),
        work_item=item["id"], date=day, recorded_by="drain")
    _settle(reservation, {**record, "raw_folder": raw, "request": what})
    # Into the worktree: the raws and the spend record land with the card's patch.
    os.makedirs(os.path.join(tree, raw), exist_ok=True)
    for f in files:
        shutil.copy2(os.path.join(store, f), os.path.join(tree, raw, f))
    _tool("record_spend").append(record, os.path.join(tree, "hq", "data", "spend.json"))
    try:
        money = budget(item, day)
    except (OSError, ValueError, AttributeError):
        money = {}
    return {"status": "generated", "what": what, "folder": raw, "dollars": dollars,
            "images": [f"{raw}/{f}" for f in files if not f.endswith("_meta.json")],
            "meta": f"{raw}/{name}_meta.json", **money}


# ---------------------------------------------------------------------------
# a session's calls, for the drain to read afterwards
# ---------------------------------------------------------------------------

def session_path(attempt_id):
    return os.path.join(STORE, "sessions", f"{attempt_id}.json")


def new_session(day=None):
    return {"calls": 0, "day": day or today(), "generated": [], "refused": [], "rejected": [],
            "failed": [], "hold": None, "spent": 0.0}


def note_call(art, outcome):
    """Fold one call's outcome into the session's record."""
    art["calls"] += 1
    status = outcome["status"]
    if status == "generated":
        art["generated"].append({k: outcome[k] for k in ("what", "folder", "dollars", "images", "meta")})
        art["spent"] = round(art["spent"] + outcome["dollars"], 4)
    else:
        art[status].append({"what": outcome.get("what"), "reason": outcome["reason"]})
    if outcome.get("hold"):
        art["hold"] = outcome["hold"]
    return art


def save_session(attempt_id, art):
    path = session_path(attempt_id)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(art, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def session_outcome(attempt_id):
    """What the worker's tool calls did, or None when it made none. A session
    whose calls all failed at the service is held like a refused one."""
    try:
        with open(session_path(attempt_id), encoding="utf-8") as f:
            art = json.load(f)
    except (OSError, ValueError):
        return None
    if not art.get("calls"):
        return None
    if not art.get("hold") and not art.get("generated") and art.get("failed"):
        art["hold"] = {"kind": "failed", "day": art["day"], "asked": None,
                       "reason": "The art service did not generate any of the art this card asked "
                                 "for: " + "; ".join(f["reason"] for f in art["failed"][:3]) + "."}
    return art


def mcp_server(item, tree, run_id, attempt_id, repo):
    """How a worker session starts its art tool server. Every argument is a
    path or a card fact; the server finds the key itself, in key_files."""
    args = [os.path.join(str(roots.CODE_ROOT), "art_mcp.py"),
            "--card", item["id"], "--title", str(item.get("title") or "")[:80],
            "--cap", str(card_cap(item)), "--tree", tree, "--run", run_id or "byhand",
            "--attempt", attempt_id, "--store", STORE]
    for path in key_files(repo):
        args += ["--key-file", path]
    return {"name": MCP_NAME, "command": sys.executable, "args": args, "tools": list(MCP_TOOLS)}


# ---------------------------------------------------------------------------
# what the worker, the card and the chief of staff are told
# ---------------------------------------------------------------------------

WORKER_BRIEF = f"""
NEW PIXEL ART: if the card needs new art, call the `generate_art` tool (you cannot reach the
art service yourself: no network, no key). Fields: "what" (short slug), "prompt", "width",
"height" (16-512; sprites 64+, generate at 4x the cell), optional "num_images" (1-{MAX_IMAGES}),
"prompt_style" (default {DEFAULT_STYLE}), "palette" (["#rrggbb", ...] from
docs/design/09-art-direction.md), "input_image" (a worktree PNG path), "seed". It returns the
raw files it saved under assets/raw/, what the call cost and what is left. A card may spend
{_money(CARD_CAP_USD)} of art and the studio {_money(DAY_CAP_USD)} a day; `art_budget` tells you
where you stand. Look at what comes back, and if it is wrong, call again with a better prompt
while the budget allows. The spend is already recorded in hq/data/spend.json; do not record it
again or touch the raw folders. Post-process the raws (key the background, trim, fit the cell,
lock to the game's palette), place the result where the card needs it, and credit it in
CREDITS.md (generator, prompt, date, raw folder, cost). If the tool refuses for budget, finish
the rest of the card and say in your reply what is still waiting for art.
"""


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
    return " ".join(said)


def hold_wake(hold):
    if hold["kind"] == "card":
        return ("The chief of staff raises this card's art limit (art_cap_usd) above what it has "
                "spent plus what it asked for, or turns the request down.")
    return "The next calendar day, when the drain tries the art again."


def after_write_back(item, rec):
    """Put the session's art on the card once its result is written: the note on
    the result and, when art was refused, the hold. Only a card still in the
    queue's hands is held; a card that landed without the art says so and closes."""
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
            # Back in the queue, held: a refused call is the chief of staff's to
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
        try:
            if not hold_cleared(item, day):
                continue
        except (OSError, ValueError, AttributeError):
            continue          # an unreadable ledger releases nothing
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

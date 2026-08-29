# session_trace.gd — diagnostic record of what the player tried, including the
# tries that did nothing.
#
# Why this is separate from ReplayLog: that stream is the S-3 training substrate
# and `apply_to()` applies every entry it holds, so it must stay "actions that
# changed the world". This one is the opposite — its whole value is the taps the
# sim never saw. The two share a seed header so a trace can be read alongside a
# world reconstructed from the replay.
#
# Because the sim is deterministic, world state is derivable and is deliberately
# NOT stored here; only the non-derivable part is: the input and how the game
# interpreted it.
#
# Layer note: diagnostic only. Nothing reads this back into the sim, and writing
# it consumes no RNG, so it cannot affect determinism.
class_name SessionTrace
extends RefCounted

const VERSION := 1

var gen_seed: int = 0
var continued: bool = false
var entries: Array[Dictionary] = []

var _flushed := 0
var _t0 := 0


func start(seed_value: int, from_save: bool) -> void:
	gen_seed = seed_value
	continued = from_save
	entries.clear()
	_flushed = 0
	_t0 = Time.get_ticks_msec()


func _stamp() -> int:
	return Time.get_ticks_msec() - _t0


# Every tap, whatever came of it. `verb` is the router's reading of the tap
# ("" when it resolved to nothing) and `outcome` is what followed:
#   none        - nothing on that tile to act on (a dead tap)
#   walk        - just a move order
#   queued      - action deferred until she arrives
#   acted       - performed immediately
#   refused     - the sim said no; `reason` carries why
#   unreachable - she cannot path there and is not already beside it: the tap
#                 did nothing whatsoever. The most diagnostic outcome we record.
func tap(modality: String, tile: Vector2i, player_tile: Vector2i, tool_idx: int,
		verb: String, outcome: String, reason: String = "") -> void:
	var e := {
		"t": _stamp(),
		"kind": "tap",
		"in": modality,
		"tile": [tile.x, tile.y],
		"at": [player_tile.x, player_tile.y],
		"tool": tool_idx,
		"verb": verb,
		"out": outcome,
	}
	if reason != "":
		e["why"] = reason
	entries.append(e)


# A queued action firing on arrival, so a refusal that happens seconds after the
# tap is still attributable to it.
func act(tile: Vector2i, actor: String, verb: String, ok: bool, reason: String = "") -> void:
	var e := {
		"t": _stamp(),
		"kind": "act",
		"tile": [tile.x, tile.y],
		"actor": actor,
		"verb": verb,
		"ok": ok,
	}
	if not ok and reason != "":
		e["why"] = reason
	entries.append(e)


func header() -> Dictionary:
	return {"version": VERSION, "gen_seed": gen_seed, "continued": continued}


func to_jsonl() -> String:
	var lines: PackedStringArray = []
	lines.append(JSON.stringify(header()))
	for e in entries:
		lines.append(JSON.stringify(e))
	return "\n".join(lines) + "\n"


# Append-only like ReplayLog, so a long session costs O(new entries) per flush.
func flush(path: String) -> void:
	if entries.is_empty() and _flushed == 0:
		return
	if _flushed == 0:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return
		f.store_string(to_jsonl())
		f.close()
		_flushed = entries.size()
		return
	if _flushed >= entries.size():
		return
	var fa := FileAccess.open(path, FileAccess.READ_WRITE)
	if fa == null:
		return
	fa.seek_end()
	for i in range(_flushed, entries.size()):
		fa.store_string(JSON.stringify(entries[i]) + "\n")
	fa.close()
	_flushed = entries.size()


# --- Reading a trace back (for analysis) --------------------------------------

static func parse(text: String) -> Dictionary:
	var out := {"header": {}, "entries": []}
	var lines := text.strip_edges().split("\n")
	# A blank or whitespace-only file still yields one empty line, and handing
	# that to JSON.parse_string logs a parse error before returning null. It
	# recovers, but the reader is meant to be pointed at whatever file exists —
	# including a truncated or empty one — without printing engine errors at a
	# designer who just wanted a report.
	if lines.is_empty() or lines[0].strip_edges() == "":
		return out
	var head = JSON.parse_string(lines[0])
	if typeof(head) == TYPE_DICTIONARY:
		out["header"] = head
	for i in range(1, lines.size()):
		if lines[i].strip_edges() == "":
			continue
		var e = JSON.parse_string(lines[i])
		if typeof(e) == TYPE_DICTIONARY:
			out["entries"].append(e)
	return out


# What a playtest actually wants to know: which taps went nowhere, and why.
static func summarize(parsed: Dictionary) -> Dictionary:
	var taps := 0
	var dead := 0
	var unreachable := 0
	var refused := 0
	var reasons: Dictionary = {}
	var repeated: Dictionary = {}  # "x,y" -> dead/refused taps on that tile
	for e in parsed.get("entries", []):
		var out: String = String(e.get("out", ""))
		var is_dead: bool = String(e.get("kind", "")) == "tap" \
			and (out == "none" or out == "refused" or out == "unreachable")
		if e.get("kind", "") == "tap":
			taps += 1
		if e.get("kind", "") == "act" and not e.get("ok", true):
			refused += 1
			var w: String = e.get("why", "?")
			reasons[w] = int(reasons.get(w, 0)) + 1
		if is_dead:
			if out == "refused":
				refused += 1
				var w2: String = e.get("why", "?")
				reasons[w2] = int(reasons.get(w2, 0)) + 1
			else:
				# "none" and "unreachable" are both dead taps, but they mean
				# different things to a designer: one is "there was nothing to do
				# here", the other is "she wanted to and the game would not let
				# her get there". Keep them separable.
				dead += 1
				if out == "unreachable":
					unreachable += 1
			var key := "%d,%d" % [e["tile"][0], e["tile"][1]]
			repeated[key] = int(repeated.get(key, 0)) + 1
	var stuck: Array = []
	for k in repeated.keys():
		if int(repeated[k]) >= 3:
			stuck.append(k)
	return {
		"taps": taps,
		"dead_taps": dead,
		"unreachable": unreachable,
		"refused": refused,
		"reasons": reasons,
		"stuck_tiles": stuck,
	}


# What a *teaching* playtest wants to know, which is a different question from
# summarize()'s "what went nowhere": how long each lesson took to land, and where
# she stopped moving. Chapter design/13 §8 names these as the pass criteria, so
# they live here (pure, static, testable) rather than in the reader tool.
#
# `stall_ms` defaults to 8000 to match the stage-2 nudge threshold in design/13
# §6: a gap that long is, by that design's own definition, a moment the game
# should have noticed and helped with.
static func teaching_report(parsed: Dictionary, stall_ms: int = 8000) -> Dictionary:
	var entries: Array = parsed.get("entries", [])
	var first_use: Dictionary = {}   # verb -> ms of first SUCCESSFUL player act
	var outcomes: Dictionary = {}    # outcome -> tap count
	var stalls: Array = []           # gaps between consecutive taps
	var tap_times: Array = []
	var last_t := 0

	for e in entries:
		var t := int(e.get("t", 0))
		last_t = maxi(last_t, t)
		var kind := String(e.get("kind", ""))
		if kind == "tap":
			var out := String(e.get("out", "?"))
			outcomes[out] = int(outcomes.get(out, 0)) + 1
			tap_times.append(t)
		elif kind == "act":
			# Only the player's own successful actions count as a lesson landing.
			# The chicken laying an egg is not the child learning anything.
			if e.get("ok", false) and String(e.get("actor", "")) == "player":
				var verb := String(e.get("verb", ""))
				if verb != "" and not first_use.has(verb):
					first_use[verb] = t

	for i in range(1, tap_times.size()):
		var gap: int = int(tap_times[i]) - int(tap_times[i - 1])
		if gap >= stall_ms:
			stalls.append({"after_ms": tap_times[i - 1], "gap_ms": gap})

	return {
		"duration_ms": last_t,
		"time_to_first_tap_ms": (int(tap_times[0]) if not tap_times.is_empty() else -1),
		"taps": tap_times.size(),
		"outcomes": outcomes,
		"first_use": first_use,
		"stalls": stalls,
		"longest_stall_ms": _longest(stalls),
	}


static func _longest(stalls: Array) -> int:
	var m := 0
	for s in stalls:
		m = maxi(m, int(s.get("gap_ms", 0)))
	return m


# --- Analyses promoted from hand-written one-offs -----------------------------
# Everything below was first run by hand against a real session on 2026-08-28 and
# earned its place by finding something. They live here rather than in the reader
# tool so they are pure, unit-testable, and reusable by anything that reads a
# trace. The rule for adding to this file: an analysis graduates from a one-off
# only after it has actually found something worth acting on.


# Wall-clock lies. The first real session reported a duration of 274 minutes; it
# was about twenty seconds of play with a four-and-a-half-hour backgrounded gap
# in the middle, because persistence now survives the app being put down. Any gap
# longer than `idle_ms` is treated as the player having left rather than played.
static func active_time(parsed: Dictionary, idle_ms: int = 120000) -> Dictionary:
	var ts: Array = []
	for e in parsed.get("entries", []):
		if String(e.get("kind", "")) == "tap":
			ts.append(int(e.get("t", 0)))
	if ts.size() < 2:
		return {"active_ms": 0, "wall_ms": (int(ts[0]) if ts.size() == 1 else 0), "gaps": 0}
	var active := 0
	var gaps := 0
	for i in range(1, ts.size()):
		var d: int = int(ts[i]) - int(ts[i - 1])
		if d <= idle_ms:
			active += d
		else:
			gaps += 1
	return {"active_ms": active, "wall_ms": int(ts[-1]) - int(ts[0]), "gaps": gaps}


# Integrity check on the instrument itself, not on the player.
#
# A tap logged "unreachable" while she was standing beside the tile is a lie, and
# the 2026-08-28 session contained fourteen of them — every one adjacent. The
# report is the measuring device for the M1 gate, so it must be able to catch its
# own categories drifting. If this ever returns non-zero again, fix the logger
# before drawing a single conclusion from the session.
static func mislabelled_unreachable(parsed: Dictionary) -> Array:
	var bad: Array = []
	for e in parsed.get("entries", []):
		if String(e.get("out", "")) != "unreachable":
			continue
		var t = e.get("tile", null)
		var at = e.get("at", null)
		if t is Array and at is Array and t.size() == 2 and at.size() == 2:
			if absi(int(at[0]) - int(t[0])) + absi(int(at[1]) - int(t[1])) <= 1:
				bad.append(e)
	return bad


# Which verbs are failing, as opposed to which reasons are given. Refusals with
# no reason show up as "?" in the reason table, which says nothing about where to
# look; grouping by verb found the well and the shipping bin immediately.
static func failures_by_verb(parsed: Dictionary) -> Dictionary:
	var out := {"with_reason": {}, "without_reason": {}}
	for e in parsed.get("entries", []):
		if String(e.get("kind", "")) != "act" or e.get("ok", true):
			continue
		var verb := String(e.get("verb", "?"))
		var bucket: String = "with_reason" if e.has("why") else "without_reason"
		out[bucket][verb] = int(out[bucket].get(verb, 0)) + 1
	return out


# What a stuck tile actually did, over the whole session. A tile that is only
# ever dead is a different problem from one that worked five times and then
# stopped — the second is a state change she could not see.
static func tile_history(parsed: Dictionary, key: String) -> Dictionary:
	var outs: Dictionary = {}
	var tools: Dictionary = {}
	for e in parsed.get("entries", []):
		if String(e.get("kind", "")) != "tap":
			continue
		var t = e.get("tile", null)
		if not (t is Array and t.size() == 2):
			continue
		if "%d,%d" % [int(t[0]), int(t[1])] != key:
			continue
		var o := String(e.get("out", "?"))
		outs[o] = int(outs.get(o, 0)) + 1
		var tool := int(e.get("tool", -1))
		tools[tool] = int(tools.get(tool, 0)) + 1
	return {"outcomes": outs, "tools": tools}


# What she was holding when a tap went nowhere. Twelve of fourteen dead taps in
# the 2026-08-28 session had the watering can selected, which is what identified
# them as already-watered crops rather than a pathing fault.
static func dead_tap_tools(parsed: Dictionary) -> Dictionary:
	var tools: Dictionary = {}
	for e in parsed.get("entries", []):
		if String(e.get("kind", "")) != "tap":
			continue
		var o := String(e.get("out", ""))
		if o == "none" or o == "unreachable" or o == "refused":
			var tool := int(e.get("tool", -1))
			tools[tool] = int(tools.get(tool, 0)) + 1
	return tools


# Days reached, from the world's own sleep verb — the cheapest proxy for whether
# she understood the cot, which is the one beat with no visual affordance at all.
static func days_played(parsed: Dictionary) -> int:
	var n := 0
	for e in parsed.get("entries", []):
		if String(e.get("kind", "")) == "act" and String(e.get("verb", "")) == "sleep" \
				and e.get("ok", false):
			n += 1
	return n

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
#   none    - nothing on that tile to act on (a dead tap)
#   walk    - just a move order
#   queued  - action deferred until she arrives
#   acted   - performed immediately
#   refused - the sim said no; `reason` carries why
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
	if lines.is_empty():
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
	var refused := 0
	var reasons: Dictionary = {}
	var repeated: Dictionary = {}  # "x,y" -> dead/refused taps on that tile
	for e in parsed.get("entries", []):
		var out: String = String(e.get("out", ""))
		var is_dead: bool = String(e.get("kind", "")) == "tap" and (out == "none" or out == "refused")
		if e.get("kind", "") == "tap":
			taps += 1
		if e.get("kind", "") == "act" and not e.get("ok", true):
			refused += 1
			var w: String = e.get("why", "?")
			reasons[w] = int(reasons.get(w, 0)) + 1
		if is_dead:
			if out == "none":
				dead += 1
			else:
				refused += 1
				var w2: String = e.get("why", "?")
				reasons[w2] = int(reasons.get(w2, 0)) + 1
			var key := "%d,%d" % [e["tile"][0], e["tile"][1]]
			repeated[key] = int(repeated.get(key, 0)) + 1
	var stuck: Array = []
	for k in repeated.keys():
		if int(repeated[k]) >= 3:
			stuck.append(k)
	return {
		"taps": taps,
		"dead_taps": dead,
		"refused": refused,
		"reasons": reasons,
		"stuck_tiles": stuck,
	}

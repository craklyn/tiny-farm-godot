# replay_log.gd — Action-stream recording for deterministic replay (S-3/S-5, M2)
# A session is (gen_seed, [Action...]); re-applying the stream to a freshly
# generated world reproduces the end state exactly. Sleep entries carry the
# weather that was rolled live, so entity RNG noise between actions cannot
# desync a replay. Replays are also the training-data substrate phase 4
# curates into datasets (docs/ARCHITECTURE.md, "The Action record").
#
# --- Format v2 (M2.5 WI-5, per plan §3.3, ratified by Q-53) -------------------
#
# v1's model was "a session is an ordered list of Actions". It has no notion of
# *when*, which was fine while nothing in the sim moved on its own. Since WI-3
# the hen walks and the crow flies on the tick clock, so an ordered list is no
# longer enough information to rebuild the session: two runs can apply the same
# actions and end with everybody standing somewhere else.
#
# v2 adds three things and changes nothing else:
#
#  1. **Every entry carries a `tick`** — the sim time it was applied at. A replay
#     advances the clock to that tick before applying the entry, so sim time
#     passes in a replay exactly as it passed in the session.
#  2. **Entries a brain produced are marked `brain: true`** and are *not*
#     re-applied on replay: the clock advance above recomputes them, and the
#     replay **asserts the recomputation matches the recording action for
#     action** (`divergence` below). That is the plan's dual-record net —
#     Phase A, where both halves are written and compared. Phase B stops writing
#     the brain entries, and it does not happen until this has soaked.
#  3. **The session's seed is a header field that `apply_to` reseeds from**, on
#     both the fresh and the continued-from-save paths. `SimRng.stateless()`
#     derives from the current seed, so without this a continued session replays
#     under whatever seed the verifying process happens to hold — a hole that
#     predates this work (M2_5_PLAN §9, WI-3's closing note) and is closed here.
#
# v1 logs keep working **unchanged**: `apply_to` takes a legacy path for them
# that advances no clock, recomputes nothing and reseeds nothing, which is
# exactly what it did before. They are unverifiable rather than wrong, and Q-41's
# build stamp is what says which (see `build_note`).
class_name ReplayLog
extends RefCounted

# 1: M2's action stream. 2: tick-stamped, with the dual-record net (M2.5 WI-5).
const VERSION := 2

# Q-41: the *format* version above says how to parse the file; this says which game
# produced it. They are different questions, and only the second one can tell you
# whether a replay's actions still mean what they meant when they were recorded.
#
# A replay is not self-validating: apply_to() re-runs the actions against today's
# rules, so a change to what `till` does, to worldgen for a seed, to growth rates,
# to energy costs, or to SimRng consumption order silently produces a different
# world from the one the player actually played. Nothing in the file itself reveals
# that. The industry answer is not to make replays version-proof — that is
# expensive and usually fails — but to make them version-*aware*, the way
# StarCraft II refuses a replay from a different patch. This is that.
#
# Stamped at record time and free thereafter; it cannot be added retroactively to a
# corpus already on disk, which is why it lands before phase 4 accumulates one.
#
# **The energy-cost case, worked (T-29, 2026-08-31).** That change multiplied every
# cost — and the pool they are spent from — by 30, and it is the one shape of
# cost drift that leaves a replay *meaning the same thing*: no entry carries an
# energy, so recomputing an old log under the new costs from the new pool lands on
# exactly the ×30 image of the state it landed on before, refusal for refusal. The
# saves needed a shim (`SaveGame` v2) because they store the numbers; the logs
# needed nothing, and `assets/demo/demo_replay.json` regenerates byte-identical
# across the change. Not every cost change is this kind — a *re-weighting* would
# genuinely reinterpret a log, and that is what the stamp above is for.
static func current_build() -> String:
	return str(ProjectSettings.get_setting("application/config/build_id", "dev"))


# The seed the session ran under. On a fresh session that is the seed its world
# was generated from; on a continued one it is the seed the save carried
# (`SimWorld.gen_seed`), which is what makes the two halves of a continued
# session agree about `SimRng.stateless()`. 0 means "not recorded" — every v1
# log, and any v2 log continued from a save written before the world knew its
# own seed — and those replay under whatever seed the caller holds, as they
# always did.
var gen_seed: int = 0
var base_save: Dictionary = {}  # non-empty when the session continued from a save
var entries: Array[Dictionary] = []
var build_id: String = ""  # "" means a pre-Q-41 replay, not a mismatch
var version: int = VERSION  # the format this log was *read* in; new logs are VERSION

# Sim time at the last flush (M2.5 WI-5). The entries say when each Action
# happened; this says how long the session went on afterwards, which is the
# difference between a replay that stops the moment the player last acted and
# one that ends where the autosave it is compared against was taken — the hen
# keeps pottering in the seconds between. Written as a mark line by `flush_to`
# / `save_to`, so it stays append-only.
var end_tick: int = 0

# Empty when a replay recomputed exactly what was recorded; otherwise the first
# place the two disagreed, in one line (M2.5 WI-5's dual-record net). Set by
# `apply_to`; read by `SaveGame.replay_matches`, the robot session and
# `verify_replay.gd`, which are where a failure gets to be loud.
var divergence: String = ""


func start(seed_value: int) -> void:
	gen_seed = seed_value
	base_save = {}
	build_id = current_build()
	version = VERSION
	end_tick = 0
	entries.clear()


# Sessions that continue from an autosave replay from that snapshot instead
# of regenerating from seed. `seed_value` is the seed the continued session is
# running under — `SimWorld.gen_seed` of the restored world, which `main.gd`
# reseeds to. Optional so a caller that has no seed to offer (a pre-WI-5 save,
# a test) still gets v1's behaviour: replay under the ambient seed.
func start_from_save(save_data: Dictionary, seed_value: int = 0) -> void:
	gen_seed = seed_value
	base_save = save_data.duplicate(true)
	build_id = current_build()
	version = VERSION
	end_tick = 0
	entries.clear()


# `tick` is sim time at the moment the Action resolved; `from_brain` marks the
# Actions a tick-driven brain decided, which a v2 replay recomputes instead of
# re-applying (see apply_to). Both default to what a caller with no clock would
# honestly say — tick 0, decided by somebody outside the sim.
func record(action: Dictionary, result: Dictionary, tick: int = 0,
		from_brain: bool = false) -> void:
	var a := action.duplicate(true)
	if a.get("verb", "") == "sleep":
		a["weather"] = result.get("weather", "sunny")
	a["tick"] = tick
	if from_brain:
		a["brain"] = true
	entries.append(_encode(a))
	end_tick = maxi(end_tick, tick)


# How much sim time the session had passed by the time it was last written down.
# Called beside the autosave, never on its own: the pairing is what
# `verify_replay.gd` and the robot session check (M2.5 WI-5).
func mark_tick(tick: int) -> void:
	end_tick = maxi(end_tick, tick)


# --- Player free walking (format v2, live since M2.5 WI-6) --------------------
#
# §3.3's other half, and the one thing about the player no rule can recompute:
# where she chose to walk. The entry shape is
# `{ "kind": "walk", "event": "begin"|"turn"|"step"|"stop", "dir": "left",
# "from": [x, y], "tick": n }` — no verb, no target, and it is not an Action.
#
# **`from` is the tile she is standing on at that instant**, which is what makes
# these verifiable: `_apply_v2` writes it straight into her registry entry, so a
# replay's player position is the session's player position and
# `SaveGame.capture_canonical` compares her like everybody else. WI-5 defined the
# shape and left the recorder off because nothing could check one yet; WI-6 wires
# `player/player.gd`'s pixel walker to the registry, which is what turned it on.
#
# `step` is the fourth event value, added with the recorder (WI-6): §3.3's
# begin/turn/stop is a run-length encoding of *held input*, and a crossing that
# continues in the same direction is neither a begin, a turn, nor a stop. Every
# reader keys off `kind` alone, so the extra value cost nothing downstream.
const WALK_KIND := "walk"


static func is_walk(entry: Dictionary) -> bool:
	return String(entry.get("kind", "")) == WALK_KIND


func record_walk(event: String, dir: String, from: Vector2i, tick: int) -> void:
	entries.append({
		"kind": WALK_KIND, "event": event, "dir": dir,
		"from": [from.x, from.y], "tick": tick,
	})
	end_tick = maxi(end_tick, tick)


# Rebuild world + gs from scratch by re-applying the stream.
#
# v2 does three things v1 did not, and the difference is the whole of the format
# bump: it reseeds from the session's own seed, it advances the clock to each
# entry's tick so the brains live through the same sim time the session did, and
# it checks what they decided against what was recorded (`divergence`).
func apply_to(world: SimWorld, gs) -> void:
	divergence = ""
	if gs != null and gs.has_method("reset"):
		gs.reset()
	if not base_save.is_empty():
		# Restore first, then reseed — the same order `main.gd` does it in when a
		# player taps Continue, which is what makes the live session and this
		# reproduction agree about every `SimRng.stateless()` draw for the rest of
		# the run. A v1 log, or one whose save predates `SimWorld.gen_seed`, has
		# no seed to go back to and keeps the old behaviour exactly.
		SaveGame.restore(base_save, world, gs)
		if version >= 2 and gen_seed != 0:
			SimRng.reseed(gen_seed)
	else:
		SimRng.reseed(gen_seed)
		world.generate()
	if version < 2:
		# The legacy path, unchanged: no clock, no recomputation, every entry
		# applied exactly as recorded (M2's semantics, Q-41's build stamp).
		for e in entries:
			world.apply_action(_decode(e), gs)
		return
	_apply_v2(world, gs)


# The dual-record net (plan §4, WI-5 Phase A).
#
# Two streams have to agree. The **recording** is `entries`, in the order the
# session produced them. The **recomputation** is whatever the brains decide
# while the clock is advanced through the same ticks, which `advance_to_tick`
# hands back in dispatch order. Player and neighbour entries are applied (nothing
# recomputes a person); brain entries are matched against the recomputation and
# never re-applied, because the clock advance has already applied them.
#
# The two are compared head to head as signatures — actor, verb, target, tick and
# any parameters — so "the same hen laid the same egg on the same tile four ticks
# late" fails, and says so.
func _apply_v2(world: SimWorld, gs) -> void:
	var recomputed: Array[Dictionary] = []
	var matched := 0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var tick := int(e.get("tick", 0))
		recomputed.append_array(world.advance_to_tick(tick, gs))
		if is_walk(e):
			# Not an Action: the player's own motion, replayed by putting her back
			# on the tile the event says she reached (M2.5 WI-6). It changes
			# nothing else in the world, and it is not part of the net — a person
			# is recorded, never recomputed.
			_apply_walk(e, world)
			continue
		var decoded := _decode(e)
		if bool(e.get("brain", false)):
			if matched >= recomputed.size():
				_note_divergence(i, _signature(decoded, tick), "(nothing recomputed)")
				continue
			var got: Dictionary = recomputed[matched]
			matched += 1
			_note_divergence(i, _signature(decoded, tick),
				_signature(got["action"], int(got.get("tick", -1))))
			continue
		world.apply_action(decoded, gs)
	# The session went on after its last Action — the hen was still pottering when
	# the autosave was written — so the replay lives out the same sim time.
	recomputed.append_array(world.advance_to_tick(end_tick, gs))
	if matched < recomputed.size():
		var extra: Dictionary = recomputed[matched]
		_note_divergence(entries.size(), "(nothing recorded)",
			_signature(extra["action"], int(extra.get("tick", -1))))


# A recorded free walk, put back into the registry. Tolerant of a malformed entry
# rather than fatal on one: a walk that cannot be read is a walk that does not
# move her, which is exactly what every reader did with these before WI-6 turned
# the recorder on.
static func _apply_walk(entry: Dictionary, world: SimWorld) -> void:
	var from = entry.get("from", null)
	if not (from is Array) or from.size() != 2:
		return
	world.set_actor_pos(SimWorld.ACTOR_PLAYER,
		Vector2i(int(from[0]), int(from[1])), String(entry.get("dir", "")))


# First one wins: a desync cascades, and the first divergence is the one that
# says something. Equal signatures are not a divergence at all.
func _note_divergence(index: int, recorded: String, recomputed: String) -> void:
	if recorded == recomputed or divergence != "":
		return
	divergence = "entry %d: recorded %s, recomputed %s" % [index, recorded, recomputed]


# One line that stands for an Action-at-a-tick, for comparing a recorded entry
# against a recomputed one. `tick` and `brain` are the recorder's own bookkeeping
# and are compared explicitly (the tick) or not at all (the mark), so they are
# not folded into the parameter list.
static func _signature(action: Dictionary, tick: int) -> String:
	var keys: Array = action.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		if k == "tick" or k == "brain":
			continue
		parts.append("%s=%s" % [k, _value_text(action[k])])
	return "@%d {%s}" % [tick, ",".join(parts)]


static func _value_text(v) -> String:
	if v is Vector2i:
		return "%d,%d" % [v.x, v.y]
	if v is Array and v.size() == 2 and not (v[0] is Array):
		return "%d,%d" % [int(v[0]), int(v[1])]
	return str(v)


# On-disk/in-text format is JSONL: line 1 is a header {version, gen_seed,
# base_save}; every following line is one entry. This makes per-sleep
# persistence append-only (O(new entries), not O(session)) — the review-flagged
# O(n^2) rewrite is gone.
#
# **The end tick is a line, not a header field** (v2), for that reason exactly: a
# session's sim time is only known at the moment it is written down, and the
# header was written at the start. So a flush appends `{"mark": <tick>}` after
# whatever entries it added; the last mark in the file wins, and a reader lifts
# them out of the stream rather than handing them to anybody as Actions.
var _flushed := 0  # entries already on disk at the current flush target
var _marked := -1  # end_tick of the last mark line written


func to_json() -> String:
	var lines: PackedStringArray = []
	lines.append(JSON.stringify({
		"version": VERSION,
		"gen_seed": gen_seed,
		"base_save": base_save,
		"build_id": build_id,
	}))
	for e in entries:
		lines.append(JSON.stringify(e))
	if end_tick > 0:
		lines.append(_mark_line())
	return "\n".join(lines)


func _mark_line() -> String:
	return JSON.stringify({ "mark": end_tick })


static func from_json(text: String) -> ReplayLog:
	var replay := ReplayLog.new()
	var lines := text.split("\n", false)
	if lines.is_empty():
		return replay
	var header = JSON.parse_string(lines[0])
	if header == null or typeof(header) != TYPE_DICTIONARY:
		return replay
	# Absent ⇒ 1: every log written before the field existed is a v1 log, and the
	# whole point of the version is to keep reading them the way they were meant.
	replay.version = int(header.get("version", 1))
	replay.gen_seed = int(header.get("gen_seed", 0))
	replay.build_id = str(header.get("build_id", ""))
	var bs = header.get("base_save", {})
	if typeof(bs) == TYPE_DICTIONARY:
		replay.base_save = bs
	for i in range(1, lines.size()):
		var e = JSON.parse_string(lines[i])
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if e.has("mark"):
			replay.end_tick = maxi(replay.end_tick, int(e["mark"]))
			continue
		replay.entries.append(e)
		replay.end_tick = maxi(replay.end_tick, int(e.get("tick", 0)))
	return replay


# Three outcomes, not two: a replay from this build, one from a different build, and
# one recorded before stamping existed. Callers need to tell the last two apart —
# a legacy replay is unverifiable rather than known-bad, and refusing it outright
# would discard the only sessions we have.
enum Build { MATCH, MISMATCH, UNSTAMPED }


func build_status() -> Build:
	if build_id == "":
		return Build.UNSTAMPED
	return Build.MATCH if build_id == current_build() else Build.MISMATCH


# One line a human can read, for the tools that report rather than decide.
func build_note() -> String:
	match build_status():
		Build.MATCH:
			return "build %s (matches this build)" % build_id
		Build.MISMATCH:
			return "build %s, but this is %s — actions may no longer mean the same thing" \
				% [build_id, current_build()]
	return "unstamped (recorded before Q-41); cannot be checked against this build"


# Full rewrite (new file / format reset). Prefer flush_to for periodic saves.
func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json())
	f.store_string("\n")
	_flushed = entries.size()
	_marked = end_tick
	return true


# Append-only periodic save: writes only entries recorded since the last
# flush. Falls back to a full write when the file doesn't exist yet.
func flush_to(path: String) -> bool:
	if _flushed == 0 or not FileAccess.file_exists(path):
		return save_to(path)
	# Sim time moving is a change worth writing even when nobody acted: a farm
	# where the hen wandered for twenty seconds and nothing else happened is a
	# farm whose replay has to run for twenty seconds (v2).
	if _flushed >= entries.size() and _marked >= end_tick:
		return true
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return false
	f.seek_end()
	for i in range(_flushed, entries.size()):
		f.store_string(JSON.stringify(entries[i]))
		f.store_string("\n")
	if end_tick > 0:
		f.store_string(_mark_line())
		f.store_string("\n")
		_marked = end_tick
	_flushed = entries.size()
	return true


static func load_from(path: String) -> ReplayLog:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))


# JSON has no Vector2i; store targets as [x, y]
static func _encode(a: Dictionary) -> Dictionary:
	if a.has("target") and a.target is Vector2i:
		a["target"] = [a.target.x, a.target.y]
	return a


static func _decode(e: Dictionary) -> Dictionary:
	var a: Dictionary = e.duplicate(true)
	if a.has("target") and a.target is Array and a.target.size() == 2:
		a["target"] = Vector2i(int(a.target[0]), int(a.target[1]))
	return a

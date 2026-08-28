# replay_log.gd — Action-stream recording for deterministic replay (S-3/S-5, M2)
# A session is (gen_seed, [Action...]); re-applying the stream to a freshly
# generated world reproduces the end state exactly. Sleep entries carry the
# weather that was rolled live, so entity RNG noise between actions cannot
# desync a replay. Replays are also the training-data substrate phase 4
# curates into datasets (docs/ARCHITECTURE.md, "The Action record").
class_name ReplayLog
extends RefCounted

const VERSION := 1

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
static func current_build() -> String:
	return str(ProjectSettings.get_setting("application/config/build_id", "dev"))


var gen_seed: int = 0
var base_save: Dictionary = {}  # non-empty when the session continued from a save
var entries: Array[Dictionary] = []
var build_id: String = ""  # "" means a pre-Q-41 replay, not a mismatch


func start(seed_value: int) -> void:
	gen_seed = seed_value
	base_save = {}
	build_id = current_build()
	entries.clear()


# Sessions that continue from an autosave replay from that snapshot instead
# of regenerating from seed.
func start_from_save(save_data: Dictionary) -> void:
	gen_seed = 0
	base_save = save_data.duplicate(true)
	build_id = current_build()
	entries.clear()


func record(action: Dictionary, result: Dictionary) -> void:
	var a := action.duplicate(true)
	if a.get("verb", "") == "sleep":
		a["weather"] = result.get("weather", "sunny")
	entries.append(_encode(a))


# Rebuild world + gs from scratch by re-applying the stream.
func apply_to(world: SimWorld, gs) -> void:
	if gs != null and gs.has_method("reset"):
		gs.reset()
	if not base_save.is_empty():
		SaveGame.restore(base_save, world, gs)
	else:
		SimRng.reseed(gen_seed)
		world.generate()
	for e in entries:
		world.apply_action(_decode(e), gs)


# On-disk/in-text format is JSONL: line 1 is a header {version, gen_seed,
# base_save}; every following line is one entry. This makes per-sleep
# persistence append-only (O(new entries), not O(session)) — the review-flagged
# O(n^2) rewrite is gone.
var _flushed := 0  # entries already on disk at the current flush target


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
	return "\n".join(lines)


static func from_json(text: String) -> ReplayLog:
	var replay := ReplayLog.new()
	var lines := text.split("\n", false)
	if lines.is_empty():
		return replay
	var header = JSON.parse_string(lines[0])
	if header == null or typeof(header) != TYPE_DICTIONARY:
		return replay
	replay.gen_seed = int(header.get("gen_seed", 0))
	replay.build_id = str(header.get("build_id", ""))
	var bs = header.get("base_save", {})
	if typeof(bs) == TYPE_DICTIONARY:
		replay.base_save = bs
	for i in range(1, lines.size()):
		var e = JSON.parse_string(lines[i])
		if typeof(e) == TYPE_DICTIONARY:
			replay.entries.append(e)
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
	return true


# Append-only periodic save: writes only entries recorded since the last
# flush. Falls back to a full write when the file doesn't exist yet.
func flush_to(path: String) -> bool:
	if _flushed == 0 or not FileAccess.file_exists(path):
		return save_to(path)
	if _flushed >= entries.size():
		return true
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return false
	f.seek_end()
	for i in range(_flushed, entries.size()):
		f.store_string(JSON.stringify(entries[i]))
		f.store_string("\n")
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

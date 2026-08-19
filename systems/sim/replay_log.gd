# replay_log.gd — Action-stream recording for deterministic replay (S-3/S-5, M2)
# A session is (gen_seed, [Action...]); re-applying the stream to a freshly
# generated world reproduces the end state exactly. Sleep entries carry the
# weather that was rolled live, so entity RNG noise between actions cannot
# desync a replay. Replays are also the training-data substrate phase 4
# curates into datasets (docs/ARCHITECTURE.md, "The Action record").
class_name ReplayLog
extends RefCounted

const VERSION := 1

var gen_seed: int = 0
var entries: Array[Dictionary] = []


func start(seed_value: int) -> void:
	gen_seed = seed_value
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
	SimRng.reseed(gen_seed)
	world.generate()
	for e in entries:
		world.apply_action(_decode(e), gs)


func to_json() -> String:
	return JSON.stringify({ "version": VERSION, "gen_seed": gen_seed, "entries": entries })


static func from_json(text: String) -> ReplayLog:
	var replay := ReplayLog.new()
	var data = JSON.parse_string(text)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return replay
	replay.gen_seed = int(data.get("gen_seed", 0))
	for e in data.get("entries", []):
		if typeof(e) == TYPE_DICTIONARY:
			replay.entries.append(e)
	return replay


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json())
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

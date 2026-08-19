# save_game.gd — Versioned save format v1 (M2 step 7)
# Snapshot of sim truth (SimWorld grids + GameState fields) with a version
# field and a migration hook from the very first save we ever ship
# (docs/ARCHITECTURE.md, world scale plan). JSON on disk.
class_name SaveGame
extends RefCounted

const VERSION := 1


static func capture(world: SimWorld, gs) -> Dictionary:
	return {
		"version": VERSION,
		"world": {
			"tiles": world.tiles.duplicate(true),
			"objects": world.objects.duplicate(true),
		},
		"state": {
			"day": gs.day,
			"weather": gs.weather,
			"energy": gs.energy,
			"max_energy": gs.max_energy,
			"gold": gs.gold,
			"selected_tool": gs.selected_tool,
			"seeds": gs.seeds.duplicate(),
			"crops": gs.crops.duplicate(),
			"harvest_counts": gs.harvest_counts.duplicate(),
			"shipping_bin": gs.shipping_bin.duplicate(),
			"watering_can_charges": gs.watering_can_charges,
			"max_watering_can_charges": gs.max_watering_can_charges,
			"selected_seed_type": gs.selected_seed_type,
			"hard_energy": gs.hard_energy,
			"crows_scared": gs.crows_scared,
			"total_shipped": gs.total_shipped,
			"milestones": gs._milestones_earned.duplicate(),
		},
	}


static func restore(data: Dictionary, world: SimWorld, gs) -> bool:
	var d := migrate(data)
	if d.is_empty():
		return false

	# Structural validation: a version-valid save with missing or truncated
	# grids must be rejected, not restored into undersized arrays.
	var w: Dictionary = d.get("world", {})
	var in_tiles: Array = w.get("tiles", [])
	var in_objects: Array = w.get("objects", [])
	if in_tiles.size() != SimWorld.MAP_HEIGHT or in_objects.size() != SimWorld.MAP_HEIGHT:
		return false
	for row in in_tiles:
		if not (row is Array) or row.size() != SimWorld.MAP_WIDTH:
			return false
	for row in in_objects:
		if not (row is Array) or row.size() != SimWorld.MAP_WIDTH:
			return false

	world.tiles.clear()
	for row in in_tiles:
		var r: Array = []
		for tile in row:
			r.append(_normalize_tile(tile))
		world.tiles.append(r)
	world.objects.clear()
	for row in in_objects:
		var r2: Array = []
		for obj in row:
			r2.append(String(obj))
		world.objects.append(r2)

	var s: Dictionary = d.get("state", {})
	gs.day = int(s.get("day", 1))
	gs.weather = String(s.get("weather", "sunny"))
	gs.energy = int(s.get("energy", 20))
	gs.max_energy = int(s.get("max_energy", 20))
	gs.gold = int(s.get("gold", 0))
	gs.selected_tool = int(s.get("selected_tool", 0))
	gs.seeds = _int_values(s.get("seeds", {}))
	gs.crops = _int_values(s.get("crops", {}))
	gs.harvest_counts = _int_values(s.get("harvest_counts", {}))
	gs.shipping_bin = _int_values(s.get("shipping_bin", {}))
	gs.watering_can_charges = int(s.get("watering_can_charges", 8))
	gs.max_watering_can_charges = int(s.get("max_watering_can_charges", 8))
	gs.selected_seed_type = String(s.get("selected_seed_type", "wheat"))
	gs.hard_energy = bool(s.get("hard_energy", false))
	gs.crows_scared = int(s.get("crows_scared", 0))
	gs.total_shipped = int(s.get("total_shipped", 0))
	gs._milestones_earned = s.get("milestones", {}).duplicate()

	gs.day_changed.emit(gs.day)
	gs.energy_changed.emit(gs.energy)
	gs.gold_changed.emit(gs.gold)
	gs.weather_changed.emit(gs.weather)
	gs.tool_changed.emit(gs.selected_tool)
	return true


# Version chain: v(n) saves are migrated stepwise to VERSION here.
# Unknown/future versions return {} (caller treats as unloadable).
static func migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	if v == VERSION:
		return data
	# future: if v == 1: data = _migrate_1_to_2(data); ...
	return {}


static func save_to(path: String, world: SimWorld, gs) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(capture(world, gs)))
	return true


# Canonical string form of a capture for equality checks. Excludes
# presentation-only fields (selected tool/seed) — they are not Actions and
# not sim truth, so replays legitimately differ on them.
static func capture_canonical(world: SimWorld, gs) -> String:
	var c := capture(world, gs)
	var s: Dictionary = c.get("state", {})
	s.erase("selected_tool")
	s.erase("selected_seed_type")
	return JSON.stringify(c)


static func load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


# Shared verification: does a session's action log reproduce this save exactly?
# Used by tools/verify_replay.gd and tools/robot_session.gd.
static func replay_matches(rlog: ReplayLog, save: Dictionary) -> bool:
	var gs_replay = load("res://systems/game_state.gd").new()
	var world_replay := SimWorld.new()
	rlog.apply_to(world_replay, gs_replay)
	var gs_save = load("res://systems/game_state.gd").new()
	var world_save := SimWorld.new()
	restore(save, world_save, gs_save)
	var matched := capture_canonical(world_replay, gs_replay) == capture_canonical(world_save, gs_save)
	gs_replay.free()
	gs_save.free()
	return matched


# JSON turns ints into floats and has no bool guarantees across tools;
# normalize so a loaded save is value-identical to a live one.
static func _normalize_tile(tile) -> Dictionary:
	return {
		"state": String(tile.get("state", "cleared")),
		"crop_type": String(tile.get("crop_type", "")),
		"growth_stage": int(tile.get("growth_stage", 0)),
		"watered_today": bool(tile.get("watered_today", false)),
	}


static func _int_values(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[k] = int(d[k])
	return out

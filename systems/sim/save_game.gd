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
			"milestones": gs._milestones_earned.duplicate(),
		},
	}


static func restore(data: Dictionary, world: SimWorld, gs) -> bool:
	var d := migrate(data)
	if d.is_empty():
		return false

	var w: Dictionary = d.get("world", {})
	world.tiles.clear()
	for row in w.get("tiles", []):
		var r: Array = []
		for tile in row:
			r.append(_normalize_tile(tile))
		world.tiles.append(r)
	world.objects.clear()
	for row in w.get("objects", []):
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


static func load_from(path: String, world: SimWorld, gs) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return false
	return restore(data, world, gs)


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

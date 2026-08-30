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
			# Per-actor energy (designer, 2026-08-29): every actor has its own
			# meter, and only the player's is also the clock. World state rather
			# than player state, so it lives here beside the grids.
			"actor_energy": world.actor_energy.duplicate(),
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
			"crows_seen": gs.crows_seen,
			"crop_crows_seen": gs.crop_crows_seen,
			"tools_owned": gs.tools_owned.duplicate(),
			"takeover_day": gs.takeover_day,
			"clear_counts": gs.clear_counts.duplicate(),
			"actions_today": gs.actions_today,
			"crow_schedule": gs.crow_schedule.duplicate(),
			"total_shipped": gs.total_shipped,
			"seeds_bought": gs.seeds_bought,
			"cans_refilled": gs.cans_refilled,
			"phase1_complete": gs.phase1_complete,
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
	# Additive: a save written before per-actor energy existed simply has nobody
	# on record, which reads as everybody rested — true of the builds that wrote it.
	world.actor_energy = _int_values(w.get("actor_energy", {}))

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
	# Defaulted, so pre-T-2 saves load unchanged and simply get a harmless first crow.
	gs.crows_seen = int(s.get("crows_seen", 0))
	# Additive M1.5 fields, all chosen so a pre-M1.5 save loads and plays. Tools
	# default to **owned**, because every save written before T-9 was written by a
	# build where she had all six — restoring one into a farm that has confiscated
	# her axe would be a bug wearing a migration's clothes. No VERSION bump: these
	# are additive keys in the existing schema (docs/ARCHITECTURE.md).
	gs.crop_crows_seen = int(s.get("crop_crows_seen", 0))
	var owned: Dictionary = {}
	for t in Tools.LIST:
		owned[t.key] = true
	for k in s.get("tools_owned", {}).keys():
		owned[k] = bool(s["tools_owned"][k])
	gs.tools_owned = owned
	# 1 means "the world began the day she did", which is exactly true of every
	# save written before the cold open existed.
	gs.takeover_day = int(s.get("takeover_day", 1))
	gs.clear_counts = _int_values(s.get("clear_counts", {}))
	gs.actions_today = int(s.get("actions_today", 0))
	# Reloading mid-day must neither resurrect a crow already shooed nor erase one
	# still owed, so the remaining schedule is part of the save.
	var sched: Array[int] = []
	for v in s.get("crow_schedule", []):
		sched.append(int(v))
	gs.crow_schedule = sched
	gs.total_shipped = int(s.get("total_shipped", 0))
	# T-11, additive: a save from before these existed reads as "never done it",
	# so an old farm gets the teaching beat once rather than never.
	gs.seeds_bought = int(s.get("seeds_bought", 0))
	gs.cans_refilled = int(s.get("cans_refilled", 0))
	gs.phase1_complete = bool(s.get("phase1_complete", false))
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


# Progression figures for the title screen's Continue card. Lives here because
# it is a read over the save schema; returns {} for anything unreadable so the
# caller can offer a fresh start instead of a Continue that cannot load.
static func summarize(data: Dictionary) -> Dictionary:
	if data.is_empty() or not data.has("state") or typeof(data["state"]) != TYPE_DICTIONARY:
		return {}
	var s: Dictionary = data["state"]
	return {
		"day": int(s.get("day", 1)),
		"gold": int(s.get("gold", 0)),
		"shipped": int(s.get("total_shipped", 0)),
		"scared": int(s.get("crows_scared", 0)),
		"phase1": bool(s.get("phase1_complete", false)),
	}


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

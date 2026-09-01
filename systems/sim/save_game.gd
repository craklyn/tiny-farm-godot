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
			# Who is in the world and where (M2.5 WI-2, D-9/Q-53). Additive in
			# exactly the way `actor_energy` and `tick` were: a save without this
			# key default-spawns on load (see restore), so no VERSION bump.
			#
			# This absorbs the old `actor_energy` map — every actor has its own
			# meter (designer, 2026-08-29) and the meter now rides inside its
			# registry entry, so it is written once, beside the position it
			# belongs to. The old key is still *read* below, for saves that have
			# one; it is no longer written.
			"actors": _capture_actors(world),
			# Sim time (M2.5 WI-1). Additive, same pattern as actor_energy above:
			# a save written before the clock existed simply has no tick, which
			# reads as 0 — true of every build that wrote one.
			# **Pending events are not saved.** Nothing schedules any yet; when
			# something does (WI-3), events carry Callables, which do not
			# serialize, so persisting them is its own design rather than a key
			# added here in advance of a need.
			"tick": world.clock.tick,
			# The scent layer (P-10, M2.5 WI-7). Additive in the same way again: a
			# save written before it existed has no field, and reads as a clean one
			# — which is what every farm in the game holds today, since no shipping
			# species writes scent yet. Only *written* cells are stored, so this is
			# `{}` on an unmarked farm and never a grid of zeroes.
			"scent": world.scent.to_save(),
			# The seed this world came from (M2.5 WI-5). Additive, the same way
			# again: absent ⇒ 0 ⇒ "unknown", which is what every save written
			# before this field says, and those load and play exactly as before.
			# It is here because `SimRng.stateless()` derives every per-day draw
			# from the current seed, so a farm that cannot say which seed it came
			# from cannot be continued *or* replayed faithfully — the hole WI-3's
			# closing note filed and this closes.
			"gen_seed": world.gen_seed,
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
			# What she has picked up off the ground herself (T-30 / Q-48).
			# Additive, like every field below it: absent ⇒ 0, which is what every
			# save written before acorns could be picked up means.
			"acorns": gs.acorns,
			"tools_owned": gs.tools_owned.duplicate(),
			"takeover_day": gs.takeover_day,
			"clear_counts": gs.clear_counts.duplicate(),
			"actions_today": gs.actions_today,
			"crow_schedule": gs.crow_schedule.duplicate(),
			# The raid's appointment book (M2.5 WI-8a). Additive, and empty in
			# every save this build writes — `ANT_RAIDS_PER_DAY` is 0 — but a raid
			# reloaded mid-column has to know it already used its chance for the
			# day, for the same reason the crow's schedule is here.
			"ant_schedule": gs.ant_schedule.duplicate(),
			# ...and the book everybody after the ants shares (M2.5 WI-8c/8f/8g).
			# Additive, and `{}` in every save this build writes — every `per_day`
			# in `SimWorld.visitors()` is 0 — but a rabbit reloaded mid-nibble has
			# to know its visit was already this day's, for the crow's reason.
			"visitor_schedules": _copy_schedules(gs.visitor_schedules),
			"total_shipped": gs.total_shipped,
			"seeds_bought": gs.seeds_bought,
			"cans_refilled": gs.cans_refilled,
			"phase1_complete": gs.phase1_complete,
			"milestones": gs._milestones_earned.duplicate(),
		},
	}


# The visitors' book, out and back (M2.5 WI-8c/8f/8g). Both directions are a
# deep copy with the ints coerced, for the reason every other collection here is:
# a save must not hand out a reference into the live GameState, and JSON hands
# back floats where the sim keeps `Array[int]`.
static func _copy_schedules(book: Dictionary) -> Dictionary:
	var out := {}
	for species in book.keys():
		var days: Array = book[species]
		out[String(species)] = days.duplicate()
	return out


static func _restore_schedules(raw) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for species in raw.keys():
		var days: Array[int] = []
		var listed = raw[species]
		if listed is Array:
			for v in listed:
				days.append(int(v))
		out[String(species)] = days
	return out


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
	# The actor registry (M2.5 WI-2). Grids first, deliberately: the default spawn
	# below reads the restored world — the gate tells it whether the neighbour is
	# still here, the walkable tiles tell it where the hen can stand.
	# Sim time comes back before the cast does, and it matters which way round:
	# `reset()` empties the clock's queue, and spawning an actor schedules that
	# actor's first thought on it (M2.5 WI-3). Resetting afterwards would throw
	# every one of those away and leave a reloaded farm standing perfectly still.
	world.clock.reset(int(w.get("tick", 0)))
	# Which seed this farm came from (M2.5 WI-5). Restored, never *applied*: a load
	# must not reach out and reseed the process — `SaveGame.restore` is called by
	# tests and by the attract loop, and a global side effect from a read would be
	# a landmine. Whoever owns the session does the reseeding, at the session
	# boundary where the one raw `randi()` already lives (`main.gd`, and
	# `ReplayLog.apply_to` for a replay of one).
	world.gen_seed = int(w.get("gen_seed", 0))
	# ...and the scent layer with it (M2.5 WI-7), before the cast: a restored trail
	# is part of the world its actors wake up into. Absent ⇒ a clean field.
	world.scent.from_save(w.get("scent", {}))
	var saved_actors: Dictionary = w.get("actors", {})
	# Empty counts as absent: a world containing nobody at all is not a state
	# anything produces (the player is always registered), so reading it as a
	# save from before the registry is the more useful of the two answers.
	if saved_actors.is_empty():
		# Pre-M2.5 save: nobody on record, so the world gets the cast it would
		# have had under the build that wrote it — the player at her spawn, the
		# hen on the farm, the neighbour if her scene never finished. Placed by
		# rule rather than by a draw, because a load must not consume the shared
		# RNG stream (see SimWorld.spawn_default_actors).
		world.spawn_default_actors(false)
		# Compat shim: such a save recorded NPC tiredness in its own `actor_energy`
		# map. Energy lives in the registry now, so the old map is folded into it —
		# but only for actors this world still contains. A save written after the
		# cold open finished carries the neighbour's meter and she is gone;
		# restoring a meter would be the one way to put a departed actor back.
		var legacy_energy := _int_values(w.get("actor_energy", {}))
		for id in legacy_energy:
			if world.has_actor(id):
				world.set_actor_energy(id, int(legacy_energy[id]))
	else:
		world.actors = _restore_actors(saved_actors)
		# A restored registry did not go through spawn_actor, so nobody is on the
		# clock yet. This is the one call that makes a loaded farm alive.
		world.schedule_all_brains()

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
	gs.acorns = int(s.get("acorns", 0))  # T-30 (Q-48); absent ⇒ she has none
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
	# Same again for the raid (M2.5 WI-8a); absent ⇒ no raid owed, which is what
	# every save written before this field means and what every save written
	# after it says anyway.
	var ants: Array[int] = []
	for v in s.get("ant_schedule", []):
		ants.append(int(v))
	gs.ant_schedule = ants
	# ...and everybody else's; absent ⇒ nobody is owed a visit, which is what
	# every save written before this field means and what every save written
	# after it says anyway.
	gs.visitor_schedules = _restore_schedules(s.get("visitor_schedules", {}))
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
#
# **The WI-3 seam is closed here** (M2.5 WI-5). WI-3 took the tick counter and
# every actor's `pos`/`facing`/`extra` out of this comparison, because brains had
# started moving them during live play while a v1 replay had no tick information
# at all and could not recompute the motion. Format v2 stamps every entry with
# the tick it happened on, and `ReplayLog.apply_to` now advances the clock
# through those ticks and lives out the session's remaining sim time, so a replay
# *does* recompute the motion — and this compares it. A hen who ends the session
# on a different tile than the one the save recorded is now a failure, which is
# the point: it is the strongest statement the repo can make that the
# recomputation is the recording.
#
# **And the last residue with it** (M2.5 WI-6). The player was excluded from this
# comparison for as long as her position was not sim truth: she walked in pixels,
# nothing wrote her tile into the registry, and so both sides held her spawn tile
# and comparing them asserted nothing. Her tile crossings write the registry now
# and are recorded as free-walk entries that `ReplayLog._apply_v2` applies back,
# so the comparison is **total**: every actor the world contains, position,
# facing, meter and scratch, plus the clock — nothing is erased here but the two
# presentation fields below, which are not Actions and never were sim truth.
#
# `capture()` itself is untouched: a **save** still stores every position and the
# tick, because a save is a snapshot and a snapshot knows where everybody was.
static func capture_canonical(world: SimWorld, gs) -> String:
	var c := capture(world, gs)
	var s: Dictionary = c.get("state", {})
	s.erase("selected_tool")
	s.erase("selected_seed_type")
	return _canonical_text(c)


# Comparison text, with one normalization: everything goes through JSON and back
# before being written out (M2.5 WI-5).
#
# It exists because half of what this compares is a **live** world and half is one
# **restored from disk**, and JSON has one number type. A brain's scratch state
# (`extra`) holds honest integers live — `wake: 43`, `step: 4` — and comes back
# from a save as `43.0` and `4.0`, so without this the two stringify differently
# and every replay of a session with a walking hen in it fails on a difference
# that is an artifact of the file format rather than a fact about the farm. One
# round trip puts both sides in the same shape. It normalizes nothing else: key
# order was already canonical (`JSON.stringify` sorts), and a value that differs
# still differs.
static func _canonical_text(c: Dictionary) -> String:
	var text := JSON.stringify(c)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return text  # unparseable (a NaN somewhere): compare the raw form, never "null"
	return JSON.stringify(parsed)


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
	return replay_report(rlog, save).get("matched", false)


# The same check with its reasons attached (M2.5 WI-5). A v2 replay can fail in
# two different places and they mean different things: `divergence` is the
# dual-record net — a brain recomputed something other than what it did live,
# named down to the entry — while a bare state mismatch says the end states
# differ without saying where. Reporting both is what makes a failure a
# diagnosis; the tools print it.
static func replay_report(rlog: ReplayLog, save: Dictionary) -> Dictionary:
	var gs_replay = load("res://systems/game_state.gd").new()
	var world_replay := SimWorld.new()
	rlog.apply_to(world_replay, gs_replay)
	var gs_save = load("res://systems/game_state.gd").new()
	var world_save := SimWorld.new()
	restore(save, world_save, gs_save)
	var same_state := capture_canonical(world_replay, gs_replay) \
		== capture_canonical(world_save, gs_save)
	gs_replay.free()
	gs_save.free()
	return {
		"matched": same_state and rlog.divergence == "",
		"state_matched": same_state,
		"divergence": rlog.divergence,
	}


# The registry, flattened for JSON — which has no Vector2i, so a tile becomes
# x/y. Key order is not preserved and does not need to be: `JSON.stringify` sorts
# keys, which is what lets `capture_canonical` compare a live world against the
# same world restored (they hold their actors in different orders — see the
# registry block in sim_world.gd).
#
# **A visit is not saved** (M2.5 WI-3). Species whose row says `persistent: false`
# — the crow, today — are skipped: a save is a snapshot of a farm, and a bird
# halfway across the sky on the frame the autosave timer happened to fire is not
# part of one. Reloading has never restored a crow (it was a node), its schedule
# entry for the day is already spent, and T-20 says one arrival is one arrival.
# The alternative is worse in both directions: persisting it would resurrect a
# bird mid-flight with a stale target, and comparing it would fail a replay for a
# bird the replay was never asked to fly.
static func _capture_actors(world: SimWorld) -> Dictionary:
	var out := {}
	for id in world.actors:
		var a: Dictionary = world.actors[id]
		if not SpeciesDefs.is_persistent(String(a.get("species", ""))):
			continue
		var pos: Vector2i = a.get("pos", Vector2i(-1, -1))
		out[id] = {
			"species": String(a.get("species", "")),
			"x": pos.x,
			"y": pos.y,
			"facing": String(a.get("facing", "down")),
			"energy": int(a.get("energy", SimWorld.ACTOR_MAX_ENERGY)),
			"extra": a.get("extra", {}).duplicate(true),
		}
	return out


# ...and back, with the same normalization the tiles get: JSON hands back floats,
# and a live registry holds ints and a Vector2i.
static func _restore_actors(raw: Dictionary) -> Dictionary:
	var out := {}
	for id in raw.keys():
		var a = raw[id]
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var extra = a.get("extra", {})
		out[String(id)] = {
			"species": String(a.get("species", "")),
			"pos": Vector2i(int(a.get("x", -1)), int(a.get("y", -1))),
			"facing": String(a.get("facing", "down")),
			"energy": int(a.get("energy", SimWorld.ACTOR_MAX_ENERGY)),
			"extra": extra.duplicate(true) if typeof(extra) == TYPE_DICTIONARY else {},
		}
	return out


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

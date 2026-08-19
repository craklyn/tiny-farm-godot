# sim_world.gd — Grid-truth simulation state (S-5, M2)
# Owns the farm's tile/object grids and every mutation of them; apply_action()
# is the single gateway every actor (player, crow, chicken, later bots) uses
# to change the world (S-3).
# Layer-2 rules (docs/ARCHITECTURE.md): no Node inheritance, no rendering,
# no autoload access, no Input — only SimRng (seeded) and CropDefs/Tools (data).
class_name SimWorld
extends RefCounted

const MAP_WIDTH := 32
const MAP_HEIGHT := 20

# Q-9 onboarding vignette tiles (inside the guaranteed-clear spawn band)
const VIGNETTE_WEED := Vector2i(4, 3)
const VIGNETTE_PLANT := Vector2i(6, 3)

# Fixed object positions (0-indexed tile coords)
const OBJECT_POSITIONS: Array[Dictionary] = [
	{ "type": "cot",          "tx": 2, "ty": 1 },
	{ "type": "shipping_bin", "tx": 4, "ty": 1 },
	{ "type": "well",         "tx": 6, "ty": 1 },
	{ "type": "seed_box",     "tx": 8, "ty": 1 },
]

# Tile data: tiles[y][x] = { state, crop_type, growth_stage, watered_today }
var tiles: Array[Array] = []
var objects: Array[Array] = []  # objects[y][x] = "" or object type string


func generate() -> void:
	tiles.clear()
	objects.clear()

	for ty in MAP_HEIGHT:
		var row: Array[Dictionary] = []
		var obj_row: Array[String] = []
		for tx in MAP_WIDTH:
			if ty == 0 or ty == MAP_HEIGHT - 1 or tx == 0 or tx == MAP_WIDTH - 1:
				row.append(_create_tile("border"))
			else:
				if SimRng.randf() < 0.25:
					var obstacle_types: Array[String] = ["obstacle_rock", "obstacle_log", "obstacle_weed"]
					row.append(_create_tile(obstacle_types[SimRng.randi() % 3]))
				else:
					row.append(_create_tile("cleared"))
			obj_row.append("")
		tiles.append(row)
		objects.append(obj_row)

	# Place fixed objects
	for obj in OBJECT_POSITIONS:
		var tx: int = obj.tx
		var ty: int = obj.ty
		tiles[ty][tx] = _create_tile("cleared")
		objects[ty][tx] = obj.type
		# Clear surrounding tiles
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := tx + dx
				var ny := ty + dy
				if nx >= 1 and nx <= MAP_WIDTH - 2 and ny >= 1 and ny <= MAP_HEIGHT - 2:
					if objects[ny][nx] == "":
						tiles[ny][nx] = _create_tile("cleared")

	# Ensure player spawn area is clear
	for dy in range(0, 3):
		for dx in range(0, 11):
			var tx := 1 + dx
			var ty := 1 + dy
			if tx <= MAP_WIDTH - 2 and ty <= MAP_HEIGHT - 2:
				if objects[ty][tx] == "":
					tiles[ty][tx] = _create_tile("cleared")

	# Q-9 onboarding vignette: one weed to clear, one tilled tile to plant and
	# water, in the spawn band. Part of seeded generation, so replays match.
	tiles[VIGNETTE_WEED.y][VIGNETTE_WEED.x] = _create_tile("obstacle_weed")
	tiles[VIGNETTE_PLANT.y][VIGNETTE_PLANT.x] = _create_tile("tilled")


func _create_tile(state: String) -> Dictionary:
	return {
		"state": state,
		"crop_type": "",
		"growth_stage": 0,
		"watered_today": false,
	}


func get_tile(tx: int, ty: int) -> Dictionary:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		return tiles[ty][tx]
	return {}


func get_crop_type(tx: int, ty: int) -> String:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return ""
	return tile.get("crop_type", "")


func get_object(tx: int, ty: int) -> String:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		if objects[ty][tx] != "":
			return objects[ty][tx]
		# Check if the tile below has a tall object
		if ty + 1 < MAP_HEIGHT and objects[ty + 1][tx] in ["cot", "well", "seed_box"]:
			return objects[ty + 1][tx]
	return ""


func set_object(tx: int, ty: int, obj_type: String) -> void:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		objects[ty][tx] = obj_type


func is_protected_by_scarecrow(tx: int, ty: int) -> bool:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var nx := tx + dx
			var ny := ty + dy
			if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
				if objects[ny][nx] == "scarecrow":
					return true
	return false


func is_walkable(tx: int, ty: int) -> bool:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return false
	var state: String = tile.state
	if state == "border":
		return false
	if state.begins_with("obstacle"):
		return false
	var obj := get_object(tx, ty)
	if obj != "" and obj != "egg":
		return false
	return true


func set_tile_state(tx: int, ty: int, new_state: String, crop_type: String = "") -> void:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return
	tile.state = new_state
	if crop_type != "":
		tile.crop_type = crop_type
	if new_state == "cleared" or new_state == "tilled":
		tile.crop_type = ""
		tile.growth_stage = 0
		tile.watered_today = false
	elif new_state == "seeded":
		tile.growth_stage = 0
		tile.watered_today = false


func water_tile(tx: int, ty: int) -> void:
	var tile := get_tile(tx, ty)
	if not tile.is_empty() and (tile.state == "seeded" or tile.state == "growing"):
		tile.watered_today = true


# --- Action gateway (S-3) -----------------------------------------------------
# action: { verb: String, target: Vector2i, seed_type: String, actor: String }
# gs: GameState (player/economy state) — required for verbs that touch it.
# Returns { ok: bool, reason: String, ...verb extras }. Mutation happens only
# on ok. Guards mirror the pre-M2 player checks exactly (no new validation yet).
# Verbs that can change milestone inputs (harvest counts, gold); other verbs
# skip the check — it dominated fast-forward throughput when run per action.
const MILESTONE_VERBS := { "harvest": true, "collect": true, "sell": true, "sleep": true, "buy_seed": true }


func apply_action(action: Dictionary, gs = null) -> Dictionary:
	var result := _apply(action, gs)
	# Milestones are capability proofs (P-4) — sim truth, so replays earn them too
	if result.get("ok", false) and gs != null and MILESTONE_VERBS.has(action.get("verb", "")) \
			and gs.has_method("check_milestones"):
		gs.check_milestones()
	return result


func _apply(action: Dictionary, gs) -> Dictionary:
	var verb: String = action.get("verb", "")
	var target: Vector2i = action.get("target", Vector2i(-1, -1))

	match verb:
		# -- special-object verbs (no energy cost, pre-M2 behavior) --
		"sell":
			if gs == null: return _fail("no_state")
			return { "ok": gs.sell_crops_to_bin() }
		"refill":
			if gs == null: return _fail("no_state")
			return { "ok": gs.refill_watering_can() }
		"buy_seed":
			if gs == null: return _fail("no_state")
			return { "ok": gs.buy_seed(action.get("seed_type", "")) }
		"collect":
			if gs == null: return _fail("no_state")
			var obj := get_object(target.x, target.y)
			if obj == "egg":
				set_object(target.x, target.y, "")
				gs.crops["egg"] = gs.crops.get("egg", 0) + 1
				gs.harvest_counts["egg"] = gs.harvest_counts.get("egg", 0) + 1
				return { "ok": true, "collected": "egg" }
			if obj == "scarecrow":
				set_object(target.x, target.y, "")
				gs.seeds["scarecrow"] = gs.seeds.get("scarecrow", 0) + 1
				return { "ok": true, "collected": "scarecrow" }
			return _fail("nothing_to_collect")

		# -- day transition --
		"sleep":
			if gs == null: return _fail("no_state")
			gs.start_new_day()
			if action.has("weather"):  # replay override: reproduce the logged roll
				gs.weather = action.weather
				gs.weather_changed.emit(gs.weather)
			advance_day(gs.weather)
			gs.process_shipping_bin()
			# Q-12/P-4: silent capability proof, measured at sleep; the flag
			# flips once, and the result tells presentation to celebrate
			var newly_complete := false
			if not gs.phase1_complete and _phase1_proof_met(gs):
				gs.phase1_complete = true
				newly_complete = true
			return { "ok": true, "day": gs.day, "weather": gs.weather, "phase1_complete_now": newly_complete }

		# -- entity verbs --
		"eat_crop":
			var tile := get_tile(target.x, target.y)
			if tile.is_empty(): return _fail("out_of_bounds")
			if tile.state in ["growing", "ready", "seeded"]:
				set_tile_state(target.x, target.y, "tilled")
				return { "ok": true }
			return _fail("no_crop")
		"lay_egg":
			if get_object(target.x, target.y) != "": return _fail("occupied")
			set_object(target.x, target.y, "egg")
			return { "ok": true }
		"crow_scared":
			# Player-caused scare event; feeds the Q-12 capability proof
			if gs == null: return _fail("no_state")
			gs.crows_scared += 1
			return { "ok": true }

		# -- energy-costed tile verbs --
		"clear_weed", "clear_log", "clear_rock", "till", "plant", "water", "harvest":
			if gs == null: return _fail("no_state")
			var tile := get_tile(target.x, target.y)
			if tile.is_empty() or tile.get("state", "") == "": return _fail("out_of_bounds")
			var cost: int = Tools.get_energy_cost(verb)
			# Q-11 soft floor: in phase 1 an empty tank never blocks the action,
			# it just stays at 0 (presentation slows the farmer as the nudge)
			if gs.hard_energy and gs.energy < cost: return _fail("no_energy")
			var seed_type: String = action.get("seed_type", "")
			if verb == "water" and gs.watering_can_charges <= 0: return _fail("no_water")
			if verb == "plant" and gs.seeds.get(seed_type, 0) <= 0: return _fail("no_seeds")

			gs.energy = maxi(0, gs.energy - cost)
			match verb:
				"clear_weed", "clear_log", "clear_rock":
					set_tile_state(target.x, target.y, "cleared")
				"till":
					set_tile_state(target.x, target.y, "tilled")
				"plant":
					var is_obj: bool = CropDefs.TYPES.get(seed_type, {}).get("is_object", false)
					if is_obj:
						set_object(target.x, target.y, seed_type)
					else:
						set_tile_state(target.x, target.y, "seeded", seed_type)
					gs.seeds[seed_type] -= 1
				"water":
					water_tile(target.x, target.y)
					gs.watering_can_charges -= 1
				"harvest":
					var crop_type := get_crop_type(target.x, target.y)
					if crop_type != "":
						gs.crops[crop_type] = gs.crops.get(crop_type, 0) + 1
						gs.harvest_counts[crop_type] = gs.harvest_counts.get(crop_type, 0) + 1
						set_tile_state(target.x, target.y, "cleared")
						return { "ok": true, "crop_type": crop_type }
			return { "ok": true }

	return _fail("unknown_verb")


func _fail(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason }


# Q-12 phase-1 proof thresholds — provisional, fine-tuned at playtest
const PHASE1_SHIPPED_TARGET := 20
const PHASE1_SCARED_TARGET := 3


func _phase1_proof_met(gs) -> bool:
	if gs.total_shipped < PHASE1_SHIPPED_TARGET:
		return false
	if gs.crows_scared < PHASE1_SCARED_TARGET:
		return false
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			if String(tiles[ty][tx].get("state", "")).begins_with("obstacle"):
				return false
	return true


func advance_day(weather: String) -> void:
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			var tile: Dictionary = tiles[ty][tx]
			if tile.watered_today and (tile.state == "seeded" or tile.state == "growing"):
				tile.growth_stage += 1
				if tile.state == "seeded":
					tile.state = "growing"
				if CropDefs.is_ready(tile.crop_type, tile.growth_stage):
					tile.state = "ready"
			tile.watered_today = false

			if weather == "rainy" and tile.state in ["tilled", "seeded", "growing"]:
				tile.watered_today = true

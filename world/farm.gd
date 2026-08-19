# farm.gd — Renderer + facade over SimWorld (M2)
# Grid truth lives in systems/sim/sim_world.gd; this node draws it with
# sprite atlases and forwards the old farm API to the sim so call sites
# (player, entities, ActionRouter, Pathfinding, tests) are unchanged.
extends Node2D

const TILE_SIZE := 16
const MAP_WIDTH := SimWorld.MAP_WIDTH
const MAP_HEIGHT := SimWorld.MAP_HEIGHT

var sim: SimWorld = SimWorld.new()
var replay: ReplayLog = null  # set via start_replay_log(); records every ok action

# Facade views over sim truth (same Array references — in-place mutation works)
var tiles: Array[Array]:
	get:
		return sim.tiles
var objects: Array[Array]:
	get:
		return sim.objects

# Sprite resources
var tileset_texture: Texture2D
var crops_texture: Texture2D
var objects_texture: Texture2D

# Quad regions (Rect2 for atlas lookups)
var tile_regions: Dictionary = {}     # state_name -> Rect2
var crop_regions: Dictionary = {}     # crop_type -> { stage -> Rect2 }
var object_regions: Dictionary = {}   # object_name -> Rect2

func _ready() -> void:
	_load_textures()
	sim.generate()


var dirt_texture: Texture2D
var biomes_texture: Texture2D
var furniture_texture: Texture2D
var chest_texture: Texture2D

func _load_textures() -> void:
	tileset_texture = load("res://assets/sprites/sprout_lands/grass.png")
	dirt_texture = load("res://assets/sprites/sprout_lands/dirt.png")
	crops_texture = load("res://assets/sprites/sprout_lands/crops.png")
	objects_texture = load("res://assets/sprites/sprout_lands/tools.png") # Kept just in case
	biomes_texture = load("res://assets/sprites/sprout_lands/biomes.png")
	furniture_texture = load("res://assets/sprites/sprout_lands/furniture.png")
	chest_texture = load("res://assets/sprites/sprout_lands/chest.png")

	# Tile regions (mapping obstacles to biomes.png)
	tile_regions["obstacle_rock"] = Rect2(5 * 16, 4 * 16, 16, 16)
	tile_regions["obstacle_log"] = Rect2(4 * 16, 2 * 16, 16, 16)
	tile_regions["obstacle_weed"] = Rect2(0 * 16, 0 * 16, 16, 16)
	tile_regions["border"] = Rect2(0 * 16, 0 * 16, 16, 16)

	# Crop regions: 4 columns x 3 rows
	crop_regions["wheat"] = {}
	crop_regions["tomato"] = {}
	for stage in 4: crop_regions["wheat"][stage] = Rect2(stage * 16, 1 * 16, 16, 16)
	for stage in 6: crop_regions["tomato"][stage] = Rect2(stage * 16, 3 * 16, 16, 16)

	# Object regions map
	# Format: object_name -> [texture, rect]
	object_regions["cot"] = [furniture_texture, Rect2(0 * 16, 0 * 16, 16, 32)]
	object_regions["well"] = [furniture_texture, Rect2(4 * 16, 0 * 16, 16, 32)]
	object_regions["shipping_bin"] = [chest_texture, Rect2(1 * 16, 1 * 16, 16, 16)]
	object_regions["seed_box"] = [furniture_texture, Rect2(5 * 16, 2 * 16, 16, 32)]
	object_regions["scarecrow"] = [crops_texture, Rect2(0 * 16, 4 * 16, 16, 16)]


# --- Facade: forwards the old farm API to SimWorld ---------------------------

func start_replay_log(gen_seed: int) -> void:
	replay = ReplayLog.new()
	replay.start(gen_seed)


func start_replay_log_from_save(save_data: Dictionary) -> void:
	replay = ReplayLog.new()
	replay.start_from_save(save_data)


func apply_action(action: Dictionary, gs = null) -> Dictionary:
	var result := sim.apply_action(action, gs)
	if result.get("ok", false):
		if replay != null:
			replay.record(action, result)
		queue_redraw()
	return result


func get_tile(tx: int, ty: int) -> Dictionary:
	return sim.get_tile(tx, ty)


func get_crop_type(tx: int, ty: int) -> String:
	return sim.get_crop_type(tx, ty)


func get_object(tx: int, ty: int) -> String:
	return sim.get_object(tx, ty)


func set_object(tx: int, ty: int, obj_type: String) -> void:
	sim.set_object(tx, ty, obj_type)
	queue_redraw()


func is_protected_by_scarecrow(tx: int, ty: int) -> bool:
	return sim.is_protected_by_scarecrow(tx, ty)


func is_walkable(tx: int, ty: int) -> bool:
	return sim.is_walkable(tx, ty)


func set_tile_state(tx: int, ty: int, new_state: String, crop_type: String = "") -> void:
	sim.set_tile_state(tx, ty, new_state, crop_type)
	queue_redraw()


func water_tile(tx: int, ty: int) -> void:
	sim.water_tile(tx, ty)
	queue_redraw()


func advance_day() -> void:
	var weather := "sunny"
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("GameState"):
		weather = Engine.get_main_loop().root.get_node("GameState").weather
	sim.advance_day(weather)
	queue_redraw()


func _draw() -> void:
	var BITMASK_MAP: Array[Vector2i] = [
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(3, 3), 	Vector2i(0, 4), 	Vector2i(3, 3), 	Vector2i(0, 2),
		Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(2, 6), 	Vector2i(2, 6), 	Vector2i(3, 6), 	Vector2i(0, 5),
		Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(2, 6), 	Vector2i(2, 6), 	Vector2i(3, 6), 	Vector2i(2, 6),
		Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(2, 6), 	Vector2i(1, 7), 	Vector2i(3, 6), 	Vector2i(1, 7),
		Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(2, 6), 	Vector2i(1, 7), 	Vector2i(3, 6), 	Vector2i(1, 7),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(3, 3), 	Vector2i(0, 4), 	Vector2i(3, 3), 	Vector2i(2, 2),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(3, 3), 	Vector2i(0, 4), 	Vector2i(3, 3), 	Vector2i(1, 2),
		Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(2, 6), 	Vector2i(2, 6), 	Vector2i(3, 6), 	Vector2i(0, 5),
		Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(3, 6), 	Vector2i(0, 5), 	Vector2i(2, 6), 	Vector2i(2, 6), 	Vector2i(3, 6), 	Vector2i(2, 6),
		Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(2, 6), 	Vector2i(1, 7), 	Vector2i(3, 6), 	Vector2i(1, 7),
		Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(3, 6), 	Vector2i(0, 4), 	Vector2i(2, 6), 	Vector2i(1, 7), 	Vector2i(3, 6), 	Vector2i(1, 7),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(1, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5),
		Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4), 	Vector2i(0, 3), 	Vector2i(0, 4),
		Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(0, 6), 	Vector2i(0, 5), 	Vector2i(3, 3), 	Vector2i(0, 4), 	Vector2i(3, 3), 	Vector2i(2, 3)
	]

	var render_queue: Array[Dictionary] = []

	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			var tile: Dictionary = tiles[ty][tx]
			var px := tx * TILE_SIZE
			var py := ty * TILE_SIZE

			# Draw Grass background always
			draw_texture_rect_region(tileset_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), Rect2(16, 16, 16, 16))

			# Draw Tilled Dirt if applicable
			if tile.state in ["tilled", "seeded", "growing", "ready"]:
				var mask := 0
				var c_n = ty > 0 and tiles[ty-1][tx].state in ["tilled", "seeded", "growing", "ready"]
				var c_e = tx < MAP_WIDTH - 1 and tiles[ty][tx+1].state in ["tilled", "seeded", "growing", "ready"]
				var c_s = ty < MAP_HEIGHT - 1 and tiles[ty+1][tx].state in ["tilled", "seeded", "growing", "ready"]
				var c_w = tx > 0 and tiles[ty][tx-1].state in ["tilled", "seeded", "growing", "ready"]
				var c_ne = ty > 0 and tx < MAP_WIDTH - 1 and tiles[ty-1][tx+1].state in ["tilled", "seeded", "growing", "ready"]
				var c_se = ty < MAP_HEIGHT - 1 and tx < MAP_WIDTH - 1 and tiles[ty+1][tx+1].state in ["tilled", "seeded", "growing", "ready"]
				var c_sw = ty < MAP_HEIGHT - 1 and tx > 0 and tiles[ty+1][tx-1].state in ["tilled", "seeded", "growing", "ready"]
				var c_nw = ty > 0 and tx > 0 and tiles[ty-1][tx-1].state in ["tilled", "seeded", "growing", "ready"]

				if c_n: mask |= 1
				if c_n and c_e and c_ne: mask |= 2
				if c_e: mask |= 4
				if c_e and c_s and c_se: mask |= 8
				if c_s: mask |= 16
				if c_s and c_w and c_sw: mask |= 32
				if c_w: mask |= 64
				if c_w and c_n and c_nw: mask |= 128
				
				var coord: Vector2i = BITMASK_MAP[mask]
				# If watered, use the next 4x4 block to the right! (x + 4)
				var ox := 4 * 16 if tile.watered_today else 0
				draw_texture_rect_region(dirt_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), Rect2(coord.x * 16 + ox, coord.y * 16, 16, 16))

			# Queue obstacles
			if tile.state in ["border", "obstacle_rock", "obstacle_log", "obstacle_weed"]:
				var region: Rect2 = tile_regions.get(tile.state, Rect2())
				if region.size.x > 0:
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(biomes_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), region)
					})

			# Queue crops
			if tile.state in ["seeded", "growing", "ready"]:
				var stage = tile.growth_stage
				# clamp stage safely
				if tile.crop_type == "wheat": stage = min(stage, 3)
				var region: Rect2 = crop_regions[tile.crop_type].get(stage, Rect2())
				if region.size.x > 0:
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(crops_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), region)
					})

			# Queue objects
			var obj: String = objects[ty][tx]
			if obj == "egg":
				render_queue.append({
					"y": py,
					"draw": func(): 
						draw_rect(Rect2(px + 6, py + 8, 4, 6), Color.WHITE)
				})
			elif obj != "":
				var obj_data = object_regions.get(obj)
				if obj_data:
					var tex: Texture2D = obj_data[0]
					var region: Rect2 = obj_data[1]
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(tex, Rect2(px, py - (region.size.y - TILE_SIZE), region.size.x, region.size.y), region)
					})

	# Insert player into render queue if player exists
	var player = get_node_or_null("../Player")
	if player and player.has_method("queue_render"):
		player.queue_render(self, render_queue)

	# Insert entities into render queue
	var entities = get_node_or_null("../Entities")
	if entities:
		for child in entities.get_children():
			if child.has_method("queue_render"):
				child.queue_render(self, render_queue)

	# Inject insertion order for stable sorting
	for i in range(render_queue.size()):
		if not render_queue[i].has("order"):
			render_queue[i]["order"] = i

	# Sort by Y-coordinate (using order as tie-breaker)
	render_queue.sort_custom(func(a, b): 
		if a.y == b.y:
			return a.order < b.order
		return a.y < b.y
	)

	# Execute drawing commands
	for entity in render_queue:
		entity.draw.call()



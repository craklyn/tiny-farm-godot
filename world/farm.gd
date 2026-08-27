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
var generate_on_ready := true  # main disables this when a save restore is pending

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

# Quad regions (Rect2 for atlas lookups)
var tile_regions: Dictionary = {}     # state_name -> Rect2
var crop_regions: Dictionary = {}     # crop_type -> { stage -> Rect2 }
var object_regions: Dictionary = {}   # object_name -> Rect2

func _ready() -> void:
	_load_textures()
	if generate_on_ready:
		sim.generate()


var dirt_texture: Texture2D
var biomes_texture: Texture2D
var furniture_texture: Texture2D
var chest_texture: Texture2D
var animals_texture: Texture2D

func _load_textures() -> void:
	# Generated sheets (see CREDITS.md — AI-generated via Retro Diffusion).
	# terrain_grass: 3x3 of the seamless grass tile; draw code reads (16,16).
	# terrain_dirt: one tile per neighbour mask (world/autotile.gd), watered at +16 cols.
	tileset_texture = load("res://assets/sprites/generated/terrain_grass.png")
	dirt_texture = load("res://assets/sprites/generated/terrain_dirt.png")
	crops_texture = load("res://assets/sprites/generated/crops.png")
	biomes_texture = load("res://assets/sprites/generated/obstacles.png")
	furniture_texture = load("res://assets/sprites/generated/objects.png")
	chest_texture = furniture_texture
	animals_texture = load("res://assets/sprites/generated/animals.png")

	# Tile regions (obstacles.png: rock, log, weed)
	tile_regions["obstacle_rock"] = Rect2(0 * 16, 0, 16, 16)
	tile_regions["obstacle_log"] = Rect2(1 * 16, 0, 16, 16)
	tile_regions["obstacle_weed"] = Rect2(2 * 16, 0, 16, 16)
	tile_regions["border"] = Rect2(2 * 16, 0, 16, 16)

	# Crop regions (crops.png: row 0 wheat, row 1 tomato, 4 visual stages each)
	crop_regions["wheat"] = {}
	crop_regions["tomato"] = {}
	for stage in 4: crop_regions["wheat"][stage] = Rect2(stage * 16, 0 * 16, 16, 16)
	for stage in 4: crop_regions["tomato"][stage] = Rect2(stage * 16, 1 * 16, 16, 16)

	# Object regions map (objects.png: cot, well, seed_box 16x32; bin 16x16)
	# Format: object_name -> [texture, rect]
	object_regions["cot"] = [furniture_texture, Rect2(0 * 16, 0, 16, 32)]
	object_regions["well"] = [furniture_texture, Rect2(1 * 16, 0, 16, 32)]
	object_regions["shipping_bin"] = [chest_texture, Rect2(3 * 16, 16, 16, 16)]
	object_regions["seed_box"] = [furniture_texture, Rect2(2 * 16, 0, 16, 32)]
	object_regions["scarecrow"] = [crops_texture, Rect2(2 * 16, 2 * 16, 16, 16)]


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


# Out-of-bounds counts as not-soil, so plots edge correctly against the map border.
func _is_soil_at(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= MAP_WIDTH or ty >= MAP_HEIGHT:
		return false
	return Autotile.is_soil(tiles[ty][tx].state)


func _draw() -> void:
	var render_queue: Array[Dictionary] = []

	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			var tile: Dictionary = tiles[ty][tx]
			var px := tx * TILE_SIZE
			var py := ty * TILE_SIZE

			# Draw Grass background always
			draw_texture_rect_region(tileset_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), Rect2(16, 16, 16, 16))

			# Draw tilled soil, edge-matched to its neighbours (see world/autotile.gd)
			if Autotile.is_soil(tile.state):
				var mask := Autotile.compute_mask(
					_is_soil_at(tx, ty - 1), _is_soil_at(tx + 1, ty - 1),
					_is_soil_at(tx + 1, ty), _is_soil_at(tx + 1, ty + 1),
					_is_soil_at(tx, ty + 1), _is_soil_at(tx - 1, ty + 1),
					_is_soil_at(tx - 1, ty), _is_soil_at(tx - 1, ty - 1))
				var coord := Autotile.atlas_coord(mask, tile.watered_today)
				draw_texture_rect_region(dirt_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE),
					Rect2(coord.x * 16, coord.y * 16, 16, 16))

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
						# animals.png cell 11
						draw_texture_rect_region(animals_texture,
							Rect2(px, py, TILE_SIZE, TILE_SIZE), Rect2(11 * 16, 0, 16, 16))
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



# farm.gd — Tile grid with state machine + rendering
# Mirrors the Love2D tilemap.lua: manages a 2D array of tile data,
# draws tiles/crops/objects using sprite atlases, handles day advancement
extends Node2D

const TILE_SIZE := 16
const MAP_WIDTH := 32
const MAP_HEIGHT := 20

# Tile data: tiles[y][x] = { state, crop_type, growth_stage, watered_today }
var tiles: Array[Array] = []
var objects: Array[Array] = []  # objects[y][x] = "" or object type string

# Sprite resources
var tileset_texture: Texture2D
var crops_texture: Texture2D
var objects_texture: Texture2D

# Quad regions (Rect2 for atlas lookups)
var tile_regions: Dictionary = {}     # state_name -> Rect2
var crop_regions: Dictionary = {}     # crop_type -> { stage -> Rect2 }
var object_regions: Dictionary = {}   # object_name -> Rect2

# Fixed object positions (0-indexed tile coords)
const OBJECT_POSITIONS: Array[Dictionary] = [
	{ "type": "cot",          "tx": 2, "ty": 1 },
	{ "type": "shipping_bin", "tx": 4, "ty": 1 },
	{ "type": "well",         "tx": 6, "ty": 1 },
	{ "type": "seed_box",     "tx": 8, "ty": 1 },
]


func _ready() -> void:
	_load_textures()
	_init_grid()


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


func _init_grid() -> void:
	tiles.clear()
	objects.clear()

	for ty in MAP_HEIGHT:
		var row: Array[Dictionary] = []
		var obj_row: Array[String] = []
		for tx in MAP_WIDTH:
			if ty == 0 or ty == MAP_HEIGHT - 1 or tx == 0 or tx == MAP_WIDTH - 1:
				row.append(_create_tile("border"))
			else:
				if randf() < 0.25:
					var obstacle_types: Array[String] = ["obstacle_rock", "obstacle_log", "obstacle_weed"]
					row.append(_create_tile(obstacle_types[randi() % 3]))
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
		queue_redraw()


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
	queue_redraw()


func water_tile(tx: int, ty: int) -> void:
	var tile := get_tile(tx, ty)
	if not tile.is_empty() and (tile.state == "seeded" or tile.state == "growing"):
		tile.watered_today = true
		queue_redraw()


func advance_day() -> void:
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
			
			var weather = "sunny"
			if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("GameState"):
				weather = Engine.get_main_loop().root.get_node("GameState").weather
			if weather == "rainy" and tile.state in ["tilled", "seeded", "growing"]:
				tile.watered_today = true
				
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



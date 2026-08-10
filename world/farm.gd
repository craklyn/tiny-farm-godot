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
	# Carrot is row 1, tomato is row 3, sunflower is row 4 in crops.png
	crop_regions["carrot"] = {}
	crop_regions["tomato"] = {}
	crop_regions["sunflower"] = {}
	for stage in 4: crop_regions["carrot"][stage] = Rect2(stage * 16, 1 * 16, 16, 16)
	for stage in 6: crop_regions["tomato"][stage] = Rect2(stage * 16, 3 * 16, 16, 16)
	for stage in 6: crop_regions["sunflower"][stage] = Rect2(stage * 16, 4 * 16, 16, 16)

	# Object regions map
	# Format: object_name -> [texture, rect]
	object_regions["cot"] = [furniture_texture, Rect2(0 * 16, 1 * 16, 16, 16)]
	object_regions["well"] = [furniture_texture, Rect2(4 * 16, 1 * 16, 16, 16)]
	object_regions["shipping_bin"] = [chest_texture, Rect2(1 * 16, 1 * 16, 16, 16)]
	object_regions["seed_box"] = [chest_texture, Rect2(4 * 16, 1 * 16, 16, 16)]


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
		return objects[ty][tx]
	return ""


func is_walkable(tx: int, ty: int) -> bool:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return false
	var state: String = tile.state
	if state == "border":
		return false
	if state.begins_with("obstacle"):
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
	queue_redraw()


func _draw() -> void:
	# Bitmask mapping (0-15) for Sprout Lands top-left 4x4 layout
	var BITMASK_MAP := {
		0: Vector2i(3, 0),  1: Vector2i(3, 2),  2: Vector2i(0, 3),  3: Vector2i(0, 2),
		4: Vector2i(3, 1),  5: Vector2i(3, 3),  6: Vector2i(0, 0),  7: Vector2i(0, 1),
		8: Vector2i(2, 3),  9: Vector2i(2, 2), 10: Vector2i(1, 3), 11: Vector2i(1, 2),
		12: Vector2i(2, 0), 13: Vector2i(2, 1), 14: Vector2i(1, 0), 15: Vector2i(1, 1)
	}

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
				# Calculate 4-way bitmask for dirt
				var mask := 0
				if ty > 0 and tiles[ty-1][tx].state in ["tilled", "seeded", "growing", "ready"]: mask += 1 # N
				if tx < MAP_WIDTH - 1 and tiles[ty][tx+1].state in ["tilled", "seeded", "growing", "ready"]: mask += 2 # E
				if ty < MAP_HEIGHT - 1 and tiles[ty+1][tx].state in ["tilled", "seeded", "growing", "ready"]: mask += 4 # S
				if tx > 0 and tiles[ty][tx-1].state in ["tilled", "seeded", "growing", "ready"]: mask += 8 # W
				
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
				if tile.crop_type == "carrot": stage = min(stage, 3)
				elif tile.crop_type == "tomato" or tile.crop_type == "sunflower": stage = min(stage, 5)
				var region: Rect2 = crop_regions[tile.crop_type].get(stage, Rect2())
				if region.size.x > 0:
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(crops_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), region)
					})

			# Queue objects
			var obj: String = objects[ty][tx]
			if obj != "":
				var obj_data = object_regions.get(obj)
				if obj_data:
					var tex: Texture2D = obj_data[0]
					var region: Rect2 = obj_data[1]
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(tex, Rect2(px, py, TILE_SIZE, TILE_SIZE), region)
					})

	# Insert player into render queue if player exists
	var player = get_node_or_null("../Player")
	if player and player.has_method("queue_render"):
		player.queue_render(self, render_queue)

	# Sort by Y-coordinate
	render_queue.sort_custom(func(a, b): return a.y < b.y)

	# Execute drawing commands
	for entity in render_queue:
		entity.draw.call()



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


func _load_textures() -> void:
	tileset_texture = load("res://assets/sprites/tiles.png")
	crops_texture = load("res://assets/sprites/crops.png")
	objects_texture = load("res://assets/sprites/objects.png")

	# Tile regions: 8 columns x 1 row
	var tile_names: Array[String] = [
		"border", "obstacle_rock", "obstacle_log", "obstacle_weed",
		"cleared", "tilled", "watered_tilled", "grass"
	]
	for i in tile_names.size():
		tile_regions[tile_names[i]] = Rect2(i * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE)

	# Crop regions: 4 columns x 3 rows
	for crop_name in CropDefs.ORDER:
		crop_regions[crop_name] = {}
		var row: int = CropDefs.TYPES[crop_name].sprite_row
		for stage in 4:
			crop_regions[crop_name][stage] = Rect2(
				stage * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE
			)

	# Object regions: 4 columns x 1 row
	var obj_names: Array[String] = ["cot", "shipping_bin", "well", "seed_box"]
	for i in obj_names.size():
		object_regions[obj_names[i]] = Rect2(i * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE)


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
					row.append(_create_tile("grass"))
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
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			var tile: Dictionary = tiles[ty][tx]
			var px := tx * TILE_SIZE
			var py := ty * TILE_SIZE

			# Choose tile quad based on state
			var quad_name: String = tile.state
			if tile.state in ["seeded", "growing", "ready"]:
				quad_name = "watered_tilled" if tile.watered_today else "tilled"
			elif tile.state == "tilled" and tile.watered_today:
				quad_name = "watered_tilled"

			# Draw base tile
			var region: Rect2 = tile_regions.get(quad_name, Rect2())
			if region.size.x > 0:
				draw_texture_rect_region(tileset_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), region)

			# Draw crops on top
			if tile.state in ["seeded", "growing", "ready"]:
				var visual_stage := CropDefs.get_visual_stage(tile.crop_type, tile.growth_stage)
				var crop_region_map = crop_regions.get(tile.crop_type, {})
				var crop_region: Rect2 = crop_region_map.get(visual_stage, Rect2())
				if crop_region.size.x > 0:
					draw_texture_rect_region(crops_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), crop_region)

			# Draw objects
			var obj: String = objects[ty][tx]
			if obj != "":
				var obj_region: Rect2 = object_regions.get(obj, Rect2())
				if obj_region.size.x > 0:
					draw_texture_rect_region(objects_texture, Rect2(px, py, TILE_SIZE, TILE_SIZE), obj_region)



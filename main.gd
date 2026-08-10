# main.gd — Main scene entry point
# Wires all game systems together, mirrors the Love2D main.lua
extends Node2D

const TILE_SIZE := 16
const CAMERA_SCALE := 3
const MAP_WIDTH := 32
const MAP_HEIGHT := 20

# Scene references
var farm: Node2D
var player: Node2D
var particles_manager: Node2D
var camera: Camera2D

# UI layers
var hud: CanvasLayer
var menus: CanvasLayer
var day_cycle: CanvasLayer

# Tile cursor drawing
var cursor_visible: bool = false
var cursor_tile: Vector2i = Vector2i(-1, -1)
var cursor_color: Color = Color.WHITE


func _ready() -> void:
	# Pixel art rendering
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

	# Create farm
	var FarmScript = load("res://world/farm.gd")
	farm = FarmScript.new()
	farm.name = "Farm"
	add_child(farm)

	# Create player
	var PlayerScript = load("res://player/player.gd")
	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.farm = farm
	player.init_position(2, 2)  # Near the cot

	# Create particles manager
	var ParticlesScript = load("res://effects/particles_manager.gd")
	particles_manager = ParticlesScript.new()
	add_child(particles_manager)

	# Create camera
	camera = Camera2D.new()
	camera.zoom = Vector2(CAMERA_SCALE, CAMERA_SCALE)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	# Set camera limits to clamp within the map
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE
	player.add_child(camera)

	# Create HUD
	var HUDScript = load("res://ui/hud.gd")
	hud = HUDScript.new()
	add_child(hud)

	# Create menus
	var MenusScript = load("res://ui/menus.gd")
	menus = MenusScript.new()
	add_child(menus)
	menus.menu_action.connect(_on_menu_action)

	# Create day cycle overlay
	var DayCycleScript = load("res://systems/day_cycle.gd")
	day_cycle = DayCycleScript.new()
	add_child(day_cycle)


func _process(delta: float) -> void:
	# Update camera offset for input manager
	var cam_offset := Vector2.ZERO
	if camera:
		var viewport_size := get_viewport().get_visible_rect().size
		cam_offset = camera.get_screen_center_position() * CAMERA_SCALE - viewport_size / 2.0
	InputManager.update_camera_offset(cam_offset)

	# Skip gameplay during day transition
	if day_cycle.is_active():
		return

	# Skip gameplay while menu is open
	if menus.is_open():
		return

	# Player update
	player.update_player(delta)

	# Action
	if Input.is_action_just_pressed("action") and not player.is_acting:
		var action: String = player.handle_action()
		_handle_action_result(action)

	# Seed type cycling with number keys when Seeds tool is active
	var current_tool_idx := GameState.selected_tool
	if current_tool_idx >= 0 and current_tool_idx < Tools.LIST.size():
		if Tools.LIST[current_tool_idx].tool_name == "Seeds":
			if Input.is_key_pressed(KEY_1):
				GameState.selected_seed_type = "carrot"
			elif Input.is_key_pressed(KEY_2) and CropDefs.is_seed_unlocked("tomato", GameState.harvest_counts):
				GameState.selected_seed_type = "tomato"
			elif Input.is_key_pressed(KEY_3) and CropDefs.is_seed_unlocked("sunflower", GameState.harvest_counts):
				GameState.selected_seed_type = "sunflower"

	# Update tile cursor
	var cursor_info: Dictionary = hud.get_cursor_info(GameState.selected_tool, farm)
	cursor_visible = cursor_info.get("visible", false)
	if cursor_visible:
		cursor_tile = cursor_info.get("tile", Vector2i(-1, -1))
		cursor_color = cursor_info.get("color", Color.WHITE)
	queue_redraw()

	# Determine interaction hints
	var hint_text: String = ""
	var pt = player.get_tile_pos()
	var ft = player.get_facing_tile()
	var obj: String = farm.get_object(pt.x, pt.y)
	var adj_obj: String = farm.get_object(ft.x, ft.y)
	
	if obj == "shipping_bin" or adj_obj == "shipping_bin":
		var has_crops := false
		for count in GameState.crops.values():
			if count > 0:
				has_crops = true
				break
		if has_crops:
			hint_text = "Press SPACE to deposit crops"
		else:
			var bin_has_crops := false
			for count in GameState.shipping_bin.values():
				if count > 0:
					bin_has_crops = true
					break
			if bin_has_crops:
				hint_text = "Sleep in cot to sell deposited crops"
				
	hud.set_hint(hint_text)


func _unhandled_input(event: InputEvent) -> void:
	if menus.is_open():
		return
	
	if event.is_action_pressed("pause"):
		menus.open_menu("pause")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		menus.open_menu("inventory")
		get_viewport().set_input_as_handled()


func _handle_action_result(action: String) -> void:
	if action == "":
		return
	if action == "sleep":
		day_cycle.set_day_display(GameState.day + 1)
		day_cycle.start_sleep(func():
			farm.advance_day()
			GameState.process_shipping_bin()
			GameState.start_new_day()
		)
	elif action == "open_shop":
		menus.open_menu("shop")
	else:
		GameState.check_milestones()


func _on_menu_action(action: String) -> void:
	if action == "quit":
		get_tree().quit()


func spawn_particles(effect_type: String, world_pos: Vector2) -> void:
	particles_manager.emit(effect_type, world_pos)


func _draw() -> void:
	# Draw tile cursor in world space
	if cursor_visible and cursor_tile.x >= 0 and cursor_tile.y >= 0:
		var px := cursor_tile.x * TILE_SIZE
		var py := cursor_tile.y * TILE_SIZE
		var rect := Rect2(px, py, TILE_SIZE, TILE_SIZE)
		draw_rect(rect, cursor_color, false, 1.0)

# input_manager.gd — Autoloaded input abstraction singleton
# Tracks input mode (keyboard/gamepad/mouse) and provides mouse-to-tile conversion
extends Node

signal input_mode_changed(new_mode: String)

enum Mode { KEYBOARD, GAMEPAD, MOUSE }

var current_mode: Mode = Mode.KEYBOARD
var mouse_tile: Vector2i = Vector2i(-1, -1)
var click_tile: Vector2i = Vector2i(-1, -1)
var has_click: bool = false

# Tile conversion constants
const TILE_SIZE := 16
const SCALE := 3

var _camera_offset: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventKey or (event is InputEventJoypadButton and false):
		_set_mode(Mode.KEYBOARD)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion:
			if absf(event.axis_value) > 0.3:
				_set_mode(Mode.GAMEPAD)
		else:
			_set_mode(Mode.GAMEPAD)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_mode(Mode.MOUSE)
	elif event is InputEventScreenTouch:
		_set_mode(Mode.MOUSE)

	# Track mouse clicks
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		click_tile = screen_to_tile(event.position)
		has_click = true


func _process(_delta: float) -> void:
	# Update mouse tile position continuously
	var mouse_pos := get_viewport().get_mouse_position()
	mouse_tile = screen_to_tile(mouse_pos)


func screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world_x := (screen_pos.x + _camera_offset.x) / SCALE
	var world_y := (screen_pos.y + _camera_offset.y) / SCALE
	var tx := int(world_x / TILE_SIZE)
	var ty := int(world_y / TILE_SIZE)
	return Vector2i(tx, ty)


func tile_to_screen(tile_pos: Vector2i) -> Vector2:
	var world_x := (tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0) * SCALE - _camera_offset.x
	var world_y := (tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0) * SCALE - _camera_offset.y
	return Vector2(world_x, world_y)


func update_camera_offset(offset: Vector2) -> void:
	_camera_offset = offset


func consume_click() -> Vector2i:
	has_click = false
	return click_tile


func get_mode_string() -> String:
	match current_mode:
		Mode.KEYBOARD: return "keyboard"
		Mode.GAMEPAD: return "gamepad"
		Mode.MOUSE: return "mouse"
	return "keyboard"


func _set_mode(new_mode: Mode) -> void:
	if current_mode != new_mode:
		current_mode = new_mode
		input_mode_changed.emit(get_mode_string())

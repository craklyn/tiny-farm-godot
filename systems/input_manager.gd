# input_manager.gd — Autoloaded input abstraction singleton
# Tracks input mode (keyboard/gamepad/mouse) and provides mouse-to-tile conversion
extends Node

signal input_mode_changed(new_mode: String)

# TOUCH is distinct from MOUSE on purpose. A finger has no hover: it is either
# down somewhere or absent, and there is no "the pointer is resting on this tile"
# for the game to show. Godot delivers touches as mouse events too, so without
# this the tablet looked like a mouse to everything downstream.
enum Mode { KEYBOARD, GAMEPAD, MOUSE, TOUCH }

var current_mode: Mode = Mode.KEYBOARD
var mouse_tile: Vector2i = Vector2i(-1, -1)

# How long after a real touch an incoming mouse event is assumed to be Godot's
# emulation of that touch rather than a person moving a mouse.
const TOUCH_EMULATION_WINDOW_MS := 1200
var _last_touch_ms: int = -100000
var click_tile: Vector2i = Vector2i(-1, -1)
var has_click: bool = false

# Swipe-chain state
var swipe_active: bool = false
var swipe_tile: Vector2i = Vector2i(-1, -1)
var swipe_moved: bool = false  # true for one frame when finger enters a new tile

# Tile conversion constants
const TILE_SIZE := 16
const SCALE := 3

var _camera_offset: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	swipe_moved = false  # Reset per-frame

	if event is InputEventKey or (event is InputEventJoypadButton and false):
		_set_mode(Mode.KEYBOARD)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion:
			if absf(event.axis_value) > 0.3:
				_set_mode(Mode.GAMEPAD)
		else:
			_set_mode(Mode.GAMEPAD)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# Godot emulates mouse events from touches, and that emulation is what the
		# menus' Buttons actually run on — so it cannot simply be turned off. But
		# it also means a tablet looks exactly like a mouse to this branch, which
		# would put the mode straight back to MOUSE and bring the drifting hover
		# cursor with it. A real mouse does not move within a second of a finger
		# touching the glass; emulated events always do. The window self-corrects,
		# so a desktop with a touchscreen still gets its hover back a moment after
		# the user picks the mouse up again.
		if Time.get_ticks_msec() - _last_touch_ms > TOUCH_EMULATION_WINDOW_MS:
			_set_mode(Mode.MOUSE)
	elif event is InputEventScreenTouch:
		_last_touch_ms = Time.get_ticks_msec()
		_set_mode(Mode.TOUCH)
		if event.pressed:
			# Treat touch-press as a click
			click_tile = screen_to_tile(event.position)
			has_click  = true
			swipe_active = false
		else:
			# Finger lifted
			swipe_active = false
			swipe_tile   = Vector2i(-1, -1)
	elif event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		_set_mode(Mode.TOUCH)
		var new_tile := screen_to_tile(event.position)
		if new_tile != swipe_tile:
			swipe_tile   = new_tile
			swipe_active = true
			swipe_moved  = true

	# Track mouse clicks
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		click_tile = screen_to_tile(event.position)
		has_click = true


func _process(_delta: float) -> void:
	# Only a real pointing device has a hover position worth tracking.
	#
	# Reported from play 2026-08-30: "yellow box is moving around as screen
	# scrolls, instead of holding position of the click." That is this line. The
	# tile is recomputed every frame from the *screen* position plus the camera
	# offset, so on a tablet — where the last touch point stays put and the camera
	# scrolls after the walking farmer — the cursor slid across the world. It was
	# never a click indicator; it is a mouse hover, and a finger does not hover.
	if current_mode != Mode.MOUSE:
		mouse_tile = Vector2i(-1, -1)
		return
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
		Mode.TOUCH: return "touch"
	return "keyboard"


func _set_mode(new_mode: Mode) -> void:
	if current_mode != new_mode:
		current_mode = new_mode
		input_mode_changed.emit(get_mode_string())

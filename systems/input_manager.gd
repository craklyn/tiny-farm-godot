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

# --- two fingers: the camera's own gesture (design/11 row 26) -----------------
#
# Reserved from the first inventory pass for the camera and nothing else, and
# that is exactly what it drives here. One finger keeps every meaning it has;
# the moment a second lands, the pair is a camera gesture and the first finger's
# pending tap is dropped — a pinch that marks a square on the way in would make
# the gesture cost something to try, which is the one thing a view control must
# never do.
# Measured **against the moment the gesture started**, not against the previous
# event. The first version compared each event to the one before it, and fingers
# do not move in step: a two-finger drag arrives as finger A moved, then finger B
# moved, so every span was computed with one finger current and one stale. A pure
# pan therefore reported the fingers spreading and closing on alternate events —
# which is what "it zooms me in and out when I pan" was — and because each event
# *overwrote* the pan instead of adding to it, only the last one in a frame
# survived, which is what "barely moves left/right" was. One mistake, both
# symptoms. Absolute measurements have neither failure by construction, and they
# cannot drift, because nothing accumulates.
var touches: Dictionary = {}            # finger index -> current screen position
var gesture_active: bool = false        # two or more fingers are down right now
var gesture_began: bool = false         # true for the one frame the pair landed
var gesture_span_ratio: float = 1.0     # fingers' spread now ÷ spread at the start
var gesture_pan: Vector2 = Vector2.ZERO # midpoint travel since the start, screen px
var _span0: float = -1.0
var _mid0: Vector2 = Vector2.ZERO

# Tile conversion constants
const TILE_SIZE := 16
const SCALE := 3          # the ground-level zoom, and the fallback before main reports one

var _camera_offset: Vector2 = Vector2.ZERO
# **The camera's live zoom, not the constant.** This used to be `SCALE` inline in
# both conversions, which was true for as long as the camera never moved off its
# fixed close-up altitude. The moment it could — showing a mark-1 where to work
# frames the whole farm at about 1.5× — every tap on the glass resolved to a
# square about half as far from the centre as the one under the finger. Nothing
# caught it: the integration suite injects tiles straight into `click_tile`, so
# the one path that was wrong was the one path no test used.
var _camera_scale: float = float(SCALE)

# T-27 (box 2): the consumption window.
#
# Her triple sleep — three cot taps in five seconds (2026-08-30 trace, 3m37–42s),
# about three phantom days inside "day 12" — was never three decisions. `main.gd`
# returns early for the whole day transition, so `player.update_player()` never
# ran and never *consumed* `has_click`: the tap sat in this buffer and fired on
# the first frame of morning, which started the next transition, which buffered
# the next tap. One intention, three days.
#
# The fix is a window, not a timer. While a transition owns the screen, pointer
# events are dropped **here**, at the input boundary, before anything downstream
# can turn one into an intent — so there is nothing to debounce and no interval to
# tune. Nothing about the gateway changes: an Action that has already resolved
# still lands, and a tap the instant after the window closes is an ordinary tap.
var _swallowing: bool = false


## Open or close the window. Opening it also discards whatever is already
## buffered: a tap made in the world she fell asleep in is not a tap in the one
## she wakes up in.
func swallow_input(on: bool) -> void:
	_swallowing = on
	if on:
		has_click = false
		swipe_active = false
		swipe_moved = false
		swipe_tile = Vector2i(-1, -1)
		# Fingers that were down when the window opened will never send their
		# release here, so forget them rather than leave a phantom pinch running.
		touches.clear()
		gesture_span_ratio = 1.0
		gesture_pan = Vector2.ZERO
		gesture_active = false
		gesture_began = false
		_span0 = -1.0


func is_swallowing() -> bool:
	return _swallowing


## A tap aimed at a **tile** rather than at a point on the glass — T-31 (Q-49),
## and the HUD's bed button is its only caller today.
##
## The button has to produce the same intent a thumb on the cot produces: walk,
## tuck in, sleep. Injecting it here, into the same one-tap buffer a finger fills,
## is what makes that literally true rather than merely similar — everything
## downstream (`resolve_with_halo`, the approach, the path, the tap indicator, the
## Action) is the ordinary cot tap and knows nothing about a button. It cannot go
## through `screen_to_tile`, because by evening the cot is usually off screen,
## which is exactly when she wants it.
##
## Refused while the T-27 window is open, for the same reason a finger is: a tap
## made during a day transition is not a tap in the day it lands in. Returns
## whether the tap was taken, so a caller can tell the difference.
func tap_tile(t: Vector2i) -> bool:
	if _swallowing:
		return false
	click_tile = t
	has_click = true
	return true


# What the two fingers add up to, measured once a frame with both positions
# current — never per event, which is what made a pan read as a pinch.
func _measure_gesture() -> void:
	gesture_began = false
	if touches.size() < 2:
		if gesture_active:
			gesture_active = false
			_span0 = -1.0
		gesture_span_ratio = 1.0
		gesture_pan = Vector2.ZERO
		return
	var pts: Array = touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var span: float = a.distance_to(b)
	var mid: Vector2 = (a + b) * 0.5
	if not gesture_active or _span0 <= 0.0:
		# The reference the whole gesture is measured from. Re-taken whenever the
		# pair changes, so lifting a finger and putting it back is a new gesture
		# rather than a jump.
		_span0 = maxf(span, 1.0)
		_mid0 = mid
		gesture_active = true
		gesture_began = true
		gesture_span_ratio = 1.0
		gesture_pan = Vector2.ZERO
		return
	gesture_span_ratio = span / _span0
	gesture_pan = mid - _mid0


func _unhandled_input(event: InputEvent) -> void:
	swipe_moved = false  # Reset per-frame

	# T-27: dropped whole, including the mode bookkeeping — a fade is not a moment
	# to decide the player has switched from a finger to a mouse. Keys and pads
	# still come through: the pause button must work during a transition.
	if _swallowing and (event is InputEventScreenTouch or event is InputEventScreenDrag \
			or event is InputEventMouseButton or event is InputEventMouseMotion):
		return

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
			touches[event.index] = event.position
			if touches.size() >= 2:
				# The second finger cancels the first one's tap. Whatever she is
				# doing now, it is not marking a square.
				has_click = false
				swipe_active = false
			else:
				click_tile = screen_to_tile(event.position)
				has_click  = true
				swipe_active = false
		else:
			touches.erase(event.index)
			# Lifting one of two fingers must not hand the survivor a tap: the
			# gesture is over, and the leftover finger is on its way off the glass.
			if touches.size() <= 1:
				has_click = false
			swipe_active = false
			swipe_tile   = Vector2i(-1, -1)
	elif event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		_set_mode(Mode.TOUCH)
		touches[event.index] = event.position
		if touches.size() >= 2:
			has_click = false
			swipe_active = false
			return
		var new_tile := screen_to_tile(event.position)
		if new_tile != swipe_tile:
			swipe_tile   = new_tile
			swipe_active = true
			swipe_moved  = true

	# Track mouse clicks
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		click_tile = screen_to_tile(event.position)
		has_click = true


## Where the two fingers have got to, relative to where they started. Nothing is
## consumed or cleared: the numbers are absolute, so reading them twice in a
## frame is the same as reading them once, and a dropped frame loses nothing.
func gesture() -> Dictionary:
	return {"active": gesture_active, "began": gesture_began,
		"ratio": gesture_span_ratio, "pan": gesture_pan}


func _process(_delta: float) -> void:
	# Both fingers are current here; in `_unhandled_input` only one ever is.
	_measure_gesture()
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
	var world_x := (screen_pos.x + _camera_offset.x) / _camera_scale
	var world_y := (screen_pos.y + _camera_offset.y) / _camera_scale
	# floor, not truncate: `int()` rounds toward zero, so every negative world
	# coordinate collapsed onto tile 0 and a tap just off the left edge read as a
	# tap on the first column. Off the map should stay off the map.
	return Vector2i(floori(world_x / TILE_SIZE), floori(world_y / TILE_SIZE))


func tile_to_screen(tile_pos: Vector2i) -> Vector2:
	var world_x := (tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0) * _camera_scale - _camera_offset.x
	var world_y := (tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0) * _camera_scale - _camera_offset.y
	return Vector2(world_x, world_y)


func update_camera_offset(offset: Vector2, scale: float = float(SCALE)) -> void:
	_camera_offset = offset
	_camera_scale = maxf(0.01, scale)


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

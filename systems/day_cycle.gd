# day_cycle.gd — Day transition with fade animation
# Mirrors the Love2D day_cycle.lua
extends CanvasLayer

var state: String = "idle"  # "idle", "tucking", "fading_out", "hold", "fading_in"
var alpha: float = 0.0
var timer: float = 0.0
var day_display: int = 1

# T-27 (box 1): the anticipation beat. The transition now *opens* on the lit
# world with the farmer lying on her cot, and only then fades.
#
# **This does not delay the sim by a frame, and must not (D-8).** The sleep Action
# is applied by `main.gd` at the instant the tap resolves, before `start_sleep()`
# is even called — so the world is already in the new day for the whole of the
# sequence below, and every phase here is presentation that could be skipped
# entirely without the sim noticing. D-8 names the one variant that would be a
# sim change ("a wind-up before the effect") and this is deliberately not it: the
# effect has already happened, and what she is watching is its acknowledgement.
#
# Long enough to register as an answer to her tap, short enough that it never
# reads as a wait. [Playtest]
const TUCK_TIME := 0.45
const FADE_OUT_TIME := 0.5
const HOLD_TIME := 0.5
const FADE_IN_TIME := 0.5

var _on_new_day: Callable
var _new_day_fired: bool = false

# UI elements
var overlay: ColorRect
var day_label: Label


func _ready() -> void:
	layer = 100  # Draw on top of everything

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	day_label = Label.new()
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	day_label.set_anchors_preset(Control.PRESET_CENTER)
	day_label.add_theme_font_size_override("font_size", 24)
	day_label.add_theme_color_override("font_color", Color.WHITE)
	day_label.visible = false
	add_child(day_label)


## `tuck` asks for T-27's anticipation beat before the fade. The player's own
## sleep passes it; the cold open's world sleep does not — nobody is lying on
## anything there, and holding a lit world for half a second to show that would be
## a pause with nothing in it (T-26 asks the opposite question of that transition,
## and it is still open).
func start_sleep(on_new_day: Callable, tuck: bool = false) -> void:
	if state != "idle":
		return
	state = "tucking" if tuck else "fading_out"
	timer = 0.0
	alpha = 0.0
	_on_new_day = on_new_day
	_new_day_fired = false


func is_active() -> bool:
	return state != "idle"


func set_day_display(day: int) -> void:
	day_display = day


func _process(delta: float) -> void:
	if state == "idle":
		return

	timer += delta

	match state:
		"tucking":
			# The world stays lit and unfaded: this beat exists to be *seen*.
			alpha = 0.0
			if timer >= TUCK_TIME:
				state = "fading_out"
				timer = 0.0
		"fading_out":
			alpha = minf(1.0, timer / FADE_OUT_TIME)
			if timer >= FADE_OUT_TIME:
				state = "hold"
				timer = 0.0
		"hold":
			alpha = 1.0
			if not _new_day_fired and _on_new_day.is_valid():
				_on_new_day.call()
				_new_day_fired = true
			if timer >= HOLD_TIME:
				state = "fading_in"
				timer = 0.0
		"fading_in":
			alpha = 1.0 - minf(1.0, timer / FADE_IN_TIME)
			if timer >= FADE_IN_TIME:
				state = "idle"
				alpha = 0.0

	overlay.color = Color(0, 0, 0, alpha)

	# Show day text during hold
	if state == "hold" and alpha >= 0.9:
		day_label.text = "Day %d" % day_display
		day_label.visible = true
	else:
		day_label.visible = false

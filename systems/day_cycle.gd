# day_cycle.gd — Day transition with fade animation
# Mirrors the Love2D day_cycle.lua
extends CanvasLayer

var state: String = "idle"  # "idle", "fading_out", "hold", "fading_in"
var alpha: float = 0.0
var timer: float = 0.0
var day_display: int = 1

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


func start_sleep(on_new_day: Callable) -> void:
	if state != "idle":
		return
	state = "fading_out"
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

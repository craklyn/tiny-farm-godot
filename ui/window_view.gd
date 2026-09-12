# window_view.gd — what she sees when she looks out of her own window
#
# **What this is** (the CEO, 2026-09-11: *"a player that selects their house
# window can look out and see a landscape... maybe for now we see a beautiful
# grassland hillside"*). The home's north wall has two windows cut in it
# (`WorldLayout.HOME`), and until now a tap on one did what a tap on the wall
# does: nothing. Now it is looking out. She walks up to the sill, and this takes
# the screen — the wall she is standing at, the window in it, and the hillside
# beyond the glass.
#
# **A look changes nothing, so it is a screen and not a verb.** The router reads
# the tap as `look_out_window`, the player node hands it to `main.gd` the way it
# hands over `open_shop` and `open_workbench`, and `ui/menus.gd` runs it as one
# more mode of the menu layer. Nothing about it reaches the gateway or a replay
# (CLAUDE.md's line: UI navigation is never an Action), and the sim does not know
# the word — the unit suite proves it refuses it.
#
# **The world holds while she looks** (ground rule 7, as behind every screen).
# The view is lit by the hour she opened it at: the picture is drawn through the
# same daylight tint the room outside is under, so dusk at the window is dusk.
#
# **What is out there is provisional** (P-16). The hillside is one generated
# picture, the same for both windows, and the long-term art vision — whether the
# window shows the real farm, the wilds, the season, the weather — is the
# designer's to settle when the visual identity is. This file is written so that
# swapping the picture is swapping one file.
#
# **It closes on any tap.** A child who has looked wants the room back, and the
# picture has nothing to press; the corner card is there so the way out is also
# visible, in the same dark-green card the HUD and the workbench put every
# control in.
class_name WindowView
extends Control

## Emitted when she is done looking. `ui/menus.gd` hears it and closes the
## menu, which is what unpauses the world — the view does not touch the tree.
signal closed

## The picture beyond the glass: 320x240, drawn at 2x. One file, so a redrawn
## world is a redrawn file (P-16).
const HILLSIDE := "res://assets/sprites/generated/window_hillside.png"

# --- geometry, absolute against the game's fixed 800x600 screen ---------------
const SCREEN := Vector2(800, 600)
const PICTURE_RECT := Rect2(80, 60, 640, 480)     # the glass, 2x the source
const FRAME := 16.0                               # the wood around the glass
const MULLION := 10.0                             # the cross bars over it
const SILL_H := 26.0
const SILL_OVERHANG := 14.0
const SKIRTING_H := 28.0

# **Every target a thumb has to find is 56 across** — the HUD's rule (S-6/S-7),
# and the workbench's close card is this same number.
const TOUCH := 56.0

# --- the colours: the room's own -----------------------------------------------
#
# The plaster is `interior_wall.png`'s, the wood is the fence's browns the way
# `tools/gen_interior.py` derived the room's from them — so the wall she is
# looking at here is the wall she was standing at a moment ago, larger.
const PLASTER := Color("efe4cf")
const PLASTER_LIGHT := Color("f9f4e5")
const WOOD_LIGHT := Color("c39a6c")
const WOOD_MID := Color("af8466")
const WOOD_DARK := Color("90625d")

var _picture: Texture2D = null
var _tint: Color = Color.WHITE
var _close_button: Button = null

## The window she is looking out of, for anyone who asks (the tests do).
var window_tile: Vector2i = Vector2i(-1, -1)


func _init() -> void:
	name = "WindowView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	# **Sized by hand, not by anchors.** Under a CanvasLayer the full-rect preset
	# leaves this control at 0x0 until a layout pass that headless never runs, and
	# a control with no size gets no `_gui_input` — so "any tap closes it" would
	# have been true only of the corner card. Found by a headless probe before it
	# reached a tablet; the game's screen is fixed at 800x600, so the number is
	# the honest one.
	position = Vector2.ZERO
	size = SCREEN


func _ready() -> void:
	_picture = load(HILLSIDE)
	_build_close()


# The close card, in the HUD's corner-card style (`ui/hud.gd`'s bed and menu
# buttons, `ui/workbench.gd`'s close) — the same dark green card with a pale
# border everywhere else in the game puts a control the player is meant to press.
func _build_close() -> void:
	_close_button = Button.new()
	_close_button.name = "WindowClose"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.size = Vector2(TOUCH, TOUCH)
	_close_button.position = Vector2(SCREEN.x - 12.0 - TOUCH, 12.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.20, 0.16, 0.9)
	style.border_color = Color(0.62, 0.72, 0.58)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	for state in ["normal", "hover", "pressed", "focus"]:
		_close_button.add_theme_stylebox_override(state, style)
	_close_button.pressed.connect(func(): closed.emit())
	add_child(_close_button)

	# The cross, drawn rather than typed — two lines cannot be a codepoint the
	# bundled font is missing (`ui/menus.gd`, the U+2715 note).
	var mark := Control.new()
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.draw.connect(func():
		var pad := TOUCH * 0.32
		var ink := Color(0.92, 0.96, 0.88)
		mark.draw_line(Vector2(pad, pad), Vector2(TOUCH - pad, TOUCH - pad), ink, 3.0)
		mark.draw_line(Vector2(TOUCH - pad, pad), Vector2(pad, TOUCH - pad), ink, 3.0)
	)
	_close_button.add_child(mark)


# --- opening ------------------------------------------------------------------

## Look out of the window standing at `at`, in the light of this hour.
##
## `energy` and `max_energy` are the player's meter, which is also the clock
## (Q-38): `Daylight.tint_for` turns them into the same tint the room is drawn
## under, so the view is not brighter than the room she opened it from.
func show_view(at: Vector2i, energy: int, max_energy: int) -> void:
	window_tile = at
	_tint = Daylight.tint_for(energy, max_energy)
	queue_redraw()


## Whether there is a picture to show — the tests ask, so a missing file is a
## red suite rather than a blank pane on a tablet.
func has_picture() -> bool:
	return _picture != null


# --- closing ------------------------------------------------------------------

# Any press on the wall or the glass is "done looking". The event is accepted
# here so it ends here: this control stops the mouse, so nothing below it —
# `InputManager`'s unhandled-input hook included — turns the same press into a
# tap on the farm once the view is gone.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if pressed:
		accept_event()
		closed.emit()


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	# The wall she is standing at, and the skirting along its foot.
	draw_rect(Rect2(Vector2.ZERO, SCREEN), PLASTER * _tint)
	draw_rect(Rect2(0, SCREEN.y - SKIRTING_H, SCREEN.x, SKIRTING_H), WOOD_MID * _tint)
	draw_rect(Rect2(0, SCREEN.y - SKIRTING_H, SCREEN.x, 3), WOOD_DARK * _tint)

	# The frame, then the glass in it, then the bars over the glass.
	var frame_rect := PICTURE_RECT.grow(FRAME)
	draw_rect(frame_rect, WOOD_LIGHT * _tint)
	draw_rect(frame_rect, WOOD_DARK * _tint, false, 2.0)
	draw_rect(PICTURE_RECT.grow(2.0), WOOD_DARK * _tint, false, 2.0)

	if _picture != null:
		draw_texture_rect(_picture, PICTURE_RECT, false, _tint)
	else:
		# No picture on disk: the pane's own sky blue, so the window is still a
		# window rather than a hole. The tests refuse this state; a player never
		# sees it.
		draw_rect(PICTURE_RECT, Color("80a2b8") * _tint)

	var cx := PICTURE_RECT.position.x + PICTURE_RECT.size.x / 2.0 - MULLION / 2.0
	var cy := PICTURE_RECT.position.y + PICTURE_RECT.size.y / 2.0 - MULLION / 2.0
	var vbar := Rect2(cx, PICTURE_RECT.position.y, MULLION, PICTURE_RECT.size.y)
	var hbar := Rect2(PICTURE_RECT.position.x, cy, PICTURE_RECT.size.x, MULLION)
	for bar in [vbar, hbar]:
		draw_rect(bar, WOOD_MID * _tint)
		draw_rect(bar, WOOD_DARK * _tint, false, 1.0)

	# The sill, standing proud of the frame with a shadow under its lip.
	var sill := Rect2(frame_rect.position.x - SILL_OVERHANG, frame_rect.end.y,
		frame_rect.size.x + SILL_OVERHANG * 2.0, SILL_H)
	draw_rect(sill, WOOD_LIGHT * _tint)
	draw_rect(Rect2(sill.position.x, sill.end.y, sill.size.x, 4.0), WOOD_DARK * _tint)
	draw_rect(sill, WOOD_DARK * _tint, false, 2.0)
	draw_rect(Rect2(sill.position.x + 2.0, sill.position.y + 2.0, sill.size.x - 4.0, 3.0),
		PLASTER_LIGHT * _tint)

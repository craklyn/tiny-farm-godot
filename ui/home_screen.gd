# home_screen.gd — the player's home, seen (T-37)
#
# The designer, 2026-09-01: *"create an indoor space representing the player's
# home. The home should have the bed, windows, and very few furnishings
# initially. We'll add those later."*
#
# The fourth debug door, and the Zoo's pattern exactly: a detached GameState
# and a second farm renderer generating from its own layout
# (`WorldLayout.HOME`), so nothing here can touch a real save, a real replay,
# or the live farm. What it shows is real, though — the room comes out of
# `SimWorld.generate` through the ordinary steps (walls and windows are
# boundary tiles like the fence, the floor is a ground like the yard, the bed
# is the cot placed by the layout's own `objects` list), so this screen is a
# faithful preview of exactly what wiring the home into play would produce.
#
# The farmer stands by her bed as scenery, the Zoo's rule: nothing calls
# `update_player`, so there is no walking here yet. Walking indoors, a door on
# the farm, and the cot's move indoors are content sequencing on the ruled
# onboarding flow — the multi-map project's territory, not this screen's.
extends Control

# Any fixed seed works — HOME lays no random obstacles, so generation draws
# nothing from the stream; reseeding just keeps the detached world polite.
const HOME_SEED := 3737

# Frame the room (walls x10..21, y5..13 in tiles) in the 800x600 viewport.
const WORLD_SCALE := 2.5
const WORLD_ORIGIN := Vector2(-240, -70)

var farm: Node2D = null
var player: Node2D = null
var gs: Node = null
var _world: Node2D = null


func _ready() -> void:
	_build_world()
	_build_ui()


func _build_world() -> void:
	# Detached state first — everything below is handed it rather than finding
	# the autoload for itself (the Zoo's hazard, the Zoo's cure).
	gs = load("res://systems/game_state.gd").new()
	gs.name = "HomeState"
	gs.reset()
	add_child(gs)

	_world = Node2D.new()
	_world.name = "HomeWorld"
	_world.position = WORLD_ORIGIN
	_world.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	add_child(_world)

	var FarmScript = load("res://world/farm.gd")
	farm = FarmScript.new()
	farm.name = "HomeFarm"
	farm.generate_on_ready = false
	farm.gs = gs
	_world.add_child(farm)

	SimRng.reseed(HOME_SEED)
	farm.sim.generate(WorldLayout.HOME)
	# Nobody lives here but her: the hen and anything else the default cast
	# brings stays outside (Zoo.furnish's rule, for the same reason).
	for raw in farm.sim.actors.keys():
		if String(raw) != SimWorld.ACTOR_PLAYER:
			farm.sim.despawn_actor(String(raw))

	# The farmer, as scenery, standing in her room. `Player` is load-bearing:
	# `world/farm.gd` finds her at `../Player`.
	var PlayerScript = load("res://player/player.gd")
	player = PlayerScript.new()
	player.name = "Player"
	player.gs = gs
	_world.add_child(player)
	player.farm = farm
	var spawn := WorldLayout.spawn(WorldLayout.HOME)
	player.init_position(spawn.x, spawn.y)

	farm.sync_actors()
	farm.queue_redraw()


func _build_ui() -> void:
	var back := ColorRect.new()
	back.name = "HomeBackdrop"
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.10, 0.08, 0.07)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	move_child(back, 0)  # behind the room, which was added first

	var title := Label.new()
	title.text = "Home"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.93, 0.89, 0.82))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var note := Label.new()
	note.text = "The bed, two windows, and very little else — on purpose (T-37).\n" \
		+ "Generated from WorldLayout.HOME by the ordinary generator; walls are boundaries, the floor is a ground."
	note.position = Vector2(12, 40)
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.66, 0.60, 0.52))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(note)

	var exit := Button.new()
	exit.name = "HomeBackButton"
	exit.text = "Back"
	exit.custom_minimum_size = Vector2(150, 40)
	exit.position = Vector2(8, 552)
	exit.add_theme_font_size_override("font_size", 16)
	_style_button(exit, Color(0.18, 0.42, 0.22), Color(1.0, 0.72, 0.15), Color(0.24, 0.52, 0.28))
	exit.pressed.connect(_go_back)
	add_child(exit)
	exit.grab_focus()


# The title screen's button dressing, copied rather than shared — the Zoo's
# reasoning, verbatim.
func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _style_button(btn: Button, bg: Color, border: Color, hover: Color) -> void:
	btn.add_theme_stylebox_override("normal", _button_style(bg, border))
	btn.add_theme_stylebox_override("hover", _button_style(hover, border))
	btn.add_theme_stylebox_override("pressed", _button_style(border, border))
	btn.add_theme_stylebox_override("focus", _button_style(hover, border))


func _go_back() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")

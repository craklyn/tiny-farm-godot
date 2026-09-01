# zoo_screen.gd — the debug door onto the bestiary (T-33)
#
# The designer, 2026-09-01: *"Some sort of way for us to experience the new
# entities in the game. Either a debug world (like our sound debug) or another
# 'zoo' of the entities we've created, and a way to select or add them in a useful
# way just to see them doing their thing in action."*
#
# It is the **Sound Test's door**, one step further through (Q-31's precedent, and
# T-28's Look Lab took the same one): the title screen's debug row, a full screen
# of its own, a Back button home. What it opens onto is a second farm — a flat
# field, a stocked crop patch, a standing farmer — with a button per species and a
# clock that runs, so a rabbit can be watched rather than read about.
#
# **The whole hazard is the second world touching the first.** `ui/attract_loop.gd`
# names it at length and this file inherits every word: a renderer driven over the
# player's own `GameState` drained her energy to 0 and her wheat to 0 while she was
# still looking at the menu. So, exactly as the attract loop does it:
#
#   * its own `SimWorld`, generated from `Zoo.LAYOUT`, never the played farm's;
#   * its own **detached** `GameState`, a child node of this scene, never the
#     autoload — this is the one that matters, and Scenario AC re-proves it by
#     fingerprinting the live singleton across a full session in here;
#   * **no `ReplayLog` and no `SessionTrace`.** `farm.replay` and `farm.trace` are
#     left null, so `world/farm.gd:_record` writes nowhere, and nothing in this
#     file calls `SaveGame`. The zoo cannot reach a real save slot because it never
#     learns what one is. (The re-baseline commit's review rig is the cautionary
#     tale: a debug harness that wrote where the game keeps its farm.)
#
# **Debug builds only**, gated at the title screen's button exactly as the Sound
# Test and the Look Lab are. The scene ships in the export because those do too
# (`export_filter="all_resources"`); what does not ship is a way to reach it.
#
# S-7 (nothing a pre-reader needs to read) does not bind here — this is a
# developer's surface and the Look Lab already writes English on it — but a
# picture is still better than a word where the picture is free, so every roster
# button wears the sprite the game actually draws that animal with.
extends Control

const TILE := 16
const MAP_W := SimWorld.MAP_WIDTH
const MAP_H := SimWorld.MAP_HEIGHT

# The world sits left of the roster panel and below the census line, scaled to
# fill what is left. 800x600 is the design viewport (`project.godot`).
const PANEL_W := 196
const WORLD_SCALE := 1.14
const WORLD_ORIGIN := Vector2(6, 96)

# `main.gd`'s dial, times the speed multiplier: whole ticks only, remainder
# carried, and a hitch dropped rather than replayed in full.
const MAX_TICKS_PER_FRAME := 4
const SPEEDS: Array[int] = [1, 2, 4]

# How often the census line is recomputed. It is O(actors) and nobody needs it
# frame-exact; a visitor that leaves on its own shows up a quarter-second later.
const CENSUS_SECONDS := 0.25

var farm: Node2D = null
var player: Node2D = null
var gs: Node = null
var overlay: Node2D = null

var speed_idx := 0
var running := true

var _world: Node2D = null
var _tick_debt: float = 0.0
var _census_timer := 0.0
var _taps: Dictionary = {}          # species -> how many times its button was hit
var _census_label: Label = null
var _speed_button: Button = null
var _trail_button: Button = null
var _day_label: Label = null


func _ready() -> void:
	_build_world()
	_build_ui()
	_refresh_census()


# --- the second world -----------------------------------------------------------

func _build_world() -> void:
	# The detached state, first: everything below is handed it rather than finding
	# the autoload for itself (`world/farm.gd:_state`, `player/player.gd:_ready`
	# both fall back to the singleton when nobody injects one, which is right for
	# the game and is precisely the trap here).
	gs = load("res://systems/game_state.gd").new()
	gs.name = "ZooState"
	gs.reset()
	add_child(gs)

	_world = Node2D.new()
	_world.name = "ZooWorld"
	_world.position = WORLD_ORIGIN
	_world.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	add_child(_world)

	var FarmScript = load("res://world/farm.gd")
	farm = FarmScript.new()
	farm.name = "ZooFarm"
	farm.generate_on_ready = false   # Zoo.furnish generates, from its own layout
	farm.gs = gs
	_world.add_child(farm)

	Zoo.furnish(farm.sim, gs)

	# The farmer, as scenery. She takes no input and is never stepped — nothing
	# calls `update_player` — so she stands where she is put: a follow-bot's owner,
	# a grazer's `spook_radius`, and something to judge a critter's size against.
	# The node name is load-bearing: `world/farm.gd` finds her at `../Player`.
	var PlayerScript = load("res://player/player.gd")
	player = PlayerScript.new()
	player.name = "Player"
	player.gs = gs                   # injected BEFORE entering the tree
	_world.add_child(player)
	player.farm = farm
	var spawn := WorldLayout.spawn(farm.sim.layout)
	player.init_position(spawn.x, spawn.y)

	# The trail tint rides in the farm's own render queue — see
	# `ui/zoo_scent_overlay.gd` for why it is a child of the sprite layer and not a
	# node on top of it.
	overlay = load("res://ui/zoo_scent_overlay.gd").new()
	overlay.name = "ScentOverlay"
	farm.actors_node.add_child(overlay)
	overlay.init_overlay(farm)

	farm.sync_actors()
	farm.queue_redraw()


# --- the clock ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not running or farm == null:
		return
	pump(delta)
	_census_timer += delta
	if _census_timer >= CENSUS_SECONDS:
		_census_timer = 0.0
		_refresh_census()


## Let sim time pass. Split out of `_process` so a headless test can drive the zoo
## without waiting on frames, which is how Scenario AC runs its 200 ticks.
func pump(delta: float) -> void:
	var rate: int = SPEEDS[speed_idx]
	_tick_debt += delta * float(SimClock.RATE) * float(rate)
	var whole := int(_tick_debt)
	if whole <= 0:
		return
	_tick_debt -= float(whole)
	farm.advance_sim(mini(whole, MAX_TICKS_PER_FRAME * rate), gs)


# --- what the buttons do ---------------------------------------------------------

## One more of this species, entering the way its real lifecycle would. Returns the
## ids that arrived — empty when the species declined to come, which is a real
## answer rather than a failure (a second crow while one is still on the wing).
func spawn_species(species: String) -> Array[String]:
	var nth := int(_taps.get(species, 0))
	_taps[species] = nth + 1
	var born := Zoo.spawn(farm.sim, gs, species, nth)
	farm.sync_actors()
	farm.queue_redraw()
	_refresh_census()
	return born


## Everything the zoo added, gone; the farmer stays.
func clear_zoo() -> int:
	var gone := Zoo.clear(farm.sim)
	_taps.clear()
	farm.sync_actors()
	farm.queue_redraw()
	_refresh_census()
	return gone


## A morning. The sprinkler fires (its whole life is the day turn), everybody wakes
## rested and thinks again, and the crops that were watered come on a stage.
##
## The weather is forced sunny rather than rolled, and that is not tidiness: a rainy
## turn washes every scent channel farm-wide (Q-58), so a random morning could erase
## the trail somebody opened the tint to look at.
func turn_day() -> Dictionary:
	var result: Dictionary = farm.apply_action(
		{ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	farm.sync_actors()
	farm.queue_redraw()
	_refresh_census()
	if _day_label != null:
		_day_label.text = "Day %d" % int(gs.day)
	return result


func cycle_speed() -> int:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	if _speed_button != null:
		_speed_button.text = "Speed %d×" % SPEEDS[speed_idx]
	return SPEEDS[speed_idx]


func toggle_trail() -> bool:
	overlay.enabled = not overlay.enabled
	if _trail_button != null:
		_trail_button.text = "Trail: %s" % ("on" if overlay.enabled else "off")
	farm.queue_redraw()
	return overlay.enabled


## "3 in the zoo — Crow 1, Ant Scout 1, Rabbit 1", or the empty state.
func census_text() -> String:
	var counts := Zoo.census(farm.sim)
	if counts.is_empty():
		return "Nothing in the zoo yet — tap a critter."
	var total := 0
	var parts: PackedStringArray = []
	for species in counts:
		total += int(counts[species])
		parts.append("%s %d" % [Zoo.label_of(String(species)), int(counts[species])])
	return "%d in the zoo — %s" % [total, ", ".join(parts)]


func _refresh_census() -> void:
	if _census_label != null:
		_census_label.text = census_text()


# --- the panel -------------------------------------------------------------------

func _build_ui() -> void:
	var back := ColorRect.new()
	back.name = "ZooBackdrop"
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.09, 0.14, 0.11)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	move_child(back, 0)   # behind the farm, which was added first

	var head := Label.new()
	head.text = "Zoo"
	head.position = Vector2(10, 2)
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)

	_day_label = Label.new()
	_day_label.name = "ZooDayLabel"
	_day_label.text = "Day %d" % int(gs.day)
	_day_label.position = Vector2(62, 12)
	_day_label.add_theme_font_size_override("font_size", 13)
	_day_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	_day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_day_label)

	_census_label = Label.new()
	_census_label.name = "ZooCensus"
	_census_label.position = Vector2(10, 38)
	_census_label.size = Vector2(584, 54)
	_census_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_census_label.add_theme_font_size_override("font_size", 12)
	_census_label.add_theme_color_override("font_color", Color(0.86, 0.94, 0.82))
	_census_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_census_label)

	_build_controls()
	_build_roster()


func _build_controls() -> void:
	var row := HBoxContainer.new()
	row.name = "ZooControls"
	row.position = Vector2(8, 476)
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var day := _small_button("NextDayButton", "Next day")
	day.pressed.connect(func():
		turn_day()
		AudioManager.play_sfx("click"))
	row.add_child(day)

	_speed_button = _small_button("SpeedButton", "Speed %d×" % SPEEDS[speed_idx])
	_speed_button.pressed.connect(func():
		cycle_speed()
		AudioManager.play_sfx("click"))
	row.add_child(_speed_button)

	_trail_button = _small_button("TrailButton", "Trail: off")
	_trail_button.pressed.connect(func():
		toggle_trail()
		AudioManager.play_sfx("click"))
	row.add_child(_trail_button)

	var wipe := _small_button("ClearZooButton", "Clear")
	_style_button(wipe, Color(0.38, 0.18, 0.14), Color(0.72, 0.42, 0.34), Color(0.46, 0.22, 0.17))
	wipe.pressed.connect(func():
		clear_zoo()
		AudioManager.play_sfx("click"))
	row.add_child(wipe)

	var note := Label.new()
	note.text = "Every species in SpeciesDefs, entering as its real lifecycle does."\
		+ "\nTrail tints the pest pheromone channel (design/09's reserved magenta)."
	note.position = Vector2(168, 518)
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.70, 0.80, 0.86))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(note)

	var home := _small_button("ZooBackButton", "Back")
	home.custom_minimum_size = Vector2(150, 40)
	home.position = Vector2(8, 522)
	home.add_theme_font_size_override("font_size", 16)
	_style_button(home, Color(0.18, 0.42, 0.22), Color(1.0, 0.72, 0.15), Color(0.24, 0.52, 0.28))
	home.pressed.connect(_go_home)
	add_child(home)
	home.grab_focus()


# One button per species, **driven off `Zoo.roster()`** — which is
# `SpeciesDefs.ids()` minus the farmer, so this panel cannot drift from the table
# the game actually has. The Sound Test's rule (its list comes off
# `AudioManager.sfx_streams`), for the Sound Test's reason.
func _build_roster() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "ZooRoster"
	scroll.position = Vector2(800 - PANEL_W - 6, 6)
	scroll.size = Vector2(PANEL_W, 588)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Tap to add one"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	for species in Zoo.roster():
		grid.add_child(_species_button(species))


func _species_button(species: String) -> Button:
	var btn := Button.new()
	btn.name = "Zoo_%s" % species
	btn.custom_minimum_size = Vector2(88, 58)
	btn.tooltip_text = "%s — brain: %s" % [Zoo.label_of(species), SpeciesDefs.brain_of(species)]
	_style_button(btn, Color(0.13, 0.24, 0.30), Color(0.45, 0.62, 0.70), Color(0.18, 0.32, 0.40))
	btn.pressed.connect(func():
		spawn_species(species)
		AudioManager.play_sfx("click"))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	btn.add_child(box)

	# The sprite the *game* draws this animal with, read through the renderer the
	# farm binds to its species — never a second picture kept beside the first.
	var art: Array = Zoo.icon_of(species)
	if not art.is_empty():
		var atlas := AtlasTexture.new()
		atlas.atlas = art[0]
		atlas.region = art[1]
		var pic := TextureRect.new()
		pic.texture = atlas
		pic.custom_minimum_size = Vector2(0, 30)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pic)

	var name_label := Label.new()
	name_label.text = Zoo.label_of(species)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.90, 0.95, 0.88))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	return btn


func _small_button(node_name: String, text: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.custom_minimum_size = Vector2(112, 34)
	btn.add_theme_font_size_override("font_size", 13)
	_style_button(btn, Color(0.13, 0.24, 0.30), Color(0.45, 0.62, 0.70), Color(0.18, 0.32, 0.40))
	return btn


# The title screen's own button dressing, copied rather than shared because
# `ui/title_screen.gd` keeps it private to itself and a debug surface is not a
# reason to widen its API.
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


func _go_home() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		accept_event()
		_go_home()

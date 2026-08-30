# hud.gd — Heads-up display overlay
# Mirrors the Love2D hud.lua: top bar, bottom bar, tile cursor, toasts
extends CanvasLayer

# Tool icons
var tool_icons_texture: Texture2D
var tool_icon_regions: Dictionary = {}

# Toast
var toast_message: String = ""
var toast_timer: float = 0.0
const TOAST_DURATION := 3.0

# UI controls (created programmatically)
var top_bar: Panel
var bottom_bar: Panel
var day_label: Label
var weather_label: Label
var energy_label: Label  # T-14: debug builds only — the sky is the bar (Q-38)
var gold_label: Label
var menu_button: Button
var tool_icon_rect: TextureRect
var tool_name_label: Label
var seed_info_label: Label
var crop_counts_label: Label
var water_label: Label
var seed_pill: Panel
var seed_pill_label: Label
var toast_panel: Panel
var toast_label: Label
var hint_label: Label

# --- Playtest readout ---------------------------------------------------------
#
# **A scaffold, not the game.** Asked for on 2026-08-29 so a playtester can see
# what the game currently wants and what is gating the next thing; the shipping
# game is wordless by S-7 and none of this belongs in it. It is one constant to
# switch off, and `docs/DEPLOY.md`'s pre-release checklist says to do exactly
# that before any public build.
#
# Everything shown here is read from the sim's own gate functions
# (`tool_proof_progress`, `phase1_progress`), never recomputed alongside them, so
# a number on screen cannot disagree with the rule it is describing.
const PLAYTEST_NOTES := true
# The obstacle count is an O(map) scan, so it is refreshed on a timer rather than
# every frame — the no-per-tile-per-frame guardrail applies to debug UI too.
const NOTES_REFRESH := 0.5
var notes_label: Label
var _notes_timer: float = 0.0

# Tile cursor (drawn in world space via the main scene)
var cursor_tile: Vector2i = Vector2i(-1, -1)
var cursor_color: Color = Color.WHITE


func _ready() -> void:
	layer = 10
	tool_icons_texture = load("res://assets/sprites/tool_icons.png")
	for i in 6:
		tool_icon_regions[i] = Rect2(i * 16, 0, 16, 16)

	_build_ui()

	# Connect milestone signal
	GameState.milestone_reached.connect(_on_milestone)


func _build_ui() -> void:
	var viewport_size := get_viewport().get_visible_rect().size

	# --- Top Bar ---
	top_bar = Panel.new()
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0, 0, 0, 0.6)
	top_bar.add_theme_stylebox_override("panel", top_style)
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(viewport_size.x, 30)
	add_child(top_bar)

	# Day label
	day_label = Label.new()
	day_label.position = Vector2(10, 5)
	day_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
	top_bar.add_child(day_label)

	# Weather label
	weather_label = Label.new()
	weather_label.position = Vector2(70, 5)
	weather_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	top_bar.add_child(weather_label)

	# T-14 / Q-38: the energy bar is gone. Time of day *is* the meter now — the
	# world tint in main.gd renders the same number as light, which a pre-reader
	# can read and "14/20" never was. The numeric readout survives for debugging
	# only, because a developer still wants the exact figure.
	if OS.is_debug_build():
		energy_label = Label.new()
		energy_label.name = "energy_debug_label"
		energy_label.position = Vector2(viewport_size.x / 2 - 50, 5)
		energy_label.size = Vector2(100, 20)
		energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		energy_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		top_bar.add_child(energy_label)

	# Gold label
	gold_label = Label.new()
	gold_label.position = Vector2(viewport_size.x - 116, 5)
	gold_label.size = Vector2(70, 20)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	top_bar.add_child(gold_label)

	# Menu button, top-right. Chunky enough for a small finger (S-6/S-7) and
	# drawn as three bars so it needs no reading.
	menu_button = Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = "\u2630"
	menu_button.size = Vector2(34, 26)
	menu_button.position = Vector2(viewport_size.x - 38, 2)
	menu_button.add_theme_font_size_override("font_size", 18)
	var mb_style := StyleBoxFlat.new()
	mb_style.bg_color = Color(0.16, 0.20, 0.16, 0.9)
	mb_style.border_color = Color(0.62, 0.72, 0.58)
	mb_style.set_border_width_all(2)
	mb_style.set_corner_radius_all(6)
	menu_button.add_theme_stylebox_override("normal", mb_style)
	menu_button.add_theme_stylebox_override("hover", mb_style)
	menu_button.add_theme_stylebox_override("pressed", mb_style)
	menu_button.add_theme_stylebox_override("focus", mb_style)
	menu_button.add_theme_color_override("font_color", Color(0.92, 0.96, 0.88))
	menu_button.pressed.connect(_on_menu_button)
	top_bar.add_child(menu_button)

	# --- Bottom Bar ---
	bottom_bar = Panel.new()
	var bottom_style := StyleBoxFlat.new()
	bottom_style.bg_color = Color(0, 0, 0, 0.6)
	bottom_bar.add_theme_stylebox_override("panel", bottom_style)
	bottom_bar.position = Vector2(0, viewport_size.y - 32)
	bottom_bar.size = Vector2(viewport_size.x, 32)
	add_child(bottom_bar)

	# Tool icon
	tool_icon_rect = TextureRect.new()
	tool_icon_rect.position = Vector2(8, 2)
	tool_icon_rect.size = Vector2(28, 28)
	tool_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tool_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bottom_bar.add_child(tool_icon_rect)

	# Tool name
	tool_name_label = Label.new()
	tool_name_label.position = Vector2(42, 6)
	tool_name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
	bottom_bar.add_child(tool_name_label)

	# Seed info (when Seeds tool is selected)
	seed_info_label = Label.new()
	seed_info_label.position = Vector2(150, 6)
	seed_info_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.4))
	bottom_bar.add_child(seed_info_label)

	# Harvested-crop counts (seed counts live on the seed pill / seed info label)
	crop_counts_label = Label.new()
	crop_counts_label.position = Vector2(viewport_size.x / 2 - 80, 6)
	crop_counts_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7))
	bottom_bar.add_child(crop_counts_label)

	# Watering can
	water_label = Label.new()
	water_label.position = Vector2(viewport_size.x - 120, 6)
	water_label.size = Vector2(110, 20)
	water_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	water_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.95))
	bottom_bar.add_child(water_label)

	# Hint label (above bottom bar)
	hint_label = Label.new()
	hint_label.position = Vector2(0, viewport_size.y - 70)
	hint_label.size = Vector2(viewport_size.x, 30)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hint_label.add_theme_constant_override("outline_size", 4)
	hint_label.text = ""
	add_child(hint_label)

	if PLAYTEST_NOTES:
		notes_label = Label.new()
		notes_label.name = "playtest_notes"
		notes_label.position = Vector2(10, 34)
		notes_label.size = Vector2(viewport_size.x - 20, 76)
		notes_label.add_theme_font_size_override("font_size", 13)
		notes_label.add_theme_color_override("font_color", Color(1, 1, 0.86, 0.92))
		notes_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		notes_label.add_theme_constant_override("outline_size", 4)
		notes_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(notes_label)

	# --- Active Seed Pill (above hint) ---
	seed_pill = Panel.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0.18, 0.52, 0.22, 0.88)
	pill_style.corner_radius_top_left = 12
	pill_style.corner_radius_top_right = 12
	pill_style.corner_radius_bottom_left = 12
	pill_style.corner_radius_bottom_right = 12
	pill_style.border_width_bottom = 1
	pill_style.border_width_top = 1
	pill_style.border_width_left = 1
	pill_style.border_width_right = 1
	pill_style.border_color = Color(1, 1, 1, 0.3)
	seed_pill.add_theme_stylebox_override("panel", pill_style)
	seed_pill.size = Vector2(100, 24)
	seed_pill.position = Vector2(viewport_size.x / 2 - 50, viewport_size.y - 60 - 24)
	seed_pill.gui_input.connect(_on_seed_pill_gui_input)
	add_child(seed_pill)

	seed_pill_label = Label.new()
	seed_pill_label.position = Vector2(0, 2)
	seed_pill_label.size = Vector2(100, 20)
	seed_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_pill_label.add_theme_color_override("font_color", Color(1, 1, 0.9))
	seed_pill.add_child(seed_pill_label)

	# --- Toast ---
	toast_panel = Panel.new()
	var toast_style := StyleBoxFlat.new()
	toast_style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	toast_style.corner_radius_top_left = 6
	toast_style.corner_radius_top_right = 6
	toast_style.corner_radius_bottom_left = 6
	toast_style.corner_radius_bottom_right = 6
	toast_panel.add_theme_stylebox_override("panel", toast_style)
	toast_panel.position = Vector2(viewport_size.x / 2 - 120, viewport_size.y / 2 - 40)
	toast_panel.size = Vector2(240, 40)
	toast_panel.visible = false
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_panel)

	toast_label = Label.new()
	toast_label.position = Vector2(10, 8)
	toast_label.size = Vector2(220, 24)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	toast_panel.add_child(toast_label)


func _process(delta: float) -> void:
	_update_hud()
	_update_toast(delta)
	if notes_label != null:
		_notes_timer -= delta
		if _notes_timer <= 0.0:
			_notes_timer = NOTES_REFRESH
			_update_playtest_notes()


# What the game currently wants, and what is gating whatever is still locked.
func _update_playtest_notes() -> void:
	var main := get_tree().get_first_node_in_group("Main")
	if main == null or main.farm == null or main.farm.sim == null:
		return
	var world: SimWorld = main.farm.sim
	var lines: PackedStringArray = []

	lines.append("PLAYTEST — day %d (her day %d)%s" % [
		GameState.day, GameState.play_day(),
		"  ·  the neighbour is still here" if not ColdOpen.is_done(world) else ""])

	# The beat the game is actually pointing at, named.
	var player_t: Vector2i = main.player.get_tile_pos() if main.player != null else Vector2i(-1, -1)
	var targets: Array[Vector2i] = TeachingFocus.targets(world, GameState, player_t)
	if targets.is_empty():
		lines.append("NOW: nothing is being taught — the farm is yours to poke at")
	else:
		lines.append("NOW: %s  %s" % [_describe_target(main.farm, targets[0]), _target_list(targets)])

	# Every locked tool, and how far along its proof is.
	var tools: PackedStringArray = []
	for e in WorldLayout.tools(world.layout):
		var at: Vector2i = e.get("at", Vector2i(-1, -1))
		if world.get_object(at.x, at.y) != String(e.get("object", "")):
			continue  # already taken
		var p: Dictionary = SimWorld.tool_proof_progress(e, GameState)
		tools.append("%s %d/%d %s" % [String(e.get("tool", "?")).to_upper(),
			p.have, p.need, "READY — go and take it" if p.met else _proof_name(String(p.proof))])
	if not tools.is_empty():
		lines.append("TOOLS: " + "   ".join(tools))

	var ph: Dictionary = world.phase1_progress(GameState)
	lines.append("PHASE 1: shipped %d/%d · crows scared %d/%d · obstacles left %d%s" % [
		ph.shipped, ph.shipped_target, ph.scared, ph.scared_target, ph.obstacles_left,
		"  ✓ COMPLETE" if ph.met else ""])

	notes_label.text = "\n".join(lines)


# Tile states are code words; a playtester should read English.
const TILE_NOUNS := {
	"ready": "ripe crop",
	"growing": "growing crop",
	"seeded": "planted seed",
	"tilled": "tilled soil",
	"cleared": "bare ground",
	"obstacle_weed": "weed",
	"obstacle_log": "log",
	"obstacle_rock": "rock",
	"obstacle_tree": "tree",
}


func _proof_name(proof: String) -> String:
	match proof:
		"harvests": return "harvests"
		"clear_log": return "logs cleared"
		"clear_rock": return "rocks cleared"
		"clear_weed": return "weeds cleared"
		"clear_tree": return "trees cleared"
	return proof


func _describe_target(farm: Node2D, t: Vector2i) -> String:
	var obj: String = farm.get_object(t.x, t.y)
	if obj != "":
		return "%s at (%d,%d)" % [obj.replace("_", " "), t.x, t.y]
	var state: String = String(farm.get_tile(t.x, t.y).get("state", "?"))
	if state == WorldLayout.GATE_OPEN or state == WorldLayout.GATE_CLOSED:
		return "the gate at (%d,%d) — walk through it" % [t.x, t.y]
	var noun: String = TILE_NOUNS.get(state, state)
	var resolved: Dictionary = ActionRouter.resolve(farm, GameState, t, t)
	var verb: String = String(resolved.get("action", ""))
	if verb == "":
		return "the %s at (%d,%d)" % [noun, t.x, t.y]
	return "%s the %s at (%d,%d)" % [verb.replace("_", " "), noun, t.x, t.y]


func _target_list(targets: Array[Vector2i]) -> String:
	if targets.size() <= 1:
		return ""
	return "(+%d more highlighted together)" % (targets.size() - 1)


func _update_hud() -> void:
	if not seed_pill_label:
		return
	# Top bary & Weather
	day_label.text = "Day %d" % GameState.day
	
	var w_icon := "☀️" if GameState.weather == "sunny" else "🌧️"
	weather_label.text = "%s %s" % [w_icon, GameState.weather.capitalize()]

	# Energy — debug readout only (T-14). Release builds show the sky instead.
	if energy_label != null:
		energy_label.text = "Energy: %d/%d" % [GameState.energy, GameState.max_energy]

	# Gold
	gold_label.text = "%dg" % GameState.gold

	# Tool
	var tool_idx := GameState.selected_tool
	if tool_idx >= 0 and tool_idx < Tools.LIST.size():
		var tool_def = Tools.LIST[tool_idx]
		tool_name_label.text = tool_def.tool_name

		# Update tool icon using AtlasTexture
		var atlas := AtlasTexture.new()
		atlas.atlas = tool_icons_texture
		atlas.region = tool_icon_regions.get(tool_def.icon, Rect2())
		tool_icon_rect.texture = atlas

		# Seed info
		if tool_def.tool_name == "Seeds":
			var count: int = GameState.seeds.get(GameState.selected_seed_type, 0)
			seed_info_label.text = "[%s x%d]" % [GameState.selected_seed_type, count]
			seed_info_label.visible = true
		else:
			seed_info_label.visible = false

	# Harvested-crop counts
	var parts: PackedStringArray = []
	for crop_name in CropDefs.ORDER:
		var count: int = GameState.crops.get(crop_name, 0)
		var abbrev: String = crop_name.substr(0, 2).capitalize()
		parts.append("%s:%d" % [abbrev, count])
	crop_counts_label.text = "  ".join(parts)

	# Active Seed Pill update
	var seed_name: String = GameState.selected_seed_type
	var scount: int = GameState.seeds.get(seed_name, 0)
	var emoji := "?"
	match seed_name:
		"wheat": emoji = "🥕"
		"tomato": emoji = "🍅"
	seed_pill_label.text = "%s %s x%d" % [emoji, seed_name, scount]
	
	var style: StyleBoxFlat = seed_pill.get_theme_stylebox("panel")
	if scount > 0:
		style.bg_color = Color(0.18, 0.52, 0.22, 0.88)
	else:
		style.bg_color = Color(0.25, 0.25, 0.25, 0.75)

	# Water
	water_label.text = "Water: %d/%d" % [GameState.watering_can_charges, GameState.max_watering_can_charges]


func _update_toast(delta: float) -> void:
	if toast_timer > 0:
		toast_timer -= delta
		var a := minf(1.0, toast_timer)
		toast_panel.modulate = Color(1, 1, 1, a)
		if toast_timer <= 0:
			toast_panel.visible = false
			toast_message = ""


func show_toast(message: String) -> void:
	toast_message = message
	toast_timer = TOAST_DURATION
	toast_label.text = message
	toast_panel.visible = true
	toast_panel.modulate = Color(1, 1, 1, 1)


func _on_milestone(_id: String, message: String) -> void:
	show_toast(message)


func get_cursor_info(_pt: int, _fn: Node2D) -> Dictionary:
	# Obsolete: main.gd uses ActionRouter.get_cursor_color directly
	return { "visible": false }

func set_hint(text: String) -> void:
	if hint_label:
		hint_label.text = text

func _on_seed_pill_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.cycle_seed_type()
		AudioManager.play_sfx("click")
		get_viewport().set_input_as_handled()


func _on_menu_button() -> void:
	# Routed through main so the HUD does not need to know about the menu layer.
	var main := get_tree().get_first_node_in_group("Main")
	if main and main.has_method("trigger_action"):
		AudioManager.play_sfx("click")
		main.trigger_action("open_pause")

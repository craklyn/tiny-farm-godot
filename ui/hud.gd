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
var energy_label: Label
var energy_bar_bg: ColorRect
var energy_bar_fill: ColorRect
var gold_label: Label
var tool_icon_rect: TextureRect
var tool_name_label: Label
var seed_info_label: Label
var seed_counts_label: Label
var water_label: Label
var seed_pill: Panel
var seed_pill_label: Label
var toast_panel: Panel
var toast_label: Label
var hint_label: Label

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

	# Energy bar background
	energy_bar_bg = ColorRect.new()
	energy_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	energy_bar_bg.position = Vector2(viewport_size.x / 2 - 60, 5)
	energy_bar_bg.size = Vector2(120, 20)
	top_bar.add_child(energy_bar_bg)

	# Energy bar fill
	energy_bar_fill = ColorRect.new()
	energy_bar_fill.position = Vector2(viewport_size.x / 2 - 59, 6)
	energy_bar_fill.size = Vector2(118, 18)
	top_bar.add_child(energy_bar_fill)

	# Energy text
	energy_label = Label.new()
	energy_label.position = Vector2(viewport_size.x / 2 - 50, 5)
	energy_label.size = Vector2(100, 20)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_label.add_theme_color_override("font_color", Color.WHITE)
	top_bar.add_child(energy_label)

	# Gold label
	gold_label = Label.new()
	gold_label.position = Vector2(viewport_size.x - 80, 5)
	gold_label.size = Vector2(70, 20)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	top_bar.add_child(gold_label)

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

	# Seed counts
	seed_counts_label = Label.new()
	seed_counts_label.position = Vector2(viewport_size.x / 2 - 80, 6)
	seed_counts_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7))
	bottom_bar.add_child(seed_counts_label)

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


func _update_hud() -> void:
	if not seed_pill_label:
		return
	# Top bary & Weather
	day_label.text = "Day %d" % GameState.day
	
	var w_icon := "☀️" if GameState.weather == "sunny" else "🌧️"
	weather_label.text = "%s %s" % [w_icon, GameState.weather.capitalize()]

	# Energy
	var fill_ratio := float(GameState.energy) / float(GameState.max_energy)
	var r := 0.3 + 0.7 * (1.0 - fill_ratio)
	var g := 0.3 + 0.7 * fill_ratio
	energy_bar_fill.color = Color(r, g, 0.2, 0.9)
	energy_bar_fill.size.x = 118.0 * fill_ratio
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

	# Seed counts
	var parts: PackedStringArray = []
	for crop_name in CropDefs.ORDER:
		var count: int = GameState.seeds.get(crop_name, 0)
		var abbrev: String = crop_name.substr(0, 2).capitalize()
		parts.append("%s:%d" % [abbrev, count])
	seed_counts_label.text = "  ".join(parts)

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

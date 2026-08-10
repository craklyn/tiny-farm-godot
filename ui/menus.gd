# menus.gd — Pause, shop, and inventory overlay menus
# Mirrors the Love2D ui_menus.lua
extends CanvasLayer

signal menu_action(action: String)

var active_menu: String = ""  # "", "pause", "shop", "inventory"
var selected_option: int = 0
var shop_items: Array[Dictionary] = []

# UI elements
var dim_overlay: ColorRect
var menu_panel: Panel
var title_label: Label
var options_container: VBoxContainer
var gold_display: Label


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS  # Work even when paused

	var viewport_size := get_viewport().get_visible_rect().size

	# Dim background
	dim_overlay = ColorRect.new()
	dim_overlay.color = Color(0, 0, 0, 0.5)
	dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	dim_overlay.visible = false
	add_child(dim_overlay)

	# Menu panel
	menu_panel = Panel.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	panel_style.border_color = Color(0.4, 0.4, 0.5, 0.8)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	menu_panel.add_theme_stylebox_override("panel", panel_style)
	menu_panel.size = Vector2(300, 200)
	menu_panel.position = Vector2(viewport_size.x / 2 - 150, viewport_size.y / 2 - 100)
	menu_panel.visible = false
	add_child(menu_panel)

	# Title
	title_label = Label.new()
	title_label.position = Vector2(10, 10)
	title_label.size = Vector2(280, 30)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	title_label.add_theme_font_size_override("font_size", 18)
	menu_panel.add_child(title_label)

	# Gold display (for shop)
	gold_display = Label.new()
	gold_display.position = Vector2(200, 10)
	gold_display.size = Vector2(90, 30)
	gold_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_display.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	gold_display.visible = false
	menu_panel.add_child(gold_display)

	# Options container
	options_container = VBoxContainer.new()
	options_container.position = Vector2(10, 45)
	options_container.size = Vector2(280, 300)
	menu_panel.add_child(options_container)


func open_menu(menu_name: String) -> void:
	active_menu = menu_name
	selected_option = 0
	dim_overlay.visible = true
	menu_panel.visible = true
	get_tree().paused = (menu_name == "pause")
	_rebuild_options()


func close_menu() -> void:
	active_menu = ""
	dim_overlay.visible = false
	menu_panel.visible = false
	get_tree().paused = false


func is_open() -> bool:
	return active_menu != ""


func _rebuild_options() -> void:
	# Clear existing options
	for child in options_container.get_children():
		child.queue_free()

	var viewport_size := get_viewport().get_visible_rect().size

	match active_menu:
		"pause":
			title_label.text = "PAUSED"
			gold_display.visible = false
			_add_option("Resume", true)
			_add_option("Quit", true)
			menu_panel.size = Vector2(300, 130)

		"shop":
			title_label.text = "SEED SHOP"
			gold_display.visible = true
			gold_display.text = "%dg" % GameState.gold
			_build_shop_items()
			for item in shop_items:
				var label_text: String
				if not item.unlocked:
					label_text = "??? (locked)"
				else:
					label_text = "%s - %dg" % [item.item_name, item.price]
				_add_option(label_text, item.affordable)
			_add_option("Close", true)
			menu_panel.size = Vector2(300, 60 + (shop_items.size() + 1) * 30)

		"inventory":
			title_label.text = "INVENTORY"
			gold_display.visible = false

			# Seeds section
			var seeds_header := Label.new()
			seeds_header.text = "Seeds:"
			seeds_header.add_theme_color_override("font_color", Color(0.7, 0.9, 0.6))
			options_container.add_child(seeds_header)
			for crop_name in CropDefs.ORDER:
				var def: Dictionary = CropDefs.TYPES[crop_name]
				var count: int = GameState.seeds.get(crop_name, 0)
				var lbl := Label.new()
				lbl.text = "  %s: %d" % [def.name, count]
				lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
				options_container.add_child(lbl)

			# Crops section
			var crops_header := Label.new()
			crops_header.text = "\nHarvested Crops:"
			crops_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
			options_container.add_child(crops_header)
			for crop_name in CropDefs.ORDER:
				var def: Dictionary = CropDefs.TYPES[crop_name]
				var count: int = GameState.crops.get(crop_name, 0)
				var lbl := Label.new()
				lbl.text = "  %s: %d" % [def.name, count]
				lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
				options_container.add_child(lbl)

			# Shipping bin
			var bin_header := Label.new()
			bin_header.text = "\nShipping Bin:"
			bin_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
			options_container.add_child(bin_header)
			for crop_name in CropDefs.ORDER:
				var def: Dictionary = CropDefs.TYPES[crop_name]
				var count: int = GameState.shipping_bin.get(crop_name, 0)
				var lbl := Label.new()
				lbl.text = "  %s: %d" % [def.name, count]
				lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
				options_container.add_child(lbl)

			_add_option("\nClose", true)
			menu_panel.size = Vector2(300, 340)

	menu_panel.position = Vector2(
		viewport_size.x / 2 - menu_panel.size.x / 2,
		viewport_size.y / 2 - menu_panel.size.y / 2
	)


func _add_option(text: String, enabled: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if enabled:
		btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.8))
		btn.add_theme_color_override("font_focus_color", Color(1, 1, 0.8))
	else:
		btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.6))
		btn.disabled = true

	var idx := options_container.get_child_count()
	btn.pressed.connect(_on_option_pressed.bind(idx))
	btn.focus_entered.connect(func(): selected_option = idx)
	options_container.add_child(btn)


func _on_option_pressed(index: int) -> void:
	selected_option = index
	_select_current_option()


func _input(event: InputEvent) -> void:
	if not is_open():
		return

	if event.is_action_pressed("pause"):
		close_menu()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("action"):
		_select_current_option()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("move_up"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate(1)
		get_viewport().set_input_as_handled()


func _navigate(direction: int) -> void:
	var button_count := _get_button_count()
	if button_count == 0:
		return
	# Find currently focused button
	selected_option = (selected_option + direction + button_count) % button_count
	_focus_current()


func _get_button_count() -> int:
	var count := 0
	for child in options_container.get_children():
		if child is Button:
			count += 1
	return count


func _focus_current() -> void:
	var button_idx := 0
	for child in options_container.get_children():
		if child is Button:
			if button_idx == selected_option:
				child.grab_focus()
				return
			button_idx += 1


func _select_current_option() -> void:
	match active_menu:
		"pause":
			if selected_option == 0:
				close_menu()
				menu_action.emit("resume")
			elif selected_option == 1:
				menu_action.emit("quit")

		"shop":
			if selected_option < shop_items.size():
				var item: Dictionary = shop_items[selected_option]
				if GameState.buy_seed(item.seed_type):
					_rebuild_options()
					menu_action.emit("bought_seed")
			else:
				close_menu()
				menu_action.emit("resume")

		"inventory":
			close_menu()
			menu_action.emit("resume")


func _build_shop_items() -> void:
	shop_items.clear()
	for crop_name in CropDefs.ORDER:
		var def: Dictionary = CropDefs.TYPES[crop_name]
		var unlocked := CropDefs.is_seed_unlocked(crop_name, GameState.harvest_counts)
		var affordable: bool = GameState.gold >= def.seed_price and unlocked
		shop_items.append({
			"seed_type": crop_name,
			"item_name": def.name + " Seeds",
			"price": def.seed_price,
			"unlocked": unlocked,
			"affordable": affordable,
		})

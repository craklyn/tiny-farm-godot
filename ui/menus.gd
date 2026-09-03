# menus.gd — Pause, shop, and inventory overlay menus
# Mirrors the Love2D ui_menus.lua
extends CanvasLayer

var farm: Node2D = null  # set by main before any menu can open; transactions route through the sim

signal menu_action(action: String)

# Panel metrics. The pause panel used a hard-coded height and its second option
# hung out of the box; anything list-shaped sizes itself from these now.
const OPTION_H := 52.0
const OPTION_SEP := 4.0
const OPTIONS_TOP := 45.0
const PANEL_PAD := 12.0

# Where the look lab's lines start in the pause menu: after Resume and Return to
# Title, and one line per open axis (`LookLab.AXES`). Named rather than spelled
# `== 2`, because T-28 turned one debug line into three and the next axis will
# not want to find this arithmetic by reading it.
const PAUSE_LAB_FIRST := 2

# What each of the robot's three settings is called in its menu (2026-09-03).
# Plain descriptions of what it will do rather than the engineering words the
# sim uses ("follow"/"circle"/"shoo"), because the player is choosing a job for a
# machine, not naming a mode. Q-87 is the open question of doing this with
# pictures instead of words.
const CONFIG_LABELS := {
	"shoo": "Chase birds off",
	"follow": "Follow me",
	"circle": "Circle me",
}

var active_menu: String = ""  # "", "pause", "shop", "inventory", "machine"
var selected_option: int = 0
var shop_items: Array[Dictionary] = []

# The machine menu (2026-09-03) — what a tap on a placed machine opens, and what
# a freshly placed one opens by itself.
#
# **It remembers the machine, not the square.** The tap resolves a tile to an
# actor id once, and from then on the panel follows that actor: a robot on
# "follow me" is walking the whole time the panel is up, and a menu keyed to the
# tile it was standing on when she tapped would go dead the moment it took a
# step. Everything else — which settings exist, which one is ticked, whether it is
# still there at all — is read back off the sim on every rebuild, so the panel
# cannot show a stale answer.
#
# The Actions it sends are still **tile-targeted**, like every other verb in the
# game; the tile is looked up from the id at the moment she taps, so the replay
# records the square the machine was actually standing on.
var machine_id: String = ""
var machine_options: Array[Dictionary] = []

# UI elements
var dim_overlay: ColorRect
var menu_panel: Panel
var title_label: Label
var shop_title_icon: TextureRect
var gold_icon: TextureRect
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

	# T-12 (Q-35): the shop's own header, as a picture. The seed packet says
	# "seeds are sold here" to someone who cannot read "SEED SHOP".
	shop_title_icon = TextureRect.new()
	shop_title_icon.name = "shop_title_icon"
	shop_title_icon.position = Vector2(10, 8)
	shop_title_icon.size = Vector2(26, 26)
	shop_title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shop_title_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shop_title_icon.texture = crop_icon(0)
	shop_title_icon.visible = false
	menu_panel.add_child(shop_title_icon)

	# And the coin beside the gold count, so the number has a unit she can read.
	gold_icon = TextureRect.new()
	gold_icon.name = "gold_icon"
	gold_icon.position = Vector2(176, 10)
	gold_icon.size = Vector2(22, 22)
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gold_icon.texture = coin_icon()
	gold_icon.visible = false
	menu_panel.add_child(gold_icon)
	menu_panel.add_child(gold_display)

	# Options container
	options_container = VBoxContainer.new()
	options_container.position = Vector2(10, OPTIONS_TOP)
	options_container.add_theme_constant_override("separation", int(OPTION_SEP))
	options_container.size = Vector2(280, 300)
	menu_panel.add_child(options_container)


func open_menu(menu_name: String) -> void:
	active_menu = menu_name
	selected_option = 0
	dim_overlay.visible = true
	menu_panel.visible = true
	menu_panel.pivot_offset = menu_panel.size / 2.0
	menu_panel.scale = Vector2(0.8, 0.8)
	
	var tween = create_tween()
	tween.tween_property(menu_panel, "scale", Vector2(1, 1), 0.2).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	
	# **While any menu is open, the world holds.** This used to pause only for the
	# pause screen, so with the shop up the player was frozen (main._process
	# returns early on is_open()) while every entity carried on living. Reported
	# from play 2026-08-29: "the chicken advances by a big jump when I bought in
	# the shop" — she had simply been walking the whole time, behind a panel.
	# A menu is not a place the game continues without you.
	get_tree().paused = true
	_rebuild_options()


## Open the machine panel on the machine standing at `at`.
##
## Called by `main.gd` for two things that are the same beat: a tap on a machine,
## and the moment one is placed. If nothing is standing there — she picked it up,
## or it walked off — nothing opens, because a panel about an absent machine has
## no honest content.
func open_machine_menu(at: Vector2i) -> void:
	if farm == null:
		return
	open_machine_menu_for(farm.sim.machine_at(at))


## The same panel, opened on a machine by name.
##
## The entry point a *placement* uses, and the tap path resolves to it too. Both
## callers know the id at the moment the player acted, which is what closes the
## one-frame race a moving machine would otherwise have: a shoo-bot's first
## thought is scheduled for the tick after it lands, so keying the open on the
## square it was put down on could miss it by a step.
func open_machine_menu_for(id: String) -> void:
	if farm == null or id == "" or not farm.sim.has_actor(id):
		return
	machine_id = id
	open_menu("machine")


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
		options_container.remove_child(child)
		child.queue_free()

	var viewport_size := get_viewport().get_visible_rect().size

	match active_menu:
		"pause":
			title_label.text = "PAUSED"
			gold_display.visible = false
			shop_title_icon.visible = false
			gold_icon.visible = false
			_add_option("Resume", true)
			_add_option("Return to Title", true)
			# The look lab, where the designer can actually reach it — one line per
			# open question (T-27's cot, T-28's two station axes; see
			# `systems/look_lab.gd`), each naming where it currently stands.
			#
			# The same candidates sit behind the title screen's "Look Lab" panel,
			# which is Q-31's Sound Test precedent proper — but a look that only
			# shows itself at dusk, or only when the basket has something in it,
			# cannot be judged from the title screen without reloading the farm for
			# every comparison. From here it is two taps and the farm is still where
			# he left it: tap, the menu closes, the world is wearing the next
			# treatment. Debug builds only, exactly like the Sound Test, so a public
			# build never shows it (S-7: no words in the game).
			if OS.is_debug_build():
				for axis in LookLab.AXES:
					_add_option(LookLab.option_label(axis), true)
			menu_panel.size = Vector2(300, _fit_panel_height())

		"shop":
			# T-12 (Q-35): **the shop is the one screen in phase 1 that required
			# reading**, and guiding a pre-reader into a screen she cannot read is
			# worse than not guiding her at all. So: a seed-packet header instead
			# of "SEED SHOP", a coin beside the gold count instead of "g", crop
			# icons instead of names, and an ✕ instead of "Close". Numerals stay —
			# S-7 forbids required *reading*, not digits.
			title_label.text = ""
			shop_title_icon.visible = true
			gold_icon.visible = true
			gold_display.visible = true
			gold_display.text = "%d" % GameState.gold
			gold_display.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
			_build_shop_items()
			for item in shop_items:
				_add_shop_card(item)
			# ✕ — a symbol, not a word. The row is already full-width and 52px
			# tall, so the *target* was never the problem; the glyph was.
			_add_option("\u2715", true, 28)
			menu_panel.size = Vector2(300, 60 + shop_items.size() * 56 + 40)

		"machine":
			# **The interface a machine gets when you select it**, and it is a
			# different panel per *mark*, because the two robots are different
			# kinds of thing to own (designer, 2026-09-03).
			#
			#   mark-1  you teach it a list of tiles, then send it out for the day.
			#           It decides nothing; the panel is the two verbs that make
			#           that true.
			#   mark-2  you set it to one of three standing behaviours and it gets
			#           on with them.
			#   a sprinkler, or anything else with neither, gets the one row every
			#           machine has: pick it up.
			#
			# "Pick up" is the same `collect` verb an egg gets, so nothing here is
			# a capability the player did not already have.
			#
			# Words, for now, and knowingly against S-7's no-required-reading rule:
			# there is no icon vocabulary yet for any of it. Filed for the designer
			# as Q-87; the shop, which a pre-reader must use to play at all, stays
			# wordless.
			var mid: String = machine_id if farm != null and farm.sim.has_actor(machine_id) else ""
			var mkey: String = farm.sim.machine_key_of(mid) if mid != "" else ""
			title_label.text = MachineDefs.name_of(mkey).to_upper() if mkey != "" else ""
			gold_display.visible = false
			shop_title_icon.visible = false
			gold_icon.visible = false

			machine_options.clear()
			var mextra: Dictionary = farm.sim.actor(mid).get("extra", {}) if mid != "" else {}
			match MachineDefs.program_of(mkey):
				"orders":
					var taught: int = BotBrain.orders_of(mextra).size()
					var been_out: bool = bool(mextra.get("ran_today", false))
					var out_now: bool = bool(mextra.get("sent", false))
					machine_options.append({ "kind": "teach" })
					_add_option("Show it what to water  (%d/%d)"
						% [taught, BotBrain.ORDER_LIMIT], not out_now)
					# One row that says all three states it can be in, because
					# "why is this greyed out" is the question a disabled control
					# always asks and there is nowhere else here to answer it.
					machine_options.append({ "kind": "activate" })
					if out_now:
						_add_option("Out working…", false)
					elif been_out:
						_add_option("Been out today", false)
					elif taught <= 0:
						_add_option("Send it out  (nothing to do yet)", false)
					else:
						_add_option("Send it out  (%d tiles)" % taught, true)
				"configs":
					var current: String = String(mextra.get("config", ""))
					for config in MachineDefs.configs_of(mkey):
						# The tick is the whole state readout: which of these it is
						# doing now. A machine already on this setting still offers
						# the row — tapping it is a harmless no-op, and greying it
						# out would make the panel look broken to somebody who just
						# wanted to check.
						var mark: String = "\u2713 " if config == current else "   "
						machine_options.append({ "kind": "config", "config": config })
						_add_option(mark + CONFIG_LABELS.get(config, config), true)
			machine_options.append({ "kind": "collect" })
			_add_option("Pick up", true)
			machine_options.append({ "kind": "close" })
			_add_option("\u2715", true, 28)
			menu_panel.size = Vector2(320, _fit_panel_height())

		"inventory":
			title_label.text = "INVENTORY"
			gold_display.visible = false
			shop_title_icon.visible = false
			gold_icon.visible = false

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


			_add_option("\nClose", true)
			menu_panel.size = Vector2(300, 340)

	# Shrink the container to its contents: left at its declared 300px it extends
	# past the panel and can swallow taps aimed at the world below it.
	options_container.size = Vector2(
		menu_panel.size.x - 2 * 10,
		max(0.0, menu_panel.size.y - OPTIONS_TOP - PANEL_PAD)
	)

	menu_panel.position = Vector2(
		viewport_size.x / 2 - menu_panel.size.x / 2,
		viewport_size.y / 2 - menu_panel.size.y / 2
	)


# Height that exactly contains the options currently in the container.
func _fit_panel_height() -> float:
	var n := options_container.get_child_count()
	if n <= 0:
		return OPTIONS_TOP + PANEL_PAD
	return OPTIONS_TOP + n * OPTION_H + (n - 1) * OPTION_SEP + PANEL_PAD


# crops.png row 2 holds the shop iconography: wheat packet, tomato packet,
# scarecrow, and (added 2026-08-30 for T-12) a coin.
const ICON_SHEET := preload("res://assets/sprites/generated/crops.png")
const COIN_COL := 3


static func crop_icon(sprite_row: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = ICON_SHEET
	atlas.region = Rect2(sprite_row * 16, 32, 16, 16)
	return atlas


static func coin_icon() -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = ICON_SHEET
	atlas.region = Rect2(COIN_COL * 16, 32, 16, 16)
	return atlas


func _add_icon_number(row: HBoxContainer, tex: Texture2D, text: String, size: float,
		colour: Color) -> void:
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(size, size)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.texture = tex
	row.add_child(pic)
	var lbl := Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", colour)
	row.add_child(lbl)


func _add_option(text: String, enabled: bool, font_size: int = 0) -> void:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(0, OPTION_H)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.25, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	container.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(hbox)
	
	var lbl = Label.new()
	lbl.text = text
	if font_size > 0:
		lbl.add_theme_font_size_override("font_size", font_size)
	if enabled:
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
	else:
		lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.6))
	hbox.add_child(lbl)
	
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(btn)
	
	if not enabled:
		btn.disabled = true

	var idx := options_container.get_child_count()
	btn.pressed.connect(_on_option_pressed.bind(idx))
	btn.focus_entered.connect(func(): selected_option = idx)
	options_container.add_child(container)


func _add_shop_card(item: Dictionary) -> void:
	var container = PanelContainer.new()
	var style = StyleBoxFlat.new()
	if item.affordable:
		style.bg_color = Color(0.18, 0.18, 0.25, 0.6)
	else:
		style.bg_color = Color(0.1, 0.1, 0.15, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	container.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	container.add_child(hbox)
	
	# The crop's own packet, always drawn. A locked item is the **same picture,
	# darkened** — never an empty box and never "???", which tells a pre-reader
	# nothing except that something is missing. Same vocabulary as the placed
	# tools she cannot pick up yet (Q-46a), so "you can see it, not yet yours"
	# looks the same everywhere in the game.
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = item.icon
	if not item.unlocked:
		icon.modulate = Color(0.12, 0.11, 0.18, 0.85)
	hbox.add_child(icon)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	if item.unlocked:
		# What it costs, and what she already has: coin + numeral, packet + numeral.
		var price_row := HBoxContainer.new()
		price_row.alignment = BoxContainer.ALIGNMENT_END
		hbox.add_child(price_row)
		_add_icon_number(price_row, coin_icon(), str(item.price), 20.0,
			Color(1, 0.85, 0.2) if item.affordable else Color(0.9, 0.3, 0.3))

		var owned_row := HBoxContainer.new()
		owned_row.alignment = BoxContainer.ALIGNMENT_END
		owned_row.custom_minimum_size = Vector2(58, 0)
		hbox.add_child(owned_row)
		_add_icon_number(owned_row, item.icon,
			"\u00d7%d" % int(item.owned), 18.0, Color(0.72, 0.82, 0.7))
	
	# Transparent button overlay for clicks
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(btn)
	
	if not item.unlocked or not item.affordable:
		btn.disabled = true
	
	var idx = options_container.get_child_count()
	btn.pressed.connect(_on_shop_card_pressed.bind(idx, container))
	btn.focus_entered.connect(func(): selected_option = idx)
	options_container.add_child(container)

func _on_shop_card_pressed(index: int, container: Control) -> void:
	selected_option = index
	container.pivot_offset = container.size / 2.0
	
	var tween = create_tween()
	tween.tween_property(container, "scale", Vector2(0.95, 0.95), 0.05)
	tween.tween_property(container, "scale", Vector2(1, 1), 0.1)
	
	# Small delay to let the animation play
	await get_tree().create_timer(0.1).timeout
	_select_current_option()


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
				close_menu()
				menu_action.emit("return_to_title")
			elif OS.is_debug_build() and selected_option >= PAUSE_LAB_FIRST \
					and selected_option < PAUSE_LAB_FIRST + LookLab.AXES.size():
				# Advance that one axis and get out of the way — the whole value of
				# this switch is seeing the farm immediately afterwards. `main.gd`
				# picks the change up on "look_lab" and names the axis and its new
				# treatment in a toast. Each axis moves on its own, because T-28's
				# two problems have to be judgeable one at a time.
				LookLab.cycle(LookLab.AXES[selected_option - PAUSE_LAB_FIRST])
				close_menu()
				menu_action.emit("look_lab")

		"shop":
			if selected_option < shop_items.size():
				var item: Dictionary = shop_items[selected_option]
				# Transactions are sim Actions too (P-9 guardrail). Two verbs, one
				# per catalogue — see `SimWorld`'s `buy_machine` for why the seed
				# verb was not generalised to cover both.
				var purchase := { "actor": "player" }
				if String(item.kind) == "machine":
					purchase["verb"] = "buy_machine"
					purchase["item"] = item.seed_type
				else:
					purchase["verb"] = "buy_seed"
					purchase["seed_type"] = item.seed_type
				var bought: bool = farm.apply_action(purchase, GameState).get("ok", false)
				if bought:
					AudioManager.play_sfx("harvest")
					_rebuild_options()
					menu_action.emit("bought_seed")
			else:
				close_menu()
				menu_action.emit("resume")

		"machine":
			if selected_option >= machine_options.size():
				close_menu()
				menu_action.emit("resume")
				return
			var choice: Dictionary = machine_options[selected_option]
			if not farm.sim.has_actor(machine_id) or choice.get("kind", "") == "close":
				close_menu()
				menu_action.emit("resume")
				return
			# Where it is *now*, not where it was when she tapped: a bot on "follow
			# me" has been walking the whole time the panel was up.
			var mid_tile: Vector2i = farm.sim.actor_pos(machine_id)
			# Both branches are sim Actions (P-9 guardrail): the panel decides
			# nothing, it asks the one gateway and shows what came back.
			if choice.kind == "config":
				var set_ok: bool = farm.apply_action({
					"verb": "configure", "target": mid_tile,
					"config": choice.config, "actor": "player",
				}, GameState).get("ok", false)
				if set_ok:
					AudioManager.play_sfx("jingle")
					_rebuild_options()
					menu_action.emit("configured_machine")
				return
			if choice.kind == "teach":
				# The panel gets out of the way: teaching happens on the farm, with
				# her finger, and a modal over the plot is the one thing that
				# cannot work. `main.gd` owns the mode.
				close_menu()
				menu_action.emit("resume")
				var main_node := get_tree().get_first_node_in_group("Main")
				if main_node != null and main_node.has_method("begin_teaching"):
					main_node.begin_teaching(machine_id)
				return
			if choice.kind == "activate":
				var sent: bool = farm.apply_action({
					"verb": "activate", "target": mid_tile, "actor": "player",
				}, GameState).get("ok", false)
				if sent:
					AudioManager.play_sfx("jingle")
				close_menu()
				menu_action.emit("resume")
				return
			if choice.kind == "collect":
				var took: bool = farm.apply_action({
					"verb": "collect", "target": mid_tile, "actor": "player",
				}, GameState).get("ok", false)
				if took:
					AudioManager.play_sfx("harvest")
				close_menu()
				menu_action.emit("resume")

		"inventory":
			close_menu()
			menu_action.emit("resume")


# The shop's stock: seeds first, then machines (2026-09-03, the placeholder
# acquisition rule). Two catalogues rather than one, because a seed and a machine
# are genuinely different purchases — one goes in the ground and one gets placed
# and starts working — and `kind` is what the card and the transaction below key
# off. Adding a purchasable thing is a row in `CropDefs.ORDER` or
# `MachineDefs.ORDER`; nothing in this file has to learn its name.
func _build_shop_items() -> void:
	shop_items.clear()
	for crop_name in CropDefs.ORDER:
		var def: Dictionary = CropDefs.TYPES[crop_name]
		var unlocked := CropDefs.is_seed_unlocked(crop_name, GameState.harvest_counts)
		var affordable: bool = GameState.gold >= def.seed_price and unlocked
		shop_items.append({
			"kind": "seed",
			"seed_type": crop_name,
			"item_name": def.name,
			"price": def.seed_price,
			"unlocked": unlocked,
			"affordable": affordable,
			"icon": crop_icon(int(def.sprite_row)),
			"owned": GameState.seeds.get(crop_name, 0)
		})
	for machine_key in MachineDefs.ORDER:
		var mdef: Dictionary = MachineDefs.TYPES[machine_key]
		var munlocked := MachineDefs.is_unlocked(machine_key, GameState.harvest_counts)
		shop_items.append({
			"kind": "machine",
			"seed_type": machine_key,
			"item_name": mdef.name,
			"price": int(mdef.price),
			"unlocked": munlocked,
			"affordable": GameState.gold >= int(mdef.price) and munlocked,
			"icon": MachineDefs.icon_of(machine_key),
			"owned": GameState.machines.get(machine_key, 0)
		})

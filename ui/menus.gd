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

# The shop's shelf, in columns (2026-09-10). One card per row sized the panel
# past the bottom of the screen and, because every panel here is centred, off the
# **top** as well — the header and the first two rows of stock were simply gone
# (found by the designer's wife mid-playthrough, with ten things on the shelf).
# A column of ten is also the wrong shape for a shelf: she is picking a picture
# out of a set, not reading down a list. Cards keep their full 52px height, so
# nothing about the target a thumb aims at gets smaller.
const SHOP_COLUMNS := 2
const SHOP_PANEL_W := 480.0
const SHOP_CARD_H := 52.0
# Wider than the gap between rows, because the columns are what a reader could
# confuse: side by side, two cards 4px apart read as one long row.
const SHOP_GUTTER := 16

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
	# Both a job and the off switch: it is what a machine is before she has
	# chosen one, and what she picks when she wants it to stop without picking
	# it up. Named for what the machine does rather than for the absence of a
	# setting — "none selected" would be a fact about the panel, not about the farm.
	"idle": "Wait here",
}

var active_menu: String = ""  # "", "pause", "shop", "inventory", "machine", "workbench"
var selected_option: int = 0

# **What number the next row on a panel gets.** `_select_current_option` reads a
# tap back as a position in a list — `shop_items[n]`, `machine_options[n]` — so
# every row has to know its own place in that list as it is built.
#
# It used to be `options_container.get_child_count()`, which held only while one
# row meant one child. The shop's shelf broke that the moment it became a grid:
# ten cards inside one child left the ✕ underneath them numbered 1, so tapping
# it "bought" the second thing on the shelf — a locked packet, which fails
# silently, so the close button simply stopped working (found on the tablet,
# 2026-09-10). Counting rows instead of children is true however they are nested.
var next_option: int = 0
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

# The training workbench (Q-101, 2026-09-10) — the fifth mode of this file, and
# the only one that is not a list of rows.
#
# **A mode here rather than a screen of its own**, because everything a screen
# needs is already in this file: the world holds while it is open, the dim behind
# it, `is_open()` so the world's taps stop landing, and the pause key that closes
# whatever is up. A second CanvasLayer would have been a second copy of all four.
# `menu_panel` is hidden in this mode; the bench draws its own card.
var workbench: Workbench = null

## The square the open bench stands on. Kept so a refresh can find it again.
var workbench_tile: Vector2i = Vector2i(-1, -1)


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

	# The workbench, added last so it sits above the dim and above the panel it
	# replaces. Hidden until `open_workbench` puts a robot on it.
	workbench = Workbench.new()
	workbench.closed.connect(close_menu)
	add_child(workbench)


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


## Open the training workbench standing at `at` (Q-101, 2026-09-10).
##
## The machine panel's shape, one level up: `open_menu` does the pausing, the dim
## and the option rebuild, and then the bench takes the screen while `menu_panel`
## steps out of the way. `machine_id` is handed on as the preferred robot — she
## most likely walked to the bench from the machine she was just looking at, and a
## bench that opened on a different robot than the one she tapped would be wrong
## about what she came to do.
func open_workbench(at: Vector2i) -> void:
	if farm == null or workbench == null:
		return
	workbench_tile = at
	open_menu("workbench")
	menu_panel.visible = false
	workbench.show_bench(farm, at, machine_id)
	workbench.visible = true


func close_menu() -> void:
	active_menu = ""
	dim_overlay.visible = false
	menu_panel.visible = false
	if workbench != null:
		workbench.visible = false
	get_tree().paused = false


func is_open() -> bool:
	return active_menu != ""


func _rebuild_options() -> void:
	# Clear existing options
	for child in options_container.get_children():
		options_container.remove_child(child)
		child.queue_free()
	next_option = 0

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
			#
			# **And one line under them that puts them all back** (2026-09-08).
			# The designer opened this menu at the tablet, met lines he did not
			# recognise, and read back two axes that were not on their picks —
			# because a look line advances on a tap and closes the menu, which is
			# what makes it good for comparing and what makes it easy to nudge in
			# passing. A switch that changes the game quietly is a trap: every
			# session he plays and reports afterwards is a report about a build
			# nobody ships. So a line off its pick now says what the pick is, and
			# this puts the lot back in one press. Greyed rather than hidden when
			# there is nothing to undo, which is the answer design/11 already gave
			# for the teaching mode's clear-all — a control that comes and goes is
			# one he has to hunt for.
			#
			# Nothing at all while no look question is open, which is the state
			# as of 2026-09-08 — a put-back line for a set of zero switches is
			# furniture that explains nothing.
			if OS.is_debug_build() and not LookLab.AXES.is_empty():
				for axis in LookLab.AXES:
					_add_option(LookLab.option_label(axis), true)
				_add_option(LookLab.restore_label(),
					not LookLab.changed_axes().is_empty())
			menu_panel.size = Vector2(_fit_panel_width(300.0), _fit_panel_height())

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
			var shelf := GridContainer.new()
			shelf.name = "shop_shelf"
			shelf.columns = SHOP_COLUMNS
			shelf.add_theme_constant_override("h_separation", SHOP_GUTTER)
			shelf.add_theme_constant_override("v_separation", int(OPTION_SEP))
			options_container.add_child(shelf)
			for item in shop_items:
				_add_shop_card(shelf, item)
			# × — a symbol, not a word. The row is already full-width and 52px
			# tall, so the *target* was never the problem; the glyph was — twice:
			# U+2715 ✕ lives outside the bundled font, and the web export has no
			# system-font fallback, so the itch build drew the close button as a
			# codepoint-in-a-box (found by the designer on v0.2.0's launch day).
			# U+00D7 is Latin-1, which the bundled font carries on every platform.
			# Any symbol on a surface a player sees must be Latin-1 or drawn art.
			_add_option("\u00d7", true, 28)
			# Measured from what is actually in the container, like every other
			# panel in this file — the arithmetic this replaced counted a row per
			# item and knew nothing about the close button underneath them.
			menu_panel.size = Vector2(
				minf(SHOP_PANEL_W, viewport_size.x - PANEL_PAD * 2.0),
				_fit_panel_height())
			# The coin and its numeral ride the right edge, which is no longer at
			# x=290: a header pinned to a width is a header that moves when the
			# panel does not.
			gold_display.position.x = menu_panel.size.x - 10.0 - gold_display.size.x
			gold_icon.position.x = gold_display.position.x - 24.0

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
			#   mark-3  there is nothing to set: it is working out its own job. The
			#           panel is what it has to show for that so far — the nights
			#           it has practised and the squares it watered yesterday.
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
					# Not "what to water" since 2026-09-07: it tills bare ground and
					# waters soil, so the row has to name the job rather than one of
					# the two verbs it might turn out to be.
					_add_option("Show it where to work  (%d/%d)"
						% [taught, BotBrain.ORDER_LIMIT], not out_now)
					# One row that says all three states it can be in, because
					# "why is this greyed out" is the question a disabled control
					# always asks and there is nowhere else here to answer it.
					machine_options.append({ "kind": "activate" })
					if out_now and BotBrain.waiting_for_player(farm.sim):
						# It is sent, and standing in its bay because she is indoors
						# — the machines wait for her day to start (CEO, 2026-09-07).
						# Saying "Out working…" here was a straight lie, and the one
						# she caught: sent on a rainy morning from inside the house,
						# the panel claimed it was working while it had not moved.
						# A disabled row has to answer "why", and the answer is her.
						_add_option("Waiting for you outside", false)
					elif out_now:
						_add_option("Out working…", false)
					elif been_out:
						_add_option("Been out today", false)
					elif taught <= 0:
						_add_option("Send it out  (nothing to do yet)", false)
					elif not BotBrain.round_has_work(farm.sim, mextra):
						# Taught, unspent, and every square on the list already
						# needs nothing — rain has watered them and none has gone
						# bare. Sending it would spend its one turn on a walk that
						# changes nothing (Q-93).
						_add_option("Send it out  (nothing needs doing today)", false)
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
						var mark: String = "\u00bb " if config == current else "   "
						machine_options.append({ "kind": "config", "config": config })
						_add_option(mark + CONFIG_LABELS.get(config, config), true)
				"policy":
					# **The Mark III has no dial and no list**, so where the other
					# marks put rows this one puts its practice (Q-97, ruled
					# 2026-09-09). Its settings would be a dial that wiped weeks of
					# learning, which is why the catalogue row has no configs and the
					# gateway refuses `configure` on it outright.
					#
					# **A scorecard, replacing the two numerals (2026-09-10).** Q-97's
					# surface was a crescent and a can, one numeral each. The designer
					# met it on the tablet and asked for the whole day: a line per
					# thing the robot is paid for, one point per day. Two numbers could
					# say a robot earned twelve points; they could not say whether it
					# had learned to *sell* or had spent the week watering mud, and
					# that is the difference between a machine worth owning and one
					# that is not. `ui/bot_scorecard.gd` draws it, off the robot's own
					# record and nothing else (D-4).
					#
					# Still wordless but for numerals on the axes, and still a readout
					# rather than a control: nothing on it to press, so no tap of hers
					# can land on it and come back with nothing. It keeps its slot in
					# `machine_options`, because the rows below are tapped by their
					# position in that list.
					machine_options.append({ "kind": "practice" })
					_add_scorecard(mextra)
			machine_options.append({ "kind": "collect" })
			_add_option("Pick up", true)
			machine_options.append({ "kind": "close" })
			_add_option("\u00d7", true, 28)
			# **A wider card for the mark-3 only.** A fortnight of chart needs more
			# room than a column of buttons does, and the rows underneath it grow
			# with the panel rather than shrink: "pick it up" and the close button
			# keep every pixel of the target they had.
			menu_panel.size = Vector2(
				SCORECARD_PANEL_W if MachineDefs.program_of(mkey) == "policy" else 320.0,
				_fit_panel_height())

		"workbench":
			# **No rows at all.** The bench is its own full-rect Control
			# (`ui/workbench.gd`) and builds itself; this arm exists so the panel's
			# chrome — the last screen's title, its gold count, its seed packet —
			# is cleared rather than left showing behind a hidden panel, and so
			# that a reader of this `match` finds every mode of this file in it.
			title_label.text = ""
			gold_display.visible = false
			shop_title_icon.visible = false
			gold_icon.visible = false

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

	# Centred, but **never above the top edge**: a panel taller than the screen
	# used to lose its header and first rows off the top, where there is nothing
	# to tell her they exist. Clipped at the bottom is a panel she can see the top
	# of; clipped at the top is a panel that looks like it starts halfway down.
	# The arms above are meant to fit the viewport — this is the floor under them.
	menu_panel.position = Vector2(
		maxf(0.0, viewport_size.x / 2 - menu_panel.size.x / 2),
		maxf(0.0, viewport_size.y / 2 - menu_panel.size.y / 2)
	)


# Height that exactly contains the options currently in the container.
#
# **Each row's own height, summed** rather than `rows x OPTION_H` (2026-09-10).
# Every row was a button of the same height until the Mark III's scorecard, which
# is a chart several buttons tall; multiplying would have hung it out of the
# bottom of the panel — the same bug the pause menu shipped with once and the
# reason this function exists. A panel of ordinary rows gets exactly the height it
# always got, because a button's minimum height *is* `OPTION_H`.
func _fit_panel_height() -> float:
	var n := options_container.get_child_count()
	if n <= 0:
		return OPTIONS_TOP + PANEL_PAD
	var stack := 0.0
	for child in options_container.get_children():
		var h := OPTION_H
		if child is Control:
			h = maxf(h, (child as Control).get_combined_minimum_size().y)
		stack += h
	return OPTIONS_TOP + stack + (n - 1) * OPTION_SEP + PANEL_PAD


# **Wide enough to read the longest line on it**, measured rather than guessed.
#
# The pause menu was a fixed 300 wide and the look-lab lines have long outgrown
# it — "Already done: A · the answer names itself" was already running off the
# edge before anything was added to it (found 2026-09-08, when the designer met
# these lines on the tablet and could not tell what they were; a line he cannot
# read is a switch with no label). Only the pause menu asks for this: every other
# menu's rows are short, or are pictures.
#
# Clamped to the viewport with a margin, so a narrow phone gets a panel that
# fits the screen and clips the text rather than a panel that runs off it.
func _fit_panel_width(minimum: float) -> float:
	var widest := minimum
	for child in options_container.get_children():
		for label in _labels_in(child):
			var f: Font = label.get_theme_font("font")
			var size: int = label.get_theme_font_size("font_size")
			if f == null:
				continue
			widest = maxf(widest,
				f.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
					+ PANEL_PAD * 2.0)
	return minf(widest, get_viewport().get_visible_rect().size.x - PANEL_PAD * 2.0)


func _labels_in(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	if node is Label:
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels_in(child))
	return out


# shop_icons.png is the shop iconography in one row: wheat packet, tomato
# packet, scarecrow, (added 2026-08-30 for T-12) a coin, then T-28's droplet
# and basket.
const ICON_SHEET := preload("res://assets/sprites/generated/shop_icons.png")
const COIN_COL := 3


static func crop_icon(icon_col: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = ICON_SHEET
	atlas.region = Rect2(icon_col * 16, 0, 16, 16)
	return atlas


static func coin_icon() -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = ICON_SHEET
	atlas.region = Rect2(COIN_COL * 16, 0, 16, 16)
	return atlas


func _add_icon_number(row: HBoxContainer, tex: Texture2D, text: String, size: float,
		colour: Color, font_size: int = 0) -> void:
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(size, size)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.texture = tex
	row.add_child(pic)
	var lbl := Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font_size > 0:
		lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", colour)
	row.add_child(lbl)


# --- What a Mark III has to show for itself ----------------------------------
#
# It sits in the slot the other marks fill with rows, above "pick it up", and it
# is a chart: `ui/bot_scorecard.gd`, one line per row of the reward table, a point
# per day. It replaces the crescent-and-can pair Q-97 ruled on 2026-09-09, at the
# designer's request the day after he read that pair on the tablet — see the
# "policy" arm above for why one number a day was not enough.
#
# **The wide panel is for this**: 320 has no room for both a fortnight of days and
# the column of pictures that says which line is which.
const SCORECARD_PANEL_W := 380.0
const SCORECARD_INSET := 8.0


func _add_scorecard(extra: Dictionary) -> void:
	# A row with nothing to press is still a row: it holds the "practice" slot in
	# `machine_options`, and the rows under it are numbered past it.
	next_option += 1
	var card := BotScorecard.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Nothing behind it and nothing to press: a readout wearing a row's dark panel
	# would look like a control that does nothing when tapped.
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("margin_left", int(SCORECARD_INSET))
	holder.add_theme_constant_override("margin_right", int(SCORECARD_INSET))
	holder.add_child(card)
	options_container.add_child(holder)
	# The robot's own record, read once per rebuild rather than per frame: the
	# panel is rebuilt whenever anything on it could have changed, and a chart of
	# closed days has nothing to say in between.
	card.show_bot(extra)


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

	var idx := next_option
	next_option += 1
	btn.pressed.connect(_on_option_pressed.bind(idx))
	btn.focus_entered.connect(func(): selected_option = idx)
	options_container.add_child(container)


## One thing on the shelf: its picture, its price, and how many she already has.
##
## `into` is the shelf it is added to: the cards no longer sit directly in
## `options_container`, and the number a card comes back with is its place in
## `shop_items`, taken from `next_option` like every other row on every panel.
func _add_shop_card(into: Control, item: Dictionary) -> void:
	var idx := next_option
	next_option += 1
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(0, SHOP_CARD_H)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	
	# Inset from the card's own edges, so the picture and the price sit inside a
	# boundary rather than running to it. With two cards side by side, what tells
	# her a price belongs to the packet on its left is the gap on its right.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	container.add_child(pad)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	pad.add_child(hbox)
	
	# The crop's own packet, always drawn. A locked item is the **same picture,
	# darkened** — never an empty box and never "???", which tells a pre-reader
	# nothing except that something is missing. Same vocabulary as the placed
	# tools she cannot pick up yet (Q-46a), so "you can see it, not yet yours"
	# looks the same everywhere in the game.
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	# Exactly 34 wide whatever the picture is: a robot's sprite is wider than a
	# seed packet, and left to its own size it pushed that card's price out of
	# line with the prices above and below it.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = item.icon
	if not item.unlocked:
		icon.modulate = Color(0.12, 0.11, 0.18, 0.85)
	hbox.add_child(icon)

	if item.unlocked:
		# What it costs, and what she already has: coin + numeral, packet + numeral.
		# **Both pinned to the left, beside the picture they are about**, and the
		# slack left at the right end of the card (2026-09-10). Pushed to the far
		# edge — which is what one card per row made look natural — a price in a
		# two-column shelf ends up nearer the *next* thing's picture than its own.
		# The price columns line up card to card, so the shelf can be read down as
		# well as across.
		var price_row := HBoxContainer.new()
		price_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		price_row.custom_minimum_size = Vector2(66, 0)
		hbox.add_child(price_row)
		_add_icon_number(price_row, coin_icon(), str(item.price), 20.0,
			Color(1, 0.85, 0.2) if item.affordable else Color(0.9, 0.3, 0.3))

		var owned_row := HBoxContainer.new()
		owned_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		owned_row.custom_minimum_size = Vector2(52, 0)
		hbox.add_child(owned_row)
		_add_icon_number(owned_row, item.icon,
			"\u00d7%d" % int(item.owned), 18.0, Color(0.72, 0.82, 0.7))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	
	# Transparent button overlay for clicks
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(btn)
	
	if not item.unlocked or not item.affordable:
		btn.disabled = true
	
	btn.pressed.connect(_on_shop_card_pressed.bind(idx, container))
	btn.focus_entered.connect(func(): selected_option = idx)
	into.add_child(container)

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
			elif OS.is_debug_build() \
					and selected_option == PAUSE_LAB_FIRST + LookLab.AXES.size() \
					and not LookLab.changed_axes().is_empty():
				# Back to the picks, and out of the way like every other look line
				# — the farm is what he should be looking at when it changes back.
				LookLab.restore_all()
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
			"icon": crop_icon(int(def.icon_col)),
			"owned": GameState.seeds.get(crop_name, 0)
		})
	for machine_key in MachineDefs.ORDER:
		var mdef: Dictionary = MachineDefs.TYPES[machine_key]
		# **The sim answers what is for sale** (S-12). Two of these rows are rungs
		# of the robot ladder — the bench and the Mark III — and what has been
		# earned is a fact about the farm rather than about the row, so the card
		# asks the world the same question the till asks it (`SimWorld.offers`).
		# A locked row still draws: same picture, darkened, like a seed packet she
		# has not earned, so the shelf is what teaches the ladder.
		#
		# With no farm behind it nothing on this shelf is offered. The shop cannot
		# open before `main` hands the menus a farm, so this is a guard rather than
		# a case — and locking is the answer that cannot sell her something the
		# world would then refuse.
		var munlocked: bool = farm != null and farm.sim.offers(machine_key, GameState)
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

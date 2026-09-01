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

# --- The sun-arc (T-29 / Q-38's rider) ----------------------------------------
#
# An eighth of the top bar's width and all of its height: big enough that the
# token's move after one action is visible, small enough that it stays a status
# element beside the day counter rather than becoming the HUD.
#
# It is a **flattened** arc rather than a half circle, and that is forced rather
# than chosen: a semicircle wide enough to read is taller than the 30px bar, so a
# circular path would have its middle hours cut off by the top of the screen —
# which is the one part of the day a clock most needs to show. An ellipse keeps
# the whole path inside the bar and still rises and falls, which is the shape the
# reading depends on.
const ARC_W := 104.0
const ARC_H := 30.0
const ARC_RX := 46.0
const ARC_RY := 13.0
const ARC_CENTRE := Vector2(ARC_W / 2.0, 21.0)  # the horizon the token rises from
const ARC_STEPS := 48
const ARC_TOKEN_R := 4.0
const ARC_TICK := 3.0           # half a tick's length, either side of the path
# The top bar's own colour once its 60%-black panel has composited: what the moon
# is bitten out with, so the crescent reads as sky.
const MOON_CUT := Color(0.122, 0.122, 0.122)

# UI controls (created programmatically)
var top_bar: Panel
var bottom_bar: Panel
var day_label: Label
var weather_label: Label
var energy_label: Label  # T-14: debug builds only — the sky is the bar (Q-38)
var sun_arc: Control     # T-29: the hour, precisely and wordlessly
var clock_label: Label   # T-34: the same hour in digits, beside the arc
var gold_label: Label
var menu_button: Button
var bed_button: Button          # T-31 (Q-49): the HUD's one action control
var bed_button_icon: TextureRect
var tool_icon_rect: TextureRect
var tool_name_label: Label
var seed_info_label: Label
var crop_counts_label: Label
var water_label: Label
var seed_pill: Panel
var seed_pill_label: Label
var seed_pill_icon: TextureRect

# The pill sizes to its own words. Reported from play 2026-09-01: *"The pill drawn
# beneath the current selected item (e.g. scarecrow) .. the pill isn't big enough
# so the words spill over."* It was a fixed 100x24 with an 82px label inside it,
# which holds "wheat x5" and does not hold "scarecrow x1" — and the scarecrow is
# the one thing in the pouch with a long name, so the bug arrived with the item.
#
# The minimum is the width the pill has always been, so short names look exactly
# as they did; the maximum is a pill that still fits across a phone. Between them
# it is the icon, the measured string and a little air.
const PILL_ICON_W := 18.0
const PILL_PAD := 12.0
const PILL_MIN_W := 100.0
const PILL_MAX_W := 240.0
const PILL_H := 24.0


# Pure, so the suites can ask what a given string would need without a viewport.
static func pill_width(text_width: float) -> float:
	return clampf(PILL_ICON_W + text_width + PILL_PAD, PILL_MIN_W, PILL_MAX_W)

# T-28's satisfied treatment B — "the state shows before the tap". Built always,
# shown only under that treatment, so the default build is byte-for-byte the HUD
# it was and the visual baseline does not move.
var state_chips: Control
var basket_chip: TextureRect
var basket_pips: Array[ColorRect] = []
var can_chip: TextureRect
var can_gauge_back: ColorRect
var can_gauge_fill: ColorRect
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

# The collapse toggle (the designer, 2026-09-01) and its state. Small enough that
# a collapsed readout leaves a chip rather than a dead slab of button, which is
# the whole point of collapsing it.
const NOTES_TOGGLE_W := 22.0
const NOTES_TOGGLE_H := 18.0
static var notes_collapsed := false
var notes_toggle: Button

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
	# can read and "420/600" never was.
	#
	# T-29 (Q-38's rider) puts the *precise* read back in the bar without putting
	# the number back: a wordless sun-arc, centred, with a token that slides
	# sunrise→dusk as the day is spent. The tint says roughly what hour it is; the
	# arc says exactly, and neither needs reading (S-7). Drawn rather than
	# assembled from nodes because it is one small picture and a `_draw` costs no
	# tree.
	sun_arc = Control.new()
	sun_arc.name = "sun_arc"
	sun_arc.position = Vector2(viewport_size.x / 2 - ARC_W / 2.0, 0)
	sun_arc.size = Vector2(ARC_W, ARC_H)
	sun_arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun_arc.draw.connect(_draw_sun_arc)
	top_bar.add_child(sun_arc)

	# T-34: and the same hour in digits, immediately right of the arc.
	#
	# Not a contradiction of the arc but a second reading of one number, the way
	# the tint and the arc already are. The arc answers "roughly where in the day
	# am I" at a glance and stays the reading a pre-reader uses; the digits answer
	# "exactly how much is left", which is the question the debug readout kept
	# being asked for.
	#
	# T-36 (2026-08-31): 12-hour with AM/PM. T-34 read S-7's word ban as ruling
	# the markers out and shipped 24-hour; the designer overruled it — *"I'd
	# prefer time of day to be 12-hour clock with AM / PM"* — so the face runs
	# 6:00 AM → 4:00 PM and the suffix marks the noon wrap. Right of the arc
	# rather than under it because the bar is 30px tall and there is no under;
	# the type is the bar's own, so the row still reads as one row. Sized for
	# the longest face it wears ("11:59 AM").
	clock_label = Label.new()
	clock_label.name = "clock_label"
	clock_label.position = Vector2(sun_arc.position.x + ARC_W + 8.0, 5)
	clock_label.size = Vector2(76, 20)
	clock_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
	clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(clock_label)

	# The numeric readout survives for debugging only, because a developer still
	# wants the exact figure. Moved off centre at T-29 to leave the arc the middle
	# of the bar — it is the thing that ships, and the digits are not (S-7, and
	# Q-38's sub-ruling that the readout stays debug-only).
	if OS.is_debug_build():
		energy_label = Label.new()
		energy_label.name = "energy_debug_label"
		energy_label.position = Vector2(110, 5)
		energy_label.size = Vector2(130, 20)
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

	_build_state_chips(viewport_size)

	# --- The bed button (T-31 / Q-49) -----------------------------------------
	#
	# The HUD's first action control. Everything else here is status; this one
	# does something, which is the shape decision Q-49 held the item for and the
	# designer ruled: *"a tired player should not have to find the bed."* T-27's
	# fixes make the cot findable **once it is on screen**, and by evening it
	# usually is not.
	#
	# It is a *tap on the cot*, not a sleep (see `main.gd`'s `go_to_bed`): the
	# button knows nothing about where the cot is or what sleeping costs — it asks
	# main, main injects the tap, and the walk, the tuck-in and the Action all take
	# the ordinary route. So there is no new verb, no shortcut, and nothing new in
	# a replay but an ordinary cot tap.
	#
	# Wordless (S-7), and the picture is the cot's own sprite cell rather than a
	# glyph: the affordance is "that thing over there", so showing the thing is the
	# strongest label available, and it costs no art at all.
	#
	# Placed above the bottom bar on the **left**, deliberately away from the top
	# bar: Q-68 is still open on the top bar's geometry (the (d) camera answer and
	# the (c) float-or-shrink option both live up there), and a control the player
	# needs at dusk must not be sitting where that ruling might move things. The
	# bottom-right is spoken for by the build stamp overlay.
	bed_button = Button.new()
	bed_button.name = "BedButton"
	bed_button.size = Vector2(44, 48)
	bed_button.position = Vector2(10, viewport_size.y - 32 - 8 - 48)
	bed_button.tooltip_text = "Go to bed"  # never drawn; for a developer with a mouse
	var bed_style := StyleBoxFlat.new()
	bed_style.bg_color = Color(0.16, 0.20, 0.16, 0.9)
	bed_style.border_color = Color(0.62, 0.72, 0.58)
	bed_style.set_border_width_all(2)
	bed_style.set_corner_radius_all(8)
	bed_button.add_theme_stylebox_override("normal", bed_style)
	bed_button.add_theme_stylebox_override("hover", bed_style)
	bed_button.add_theme_stylebox_override("pressed", bed_style)
	bed_button.add_theme_stylebox_override("focus", bed_style)
	bed_button.pressed.connect(_on_bed_button)
	add_child(bed_button)

	# objects.png cell 0 is the cot, 16x32 — the same cell the world draws (see
	# `world/farm.gd`'s object_regions). Treatment C's turned-down cell is
	# deliberately *not* followed here: the button is a signpost to the bed, and a
	# signpost that changes picture at dusk is a second thing to learn.
	bed_button_icon = TextureRect.new()
	bed_button_icon.name = "bed_button_icon"
	bed_button_icon.position = Vector2(4, 3)
	bed_button_icon.size = Vector2(36, 42)
	bed_button_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bed_button_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bed_button_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cot_icon := AtlasTexture.new()
	cot_icon.atlas = load("res://assets/sprites/generated/objects.png")
	cot_icon.region = Rect2(0, 0, 16, 32)
	bed_button_icon.texture = cot_icon
	bed_button.add_child(bed_button_icon)

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
		# The designer, 2026-09-01: *"We should add a 'hide debug' button in the top
		# left that collapses the debug information printed in the top left."* The
		# readout is a scaffold that covers the top third of the screen, and on a
		# tablet that is exactly where the yard is.
		#
		# Debug-gated with the block it hides, so a release build has neither. The
		# collapsed state is a **static**, the look-lab's precedent: it survives a
		# return to the title and a new game the way a developer expects a debug
		# switch to, and it is deliberately not saved — S-7 does not bind a debug
		# surface, and neither does the save format.
		notes_toggle = Button.new()
		notes_toggle.name = "playtest_notes_toggle"
		notes_toggle.size = Vector2(NOTES_TOGGLE_W, NOTES_TOGGLE_H)
		notes_toggle.position = Vector2(10, 34)
		notes_toggle.focus_mode = Control.FOCUS_NONE
		notes_toggle.add_theme_font_size_override("font_size", 12)
		var nt_style := StyleBoxFlat.new()
		nt_style.bg_color = Color(0.10, 0.12, 0.10, 0.75)
		nt_style.border_color = Color(0.62, 0.72, 0.58, 0.8)
		nt_style.set_border_width_all(1)
		nt_style.set_corner_radius_all(4)
		for slot in ["normal", "hover", "pressed", "focus"]:
			notes_toggle.add_theme_stylebox_override(slot, nt_style)
		notes_toggle.add_theme_color_override("font_color", Color(0.92, 0.96, 0.88))
		notes_toggle.pressed.connect(_on_notes_toggle)
		add_child(notes_toggle)

		notes_label = Label.new()
		notes_label.name = "playtest_notes"
		notes_label.position = Vector2(10 + NOTES_TOGGLE_W + 4, 34)
		notes_label.size = Vector2(viewport_size.x - 24 - NOTES_TOGGLE_W, 76)
		notes_label.add_theme_font_size_override("font_size", 13)
		notes_label.add_theme_color_override("font_color", Color(1, 1, 0.86, 0.92))
		notes_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		notes_label.add_theme_constant_override("outline_size", 4)
		notes_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(notes_label)
		_apply_notes_collapsed()

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
	seed_pill.size = Vector2(PILL_MIN_W, PILL_H)
	seed_pill.position = Vector2(viewport_size.x / 2 - PILL_MIN_W / 2.0,
		viewport_size.y - 60 - PILL_H)
	seed_pill.gui_input.connect(_on_seed_pill_gui_input)
	add_child(seed_pill)

	seed_pill_icon = TextureRect.new()
	seed_pill_icon.name = "seed_pill_icon"
	seed_pill_icon.position = Vector2(4, 4)
	seed_pill_icon.size = Vector2(16, 16)
	seed_pill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seed_pill_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	seed_pill.add_child(seed_pill_icon)

	seed_pill_label = Label.new()
	seed_pill_label.position = Vector2(PILL_ICON_W, 2)
	seed_pill_label.size = Vector2(PILL_MIN_W - PILL_ICON_W - 4.0, 20)
	seed_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Belt and braces behind `_fit_seed_pill`: a name longer than the widest pill
	# we will draw gets trimmed rather than spilling out of the rounded rect.
	seed_pill_label.clip_text = true
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


# --- T-28, satisfied treatment B: the state, before the question --------------
#
# Two of the three "already done" answers in the gate session were about things
# she was *carrying* — a can that was already full (×2) and a basket that was
# already empty (×3) — and the only way to find either out was to walk to a
# station and tap it. The HUD did hold both numbers, as "Water: 8/8" and "Wh:0",
# which is (a) reading, in the one part of the game S-7 says must not require it,
# and (b) a number where a picture belongs.
#
# So under this treatment they become pictures: a basket with a pip for each crop
# in it, drawn dim and empty when there is nothing, and a can beside a tube of
# water filled to the level in it. Both replace their labels rather than sitting
# beside them — a picture that has to compete with the number it replaced is not
# a fair draft of the picture.
#
# The third answer, "already watered", is not a thing she carries, so it is on
# the tile instead (`world/farm.gd` draws the droplet). All three under one
# treatment, because the treatment is a claim about *when* the answer arrives.
const CHIP_W := 136.0
const GAUGE_W := 9.0
const GAUGE_H := 22.0
const BASKET_PIPS := 5     # [Playtest] past five, "lots" is the honest reading


func _build_state_chips(viewport_size: Vector2) -> void:
	state_chips = Control.new()
	state_chips.name = "state_chips"
	state_chips.position = Vector2(viewport_size.x - CHIP_W, 0)
	state_chips.size = Vector2(CHIP_W, 32)
	state_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_chips.visible = false
	bottom_bar.add_child(state_chips)

	basket_chip = TextureRect.new()
	basket_chip.name = "basket_chip"
	basket_chip.position = Vector2(0, 3)
	basket_chip.size = Vector2(26, 26)
	basket_chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	basket_chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	basket_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	basket_chip.texture = _glyph_icon(StationPresentation.GLYPH_BASKET)
	state_chips.add_child(basket_chip)

	# One pip per crop in the basket. A tally rather than a numeral: "how many
	# things have I got" is a question a pre-reader answers by counting, and the
	# shop already proved digits are legible where they are unavoidable — here
	# they are avoidable.
	basket_pips.clear()
	for i in BASKET_PIPS:
		var pip := ColorRect.new()
		pip.name = "basket_pip_%d" % i
		pip.position = Vector2(28 + i * 7, 13)
		pip.size = Vector2(5, 5)
		pip.color = Color(0.95, 0.80, 0.28)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.visible = false
		state_chips.add_child(pip)
		basket_pips.append(pip)

	can_chip = TextureRect.new()
	can_chip.name = "can_chip"
	can_chip.position = Vector2(70, 3)
	can_chip.size = Vector2(26, 26)
	can_chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	can_chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	can_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	can_chip.texture = _glyph_icon(StationPresentation.GLYPH_CAN)
	state_chips.add_child(can_chip)

	can_gauge_back = ColorRect.new()
	can_gauge_back.name = "can_gauge"
	can_gauge_back.position = Vector2(100, 5)
	can_gauge_back.size = Vector2(GAUGE_W, GAUGE_H)
	can_gauge_back.color = Color(0.06, 0.10, 0.14, 0.92)
	can_gauge_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_chips.add_child(can_gauge_back)

	can_gauge_fill = ColorRect.new()
	can_gauge_fill.name = "can_gauge_fill"
	can_gauge_fill.color = Color(0.36, 0.72, 0.95)
	can_gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	can_gauge_back.add_child(can_gauge_fill)


func _glyph_icon(key: String):
	var entry: Dictionary = StationPresentation.GLYPH_ATLAS.get(key, {})
	if entry.is_empty():
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tool_icons_texture if entry["sheet"] == "tools" \
		else load("res://assets/sprites/generated/crops.png")
	var r: Array = entry["rect"]
	atlas.region = Rect2(r[0], r[1], r[2], r[3])
	return atlas


func _update_state_chips() -> void:
	if state_chips == null:
		return
	var on: bool = StationPresentation.satisfied == StationPresentation.SATISFIED_CHIP
	state_chips.visible = on
	# The labels these replace. Under every other treatment the HUD is exactly
	# what it was, which is what keeps the A/B honest.
	if water_label != null:
		water_label.visible = not on
	if crop_counts_label != null:
		crop_counts_label.visible = not on
	if not on:
		return

	var basket := 0
	for count in GameState.crops.values():
		basket += int(count)
	# Empty is the state this treatment exists to show, so it is the loud one:
	# the basket goes grey and stays visibly unfilled. Q-46(a)'s vocabulary —
	# darkened means "not there" — reused rather than reinvented.
	basket_chip.modulate = Color(1, 1, 1, 1) if basket > 0 else Color(0.42, 0.44, 0.48, 0.9)
	for i in basket_pips.size():
		basket_pips[i].visible = i < basket

	var frac: float = float(GameState.watering_can_charges) \
		/ maxf(1.0, float(GameState.max_watering_can_charges))
	var h: float = round((GAUGE_H - 2.0) * clampf(frac, 0.0, 1.0))
	can_gauge_fill.position = Vector2(1.0, GAUGE_H - 1.0 - h)
	can_gauge_fill.size = Vector2(GAUGE_W - 2.0, h)
	can_chip.modulate = Color(1, 1, 1, 1) if frac > 0.0 else Color(0.42, 0.44, 0.48, 0.9)


func _process(delta: float) -> void:
	_update_hud()
	_update_toast(delta)
	# Collapsed means collapsed: the readout's obstacle count is an O(map) scan, and
	# a hidden label has no business paying for one.
	if notes_label != null and not notes_collapsed:
		_notes_timer -= delta
		if _notes_timer <= 0.0:
			_notes_timer = NOTES_REFRESH
			_update_playtest_notes()


# Measure, pad, then draw — and stay centred while doing it, because the pill's
# position is where it is *drawn from*, not where its middle is.
func _fit_seed_pill() -> void:
	if seed_pill == null or seed_pill_label == null:
		return
	var font: Font = seed_pill_label.get_theme_font("font")
	var font_size: int = seed_pill_label.get_theme_font_size("font_size")
	var text_w := 0.0
	if font != null:
		text_w = font.get_string_size(seed_pill_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var w := pill_width(text_w)
	if is_equal_approx(w, seed_pill.size.x):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	seed_pill.size = Vector2(w, PILL_H)
	seed_pill.position = Vector2(round(viewport_size.x / 2.0 - w / 2.0), seed_pill.position.y)
	seed_pill_label.size = Vector2(w - PILL_ICON_W - 4.0, 20)


func _on_notes_toggle() -> void:
	notes_collapsed = not notes_collapsed
	_apply_notes_collapsed()
	if not notes_collapsed:
		_notes_timer = 0.0  # refresh on the next frame rather than up to half a second later


func _apply_notes_collapsed() -> void:
	if notes_label != null:
		notes_label.visible = not notes_collapsed
	if notes_toggle != null:
		# "≡" offers the block back; "×" closes it. No words, on a surface that is
		# nothing but words — the button has to be readable at 22 pixels wide.
		notes_toggle.text = "☰" if notes_collapsed else "×"
		notes_toggle.tooltip_text = "show the playtest readout" if notes_collapsed \
			else "hide the playtest readout"


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
	"yard": "the yard",           # T-32: home ground, and never tillable
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
	
	# Reported from play 2026-08-30: "Sunny" at night is confusing — and it was,
	# because the label was answering a question nobody asked. Dropping the word
	# left a ☀️/🌇/🌙 icon behind, and **Q-72 (ruled 2026-09-01) retires that
	# too**: the arc says what time it is precisely and T-34's digits say it
	# exactly, so a third, coarser telling of the same hour was only spending
	# pixels. The line now speaks *only when weather is happening* — silent on a
	# clear day, "🌧️ Rainy" when it is not, which is the thing worth naming and
	# the one the player can act on.
	if GameState.weather == "sunny":
		weather_label.text = ""
	else:
		weather_label.text = "🌧️ %s" % GameState.weather.capitalize()

	# The hour, drawn (T-29). Redrawn here rather than on a signal because the rest
	# of the bar is: one pass, one place to look when the bar is wrong.
	if sun_arc != null:
		sun_arc.queue_redraw()

	# The same hour in digits (T-34), from the same function the arc and the sky
	# are drawn from — so the three of them cannot disagree about the time.
	if clock_label != null:
		clock_label.text = Daylight.clock_text(GameState.energy, GameState.max_energy)

	# Energy — debug readout only (T-14/Q-38's sub-ruling). Release builds get the
	# sun-arc above and the sky behind it; neither carries a digit.
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

	# Active Seed Pill update. The icon is the crop's own shop sprite rather than
	# an emoji looked up by name: the emoji table knew wheat and tomato and fell
	# through to "?" for the scarecrow, so selecting it showed no icon at all
	# (reported from play 2026-08-30). Reading the sprite from CropDefs means a
	# crop added later cannot silently lose its picture.
	var seed_name: String = GameState.selected_seed_type
	var scount: int = GameState.seeds.get(seed_name, 0)
	var seed_def: Dictionary = CropDefs.TYPES.get(seed_name, {})
	if seed_def.has("sprite_row"):
		seed_pill_icon.texture = _crop_icon(int(seed_def.sprite_row))
		seed_pill_icon.visible = true
	else:
		seed_pill_icon.visible = false
	seed_pill_label.text = "%s x%d" % [seed_name, scount]
	_fit_seed_pill()

	var style: StyleBoxFlat = seed_pill.get_theme_stylebox("panel")
	if scount > 0:
		style.bg_color = Color(0.18, 0.52, 0.22, 0.88)
	else:
		style.bg_color = Color(0.25, 0.25, 0.25, 0.75)

	# Water
	water_label.text = "Water: %d/%d" % [GameState.watering_can_charges, GameState.max_watering_can_charges]

	# T-28's satisfied treatment B, if it is the one being judged.
	_update_state_chips()


# --- The sun-arc (T-29) -------------------------------------------------------
#
# Wordless by construction: an arc, three ticks, and one token. Nothing here is
# text and nothing here is a digit (S-7). The whole drawing is a pure function of
# `Daylight.progress`, so it cannot show an hour the tint disagrees with, and it
# is redrawn on the same `_update_hud` pass everything else in the bar is.

# Where the token sits for a given progress (0.0 sunrise → 1.0 dusk). The path is
# the upper half of the ellipse walked left to right, so sunrise is due west and
# dusk due east with midday overhead — which is the shape a day has.
func _arc_point(p: float) -> Vector2:
	var a: float = PI + clampf(p, 0.0, 1.0) * PI
	return ARC_CENTRE + Vector2(cos(a) * ARC_RX, sin(a) * ARC_RY)


# The token's place on the arc, in the arc's own pixels. Public because a drawing
# can only be asserted on through the numbers it is drawn from, and the
# integration suite does exactly that (Scenario H).
func sun_token_pos() -> Vector2:
	return _arc_point(Daylight.progress(GameState.energy, GameState.max_energy))


# Past dusk the token is a moon rather than a sun — the same threshold the sky
# glyph changes on, which is also the arc's third tick.
func sun_token_is_moon() -> bool:
	return Daylight.is_night(GameState.energy, GameState.max_energy)


# The path between two progress points, sampled. `draw_arc` would do this in one
# call but only for a circle, and the bar is not tall enough for one.
func _arc_path(from_p: float, to_p: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps: int = maxi(2, int(round(ARC_STEPS * (to_p - from_p))))
	for i in steps + 1:
		pts.append(_arc_point(from_p + (to_p - from_p) * float(i) / float(steps)))
	return pts


func _draw_sun_arc() -> void:
	var p: float = Daylight.progress(GameState.energy, GameState.max_energy)

	# The horizon, so the arc reads as a sky rather than as a gauge.
	sun_arc.draw_line(Vector2(2, ARC_CENTRE.y), Vector2(ARC_W - 2, ARC_CENTRE.y),
		Color(1, 1, 1, 0.16), 1.0)
	# The day's whole path, dim...
	sun_arc.draw_polyline(_arc_path(0.0, 1.0), Color(1, 1, 1, 0.20), 1.0, true)
	# ...and the part of it already walked, lit. This is the only "how much is
	# left" cue, and it is a length rather than a number.
	if p > 0.01:
		sun_arc.draw_polyline(_arc_path(0.0, p), Color(1.0, 0.93, 0.74, 0.55), 2.0, true)

	# The three hours the sky itself turns (Daylight.TICKS), as notches across the
	# path. They are what turns "somewhere along here" into a precise read.
	for tick in Daylight.TICKS:
		var tp: float = 1.0 - float(tick["f"])
		var at_tick := _arc_point(tp)
		var out := (at_tick - ARC_CENTRE).normalized()
		sun_arc.draw_line(at_tick - out * ARC_TICK, at_tick + out * ARC_TICK,
			Color(1, 1, 1, 0.38), 1.0)

	var at := _arc_point(p)
	if sun_token_is_moon():
		# A crescent, cut by a disc in the bar's own colour, so the bite reads as
		# night sky rather than as a hole punched in the HUD. The cut is sized to
		# sit *inside* the disc (offset + radius = the moon's own radius): a bite
		# that overhung the edge would paint bar-colour onto the bar and show up
		# as a dark ring around the moon.
		sun_arc.draw_circle(at, ARC_TOKEN_R, Color(0.87, 0.90, 1.0))
		sun_arc.draw_circle(at + Vector2(1.3, -0.95), ARC_TOKEN_R * 0.6, MOON_CUT)
	else:
		# The sun reddens as it falls, which is the same story the tint tells.
		var warm: Color = Color(1.0, 0.94, 0.62).lerp(Color(1.0, 0.66, 0.30), p)
		for i in 8:
			var a2: float = i * PI / 4.0
			var d2 := Vector2(cos(a2), sin(a2))
			sun_arc.draw_line(at + d2 * (ARC_TOKEN_R + 1.5), at + d2 * (ARC_TOKEN_R + 3.5),
				Color(warm.r, warm.g, warm.b, 0.55), 1.0)
		sun_arc.draw_circle(at, ARC_TOKEN_R, warm)


# crops.png row 2: one shop icon per crop, indexed by its sprite_row.
func _crop_icon(sprite_row: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/sprites/generated/crops.png")
	atlas.region = Rect2(sprite_row * 16, 32, 16, 16)
	return atlas


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


func _on_bed_button() -> void:
	# Routed through main for the same reason the menu button is: the HUD does not
	# know where the cot is, and should not learn. Main turns this into a tap on
	# the cot's tile (T-31). The click is *not* consumed here — during a day
	# transition `InputManager` drops it and this is silently nothing, which is
	# T-27 box 2 covering the button for free.
	var main := get_tree().get_first_node_in_group("Main")
	if main and main.has_method("trigger_action"):
		AudioManager.play_sfx("click")
		main.trigger_action("go_to_bed")


func _on_menu_button() -> void:
	# Routed through main so the HUD does not need to know about the menu layer.
	var main := get_tree().get_first_node_in_group("Main")
	if main and main.has_method("trigger_action"):
		AudioManager.play_sfx("click")
		main.trigger_action("open_pause")

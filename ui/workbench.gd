# workbench.gd — the bench she puts a learning robot on, and the five plates
#
# **What the bench is** (`design/14`, ruled whole as Q-101 on 2026-09-10). A
# Mark III is the first machine in the game that decides for itself, and until now
# the only thing the player could see of that was a scorecard on its panel. The
# bench is where she reads the machine properly and where she turns the one dial
# it has: what each thing it does is worth to her. Five plates across the top, one
# page each — the dials, its eyes, its plate, its ledger, its mosaic.
#
# **This file is the shell and nothing else.** It draws the chrome, holds the five
# pages, decides which robot is on the bench, and owns the two pictures every page
# needs (`draw_action_glyph` here, `BotScorecard.draw_pip` there). Every page is
# its own file with one method, `show_robot(farm, actor_id)`, so the five of them
# were built side by side without touching each other or this.
#
# **It is a menu, so the world holds while it is open** (ground rule 7). That is
# not a compromise, it is the design: the eyes page shows what the robot saw at
# the moment she opened the bench, not a feed she has to keep up with.
#
# **It never writes the robot.** Everything on screen is read out of `extra`
# through `farm.sim`; the one thing the bench changes is a reward value, and that
# goes through the gateway as a `tune` Action like every other change in the game
# (S-3). `tools/check_gateway.py` does not scan `ui/`, so this rule is held here
# by review and by the tests rather than by CI.
#
# Geometry is the mockups' (`docs/design/mockups/workbench/`), absolute against
# the game's fixed 800x600 screen: each page is a full-rect Control, so a page can
# use those numbers as they are written rather than offsetting everything by the
# body's corner.
class_name Workbench
extends Control

## Emitted when the close card is pressed. `ui/menus.gd` hears it and closes the
## menu, which is what unpauses the world — the bench does not touch the tree.
signal closed

# --- geometry (docs/design/mockups/workbench/workbench_mock.html) --------------
const SCREEN := Vector2(800, 600)
const CARD_RECT := Rect2(12, 12, 776, 576)     # the whole bench, on the dim
const STRIP_RECT := Rect2(14, 14, 772, 62)     # the robots, the name, the close
const WOOD_RECT := Rect2(14, 76, 772, 76)      # the bench top the plates sit on
const BODY_RECT := Rect2(14, 152, 772, 434)    # everything a page may draw in

const PLATES := 5
const PLATE_SIZE := Vector2(148, 60)
const PLATE_Y := 84.0
const PLATE_X0 := 20.0
const PLATE_STRIDE := 152.0

# **Every target a thumb has to find is 56 across.** The HUD's rule (S-6/S-7 — a
# four-year-old's hand on a tablet), and the number the dials page uses for its
# plus and minus buttons too.
const TOUCH := 56.0
const PORTRAITS_SHOWN := 6

# --- the colours the pages share ----------------------------------------------
#
# One language across the five pages, so a page cannot invent its own dark blue.
# Reward rows are `BotScorecard.LINE_COLOURS` (the machine panel's chart already
# speaks it); observation channels are `CHANNEL_COLOURS` below.
const CARD := Color("1f1f2e")
const STRIP := Color("191926")
const WOOD := Color("6b4d3a")
const BODY := Color("22222e")
const BRASS_LIT := Color("c9a94e")
const BRASS_LIT_BACK := Color("8a6f2c")
const BRASS := Color("6d6440")
const BRASS_BACK := Color("4a442c")
const INK := Color("d8dae6")
const INK_DIM := Color(0.62, 0.64, 0.74, 0.55)
const EDGE := Color(0.62, 0.64, 0.74, 0.20)

# **Each channel borrows the colour of the reward row it feeds**, so a player who
# has learned "blue is watering a thirsty plant" on the ledger reads the same blue
# on the eyes and on the mosaic. Walkable is the one with no row behind it and
# takes a grey, which is also what it is: the ground itself.
const CHANNEL_COLOURS := {
	"needs_water": Color("63c8f0"),
	"wet":         Color("c88ae0"),
	"walkable":    Color("8a8fa8"),
	"crop":        Color("86d96a"),
	"bare":        Color("c39a6c"),
	"ripe":        Color("f2a05a"),
	"crow":        Color("ee7b7b"),
	"bin":         Color("f2e06a"),
}

# Warm and cool, for a weight the mosaic has to show the sign of.
const WEIGHT_COOL := Color("4a6fa5")
const WEIGHT_NEUTRAL := Color("2a2a3a")
const WEIGHT_WARM := Color("d08a3c")

const NAME_SIZE := 18
const DAY_SIZE := 16

# --- the pictures the eight actions are drawn with -----------------------------
#
# Six of them are pictures the game already speaks in (the same cells the machine
# panel's scorecard borrows), because a bench that invented its own hoe would be a
# second hoe for the player to learn. The two that have no picture anywhere —
# wandering and waiting — are drawn from lines below.
const SHEET_TOOLS := preload("res://assets/sprites/tool_icons.png")
const SHEET_ICONS := preload("res://assets/sprites/generated/shop_icons.png")
const SHEET_CROW := preload("res://assets/sprites/generated/crow.png")
const SHEET_WHEAT := preload("res://assets/sprites/generated/wheat.png")
const SHEET_BIN := preload("res://assets/sprites/generated/shipping_bin.png")

const ACTION_CELLS := {
	BotBrain.LEARN_TILL:    { "sheet": "tools", "cell": 3 },   # the hoe
	BotBrain.LEARN_PLANT:   { "sheet": "tools", "cell": 5 },   # the seed packet
	BotBrain.LEARN_WATER:   { "sheet": "tools", "cell": 4 },   # the can
	# The ripe head rather than the basket: the basket is the *scorecard's* word
	# for "harvested", and one picture meaning two things on one screen is worse
	# than two pictures meaning one thing each.
	BotBrain.LEARN_HARVEST: { "sheet": "wheat", "cell": 3 },
	BotBrain.LEARN_SHIP:    { "sheet": "bin",   "cell": 0 },   # the shipping bin
	# Wings up: the bird still in the air is what shooing is for. It gets a chip
	# behind it for the scorecard's reason — the crow is four shades off this
	# body colour and vanishes into it without one.
	BotBrain.LEARN_SHOO:    { "sheet": "crow",  "cell": 1, "chip": true },
}

# --- state --------------------------------------------------------------------

## The farm the bench is reading. Presentation's facade over the sim; never
## written from here.
var farm: Node2D = null

## The square the bench itself stands on — what "the nearest robot" is nearest to.
var bench_tile: Vector2i = Vector2i(-1, -1)

## Every learner in the world, in `SimWorld.learners()` order. The strip shows the
## first `PORTRAITS_SHOWN` of them; `select_robot` indexes into all of them.
var robots: Array = []

## The one on the bench, or "" when the player owns no learning robot yet.
var robot_id: String = ""

## Which plate is lit: 0 dials, 1 eyes, 2 plate, 3 ledger, 4 mosaic.
var plate: int = 0

## The five page Controls, in plate order.
var pages: Array = []

## A channel index the mosaic has asked the eyes to outline next time they draw,
## or -1 for none. It lives here because it is a conversation *between* two pages
## and neither of them owns the other.
var highlight_channel: int = -1

## The portrait cards in the strip, in `robots` order (up to `PORTRAITS_SHOWN`).
var portraits: Array = []

var _plate_buttons: Array = []
var _close_button: Button = null


func _init() -> void:
	name = "Workbench"
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_pages()
	_build_plates()
	_build_close()


# --- the pages ----------------------------------------------------------------
#
# Five full-rect Controls, one file each. They are added *first* so the chrome's
# controls sit above them, and each one is told to ignore the mouse: a page that
# wants a button adds one of its own, and a page that is only a readout must not
# swallow a tap meant for a plate.
func _build_pages() -> void:
	for script_path in [
		"res://ui/workbench_dials.gd",
		"res://ui/workbench_eyes.gd",
		"res://ui/workbench_plate.gd",
		"res://ui/workbench_ledger.gd",
		"res://ui/workbench_mosaic.gd",
	]:
		var page := Control.new()
		page.set_script(load(script_path))
		# Full-rect anchors size it to the screen on their own; setting `size` here
		# as well is overridden a frame later and only earns a warning.
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		page.visible = false
		add_child(page)
		pages.append(page)
	if not pages.is_empty():
		(pages[0] as Control).visible = true


# --- the five plates ----------------------------------------------------------
#
# The faces and the glyphs are drawn by this node's own `_draw`, one place for the
# whole strip of them; these are the touch targets on top, transparent so the
# brass shows through. That is what keeps a plate's *look* and a plate's *hit box*
# from being two descriptions that can disagree.
func _build_plates() -> void:
	var blank := StyleBoxEmpty.new()
	for i in PLATES:
		var b := Button.new()
		b.name = "Plate%d" % i
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.position = plate_rect(i).position
		b.size = PLATE_SIZE
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, blank)
		b.pressed.connect(select_plate.bind(i))
		add_child(b)
		_plate_buttons.append(b)


# The close card, in the HUD's corner-card style (`ui/hud.gd`'s bed and menu
# buttons) — the same dark green card with a pale border everywhere else in the
# game puts a control the player is meant to press.
func _build_close() -> void:
	_close_button = Button.new()
	_close_button.name = "WorkbenchClose"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.size = Vector2(TOUCH, TOUCH)
	_close_button.position = Vector2(CARD_RECT.end.x - 6.0 - TOUCH, STRIP_RECT.position.y + 3.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.20, 0.16, 0.9)
	style.border_color = Color(0.62, 0.72, 0.58)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	for state in ["normal", "hover", "pressed", "focus"]:
		_close_button.add_theme_stylebox_override(state, style)
	_close_button.pressed.connect(func(): closed.emit())
	add_child(_close_button)

	# The cross, drawn rather than typed. Two lines cannot be a codepoint the
	# bundled font is missing, which is the trap the shop's close button fell
	# into twice (`ui/menus.gd`, the U+2715 note).
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

## Point the bench at a farm and put a robot on it.
##
## `preferred_id` is the robot she last tapped (`ui/menus.gd` passes its
## `machine_id`); it wins when it is a learner, because the bench she opened from
## a machine should be about that machine. Otherwise the nearest learner to the
## bench takes the spot, ties settled by strip order — and with no learner at all
## the strip is empty and every page draws its own empty state.
func show_bench(farm_node: Node2D, at: Vector2i, preferred_id: String) -> void:
	farm = farm_node
	bench_tile = at
	highlight_channel = -1
	_read_robots(preferred_id)
	_build_portraits()
	# A fresh open starts on the dials, which is the page the bench is *for*: the
	# other four are what the dials are turned against.
	select_plate(0)
	refresh()


## Re-read the sim and hand every page the robot again. The one way anything on
## the bench changes: a dial turn goes through the gateway and then calls this, so
## what is on screen is always a read of sim truth rather than a local edit.
func refresh() -> void:
	if farm != null and robot_id != "" and not farm.sim.has_actor(robot_id):
		# It was picked up out from under the bench.
		_read_robots("")
		_build_portraits()
	for page in pages:
		if page.has_method("show_robot"):
			page.show_robot(farm, robot_id)
	_style_portraits()
	queue_redraw()


## Light one plate and show its page. Out-of-range is clamped rather than refused:
## a plate index is never user input, it is one of five buttons.
func select_plate(index: int) -> void:
	plate = clampi(index, 0, PLATES - 1)
	for i in pages.size():
		(pages[i] as Control).visible = i == plate
	queue_redraw()


## Put another robot on the bench. `index` is into `robots`, which is the strip's
## own order.
func select_robot(index: int) -> void:
	if index < 0 or index >= robots.size():
		return
	robot_id = String(robots[index])
	refresh()


## The robot's `extra`, or an empty dictionary when there is no robot on the
## bench. The one place the pages and the header agree how to reach it.
func robot_extra() -> Dictionary:
	if farm == null or robot_id == "" or not farm.sim.has_actor(robot_id):
		return {}
	return farm.sim.actor(robot_id).get("extra", {})


func _read_robots(preferred_id: String) -> void:
	robots = []
	robot_id = ""
	if farm == null or farm.get("sim") == null:
		return
	robots = farm.sim.learners()
	if robots.is_empty():
		return
	if preferred_id != "" and preferred_id in robots:
		robot_id = preferred_id
		return
	var best_d := 1 << 30
	for raw in robots:
		var id := String(raw)
		var p: Vector2i = farm.sim.actor_pos(id)
		var d: int = absi(p.x - bench_tile.x) + absi(p.y - bench_tile.y)
		if d < best_d:
			best_d = d
			robot_id = id


# --- the portrait strip -------------------------------------------------------

func _build_portraits() -> void:
	for card in portraits:
		remove_child(card)
		card.queue_free()
	portraits = []
	var shown: int = mini(robots.size(), PORTRAITS_SHOWN)
	for i in shown:
		var id := String(robots[i])
		var card := Button.new()
		card.name = "Portrait%d" % i
		card.focus_mode = Control.FOCUS_NONE
		card.size = Vector2(TOUCH, TOUCH)
		card.position = Vector2(PLATE_X0 + i * (TOUCH + 6.0), STRIP_RECT.position.y + 3.0)
		card.pressed.connect(select_robot.bind(i))
		add_child(card)

		var face := TextureRect.new()
		face.name = "Face"
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.offset_left = 4
		face.offset_top = 4
		face.offset_right = -4
		face.offset_bottom = -4
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		face.texture = MachineDefs.icon_of(_model_of(id))
		card.add_child(face)

		portraits.append(card)
	_style_portraits()


# Which robot the bench is on, said in the strip: a lit card behind the one that
# is, a dark one behind the rest. The same brass the lit plate uses, so "this is
# the one you are looking at" is one colour on the whole screen.
func _style_portraits() -> void:
	for i in portraits.size():
		var card: Button = portraits[i]
		var mine: bool = i < robots.size() and String(robots[i]) == robot_id
		var style := StyleBoxFlat.new()
		style.bg_color = BRASS_LIT_BACK if mine else Color(0.13, 0.13, 0.19, 1.0)
		style.border_color = BRASS_LIT if mine else EDGE
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		for state in ["normal", "hover", "pressed", "focus"]:
			card.add_theme_stylebox_override(state, style)


func _model_of(id: String) -> String:
	if farm == null or not farm.sim.has_actor(id):
		return ""
	var extra: Dictionary = farm.sim.actor(id).get("extra", {})
	var model := String(extra.get("model", ""))
	if model != "":
		return model
	return String(farm.sim.machine_key_of(id))


# --- the chrome ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(CARD_RECT, CARD)
	draw_rect(STRIP_RECT, STRIP)
	draw_rect(WOOD_RECT, WOOD)
	draw_rect(BODY_RECT, BODY)

	for i in PLATES:
		var r := plate_rect(i)
		var lit: bool = i == plate
		draw_rect(r, BRASS_LIT_BACK if lit else BRASS_BACK)
		draw_rect(r, BRASS_LIT if lit else BRASS, false, 2.0)
		_draw_plate_glyph(self, i, r, BRASS_LIT if lit else BRASS)
		if lit:
			# **The lit plate's underline**, which is what says the page below
			# belongs to it: brass running the width of the plate along the edge
			# it meets the body at.
			draw_rect(Rect2(r.position.x + 8.0, r.end.y - 6.0, r.size.x - 16.0, 4.0),
				BRASS_LIT)

	_draw_header()


# The robot's name and how many nights it has had, which is the one place on the
# bench that carries words (`design/14`: numerals everywhere else).
func _draw_header() -> void:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return
	var extra := robot_extra()
	var label_x := PLATE_X0 + PORTRAITS_SHOWN * (TOUCH + 6.0) + 8.0
	var mid_y := STRIP_RECT.position.y + STRIP_RECT.size.y / 2.0

	if robot_id == "":
		# No learning robot on the farm at all. A dash rather than a sentence
		# explaining the absence — the empty strip beside it has already said it.
		draw_rect(Rect2(label_x, mid_y - 2.0, 26.0, 4.0), INK_DIM)
		return

	var title := MachineDefs.name_of(_model_of(robot_id))
	draw_string(f, Vector2(label_x, mid_y + NAME_SIZE * 0.36), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, INK)

	# The nights it has had, beside a drawn clock — the numeral needs a unit and
	# "days" is a word.
	var clock_size := 22.0
	var clock_at := Vector2(_close_button.position.x - 12.0 - clock_size - 34.0,
		mid_y - clock_size / 2.0)
	draw_clock(self, clock_at, clock_size, INK)
	draw_string(f, Vector2(clock_at.x + clock_size + 6.0, mid_y + DAY_SIZE * 0.36),
		str(int(extra.get("days", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, DAY_SIZE, INK)


## Where plate `i` sits, so a page that wants to point at one does not re-derive
## the arithmetic.
static func plate_rect(i: int) -> Rect2:
	return Rect2(PLATE_X0 + PLATE_STRIDE * i, PLATE_Y, PLATE_SIZE.x, PLATE_SIZE.y)


# The five plate faces, drawn from lines: sliders, an eye, three lines, a rising
# line, a grid. No new art — the plates say what their page is about with the
# simplest shape that could mean it.
static func _draw_plate_glyph(canvas: CanvasItem, index: int, r: Rect2, ink: Color) -> void:
	var c := r.position + r.size / 2.0
	match index:
		0:
			# Dials: three tracks with a knob on each, at different settings.
			var knobs := [0.30, 0.62, 0.45]
			for k in 3:
				var y := c.y - 14.0 + k * 14.0
				canvas.draw_rect(Rect2(c.x - 34.0, y - 1.0, 68.0, 2.0), Color(ink, 0.55))
				canvas.draw_rect(
					Rect2(c.x - 34.0 + 68.0 * float(knobs[k]) - 3.0, y - 6.0, 6.0, 12.0), ink)
		1:
			# The eye: two arcs meeting at the corners, and a pupil.
			_draw_lens(canvas, c, 34.0, 15.0, ink)
			canvas.draw_circle(c, 6.0, ink)
		2:
			# The plate: three lines of writing on brass, longest first.
			var widths := [56.0, 44.0, 50.0]
			for k in 3:
				canvas.draw_rect(
					Rect2(c.x - 30.0, c.y - 13.0 + k * 12.0, float(widths[k]), 4.0), ink)
		3:
			# The ledger: an axis corner with a line climbing out of it.
			canvas.draw_rect(Rect2(c.x - 32.0, c.y - 16.0, 2.0, 32.0), Color(ink, 0.55))
			canvas.draw_rect(Rect2(c.x - 32.0, c.y + 14.0, 64.0, 2.0), Color(ink, 0.55))
			canvas.draw_polyline(PackedVector2Array([
				Vector2(c.x - 26.0, c.y + 8.0), Vector2(c.x - 10.0, c.y - 2.0),
				Vector2(c.x + 6.0, c.y + 2.0), Vector2(c.x + 26.0, c.y - 14.0),
			]), ink, 2.5)
		4:
			# The mosaic: nine cells, one of them lit.
			for gy in 3:
				for gx in 3:
					var cell := Rect2(c.x - 21.0 + gx * 14.0, c.y - 21.0 + gy * 14.0, 11.0, 11.0)
					canvas.draw_rect(cell, ink if (gx == 2 and gy == 0) else Color(ink, 0.45))


# --- the pictures every page shares -------------------------------------------

## One of the eight things a learning robot can decide to do, as a picture.
##
## `action` is a `BotBrain.LEARN_*` index; `at` is the top-left of a box `size`
## across. Six of the eight are cells the game already draws elsewhere and two —
## wandering and waiting — are lines, because the game has never had to say either
## of them before.
##
## It lives on the shell rather than on a page because four of the five pages need
## it, and eight pictures defined twice is eight chances for two pages of one
## screen to disagree about what watering looks like.
static func draw_action_glyph(canvas: CanvasItem, action: int, at: Vector2, size: float) -> void:
	if action == BotBrain.LEARN_WANDER:
		_draw_wander(canvas, at, size, INK)
		return
	if action == BotBrain.LEARN_WAIT:
		draw_clock(canvas, at, size, INK)
		return
	var entry: Dictionary = ACTION_CELLS.get(action, {})
	if entry.is_empty():
		return
	if bool(entry.get("chip", false)):
		# The bird sits on a chip of its own row's colour, for the scorecard's
		# reason: (47, 43, 61) against a (34, 34, 46) body is not a picture.
		canvas.draw_rect(
			Rect2(at + Vector2(size * 0.06, size * 0.11),
				Vector2(size * 0.88, size * 0.78)),
			Color(BotScorecard.LINE_COLOURS["crow_flying"], 0.9))
	canvas.draw_texture_rect_region(_action_sheet(String(entry.get("sheet", "tools"))),
		Rect2(at, Vector2(size, size)),
		Rect2(int(entry.get("cell", 0)) * 16, 0, 16, 16))


static func _action_sheet(sheet_name: String) -> Texture2D:
	match sheet_name:
		"icons":
			return SHEET_ICONS
		"crow":
			return SHEET_CROW
		"wheat":
			return SHEET_WHEAT
		"bin":
			return SHEET_BIN
		_:
			return SHEET_TOOLS


# Wandering: four arrows out of one point, which is the honest picture of a
# machine that has decided to go somewhere without deciding where.
static func _draw_wander(canvas: CanvasItem, at: Vector2, size: float, ink: Color) -> void:
	var c := at + Vector2(size, size) / 2.0
	var arm := size * 0.40
	var head := size * 0.13
	for raw in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var dir: Vector2 = raw
		var tip: Vector2 = c + dir * arm
		canvas.draw_line(c, tip, ink, maxf(1.5, size * 0.07))
		var side := Vector2(-dir.y, dir.x)
		canvas.draw_colored_polygon(PackedVector2Array([
			tip, tip - dir * head + side * head * 0.8, tip - dir * head - side * head * 0.8,
		]), ink)


## A clock face: a ring and two hands. Waiting, in the thinking strip — and the
## same picture beside the day numeral in the header, because "how many days" and
## "it decided to wait" are the same idea in this game.
static func draw_clock(canvas: CanvasItem, at: Vector2, size: float, ink: Color) -> void:
	var c := at + Vector2(size, size) / 2.0
	var r := size * 0.42
	canvas.draw_arc(c, r, 0.0, TAU, 24, ink, maxf(1.5, size * 0.07))
	canvas.draw_line(c, c + Vector2(0, -r * 0.68), ink, maxf(1.5, size * 0.07))
	canvas.draw_line(c, c + Vector2(r * 0.50, 0), ink, maxf(1.5, size * 0.07))


# An almond, from two parabolic arcs. Used by the eye plate; kept here so the eyes
# page can draw the same shape at its own size if it wants one.
static func _draw_lens(canvas: CanvasItem, c: Vector2, half_w: float, half_h: float,
		ink: Color) -> void:
	for sign in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 17:
			var t := -1.0 + 2.0 * float(i) / 16.0
			pts.append(Vector2(c.x + t * half_w, c.y + sign * half_h * (1.0 - t * t)))
		canvas.draw_polyline(pts, ink, 2.5)


## The dash a page draws when there is no robot on the bench — one picture of
## "nothing to show", in the middle of the body, the same on all five pages.
static func draw_empty_dash(canvas: CanvasItem) -> void:
	var c := BODY_RECT.position + BODY_RECT.size / 2.0
	canvas.draw_rect(Rect2(c.x - 18.0, c.y - 3.0, 36.0, 6.0), INK_DIM)

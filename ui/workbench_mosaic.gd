# workbench_mosaic.gd — plate 5 of 5: the weights themselves, folded into a picture
#
# **What this page is** (`design/14` §6, ruled whole as Q-101). A Mark III's mind
# is 1,664 numbers, which is not a thing anyone can look at. This page folds them
# down to a grid a person can read: eight columns, one per thing the robot can
# decide to do, and thirteen rows, one per group of the things it looks at. Each
# cell is the sum of every weight joining that group to that action — **warm for
# "this makes it want to", cool for "this puts it off"**.
#
# A week-old waterer shows a warm cell where watering meets thirsty ground and a
# cool one where watering meets ground that is already wet. A scientist calls that
# feature attribution; a child sees a robot that likes thirsty plants. Both are
# looking at the same eight by thirteen squares, which is the whole argument for
# drawing the brain this way rather than printing it.
#
# **The fold is the sim's, not this page's.** `Observation.input_groups(spec)`
# says which inputs belong to which row and `Policy.fold` does the summing, so a
# spec that grows a channel grows a row here without this file being touched — and
# the row order on screen can never drift from the order the vector is actually
# laid out in.
#
# **Tap a cell** and the two cards on the right hold it: what the weight is, which
# row and which column it joins. The one before it drops to the second card, so
# comparing two cells is two taps rather than a memory test. Tap a channel row and
# the eyes page outlines those marks in the patch next time she looks at it —
# that hand-off is `Workbench.highlight_channel`, because it is a conversation
# between two pages and neither owns the other.
#
# **Read-only** (P-13). Looking at the brain is this release; painting a cell —
# telling the robot what to care about with a finger — is the later rung the
# design holds back.
#
# Geometry is the mockup's (`docs/design/mockups/workbench/workbench_mosaic.png`),
# absolute against the fixed 800x600 screen.
extends Control

# --- geometry (F-44 for the cards and the legend; the grid from the mockup) ----
const GRID_X := 100.0
const GRID_Y := 206.0
const CELL := Vector2(52, 26)
const COL_STRIDE := 54.0
const ROW_STRIDE := 28.0

const RAIL_X := 58.0          # the dim tick that makes a row a row
const RAIL_W := 4.0
const SWATCH_X := 66.0
const SWATCH := 16.0

const HEADER_Y := 172.0       # the action pictures over the columns
const HEADER_SIZE := 24.0

const CARD_NOW := Rect2(558, 206, 200, 128)
const CARD_BEFORE := Rect2(558, 346, 200, 92)
const LEGEND := Rect2(558, 532, 200, 20)

const VALUE_SIZE := 20
const SMALL_SIZE := 14
const LEGEND_SIZE := 11


## The farm to read through, and the robot to read. `""` means the player owns no
## learning robot, and the page draws its empty state.
var farm: Node2D = null
var actor_id: String = ""

## The thirteen row definitions, straight from `Observation.input_groups(spec)`:
## the eight channels in spec order, then position, energy, carrying, seeds, bin.
var groups: Array = []

## The grid, `Policy.fold`'s own shape: `cells[action][group]`, eight rows of
## thirteen. Built in `show_robot` so it can be read whether or not this is the
## page that happens to be showing.
var cells: Array = []

## The cell she is holding, as (column, row) — (action, group) — or (-1, -1) for
## none. A `Vector2i` in that order because the cards read left to right: which
## column, then which row.
var selected: Vector2i = Vector2i(-1, -1)

## The one before it, which is what the second card shows.
var previous: Vector2i = Vector2i(-1, -1)

# The largest weight on the grid in either direction. Every cell is coloured
# against it, so the picture is about *this* robot's proportions rather than
# against some absolute scale a fresh robot would have none of.
var _peak: float = 0.0

# How many of the rows are observation channels: the ones that mean something to
# the eyes page, and so the only ones a row tap can highlight.
var _channels: int = 0

# The tap surface. Pages are `MOUSE_FILTER_IGNORE` so a readout cannot swallow a
# tap meant for a plate, which means a page that wants to be touched brings its
# own control — this one, laid over the grid and the row swatches.
var _taps: Control = null


func _ready() -> void:
	_ensure_taps()


func show_robot(farm_node: Node2D, id: String) -> void:
	var same_robot: bool = id == actor_id
	farm = farm_node
	actor_id = id
	_fold()
	if not same_robot:
		# A different robot is a different brain; holding a cell from the last
		# one would be pointing at a number that no longer exists.
		selected = Vector2i(-1, -1)
		previous = Vector2i(-1, -1)
	_ensure_taps()
	queue_redraw()


## The value in a cell, or 0.0 when there is no such cell. `action` is a column
## (`BotBrain.LEARN_*`), `group` a row.
func cell_value(action: int, group: int) -> float:
	if action < 0 or action >= cells.size():
		return 0.0
	var row: Array = cells[action]
	if group < 0 or group >= row.size():
		return 0.0
	return float(row[group])


## What a cell is painted: the cool-neutral-warm ramp, at this cell's share of the
## grid's largest weight. Every cell is neutral on a robot that has learned
## nothing yet, because on that robot every weight really is the same: zero.
func cell_colour(action: int, group: int) -> Color:
	if _peak <= 0.0:
		return Workbench.WEIGHT_NEUTRAL
	var t: float = clampf(cell_value(action, group) / _peak, -1.0, 1.0)
	if t >= 0.0:
		return Workbench.WEIGHT_NEUTRAL.lerp(Workbench.WEIGHT_WARM, t)
	return Workbench.WEIGHT_NEUTRAL.lerp(Workbench.WEIGHT_COOL, -t)


## Hold a cell. The one being held drops to the second card, so the page always
## shows the last two she looked at.
func tap_cell(action: int, group: int) -> void:
	if action < 0 or action >= cells.size():
		return
	if group < 0 or group >= groups.size():
		return
	var spot := Vector2i(action, group)
	if spot == selected:
		return
	previous = selected
	selected = spot
	queue_redraw()


## What the lit card reads — the held weight, signed — or `""` when nothing is
## held. The card draws this same string, so what a test reads here is what a
## player sees there.
func highlight_text() -> String:
	return _card_text(selected)


## And what the card below it reads: the cell she was holding before this one.
func previous_text() -> String:
	return _card_text(previous)


func _card_text(spot: Vector2i) -> String:
	if spot.x < 0 or spot.y < 0:
		return ""
	return "%+.2f" % cell_value(spot.x, spot.y)


## Ask the eyes page to outline this channel's marks next time it draws. Only the
## channel rows can do it: the five scalars at the bottom are not marks on a tile,
## so there is nothing in the patch for them to light up.
func tap_row(group: int) -> void:
	if group < 0 or group >= _channels:
		return
	var bench := get_parent() as Workbench
	if bench != null:
		bench.highlight_channel = group
	queue_redraw()


# --- the fold -----------------------------------------------------------------

func _fold() -> void:
	groups = []
	cells = []
	_peak = 0.0
	_channels = 0
	var extra := _extra()
	if extra.is_empty():
		return
	var spec: Dictionary = extra.get("spec", Observation.spec_default())
	var weights: Array = extra.get("weights", [])
	if weights.is_empty():
		return
	groups = Observation.input_groups(spec)
	_channels = (spec.get("channels", Observation.CHANNELS) as Array).size()
	cells = Policy.fold(weights, Observation.size(spec), BotBrain.LEARN_ACTIONS, groups)
	for row in cells:
		for v in row:
			_peak = maxf(_peak, absf(float(v)))
	if selected.x >= cells.size() or selected.y >= groups.size():
		selected = Vector2i(-1, -1)
	if previous.x >= cells.size() or previous.y >= groups.size():
		previous = Vector2i(-1, -1)


# The robot's `extra`. The shell owns the one way to reach it (`robot_extra`), and
# this page uses it when it is mounted on a bench; the `farm` handed to
# `show_robot` is the fallback so the page is still readable on its own.
func _extra() -> Dictionary:
	var bench := get_parent() as Workbench
	if bench != null and bench.robot_id == actor_id:
		return bench.robot_extra()
	if farm == null or actor_id == "" or not farm.sim.has_actor(actor_id):
		return {}
	return farm.sim.actor(actor_id).get("extra", {})


# --- the tap surface ----------------------------------------------------------

func _ensure_taps() -> void:
	if _taps == null:
		_taps = Control.new()
		_taps.name = "MosaicTaps"
		_taps.mouse_filter = Control.MOUSE_FILTER_STOP
		_taps.gui_input.connect(_on_grid_input)
		add_child(_taps)
	var rows: int = maxi(groups.size(), 1)
	_taps.position = Vector2(RAIL_X, GRID_Y)
	_taps.size = Vector2(GRID_X + COL_STRIDE * float(BotBrain.LEARN_ACTIONS) - RAIL_X,
		ROW_STRIDE * float(rows))
	_taps.visible = not cells.is_empty()


func _on_grid_input(event: InputEvent) -> void:
	var at := Vector2.INF
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		at = (event as InputEventScreenTouch).position
	if at == Vector2.INF:
		return
	var row: int = int(floorf(at.y / ROW_STRIDE))
	if row < 0 or row >= groups.size():
		return
	# Left of the grid is the row's own swatch, which is a different question:
	# "show me this channel in the patch" rather than "tell me about this weight".
	var x := at.x + RAIL_X
	if x < GRID_X:
		tap_row(row)
		return
	var column: int = int(floorf((x - GRID_X) / COL_STRIDE))
	if column < 0 or column >= cells.size():
		return
	tap_cell(column, row)


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if actor_id == "" or cells.is_empty() or groups.is_empty():
		Workbench.draw_empty_dash(self)
		return

	var bench := get_parent() as Workbench
	var lit: int = bench.highlight_channel if bench != null else -1

	# The columns' pictures, the same eight the whole bench draws with.
	for a in cells.size():
		Workbench.draw_action_glyph(self,
			a, Vector2(GRID_X + COL_STRIDE * float(a) + (CELL.x - HEADER_SIZE) / 2.0,
				HEADER_Y), HEADER_SIZE)

	for g in groups.size():
		var y := GRID_Y + ROW_STRIDE * float(g)
		draw_rect(Rect2(RAIL_X, y, RAIL_W, CELL.y), Color(Workbench.INK_DIM, 0.35))
		_draw_row_mark(g, Vector2(SWATCH_X, y + (CELL.y - SWATCH) / 2.0), lit == g)
		for a in cells.size():
			var cell := Rect2(GRID_X + COL_STRIDE * float(a), y, CELL.x, CELL.y)
			draw_rect(cell, cell_colour(a, g))
			if selected == Vector2i(a, g):
				draw_rect(cell, Workbench.BRASS_LIT, false, 2.0)
			elif previous == Vector2i(a, g):
				draw_rect(cell, Color(Workbench.INK, 0.8), false, 1.0)

	_draw_card(CARD_NOW, selected, true)
	_draw_card(CARD_BEFORE, previous, false)
	_draw_legend()


# A row's picture: the channel's own colour for the eight that are channels (the
# same colour the eyes and the ledger give it, so blue means one thing on the
# whole bench), and a small drawing for each of the five scalars.
func _draw_row_mark(group: int, at: Vector2, lit: bool) -> void:
	var box := Rect2(at, Vector2(SWATCH, SWATCH))
	var row_name := String((groups[group] as Dictionary).get("name", ""))
	if group < _channels:
		draw_rect(box, Workbench.CHANNEL_COLOURS.get(row_name, Workbench.INK))
	else:
		match row_name:
			"position":
				_draw_sun(box)
			"energy":
				_draw_bolt(box)
			"carrying":
				draw_texture_rect_region(Workbench.SHEET_WHEAT, box, Rect2(3 * 16, 0, 16, 16))
			"seeds":
				draw_texture_rect_region(Workbench.SHEET_ICONS, box, Rect2(0, 0, 16, 16))
			"bin":
				draw_texture_rect_region(Workbench.SHEET_BIN, box, Rect2(0, 0, 16, 16))
			_:
				draw_rect(box, Workbench.INK)
	if lit:
		# This is the channel the eyes have been asked to outline. Saying so here
		# is what stops the hand-off from being a thing that happens invisibly on
		# another page.
		draw_rect(box.grow(3.0), Workbench.BRASS_LIT, false, 2.0)


# One of the two cards on the right: the weight, and the two things it joins.
# `now` is the lit one — the cell she is holding — and the other is where the last
# one went.
func _draw_card(rect: Rect2, spot: Vector2i, now: bool) -> void:
	draw_rect(rect, Workbench.CARD)
	draw_rect(rect, Workbench.BRASS_LIT if now and spot.x >= 0 else Workbench.EDGE, false, 2.0)
	if spot.x < 0 or spot.y < 0:
		var c := rect.position + rect.size / 2.0
		draw_rect(Rect2(c.x - 14.0, c.y - 3.0, 28.0, 6.0), Workbench.INK_DIM)
		return

	var f := _font()
	var swatch: float = 24.0 if now else 20.0
	var box_w: float = 98.0 if now else 68.0
	var box := Rect2(rect.position + Vector2(15, 12), Vector2(box_w, rect.size.y - 24.0))
	var tint := cell_colour(spot.x, spot.y)
	draw_rect(box, tint)
	draw_rect(box, Workbench.BRASS_LIT if now else Workbench.EDGE, false, 2.0)

	if f != null:
		var text := _card_text(spot)
		var size: int = VALUE_SIZE if now else SMALL_SIZE
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		# Dark lettering on the warm end, pale on the cool end — the box is the
		# cell's own colour, so the numeral has to survive both ends of the ramp.
		var ink := Color(0.10, 0.08, 0.12) if tint.get_luminance() > 0.45 else Workbench.INK
		draw_string(f, box.position + Vector2((box.size.x - w) / 2.0,
			box.size.y / 2.0 + float(size) * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)

	# The row and the column, as their own pictures: which input, times which
	# action. That is what a weight *is*, said without a word.
	var right := box.end.x + 16.0
	_draw_row_mark(spot.y, Vector2(right, rect.position.y + 30.0), false)
	if now:
		_draw_times(Vector2(right + swatch / 2.0, rect.position.y + 68.0), f)
		Workbench.draw_action_glyph(self, spot.x, Vector2(right, rect.position.y + 82.0), swatch)
	else:
		Workbench.draw_action_glyph(self, spot.x,
			Vector2(right + swatch + 12.0, rect.position.y + 30.0), swatch)
		_draw_times(Vector2(right + swatch + 6.0, rect.position.y + 58.0), f)


# U+00D7, which is Latin-1 and so is carried by the bundled font on every
# platform — the trap the shop's close button fell into with U+2715 twice.
func _draw_times(at: Vector2, f: Font) -> void:
	if f == null:
		return
	draw_string(f, at, "×", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, Workbench.INK_DIM)


# The scale, so a colour on the grid can be read without tapping it: cool at one
# end, warm at the other, and the robot's own largest weight at each end.
func _draw_legend() -> void:
	var steps := 40
	var step_w := LEGEND.size.x / float(steps)
	for i in steps:
		var t := -1.0 + 2.0 * float(i) / float(steps - 1)
		var shade: Color = Workbench.WEIGHT_NEUTRAL.lerp(Workbench.WEIGHT_WARM, t) if t >= 0.0 \
			else Workbench.WEIGHT_NEUTRAL.lerp(Workbench.WEIGHT_COOL, -t)
		draw_rect(Rect2(LEGEND.position.x + step_w * float(i), LEGEND.position.y,
			step_w + 1.0, LEGEND.size.y), shade)
	draw_rect(LEGEND, Workbench.EDGE, false, 1.0)
	var f := _font()
	if f == null:
		return
	var y := LEGEND.end.y + float(LEGEND_SIZE) + 2.0
	for pair in [["-1", 0.0], ["0", 0.5], ["+1", 1.0]]:
		var text := String(pair[0])
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_SIZE).x
		var x := LEGEND.position.x + LEGEND.size.x * float(pair[1])
		draw_string(f, Vector2(x - w * float(pair[1]), y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_SIZE, Workbench.INK_DIM)


# The sun, for the robot's own position on the map: where it is standing, drawn
# as the thing that is always overhead wherever that is.
func _draw_sun(box: Rect2) -> void:
	var c := box.position + box.size / 2.0
	var ink := Color("f2e06a")
	draw_circle(c, box.size.x * 0.24, ink)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * box.size.x * 0.32, c + dir * box.size.x * 0.48, ink, 2.0)


# The bolt, for energy: the one picture of "how much is left in it" that needs no
# word beside it.
func _draw_bolt(box: Rect2) -> void:
	var p := box.position
	var s := box.size
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(s.x * 0.58, s.y * 0.05),
		p + Vector2(s.x * 0.22, s.y * 0.55),
		p + Vector2(s.x * 0.46, s.y * 0.55),
		p + Vector2(s.x * 0.36, s.y * 0.95),
		p + Vector2(s.x * 0.80, s.y * 0.40),
		p + Vector2(s.x * 0.52, s.y * 0.40),
	]), Color("f2e06a"))


func _font() -> Font:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	return f

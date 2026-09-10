# bot_scorecard.gd — what a Mark III did, one line per thing it is paid for
#
# **The panel is its practice** (`design/06`). Until 2026-09-10 that was two
# numerals — nights practised, and yesterday's total — which is what Q-97 ruled
# and what shipped. The designer met it on the tablet and asked for the rest of
# the sentence: *"a scorecard of everything he did... a chart with x-axis each
# day, and y-axis the value done of that action... multiple lines/colors,
# corresponding to each of our rewarded actions."* One number a day cannot say
# whether the machine got better at **selling** or merely watered more mud, and
# that difference is the whole of whether it is worth owning.
#
# **It is the real record, drawn** (D-4: stylise the rendering, never the facts).
# Every point on it is a float the brain wrote when the gateway said yes —
# `extra["history"]` for the days that are closed, `extra["earned"]` for the one
# being played — in `Rewards.KEYS` order, so a line cannot drift away from what
# the robot actually earned. Nothing here computes, smooths or flatters a number;
# presentation reads the sim and never writes it.
#
# **Wordless** (S-7). The only text is numerals: the top of the scale, the zero,
# the first day's number and today's. Which line is which is answered by the
# picture at its right-hand end, and every one of those pictures is one the game
# already uses somewhere else — the shop's coin, the HUD's can, the seed packet
# from "no seeds", the hoe off the tool row, the basket, and the crow itself.
class_name BotScorecard
extends Control

# A fortnight, which is as many days as fit at a width a hand-held tablet can
# resolve. The brain keeps thirty (`BotBrain.LEARN_HISTORY_DAYS`), so a longer
# chart is a constant away and needs no new bookkeeping.
const DAYS_SHOWN := 14

# --- the card's own geometry ---------------------------------------------------
const PLOT_H := 150.0        # the drawing itself
const AXIS_LEFT := 24.0      # room for the scale's numerals
const AXIS_BOTTOM := 16.0    # room for the day numerals
const PIP_SIZE := 18.0       # the picture at the end of a line
const PIP_GUTTER := 32.0     # the column those pictures live in
const PIP_SPACING := 19.0    # closest two of them may sit before they are pushed apart
const PAD := 6.0

# **A line per row, and the pictures are borrowed, never invented** — the same
# rule the two numerals were built on. Where two rows share a verb they share the
# picture and differ in what it is doing: the crow still in the air is the
# wings-up cell of `crow.png`, the crow caught on the food is the perched cell,
# and the watering can that paid for a thirsty *plant* carries a seedling in its
# corner while the one that paid for wet mud does not. So each pair is told apart
# by its picture as well as by its colour, which is what a player who cannot
# separate two blues at arm's length needs.
const SHEET_TOOLS := preload("res://assets/sprites/tool_icons.png")
const SHEET_ICONS := preload("res://assets/sprites/generated/shop_icons.png")
const SHEET_CROW := preload("res://assets/sprites/generated/crow.png")
const SHEET_WHEAT := preload("res://assets/sprites/generated/wheat.png")

const PIPS := {
	"shipped":       { "sheet": "icons", "cell": 3 },                  # the shop's coin
	# **The two birds sit on a card of their own colour.** Every other picture here
	# is light enough to read straight off the panel; the crow is (47, 43, 61),
	# four shades off the panel's own (31, 31, 46), and vanishes into it. So the
	# bird is drawn on a chip in its row's colour — which is also the second thing
	# telling the pair apart, since they are the same bird twice.
	"crow_flying":   { "sheet": "crow",  "cell": 1, "chip": true },    # wings up
	"crow_eating":   { "sheet": "crow",  "cell": 0, "chip": true },    # perched, mid-meal
	"harvested":     { "sheet": "icons", "cell": 5 },                  # the basket
	"watered_plant": { "sheet": "tools", "cell": 4, "sprout": true },  # can, with a seedling
	"planted":       { "sheet": "tools", "cell": 5 },                  # the seed packet
	"tilled":        { "sheet": "tools", "cell": 3 },                  # the hoe
	"watered_soil":  { "sheet": "tools", "cell": 4 },                  # the can, plain
}

# **Eight hues that survive a dark card at arm's length**, taken from the game's
# own ramps where a row has a natural colour and spaced around the wheel where it
# does not (`design/09`: the ambient world is yellow-green and warm tan, so a UI
# hue outside that space reads instantly).
#
# The sale is the crop's own gold; a cut crop is the warm orange of the basket; a
# bird on the food is the one alarming row and takes the red; thirsty plants
# watered is the HUD's own water blue; a seed sown is leaf green; opened ground is
# the dirt ramp's brown. That leaves the two rows with no colour of their own —
# the bird still in the air, and the wet mud — and they take the two hues nothing
# else on the chart uses, so neither can be confused with the row it shares a
# picture with.
const LINE_COLOURS := {
	"shipped":       Color("f2e06a"),
	"crow_flying":   Color("8fa8f0"),
	"crow_eating":   Color("ee7b7b"),
	"harvested":     Color("f2a05a"),
	"watered_plant": Color("63c8f0"),
	"planted":       Color("86d96a"),
	"tilled":        Color("c39a6c"),
	"watered_soil":  Color("c88ae0"),
}

const AXIS_INK := Color(0.62, 0.64, 0.74, 0.75)
const GRID_INK := Color(0.62, 0.64, 0.74, 0.18)
const TODAY_BAND := Color(0.75, 0.78, 0.9, 0.07)
const NUMERAL_SIZE := 11

# What the card is drawing, filled by `show_bot`. Days oldest first; each entry is
# `{ "n": which night of its life, "rows": eight floats, "partial": still being
# played }`.
var days: Array = []


func _init() -> void:
	# A readout, not a control: there is nothing on it to press, so it must not
	# swallow a tap aimed at the panel behind it (the two numerals it replaces had
	# the same rule, for the same reason).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(0, PLOT_H + AXIS_BOTTOM + PAD * 2.0)


# Point the card at a robot. It reads `extra` rather than being handed numbers, so
# there is exactly one place that knows how a robot's record is shaped.
func show_bot(extra: Dictionary) -> void:
	days = read_days(extra, DAYS_SHOWN)
	queue_redraw()


# **The record, as days to plot** — the only place presentation interprets the
# brain's two containers, and pure, so a test can ask what the chart is showing
# without rendering anything.
#
# `history` is the closed days, oldest first; `earned` is today, still open. A
# day's number comes from `days`, the nights the robot has slept: the last closed
# day is night number `days`, and today is the one after it. That stays true once
# the thirty-day cap has begun dropping the front of the record, which a bare
# index into `history` would not.
static func read_days(extra: Dictionary, limit: int = DAYS_SHOWN) -> Array:
	var width: int = (Rewards.KEYS as Array).size()
	var history: Array = extra.get("history", []) as Array
	var nights := int(extra.get("days", 0))
	var out: Array = []
	var first := maxi(0, history.size() - maxi(1, limit) + 1)
	for i in range(first, history.size()):
		out.append({
			"n": nights - history.size() + i + 1,
			"rows": _row_of(history[i], width),
			"partial": false,
		})
	out.append({
		"n": nights + 1,
		"rows": _row_of(extra.get("earned", []), width),
		"partial": true,
	})
	return out


# Eight floats out of whatever is in `extra`. A day that came back from JSON is an
# Array of floats already; a robot from a save written before the record existed
# has none, and gets a day of zeros rather than a gap — "it earned nothing that
# day" is the honest reading of a missing row, and a chart with holes in it would
# be a chart inviting her to guess.
static func _row_of(value, width: int) -> Array:
	var out: Array = []
	out.resize(width)
	out.fill(0.0)
	if value is Array:
		for i in mini(width, (value as Array).size()):
			out[i] = float((value as Array)[i])
	return out


# The top of the scale: the largest point on the chart rounded up to a number a
# person reads without effort. Never below 1, so a robot that has earned nothing
# still gets an axis rather than a division by zero.
static func nice_top(peak: float) -> float:
	if peak <= 1.0:
		return 1.0
	var step := 1.0
	while step * 10.0 <= peak:
		step *= 10.0
	for k in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]:
		if step * float(k) >= peak:
			return step * float(k)
	return step * 10.0


func _draw() -> void:
	if days.is_empty():
		return
	var keys: Array = Rewards.KEYS
	var plot := Rect2(AXIS_LEFT, PAD,
		maxf(24.0, size.x - AXIS_LEFT - PIP_GUTTER), PLOT_H)
	var peak := 0.0
	for day in days:
		for v in day["rows"]:
			peak = maxf(peak, float(v))
	var top := nice_top(peak)

	# The frame: a zero line, a rule at the top of the scale, and the two numerals
	# that say what those heights are. Nothing between them — a gridline per step
	# would out-weigh the data on a card this small.
	var zero_y := plot.position.y + plot.size.y
	draw_line(plot.position, Vector2(plot.position.x, zero_y), AXIS_INK, 1.0)
	draw_line(Vector2(plot.position.x, zero_y),
		Vector2(plot.position.x + plot.size.x, zero_y), AXIS_INK, 1.0)
	draw_line(plot.position, Vector2(plot.position.x + plot.size.x, plot.position.y),
		GRID_INK, 1.0)
	_numeral(_scale_text(top), Vector2(plot.position.x - 3.0, plot.position.y + 8.0), true)
	_numeral("0", Vector2(plot.position.x - 3.0, zero_y + 3.0), true)

	var last := days.size() - 1
	var xs: Array = []
	for i in days.size():
		xs.append(plot.position.x + (plot.size.x if days.size() <= 1
			else plot.size.x * float(i) / float(last)))

	# Today is the rightmost column and is **not a finished day**: it is banded, the
	# segment into it is dashed, and its point is a ring rather than a dot. A part
	# day drawn like a whole one is the one way a truthful chart still misleads —
	# every morning would look like a collapse.
	if days.size() > 1:
		var band_left: float = (float(xs[last - 1]) + float(xs[last])) / 2.0
		draw_rect(Rect2(band_left, plot.position.y,
			float(xs[last]) - band_left, plot.size.y), TODAY_BAND)

	# The day numerals: the oldest day on the chart, and today. Two rather than
	# fourteen, because fourteen at this width is a grey smear.
	_numeral(str(int(days[0]["n"])), Vector2(float(xs[0]), zero_y + AXIS_BOTTOM - 2.0),
		days.size() <= 1)
	if days.size() > 1:
		_numeral(str(int(days[last]["n"])),
			Vector2(float(xs[last]), zero_y + AXIS_BOTTOM - 2.0), true)

	# One line per row of the reward table, in the table's own order — so the day a
	# ninth row is priced, a ninth line appears here and nobody has to remember to
	# add it. O(days x rows), and only while the panel is open.
	var ends: Array = []
	for r in keys.size():
		var colour: Color = LINE_COLOURS.get(keys[r], Color.WHITE)
		var points := PackedVector2Array()
		for i in days.size():
			var v := float(days[i]["rows"][r])
			points.append(Vector2(float(xs[i]), zero_y - plot.size.y * (v / top)))
		ends.append(points[last].y)
		if points.size() >= 3:
			# The finished days, solid; today's segment is the dashed one below.
			draw_polyline(points.slice(0, last), colour, 2.0, true)
		if points.size() >= 2:
			draw_dashed_line(points[last - 1], points[last], colour, 2.0, 3.0)
		for i in days.size():
			if bool(days[i].get("partial", false)):
				draw_arc(points[i], 3.0, 0.0, TAU, 12, colour, 1.5, true)
			else:
				draw_circle(points[i], 2.0, colour)

	# ...and its picture at the right-hand end, which is the whole legend. Several
	# rows finish a day at zero and would stack their pictures on top of one
	# another, so the column is relaxed apart — the leader, drawn in the row's own
	# colour, is what keeps a picture attached to the line it belongs to.
	var slots := _relax(ends, plot.position.y + PIP_SIZE / 2.0, zero_y - PIP_SIZE / 2.0)
	var pip_x := plot.position.x + plot.size.x + PIP_GUTTER - PIP_SIZE - 2.0
	for r in keys.size():
		var colour: Color = LINE_COLOURS.get(keys[r], Color.WHITE)
		# Thin and half-lit: eight leaders in one narrow gutter make a bundle, and a
		# bundle drawn at the weight of the data competes with the data.
		draw_line(Vector2(plot.position.x + plot.size.x, float(ends[r])),
			Vector2(pip_x - 2.0, float(slots[r])),
			Color(colour, colour.a * 0.5), 1.0, true)
		_pip(String(keys[r]), Vector2(pip_x, float(slots[r]) - PIP_SIZE / 2.0), colour)


# Push a column of pictures apart until none sits closer to its neighbour than
# `PIP_SPACING`, keeping them in the order their lines finished and inside the
# card. Down and then back up, which is the shortest honest fix: a picture may end
# a few pixels off its line's height, and its leader says where it came from.
static func _relax(wanted: Array, low: float, high: float) -> Array:
	var order: Array = []
	for i in wanted.size():
		order.append(i)
	order.sort_custom(func(a, b): return float(wanted[a]) < float(wanted[b]))
	var placed: Array = []
	placed.resize(wanted.size())
	var y := low
	for i in order:
		y = maxf(float(wanted[i]), y)
		placed[i] = y
		y += PIP_SPACING
	# That sweep can run off the bottom of the card; walk back up from the last.
	var limit := high
	for j in range(order.size() - 1, -1, -1):
		var i: int = order[j]
		placed[i] = minf(float(placed[i]), limit)
		limit = float(placed[i]) - PIP_SPACING
	return placed


func _pip(key: String, at: Vector2, colour: Color) -> void:
	draw_pip(self, key, at, PIP_SIZE, colour)


# **The row's picture, drawn anywhere and at any size** (v0.2.2, the workbench).
#
# It was this card's private method until the bench asked for the same eight
# pictures on its dials page — and a second copy of "which cell is the hoe, and
# which of them needs a chip behind it" is the exact thing that lets two surfaces
# drift apart until the crow on one panel is not the crow on the other. So the
# drawing moved here, static, taking the canvas it draws on; the card's own `_pip`
# above is this function at `PIP_SIZE`, which is what keeps the machine panel
# pixel-identical to before.
#
# The chip and the seedling are placed in **fractions of the pip**, so a bigger
# pip is the same picture bigger rather than the same picture with a chip sliding
# off it. At `size == PIP_SIZE` the arithmetic is the constants it replaced.
static func draw_pip(canvas: CanvasItem, key: String, at: Vector2, size: float,
		colour: Color = Color(1, 1, 1)) -> void:
	var entry: Dictionary = PIPS.get(key, {})
	if entry.is_empty():
		return
	var scale := size / PIP_SIZE
	var sheet := _sheet_of(String(entry.get("sheet", "tools")))
	var cell := int(entry.get("cell", 0))
	if bool(entry.get("chip", false)):
		canvas.draw_rect(
			Rect2(at + Vector2(1.0, 2.0) * scale, Vector2(size - 2.0 * scale, size - 4.0 * scale)),
			Color(colour, 0.9))
	canvas.draw_texture_rect_region(sheet, Rect2(at, Vector2(size, size)),
		Rect2(cell * 16, 0, 16, 16))
	if bool(entry.get("sprout", false)):
		# The seedling that says "this can went on something growing": wheat's
		# first growth stage, small, in the corner — the same picture the farm
		# draws on a bed that has just come up.
		canvas.draw_texture_rect_region(SHEET_WHEAT,
			Rect2(at + Vector2(size * 0.48, -size * 0.18), Vector2(size, size) * 0.66),
			Rect2(0, 0, 16, 16))


static func _sheet_of(sheet_name: String) -> Texture2D:
	match sheet_name:
		"icons":
			return SHEET_ICONS
		"crow":
			return SHEET_CROW
		"wheat":
			return SHEET_WHEAT
		_:
			return SHEET_TOOLS


# A number on an axis. `right` ends it at `at` instead of starting it there, which
# is what both the scale and today's day number need.
func _numeral(text: String, at: Vector2, right: bool) -> void:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMERAL_SIZE).x
	draw_string(f, Vector2(at.x - (w if right else 0.0), at.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, NUMERAL_SIZE, AXIS_INK)


# The top of the scale, written the way a person would: whole when it is whole,
# and one decimal only for the fractions the two tenth-point rows leave on a robot
# that has earned nothing else.
static func _scale_text(top: float) -> String:
	if is_equal_approx(top, roundf(top)):
		return str(int(roundf(top)))
	return "%.1f" % top

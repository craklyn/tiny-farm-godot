# metric_card.gd — one number about the robot's day, and the days behind it
#
# **The four small cards under the workbench's ledger** (`design/14`, Q-101).
# Each one answers a single question about the machine — what it expected of the
# day against what it got, how undecided it is, how far last night moved it, how
# many of its decisions came to nothing — and answers it twice: as today's
# numeral, big, and as the shape of the days leading to it.
#
# **It is the scorecard's own drawing at card size** (ground rule 8). The scale,
# the inks and the numeral size are `BotScorecard`'s, so a card cannot round a
# number one way while the chart above it rounds it another.
#
# **Wordless** (S-7). Numerals only: today's reading, and the reference where a
# measure has one. What the card is *about* is the picture in its corner, which is
# the same rule the scorecard's eight row pictures are drawn under.
#
# **Today is never drawn as a finished day.** The last column is dashed and ringed
# on a line, and outlined rather than filled on bars — the same language the
# machine panel already uses, for the same reason: a part day drawn like a whole
# one makes every morning look like a collapse.
class_name MetricCard
extends Control

# --- the card's own geometry ---------------------------------------------------
const PAD := 10.0
const GLYPH := 22.0          # the picture in the corner
const READING_SIZE := 18     # today's numeral
const DELTA_W := 11.0        # the triangle that says which way it moved
const HEAD_H := 30.0         # the band the picture and the numeral live in

# The face is a shade up from the bench's body, so four cards read as four things
# rather than as one dark field. The mockup's `#262636`; it lives here rather than
# on `Workbench` because the card is its own widget and nothing else uses it.
const FACE := Color("262636")

# The data's own ink: the grey the bench gives ground with, which is what a
# reading with no natural colour should be. Today is drawn in the same ink — it is
# the same measure, not a different one — and told apart by being unfinished.
const INK_LINE := Color("8a8fa8")
const INK_TODAY := Color("c2c9e0")

# --- what the card is showing, filled by `show_series` -------------------------

## The closed days, oldest first. The card draws the last `BotScorecard.DAYS_SHOWN`
## of them, which is the window the chart above it draws.
var closed: Array = []

## Today's reading, or `NAN` for a measure that only exists at night.
var today: float = NAN

## `"line"` or `"bars"`.
var kind: String = "line"

## Which picture the corner carries: `"rising"`, `"spread"`, `"grid"`, `"crossed"`.
var glyph: String = ""

## A height worth marking on the scale — entropy's ceiling is the only one so far
## — or `NAN` for none.
var reference: float = NAN

## **The numeral the card carries, and what its triangle compares it against.**
##
## For three of the four cards that is today's reading against yesterday's, and
## `show_series` fills both from what it is handed. The night's update is the
## odd one out: it is a measure that only exists once she has slept, so its
## numeral is *last night's* against the night before (v0.2.2 WI-8), which is
## what `show_nightly` fills them with. Keeping the numeral apart from `today`
## is what lets that card say a number while its line still ends at the last
## finished day — the mockup's card, and the truth: there is no today point to
## draw, because no update has happened today.
var reading: float = NAN
var previous: float = NAN


func _init() -> void:
	# A readout, like the scorecard: nothing on it to press, so it must not eat a
	# tap meant for the plate strip above it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Point the card at a series.
##
## The parameters are named apart from the members they fill (`series` for
## `closed`, `today_value` for `today`) only because a parameter of the same name
## would shadow the member and earn a warning on every parse.
func show_series(series: Array, today_value: float, kind_name: String,
		glyph_name: String, reference_value: float = NAN) -> void:
	closed = series
	today = today_value
	kind = kind_name
	glyph = glyph_name
	reference = reference_value
	reading = today_value
	previous = float(series[series.size() - 1]) if not series.is_empty() else NAN
	queue_redraw()


## Point the card at a measure that **only exists at night** (v0.2.2 WI-8).
##
## The night's update is the one reading with no today: it happens while she
## sleeps, so the card carries last night's number, compares it with the night
## before, and its line stops at the last finished day rather than reaching for
## a point that does not exist yet. `reading_value` is `NAN` for a robot that has
## never slept, which draws the dash — "nothing yet" and "zero" being different
## answers.
func show_nightly(series: Array, reading_value: float, glyph_name: String) -> void:
	closed = series
	today = NAN
	kind = "line"
	glyph = glyph_name
	reference = NAN
	reading = reading_value
	previous = float(series[series.size() - 2]) if series.size() >= 2 else NAN
	queue_redraw()


# **The columns the card draws**, oldest first: the tail of the closed days, and
# today when there is a today. Pure, so a test can ask what a card is showing
# without rendering it.
func columns() -> Array:
	var out: Array = []
	var first := maxi(0, closed.size() - BotScorecard.DAYS_SHOWN)
	for i in range(first, closed.size()):
		out.append(float(closed[i]))
	if not is_nan(today):
		out.append(today)
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FACE)
	draw_rect(Rect2(Vector2.ZERO, size), Workbench.EDGE, false, 1.0)
	_draw_glyph(Rect2(PAD, PAD, GLYPH, GLYPH))
	_draw_reading()
	_draw_series()


# --- the reading ---------------------------------------------------------------

# The card's number, and which way it moved from the one behind it. A card with
# no reading at all — the night's update on a robot that has never slept — gets a
# dash and no triangle, because "nothing yet" and "zero" are different answers.
func _draw_reading() -> void:
	var f := _font()
	if f == null:
		return
	var right := size.x - PAD
	if is_nan(reading):
		draw_rect(Rect2(right - 22.0, PAD + HEAD_H / 2.0 - 2.0, 22.0, 4.0),
			Color(BotScorecard.AXIS_INK, 0.7))
		return

	if not is_nan(previous) and not is_equal_approx(reading, previous):
		_draw_delta(right - DELTA_W, PAD + HEAD_H / 2.0, reading > previous)
		right -= DELTA_W + 5.0

	var text := format_reading(reading, _signed())
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, READING_SIZE).x
	draw_string(f, Vector2(right - w, PAD + HEAD_H / 2.0 + READING_SIZE * 0.36), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, READING_SIZE, Workbench.INK)


# Up or down since the reading behind this one, and **only that** — yesterday for
# a card whose numeral is today's, the night before last for the night's update.
# Which of the two is good news
# depends on the card — fewer wasted decisions is better, more entropy is usually
# worse — so the triangle is one ink and never a verdict (D-4).
func _draw_delta(x: float, mid: float, up: bool) -> void:
	var h := 6.0
	var ink := Color(Workbench.INK, 0.8)
	if up:
		draw_colored_polygon(PackedVector2Array([
			Vector2(x + DELTA_W / 2.0, mid - h / 2.0),
			Vector2(x + DELTA_W, mid + h / 2.0), Vector2(x, mid + h / 2.0)]), ink)
	else:
		draw_colored_polygon(PackedVector2Array([
			Vector2(x + DELTA_W / 2.0, mid + h / 2.0),
			Vector2(x, mid - h / 2.0), Vector2(x + DELTA_W, mid - h / 2.0)]), ink)


# A number written the way a person reads it: whole when it is whole, two places
# while it is small enough for them to matter, one when it is not.
static func format_reading(value: float, signed: bool = false) -> String:
	var text := ""
	if is_equal_approx(value, roundf(value)):
		text = str(int(roundf(value)))
	elif absf(value) < 10.0:
		text = "%.2f" % value
	else:
		text = "%.1f" % value
	if signed and value > 0.0:
		text = "+" + text
	return text


# A card whose measure can go either side of zero signs its numeral, so "+10" and
# "10" are never the same picture on two cards that mean different things.
func _signed() -> bool:
	if not is_nan(reading) and reading < 0.0:
		return true
	for v in closed:
		if float(v) < 0.0:
			return true
	return false


# --- the series ----------------------------------------------------------------

func _draw_series() -> void:
	var vals := columns()
	if vals.is_empty():
		return
	var plot := Rect2(PAD + 4.0, PAD + HEAD_H,
		maxf(16.0, size.x - (PAD + 4.0) * 2.0),
		maxf(16.0, size.y - PAD - HEAD_H - PAD))

	var hi := 0.0
	var lo := 0.0
	for v in vals:
		hi = maxf(hi, float(v))
		lo = minf(lo, float(v))
	if not is_nan(reference):
		hi = maxf(hi, reference)
	var top := BotScorecard.nice_top(hi)
	var bottom := (-BotScorecard.nice_top(-lo)) if lo < 0.0 else 0.0
	var span := maxf(0.001, top - bottom)
	var zero_y: float = plot.end.y - plot.size.y * (0.0 - bottom) / span

	# The rule the data stands on. When the measure goes negative that rule is the
	# zero and the card's own floor is only an edge, so a bar below the line reads
	# as below it rather than as a short bar.
	draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y),
		BotScorecard.AXIS_INK, 1.0)
	if bottom < 0.0:
		draw_line(plot.end, Vector2(plot.position.x, plot.end.y),
			BotScorecard.GRID_INK, 1.0)

	if not is_nan(reference):
		var ry: float = plot.end.y - plot.size.y * (reference - bottom) / span
		draw_dashed_line(Vector2(plot.position.x, ry), Vector2(plot.end.x, ry),
			BotScorecard.GRID_INK, 1.0, 3.0)
		var f := _font()
		if f != null:
			var text := format_reading(reference)
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				BotScorecard.NUMERAL_SIZE).x
			draw_string(f, Vector2(plot.end.x - w, ry - 3.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, BotScorecard.NUMERAL_SIZE,
				BotScorecard.AXIS_INK)

	if kind == "bars":
		_draw_bars(vals, plot, zero_y, top, bottom, span)
	else:
		_draw_line(vals, plot, top, bottom, span)


func _draw_line(vals: Array, plot: Rect2, _top: float, bottom: float, span: float) -> void:
	var last := vals.size() - 1
	var points := PackedVector2Array()
	for i in vals.size():
		var x: float = plot.position.x + (plot.size.x if vals.size() <= 1
			else plot.size.x * float(i) / float(last))
		points.append(Vector2(x,
			plot.end.y - plot.size.y * (float(vals[i]) - bottom) / span))
	var open_end := not is_nan(today)
	var solid: int = (last if open_end else last + 1)
	if solid >= 2:
		draw_polyline(points.slice(0, solid), INK_LINE, 2.0, true)
	if open_end and points.size() >= 2:
		draw_dashed_line(points[last - 1], points[last], INK_TODAY, 2.0, 3.0)
	for i in points.size():
		if open_end and i == last:
			draw_arc(points[i], 3.0, 0.0, TAU, 12, INK_TODAY, 1.5, true)
		elif points.size() <= 2:
			draw_circle(points[i], 2.0, INK_LINE)


func _draw_bars(vals: Array, plot: Rect2, zero_y: float, _top: float, bottom: float,
		span: float) -> void:
	var last := vals.size() - 1
	var slot := plot.size.x / float(maxi(1, vals.size()))
	# Capped as well as shared out: a robot on its first day has one column, and a
	# bar seventy per cent of the card wide reads as a filled panel rather than as
	# one day's count.
	var w := clampf(slot * 0.7, 2.0, 18.0)
	for i in vals.size():
		var cx := plot.position.x + slot * (float(i) + 0.5)
		var y: float = plot.end.y - plot.size.y * (float(vals[i]) - bottom) / span
		var bar := Rect2(cx - w / 2.0, minf(y, zero_y), w, maxf(1.0, absf(y - zero_y)))
		if i == last and not is_nan(today):
			# Today, still running: lit at its edge and hollow inside, which is the
			# bar version of the ring the chart above puts on today's point.
			draw_rect(bar, Color(INK_LINE, 0.30))
			draw_rect(bar, INK_TODAY, false, 1.0)
		else:
			draw_rect(bar, INK_LINE)


# --- the corner picture --------------------------------------------------------
#
# Four small drawings, from lines and squares: the game has no picture for "how
# undecided a machine is" and inventing a sprite for four 22-pixel marks would be
# art nobody else can use.
func _draw_glyph(box: Rect2) -> void:
	var ink := Color(Workbench.INK, 0.85)
	match glyph:
		"rising":
			# What it got against what it expected: a line that climbs.
			draw_polyline(PackedVector2Array([
				Vector2(box.position.x, box.end.y - 3.0),
				Vector2(box.position.x + box.size.x * 0.36, box.position.y + box.size.y * 0.52),
				Vector2(box.position.x + box.size.x * 0.60, box.position.y + box.size.y * 0.66),
				Vector2(box.end.x, box.position.y + 3.0),
			]), ink, 2.0, true)
		"spread":
			# How undecided it is: the spread of chances it drew from.
			var heights := [0.55, 1.0, 0.40, 0.75, 0.30, 0.22, 0.16]
			for i in heights.size():
				var h: float = box.size.y * float(heights[i])
				draw_rect(Rect2(box.position.x + i * (box.size.x / float(heights.size())),
					box.end.y - h, box.size.x / float(heights.size()) - 1.0, h), ink)
		"grid":
			# How far the night moved it: the weights, one cell of them changed.
			for gy in 2:
				for gx in 3:
					var cell := Rect2(box.position.x + gx * (box.size.x / 3.0),
						box.position.y + box.size.y * 0.18 + gy * (box.size.y * 0.36),
						box.size.x / 3.0 - 2.0, box.size.y * 0.36 - 2.0)
					draw_rect(cell, Workbench.WEIGHT_WARM if (gx == 1 and gy == 0)
						else Color(ink, 0.55))
		"crossed":
			# A decision that came to nothing: a square struck through.
			draw_rect(box, ink, false, 2.0)
			draw_line(box.position + Vector2(2.0, box.size.y - 2.0),
				box.position + Vector2(box.size.x - 2.0, 2.0), ink, 2.0)


# The face the whole game writes numerals in, found the way the scorecard's own
# `_numeral` finds it. It is copied rather than shared because that helper is an
# instance method that draws on the scorecard itself; see the note in WI-5.
func _font() -> Font:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	return f

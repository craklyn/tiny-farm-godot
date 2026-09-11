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
# **A short label, then numerals** (2026-09-10). The card's picture was meant to
# say what it is about, the way the scorecard's eight row pictures do. It did not:
# the designer, looking at the finished page, said *"I don't know what the four
# charts at bottom of screen are. I can't tell by the illustration."* So a card
# carries a few plain words above its picture — the licence §7 of `design/14`
# already gives the bench's scientist pages — and nothing else on it is written.
# There is no drawing of "how undecided a machine is" that a person reads cold.
#
# **Today is never drawn as a finished day.** The last column is dashed and ringed
# on a line, and outlined rather than filled on bars — the same language the
# machine panel already uses, for the same reason: a part day drawn like a whole
# one makes every morning look like a collapse.
#
# **A column per day, and today is one of them** (2026-09-10). The cards used to
# spread their days between the plot's two edges, which put today on the right edge
# itself. The chart above them was fixed the same morning and they now follow it: as
# many equal columns as there are days, each day's point or bar centred in its own,
# and `BotScorecard.TODAY_BAND` over the last column edge to edge. A measure that
# only exists at night keeps that column too — banded and empty, because the day is
# real even where the reading is not.
#
# **Two heights carry a numeral, and nothing else does** (2026-09-10). Asked whether
# these four plots need their axes labelled, the answer is almost none of it: the
# words along the top are already the metric's name, the day axis belongs to the
# chart above (which counts `-13` to `0` over the same fortnight), and a card's
# heights are read against the other days on the card rather than against a scale.
# The exceptions are the two heights that mean something on their own — zero, where
# a measure can cross it, and the 3.00 a machine picking evenly between its eight
# actions would sit at — so those two get a small numeral and the rest of the card
# stays a picture.
class_name MetricCard
extends Control

# --- the card's own geometry ---------------------------------------------------
const PAD := 10.0
const GLYPH := 22.0          # the picture in the corner
const READING_SIZE := 18     # today's numeral
const DELTA_W := 11.0        # the triangle that says which way it moved
const HEAD_H := 30.0         # the band the picture and the numeral live in

# The label is written at the axis numerals' size, because it is the same kind of
# thing: a small mark that tells you how to read the drawing, not part of it.
const LABEL_SIZE := BotScorecard.NUMERAL_SIZE

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

## **What this card is about, in a few plain words** (2026-09-10), drawn along the
## card's top edge above the picture. It belongs to the slot rather than to the
## robot — the ledger sets it once, when it builds its four cards — so it is a
## member here and not a parameter of `show_series`, which says what the numbers
## are. Empty draws nothing and costs the series no height, which is what a card
## used anywhere else would get.
var label: String = ""

## The closed days, oldest first. The card draws the last
## `BotScorecard.DAYS_SHOWN - 1` of them, so that those days plus today's own column
## come to the same fortnight the chart above the cards draws.
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


# **The points the card draws**, oldest first: the tail of the closed days, and
# today when today has a reading. The card can lay out one column more than this —
# a measure that only exists at night still gets today's column, empty (2026-09-10)
# — which `_draw_series` works out from `today`. Pure, so a test can ask what a card
# is showing without rendering it.
func columns() -> Array:
	var out: Array = []
	var first := maxi(0, closed.size() - (BotScorecard.DAYS_SHOWN - 1))
	for i in range(first, closed.size()):
		out.append(float(closed[i]))
	if not is_nan(today):
		out.append(today)
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FACE)
	draw_rect(Rect2(Vector2.ZERO, size), Workbench.EDGE, false, 1.0)
	_draw_label()
	_draw_glyph(Rect2(PAD, _head_top(), GLYPH, GLYPH))
	_draw_reading()
	_draw_series()


# --- the label -----------------------------------------------------------------

# The words go along the top, and the rest of the card moves down under them as a
# block: the picture keeps the numeral's company on one band and the numeral keeps
# its corner, so only the chart is any smaller than it was. Clipped to the card's
# width rather than allowed to run off the edge — four cards at 180 across have
# room for these four labels, and a longer one should look cramped rather than
# spill onto its neighbour.
func _draw_label() -> void:
	if label == "":
		return
	var f := _font()
	if f == null:
		return
	draw_string(f, Vector2(PAD, PAD + f.get_ascent(LABEL_SIZE)), label,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2.0, LABEL_SIZE,
		BotScorecard.AXIS_INK)


# The top of the band the picture and the numeral live in: the padding, plus the
# label's line where there is a label.
func _head_top() -> float:
	return PAD + _label_h()


func _label_h() -> float:
	if label == "":
		return 0.0
	var f := _font()
	return 0.0 if f == null else f.get_height(LABEL_SIZE)


# --- the reading ---------------------------------------------------------------

# The card's number, and which way it moved from the one behind it. A card with
# no reading at all — the night's update on a robot that has never slept — gets a
# dash and no triangle, because "nothing yet" and "zero" are different answers.
func _draw_reading() -> void:
	var f := _font()
	if f == null:
		return
	var right := size.x - PAD
	var mid := _head_top() + HEAD_H / 2.0
	if is_nan(reading):
		draw_rect(Rect2(right - 22.0, mid - 2.0, 22.0, 4.0),
			Color(BotScorecard.AXIS_INK, 0.7))
		return

	if not is_nan(previous) and not is_equal_approx(reading, previous):
		_draw_delta(right - DELTA_W, mid, reading > previous)
		right -= DELTA_W + 5.0

	var text := format_reading(reading, _signed())
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, READING_SIZE).x
	draw_string(f, Vector2(right - w, mid + READING_SIZE * 0.36), text,
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
	# The chart is what the label is paid for: it starts one line lower and ends
	# where it always did.
	var plot := Rect2(PAD + 4.0, _head_top() + HEAD_H,
		maxf(16.0, size.x - (PAD + 4.0) * 2.0),
		maxf(16.0, size.y - _head_top() - HEAD_H - PAD))

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

	# **A column per day, the point in the middle of it** — the chart's own layout
	# above these cards. `vals` already ends with today where today has a reading;
	# where it does not, the column is laid out anyway and left empty, so the band
	# sits in the same place on all four cards.
	var slots := vals.size() + (1 if is_nan(today) else 0)
	var slot := plot.size.x / float(slots)

	# Today, banded edge to edge of its own column: a part day, marked as one. A
	# robot on its first day has the whole plot banded, which is the truth about
	# that robot.
	draw_rect(Rect2(plot.position.x + slot * float(slots - 1), plot.position.y,
		slot, plot.size.y), BotScorecard.TODAY_BAND)

	# The rule the data stands on, and the one height every card has in common: the
	# scale is built around zero — `hi` and `lo` both start there — so the line is
	# always on the card, and a bar's length means nothing except against it. Faint,
	# because it is a rule and not a reading.
	draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y),
		BotScorecard.GRID_INK, 1.0)
	if bottom < 0.0:
		# Below zero is a real place on this card, so the card's own floor becomes
		# only an edge and the zero rule gets the numeral that says which line it is.
		draw_line(plot.end, Vector2(plot.position.x, plot.end.y),
			BotScorecard.GRID_INK, 1.0)
		_numeral("0", Vector2(plot.position.x - 2.0, zero_y + 3.0),
			HORIZONTAL_ALIGNMENT_RIGHT)

	if not is_nan(reference):
		var ry: float = plot.end.y - plot.size.y * (reference - bottom) / span
		draw_dashed_line(Vector2(plot.position.x, ry), Vector2(plot.end.x, ry),
			BotScorecard.GRID_INK, 1.0, 3.0)
		# What height that dashed line is, at its right end and to two places —
		# "2.24 against 3.00" is the whole reading of the entropy card. The reference
		# is usually the top of the scale, where a numeral hung above the line would
		# climb into the big reading's row, so it drops just inside the plot instead.
		_numeral("%.2f" % reference, Vector2(plot.end.x, maxf(
			plot.position.y + float(BotScorecard.NUMERAL_SIZE), ry - 3.0)),
			HORIZONTAL_ALIGNMENT_RIGHT)

	if kind == "bars":
		_draw_bars(vals, plot, zero_y, slot, bottom, span)
	else:
		_draw_line(vals, plot, slot, bottom, span)


func _draw_line(vals: Array, plot: Rect2, slot: float, bottom: float, span: float) -> void:
	var last := vals.size() - 1
	var points := PackedVector2Array()
	for i in vals.size():
		points.append(Vector2(plot.position.x + slot * (float(i) + 0.5),
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


func _draw_bars(vals: Array, plot: Rect2, zero_y: float, slot: float, bottom: float,
		span: float) -> void:
	var last := vals.size() - 1
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


# --- the two numerals on the plot ----------------------------------------------

# A small numeral, the scorecard's way (2026-09-10): its size, its ink, and placed
# by the end that matters rather than by its left edge, so the `0` hangs off the
# zero line's left and the reference off its line's right. Never allowed off the
# left of the card, which is the one direction the card has no room in.
func _numeral(text: String, at: Vector2, align: int) -> void:
	var f := _font()
	if f == null:
		return
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		BotScorecard.NUMERAL_SIZE).x
	var dx := 0.0
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		dx = -w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		dx = -w / 2.0
	draw_string(f, Vector2(maxf(1.0, at.x + dx), at.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, BotScorecard.NUMERAL_SIZE,
		BotScorecard.AXIS_INK)


# The face the whole game writes numerals in, found the way the scorecard's own
# `_numeral` finds it. It is copied rather than shared because that helper is an
# instance method that draws on the scorecard itself; see the note in WI-5.
func _font() -> Font:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	return f

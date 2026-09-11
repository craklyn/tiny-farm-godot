# workbench_ledger.gd — plate 4 of 5: the days it has had, and how they went
#
# **The chart is the panel's chart** (ground rule 8, v0.2.2 WI-5). The big drawing
# here is one `BotScorecard`, the same object the machine panel puts on a Mark
# III's readout, at the size this page has room for — so the bench and the panel
# can never tell the player two different stories about the same week. The only
# thing that differs is `plot_h`.
#
# **Four cards under it, one question each.** The chart says what the robot earned;
# the cards say how the day went for the machine itself: what it expected of the
# day against what it got, how undecided it was, how far the night moved it, and
# how many of its decisions came to nothing. Every one of those is a column of
# `extra["ledger"]`, written by the brain at bedtime and read here — nothing on
# this page is computed twice or smoothed (D-4).
#
# **It never writes the robot.** Reads through `farm.sim` and the shell's
# `robot_extra()`, and that is all.
#
# Geometry is the mockup's (`docs/design/mockups/workbench/workbench_ledger.png`,
# F-44), absolute: the page is a full-rect 800x600 Control, so the numbers are
# used as written.
extends Control

# --- geometry (F-44) -----------------------------------------------------------
const CHART_RECT := Rect2(28, 164, 744, 232)
const CARD_SIZE := Vector2(180, 158)
const CARD_Y := 414.0
const CARD_X: Array[float] = [28.0, 216.0, 404.0, 592.0]

# **What each card is about, in words** (2026-09-10). The four pictures were meant
# to carry it and did not: shown the finished page, the designer said *"I don't
# know what the four charts at bottom of screen are. I can't tell by the
# illustration."* These are the bench's scientist pages, where "how undecided it
# is" has no drawing a person reads cold, and §7 of `design/14` allows words here.
# Lowercase and as plain as the measures let them be — what a person would say
# about the robot, not the name a metrics review uses.
const CARD_LABELS: Array[String] = [
	"against its usual day",
	"still guessing",
	"changed overnight",
	"wasted tries",
]

# The well the chart is sunk into: a shade darker than the body, which is what
# says "this is the data" rather than "this is more bench".
const WELL := Color("1b1b28")

## The farm to read through, and the robot to read. `""` means the player owns no
## learning robot, and the page draws its empty state.
var farm: Node2D = null
var actor_id: String = ""

## The week, as the machine panel draws it.
var chart: BotScorecard = null

## The four `MetricCard`s, left to right: expected against actual, entropy, the
## night's update, spent decisions.
var cards: Array = []


func _ready() -> void:
	_build()


func show_robot(farm_node: Node2D, id: String) -> void:
	farm = farm_node
	actor_id = id
	# The shell builds its pages by hand and may hand one a robot before the tree
	# has readied it; building on demand costs nothing and removes the ordering.
	if chart == null:
		_build()
	var live := actor_id != ""
	chart.visible = live
	for card in cards:
		(card as Control).visible = live
	if live:
		var extra := _extra()
		chart.show_bot(extra)
		_fill_cards(extra)
	queue_redraw()


func _build() -> void:
	if chart != null:
		return
	chart = BotScorecard.new()
	chart.name = "LedgerChart"
	chart.position = CHART_RECT.position
	# The room the page has, less the axis numerals and the card's own padding —
	# so the drawing fills the well instead of sitting in the top of it.
	chart.plot_h = CHART_RECT.size.y - BotScorecard.AXIS_BOTTOM - BotScorecard.PAD * 2.0
	chart.size = CHART_RECT.size
	chart.visible = false
	add_child(chart)

	for i in CARD_X.size():
		var card := MetricCard.new()
		card.name = "Metric%d" % i
		# The label belongs to the slot, not to the robot on the bench: card two is
		# the entropy card whichever machine is being read, so it is set here once
		# and `_fill_cards` is left to the numbers.
		card.label = CARD_LABELS[i]
		card.position = Vector2(CARD_X[i], CARD_Y)
		card.size = CARD_SIZE
		card.visible = false
		add_child(card)
		cards.append(card)


# **The one way a page reaches the robot's record** is the shell's `robot_extra()`
# (v0.2.2 WI-2). The direct read below is only for a page held on its own — a
# capture tool, or a test that builds the page without the bench around it.
func _extra() -> Dictionary:
	var shell := get_parent()
	if shell != null and shell.has_method("robot_extra"):
		return shell.robot_extra()
	if farm == null or actor_id == "" or farm.get("sim") == null:
		return {}
	if not farm.sim.has_actor(actor_id):
		return {}
	return farm.sim.actor(actor_id).get("extra", {})


# The four cards, off the seven-float ledger rows the brain writes at bedtime:
# `[score, expected, entropy, update, spent, decisions, waits]`.
func _fill_cards(extra: Dictionary) -> void:
	if cards.size() < 4:
		return
	var ledger: Array = extra.get("ledger", []) as Array
	var gap: Array = []
	var entropy: Array = []
	var update: Array = []
	var spent: Array = []
	for raw in ledger:
		var row: Array = (raw as Array) if raw is Array else []
		# What it got, less what it expected. A robot that keeps beating its own
		# average is a robot still learning something; one sitting at zero has
		# settled, whether it settled high or low.
		gap.append(_col(row, 0) - _col(row, 1))
		entropy.append(_col(row, 2))
		update.append(_col(row, 3))
		spent.append(_col(row, 4))

	var decisions := int(extra.get("decisions", 0))
	var today_gap := float(extra.get("score", 0.0)) - float(extra.get("baseline", 0.0))
	# Today's entropy is the day's sum over the day's decisions. Before it has
	# decided anything there is no answer, and a NAN is how the card is told to
	# draw a dash rather than a confident zero.
	var today_entropy := NAN
	if decisions > 0:
		today_entropy = float(extra.get("entropy_sum", 0.0)) / float(decisions)
	# The ceiling: a machine picking evenly between everything it could do.
	# Computed off `LEARN_ACTIONS` rather than typed, so the day a ninth action is
	# added the line moves with it.
	var even := log(float(BotBrain.LEARN_ACTIONS)) / log(2.0)

	cards[0].show_series(gap, today_gap, "line", "rising")
	cards[1].show_series(entropy, today_entropy, "line", "spread", even)
	# **The night's update has no today** — it is a thing that happens while she
	# sleeps, so its line stops at the last finished night. The numeral it carries
	# is therefore *last night's* move, against the night before it (v0.2.2 WI-8):
	# the card's whole job is to answer "how far did last night shift it", and a
	# dash where the mockup shows a number answered nothing. A robot that has never
	# slept has no answer yet, and that is the dash.
	var last_update := NAN
	if not update.is_empty():
		last_update = float(extra.get("last_update", 0.0))
	cards[2].show_nightly(update, last_update, "grid")
	cards[3].show_series(spent, float(int(extra.get("spent", 0))), "bars", "crossed")


static func _col(row: Array, i: int) -> float:
	return float(row[i]) if i < row.size() else 0.0


func _draw() -> void:
	if actor_id == "":
		Workbench.draw_empty_dash(self)
		return
	draw_rect(CHART_RECT, WELL)
	draw_rect(CHART_RECT, Workbench.EDGE, false, 1.0)

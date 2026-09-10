# workbench_plate.gd — plate 3 of 5: the maker's plate on the side of the machine
#
# **What this page is** (`design/14` §4, ruled whole as Q-101). Every machine in
# the world has a plate riveted to it saying what it is; this is the Mark III's.
# Five engraved lines: how many numbers it looks at, how many things it can
# decide between, how it learns and how fast, how many nights it has had, and how
# undecided it still is this morning.
#
# **The one page on the bench with words on it.** Everywhere else the bench draws
# pictures and numerals (`design/14` §7 — the game's reader is five). A plate is
# the exception because a plate is a thing you read, and because the person who
# most wants this page is the one asking what the model actually *is*.
#
# **Not one word of it is typed.** Every number and every name on the plate is
# read back out of the code's own constants and the robot's own `extra`:
# `Observation.size(spec)` for the input count, `BotBrain.LEARN_ACTIONS` for the
# actions, `weights.size()` for the weights, `BotBrain.LEARN_RATE` for the rate.
# The day someone widens the robot's view or swaps the learner, this page says so
# by itself. A plate that had those numbers written into it would be a lie
# waiting for the first change to the sim, and this is the page a scientist would
# quote.
#
# **The sentence at the bottom.** When a robot spends a whole day deciding to do
# nothing — every decision it made was `wait` — the plate says so in words: *it
# has learned to do nothing*. That is the one failure of this kind of training a
# chart hides rather than shows (a flat score line looks the same as a quiet day),
# so it gets a sentence rather than a number.
#
# Geometry is the mockup's (`docs/design/mockups/workbench/workbench_plate.png`),
# absolute against the fixed 800x600 screen: this page is a full-rect Control, so
# the numbers below are the mockup's own.
extends Control

# --- geometry (F-44) ----------------------------------------------------------
const PLATE_RECT := Rect2(48, 174, 704, 310)
const LABEL_X := 88.0
const VALUE_X := 210.0
const LINE_Y := 240.0        # the baseline of the first line
const LINE_STRIDE := 46.0
const SCREW_INSET := Vector2(20, 12)

const LABEL_SIZE := 13
const VALUE_SIZE := 12
const FALLBACK_SIZE := 11

# The fallback note sits on the body below the plate, not on the brass: it is
# about the training rule the studio would fall back to, not about this machine.
const FALLBACK_RECT := Rect2(48, 508, 704, 48)

# Brass, engraved. The plate face is a gentle vertical gradient between these two
# and the lettering is cut into it, which is why the ink is a darker brass rather
# than the body's pale grey.
const FACE_TOP := Color("efd88a")
const FACE_BOTTOM := Color("c9a94e")
const EDGE := Color("8a6f2c")
const LABEL_INK := Color("463713")
const VALUE_INK := Color("5c4a1b")
const SCREW := Color("8a6f2c")
const SCREW_SLOT := Color("d9c079")

# How many bands the face gradient is painted in. Sixteen is past the point the
# banding is visible at this size and is sixteen rectangles rather than 310.
const FACE_BANDS := 16


## The farm to read through, and the robot to read. `""` means the player owns no
## learning robot, and the page draws its empty state.
var farm: Node2D = null
var actor_id: String = ""

## The engraving, as `[label, value]` pairs in the order they are cut. Five lines
## normally; a sixth with an empty label when the robot has learned to do nothing.
## Built in `show_robot` rather than in `_draw`, so what the page says can be read
## whether or not it happens to be the plate that is showing.
var lines: Array = []

## The smaller note under the plate, naming the rule the night would fall back to
## and whether it is in force. Read from `BotBrain`, so the day a fallback lands
## this line changes with the code.
var fallback: String = ""


func show_robot(farm_node: Node2D, id: String) -> void:
	farm = farm_node
	actor_id = id
	_engrave()
	queue_redraw()


# --- what the plate says ------------------------------------------------------

func _engrave() -> void:
	lines = []
	fallback = "fallback rule if it stalls: %s · %s" % [
		BotBrain.LEARN_FALLBACK,
		"in force" if BotBrain.LEARN_FALLBACK_IN_FORCE else "not in force",
	]
	var extra := _extra()
	if extra.is_empty():
		return

	var spec: Dictionary = extra.get("spec", Observation.spec_default())
	var weights: Array = extra.get("weights", [])
	var n_in: int = Observation.size(spec)

	# **Model.** What kind of thing it is, and its three sizes. The weight count is
	# the one number that makes people flinch, so it is written the way a person
	# writes a thousand rather than as four bare digits.
	lines.append(["Model", "Linear softmax policy · %d inputs -> %d actions · %s weights"
		% [n_in, BotBrain.LEARN_ACTIONS, _thousands(weights.size())]])

	# **Inputs.** The spec's own flags, in the order `Observation` lays the vector
	# out, and the patch as its side length rather than as a radius: "5×5 view" is
	# a thing a person can picture, "vision 2" is not.
	var named: Array = []
	if bool(spec.get("self_pos", true)):
		named.append("position")
	if bool(spec.get("energy", true)):
		named.append("energy")
	if bool(spec.get("carrying", true)):
		named.append("carrying")
	if bool(spec.get("seeds", true)):
		named.append("seeds")
	if bool(spec.get("bin", true)):
		named.append("bin offset")
	var side: int = 2 * maxi(0, int(spec.get("vision", Observation.DEFAULT_VISION))) + 1
	var channels: Array = spec.get("channels", Observation.CHANNELS)
	var inputs := "%d×%d view · %d channels" % [side, side, channels.size()]
	if not named.is_empty():
		inputs = ", ".join(PackedStringArray(named)) + " · " + inputs
	lines.append(["Inputs", inputs])

	# **Training.** The algorithm by its name, said once, plus the one dial the
	# studio turns on it.
	lines.append(["Training",
		"REINFORCE, one episode per day, state-dependent baseline · rate %s"
			% _plain(BotBrain.LEARN_RATE)])

	# **Updated.** When it learns and how often it has. A robot learns at the day
	# turn and at no other moment, which is worth saying on the machine itself:
	# nothing she does during the day changes its mind.
	lines.append(["Updated", "at the day turn · nights practised: %d"
		% int(extra.get("days", 0))])

	# **Exploration.** How undecided it still is, against the most undecided it
	# could possibly be — eight equally likely actions, which is three bits. A
	# number falling toward zero is a robot that has stopped trying things.
	var decisions: int = int(extra.get("decisions", 0))
	var today: float = float(extra.get("entropy_sum", 0.0)) / float(maxi(1, decisions))
	var ceiling: float = log(float(BotBrain.LEARN_ACTIONS)) / log(2.0)
	lines.append(["Exploration", "softmax sampling, seeded · entropy today: %.2f bits of %.2f"
		% [today, ceiling]])

	# **The sentence.** The last closed day, not today: a morning with two `wait`
	# decisions on the board is not a robot that has given up, and the plate must
	# not say it is. `ledger` rows are `[score, expected, entropy, update, spent,
	# decisions, waits]` (v0.2.2 WI-1).
	var ledger: Array = extra.get("ledger", [])
	if not ledger.is_empty():
		var last: Array = ledger[ledger.size() - 1]
		if last.size() >= 7:
			var made: int = int(last[5])
			var waited: int = int(last[6])
			if made > 0 and waited == made:
				lines.append(["", "it has learned to do nothing"])


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


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if actor_id == "" or lines.is_empty():
		Workbench.draw_empty_dash(self)
		return

	_draw_face()

	var label_font := _font(true)
	var value_font := _font(false)
	if label_font == null or value_font == null:
		return

	for i in lines.size():
		var y := LINE_Y + LINE_STRIDE * float(i)
		var label := String(lines[i][0])
		var value := String(lines[i][1])
		if label == "":
			# The sentence, which has no label and starts where the labels do —
			# it is a remark about the whole plate rather than another field.
			draw_string(label_font, Vector2(LABEL_X, y), value,
				HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_INK)
			continue
		draw_string(label_font, Vector2(LABEL_X, y), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_INK)
		draw_string(value_font, Vector2(VALUE_X, y), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_SIZE, VALUE_INK)

	# The fallback note, wrapped to the body's width. It is dim and small on
	# purpose: it is true of every learning robot in the game, not of this one.
	draw_multiline_string(value_font, FALLBACK_RECT.position, fallback,
		HORIZONTAL_ALIGNMENT_LEFT, FALLBACK_RECT.size.x, FALLBACK_SIZE, 3,
		Workbench.INK_DIM)


# The brass itself: a banded gradient, a darker rim, and four screws. The screws
# are the whole reason this reads as a plate bolted to a machine rather than as a
# yellow rectangle, and they cost four circles.
func _draw_face() -> void:
	var band_h := PLATE_RECT.size.y / float(FACE_BANDS)
	for b in FACE_BANDS:
		var t := float(b) / float(FACE_BANDS - 1)
		draw_rect(Rect2(PLATE_RECT.position.x, PLATE_RECT.position.y + band_h * float(b),
			PLATE_RECT.size.x, band_h + 1.0), FACE_TOP.lerp(FACE_BOTTOM, t))
	draw_rect(PLATE_RECT, EDGE, false, 2.0)
	for corner in [
		PLATE_RECT.position + SCREW_INSET,
		Vector2(PLATE_RECT.end.x - SCREW_INSET.x, PLATE_RECT.position.y + SCREW_INSET.y),
		Vector2(PLATE_RECT.position.x + SCREW_INSET.x, PLATE_RECT.end.y - SCREW_INSET.y),
		PLATE_RECT.end - SCREW_INSET,
	]:
		draw_circle(corner, 5.0, SCREW)
		draw_line(corner - Vector2(3, 0), corner + Vector2(3, 0), SCREW_SLOT, 1.5)


# The game has one face and no theme file (F-42), so "bold" is that face leaned
# on rather than a second font nobody shipped. `FontVariation` does it on the
# bundled font, which means it cannot go missing on a platform the way a
# hand-picked codepoint can.
func _font(bold: bool) -> Font:
	var base := get_theme_font("font", "Label")
	if base == null:
		base = ThemeDB.fallback_font
	if base == null or not bold:
		return base
	var thick := FontVariation.new()
	thick.base_font = base
	thick.variation_embolden = 0.35
	return thick


# --- numbers, written the way a person writes them ----------------------------

# 1664 -> "1,664". The plate's one concession to prose: the weight count is a
# number people quote out loud, and four unbroken digits are read as a code.
static func _thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	var seen := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		seen += 1
		if seen % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# A rate as a person would write it: 0.03, not 0.030000. Four places is past
# anything the ladder of learning rates has ever wanted and the zeros come off.
static func _plain(value: float) -> String:
	var text := "%.4f" % value
	if text.contains("."):
		while text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
	return text

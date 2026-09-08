# look_lab.gd — one door for every look that is still the designer's to pick.
#
# T-27 box 5 shipped a switch for one question ("what does a cot look like before
# you have ever slept in it?") behind a pause-menu line that advances and closes,
# so the farm is what you are looking at when it changes. That shape works — it
# is Q-31's Sound Test precedent, and the cot's pick was made on a tablet with a
# thumb — and three more questions of exactly the same kind followed it.
#
# So the switch generalised rather than being copied. **A second rig would have
# been the mistake**: two pause lines, two sets of statics to remember to
# restore, and a designer holding a tablet wondering which menu the thing he
# wants is under. This is one registry of *axes*; each axis is an open question
# with N drafts, and each is judged independently, because two problems that
# arrive together are usually different failures and a build that only offers
# fixed combinations cannot tell you which half worked.
#
# **All four questions it has carried are now answered, so `AXES` is empty**
# (2026-09-08, at the designer's request: *"clean up the debug menu options for
# the other things, if they are no longer needed"*). The cot's look, the two
# station axes and the ripe crop were each ruled from staged captures, and a
# switch between candidates that no longer exist is furniture. The pause menu
# therefore carries no look lines at all, which is the honest picture of a studio
# with no open look question.
#
# **The rig is kept, not deleted.** It is Q-86's answer to "how do we ask the
# designer a look question", and four decisions were made from it. Opening the
# next one costs an entry here, one in `tools/look_scenarios.gd`, and one arm of
# `tools/capture_looks.gd`'s staging — the three lines the ripe crop cost. An
# empty registry is this file at rest, not this file retired.
#
# Layer note: pure static over other pure statics. No Node, no autoload, no sim.
class_name LookLab

# One entry per **open** question. Empty is a legitimate and expected state.
const AXES: Array[String] = []

# Short enough to fit a pause-menu line beside its current value; keyed by axis.
const LABELS := {}

# What each axis is asking. Developer text, debug builds only — S-7 is about the
# game, and none of this is in it.
const QUESTIONS := {}

# Which axis the last `cycle()` moved, so a toast can name it. Empty means the
# last press was the put-back rather than a single axis.
static var last_axis: String = ""


# --- The five questions an axis has to answer --------------------------------
#
# Each of these was a `match` over the registered axes, dispatching to the
# treatment file that owns one. With nothing registered they answer for the empty
# set, and the shape is left standing because that is what the next question
# fills in: one arm each, pointing at its own presentation file, which is where
# the numbers and the reasoning belong.

## How many drafts this axis is choosing between.
static func count_of(_axis: String) -> int:
	return 0


## Which draft it is currently wearing.
static func current(_axis: String) -> int:
	return 0


## What the game ships wearing on this axis — the ruled pick. Named beside the
## treatment it selects, never restated here, so it cannot drift from what the
## game actually starts as.
static func shipped(_axis: String) -> int:
	return 0


static func set_to(axis: String, _value: int) -> int:
	last_axis = axis
	return 0


static func name_of(_axis: String, _value: int) -> String:
	return ""


static func blurb_of(_axis: String, _value: int) -> String:
	return ""


static func cycle(axis: String) -> int:
	return set_to(axis, current(axis) + 1)


static func label_of(axis: String) -> String:
	return String(LABELS.get(axis, axis))


# --- Is this farm dressed the way the game ships? -----------------------------
#
# **Why this exists** (2026-09-08, from the designer at the tablet). He opened the
# pause menu, met lines he did not recognise, and read back two axes that were
# not on their picks — because a look line advances on a tap and then closes the
# menu, which is exactly what makes it good for comparing and exactly what makes
# it easy to nudge in passing. A switch that changes the game silently and then
# says nothing is a trap: everything played and reported afterwards is a report
# about a build nobody ships.
#
# Kept with the empty registry rather than deleted with the axes, because the
# trap is a property of the *mechanism* and will be back the moment an axis is.

static func is_shipped(axis: String) -> bool:
	return current(axis) == shipped(axis)


static func changed_axes() -> Array[String]:
	var out: Array[String] = []
	for axis in AXES:
		if not is_shipped(axis):
			out.append(axis)
	return out


## Everything back to the picks. One press, for the same reason the teaching
## mode's clear-all is one press: undoing four taps one at a time is arithmetic
## an interface should absorb.
static func restore_all() -> void:
	for axis in AXES:
		set_to(axis, shipped(axis))
	# `set_to` has been naming each axis in turn; none of them is what just
	# happened, so the toast speaks for the whole set instead of for whichever
	# one went last.
	last_axis = ""


## "Cot look: A · dusk glow" — one pause-menu line, naming the axis and where it
## currently stands, so the menu itself is the readout. A line that is off its
## shipped pick says what the pick is.
static func option_label(axis: String) -> String:
	var line := "%s: %s" % [label_of(axis), name_of(axis, current(axis))]
	if is_shipped(axis):
		return line
	return "%s  (ships as %s)" % [line, name_of(axis, shipped(axis))]


## The line under them all, naming how many looks are off their pick.
static func restore_label() -> String:
	var n := changed_axes().size()
	if n == 0:
		return "Every look is as it ships"
	return "Put %d look%s back to what ships" % [n, "" if n == 1 else "s"]


## What the last press did, in one line, for the toast the tablet shows. Here
## rather than in `main.gd` because only this file knows whether a press moved
## one axis or put the whole set back.
static func last_change_text() -> String:
	if last_axis == "":
		return "Every look back to what ships"
	return "%s: %s" % [label_of(last_axis), name_of(last_axis, current(last_axis))]


## Everything the game is currently wearing, for a trace line or a toast.
static func summary() -> String:
	var parts: PackedStringArray = []
	for axis in AXES:
		parts.append("%s=%d" % [axis, current(axis)])
	return " ".join(parts)

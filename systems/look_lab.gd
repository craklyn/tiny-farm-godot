# look_lab.gd — one door for every look that is still the designer's to pick.
#
# T-27 box 5 shipped a switch for one question ("what does a cot look like before
# you have ever slept in it?") behind two doors: a title-screen panel beside the
# Sound Test, and a pause-menu line that advances and closes so the farm is what
# you are looking at when it changes. That shape works — it is Q-31's Sound Test
# precedent, and the cot's pick was made on a tablet with a thumb — and T-28
# arrives with two more questions of exactly the same kind.
#
# So the switch generalises rather than being copied. **A second rig would have
# been the mistake**: two panels, two pause lines, two sets of statics to
# remember to restore, and a designer holding a tablet wondering which menu the
# thing he wants is under. This is one registry of *axes*; each axis is an open
# question with N drafts, and each is judged independently, because T-28's two
# problems are different failures and a build that only offers fixed
# combinations cannot tell you which half worked.
#
# It is a lookup table with a `match` in it, deliberately: GDScript has no clean
# way to put setters in a const table, and a nine-line match that the whole game
# reads through is better than a plugin system for three entries. Adding a
# fourth axis is this file plus nothing — and the fourth arrived on 2026-09-07
# ("how does a ripe crop carry across a whole plot?"), costing exactly that: six
# lines here, and the pause menu and the capture rig picked it up on their own.
#
# Layer note: pure static over other pure statics. No Node, no autoload, no sim.
class_name LookLab

const COT := "cot"
const DISCOVERY := "discovery"
const SATISFIED := "satisfied"
const RIPE := "ripe"

const AXES: Array[String] = [COT, DISCOVERY, SATISFIED, RIPE]

# Short enough to fit a pause-menu line beside its current value.
const LABELS := {
	COT: "Cot look",
	DISCOVERY: "Stations seen",
	SATISFIED: "Already done",
	RIPE: "Ripe crops",
}

# The question each axis is asking, for the title screen's panel. Developer text,
# debug builds only — S-7 is about the game, and none of this is in it.
const QUESTIONS := {
	COT: "What does a bed look like before you have slept in it? (T-27)",
	DISCOVERY: "How does a station say what it is for, first time? (T-28)",
	SATISFIED: "How does \"already done\" say what is already done? (T-28)",
	RIPE: "How does a ripe crop carry across a whole plot? (v0.2.0, from play)",
}

# Which axis the last `cycle()` moved, so a toast can name it.
static var last_axis: String = COT


# **What the game ships wearing on each axis** — the ruled picks, and OFF for a
# question still open. Every one of these lives beside the treatment it names, so
# this cannot drift from what the game actually starts as.
static func shipped(axis: String) -> int:
	match axis:
		COT:
			return CotPresentation.SHIPPED
		DISCOVERY:
			return StationPresentation.DISCOVERY_SHIPPED
		SATISFIED:
			return StationPresentation.SATISFIED_SHIPPED
		RIPE:
			return CropPresentation.SHIPPED
	return 0


## Is this farm dressed the way the game ships?
##
## **Why this exists** (2026-09-08, from the designer at the tablet). He opened
## the pause menu, met three lines he did not recognise, and read back values
## that were not the shipped ones — because a look line advances on a tap and
## then closes the menu, which is exactly what makes it good for comparing and
## exactly what makes it easy to nudge in passing. A switch that changes the game
## silently and then says nothing is a trap: everything he plays and reports
## afterwards is a report about a build nobody ships. So the menu now says which
## lines are off their pick, and offers one press to put them all back.
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
	# happened, so the toast is told to speak for the whole set instead of for
	# whichever one went last.
	last_axis = ""


static func count_of(axis: String) -> int:
	match axis:
		COT:
			return CotPresentation.COUNT
		DISCOVERY:
			return StationPresentation.DISCOVERY_COUNT
		SATISFIED:
			return StationPresentation.SATISFIED_COUNT
		RIPE:
			return CropPresentation.COUNT
	return 0


static func current(axis: String) -> int:
	match axis:
		COT:
			return CotPresentation.treatment
		DISCOVERY:
			return StationPresentation.discovery
		SATISFIED:
			return StationPresentation.satisfied
		RIPE:
			return CropPresentation.treatment
	return 0


static func set_to(axis: String, value: int) -> int:
	last_axis = axis
	match axis:
		COT:
			return CotPresentation.set_treatment(value)
		DISCOVERY:
			return StationPresentation.set_discovery(value)
		SATISFIED:
			return StationPresentation.set_satisfied(value)
		RIPE:
			return CropPresentation.set_treatment(value)
	return 0


static func cycle(axis: String) -> int:
	return set_to(axis, current(axis) + 1)


static func name_of(axis: String, value: int) -> String:
	match axis:
		COT:
			return CotPresentation.name_of(value)
		DISCOVERY:
			return StationPresentation.discovery_name(value)
		SATISFIED:
			return StationPresentation.satisfied_name(value)
		RIPE:
			return CropPresentation.name_of(value)
	return ""


static func blurb_of(axis: String, value: int) -> String:
	match axis:
		COT:
			return CotPresentation.blurb_of(value)
		DISCOVERY:
			return StationPresentation.discovery_blurb(value)
		SATISFIED:
			return StationPresentation.satisfied_blurb(value)
		RIPE:
			return CropPresentation.blurb_of(value)
	return ""


static func label_of(axis: String) -> String:
	return String(LABELS.get(axis, axis))


## "Cot look: A · dusk glow" — one pause-menu line, naming the axis and where it
## currently stands, so the menu itself is the readout.
##
## A line that is off its shipped pick says so, and says what the pick is. That
## trailing clause is the whole of the fix described at `is_shipped`: the reason
## he could not tell his farm was wearing two non-shipping looks is that the line
## reporting them looked exactly like the two that were fine.
static func option_label(axis: String) -> String:
	var line := "%s: %s" % [label_of(axis), name_of(axis, current(axis))]
	if is_shipped(axis):
		return line
	return "%s  (ships as %s)" % [line, name_of(axis, shipped(axis))]


## The line under them all. Names how many looks are off their pick, so the
## count is on screen rather than something he has to work out by reading four
## lines against a memory of what they should say.
static func restore_label() -> String:
	var n := changed_axes().size()
	if n == 0:
		return "Every look is as it ships"
	return "Put %d look%s back to what ships" % [n, "" if n == 1 else "s"]


## What the last press did, in one line, for the toast the tablet shows. It is
## here rather than in `main.gd` because only this file knows whether a press
## moved one axis or put the whole set back.
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

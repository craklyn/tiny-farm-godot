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
# fourth axis is this file plus nothing.
#
# Layer note: pure static over other pure statics. No Node, no autoload, no sim.
class_name LookLab

const COT := "cot"
const DISCOVERY := "discovery"
const SATISFIED := "satisfied"

const AXES: Array[String] = [COT, DISCOVERY, SATISFIED]

# Short enough to fit a pause-menu line beside its current value.
const LABELS := {
	COT: "Cot look",
	DISCOVERY: "Stations seen",
	SATISFIED: "Already done",
}

# The question each axis is asking, for the title screen's panel. Developer text,
# debug builds only — S-7 is about the game, and none of this is in it.
const QUESTIONS := {
	COT: "What does a bed look like before you have slept in it? (T-27)",
	DISCOVERY: "How does a station say what it is for, first time? (T-28)",
	SATISFIED: "How does \"already done\" say what is already done? (T-28)",
}

# Which axis the last `cycle()` moved, so a toast can name it.
static var last_axis: String = COT


static func count_of(axis: String) -> int:
	match axis:
		COT:
			return CotPresentation.COUNT
		DISCOVERY:
			return StationPresentation.DISCOVERY_COUNT
		SATISFIED:
			return StationPresentation.SATISFIED_COUNT
	return 0


static func current(axis: String) -> int:
	match axis:
		COT:
			return CotPresentation.treatment
		DISCOVERY:
			return StationPresentation.discovery
		SATISFIED:
			return StationPresentation.satisfied
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
	return ""


static func blurb_of(axis: String, value: int) -> String:
	match axis:
		COT:
			return CotPresentation.blurb_of(value)
		DISCOVERY:
			return StationPresentation.discovery_blurb(value)
		SATISFIED:
			return StationPresentation.satisfied_blurb(value)
	return ""


static func label_of(axis: String) -> String:
	return String(LABELS.get(axis, axis))


## "Cot look: A · dusk glow" — one pause-menu line, naming the axis and where it
## currently stands, so the menu itself is the readout.
static func option_label(axis: String) -> String:
	return "%s: %s" % [label_of(axis), name_of(axis, current(axis))]


## Everything the game is currently wearing, for a trace line or a toast.
static func summary() -> String:
	var parts: PackedStringArray = []
	for axis in AXES:
		parts.append("%s=%d" % [axis, current(axis)])
	return " ".join(parts)

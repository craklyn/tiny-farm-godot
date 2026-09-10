# rewards.gd — What the farm is worth teaching, one row per outcome
# (v0.2.1 plan WI-9a; P-14's first rule, "reward on outcomes"; the table is Q-100)
#
# Layer 1 (data): plain definitions, no logic beyond a lookup. It sits beside
# `crops/crop_defs.gd` and `systems/tools.gd` for the same reason they do — a
# number the design argues about belongs somewhere a designer can find it, not
# buried in the brain that happens to read it.
#
# **The reward is on outcomes, never on actions** (P-14). A robot is not paid for
# emitting `water`; it is paid when a tile that needed water came out wet. That
# distinction is the whole of why the table is keyed by what happened —
# `"watered_plant"` — rather than by a verb. A robot that learned to spray wet
# ground would be a robot that had been paid for the gesture.
#
# **The whole farm, not one job** (Q-100, ruled 2026-09-09). The first draft of
# the Mark III paid for watering and nothing else. The designer widened it the
# same day — *"the robot should be rewarded for doing beneficial things"* — and
# listed them: a crop in the mailbox, a bird chased off, a crop cut, a plant
# watered, a seed sown, ground opened, dry soil wetted. So what is deliberately
# weak in v1 (P-13) is the *learner*, not the breadth of what it may earn.
#
# The numbers say what the farm is for. Ten for a crop that reached the bin,
# because that is the one row where the farm ends up better off in gold, and
# everything leading to it — the hoeing, the sowing, the watering, the cutting —
# is a step towards one. Three for a crow caught eating and one for a crow turned
# back before it lands, because the first is a crop saved and the second is a
# crop that was never in danger. A tenth for tilling and for watering empty soil,
# because those leave the farm one step better *placed* rather than one thing
# better off — worth a little, and not enough that a robot which only ever hoed
# would score well.
#
# **Nobody owns a tile** (Q-100). A thirsty plant she sowed and one the robot
# sowed pay exactly the same. An earlier build kept two watering rows so that the
# question "should her squares be worth more than its own?" could be answered
# here; the designer answered it, and the second row is gone.
class_name Rewards
extends RefCounted


# The eight outcomes a Mark III is paid for (Q-100). Every key is something that
# *happened to the farm*, and the brain looks one up only after the gateway has
# said yes — see `systems/sim/brains/bot_brain.gd`.
const TABLE := {
	# A crop it carried reached the shipping bin and sold. The day's big one.
	"shipped": 10.0,
	# A crow it reached gave up and left. Two rows, because a bird still circling
	# has taken nothing yet and a bird on the ground is mid-meal.
	"crow_flying": 1.0,
	"crow_eating": 3.0,
	# A ripe tile cut, the crop now in the machine's hands.
	"harvested": 1.0,
	# Water onto a square that was dry and had something growing in it.
	"watered_plant": 1.0,
	# A seed out of her box and into open soil.
	"planted": 1.0,
	# Bare (`cleared`) ground opened into soil.
	"tilled": 0.1,
	# Water onto dry tilled soil with nothing in it yet.
	"watered_soil": 0.1,
}


# The same eight, in a fixed order, so a day's score can be split by what earned
# it and the columns mean the same thing every run (v0.2.1 WI-9b).
#
# **A written-out list rather than `TABLE.keys()`**, for the reason the brain's
# action list is written out: this order is a position in an array that rides in
# an actor's `extra`, goes through JSON on every save and is compared by
# `capture_canonical`. A dictionary's key order is an implementation detail of the
# engine; a robot's day should not be.
const KEYS := ["shipped", "crow_flying", "crow_eating", "harvested",
	"watered_plant", "planted", "tilled", "watered_soil"]


# What an outcome is worth. **An outcome nobody has priced is worth nothing** —
# zero rather than an error, because "that did not earn anything" is the ordinary
# answer for almost everything a robot does in a day, walking and waiting
# included.
static func of(outcome: String) -> float:
	return float(TABLE.get(outcome, 0.0))


# Which column of a day's split this outcome is, or -1 for one nobody has priced.
static func index_of(outcome: String) -> int:
	return KEYS.find(outcome)


# --- the dials (v0.2.2, the training workbench; Q-101) --------------------------

# **The only reward values that exist.** Ten steps, ascending, and a row of the
# table above is always sitting on one of them — which is what makes a dial a
# dial rather than a number field: there is no `2.7`, so there is no way to type
# one, and every robot in every save can be drawn on the same ten-cell strip.
#
# It is a ladder rather than a slider because the interesting differences between
# rewards are ratios, not increments: the gap that matters between "worth a
# little" and "worth the day" is 0.1 against 10, and a linear control would spend
# nine tenths of its travel in a range nobody wants. Negative entries because a
# designer must be able to say *stop doing that*, and zero because she must be
# able to say *this is not worth anything* without deleting the row.
const LADDER := [-3.0, -1.0, -0.3, -0.1, 0.0, 0.1, 0.3, 1.0, 3.0, 10.0]


# The table above as a plain array in `KEYS` order — the eight numbers a robot is
# born with, and the ones a long press on a dial puts back.
#
# **A fresh array every call**, for the reason `Observation.spec_default` returns
# one: the caller puts this straight into an actor's `extra`, and a shared array
# there would be one robot's dials wired to every other robot's.
static func factory() -> Array:
	var out: Array = []
	for key in KEYS:
		out.append(float(TABLE.get(key, 0.0)))
	return out


# Which rung a value is standing on, or -1 for a value that is not on the ladder.
#
# **Within 1e-9 rather than exactly**, because the number arriving here has been
# through JSON at least once — a replayed `tune` carries its value as text — and
# a float that survived that round trip is equal to the rung it came from for
# every practical purpose and occasionally not for `==`.
static func ladder_index(value: float) -> int:
	for i in LADDER.size():
		if absf(float(LADDER[i]) - value) < 1e-9:
			return i
	return -1


# One rung up (`direction` 1) or down (-1), clamping at the ends: a dial at the
# top of the ladder that is pushed up stays where it is, which is what the
# workbench's disabled buttons show. A value that is not on the ladder at all —
# a robot from a save written by a build that priced a row differently — is read
# as the nearest rung and stepped from there, so a dial is never stuck.
static func stepped(value: float, direction: int) -> float:
	var at := ladder_index(value)
	if at < 0:
		var best := 0
		var best_gap := INF
		for i in LADDER.size():
			var gap := absf(float(LADDER[i]) - value)
			if gap < best_gap:
				best_gap = gap
				best = i
		at = best
	return float(LADDER[clampi(at + direction, 0, LADDER.size() - 1)])

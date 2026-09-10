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


# What an outcome is worth. **An outcome nobody has priced is worth nothing** —
# zero rather than an error, because "that did not earn anything" is the ordinary
# answer for almost everything a robot does in a day, walking and waiting
# included.
static func of(outcome: String) -> float:
	return float(TABLE.get(outcome, 0.0))

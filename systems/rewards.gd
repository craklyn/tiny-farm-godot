# rewards.gd — What the farm is worth teaching, one row per outcome
# (v0.2.1 plan WI-2; P-14's first rule, "reward on outcomes"; the v1 value is Q-96)
#
# Layer 1 (data): plain definitions, no logic beyond a lookup. It sits beside
# `crops/crop_defs.gd` and `systems/tools.gd` for the same reason they do — a
# number the design argues about belongs somewhere a designer can find it, not
# buried in the brain that happens to read it.
#
# **The reward is on outcomes, never on actions** (P-14). A robot is not paid for
# emitting `water`; it is paid when a tile that needed water came out wet. That
# distinction is the whole of why the table is keyed by what happened —
# `"wet_tile"` — rather than by a verb. A robot that learned to spray wet ground
# would be a robot that had been paid for the gesture.
#
# **One row, on purpose** (P-13: v1 is deliberately weak). The Mark III has one
# job. Every later outcome the ladder adds — a crop harvested, a bird chased off,
# a round finished before dusk — is one more row here and no change at all to the
# policy maths or to the brain that spends it.
class_name Rewards
extends RefCounted


# The v1 table (Q-96): +1 when a robot's `water` turned a tile that needed water
# into a wet one. [Playtest]
const TABLE := {
	"wet_tile": 1.0,
}


# What an outcome is worth. **An outcome nobody has priced is worth nothing** —
# zero rather than an error, because "that did not earn anything" is the ordinary
# answer for almost everything a robot does in a day, and the six actions of v1
# include waiting and walking into a fence.
static func of(outcome: String) -> float:
	return float(TABLE.get(outcome, 0.0))

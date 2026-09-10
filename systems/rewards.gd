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
# **Two rows, and the second one is a tenth of the first** (Q-99). The Mark III
# still has one job; the hoe is not a second job but a way of making the first one
# findable. A robot out of the box picks a direction at random, so on open ground
# it will wander off the crop long before it stumbles into watering something
# thirsty — and a week in which nothing is ever earned teaches nothing at all.
# Turning bare earth into tilled soil is worth a little because it is worth a
# little: it leaves behind a square that *wants water*, so a lucky hoe makes the
# ground under the robot's own feet into the next thing worth doing. The tenth is
# what keeps it a stepping stone rather than the job — twenty hoeings are worth
# two waterings, so a robot that only ever hoed would score badly.
#
# Every later outcome the ladder adds — a crop harvested, a bird chased off, a
# round finished before dusk — is one more row here and no change at all to the
# policy maths or to the brain that spends it.
class_name Rewards
extends RefCounted


# The v1 table: +1 when a robot's `water` turned a tile that needed water into a
# wet one (Q-96), and +0.1 when its `till` turned bare ground into soil (Q-99).
#
# **The two watering rows hold the same number, and that is the shipped design.**
# A thirsty square is a thirsty square: the machine is paid the same for her sown
# wheat and for the bare soil it opened for itself, exactly as Q-96 wrote it.
# They are two rows because the measured behaviour of the first mark-3 is that it
# waters almost nothing but its own practice ground (v0.2.1 §9), and the question
# that follows — *should her squares be worth more than its own?* — is answered
# by a number in this file and by nothing else. Splitting the row is what makes
# that answer sayable; `tools/demo_learning_robot.gd --split-sweep` measures what
# each answer would do. Until the designer rules, both are 1.0 and the robot
# cannot tell the difference.
const TABLE := {
	# A square that was carrying a crop or a seed — hers.
	"wet_tile": 1.0,
	# Bare tilled soil with nothing in it — the robot's own, in practice, since
	# the only bare soil on an open farm is soil it hoed itself.
	"wet_tile_empty": 1.0,
	# Q-99, the CEO on a robot that walked off the field before it earned
	# anything: "not a pen, a denser reward". [Playtest]
	"tilled_tile": 0.1,
}


# **An experiment's table, empty in every game ever played.** A sweep that wants
# to know what a different price would teach has to change the price before the
# week starts and put it back afterwards, and `TABLE` is a constant — read-only
# down to its values, which is what keeps a shipped reward from being edited by
# something that ran earlier. So an experiment writes here instead, and the
# emptiness of this dictionary is the guarantee that a measurement cannot leak
# into a save, a replay or a suite: `tools/demo_learning_robot.gd` is the only
# caller, it sets one key, and it clears it in the same function.
static var overrides: Dictionary = {}


# What an outcome is worth. **An outcome nobody has priced is worth nothing** —
# zero rather than an error, because "that did not earn anything" is the ordinary
# answer for almost everything a robot does in a day, and the seven actions of v1
# include waiting and walking into a fence.
static func of(outcome: String) -> float:
	if overrides.has(outcome):
		return float(overrides[outcome])
	return float(TABLE.get(outcome, 0.0))

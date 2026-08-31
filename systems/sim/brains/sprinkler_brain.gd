# sprinkler_brain.gd — The first machine (design/03, M2.5 WI-10)
#
# Layer 2 (pure). **"A sprinkler waters; it does nothing the watering can
# couldn't"** (`design/03`, principles). That sentence is the entire design and
# it is also the entire implementation: this brain emits the `water` verb the
# player already owns, at tiles around itself, through the one gateway — so a
# machine is measured against ground rule 1 the same way a bot is, and the work
# item that added the first machine to the game added no new verb, no new
# mutation and no new path through `apply_action`.
#
# **It thinks once a morning, and is otherwise inert.** `on_clock()` is false: a
# sprinkler holds no pending event, costs the clock nothing between days, and
# cannot be woken by anything (ground rule 8 — a machine is not a heartbeat).
# Its one moment is `day_actions()`, which `SimWorld.advance_day` runs at the end
# of the day turn, after the growth pass has cleared yesterday's water. That
# ordering is what "the tiles in its radius **wake** watered" means: the sprinkler
# waters the morning it is turning into, exactly as rain does, so a crop under it
# grows the following night without anybody having carried a can.
#
# **Recomputed, never recorded** (Q-53): the day turn is one `sleep` entry in the
# log, and a replay re-applies it, and this runs again inside it. A machine that
# recorded a verb per tile would put nine entries a day into what is also phase
# 4's training corpus, describing a decision nobody made.
#
# What this deliberately does not do: **upkeep** (plan §4 defers it to M3 design —
# `design/03` §4 has not chosen between "machines break and need refills" and
# "machines run free"), **water source coupling** (§3: pipes? well proximity?),
# and **acquisition** (Q-15). Nothing places a sprinkler; one exists only where a
# test or a future M3 system calls `spawn_actor`.
class_name SprinklerBrain
extends Brain

# [Playtest] — the 3x3 the machine stands in the middle of. Small on purpose:
# design/03 §3 ("sprinkler radius on the grid; overlap rules") is unwritten, and
# the reason a sprinkler is a reward at all is that it retires a chore the player
# felt, not that it retires the farm. A square rather than a diamond because it
# is the shape the scarecrow's radius already uses in this codebase, and one
# coverage shape is easier to teach than two.
#
# `extra["radius"]` overrides it per actor — the `body_len` pattern from the
# movement engine (WI-4 deviation 7), so an M3 upgrade tier is one integer rather
# than a species row per size.
const RADIUS := 1


# It never thinks on the tick clock. Its whole life is the day turn.
func on_clock() -> bool:
	return false


# The tiles it sprays, as ordinary `water` Actions in a fixed order (rows then
# columns, so two runs of the same farm water in the same sequence). Tiles off the
# map are skipped rather than attempted; everything else is offered to the
# gateway, which decides what water does to it — soil takes it, and a rock does
# not, which is the same answer the player gets when she waters a rock.
func day_actions(world: SimWorld, actor_id: String, _gs = null) -> Array[Dictionary]:
	return actions_for(world, actor_id)


static func actions_for(world: SimWorld, actor_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := world.actor_pos(actor_id)
	if at.x < 0:
		return out
	var radius: int = maxi(0, int(world.actor(actor_id)["extra"].get("radius", RADIUS)))
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t := at + Vector2i(dx, dy)
			if world.get_tile(t.x, t.y).is_empty():
				continue
			out.append({ "verb": "water", "target": t, "actor": actor_id })
	return out


# The tiles it covers, for a test, a future overlay and whatever M3 builds to let
# the player see coverage before she places one. Derived from `day_actions` rather
# than computed beside it, so a readout can never disagree with what the machine
# actually does — `SimWorld.tool_proof_progress`'s pattern.
static func coverage(world: SimWorld, actor_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for action in actions_for(world, actor_id):
		out.append(action["target"])
	return out

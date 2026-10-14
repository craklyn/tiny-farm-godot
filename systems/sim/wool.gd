# wool.gd — a sheep's coat, and what it does to her walk (docs/design/18-sheep.md)
#
# Layer 2 (pure): rules over a `SimWorld`, no state of its own. The coat itself is
# `extra["coat"]` on the sheep, a whole number from SHEARED to EXTREME, written only
# by the gateway (`buy_sheep` sets it, `grow_wool` adds one a night). Nothing takes
# it away: there are no shears yet, on purpose (Daniel, 2026-10-13: "a monkey's paw
# version of game development where we leave part of the feature missing").
#
# What the coat does is decided here, in the sim, so a replay and the screen agree:
#
#   * **Extra full** (Daniel: "their walk slows to 25% speed through doors and narrow
#     (single width) passages ... and accelerates back to 100% after clearing a bit
#     from those spaces"). `step_ticks` is how long each step takes. A step into or
#     out of a tight square takes four times as long; the steps after it speed up
#     over `RAMP` until she is at her own pace again.
#   * **Extreme** ("the sheep literally becomes unable to take another step because
#     they've become too fluffy"). Her brain stops her on the first square where she
#     may settle (`may_settle`): anywhere but a doorway, a doorstep or a one-square
#     gap, so she finishes squeezing through first. She stays there, content.
class_name Wool
extends RefCounted

# The five coats, in the order they grow (Daniel's names, 2026-10-13).
const SHEARED := 0
const MID_GROWTH := 1
const FULL := 2
const EXTRA_FULL := 3
const EXTREME := 4
const NAMES: Array[String] = ["freshly sheared", "mid-growth", "full coat", "extra full coat", "extreme coat"]

# [Tunable] The coat a bought sheep arrives in. Mid-growth, so her first night gives
# her a full coat, her second an extra full one, and her third the extreme one.
const BOUGHT_COAT := MID_GROWTH
# [Tunable] Coat stages a night. One, at the sleep that turns the day, as cow milk is.
const GROWTH_PER_NIGHT := 1
# [Tunable] Her pace in a tight square, as a share of her own (Daniel: 25%).
const TIGHT_PACE := 0.25
# [Tunable] Her pace on the squares after a tight one, one entry a square, until she
# is back to her own: half, then three quarters, then full.
const RAMP: Array[float] = [0.5, 0.75]


static func coat_of(world: SimWorld, actor_id: String) -> int:
	return clampi(int(world.actor(actor_id).get("extra", {}).get("coat", SHEARED)), SHEARED, EXTREME)


static func slows(coat: int) -> bool:
	return coat >= EXTRA_FULL


static func is_stuck_coat(coat: int) -> bool:
	return coat >= EXTREME


# **A tight square**: a doorway or a doorstep of any room, or a one-square gap — a
# square she may cross whose two neighbours on one axis she may not (her route's
# own rules, so a gap between beds is a gap to her as well as one between rocks).
# Four neighbour lookups and a short loop over the rooms: no scan.
static func is_tight(world: SimWorld, cell: Vector2i, mode: String) -> bool:
	for id in world.rooms:
		var room: Dictionary = world.rooms[id]
		if Vector2i(room.get("door", Vector2i(-1, -1))) == cell:
			return true
		if world.room_exit_for(room) == cell:
			return true
	if not Movement.passable(world, mode, cell):
		return false
	var w := Movement.passable(world, mode, cell + Vector2i(-1, 0))
	var e := Movement.passable(world, mode, cell + Vector2i(1, 0))
	var n := Movement.passable(world, mode, cell + Vector2i(0, -1))
	var s := Movement.passable(world, mode, cell + Vector2i(0, 1))
	return (not w and not e) or (not n and not s)


# Where an extreme-coat sheep may stop for good: ground her own walk may cross (never
# a crop bed: no animal stands on one, 2026-10-11) that is not a tight square —
# except her own stall, which she may keep for ever (a sheep that freezes in a stall
# keeps it, and Daniel's brief says that is fine and funny).
static func may_settle(world: SimWorld, actor_id: String, cell: Vector2i) -> bool:
	if in_own_stall(world, actor_id, cell):
		return true
	var mode := Movement.route_mode_of(world.species_of(actor_id))
	return Movement.passable(world, mode, cell) and not is_tight(world, cell, mode)


static func in_own_stall(world: SimWorld, actor_id: String, cell: Vector2i) -> bool:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	var barn_id := String(extra.get("barn_id", ""))
	var index := int(extra.get("stall_index", -1))
	if not world.barns.has(barn_id) or index < 0 or index >= world.barns[barn_id]["stalls"].size():
		return false
	var stall_cell: Array = world.barns[barn_id]["stalls"][index].get("cell", [])
	return stall_cell.size() == 2 and Vector2i(int(stall_cell[0]), int(stall_cell[1])) == cell


# How many ticks the step she has just taken from `from` to `to` lasts, and so when
# she may take the next. Called by `Movement.step` for a species whose row sets
# `coat_pace`, once a step. Writes two numbers into her `extra`, both movement
# state like her route: `clear_steps`, the steps since her last tight one, and
# `step_ticks`, this step's length, which is what the picture of her walk reads.
static func step_ticks(world: SimWorld, actor_id: String, from: Vector2i, to: Vector2i) -> int:
	var species := world.species_of(actor_id)
	var base := Movement.ticks_per_tile(species)
	var extra: Dictionary = world.actor(actor_id)["extra"]
	var pace := 1.0
	if slows(coat_of(world, actor_id)):
		var mode := Movement.route_mode_of(species)
		if is_tight(world, from, mode) or is_tight(world, to, mode):
			extra["clear_steps"] = 0
			pace = TIGHT_PACE
		else:
			var clear := int(extra.get("clear_steps", RAMP.size())) + 1
			extra["clear_steps"] = clear
			if clear <= RAMP.size():
				pace = RAMP[clear - 1]
	else:
		extra.erase("clear_steps")
	var ticks := maxi(1, int(round(float(base) / pace)))
	extra["step_ticks"] = ticks
	return ticks

# sheep_brain.gd — a sheep's day: grazing, resting in a stall, and the coat that
# ends her walking (docs/design/18-sheep.md)
#
# Layer 2 (pure). She is the cow's brain with three answers changed:
#
#   * **Why she goes to a stall.** Not to give milk — she has none, and the gateway
#     refuses her `give_milk`. Now and then, deciding where to graze next, she goes
#     in to rest: a stateless draw from her id and the tick, so a replay agrees.
#   * **What she does there.** She rests for a while (`REST_SECONDS`) and walks
#     back out. While she rests the stall is hers, and a cow with milk waits.
#   * **Her extreme coat.** Daniel, 2026-10-13: "the sheep literally becomes unable
#     to take another step because they've become too fluffy", and "content/happy
#     with their immobile condition". She stops for good on the first square she
#     may settle on (`Wool.may_settle`) — never a doorway, a doorstep or a one-square
#     gap, which she squeezes through first. If she was on her way to a stall she
#     gives it back; if she was in it, it is hers for good.
#
# The coat grows at the day turn (`day_actions`, the `grow_wool` verb), and her
# slower steps at the extra-full coat are `Wool.step_ticks`, called from
# `Movement.step`: neither is decided here.
class_name SheepBrain
extends CowBrain

# Everything a sheep's `state` may say: the cow's, less nothing (she never reaches
# "giving"), plus resting in a stall and the extreme coat's contented stop.
const SHEEP_STATES: Array[String] = ["idle", "going_to_stall", "moving", "at_exterior_door",
	"crossing_in", "at_interior_door", "entering", "giving", "leaving_stall",
	"releasing", "leaving_barn", "crossing_out", "resting", "content"]

# [Tunable] The chance, in percent, that a sheep deciding where to graze next goes
# in to rest in a free stall instead. A grazing decision comes every 6 to 15
# seconds, so one in five is a visit every minute or so.
const REST_CHANCE_PERCENT := 20
# [Tunable] How long she rests in a stall, in seconds, before walking back out.
const REST_SECONDS := [20.0, 40.0]
# How often a contented sheep is looked at again, in seconds. She will not move;
# this only notices a coat that a test or the Zoo set back.
const CONTENT_SECONDS := 60.0
# How far, in squares, an extreme-coat sheep stranded in a gap looks for a square
# to settle on, and how many routes she searches each time she looks (a route to a
# square she cannot reach searches everything she can before it fails, as the cow's
# `GRAZE_ROUTES` says). A sheep who finds nowhere `SQUEEZE_TRIES` times running —
# a one-square pocket fenced all round — stops where she is.
const SETTLE_SEARCH := 4
const SQUEEZE_ROUTES := 2
const SQUEEZE_TRIES := 5


func step(world: SimWorld, actor_id: String, tick: int, gs = null) -> Dictionary:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	var state := String(extra.get("state", "idle"))
	if not Wool.is_stuck_coat(Wool.coat_of(world, actor_id)):
		if state == "content":
			extra["state"] = "idle"  # only a coat set back by hand gets here
		return super.step(world, actor_id, tick, gs)
	if state == "content":
		extra["wake"] = tick + ticks(CONTENT_SECONDS)
		return {}
	var here := world.actor_pos(actor_id)
	if Wool.may_settle(world, actor_id, here) or int(extra.get("squeeze_tries", 0)) >= SQUEEZE_TRIES:
		return _settle(world, actor_id, extra, tick, here)
	# Not to a stall now: a stall she holds and is not standing in goes back first,
	# so no cow waits on her while she squeezes out.
	if String(extra.get("barn_id", "")) != "" and not Wool.in_own_stall(world, actor_id, here):
		return _stall_action(actor_id, "leave_milk_stall", String(extra.get("barn_id", "")),
			int(extra.get("stall_index", -1)))
	# Still squeezing through. Whatever she was doing carries her on, at a quarter
	# of her pace — through a door she is crossing, along a route she is walking; if
	# she was doing nothing, she makes for the nearest square she may settle on.
	if state in ["idle", "going_to_stall", "at_interior_door"]:
		_squeeze_out(world, actor_id, extra, tick, here)
		return {}
	return super.step(world, actor_id, tick, gs)


func on_result(world: SimWorld, actor_id: String, action: Dictionary, result: Dictionary) -> void:
	super.on_result(world, actor_id, action, result)
	if String(action.get("verb", "")) != "enter_milk_stall" or not bool(result.get("ok", false)):
		return
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	var tick := world.clock.tick
	var low := ticks(float(REST_SECONDS[0]))
	var high := ticks(float(REST_SECONDS[1]))
	extra["state"] = "resting"
	extra["rest_until"] = tick + low + SimRng.stateless(_rest_salt(world, actor_id), tick) % (high - low + 1)
	extra["wake"] = int(extra["rest_until"])


# A night's wool, until the extreme coat; nothing after it.
func day_actions(world: SimWorld, actor_id: String, _gs = null) -> Array[Dictionary]:
	if Wool.is_stuck_coat(Wool.coat_of(world, actor_id)):
		return []
	return [{ "actor": actor_id, "verb": "grow_wool" }]


func _wants_stall(world: SimWorld, actor_id: String, _extra: Dictionary, tick: int) -> bool:
	if Wool.is_stuck_coat(Wool.coat_of(world, actor_id)):
		return false
	return SimRng.stateless(_rest_salt(world, actor_id) ^ 0x57a11, tick) % 100 < REST_CHANCE_PERCENT


func _rest_in_stall(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		barn_id: String, stall_index: int) -> Dictionary:
	var until := int(extra.get("rest_until", 0))
	if tick < until:
		extra["wake"] = until
		return {}
	extra.erase("rest_until")
	return _stall_action(actor_id, "leave_milk_stall", barn_id, stall_index)


# She stops here for good. A stall she holds and is not standing in goes back
# through the gateway first, so no cow waits for ever on a sheep who never came.
func _settle(world: SimWorld, actor_id: String, extra: Dictionary, tick: int, here: Vector2i) -> Dictionary:
	var barn_id := String(extra.get("barn_id", ""))
	if barn_id != "" and not Wool.in_own_stall(world, actor_id, here):
		return _stall_action(actor_id, "leave_milk_stall", barn_id, int(extra.get("stall_index", -1)))
	Movement.clear_route(world, actor_id)
	extra.erase("route_stage")
	extra.erase("rest_until")
	extra.erase("leaving_barn_id")
	extra.erase("squeeze_tries")
	extra["state"] = "content"
	extra["wake"] = tick + ticks(CONTENT_SECONDS)
	# When she stopped, and how many nights she has stood here since: the two facts
	# the picture of the grass she grazes bare round her is drawn from (design/18,
	# "Stuck for good"). Written here and at the day turn, never read by the sim.
	extra["content_since"] = tick
	extra["nights_content"] = 0
	return {}


# Another night where she stopped (design/18, "Stuck for good"): by morning she has
# grazed everything she can reach down to bare earth. Counted at the day turn, which
# a replay re-applies, so a replay and the screen agree.
func on_new_day(world: SimWorld, actor_id: String) -> void:
	var extra: Dictionary = world.actor(actor_id).get("extra", {})
	if String(extra.get("state", "")) == "content":
		extra["nights_content"] = int(extra.get("nights_content", 0)) + 1


# Walk to the nearest square she may settle on. Rings out from where she stands,
# nearest first, as far as `SETTLE_SEARCH`; the first with a route is hers. Her
# route keeps off the beds, as every walk of hers does — and a sheep whose coat
# went extreme while she stood on one walks off it this way too.
func _squeeze_out(world: SimWorld, actor_id: String, extra: Dictionary, tick: int, here: Vector2i) -> void:
	var routes := 0
	for d in range(1, SETTLE_SEARCH + 1):
		for dx in range(-d, d + 1):
			var dy := d - absi(dx)
			for cell in ([here + Vector2i(dx, -dy), here + Vector2i(dx, dy)] if dy != 0 else [here + Vector2i(dx, 0)]):
				if routes >= SQUEEZE_ROUTES:
					break
				if world.space_of(cell) != world.space_of(here) or not Wool.may_settle(world, actor_id, cell):
					continue
				if Movement.plan(world, actor_id, cell):
					extra["route_stage"] = "squeeze"; extra["state"] = "moving"
					extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))
					return
				routes += 1
	# Nowhere: she waits where she is and looks again in a second, and after
	# `SQUEEZE_TRIES` of those she stops where she is.
	Movement.clear_route(world, actor_id)
	extra["state"] = "idle"
	extra["squeeze_tries"] = int(extra.get("squeeze_tries", 0)) + 1
	extra["wake"] = tick + SimClock.RATE


static func _rest_salt(world: SimWorld, actor_id: String) -> int:
	return world.gen_seed ^ int(hash("sheep_rest:%s" % actor_id))

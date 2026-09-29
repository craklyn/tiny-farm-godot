# actor_motion.gd — how an actor's sprite follows the tile the sim has it on
#
# Every actor sprite walks toward its sim tile a few pixels a frame. That is right
# for a step across the farm and wrong for a step through a door: rooms live on the
# grid far below the farm (a coop's inside is 20-odd rows under it), so a hen who
# let herself into her coop in the rain was drawn marching straight south, through
# fences and off the bottom of the map (2026-09-28, Daniel's first save). A move
# into a different space (the farm, a room, the house) is a door, and the sprite
# goes with it at once. The dark beyond the map edge has no space, so a bird
# flying in from outside still glides in.
class_name ActorMotion

static func follow(sim, from: Vector2, goal: Vector2, step: float, tile: int) -> Vector2:
	var here := Vector2i(roundi(from.x / tile), roundi(from.y / tile))
	var there := Vector2i(roundi(goal.x / tile), roundi(goal.y / tile))
	var a: String = sim.space_of(here)
	var b: String = sim.space_of(there)
	if a != "" and b != "" and a != b:
		return goal
	return from.move_toward(goal, step)

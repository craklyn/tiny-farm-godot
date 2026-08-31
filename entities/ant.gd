# ant.gd — the raid, drawn (`design/04`; M2.5 WI-8a/8b, WI-6)
#
# **Presentation only, and one file for both ants.** Which tile an ant is on,
# where it is going, what it eats and when it gives up is
# `systems/sim/brains/ant_scout_brain.gd` and `ant_forager_brain.gd`, on the tick
# clock, in the sim. This node slides a sprite toward the tile the registry holds
# and animates the walk — the hen's job, with the hen's stalled-frame cap.
#
# The two species differ by exactly two numbers (which cells they draw and how
# fast they walk), so they share a script and differ by a row in
# `SpeciesDefs`: `world/farm.gd`'s `ACTOR_RENDERERS` names this file twice. A
# renderer per species would have been two copies of the chicken.
#
# **Nothing spawns an ant in the live game** (`SimWorld.ANT_RAIDS_PER_DAY` is 0,
# and the debut is a designer's content-sequencing call), so this is exercised in
# a detached farm by the integration suite — the sprinkler's standing, and for
# the sprinkler's reason: the renderer is the half a sim-only work item cannot
# write, and it should exist for the day the species is turned on.
extends Node2D

const TILE_SIZE := 16

# critters.png row 0: cols 0–1 the scout's two-frame walk, cols 2–3 the
# forager's (CREDITS.md, the 2026-08-30 art bench). Every cell faces **right**
# and is mirrored for the other direction, as the hen's are — she has her left
# frames drawn into the sheet; this sheet does not, so the flip is a negative
# width on the destination rect.
const SPRITES := preload("res://assets/sprites/generated/critters.png")
const FIRST_CELL := {
	SpeciesDefs.ANT_SCOUT: 0,
	SpeciesDefs.ANT_FORAGER: 2,
}
const WALK_FRAMES := 2
const FRAME_TIME := 0.16

# A long frame must not teleport it — the hen's cap, for the report her comment
# records (a stalled frame used to carry her a whole tile in one step).
const MAX_STEP := TILE_SIZE * 0.5

var actor_id: String = SimWorld.ACTOR_ANT_SCOUT
var farm: Node2D = null

var first_cell: int = 0
# Pixels per second, derived from the species' own tiles-per-tick rather than
# written down again here: the sprite then walks at exactly the speed the sim
# moves the ant, so it trails by less than a tile and cannot drift as the row is
# tuned.
var speed_px: float = 10.0

var facing_left: bool = false
var walk_frame: int = 0
# Cosmetic, and the only die roll in this file: a column of three should not step
# in lockstep. `CosmeticRng`, never the sim's seeded stream — see
# systems/cosmetic_rng.gd, and the unit test that reads this directory for the
# name of that stream and fails on a hit.
var _frame_timer: float = CosmeticRng.randf_range(0.0, FRAME_TIME)


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SimWorld.ACTOR_ANT_SCOUT) -> void:
	farm = farm_ref
	actor_id = id
	var species: String = farm.sim.species_of(actor_id)
	first_cell = int(FIRST_CELL.get(species, 0))
	speed_px = SpeciesDefs.speed_of(species) * TILE_SIZE * float(SimClock.RATE)
	position = sim_position()


func sim_position() -> Vector2:
	# `Movement.float_pos` falls back to the registry tile for anybody without a
	# continuous position, so the path that draws a flying crow draws a walking
	# ant without knowing which it has (WI-4's handoff).
	var at := Movement.float_pos(farm.sim, actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)


func _process(delta: float) -> void:
	if farm == null:
		return
	# Stomped, dispersed, or home with its crop — every one of those is the sim
	# dropping the actor, and the sprite goes with it.
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	var goal := sim_position()
	if not position.is_equal_approx(goal):
		_frame_timer += delta
		if _frame_timer >= FRAME_TIME:
			_frame_timer -= FRAME_TIME
			walk_frame = (walk_frame + 1) % WALK_FRAMES
		if goal.x < position.x:
			facing_left = true
		elif goal.x > position.x:
			facing_left = false
		position = position.move_toward(goal, minf(speed_px * delta, MAX_STEP))
		queue_redraw()
	elif walk_frame != 0:
		walk_frame = 0
		queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			# A negative width flips the cell, which is how a right-facing sheet
			# draws an ant walking left.
			var dest := Rect2(position.x, position.y, TILE_SIZE, TILE_SIZE)
			if facing_left:
				dest = Rect2(position.x + TILE_SIZE, position.y, -TILE_SIZE, TILE_SIZE)
			canvas.draw_texture_rect_region(
				SPRITES, dest, Rect2((first_cell + walk_frame) * 16, 0, 16, 16))
	})

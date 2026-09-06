# grazer.gd — the rabbit and the kangaroo, drawn (`design/04`; M2.5 WI-8c/8f, WI-6)
#
# **Presentation only, and one file for both.** Where a grazer is, what it eats,
# when it runs and where it goes is `systems/sim/brains/grazer_brain.gd`, on the
# tick clock, in the sim. This node slides a sprite toward the tile the registry
# holds and animates the hop — the hen's job, with the hen's stalled-frame cap.
#
# The two species share a script for the same reason they share a brain: they
# differ by which row of `critters.png` they draw and how fast they move, and both
# of those are read off `SpeciesDefs` rather than written here. A renderer per
# species would have been two copies of `entities/ant.gd`, which is already one
# copy of the hen — and it would have been the one place in the codebase where the
# kangaroo was a special case, which is exactly what WI-8f exists to disprove.
#
# **Nothing spawns either in the live game** (every `per_day` in
# `SimWorld.visitors()` is 0, and the debut is a designer's content-sequencing
# call), so this is exercised in a detached farm by the integration suite — the
# sprinkler's standing, and for the sprinkler's reason: the renderer is the half a
# sim-only work item cannot write, and it should exist for the day the species is
# turned on.
extends Node2D

const TILE_SIZE := 16

# One sheet per species (CREDITS.md, the 2026-08-30 art bench; split 2026-09-06):
# each is its four-frame hop in one row. Every cell faces right and is mirrored
# for the other direction, as the ants' are — the flip is a negative width on
# the destination rect, because unlike the hen's sheet these do not carry their
# own left-facing frames.
const SPRITES := {
	SpeciesDefs.RABBIT: preload("res://assets/sprites/generated/rabbit.png"),
	SpeciesDefs.KANGAROO: preload("res://assets/sprites/generated/kangaroo.png"),
}
const HOP_FRAMES := 4
const FRAME_TIME := 0.13

# A long frame must not teleport it — the hen's cap, for the report her comment
# records (a stalled frame used to carry her a whole tile in one step).
const MAX_STEP := TILE_SIZE * 0.5

var actor_id: String = SpeciesDefs.RABBIT
var farm: Node2D = null

var sprites: Texture2D = SPRITES[SpeciesDefs.RABBIT]
# Pixels per second, derived from the species' own tiles-per-tick rather than
# written down again here: the sprite then moves at exactly the speed the sim
# moves the animal, so it trails by less than a tile and cannot drift as the row
# is tuned. It is also the only place the kangaroo visibly differs from the
# rabbit, and it differs by arithmetic on the table.
var speed_px: float = 30.0

var facing_left: bool = false
var hop_frame: int = 0
# Cosmetic, and the only die roll in this file: two animals in one field should
# not hop in lockstep. `CosmeticRng`, never the sim's seeded stream — see
# systems/cosmetic_rng.gd, and the unit test that reads this directory for the
# name of that stream and fails on a hit.
var _frame_timer: float = CosmeticRng.randf_range(0.0, FRAME_TIME)


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.RABBIT) -> void:
	farm = farm_ref
	actor_id = id
	var species: String = farm.sim.species_of(actor_id)
	sprites = SPRITES.get(species, SPRITES[SpeciesDefs.RABBIT])
	speed_px = SpeciesDefs.speed_of(species) * TILE_SIZE * float(SimClock.RATE)
	position = sim_position()


func sim_position() -> Vector2:
	# `Movement.float_pos` falls back to the registry tile for anybody without a
	# continuous position, so the path that draws a flying crow draws a hopping
	# rabbit without knowing which it has (WI-4's handoff).
	var at := Movement.float_pos(farm.sim, actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)


func _process(delta: float) -> void:
	if farm == null:
		return
	# Full, bored, or safely back through the hedge — every one of those is the
	# sim dropping the actor, and the sprite goes with it.
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	var goal := sim_position()
	if not position.is_equal_approx(goal):
		_frame_timer += delta
		if _frame_timer >= FRAME_TIME:
			_frame_timer -= FRAME_TIME
			hop_frame = (hop_frame + 1) % HOP_FRAMES
		if goal.x < position.x:
			facing_left = true
		elif goal.x > position.x:
			facing_left = false
		position = position.move_toward(goal, minf(speed_px * delta, MAX_STEP))
		queue_redraw()
	elif hop_frame != 0:
		# A sitting rabbit sits: frame 0 is the resting pose, which is also what
		# the player sees for the second or two it is chewing.
		hop_frame = 0
		queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			# A negative width flips the cell, which is how a right-facing sheet
			# draws an animal moving left.
			var dest := Rect2(position.x, position.y, TILE_SIZE, TILE_SIZE)
			if facing_left:
				dest = Rect2(position.x + TILE_SIZE, position.y, -TILE_SIZE, TILE_SIZE)
			canvas.draw_texture_rect_region(
				sprites, dest, Rect2(hop_frame * 16, 0, 16, 16))
	})

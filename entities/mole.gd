# mole.gd — the mole, drawn (`design/04`; M2.5 WI-8d, WI-6)
#
# **Presentation only.** Where the mole is, what it steals and when it comes up is
# `systems/sim/brains/mole_brain.gd`, on the tick clock, in the sim. This node
# slides a sprite toward the tile the registry holds — the hen's job, with the
# hen's stalled-frame cap — and picks one of three cells.
#
# **The three cells are the three states `Movement.is_under` implies**, which is
# WI-6's handoff to this file almost word for word ("a burrower asks
# `Movement.is_under` whether to draw at all, and r2's three cells are exactly the
# three states that answer implies"). Rather than draw nothing while it is under,
# it draws the **mound**: a mole under the farm is not invisible, it is a ridge of
# soil moving across the field, and that is both the readable answer and the one
# that gives the player something to walk over to. Whether the route should be
# given away like that was `[Designer]` Q-64, **ruled 2026-08-31: the mound stays
# visible** — a chase a four-year-old can win beats an ambush she cannot see.
#
# **Nothing spawns one in the live game** (`SimWorld.MOLE_VISITS_PER_DAY` is 0, and
# the debut is a designer's content-sequencing call), so this is exercised in a
# detached farm by the integration suite — the sprinkler's standing, and for the
# sprinkler's reason.
extends Node2D

const TILE_SIZE := 16

# mole.png: col 0 the mound, col 1 emerging, col 2 surfaced (CREDITS.md, the
# 2026-08-31 art bench; split to its own sheet 2026-09-06). Every cell faces
# right and is mirrored for the other direction, as the ants' and the grazers' are.
const SPRITES := preload("res://assets/sprites/generated/mole.png")
const CELL_MOUND := 0
const CELL_EMERGING := 1
const CELL_SURFACED := 2

# A long frame must not teleport it — the hen's cap, for the report her comment
# records (a stalled frame used to carry her a whole tile in one step).
const MAX_STEP := TILE_SIZE * 0.5

var actor_id: String = SpeciesDefs.MOLE
var farm: Node2D = null

# Pixels per second, derived from the species' own tiles-per-tick rather than
# written down again here, so the mound travels at exactly the speed the sim
# tunnels the mole and cannot drift as the row is tuned.
var speed_px: float = 20.0

var facing_left: bool = false


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.MOLE) -> void:
	farm = farm_ref
	actor_id = id
	speed_px = SpeciesDefs.speed_of(farm.sim.species_of(actor_id)) * TILE_SIZE * float(SimClock.RATE)
	position = sim_position()


func sim_position() -> Vector2:
	# `Movement.float_pos` falls back to the registry tile for anybody without a
	# continuous position, so the path that draws a flying crow draws a tunnelling
	# mole without knowing which it has (WI-4's handoff).
	var at := Movement.float_pos(farm.sim, actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)


# Which of the three it is right now. Read off the sim — `Movement.is_under` for
# the mound, and the brain's own state for the moment it is coming up — so the
# renderer holds no animation state of its own and cannot disagree with the world.
func cell() -> int:
	if not farm.sim.has_actor(actor_id):
		return CELL_MOUND
	if Movement.is_under(farm.sim, actor_id):
		return CELL_MOUND
	if String(farm.sim.actor(actor_id)["extra"].get("state", "")) == MoleBrain.STATE_EMERGE:
		return CELL_EMERGING
	return CELL_SURFACED


func _process(delta: float) -> void:
	if farm == null:
		return
	# Fed, or out of seeds worth surfacing for — either way the sim drops the
	# actor when the visit ends, and the sprite goes with it.
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	var goal := sim_position()
	if not position.is_equal_approx(goal):
		if goal.x < position.x:
			facing_left = true
		elif goal.x > position.x:
			facing_left = false
		position = position.move_toward(goal, minf(speed_px * delta, MAX_STEP))
	queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			# A negative width flips the cell, which is how a right-facing sheet
			# draws a mole heading the other way.
			var dest := Rect2(position.x, position.y, TILE_SIZE, TILE_SIZE)
			if facing_left:
				dest = Rect2(position.x + TILE_SIZE, position.y, -TILE_SIZE, TILE_SIZE)
			canvas.draw_texture_rect_region(
				SPRITES, dest, Rect2(cell() * 16, 0, 16, 16))
	})

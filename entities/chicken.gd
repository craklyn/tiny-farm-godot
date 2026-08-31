# chicken.gd — the hen, drawn (design/13 §4a; M2.5 WI-3)
#
# **Presentation only.** Where she is and where she is going is sim truth, decided
# by `systems/sim/brains/chicken_brain.gd` and stored in the actor registry; this
# node slides a sprite toward the tile the sim has her on and animates the walk.
#
# It used to be the other way round. Her whole FSM lived in `_process` here —
# idle timers, wander targets and pathing, all drawn from the **sim's seeded
# stream** (plan finding F-2) on **frame time** (F-4). A renderer holding the
# sim's dice is a desync waiting for a witness, and it is why the stateless
# per-day draw had to be invented for the crow schedule. Nothing under
# `entities/` reaches for that stream any more, and the verifier greps for
# exactly that (checklist §8.B). Anything here that genuinely wants a die roll
# uses `CosmeticRng`, whose answers can differ between two runs of the same
# session without either being wrong.
extends Node2D

const TILE_SIZE = 16
const SPEED = 20.0
# A long frame must not teleport her. `_process` is handed the real frame time,
# so one stalled frame — rebuilding a menu's options, a shader compile, a hitch —
# used to carry her a whole tile in a single step. That is what a player saw as
# the chicken jumping at the moment of clicking Buy. Capping the step at half a
# tile costs nothing at 60fps (0.33px/frame) and only bites past ~0.4s frames.
# Still true, and still needed: the sim moves her a tile at a time and this is
# what walks the sprite between them.
const MAX_STEP := TILE_SIZE * 0.5

# animals.png cells: 0-3 walk cycle facing right, 4-7 the same facing left
const SPRITES := preload("res://assets/sprites/generated/animals.png")
const WALK_FRAMES := 4
const FRAME_TIME := 0.14  # matches the 4-frame walk budget in docs/design/09

# Her id in the registry. Ids are species names in phase 1 — there is one hen and
# she is called "chicken" — but the node takes it as a parameter, so a second hen
# is a second `spawn_actor` and a second node and nothing else.
var actor_id: String = SimWorld.ACTOR_CHICKEN

var tx: int
var ty: int
var facing_left: bool = false
var walk_frame: int = 0
# Cosmetic, and the one die roll a renderer is allowed: two hens standing side by
# side should not step in lockstep. Nothing reads this but the sprite.
var _frame_timer: float = CosmeticRng.randf_range(0.0, FRAME_TIME)

var farm: Node2D

func _ready() -> void:
	queue_redraw()

func init(farm_ref: Node2D, id: String = SimWorld.ACTOR_CHICKEN) -> void:
	farm = farm_ref
	actor_id = id
	var at: Vector2i = farm.sim.actor_pos(actor_id)
	tx = at.x
	ty = at.y
	position = Vector2(tx * TILE_SIZE, ty * TILE_SIZE)

# Where the sim says she is, in pixels — the goal this node walks toward.
func sim_position() -> Vector2:
	var at: Vector2i = farm.sim.actor_pos(actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)

func _process(delta: float) -> void:
	if not farm:
		return
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	var goal := sim_position()
	var moving := not position.is_equal_approx(goal)

	# Walk cycle runs only while actually moving; idle rests on frame 0 so a
	# standing hen doesn't march in place.
	if moving:
		_frame_timer += delta
		if _frame_timer >= FRAME_TIME:
			_frame_timer -= FRAME_TIME
			walk_frame = (walk_frame + 1) % WALK_FRAMES
			queue_redraw()
		if goal.x < position.x:
			facing_left = true
		elif goal.x > position.x:
			facing_left = false
		position = position.move_toward(goal, minf(SPEED * delta, MAX_STEP))
		queue_redraw()
	else:
		if walk_frame != 0:
			queue_redraw()
		walk_frame = 0

	var at: Vector2i = farm.sim.actor_pos(actor_id)
	tx = at.x
	ty = at.y

func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			var cell: int = walk_frame + (WALK_FRAMES if facing_left else 0)
			canvas.draw_texture_rect_region(
				SPRITES,
				Rect2(position.x, position.y, TILE_SIZE, TILE_SIZE),
				Rect2(cell * 16, 0, 16, 16))
	})

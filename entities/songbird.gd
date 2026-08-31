# songbird.gd — the ambient bird, drawn (`design/04` §5; M2.5 WI-8g, WI-6)
#
# **Presentation only, and there is very little of it**, which is the point. The
# bird's whole visit — where it goes, how long it sits, when it leaves — is
# `systems/sim/brains/songbird_brain.gd`, on the tick clock, in the sim, and that
# brain never returns an Action. So this file has no verb to react to, no sound to
# make on a result, and no proximity to measure: it draws a bird where the sim
# says one is, and flaps while it is moving.
#
# It reads a **continuous** position (`Movement.float_pos`, the crow's pairing:
# the brain keeps `fx`/`fy` in tile space and the registry tile is its rounded
# shadow), which is what makes smooth flight possible out of a ten-hertz truth.
#
# **Nothing spawns one in the live game** — `SimWorld.SONGBIRDS_PER_DAY` is 0 and
# the debut is a designer's content-sequencing call — so this is exercised in a
# detached farm by the integration suite, the sprinkler's and the ants' standing.
extends Node2D

const TILE_SIZE := 16

# critters.png row 5 (CREDITS.md, the 2026-08-30 art bench): col 0 perched,
# col 1 wings up, col 2 wings down. The three generations disagreed about belly
# colour and were remapped to one cream belly precisely so this two-frame flap
# does not strobe.
const SPRITES := preload("res://assets/sprites/generated/critters.png")
const SHEET_ROW := 5
const CELL_PERCHED := 0
const CELL_WINGS_UP := 1
const CELL_WINGS_DOWN := 2

# Pixels per second, from the species row rather than written down again, so the
# sprite flies at exactly the speed the sim flies the bird (the ant's rule).
const FLAP_TIME := 0.09
const MAX_STEP := TILE_SIZE * 1.5  # a stalled frame must not fling it across the farm

var actor_id: String = SpeciesDefs.SONGBIRD
var farm: Node2D = null

var speed_px: float = 35.0
var flap_timer: float = 0.0
var flap_state: int = 0
var facing_left: bool = false


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.SONGBIRD) -> void:
	farm = farm_ref
	actor_id = id
	speed_px = SpeciesDefs.speed_of(farm.sim.species_of(actor_id)) * TILE_SIZE * float(SimClock.RATE)
	position = sim_position()
	# Cosmetic, and the only die roll in this file: two birds should not flap in
	# unison. `CosmeticRng`, never the sim's seeded stream.
	flap_timer = CosmeticRng.randf_range(0.0, FLAP_TIME)


func sim_position() -> Vector2:
	var at := Movement.float_pos(farm.sim, actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)


func perched() -> bool:
	return String(farm.sim.actor(actor_id).get("extra", {}).get("state", "")) \
		== SongbirdBrain.STATE_PERCHED


func _process(delta: float) -> void:
	if farm == null:
		return
	# It left the map, which is the only way a songbird's visit ends.
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	var goal := sim_position()
	if goal.x < position.x - 0.01:
		facing_left = true
	elif goal.x > position.x + 0.01:
		facing_left = false
	position = position.move_toward(goal, minf(speed_px * delta, MAX_STEP))

	flap_timer += delta
	if flap_timer > FLAP_TIME:
		flap_timer = 0.0
		flap_state = (flap_state + 1) % 2
		queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			var cell := CELL_PERCHED
			if not perched():
				cell = CELL_WINGS_UP if flap_state == 0 else CELL_WINGS_DOWN
			# A negative width flips the cell; the sheet faces right, like the
			# rest of critters.png.
			var dest := Rect2(position.x, position.y, TILE_SIZE, TILE_SIZE)
			if facing_left:
				dest = Rect2(position.x + TILE_SIZE, position.y, -TILE_SIZE, TILE_SIZE)
			canvas.draw_texture_rect_region(
				SPRITES, dest, Rect2(cell * 16, SHEET_ROW * 16, 16, 16))
	})

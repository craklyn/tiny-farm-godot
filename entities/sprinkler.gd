# sprinkler.gd — the first machine, drawn (design/03; M2.5 WI-10, WI-6)
#
# **Presentation only, and barely that.** A sprinkler is a registered actor that
# never moves (`SpeciesDefs.STATIC` — `Movement.passable` refuses it every tile,
# so there is nothing to interpolate) and acts exactly once a day, inside the day
# turn. So this node is a sprite at `world.actor_pos()` plus one piece of timing:
# the spray frame, held briefly after a morning so the watering it did is
# something the player can see happen rather than a farm that is simply wet.
#
# **Nothing places one yet.** Acquisition is Q-15's ruling and the plan leaves it
# open (WI-10 deviation 8), so a sprinkler exists only where `spawn_actor` puts
# one — the tests, and whatever M3 builds. This is here so that the day it does
# get placed, it is visible: the renderer was the one half WI-10 could not write.
extends Node2D

const TILE_SIZE := 16

# objects.png row 1: col 5 idle, col 6 spraying. Generated as a pair so they
# cannot drift (CREDITS.md, the 2026-08-30 art bench).
const SPRITES := preload("res://assets/sprites/generated/objects.png")
const IDLE_CELL := Rect2(5 * 16, 16, 16, 16)
const SPRAY_CELL := Rect2(6 * 16, 16, 16, 16)

# How long the spray frame is held after the day turn. [Playtest] — long enough
# to read across a room, short enough that a machine is not permanently mid-act.
const SPRAY_SECONDS := 1.4

var actor_id: String = SpeciesDefs.SPRINKLER
var farm: Node2D = null

var _spray_timer: float = 0.0


func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.SPRINKLER) -> void:
	farm = farm_ref
	actor_id = id
	position = _sim_position()


# The day turned, so it has just watered its radius. Told by the farm rather than
# noticed here, because a machine's one act happens *inside* `advance_day`
# (`Brain.day_actions`, WI-10) — there is no tick a renderer could catch it on.
func on_day_turn() -> void:
	_spray_timer = SPRAY_SECONDS
	queue_redraw()


func _sim_position() -> Vector2:
	# `Movement.float_pos` falls back to the registry tile for anybody without a
	# continuous position, so the one code path that draws a flying crow draws a
	# machine too, without knowing which it has (WI-4's handoff).
	var at := Movement.float_pos(farm.sim, actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)


func _process(delta: float) -> void:
	if farm == null:
		return
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return
	position = _sim_position()
	if _spray_timer > 0.0:
		_spray_timer -= delta
		if _spray_timer <= 0.0:
			queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	var cell: Rect2 = SPRAY_CELL if _spray_timer > 0.0 else IDLE_CELL
	render_queue.append({
		"y": position.y,
		"draw": func():
			canvas.draw_texture_rect_region(
				SPRITES, Rect2(position.x, position.y, TILE_SIZE, TILE_SIZE), cell)
	})

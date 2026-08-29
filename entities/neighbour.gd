# neighbour.gd — the departing child, as an actor (T-13, Q-37/Q-45)
#
# Presentation only. Every world change she makes goes through
# `SimWorld.apply_action` with `actor: "neighbour"`, decided by the pure
# `systems/sim/cold_open.gd` — this file only walks her there and animates the
# swing. That is what makes the cold open cheap: she is not a cutscene system,
# she is one more entity, exactly like the chicken and the crow (S-3).
#
# She borrows the player's own walk cycle, recoloured (see CREDITS.md): at 16px
# a four-year-old reads *another child* from hair and clothes, and a bespoke
# sheet is a cheap upgrade whenever the art pass wants one.
extends Node2D

const TILE_SIZE := 16
const SPEED := 26.0
const POSE_SECONDS := 0.45
const WAVE_SECONDS := 1.6

const SPRITES := preload("res://assets/sprites/generated/neighbour.png")
const WALK_FRAMES := 4
const FRAME_TIME := 0.15

var tx: int = 0
var ty: int = 0
var facing: String = "down"
var farm: Node2D = null

var _path: Array[Vector2i] = []
var _walk_frame: int = 0
var _frame_timer: float = 0.0
var _pose_timer: float = 0.0
var _leaving := false

var _quads: Dictionary = {}


func _ready() -> void:
	var directions: Array[String] = ["down", "up", "left", "right"]
	for row in directions.size():
		_quads[directions[row]] = {}
		for col in 4:
			_quads[directions[row]][col] = Rect2(col * 48, row * 48, 48, 48)
	queue_redraw()


func init(farm_ref: Node2D, start_t: Vector2i) -> void:
	farm = farm_ref
	tx = start_t.x
	ty = start_t.y
	position = Vector2(tx * TILE_SIZE + TILE_SIZE / 2.0, ty * TILE_SIZE + TILE_SIZE / 2.0)


# Busy means "do not hand me the next action yet" — she is mid-stride or
# mid-swing. The scene waits for her rather than teleporting her, because a
# person who slides between tiles is not demonstrating anything.
func is_busy() -> bool:
	return _pose_timer > 0.0 or not _path.is_empty() or _leaving


func is_beside(t: Vector2i) -> bool:
	return absi(tx - t.x) + absi(ty - t.y) <= 1


# Walk up to a tile, not onto it: she works from the side, the way the player
# does (Q-30). An empty path here means "already beside it", which is the common
# case and must never be read as "cannot get there".
func go_to(t: Vector2i) -> void:
	if farm == null or is_beside(t):
		return
	_path = Pathfinding.find_path_toward(farm, Vector2i(tx, ty), t)


func face(t: Vector2i) -> void:
	var dx := t.x - tx
	var dy := t.y - ty
	if absi(dx) >= absi(dy) and dx != 0:
		facing = "right" if dx > 0 else "left"
	elif dy != 0:
		facing = "down" if dy > 0 else "up"


func pose(t: Vector2i) -> void:
	face(t)
	_pose_timer = POSE_SECONDS


# She waves, and a four-year-old reads a wave instantly. It is the same action
# frame held longer — one frame of art doing two jobs (design/13 §4a).
func wave() -> void:
	facing = "down"
	_pose_timer = WAVE_SECONDS


# Off the map edge, which with the offscreen engine is the whole departure. No
# truck sprite: sound is far cheaper than art and reads as clearly.
func leave() -> void:
	_leaving = true
	_path = []


func _process(delta: float) -> void:
	if _pose_timer > 0.0:
		_pose_timer -= delta
		queue_redraw()
		return

	if _leaving:
		facing = "left"
		position.x -= SPEED * delta
		_advance_walk(delta)
		if position.x < -3.0 * TILE_SIZE:
			queue_free()
		return

	if _path.is_empty():
		_walk_frame = 0
		return

	var wp: Vector2i = _path[0]
	var goal := Vector2(wp.x * TILE_SIZE + TILE_SIZE / 2.0, wp.y * TILE_SIZE + TILE_SIZE / 2.0)
	var diff := goal - position
	if diff.length() < 1.0:
		position = goal
		tx = wp.x
		ty = wp.y
		_path.remove_at(0)
		return
	var dir := diff.normalized()
	position += dir * SPEED * delta
	if absf(dir.x) > absf(dir.y):
		facing = "right" if dir.x > 0 else "left"
	else:
		facing = "down" if dir.y > 0 else "up"
	_advance_walk(delta)


func _advance_walk(delta: float) -> void:
	_frame_timer += delta
	if _frame_timer >= FRAME_TIME:
		_frame_timer -= FRAME_TIME
		_walk_frame = (_walk_frame + 1) % WALK_FRAMES
	queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	var frame: int = 3 if _pose_timer > 0.0 else _walk_frame
	var region: Rect2 = _quads.get(facing, {}).get(frame, Rect2())
	if region.size.x <= 0.0:
		return
	var draw_pos := position + Vector2(-24.0, -32.0)
	render_queue.append({
		"y": position.y,
		"draw": func(): canvas.draw_texture_rect_region(SPRITES, Rect2(draw_pos, Vector2(48, 48)), region)
	})

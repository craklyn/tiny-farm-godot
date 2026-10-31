# A visiting farmer follows the collector registry actor. No onboarding behavior.
extends Node2D

const SPRITES := preload("res://assets/sprites/generated/neighbour.png")
const TILE_SIZE := 16
const SPEED := 26.0
var farm: Node2D
var actor_id := ""
var _frame_time := 0.0
var _frame := 0
var _facing := "down"

func init_actor(farm_ref: Node2D, id: String) -> void:
	farm = farm_ref
	actor_id = id
	position = Vector2(farm.sim.actor_pos(id)) * TILE_SIZE

func _process(delta: float) -> void:
	if farm == null:
		return
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return
	var goal := Vector2(farm.sim.actor_pos(actor_id)) * TILE_SIZE
	var moving := not goal.is_equal_approx(position)
	if moving:
		_facing = String(farm.sim.actor(actor_id).get("facing", "down"))
		_frame_time += delta
		if _frame_time >= 0.15:
			_frame_time -= 0.15
			_frame = (_frame + 1) % 4
		position = ActorMotion.follow(farm.sim, position, goal, minf(SPEED * delta, 8.0), TILE_SIZE)
	else:
		_frame = 0

func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	var row := ["down", "up", "left", "right"].find(_facing)
	if row < 0:
		row = 0
	var region := Rect2(_frame * 48, row * 48, 48, 48)
	var extra: Dictionary = farm.sim.actor(actor_id).get("extra", {})
	var carried: Array = extra.get("carried", [])
	var origin := position + Vector2(-16, -24)
	render_queue.append({"y": position.y + 8, "draw": func():
		canvas.draw_texture_rect_region(SPRITES, Rect2(origin, Vector2(48, 48)), region)
		# The hen lies across the farmer's arms, not on the ground following them.
		for i in carried.size():
			var bird: Dictionary = carried[i]
			var chick := String(bird.get("stage", "adult")) == "chick"
			var size := 6.0 if chick else 10.0
			# The person occupies only 13x22 pixels of the 48px cell. Keep
			# birds beside the lower torso, clear of their face and feet.
			var at := position + (Vector2(9, 7) if chick else Vector2(-3, 5))
			canvas.draw_texture_rect_region(PoultryArt.chick_texture() if chick else PoultryArt.HEN,
				Rect2(at, Vector2(size, size)), Rect2(0, 0, 16, 16))
	})

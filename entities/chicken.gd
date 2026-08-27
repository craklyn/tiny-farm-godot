extends Node2D

const TILE_SIZE = 16
const SPEED = 20.0

# animals.png cells: 0-3 walk cycle facing right, 4-7 the same facing left
const SPRITES := preload("res://assets/sprites/generated/animals.png")
const WALK_FRAMES := 4
const FRAME_TIME := 0.14  # matches the 4-frame walk budget in docs/design/09

var tx: int
var ty: int
var state: String = "idle"
var timer: float = SimRng.randf_range(0.0, 2.0)
var facing_left: bool = false
var walk_frame: int = 0
var _frame_timer: float = 0.0

var path: Array[Vector2i] = []
var path_index: int = 0
var farm: Node2D

func _ready() -> void:
	queue_redraw()

func init(farm_ref: Node2D, start_t: Vector2i):
	farm = farm_ref
	tx = start_t.x
	ty = start_t.y
	position = Vector2(tx * TILE_SIZE, ty * TILE_SIZE)

func _process(delta: float) -> void:
	if not farm:
		return
		
	# Walk cycle runs only while actually moving; idle rests on frame 0 so a
	# standing hen doesn't march in place.
	if state == "moving":
		_frame_timer += delta
		if _frame_timer >= FRAME_TIME:
			_frame_timer -= FRAME_TIME
			walk_frame = (walk_frame + 1) % WALK_FRAMES
			queue_redraw()
	else:
		walk_frame = 0
		_frame_timer = 0.0

	if state == "idle":
		timer -= delta
		if timer <= 0:
			var reachable = Pathfinding.get_reachable_tiles(farm, Vector2i(tx, ty))
			if reachable.size() > 0:
				var target = reachable[SimRng.randi() % reachable.size()]
				path = Pathfinding.find_path(farm, Vector2i(tx, ty), target)
				if path.size() > 0:
					state = "moving"
					path_index = 0
				else:
					timer = SimRng.randf_range(1.0, 3.0)
			else:
				timer = SimRng.randf_range(1.0, 3.0)
	elif state == "moving":
		if path_index >= path.size():
			state = "idle"
			timer = SimRng.randf_range(2.0, 5.0)
			return
			
		var target = path[path_index]
		if not farm.is_walkable(target.x, target.y):
			state = "idle"
			timer = 0.0
			return
		var target_pos = Vector2(target.x * TILE_SIZE, target.y * TILE_SIZE)
		
		if target_pos.x < position.x:
			facing_left = true
		elif target_pos.x > position.x:
			facing_left = false

		var dist = position.distance_to(target_pos)
		if dist <= SPEED * delta:
			position = target_pos
			tx = target.x
			ty = target.y
			path_index += 1
		else:
			position = position.move_toward(target_pos, SPEED * delta)

func on_new_day() -> void:
	if SimRng.randf() > 0.5:
		var reachable = Pathfinding.get_reachable_tiles(farm, Vector2i(tx, ty))
		if reachable.size() > 0:
			var target = reachable[SimRng.randi() % reachable.size()]
			farm.apply_action({ "verb": "lay_egg", "target": target, "actor": "chicken" })

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

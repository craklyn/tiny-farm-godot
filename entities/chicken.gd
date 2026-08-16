extends Node2D

const TILE_SIZE = 16
const SPEED = 20.0

var tx: int
var ty: int
var state: String = "idle"
var timer: float = randf_range(0.0, 2.0)

var path: Array[Vector2i] = []
var path_index: int = 0
var farm: Node2D

func _ready() -> void:
	queue_redraw()

func init(farm_ref: Node2D, start_t: Vector2i):
	farm = farm_ref
	tx = start_t.x
	ty = start_t.y
	position = Vector2((tx - 1) * TILE_SIZE, (ty - 1) * TILE_SIZE)

func _process(delta: float) -> void:
	if not farm:
		return
		
	if state == "idle":
		timer -= delta
		if timer <= 0:
			var reachable = Pathfinding.get_reachable_tiles(farm, Vector2i(tx, ty))
			if reachable.size() > 0:
				var target = reachable[randi() % reachable.size()]
				path = Pathfinding.find_path(farm, Vector2i(tx, ty), target)
				if path.size() > 0:
					state = "moving"
					path_index = 0
				else:
					timer = randf_range(1.0, 3.0)
			else:
				timer = randf_range(1.0, 3.0)
	elif state == "moving":
		if path_index >= path.size():
			state = "idle"
			timer = randf_range(2.0, 5.0)
			return
			
		var target = path[path_index]
		if not farm.is_walkable(target.x, target.y):
			state = "idle"
			timer = 0.0
			return
		var target_pos = Vector2((target.x - 1) * TILE_SIZE, (target.y - 1) * TILE_SIZE)
		
		var dist = position.distance_to(target_pos)
		if dist <= SPEED * delta:
			position = target_pos
			tx = target.x
			ty = target.y
			path_index += 1
		else:
			position = position.move_toward(target_pos, SPEED * delta)

func on_new_day() -> void:
	if randf() > 0.5:
		var reachable = Pathfinding.get_reachable_tiles(farm, Vector2i(tx, ty))
		if reachable.size() > 0:
			var target = reachable[randi() % reachable.size()]
			if farm.get_object(target.x, target.y) == "":
				farm.set_object(target.x, target.y, "egg")

func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func(): 
			canvas.draw_rect(Rect2(position.x + 4, position.y + 4, 8, 8), Color.WHITE)
			canvas.draw_rect(Rect2(position.x + 6, position.y + 2, 4, 2), Color.RED)
			canvas.draw_rect(Rect2(position.x + 6, position.y + 6, 2, 2), Color.ORANGE)
	})

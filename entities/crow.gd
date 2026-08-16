extends Node2D

const TILE_SIZE := 16

var target_tx: int = 0
var target_ty: int = 0

var state: String = "flying_in" # flying_in, eating, flying_away
var timer: float = 0.0

var flap_timer: float = 0.0
var flap_state: int = 0

var farm: Node2D = null
var player: Node2D = null
var entities_manager: Node = null

func init_crow(start_x: float, start_y: float, tx: int, ty: int, f: Node2D, p: Node2D, em: Node) -> void:
	position = Vector2(start_x, start_y)
	target_tx = tx
	target_ty = ty
	farm = f
	player = p
	entities_manager = em


func _process(delta: float) -> void:
	# Animation
	flap_timer += delta
	if flap_timer > 0.1:
		flap_timer = 0.0
		flap_state = (flap_state + 1) % 2
		queue_redraw()
	
	if state == "flying_in":
		if _is_spooked():
			state = "flying_away"
			return
		
		var target_x: float = target_tx * TILE_SIZE + TILE_SIZE / 2.0
		var target_y: float = target_ty * TILE_SIZE + TILE_SIZE / 2.0
		
		var speed: float = 60.0 * delta
		var dx: float = target_x - position.x
		var dy: float = target_y - position.y
		var dist: float = sqrt(dx*dx + dy*dy)
		
		if dist <= speed:
			position.x = target_x
			position.y = target_y
			state = "eating"
			timer = 5.0 # 5 seconds to eat crop
		else:
			position.x += (dx/dist) * speed
			position.y += (dy/dist) * speed
			
	elif state == "eating":
		if _is_spooked():
			state = "flying_away"
			return
			
		timer -= delta
		if timer <= 0:
			var tile = farm.get_tile(target_tx, target_ty)
			if not tile.is_empty() and (tile.state == "growing" or tile.state == "ready" or tile.state == "seeded"):
				farm.set_tile_state(target_tx, target_ty, "tilled")
				if get_tree() and get_tree().root.has_node("AudioManager"):
					get_tree().root.get_node("AudioManager").play_sfx("till")
			state = "flying_away"
			
	elif state == "flying_away":
		var speed: float = 80.0 * delta
		position.x -= speed
		position.y -= speed
		
		if position.x < -100 or position.y < -100:
			queue_free()


func _is_spooked() -> bool:
	if not player or not farm:
		return false
		
	# Check player distance
	var dx: float = player.position.x - position.x
	var dy: float = player.position.y - position.y
	var dist: float = sqrt(dx*dx + dy*dy)
	var sr = player.get("spook_radius")
	if sr == null:
		sr = 3.0 * TILE_SIZE
	if dist < sr:
		return true
		
	# Check scarecrow
	var my_tx = int(position.x / TILE_SIZE)
	var my_ty = int(position.y / TILE_SIZE)
	if farm.has_method("is_protected_by_scarecrow") and farm.is_protected_by_scarecrow(my_tx, my_ty):
		return true
		
	# Check other entities
	if entities_manager:
		for ent in entities_manager.get_children():
			if ent != self and ent.get("spook_radius") != null:
				var edx: float = ent.position.x - position.x
				var edy: float = ent.position.y - position.y
				var edist: float = sqrt(edx*edx + edy*edy)
				if edist < ent.spook_radius:
					return true
					
	return false


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			# Draw body
			canvas.draw_rect(Rect2(position.x - 4, position.y - 4, 8, 8), Color(0.1, 0.1, 0.1))
			
			# Draw wings
			if state == "flying_in" or state == "flying_away":
				if flap_state == 0:
					canvas.draw_rect(Rect2(position.x - 10, position.y - 8, 6, 4), Color(0.1, 0.1, 0.1))
					canvas.draw_rect(Rect2(position.x + 4, position.y - 8, 6, 4), Color(0.1, 0.1, 0.1))
				else:
					canvas.draw_rect(Rect2(position.x - 10, position.y, 6, 4), Color(0.1, 0.1, 0.1))
					canvas.draw_rect(Rect2(position.x + 4, position.y, 6, 4), Color(0.1, 0.1, 0.1))
					
			# Draw beak
			canvas.draw_rect(Rect2(position.x - 2, position.y + 2, 4, 4), Color(0.9, 0.7, 0.1))
	})

extends Node2D

const TILE_SIZE := 16

const SPRITES := preload("res://assets/sprites/generated/animals.png")

var target_tx: int = 0
var target_ty: int = 0

var state: String = "flying_in" # flying_in, eating, flying_away
var timer: float = 0.0

var flap_timer: float = 0.0
var flap_state: int = 0

var farm: Node2D = null
var player: Node2D = null
var entities_manager: Node = null

# T-2: the first crow of a save cannot eat. It still flies in, still perches,
# still squawks and puffs feathers when scared — it simply leaves empty-beaked.
# Q-10 rules that pests are comedy rather than threat and that the *first
# introduction* of each pest is the case that matters most; a first encounter
# that costs the player a crop teaches threat no matter how gently it is drawn.
var harmless: bool = false

# A harmless crow dawdles, so there is an unmissable window to walk over and
# scare it off. The telegraph is the point: she should get to win.
const EAT_SECONDS := 5.0
const HARMLESS_PERCH_SECONDS := 12.0

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
		var cause_in := _spook_cause()
		if cause_in != "":
			_on_scared(cause_in)
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
			timer = HARMLESS_PERCH_SECONDS if harmless else EAT_SECONDS
		else:
			position.x += (dx/dist) * speed
			position.y += (dy/dist) * speed
			
	elif state == "eating":
		var cause_eat := _spook_cause()
		if cause_eat != "":
			_on_scared(cause_eat)
			state = "flying_away"
			return
			
		timer -= delta
		if timer <= 0:
			if harmless:
				# Leaves without touching the crop, and without consuming the
				# eat_crop verb — the sim never hears about this visit at all.
				if get_tree() and get_tree().root.has_node("AudioManager"):
					get_tree().root.get_node("AudioManager").play_sfx("squawk")
			else:
				var result: Dictionary = farm.apply_action({
					"verb": "eat_crop",
					"target": Vector2i(target_tx, target_ty),
					"actor": "crow",
				})
				if result.get("ok", false):
					if get_tree() and get_tree().root.has_node("AudioManager"):
						get_tree().root.get_node("AudioManager").play_sfx("till")
			state = "flying_away"
			
	elif state == "flying_away":
		var speed: float = 80.0 * delta
		position.x -= speed
		position.y -= speed
		
		if position.x < -100 or position.y < -100:
			queue_free()


# Returns what spooked the crow: "player", "scarecrow", "entity", or "" if calm.
func _spook_cause() -> String:
	if not player or not farm:
		return ""

	# Check player distance
	var dx: float = player.position.x - position.x
	var dy: float = player.position.y - position.y
	var dist: float = sqrt(dx*dx + dy*dy)
	var sr = player.get("spook_radius")
	if sr == null:
		sr = 3.0 * TILE_SIZE
	if dist < sr:
		return "player"

	# Check scarecrow
	var my_tx = int(position.x / TILE_SIZE)
	var my_ty = int(position.y / TILE_SIZE)
	if farm.has_method("is_protected_by_scarecrow") and farm.is_protected_by_scarecrow(my_tx, my_ty):
		return "scarecrow"

	# Check other entities
	if entities_manager:
		for ent in entities_manager.get_children():
			if ent != self and ent.get("spook_radius") != null:
				var edx: float = ent.position.x - position.x
				var edy: float = ent.position.y - position.y
				var edist: float = sqrt(edx*edx + edy*edy)
				if edist < ent.spook_radius:
					return "entity"

	return ""


var _scared_reported := false

# Q-10 juice + Q-12 proof: squawk and feathers on any scare; only a
# player-caused scare counts toward the capability proof (via the sim verb).
func _on_scared(cause: String) -> void:
	if _scared_reported:
		return
	_scared_reported = true
	if cause == "player":
		farm.apply_action({ "verb": "crow_scared", "actor": "crow" }, GameState)
	if get_tree():
		var main = get_tree().get_first_node_in_group("Main")
		if main and main.has_method("spawn_particles"):
			main.spawn_particles("feathers", position)
		if get_tree().root.has_node("AudioManager"):
			get_tree().root.get_node("AudioManager").play_sfx("squawk")


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			# animals.png cells: 8 perched, 9 wings up, 10 wings down
			var cell := 8
			if state == "flying_in" or state == "flying_away":
				cell = 9 if flap_state == 0 else 10
			canvas.draw_texture_rect_region(
				SPRITES,
				Rect2(position.x - TILE_SIZE / 2.0, position.y - TILE_SIZE / 2.0, TILE_SIZE, TILE_SIZE),
				Rect2(cell * 16, 0, 16, 16))
	})

# Four photographs of the live farmhouse and yard for Q-108. Needs a display:
#   godot --path . res://tools/capture_through_walls.tscn --treatment=none
# Repeat with haze, desaturate, hardcut. All runs use the same seed and hour.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/through_walls"
const TREATMENTS := ["none", "haze", "desaturate", "hardcut"]
const FARM_SEED := 1082026
const DAY_CYCLE = preload("res://systems/day_cycle.gd")

var treatment := ""
var farm: Node2D
var overlay: Node2D


func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--treatment="):
			treatment = arg.trim_prefix("--treatment=")
	if treatment not in TREATMENTS:
		push_error("Give --treatment=none|haze|desaturate|hardcut")
		get_tree().quit(1)
		return

	# main.gd's one entropy draw is reproducible when the engine RNG is seeded.
	seed(FARM_SEED)
	var gs = get_tree().root.get_node("GameState")
	gs.pending_load = false
	gs.save_path = "user://capture_through_walls_scratch.json"
	gs.replay_path = "user://capture_through_walls_scratch_replay.json"
	gs.trace_path = "user://capture_through_walls_scratch_trace.jsonl"
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	farm = main.farm
	main.hud.visible = false
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false
	gs.set_energy(gs.max_energy)

	var door := Vector2i(-1, -1)
	for pair in WorldLayout.doors_of_world():
		var at: Vector2i = pair.get("at", Vector2i(-1, -1))
		if at.x >= 0 and farm.get_object(at.x, at.y) == WorldLayout.HOUSE_DOOR:
			door = at
			break
	if door.x < 0:
		push_error("Farmhouse door is absent")
		get_tree().quit(1)
		return
	var doorstep := door + Vector2i(0, 1)
	farm.sim.set_actor_pos("player", doorstep)
	main.player.init_position(doorstep.x, doorstep.y)
	main.player.path.clear()
	main.player.pending_action = {}
	for i in 6:
		await get_tree().process_frame
	main.player._execute_resolved_action({ "action": "use_door", "target_t": door })
	for i in 90:
		await get_tree().process_frame
	if farm.sim.room_of_cell(farm.sim.actor_pos("player")) == "" or not farm._backdrop_active:
		push_error("Player did not enter the farmhouse")
		get_tree().quit(1)
		return
	# The glide and camera easing depend on frame time. Snap to the same final
	# indoor view before each shutter, then hold the sim and sprite still.
	main._door_glide = {}
	main.camera.zoom = Vector2(main.CAMERA_SCALE, main.CAMERA_SCALE)
	main.camera.position = Vector2.ZERO
	main.camera.position_smoothing_enabled = false
	main.camera.reset_smoothing()
	main.set_process(false)
	main.player.set_process(false)

	# This layer holds the live farm texture and sits under the room. Painting here
	# changes only what is visible beyond the room, never the room's own pixels.
	overlay = Node2D.new()
	overlay.name = "Q108YardTreatment"
	overlay.draw.connect(_draw_treatment)
	farm._backdrop_layer.add_child(overlay)
	if treatment == "desaturate":
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; render_mode blend_mix; void fragment() { vec4 c = texture(TEXTURE, UV); float g = dot(c.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(mix(c.rgb, vec3(g), 0.62) * 0.76, c.a); }"
		var mat := ShaderMaterial.new()
		mat.shader = shader
		farm._backdrop_node.material = mat
	overlay.queue_redraw()
	for i in 8:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var file := "%s/%s.png" % [OUT_DIR, treatment]
	var err := get_viewport().get_texture().get_image().save_png(file)
	if err != OK:
		push_error("Could not save %s: %s" % [file, error_string(err)])
		get_tree().quit(1)
		return
	print("captured -> %s (seed %d, energy %d, room %s)" % [file, FARM_SEED,
		gs.energy, str(farm._backdrop_own)])
	get_tree().quit(0)


func _draw_treatment() -> void:
	if treatment == "none":
		return
	overlay.draw_set_transform(farm._backdrop_offset, 0.0,
		Vector2(farm._backdrop_pitch, farm._backdrop_pitch))
	var size: Vector2 = Vector2(farm._backdrop_view.size)
	if treatment == "haze":
		# The four-by-four ordered dither used by the game's day cycle, at art-pixel pitch.
		for y in int(size.y):
			for x in int(size.x):
				if DAY_CYCLE.BAYER4[y % 4][x % 4] < 5:
					overlay.draw_rect(Rect2(x, y, 1, 1), Color(0.87, 0.92, 0.88, 0.65))
	elif treatment == "desaturate":
		pass # The shader is attached to the live backdrop texture above.
	elif treatment == "hardcut":
		# Frame an opening around the house's footprint in farm-page coordinates.
		# The prior rig used the 512x320 page centre, far outside this room's view.
		var own: Rect2i = farm._backdrop_own
		var opening := Rect2(Vector2(own.position) * float(farm.TILE_SIZE) - Vector2(12, 12),
			Vector2(own.size) * float(farm.TILE_SIZE) + Vector2(24, 24))
		var wall: Texture2D = farm.interior_wall_texture
		overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		overlay.draw_texture_rect(wall, Rect2(0, 0, size.x, opening.position.y), true)
		overlay.draw_texture_rect(wall, Rect2(0, opening.end.y, size.x, size.y - opening.end.y), true)
		overlay.draw_texture_rect(wall, Rect2(0, opening.position.y, opening.position.x, opening.size.y), true)
		overlay.draw_texture_rect(wall, Rect2(opening.end.x, opening.position.y,
			size.x - opening.end.x, opening.size.y), true)

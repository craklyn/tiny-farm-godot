# capture_coop.gd — the chicken coop on the farm, dry and wet (2026-09-11)
#
# The `capture_workbench.gd` pattern. Needs a display:
#   godot --path . res://tools/capture_coop.tscn
#
# Writes `tools/shot_coop_dry.png` and `tools/shot_coop_wet.png`: the hut standing
# on its four squares with the hen out in the yard, and then the same farm with the
# weather turned and the hen sitting in the doorway. The shots are a developer's
# look at the screen and are **not committed** — regenerate them whenever the coop
# or the hen's shelter changes.
extends Node2D


func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.gold = 2000

	# Scratch paths, for `capture_workbench.gd`'s hard-won reason: main.gd
	# autosaves while this runs, and a capture tool must not leave a staged farm
	# in the player's own session.
	gs.save_path = "user://capture_coop_scratch.json"
	gs.replay_path = "user://capture_coop_scratch_replay.json"
	gs.trace_path = "user://capture_coop_scratch_trace.jsonl"

	var here: Vector2i = main.farm.sim.actor_pos("player")
	var spot := _free_block(main, here)
	if spot.x < 0:
		print("no four-square block free near the farmer; nothing captured")
		get_tree().quit(1)
		return
	gs.machines["coop"] = 1
	main.farm.apply_action({
		"verb": "place", "target": spot, "item": "coop", "actor": "player" }, gs)
	main.farm.queue_redraw()
	for i in 10:
		await get_tree().process_frame

	gs.weather = "sunny"
	gs.weather_changed.emit(gs.weather)
	await _settle(main, 240)
	get_viewport().get_texture().get_image().save_png("res://tools/shot_coop_dry.png")

	gs.weather = "rainy"
	gs.weather_changed.emit(gs.weather)
	main.farm.sim.schedule_all_brains()
	await _settle(main, 900)
	get_viewport().get_texture().get_image().save_png("res://tools/shot_coop_wet.png")

	print("captured -> tools/shot_coop_dry.png, tools/shot_coop_wet.png (coop at %s, hen at %s)"
		% [spot, main.farm.sim.actor_pos("chicken")])
	get_tree().quit(0)


# Let the sim run the given number of ticks, then let the renderer catch up.
#
# The second half matters and cost a confusing screenshot to learn: a slice of 20
# ticks is two seconds of sim time spent in one frame, while `entities/chicken.gd`
# slides her sprite toward the tile the sim put her on at twenty pixels a second.
# Fast-forward the sim and the picture is of where she *was* — a hen standing
# outside a coop the sim says she is sitting in. The plain frames at the end are
# the sprite walking the rest of the way.
func _settle(main, ticks: int) -> void:
	var slice := 20
	for i in int(ticks / slice):
		main.farm.sim.advance_ticks(slice, get_tree().root.get_node("GameState"))
		main.farm.queue_redraw()
		await get_tree().process_frame
	for i in 240:
		await get_tree().process_frame


func _free_block(main, near: Vector2i) -> Vector2i:
	for r in range(2, 9):
		for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(r, r),
				Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, -r)]:
			if main.farm.sim.placeable_at(near + d, "coop"):
				return near + d
	return Vector2i(-1, -1)

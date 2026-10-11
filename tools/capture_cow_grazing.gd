# capture_cow_grazing.gd — the herd outside the creamery after giving milk
#
# Loads a saved farm into the real game, frames its first barn and the field
# around it, and saves one PNG when the farm opens and one after `--seconds` of
# play. Made for the fix to cows stacking on the barn's doorstep (2026-10-10): a
# farm saved just after four cows had each given milk shows all four on one
# square at the start, and the field shows where they went by the end.
#
#   godot --path . res://tools/capture_cow_grazing.tscn -- --save=<farm.json> --out=<prefix> [--seconds=40]
#
# Needs a display. Writes <prefix>_start.png and <prefix>_end.png, and prints
# where each cow stood at both moments. Plays on a scratch copy of the farm, so
# the game's autosave never writes over the file it was given.
extends Node2D

const SCRATCH := "user://capture_cow_grazing.json"


func _ready() -> void:
	var opts := {"seconds": "40"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			opts[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	if not opts.has("save") or not opts.has("out"):
		print("usage: -- --save=<farm.json> --out=<prefix> [--seconds=40]")
		get_tree().quit(1)
		return
	DirAccess.copy_absolute(String(opts.save), ProjectSettings.globalize_path(SCRATCH))
	GameState.save_path = SCRATCH
	GameState.replay_path = "user://capture_cow_grazing_replay.json"
	GameState.trace_path = "user://capture_cow_grazing_trace.jsonl"
	GameState.pending_load = true
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	main.hud.visible = false
	var overlay := get_node_or_null("/root/BuildOverlay")
	if overlay != null:
		overlay.visible = false
	GameState.weather = "sunny"
	GameState.weather_changed.emit(GameState.weather)
	var sim: SimWorld = main.farm.sim
	var ids: Array = sim.barns.keys(); ids.sort()
	if ids.is_empty():
		print("this farm has no barn; nothing captured")
		get_tree().quit(1)
		return
	var raw: Array = sim.barns[ids[0]]["anchor"]
	var anchor := Vector2i(int(raw[0]), int(raw[1]))
	var cam: Camera2D = main.camera
	cam.limit_left = -100000; cam.limit_top = -100000
	cam.limit_right = 100000; cam.limit_bottom = 100000
	cam.top_level = true
	# Centred below the barn, but kept on the farm's own page so no dark margin shows.
	var zoom := 2.5
	var half := get_viewport().get_visible_rect().size / (2.0 * zoom)
	var page := Vector2(SimWorld.MAP_WIDTH, WorldLayout.PAGE_ROWS) * 16.0
	cam.global_position = Vector2(clampf(anchor.x * 16 + 24, half.x, page.x - half.x),
		clampf(anchor.y * 16 + 40, half.y, page.y - half.y))
	cam.zoom = Vector2(zoom, zoom)
	cam.reset_smoothing()
	await _frames(20)
	await _shot(String(opts.out) + "_start.png")
	_report(sim, "start")
	await _frames(int(float(opts.seconds) * 60.0))
	await _shot(String(opts.out) + "_end.png")
	_report(sim, "after %ss" % opts.seconds)
	get_tree().quit(0)


func _report(sim: SimWorld, moment: String) -> void:
	var where := []
	for cow_id in sim.actors_of_species(SpeciesDefs.COW):
		where.append("%s %s %s" % [cow_id, sim.actor_pos(cow_id), sim.actor(cow_id).extra.get("state", "")])
	print("%s: %s" % [moment, ", ".join(where)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

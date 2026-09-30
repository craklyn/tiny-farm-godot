# capture_thin_walls.gd — every candidate room edge (Q-135) in the real game
#
# Needs a display. Run once per room:
#   godot --path . res://tools/capture_thin_walls.tscn --room=tower
#   godot --path . res://tools/capture_thin_walls.tscn --room=coop
# then compose the side-by-side:
#   python3 tools/compose_thin_walls.py
#
# Writes docs/design/mockups/thin_walls/<room>_<style>.png for every style in
# `RoomEdgeStyle.STYLES`, with identical framing: same seed, same spot, the farmer
# on the same cell, the camera snapped to its resting place and the sim held still
# between shutters, so the only thing that changes from one picture to the next is
# the edge.
#
# `tower` is the Spiral Tower's own 2x2 room at pitch 1/2 — the room the thin edge
# ships in. `coop` is the chicken coop's room at pitch 3 **with its one-cell wall
# ring floored over and the thin edge drawn instead**, done here in the capture and
# nowhere else: it shows how each style reads at the finest room scale the game
# has, and is not a change to the coop.
#
# Saves go to scratch paths, never the player's autosave; the farm is a fresh one
# from a fixed seed, never her saved farm.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/thin_walls"
const FARM_SEED := 29092026
const ROOMS := ["tower", "coop"]

var room := ""


func _ready() -> void:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			room = arg.trim_prefix("--room=")
	if room not in ROOMS:
		push_error("Give --room=tower or --room=coop")
		get_tree().quit(1)
		return

	seed(FARM_SEED)
	var gs = get_tree().root.get_node("GameState")
	gs.pending_load = false
	gs.save_path = "user://capture_thin_walls_scratch.json"
	gs.replay_path = "user://capture_thin_walls_scratch_replay.json"
	gs.trace_path = "user://capture_thin_walls_scratch_trace.jsonl"
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var farm = main.farm
	gs.gold = 2000
	gs.set_energy(gs.max_energy)
	main.hud.visible = false
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false

	# The same cleared patch every run, whatever the seed put there.
	var item := "spiral_tower" if room == "tower" else "coop"
	var spot := Vector2i(15, 11)
	for cell in MachineDefs.footprint_cells(item, spot):
		farm.sim.set_tile_state(cell.x, cell.y, "cleared")
		farm.sim.set_object(cell.x, cell.y, "")
	gs.machines[item] = 1
	var laid: Dictionary = farm.apply_action({
		"verb": "place", "target": spot, "item": item, "actor": "player" }, gs)
	main.menus.close_menu()
	if not laid.get("ok", false) or not laid.has("room"):
		push_error("Could not place the %s: %s" % [item, str(laid)])
		get_tree().quit(1)
		return
	var id: String = laid["room"]
	var r: Dictionary = farm.sim.rooms[id]

	var door_tile := spot + Vector2i(1, 0) if room == "tower" else spot
	var outside := spot + Vector2i(1, 1) if room == "tower" else spot + Vector2i(0, 1)
	farm.sim.set_actor_pos("player", outside)
	main.player.init_position(outside.x, outside.y)
	for i in 10:
		await get_tree().process_frame
	main.player._execute_resolved_action({ "action": "use_door", "target_t": door_tile })
	for i in 90:
		await get_tree().process_frame
	if farm.sim.room_of_cell(farm.sim.actor_pos("player")) != id:
		push_error("The farmer did not go inside")
		get_tree().quit(1)
		return

	var origin: Vector2i = r["origin"]
	var size: Vector2i = r["size"]
	if room == "coop":
		# Floor the ring over and let the thin edge stand where it stood.
		for y in size.y:
			for x in size.x:
				farm.sim.set_tile_state(origin.x + x, origin.y + y, WorldLayout.FLOOR)
		r["edge_walls"] = true
	# She stands away from the door so the gap is in plain view.
	var stand := origin + (Vector2i(0, 0) if room == "tower" else Vector2i(1, 2))
	farm.sim.set_actor_pos("player", stand)
	main.player.init_position(stand.x, stand.y)
	main.player.path.clear()
	main.player.pending_action = {}
	for i in 10:
		await get_tree().process_frame
	main._door_glide = {}
	main.camera.zoom = Vector2(main.CAMERA_SCALE, main.CAMERA_SCALE)
	main.camera.position = Vector2.ZERO
	main.camera.position_smoothing_enabled = false
	main.camera.reset_smoothing()
	main.set_process(false)
	main.player.set_process(false)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for style in RoomEdgeStyle.STYLES:
		RoomEdgeStyle.override = style
		farm.queue_redraw()
		for i in 6:
			await get_tree().process_frame
		var file := "%s/%s_%s.png" % [OUT_DIR, room, style]
		var err: int = get_viewport().get_texture().get_image().save_png(file)
		if err != OK:
			push_error("Could not save %s: %s" % [file, error_string(err)])
			get_tree().quit(1)
			return
		print("captured -> %s" % file)
	RoomEdgeStyle.override = ""
	# Where the room landed on screen, for the side-by-side's crop.
	var box := Rect2(Vector2(origin * farm.TILE_SIZE), Vector2(size * farm.TILE_SIZE))
	var on_screen: Transform2D = farm.get_global_transform_with_canvas()
	var a: Vector2 = on_screen * box.position
	var b: Vector2 = on_screen * box.end
	var frame := FileAccess.open("%s/%s_frame.json" % [OUT_DIR, room], FileAccess.WRITE)
	frame.store_string(JSON.stringify({ "room": [a.x, a.y, b.x, b.y],
		"pitch": float(r["pitch"]), "cells": [size.x, size.y] }) + "\n")
	frame.close()
	print("room %s at pitch %s, floor %s, farmer on %s" % [id, str(r["pitch"]),
		str(size), str(stand - origin)])
	get_tree().quit(0)

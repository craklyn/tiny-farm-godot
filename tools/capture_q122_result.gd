# Before/after evidence for Q-122 (card w1f2bb35bd5d): the rock at ten colours
# and the redrawn fox, same seed, same camera, same tile positions in both
# shots so the only thing that differs between "before" and "after" is the
# two sprite files on disk.
#
# The fox has no actor, brain or registry row (`hq/data/entities.json`: "pure
# potential") — nothing in the game ever draws it — so it cannot be captured
# "in game" the way the rock (a real, seeded obstacle) can. It is drawn here at
# 1:1, unfiltered, the exact way `entities/chicken.gd` draws an actor's cell
# onto the farm, so the comparison is still the real renderer and the real
# import pipeline, just without a gameplay reason for the sprite to be there.
#
# Run once with the OLD obstacle_rock.png/fox.png on disk (re-import between
# swaps: `godot --headless --path . --import`) and once with the NEW ones:
#   xvfb-run -a godot --path . res://tools/capture_q122_result.tscn -- --tag=before
#   xvfb-run -a godot --path . res://tools/capture_q122_result.tscn -- --tag=after
extends Node2D

const OUT_DIR := "res://docs/design/mockups/q122_result/"
const FOX_TEX := preload("res://assets/sprites/generated/fox.png")
const TILE_SIZE := 16

func _tag() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			return a.substr(6)
	return "shot"

func _ready() -> void:
	seed(12345)  # same fixed world every run (test_visuals.gd's regression seed)
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var gs = get_tree().root.get_node("GameState")
	gs.save_path = "user://capture_q122_scratch.json"
	gs.replay_path = "user://capture_q122_scratch_replay.json"
	gs.trace_path = "user://capture_q122_scratch_trace.jsonl"
	main.hud.visible = false
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false

	var here: Vector2i = main.farm.sim.actor_pos("player")
	var rock_tile: Vector2i = here + Vector2i(3, 1)
	var fox_tile: Vector2i = here + Vector2i(6, 1)

	# A clean, deterministic patch for the rock — independent of whatever the
	# procedural scatter (systems/world_layout.gd) put on these two tiles.
	main.farm.sim.set_tile_state(rock_tile.x, rock_tile.y, "cleared")
	main.farm.sim.set_object(rock_tile.x, rock_tile.y, "obstacle_rock")
	main.farm.sim.set_tile_state(fox_tile.x, fox_tile.y, "cleared")
	main.farm.sim.set_object(fox_tile.x, fox_tile.y, "")
	main.farm.queue_redraw()

	# The fox sprite, drawn exactly the way an actor's cell is drawn
	# (`entities/chicken.gd queue_render`: 1:1, unfiltered, top-left at the
	# tile's world pixel position) — presentation only, no sim actor, no gateway
	# verb, so this never claims the fox is a creature the game simulates today.
	var fox_sprite := Sprite2D.new()
	fox_sprite.texture = FOX_TEX
	fox_sprite.centered = false
	fox_sprite.position = Vector2(fox_tile.x * TILE_SIZE, fox_tile.y * TILE_SIZE)
	main.farm.add_child(fox_sprite)

	main.farm.sim.set_actor_pos("player", here)
	main.player.init_position(here.x, here.y)
	main.camera.position_smoothing_enabled = false

	for i in 40:
		await get_tree().process_frame

	var tag := _tag()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "farm_%s.png" % tag)
	print("captured %s: rock at %s, fox at %s" % [tag, str(rock_tile), str(fox_tile)])
	get_tree().quit(0)

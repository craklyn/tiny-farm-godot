# capture_boot_bloom.gd — three PNGs of the Q-103 boot sequence for review:
# the splash's own frame, partway through the rise, and the menu settled in.
# Needs a display: godot --path . res://tools/capture_boot_bloom.tscn
#
# Scratch only — writes to tools/boot_bloom_shots/, which is gitignored, and
# is not part of either test suite.
extends Node2D

const OUT_DIR := "res://tools/boot_bloom_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Added under the tree's root, not this Node2D: title_screen.tscn's root is
	# a Control anchored full-rect against the viewport, which is how
	# `run/main_scene` shows it in the real game. Parenting it under a Node2D
	# instead (as most of the integration suite's own title_screen scenarios
	# do, where only button *presence* is ever asserted) leaves its anchors
	# resolving against that Node2D's own empty rect, and every card lands
	# pinned to the top-left corner instead of centred — a capture-rig
	# artifact worth avoiding for a screenshot meant to show the real layout.
	# Scenario K (`tools/test_runner.gd`) already uses this same fix.
	var title = load("res://ui/title_screen.tscn").instantiate()
	get_tree().root.add_child.call_deferred(title)
	await get_tree().process_frame
	await get_tree().process_frame
	_shoot("0_splash")

	await get_tree().create_timer(1.1).timeout  # partway through the rise
	_shoot("1_mid_rise")

	await get_tree().create_timer(1.6).timeout  # settled: title, menu, farm all in
	_shoot("2_menu_settled")

	print("done")
	get_tree().quit(0)


func _shoot(name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("wrote ", path)

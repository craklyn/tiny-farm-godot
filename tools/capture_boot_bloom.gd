# capture_boot_bloom.gd — four PNGs of the Q-103 boot sequence for review: the
# icon plate the engine holds while the game loads, the bloom's own first frame
# once the plate has dissolved off it, partway through the rise, and the menu
# settled in.
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
	_shoot("0_icon_plate")

	# The plate leaves when the game is live under it, which is a measured
	# moment and not a fixed one — on a loaded machine it is seconds later than
	# on a quiet one. So this watches for the node to go rather than timing it,
	# and only the waits *after* it are read off the title screen's own
	# constants, so retiming the boot retimes these shots with it.
	var T := load("res://ui/title_screen.gd")
	while title.get_node_or_null("BootPlate") != null:
		await get_tree().process_frame
	await get_tree().process_frame
	_shoot("1_bud")

	var into_rise: float = T.BLOOM_HOLD_SEC + 0.7
	await get_tree().create_timer(into_rise).timeout  # partway through the rise
	_shoot("2_mid_rise")

	# The rest of the rise, the linger on the bloomed flower, and the reveal:
	# the flower dissolving into the farm, then the menu settling onto it.
	var rest: float = _rise_seconds() - 0.7 + T.BLOOM_LINGER_SEC \
		+ T.BLOOM_MENU_DELAY_SEC + T.BLOOM_TITLE_FADE_SEC + 0.4
	await get_tree().create_timer(rest).timeout  # settled: title, menu, farm all in
	_shoot("3_menu_settled")

	print("done")
	get_tree().quit(0)


# The bloom's rise, as its manifest gives it.
func _rise_seconds() -> float:
	var f := FileAccess.open("res://assets/anim/sunflower_bloom/manifest.json", FileAccess.READ)
	if f == null:
		return 1.44
	var m = JSON.parse_string(f.get_as_text())
	if not (m is Dictionary):
		return 1.44
	return int(m.get("frame_count", 16)) * int(m.get("ms_per_frame", 90)) / 1000.0


func _shoot(name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("wrote ", path)

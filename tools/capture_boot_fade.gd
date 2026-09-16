# capture_boot_fade.gd — a strip through the hand-off from the bloom to the
# menu, for judging how the transition reads (the designer asked, 2026-09-15,
# "what do you think about a fade between the flower animation and the main
# landing page?"). Shoots every 0.2 s from the moment the flower's linger ends.
#
# Scratch only — writes to tools/boot_bloom_shots/, which is gitignored.
extends Node2D

const OUT_DIR := "res://tools/boot_bloom_shots/fade"
const STEP := 0.2
const SHOTS := 9


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var title = load("res://ui/title_screen.tscn").instantiate()
	get_tree().root.add_child.call_deferred(title)
	await get_tree().process_frame
	await get_tree().process_frame

	# Wait out the plate, then the bloom's own hold and rise and linger, so the
	# strip starts on the frame the reveal starts on.
	while title.get_node_or_null("BootPlate") != null:
		await get_tree().process_frame
	var T := load("res://ui/title_screen.gd")
	var to_reveal: float = T.BLOOM_HOLD_SEC + (T.BLOOM_LINGER_SEC as float)
	to_reveal += _rise_seconds()
	await get_tree().create_timer(to_reveal).timeout

	for i in SHOTS:
		_shoot("t%02d_%.1fs" % [i, i * STEP])
		await get_tree().create_timer(STEP).timeout

	print("done")
	get_tree().quit(0)


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
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("wrote ", name)

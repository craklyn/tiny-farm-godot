# capture_watering_inset.gd — one-off frame capture of the watering shot
# (Q-104), the capture_t39.gd pattern. Needs a display:
#   godot --path . res://tools/capture_watering_inset.tscn
#
# Drives the neighbour's actual first cold-open `water` Action through the
# gateway (`ColdOpen.next_action` + `farm.apply_action`, exactly what
# `main.gd`'s own real-time pacer would do a beat later) so what is captured
# is the shipping presentation reacting to a real recorded Action, not a mock.
extends Node2D

func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var farm = main.farm

	# Review evidence, not debug output — same cleanup capture_t39.gd does.
	if main.hud != null and main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	var build_overlay := get_node_or_null("/root/BuildOverlay")
	if build_overlay != null:
		build_overlay.visible = false

	var act: Dictionary = ColdOpen.next_action(farm.sim, GameState)
	if String(act.get("verb", "")) != "water":
		push_error("cold open's first action was not a water (got %s) — capture is stale" % str(act))
		get_tree().quit(1)
		return
	var res: Dictionary = farm.apply_action(act, GameState)
	if not res.get("ok", false):
		push_error("neighbour's first water was refused in capture: %s" % str(res))
		get_tree().quit(1)
		return

	# Past the 0.4s fade-up, mid-way through the loop's one pass.
	await get_tree().create_timer(0.6).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/shot_watering_inset.png")
	print("captured -> tools/shot_watering_inset.png")
	get_tree().quit(0)

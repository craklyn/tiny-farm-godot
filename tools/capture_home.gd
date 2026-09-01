# capture_home.gd — one-off frame capture of the home screen (T-37), the
# test_visuals.gd pattern. Needs a display:
#   godot --path . res://tools/capture_home.tscn
extends Node2D

func _ready() -> void:
	var home = load("res://ui/home_screen.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/home_capture.png")
	print("captured -> tools/home_capture.png")
	get_tree().quit(0)

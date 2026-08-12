extends Control

func _ready() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		start_game()
	elif event is InputEventScreenTouch and event.pressed:
		start_game()
	elif event.is_action_pressed("ui_accept"):
		start_game()

func start_game() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://main.tscn")

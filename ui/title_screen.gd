extends Control

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		start_game()
	elif event is InputEventScreenTouch and event.pressed:
		accept_event()
		start_game()
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		start_game()

func start_game() -> void:
	print("Starting game...")
	InputManager.has_click = false
	AudioManager.play_sfx("click")
	var err = get_tree().change_scene_to_file("res://main.tscn")
	if err != OK:
		print("Failed to change scene! Error code: ", err)

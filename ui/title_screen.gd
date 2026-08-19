extends Control

@onready var start_label: Label = $VBoxContainer/StartLabel
@onready var new_farm_button: Button = $VBoxContainer/NewFarmButton

var _has_save := false


func _ready() -> void:
	_has_save = FileAccess.file_exists(GameState.save_path)
	start_label.text = "Tap Anywhere to Continue" if _has_save else "Tap Anywhere to Start"
	new_farm_button.visible = _has_save
	new_farm_button.pressed.connect(_on_new_farm)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		start_game(_has_save)
	elif event is InputEventScreenTouch and event.pressed:
		accept_event()
		start_game(_has_save)
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		start_game(_has_save)


func _on_new_farm() -> void:
	start_game(false)


func start_game(load_save: bool) -> void:
	print("Starting game... (continue=%s)" % load_save)
	GameState.pending_load = load_save
	InputManager.has_click = false
	AudioManager.play_sfx("click")
	var err = get_tree().change_scene_to_file("res://main.tscn")
	if err != OK:
		print("Failed to change scene! Error code: ", err)

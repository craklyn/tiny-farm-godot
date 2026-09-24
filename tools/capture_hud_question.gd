# Capture the two live HUD presentations at the same farm state for the
# separate basket-pictures question. The can gauge is already ruled by Q-78.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/hud_pictures"

func _ready() -> void:
	seed(7322026)
	GameState.use_slot(1, "user://capture_hud_scratch/")
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false
	if main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	if main.hud.notes_toggle != null:
		main.hud.notes_toggle.visible = false
	GameState.pouch["wheat"] = 2
	GameState.pouch["tomato"] = 1
	GameState.watering_can_charges = 4
	GameState.set_energy(GameState.max_energy)
	main.player.set_process(false)
	main.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var shots: Array[Image] = []
	for setting in [StationPresentation.SATISFIED_NOUN, StationPresentation.SATISFIED_CHIP]:
		StationPresentation.set_satisfied(setting)
		main.hud._update_hud()
		main._apply_station_treatment()
		for i in 4:
			await get_tree().process_frame
		var shot := get_viewport().get_texture().get_image()
		var name := "current_words" if setting == StationPresentation.SATISFIED_NOUN else "basket_pictures"
		var err := shot.save_png("%s/%s.png" % [OUT_DIR, name])
		if err != OK:
			push_error("HUD capture failed: %s" % error_string(err))
			get_tree().quit(1)
			return
		shots.append(shot)
	var width := shots[0].get_width()
	var height := shots[0].get_height()
	var pair := Image.create_empty(width * 2, height, false, Image.FORMAT_RGBA8)
	pair.blit_rect(shots[0], Rect2i(0, 0, width, height), Vector2i.ZERO)
	pair.blit_rect(shots[1], Rect2i(0, 0, width, height), Vector2i(width, 0))
	var err := pair.save_png("%s/side_by_side.png" % OUT_DIR)
	if err != OK:
		push_error("HUD pair failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	StationPresentation.set_satisfied(StationPresentation.SATISFIED_SHIPPED)
	print("Captured the two real HUD states side by side (%dx%d each)." % [width, height])
	get_tree().quit(0)

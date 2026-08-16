extends Node
func _ready():
	print("Test runtime ready.")
	var title_screen = get_tree().root.get_node_or_null("TitleScreen")
	if title_screen:
		print("TitleScreen found. Emitting button pressed.")
		title_screen.get_node("StartButton").pressed.emit()
		await get_tree().create_timer(1.0).timeout
		print("Tree after press: ", get_tree().root.get_children())
	else:
		print("TitleScreen NOT found!")
	get_tree().quit()

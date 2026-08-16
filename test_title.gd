extends SceneTree

func _init():
	print("Starting test...")
	var title_screen_pack = load("res://ui/title_screen.tscn")
	var title_screen = title_screen_pack.instantiate()
	root.add_child(title_screen)
	
	print("Title screen instantiated.")
	var btn = title_screen.get_node("StartButton")
	if btn:
		print("Found StartButton, emitting pressed...")
		btn.pressed.emit()
	else:
		print("StartButton not found!")
	
	await create_timer(1.0).timeout
	
	var main = root.get_node_or_null("Main")
	if main:
		print("Main scene is running!")
	else:
		print("Main scene NOT found. Children of root: ")
		for c in root.get_children():
			print("- ", c.name)
	
	quit()

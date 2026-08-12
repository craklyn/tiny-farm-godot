extends SceneTree
func _init():
	var es = ResourceLoader.load("/home/daniel/.config/godot/editor_settings-4.tres")
	for prop in es.get_property_list():
		if "android" in prop.name.to_lower() or "java" in prop.name.to_lower() or "jdk" in prop.name.to_lower():
			print(prop.name)
	quit()

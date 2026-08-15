@tool
extends EditorScript
func _run():
	var settings = get_editor_interface().get_editor_settings()
	for p in settings.get_property_list():
		if "android" in p.name:
			print(p.name, " = ", settings.get(p.name))

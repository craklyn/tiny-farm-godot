extends SceneTree

func _init():
	var settings = EditorInterface.get_editor_settings()
	if settings:
		settings.set_setting("export/android/android_sdk_path", "/home/daniel/Android/Sdk")
		settings.set_setting("export/android/debug_keystore", "/home/daniel/tiny-farm-godot/debug.keystore")
		settings.set_setting("export/android/debug_keystore_user", "androiddebugkey")
		settings.set_setting("export/android/debug_keystore_pass", "android")
		settings.save()
		print("Android settings saved!")
	else:
		print("Could not get EditorSettings")
	quit()

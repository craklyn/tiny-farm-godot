@tool
extends EditorScript

func _run():
	var settings = get_editor_interface().get_editor_settings()
	settings.set("export/android/android_sdk_path", "/home/daniel/Android/Sdk")
	settings.set("export/android/debug_keystore", "/home/daniel/.android/debug.keystore")
	settings.set("export/android/debug_keystore_user", "androiddebugkey")
	settings.set("export/android/debug_keystore_pass", "android")
	
	settings.save()
	print("Android editor settings configured successfully!")

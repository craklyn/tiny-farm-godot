@tool
extends EditorScript

func _run():
	var settings = get_editor_interface().get_editor_settings()
	var os_name = "Android"
	
	print("SDK path: ", settings.get("export/android/android_sdk_path"))
	print("Java path: ", settings.get("export/android/java_sdk_path"))
	print("Keystore: ", settings.get("export/android/debug_keystore"))
	print("Keystore User: ", settings.get("export/android/debug_keystore_user"))
	print("Keystore Pass: ", settings.get("export/android/debug_keystore_pass"))


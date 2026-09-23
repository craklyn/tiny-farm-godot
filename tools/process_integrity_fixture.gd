extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		finish(2, "fixture needs a mode")
		return
	match args[0]:
		"isolation":
			isolation(args)
		"green_hang":
			print("Results: 1 PASSED, 0 FAILED")
			hang()
		"status_green_hang":
			print("Results: PASSED")
			hang()
		"timing_failure":
			print("Results: 0 PASSED, 1 FAILED")
			hang()
		"status_failure":
			print("Results: FAILED")
			hang()
		_:
			finish(2, "unknown fixture mode")


func isolation(args: PackedStringArray) -> void:
	if args.size() != 3:
		finish(2, "isolation needs a token and rendezvous directory")
		return
	var token := args[1]
	var rendezvous := args[2]
	DirAccess.make_dir_recursive_absolute(rendezvous)
	var canary := FileAccess.open("user://process-isolation-canary", FileAccess.WRITE)
	if canary == null:
		finish(2, "could not write user canary")
		return
	canary.store_string(token)
	canary.close()
	var marker := FileAccess.open(rendezvous.path_join(token), FileAccess.WRITE)
	if marker == null:
		finish(2, "could not write rendezvous marker")
		return
	marker.store_string(token)
	marker.close()
	var deadline := Time.get_ticks_msec() + 5000
	while DirAccess.get_files_at(rendezvous).size() < 2 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
	var saved := FileAccess.get_file_as_string("user://process-isolation-canary")
	if saved != token:
		finish(1, "user data leaked between concurrent Godot processes")
		return
	print("Results: PASSED")
	finish(0, "isolated " + token)


func hang() -> void:
	while true:
		OS.delay_msec(50)


func finish(code: int, message: String) -> void:
	print(message)
	quit(code)

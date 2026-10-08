# atomic_file.gd — replace a complete file without first emptying its old copy.
#
# The temporary file must sit beside the destination: a rename within one
# directory is atomic on the storage Godot supports, so an app killed before the
# rename still leaves the destination exactly as it was.
class_name AtomicFile
extends RefCounted


static func write_text(path: String, text: String, stop_before_replace: bool = false) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	# This test seam models Android ending the process after the new file reaches
	# storage but before the atomic rename. Production callers leave it false.
	if stop_before_replace:
		return false
	return DirAccess.rename_absolute(temp_path, path) == OK

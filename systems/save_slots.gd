# save_slots.gd — where each farm's files live (S-14)
#
# Three fixed farms, numbered 1 to 3, each one a directory of its own holding the
# same three file names the game has always written:
#
#   user://slot1/autosave.json   user://slot1/session_replay.json   user://slot1/session_trace.jsonl
#   user://slot2/...             user://slot3/...
#
# A slot is a **location, not a format**. Nothing here reads a byte of what is
# inside those files, so `SaveGame.VERSION` is untouched by slots existing and
# every tool that reads a save still reads exactly the file it always read — it
# is simply one directory further down. Choosing a slot is UI navigation and
# never an Action, so no verb is added to the gateway for it either.
#
# Every function takes the root it works under, defaulting to `user://`. That is
# what lets the suites exercise all of this — migration included — against a
# scratch directory instead of the developer's own farms.
class_name SaveSlots
extends RefCounted

const COUNT := 3
const ROOT := "user://"

const SAVE_FILE := "autosave.json"
const REPLAY_FILE := "session_replay.json"
const TRACE_FILE := "session_trace.jsonl"

# Which farm was played last, so the title screen opens on it and the attract
# loop plays it back. One number, kept beside the slots rather than inside one.
const LAST_PLAYED_FILE := "slots.json"

# What a single-slot install has sitting in `user://`, and what the migration
# below moves into slot 1. The `.bak` and `.unloadable` siblings are here because
# they are the two places the game has ever parked a farm it was about to replace
# (`ui/title_screen.gd` before a new farm, `main.gd` when a save will not load) —
# leaving them behind would orphan exactly the copies that exist to be recovered.
const LEGACY_FILES := [
	SAVE_FILE,
	REPLAY_FILE,
	TRACE_FILE,
	SAVE_FILE + ".bak",
	REPLAY_FILE + ".bak",
	SAVE_FILE + ".unloadable",
	REPLAY_FILE + ".unloadable",
]


static func clamp_slot(n: int) -> int:
	return clampi(n, 1, COUNT)


static func dir_for(n: int, root: String = ROOT) -> String:
	return root.path_join("slot%d" % clamp_slot(n))


static func save_path(n: int, root: String = ROOT) -> String:
	return dir_for(n, root).path_join(SAVE_FILE)


static func replay_path(n: int, root: String = ROOT) -> String:
	return dir_for(n, root).path_join(REPLAY_FILE)


static func trace_path(n: int, root: String = ROOT) -> String:
	return dir_for(n, root).path_join(TRACE_FILE)


# Android's `user://` is internal storage and the directory does not exist until
# something makes it (docs/DEPLOY.md). A missing directory turns every write in
# `main.gd`'s `persist_session` into a silent failure, so this is called before
# a slot is played rather than hoped for.
static func ensure_dir(n: int, root: String = ROOT) -> bool:
	return _ensure(dir_for(n, root))


# The same guarantee for one file, whatever slot it belongs to.
static func ensure_parent(path: String) -> bool:
	var dir := path.get_base_dir()
	if dir.is_empty():
		return true
	return _ensure(dir)


static func _ensure(dir: String) -> bool:
	if DirAccess.dir_exists_absolute(dir):
		return true
	return DirAccess.make_dir_recursive_absolute(dir) == OK


static func has_farm(n: int, root: String = ROOT) -> bool:
	return FileAccess.file_exists(save_path(n, root))


# --- Which farm was played last ----------------------------------------------

static func last_played_path(root: String = ROOT) -> String:
	return root.path_join(LAST_PLAYED_FILE)


# Slot 1 unless a previous session said otherwise. Anything unreadable reads as
# slot 1 too: the file is a convenience, and a farm must never be unreachable
# because a two-line preference went missing.
static func last_played(root: String = ROOT) -> int:
	var path := last_played_path(root)
	if not FileAccess.file_exists(path):
		return 1
	# Parsed through an instance rather than `JSON.parse_string`, which prints an
	# engine error on bad input. A garbled preference file is a thing this
	# function is expected to survive, not a fault to shout about in a log.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return 1
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return 1
	return clamp_slot(int(parsed.get("last_played", 1)))


static func remember(n: int, root: String = ROOT) -> bool:
	_ensure(root)
	var f := FileAccess.open(last_played_path(root), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({ "last_played": clamp_slot(n) }))
	return true


# --- Moving a single-slot install into slot 1 ---------------------------------
#
# Every build before slots wrote its farm straight into `user://`. On the first
# run of a build that has them, that farm has to end up in slot 1 — it is the
# farm somebody is in the middle of playing, and losing it is the one outcome
# this whole change is not allowed to have.
#
# The order is copy, verify, then remove, in that order and never another: a
# rename that half-succeeds on internal storage would leave slot 1 empty and the
# original gone. If the copy does not verify, the original stays exactly where it
# is and the file is reported as failed rather than quietly dropped.
#
# **It never overwrites a slot 1 file that already exists.** That can only happen
# if slot 1 has been played since the upgrade, in which case the file in `user://`
# is the older of the two and the one in slot 1 is the live farm. The root file is
# left alone rather than deleted, so nothing is destroyed by the safe branch either.
#
# Idempotent by construction: it works off what is in `user://`, and a second run
# finds nothing there.
#
# Returns {"moved": [...], "kept": [...], "failed": [...]} — file names, for the
# suites and for anyone reading a log.
static func migrate_legacy(root: String = ROOT) -> Dictionary:
	var out := { "moved": [], "kept": [], "failed": [] }
	var pending: Array[String] = []
	for name in LEGACY_FILES:
		if FileAccess.file_exists(root.path_join(name)):
			pending.append(String(name))
	if pending.is_empty():
		return out
	if not ensure_dir(1, root):
		out["failed"] = pending
		return out

	for name in pending:
		var from := root.path_join(name)
		var to := dir_for(1, root).path_join(name)
		if FileAccess.file_exists(to):
			out["kept"].append(name)
			continue
		if DirAccess.copy_absolute(from, to) != OK or not _same_size(from, to):
			out["failed"].append(name)
			continue
		if DirAccess.remove_absolute(from) != OK:
			# The farm is safe — it is in slot 1 — but the original is still in
			# `user://`, so the next run would try the move again and find the
			# destination taken, which is the harmless "kept" branch above.
			out["failed"].append(name)
			continue
		out["moved"].append(name)
	return out


# The verification half of copy-verify-remove. Length is what a truncated write
# gets wrong, and it costs two file opens rather than reading both files whole —
# which matters because a session trace is the biggest file the game writes.
static func _same_size(a: String, b: String) -> bool:
	var size_a := _size_of(a)
	return size_a >= 0 and size_a == _size_of(b)


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	return int(f.get_length())

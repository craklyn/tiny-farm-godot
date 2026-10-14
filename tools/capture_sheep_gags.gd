# capture_sheep_gags.gd — still pictures of what a stuck sheep does with forever
# (docs/design/18-sheep.md, "Stuck for good"), as PNGs under docs/design/mockups/sheep/.
# Needs a display:
#
#   godot --path . res://tools/capture_sheep_gags.tscn
#
# Staged the way the video shot `sheepgags` stages them (`tools/record_video_shots.gd`):
#   gags_stubble_two.png  two stuck sheep side by side on their first day, the grass
#                         round them grazed to stubble, the two rings joined
#   gags_bare_two.png     the same two a night on: bare earth, and a tuft past each ring
#   gags_bare_one.png     one sheep, her bald ring and her tuft
#   gags_stretch.png      her neck at full stretch toward the tuft
#   gags_smug.png         back where she started, looking smug
#   gags_bird.png         a bird just landed on her, and her heart
extends "res://tools/record_video_shots.gd"

const OUT := "res://docs/design/mockups/sheep/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scratch_paths()
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)

	var ids := await _stage_stuck_sheep("stubble", 2)
	await _seconds(0.5)
	await _shot(dir.path_join("gags_stubble_two.png"))
	for id in ids:
		farm.sim.actor(id)["extra"]["nights_content"] = 1
	await _seconds(0.5)
	await _shot(dir.path_join("gags_bare_two.png"))
	farm.sim.despawn_actor(ids[1])
	farm.sync_actors()
	var one := ids[0]
	_on_page_camera(_px(farm.sim.actor_pos(one)) + Vector2(8, -6), 5.0)
	await _seconds(0.5)
	await _shot(dir.path_join("gags_bare_one.png"))

	# The stretch: cued now, caught on its full-stretch frame, then on the smug one.
	SheepGags.cue(one, "stretch", farm.sim.clock.tick)
	await _wait_until(func(): return _frame_of(one) == SheepArt.STRETCH_FULL, 120)
	await _frames(1)
	await _shot(dir.path_join("gags_stretch.png"))
	await _wait_until(func(): return _frame_of(one) == SheepArt.STRETCH_SMUG, 120)
	await _frames(1)
	await _shot(dir.path_join("gags_smug.png"))

	# A bird, caught just after it lands while her heart is up.
	SheepGags.cue(one, "stretch", farm.sim.clock.tick + 100000)
	SheepGags.cue(one, "bird", farm.sim.clock.tick)
	await _wait_until(func(): return _landed(one), 200)
	await _seconds(0.3)
	await _shot(dir.path_join("gags_bird.png"))
	print("captured under ", dir)
	get_tree().quit(0)


func _frame_of(id: String) -> int:
	return SheepGags.stretch_frame(id, farm.sim.clock.tick)


func _landed(id: String) -> bool:
	var b := SheepGags.bird(id, farm.sim.clock.tick)
	return not b.is_empty() and not bool(b["flying"])

# Real-game sheep review: stage one look at a time; save untouched viewport pixels.
# The same rig runs on main and the candidate for matched before/after pictures.
extends "res://tools/record_video_shots.gd"

var out_dir := "/tmp/sheep-review/candidate"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_scratch_paths()
	if args.size() > 1 and args[1] == "squeeze":
		var passed := await _squeeze_review()
		get_tree().quit(0 if passed else 1)
		return
	var ids := await _stage_stuck_sheep("bare", 1)
	var at: Vector2i = farm.sim.actor_pos(ids[0])
	farm.sim.despawn_actor(ids[0])
	farm.sync_actors()
	_on_page_camera(_px(at) + Vector2(8, -6), 3.0)
	# Hold the world while stepping its picture clock. No movement is authored here.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	for look in SheepArt.looks():
		var id := _id_for(look)
		farm.sim.spawn_actor(id, SpeciesDefs.SHEEP, at, {"coat": Wool.EXTREME})
		var e: Dictionary = farm.sim.actor(id)
		e["facing"] = "right"
		e["extra"]["state"] = "content"
		e["extra"]["nights_content"] = 1
		farm.sync_actors()
		SheepGags.cue(id, "stretch", 10000)
		SheepGags.cue(id, "bird", 1000000)
		# The middle poses plus the unchanged smug ending, captured at exact ticks.
		for spec in [["reach", 0], ["stretch", 4], ["lick", 9], ["smug", 20]]:
			farm.sim.clock.tick = 10000 + int(spec[1])
			farm.actor_nodes[id]._process(0.0)
			farm.queue_redraw()
			await _frames(2)
			await _shot(out_dir.path_join("look_%d_%s.png" % [look, spec[0]]))
		# A full beat sampled from the game's renderer, for a looping comparison.
		for frame in 36:
			farm.sim.clock.tick = 10000 + frame
			farm.actor_nodes[id]._process(0.0)
			farm.queue_redraw()
			await _frames(1)
			await _shot(out_dir.path_join("look_%d_motion_%03d.png" % [look, frame]))
		farm.sim.despawn_actor(id)
		farm.sync_actors()
	print("SHEEP_REVIEW captured ", out_dir)
	get_tree().quit(0)


func _id_for(look: int) -> String:
	for n in 10000:
		var id := "sheep_review_%d" % n
		if SheepArt.look_of(id) == look:
			return id
	return ""


# A doorway and a one-square gap, driven by SheepBrain and Movement without
# overriding poses or moving the sprite by hand. The movie's marks name its cuts.
func _squeeze_review() -> bool:
	var barn_id := await _sheep_farm()
	var doorstep: Vector2i = _barn_doors(barn_id)[0]
	_place_player(doorstep + Vector2i(8, 3))
	InputManager.current_mode = InputManager.Mode.TOUCH
	_on_page_camera(_px(doorstep) + Vector2(12, -4), 4.0)
	await _seconds(0.5)
	var door_sheep := _put_sheep(doorstep, Wool.EXTREME)
	farm.sim.schedule_all_brains()
	_mark("doorway_start")
	if not await _observe_squeeze(door_sheep, "doorway"):
		return false
	_mark("doorway_end")
	farm.sim.despawn_actor(door_sheep)
	farm.sync_actors()
	var at := _open_grass_for(barn_id, 1)
	farm.sim.set_tile_state(at.x, at.y - 1, "obstacle_rock")
	farm.sim.set_tile_state(at.x, at.y + 1, "obstacle_rock")
	_on_page_camera(_px(at) + Vector2(8, -6), 4.0)
	_place_player(at + Vector2i(-3, 2))
	await _seconds(0.5)
	var gap_sheep := _put_sheep(at, Wool.EXTREME)
	farm.sim.schedule_all_brains()
	_mark("gap_start")
	if not await _observe_squeeze(gap_sheep, "gap"):
		return false
	_mark("gap_end")
	return true


func _observe_squeeze(id: String, label: String) -> bool:
	var seen := {}
	var moving_frames := 0
	for i in 240:
		await _frames(1)
		var node = farm.actor_nodes.get(id)
		if node != null and bool(node.get("waddling")):
			seen[int(node.hop_frame)] = true
			moving_frames += 1
	var content := String(farm.sim.actor(id).extra.get("state", "")) == "content"
	var node = farm.actor_nodes.get(id)
	print("SQUEEZE_REVIEW ", label, " waddle_poses=", seen.keys(), " moving_frames=", moving_frames,
		" stopped=", content, " waddling_after_stop=", node.get("waddling") if node != null else null)
	if not content or seen.size() != 4 or node == null or bool(node.get("waddling")):
		push_error("Squeeze review did not exercise all four moving poses and a stopped idle")
		return false
	return true

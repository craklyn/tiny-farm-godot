# replay_view.gd — SPIKE for T-16 / Q-40, not the landing page.
#
#   godot --path . tools/replay_view.tscn            # windowed, watch it play
#   godot --headless --path . tools/replay_view.tscn # assertions only
#
# Answers the one assumption the T-16 estimate rests on and that nothing had
# tested: can a recorded session drive a farm rendered outside main.tscn, without
# touching the player's live state?
#
# Deliberately NOT the feature. Q-40 is unruled; this exists to price it and to
# find out early whether replay-driven playback is even pleasant to watch.
extends Node2D

const STEP_SECONDS := 0.6

var _farm: Node2D = null
var _gs = null                      # detached GameState — see _check_isolation()
var _log: ReplayLog = null
var _decoded: Array[Dictionary] = []
var _next := 0
var _timer := 0.0
var _walk: Array[Vector2i] = []
var _at := Vector2i(2, 2)
var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=".repeat(60))
	print("T-16 SPIKE — can a replay drive a farm outside main.tscn?")
	print("=".repeat(60))

	var live_before := _live_gamestate_fingerprint()

	_log = _record_a_session()
	_check_renderer_standalone()
	_check_isolation(live_before)
	_check_movement_is_synthesizable()

	print("")
	print("-".repeat(60))
	print("Spike: %d PASSED, %d FAILED" % [_pass, _fail])
	print("-".repeat(60))
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _fail > 0 else 0)
	else:
		print("Windowed: stepping the replay at %.1fs per action. Ctrl-C to stop." % STEP_SECONDS)


func _ok(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ FAIL: " + name)


# --- Build a session to play back --------------------------------------------
# Recorded programmatically rather than read from user://, so the spike is
# self-contained and repeatable rather than depending on whoever played last.
func _record_a_session() -> ReplayLog:
	print("\n--- Recording a session to replay ---")
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var w := SimWorld.new()
	SimRng.reseed(4242)
	w.generate()

	var rlog := ReplayLog.new()
	rlog.start(4242)

	# A plausible little day: clear a few tiles, till, plant, water, sleep.
	var recorded := 0
	for ty in range(2, 6):
		for tx in range(3, 9):
			var st: String = w.get_tile(tx, ty).get("state", "")
			var verb := ""
			match st:
				"obstacle_weed": verb = "clear_weed"
				"cleared": verb = "till"
			if verb == "":
				continue
			var a := { "verb": verb, "target": Vector2i(tx, ty), "actor": "player" }
			var r := w.apply_action(a, gs)
			if r.get("ok", false):
				rlog.record(a, r)
				recorded += 1
	for ty in range(2, 6):
		for tx in range(3, 9):
			if w.get_tile(tx, ty).get("state", "") == "tilled":
				var a := { "verb": "plant", "target": Vector2i(tx, ty), "actor": "player",
					"seed_type": "wheat" }
				var r := w.apply_action(a, gs)
				if r.get("ok", false):
					rlog.record(a, r)
					recorded += 1
	var slp := { "verb": "sleep", "actor": "world" }
	var sr := w.apply_action(slp, gs)
	if sr.get("ok", false):
		rlog.record(slp, sr)
		recorded += 1

	print("  recorded %d actions" % recorded)
	_ok(recorded > 10, "a session with enough actions to be worth watching")
	return rlog


# --- 1. Does the renderer work outside main.tscn? -----------------------------
func _check_renderer_standalone() -> void:
	print("\n--- Renderer standalone ---")
	var FarmScript = load("res://world/farm.gd")
	_ok(FarmScript != null, "world/farm.gd loads")

	_farm = FarmScript.new()
	_farm.generate_on_ready = false          # the replay owns generation
	_farm.name = "AttractFarm"
	_farm.scale = Vector2(2, 2)
	add_child(_farm)
	_ok(is_instance_valid(_farm), "farm instantiates as a bare Node2D child")
	_ok(_farm.sim != null, "it brought its own SimWorld")

	# Detached GameState: apply_to() calls gs.reset(), so handing it the autoload
	# would wipe the player's live state on the title screen. This is the whole
	# hazard the spike exists to prove is avoidable.
	_gs = load("res://systems/game_state.gd").new()
	_gs.reset()

	SimRng.reseed(_log.gen_seed)
	_log.apply_to(_farm.sim, _gs)
	_ok(_farm.sim.count_planted() > 0, "the replay applied — crops exist in the attract world")

	# Rewind to the start so the spike can play it forward a step at a time.
	SimRng.reseed(_log.gen_seed)
	_gs.reset()
	_farm.sim.generate()
	for e in _log.entries:
		_decoded.append(_log._decode(e))
	_ok(_decoded.size() == _log.entries.size(), "entries decode for stepped playback")
	_farm.queue_redraw()


# --- 2. Is the player's live state safe? --------------------------------------
func _live_gamestate_fingerprint() -> String:
	var root = Engine.get_main_loop().root
	if not root.has_node("GameState"):
		return "no-autoload"
	var g = root.get_node("GameState")
	return "%d|%d|%d|%s" % [g.day, g.gold, g.energy, JSON.stringify(g.seeds)]


func _check_isolation(before: String) -> void:
	print("\n--- Live state isolation ---")
	var after := _live_gamestate_fingerprint()
	if before == "no-autoload":
		print("  (no GameState autoload in this context — isolation is trivially held)")
		_pass += 1
		return
	_ok(before == after, "the GameState autoload is untouched by the attract replay")
	_ok(_gs != null and _gs != Engine.get_main_loop().root.get_node("GameState"),
		"the attract loop is driving a detached GameState, not the singleton")


# --- 3. Can the farmer's walk be synthesized? ---------------------------------
# ReplayLog holds no movement — only world mutations pass through apply_action —
# so playback has to invent the walk between action targets. If Pathfinding can
# do that against the attract world, the "replay is the score, title screen is
# the performance" plan holds.
func _check_movement_is_synthesizable() -> void:
	print("\n--- Movement synthesis ---")
	var targets: Array[Vector2i] = []
	for a in _decoded:
		var t = a.get("target", null)
		if t is Vector2i:
			targets.append(t)
	_ok(targets.size() >= 2, "the replay carries action targets to walk between")
	if targets.size() < 2:
		return

	# An empty path is ambiguous — it means "cannot get there" OR "already beside
	# it", which is exactly the distinction the Q-30 work turned on. Counting an
	# empty path as failure understates reachability badly, since consecutive
	# actions in a real session are usually on adjacent tiles.
	var reached := 0
	var already := 0
	var stranded: Array[Vector2i] = []
	var at := Vector2i(2, 2)
	for t in targets:
		var adjacent: bool = absi(at.x - t.x) + absi(at.y - t.y) <= 1
		var path: Array[Vector2i] = Pathfinding.find_path_toward(_farm, at, t)
		if not path.is_empty():
			reached += 1
			at = path[path.size() - 1]
		elif adjacent:
			already += 1
		else:
			stranded.append(t)
	_ok(stranded.is_empty(), "every replay target is reachable, so the walk is synthesizable")
	print("  walked to %d, already beside %d, stranded %d (of %d targets)"
		% [reached, already, stranded.size(), targets.size()])
	if not stranded.is_empty():
		print("  stranded: %s" % str(stranded.slice(0, 6)))


# --- Windowed playback --------------------------------------------------------
func _process(delta: float) -> void:
	if _farm == null or _next >= _decoded.size():
		return
	if DisplayServer.get_name() == "headless":
		return
	_timer += delta
	if _timer < STEP_SECONDS:
		return
	_timer = 0.0
	var a := _decoded[_next]
	_next += 1
	_farm.sim.apply_action(a, _gs)
	_farm.queue_redraw()
	if _next >= _decoded.size():
		print("Playback reached the end of the replay (%d actions)." % _decoded.size())
		_capture()


# Proof that the attract farm actually draws, not merely that it constructs.
func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# Written to the scratch dir, not the repo: it is evidence, not an asset.
	var path := "user://spike_frame.png"
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("frame capture: %s (%dx%d)" % ["ok" if err == OK else "FAILED", img.get_width(), img.get_height()])
	get_tree().quit(0)

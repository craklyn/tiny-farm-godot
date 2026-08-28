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
var _player: Node2D = null          # sibling named "Player" — farm.gd looks it up by path
var _gs = null                      # detached GameState — see _check_isolation()
var _log: ReplayLog = null
var _decoded: Array[Dictionary] = []
var _next := 0
var _dwell := 0.0
var _pass := 0
var _fail := 0

const SPAWN := Vector2i(2, 2)

var _pending := Vector2i(-1, -1)   # tile being tapped until it actually changes
var _state_before := ""
var _attempts := 0
var _live_at_start := ""


func _ready() -> void:
	print("=".repeat(60))
	print("T-16 SPIKE — can a replay drive a farm outside main.tscn?")
	print("=".repeat(60))

	var live_before := _live_gamestate_fingerprint()
	_live_at_start = live_before

	# A real session if one is offered, otherwise a synthetic one so the spike
	# stays self-contained and runnable with no play history.
	#   godot --path . tools/replay_view.tscn -- playtests/session_replay.json
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and FileAccess.file_exists(args[0]):
		_log = ReplayLog.load_from(args[0])
		if _log == null:
			print("Could not parse %s" % args[0])
			get_tree().quit(1)
			return
		print("\n--- Loaded a recorded session ---")
		print("  %s" % args[0])
		print("  %d actions · %s" % [_log.entries.size(), _log.build_note()])
		_ok(not _log.entries.is_empty(), "the recorded session has actions to watch")
		if not _log.base_save.is_empty():
			print("  NOTE: this session continued from a save, so playback starts from")
			print("  that snapshot rather than from worldgen.")
	else:
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
		print("Windowed: the farmer plays the replay through her own input path.")


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

	# A plausible little day, worked the way a person works a plot: clear the
	# whole patch, then till it, then plant it.
	#
	# Separate passes are not stylistic. Matching on each tile's state as the loop
	# visited it meant a tile that started as an obstacle got cleared and then
	# never tilled, because the loop had already moved past it — which left bare
	# grass notches in the middle of the field and read as a playback bug rather
	# than a gap in this recorder.
	var recorded := 0
	var plot: Array[Vector2i] = []
	for ty in range(2, 6):
		for tx in range(3, 9):
			plot.append(Vector2i(tx, ty))

	var clear_verbs := {
		"obstacle_weed": "clear_weed",
		"obstacle_rock": "clear_rock",
		"obstacle_log": "clear_log",
	}
	for pass_name in ["clear", "till", "plant"]:
		for t in plot:
			var st: String = w.get_tile(t.x, t.y).get("state", "")
			var a := {}
			match pass_name:
				"clear":
					if clear_verbs.has(st):
						a = { "verb": clear_verbs[st], "target": t, "actor": "player" }
				"till":
					if st == "cleared":
						a = { "verb": "till", "target": t, "actor": "player" }
				"plant":
					if st == "tilled":
						a = { "verb": "plant", "target": t, "actor": "player",
							"seed_type": "wheat" }
			if a.is_empty():
				continue
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

	# The farmer. Without her the attract loop is tiles morphing on their own,
	# which is neither gameplay nor a demonstration of any verb — so a visible
	# actor is the feature, not a garnish. farm.gd finds her via get_node("../Player"),
	# so the node name is load-bearing.
	var PlayerScript = load("res://player/player.gd")
	_player = PlayerScript.new()
	_player.name = "Player"
	add_child(_player)
	_player.farm = _farm
	_player.init_position(SPAWN.x, SPAWN.y)
	_ok(_farm.get_node_or_null("../Player") != null,
		"the farm renderer can find a sibling named Player")
	_ok(_player.has_method("queue_render"), "the player can queue itself for drawing")

	# Detached GameState: apply_to() calls gs.reset(), so handing it the autoload
	# would wipe the player's live state on the title screen. This is the whole
	# hazard the spike exists to prove is avoidable.
	_gs = load("res://systems/game_state.gd").new()
	_gs.reset()

	SimRng.reseed(_log.gen_seed)
	_log.apply_to(_farm.sim, _gs)
	_ok(_farm.sim.count_planted() > 0, "the replay applied — crops exist in the attract world")

	# Rewind to the start so the spike can play it forward a step at a time.
	# Rewind to the session's starting world, however it began.
	if _log.base_save.is_empty():
		SimRng.reseed(_log.gen_seed)
		_gs.reset()
		_farm.sim.generate()
	else:
		_gs.reset()
		SaveGame.restore(_log.base_save, _farm.sim, _gs)
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
# The performance — driven through the *player's own input path*, not by calling
# sim.apply_action() directly.
#
# The first cut did apply actions directly, and the designer immediately spotted
# that she walked on top of each tile before working it. That is not how the game
# plays: find_path_toward() does not stop short, and the halt-when-in-range
# behaviour lives in the player's `approach_target`, which only the tap-handling
# branch sets. Shoving a path into `player.path` therefore silently discards the
# whole Q-30 fix — three revisions of work — along with the action animation,
# tool swap, sfx, particles and the D-8 tile squash, all of which live in
# _execute_resolved_action().
#
# So: inject the tap and let the existing intent -> player -> sim pipeline do
# everything. The attract loop then renders identically to real play *by
# construction*, and cannot drift from it later.
func _process(delta: float) -> void:
	if _farm == null or _player == null or _next >= _decoded.size():
		return
	if DisplayServer.get_name() == "headless":
		return

	_player.update_player(delta)
	_farm.queue_redraw()

	if not _player_is_idle():
		return

	_dwell += delta
	if _dwell < STEP_SECONDS:
		return
	_dwell = 0.0

	while _next < _decoded.size() and not (_decoded[_next].get("target", null) is Vector2i):
		_next += 1
	if _next >= _decoded.size():
		print("Playback reached the end of the replay.")
		_capture()
		return

	var a := _decoded[_next]
	_next += 1
	_dispatch_intent(String(a.get("verb", "")), a["target"], String(a.get("seed_type", "wheat")))


# Replay at the INTENT layer — not taps, and not the sim.
#
# Taps are the wrong layer: they are ambiguous by design, because the router
# reads one tap on a distant workable tile as pure movement (Q-30). The sim is
# also the wrong layer: going straight to apply_action() skips the approach and
# the whole of _execute_resolved_action().
#
# Between them sits the resolved intent — {action, target_t, tool_idx} — which is
# unambiguous, is exactly what a tap resolves *into*, and is precisely what
# ReplayLog already stores as (verb, target). Handing the player one and letting
# her walk to it reproduces real play without needing any new recorded data:
# the walk is *derivable*, because Pathfinding is deterministic given a start and
# a goal, and the start is itself derived from where the previous action left her.
func _dispatch_intent(verb: String, target: Vector2i, seed_type: String) -> void:
	var at: Vector2i = _player.get_tile_pos()
	var intent := {
		"action": verb,
		"target_t": target,
		"tool_idx": _tool_for(verb, target),
		"seed_type": seed_type,
	}
	var path: Array[Vector2i] = Pathfinding.find_path_toward(_farm, at, target)
	if path.is_empty():
		_player._execute_resolved_action(intent)   # already in range
	else:
		_player.approach_target = target
		_player.path = path
		_player.pending_action = intent            # fires on arrival


func _tool_for(verb: String, target: Vector2i) -> int:
	var st: String = _farm.sim.get_tile(target.x, target.y).get("state", "")
	for i in range(Tools.LIST.size()):
		if Tools.get_action(i, st) == verb:
			return i
	return 0


func _player_is_idle() -> bool:
	return _player.path.is_empty() \
		and not _player.is_acting \
		and _player.pending_action.is_empty()


func _face_toward(t: Vector2i) -> void:
	var at: Vector2i = _player.get_tile_pos()
	var dx := t.x - at.x
	var dy := t.y - at.y
	if dx == 0 and dy == 0:
		return
	if absi(dx) >= absi(dy):
		_player.facing = "right" if dx > 0 else "left"
	else:
		_player.facing = "down" if dy > 0 else "up"


# Proof that the attract farm actually draws, not merely that it constructs.
func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# Written to the scratch dir, not the repo: it is evidence, not an asset.
	# Honesty check: the isolation assertion above runs at *setup*, before any
	# tap-driven playback. Tap dispatch goes through _execute_resolved_action(),
	# which hardcodes the GameState autoload — so re-measure at the end and say
	# so plainly rather than leaving the earlier ✓ to imply more than it proved.
	var after := _live_gamestate_fingerprint()
	if after == _live_at_start:
		print("isolation after playback: HELD (autoload unchanged)")
	else:
		print("isolation after playback: **VIOLATED** — the live GameState moved.")
		print("  before: %s" % _live_at_start)
		print("  after:  %s" % after)
		print("  Cause: player._execute_resolved_action() uses the GameState autoload")
		print("  directly. Tap-driven playback therefore spends the player's real")
		print("  seeds and energy. T-16 needs an injectable game state on the player.")

	var path := "user://spike_frame.png"
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("frame capture: %s (%dx%d)" % ["ok" if err == OK else "FAILED", img.get_width(), img.get_height()])
	get_tree().quit(0)

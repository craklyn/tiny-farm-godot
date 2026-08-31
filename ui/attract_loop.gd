# attract_loop.gd — the title screen plays a farm (T-16 / Q-40)
#
# The menu sits over a real farm being worked by a visible farmer, driven by a
# recorded session. Q-40's reasoning, which is worth keeping in front of anyone
# changing this: an attract loop is *a demonstration channel that costs zero
# agency* — the thing Q-37's cold open buys at the price of control — and it is
# skippable by construction, because the skip is the button the player was
# already reaching for.
#
# Three findings from the spike (`tools/replay_view.gd`) are load-bearing here.
# Breaking any of them turns this back into something that looks wrong:
#
#  1. **Drive at the intent layer.** Not raw taps (ambiguous by design — the
#     router reads a far tap on workable ground as pure movement, Q-30) and not
#     `sim.apply_action` (skips the approach, the tool swap, the animation, the
#     sfx and the D-8 tile squash). Between them sits the resolved intent, which
#     is exactly what a tap resolves *into* and exactly what ReplayLog stores.
#     The designer spotted the sim-layer version immediately: the farmer stood
#     *on* each tile instead of beside it.
#  2. **An empty path means "already beside it" as often as "unreachable."**
#     Treating it as failure strands the playback on adjacent actions, which are
#     most of a real session.
#  3. **Its own detached GameState.** `ReplayLog.apply_to()` calls `gs.reset()`,
#     so handing it the autoload would wipe the player's save summary before they
#     ever tapped Continue — and the spike measured the live state being drained
#     to energy 0, wheat 0 just by watching the menu.
extends Node2D

# One const to switch the whole thing off, per the plan's kill-switch
# requirement: if the second world costs frames on the tablet, reduce TICK_EVERY
# first and only then set this to false.
const ATTRACT_ENABLED := true

# Playback advances every Nth frame rather than every frame, so the cost of the
# second world is a dial rather than a rebuild (finding F-6: farm.gd's _draw
# already walks every tile, and this doubles that).
const TICK_EVERY := 1
const STEP_SECONDS := 0.55

# The developed part of any real session sits in the top-left spawn band, and the
# menu covers the centre, so a static view shows the player a lot of empty grass.
const DRIFT_SECONDS := 26.0
const DRIFT_FROM := Vector2(-40.0, -20.0)
const DRIFT_TO := Vector2(-150.0, -95.0)
const WORLD_SCALE := 2.2

var farm: Node2D = null
var player: Node2D = null
var gs: Node = null

var _log: ReplayLog = null
var _decoded: Array[Dictionary] = []
var _next := 0
var _dwell := 0.0
var _frame := 0
var _drift := 0.0
var _running := false
var paused := false


# Returns false when there is nothing to play, so the caller can keep its plain
# backdrop. First boot on a fresh install has no session and no demo replay yet,
# and must not crash or show a blank hole.
func begin(replay: ReplayLog) -> bool:
	if replay == null or replay.entries.is_empty():
		return false
	_log = replay

	gs = load("res://systems/game_state.gd").new()
	gs.name = "AttractState"
	gs.reset()
	add_child(gs)

	var FarmScript = load("res://world/farm.gd")
	farm = FarmScript.new()
	farm.name = "AttractFarm"
	farm.generate_on_ready = false
	farm.gs = gs
	farm.mute_feedback = true      # no nope sounds into a menu
	add_child(farm)

	# The node name is load-bearing: farm.gd finds the farmer with
	# get_node("../Player") when it builds its render queue.
	var PlayerScript = load("res://player/player.gd")
	player = PlayerScript.new()
	player.name = "Player"
	player.gs = gs                 # injected BEFORE entering the tree
	add_child(player)
	player.farm = farm

	# Start from the session's own beginning, however it began.
	_rewind_world()

	var spawn := WorldLayout.spawn()
	player.init_position(spawn.x, spawn.y)

	for e in _log.entries:
		_decoded.append(ReplayLog._decode(e))

	scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	position = DRIFT_FROM
	_running = true
	farm.queue_redraw()
	return true


func _process(delta: float) -> void:
	if not _running or paused:
		return

	# A slow drift across the developed corner. Ping-pongs rather than looping, so
	# there is never a jump cut back to the start.
	_drift += delta / DRIFT_SECONDS
	var t: float = 0.5 - 0.5 * cos(_drift * PI)
	position = DRIFT_FROM.lerp(DRIFT_TO, t)

	_frame += 1
	if _frame % TICK_EVERY != 0:
		return

	player.update_player(delta * TICK_EVERY)
	farm.queue_redraw()

	if not _idle():
		return
	_dwell += delta * TICK_EVERY
	if _dwell < STEP_SECONDS:
		return
	_dwell = 0.0
	_advance()


# The world the recorded session started from — used on the first play and on
# every loop round. Mirrors `ReplayLog.apply_to`'s opening deliberately, seed and
# all: a v2 session continued from a save ran under that save's own seed (M2.5
# WI-5), and a playback on some other seed is a farm that never was, which is the
# same lie Q-41's build check exists to prevent.
func _rewind_world() -> void:
	if _log.base_save.is_empty():
		SimRng.reseed(_log.gen_seed)
		farm.sim.generate()
	else:
		SaveGame.restore(_log.base_save, farm.sim, gs)
		if _log.version >= 2 and _log.gen_seed != 0:
			SimRng.reseed(_log.gen_seed)


func _idle() -> bool:
	return player.path.is_empty() and not player.is_acting and player.pending_action.is_empty()


func _advance() -> void:
	if _next >= _decoded.size():
		_restart()
		return
	var a: Dictionary = _decoded[_next]
	_next += 1
	var verb := String(a.get("verb", ""))

	# Format v2 (M2.5 WI-5). Two entry kinds this playback does not perform:
	#
	#  - A **free-walk event** is not an Action at all; nothing records one yet
	#    and this steps over it when something does.
	#  - A **brain entry** is somebody else's decision — the hen laying, the crow
	#    eating — and driving the *farmer* to it is finding F-3 from the other
	#    end: she would walk across the farm to lay an egg. Applied straight to
	#    the detached sim instead, so the egg simply appears where the hen left
	#    it. Recomputation-driven playback (running the brains here, with sprites
	#    for them) is WI-6's, and it is what this becomes.
	if ReplayLog.is_walk(a):
		return
	if bool(a.get("brain", false)):
		farm.apply_action(a, gs)
		return

	# A day turning is not something the farmer walks to. Applied straight to the
	# detached sim, which is also the only place playback may legitimately do so.
	if verb == "sleep":
		farm.apply_action({ "verb": "sleep", "actor": "world",
			"weather": String(a.get("weather", "sunny")) }, gs)
		return
	var target = a.get("target", null)
	if not (target is Vector2i):
		farm.apply_action(a, gs)
		return

	_dispatch_intent(verb, target, String(a.get("seed_type", "wheat")))


# Hand the player a resolved intent and let her walk to it — the whole of finding
# 1 above. The walk is *derivable* rather than recorded, because Pathfinding is
# deterministic given a start and a goal, and the start is where the previous
# action left her.
func _dispatch_intent(verb: String, target: Vector2i, seed_type: String) -> void:
	var intent := {
		"action": verb,
		"target_t": target,
		"tool_idx": _tool_for(verb, target),
		"seed_type": seed_type,
	}
	var path: Array[Vector2i] = Pathfinding.find_path_toward(farm, player.get_tile_pos(), target)
	if path.is_empty():
		# Finding 2: empty means "already beside it" far more often than
		# "unreachable", and the difference is the whole of Q-30.
		player._execute_resolved_action(intent)
	else:
		player.approach_target = target
		player.path = path
		player.pending_action = intent


func _tool_for(verb: String, target: Vector2i) -> int:
	var st: String = farm.sim.get_tile(target.x, target.y).get("state", "")
	for i in range(Tools.LIST.size()):
		if Tools.get_action(i, st) == verb:
			return i
	return 0


# Loop rather than stop: the menu may sit here for a long time, and a farm that
# freezes mid-session reads as a crash.
func _restart() -> void:
	_next = 0
	gs.reset()
	_rewind_world()
	var spawn := WorldLayout.spawn()
	player.init_position(spawn.x, spawn.y)
	farm.queue_redraw()


# --- Choosing what to play ----------------------------------------------------

# The player's own last session when it is trustworthy, else the shipped demo,
# else nothing (and the caller keeps its plain backdrop).
#
# "Trustworthy" means the replay was recorded by *this* build: `apply_to()`
# re-runs the actions against today's rules, so a cross-build replay can produce
# a different farm from the one that was actually played (Q-41). On the title
# screen that would be a quiet lie about the player's own save.
static func choose_replay(save_replay_path: String, demo_path: String) -> ReplayLog:
	var own := ReplayLog.load_from(save_replay_path)
	if own != null and not own.entries.is_empty() \
			and own.build_status() == ReplayLog.Build.MATCH:
		return own
	var demo := ReplayLog.load_from(demo_path)
	if demo == null or demo.entries.is_empty():
		return null
	# In a dev build accept the demo whatever its stamp — it is regenerated by
	# hand and its build id is usually stale. In a release, a stale demo means
	# the generator did not run, and playing it would show a farm that never was.
	if ReplayLog.current_build() == "dev" or demo.build_status() == ReplayLog.Build.MATCH:
		return demo
	return null

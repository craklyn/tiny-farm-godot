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
	# ...and give the world its cast (M2.5 WI-6). This is finding F-3 fixed at the
	# root: the farm draws whoever the registry holds, so the neighbour, the hen
	# and any crow the playback's own sim sends are all here, in a scene that has
	# never known what an entity is.
	farm.sync_actors()

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
	# The neighbour walks on the playback's clock too, for the same reason the
	# farmer does: this loop advances at `TICK_EVERY`, and a scene where one of the
	# two people is on that clock and the other is on the engine's demonstrates
	# nothing at half speed (M2.5 WI-6).
	var walker := _neighbour()
	if walker != null:
		walker.set_process(false)
		walker.step(delta * TICK_EVERY)
	_pump_sim_clock(delta * TICK_EVERY)
	farm.sync_actors()
	farm.queue_redraw()

	_skip_unplayable()
	if not _idle():
		return
	_dwell += delta * TICK_EVERY
	if _dwell < STEP_SECONDS:
		return
	_dwell = 0.0
	_advance()


# Sim time, for the same reason `main.gd` has one (M2.5 WI-6): the brains that
# move the hen and fly a crow are on the tick clock, and a playback that advanced
# no clock would draw a farm of statues — which is finding F-3 half-fixed and
# arguably worse than the empty yard it replaces.
#
# So the brains **recompute** here rather than being re-applied from the log
# (`_advance` steps over brain entries for that reason), exactly as
# `ReplayLog.apply_to` does. It cannot match the recording tick-for-tick and does
# not try: this playback paces itself by the farmer's walk, not by the session's
# clock, so the hen potters on her own schedule. Nobody is checking — it is a
# backdrop, and what it owes the player is a farm that looks alive, not one that
# is bit-identical to somebody else's afternoon.
const MAX_TICKS_PER_FRAME := 4
var _tick_debt: float = 0.0


func _pump_sim_clock(delta: float) -> void:
	_tick_debt += delta * float(SimClock.RATE)
	var whole := int(_tick_debt)
	if whole <= 0:
		return
	_tick_debt -= float(whole)
	farm.advance_sim(mini(whole, MAX_TICKS_PER_FRAME), gs)


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


# Whose turn it is to be waited for. Most beats are the farmer's, but the cold
# open's are the neighbour's, and waiting for the wrong one either stalls the
# playback or fires her next action while she is still mid-stride.
func _idle() -> bool:
	if _next < _decoded.size() \
			and String(_decoded[_next].get("actor", "")) == SimWorld.ACTOR_NEIGHBOUR:
		var n := _neighbour()
		return n == null or not n.is_busy()
	return player.path.is_empty() and not player.is_acting and player.pending_action.is_empty()


# Entries that are not beats: a free-walk event is not an Action, and a brain's
# Action is recomputed by the clock pump rather than performed here (M2.5 WI-6).
# Skipped without spending a dwell — at STEP_SECONDS each, a session's walk stream
# would otherwise freeze the farm for minutes.
func _skip_unplayable() -> void:
	while _next < _decoded.size():
		var e: Dictionary = _decoded[_next]
		if ReplayLog.is_walk(e) or bool(e.get("brain", false)):
			_next += 1
			continue
		return


# Her sprite, while the farm still has one. Built by `world/farm.gd` from the
# registry, freed when she has walked off the map (M2.5 WI-6).
func _neighbour() -> Node2D:
	if farm == null:
		return null
	var n = farm.actor_nodes.get(SimWorld.ACTOR_NEIGHBOUR, null)
	return n if is_instance_valid(n) else null


func _advance() -> void:
	_skip_unplayable()
	if _next >= _decoded.size():
		_restart()
		return
	var a: Dictionary = _decoded[_next]

	# **The cold open's beats are hers, not the farmer's** (M2.5 WI-6, finding
	# F-3). The shipped demo opens with nine `actor: "neighbour"` entries, and
	# until now every one of them was handed to `_dispatch_intent` — so the
	# *farmer* walked across the map and tilled the neighbour's row, which is the
	# same bug as an empty yard seen from the other side. Her motion is derived
	# here the way the farmer's is: walk to the action's target, pose, act.
	if String(a.get("actor", "")) == SimWorld.ACTOR_NEIGHBOUR and _neighbour() != null:
		if not _perform_neighbour(a):
			return   # still walking there; the entry is not spent
		_next += 1
		return

	_next += 1
	var verb := String(a.get("verb", ""))

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


# One of the neighbour's recorded beats, performed by her sprite. Returns false
# while she still has walking to do, so the caller leaves the entry where it is
# and asks again — the same "let her finish her stride" rule `main.gd` keeps for
# the live cold open, and for the same reason: a person who teleports between
# tiles is not demonstrating anything.
#
# It cannot stall. Either she is beside the target (she acts), or a route exists
# (she walks, and `is_busy` holds the playback), or there is no route at all and
# she acts from where she stands — a demonstration slightly out of place beats a
# title screen that has stopped.
func _perform_neighbour(a: Dictionary) -> bool:
	var n := _neighbour()
	var target = a.get("target", null)
	if target is Vector2i and not n.is_beside(target):
		n.go_to(target)
		if n.is_busy():
			return false
	farm.apply_action(a, gs)
	if target is Vector2i:
		n.pose(target)
	# The honk is main.gd's; here she simply waves and goes, which is the whole
	# visible beat. The registry drops her the moment the gate opens, and the
	# renderer leaves a departing sprite alone until it has walked off the map.
	if String(a.get("verb", "")) == "open_gate":
		n.wave()
		# Immediately, not deferred as `main.gd` does it: the gate opening drops
		# her from the registry in the same call above, and the renderer only
		# spares a sprite that already says it is departing. A deferred flag would
		# leave a window in which she is neither registered nor leaving, and the
		# next sync would free her mid-wave. (The wave itself is a pose timer, so
		# she still stands and waves before she walks — nothing about the beat
		# changes.)
		n.leave()
	return true


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
	_tick_debt = 0.0
	gs.reset()
	# Every sprite goes with the world it belonged to. Without this, a neighbour
	# still walking off the map from the last round would be adopted as the new
	# round's neighbour and spend the whole cold open leaving (M2.5 WI-6).
	farm.clear_actors()
	_rewind_world()
	farm.sync_actors()
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

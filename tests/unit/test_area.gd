# Shared assertion accounting and fixtures for every unit-test area.
extends RefCounted

const AtomicFileWriter := preload("res://systems/atomic_file.gd")

var pass_count := 0
var fail_count := 0
var fail_log: Array[String] = []

var GameState: Node
var ActionRouter: Node
var Pathfinding: Node

# The shelf: every session folder in playtests/, classified. `format` is the
# replay version it was recorded under; `verdict` is what its replay does against
# its own autosave — "match", or "cross" for sessions whose world has moved under
# them (M1.5's parcels invalidated the 08-28/08-30 play sessions; T-32's yard adds
# a second reason to the same files; the 08-31 pair are deploy rescues — the first
# from the pre-M2.5 build, the second a Continue on a pre-T-32 base, this game's
# first v2 log; 08-21 is the oldest surviving session of all, rescued by hand
# from the retired com.godot.game install — see its NOTE.md).
#
# **Five folders were removed on 2026-09-02 and the shelf went 15 → 10.** Every
# one was redundant, and it is worth being precise about how, because "duplicate"
# turned out to mean two different things:
#
# - `2026-08-28_224740` and the 08-30 pair `215356`/`215452` were **byte-identical
#   in all three files** to `115934` and `215248` respectively. Copies, nothing
#   more.
# - `2026-09-02_211138` and `214427` shared `233943`'s tap trace because the trace
#   file on the device is never cleared — but their *replays* were a `base_save`
#   and **one entry**. They recorded no play at all. The play they appear to
#   contain is `233943`'s, which is still here with all 3450 of its entries.
#
# That second pair is also a correction. The commentary below used to argue that
# `211138` mattered because it was "a real play session — 700-odd entries, not an
# empty log — and it still replays to its own autosave". It was not: one entry, on
# a base save. Its "match" was the hollow kind this file already knew about — a
# saved world with no Actions reproduces itself whatever the generator does — and
# it was read as evidence of determinism it could not carry.
#
# **A folder not listed here does not fail anything** (changed 2026-09-02). It
# used to fail BY NAME until classified, and that was wrong for a reason worth
# keeping: the rescue takes whatever is on the device and the device does not
# forget, so deploying twice filed the same play twice and the suite went red
# because somebody had *deployed*. Red has to mean broken. Unclassified sessions
# are skipped, printed as a note, and shown in HQ's Playtests page instead;
# tools/pull_session.sh no longer shelves a duplicate trace or a tapless one at
# all, which is where that problem actually belonged.
#
# What has not changed: everything listed below is pinned exactly, and moving one
# of these numbers still means coming here and saying which, and why.
const SHELF := {
	"2026-08-21_103100": { "format": 1, "verdict": "cross" },
	"2026-08-28_111552": { "format": 1, "verdict": "cross" },
	"2026-08-28_114839": { "format": 1, "verdict": "cross" },
	"2026-08-28_115934": { "format": 1, "verdict": "cross" },
	"2026-08-30_215248": { "format": 1, "verdict": "match" },
	"2026-08-30_221027": { "format": 1, "verdict": "cross" },
	"2026-08-31_220017": { "format": 1, "verdict": "cross" },
	"2026-08-31_220426": { "format": 2, "verdict": "cross" },
	"2026-08-31_230643": { "format": 2, "verdict": "cross" },
	"2026-08-31_233943": { "format": 2, "verdict": "cross" },
	# 2026-09-10: the four tablet rescues of the workbench day. 191345 is the designer's
	# finished playthrough (day 53, nothing left to unlock); 004251 is a shorter day on
	# the same build. Both replayed exactly under the build that added the bench, and
	# **neither does any more.** The crow night landed (P-15, design/04): on a farm with
	# no acorns left on the ground and four tomatoes standing, the sleep now places three
	# birds on three of them, and both of these farms meet that description. 004251
	# diverges at entry 2226 and 191345 at entry 329, each of them a raid crow eating a
	# tomato the recording never lost. That is the world moving under a recording, which
	# is what "cross" means here — the same thing Q-98 did to 112331 (a robot picked up
	# and set down again now keeps its weights) the day before. 013629 was already cross.
	"2026-09-10_004251": { "format": 2, "verdict": "cross" },
	"2026-09-10_013629": { "format": 2, "verdict": "cross" },
	"2026-09-10_112331": { "format": 2, "verdict": "cross" },
	"2026-09-10_191345": { "format": 2, "verdict": "cross" },
	# A complete playthrough by the designer's wife on the tablet, 2026-09-10 evening: day 41,
	# from a new farm to the Mark III, 13,419 entries. Crosses at entry 3394, where the crow
	# night (P-15, landed 2026-09-10) now raids a tomato her recording never lost — the
	# world moving under a recording by the designer's own ruling, as with his two above.
	"2026-09-11_095433": { "format": 2, "verdict": "cross" },
	# Pulled off the tablet 2026-09-15, the evening the save slots landed: the CEO's
	# daughter's farm at day 31, continued from a save after the tablet was restarted,
	# so the log is the 66 entries since that restart rather than the whole play. It
	# replays to its autosave exactly under this build.
	"2026-09-15_234314": { "format": 2, "verdict": "match" },
}

# The robot-value measurement, shared with the tool that prints it as a table for
# a human (`test_robot_usefulness` at the bottom of this file says why it is
# shared rather than copied). Only its static functions are used — the script's
# own `_init` is the demo's, and preloading never runs it.
const RobotValue := preload("res://tools/demo_robot_value.gd")

# The week a Mark III spends learning to farm, shared with the tool that prints
# it as a table (`test_learning_robot` at the end of the mark-3 block says why it
# is shared rather than copied). Static functions only, as above.
const LearningRobot := preload("res://tools/demo_learning_robot.gd")

# The crow raid's morning walked out on the farm the game generates, shared with
# the tool that prints it for a human (`test_crow_raid_costs_one_tomato` says why
# it is shared rather than copied). Static functions only, as above.
const RaidRace := preload("res://tools/measure_raid_race.gd")

# A Mark III given a wider view (Q-127), shared with the tool that plays the
# 24-farm comparison. Static functions only, as above.
const WiderView := preload("res://tools/measure_wider_view.gd")

# The studio's starting brain for the Mark III (Q-128), shared with the tool that
# trains it and measures it on held-out farms. Static functions only, as above.
const PretrainMk3 := preload("res://tools/pretrain_mk3.gd")


func _init() -> void:
	GameState = load("res://systems/game_state.gd").new()
	ActionRouter = load("res://systems/action_router.gd").new()
	Pathfinding = load("res://systems/pathfinding.gd").new()


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		pass_count += 1
		print("  ✓ " + test_name)
	else:
		fail_count += 1
		fail_log.append("FAIL: " + test_name)
		print("  ✗ FAIL: " + test_name)


func _draw_order_test_head(rows: int, per_row: int, tile_size: int) -> Array[Dictionary]:
	var head: Array[Dictionary] = []
	for row in rows:
		for col in per_row:
			head.append({ "y": row * tile_size, "tag": "tile_%d_%d" % [row, col] })
	return head


# Runs both algorithms on the same queue and asserts they land on the
# identical sequence of tags — the order-equality test wec1e9f9eb27 asks for,
# checked entry by entry rather than trusting a size match alone.
func _assert_draw_order_matches(FarmScript, label: String, queue: Array[Dictionary], walk_len: int) -> void:
	var merged: Array[Dictionary] = FarmScript._merge_render_queue(queue, walk_len)
	var reference: Array[Dictionary] = FarmScript._sort_render_queue_reference(queue)
	_assert(merged.size() == reference.size() and merged.size() == queue.size(),
		"%s: merge keeps every entry (%d merged, %d reference, %d queued)"
			% [label, merged.size(), reference.size(), queue.size()])
	for i in min(merged.size(), reference.size()):
		_assert_quiet(merged[i]["tag"] == reference[i]["tag"],
			"%s entry %d: got %s, old sort had %s"
				% [label, i, merged[i].get("tag"), reference[i].get("tag")])
	_flush_quiet("%s: the merge's order matches the old full sort's" % label)


func _replay_do(world: SimWorld, rlog: ReplayLog, action: Dictionary) -> Dictionary:
	var r := world.apply_action(action, GameState)
	if r.get("ok", false):
		rlog.record(action, r)
	return r

func _replay_snapshot(world: SimWorld) -> String:
	# One definition of "sim truth" everywhere: same canonical form the
	# verification tools use (includes milestones and max fields).
	return SaveGame.capture_canonical(world, GameState)

const SLOT_SCRATCH := "user://test_slots_scratch/"


func _wipe_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if d.current_is_dir():
			_wipe_dir(full)
		else:
			DirAccess.remove_absolute(full)
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_text(path: String, text: String) -> void:
	SaveSlots.ensure_parent(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


const RAID_BED_Y := 5
const RAID_BED_X0 := 12


# The farm as she leaves it on the eve of the crow night: the acorns gone off the
# ground (which is what picking them up does, T-30), a tomato bed standing, and
# her indoors beside her own front door. The log is re-based on the result, so a
# session recorded from here reproduces a farm no sequence of taps would have
# produced. Returns the bed.
func _raid_eve(s: LiveSession) -> Array[Vector2i]:
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if s.world.get_object(tx, ty) == "acorn":
				s.world.set_object(tx, ty, "")
	var bed: Array[Vector2i] = []
	for i in SimWorld.RAID_MIN_TOMATOES:
		var t := Vector2i(RAID_BED_X0 + i, RAID_BED_Y)
		s.world.set_tile_state(t.x, t.y, "growing", SimWorld.RAID_CROP)
		bed.append(t)
	s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, _indoor_door_tile(s.world))
	s.rebase()
	return bed


# The tile her front door puts her on inside the house, and the doorway she taps
# to come back out — read off the layout's door table rather than typed in.
func _indoor_door_tile(world: SimWorld) -> Vector2i:
	return WorldLayout.door_at(world.find_object(WorldLayout.HOUSE_DOOR),
		world.layout).get("to", Vector2i(-1, -1))


func _doorway_tile(world: SimWorld) -> Vector2i:
	return world.find_object(WorldLayout.HOME_DOORWAY)


# The raid's birds, by id, in a fixed order.
func _raid_birds(world: SimWorld) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = world.actors.keys()
	ids.sort()
	for id in ids:
		if String(id).begins_with(SimWorld.ACTOR_RAID_CROW):
			out.append(String(id))
	return out


func _standing_tomatoes(world: SimWorld) -> int:
	return world.crow_targets_of_crop(SimWorld.RAID_CROP).size()


var _quiet_fail := ""
var _quiet_count := 0

func _assert_quiet(condition: bool, label: String) -> void:
	_quiet_count += 1
	if not condition and _quiet_fail == "":
		_quiet_fail = label

func _flush_quiet(label: String) -> void:
	if _quiet_fail == "":
		_assert(true, "%s (%d checks)" % [label, _quiet_count])
	else:
		_assert(false, "%s — first failure: %s" % [label, _quiet_fail])
	_quiet_fail = ""
	_quiet_count = 0


func _flood(world: SimWorld, start: Vector2i) -> Array[Vector2i]:
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var out: Array[Vector2i] = []
	var idx := 0
	while idx < queue.size():
		var c: Vector2i = queue[idx]
		idx += 1
		out.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			if not world.is_walkable(n.x, n.y):
				continue
			seen[n] = true
			queue.append(n)
	return out


func _actors_signature(world: SimWorld) -> String:
	var ids := world.actors.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id in ids:
		parts.append("%s=%s" % [id, world.actors[id]])
	return "; ".join(parts)


func _only(targets: Array[Vector2i]) -> Vector2i:
	return targets[0] if targets.size() == 1 else Vector2i(-1, -1)


class LiveSession:
	var world := SimWorld.new()
	var gs
	var log := ReplayLog.new()

	func _init(seed_value: int) -> void:
		gs = load("res://systems/game_state.gd").new()
		gs.reset()
		SimRng.reseed(seed_value)
		world.generate()
		log.start(seed_value)

	func act(action: Dictionary) -> Dictionary:
		var r := world.apply_action(action, gs)
		if r.get("ok", false):
			log.record(action, r, world.clock.tick)
		return r

	# Sim time passing, recorded the way `world/farm.gd:advance_sim` records it
	# (M2.5 WI-5): each brain Action carries the tick it was decided on and the
	# mark that says a brain decided it, and the log is marked with where the
	# clock got to — which is what `main.gd` writes beside every autosave, and
	# what lets a replay live out the pottering after the last Action.
	func tick(n: int) -> Array[Dictionary]:
		var taken := world.advance_ticks(n, gs)
		for t in taken:
			if t["result"].get("ok", false):
				log.record(t["action"], t["result"], int(t["tick"]), true)
			elif String(t.get("actor", "")) == SimWorld.ACTOR_CHICKEN:
				log.record_brain_decision(t)
		log.mark_tick(world.clock.tick)
		return taken

	# Re-base the log on a snapshot of right now, exactly as `main.gd` does when a
	# session continues from an autosave (`farm.start_replay_log_from_save`). Lets
	# a fixture arrange a farm however it likes — including in ways no sequence of
	# Actions would — and still hold a log that reproduces everything after it.
	# The seed goes with it, as `main.gd` passes it: a continued session runs on
	# the seed its farm was made from (WI-5).
	# A tile crossing, recorded the way `world/farm.gd:note_player_walk` records
	# one (M2.5 WI-6): the registry entry and the log entry are written together,
	# because a walk that moved her without saying so — or said so without moving
	# her — is exactly the divergence the pairing exists to prevent.
	func walk(event: String, dir: String, at: Vector2i) -> void:
		world.set_actor_pos(SimWorld.ACTOR_PLAYER, at, dir)
		log.record_walk(event, dir, at, world.clock.tick)

	func rebase() -> void:
		log = ReplayLog.new()
		var base = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
		log.start_from_save(base, world.gen_seed)
		# ...and back onto that seed and that save's place in its stream, which is
		# the WI-5 seed fix (and its 2026-10-08 completion) seen from the live side:
		# `main.gd` resumes the stream from the restored save before the continued
		# session takes a single action, so the session and its replay draw from
		# the same stream position. A fixture that skipped this would be testing a
		# session no player can have.
		SaveGame.resume_stream(base, world.gen_seed)

	func done() -> void:
		gs.free()


func _record_brain_step(log: ReplayLog, taken: Dictionary) -> void:
	if taken["result"].get("ok", false):
		log.record(taken["action"], taken["result"], int(taken["tick"]), true)
	elif log.record_decisions and String(taken.get("actor", "")) == SimWorld.ACTOR_CHICKEN:
		log.record_brain_decision(taken)


func _count_objects(world: SimWorld, kind: String) -> int:
	var n := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.objects[ty][tx] == kind:
				n += 1
	return n


# A farm far enough along that T-2's readiness gate is open: the cold open done,
# a harvest behind her, plenty planted, and a crow scheduled for today.
func _crow_ready_session(seed_value: int) -> LiveSession:
	var s := LiveSession.new(seed_value)
	ColdOpen.run(s.world, s.world, s.gs)
	s.gs.pouch["wheat"] = 500
	s.gs.watering_can_charges = 500
	s.gs.energy = 500
	s.gs.harvest_counts["wheat"] = 3
	for ty in range(3, 6):
		for tx in range(3, 10):
			s.world.set_tile_state(tx, ty, "seeded", "wheat")
	# Three sleeps past the handover, so this is a play-day a crow may visit.
	for _i in 3:
		s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	return s


# Farm work until the day's action clock reaches `n`. Tilling a tile and clearing
# it again is the cheapest repeatable player action there is.
func _work_until_actions(s: LiveSession, n: int) -> void:
	var t := Vector2i(10, 12)
	var guard := 0
	while s.gs.actions_today < n and guard < 200:
		guard += 1
		s.world.set_tile_state(t.x, t.y, "cleared")
		s.act({ "verb": "till", "target": t, "actor": "player" })


# One session, boiled down to a string: what the brains did, when, and where
# everybody ended up. Two runs of the same seed must produce the same string.
func _tick_trace(seed_value: int) -> String:
	var s := _crow_ready_session(seed_value)
	var out: PackedStringArray = []
	for i in 30:
		_work_until_actions(s, s.gs.actions_today + 2)
		for t in s.tick(40):
			out.append("%d:%s@%s" % [s.world.clock.tick, t["action"].get("verb", ""),
				t["action"].get("target", Vector2i(-1, -1))])
	for id in ["player", "chicken", "crow"]:
		out.append("%s=%s" % [id, s.world.actor_pos(id)])
	out.append("planted=%d acorns=%d" % [s.world.count_planted(), s.world.count_acorns()])
	s.done()
	return "|".join(out)


# --- The movement engine (M2.5 WI-4) ------------------------------------------

# A purpose-built arena rather than a carved-up farm: a movement test wants to
# say exactly where the wall is. Blank ground inside the border, with two walls
# running down it and one way round the south end of both —
#
#   x:      5        10       14      18
#   y 1     .        |        #       .      | barrier column: fence / hedge /
#   ...     .        |        #       .        closed gate, cycling by row
#   y 14    .        |        #       .      # rock column (a surface obstacle)
#   y 15-18 .   the way round both walls .
#
# so a walker must go the long way, a flyer and a burrower go straight, and a
# hopper crosses the barrier column but not the rocks.
func _movement_arena(seed_value: int = 4) -> SimWorld:
	var w := SimWorld.new()
	SimRng.reseed(seed_value)
	w.generate()
	for id in w.actors.keys():
		w.despawn_actor(String(id))
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			w.set_object(tx, ty, "")
			var edge := tx == 0 or ty == 0 or tx == SimWorld.MAP_WIDTH - 1 or ty == SimWorld.MAP_HEIGHT - 1
			w.set_tile_state(tx, ty, "border" if edge else "cleared")
	const BARRIERS := [WorldLayout.FENCE, WorldLayout.HEDGE, WorldLayout.GATE_CLOSED]
	for ty in range(1, 15):
		w.set_tile_state(10, ty, BARRIERS[(ty + 1) % BARRIERS.size()])
		w.set_tile_state(14, ty, "obstacle_rock")
	return w


# --- Q-67: the reference pathfinder, kept so the fast one can be held against it
#
# `Movement.path`, `Movement.reachable`, `SimWorld.is_walkable` and
# `SimWorld.get_object` were all rewritten for speed (Q-67, from M2.5 WI-12's
# profile: the A* was 44.9 µs a call and travel was 79% of a fast-forward). Every
# one of those rewrites is a claim that the *answer* did not change, and the
# answer is load-bearing in the strongest way this project has. D-9 records no
# motion at all, so every critter's walk in every recorded session — the robot
# fixture, the demo replay, a human's tablet session — is **recomputed** through
# these functions on replay. A route that broke a tie one tile differently would
# desync all of them, silently, and only the replay verifier would ever say so.
#
# So the implementations they replaced live on here, verbatim, and
# `test_pathfinder_identity` is element-by-element equality over a sweep. These
# four are the *old* code and are not to be tidied into calling the new one — that
# is the entire point of them.

func _ref_object(world: SimWorld, tx: int, ty: int) -> String:
	if ty >= 0 and ty < SimWorld.MAP_HEIGHT and tx >= 0 and tx < SimWorld.MAP_WIDTH:
		if world.objects[ty][tx] != "":
			return world.objects[ty][tx]
		if ty + 1 < SimWorld.MAP_HEIGHT and world.objects[ty + 1][tx] in ["cot", "well", "seed_box"]:
			return world.objects[ty + 1][tx]
	return ""


func _ref_walkable(world: SimWorld, tx: int, ty: int) -> bool:
	var tile := world.get_tile(tx, ty)
	if tile.is_empty():
		return false
	var state: String = tile.state
	if state == "border":
		return false
	# The dark outside a room (2026-09-06), mirrored here the moment the real
	# function gained it: this copy is only worth having while it asks the same
	# questions in the same order.
	if state == WorldLayout.VOID:
		return false
	if state.begins_with("obstacle"):
		return false
	if WorldLayout.is_boundary_state(state):
		return false
	var obj := _ref_object(world, tx, ty)
	if obj != "" and obj != "egg" and obj != "acorn":
		return false
	return true


# The old A*: a linear scan over an open list of freshly allocated Dictionaries,
# keeping the earliest of equal f-scores.
func _ref_path(world: SimWorld, mode: String, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if start == goal or not Movement.in_bounds(world, start) or not Movement.in_bounds(world, goal):
		return out
	if not Movement.passable(world, mode, start) or not Movement.can_stop(world, mode, goal):
		return out
	var came: Dictionary = {}
	var cost: Dictionary = { start: 0 }
	var open: Array[Dictionary] = [{ "t": start, "f": float(_ref_h(start, goal)) }]
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if open[i]["f"] < open[best]["f"]:
				best = i
		var cur: Vector2i = open[best]["t"]
		open.remove_at(best)
		if cur == goal:
			var t := cur
			while t != start:
				out.push_front(t)
				t = came[t]
			return out
		var here: int = int(cost[cur])
		for d in Movement.DIRS:
			var n: Vector2i = cur + d
			if not Movement.in_bounds(world, n) or not Movement.passable(world, mode, n):
				continue
			var step_cost := here + 1
			if step_cost < int(cost.get(n, 0x7FFFFFFF)):
				cost[n] = step_cost
				came[n] = cur
				open.append({ "t": n, "f": float(step_cost) + float(_ref_h(n, goal)) })
	return out


func _ref_h(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# The old flood fill: a `seen` Dictionary keyed on Vector2i and a separate queue.
func _ref_reachable(world: SimWorld, mode: String, start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not Movement.in_bounds(world, start) or not Movement.passable(world, mode, start):
		return out
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var idx := 0
	while idx < queue.size():
		var t := queue[idx]
		idx += 1
		out.append(t)
		for d in Movement.DIRS:
			var n: Vector2i = t + d
			if seen.has(n) or not Movement.in_bounds(world, n) or not Movement.passable(world, mode, n):
				continue
			seen[n] = true
			queue.append(n)
	return out


# The four worlds the sweep runs over, chosen for the four things that can make
# two shortest routes differ: ordinary terrain, walls to go round, open ground
# where every route is a diamond of equal-cost ties, and somewhere with no way in.
func _pathfinder_worlds() -> Array:
	return [
		["the farm as it generates", _pathfinder_farm()],
		["the arena (two walls to go round)", _movement_arena()],
		["an open field (every route a diamond of ties)", _open_field()],
		["a sealed room and a rock maze", _sealed_room()],
	]


func _pathfinder_farm() -> SimWorld:
	SimRng.reseed(1234)
	var w := SimWorld.new()
	w.generate()
	return w


func _open_field() -> SimWorld:
	var w := _movement_arena()
	for ty in range(1, SimWorld.MAP_HEIGHT - 1):
		for tx in range(1, SimWorld.MAP_WIDTH - 1):
			w.set_tile_state(tx, ty, "cleared")
	return w


func _sealed_room() -> SimWorld:
	var w := _open_field()
	# A hedged room with four walls and no door: a goal inside it is reachable by
	# a hopper and a burrower and by nobody else, which is the case where the old
	# A* flooded its whole component before giving up and the new one has to give
	# up in exactly the same place.
	for tx in range(20, 27):
		w.set_tile_state(tx, 6, WorldLayout.HEDGE)
		w.set_tile_state(tx, 12, WorldLayout.HEDGE)
	for ty in range(6, 13):
		w.set_tile_state(20, ty, WorldLayout.HEDGE)
		w.set_tile_state(26, ty, WorldLayout.HEDGE)
	# and a rock maze in the west, for the long way round.
	for ty in range(2, 16):
		if ty % 4 != 0:
			w.set_tile_state(6, ty, "obstacle_rock")
	for tx in range(2, 12):
		if tx % 3 != 0:
			w.set_tile_state(tx, 9, "obstacle_rock")
	return w


func _movement_trace(world: SimWorld, actor_id: String, steps: int) -> String:
	var out: PackedStringArray = []
	for i in steps:
		out.append("%s%s" % [Movement.step(world, actor_id, i), world.actor_pos(actor_id)])
	return "|".join(out)


# The goals the sweep asks for, relative to each start: one step each way, the
# short diagonals whose shortest routes are a diamond of ties, the axis runs, and
# hauls long enough to cross a wall or fall off the map.
const _SWEEP_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2), Vector2i(-2, 2),
	Vector2i(3, 2), Vector2i(2, 3), Vector2i(-3, -2), Vector2i(4, 0),
	Vector2i(0, -4), Vector2i(5, 3), Vector2i(-5, 3), Vector2i(6, 6),
	Vector2i(9, 0), Vector2i(0, 8), Vector2i(13, 7), Vector2i(-13, -7),
]


# Q-67. The pathfinder was rewritten for speed; this is the whole of the argument
# that it is still the same pathfinder. See the reference copies above for why the
# bar is byte-for-byte and not "still finds a shortest route".
func _session_with_brain_actions(seed_value: int) -> LiveSession:
	var s := LiveSession.new(seed_value)
	s.log.record_decisions = true
	for _day in 8:
		s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
		s.tick(400)
		for e in s.log.entries:
			if bool(e.get("brain", false)):
				return s
	return s


func _brain_entry_count(rlog: ReplayLog) -> int:
	var n := 0
	for e in rlog.entries:
		if bool(e.get("brain", false)):
			n += 1
	return n


func _ant_session(seed_value: int) -> LiveSession:
	var s := LiveSession.new(seed_value)
	for ty in range(3, 12):
		for tx in range(3, 20):
			s.world.set_tile_state(tx, ty, "cleared")
			s.world.set_object(tx, ty, "")
	for tx in range(10, 14):
		s.world.set_tile_state(tx, 5, "growing", "wheat")
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	return s


const ANT_NEST := Vector2i(5, 5)


func _release_scout(s: LiveSession) -> void:
	s.world.spawn_actor(SimWorld.ACTOR_ANT_SCOUT, SpeciesDefs.ANT_SCOUT, ANT_NEST, {
		"state": AntScoutBrain.STATE_SEARCH,
		"home_x": ANT_NEST.x, "home_y": ANT_NEST.y,
		"tgt_x": -1, "tgt_y": -1,
	})


# Sim time until the scout is on its way home (a trail exists, and is not yet
# complete), or until it is over. Returns whether it got there.
func _tick_until_homing(s: LiveSession, limit: int = 6000) -> bool:
	var spent := 0
	while spent < limit:
		s.tick(5)
		spent += 5
		if not s.world.has_actor(SimWorld.ACTOR_ANT_SCOUT):
			return false
		if String(s.world.actor(SimWorld.ACTOR_ANT_SCOUT)["extra"].get("state", "")) \
				== AntScoutBrain.STATE_HOME:
			return true
	return false


func _tick_until_column(s: LiveSession, limit: int = 8000) -> bool:
	var spent := 0
	while spent < limit:
		s.tick(10)
		spent += 10
		if not s.world.actors_of_species(SpeciesDefs.ANT_FORAGER).is_empty():
			return true
	return false


func _tick_until_raid_over(s: LiveSession, limit: int = 12000) -> void:
	var spent := 0
	while spent < limit and AntScoutBrain.raid_is_live(s.world):
		s.tick(25)
		spent += 25


func _trail_tiles(world: SimWorld) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.scent.read(Scent.TRAIL, Vector2i(tx, ty), world.clock.tick) > 0.0:
				out.append(Vector2i(tx, ty))
	return out


const MEADOW_FAR_CORNER := Vector2i(29, 17)
const MEADOW_ROW_Y := 5
const PEN_CROP := Vector2i(17, 10)


func _meadow_session(seed_value: int, with_crops: bool = true) -> LiveSession:
	var s := LiveSession.new(seed_value)
	for ty in range(3, 15):
		for tx in range(3, 23):
			s.world.set_tile_state(tx, ty, "cleared")
			s.world.set_object(tx, ty, "")
	if with_crops:
		for tx in range(10, 16):
			s.world.set_tile_state(tx, MEADOW_ROW_Y, "growing", "wheat")
	s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	return s


# A one-tile crop inside a ring of fence: the barrier class, built by hand so the
# test does not depend on where the generated layout happens to put a parcel.
# A walker has no route in and a hopper does, and that difference is the whole of
# WI-8f.
func _fence_pen(world: SimWorld) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			world.set_tile_state(PEN_CROP.x + dx, PEN_CROP.y + dy, WorldLayout.FENCE)
	world.set_tile_state(PEN_CROP.x, PEN_CROP.y, "growing", "wheat")


func _release_grazer(s: LiveSession, species: String, at: Vector2i) -> void:
	s.world.spawn_actor(species, species, at, {
		"state": GrazerBrain.STATE_GRAZE,
		"home_x": at.x, "home_y": at.y,
		"bites": 0, "tries": 0,
	})


func _release_songbird(s: LiveSession, from: Vector2 = Vector2(-2.0, 5.5)) -> void:
	s.world.spawn_actor(SpeciesDefs.SONGBIRD, SpeciesDefs.SONGBIRD,
		Vector2i(floori(from.x), floori(from.y)), {
			"state": SongbirdBrain.STATE_PERCHED,
			"fx": from.x, "fy": from.y,
			"tgt_x": -1, "tgt_y": -1,
			"perches": 0, "perch_until": 0, "ex": 0.0, "ey": 0.0,
		})


# Sim time until this actor's visit is over, or the limit runs out.
func _tick_until_gone(s: LiveSession, actor_id: String, limit: int = 8000) -> bool:
	var spent := 0
	while spent < limit and s.world.has_actor(actor_id):
		s.tick(10)
		spent += 10
	return not s.world.has_actor(actor_id)


func _state_of(world: SimWorld, actor_id: String) -> String:
	return String(world.actor(actor_id).get("extra", {}).get("state", ""))


# One visit, interrupted (`[Designer]` Q-63): let the animal take a mouthful, walk
# up to it until it bolts, walk away again, and let the rest of the visit play
# out. Returns what the farm lost by the end. The two answers to Q-63 are this
# same scenario on the same seed with one field of the species row different.
func _bite_then_scare(seed_value: int, species: String) -> Dictionary:
	var s := _meadow_session(seed_value)
	var dawn := s.world.count_planted()
	_release_grazer(s, species, Vector2i(5, 9))
	var bit := false
	var spent := 0
	while spent < 4000 and s.world.has_actor(species):
		s.tick(10)
		spent += 10
		if int(s.world.actor(species).get("extra", {}).get("bites", 0)) >= 1:
			bit = true
			break
	var bolted := false
	if bit:
		for _round in 20:
			s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, s.world.actor_pos(species) + Vector2i(1, 0))
			s.tick(3)
			if not s.world.has_actor(species):
				break
			if _state_of(s.world, species) == GrazerBrain.STATE_FLEE:
				bolted = true
				break
		s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	var gone := _tick_until_gone(s, species)
	s.tick(600)  # ...and it does not wander back in afterwards
	var out := {
		"bit": bit, "bolted": bolted, "gone": gone,
		"lost": dawn - s.world.count_planted(),
	}
	s.done()
	return out


const SEED_ROW_Y := 8
const WALLED_SEED := Vector2i(18, 12)


# Sow a handful of tiles: `seeded` is what `plant` leaves behind and what the mole
# comes for (`SimWorld.has_seed`).
func _sow(s: LiveSession, tiles: Array) -> void:
	for t in tiles:
		s.world.set_tile_state(int(t.x), int(t.y), "seeded", "wheat")


func _seeded_count(world: SimWorld) -> int:
	var n := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.has_seed(tx, ty):
				n += 1
	return n


# A seed inside a ring of rock: no walker and no hopper has a route in, and a
# burrower does not care. `_fence_pen`'s shape for the mode below the ground.
func _rock_pen(world: SimWorld, at: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			world.set_tile_state(at.x + dx, at.y + dy, "obstacle_rock")
	world.set_tile_state(at.x, at.y, "seeded", "wheat")


func _release_mole(s: LiveSession, at: Vector2i) -> void:
	s.world.spawn_actor(SpeciesDefs.MOLE, SpeciesDefs.MOLE, at, {
		"state": MoleBrain.STATE_TUNNEL,
		"under": true,
		"home_x": at.x, "home_y": at.y,
		"tgt_x": -1, "tgt_y": -1,
		"steals": 0,
	})


func _release_worm(s: LiveSession, at: Vector2i) -> void:
	s.world.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, at, {
		"state": WormBrain.STATE_HUNT,
		"home_x": at.x, "home_y": at.y,
		"tgt_x": -1, "tgt_y": -1,
		"meals": 0, "tries": 0, "stuck": 0, "detours": 0,
	})


# Sim time until this actor is above ground (or the limit runs out).
func _tick_until_up(s: LiveSession, actor_id: String, limit: int = 4000) -> bool:
	var spent := 0
	while spent < limit and s.world.has_actor(actor_id) \
			and Movement.is_under(s.world, actor_id):
		s.tick(5)
		spent += 5
	return s.world.has_actor(actor_id) and not Movement.is_under(s.world, actor_id)


const BOT_CROP_ROW_Y := 10
const BOT_CROP_X0 := 12
const BOT_CROP_X1 := 18
const BOT_HER_TILE := Vector2i(8, 6)


func _bot_yard(seed_value: int, with_crops: bool = false) -> LiveSession:
	var s := LiveSession.new(seed_value)
	for ty in range(3, 17):
		for tx in range(3, 28):
			s.world.set_tile_state(tx, ty, "cleared")
			s.world.set_object(tx, ty, "")
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if s.world.get_object(tx, ty) == "acorn":
				s.world.set_object(tx, ty, "")
	if with_crops:
		for tx in range(BOT_CROP_X0, BOT_CROP_X1):
			s.world.set_tile_state(tx, BOT_CROP_ROW_Y, "growing", "wheat")
	s.world.set_actor_pos(SimWorld.ACTOR_PLAYER, BOT_HER_TILE)
	s.gs.energy = 500
	s.gs.watering_can_charges = 500
	s.gs.pouch["wheat"] = 500
	return s


# How far a bot is from the actor it belongs to, in tiles walked.
func _bot_gap(world: SimWorld, bot_id: String, owner_id: String = SimWorld.ACTOR_PLAYER) -> int:
	var a := world.actor_pos(bot_id)
	var b := world.actor_pos(owner_id)
	return absi(a.x - b.x) + absi(a.y - b.y)


# Her walking, one tile at a time, recorded exactly as `world/farm.gd` records a
# crossing (M2.5 WI-6) — which is what makes a follower's whole session
# replayable: nothing can recompute where she chose to go, so the log carries it
# and `ReplayLog._apply_v2` puts her back.
func _walk_her(s: LiveSession, to: Vector2i, ticks_between: int = 4) -> void:
	var at := s.world.actor_pos(SimWorld.ACTOR_PLAYER)
	while at != to:
		var d := Vector2i(signi(to.x - at.x), 0)
		if d.x == 0:
			d = Vector2i(0, signi(to.y - at.y))
		at += d
		s.walk("step", Movement.facing_from(at - d, at), at)
		s.tick(ticks_between)


# The tile the day's first scheduled crow will come for, worked out **from the
# schedule** rather than from watching: `CrowBrain.send` picks it with a
# stateless draw off (day, arrival), so a test can know where a bird is going
# before it exists — which is what lets the shoo tests place a bot's patch to
# cover it, or not, and change nothing else.
func _crow_target_for(s: LiveSession, arrival: int) -> Vector2i:
	var pick: Dictionary = s.world.choose_crow_target(
		SimRng.stateless(int(s.gs.day), 1000 + arrival))
	return pick.get("tile", Vector2i(-1, -1))


# A farm a crow may visit, with one appointment in the book (T-2's readiness
# gate, T-20's action clock). `crop_crows_seen` is spent, so the bird that comes
# is **not** the scripted harmless one and will actually take a crop — which is
# what the control run has to be able to lose.
func _bot_crow_ready(s: LiveSession, arrival: int = 1) -> void:
	s.gs.day = 6
	s.gs.takeover_day = 1
	s.gs.harvest_counts["wheat"] = 3
	s.gs.crop_crows_seen = 1
	s.gs.actions_today = 0
	var book: Array[int] = [arrival]
	s.gs.crow_schedule = book


# One shoo scenario, played out: the same farm, the same crow, the same bot, and
# **one number different** — how far the machine considers its business.
func _shoo_run(seed_value: int, radius: float) -> Dictionary:
	var s := _bot_yard(seed_value, true)
	_bot_crow_ready(s)
	var target := _crow_target_for(s, 1)
	var home := target + Vector2i(0, 2)
	BotBrain.deploy(s.world, "shoo_bot", BotBrain.CONFIG_SHOO, home,
		{ "home_x": home.x, "home_y": home.y, "radius": radius })
	var planted_before := s.world.count_planted()
	# One action of hers moves T-20's clock, which is the only thing that brings a
	# crow (the gateway decides it, not this test).
	s.act({ "verb": "till", "target": Vector2i(5, 12), "actor": "player" })
	var arrived := s.world.has_actor(SimWorld.ACTOR_CROW)
	var reason := ""
	var spent := 0
	while spent < 900 and s.world.has_actor(SimWorld.ACTOR_CROW):
		s.tick(5)
		spent += 5
		var st := String(s.world.actor(SimWorld.ACTOR_CROW).get("extra", {}).get("state", ""))
		if st == "leaving" and reason == "":
			reason = String(s.world.actor(SimWorld.ACTOR_CROW)["extra"].get("leaving_because", ""))
	var scares := 0
	var by := ""
	for e in s.log.entries:
		if String(e.get("verb", "")) == "crow_scared":
			scares += 1
			by = String(e.get("by", ""))
			_assert_quiet(bool(e.get("brain", false)),
				"the bot's scare is recorded as a brain Action")
	var out := {
		"target": target,
		"arrived": arrived,
		"reason": reason,
		"lost": planted_before - s.world.count_planted(),
		"scares": scares,
		"by": by,
		"scared_counter": int(s.gs.crows_scared),
		"seen": int(s.gs.crows_seen),
		"booked": s.gs.crow_schedule.size(),
		"bot_home": home,
		"bot_end": s.world.actor_pos("shoo_bot"),
	}
	s.done()
	return out


# `tools/benchmark_sim.gd`'s inner loop, in the shape that file runs it: a
# generous day's work over a 10x8 plot, applied as one actor.
func _benchmark_day(world: SimWorld, gs, actor_id: String) -> int:
	var applied := 0
	gs.energy = 1000000
	gs.watering_can_charges = 1000000
	gs.pouch["wheat"] = 1000000
	for ty in range(4, 12):
		for tx in range(12, 22):
			var st: String = world.get_tile(tx, ty).get("state", "")
			var verb := ""
			match st:
				"obstacle_rock": verb = "clear_rock"
				"obstacle_log": verb = "clear_log"
				"obstacle_weed": verb = "clear_weed"
				"cleared": verb = "till"
				"tilled": verb = "plant"
				"seeded", "growing": verb = "water"
				"ready": verb = "harvest"
			if verb == "":
				continue
			var action := { "verb": verb, "target": Vector2i(tx, ty), "actor": actor_id }
			if verb == "plant":
				action["seed_type"] = "wheat"
			world.apply_action(action, gs)
			applied += 1
	world.apply_action({ "verb": "sleep", "actor": "world" }, gs)
	return applied + 1


# The grids, as a string. What the benchmark actually produces, with the registry
# deliberately left out of it — the whole question there is whether *registering*
# the worker changes the work.
func _grid_signature(world: SimWorld) -> String:
	return "%s|%s" % [str(world.tiles), str(world.objects)]


func _obs_tile(v: Array, dx: int, dy: int, r: int, head: int, nch: int) -> Array:
	var side := 2 * r + 1
	var idx := (dy + r) * side + (dx + r)
	return v.slice(head + idx * nch, head + (idx + 1) * nch)


const BANDIT_DECISIONS := 10
# Deliberately below the robot's own 0.05 [Playtest]. See `test_policy`.
const BANDIT_RATE := 0.02


func _bandit_day(state: Dictionary, decisions: int, rate: float) -> Dictionary:
	var obs: Array = [1.0]
	var w: Array = state["weights"]
	var trace := Policy.new_weights(1, 2)
	var acc := Policy.new_weights(1, 2)
	var score := 0.0
	var salt: int = hash("bandit") ^ (int(state["days"]) * 7919)
	for d in decisions:
		var p := Policy.probs(Policy.logits(w, 1, 2, obs))
		var action := Policy.sample(p, Policy.draw_u(salt, d))
		Policy.add_into(trace, Policy.grad_log_prob(obs, p, action, 1, 2), 1.0)
		var r := 1.0 if action == 0 else 0.0
		if r != 0.0:
			Policy.add_into(acc, trace, r)
			score += r
	state["weights"] = Policy.night_update(w, acc, trace, float(state["baseline"]), rate)
	state["baseline"] = (float(state["baseline"]) * int(state["days"]) + score) / float(int(state["days"]) + 1)
	state["last_score"] = score
	state["days"] = int(state["days"]) + 1
	return state


func _bandit_run(seed_value: int, days: int) -> Dictionary:
	SimRng.reseed(seed_value)
	var state := {
		"weights": Policy.new_weights(1, 2),
		"baseline": 0.0,
		"days": 0,
		"last_score": 0.0,
	}
	for _d in days:
		_bandit_day(state, BANDIT_DECISIONS, BANDIT_RATE)
	return state


# What the trained bandit thinks of the arm that pays.
func _bandit_p0(state: Dictionary) -> float:
	return float(Policy.probs(Policy.logits(state["weights"], 1, 2, [1.0]))[0])


const MK3_PATCH := Rect2i(9, 8, 6, 4)
const MK3_SPOT := Vector2i(11, 9)


func _mk3_yard(seed_value: int) -> LiveSession:
	var s := _bot_yard(seed_value)
	for ty in range(MK3_PATCH.position.y, MK3_PATCH.end.y):
		for tx in range(MK3_PATCH.position.x, MK3_PATCH.end.x):
			s.world.set_tile_state(tx, ty, "seeded", "wheat")
	s.gs.gold = 2000
	# A farm far enough along to be sold a Mark III (S-12): its mark-2 has chased a
	# bird and a bench is standing. Arranged rather than played, the way the gold
	# above is — every test below this line is about what a learning robot does, and
	# the ladder that put it on the shelf is `test_robot_ladder`'s subject.
	s.world.earn(SimWorld.RUNG_MK2_WORKED)
	s.world.earn(SimWorld.RUNG_DESK_PLACED)
	return s


func _mk3_place(s: LiveSession, at: Vector2i) -> String:
	s.act({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" })
	return String(s.act({ "verb": "place", "target": at,
		"item": "bot_mk3", "actor": "player" }).get("machine", ""))


# Is every value in here one of the five things JSON has? Recursive, because a
# robot's `extra` is a dictionary holding arrays holding numbers, and ground rule
# 4 binds all the way down: `extra` is deep-copied into the save and compared by
# `capture_canonical`, so one Vector2i anywhere in it is a robot that comes back
# from disk as a different robot.
func _json_plain(value) -> bool:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for x in value:
				if not _json_plain(x):
					return false
			return true
		TYPE_DICTIONARY:
			for k in value:
				if typeof(k) != TYPE_STRING or not _json_plain(value[k]):
					return false
			return true
	return false


# A robot that will certainly water, whatever it draws. Its whole policy is one
# enormous bias on the water row, which `probs` turns into a flat 1 — so the six
# actions become one action and the *outcome* is the only thing left varying.
# The scoring rule is what these tests are after, and this is how it is asked
# through the real brain rather than by calling `on_result` by hand.
func _mk3_make_certain(extra: Dictionary, action: int) -> void:
	var width: int = Observation.size(extra.get("spec", Observation.spec_default()))
	var w := Policy.new_weights(width, BotBrain.LEARN_ACTIONS)
	w[action * (width + 1) + width] = 1000.0
	extra["weights"] = w


# How many Actions a robot actually put through the gateway over this many ticks.
# The difference between "it decided" and "it asked for anything" is the whole of
# what a spent decision looks like from outside the brain: the second is gone,
# and the world never heard from it.
func _mk3_asked(s: LiveSession, actor_id: String, span: int) -> int:
	var n := 0
	for t in s.tick(span):
		if String(t["action"].get("actor", "")) == actor_id:
			n += 1
	return n


func _numbers_match(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] is Array:
			if not (b[i] is Array) or not _numbers_match(a[i] as Array, b[i] as Array):
				return false
		elif not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true


# --- The crate remembers (v0.2.2 WI-9, Q-98) ----------------------------------
#
# Ruled 2026-09-10: "pick up is just repositioning, it shouldn't factory reset the
# robot." Before this, tapping a Mark III and choosing "pick it up" was the most
# expensive accident available in the game: `collect` despawned the actor and added
# one to an anonymous crate, and the next `place` deployed a factory machine — so a
# week of practice, the dials she had set on the workbench and every row of the
# ledger went with it, silently.
#
# What is asserted here is the round trip rather than the storage: the same robot
# back out as went in, a blank one when the crate has no memories, nothing at all
# kept for a machine that has nothing to keep — and all of that still true after a
# save and after a replay, because what the crate remembers is now part of the farm
# a session is checked against.
func _yard_square(world: SimWorld, avoid: Vector2i = Vector2i(-1000, -1000)) -> Vector2i:
	for ty in range(1, WorldLayout.PAGE_ROWS - 1):
		for tx in range(1, SimWorld.MAP_WIDTH - 2):
			var here := Vector2i(tx, ty)
			if absi(here.x - avoid.x) <= 2 and here.y == avoid.y:
				continue
			if String(world.get_tile(tx, ty).get("state", "")) != WorldLayout.YARD:
				continue
			if world.get_object(tx, ty) != "" or world.get_object(tx, ty - 1) != "":
				continue
			if not world.placeable_at(here) or not world.placeable_at(here + Vector2i(1, 0)):
				continue
			return here
	return Vector2i(-1, -1)


# --- Does it actually get better? (v0.2.1 WI-5) -------------------------------
#
# Everything above proves the Mark III *runs*: it decides once a second, it is
# paid for outcomes and not for gestures, it survives a save, and a recorded
# session replays into the same robot. None of it says the machine is worth
# owning. This one does, and it is deliberately the only test in the file that
# asks a question about a whole week rather than about a rule.
#
# The measurement lives in `tools/demo_learning_robot.gd`, which prints it as a
# table for a person to read, so the report a human sees and the gate CI runs are
# one week and not two (`test_robot_usefulness` is built the same way and says
# more about why).
const HER_BED := Rect2i(20, 12, 4, 4)


func _her_bed(s: LiveSession) -> Array[Vector2i]:
	var bed: Array[Vector2i] = []
	for ty in range(HER_BED.position.y, HER_BED.end.y):
		for tx in range(HER_BED.position.x, HER_BED.end.x):
			s.world.set_tile_state(tx, ty, "seeded", "wheat")
			s.world.get_tile(tx, ty).watered_today = false
			bed.append(Vector2i(tx, ty))
	return bed


func _flat(tiles: Array[Vector2i]) -> Array:
	var out: Array = []
	for t in tiles:
		out.append(t.x)
		out.append(t.y)
	return out


func _assign(s: LiveSession, bot: String, tiles: Array[Vector2i],
		at := Vector2i(-1, -1)) -> Dictionary:
	var aim := at
	if aim.x < 0:
		aim = tiles[0] if not tiles.is_empty() else s.world.actor_pos(bot)
	return s.act({ "verb": "assign_tiles", "target": aim, "machine": bot,
		"tiles": _flat(tiles), "actor": "player" })


# How far a tile is from the nearest square of a bed, the way the robot's view
# measures it: a square window, so the larger of the two offsets.
func _gap_to(at: Vector2i, bed: Array[Vector2i]) -> int:
	var best := 1 << 30
	for t in bed:
		best = mini(best, maxi(absi(t.x - at.x), absi(t.y - at.y)))
	return best


func _shelf_yard(seed_value: int) -> Dictionary:
	var s := _mk3_yard(seed_value)
	var bot := _mk3_place(s, MK3_SPOT)
	var bench := _yard_square(s.world)
	s.act({ "verb": "buy_machine", "item": "workbench", "actor": "player" })
	s.act({ "verb": "place", "target": bench, "item": "workbench", "actor": "player" })
	s.gs.gold = 2000
	return { "s": s, "bot": bot, "bench": bench }


func _shelf_buy(s: LiveSession, bot: String, bench: Vector2i, item := "pace") -> Dictionary:
	return s.act({ "verb": "buy_upgrade", "target": bench, "machine": bot, "item": item,
		"actor": "player" })


func _set_pace(s: LiveSession, bot: String, pace: int) -> Dictionary:
	return s.act({ "verb": "set_pace", "target": s.world.actor_pos(bot), "machine": bot,
		"pace": pace, "actor": "player" })


func _buy_pace(s: LiveSession, bot: String, bench: Vector2i, pace: int) -> Dictionary:
	return s.act({ "verb": "buy_pace", "target": bench, "machine": bot,
		"pace": pace, "actor": "player" })


# A cleared yard with the barn bought and put down through the ordinary `place`
# verb. Returns [world, anchor, room id, cow id].
func _placed_barn_world(seed_value: int) -> Array:
	GameState.reset()
	SimRng.reseed(seed_value)
	var world := SimWorld.new(); world.generate()
	var spot := Vector2i(-1, -1)
	for y in range(8, 18):
		for x in range(5, 24):
			for dy in range(-1, 3):
				for dx in range(-1, 5):
					world.set_tile_state(x + dx, y + dy, "cleared")
			if world.placeable_at(Vector2i(x, y), "industrial_barn") \
					and world.placeable_at(Vector2i(x, y + 2)):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	GameState.gold = 500
	GameState.harvest_counts["egg"] = 10
	world.apply_action({ "verb": "buy_machine", "item": "industrial_barn", "actor": "player" }, GameState)
	var laid := world.apply_action({ "verb": "place", "target": spot, "item": "industrial_barn",
		"actor": "player" }, GameState)
	return [world, spot, String(laid.get("room", "")), String(laid.get("cow", ""))]

func _barn_assert_tick_drawn(world: SimWorld, what: String) -> void:
	var t := world.clock.tick
	var before := SaveGame.capture_canonical(world, GameState)
	var first := var_to_str(BarnPresentation.drawn_state(world, "barn_1", t))
	OS.delay_msec(150)
	var later := var_to_str(BarnPresentation.drawn_state(world, "barn_1", t))
	_assert(first == later and first != var_to_str({}),
		"%s: the same saved tick draws the same barn after real time passes" % what)
	_assert(SaveGame.capture_canonical(world, GameState) == before,
		"%s: drawing the barn changes nothing in the world" % what)
	var reloaded := SimWorld.new()
	_assert(SaveGame.restore(SaveGame.capture(world, GameState), reloaded, GameState)
		and reloaded.clock.tick == t
		and var_to_str(BarnPresentation.drawn_state(reloaded, "barn_1", t)) == first,
		"%s: and a reloaded save draws it identically at that tick" % what)


# The 500-gold shop card is a barn-plus-first-cow bundle. The cow is created by
# the accepted placement Action, not by the renderer, so a save and replay keep
# the same animal and later barns do not create a second one.
func _barn_world() -> SimWorld:
	var world := SimWorld.new(); world.generate()
	for y in range(9, 13):
		for x in range(10, 14):
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	var room_id := world.open_room("industrial_barn", Vector2i(10, 10))
	_assert(room_id != "", "the barn fixture opens its six-by-four room")
	world.rooms["barn_1"] = world.rooms[room_id]
	world.rooms.erase(room_id)
	world.make_barn("barn_1", Vector2i(10, 10))
	world.schedule_all_brains()
	return world


# Runs the farm until `done` says so (or `limit` ticks pass), one tick at a time.
func _barn_run_until(world: SimWorld, done: Callable, limit: int = 5000) -> bool:
	for i in limit:
		if done.call():
			return true
		world.advance_ticks(1, GameState)
	return done.call()


# MUST 1: a barn and its cow survive the trip through a file, mid-visit and mid-line.

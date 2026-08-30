# gen_demo_replay.gd — build the shipped attract-loop session (T-17 / Q-40)
#
#   godot --headless --path . --script res://tools/gen_demo_replay.gd
#
# Writes `assets/demo/demo_replay.json`: the farm the title screen plays when the
# player has no session of their own — a fresh install, or a build whose stamp no
# longer matches theirs (Q-41).
#
# **Sim-only by design.** No autoloads, no rendering, no scene tree: it drives
# SimWorld directly and writes an action stream. That is also why it can run in
# CI without a display.
#
# The lesson this file exists to enforce, from the T-16 spike: *a replay can
# verify perfectly and still read as a broken farm.* The spike's first recorded
# session cleared and tilled tile-by-tile, which left bare grass notches through
# the middle of the plot and looked like a playback bug rather than what it was —
# a gap in the recorder. So every assertion below is about whether the result is
# **nice to watch**, not whether it is valid. They all hard-fail.
extends SceneTree

const OUT_PATH := "res://assets/demo/demo_replay.json"
const SEED := 20260830          # fixed, so the demo is reproducible byte-for-byte
const MIN_DAYS := 3
const PLOT_ROWS := [3, 4, 5]
const PLOT_COLS := [13, 14, 15, 16, 17, 18]

var _fail := 0


func _init() -> void:
	print("=".repeat(60))
	print("TINY FARM — demo replay generator (T-17)")
	print("=".repeat(60))

	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var world := SimWorld.new()
	SimRng.reseed(SEED)
	world.generate()

	var log := ReplayLog.new()
	log.start(SEED)

	# The cold open first, so the demo shows the farm the player would actually be
	# handed rather than one that skipped its own opening. Stepped rather than
	# `ColdOpen.run()`, because run() applies to the world without recording and
	# every action here has to land in the log.
	_check(_run_cold_open(world, gs, log), "the cold open ran to completion and was recorded")

	var refused := 0
	var days := 0
	var planted_today: Array[Vector2i] = []

	# Three days of tidy, legible work. Whole passes rather than tile-by-tile:
	# the spike's notch bug came from deciding each tile's verb as the loop
	# reached it, so a tile cleared on the way past never got tilled.
	for day in MIN_DAYS:
		planted_today.clear()
		refused += _pass(world, gs, log, "till")
		refused += _pass(world, gs, log, "plant", planted_today)
		refused += _pass(world, gs, log, "water")
		refused += _pass(world, gs, log, "harvest")
		# Sleep last, always, so the recording ends on a resolved day.
		var sleep := { "verb": "sleep", "actor": "world", "weather": "sunny" }
		var r := world.apply_action(sleep, gs)
		_check(r.get("ok", false), "day %d ended with a sleep" % (day + 1))
		log.record(sleep, r)
		days += 1

	# --- Quality assertions. All hard-fail; none is about validity. ----------
	_check(refused == 0, "no refused actions in the recording (%d)" % refused)
	_check(days >= MIN_DAYS, "at least %d in-game days (%d)" % [MIN_DAYS, days])
	_check(_last_verb(log) == "sleep", "the recording ends on a sleep")
	_check(_unwatered(world) == 0,
		"every planted tile was watered the day it was planted (%d dry)" % _unwatered(world))
	_check(_notches(world) == 0,
		"the worked plot is contiguous — no bare grass notches (%d)" % _notches(world))
	_check(gs.seeds.get("wheat", 0) > 0, "the seed pouch never hit zero mid-pass")
	_check(log.entries.size() >= 20, "the session is long enough to watch (%d actions)" % log.entries.size())

	# --- Self-check: does it reproduce what it recorded? ---------------------
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	log.apply_to(w2, gs2)
	_check(SaveGame.capture_canonical(world, gs) == SaveGame.capture_canonical(w2, gs2),
		"replaying the file reproduces the generator's own end state")

	# --- Write, then reload and verify what actually landed on disk ----------
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/demo"))
	_check(log.save_to(OUT_PATH), "wrote %s" % OUT_PATH)
	var reloaded := ReplayLog.load_from(OUT_PATH)
	_check(reloaded != null and reloaded.entries.size() == log.entries.size(),
		"and it reloads with every action intact")
	if reloaded != null:
		var w3 := SimWorld.new()
		var gs3 = load("res://systems/game_state.gd").new()
		reloaded.apply_to(w3, gs3)
		_check(SaveGame.capture_canonical(world, gs) == SaveGame.capture_canonical(w3, gs3),
			"and the file on disk reproduces the same farm")
		gs3.free()

	print("")
	print("  %d actions · %d days · build %s" % [log.entries.size(), days, log.build_id])
	print("=".repeat(60))
	print("Results: %s" % ("FAILED" if _fail > 0 else "PASSED"))
	print("=".repeat(60))
	gs.free()
	gs2.free()
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ✓ " + label)
	else:
		_fail += 1
		print("  ✗ FAIL: " + label)


func _run_cold_open(world: SimWorld, gs, log: ReplayLog) -> bool:
	for _i in ColdOpen.MAX_STEPS:
		var a := ColdOpen.next_action(world, gs)
		if a.is_empty():
			return ColdOpen.is_done(world)
		var r := world.apply_action(a, gs)
		if not r.get("ok", false):
			return false
		log.record(a, r)
	return false


# One verb across the whole plot, in a fixed order, recording what resolves.
func _pass(world: SimWorld, gs, log: ReplayLog, verb: String,
		planted: Array[Vector2i] = []) -> int:
	var refused := 0
	for ty in PLOT_ROWS:
		for tx in PLOT_COLS:
			var t := Vector2i(tx, ty)
			var st := String(world.get_tile(t.x, t.y).get("state", ""))
			if not _wants(verb, st, gs):
				continue
			var a := { "verb": verb, "target": t, "actor": "player" }
			if verb == "plant":
				a["seed_type"] = "wheat"
			var r := world.apply_action(a, gs)
			if r.get("ok", false):
				log.record(a, r)
				if verb == "plant":
					planted.append(t)
			else:
				refused += 1
	return refused


# Whether this tile is one the pass should touch. Checked before applying, so a
# refusal in the recording is a real fault rather than an expected miss.
func _wants(verb: String, state: String, gs) -> bool:
	match verb:
		"till":
			return state == "cleared"
		"plant":
			return state == "tilled" and gs.seeds.get("wheat", 0) > 1
		"water":
			return state == "seeded" or state == "growing"
		"harvest":
			return state == "ready"
	return false


func _last_verb(log: ReplayLog) -> String:
	if log.entries.is_empty():
		return ""
	return String(log.entries[log.entries.size() - 1].get("verb", ""))


func _unwatered(world: SimWorld) -> int:
	var n := 0
	for ty in PLOT_ROWS:
		for tx in PLOT_COLS:
			var tile := world.get_tile(tx, ty)
			var st := String(tile.get("state", ""))
			if (st == "seeded" or st == "growing") and not tile.get("watered_today", false):
				n += 1
	return n


# A tile inside the worked plot that is still bare grass, with worked tiles on
# both sides of it. This is the exact shape the spike's first recording produced.
func _notches(world: SimWorld) -> int:
	var n := 0
	for ty in PLOT_ROWS:
		for i in range(1, PLOT_COLS.size() - 1):
			var here := String(world.get_tile(PLOT_COLS[i], ty).get("state", ""))
			if here != "cleared":
				continue
			var left := String(world.get_tile(PLOT_COLS[i - 1], ty).get("state", ""))
			var right := String(world.get_tile(PLOT_COLS[i + 1], ty).get("state", ""))
			if left != "cleared" and right != "cleared":
				n += 1
	return n

# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

func test_replay() -> void:
	print("\n--- Replay Determinism Tests ---")
	var GEN := 99
	var rlog := ReplayLog.new()
	rlog.start(GEN)

	GameState.reset()
	SimRng.reseed(GEN)
	var world := SimWorld.new()
	world.generate()

	var a := Vector2i(5, 2)
	var b := Vector2i(7, 2)
	_replay_do(world, rlog, { "verb": "till", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "plant", "target": a, "seed_type": "wheat", "actor": "player" })
	_replay_do(world, rlog, { "verb": "water", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "till", "target": b, "actor": "player" })
	_replay_do(world, rlog, { "verb": "plant", "target": b, "seed_type": "wheat", "actor": "player" })
	_replay_do(world, rlog, { "verb": "water", "target": b, "actor": "player" })
	_replay_do(world, rlog, { "verb": "sleep", "actor": "world" })
	for i in 7:  # entity RNG noise the replay will NOT repeat
		SimRng.randf()
	_replay_do(world, rlog, { "verb": "water", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "eat_crop", "target": b, "actor": "crow" })
	_replay_do(world, rlog, { "verb": "lay_egg", "target": Vector2i(7, 3), "actor": "chicken" })
	_replay_do(world, rlog, { "verb": "sleep", "actor": "world" })
	SimRng.randf()
	_replay_do(world, rlog, { "verb": "water", "target": a, "actor": "player" })
	_replay_do(world, rlog, { "verb": "sleep", "actor": "world" })
	var hr := _replay_do(world, rlog, { "verb": "harvest", "target": a, "actor": "player" })
	_assert(hr.get("ok", false) and hr.get("crop_type", "") == "wheat", "scripted session harvests wheat")
	_replay_do(world, rlog, { "verb": "collect", "target": Vector2i(7, 3), "actor": "player" })
	_replay_do(world, rlog, { "verb": "sell", "actor": "player" })
	_assert(GameState.gold == 10 and int(GameState.bin_reserve.wheat) == 6,
		"the scripted session reserves wheat and sells its egg for ten gold")
	var live_snap := _replay_snapshot(world)

	var rlog2 := ReplayLog.from_json(rlog.to_json())
	_assert(rlog2.entries.size() == rlog.entries.size(), "replay JSON round-trip keeps all entries")
	var world2 := SimWorld.new()
	rlog2.apply_to(world2, GameState)
	var replay_snap := _replay_snapshot(world2)
	_assert(replay_snap == live_snap, "replay reproduces exact end state despite RNG noise")

func test_save_game() -> void:
	print("\n--- SaveGame v1 Tests ---")

	GameState.reset()
	SimRng.reseed(55)
	var world := SimWorld.new()
	world.generate()
	# Mutate some state through actions so the save is non-trivial
	world.apply_action({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "plant", "target": Vector2i(5, 2), "seed_type": "wheat", "actor": "player" }, GameState)
	world.apply_action({ "verb": "water", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	GameState.gold = 123
	GameState._milestones_earned = { "first_harvest": true }
	SaveGame.note_session(GameState, world, "start")
	_assert(GameState.save_lineage == [{
		"build": ReplayLog.current_build(), "day": 2,
		"tick": world.clock.tick, "event": "start",
	}], "a new farm starts its build lineage")

	var live := JSON.stringify(SaveGame.capture(world, GameState))

	# Round-trip through JSON text (as on disk), restore into fresh objects
	var parsed = JSON.parse_string(live)
	var world2 := SimWorld.new()
	GameState.reset()
	var ok := SaveGame.restore(parsed, world2, GameState)
	_assert(ok, "restore accepts v1 save")
	_assert(GameState.gold == 123, "gold restored")
	_assert(GameState.day == 2, "day restored")
	_assert(GameState._milestones_earned.has("first_harvest"), "milestones restored")
	_assert(world2.get_tile(5, 2).state in ["growing", "seeded"], "planted tile restored")
	var roundtrip := JSON.stringify(SaveGame.capture(world2, GameState))
	_assert(roundtrip == live, "capture->restore->capture is value-identical")

	# Continue adds only a genuinely new build. The build argument is injectable
	# here so the test never rewrites the process-wide project setting.
	SaveGame.note_session(GameState, world2, "resume", ReplayLog.current_build())
	_assert(GameState.save_lineage.size() == 1,
		"continuing under the same build does not repeat the lineage entry")
	SaveGame.note_session(GameState, world2, "resume", "future-build")
	_assert(GameState.save_lineage.size() == 2,
		"continuing under a different build adds a lineage entry")
	_assert(GameState.save_lineage[-1] == {
		"build": "future-build", "day": 2,
		"tick": world2.clock.tick, "event": "resume",
	}, "the resume entry records its build, day and tick")

	var canonical_with_lineage := SaveGame.capture_canonical(world2, GameState)
	GameState.save_lineage.clear()
	_assert(SaveGame.capture_canonical(world2, GameState) == canonical_with_lineage,
		"canonical state is byte-identical with and without build lineage")

	# Unknown version refused
	var bad = JSON.parse_string(live)
	bad["version"] = 999
	_assert(not SaveGame.restore(bad, SimWorld.new(), GameState), "unknown save version refused")


func test_interrupted_save_write() -> void:
	print("\n--- Interrupted save write Tests ---")
	_wipe_dir(SLOT_SCRATCH)
	var path := SaveSlots.save_path(1, SLOT_SCRATCH)
	_write_text(path, "the farm before this save")
	_write_text(path + ".bak", "the parked farm")
	_assert(not AtomicFileWriter.write_text(path, "the unfinished farm", true),
		"a write stopped before replacement reports failure")
	_assert(_read_text(path) == "the farm before this save",
		"a write interrupted before replacement leaves the old farm intact")
	_assert(_read_text(path + ".bak") == "the parked farm",
		"an interrupted save does not disturb the parked backup")
	_wipe_dir(SLOT_SCRATCH)


# --- Three farms, three directories (S-14) ------------------------------------
#
# Everything below runs under SLOT_SCRATCH, never under `user://slot1` and never
# against `user://autosave.json`. A developer's own farms live at those paths and
# a suite that writes them is a suite that eats somebody's game.
func test_save_slots() -> void:
	print("\n--- Save slots: three farms, three directories (S-14) ---")
	_wipe_dir(SLOT_SCRATCH)

	# The shipped layout, asserted as literal paths: every tool in the repo reads
	# one of these three file names, and a slot must not have renamed any of them.
	_assert(SaveSlots.COUNT == 3, "the game keeps three farms")
	_assert(SaveSlots.save_path(1) == "user://slot1/autosave.json",
		"slot 1's farm is user://slot1/autosave.json")
	_assert(SaveSlots.replay_path(2) == "user://slot2/session_replay.json",
		"slot 2's action log keeps the name every tool already reads")
	_assert(SaveSlots.trace_path(3) == "user://slot3/session_trace.jsonl",
		"and slot 3's trace does too")
	_assert(SaveSlots.clamp_slot(0) == 1 and SaveSlots.clamp_slot(9) == 3,
		"a slot number out of range lands on a real slot rather than a stray directory")

	# use_slot derives all three paths together, for each of the three farms.
	var held := [GameState.save_path, GameState.replay_path, GameState.trace_path, GameState.slot]
	for n in [1, 2, 3]:
		GameState.use_slot(n, SLOT_SCRATCH)
		_assert(GameState.slot == n, "use_slot(%d) remembers which farm is being played" % n)
		_assert(GameState.save_path == SLOT_SCRATCH + "slot%d/autosave.json" % n
				and GameState.replay_path == SLOT_SCRATCH + "slot%d/session_replay.json" % n
				and GameState.trace_path == SLOT_SCRATCH + "slot%d/session_trace.jsonl" % n,
			"use_slot(%d) points the save, the replay and the trace at that farm" % n)
		_assert(DirAccess.dir_exists_absolute(SaveSlots.dir_for(n, SLOT_SCRATCH)),
			"and makes the directory, which Android does not have until something does")

	# Three genuinely separate farms: writing one must not disturb another.
	SimRng.reseed(91)
	var world := SimWorld.new()
	world.generate()
	GameState.reset()
	GameState.day = 4
	GameState.gold = 40
	SaveGame.save_to(SaveSlots.save_path(1, SLOT_SCRATCH), world, GameState)
	var slot1_bytes := _read_text(SaveSlots.save_path(1, SLOT_SCRATCH))

	GameState.reset()
	GameState.day = 31
	GameState.gold = 900
	GameState.total_shipped = 22
	GameState.crows_scared = 6
	SaveGame.save_to(SaveSlots.save_path(2, SLOT_SCRATCH), world, GameState)

	_assert(_read_text(SaveSlots.save_path(1, SLOT_SCRATCH)) == slot1_bytes,
		"playing the second farm leaves the first one byte-identical")
	_assert(not SaveSlots.has_farm(3, SLOT_SCRATCH),
		"and the third is still empty, because nobody has started it")
	var sum1 := SaveGame.summarize(SaveGame.load_dict(SaveSlots.save_path(1, SLOT_SCRATCH)))
	var sum2 := SaveGame.summarize(SaveGame.load_dict(SaveSlots.save_path(2, SLOT_SCRATCH)))
	_assert(int(sum1.get("day", 0)) == 4 and int(sum2.get("day", 0)) == 31,
		"each card would show its own farm's day (4 and 31)")
	_assert(int(sum1.get("gold", 0)) == 40 and int(sum2.get("gold", 0)) == 900,
		"and its own purse (40g and 900g)")

	# A farm written into a slot comes back out of it unchanged — the round trip
	# the title screen's Continue depends on, done through a slot's own path.
	GameState.reset()
	GameState.day = 31
	GameState.gold = 900
	GameState.total_shipped = 22
	GameState.crows_scared = 6
	var live := JSON.stringify(SaveGame.capture(world, GameState))
	var reloaded := SaveGame.load_dict(SaveSlots.save_path(2, SLOT_SCRATCH))
	var world2 := SimWorld.new()
	GameState.reset()
	_assert(SaveGame.restore(reloaded, world2, GameState), "a farm reloads out of its slot")
	_assert(JSON.stringify(SaveGame.capture(world2, GameState)) == live,
		"and is value-identical to the farm that was saved into it")

	GameState.save_path = held[0]
	GameState.replay_path = held[1]
	GameState.trace_path = held[2]
	GameState.slot = held[3]
	_wipe_dir(SLOT_SCRATCH)


func test_save_slot_migration() -> void:
	print("\n--- Save slots: a single-slot farm moves into slot 1, once (S-14) ---")
	_wipe_dir(SLOT_SCRATCH)

	# Nothing to move: the ordinary case on every run after the first.
	var quiet := SaveSlots.migrate_legacy(SLOT_SCRATCH)
	_assert(quiet["moved"].is_empty() and quiet["kept"].is_empty() and quiet["failed"].is_empty(),
		"a fresh install has nothing to move and says so")

	# What a build from before slots leaves in user://: the farm, its action log
	# and its trace, sitting in the root.
	_write_text(SLOT_SCRATCH + "autosave.json", '{"version":3,"state":{"day":17}}')
	_write_text(SLOT_SCRATCH + "session_replay.json", '{"version":2,"entries":[]}')
	_write_text(SLOT_SCRATCH + "session_trace.jsonl", "{\"kind\":\"tap\"}\n")

	var first := SaveSlots.migrate_legacy(SLOT_SCRATCH)
	_assert(first["moved"].size() == 3 and first["failed"].is_empty(),
		"the farm, the log and the trace all move (%d of 3)" % first["moved"].size())
	_assert(_read_text(SaveSlots.save_path(1, SLOT_SCRATCH)) == '{"version":3,"state":{"day":17}}',
		"the farm is in slot 1, byte for byte")
	_assert(_read_text(SaveSlots.replay_path(1, SLOT_SCRATCH)) == '{"version":2,"entries":[]}'
			and _read_text(SaveSlots.trace_path(1, SLOT_SCRATCH)) == "{\"kind\":\"tap\"}\n",
		"with the log and the trace it was recorded beside")
	_assert(not FileAccess.file_exists(SLOT_SCRATCH + "autosave.json"),
		"and the old location is empty, so nothing reads a stale farm from it")

	# Run it again, and again: it works off what is in the root, and there is
	# nothing there any more.
	var second := SaveSlots.migrate_legacy(SLOT_SCRATCH)
	var third := SaveSlots.migrate_legacy(SLOT_SCRATCH)
	_assert(second["moved"].is_empty() and third["moved"].is_empty(),
		"a second and third run move nothing — this happens once")
	_assert(_read_text(SaveSlots.save_path(1, SLOT_SCRATCH)) == '{"version":3,"state":{"day":17}}',
		"and slot 1 still holds the farm it was given")

	# The dangerous case: a farm in the root AND a farm already in slot 1. The
	# one in slot 1 has been played since the upgrade and is the live one; the
	# root file is older. Neither is destroyed.
	_write_text(SLOT_SCRATCH + "autosave.json", '{"version":3,"state":{"day":2}}')
	var guarded := SaveSlots.migrate_legacy(SLOT_SCRATCH)
	_assert(guarded["kept"].has("autosave.json") and guarded["moved"].is_empty(),
		"a farm already in slot 1 is not overwritten")
	_assert(_read_text(SaveSlots.save_path(1, SLOT_SCRATCH)) == '{"version":3,"state":{"day":17}}',
		"slot 1 still holds the farm that was there")
	_assert(_read_text(SLOT_SCRATCH + "autosave.json") == '{"version":3,"state":{"day":2}}',
		"and the older one is left where it is rather than deleted")

	# The parked copies move too: they exist to be recovered by hand, and a copy
	# left behind in the root is a rescue nobody would find.
	_wipe_dir(SLOT_SCRATCH)
	_write_text(SLOT_SCRATCH + "autosave.json", "farm")
	_write_text(SLOT_SCRATCH + "autosave.json.bak", "parked before a new farm")
	_write_text(SLOT_SCRATCH + "autosave.json.unloadable", "would not load")
	var rescues := SaveSlots.migrate_legacy(SLOT_SCRATCH)
	_assert(rescues["moved"].size() == 3,
		"the parked copies travel with the farm (%d of 3)" % rescues["moved"].size())
	_assert(_read_text(SaveSlots.dir_for(1, SLOT_SCRATCH).path_join("autosave.json.bak"))
			== "parked before a new farm",
		"and the .bak is still readable where a rescue would look for it")

	# Which farm was played last, for the title screen to open on.
	_assert(SaveSlots.last_played(SLOT_SCRATCH) == 1,
		"with nothing recorded, the first farm is the one that opens")
	SaveSlots.remember(3, SLOT_SCRATCH)
	_assert(SaveSlots.last_played(SLOT_SCRATCH) == 3, "and the last farm played is remembered")
	_write_text(SaveSlots.last_played_path(SLOT_SCRATCH), "not json at all")
	_assert(SaveSlots.last_played(SLOT_SCRATCH) == 1,
		"a preference file we cannot read falls back to the first farm rather than to none")

	_wipe_dir(SLOT_SCRATCH)


func test_replay_from_save() -> void:
	print("\n--- Replay-from-save (continue session) Tests ---")

	# Session 1: fresh farm, some work, then capture the "autosave"
	GameState.reset()
	SimRng.reseed(77)
	var world := SimWorld.new()
	world.generate()
	world.apply_action({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "plant", "target": Vector2i(5, 2), "seed_type": "wheat", "actor": "player" }, GameState)
	world.apply_action({ "verb": "water", "target": Vector2i(5, 2), "actor": "player" }, GameState)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	var autosave = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))

	# Session 2: continue from the autosave, do more work, record it
	var world2 := SimWorld.new()
	GameState.reset()
	_assert(SaveGame.restore(autosave, world2, GameState), "continue session restores autosave")
	var rlog := ReplayLog.new()
	rlog.start_from_save(autosave)
	var actions := [
		{ "verb": "water", "target": Vector2i(5, 2), "actor": "player" },
		{ "verb": "sleep", "actor": "world", "weather": "sunny" },
		{ "verb": "water", "target": Vector2i(5, 2), "actor": "player" },
		{ "verb": "sleep", "actor": "world", "weather": "rainy" },
		{ "verb": "harvest", "target": Vector2i(5, 2), "actor": "player" },
		{ "verb": "sell", "actor": "player" },
	]
	for a in actions:
		_replay_do(world2, rlog, a)
	# Five in the pouch to start, one sown, one cut back in — and the bin takes
	# the two that stand above the keep line (S-18/S-19/S-20).
	_assert(GameState.gold == 0 and int(GameState.bin_reserve.wheat) == 7,
		"continued session places its wheat in reserve before any sale")
	var live_snap := _replay_snapshot(world2)

	# Replay the continued session from the log's embedded base save
	var rlog2 := ReplayLog.from_json(rlog.to_json())
	var world3 := SimWorld.new()
	rlog2.apply_to(world3, GameState)
	_assert(_replay_snapshot(world3) == live_snap, "continued session replays to identical end state")
	_assert(GameState._milestones_earned.has("first_harvest"), "replayed actions earn milestones (sim truth)")

func test_replay_flush() -> void:
	print("\n--- ReplayLog append-only flush Tests ---")

	var path := "user://test_flush_replay.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var rlog := ReplayLog.new()
	rlog.start(123)
	rlog.record({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" }, { "ok": true })
	rlog.record({ "verb": "sleep", "actor": "world" }, { "ok": true, "weather": "sunny" })
	_assert(rlog.flush_to(path), "first flush writes file")

	rlog.record({ "verb": "water", "target": Vector2i(5, 2), "actor": "player" }, { "ok": true })
	rlog.record({ "verb": "sleep", "actor": "world" }, { "ok": true, "weather": "rainy" })
	_assert(rlog.flush_to(path), "second flush appends")
	_assert(rlog.flush_to(path), "no-op flush with nothing new succeeds")

	var loaded := ReplayLog.load_from(path)
	_assert(loaded != null and loaded.entries.size() == 4, "flushed file loads all 4 entries")
	_assert(loaded.gen_seed == 123, "flushed file keeps header gen_seed")
	# JSON round-trips turn ints into floats, so byte-equality with the
	# in-memory log is wrong by design; assert stability + verb sequence.
	_assert(ReplayLog.from_json(loaded.to_json()).to_json() == loaded.to_json(),
		"loaded log re-serializes stably")
	var verbs: Array = []
	for e in loaded.entries:
		verbs.append(e.get("verb", ""))
	_assert(verbs == ["till", "sleep", "water", "sleep"], "loaded entries keep order and verbs")
	DirAccess.remove_absolute(path)


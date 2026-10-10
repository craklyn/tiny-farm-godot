# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

func test_brains() -> void:
	print("\n--- One brain interface, and the three retrofits (M2.5 WI-3) Tests ---")

	# --- the interface (plan §4: the neighbour's pattern made law) -------------
	for id in SpeciesDefs.ids():
		_assert_quiet(Brains.has(SpeciesDefs.brain_of(id)),
			"%s's brain id resolves to a brain" % id)
		_assert_quiet(Brains.of_species(id) is Brain, "%s's brain is a Brain" % id)
	_flush_quiet("every species row's brain id binds to a real implementation (WI-2's handoff)")
	_assert(Brains.of_id("cold_open") is ColdOpenBrain
			and Brains.of_id("chicken_wander") is ChickenBrain
			and Brains.of_id("crow_visit") is CrowBrain,
		"and the three retrofitted brains are the three this work item wrote")
	_assert(Brains.of_id("no_such_brain") is Brain,
		"an unknown brain id is a brain that decides nothing, not a crash")

	# Two of the four are not on the tick clock, and both for pacing reasons the
	# brain files spell out: the player is a person, and the cold open is a scene
	# presentation paces (rule 7 keeps cameras and viewports out of layer 2).
	_assert(not Brains.of_id("player_input").on_clock(), "the player is not stepped by the sim")
	_assert(not Brains.of_id("cold_open").on_clock(), "nor is the cold open — main.gd paces the scene")
	_assert(Brains.of_id("chicken_wander").on_clock() and Brains.of_id("crow_visit").on_clock(),
		"the hen and the crow ride the clock")

	# The neighbour's brain IS `ColdOpen.next_action`, which is the whole claim of
	# finding F-1: the interface was generalised from her, so it has to fit her.
	var s := LiveSession.new(2026)
	_assert(Brains.of_id("cold_open").step(s.world, SimWorld.ACTOR_NEIGHBOUR, 0, s.gs)
			== ColdOpen.next_action(s.world, s.gs),
		"the cold-open brain returns exactly what her pure decider returns")

	# --- the hen: F-2 and F-4 die ---------------------------------------------
	# Her wander used to be a presentation FSM drawing from the shared SimRng
	# stream on frame time. It is a tick-stepped sim process now: she moves one
	# tile at a time, only onto walkable ground, and only when the clock says so.
	var hen_start: Vector2i = s.world.actor_pos(SimWorld.ACTOR_CHICKEN)
	_assert(s.world.clock.tick == 0, "a fresh world has not begun")
	s.tick(1)
	_assert(s.world.actor_pos(SimWorld.ACTOR_CHICKEN) == hen_start,
		"and one tick in she has not teleported anywhere")
	var visited := { hen_start: true }
	var last := hen_start
	var wandered := false
	for _i in 600:
		s.tick(1)
		var at: Vector2i = s.world.actor_pos(SimWorld.ACTOR_CHICKEN)
		if at != last:
			wandered = true
			_assert_quiet(absi(at.x - last.x) + absi(at.y - last.y) == 1,
				"she stepped to an adjacent tile, not across the farm")
			_assert_quiet(s.world.is_walkable(at.x, at.y), "onto ground she could stand on")
			visited[at] = true
			last = at
	_flush_quiet("every step the hen took over a minute of sim time was one walkable tile")
	_assert(wandered, "she wanders on her own, with no node in sight (%d tiles)" % visited.size())
	_assert(s.world.actor(SimWorld.ACTOR_CHICKEN)["extra"].has("wake"),
		"and her scratch lives in the registry entry's `extra`, where WI-2 put it")

	# --- the egg is an Action, not a side effect of the day turn ---------------
	# The distinction is load-bearing. A coin flip taken inside advance_day() would
	# be taken twice — once live, once when a replay re-applies the sleep — which
	# is the exact desync this work item exists to end. So the day turn only marks
	# the morning; the brain acts on it and the Action is recorded.
	var eggs_before := _count_objects(s.world, "egg")
	s.world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, s.gs)
	_assert(_count_objects(s.world, "egg") == eggs_before,
		"a day turning lays no egg by itself")
	_assert(bool(s.world.actor(SimWorld.ACTOR_CHICKEN)["extra"].get("lay_due", false)),
		"it only tells the hen there is a morning")
	var laid := 0
	for _i in 40:
		for t in s.tick(1):
			if String(t["action"].get("verb", "")) == "lay_egg":
				laid += 1
	_assert(laid <= 1, "and she considers it exactly once (%d)" % laid)
	_assert(not bool(s.world.actor(SimWorld.ACTOR_CHICKEN)["extra"].get("lay_due", true)),
		"the morning is spent whichever way the coin came down")
	s.done()

	# Over many days the coin is a coin — neither a guarantee nor a drought.
	var days_with_egg := 0
	for seed_value in range(1, 41):
		var d := LiveSession.new(seed_value)
		d.world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, d.gs)
		for t in d.tick(30):
			if String(t["action"].get("verb", "")) == "lay_egg":
				days_with_egg += 1
		d.done()
	_assert(days_with_egg > 5 and days_with_egg < 35,
		"the morning egg is still a coin flip across 40 seeds (%d)" % days_with_egg)

	# --- the crow: its whole visit is sim truth now ----------------------------
	var c := _crow_ready_session(4242)
	_assert(not c.world.has_actor(SimWorld.ACTOR_CROW), "no crow before its appointment")
	var arrival: int = int(c.gs.crow_schedule[0])
	_work_until_actions(c, arrival)
	_assert(c.world.has_actor(SimWorld.ACTOR_CROW),
		"a crow arrives when the day's action clock reaches its scheduled arrival (T-20)")
	_assert(c.gs.crow_schedule.is_empty(), "and the arrival is spent")
	_assert(c.world.species_of(SimWorld.ACTOR_CROW) == SpeciesDefs.CROW,
		"it is a registered actor of the species the table describes")
	var visit: Dictionary = c.world.actor(SimWorld.ACTOR_CROW)["extra"].duplicate(true)
	_assert(String(visit.get("kind", "")) == "acorn",
		"and it went for an acorn, because any acorn beats any crop (T-15/Q-39)")
	var entry: Vector2i = c.world.actor_pos(SimWorld.ACTOR_CROW)
	_assert(entry.x < 0 or entry.y < 0 or entry.x >= SimWorld.MAP_WIDTH or entry.y >= SimWorld.MAP_HEIGHT,
		"it enters from off the map, at %s" % entry)

	# Finding F-4, dead: the eat lands at a *tick*, not when a sprite arrived.
	var acorns_before := c.world.count_acorns()
	var ate_at := -1
	for _i in 400:
		for t in c.tick(1):
			if String(t["action"].get("verb", "")).begins_with("eat_"):
				ate_at = c.world.clock.tick
	_assert(ate_at > 0, "the crow eats at a deterministic tick (%d)" % ate_at)
	_assert(c.world.count_acorns() == acorns_before - 1, "and takes exactly one acorn")
	_assert(not c.world.has_actor(SimWorld.ACTOR_CROW), "then leaves the map and the registry")
	var crow_planted := c.world.count_planted()
	c.tick(600)
	_assert(c.world.count_planted() == crow_planted,
		"and nothing else eats a crop for the rest of the day — one arrival, one visit")

	# The same visit, twice, from the same seed: identical timing and outcome.
	# The draws are `SimRng.stateless`, so this holds no matter what else has been
	# consuming the shared stream (which in a live session is the hen, constantly).
	var twin := _crow_ready_session(4242)
	_work_until_actions(twin, arrival)
	_assert(str(twin.world.actor(SimWorld.ACTOR_CROW)["extra"]) == str(visit),
		"same seed, same day, same arrival: the same bird on the same errand")
	twin.done()

	# One arrival is consumed whether the bird is fed **or shooed** (T-20). Shooing
	# it is a recorded Action through the one gateway, and it ends the visit.
	var shooed := _crow_ready_session(4242)
	_work_until_actions(shooed, arrival)
	var acorns_at_arrival := shooed.world.count_acorns()
	shooed.tick(20)
	_assert(shooed.world.has_actor(SimWorld.ACTOR_CROW), "the bird is still on its way in")
	shooed.act({ "verb": "crow_scared", "actor": SimWorld.ACTOR_CROW })
	_assert(String(shooed.world.actor(SimWorld.ACTOR_CROW)["extra"].get("state", "")) == "leaving",
		"a scare report turns it around inside the gateway")
	_assert(shooed.gs.crows_scared == 1, "and counts toward the Q-12 capability proof")
	shooed.tick(600)
	_assert(not shooed.world.has_actor(SimWorld.ACTOR_CROW), "it leaves")
	_assert(shooed.world.count_acorns() == acorns_at_arrival, "having eaten nothing")
	_assert(shooed.gs.crow_schedule.is_empty(),
		"and the day owes no replacement — shooing one is a win for the day (T-20)")
	shooed.done()

	# A scarecrow is sim truth, so the bird notices it without presentation's help.
	var scared := _crow_ready_session(4242)
	_work_until_actions(scared, arrival)
	var target := Vector2i(int(scared.world.actor(SimWorld.ACTOR_CROW)["extra"]["tgt_x"]),
		int(scared.world.actor(SimWorld.ACTOR_CROW)["extra"]["tgt_y"]))
	scared.world.set_object(target.x, target.y + 1, "scarecrow")
	var acorns_guarded := scared.world.count_acorns()
	scared.tick(600)
	_assert(not scared.world.has_actor(SimWorld.ACTOR_CROW), "a guarded crop sends the crow home")
	_assert(scared.world.count_acorns() == acorns_guarded, "with nothing eaten")
	scared.done()

	# T-2's mercy, retargeted by T-15: the first crow to go for a **crop** eats
	# nothing at all. It still flies in, still perches, and leaves empty-beaked.
	var mercy := _crow_ready_session(4242)
	# This is the crow's mercy test; a rare worm is a separate legitimate loss.
	mercy.gs.visitor_schedules[SpeciesDefs.WORM] = []
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if mercy.world.objects[ty][tx] == "acorn":
				mercy.world.set_object(tx, ty, "")
	_work_until_actions(mercy, arrival)
	_assert(mercy.world.has_actor(SimWorld.ACTOR_CROW), "with the acorns gone a crow still comes")
	_assert(String(mercy.world.actor(SimWorld.ACTOR_CROW)["extra"].get("kind", "")) == "crop",
		"and now it wants a crop")
	_assert(bool(mercy.world.actor(SimWorld.ACTOR_CROW)["extra"].get("harmless", false)),
		"the first crop-crow is the harmless one")
	var crops_before := mercy.world.count_planted()
	mercy.tick(600)
	_assert(not mercy.world.has_actor(SimWorld.ACTOR_CROW), "it perches, then goes")
	_assert(mercy.world.count_planted() == crops_before,
		"and the first crop-crow of a save costs the player nothing (T-2)")
	_assert(mercy.gs.crop_crows_seen == 1, "but it does spend the mercy")
	mercy.done()

	# The daily-loss bound the acorn tests state, now over the live path: a day
	# cannot cost more crops than it scheduled arrivals.
	var budget := _crow_ready_session(77)
	for ty2 in SimWorld.MAP_HEIGHT:
		for tx2 in SimWorld.MAP_WIDTH:
			if budget.world.objects[ty2][tx2] == "acorn":
				budget.world.set_object(tx2, ty2, "")
	budget.gs.crop_crows_seen = 1  # past the mercy, so every bird is a real one
	var planted_at_dawn := budget.world.count_planted()
	_work_until_actions(budget, 40)
	budget.tick(2000)
	_assert(planted_at_dawn - budget.world.count_planted() <= SimWorld.CROWS_PER_DAY,
		"a whole day of work loses at most CROWS_PER_DAY crops to birds")
	budget.done()

	# --- rule 8: cost is per decision, never per tick --------------------------
	# A day of sim time with nobody but a dozing hen in it must be cheap, because
	# fast-forward is the thing this whole clock exists to keep honest.
	var idle := LiveSession.new(31337)
	var t0 := Time.get_ticks_msec()
	idle.world.advance_ticks(60 * SimClock.RATE, idle.gs)  # a minute of sim time
	var elapsed := Time.get_ticks_msec() - t0
	_assert(elapsed < 250, "a minute of sim time with one wandering actor costs %d ms" % elapsed)
	_assert(idle.world.clock.pending() == 1,
		"and exactly one event is pending — one think per actor on the clock, never a queue of them")
	idle.done()

	# --- determinism: the property everything else rests on --------------------
	var trace_a := _tick_trace(909)
	_assert(trace_a == _tick_trace(909), "same seed + same inputs + same ticks = the same session")
	_assert(trace_a != _tick_trace(910), "and a different seed is a different one")

	# --- a live tick-stepped session still replays -----------------------------
	# The seam this work item deliberately opens is in `capture_canonical`, not
	# here: the Action stream is compared in full, and it is the stream that
	# crosses the determinism boundary in a v1 log. Brains do not run during
	# playback (a v1 entry has no tick to run them against), so what they did live
	# has to be in the log — which is exactly what `world/farm.gd` records.
	#
	# From the seed first: the cold open recorded action by action, then days
	# turning with the hen thinking between them.
	var seeded := LiveSession.new(1717)
	for _i in ColdOpen.MAX_STEPS:
		var next := ColdOpen.next_action(seeded.world, seeded.gs)
		if next.is_empty():
			break
		seeded.act(next)
	for _i in 4:
		seeded.act({ "verb": "sleep", "actor": "world" })
		seeded.tick(300)
	var replayed := SimWorld.new()
	var gs_replayed = load("res://systems/game_state.gd").new()
	seeded.log.apply_to(replayed, gs_replayed)
	_assert(SaveGame.capture_canonical(seeded.world, seeded.gs)
			== SaveGame.capture_canonical(replayed, gs_replayed),
		"a tick-stepped session replays from its seed to the same world (%d entries)"
			% seeded.log.entries.size())
	_assert(_count_objects(seeded.world, "egg") > 0,
		"and there were eggs in it — the hen's Actions really are in the log")
	gs_replayed.free()
	seeded.done()

	# And from a save, which is the other way a session begins and the pairing
	# `tools/verify_replay.gd` checks. This is the one that carries a crow.
	var played := _crow_ready_session(1717)
	played.rebase()
	_work_until_actions(played, 30)
	played.tick(900)
	_work_until_actions(played, 40)
	played.tick(900)
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(played.gs.crows_seen > 0, "a crow visited during the recorded session")
	var played_report := SaveGame.replay_report(played.log, snapshot)
	_assert(played_report["matched"],
		"and the session reproduces its own autosave, which is what the robot asserts %s"
			% played_report["divergence"])

	# --- the seam, closed, stated as a test -----------------------------------
	# WI-3 took the tick and every actor's pos/facing/extra out of
	# `capture_canonical` because a v1 replay had no way to recompute them. v2
	# stamps the ticks and `apply_to` lives out the session's sim time, so they
	# are back in and they **bite**: a hen standing somewhere else is a failed
	# replay now. The player is the one residue, and she is asserted below.
	var seam := SimWorld.new()
	var gs_seam = load("res://systems/game_state.gd").new()
	SimRng.reseed(5150)
	seam.generate()
	var seam_before := SaveGame.capture_canonical(seam, gs_seam)
	seam.set_actor_pos(SimWorld.ACTOR_CHICKEN, Vector2i(9, 9), "left")
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"a moved actor fails the replay comparison (the WI-3 seam, closed by WI-5)")
	seam.actor(SimWorld.ACTOR_CHICKEN)["extra"]["wake"] = 12345
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so does brain scratch that drifted")
	SimRng.reseed(5150)
	seam.generate()
	seam.clock.advance_to(999)
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so does a clock that turned further than the recording did")
	SimRng.reseed(5150)
	seam.generate()
	# ...and the last residue is gone (M2.5 WI-6). The player was excluded from
	# this comparison for as long as nothing wrote her tile into the registry; her
	# crossings write it now and are recorded as free-walk entries a replay applies
	# back, so the comparison is total and a farmer who ends the session on a
	# different tile is a failed replay like anybody else.
	seam.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(11, 11), "up")
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so does the player, whose position is in the comparison now (WI-6)")
	_assert(JSON.stringify(SaveGame.capture(seam, gs_seam)).contains("\"x\":11"),
		"but the *save* still stores where she is — a save is a snapshot")
	SimRng.reseed(5150)
	seam.generate()
	seam.set_actor_energy(SimWorld.ACTOR_CHICKEN, 3)
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"energy is still compared: the seam is about motion, not about state in general")
	seam.set_actor_energy(SimWorld.ACTOR_CHICKEN, SimWorld.ACTOR_MAX_ENERGY)
	seam.despawn_actor(SimWorld.ACTOR_CHICKEN)
	_assert(SaveGame.capture_canonical(seam, gs_seam) != seam_before,
		"and so is existence: an actor who should be on the farm and is not still fails")

	# A visit is not saved. The crow's row says `persistent: false`, and that is
	# what keeps a bird mid-flight out of a snapshot of a farm. **Revisited in
	# WI-5 and deliberately kept**: the argument (a save is a snapshot of a farm;
	# a bird halfway across the sky is not part of one) did not change, and the
	# dual-record net now checks the crow harder than a position ever could — every
	# Action of its visit is recomputed and compared, tick for tick.
	SimRng.reseed(5150)
	seam.generate()
	seam.spawn_actor(SimWorld.ACTOR_CROW, SpeciesDefs.CROW, Vector2i(4, 4))
	_assert(seam.has_actor(SimWorld.ACTOR_CROW), "a crow can be in the registry")
	_assert(not SaveGame.capture(seam, gs_seam)["world"]["actors"].has(SimWorld.ACTOR_CROW),
		"but never in a save — a visit is not a resident")
	_assert(SaveGame.capture_canonical(seam, gs_seam) == seam_before,
		"so a bird in flight cannot fail a replay comparison either")
	gs_seam.free()
	played.done()

	# --- a reloaded farm is alive ---------------------------------------------
	# A restored registry never went through spawn_actor, so nothing would be on
	# the clock without SaveGame's explicit call. A hen who stands perfectly still
	# after a reload is the failure this catches.
	var saved := LiveSession.new(6161)
	var save_dict = JSON.parse_string(JSON.stringify(SaveGame.capture(saved.world, saved.gs)))
	var loaded := SimWorld.new()
	var gs_loaded = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(save_dict, loaded, gs_loaded), "the save restores")
	_assert(loaded.clock.pending() > 0, "and its actors are on the clock again")
	var loaded_start: Vector2i = loaded.actor_pos(SimWorld.ACTOR_CHICKEN)
	loaded.advance_ticks(600, gs_loaded)
	_assert(loaded.actor_pos(SimWorld.ACTOR_CHICKEN) != loaded_start,
		"so the hen carries on pottering after a reload")
	gs_loaded.free()
	saved.done()

	# --- the carve-out, as a grep the suite runs itself ------------------------
	# Checklist §8.B: zero `SimRng` references under `entities/`. Presentation may
	# not hold the sim's dice — that is finding F-2 — and cosmetics that want a
	# die roll have `CosmeticRng`, whose answers are allowed to differ between two
	# runs of the same session.
	var sources := DirAccess.open("res://entities")
	_assert(sources != null, "there is an entities/ directory to check")
	if sources != null:
		var checked := 0
		for name in sources.get_files():
			if not name.ends_with(".gd"):
				continue
			checked += 1
			var src := FileAccess.get_file_as_string("res://entities/%s" % name)
			_assert_quiet(not src.contains("SimRng"), "entities/%s draws from SimRng" % name)
		_assert_quiet(checked >= 3, "there were entity scripts to check (%d)" % checked)
		_flush_quiet("no renderer under entities/ touches SimRng (the WI-3 carve-out, §8.B)")
	_assert(CosmeticRng.randf() >= 0.0 and CosmeticRng.randf() <= 1.0,
		"and the cosmetic source they use instead answers without touching the sim stream")


func test_pathfinder_identity() -> void:
	print("\n--- The faster pathfinder answers identically (Q-67) ---")

	# The neighbour order both searches run on is `DIRS`, split into two integer
	# lanes so the loop adds ints rather than building Vector2i temporaries. It is
	# the tie-break, so the two are asserted equal here rather than trusted to a
	# comment: they would drift in silence, and the silence would be a desync.
	var lanes: Array[Vector2i] = []
	for d in 4:
		lanes.append(Vector2i(Movement._DX[d], Movement._DY[d]))
	_assert(str(lanes) == str(Movement.DIRS),
		"the search's neighbour order is DIRS itself: %s" % str(lanes))

	var worlds := _pathfinder_worlds()

	# --- the terrain reads the searches rest on -------------------------------
	# `is_walkable` stopped composing itself out of `get_tile` and `get_object`
	# and reads both inline instead. It is the hottest read in the sim and every
	# route in the game is built out of its answers, so it is swept whole.
	for entry in worlds:
		var w: SimWorld = entry[1]
		for ty in SimWorld.MAP_HEIGHT:
			for tx in SimWorld.MAP_WIDTH:
				_assert_quiet(w.get_object(tx, ty) == _ref_object(w, tx, ty),
					"%s: object at %d,%d" % [entry[0], tx, ty])
				_assert_quiet(w.is_walkable(tx, ty) == _ref_walkable(w, tx, ty),
					"%s: walkable at %d,%d" % [entry[0], tx, ty])
	_flush_quiet("every tile of every test world reads the same as it always did")

	# --- the sweep -------------------------------------------------------------
	var modes := [SpeciesDefs.GROUND, SpeciesDefs.HOP, SpeciesDefs.BURROW, SpeciesDefs.FLY]
	var pairs := 0
	var routed := 0
	var refused := 0
	var longest := 0
	var mismatch := ""
	for entry in worlds:
		var w: SimWorld = entry[1]
		for mode in modes:
			# Strides that share no factor with the map's dimensions, so the starts
			# land on every phase of the terrain rather than on one lane of it.
			for sy in range(0, SimWorld.MAP_HEIGHT, 3):
				for sx in range(0, SimWorld.MAP_WIDTH, 5):
					var s := Vector2i(sx, sy)
					for off in _SWEEP_OFFSETS:
						var g: Vector2i = s + off
						var got := Movement.path(w, mode, s, g)
						var want := _ref_path(w, mode, s, g)
						pairs += 1
						if got.is_empty():
							refused += 1
						else:
							routed += 1
							longest = maxi(longest, got.size())
						if mismatch == "" and str(got) != str(want):
							mismatch = "%s, %s, %s -> %s: %s, was %s" % [entry[0], mode, s, g, got, want]
	_assert(mismatch == "",
		"%d (start, goal, mode) pairs route tile-for-tile as they always did%s"
			% [pairs, "" if mismatch == "" else " — first difference: " + mismatch])
	# A sweep that found nothing proves nothing: it has to have routed, to have
	# refused, and to have gone a long way round at least once.
	_assert(routed > 5000 and refused > 2000 and longest >= 20,
		"and the sweep is a real one (%d routed, %d refused, longest %d tiles)"
			% [routed, refused, longest])

	# --- the flood fill, whose *order* worldgen draws the hen's tile out of ----
	var fills := 0
	var filled := 0
	var fill_mismatch := ""
	for entry in worlds:
		var w: SimWorld = entry[1]
		for mode in [SpeciesDefs.GROUND, SpeciesDefs.HOP, SpeciesDefs.BURROW]:
			for sy in range(0, SimWorld.MAP_HEIGHT, 5):
				for sx in range(0, SimWorld.MAP_WIDTH, 5):
					var s := Vector2i(sx, sy)
					var got := Movement.reachable(w, mode, s)
					var want := _ref_reachable(w, mode, s)
					fills += 1
					filled = maxi(filled, got.size())
					if fill_mismatch == "" and str(got) != str(want):
						fill_mismatch = "%s, %s, from %s (%d vs %d tiles)" % [
							entry[0], mode, s, got.size(), want.size()]
	_assert(fill_mismatch == "",
		"%d flood fills come back in the identical order%s (largest %d tiles)"
			% [fills, "" if fill_mismatch == "" else " — first difference: " + fill_mismatch, filled])

	# --- the answers that are not routes --------------------------------------
	var field: SimWorld = worlds[2][1]
	var sealed: SimWorld = worlds[3][1]
	var arena: SimWorld = worlds[1][1]
	var inside := Vector2i(23, 9)
	var outside := Vector2i(5, 3)
	_assert(Movement.path(field, SpeciesDefs.GROUND, outside, outside).is_empty()
			and _ref_path(field, SpeciesDefs.GROUND, outside, outside).is_empty(),
		"going nowhere is no route, not a route of length zero")
	_assert(str(Movement.path(field, SpeciesDefs.GROUND, Vector2i(-4, 5), outside))
				== str(_ref_path(field, SpeciesDefs.GROUND, Vector2i(-4, 5), outside))
			and str(Movement.path(field, SpeciesDefs.GROUND, outside, Vector2i(40, 5)))
				== str(_ref_path(field, SpeciesDefs.GROUND, outside, Vector2i(40, 5))),
		"and a start or a goal off the map is refused the same way at both ends")
	_assert(Movement.path(sealed, SpeciesDefs.GROUND, outside, inside).is_empty(),
		"a walker has no way into a room with no door")
	_assert(not Movement.path(sealed, SpeciesDefs.HOP, outside, inside).is_empty(),
		"a hopper does, over the hedge — the same tile, a different capability")
	_assert(str(Movement.path(sealed, SpeciesDefs.HOP, outside, inside))
			== str(_ref_path(sealed, SpeciesDefs.HOP, outside, inside)),
		"and it hops it by the identical route")
	_assert(Movement.path(arena, SpeciesDefs.BURROW, Vector2i(5, 5), Vector2i(14, 5)).is_empty(),
		"a burrower still cannot surface inside a rock")

	# The tie-break itself, stated as a fact rather than inferred from a sweep: on
	# open ground a 3-by-2 goal has ten shortest routes, and which one comes back
	# is decided by DIRS order and by insertion order among equal f-scores. Both
	# implementations pick this one, and a replay of any recorded session depends
	# on it staying this one.
	var diamond := Movement.path(field, SpeciesDefs.GROUND, Vector2i(4, 4), Vector2i(7, 6))
	_assert(str(diamond) == str(_ref_path(field, SpeciesDefs.GROUND, Vector2i(4, 4), Vector2i(7, 6)))
			and str(diamond) == "[(4, 5), (4, 6), (5, 6), (6, 6), (7, 6)]",
		"an equal-cost diamond breaks the same way it always has: %s" % str(diamond))


func test_movement() -> void:
	print("\n--- The movement engine: one mode per capability (M2.5 WI-4) Tests ---")

	# --- the capability table drives everything -------------------------------
	# The engine reads the species row WI-2 wrote, so the crow flying over a fence
	# the hen walks around is *data* (finding F-6), not two nodes' worth of code.
	_assert(Movement.mode_of(SpeciesDefs.CROW) == SpeciesDefs.FLY
			and Movement.mode_of(SpeciesDefs.CHICKEN) == SpeciesDefs.GROUND,
		"the engine takes each actor's mode off its species row")
	for id in SpeciesDefs.ids():
		_assert_quiet(Movement.ticks_per_tile(id) >= 1, "%s converts its speed to ticks/tile" % id)
		_assert_quiet(Movement.body_len_of(id) >= 1, "%s occupies at least one tile" % id)
	_flush_quiet("every shipping species is a mover the engine can already move")
	_assert(Brain.ticks_per_tile(SpeciesDefs.CHICKEN) == Movement.ticks_per_tile(SpeciesDefs.CHICKEN),
		"and a brain's speed conversion *is* the engine's, not a second copy of it")

	var w := _movement_arena()
	var west := Vector2i(5, 5)
	var east := Vector2i(18, 5)
	var barrier := Vector2i(10, 5)
	var rock := Vector2i(14, 5)
	var straight := absi(east.x - west.x) + absi(east.y - west.y)
	_assert(w.get_tile(barrier.x, barrier.y).get("state", "") == WorldLayout.FENCE
			and w.get_tile(rock.x, rock.y).get("state", "") == "obstacle_rock",
		"the arena has a fence at %s and a rock wall at %s" % [barrier, rock])

	# --- ground: A* over sim truth --------------------------------------------
	var walk := Movement.path(w, SpeciesDefs.GROUND, west, east)
	_assert(not walk.is_empty(), "a walker finds a way round (%d tiles)" % walk.size())
	_assert(walk.size() > straight, "the long way, because both walls are in her way (%d > %d)"
		% [walk.size(), straight])
	_assert(walk[walk.size() - 1] == east, "and it ends where she was going")
	var crossed_a_wall := false
	var stepwise := true
	var prev := west
	for t in walk:
		if not w.is_walkable(t.x, t.y):
			crossed_a_wall = true
		if absi(t.x - prev.x) + absi(t.y - prev.y) != 1:
			stepwise = false
		prev = t
	_assert(not crossed_a_wall, "every tile of a walker's route is ground she can stand on")
	_assert(stepwise, "and every step of it is one tile")
	_assert(Movement.path(w, SpeciesDefs.GROUND, west, barrier).is_empty(),
		"a walker cannot even be sent *to* a fence tile")

	# The ground-mode names the rest of the sim calls are this engine now, not a
	# second implementation that could drift from it (WI-3 wrote them as the
	# deliberate special case and said so).
	_assert(str(w.path_between(west, east)) == str(walk),
		"SimWorld.path_between is the engine's ground mode")
	_assert(str(w.reachable_from(west)) == str(Movement.reachable(w, SpeciesDefs.GROUND, west)),
		"and so is reachable_from — whose *order* worldgen draws the hen's tile out of")

	# --- fly: the criterion, in one scenario ----------------------------------
	# The flyer crosses the fence the walker paths around, and it is the crow's
	# own shipping row doing it — the same code path, not a test-only mode.
	w.spawn_actor("flyer", SpeciesDefs.CROW, west,
		{ "fx": Movement.tile_centre(west).x, "fy": Movement.tile_centre(west).y })
	var over: Dictionary = {}
	var arrived_at := -1
	for i in 200:
		if Movement.fly_toward(w, "flyer", Movement.tile_centre(east), SpeciesDefs.speed_of(SpeciesDefs.CROW)):
			arrived_at = i
			break
		over[w.actor_pos("flyer")] = true
	_assert(arrived_at > 0, "the flyer arrives, tick-stepped, in %d steps" % arrived_at)
	_assert(w.actor_pos("flyer") == east, "on the tile it was aiming at")
	_assert(over.has(barrier) and over.has(rock),
		"having gone straight over the fence and the rocks (%d tiles crossed)" % over.size())
	_assert(over.size() <= straight + 1, "in a straight line, not round anything")
	# The pairing WI-3 asked to keep: continuous position in `extra`, registry
	# tile as its rounded shadow, so a renderer can draw smoothly from 10 Hz truth.
	_assert(Movement.float_pos(w, "flyer").is_equal_approx(Movement.tile_centre(east)),
		"its continuous position is where it really is")
	_assert(Vector2i(floori(Movement.float_pos(w, "flyer").x), floori(Movement.float_pos(w, "flyer").y))
			== w.actor_pos("flyer"),
		"and the registry tile is that position, rounded")

	# A flyer's *continuous* flight leaves the map on purpose (a crow enters from
	# two tiles off it), but a tile route is a route over the map: nothing in the
	# engine may search open sky.
	var sky := Movement.path(w, SpeciesDefs.FLY, west, east)
	_assert(sky.size() == straight, "a flyer asked for a tile route gets the straight one")
	for t in sky:
		_assert_quiet(Movement.in_bounds(w, t), "route tile %s is on the map" % t)
	_flush_quiet("and every tile of it is on the map, in every mode")

	# --- burrow: under the grid, up at the target (WI-8d's mole) --------------
	Movement.define_test_species("test_mole", { "mode": SpeciesDefs.BURROW }, 1.0)
	_assert(Movement.passable(w, SpeciesDefs.BURROW, rock)
			and Movement.passable(w, SpeciesDefs.BURROW, barrier),
		"a burrower ignores surface obstacles — rocks and fences alike")
	_assert(not Movement.passable(w, SpeciesDefs.BURROW, Vector2i(0, 0)),
		"but the map border is the edge of the world, not a surface obstacle")
	var dig := Movement.path(w, SpeciesDefs.BURROW, west, east)
	_assert(dig.size() == straight, "so its route is the straight one (%d tiles)" % dig.size())
	_assert(barrier in dig and rock in dig, "straight through both walls")
	_assert(Movement.path(w, SpeciesDefs.BURROW, west, rock).is_empty(),
		"and it cannot surface inside a rock — a journey ends where it can stand")
	w.spawn_actor("mole", "test_mole", west)
	Movement.plan(w, "mole", east)
	_assert(Movement.is_under(w, "mole"), "it goes under to travel")
	var surfaced_at := -1
	for i in 40:
		if Movement.step(w, "mole", i) == Movement.ARRIVED:
			surfaced_at = i
			break
	_assert(w.actor_pos("mole") == east, "arrives at its target")
	_assert(surfaced_at == straight, "in one tick per tile at 1 tile/tick (%d)" % surfaced_at)
	_assert(not Movement.is_under(w, "mole"), "and surfaces there (plan §4)")

	# --- hop: ground plus *exactly* the barrier class (WI-8f's kangaroo) ------
	Movement.define_test_species("test_roo", { "mode": SpeciesDefs.HOP }, 1.0)
	var hop_over := Movement.path(w, SpeciesDefs.HOP, west, Vector2i(12, 5))
	_assert(hop_over.size() == 7 and barrier in hop_over,
		"a hopper crosses the fence a walker paths around (%d tiles)" % hop_over.size())
	var hop_round := Movement.path(w, SpeciesDefs.HOP, west, east)
	_assert(not hop_round.is_empty() and hop_round.size() > straight,
		"but the rock wall still stops it (%d > %d)" % [hop_round.size(), straight])
	var hopped_a_rock := false
	for t in hop_round:
		if String(w.get_tile(t.x, t.y).get("state", "")).begins_with("obstacle"):
			hopped_a_rock = true
	_assert(not hopped_a_rock, "it hops fences, not obstacles")
	_assert(not Movement.can_stop(w, SpeciesDefs.HOP, barrier),
		"and it clears a fence rather than perching on one")

	# "Exactly barrier-class" measured against every tile of a **real** farm, and
	# against the tile states themselves rather than against the engine's own
	# helper — so no other state can quietly join the class.
	var farm := SimWorld.new()
	SimRng.reseed(99)
	farm.generate()
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			var t := Vector2i(tx, ty)
			var st := String(farm.get_tile(tx, ty).get("state", ""))
			# The whole class, written out by hand — the walls and windows T-37
			# added included, which a generated farm only started containing when
			# the home became page 1 of it (2026-09-06). VOID is deliberately not
			# in the list: darkness is not a boundary, it is the edge of the map
			# drawn inside the grid, and a hopper does not clear it.
			var is_barrier_state := st == WorldLayout.FENCE or st == WorldLayout.HEDGE \
				or st == WorldLayout.GATE_CLOSED or st == WorldLayout.WALL \
				or st == WorldLayout.WINDOW
			_assert_quiet(Movement.passable(farm, SpeciesDefs.HOP, t)
					== (farm.is_walkable(tx, ty) or is_barrier_state),
				"hop passability at %s (%s)" % [t, st])
			_assert_quiet(Movement.passable(farm, SpeciesDefs.GROUND, t) == farm.is_walkable(tx, ty),
				"ground passability at %s (%s)" % [t, st])
	_flush_quiet("a hopper crosses exactly the barrier class, over every tile of a generated farm")

	# --- body_len > 1: trailing segments occupy tiles (WI-8e's worm) ----------
	Movement.define_test_species("test_worm", { "mode": SpeciesDefs.GROUND, "body_len": 3 }, 1.0)
	w.spawn_actor("worm", "test_worm", Vector2i(3, 3))
	_assert(Movement.body_len(w, "worm") == 3, "a three-segment species is three segments long")
	_assert(Movement.occupied_tiles(w, "worm").size() == 1,
		"a worm that has never moved is one tile of worm")
	Movement.plan(w, "worm", Vector2i(8, 3))
	for i in 3:
		Movement.step(w, "worm", i)
	var body := Movement.occupied_tiles(w, "worm")
	_assert(body.size() == 3, "after three steps its body occupies three tiles")
	_assert(str(body) == str([Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)]),
		"head first, and trailing behind it: %s" % str(body))
	_assert(w.actor_pos("worm") == body[0], "the registry tile is the head")
	# The snake rule: it is blocked by its own body, and by nothing else here.
	_assert(not Movement.can_enter(w, "worm", Vector2i(5, 3)),
		"it cannot double back into its own neck (the snake rule)")
	_assert(Movement.can_enter(w, "worm", Vector2i(7, 3)) and Movement.can_enter(w, "worm", Vector2i(6, 2)),
		"but every other neighbour is open ground")
	Movement.plan(w, "worm", Vector2i(5, 3))
	_assert(Movement.step(w, "worm", 10) == Movement.BLOCKED,
		"and a route into itself is blocked at the step, not at the plan")
	_assert(w.actor_pos("worm") == Vector2i(6, 3), "so it has not moved")
	# Per-actor override: WI-8e grows the worm by writing one integer, with no
	# species row per length.
	w.actor("worm")["extra"]["body_len"] = 5
	_assert(Movement.body_len(w, "worm") == 5, "a worm grows by overriding its own length")

	# --- tile_exclusive: never two of a kind on one tile ----------------------
	Movement.define_test_species("test_ant", { "mode": SpeciesDefs.GROUND, "tile_exclusive": true }, 1.0)
	Movement.define_test_species("test_hen", { "mode": SpeciesDefs.GROUND }, 1.0)
	w.spawn_actor("ant_a", "test_ant", Vector2i(3, 10))
	w.spawn_actor("ant_b", "test_ant", Vector2i(5, 10))
	Movement.plan(w, "ant_a", Vector2i(7, 10))
	var shared := false
	var ant_blocked := false
	for i in 20:
		if Movement.step(w, "ant_a", i) == Movement.BLOCKED:
			ant_blocked = true
		if w.actor_pos("ant_a") == w.actor_pos("ant_b"):
			shared = true
	_assert(w.actor_pos("ant_a") == Vector2i(4, 10), "an exclusive actor stops short of its own kind")
	_assert(ant_blocked and not shared, "two exclusive actors never share a tile")
	w.despawn_actor("ant_b")
	_assert(Movement.step(w, "ant_a", 30) == Movement.MOVED and w.actor_pos("ant_a") == Vector2i(5, 10),
		"and it carries on the moment the tile is free")
	# The flag is what does the work: without it, sharing is fine and always was —
	# the hen and the player have stood on the same tile since M1.
	w.spawn_actor("hen_a", "test_hen", Vector2i(3, 12))
	w.spawn_actor("hen_b", "test_hen", Vector2i(4, 12))
	Movement.plan(w, "hen_a", Vector2i(5, 12))
	Movement.step(w, "hen_a", 40)
	_assert(w.actor_pos("hen_a") == w.actor_pos("hen_b"),
		"a species that is not tile_exclusive shares happily")

	# --- cost is per step, not per tick (plan §1 rule 8) ----------------------
	# An actor that has arrived asks for nothing: `step()` sets a wake when it
	# moves and deliberately does not when it stops, so a parked mover cannot
	# schedule itself a heartbeat.
	var parked: int = int(w.actor("mole")["extra"].get("wake", -1))
	for i in 100:
		_assert_quiet(Movement.step(w, "mole", 1000 + i) == Movement.ARRIVED, "a parked mover stays put")
		_assert_quiet(int(w.actor("mole")["extra"].get("wake", -1)) == parked,
			"and asks for no tick of its own")
	_flush_quiet("a mover that has arrived costs the clock nothing (rule 8)")

	# --- deterministic across runs --------------------------------------------
	# Every mode, twice, from scratch: the same routes and the same step-by-step
	# outcomes. A recomputed walk is how D-9 avoids recording motion at all, so
	# this is the property the whole engine rests on.
	var traces: Array[String] = []
	for run in 2:
		var a := _movement_arena()
		var out: PackedStringArray = []
		out.append(str(Movement.path(a, SpeciesDefs.GROUND, west, east)))
		out.append(str(Movement.path(a, SpeciesDefs.HOP, west, east)))
		out.append(str(Movement.path(a, SpeciesDefs.BURROW, west, east)))
		out.append(str(Movement.reachable(a, SpeciesDefs.GROUND, west).size()))
		a.spawn_actor("m", "test_mole", west)
		Movement.plan(a, "m", east)
		out.append(_movement_trace(a, "m", 20))
		a.spawn_actor("k", "test_roo", west)
		Movement.plan(a, "k", east)
		out.append(_movement_trace(a, "k", 40))
		a.spawn_actor("wm", "test_worm", Vector2i(3, 3))
		Movement.plan(a, "wm", Vector2i(9, 9))
		out.append(_movement_trace(a, "wm", 20))
		a.spawn_actor("f", SpeciesDefs.CROW, west, { "fx": 5.5, "fy": 5.5 })
		for i in 40:
			Movement.fly_toward(a, "f", Movement.tile_centre(east), SpeciesDefs.speed_of(SpeciesDefs.CROW))
			out.append(str(Movement.float_pos(a, "f")))
		traces.append("|".join(out))
	_assert(traces[0] == traces[1], "every mode moves identically across two runs")
	_assert(traces[0].length() > 400, "and the trace is a real one (%d chars)" % traces[0].length())

	# The seam closes behind the tests: the shipping table stays the only source
	# of species, and WI-8's rows are the only way burrow and hop reach the game.
	Movement.forget_test_species()
	_assert(Movement.capability_of("test_mole").is_empty(),
		"the test-only species mechanism leaves nothing behind")
	for id in SpeciesDefs.ids():
		_assert_quiet(not SpeciesDefs.movement_of(id).is_empty(), "%s still answers from the real table" % id)
	_flush_quiet("and the shipping species table is untouched by it")


func test_scent() -> void:
	print("\n--- The scent layer: write on event, decay on read (P-10, M2.5 WI-7) Tests ---")

	# --- channels are data (P-10's pheromone/repellent/lure/wear) --------------
	_assert(Scent.has_channel(Scent.TRAIL), "the pest trail is a channel the layer knows")
	_assert(Scent.CHANNELS[Scent.TRAIL].has("half_life") and Scent.cap_of(Scent.TRAIL) > 0.0,
		"and its row says how fast it fades and how far reinforcement can go (design/04: the difficulty dial)")
	_assert(not Scent.has_channel("no_such_channel"), "a channel nobody defined does not exist")
	_assert(is_equal_approx(Scent.half_life_ticks(Scent.TRAIL),
			float(Scent.CHANNELS[Scent.TRAIL]["half_life"]) * float(SimClock.RATE)),
		"half-lives are stated in seconds and converted at SimClock.RATE, like a brain's timings")

	var field := Scent.new()
	var here := Vector2i(8, 8)
	_assert(field.deposit("no_such_channel", here, 50.0, 0) == 0.0
			and field.read("no_such_channel", here, 0) == 0.0
			and field.cell_count() == 0,
		"a typo'd channel writes nothing and reads as nothing, rather than becoming a phantom field")

	# --- the closed form, exact at arbitrary tick gaps (the WI's criterion) ----
	# The value at t is value₀ · retention^(t − t₀), computed once on read. Not
	# approached by stepping, not accumulated: asserted against `pow` itself, at
	# gaps chosen to be nothing like each other.
	var r := Scent.retention(Scent.TRAIL)
	_assert(r > 0.0 and r < 1.0, "a channel decays: 0 < retention < 1 (%.6f per tick)" % r)
	field.deposit(Scent.TRAIL, here, 80.0, 100)
	_assert(field.read(Scent.TRAIL, here, 100) == 80.0, "a fresh deposit reads as itself")
	for gap in [1, 2, 7, 13, 60, 137, 599, 1200]:
		_assert_quiet(field.read(Scent.TRAIL, here, 100 + gap) == 80.0 * pow(r, float(gap)),
			"the reading %d ticks later is the closed form" % gap)
	_flush_quiet("a trail read after N ticks equals closed-form decay, at every gap asked for")
	_assert(is_equal_approx(field.read(Scent.TRAIL, here, 100 + int(Scent.half_life_ticks(Scent.TRAIL))), 40.0),
		"which after one half-life is half of it — the number the designer actually tunes")
	_assert(field.read(Scent.TRAIL, here, 50) == 80.0,
		"and a reading stamped *before* the deposit does not decay backwards into a larger one")

	# Reinforcement composes with decay rather than papering over it: a second
	# deposit adds to what is left, not to what was once there.
	var left := field.read(Scent.TRAIL, here, 400)
	field.deposit(Scent.TRAIL, here, 30.0, 400)
	_assert(is_equal_approx(field.read(Scent.TRAIL, here, 400), left + 30.0),
		"reinforcement adds to what has survived (%.3f + 30)" % left)
	for i in 40:
		field.deposit(Scent.TRAIL, here, 50.0, 400)
	_assert(field.read(Scent.TRAIL, here, 400) == Scent.cap_of(Scent.TRAIL),
		"and a tile walked over a hundred times holds its cap, not a runaway number")

	# P-10's sanctioned answer to "we want a spread feel": pay for softness at
	# *write* time, in one event, instead of diffusing the field every tick. Nothing
	# ships that uses it; it is here so the first design that wants softness does not
	# reach for a per-tile pass.
	var soft := Scent.new()
	var scent_world := SimWorld.new()
	scent_world.generate()
	soft.deposit_blob(scent_world, Scent.TRAIL, Vector2i(9, 9), 20.0, 0, 1)
	_assert(soft.cell_count(Scent.TRAIL) == 5,
		"a blob writes its own tile and its four neighbours — five cells, not a map")
	_assert(soft.read(Scent.TRAIL, Vector2i(9, 9), 0) == 20.0
			and is_equal_approx(soft.read(Scent.TRAIL, Vector2i(9, 8), 0), 10.0),
		"strongest in the middle and weaker at the edge, in one event")

	# Faded is gone: a trail nobody reinforced stops being a gradient of
	# imperceptible numbers a forager could follow forever.
	field.deposit(Scent.TRAIL, Vector2i(1, 1), 1.0, 0)
	var faded_at := int(Scent.half_life_ticks(Scent.TRAIL) * 20.0)
	_assert(field.read(Scent.TRAIL, Vector2i(1, 1), faded_at) == 0.0,
		"a trail left alone for twenty half-lives reads as nothing at all")
	_assert(not field.cell(Scent.TRAIL, Vector2i(1, 1)).is_empty(),
		"though the cell is still there — reading it did not quietly rewrite the field")

	# --- reading never mutates (the determinism half of "lazy") ---------------
	var before := JSON.stringify(field.to_save())
	var count_before := field.cell_count()
	for i in 500:
		field.read(Scent.TRAIL, here, 400 + i * 37)
		field.read(Scent.TRAIL, Vector2i(3, 3), i)
		field.strongest_neighbour(Scent.TRAIL, here, i)
	_assert(JSON.stringify(field.to_save()) == before and field.cell_count() == count_before,
		"a thousand reads change nothing about what is stored (storage is a function of the writes)")

	# --- the gradient WI-8b's foragers walk on --------------------------------
	# A scout's trail home, strongest at the end it just left, and a forager reads
	# it one tile at a time.
	var trail := Scent.new()
	var route: Array[Vector2i] = [Vector2i(10, 5), Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5)]
	for i in route.size():
		trail.deposit(Scent.TRAIL, route[i], 10.0 + float(i) * 10.0, 0)
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), 0) == Vector2i(12, 5),
		"a forager standing on the trail is pulled toward the stronger end")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(13, 5), 0) == Vector2i(12, 5),
		"and at the strong end, back down it — the gradient, not the tile it is on")
	_assert(is_equal_approx(trail.strongest_neighbour_value(Scent.TRAIL, Vector2i(11, 5), 0), 30.0),
		"the strongest neighbour's reading is the other half of that answer")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(2, 15), 0) == Vector2i(2, 15),
		"and a tile in clean air answers with itself: there is nothing to follow")
	_assert(trail.strongest_neighbour_value(Scent.TRAIL, Vector2i(2, 15), 0) == 0.0,
		"reading as nothing, so a brain can tell 'follow' from 'search'")
	# Ties break on Movement's neighbour order — the pathfinder's tie-break, not a
	# second one that could drift from it — so two ants in one field agree.
	var even := Scent.new()
	for d in Movement.DIRS:
		even.deposit(Scent.TRAIL, Vector2i(6, 6) + d, 25.0, 0)
	_assert(even.strongest_neighbour(Scent.TRAIL, Vector2i(6, 6), 0) == Vector2i(6, 6) + Movement.DIRS[0],
		"equal neighbours break the tie in Movement.DIRS order, on every machine")
	# The gradient decays with everything else: the same field, later, still points
	# the same way (decay is uniform per channel) but has stopped being followable.
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), 3000) == Vector2i(12, 5),
		"a decayed trail still points the same way")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), faded_at) == Vector2i(11, 5),
		"until it has faded, and then it points nowhere")

	# --- erasure: the counterplay, as a hole rather than a dent ---------------
	_assert(trail.erase(Scent.TRAIL, Vector2i(12, 5)), "a washed cell had something in it")
	_assert(trail.read(Scent.TRAIL, Vector2i(12, 5), 0) == 0.0
			and trail.cell(Scent.TRAIL, Vector2i(12, 5)).is_empty(),
		"and afterwards holds nothing at all — full-cell erasure, not a subtraction")
	_assert(trail.strongest_neighbour(Scent.TRAIL, Vector2i(11, 5), 0) == Vector2i(10, 5),
		"which is what breaks a gradient: the column is pulled back the way it came")
	_assert(is_equal_approx(trail.read(Scent.TRAIL, Vector2i(13, 5), 0), 40.0),
		"the tiles either side of the wash are untouched")
	_assert(not trail.erase(Scent.TRAIL, Vector2i(12, 5)), "washing clean ground erases nothing")

	# A wash takes every channel, because water on a tile is water on a tile.
	Scent.define_test_channel("test_lure", 30.0)
	trail.deposit("test_lure", Vector2i(13, 5), 12.0, 0)
	_assert(trail.wash(Vector2i(13, 5)) == 2, "one wash, both channels")
	_assert(trail.read(Scent.TRAIL, Vector2i(13, 5), 0) == 0.0
			and trail.read("test_lure", Vector2i(13, 5), 0) == 0.0,
		"and neither of them survives it")
	_assert(trail.wash(Vector2i(1, 19)) == 0, "washing a tile nothing has marked is a no-op")

	# --- the wash is wired to the `water` verb (P-10: no new verb, no new UI) --
	GameState.reset()
	SimRng.reseed(77)
	var world := SimWorld.new()
	world.generate()
	_assert(world.scent.cell_count() == 0,
		"a generated world holds no cells: nothing iterates tiles to make them (P-10's guardrail)")
	var plot := WorldLayout.spawn()
	var soil := Vector2i(plot.x + 1, plot.y)
	GameState.watering_can_charges = 8
	GameState.pouch["wheat"] = 5
	world.apply_action({ "verb": "till", "target": soil, "actor": "player" }, GameState)
	world.apply_action({ "verb": "plant", "target": soil, "seed_type": "wheat", "actor": "player" }, GameState)
	world.scent.deposit(Scent.TRAIL, soil, 60.0, world.clock.tick)
	world.scent.deposit(Scent.TRAIL, soil + Vector2i(1, 0), 60.0, world.clock.tick)
	_assert(world.scent.read(Scent.TRAIL, soil, world.clock.tick) == 60.0, "a trail runs across her plot")
	var watered := world.apply_action({ "verb": "water", "target": soil, "actor": "player" }, GameState)
	_assert(watered.get("ok", false) and world.get_tile(soil.x, soil.y).watered_today,
		"she waters the tile, and it is wet — the verb still does its own job")
	_assert(world.scent.read(Scent.TRAIL, soil, world.clock.tick) == 0.0,
		"and the trail on it is washed away (P-10's counterplay, through the existing verb)")
	_assert(world.scent.read(Scent.TRAIL, soil + Vector2i(1, 0), world.clock.tick) == 60.0,
		"the next tile along is untouched: a wash is one tile, and one tile is a hole in a trail")
	GameState.watering_can_charges = 0
	world.scent.deposit(Scent.TRAIL, soil, 60.0, world.clock.tick)
	var dry := world.apply_action({ "verb": "water", "target": soil, "actor": "player" }, GameState)
	_assert(not dry.get("ok", false) and world.scent.read(Scent.TRAIL, soil, world.clock.tick) == 60.0,
		"a watering that fails washes nothing — an empty can is not a bucket")

	# --- ...and rain washes the lot (`[Designer]` Q-58, ruled 2026-08-31) -----
	#
	# "Water is water": what her bucket does to one tile, the sky does to all of
	# them at once. Three claims, in order — every channel goes, *only* rain does
	# it, and the clean ground survives a save and a replay like any other fact a
	# day turn produces.
	world.scent.deposit(Scent.TRAIL, soil + Vector2i(2, 0), 45.0, world.clock.tick)
	world.scent.deposit("test_lure", soil + Vector2i(3, 0), 20.0, world.clock.tick)
	var marked_tiles: Array[Vector2i] = [soil, soil + Vector2i(1, 0), soil + Vector2i(2, 0), soil + Vector2i(3, 0)]
	var dusk = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	_assert(world.scent.cell_count() == 4 and dusk["world"]["scent"].has("test_lure"),
		"a trail and a lure lie across her plot as she goes to bed")

	# The dry night first, from the same dusk, so the two mornings differ in the
	# weather and in nothing else.
	var dry_gs = load("res://systems/game_state.gd").new()
	var dry_world := SimWorld.new()
	SaveGame.restore(dusk, dry_world, dry_gs)
	dry_world.apply_action({ "verb": "sleep", "weather": "sunny", "actor": "player" }, dry_gs)
	var dry_tick := dry_world.clock.tick
	_assert(dry_world.scent.cell_count() == 4, "a dry night leaves every cell where it was")
	_assert(is_equal_approx(dry_world.scent.read(Scent.TRAIL, soil, dry_tick), 60.0),
		"...holding the value it held, because a day turn is not a decay rule of its own")
	_assert(is_equal_approx(dry_world.scent.read(
			Scent.TRAIL, soil, dry_tick + int(Scent.half_life_ticks(Scent.TRAIL))), 30.0),
		"and still halving on its own clock, exactly as it did yesterday")
	dry_gs.free()

	# The wet one.
	world.apply_action({ "verb": "sleep", "weather": "rainy", "actor": "player" }, GameState)
	_assert(world.scent.cell_count() == 0, "**a rainy night washes the farm** — not one cell is left")
	var rained_clean := true
	for c in Scent.channels():
		for t in marked_tiles:
			if world.scent.read(String(c), t, world.clock.tick) != 0.0:
				rained_clean = false
	_assert(rained_clean,
		"every channel on every marked tile reads nothing: the lure goes with the trail")
	_assert(world.scent.to_save().is_empty(),
		"and the field holds no cells at all, rather than a map of zeroes")

	# The round trip WI-5's net asks of everything else: a session that lays a
	# trail, sleeps in the rain and is replayed from its own save must wake to the
	# same clean ground. The wash is not recorded anywhere — the *weather* is, and
	# the replay washes the farm for the same reason the session did.
	var wet := LiveSession.new(5858)
	wet.world.scent.deposit(Scent.TRAIL, Vector2i(6, 6), 70.0, wet.world.clock.tick)
	wet.world.scent.deposit("test_lure", Vector2i(7, 6), 25.0, wet.world.clock.tick)
	wet.rebase()
	_assert(wet.act({ "verb": "sleep", "weather": "rainy", "actor": "player" }).get("ok", false)
			and wet.world.scent.cell_count() == 0,
		"a recorded session sleeps through the rain and wakes to a washed farm")
	var wet_end = JSON.parse_string(JSON.stringify(SaveGame.capture(wet.world, wet.gs)))
	var wet_report := SaveGame.replay_report(wet.log, wet_end)
	_assert(wet_report["matched"],
		"and its replay reproduces the wash rather than the trail %s" % wet_report["divergence"])
	wet.done()

	# --- cost scales with writes, not tiles (ground rule 8) -------------------
	# Two halves of one claim. First: the work is proportional to the number of
	# deposits and reads, and 40,000 of them are cheap. Second, and the one the
	# guardrail is actually about: the *map* is not in the cost at all — neither
	# in storage (a cell exists because it was written) nor in time (elapsed ticks
	# are one `pow`, not a loop over them).
	var bench := Scent.new()
	var t0 := Time.get_ticks_msec()
	for pass_i in 40:
		for i in 500:
			bench.deposit(Scent.TRAIL, Vector2i(i % 32, i / 32), 1.0, pass_i * 10)
	for pass_i in 40:
		for i in 500:
			bench.read(Scent.TRAIL, Vector2i(i % 32, i / 32), 400 + pass_i * 1000)
	var writes_ms := Time.get_ticks_msec() - t0
	_assert(bench.cell_count(Scent.TRAIL) == 500,
		"20,000 deposits over 500 tiles are 500 cells — storage counts writes, not tiles")
	_assert(writes_ms < 400, "and 40,000 deposits and reads cross in under 400 ms (%d ms)" % writes_ms)

	var sparse := Scent.new()
	sparse.deposit(Scent.TRAIL, Vector2i(4, 4), 50.0, 0)
	var t1 := Time.get_ticks_msec()
	for i in 20000:
		sparse.read(Scent.TRAIL, Vector2i(4, 4), 1_000_000 + i)
	var far_ms := Time.get_ticks_msec() - t1
	_assert(sparse.cell_count() == 1, "one written cell is one cell on a 32x20 map")
	_assert(far_ms < 200,
		"and reading it a million ticks later costs the same as one tick later (%d ms for 20,000 reads)" % far_ms)
	_assert(sparse.read(Scent.TRAIL, Vector2i(4, 4), 1_000_000) == 0.0
			and sparse.read(Scent.TRAIL, Vector2i(4, 4), 0) == 50.0,
		"a million ticks of nobody looking is still a million ticks of decay")
	# The explicit sweep exists, and nothing in the sim calls it (see compact()).
	_assert(sparse.compact(1_000_000) == 1 and sparse.cell_count() == 0,
		"a caller with a deterministic reason can reclaim a faded cell explicitly")

	# --- it saves, it restores, and a pre-scent save is a clean field ---------
	var keeper := SimWorld.new()
	SimRng.reseed(505)
	keeper.generate()
	keeper.clock.advance_to(900)
	for i in 6:
		keeper.scent.deposit(Scent.TRAIL, Vector2i(5 + i, 7), 12.5 + float(i), 900 - i * 30)
	keeper.scent.deposit("test_lure", Vector2i(5, 7), 3.25, 880)
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(keeper, GameState)))
	_assert(snap["world"].has("scent") and snap["world"]["scent"].has(Scent.TRAIL),
		"a save carries the written cells")
	var back := SimWorld.new()
	var gs_back = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snap, back, gs_back), "and restores")
	_assert(back.scent.cell_count(Scent.TRAIL) == 6 and back.scent.cell_count("test_lure") == 1,
		"with every cell in both channels")
	var same := true
	for i in 6:
		var t := Vector2i(5 + i, 7)
		# JSON carries about fifteen significant digits, so a round trip is equal to
		# a hair rather than bit-for-bit; what has to survive exactly is the *shape*
		# (which tiles, which ticks) and it does.
		if not is_equal_approx(back.scent.read(Scent.TRAIL, t, 900), keeper.scent.read(Scent.TRAIL, t, 900)):
			same = false
		if int(back.scent.cell(Scent.TRAIL, t)["tick"]) != int(keeper.scent.cell(Scent.TRAIL, t)["tick"]):
			same = false
	_assert(same, "every restored cell reads the same value at the same tick, from the same stamp")
	_assert(JSON.stringify(back.scent.to_save()) == JSON.stringify(keeper.scent.to_save()),
		"and the field's serialized form is canonical — sorted by tile, so two equal fields compare equal")

	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": keeper.tiles.duplicate(true), "objects": keeper.objects.duplicate(true) },
		"state": {} }
	var old_world := SimWorld.new()
	var gs_old = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, old_world, gs_old), "a save written before the scent layer still restores")
	_assert(old_world.scent.cell_count() == 0, "reading, correctly, as a farm nobody has marked")
	# Restoring into a world that already holds a field replaces it rather than
	# merging: a load is a world, not an addition to the one you were playing.
	var reused := SimWorld.new()
	reused.scent.deposit(Scent.TRAIL, Vector2i(2, 2), 99.0, 0)
	var gs_reused = load("res://systems/game_state.gd").new()
	SaveGame.restore(snap, reused, gs_reused)
	_assert(reused.scent.read(Scent.TRAIL, Vector2i(2, 2), 900) == 0.0
			and reused.scent.cell_count(Scent.TRAIL) == 6,
		"and loading a save replaces the field rather than merging into it")
	gs_back.free()
	gs_old.free()
	gs_reused.free()

	# Same deposits in the same order, twice: the same field, byte for byte. The
	# property WI-8's ants and WI-5's replays both rest on.
	var runs: Array[String] = []
	for run in 2:
		var f := Scent.new()
		for i in 200:
			f.deposit(Scent.TRAIL, Vector2i(i % 17, (i * 7) % 13), 1.0 + float(i % 5), i * 3)
			if i % 11 == 0:
				f.wash(Vector2i((i * 3) % 17, i % 13))
		runs.append(JSON.stringify(f.to_save()))
	_assert(runs[0] == runs[1], "the same writes twice produce the same field, byte for byte")

	# The seam closes behind the tests, exactly as the movement engine's does: the
	# shipping table stays the only source of channels.
	Scent.forget_test_channels()
	_assert(not Scent.has_channel("test_lure"), "the test-only channel mechanism leaves nothing behind")
	_assert(Scent.channels().size() == Scent.CHANNELS.size(),
		"and the shipping channel set is untouched by it")


func test_sprinkler() -> void:
	print("\n--- The first machine: a sprinkler waters (design/03, M2.5 WI-10) Tests ---")

	# --- the row: a machine is an actor, and an actor is measured like any other -
	_assert(SpeciesDefs.has(SpeciesDefs.SPRINKLER), "the sprinkler is a species the table knows")
	_assert(str(SpeciesDefs.verbs_of(SpeciesDefs.SPRINKLER)) == str(["water"]),
		"and its whole vocabulary is one verb the player already owns (design/03: it does nothing the can couldn't)")
	_assert("water" in SpeciesDefs.PLAYER_VERBS,
		"which is what makes it legal under ground rule 1 — no capability she lacks")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.SPRINKLER) == SpeciesDefs.STATIC
			and SpeciesDefs.speed_of(SpeciesDefs.SPRINKLER) == 0.0,
		"it is stationary, and says so with its mode rather than with a speed of nearly zero")
	_assert(SpeciesDefs.is_persistent(SpeciesDefs.SPRINKLER),
		"a machine is a resident: it is in the save, unlike a crow's visit")
	_assert(Brains.of_species(SpeciesDefs.SPRINKLER) is SprinklerBrain,
		"its brain id binds to the brain this work item wrote")
	_assert(not Brains.of_species(SpeciesDefs.SPRINKLER).on_clock(),
		"which is not on the tick clock: a machine fires once a morning, it is not a heartbeat")

	# --- stationary means the engine cannot be asked to move it ---------------
	GameState.reset()
	SimRng.reseed(4040)
	var world := SimWorld.new()
	world.generate()
	var middle := Vector2i(20, 10)
	var pending_before := world.clock.pending()
	world.spawn_actor("sprinkler_1", SpeciesDefs.SPRINKLER, middle)
	_assert(world.clock.pending() == pending_before,
		"spawning one schedules nothing: it costs the clock nothing between days (rule 8)")
	_assert(not Movement.plan(world, "sprinkler_1", Vector2i(10, 10)),
		"no route can be planned for it")
	_assert(Movement.path(world, SpeciesDefs.STATIC, middle, Vector2i(10, 10)).is_empty()
			and Movement.reachable(world, SpeciesDefs.STATIC, middle).is_empty(),
		"in either search, because a machine travels through nothing")
	_assert(Movement.step(world, "sprinkler_1", 1) == Movement.ARRIVED
			and world.actor_pos("sprinkler_1") == middle,
		"and stepping it reports that it is already where it is going")

	# --- the criterion: tiles in radius wake watered, tiles outside don't -----
	# A 5x5 of planted soil around a radius-1 machine, so the edge of its reach is
	# inside the plot rather than at the edge of the world.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t: Vector2i = middle + Vector2i(dx, dy)
			world.set_tile_state(t.x, t.y, "seeded", "wheat")
	GameState.watering_can_charges = GameState.max_watering_can_charges
	# Weather is overridden the way a replay overrides it, so "it rained" cannot be
	# the reason a tile outside the radius is wet.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	var inside := 0
	var outside_wet := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t: Vector2i = middle + Vector2i(dx, dy)
			var wet: bool = world.get_tile(t.x, t.y).watered_today
			if maxi(absi(dx), absi(dy)) <= SprinklerBrain.RADIUS:
				if wet:
					inside += 1
			elif wet:
				outside_wet += 1
	_assert(inside == 9, "every tile in the machine's radius wakes watered (%d of 9)" % inside)
	_assert(outside_wet == 0, "and no tile outside it does (%d wet)" % outside_wet)
	_assert(GameState.weather == "sunny", "on a day it did not rain")

	# It waters with the verb, so it pays what the verb costs — out of its own
	# meter (every actor has one), never out of hers, and never out of her can.
	_assert(world.energy_of("sprinkler_1") == SimWorld.ACTOR_MAX_ENERGY - 9 * Tools.get_energy_cost("water"),
		"it spends its own energy on the nine tiles, and wakes refilled to do it again")
	_assert(GameState.watering_can_charges == GameState.max_watering_can_charges
			and GameState.energy == GameState.max_energy,
		"her can and her arms are untouched — which is the entire point of owning one")

	# The chore it retires, actually retired: the crops under it grow, on a dry
	# week, with nobody carrying anything.
	var under := middle + Vector2i(1, 0)
	var beyond := middle + Vector2i(2, 0)
	for _i in 3:
		world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(world.get_tile(under.x, under.y).state == "ready",
		"a crop inside the radius grows to ready on its own (design/03: your old job, happening without you)")
	_assert(world.get_tile(beyond.x, beyond.y).state == "seeded"
			and world.get_tile(beyond.x, beyond.y).growth_stage == 0,
		"and a crop one tile beyond it is exactly as far along as the day it was planted")

	# --- coverage is data about the machine, not a second implementation ------
	_assert(SprinklerBrain.coverage(world, "sprinkler_1").size() == 9,
		"coverage answers with the nine tiles it waters")
	_assert(SprinklerBrain.coverage(world, "sprinkler_1")[0] == middle + Vector2i(-1, -1),
		"in a fixed order, so two runs of the same farm water in the same sequence")
	world.actor("sprinkler_1")["extra"]["radius"] = 0
	_assert(str(SprinklerBrain.coverage(world, "sprinkler_1")) == str([middle]),
		"and a per-actor radius overrides the species default (the body_len pattern, for M3's upgrades)")
	world.actor("sprinkler_1")["extra"]["radius"] = 2
	_assert(SprinklerBrain.coverage(world, "sprinkler_1").size() == 25, "in both directions")
	world.actor("sprinkler_1")["extra"].erase("radius")
	# A machine at the edge of the map sprays what is there and nothing else.
	world.spawn_actor("sprinkler_edge", SpeciesDefs.SPRINKLER, Vector2i(0, 0))
	_assert(SprinklerBrain.coverage(world, "sprinkler_edge").size() == 4,
		"a machine in the corner waters the four tiles that exist, not the five that don't")
	world.despawn_actor("sprinkler_edge")

	# Who acts at a day turn is sorted by id, so it cannot depend on registry
	# order — which differs between a generated world and a restored one.
	world.spawn_actor("sprinkler_b", SpeciesDefs.SPRINKLER, Vector2i(6, 12))
	world.spawn_actor("sprinkler_a", SpeciesDefs.SPRINKLER, Vector2i(9, 12))
	var day_actions := Brains.day_actions(world, GameState)
	_assert(day_actions.size() == 27, "three machines, nine tiles each, one list")
	_assert(String(day_actions[0]["actor"]) == "sprinkler_1"
			and String(day_actions[9]["actor"]) == "sprinkler_a"
			and String(day_actions[18]["actor"]) == "sprinkler_b",
		"in actor-id order, whatever order they were spawned in")
	for a in day_actions:
		_assert_quiet(String(a["verb"]) == "water", "a machine's day action is a water")
	_flush_quiet("and every one of them is the player's own verb, through the one gateway")
	world.despawn_actor("sprinkler_a")
	world.despawn_actor("sprinkler_b")
	_assert(Brains.day_actions(SimWorld.new(), GameState).is_empty(),
		"a farm with no machines on it — which is every farm in the game today — turns its day with an empty list")

	# --- it saves and it replays, like any other actor ------------------------
	var s := LiveSession.new(808)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			s.world.set_tile_state(20 + dx, 10 + dy, "seeded", "wheat")
	s.world.spawn_actor("sprinkler_1", SpeciesDefs.SPRINKLER, Vector2i(20, 10))
	# Rebased on a snapshot of right now, exactly as a session continued from an
	# autosave is: nothing *places* a machine, so a save is how one reaches a
	# replay (Q-15 owns the acquisition path that would make it an Action).
	s.rebase()
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	s.tick(200)
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	_assert(snap["world"]["actors"].has("sprinkler_1")
			and String(snap["world"]["actors"]["sprinkler_1"]["species"]) == SpeciesDefs.SPRINKLER,
		"a machine is in the save, at its tile, like any resident")
	_assert(SaveGame.replay_matches(s.log, snap),
		"and the session reproduces its own autosave — the day turn waters the same nine tiles again")
	var restored := SimWorld.new()
	var gs_restored = load("res://systems/game_state.gd").new()
	SaveGame.restore(snap, restored, gs_restored)
	_assert(restored.actor_pos("sprinkler_1") == Vector2i(20, 10)
			and restored.species_of("sprinkler_1") == SpeciesDefs.SPRINKLER,
		"a reloaded farm still has its machine, standing where it stood")
	_assert(not restored._brain_events.has("sprinkler_1")
			and not Brains.of_actor(restored, "sprinkler_1").on_clock(),
		"and a load does not put it on the clock: schedule_all_brains skips a brain that is not on one")
	restored.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs_restored)
	_assert(restored.get_tile(20, 10).watered_today,
		"and it waters the morning after a reload, which is the thing F-7c was about for the hen")
	gs_restored.free()
	s.done()


func test_pea() -> void:
	print("\n--- Pea, an ordinary crop (Q-55 ruled 2026-08-31; on the shelf by P-19) Tests ---")

	var pea: Dictionary = CropDefs.TYPES.get("pea", {})
	_assert(not pea.is_empty(), "pea is a crop type")
	_assert(int(pea.days_to_grow) == 3 and int(pea.stages) == 4,
		"three days to grow, four visual stages — the shape wheat and tomato already have")
	_assert(int(pea.sell_price) == 15 and int(pea.seed_price) == 8,
		"P-19's prices [Playtest]: an 8g packet, a 15g pea")
	# P-19's reason for those prices: kept for replanting (S-19 returns three
	# units), a pea earns 10g per growing day and a tomato 12g, so the pea is the
	# cheap, quick start and never the best crop income.
	var tomato_def: Dictionary = CropDefs.TYPES["tomato"]
	var pea_per_day := float(2 * int(pea.sell_price)) / float(pea.days_to_grow)
	var tomato_per_day := float(2 * int(tomato_def.sell_price)) / float(tomato_def.days_to_grow)
	_assert(pea_per_day < tomato_per_day and int(pea.seed_price) < int(tomato_def.seed_price)
			and int(pea.days_to_grow) < int(tomato_def.days_to_grow),
		"cheaper and quicker than a tomato, but it earns less per growing day")
	_assert(int(pea.sell_price) > int(pea.seed_price),
		"and worth more than its seed, which is the only balance rule that is not taste")
	var sheet: Texture2D = load("res://assets/sprites/generated/pea.png")
	_assert(sheet != null and sheet.get_image().get_width() >= int(pea.stages) * 16,
		"its growth stages are really in pea.png, not cells off the end of it")
	_assert(int(pea.icon_col) == 6, "its icon column points at the pea packet after the six existing shop icons")
	var icons: Texture2D = load("res://assets/sprites/generated/shop_icons.png")
	_assert(icons != null and icons.get_width() == 112,
		"the pea packet is a seventh 16px shop-icon cell")

	# P-19: the shelf lists tomato, pea, then the scarecrow. Every shop, HUD and
	# seed-picker path iterates ORDER, so this row is the whole debut.
	_assert(CropDefs.is_on_shelf("pea"), "the shop sells pea seeds")
	_assert(CropDefs.ORDER.find("pea") == CropDefs.ORDER.find("tomato") + 1
			and CropDefs.ORDER.find("scarecrow") == CropDefs.ORDER.find("pea") + 1,
		"listed after the tomato and before the scarecrow")
	_assert(not CropDefs.is_seed_unlocked("pea", {}),
		"behind the same first-harvest gate the tomato is")
	_assert(CropDefs.is_seed_unlocked("pea", { "wheat": 1 }), "which one wheat opens")

	# Growth, through the ordinary stages, with no special case anywhere.
	for stage in [0, 1, 2, 3]:
		_assert_quiet(CropDefs.get_visual_stage("pea", stage) == stage,
			"pea at growth %d draws its stage-%d cell" % [stage, stage])
	_flush_quiet("a pea walks up its four stages exactly as wheat does")
	_assert(not CropDefs.is_ready("pea", 2) and CropDefs.is_ready("pea", 3),
		"and is ready on the third day, not the second")

	# ...and the same walk through the gateway, in a real world: planted, watered,
	# slept over three times, harvested, sold.
	GameState.reset()
	SimRng.reseed(606)
	var world := SimWorld.new()
	world.generate()
	var plot := Vector2i(20, 10)
	world.set_tile_state(plot.x, plot.y, "cleared")
	# Peas and nothing else in the pouch, one over the keep line, so what the bin
	# pays at the end of this walk is the pea's own price and not a wheat's.
	GameState.pouch = { "pea": 0 + 1 }
	GameState.gold = 0
	_assert(world.apply_action({ "verb": "till", "target": plot, "actor": "player" }, GameState).get("ok", false)
			and world.apply_action({ "verb": "plant", "target": plot, "seed_type": "pea", "actor": "player" }, GameState).get("ok", false),
		"she tills and plants a pea with the verbs she already had")
	_assert(world.get_crop_type(plot.x, plot.y) == "pea"
			and GameState.pouch["pea"] == 0,
		"the tile holds a pea and the seed left her pocket")
	for _day in 3:
		world.apply_action({ "verb": "water", "target": plot, "actor": "player" }, GameState)
		world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(world.get_tile(plot.x, plot.y).state == "ready"
			and world.get_tile(plot.x, plot.y).growth_stage == 3,
		"three watered nights and it is ready")
	var harvested := world.apply_action({ "verb": "harvest", "target": plot, "actor": "player" }, GameState)
	_assert(harvested.get("ok", false) and String(harvested.get("crop_type", "")) == "pea",
		"harvesting one gives back a pea")
	_assert(int(GameState.pouch.get("pea", 0)) == 3
			and int(GameState.harvest_counts.get("pea", 0)) == 1,
		"three plantable peas land in her pouch; the harvest tally rises once")
	var gold_before: int = GameState.gold
	_assert(GameState.sell_crops_to_bin().ok, "and she deposits them")
	_assert(GameState.gold == gold_before and int(GameState.bin_reserve.pea) == 3,
		"the first three peas enter their own reserve before any sale")


# --- M2.5 WI-5 -----------------------------------------------------------------

# A live session that is guaranteed to contain at least one Action a brain took,
# so the dual-record net has something to compare. The hen's egg is a coin flip
# at each day turn (Q-10), so this turns days until one lands rather than
# assuming the first morning obliges.
func test_hen_replay_from_fresh_save() -> void:
	print("\n--- Hen replay from a fresh-world save Tests ---")

	var gs_live = load("res://systems/game_state.gd").new()
	gs_live.reset()
	SimRng.reseed(6363)
	var live := SimWorld.new()
	live.generate()
	var base = JSON.parse_string(JSON.stringify(SaveGame.capture(live, gs_live)))
	var log := ReplayLog.new()
	log.start_from_save(base, live.gen_seed)

	for taken in live.advance_ticks(400, gs_live):
		if taken["result"].get("ok", false):
			log.record(taken["action"], taken["result"], int(taken["tick"]), true)
	log.mark_tick(live.clock.tick)
	var live_hen := live.actor_pos(SimWorld.ACTOR_CHICKEN)

	var replayed := SimWorld.new()
	var gs_replayed = load("res://systems/game_state.gd").new()
	_assert(log.apply_to(replayed, gs_replayed), "the fresh-world base save reloads for replay")
	var replayed_hen := replayed.actor_pos(SimWorld.ACTOR_CHICKEN)
	_assert(replayed_hen == live_hen,
		"the hen replayed from a fresh-world save ends on her live-play tile "
			+ "(live %s, replay %s)" % [live_hen, replayed_hen])

	gs_live.free()
	gs_replayed.free()


# Found by the many-games check, 2026-10-09 (seed 918801901): a coop whose front is
# blocked lets out of a side square (`SimWorld.room_exit_for`), and the hen, standing
# on that side square in the rain, reached for "the hut above her" — which from the
# side is grass. The gateway answered "no door here" about once a tick all day. She
# reaches for the hut beside her now, so she goes in.
func test_hen_side_door() -> void:
	print("\n--- A hen lets herself into a coop by its side door Tests ---")
	GameState.reset()
	SimRng.reseed(9111)
	var world := SimWorld.new()
	world.generate()
	GameState.gold = 1000
	var spot := Vector2i(-1, -1)
	for y in range(10, 17):
		for x in range(5, 23):
			if world.placeable_at(Vector2i(x, y), "coop"):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	for dy in range(-3, 3):
		for dx in range(-2, 4):
			var t: Vector2i = spot + Vector2i(dx, dy)
			world.set_tile_state(t.x, t.y, "cleared")
	_assert(world.apply_action({ "verb": "buy_machine", "item": "coop",
			"actor": "player" }, GameState).get("ok", false)
			and world.apply_action({ "verb": "place", "target": spot, "item": "coop",
				"actor": "player" }, GameState).get("ok", false),
		"a coop is bought and put down the ordinary way (%s)" % spot)

	# Fence off both squares under the hut, so the room lets out of its side.
	for front in [spot + Vector2i(0, 1), spot + Vector2i(1, 1)]:
		world.set_tile_state(front.x, front.y, WorldLayout.FENCE_BUILT)
	var room_id := ""
	for id in world.room_ids():
		if String(world.rooms[id].get("item", "")) == SimWorld.COOP_ITEM:
			room_id = id
	var side := world.room_exit_for(world.rooms[room_id])
	_assert(side.x >= 0 and side.y <= spot.y,
		"with its front fenced off the coop lets out of a side square (%s)" % side)

	# She starts on that side square on a wet day: the one place the old aim missed.
	world.spawn_actor(SimWorld.ACTOR_CHICKEN, SpeciesDefs.CHICKEN, side)
	GameState.weather = "rainy"
	var refused := 0
	var went_in := false
	for taken in world.advance_ticks(600, GameState):
		var action: Dictionary = taken["action"]
		if String(action.get("verb", "")) != "use_door":
			continue
		if taken["result"].get("ok", false):
			went_in = true
		else:
			refused += 1
	_assert(refused == 0,
		"she never asks for a door that is not there (%d refused)" % refused)
	_assert(went_in and world.room_of_cell(world.actor_pos(SimWorld.ACTOR_CHICKEN)) == room_id,
		"she lets herself in by the side and is standing on the coop's floor (%s)"
			% world.actor_pos(SimWorld.ACTOR_CHICKEN))
	GameState.weather = "sunny"


func test_replay_v2() -> void:
	print("\n--- Replay format v4 + the dual-record net (M2.5 WI-5) Tests ---")

	# --- the format ------------------------------------------------------------
	var s := _session_with_brain_actions(4321)
	_assert(ReplayLog.VERSION == 4, "the format version is 4 (all brain decisions are checked)")
	_assert(_brain_entry_count(s.log) > 0,
		"the session contains Actions a brain decided (%d of %d entries)"
			% [_brain_entry_count(s.log), s.log.entries.size()])
	var stamped := true
	var ordered := true
	var last_tick := -1
	for e in s.log.entries:
		stamped = stamped and e.has("tick")
		ordered = ordered and int(e["tick"]) >= last_tick
		last_tick = int(e["tick"])
	_assert(stamped, "every entry carries the tick it happened on")
	_assert(ordered, "and the stream is in tick order, which is what lets a replay walk it")
	_assert(s.log.end_tick >= last_tick and s.log.end_tick == s.world.clock.tick,
		"the log knows how long the session ran (%d ticks), not just when it last acted"
			% s.log.end_tick)

	var text := s.log.to_json()
	var reloaded := ReplayLog.from_json(text)
	_assert(reloaded.version == 4, "a v4 log reads back as v4")
	_assert(reloaded.entries.size() == s.log.entries.size()
			and _brain_entry_count(reloaded) == _brain_entry_count(s.log),
		"with every entry and every brain mark intact")
	_assert(reloaded.end_tick == s.log.end_tick,
		"and the end tick survives the round trip (it rides as a mark line, so a flush stays append-only)")
	_assert(text.contains("\"mark\":"), "which is what that line is")
	_assert(ReplayLog.from_json(reloaded.to_json()).to_json() == reloaded.to_json(),
		"and re-serializes stably")

	# --- the net: the recomputation is the recording ---------------------------
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var report := SaveGame.replay_report(reloaded, snapshot)
	_assert(String(report["divergence"]) == "",
		"the brains recompute exactly what they were recorded doing %s" % report["divergence"])
	_assert(report["matched"],
		"and the session reproduces its own autosave — positions, clock and all")
	_assert(String(report["state_difference"]) == "",
		"and a matching state has no reported difference")
	var presentation_snapshot: Dictionary = snapshot.duplicate(true)
	presentation_snapshot["state"]["story_loops_shown"]["robot_night"] = true
	_assert(SaveGame.replay_report(reloaded, presentation_snapshot)["matched"],
		"a presentation-only story-loop guard is not mistaken for sim drift")
	var changed_snapshot: Dictionary = snapshot.duplicate(true)
	changed_snapshot["world"]["tiles"][0][0]["watered_today"] = \
		not bool(changed_snapshot["world"]["tiles"][0][0]["watered_today"])
	var changed_report := SaveGame.replay_report(reloaded, changed_snapshot)
	_assert(not changed_report["matched"]
			and String(changed_report["state_difference"]).begins_with(
				"world.tiles[0][0].watered_today: replay has ")
			and String(changed_report["state_difference"]).contains("; autosave has "),
		"a state mismatch names the first field and both values: %s"
			% changed_report["state_difference"])
	# The state comparison is doing real work now: the hen's tile is in it (the
	# WI-3 seam, closed above), so this is not merely the grids agreeing.
	var w_replay := SimWorld.new()
	var gs_replay = load("res://systems/game_state.gd").new()
	reloaded.apply_to(w_replay, gs_replay)
	_assert(w_replay.actor_pos(SimWorld.ACTOR_CHICKEN) == s.world.actor_pos(SimWorld.ACTOR_CHICKEN),
		"the replayed hen ends where the recorded hen ended (%s), having walked there herself"
			% s.world.actor_pos(SimWorld.ACTOR_CHICKEN))
	_assert(w_replay.clock.tick == s.world.clock.tick,
		"and the same amount of sim time passed (%d ticks)" % w_replay.clock.tick)
	_assert(_count_objects(w_replay, "egg") == _count_objects(s.world, "egg"),
		"and a recomputed Action is applied once, not twice — the same eggs, not double")
	gs_replay.free()

	# --- the net catches a recording that no longer recomputes ------------------
	# Each of these is a way a refactor could silently change what an NPC does.
	# The net's whole job is that none of them is silent.
	var tampered := ReplayLog.from_json(text)
	var first_brain := -1
	for i in tampered.entries.size():
		if bool(tampered.entries[i].get("brain", false)):
			first_brain = i
			break
	tampered.entries[first_brain]["target"] = [0, 0]
	var w_t := SimWorld.new()
	var gs_t = load("res://systems/game_state.gd").new()
	tampered.apply_to(w_t, gs_t)
	_assert(tampered.divergence.contains("entry %d" % first_brain),
		"a brain Action recorded on a different tile fails, naming the entry: %s" % tampered.divergence)
	gs_t.free()

	var late := ReplayLog.from_json(text)
	late.entries[first_brain]["tick"] = int(late.entries[first_brain]["tick"]) + 3
	var w_l := SimWorld.new()
	var gs_l = load("res://systems/game_state.gd").new()
	late.apply_to(w_l, gs_l)
	_assert(late.divergence != "",
		"the same Action three ticks late fails too — when is half of what it means")
	gs_l.free()

	var missing := ReplayLog.from_json(text)
	missing.entries.remove_at(first_brain)
	var w_m := SimWorld.new()
	var gs_m = load("res://systems/game_state.gd").new()
	missing.apply_to(w_m, gs_m)
	_assert(missing.divergence != "",
		"and so does a recomputation that produced something nobody recorded")
	gs_m.free()

	var broken_wander := ReplayLog.from_json(text)
	var wander_entry := -1
	for i in broken_wander.entries.size():
		var entry: Dictionary = broken_wander.entries[i]
		if String(entry.get("kind", "")) == "brain_decision" \
				and String(entry.get("actor", "")) == SimWorld.ACTOR_CHICKEN:
			wander_entry = i
			break
	_assert(wander_entry >= 0, "the replay records a hen wander decision even when it emits no Action")
	broken_wander.entries[wander_entry]["brain_fingerprint"] = "deliberately-broken"
	var wander_world := SimWorld.new()
	var wander_gs = load("res://systems/game_state.gd").new()
	broken_wander.apply_to(wander_world, wander_gs)
	_assert(broken_wander.divergence.contains("entry %d" % wander_entry),
		"a deliberately broken hen wander fails at that decision: %s" % broken_wander.divergence)
	wander_gs.free()
	s.done()

	# --- the seed fix (the hole WI-3 filed and this closes) --------------------
	# `SimRng.stateless()` derives from the current seed, and a continued session
	# used to replay under whatever seed the verifying process happened to hold.
	# The day's crow schedule is rolled that way, so the two disagreed about the
	# birds — silently, unless the session happened to be long enough to show it.
	SimRng.reseed(24680)
	var right_crows := SimWorld.roll_crow_schedule(SimWorld.CROW_MIN_DAY + 1)
	SimRng.reseed(999999)
	var wrong_crows := SimWorld.roll_crow_schedule(SimWorld.CROW_MIN_DAY + 1)
	_assert(right_crows != wrong_crows,
		"the two seeds really do disagree about a day's crows — which is what makes this testable")

	var cont := _crow_ready_session(24680)
	cont.rebase()   # continue from an autosave, exactly as main.gd does
	cont.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	cont.tick(300)
	var cont_snap = JSON.parse_string(JSON.stringify(SaveGame.capture(cont.world, cont.gs)))
	_assert(not cont.gs.crow_schedule.is_empty(),
		"the continued day has a crow due, so the seed is load-bearing in what follows")
	_assert(cont.log.gen_seed == 24680,
		"a continued session's log carries the seed its farm was made from")
	_assert(int(cont_snap["world"]["gen_seed"]) == 24680,
		"and so does the save, which is where a reload gets it")

	# The verifier is a different process holding a completely different seed.
	SimRng.reseed(13579)
	var cont_report := SaveGame.replay_report(cont.log, cont_snap)
	_assert(cont_report["matched"],
		"a session continued from a save replays under a foreign ambient seed and still matches %s"
			% cont_report["divergence"])

	# ...and the control: the same log with its seed removed does not, which is
	# the hole itself, demonstrated rather than described.
	var seedless := ReplayLog.from_json(cont.log.to_json())
	seedless.gen_seed = 0
	SimRng.reseed(13579)
	_assert(not SaveGame.replay_matches(seedless, cont_snap),
		"and without the seed it does not — that was the hole")
	cont.done()

	# --- v1 logs are read as v1, and nothing new happens to them ---------------
	# (5,9) rather than (5,2): a v1 log regenerates its world before re-applying,
	# and since T-32 a till aimed inside the fenced yard is refused there. What
	# this asserts is that the *legacy path* still applies an action, so the action
	# is aimed at ground that still takes one.
	var legacy_text := JSON.stringify({ "gen_seed": 99, "base_save": {}, "build_id": "old" }) \
		+ "\n" + JSON.stringify({ "verb": "till", "target": [5, 9], "actor": "player" })
	var legacy := ReplayLog.from_json(legacy_text)
	_assert(legacy.version == 1, "a header with no version field is a v1 log")
	var w_v1 := SimWorld.new()
	var gs_v1 = load("res://systems/game_state.gd").new()
	legacy.apply_to(w_v1, gs_v1)
	_assert(w_v1.get_tile(5, 9).state == "tilled", "and it still applies, action for action")
	_assert(w_v1.clock.tick == 0 and legacy.divergence == "",
		"advancing no clock and recomputing nothing — the legacy path, untouched")
	gs_v1.free()

	# The real thing: every recorded session in playtests/ replays as exactly the
	# log SHELF says it is — format and verdict both. A folder missing from SHELF
	# is skipped here and reported once, by the autosave block above.
	var dir := DirAccess.open("res://playtests")
	_assert(dir != null, "the playtests fixtures directory is readable")
	var shelf_build_note := SaveGame.build_note({
		"state": { "build_id": "recorded-build" },
	}, "checking-build")
	_assert(shelf_build_note == "recorded under recorded-build, checked under checking-build",
		"the shelf message names both its recorded and checking builds")
	var checked := 0
	for name in dir.get_directories():
		var path := "res://playtests/%s/session_replay.json" % name
		if not FileAccess.file_exists(path):
			continue
		var fixture := ReplayLog.load_from(path)
		if fixture == null:
			continue
		if not SHELF.has(name):
			continue  # unclassified: reported once by the autosave block, not failed
		checked += 1
		var expect: Dictionary = SHELF[name]
		_assert_quiet(fixture.version == int(expect["format"]),
			"%s is the v%d log the shelf says it is" % [name, int(expect["format"])])
		var wf := SimWorld.new()
		var gsf = load("res://systems/game_state.gd").new()
		fixture.apply_to(wf, gsf)
		if int(expect["format"]) == 1:
			_assert_quiet(fixture.divergence == "",
				"%s takes the legacy path and asserts nothing about brains" % name)
		# (a v2 fixture may report divergence — the tenth session is a Continue on
		# a pre-T-32 base, and its recomputation disagreeing with its recording is
		# the cross-provenance speaking, not a bug.)
		var is_match := SaveGame.replay_matches(fixture, SaveGame.load_dict(
				"res://playtests/%s/autosave.json" % name))
		var fixture_save := SaveGame.load_dict("res://playtests/%s/autosave.json" % name)
		print("      %s: %s" % [name, SaveGame.build_note(fixture_save)])
		_assert_quiet(is_match == (String(expect["verdict"]) == "match"),
			"%s replays to the '%s' verdict the shelf records" % [name, expect["verdict"]])
		gsf.free()
	_flush_quiet("every recorded session in playtests/ replays as the log the shelf says it is (%d)"
		% checked)

	# **Which of them still reproduce their own farm, counted.** This used to be a
	# single quiet check on the logs with *no* Actions in them — the one case a
	# worldgen change cannot touch — which meant the interesting half of the shelf
	# was replayed and then nobody looked at the answer. Written down at T-32,
	# because a worldgen change is exactly when somebody should.
	#
	# **1 matches, 9 do not** (2026-09-02, after the shelf was deduplicated: it was
	# "3 match, 5 do not" across 8 recorded sessions, then briefly 4 across 10).
	# **T-32 did not move any of it**, measured on both sides of the change.
	#
	# The one that matches is an empty log — 2026-08-30 21:52, a base save and no
	# Actions — so it reproduces itself whatever the generator does. Read it as a
	# specimen of that case, not as evidence of anything. The nine that do not are
	# the sessions with real play in them, and they were already failing before
	# T-32: M1.5's parcel rebuild is what invalidated them, exactly as
	# `docs/M1_5_PLAN.md` §1 said it would. T-32 adds a second independent reason to
	# the same files (every one of them tills tiles inside the fenced yard, which is
	# not tillable ground any more) and changes nothing about the count.
	#
	# **The count fell because two of the old "matches" were not matches of
	# anything.** 2026-09-02_211138 and _214427 were argued here to be the first
	# interesting entries — "a real play session, 700-odd entries, not an empty
	# log". They held one entry each, on a base save. The 700-odd belonged to their
	# *trace*, which the device had never cleared and which really was a copy of
	# 233943's play; the replay beside it recorded nothing. So they were the hollow
	# case in the paragraph above, mistaken for its opposite. Both are gone.
	#
	# The lesson is cheap to state and was expensive to spot: **a session's trace
	# and its replay can disagree about whether anything happened**, and the replay
	# is the one that decides whether a "match" means a thing.
	#
	# So this is not a regression bar; it is a **ledger**. The determinism proof is
	# the unit replay tests plus a fresh robot session, never an old session
	# replayed across a worldgen change. What pinning the numbers buys is that the
	# next change to move them has to come here and say which, and why.
	#
	# Worth knowing and not fixable from here: `build_status()` does **not** flag
	# any of this. The stamp is a `git describe`, and a worldgen change ships under
	# the same one until the next tag — so a file's provenance line can read
	# "matches this build" while the world underneath it has moved. That is what
	# `tools/verify_replay.gd` did to the last local human session at T-32: MATCH
	# before, MISMATCH after, with no cross-build warning to explain it.
	_assert(checked == SHELF.size(),
		"there are %d recorded sessions in playtests/ (%d)" % [SHELF.size(), checked])

	# --- free-walk entries: recorded, applied, compared (M2.5 WI-6) ------------
	# §3.3's other half, and the switch WI-5 armed and left off. A crossing writes
	# her registry entry and records an event; a replay applies the event back; and
	# `capture_canonical` — which no longer excludes her — is what says the two
	# agree.
	var walked := LiveSession.new(31415)
	walked.act({ "verb": "till", "target": Vector2i(5, 2), "actor": "player" })
	walked.walk("begin", "left", Vector2i(5, 2))
	walked.walk("step", "left", Vector2i(4, 2))
	walked.walk("turn", "up", Vector2i(4, 1))
	walked.walk("stop", "up", Vector2i(4, 1))
	walked.act({ "verb": "plant", "target": Vector2i(5, 2), "seed_type": "wheat", "actor": "player" })
	var w_w := SimWorld.new()
	var gs_w = load("res://systems/game_state.gd").new()
	var round_tripped := ReplayLog.from_json(walked.log.to_json())
	_assert(ReplayLog.is_walk(round_tripped.entries[1]),
		"a free-walk event survives the file as a walk, not as an Action")
	_assert(walked.world.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(4, 1),
		"a recorded crossing is also a move: the registry holds the tile she reached")
	round_tripped.apply_to(w_w, gs_w)
	_assert(w_w.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(4, 1)
			and String(w_w.actor(SimWorld.ACTOR_PLAYER)["facing"]) == "up",
		"and a replay walks her there — position and facing, from the events alone")
	_assert(SaveGame.capture_canonical(walked.world, walked.gs)
			== SaveGame.capture_canonical(w_w, gs_w),
		"so the session and its replay compare equal with the player's tile IN the comparison")
	_assert(round_tripped.divergence == "",
		"without the net mistaking it for a brain that failed to recompute")

	# ...and the comparison bites. A log with her walk stripped out — which is
	# exactly what every log written before this WI is — replays into a farm where
	# she never left the spawn tile, and now that is a failure rather than a thing
	# nobody was looking at.
	var lost := ReplayLog.from_json(walked.log.to_json())
	for i in range(lost.entries.size() - 1, -1, -1):
		if ReplayLog.is_walk(lost.entries[i]):
			lost.entries.remove_at(i)
	var w_lost := SimWorld.new()
	var gs_lost = load("res://systems/game_state.gd").new()
	lost.apply_to(w_lost, gs_lost)
	_assert(SaveGame.capture_canonical(walked.world, walked.gs)
			!= SaveGame.capture_canonical(w_lost, gs_lost),
		"and a dropped walk event is a failed replay, which is what makes recording one worth it")
	gs_lost.free()
	gs_w.free()
	walked.done()


# --- the ant pair: scouts mark, foragers follow (M2.5 WI-8a/8b) ---------------
#
# A farm arranged so a raid is legible: a clear field with a short row of wheat
# in it, and nothing else in the way. The nest is placed by the test rather than
# by `AntScoutBrain.nest_tile`, because *where* nests belong is `[Designer]`
# Q-18 and a test that depended on today's placeholder answer would break the day
# it is ruled.
func test_ants() -> void:
	print("\n--- The ant pair: scouts mark, foragers follow (M2.5 WI-8a/8b, P-10) Tests ---")

	# --- the two rows (checklist §8.B) ----------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.ANT_SCOUT) and SpeciesDefs.has(SpeciesDefs.ANT_FORAGER),
		"the table has both ants")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.ANT_SCOUT) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.ANT_FORAGER) == SpeciesDefs.GROUND,
		"both walk, and say so in the one field that decides it (WI-4)")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.ANT_SCOUT), SimClock.tiles_per_tick(10.0)),
		"the scout's 10 px/s converts, like every other row")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.ANT_FORAGER), SimClock.tiles_per_tick(8.0)),
		"and a laden forager's 8 px/s")
	# Ground rule 1, on the pair that most obviously could have broken it.
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.ANT_SCOUT).is_empty(),
		"the scout has no verbs at all — it walks and it marks, and neither is an Action")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.ANT_FORAGER) == ["eat_crop"],
		"and the forager's one verb is the crow's, reused (P-9: no verb the player lacks)")
	_assert(Brains.of_species(SpeciesDefs.ANT_SCOUT) is AntScoutBrain
			and Brains.of_species(SpeciesDefs.ANT_FORAGER) is AntForagerBrain,
		"both rows bind to a brain")
	_assert(SpeciesDefs.is_stompable(SpeciesDefs.ANT_SCOUT)
			and SpeciesDefs.is_stompable(SpeciesDefs.ANT_FORAGER),
		"both answer a boot")
	_assert(not SpeciesDefs.is_stompable(SpeciesDefs.CHICKEN)
			and not SpeciesDefs.is_stompable(SpeciesDefs.PLAYER),
		"and nothing else does — stomping is opt-in per row, so the hen can never be tapped away")
	# The census, kept as a census: which species answer a boot is a design fact
	# and it should change only on purpose. It grew from two to four at M2.5
	# WI-8d/8e — the crawling things are answerable and the mammals and the birds
	# are not, and each of the two newcomers qualifies its own answer (a mole only
	# while it is above ground, a worm on any tile of itself).
	var boots: Array[String] = []
	for id in SpeciesDefs.ids():
		if SpeciesDefs.is_stompable(String(id)):
			boots.append(String(id))
	boots.sort()
	_assert(str(boots) == str([SpeciesDefs.ANT_FORAGER, SpeciesDefs.ANT_SCOUT,
			SpeciesDefs.MOLE, SpeciesDefs.WORM]),
		"which is exactly the two ants, the mole and the worm: %s" % str(boots))

	# --- nothing spawns in the live game (plan §4) ----------------------------
	_assert(SimWorld.ANT_RAIDS_PER_DAY == 0,
		"no raid is scheduled in a shipping build — the debut is content sequencing, not this WI")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_ant_schedule(day).is_empty(),
			"day %d schedules no raid" % day)
	_flush_quiet("and no day of any real game rolls one")
	var quiet := _crow_ready_session(31337)
	_work_until_actions(quiet, 40)
	quiet.tick(1200)
	_assert(not AntScoutBrain.raid_is_live(quiet.world),
		"a whole worked day on an ordinary farm never contains an ant")
	quiet.done()

	# --- but the arrival path is real, and rides the crow's own clock ---------
	_assert(SimWorld.may_start_raid(SimWorld.ANT_MIN_DAY, SimWorld.ANT_MIN_PLANTED),
		"a raid may start once there is a farm worth raiding")
	_assert(not SimWorld.may_start_raid(SimWorld.ANT_MIN_DAY - 1, SimWorld.ANT_MIN_PLANTED),
		"not before the day floor")
	_assert(not SimWorld.may_start_raid(SimWorld.ANT_MIN_DAY, SimWorld.ANT_MIN_PLANTED - 1),
		"and not onto a farm with almost nothing growing on it (the crow's T-2 mercy, for a column)")
	var booked := _ant_session(7)
	booked.gs.day = 8
	booked.gs.takeover_day = 1
	var appointment: Array[int] = [3]
	booked.gs.ant_schedule = appointment
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SimWorld.ACTOR_ANT_SCOUT),
		"a booked raid arrives when the day's *action* clock reaches it (T-20's clock, for ants)")
	_assert(booked.gs.ant_schedule.is_empty(),
		"and the appointment is spent, whether the raid comes to anything or not")
	_assert(AntScoutBrain.send(booked.world, booked.gs, 9) == "",
		"a second raid is refused while the first is still on the farm")
	booked.done()

	# --- the scout: a trail is written by walking home ------------------------
	var raid := _ant_session(4242)
	# Her pouch is emptied of wheat first, so what it holds at the end of the
	# visit is exactly what the pest handed her — which is nothing (S-18/S-19/S-20 put her
	# seed and her harvest in one place, and a starting handful would mask this).
	raid.gs.pouch["wheat"] = 0
	_release_scout(raid)
	_assert(raid.world.scent.cell_count(Scent.TRAIL) == 0,
		"a searching scout marks nothing — the trail is the *way back*, not the walk out")
	_assert(_tick_until_homing(raid), "it finds the wheat and sets off home")
	var found := Vector2i(int(raid.world.actor(SimWorld.ACTOR_ANT_SCOUT)["extra"]["tgt_x"]),
		int(raid.world.actor(SimWorld.ACTOR_ANT_SCOUT)["extra"]["tgt_y"]))
	_assert(raid.world.scent.read(Scent.TRAIL, found, raid.world.clock.tick) > 0.0,
		"the first mark is on the food itself, so a trail's far end is dinner")
	_tick_until_raid_over(raid)

	var trail := _trail_tiles(raid.world)
	_assert(trail.size() >= 5, "the finished trail is a run of tiles (%d)" % trail.size())
	_assert(trail.has(ANT_NEST) and trail.has(found),
		"running from the nest to the crop it found")
	for t in trail:
		var joined := false
		for d in Movement.DIRS:
			if trail.has(t + d):
				joined = true
		_assert_quiet(joined, "%s has a neighbour on the trail" % t)
	_flush_quiet("and it is a corridor, not a scatter — every marked tile touches another")
	# The gradient points *home*, because home was written last. That is exactly
	# why a follower has to exclude the tile it came from (see `Scent.strongest_neighbour`).
	_assert(int(raid.world.scent.cell(Scent.TRAIL, ANT_NEST)["tick"])
			> int(raid.world.scent.cell(Scent.TRAIL, found)["tick"]),
		"the nest end was written last, so the field's slope runs the wrong way for a follower")

	# --- the column: it forms, it eats one each, it goes home -----------------
	_assert(raid.gs.pouch.get("wheat", 0) == 0,
		"nothing the ants took reached the player's basket — a raid is a loss, not a harvest")
	_assert(raid.world.count_planted() <= 4 - 1, "the row lost plants to the column")
	_assert(4 - raid.world.count_planted() <= SimWorld.ANT_COLUMN_SIZE,
		"and at most one per forager, which is the whole cost of a raid")
	_assert(not AntScoutBrain.raid_is_live(raid.world),
		"and when the column has carried its crops home there are no ants left")

	# Success reinforces: a tile a laden ant walked over holds more than the one
	# deposit the scout left on it (`design/04` §1).
	var strongest := 0.0
	for t in trail:
		strongest = maxf(strongest, raid.world.scent.read(Scent.TRAIL, t, raid.world.clock.tick))
	_assert(strongest > AntScoutBrain.DEPOSIT,
		"a route that fed somebody is stronger than the scout left it (%.1f > %.1f)"
			% [strongest, AntScoutBrain.DEPOSIT])

	# ...and decay erases. No writer left, so the field is a closed form of its
	# own past: read it far enough into the future and the trail is simply gone.
	var far_off := raid.world.clock.tick + int(20.0 * Scent.half_life_ticks(Scent.TRAIL))
	var still_there := 0
	for t in trail:
		if raid.world.scent.read(Scent.TRAIL, t, far_off) > 0.0:
			still_there += 1
	_assert(still_there == 0,
		"and a trail nobody reinforces fades to nothing (P-10's third clause, the difficulty dial)")
	raid.done()

	# --- counterplay 1: stomp the scout, and no column ever forms -------------
	var stomped := _ant_session(4242)
	_release_scout(stomped)
	_assert(_tick_until_homing(stomped), "a second scout finds the same row")
	var standing := stomped.world.actor_pos(SimWorld.ACTOR_ANT_SCOUT)
	var ground_was := String(stomped.world.get_tile(standing.x, standing.y).get("state", ""))
	var planted_was := stomped.world.count_planted()
	_assert(stomped.world.stompable_at(standing), "the sim knows there is something to stomp there")
	_assert(not stomped.world.stompable_at(stomped.world.actor_pos(SimWorld.ACTOR_CHICKEN))
			or stomped.world.actor_pos(SimWorld.ACTOR_CHICKEN) == standing,
		"and the hen is not something to stomp")
	var boot := stomped.act({ "verb": "clear_weed", "target": standing, "actor": "player" })
	_assert(boot.get("ok", false) and boot.get("stomped", false),
		"the player's existing clear-class verb answers it — no new verb, no new UI")
	_assert(not stomped.world.has_actor(SimWorld.ACTOR_ANT_SCOUT), "and the scout is gone")
	_assert(String(stomped.world.get_tile(standing.x, standing.y).get("state", "")) == ground_was,
		"leaving the ground exactly as it was — an ant on a row of wheat costs her the ant, not the wheat")
	_assert(int(stomped.gs.clear_counts.get("clear_weed", 0)) == 0,
		"and it is not evidence of clearing an obstacle (T-10/Q-46 count weeds, not ants)")
	_tick_until_raid_over(stomped)
	stomped.tick(4000)
	_assert(stomped.world.actors_of_species(SpeciesDefs.ANT_FORAGER).is_empty(),
		"**no column forms**: the trail never completed, so nothing was ever summoned")
	_assert(stomped.world.count_planted() == planted_was,
		"and the row the scout found keeps every plant")
	stomped.done()

	# --- counterplay 2: wash a trail tile, and the column disperses -----------
	var washed := _ant_session(4242)
	_release_scout(washed)
	_assert(_tick_until_column(washed), "a third raid gets its column out of the nest")
	_assert(washed.world.actors_of_species(SpeciesDefs.ANT_FORAGER).size() == SimWorld.ANT_COLUMN_SIZE,
		"of %d, which is what a completed trail summons" % SimWorld.ANT_COLUMN_SIZE)
	var planted_at_wash := washed.world.count_planted()
	var hole := Vector2i(ANT_NEST.x + 3, ANT_NEST.y)
	_assert(washed.world.scent.read(Scent.TRAIL, hole, washed.world.clock.tick) > 0.0,
		"and there is trail on the tile about to be watered")
	var splash := washed.act({ "verb": "water", "target": hole, "actor": "player" })
	_assert(splash.get("ok", false), "she waters it — the verb she already waters crops with")
	_assert(washed.world.scent.read(Scent.TRAIL, hole, washed.world.clock.tick) == 0.0,
		"which leaves a hole in the trail rather than a weak link (WI-7's full-cell erase)")
	_tick_until_raid_over(washed)
	_assert(washed.world.actors_of_species(SpeciesDefs.ANT_FORAGER).is_empty(),
		"**the column disperses**: an ant that has lost the trail has lost everything it knew")
	_assert(washed.world.count_planted() == planted_at_wash,
		"and the crops on the far side of the hole are never reached")
	washed.done()

	# A forager is stompable too — the same tap, on a different ant.
	var underfoot := _ant_session(4242)
	_release_scout(underfoot)
	_assert(_tick_until_column(underfoot), "a fourth raid forms its column")
	var ant0 := underfoot.world.actors_of_species(SpeciesDefs.ANT_FORAGER)[0]
	var at := underfoot.world.actor_pos(ant0)
	underfoot.act({ "verb": "clear_weed", "target": at, "actor": "player" })
	_assert(not underfoot.world.has_actor(ant0), "one stamp, one fewer ant in the column")
	_tick_until_raid_over(underfoot)
	underfoot.done()

	# --- the daily-loss identity, extended to the new mouths (plan §4) --------
	# T-15/T-20 bound a day's losses by the birds it scheduled. The formula now
	# reads: **crows scheduled + raids scheduled x column size**, because a
	# forager eats exactly once in its life and then leaves.
	var bound := SimWorld.CROWS_PER_DAY + SimWorld.ANT_RAIDS_PER_DAY * SimWorld.ANT_COLUMN_SIZE
	_assert(bound == SimWorld.CROWS_PER_DAY,
		"in a shipping build the ants add nothing to it: no raid is ever scheduled")
	var budget := _ant_session(77)
	var dawn := budget.world.count_planted()
	_release_scout(budget)
	_tick_until_raid_over(budget)
	budget.tick(2000)
	_assert(dawn - budget.world.count_planted() <= SimWorld.ANT_COLUMN_SIZE,
		"and a forced raid costs at most one crop per forager (%d of %d)"
			% [dawn - budget.world.count_planted(), SimWorld.ANT_COLUMN_SIZE])
	budget.done()

	# --- two columns may coexist (found in the zoo, 2026-09-01) ---------------
	# On a real farm `send` keeps raids serial, so a column's ids were fixed at
	# 0..2 — and the zoo, which parks that refusal to run two raids at once,
	# showed the cost: a second completed trail's column landed on the first's
	# ids and `spawn_actor` silently replaced three live ants mid-march. Ids now
	# count past anybody still registered.
	var two := SimWorld.new()
	SimRng.reseed(11)
	two.generate()
	var col_a := AntForagerBrain.raise_column(two, "", Vector2i(4, 4), 0)
	var col_b := AntForagerBrain.raise_column(two, "", Vector2i(12, 9), 0)
	_assert(col_a.size() == SimWorld.ANT_COLUMN_SIZE
			and col_b.size() == SimWorld.ANT_COLUMN_SIZE,
		"two trails raise two full columns")
	for id in col_b:
		_assert_quiet(not col_a.has(id), "%s is not an id the first column holds" % id)
	_flush_quiet("with no id shared between them")
	for id in col_a:
		_assert_quiet(two.actor_pos(String(id)) == Vector2i(4, 4),
			"%s still stands at its own nest" % id)
	_flush_quiet("and the first column's ants are untouched where they stood")
	_assert(two.actors_of_species(SpeciesDefs.ANT_FORAGER).size() == 2 * SimWorld.ANT_COLUMN_SIZE,
		"six foragers are registered, not three survivors of an overwrite")

	# --- determinism, which everything above rests on ------------------------
	var runs: Array[String] = []
	for _i in 2:
		var d := _ant_session(909)
		_release_scout(d)
		_tick_until_raid_over(d)
		d.tick(500)
		runs.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(runs[0] == runs[1],
		"the same seed raids the same farm the same way, ant for ant and tick for tick")

	# --- a save taken mid-raid, continued, and its own replay ----------------
	# The strongest statement the repo can make, and the one WI-5's handoff
	# promised would judge this brain: a session continued from a mid-raid save
	# is recorded, replayed, and the recomputation is compared **action for
	# action and tick for tick** — which for an ant means its `eat_crop` and,
	# through `capture()`, every scent cell it wrote.
	var played := _ant_session(4242)
	_release_scout(played)
	_assert(_tick_until_column(played), "a raid is under way when the game is saved")
	played.tick(120)
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	var mid_ants := AntScoutBrain.raid_is_live(played.world)
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-raid save restores")
	_assert(mid_ants and AntScoutBrain.raid_is_live(w_cont),
		"with the raid still on the farm — a column is part of a snapshot of one, unlike a bird in flight")
	SaveGame.resume_stream(mid, w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var spent := 0
	while spent < 6000 and AntScoutBrain.raid_is_live(w_cont):
		for t in w_cont.advance_ticks(25, gs_cont):
			_record_brain_step(cont_log, t)
		cont_log.mark_tick(w_cont.clock.tick)
		spent += 25
	_assert(cont_log.entries.size() > 0,
		"the continued session records the ants' Actions (%d)" % cont_log.entries.size())
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()

	# --- the gradient's one rule, in isolation -------------------------------
	# Why the follower excludes the tile it came from, stated as a test rather
	# than only as a comment: a trail laid *towards* the nest gets stronger the
	# closer to home it is, so uphill is backwards.
	var field := Scent.new()
	field.deposit(Scent.TRAIL, Vector2i(4, 4), 10.0, 0)
	field.deposit(Scent.TRAIL, Vector2i(5, 4), 10.0, 100)
	field.deposit(Scent.TRAIL, Vector2i(6, 4), 10.0, 200)
	_assert(field.strongest_neighbour(Scent.TRAIL, Vector2i(5, 4), 300) == Vector2i(6, 4),
		"the strongest neighbour is the one written last — the way the scout came")
	_assert(field.strongest_neighbour(Scent.TRAIL, Vector2i(5, 4), 300, Vector2i(6, 4)) == Vector2i(4, 4),
		"and excluding it turns a follower round to face the food")
	_assert(field.strongest_neighbour(Scent.TRAIL, Vector2i(4, 4), 300, Vector2i(5, 4)) == Vector2i(4, 4),
		"at the end of the trail there is nothing left, which is what 'disperse' means")

	# --- the intent layer: a tap on a critter (M2.5 WI-8a) -------------------
	var FarmScript = load("res://world/farm.gd")
	var tap_farm = FarmScript.new()
	tap_farm.tiles.clear()
	tap_farm.objects.clear()
	for ty in SimWorld.MAP_HEIGHT:
		tap_farm.tiles.append([])
		tap_farm.objects.append([])
		for tx in SimWorld.MAP_WIDTH:
			tap_farm.objects[ty].append("")
			tap_farm.tiles[ty].append({ "state": "growing", "crop_type": "wheat",
				"growth_stage": 1, "watered_today": true })
	GameState.pouch = { "wheat": 1 }
	GameState.energy = Tools.DAY_UNITS  # T-29: a full day, so the stomp is affordable
	GameState.watering_can_charges = 8
	var on_a_crop := Vector2i(6, 6)
	_assert(ActionRouter.resolve(tap_farm, GameState, on_a_crop, Vector2i(6, 5)).is_empty(),
		"a watered crop answers nothing, which is the tile's own state today")
	tap_farm.sim.spawn_actor(SimWorld.ACTOR_ANT_SCOUT, SpeciesDefs.ANT_SCOUT, on_a_crop, {})
	var tapped: Dictionary = ActionRouter.resolve(tap_farm, GameState, on_a_crop, Vector2i(6, 5))
	_assert(String(tapped.get("action", "")) == "clear_weed",
		"an ant standing on it answers with the hands — the stomp, in the intent layer")
	_assert(int(tapped.get("tool_idx", -1)) == 0 and bool(tapped.get("walk_to", false)),
		"with her hands, and she walks over to do it")
	_assert(ActionRouter.resolve(tap_farm, GameState, on_a_crop, Vector2i(0, 0)).is_empty(),
		"a far tap is still pure movement — she goes there first, exactly as for a workable tile")
	tap_farm.free()


# --- the tier-1 visitors: two mouths and one bird (M2.5 WI-8c/8f/8g) ----------
#
# A farm arranged so a visit is legible: a wide cleared field with a short row of
# wheat in it, nothing else in the way, and the farmer parked in the far corner
# so that her `spook_radius` is not quietly part of every scenario. The player's
# tile is written directly rather than walked, because these fixtures arrange a
# farm rather than play one — the one place it matters (the replay test at the
# bottom) records her crossings properly, which is the whole point of that test.
func test_grazers() -> void:
	print("\n--- The rabbit and the kangaroo: one brain, two rows (M2.5 WI-8c/8f) Tests ---")

	# --- the two rows (checklist §8.B) ----------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.RABBIT) and SpeciesDefs.has(SpeciesDefs.KANGAROO),
		"the table has both grazers")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.RABBIT) == ["eat_crop"]
			and SpeciesDefs.verbs_of(SpeciesDefs.KANGAROO) == ["eat_crop"],
		"each has one verb and it is the crow's, reused (P-9: no verb the player lacks)")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.RABBIT), SimClock.tiles_per_tick(30.0)),
		"the rabbit's 30 px/s converts, like every other row")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.KANGAROO), SimClock.tiles_per_tick(45.0)),
		"and the kangaroo's 45 px/s")

	# **The claim WI-8f exists to make**, stated three ways before it is played:
	# same brain id, same brain *object*, and exactly one field of difference.
	_assert(SpeciesDefs.brain_of(SpeciesDefs.RABBIT) == SpeciesDefs.brain_of(SpeciesDefs.KANGAROO),
		"both rows name the same brain")
	_assert(Brains.of_species(SpeciesDefs.RABBIT) == Brains.of_species(SpeciesDefs.KANGAROO),
		"...which is literally the same object — there is no kangaroo code anywhere")
	_assert(Brains.of_species(SpeciesDefs.RABBIT) is GrazerBrain, "and it is the grazer's")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.RABBIT) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.KANGAROO) == SpeciesDefs.HOP,
		"the one field that differs is the movement capability (WI-4, plan §3.4)")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.RABBIT)
			== SpeciesDefs.senses_of(SpeciesDefs.KANGAROO),
		"even their senses are the same table entry — the fence is not a sense")
	_assert(not SpeciesDefs.is_stompable(SpeciesDefs.RABBIT)
			and not SpeciesDefs.is_stompable(SpeciesDefs.KANGAROO),
		"and neither answers a boot: a rabbit's counterplay is her footsteps, not a tap")

	# --- nothing spawns in the live game (plan §4) ----------------------------
	_assert(SimWorld.RABBIT_VISITS_PER_DAY == 0 and SimWorld.KANGAROO_VISITS_PER_DAY == 0,
		"no visit is scheduled in a shipping build — the debut is content sequencing")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.RABBIT, day).is_empty(),
			"day %d schedules no rabbit" % day)
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.KANGAROO, day).is_empty(),
			"day %d schedules no kangaroo" % day)
	_flush_quiet("and no day of any real game rolls one")
	var quiet := _crow_ready_session(31337)
	_work_until_actions(quiet, 40)
	quiet.tick(1200)
	_assert(quiet.world.actors_of_species(SpeciesDefs.RABBIT).is_empty()
			and quiet.world.actors_of_species(SpeciesDefs.KANGAROO).is_empty(),
		"a whole worked day on an ordinary farm never contains one")
	quiet.done()

	# --- but the arrival path is real, and rides the crow's own clock ---------
	_assert(SimWorld.may_visit(SpeciesDefs.RABBIT, 4, 3),
		"a rabbit may come once there is a farm worth visiting")
	_assert(not SimWorld.may_visit(SpeciesDefs.RABBIT, 3, 3), "not before the day floor")
	_assert(not SimWorld.may_visit(SpeciesDefs.RABBIT, 4, 2),
		"and not onto a farm with almost nothing growing on it (the crow's T-2 mercy)")
	_assert(not SimWorld.may_visit("no_such_species", 99, 99),
		"a species with no row in the visitors' table never arrives at all")

	var booked := _meadow_session(7)
	booked.gs.day = 9
	booked.gs.takeover_day = 1
	booked.gs.visitor_schedules = { SpeciesDefs.RABBIT: [3] }
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SpeciesDefs.RABBIT),
		"a booked visit arrives when the day's *action* clock reaches it (T-20's clock)")
	_assert(booked.gs.visitor_schedules.get(SpeciesDefs.RABBIT, []).is_empty(),
		"and the appointment is spent, whether the visit comes to anything or not")
	var arrived_at := booked.world.actor_pos(SpeciesDefs.RABBIT)
	# The edge of its **page**, since the grid became two of them (2026-09-06).
	# The farm's own bottom row is still the hole in the hedge it came through;
	# what changed is that `MAP_HEIGHT - 2` stopped naming it.
	var arrived_y := arrived_at.y % SimWorld.PAGE_ROWS
	_assert(arrived_at.x <= 1 or arrived_y <= 1
			or arrived_at.x >= SimWorld.MAP_WIDTH - 2 or arrived_y >= SimWorld.PAGE_ROWS - 2,
		"coming in at the edge of the map, which is also the way it will leave %s" % arrived_at)
	_assert(Brains.of_species(SpeciesDefs.RABBIT).arrive(
			booked.world, booked.gs, SpeciesDefs.RABBIT, 9) == "",
		"a second rabbit is refused while the first is still on the farm")
	booked.done()

	# --- the mechanic: it finds the row, takes its fill, and leaves -----------
	var visit := _meadow_session(4242)
	# Her pouch is emptied of wheat first, so what it holds at the end of the
	# visit is exactly what the pest handed her — which is nothing (S-18/S-19/S-20 put her
	# seed and her harvest in one place, and a starting handful would mask this).
	visit.gs.pouch["wheat"] = 0
	var dawn := visit.world.count_planted()
	_release_grazer(visit, SpeciesDefs.RABBIT, Vector2i(5, 9))
	_assert(_tick_until_gone(visit, SpeciesDefs.RABBIT),
		"a rabbit put in a field of wheat eats and goes")
	_assert(dawn - visit.world.count_planted() == SimWorld.GRAZER_BITES,
		"taking exactly its fill — %d bites, which is what bounds a visit"
			% SimWorld.GRAZER_BITES)
	_assert(visit.gs.pouch.get("wheat", 0) == 0,
		"and nothing it took reached the player's basket: a visit is a loss, not a harvest")
	visit.done()

	# --- the fright: F-7b's sense, alive (plan §4's criterion for 8c) ---------
	#
	# A bare meadow, so nothing but the player is on its mind. It flees **inside**
	# the radius and resumes **outside** it, which is the criterion in both halves
	# — the second half is why this is a scare and not a despawn.
	var scare := _meadow_session(77, false)
	_release_grazer(scare, SpeciesDefs.RABBIT, Vector2i(12, 9))
	scare.tick(60)
	var settled := scare.world.actor_pos(SpeciesDefs.RABBIT)
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) != GrazerBrain.STATE_FLEE,
		"with the farmer across the farm, a rabbit is not running from anything")
	var radius := float(SpeciesDefs.senses_of(SpeciesDefs.PLAYER)["spook_radius"])
	scare.world.set_actor_pos(SimWorld.ACTOR_PLAYER, settled + Vector2i(1, 0))
	_assert(scare.world.spook_source_near(settled) == SimWorld.ACTOR_PLAYER,
		"the sim can now answer 'who is frightening, and are they near' — F-7b, alive")
	_assert(scare.world.spook_source_near(MEADOW_FAR_CORNER) == "",
		"...and answers nobody where nobody is")
	scare.tick(3)
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) == GrazerBrain.STATE_FLEE,
		"**she walks up and it bolts** — no tap, no tool, no verb at all")
	scare.tick(400)
	var bolted := scare.world.actor_pos(SpeciesDefs.RABBIT)
	var away := Vector2(bolted - scare.world.actor_pos(SimWorld.ACTOR_PLAYER)).length()
	_assert(away > radius,
		"it runs clear of her radius (%.1f tiles, radius %.1f)" % [away, radius])
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) != GrazerBrain.STATE_FLEE,
		"**and stops running once it is clear** — a scare, not a despawn")
	# ...and it settles back into what it was doing rather than standing there.
	scare.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	scare.tick(100)
	_assert(_state_of(scare.world, SpeciesDefs.RABBIT) == GrazerBrain.STATE_GRAZE,
		"and when she has gone it goes back to grazing (the criterion's second half)")
	_assert(scare.world.has_actor(SpeciesDefs.RABBIT),
		"still on the farm the whole time — she moved it, she did not delete it")
	scare.done()

	# The crow's row asked the same question first and its answer is unchanged:
	# the sense is opt-in per row, so the hen is never startled by a farmer walking
	# past her.
	_assert(SpeciesDefs.senses_of(SpeciesDefs.RABBIT).get("flees_spook_radius", false),
		"the rabbit notices, because its row says it does")
	_assert(not SpeciesDefs.senses_of(SpeciesDefs.CHICKEN).get("flees_spook_radius", false),
		"and the hen does not, because hers does not")

	# --- ...and whether the fright *ends* the visit is the row's answer -------
	#
	# `[Designer]` Q-63, ruled 2026-08-31: the *shape* of the behaviour is this
	# brain's and the *value* is the species row's (`ARCHITECTURE.md`, "Where a
	# behaviour lives"). Both shipping grazers are ruled `false` — flee-and-return,
	# the behaviour asserted immediately above — so the ruling changed nothing a
	# player could see, and the true path deliberately has no shipping row. It is
	# played through the test-row seam instead, for the same reason the movement
	# engine keeps one: a row in the table is a claim about the game.
	_assert(not SpeciesDefs.fright_ends_visit(SpeciesDefs.RABBIT)
			and not SpeciesDefs.fright_ends_visit(SpeciesDefs.KANGAROO),
		"neither grazer's visit is ended by a fright, which is the behaviour it always had")
	_assert(not SpeciesDefs.fright_ends_visit("no_such_species"),
		"and a row that never mentions the field means the same thing: a fright is a pause")

	SpeciesDefs.define_test_row("test_bolter", {
		"name": "Test Bolter",
		"brain": "graze",  # the rabbit's brain, unmodified — that is the claim
		"verbs": ["eat_crop"],
		"speed": SpeciesDefs.speed_of(SpeciesDefs.RABBIT),
		"movement": SpeciesDefs.movement_of(SpeciesDefs.RABBIT),
		"senses": SpeciesDefs.senses_of(SpeciesDefs.RABBIT),
		"persistent": true,
		"fright_ends_visit": true,
	})
	# The same farm, the same seed, the same mouthful and the same fright: the two
	# runs differ in one field of one row and in nothing else.
	# Seed 99 rather than the 4242 this pair ran on until 2026-09-06: the world it
	# runs in is the composed one now, so the same draws put the rabbit in a
	# different corner of the same meadow, and on 4242 it wandered past its
	# patience before finding a second mouthful. The claim is unchanged and so is
	# the fixture — one number moved, and it is the number that says "some farm".
	var paused := _bite_then_scare(99, SpeciesDefs.RABBIT)
	var ended := _bite_then_scare(99, "test_bolter")
	_assert(paused["bit"] and paused["bolted"] and ended["bit"] and ended["bolted"],
		"both animals take a bite, and both bolt when she walks up — the fright is the same fright")
	_assert(paused["lost"] == SimWorld.GRAZER_BITES,
		"**the rabbit comes back for the rest of its fill**: her fright bought a pause (%d crops)"
			% paused["lost"])
	_assert(ended["lost"] == 1,
		"**a `fright_ends_visit` row does not**: one bite, and the scare ended the visit (%d crops)"
			% ended["lost"])
	_assert(paused["gone"] and ended["gone"],
		"and both leave under their own steam — what differs is when, not whether")
	SpeciesDefs.forget_test_rows()
	_assert(not SpeciesDefs.has("test_bolter"),
		"the test-row seam leaves nothing behind, exactly as the movement engine's does")
	_assert(SpeciesDefs.ids().size() == SpeciesDefs.ROWS.size(),
		"and the shipping species table is untouched by it")

	# --- the kangaroo: exactly the barrier class, and nothing else -----------
	#
	# The criterion, played rather than asserted: a fence-enclosed crop is
	# reachable by the hopper and not by the walker, **with the same brain in
	# both**. The only line that differs between these two scenarios is the
	# species name.
	var pen_modes := _meadow_session(11, false)
	_fence_pen(pen_modes.world)
	var outside := Vector2i(14, 10)
	_assert(Movement.path(pen_modes.world, SpeciesDefs.HOP, outside, PEN_CROP).size() > 0,
		"a hopper has a route into a fenced pen")
	_assert(Movement.path(pen_modes.world, SpeciesDefs.GROUND, outside, PEN_CROP).is_empty(),
		"and a walker has none — the barrier class is the whole difference (WI-4)")
	pen_modes.done()

	var hopper := _meadow_session(11, false)
	_fence_pen(hopper.world)
	_release_grazer(hopper, SpeciesDefs.KANGAROO, outside)
	_tick_until_gone(hopper, SpeciesDefs.KANGAROO)
	_assert(hopper.world.count_planted() == 0,
		"**the kangaroo gets the crop in the pen** — over the fence, because its row says hop")

	var walker := _meadow_session(11, false)
	_fence_pen(walker.world)
	_release_grazer(walker, SpeciesDefs.RABBIT, outside)
	_tick_until_gone(walker, SpeciesDefs.RABBIT)
	_assert(walker.world.count_planted() == 1,
		"**the rabbit never does** — same brain, same farm, same wheat, one word changed")
	_assert(not walker.world.has_actor(SpeciesDefs.RABBIT),
		"and it gives up and leaves rather than standing at the fence forever")
	hopper.done()
	walker.done()

	# The taste question this raises is **ruled** (Q-57, 2026-08-31: wild things hop
	# anything, closed gates included — a boundary is the player's rule, not
	# nature's), and the assertion that pinned it stays exactly where it was: a
	# change to the barrier class is a failing test rather than a surprise on a
	# tablet.
	var gated := _meadow_session(12, false)
	gated.world.set_tile_state(PEN_CROP.x, PEN_CROP.y - 1, WorldLayout.GATE_CLOSED)
	_assert(Movement.is_barrier(gated.world, Vector2i(PEN_CROP.x, PEN_CROP.y - 1)),
		"a closed gate is in the barrier class a hopper crosses (Q-57, ruled: keep as built)")
	gated.done()

	# --- the daily-loss identity, extended to the new mouths (plan §4) --------
	#
	# T-15/T-20 bounded a day's losses by the birds it scheduled; WI-8a/8b added
	# the raid's term. The formula now reads:
	#   crows + raids x column size + grazer visits x bites per visit
	# and each term is guaranteed by construction rather than by tuning — a
	# forager's `carrying` is set once, and a grazer counts its own bites and goes
	# home on the last one.
	var bound := SimWorld.CROWS_PER_DAY \
		+ SimWorld.ANT_RAIDS_PER_DAY * SimWorld.ANT_COLUMN_SIZE \
		+ (SimWorld.RABBIT_VISITS_PER_DAY + SimWorld.KANGAROO_VISITS_PER_DAY) * SimWorld.GRAZER_BITES
	_assert(bound == SimWorld.CROWS_PER_DAY,
		"in a shipping build the grazers add nothing to it: no visit is ever scheduled")
	for species in [SpeciesDefs.RABBIT, SpeciesDefs.KANGAROO]:
		var budget := _meadow_session(88)
		var before := budget.world.count_planted()
		_release_grazer(budget, String(species), Vector2i(8, 6))
		_tick_until_gone(budget, String(species))
		budget.tick(2000)
		_assert_quiet(before - budget.world.count_planted() <= SimWorld.GRAZER_BITES,
			"a forced %s visit costs at most %d crops" % [species, SimWorld.GRAZER_BITES])
		budget.done()
	_flush_quiet("and a forced visit costs at most GRAZER_BITES crops, for either mouth")

	# ...and it stays bounded when the player *interferes*, which is the case a
	# bound is actually for. A fright interrupts whatever the animal was doing,
	# including the walk home, so a fed rabbit that is startled must not come back
	# to the row for thirds. It does not: the fill is re-checked every time it
	# grazes (`GrazerBrain._graze`).
	var harried := _meadow_session(88)
	var harried_dawn := harried.world.count_planted()
	_release_grazer(harried, SpeciesDefs.RABBIT, Vector2i(8, 6))
	for _round in 12:
		harried.tick(60)
		if not harried.world.has_actor(SpeciesDefs.RABBIT):
			break
		# She keeps walking up to it, over and over, all through the visit.
		harried.world.set_actor_pos(SimWorld.ACTOR_PLAYER,
			harried.world.actor_pos(SpeciesDefs.RABBIT) + Vector2i(1, 0))
		harried.tick(5)
		harried.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)
	harried.tick(2000)
	_assert(harried_dawn - harried.world.count_planted() <= SimWorld.GRAZER_BITES,
		"a rabbit scared off and back again all afternoon still costs at most %d (%d)"
			% [SimWorld.GRAZER_BITES, harried_dawn - harried.world.count_planted()])
	harried.done()

	# --- determinism, which everything above rests on ------------------------
	for species in [SpeciesDefs.RABBIT, SpeciesDefs.KANGAROO]:
		var runs: Array[String] = []
		for _i in 2:
			var d := _meadow_session(909)
			_release_grazer(d, String(species), Vector2i(6, 8))
			_tick_until_gone(d, String(species))
			d.tick(300)
			runs.append(SaveGame.capture_canonical(d.world, d.gs))
			d.done()
		_assert_quiet(runs[0] == runs[1], "%s: two runs of one seed agree" % species)
	_flush_quiet("the same seed grazes the same farm the same way, bite for bite and tick for tick")

	# --- a save taken mid-visit, continued, and its own replay ---------------
	#
	# The strongest statement the repo can make, and the one WI-5's handoff
	# promised would judge this brain (plan §4's criterion for 8c): a session
	# continued from a mid-visit save is recorded, replayed, and the recomputation
	# is compared **action for action and tick for tick**.
	#
	# The player *walks* during it, recorded as free-walk entries (WI-6), which is
	# what makes this a test of the fright rather than only of the nibble: the
	# replay has to walk her the same way and the rabbit has to bolt at the same
	# tick, from the same tile, or the net names the entry where they parted.
	var played := _meadow_session(4242)
	_release_grazer(played, SpeciesDefs.RABBIT, Vector2i(5, 9))
	played.tick(40)
	_assert(played.world.has_actor(SpeciesDefs.RABBIT), "a visit is under way when the game is saved")
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(mid["world"]["actors"].has(SpeciesDefs.RABBIT),
		"and the rabbit is *in* the save — a visit on the ground is part of a snapshot of a farm")
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-visit save restores")
	SaveGame.resume_stream(mid, w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var walked_in := false
	var bolted_live := false
	var spent := 0
	while spent < 4000 and w_cont.has_actor(SpeciesDefs.RABBIT):
		for t in w_cont.advance_ticks(20, gs_cont):
			_record_brain_step(cont_log, t)
		cont_log.mark_tick(w_cont.clock.tick)
		spent += 20
		# Halfway through, she walks over — one recorded crossing, exactly as
		# `world/farm.gd:note_player_walk` writes one.
		if not walked_in and spent >= 40 and w_cont.has_actor(SpeciesDefs.RABBIT):
			walked_in = true
			var beside: Vector2i = w_cont.actor_pos(SpeciesDefs.RABBIT) + Vector2i(1, 0)
			w_cont.set_actor_pos(SimWorld.ACTOR_PLAYER, beside, "left")
			cont_log.record_walk("stop", "left", beside, w_cont.clock.tick)
			w_cont.advance_ticks(3, gs_cont)
			bolted_live = _state_of(w_cont, SpeciesDefs.RABBIT) == GrazerBrain.STATE_FLEE
	_assert(walked_in, "the farmer walks up to it mid-visit, and the crossing is recorded")
	_assert(bolted_live,
		"the rabbit bolts because of it, so the fright is part of what the replay has to reproduce")
	_assert(cont_log.entries.size() > 0,
		"the continued session records something (%d entries)" % cont_log.entries.size())
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()


func test_songbird() -> void:
	print("\n--- The songbird: a bird that never acts (M2.5 WI-8g, design/04 §5) Tests ---")

	# --- the row --------------------------------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.SONGBIRD), "the table has it")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.SONGBIRD).is_empty(),
		"**with no verbs at all** — the whole work item, as one line of data")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.SONGBIRD) == SpeciesDefs.FLY,
		"it flies, which is the crow's capability out of the same table (WI-4)")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.SONGBIRD), SimClock.tiles_per_tick(35.0)),
		"its 35 px/s converts, like every other row")
	_assert(Brains.of_species(SpeciesDefs.SONGBIRD) is SongbirdBrain, "and the row binds to a brain")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.SONGBIRD).is_empty(),
		"it notices nothing: a bird that fled would be a second mechanic on an actor with none")
	_assert(SimWorld.SONGBIRDS_PER_DAY == 0, "and nothing schedules one in a shipping build")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.SONGBIRD, day).is_empty(),
			"day %d schedules no songbird" % day)
	_flush_quiet("on any day of any real game")

	# --- the claim: a whole visit, and not one Action ------------------------
	var ambient := _meadow_session(909)
	_release_songbird(ambient)
	var perched_somewhere := false
	var moved_at_all := false
	var was := Movement.float_pos(ambient.world, SpeciesDefs.SONGBIRD)
	var brain_actions := 0
	var spent := 0
	while spent < 8000 and ambient.world.has_actor(SpeciesDefs.SONGBIRD):
		for t in ambient.world.advance_ticks(20, ambient.gs):
			if String(t["action"].get("actor", "")) == SpeciesDefs.SONGBIRD:
				brain_actions += 1
		spent += 20
		if ambient.world.has_actor(SpeciesDefs.SONGBIRD):
			if _state_of(ambient.world, SpeciesDefs.SONGBIRD) == SongbirdBrain.STATE_PERCHED:
				perched_somewhere = true
			if Movement.float_pos(ambient.world, SpeciesDefs.SONGBIRD) != was:
				moved_at_all = true
	_assert(moved_at_all, "it drifts")
	_assert(perched_somewhere, "and perches")
	_assert(not ambient.world.has_actor(SpeciesDefs.SONGBIRD),
		"and then it is gone, off the edge of the map like the crow (after %d ticks)" % spent)
	_assert(brain_actions == 0,
		"**and in the whole visit it took no Action whatsoever** (%d)" % brain_actions)
	ambient.done()

	# The same claim from the other end: the *log*. A session with a songbird in
	# it and a hen who lays and walks records everything the hen does and never
	# once names the bird — which is what "carries a pure-charm actor with no
	# special case" has to mean in a game whose logs are phase 4's corpus.
	var logged := _meadow_session(4242)
	_release_songbird(logged)
	# A session with work in it, so "no songbird entries" is a statement about the
	# bird rather than about an empty log.
	_work_until_actions(logged, 4)
	logged.tick(200)
	_assert(logged.log.entries.size() > 0,
		"the session records the farmer's work (%d entries)" % logged.log.entries.size())
	var songbird_entries := 0
	for e in logged.log.entries:
		if String(e.get("actor", "")) == SpeciesDefs.SONGBIRD:
			songbird_entries += 1
	_assert(songbird_entries == 0,
		"a recorded session containing a songbird contains no songbird entries (%d of %d)"
			% [songbird_entries, logged.log.entries.size()])

	# ...and the net still matches, which is the half that makes the zero-entry
	# claim mean something: the bird's flight is **recomputed** from the seed and
	# compared tile for tile, so "it wrote nothing down" is not the same as "it
	# was not checked".
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(logged.world, logged.gs)))
	var bird_in_save: bool = mid["world"]["actors"].has(SpeciesDefs.SONGBIRD)
	logged.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont) and bird_in_save,
		"a mid-visit save restores, with the bird in it")
	SaveGame.resume_stream(mid, w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var flew := 0
	while flew < 600:
		for t in w_cont.advance_ticks(20, gs_cont):
			_record_brain_step(cont_log, t)
		cont_log.mark_tick(w_cont.clock.tick)
		flew += 20
	var moved_on := w_cont.has_actor(SpeciesDefs.SONGBIRD)
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and the continued session replays to the identical outcome %s" % report["divergence"])
	_assert(not moved_on,
		"the bird's whole visit ends inside the continued session, and the replay ends it too")
	gs_cont.free()

	# --- the visitors' book, which all three of them ride --------------------
	_assert(SimWorld.visitors().has(SpeciesDefs.RABBIT)
			and SimWorld.visitors().has(SpeciesDefs.KANGAROO)
			and SimWorld.visitors().has(SpeciesDefs.SONGBIRD),
		"all three are rows in one table rather than three copies of the crow's plumbing")
	for species in SimWorld.visitors().keys():
		_assert_quiet(SpeciesDefs.has(String(species)),
			"%s is a species the table knows" % species)
		var expected := 1 if String(species) == SpeciesDefs.WORM else 0
		_assert_quiet(int(SimWorld.visitors()[species]["per_day"]) == expected,
			"%s has its shipping daily ceiling" % species)
		_assert_quiet(Brains.of_species(String(species)).arrive(null, null, String(species), 0) == "",
			"%s's arrival hook refuses a null world" % species)
	_flush_quiet("every row in the visitors' table names a real species, has its shipping rate, and is safe")

	# A fresh day rolls the same book the public scheduler describes.
	var fresh = load("res://systems/game_state.gd").new()
	fresh.reset()
	fresh.takeover_day = 1
	fresh.day = 9
	fresh.start_new_day()
	_assert(fresh.visitor_schedules.size() == SimWorld.visitors().size(),
		"start_new_day rolls one book per visiting species")
	for species in fresh.visitor_schedules.keys():
		_assert(fresh.visitor_schedules[species]
				== SimWorld.roll_visitor_schedule(String(species), fresh.play_day()),
			"and %s's live book uses that species' deterministic roll" % species)
	fresh.free()

	# The book survives a save, because a reload mid-day must neither resurrect a
	# spent visit nor erase an owed one (the crow's reason, WI-3).
	var carried := _meadow_session(5)
	carried.gs.visitor_schedules = { SpeciesDefs.SONGBIRD: [4, 11] }
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(carried.world, carried.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	var w_back := SimWorld.new()
	SaveGame.restore(snap, w_back, gs_back)
	_assert(gs_back.visitor_schedules.get(SpeciesDefs.SONGBIRD, []) == [4, 11],
		"an appointment survives a save and a load")
	gs_back.free()
	carried.done()

	# ...and an old save, written before the field existed, restores as "nobody
	# is owed a visit" rather than as a crash.
	var legacy = JSON.parse_string(JSON.stringify(snap))
	legacy["state"].erase("visitor_schedules")
	var gs_legacy = load("res://systems/game_state.gd").new()
	var w_legacy := SimWorld.new()
	_assert(SaveGame.restore(legacy, w_legacy, gs_legacy),
		"a save from before the visitors' book still loads")
	_assert(gs_legacy.visitor_schedules.is_empty(), "with nobody owed a visit")
	gs_legacy.free()


# --- the last two of tier 1: a thief and a snake (M2.5 WI-8d/8e) --------------
#
# Both ride `_meadow_session` (the flattened field the grazers arranged) with a
# few tiles sown by hand, because what the mole steals is a *seed* and what the
# worm grows on is a crop, and a scenario has to be able to tell those apart in
# the assertion.
func test_mole() -> void:
	print("\n--- The mole: it is never where you tapped (M2.5 WI-8d, design/04 §4) Tests ---")

	# --- the row (checklist §8.B) ---------------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.MOLE), "the table has it")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.MOLE) == ["eat_crop"],
		"with one verb, and it is the crow's, reused a fourth time (P-9: no verb the player lacks)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.MOLE) == SpeciesDefs.BURROW,
		"**the first shipping row that burrows** — the capability WI-4 built and left empty")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.MOLE), SimClock.tiles_per_tick(20.0)),
		"its 20 px/s converts, like every other row")
	_assert(Brains.of_species(SpeciesDefs.MOLE) is MoleBrain, "and the row binds to a brain")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.MOLE).is_empty(),
		"it senses nothing: a mole that fled the player would be the opposite of the claim")
	_assert(not SpeciesDefs.senses_of(SpeciesDefs.MOLE).get("flees_spook_radius", false),
		"...and in particular it does not flee, which is what makes 'unspookable' structural")
	_assert(SpeciesDefs.is_stompable(SpeciesDefs.MOLE), "a boot answers it — when it is up")

	# --- nothing spawns one in the live game (plan §4) ------------------------
	_assert(SimWorld.MOLE_VISITS_PER_DAY == 0,
		"no visit is scheduled in a shipping build — the debut is content sequencing")
	for day in range(1, 21):
		_assert_quiet(SimWorld.roll_visitor_schedule(SpeciesDefs.MOLE, day).is_empty(),
			"day %d schedules no mole" % day)
	_flush_quiet("and no day of any real game rolls one")
	var quiet := _crow_ready_session(20260831)
	_work_until_actions(quiet, 40)
	quiet.tick(1200)
	_assert(quiet.world.actors_of_species(SpeciesDefs.MOLE).is_empty(),
		"a whole worked day on an ordinary farm never contains one")
	quiet.done()

	# --- the arrival, on the visitors' book -----------------------------------
	var booked := _meadow_session(7)
	_sow(booked, [Vector2i(12, SEED_ROW_Y), Vector2i(13, SEED_ROW_Y)])
	booked.gs.day = 9
	booked.gs.takeover_day = 1
	booked.gs.visitor_schedules = { SpeciesDefs.MOLE: [3] }
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SpeciesDefs.MOLE),
		"a booked visit arrives when the day's *action* clock reaches it (T-20's clock)")
	_assert(booked.gs.visitor_schedules.get(SpeciesDefs.MOLE, []).is_empty(),
		"and the appointment is spent, whether the visit comes to anything or not")
	_assert(Movement.is_under(booked.world, SpeciesDefs.MOLE),
		"**it arrives the way it travels** — under the farm, before anything has seen it")
	_assert(Brains.of_species(SpeciesDefs.MOLE).arrive(
			booked.world, booked.gs, SpeciesDefs.MOLE, 9) == "",
		"a second mole is refused while the first is still down there")
	booked.done()

	# --- the mechanic: it takes the seed and leaves the crop ------------------
	#
	# The distinction is the species: a grazer eats what is growing, and this one
	# steals what was planted. Both go through the same verb on the same gateway,
	# and `eat_crop` on a `seeded` tile has always meant exactly this.
	var theft := _meadow_session(4242)
	# Her pouch is emptied of wheat first, so what it holds at the end of the
	# visit is exactly what the pest handed her — which is nothing (S-18/S-19/S-20 put her
	# seed and her harvest in one place, and a starting handful would mask this).
	theft.gs.pouch["wheat"] = 0
	_sow(theft, [Vector2i(10, SEED_ROW_Y), Vector2i(12, SEED_ROW_Y),
		Vector2i(14, SEED_ROW_Y), Vector2i(16, SEED_ROW_Y)])
	var seeds_before := _seeded_count(theft.world)
	var crops_before := theft.world.count_planted() - seeds_before
	_release_mole(theft, Vector2i(5, 12))
	_assert(_tick_until_gone(theft, SpeciesDefs.MOLE),
		"a mole let into a sown field steals and goes")
	_assert(seeds_before - _seeded_count(theft.world) == SimWorld.MOLE_STEALS,
		"taking exactly its fill — %d seeds, which is what bounds a visit"
			% SimWorld.MOLE_STEALS)
	_assert(theft.world.count_planted() - _seeded_count(theft.world) == crops_before,
		"and **not one growing crop**: it came for seed, and the row of wheat is untouched")
	_assert(theft.gs.pouch.get("wheat", 0) == 0,
		"nothing it took reached the player's basket: a visit is a loss, not a harvest")
	theft.done()

	# --- off the grid, honestly (plan §4's criterion for 8d) ------------------
	#
	# 1. **Surface obstacles are irrelevant to its route.** A seed inside a ring of
	#    rock that neither a walker nor a hopper has a route into, taken anyway.
	var walled := _meadow_session(11, false)
	_rock_pen(walled.world, WALLED_SEED)
	var outside := Vector2i(14, 12)
	_assert(Movement.path(walled.world, SpeciesDefs.GROUND, outside, WALLED_SEED).is_empty()
			and Movement.path(walled.world, SpeciesDefs.HOP, outside, WALLED_SEED).is_empty(),
		"nothing that walks or hops has a route to a seed ringed with rock")
	var under_route := Movement.path(walled.world, SpeciesDefs.BURROW, outside, WALLED_SEED)
	_assert(not under_route.is_empty(),
		"a burrower has one, straight through (%d tiles)" % under_route.size())
	var through_rock := false
	for t in under_route:
		if not walled.world.is_walkable(t.x, t.y):
			through_rock = true
	_assert(through_rock, "and it goes *through* the wall rather than round it")
	_release_mole(walled, outside)
	_tick_until_gone(walled, SpeciesDefs.MOLE)
	_assert(not walled.world.has_seed(WALLED_SEED.x, WALLED_SEED.y),
		"**and the mole gets the walled seed** — under the rock, because its row says burrow")
	walled.done()

	# 2. **It cannot be answered from above.** While it is under, the tile it is
	#    passing beneath is ordinary ground: the tap that would stomp an ant falls
	#    through to the clear it always was, and the mole carries on.
	var reach := _meadow_session(31, false)
	_sow(reach, [Vector2i(18, 6)])
	_release_mole(reach, Vector2i(5, 6))
	reach.tick(40)
	_assert(reach.world.has_actor(SpeciesDefs.MOLE) and Movement.is_under(reach.world, SpeciesDefs.MOLE),
		"a mole on its way somewhere is under the farm")
	var beneath := reach.world.actor_pos(SpeciesDefs.MOLE)
	_assert(not reach.world.stompable_at(beneath),
		"**the sim says there is nothing on that tile to stomp**, though the mole is right there")
	var swing := reach.act({ "verb": "clear_weed", "target": beneath, "actor": "player" })
	_assert(swing.get("ok", false) and not swing.get("stomped", false),
		"so a clear-class tap is an ordinary clear, not a stomp")
	_assert(reach.world.has_actor(SpeciesDefs.MOLE), "and the mole is still down there")

	# 3. **Nothing frightens it mid-burrow.** She stands on top of it; it does not
	#    notice, because there is no fright in the brain to notice with.
	var route_was := str(reach.world.actor(SpeciesDefs.MOLE)["extra"].get("path", []))
	var target_was := str([reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_x", -1),
		reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_y", -1)])
	reach.world.set_actor_pos(SimWorld.ACTOR_PLAYER, beneath)
	reach.tick(20)
	_assert(reach.world.has_actor(SpeciesDefs.MOLE)
			and _state_of(reach.world, SpeciesDefs.MOLE) == MoleBrain.STATE_TUNNEL,
		"she walks over the top of it and it is still tunnelling")
	_assert(str(reach.world.actor(SpeciesDefs.MOLE)["extra"].get("path", [])) == route_was
			and str([reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_x", -1),
				reach.world.actor(SpeciesDefs.MOLE)["extra"].get("tgt_y", -1)]) == target_was,
		"on the same route to the same tile — the fright is not merely ignored, it is absent")
	reach.world.set_actor_pos(SimWorld.ACTOR_PLAYER, MEADOW_FAR_CORNER)

	# 4. **But when it comes up, the boot lands.** Which is what makes the three
	#    assertions above a *window* rather than an immunity: the answer to a mole
	#    is the second or two it is above ground.
	_assert(_tick_until_up(reach, SpeciesDefs.MOLE), "it surfaces at the tile it was aiming for")
	var up_at := reach.world.actor_pos(SpeciesDefs.MOLE)
	_assert(up_at == Vector2i(18, 6), "which is the sown one (%s)" % up_at)
	_assert(reach.world.stompable_at(up_at), "and *now* the sim says there is something there")
	var boot := reach.act({ "verb": "clear_weed", "target": up_at, "actor": "player" })
	_assert(boot.get("ok", false) and boot.get("stomped", false), "the tap answers it")
	_assert(not reach.world.has_actor(SpeciesDefs.MOLE), "and the mole is gone")
	_assert(reach.world.has_seed(up_at.x, up_at.y),
		"with the seed still in the ground: the stomp leaves the tile alone (WI-8a's rule)")
	reach.done()

	# --- she can guard a seedbed by standing in it ----------------------------
	#
	# The one place the player is in this brain at all, and it is a fact about the
	# *tile* rather than a sense on the row: a mole will not surface where anything
	# frightening is near. Same seed, same farm, same seed tile — the only
	# difference between the two runs is where she is standing.
	var guarded := _meadow_session(505, false)
	_sow(guarded, [Vector2i(12, 10)])
	guarded.world.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(13, 10))
	_release_mole(guarded, Vector2i(5, 10))
	_assert(_tick_until_gone(guarded, SpeciesDefs.MOLE),
		"a mole with nowhere it is willing to come up gives up and leaves")
	_assert(guarded.world.has_seed(12, 10),
		"**and the seed she was standing over survives** — no tap, no tool, no verb at all")
	guarded.done()

	var unguarded := _meadow_session(505, false)
	_sow(unguarded, [Vector2i(12, 10)])
	_release_mole(unguarded, Vector2i(5, 10))
	_tick_until_gone(unguarded, SpeciesDefs.MOLE)
	_assert(not unguarded.world.has_seed(12, 10),
		"...and with her across the farm instead, the same mole takes the same seed")
	unguarded.done()

	# --- the daily-loss identity, extended again (plan §4) --------------------
	#
	# The mole's term is denominated in **seeds**, which is the honest accounting:
	# `count_planted()` has always counted a sown tile as planted, so a stolen seed
	# is a unit of the currency the identity was already measured in — a thing she
	# paid gold for and will not harvest. It is a subset of the same loss, not a
	# new kind of it, which is why the formula gains a term rather than a footnote.
	var bound := SimWorld.CROWS_PER_DAY \
		+ SimWorld.ANT_RAIDS_PER_DAY * SimWorld.ANT_COLUMN_SIZE \
		+ (SimWorld.RABBIT_VISITS_PER_DAY + SimWorld.KANGAROO_VISITS_PER_DAY) * SimWorld.GRAZER_BITES \
		+ SimWorld.MOLE_VISITS_PER_DAY * SimWorld.MOLE_STEALS \
		+ SimWorld.WORM_VISITS_PER_DAY * SimWorld.WORM_MEALS
	_assert(bound == SimWorld.CROWS_PER_DAY + SimWorld.WORM_MEALS,
		"the shipping daily ceiling includes one rare worm's bounded meal")
	var budget := _meadow_session(88)
	_sow(budget, [Vector2i(8, SEED_ROW_Y), Vector2i(9, SEED_ROW_Y), Vector2i(10, SEED_ROW_Y),
		Vector2i(11, SEED_ROW_Y), Vector2i(12, SEED_ROW_Y), Vector2i(13, SEED_ROW_Y)])
	var planted_dawn := budget.world.count_planted()
	_release_mole(budget, Vector2i(6, 12))
	_tick_until_gone(budget, SpeciesDefs.MOLE)
	budget.tick(2000)
	_assert(planted_dawn - budget.world.count_planted() <= SimWorld.MOLE_STEALS,
		"a forced mole visit costs at most %d planted tiles (%d)"
			% [SimWorld.MOLE_STEALS, planted_dawn - budget.world.count_planted()])
	budget.done()

	# --- determinism, which everything above rests on -------------------------
	var runs: Array[String] = []
	for _i in 2:
		var d := _meadow_session(909)
		_sow(d, [Vector2i(10, SEED_ROW_Y), Vector2i(14, SEED_ROW_Y), Vector2i(18, SEED_ROW_Y)])
		_release_mole(d, Vector2i(6, 12))
		_tick_until_gone(d, SpeciesDefs.MOLE)
		d.tick(300)
		runs.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(runs[0] == runs[1],
		"the same seed digs the same farm the same way, seed for seed and tick for tick")

	# --- a save taken mid-tunnel, continued, and its own replay ---------------
	#
	# The strongest statement the repo can make (WI-5's net, WI-8c's shape): a
	# session continued from a save taken while the mole is **under the farm** is
	# recorded, replayed, and the recomputation compared action for action and tick
	# for tick. The farmer walks during it and the crossing is recorded, so the
	# surfacing rule — the one thing in this brain that reads her position — has to
	# be recomputed from the log or the net names the entry where they parted.
	var played := _meadow_session(4242)
	_sow(played, [Vector2i(10, SEED_ROW_Y), Vector2i(14, SEED_ROW_Y), Vector2i(18, SEED_ROW_Y)])
	_release_mole(played, Vector2i(5, 12))
	played.tick(30)
	_assert(played.world.has_actor(SpeciesDefs.MOLE) and Movement.is_under(played.world, SpeciesDefs.MOLE),
		"the mole is under the farm when the game is saved")
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(mid["world"]["actors"].has(SpeciesDefs.MOLE),
		"and it is *in* the save — a visit in progress is part of a snapshot of a farm")
	_assert(bool(mid["world"]["actors"][SpeciesDefs.MOLE]["extra"].get("under", false)),
		"with its off-grid position saved as the fact it is (under: true)")
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-tunnel save restores")
	_assert(Movement.is_under(w_cont, SpeciesDefs.MOLE), "with the mole still under the farm")
	SaveGame.resume_stream(mid, w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var walked_in := false
	var spent := 0
	while spent < 6000 and w_cont.has_actor(SpeciesDefs.MOLE):
		for t in w_cont.advance_ticks(20, gs_cont):
			_record_brain_step(cont_log, t)
		cont_log.mark_tick(w_cont.clock.tick)
		spent += 20
		# Halfway through she walks out to the seed row and stands there, which is
		# a decision the mole has to recompute the same way twice.
		if not walked_in and spent >= 60:
			walked_in = true
			var beside := Vector2i(11, SEED_ROW_Y)
			w_cont.set_actor_pos(SimWorld.ACTOR_PLAYER, beside, "left")
			cont_log.record_walk("stop", "left", beside, w_cont.clock.tick)
	_assert(walked_in, "the farmer walks out to the seedbed mid-visit, and the crossing is recorded")
	_assert(not w_cont.has_actor(SpeciesDefs.MOLE),
		"the visit ends inside the continued session (%d ticks)" % spent)
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()


func test_worm() -> void:
	print("\n--- The worm: it grows, and its own back is in the way (M2.5 WI-8e) Tests ---")

	# --- the row (checklist §8.B) ---------------------------------------------
	_assert(SpeciesDefs.has(SpeciesDefs.WORM), "the table has it")
	_assert(SpeciesDefs.verbs_of(SpeciesDefs.WORM) == ["eat_crop"],
		"with one verb, and it is everybody else's (P-9: no verb the player lacks)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.WORM) == SpeciesDefs.GROUND,
		"it walks like a walker — the strangeness is not in the mode")
	_assert(Movement.body_len_of(SpeciesDefs.WORM) == 2,
		"**the first shipping row with a body**: two segments to start with")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.WORM), SimClock.tiles_per_tick(6.0)),
		"its 6 px/s converts, and makes it the slowest thing in the game")
	_assert(Brains.of_species(SpeciesDefs.WORM) is WormBrain, "and the row binds to a brain")
	_assert(SpeciesDefs.is_stompable(SpeciesDefs.WORM), "a boot answers it")
	_assert(SimWorld.WORM_VISITS_PER_DAY == 1 and SimWorld.WORM_VISIT_DAY_RATE == 10,
		"and the living farm gives it one deterministic chance in ten eligible days")
	SimRng.reseed(350038)
	var visit_days: Array[int] = []
	var appointments: Array[int] = []
	for day in range(1, 103):
		var first := SimWorld.roll_visitor_schedule(SpeciesDefs.WORM, day)
		var again := SimWorld.roll_visitor_schedule(SpeciesDefs.WORM, day)
		_assert_quiet(first == again, "day %d rolls the same appointment twice" % day)
		if not first.is_empty():
			visit_days.append(day)
			appointments.append(int(first[0]))
	_assert(SimWorld.roll_visitor_schedule(SpeciesDefs.WORM, 1).is_empty()
			and SimWorld.roll_visitor_schedule(SpeciesDefs.WORM, 2).is_empty(),
		"a new player's first two days have no worm")
	_assert(visit_days == [14, 32, 38, 45, 46, 53, 56, 66, 67, 90]
			and appointments == [12, 16, 18, 11, 8, 10, 16, 12, 15, 21],
		"and seed 350038 pins the exact hundred-day visit book and action times")

	# --- the arrival ----------------------------------------------------------
	var booked := _meadow_session(7)
	booked.gs.day = 9
	booked.gs.takeover_day = 1
	booked.gs.visitor_schedules = { SpeciesDefs.WORM: [3] }
	_work_until_actions(booked, 3)
	_assert(booked.world.has_actor(SpeciesDefs.WORM),
		"a booked visit arrives on the day's action clock, like every other visitor")
	_assert(booked.gs.visitor_schedules.get(SpeciesDefs.WORM, []).is_empty(),
		"and the appointment is spent either way")
	_assert(Brains.of_species(SpeciesDefs.WORM).arrive(
			booked.world, booked.gs, SpeciesDefs.WORM, 9) == "",
		"a second worm is refused while the first is still here")
	booked.done()

	# A written appointment cannot bypass either readiness rule. It is still
	# consumed, so a farm does not accumulate an overdue pest for later.
	var one_crop := _meadow_session(8, false)
	one_crop.world.set_tile_state(12, MEADOW_ROW_Y, "growing", "wheat")
	one_crop.gs.day = 9
	one_crop.gs.takeover_day = 1
	one_crop.gs.visitor_schedules = { SpeciesDefs.WORM: [1] }
	_work_until_actions(one_crop, 1)
	_assert(not one_crop.world.has_actor(SpeciesDefs.WORM)
			and one_crop.gs.visitor_schedules[SpeciesDefs.WORM].is_empty(),
		"a booked worm is spent but cannot arrive for fewer than two planted crops")
	one_crop.done()

	var second_day := _meadow_session(9)
	second_day.gs.day = 2
	second_day.gs.takeover_day = 1
	second_day.gs.visitor_schedules = { SpeciesDefs.WORM: [1] }
	_work_until_actions(second_day, 1)
	_assert(not second_day.world.has_actor(SpeciesDefs.WORM)
			and second_day.gs.visitor_schedules[SpeciesDefs.WORM].is_empty(),
		"a booked worm is spent but cannot arrive before play-day 3")
	second_day.done()

	# --- the mechanic: one segment per crop ----------------------------------
	#
	# The growth is the work item, so it is measured rather than watched: the
	# length before, the crops missing after, and the drawn footprint at the end.
	# **"A three-segment body occupies three tiles" is WI-4's test**; this one is
	# the growth — n crops eaten, n segments longer, and the tiles to match.
	var grow := _meadow_session(4242, false)
	# Three crops, spaced exactly a nose apart along one row, so the animal has to
	# **crawl** between them: a body only fills out over the tiles its head has
	# already been on (WI-4's `_advance_body`), so a worm that ate three crops
	# standing still would be three segments long and drawn as one tile — true, and
	# not a picture of anything.
	for tx in [12, 16, 20]:
		grow.world.set_tile_state(tx, SEED_ROW_Y, "growing", "wheat")
	var was_len := Movement.body_len(grow.world, "nobody")
	_release_worm(grow, Vector2i(8, SEED_ROW_Y))
	_assert(was_len == 1, "an actor that does not exist is one tile long, and asks nothing of anybody")
	_assert(Movement.body_len(grow.world, SpeciesDefs.WORM) == 2,
		"a worm starts at the length its species row says")
	var crops_dawn := grow.world.count_planted()
	var contiguous := true
	var never_overdrawn := true
	var distinct := true
	var longest := 0
	var grew_to := 2
	var spent := 0
	while spent < 16000 and grow.world.has_actor(SpeciesDefs.WORM):
		grow.tick(20)
		spent += 20
		if not grow.world.has_actor(SpeciesDefs.WORM):
			break
		var body := Movement.occupied_tiles(grow.world, SpeciesDefs.WORM)
		grew_to = Movement.body_len(grow.world, SpeciesDefs.WORM)
		longest = maxi(longest, body.size())
		if body.size() > grew_to:
			never_overdrawn = false  # it drew more of itself than it is
		var seen := {}
		for i in body.size():
			if seen.has(body[i]):
				distinct = false
			seen[body[i]] = true
			if i > 0 and absi(body[i].x - body[i - 1].x) + absi(body[i].y - body[i - 1].y) != 1:
				contiguous = false
	var eaten := crops_dawn - grow.world.count_planted()
	_assert(eaten == SimWorld.WORM_MEALS,
		"a worm in a row of wheat eats its fill and goes (%d crops)" % eaten)
	_assert(grew_to == 2 + eaten,
		"**and it is one segment longer for every one of them**: 2 + %d eaten = %d segments"
			% [eaten, grew_to])
	_assert(longest == grew_to,
		"and the tiles it is drawn on grew with it — %d of them, which is what it is" % longest)
	_assert(contiguous, "its body is a line of adjacent tiles, head first, at every moment of it")
	_assert(distinct and never_overdrawn,
		"and it never occupies one tile twice, or more tiles than it is long")
	grow.done()

	# The same claim from the registry's side: the growth is one integer in the
	# actor's own `extra` (WI-4's per-actor override), which is why it survives a
	# save without the species table ever hearing about it.
	var one_meal := _meadow_session(77, false)
	one_meal.world.set_tile_state(12, 8, "ready", "wheat")
	_release_worm(one_meal, Vector2i(10, 8))
	var fed := false
	var meal_spent := 0
	while meal_spent < 6000 and one_meal.world.has_actor(SpeciesDefs.WORM) and not fed:
		one_meal.tick(20)
		meal_spent += 20
		fed = one_meal.world.count_planted() == 0
	_assert(fed, "a worm eats the one crop on the farm")
	_assert(int(one_meal.world.actor(SpeciesDefs.WORM)["extra"].get("body_len", 0)) == 3,
		"and writes its new length into its own registry entry (2 -> 3)")
	_assert(Movement.body_len(one_meal.world, SpeciesDefs.WORM) == 3,
		"which is the length the engine moves it at")
	var carried = JSON.parse_string(JSON.stringify(SaveGame.capture(one_meal.world, one_meal.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	var w_back := SimWorld.new()
	SaveGame.restore(carried, w_back, gs_back)
	_assert(Movement.body_len(w_back, SpeciesDefs.WORM) == 3,
		"a saved worm restores at the length it grew to")
	_assert(str(Movement.occupied_tiles(w_back, SpeciesDefs.WORM))
			== str(Movement.occupied_tiles(one_meal.world, SpeciesDefs.WORM)),
		"with its body on the same tiles it was lying on")
	gs_back.free()
	one_meal.done()

	# --- the snake rule: it can shut itself in ---------------------------------
	#
	# Plan §4's criterion, played rather than asserted: the worm is walked in a
	# spiral by the movement engine — every step is `Movement.plan` + `step`, the
	# same two calls its brain makes — until its head steps into the middle of the
	# coil. All four of its neighbours are then **its own body**, on open ground,
	# with no wall anywhere near it. That is the classic constraint: the only thing
	# that trapped it is how long it got.
	SimRng.reseed(4242)
	var arena := SimWorld.new()
	arena.generate()
	for ty in range(3, 12):
		for tx in range(3, 12):
			arena.set_tile_state(tx, ty, "cleared")
			arena.set_object(tx, ty, "")
	arena.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, Vector2i(4, 4), {})
	# Eight segments — five meals' worth of growth, written the way a meal writes
	# it (WI-4's `extra.body_len`, and the same line `WormBrain.on_result` uses).
	arena.actor(SpeciesDefs.WORM)["extra"]["body_len"] = 8
	var coil: Array[Vector2i] = [
		Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6),
		Vector2i(5, 6), Vector2i(4, 6), Vector2i(4, 5), Vector2i(5, 5),
	]
	var walked := 0
	for t in coil:
		if Movement.plan(arena, SpeciesDefs.WORM, t) \
				and Movement.step(arena, SpeciesDefs.WORM, walked) == Movement.MOVED:
			walked += 1
	_assert(walked == coil.size(), "the worm walks itself into a coil, one engine step at a time")
	var head := arena.actor_pos(SpeciesDefs.WORM)
	_assert(head == Vector2i(5, 5), "its head ends in the middle of it (%s)" % head)
	var occupied := Movement.occupied_tiles(arena, SpeciesDefs.WORM)
	_assert(occupied.size() == 8, "eight tiles of worm (%d)" % occupied.size())
	var walled_in := true
	var open_ground := true
	for d in Movement.DIRS:
		var n: Vector2i = head + d
		if not (n in occupied) or Movement.can_enter(arena, SpeciesDefs.WORM, n):
			walled_in = false
		if not arena.is_walkable(n.x, n.y):
			open_ground = false
	_assert(open_ground, "on ground it could otherwise walk across in any direction")
	_assert(walled_in,
		"**and every way out is its own body** — the snake rule, with no wall involved")
	Movement.plan(arena, SpeciesDefs.WORM, Vector2i(9, 9))
	_assert(Movement.step(arena, SpeciesDefs.WORM, 99) == Movement.BLOCKED,
		"so a route out is blocked at the step, not at the plan (WI-4's rule)")
	_assert(arena.actor_pos(SpeciesDefs.WORM) == head, "and it has not moved")

	# ...and what a stuck worm *does* is the brain's answer, not the engine's: it
	# balks a few times and then goes back down into the soil, because an actor
	# that will never move again must not keep waking up (ground rule 8).
	var trapped := _meadow_session(4242, false)
	trapped.world.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, Vector2i(4, 4), {
		"state": WormBrain.STATE_HUNT, "home_x": 4, "home_y": 4,
		"meals": 0, "tries": 0, "stuck": 0,
	})
	trapped.world.actor(SpeciesDefs.WORM)["extra"]["body_len"] = 8
	var steps := 0
	for t in coil:
		if Movement.plan(trapped.world, SpeciesDefs.WORM, t) \
				and Movement.step(trapped.world, SpeciesDefs.WORM, steps) == Movement.MOVED:
			steps += 1
	_assert(steps == coil.size() and trapped.world.actor_pos(SpeciesDefs.WORM) == Vector2i(5, 5),
		"a second worm coils itself up the same way, this time on the clock")
	_assert(_tick_until_gone(trapped, SpeciesDefs.WORM),
		"and a worm with nowhere left to go stops trying rather than waking up forever")
	trapped.done()

	# --- the stomp answers any tile of it ------------------------------------
	var boot := _meadow_session(31, false)
	boot.world.set_tile_state(12, 8, "ready", "wheat")
	_release_worm(boot, Vector2i(8, 8))
	var crawled := 0
	while crawled < 4000 and Movement.occupied_tiles(boot.world, SpeciesDefs.WORM).size() < 2:
		boot.tick(20)
		crawled += 20
	var body := Movement.occupied_tiles(boot.world, SpeciesDefs.WORM)
	_assert(body.size() >= 2, "a worm that has crawled a tile is lying on two of them")
	var tail: Vector2i = body[body.size() - 1]
	_assert(tail != boot.world.actor_pos(SpeciesDefs.WORM), "and its tail is not its head")
	_assert(boot.world.stompable_at(tail),
		"**a tap on the tail is a tap on the worm** (`Movement.occupied_tiles`, not the head)")
	var stomp := boot.act({ "verb": "clear_weed", "target": tail, "actor": "player" })
	_assert(stomp.get("ok", false) and stomp.get("stomped", false), "the boot lands")
	_assert(not boot.world.has_actor(SpeciesDefs.WORM), "and the whole animal goes, not a segment")
	boot.done()

	# --- the daily-loss identity ---------------------------------------------
	var budget := _meadow_session(88)
	var dawn := budget.world.count_planted()
	_release_worm(budget, Vector2i(9, 6))
	_tick_until_gone(budget, SpeciesDefs.WORM, 16000)
	budget.tick(2000)
	_assert(dawn - budget.world.count_planted() <= SimWorld.WORM_MEALS,
		"a forced worm visit costs at most %d crops (%d)"
			% [SimWorld.WORM_MEALS, dawn - budget.world.count_planted()])
	budget.done()

	# --- determinism ----------------------------------------------------------
	var runs: Array[String] = []
	for _i in 2:
		var d := _meadow_session(909)
		_release_worm(d, Vector2i(9, 6))
		_tick_until_gone(d, SpeciesDefs.WORM, 16000)
		d.tick(300)
		runs.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(runs[0] == runs[1],
		"the same seed grows the same worm the same way, segment for segment and tick for tick")

	# --- a save taken mid-crawl, continued, and its own replay ---------------
	#
	# WI-5's net, aimed at the one thing that is new here: the **body** is in the
	# save and in the comparison, so a restored worm that lay down differently, or
	# grew at a different tick, is a divergence with a name.
	var played := _meadow_session(4242)
	_release_worm(played, Vector2i(9, 6))
	played.tick(120)
	_assert(played.world.has_actor(SpeciesDefs.WORM), "a visit is under way when the game is saved")
	var half_fed := int(played.world.actor(SpeciesDefs.WORM)["extra"].get("meals", 0))
	_assert(half_fed > 0 and half_fed < SimWorld.WORM_MEALS,
		"with the worm part-grown and still hungry (%d of %d meals)" % [half_fed, SimWorld.WORM_MEALS])
	var mid = JSON.parse_string(JSON.stringify(SaveGame.capture(played.world, played.gs)))
	_assert(mid["world"]["actors"].has(SpeciesDefs.WORM)
			and mid["world"]["actors"][SpeciesDefs.WORM]["extra"].has("body"),
		"and the worm is in it, body and all")
	_assert(int(mid["world"]["actors"][SpeciesDefs.WORM]["extra"].get("body_len", 0)) == 2 + half_fed,
		"at the length it has grown to, which is one integer in its own registry entry")
	played.done()

	var gs_cont = load("res://systems/game_state.gd").new()
	gs_cont.reset()
	var w_cont := SimWorld.new()
	_assert(SaveGame.restore(mid, w_cont, gs_cont), "the mid-crawl save restores")
	SaveGame.resume_stream(mid, w_cont.gen_seed)
	var cont_log := ReplayLog.new()
	cont_log.start_from_save(mid, w_cont.gen_seed)
	var lived := 0
	while lived < 16000 and w_cont.has_actor(SpeciesDefs.WORM):
		for t in w_cont.advance_ticks(20, gs_cont):
			_record_brain_step(cont_log, t)
		cont_log.mark_tick(w_cont.clock.tick)
		lived += 20
	_assert(not w_cont.has_actor(SpeciesDefs.WORM),
		"the whole visit plays out inside the continued session (%d ticks)" % lived)
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(w_cont, gs_cont)))
	var report := SaveGame.replay_report(cont_log, end_save)
	_assert(report["matched"],
		"and it replays to the identical outcome %s" % report["divergence"])
	gs_cont.free()


# --- The bot line, v1 (M2.5 WI-9) ---------------------------------------------
#
# A flat yard with no acorns on it. No acorns because a crow prefers one to any
# crop (T-15/Q-39), and the shoo tests need the bird to come for a **crop** on a
# tile this test chose — which is also the only way "its radius covers the
# target" can be a thing to assert rather than a thing to hope for.
func test_bots() -> void:
	print("\n--- The bot line, v1: one machine, three settings (M2.5 WI-9) Tests ---")

	# --- the row (P-9, ground rule 1) -----------------------------------------
	#
	# P-9 says any entity may carry the full player verb set. This row is the
	# first one that does, and the assertion below is the strongest form of it:
	# not "the same verbs" but **the same array**, so there is nothing to keep in
	# step and no way for the two to drift.
	_assert(is_same(SpeciesDefs.ROWS[SpeciesDefs.BOT]["verbs"],
			SpeciesDefs.ROWS[SpeciesDefs.PLAYER]["verbs"]),
		"a bot carries the player's verb set — literally her row's array, not a copy (P-9)")
	_assert(str(SpeciesDefs.verbs_of(SpeciesDefs.BOT)) == str(SpeciesDefs.PLAYER_VERBS)
			and SpeciesDefs.verbs_of(SpeciesDefs.BOT).size() == SpeciesDefs.PLAYER_VERBS.size(),
		"...and therefore verb for verb, in order (%d verbs)" % SpeciesDefs.PLAYER_VERBS.size())
	var borrowed := false
	for v in SpeciesDefs.verbs_of(SpeciesDefs.BOT):
		if v in SpeciesDefs.ENTITY_VERBS and not (v in SpeciesDefs.PLAYER_VERBS):
			borrowed = true
	_assert(not borrowed,
		"and not one verb she lacks — a bot gets no capability the player has not got (rule 1)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.BOT) == SpeciesDefs.GROUND
			and SpeciesDefs.is_persistent(SpeciesDefs.BOT)
			and not SpeciesDefs.is_stompable(SpeciesDefs.BOT),
		"it walks, it is part of a snapshot of the farm, and a boot does not answer it")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.BOT), SimClock.tiles_per_tick(32.0)),
		"at 32 px/s — two thirds of her pace (ruled from play 2026-09-07: a machine that trails her reads as labour)")
	_assert(Brains.of_species(SpeciesDefs.BOT) is BotBrain,
		"and one brain answers for all three configs")

	# **A class is data** (the shoo config's quarry). The alternative was a list
	# of species names inside the brain, which is the hardcoded roster the species
	# table exists to abolish — and which the next bird would have fallen out of.
	_assert(str(SpeciesDefs.species_of_class(SpeciesDefs.CLASS_BIRD))
			== str([SpeciesDefs.CROW, SpeciesDefs.SONGBIRD]),
		"the bird class is exactly the crow and the songbird, and it is a field on their rows")
	_assert(SpeciesDefs.class_of(SpeciesDefs.CHICKEN) == ""
			and SpeciesDefs.class_of(SpeciesDefs.BOT) == "",
		"a hen is not a bird as far as a shoo-bot is concerned, and neither is another bot")

	# --- nothing acquires one (Q-56, ruled) -----------------------------------
	SimRng.reseed(31337)
	var fresh := SimWorld.new()
	fresh.generate()
	_assert(fresh.actors_of_species(SpeciesDefs.BOT).is_empty(),
		"a generated world contains no bot — the debut is Q-56's, and it is ruled: not before M3")
	_assert(not SimWorld.visitors().has(SpeciesDefs.BOT),
		"and nothing schedules one either: a machine is not a visitor")

	# --- follow: it trails her, and it reads the registry to do it ------------
	var f := _bot_yard(9001)
	BotBrain.deploy(f.world, "follow_bot", BotBrain.CONFIG_FOLLOW, BOT_HER_TILE + Vector2i(2, 0))
	f.rebase()
	f.tick(20)
	_assert(_bot_gap(f.world, "follow_bot") <= BotBrain.FOLLOW_TILES + BotBrain.FOLLOW_SLACK,
		"a deployed follow bot settles at its station (%d tiles)" % _bot_gap(f.world, "follow_bot"))

	# Her walk is *recorded*, tile by tile, exactly as the game records one — and
	# it has to be, because nothing can recompute where she chose to go. The bot's
	# whole behaviour is a function of those entries.
	var sites: Array[Vector2i] = [Vector2i(14, 6), Vector2i(14, 13), Vector2i(6, 13)]
	var worst := 0
	var stood_on_her := false
	for site in sites:
		_walk_her(f, site)
		f.tick(12)
		worst = maxi(worst, _bot_gap(f.world, "follow_bot"))
		if f.world.actor_pos("follow_bot") == f.world.actor_pos(SimWorld.ACTOR_PLAYER):
			stood_on_her = true
		f.world.set_tile_state(site.x, site.y, "cleared")
		f.act({ "verb": "till", "target": site, "actor": "player" })
		_assert_quiet(_bot_gap(f.world, "follow_bot") <= BotBrain.FOLLOW_TILES + BotBrain.FOLLOW_SLACK + 1,
			"the bot is at her elbow for the action at %s" % str(site))
	_flush_quiet("a follow bot's position tracks the player's action sites across a recorded session")
	_assert(worst <= BotBrain.FOLLOW_TILES + BotBrain.FOLLOW_SLACK + 1,
		"and never falls behind by more than its station plus a step (worst: %d)" % worst)
	_assert(not stood_on_her, "and never stands where she is standing")

	# The net, on the config whose whole input is her recorded motion: strip the
	# walks out and the bot follows a farmer who never moved.
	var f_save = JSON.parse_string(JSON.stringify(SaveGame.capture(f.world, f.gs)))
	var f_report := SaveGame.replay_report(f.log, f_save)
	_assert(f_report["matched"],
		"the whole session replays to the identical outcome, bot included %s" % f_report["divergence"])
	var stripped := ReplayLog.new()
	stripped.gen_seed = f.log.gen_seed
	stripped.base_save = f.log.base_save
	stripped.version = f.log.version
	stripped.end_tick = f.log.end_tick
	for e in f.log.entries:
		if not ReplayLog.is_walk(e):
			stripped.entries.append(e)
	_assert(not SaveGame.replay_report(stripped, f_save)["matched"],
		"and a log with her crossings taken out of it does not — the bot is following *her*")
	f.done()

	# Two runs of one seed are one run twice (ground rule 3: every draw is SimRng).
	var follow_ends: Array[String] = []
	for _i in 2:
		var d := _bot_yard(4711)
		BotBrain.deploy(d.world, "follow_bot", BotBrain.CONFIG_FOLLOW, BOT_HER_TILE + Vector2i(3, 1))
		_walk_her(d, Vector2i(16, 12))
		d.tick(60)
		follow_ends.append(SaveGame.capture_canonical(d.world, d.gs))
		d.done()
	_assert(follow_ends[0] == follow_ends[1], "and the same seed walks the same bot the same way")

	# --- circle: it orbits, one tile at a time --------------------------------
	var c := _bot_yard(2024)
	BotBrain.deploy(c.world, "circle_bot", BotBrain.CONFIG_CIRCLE, BOT_HER_TILE + Vector2i(0, 2),
		{ "radius": 2 })
	c.tick(40)
	var ring_tiles := {}
	var off_ring := 0
	var on_her := 0
	for _i in 60:
		c.tick(3)
		var at := c.world.actor_pos("circle_bot")
		ring_tiles[at] = true
		var her := c.world.actor_pos(SimWorld.ACTOR_PLAYER)
		if maxi(absi(at.x - her.x), absi(at.y - her.y)) != 2:
			off_ring += 1
		if at == her:
			on_her += 1
	_assert(off_ring == 0,
		"a circle bot holds its radius on every sample of a standing farmer (%d off)" % off_ring)
	_assert(on_her == 0, "and is never underfoot")
	_assert(ring_tiles.size() >= 8,
		"and it *orbits* rather than parking: %d of the ring's 16 tiles" % ring_tiles.size())
	# The ring is a square, and that is load-bearing: consecutive tiles have to be
	# orthogonally adjacent or an orbit is a series of diagonal hops nobody can walk.
	var ring := BotBrain.ring_tiles(Vector2i(10, 10), 2)
	var adjacent := true
	for i in ring.size():
		var step_v: Vector2i = ring[(i + 1) % ring.size()] - ring[i]
		if absi(step_v.x) + absi(step_v.y) != 1:
			adjacent = false
	_assert(ring.size() == 16 and adjacent,
		"the orbit of radius 2 is 16 tiles and every step round it is one tile")

	# It keeps orbiting *her*, not the spot she was on.
	_walk_her(c, Vector2i(16, 10))
	c.tick(30)
	var her_now := c.world.actor_pos(SimWorld.ACTOR_PLAYER)
	var bot_now := c.world.actor_pos("circle_bot")
	_assert(maxi(absi(bot_now.x - her_now.x), absi(bot_now.y - her_now.y)) <= 3,
		"and it comes with her when she walks off (%s vs %s)" % [str(bot_now), str(her_now)])
	c.done()

	# --- shoo: the same farm, the same bird, one number different -------------
	#
	# The criterion, stated the way plan §4 states it: the visit ends early
	# **exactly when the bot's radius covers the crow's target**, and the target
	# is worked out from the appointment book rather than observed, so the two
	# runs differ in nothing but the radius.
	var covered := _shoo_run(5150, 3.0)
	var uncovered := _shoo_run(5150, 1.0)
	_assert(covered["arrived"] and uncovered["arrived"],
		"the day's appointment brings a crow in both runs (target %s)" % str(covered["target"]))
	_assert(str(covered["target"]) == str(uncovered["target"]),
		"the same crow, for the same crop, on the same tick")
	_assert(covered["reason"] == "bot" and covered["lost"] == 0,
		"a bot whose patch covers the target ends the visit — and the crop is still there")
	_assert(uncovered["reason"] == "ate" and uncovered["lost"] == 1,
		"and a bot whose patch does not, does not: that crow ate (%s)" % str(uncovered["reason"]))
	_assert(covered["scares"] == 1 and covered["by"] == "shoo_bot",
		"the scare is one recorded Action, and it says which machine caused it")
	_assert(uncovered["scares"] == 0, "and the run that lost the crop recorded none")
	_flush_quiet("every Action a shoo bot takes is in the log, marked as a brain's")
	_assert(covered["seen"] == 1 and uncovered["seen"] == 1
			and covered["booked"] == 0 and uncovered["booked"] == 0,
		"T-20 holds either way: one arrival is one arrival, shooed or fed")
	# **Delegated work counts** (`[Designer]` Q-66, ruled 2026-08-31: credit flows
	# up). She built the machine and she placed it, so the bird it walked off her
	# farm is on her proof exactly as the ones she walked off herself — which is
	# the whole game's thesis, arriving early and in miniature. WI-9 shipped the
	# opposite as the safe default and this assertion is the flip of it.
	_assert(covered["scared_counter"] == 1,
		"a bot's scare counts toward her capability proof, like her own (Q-12/Q-66)")
	var by_hand := _bot_yard(77)
	by_hand.world.spawn_actor(SimWorld.ACTOR_CROW, SpeciesDefs.CROW, Vector2i(9, 9), {})
	by_hand.act({ "verb": "crow_scared", "actor": SimWorld.ACTOR_CROW })
	_assert(by_hand.gs.crows_scared == 1,
		"...while her own scare counts exactly as it always has (no `by` means her)")
	by_hand.done()

	# --- shoo: the actor with nothing to say about it -------------------------
	#
	# A songbird has no verbs at all (WI-8g), which means there is no Action either
	# of them can take when a bot arrives on its tile. The honest outcome is
	# *nothing*, and the only honest thing for the machine to do about it is stop.
	var q := _bot_yard(8123)
	var perch := Vector2i(14, 9)
	BotBrain.deploy(q.world, "shoo_bot", BotBrain.CONFIG_SHOO, perch + Vector2i(0, 3),
		{ "home_x": perch.x, "home_y": perch.y + 3, "radius": 5.0 })
	q.world.spawn_actor(SpeciesDefs.SONGBIRD, SpeciesDefs.SONGBIRD, perch, {
		"state": SongbirdBrain.STATE_PERCHED,
		"fx": float(perch.x) + 0.5, "fy": float(perch.y) + 0.5,
		"tgt_x": -1, "tgt_y": -1, "perches": 0, "perch_until": 100000, "ex": 0.0, "ey": 0.0,
	})
	var chased := false
	for _i in 30:
		q.tick(10)
		if String(q.world.actor("shoo_bot")["extra"].get("state", "")) == BotBrain.STATE_CHASE:
			chased = true
	_assert(chased, "a shoo bot chases a songbird — a bird is a bird, by its class")
	_assert(q.world.has_actor(SpeciesDefs.SONGBIRD),
		"and achieves nothing, because a songbird has no visit to end and no Action to receive")
	var log_had_actions := false
	for e in q.log.entries:
		if not ReplayLog.is_walk(e) and String(e.get("kind", "")) != "brain_decision":
			log_had_actions = true
	_assert(not log_had_actions,
		"no Action is written down, because nothing happened — no verb was invented for it")
	_assert(String(q.world.actor("shoo_bot")["extra"].get("ignore", "")) == SpeciesDefs.SONGBIRD,
		"the machine marks the bird as one it cannot budge...")
	var home_q := Vector2i(perch.x, perch.y + 3)
	var went_home := Vector2(q.world.actor_pos("shoo_bot") - home_q).length() <= 5.0
	_assert(went_home and String(q.world.actor("shoo_bot")["extra"].get("state", ""))
			!= BotBrain.STATE_CHASE,
		"...and goes back to its patch rather than hounding it forever")
	q.done()

	# Reusing a patrol choice must preserve the exact breadth-first candidate
	# order and the single seeded draw, including after terrain changes.
	var patrol := _bot_yard(9917)
	BotBrain.deploy(patrol.world, "patrol_bot", BotBrain.CONFIG_SHOO,
		BOT_HER_TILE + Vector2i(0, 2), { "radius": 4.0 })
	var patrol_brain := BotBrain.new()
	var patrol_extra: Dictionary = patrol.world.actor("patrol_bot")["extra"]
	for change in 3:
		if change == 2:
			patrol.world.set_tile_state(BOT_HER_TILE.x + 1, BOT_HER_TILE.y + 2,
				WorldLayout.FENCE)
		var candidates: Array[Vector2i] = []
		var home := Vector2i(int(patrol_extra["home_x"]), int(patrol_extra["home_y"]))
		for tile in Movement.reachable(patrol.world, SpeciesDefs.GROUND,
				patrol.world.actor_pos("patrol_bot")):
			if Vector2(tile - home).length() <= 4.0 \
					and Movement.can_stop(patrol.world, SpeciesDefs.GROUND, tile):
				candidates.append(tile)
		SimRng.reseed(1777)
		var expected := candidates[SimRng.randi() % candidates.size()]
		SimRng.reseed(1777)
		_assert(patrol_brain._patrol_tile(patrol.world, "patrol_bot", patrol_extra) == expected,
			"shoo patrol keeps its seeded tile on %s" % ["first choice", "cached choice", "changed ground"][change])
	patrol.done()

	# --- energy: a bot is metered like everybody else --------------------------
	#
	# Plan §4's third criterion. The meter is the registry's (`spend_actor_energy`),
	# the floor is Q-11's soft one — an exhausted actor clamps at 0 and its action
	# still resolves, because nothing in phase 1 is a wall — and the day turn
	# refills it exactly as it refills the neighbour's.
	var e := _bot_yard(606)
	BotBrain.deploy(e.world, "work_bot", BotBrain.CONFIG_FOLLOW, Vector2i(20, 12))
	_assert(e.world.energy_of("work_bot") == SimWorld.ACTOR_MAX_ENERGY,
		"a fresh bot has a full meter of its own")
	var till_cost := Tools.get_energy_cost("till")
	e.world.set_tile_state(6, 12, "cleared")
	e.world.apply_action({ "verb": "till", "target": Vector2i(6, 12), "actor": "work_bot" }, e.gs)
	_assert(e.world.energy_of("work_bot") == SimWorld.ACTOR_MAX_ENERGY - till_cost,
		"and spends it on the work, at the same cost her own arm charges")
	var hers: int = e.gs.energy
	_assert(int(e.world.actor(SimWorld.ACTOR_PLAYER).get("energy", 0)) == -1 and e.gs.energy == hers,
		"out of its own pocket — the farmer's meter (which is also the clock) is untouched")
	var work := 0
	while e.world.energy_of("work_bot") > 0 and work < 200:
		work += 1
		e.world.set_tile_state(7, 12, "cleared")
		e.world.apply_action({ "verb": "till", "target": Vector2i(7, 12), "actor": "work_bot" }, e.gs)
	_assert(e.world.energy_of("work_bot") == 0 and e.world.is_exhausted("work_bot"),
		"it runs out, like anybody else who works all day (%d actions)" % work)
	e.world.set_tile_state(8, 12, "cleared")
	var tired := e.world.apply_action(
		{ "verb": "till", "target": Vector2i(8, 12), "actor": "work_bot" }, e.gs)
	_assert(tired.get("ok", false) and e.world.get_tile(8, 12).get("state", "") == "tilled"
			and e.world.energy_of("work_bot") == 0,
		"and an empty tank still does the job at 0 — Q-11's soft floor, for machines too")
	e.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(e.world.energy_of("work_bot") == SimWorld.ACTOR_MAX_ENERGY,
		"the day turning refills it, exactly as it refills the hen and the neighbour")
	e.done()

	# --- the benchmark's fake actor, made real (WI-12's other half) ------------
	#
	# `tools/benchmark_sim.gd` has always applied its day's work as actor "bot",
	# which nobody had registered — the gateway minted a species-less entry for it
	# (`_ensure_actor`). There is a species called `bot` now, so the same
	# unregistered id comes back as one; **the world it produces is identical
	# either way**, which is the thing WI-12 needs to be true before it converts
	# that file to deploy a real one.
	# One run at a time, each from its own reseed: the benchmark's days roll
	# weather off the shared stream, so interleaving two of them would compare a
	# sunny farm against a rainy one and blame the bot.
	var gs_a = load("res://systems/game_state.gd").new()
	gs_a.reset()
	SimRng.reseed(1234)
	var bench_a := SimWorld.new()
	bench_a.generate()
	var applied_a := 0
	for _day_a in 4:
		applied_a += _benchmark_day(bench_a, gs_a, "bot")
	var gs_b = load("res://systems/game_state.gd").new()
	gs_b.reset()
	SimRng.reseed(1234)
	var bench_b := SimWorld.new()
	bench_b.generate()
	BotBrain.deploy(bench_b, "bot", BotBrain.CONFIG_FOLLOW, Vector2i(16, 8))
	var applied_b := 0
	for _day_b in 4:
		applied_b += _benchmark_day(bench_b, gs_b, "bot")
	_assert(applied_a == applied_b and applied_a > 0,
		"the same day's work, applied by an unregistered worker and a real one (%d actions)"
			% applied_a)
	_assert(bench_a.species_of("bot") == SpeciesDefs.BOT
			and bench_a.actor_pos("bot") == Vector2i(-1, -1),
		"an id that names a species is registered as one, standing nowhere (`_ensure_actor`)")
	_assert(_grid_signature(bench_a) == _grid_signature(bench_b),
		"and the farm they leave behind is the same farm, tile for tile")
	_assert(str(SaveGame.capture(bench_a, gs_a)["state"])
			== str(SaveGame.capture(bench_b, gs_b)["state"]),
		"with the same gold, the same harvests and the same day (%d)" % gs_a.day)
	_assert(bench_b.energy_of("bot") == bench_a.energy_of("bot"),
		"and the meter reads the same, because it was always a real meter")
	gs_a.free()
	gs_b.free()

	# --- the net, over a working bot (plan §4's last criterion) ----------------
	#
	# Save mid-session, restore, keep playing with a bot on the farm — her walk
	# recorded, the bot's chase recomputed — and check the whole thing against
	# `SaveGame.replay_report`. It is the strongest statement the repo can make
	# about a new actor: every Action it took is in the log with `brain: true`,
	# the recomputation produced the same Actions at the same ticks, and the two
	# worlds are equal down to the machine's own scratch state.
	#
	# **Both sides restore**, which is not an accident: `SaveGame.restore` calls
	# `schedule_all_brains()` and wakes everybody on the next tick, so a
	# kept-playing world compared against a restored one drifts for reasons that
	# have nothing to do with bots (WI-8a's handoff; still true, still not to be
	# fixed casually).
	var live := _bot_yard(4242, true)
	_bot_crow_ready(live)
	var crow_at := _crow_target_for(live, 1)
	BotBrain.deploy(live.world, "shoo_bot", BotBrain.CONFIG_SHOO, crow_at + Vector2i(0, 2),
		{ "home_x": crow_at.x, "home_y": crow_at.y + 2, "radius": 4.0 })
	BotBrain.deploy(live.world, "follow_bot", BotBrain.CONFIG_FOLLOW, BOT_HER_TILE + Vector2i(1, 1))
	live.tick(30)
	var mid_save = JSON.parse_string(JSON.stringify(SaveGame.capture(live.world, live.gs)))
	_assert(mid_save["world"]["actors"].has("shoo_bot")
			and mid_save["world"]["actors"]["shoo_bot"]["extra"].get("config", "")
				== BotBrain.CONFIG_SHOO,
		"a bot is in the save like anybody else, with its configuration in its own entry")
	live.done()

	var gs_cont2 = load("res://systems/game_state.gd").new()
	gs_cont2.reset()
	var w2 := SimWorld.new()
	_assert(SaveGame.restore(mid_save, w2, gs_cont2), "the mid-session save restores")
	SaveGame.resume_stream(mid_save, w2.gen_seed)
	var log2 := ReplayLog.new()
	log2.start_from_save(mid_save, w2.gen_seed)

	# Her half of the continued session: a walk, recorded crossing by crossing,
	# and the action that moves T-20's clock and brings the bird.
	var here := w2.actor_pos(SimWorld.ACTOR_PLAYER)
	for i in 4:
		var to := here + Vector2i(i + 1, 0)
		w2.set_actor_pos(SimWorld.ACTOR_PLAYER, to, "right")
		log2.record_walk("step", "right", to, w2.clock.tick)
		for t in w2.advance_ticks(4, gs_cont2):
			_record_brain_step(log2, t)
	var till_at := Vector2i(5, 14)
	w2.set_tile_state(till_at.x, till_at.y, "cleared")
	var r2 := w2.apply_action({ "verb": "till", "target": till_at, "actor": "player" }, gs_cont2)
	if r2.get("ok", false):
		log2.record({ "verb": "till", "target": till_at, "actor": "player" }, r2, w2.clock.tick)
	_assert(w2.has_actor(SimWorld.ACTOR_CROW), "the continued session's action brings the crow")
	var lived2 := 0
	while lived2 < 900 and w2.has_actor(SimWorld.ACTOR_CROW):
		for t in w2.advance_ticks(10, gs_cont2):
			_record_brain_step(log2, t)
		log2.mark_tick(w2.clock.tick)
		lived2 += 10
	log2.mark_tick(w2.clock.tick)
	_assert(not w2.has_actor(SimWorld.ACTOR_CROW),
		"the visit is over inside the continued session (%d ticks)" % lived2)
	var bot_scares := 0
	for entry in log2.entries:
		if String(entry.get("verb", "")) == "crow_scared" and String(entry.get("by", "")) == "shoo_bot":
			bot_scares += 1
			_assert_quiet(bool(entry.get("brain", false)) and entry.has("tick"),
				"the bot's Action is stamped with its tick and marked as a brain's")
	_flush_quiet("the log holds the bot's own Actions, in the format the net checks")
	_assert(bot_scares == 1, "and the bot ended the visit rather than the crow's appetite")
	var end2 = JSON.parse_string(JSON.stringify(SaveGame.capture(w2, gs_cont2)))
	var report2 := SaveGame.replay_report(log2, end2)
	_assert(report2["matched"],
		"and the continued session replays to the identical outcome %s" % report2["divergence"])
	gs_cont2.free()



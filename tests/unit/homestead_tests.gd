# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

func test_crow_scared_verb() -> void:
	print("\n--- crow_scared verb Tests ---")
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(11)
	world.generate()
	var r := world.apply_action({ "verb": "crow_scared", "actor": "crow" }, GameState)
	_assert(r.ok and GameState.crows_scared == 1, "crow_scared increments counter")
	world.apply_action({ "verb": "crow_scared", "actor": "crow" }, GameState)
	_assert(GameState.crows_scared == 2, "counter accumulates")
	r = world.apply_action({ "verb": "crow_scared", "actor": "crow" })
	_assert(not r.ok, "crow_scared without gs refused")

func test_vignette_multiday() -> void:
	print("\n--- Vignette: harvest-first, multi-day (T-3/T-4/T-5, Q-33) Tests ---")

	# Q-33 replaced a vignette that opened on a **weed** — a chore, and the least
	# motivating verb in the game. It taught three verbs and zero goals: a player
	# who finished it had learned which pixels respond, not what the game is for.
	# The chain is now taught backwards from the harvest, and the day-2 payoff is
	# what makes day 1 mean anything, which is why the three stories shipped
	# together.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(21)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()

	var gate := WorldLayout.gate_of("neighbour")
	var yard_tile := Vector2i(3, 3)
	var plot_tile := Vector2i(15, 4)

	# While the cold open is still running, the neighbour is the show and the
	# vignette says nothing at all.
	_assert(not VignetteState.is_active(world, gs, yard_tile),
		"the vignette is silent while the gate is still closed")

	ColdOpen.run(world, world, gs)
	_assert(gs.takeover_day == gs.day, "takeover is anchored where the cold open ends")

	# Beat 0 — the handoff. Standing in her own yard, the only thing glowing is
	# the way out; the ripe crop beyond it is the reason to take it.
	_assert(not world.player_left_yard(), "before she has ever crossed, the latch is unset")
	var beat0 := VignetteState.target_tiles(world, gs, yard_tile)
	_assert(beat0.size() == 1 and beat0[0] == gate, "beat 0 highlights the opened gate")

	# T-35 — and crossing it once completes the beat forever. The crossing is a
	# position write (the gate tile is the first non-yard ground she can stand
	# on), and the latch rides her registry entry from there.
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, gate)
	_assert(world.player_left_yard(), "stepping onto the gate tile latches the crossing")
	var after_cross := VignetteState.target_tiles(world, gs, yard_tile)
	_assert(not after_cross.has(gate),
		"once crossed, standing home-side never re-arms the gate beat (T-35)")

	# Beat 1 — the ripe crop. It cannot fail, cannot be refused and costs a tap:
	# the safest possible room, and the player is paid before she is asked.
	var beat1 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat1.size() == 1, "beat 1 highlights exactly one tile")
	var ripe: Vector2i = beat1[0]
	_assert(world.get_tile(ripe.x, ripe.y).state == "ready", "and it is the ripe crop")
	_assert(absi(ripe.x - gate.x) + absi(ripe.y - gate.y) >= 2,
		"the ripe crop is not adjacent to the gate, so beat 1 teaches movement implicitly")

	world.apply_action({ "verb": "harvest", "target": ripe, "actor": "player" }, gs)

	# Beat 2 — plant. One tilled tile, and only one.
	var beat2 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat2.size() == 1, "beat 2 highlights exactly one tilled tile")
	var to_plant: Vector2i = beat2[0]
	_assert(world.get_tile(to_plant.x, to_plant.y).state == "tilled", "and it is tilled")

	world.apply_action({ "verb": "plant", "target": to_plant, "seed_type": "wheat", "actor": "player" }, gs)

	# Beat 3 — water the thing she just planted.
	var beat3 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat3.size() == 1 and beat3[0] == to_plant, "beat 3 highlights the tile she just planted")

	world.apply_action({ "verb": "water", "target": to_plant, "actor": "player" }, gs)

	# Beat 4 (T-4) — bed, and only once nothing else is asking. This is what turns
	# "I did some things" into "I did some things and then something happened";
	# without it the first session has no resolution.
	#
	# **What it points at is the way to bed** (2026-09-06, the door). The cot is in
	# a room now, so out on the farm the beat aims her at her own front door and
	# inside it aims at the bed — the same one answer the dusk glow and the HUD's
	# bed button take, so the three can never point three different ways.
	var beat4 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(beat4.size() == 1, "beat 4 highlights exactly one thing")
	_assert(world.objects[beat4[0].y][beat4[0].x] == WorldLayout.HOUSE_DOOR,
		"and out on the farm it is the house door — the way to a bed she cannot see from here")
	# ...and asked from the room the bed is in, it is the bed itself.
	var by_the_bed: Vector2i = world.find_object("cot") + Vector2i(0, 1)
	var beat4_inside := VignetteState.target_tiles(world, gs, by_the_bed)
	_assert(beat4_inside.size() == 1
			and world.objects[beat4_inside[0].y][beat4_inside[0].x] == "cot",
		"indoors, the same beat points at the cot")
	# T-35's reported moment, in miniature: she is standing in the yard when this
	# beat should fire, and what she must see there is the way to bed — never the
	# gate again.
	var beat4_home := VignetteState.target_tiles(world, gs, yard_tile)
	_assert(beat4_home.size() == 1
			and world.objects[beat4_home[0].y][beat4_home[0].x] == WorldLayout.HOUSE_DOOR,
		"asked from the yard, bedtime points at the way to bed, not the gate (T-35)")

	# T-4: day 1's phase ends by **sleeping**, not by the day counter passing 1.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(gs.play_day() == 2, "sleeping moved her to play-day 2")

	# T-5 — the payoff. The neighbour's last growing tile ripened overnight, and
	# it is the only thing glowing.
	var day2 := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(day2.size() == 1, "day 2 opens on exactly one target")
	_assert(world.get_tile(day2[0].x, day2[0].y).state == "ready", "and it is the newly ripe tile")
	world.apply_action({ "verb": "harvest", "target": day2[0], "actor": "player" }, gs)

	# Then the half-prepared row, highlighted **together** — the first honest read
	# on whether chaining a swipe along a row feels right (the Q-30 leftover).
	var row := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(row.size() >= 2, "the remaining tilled tiles are highlighted together, not in sequence")
	for t2 in row:
		_assert(world.get_tile(t2.x, t2.y).state == "tilled", "every tile in the group is tilled")
		world.apply_action({ "verb": "plant", "target": t2, "seed_type": "wheat", "actor": "player" }, gs)

	# ...and watering the row is a group too, for the same reason.
	var wet := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(wet.size() >= 2, "the row she just planted is highlighted together for watering")
	for t3 in wet:
		world.apply_action({ "verb": "water", "target": t3, "actor": "player" }, gs)

	# One new verb, and only one: till. The chain extends one link backwards.
	var till_beat := VignetteState.target_tiles(world, gs, plot_tile)
	_assert(till_beat.size() == 1, "the day-2 till beat is a single tile")
	_assert(world.get_tile(till_beat[0].x, till_beat[0].y).state == "cleared", "and it is cleared ground")
	world.apply_action({ "verb": "till", "target": till_beat[0], "actor": "player" }, gs)

	# From play-day 3 the game stops teaching and starts trusting. Asserted
	# regardless of world state, because "silent from day 3" is the promise.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(gs.play_day() == 3, "and on to play-day 3")
	_assert(not VignetteState.is_active(world, gs, plot_tile),
		"the vignette is over for good from play-day 3")
	world.set_tile_state(5, 3, "tilled")
	_assert(not VignetteState.is_active(world, gs, plot_tile),
		"and no amount of fresh world state brings it back")
	gs.free()


func test_gate_lesson_latch_regression() -> void:
	print("\n--- T-35: the gate lesson latches (her 2026-08-31 bedtime window) Tests ---")

	# The report, live from the couch on 2026-08-31: her first prompted trip to
	# bed, the pointer aimed at the GATE, and she followed it out of the yard —
	# 22 seconds of field pokes and a shop detour before she found the bed
	# herself. The trace window is 1m47s–2m20s; in the replay that is the walk
	# entries between her day-1 planting and her first sleep (ticks ~380–511),
	# ending at (3,4), beside the cot. This replays her session to the moment
	# just before that sleep and asks what was glowing.
	var fixture := ReplayLog.load_from("res://playtests/2026-08-31_233943/session_replay.json")
	_assert(fixture != null, "her session replay is on the shelf")

	# Cut just before her first sleep: the cold open's own sleeps predate any
	# player entry, so "the first sleep after she has acted" finds bedtime
	# whatever the cold open spent getting there.
	var seen_player := false
	var cut := -1
	for i in fixture.entries.size():
		var e: Dictionary = fixture.entries[i]
		if String(e.get("actor", "")) == "player":
			seen_player = true
		if seen_player and String(e.get("verb", "")) == "sleep":
			cut = i
			break
	_assert(cut > 0, "her first bedtime is in the log")

	var cut_tick := int(fixture.entries[cut - 1].get("tick", 0))
	fixture.entries.resize(cut)
	fixture.end_tick = cut_tick

	var world := SimWorld.new()
	var gs = load("res://systems/game_state.gd").new()
	fixture.apply_to(world, gs)

	_assert(gs.play_day() == 1, "the cut lands on her first play-day, at bedtime")
	_assert(world.player_left_yard(),
		"by bedtime she had long since crossed the gate, and the sim knows it")
	var at := world.actor_pos(SimWorld.ACTOR_PLAYER)
	_assert(String(WorldLayout.parcel_at(at, world.layout).get("id", "")) == "yard",
		"she is standing home-side, exactly where the bug fired")

	var glowing := VignetteState.target_tiles(world, gs, at)
	var gate := WorldLayout.gate_of("neighbour")
	_assert(not glowing.has(gate),
		"the gate does not glow at her again — the lesson latched (T-35)")
	_assert(glowing.size() == 1
			and world.objects[glowing[0].y][glowing[0].x] == WorldLayout.HOUSE_DOOR,
		"what glows at her bedtime is the way to bed — from the yard, her own front door")

	# And the latch is part of the farm, not the run: it survives a save.
	var reloaded := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	SaveGame.restore(SaveGame.capture(world, gs), reloaded, gs2)
	_assert(reloaded.player_left_yard(), "the latch rides the save with her registry entry")
	gs.free()
	gs2.free()


func test_takeover_layout() -> void:
	print("\n--- The takeover contract WI-4 derives its beats from Tests ---")

	# The vignette derives every beat from world state, so generation has to
	# *guarantee* the state. This is that guarantee, checked across seeds: what
	# the player inherits must read left-to-right as the whole production chain
	# — cleared, tilled, seeded, growing, ready — because that is environmental
	# storytelling she cannot skip and does not need to have watched.
	var gate := WorldLayout.gate_of("neighbour")
	var checked := 0
	for seed_value in range(1, 21):
		var world := SimWorld.new()
		SimRng.reseed(seed_value)
		world.generate()
		var gs = load("res://systems/game_state.gd").new()
		var res := ColdOpen.run(world, world, gs)
		var ok_run: bool = res.get("ok", false)

		var ready: Array[Vector2i] = []
		var tilled: Array[Vector2i] = []
		var seeded_wet := 0
		var growing_wet := 0
		for p in WorldLayout.parcels(world.layout):
			if String(p.get("id", "")) != "neighbour":
				continue
			for r in p.get("rects", []):
				var rect: Rect2i = r
				for ty in range(rect.position.y, rect.end.y):
					for tx in range(rect.position.x, rect.end.x):
						var t: Dictionary = world.tiles[ty][tx]
						match String(t.get("state", "")):
							"ready": ready.append(Vector2i(tx, ty))
							"tilled": tilled.append(Vector2i(tx, ty))
							"seeded":
								if t.get("watered_today", false): seeded_wet += 1
							"growing":
								if t.get("watered_today", false): growing_wet += 1

		var pass_row: bool = ok_run and ready.size() == 1 and tilled.size() >= 2 \
			and seeded_wet >= 1 and growing_wet >= 1 \
			and absi(ready[0].x - gate.x) + absi(ready[0].y - gate.y) >= 2 \
			and gs.takeover_day == 1 + ColdOpen.COLD_OPEN_DAYS
		if pass_row:
			checked += 1
		gs.free()
	_assert(checked == 20, "the takeover contract holds for every seed 1..20 (%d/20)" % checked)

func test_phase1_proof() -> void:
	print("\n--- Phase-1 capability proof (Q-12) Tests ---")
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(31)
	world.generate()

	# Negative: counters met but obstacles remain (vignette weed included)
	GameState.total_shipped = SimWorld.PHASE1_SHIPPED_TARGET
	GameState.crows_scared = SimWorld.PHASE1_SCARED_TARGET
	var r := world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(r.ok and not r.get("phase1_complete_now", false), "proof not met while yard has obstacles")
	_assert(not GameState.phase1_complete, "flag stays false")

	# Same contract as the tool proofs: phase1_progress is what _phase1_proof_met
	# consults, so the numbers a playtester reads are the numbers being tested.
	var before_clear: Dictionary = world.phase1_progress(GameState)
	_assert(int(before_clear.obstacles_left) > 0, "progress reports the obstacles still standing")
	_assert(not bool(before_clear.met), "and agrees the proof is not met")

	# Clear every obstacle, then sleep again
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(world.tiles[ty][tx].get("state", "")).begins_with("obstacle"):
				world.set_tile_state(tx, ty, "cleared")
	r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(r.get("phase1_complete_now", false), "proof met once yard cleared + counters reached")
	var after_clear: Dictionary = world.phase1_progress(GameState)
	_assert(int(after_clear.obstacles_left) == 0, "and no obstacles are left in reach")
	_assert(bool(after_clear.met), "and the readout agrees the proof is met")
	_assert(int(after_clear.shipped_target) == SimWorld.PHASE1_SHIPPED_TARGET,
		"and reports the real targets rather than its own copy of them")
	_assert(GameState.phase1_complete, "flag set")

	r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(not r.get("phase1_complete_now", false), "celebration fires exactly once")

	# Below-threshold counters never pass even on a cleared yard
	GameState.reset()
	GameState.total_shipped = SimWorld.PHASE1_SHIPPED_TARGET - 1
	GameState.crows_scared = SimWorld.PHASE1_SCARED_TARGET
	r = world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(not GameState.phase1_complete, "shipping below target does not complete phase 1")


func test_autotile() -> void:
	print("\n--- Autotile neighbour-mask Tests (tilled soil merging) ---")

	# Bit layout must stay in lockstep with tools/gen_terrain_autotile.py.
	_assert(Autotile.N == 1 and Autotile.E == 4 and Autotile.S == 16 and Autotile.W == 64,
		"side bit values are N=1 E=4 S=16 W=64")

	var none := Autotile.compute_mask(false, false, false, false, false, false, false, false)
	_assert(none == 0, "isolated tile has mask 0")

	var all_n := Autotile.compute_mask(true, true, true, true, true, true, true, true)
	_assert(all_n == 255, "fully surrounded tile has mask 255")

	# Sides are independent and land in the right bits.
	_assert(Autotile.compute_mask(true, false, false, false, false, false, false, false) == Autotile.N,
		"north-only neighbour sets just N")
	_assert(Autotile.compute_mask(false, false, true, false, false, false, false, false) == Autotile.E,
		"east-only neighbour sets just E")
	_assert(Autotile.compute_mask(false, false, false, false, true, false, false, false) == Autotile.S,
		"south-only neighbour sets just S")
	_assert(Autotile.compute_mask(false, false, false, false, false, false, true, false) == Autotile.W,
		"west-only neighbour sets just W")

	# Corner gating: a diagonal without both its sides must not set its bit.
	var lone_ne := Autotile.compute_mask(false, true, false, false, false, false, false, false)
	_assert(lone_ne == 0, "diagonal alone never sets a corner bit")
	var ne_missing_side := Autotile.compute_mask(true, true, false, false, false, false, false, false)
	_assert(ne_missing_side == Autotile.N, "NE ignored when east side is open")
	var ne_full := Autotile.compute_mask(true, true, true, false, false, false, false, false)
	_assert(ne_full == Autotile.N | Autotile.E | Autotile.NE, "NE set when N, E and NE all present")
	# The inner-corner case the old table collapsed: both sides, no diagonal.
	var inner := Autotile.compute_mask(true, false, true, false, false, false, false, false)
	_assert(inner == Autotile.N | Autotile.E, "inner corner keeps sides without the diagonal bit")

	# Every distinct neighbourhood must land on a distinct tile — the property the
	# old 13-tile table violated for 35 of the 47 reachable configurations.
	var seen: Dictionary = {}
	var reachable := 0
	for m in 256:
		var n := (m & Autotile.N) != 0
		var e := (m & Autotile.E) != 0
		var s := (m & Autotile.S) != 0
		var w := (m & Autotile.W) != 0
		var ne := (m & Autotile.NE) != 0
		var se := (m & Autotile.SE) != 0
		var sw := (m & Autotile.SW) != 0
		var nw := (m & Autotile.NW) != 0
		if Autotile.compute_mask(n, ne, e, se, s, sw, w, nw) != m:
			continue  # not reachable under corner gating
		reachable += 1
		var c := Autotile.atlas_coord(m)
		var key := "%d,%d" % [c.x, c.y]
		_assert(not seen.has(key), "mask %d has its own tile" % m)
		seen[key] = m
		_assert(c.x >= 0 and c.x < 16 and c.y >= 0 and c.y < 16, "mask %d maps inside the sheet" % m)
	_assert(reachable == 47, "47 neighbourhoods are reachable, got %d" % reachable)

	# Watered variant is the same tile shifted into the second block.
	for m in [0, 5, 47, 255]:
		var dry := Autotile.atlas_coord(m, false)
		var wet := Autotile.atlas_coord(m, true)
		_assert(wet.y == dry.y and wet.x == dry.x + 16, "watered mask %d offsets by 16 columns" % m)

	# State membership drives the whole thing.
	_assert(Autotile.is_soil("tilled") and Autotile.is_soil("seeded")
		and Autotile.is_soil("growing") and Autotile.is_soil("ready"),
		"all four soil states join the tilled region")
	_assert(not Autotile.is_soil("cleared") and not Autotile.is_soil("obstacle_rock")
		and not Autotile.is_soil("border"),
		"grass, obstacles and border are not soil")


func test_autotile_sheet() -> void:
	print("\n--- Autotile sheet Tests (art matches the mask) ---")
	var tex: Texture2D = load("res://assets/sprites/generated/terrain_dirt.png")
	_assert(tex != null, "terrain_dirt.png loads")
	var img: Image = tex.get_image()
	_assert(img.get_width() == 512 and img.get_height() == 256,
		"sheet is 512x256 (256 masks x tilled/watered)")

	# For each reachable mask, an open side must be drawn as a darker rim and a
	# closed side must not be. This is what actually makes plots merge on screen.
	var checked := 0
	var wrong := 0
	for m in 256:
		var n := (m & Autotile.N) != 0
		var e := (m & Autotile.E) != 0
		var s := (m & Autotile.S) != 0
		var w := (m & Autotile.W) != 0
		if Autotile.compute_mask(n, (m & Autotile.NE) != 0, e, (m & Autotile.SE) != 0,
				s, (m & Autotile.SW) != 0, w, (m & Autotile.NW) != 0) != m:
			continue
		for watered in [false, true]:
			var c := Autotile.atlas_coord(m, watered)
			var ox := c.x * 16
			var oy := c.y * 16
			var body := img.get_pixel(ox + 8, oy + 8)
			var probes := [
				[img.get_pixel(ox + 8, oy), not n, "N"],
				[img.get_pixel(ox + 8, oy + 15), not s, "S"],
				[img.get_pixel(ox, oy + 8), not w, "W"],
				[img.get_pixel(ox + 15, oy + 8), not e, "E"],
			]
			for p in probes:
				var col: Color = p[0]
				var expect_rim: bool = p[1]
				# A rim pixel is materially darker than the tile body.
				var is_rim: bool = col.v < body.v * 0.85
				checked += 1
				if is_rim != expect_rim:
					wrong += 1
	_assert(wrong == 0, "every open side is rimmed and every closed side is not (%d/%d wrong)" % [wrong, checked])
	_assert(checked == 47 * 2 * 4, "checked all 47 masks x 2 variants x 4 sides, got %d" % checked)

	# Watered soil must be obviously darker than dry soil at a glance (kid-legible).
	var dry_body := img.get_pixel(Autotile.atlas_coord(255, false).x * 16 + 8, 8)
	var wet_body := img.get_pixel(Autotile.atlas_coord(255, true).x * 16 + 8, 8)
	_assert(wet_body.v < dry_body.v * 0.7,
		"watered soil is much darker than dry (dry v=%.2f wet v=%.2f)" % [dry_body.v, wet_body.v])


func test_title_summary() -> void:
	print("\n--- Title screen Continue-card summary Tests ---")
	# A real captured save must surface the figures the card advertises.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(5)
	world.generate()
	GameState.day = 12
	GameState.gold = 340
	GameState.total_shipped = 14
	GameState.crows_scared = 2
	var save := SaveGame.capture(world, GameState)
	var sum: Dictionary = SaveGame.summarize(save)
	_assert(sum.get("day", 0) == 12, "summary reports the saved day")
	_assert(sum.get("gold", 0) == 340, "summary reports gold")
	_assert(sum.get("shipped", 0) == 14, "summary reports crops shipped")
	_assert(sum.get("scared", 0) == 2, "summary reports crows scared")
	_assert(sum.get("phase1", true) == false, "phase 1 incomplete before the proof")

	GameState.phase1_complete = true
	_assert(SaveGame.summarize(SaveGame.capture(world, GameState)).get("phase1", false),
		"summary reports a completed homestead")

	# Anything unreadable must summarise to nothing, so the screen offers a
	# fresh start instead of a Continue button that cannot load.
	_assert(SaveGame.summarize({}).is_empty(), "empty save summarises to nothing")
	_assert(SaveGame.summarize({"version": 1}).is_empty(), "save without state summarises to nothing")
	_assert(SaveGame.summarize({"state": "not-a-dict"}).is_empty(), "malformed state summarises to nothing")

	# Counters the card renders as progress must match the sim's proof targets.
	_assert(SimWorld.PHASE1_SHIPPED_TARGET > 0 and SimWorld.PHASE1_SCARED_TARGET > 0,
		"phase-1 targets exist for the card to count toward")
	GameState.reset()


func test_approach_adjacent() -> void:
	print("\n--- Approach / move-until-in-range Tests (Q-30) ---")
	var world := SimWorld.new()
	SimRng.reseed(11)
	world.generate()
	for ty in range(2, 12):
		for tx in range(2, 14):
			world.set_tile_state(tx, ty, "cleared")

	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	var goal := Vector2i(6, 6)

	# Already beside it: no walking at all.
	_assert(Pathfinding.find_path_toward(farm, goal + Vector2i(0, 1), goal).is_empty(),
		"already adjacent needs no movement")
	_assert(Pathfinding.find_path_toward(farm, goal + Vector2i(-1, 0), goal).is_empty(),
		"adjacent from the west needs no movement either")

	# Standing on it: a single step off, so she can turn back and work it.
	var off: Array = Pathfinding.find_path_toward(farm, goal, goal)
	_assert(off.size() == 1, "standing on the target yields one step off it")
	_assert(absi(off[0].x - goal.x) + absi(off[0].y - goal.y) == 1,
		"the step off lands on an adjacent tile")

	# From a distance the route heads at the goal itself; the caller halts on
	# adjacency, so the approach side falls out of the route rather than being
	# chosen up front (choosing up front made her walk past the natural side and
	# pivot on arrival).
	var diag: Array = Pathfinding.find_path_toward(farm, Vector2i(3, 3), goal)
	_assert(not diag.is_empty(), "a distant tap produces a path")
	_assert(diag[diag.size() - 1] == goal, "the route targets the goal itself")

	var first_adjacent := -1
	for i in diag.size():
		var w: Vector2i = diag[i]
		if absi(w.x - goal.x) + absi(w.y - goal.y) == 1:
			first_adjacent = i
			break
	_assert(first_adjacent >= 0, "the route passes through a tile adjacent to the goal")
	_assert(first_adjacent == diag.size() - 2,
		"she becomes adjacent exactly one step before the goal, so halting there never overshoots")

	# Unreachable target: no path, and the caller acts where it stands.
	for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]:
		world.set_tile_state(goal.x + d.x, goal.y + d.y, "obstacle_rock")
	_assert(Pathfinding.find_path_toward(farm, Vector2i(3, 3), goal).is_empty(),
		"a walled-in target returns empty so the action still fires in place")
	farm.free()


func test_approach_ignores_inventory() -> void:
	print("\n--- Approach independent of inventory (Q-30) Tests ---")
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(3)
	world.generate()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	var t := Vector2i(6, 6)
	world.set_tile_state(t.x, t.y, "tilled")

	# With seeds, planting resolves and the tile is workable.
	GameState.pouch["wheat"] = 5
	GameState.selected_seed_type = "wheat"
	_assert(not ActionRouter.resolve(farm, GameState, t, t, false, null).is_empty(),
		"planting resolves while she has seeds")
	_assert(ActionRouter.is_workable(farm, t), "a tilled tile is workable")

	# Out of seeds, resolve correctly refuses — but the tile must still count as
	# workable, or she walks on top of it instead of up to it.
	GameState.pouch["wheat"] = 0
	_assert(ActionRouter.resolve(farm, GameState, t, t, false, null).is_empty(),
		"planting does not resolve with an empty pouch")
	_assert(ActionRouter.is_workable(farm, t),
		"the tile is still workable with an empty pouch, so the approach is unchanged")

	# Same for the other exhaustible resources.
	world.set_tile_state(t.x, t.y, "seeded", "wheat")
	GameState.watering_can_charges = 0
	_assert(ActionRouter.is_workable(farm, t), "a dry crop is workable with an empty can")
	world.set_tile_state(t.x, t.y, "cleared")
	GameState.energy = 0
	GameState.hard_energy = true
	_assert(ActionRouter.is_workable(farm, t), "bare soil is workable with no energy")

	# Things with genuinely nothing to do are walked onto normally.
	world.set_tile_state(t.x, t.y, "border")
	_assert(not ActionRouter.is_workable(farm, t), "the map border is not workable")
	GameState.reset()
	farm.free()


func test_session_trace() -> void:
	print("\n--- SessionTrace Tests ---")

	# Round-trip: a trace written by a session must read back as the same thing.
	# parse()/summarize() shipped 2026-08-27 with no coverage at all; the M1 gate
	# playtest is not the moment to discover the reader is wrong.
	var tr := SessionTrace.new()
	tr.start(12345, false)
	_assert(tr.header().get("gen_seed", 0) == 12345, "header carries the seed")
	_assert(tr.header().get("continued", true) == false, "header carries fresh-farm flag")

	tr.tap("tap", Vector2i(3, 2), Vector2i(2, 2), 0, "till", "acted")
	tr.act(Vector2i(3, 2), "player", "till", true)
	tr.tap("tap", Vector2i(9, 9), Vector2i(2, 2), 0, "", "none")
	tr.tap("tap", Vector2i(9, 9), Vector2i(2, 2), 0, "", "none")
	tr.tap("tap", Vector2i(9, 9), Vector2i(2, 2), 0, "", "none")
	tr.tap("tap", Vector2i(5, 5), Vector2i(2, 2), 3, "plant", "refused", "no_seeds")
	tr.tap("tap", Vector2i(30, 1), Vector2i(2, 2), 0, "", "unreachable")

	var parsed := SessionTrace.parse(tr.to_jsonl())
	_assert(parsed["header"].get("gen_seed", 0) == 12345, "parsed header round-trips")
	_assert(parsed["entries"].size() == 7, "parsed all seven entries")

	var sum := SessionTrace.summarize(parsed)
	_assert(int(sum["taps"]) == 6, "counts every tap")
	# 3 x none + 1 x unreachable are dead; the refusal is counted separately.
	_assert(int(sum["dead_taps"]) == 4, "dead taps counted")
	_assert(int(sum["unreachable"]) == 1, "unreachable taps counted separately")
	_assert(int(sum["refused"]) == 1, "refusals counted")
	_assert(sum["reasons"].get("no_seeds", 0) == 1, "refusal reason recorded")
	_assert(sum["stuck_tiles"].has("9,9"), "a tile tapped 3x with no effect is flagged")
	_assert(not sum["stuck_tiles"].has("3,2"), "a tile that worked is not flagged")

	# T-18/T-19 (Q-42): an acknowledged tap is NOT a dead tap. The 2026-08-28
	# session's headline number was 20 dead taps holding the watering can over
	# crops already watered that day; if "satisfied" were still counted as dead,
	# the fix would be invisible in the one measurement that is meant to show it —
	# and those tiles would sit in the stuck-tile list for ever.
	var ack := SessionTrace.new()
	ack.start(7, false)
	ack.tap("tap", Vector2i(6, 3), Vector2i(6, 4), 4, "", "satisfied", "already_watered")
	ack.tap("tap", Vector2i(6, 3), Vector2i(6, 4), 4, "", "satisfied", "already_watered")
	ack.tap("tap", Vector2i(6, 3), Vector2i(6, 4), 4, "", "satisfied", "already_watered")
	ack.tap("tap", Vector2i(6, 1), Vector2i(6, 2), 4, "refill", "satisfied", "can_full")
	ack.tap("tap", Vector2i(8, 8), Vector2i(6, 4), 4, "", "none")
	var ack_parsed := SessionTrace.parse(ack.to_jsonl())
	var ack_sum := SessionTrace.summarize(ack_parsed)
	_assert(int(ack_sum["taps"]) == 5, "acknowledged taps are still taps")
	_assert(int(ack_sum["satisfied"]) == 4, "acknowledged taps counted as their own outcome")
	_assert(int(ack_sum["dead_taps"]) == 1, "and they are NOT dead taps — only the real one is")
	_assert(int(ack_sum["refused"]) == 0, "nor refusals — a good state is not a refusal")
	_assert(int(ack_sum["satisfied_reasons"].get("already_watered", 0)) == 3,
		"the acknowledgement reason is recorded")
	_assert(int(ack_sum["satisfied_reasons"].get("can_full", 0)) == 1,
		"and the well's full can is its own reason")
	_assert(not ack_sum["stuck_tiles"].has("6,3"),
		"a tile tapped 3x and answered every time is not a stuck tile")
	var ack_rep := SessionTrace.teaching_report(ack_parsed)
	_assert(int(ack_rep["outcomes"].get("satisfied", 0)) == 4,
		"teaching_report tallies satisfied taps as their own row")
	_assert(SessionTrace.dead_tap_tools(ack_parsed).get(4, 0) == 1,
		"dead_tap_tools counts only the genuinely dead tap, not the answered ones")
	_assert(SessionTrace.tile_history(ack_parsed, "6,3")["outcomes"].get("satisfied", 0) == 3,
		"tile_history shows worked-then-acknowledged instead of worked-then-dead (T-19)")

	# An unreachable tap is a dead tap. Before 2026-08-28 player.gd never recorded
	# one at all, so this is the regression guard for the analysis half.
	var only_unreachable := SessionTrace.parse(
		'{"version":1,"gen_seed":1,"continued":false}\n'
		+ '{"t":10,"kind":"tap","tile":[30,1],"at":[2,2],"out":"unreachable","verb":""}\n')
	_assert(int(SessionTrace.summarize(only_unreachable)["dead_taps"]) == 1,
		"an unreachable tap counts as dead")

	# teaching_report: when each lesson first landed, and where she stopped.
	var timed := SessionTrace.parse(
		'{"version":1,"gen_seed":1,"continued":false}\n'
		+ '{"t":500,"kind":"tap","tile":[3,2],"at":[2,2],"out":"acted","verb":"harvest"}\n'
		+ '{"t":520,"kind":"act","tile":[3,2],"actor":"player","verb":"harvest","ok":true}\n'
		+ '{"t":600,"kind":"act","tile":[3,2],"actor":"player","verb":"harvest","ok":true}\n'
		+ '{"t":15000,"kind":"tap","tile":[4,2],"at":[2,2],"out":"acted","verb":"plant"}\n'
		+ '{"t":15100,"kind":"act","tile":[4,2],"actor":"chicken","verb":"lay_egg","ok":true}\n'
		+ '{"t":15200,"kind":"act","tile":[4,2],"actor":"player","verb":"plant","ok":true}\n')
	var rep := SessionTrace.teaching_report(timed)
	_assert(int(rep["time_to_first_tap_ms"]) == 500, "time to first tap")
	_assert(int(rep["first_use"]["harvest"]) == 520, "first successful harvest is the first one")
	_assert(int(rep["first_use"]["plant"]) == 15200, "first successful plant recorded")
	_assert(not rep["first_use"].has("lay_egg"),
		"a chicken laying an egg is not the player learning a verb")
	_assert(rep["stalls"].size() == 1, "the 14.5s gap between taps is a stall")
	_assert(int(rep["longest_stall_ms"]) == 14500, "longest stall measured")
	_assert(int(rep["duration_ms"]) == 15200, "duration is the last stamp")
	_assert(int(rep["outcomes"]["acted"]) == 2, "outcomes tallied by kind")

	# A refused action arriving seconds after its tap must not count as a lesson.
	var refused_only := SessionTrace.parse(
		'{"version":1,"gen_seed":1,"continued":false}\n'
		+ '{"t":100,"kind":"act","tile":[1,1],"actor":"player","verb":"plant","ok":false,"why":"no_seeds"}\n')
	_assert(not SessionTrace.teaching_report(refused_only)["first_use"].has("plant"),
		"a refused action is not a first successful use")

	# Degenerate inputs must not crash the reader mid-playtest.
	var empty := SessionTrace.parse("")
	_assert(empty["entries"].is_empty(), "empty text parses to no entries")
	_assert(int(SessionTrace.summarize(empty)["taps"]) == 0, "empty trace summarises to zero")
	_assert(int(SessionTrace.teaching_report(empty)["time_to_first_tap_ms"]) == -1,
		"empty trace reports no first tap")
	_assert(int(SessionTrace.summarize({})["taps"]) == 0, "summarize tolerates a missing entries key")


func test_crow_readiness() -> void:
	print("\n--- Crow readiness gate (T-2) Tests ---")

	# The rule design/13 §4 asks for: no pest until she has met a harvest, and
	# has enough planted that losing one is affordable. Day is a backstop.
	_assert(not SimWorld.may_spawn_crow(1, 5, 10), "no crow on day 1, however well she is doing")
	_assert(not SimWorld.may_spawn_crow(2, 5, 10), "no crow on day 2 either")
	_assert(not SimWorld.may_spawn_crow(3, 0, 10), "no crow before she has harvested anything")
	_assert(not SimWorld.may_spawn_crow(3, 1, 2), "no crow while only two crops are planted")
	_assert(SimWorld.may_spawn_crow(3, 1, 3), "a crow may come once all three conditions hold")
	_assert(SimWorld.may_spawn_crow(9, 40, 30), "and keeps coming later")

	# The acceptance criterion stated in the roadmap, asserted directly: a fresh
	# save cannot see a crow at any point across days 1 and 2.
	var day1_2_clear := true
	for d in [1, 2]:
		for h in range(0, 6):
			for pl in range(0, 12):
				if SimWorld.may_spawn_crow(d, h, pl):
					day1_2_clear = false
	_assert(day1_2_clear, "no combination of progress permits a crow on day 1 or 2")

	# count_planted feeds the gate, so it has to agree with what a crow can target.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(7)
	world.generate()
	var before := world.count_planted()
	world.tiles[3][6]["state"] = "seeded"
	world.tiles[3][7]["state"] = "growing"
	world.tiles[3][8]["state"] = "ready"
	world.tiles[3][9]["state"] = "tilled"
	_assert(world.count_planted() == before + 3,
		"count_planted counts seeded/growing/ready but not tilled")

	# Eggs are a gift, not evidence of working the loop, so they must not unlock
	# the crow. This is the shared helper the milestone check also uses.
	GameState.reset()
	GameState.harvest_counts = {"egg": 9}
	_assert(GameState.total_harvests() == 0, "eggs do not count as harvests")
	_assert(not SimWorld.may_spawn_crow(5, GameState.total_harvests(), 10),
		"nine eggs and no crops still means no crow")
	GameState.harvest_counts["wheat"] = 1
	_assert(GameState.total_harvests() == 1, "a crop does count")
	_assert(SimWorld.may_spawn_crow(5, GameState.total_harvests(), 10),
		"one real harvest opens the gate")

	# crows_seen decides whether the first crow can eat, so it must survive a
	# save/load — otherwise reloading hands the player an endless harmless crow.
	GameState.reset()
	GameState.crows_seen = 2
	var w2 := SimWorld.new()
	SimRng.reseed(11)
	w2.generate()
	var snapshot := SaveGame.capture(w2, GameState)
	GameState.reset()
	_assert(GameState.crows_seen == 0, "reset clears crows_seen")
	var w3 := SimWorld.new()
	_assert(SaveGame.restore(snapshot, w3, GameState), "save restores")
	_assert(GameState.crows_seen == 2, "crows_seen round-trips through a save")

	# A save written before T-2 has no such field and must still load.
	var legacy := SaveGame.capture(w2, GameState)
	legacy["state"].erase("crows_seen")
	var w4 := SimWorld.new()
	_assert(SaveGame.restore(legacy, w4, GameState), "a pre-T-2 save still loads")
	_assert(GameState.crows_seen == 0, "and defaults to a harmless first crow")



func test_replay_build_stamp() -> void:
	print("\n--- Replay build stamp (Q-41) Tests ---")

	# Why this exists: apply_to() re-runs a replay's actions against *today's*
	# rules, so semantic drift — what a verb does, worldgen per seed, growth
	# rates, energy costs, SimRng ordering — silently yields a different world
	# with nothing in the file to say so. The stamp makes that detectable.
	var rlog := ReplayLog.new()
	rlog.start(99)
	_assert(rlog.build_id == ReplayLog.current_build(), "start() stamps the build")
	_assert(rlog.build_id != "", "the build id is non-empty")
	_assert(rlog.build_status() == ReplayLog.Build.MATCH, "a fresh replay matches this build")

	var from_save := ReplayLog.new()
	from_save.start_from_save({"version": 1, "state": {}})
	_assert(from_save.build_id == ReplayLog.current_build(),
		"continued sessions are stamped too, not just fresh ones")

	# Round-trip through the on-disk format.
	var world := SimWorld.new()
	SimRng.reseed(99)
	world.generate()
	GameState.reset()
	# Out in the meadow, beyond the fence: the yard's ground stopped being tillable
	# at T-32, and a replay regenerates its world, so the tile has to be one a till
	# still lands on after the regeneration.
	var field_tile := Vector2i(5, 9)
	var a := { "verb": "till", "target": field_tile, "actor": "player" }
	rlog.record(a, world.apply_action(a, GameState))
	var restored := ReplayLog.from_json(rlog.to_json())
	_assert(restored.build_id == rlog.build_id, "the stamp survives a save/load round trip")
	_assert(restored.build_status() == ReplayLog.Build.MATCH, "and still reads as a match")

	# A replay from another build is detected rather than silently trusted.
	var foreign := ReplayLog.from_json(rlog.to_json())
	foreign.build_id = "deadbee-fromthepast"
	_assert(foreign.build_status() == ReplayLog.Build.MISMATCH, "a foreign build is flagged")
	_assert(foreign.build_note().contains("deadbee"), "the note names the recording build")
	_assert(foreign.build_note().contains(ReplayLog.current_build()),
		"and names this one, so the difference is readable")

	# Three states, not two: a replay recorded before stamping existed is
	# unverifiable, which is different from known-bad. Refusing it outright would
	# discard the only real sessions we have.
	var legacy_text := '{"version":1,"gen_seed":7,"base_save":{}}\n'
	var legacy := ReplayLog.from_json(legacy_text)
	_assert(legacy.build_id == "", "a pre-Q-41 replay has no stamp")
	_assert(legacy.build_status() == ReplayLog.Build.UNSTAMPED,
		"and is reported as unstamped, not as a mismatch")
	_assert(legacy.gen_seed == 7, "and still loads and replays normally")

	# The stamp must not disturb what the replay is actually for.
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	restored.apply_to(w2, gs2)
	_assert(w2.get_tile(field_tile.x, field_tile.y).get("state", "") == "tilled",
		"a stamped replay still reproduces its world")


func test_blocked_reason() -> void:
	print("\n--- Silent-tap reasons (from the first real trace) Tests ---")

	# The first real session trace ever read (2026-08-28) showed eight taps in
	# four seconds on a tilled tile producing no response at all. resolve()
	# returns {} when a resource is missing, so the sim never receives an action
	# to refuse, so the 2026-08-27 refusal feedback never fired. Every such tile
	# must now be able to say why.
	GameState.reset()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	SimRng.reseed(31)
	farm.sim.generate()
	var t := Vector2i(7, 6)

	farm.sim.tiles[t.y][t.x]["state"] = "tilled"
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "",
		"a tilled tile with seeds in hand is not blocked")
	GameState.pouch["wheat"] = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "no_seeds",
		"a tilled tile with an empty pouch says so — the exact trace case")
	_assert(ActionRouter.resolve(farm, GameState, t, t).is_empty(),
		"and resolve still returns nothing, so the reason is the only feedback there is")

	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "cleared ground tills fine")
	GameState.energy = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "no_energy",
		"an exhausted farmer on cleared ground says so")

	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "seeded"
	farm.sim.tiles[t.y][t.x]["watered_today"] = false
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "a dry crop waters fine")
	GameState.watering_can_charges = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "no_water",
		"an empty can says so")

	# Already-watered is genuinely nothing to do, not a refusal — wobbling at a
	# tile she just finished would teach that success looks like failure.
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["watered_today"] = true
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "",
		"a crop already watered today is silent, because there is nothing wrong")

	# Tiles with nothing to do at all stay silent.
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "border"
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "", "a border tile is not a refusal")
	_assert(ActionRouter.blocked_reason(farm, GameState, Vector2i(-5, -5)) == "",
		"an out-of-bounds tile does not crash or invent a reason")
	farm.free()


func test_benign_failures() -> void:
	print("\n--- Nothing-to-do vs cannot-do (from the 2026-08-28 session) Tests ---")

	# A real session logged 17 refusals with no reason at all — 8 on the well, 9
	# on the shipping bin, out of 27 total. Both were returning a bare
	# {"ok": false}, which made them undiagnosable in the trace AND answered a
	# perfectly normal state with the nope sound and a wobble.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(5)
	world.generate()

	# Refill: full can is not a mistake.
	GameState.watering_can_charges = GameState.max_watering_can_charges
	var r := world.apply_action({ "verb": "refill", "actor": "player" }, GameState)
	_assert(not r.get("ok", true), "refilling a full can does not succeed")
	_assert(r.get("reason", "") == "can_already_full", "and now says why")
	GameState.watering_can_charges = 0
	_assert(world.apply_action({ "verb": "refill", "actor": "player" }, GameState).get("ok", false),
		"refilling an empty can still works")

	# Sell: an empty basket is not a mistake.
	GameState.reset()
	GameState.pouch["wheat"] = 0
	GameState.pouch["tomato"] = 0
	var s2 := world.apply_action({ "verb": "sell", "actor": "player" }, GameState)
	_assert(not s2.get("ok", true), "selling nothing does not succeed")
	_assert(s2.get("reason", "") == "nothing_to_sell", "and now says why")
	GameState.pouch["wheat"] = 0
	var s2b := world.apply_action({ "verb": "sell", "actor": "player" }, GameState)
	_assert(not s2b.get("ok", true) and s2b.get("reason", "") == "nothing_to_sell",
		"and a pouch down at the keep line is the same benign answer, not a refusal")
	GameState.pouch["wheat"] = 0 + 2
	var s3 := world.apply_action({ "verb": "sell", "actor": "player" }, GameState)
	_assert(s3.get("ok", false), "selling a real crop still works")
	_assert(int(GameState.bin_reserve.wheat) == 2 and GameState.gold == 0,
		"and fills the reserve before paying gold")

	# The distinction that matters: these must not be answered as refusals.
	# Wobbling at a full watering can teaches that a normal state is a
	# malfunction, which is the opposite of what the refusal feedback is for.
	var Farm = load("res://world/farm.gd")
	_assert(Farm.BENIGN_FAILURES.has("can_already_full"), "a full can is benign")
	_assert(Farm.BENIGN_FAILURES.has("nothing_to_sell"), "an empty basket is benign")
	_assert(not Farm.BENIGN_FAILURES.has("no_seeds"),
		"an empty seed pouch is NOT benign — she wanted to plant and could not")
	_assert(not Farm.BENIGN_FAILURES.has("no_state"), "an internal failure is not benign")


func test_seed_selection_trap() -> void:
	print("\n--- Seed cycling with an empty pouch (2026-08-28 report) Tests ---")

	# Reported from play: after placing a scarecrow, holding 0 of every type,
	# cycling stopped responding entirely. The old loop only accepted a type with
	# stock, so owning nothing matched nothing and it returned silently.
	GameState.reset()
	GameState.harvest_counts = { "wheat": 1, "tomato": 0 }  # unlock tomato
	GameState.pouch = { "wheat": 0, "tomato": 0, "scarecrow": 0 }
	GameState.selected_seed_type = "scarecrow"
	GameState.cycle_seed_type()
	_assert(GameState.selected_seed_type != "scarecrow",
		"cycling still moves when she holds nothing — the reported dead control")
	var first: String = GameState.selected_seed_type
	GameState.cycle_seed_type()
	_assert(GameState.selected_seed_type != first, "and keeps moving on the next press")

	# Stock is still preferred over an empty type.
	GameState.reset()
	GameState.harvest_counts = { "wheat": 1 }
	GameState.pouch = { "wheat": 0, "tomato": 3, "scarecrow": 0 }
	GameState.selected_seed_type = "wheat"
	GameState.cycle_seed_type()
	_assert(GameState.selected_seed_type == "tomato",
		"cycling prefers a type she actually has")

	# The trap underneath the report: buying while empty-handed must select what
	# was bought, or resolve() reports "no seeds" to someone holding seeds.
	GameState.reset()
	GameState.pouch = { "wheat": 0, "tomato": 0, "scarecrow": 0 }
	GameState.harvest_counts = { "wheat": 1 }   # tomato unlocked; wheat is off the shelf (S-18/S-19/S-20)
	GameState.selected_seed_type = "scarecrow"
	GameState.gold = 100
	_assert(GameState.buy_seed("tomato"), "buying a tomato succeeds")
	_assert(GameState.selected_seed_type == "tomato",
		"and she is now holding it, not the scarecrow she ran out of")

	_assert(GameState.pouch.get(GameState.selected_seed_type, 0) > 0,
		"the selected type has stock, so a tilled tile can no longer answer 'no seeds'")

	# But a purchase must not hijack a selection she is still using.
	GameState.reset()
	GameState.pouch = { "wheat": 5, "tomato": 0, "scarecrow": 0 }
	GameState.selected_seed_type = "wheat"
	GameState.gold = 100
	_assert(GameState.buy_seed("scarecrow"), "buying a scarecrow succeeds")
	_assert(GameState.selected_seed_type == "wheat",
		"and does not interrupt the row of wheat she was planting")


func test_trace_analyses() -> void:
	print("\n--- Trace analyses promoted from hand-run one-offs ---")

	# Each of these was written by hand against a real session on 2026-08-28 and
	# earned a place by finding something. The rule for this file: an analysis
	# graduates from a one-off only after it has found something worth acting on.
	var hdr := '{"version":1,"gen_seed":1,"continued":false}\n'

	# active_time: wall-clock lies once the app persists while backgrounded. The
	# first real session reported 274 minutes and was ~20s of play either side of
	# a four-hour gap.
	var backgrounded := SessionTrace.parse(hdr
		+ '{"t":1000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n'
		+ '{"t":6000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n'
		+ '{"t":16000000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n'
		+ '{"t":16004000,"kind":"tap","tile":[1,1],"at":[1,1],"out":"acted"}\n')
	var act := SessionTrace.active_time(backgrounded)
	_assert(int(act["active_ms"]) == 9000, "active time excludes the backgrounded gap")
	_assert(int(act["wall_ms"]) > 15000000, "wall clock still reported, for contrast")
	_assert(int(act["gaps"]) == 1, "and the break is counted")

	# mislabelled_unreachable: an integrity check on the instrument itself. This
	# is the one that caught my own logging bug — 14 taps reported as unreachable
	# were every one of them adjacent.
	var lying := SessionTrace.parse(hdr
		+ '{"t":10,"kind":"tap","tile":[10,3],"at":[11,3],"out":"unreachable"}\n'
		+ '{"t":20,"kind":"tap","tile":[10,3],"at":[20,15],"out":"unreachable"}\n')
	var bad: Array = SessionTrace.mislabelled_unreachable(lying)
	_assert(bad.size() == 1, "an adjacent 'unreachable' tap is flagged as a fault")
	_assert(int(bad[0]["at"][0]) == 11, "and it is the adjacent one, not the distant one")
	_assert(SessionTrace.mislabelled_unreachable(SessionTrace.parse(hdr)).is_empty(),
		"a clean trace reports no fault")

	# failures_by_verb: "?" in the reason table says nothing about where to look.
	# Grouping by verb found the well and the shipping bin immediately.
	var fails := SessionTrace.parse(hdr
		+ '{"t":1,"kind":"act","verb":"refill","actor":"player","ok":false}\n'
		+ '{"t":2,"kind":"act","verb":"refill","actor":"player","ok":false}\n'
		+ '{"t":3,"kind":"act","verb":"sell","actor":"player","ok":false}\n'
		+ '{"t":4,"kind":"act","verb":"plant","actor":"player","ok":false,"why":"no_seeds"}\n')
	var byv := SessionTrace.failures_by_verb(fails)
	_assert(int(byv["without_reason"].get("refill", 0)) == 2, "silent refills grouped by verb")
	_assert(int(byv["without_reason"].get("sell", 0)) == 1, "silent sells too")
	_assert(not byv["without_reason"].has("plant"), "a failure WITH a reason is not listed as silent")
	_assert(int(byv["with_reason"].get("plant", 0)) == 1, "and appears in the explained bucket")

	# tile_history: a tile that only ever failed is a different problem from one
	# that worked five times and then stopped — the second is a state change she
	# could not see.
	var hist := SessionTrace.parse(hdr
		+ '{"t":1,"kind":"tap","tile":[10,3],"at":[9,3],"out":"acted","tool":3}\n'
		+ '{"t":2,"kind":"tap","tile":[10,3],"at":[9,3],"out":"acted","tool":3}\n'
		+ '{"t":3,"kind":"tap","tile":[10,3],"at":[9,3],"out":"none","tool":4}\n'
		+ '{"t":4,"kind":"tap","tile":[9,9],"at":[9,3],"out":"acted","tool":3}\n')
	var h := SessionTrace.tile_history(hist, "10,3")
	_assert(int(h["outcomes"].get("acted", 0)) == 2, "tile history counts what worked")
	_assert(int(h["outcomes"].get("none", 0)) == 1, "and what did not")
	_assert(not h["outcomes"].has("9,9"), "and only for the tile asked about")

	# dead_tap_tools: 12 of 14 dead taps held the watering can, which is what
	# identified them as already-watered crops rather than a pathing fault.
	var tools := SessionTrace.dead_tap_tools(hist)
	_assert(int(tools.get(4, 0)) == 1, "dead taps are grouped by the tool in hand")
	_assert(not tools.has(3), "and successful taps are not counted")

	# days_played: the cheapest proxy for whether she understood the cot, which
	# is the one beat with no visual affordance at all.
	var slept := SessionTrace.parse(hdr
		+ '{"t":1,"kind":"act","verb":"sleep","actor":"world","ok":true}\n'
		+ '{"t":2,"kind":"act","verb":"sleep","actor":"world","ok":true}\n'
		+ '{"t":3,"kind":"act","verb":"sleep","actor":"world","ok":false}\n')
	_assert(SessionTrace.days_played(slept) == 2, "only successful sleeps count as days")

	# Degenerate input must not crash the reader mid-playtest.
	var empty := SessionTrace.parse("")
	_assert(int(SessionTrace.active_time(empty)["active_ms"]) == 0, "empty trace has no active time")
	_assert(SessionTrace.days_played(empty) == 0, "and no days")
	_assert(SessionTrace.dead_tap_tools(empty).is_empty(), "and no dead taps")


func test_stateless_schedule_revision() -> void:
	print("\n--- Per-day schedule revision Tests ---")
	SimRng.reseed(1, SimRng.STATELESS_LEGACY)
	_assert(SimWorld.roll_crow_schedule(3) == [9]
		and SimWorld.roll_crow_schedule(4) == [18],
		"legacy revision preserves the shipped crow sequence")
	var legacy_steps := 0
	for day in range(3, 30):
		var a: int = SimWorld.roll_crow_schedule(day)[0]
		var b: int = SimWorld.roll_crow_schedule(day + 1)[0]
		if (b - a + 20) % 20 == 9:
			legacy_steps += 1
	_assert(legacy_steps == 24, "the measured legacy sequence has 24 predictable steps in 27")
	for seed_value in [1, 42, 20260909]:
		SimRng.reseed(seed_value)
		var current_steps := 0
		for day in range(3, 30):
			var a: int = SimWorld.roll_crow_schedule(day)[0]
			var b: int = SimWorld.roll_crow_schedule(day + 1)[0]
			if (b - a + 20) % 20 == 9:
				current_steps += 1
		_assert(current_steps < 8, "current seed %d breaks the +9 cycle" % seed_value)
	var world := SimWorld.new()
	GameState.reset()
	SimRng.reseed(1)
	world.generate()
	var fresh := SaveGame.capture(world, GameState)
	_assert(int(fresh["world"]["stateless_revision"]) == SimRng.STATELESS_CURRENT,
		"new saves stamp the current derivation")
	var old := fresh.duplicate(true)
	old["version"] = 5
	old["world"].erase("stateless_revision")
	_assert(SaveGame.restore(old, SimWorld.new(), GameState)
		and SimRng.stateless_revision == SimRng.STATELESS_LEGACY,
		"v5 saves restore the original derivation")
	_assert(SaveGame.restore(fresh, SimWorld.new(), GameState)
		and SimRng.stateless_revision == SimRng.STATELESS_CURRENT,
		"v6 saves restore the current derivation")
	var replay := ReplayLog.new()
	replay.start(1)
	_assert(ReplayLog.from_json(replay.to_json()).version == 5,
		"new replay headers carry the new derivation version")
	replay.start_from_save(old, 1)
	_assert(replay.apply_to(SimWorld.new(), GameState)
		and SimRng.stateless_revision == SimRng.STATELESS_LEGACY,
		"a continued v3 replay inherits its v5 base save's derivation")
	replay.start_from_save(fresh, 1)
	_assert(replay.apply_to(SimWorld.new(), GameState)
		and SimRng.stateless_revision == SimRng.STATELESS_CURRENT,
		"a continued v3 replay inherits its v6 base save's derivation")
	replay.start(1)
	replay.version = 2
	_assert(replay.apply_to(SimWorld.new(), GameState)
		and SimRng.stateless_revision == SimRng.STATELESS_LEGACY,
		"v2 seed replays use the original derivation")
	SimRng.reseed(1)


func test_crow_schedule() -> void:
	print("\n--- One crow, one chance per day (T-20) Tests ---")

	# Ruled 2026-08-28. The spawner fired every 10 seconds, so once the readiness
	# conditions were met a crow arrived about six times a minute for as long as
	# the app was open — which makes shooing a chore rather than a win. Each crow
	# now gets one scheduled arrival, expressed as a point in the day's action
	# clock, and it is consumed whether the bird is fed or shooed.
	_assert(SimWorld.roll_crow_schedule(1).is_empty(), "no crows scheduled on day 1")
	_assert(SimWorld.roll_crow_schedule(2).is_empty(), "nor day 2")
	var d3 := SimWorld.roll_crow_schedule(3)
	_assert(d3.size() == SimWorld.CROWS_PER_DAY, "one arrival per crow per day")
	_assert(int(d3[0]) >= SimWorld.CROW_EARLIEST_ACTION,
		"and never in the first few actions of the day")

	# Stateless by construction: a per-day value drawn from the shared SimRng
	# stream desynced replays immediately, because entity noise advances that
	# stream between actions — the same failure sleep's weather stamping fixed.
	SimRng.reseed(77)
	var a := SimWorld.roll_crow_schedule(5)
	SimRng.randi(); SimRng.randi(); SimRng.randf()   # entity noise
	var b := SimWorld.roll_crow_schedule(5)
	_assert(a == b, "the schedule is unmoved by other draws on the shared stream")
	SimRng.reseed(78)
	var c := SimWorld.roll_crow_schedule(5)
	_assert(a != c or SimWorld.CROWS_PER_DAY == 0, "but it does vary with the seed")
	SimRng.reseed(77)
	_assert(SimWorld.roll_crow_schedule(5) == a, "and is reproducible from the seed alone")
	_assert(SimWorld.roll_crow_schedule(6) != a or SimWorld.CROWS_PER_DAY == 0,
		"and differs day to day")

	# The action clock: farm work advances the day, errands do not.
	GameState.reset()
	var world := SimWorld.new()
	SimRng.reseed(9)
	world.generate()
	var t := Vector2i(5, 3)  # inside the fenced yard
	world.tiles[t.y][t.x]["state"] = "cleared"
	# Measured as deltas per step, so one surprising verb cannot cascade into
	# three misleading failures.
	var n0: int = GameState.actions_today
	world.apply_action({ "verb": "till", "target": t, "actor": "player" }, GameState)
	_assert(GameState.actions_today == n0 + 1, "a successful player action ticks the clock")

	var n1: int = GameState.actions_today
	world.apply_action({ "verb": "plant", "target": t, "actor": "player",
		"seed_type": "nonexistent_seed" }, GameState)
	_assert(GameState.actions_today == n1, "a refused action does not tick it")

	var n2: int = GameState.actions_today
	GameState.pouch["wheat"] = 1
	world.apply_action({ "verb": "sell", "actor": "player" }, GameState)
	_assert(GameState.actions_today == n2, "nor does an errand at the bin")

	var n3: int = GameState.actions_today
	GameState.watering_can_charges = 0
	world.apply_action({ "verb": "refill", "actor": "player" }, GameState)
	_assert(GameState.actions_today == n3, "nor does refilling at the well")

	var n4: int = GameState.actions_today
	world.tiles[t.y][t.x]["state"] = "seeded"
	world.apply_action({ "verb": "eat_crop", "target": t, "actor": "crow" }, GameState)
	_assert(GameState.actions_today == n4, "nor does another actor's action")

	# Sleeping starts a fresh day and a fresh set of arrivals.
	GameState.day = 4
	GameState.actions_today = 12
	world.apply_action({ "verb": "sleep", "actor": "world" }, GameState)
	_assert(GameState.actions_today == 0, "sleeping resets the day's action clock")
	_assert(GameState.crow_schedule.size() == SimWorld.CROWS_PER_DAY,
		"and rolls the new day's arrivals")

	# The schedule survives a reload, so a mid-day save neither resurrects a crow
	# already dealt with nor erases one still owed.
	var pending: Array[int] = [7]
	GameState.crow_schedule = pending
	GameState.actions_today = 5
	var snap := SaveGame.capture(world, GameState)
	GameState.reset()
	var w2 := SimWorld.new()
	_assert(SaveGame.restore(snap, w2, GameState), "save restores")
	_assert(GameState.crow_schedule.size() == 1 and int(GameState.crow_schedule[0]) == 7,
		"the remaining schedule survives")
	_assert(GameState.actions_today == 5, "and so does the day's progress")


# --- The morning the crows come for the tomatoes (design/04, P-15) ------------
#
# The bed these tests plant: a four-tomato row in the neighbour's plot, which is
# the nearest ground she can actually plant on (`tools/measure_raid_race.gd`
# finds the same row when it measures the race). Written into the grid rather
# than farmed, because what is under test is the night and the morning, not the
# hoe.
func test_crow_raid_trigger() -> void:
	print("\n--- The crow night fires once, and only when both halves hold (P-15) Tests ---")

	# Half one, on its own: a bed worth raiding while there are still acorns on
	# the ground. The crows have no reason to turn to crops yet (T-15/Q-39), so
	# there is no story to tell.
	var acorns := LiveSession.new(3001)
	for i in SimWorld.RAID_MIN_TOMATOES:
		acorns.world.set_tile_state(RAID_BED_X0 + i, RAID_BED_Y, "growing", SimWorld.RAID_CROP)
	_assert(acorns.world.count_acorns() > 0, "the farm still has acorns on the ground")
	var with_acorns := acorns.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(String(with_acorns.get("story_night", "?")) == SimWorld.STORY_NIGHT_NONE,
		"a night with acorns still on the ground is an ordinary night")
	_assert(_raid_birds(acorns.world).is_empty(), "and no crows are waiting in the morning")
	acorns.done()

	# Half two, on its own: the acorns are gone but the bed is one short.
	var thin := LiveSession.new(3002)
	var thin_bed := _raid_eve(thin)
	thin.world.set_tile_state(thin_bed[0].x, thin_bed[0].y, "cleared")
	_assert(_standing_tomatoes(thin.world) == SimWorld.RAID_MIN_TOMATOES - 1,
		"three tomatoes stand, one short of the four the designer asked for")
	var three_only := thin.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(String(three_only.get("story_night", "?")) == SimWorld.STORY_NIGHT_NONE,
		"three tomatoes and no acorns is still an ordinary night")

	# ...and a fourth tile that remembers a tomato but has nothing standing on it
	# does not make it four. The count is the crow's own target rule — the states
	# in `SimWorld.CROP_STATES`, which `has_crop`, `eat_crop` and
	# `choose_crow_target` all read — so a bed can never pass this test and then
	# leave a bird with nothing to eat when it lands.
	#
	# Written onto the tile by hand because the game cannot produce it: turning
	# soil over clears its crop type (`set_tile_state`). What is being pinned is
	# the rule, not a state the player can reach.
	thin.world.tiles[thin_bed[0].y][thin_bed[0].x]["crop_type"] = SimWorld.RAID_CROP
	_assert(not thin.world.has_crop(thin_bed[0].x, thin_bed[0].y),
		"a tilled tile with a tomato's name on it has nothing a crow could eat")
	_assert(_standing_tomatoes(thin.world) == SimWorld.RAID_MIN_TOMATOES - 1,
		"so it does not count towards the four")
	_assert(String(thin.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
			.get("story_night", "?")) == SimWorld.STORY_NIGHT_NONE,
		"and the night stays ordinary")

	# Every state a crow *will* eat counts, which is the other half of the same
	# rule: a sown tomato is a tomato, because a bird that lands on one takes it.
	for state in SimWorld.CROP_STATES:
		thin.world.set_tile_state(thin_bed[0].x, thin_bed[0].y, state, SimWorld.RAID_CROP)
		_assert_quiet(thin.world.has_crop(thin_bed[0].x, thin_bed[0].y)
				and _standing_tomatoes(thin.world) == SimWorld.RAID_MIN_TOMATOES,
			"a %s tomato counts towards the four" % state)
	_flush_quiet("the four are counted by the same rule the crow picks its target with")
	thin.done()

	# Both halves: the night is named, and the morning it promises is on the farm.
	var raid := LiveSession.new(3003)
	var bed := _raid_eve(raid)
	var night := raid.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(String(night.get("story_night", "")) == SimWorld.STORY_NIGHT_CROW,
		"the first sleep with no acorns and four tomatoes is the crow night")
	_assert(raid.world.story_night == SimWorld.STORY_NIGHT_CROW,
		"and the world carries the same one fact, for the save to pick up")
	var birds := _raid_birds(raid.world)
	_assert(birds.size() == SimWorld.RAID_CROWS, "three crows are on the farm")
	var on_tomatoes := 0
	for id in birds:
		if bed.has(raid.world.actor_pos(id)):
			on_tomatoes += 1
	_assert(on_tomatoes == SimWorld.RAID_CROWS, "each one standing on one of her tomatoes")
	var tiles := {}
	for id in birds:
		tiles[raid.world.actor_pos(id)] = true
	_assert(tiles.size() == SimWorld.RAID_CROWS, "and no two of them on the same plant")
	_assert(_standing_tomatoes(raid.world) == SimWorld.RAID_MIN_TOMATOES,
		"nothing has been eaten yet — the tomatoes are all still standing")

	# Once per farm. The conditions still hold the next night (nobody has opened
	# the door, so nothing has been eaten), and the night is over all the same.
	var second := raid.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_assert(String(second.get("story_night", "?")) == SimWorld.STORY_NIGHT_NONE,
		"the second night is ordinary, though the farm still meets every condition")
	_assert(_raid_birds(raid.world).size() == SimWorld.RAID_CROWS,
		"and no second flock arrives on top of the first")
	raid.done()


func test_crow_raid_waits_for_the_door() -> void:
	print("\n--- The raid's meals start at the door, not at dawn (design/04) Tests ---")

	var s := LiveSession.new(3101)
	var bed := _raid_eve(s)
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	var birds := _raid_birds(s.world)
	_assert(birds.size() == SimWorld.RAID_CROWS, "the morning starts with three crows on the bed")
	var waiting := true
	for id in birds:
		waiting = waiting and bool(s.world.actor(id)["extra"].get("waiting_for_door", false))
	_assert(waiting, "and not one of them has started counting")

	# A minute of sim time with her still indoors. A raid bird placed with no meal
	# clock used to eat on its first thought at dawn, which is the failure this
	# asserts against: the plants come into view when she opens the door.
	s.tick(600)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES,
		"a minute later, with her still inside, every tomato is standing")
	_assert(_raid_birds(s.world).size() == SimWorld.RAID_CROWS, "and all three birds are still on them")

	# She comes out. The same Action that moves her rings the bell.
	var out := s.act({ "verb": "use_door", "actor": "player", "target": _doorway_tile(s.world) })
	_assert(out.get("ok", false), "she opens her front door")
	var started := true
	for id in birds:
		var extra: Dictionary = s.world.actor(id)["extra"]
		started = started and not bool(extra.get("waiting_for_door", true)) \
			and int(extra.get("eat_at", 0)) > s.world.clock.tick
	_assert(started, "and all three meal clocks start on that one moment")

	# ...and she does nothing at all. Since Q-105 the clock that ends a raid meal
	# is her walk, so what is left here is the patience under it: a player who
	# opens the door on three crows and never walks over still loses the bed, and
	# the wait before that is long enough that it can never be what decides a race
	# she is actually running.
	s.tick(int(CrowBrain.RAID_PATIENCE_SECONDS * SimClock.RATE) - 2)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES,
		"a fifth of a second before their patience runs out, the bed is untouched")
	s.tick(4)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES - SimWorld.RAID_CROWS,
		"and when it does, the three tomatoes they were standing on are gone")
	var eaten := 0
	for t in bed:
		if not s.world.has_crop(t.x, t.y):
			eaten += 1
	_assert(eaten == SimWorld.RAID_CROWS, "each bird took the plant it was standing on")
	s.done()


func test_crow_raid_costs_one_tomato() -> void:
	print("\n--- The raid's meal lasts as long as her walk (Q-105) Tests ---")

	# The rule itself, with no walk in it: the birds are shooed through the
	# gateway, which is what her walking into range amounts to.
	var s := LiveSession.new(3102)
	var bed := _raid_eve(s)
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	var birds := _raid_birds(s.world)
	s.act({ "verb": "use_door", "actor": "player", "target": _doorway_tile(s.world) })
	var plants: Array[Vector2i] = []
	for id in birds:
		plants.append(s.world.actor_pos(id))

	s.tick(30)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES,
		"three seconds out of the door, with nobody frightened, the bed is whole")

	s.act({ "verb": "crow_scared", "actor": birds[0] })
	s.tick(5)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES,
		"she reaches the first bird and it leaves with nothing")
	_assert(CrowBrain.raid_birds_eating(s.world).size() == SimWorld.RAID_CROWS - 1,
		"two of the raid are still on their plants")

	# The second one is the bell. The bird she has not reached takes the plant it
	# is standing on and goes, so the morning costs one tomato however long the
	# walk was — which is the whole of the ruling.
	s.act({ "verb": "crow_scared", "actor": birds[1] })
	s.tick(2)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES - 1,
		"and when she reaches the second, the last bird eats at once — one tomato")
	_assert(s.world.has_crop(plants[0].x, plants[0].y)
			and s.world.has_crop(plants[1].x, plants[1].y),
		"the two she got to still have their plants")
	_assert(not s.world.has_crop(plants[2].x, plants[2].y),
		"and the one she did not is the plant that went")
	_assert(CrowBrain.raid_birds_eating(s.world).is_empty(), "the bed is empty of birds")

	# Nothing else changes in the minute after: the raid is over, and the patience
	# clock cannot come back and take a second tomato off a bird that has gone.
	s.tick(int(CrowBrain.RAID_PATIENCE_SECONDS * SimClock.RATE) + 20)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES - 1,
		"a minute later the bed is still three plants")
	_assert(bed.size() == SimWorld.RAID_MIN_TOMATOES, "out of the four she went to bed with")
	s.done()

	# And the same morning walked for real, on the farm the game generates. This
	# is `tools/measure_raid_race.gd` — the tool a human runs to watch the race —
	# called rather than copied, so the rule is asserted against the same walk the
	# tool prints and the two can never drift. Two beds: the nearest ground she
	# can plant, and the same row ten tiles further from her door, which is the
	# distance that used to take every tomato.
	for push_out in [RaidRace.NEAR_BED, RaidRace.FAR_BED]:
		var run: Dictionary = RaidRace.measure(push_out)
		_assert(String(run.get("problem", "?")) == "",
			"the raid's morning can be walked on a bed %d tiles out (%s)"
				% [push_out, run.get("problem", "?")])
		if String(run.get("problem", "?")) != "":
			continue
		_assert(int(run["saved"]) == SimWorld.RAID_CROWS - 1,
			"a direct walk from the door saves two of the three, %d tiles out" % push_out)
		_assert(int(run["lost"]) == 1,
			"and costs exactly one tomato, %d tiles out" % push_out)


func test_crow_raid_marks_the_plot() -> void:
	print("\n--- A plot a crow emptied says so, until she works it again (Q-105) Tests ---")

	var s := LiveSession.new(3103)
	_raid_eve(s)
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	var birds := _raid_birds(s.world)
	s.act({ "verb": "use_door", "actor": "player", "target": _doorway_tile(s.world) })
	var plant: Vector2i = s.world.actor_pos(birds[2])
	_assert(not bool(s.world.get_tile(plant.x, plant.y).get("ransacked", false)),
		"a plant still standing carries no mark")

	s.act({ "verb": "crow_scared", "actor": birds[0] })
	s.act({ "verb": "crow_scared", "actor": birds[1] })
	s.tick(2)
	_assert(not s.world.has_crop(plant.x, plant.y), "the last bird takes its tomato")
	_assert(bool(s.world.get_tile(plant.x, plant.y).get("ransacked", false)),
		"and leaves the square marked as a square something ate a plant off")
	# **And names the plant it took.** The designer ruled on 2026-09-19 that the
	# square keeps a bitten stalk of what was growing there (Q-110 b), so the
	# square has to remember which crop that was — the state is cleared to soil
	# the instant the bird eats, and after that nothing else can say.
	_assert(String(s.world.get_tile(plant.x, plant.y).get("ransacked_crop", ""))
			== SimWorld.RAID_CROP,
		"and remembers that what it lost was a %s" % SimWorld.RAID_CROP)

	# The mark rides in the save, because a farm reloaded the next minute is the
	# same farm and the loss did not stop being true while the file was shut.
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var loaded := SimWorld.new()
	var gs_loaded = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snapshot, loaded, gs_loaded), "the morning save restores")
	_assert(bool(loaded.get_tile(plant.x, plant.y).get("ransacked", false)),
		"with the ransacked square still ransacked")
	_assert(String(loaded.get_tile(plant.x, plant.y).get("ransacked_crop", ""))
			== SimWorld.RAID_CROP,
		"and still knowing which plant it lost, so it draws the right stalk")
	_assert(SaveGame.capture_canonical(loaded, gs_loaded)
			== SaveGame.capture_canonical(s.world, s.gs),
		"and the two farms are the same farm in every other respect too")

	# A save from before any of this loads as a farm nothing has eaten off, which
	# is the only thing it could honestly be.
	var legacy = JSON.parse_string(JSON.stringify(snapshot))
	legacy["world"]["tiles"][plant.y][plant.x].erase("ransacked")
	var old := SimWorld.new()
	var gs_old = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, old, gs_old), "a save from before the mark loads")
	_assert(not bool(old.get_tile(plant.x, plant.y).get("ransacked", false)),
		"as a farm with nothing marked on it")

	# A save from the four days when the square was marked but the crop was not
	# recorded loads as a marked square that does not know what it lost. It stays
	# a legal state, because the renderer has an answer for it and because the
	# first work she does on the square ends it.
	var mid = JSON.parse_string(JSON.stringify(snapshot))
	mid["world"]["tiles"][plant.y][plant.x].erase("ransacked_crop")
	var half := SimWorld.new()
	var gs_half = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(mid, half, gs_half), "a save that marked the square but never named the crop loads")
	_assert(bool(half.get_tile(plant.x, plant.y).get("ransacked", false))
			and String(half.get_tile(plant.x, plant.y).get("ransacked_crop", "")) == "",
		"as a marked square that does not know what it lost")

	# She puts the hoe through it, and the square is hers again.
	var tilled := s.act({ "verb": "till", "actor": "player", "target": plant })
	_assert(tilled.get("ok", false), "she turns the square over")
	_assert(not bool(s.world.get_tile(plant.x, plant.y).get("ransacked", false))
			and String(s.world.get_tile(plant.x, plant.y).get("ransacked_crop", "")) == "",
		"and the mark and the crop it named both come off with the first work she does on it")
	gs_loaded.free()
	gs_old.free()
	gs_half.free()
	s.done()


func test_crow_raid_survives_a_save() -> void:
	print("\n--- The crow night and its three birds survive a save (P-15) Tests ---")

	# The save the game writes at bedtime, and the same farm played on without
	# one: the night must land identically on both.
	var live := LiveSession.new(3201)
	var bed := _raid_eve(live)
	var eve = JSON.parse_string(JSON.stringify(SaveGame.capture(live.world, live.gs)))
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })

	var loaded := SimWorld.new()
	var gs_loaded = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(eve, loaded, gs_loaded), "the bedtime save restores")
	loaded.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs_loaded)
	_assert(_raid_birds(loaded) == _raid_birds(live.world),
		"a farm saved the night before wakes to the same three crows, by name")
	var same_tiles := true
	for id in _raid_birds(loaded):
		same_tiles = same_tiles and loaded.actor_pos(id) == live.world.actor_pos(id)
	_assert(same_tiles, "on the same three tomatoes")
	_assert(SaveGame.capture_canonical(loaded, gs_loaded)
			== SaveGame.capture_canonical(live.world, live.gs),
		"and the two farms are the same farm in every other respect too")

	# ...and the morning itself, saved and picked up again. Three birds standing
	# on three plants are not a visit passing through: they are what the morning
	# is, so they are in the file.
	var morning = JSON.parse_string(JSON.stringify(SaveGame.capture(live.world, live.gs)))
	var again := SimWorld.new()
	var gs_again = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(morning, again, gs_again), "the morning save restores")
	_assert(_raid_birds(again) == _raid_birds(live.world), "with the same three crows")
	var intact := true
	for id in _raid_birds(again):
		intact = intact and again.actor_pos(id) == live.world.actor_pos(id) \
			and String(again.actor(id)["extra"].get("state", "")) == "eating" \
			and bool(again.actor(id)["extra"].get("waiting_for_door", false))
	_assert(intact, "still on their plants, and still waiting for the door")
	_assert(again.story_night == SimWorld.STORY_NIGHT_CROW,
		"the world remembers which night it just had, so the loop can still play")
	_assert(again.story_nights_told.has(SimWorld.STORY_NIGHT_CROW),
		"and that it has had it")
	again.advance_day("sunny", gs_again)
	_assert(again.story_night == SimWorld.STORY_NIGHT_NONE
			and _raid_birds(again).size() == SimWorld.RAID_CROWS,
		"so a reloaded farm cannot have a second crow night")

	# A bird that has been shooed, or has eaten, is a visit again — and a visit is
	# not saved (M2.5 WI-3). Nothing is left standing in the file that the game
	# would have to explain on the next load.
	CrowBrain.new().flee(live.world, _raid_birds(live.world)[0], "player")
	var after := SaveGame.capture(live.world, live.gs)
	_assert(after["world"]["actors"].keys().size()
			== morning["world"]["actors"].keys().size() - 1,
		"a shooed raid bird leaves the save as it leaves the plant")

	# A save written before any of this existed loads into a farm whose crow night
	# is still ahead of it.
	var legacy := SaveGame.capture(live.world, live.gs)
	legacy["world"].erase("story_night")
	legacy["world"].erase("story_nights_told")
	var old := SimWorld.new()
	var gs_old = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, old, gs_old), "a save from before the crow night loads")
	_assert(old.story_night == SimWorld.STORY_NIGHT_NONE
			and old.story_nights_told.is_empty(),
		"as a farm that has had no story nights at all")
	_assert(bed.size() == SimWorld.RAID_MIN_TOMATOES, "the bed under all of this is four tomatoes")
	gs_loaded.free()
	gs_again.free()
	gs_old.free()
	live.done()


func test_story_loop_shown_survives_a_save() -> void:
	print("\n--- The overnight's shown-loop flag survives a save (P-15) Tests ---")
	# Presentation's own record of which story-night loops this farm has seen. The
	# flag travels with the farm's next save, independently of the sim's record
	# that the story night itself has happened.
	var live := LiveSession.new(3202)
	live.gs.story_loops_shown[SimWorld.STORY_NIGHT_CROW] = true
	var saved = JSON.parse_string(JSON.stringify(SaveGame.capture(live.world, live.gs)))
	var loaded := SimWorld.new()
	var gs_loaded = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(saved, loaded, gs_loaded), "the save restores")
	_assert(bool(gs_loaded.story_loops_shown.get(SimWorld.STORY_NIGHT_CROW, false)),
		"and the farm still knows the crow night's loop has been shown")
	_assert(not gs_loaded.story_loops_shown.has(SimWorld.STORY_NIGHT_ROBOT),
		"while a night it has not seen is still unset")
	# A save from before the overnight loop existed reads as a farm shown nothing.
	saved["state"].erase("story_loops_shown")
	var old := SimWorld.new()
	var gs_old = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(saved, old, gs_old), "a save from before the overnight loop loads")
	_assert(gs_old.story_loops_shown.is_empty(), "as a farm that has been shown no loop yet")
	gs_loaded.free()
	gs_old.free()
	live.done()


func test_crow_raid_replays() -> void:
	print("\n--- The raid replays: the same three birds, the same three tomatoes Tests ---")

	var s := LiveSession.new(3301)
	var bed := _raid_eve(s)
	s.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	var birds := _raid_birds(s.world)
	s.tick(150)
	s.act({ "verb": "use_door", "actor": "player", "target": _doorway_tile(s.world) })
	# The morning as it is actually played (Q-105): she gets to two of the three,
	# the last one eats on the second shoo, and the log has to carry a meal whose
	# moment was decided by a report she filed rather than by a count of seconds.
	s.tick(20)
	s.act({ "verb": "crow_scared", "actor": birds[0] })
	s.tick(8)
	s.act({ "verb": "crow_scared", "actor": birds[1] })
	s.tick(int(CrowBrain.RAID_PATIENCE_SECONDS * SimClock.RATE) + 20)
	_assert(_standing_tomatoes(s.world) == SimWorld.RAID_MIN_TOMATOES - 1,
		"the session ends with one tomato eaten and three left")

	var eats := 0
	for e in s.log.entries:
		if String(e.get("actor", "")).begins_with(SimWorld.ACTOR_RAID_CROW) \
				and String(e.get("verb", "")) == "eat_crop":
			eats += 1
	_assert(eats == 1, "and the log carries that meal as an Action a brain decided")

	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(s.world, s.gs)))
	var report := SaveGame.replay_report(ReplayLog.from_json(s.log.to_json()), snapshot)
	_assert(String(report["divergence"]) == "",
		"the replay's birds decide exactly what the session's birds decided %s"
			% report["divergence"])
	_assert(report["matched"], "and the replay reproduces the morning it was recorded from")

	# ...and the grid says the same thing in the plainest possible terms: the same
	# three plants gone, the same one standing.
	var replayed := SimWorld.new()
	var gs_replayed = load("res://systems/game_state.gd").new()
	ReplayLog.from_json(s.log.to_json()).apply_to(replayed, gs_replayed)
	var same := true
	for t in bed:
		same = same and replayed.has_crop(t.x, t.y) == s.world.has_crop(t.x, t.y)
	_assert(same, "the replayed bed lost the same tomatoes the recorded one did")
	gs_replayed.free()
	s.done()


func test_daylight() -> void:
	print("\n--- Daylight from energy (Q-38 / T-14) Tests ---")

	# The day is measured in work done: energy starts full and only actions spend
	# it, so the number that used to be an unreadable bar is exactly the day's
	# progress. This maps it to light.
	var dawn := Daylight.tint_for(20, 20)
	# 78 of 100 lands exactly on the midday stop; 16 of 20 is 0.80 and would sit
	# part-way between dawn and midday.
	var noon := Daylight.tint_for(78, 100)
	var dusk := Daylight.tint_for(0, 20)
	_assert(dawn != noon, "dawn and midday differ")
	_assert(dusk != noon, "dusk and midday differ")
	_assert(noon.is_equal_approx(Color(1, 1, 1)), "midday applies no tint at all")
	_assert(dusk.b > dusk.r, "twilight is blue")
	_assert(Daylight.tint_for(3, 20).r > Daylight.tint_for(3, 20).b, "sunset is warm")

	# Night must stay legible: Q-11's floor means actions still work at zero, so
	# twilight is a nudge toward the cot and never a blackout.
	_assert(dusk.r > 0.4 and dusk.g > 0.4 and dusk.b > 0.4,
		"twilight dims but never goes dark enough to hide the farm")

	# The arc brightens into midday and then declines, which is what makes it read
	# as a day passing rather than as a battery draining. So the fall is only
	# asserted *after* midday (f < 0.78, i.e. energy below ~15 of 20).
	_assert(Daylight.tint_for(18, 20) != dawn, "the light changes as the first actions are spent")
	var prev := 99.0
	for e in [12, 9, 6, 3, 0]:
		var c := Daylight.tint_for(e, 20)
		var lum: float = c.r + c.g + c.b
		_assert(lum <= prev + 0.001, "light falls through the afternoon (energy %d)" % e)
		prev = lum

	# Degenerate inputs must not produce a black screen mid-play.
	_assert(Daylight.tint_for(5, 0).is_equal_approx(Color(1, 1, 1)), "no max energy means no tint")
	_assert(Daylight.tint_for(99, 20).is_equal_approx(Daylight.tint_for(20, 20)),
		"energy above max clamps to dawn")
	_assert(Daylight.tint_for(-5, 20).is_equal_approx(dusk), "negative energy clamps to dusk")

	# Hints are drawn into the tinted canvas, so a gold highlight would go muddy
	# blue at dusk — exactly when a stuck player most needs to see it.
	var gold := Color(1.0, 0.72, 0.15, 1.0)
	var fixed := Daylight.compensate(gold, dusk)
	_assert(fixed.r >= gold.r and fixed.g >= gold.g,
		"hint colours are brightened to survive the twilight tint")
	_assert(fixed.a == gold.a, "and their alpha is left alone")
	_assert(Daylight.compensate(gold, Color(1, 1, 1)).is_equal_approx(gold),
		"at midday compensation changes nothing")
	var black := Daylight.compensate(gold, Color(0, 0, 0))
	_assert(black.r <= 1.0 and black.g <= 1.0 and black.b <= 1.0,
		"a pathological tint cannot push a colour out of range")


func test_energy_repartition() -> void:
	print("\n--- T-29: the day re-partitioned into 600 fine units (Q-38's rider) ---")

	# --- the constants, as shipped -------------------------------------------
	_assert(Tools.DAY_UNITS == 600, "a day is 600 fine units")
	_assert(Tools.BASE_COST == 30 and Tools.HEAVY_COST == 60 and Tools.DEAR_COST == 90,
		"a base verb costs 30 of them, a heavy clear 60, a dear clear 90 (Q-50)")
	_assert(SimWorld.ACTOR_MAX_ENERGY == Tools.DAY_UNITS,
		"an NPC's day is the same length as hers — a bot gets no more clock (S-3)")
	var fresh = load("res://systems/game_state.gd").new()
	_assert(fresh.energy == 600 and fresh.max_energy == 600,
		"and a new game starts on a full one")
	fresh.free()
	for verb in ["till", "water", "harvest", "clear_weed"]:
		_assert_quiet(Tools.get_energy_cost(verb) == 30, "%s costs 30" % verb)
	_assert_quiet(Tools.get_energy_cost("clear_log") == 60, "clear_log costs 60")
	for verb in ["clear_rock", "clear_tree"]:
		_assert_quiet(Tools.get_energy_cost(verb) == 90, "%s costs 90 (Q-50)" % verb)
	for verb in ["plant", "sell", "refill", "sleep"]:
		_assert_quiet(Tools.get_energy_cost(verb) == 0, "%s is free" % verb)
	_flush_quiet("every verb's cost is 30, 60, 90 or nothing")
	# Q-38's divisibility argument holds for every cost, not just the base: any
	# cost that is a whole multiple of 30 divides evenly under every multiplier
	# the base does (30k·d/n is whole wherever 30·d/n is).
	for verb in Tools.ENERGY_COSTS:
		_assert_quiet(int(Tools.ENERGY_COSTS[verb]) % Tools.BASE_COST == 0,
			"%s's cost is a whole multiple of 30" % verb)
	_flush_quiet("every cost is a multiple of the base, so Q-38's multipliers stay whole")

	# --- the same day at 1x ---------------------------------------------------
	#
	# The load-bearing claim of the whole item: this changes the ruler, not the
	# game. Twenty base actions fill a day exactly, the twenty-first is the one
	# that would overdraw, and Q-11's soft floor catches it in exactly the same
	# place it always did.
	SimRng.reseed(29)
	var world := SimWorld.new()
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	for ty in range(4, 12):
		for tx in range(4, 12):
			world.set_tile_state(tx, ty, "cleared")
			world.set_object(tx, ty, "")
	var spent := 0
	var refused_at := -1
	gs.hard_energy = true  # phase 2's rule, so the refusal is visible at all
	for i in 40:
		var tile := Vector2i(4 + i % 8, 4 + i / 8)
		var res := world.apply_action({ "verb": "till", "target": tile, "actor": "player" }, gs)
		if not res.ok:
			refused_at = i
			break
		spent += 1
	_assert(spent == 20 and refused_at == 20,
		"twenty base actions fill a day and the twenty-first is refused, exactly as at 20 points")
	_assert(gs.energy == 0, "with the meter landing on nothing left over — 600 divides by 30")
	gs.hard_energy = false
	var soft := world.apply_action({ "verb": "till", "target": Vector2i(6, 6), "actor": "player" }, gs)
	_assert(soft.ok and gs.energy == 0,
		"and phase 1's soft floor still lets the 21st through at zero (Q-11)")
	gs.free()

	# --- every fraction-reader is unchanged, proven pair by pair ---------------
	#
	# `Daylight`, `CotPresentation` and the sky glyph are all ratios over
	# `energy / max_energy`, so re-partitioning must be invisible to them. This is
	# the proof rather than the claim: the old scale and the new one are asked the
	# same question at every equivalent instant and must answer identically.
	for e in range(0, 21):
		var fine: int = e * 30
		_assert_quiet(Daylight.tint_for(e, 20).is_equal_approx(Daylight.tint_for(fine, 600)),
			"tint at %d/20 == tint at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(Daylight.fraction(e, 20), Daylight.fraction(fine, 600)),
			"fraction at %d/20 == fraction at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(Daylight.progress(e, 20), Daylight.progress(fine, 600)),
			"arc progress at %d/20 == arc progress at %d/600" % [e, fine])
		# (the sky glyph was the fourth reader checked here until Q-72 retired it
		# with T-34; `is_night` carries its threshold now)
		_assert_quiet(Daylight.is_night(e, 20) == Daylight.is_night(fine, 600),
			"night at %d/20 == night at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(CotPresentation.dusk_ramp(e, 20),
				CotPresentation.dusk_ramp(fine, 600)),
			"dusk ramp at %d/20 == dusk ramp at %d/600" % [e, fine])
		_assert_quiet(is_equal_approx(CotPresentation.glow_alpha(e, 20, 1.25),
				CotPresentation.glow_alpha(fine, 600, 1.25)),
			"lamp at %d/20 == lamp at %d/600" % [e, fine])
	_flush_quiet("every fraction-reader gives the same answer at both scales, at all 21 instants")

	# Q-11's own floor pulse moved from `energy <= 2` to a stated threshold, and
	# it must land on the same instant: two base actions' worth of daylight left.
	_assert(CotPresentation.at_floor(60) and not CotPresentation.at_floor(61),
		"the Q-11 cot pulse still starts with two base actions left (was energy <= 2)")
	_assert(CotPresentation.at_floor(0), "and it is certainly on at an empty day")

	# --- the arc's own geometry ----------------------------------------------
	_assert(is_equal_approx(Daylight.progress(600, 600), 0.0)
			and is_equal_approx(Daylight.progress(0, 600), 1.0),
		"the arc walks 0 at sunrise to 1 at dusk")
	_assert(Daylight.TICKS.size() == 3, "three ticks, as the box asks")
	var last_f := 1.1
	for tick in Daylight.TICKS:
		var f: float = float(tick["f"])
		_assert_quiet(f < last_f, "%s comes after the tick before it" % tick["id"])
		last_f = f
		var found := false
		for stop in Daylight.STOPS:
			if is_equal_approx(float(stop["f"]), f):
				found = true
		_assert_quiet(found, "the %s tick sits on one of the sky's own stops" % tick["id"])
	_flush_quiet("the arc's ticks are the hours the tint itself turns — no invented thresholds")
	_assert(is_equal_approx(Daylight.NIGHT_F, float(Daylight.TICKS[2]["f"])),
		"and the token becomes a moon exactly as it passes the dusk tick")

	# --- v1 -> v2: a legacy save loads at the fraction it was saved at ---------
	var legacy := {
		"version": 1,
		"world": {
			"tiles": world.tiles.duplicate(true),
			"objects": world.objects.duplicate(true),
			"actors": {
				"player": { "species": "farmer", "x": 3, "y": 3, "facing": "down",
					"energy": -1, "extra": {} },
				"chicken": { "species": "chicken", "x": 5, "y": 5, "facing": "down",
					"energy": 7, "extra": {} },
			},
		},
		"state": { "energy": 14, "max_energy": 20 },
	}
	var migrated := SaveGame.migrate(legacy)
	# Migration is a chain since v3 (the door, 2026-09-06): a v1 file is scaled to
	# v2 and then padded to v3, and what a caller gets back is always current.
	_assert(int(migrated.get("version", 0)) == SaveGame.VERSION,
		"a v1 save migrates all the way to the current version")
	_assert(int(legacy["state"]["energy"]) == 14,
		"and the caller's own dictionary is left alone — migrate copies, it does not rewrite")
	var w1 := SimWorld.new()
	var gs1 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, w1, gs1), "a v1 save still restores")
	_assert(gs1.energy == 420 and gs1.max_energy == 600,
		"with her meter scaled x30 — 14/20 lands as 420/600")
	_assert(is_equal_approx(Daylight.fraction(gs1.energy, gs1.max_energy),
			Daylight.fraction(14, 20)),
		"which is the same fraction, and therefore the same sky she saved under")
	_assert(w1.energy_of("chicken") == 210, "and every actor's meter scales with it (7 -> 210)")
	_assert(int(w1.actor("player").get("energy", 0)) == -1,
		"except the player's world-side sentinel, which is not a meter and must not be multiplied")
	gs1.free()

	# The pre-M2.5 shape of the same thing: meters in their own `actor_energy` map.
	var legacy_map := {
		"version": 1,
		"world": {
			"tiles": world.tiles.duplicate(true),
			"objects": world.objects.duplicate(true),
			"actor_energy": { "chicken": 5 },
		},
		"state": { "energy": 20, "max_energy": 20 },
	}
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy_map, w2, gs2), "a pre-registry v1 save restores too")
	_assert(w2.energy_of(SimWorld.ACTOR_CHICKEN) == 150,
		"and the old actor_energy map is scaled on the way through the compat shim")
	_assert(gs2.energy == 600 and gs2.max_energy == 600, "a full day saved is a full day loaded")
	gs2.free()

	# A v2 save is not scaled twice, and a version this build has never heard of
	# is still unloadable rather than guessed at.
	var w3 := SimWorld.new()
	var gs3 = load("res://systems/game_state.gd").new()
	gs3.energy = 420
	_assert(SaveGame.restore(SaveGame.capture(world, gs3), w3, gs3),
		"a save this build wrote round-trips")
	_assert(gs3.energy == 420, "at the number it was written with, unscaled")
	_assert(SaveGame.migrate({ "version": 99 }).is_empty(), "a future save is still unloadable")
	_assert(SaveGame.migrate({}).is_empty(), "and so is one with no version at all")
	gs3.free()

	# --- the real fixtures, at the fraction each of them was saved at ----------
	#
	# The synthetic cases above prove the arithmetic; these are the files an
	# actual player would be carrying. Each must come back under the sky it went
	# down under. The roster of shelved sessions lives in SHELF (top of this file).
	# A folder that is not in SHELF is *skipped*, not failed: being unclassified is
	# paperwork, and paperwork must not turn the suite red (2026-09-02, see SHELF's
	# own comment). Everything SHELF does claim stays pinned exactly as before.
	var dir := DirAccess.open("res://playtests")
	_assert(dir != null, "the playtests fixtures directory is readable")
	var unclassified: Array[String] = []
	if dir != null:
		for name in dir.get_directories():
			if not SHELF.has(name):
				unclassified.append(name)
	var checked := 0
	if dir != null:
		for name in dir.get_directories():
			if not SHELF.has(name):
				continue
			var path := "res://playtests/%s/autosave.json" % name
			var data := SaveGame.load_dict(path)
			if data.is_empty() or not data.get("state", {}).has("energy"):
				continue
			var was := Daylight.fraction(int(data["state"]["energy"]),
				int(data["state"].get("max_energy", 20)))
			checked += 1
			var wf := SimWorld.new()
			var gsf = load("res://systems/game_state.gd").new()
			_assert_quiet(SaveGame.restore(data, wf, gsf), "%s restores" % name)
			_assert_quiet(gsf.max_energy == 600, "%s loads into a 600-unit day" % name)
			_assert_quiet(is_equal_approx(Daylight.fraction(gsf.energy, gsf.max_energy), was),
				"%s loads at the fraction it was saved at (%.3f)" % [name, was])
			_assert_quiet(Daylight.tint_for(gsf.energy, gsf.max_energy).is_equal_approx(
					Daylight.tint_for(int(data["state"]["energy"]),
						int(data["state"].get("max_energy", 20)))),
				"%s wakes under the same sky" % name)
			gsf.free()
	_flush_quiet("every shelved autosave in playtests/ loads at its own hour (%d)" % checked)
	_assert(checked == SHELF.size(),
		"all %d shelved sessions were checked (%d)" % [SHELF.size(), checked])
	if not unclassified.is_empty():
		print("      note: %d session(s) in playtests/ not yet in SHELF: %s"
			% [unclassified.size(), ", ".join(unclassified)])
		print("      HQ lists these under Playtests; classifying one pins it here.")


func test_q50_clearing_costs() -> void:
	print("\n--- Q-50: expansion is exertion — per-obstacle clearing costs ---")

	# The ruling (2026-09-02): early-game pacing leans on clearing costs.
	# Expanding into debris costs noticeably more than tending cleared land, and
	# the costs differ by obstacle — a weed is a bare-handed tug, a downed log
	# heavier, a standing tree or a rock dear. The exact numbers are [Playtest];
	# the *ordering* is the ruling, so the ordering gets its own asserts below.
	SimRng.reseed(50)
	var world := SimWorld.new()
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()

	# --- the ladder, charged at the gateway -----------------------------------
	# Each rung through apply_action itself: the cost is sim truth, so a replayed
	# session spends the identical clock.
	var ladder := [
		["obstacle_weed", "clear_weed", 30],
		["obstacle_log", "clear_log", 60],
		["obstacle_tree", "clear_tree", 90],
		["obstacle_rock", "clear_rock", 90],
	]
	var col := 4
	for step in ladder:
		var tile := Vector2i(col, 4)
		col += 1
		world.set_tile_state(tile.x, tile.y, String(step[0]))
		world.set_object(tile.x, tile.y, "")
		var before: int = gs.energy
		var res := world.apply_action({ "verb": String(step[1]), "target": tile, "actor": "player" }, gs)
		_assert(res.get("ok", false), "%s goes through the gateway" % step[1])
		_assert(before - gs.energy == int(step[2]),
			"%s charges %d fine units, sim-side" % [step[1], step[2]])
		_assert(String(world.get_tile(tile.x, tile.y).get("state", "")) == "cleared",
			"and the %s tile comes out cleared" % step[0])
		_assert(int(gs.clear_counts.get(String(step[1]), 0)) == 1,
			"and the clear is counted (T-10's proof trail)")

	# --- the ordering is the ruling -------------------------------------------
	_assert(Tools.get_energy_cost("clear_weed") <= Tools.get_energy_cost("clear_log")
			and Tools.get_energy_cost("clear_log") < Tools.get_energy_cost("clear_tree"),
		"the ladder climbs: weed <= log < tree")
	_assert(Tools.get_energy_cost("clear_tree") == Tools.get_energy_cost("clear_rock"),
		"tree and rock share the dear tier")
	for verb in ["clear_log", "clear_tree", "clear_rock"]:
		_assert_quiet(Tools.get_energy_cost(verb) >= 2 * Tools.get_energy_cost("till"),
			"%s costs at least twice a tend" % verb)
	_flush_quiet("expanding into standing debris costs at least double any tending verb (Q-50)")

	# --- Q-11's soft floor survives the dearest rung --------------------------
	# The kid-friction rule checked before tuning upward: at zero energy in
	# phase 1 the verb still lands — a dear clear spends clock, never locks out.
	gs.set_energy(0)
	gs.hard_energy = false
	world.set_tile_state(8, 4, "obstacle_rock")
	world.set_object(8, 4, "")
	var floor_res := world.apply_action({ "verb": "clear_rock", "target": Vector2i(8, 4), "actor": "player" }, gs)
	_assert(floor_res.get("ok", false) and gs.energy == 0,
		"a dear clear at zero energy still lands and the meter clamps at 0 (Q-11 soft floor)")

	# --- an NPC pays the same ladder from its own meter (S-3) -----------------
	world.set_tile_state(9, 4, "obstacle_tree")
	world.set_object(9, 4, "")
	var npc_before: int = world.energy_of(SimWorld.ACTOR_CHICKEN)
	var npc_res := world.apply_action(
		{ "verb": "clear_tree", "target": Vector2i(9, 4), "actor": SimWorld.ACTOR_CHICKEN }, gs)
	_assert(npc_res.get("ok", false)
			and npc_before - world.energy_of(SimWorld.ACTOR_CHICKEN) == Tools.DEAR_COST,
		"an NPC's tree costs the same 90, from its own meter — no cheaper verb for bots (S-3)")
	gs.free()


func test_clock_digits() -> void:
	print("\n--- T-34/T-36: the clock gets digits (6:00 AM → 4:00 PM) ---")

	# --- the boundary instants the rulings name -------------------------------
	# The hours are T-34's; the face is T-36's (12-hour with AM/PM, the designer
	# overturning T-34's 24-hour deviation on 2026-08-31).
	_assert(Daylight.clock_text(600, 600) == "6:00 AM", "a full meter opens the day at 6:00 AM")
	_assert(Daylight.clock_text(570, 600) == "6:30 AM", "one base verb (30) is half an hour")
	_assert(Daylight.clock_text(540, 600) == "7:00 AM", "two of them make an hour")
	_assert(Daylight.clock_text(300, 600) == "11:00 AM", "half a day's work lands at 11:00 AM")
	_assert(Daylight.clock_text(60, 600) == "3:00 PM", "two base verbs left is 3:00 PM")
	_assert(Daylight.clock_text(0, 600) == "4:00 PM", "and an empty meter is 4:00 PM")

	# --- the noon wrap, marked by the suffix and nothing else -----------------
	_assert(Daylight.clock_text(241, 600) == "11:59 AM", "the last morning minute is 11:59 AM")
	_assert(Daylight.clock_text(240, 600) == "12:00 PM", "noon is 12:00 PM — the suffix turns, the hour holds")
	_assert(Daylight.clock_text(181, 600) == "12:59 PM", "12 stays 12 through its whole hour")
	_assert(Daylight.clock_text(180, 600) == "1:00 PM", "and then the afternoon counts from 1")

	# --- one unit IS one minute -----------------------------------------------
	#
	# The identity T-34 is built on, asserted directly so that anyone who ever
	# adds a conversion factor breaks a test instead of quietly re-scaling the
	# day. Every single unit of the meter is one minute of the clock face, and the
	# meter's whole length is exactly the ten-hour workday.
	_assert(Tools.DAY_UNITS == 600, "the day is 600 units (T-29)")
	_assert(Daylight.clock_minutes(0, Tools.DAY_UNITS)
			- Daylight.clock_minutes(Tools.DAY_UNITS, Tools.DAY_UNITS) == Tools.DAY_UNITS,
		"and the clock spans exactly DAY_UNITS minutes — 600 units, ten hours, no factor")
	for spent in range(0, Tools.DAY_UNITS + 1):
		_assert_quiet(Daylight.clock_minutes(Tools.DAY_UNITS - spent, Tools.DAY_UNITS)
				== 6 * 60 + spent,
			"unit %d spent reads minute 6:00 + %d" % [spent, spent])
	_flush_quiet("every one of the 600 units is one minute of the clock face")
	_assert(Daylight.clock_text(Tools.DAY_UNITS - Tools.get_energy_cost("clear_log"),
			Tools.DAY_UNITS) == "7:00 AM",
		"a heavy clear (60) is a full hour, straight out of the cost table")

	# --- the face's whole grammar (T-36) --------------------------------------
	# Digits, a colon, and exactly one of the two accepted markers — the ruling
	# accepts "AM"/"PM" on the clock and nothing wider. Checked at every minute
	# of the workday: hour 1–12 (never 0, never 13+), minutes zero-padded, the
	# suffix AM strictly before noon and PM from it.
	for spent2 in range(0, Tools.DAY_UNITS + 1):
		var face: String = Daylight.clock_text(Tools.DAY_UNITS - spent2, Tools.DAY_UNITS)
		var parts := face.split(" ")
		var ok_face := parts.size() == 2 and (parts[1] == "AM" or parts[1] == "PM")
		if ok_face:
			var hm := parts[0].split(":")
			ok_face = hm.size() == 2 and hm[0].is_valid_int() and hm[1].is_valid_int() \
				and int(hm[0]) >= 1 and int(hm[0]) <= 12 and hm[1].length() == 2
			var expect_pm := 6 * 60 + spent2 >= 12 * 60
			ok_face = ok_face and (parts[1] == "PM") == expect_pm
		_assert_quiet(ok_face, "the face '%s' is h:mm plus AM/PM, hour 1–12" % face)
	_flush_quiet("every minute of the day wears a legal 12-hour face")

	# --- it parks at dusk, and soft-floor work happens in the evening ---------
	#
	# Q-11's floor means the verbs still resolve on an empty meter, and
	# `GameState.set_energy` clamps at 0 — so that work is *evening* work (Q-73's
	# span) and the digits do not move for it.
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "6:00 AM",
		"a fresh day starts at 6:00 AM")
	gs.set_energy(0)
	for _i in 5:
		gs.set_energy(gs.energy - Tools.get_energy_cost("till"))
	_assert(gs.energy == 0, "five actions past the floor leave the meter at 0 (Q-11)")
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "4:00 PM",
		"and the clock is still parked at 4:00 PM — the evening is not on the face")
	_assert(Daylight.clock_text(-300, 600) == "4:00 PM",
		"even an unclamped negative cannot push the digits past dusk")
	_assert(Daylight.clock_text(900, 600) == "6:00 AM", "nor an over-full meter before dawn")
	_assert(Daylight.clock_text(5, 0) == "6:00 AM", "and a degenerate day reads as its opening")

	# --- sleep at any hour wakes at 6:00 AM -----------------------------------
	gs.set_energy(240)
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "12:00 PM", "asleep at noon...")
	gs.start_new_day()
	_assert(Daylight.clock_text(gs.energy, gs.max_energy) == "6:00 AM",
		"...and awake at 6:00 AM — an unspent afternoon is not banked (T-14's sub-ruling)")
	gs.free()

	# --- the clock is the one reader that counts units, not ratios ------------
	# Deliberate, and worth pinning: the legacy 20-unit scale would read 6:20 at
	# dusk, which is why saves are migrated ×30 on load (T-29) rather than the
	# clock being taught two rulers.
	_assert(Daylight.clock_text(0, 20) == "6:20 AM",
		"the clock reads units, not the fraction every other reader here uses")


func test_satisfied_states() -> void:
	print("\n--- The third state has a voice (T-18/T-19, Q-42) Tests ---")

	# Evidence, from the 2026-08-28 adult session on a fresh farm: 14 taps
	# produced nothing at all and 12 of them held the watering can over crops
	# already watered that day; three separate tiles were tapped 3+ times. The
	# game has three answers — did it, cannot, nothing-to-do — and only the first
	# two spoke. Q-42 ruled that the third answers **yes-done, never no**.
	GameState.reset()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	SimRng.reseed(41)
	farm.sim.generate()
	var t := Vector2i(7, 6)

	# --- already watered ------------------------------------------------------
	farm.sim.tiles[t.y][t.x]["state"] = "growing"
	farm.sim.tiles[t.y][t.x]["crop_type"] = "wheat"
	farm.sim.tiles[t.y][t.x]["watered_today"] = false
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "",
		"a dry crop is not satisfied — there is real work to do")
	_assert(not ActionRouter.resolve(farm, GameState, t, t).is_empty(),
		"and the action resolves, so nothing is acknowledged over a live action")
	farm.sim.tiles[t.y][t.x]["watered_today"] = true
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "already_watered",
		"a crop watered today answers 'already done' — the exact 20-dead-tap case")
	_assert(ActionRouter.blocked_reason(farm, GameState, t) == "",
		"and it is NOT a refusal: a good state must never wobble")
	_assert(ActionRouter.resolve(farm, GameState, t, t).is_empty(),
		"resolve still declines, so the acknowledgement is the only answer there is")
	farm.sim.tiles[t.y][t.x]["state"] = "seeded"
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "already_watered",
		"a watered seed answers the same way as a watered sprout")

	# A ripe crop is not "satisfied" — there is a harvest waiting.
	farm.sim.tiles[t.y][t.x]["state"] = "ready"
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "",
		"a ripe crop is work, not a finished state")
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	_assert(ActionRouter.satisfied_reason(farm, GameState, t) == "",
		"cleared ground has nothing to acknowledge")
	_assert(ActionRouter.satisfied_reason(farm, GameState, Vector2i(-3, -3)) == "",
		"an out-of-bounds tile does not crash or invent an answer")

	# --- the well, with a full can -------------------------------------------
	var well := Vector2i(6, 1)
	_assert(farm.get_object(well.x, well.y) == "well", "the well is where the layout puts it")
	GameState.watering_can_charges = GameState.max_watering_can_charges
	_assert(ActionRouter.satisfied_reason(farm, GameState, well) == "can_full",
		"a full can at the well answers 'already done'")
	GameState.watering_can_charges = 3
	_assert(ActionRouter.satisfied_reason(farm, GameState, well) == "",
		"a part-empty can still has a refill to do")

	# --- the bin, with an empty basket ---------------------------------------
	var bin := Vector2i(4, 1)
	_assert(farm.get_object(bin.x, bin.y) == "shipping_bin", "the bin is where the layout puts it")
	GameState.pouch["wheat"] = 0
	GameState.pouch["tomato"] = 0
	_assert(ActionRouter.satisfied_reason(farm, GameState, bin) == "",
		"an empty pouch still lets the player open the bin")
	GameState.pouch["wheat"] = 0
	_assert(ActionRouter.satisfied_reason(farm, GameState, bin) == "",
		"the bin menu remains available after a deposit")
	GameState.pouch["wheat"] = 0 + 1
	_assert(ActionRouter.satisfied_reason(farm, GameState, bin) == "",
		"one crop over the line has a sale to make")

	# The cot is never "satisfied" — sleeping is always available (S-7).
	_assert(ActionRouter.satisfied_reason(farm, GameState, Vector2i(2, 1)) == "",
		"the cot is never answered as already-done; sleep is never refused")

	# --- F-5: the refusal vocabulary must be one vocabulary -------------------
	# blocked_reason() returned human phrases ("no seeds") while farm's icon table
	# matched the sim's codes ("no_seeds"), so they never met and every
	# router-level refusal silently lost its picture — the wordless half of the
	# feedback, dropped on the exact path built to end silent refusals.
	var Farm = load("res://world/farm.gd")
	for code in ["no_seeds", "no_water", "no_energy"]:
		_assert(Farm.REFUSE_ICONS.has(code),
			"the refusal icon table knows the sim code '%s'" % code)
	var src := (ActionRouter.get_script().source_code as String)
	var body := src.substr(src.find("func blocked_reason"))
	body = body.substr(0, body.find("\n## Why a tap produced no action because"))
	for phrase in ["\"no seeds\"", "\"too tired\"", "\"watering can empty\""]:
		_assert(not body.contains(phrase),
			"blocked_reason no longer speaks the human phrase %s" % phrase)

	# Every code blocked_reason can actually emit, driven through real states, has
	# a picture. This is the assertion that stops F-5 recurring.
	var emitted: Dictionary = {}
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "tilled"
	GameState.pouch["wheat"] = 0
	emitted[ActionRouter.blocked_reason(farm, GameState, t)] = true
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	GameState.energy = 0
	emitted[ActionRouter.blocked_reason(farm, GameState, t)] = true
	GameState.reset()
	farm.sim.tiles[t.y][t.x]["state"] = "seeded"
	farm.sim.tiles[t.y][t.x]["watered_today"] = false
	GameState.watering_can_charges = 0
	emitted[ActionRouter.blocked_reason(farm, GameState, t)] = true
	emitted.erase("")
	_assert(emitted.size() == 3, "three distinct refusal codes are reachable")
	for code in emitted.keys():
		_assert(Farm.REFUSE_ICONS.has(String(code)),
			"refusal code '%s' from the router has an icon" % code)

	# --- the sim's benign failures are acknowledged, not refused --------------
	# They are the same third state arriving from the other layer: a full can and
	# an empty basket are perfectly good states, so they must not wobble.
	for reason in Farm.BENIGN_FAILURES.keys():
		_assert(not Farm.REFUSE_ICONS.has(String(reason)),
			"benign reason '%s' has no refusal picture — it is not a refusal" % reason)

	# --- the cue is never the wobble -----------------------------------------
	# Q-42's one hard rule. Asserted structurally so a future edit that reaches for
	# refuse_at() inside acknowledge_at() fails here rather than in a playtest.
	var fsrc := (Farm.source_code as String)
	var ack := fsrc.substr(fsrc.find("func acknowledge_at"))
	ack = ack.substr(0, ack.find("\n\nfunc ") if ack.find("\n\nfunc ") != -1 else ack.length())
	_assert(not ack.contains("refuse_at"), "acknowledge_at never routes to the refusal wobble")
	_assert(not ack.contains("\"nope\""), "and never plays the nope sound")

	GameState.reset()
	farm.free()


func test_parcel_generation() -> void:
	print("\n--- Parcel world generation (T-8, Q-34) Tests ---")

	# Obstacles used to be sprinkled uniformly at 25% across the whole map, which
	# made the yard's rocks and logs *noise*: indistinguishable in affordance from
	# a weed, differing only in which invisible tool resolved them. Obstacle type
	# is now a property of the parcel a tile belongs to, so a rock she cannot yet
	# break is a legible future behind a hedge instead.
	SimRng.reseed(4242)
	var a := SimWorld.new()
	a.generate()
	SimRng.reseed(4242)
	var b := SimWorld.new()
	b.generate()
	var gs_a = load("res://systems/game_state.gd").new()
	var gs_b = load("res://systems/game_state.gd").new()
	_assert(SaveGame.capture_canonical(a, gs_a) == SaveGame.capture_canonical(b, gs_b),
		"the same seed generates a byte-identical world")

	SimRng.reseed(4243)
	var c := SimWorld.new()
	c.generate()
	var gs_c = load("res://systems/game_state.gd").new()
	_assert(SaveGame.capture_canonical(a, gs_a) != SaveGame.capture_canonical(c, gs_c),
		"and a different seed generates a different one")
	gs_b.free()
	gs_c.free()

	# **The generator must not compute a distance from spawn.** "Ring" was a
	# placeholder and the arrangement is an explicitly free design parameter
	# (designer, 2026-08-29); a generator that derives type from distance turns
	# the placeholder into the design by default. It takes a region definition.
	var src := (load("res://systems/sim/sim_world.gd").source_code as String)
	_assert(not src.contains("ring_index"), "generation carries no ring_index")
	_assert(not src.contains("distance_from_spawn"), "nor a distance from spawn")

	# Each parcel contains only the obstacles it declares — one new thing per
	# parcel (Valve principle 4). The wood is the single deliberate exception: a
	# standing tree is where a log comes from (Q-39).
	#
	# `scatter` joins the allowance as of 2026-09-01, ruled by the designer: an
	# open parcel may hold a handful of rocks and logs she cannot clear yet. It is
	# still declared data, so nothing arrives here that the layout did not ask
	# for — and it is deliberately NOT what the parcel *introduces*, which stays
	# `obstacle`/`extra_obstacle` (see `test_parcel_scatter`).
	for p in WorldLayout.parcels():
		var allowed := { "": true }
		allowed[String(p.get("obstacle", ""))] = true
		allowed[String(p.get("extra_obstacle", ""))] = true
		for kind in WorldLayout.scatter_of(p).get("kinds", []):
			allowed[String(kind)] = true
		var strays := 0
		var own := 0
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					var st := String(a.tiles[ty][tx].get("state", ""))
					if not st.begins_with("obstacle"):
						continue
					if allowed.has(st):
						own += 1
					else:
						strays += 1
		_assert(strays == 0, "parcel '%s' holds no obstacle but its own" % p.get("id", "?"))
		if String(p.get("obstacle", "")) != "":
			_assert(own > 0, "parcel '%s' actually contains its obstacle" % p.get("id", "?"))

	# The boundary is the design's real content: "not yet" expressed as land.
	var boundary_tiles := 0
	for bnd in WorldLayout.boundaries():
		for r in bnd.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					boundary_tiles += 1
					var st := String(a.tiles[ty][tx].get("state", ""))
					var is_gate := (st == WorldLayout.GATE_CLOSED or st == WorldLayout.GATE_OPEN)
					_assert_quiet(st == String(bnd.get("kind", "")) or is_gate,
						"boundary tile (%d,%d) is boundary or gate" % [tx, ty])
					_assert_quiet(not a.is_walkable(tx, ty) or is_gate,
						"boundary tile (%d,%d) is not walkable" % [tx, ty])
	_assert(boundary_tiles > 0, "the layout draws a boundary at all")
	_flush_quiet("every boundary tile is a wall she can see")

	# Gates start closed, so the very first lesson in the game is "not yet" told
	# as land — and an opening gate is the cheapest celebration there is.
	for p in WorldLayout.parcels():
		var g: Vector2i = p.get("gate", Vector2i(-1, -1))
		if g.x < 0:
			continue
		_assert(String(a.tiles[g.y][g.x].get("state", "")) == WorldLayout.GATE_CLOSED,
			"parcel '%s' starts behind a closed gate" % p.get("id", "?"))
		_assert(not a.is_walkable(g.x, g.y), "and a closed gate is not walkable")
		_assert(not a.is_parcel_open(p), "and reads as closed")

	# The yard: the four fixed objects at their known coordinates, and nothing to
	# clear. The integration suite and the robot session both assert these, and
	# moving them would buy nothing.
	# Read off the world's own layout rather than the module constant: since the
	# door (2026-09-06) the generated world is `WorldLayout.WORLD`, which carries
	# its own object list — the same three stations, the farmhouse, and the cot
	# indoors. The claim is unchanged ("every fixed object generation promises is
	# where it says"); what it is asked of is the world the game actually plays.
	for obj in a.layout.get("objects", SimWorld.OBJECT_POSITIONS):
		_assert(a.objects[obj.ty][obj.tx] == obj.type,
			"%s is still at (%d,%d)" % [obj.type, obj.tx, obj.ty])
	var spawn := WorldLayout.spawn(a.layout)
	_assert(a.is_walkable(spawn.x, spawn.y), "the spawn tile is walkable")
	_assert(String(WorldLayout.parcel_at(spawn, a.layout).get("id", "")) == "yard",
		"and it is inside the fenced yard")

	# The pen has a toy in it, not a chore: the yard must contain nothing to
	# clear, or she ignores the neighbour and tidies up instead (design/13 §4a).
	var yard_obstacles := 0
	for r in WorldLayout.parcel_at(spawn, a.layout).get("rects", []):
		var rect: Rect2i = r
		for ty in range(rect.position.y, rect.end.y):
			for tx in range(rect.position.x, rect.end.x):
				if String(a.tiles[ty][tx].get("state", "")).begins_with("obstacle"):
					yard_obstacles += 1
	_assert(yard_obstacles == 0, "the starting yard holds no chores")

	# Both tools lie visibly at their gates from generation (Q-46 strawman).
	for e in WorldLayout.tools():
		var at: Vector2i = e.get("at", Vector2i(-1, -1))
		_assert(a.objects[at.y][at.x] == String(e.get("object", "")),
			"the %s is on the ground at its gate" % e.get("tool", "?"))

	# She is genuinely penned in until the gate opens — that is what makes the
	# spatial restriction real rather than decorative.
	var reachable := _flood(a, spawn)
	var escaped := false
	for t in reachable:
		if String(WorldLayout.parcel_at(t).get("id", "")) != "yard":
			escaped = true
	_assert(not escaped, "nothing outside the yard is reachable before the gate opens")
	_assert(reachable.size() > 20, "but the yard itself is roomy enough to play in")

	gs_a.free()


func test_tool_acquisition() -> void:
	print("\n--- Tools are acquired, not owned (T-9, Q-34) Tests ---")

	# All six tools existed from the first frame, so the yard's rocks and logs
	# were noise. Under Q-34 they become promises: a tool is a solution to a
	# problem she already has, and the lock is land rather than a message.
	var gs = load("res://systems/game_state.gd").new()
	_assert(gs.owns_tool("hands") and gs.owns_tool("hoe"), "she starts with hands and hoe")
	_assert(gs.owns_tool("watering_can") and gs.owns_tool("seeds"), "and the can and seeds")
	_assert(not gs.owns_tool("axe"), "but not the axe")
	_assert(not gs.owns_tool("pickaxe"), "and not the pickaxe")

	var world := SimWorld.new()
	SimRng.reseed(77)
	world.generate()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	# Cycling never lands on a tool she has not got.
	for _i in 24:
		gs.cycle_tool(1)
		_assert_quiet(gs.owns_tool(Tools.key_of(gs.selected_tool)),
			"cycle_tool never selects an unowned tool")
	for _i in 24:
		gs.cycle_tool(-1)
		_assert_quiet(gs.owns_tool(Tools.key_of(gs.selected_tool)),
			"cycle_tool never selects an unowned tool (backwards)")
	_flush_quiet("cycling in both directions only ever lands on tools she has")

	var axe_entry: Dictionary = WorldLayout.tools()[0]
	var at: Vector2i = axe_entry.get("at", Vector2i(-1, -1))
	var gate: Vector2i = axe_entry.get("gate", Vector2i(-1, -1))

	# The proof has not fired, so the tool is a promise: the router yields no
	# action at all and the tap becomes movement.
	_assert(not SimWorld.tool_proof_met(axe_entry, gs), "the axe's proof is not met yet")
	# The playtest readout reads these numbers, and `tool_proof_met` is defined in
	# terms of them, so what is on screen cannot disagree with the gate itself.
	var prog: Dictionary = SimWorld.tool_proof_progress(axe_entry, gs)
	_assert(int(prog.need) == int(axe_entry.get("threshold", 0)),
		"progress reports the threshold the layout actually sets")
	_assert(int(prog.have) == gs.total_harvests(), "and how far along she is")
	_assert(bool(prog.met) == SimWorld.tool_proof_met(axe_entry, gs),
		"and agrees with the gate, because the gate is defined by it")
	_assert(ActionRouter.resolve(farm, gs, at, at).is_empty(),
		"an unearned tool yields no action — she walks over and looks at it")
	_assert(ActionRouter.is_workable(farm, at),
		"but it is still a thing to approach, so she stops beside it rather than on it")

	# And no obstacle it would unlock is actionable either.
	var log_t := Vector2i(23, 3)
	world.set_tile_state(log_t.x, log_t.y, "obstacle_log")
	_assert(ActionRouter.resolve(farm, gs, log_t, log_t).is_empty(),
		"a log yields no action without the axe")
	var rock_t := Vector2i(23, 12)
	world.set_tile_state(rock_t.x, rock_t.y, "obstacle_rock")
	_assert(ActionRouter.resolve(farm, gs, rock_t, rock_t).is_empty(),
		"a rock yields no action without the pickaxe")

	# Q-46(a), from play 2026-08-29: the lock has to be legible *without tapping*,
	# because a tool that looks takeable and answers a tap with nothing is the
	# silent-tap failure T-18 exists to remove — and Q-34 forbids repairing that
	# with a refusal. So an unearned tool is drawn as a silhouette of itself, and
	# the moment it becomes takeable it is the one thing that glows.
	_assert(TeachingFocus.locked_tools(world, gs).has(at),
		"an unearned tool is listed as locked, so presentation can draw it darkened")
	_assert(not TeachingFocus.ready_tools(world, gs).has(at),
		"and is not announced as available")
	_assert(not TeachingFocus.targets(world, gs, at).has(at),
		"and nothing glows on it")

	# Teaching is switched off entirely until the farm is hers, so to see the
	# arbitration at all this fixture has to be past the handover and past the
	# vignette's two days — otherwise the vignette would rightly own the
	# highlight and this would prove nothing.
	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs)
	gs.day = gs.takeover_day + 5

	# Meet the proof (Q-46 strawman: harvests, threshold in the layout data).
	gs.harvest_counts["wheat"] = int(axe_entry.get("threshold", 5))
	_assert(SimWorld.tool_proof_met(axe_entry, gs), "harvesting enough meets the axe's proof")
	_assert(bool(SimWorld.tool_proof_progress(axe_entry, gs).met),
		"and the readout says so too")
	var offer: Dictionary = ActionRouter.resolve(farm, gs, at, at)
	_assert(offer.get("action", "") == "take_tool", "and now the tool answers a tap")
	_assert(offer.get("tool", "") == "axe", "with the tool it will grant")

	_assert(not TeachingFocus.locked_tools(world, gs).has(at),
		"once earned it stops being drawn as locked")
	_assert(TeachingFocus.ready_tools(world, gs).has(at), "and starts being announced")
	_assert(TeachingFocus.targets(world, gs, at).has(at),
		"the moment it becomes takeable is the moment it glows")

	var got := world.apply_action({ "verb": "take_tool", "target": at, "tool": "axe", "actor": "player" }, gs)
	_assert(got.get("ok", false) and got.get("tool", "") == "axe", "take_tool grants the axe")
	_assert(gs.owns_tool("axe"), "and she owns it")
	_assert(world.get_object(at.x, at.y) == "", "and it is no longer on the ground")
	_assert(world.apply_action({ "verb": "take_tool", "target": at, "actor": "player" }, gs).get("reason", "")
		== "no_tool_here", "taking it twice is refused")
	# The beat ends itself: the object is gone, so there is nothing left to point
	# at and no flag was ever needed to remember that she has it.
	_assert(not TeachingFocus.ready_tools(world, gs).has(at),
		"picking it up ends its highlight, with no flag to clear")
	_assert(not TeachingFocus.locked_tools(world, gs).has(at),
		"and a tool that is gone is not drawn as a locked one either")
	# The pickaxe is still lying at its own gate, still unearned, and still
	# correctly listed as locked — taking one tool says nothing about the other.
	_assert(TeachingFocus.locked_tools(world, gs).size() == 1,
		"the pickaxe is untouched by any of this")

	# Acquisition opens the parcel — that is acquisition's visible half.
	_assert(String(world.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_CLOSED,
		"the gate is still closed until the follow-up action")
	var opened := world.apply_action({ "verb": "open_gate", "target": gate, "actor": "world" }, gs)
	_assert(opened.get("ok", false), "open_gate succeeds on a closed gate")
	_assert(String(world.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_OPEN, "and the gate opens")
	_assert(world.is_walkable(gate.x, gate.y), "an open gate is ordinary ground")
	_assert(not world.apply_action({ "verb": "open_gate", "target": gate, "actor": "world" }, gs).get("ok", true),
		"opening an already-open gate is refused rather than silently repeated")
	_assert(not world.apply_action({ "verb": "open_gate", "target": Vector2i(5, 3), "actor": "world" }, gs).get("ok", true),
		"and a non-gate tile is not a gate")

	# With the axe in hand the log finally answers, and the tree with it.
	_assert(ActionRouter.resolve(farm, gs, log_t, log_t).get("action", "") == "clear_log",
		"the log answers once she holds the axe")
	world.set_tile_state(log_t.x, log_t.y, "obstacle_tree")
	_assert(ActionRouter.resolve(farm, gs, log_t, log_t).get("action", "") == "clear_tree",
		"and so does a standing tree")
	world.apply_action({ "verb": "clear_tree", "target": log_t, "actor": "player" }, gs)
	_assert(String(world.get_tile(log_t.x, log_t.y).state) == "cleared", "clear_tree clears it")
	_assert(int(gs.clear_counts.get("clear_tree", 0)) == 1, "and the sim gateway counts the clear")

	# Old saves keep their tools. Every save written before T-9 came from a build
	# where she had all six; confiscating her axe on load would be a bug wearing
	# a migration's clothes.
	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": { "day": 4 } }
	var gs_old = load("res://systems/game_state.gd").new()
	var w_old := SimWorld.new()
	_assert(SaveGame.restore(legacy, w_old, gs_old), "a pre-M1.5 save still restores")
	_assert(gs_old.owns_tool("axe") and gs_old.owns_tool("pickaxe"),
		"and defaults to owning every tool")
	_assert(gs_old.takeover_day == 1, "and to a takeover day of 1 — the world began when she did")

	# A current save round-trips the real ownership.
	var fresh := SaveGame.capture(world, gs)
	var gs_rt = load("res://systems/game_state.gd").new()
	var w_rt := SimWorld.new()
	SaveGame.restore(JSON.parse_string(JSON.stringify(fresh)), w_rt, gs_rt)
	_assert(gs_rt.owns_tool("axe"), "a current save keeps the axe she earned")
	_assert(not gs_rt.owns_tool("pickaxe"), "and keeps the pickaxe she has not")
	_assert(int(gs_rt.clear_counts.get("clear_tree", 0)) == 1, "and the clear counts round-trip")

	gs.free()
	gs_old.free()
	gs_rt.free()
	farm.free()


# Reported from live play 2026-09-08, the first session with the door in it: a
# repeat player earned the axe, walked home to bed, and a gold edge-arrow
# pointed at the tool *through the roof* — the farm page is literally up in
# world coordinates from the bedroom. The arbitration now filters every beat's
# answer to the page she is standing on, and a beat whose whole answer is
# elsewhere falls through, exactly as the priority order already promises.
func test_lessons_never_point_through_a_door() -> void:
	print("\n--- A lesson never points through a door (2026-09-08) Tests ---")

	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(77)
	world.generate()

	# Past the handover and past the vignette's two days, so the arbitration is
	# live — the tool-acquisition fixture's own preamble.
	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs)
	gs.day = gs.takeover_day + 5

	# Earn the axe and leave it lying at its gate: the ready-tool beat is live.
	var axe_entry: Dictionary = WorldLayout.tool_for_gate(WorldLayout.gate_for_tool("axe"), world.layout)
	var at: Vector2i = axe_entry.get("at", Vector2i(-1, -1))
	gs.harvest_counts["wheat"] = int(axe_entry.get("threshold", 5))
	_assert(SimWorld.tool_proof_met(axe_entry, gs), "the axe's proof is met")

	# From the yard, the announcement stands.
	var outdoors := Vector2i(5, 5)
	_assert(TeachingFocus.targets(world, gs, outdoors).has(at),
		"from her own page, the earned tool glows")

	# From the bedroom, it does not follow her through the door.
	var indoors := Vector2i(15, 32)
	_assert(world.page_of(indoors) != world.page_of(at), "the fixture spans the two pages")
	var pointed := TeachingFocus.targets(world, gs, indoors)
	_assert(not pointed.has(at), "an earned tool on the farm does not glow from the bedroom")
	for t in pointed:
		_assert_quiet(world.page_of(t) == world.page_of(indoors),
			"nothing the arbitration returns indoors is on another page")

	# And with no known player tile (the detached farms), nothing is filtered.
	_assert(TeachingFocus.targets(world, gs).has(at),
		"with no player position the filter scopes nothing out")

	gs.free()


func test_boundary_tap_answers() -> void:
	print("\n--- A tap past the boundary still answers (T-8, design/13 §5) Tests ---")

	# The design risk in Q-34 is sharp and it is the whole reason the lock is
	# land: a four-year-old cannot read a locked-tool message, and a tap that
	# silently does nothing is precisely the failure M1 spent a milestone
	# eliminating. So the honest answer to a tap across the fence is *movement* —
	# she walks to the boundary and stops, which reads correctly without a word.
	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(1234)
	world.generate()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim = world

	var spawn := WorldLayout.spawn()
	var beyond := Vector2i(17, 4)  # deep inside the neighbour's plot, gate closed
	_assert(String(WorldLayout.parcel_at(beyond).get("id", "")) == "neighbour",
		"the test target really is inside a closed parcel")
	_assert(world.is_walkable(beyond.x, beyond.y), "and is itself perfectly ordinary ground")

	_assert(Pathfinding.find_path(farm, spawn, beyond).is_empty(),
		"there is genuinely no route there")
	_assert(ActionRouter.blocked_reason(farm, gs, beyond) == "" ,
		"and no refusal reason is produced — she has done nothing wrong")
	_assert(ActionRouter.satisfied_reason(farm, gs, beyond) == "",
		"nor is it an already-done state")

	# The fallback: as far toward it as the land allows.
	var toward: Array = Pathfinding.find_path_nearest(farm, spawn, beyond)
	_assert(not toward.is_empty(), "she still gets a walk order — the tap is never silent")
	var edge: Vector2i = toward[toward.size() - 1]
	_assert(world.is_walkable(edge.x, edge.y), "and it ends somewhere she can stand")
	_assert(String(WorldLayout.parcel_at(edge).get("id", "")) == "yard",
		"inside her own yard, because that is as far as the land goes")
	var d_edge: int = absi(edge.x - beyond.x) + absi(edge.y - beyond.y)
	var d_spawn: int = absi(spawn.x - beyond.x) + absi(spawn.y - beyond.y)
	_assert(d_edge < d_spawn, "and closer to what she tapped than where she started")

	# Right up against the boundary, not somewhere vaguely in that direction.
	var touching := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = edge + d
		if WorldLayout.is_boundary_state(String(world.get_tile(n.x, n.y).get("state", ""))):
			touching = true
	_assert(touching, "she stops with her nose against the fence")

	# Once the gate opens the same tap is an ordinary walk, no special case.
	var gate := WorldLayout.gate_of("neighbour")
	world.apply_action({ "verb": "open_gate", "target": gate, "actor": "neighbour" }, gs)
	_assert(not Pathfinding.find_path(farm, spawn, beyond).is_empty(),
		"an open gate makes the ordinary path work again")

	gs.free()
	farm.free()


func test_cold_open() -> void:
	print("\n--- The cold open (T-13, Q-37/Q-45) Tests ---")

	# She is not a cutscene system, she is one more actor: her verbs go through
	# apply_action as actor "neighbour", exactly like the crow and chicken (S-3).
	# So the whole opening is replayable, deterministic, and produces real world
	# state rather than scripted fakery.
	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(2026)
	world.generate()

	var gate := WorldLayout.gate_of("neighbour")
	_assert(not ColdOpen.is_done(world), "a fresh farm still has the scene ahead of it")

	# The stage: every tile the scene will act on. Presentation waits until the
	# player can see all of it before letting the neighbour start, so this has to
	# actually cover her work — a rect that missed the far end of her row would
	# start the scene exactly where the report said it was invisible.
	var stage := ColdOpen.stage_rect(world)
	_assert(stage.size.x > 0 and stage.size.y > 0, "the scene has a stage rect")
	var plot: Dictionary = world.layout.get("neighbour_plot", {})
	var must_cover: Array[Vector2i] = [
		plot.get("cleared_for_demo", Vector2i(-1, -1)),
		plot.get("wave_at", Vector2i(-1, -1)),
		WorldLayout.gate_of("neighbour"),
	]
	for e in plot.get("growing", []):
		must_cover.append(e.get("at", Vector2i(-1, -1)))
	for t in plot.get("seeded", []):
		must_cover.append(t)
	for t in must_cover:
		_assert_quiet(t.x < 0 or stage.has_point(t), "the stage covers %s" % t)
	_flush_quiet("the stage rect covers every tile the scene acts on")
	# And it is genuinely wider than one screenful from spawn, which is the whole
	# reason the wait exists: 8.3 tiles either side of a camera clamped at spawn
	# cannot reach the far end of her row.
	_assert(stage.end.x >= 17, "it reaches the far end of her row (x=%d)" % stage.end.x)
	_assert(ColdOpen.gate(world) == gate, "and the scene knows which gate it ends with")

	var energy_before: int = gs.energy
	var log := ReplayLog.new()
	log.start(2026)
	var steps := 0
	var all_ok := true
	var actors := {}
	for _i in ColdOpen.MAX_STEPS:
		var act := ColdOpen.next_action(world, gs)
		if act.is_empty():
			break
		actors[String(act.get("actor", "?"))] = true
		var res := world.apply_action(act, gs)
		if not res.get("ok", false):
			all_ok = false
		log.record(act, res)
		steps += 1
	_assert(steps > 0 and steps < ColdOpen.MAX_STEPS, "the scene runs and terminates (%d steps)" % steps)
	_assert(all_ok, "every action the neighbour derives actually resolves")
	_assert(actors.has("neighbour"), "her work is recorded as actor 'neighbour'")
	_assert(actors.has("world"), "and the days that pass are world sleeps")
	_assert(ColdOpen.next_action(world, gs).is_empty(), "and then she has nothing left to do")
	_assert(ColdOpen.is_done(world), "the gate is open")
	_assert(String(world.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_OPEN, "really open")

	# Q-45: time visibly passes, so the player watches a seed become food.
	_assert(gs.day == 1 + ColdOpen.COLD_OPEN_DAYS,
		"the world is %d days older" % ColdOpen.COLD_OPEN_DAYS)
	_assert(gs.takeover_day == gs.day, "and her own day 1 is anchored at the handover")

	# Her work is not charged to the player. She spends her own energy, not hers.
	_assert(gs.energy == energy_before,
		"the neighbour's labour costs the player nothing (and the sleeps refill anyway)")
	_assert(gs.pouch.get("wheat", 0) == 5, "and she plants her own seed, not the player's")
	# She is a registered actor while her scene is live (M2.5 WI-2) with a meter of
	# her own; opening the gate is her leaving, so it takes her out of the world
	# as well as off the farm. Her meter is exercised in test_actor_registry and
	# test_actor_energy, which do not have to run her all the way out of the game
	# to look at it.
	_assert(not world.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and when the gate is open she is gone from the registry too")

	# The clock dispatcher records the state after every brain decision. An Action
	# may remove its own actor inside the gateway; the neighbour's final open_gate
	# is the smallest real example. Her decision must still be returned with an
	# empty post-state instead of asking the registry for an actor that has left.
	var dispatched_world := SimWorld.new()
	var dispatched_gs = load("res://systems/game_state.gd").new()
	SimRng.reseed(2026)
	dispatched_world.generate()
	for _i in ColdOpen.MAX_STEPS:
		var next := ColdOpen.next_action(dispatched_world, dispatched_gs)
		if String(next.get("verb", "")) == "open_gate":
			break
		dispatched_world.apply_action(next, dispatched_gs)
	dispatched_world.clock.schedule(dispatched_world.clock.tick + 1, {
		"kind": SimWorld.BRAIN_EVENT,
		"actor": SimWorld.ACTOR_NEIGHBOUR,
	})
	var dispatched := dispatched_world.advance_ticks(1, dispatched_gs)
	var departure: Dictionary = {}
	for decision in dispatched:
		if String(decision.get("actor", "")) == SimWorld.ACTOR_NEIGHBOUR:
			departure = decision
	_assert(String(departure.get("action", {}).get("verb", "")) == "open_gate"
		and departure.get("result", {}).get("ok", false)
		and departure.get("state", { "unexpected": true }).is_empty(),
		"a despawning brain Action is recorded with an empty post-state")
	_assert(not dispatched_world.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and the dispatched neighbour really left through the action gateway")
	dispatched_gs.free()

	# The whole opening replays. This is the property that makes it free: no new
	# machinery to keep in sync with the sim, and the single gateway is honoured
	# rather than carved around.
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	log.apply_to(w2, gs2)
	_assert(SaveGame.capture_canonical(world, gs) == SaveGame.capture_canonical(w2, gs2),
		"replaying the cold open reproduces the same world exactly")

	# Continue never replays it: the scene is derived, so an already-open gate is
	# all the memory it needs.
	_assert(ColdOpen.next_action(w2, gs2).is_empty(),
		"a restored world with an open gate has no cold open left in it")

	# It must terminate for every world it can be handed. A stuck neighbour must
	# never block the game, so run() is bounded and opens the gate regardless.
	var stuck := 0
	for seed_value in range(1, 101):
		var w := SimWorld.new()
		SimRng.reseed(seed_value)
		w.generate()
		var g = load("res://systems/game_state.gd").new()
		var res := ColdOpen.run(w, w, g)
		if not (res.get("ok", false) and ColdOpen.is_done(w)):
			stuck += 1
		g.free()
	_assert(stuck == 0, "the scene finishes cleanly on 100 consecutive seeds")

	# And when it cannot finish, it still hands over the farm.
	var broken := SimWorld.new()
	SimRng.reseed(5)
	broken.generate()
	var gs_broken = load("res://systems/game_state.gd").new()
	broken.layout = {
		"parcels": [{ "id": "neighbour", "rects": [Rect2i(12, 1, 9, 6)], "obstacle": "",
			"gate": WorldLayout.gate_of("neighbour"), "opened_by": WorldLayout.OPENED_BY_COLD_OPEN }],
		"neighbour_plot": { "cleared_for_demo": Vector2i(-1, -1), "crop": "wheat" },
	}
	var res_broken := ColdOpen.run(broken, broken, gs_broken)
	_assert(ColdOpen.is_done(broken),
		"even a scene with nothing to perform ends with the gate open")
	_assert(res_broken.get("steps", -1) >= 0, "and reports what it managed")
	gs_broken.free()

	gs.free()
	gs2.free()


func test_takeover_anchoring() -> void:
	print("\n--- Play-days, not calendar days (T-13 x T-2/T-20) Tests ---")

	# The cold open spends real days before the player owns anything, so every
	# day-keyed rule has to count from the handover. Anchoring on the raw day
	# counter would let a crow arrive on her first morning — which would break
	# T-2's "no threat before she is ready" outright, on day one, invisibly.
	# This is the T-2/T-20 safety property, so a red here is stop-and-think.
	var gs = load("res://systems/game_state.gd").new()
	gs.takeover_day = 3
	gs.day = 3
	_assert(gs.play_day() == 1, "the day the gate opens is her play-day 1")
	gs.day = 4
	_assert(gs.play_day() == 2, "and the next morning is play-day 2")

	# Exhaustive, in the style of the crow-readiness test it protects.
	for takeover in range(1, 8):
		for offset in range(0, 6):
			var play := offset + 1
			var absolute := takeover + offset
			gs.takeover_day = takeover
			gs.day = absolute
			_assert_quiet(gs.play_day() == play,
				"takeover %d, day %d is play-day %d" % [takeover, absolute, play])
			var sched := SimWorld.roll_crow_schedule(gs.play_day())
			if play < SimWorld.CROW_MIN_DAY:
				_assert_quiet(sched.is_empty(),
					"no crow is scheduled on play-day %d (absolute day %d)" % [play, absolute])
			_assert_quiet(
				SimWorld.may_spawn_crow(gs.play_day(), 99, 99) == (play >= SimWorld.CROW_MIN_DAY),
				"readiness follows the play-day, not the calendar")
	_flush_quiet("crow scheduling and readiness follow play-days for every takeover day 1..7")

	# The anchor is set by the sim, inside the gateway, so a replay earns it.
	var world := SimWorld.new()
	SimRng.reseed(31)
	world.generate()
	var gs2 = load("res://systems/game_state.gd").new()
	gs2.day = 3
	var stale_schedule: Array[int] = [4, 9]
	gs2.crow_schedule = stale_schedule
	gs2.actions_today = 12
	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs2)
	_assert(gs2.takeover_day == 3, "opening the cold open's gate sets the anchor")
	_assert(gs2.crow_schedule.is_empty(),
		"and discards the schedule the cold open's own days rolled — play-day 1 has no crows in it")
	_assert(gs2.actions_today == 0, "and starts her action clock at zero")

	# A tool gate is not a handover and must not move the anchor.
	var gs3 = load("res://systems/game_state.gd").new()
	gs3.day = 9
	var w3 := SimWorld.new()
	SimRng.reseed(31)
	w3.generate()
	w3.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("wood"), "actor": "world" }, gs3)
	_assert(gs3.takeover_day == 1, "opening the axe's gate leaves the anchor alone")

	gs.free()
	gs2.free()
	gs3.free()


func test_acorns() -> void:
	print("\n--- Acorns, and crows that prefer them (T-15, Q-39/Q-44) Tests ---")

	# T-2's harmless-first-crow is a *scripted* mercy: a boolean the player can
	# never perceive, experienced as a crow that inexplicably left. Acorns replace
	# the script with behaviour — the crow is not nerfed, it simply prefers
	# acorns, and she can watch it happen. It is also the game's first decoy,
	# which is lure-and-aggro management several phases before design/05.
	var world := SimWorld.new()
	SimRng.reseed(808)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()

	var stock := world.count_acorns()
	_assert(stock > 0, "a fresh farm has an acorn stock (%d)" % stock)
	_assert(stock == int(world.layout["acorns"]["count"]),
		"and it is exactly the [Playtest] number the layout asks for")
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if world.objects[ty][tx] == "acorn":
				_assert_quiet(world.is_walkable(tx, ty),
					"acorn at (%d,%d) is walkable" % [tx, ty])
	_flush_quiet("acorns are walkable like eggs, so they can never trap anyone")

	# Plant a row of crops in the yard, so both kinds of target exist at once.
	# (The neighbour's plot already holds crops of its own, so count from there.)
	var crops_before: int = world.count_planted()
	for i in 5:
		world.set_tile_state(3 + i, 3, "seeded", "wheat")
	_assert(world.count_planted() == crops_before + 5, "and five more crops to compete with them")

	# **Any acorn beats any crop.** Asserted across many draws, because the choice
	# is what a four-year-old will be watching.
	var crop_picked := 0
	for i in 200:
		var pick := world.choose_crow_target(i)
		if String(pick.get("kind", "")) != "acorn":
			crop_picked += 1
	_assert(crop_picked == 0, "with an acorn about, no crow ever goes for a crop")

	# eat_acorn takes exactly one, and only from a tile that has one.
	var first := world.choose_crow_target(0)
	var at: Vector2i = first.get("tile", Vector2i(-1, -1))
	_assert(world.apply_action({ "verb": "eat_acorn", "target": at, "actor": "crow" }).get("ok", false),
		"a crow eats the acorn it flew to")
	_assert(world.count_acorns() == stock - 1, "and the stock drops by exactly one")
	_assert(not world.apply_action({ "verb": "eat_acorn", "target": at, "actor": "crow" }).get("ok", true),
		"and there is nothing left on that tile to eat twice")
	_assert(world.count_planted() == crops_before + 5, "no crop was touched")

	# Depletion is the difficulty ramp: the threat arrives on a schedule the
	# *world* sets, experienced as food running out. Finite, no regeneration.
	var eaten := 1
	while world.count_acorns() > 0 and eaten < 100:
		var p := world.choose_crow_target(eaten)
		world.apply_action({ "verb": "eat_acorn", "target": p.get("tile"), "actor": "crow" })
		eaten += 1
	_assert(world.count_acorns() == 0, "the stock can be emptied")
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(world.count_acorns() == 0, "and sleeping does not refill it — no regeneration in phase 1")

	# Only then do crows turn to crops, which is the moment the peace ends.
	var after := world.choose_crow_target(3)
	_assert(String(after.get("kind", "")) == "crop", "with the acorns gone, the crow wants a crop")
	_assert(world.apply_action({ "verb": "eat_crop", "target": after.get("tile"), "actor": "crow" }).get("ok", false),
		"and takes one")
	_assert(world.count_planted() == crops_before + 4, "exactly one")

	# An empty farm is not a crash.
	var bare := SimWorld.new()
	SimRng.reseed(3)
	bare.generate()
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if bare.objects[ty][tx] == "acorn":
				bare.objects[ty][tx] = ""
			var bst := String(bare.tiles[ty][tx].get("state", ""))
			if bst == "seeded" or bst == "growing" or bst == "ready":
				bare.set_tile_state(tx, ty, "cleared")
	_assert(String(bare.choose_crow_target(0).get("kind", "")) == "none",
		"nothing to eat is answered as 'none', not as a crash")

	# T-15's retarget of T-2's mercy flag: it belongs on the first crow to go for
	# a **crop**, which is the transition, not on one of the several earlier birds
	# that were already harmless because they went for an acorn.
	_assert(gs.crop_crows_seen == 0, "the crop-crow counter starts at zero")
	var harmless_first: bool = ("crop" == "crop" and gs.crop_crows_seen == 0)
	_assert(harmless_first, "so the first crop-targeting crow is the harmless one")
	gs.crop_crows_seen += 1
	_assert(not ("crop" == "crop" and gs.crop_crows_seen == 0),
		"and the second one is not")
	_assert(not ("acorn" == "crop" and 0 == 0), "an acorn-targeting crow never spends the mercy")

	# The daily-loss identity still holds with acorns in the equation: a day
	# cannot cost more crops than there were scheduled arrivals.
	_assert(SimWorld.CROWS_PER_DAY >= 1, "there is a per-day crow budget at all")
	var sched := SimWorld.roll_crow_schedule(SimWorld.CROW_MIN_DAY)
	_assert(sched.size() == SimWorld.CROWS_PER_DAY,
		"and a day schedules exactly that many arrivals, so daily loss is bounded by it")

	gs.free()


func test_acorn_pickup() -> void:
	# T-30, Q-48's ruling (2026-09-01). The proof and the acorns both stay exactly
	# as they are — *"acorns run out by design"* — and what changes is that the
	# player may run them out herself: an acorn she picks up is an acorn no crow
	# will eat, so her own hands can bring the turn to crops (and with it Q-12's
	# three scares) forward. Everything asserted here is about that one sentence.
	print("\n--- T-30 (Q-48): acorns are pickable ---")

	# 1. Intent, and the ordering question the acorn raises: they are dropped on
	#    *cleared* ground, which is also the one state that answers "till". The
	#    object wins — the egg's rule, and the reason `resolve()` reads the object
	#    table before it reads the tile at all.
	var FarmScript = load("res://world/farm.gd")
	var t = FarmScript.new()
	t.tiles.clear()
	t.objects.clear()
	for ty in t.MAP_HEIGHT:
		t.tiles.append([])
		t.objects.append([])
		for tx in t.MAP_WIDTH:
			t.objects[ty].append("")
			t.tiles[ty].append({ "state": "cleared", "crop_type": "", "growth_stage": 0, "watered_today": false })

	GameState.reset()
	GameState.selected_tool = 3           # hoe in hand, as she usually has
	var acorn_t := Vector2i(4, 4)
	_assert(ActionRouter.resolve(t, GameState, acorn_t).get("action", "") == "till",
		"bare cleared ground still answers 'till'")
	t.objects[acorn_t.y][acorn_t.x] = "acorn"
	var pick = ActionRouter.resolve(t, GameState, acorn_t)
	_assert(pick.get("action", "") == "collect",
		"an acorn on that same ground answers 'collect' — the object wins over the soil")
	_assert(pick.get("target_t", Vector2i.ZERO) == acorn_t,
		"and the acorn's own tile is what she is sent to")
	t.tiles[acorn_t.y][acorn_t.x]["state"] = "tilled"
	_assert(ActionRouter.resolve(t, GameState, acorn_t).get("action", "") == "collect",
		"the same rule on tilled soil: she picks the acorn up, she does not plant through it")
	_assert(ActionRouter.is_workable(t, acorn_t),
		"so she walks *up to* an acorn rather than onto it, exactly as she does an egg")
	t.free()

	# 2. The gateway. One verb, no new one: `collect`, actor "player", the egg's
	#    handler extended.
	GameState.reset()
	SimRng.reseed(4242)
	var world := SimWorld.new()
	world.generate()
	var stock := world.count_acorns()
	_assert(stock > 0, "the farm starts with its finite acorn stock (%d)" % stock)
	_assert(GameState.acorns == 0, "and she starts with none in her pocket")

	var first: Vector2i = world.choose_crow_target(0).get("tile", Vector2i(-1, -1))
	var planted_before: int = world.count_planted()
	var day_actions: int = GameState.actions_today
	var got := world.apply_action(
		{ "verb": "collect", "target": first, "actor": "player" }, GameState)
	_assert(got.get("ok", false) and String(got.get("collected", "")) == "acorn",
		"she picks up an acorn with the same verb that picks up an egg")
	_assert(GameState.acorns == 1, "it is in her pocket, counted (1)")
	_assert(world.count_acorns() == stock - 1, "and out of the stock (%d)" % world.count_acorns())
	_assert(world.get_object(first.x, first.y) == "", "the tile is bare")
	_assert(GameState.energy == GameState.max_energy,
		"picking it up cost no energy, like the egg")
	_assert(GameState.actions_today == day_actions + 1,
		"but it did advance the day's action clock, like the egg (bending down is work)")
	_assert(not world.apply_action(
		{ "verb": "collect", "target": first, "actor": "player" }, GameState).get("ok", true),
		"and there is nothing on that tile to pick up twice")
	_assert(world.count_planted() == planted_before, "no crop was touched")

	# 3. The stock is the crow's larder, so a pocketed acorn is gone from it.
	var never_picked := true
	for i in 200:
		if world.choose_crow_target(i).get("tile", Vector2i(-1, -1)) == first:
			never_picked = false
	_assert(never_picked, "no crow ever flies to the acorn she took (200 draws)")

	# 4. Q-48's acceleration, end to end: empty the stock by hand, and the crows
	#    turn to crops — which is exactly what her hands were for.
	var guard := 0
	while world.count_acorns() > 0 and guard < 100:
		var next: Vector2i = world.choose_crow_target(guard).get("tile", Vector2i(-1, -1))
		world.apply_action({ "verb": "collect", "target": next, "actor": "player" }, GameState)
		guard += 1
	_assert(world.count_acorns() == 0, "she can clear the whole stock herself")
	_assert(GameState.acorns == stock, "with every one of them in her pocket (%d)" % GameState.acorns)
	_assert(String(world.choose_crow_target(3).get("kind", "")) == "crop",
		"and the next crow wants a crop — the turn she just brought forward")

	# 5. T-15's ramp is untouched: nothing she did refills anything, and sleeping
	#    does not either. (`test_acorns` owns the invariant; this is the version of
	#    it that has been through her hands.)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(world.count_acorns() == 0, "a night does not put the acorns back (no regeneration)")
	_assert(GameState.acorns == stock, "and she still has the ones she picked up")

	# 6. Recorded, replayed, saved. A pickup is an ordinary Action, so it must
	#    survive both round trips like every other one.
	GameState.reset()
	SimRng.reseed(606)
	var rlog := ReplayLog.new()
	rlog.start(606)
	var live := SimWorld.new()
	live.generate()
	var take: Array[Vector2i] = []
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if live.objects[ty][tx] == "acorn":
				take.append(Vector2i(tx, ty))
	_assert(take.size() >= 2, "the recorded session has acorns to pick up (%d)" % take.size())
	_replay_do(live, rlog, { "verb": "collect", "target": take[0], "actor": "player" })
	_replay_do(live, rlog, { "verb": "sleep", "actor": "world", "weather": "sunny" })
	_replay_do(live, rlog, { "verb": "collect", "target": take[1], "actor": "player" })
	var picked_up: int = GameState.acorns
	_assert(picked_up == 2, "the session picked up two acorns")
	var live_snap := _replay_snapshot(live)

	var replayed := SimWorld.new()
	ReplayLog.from_json(rlog.to_json()).apply_to(replayed, GameState)
	_assert(_replay_snapshot(replayed) == live_snap,
		"the replay reproduces the farm exactly, acorns and all")
	_assert(GameState.acorns == picked_up,
		"including her pocket — the count is in the canonical state, so a replay that lost it fails")

	var on_disk = JSON.parse_string(JSON.stringify(SaveGame.capture(replayed, GameState)))
	var loaded := SimWorld.new()
	GameState.reset()
	_assert(SaveGame.restore(on_disk, loaded, GameState), "the session saves and loads")
	_assert(GameState.acorns == picked_up, "with her acorns still counted (%d)" % GameState.acorns)
	_assert(loaded.count_acorns() == live.count_acorns(),
		"and the stock still short by the ones she took")

	# A save written before T-30 says nothing about acorns, and must load as "none".
	var old_save: Dictionary = on_disk.duplicate(true)
	old_save["state"].erase("acorns")
	GameState.reset()
	_assert(SaveGame.restore(old_save, SimWorld.new(), GameState),
		"a save from before T-30 still loads")
	_assert(GameState.acorns == 0, "and reads as an empty pocket")

	GameState.reset()


# --- helpers for the noisier loops above --------------------------------------
# A loop over 640 tiles should not print 640 lines. These collapse a run of
# assertions into one, reporting the first failure if there was one.
func test_actor_energy() -> void:
	print("\n--- Every actor has its own energy meter (designer, 2026-08-29) Tests ---")

	# The player's energy is also the clock — spending it is what advances the
	# time of day (Q-38) — but that is a property of *her* meter, not a reason for
	# everybody else to work for free. The first fix for the cold open charging the
	# player made non-player actors free, which was wrong in the same way for the
	# opposite reason. An NPC just gets tired, in its own pocket.
	var world := SimWorld.new()
	SimRng.reseed(606)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()

	var t := Vector2i(5, 3)  # inside the yard, cleared ground
	world.set_tile_state(t.x, t.y, "cleared")

	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY,
		"an actor who has never worked reads as rested")
	_assert(world.energy_of("player") == -1,
		"the player has no meter here — hers is GameState's, because hers is the clock")
	_assert(not world.is_exhausted("neighbour"), "and is not exhausted")

	# An NPC's action spends the NPC's energy and none of the player's.
	var player_energy_before: int = gs.energy
	var r := world.apply_action({ "verb": "till", "target": t, "actor": "neighbour" }, gs)
	_assert(r.get("ok", false), "the neighbour can till")
	_assert(gs.energy == player_energy_before, "and it costs the player nothing")
	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"but it costs her exactly what the verb costs")

	# Two actors are two meters; neither reaches into the other.
	world.set_tile_state(t.x, t.y, "cleared")
	world.apply_action({ "verb": "till", "target": t, "actor": "somebody_else" }, gs)
	_assert(world.energy_of("somebody_else") == SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"a second actor gets a second meter")
	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"and spending from it leaves the first alone")

	# The player's own action still charges the player, and still moves the clock.
	world.set_tile_state(t.x, t.y, "cleared")
	world.apply_action({ "verb": "till", "target": t, "actor": "player" }, gs)
	_assert(gs.energy == player_energy_before - Tools.get_energy_cost("till"),
		"the player still pays for her own work")
	_assert(world.energy_of("player") == -1, "and gains no world-side meter by doing it")

	# An unnamed actor is the player: plenty of call sites omit it, and the player
	# is the only actor anything ever forgot to name.
	var before_unnamed: int = gs.energy
	world.set_tile_state(t.x, t.y, "cleared")
	world.apply_action({ "verb": "till", "target": t }, gs)
	_assert(gs.energy == before_unnamed - Tools.get_energy_cost("till"),
		"an action with no actor named is charged to the player")

	# Soft floor, exactly as Q-11 gives the player: an exhausted NPC clamps at 0
	# and its action still resolves. Nothing in phase 1 is a wall, for anyone.
	world.set_actor_energy("neighbour", 0)
	_assert(world.is_exhausted("neighbour"), "an NPC can be exhausted")
	world.set_tile_state(t.x, t.y, "cleared")
	_assert(world.apply_action({ "verb": "till", "target": t, "actor": "neighbour" }, gs).get("ok", false),
		"and still works — the soft floor is not the player's alone")
	_assert(world.energy_of("neighbour") == 0, "clamped at zero rather than going negative")

	# Everyone wakes rested when the day turns.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	_assert(world.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY,
		"a day turning refills every actor's meter")
	_assert(world.energy_of("somebody_else") == SimWorld.ACTOR_MAX_ENERGY, "all of them")
	_assert(gs.energy == gs.max_energy, "the player's included, as before")

	# It is sim truth: saved, restored, and reproduced by a replay.
	world.set_actor_energy("neighbour", 7)
	var round_trip = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(round_trip, w2, gs2), "a save with actor energy in it restores")
	_assert(w2.energy_of("neighbour") == 7, "and an NPC's tiredness survives a reload")

	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": {} }
	var w3 := SimWorld.new()
	var gs3 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, w3, gs3), "a save written before meters existed still restores")
	_assert(w3.energy_of("neighbour") == SimWorld.ACTOR_MAX_ENERGY,
		"with nobody on record, which reads as everybody rested")

	var log := ReplayLog.new()
	log.start(606)
	var w4 := SimWorld.new()
	var gs4 = load("res://systems/game_state.gd").new()
	SimRng.reseed(606)
	w4.generate()
	# Out in the meadow: the replay regenerates the world and re-applies the tills
	# alone, so the row has to be on ground a till still lands on afterwards, and
	# since T-32 the fenced yard is not that ground.
	for i in 3:
		var tile := Vector2i(5 + i, 9)
		w4.set_tile_state(tile.x, tile.y, "cleared")
		var a := { "verb": "till", "target": tile, "actor": "neighbour" }
		log.record(a, w4.apply_action(a, gs4))
	var w5 := SimWorld.new()
	var gs5 = load("res://systems/game_state.gd").new()
	log.apply_to(w5, gs5)
	_assert(w5.energy_of("neighbour") == w4.energy_of("neighbour"),
		"and a replay reproduces it exactly")
	_assert(SaveGame.capture_canonical(w4, gs4) == SaveGame.capture_canonical(w5, gs5),
		"so the canonical capture still matches after a replay")

	gs.free()
	gs2.free()
	gs3.free()
	gs4.free()
	gs5.free()


# The registry as a value, with its arrangement thrown away — see the comment at
# the call site.
func test_actor_registry() -> void:
	print("\n--- The actor registry and the species table (D-9/Q-53, M2.5 WI-2) Tests ---")

	# --- the table (plan §3.4; checklist §8.B) --------------------------------
	# Every row answers all four questions. `movement` has no default anywhere in
	# SpeciesDefs precisely so that this can fail rather than shrug: WI-8 adds a
	# critter row per worker, and a row that forgot how it moves must not walk.
	for id in SpeciesDefs.ids():
		var row: Dictionary = SpeciesDefs.row(id)
		var move: Dictionary = SpeciesDefs.movement_of(id)
		_assert_quiet(not move.is_empty(), "%s carries a movement capability" % id)
		_assert_quiet(SpeciesDefs.mode_of(id) in SpeciesDefs.MODES,
			"%s moves in one of the four modes" % id)
		_assert_quiet(int(move.get("body_len", 0)) >= 1, "%s occupies at least one tile" % id)
		_assert_quiet(typeof(move.get("tile_exclusive")) == TYPE_BOOL,
			"%s says whether it shares a tile" % id)
		# Every *mover* has a speed. A machine has none, and says so with its mode
		# rather than with a zero that could be mistaken for an oversight (M2.5
		# WI-10): `STATIC` is the one row shape where "no speed" is the answer.
		_assert_quiet(SpeciesDefs.speed_of(id) > 0.0 or SpeciesDefs.mode_of(id) == SpeciesDefs.STATIC,
			"%s has a speed, or is stationary and says so" % id)
		_assert_quiet(SpeciesDefs.brain_of(id) != "", "%s names a brain (WI-3 binds it)" % id)
		_assert_quiet(SpeciesDefs.verbs_of(id) is Array, "%s lists its verbs" % id)
		_assert_quiet(String(row.get("name", "")) != "", "%s has a display name" % id)
	_flush_quiet("every species row answers all of the questions a row exists to answer")

	# Finding F-6, now one field instead of an accident of each node's code: the
	# crow has always flown over what a walker paths around.
	_assert(SpeciesDefs.mode_of(SpeciesDefs.CROW) == SpeciesDefs.FLY,
		"the crow's obstacle-ignoring flight is a data row (F-6)")
	_assert(SpeciesDefs.mode_of(SpeciesDefs.CHICKEN) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.NEIGHBOUR) == SpeciesDefs.GROUND
			and SpeciesDefs.mode_of(SpeciesDefs.PLAYER) == SpeciesDefs.GROUND,
		"and everybody else walks")

	# Speeds are tiles per tick, converted from the px/s each presentation node
	# moves at today. Asserted against the conversion rather than against a
	# literal, so raising SimClock.RATE cannot quietly leave the table saying
	# something it no longer means.
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.PLAYER), SimClock.tiles_per_tick(48.0)),
		"the player's 48 px/s is 0.3 tiles/tick")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.NEIGHBOUR), SimClock.tiles_per_tick(26.0)),
		"the neighbour's 26 px/s converts")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.CHICKEN), SimClock.tiles_per_tick(20.0)),
		"the chicken's 20 px/s converts")
	_assert(is_equal_approx(SpeciesDefs.speed_of(SpeciesDefs.CROW), SimClock.tiles_per_tick(60.0)),
		"the crow's 60 px/s flight converts")
	_assert(is_equal_approx(SimClock.tiles_per_tick(160.0), 1.0),
		"a tile per tick is 160 px/s at 16 px tiles and 10 Hz")

	# The player's spook radius is the one sense that exists today, and it exists
	# in pixels on a node (`player/player.gd`). In tiles here, because a sim that
	# reasons in pixels is a sim that has lost the plot.
	_assert(is_equal_approx(float(SpeciesDefs.senses_of(SpeciesDefs.PLAYER).get("spook_radius", 0.0)), 3.0),
		"the player startles things within 3 tiles (48 px, as the crow reads it today)")
	_assert(SpeciesDefs.senses_of(SpeciesDefs.CROW).get("flees_spook_radius", false),
		"and the crow is what notices — F-7b's scan, written down as a sense")

	# Ground rule 1: nobody gets a verb the player lacks, except the handful of
	# entity verbs the table documents one by one with their reasons.
	for id in SpeciesDefs.ids():
		for v in SpeciesDefs.verbs_of(id):
			_assert_quiet(v in SpeciesDefs.PLAYER_VERBS or v in SpeciesDefs.ENTITY_VERBS,
				"%s's verb %s is accounted for" % [id, v])
	_flush_quiet("no species has a verb outside the player's set and the documented entity verbs")

	# And every verb named in the table is one the gateway actually knows — a
	# typo in a row would otherwise be a brain that silently never acts. Driven
	# with no GameState and an off-map target, so nothing here mutates anything:
	# the only answer being ruled out is "unknown_verb".
	var vocab := SimWorld.new()
	for id in SpeciesDefs.ids():
		for v in SpeciesDefs.verbs_of(id):
			var r: Dictionary = vocab.apply_action({ "verb": v, "target": Vector2i(-1, -1) }, null)
			_assert_quiet(String(r.get("reason", "")) != "unknown_verb",
				"%s's verb %s is a verb the gateway knows" % [id, v])
	_flush_quiet("every verb in the table is a verb apply_action() implements")

	# --- the cast a generated world contains ----------------------------------
	GameState.reset()
	SimRng.reseed(2026)
	var world := SimWorld.new()
	world.generate()

	_assert(world.has_actor(SimWorld.ACTOR_PLAYER), "a generated world contains the player")
	_assert(world.actor_pos(SimWorld.ACTOR_PLAYER) == WorldLayout.spawn(world.layout),
		"at the layout's spawn point (nothing moves her yet — WI-4/WI-6)")
	_assert(world.has_actor(SimWorld.ACTOR_CHICKEN), "and the chicken")
	_assert(world.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and the neighbour, because her cold open has not run")
	var hen: Vector2i = world.actor_pos(SimWorld.ACTOR_CHICKEN)
	_assert(world.is_walkable(hen.x, hen.y), "the hen is standing somewhere she could stand")
	_assert(world.species_of(SimWorld.ACTOR_CHICKEN) == SpeciesDefs.CHICKEN,
		"and she is a chicken, which is a species the table knows")
	for id in world.actors:
		_assert_quiet(SpeciesDefs.has(world.species_of(id)),
			"%s's species is in the table" % id)
		_assert_quiet(not SpeciesDefs.movement_of(world.species_of(id)).is_empty(),
			"%s can move somehow" % id)
	_flush_quiet("every actor a generated world registers has a species, and that species can move")
	_assert(not world.has_actor("crow"),
		"the crow is not in registry v1 — a visit is not a resident (WI-3 owns its lifecycle)")

	# Where she stands is a function of the seed, which is the point: the tile
	# used to be drawn in main.gd after generation, so it was a function of
	# whatever the stream happened to be holding when a renderer got there.
	SimRng.reseed(2026)
	var twin := SimWorld.new()
	twin.generate()
	_assert(twin.actor_pos(SimWorld.ACTOR_CHICKEN) == hen,
		"the same seed puts the hen on the same tile")
	var moved := false
	for s in [7, 99, 1234, 55555]:
		SimRng.reseed(s)
		var other := SimWorld.new()
		other.generate()
		if other.actor_pos(SimWorld.ACTOR_CHICKEN) != hen:
			moved = true
	_assert(moved, "and a different seed puts her somewhere else")

	# --- she survives a save and a load (the WI's named criterion, F-7c) -------
	var gs = load("res://systems/game_state.gd").new()
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
	var reloaded := SimWorld.new()
	var gs_reloaded = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snapshot, reloaded, gs_reloaded), "a save with a registry in it restores")
	_assert(reloaded.actor_pos(SimWorld.ACTOR_CHICKEN) == hen,
		"and the chicken is where she was, not where a fresh die roll put her (F-7c)")
	_assert(reloaded.actor_pos(SimWorld.ACTOR_PLAYER) == world.actor_pos(SimWorld.ACTOR_PLAYER)
			and reloaded.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and so is everybody else who was in the world")
	# Entry for entry, not arrangement for arrangement: a saved registry comes
	# back in the order JSON.stringify sorted its keys into rather than in spawn
	# order, and nothing is allowed to care (see SimWorld's registry block).
	_assert(_actors_signature(reloaded) == _actors_signature(world),
		"the whole registry round-trips value-for-value")

	# --- and a replay reproduces it exactly -----------------------------------
	# Same seed, same action stream, same registry — including the neighbour's
	# departure, which is a sim fact applied in the gateway rather than a node
	# calling queue_free().
	var log := ReplayLog.new()
	log.start(4242)
	SimRng.reseed(4242)
	var live := SimWorld.new()
	var gs_live = load("res://systems/game_state.gd").new()
	live.generate()
	var gate := ColdOpen.gate(live)
	var stream: Array[Dictionary] = [
		{ "verb": "till", "target": Vector2i(14, 4), "actor": "neighbour" },
		{ "verb": "water", "target": Vector2i(13, 4), "actor": "neighbour" },
		{ "verb": "open_gate", "target": gate, "actor": "neighbour" },
	]
	for a in stream:
		log.record(a, live.apply_action(a, gs_live))
	_assert(not live.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"opening the cold open's gate takes the neighbour out of the world")
	var replayed := SimWorld.new()
	var gs_replayed = load("res://systems/game_state.gd").new()
	log.apply_to(replayed, gs_replayed)
	_assert(str(replayed.actors) == str(live.actors),
		"same seed + same actions = the same registry, entry for entry")
	_assert(SaveGame.capture_canonical(live, gs_live) == SaveGame.capture_canonical(replayed, gs_replayed),
		"so the canonical capture still matches after a replay")

	# --- the meter lives in the entry now -------------------------------------
	SimRng.reseed(606)
	var metered := SimWorld.new()
	metered.generate()
	var gs_m = load("res://systems/game_state.gd").new()
	metered.set_tile_state(5, 3, "cleared")
	metered.apply_action({ "verb": "till", "target": Vector2i(5, 3), "actor": "neighbour" }, gs_m)
	_assert(int(metered.actor(SimWorld.ACTOR_NEIGHBOUR).get("energy", -99))
			== SimWorld.ACTOR_MAX_ENERGY - Tools.get_energy_cost("till"),
		"spending an NPC's energy writes it into her registry entry")
	_assert(metered.energy_of(SimWorld.ACTOR_NEIGHBOUR)
			== int(metered.actor(SimWorld.ACTOR_NEIGHBOUR).get("energy", -99)),
		"and energy_of() reads the same field, not a second copy of the truth")
	_assert(int(metered.actor(SimWorld.ACTOR_PLAYER).get("energy", 0)) == -1,
		"the player's entry carries no meter — hers is GameState's, because hers is the clock")
	metered.advance_day("sunny")
	_assert(metered.energy_of(SimWorld.ACTOR_NEIGHBOUR) == SimWorld.ACTOR_MAX_ENERGY,
		"a day turning refills every registered actor")
	_assert(int(metered.actor(SimWorld.ACTOR_PLAYER).get("energy", 0)) == -1,
		"and leaves the player's alone")

	# --- spawn and despawn are sim functions ----------------------------------
	metered.spawn_actor("chicken_2", SpeciesDefs.CHICKEN, Vector2i(6, 6))
	_assert(metered.actors_of_species(SpeciesDefs.CHICKEN).size() == 2,
		"a second hen is a second entry, not a special case")
	metered.set_actor_pos("chicken_2", Vector2i(7, 6), "left")
	_assert(metered.actor_pos("chicken_2") == Vector2i(7, 6)
			and String(metered.actor("chicken_2").get("facing", "")) == "left",
		"moving one is a sim call (WI-4 is what will make it happen on its own)")
	_assert(metered.despawn_actor("chicken_2") and not metered.has_actor("chicken_2"),
		"and despawning removes her")
	_assert(not metered.despawn_actor("chicken_2"), "despawning twice is not a second departure")
	_assert(metered.actor_pos("nobody") == Vector2i(-1, -1) and metered.actor("nobody").is_empty(),
		"an actor nobody spawned has no entry and no position")

	# --- a pre-M2.5 save default-spawns exactly as the old build would ---------
	var legacy := { "version": SaveGame.VERSION,
		"world": {
			"tiles": world.tiles.duplicate(true),
			"objects": world.objects.duplicate(true),
			# What such a save *did* carry: the meters, in a map of their own.
			"actor_energy": { "neighbour": 7 },
		},
		"state": {} }
	var old_world := SimWorld.new()
	var gs_old = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, old_world, gs_old), "a save written before the registry still restores")
	_assert(old_world.has_actor(SimWorld.ACTOR_PLAYER) and old_world.has_actor(SimWorld.ACTOR_CHICKEN),
		"and default-spawns the cast that build would have had")
	var old_hen: Vector2i = old_world.actor_pos(SimWorld.ACTOR_CHICKEN)
	_assert(old_world.is_walkable(old_hen.x, old_hen.y) and old_hen != old_world.actor_pos(SimWorld.ACTOR_PLAYER),
		"with the hen beside the player rather than under her")
	_assert(old_world.energy_of(SimWorld.ACTOR_NEIGHBOUR) == 7,
		"and its actor_energy map is folded into the entries (the compat shim)")

	# The common case for a legacy save is one written *after* the cold open, and
	# its actor_energy still has the neighbour in it. She is gone; a meter must
	# not be the thing that puts a departed actor back on the farm.
	SimRng.reseed(2026)
	var after := SimWorld.new()
	var gs_after = load("res://systems/game_state.gd").new()
	after.generate()
	after.apply_action({ "verb": "open_gate", "target": ColdOpen.gate(after), "actor": "neighbour" }, gs_after)
	var legacy_after := { "version": SaveGame.VERSION,
		"world": {
			"tiles": after.tiles.duplicate(true),
			"objects": after.objects.duplicate(true),
			"actor_energy": { "neighbour": 3, "chicken": 5 },
		},
		"state": {} }
	var old_after := SimWorld.new()
	var gs_old_after = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy_after, old_after, gs_old_after),
		"a legacy save from after the cold open restores too")
	_assert(not old_after.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"and does not resurrect the neighbour to give her meter back to")
	_assert(old_after.energy_of(SimWorld.ACTOR_CHICKEN) == 5,
		"while the hen, who is still here, keeps hers")

	# The real fixtures, not a synthetic old save: every genuinely pre-M2.5
	# autosave in playtests/ must come back with a farm that has a hen on it.
	var dir := DirAccess.open("res://playtests")
	if dir != null:
		var checked := 0
		for name in dir.get_directories():
			var path := "res://playtests/%s/autosave.json" % name
			var data := SaveGame.load_dict(path)
			if data.is_empty() or data.get("world", {}).has("actors"):
				continue
			checked += 1
			var fixture := SimWorld.new()
			var gs_fixture = load("res://systems/game_state.gd").new()
			_assert_quiet(SaveGame.restore(data, fixture, gs_fixture), "%s restores" % name)
			_assert_quiet(fixture.has_actor(SimWorld.ACTOR_PLAYER)
					and fixture.has_actor(SimWorld.ACTOR_CHICKEN),
				"%s comes back with a player and a hen" % name)
			var t: Vector2i = fixture.actor_pos(SimWorld.ACTOR_CHICKEN)
			_assert_quiet(fixture.is_walkable(t.x, t.y), "%s puts the hen somewhere walkable" % name)
			gs_fixture.free()
		_assert_quiet(checked > 0, "there were pre-M2.5 fixtures to check")
		_flush_quiet("every real pre-registry autosave in playtests/ default-spawns its cast")

	gs.free()
	gs_reloaded.free()
	gs_live.free()
	gs_replayed.free()
	gs_m.free()
	gs_old.free()
	gs_after.free()
	gs_old_after.free()


func test_economy_teaching() -> void:
	print("\n--- The economy, taught at first need (T-11, Q-35) Tests ---")

	# Sell, buy and refill were taught *nowhere* — the gap that produced the
	# silent empty-pouch refusal on 2026-08-27, where the player was never told
	# where seeds come from. Each beat now fires at the moment of need, and each
	# fires at most once **by construction**: the condition includes "you have
	# never done this", so doing it once retires the beat with no flag to store.
	var world := SimWorld.new()
	SimRng.reseed(1212)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	# Past the handover and past the vignette, or nothing is taught at all.
	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs)
	gs.day = gs.takeover_day + 5

	var bin := Vector2i(4, 1)
	var well := Vector2i(6, 1)
	var box := Vector2i(8, 1)
	_assert(world.get_object(bin.x, bin.y) == "shipping_bin", "the bin is where the layout puts it")

	# Nothing owed, nothing needed: silence. Five wheat is under the keep line's
	# reach — a pouch with nothing to sell (S-18/S-19/S-20).
	gs.watering_can_charges = gs.max_watering_can_charges
	gs.pouch = { "wheat": 0, "tomato": 0 }
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"a farmer with nothing to sell, water or buy is not nagged")

	# --- sell: the pouch fills up --------------------------------------------
	# The threshold is counted in what the bin would take, so the keep line rides
	# under it: she has to be that many crops *over* a row's worth before the
	# errand is real (S-18/S-19/S-20).
	gs.pouch["wheat"] = 0 + TeachingFocus.SELL_BEAT_CROPS - 1
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"one crop short of the threshold is still silence")
	gs.pouch["wheat"] = 0 + TeachingFocus.SELL_BEAT_CROPS
	_assert(_only(TeachingFocus.economy_beat(world, gs)) == bin,
		"a full enough basket points at the bin")
	# Selling once retires it for good, and the counter is what remembers.
	world.apply_action({ "verb": "sell", "actor": "player" }, gs)
	_assert(gs.bin_deposits > 0 and gs.total_shipped == 0,
		"a reserve-only bin deposit is recorded without counting a sale")
	gs.pouch["wheat"] = 99
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and the bin is never highlighted again, however full the basket gets")

	# --- refill: the can runs dry --------------------------------------------
	gs.watering_can_charges = 0
	_assert(_only(TeachingFocus.economy_beat(world, gs)) == well,
		"an empty can points at the well")
	world.apply_action({ "verb": "refill", "actor": "player" }, gs)
	_assert(gs.cans_refilled == 1, "refilling accrues its counter")
	gs.watering_can_charges = 0
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and the well is never highlighted again")

	# --- buy: the pouch empties ----------------------------------------------
	gs.pouch = { "wheat": 0, "tomato": 0 }
	gs.gold = 0
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"an empty pouch with no money points at NOTHING — never send her to a shop she cannot buy from")
	# The cheapest packet the shelf will actually sell *this* farm. Wheat is off
	# the shelf since S-18/S-19/S-20, so the price the beat waits for is no longer a
	# constant: on a farm that has never cut a wheat the tomato is locked and the
	# cheapest thing left is the scarecrow, and once she has cut one it is the
	# pea (P-19), cheaper than the tomato. Either way it is what she could walk up and buy.
	_assert(TeachingFocus.cheapest_seed({}) == int(CropDefs.TYPES["scarecrow"].seed_price),
		"an unearned shelf is priced at the only packet on it")
	gs.harvest_counts["wheat"] = 1
	_assert(TeachingFocus.cheapest_seed(gs.harvest_counts) == int(CropDefs.TYPES["pea"].seed_price),
		"and one harvest behind her, at the pea she has just unlocked (P-19: cheaper than the tomato)")
	gs.gold = TeachingFocus.cheapest_seed(gs.harvest_counts) - 1
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"a penny short of the cheapest packet is still silence")
	gs.gold = TeachingFocus.cheapest_seed(gs.harvest_counts)
	_assert(_only(TeachingFocus.economy_beat(world, gs)) == box,
		"an empty pouch and the price of a seed points at the seed box")
	world.apply_action({ "verb": "buy_seed", "seed_type": "pea", "actor": "player" }, gs)
	_assert(gs.seeds_bought == 1, "buying accrues its counter")
	gs.pouch = { "wheat": 0, "tomato": 0 }
	gs.gold = 500
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and the seed box is never highlighted again")

	# --- one glowing thing at a time -----------------------------------------
	# An errand must never interrupt a lesson, so these sit below the vignette
	# and below a newly opened parcel's introduction in the arbitration.
	var gs2 = load("res://systems/game_state.gd").new()
	var w2 := SimWorld.new()
	SimRng.reseed(1212)
	w2.generate()
	ColdOpen.run(w2, w2, gs2)
	gs2.pouch["wheat"] = 0 + TeachingFocus.SELL_BEAT_CROPS
	_assert(not TeachingFocus.economy_beat(w2, gs2).is_empty(),
		"the sell beat would fire on its own")
	var during_vignette: Array[Vector2i] = TeachingFocus.targets(w2, gs2, Vector2i(15, 4))
	_assert(during_vignette.size() == 1 and not during_vignette.has(bin),
		"but on play-day 1 the vignette owns the highlight and the errand waits")

	# --- the counters are sim truth ------------------------------------------
	var round_trip = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
	var gs3 = load("res://systems/game_state.gd").new()
	var w3 := SimWorld.new()
	SaveGame.restore(round_trip, w3, gs3)
	_assert(gs3.seeds_bought == gs.seeds_bought and gs3.cans_refilled == gs.cans_refilled,
		"the counters round-trip through a save")
	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": {} }
	var gs4 = load("res://systems/game_state.gd").new()
	var w4 := SimWorld.new()
	SaveGame.restore(legacy, w4, gs4)
	_assert(gs4.seeds_bought == 0 and gs4.cans_refilled == 0,
		"and a pre-T-11 save reads as 'never done it', so an old farm gets the beat once")

	gs.free()
	gs2.free()
	gs3.free()
	gs4.free()


# One target, or (-1,-1). Keeps the economy assertions readable without fighting
# GDScript's typed-array literals.
func test_offscreen_arrow() -> void:
	print("\n--- Off-screen target arrow (T-25, Q-36's one survivor) Tests ---")

	# Q-36 rejected the hint-escalation ladder outright and kept exactly one
	# thing: when the highlighted target is off screen, point at it. The camera
	# follows the farmer, so a target can leave the view entirely — at which
	# point the highlight is drawing to nobody and there is no other cue at all.
	var view := Rect2(100, 100, 400, 300)   # centre (300, 250)
	var centre := view.position + view.size / 2.0
	var margin := 10.0

	# On screen: nothing is drawn. An arrow pointing at something she can already
	# see is noise, and noise is what Q-36 was rejecting.
	for inside in [centre, Vector2(105, 105), Vector2(495, 395), Vector2(300, 101)]:
		_assert_quiet(not OverlayMath.edge_arrow(view, inside).visible,
			"a target at %s is inside the view" % inside)
	_flush_quiet("nothing is drawn while the target is on screen")

	# Off screen in each of the eight directions: drawn, clamped to the inset
	# edge, and pointing at the thing.
	var far := 5000.0
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
			Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var target: Vector2 = centre + dir.normalized() * far
		var a: Dictionary = OverlayMath.edge_arrow(view, target, margin)
		_assert_quiet(a.visible, "a target %s of the view is pointed at" % dir)
		var pos: Vector2 = a.pos
		# Inside the view, and on its inset edge rather than somewhere in the middle.
		_assert_quiet(view.has_point(pos), "the arrow at %s is drawn on screen" % dir)
		var on_edge: bool = (
			is_equal_approx(pos.x, view.position.x + margin)
			or is_equal_approx(pos.x, view.end.x - margin)
			or is_equal_approx(pos.y, view.position.y + margin)
			or is_equal_approx(pos.y, view.end.y - margin))
		_assert_quiet(on_edge, "the arrow at %s sits on the inset edge, at %s" % [dir, pos])
		# And it points at the target, not merely away from the centre.
		var want: float = (target - pos).angle()
		_assert_quiet(absf(angle_difference(float(a.angle), want)) < 0.05,
			"the arrow at %s points at the target" % dir)
	_flush_quiet("an off-screen target is pointed at from the edge, in all 8 directions")

	# Quadrant spot-check with real numbers, so a sign error cannot hide behind
	# the loop above.
	var right: Dictionary = OverlayMath.edge_arrow(view, Vector2(9000, 250), margin)
	_assert(is_equal_approx(right.pos.x, view.end.x - margin), "a target to the right clamps to the right edge")
	_assert(is_equal_approx(right.pos.y, centre.y), "and stays level with the centre")
	_assert(absf(float(right.angle)) < 0.001, "pointing right is angle 0")

	var up: Dictionary = OverlayMath.edge_arrow(view, Vector2(300, -9000), margin)
	_assert(is_equal_approx(up.pos.y, view.position.y + margin), "a target above clamps to the top edge")
	_assert(float(up.angle) < 0.0, "and points upward (negative y is up)")

	# Degenerate inputs must not produce a stray arrow.
	_assert(not OverlayMath.edge_arrow(Rect2(0, 0, 0, 0), Vector2(5, 5)).visible,
		"an empty view draws nothing")
	_assert(not OverlayMath.edge_arrow(view, centre).visible,
		"a target exactly at the centre draws nothing")


func test_player_gs_injection() -> void:
	print("\n--- Injectable state, not the autoload (T-16) Tests ---")

	# The T-16 spike (`tools/replay_view.gd`) measured this failing: driving the
	# renderer from a replay drained the **live** GameState to energy 0, wheat 0
	# while the player was still looking at the title screen. A farmer who spends
	# your seeds on the menu is a data-loss bug wearing an animation. The spike's
	# closing note named the cause — `_execute_resolved_action()` used the
	# autoload directly — and this is that finding, fixed and guarded.
	#
	# **Split deliberately.** `player.gd` still names `InputManager`, `ActionRouter`
	# and `Pathfinding` as global identifiers, so the script cannot be *compiled*
	# in this runner, which has no autoloads. Removing those too is a much larger
	# change to the hottest file in the game and is not what T-16 asked for. So the
	# behavioural half — construct a player with a detached state, work a tile,
	# assert the autoload is byte-identical — lives in the integration suite's
	# `_scenario_k_attract`, where autoloads exist. What is checked here is
	# everything that *can* be checked headlessly, including the guarantee that
	# player.gd holds no direct reference to the live state at all.

	# --- farm.gd's injection, which is finding F-4's fix ----------------------
	var detached = load("res://systems/game_state.gd").new()
	detached.reset()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.gs = detached
	farm.mute_feedback = true
	SimRng.reseed(4242)
	farm.sim.generate()

	var t := Vector2i(5, 3)
	farm.set_tile_state(t.x, t.y, "tilled")
	detached.weather = "rainy"
	farm.advance_day()
	_assert(farm.get_tile(t.x, t.y).watered_today,
		"advance_day() reads the injected state's weather, not the autoload's (F-4)")

	detached.weather = "sunny"
	farm.set_tile_state(t.x, t.y, "tilled")
	farm.advance_day()
	_assert(not farm.get_tile(t.x, t.y).watered_today, "and follows it when it changes")

	# --- mute_feedback: the attract farm must be silent ----------------------
	farm.refuse_at(t, "no_seeds")
	farm.acknowledge_at(t, "already_watered")
	_assert(farm._refusals.is_empty(), "a muted farm records no refusal wobble")
	_assert(farm._acks.is_empty(), "and no acknowledgement tick")
	farm.mute_feedback = false
	farm.acknowledge_at(t, "already_watered")
	_assert(not farm._acks.is_empty(), "and speaks again when unmuted")

	# --- player.gd holds no direct reference to the live state ---------------
	# The spike's failure was one hardcoded autoload in one function. Asserting on
	# the source is what stops it coming back in a different function later.
	# Read as text rather than loaded: loading compiles the script, and compiling
	# it in this runner fails on the autoloads it still names, which would print an
	# error the reader would have to learn to ignore.
	var src := FileAccess.get_file_as_string("res://player/player.gd")
	_assert(src.length() > 0, "player.gd is readable as text")
	var offenders: Array = []
	for line in src.split("\n"):
		var code: String = String(line).split("#")[0]
		if not code.contains("GameState"):
			continue
		# The only permitted mentions are the tree lookup supplying the default.
		if code.contains("has_node(") or code.contains("get_node("):
			continue
		offenders.append(String(line).strip_edges())
	_assert(offenders.is_empty(),
		"player.gd never uses the live state directly%s"
			% ("" if offenders.is_empty() else " — found %s" % str(offenders)))
	_assert(src.contains("var gs: Node"), "player.gd declares an injectable state")
	_assert(src.contains("gs.set_energy") or src.contains(", gs)"),
		"and spends that state rather than a global")

	detached.free()
	farm.free()


func test_pre_m15_saves_load() -> void:
	print("\n--- Real pre-M1.5 saves still load (§10.C item 22) Tests ---")

	# M1.5 added six fields to the save (`tools_owned`, `takeover_day`,
	# `clear_counts`, `crop_crows_seen`, `seeds_bought`, `cans_refilled`) and
	# rebuilt world generation underneath them. Every one was chosen to be
	# additive, and `test_tool_acquisition` proves that against a *synthetic* old
	# save — but the fixtures in `playtests/` are the real thing, written by the
	# build that closed M1, and they are what an actual player would be carrying.
	# A migration that works on a save you wrote yourself is not evidence.
	var dir := DirAccess.open("res://playtests")
	_assert(dir != null, "the playtests fixtures directory is readable")
	if dir == null:
		return

	var checked := 0
	for name in dir.get_directories():
		var path := "res://playtests/%s/autosave.json" % name
		if not FileAccess.file_exists(path):
			continue
		var data := SaveGame.load_dict(path)
		if data.is_empty():
			continue
		# Only the genuinely pre-M1.5 fixtures. `playtests/` grows every time a
		# session is pulled off the tablet, so "everything in here is old" stopped
		# being true the moment the first post-M1.5 session landed — detect it by
		# the absence of the fields M1.5 added rather than by date or by faith.
		if data.get("state", {}).has("tools_owned"):
			continue
		checked += 1
		var world := SimWorld.new()
		var gs = load("res://systems/game_state.gd").new()
		var ok: bool = SaveGame.restore(data, world, gs)
		_assert_quiet(ok, "%s restores" % name)
		if ok:
			# Tools default to owned: every one of these was written by a build
			# where she had all six, and confiscating her axe on load would be a
			# bug wearing a migration's clothes.
			_assert_quiet(gs.owns_tool("axe") and gs.owns_tool("pickaxe"),
				"%s keeps every tool" % name)
			# takeover_day 1 is exactly true of a world that had no cold open.
			_assert_quiet(gs.takeover_day == 1, "%s anchors at day 1" % name)
			_assert_quiet(gs.play_day() == gs.day, "%s play-day equals its day" % name)
			# And the world is intact enough to keep playing.
			_assert_quiet(world.tiles.size() == SimWorld.MAP_HEIGHT,
				"%s restored a full grid" % name)
			var spawn := WorldLayout.spawn()
			_assert_quiet(world.get_tile(spawn.x, spawn.y).size() > 0,
				"%s has a tile at the spawn point" % name)
			# The new derived readers must not crash on an old world, which has
			# no gates, no parcels drawn and no acorns in it.
			_assert_quiet(world.count_obstacles_in_open_parcels() >= 0,
				"%s survives the phase-1 progress scan" % name)
			_assert_quiet(String(world.choose_crow_target(0).get("kind", "")) != "",
				"%s survives crow target selection" % name)
			_assert_quiet(not VignetteState.is_active(world, gs, spawn),
				"%s does not resurrect the vignette (it has no gate to open)" % name)
			_assert_quiet(TeachingFocus.targets(world, gs, spawn) is Array,
				"%s survives the teaching arbitration" % name)
		gs.free()
	_flush_quiet("every real pre-M1.5 autosave in playtests/ still loads and plays")
	_assert(checked >= 1, "there was at least one real fixture to check (%d)" % checked)


func test_sim_clock() -> void:
	print("\n--- SimClock: sim time is the tick counter (D-9/Q-53, M2.5 WI-1) Tests ---")

	# Nothing dispatches early, nothing dispatches late, and events sharing a tick
	# dispatch in the order they were scheduled — the property the `seq` tiebreak
	# exists for, so determinism can never come to depend on heap internals.
	var clock := SimClock.new()
	var trace := []
	var read_at := []
	var stamp := func(e: Dictionary) -> void:
		trace.append(String(e.get("name", "")))
		read_at.append(clock.tick)
	clock.schedule(5, { "name": "a" }, stamp)
	clock.schedule(5, { "name": "b" }, stamp)
	clock.schedule(7, { "name": "c" }, stamp)
	clock.schedule(5, { "name": "d" }, stamp)
	_assert(clock.pending() == 4, "four events queued")
	_assert(clock.next_event_tick() == 5, "fast-forward can see the next event without stepping to it")

	_assert(clock.advance_to(4).is_empty(), "advancing short of an event dispatches nothing")
	_assert(clock.tick == 4, "though the clock still arrives where it was sent")
	var fired := clock.advance_to(5)
	_assert(fired.size() == 3, "everything due at a tick fires when that tick arrives")
	_assert(str(trace) == str(["a", "b", "d"]), "events sharing a tick fire in scheduling order")
	_assert(str(read_at) == str([5, 5, 5]), "and the clock reads as their own tick while they do")
	_assert(clock.advance_to(6).is_empty(), "an already-dispatched tick does not fire twice")
	_assert(clock.advance_to(9).size() == 1, "and the later event waits for its own tick")
	_assert(str(read_at) == str([5, 5, 5, 7]), "which is 7, not the 9 the fast-forward was aiming at")
	_assert(clock.pending() == 0 and clock.next_event_tick() == -1, "an empty queue has no next event")

	# Same seed, same schedule, twice: identical dispatch order and tick trace.
	# The walker reschedules itself from the dispatch loop, so this exercises the
	# shape WI-3's brains will actually use rather than a static queue.
	var run := func(seed_value: int) -> String:
		SimRng.reseed(seed_value)
		var c := SimClock.new()
		var out := []
		for i in 8:
			c.schedule(SimRng.randi() % 40, { "name": "e%d" % i })
		c.schedule(3, { "name": "walker", "steps": 5 })
		while c.pending() > 0:
			for e in c.advance_to(c.next_event_tick()):
				out.append("%s@%d" % [String(e.get("name", "")), int(e.get("at", -1))])
				var steps := int(e.get("steps", 0))
				if steps > 1:
					c.schedule(c.tick + 1 + SimRng.randi() % 3,
						{ "name": "walker", "steps": steps - 1 })
		return str(out)

	var first: String = run.call(2026)
	var second: String = run.call(2026)
	_assert(first.length() > 0 and first.count("walker@") == 5,
		"the run produced a trace with the walker's five steps in it")
	_assert(first == second, "same seed + same schedule = identical dispatch order and tick trace")
	_assert(run.call(7) != first, "and a different seed produces a different one")

	# Ground rule 8: fast-forward *jumps*. A million empty ticks cost nothing,
	# because the cost is per event and never per tick. Time.get_ticks_msec() is
	# legal here and nowhere under systems/sim/ — this file is a test, not the sim.
	var far := SimClock.new()
	var hits := []
	var count := func(_e: Dictionary) -> void:
		hits.append(1)
	for i in 10:
		far.schedule(100_000 * (i + 1), { "name": "milestone" }, count)
	var t0 := Time.get_ticks_msec()
	far.advance_to(1_000_000)
	var empty := SimClock.new()
	empty.advance_to(1_000_000)
	var elapsed := Time.get_ticks_msec() - t0
	_assert(hits.size() == 10, "every milestone across a million ticks fired")
	_assert(far.tick == 1_000_000 and empty.tick == 1_000_000, "and both clocks landed on the target tick")
	_assert(elapsed < 100, "1,000,000 empty ticks cross in under 100 ms (%d ms)" % elapsed)

	# Cancelling is how a despawn will withdraw a pending step (WI-3). A cancelled
	# event never fires and never reaches the caller's trace.
	var c2 := SimClock.new()
	var id_a := c2.schedule(10, { "name": "a" })
	c2.schedule(10, { "name": "b" })
	_assert(c2.cancel(id_a), "a pending event can be cancelled")
	_assert(not c2.cancel(id_a), "and cancelling it again is not a second cancellation")
	_assert(c2.pending() == 1, "the cancelled event is gone from the count immediately")
	var survivors := c2.advance_to(20)
	_assert(survivors.size() == 1 and String(survivors[0].get("name", "")) == "b",
		"only the surviving event dispatches")

	# Time never runs backwards, and nothing can be scheduled into the past: an
	# event aimed at a tick already gone lands on the present instead.
	var c3 := SimClock.new()
	c3.advance_to(50)
	c3.schedule(10, { "name": "late" })
	_assert(c3.next_event_tick() == 50, "an event scheduled for a past tick lands on the present")
	c3.advance_to(20)
	_assert(c3.tick == 50 and c3.pending() == 1, "a target in the past is a no-op, not a rewind")
	_assert(c3.advance_to(50).size() == 1, "and the present-tick event fires on the next advance")

	# An event scheduled *during* a dispatch, for the tick being dispatched, joins
	# the same pass behind everything already due there. (Which is also why a
	# process must reschedule itself at tick + 1 or later; see SimClock.schedule.)
	var c4 := SimClock.new()
	var chain := []
	var follow := func(_e: Dictionary) -> void:
		chain.append("follow@%d" % c4.tick)
	var lead := func(_e: Dictionary) -> void:
		chain.append("lead@%d" % c4.tick)
		c4.schedule(c4.tick, { "name": "follow" }, follow)
	c4.schedule(2, { "name": "lead" }, lead)
	var one_pass := c4.advance_to(9)
	_assert(one_pass.size() == 2, "an event scheduled during a dispatch joins the same pass")
	_assert(str(chain) == str(["lead@2", "follow@2"]), "on the same tick, behind what was already due")

	# The clock is sim truth, so it is saved with the world and comes back — the
	# same additive pattern actor_energy used, with no VERSION bump.
	GameState.reset()
	SimRng.reseed(910)
	var world := SimWorld.new()
	world.generate()
	_assert(world.clock.tick == 0, "a freshly generated world starts at tick 0")
	world.clock.advance_to(4242)
	var snap = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var w2 := SimWorld.new()
	var gs2 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snap, w2, gs2), "a save with sim time in it restores")
	_assert(w2.clock.tick == 4242, "and the tick counter survives the round trip")

	var legacy := { "version": SaveGame.VERSION,
		"world": { "tiles": world.tiles.duplicate(true), "objects": world.objects.duplicate(true) },
		"state": {} }
	var w3 := SimWorld.new()
	var gs3 = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(legacy, w3, gs3), "a save written before the clock existed still restores")
	_assert(w3.clock.tick == 0, "reading, correctly, as tick 0")
	gs2.free()
	gs3.free()

	world.generate()
	_assert(world.clock.tick == 0, "regenerating a world restarts its timeline (so a replay counts from the same zero)")
	_assert(SimClock.RATE == 10, "the proposed tick rate is 10 Hz [Playtest]")


# --- M2.5 WI-3 -----------------------------------------------------------------

# A farm being played, the way `world/farm.gd` plays one: actions go through the
# gateway and are recorded, and sim time passes between them, recording whatever
# the brains did with it. Everything below that needs a "live session" uses this,
# so what the tests exercise is the same shape the running game uses.

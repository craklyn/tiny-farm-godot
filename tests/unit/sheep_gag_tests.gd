# Unit tests for what a stuck sheep does with forever (docs/design/18-sheep.md, "Stuck
# for good"): the two facts her brain keeps about her stop, her bald ring of grazed
# grass, the tuft past it she strains for, the beat of the strain itself, and the
# birds that perch on her. The last four are presentation (`entities/sheep_gags.gd`),
# read off the sim at a tick; they are tested here because they are pure functions of
# the sim and need no scene.
extends "res://tests/unit/test_area.gd"


func test_sheep_gags() -> void:
	print("\n--- Sheep: stuck for good, a bald ring, a tuft out of reach, birds ---")
	test_stuck_sheep_remembers_when()
	test_stuck_sheep_save()
	test_bald_ring()
	test_bald_rings_overlap()
	test_tuft_out_of_reach()
	test_neck_stretch_beat()
	test_birds_perch_on_her()
	test_gag_art()


# A generated farm with a wide stretch of open field grass in the middle of the farm
# page, so a ring is never cut by the farm the generator happened to make.
func _open_field() -> SimWorld:
	var world := SimWorld.new(); world.generate()
	for raw in world.actors.keys():
		if String(raw) != SimWorld.ACTOR_PLAYER:
			world.despawn_actor(String(raw))
	for y in range(4, 17):
		for x in range(4, 28):
			world.set_tile_state(x, y, "cleared"); world.set_object(x, y, "")
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(5, 16))
	return world


# An extreme-coat sheep put down at `at` and left to stop.
func _stuck(world: SimWorld, id: String, at: Vector2i) -> void:
	world.spawn_actor(id, SpeciesDefs.SHEEP, at, { "coat": Wool.EXTREME })
	world.actor(id)["facing"] = "right"
	world.schedule_all_brains()
	world.advance_ticks(20, GameState)


func test_stuck_sheep_remembers_when() -> void:
	GameState.reset()
	SimRng.reseed(1901)
	var world := _open_field()
	world.spawn_actor("sheep_1", SpeciesDefs.SHEEP, Vector2i(14, 10), { "coat": Wool.EXTREME })
	world.spawn_actor("sheep_2", SpeciesDefs.SHEEP, Vector2i(20, 10), { "coat": Wool.FULL })
	world.schedule_all_brains()
	var stopped := -1
	for i in 50:
		world.advance_ticks(1, GameState)
		if String(world.actor("sheep_1").extra.get("state", "")) == "content":
			stopped = world.clock.tick
			break
	var extra: Dictionary = world.actor("sheep_1").extra
	_assert(stopped >= 0 and int(extra.get("content_since", -1)) == stopped
		and int(extra.get("nights_content", -1)) == 0,
		"a sheep who stops for good remembers the tick she stopped (%d, %s)" % [stopped, extra.get("content_since")])
	world.advance_ticks(600, GameState)
	_assert(int(extra.content_since) == stopped, "and it stays the tick she stopped while she stands there")
	for night in 2:
		world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	_assert(int(extra.nights_content) == 2 and int(extra.content_since) == stopped,
		"each night she stands there is counted at the day turn (%d)" % int(extra.nights_content))
	var walker: Dictionary = world.actor("sheep_2").extra
	_assert(not walker.has("content_since") and not walker.has("nights_content"),
		"a sheep still walking keeps neither")


func test_stuck_sheep_save() -> void:
	GameState.reset()
	SimRng.reseed(1902)
	var world := _open_field()
	_stuck(world, "sheep_1", Vector2i(14, 10))
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	world.advance_ticks(30, GameState)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var restored := SimWorld.new()
	_assert(SaveGame.restore(saved, restored, GameState)
		and SaveGame.capture_canonical(restored, GameState) == SaveGame.capture_canonical(world, GameState)
		and typeof(restored.actor("sheep_1").extra.content_since) == TYPE_INT
		and typeof(restored.actor("sheep_1").extra.nights_content) == TYPE_INT,
		"when she stopped and the nights since round-trip through a file as whole numbers")
	# A farm saved by the build before the ring: a stuck sheep with neither. She loads
	# with her ring bare, as if she had stood there a night already.
	var older: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	older.world.actors.sheep_1.extra.erase("content_since")
	older.world.actors.sheep_1.extra.erase("nights_content")
	var loaded := SimWorld.new()
	_assert(SaveGame.restore(older, loaded, GameState)
		and int(loaded.actor("sheep_1").extra.get("content_since", -1)) == 0
		and int(loaded.actor("sheep_1").extra.get("nights_content", -1)) == 1
		and SheepGags.ring_is_bare(loaded, "sheep_1"),
		"a sheep stuck before the ring was drawn loads with it bare")
	# Played on from the save beside the farm that kept going, through a night: the
	# two end on the same sheep.
	world.schedule_all_brains()
	var again := SimWorld.new()
	SaveGame.restore(saved, again, GameState)
	for w in [world, again]:
		w.advance_ticks(300, GameState)
		w.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
		w.advance_ticks(300, GameState)
	_assert(SaveGame._first_difference(SaveGame._canonical_capture(again, GameState).world.actors.sheep_1,
		SaveGame._canonical_capture(world, GameState).world.actors.sheep_1, "sheep_1") == "",
		"a loaded farm and the one that kept going agree on her through another night")


func test_bald_ring() -> void:
	GameState.reset()
	SimRng.reseed(1903)
	var world := _open_field()
	var at := Vector2i(14, 10)
	# Things she must leave alone inside her reach: a crop bed, a weed, a fence.
	world.set_tile_state(at.x + 1, at.y, "tilled")
	world.set_tile_state(at.x - 1, at.y + 1, "obstacle_weed")
	world.set_object(at.x, at.y - 1, WorldLayout.FENCE)
	_stuck(world, "sheep_1", at)
	var since := int(world.actor("sheep_1").extra.content_since)
	var graze := SheepGags.ticks(SheepGags.GRAZE_SECONDS)
	# Nine squares in reach, three of them not grass: by each moment, the grass among
	# the squares her order has reached is grazed, and nothing else.
	var order := SheepGags.ring_order("sheep_1")
	var counts: Array[int] = []
	var expected: Array[int] = []
	for k in [0, 1, 4, 8, 20]:
		counts.append(SheepGags.ring_pieces(world, since + k * graze).size())
		var n := 0
		for i in mini(k + 1, order.size()):
			n += 1 if SheepGags.grazable(world, at + order[i]) else 0
		expected.append(n)
	_assert(counts == expected and counts[0] == 1 and counts[-1] == 6,
		"her square first, then a square every %d s, and only the six that are grass (%s)"
			% [int(SheepGags.GRAZE_SECONDS), str(counts)])
	var grazed := {}
	for piece in SheepGags.ring_pieces(world, since + 20 * graze):
		grazed[piece.cell] = int(piece.stage)
	_assert(not grazed.has(at + Vector2i(1, 0)) and not grazed.has(at + Vector2i(-1, 1))
		and not grazed.has(at + Vector2i(0, -1)) and grazed.values().all(func(s): return s == SheepGags.STUBBLE),
		"the bed, the weed and the fence are left alone, and the rest is stubble on her first day")
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	var pieces := SheepGags.ring_pieces(world, world.clock.tick)
	_assert(pieces.size() == 6 and pieces.all(func(p): return int(p.stage) == SheepGags.BARE),
		"a night on, the same six are bare earth")
	# Nothing is grazed under a sheep who has not stopped, or one in a stall.
	world.spawn_actor("sheep_2", SpeciesDefs.SHEEP, Vector2i(22, 10), { "coat": Wool.FULL })
	_assert(SheepGags.stuck_sheep(world) == ["sheep_1"], "only a sheep stopped for good grazes a ring")
	var unique := {}
	for d in order:
		unique[d] = true
	_assert(order.size() == 9 and unique.size() == 9 and order[0] == Vector2i.ZERO,
		"the ring is her square and the eight round it, each once")


func test_bald_rings_overlap() -> void:
	GameState.reset()
	SimRng.reseed(1904)
	var world := _open_field()
	_stuck(world, "sheep_1", Vector2i(12, 10))
	_stuck(world, "sheep_2", Vector2i(14, 10))
	world.actor("sheep_1").extra["nights_content"] = 1
	world.actor("sheep_2").extra["content_since"] = world.clock.tick - SheepGags.ticks(SheepGags.GRAZE_SECONDS * 9)
	var pieces := SheepGags.ring_pieces(world, world.clock.tick)
	var first_bare := -1
	var last_stubble := -1
	for i in pieces.size():
		if int(pieces[i].stage) == SheepGags.BARE and first_bare < 0:
			first_bare = i
		if int(pieces[i].stage) == SheepGags.STUBBLE:
			last_stubble = i
	_assert(pieces.size() == 18 and last_stubble < first_bare,
		"two rings side by side: every stubble piece is drawn before any bare one, so the barer wins where they overlap (%d pieces)" % pieces.size())
	var shared := Vector2i(13, 10)
	var owners := pieces.filter(func(p): return p.cell == shared).map(func(p): return p.centre)
	_assert(owners.size() == 2, "a square both can reach is cut from both discs, so the two circles join")


func test_tuft_out_of_reach() -> void:
	GameState.reset()
	SimRng.reseed(1905)
	var world := _open_field()
	_stuck(world, "sheep_1", Vector2i(14, 10))
	_assert(SheepGags.stretch_target(world, "sheep_1").is_empty(), "no tuft to strain for while her ring is still grass")
	world.actor("sheep_1").extra["nights_content"] = 1
	var target := SheepGags.stretch_target(world, "sheep_1")
	_assert(target.get("cell") == Vector2i(16, 10) and not bool(target.get("left", true)),
		"once it is bare she strains for the grass two squares out, the way she faces (%s)" % str(target))
	# Grass on that side gone (beds), she turns to the tuft on the other.
	for dy in [-1, 0, 1]:
		world.set_tile_state(16, 10 + dy, "tilled")
	target = SheepGags.stretch_target(world, "sheep_1")
	_assert(target.get("cell") == Vector2i(12, 10) and bool(target.get("left", false)),
		"with no grass past her ring on that side, she faces the other way to strain (%s)" % str(target))
	# Another stuck sheep's ring is not a tuft.
	_stuck(world, "sheep_2", Vector2i(11, 10))
	target = SheepGags.stretch_target(world, "sheep_1")
	_assert(target.is_empty() or not SheepGags.in_a_ring(world, target.cell),
		"and never a square another sheep has grazed (%s)" % str(target))


func test_neck_stretch_beat() -> void:
	var period := SheepGags.ticks(SheepGags.STRETCH_EVERY_SECONDS)
	var frames: Array[int] = []
	for t in period:
		frames.append(SheepGags.stretch_frame("sheep_1", 5000 + t))
	var seen := {}
	for f in frames:
		seen[f] = true
	var beat := frames.filter(func(f): return f >= 0).size()
	var expected := 0
	for b in SheepGags.STRETCH_BEAT:
		expected += SheepGags.ticks(float(b[1]))
	_assert(seen.has(-1) and seen.has(SheepArt.STRETCH_REACH) and seen.has(SheepArt.STRETCH_FULL)
		and seen.has(SheepArt.STRETCH_LICK) and seen.has(SheepArt.STRETCH_SMUG) and beat == expected,
		"once a cycle she reaches, stretches, licks and settles back smug, for %d ticks of it" % beat)
	_assert(SheepGags.stretch_frame("sheep_1", 777) == SheepGags.stretch_frame("sheep_1", 777 + period),
		"the beat comes round on the sim clock, the same at the same tick")
	SheepGags.cue("sheep_9", "stretch", 400)
	_assert(SheepGags.stretch_frame("sheep_9", 399) == -1
		and SheepGags.stretch_frame("sheep_9", 400) == SheepArt.STRETCH_REACH,
		"a video tool's cue starts it on demand")
	SheepGags.clear_cues()


func test_birds_perch_on_her() -> void:
	var period := SheepGags.ticks(SheepGags.BIRD_EVERY_SECONDS)
	var arrived := false
	var landed := false
	var heart := false
	var left := false
	var was := {}
	for t in period * 2:
		var b := SheepGags.bird("sheep_1", t)
		if b.is_empty():
			if not was.is_empty() and landed:
				left = true
		else:
			arrived = arrived or bool(b.flying)
			if not bool(b.flying):
				landed = true
				_assert_quiet(b.pos == SheepGags.PERCH, "a perched bird sits on her fleece")
				heart = heart or float(b.heart) >= 0.0
		was = b
	_assert(arrived and landed and heart and left,
		"a bird flies in, sits on her, her heart shows, and it flies off again")
	_assert(SheepGags.bird("sheep_1", 1234) == SheepGags.bird("sheep_1", 1234),
		"which moment of a visit it is depends only on the tick and her id")


func test_gag_art() -> void:
	if SheepArt.is_placeholder():
		_assert(not SheepArt.has_stretch(), "the cow-made stand-in has no neck stretch")
		return
	var cell := SheepArt.cell_size()
	var sheet := SheepArt.sheet()
	var last := SheepArt.stretch_rect(SheepArt.looks() - 1, SheepArt.STRETCH_SMUG)
	_assert(SheepArt.has_stretch() and last.end.y <= sheet.get_height() and last.end.x <= sheet.get_width()
		and int(last.position.y) == (SheepArt.looks() * SheepArt.ROWS + SheepArt.looks() - 1) * cell.y,
		"the neck stretch is a row a look after every look's coats, on the sheet")
	var gags := SheepArt.gag_sheet()
	var fits := gags != null
	for name in ["stubble", "bare", "tuft", "heart"]:
		var r := SheepArt.gag_rect(name)
		fits = fits and r.size.x > 0 and r.end.x <= gags.get_width() and r.end.y <= gags.get_height()
	_assert(fits and SheepArt.gag_rect("bare").size == Vector2(48, 48),
		"the ring's discs, the tuft and the heart are on the gags' sheet, the discs 48 px")

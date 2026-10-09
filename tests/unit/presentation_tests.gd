# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

func test_cot_halo() -> void:
	# T-27 (box 3). The 2026-08-30 tablet session, 5m04–10s: four consecutive
	# `no_energy` refusals on (2,2) — every one a tap meant for the cot at (2,1),
	# one tile north, resolved as till-with-hoe. Nothing was broken; she missed by
	# one tile, four times, and the game said "you cannot till that" four times.
	#
	# The rule under test, in full: **the tapped tile wins whenever it produces a
	# real world change**, and only a tap that produced nothing at all is rescued
	# to a haloed object beside it.
	print("\n--- T-27: the cot's refusal-aware tap halo ---")
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

	GameState.selected_tool = 3          # hoe
	GameState.selected_seed_type = "wheat"
	GameState.pouch = { "wheat": 0 }     # so cleared soil means "till", never "plant"
	GameState.energy = Tools.DAY_UNITS   # T-29: "with energy" is a full day now
	GameState.watering_can_charges = 8

	var cot := Vector2i(2, 1)
	var below := Vector2i(2, 2)          # the tile her finger actually hit
	var beside := Vector2i(3, 2)         # where she was standing while it did
	t.objects[cot.y][cot.x] = "cot"

	# 1. With energy, the tapped tile wins outright.
	var till = ActionRouter.resolve_with_halo(t, GameState, below, beside, false, null)
	_assert(till.get("action", "") == "till",
		"with energy, the tile below the cot still tills — the tapped tile wins")
	_assert(not till.has("halo_from"), "and nothing was rescued")

	# 2. Her exact case: no energy, so the tap resolves to nothing at all.
	GameState.energy = 0
	_assert(ActionRouter.resolve(t, GameState, below, beside, false, null).is_empty(),
		"with no energy that same tap resolves to nothing (the case that refused four times)")
	var saved = ActionRouter.resolve_with_halo(t, GameState, below, beside, false, null)
	_assert(saved.get("action", "") == "sleep", "and the halo rescues it to the cot")
	_assert(saved.get("target_t", Vector2i.ZERO) == cot,
		"re-resolved as a tap on the cot's own tile, so everything downstream is an ordinary cot tap")
	_assert(saved.get("halo_from", Vector2i.ZERO) == below,
		"carrying the tile she actually hit, so the trace can still record the miss")

	# 3. A far tap already has an honest answer — she walks. Rescuing one would put
	#    her to sleep from across the farm.
	_assert(ActionRouter.resolve_with_halo(t, GameState, below, Vector2i(6, 6), false, null).is_empty(),
		"a far tap keeps its walk order and is never rescued")

	# 4. A drag is a deliberate stroke: a swipe along a row must not sleep her when
	#    it reaches the cot's column.
	GameState.energy = Tools.DAY_UNITS  # T-29
	var dragged = ActionRouter.resolve_with_halo(t, GameState, below, beside, true, -1)
	_assert(dragged.is_empty() or not dragged.has("halo_from"),
		"a drag is never rescued")

	# 5. Q-42's third state is an answer, and the halo must not talk over it.
	GameState.energy = 0
	t.tiles[below.y][below.x]["state"] = "growing"
	t.tiles[below.y][below.x]["crop_type"] = "wheat"
	t.tiles[below.y][below.x]["watered_today"] = true
	_assert(ActionRouter.resolve_with_halo(t, GameState, below, beside, false, null).is_empty(),
		"an already-watered crop beside the cot still says 'yes, done' instead of sleeping her")
	t.tiles[below.y][below.x]["state"] = "cleared"
	t.tiles[below.y][below.x]["watered_today"] = false

	# 6. A dead tap with nothing worth rescuing to stays a dead tap.
	_assert(ActionRouter.resolve_with_halo(t, GameState, Vector2i(8, 8), Vector2i(8, 7), false, null).is_empty(),
		"a dead tap with no haloed object beside it is still a dead tap")

	# 7. And the cot itself is untouched by any of this.
	var plain = ActionRouter.resolve_with_halo(t, GameState, cot, below, false, null)
	_assert(plain.get("action", "") == "sleep" and not plain.has("halo_from"),
		"a tap on the cot is a plain cot tap, not a rescue")

	# The halo is wired to the cot and to the door the cot moved behind
	# (2026-09-06), and to nothing else. If this ever fails, the bin and the well
	# arrived — check the designer actually asked for them.
	_assert(ActionRouter.HALO_OBJECTS.size() == 2
			and ActionRouter.HALO_OBJECTS.has("cot")
			and ActionRouter.HALO_OBJECTS.has(WorldLayout.HOUSE_DOOR),
		"two objects are haloed today: the bed, and the front door that leads to it")

	GameState.energy = Tools.DAY_UNITS  # T-29
	GameState.pouch = { "wheat": 5 }
	t.free()


func test_cot_presentation() -> void:
	print("\n--- T-27: the ruled dusk glow and Q-11 floor pulse ---")
	var maxe := 20
	_assert(CotPresentation.SHIPPED == CotPresentation.GLOW,
		"the designer's pick is the dusk glow")
	_assert(CotPresentation.dusk_ramp(maxe, maxe) == 0.0
			and CotPresentation.glow_alpha(maxe, maxe, 0.0) == 0.0,
		"the lamp is dark at dawn")
	_assert(CotPresentation.dusk_ramp(0, maxe) == 1.0
			and CotPresentation.glow_alpha(0, maxe, 0.0) > 0.0,
		"the lamp lights as the day runs out")
	_assert(CotPresentation.dusk_ramp(0, 0) == 0.0,
		"zero max energy does not divide by zero")
	_assert(CotPresentation.at_floor(60) and not CotPresentation.at_floor(61),
		"Q-11's floor pulse still starts with two base actions left")
	_assert(CotPresentation.camera_top_limit(30.0, 3) == -10
			and CotPresentation.camera_top_limit(30.0, 0) == 0,
		"Q-68's ruled camera offset is unconditional at a valid scale")


func test_crop_presentation() -> void:
	# "A ripe crop is obvious at a glance", raised from play 2026-09-07 and ruled
	# 2026-09-08: a ready plant sways gently and gives off its own ripe colour.
	# What is asserted here is only what the cue is *allowed* to be — pure
	# arithmetic over a tile coordinate and a clock, with no way to reach the sim
	# and no way to reach a die.
	print("\n--- A ripe crop is obvious at a glance ---")

	# --- only a ripe square --------------------------------------------------
	_assert(CropPresentation.shows("ready"), "a ready square is treated")
	for other in ["seeded", "growing", "tilled", "cleared", "obstacle_weed"]:
		_assert_quiet(not CropPresentation.shows(other), "and %s is not" % other)
	_assert(true, "and nothing else is — seeded, growing, bare soil, an obstacle")
	_assert(not LookLab.AXES.has("ripe_crop"),
		"the ruled ripe crop is no longer a switch")

	# --- the variation is a function of the square, never a die ---------------
	#
	# The load-bearing property of the whole file. A cue whose phase came out of
	# an RNG would put a replay's screenshot a beat away from the session's, and
	# the visual-regression check would never settle.
	seed(1)
	var first: float = CropPresentation.hash01(Vector2i(7, 3))
	seed(999)
	_assert(CropPresentation.hash01(Vector2i(7, 3)) == first,
		"the same square hashes the same however the engine's dice were last rolled")
	var in_range := true
	var flat := true
	for x in 32:
		for y in 20:
			var h: float = CropPresentation.hash01(Vector2i(x, y))
			if h < 0.0 or h >= 1.0:
				in_range = false
			if h != first:
				flat = false
	_assert(in_range, "and every square on the map hashes into [0, 1)")
	_assert(not flat, "and they are not all the same number")
	_assert(CropPresentation.hash01(Vector2i(7, 3), 1) != first,
		"a salt gives one square a second, independent number — its rate is not its phase")

	# **Not regular**, which is the difference between this and the ground
	# tiling's `tx % 3`. That one is pure and also predictable, and a repeat the
	# eye can predict stops being texture and becomes wallpaper — the exact
	# complaint the CEO made of the mirrored ground on 2026-09-07.
	var periodic := true
	for x in 12:
		if not is_equal_approx(CropPresentation.hash01(Vector2i(x, 5)),
				CropPresentation.hash01(Vector2i(x + 3, 5))):
			periodic = false
	_assert(not periodic, "and a row of squares does not repeat on a three-square beat")

	# --- the sway ------------------------------------------------------------
	var here := Vector2i(6, 11)
	var here_travel: float = CropPresentation.nod_travel(here, "tomato")
	var swing: float = 0.0
	var lifted := false
	for i in 400:
		var o: Vector2 = CropPresentation.nod_offset(here, i * 0.05, "tomato")
		swing = maxf(swing, absf(o.x))
		if o.y < 0.0:
			lifted = true
		_assert_quiet(absf(o.x) <= here_travel + 0.001
				and o.y >= -0.001 and o.y <= CropPresentation.NOD_DROP * here_travel / CropPresentation.NOD_LEAN + 0.001,
			"the sway stays inside its stated bounds")

	# **The head never rises**, which is what keeps the plant in one piece. The
	# renderer draws it as a travelling head over a rooted base; a head that lifts
	# takes its bottom edge off the base's top edge and opens a seam, reported
	# from the crop page on 2026-09-08 as a horizontal line across every ripe
	# plant. The guarantee is the sign of this number, so it is asserted on the
	# number rather than left to the renderer to be careful about.
	_assert(not lifted,
		"the head only ever sinks as it leans — a rising one would part from its own base")
	_assert(CropPresentation.NOD_OVERLAP >= 1,
		"and its piece reaches past the cut, so two rounded rectangles cannot leave a hairline")
	_assert(swing > here_travel * 0.9,
		"the head reaches the sway it is drawn for (%.2f of %.2f world px)"
			% [swing, here_travel])
	_assert(CropPresentation.nod_offset(here, 0.0, "tomato").is_equal_approx(
			CropPresentation.nod_offset(here, CropPresentation.nod_period(here), "tomato")),
		"and comes back to where it started, one period later")
	var apart := false
	for t in [0.3, 0.9, 1.7]:
		if not is_equal_approx(CropPresentation.nod_offset(here, t, "tomato").x,
				CropPresentation.nod_offset(here + Vector2i(1, 0), t, "tomato").x):
			apart = true
	_assert(apart, "two neighbouring plants are never at the same point of the sway")

	# **The sway is gentle, and gentle is a number.** The designer asked for the
	# dance turned down once he saw it beside the light (2026-09-08), so the cue
	# is deliberately at the quiet end — but it is a *state* cue, so there is a
	# floor under it too: a plant that moved by a fraction of a pixel would be a
	# cue nobody can see, which is the failure this whole story was about.
	_assert(CropPresentation.NOD_LEAN >= 0.75 and CropPresentation.NOD_LEAN <= 1.5,
		"the head travels %.2f world px — visible, and not a wave for attention"
			% CropPresentation.NOD_LEAN)
	_assert(CropPresentation.NOD_PERIOD > 2.5,
		"over %.2f seconds, which is weather rather than a heartbeat (the cot owns pulsing)"
			% CropPresentation.NOD_PERIOD)
	_assert(CropPresentation.nod_travel(here, "wheat")
			> CropPresentation.nod_travel(here, "pea")
			and CropPresentation.nod_travel(here, "pea")
			> CropPresentation.nod_travel(here, "tomato"),
		"each crop has its own sway amplitude")
	_assert(not is_equal_approx(CropPresentation.nod_travel(here, "wheat"),
		CropPresentation.nod_travel(here + Vector2i(1, 0), "wheat")),
		"two plants of one crop retain square-to-square amplitude variation")

	# --- the light -----------------------------------------------------------
	_assert(CropPresentation.bloom_radius(0)
			> CropPresentation.bloom_radius(CropPresentation.BLOOM_RINGS - 1),
		"the rings come back widest first, which is the order light has to accumulate in")
	var lit := true
	for i in CropPresentation.BLOOM_RINGS:
		if CropPresentation.bloom_ring_alpha(here, i) <= 0.0:
			lit = false
	_assert(lit, "and every ring of the pool carries light")
	_assert(not is_equal_approx(CropPresentation.bloom_ring_alpha(here, 0),
			CropPresentation.bloom_ring_alpha(here + Vector2i(1, 0), 0)),
		"two ready plants do not glow at identical strength")
	_assert(CropPresentation.bloom_light("wheat") != CropPresentation.bloom_light("tomato"),
		"a ripe wheat and a ripe tomato give off different light — the crop's own colour")
	_assert(CropPresentation.bloom_light("nasturtium") == CropPresentation.RIPE_LIGHT_FALLBACK,
		"and a crop nobody sampled still lights up rather than silently losing the cue")
	var sampled := true
	for crop in CropPresentation.RIPE_LIGHT.keys():
		if not CropDefs.TYPES.has(crop):
			sampled = false
	_assert(sampled, "every sampled colour belongs to a crop this game actually has")

	# **And every crop that can ripen has one.** The other direction, and it is
	# the one that rots: the table is written by hand off three sheets, so the day
	# a fourth crop is added it gets the warm neutral fallback and looks subtly
	# wrong on a farm nobody is inspecting. Growable means it can reach a `ready`
	# tile at all — the scarecrow is an object and the egg does not grow.
	var unsampled: Array[String] = []
	var unswayed: Array[String] = []
	var below_floor: Array[String] = []
	for crop in CropDefs.TYPES.keys():
		var def: Dictionary = CropDefs.TYPES[crop]
		if not def.has("days_to_grow") or bool(def.get("is_object", false)):
			continue
		if not CropPresentation.RIPE_LIGHT.has(crop):
			unsampled.append(String(crop))
		if not CropPresentation.RIPE_SWAY.has(crop):
			unswayed.append(String(crop))
		else:
			var minimum: float = CropPresentation.NOD_LEAN * float(CropPresentation.RIPE_SWAY[crop]) * (1.0 - CropPresentation.NOD_LEAN_SPREAD)
			if minimum < CropPresentation.RIPE_SWAY_FLOOR:
				below_floor.append(String(crop))
	_assert(unsampled.is_empty(),
		"and every crop that can ripen has a colour of its own to give off (missing: %s)"
			% str(unsampled))
	_assert(unswayed.is_empty(), "every growable crop has a sway number (missing: %s)" % str(unswayed))
	_assert(below_floor.is_empty(), "even the least-moving plant of every crop travels at least %.2f world px (below: %s)"
		% [CropPresentation.RIPE_SWAY_FLOOR, str(below_floor)])


func test_home_layout() -> void:
	# T-37, the designer 2026-09-01: *"create an indoor space representing the
	# player's home. The home should have the bed, windows, and very few
	# furnishings initially."*
	#
	# The claim under test: an interior is not new machinery, it is another
	# layout — FLOOR is a ground the way YARD is, WALL/WINDOW are boundaries the
	# way FENCE is, and the bed arrives through the layout's own `objects` list
	# (the first layout to carry one).
	print("\n--- T-37: the home is a layout, not a new kind of world ---")

	SimRng.reseed(3737)
	var w := SimWorld.new()
	w.generate(WorldLayout.HOME)

	# --- 1. the room ------------------------------------------------------------
	var room: Rect2i = WorldLayout.HOME["parcels"][0]["rects"][0]
	var floors := 0
	for ty in range(room.position.y, room.end.y):
		for tx in range(room.position.x, room.end.x):
			_assert_quiet(String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.FLOOR,
				"(%d,%d) is floor" % [tx, ty])
			floors += 1
	_flush_quiet("every tile of the room is floor (%d)" % floors)
	_assert(floors == room.get_area(), "which is the whole parcel (%d)" % floors)

	# The shell: walls, with the two windows and the doorway punched into it.
	_assert(String(w.get_tile(10, 5).get("state", "")) == WorldLayout.WALL, "the corner is wall")
	_assert(String(w.get_tile(13, 5).get("state", "")) == WorldLayout.WINDOW, "window one")
	_assert(String(w.get_tile(18, 5).get("state", "")) == WorldLayout.WINDOW, "window two")
	_assert(String(w.get_tile(15, 13).get("state", "")) == WorldLayout.GATE_OPEN, "the doorway")

	# --- 2. what blocks and what doesn't ----------------------------------------
	_assert(not w.is_walkable(10, 6), "a wall is never walkable")
	_assert(not w.is_walkable(13, 5), "a window is a wall that shows the sky — still a wall")
	_assert(w.is_walkable(15, 13), "the doorway is walkable")
	_assert(w.is_walkable(14, 8), "the floor is walkable")

	# --- 3. the furnishings: the bed, and nothing else --------------------------
	var found := {}
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			var obj := String(w.get_object_at(tx, ty)) if w.has_method("get_object_at") else String(w.objects[ty][tx])
			if obj != "":
				found[obj] = Vector2i(tx, ty)
	_assert(found.get("cot", Vector2i(-1, -1)) == Vector2i(12, 7),
		"the bed is where the layout put it (%s)" % found)
	for station in ["shipping_bin", "well", "seed_box"]:
		_assert(not found.has(station), "%s stays on the farm — the layout's objects override" % station)

	# And the farm itself is untouched by the override's existence: DEFAULT
	# carries no `objects` key, so it falls back to the module constant. Asked of
	# DEFAULT by name since the door (2026-09-06) — the world the game generates
	# now carries an object list of its own, and the fallback is exactly what this
	# line is about.
	SimRng.reseed(3737)
	var farm_w := SimWorld.new()
	farm_w.generate(WorldLayout.DEFAULT)
	_assert(String(farm_w.objects[4][2]) == "cot" and String(farm_w.objects[1][6]) == "well",
		"the default farm still places its four fixed objects")

	# --- 4. never tillable, whoever asks (the yard's rule, indoors) --------------
	_assert(not Tools.can_act_on_tile(3, WorldLayout.FLOOR), "the hoe cannot act on floor")
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var before: int = gs.energy
	var r := w.apply_action({ "verb": "till", "target": Vector2i(14, 8), "actor": "player" }, gs)
	_assert(not r.get("ok", false) and String(r.get("reason", "")) == "not_tillable",
		"the gateway refuses a till on the floor (%s)" % r)
	_assert(gs.energy == before, "and it cost nothing — the guard runs before the meter")

	# --- 5. it round-trips ------------------------------------------------------
	var save: Dictionary = SaveGame.capture(w, gs)
	var w2 := SimWorld.new()
	var restored := SaveGame.restore(save, w2, gs)
	_assert(restored, "a home world saves and restores")
	_assert(String(w2.get_tile(14, 8).get("state", "")) == WorldLayout.FLOOR
		and String(w2.get_tile(13, 5).get("state", "")) == WorldLayout.WINDOW,
		"floor and window states survive a save round-trip")


func test_yard_ground() -> void:
	# T-32, the designer 2026-09-01: *"create a separate form of ground that cannot
	# be tilled, and fill the initial fenced space with it."*
	#
	# **The yard is home, not field.** Walkable like the field, never tillable, and
	# everything else in the sim indifferent to it. The three claims in that
	# sentence are the three sections below; the fourth section is the one that
	# makes them cheap — the fill costs the RNG stream nothing, so a worldgen
	# change this large moves no seeded placement at all.
	print("\n--- T-32: the yard is home, not field ---")

	var yard_rect: Rect2i = WorldLayout.parcels()[0]["rects"][0]

	# **On DEFAULT, deliberately** (2026-09-06). T-32 is a claim about the farm
	# layout, and the farm layout is what this generates — the composed world the
	# game now plays keeps the identical yard on page 0 (`test_world_pages` asserts
	# it tile for tile), but the cot it once held has moved indoors, and asserting
	# the cot's yard tile here would be asserting it of a world where the cot is
	# not in the yard at all.
	SimRng.reseed(2026)
	var w := SimWorld.new()
	w.generate(WorldLayout.DEFAULT)
	var inside := 0
	for ty in range(yard_rect.position.y, yard_rect.end.y):
		for tx in range(yard_rect.position.x, yard_rect.end.x):
			_assert_quiet(String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.YARD,
				"(%d,%d) is yard ground" % [tx, ty])
			inside += 1
	_flush_quiet("every tile of the fenced space is yard ground (%d)" % inside)
	_assert(inside == yard_rect.get_area(), "which is the whole parcel (%d)" % inside)

	# And nowhere else is. The yard is a place, not a texture: a stray yard tile
	# outside the fence would be land she could walk on and never work, with no
	# fence to explain why.
	var outside := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.YARD \
					and not yard_rect.has_point(Vector2i(tx, ty)):
				outside += 1
	_assert(outside == 0, "and no tile beyond the fence is (%d)" % outside)

	# The cot came down three rows with it, and the objects still sit on ground
	# rather than in it — step 5b runs *after* the object step precisely so the
	# shoulders it clears do not survive as tillable holes around the furniture.
	_assert(w.objects[4][2] == "cot", "the cot's footprint is (2,4)")
	_assert(w.get_object(2, 3) == "cot", "and its head tile is (2,3), from TALL_OBJECTS")
	_assert(String(w.get_tile(2, 4).get("state", "")) == WorldLayout.YARD
			and String(w.get_tile(2, 5).get("state", "")) == WorldLayout.YARD,
		"the cot stands on yard, and so does the tile below it — the fat-finger tile")
	for obj in SimWorld.OBJECT_POSITIONS:
		_assert_quiet(String(w.get_tile(obj.tx, obj.ty).get("state", "")) == WorldLayout.YARD,
			"%s stands on yard ground" % obj.type)
	_flush_quiet("no fixed object left a ring of tillable field around itself")

	# --- 2. walkable like the field --------------------------------------------
	_assert(w.is_walkable(5, 3) and w.is_walkable(9, 6),
		"yard ground is walkable, exactly like the field")
	var reach := w.reachable_from(WorldLayout.spawn())
	_assert(reach.size() > 20,
		"and the whole yard is still hers to cross (%d tiles reachable)" % reach.size())
	var all_yard := true
	for t in reach:
		if String(w.get_tile(t.x, t.y).get("state", "")) != WorldLayout.YARD:
			all_yard = false
	_assert(all_yard, "every tile she can reach before the gate opens is yard ground")

	# --- 3. never tillable, whoever asks ---------------------------------------
	# The tool layer says so, the gateway enforces it, and the router therefore
	# never has occasion to refuse anything (T-18 — that half is Scenario AA's).
	_assert(not Tools.can_act_on_tile(3, WorldLayout.YARD),
		"the hoe cannot act on yard ground")
	_assert(Tools.get_action(3, WorldLayout.YARD) == "",
		"so there is no hoe action to name")

	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var before: int = gs.energy
	var r := w.apply_action({ "verb": "till", "target": Vector2i(5, 3), "actor": "player" }, gs)
	_assert(not r.get("ok", false) and String(r.get("reason", "")) == "not_tillable",
		"the gateway refuses her till on yard ground (%s)" % r)
	_assert(String(w.get_tile(5, 3).get("state", "")) == WorldLayout.YARD,
		"the ground is unchanged")
	_assert(gs.energy == before, "and it cost her nothing — the guard runs before the meter")

	# S-3, ground rule 1: one gateway, so the rule is the same for everybody. A bot
	# gets no verb the player lacks, and no ground she cannot work either.
	w.spawn_actor("bot_0", SpeciesDefs.BOT, Vector2i(5, 4))
	var rb := w.apply_action({ "verb": "till", "target": Vector2i(5, 3), "actor": "bot_0" }, gs)
	_assert(not rb.get("ok", false) and String(rb.get("reason", "")) == "not_tillable",
		"and refuses a bot's, identically (%s)" % rb)
	_assert(w.energy_of("bot_0") == SimWorld.ACTOR_MAX_ENERGY,
		"which also cost the machine nothing")

	# The field is untouched by any of this: the guard names one state.
	var rf := w.apply_action({ "verb": "till", "target": Vector2i(13, 4), "actor": "player" }, gs)
	_assert(rf.get("ok", false) and String(w.get_tile(13, 4).get("state", "")) == "tilled",
		"a till beyond the fence still lands, on the ordinary field ground it always did")

	# Everything else is indifferent to it, which is what "a form of ground" means
	# rather than "a new kind of object". A hen lays on it, a crow flies over it,
	# water washes a trail off it.
	_assert(w.apply_action({ "verb": "lay_egg", "target": Vector2i(6, 3), "actor": "chicken" }
			).get("ok", false),
		"a hen lays an egg on yard ground like any other")
	_assert(not w.has_crop(5, 3), "nothing grows in it")
	_assert(String(w.choose_crow_target(0).get("kind", "")) != "",
		"and a crow still finds something to want")

	# --- 4. the fill costs the RNG stream nothing -------------------------------
	# The strongest thing that can be said about a worldgen change of this size:
	# generate the same seed with and without the yard's ground and the two worlds
	# differ in **exactly** the yard's tiles. Every seeded placement — the acorn
	# stock, the hen's tile, the obstacle rolls — lands where it always did, so
	# nothing outside the fence moved because of T-32.
	var plain: Dictionary = WorldLayout.DEFAULT.duplicate(true)
	plain["parcels"][0].erase("ground")
	SimRng.reseed(31337)
	var a := SimWorld.new()
	a.generate(WorldLayout.DEFAULT)
	SimRng.reseed(31337)
	var b := SimWorld.new()
	b.generate(plain)
	var differ_in := 0
	var differ_out := 0
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if String(a.get_tile(tx, ty).get("state", "")) \
					!= String(b.get_tile(tx, ty).get("state", "")):
				if yard_rect.has_point(Vector2i(tx, ty)):
					differ_in += 1
				else:
					differ_out += 1
	_assert(differ_in == yard_rect.get_area() and differ_out == 0,
		"with and without the yard's ground, the same seed differs in exactly its %d tiles (%d in, %d out)"
			% [yard_rect.get_area(), differ_in, differ_out])
	_assert(str(a.objects) == str(b.objects),
		"and not one object moved — the acorn stock included, so no draw was spent")
	_assert(a.actor_pos(SimWorld.ACTOR_CHICKEN) == b.actor_pos(SimWorld.ACTOR_CHICKEN),
		"nor did the hen, who is placed from the stream after the fill")

	# --- 5. saves: written, restored, and deliberately not migrated -------------
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(a, gs)))
	var back := SimWorld.new()
	var gs_back = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(snapshot, back, gs_back), "a farm with a yard in it saves and restores")
	_assert(String(back.get_tile(5, 3).get("state", "")) == WorldLayout.YARD,
		"with its ground intact")

	# **No migration, on purpose.** A save from before T-32 restores a fenced space
	# of ordinary field, including any rows she tilled in it, and keeps playing.
	# Rewriting her ground underneath her would delete work she did to answer a
	# rule that did not exist when she did it.
	var old_save: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	old_save["world"]["tiles"][3][5] = { "state": "tilled", "crop_type": "",
		"growth_stage": 0, "watered_today": false }
	var legacy := SimWorld.new()
	var gs_legacy = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(old_save, legacy, gs_legacy),
		"a save whose yard was tilled before T-32 existed still restores")
	_assert(String(legacy.get_tile(5, 3).get("state", "")) == "tilled",
		"keeping her tilled row exactly as she left it")
	_assert(legacy.apply_action({ "verb": "plant", "target": Vector2i(5, 3),
			"seed_type": "wheat", "actor": "player" }, gs_legacy).get("ok", false),
		"and she can go on farming it — the yard is a fact about generation, not a law of physics")

	gs.free()
	gs_back.free()
	gs_legacy.free()


func test_station_presentation() -> void:
	# T-28, drafted rather than decided. The designer's two observations about the
	# bin, the well and the seed box — (1) they never say what they are for before
	# first use, (2) their "already done" answers do not communicate — get two
	# treatments each, all four in one build, switched on the tablet with a thumb.
	#
	# This test does not know which he will pick. It holds the drafts to the rules
	# they have to obey either way: the axes are independent, the pictures exist,
	# the pip never fights the teaching highlight, nothing fires before the farm is
	# hers, and none of it touches the sim.
	print("\n--- The stations present themselves (T-28) Tests ---")

	var was_s: int = StationPresentation.satisfied
	_assert(StationPresentation.DISCOVERY_SHIPPED == StationPresentation.DISCOVERY_PIP
			and StationPresentation.satisfied == StationPresentation.SATISFIED_NOUN,
		"stations ship with purpose pips and the noun reply")
	_assert(StationPresentation.set_satisfied(StationPresentation.SATISFIED_CHIP)
			== StationPresentation.SATISFIED_CHIP,
		"the wordless HUD remains available for the separate designer question")
	StationPresentation.set_satisfied(was_s)
	_assert(StationPresentation.SATISFIED_NAMES.size() == StationPresentation.SATISFIED_COUNT,
		"the retained HUD comparison has names")

	# --- the look lab with its one open colour question ------------------------
	#
	# The answered cot, station and ripe-crop axes stay retired. Unknown axes
	# still answer empty while Q-14 offers its colour comparison.
	_assert(LookLab.AXES.size() == 1 and LookLab.AXES[0] == "world_tint",
		"the colour study is the only open look switch")
	_assert(LookLab.changed_axes().is_empty()
			and LookLab.restore_label() == "Every look is as it ships",
		"and there is nothing to put back")
	_assert(LookLab.count_of("no_such_axis") == 0
			and LookLab.name_of("no_such_axis", 0) == ""
			and LookLab.option_label("no_such_axis") == "no_such_axis: ",
		"an axis that does not exist answers empty rather than crashing the menu")
	LookLab.restore_all()
	_assert(LookLab.last_change_text() == "Every look back to what ships",
		"and a put-back with nothing in it is still a sentence, not a crash")
	_assert(LookScenarios.SCENARIOS.size() == 1
			and LookScenarios.by_id("world_colour_station")["axis"] == "world_tint",
		"the station capture draws the same colour axis as the game")


	# --- the pictures exist --------------------------------------------------
	#
	# Finding F-5's lesson, applied before it can happen again: the refusal icons
	# and the router's vocabulary drifted apart silently once, and what stopped it
	# coming back was making the table something a test can walk.
	var art_ok := true
	for kind in StationPresentation.STATIONS:
		if not StationPresentation.STATION_GLYPHS.has(kind):
			art_ok = false
			continue
		if not StationPresentation.GLYPH_ATLAS.has(StationPresentation.STATION_GLYPHS[kind]):
			art_ok = false
	_assert(art_ok, "every station has a glyph and every glyph has a cell on a sheet")

	var sheets := { "icons": "res://assets/sprites/generated/shop_icons.png",
		"tools": "res://assets/sprites/tool_icons.png" }
	var cells_ok := true
	for key in StationPresentation.GLYPH_ATLAS.keys():
		var entry: Dictionary = StationPresentation.GLYPH_ATLAS[key]
		if not sheets.has(entry.get("sheet", "")):
			cells_ok = false
			continue
		var r: Array = entry["rect"]
		var tex: Texture2D = load(sheets[entry["sheet"]])
		if tex == null or r.size() != 4 \
				or r[0] + r[2] > tex.get_width() or r[1] + r[3] > tex.get_height():
			cells_ok = false
	_assert(cells_ok, "and every one of those cells is really on the sheet it claims")

	# The two nouns T-28 had to draw (`tools/gen_station_glyphs.py`, derived from
	# the can and the bin, no art spend) are actually in the file — an empty cell
	# would draw as nothing at all and fail silently, which is the worst failure
	# a wordless cue can have.
	var icons_img: Image = (load(sheets["icons"]) as Texture2D).get_image()
	var drawn_ok := true
	for key in [StationPresentation.GLYPH_DROPLET, StationPresentation.GLYPH_BASKET]:
		var r2: Array = StationPresentation.GLYPH_ATLAS[key]["rect"]
		var ink := 0
		for y in range(r2[1], r2[1] + r2[3]):
			for x in range(r2[0], r2[0] + r2[2]):
				if icons_img.get_pixel(x, y).a > 0.15:
					ink += 1
		if ink < 40:
			drawn_ok = false
	_assert(drawn_ok, "the droplet and the empty basket are drawn, not empty cells")

	# --- the already-done nouns cover every answer the router can give -------
	#
	# Driven rather than listed: the codes come out of `satisfied_reason` itself,
	# so a fourth good state added later arrives here as a failure instead of as a
	# cue that silently says nothing.
	GameState.reset()
	var farm_node = load("res://world/farm.gd").new()
	farm_node.generate_on_ready = false
	SimRng.reseed(41)
	farm_node.sim.generate()
	var crop_t := Vector2i(7, 6)
	farm_node.sim.tiles[crop_t.y][crop_t.x]["state"] = "growing"
	farm_node.sim.tiles[crop_t.y][crop_t.x]["crop_type"] = "wheat"
	farm_node.sim.tiles[crop_t.y][crop_t.x]["watered_today"] = true
	GameState.watering_can_charges = GameState.max_watering_can_charges
	GameState.pouch["wheat"] = 0
	GameState.pouch["tomato"] = 0
	var codes: Array[String] = []
	for probe in [crop_t, Vector2i(6, 1), Vector2i(4, 1)]:
		var code: String = ActionRouter.satisfied_reason(farm_node, GameState, probe)
		if code != "" and not codes.has(code):
			codes.append(code)
	_assert(codes.size() == 2 and not codes.has("basket_empty"),
		"the router gives two already-done answers and leaves the bin open (%s)" % ", ".join(codes))
	var nouns_ok := true
	for code in codes:
		if StationPresentation.noun_for(code) == "" \
				or not StationPresentation.GLYPH_ATLAS.has(StationPresentation.noun_for(code)):
			nouns_ok = false
	_assert(nouns_ok, "and every one of them has a noun to say itself with (treatment A)")
	_assert(StationPresentation.noun_for("no_seeds") == "",
		"while a refusal code gets no noun here — a refusal is not an answer of this kind")
	farm_node.free()

	# --- the pips ------------------------------------------------------------
	var world := SimWorld.new()
	SimRng.reseed(1212)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	var bin := Vector2i(4, 1)
	var well := Vector2i(6, 1)
	var box := Vector2i(8, 1)

	# Before the handover, nothing at all: the neighbour is the show, and a hint
	# on a farm that is not hers yet is a hint on a tile whose tap does nothing.
	gs.pouch["wheat"] = 2
	_assert(StationPresentation.pips(world, gs).is_empty(),
		"during the cold open the stations say nothing — guard 0, shared with the highlight")

	world.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
		"actor": "neighbour" }, gs)
	gs.day = gs.takeover_day + 5   # past the vignette, which owns the highlight outright

	gs.pouch["wheat"] = 0
	gs.pouch["tomato"] = 0
	gs.watering_can_charges = gs.max_watering_can_charges
	gs.gold = 0
	_assert(StationPresentation.pips(world, gs).is_empty(),
		"a farmer with nothing to sell, no water spent and no money is told nothing")

	# The bin, at *relevance* rather than at need. This is the whole of T-28's
	# discovery gap: T-11's beat waits for three crops, and a first crop is
	# already something to sell.
	gs.pouch["wheat"] = 0 + 1
	var p1 := StationPresentation.pips(world, gs)
	_assert(p1.size() == 1 and p1[0]["at"] == bin
			and p1[0]["glyph"] == StationPresentation.GLYPH_COIN,
		"one crop in the basket floats a coin over the bin — before the beat would fire")
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"and at that moment the teaching highlight is still silent, which is the gap")

	# The *other* half of the gap, and the sharper one: even once the beat would
	# fire, an unlearned obstacle outranks it, so the errand waits for the lesson
	# (`targets()` returns the first non-empty). Here the highlight is on a weed
	# and the pip is free to speak about the bin — two systems busy at once,
	# on two tiles, saying two different kinds of thing.
	var taught_now := TeachingFocus.targets(world, gs)
	_assert(not taught_now.is_empty() and not taught_now.has(bin),
		"the highlight is elsewhere — a lesson outranks an errand — and the pip fills the silence")

	# Where they meet, the directive cue wins and the ambient one gets out of the
	# way. One glowing thing at a time, extended to cover the quiet thing too.
	gs.pouch["wheat"] = 0 + TeachingFocus.SELL_BEAT_CROPS
	gs.clear_counts["clear_weed"] = 1   # the parcel's lesson is done; the errand can be heard
	_assert(TeachingFocus.targets(world, gs).has(bin),
		"at three crops, with no lesson outranking it, the highlight takes the bin")
	var p2 := StationPresentation.pips(world, gs)
	var bin_pipped := false
	for pip in p2:
		if pip["at"] == bin:
			bin_pipped = true
	_assert(not bin_pipped,
		"and the pip stands down there — they never draw on one tile (the pip is ambient, the highlight is directive)")

	world.apply_action({ "verb": "sell", "actor": "player" }, gs)
	gs.gold = 0        # the sale's coins would otherwise light the seed box next
	gs.pouch["wheat"] = 9
	var p3 := StationPresentation.pips(world, gs)
	for pip in p3:
		_assert(pip["at"] != bin, "selling once retires the bin's pip for good")
	_assert(p3.is_empty(), "and with nothing else relevant, nothing is shown at all")

	# The well, at the first sip rather than at the last.
	gs.watering_can_charges = gs.max_watering_can_charges - 1
	var p4 := StationPresentation.pips(world, gs)
	_assert(p4.size() == 1 and p4[0]["at"] == well
			and p4[0]["glyph"] == StationPresentation.GLYPH_CAN,
		"a can that is not full floats the can over the well")
	_assert(TeachingFocus.economy_beat(world, gs).is_empty(),
		"where the beat waits for empty")
	world.apply_action({ "verb": "refill", "actor": "player" }, gs)
	gs.watering_can_charges = 0
	for pip in StationPresentation.pips(world, gs):
		_assert(pip["at"] != well, "refilling once retires the well's pip")

	# The seed box: relevance is money, and never a shop that will refuse her.
	gs.watering_can_charges = gs.max_watering_can_charges
	# Priced at what this farm could actually buy: wheat left the shelf with S-18/S-19/S-20
	# and a tomato is locked until she has cut one, so the packet the box is
	# costed at follows her harvests.
	gs.harvest_counts["wheat"] = 1
	gs.gold = TeachingFocus.cheapest_seed(gs.harvest_counts) - 1
	_assert(StationPresentation.pips(world, gs).is_empty(),
		"a pocket one coin short of a seed points at nothing — never send her to a shop that will refuse her")
	gs.gold = TeachingFocus.cheapest_seed(gs.harvest_counts)
	var p5 := StationPresentation.pips(world, gs)
	_assert(p5.size() == 1 and p5[0]["at"] == box
			and p5[0]["glyph"] == StationPresentation.GLYPH_PACKET,
		"the price of one seed floats a packet over the box, pouch full or not")
	world.apply_action({ "verb": "buy_seed", "seed_type": "pea", "actor": "player" }, gs)
	gs.gold = 500
	for pip in StationPresentation.pips(world, gs):
		_assert(pip["at"] != box, "and buying once retires it")

	# --- D-8: none of this can reach the gateway -----------------------------
	#
	# Every treatment is presentation, so asking it what to draw must leave the
	# world byte-identical. Cheap to prove and the one property that would break
	# replays if it were ever false.
	var before := SaveGame.capture_canonical(world, gs)
	for sat in [StationPresentation.SATISFIED_NOUN, StationPresentation.SATISFIED_CHIP]:
		StationPresentation.set_satisfied(sat)
		StationPresentation.pips(world, gs, Vector2i(9, 9))
		for kind in StationPresentation.STATIONS:
			StationPresentation.used(gs, kind)
			StationPresentation.relevant(gs, kind)
			StationPresentation.find_station(world, kind)
	_assert(SaveGame.capture_canonical(world, gs) == before,
		"asking either retained HUD comparison what to draw, changed nothing in the world (D-8)")

	# A missing GameState is a renderer that is starting up, not a crash.
	_assert(StationPresentation.pips(world, null).is_empty()
			and StationPresentation.used(null, StationPresentation.BIN),
		"and a half-built scene asks these questions safely")

	gs.free()
	StationPresentation.set_satisfied(was_s)
	_assert(StationPresentation.DISCOVERY_SHIPPED == StationPresentation.DISCOVERY_PIP
			and StationPresentation.satisfied == StationPresentation.SATISFIED_NOUN,
		"and the ruled picks are restored")


# --- The zoo (T-33) -----------------------------------------------------------
#
# The zoo's job is to be the one surface that cannot fall behind the bestiary, so
# the first assertion here is the only one that really matters: **the roster is
# `SpeciesDefs.ids()`**, not a list somebody wrote out beside it. Everything else
# proves that the door it opens actually leads somewhere — every species reaching
# the registry, with its own brain bound, through its own real entry point.
func test_world_tint_presentation() -> void:
	print("\n--- World colour switch (Q-14) Tests ---")
	WorldTintPresentation.set_to(WorldTintPresentation.NEUTRAL)
	_assert(WorldTintPresentation.multiplier() == Color.WHITE,
		"the shipping look does not alter daylight")
	_assert(LookLab.count_of("world_tint") == 3,
		"the switch contains today, quiet world and cold light")
	LookLab.set_to("world_tint", WorldTintPresentation.QUIET_WORLD)
	_assert(WorldTintPresentation.multiplier().g > WorldTintPresentation.multiplier().r,
		"quiet world moves toward grey green")
	_assert(LookLab.changed_axes() == ["world_tint"],
		"the game reports a colour draft away from shipping")
	LookLab.set_to("world_tint", WorldTintPresentation.COLD_LIGHT)
	_assert(WorldTintPresentation.multiplier().b > WorldTintPresentation.multiplier().r,
		"cold light has a blue cast")
	LookLab.restore_all()
	_assert(WorldTintPresentation.multiplier() == Color.WHITE,
		"restore returns the world to the shipped colour")


func test_zoo() -> void:
	print("\n--- The zoo (T-33) ---")

	# 1. The roster cannot drift from the table.
	var expected: Array[String] = []
	for raw in SpeciesDefs.ids():
		if not String(raw) in Zoo.EXCLUDED:
			expected.append(String(raw))
	_assert(Zoo.roster() == expected,
		"the roster is SpeciesDefs.ids() minus the exclusions, in the table's order (%d species)"
			% Zoo.roster().size())
	_assert(not SpeciesDefs.PLAYER in Zoo.roster(),
		"the farmer is scenery here, not an exhibit")
	_assert(Zoo.roster().size() == SpeciesDefs.ids().size() - Zoo.EXCLUDED.size(),
		"and nothing else is quietly filtered out — a new row appears with no edit to the panel")
	for species in Zoo.roster():
		_assert(SpeciesDefs.has(species) and Brains.has(SpeciesDefs.brain_of(species)),
			"%s has a species row and a brain this build knows" % species)
	# The picture and the renderer are one decision, so the two tables agree
	# exactly: art that exists has a portrait, art that does not has neither.
	var renderers: Dictionary = Zoo.renderers()
	for species in Zoo.roster():
		_assert(Zoo.has_art(species) == renderers.has(species),
			"%s has a button portrait exactly when the farm has a sprite for it" % species)

	# 2. The field.
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var world := SimWorld.new()
	Zoo.furnish(world, gs)
	_assert(world.actors.keys() == [SimWorld.ACTOR_PLAYER],
		"a furnished zoo holds the farmer and nobody else — the census starts at zero")
	_assert(world.count_planted() >= 4 and world.count_acorns() >= 1,
		"stocked: %d crops in the ground and %d acorns, so every mouth finds its own food"
			% [world.count_planted(), world.count_acorns()])
	var seeded := 0
	for t in Zoo.SOWN:
		if world.has_seed(t.x, t.y):
			seeded += 1
	_assert(seeded == Zoo.SOWN.size(), "and seed in the ground for a mole to steal (%d tiles)" % seeded)
	_assert(gs.play_day() >= 6 and gs.total_harvests() >= SimWorld.CROW_MIN_HARVESTS,
		"on a calendar every readiness gate is already past (play day %d)" % gs.play_day())
	var flat := true
	for ty in range(1, SimWorld.MAP_HEIGHT - 1):
		for tx in range(1, SimWorld.MAP_WIDTH - 1):
			if String(world.tiles[ty][tx]["state"]).begins_with("obstacle"):
				flat = false
	_assert(flat, "the field is flat — nothing is in the way of a walk, a hop or a flight")

	# 3. Every species gets in, through its own entry point, with its brain bound.
	var born_by_species: Dictionary = {}
	for species in Zoo.roster():
		var born := Zoo.spawn(world, gs, species, 0)
		born_by_species[species] = born
		_assert(not born.is_empty(), "%s enters the zoo" % species)
		for id in born:
			_assert(world.species_of(id) == species,
				"  %s is registered as a %s" % [id, species])
			_assert(Brains.of_actor(world, id) == Brains.of_species(species),
				"  and thinks with its own brain")
	_assert(born_by_species[SpeciesDefs.ANT_FORAGER].size() == SimWorld.ANT_COLUMN_SIZE,
		"the forager button raises a whole column (%d), because that is how a forager exists"
			% SimWorld.ANT_COLUMN_SIZE)
	_assert(world.actor(born_by_species[SpeciesDefs.BOT][0])["extra"]["config"]
			== BotBrain.CONFIGS[0],
		"the first bot is a %s bot" % BotBrain.CONFIGS[0])
	_assert(String(world.actor(SimWorld.ACTOR_CROW)["extra"].get("kind", "")) == "acorn",
		"and the crow goes for an acorn, which is the T-15 rule and not a zoo special case")

	# 4. The census reports what the registry holds.
	var census := Zoo.census(world)
	var counted := 0
	for species in census:
		counted += int(census[species])
		_assert(int(census[species]) == world.actors_of_species(String(species)).size(),
			"census agrees with the registry for %s" % species)
	_assert(counted == world.actors.size() - 1,
		"and covers everybody but the farmer (%d)" % counted)

	# 5. It runs. 200 ticks of every brain in the game deciding at once.
	var before_tick := world.clock.tick
	world.advance_ticks(200, gs)
	_assert(world.clock.tick == before_tick + 200, "200 ticks pass with the whole bestiary awake")
	_assert(world.has_actor(SimWorld.ACTOR_PLAYER), "and the farmer is still standing there")

	# 6. One more of each — the interaction the roster exists for. The real entry
	#    points refuse a second of anything, so this is the park-and-rename path.
	for species in Zoo.roster():
		var again := Zoo.spawn(world, gs, species, 1)
		_assert(not again.is_empty(), "a second %s can be added" % species)
		for id in again:
			_assert(world.has_actor(id) and world.species_of(id) == species,
				"  %s joined without evicting the first" % id)
	_assert(world.actors_of_species(SpeciesDefs.RABBIT).size() >= 2,
		"two rabbits on one farm, which no real game would ever allow")
	world.advance_ticks(200, gs)

	# 7. A day turn: the machine's whole life, and everybody wakes rested.
	#
	# The patch is re-sown under the machine first, because four hundred ticks of
	# a full bestiary is exactly long enough for the mouths to have eaten what it
	# was standing over — which is the zoo working, not the sprinkler failing.
	var sprinkler_id: String = world.actors_of_species(SpeciesDefs.SPRINKLER)[0]
	var covered: Array[Vector2i] = SprinklerBrain.coverage(world, sprinkler_id)
	for t in covered:
		world.set_tile_state(t.x, t.y, "growing", "wheat")
		world.tiles[t.y][t.x]["watered_today"] = false
	# Somebody with no day-turn job of their own, so "rested" is observable after
	# the turn rather than immediately spent (the sprinkler waters nine tiles out
	# of its own meter, which is the point of the meter).
	var hen: String = world.actors_of_species(SpeciesDefs.CHICKEN)[0]
	world.set_actor_energy(hen, 1)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)
	var wet := 0
	for t in covered:
		if world.tiles[t.y][t.x]["watered_today"]:
			wet += 1
	_assert(wet == covered.size(),
		"the day turn fires the sprinkler over its whole radius (%d of %d tiles wet)"
			% [wet, covered.size()])
	_assert(world.energy_of(hen) == SimWorld.ACTOR_MAX_ENERGY,
		"and everybody wakes rested")

	# 8. Clear.
	var gone := Zoo.clear(world)
	_assert(gone > 0 and world.actors.keys() == [SimWorld.ACTOR_PLAYER],
		"clear empties the zoo (%d removed) and leaves the farmer" % gone)
	_assert(Zoo.census(world).is_empty(), "so the census is empty again")

	# 9. And it can be refilled from empty, which is the loop a designer actually
	#    does: add, watch, clear, add something else.
	_assert(not Zoo.spawn(world, gs, SpeciesDefs.KANGAROO, 0).is_empty(),
		"and the zoo refills after a clear")

	# 10. A gate may genuinely refuse in here — the residents eat the crops the
	#     ant and crow gates count — and the refusal has words and a remedy.
	#     (Found 2026-09-01: the scout button silently did nothing on a grazed-
	#     out field, which read as a broken button.)
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			var st := String(world.tiles[ty][tx].get("state", ""))
			if st == "seeded" or st == "growing" or st == "ready":
				world.set_tile_state(tx, ty, "grass")
	_assert(Zoo.spawn(world, gs, SpeciesDefs.ANT_SCOUT, 0).is_empty(),
		"a grazed-out field refuses a scout — the real gate, not a zoo special case")
	_assert(Zoo.decline_reason(world, SpeciesDefs.ANT_SCOUT) != "",
		"and the refusal can say why: %s" % Zoo.decline_reason(world, SpeciesDefs.ANT_SCOUT))
	_assert(Zoo.decline_reason(world, SpeciesDefs.CROW) != "",
		"the crow's gate too")
	Zoo.stock(world)
	_assert(world.count_planted() >= SimWorld.ANT_MIN_PLANTED,
		"Re-sow restocks the field past the gates")
	_assert(not Zoo.spawn(world, gs, SpeciesDefs.ANT_SCOUT, 1).is_empty(),
		"and the scout button works again")

	gs.free()


# Reported from play 2026-09-01: *"When weather is rainy and corn was ready to
# collect, the ground drew as dry instead of wet under it. Unripe corn still had
# wet ground."*
#
# Confirmed against the code before it was touched, and the confirmation is the
# interesting part: this was **not** the renderer alone. `advance_day` washes
# every tile dry and then re-wets what the rain falls on, and its list was the
# growth pass's list — seeded, growing, plus bare tilled ground — so a crop that
# ripened was set dry and then skipped. The soil under a ripe crop was dry in the
# sim, and no picture could have been drawn otherwise. Both halves are asserted
# here: the flag, and the rule that draws it.
func test_rain_on_ripe_soil() -> void:
	print("\n--- Rain falls on ripe soil too (reported 2026-09-01) ---")

	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(9701)
	world.generate()

	# Her exact case: a crop one day from ripe beside one that is not, and a rainy
	# night over both.
	var ripe_t := Vector2i(5, 10)
	var unripe_t := Vector2i(6, 10)
	world.tiles[ripe_t.y][ripe_t.x] = { "state": "growing", "crop_type": "wheat",
		"growth_stage": 2, "watered_today": true }
	world.tiles[unripe_t.y][unripe_t.x] = { "state": "seeded", "crop_type": "tomato",
		"growth_stage": 0, "watered_today": true }
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)

	var ripe: Dictionary = world.get_tile(ripe_t.x, ripe_t.y)
	var unripe: Dictionary = world.get_tile(unripe_t.x, unripe_t.y)
	_assert(ripe.state == "ready", "the crop ripened overnight (her corn)")
	_assert(unripe.state == "growing", "and the one beside it did not")
	_assert(ripe.watered_today, "the rain wets the ripe crop's soil — it used to skip it")
	_assert(unripe.watered_today, "and the unripe one's, which it always did")
	_assert(Autotile.draws_wet(String(ripe.state), ripe.watered_today),
		"so the ground under ripe corn draws WET on a rainy day")
	_assert(Autotile.draws_wet(String(unripe.state), unripe.watered_today),
		"exactly like the row beside it")

	# A tile that was ALREADY ripe when the rain fell — the case a second rainy
	# night produces, and the one the old list skipped every morning forever.
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)
	var still: Dictionary = world.get_tile(ripe_t.x, ripe_t.y)
	_assert(still.state == "ready" and still.watered_today,
		"and a crop that was ripe before the rain started wakes wet as well")

	# --- and it does nothing at all, which is what makes it safe ---------------
	#
	# Every reader of `watered_today` outside the renderer is gated on
	# seeded/growing, so a wet ripe tile cannot grow, cannot be watered and cannot
	# answer "already watered". Asserted rather than asserted-by-reading, because
	# this flag is saved and replayed and a mechanical side effect would be a
	# determinism bug rather than a cosmetic one.
	var stage_before: int = int(still.growth_stage)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)
	var after: Dictionary = world.get_tile(ripe_t.x, ripe_t.y)
	_assert(int(after.growth_stage) == stage_before,
		"a ripe crop left out in the rain does not keep growing (stage %d)" % stage_before)
	world.water_tile(ripe_t.x, ripe_t.y)
	_assert(after.state == "ready", "and `water_tile` still refuses to touch it")

	# --- Q-52, ruled 2026-09-02: wet ground with nothing in it SHOWS now -------
	# The playtest-night hide is reversed; what answers the 2026-08-30 confusion
	# instead is the soak animation (test_wetness_soaks_in).
	_assert(Autotile.draws_wet("tilled", true),
		"bare tilled ground the rain has marked draws WET (Q-52 ruling, 2026-09-02)")
	_assert(Autotile.draws_wet("seeded", true) and Autotile.draws_wet("growing", true),
		"seeded and growing soil draws wet, as it always has")
	_assert(not Autotile.draws_wet("ready", false) and not Autotile.draws_wet("growing", false),
		"and nothing draws wet on a dry tile under a clear sky")
	_assert(Autotile.draws_wet("tilled", false, true),
		"a sky raining right now wets open soil ahead of the sim's day-turn flag")
	_assert(not Autotile.draws_wet("cleared", true, true),
		"but only soil can look wet — cleared ground never does, rain or flag")
	_assert(Autotile.is_soil("ready"),
		"the soil region already counted `ready`; only the wetness rule had forgotten it")

	gs.free()


# Reported from play 2026-09-01: *"When you go to sleep, the ground re-renders as
# dry BEFORE the fade out. Should wait until screen is black to update."*
#
# The cause is D-8 working correctly: the sleep Action resolves at the tap, so
# `advance_day` has already washed the farm dry while the lit world is still on
# screen. The sky has been held for exactly this reason since T-27
# (`main.gd:_freeze_daylight`); the ground now is too. **The sim is not delayed by
# a frame** — that is asserted below, because a fix that delayed it would be a
# D-8 violation wearing this bug's clothes.
func test_ground_holds_until_black() -> void:
	print("\n--- The ground she fell asleep on, held until the screen is black ---")

	var gs = load("res://systems/game_state.gd").new()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.gs = gs
	SimRng.reseed(9702)
	farm.sim.generate()

	var t := Vector2i(5, 10)
	farm.sim.tiles[t.y][t.x] = { "state": "growing", "crop_type": "wheat",
		"growth_stage": 2, "watered_today": true }

	_assert(not farm.is_tile_look_held(), "a farm nobody is sleeping on holds nothing")
	_assert(farm.tile_look(t.x, t.y).state == "growing",
		"and shows sim truth, which is the whole of its life except one second a day")

	farm.hold_tile_look()
	_assert(farm.is_tile_look_held(), "the sleep tap holds the picture")
	farm.sim.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, gs)

	# The sim moved on the same line the Action landed on (D-8) …
	var live: Dictionary = farm.sim.get_tile(t.x, t.y)
	_assert(live.state == "ready" and not live.watered_today,
		"the sim is already in the new day — the Action was not delayed by a frame (D-8)")
	# … and the picture did not.
	var held: Dictionary = farm.tile_look(t.x, t.y)
	_assert(held.state == "growing" and held.watered_today,
		"but the ground still shows the wet, unripe tile she went to bed looking at")
	_assert(Autotile.draws_wet(String(held.state), held.watered_today),
		"so the soil is still drawn wet through the fade, instead of drying under her")

	# Under the black.
	farm.release_tile_look()
	_assert(not farm.is_tile_look_held(), "and the hold is dropped under the black")
	var thawed: Dictionary = farm.tile_look(t.x, t.y)
	_assert(thawed.state == "ready" and not thawed.watered_today,
		"after which the ground is the morning's, dry and ripe")

	# The snapshot is a copy, not a view: mutating the sim under a hold must not
	# leak through it, or the hold would be decorative.
	farm.hold_tile_look()
	farm.sim.tiles[t.y][t.x]["state"] = "cleared"
	_assert(farm.tile_look(t.x, t.y).state == "ready",
		"the held picture is a copy — the sim moving under it changes nothing on screen")
	farm.release_tile_look()
	_assert(farm.tile_look(t.x, t.y).state == "cleared", "and releasing it catches up in one step")

	farm.free()
	gs.free()


# Q-52, ruled 2026-09-02: wetness *animates in*, so the change reads as caused.
# The sim's flag flips in an instant and stays the only truth (asserted); what
# eases is the picture — farm.gd crossfades the dry and wet soil cells on a
# soak timer. Rain and sprinklers soak slow (~3s), the watering can pours fast
# (~1/3 the duration), both [Playtest] constants. Asserted headless: the timers
# and their bookkeeping are data; only the blend itself needs a viewport.
# Q-50's other half (2026-09-07: "animate the boulder and wood being reduced
# over each impact, to indicate why three hits occur"): the sim clears at the
# tap, so the farm keeps drawing the obstacle, one chip stage smaller per
# landed beat, until the last chop.
func test_clear_chips_the_obstacle() -> void:
	print("\n--- Q-50: a multi-beat clear chips the obstacle down ---")
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm._load_textures()

	var t := Vector2i(4, 4)
	farm.note_clear_performance(t, "clear_rock", 3, 350)
	_assert(farm.chip_region(t) == farm._chip_regions["clear_rock"][1],
		"the first impact has landed, so the rock draws its first chip stage")
	farm._chipping[t]["t0"] -= 350.0
	_assert(farm.chip_region(t) == farm._chip_regions["clear_rock"][2],
		"the second beat shows the second chip")
	farm._chipping[t]["t0"] -= 350.0
	_assert(farm.chip_region(t) == farm._chip_regions["clear_rock"][2],
		"the smallest stage holds through the final beat's wind-up")
	farm._chipping[t]["t0"] -= 350.0
	_assert(farm.chip_region(t) == Rect2() and not farm._chipping.has(t),
		"and the last chop finishes it — the entry erases itself")

	# A one-beat weed never performs: there is nothing to explain.
	farm.note_clear_performance(t, "clear_weed", 1, 350)
	_assert(not farm._chipping.has(t), "a single-chop clear draws no chips")
	farm.free()


func test_wetness_soaks_in() -> void:
	print("\n--- Q-52: wetness soaks in (rain slow, can fast) ---")

	var gs = load("res://systems/game_state.gd").new()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.gs = gs
	SimRng.reseed(9703)
	farm.sim.generate()

	_assert(farm.WET_CAN_MS < farm.WET_RAIN_MS,
		"the can pours faster than the rain soaks (the ruling says ~1/3 the duration)")

	# The watering can: the pour starts at the Action, from dry, at the fast rate.
	var t := Vector2i(5, 10)
	farm.sim.tiles[t.y][t.x] = { "state": "seeded", "crop_type": "wheat",
		"growth_stage": 0, "watered_today": false }
	var r: Dictionary = farm.apply_action({ "verb": "water", "target": t, "actor": "player" }, gs)
	_assert(r.get("ok", false), "the water Action resolves")
	_assert(farm.sim.get_tile(t.x, t.y).watered_today,
		"sim truth is wet the same instant — the soak is presentation only (D-8)")
	_assert(farm._wet_alpha(t.x, t.y) < 0.5,
		"but the picture starts near dry and eases toward it")
	_assert(farm._wetting[t]["ms"] == farm.WET_CAN_MS, "at the can's fast rate")

	# No soak in flight means fully wet: a farm restored from a save, or any
	# renderer that never animates, must not re-pour yesterday's water.
	_assert(farm._wet_alpha(9, 9) == 1.0, "a tile with no soak entry draws fully wet")

	# Freshly tilled ground under rain. Updated 2026-09-07 (reported from play:
	# the soil animated wet, yet the router offered water for it): rain falls
	# all day, so the sim flag is wet the moment the soil is bared. The ruling's
	# presentation half stands — the *picture* still soaks in at the rain's own
	# slow rate rather than snapping.
	gs.weather = "rainy"
	var t2 := Vector2i(6, 10)
	farm.sim.tiles[t2.y][t2.x] = { "state": "cleared", "crop_type": "",
		"growth_stage": 0, "watered_today": false }
	r = farm.apply_action({ "verb": "till", "target": t2, "actor": "player" }, gs)
	_assert(r.get("ok", false), "the till resolves")
	_assert(farm.sim.get_tile(t2.x, t2.y).watered_today,
		"sim truth is wet the moment the soil is bared — rain falls all day")
	_assert(farm._wetting.has(t2) and farm._wetting[t2]["ms"] == farm.WET_RAIN_MS,
		"while the picture starts soaking at the tap, at the rain's slow rate")

	# The same till under a clear sky wets nothing and starts nothing.
	gs.weather = "sunny"
	var t3 := Vector2i(7, 10)
	farm.sim.tiles[t3.y][t3.x] = { "state": "cleared", "crop_type": "",
		"growth_stage": 0, "watered_today": false }
	r = farm.apply_action({ "verb": "till", "target": t3, "actor": "player" }, gs)
	_assert(r.get("ok", false) and not farm._wetting.has(t3),
		"tilling under a clear sky starts no soak")

	# The day turn: rain marks the farm while the look is held (T-27), and the
	# soaks it queues start at the release — the morning's rain is watched
	# falling from its start, not mid-pour.
	var t4 := Vector2i(8, 10)
	farm.sim.tiles[t4.y][t4.x] = { "state": "tilled", "crop_type": "",
		"growth_stage": 0, "watered_today": false }
	farm._wetting.clear()
	farm.hold_tile_look()
	r = farm.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)
	_assert(r.get("ok", false), "the sleep resolves")
	_assert(farm.sim.get_tile(t4.x, t4.y).watered_today,
		"rain marked the bare tilled tile at the turn")
	_assert(farm._wetting.has(t4) and farm._wetting[t4]["t"] < 0.0,
		"its soak is queued but not started while the look is held")
	_assert(farm._wet_alpha(t4.x, t4.y) == 0.0,
		"so it would still draw dry through the fade")
	farm.release_tile_look()
	_assert(farm._wetting[t4]["t"] >= 0.0, "the release under the black starts it")
	_assert(farm._wetting[t4]["ms"] == farm.WET_RAIN_MS, "at the rain's rate")

	# A second rainy morning re-soaks nothing that never dried: the day turn's
	# diff compares against what was already drawn wet.
	farm._wetting.clear()
	r = farm.apply_action({ "verb": "sleep", "actor": "world", "weather": "rainy" }, gs)
	_assert(r.get("ok", false) and not farm._wetting.has(t4),
		"ground that stayed wet through the turn does not animate again")

	farm.free()
	gs.free()


# T-10's introduction highlight, reported from play 2026-09-01: *"When the first
# rock was ready to be hit by pickaxe, it was blocked by a rock nearer the
# entrance of that section. We should ensure the rock that's marked is accessible
# and near the entrance of the section."*
#
# The designer's sentence is the spec, and both halves of it are asserted here:
# the marked obstacle must be one she can stand next to, and of those it must be
# the one nearest the way in.
func test_parcel_introduction_pick() -> void:
	print("\n--- T-10: the marked obstacle is reachable, and nearest the gate ---")

	var gs = load("res://systems/game_state.gd").new()
	var world := SimWorld.new()
	SimRng.reseed(3101)
	world.generate()

	# Open the quarry and retire the earlier introductions, so the rock is the beat
	# under test rather than the meadow's weed.
	var quarry: Dictionary = {}
	for p in WorldLayout.parcels(world.layout):
		if String(p.get("id", "")) == "quarry":
			quarry = p
	_assert(not quarry.is_empty(), "the layout still has a quarry to introduce")
	var gate: Vector2i = quarry.get("gate", Vector2i(-1, -1))
	world.tiles[gate.y][gate.x] = { "state": WorldLayout.GATE_OPEN, "crop_type": "",
		"growth_stage": 0, "watered_today": false }
	gs.clear_counts = { "clear_weed": 1, "clear_log": 1, "clear_tree": 1 }

	# --- on the generated world: the pick is reachable, and it is the nearest ---
	var picked: Array[Vector2i] = TeachingFocus.parcel_introduction(world, gs)
	_assert(picked.size() == 1, "one obstacle is marked, never two (T-10)")
	var mark: Vector2i = picked[0]
	_assert(String(world.get_tile(mark.x, mark.y).state) == "obstacle_rock",
		"and it is a rock, the quarry's one new kind")

	# Ranked independently of the code under test: a flood fill from the gate,
	# whose result is in discovery order, so a tile's index in it is its distance
	# order from the way in.
	var order: Dictionary = {}
	var reach: Array[Vector2i] = Movement.reachable(world, SpeciesDefs.GROUND, gate)
	for i in reach.size():
		order[reach[i]] = i
	var rank := func(t: Vector2i) -> int:
		var best := -1
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = t + d
			if order.has(n) and (best < 0 or int(order[n]) < best):
				best = int(order[n])
		return best
	_assert(rank.call(mark) >= 0,
		"she can stand beside it — the marked rock is clearable from ground she can reach")
	var nearer := 0
	var rocks := 0
	for r in quarry.get("rects", []):
		var rect: Rect2i = r
		for ty in range(rect.position.y, rect.end.y):
			for tx in range(rect.position.x, rect.end.x):
				if String(world.get_tile(tx, ty).state) != "obstacle_rock":
					continue
				rocks += 1
				var rk: int = rank.call(Vector2i(tx, ty))
				if rk >= 0 and rk < rank.call(mark):
					nearer += 1
	_assert(rocks > 1, "the quarry generated more than one rock to choose between (%d)" % rocks)
	_assert(nearer == 0,
		"and no reachable rock is nearer the gate than the marked one (%d nearer)" % nearer)

	# --- the adversarial fixture: a rock behind a rock -------------------------
	#
	# Her exact case, built deliberately: the row-major-first rock is walled in,
	# and the only sensible answer is the one beside the gate. The old rule
	# returned the walled-in one — it scanned the parcel's rectangle and never
	# asked whether she could get there.
	for r in quarry.get("rects", []):
		var rect: Rect2i = r
		for ty in range(rect.position.y, rect.end.y):
			for tx in range(rect.position.x, rect.end.x):
				world.tiles[ty][tx] = { "state": "cleared", "crop_type": "",
					"growth_stage": 0, "watered_today": false }
	var walled := Vector2i(22, 10)         # first in row-major order, and sealed off
	var by_the_gate := Vector2i(23, 14)    # one step in from the gate at (21,14)
	var far := Vector2i(29, 18)            # reachable, but the length of the quarry away
	for t in [walled, by_the_gate, far, Vector2i(23, 10), Vector2i(22, 11)]:
		world.tiles[t.y][t.x] = { "state": "obstacle_rock", "crop_type": "",
			"growth_stage": 0, "watered_today": false }
	var row_major := Vector2i(-1, -1)
	for r in quarry.get("rects", []):
		var rect: Rect2i = r
		for ty in range(rect.position.y, rect.end.y):
			for tx in range(rect.position.x, rect.end.x):
				if row_major.x < 0 and String(world.get_tile(tx, ty).state) == "obstacle_rock":
					row_major = Vector2i(tx, ty)
	_assert(row_major == walled,
		"the fixture's first-in-scan-order rock is the walled-in one, as her session's was")
	var walled_open := 0
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if world.is_walkable(walled.x + d.x, walled.y + d.y):
			walled_open += 1
	_assert(walled_open == 0, "and there is nowhere at all to stand beside it")

	var picked2: Array[Vector2i] = TeachingFocus.parcel_introduction(world, gs)
	_assert(_only(picked2) == by_the_gate,
		"so the beat marks the rock beside the gate instead (%s)" % [_only(picked2)])
	_assert(_only(picked2) != walled, "never the one she cannot reach")
	_assert(_only(picked2) != far, "and never the far one when a nearer one is reachable")

	# Determinism: the same farm gives the same answer, every time it is asked.
	_assert(_only(TeachingFocus.parcel_introduction(world, gs)) == by_the_gate,
		"asked again, the same rock — the pick is a fact about the farm, not a roll")

	gs.free()


# The designer, 2026-09-01: *"We should include sparse rocks and logs in the
# un-blocked sections. Once those items are available, then the player can do a
# superior job clearing that space."*
#
# A worldgen change, so it is tested over a spread of seeds rather than one: the
# scatter must be sparse, deterministic, confined to the parcels that ask for it,
# and incapable of sealing anything off or standing on a beat.


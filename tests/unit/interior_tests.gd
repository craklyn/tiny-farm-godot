# Unit tests for this engineering area.
extends "res://tests/unit/test_area.gd"

func test_world_pages() -> void:
	print("\n--- The world is two pages, and page 0 did not move ---")

	# --- 1. compose() is pure ---------------------------------------------------
	# The composed world is built from DEFAULT and HOME, and building it must not
	# touch either: the tests above generate DEFAULT on its own and the title
	# screen's debug row still generates HOME at its own coordinates.
	_assert(WorldLayout.spawn(WorldLayout.DEFAULT) == Vector2i(2, 2)
			and not WorldLayout.DEFAULT.has("objects"),
		"DEFAULT is untouched by composition — still spawning at (2,2), still no object list")
	_assert(Rect2i(WorldLayout.HOME["parcels"][0]["rects"][0]) == Rect2i(11, 6, 10, 7)
			and WorldLayout.HOME["objects"][0]["ty"] == 7,
		"and HOME is untouched — its room and its bed are where the debug screen expects them")
	_assert(str(WorldLayout.compose()) == str(WorldLayout.WORLD),
		"and composing again produces the same world, because its inputs are constants")

	# --- 2. page 0 is the farm, unmoved ----------------------------------------
	# The strongest thing that can be said for a change that doubles the grid: the
	# same seed lays the same farm, tile for tile, over the whole of page 0.
	SimRng.reseed(20260906)
	var w := SimWorld.new()
	w.generate()
	SimRng.reseed(20260906)
	var farm := SimWorld.new()
	farm.generate(WorldLayout.DEFAULT)
	for ty in SimWorld.PAGE_ROWS:
		for tx in SimWorld.MAP_WIDTH:
			_assert_quiet(String(w.get_tile(tx, ty).get("state", ""))
					== String(farm.get_tile(tx, ty).get("state", "")),
				"(%d,%d) reads %s on the farm and %s in the world"
					% [tx, ty, farm.get_tile(tx, ty).get("state", ""),
						w.get_tile(tx, ty).get("state", "")])
	_flush_quiet("every tile of page 0 is the tile the farm layout lays on its own")
	_assert(String(w.get_tile(0, SimWorld.PAGE_ROWS - 1).get("state", "")) == "border",
		"the farm's bottom row is still its border, not ground that appeared under it")

	# What did change on page 0 is furniture, and only furniture: the cot went
	# indoors and the house it went into arrived.
	var moved: Array[String] = []
	for ty in SimWorld.PAGE_ROWS:
		for tx in SimWorld.MAP_WIDTH:
			if w.objects[ty][tx] != farm.objects[ty][tx]:
				moved.append("%d,%d %s->%s" % [tx, ty, farm.objects[ty][tx], w.objects[ty][tx]])
	_assert(moved.size() == 7, "seven tiles of the farm hold something different: %s" % str(moved))
	_assert(w.objects[4][2] == "" and w.get_object(2, 4) == "",
		"the cot is gone from the yard — she has to go inside to find her bed")
	for t in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(3, 2)]:
		_assert_quiet(w.objects[t.y][t.x] == WorldLayout.HOUSE_WALL, "%s is house" % t)
	_flush_quiet("and a farmhouse stands where it was, five tiles of wall")
	_assert(w.objects[2][2] == WorldLayout.HOUSE_DOOR, "with a door in the middle of them")
	_assert(not w.is_walkable(2, 2) and not w.is_walkable(1, 1),
		"the house is solid — she walks up to the door rather than through the wall")
	_assert(WorldLayout.spawn(w.layout) == Vector2i(2, 4) and w.is_walkable(2, 4),
		"and she wakes on the cot's old tile, which is now free")

	# The stations are still the stations. Written out in the layout (layer 1 does
	# not read layer 2), so this is what stops the two copies drifting apart.
	var pinned := {}
	for obj in SimWorld.OBJECT_POSITIONS:
		if String(obj.type) != "cot":
			pinned[String(obj.type)] = Vector2i(obj.tx, obj.ty)
	for obj in WorldLayout.farm_objects():
		if pinned.has(String(obj.type)):
			_assert_quiet(pinned[String(obj.type)] == Vector2i(obj.tx, obj.ty),
				"%s at %d,%d" % [obj.type, obj.tx, obj.ty])
			pinned.erase(String(obj.type))
	_assert(pinned.is_empty(),
		"every station in SimWorld.OBJECT_POSITIONS but the cot is in the composed farm too")
	_flush_quiet("at exactly the coordinates the sim's own constant gives them")

	# --- 3. page 1 is the home, one page down ----------------------------------
	var room := Rect2i(11, 6 + SimWorld.PAGE_ROWS, 10, 7)
	var floors := 0
	for ty in range(room.position.y, room.end.y):
		for tx in range(room.position.x, room.end.x):
			_assert_quiet(String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.FLOOR,
				"(%d,%d) is floor" % [tx, ty])
			floors += 1
	_flush_quiet("the home's room is laid out on page 1, floor and all (%d)" % floors)
	_assert(String(w.get_tile(13, 25).get("state", "")) == WorldLayout.WINDOW
			and String(w.get_tile(10, 26).get("state", "")) == WorldLayout.WALL,
		"with its windows and its walls, every rect moved by exactly one page")
	_assert(String(w.get_tile(15, 33).get("state", "")) == WorldLayout.GATE_OPEN,
		"and the doorway still cut in the south wall — the object on it kept the hole")
	_assert(w.objects[27][12] == "cot", "the bed is on page 1, at (12,27)")
	_assert(w.objects[33][15] == WorldLayout.HOME_DOORWAY, "and the way out stands in the doorway")

	# --- 4. the dark ------------------------------------------------------------
	var lit := 0
	var dark := 0
	for ty in range(SimWorld.PAGE_ROWS, SimWorld.MAP_HEIGHT):
		for tx in SimWorld.MAP_WIDTH:
			if String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.VOID:
				dark += 1
				_assert_quiet(not w.is_walkable(tx, ty), "(%d,%d) is not walkable" % [tx, ty])
			else:
				lit += 1
	_flush_quiet("no tile of the void can be stood on (%d)" % dark)
	_assert(dark > 0 and lit > 0, "page 1 is a lit room in darkness (%d dark, %d not)" % [dark, lit])
	for tx in SimWorld.MAP_WIDTH:
		_assert_quiet(String(w.get_tile(tx, SimWorld.PAGE_ROWS).get("state", "")) == WorldLayout.VOID,
			"(%d,20) is void" % tx)
	_flush_quiet("and row 20 is a solid line of it, so the two pages never touch")

	# Which is the point: no walker can get from one page to the other on foot.
	var downstairs := 0
	for t in w.reachable_from(WorldLayout.spawn(w.layout)):
		if w.page_of(t) != 0:
			downstairs += 1
	_assert(downstairs == 0, "nothing walkable from the farm reaches page 1 (%d)" % downstairs)
	var upstairs := 0
	for t in w.reachable_from(Vector2i(15, 30)):
		if w.page_of(t) != 1:
			upstairs += 1
	_assert(upstairs == 0, "and nothing walkable from the home reaches page 0 (%d)" % upstairs)
	_assert(w.page_of(Vector2i(2, 4)) == 0 and w.page_of(Vector2i(15, 32)) == 1,
		"which is what `page_of` says: rows 0-19 are the farm, 20-39 are the home")

	# --- 5. nothing can be done to the dark ------------------------------------
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	var void_tile := Vector2i(3, 22)
	_assert(String(w.get_tile(void_tile.x, void_tile.y).get("state", "")) == WorldLayout.VOID,
		"a tile out in the dark is void")
	var before: int = gs.energy
	for verb in ["till", "plant", "water", "harvest", "clear_weed"]:
		var r := w.apply_action({ "verb": verb, "target": void_tile, "seed_type": "wheat",
			"actor": "player" }, gs)
		_assert_quiet(not r.get("ok", false), "%s refused (%s)" % [verb, r.get("reason", "")])
	_flush_quiet("every verb the gateway costs energy for is refused on it")
	_assert(gs.energy == before, "and none of them cost her anything — the guard runs first")
	_assert(not w.placeable_at(void_tile), "nor may a machine be set down in it")

	# --- 6. the same seed makes the same two pages -----------------------------
	SimRng.reseed(4242)
	var one := SimWorld.new()
	one.generate()
	SimRng.reseed(4242)
	var two := SimWorld.new()
	two.generate()
	var gs_one = load("res://systems/game_state.gd").new()
	var gs_two = load("res://systems/game_state.gd").new()
	_assert(SaveGame.capture_canonical(one, gs_one) == SaveGame.capture_canonical(two, gs_two),
		"the same seed generates a byte-identical world, both pages of it")
	gs_one.free()
	gs_two.free()
	gs.free()


# --- Q-92: she puts up a fence -----------------------------------------------
# --- the go-to-bed cue fits what it points at (2026-09-07) -------------------
func test_bed_cue_shape() -> void:
	print("\n--- The dusk cue is the size of the thing it points at ---")
	var bed := Vector2i(12, 27)
	var door := Vector2i(2, 2)
	var on_bed := CotPresentation.cue_rect(bed, 16, false)
	var on_door := CotPresentation.cue_rect(door, 16, true)
	_assert(on_bed.size == Vector2(16, 32),
		"on the cot it is the bed's own two-tile footprint (%s)" % on_bed.size)
	_assert(on_bed.position == Vector2(12 * 16, 26 * 16),
		"starting a tile above it, because a bed lies along two squares (%s)" % on_bed.position)
	# **The bug this exists for.** Outside, the cue lands on the front door, and
	# the bed's footprint painted a bed outline over the doorway and the wall
	# above it — so from the yard the house wore a bed every dusk.
	_assert(on_door.size == Vector2(16, 16),
		"on the door it is one tile, not a bed (%s)" % on_door.size)
	_assert(on_door.position == Vector2(2 * 16, 2 * 16),
		"and it starts on the door itself, with nothing spilled onto the wall above (%s)"
			% on_door.position)
	_assert(CotPresentation.cue_centre(door, 16, true) == Vector2(2 * 16 + 8, 2 * 16 + 8),
		"the lamp hangs in the middle of the doorway")
	_assert(CotPresentation.cue_centre(bed, 16, false) == Vector2(12 * 16 + 8, 27 * 16),
		"and in the middle of the bed, which is the seam between its two squares")


func test_fencing() -> void:
	print("\n--- Fencing: bought in the crate, built on bare ground, taken back up ---")
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(92)
	var w := SimWorld.new()
	w.generate()
	var theirs := Vector2i(-1, -1)
	var hedge := Vector2i(-1, -1)
	for ty in range(0, 20):
		for tx in range(0, 32):
			if String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.FENCE:
				theirs = Vector2i(tx, ty)
			if String(w.get_tile(tx, ty).get("state", "")) == WorldLayout.HEDGE:
				hedge = Vector2i(tx, ty)
			if theirs.x >= 0 and hedge.x >= 0: break
		if theirs.x >= 0 and hedge.x >= 0: break
	_assert(theirs.x >= 0, "the farm has a fence of the world's own (%s)" % theirs)
	_assert(hedge.x >= 0, "and a hedge that still means not yet (%s)" % hedge)
	w.set_actor_pos(SimWorld.ACTOR_PLAYER, theirs + Vector2i(-1, 0))
	var farm = load("res://world/farm.gd").new()
	farm.sim = w
	_assert(gs.is_unlocked("fence") and not gs.fence_purchased,
		"fencing is on the shelf, but she has not bought any")
	_assert(ActionRouter.resolve(farm, gs, theirs, w.actor_pos(SimWorld.ACTOR_PLAYER)).is_empty(),
		"before purchase, tapping the starting fence is refused by the router")
	var untouched: Dictionary = w.apply_action({ "verb": "collect", "target": theirs,
		"actor": "player" }, gs)
	_assert(not untouched.get("ok", false)
		and String(w.get_tile(theirs.x, theirs.y).get("state", "")) == WorldLayout.FENCE,
		"the gateway keeps the starting fence standing before purchase (%s)" % untouched)
	_assert(not gs.buy_machine("fence") and not gs.fence_purchased,
		"a failed purchase cannot unlock the starting fence")

	# Somewhere bare, beside her, and not the yard.
	var here := Vector2i(6, 10)
	w.set_actor_pos(SimWorld.ACTOR_PLAYER, here)
	var spot := here + Vector2i(1, 0)
	w.set_tile_state(spot.x, spot.y, "cleared")
	_assert(w.buildable_at(spot), "bare cleared ground will take a post")

	# --- the crate, and the bundle -------------------------------------------
	gs.gold = 200
	var before_gold: int = gs.gold
	_assert(gs.buy_machine("fence"), "she buys a card of fencing at the seed box")
	_assert(gs.fence_purchased, "her first successful purchase unlocks the starting fence")
	_assert(gs.gold == before_gold - MachineDefs.price_of("fence"), "and pays for it")
	_assert(gs.machines.get("fence", 0) == 10,
		"a card is ten posts — a fence is a run, not an object (%d)" % gs.machines.get("fence", 0))
	_assert(MachineDefs.terrain_of("fence") == WorldLayout.FENCE_BUILT,
		"the crate row says what it lays down, which is what sends it to `build`")
	# **It has to be on the shelf, not merely in the catalogue.** The shop walks
	# `ORDER`, so fencing first shipped with a verb, a state, a refund and every
	# gateway assertion passing — and no way for anyone to buy one. Every row of
	# the table is checked, because the next thing added will make the same
	# mistake in the same place.
	for key in MachineDefs.TYPES.keys():
		_assert(String(key) in MachineDefs.ORDER,
			"%s is on the shop's shelf and not only in its catalogue" % key)

	# --- building -------------------------------------------------------------
	var e0: int = gs.energy
	var put: Dictionary = w.apply_action({ "verb": "build", "target": spot,
		"item": "fence", "actor": "player" }, gs)
	_assert(put.get("ok", false), "one tap puts a post in that square (%s)" % put)
	_assert(String(w.get_tile(spot.x, spot.y).get("state", "")) == WorldLayout.FENCE_BUILT,
		"the square is her fence now")
	_assert(gs.machines.get("fence", 0) == 9, "one post out of the crate")
	_assert(gs.energy == e0 - Tools.get_energy_cost("build"),
		"and it cost a stroke of work, like breaking the ground would have")
	_assert(not w.is_walkable(spot.x, spot.y), "nothing walks through it")
	_assert(Movement.is_barrier(w, spot), "it is a boundary, so a rabbit paths around it")
	_assert(not w.buildable_at(spot), "and a second post cannot go in the same square")

	# --- what it refuses ------------------------------------------------------
	var crop := here + Vector2i(0, 1)
	w.set_tile_state(crop.x, crop.y, "seeded", "wheat")
	var over_crop: Dictionary = w.apply_action({ "verb": "build", "target": crop,
		"item": "fence", "actor": "player" }, gs)
	_assert(not over_crop.get("ok", false)
			and String(over_crop.get("reason", "")) == "cannot_build_here",
		"a growing crop will not take one — building can never destroy her work (%s)" % over_crop)
	_assert(String(w.get_tile(crop.x, crop.y).get("state", "")) == "seeded", "the crop is untouched")
	var under_her: Dictionary = w.apply_action({ "verb": "build", "target": here,
		"item": "fence", "actor": "player" }, gs)
	_assert(not under_her.get("ok", false),
		"nor the square she is standing on — nobody gets walled in where they stand")
	var not_terrain: Dictionary = w.apply_action({ "verb": "build", "target": spot + Vector2i(1, 0),
		"item": "sprinkler", "actor": "player" }, gs)
	_assert(not not_terrain.get("ok", false)
			and String(not_terrain.get("reason", "")) == "not_buildable_item",
		"and a sprinkler is not something you build — that is `place`'s word (%s)" % not_terrain)
	var placed_fence: Dictionary = w.apply_action({ "verb": "place", "target": spot + Vector2i(1, 0),
		"item": "fence", "actor": "player" }, gs)
	_assert(not placed_fence.get("ok", false)
			and String(placed_fence.get("reason", "")) == "not_a_machine",
		"the two verbs cannot both claim the same item (%s)" % placed_fence)

	# --- taking it back, and only hers ---------------------------------------
	var back: Dictionary = w.apply_action({ "verb": "collect", "target": spot,
		"actor": "player" }, gs)
	_assert(back.get("ok", false) and String(back.get("collected", "")) == "fence",
		"tapping her own fence takes it back up (%s)" % back)
	_assert(String(w.get_tile(spot.x, spot.y).get("state", "")) == "cleared",
		"the ground is bare again")
	_assert(gs.machines.get("fence", 0) == 10,
		"and the post is back in the crate — a run she regrets costs her nothing")

	# Even when she has laid or picked up every bought post, the purchase holds.
	gs.machines["fence"] = 0
	w.set_actor_pos(SimWorld.ACTOR_PLAYER, theirs + Vector2i(-1, 0))
	var intent: Dictionary = ActionRouter.resolve(
		farm, gs, theirs, w.actor_pos(SimWorld.ACTOR_PLAYER))
	_assert(intent.get("action", "") == "collect",
		"after purchase, tapping the starting fence resolves to the same collect verb")
	var crate_before := int(gs.machines.get("fence", 0))
	var take: Dictionary = w.apply_action({ "verb": "collect", "target": theirs,
		"actor": "player" }, gs)
	_assert(take.get("ok", false) and take.get("collected", "") == "fence",
		"the purchased starting fence can be taken up (%s)" % take)
	_assert(String(w.get_tile(theirs.x, theirs.y).get("state", "")) == "cleared",
		"and leaves the same bare ground as a taken built fence")
	_assert(int(gs.machines.get("fence", 0)) == crate_before + 1,
		"with its post credited to the crate")

	w.set_actor_pos(SimWorld.ACTOR_PLAYER, hedge + Vector2i(-1, 0))
	_assert(ActionRouter.resolve(farm, gs, hedge, w.actor_pos(SimWorld.ACTOR_PLAYER)).is_empty(),
		"an unlocked fence does not make a hedge answer a tap")
	var clipped: Dictionary = w.apply_action({ "verb": "collect", "target": hedge,
		"actor": "player" }, gs)
	_assert(not clipped.get("ok", false)
		and String(w.get_tile(hedge.x, hedge.y).get("state", "")) == WorldLayout.HEDGE,
		"and the gateway still refuses the hedge (%s)" % clipped)
	farm.free()

	gs.machines["fence"] = 0
	var saved := SaveGame.capture(w, gs)
	var restored_gs = load("res://systems/game_state.gd").new()
	var restored_world := SimWorld.new()
	_assert(SaveGame.restore(saved, restored_world, restored_gs)
		and restored_gs.fence_purchased,
		"purchase survives a save even if her crate was emptied")
	var legacy: Dictionary = saved.duplicate(true)
	legacy["state"].erase("fence_purchased")
	legacy["state"]["machines"]["fence"] = 1
	var legacy_gs = load("res://systems/game_state.gd").new()
	var legacy_world := SimWorld.new()
	_assert(SaveGame.restore(legacy, legacy_world, legacy_gs)
		and legacy_gs.fence_purchased,
		"an old save with bought fencing in the crate retains access")
	w.set_tile_state(spot.x, spot.y, WorldLayout.FENCE_BUILT)
	var legacy_built: Dictionary = SaveGame.capture(w, gs)
	legacy_built["state"].erase("fence_purchased")
	var built_gs = load("res://systems/game_state.gd").new()
	var built_world := SimWorld.new()
	_assert(SaveGame.restore(legacy_built, built_world, built_gs)
		and built_gs.fence_purchased,
		"an old save with all bought posts laid still retains access")
	var legacy_unbought: Dictionary = saved.duplicate(true)
	legacy_unbought["state"].erase("fence_purchased")
	var unbought_gs = load("res://systems/game_state.gd").new()
	var unbought_world := SimWorld.new()
	_assert(SaveGame.restore(legacy_unbought, unbought_world, unbought_gs)
		and not unbought_gs.fence_purchased,
		"an old save without evidence of a purchase keeps the starting fence locked")

	# A take-and-relay session is ordinary collect/build data: no new replay
	# shape, and applying it from the same starting save lands on the same farm.
	var replay_gs = load("res://systems/game_state.gd").new()
	replay_gs.reset()
	replay_gs.gold = 200
	var replay_world := SimWorld.new()
	SimRng.reseed(9202)
	replay_world.generate()
	replay_world.set_actor_pos(SimWorld.ACTOR_PLAYER, theirs + Vector2i(-1, 0))
	var base := SaveGame.capture(replay_world, replay_gs)
	var log := ReplayLog.new()
	log.start_from_save(base, replay_world.gen_seed)
	var buy_action := { "verb": "buy_machine", "item": "fence", "actor": "player" }
	var buy_result: Dictionary = replay_world.apply_action(buy_action, replay_gs)
	_assert(buy_result.get("ok", false) and replay_gs.fence_purchased,
		"the replay fixture buys fencing through the gateway")
	log.record(buy_action, buy_result)
	var take_action := { "verb": "collect", "target": theirs, "actor": "player" }
	var take_result: Dictionary = replay_world.apply_action(take_action, replay_gs)
	_assert(take_result.get("ok", false), "the replay fixture takes the purchased starting post")
	log.record(take_action, take_result)
	var relay_action := { "verb": "build", "target": theirs, "item": "fence", "actor": "player" }
	var relay_result: Dictionary = replay_world.apply_action(relay_action, replay_gs)
	_assert(relay_result.get("ok", false), "and lays that post again")
	log.record(relay_action, relay_result)
	var live := SaveGame.capture_canonical(replay_world, replay_gs)
	var replayed_world := SimWorld.new()
	var replayed_gs = load("res://systems/game_state.gd").new()
	var round_trip := ReplayLog.from_json(log.to_json())
	_assert(round_trip.apply_to(replayed_world, replayed_gs)
		and SaveGame.capture_canonical(replayed_world, replayed_gs) == live,
		"taking and relaying the starting fence round-trips through the replay")


func test_the_door() -> void:
	print("\n--- Going indoors is an Action, and it comes back ---")

	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(606)
	var w := SimWorld.new()
	w.generate()
	var door := Vector2i(2, 2)
	var doorway := Vector2i(15, 33)

	# --- 1. she has to be standing at it ---------------------------------------
	w.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(6, 5))
	var far := w.apply_action({ "verb": "use_door", "target": door, "actor": "player" }, gs)
	_assert(not far.get("ok", false) and String(far.get("reason", "")) == "too_far",
		"a door across the yard is refused — she walks to it, like every special object (%s)" % far)
	_assert(w.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(6, 5), "and she has not moved")

	# --- 2. in ------------------------------------------------------------------
	w.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(2, 3), "up")
	var before_energy: int = gs.energy
	var before_actions: int = gs.actions_today
	var went := w.apply_action({ "verb": "use_door", "target": door, "actor": "player" }, gs)
	_assert(went.get("ok", false) and went.get("dest", Vector2i()) == Vector2i(15, 32),
		"standing under her own door, one tap puts her inside (%s)" % went)
	_assert(String(went.get("face", "")) == "up", "facing into the room she just walked into")
	_assert(w.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(15, 32),
		"and the registry says so — where she is has been sim truth since Q-53")
	_assert(w.page_of(w.actor_pos(SimWorld.ACTOR_PLAYER)) == 1, "she is on the home page")
	_assert(gs.energy == before_energy and gs.actions_today == before_actions,
		"a door costs no energy and does not tick the day's clock (NON_WORK_VERBS)")
	_assert(SimWorld.NON_WORK_VERBS.has("use_door"), "which is stated once, in the table")

	# --- 3. and out again -------------------------------------------------------
	var back := w.apply_action({ "verb": "use_door", "target": doorway, "actor": "player" }, gs)
	_assert(back.get("ok", false) and back.get("dest", Vector2i()) == Vector2i(2, 3)
			and String(back.get("face", "")) == "down",
		"the doorway leads back out, to the tile below the door, facing the yard (%s)" % back)
	_assert(w.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(2, 3), "she is home on the farm")

	# --- 3b. and the machines are told -----------------------------------------
	#
	# **Stepping outside is the farm's starting bell.** A bot stands still while
	# she is indoors and then naps for `IDLE_SECONDS` before looking again, so
	# without this she came out and watched an already-sent machine do nothing for
	# up to half a minute — reported from play, 2026-09-07: "after some delay, it
	# then went out". The door is an Action, so it can tell them, exactly as
	# `activate` does.
	#
	# Asserted through the brain actually thinking rather than through a field:
	# the schedule is a clock event, and `extra.wake` is what a think *writes*, so
	# a wake that has been overwritten is proof the machine looked up.
	BotBrain.deploy(w, "bell_bot", BotBrain.CONFIG_ORDERS, Vector2i(6, 6))
	var parked := w.clock.tick + 100000
	var doze := func():
		w.actor("bell_bot")["extra"]["wake"] = parked
		w._schedule_brain("bell_bot", parked)
	var thought := func() -> bool:
		return int(w.actor("bell_bot")["extra"].get("wake", 0)) != parked

	w.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(2, 3), "up")
	doze.call()
	w.apply_action({ "verb": "use_door", "target": door, "actor": "player" }, gs)
	w.advance_to_tick(w.clock.tick + 20, gs)
	_assert(not thought.call(),
		"walking *in* wakes nothing — the farm's day has not started")

	doze.call()
	w.apply_action({ "verb": "use_door", "target": doorway, "actor": "player" }, gs)
	w.advance_to_tick(w.clock.tick + 20, gs)
	_assert(thought.call(),
		"walking *out* wakes every machine on the spot, rather than leaving it mid-nap")

	# --- 4. what it refuses -----------------------------------------------------
	var nothing := w.apply_action({ "verb": "use_door", "target": Vector2i(5, 5),
		"actor": "player" }, gs)
	_assert(not nothing.get("ok", false) and String(nothing.get("reason", "")) == "no_door_here",
		"a tap on ordinary ground is not a door (%s)" % nothing)
	# **A hen goes through a door too** (P-18, 2026-09-15). This used to refuse
	# everybody but the player, which was right while the only door in the game was
	# her own front door; a coop has one now and the animal it is for has to be able
	# to use it. S-3 read from the other side: `use_door` is a verb the player
	# already had, so nothing here is a capability an animal has and she does not.
	w.set_actor_pos(SimWorld.ACTOR_CHICKEN, Vector2i(2, 3))
	var hen := w.apply_action({ "verb": "use_door", "target": door, "actor": "chicken" }, gs)
	_assert(hen.get("ok", false)
			and w.actor_pos(SimWorld.ACTOR_CHICKEN) == Vector2i(hen.get("dest", Vector2i(-1, -1))),
		"a hen walks through a door as the farmer does, and ends up on the far side (%s)" % hen)
	var nobody := w.apply_action({ "verb": "use_door", "target": door, "actor": "ghost" }, gs)
	_assert(not nobody.get("ok", false) and String(nobody.get("reason", "")) == "no_such_actor",
		"...but somebody who is not in the world does not (%s)" % nobody)

	# **The migration's safety net, from the other side.** A world with no door
	# table is every farm ever saved before today: even with a door object sitting
	# on a tile, the verb has nowhere to send her and says so rather than guessing.
	SimRng.reseed(606)
	var old := SimWorld.new()
	old.generate(WorldLayout.DEFAULT)
	old.set_object(5, 5, WorldLayout.HOUSE_DOOR)
	old.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(5, 6))
	var nowhere := old.apply_action({ "verb": "use_door", "target": Vector2i(5, 5),
		"actor": "player" }, gs)
	_assert(not nowhere.get("ok", false)
			and String(nowhere.get("reason", "")) == "door_leads_nowhere",
		"a door in a world that has no doors leads nowhere, and is refused (%s)" % nowhere)

	# --- 5. the way to bed ------------------------------------------------------
	# One resolver, so the dusk glow, the bedtime nudge and the HUD's bed button
	# cannot come to disagree about where she is being sent.
	_assert(w.way_to_bed(Vector2i(6, 5)) == door,
		"outside at dusk, the way to bed is the front door")
	_assert(w.way_to_bed(Vector2i(15, 32)) == Vector2i(12, 27),
		"and once she is inside, it is the bed itself")
	SimRng.reseed(606)
	var bedless := SimWorld.new()
	bedless.generate(WorldLayout.DEFAULT)
	bedless.set_object(2, 4, "")
	_assert(bedless.way_to_bed(Vector2i(5, 5)) == Vector2i(-1, -1),
		"a world with no bed in it says so, rather than pointing at the origin")
	_assert(old.way_to_bed(Vector2i(9, 9)) == Vector2i(2, 4),
		"and on an old farm, where the cot is still out in the yard, it is the cot")
	gs.free()

	# --- 6. recorded, and replayed ---------------------------------------------
	# A transition is an ordinary logged Action, which is the whole reason it is a
	# verb: a session in which she went indoors, slept and came out replays to the
	# same world — her position included.
	var s := LiveSession.new(8080)
	s.walk("begin", "up", Vector2i(2, 3))
	_assert(s.act({ "verb": "use_door", "target": door, "actor": "player" }).get("ok", false),
		"the session's farmer goes inside")
	s.walk("step", "up", Vector2i(15, 31))
	s.walk("turn", "left", Vector2i(13, 28))
	_assert(s.act({ "verb": "sleep", "actor": "player", "weather": "sunny" }).get("ok", false),
		"sleeps in her own bed")
	s.walk("step", "down", Vector2i(15, 32))
	_assert(s.act({ "verb": "use_door", "target": doorway, "actor": "player" }).get("ok", false),
		"and comes back out in the morning")
	_assert(s.world.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(2, 3), "into her own yard")
	var live := SaveGame.capture_canonical(s.world, s.gs)

	var replayed := SimWorld.new()
	var gs_replay = load("res://systems/game_state.gd").new()
	var rlog := ReplayLog.from_json(s.log.to_json())
	_assert(rlog.apply_to(replayed, gs_replay), "the log replays")
	_assert(rlog.divergence == "", "with nothing recomputed differently (%s)" % rlog.divergence)
	_assert(SaveGame.capture_canonical(replayed, gs_replay) == live,
		"onto the same farm, the same home and the same farmer standing in her own yard")
	_assert(replayed.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(2, 3),
		"a door transit reproduces exactly, because it is an Action and not a teleport")
	gs_replay.free()
	s.done()



func test_the_window() -> void:
	print("\n--- A window is for looking out of, and looking is not a verb (P-16) ---")

	# --- 1. the composed world has the two windows where HOME cut them ---------
	SimRng.reseed(707)
	var w := SimWorld.new()
	w.generate()
	var glass := [Vector2i(13, 25), Vector2i(14, 25), Vector2i(17, 25), Vector2i(18, 25)]
	var cut := 0
	var solid := 0
	for g in glass:
		if String(w.get_tile(g.x, g.y).get("state", "")) == WorldLayout.WINDOW:
			cut += 1
		if not w.is_walkable(g.x, g.y):
			solid += 1
	_assert(cut == 4, "the home's north wall has two two-tile windows, one page down (%d of 4)" % cut)
	_assert(solid == 4, "and glass is as solid as the wall around it — she stands at the sill (%d of 4)" % solid)
	_assert(String(w.get_tile(13, 26).get("state", "")) == WorldLayout.FLOOR,
		"with floor under each window to stand on")

	# --- 2. the router reads a tap on the glass as a look --------------------
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
	t.tiles[5][5]["state"] = WorldLayout.WINDOW
	GameState.energy = Tools.DAY_UNITS

	var far = ActionRouter.resolve(t, GameState, Vector2i(5, 5), Vector2i(20, 15))
	_assert(far.get("action", "") == "look_out_window",
		"a tap on the glass is a look out of it (%s)" % str(far))
	_assert(far.get("walk_to", false), "from across the room — she walks up to the sill first")
	_assert(far.get("tool_idx", -1) == 0, "with her hands, not a tool")
	var near = ActionRouter.resolve(t, GameState, Vector2i(5, 5), Vector2i(5, 6))
	_assert(near.get("action", "") == "look_out_window", "and standing under it, the same look")
	var swiped = ActionRouter.resolve(t, GameState, Vector2i(5, 5), Vector2i(5, 6), true, -1)
	_assert(swiped.is_empty(), "a swipe over the glass is not a look — a row-chain never opens a screen")
	t.tiles[5][6]["state"] = WorldLayout.WALL
	var wall_tap = ActionRouter.resolve(t, GameState, Vector2i(6, 5), Vector2i(6, 6))
	_assert(wall_tap.is_empty(), "the wall beside it is still just a wall")

	# --- 3. the sim does not know the word -------------------------------------
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	w.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(13, 26), "up")
	var looked := w.apply_action({ "verb": "look_out_window", "target": Vector2i(13, 25), "actor": "player" }, gs)
	_assert(not looked.get("ok", false) and String(looked.get("reason", "")) == "unknown_verb",
		"handed to the gateway, a look is refused as no verb at all — so it can never enter a replay (%s)" % str(looked))
	_assert(not SimWorld.NON_WORK_VERBS.has("look_out_window"),
		"and it is not in the verb tables either — it is a screen, not a free verb")

func test_save_v3_migration() -> void:
	# The recon's first finding: `restore` checks a save's grid against the world's
	# height exactly, so a world that grows a page breaks every save on disk unless
	# the save is grown first. v3 is that padding — twenty rows of void, which is
	# the honest picture of a farm from before there was anywhere else to be.
	print("\n--- A farm saved before the door still loads, and still plays ---")

	GameState.reset()
	SimRng.reseed(1907)
	var world := SimWorld.new()
	world.generate(WorldLayout.DEFAULT)
	world.apply_action({ "verb": "till", "target": Vector2i(5, 9), "actor": "player" }, GameState)
	world.apply_action({ "verb": "plant", "target": Vector2i(5, 9), "seed_type": "wheat",
		"actor": "player" }, GameState)
	GameState.gold = 87

	# A genuine v2 file: today's capture with the second page cut back off it,
	# which is byte for byte what every build before this one wrote.
	var v2 = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	v2["version"] = 2
	v2["world"]["tiles"] = (v2["world"]["tiles"] as Array).slice(0, SaveGame.LEGACY_MAP_HEIGHT)
	v2["world"]["objects"] = (v2["world"]["objects"] as Array).slice(0, SaveGame.LEGACY_MAP_HEIGHT)

	var migrated := SaveGame.migrate(v2)
	_assert(int(migrated.get("version", 0)) == SaveGame.VERSION,
		"a v2 save walks the whole chain to the current version (%d)"
			% int(migrated.get("version", 0)))
	_assert((v2["world"]["tiles"] as Array).size() == SaveGame.LEGACY_MAP_HEIGHT,
		"and the caller's own dictionary is left alone — migrate copies, it does not rewrite")
	var rows: Array = migrated["world"]["tiles"]
	_assert(rows.size() == SimWorld.MAP_HEIGHT, "the grid is a two-page grid now (%d)" % rows.size())
	var padded := 0
	for ty in range(SaveGame.LEGACY_MAP_HEIGHT, SimWorld.MAP_HEIGHT):
		for tx in SimWorld.MAP_WIDTH:
			_assert_quiet(String(rows[ty][tx].get("state", "")) == WorldLayout.VOID,
				"(%d,%d) padded with void" % [tx, ty])
			_assert_quiet(String(migrated["world"]["objects"][ty][tx]) == "",
				"(%d,%d) padded with nothing on it" % [tx, ty])
			padded += 1
	_flush_quiet("padded with a page of darkness and nothing else (%d tiles)" % padded)
	_assert(str(rows[9]) == str(v2["world"]["tiles"][9]),
		"and her farm is untouched — no regeneration, no house built under her")

	# --- it restores, and it plays ---------------------------------------------
	var back := SimWorld.new()
	var gs_back = load("res://systems/game_state.gd").new()
	_assert(SaveGame.restore(v2, back, gs_back), "a v2 save restores into the two-page world")
	_assert(gs_back.gold == 87 and String(back.get_tile(5, 9).get("state", "")) == "seeded",
		"with her gold and her planted row exactly as she left them")
	_assert(back.objects[4][2] == "cot",
		"her cot is still out in the yard, where the build that saved it put it")
	_assert(back.is_walkable(5, 8) and not back.is_walkable(2, 4)
			and not back.is_walkable(5, SimWorld.PAGE_ROWS + 2),
		"the farm is walkable, the cot is not, and the page below is dark")
	_assert(back.apply_action({ "verb": "water", "target": Vector2i(5, 9), "actor": "player" },
			gs_back).get("ok", false),
		"and she can go on farming it")

	# The door she does not have refuses politely, which is the whole reason the
	# verb looks its destination up rather than assuming one.
	back.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(2, 3))
	var no_door := back.apply_action({ "verb": "use_door", "target": Vector2i(2, 2),
		"actor": "player" }, gs_back)
	_assert(not no_door.get("ok", false) and String(no_door.get("reason", "")) == "no_door_here",
		"there is no door on an old farm, so `use_door` refuses (%s)" % no_door)
	_assert(back.way_to_bed(Vector2i(6, 6)) == Vector2i(2, 4),
		"and the way to bed is the cot in the yard, as it always was")

	# A save that is short for a reason other than its age is still refused: the
	# padding is keyed to the exact old height, so a truncated file cannot sneak in.
	var truncated = JSON.parse_string(JSON.stringify(v2))
	truncated["world"]["tiles"] = (truncated["world"]["tiles"] as Array).slice(0, 12)
	_assert(not SaveGame.restore(truncated, SimWorld.new(), gs_back),
		"a truncated save is still refused, rather than padded into a plausible one")
	gs_back.free()


# --- The robot stall (CEO, 2026-09-06) ----------------------------------------
#
# *"A robot stall holds two robots. The player buys a robot, leaves it in the
# stall, teaches it, and after teaching it works productively growing crops."*
#
# The mark-1 already walked a taught round; what it did not have was anywhere to
# live. This is the shed that gives it one, and the three things that follow from
# an address: a robot may be **parked** in a bay, it comes **home** at the end of
# its round, and it goes out again **the next morning without being told**. That
# last one is the whole value of the 80 gold — a machine that has to be sent out
# by hand every day is a chore with a sprite.
# --- A stall's floor is not ground to work (2026-09-25) ------------------------
#
# From play (playtests/2026-09-25_113814): a Mark III parked in its stall picked
# `till` on its own bay, and the gateway refused it, because a building's floor
# wins over the soil under it (`SimWorld.is_structure_floor`). The robot's scan and
# her tap both judged the square by the tool table alone, so both offered a verb
# the gateway would never take. Both now ask the gateway's question first — and
# this pins that the two still agree with each other and with the gateway.
func test_stall_floor_is_not_ground() -> void:
	print("\n--- A stall's floor is not ground to work, for the robot or for her tap (2026-09-25) Tests ---")

	# --- the Mark III, parked in its stall on bare soil ------------------------
	var s := _mk3_yard(2509)
	var stall := Vector2i(20, 13)
	var bay := stall + Vector2i(1, 0)
	_assert(s.world.placeable_at(stall, "stall"), "the yard has room for a stall at %s" % stall)
	s.act({ "verb": "buy_machine", "item": "stall", "actor": "player" })
	_assert(s.act({ "verb": "place", "target": stall, "item": "stall",
			"actor": "player" }).get("ok", false), "she puts a stall down on cleared soil")
	# Everything the robot can see is ground a hoe cannot open, except its own
	# two bays (still `cleared` underneath) and one square of open soil two steps
	# away — so the nearest "tillable" square by the tool table alone is the one
	# it is standing on, and the only square the gateway would take is the far one.
	var open_soil := stall + Vector2i(0, -2)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var t := stall + Vector2i(dx, dy)
			if t != stall and t != bay and t != open_soil:
				s.world.set_tile_state(t.x, t.y, "tilled")
	_assert(String(s.world.get_tile(stall.x, stall.y).get("state", "")) == "cleared"
			and String(s.world.get_tile(bay.x, bay.y).get("state", "")) == "cleared",
		"both bays stand on cleared soil, which is the case the play session found")
	var bot := _mk3_place(s, stall)
	_assert(bot != "" and s.world.actor_pos(bot) == stall, "a Mark III is parked in the left bay")
	var extra: Dictionary = s.world.actor(bot)["extra"]
	_mk3_make_certain(extra, BotBrain.LEARN_TILL)

	_assert(BotBrain.order_verb(s.world, stall) == "" and BotBrain.order_verb(s.world, bay) == "",
		"the robots' shared answer for a square offers no verb on a stall's floor")
	_assert(BotBrain.order_verb(s.world, open_soil) == "till",
		"...and still offers the hoe on the open soil beside it")

	var on_floor := 0
	var refused_occupied := 0
	var tilled_open := 0
	for t in s.tick(SimClock.RATE * 60):
		if String(t["action"].get("actor", "")) != bot:
			continue
		var at: Vector2i = t["action"].get("target", Vector2i(-1, -1))
		var verb := String(t["action"].get("verb", ""))
		if verb in ["till", "plant", "water", "harvest"] and s.world.is_structure_floor(at):
			on_floor += 1
		if String(t["result"].get("reason", "")) == "occupied":
			refused_occupied += 1
		if verb == "till" and at == open_soil and t["result"].get("ok", false):
			tilled_open += 1
	_assert(on_floor == 0,
		"in its first minute it never asks to work its own stall's floor (%d times)" % on_floor)
	_assert(refused_occupied == 0,
		"so the gateway never has to refuse it as occupied (%d refusals; once a second, 60 in all, before the fix)" % refused_occupied)
	_assert(tilled_open == 1,
		"and the hoe it was certain to swing went into the open soil instead (%d)" % tilled_open)

	# --- her tap on the same floor ---------------------------------------------
	GameState.reset()
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	SimRng.reseed(2509)
	farm.sim.generate()
	GameState.gold = 1000
	var shed := Vector2i(-1, -1)
	for y in range(9, 16):
		for x in range(5, 23):
			if farm.sim.placeable_at(Vector2i(x, y), "stall"):
				shed = Vector2i(x, y)
				break
		if shed.x >= 0:
			break
	_assert(shed.x >= 0, "the generated farm has room for a stall")
	for dy in range(-1, 2):
		for dx in range(-1, 3):
			farm.sim.set_tile_state(shed.x + dx, shed.y + dy, "cleared")
	farm.sim.apply_action({ "verb": "buy_machine", "item": "stall", "actor": "player" }, GameState)
	_assert(farm.sim.apply_action({ "verb": "place", "target": shed, "item": "stall",
			"actor": "player" }, GameState).get("ok", false), "a stall stands on the generated farm")
	var beside := shed + Vector2i(0, 1)
	GameState.selected_seed_type = "wheat"
	GameState.pouch["wheat"] = 5
	GameState.energy = 100
	GameState.watering_can_charges = 5
	_assert(String(ActionRouter.resolve(farm, GameState, beside, beside).get("action", "")) == "till",
		"the cleared square beside the stall still resolves to the hoe")
	for state in ["cleared", "tilled", "seeded", "ready"]:
		farm.sim.set_tile_state(shed.x, shed.y, state, "wheat")
		var r: Dictionary = ActionRouter.resolve(farm, GameState, shed, beside)
		var gate: Dictionary = farm.sim.apply_action({ "verb": { "cleared": "till",
				"tilled": "plant", "seeded": "water", "ready": "harvest" }[state],
				"target": shed, "seed_type": "wheat", "actor": "player" }, GameState)
		_assert(r.is_empty() and String(gate.get("reason", "")) == "occupied",
			"a tap on %s soil under a stall's floor offers nothing, as the gateway would refuse it" % state)
	_assert(not ActionRouter.is_workable(farm, shed),
		"so she walks onto the floor rather than stopping beside it to work it")
	farm.sim.set_tile_state(shed.x, shed.y, "cleared")
	GameState.energy = 0
	_assert(ActionRouter.blocked_reason(farm, GameState, shed) == "",
		"and an empty meter is no reason to wobble at a floor no tool may touch")
	GameState.energy = 100
	GameState.machines["bot_mk1"] = 1
	GameState.selected_seed_type = "bot_mk1"
	_assert(String(ActionRouter.resolve(farm, GameState, shed, beside).get("action", "")) == "place",
		"holding a robot, the same tap still stands it in the bay")
	farm.free()
	GameState.reset()


func test_robot_stall() -> void:
	print("\n--- The robot stall: a robot with an address (CEO, 2026-09-06) Tests ---")

	# --- the catalogue row -----------------------------------------------------
	_assert(MachineDefs.has(SimWorld.STALL_ITEM), "the shop sells a stall")
	_assert(MachineDefs.price_of("stall") == 80,
		"at 80 gold, because an empty shed waters nothing")
	_assert(not MachineDefs.spawns_actor("stall") and MachineDefs.species_of("stall") == "",
		"and it names no species: a shed is an object on the grid, never an actor")
	_assert(MachineDefs.key_for_species("") == "",
		"...which must not make it the answer for an actor with no species of its own")
	_assert(MachineDefs.ORDER.find("stall") > MachineDefs.ORDER.find("sprinkler")
			and MachineDefs.ORDER.find("stall") < MachineDefs.ORDER.find("bot_mk1"),
		"the shop lists it between the sprinkler and the robots it holds")

	GameState.reset()
	SimRng.reseed(4242)
	var world := SimWorld.new()
	world.generate()
	GameState.gold = 1000

	# Somewhere with room for a two-tile shed and a crop row under it.
	var stall := Vector2i(-1, -1)
	for y in range(9, 16):
		for x in range(5, 23):
			if world.placeable_at(Vector2i(x, y), "stall"):
				stall = Vector2i(x, y)
				break
		if stall.x >= 0:
			break
	_assert(stall.x >= 0, "the generated farm has two free squares side by side")
	var bay := stall + Vector2i(1, 0)

	# A clean patch to work in: the ground the shed stands on and the row the
	# robot is going to water, staged rather than hoped for.
	for dy in range(-1, 4):
		for dx in range(-2, 6):
			var t: Vector2i = stall + Vector2i(dx, dy)
			world.set_tile_state(t.x, t.y, "cleared")
	var row: Array[Vector2i] = []
	for i in 3:
		var t := Vector2i(stall.x + i, stall.y + 2)
		world.set_tile_state(t.x, t.y, "seeded", "wheat")
		row.append(t)

	# --- buying and putting it down --------------------------------------------
	var purse: int = GameState.gold
	_assert(world.apply_action({ "verb": "buy_machine", "item": "stall",
			"actor": "player" }, GameState).get("ok", false),
		"she buys one from the shop, the way she buys everything (P-12)")
	_assert(GameState.gold == purse - 80 and GameState.machines.get("stall", 0) == 1,
		"it costs its price and goes into the crate")
	_assert(GameState.holding_machine() and GameState.selected_seed_type == "stall",
		"and lands in her hands, so the next tap is the placement")

	var energy_before: int = GameState.energy
	var built: Dictionary = world.apply_action({ "verb": "place", "target": stall,
		"item": "stall", "actor": "player" }, GameState)
	_assert(built.get("ok", false), "she puts it down")
	_assert(world.get_object(stall.x, stall.y) == WorldLayout.ROBOT_STALL
			and world.get_object(bay.x, bay.y) == WorldLayout.ROBOT_STALL_SLOT,
		"two tiles of shed go onto the grid, left bay and right (%s, %s)" % [stall, bay])
	_assert(built.get("slot", Vector2i(-1, -1)) == bay,
		"and the result says where the second bay landed, for whatever draws it")
	_assert(GameState.energy == energy_before - Tools.get_energy_cost("place"),
		"carrying it out cost her exactly what setting a machine down costs")
	_assert(GameState.machines.get("stall", 0) == 0, "the crate is empty again")
	_assert(world.machine_at(stall) == "" and world.machine_at(bay) == "",
		"and nothing was spawned: a stall is not an actor and never thinks")

	# --- what a bay is, and is not ---------------------------------------------
	_assert(world.is_stall_tile(stall) and world.is_stall_tile(bay),
		"both tiles answer as stall")
	_assert(world.is_walkable(stall.x, stall.y) and world.is_walkable(bay.x, bay.y),
		"and both are walkable — an open-fronted shed is a thing you stand in")
	for verb in ["till", "plant", "water", "harvest", "clear_weed"]:
		var refused: Dictionary = world.apply_action({ "verb": verb, "target": stall,
			"seed_type": "wheat", "actor": "player" }, GameState)
		_assert(not refused.get("ok", false) and String(refused.get("reason", "")) == "occupied",
			"...and there is no farming the floor of a shed: %s is refused" % verb)
	_assert(not world.teachable_at(stall) and not world.teachable_at(bay),
		"nor may a robot be taught to water its own garage")
	_assert(not world.apply_action({ "verb": "collect", "target": stall,
			"actor": "player" }, GameState).get("ok", false),
		"and v1 cannot pick it back up — deliberately weak first version (P-13)")

	# --- where a stall may not go ----------------------------------------------
	GameState.machines["stall"] = 3
	_assert(not world.placeable_at(stall, "stall"),
		"a second shed will not go on top of the first")
	var edge := Vector2i(SimWorld.MAP_WIDTH - 2, stall.y)
	_assert(not world.placeable_at(edge, "stall"),
		"nor against the right-hand wall, where its second bay would be off the map")
	var edge_try: Dictionary = world.apply_action({ "verb": "place", "target": edge,
		"item": "stall", "actor": "player" }, GameState)
	_assert(not edge_try.get("ok", false) and String(edge_try.get("reason", "")) == "occupied",
		"the gateway says so rather than building half a shed")
	_assert(world.get_object(edge.x, edge.y) == "",
		"...and writes nothing at all when it refuses")

	var blocked := Vector2i(stall.x, stall.y + 3)
	world.set_tile_state(blocked.x + 1, blocked.y, "obstacle_rock")
	_assert(world.placeable_at(blocked) and not world.placeable_at(blocked, "stall"),
		"a square that would take a sprinkler will not take a stall if its neighbour is a rock")
	world.set_tile_state(blocked.x + 1, blocked.y, "cleared")
	GameState.machines["stall"] = 0

	# --- a robot parks in a bay -------------------------------------------------
	GameState.machines["sprinkler"] = 1
	GameState.selected_seed_type = "sprinkler"
	var wrong_thing: Dictionary = world.apply_action({ "verb": "place", "target": stall,
		"item": "sprinkler", "actor": "player" }, GameState)
	_assert(not wrong_thing.get("ok", false),
		"a bay is for robots: a sprinkler set down in one is refused")
	_assert(not world.placeable_at(stall) and world.placeable_at(stall, "bot_mk1"),
		"...which is what the item in her hand decides, and nothing else about the square")

	GameState.machines["bot_mk1"] = 3
	GameState.selected_seed_type = "bot_mk1"
	var parked: Dictionary = world.apply_action({ "verb": "place", "target": stall,
		"item": "bot_mk1", "actor": "player" }, GameState)
	var mk1: String = String(parked.get("machine", ""))
	_assert(parked.get("ok", false) and mk1 != "", "she stands a robot in the left bay")
	_assert(world.actor(mk1)["extra"].get("home_x", -1) == stall.x
			and world.actor(mk1)["extra"].get("home_y", -1) == stall.y,
		"and it now has an address — the tile it was parked on (%s)" % stall)
	_assert(world.machine_at(stall) == mk1,
		"a tap on the bay finds the robot in it, which is how its menu opens")

	var second_in_bay: Dictionary = world.apply_action({ "verb": "place", "target": stall,
		"item": "bot_mk1", "actor": "player" }, GameState)
	_assert(not second_in_bay.get("ok", false)
			and String(second_in_bay.get("reason", "")) == "occupied",
		"a second robot will not fit in an occupied bay — capacity is spatial")
	var neighbour: Dictionary = world.apply_action({ "verb": "place", "target": bay,
		"item": "bot_mk1", "actor": "player" }, GameState)
	var mk1_b: String = String(neighbour.get("machine", ""))
	_assert(neighbour.get("ok", false) and world.has_actor(mk1) and world.has_actor(mk1_b),
		"but the right-hand bay takes the second one: a stall holds two robots")
	_assert(world.actor(mk1_b)["extra"].get("home_x", -1) == bay.x,
		"and that one's address is its own bay")

	# A robot set down on open ground has no home at all, and behaves exactly as
	# the machine that shipped: sent by hand, stopping wherever it finishes.
	var open_ground := Vector2i(stall.x, stall.y - 1)
	var homeless: Dictionary = world.apply_action({ "verb": "place", "target": open_ground,
		"item": "bot_mk1", "actor": "player" }, GameState)
	var loose: String = String(homeless.get("machine", ""))
	_assert(homeless.get("ok", false) and not world.actor(loose)["extra"].has("home_x"),
		"a robot put down on the grass has no address, and nothing about it changed")

	# --- it comes home ----------------------------------------------------------
	for t in row:
		world.apply_action({ "verb": "teach", "target": t, "machine": mk1, "actor": "player" }, GameState)
		world.get_tile(t.x, t.y).watered_today = false
	_assert(BotBrain.orders_of(world.actor(mk1)["extra"]).size() == row.size(),
		"she teaches the parked robot its round")
	world.apply_action({ "verb": "activate", "target": stall, "actor": "player" }, GameState)
	world.advance_to_tick(world.clock.tick + SimClock.RATE * 240, GameState)

	var watered := 0
	for t in row:
		if world.get_tile(t.x, t.y).get("watered_today", false):
			watered += 1
	_assert(watered == row.size(),
		"it walks out and waters every tile it was shown (%d of %d)" % [watered, row.size()])
	_assert(world.actor_pos(mk1) == stall,
		"and then it goes home and stands in its bay (%s)" % world.actor_pos(mk1))
	_assert(not bool(world.actor(mk1)["extra"].get("sent", false)),
		"the round is over once it is parked, not once the list runs out")

	# --- and it lets itself out in the morning ----------------------------------
	#
	# The point of the shed. Nobody taps anything: the day turns, and a machine
	# with an address, a list and a turn it has not used goes back to work.
	for t in row:
		world.apply_action({ "verb": "teach", "target": t, "machine": mk1_b, "actor": "player" }, GameState)
	world.apply_action({ "verb": "teach", "target": row[0], "machine": loose, "actor": "player" }, GameState)
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)

	_assert(bool(world.actor(mk1)["extra"].get("sent", false))
			and bool(world.actor(mk1)["extra"].get("ran_today", false)),
		"the parked robot is out working the moment the day turns, with no send tap")
	_assert(bool(world.actor(mk1_b)["extra"].get("sent", false)),
		"and so is the one in the other bay — both bays are employed")
	_assert(not bool(world.actor(loose)["extra"].get("sent", false)),
		"the robot on the grass is not: without a stall it still waits to be sent (that is what the 80g buys)")
	_assert(not world.apply_action({ "verb": "activate", "target": stall,
			"actor": "player" }, GameState).get("ok", false),
		"...and the morning used its one turn, so a hand cannot send it twice")

	for t in row:
		_assert(not world.get_tile(t.x, t.y).get("watered_today", false),
			"the morning starts dry (%s)" % t)
	world.advance_to_tick(world.clock.tick + SimClock.RATE * 240, GameState)
	var morning_watered := 0
	for t in row:
		if world.get_tile(t.x, t.y).get("watered_today", false):
			morning_watered += 1
	_assert(morning_watered == row.size(),
		"and the round happens: %d of %d tiles watered without her lifting a finger"
			% [morning_watered, row.size()])
	_assert(world.actor_pos(mk1) == stall and world.actor_pos(mk1_b) == bay,
		"with both robots back in their own bays by the end of it")

	# --- and the arrangement survives being put down ---------------------------
	#
	# The address is the thing that could quietly be lost: it is two ints in the
	# machine's `extra` and two objects on the grid, and if either half failed to
	# save, a reloaded farm would look identical and simply stop working in the
	# morning — the worst kind of break, because nothing about it looks broken.
	var snapshot: Dictionary = SaveGame.capture(world, GameState)
	var reloaded := SimWorld.new()
	_assert(SaveGame.restore(snapshot, reloaded, GameState), "the farm saves and loads")
	_assert(reloaded.get_object(stall.x, stall.y) == WorldLayout.ROBOT_STALL
			and reloaded.is_stall_tile(bay),
		"the shed comes back with it, both bays")
	_assert(int(reloaded.actor(mk1)["extra"].get("home_x", -1)) == stall.x,
		"and so does the robot's address, which is what the morning routine reads")

	# --- and every bit of it replays -------------------------------------------
	#
	# The morning routine is **recomputed, not recorded** (Q-53, the sprinkler's
	# rule): the log holds one `sleep`, and the send that happens inside it has to
	# happen inside the replay's `sleep` too. If it did not, the reproduction would
	# wake up with a robot standing idle in a shed and the canonical states would
	# part company on the spot.
	GameState.reset()
	SimRng.reseed(6363)
	var live := SimWorld.new()
	live.generate()
	GameState.gold = 1000
	live.earn(SimWorld.RUNG_MK1_EARNED)
	var here := Vector2i(-1, -1)
	for y in range(9, 16):
		for x in range(5, 23):
			if live.placeable_at(Vector2i(x, y), "stall"):
				here = Vector2i(x, y)
				break
		if here.x >= 0:
			break
	for dy in range(-1, 4):
		for dx in range(-2, 6):
			var t: Vector2i = here + Vector2i(dx, dy)
			live.set_tile_state(t.x, t.y, "cleared")
	var lesson: Array[Vector2i] = []
	for i in 2:
		var t := Vector2i(here.x + i, here.y + 2)
		live.set_tile_state(t.x, t.y, "seeded", "wheat")
		lesson.append(t)
	# Staged before the base save, because the replay rebuilds the world from it.
	var log := ReplayLog.new()
	var base := SaveGame.capture(live, GameState)
	log.start_from_save(base, 6363)
	SaveGame.resume_stream(base, 6363)
	var script: Array[Dictionary] = [
		{ "verb": "buy_machine", "item": "stall", "actor": "player" },
		{ "verb": "place", "target": here, "item": "stall", "actor": "player" },
		{ "verb": "buy_machine", "item": "bot_mk1", "actor": "player" },
		{ "verb": "place", "target": here, "item": "bot_mk1", "actor": "player" },
		{ "verb": "teach", "target": lesson[0], "machine": "bot_mk1", "actor": "player" },
		{ "verb": "teach", "target": lesson[1], "machine": "bot_mk1", "actor": "player" },
		{ "verb": "sleep", "actor": "world", "weather": "sunny" },
	]
	for act in script:
		var res: Dictionary = live.apply_action(act, GameState)
		_assert(res.get("ok", false), "stall replay step %s resolves" % act.verb)
		log.record(act, res, live.clock.tick)
	_assert(bool(live.actor("bot_mk1")["extra"].get("sent", false)),
		"the recorded session's robot let itself out at the day turn")
	for taken in live.advance_to_tick(live.clock.tick + SimClock.RATE * 200, GameState):
		_record_brain_step(log, taken)
	log.mark_tick(live.clock.tick)
	var live_canonical := SaveGame.capture_canonical(live, GameState)

	var replayed := SimWorld.new()
	log.apply_to(replayed, GameState)
	_assert(log.divergence == "", "the stalled session recomputes cleanly (%s)" % log.divergence)
	_assert(SaveGame.capture_canonical(replayed, GameState) == live_canonical,
		"and a replay lands on the same farm, the same shed and the same robot in it")
	_assert(replayed.get_object(here.x, here.y) == WorldLayout.ROBOT_STALL,
		"with the stall standing where she built it")
	_assert(replayed.actor_pos("bot_mk1") == here,
		"and the robot home in its bay, having done a morning's work nobody recorded")


# The measured version of the CEO's sentence — *"after teaching it works
# productively growing crops"* — and it is deliberately the only test in this file
# that asks whether the farm is **better off** rather than whether a mechanism
# fires. Everything above proves the machine goes out, waters what it was shown
# and comes home; none of it rules out the machine simply doing work the farmer
# would have done anyway, which would be a robot that moves the day around instead
# of adding to it.
#
# The design is a controlled comparison and the fairness is the whole of it. Two
# farms, one seed, the same staged plot. In **both**, the farmer works the
# identical day — the same verbs on the same squares, twenty of them, which is
# exactly the energy a day holds — and one farm additionally has a stall with a
# taught mark-1 in it, whose eight squares her identical day never touches. Both
# clocks advance by the same amount, both farms sleep under the same sky.
#
# The measurement itself lives in `tools/demo_robot_value.gd`, which prints it as
# a table for a human to read. Sharing it is the point: the number in the morning
# report and the number this test gates on are the same number, produced by the
# same code, so neither can quietly drift away from the other.
func test_robot_usefulness() -> void:
	print("\n--- A taught robot makes the farm do more in a day (CEO, 2026-09-06) Tests ---")

	var runs: Dictionary = RobotValue.compare()
	var alone: Dictionary = runs["control"]
	var employed: Dictionary = runs["treatment"]
	var round_size: int = RobotValue.ROBOT_ROW_LEN

	# --- the two days really are the same day ---------------------------------
	#
	# Asserted first, because every number below it is worthless if they are not.
	_assert(int(alone["watered_by_her"]) == int(employed["watered_by_her"]),
		"the farmer waters the same %d squares with a robot as without one"
			% alone["watered_by_her"])
	_assert(int(alone["energy_left"]) == 0 and int(employed["energy_left"]) == 0,
		"and works herself out on both farms — a full day, not a half one (%d / %d left)"
			% [alone["energy_left"], employed["energy_left"]])
	_assert(alone["her_tiles"] == employed["her_tiles"],
		"her own squares end the night in identical states on the two farms")

	# --- (a) more ground is wet by dusk ---------------------------------------
	_assert(int(employed["watered_by_robot"]) == round_size
			and int(alone["watered_by_robot"]) == 0,
		"the machine waters its whole round and the farm without one waters none by machine (%d / %d)"
			% [employed["watered_by_robot"], alone["watered_by_robot"]])
	_assert(int(employed["wet_at_dusk"]) > int(alone["wet_at_dusk"]),
		"so more of the farm is wet at dusk with a robot on it (%d vs %d)"
			% [employed["wet_at_dusk"], alone["wet_at_dusk"]])
	_assert(int(employed["wet_at_dusk"]) - int(alone["wet_at_dusk"])
			== int(employed["watered_by_robot"]),
		"and the whole of the difference is the machine's own watering (%d)"
			% (int(employed["wet_at_dusk"]) - int(alone["wet_at_dusk"])))

	# --- (b) and more crops grow for it ---------------------------------------
	#
	# Which is the claim that matters: wet ground is a means, and a growth stage
	# is the farm actually being further along in the morning.
	_assert(int(employed["grew_overnight"]) > int(alone["grew_overnight"]),
		"more crops advance a growth stage overnight on the farm with the robot (%d vs %d)"
			% [employed["grew_overnight"], alone["grew_overnight"]])
	_assert(int(employed["grew_overnight"]) - int(alone["grew_overnight"]) == round_size,
		"one for every square it was taught (%d)"
			% (int(employed["grew_overnight"]) - int(alone["grew_overnight"])))

	# --- (c) additive, not a redistribution -----------------------------------
	#
	# The failure this rules out: a machine that "helps" by watering squares she
	# was going to water anyway, leaving the day's total exactly where it was. The
	# taught row is the tell — untouched on one farm, a stage further on on the
	# other, with her own row identical on both.
	var stood_still := 0
	for i in alone["robot_tiles"].size():
		if String(alone["robot_tiles"][i]) != String(employed["robot_tiles"][i]):
			stood_still += 1
	_assert(stood_still == round_size,
		"every one of the %d taught squares is in a different state on the two farms (%d)"
			% [round_size, stood_still])
	_assert(String(alone["robot_tiles"][0]).ends_with(":1")
			and String(employed["robot_tiles"][0]).ends_with(":2"),
		"the row she never reaches stands still without a robot and moves on with one (%s / %s)"
			% [alone["robot_tiles"][0], employed["robot_tiles"][0]])
	_assert(int(employed["gold_spent"]) == 230 and int(alone["gold_spent"]) == 0,
		"and the whole of it cost 230 gold, once (%d)" % employed["gold_spent"])
	_assert(bool(employed["parked_home"]),
		"with the machine back in its bay at the end of it, ready for a morning nobody has to run")


# --- The chicken coop: the first thing she buys because she likes it ----------
#
# Daniel, 2026-09-11: *"Let's add a 2x2 chicken coop object. 25 gold (cheap), just
# cosmetic behavior. In inclement weather, the chicken will huddle in the coop
# instead of wander the yard."*
#
# Three claims, and they are separable, so they are asserted separately: the shelf
# sells a four-cell hut for 25 gold, the hut is a building rather than a machine
# (walk into it, farm nothing in it, it decides nothing and never thinks), and a
# wet morning finds the hen inside it instead of out in the yard.
#
# The last one is the only behaviour in the game that pays for nothing. That is
# what makes it worth a test: a cosmetic feature has no yield to notice when it
# silently stops working, so the only thing standing between "the hen shelters"
# and "the hen used to shelter" is this.
func test_chicken_coop() -> void:
	print("\n--- The chicken coop: the hen comes in out of the rain (2026-09-11) Tests ---")

	# --- the catalogue row -----------------------------------------------------
	_assert(MachineDefs.has(SimWorld.COOP_ITEM), "the shop sells a coop")
	_assert(MachineDefs.price_of("coop") == 25,
		"at 25 gold (%d)" % MachineDefs.price_of("coop"))
	var cheapest := true
	for key in MachineDefs.ORDER:
		if key != "coop" and MachineDefs.price_of(key) <= 25:
			cheapest = false
	_assert(cheapest and MachineDefs.ORDER[0] == "coop",
		"and it is the cheapest thing on the shelf, listed first — the ladder needs a bottom rung")
	_assert(not MachineDefs.spawns_actor("coop") and MachineDefs.species_of("coop") == "",
		"it names no species: a hut is an object on the grid, never an actor")
	_assert(MachineDefs.configs_of("coop").is_empty() and MachineDefs.program_of("coop") == ""
			and MachineDefs.earns_of("coop") == "" and MachineDefs.earned_by("coop") == "",
		"...with nothing to set, nothing to prove and no rung of the ladder to climb")
	_assert(MachineDefs.footprint_of("coop") == Vector2i(2, 2),
		"two squares wide and two deep (%s)" % MachineDefs.footprint_of("coop"))
	_assert(MachineDefs.icon_of("coop") != null,
		"with a picture for the shop card, which is the same picture the yard gets")

	# The block it would stand on: the anchor is the square she taps, and it runs
	# right and back. Pinned because the renderer hangs a 32x48 picture off that
	# corner and a block that ran the other way would be drawn somewhere else.
	var cells := MachineDefs.footprint_cells("coop", Vector2i(10, 10))
	_assert(cells.size() == 4 and cells[0] == Vector2i(10, 10),
		"four cells, the tapped one first (%s)" % [cells])
	_assert(cells.has(Vector2i(11, 10)) and cells.has(Vector2i(10, 9))
			and cells.has(Vector2i(11, 9)),
		"running one square right and one square back, never rotated (P-13)")
	_assert(MachineDefs.footprint_cells("sprinkler", Vector2i(10, 10)).size() == 1,
		"...and a thing that stands on one square still stands on one square")

	GameState.reset()
	SimRng.reseed(9111)
	var world := SimWorld.new()
	world.generate()
	GameState.gold = 1000

	# Room for a two-by-two hut with clear ground around it.
	var spot := Vector2i(-1, -1)
	for y in range(10, 17):
		for x in range(5, 23):
			if world.placeable_at(Vector2i(x, y), "coop"):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "the generated farm has a four-square block free")
	for dy in range(-3, 3):
		for dx in range(-2, 4):
			var t: Vector2i = spot + Vector2i(dx, dy)
			world.set_tile_state(t.x, t.y, "cleared")

	# --- bought, and put down --------------------------------------------------
	var purse: int = GameState.gold
	_assert(world.apply_action({ "verb": "buy_machine", "item": "coop",
			"actor": "player" }, GameState).get("ok", false),
		"she buys one from the shop, the way she buys everything (P-12)")
	_assert(GameState.gold == purse - 25 and GameState.machines.get("coop", 0) == 1,
		"it costs 25 and goes into the crate")

	var energy_before: int = GameState.energy
	var laid: Dictionary = world.apply_action({ "verb": "place", "target": spot,
		"item": "coop", "actor": "player" }, GameState)
	_assert(laid.get("ok", false), "she puts it down")
	_assert(world.get_object(spot.x, spot.y) == WorldLayout.CHICKEN_COOP,
		"the front-left cell carries the object the renderer draws (%s)" % spot)
	var parts := 0
	for cell in MachineDefs.footprint_cells("coop", spot):
		if cell != spot and world.get_object(cell.x, cell.y) == WorldLayout.CHICKEN_COOP_PART:
			parts += 1
	_assert(parts == 3, "and the other three cells are parts, drawn by it (%d)" % parts)
	_assert(GameState.energy == energy_before - Tools.get_energy_cost("place"),
		"carrying it out cost her exactly what setting a machine down costs")
	_assert(GameState.machines.get("coop", 0) == 0, "the crate is empty again")
	_assert(world.machine_at(spot) == "",
		"and nothing was spawned: a coop is not an actor and never thinks")

	# --- what a coop is, and is not --------------------------------------------
	for cell in MachineDefs.footprint_cells("coop", spot):
		_assert(world.is_coop_tile(cell) and world.is_structure_floor(cell),
			"every cell answers as coop, and as a building you stand in (%s)" % cell)
		_assert(world.is_walkable(cell.x, cell.y),
			"and every cell is walkable — a coop the hen cannot step into is a shed with a hen outside it (%s)" % cell)
		for verb in ["till", "plant", "water", "harvest", "clear_weed"]:
			_assert(not world.apply_action({ "verb": verb, "target": cell,
				"seed_type": "wheat", "actor": "player" }, GameState).get("ok", false),
				"...and nothing may be farmed on it (%s on %s)" % [verb, cell])
		_assert(not world.buildable_at(cell), "nor fenced through (%s)" % cell)
		_assert(not world.teachable_at(cell),
			"nor taught to a robot, which could only walk there and fail (%s)" % cell)
	_assert(not world.placeable_at(spot, "coop") and not world.placeable_at(spot, "sprinkler"),
		"and nothing may be set down inside one, coop or machine")
	_assert(not world.is_stall_tile(spot),
		"a coop is not a stall: a robot that went to live in the hen house would be a bug")
	_assert(world.coop_tiles().size() == 4,
		"the farm reports its four coop cells, sorted (%d)" % world.coop_tiles().size())
	_assert(world.coop_perches() == [spot, spot + Vector2i(1, 0)],
		"and its two perches are the front row — the back row is behind the hut's own wall (%s)"
			% [world.coop_perches()])

	# --- and the hut survives being put down -----------------------------------
	#
	# Four cells, three of which draw nothing. If a part failed to save, a reloaded
	# farm would look identical — the anchor draws the whole picture — and would
	# quietly let her till the square the hut is standing on.
	var snapshot: Dictionary = SaveGame.capture(world, GameState)
	var reloaded := SimWorld.new()
	_assert(SaveGame.restore(snapshot, reloaded, GameState), "the farm saves and loads")
	var back := 0
	for cell in MachineDefs.footprint_cells("coop", spot):
		if reloaded.is_coop_tile(cell):
			back += 1
	_assert(back == 4 and reloaded.get_object(spot.x, spot.y) == WorldLayout.CHICKEN_COOP,
		"the hut comes back with all four of its cells (%d)" % back)

	# --- and the hen comes in out of the rain ----------------------------------
	#
	# Two identical farms, one clock, one difference: the weather. The hen is put
	# down well away from the hut on both, given the same seed and the same number
	# of ticks to think in, and where she ends up is the whole claim.
	var start := spot + Vector2i(-2, 2)
	world.spawn_actor("chicken", SpeciesDefs.CHICKEN, start)

	GameState.weather = "sunny"
	SimRng.reseed(515)
	world.advance_ticks(600, GameState)
	var dry_spot := world.actor_pos("chicken")
	_assert(not world.is_coop_tile(dry_spot),
		"on a dry day she potters about the yard and not into the hut (%s)" % dry_spot)

	GameState.weather = "rainy"
	SimRng.reseed(515)
	world.advance_ticks(1800, GameState)
	var wet_spot := world.actor_pos("chicken")
	# **Inside now, not on the doorstep** (P-18, 2026-09-15). Before the hut had an
	# inside she sheltered on its front row, which was the best the design could
	# offer; now she walks to the doorstep, lets herself in, and is standing on the
	# room's own floor.
	_assert(world.room_of_cell(wet_spot) != "",
		"and when it rains she lets herself in and stands on the floor of it (%s)" % wet_spot)
	var wet_room: Dictionary = world.rooms[world.room_of_cell(wet_spot)]
	_assert(wet_spot != Vector2i(wet_room["door"]),
		"she settles away from the coop doorway, where the farmer enters (%s)" % wet_spot)

	# Indoors is not a special perch or a shelter-only idle loop. She uses her
	# ordinary reachable-tile wander within the room, while never choosing the
	# doorway where the farmer arrives.
	var indoor_positions := {}
	var stayed_inside := true
	var kept_door_clear := true
	for i in 12:
		world.advance_ticks(75, GameState)
		var p := world.actor_pos("chicken")
		indoor_positions[p] = true
		if world.room_of_cell(p) == "":
			stayed_inside = false
		if p == Vector2i(wet_room["door"]):
			kept_door_clear = false
	_assert(stayed_inside and indoor_positions.size() > 1,
		"while rain falls she wanders among reachable coop tiles and stays indoors (%s)"
			% [indoor_positions.keys()])
	_assert(kept_door_clear,
		"and her indoor wander leaves the farmer's doorway clear")

	# ...and the sky clearing is what lets her out. Nothing else changes.
	GameState.weather = "sunny"
	world.schedule_all_brains()
	var left := false
	for i in 20:
		world.advance_ticks(150, GameState)
		if world.room_of_cell(world.actor_pos("chicken")) == "" \
				and not world.is_coop_tile(world.actor_pos("chicken")):
			left = true
	_assert(left, "a dry morning is what lets her back out into the yard (%s)"
		% world.actor_pos("chicken"))

	# --- and it is an ornament, not a dependency -------------------------------
	#
	# The failure this rules out: a hen who stands still on a wet day on a farm
	# with no coop on it, because the shelter branch swallowed her wander. A coop
	# is bought for 25 gold by a player who wants one, and every farm without one
	# has to behave exactly as it did before this existed.
	GameState.reset()
	SimRng.reseed(9111)
	var bare := SimWorld.new()
	bare.generate()
	GameState.weather = "rainy"
	bare.spawn_actor("chicken", SpeciesDefs.CHICKEN, start)
	var before := bare.actor_pos("chicken")
	SimRng.reseed(515)
	bare.advance_ticks(900, GameState)
	_assert(bare.coop_tiles().is_empty() and bare.actor_pos("chicken") != before,
		"with no coop on the farm a wet day is an ordinary day and she potters (%s)" % bare.actor_pos("chicken"))


# --- Inside the coop: a building you walk into without leaving the farm -------
#
# P-18, ruled 2026-09-15 after the CEO corrected the reading of his own directive:
# *"one world, one metric, two grids"*. A building's inside is a finer grid nested
# in its own footprint, and going in is a camera zoom.
#
# What the sim owes that design is small and exact, which is the point: the room is
# **ordinary tiles** in a slot on page 2, so `is_walkable` refuses its walls and
# `Movement` walks its floor with nothing new to learn. What makes those tiles an
# *interior* is two numbers recorded beside them — the anchor and the pitch — and
# those are what this test pins, because they are the whole of the idea and the
# only part a renderer or a later flattening depends on.
func test_spiral_tower_interior() -> void:
	print("\n--- Spiral Tower: four cells above a compressed farm ---")
	var spec := MachineDefs.room_of("spiral_tower")
	_assert("spiral_tower" in MachineDefs.ORDER
			and MachineDefs.footprint_of("spiral_tower") == Vector2i(4, 4)
			and spec.get("cells") == Vector2i(2, 2)
			and is_equal_approx(float(spec.get("pitch", 0)), 0.5),
		"tower is four farm tiles wide, with two indoor cells at half pitch")
	var cells := WorldLayout.room_cells(Vector2i(2, 2), true)
	var floor_count := 0
	for row in cells:
		for cell in row:
			if cell == WorldLayout.FLOOR:
				floor_count += 1
	_assert(floor_count == 4, "all four indoor cells are floor; walls consume none")

	GameState.reset()
	SimRng.reseed(9152)
	var world := SimWorld.new()
	world.generate()
	GameState.gold = 1000
	var spot := Vector2i(-1, -1)
	for y in range(10, 18):
		for x in range(5, 23):
			if world.placeable_at(Vector2i(x, y), "spiral_tower"):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "a four-by-four tower can fit on the generated farm")
	if spot.x < 0:
		return
	for dy in range(-4, 2):
		for dx in range(-1, 5):
			world.set_tile_state(spot.x + dx, spot.y + dy, "cleared")
	_assert(world.apply_action({"verb": "buy_machine", "item": "spiral_tower",
		"actor": "player"}, GameState).get("ok", false), "tower can be bought")
	var laid: Dictionary = world.apply_action({"verb": "place", "target": spot,
		"item": "spiral_tower", "actor": "player"}, GameState)
	var id := String(laid.get("room", ""))
	_assert(laid.get("ok", false) and id != "", "placing tower creates its room")
	if id == "":
		return
	var room: Dictionary = world.rooms[id]
	var origin: Vector2i = room["origin"]
	var FarmScript = load("res://world/farm.gd")
	_assert(is_equal_approx(float(room["pitch"]), 0.5)
			and bool(room["edge_walls"]), "tower preserves fractional pitch and edge walls")
	# Every tower doorway is a corner in the real two-by-two room. The room's
	# existing outside exit and building footprint, not new simulated direction
	# data, tell the renderer which wall loses its line.
	var tower_size := Vector2i(2, 2)
	var presentation_exits := {
		"north": { "door": Vector2i(1, 0), "exit": Vector2i(1, -4) },
		"east": { "door": Vector2i(1, 1), "exit": Vector2i(4, -1) },
		"south": { "door": Vector2i(1, 1), "exit": Vector2i(1, 4) },
		"west": { "door": Vector2i(0, 1), "exit": Vector2i(-1, -1) },
	}
	var box := Rect2(Vector2(origin * FarmScript.TILE_SIZE),
		Vector2(tower_size * FarmScript.TILE_SIZE))
	var p := func(x: int, y: int) -> Vector2:
		return Vector2(origin + Vector2i(x, y)) * FarmScript.TILE_SIZE
	# These endpoints are deliberately written as the four 2x2 room edges, not
	# calculated by RoomEdgeStyle. A diagonal south or east fragment therefore
	# cannot pass by merely returning a non-empty set of lines.
	var expected_segments := {
		"north": [{"from": p.call(0, 0), "to": p.call(1, 0)},
			{"from": p.call(2, 0), "to": p.call(2, 2)},
			{"from": p.call(0, 2), "to": p.call(2, 2)},
			{"from": p.call(0, 0), "to": p.call(0, 2)}],
		"east": [{"from": p.call(0, 0), "to": p.call(2, 0)},
			{"from": p.call(2, 0), "to": p.call(2, 1)},
			{"from": p.call(0, 2), "to": p.call(2, 2)},
			{"from": p.call(0, 0), "to": p.call(0, 2)}],
		"south": [{"from": p.call(0, 0), "to": p.call(2, 0)},
			{"from": p.call(2, 0), "to": p.call(2, 2)},
			{"from": p.call(0, 2), "to": p.call(1, 2)},
			{"from": p.call(0, 0), "to": p.call(0, 2)}],
		"west": [{"from": p.call(0, 0), "to": p.call(2, 0)},
			{"from": p.call(2, 0), "to": p.call(2, 2)},
			{"from": p.call(0, 2), "to": p.call(2, 2)},
			{"from": p.call(0, 0), "to": p.call(0, 1)}],
	}
	for edge in presentation_exits:
		var shown: Dictionary = room.duplicate(true)
		var display: Dictionary = presentation_exits[edge]
		var door: Vector2i = origin + display["door"]
		shown["door"] = door
		shown["exit"] = Vector2i(room["anchor"]) + display["exit"]
		var doorway := RoomEdgeStyle.doorway_threshold_rect(door, FarmScript.TILE_SIZE)
		var segments: Array = RoomEdgeStyle.doorway_segments(box, doorway, String(edge))
		var straight := true
		for segment: Dictionary in segments:
			var a: Vector2 = segment["from"]
			var b: Vector2 = segment["to"]
			if a.x != b.x and a.y != b.y:
				straight = false
		_assert(tower_size == Vector2i(2, 2)
				and FarmScript.room_exit_edge(shown) == edge
				and doorway.position == Vector2(door * FarmScript.TILE_SIZE)
				and segments == expected_segments[edge]
				and straight,
			"the two-by-two tower's %s doorway has the exact straight wall segments and threshold" % edge)
		# The shipped stone course, on the same doorway. Its pieces come from a
		# hash, so rather than every rectangle the test holds the course to the
		# geometry written out above: a line one and a half pixels out along each
		# edge's band is covered by stone everywhere except across the doorway
		# cell of the named edge, where its inner fourteen pixels are bare. The
		# two pixels at each corner are left out: there the crossing course's
		# stones wander by a pixel, which is the laid-stone look, not a gap.
		var gap_at := RoomEdgeStyle.gap_along(doorway, String(edge))
		var stone: Array = RoomEdgeStyle.pieces(box, gap_at, 16.0, "stone", String(edge))
		var shaped := stone.size() > 0
		for piece in stone:
			var r: Rect2 = piece[0]
			if r.size.x <= 0.0 or r.size.y <= 0.0 or not box.grow(5.0).encloses(r) \
					or r.intersects(box.grow(-2.0)):
				shaped = false
		var covered := func(pt: Vector2) -> bool:
			for piece in stone:
				if (piece[0] as Rect2).has_point(pt):
					return true
			return false
		# Each edge's centre line and the doorway cell's stretch along it, both in
		# the independently written corner points `p`.
		var lines := {
			"north": [p.call(0, 0) + Vector2(0, -1.5), Vector2(1, 0), p.call(1, 0).x],
			"south": [p.call(0, 2) + Vector2(0, 0.5), Vector2(1, 0), p.call(1, 2).x],
			"west": [p.call(0, 0) + Vector2(-1.5, 0), Vector2(0, 1), p.call(0, 1).y],
			"east": [p.call(2, 0) + Vector2(0.5, 0), Vector2(0, 1), p.call(2, 1).y],
		}
		var walls_whole := true
		var gap_open := true
		for side in lines:
			var start: Vector2 = lines[side][0]
			var along: Vector2 = lines[side][1]
			var cut: float = lines[side][2]
			for i in range(2, 30):
				var pt: Vector2 = start + along * (float(i) + 0.5)
				var at: float = pt.dot(along)
				var in_gap: bool = side == edge and at > cut and at < cut + 16.0
				var in_core: bool = side == edge and at > cut + 1.0 and at < cut + 15.0
				if in_core and covered.call(pt):
					gap_open = false
				if not in_gap and not covered.call(pt):
					walls_whole = false
		_assert(shaped and walls_whole and gap_open,
			"the stone course is cut in the %s edge at the doorway and nowhere else" % edge)
	# Unchanged for the doorway every tower has today: the south course is the
	# same list whether or not the edge is named.
	RoomEdgeStyle._cache_key = ""
	var real_door: Vector2i = room["door"]
	var south_named: Array = RoomEdgeStyle.pieces(box, float(real_door.x * FarmScript.TILE_SIZE),
		16.0, "stone", "south")
	RoomEdgeStyle._cache_key = ""
	var south_default: Array = RoomEdgeStyle.pieces(box, float(real_door.x * FarmScript.TILE_SIZE),
		16.0, "stone")
	_assert(FarmScript.room_exit_edge(room) == "south" and str(south_named) == str(south_default),
		"the placed tower's own exit is the south edge, drawn as the ruled stone course")
	_assert(room["door"] == origin + Vector2i(1, 1)
			and not room.has("door_edge"),
		"the placed tower keeps its original room state")
	for y in 2:
		for x in 2:
			_assert_quiet(world.is_walkable(origin.x + x, origin.y + y),
				"indoor cell should be walkable")
	_flush_quiet("every tower room cell is walkable")
	_assert(not world.is_walkable(origin.x - 1, origin.y)
			and not world.is_walkable(origin.x + 2, origin.y),
		"the surrounding void blocks walking through the edge wall")
	var building := world.room_building_rect(room)
	var offset: Vector2 = FarmScript.room_backdrop_offset(room, building)
	_assert(building.size == Vector2i(4, 4)
			and offset + Vector2(building.position) * 8.0 == Vector2(origin) * 16.0,
		"the live yard maps to the tower at half scale")
	_assert(world.world_pos_of_cell(origin + Vector2i(1, 1))
			== Vector2(building.position + Vector2i(2, 2)),
		"an indoor cell maps to the same farm square shown behind it")
	_assert(world.space_of(origin) == id and world.space_of(building.position) == "farm"
			and world.space_of(origin - Vector2i(1, 0)) == "",
		"tower cells have their own sensing space even when their world positions overlap the farm")
	var entry := world.room_door_at(spot)
	_assert(entry.get("to") == room["door"], "all tower footprint cells lead inside")
	var exit := world.room_door_at(room["door"])
	_assert(exit.get("to") == spot + Vector2i(1, 1),
		"the indoor doorway returns to the tower's front entrance")
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, spot + Vector2i(1, 1))
	var entered: Dictionary = world.apply_action({"verb": "use_door",
		"target": spot + Vector2i(1, 0), "actor": "player"}, GameState)
	_assert(entered.get("ok", false)
			and world.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(room["door"]),
		"the farmer can enter from the tower's front arch")
	var departed: Dictionary = world.apply_action({"verb": "use_door",
		"target": Vector2i(room["door"]), "actor": "player"}, GameState)
	_assert(departed.get("ok", false)
			and world.actor_pos(SimWorld.ACTOR_PLAYER) == spot + Vector2i(1, 1),
		"the farmer can leave through the same doorway")
	var snap: Dictionary = SaveGame.capture(world, GameState)
	var saved_room: Dictionary = snap["world"]["rooms"][id]
	_assert(not saved_room.has("door_edge"),
		"the exit marker adds no doorway direction to the save")
	var restored := SimWorld.new()
	_assert(SaveGame.restore(snap, restored, GameState)
			and is_equal_approx(float(restored.rooms[id]["pitch"]), 0.5)
			and bool(restored.rooms[id]["edge_walls"])
			and not restored.rooms[id].has("door_edge"),
		"the compressed room survives save and reload")


func test_spiral_tower_pick_up() -> void:
	print("\n--- Spiral Tower: picked up like the coop, with what was inside it ---")
	# Taking a building up was written around the coop until 2026-09-25. The tower
	# is the second row with a room, so it proves the rule reads the row: all
	# sixteen squares clear, the room closes, the tower goes back in the crate, and
	# nothing inside is lost (Q-98: picking up is repositioning) — the hen, if she
	# was in there, is left standing outside.
	#
	# Nothing on today's shelf names the tower's room, so a fitting and a machine
	# that do are staged, as `test_room_fittings` stages one for the coop.
	MachineDefs.TYPES["test_lantern"] = { "name": "Test Lantern", "price": 1,
		"species": "", "configs": [], "default_config": "", "unlock_requirement": null,
		"object": "test_lantern", "rooms": ["spiral_tower"], "outdoors": false }
	MachineDefs.TYPES["test_perch"] = { "name": "Test Perch", "price": 1,
		"species": SpeciesDefs.SPRINKLER, "configs": [], "default_config": "",
		"unlock_requirement": null, "rooms": ["spiral_tower"] }
	MachineDefs.ORDER.append("test_lantern")
	MachineDefs.ORDER.append("test_perch")

	GameState.reset()
	SimRng.reseed(9152)   # the farm `test_spiral_tower_interior` finds room on
	var world := SimWorld.new()
	world.generate()
	var spot := Vector2i(-1, -1)
	for y in range(10, 18):
		for x in range(5, 23):
			if world.placeable_at(Vector2i(x, y), "spiral_tower"):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "a four-by-four tower can fit on the generated farm")
	if spot.x < 0:
		MachineDefs.ORDER.erase("test_lantern")
		MachineDefs.ORDER.erase("test_perch")
		MachineDefs.TYPES.erase("test_lantern")
		MachineDefs.TYPES.erase("test_perch")
		return
	GameState.machines["spiral_tower"] = 1
	var laid: Dictionary = world.apply_action({ "verb": "place", "target": spot,
		"item": "spiral_tower", "actor": "player" }, GameState)
	var room_id := String(laid.get("room", ""))
	_assert(laid.get("ok", false) and room_id != "", "a tower with an inside (%s)" % laid)
	var origin: Vector2i = world.rooms[room_id]["origin"]

	# The staging a continued session starts from: stock in the crate, a trained
	# machine's memory boxed, an egg on the floor and the hen indoors.
	GameState.machines["test_lantern"] = 1
	GameState.machines["test_perch"] = 1
	GameState.boxed["test_perch"] = [{ "weights": [0.25, -0.5], "ledger": [7] }]
	var egg_at := origin + Vector2i(0, 1)
	world.set_object(egg_at.x, egg_at.y, "egg")
	if not world.has_actor(SimWorld.ACTOR_CHICKEN):
		world.spawn_actor(SimWorld.ACTOR_CHICKEN, SpeciesDefs.CHICKEN, spot + Vector2i(0, 1))
	world.set_actor_pos(SimWorld.ACTOR_CHICKEN, Vector2i(world.rooms[room_id]["door"]))
	var base_save = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var rlog := ReplayLog.new()
	rlog.start_from_save(base_save)

	var lantern := origin
	var perch := origin + Vector2i(1, 0)
	var put_lantern := _replay_do(world, rlog, { "verb": "place", "target": lantern,
		"item": "test_lantern", "actor": "player" })
	var put_perch := _replay_do(world, rlog, { "verb": "place", "target": perch,
		"item": "test_perch", "actor": "player" })
	_assert(put_lantern.get("ok", false) and put_perch.get("ok", false)
			and world.actor(String(put_perch.get("machine", ""))).get("extra", {}).get("weights", [])
				== [0.25, -0.5],
		"a fitting and a machine that name the tower go in (%s, %s)" % [put_lantern, put_perch])

	# --- a tap on its back corner takes the whole tower up -------------------------
	var egg_before := int(GameState.items.get("egg", 0))
	var back_corner := spot + Vector2i(3, -3)
	var up := _replay_do(world, rlog, { "verb": "collect", "target": back_corner,
		"actor": "player" })
	_assert(up.get("ok", false) and String(up.get("collected", "")) == "spiral_tower"
			and Vector2i(up.get("anchor", Vector2i(-1, -1))) == spot and int(up.get("count", 0)) == 1,
		"a tap on any of its squares takes the tower up, found from its front-left anchor (%s)" % up)
	var came_out: Array = []
	for entry in up.get("contents", []):
		came_out.append([String(entry.item), Vector2i(entry.cell)])
	_assert(came_out == [["test_lantern", lantern], ["test_perch", perch], ["egg", egg_at]],
		"everything inside comes out first, row by row across the floor (%s)" % [came_out])
	_assert(int(GameState.machines["test_lantern"]) == 1 and int(GameState.machines["test_perch"]) == 1
			and int(GameState.items.get("egg", 0)) == egg_before + 1,
		"each as its own item: the fitting and the machine in the crate, the egg in her basket")
	var kept: Array = GameState.boxed.get("test_perch", [])
	_assert(kept.size() == 1 and kept[0].get("weights", []) == [0.25, -0.5]
			and kept[0].get("ledger", []) == [7],
		"and the machine went in with what it knew (Q-98: picking up is repositioning)")
	for cell in MachineDefs.footprint_cells("spiral_tower", spot):
		_assert_quiet(world.get_object(cell.x, cell.y) == "", "tower square %s should clear" % cell)
	_flush_quiet("all sixteen of the tower's squares clear")
	_assert(not world.rooms.has(room_id)
			and String(world.get_tile(origin.x, origin.y).get("state", "")) == WorldLayout.VOID,
		"its room closes, with nothing left in its slot")
	_assert(int(GameState.machines.get("spiral_tower", 0)) == 1, "and the tower is back in the crate")
	_assert(world.actor_pos(SimWorld.ACTOR_CHICKEN) == spot
			and world.space_of(world.actor_pos(SimWorld.ACTOR_CHICKEN)) == "farm",
		"and the hen who was indoors is standing on the grass where it stood (%s)"
			% world.actor_pos(SimWorld.ACTOR_CHICKEN))

	# --- a replay of the session agrees ---------------------------------------------
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var report := SaveGame.replay_report(ReplayLog.from_json(rlog.to_json()), end_save)
	_assert(report["matched"],
		"a replay of the session ends on the same farm and the same crate %s" % report["divergence"])

	# --- and it goes down again as a tower with an empty room -----------------------
	world.set_actor_pos(SimWorld.ACTOR_CHICKEN, spot + Vector2i(0, 1))
	var again: Dictionary = world.apply_action({ "verb": "place", "target": spot,
		"item": "spiral_tower", "actor": "player" }, GameState)
	var again_id := String(again.get("room", ""))
	var bare := again_id != ""
	if bare:
		var o2: Vector2i = world.rooms[again_id]["origin"]
		for y in 2:
			for x in 2:
				var c := o2 + Vector2i(x, y)
				if world.get_object(c.x, c.y) not in ["", WorldLayout.ROOM_DOORWAY] \
						or world.machine_at(c) != "":
					bare = false
	_assert(again.get("ok", false) and bare
			and int(GameState.machines.get("spiral_tower", 0)) == 0,
		"set down again, it is a tower with a bare room (%s)" % again)

	MachineDefs.ORDER.erase("test_lantern")
	MachineDefs.ORDER.erase("test_perch")
	MachineDefs.TYPES.erase("test_lantern")
	MachineDefs.TYPES.erase("test_perch")
	GameState.reset()


func test_building_that_will_not_fit() -> void:
	print("\n--- A building that will not fit is refused, never tilled, and shows its block ---")
	# From play on the tablet, 2026-10-09: "I am having trouble placing the tower.
	# When I try, it just tills the ground." Holding a building on ground it would
	# not fit on fell through to the hoe. The tap now goes to the gateway as the
	# `place` it was meant to be, the gateway refuses it, and the farm draws the
	# building's whole block with the squares in the way marked.
	GameState.reset()
	SimRng.reseed(9152)   # the farm `test_spiral_tower_interior` finds room on
	var farm = load("res://world/farm.gd").new()
	farm.generate_on_ready = false
	farm.sim.generate()
	var world: SimWorld = farm.sim
	var spot := Vector2i(-1, -1)
	for y in range(10, 18):
		for x in range(5, 23):
			if world.placeable_at(Vector2i(x, y), "spiral_tower"):
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "a four-by-four tower can fit on the generated farm")
	if spot.x < 0:
		farm.free()
		return
	world.set_tile_state(spot.x, spot.y, "cleared")
	_assert(world.placeable_at(spot, "spiral_tower") and world.footprint_blockers(spot, "spiral_tower").is_empty(),
		"where the tower fits, nothing is in the way")

	# One weed in the block's far corner: the tower no longer fits, and that weed
	# is the one square to blame.
	var corner := spot + Vector2i(3, -3)
	world.set_tile_state(corner.x, corner.y, "obstacle_weed")
	var blockers := world.footprint_blockers(spot, "spiral_tower")
	_assert(not world.placeable_at(spot, "spiral_tower") and blockers == [corner],
		"a weed in the far corner stops it, and it is the only square named (%s)" % str(blockers))

	GameState.machines["spiral_tower"] = 1
	GameState.selected_seed_type = "spiral_tower"
	GameState.energy = 100
	var beside := spot + Vector2i(-1, 0)
	var near: Dictionary = ActionRouter.resolve(farm, GameState, spot, beside)
	_assert(String(near.get("action", "")) == "place" and not bool(near.get("fits", true))
			and not bool(near.get("walk_to", true)),
		"a tap beside it is an attempt to place, not a till (%s)" % str(near))
	var far: Dictionary = ActionRouter.resolve(farm, GameState, spot, spot + Vector2i(-6, 2))
	_assert(String(far.get("action", "")) == "place" and not bool(far.get("fits", true)),
		"and so is a tap from across the farm, answered at once (%s)" % str(far))
	_assert(ActionRouter.resolve(farm, GameState, spot, beside, true).is_empty(),
		"a drag never places, so a stroke is not a row of buzzes and never a row of tilling")
	var weed_tap: Dictionary = ActionRouter.resolve(farm, GameState, corner, corner + Vector2i(0, 1))
	_assert(String(weed_tap.get("action", "")) == "clear_weed",
		"a tap on the weed itself still pulls it: the tower in her hands is not a mode (%s)" % str(weed_tap))

	var refused: Dictionary = farm.apply_action({ "verb": "place", "target": spot,
		"item": "spiral_tower", "actor": "player" }, GameState)
	_assert(not refused.get("ok", true) and String(refused.get("reason", "")) == "occupied",
		"the gateway refuses it as occupied (%s)" % str(refused))
	_assert(String(world.get_tile(spot.x, spot.y).get("state", "")) == "cleared"
			and world.get_object(spot.x, spot.y) == ""
			and int(GameState.machines.get("spiral_tower", 0)) == 1,
		"and nothing changed: the square is not tilled and the tower is still in her hands")
	var shown: Dictionary = farm.footprint_refusal()
	_assert(shown.get("anchor", Vector2i(-1, -1)) == spot and Array(shown.get("cells", [])).size() == 16,
		"the farm shows the tower's whole four-by-four block at the spot (%s)" % str(shown.get("cells", [])))
	_assert(Dictionary(shown.get("blocked", {})).keys() == [corner],
		"with the weed's square marked as the one in the way")

	# The block hangs off the map at the top: the squares off the edge are in the way.
	var top := Vector2i(spot.x, 1)
	_assert(Vector2i(spot.x, -1) in world.footprint_blockers(top, "spiral_tower"),
		"a tower whose block runs off the top of the map names the squares past the edge")

	# Every building on the shelf, read from its own row: the blockers are empty
	# exactly when it fits, and are always squares of its own block.
	for raw in MachineDefs.ORDER:
		var item := String(raw)
		if MachineDefs.terrain_of(item) != "":
			continue
		var agreed := true
		for y in range(0, 20, 3):
			for x in range(0, 32, 3):
				var t := Vector2i(x, y)
				var b := world.footprint_blockers(t, item)
				var cells := MachineDefs.footprint_cells(item, t)
				if b.is_empty() != world.placeable_at(t, item):
					agreed = false
				for c in b:
					if not c in cells:
						agreed = false
		_assert(agreed, "%s: blockers are empty exactly where it fits, and lie in its own %s block"
			% [item, str(MachineDefs.footprint_of(item))])
	GameState.reset()
	farm.free()


func test_senses_stop_at_space_boundary() -> void:
	print("\n--- Senses stop at the farm/home boundary ---")
	var world := SimWorld.new()
	world.generate()
	var outside := Vector2i(8, WorldLayout.PAGE_ROWS - 1)
	var inside := outside + Vector2i.DOWN
	_assert(world.space_of(outside) == "farm" and world.space_of(inside) == SimWorld.HOME_ROOM_ID,
		"adjacent storage rows belong to different spaces")
	world.set_object(outside.x, outside.y, "scarecrow")
	_assert(world.is_protected_by_scarecrow(outside.x, outside.y)
			and not world.is_protected_by_scarecrow(inside.x, inside.y),
		"a scarecrow on the farm bottom row cannot protect the home top row")
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, outside)
	_assert(world.spook_source_near(inside) == "" and world.spook_source_near(outside) == SimWorld.ACTOR_PLAYER,
		"the nearest frightener has no distance through a page wall")
	world.set_tile_state(inside.x, inside.y, "growing", "tomato")
	var grazer := GrazerBrain.new()
	_assert(grazer._crop_within(world, outside, 5).x < 0
			and grazer._crop_within(world, inside, 5) == inside,
		"a grazer's crop sense reads only its own space")
	world.spawn_actor("edge_sprinkler", SpeciesDefs.SPRINKLER, outside, {"radius": 1})
	var coverage := SprinklerBrain.coverage(world, "edge_sprinkler")
	_assert(outside in coverage and inside not in coverage,
		"sprinkler coverage stops before the home page")
	var blob := Scent.new()
	blob.deposit_blob(world, Scent.TRAIL, outside, 20.0, 0, 1)
	_assert(blob.read(Scent.TRAIL, outside, 0) > 0.0
			and blob.read(Scent.TRAIL, inside, 0) == 0.0,
		"a scent blob does not deposit through the page wall")
	world.spawn_actor("edge_bird", SpeciesDefs.CROW, inside)
	var bot := BotBrain.new()
	var shoo := {"radius": 4.0, "quarry": SpeciesDefs.CLASS_BIRD,
		"home_x": outside.x, "home_y": outside.y}
	_assert(bot._quarry_near(world, "edge_sprinkler", shoo, 0) == ""
			and is_inf(bot._distance_to(world, "edge_bird", outside)),
		"a shoo bot has no distance to a bird in another space")
	world.set_actor_pos("edge_bird", outside)
	_assert(bot._quarry_near(world, "edge_sprinkler", shoo, 0) == "edge_bird",
		"the shoo bot finds the same bird once it enters its space")
	world.spawn_actor("edge_bot", SpeciesDefs.BOT, outside)
	var follow_extra := {"owner": SimWorld.ACTOR_PLAYER, "distance": 2}
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, inside)
	bot._follow(world, "edge_bot", follow_extra, 0)
	_assert(not Movement.has_route(world, "edge_bot"),
		"a follow bot waits when its owner enters another space")


func test_coop_interior() -> void:
	print("\n--- Inside the coop: a nested room and a door to it (P-18, 2026-09-15) Tests ---")

	_assert(MachineDefs.room_of("coop") == { "cells": Vector2i(6, 6), "pitch": 3 },
		"the coop's row says it has an inside, and how big and how fine (%s)"
			% [MachineDefs.room_of("coop")])
	_assert(MachineDefs.room_of("stall").is_empty() and MachineDefs.room_of("sprinkler").is_empty(),
		"...and nothing else does: a shed is solid all the way through")
	_assert(SimWorld.MAP_HEIGHT == WorldLayout.PAGE_ROWS * 3,
		"the world has a third page for rooms to live on (%d)" % SimWorld.MAP_HEIGHT)

	GameState.reset()
	SimRng.reseed(9151)
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
	_assert(spot.x >= 0, "the generated farm has a four-square block free")
	for dy in range(-3, 4):
		for dx in range(-2, 4):
			world.set_tile_state(spot.x + dx, spot.y + dy, "cleared")

	# --- putting the hut down puts a room down ---------------------------------
	world.apply_action({ "verb": "buy_machine", "item": "coop", "actor": "player" }, GameState)
	var laid: Dictionary = world.apply_action({ "verb": "place", "target": spot,
		"item": "coop", "actor": "player" }, GameState)
	var room_id := String(laid.get("room", ""))
	_assert(laid.get("ok", false) and room_id != "",
		"she puts the hut down and its inside goes down with it (%s)" % room_id)
	var room: Dictionary = world.rooms[room_id]
	_assert(Vector2i(room["anchor"]) == spot and int(room["pitch"]) == 3,
		"and it records the two numbers that make it an interior: anchor %s, pitch %d"
			% [room["anchor"], room["pitch"]])
	_assert(world.page_of(Vector2i(room["origin"])) == WorldLayout.ROOMS_PAGE,
		"its tiles are stored on the rooms page, out of the farm's way")

	# **Slots do not touch** (CEO, 2026-09-16). The renderer no longer draws a room
	# that is not hers, so this is not what separates two coops any more — but a wall
	# ring that ever lost a cell would otherwise open into the room next door, and a
	# page that is mostly empty can afford the gap.
	var seen_rects: Array[Rect2i] = []
	for i in WorldLayout.room_slot_count():
		var o := WorldLayout.room_slot_origin(i)
		var rect := Rect2i(o, WorldLayout.ROOM_SLOT)
		_assert_quiet(o.x >= 0 and o.y >= 0
				and o.x + WorldLayout.ROOM_SLOT.x <= SimWorld.MAP_WIDTH
				and o.y + WorldLayout.ROOM_SLOT.y <= SimWorld.MAP_HEIGHT,
			"slot %d runs off the page at %s" % [i, o])
		for other in seen_rects:
			_assert_quiet(not rect.grow(1).intersects(other),
				"slot %d at %s touches another" % [i, o])
		seen_rects.append(rect)
	_flush_quiet("every room slot is on the page and none touches another (%d slots)"
		% WorldLayout.room_slot_count())

	# --- and the room is a room ------------------------------------------------
	var origin: Vector2i = room["origin"]
	var size: Vector2i = room["size"]
	var floor_cells := 0
	var wall_cells := 0
	for y in size.y:
		for x in size.x:
			var c := origin + Vector2i(x, y)
			var edge: bool = x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1
			if edge and c != Vector2i(room["door"]):
				wall_cells += 1
				_assert_quiet(not world.is_walkable(c.x, c.y), "a wall cell at %s is walkable" % c)
			elif not edge:
				floor_cells += 1
				_assert_quiet(world.is_walkable(c.x, c.y), "a floor cell at %s is not walkable" % c)
	_assert(floor_cells == 16,
		"a four-by-four floor, which is the CEO's 'a bit bigger' with the walls paid for (%d)"
			% floor_cells)
	_assert(wall_cells == 19,
		"inside a ring of wall with one square cut out of it (%d)" % wall_cells)
	_assert(world.is_walkable(Vector2i(room["door"]).x, Vector2i(room["door"]).y),
		"and the square cut out is the doorway, which is the one way through")

	# --- the two numbers do what they exist to do ------------------------------
	#
	# This is the claim the whole architecture rests on: an actor standing indoors
	# has a true position on the farm, so a distance to it is an ordinary distance
	# and nothing has to be undefined.
	var inside_centre := origin + size / 2
	var where := world.world_pos_of_cell(inside_centre)
	_assert(where.distance_to(Vector2(spot) + Vector2(1, 1)) < 1.5,
		"a cell in the middle of the room really is in the middle of the hut (%s vs %s)"
			% [where, Vector2(spot)])
	_assert(world.world_pos_of_cell(spot) == Vector2(spot),
		"...and a tile that is not in any room is just where it is")

	# --- the door, both ways ---------------------------------------------------
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, spot + Vector2i(0, 1))
	var went_in: Dictionary = world.apply_action({ "verb": "use_door", "target": spot,
		"actor": "player" }, GameState)
	_assert(went_in.get("ok", false)
			and Vector2i(went_in.get("dest", Vector2i(-1, -1))) == Vector2i(room["door"]),
		"a tap on the hut takes her inside, through the doorway (%s)" % went_in)
	_assert(world.actor_pos(SimWorld.ACTOR_PLAYER) == Vector2i(room["door"]),
		"and she is standing in it")
	var back_out: Dictionary = world.apply_action({ "verb": "use_door",
		"target": Vector2i(room["door"]), "actor": "player" }, GameState)
	_assert(back_out.get("ok", false)
			and world.actor_pos(SimWorld.ACTOR_PLAYER) == spot + Vector2i(0, 1),
		"and a tap on the doorway brings her back out onto her own doorstep (%s)" % back_out)
	var part: Vector2i = spot + Vector2i(1, 0)
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, part + Vector2i(0, 1))
	_assert(world.apply_action({ "verb": "use_door", "target": part,
			"actor": "player" }, GameState).get("ok", false),
		"any square of the hut is its door, because the arch is drawn across its front")

	# --- the room lands inside its own building --------------------------------
	#
	# **Reported from play, 2026-09-16**: "the coop is translated down one tile with
	# respect to the external world — it's on top of the fence, instead of one tile
	# north of the fence." The backdrop draws the farm under a transform built from
	# the room's two numbers, and the transform lined the room's *top-left* up with
	# the building's *front-left*. A footprint runs upward from its anchor, so those
	# are a building's depth apart, and the whole world slid south by one tile.
	#
	# Asserted as arithmetic rather than as a picture, because that is what it is.
	var back_offset: Vector2 = load("res://world/farm.gd").room_backdrop_offset(
		world.rooms[room_id], world.room_building_rect(world.rooms[room_id]))
	var back_pitch := float(room["pitch"])
	var to_screen := func(t: Vector2i) -> Vector2:
		return back_offset + Vector2(t) * 16.0 * back_pitch
	var block := MachineDefs.footprint_cells("coop", spot)
	var top_left := spot
	for cell in block:
		top_left.x = mini(top_left.x, cell.x)
		top_left.y = mini(top_left.y, cell.y)
	_assert(to_screen.call(top_left) == Vector2(origin) * 16.0,
		"the building's top-left corner is drawn exactly where the room begins (%s vs %s)"
			% [to_screen.call(top_left), Vector2(origin) * 16.0])
	# ...and therefore the square below the hut is drawn below the room, not through it.
	var below := float(origin.y + size.y) * 16.0
	_assert(is_equal_approx(to_screen.call(spot + Vector2i(0, 1)).y, below),
		"and the square south of it begins exactly where the room ends (%.1f vs %.1f)"
			% [to_screen.call(spot + Vector2i(0, 1)).y, below])

	# --- a room you can enter is a room you can leave --------------------------
	#
	# **Found in play, 2026-09-16.** The way out was the tile below the hut and
	# nothing else, so a coop put down with its doorstep against a fence was a room
	# that could be entered and not left — the worst bug this feature can have. The
	# exit is worked out when it is asked for now, and the arch's own square is only
	# the first candidate rather than the only one.
	var doorstep: Vector2i = spot + Vector2i(0, 1)
	world.set_tile_state(doorstep.x, doorstep.y, WorldLayout.FENCE_BUILT)
	var side := world.room_exit_for(world.rooms[room_id])
	_assert(side.x >= 0 and world.is_walkable(side.x, side.y) and side != doorstep,
		"fence the doorstep off and the room lets out of a square beside it instead (%s)" % side)
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, Vector2i(room["door"]))
	var squeezed: Dictionary = world.apply_action({ "verb": "use_door",
		"target": Vector2i(room["door"]), "actor": "player" }, GameState)
	_assert(squeezed.get("ok", false)
			and world.actor_pos(SimWorld.ACTOR_PLAYER) == side,
		"and she gets out of it (%s)" % squeezed)

	# ...and if there is nowhere at all to come out, she is not let in. Refusing at
	# the threshold is the only honest place: once she is inside, every answer is bad.
	for cell in MachineDefs.footprint_cells("coop", spot):
		for step in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = cell + step
			if not (n in MachineDefs.footprint_cells("coop", spot)):
				world.set_tile_state(n.x, n.y, WorldLayout.FENCE_BUILT)
	_assert(world.room_exit_for(world.rooms[room_id]).x < 0,
		"wall a hut in on every side and it has no way out")
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, spot + Vector2i(0, 2))
	var barred: Dictionary = world.apply_action({ "verb": "use_door", "target": spot,
		"actor": "player" }, GameState)
	_assert(not barred.get("ok", false),
		"so she is not let in either, rather than let in and trapped (%s)" % barred)
	# Put the ground back for the checks below.
	for cell2 in MachineDefs.footprint_cells("coop", spot):
		for step2 in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n2: Vector2i = cell2 + step2
			if not (n2 in MachineDefs.footprint_cells("coop", spot)):
				world.set_tile_state(n2.x, n2.y, "cleared")

	# --- it survives being saved ----------------------------------------------
	var snap: Dictionary = SaveGame.capture(world, GameState)
	var reloaded := SimWorld.new()
	_assert(SaveGame.restore(snap, reloaded, GameState), "the farm saves and loads")
	_assert(reloaded.rooms.has(room_id)
			and Vector2i(reloaded.rooms[room_id]["anchor"]) == spot
			and int(reloaded.rooms[room_id]["pitch"]) == 3,
		"and the room comes back with both its numbers, or it is a room no renderer can place")
	_assert(reloaded.is_walkable(Vector2i(room["door"]).x, Vector2i(room["door"]).y)
			and not reloaded.is_walkable(origin.x, origin.y),
		"...and its walls are still walls")

	# --- nothing is put down inside a room -------------------------------------
	#
	# **Found in play, 2026-09-16**: a coop placed inside a coop's floor, and picking
	# the outer one up wiped the inner hut's squares and left its room orphaned in a
	# slot — the coop was simply gone. Refused whole rather than answered, which is
	# what P-13's deliberately weak first version is for: what may go in a room is a
	# design question, and this is the line until it is answered.
	var inner := Vector2i(room["origin"]) + Vector2i(1, 1)
	_assert(world.is_walkable(inner.x, inner.y),
		"a room's floor is ordinary walkable ground (%s)" % inner)
	_assert(not world.placeable_at(inner, "coop") and not world.placeable_at(inner, "sprinkler"),
		"...and nothing may be set down on it, hut or machine")
	_assert(not world.placeable_at(Vector2i(WorldLayout.home_room()["origin"]) + Vector2i(2, 2),
			"sprinkler"),
		"which goes for the farmhouse too, because the home is a room")

	# ...and a farm that already got into that state comes out of it. Staged by hand,
	# because the placement above is refused now and that is the point.
	var nested := Vector2i(room["origin"]) + Vector2i(1, 2)
	var nested_room := world.open_room("coop", nested)
	for cell in MachineDefs.footprint_cells("coop", nested):
		world.set_object(cell.x, cell.y, WorldLayout.CHICKEN_COOP if cell == nested
			else WorldLayout.CHICKEN_COOP_PART)
	_assert(nested_room != "" and world.rooms.has(nested_room),
		"a coop nested inside another can be staged (%s)" % nested_room)
	GameState.machines["coop"] = 0
	var nest_up: Dictionary = world.apply_action({ "verb": "collect", "target": spot,
		"actor": "player" }, GameState)
	_assert(nest_up.get("ok", false) and int(nest_up.get("count", 0)) == 2,
		"picking the outer hut up takes the nest with it (%s)" % nest_up)
	_assert(GameState.machines.get("coop", 0) == 2,
		"and the crate is paid for both, rather than one of them vanishing (%d)"
			% GameState.machines.get("coop", 0))
	_assert(not world.rooms.has(nested_room) and not world.rooms.has(room_id),
		"with neither room left holding a slot")
	# Put it back for the checks below.
	GameState.machines["coop"] = 1
	world.apply_action({ "verb": "place", "target": spot, "item": "coop",
		"actor": "player" }, GameState)
	room_id = world.room_of_anchor(spot)
	room = world.rooms[room_id]
	origin = room["origin"]

	# --- and goes away with the hut -------------------------------------------
	#
	# Nothing living is ever pocketed (P-17, 2026-09-14): the hen was standing on
	# the front row, which is outdoors, so picking the hut up leaves her on grass.
	world.spawn_actor("chicken", SpeciesDefs.CHICKEN, spot)
	var taken: Dictionary = world.apply_action({ "verb": "collect", "target": spot,
		"actor": "player" }, GameState)
	_assert(taken.get("ok", false) and String(taken.get("collected", "")) == "coop",
		"the hut is picked back up (%s)" % taken)
	_assert(not world.rooms.has(room_id) and world.coop_tiles().is_empty(),
		"its inside goes with it, and its four squares are grass again")
	_assert(world.rooms.has(SimWorld.HOME_ROOM_ID),
		"...and the home is still a room, because nobody put the house down either")
	_assert(not world.is_walkable(origin.x, origin.y)
			and String(world.get_tile(origin.x, origin.y).get("state", "")) == WorldLayout.VOID,
		"the slot it was using is dark again, ready for the next hut")
	_assert(world.has_actor("chicken") and world.actor_pos("chicken") == spot,
		"and the hen is standing where the hut was, rather than in the crate")
	_assert(GameState.machines.get("coop", 0) == 1, "with the hut back in the crate")


# Room fittings (S-22, Q-117 ruled 2026-09-24; design/15 §9a). A nest box for the
# coop and a rug for the farmhouse, each bought in the shop and set down on a floor
# cell of the one room kind that takes it — and everything else still refused
# indoors. Taking the coop up hands back everything inside it, in a fixed order,
# with a machine's memory kept, and walks the hen out onto the grass. Recorded as a
# continued session and replayed, because the order things come out of a room is
# exactly what a replay has to agree about.
func test_room_fittings() -> void:
	print("\n--- Room fittings: a nest box and a rug, set down and taken back up (S-22) Tests ---")

	# --- the catalogue ---------------------------------------------------------
	for key in ["nest_box", "rug"]:
		_assert(MachineDefs.is_fitting(key) and key in MachineDefs.ORDER
				and not MachineDefs.goes_outdoors(key)
				and MachineDefs.price_of(key) > MachineDefs.price_of(SimWorld.COOP_ITEM),
			"the shop sells a %s as a fitting: indoors only, priced over the coop" % key)
		_assert(MachineDefs.icon_of(key) != null, "...with a picture for its card (%s)" % key)
	_assert(MachineDefs.rooms_of("nest_box") == ["coop"]
			and MachineDefs.rooms_of("rug") == [MachineDefs.FARMHOUSE_ROOM],
		"the nest box goes in a coop and the rug in the farmhouse, and nowhere else")
	var indoor_machines: Array = []
	for key in MachineDefs.ORDER:
		if not MachineDefs.is_fitting(key) and not MachineDefs.rooms_of(key).is_empty():
			indoor_machines.append(key)
	_assert(indoor_machines.is_empty(),
		"and no machine on today's shelf names a room, so every one stays outdoors (%s)"
			% [indoor_machines])
	_assert(MachineDefs.fitting_of_object(WorldLayout.NEST_BOX) == "nest_box"
			and MachineDefs.fitting_of_object(WorldLayout.CHICKEN_COOP) == ""
			and MachineDefs.fitting_of_object("") == "",
		"a nest box on the floor is known as one, and a coop is not a fitting")

	GameState.reset()
	SimRng.reseed(9225)
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
	_assert(spot.x >= 0, "the generated farm has a four-square block free")
	world.apply_action({ "verb": "buy_machine", "item": "coop", "actor": "player" }, GameState)
	var laid: Dictionary = world.apply_action({ "verb": "place", "target": spot,
		"item": "coop", "actor": "player" }, GameState)
	var room_id := String(laid.get("room", ""))
	_assert(laid.get("ok", false) and room_id != "", "a coop with an inside (%s)" % room_id)
	var origin: Vector2i = world.rooms[room_id]["origin"]
	var doorway: Vector2i = world.rooms[room_id]["door"]
	_assert(world.room_kind(room_id) == "coop"
			and world.room_kind(SimWorld.HOME_ROOM_ID) == MachineDefs.FARMHOUSE_ROOM,
		"a coop's room is a coop room and the house's is the farmhouse")

	# --- where each may go -----------------------------------------------------
	var home_floor := Vector2i(WorldLayout.home_room()["origin"]) + Vector2i(5, 5)
	var yard := Vector2i(-1, -1)
	for y in range(10, 17):
		for x in range(5, 23):
			if yard.x < 0 and world.placeable_at(Vector2i(x, y), "sprinkler"):
				yard = Vector2i(x, y)
	_assert(yard.x >= 0, "and a square of open farm ground to compare with (%s)" % yard)
	_assert(world.placeable_at(origin + Vector2i(1, 1), "nest_box"),
		"a nest box fits on a coop's floor")
	_assert(world.placeable_at(home_floor, "rug"), "and a rug on the farmhouse's floor")
	_assert(not world.placeable_at(home_floor, "nest_box")
			and not world.placeable_at(origin + Vector2i(1, 1), "rug"),
		"but not each other's: a room takes only what names it")
	_assert(not world.placeable_at(yard, "nest_box") and not world.placeable_at(yard, "rug")
			and world.placeable_at(yard, "sprinkler"),
		"and neither goes down in the yard, where a sprinkler still does")
	_assert(not world.placeable_at(origin + Vector2i(1, 1), "sprinkler")
			and not world.placeable_at(home_floor, "sprinkler")
			and not world.placeable_at(origin + Vector2i(1, 1), "bot_mk1"),
		"a machine whose row names no room is refused indoors, coop and house alike")
	_assert(not world.placeable_at(origin + Vector2i(1, 1), "coop")
			and not world.placeable_at(origin + Vector2i(1, 1), "spiral_tower"),
		"and a room may not hold another room")
	_assert(not world.placeable_at(doorway, "nest_box") and not world.placeable_at(origin, "nest_box"),
		"nor does a fitting go on the doorway or in the wall")

	# --- a machine that names a room goes in, and comes out knowing what it knew --
	#
	# No machine on the shelf names a room, so one is staged for the test: the rule
	# the ruling sets is that the row decides, and this proves the row is what is read.
	MachineDefs.TYPES["test_perch"] = { "name": "Test Perch", "price": 1,
		"species": SpeciesDefs.SPRINKLER, "configs": [], "default_config": "",
		"unlock_requirement": null, "rooms": ["coop"] }
	MachineDefs.ORDER.append("test_perch")
	_assert(world.placeable_at(origin + Vector2i(1, 1), "test_perch")
			and not world.placeable_at(home_floor, "test_perch"),
		"a machine whose row names the coop may go in a coop, and only a coop")

	# The staging a continued session starts from: stock in the crate, a trained
	# machine's memory boxed, and the hen indoors.
	GameState.machines["nest_box"] = 2
	GameState.machines["rug"] = 1
	GameState.machines["test_perch"] = 1
	GameState.boxed["test_perch"] = [{ "weights": [0.5, -0.25], "ledger": [3] }]
	if not world.has_actor(SimWorld.ACTOR_CHICKEN):
		world.spawn_actor(SimWorld.ACTOR_CHICKEN, SpeciesDefs.CHICKEN, spot + Vector2i(0, 1))
	world.set_actor_pos(SimWorld.ACTOR_CHICKEN, origin + Vector2i(2, 3))
	var base_save = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var rlog := ReplayLog.new()
	rlog.start_from_save(base_save)

	# --- setting them down -----------------------------------------------------
	var box_a := origin + Vector2i(3, 3)
	var box_b := origin + Vector2i(1, 1)
	var perch := origin + Vector2i(4, 1)
	var egg_at := origin + Vector2i(2, 2)
	var put_a := _replay_do(world, rlog, { "verb": "place", "target": box_a,
		"item": "nest_box", "actor": "player" })
	_assert(put_a.get("ok", false) and world.get_object(box_a.x, box_a.y) == WorldLayout.NEST_BOX
			and int(GameState.machines["nest_box"]) == 1,
		"she sets a nest box down on the coop's floor, out of the crate (%s)" % put_a)
	_assert(world.is_walkable(box_a.x, box_a.y),
		"and it lies low: the floor it stands on can still be crossed")
	var again: Dictionary = world.apply_action({ "verb": "place", "target": box_a,
		"item": "nest_box", "actor": "player" }, GameState)
	_assert(not again.get("ok", false) and int(GameState.machines["nest_box"]) == 1,
		"a second one on the same cell is refused and costs nothing (%s)" % again)
	_replay_do(world, rlog, { "verb": "place", "target": box_b, "item": "nest_box",
		"actor": "player" })
	var put_perch := _replay_do(world, rlog, { "verb": "place", "target": perch,
		"item": "test_perch", "actor": "player" })
	_assert(put_perch.get("ok", false)
			and world.actor(String(put_perch.get("machine", ""))).get("extra", {}).get("weights", [])
				== [0.5, -0.25],
		"the machine goes in with its boxed memory (%s)" % put_perch)
	_replay_do(world, rlog, { "verb": "lay_egg", "target": egg_at,
		"actor": SimWorld.ACTOR_CHICKEN })
	_assert(world.get_object(egg_at.x, egg_at.y) == "egg", "and the hen lays on the coop floor")

	var rug_down := _replay_do(world, rlog, { "verb": "place", "target": home_floor,
		"item": "rug", "actor": "player" })
	_assert(rug_down.get("ok", false) and world.get_object(home_floor.x, home_floor.y) == WorldLayout.RUG,
		"a rug goes down in the farmhouse (%s)" % rug_down)
	var rug_up := _replay_do(world, rlog, { "verb": "collect", "target": home_floor,
		"actor": "player" })
	_assert(rug_up.get("ok", false) and String(rug_up.get("collected", "")) == "rug"
			and world.get_object(home_floor.x, home_floor.y) == ""
			and int(GameState.machines["rug"]) == 1,
		"and comes back up into the crate with a tap's verb (%s)" % rug_up)
	_replay_do(world, rlog, { "verb": "place", "target": home_floor + Vector2i(1, 0),
		"item": "rug", "actor": "player" })

	# --- taking the coop up hands back everything inside it -----------------------
	var egg_before := int(GameState.items.get("egg", 0))
	var up := _replay_do(world, rlog, { "verb": "collect", "target": spot, "actor": "player" })
	_assert(up.get("ok", false) and String(up.get("collected", "")) == "coop",
		"the coop comes up (%s)" % up)
	var came_out: Array = []
	for entry in up.get("contents", []):
		came_out.append([String(entry.item), Vector2i(entry.cell)])
	_assert(came_out == [["nest_box", box_b], ["test_perch", perch], ["egg", egg_at],
			["nest_box", box_a]],
		"everything inside comes out first, row by row across the floor (%s)" % [came_out])
	_assert(int(GameState.machines["nest_box"]) == 2 and int(GameState.machines["test_perch"]) == 1
			and int(GameState.items.get("egg", 0)) == egg_before + 1,
		"each as its own item: two nest boxes and the machine in the crate, the egg in her basket")
	var kept: Array = GameState.boxed.get("test_perch", [])
	_assert(kept.size() == 1 and kept[0].get("weights", []) == [0.5, -0.25]
			and kept[0].get("ledger", []) == [3],
		"and the machine went in with what it knew (Q-98: picking up is repositioning)")
	_assert(not world.rooms.has(room_id)
			and String(world.get_tile(box_a.x, box_a.y).get("state", "")) == WorldLayout.VOID,
		"then the room closes, with nothing left in its slot")
	_assert(world.has_actor(SimWorld.ACTOR_CHICKEN)
			and world.actor_pos(SimWorld.ACTOR_CHICKEN) == spot
			and world.space_of(world.actor_pos(SimWorld.ACTOR_CHICKEN)) == "farm",
		"and the hen who was indoors is standing on the grass where the hut was (%s)"
			% world.actor_pos(SimWorld.ACTOR_CHICKEN))
	_assert(world.get_object(home_floor.x + 1, home_floor.y) == WorldLayout.RUG,
		"the farmhouse's rug is untouched: only the coop came up")

	# --- and a replay of the session agrees ---------------------------------------
	var end_save = JSON.parse_string(JSON.stringify(SaveGame.capture(world, GameState)))
	var report := SaveGame.replay_report(ReplayLog.from_json(rlog.to_json()), end_save)
	_assert(report["matched"],
		"a replay of the session ends on the same farm and the same crate %s" % report["divergence"])

	MachineDefs.ORDER.erase("test_perch")
	MachineDefs.TYPES.erase("test_perch")
	GameState.reset()


func test_one_pouch() -> void:
	print("\n--- Three plantable units and a separate shipping reserve ---")
	GameState.reset()
	SimRng.reseed(113116)
	var world := SimWorld.new()
	world.generate()
	_assert(GameState.pouch == {"wheat": 5, "tomato": 0}, "a new farm carries five wheat units")
	_assert(CropDefs.is_plantable("wheat") and CropDefs.is_plantable("tomato")
		and not CropDefs.is_plantable("egg") and not CropDefs.is_plantable("scarecrow"),
		"only crop species can be replanted")
	for species in ["wheat", "tomato"]:
		var plot := Vector2i(20, 10)
		world.set_tile_state(plot.x, plot.y, "tilled")
		if species == "tomato":
			GameState.pouch["tomato"] = 1
		var before := int(GameState.pouch[species])
		var planted := world.apply_action({"actor": "player", "verb": "plant",
			"target": plot, "seed_type": species}, GameState)
		_assert(planted.ok and int(GameState.pouch[species]) == before - 1,
			"planting %s spends one carried unit" % species)
		world.set_tile_state(plot.x, plot.y, "ready", species)
		var harvested := world.apply_action({"actor": "player", "verb": "harvest",
			"target": plot}, GameState)
		_assert(harvested.ok and int(GameState.pouch[species]) == before + 2,
			"harvesting %s yields three plantable units" % species)
	GameState.pouch = {"wheat": 5, "tomato": 0}
	var first := world.apply_action({"actor": "player", "verb": "sell"}, GameState)
	_assert(first.ok and int(first.reserved.wheat) == 5 and int(first.sold.wheat) == 0
		and GameState.gold == 0 and int(GameState.bin_reserve.wheat) == 5,
		"five wheat fill reserve and sell none")
	GameState.pouch["wheat"] = 8
	var second := world.apply_action({"actor": "player", "verb": "sell"}, GameState)
	_assert(second.ok and int(second.reserved.wheat) == 5 and int(second.sold.wheat) == 3
		and int(GameState.bin_reserve.wheat) == 10 and GameState.gold == 45,
		"eight more reserve five and sell three")
	var last_player_deposit: Dictionary = GameState.last_bin_delivery.duplicate(true)
	var machine: Dictionary = GameState.sell_one_crop("wheat")
	_assert(machine.ok and machine.reserved == 0 and machine.sold == 1
		and GameState.gold == 60, "another delivery sells one")
	_assert(GameState.last_bin_delivery == last_player_deposit,
		"a machine delivery does not rewrite the last player deposit")
	GameState.items["egg"] = 2
	var eggs := world.apply_action({"actor": "player", "verb": "sell"}, GameState)
	_assert(eggs.ok and int(eggs.sold.egg) == 2 and GameState.gold == 80
		and not GameState.bin_reserve.has("egg"), "eggs keep their sale behavior outside reserve")
	GameState.pouch["tomato"] = 4
	var tomatoes := world.apply_action({"actor": "player", "verb": "sell"}, GameState)
	_assert(tomatoes.ok and int(GameState.bin_reserve.tomato) == 4
		and int(GameState.bin_reserve.wheat) == 10 and GameState.gold == 80,
		"tomato fills its own reserve without changing wheat or gold")
	var clock_before: int = GameState.actions_today
	var energy_before: int = GameState.energy
	GameState.pouch["wheat"] = SimWorld.ON_PERSON_CAP
	var no_room := world.apply_action({"actor": "player", "verb": "withdraw_seed",
		"params": {"crop_type": "wheat"}}, GameState)
	_assert(not no_room.ok and int(GameState.bin_reserve.wheat) == 10
		and int(GameState.pouch.wheat) == SimWorld.ON_PERSON_CAP,
		"a full stack cannot withdraw or change either balance")
	GameState.pouch["wheat"] = 0
	var taken := world.apply_action({"actor": "player", "verb": "withdraw_seed",
		"params": {"crop_type": "wheat"}}, GameState)
	_assert(taken.ok and taken.moved == 10 and int(GameState.pouch.wheat) == 10
		and int(GameState.bin_reserve.wheat) == 0, "withdrawal moves the reserve into the pouch")
	_assert(GameState.actions_today == clock_before and GameState.energy == energy_before,
		"bin errands spend no action time or energy")


func test_carry_cap() -> void:
	print("\n--- Per-species carrying cap and atomic harvest ---")
	GameState.reset()
	SimRng.reseed(113)
	var world := SimWorld.new()
	world.generate()
	var plot := Vector2i(20, 10)
	world.set_tile_state(plot.x, plot.y, "ready", "wheat")
	var cap: int = SimWorld.ON_PERSON_CAP
	GameState.pouch = {"wheat": cap - 2, "tomato": cap}
	var energy_before: int = GameState.energy
	var rng_before: int = SimRng.rng.state
	var refused := world.apply_action({"actor": "player", "verb": "harvest",
		"target": plot}, GameState)
	_assert(not refused.ok and refused.reason == "pouch_full"
		and world.get_tile(plot.x, plot.y).state == "ready"
		and GameState.energy == energy_before and int(GameState.pouch.wheat) == cap - 2,
		"two short of the cap refuses a three-unit harvest without changing the crop or energy")
	_assert(SimRng.rng.state == rng_before, "full-pouch refusal consumes no RNG")
	GameState.pouch["wheat"] = cap - 3
	var accepted := world.apply_action({"actor": "player", "verb": "harvest",
		"target": plot}, GameState)
	_assert(accepted.ok and int(GameState.pouch.wheat) == cap,
		"three short of the cap reaches the wheat cap exactly, independent of tomato's full stack")
	GameState.gold = 100
	GameState.harvest_counts["wheat"] = 1
	var gold_before: int = GameState.gold
	var buy := world.apply_action({"actor": "player", "verb": "buy_seed",
		"seed_type": "tomato"}, GameState)
	_assert(not buy.ok and GameState.gold == gold_before,
		"a full tomato stack refuses a purchase before gold changes")
	var silo: int = cap * 4
	MachineDefs.TYPES["test_silo"] = {"object": "silo_fixture", "crop_capacity": silo}
	MachineDefs.ORDER.append("test_silo")
	world.set_object(21, 10, "silo_fixture")
	_assert(world.carry_cap("wheat") == silo and world.carry_cap("tomato") == silo,
		"a placed silo fixture raises each species cap to its own capacity")
	world.set_tile_state(plot.x, plot.y, "ready", "wheat")
	GameState.pouch["wheat"] = silo - 2
	energy_before = GameState.energy
	rng_before = SimRng.rng.state
	var silo_refusal := world.apply_action({"actor": "player", "verb": "harvest",
		"target": plot}, GameState)
	_assert(not silo_refusal.ok and silo_refusal.reason == "pouch_full"
		and String(world.get_tile(plot.x, plot.y).state) == "ready"
		and int(GameState.pouch.wheat) == silo - 2 and GameState.energy == energy_before
		and SimRng.rng.state == rng_before,
		"two short of the silo's cap refuses all three units without changing tile, energy, or RNG")
	GameState.pouch["wheat"] = silo - 3
	var silo_harvest := world.apply_action({"actor": "player", "verb": "harvest",
		"target": plot}, GameState)
	_assert(silo_harvest.ok and int(GameState.pouch.wheat) == silo
		and String(world.get_tile(plot.x, plot.y).state) == "cleared",
		"three short of the silo's cap accepts all three units and cuts the crop")
	MachineDefs.ORDER.erase("test_silo")
	MachineDefs.TYPES.erase("test_silo")


func test_save_v5_migration() -> void:
	print("\n--- Legacy stock, pending sale, and bin replay ---")
	GameState.reset()
	SimRng.reseed(515)
	var world := SimWorld.new()
	world.generate()
	BotBrain.deploy(world, "legacy_picker", BotBrain.CONFIG_IDLE, Vector2i(20, 10))
	var legacy_hands: Dictionary = world.actor("legacy_picker")["extra"]
	legacy_hands["carrying"] = "wheat"
	legacy_hands.erase("carrying_count")
	var old := SaveGame.capture(world, GameState)
	old["version"] = 4
	old.state.erase("pouch")
	old.state.erase("items")
	old.state.erase("bin_reserve")
	old.state.erase("last_bin_delivery")
	old.state["seeds"] = {"wheat": SimWorld.ON_PERSON_CAP - 1, "tomato": 1, "scarecrow": 2}
	old.state["crops"] = {"wheat": 7, "egg": 3}
	old.state["shipping_bin"] = {"wheat": 2}
	var migrated := SaveGame.migrate(old)
	_assert(int(migrated.world.actors.legacy_picker.extra.carrying_count) == 1,
		"a v4 machine hand migrates as one carried unit")
	_assert(migrated.version == SaveGame.VERSION and int(migrated.state.pouch.wheat) == SimWorld.ON_PERSON_CAP + 6
		and int(migrated.state.items.egg) == 3 and int(migrated.state.items.scarecrow) == 2,
		"v4 stock sums plantable units without clipping and preserves noncrop items")
	var restored := SimWorld.new()
	GameState.reset()
	_assert(SaveGame.restore(old, restored, GameState), "v4 farm restores into v5")
	_assert(int(GameState.pouch.wheat) == SimWorld.ON_PERSON_CAP + 6 and GameState.bin_reserve.is_empty(),
		"over-cap carried stock survives; new reserve starts empty")
	var plot := Vector2i(20, 10)
	restored.set_tile_state(plot.x, plot.y, "ready", "wheat")
	var blocked := restored.apply_action({"actor": "player", "verb": "harvest",
		"target": plot}, GameState)
	_assert(not blocked.ok and blocked.reason == "pouch_full", "an over-cap save cannot grow its stack")
	var gold_before: int = GameState.gold
	restored.apply_action({"actor": "world", "verb": "sleep", "weather": "sunny"}, GameState)
	_assert(GameState.gold == gold_before + 30 and int(GameState.shipping_bin.wheat) == 0,
		"the legacy pending bin sale still pays at sleep")
	var old_delivery := restored.apply_action({"actor": "legacy_picker", "verb": "sell"}, GameState)
	_assert(old_delivery.ok and old_delivery.reserved == 1 and old_delivery.sold == 0
		and int(GameState.bin_reserve.wheat) == 1
		and int(restored.actor("legacy_picker")["extra"].carrying_count) == 0,
		"the restored one-unit machine hand delivers exactly one unit")
	# The new bin path is replayable across an autosave boundary, including the
	# withdrawal that makes the deposited unit plantable again.
	GameState.reset()
	SimRng.reseed(516)
	var fresh := SimWorld.new()
	fresh.generate()
	var soil := Vector2i(20, 10)
	fresh.set_tile_state(soil.x, soil.y, "tilled")
	var base: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(fresh, GameState)))
	var log := ReplayLog.new()
	log.start_from_save(base, fresh.gen_seed)
	var deposited := _replay_do(fresh, log, {"actor": "player", "verb": "sell"})
	_assert(deposited.ok and int(GameState.bin_reserve.wheat) == 5
		and int(GameState.pouch.wheat) == 0, "deposit moves the five units to reserve")
	var withdrawn := _replay_do(fresh, log, {"actor": "player", "verb": "withdraw_seed",
		"params": {"crop_type": "wheat"}})
	_assert(withdrawn.ok and withdrawn.moved == 5 and int(GameState.pouch.wheat) == 5,
		"withdrawal returns the reserved units to the pouch")
	var planted := _replay_do(fresh, log, {"actor": "player", "verb": "plant",
		"target": soil, "seed_type": "wheat"})
	_assert(planted.ok and int(GameState.pouch.wheat) == 4
		and String(fresh.get_tile(soil.x, soil.y).state) == "seeded",
		"the returned units can be planted")
	var live_canonical := SaveGame.capture_canonical(fresh, GameState)
	var final_save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(fresh, GameState)))
	var loaded := SimWorld.new()
	GameState.reset()
	_assert(SaveGame.restore(final_save, loaded, GameState),
		"deposit, withdrawal, and planting survive a v5 save/load")
	_assert(SaveGame.capture_canonical(loaded, GameState) == live_canonical,
		"loaded v5 stock and planted tile match the live farm")
	_assert(SaveGame.replay_matches(log, final_save),
		"deposit, withdrawal, and planting replay to the saved farm")


# --- A Mark III given its squares (Q-124, ruled 2026-09-25) ------------------
#
# The designer kept the reward as it is and asked for a way to tell the robot
# where to work. So this is that instruction proved end to end in the sim: the
# verb and its refusals, what the robot is shown, where it walks and works, and
# that the assignment survives everything a robot's memory has to survive — the
# disk, a replay and being picked up.

# Her own bed, sown and dry, well outside what the robot can see from where it is
# put down (`MK3_SPOT`, in the middle of `MK3_PATCH`, which is sown too). A 4×4,
# so it is exactly `ASSIGN_LIMIT` squares.
func test_mark_three_assigned_tiles() -> void:
	print("\n--- A Mark III works the squares she gives it (Q-124) Tests ---")

	# --- the verb, and what it refuses -----------------------------------------
	var s := _mk3_yard(12401)
	var bed := _her_bed(s)
	var bot := _mk3_place(s, MK3_SPOT)
	var energy_before: int = s.gs.energy
	var clock_before: int = s.gs.actions_today
	var given := _assign(s, bot, bed)
	_assert(given.get("ok", false) and int(given.get("count", 0)) == BotBrain.ASSIGN_LIMIT
			and bool(given.get("assigned", false)),
		"she gives the robot her sixteen-square bed in one Action (%s)" % str(given))
	_assert(BotBrain.assigned_of(s.world.actor(bot)["extra"]) == bed,
		"and the robot holds exactly those squares, in the order she gave them")
	_assert(s.gs.energy == energy_before and s.gs.actions_today == clock_before,
		"pointing costs her nothing and does not move the day's clock — it is an instruction")
	var one_more: Array[Vector2i] = bed.duplicate()
	one_more.append(Vector2i(19, 12))
	var full := _assign(s, bot, one_more)
	_assert(not full.get("ok", false) and String(full.get("reason", "")) == "assignment_full",
		"a seventeenth square is refused as assignment_full (%s)" % String(full.get("reason", "")))
	var bin_only: Array[Vector2i] = [Observation.bin_tile(s.world)]
	var not_ground := _assign(s, bot, bin_only)
	_assert(not not_ground.get("ok", false)
			and String(not_ground.get("reason", "")) == "not_teachable",
		"the shipping bin's square is not ground to work, and is refused (%s)"
			% String(not_ground.get("reason", "")))
	var odd := s.act({ "verb": "assign_tiles", "target": bed[0], "machine": bot,
		"tiles": [20, 12, 21], "actor": "player" })
	_assert(not odd.get("ok", false) and String(odd.get("reason", "")) == "bad_tiles",
		"half a square is refused as bad_tiles")
	var hen := s.act({ "verb": "assign_tiles", "target": bed[0],
		"machine": SimWorld.ACTOR_CHICKEN, "tiles": _flat(bed), "actor": "player" })
	_assert(not hen.get("ok", false)
			and String(hen.get("reason", "")) == "not_assignable_machine",
		"only a learning robot can be given squares (%s)" % String(hen.get("reason", "")))
	_assert(BotBrain.assigned_of(s.world.actor(bot)["extra"]) == bed,
		"and none of those refusals touched the squares it already had")

	# --- what it is shown ------------------------------------------------------
	# From where it stands, in the middle of the patch it was put down in, every
	# square around it is sown and thirsty — and not one of them is its own.
	var extra: Dictionary = s.world.actor(bot)["extra"]
	var spec: Dictionary = extra["spec"]
	var r := int(spec.get("vision", 2))
	var side := 2 * r + 1
	var nch := (spec["channels"] as Array).size()
	var head := Observation.size(spec) - side * side * nch
	var west := head + (r * side + (r - 1)) * nch
	var masked_view := Observation.build(s.world, bot, spec, s.gs)
	var kept_squares: Array = extra["assigned"]
	extra.erase("assigned")
	var open_view := Observation.build(s.world, bot, spec, s.gs)
	extra["assigned"] = kept_squares
	_assert(float(open_view[west + Observation.CH_NEEDS_WATER]) == 1.0
			and float(open_view[west + Observation.CH_CROP]) == 1.0,
		"unassigned, the square beside it reads as a thirsty crop")
	_assert(float(masked_view[west + Observation.CH_NEEDS_WATER]) == 0.0
			and float(masked_view[west + Observation.CH_CROP]) == 0.0,
		"given her bed, the same square shows no work — it is not the robot's to do")
	_assert(float(masked_view[west + Observation.CH_WALKABLE])
			== float(open_view[west + Observation.CH_WALKABLE])
			and float(open_view[west + Observation.CH_WALKABLE]) == 1.0,
		"while what the ground is like is still what the ground is like")
	_assert(masked_view.size() == open_view.size(),
		"and the vector keeps its width, so every weight it learned still lines up (%d)"
			% masked_view.size())

	# --- where it goes, and what it works --------------------------------------
	# A fresh robot, uniform over its eight actions, put down with her bed out of
	# its sight. Everything it does to a square in the next three minutes has to
	# be done to a square of hers.
	var taken := s.tick(SimClock.RATE * 180)
	var worked := 0
	var watered_hers := 0
	var strays: Array = []
	for t in taken:
		var a: Dictionary = t["action"]
		if String(a.get("actor", "")) != bot or not t["result"].get("ok", false):
			continue
		var verb := String(a.get("verb", ""))
		if not (verb in ["till", "plant", "water", "harvest"]):
			continue
		worked += 1
		var at: Vector2i = a.get("target", Vector2i(-1, -1))
		if not bed.has(at):
			strays.append(at)
		elif verb == "water":
			watered_hers += 1
	_assert(worked > 0 and strays.is_empty(),
		"every square it worked in three minutes was one of hers: %d worked, strays %s"
			% [worked, str(strays)])
	_assert(watered_hers > 0,
		"and it walked over and watered her crop — %d of her squares" % watered_hers)
	var patch_watered := 0
	for ty in range(MK3_PATCH.position.y, MK3_PATCH.end.y):
		for tx in range(MK3_PATCH.position.x, MK3_PATCH.end.x):
			if bool(s.world.get_tile(tx, ty).get("watered_today", false)):
				patch_watered += 1
	_assert(patch_watered == 0,
		"while the thirsty patch it was set down in stayed dry (%d watered)" % patch_watered)

	# --- nothing assigned is today's robot -------------------------------------
	var cleared := _assign(s, bot, [] as Array[Vector2i])
	_assert(cleared.get("ok", false) and int(cleared.get("count", -1)) == 0
			and not (s.world.actor(bot)["extra"] as Dictionary).has("assigned"),
		"an empty list takes every square back, and leaves no key behind")
	s.done()

	# Two robots on one seed, one given squares and cleared before it ever thought:
	# a minute later they are the same robot, key for key. The learning gate's
	# farms assign nothing, and this is why they play exactly as they did.
	var twin_a := _mk3_yard(12402)
	var bed_a := _her_bed(twin_a)
	var id_a := _mk3_place(twin_a, MK3_SPOT)
	_assign(twin_a, id_a, bed_a)
	_assign(twin_a, id_a, [] as Array[Vector2i])
	twin_a.tick(SimClock.RATE * 60)
	var twin_b := _mk3_yard(12402)
	_her_bed(twin_b)
	var id_b := _mk3_place(twin_b, MK3_SPOT)
	twin_b.tick(SimClock.RATE * 60)
	var ex_a: Dictionary = twin_a.world.actor(id_a)["extra"]
	var ex_b: Dictionary = twin_b.world.actor(id_b)["extra"]
	_assert(ex_a.keys().size() == ex_b.keys().size(),
		"a cleared robot carries no key a never-assigned one does not")
	for key in ex_a.keys():
		_assert_quiet(str(ex_a[key]) == str(ex_b.get(key)), "'%s' agrees" % key)
	_flush_quiet("and a minute on, it is the never-assigned robot key for key")
	twin_a.done()
	twin_b.done()

	# --- the disk --------------------------------------------------------------
	var saved := _mk3_yard(12403)
	var saved_bed := _her_bed(saved)
	var saved_bot := _mk3_place(saved, MK3_SPOT)
	_assign(saved, saved_bot, saved_bed)
	saved.tick(SimClock.RATE * 20)
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(saved.world, saved.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	gs_back.reset()
	var restored := SimWorld.new()
	_assert(SaveGame.restore(snapshot, restored, gs_back),
		"a farm with an assigned Mark III saves")
	_assert(BotBrain.assigned_of(restored.actor(saved_bot)["extra"]) == saved_bed,
		"and the robot comes back holding the same sixteen squares")
	_assert(SaveGame.capture_canonical(restored, gs_back)
			== SaveGame.capture_canonical(saved.world, saved.gs),
		"the restored farm is the saved farm")
	gs_back.free()

	# --- being picked up is repositioning (Q-98) --------------------------------
	var lifted := saved.act({ "verb": "collect", "target": saved.world.actor_pos(saved_bot),
		"actor": "player" })
	_assert(lifted.get("ok", false) and not saved.world.has_actor(saved_bot),
		"she picks it up")
	var boxed: Array = saved.gs.boxed.get("bot_mk3", [])
	_assert(boxed.size() == 1 and BotBrain.assigned_of(boxed[0]) == saved_bed,
		"and the crate remembers its squares along with everything else it learned")
	var far := Vector2i(5, 5)
	var back_id := String(saved.act({ "verb": "place", "target": far, "item": "bot_mk3",
		"actor": "player" }).get("machine", ""))
	_assert(back_id != ""
			and BotBrain.assigned_of(saved.world.actor(back_id)["extra"]) == saved_bed,
		"set down across the farm, it still holds her bed")
	var start_gap := _gap_to(saved.world.actor_pos(back_id), saved_bed)
	saved.tick(SimClock.RATE * 30)
	var end_gap := _gap_to(saved.world.actor_pos(back_id), saved_bed)
	_assert(start_gap > 2 and end_gap <= 2,
		"and walks back to it on its own: %d tiles away when put down, %d after half a minute"
			% [start_gap, end_gap])
	saved.done()

	# --- a replay --------------------------------------------------------------
	# The assignment is a recorded Action; everything the robot then does with it
	# is recomputed. She changes her mind once, part way through, and there is a
	# night in between, so the replay has to apply each list at its own tick for
	# the robot's day to come out the same.
	var live := _mk3_yard(12404)
	var live_bed := _her_bed(live)
	live.rebase()
	var learner := _mk3_place(live, MK3_SPOT)
	_assign(live, learner, live_bed)
	live.tick(SimClock.RATE * 45)
	var smaller: Array[Vector2i] = live_bed.slice(0, 8)
	_assign(live, learner, smaller, live_bed[12])
	live.tick(SimClock.RATE * 15)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	live.tick(SimClock.RATE * 30)
	var live_canonical := SaveGame.capture_canonical(live.world, live.gs)
	var again := SimWorld.new()
	live.log.apply_to(again, live.gs)
	_assert(live.log.divergence == "",
		"a session in which she gave the robot squares, then took half back, recomputes cleanly (%s)"
			% live.log.divergence)
	_assert(SaveGame.capture_canonical(again, live.gs) == live_canonical,
		"landing on the same farm and the same robot")
	_assert(BotBrain.assigned_of(again.actor(learner)["extra"]) == smaller,
		"holding the eight squares she left it with")
	live.done()


# A brain the gateway says no to still replays (playtests/2026-09-25_113814).
#
# The recorder writes down only what succeeded, and the replay used to compare the
# recording against everything the brains *tried* — so the first refused brain
# Action in a session read as a desync, naming a robot that had done exactly what
# it did live. The tablet found it with a Mark III set down in a stall: it swung
# its hoe at the stall's floor, the stall won, and the verifier said the brain
# had diverged. This is that farm in miniature.
#
# **The robot no longer asks** (2026-09-25, `test_stall_floor_is_not_ground`): its
# scan skips a building's floor, as her tap does, so this farm now plays with no
# refusal at all and still has to replay cleanly. No brain in the game is refused
# in ordinary play any more, so the verifier's rule — a refusal is left out of the
# comparison — is pinned below on a recomputed list directly, where the next brain
# that disagrees with the gateway will meet it.
func test_refused_brain_action_replays() -> void:
	print("\n--- A refused brain Action is not a desync (2026-09-25 playtest) Tests ---")
	var s := _mk3_yard(7307)
	var bay := _yard_square(s.world)
	s.world.set_tile_state(bay.x, bay.y, "cleared")
	s.world.set_tile_state(bay.x + 1, bay.y, "cleared")
	s.rebase()
	s.act({ "verb": "buy_machine", "item": "stall", "actor": "player" })
	var shed := s.act({ "verb": "place", "target": bay, "item": "stall", "actor": "player" })
	_assert(shed.get("ok", false), "a stall goes down on open ground (%s)" % str(shed))
	var robot := _mk3_place(s, bay)
	_assert(robot != "" and s.world.actor_pos(robot) == bay,
		"and a Mark III is set down inside it (%s)" % robot)

	var refused := 0
	var acted := 0
	for t in s.tick(SimClock.RATE * 60):
		if t["action"].get("actor", "") != robot:
			continue
		acted += 1
		if not t["result"].get("ok", false):
			refused += 1
	_assert(acted > 0 and refused == 0,
		"in its first minute it works and is never refused (%d Actions, %d refused)" % [acted, refused])

	var tried: Array[Dictionary] = [
		{ "action": { "verb": "till", "actor": robot }, "result": { "ok": false, "reason": "occupied" }, "tick": 5 },
		{ "action": { "verb": "water", "actor": robot }, "result": { "ok": true }, "tick": 6 },
	]
	var recomputed: Array[Dictionary] = []
	ReplayLog._collect(recomputed, tried)
	_assert(recomputed.size() == 1 and String(recomputed[0]["action"]["verb"]) == "water",
		"a refused brain Action is left out of what the recording is compared against")

	var live_canonical := SaveGame.capture_canonical(s.world, s.gs)
	var again := SimWorld.new()
	var gs_again = load("res://systems/game_state.gd").new()
	var log := ReplayLog.from_json(s.log.to_json())
	log.apply_to(again, gs_again)
	_assert(log.divergence == "",
		"and the replay recomputes it cleanly, refusals and all (%s)" % log.divergence)
	_assert(SaveGame.capture_canonical(again, gs_again) == live_canonical,
		"landing on the same farm and the same robot")
	gs_again.free()
	s.done()



# --- The workbench's shelf, and the pace setting (S-29; Q-129 a, 2026-09-25) -----
#
# Daniel ruled that a Mark III's learning upgrades are bought at the training
# workbench (S-29) and that the first of them is a pace setting (Q-129 a). The
# purchase and the pace are both recorded player Actions, so everything below goes
# through the gateway: what each refuses, what each costs, that normal pace is the
# night the robot already had to the bit, that bold cannot push past what the
# day-size guard allows on a big day, and that the pace survives the disk, the crate
# and a replay. Design in `design/14` §11 and `design/06` ("Its pace").

# A farm with a Mark III on it and a bench in the yard, both put down through the
# gateway. Returns the session, the robot and the bench's square.
func test_workbench_shelf() -> void:
	print("\n--- The workbench's shelf and a Mark III's pace (S-29, Q-129) Tests ---")

	# --- the catalogue ---------------------------------------------------------
	_assert(ShelfDefs.ORDER.size() >= 1 and ShelfDefs.ORDER[0] == "pace" and ShelfDefs.has("pace"),
		"the shelf's first row is the pace setting (%s)" % str(ShelfDefs.ORDER))
	_assert(ShelfDefs.price_of("pace") == 150 and ShelfDefs.scope_of("pace") == "robot",
		"for 150 gold, bought for one robot (S-29)")
	_assert(not MachineDefs.has("pace") and not ("pace" in MachineDefs.ORDER),
		"and it is not in the seed box's catalogue — learning upgrades are sold at the bench")
	_assert(BotBrain.PACE_SCALES.size() == 3
			and float(BotBrain.PACE_SCALES[BotBrain.PACE_NORMAL]) == 1.0
			and float(BotBrain.PACE_SCALES[BotBrain.PACE_CALM]) < 1.0
			and float(BotBrain.PACE_SCALES[BotBrain.PACE_BOLD]) > 1.0,
		"three steps, and normal is exactly the rate the robot always had (%s)"
			% str(BotBrain.PACE_SCALES))
	_assert(ShelfDefs.pace_price(BotBrain.PACE_CALM) == 150
			and ShelfDefs.pace_price(BotBrain.PACE_NORMAL) < 0
			and ShelfDefs.pace_price(BotBrain.PACE_BOLD) < 0,
		"the first pace step costs 150 gold and later prices remain unset")
	_assert(BotBrain.owns_pace({}, BotBrain.PACE_NORMAL),
		"normal is owned by every Mark III because it is the pace each one starts with")
	# --- separately owned steps (S-34) -----------------------------------------
	var separate := _shelf_yard(12900)
	var ss: LiveSession = separate["s"]
	var sb := String(separate["bot"])
	var sbench: Vector2i = separate["bench"]
	ss.gs.gold = 149
	var step_short := _buy_pace(ss, sb, sbench, BotBrain.PACE_CALM)
	_assert(not step_short.get("ok", true) and step_short.get("reason", "") == "no_gold"
			and ss.gs.gold == 149 and not BotBrain.owns_pace(ss.world.actor(sb)["extra"], BotBrain.PACE_CALM),
		"one gold short cannot buy the first pace step")
	ss.gs.gold = 500
	var step_bought := _buy_pace(ss, sb, sbench, BotBrain.PACE_CALM)
	var step_extra: Dictionary = ss.world.actor(sb)["extra"]
	_assert(step_bought.get("ok", false) and ss.gs.gold == 350
			and BotBrain.owns_pace(step_extra, BotBrain.PACE_CALM)
			and not BotBrain.owns_pace(step_extra, BotBrain.PACE_BOLD),
		"150 gold buys only the first pace step through the gateway")
	var unset := _buy_pace(ss, sb, sbench, BotBrain.PACE_BOLD)
	_assert(not unset.get("ok", true) and unset.get("reason", "") == "price_unset"
			and ss.gs.gold == 350 and not BotBrain.owns_pace(step_extra, BotBrain.PACE_BOLD),
		"an unset later price cannot be treated as free")
	_assert(_set_pace(ss, sb, BotBrain.PACE_CALM).get("ok", false)
			and not _set_pace(ss, sb, BotBrain.PACE_BOLD).get("ok", true),
		"the bought step can be set and an unowned step cannot")
	var normal_free := _set_pace(ss, sb, BotBrain.PACE_NORMAL)
	_assert(normal_free.get("ok", false)
			and BotBrain.owns_pace(step_extra, BotBrain.PACE_NORMAL)
			and BotBrain.pace_of(step_extra) == BotBrain.PACE_NORMAL,
		"after choosing calm, the robot can always return to its starting normal pace")
	# A save gives the bought step back as bought. The file is JSON, which hands
	# every number back as a float, and an array holding 0.0 does not contain the
	# step 0 — so without care a loaded robot forgets the step she paid for, and
	# the shelf sells it to her a second time.
	var step_snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(ss.world, ss.gs)))
	var step_gs = load("res://systems/game_state.gd").new()
	step_gs.reset()
	var step_world := SimWorld.new()
	_assert(SaveGame.restore(step_snapshot, step_world, step_gs),
		"a farm with a separately bought pace step saves")
	var step_back: Dictionary = step_world.actor(sb)["extra"]
	_assert(BotBrain.owns_pace(step_back, BotBrain.PACE_CALM)
			and BotBrain.owns_pace(step_back, BotBrain.PACE_NORMAL)
			and not BotBrain.owns_pace(step_back, BotBrain.PACE_BOLD),
		"and the loaded robot keeps calm, its starting normal pace, and no bold pace")
	var rebuy: Dictionary = step_world.apply_action({ "verb": "buy_pace", "target": sbench,
		"machine": sb, "pace": BotBrain.PACE_CALM, "actor": "player" }, step_gs)
	_assert(not rebuy.get("ok", true) and rebuy.get("reason", "") == "already_owned"
			and step_gs.gold == ss.gs.gold,
		"so the shelf does not sell her the same step twice (%s)" % str(rebuy))
	step_gs.free()
	var loaded_steps := { "pace_steps": [0.0] }
	BotBrain.add_pace(loaded_steps, BotBrain.PACE_NORMAL)
	_assert(loaded_steps["pace_steps"] == [BotBrain.PACE_CALM, BotBrain.PACE_NORMAL],
		"and a step bought after a load joins a list of whole steps (%s)"
			% str(loaded_steps["pace_steps"]))
	ss.done()

	# Exercise the complete ownership model without inventing bold's production
	# price. The catalogue is restored before any other case.
	var held_prices := ShelfDefs.PACE_PRICES.duplicate()
	ShelfDefs.PACE_PRICES = [150, 200, 300]
	var ordered := _shelf_yard(12902)
	var os: LiveSession = ordered["s"]
	var ob := String(ordered["bot"])
	var obench: Vector2i = ordered["bench"]
	os.gs.gold = 1000
	var bought_in_order := true
	for step in [BotBrain.PACE_CALM, BotBrain.PACE_BOLD]:
		var purchase := _buy_pace(os, ob, obench, step)
		bought_in_order = bought_in_order and purchase.get("ok", false) \
			and BotBrain.owns_pace(os.world.actor(ob)["extra"], step)
	_assert(bought_in_order
			and os.world.actor(ob)["extra"].get("pace_steps", []) == [0, 2]
			and BotBrain.owns_pace(os.world.actor(ob)["extra"], BotBrain.PACE_NORMAL),
		"calm and bold can be bought while normal remains owned without purchase")
	os.done()
	ShelfDefs.PACE_PRICES = held_prices

	var recorded := _shelf_yard(12899)
	var rs: LiveSession = recorded["s"]
	var rb := String(recorded["bot"])
	rs.gs.gold = 500
	rs.rebase()
	_buy_pace(rs, rb, recorded["bench"], BotBrain.PACE_CALM)
	_set_pace(rs, rb, BotBrain.PACE_CALM)
	var replay_gold = load("res://systems/game_state.gd").new()
	var replay_world := SimWorld.new()
	var pace_replay := ReplayLog.from_json(rs.log.to_json())
	pace_replay.apply_to(replay_world, replay_gold)
	_assert(pace_replay.divergence == ""
			and SaveGame.capture_canonical(replay_world, replay_gold)
				== SaveGame.capture_canonical(rs.world, rs.gs),
		"a separately bought pace step replays to the same farm and robot")
	replay_gold.free()
	rs.done()

	# --- what buying refuses ---------------------------------------------------
	var yard := _shelf_yard(12901)
	var s: LiveSession = yard["s"]
	var bot := String(yard["bot"])
	var bench: Vector2i = yard["bench"]
	_assert(s.world.get_object(bench.x, bench.y) == WorldLayout.WORKBENCH,
		"a bench stands in the yard (%s)" % str(bench))
	var away := _shelf_buy(s, bot, MK3_SPOT)
	_assert(not away.get("ok", true) and String(away.get("reason", "")) == "no_workbench",
		"bought anywhere but at a bench, it is refused as no_workbench (%s)"
			% String(away.get("reason", "")))
	var junk := _shelf_buy(s, bot, bench, "nonsense")
	_assert(not junk.get("ok", true) and String(junk.get("reason", "")) == "not_offered",
		"a thing the shelf does not sell is refused as not_offered")
	var hen := _shelf_buy(s, SimWorld.ACTOR_CHICKEN, bench)
	_assert(not hen.get("ok", true) and String(hen.get("reason", "")) == "not_a_learner",
		"and only a learning robot can be bought for (%s)" % String(hen.get("reason", "")))
	var early_pace := _set_pace(s, bot, BotBrain.PACE_BOLD)
	_assert(not early_pace.get("ok", true)
			and String(early_pace.get("reason", "")) == "not_owned",
		"a robot nobody bought the pace setting for cannot be set bold (%s)"
			% String(early_pace.get("reason", "")))
	s.gs.gold = 149
	var short := _shelf_buy(s, bot, bench)
	_assert(not short.get("ok", true) and String(short.get("reason", "")) == "no_gold"
			and s.gs.gold == 149,
		"a gold short, it is refused as no_gold and costs nothing (%d left)" % s.gs.gold)
	_assert(not BotBrain.has_upgrade(s.world.actor(bot)["extra"], "pace"),
		"and none of those refusals gave the robot anything")

	# --- buying it -------------------------------------------------------------
	s.gs.gold = 1000
	var energy_before: int = s.gs.energy
	var clock_before: int = s.gs.actions_today
	var bought := _shelf_buy(s, bot, bench)
	var extra: Dictionary = s.world.actor(bot)["extra"]
	_assert(bought.get("ok", false) and s.gs.gold == 850
			and BotBrain.has_upgrade(extra, "pace"),
		"at the bench with 1000 gold, she buys it: 850 left, and the robot has it (%s)"
			% str(bought))
	_assert(s.gs.energy == energy_before and s.gs.actions_today == clock_before,
		"an errand at the bench costs no energy and does not move the day's clock")
	_assert(BotBrain.pace_of(extra) == BotBrain.PACE_NORMAL and not extra.has("pace"),
		"it starts on normal, which is stored as nothing — buying alone changes no night")
	var twice := _shelf_buy(s, bot, bench)
	_assert(not twice.get("ok", true) and String(twice.get("reason", "")) == "already_owned"
			and s.gs.gold == 850,
		"a second purchase for the same robot is refused as already_owned, at no cost")
	_assert(_json_plain(extra), "and what it owns is plain JSON, like everything on the robot")

	# --- setting the pace ------------------------------------------------------
	for wrong in [-1, 3]:
		var bad := _set_pace(s, bot, wrong)
		_assert_quiet(not bad.get("ok", true) and String(bad.get("reason", "")) == "bad_pace",
			"pace %d is refused as bad_pace" % wrong)
	_flush_quiet("a pace off the three steps is refused as bad_pace")
	var bolder := _set_pace(s, bot, BotBrain.PACE_BOLD)
	_assert(bolder.get("ok", false) and int(bolder.get("previous", -1)) == BotBrain.PACE_NORMAL
			and BotBrain.pace_of(extra) == BotBrain.PACE_BOLD,
		"she sets it bold, and the Action says what it was before (%s)" % str(bolder))
	_assert(s.gs.energy == energy_before and s.gs.actions_today == clock_before,
		"setting it is an instruction, free and off the clock")
	_set_pace(s, bot, BotBrain.PACE_NORMAL)
	_assert(not extra.has("pace"),
		"and set back to normal it carries no key at all — the same robot as one never touched")

	# --- per robot (S-29) ------------------------------------------------------
	s.gs.gold = 2000
	s.act({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" })
	var second := String(s.act({ "verb": "place", "target": MK3_SPOT + Vector2i(3, 0),
		"item": "bot_mk3", "actor": "player" }).get("machine", ""))
	_assert(second != "" and not BotBrain.has_upgrade(s.world.actor(second)["extra"], "pace"),
		"a second Mark III on the same farm has not been bought it (%s)" % second)
	var theirs := _set_pace(s, second, BotBrain.PACE_BOLD)
	_assert(not theirs.get("ok", true) and String(theirs.get("reason", "")) == "not_owned",
		"so its pace cannot be set until it is bought for that robot too")
	s.done()

	# --- normal is today's night, to the bit -----------------------------------
	# Four robots on one seed: never touched; bought the setting and left on normal
	# after a trip to bold and back; bold; and calm. Pace acts only at night, so
	# their first minute is the same minute. After the night the first two are the
	# same robot weight for weight, calm has moved less and bold more.
	var arms := {
		"plain": -1, "normal": BotBrain.PACE_NORMAL, "bold": BotBrain.PACE_BOLD,
		"calm": BotBrain.PACE_CALM,
	}
	var twins: Array = []
	for arm in ["plain", "normal", "bold", "calm"]:
		var t := _shelf_yard(12902)
		var ts: LiveSession = t["s"]
		var tb := String(t["bot"])
		if int(arms[arm]) >= 0:
			_shelf_buy(ts, tb, t["bench"])
			_set_pace(ts, tb, BotBrain.PACE_BOLD)
			_set_pace(ts, tb, int(arms[arm]))
		ts.tick(SimClock.RATE * 60)
		twins.append(t)
	var day_scores: Array = []
	for t in twins:
		day_scores.append(float(t["s"].world.actor(t["bot"])["extra"]["score"]))
	_assert(day_scores[0] == day_scores[1] and day_scores[0] == day_scores[2]
			and day_scores[0] == day_scores[3],
		"four robots on one seed play the same first minute whatever their pace (%s)"
			% str(day_scores))
	_assert(float(day_scores[0]) > 0.0 and float(day_scores[0]) < BotBrain.LEARN_DAY_REF,
		"a small day with something in it, under the day-size reference (%.1f < %.1f)"
			% [float(day_scores[0]), BotBrain.LEARN_DAY_REF])
	var moved: Array = []
	for t in twins:
		t["s"].gs.weather = "sunny"
		t["s"].act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
		moved.append(float(t["s"].world.actor(t["bot"])["extra"]["last_update"]))
	var w_plain: Array = twins[0]["s"].world.actor(twins[0]["bot"])["extra"]["weights"]
	var w_normal: Array = twins[1]["s"].world.actor(twins[1]["bot"])["extra"]["weights"]
	_assert(w_plain == w_normal and w_plain.size() > 0,
		"after the night, normal pace is the untouched robot weight for weight (%d weights)"
			% w_plain.size())
	_assert(float(moved[3]) < float(moved[1]) and float(moved[1]) < float(moved[2]),
		"and on a small day calm moves it less and bold more: %.4f, %.4f, %.4f"
			% [float(moved[3]), float(moved[1]), float(moved[2])])
	for t in twins:
		t["s"].done()

	# --- a big day cannot be pushed harder -------------------------------------
	# The failure the day-size guard fixed (S-26): a hard push on a day three times
	# the size the rate was tuned on ended a week below a robot that never learned.
	# Bold rides under the same guard, so on such a day it moves the robot exactly
	# as far as normal does — whatever bold adds, it adds on small days only.
	var big: Array = []
	for pace in [BotBrain.PACE_NORMAL, BotBrain.PACE_BOLD]:
		var t := _shelf_yard(12903)
		var ts: LiveSession = t["s"]
		var tb := String(t["bot"])
		_shelf_buy(ts, tb, t["bench"])
		_set_pace(ts, tb, pace)
		ts.tick(SimClock.RATE * 60)
		var ex: Dictionary = ts.world.actor(tb)["extra"]
		ex["score"] = BotBrain.LEARN_DAY_REF * 3.0
		ts.gs.weather = "sunny"
		ts.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
		big.append((ex["weights"] as Array).duplicate())
		ts.done()
	_assert(big[0] == big[1],
		"on a day of %d points a bold night moves the robot exactly as far as a normal one"
			% int(BotBrain.LEARN_DAY_REF * 3.0))

	# --- the disk, the crate and a replay --------------------------------------
	var kept := _shelf_yard(12904)
	var ks: LiveSession = kept["s"]
	var kb := String(kept["bot"])
	_shelf_buy(ks, kb, kept["bench"])
	_set_pace(ks, kb, BotBrain.PACE_BOLD)
	ks.tick(SimClock.RATE * 20)
	var snapshot = JSON.parse_string(JSON.stringify(SaveGame.capture(ks.world, ks.gs)))
	var gs_back = load("res://systems/game_state.gd").new()
	gs_back.reset()
	var restored := SimWorld.new()
	_assert(SaveGame.restore(snapshot, restored, gs_back), "a farm with a paced Mark III saves")
	var back_extra: Dictionary = restored.actor(kb)["extra"]
	_assert(BotBrain.has_upgrade(back_extra, "pace")
			and BotBrain.pace_of(back_extra) == BotBrain.PACE_BOLD,
		"and the robot comes back owning the setting and still bold")
	_assert(SaveGame.capture_canonical(restored, gs_back)
			== SaveGame.capture_canonical(ks.world, ks.gs),
		"the restored farm is the saved farm")
	gs_back.free()
	var lifted := ks.act({ "verb": "collect", "target": ks.world.actor_pos(kb),
		"actor": "player" })
	var boxed: Array = ks.gs.boxed.get("bot_mk3", [])
	_assert(lifted.get("ok", false) and boxed.size() == 1
			and BotBrain.has_upgrade(boxed[0], "pace")
			and BotBrain.pace_of(boxed[0]) == BotBrain.PACE_BOLD,
		"picked up, the crate keeps what she bought it and its pace (Q-98)")
	var down_id := String(ks.act({ "verb": "place", "target": Vector2i(5, 5),
		"item": "bot_mk3", "actor": "player" }).get("machine", ""))
	_assert(down_id != ""
			and BotBrain.pace_of(ks.world.actor(down_id)["extra"]) == BotBrain.PACE_BOLD,
		"and set down elsewhere, it is still bold")
	ks.done()

	var yard_live := _shelf_yard(12905)
	var live: LiveSession = yard_live["s"]
	var lb := String(yard_live["bot"])
	live.rebase()
	_shelf_buy(live, lb, yard_live["bench"])
	_set_pace(live, lb, BotBrain.PACE_BOLD)
	live.tick(SimClock.RATE * 40)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	_set_pace(live, lb, BotBrain.PACE_CALM)
	live.tick(SimClock.RATE * 30)
	live.gs.weather = "sunny"
	live.act({ "verb": "sleep", "actor": "world", "weather": "sunny" })
	var live_canonical := SaveGame.capture_canonical(live.world, live.gs)
	var gs_again = load("res://systems/game_state.gd").new()
	var again := SimWorld.new()
	var replayed := ReplayLog.from_json(live.log.to_json())
	replayed.apply_to(again, gs_again)
	_assert(replayed.divergence == "",
		"a session that bought the setting, went bold for a night and calm the next recomputes cleanly (%s)"
			% replayed.divergence)
	_assert(SaveGame.capture_canonical(again, gs_again) == live_canonical,
		"landing on the same farm, the same gold and the same robot")
	_assert(BotBrain.pace_of(again.actor(lb)["extra"]) == BotBrain.PACE_CALM,
		"left on calm, where she left it")
	gs_again.free()
	live.done()



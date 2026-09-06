# robot_session.gd — Automated end-to-end human-path regression (post-M2)
# Run: godot --headless --path . res://tools/robot_session.tscn
#
# Plays the REAL game the way a player does — simulated taps through
# InputManager, the keyboard, the shop menu, the machine panel, the door and the
# day-cycle transition — then verifies that the session's replay log reproduces
# its autosave exactly. Uses robot-only save paths so a real player's files are
# never touched.
#
# One session, one played day, and it now crosses every seam the game has:
#
#   the cold open  →  a keyboard walk out through a parcel gate  →  a row worked
#   with taps  →  a shed and a robot bought in the shop and set down  →  a lesson
#   taught with a finger  →  a walk home through her own front door onto page 1
#   →  the bed  →  the morning, which sends the machine out with nobody touching
#   anything  →  the round it works and the bay it parks in
#
# The last two are why the stall chapter lives here rather than in a scenario:
# the whole value of the shed is a chain that *crosses a night*, and this is the
# one harness that plays a day and then proves the recording of it.
extends Node2D

const ROBOT_SAVE := "user://robot_autosave.json"
const ROBOT_REPLAY := "user://robot_session_replay.json"

# T-32: the yard is home, not field. There is no longer anything inside the fence
# a hoe will open, so the robot's day of work happens on the other side of the
# gate the cold open leaves open — (12,5) is the first square of the neighbour's
# plot, one step past the gate, untouched by her demo row (which starts at x=14).
#
# This is a better session than the one it replaces, and not only because it had
# to move. The robot used to work the tile it spawned beside and never went
# anywhere: it now walks the length of the yard on the keyboard, **through a
# parcel gate**, works, and walks home — so the free-walk events in the log are a
# real journey and the boundary crossing is regression-covered for the first time.
const WORK_TILE := Vector2i(12, 5)
const GATE_ROW := 4                  # the cold open's gate is (11,4)
const OUTBOUND_COL := 4              # clear of the cot's column on the way down

# --- the stall chapter (2026-09-06) -------------------------------------------
#
# The farm grew a shed she can employ a machine out of, and the whole value of it
# is that **nobody taps anything**: she parks a robot, teaches it a couple of
# squares, goes to bed, and the morning sends it. That is a chain across a day
# boundary, and a day boundary is exactly the seam a scenario in a scene tree does
# not get to cross casually — so it belongs here, in the one harness that plays a
# whole day and then proves the recording of it.
#
# Where: two free squares at the top of the neighbour's plot, well clear of the
# demo row she inherited and of the tile she works herself. The plot is fixed
# content (no scatter, no density), so these coordinates are as deterministic as
# WORK_TILE is.
const STALL_TILE := Vector2i(13, 2)

# What she teaches it. **The neighbour left these tilled**, which is why they are
# the two: one tap each plants them, so the robot's round is a row she made with
# two taps rather than a staged fixture, and they go to bed seeded and dry.
const BOT_ROW := [Vector2i(14, 5), Vector2i(15, 5)]

# The purse she starts the session with — a stall (80g) and a mark-1 (150g) with
# change. Staged **before the game boots**, and the replay is anchored to a base
# save taken at boot (see `_ready`), so the reproduction starts with the same
# money in the same pocket. Earning 230 gold honestly is sixteen harvests, which
# is sixteen days this run does not have.
const OPENING_PURSE := 400

# A walk of a dozen tiles at 3 tiles/sec is seconds of game time, and a headless
# frame is short, so the legs below need a budget in the thousands rather than the
# 300 frames a tap-and-act needs. Generous on purpose: it is a timeout, not a
# schedule, and every use of it prints the tile she actually reached on failure.
const WALK_FRAMES := 4000

# The tap-and-act budget: enough frames for her to walk across a plot to whatever
# she tapped and then swing at it.
const ACT_FRAMES := 1200

# The morning after, pumped one frame at a time through `main.gd`'s own clock.
# Each frame is MAX_TICKS_PER_FRAME ticks — 0.4 s of sim time — so this is four
# minutes of farm, which is what a robot needs to walk out to a two-tile round
# three rows away and park itself back in its bay.
const MORNING_FRAMES := 700

var main_scene: Node2D
var player: Node2D
var failed := false


func _ready() -> void:
	print("=".repeat(60))
	print("TINY FARM — Robot Session (end-to-end human-path regression)")
	print("=".repeat(60))

	# Isolate saves BEFORE the game boots
	GameState.save_path = ROBOT_SAVE
	GameState.replay_path = ROBOT_REPLAY
	for path in [ROBOT_SAVE, ROBOT_REPLAY]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	# The purse, before the game boots: `main.gd` never resets GameState, so this
	# is the balance the session opens with and the balance its base save records.
	GameState.gold = OPENING_PURSE

	main_scene = preload("res://main.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main_scene.player

	# **Anchor the replay to the farm as it stands right now**, which is the
	# `Continue`-from-a-save path (`main.gd` takes it whenever a player taps
	# Continue) rather than a private door. A log started from a seed alone
	# reproduces a session by regenerating the world and resetting GameState to its
	# defaults — and defaults mean an empty purse, so the reproduction could not buy
	# the shed the recording buys. Re-anchoring costs nothing: nothing has been
	# played yet, so the entries this replaces are none, and everything below —
	# the cold open included — is recorded into the new log and replayed out of it.
	#
	# The reseed is the other half of the pairing: `ReplayLog.apply_to` restores the
	# base save and then reseeds to the world's own `gen_seed`, so the live session
	# has to stand on that same seed for the two RNG streams to agree.
	SimRng.reseed(main_scene.farm.sim.gen_seed)
	main_scene.farm.start_replay_log_from_save(
		SaveGame.capture(main_scene.farm.sim, GameState), main_scene.farm.sim.gen_seed)
	_check(GameState.gold == OPENING_PURSE,
		"she opens the session with %d gold, and the base save carries it" % GameState.gold)

	# T-13: a fresh farm starts inside the cold open, so the robot plays through
	# it the way the game does — by applying the derived actions to the real
	# gateway — rather than hacking the gate open. That way this run also proves
	# the opening replays, which is the property that makes it free.
	_check(not ColdOpen.is_done(main_scene.farm.sim), "a fresh farm starts before the gate opens")
	var opening := ColdOpen.run(main_scene.farm, main_scene.farm.sim, GameState)
	_check(opening.get("ok", false), "the cold open ran to completion (%d actions)" % opening.get("steps", -1))
	_check(ColdOpen.is_done(main_scene.farm.sim), "and left the gate open")
	_check(GameState.takeover_day == GameState.day, "the player's day 1 is anchored at the handover")
	var neighbour_entries := 0
	for e in main_scene.farm.replay.entries:
		if String(e.get("actor", "")) == "neighbour":
			neighbour_entries += 1
	# She is recorded, not recomputed, and that is deliberate: her *pacing* is a
	# fact about a camera and a viewport (M2.5 WI-3 deviation 7), so she is the
	# one NPC no clock can reproduce. The brains that *are* on the clock are
	# checked at the bottom of this run, where the replay recomputes them and the
	# dual-record net compares the two streams (WI-5).
	_check(neighbour_entries > 0, "her work is in the replay as actor 'neighbour' (%d entries)" % neighbour_entries)
	await get_tree().process_frame

	# Out to the work. The keyboard is the second input modality and since M2.5
	# WI-6 the thing that puts free-walk events in the log and moves her registry
	# entry, so the journey is deliberately hers rather than a tap's: right along
	# the top of the yard, down the column beside the shipping bin (the cot's own
	# column is blocked by the cot now), then east through the open gate.
	Input.action_press("move_right")
	var east := await _wait_until(
		func(): return player.get_tile_pos().x >= OUTBOUND_COL, WALK_FRAMES)
	Input.action_release("move_right")
	_check(east, "keyboard walk carried her along the yard (tile %s)" % player.get_tile_pos())
	await get_tree().process_frame
	Input.action_press("move_down")
	var south := await _wait_until(
		func(): return player.get_tile_pos().y >= GATE_ROW, WALK_FRAMES)
	Input.action_release("move_down")
	_check(south, "and down to the gate's row (tile %s)" % player.get_tile_pos())
	await get_tree().process_frame
	Input.action_press("move_right")
	var through := await _wait_until(
		func(): return player.get_tile_pos().x >= WORK_TILE.x, WALK_FRAMES)
	Input.action_release("move_right")
	_check(through, "and out through the open gate onto the neighbour's plot (tile %s)"
		% player.get_tile_pos())
	await get_tree().process_frame
	_check(main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER) == player.get_tile_pos(),
		"and the registry knows it — her tile is sim truth now (%s)"
			% main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER))

	# A short day of real play: till, plant, water the same tile via taps.
	_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state == "cleared",
		"the work tile is bare field, ready for a hoe (%s)"
			% main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state)
	await _tap_and_wait(WORK_TILE)   # till (auto-selects hoe)
	_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state == "tilled", "tap tilled the tile")
	await _tap_and_wait(WORK_TILE)   # plant
	_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).state == "seeded", "tap planted the tile")
	# On a rainy day the freshly planted tile is already wet (2026-09-07: rain
	# falls all day, not only at dawn), so the water tap resolves as "already
	# done" and no action animates — which is exactly right. Only expect the
	# pour when there is something to pour on.
	if String(GameState.weather) == "rainy":
		_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).watered_today,
			"the rain already watered the fresh planting — no tap needed")
	else:
		await _tap_and_wait(WORK_TILE)   # water
		_check(main_scene.farm.get_tile(WORK_TILE.x, WORK_TILE.y).watered_today, "tap watered the tile")

	# --- she hires a machine ---------------------------------------------------
	#
	# Two squares the neighbour left tilled become the robot's round: one tap each
	# puts wheat in them, and they go to bed seeded and **dry**. Her own square is
	# two tiles west along the same row and is watered, so the two states sitting
	# side by side are the difference the machine is there to make.
	for t in BOT_ROW:
		await _tap_and_wait(t)
		_check(main_scene.farm.get_tile(t.x, t.y).state == "seeded",
			"a tap plants the row she is going to hand over — %s is %s"
				% [t, main_scene.farm.get_tile(t.x, t.y).state])
	var mk1 := await _employ_a_robot()

	# Home to bed, and **the game says which way that is**. `way_to_bed()` answers
	# with the front door while she is in the yard and with the bed once she is in
	# the room with it, so the same question asked twice is the whole two-press
	# chain — and nothing here knows where either of them is. That matters more than
	# it used to: the bed moved indoors on 2026-09-06 and the old route (walk west
	# along row 4 until the cot stops her) walked her into the map border instead.
	var to_the_door: Vector2i = main_scene.way_to_bed()
	_check(to_the_door == main_scene.farm.sim.find_object(WorldLayout.HOUSE_DOOR),
		"from out here, the way to bed is her own front door (%s)" % to_the_door)
	InputManager.click_tile = to_the_door
	InputManager.has_click = true
	var indoors := await _wait_until(
		func(): return main_scene.farm.sim.page_of(player.get_tile_pos()) == 1, WALK_FRAMES)
	_check(indoors, "one tap walks her the length of the farm and through it (tile %s)"
		% player.get_tile_pos())
	_check(main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER) == player.get_tile_pos(),
		"and the registry followed her indoors — which room she is in is sim truth (%s)"
			% main_scene.farm.sim.actor_pos(SimWorld.ACTOR_PLAYER))

	var to_the_bed: Vector2i = main_scene.way_to_bed()
	_check(main_scene.farm.get_object(to_the_bed.x, to_the_bed.y) == "cot",
		"and from in here the same question answers with the bed (%s)" % to_the_bed)
	InputManager.click_tile = to_the_bed
	InputManager.has_click = true

	# Takeover-relative: the calendar day is 1 + COLD_OPEN_DAYS by now, and what
	# matters is that *her* second day has begun. The Action resolves at the tap
	# (D-8), so the day turns before the transition finishes playing — which is
	# exactly the instant the morning routine below has to be read at.
	var turned := await _wait_until(func(): return GameState.play_day() == 2, WALK_FRAMES)
	_check(turned, "tapping the bed turns the day")
	if not turned:
		var pt: Vector2i = player.get_tile_pos()
		print("  [diag] day=%d day_cycle.state=%s player_t=%s bed=%s obj@bed=%s" % [
			GameState.day, main_scene.day_cycle.state, pt, to_the_bed,
			main_scene.farm.get_object(to_the_bed.x, to_the_bed.y)])
		print("  [diag] resolve(bed)=", ActionRouter.resolve(main_scene.farm, GameState, to_the_bed, pt, false))

	# --- and the morning does the sending --------------------------------------
	#
	# The point of the 80 gold. Read here rather than after the transition, because
	# `sent` is a flag that clears itself the moment the machine is parked again:
	# what is being checked is that the *day turn* raised it, with nobody's finger
	# anywhere near the farm.
	var extra: Dictionary = main_scene.farm.sim.actor(mk1)["extra"]
	_check(bool(extra.get("sent", false)) and bool(extra.get("ran_today", false)),
		"and while she slept the robot let itself out — that is its turn for the day, spent by the morning")
	var send_taps := 0
	for e in main_scene.farm.replay.entries:
		if String(e.get("verb", "")) == "activate":
			send_taps += 1
	_check(send_taps == 0,
		"nobody sent it: the session recorded no send at all (%d activate entries)" % send_taps)

	var slept := await _wait_until(func(): return not main_scene.day_cycle.is_active(), 600)
	_check(slept, "the transition played out and the new day is hers")
	# The autosave/replay write happens in the sleep callback; give it a frame
	await get_tree().process_frame
	_check(FileAccess.file_exists(ROBOT_SAVE), "autosave written")
	_check(FileAccess.file_exists(ROBOT_REPLAY), "session replay written")

	# Then let the farm live a while (M2.5 WI-5). Everything above takes about two
	# seconds of sim time, and in two seconds the hen decides almost nothing — so a
	# robot session that stopped at the sleep would hand the dual-record net an
	# empty stream to agree with, which is a green light that means nothing.
	#
	# It is also the robot's whole working morning, which is the second reason the
	# tail is longer than it was: the machine has to walk out to its round, water
	# it and park itself again inside these frames, and every Action it takes on
	# the way is another entry the reproduction has to arrive at independently.
	#
	# Sim time is driven through `main.gd`'s own pump, one call per frame with the
	# frame cap it applies to a real one, so this is the same path a slow tablet
	# frame takes rather than a private door into the clock. Then the session is
	# persisted again: the save and the replay are written together, which is the
	# pairing everything below verifies.
	var ticks_before: int = main_scene.farm.sim.clock.tick
	for _i in MORNING_FRAMES:
		main_scene._pump_sim_clock(float(main_scene.MAX_TICKS_PER_FRAME) / SimClock.RATE)
		await get_tree().process_frame
	main_scene.persist_session()
	_check(main_scene.farm.sim.clock.tick - ticks_before > 400,
		"the farm lived on after she slept (%d ticks of sim time)"
			% (main_scene.farm.sim.clock.tick - ticks_before))

	# **Read off the machine's own Actions, not off the ground.** A wet tile is
	# ambiguous evidence — a rainy morning marks every tilled square on the farm,
	# and the weather is a roll this session does not get to choose — so what is
	# checked is the water the *robot* poured: its recorded verbs, on the tiles it
	# was taught, in the log the reproduction below has to arrive at independently.
	var poured: Array[Vector2i] = []
	for e in main_scene.farm.replay.entries:
		if String(e.get("actor", "")) != mk1 or String(e.get("verb", "")) != "water":
			continue
		var at = e.get("target", [])
		if at is Array and at.size() == 2:
			poured.append(Vector2i(int(at[0]), int(at[1])))
	var watered := 0
	for t in BOT_ROW:
		if t in poured and main_scene.farm.get_tile(t.x, t.y).get("watered_today", false):
			watered += 1
	_check(watered == BOT_ROW.size(),
		"the round happened: the machine watered %d of the %d tiles it was taught, while she was in bed"
			% [watered, BOT_ROW.size()])
	_check(main_scene.farm.sim.actor_pos(mk1) == STALL_TILE,
		"and the machine walked itself home to its bay afterwards (%s)"
			% main_scene.farm.sim.actor_pos(mk1))
	_check(not bool(main_scene.farm.sim.actor(mk1)["extra"].get("sent", false)),
		"round over, parked, ready to do it again tomorrow without being asked")

	# Verify: replay the robot's own session against its autosave
	var rlog := ReplayLog.load_from(ROBOT_REPLAY)
	var save := SaveGame.load_dict(ROBOT_SAVE)
	if rlog == null or save.is_empty():
		_check(false, "robot files loadable")
	else:
		_check(rlog.version >= 2, "the session recorded in replay format v%d" % rlog.version)
		var brain_entries := 0
		var walk_entries := 0
		for e in rlog.entries:
			if bool(e.get("brain", false)):
				brain_entries += 1
			if ReplayLog.is_walk(e):
				walk_entries += 1
		# The switch WI-5 armed and WI-6 flipped: her walk is in the log, and the
		# state comparison below is what checks it — her tile is inside
		# `capture_canonical` now, so a replay that lost track of where she walked
		# fails here rather than being quietly excluded.
		_check(walk_entries > 0,
			"her free walk is in the replay as tile-crossing events (%d)" % walk_entries)
		var report := SaveGame.replay_report(rlog, save)
		# The dual-record net (M2.5 WI-5, plan §4). The replay advanced the clock
		# through the session's own ticks, so every brain on it decided again —
		# and this is the assertion that it decided the *same things*, in the same
		# order, on the same ticks. A refactor that changes what the hen does now
		# fails here, naming the entry, rather than showing up as a farm that is
		# subtly wrong somewhere.
		_check(String(report.get("divergence", "")) == "",
			"recomputation matches the recording, action for action (%d brain entries) %s" % [
				brain_entries, report.get("divergence", "")])
		_check(report.get("state_matched", false),
			"robot session replay MATCHES its autosave (%d entries, %d ticks)" % [
				rlog.entries.size(), rlog.end_tick])

	print("=".repeat(60))
	print("Results: %s" % ("FAILED" if failed else "PASSED"))
	print("=".repeat(60))
	get_tree().quit(1 if failed else 0)


# The shop, the shed, the robot standing in it and the lesson — driven the way a
# player drives them: cards in the real shop menu, taps on the real farm through
# InputManager, rows in the real machine panel. Returns the machine's id.
#
# Nothing here sends it anywhere. That omission is the point of the chapter: the
# only thing between the lesson and a watered row tomorrow is her going to bed.
func _employ_a_robot() -> String:
	var menus = main_scene.menus

	_check(await _buy("stall"),
		"she buys a robot stall from the shop (%d gold left)" % GameState.gold)
	var built := await _tap_until(STALL_TILE, func():
		return main_scene.farm.get_object(STALL_TILE.x, STALL_TILE.y) == WorldLayout.ROBOT_STALL)
	_check(built, "and a tap builds it where she pointed (%s)" % STALL_TILE)
	_check(main_scene.farm.get_object(STALL_TILE.x + 1, STALL_TILE.y)
			== WorldLayout.ROBOT_STALL_SLOT,
		"its second bay lands beside it — one shed, two tiles")

	_check(await _buy("bot_mk1"),
		"she buys a mark-1 to live in it (%d gold left)" % GameState.gold)
	var parked := await _tap_until(STALL_TILE, func():
		return main_scene.farm.sim.machine_at(STALL_TILE) != "")
	_check(parked, "and a tap stands it in the bay")
	var mk1: String = main_scene.farm.sim.machine_at(STALL_TILE)
	var extra: Dictionary = main_scene.farm.sim.actor(mk1)["extra"]
	_check(int(extra.get("home_x", -1)) == STALL_TILE.x
			and int(extra.get("home_y", -1)) == STALL_TILE.y,
		"which gives it an address — the bay it was parked in (%s)" % STALL_TILE)

	# Its panel opens as it lands, and the teach row is the way into the lesson.
	var opened := await _wait_until(func(): return menus.active_menu == "machine", 300)
	_check(opened, "its panel opens on top of it, which is where she teaches it")
	var teach_row := -1
	for i in menus.machine_options.size():
		if String(menus.machine_options[i].get("kind", "")) == "teach":
			teach_row = i
	if teach_row < 0:
		_check(false, "the mark-1's panel offers a teach row")
		return mk1
	menus.selected_option = teach_row
	menus._select_current_option()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main_scene.is_teaching() and not menus.is_open() and not get_tree().paused,
		"tapping it puts her in teaching mode, with the panel out of the way")

	# Pointing, not walking: a taught tile costs her nothing and has no distance.
	var energy_before: int = GameState.energy
	for t in BOT_ROW:
		InputManager.click_tile = t
		InputManager.has_click = true
		await get_tree().process_frame
		await get_tree().process_frame
	_check(str(BotBrain.orders_of(main_scene.farm.sim.actor(mk1)["extra"])) == str(BOT_ROW),
		"she points at its round and it takes the tiles in the order she pointed (%s)"
			% str(BotBrain.orders_of(main_scene.farm.sim.actor(mk1)["extra"])))
	_check(GameState.energy == energy_before, "and it cost her nothing — pointing is not a chore")

	main_scene.hud._on_teach_done_button()
	await get_tree().process_frame
	_check(not main_scene.is_teaching(), "the done button ends the lesson")
	_check(not bool(main_scene.farm.sim.actor(mk1)["extra"].get("sent", false)),
		"and she sends it nowhere — there is no send tap in this session")
	return mk1


# One card, bought from the real shop menu. The menu pauses the tree while it is
# open, so it is closed again before anything taps the farm.
func _buy(item: String) -> bool:
	var menus = main_scene.menus
	menus.open_menu("shop")
	await get_tree().process_frame
	var card := -1
	for i in menus.shop_items.size():
		if String(menus.shop_items[i].get("seed_type", "")) == item:
			card = i
	if card < 0:
		return false
	menus.selected_option = card
	menus._select_current_option()
	await get_tree().process_frame
	menus.close_menu()
	await get_tree().process_frame
	return GameState.selected_seed_type == item and GameState.holding_machine()


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ✓ " + label)
	else:
		failed = true
		print("  ✗ FAIL: " + label)


func _tap_and_wait(tile: Vector2i) -> void:
	await _walk_beside(tile)
	InputManager.click_tile = tile
	InputManager.has_click = true
	var acted := await _wait_until(func(): return player.is_acting, ACT_FRAMES)
	if not acted:
		_check(false, "tap at %s produced an action" % tile)
		print("  [diag] player_t=%s path=%d pending=%s approach=%s tile=%s seeds=%s sel=%s energy=%d" % [
			player.get_tile_pos(), player.path.size(), player.pending_action,
			player.approach_target, main_scene.farm.get_tile(tile.x, tile.y),
			GameState.seeds, GameState.selected_seed_type, GameState.energy])
		print("  [diag] resolve=", ActionRouter.resolve(
			main_scene.farm, GameState, tile, player.get_tile_pos(), false))
		return
	await _wait_until(func(): return not player.is_acting, ACT_FRAMES)


# The same tap, for the verbs that never raise `is_acting` — setting a machine
# down returns before the swing does (`player.gd`'s `place` block), so what says
# the tap landed is the farm changing rather than the farmer moving.
func _tap_until(tile: Vector2i, done: Callable) -> bool:
	await _walk_beside(tile)
	InputManager.click_tile = tile
	InputManager.has_click = true
	return await _wait_until(done, ACT_FRAMES)


# **A far tap is a walk order, and the tap that acts is the second one** — the
# router's intent filter (Q-30): a tap on workable ground more than one tile away
# resolves to nothing at all, so she walks to the edge of it and stops, and the
# tap she makes from there is the one that swings. That is how a finger plays this
# game, so it is how the robot plays it; the alternative — one tap that walks and
# then acts — is a game this one deliberately is not.
#
# Costs nothing when she is already beside the tile, which is every tap in the
# original session and is why this was never needed until the robot started
# working a row instead of a square.
func _walk_beside(tile: Vector2i) -> void:
	if _reach_of(tile) <= 1:
		return
	InputManager.click_tile = tile
	InputManager.has_click = true
	var arrived := await _wait_until(
		func(): return _reach_of(tile) <= 1 and player.path.is_empty(), WALK_FRAMES)
	if not arrived:
		_check(false, "she could walk to %s (stopped at %s)" % [tile, player.get_tile_pos()])


func _reach_of(tile: Vector2i) -> int:
	var here: Vector2i = player.get_tile_pos()
	return absi(here.x - tile.x) + absi(here.y - tile.y)


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await get_tree().process_frame
	return false

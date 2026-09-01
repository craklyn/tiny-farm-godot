extends Node2D

var _pass_count: int = 0
var _fail_count: int = 0
var _test_log: PackedStringArray = []

var main_scene: Node2D
var farm: Node2D
var player: Node2D

func _ready() -> void:
	print("=".repeat(60))
	print("TINY FARM — In-Situ Integration Test Runner")
	print("=".repeat(60))
	
	
	# Instantiate Main scene
	main_scene = preload("res://main.tscn").instantiate()
	add_child(main_scene)
	
	# Wait for systems to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	farm = main_scene.farm
	player = main_scene.player
	
	await _run_scenarios()
	
	print("")
	print("=".repeat(60))
	print("Results: %d PASSED, %d FAILED" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("FAILED TESTS:")
		for entry in _test_log:
			print("  " + entry)
	print("=".repeat(60))
	
	if _fail_count > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)

func _assert(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  ✓ %s" % test_name)
	else:
		_fail_count += 1
		_test_log.append("FAIL: %s" % test_name)
		print("  ✗ FAIL: %s" % test_name)

# --- Test Scenarios ---

func _run_scenarios() -> void:
	await _scenario_a()
	await _scenario_b()
	await _scenario_c()
	await _scenario_d()
	await _scenario_e()
	await _scenario_f()
	await _scenario_g()
	await _scenario_h_daylight()
	await _scenario_i_third_state()
	await _scenario_l_menu_holds_world()
	await _scenario_m_targets_on_screen()
	await _scenario_n_pick_up_the_axe()
	await _scenario_o_touch_has_no_hover()
	await _scenario_p_cold_open_waits()
	await _scenario_j_wordless_shop()
	await _scenario_k_attract()
	await _scenario_q_crow_is_sim_sent()
	await _scenario_r_attract_shows_the_neighbour()
	await _scenario_s_a_raid_is_drawn()
	await _scenario_t_the_bestiary_is_drawn()
	await _scenario_u_under_and_over()
	await _scenario_v_the_bot_is_drawn()
	await _scenario_w_the_cot_presents_itself()
	await _scenario_x_three_looks_for_the_cot()
	await _scenario_y_acorns_are_pickable()
	await _scenario_z_a_bed_button()
	await _scenario_aa_the_yard_is_home()
	await _scenario_ab_the_stations_present_themselves()
	await _scenario_ac_the_zoo()
	await _scenario_ae_the_home()
	await _scenario_ad_two_hud_findings()

func _wait_until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await get_tree().process_frame
	return false

# The action lock, waited out by condition on both edges rather than assumed to
# appear within exactly one frame. The begin-poll is bounded because instant
# verbs (sell, refill, collect) and refused actions never raise is_acting at
# all — a handful of frames is the difference between "wait for the swing" and
# "hang forever on a verb that has no swing".
func _wait_for_action() -> void:
	for i in 8:
		await get_tree().process_frame
		if player.is_acting:
			break
	while player.is_acting:
		await get_tree().process_frame


# Stage a tile for a scenario: the state it needs, and **nothing on it**.
#
# The under-load flake (M2.5 plan §9 item 12 — scenario E's harvest asserts,
# scenario H's "night stays soft", W's cot halo) was never a frame-timing race
# in the waits. It is the hen: every day turn gives her a 50% roll to lay an
# egg on a SimRng-drawn tile from *everywhere reachable* (Q-10, ChickenBrain),
# and the suite turns many days. An egg resolves to "collect" ahead of anything
# else on the tile (the T-30 object-wins rule), so a staged tile with an egg on
# it answers a tap or a press with the egg instead of the scenario's own setup —
# and the whole scenario fails on what looks like a lost input. Load matters
# only because it shifts how much sim time each frame carries, which moves the
# hen and her RNG stream, re-rolling where the eggs land; a quiet machine lands
# them on the same harmless tiles every run. So: a scenario that stages a tile
# claims the object layer too, and the lottery is out of the suite without
# touching the hen, who is behaving exactly as designed.
func _stage_tile(tx: int, ty: int, state: String, crop_type: String = "") -> void:
	farm.set_tile_state(tx, ty, state, crop_type)
	if farm.get_object(tx, ty) != "":
		farm.sim.set_object(tx, ty, "")

func _scenario_a() -> void:
	print("\n--- Scenario A: Movement & Collisions ---")
	
	# Initial position should be at spawn (2.5, 2.5 in tile coords, pos is px)
	var spawn_pos = player.position
	_assert(spawn_pos.distance_to(Vector2(2.5 * 16.0, 2.5 * 16.0)) < 1.0, "Player spawned at correct position")
	
	# Block the right side with a rock
	_stage_tile(3, 2, "obstacle_rock")
	
	# Press right for 10 frames
	Input.action_press("move_right")
	for i in 10: await get_tree().process_frame
	Input.action_release("move_right")
	
	# Should be blocked by the rock, x should be < 3.0 * 16.0 (minus player radius)
	var blocked_pos = player.position
	_assert(blocked_pos.x < (3.0 * 16.0) - 2.0, "Player collision blocked by obstacle_rock")
	
	# Move player to an open space
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)
	
func _scenario_b() -> void:
	print("\n--- Scenario B: Tool Cycling & Energy ---")
	
	var initial_tool = GameState.selected_tool
	
	Input.action_press("tool_next")
	await get_tree().process_frame
	Input.action_release("tool_next")
	await get_tree().process_frame
	
	# T-9 (Q-34): cycling skips the axe and pickaxe until they are acquired, so
	# "next" is the next tool she actually holds rather than the next index.
	_assert(GameState.selected_tool != initial_tool, "Tool cycled next")
	_assert(GameState.owns_tool(Tools.key_of(GameState.selected_tool)),
		"and landed on a tool she owns")
	
	GameState.set_energy(0)
	_assert(GameState.energy == 0, "Energy set to 0")

	# Ensure Hands tool
	GameState.selected_tool = 0

	# A weed rather than a rock: this scenario is about the energy floor, and a
	# rock now needs a pickaxe she has not earned (T-9), which would make it a
	# tool-ownership test wearing an energy test's name.
	_stage_tile(6, 5, "obstacle_weed")
	player.facing = "right"
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)

	# Hard energy (phase 2+ rule): action blocked at 0 energy
	GameState.hard_energy = true
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	_assert(farm.get_tile(6, 5).state == "obstacle_weed", "Action blocked when 0 energy (hard)")

	# Soft floor (phase 1 default, Q-11): same action works at 0 energy
	GameState.hard_energy = false
	GameState.selected_tool = 0
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	_assert(farm.get_tile(6, 5).state == "cleared", "Action allowed at 0 energy (soft floor)")
	_assert(GameState.energy == 0, "Soft floor keeps energy at 0, not negative")

	# Restore energy. `20` when this was written meant a full day; T-29 makes a day
	# 600 fine units, and 20 of those is not even one till.
	GameState.set_energy(GameState.max_energy)

func _scenario_c() -> void:
	print("\n--- Scenario C: Farming Loop (Hoe, Plant, Water) ---")
	
	# Start on cleared ground
	_stage_tile(6, 5, "cleared")
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)
	player.facing = "right"
	
	# 1. Hoe
	GameState.selected_tool = 3 # Hoe
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	var tile = farm.get_tile(6, 5)
	_assert(tile.state == "tilled", "Ground hoed to 'tilled'")
	
	# 2. Plant
	GameState.selected_tool = 5 # Seeds
	GameState.selected_seed_type = "wheat"
	GameState.seeds["wheat"] = 5
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	tile = farm.get_tile(6, 5)
	_assert(tile.state == "seeded", "Ground planted to 'seeded'")
	_assert(GameState.seeds["wheat"] == 4, "Seed consumed")
	
	# 3. Water
	GameState.selected_tool = 4 # Watering Can
	GameState.watering_can_charges = 5
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	tile = farm.get_tile(6, 5)
	_assert(tile.watered_today == true, "Ground watered successfully")
	_assert(GameState.watering_can_charges == 4, "Watering can charge consumed")

func _scenario_d() -> void:
	print("\n--- Scenario D: Day Cycle & Growth ---")
	
	var initial_day = GameState.day
	
	# Plant a second seed but DON'T water it
	_stage_tile(6, 4, "seeded", "wheat")
	var unwatered_tile = farm.get_tile(6, 4)
	
	# Sleep through the sim gateway — the same path the live game uses —
	# overriding the weather roll so growth assertions stay deterministic
	farm.apply_action({ "verb": "sleep", "actor": "world", "weather": "sunny" }, GameState)
	# There is no fade to wait for: a sleep applied straight at the gateway turns
	# the day synchronously and starts no day-cycle transition — that is main.gd's
	# doing, from a cot tap. A few frames of settle; the old 120 were two seconds
	# of dead wall-clock that load stretched further.
	for i in 5: await get_tree().process_frame
	
	_assert(GameState.day == initial_day + 1, "Day advanced")
	_assert(GameState.energy == GameState.max_energy, "Energy restored")
	
	var watered_tile = farm.get_tile(6, 5)
	_assert(watered_tile.state == "growing", "Watered seed advanced to 'growing'")
	_assert(watered_tile.growth_stage == 1, "Growth stage incremented")
	
	_assert(unwatered_tile.state == "seeded", "Unwatered seed did not advance")
	_assert(unwatered_tile.growth_stage == 0, "Unwatered seed growth stage remained 0")
	
func _scenario_e() -> void:
	print("\n--- Scenario E: Economy (Harvest, Sell) ---")
	
	# Force crop to ready
	_stage_tile(6, 5, "ready", "wheat")
	farm.get_tile(6, 5).growth_stage = 3
	
	player.pos = Vector2(5.5 * 16.0, 5.5 * 16.0)
	player.facing = "right"
	
	GameState.selected_tool = 0 # Hands
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	_assert(farm.get_tile(6, 5).state == "cleared", "Harvested tile returned to 'cleared'")
	_assert(GameState.crops["wheat"] == 1, "Harvested crop in inventory")
	
	# Move to shipping bin (assumed at tx=4, ty=1)
	player.pos = Vector2(4.5 * 16.0, 2.5 * 16.0)
	player.facing = "up"
	
	var gold_before = GameState.gold
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	
	_assert(GameState.crops["wheat"] == 0, "Crop removed from inventory on bin interact")
	_assert(GameState.gold == gold_before + 15, "Gold increased by wheat sell price (15g)")


func _scenario_f() -> void:
	# Reported from play 2026-08-28: crows only ever came from the left. They
	# spawned at a fixed (-32,-32) and flew away along that same diagonal, so
	# standing near the left edge blocked every crow in the game — an accidental
	# mechanic nobody designed and no player could reason about.
	#
	# Lives in the integration suite rather than the unit suite because crow.gd
	# reaches for the GameState autoload, which the --script unit runner has not
	# registered.
	print("\n--- Scenario F: Crow approach direction ---")

	# M2.5 WI-3 moved this arithmetic out of `entities/crow.gd` and into the crow's
	# brain, in tile space rather than pixels (a sim that reasons in pixels has lost
	# the plot). The properties asserted are the ones the 2026-08-28 report was
	# about and have not changed; only where they live has.
	var w := float(SimWorld.MAP_WIDTH)
	var h := float(SimWorld.MAP_HEIGHT)

	var left: Vector2 = CrowBrain.entry_point(0, 100)
	var right: Vector2 = CrowBrain.entry_point(1, 100)
	var top: Vector2 = CrowBrain.entry_point(2, 100)
	var bottom: Vector2 = CrowBrain.entry_point(3, 100)

	_assert(left.x < 0.0, "side 0 enters from off the left edge")
	_assert(right.x > w, "side 1 enters from off the right edge")
	_assert(top.y < 0.0, "side 2 enters from off the top edge")
	_assert(bottom.y > h, "side 3 enters from off the bottom edge")
	_assert(CrowBrain.entry_point(0, 10).y != CrowBrain.entry_point(0, 200).y,
		"entry point varies along the edge, not just the side")
	_assert(CrowBrain.entry_point(0, -7).y >= 0.0, "a negative offset stays on the edge")
	_assert(CrowBrain.entry_point(0, 999999).y < h, "a huge offset stays on the edge")
	_assert(CrowBrain.entry_point(4, 100) == left, "side index wraps")

	# All four edges must be reachable from the arrival's seeded draw, or some
	# side is unreachable and the block-one-corner exploit survives there. The draw
	# is `SimRng.stateless` now, not the shared stream (WI-3): a live session's
	# stream is advanced by the hen's wandering and a replay's is not, so a crow
	# whose entry came off it would arrive from a different edge on playback.
	var seen := {}
	SimRng.reseed(99)
	for i in range(200):
		seen[int(SimRng.stateless(i, 2000)) % 4] = true
	_assert(seen.size() == 4, "all four edges are reachable from the seeded draw")

	# Departure mirrors arrival: a crow entering from the right must leave to the
	# right, not cross the whole farm to exit where crows always used to.
	for case in [
		{ "at": right,  "name": "right",  "axis": "x", "sign": 1.0 },
		{ "at": left,   "name": "left",   "axis": "x", "sign": -1.0 },
		{ "at": bottom, "name": "bottom", "axis": "y", "sign": 1.0 },
		{ "at": top,    "name": "top",    "axis": "y", "sign": -1.0 },
	]:
		var dir: Vector2 = CrowBrain.exit_direction(case.at)
		var component: float = dir.x if case.axis == "x" else dir.y
		_assert(component * case.sign > 0.0,
			"a crow from the %s leaves toward the %s" % [case.name, case.name])


func _scenario_g() -> void:
	# Reported from play 2026-08-28: "Return to title" in the pause menu did
	# nothing. main.gd's _on_menu_action recognised only "quit" and dropped every
	# other emission, so the return_to_title branch was unreachable from the menu
	# meant to trigger it — silent, because an unmatched signal says nothing.
	print("\n--- Scenario G: pause menu actions are routed ---")

	var menus = main_scene.get("menus")
	_assert(menus != null, "the main scene exposes its menus")
	_assert(menus.menu_action.get_connections().size() > 0, "menu_action has a listener")

	# Every action the pause menu can emit must be recognised by the handler.
	# Asserting on the routing rather than on the scene change, because changing
	# scenes mid-suite would tear down the runner's own fixtures.
	var handled := main_scene.has_method("_handle_action_result")
	_assert(handled, "main routes actions through _handle_action_result")

	var src := (main_scene.get_script().source_code as String)
	var handler := src.substr(src.find("func _on_menu_action"))
	handler = handler.substr(0, handler.find("\nfunc "))
	_assert(handler.contains("_handle_action_result"),
		"menu actions are forwarded to the shared router, not matched one by one")
	_assert(handler.contains("quit"), "and quit is still handled explicitly")

	# The branch it was failing to reach must still exist and still persist first,
	# since leaving the farm without saving is the S-7 failure this guards.
	var rta := src.find("\"return_to_title\"")
	_assert(rta != -1, "return_to_title is still handled")
	var branch := src.substr(rta, 400)
	_assert(branch.contains("persist_session"),
		"leaving to the title still saves the farm on the way out")


func _scenario_h_daylight() -> void:
	# T-14 / Q-38: the energy bar is replaced by the sky. The bar was the single
	# least readable element in the HUD for the player this game is aimed at; the
	# same number rendered as light needs no reading at all.
	print("\n--- Scenario H: Daylight replaces the energy bar ---")

	var tint: CanvasModulate = null
	for child in main_scene.get_children():
		if child is CanvasModulate:
			tint = child
	_assert(tint != null, "a CanvasModulate tints the world canvas")
	if tint == null:
		return

	# (a) it starts at the colour the pure ramp says it should be
	GameState.set_energy(GameState.max_energy)
	await get_tree().process_frame
	var expected := Daylight.tint_for(GameState.energy, GameState.max_energy)
	_assert(tint.color.is_equal_approx(expected), "world tint matches Daylight.tint_for at full energy")

	# (b) spending energy through the real input path moves it
	var before := tint.color
	var energy_before := GameState.energy
	_stage_tile(9, 5, "cleared")
	player.pos = Vector2(8.5 * 16.0, 5.5 * 16.0)
	player.facing = "right"
	GameState.selected_tool = 3  # Hoe
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	await get_tree().process_frame
	_assert(GameState.energy < energy_before, "the action spent energy")
	_assert(not tint.color.is_equal_approx(before), "spending energy changed the world tint")
	_assert(tint.color.is_equal_approx(Daylight.tint_for(GameState.energy, GameState.max_energy)),
		"world tint tracks Daylight.tint_for after the action")

	# (c) the HUD no longer carries the energy bar at all
	_assert(not ("energy_bar_fill" in main_scene.hud), "the HUD has no energy_bar_fill")
	_assert(not ("energy_bar_bg" in main_scene.hud), "the HUD has no energy_bar_bg")
	var found_bar := false
	for node in main_scene.hud.find_children("*", "ColorRect", true, false):
		if node.name == "energy_bar_fill" or node.name == "energy_bar_bg":
			found_bar = true
	_assert(not found_bar, "no energy bar node survives in the HUD tree")

	# (d) Q-11's soft floor is untouched: actions still resolve at twilight
	GameState.set_energy(0)
	await get_tree().process_frame
	_assert(tint.color.is_equal_approx(Daylight.tint_for(0, GameState.max_energy)),
		"empty energy renders as the twilight stop")
	_stage_tile(9, 6, "obstacle_weed")
	player.pos = Vector2(8.5 * 16.0, 6.5 * 16.0)
	player.facing = "right"
	GameState.selected_tool = 0  # Hands
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	_assert(farm.get_tile(9, 6).state == "cleared", "night stays soft — the action still resolves at 0 energy")

	# (e) T-29: the bar carries the hour precisely, and still without a word.
	#
	# Q-38 was ratified with one rider — the tint is ambient, and the designer
	# wanted the time of day readable exactly as well. The sun-arc is that read.
	# It is a drawing, so what is asserted is the geometry it is drawn from: the
	# token's own position in the arc's pixels.
	var hud = main_scene.hud
	_assert(hud.sun_arc != null and hud.sun_arc is Control,
		"the top bar carries a sun-arc")
	_assert(hud.sun_arc.get_parent() == hud.top_bar, "in the top bar, where the readout was")
	_assert(hud.sun_arc.find_children("*", "Label", true, false).is_empty(),
		"and it is wordless — the arc has no text in it at all (S-7)")
	_assert(hud.sun_arc.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"and it never eats a tap meant for the farm")

	GameState.set_energy(0)
	await get_tree().process_frame
	var at_dusk: Vector2 = hud.sun_token_pos()
	_assert(hud.sun_token_is_moon(), "at an empty day the token is a moon")
	GameState.set_energy(GameState.max_energy)
	await get_tree().process_frame
	var at_dawn: Vector2 = hud.sun_token_pos()
	_assert(not hud.sun_token_is_moon(), "and at a full one it is the sun")
	_assert(at_dawn.x < at_dusk.x, "the token travels west to east across the day")
	_assert(is_equal_approx(at_dawn.y, at_dusk.y),
		"starting and ending on the horizon — it is an arc, not a bar")

	# Half a day spent puts it overhead, which is the whole reason it is an arc.
	GameState.set_energy(GameState.max_energy / 2)
	await get_tree().process_frame
	var at_noon: Vector2 = hud.sun_token_pos()
	_assert(at_noon.y < at_dawn.y - 5.0, "and rides high over midday")
	_assert(at_noon.x > at_dawn.x and at_noon.x < at_dusk.x, "halfway along, halfway through")
	_assert(at_dusk.x - at_dawn.x > 80.0, "with the whole day worth crossing")

	# One ordinary action visibly moves it — a clock nobody can see tick is not a
	# clock. A base verb is 1/20th of the day, so the token moves a real distance.
	GameState.set_energy(GameState.max_energy)
	await get_tree().process_frame
	var before_action: Vector2 = hud.sun_token_pos()
	GameState.set_energy(GameState.energy - Tools.get_energy_cost("till"))
	await get_tree().process_frame
	_assert(hud.sun_token_pos().distance_to(before_action) > 1.5,
		"and one base action moves it by more than a pixel or two")

	# (f) T-34: the same hour in digits, beside the arc.
	#
	# The arc is the wordless read and stays the one the game is designed around;
	# the digits are the exact one. Both are drawn from `Daylight`, so what is
	# checked here is that the label exists where the ruling put it and says what
	# the pure function says — a 12-hour face with AM/PM since T-36.
	_assert(hud.clock_label != null and hud.clock_label is Label,
		"the top bar carries a clock")
	_assert(hud.clock_label.get_parent() == hud.top_bar, "in the top bar, with the arc")
	_assert(hud.clock_label.position.x >= hud.sun_arc.position.x + hud.sun_arc.size.x,
		"beside the arc and to its right, as the ruling placed it")
	_assert(hud.clock_label.position.y + hud.clock_label.size.y <= hud.top_bar.size.y,
		"and inside the bar's own 30 pixels")

	GameState.set_energy(GameState.max_energy)
	await get_tree().process_frame
	_assert(hud.clock_label.text == "6:00 AM", "a full meter reads 6:00 AM — the workday opens")

	# T-36 (2026-08-31): the designer overturned T-34's 24-hour deviation and
	# accepted the two-letter markers on the clock — so the face carries digits,
	# a colon, and exactly AM or PM, nothing wider.
	_assert(hud.clock_label.text.ends_with(" AM") or hud.clock_label.text.ends_with(" PM"),
		"and it wears the accepted marker — AM/PM, per the T-36 ruling")

	# One real action through the real input path moves it exactly half an hour:
	# one energy unit is one fictional minute and a base verb is 30 of them.
	# (9,6) was cleared by the soft-floor action above and she is still beside it.
	GameState.selected_tool = 3  # Hoe
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	await get_tree().process_frame
	_assert(GameState.energy == GameState.max_energy - Tools.get_energy_cost("till"),
		"one base action spent 30 units")
	_assert(hud.clock_label.text == "6:30 AM",
		"and the clock says 6:30 AM — one unit is one minute, with no factor between")

	# It parks at dusk, and Q-11's soft-floor work happens in the evening (Q-73's
	# span) without moving the digits.
	GameState.set_energy(0)
	await get_tree().process_frame
	_assert(hud.clock_label.text == "4:00 PM", "an empty meter parks the clock at 4:00 PM")
	_stage_tile(9, 6, "obstacle_weed")
	player.pos = Vector2(8.5 * 16.0, 6.5 * 16.0)
	player.facing = "right"
	GameState.selected_tool = 0  # Hands
	Input.action_press("action")
	await _wait_for_action()
	Input.action_release("action")
	await get_tree().process_frame
	_assert(farm.get_tile(9, 6).state == "cleared",
		"work past the floor still resolves (Q-11)")
	_assert(hud.clock_label.text == "4:00 PM",
		"and it happens in the evening — the digits do not move for it")

	# (g) Q-72: the weather line speaks only when weather is happening. Clear days
	# are the arc's and the clock's to report; the line saying the hour a third
	# time was the duplication the ruling removed.
	var weather_was: String = GameState.weather
	GameState.weather = "sunny"
	await get_tree().process_frame
	_assert(hud.weather_label.text == "",
		"on a clear day the weather line says nothing at all")
	GameState.weather = "rainy"
	await get_tree().process_frame
	_assert(hud.weather_label.text.contains("Rainy"),
		"and rain still speaks, in exactly the words it had")
	GameState.weather = weather_was
	await get_tree().process_frame

	# The *energy* readout stays out of the shipped bar (Q-38's sub-ruling that it
	# is debug-only) — T-34 shipped a clock, not the meter's raw numbers, and the
	# two are separate rulings. Asserted on the source, because this suite only
	# ever runs in a debug build and so can never observe the release case.
	var hud_src := (hud.get_script().source_code as String)
	var gate := hud_src.find("OS.is_debug_build()")
	_assert(gate != -1 and hud_src.find("energy_debug_label") > gate,
		"the only numeric energy readout left is behind the debug gate")
	_assert(hud_src.count("Energy: %d/%d") == 1,
		"and there is exactly one of it")

	GameState.set_energy(GameState.max_energy)


func _scenario_i_third_state() -> void:
	# T-18/T-19 (Q-42): the game's third answer — *nothing to do* — used to be
	# silence, and a four-year-old reads silence as a broken tile. The 2026-08-28
	# session measured 20 dead taps holding the watering can over crops already
	# watered that day. A finished tile now says "yes, done", positively, and the
	# trace records it as its own outcome so the fix is measurable.
	print("\n--- Scenario I: the third state speaks ---")

	GameState.set_energy(GameState.max_energy)
	GameState.watering_can_charges = GameState.max_watering_can_charges
	_stage_tile(11, 8, "cleared")
	_stage_tile(12, 8, "seeded", "wheat")
	player.pos = Vector2(11.5 * 16.0, 8.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	# 1. water it through the real tap path
	var before: int = farm.trace.entries.size()
	InputManager.click_tile = Vector2i(12, 8)
	InputManager.has_click = true
	var watered := await _wait_until(func(): return farm.get_tile(12, 8).watered_today, 200)
	_assert(watered, "a tap watered the tile through the input path")

	# 2. tap it again with the can still selected — the exact dead-tap case
	InputManager.click_tile = Vector2i(12, 8)
	InputManager.has_click = true
	var acked := await _wait_until(
		func(): return _last_tap_outcome(before) == "satisfied", 200)
	_assert(acked, "tapping an already-watered crop is answered 'satisfied', not silence")
	_assert(_last_tap_reason(before) == "already_watered", "and the reason code is recorded")
	_assert(_no_refusals_since(before), "no refusal was recorded — a good state never wobbles")

	# 3. the well, with a full can: the same third state from the object side
	var mark: int = farm.trace.entries.size()
	GameState.watering_can_charges = GameState.max_watering_can_charges
	player.pos = Vector2(6.5 * 16.0, 2.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = Vector2i(6, 1)
	InputManager.has_click = true
	var well_ack := await _wait_until(
		func(): return _last_tap_outcome(mark) == "satisfied", 200)
	_assert(well_ack, "tapping the well with a full can is answered 'satisfied'")
	_assert(_last_tap_reason(mark) == "can_full", "and says which good state it was in")
	_assert(_no_refusals_since(mark), "the well no longer logs a benign refusal it never earned")

	# 4. the bin, with an empty basket
	var mark2: int = farm.trace.entries.size()
	GameState.crops = { "wheat": 0, "tomato": 0 }
	player.pos = Vector2(4.5 * 16.0, 2.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = Vector2i(4, 1)
	InputManager.has_click = true
	var bin_ack := await _wait_until(
		func(): return _last_tap_outcome(mark2) == "satisfied", 200)
	_assert(bin_ack, "tapping the bin with an empty basket is answered 'satisfied'")
	_assert(_last_tap_reason(mark2) == "basket_empty", "and says which good state it was in")

	# 5. and a real refusal still refuses — the third state must not swallow the
	#    second. An empty pouch on a tilled tile is the 2026-08-27 silent-refusal
	#    case, and it must still say what she is missing, in the sim's vocabulary.
	var mark3: int = farm.trace.entries.size()
	_stage_tile(11, 8, "cleared")
	_stage_tile(12, 8, "tilled")
	GameState.seeds["wheat"] = 0
	GameState.seeds["tomato"] = 0
	GameState.selected_seed_type = "wheat"
	player.pos = Vector2(11.5 * 16.0, 8.5 * 16.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = Vector2i(12, 8)
	InputManager.has_click = true
	var refused := await _wait_until(
		func(): return _last_tap_outcome(mark3) == "refused", 200)
	_assert(refused, "an empty pouch on a tilled tile is still a refusal, not an acknowledgement")
	_assert(_last_tap_reason(mark3) == "no_seeds",
		"and it speaks the sim's code, so the icon table matches it (finding F-5)")
	_assert(farm.REFUSE_ICONS.has(_last_tap_reason(mark3)),
		"and that code has a picture to show her")

	GameState.seeds["wheat"] = 5
	GameState.crops = { "wheat": 0, "tomato": 0 }


func _last_tap_outcome(since: int) -> String:
	for i in range(farm.trace.entries.size() - 1, since - 1, -1):
		if String(farm.trace.entries[i].get("kind", "")) == "tap":
			return String(farm.trace.entries[i].get("out", ""))
	return ""


func _last_tap_reason(since: int) -> String:
	for i in range(farm.trace.entries.size() - 1, since - 1, -1):
		if String(farm.trace.entries[i].get("kind", "")) == "tap":
			return String(farm.trace.entries[i].get("why", ""))
	return ""


func _no_refusals_since(since: int) -> bool:
	for i in range(since, farm.trace.entries.size()):
		var e: Dictionary = farm.trace.entries[i]
		if String(e.get("kind", "")) == "act" and not e.get("ok", true):
			return false
		if String(e.get("out", "")) == "refused":
			return false
	return true


func _scenario_l_menu_holds_world() -> void:
	# Reported from play 2026-08-29: "the chicken advances by a big jump when I
	# bought in the shop."
	#
	# Not corrupted state — the world kept running behind the menu. `open_menu`
	# paused the tree only for the *pause* menu, so with the shop up the player was
	# frozen (main._process returns early on menus.is_open()) while every entity
	# carried on living. The shop panel covers them, so the chicken's ordinary walk
	# is invisible until the screen closes, at which point she has teleported.
	#
	# The rule this asserts: **while any menu is open the world holds.** A menu is
	# not a place the game continues without you.
	#
	# Updated for M2.5 WI-3, which moved the hen's decisions and her position into
	# the sim: the setup now puts her somewhere in *sim truth* and watches the
	# renderer walk there, rather than hand-loading a path into a presentation FSM
	# that no longer exists. What is asserted is unchanged, and the reason it still
	# holds is unchanged too — an open menu pauses the tree, and a paused tree runs
	# no `_process`, so `main.gd`'s clock pump never converts a frame into a tick.
	print("\n--- Scenario L: an open menu holds the world ---")

	var menus = main_scene.menus
	var chicken = null
	var ChickenScript = load("res://entities/chicken.gd")
	for child in main_scene.entities.get_children():
		if child.get_script() == ChickenScript:
			chicken = child
	_assert(chicken != null, "the farm has a chicken to watch")
	if chicken == null:
		return

	# Put her on a known walk so "did she move" is a real question. The sim says
	# where she is; the node's job is to get its sprite there.
	for tx in [5, 6, 7]:
		_stage_tile(tx, 5, "cleared")
	farm.sim.set_actor_pos(chicken.actor_id, Vector2i(5, 5))
	chicken.position = Vector2(5 * 16, 5 * 16)
	await get_tree().process_frame
	farm.sim.set_actor_pos(chicken.actor_id, Vector2i(7, 5))

	var moving_start: Vector2 = chicken.position
	for i in 20: await get_tree().process_frame
	_assert(chicken.position != moving_start, "she walks while the game is running")

	menus.open_menu("shop")
	await get_tree().process_frame
	_assert(menus.is_open(), "the shop is open")
	_assert(get_tree().paused, "opening the shop pauses the world, as the pause menu does")

	var frozen_at: Vector2 = chicken.position
	for i in 30: await get_tree().process_frame
	_assert(chicken.position == frozen_at,
		"and she does not move behind it — no teleport when the screen closes")

	menus.close_menu()
	await get_tree().process_frame
	_assert(not get_tree().paused, "closing it starts the world again")
	farm.sim.set_actor_pos(chicken.actor_id, Vector2i(7, 5))
	for i in 20: await get_tree().process_frame
	_assert(chicken.position != frozen_at, "and she carries on from where she stood")

	# The inventory is a menu too, and so is the pause screen it was already true of.
	for name in ["inventory", "pause"]:
		menus.open_menu(name)
		await get_tree().process_frame
		_assert(get_tree().paused, "the %s screen holds the world too" % name)
		menus.close_menu()
		await get_tree().process_frame
	_assert(not get_tree().paused, "and the world is running again afterwards")

	# The second half of the same report: "I see it advance when I click to buy."
	# That is a *long frame*, not the menu — `_process` gets the real frame time,
	# and rebuilding the shop's options stalls one. With no cap on the step, one
	# stalled frame carried her a whole tile. Pausing hides it in menus; the cap is
	# what stops it happening anywhere else a frame hitches.
	#
	# Two caps now, and both are asserted: the renderer's (below) and, since WI-3,
	# `main.gd`'s clock pump, which converts at most MAX_TICKS_PER_FRAME of a long
	# frame into sim time so a hitch cannot run the world forward either.
	for tx2 in [6, 7, 8]:
		_stage_tile(tx2, 5, "cleared")
	farm.sim.set_actor_pos(chicken.actor_id, Vector2i(5, 5))
	chicken.position = Vector2(5 * 16, 5 * 16)
	farm.sim.set_actor_pos(chicken.actor_id, Vector2i(8, 5))
	var before_hitch: Vector2 = chicken.position
	chicken._process(2.0)  # a two-second frame, far worse than any real hitch
	var jumped: float = chicken.position.distance_to(before_hitch)
	_assert(jumped <= 16.0,
		"a stalled frame moves her at most one tile, not %d px" % int(jumped))
	_assert(jumped > 0.0, "but she still moves — the cap is not a freeze")

	var sim_before: int = farm.sim.clock.tick
	main_scene._pump_sim_clock(2.0)
	_assert(farm.sim.clock.tick - sim_before <= main_scene.MAX_TICKS_PER_FRAME,
		"and a stalled frame advances sim time by at most %d ticks, not 20"
			% main_scene.MAX_TICKS_PER_FRAME)


# Where the camera comes to rest for a player standing at `player_px`. Godot
# smooths towards this over several frames; the settled value is what matters and
# is worth computing rather than waiting for.
func _settled_view(player_px: Vector2) -> Rect2:
	var half: Vector2 = get_viewport().get_visible_rect().size / (2.0 * float(main_scene.CAMERA_SCALE))
	var cam: Camera2D = main_scene.camera
	return Rect2(Vector2(
		clampf(player_px.x, cam.limit_left + half.x, cam.limit_right - half.x),
		clampf(player_px.y, cam.limit_top + half.y, cam.limit_bottom - half.y)) - half, half * 2.0)


func _scenario_m_targets_on_screen() -> void:
	# Raised from play 2026-08-29: could the ripe-crop beat wait until the player
	# has walked far enough right to reveal it?
	#
	# Measured answer: it already does, and not by accident of timing — beat 0
	# holds the highlight on the *gate* for as long as she is inside the yard, and
	# by the time she steps through, the crop is on screen. So there is nothing to
	# build. But that only works because of a coincidence of three numbers: the
	# yard is 10 tiles wide, the camera shows 8.3 tiles either side, and the ripe
	# crop sits at x=17. `systems/world_layout.gd` exists precisely so the
	# arrangement can be edited freely, so this asserts the property rather than
	# leaving it to hold by luck. If someone widens the yard or moves the crop,
	# this fails instead of the game quietly pointing at nothing.
	print("\n--- Scenario M: a highlighted target is on screen ---")

	var world := SimWorld.new()
	SimRng.reseed(4242)
	world.generate()
	var gs = load("res://systems/game_state.gd").new()
	ColdOpen.run(world, world, gs)

	var checked := 0
	var offscreen: Array = []
	for p in WorldLayout.parcels():
		var pid := String(p.get("id", ""))
		if pid != "yard" and pid != "neighbour":
			continue
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					if not world.is_walkable(tx, ty):
						continue
					var here := Vector2i(tx, ty)
					var view := _settled_view(Vector2(tx * 16 + 8, ty * 16 + 8))
					for target in TeachingFocus.targets(world, gs, here):
						checked += 1
						if not view.has_point(Vector2(target.x * 16 + 8, target.y * 16 + 8)):
							offscreen.append("from %s the highlight %s is off screen" % [here, target])
	_assert(checked > 0, "there were targets to check (%d)" % checked)
	_assert(offscreen.is_empty(),
		"every day-1 highlight is on screen from anywhere she can stand (%s)"
			% ("ok" if offscreen.is_empty() else offscreen[0]))

	# And the specific beat the report was about: standing at spawn, the thing
	# being pointed at is the gate — not the crop two screens away.
	var spawn := WorldLayout.spawn()
	var at_spawn: Array = TeachingFocus.targets(world, gs, spawn)
	_assert(at_spawn.size() == 1 and at_spawn[0] == WorldLayout.gate_of("neighbour"),
		"from spawn the game asks for the gate, which is the only thing she can see to walk to")

	gs.free()


func _scenario_n_pick_up_the_axe() -> void:
	# Asked from play 2026-08-29: "am I supposed to be able to pick up the axe?"
	# The unit suite proves the router offers `take_tool` and the sim grants it,
	# but nothing drove the whole thing through an actual tap, which is where a
	# player meets it. This does.
	print("\n--- Scenario N: picking the axe up off the ground ---")

	var entry: Dictionary = WorldLayout.tools()[0]
	var at: Vector2i = entry.get("at", Vector2i(-1, -1))
	var gate: Vector2i = entry.get("gate", Vector2i(-1, -1))
	var stand := Vector2i(at.x - 1, at.y)

	_stage_tile(at.x, at.y, "cleared")
	farm.sim.set_object(at.x, at.y, String(entry.get("object", "")))
	_stage_tile(stand.x, stand.y, "cleared")
	_stage_tile(gate.x, gate.y, WorldLayout.GATE_CLOSED)
	GameState.tools_owned["axe"] = false
	GameState.harvest_counts = { "wheat": 0, "tomato": 0 }
	player.pos = Vector2(stand.x * 16 + 8, stand.y * 16 + 8)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	# Before the proof: the tap must not take it, and — this is the part a player
	# feels — it must not silently do nothing either. Today it resolves to pure
	# movement, so she walks up to it and stops.
	_assert(TeachingFocus.locked_tools(farm.sim, GameState).has(at),
		"an unearned axe reads as locked, so it is drawn as a silhouette (Q-46a)")
	_assert(not TeachingFocus.ready_tools(farm.sim, GameState).has(at),
		"and is not announced as available")

	InputManager.click_tile = at
	InputManager.has_click = true
	for i in 30: await get_tree().process_frame
	_assert(farm.get_object(at.x, at.y) == String(entry.get("object", "")),
		"an unearned axe stays on the ground")
	_assert(not GameState.owns_tool("axe"), "and she does not have it")
	_assert(String(farm.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_CLOSED,
		"and its gate stays shut")

	# Meet the Q-46 strawman proof, then tap it again.
	GameState.harvest_counts["wheat"] = int(entry.get("threshold", 5))
	_assert(SimWorld.tool_proof_met(entry, GameState), "the harvest proof is met")
	# Asserted on the mechanism rather than on the arbitrated result: by this
	# point in the suite the live world has been driven through many scenarios,
	# so what else may legitimately be competing for the highlight is not a
	# fixed quantity. `test_tool_acquisition` owns the arbitration assertion.
	_assert(TeachingFocus.ready_tools(farm.sim, GameState).has(at),
		"and the moment it becomes takeable, it is announced")
	_assert(not TeachingFocus.locked_tools(farm.sim, GameState).has(at),
		"and stops being drawn as locked")
	player.pos = Vector2(stand.x * 16 + 8, stand.y * 16 + 8)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	InputManager.click_tile = at
	InputManager.has_click = true
	var took := await _wait_until(func(): return GameState.owns_tool("axe"), 200)
	_assert(took, "tapping the earned axe picks it up")
	_assert(farm.get_object(at.x, at.y) == "", "and it leaves the ground")
	_assert(String(farm.get_tile(gate.x, gate.y).state) == WorldLayout.GATE_OPEN,
		"and picking it up is what opens its parcel")
	_assert(farm.is_walkable(gate.x, gate.y), "which is now walkable")
	_assert(GameState.selected_tool == Tools.index_of_key("axe"),
		"and she is holding what she just picked up")

	# Both actions are in the replay, so a session that earns a tool replays as
	# one that earns it — the gate is not a presentation side effect.
	var verbs: Array = []
	for e in farm.replay.entries:
		verbs.append(String(e.get("verb", "")))
	_assert(verbs.has("take_tool"), "take_tool is recorded")
	_assert(verbs.has("open_gate"), "and so is the gate opening")


# Any ASCII letter. The rule is S-7's: digits, whitespace and symbols are fine —
# what is forbidden is a screen that cannot be used without *reading*.
func _has_letters(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return true
	return false


func _collect_labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node)
	for child in node.get_children():
		_collect_labels(child, out)


func _scenario_j_wordless_shop() -> void:
	# T-12 (Q-35). The shop was the one screen in phase 1 that **required
	# reading** — "SEED SHOP", "5g", "Owned: N", "??? (Locked)", "Close" — and
	# Q-35's ruling is that guiding a pre-reader into a screen she cannot read is
	# worse than not guiding her at all. This is the mechanical check that it
	# stays wordless, rerunnable by anyone.
	print("\n--- Scenario J: the shop has no words in it ---")

	var menus = main_scene.menus
	GameState.gold = 100
	GameState.harvest_counts = { "wheat": 0, "tomato": 0 }  # tomato stays locked
	menus.open_menu("shop")
	await get_tree().process_frame
	await get_tree().process_frame

	var labels: Array = []
	_collect_labels(menus.options_container, labels)
	_assert(labels.size() > 0, "the shop draws some text at all (numbers)")
	var worded: Array = []
	for lbl in labels:
		if _has_letters(String(lbl.text)):
			worded.append(String(lbl.text))
	_assert(worded.is_empty(),
		"no label in the shop contains a letter%s" % ("" if worded.is_empty() else " — found %s" % str(worded)))
	_assert(not _has_letters(String(menus.title_label.text)),
		"and the title is a picture, not the words SEED SHOP")
	_assert(not _has_letters(String(menus.gold_display.text)),
		"and the gold count is a numeral beside a coin, not '100g'")
	_assert(menus.shop_title_icon.visible and menus.gold_icon.visible,
		"the seed-packet header and the coin are actually shown")

	# A locked item is the same picture, darkened — never an empty box, never
	# "???", which tells a pre-reader nothing except that something is missing.
	var icons: Array = []
	for card in menus.options_container.get_children():
		for tr in card.find_children("*", "TextureRect", true, false):
			icons.append(tr)
	_assert(icons.size() >= 2, "every card carries an icon, locked ones included")
	var darkened := 0
	for tr in icons:
		if tr.modulate.v < 0.5:
			darkened += 1
	_assert(darkened >= 1, "the locked item is drawn darkened rather than blank")

	# Buying still goes through the sim gateway, unchanged (P-9).
	var before: int = GameState.seeds.get("wheat", 0)
	var bought_gold: int = GameState.gold
	menus.selected_option = 0
	menus._select_current_option()
	await get_tree().process_frame
	_assert(GameState.seeds.get("wheat", 0) == before + 1, "tapping a card still buys the seed")
	_assert(GameState.gold < bought_gold, "and still costs gold")
	_assert(GameState.seeds_bought >= 1, "and accrues T-11's counter")

	# The ✕ closes it, and it is the last option rather than an index guess.
	menus.selected_option = menus.shop_items.size()
	menus._select_current_option()
	await get_tree().process_frame
	_assert(not menus.is_open(), "the ✕ closes the shop")
	_assert(not get_tree().paused, "and the world starts again")


func _live_fingerprint() -> String:
	var g = GameState
	return "%d|%d|%d|%d|%s|%s|%d" % [g.day, g.gold, g.energy, g.watering_can_charges,
		JSON.stringify(g.seeds), JSON.stringify(g.crops), g.total_shipped]


func _scenario_k_attract() -> void:
	# T-16 (Q-40). The spike measured the failure this guards: driving the
	# renderer from a replay drained the **live** GameState to energy 0, wheat 0
	# while the player was still looking at the menu. A farmer who spends your
	# seeds on the title screen is a data-loss bug wearing an animation.
	print("\n--- Scenario K: the attract loop cannot touch the player's farm ---")

	var AttractScript = load("res://ui/attract_loop.gd")

	# Headless has nothing to render into, so the title screen must not start one.
	var title = load("res://ui/title_screen.tscn").instantiate()
	get_tree().root.add_child(title)
	await get_tree().process_frame
	_assert(title.get_node_or_null("AttractLoop") == null,
		"the title screen starts no attract loop headless")
	title.queue_free()
	await get_tree().process_frame

	# Build a small session to play, so this does not depend on whoever played last.
	var rec = load("res://systems/game_state.gd").new()
	rec.reset()
	var w := SimWorld.new()
	SimRng.reseed(4242)
	w.generate()
	var rlog := ReplayLog.new()
	rlog.start(4242)
	var worked := 0
	for i in 6:
		var t := Vector2i(3 + i, 3)
		if not w.is_walkable(t.x, t.y):
			continue
		w.set_tile_state(t.x, t.y, "cleared")
		var a := { "verb": "till", "target": t, "actor": "player" }
		var r := w.apply_action(a, rec)
		if r.get("ok", false):
			rlog.record(a, r)
			worked += 1
	_assert(worked >= 3, "the synthetic session has actions to play (%d)" % worked)

	var before := _live_fingerprint()
	var files_before: Array = []
	for path in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		files_before.append(FileAccess.file_exists(path))

	var loop = AttractScript.new()
	loop.name = "AttractLoop"
	add_child(loop)
	_assert(loop.begin(rlog), "the attract loop starts on a real replay")
	_assert(loop.farm != null and loop.farm.sim != null, "it brought its own farm and SimWorld")
	_assert(loop.farm.sim != main_scene.farm.sim, "which is not the played farm's")
	_assert(loop.gs != null and loop.gs != GameState,
		"and a DETACHED GameState, not the singleton — this is the whole hazard")
	_assert(loop.player != null and loop.player.gs == loop.gs,
		"the farmer it drives spends that detached state")
	_assert(loop.player.name == "Player",
		"and is named Player, which farm.gd's renderer looks up by path")
	_assert(loop.farm.mute_feedback, "the attract farm is muted — no nope sounds into a menu")

	# Step it. This is the path the spike found leaking.
	for i in 240:
		loop._process(1.0 / 60.0)
	_assert(loop._next > 0, "playback actually advanced (%d entries in)" % loop._next)
	_assert(_live_fingerprint() == before,
		"the live GameState is byte-identical after playback — the spike's finding, fixed")

	# And it wrote nothing anywhere the real game keeps its farm.
	var idx := 0
	for path in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		_assert(FileAccess.file_exists(path) == files_before[idx],
			"the attract loop created no file at %s" % path)
		idx += 1
	_assert(loop.farm.replay == null, "it records no replay of its own")
	_assert(loop.farm.trace == null, "and no session trace")

	# Pausing is what the New Farm confirmation uses: one moving thing at a time.
	var frozen: int = loop._next
	loop.paused = true
	for i in 240:
		loop._process(1.0 / 60.0)
	_assert(loop._next == frozen, "a paused attract loop stops advancing")
	loop.paused = false

	# An uninjected player still defaults to the autoload, which is what the real
	# game wants and what every existing call site assumes. (The unit suite cannot
	# check this half: it has no autoloads.)
	var plain = load("res://player/player.gd").new()
	plain.name = "PlainPlayer"
	add_child(plain)
	await get_tree().process_frame
	_assert(plain.gs == GameState, "an uninjected player defaults to the GameState autoload")
	plain.queue_free()

	# Choosing what to play: the player's own session only when this build
	# recorded it, because apply_to() re-runs actions against today's rules and a
	# cross-build replay can show a farm that never existed (Q-41).
	var stale := ReplayLog.from_json(rlog.to_json())
	stale.build_id = "some-other-build"
	_assert(stale.build_status() == ReplayLog.Build.MISMATCH, "a foreign replay is detected")
	_assert(AttractScript.choose_replay("user://does_not_exist.json", "res://also_missing.json") == null,
		"with nothing to play it returns null, so the title keeps its plain backdrop")

	loop.queue_free()
	rec.free()
	await get_tree().process_frame


func _scenario_o_touch_has_no_hover() -> void:
	# Reported from the tablet, 2026-08-30: "yellow box is moving around as screen
	# scrolls, instead of holding position of the click."
	#
	# It was never a click indicator. It is a *mouse hover* — recomputed every
	# frame from the pointer's screen position plus the camera offset — so with a
	# finger resting where it last tapped and the camera scrolling after the
	# walking farmer, the box slid across the world. A finger does not hover, so
	# on touch there should be no box at all.
	print("\n--- Scenario O: a finger does not hover ---")

	var im = InputManager

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(400, 300)
	im._unhandled_input(touch)
	_assert(im.current_mode == im.Mode.TOUCH, "a screen touch is TOUCH, not MOUSE")
	im._process(0.016)
	_assert(im.mouse_tile == Vector2i(-1, -1), "and leaves no hover tile to draw")

	# Godot emulates mouse events from touch, and the menus' Buttons run on that
	# emulation, so it cannot be switched off — it must be recognised instead.
	var emulated := InputEventMouseMotion.new()
	emulated.position = Vector2(400, 300)
	im._unhandled_input(emulated)
	_assert(im.current_mode == im.Mode.TOUCH,
		"an emulated mouse event right after a touch does not flip the mode back")
	im._process(0.016)
	_assert(im.mouse_tile == Vector2i(-1, -1), "so the box stays gone")

	# A real mouse, well after the finger, still gets its hover back.
	im._last_touch_ms = -100000
	var real := InputEventMouseMotion.new()
	real.position = Vector2(120, 90)
	im._unhandled_input(real)
	_assert(im.current_mode == im.Mode.MOUSE, "a mouse moving on its own is MOUSE again")
	im._process(0.016)
	_assert(im.mouse_tile != Vector2i(-1, -1), "and the hover tile comes back")

	# Leave the suite in a known state.
	im._last_touch_ms = -100000


func _scenario_p_cold_open_waits() -> void:
	# Requested after the tablet playthrough: the cold open "plays while still
	# pretty much off-screen". The neighbour works out to x=17 and the camera
	# shows to about x=16.7 from spawn, so the most legible half of the scene
	# happened past the right edge.
	#
	# The fix is to wait rather than to pan: panning is taking control away, and
	# the fence exists so that never has to happen (design/13 §4a). She wanders to
	# the fence — which is where you would stand to watch someone in the next
	# yard — and only then does the neighbour begin.
	print("\n--- Scenario P: the cold open waits until it can be seen ---")

	var scene = preload("res://main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage := ColdOpen.stage_rect(scene.farm.sim)
	_assert(not ColdOpen.is_done(scene.farm.sim), "the fresh farm has its cold open ahead of it")
	# The suite already has a main scene running, so this second one's camera is
	# not the current one and Godot does not run its smoothing. Make it current
	# and unsmoothed so "where the camera has settled" is answerable this frame.
	scene.camera.position_smoothing_enabled = false
	scene.camera.make_current()

	# At spawn the far end of her row is off screen, so nothing starts.
	scene.player.pos = Vector2(2 * 16 + 8, 2 * 16 + 8)
	scene.player.position = scene.player.pos
	for i in 90: await get_tree().process_frame
	_assert(not scene._stage_is_visible(), "from spawn the scene is not fully on screen")
	_assert(not scene._cold_open_started, "so the neighbour has not started")
	_assert(scene.farm.sim.get_tile(stage.position.x, stage.position.y).size() > 0,
		"and the world is intact while it waits")

	# Walk to the fence and it comes into view.
	scene.player.pos = Vector2(10 * 16 + 8, 4 * 16 + 8)
	scene.player.position = scene.player.pos
	for i in 90: await get_tree().process_frame
	_assert(scene._stage_is_visible(), "at the fence the whole scene is on screen")
	_assert(scene._cold_open_started, "and the neighbour starts")

	# Once begun it is latched: wandering off must not strand her half-inherited
	# farm behind a gate that never opens.
	scene.player.pos = Vector2(2 * 16 + 8, 2 * 16 + 8)
	scene.player.position = scene.player.pos
	for i in 30: await get_tree().process_frame
	_assert(scene._cold_open_started, "walking away again does not stop it")

	# Hand the viewport back to the suite's own scene.
	if main_scene.camera != null:
		main_scene.camera.make_current()
	scene.queue_free()
	await get_tree().process_frame

	# The patience timeout is what stops a player who never wanders right from
	# never getting her farm at all — and on a small enough viewport the scene may
	# not fit however far she walks.
	_assert(scene_patience() > 0.0, "there is a patience timeout at all")


func scene_patience() -> float:
	return load("res://main.gd").COLD_OPEN_PATIENCE


func _scenario_q_crow_is_sim_sent() -> void:
	# M2.5 WI-3 turned the crow inside out. It used to exist because `main.gd`
	# built a node, fly because that node's `_process` moved it, eat when the
	# sprite arrived, and stop existing because the node called `queue_free()` —
	# the sim was never told about any of it. Now the sim sends it (the T-20
	# schedule reaching an arrival inside the gateway), flies it on the tick clock,
	# and despawns it at the map edge; the node is a sprite that follows.
	#
	# This runs live rather than headless because the thing being checked is the
	# *join*: that a bird the sim registered gets drawn, tracks where the sim puts
	# it, and disappears with it. The behaviour either side of the join has its own
	# unit tests (`test_brains`).
	print("\n--- Scenario Q: the sim sends the crow, presentation draws it ---")

	# A farm far enough along that T-2's readiness gate is open. Set on the live
	# GameState because this is the last scenario in the suite.
	GameState.takeover_day = 1
	GameState.day = maxi(GameState.day, SimWorld.CROW_MIN_DAY)
	GameState.harvest_counts["wheat"] = maxi(1, int(GameState.harvest_counts.get("wheat", 0)))
	for tx in range(4, 10):
		_stage_tile(tx, 8, "seeded", "wheat")
	_assert(GameState.play_day() >= SimWorld.CROW_MIN_DAY and farm.sim.count_planted() >= 3,
		"the farm is ready for a crow (play-day %d, %d planted)"
			% [GameState.play_day(), farm.sim.count_planted()])

	GameState.actions_today = 0
	GameState.crow_schedule = [1] as Array[int]
	_stage_tile(3, 8, "cleared")
	_assert(not farm.sim.has_actor(SimWorld.ACTOR_CROW), "no crow before its appointment")
	farm.apply_action({ "verb": "till", "target": Vector2i(3, 8), "actor": "player" }, GameState)
	_assert(farm.sim.has_actor(SimWorld.ACTOR_CROW),
		"one player action reaches the scheduled arrival and the sim sends a crow")
	_assert(GameState.crow_schedule.is_empty(), "spending the day's one arrival (T-20)")

	# The node appears because the actor does, not the other way round.
	await get_tree().process_frame
	var crow = null
	var CrowScript = load("res://entities/crow.gd")
	for child in main_scene.entities.get_children():
		if child.get_script() == CrowScript:
			crow = child
	_assert(crow != null, "and main.gd spawns a sprite for the actor the sim registered")
	if crow == null:
		return
	_assert(crow.actor_id == SimWorld.ACTOR_CROW, "the sprite knows whose it is")

	# It follows sim truth rather than flying itself.
	var was: Vector2 = crow.position
	for i in 30: await get_tree().process_frame
	_assert(crow.position != was, "the sprite moves")
	_assert(crow.position.distance_to(crow.sim_position()) < 32.0,
		"and stays within a couple of tiles of where the sim says the bird is")

	# Shooing it is an Action through the one gateway, and the sim is what ends
	# the visit — which is why a replay ends it in the same place.
	var scared_before: int = GameState.crows_scared
	farm.apply_action({ "verb": "crow_scared", "actor": SimWorld.ACTOR_CROW }, GameState)
	_assert(GameState.crows_scared == scared_before + 1, "a scare counts toward the Q-12 proof")
	_assert(String(farm.sim.actor(SimWorld.ACTOR_CROW)["extra"].get("state", "")) == "leaving",
		"and turns the bird around in the sim, not in the node")

	# Fast-forward the sim past its departure; the sprite goes with it.
	farm.advance_sim(600, GameState)
	_assert(not farm.sim.has_actor(SimWorld.ACTOR_CROW), "the crow leaves the map and the registry")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(crow) or crow.is_queued_for_deletion(),
		"and its sprite is freed because the actor is gone, not because a node decided")


func _scenario_r_attract_shows_the_neighbour() -> void:
	# Finding F-3, killed as a test rather than patched (M2.5 WI-6, plan §4).
	#
	# The shipped demo opens with the cold open: a string of `actor: "neighbour"`
	# entries in which somebody tills, plants, waters and then opens the gate. The
	# title screen played every one of them with **nobody on screen** — the farm
	# was drawn by a farm node and the entities existed only because `main.gd`
	# built them, so the designer watched tiles till themselves. Worse, the entries
	# were handed to the *farmer*, who walked across the map to do the neighbour's
	# work.
	#
	# Both halves are asserted here: a neighbour sprite exists in the attract
	# farm's own actor layer, and it is the thing that moves during those beats.
	print("\n--- Scenario R: the attract loop shows the neighbour working her row ---")

	var demo := ReplayLog.load_from("res://assets/demo/demo_replay.json")
	_assert(demo != null and not demo.entries.is_empty(), "the shipped demo replay loads")
	if demo == null or demo.entries.is_empty():
		return
	var cold_open_beats := 0
	for e in demo.entries:
		if String(e.get("actor", "")) == SimWorld.ACTOR_NEIGHBOUR:
			cold_open_beats += 1
	_assert(cold_open_beats > 0,
		"and it opens on the cold open (%d neighbour entries — the F-3 evidence)" % cold_open_beats)

	var AttractScript = load("res://ui/attract_loop.gd")
	var loop = AttractScript.new()
	loop.name = "AttractNeighbourLoop"
	add_child(loop)
	_assert(loop.begin(demo), "the attract loop starts on it")

	# The sprite exists because the *registry* holds her, not because this scene
	# built one — which is the whole of the fix, and why it works for the hen and
	# a crow too.
	var her = loop.farm.actor_nodes.get(SimWorld.ACTOR_NEIGHBOUR, null)
	_assert(her != null and is_instance_valid(her),
		"the attract farm has a neighbour sprite, drawn from the actor registry")
	_assert(loop.farm.actor_nodes.has(SimWorld.ACTOR_CHICKEN),
		"and a hen, by the same mechanism and with no code that knows about hens")
	if her == null:
		loop.queue_free()
		await get_tree().process_frame
		return
	_assert(her.get_parent() == loop.farm.actors_node,
		"living under the attract farm, not under the played game's entity layer")
	_assert(loop.farm.actors_node != main_scene.entities,
		"which is a different layer from the one the player's own farm draws")

	# Play the cold-open beats. She walks to each target at 26 px/s and the loop
	# waits for her stride, so this is thousands of sixtieths — bounded, and it
	# stops the moment both things being asserted are true.
	var start_pos: Vector2 = her.position
	var moved := false
	var beats := 0
	for i in 6000:
		loop._process(1.0 / 60.0)
		if not is_instance_valid(her):
			break
		if her.position.distance_to(start_pos) > 8.0:
			moved = true
		beats = loop._next
		if moved and beats > 0:
			break
	_assert(moved, "she walks her row while those beats play (%s → %s)"
		% [start_pos, her.position if is_instance_valid(her) else Vector2.ZERO])
	_assert(beats > 0, "and the beats are being performed (%d entries in)" % beats)
	# The farmer stays out of it: the neighbour's plot is over the fence, and a
	# playback that sent the farmer there is the same bug from the other side.
	var farmer_t: Vector2i = loop.player.get_tile_pos()
	var plot: Dictionary = loop.farm.sim.layout.get("neighbour_plot", {})
	var wave_at: Vector2i = plot.get("wave_at", Vector2i(-1, -1))
	_assert(absi(farmer_t.x - wave_at.x) + absi(farmer_t.y - wave_at.y) > 1,
		"and the farmer is not the one doing it — she is at %s, the neighbour's row is at %s"
			% [farmer_t, wave_at])

	# Play the rest of it: she works her row, opens the gate and walks off. The
	# registry drops her at `open_gate` (WI-2 deviation 3), and this is the one
	# place a registry-driven renderer must deliberately *not* follow the registry
	# — a sprite that vanished mid-wave would lose the only goodbye in the game.
	var departed := false
	for i in 40000:
		loop._process(1.0 / 60.0)
		if ColdOpen.is_done(loop.farm.sim):
			departed = not is_instance_valid(her) or her.is_queued_for_deletion() \
				or her.is_departing()
			break
	_assert(ColdOpen.is_done(loop.farm.sim), "the cold open plays through to the gate opening")
	_assert(not loop.farm.sim.has_actor(SimWorld.ACTOR_NEIGHBOUR),
		"which drops her from the registry, the moment it opens")
	_assert(departed, "and her sprite is spared to walk off the map, not freed with the actor")

	# The general claim, checked on the species that proves it: a machine. Nothing
	# in the live game places a sprinkler (Q-15), so this is the only place its
	# renderer can be exercised — and it is exercised in a *detached* farm, which
	# is also the point. No code here knows what a sprinkler is; the species row
	# and one line of `ACTOR_RENDERERS` are the whole binding (M2.5 WI-6, WI-10).
	loop.farm.sim.spawn_actor("sprinkler", SpeciesDefs.SPRINKLER, Vector2i(6, 8))
	loop.farm.sync_actors()
	var machine = loop.farm.actor_nodes.get("sprinkler", null)
	_assert(machine != null and is_instance_valid(machine),
		"spawning a sprinkler in the registry gives it a sprite, with no renderer change")
	if machine != null:
		_assert(machine.position == Vector2(6 * 16, 8 * 16), "standing on its own tile")
		_assert(machine._spray_timer <= 0.0, "idle to begin with (objects.png row 1 col 5)")
		# A machine acts *inside* the day turn, so there is no tick to notice it
		# on: the farm tells its sprites a morning happened.
		loop.farm.apply_action({ "verb": "sleep", "actor": "world" }, loop.gs)
		_assert(machine._spray_timer > 0.0,
			"and it is drawn spraying after the day turn it waters on (col 6)")
		loop.farm.sim.despawn_actor("sprinkler")
		loop.farm.sync_actors()
		_assert(not loop.farm.actor_nodes.has("sprinkler"),
			"and the sprite goes when the actor does")

	loop.queue_free()
	await get_tree().process_frame


func _scenario_s_a_raid_is_drawn() -> void:
	# The ant pair's renderer, exercised the only way it can be (M2.5 WI-8a/8b).
	#
	# Nothing in the live game spawns an ant — `SimWorld.ANT_RAIDS_PER_DAY` is 0
	# and the debut is a designer's content-sequencing call — so this is the
	# sprinkler's situation exactly, and it gets the sprinkler's treatment: a
	# **detached** farm, an actor put into the registry by hand, and the claim
	# being checked is that *no code here knows what an ant is*. A species row and
	# two lines of `ACTOR_RENDERERS` are the whole binding.
	print("\n--- Scenario S: a raid gets drawn, because the registry holds one ---")

	var FarmScript = load("res://world/farm.gd")
	var yard = FarmScript.new()
	yard.name = "AntYard"
	yard.mute_feedback = true
	add_child(yard)
	await get_tree().process_frame

	var nest := Vector2i(6, 8)
	yard.sim.spawn_actor(SimWorld.ACTOR_ANT_SCOUT, SpeciesDefs.ANT_SCOUT, nest, {})
	yard.sim.spawn_actor("ant_forager_0", SpeciesDefs.ANT_FORAGER, nest + Vector2i(1, 0), {})
	yard.sync_actors()

	var scout = yard.actor_nodes.get(SimWorld.ACTOR_ANT_SCOUT, null)
	var forager = yard.actor_nodes.get("ant_forager_0", null)
	_assert(scout != null and is_instance_valid(scout),
		"spawning a scout in the registry gives it a sprite, with no renderer change")
	_assert(forager != null and is_instance_valid(forager),
		"and so does a forager, from the same one script")
	if scout == null or forager == null:
		yard.queue_free()
		await get_tree().process_frame
		return

	_assert(scout.position == Vector2(nest.x * 16, nest.y * 16), "standing on its own tile")
	# critters.png row 0: cols 0–1 the scout, cols 2–3 the forager (CREDITS.md).
	# The two species differ by a number off the species row, not by a class.
	_assert(scout.first_cell == 0 and forager.first_cell == 2,
		"drawing its own two cells of the sheet, chosen from the species and nothing else")
	_assert(scout.get_script() == forager.get_script(),
		"and both are the same script — they differ by their row, which is the point")

	# The sprite follows sim truth, exactly as the hen's does: the sim puts an
	# actor on a tile and the renderer walks the sprite between tiles.
	var was: Vector2 = scout.position
	yard.sim.set_actor_pos(SimWorld.ACTOR_ANT_SCOUT, nest + Vector2i(3, 0))
	for i in 30:
		scout._process(1.0 / 60.0)
	_assert(scout.position.x > was.x, "it walks toward wherever the sim has put it")
	_assert(not scout.facing_left, "facing the way it is going")
	yard.sim.set_actor_pos(SimWorld.ACTOR_ANT_SCOUT, nest)
	scout._process(1.0 / 60.0)
	_assert(scout.facing_left, "and the cells are mirrored when it turns back (they all face right)")

	# Stomped, dispersed, or home with its crop — the sim dropping the actor is
	# the only way an ant ends, and the sprite goes with it.
	yard.sim.despawn_actor(SimWorld.ACTOR_ANT_SCOUT)
	yard.sync_actors()
	_assert(not yard.actor_nodes.has(SimWorld.ACTOR_ANT_SCOUT),
		"and the sprite goes when the actor does")

	yard.queue_free()
	await get_tree().process_frame


func _scenario_t_the_bestiary_is_drawn() -> void:
	# The tier-1 visitors' renderers, exercised the only way they can be
	# (M2.5 WI-8c/8f/8g).
	#
	# Scenario S's treatment, for the same reason: nothing in the live game spawns
	# a rabbit, a kangaroo or a songbird — every `per_day` in
	# `SimWorld.visitors()` is 0 and the debut is a designer's content-sequencing
	# call — so this is a **detached** farm with actors put into the registry by
	# hand, and the claim being checked is that *no code here knows what a rabbit
	# is*. Three species rows and three lines of `ACTOR_RENDERERS` are the whole
	# binding, and two of those lines name the same script.
	print("\n--- Scenario T: the bestiary gets drawn, because the registry holds it ---")

	var FarmScript = load("res://world/farm.gd")
	var yard = FarmScript.new()
	yard.name = "Meadow"
	yard.mute_feedback = true
	add_child(yard)
	await get_tree().process_frame

	var at := Vector2i(7, 9)
	yard.sim.spawn_actor(SpeciesDefs.RABBIT, SpeciesDefs.RABBIT, at, {})
	yard.sim.spawn_actor(SpeciesDefs.KANGAROO, SpeciesDefs.KANGAROO, at + Vector2i(2, 0), {})
	yard.sim.spawn_actor(SpeciesDefs.SONGBIRD, SpeciesDefs.SONGBIRD, at + Vector2i(4, 0), {
		"state": SongbirdBrain.STATE_FLYING, "fx": 11.0, "fy": 9.0,
	})
	yard.sync_actors()

	var rabbit = yard.actor_nodes.get(SpeciesDefs.RABBIT, null)
	var roo = yard.actor_nodes.get(SpeciesDefs.KANGAROO, null)
	var bird = yard.actor_nodes.get(SpeciesDefs.SONGBIRD, null)
	_assert(rabbit != null and roo != null and bird != null,
		"spawning three new species gives three sprites, with no renderer change")
	if rabbit == null or roo == null or bird == null:
		yard.queue_free()
		await get_tree().process_frame
		return

	_assert(rabbit.position == Vector2(at.x * 16, at.y * 16), "each standing on its own tile")
	# critters.png row 1 is the rabbit's hop, row 4 the kangaroo's (CREDITS.md).
	# The two species differ by a number off the species row, not by a class.
	_assert(rabbit.sheet_row == 1 and roo.sheet_row == 4,
		"each drawing its own row of the sheet, chosen from the species and nothing else")
	_assert(rabbit.get_script() == roo.get_script(),
		"and both are the same script — as they are the same brain, which is the point")
	_assert(roo.speed_px > rabbit.speed_px,
		"the kangaroo's sprite moves faster because its row says so, not because this file does")

	# The sprite follows sim truth, exactly as the hen's does: the sim puts an
	# actor on a tile and the renderer walks the sprite between tiles.
	var was: Vector2 = rabbit.position
	yard.sim.set_actor_pos(SpeciesDefs.RABBIT, at + Vector2i(3, 0))
	for i in 30:
		rabbit._process(1.0 / 60.0)
	_assert(rabbit.position.x > was.x, "it hops toward wherever the sim has put it")
	_assert(not rabbit.facing_left, "facing the way it is going")
	yard.sim.set_actor_pos(SpeciesDefs.RABBIT, at)
	rabbit._process(1.0 / 60.0)
	_assert(rabbit.facing_left, "and the cells are mirrored when it turns back (they all face right)")

	# The bird reads a *continuous* position, the crow's pairing — so a flyer's
	# sprite is not quantised to the ten-hertz tile the registry holds.
	var bird_was: Vector2 = bird.position
	yard.sim.actor(SpeciesDefs.SONGBIRD)["extra"]["fx"] = 11.4
	for i in 20:
		bird._process(1.0 / 60.0)
	_assert(bird.position.x > bird_was.x,
		"the songbird flies on the sub-tile position its brain keeps, not on the rounded one")
	_assert(not bird.perched(), "and flaps while it is flying")
	yard.sim.actor(SpeciesDefs.SONGBIRD)["extra"]["state"] = SongbirdBrain.STATE_PERCHED
	_assert(bird.perched(), "and sits still on the perched cell when the sim says it has landed")

	# Fed, bored or off the map — the sim dropping the actor is the only way any
	# of these visits ends, and the sprite goes with it.
	for id in [SpeciesDefs.RABBIT, SpeciesDefs.KANGAROO, SpeciesDefs.SONGBIRD]:
		yard.sim.despawn_actor(String(id))
	yard.sync_actors()
	_assert(not yard.actor_nodes.has(SpeciesDefs.RABBIT)
			and not yard.actor_nodes.has(SpeciesDefs.KANGAROO)
			and not yard.actor_nodes.has(SpeciesDefs.SONGBIRD),
		"and every sprite goes when its actor does")

	yard.queue_free()
	await get_tree().process_frame


func _scenario_u_under_and_over() -> void:
	# The last two renderers, and the two of them are the awkward cases the rest of
	# the actor system never had to answer (M2.5 WI-8d/8e).
	#
	# Scenarios S and T's treatment, for their reason: nothing in the live game
	# spawns a mole or a worm — both `per_day` values are 0 and the debut is a
	# designer's content-sequencing call — so this is a **detached** farm with
	# actors put into the registry by hand. What is new here is not the binding (a
	# species row and a line of `ACTOR_RENDERERS`, as ever) but what the binding
	# has to carry: **one actor drawn as no sprite at all**, and **one actor drawn
	# as several**.
	print("\n--- Scenario U: the one you cannot see, and the one that is four tiles ---")

	var FarmScript = load("res://world/farm.gd")
	var yard = FarmScript.new()
	yard.name = "Burrow"
	yard.mute_feedback = true
	add_child(yard)
	await get_tree().process_frame

	# A cleared strip to crawl along: the yard is an ordinary generated farm, and a
	# worm walked by the engine needs ground the engine will let it onto.
	var at := Vector2i(7, 9)
	for ty in range(8, 13):
		for tx in range(6, 20):
			yard.sim.set_tile_state(tx, ty, "cleared")
			yard.sim.set_object(tx, ty, "")
	yard.sim.spawn_actor(SpeciesDefs.MOLE, SpeciesDefs.MOLE, at, {
		"state": MoleBrain.STATE_TUNNEL, "under": true,
	})
	yard.sim.spawn_actor(SpeciesDefs.WORM, SpeciesDefs.WORM, at + Vector2i(5, 0), {
		"state": WormBrain.STATE_HUNT,
	})
	yard.sync_actors()

	var mole = yard.actor_nodes.get(SpeciesDefs.MOLE, null)
	var worm = yard.actor_nodes.get(SpeciesDefs.WORM, null)
	_assert(mole != null and worm != null,
		"spawning the last two species gives two sprites, with no renderer change")
	if mole == null or worm == null:
		yard.queue_free()
		await get_tree().process_frame
		return

	# --- the mole: three cells, and the sim picks which ----------------------
	# critters.png row 2 is mound / emerging / surfaced (CREDITS.md). The renderer
	# holds no animation state of its own: it asks `Movement.is_under` and the
	# brain's own state, so it cannot disagree with the world about what is
	# happening.
	_assert(mole.position == Vector2(at.x * 16, at.y * 16), "the mole is drawn on its own tile")
	_assert(mole.cell() == 0, "and while it is under the farm it is a **mound**, not a mole")
	yard.sim.actor(SpeciesDefs.MOLE)["extra"]["under"] = false
	yard.sim.actor(SpeciesDefs.MOLE)["extra"]["state"] = MoleBrain.STATE_EMERGE
	_assert(mole.cell() == 1, "the tick it surfaces, it is coming up")
	yard.sim.actor(SpeciesDefs.MOLE)["extra"]["state"] = MoleBrain.STATE_SURFACED
	_assert(mole.cell() == 2, "and then it is a mole standing on a tile")
	var was: Vector2 = mole.position
	yard.sim.set_actor_pos(SpeciesDefs.MOLE, at + Vector2i(3, 0))
	for i in 30:
		mole._process(1.0 / 60.0)
	_assert(mole.position.x > was.x, "it travels toward wherever the sim has put it")

	# --- the worm: one actor, several cells ---------------------------------
	# The first renderer in the game that draws more than one cell for one actor,
	# out of `Movement.occupied_tiles` (WI-6's handoff).
	var worm_at: Vector2i = at + Vector2i(5, 0)
	_assert(worm.segment_tiles().size() == 1 and worm.segment_cells() == [0],
		"a worm that has not moved is one tile, and that tile is its head")
	# Walk it three tiles with the engine, exactly as its brain does, and let it
	# grow the way a meal grows it (`extra.body_len`, WI-4's per-actor override).
	yard.sim.actor(SpeciesDefs.WORM)["extra"]["body_len"] = 4
	for i in 3:
		Movement.plan(yard.sim, SpeciesDefs.WORM, worm_at + Vector2i(i + 1, 0))
		Movement.step(yard.sim, SpeciesDefs.WORM, i)
	_assert(worm.segment_tiles().size() == 4, "after three crawls it is four tiles of worm")
	_assert(worm.segment_cells() == [0, 1, 1, 2],
		"drawn head, body, body, tail — one cell per tile it occupies (%s)"
			% str(worm.segment_cells()))
	# A corner puts a segment between a tile above it and a tile beside it; a
	# segment with both neighbours in its own column draws the vertical cell.
	Movement.plan(yard.sim, SpeciesDefs.WORM, worm_at + Vector2i(3, 1))
	Movement.step(yard.sim, SpeciesDefs.WORM, 4)
	Movement.plan(yard.sim, SpeciesDefs.WORM, worm_at + Vector2i(3, 2))
	Movement.step(yard.sim, SpeciesDefs.WORM, 5)
	_assert(worm.segment_cells()[1] == 3,
		"and a segment in a straight vertical run draws the vertical body cell (%s)"
			% str(worm.segment_cells()))
	# The bend itself (net flow diagonal: one neighbour above, one beside) draws
	# the joint — the symmetric cell — never the striped horizontal body, so a
	# cornering worm reads as one connected animal (designer directive 2026-09-01).
	_assert(worm.segment_cells()[2] == worm.CELL_JOINT,
		"a segment at the bend draws the joint cell (%s)" % str(worm.segment_cells()))
	# And the head, crawling downward, is rotated to face down rather than drawn
	# sideways — the directional cells rotate for vertical travel.
	var head_draw: Dictionary = worm.segment_draws()[0]
	_assert(head_draw.cell == worm.CELL_HEAD and is_equal_approx(head_draw.rot, PI / 2),
		"a head crawling down is rotated +90 deg, not sideways (rot=%f)" % head_draw.rot)
	var tail_draw: Dictionary = worm.segment_draws()[worm.segment_draws().size() - 1]
	_assert(tail_draw.cell == worm.CELL_TAIL and tail_draw.rot == 0.0 and not tail_draw.flip,
		"the tail on the horizontal run stays unrotated and unmirrored")
	for i in 60:
		worm._process(1.0 / 60.0)
	_assert(worm.seg_px.size() == worm.segment_tiles().size(),
		"every segment has a sprite position of its own, and they follow the head")
	_assert(worm.position == worm.seg_px[0],
		"the node itself is the head, which is what the farm's y-sort draws a worm by")
	# It is the slowest thing in the game (6 px/s), so catching up with five tiles
	# of crawl takes it a while — and it does catch up, without ever teleporting.
	var crawled := 0
	while crawled < 1200 and worm.position != Vector2(
			worm.segment_tiles()[0].x * 16, worm.segment_tiles()[0].y * 16):
		worm._process(1.0 / 60.0)
		crawled += 1
	_assert(crawled < 1200,
		"and the sprite crawls the whole way to the tile the sim has it on (%d frames)" % crawled)

	# Stomped, full, or curled up in itself — the sim dropping the actor is the
	# only way either of these ends, and the sprites go with them.
	for id in [SpeciesDefs.MOLE, SpeciesDefs.WORM]:
		yard.sim.despawn_actor(String(id))
	yard.sync_actors()
	_assert(not yard.actor_nodes.has(SpeciesDefs.MOLE) and not yard.actor_nodes.has(SpeciesDefs.WORM),
		"and every sprite goes when its actor does")

	yard.queue_free()
	await get_tree().process_frame


func _scenario_v_the_bot_is_drawn() -> void:
	# The bot's renderer, exercised the only way it can be (M2.5 WI-9).
	#
	# Scenarios S, T and U's treatment, for their reason: nothing in the live game
	# deploys a bot — Q-56 is ruled and the debut waits for at least M3 — so this
	# is a **detached** farm with an actor put into the registry by hand. What is
	# being checked is that a bot is a species row, a brain and one line of
	# `ACTOR_RENDERERS`, like everybody else, and that the line it needed was the
	# *player's own draw path*: `bot.png` is `characters.png`'s layout on purpose
	# (WI-6's handoff), so the sprite is 48 px cells, four rows of facing, frame 0
	# the standing idle — and none of that is new code.
	print("\n--- Scenario V: the machine gets drawn, out of the farmer's own sheet ---")

	var FarmScript = load("res://world/farm.gd")
	var yard = FarmScript.new()
	yard.name = "Depot"
	yard.mute_feedback = true
	add_child(yard)
	await get_tree().process_frame

	var at := Vector2i(8, 9)
	for ty in range(7, 13):
		for tx in range(6, 20):
			yard.sim.set_tile_state(tx, ty, "cleared")
			yard.sim.set_object(tx, ty, "")
	# Two configs of one machine: one line of ACTOR_RENDERERS draws both, because
	# a config is data on the actor rather than a species of its own.
	BotBrain.deploy(yard.sim, "follow_bot", BotBrain.CONFIG_FOLLOW, at)
	BotBrain.deploy(yard.sim, "shoo_bot", BotBrain.CONFIG_SHOO, at + Vector2i(4, 0))
	yard.sync_actors()

	var bot = yard.actor_nodes.get("follow_bot", null)
	var other = yard.actor_nodes.get("shoo_bot", null)
	_assert(bot != null and other != null,
		"deploying two bots gives two sprites, with no renderer change")
	if bot == null or other == null:
		yard.queue_free()
		await get_tree().process_frame
		return

	_assert(bot.get_script() == other.get_script(),
		"and both are the same script, because they are the same machine on a different setting")
	_assert(bot.position == Vector2(at.x * 16, at.y * 16), "standing on its own tile")
	_assert(bot.cell_region() == Rect2(0, 0, 48, 48),
		"drawn from bot.png's 48 px cells, frame 0 of the down row — the standing idle")
	_assert(is_equal_approx(bot.speed_px, SpeciesDefs.speed_of(SpeciesDefs.BOT) * 16.0 * 10.0),
		"its sprite walks at the speed its species row says, not at a number this file keeps")

	# The sprite follows sim truth, exactly as the hen's does: the sim puts an
	# actor on a tile and the renderer walks the sprite between tiles.
	var was: Vector2 = bot.position
	yard.sim.set_actor_pos("follow_bot", at + Vector2i(3, 0), "right")
	for i in 40:
		bot._process(1.0 / 60.0)
	_assert(bot.position.x > was.x, "it walks toward wherever the sim has put it")
	_assert(bot.cell_region().position.y == 3 * 48,
		"facing the way the sim says it is facing (the right-hand row of the sheet)")
	# ...and when it gets there it stops walking: frame 0 is the standing idle, so
	# a bot that arrived must not be marching in place (the hen's rule).
	var frames := 0
	while frames < 400 and not bot.position.is_equal_approx(bot.sim_position()):
		bot._process(1.0 / 60.0)
		frames += 1
	yard.sim.set_actor_pos("follow_bot", at + Vector2i(3, 0), "up")
	bot._process(1.0 / 60.0)
	_assert(bot.cell_region() == Rect2(0, 48, 48, 48),
		"and stands still on frame 0 of the row it now faces once it arrives (%d frames)" % frames)

	# Retired, recalled, or never deployed at all — the sim dropping the actor is
	# the only way a bot ends, and the sprite goes with it.
	for id in ["follow_bot", "shoo_bot"]:
		yard.sim.despawn_actor(String(id))
	yard.sync_actors()
	_assert(not yard.actor_nodes.has("follow_bot") and not yard.actor_nodes.has("shoo_bot"),
		"and every sprite goes when its actor does")

	yard.queue_free()
	await get_tree().process_frame

# --- T-27: the cot must present itself -----------------------------------------
# Counts sleeps the sim actually performed since a mark in the trace. `act`
# entries, not tap outcomes, because the question is what the *world* did.
func _sleeps_since(since: int) -> int:
	var n := 0
	for i in range(since, farm.trace.entries.size()):
		var e: Dictionary = farm.trace.entries[i]
		if String(e.get("kind", "")) == "act" and String(e.get("verb", "")) == "sleep" \
				and e.get("ok", false):
			n += 1
	return n


func _refusals_since(since: int) -> int:
	var n := 0
	for i in range(since, farm.trace.entries.size()):
		var e: Dictionary = farm.trace.entries[i]
		if String(e.get("out", "")) == "refused":
			n += 1
		elif String(e.get("kind", "")) == "act" and not e.get("ok", true):
			n += 1
	return n


func _last_tap_entry(since: int) -> Dictionary:
	for i in range(farm.trace.entries.size() - 1, since - 1, -1):
		if String(farm.trace.entries[i].get("kind", "")) == "tap":
			return farm.trace.entries[i]
	return {}


func _scenario_w_the_cot_presents_itself() -> void:
	# T-27, straight out of the 2026-08-30 tablet session, both halves of it:
	#
	#   * three cot taps in five seconds (3m37–42s) became about three days inside
	#     "day 12". `main.gd` returns early for the whole transition, so the player
	#     never ran and never *consumed* `has_click` — each tap sat in the buffer
	#     and fired on the first frame of morning, starting the next transition.
	#   * four `no_energy` refusals on (2,2) at 5m04–10s were every one of them a
	#     tap meant for the cot at (2,1), one tile north, resolved as till-with-hoe.
	#
	# Both are asserted here against the real main scene through the real input
	# path, because both were failures of the whole chain rather than of any one
	# function in it.
	print("\n--- Scenario W: the cot presents itself (T-27) ---")

	# The sleep autosaves, and the real game's autosave is the file
	# `verify_replay.gd` checks a human session against. Borrow different paths for
	# the scenario and put them back afterwards.
	var real_paths := [GameState.save_path, GameState.replay_path, GameState.trace_path]
	GameState.save_path = "user://t27_autosave.json"
	GameState.replay_path = "user://t27_replay.json"
	GameState.trace_path = "user://t27_trace.jsonl"

	var cot: Vector2i = main_scene._cot_tile
	_assert(cot.x >= 0, "the farm has a cot, and main.gd knows where it is")
	if cot.x < 0:
		return
	var below := cot + Vector2i(0, 1)          # (2,2) — the tile she kept hitting
	var beside := cot + Vector2i(1, 1)         # (3,2) — where she stood while doing it
	_stage_tile(below.x, below.y, "cleared")
	_stage_tile(beside.x, beside.y, "cleared")
	GameState.seeds["wheat"] = 0               # so cleared soil means "till", never "plant"

	# A wet, unripe crop to watch through the transition. Reported from play
	# 2026-09-01: "when you go to sleep, the ground re-renders as dry BEFORE the
	# fade out" — the sleep lands at the tap (D-8, asserted below), so the farm
	# was already washed dry while the lit world was still on screen.
	var crop_t := Vector2i(6, 10)
	_stage_tile(crop_t.x, crop_t.y, "growing", "wheat")
	farm.sim.tiles[crop_t.y][crop_t.x]["growth_stage"] = 2
	farm.sim.tiles[crop_t.y][crop_t.x]["watered_today"] = true

	# (a) One tap, one day — however many times she taps during the transition.
	GameState.set_energy(GameState.max_energy)
	player.pos = Vector2(below.x * 16 + 8.0, below.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	var day_before: int = GameState.day
	var mark: int = farm.trace.entries.size()
	InputManager.click_tile = cot
	InputManager.has_click = true
	var started := await _wait_until(func(): return main_scene.day_cycle.is_active(), 200)
	_assert(started, "tapping the cot starts the day transition")
	_assert(GameState.day == day_before + 1,
		"and the sim is ALREADY in the new day — the Action resolved at the tap, not behind the fade (D-8)")
	_assert(main_scene.day_cycle.state == "tucking",
		"the transition opens on the lit world rather than on the fade")
	_assert(player.tuck_tile == cot,
		"with the farmer drawn lying on the cot — her body answers the tap (T-27 box 1)")
	_assert(player.pos.distance_to(Vector2(below.x * 16 + 8.0, below.y * 16 + 8.0)) < 0.01,
		"and her actual position never moved: the pose is drawn, not walked (sim truth is untouched)")

	# The ground gets the sky's treatment: held until the screen is black.
	_assert(farm.is_tile_look_held(), "the ground she fell asleep on is held for the fade")
	_assert(not farm.sim.get_tile(crop_t.x, crop_t.y).watered_today,
		"even though the sim washed it dry at the tap (D-8 — the Action is never delayed)")
	_assert(farm.tile_look(crop_t.x, crop_t.y).watered_today,
		"so the soil she watered still draws wet while the world is still lit")

	# Now the hostile part, which is simply what a four-year-old does when nothing
	# appears to have happened yet: keep tapping. This covers the 1.5 s re-tap that
	# cost her a day, and every other instant of the window besides.
	var t0 := Time.get_ticks_msec()
	var taps := 0
	var guard := 0
	while main_scene.day_cycle.is_active() and guard < 2000:
		InputManager.click_tile = cot
		InputManager.has_click = true
		taps += 1
		guard += 1
		await get_tree().process_frame
	var window_ms := Time.get_ticks_msec() - t0
	_assert(taps > 0, "she tapped the cot again during the transition (%d times)" % taps)
	_assert(window_ms >= 1500,
		"and the window covered the whole transition, well past the 1.5 s re-tap (%d ms)" % window_ms)

	# Nothing may be left buffered to fire on the first frame of morning — that
	# buffer *is* the bug.
	for i in 60: await get_tree().process_frame
	_assert(GameState.day == day_before + 1,
		"the day advanced exactly once, however many times she tapped (day %d)" % GameState.day)
	_assert(_sleeps_since(mark) == 1,
		"and the sim saw exactly one sleep, not three (%d)" % _sleeps_since(mark))
	_assert(player.tuck_tile.x < 0, "she is out of bed by morning")
	_assert(not farm.is_tile_look_held(),
		"the ground was released under the black and is the morning's again")
	_assert(farm.tile_look(crop_t.x, crop_t.y).state == farm.sim.get_tile(crop_t.x, crop_t.y).state,
		"showing exactly what the sim says, with nothing held over from yesterday")
	_assert(not InputManager.is_swallowing(),
		"and the window is shut again — a tap the instant after it is an ordinary tap")

	# (b) The fat finger: no energy, hoe in hand, one tile south of the cot.
	var mark2: int = farm.trace.entries.size()
	var day2: int = GameState.day
	GameState.set_energy(0)
	GameState.selected_tool = 3  # hoe, exactly as the trace recorded
	_stage_tile(below.x, below.y, "cleared")
	player.pos = Vector2(beside.x * 16 + 8.0, beside.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = below
	InputManager.has_click = true
	var slept := await _wait_until(func(): return GameState.day == day2 + 1, 600)
	_assert(slept, "a tap one tile below the cot, with no energy, puts her to bed (her exact case)")
	var haloed := _last_tap_entry(mark2)
	_assert(haloed.get("tile", []) == [below.x, below.y],
		"and the trace still records the tile her finger actually hit")
	_assert(haloed.get("halo", []) == [cot.x, cot.y],
		"with the tile it was rescued to recorded beside it")
	_assert(_refusals_since(mark2) == 0,
		"no refusal was logged at all — the miss never became a 'no' (it used to be four)")
	await _wait_until(func(): return not main_scene.day_cycle.is_active(), 600)
	for i in 5: await get_tree().process_frame

	# (c) The tapped tile still wins whenever it can do something.
	var mark3: int = farm.trace.entries.size()
	var day3: int = GameState.day
	GameState.set_energy(GameState.max_energy)
	GameState.selected_tool = 3
	_stage_tile(below.x, below.y, "cleared")
	player.pos = Vector2(beside.x * 16 + 8.0, beside.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame
	InputManager.click_tile = below
	InputManager.has_click = true
	var tilled := await _wait_until(
		func(): return farm.get_tile(below.x, below.y).state == "tilled", 600)
	_assert(tilled, "with energy in the bank the same tap tills the tile she hit")
	_assert(GameState.day == day3, "and she did not go to bed")
	_assert(not _last_tap_entry(mark3).has("halo"),
		"nothing was rescued — the tapped tile wins whenever it produces a real change")

	GameState.seeds["wheat"] = 5
	for p in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	GameState.save_path = real_paths[0]
	GameState.replay_path = real_paths[1]
	GameState.trace_path = real_paths[2]


func _find_button(root: Node, node_name: String) -> Button:
	if root is Button and root.name == node_name:
		return root
	for child in root.get_children():
		var hit := _find_button(child, node_name)
		if hit != null:
			return hit
	return null


func _scenario_x_three_looks_for_the_cot() -> void:
	# T-27's last box, drafted rather than decided: three treatments for "the cot
	# must look like sleeping before first use", all three in this build, switched
	# on device (Q-31's Sound Test precedent). The designer picks; this scenario
	# only holds the drafts to the rules they have to obey either way.
	#
	# The load-bearing one is D-8. Scenario W proves that a cot tap resolves *at
	# the tap* under the default; a presentation treatment is exactly the kind of
	# change that could quietly turn that into a wind-up, so the same property is
	# re-proved once per treatment against the real main scene.
	print("\n--- Scenario X: three looks for the cot, and none of them gates the tap (T-27) ---")

	var real_paths := [GameState.save_path, GameState.replay_path, GameState.trace_path]
	GameState.save_path = "user://t27x_autosave.json"
	GameState.replay_path = "user://t27x_replay.json"
	GameState.trace_path = "user://t27x_trace.jsonl"
	var was_treatment: int = CotPresentation.treatment

	var cot: Vector2i = main_scene._cot_tile
	_assert(cot.x >= 0, "the farm has a cot")
	if cot.x < 0:
		return
	var below := cot + Vector2i(0, 1)
	_stage_tile(below.x, below.y, "cleared")
	GameState.seeds["wheat"] = 0

	# The switch itself. Both doors write the same static, and it is the static —
	# not the scene — that carries the pick across a return to the title screen.
	CotPresentation.set_treatment(CotPresentation.GLOW)
	var seen: Array[int] = []
	for i in CotPresentation.COUNT:
		seen.append(CotPresentation.treatment)
		CotPresentation.cycle()
	_assert(seen == [CotPresentation.GLOW, CotPresentation.PULSE, CotPresentation.TURNDOWN],
		"the toggle cycles A → B → C")
	_assert(CotPresentation.treatment == CotPresentation.GLOW,
		"and wraps back to A, so a thumb can never park it on nothing")

	# Door 1, the one that matters at dusk: pause → the cot option, which advances
	# and closes so the farm is visible again immediately.
	main_scene.menus.open_menu("pause")
	await get_tree().process_frame
	var labels: Array = []
	_collect_labels(main_scene.menus.options_container, labels)
	var has_switch := false
	for l in labels:
		if String(l.text).begins_with("Cot look:"):
			has_switch = true
	_assert(has_switch, "the pause menu carries the cot switch (debug builds), naming the current look")
	main_scene.menus.selected_option = 2
	main_scene.menus._select_current_option()
	await get_tree().process_frame
	_assert(CotPresentation.treatment == CotPresentation.PULSE,
		"tapping it advances the treatment")
	_assert(not main_scene.menus.is_open(),
		"and closes the menu, so the farm is what he is looking at when it changes")
	_assert(main_scene.camera.limit_top
			== CotPresentation.camera_top_limit(main_scene.HUD_TOP_PX, main_scene.CAMERA_SCALE),
		"the live camera picked up the new treatment's Q-68 answer without a reload")

	# Door 2, Q-31's precedent proper: the title screen's panel, beside the Sound
	# Test's own button. Built here for real, because a switch that only exists in
	# a comment is not a switch. Generalised by T-28 into the Look Lab — same
	# gate, same panel, same corner, now one section per open question.
	var title = load("res://ui/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	var opener := _find_button(title, "LookLabButton")
	_assert(opener != null, "the title screen offers 'Look Lab' beside 'Sound Test'")
	if opener != null:
		opener.pressed.emit()
		await get_tree().process_frame
		var picks := 0
		for i in CotPresentation.COUNT:
			if _find_button(title, "Look_%s_%d" % [LookLab.COT, i]) != null:
				picks += 1
		_assert(picks == CotPresentation.COUNT,
			"and the panel offers every cot treatment the game can draw (%d)" % picks)
		var c_button := _find_button(title, "Look_%s_%d" % [LookLab.COT, CotPresentation.TURNDOWN])
		if c_button != null:
			c_button.pressed.emit()
			await get_tree().process_frame
			_assert(CotPresentation.treatment == CotPresentation.TURNDOWN,
				"picking one there selects it")
	title.queue_free()
	await get_tree().process_frame

	# Each treatment, in the real scene: it draws, it looks like itself, and the
	# tap still resolves at the tap.
	for t in [CotPresentation.GLOW, CotPresentation.PULSE, CotPresentation.TURNDOWN]:
		var label: String = CotPresentation.name_of(t)
		CotPresentation.set_treatment(t)
		main_scene._apply_cot_treatment()
		# Dusk, which is the hour every one of these is about. 60 of 600 is where
		# `energy = 2` sat on the old 20-point day (T-29) — the same instant.
		GameState.set_energy(60)
		await get_tree().process_frame

		_assert(main_scene.camera.limit_top
				== CotPresentation.camera_top_limit(main_scene.HUD_TOP_PX, main_scene.CAMERA_SCALE),
			"%s: the camera carries this treatment's Q-68 answer" % label)
		_assert(farm.cot_turned_down == (t == CotPresentation.TURNDOWN),
			"%s: the bed is turned down under C and made under the others" % label)
		if t == CotPresentation.TURNDOWN:
			_assert(farm.object_regions.has("cot_turned_down"),
				"%s: and the second cell it draws from exists on the sheet" % label)

		# Renders. The counter is the witness: a draw callback that throws part way
		# through prints a red line and fails nothing, so the assertion is that the
		# block reached its end, not that the log was quiet.
		var drew: int = main_scene.cot_draws
		for i in 4:
			await get_tree().process_frame
		_assert(main_scene.cot_draws > drew,
			"%s: the cot block draws to completion, frame after frame (%d)"
				% [label, main_scene.cot_draws - drew])

		# D-8, once per treatment: presentation never gates the gateway.
		var day_before: int = GameState.day
		player.pos = Vector2(below.x * 16 + 8.0, below.y * 16 + 8.0)
		player.path.clear()
		player.pending_action = {}
		await get_tree().process_frame
		InputManager.click_tile = cot
		InputManager.has_click = true
		var started := await _wait_until(func(): return main_scene.day_cycle.is_active(), 200)
		_assert(started, "%s: tapping the cot starts the day transition" % label)
		_assert(GameState.day == day_before + 1,
			"%s: and the sim is ALREADY in the new day — the Action resolved at the tap (D-8)" % label)
		await _wait_until(func(): return not main_scene.day_cycle.is_active(), 600)
		for i in 5:
			await get_tree().process_frame

	# Put everything back: the default is A, and the next scenario (and the human
	# holding the tablet) gets the game as shipped.
	CotPresentation.set_treatment(was_treatment)
	main_scene._apply_cot_treatment()
	_assert(CotPresentation.treatment == CotPresentation.GLOW,
		"and the build's default, restored, is A — the box stays the designer's to tick")
	GameState.seeds["wheat"] = 5
	for p in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	GameState.save_path = real_paths[0]
	GameState.replay_path = real_paths[1]
	GameState.trace_path = real_paths[2]


func _scenario_y_acorns_are_pickable() -> void:
	# T-30 (Q-48), in the real scene: the whole chain a thumb goes through, from a
	# tap on a nut lying in the grass to the crow's larder being one meal shorter.
	# The unit suite owns the rule (`test_acorn_pickup`); what this scenario adds
	# is that the tap actually reaches it — the router, the approach, the walk and
	# the gateway, wired together in `main.tscn` with nothing stubbed.
	print("\n--- Scenario Y: acorns are pickable (T-30) ---")

	var stand := Vector2i(6, 6)
	var nut := Vector2i(7, 6)          # one step east of her, so she is already beside it
	_stage_tile(stand.x, stand.y, "cleared")
	_stage_tile(nut.x, nut.y, "cleared")
	farm.sim.set_object(nut.x, nut.y, "acorn")
	GameState.seeds["wheat"] = 0        # so cleared soil means "till", never "plant"
	GameState.selected_tool = 3         # hoe in hand: the tap could have meant "till"
	GameState.set_energy(GameState.max_energy)
	player.pos = Vector2(stand.x * 16 + 8.0, stand.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	var had: int = GameState.acorns
	var stock: int = farm.sim.count_acorns()
	var mark: int = farm.trace.entries.size()
	InputManager.click_tile = nut
	InputManager.has_click = true
	var picked := await _wait_until(func(): return GameState.acorns == had + 1, 600)
	_assert(picked, "tapping an acorn picks it up, hoe in hand and tillable ground under it")
	_assert(farm.get_object(nut.x, nut.y) == "", "the tile is bare afterwards")
	_assert(farm.get_tile(nut.x, nut.y).state == "cleared",
		"and the ground beneath it was never tilled — the object answered, not the soil")
	_assert(farm.sim.count_acorns() == stock - 1,
		"the crow's stock is one shorter (%d)" % farm.sim.count_acorns())
	_assert(_refusals_since(mark) == 0, "and nothing was refused along the way")

	GameState.seeds["wheat"] = 5


# Her walk has finished for the purposes of a wait: she is standing beside the
# tile she was sent to (Q-30 — a workable tile is one she stops *beside*, never on
# top of), or she has gone to bed instead, which the caller is about to fail on.
func _walk_settled(t: Vector2i) -> bool:
	if main_scene.day_cycle.is_active():
		return true
	var p: Vector2i = player.get_tile_pos()
	return absi(p.x - t.x) + absi(p.y - t.y) <= 1


func _scenario_z_a_bed_button() -> void:
	# T-31 (Q-49).
	# The HUD's first action control, and the ruling it comes from: T-27's fixes
	# make the cot findable *once it is on screen*, and by evening it usually is
	# not — *"a tired player should not have to find the bed."*
	#
	# The whole design is in one sentence: the button is **an ordinary cot tap**.
	# So this scenario asserts the two things that sentence has to survive — that
	# it really walks her there (rather than sleeping her where she stands) and
	# that it inherits the cot tap's behaviour under T-27's transition window and
	# under a retarget — plus the wordless/geometry rules the HUD owes it.
	print("\n--- Scenario Z: a bed button on the HUD (T-31) ---")

	var real_paths := [GameState.save_path, GameState.replay_path, GameState.trace_path]
	GameState.save_path = "user://t31_autosave.json"
	GameState.replay_path = "user://t31_replay.json"
	GameState.trace_path = "user://t31_trace.jsonl"

	var hud = main_scene.hud
	var cot: Vector2i = main_scene._cot_tile
	var bed := _find_button(main_scene, "BedButton")
	_assert(bed != null, "the HUD carries a bed button")
	if bed == null or cot.x < 0:
		return

	# 1. It is there to be found, and it says nothing (S-7).
	_assert(bed.visible and not bed.disabled,
		"it is visible and live from the start — discovery is the whole point (D-8: it gates nothing)")
	_assert(not _has_letters(bed.text), "and wordless: the picture is the cot's own sprite cell")
	_assert(bed.get_node("bed_button_icon").texture != null, "which is actually loaded")
	_assert(bed.size.x >= 40 and bed.size.y >= 40,
		"and it is a thumb-sized target (%dx%d)" % [int(bed.size.x), int(bed.size.y)])

	# 2. Geometry: nowhere near the top bar, whose treatment Q-68 is still open on.
	var bar := Rect2(hud.top_bar.position, hud.top_bar.size)
	_assert(not bar.intersects(Rect2(bed.position, bed.size)),
		"it sits clear of the top bar, so Q-68's ruling cannot collide with it")

	# 3. The walk. She is across the yard from the cot; the button must take her
	#    there on her own feet, not put her to bed where she stands.
	GameState.set_energy(GameState.max_energy)
	var start := Vector2i(6, 5)
	_stage_tile(start.x, start.y, "cleared")
	player.pos = Vector2(start.x * 16 + 8.0, start.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	var day_before: int = GameState.day
	var mark: int = farm.trace.entries.size()
	bed.pressed.emit()
	_assert(GameState.day == day_before,
		"pressing it does not sleep her on the spot — there is a farm to cross first")
	var walking := await _wait_until(func(): return not player.path.is_empty(), 300)
	_assert(walking, "she sets off toward the cot")
	var started := await _wait_until(func(): return main_scene.day_cycle.is_active(), 12000)
	_assert(started, "and when she gets there, she goes to bed")
	var at_cot: Vector2i = player.get_tile_pos()
	_assert(absi(at_cot.x - cot.x) + absi(at_cot.y - cot.y) <= 1,
		"having walked to the cot's own side (%d,%d) — no teleport" % [at_cot.x, at_cot.y])
	_assert(GameState.day == day_before + 1,
		"the sim is already in the new day — the Action resolved at the tap, like any cot tap (D-8)")
	_assert(player.tuck_tile == cot, "and she is drawn lying on the cot (T-27 box 1)")

	# 4. T-27 box 2 covers the button for free: presses during the transition are
	#    dropped at the input boundary, so they cannot buffer into the morning.
	var presses := 0
	var guard := 0
	while main_scene.day_cycle.is_active() and guard < 4000:
		bed.pressed.emit()
		presses += 1
		guard += 1
		await get_tree().process_frame
	_assert(presses > 0, "she pressed it again during the transition (%d times)" % presses)
	for i in 60: await get_tree().process_frame
	_assert(GameState.day == day_before + 1,
		"the day still advanced exactly once (day %d)" % GameState.day)
	_assert(_sleeps_since(mark) == 1,
		"and the sim saw exactly one sleep (%d)" % _sleeps_since(mark))

	# 5. It is a tap, so a new tap overrides it — pressing it by mistake costs her
	#    one tap to undo, exactly like tapping the wrong tile.
	GameState.set_energy(GameState.max_energy)
	var elsewhere := Vector2i(8, 7)
	_stage_tile(elsewhere.x, elsewhere.y, "cleared")
	GameState.seeds["wheat"] = 0        # nothing to plant there: a pure walk order
	GameState.selected_tool = 0
	player.pos = Vector2(start.x * 16 + 8.0, start.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	var day_mid: int = GameState.day
	bed.pressed.emit()
	await _wait_until(func(): return not player.path.is_empty(), 300)
	# Mid-walk by condition, not by counting frames: under load a frame carries
	# more wall-clock, and 40 of them could be the whole walk — the retarget then
	# lands on a farmer already in bed. One tile crossed is provably mid-walk
	# from anywhere in the yard, however long a frame is.
	await _wait_until(func(): return player.get_tile_pos() != start, 600)
	InputManager.click_tile = elsewhere
	InputManager.has_click = true
	var retargeted := await _wait_until(func(): return player.approach_target == elsewhere, 300)
	_assert(retargeted,
		"a tap mid-walk retargets her — the walk order is the finger's now, not the button's")
	var arrived := await _wait_until(func(): return _walk_settled(elsewhere), 12000)
	_assert(arrived and not main_scene.day_cycle.is_active(),
		"and she walks to where the finger said instead of to bed")
	_assert(GameState.day == day_mid, "and the day did not turn")

	GameState.seeds["wheat"] = 5
	for p in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	GameState.save_path = real_paths[0]
	GameState.replay_path = real_paths[1]
	GameState.trace_path = real_paths[2]


func _scenario_aa_the_yard_is_home() -> void:
	# T-32, the designer 2026-09-01: *"create a separate form of ground that cannot
	# be tilled, and fill the initial fenced space with it."*
	#
	# The rule has two halves and they are asserted in two places on purpose:
	#
	#   * **the gateway refuses a till on yard ground** — S-3, so it binds a bot and
	#     a crow the same way it binds her;
	#   * **the tap never meets that refusal** — T-18. `yard` is in no tool's
	#     `can_act_on` and in no `is_workable` state, so the router has no opinion
	#     about it at all, and the only answer left for a tile nothing can be done
	#     to is movement. A hoe held over the yard must produce a **walk**, not a
	#     wobble, and this is where that is proved through the real input path.
	print("\n--- Scenario AA: the yard is home, not field (T-32) ---")

	# 1. What generation makes. A detached farm, because by now the scenarios above
	#    have farmed half the live yard flat on purpose — which is still legal, it
	#    is just no longer what a fresh farm looks like.
	var FarmScript = load("res://world/farm.gd")
	var fresh = FarmScript.new()
	fresh.name = "Dooryard"
	fresh.mute_feedback = true
	add_child(fresh)
	await get_tree().process_frame

	var yard_rect: Rect2i = WorldLayout.parcels()[0]["rects"][0]
	var yard_tiles := 0
	var strays := 0
	for ty in range(yard_rect.position.y, yard_rect.end.y):
		for tx in range(yard_rect.position.x, yard_rect.end.x):
			if String(fresh.get_tile(tx, ty).get("state", "")) == WorldLayout.YARD:
				yard_tiles += 1
			else:
				strays += 1
	_assert(strays == 0 and yard_tiles == yard_rect.get_area(),
		"a fresh farm's fenced space is yard ground, every tile of it (%d/%d)"
			% [yard_tiles, yard_rect.get_area()])
	_assert(fresh.sim.is_walkable(5, 3), "which she walks across like any other ground")

	# The cot's move is part of the same directive: down three, left-aligned, its
	# 16x32 sprite filling rows 3-4 of the yard's rows 1-6.
	var cot_now := Vector2i(-1, -1)
	for ty in SimWorld.MAP_HEIGHT:
		for tx in SimWorld.MAP_WIDTH:
			if fresh.sim.objects[ty][tx] == "cot":
				cot_now = Vector2i(tx, ty)
	_assert(cot_now == Vector2i(2, 4), "the cot stands at (2,4) — %s" % cot_now)
	_assert(fresh.get_object(cot_now.x, cot_now.y - 1) == "cot",
		"with its head tile above it, so the pair reads as the middle of the room")
	_assert(fresh.get_object(4, 1) == "shipping_bin" and fresh.get_object(6, 1) == "well"
			and fresh.get_object(8, 1) == "seed_box",
		"and the three stations kept the top row")

	# Nothing beyond the fence changed: the cold open plays on field ground, and its
	# own tests are what prove that, so all this owes them is the ground they run on.
	_assert(String(fresh.get_tile(13, 4).get("state", "")) == "cleared"
			and String(fresh.get_tile(12, 2).get("state", "")) == "cleared",
		"the neighbour's plot is still ordinary field, untouched by any of this")
	fresh.queue_free()
	await get_tree().process_frame

	# 2. The tap. On the live scene, on ground this scenario lays itself — see
	#    above for why the live yard is no longer pristine by now.
	var stand := Vector2i(7, 5)
	var near := Vector2i(8, 5)
	var far := Vector2i(5, 2)
	for t in [stand, near, far]:
		_stage_tile(t.x, t.y, WorldLayout.YARD)
	GameState.set_energy(GameState.max_energy)
	GameState.selected_tool = 3            # the hoe, exactly as the fat-finger trace had it
	player.pos = Vector2(stand.x * 16 + 8.0, stand.y * 16 + 8.0)
	player.path.clear()
	player.pending_action = {}
	await get_tree().process_frame

	_assert(ActionRouter.resolve(farm, GameState, near, stand, false).is_empty(),
		"the router has no action for a yard tile, hoe in hand")
	_assert(not ActionRouter.is_workable(farm, near),
		"and does not count it workable, so she walks onto it rather than up to it")
	_assert(ActionRouter.blocked_reason(farm, GameState, near) == ""
			and ActionRouter.satisfied_reason(farm, GameState, near) == "",
		"with nothing to say about it either way — no 'cannot', no 'already done'")

	var mark: int = farm.trace.entries.size()
	InputManager.click_tile = near
	InputManager.has_click = true
	# Onto it, not up to it: `is_workable` is false, so this is an ordinary walk
	# order and Q-30's stop-beside rule does not apply.
	var stepped := await _wait_until(func(): return player.get_tile_pos() == near, 600)
	_assert(stepped, "a tap on the yard beside her walks her onto it (tile %s)" % player.get_tile_pos())
	var e := _last_tap_entry(mark)
	_assert(String(e.get("out", "")) == "walk",
		"and the trace calls it a walk, not a refusal (out=%s why=%s)"
			% [e.get("out", ""), e.get("why", "-")])
	_assert(int(e.get("tool", -1)) == 3 and String(e.get("verb", "")) == "",
		"with the hoe still in her hand and no verb attached to it")
	_assert(not e.has("halo"), "and nothing was rescued: it was simply a place to stand")

	var mark2: int = farm.trace.entries.size()
	InputManager.click_tile = far
	InputManager.has_click = true
	var crossed := await _wait_until(func(): return player.get_tile_pos() == far, 1200)
	_assert(crossed, "a far tap on the yard walks her across it (tile %s)" % player.get_tile_pos())
	_assert(String(_last_tap_entry(mark2).get("out", "")) == "walk",
		"and that one is a walk too — the yard's only answer is movement (T-18)")
	_assert(_refusals_since(mark) == 0,
		"not one refusal in the whole exchange (%d)" % _refusals_since(mark))

	# 3. The gateway's half. Asked directly, because a tap can no longer ask it.
	var r: Dictionary = farm.sim.apply_action(
		{ "verb": "till", "target": near, "actor": "player" }, GameState)
	_assert(not r.get("ok", false) and String(r.get("reason", "")) == "not_tillable",
		"the gateway refuses a till on yard ground, whoever asks (%s)" % r)
	_assert(String(farm.get_tile(near.x, near.y).get("state", "")) == WorldLayout.YARD,
		"and the ground is untouched by the asking")

	# 4. And the reason this matters at the cot. The 2026-08-30 session's four
	#    `no_energy` refusals were taps one tile below the cot resolving as
	#    till-with-hoe; T-27 rescued them, and T-32 makes the class of mistake
	#    structurally impossible, because the tile below the cot is not soil any
	#    more. Asked as a pure query so nobody actually goes to bed here.
	var cot: Vector2i = main_scene._cot_tile
	var below := cot + Vector2i(0, 1)
	var beside := cot + Vector2i(1, 1)
	_stage_tile(below.x, below.y, WorldLayout.YARD)
	var rescued := ActionRouter.resolve_with_halo(farm, GameState, below, beside, false)
	_assert(String(rescued.get("action", "")) == "sleep",
		"the tile below the cot is yard now, so the fat finger can only ever mean the cot (%s)"
			% rescued.get("action", "-"))
	_assert(rescued.get("halo_from", Vector2i(-1, -1)) == below,
		"rescued by T-27's halo, with the miss still recorded where it happened")


func _scenario_ab_the_stations_present_themselves() -> void:
	# T-28, drafted rather than decided: two treatments for "the stations never say
	# what they are for", two for "the already-done answer does not communicate",
	# all four in this build, switched on device (Q-31's Sound Test precedent, as
	# T-27 box 5 applied it to the cot).
	#
	# The load-bearing property is D-8, exactly as in Scenario X. Scenario I proves
	# that a tap on a satisfied tile answers "satisfied" and that a tap on the bin
	# sells; a presentation treatment is precisely the kind of change that could
	# quietly turn either into a wind-up, so both are re-proved once per treatment
	# against the real main scene.
	print("\n--- Scenario AB: the stations present themselves, and none of it gates a tap (T-28) ---")

	var was_d: int = StationPresentation.discovery
	var was_s: int = StationPresentation.satisfied
	var was_cot: int = CotPresentation.treatment

	# --- door 1: the pause menu, one line per open question ------------------
	main_scene.menus.open_menu("pause")
	await get_tree().process_frame
	var labels: Array = []
	_collect_labels(main_scene.menus.options_container, labels)
	var seen_axes := 0
	for axis in LookLab.AXES:
		for l in labels:
			if String(l.text) == LookLab.option_label(axis):
				seen_axes += 1
				break
	_assert(seen_axes == LookLab.AXES.size(),
		"the pause menu carries a line per open look (%d/%d), each naming where it stands"
			% [seen_axes, LookLab.AXES.size()])

	var d_before: int = StationPresentation.discovery
	main_scene.menus.selected_option = 2 + LookLab.AXES.find(LookLab.DISCOVERY)
	main_scene.menus._select_current_option()
	await get_tree().process_frame
	_assert(StationPresentation.discovery == posmod(d_before + 1, StationPresentation.DISCOVERY_COUNT),
		"tapping the discovery line advances that axis")
	_assert(CotPresentation.treatment == was_cot
			and StationPresentation.satisfied == was_s,
		"and moves nothing else — three axes, judged one at a time")
	_assert(not main_scene.menus.is_open(),
		"and closes the menu, so the farm is what he is looking at when it changes")

	# --- door 2: the title screen's Look Lab panel ---------------------------
	var title = load("res://ui/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	var opener := _find_button(title, "LookLabButton")
	_assert(opener != null, "the title screen offers 'Look Lab' beside 'Sound Test'")
	if opener != null:
		opener.pressed.emit()
		await get_tree().process_frame
		var offered := 0
		var wanted := 0
		for axis in LookLab.AXES:
			for i in LookLab.count_of(axis):
				wanted += 1
				if _find_button(title, "Look_%s_%d" % [axis, i]) != null:
					offered += 1
		_assert(offered == wanted,
			"and the panel offers every draft of every axis (%d/%d)" % [offered, wanted])
		var pick := _find_button(title, "Look_%s_%d"
			% [LookLab.SATISFIED, StationPresentation.SATISFIED_NOUN])
		if pick != null:
			pick.pressed.emit()
			await get_tree().process_frame
			_assert(StationPresentation.satisfied == StationPresentation.SATISFIED_NOUN,
				"picking one there selects it, through the same static the game reads")
	title.queue_free()
	await get_tree().process_frame

	# --- the world the drafts need -------------------------------------------
	if not TeachingFocus.handed_over(farm.sim):
		farm.apply_action({ "verb": "open_gate", "target": WorldLayout.gate_of("neighbour"),
			"actor": "neighbour" }, GameState)
	_assert(TeachingFocus.handed_over(farm.sim), "the farm is hers, so hints are allowed at all")
	GameState.day = GameState.takeover_day + 5
	GameState.clear_counts["clear_weed"] = 1   # no lesson outranking the errand
	GameState.set_energy(GameState.max_energy)
	GameState.gold = 0
	GameState.total_shipped = 0
	GameState.cans_refilled = 0
	GameState.seeds_bought = 0
	GameState.watering_can_charges = GameState.max_watering_can_charges
	GameState.crops = { "wheat": 1, "tomato": 0 }
	var bin := StationPresentation.find_station(farm.sim, StationPresentation.BIN)
	_assert(bin.x >= 0, "the bin is on the map at %s" % bin)

	var art_ok := true
	for key in StationPresentation.GLYPH_ATLAS.keys():
		if farm.glyph(key).is_empty():
			art_ok = false
	_assert(art_ok, "and the live farm resolved every T-28 glyph to a real texture")

	# --- the discovery treatments, in the real scene -------------------------
	for d in [StationPresentation.DISCOVERY_OFF, StationPresentation.DISCOVERY_GLINT,
			StationPresentation.DISCOVERY_PIP]:
		var label: String = StationPresentation.discovery_name(d)
		StationPresentation.set_discovery(d)
		main_scene._apply_station_treatment()
		await get_tree().process_frame

		var drew: int = main_scene.station_draws
		for i in 4:
			await get_tree().process_frame
		_assert(main_scene.station_draws > drew,
			"%s: the station block draws to completion, frame after frame (%d)"
				% [label, main_scene.station_draws - drew])

		var pips: Array[Dictionary] = StationPresentation.pips(
			farm.sim, GameState, player.get_tile_pos())
		var on_bin := false
		for pip in pips:
			if pip["at"] == bin:
				on_bin = true
		_assert(on_bin == (d == StationPresentation.DISCOVERY_PIP),
			"%s: a coin floats over the bin only under B" % label)

	# The glint's scheduler, driven for real: it must pick an unused station from
	# CosmeticRng and never sit on two at once.
	StationPresentation.set_discovery(StationPresentation.DISCOVERY_GLINT)
	main_scene._apply_station_treatment()
	var lit := await _wait_until(func(): return main_scene._glint_at.x >= 0, 900)
	_assert(lit, "under A a station does eventually catch the light (%s)" % main_scene._glint_at)
	if lit:
		_assert(StationPresentation.glint_candidates(farm.sim, GameState).has(main_scene._glint_at),
			"and it is one she has never used")

	# --- D-8, once per discovery treatment: the tap still sells ---------------
	for d2 in [StationPresentation.DISCOVERY_OFF, StationPresentation.DISCOVERY_GLINT,
			StationPresentation.DISCOVERY_PIP]:
		StationPresentation.set_discovery(d2)
		main_scene._apply_station_treatment()
		GameState.crops = { "wheat": 1, "tomato": 0 }
		GameState.total_shipped = 0
		player.pos = Vector2(bin.x * 16 + 8.0, (bin.y + 1) * 16 + 8.0)
		player.path.clear()
		player.pending_action = {}
		await get_tree().process_frame
		InputManager.click_tile = bin
		InputManager.has_click = true
		var sold := await _wait_until(func(): return int(GameState.total_shipped) > 0, 200)
		_assert(sold, "%s: a tap on the bin still sells, at the tap (D-8)"
			% StationPresentation.discovery_name(d2))

	# --- the already-done treatments -----------------------------------------
	_stage_tile(11, 8, "cleared")
	_stage_tile(12, 8, "seeded", "wheat")
	farm.water_tile(12, 8)
	for s in [StationPresentation.SATISFIED_OFF, StationPresentation.SATISFIED_NOUN,
			StationPresentation.SATISFIED_CHIP]:
		var slabel: String = StationPresentation.satisfied_name(s)
		StationPresentation.set_satisfied(s)
		main_scene._apply_station_treatment()
		GameState.watering_can_charges = GameState.max_watering_can_charges
		await get_tree().process_frame

		var mark: int = farm.trace.entries.size()
		player.pos = Vector2(11.5 * 16.0, 8.5 * 16.0)
		player.path.clear()
		player.pending_action = {}
		await get_tree().process_frame
		InputManager.click_tile = Vector2i(12, 8)
		InputManager.has_click = true
		var acked := await _wait_until(
			func(): return _last_tap_outcome(mark) == "satisfied", 200)
		_assert(acked, "%s: an already-watered crop is still answered 'satisfied'" % slabel)
		_assert(_last_tap_reason(mark) == "already_watered",
			"%s: with the same reason code, so the trace is comparable across the A/B" % slabel)
		_assert(_no_refusals_since(mark), "%s: and a good state still never wobbles" % slabel)
		_assert(farm._acks.has(Vector2i(12, 8)),
			"%s: the cue is in flight, so the treatment has something to draw on" % slabel)

		# Renders, whatever it is drawing.
		var fdrew: int = main_scene.station_draws
		for i in 3:
			await get_tree().process_frame
		_assert(main_scene.station_draws > fdrew, "%s: and the frame completes" % slabel)

	# --- treatment B's HUD, which is the half that is not on a tile ----------
	var hud = main_scene.hud
	StationPresentation.set_satisfied(StationPresentation.SATISFIED_CHIP)
	GameState.crops = { "wheat": 0, "tomato": 0 }
	GameState.watering_can_charges = GameState.max_watering_can_charges
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(hud.state_chips != null and hud.state_chips.visible,
		"B shows the state chips")
	_assert(not hud.water_label.visible and not hud.crop_counts_label.visible,
		"and takes away the words they replace — a picture must not have to compete with its own numeral")
	var empty_pips := 0
	for pip in hud.basket_pips:
		if pip.visible:
			empty_pips += 1
	_assert(empty_pips == 0 and hud.basket_chip.modulate.r < 0.9,
		"an empty basket is drawn dim and holding nothing — the answer to 'basket_empty', before the tap")
	_assert(hud.can_gauge_fill.size.y >= HUD_GAUGE_FULL,
		"a full can reads full (%.0fpx)" % hud.can_gauge_fill.size.y)

	GameState.crops = { "wheat": 2, "tomato": 0 }
	GameState.watering_can_charges = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var filled := 0
	for pip in hud.basket_pips:
		if pip.visible:
			filled += 1
	_assert(filled == 2 and hud.basket_chip.modulate.r > 0.9,
		"two crops put two pips in a lit basket (%d)" % filled)
	_assert(hud.can_gauge_fill.size.y == 0.0 and hud.can_chip.modulate.r < 0.9,
		"and an empty can empties the gauge — so 'go to the well' is visible from anywhere")

	StationPresentation.set_satisfied(StationPresentation.SATISFIED_OFF)
	await get_tree().process_frame
	await get_tree().process_frame
	# Q-78 (ruled 2026-09-01): the can chip is no longer treatment B's to take
	# away — it stays under every treatment, replacing the "Water:" text for
	# good. Only the basket half and the crop-count text revert with the switch.
	_assert(hud.state_chips.visible and not hud.basket_chip.visible
			and not hud.water_label.visible and hud.crop_counts_label.visible,
		"and switching back keeps the can chip (Q-78) while the basket half reverts")

	# --- put everything back --------------------------------------------------
	GameState.crops = { "wheat": 0, "tomato": 0 }
	GameState.watering_can_charges = GameState.max_watering_can_charges
	StationPresentation.set_discovery(was_d)
	StationPresentation.set_satisfied(was_s)
	CotPresentation.set_treatment(was_cot)
	main_scene._apply_station_treatment()
	main_scene._apply_cot_treatment()
	_assert(StationPresentation.discovery == StationPresentation.DISCOVERY_PIP
			and StationPresentation.satisfied == StationPresentation.SATISFIED_NOUN,
		"and the build's defaults, restored, are the 2026-09-01 picks — pips, and the noun")


# The gauge's full height, from the HUD's own metrics: 22px tall with a 1px lip
# top and bottom. Spelled once here so the assertion above cannot drift from it.
const HUD_GAUGE_FULL := 20.0


func _scenario_ae_the_home() -> void:
	# T-37, the designer 2026-09-01: an indoor space representing the player's
	# home — the bed, windows, very little else. The unit test proves the layout
	# generates; this proves the *door opens onto a room that renders*, detached
	# from the played farm (the Zoo's proof, for the Zoo's reason).
	print("\n--- Scenario AE: the home renders, detached (T-37) ---")

	var title = load("res://ui/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	_assert(_find_button(title, "HomeButton") != null,
		"the title screen offers 'Home' in the debug grid")
	title.queue_free()
	await get_tree().process_frame

	var home = load("res://ui/home_screen.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	await get_tree().process_frame

	var hfarm = home.farm
	_assert(hfarm != null and hfarm.sim != null, "the home brought its own farm and SimWorld")
	_assert(hfarm.sim != main_scene.farm.sim, "which is not the played farm's")
	_assert(home.gs != null and home.gs != GameState, "and a detached GameState, not the singleton")
	_assert(hfarm.replay == null and hfarm.trace == null,
		"nothing in the home records — no replay, no trace")

	# The room, as generated in the real scene.
	_assert(String(hfarm.sim.get_tile(14, 8).get("state", "")) == WorldLayout.FLOOR,
		"the floor is down")
	_assert(String(hfarm.sim.get_tile(13, 5).get("state", "")) == WorldLayout.WINDOW,
		"a window is in the north wall")
	_assert(String(hfarm.sim.get_tile(10, 6).get("state", "")) == WorldLayout.WALL,
		"and the wall stands")
	_assert(String(hfarm.sim.objects[7][12]) == "cot", "the bed is in the room")
	_assert(hfarm.sim.actors.size() == 1 and hfarm.sim.has_actor(SimWorld.ACTOR_PLAYER),
		"she is home alone (%d actors)" % hfarm.sim.actors.size())

	# And it draws to completion, frame after frame.
	for i in 3:
		hfarm.queue_redraw()
		await get_tree().process_frame
	_assert(is_instance_valid(hfarm), "three redraws later the room is still standing")

	home.queue_free()
	await get_tree().process_frame


func _scenario_ac_the_zoo() -> void:
	# T-33, the designer 2026-09-01: a door onto the entities, because the whole
	# bestiary ships behind `PER_DAY := 0` and nobody has ever seen a rabbit.
	#
	# Two things are worth an integration scenario rather than a unit test. The
	# first is that the door *opens onto a farm that renders* — every species
	# through the sim, out the other side as a sprite, with a clock running. The
	# second is Scenario K's hazard, inherited whole: a second world running over
	# the player's own state would spend her energy and her seeds while she was
	# looking at a debug panel. The zoo is a bigger version of the attract loop, so
	# it gets the attract loop's proof.
	print("\n--- Scenario AC: the zoo, and it cannot touch the player's farm (T-33) ---")

	# The door itself. Debug gate, same row as the Sound Test and the Look Lab.
	var title = load("res://ui/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	_assert(_find_button(title, "ZooButton") != null,
		"the title screen offers 'Zoo' beside 'Sound Test' and 'Look Lab'")
	_assert(_find_button(title, "SoundTestButton") != null
			and _find_button(title, "LookLabButton") != null,
		"and the doors that were already there are still there")
	title.queue_free()
	await get_tree().process_frame

	var live_before := _live_fingerprint()
	var files_before: Array = []
	for path in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		files_before.append(FileAccess.file_exists(path))

	var zoo = load("res://ui/zoo_screen.tscn").instantiate()
	add_child(zoo)
	await get_tree().process_frame
	await get_tree().process_frame
	zoo.running = false   # the clock is pumped by hand below, so the ticks are countable

	var zfarm = zoo.farm
	_assert(zfarm != null and zfarm.sim != null, "the zoo brought its own farm and SimWorld")
	_assert(zfarm.sim != main_scene.farm.sim, "which is not the played farm's")
	_assert(zoo.gs != null and zoo.gs != GameState,
		"and a DETACHED GameState, not the singleton — Scenario K's whole hazard")
	_assert(zoo.player != null and zoo.player.gs == zoo.gs and zoo.player.name == "Player",
		"the farmer it stands up spends that detached state, at the name farm.gd looks up")
	_assert(zfarm.replay == null and zfarm.trace == null,
		"it records no replay and no session trace — nothing here can reach a save slot")
	_assert(zfarm.sim.actors.keys() == [SimWorld.ACTOR_PLAYER],
		"and starts with the farmer and nobody else")

	# One of everything, through the panel's own buttons.
	var offered := 0
	for species in Zoo.roster():
		if _find_button(zoo, "Zoo_%s" % species) != null:
			offered += 1
	_assert(offered == Zoo.roster().size(),
		"the roster panel offers a button per species (%d/%d)" % [offered, Zoo.roster().size()])

	var drawn_species := {}
	for species in Zoo.roster():
		var button := _find_button(zoo, "Zoo_%s" % species)
		if button != null:
			button.pressed.emit()
	await get_tree().process_frame
	var census: Dictionary = Zoo.census(zfarm.sim)
	_assert(census.size() == Zoo.roster().size(),
		"tapping every button puts every species in the world (%d/%d)"
			% [census.size(), Zoo.roster().size()])
	for species in census:
		_assert(int(census[species]) == zfarm.sim.actors_of_species(String(species)).size(),
			"the census line agrees with the registry for %s" % species)

	# Sprites, which is the half a unit test cannot see.
	for id in zfarm.sim.actors.keys():
		var actor_id := String(id)
		if actor_id == SimWorld.ACTOR_PLAYER:
			continue
		if is_instance_valid(zfarm.actor_nodes.get(actor_id, null)):
			drawn_species[zfarm.sim.species_of(actor_id)] = true
	_assert(drawn_species.size() == Zoo.roster().size(),
		"and every one of them got a sprite (%d/%d species drawn)"
			% [drawn_species.size(), Zoo.roster().size()])
	for species in Zoo.roster():
		_assert(not Zoo.icon_of(species).is_empty(),
			"%s's button resolved to a real cell of a real sheet" % species)

	# 200 ticks with the whole bestiary awake, in the real scene, drawing.
	var tick_before: int = zfarm.sim.clock.tick
	for i in 200:
		zoo.pump(0.1)
		if i % 40 == 0:
			await get_tree().process_frame
	_assert(zfarm.sim.clock.tick == tick_before + 200,
		"200 ticks pass with everything running (%d)" % (zfarm.sim.clock.tick - tick_before))
	_assert(zfarm.sim.has_actor(SimWorld.ACTOR_PLAYER), "and the farmer is still standing there")

	# The scent tint: zoo-only, magenta, and O(marks) rather than O(map).
	_assert(not zoo.overlay.enabled, "the trail tint is off until it is asked for")
	var marks: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]
	for t in marks:
		zfarm.sim.scent.deposit(Scent.TRAIL, t, 12.0, zfarm.sim.clock.tick)
	_assert(zoo.toggle_trail(), "and toggles on")
	zoo.overlay._refresh()
	_assert(zoo.overlay.marked().size() == zfarm.sim.scent.cell_count(Scent.TRAIL),
		"it reads exactly the field's written cells (%d), never the map"
			% zoo.overlay.marked().size())
	for t in marks:
		_assert(t in zoo.overlay.marked(), "including %s" % t)
	var drew: int = zoo.overlay.draws
	for i in 4:
		zfarm.queue_redraw()
		await get_tree().process_frame
	_assert(zoo.overlay.draws > drew,
		"and the tint block draws to completion, frame after frame (%d)"
			% (zoo.overlay.draws - drew))
	_assert(not zoo.toggle_trail(), "and toggles back off")

	# Time controls.
	_assert(zoo.cycle_speed() == 2 and zoo.cycle_speed() == 4 and zoo.cycle_speed() == 1,
		"the speed toggle cycles 2x, 4x and back to 1x")
	var sprinkler_id: String = zfarm.sim.actors_of_species(SpeciesDefs.SPRINKLER)[0]
	var covered: Array[Vector2i] = SprinklerBrain.coverage(zfarm.sim, sprinkler_id)
	for t in covered:
		zfarm.sim.set_tile_state(t.x, t.y, "growing", "wheat")
		zfarm.sim.tiles[t.y][t.x]["watered_today"] = false
	var day_before: int = int(zoo.gs.day)
	var turn: Dictionary = zoo.turn_day()
	_assert(turn.get("ok", false) and int(zoo.gs.day) == day_before + 1,
		"the day-turn button turns the zoo's day (%d)" % int(zoo.gs.day))
	_assert(String(zoo.gs.weather) == "sunny",
		"and forces sunny, so a rainy roll cannot wash the trail he opened the tint to see")
	var wet := 0
	for t in covered:
		if zfarm.sim.tiles[t.y][t.x]["watered_today"]:
			wet += 1
	_assert(wet == covered.size(),
		"the sprinkler fires on it (%d of %d tiles wet)" % [wet, covered.size()])

	# Clear.
	var gone: int = zoo.clear_zoo()
	await get_tree().process_frame
	_assert(gone > 0 and zfarm.sim.actors.keys() == [SimWorld.ACTOR_PLAYER],
		"clear empties the zoo (%d removed) and leaves the farmer" % gone)
	var sprites_left := 0
	for id in zfarm.actor_nodes.keys():
		if is_instance_valid(zfarm.actor_nodes[id]):
			sprites_left += 1
	_assert(sprites_left == 0, "and the sprites went with them (%d left)" % sprites_left)

	# The whole point: none of that touched the player's farm.
	_assert(_live_fingerprint() == live_before,
		"the live GameState is byte-identical after a full session in the zoo")
	var idx := 0
	for path in [GameState.save_path, GameState.replay_path, GameState.trace_path]:
		_assert(FileAccess.file_exists(path) == files_before[idx],
			"the zoo created no file at %s" % path)
		idx += 1
	_assert(main_scene.farm.sim.has_actor(SimWorld.ACTOR_PLAYER),
		"and the played farm is still the played farm")

	zoo.queue_free()
	await get_tree().process_frame


# Two HUD findings from the tablet, 2026-09-01. Both are about the overlay rather
# than the world, so both are asserted against the real HUD the real scene built.
func _scenario_ad_two_hud_findings() -> void:
	print("\n--- Scenario AD: the pill fits its words, and the debug block folds away ---")

	var hud = main_scene.hud

	# --- the pill sizes to its content ---------------------------------------
	#
	# *"The pill drawn beneath the current selected item (e.g. scarecrow) .. the
	# pill isn't big enough so the words spill over."* The pill was a fixed 100
	# pixels with an 82-pixel label in it; "scarecrow x1" does not fit in 82.
	var font: Font = hud.seed_pill_label.get_theme_font("font")
	var font_size: int = hud.seed_pill_label.get_theme_font_size("font_size")
	var widest := ""
	var widest_px := 0.0
	for seed_name in CropDefs.TYPES.keys():
		var sample := "%s x%d" % [seed_name, 12]
		var px: float = font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if px > widest_px:
			widest_px = px
			widest = sample
	_assert(widest_px > 82.0,
		"the longest label in the game ('%s', %.0fpx) really did overflow the old 82px slot"
			% [widest, widest_px])

	var spilled: PackedStringArray = []
	for seed_name in CropDefs.TYPES.keys():
		GameState.selected_seed_type = seed_name
		GameState.seeds[seed_name] = 12
		hud._update_hud()
		var text_px: float = font.get_string_size(hud.seed_pill_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var room: float = hud.seed_pill.size.x - hud.PILL_ICON_W
		if text_px > room:
			spilled.append("%s (%.0f > %.0f)" % [hud.seed_pill_label.text, text_px, room])
	_assert(spilled.is_empty(),
		"every seed, tool and object in the pouch fits inside its pill (%s)"
			% ("none spill" if spilled.is_empty() else ", ".join(spilled)))

	# The scarecrow by name, because it is the one she reported.
	GameState.selected_seed_type = "scarecrow"
	GameState.seeds["scarecrow"] = 1
	hud._update_hud()
	_assert(hud.seed_pill.size.x > 100.0,
		"the scarecrow's pill grew past the old fixed 100px (%.0f)" % hud.seed_pill.size.x)
	_assert(hud.seed_pill_label.size.x + hud.PILL_ICON_W <= hud.seed_pill.size.x,
		"and the label still sits inside it, icon included")
	var centre_gap: float = absf(
		hud.seed_pill.position.x + hud.seed_pill.size.x / 2.0
		- main_scene.get_viewport().get_visible_rect().size.x / 2.0)
	_assert(centre_gap <= 1.0,
		"a wider pill is still centred, not stretched off to one side (%.1fpx off)" % centre_gap)

	GameState.selected_seed_type = "wheat"
	GameState.seeds["wheat"] = 5
	hud._update_hud()
	_assert(absf(hud.seed_pill.size.x - hud.PILL_MIN_W) <= 4.0,
		"and a short label leaves the pill within a pixel or two of the size it has always been (%.1f)"
			% hud.seed_pill.size.x)

	# --- the debug readout folds away ----------------------------------------
	#
	# *"We should add a 'hide debug' button in the top left that collapses the
	# debug information printed in the top left."*
	_assert(hud.notes_toggle != null and hud.notes_label != null,
		"the playtest readout has a toggle beside it")
	_assert(hud.notes_toggle.position.x < 40.0 and hud.notes_toggle.position.y < 60.0,
		"in the top left, where the block it hides is")
	_assert(hud.notes_toggle.size.x <= 32.0 and hud.notes_toggle.size.y <= 24.0,
		"and it is a chip (%.0fx%.0f), so collapsing does not leave a slab of button"
			% [hud.notes_toggle.size.x, hud.notes_toggle.size.y])
	_assert(hud.notes_label.visible, "the block starts open")

	hud._on_notes_toggle()
	_assert(not hud.notes_label.visible, "one press collapses it")
	_assert(hud.notes_toggle.visible and hud.notes_toggle.text != "",
		"leaving the chip behind to offer it back")
	var quiet_mark: String = hud.notes_label.text
	for i in 40: await get_tree().process_frame
	_assert(hud.notes_label.text == quiet_mark,
		"and the collapsed block stops paying for its O(map) refresh")

	hud._on_notes_toggle()
	_assert(hud.notes_label.visible, "a second press brings it back")

	# Remembered for the session: the flag is a static on the script, so a HUD
	# built later in the same run (a return to the title and a new game) opens in
	# the state the developer left it in.
	hud._on_notes_toggle()
	var HudScript = load("res://ui/hud.gd")
	_assert(HudScript.notes_collapsed,
		"the collapsed state lives on the script, not on this one HUD node")
	hud._on_notes_toggle()
	_assert(not HudScript.notes_collapsed, "and it is put back the same way")
	await get_tree().process_frame

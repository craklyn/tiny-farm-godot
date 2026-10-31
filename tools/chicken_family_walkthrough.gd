# Played chicken-family review. Always uses a scratch slot before Main exists.
# Headless: python3 tools/run_godot_test.py -- godot --headless --path . res://tools/chicken_family_walkthrough.tscn
# Pictures: xvfb-run -a godot --path . res://tools/chicken_family_walkthrough.tscn -- --capture
extends Node2D

var main
var failures := 0
var passed := 0
var capture := false
const OUTPUT := "res://tools/chicken_family_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	GameState.use_slot(1, "user://chicken_family_walkthrough/")
	SuiteSeed.apply(20261031)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: SimWorld = main.farm.sim
	ColdOpen.run(main.farm, world, GameState)
	main.menus.close_menu()
	main.end_teaching()
	GameState.gold = 1000
	GameState.set_energy(GameState.max_energy)
	GameState.items["egg"] = 2
	GameState.pouch["wheat"] = 10
	world.story_nights_told[SimWorld.STORY_NIGHT_CROW] = true
	world.story_nights_told[SimWorld.STORY_NIGHT_ROBOT] = true
	# Stage a clear scratch yard. All demonstrated inventory/lifecycle changes
	# below use the same actions and controls as the played scene.
	var hut := Vector2i(15, 10)
	for y in range(7, 14):
		for x in range(11, 20):
			world.set_tile_state(x, y, "cleared")
			world.set_object(x, y, "")
	GameState.machines["coop"] = 1
	_check(main.farm.apply_action({"verb": "place", "actor": "player", "target": hut, "item": "coop"}, GameState).get("ok", false), "a coop is placed")
	var room := world.room_of_anchor(hut)
	if room == "":
		await _finish()
		return
	var origin: Vector2i = world.rooms[room]["origin"]
	var nest := origin + Vector2i(1, 1)
	var dispenser := origin + Vector2i(4, 1)
	for item in ["nest_box", "chicken_dispenser"]:
		GameState.machines[item] = 1
		_check(main.farm.apply_action({"verb": "place", "actor": "player", "target": nest if item == "nest_box" else dispenser, "item": item}, GameState).get("ok", false), "%s goes on the coop floor" % item)
	var hen := Poultry.chicken_ids(world)[0]
	world.set_actor_pos(hen, nest + Vector2i(1, 0))
	world.set_actor_pos("player", origin + Vector2i(2, 3))
	main.player.init_position(origin.x + 2, origin.y + 3)
	main.note_page_change()
	main.farm.sync_actors()
	main.menus.open_menu("inventory")
	var egg_card := -1
	for i in main.menus.inventory_items.size():
		if String(main.menus.inventory_items[i].key) == "egg": egg_card = i
	_check(egg_card >= 0, "collected eggs appear in the touch inventory")
	await _shot("01_inventory_egg")
	if egg_card >= 0:
		main.menus.selected_option = egg_card
		main.menus._select_current_option()
	_check(GameState.selected_seed_type == "egg", "the inventory can select an egg")
	var intent: Dictionary = ActionRouter.resolve(main.farm, GameState, nest, world.actor_pos("player"))
	_check(String(intent.get("action", "")) == "nest_egg", "a selected egg tapped onto the nest resolves to nesting")
	# Execute the resolved input after staging her beside the fitting.
	world.set_actor_pos("player", nest + Vector2i(0, 1))
	main.player.init_position(nest.x, nest.y + 1)
	main.player._execute_resolved_action(intent)
	_check(bool(Poultry.nest_info(world, nest).get("egg", false)), "the inventory egg reaches the nest through the gateway")
	main.menus.open_poultry_menu(dispenser)
	for i in 7: _choose("fill_chicken_feed", "wheat")
	_check(int(Poultry.dispenser_info(world, dispenser).get("feed", 0)) == 14, "seven wheat fill seven incubation days")
	await _shot("02_full_dispenser")
	main.menus.close_menu()
	for i in 100:
		main.farm.advance_sim(1, GameState)
	_check(Poultry.incubating_id(world) == hen, "the hen adopts and attends the nested egg")
	for day in 2:
		main.farm.apply_action({"verb": "sleep", "actor": "player"}, GameState)
		main.farm.advance_sim(40, GameState)
	main.menus.open_poultry_menu(nest)
	_check(int(Poultry.nest_info(world, nest).get("progress", 0)) > 0, "nest inspection has real incubation progress")
	await _shot("03_incubation")
	main.menus.open_poultry_menu(dispenser)
	await _shot("04_partial_dispenser")
	main.menus.close_menu()
	for day in 3:
		main.farm.apply_action({"verb": "sleep", "actor": "player"}, GameState)
		main.farm.advance_sim(40, GameState)
	var chick := Poultry.chick_id(world)
	_check(chick != "", "five attended days hatch one chick")
	main.farm.sync_actors()
	if chick != "":
		_check(main.farm.actor_nodes.has(chick), "the chick receives a real renderer")
		# Separate in the same room/yard, then let the real brains choose reunion.
		world.set_actor_pos(hen, hut + Vector2i(1, 2))
		world.set_actor_pos(chick, hut + Vector2i(2, 2))
		world.set_actor_pos("player", hut + Vector2i(0, 3))
		main.player.init_position(hut.x, hut.y + 3)
		main.note_page_change()
		main.farm.advance_sim(20, GameState)
		await _shot("05_mother_and_chick")
		main.menus.open_poultry_menu(world.actor_pos(hen), hen)
		var before := float(world.actor(hen)["extra"].get("familiarity", 0))
		_choose("greet_chicken")
		_check(float(world.actor(hen)["extra"].get("familiarity", 0)) > before, "a direct greeting builds individual familiarity")
		await _shot("06_named_hen")
		_choose("quote")
		_check(main.menus.poultry_quote_ids.size() == 2, "a dependent mother/chick pair is quoted together")
		await _shot("07_neighbor_confirmation")
		_choose("request_chicken_sale")
		var buyers := world.actors_of_species("chicken_collector")
		_check(buyers.size() == 1, "sale confirmation brings a real visiting neighbor")
		var carrying := false
		for i in 2400:
			main.farm.advance_sim(1, GameState)
			for id in world.actors_of_species("chicken_collector"):
				if not (world.actor(id)["extra"].get("carried", []) as Array).is_empty():
					carrying = true
			if carrying: break
		_check(carrying, "the neighbor physically collects the pair")
		if carrying:
			var collector: String = world.actors_of_species("chicken_collector")[0]
			world.set_actor_pos("player", world.actor_pos(collector) + Vector2i(0, 2))
			main.player.init_position(world.actor_pos("player").x, world.actor_pos("player").y)
			main.note_page_change()
			main.farm.sync_actors()
			await _shot("08_neighbor_carrying_family")
		for i in 2400:
			main.farm.advance_sim(1, GameState)
			if world.actors_of_species("chicken_collector").is_empty(): break
		_check(world.actors_of_species("chicken_collector").is_empty(), "the neighbor departs carrying the family")
	await _finish()

func _choose(verb: String, item: String = "") -> void:
	for i in main.menus.poultry_options.size():
		var option: Dictionary = main.menus.poultry_options[i]
		if String(option.get("verb", "")) == verb and (item == "" or String(option.get("params", {}).get("item", "")) == item):
			main.menus.selected_option = i
			main.menus._select_current_option()
			return
	_check(false, "control exists: %s" % verb)

func _shot(label: String) -> void:
	if not capture: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for i in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))
	_check(error == OK, "captured %s" % label)

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _finish() -> void:
	get_tree().paused = false
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Results: %d PASSED, %d FAILED" % [passed, failures])
	get_tree().quit(1 if failures else 0)

# The outdoor stock, physical indoor shelf, two-card store, and bought fittings.
# Always selects scratch paths before Main can autosave.
# xvfb-run -a godot --path . res://tools/capture_coop_shop.tscn
extends Node2D

var main
var passed := 0
var failed := 0
const OUTPUT := "res://tools/coop_shop_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.use_slot(1, "user://capture_coop_shop/")
	SuiteSeed.apply(20261031)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world: SimWorld = main.farm.sim
	ColdOpen.run(main.farm, world, GameState)
	main.menus.close_menu()
	main.end_teaching()
	GameState.gold = 200
	GameState.set_energy(GameState.max_energy)
	main.hud.visible = false
	var stamp := get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null: stamp.visible = false
	var anchor := Vector2i(15, 10)
	for y in range(7, 14):
		for x in range(11, 20):
			world.set_tile_state(x, y, "cleared")
			world.set_object(x, y, "")
	GameState.machines["coop"] = 1
	_check(main.farm.apply_action({"verb": "place", "actor": "player", "item": "coop", "target": anchor}, GameState).get("ok", false), "coop stands in the scratch farm")
	main.menus.open_menu("shop")
	var outdoor: Array = main.menus.shop_items.map(func(item): return String(item.seed_type))
	_check(not outdoor.has("nest_box") and not outdoor.has("chicken_dispenser") and outdoor.has("coop") and outdoor.has("chicken_feed"), "outdoor shop keeps coop/feed and excludes both fittings")
	await _shot("01_outdoor_store")
	main.menus.close_menu()
	world.set_actor_pos("player", anchor + Vector2i.DOWN)
	main.player.init_position(anchor.x, anchor.y + 1)
	main.player._execute_resolved_action({"action": "use_door", "target_t": anchor})
	for i in 50: await get_tree().process_frame
	var room := world.room_of_anchor(anchor)
	_check(world.room_of_cell(main.player.get_tile_pos()) == room, "player enters the actual coop")
	await _shot("02_wall_shelf")
	var shelf := CoopShop.shelf_rect(world, room)
	InputManager.tap_tile(shelf.position)
	for i in 120:
		await get_tree().process_frame
		if main.menus.active_menu == "coop_shop": break
	_check(main.menus.active_menu == "coop_shop" and main.menus.shop_items.size() == 2, "touching the shelf opens only the two coop goods")
	await _shot("03_indoor_store")
	for item in CoopShop.ITEMS:
		for i in main.menus.shop_items.size():
			if String(main.menus.shop_items[i].seed_type) == item:
				var buttons: Array = main.menus.options_container.find_children("*", "Button", true, false)
				(buttons[i] as Button).pressed.emit()
				break
		for i in 120:
			await get_tree().process_frame
			if int(GameState.machines.get(item, 0)) == 1: break
		_check(int(GameState.machines.get(item, 0)) == 1, "indoor card buys one " + item)
	main.menus.close_menu()
	var origin: Vector2i = world.rooms[room]["origin"]
	for item in CoopShop.ITEMS:
		var tile := origin + (Vector2i(1, 1) if item == "nest_box" else Vector2i(4, 1))
		_check(main.farm.apply_action({"verb": "place", "actor": "player", "item": item, "target": tile}, GameState).get("ok", false), "bought fitting is placed: " + item)
	await _shot("04_bought_fittings")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Results: %d PASSED, %d FAILED" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for i in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name + ".png")) == OK, "captured " + name)

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		push_error(label)

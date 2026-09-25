# Capture the shop screen for the card that gave its shelf room to grow
# (w2989282532d): the nest box and rug (c7f7134) already left the panel 28px
# from the bottom of an 800x600 screen, and the next thing for sale would have
# pushed the close button off it. The fix wraps the shelf in a scroll capped
# to what is left of the screen (`ui/menus.gd`'s `SHOP_SCROLL_MARGIN`).
# Modelled on `capture_inventory_picker.gd`: a real `main.tscn`, a scratch save
# slot so this never touches a player's own farm, two screenshots.
extends Node2D

const OUT_DIR := "res://docs/design/mockups/shop_layout"

func _ready() -> void:
	seed(2532025)
	# Scratch, not `user://slot1` — S-14's rule for anything that plays or opens
	# a farm outside a real session, so a run of this tool can never seed or
	# overwrite a player's own autosave.
	GameState.use_slot(1, "user://capture_shop_layout_scratch/")
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 30:
		await get_tree().process_frame
	var stamp = get_tree().root.get_node_or_null("BuildOverlay")
	if stamp != null:
		stamp.visible = false
	if main.hud.notes_label != null:
		main.hud.notes_label.visible = false
	if main.hud.notes_toggle != null:
		main.hud.notes_toggle.visible = false

	main.player.set_process(false)
	main.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# **The shop as it stands today** — the real catalogue, nothing stocked in
	# for the occasion. This is what she sees on the shelf right now.
	GameState.gold = 500
	GameState.harvest_counts = {"wheat": 3, "tomato": 3}
	main.trigger_action("open_shop")
	for i in 20:
		await get_tree().process_frame
	var open_shot := get_viewport().get_texture().get_image()
	var err := open_shot.save_png("%s/open.png" % OUT_DIR)
	if err != OK:
		push_error("Shop layout capture (open) failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	main.menus.close_menu()
	for i in 5:
		await get_tree().process_frame

	# **The shelf under a load the shop has never carried yet** — the same
	# stand-in the integration test uses (ten extra fence rows on
	# `MachineDefs.ORDER`), scrolled to its end, so the card this capture is
	# for can see the mechanism it is approving rather than take it on faith.
	var original_order: Array[String] = MachineDefs.ORDER.duplicate()
	var stocked: Array[String] = original_order.duplicate()
	for i in 10:
		stocked.append("fence")
	MachineDefs.ORDER = stocked
	main.trigger_action("open_shop")
	for i in 20:
		await get_tree().process_frame
	# `find_child`, not `get_node_or_null`: the scroll now sits one level
	# deeper, inside the stack that also carries its wordless edge fade
	# (w98a60854171).
	var shop_scroll: Control = main.menus.options_container.find_child("shop_scroll", true, false)
	if shop_scroll != null:
		shop_scroll.scroll_vertical = 1000000
		for i in 5:
			await get_tree().process_frame
	var scrolled_shot := get_viewport().get_texture().get_image()
	err = scrolled_shot.save_png("%s/scrolled.png" % OUT_DIR)
	MachineDefs.ORDER = original_order
	if err != OK:
		push_error("Shop layout capture (scrolled) failed: %s" % error_string(err))
		get_tree().quit(1)
		return

	print("Captured the shop layout, at rest and stocked past the old overflow (%dx%d)."
		% [open_shot.get_width(), open_shot.get_height()])
	get_tree().quit(0)

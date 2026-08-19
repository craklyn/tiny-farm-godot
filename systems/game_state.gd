# game_state.gd — Autoloaded global state singleton
# Manages day counter, energy, gold, inventory, and global signals
extends Node

# Signals
signal day_changed(new_day: int)
signal energy_changed(new_energy: int)
signal gold_changed(new_gold: int)
signal tool_changed(new_tool_index: int)
signal milestone_reached(milestone_id: String, message: String)
signal weather_changed(new_weather: String)

# Day
var day: int = 1
var weather: String = "sunny"

# Player stats
var energy: int = 20
var max_energy: int = 20
var gold: int = 0

# Tools
var selected_tool: int = 0  # Index into Tools.LIST

# Seeds & crops
var seeds: Dictionary = { "wheat": 5, "tomato": 0 }
var crops: Dictionary = { "wheat": 0, "tomato": 0 }
var harvest_counts: Dictionary = { "wheat": 0, "tomato": 0 }
var shipping_bin: Dictionary = { "wheat": 0, "tomato": 0 }

# Watering can
var watering_can_charges: int = 8
var max_watering_can_charges: int = 8

# Selected seed type for planting
var selected_seed_type: String = "wheat"

# Milestones tracking
var _milestones_earned: Dictionary = {}

# Game state
var game_paused: bool = false


func set_energy(value: int) -> void:
	energy = clampi(value, 0, max_energy)
	energy_changed.emit(energy)


func set_gold(value: int) -> void:
	gold = value
	gold_changed.emit(gold)


func cycle_tool(direction: int) -> void:
	var tool_count := Tools.LIST.size()
	selected_tool = (selected_tool + direction + tool_count) % tool_count
	tool_changed.emit(selected_tool)


func cycle_seed_type() -> void:
	var order := CropDefs.ORDER
	var current_idx := order.find(selected_seed_type)
	if current_idx == -1:
		current_idx = 0
	# Find next unlocked seed type with stock
	for offset in range(1, order.size() + 1):
		var idx := (current_idx + offset) % order.size()
		var seed_type: String = order[idx]
		var def: Dictionary = CropDefs.TYPES.get(seed_type, {})
		var has_price = def.has("seed_price")
		if has_price and CropDefs.is_seed_unlocked(seed_type, harvest_counts) and seeds.get(seed_type, 0) > 0:
			selected_seed_type = seed_type
			return


func buy_seed(seed_type: String) -> bool:
	var def: Dictionary = CropDefs.TYPES.get(seed_type, {})
	if def.is_empty():
		return false
	if gold < def.seed_price:
		return false
	if not CropDefs.is_seed_unlocked(seed_type, harvest_counts):
		return false
	gold -= def.seed_price
	seeds[seed_type] = seeds.get(seed_type, 0) + 1
	gold_changed.emit(gold)
	return true


func sell_crops_to_bin() -> bool:
	var sold_anything := false
	for crop_type in crops.keys():
		var count: int = crops[crop_type]
		if count > 0:
			var def: Dictionary = CropDefs.TYPES.get(crop_type, {})
			if not def.is_empty():
				gold += count * def.sell_price
			crops[crop_type] = 0
			sold_anything = true
	if sold_anything:
		gold_changed.emit(gold)
		if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("AudioManager"):
			Engine.get_main_loop().root.get_node("AudioManager").play_sfx("click")
	return sold_anything


func process_shipping_bin() -> void:
	for crop_type in shipping_bin.keys():
		var count: int = shipping_bin[crop_type]
		if count > 0:
			var def: Dictionary = CropDefs.TYPES.get(crop_type, {})
			if not def.is_empty():
				gold += count * def.sell_price
			shipping_bin[crop_type] = 0
	gold_changed.emit(gold)


func start_new_day() -> void:
	energy = max_energy
	watering_can_charges = max_watering_can_charges
	day += 1
	
	if SimRng.randf() < 0.2:
		weather = "rainy"
	else:
		weather = "sunny"
		
	energy_changed.emit(energy)
	day_changed.emit(day)
	weather_changed.emit(weather)


func refill_watering_can() -> bool:
	if watering_can_charges < max_watering_can_charges:
		watering_can_charges = max_watering_can_charges
		return true
	return false


func check_milestones() -> void:
	var total_harvests: int = 0
	for count in harvest_counts.values():
		total_harvests += count

	var milestones: Array[Dictionary] = [
		{ "id": "first_harvest", "condition": total_harvests >= 1, "msg": "First Harvest!" },
		{ "id": "green_thumb", "condition": total_harvests >= 10, "msg": "Green Thumb!" },
		{ "id": "golden_field", "condition": gold >= 500, "msg": "Golden Field!" },
		{ "id": "master_farmer", "condition": (
			harvest_counts.get("wheat", 0) >= 1 and
			harvest_counts.get("tomato", 0) >= 1 and
			harvest_counts.get(0) >= 1
		), "msg": "Master Farmer!" },
	]

	for m in milestones:
		if m.condition and not _milestones_earned.has(m.id):
			_milestones_earned[m.id] = true
			milestone_reached.emit(m.id, m.msg)

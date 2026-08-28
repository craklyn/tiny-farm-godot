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

# Sim-truth player state. Defaults live in ONE place: reset(), called from
# _init() — do not add initializer values here, add them to reset().
var day: int
var weather: String
var energy: int
var max_energy: int
var gold: int
var selected_tool: int  # Index into Tools.LIST
var seeds: Dictionary
var crops: Dictionary
var harvest_counts: Dictionary
var shipping_bin: Dictionary
var watering_can_charges: int
var max_watering_can_charges: int
var selected_seed_type: String
var hard_energy: bool  # phase 1: false (soft floor, Q-11); phase 2+ flips true
var crows_scared: int  # Q-12 proof counter (player-caused scares, via crow_scared verb)
var crows_seen: int  # T-2: how many crows have ever arrived; the first one is harmless
var total_shipped: int  # Q-12 proof counter (crops sold, any route)
var phase1_complete: bool  # Q-12/P-4: set silently by the sim at sleep when the proof is met

# Milestones tracking
var _milestones_earned: Dictionary = {}

# Game state
var game_paused: bool = false
var pending_load: bool = false  # title screen asks main to load the autosave

# Save file locations — overridable so automated sessions (robot tests) never
# touch a real player's files
var save_path: String = "user://autosave.json"
var replay_path: String = "user://session_replay.json"
var trace_path: String = "user://session_trace.jsonl"  # diagnostic; see systems/session_trace.gd


func _init() -> void:
	reset()


func reset() -> void:
	# New-game / replay baseline — the single source of default values.
	day = 1
	weather = "sunny"
	energy = 20
	max_energy = 20
	gold = 0
	selected_tool = 0
	seeds = { "wheat": 5, "tomato": 0 }
	crops = { "wheat": 0, "tomato": 0 }
	harvest_counts = { "wheat": 0, "tomato": 0 }
	shipping_bin = { "wheat": 0, "tomato": 0 }
	watering_can_charges = 8
	max_watering_can_charges = 8
	selected_seed_type = "wheat"
	hard_energy = false
	crows_scared = 0
	crows_seen = 0
	total_shipped = 0
	phase1_complete = false
	_milestones_earned = {}
	game_paused = false
	day_changed.emit(day)
	energy_changed.emit(energy)
	gold_changed.emit(gold)
	weather_changed.emit(weather)
	tool_changed.emit(selected_tool)


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
			total_shipped += count
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
			total_shipped += count
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


# Crops harvested, eggs excluded — eggs are a gift, not evidence the player has
# worked the loop. Shared by the milestone check and T-2's crow readiness gate so
# the two cannot drift apart.
func total_harvests() -> int:
	var n: int = 0
	for crop_type in harvest_counts:
		if crop_type == "egg":
			continue
		n += harvest_counts[crop_type]
	return n


func check_milestones() -> void:
	var harvested: int = total_harvests()

	var milestones: Array[Dictionary] = [
		{ "id": "first_harvest", "condition": harvested >= 1, "msg": "First Harvest!" },
		{ "id": "green_thumb", "condition": harvested >= 10, "msg": "Green Thumb!" },
		{ "id": "golden_field", "condition": gold >= 500, "msg": "Golden Field!" },
		{ "id": "master_farmer", "condition": (
			harvest_counts.get("wheat", 0) >= 1 and
			harvest_counts.get("tomato", 0) >= 1 and
			harvest_counts.get("egg", 0) >= 1
		), "msg": "Master Farmer!" },
	]

	for m in milestones:
		if m.condition and not _milestones_earned.has(m.id):
			_milestones_earned[m.id] = true
			milestone_reached.emit(m.id, m.msg)

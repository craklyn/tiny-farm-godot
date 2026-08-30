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
var crows_seen: int  # T-2: how many crows have ever arrived (kept for trace/compat)
# T-15 / Q-39: the mercy flag's real anchor. Under acorns the first several crows
# are already harmless *by behaviour*, so spending the scripted mercy on "the
# first crow ever" spends it on a bird that was never a threat. It belongs on the
# first crow to go for a **crop**, which is the moment the peace actually ends.
var crop_crows_seen: int

# T-9 (Q-34): tools are acquired, not owned. She starts with hands, hoe, can and
# seeds; the axe and pickaxe are earned, and each opens the parcel that needs it.
var tools_owned: Dictionary

# T-13 (Q-37/Q-45): the cold open spends real days before the player owns
# anything, so every day-keyed rule is anchored here rather than on `day`.
# Set by the sim when the neighbour's gate opens; 1 for a world without one.
var takeover_day: int

# Cleared-obstacle counts by verb, accrued in the sim gateway so replays earn
# them identically. Feeds T-10 ("has she ever cleared one of these?") and Q-46's
# pickaxe proof.
var clear_counts: Dictionary

# T-20: the day is measured in actions taken, not seconds. Each crow is assigned
# exactly one point in that day at which it flies in; being shooed means it is
# simply gone, because it never had a second arrival scheduled. See
# SimWorld.roll_crow_schedule().
var actions_today: int
var crow_schedule: Array[int]  # action counts at which a crow arrives today
var total_shipped: int  # Q-12 proof counter (crops sold, any route)

# T-11 (Q-35): "has she ever done this?" for the three economy verbs, so each
# teaching beat can fire exactly once by construction rather than by a flag.
# `total_shipped` already answers the selling half. Accrued where the actions
# resolve, so replays earn them identically; saved additively, default 0.
var seeds_bought: int
var cans_refilled: int
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
	crop_crows_seen = 0
	tools_owned = {
		"hands": true, "hoe": true, "watering_can": true, "seeds": true,
		"axe": false, "pickaxe": false,
	}
	takeover_day = 1
	clear_counts = {}
	actions_today = 0
	crow_schedule = []
	total_shipped = 0
	seeds_bought = 0
	cans_refilled = 0
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


# T-9: cycling never lands on a tool she has not acquired. A control that
# selects an invisible, unusable tool is the same class of dead end as the
# seed-cycling trap below — it responds, and the response means nothing.
func cycle_tool(direction: int) -> void:
	var tool_count := Tools.LIST.size()
	var step: int = 1 if direction >= 0 else -1
	for _i in tool_count:
		selected_tool = (selected_tool + step + tool_count) % tool_count
		if owns_tool(Tools.key_of(selected_tool)):
			break
	tool_changed.emit(selected_tool)


func owns_tool(key: String) -> bool:
	# Defaults to owned for anything the table has never heard of, so a new tool
	# added later is usable before anyone remembers to grant it.
	return bool(tools_owned.get(key, true))


# The player's own day 1 is the day she takes the farm over, not the day the
# world started. Everything day-keyed (crow readiness, the crow schedule, the
# vignette's beats) counts in these.
func play_day() -> int:
	return day - takeover_day + 1


# Reported from play 2026-08-28: after placing a scarecrow, with 0 of every seed
# type, cycling stopped doing anything at all.
#
# The old loop only accepted a type she had stock of, so owning nothing meant it
# matched nothing and returned having changed nothing — silently. A control that
# does nothing and says nothing is indistinguishable from a broken game (S-7),
# and it is worse here than it looks, because the selection it leaves stranded
# is what resolve() consults: stuck on "scarecrow" with none left, a tilled tile
# answers "no seeds" even after she has bought wheat.
#
# Now it always advances to the next unlocked type, preferring ones she actually
# has. The control therefore always responds, and a selection with no stock is a
# recoverable state rather than a dead end.
func cycle_seed_type() -> void:
	var order := CropDefs.ORDER
	var current_idx := order.find(selected_seed_type)
	if current_idx == -1:
		current_idx = 0

	var first_unlocked := ""
	for offset in range(1, order.size() + 1):
		var idx := (current_idx + offset) % order.size()
		var seed_type: String = order[idx]
		var def: Dictionary = CropDefs.TYPES.get(seed_type, {})
		if not def.has("seed_price") or not CropDefs.is_seed_unlocked(seed_type, harvest_counts):
			continue
		if seeds.get(seed_type, 0) > 0:
			selected_seed_type = seed_type
			return
		if first_unlocked == "":
			first_unlocked = seed_type
	# Nothing in stock anywhere: still move, so the control visibly answers.
	if first_unlocked != "":
		selected_seed_type = first_unlocked


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
	seeds_bought += 1
	# Hold what you just bought, if you were holding nothing. Without this the
	# selection can point at an item with no stock while the pouch has seeds in
	# it, so a tilled tile reports "no seeds" to a player who just bought some —
	# the trap underneath the 2026-08-28 scarecrow report. Deliberately does not
	# override a selection she still has stock of: buying a scarecrow should not
	# silently stop her planting the wheat she was mid-row on.
	if seeds.get(selected_seed_type, 0) <= 0:
		selected_seed_type = seed_type
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
	# A fresh day's action clock, and a fresh set of arrival points for it. Rolled
	# here so it is seeded sim truth and a replay reproduces the same birds.
	actions_today = 0
	crow_schedule = SimWorld.roll_crow_schedule(play_day())
	
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
		cans_refilled += 1
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

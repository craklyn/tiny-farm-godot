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
# **One pouch** (S-18/S-19/S-20, 2026-09-23). What she has harvested and what she can sow
# used to be two dictionaries of the same substance — `seeds`, which `plant` drew
# from, and `crops`, which the bin emptied — and keeping them apart is what made
# a wheat plant something you could sell but never sow. Merged, a harvested plant
# *is* the seed for the next one, which is the whole of the change: she can farm
# without money, and the bin becomes the place she gets rid of a surplus rather
# than the only thing a crop is for.
#
# `pouch` holds plantable crop species only. `items` holds eggs and scarecrows;
# the crop row decides whether a key is plantable or sellable, and neither item
# counts against a crop's carrying limit or enters the reserve.
#
# Still not the home of acorns or machines; see their own notes below.
var pouch: Dictionary  # Plantable carried crop units only.
var items: Dictionary  # Eggs and scarecrows: carried, but never plantable crops.
var bin_reserve: Dictionary  # Plantable units kept at the shipping bin, per species.
var last_bin_delivery: Dictionary
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

# T-30 (Q-48): acorns she has picked up herself. A count, because an acorn is
# indistinguishable from another acorn — the egg's and the scarecrow's shape,
# minus their dictionary, since there is exactly one kind of thing in here.
#
# Deliberately **not** a key in `pouch`, which is not a neutral cupboard: what is
# deposited past the bin reserve is counted into `total_shipped` (so an acorn
# would quietly pay off Q-12's proof), and a plantable entry is one `plant` can
# put in the ground. An acorn is neither, yet.
#
# It has no use today — collecting one takes it out of the crow's stock (Q-48's
# whole point) and that is all it does. Phase 2's decoy and feed designs are
# where it may acquire one.
var acorns: int

# **The crate** — machines she has bought and not yet put down (2026-09-03, the
# designer's placeholder acquisition rule; see `systems/machine_defs.gd`).
#
# Deliberately not a corner of `pouch`, for the reason the acorn is not one: a
# plantable thing in the pouch is put into soil by the `plant` verb, and a machine
# is **placed** on the ground by the `place` verb and then starts acting on its
# own. Keeping them apart is what lets the pouch stay a pouch while a tower, a
# fence or a hopper joins this dictionary with no new field.
var machines: Dictionary

# T-11's shape, for the machines: "has she ever bought one?" — accrued in the sim
# gateway so a replay earns it identically, saved additively, default 0.
var machines_bought: int

# The world's starting fence becomes hers after her first successful purchase of
# fencing. Crate stock alone cannot answer this: she may lay or use every post.
var fence_purchased: bool

# **What the crate remembers** (Q-98, ruled 2026-09-10: "pick up is just
# repositioning, it shouldn't factory reset the robot"). Machine key → the `extra`
# of each boxed machine that had something worth keeping, newest last; `place`
# takes the newest one back out.
#
# A second dictionary rather than a richer `machines`, because the two answer
# different questions and only one of them is asked often: `machines` is "how many
# have I got", which the HUD pill, the held-item ring and the router all read every
# frame, and it is an int per key in every save on disk. Turning that into a list of
# objects to carry a robot's brain would change a count every caller already trusts.
# This sits beside it, empty for every machine that has no memories — a sprinkler
# boxed and set down again is the same sprinkler either way — and holds exactly the
# machines whose past would otherwise be thrown away.
#
# Keyed by the catalogue row rather than by the actor id the robot used to have,
# because the id is gone the moment it is despawned and the row is what she is
# holding: she picks up two Mark IIIs, she puts two down, and the one she boxed last
# is the one that comes out first.
var boxed: Dictionary

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
# The same appointment book for an ant raid (M2.5 WI-8a, `design/04` §3). Always
# empty in a real game — `SimWorld.ANT_RAIDS_PER_DAY` is 0 and the debut is a
# designer's sequencing call, not a switch this milestone flips — but the
# lifecycle behind it is built and tested, and it rides the same action clock the
# crow does so that pressure follows productivity for both.
var ant_schedule: Array[int]
# ...and one book for everybody after them (M2.5 WI-8c/8f/8g): `{species:
# [action counts]}`, filled from `SimWorld.roll_visitor_schedules()`. A
# dictionary rather than a field per species because the crow's and the raid's
# already cost a field, a roll, a save key and a `_send_due_*` each, and the
# bestiary is not going to stop at five — a new critter is a row in
# `SimWorld.visitors()` and nothing here changes. Always empty in a real game:
# every `per_day` in that table is 0.
var visitor_schedules: Dictionary
var total_shipped: int  # Q-12 proof counter (crops sold, any route)
var bin_deposits: int  # Successful player bin errands, including reserve-only deposits.

# T-11 (Q-35): "has she ever done this?" for the three economy verbs, so each
# teaching beat can fire exactly once by construction rather than by a flag.
# `total_shipped` already answers the selling half. Accrued where the actions
# resolve, so replays earn them identically; saved additively, default 0.
var seeds_bought: int
var cans_refilled: int
var phase1_complete: bool  # Q-12/P-4: set silently by the sim at sleep when the proof is met

# P-15: which story-night loops the overnight has already shown this farm, keyed
# by the sim's own night name ("crow_night", "robot_night"). The sim's own
# `story_nights_told` already stops a night's *trigger* from firing twice; this
# is presentation's own once-per-farm guard. It is set when the hold chooses a
# loop (`systems/day_cycle.gd`) and travels with the farm's next save.
var story_loops_shown: Dictionary = {}

# Which builds this farm has lived under. This is save metadata, not sim truth:
# it never affects an action or a replay comparison, but it must survive between
# autosaves so a later Continue can add the next build to the history.
var save_lineage: Array[Dictionary]

# Milestones tracking
var _milestones_earned: Dictionary = {}

# Game state
var game_paused: bool = false
var pending_load: bool = false  # title screen asks main to load the autosave
var pending_boot_fade: bool = false  # title screen asks main to fade in from its cover (Q-103)
# Q-103: the bloom plays once per launch. The title screen sets this after its
# first entry; a return from the pause menu, the zoo or the home screen lands on
# the settled menu instead of replaying the boot.
var boot_bloom_played: bool = false

# Save file locations — overridable so automated sessions (robot tests) never
# touch a real player's files
var save_path: String = SaveSlots.save_path(1)
var replay_path: String = SaveSlots.replay_path(1)
var trace_path: String = SaveSlots.trace_path(1)  # diagnostic; see systems/session_trace.gd

# Which of the three farms is being played (S-14). The three paths above are
# still the truth every writer reads, and every tool that overrides them keeps
# working exactly as it did; this is the number the title screen sets them from.
var slot: int = 1


# Point the three paths at one farm's directory. Everything a session writes
# follows from this one call, which is why the title screen makes it before it
# starts the game rather than each writer working the slot out for itself.
#
# `root` is here for the same reason the three paths are overridable at all: a
# test can run the whole of this against a scratch directory and never come near
# a real player's farms.
func use_slot(n: int, root: String = SaveSlots.ROOT) -> void:
	slot = SaveSlots.clamp_slot(n)
	SaveSlots.ensure_dir(slot, root)
	save_path = SaveSlots.save_path(slot, root)
	replay_path = SaveSlots.replay_path(slot, root)
	trace_path = SaveSlots.trace_path(slot, root)


func _init() -> void:
	reset()


func reset() -> void:
	# New-game / replay baseline — the single source of default values.
	day = 1
	weather = "sunny"
	# T-29: the day is 600 fine units and a base verb costs 30 of them, so this is
	# the same 20-action day it has always been (`Tools.DAY_UNITS`).
	energy = Tools.DAY_UNITS
	max_energy = Tools.DAY_UNITS
	gold = 0
	selected_tool = 0
	# Five wheat and nothing else: the same handful she has always started with,
	# and now the only stock she ever needs, since cutting one gives it back.
	pouch = { "wheat": 5, "tomato": 0 }
	items = { "egg": 0, "scarecrow": 0 }
	bin_reserve = {}
	last_bin_delivery = {}
	harvest_counts = { "wheat": 0, "tomato": 0 }
	shipping_bin = { "wheat": 0, "tomato": 0 }
	watering_can_charges = 8
	max_watering_can_charges = 8
	selected_seed_type = "wheat"
	hard_energy = false
	crows_scared = 0
	crows_seen = 0
	crop_crows_seen = 0
	acorns = 0
	machines = {}
	machines_bought = 0
	fence_purchased = false
	boxed = {}
	tools_owned = {
		"hands": true, "hoe": true, "watering_can": true, "seeds": true,
		"axe": false, "pickaxe": false,
	}
	takeover_day = 1
	clear_counts = {}
	actions_today = 0
	crow_schedule = []
	ant_schedule = []
	visitor_schedules = {}
	total_shipped = 0
	bin_deposits = 0
	seeds_bought = 0
	cans_refilled = 0
	phase1_complete = false
	story_loops_shown = {}
	save_lineage = []
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
	var order := held_order()
	var current_idx := order.find(selected_seed_type)
	if current_idx == -1:
		current_idx = 0

	var first_unlocked := ""
	for offset in range(1, order.size() + 1):
		var idx := (current_idx + offset) % order.size()
		var seed_type: String = order[idx]
		if MachineDefs.has(seed_type):
			# Machines only enter the cycle when she owns one (see held_order), so
			# reaching one here means it is holdable; no stock test to fail.
			selected_seed_type = seed_type
			return
		if not CropDefs.is_plantable(seed_type) \
				or not CropDefs.is_seed_unlocked(seed_type, harvest_counts):
			continue
		if held_count(seed_type) > 0:
			selected_seed_type = seed_type
			return
		if first_unlocked == "":
			first_unlocked = seed_type
	# Nothing in stock anywhere: still move, so the control visibly answers.
	if first_unlocked != "":
		selected_seed_type = first_unlocked


# What the selection control can land on: every seed, always, plus each machine
# she actually has in the crate (2026-09-03).
#
# **Machines join the cycle so that owning one is never a dead end.** Buying a
# robot puts it in her hands; without this, one press of the cycle control to get
# back to wheat would strand the robot in the crate with no way to select it
# again short of buying a second. The seeds stay unconditional for the reason
# they always were — the control has to visibly answer even with an empty pouch
# (the 2026-08-28 scarecrow report) — and a machine with none left simply drops
# out of the ring the moment it is placed.
func held_order() -> Array:
	var order: Array = CropDefs.ORDER.duplicate()
	for key in MachineDefs.ORDER:
		if machines.get(key, 0) > 0:
			order.append(key)
	return order


# How many of the held item she has, whichever cupboard it lives in. The one
# question every caller actually asks — the router, the HUD pill and the gateway
# all had to know which dictionary to look in before this existed.
func held_count(key: String) -> int:
	if MachineDefs.has(key):
		return int(machines.get(key, 0))
	if not CropDefs.is_plantable(key):
		return int(items.get(key, 0))
	return int(pouch.get(key, 0))


# How many sowable things she is carrying, of every kind together. The question
# "is there anything to plant" — which is not "is the pouch empty" now that a
# pouch can hold nothing but eggs.
func sowable_total() -> int:
	var n := 0
	for key in pouch:
		if CropDefs.is_plantable(String(key)):
			n += int(pouch[key])
	return n


func holding_machine() -> bool:
	return MachineDefs.has(selected_seed_type) and machines.get(selected_seed_type, 0) > 0 \
		and MachineDefs.terrain_of(selected_seed_type) == ""


# Is what she has in hand a thing that lays ground rather than a thing that walks
# (Q-92)? Fencing lives in the same crate as the machines and is selected the same
# way; what it becomes when she puts it down is the only difference, and that is
# the gateway's business rather than this flag's.
func holding_buildable() -> bool:
	return holding_terrain() and machines.get(selected_seed_type, 0) > 0


# Is the thing in her hand a *kind* of ground, whether or not she has any left?
#
# The stock-free question, and it exists because of the moment the stocked one
# gets wrong: she lays her tenth post, the crate empties, and the eleventh tap
# lands on bare ground with fencing still selected. Asking "is she holding
# fencing" and getting *no* there sends the tap down to the ground's own states,
# where cleared soil means **till** — so running out silently turned her fence
# into a hoe. A tap that quietly does something else is the failure this game
# keeps stamping out; running out has to say so.
func holding_terrain() -> bool:
	return MachineDefs.has(selected_seed_type) \
		and MachineDefs.terrain_of(selected_seed_type) != ""


func buy_seed(seed_type: String) -> bool:
	var def: Dictionary = CropDefs.TYPES.get(seed_type, {})
	if def.is_empty():
		return false
	if gold < def.seed_price:
		return false
	if not CropDefs.is_seed_unlocked(seed_type, harvest_counts):
		return false
	# A starter crop is not on the shelf (S-18/S-19/S-20) and so cannot be bought here
	# either — the shop and the till answer the same question, which is what stops
	# a bot buying a packet the player cannot see (S-3, ground rule 1). The
	# `buy_seed` verb itself is untouched: it is written into replay logs on disk
	# and every one of them still parses.
	if not CropDefs.is_on_shelf(seed_type):
		return false
	gold -= def.seed_price
	if CropDefs.is_plantable(seed_type):
		pouch[seed_type] = pouch.get(seed_type, 0) + 1
	else:
		items[seed_type] = items.get(seed_type, 0) + 1
	seeds_bought += 1
	# Hold what you just bought, if you were holding nothing. Without this the
	# selection can point at an item with no stock while the pouch has seeds in
	# it, so a tilled tile reports "no seeds" to a player who just bought some —
	# the trap underneath the 2026-08-28 scarecrow report. Deliberately does not
	# override a selection she still has stock of: buying a scarecrow should not
	# silently stop her planting the wheat she was mid-row on.
	if held_count(selected_seed_type) <= 0:
		selected_seed_type = seed_type
	gold_changed.emit(gold)
	return true


# The placeholder acquisition rule, in one function (2026-09-03): a machine is
# bought exactly the way a seed is, and goes into the crate instead of the pouch.
#
# **Always takes hold of what she just bought**, where `buy_seed` deliberately
# does not. The two cases are different: buying a scarecrow mid-row must not stop
# her planting wheat, but a machine is bought *in order to put it somewhere* —
# nobody buys a robot to keep it in a box — and the very next tap she makes is
# meant to be the placement. Getting back to seeds is one press of the cycle
# control, which now rings through her machines too (`held_order`).
func is_unlocked(key: String) -> bool:
	return MachineDefs.is_unlocked(key, harvest_counts)


func buy_machine(key: String) -> bool:
	var def: Dictionary = MachineDefs.TYPES.get(key, {})
	if def.is_empty():
		return false
	if gold < int(def.price):
		return false
	if not is_unlocked(key):
		return false
	gold -= int(def.price)
	# A card can be a bundle. Fencing is sold ten posts at a time because a fence
	# is a run rather than an object, and buying twenty squares one card at a time
	# is an errand rather than a decision (Q-92). Everything else is one.
	machines[key] = machines.get(key, 0) + int(def.get("bundle", 1))
	machines_bought += 1
	if key == "fence":
		fence_purchased = true
	selected_seed_type = key
	gold_changed.emit(gold)
	return true


# What one crop fetches at the bin. **One price, two sellers** (v0.2.1 WI-9a): she
# empties her carried crops into the bin, a machine brings its counted harvest, and
# a farm where those two paid differently would be a farm where it mattered whose
# hands the wheat arrived in. A crop nobody has priced is worth nothing rather
# than an error, which is what an unknown type has always been worth here.
static func crop_price(crop_type: String) -> int:
	var def: Dictionary = CropDefs.TYPES.get(crop_type, {})
	if def.is_empty():
		return 0
	return int(def.sell_price)


# The bin keeps the first ten plantable units of each species. The reserve is
# separate from what she carries and survives sleep. [Playtest] Q-116.
const BIN_RESERVE_CAP := 10


func sellable_total() -> int:
	var n := int(items.get("egg", 0))
	for crop_type in pouch:
		n += int(pouch[crop_type])
	return n


# Shared allocator for player deposits and machine deliveries. Only the excess
# pays gold and counts as shipped. An egg keeps its old immediate-sale behavior.
func allocate_bin_delivery(crop_type: String, count: int) -> Dictionary:
	if count <= 0 or not CropDefs.is_sellable(crop_type):
		return { "ok": false, "reserved": 0, "sold": 0, "gold": 0 }
	var reserved := 0
	if CropDefs.is_plantable(crop_type):
		reserved = mini(count, maxi(0, BIN_RESERVE_CAP - int(bin_reserve.get(crop_type, 0))))
		bin_reserve[crop_type] = int(bin_reserve.get(crop_type, 0)) + reserved
	var sold := count - reserved
	var paid := sold * crop_price(crop_type)
	gold += paid
	total_shipped += sold
	if paid > 0:
		gold_changed.emit(gold)
	return { "ok": true, "reserved": reserved, "sold": sold, "gold": paid }


func sell_crops_to_bin() -> Dictionary:
	var result := { "ok": false, "reserved": {}, "sold": {}, "gold": 0 }
	for crop_type in pouch.keys():
		var count := int(pouch[crop_type])
		if count <= 0:
			continue
		var delivery := allocate_bin_delivery(String(crop_type), count)
		pouch[crop_type] = 0
		result.ok = true
		result.reserved[crop_type] = int(delivery.reserved)
		result.sold[crop_type] = int(delivery.sold)
		result.gold += int(delivery.gold)
	var eggs := int(items.get("egg", 0))
	if eggs > 0:
		var egg_delivery := allocate_bin_delivery("egg", eggs)
		items["egg"] = 0
		result.ok = true
		result.reserved["egg"] = 0
		result.sold["egg"] = eggs
		result.gold += int(egg_delivery.gold)
	if result.ok:
		bin_deposits += 1
		last_bin_delivery = result.duplicate(true)
	return result


func sell_one_crop(crop_type: String, count: int = 1) -> Dictionary:
	# The bin menu reports the last *player* deposit. A machine may deliver after
	# she leaves; it must not rewrite that sentence as if she had deposited it.
	return allocate_bin_delivery(crop_type, count)


func withdraw_reserved_crop(crop_type: String, cap: int = 10) -> int:
	if not CropDefs.is_plantable(crop_type):
		return 0
	var moved := mini(int(bin_reserve.get(crop_type, 0)),
		maxi(0, cap - int(pouch.get(crop_type, 0))))
	if moved > 0:
		bin_reserve[crop_type] = int(bin_reserve[crop_type]) - moved
		pouch[crop_type] = int(pouch.get(crop_type, 0)) + moved
	return moved


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
	ant_schedule = SimWorld.roll_ant_schedule(play_day())
	visitor_schedules = SimWorld.roll_visitor_schedules(play_day())

	# The next day's sky depends on the seed and day, not on how many draws
	# moving actors happened to consume before the player went to bed.
	if SimRng.stateless(day, 9000) % 100 < 20:
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

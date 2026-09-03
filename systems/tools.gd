# tools.gd — Tool definitions and action validation (static utility)
# Mirrors the Love2D tools.lua exactly
class_name Tools
extends RefCounted

# Tool data structure
class ToolDef:
	var tool_name: String
	var icon: int
	var can_act_on: Array[String]
	# T-9 (Q-34): tools are acquired, not owned. `key` is the stable identifier
	# used by GameState.tools_owned, the take_tool verb and WorldLayout's placed
	# tool objects ("tool_axe" is the axe's object name).
	var key: String

	func _init(p_name: String, p_icon: int, p_can_act_on: Array[String], p_key: String) -> void:
		tool_name = p_name
		icon = p_icon
		can_act_on = p_can_act_on
		key = p_key

# Tool list — same order as Love2D
static var LIST: Array[ToolDef] = [
	ToolDef.new("Hands",        0, ["obstacle_weed", "ready"], "hands"),
	ToolDef.new("Axe",          1, ["obstacle_log", "obstacle_tree"], "axe"),
	ToolDef.new("Pickaxe",      2, ["obstacle_rock"], "pickaxe"),
	ToolDef.new("Hoe",          3, ["cleared"], "hoe"),
	ToolDef.new("Watering Can", 4, ["seeded", "growing"], "watering_can"),
	ToolDef.new("Seeds",        5, ["tilled"], "seeds"),
]

# --- The day, in fine units (T-29 / Q-38's rider) -----------------------------
#
# Energy *is* the clock (Q-38): the day is one full meter and only actions spend
# it. T-29 re-partitions that meter from 20 coarse points into **600 fine
# units**, with a base verb costing 30. The day is still exactly 20 base actions
# long, so at 1x this is bit-for-bit the game it was — the same refusal moments,
# the same soft floor, the same sky at the same instant. Only the ruler got finer.
#
# **Why 30.** A future work-speed multiplier m (Q-38's exchange-rate correction:
# a fed farmer spends less clock, never rewinds the sun) divides an action's cost
# to 30/m. 30 is the smallest base on which every multiplier the designer named
# lands on a whole number — 1.25x->24, 1.5x->20, 2x->15, 2/3x->45, 1/2x->60 —
# and 2.5x->12, 3x->10 and 0.75x->40 come free. (General rule: any m = n/d with n
# dividing 30d works. Misses exist, 1.4x among them, but every named multiplier
# and its neighbours hit.) Every other cost stays a whole multiple of 30 so the
# same argument covers it — 30k·d/n is whole wherever 30·d/n is.
#
# **The clear ladder (Q-50, ruled 2026-09-02).** Early-game pacing leans on
# clearing costs: expanding into debris must cost noticeably more than tending
# cleared land, and the costs differ by obstacle — a weed is a bare-handed tug
# (one base verb, and it doubles as the stomp verb, which is tending, not
# expansion), a downed log two, a standing tree or a rock three. The exact
# numbers are [Playtest]; the *ordering* is the ruling. Q-11's soft floor keeps
# even the dearest clear from ever locking a kid out — it spends clock, never
# blocks.
#
# One number, read by everything: `GameState.max_energy`, `SimWorld
# .ACTOR_MAX_ENERGY` and `SaveGame`'s ×30 legacy shim all derive from these.
const DAY_UNITS := 600
const BASE_COST := 30   # till, water, harvest, clear a weed — 20 of them make a day
const HEAVY_COST := 60  # a downed log: two base verbs' worth
const DEAR_COST := 90   # a standing tree or a rock: three — expansion is exertion (Q-50)

# Energy costs per action, in the units above.
static var ENERGY_COSTS: Dictionary = {
	"clear_weed": BASE_COST,
	"clear_log": HEAVY_COST,
	"clear_tree": DEAR_COST,
	"clear_rock": DEAR_COST,
	"till": BASE_COST,
	"water": BASE_COST,
	"harvest": BASE_COST,
	"plant": 0,
	# Carrying a machine out to where it belongs and setting it down is work
	# (2026-09-03) — one base verb, the same as tilling the square it stands on.
	# Buying it and turning its dial are errands and cost nothing (see
	# `SimWorld.NON_WORK_VERBS`); the walk and the lift are the part that is real.
	"place": BASE_COST,
	"configure": 0,
	"sell": 0,
	"refill": 0,
	"sleep": 0,
}


static func can_act_on_tile(tool_index: int, tile_state: String) -> bool:
	if tool_index < 0 or tool_index >= LIST.size():
		return false
	var tool: ToolDef = LIST[tool_index]
	return tile_state in tool.can_act_on


static func get_action(tool_index: int, tile_state: String) -> String:
	if not can_act_on_tile(tool_index, tile_state):
		return ""
	var tool_name: String = LIST[tool_index].tool_name
	match tool_name:
		"Hands":
			if tile_state == "obstacle_weed":
				return "clear_weed"
			if tile_state == "ready":
				return "harvest"
		"Axe":
			return "clear_tree" if tile_state == "obstacle_tree" else "clear_log"
		"Pickaxe":
			return "clear_rock"
		"Hoe":
			return "till"
		"Watering Can":
			return "water"
		"Seeds":
			return "plant"
	return ""


static func get_energy_cost(action: String) -> int:
	return ENERGY_COSTS.get(action, 0)


static func key_of(tool_index: int) -> String:
	if tool_index < 0 or tool_index >= LIST.size():
		return ""
	return LIST[tool_index].key


static func index_of_key(key: String) -> int:
	for i in LIST.size():
		if LIST[i].key == key:
			return i
	return -1

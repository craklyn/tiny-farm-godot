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

# Energy costs per action
static var ENERGY_COSTS: Dictionary = {
	"clear_weed": 1,
	"clear_log": 2,
	"clear_tree": 2,
	"clear_rock": 2,
	"till": 1,
	"water": 1,
	"harvest": 1,
	"plant": 0,
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

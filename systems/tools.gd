# tools.gd — Tool definitions and action validation (static utility)
# Mirrors the Love2D tools.lua exactly
class_name Tools
extends RefCounted

# Tool data structure
class ToolDef:
	var tool_name: String
	var icon: int
	var can_act_on: Array[String]

	func _init(p_name: String, p_icon: int, p_can_act_on: Array[String]) -> void:
		tool_name = p_name
		icon = p_icon
		can_act_on = p_can_act_on

# Tool list — same order as Love2D
static var LIST: Array[ToolDef] = [
	ToolDef.new("Hands",        0, ["obstacle_weed", "ready"]),
	ToolDef.new("Axe",          1, ["obstacle_log"]),
	ToolDef.new("Pickaxe",      2, ["obstacle_rock"]),
	ToolDef.new("Hoe",          3, ["cleared"]),
	ToolDef.new("Watering Can", 4, ["seeded", "growing"]),
	ToolDef.new("Seeds",        5, ["tilled"]),
]

# Energy costs per action
static var ENERGY_COSTS: Dictionary = {
	"clear_weed": 1,
	"clear_log": 2,
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
			return "clear_log"
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

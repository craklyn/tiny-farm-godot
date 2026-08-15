# crop_defs.gd — Crop type definitions and growth logic (static utility)
# Mirrors the Love2D crops.lua exactly
class_name CropDefs
extends RefCounted

# Crop definitions
static var TYPES: Dictionary = {
	"wheat": {
		"name": "Wheat",
		"days_to_grow": 3,
		"sell_price": 15,
		"seed_price": 5,
		"stages": 4,
		"unlock_requirement": null,
		"sprite_row": 0,
	},
	"tomato": {
		"name": "Tomato",
		"days_to_grow": 5,
		"sell_price": 30,
		"seed_price": 10,
		"stages": 4,
		"unlock_requirement": { "crop": "wheat", "count": 1 },
		"sprite_row": 1,
	},
	"egg": {
		"name": "Egg",
		"sell_price": 10,
	},
}

# Display order
static var ORDER: Array[String] = ["wheat", "tomato"]


static func is_ready(crop_type: String, growth_stage: int) -> bool:
	var def: Dictionary = TYPES.get(crop_type, {})
	if def.is_empty():
		return false
	return growth_stage >= def.days_to_grow


static func get_visual_stage(crop_type: String, growth_stage: int) -> int:
	var def: Dictionary = TYPES.get(crop_type, {})
	if def.is_empty():
		return 0
	if growth_stage <= 0:
		return 0  # seed
	if is_ready(crop_type, growth_stage):
		return 3  # ready
	var progress: float = float(growth_stage) / float(def.days_to_grow)
	if progress < 0.5:
		return 1  # sprout
	return 2  # mid-growth


static func is_seed_unlocked(seed_type: String, harvest_counts: Dictionary) -> bool:
	var def: Dictionary = TYPES.get(seed_type, {})
	if def.is_empty():
		return false
	var req = def.get("unlock_requirement")
	if req == null:
		return true
	return harvest_counts.get(req.crop, 0) >= req.count

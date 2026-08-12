# action_router.gd — Context-sensitive action resolver autoload
# Mirrors src/action_router.lua in the LÖVE2D build.
# Given a farm, game_state, and a tapped tile, returns the best action to
# perform automatically — no manual tool selection required for basic actions.
extends Node

const SPECIAL_OBJECTS := {
	"cot":          "sleep",
	"well":         "refill",
	"seed_box":     "open_shop",
	"shipping_bin": "sell",
}

## Result dictionary returned by resolve():
##   action     String    — action name (matches Tools energy cost keys, or special)
##   tool_idx   int       — 0-based tool index to auto-select
##   target_t   Vector2i  — tile to act ON
##   walk_to    bool      — player must walk adjacent first
##   seed_type  String    — seed type if action == "plant", else ""


## Resolve the best action for a tapped tile.
##
## @param farm     Node2D    — the farm node, must expose get_tile_state(tx,ty),
##                             get_object(tx,ty), is_walkable(tx,ty)
## @param gs       Node      — GameState autoload
## @param tap_t    Vector2i  — tapped tile (0-indexed)
## @return Dictionary|null
func resolve(farm: Node2D, gs: Node, tap_t: Vector2i) -> Dictionary:
	var tx := tap_t.x
	var ty := tap_t.y

	# 1. Special objects
	var obj: String = farm.get_object(tx, ty)
	if obj != "" and SPECIAL_OBJECTS.has(obj):
		return {
			"action":    SPECIAL_OBJECTS[obj],
			"tool_idx":  0,  # Hands
			"target_t":  tap_t,
			"walk_to":   true,
			"seed_type": "",
		}

	# 2. Get tile state
	var tile: Dictionary = farm.get_tile(tx, ty)
	if tile.is_empty():
		return {}  # Out of bounds
	var state: String = tile.get("state", "")

	# 3. Obstacle clearing → correct tool
	if state == "obstacle_rock":
		return { "action": "clear_rock", "tool_idx": 2, "target_t": tap_t, "walk_to": true, "seed_type": "" }
	if state == "obstacle_log":
		return { "action": "clear_log",  "tool_idx": 1, "target_t": tap_t, "walk_to": true, "seed_type": "" }
	if state == "obstacle_weed":
		return { "action": "clear_weed", "tool_idx": 0, "target_t": tap_t, "walk_to": true, "seed_type": "" }

	# 4. Ready crop → harvest
	if state == "ready":
		return { "action": "harvest", "tool_idx": 0, "target_t": tap_t, "walk_to": true, "seed_type": "" }

	# 5. Tilled → plant active seed
	if state == "tilled":
		var seed_type: String = gs.selected_seed_type
		if gs.seeds.get(seed_type, 0) > 0:
			return { "action": "plant", "tool_idx": 5, "target_t": tap_t, "walk_to": true, "seed_type": seed_type }
		return {}

	# 6. Cleared → till
	if state == "cleared":
		if gs.energy >= Tools.get_energy_cost("till"):
			return { "action": "till", "tool_idx": 3, "target_t": tap_t, "walk_to": true, "seed_type": "" }
		return {}

	# 7. Seeded / Growing and not yet watered today → water
	if (state == "seeded" or state == "growing") and not tile.get("watered_today", true):
		if gs.watering_can_charges > 0 and gs.energy >= Tools.get_energy_cost("water"):
			return { "action": "water", "tool_idx": 4, "target_t": tap_t, "walk_to": true, "seed_type": "" }
		return {}

	return {}


## Returns a Color for the tile cursor based on what action would be performed.
func get_cursor_color(farm: Node2D, gs: Node, tap_t: Vector2i) -> Color:
	var result := resolve(farm, gs, tap_t)
	if not result.is_empty() and result.get("action", "") != "":
		return Color(0.2, 0.9, 0.3, 0.6)  # Green — valid action
	var state: String = farm.get_tile(tap_t.x, tap_t.y).get("state", "")
	if state == "border" or state.begins_with("obstacle"):
		return Color(0.9, 0.3, 0.2, 0.6)  # Red — blocked
	return Color(0.9, 0.85, 0.3, 0.6)     # Yellow — neutral

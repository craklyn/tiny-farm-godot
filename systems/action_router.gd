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
	"egg":          "collect",
	"scarecrow":    "collect",
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
## @param player_t Vector2i|null — player's current tile (0-indexed)
## @param is_drag  bool      — true if triggered by a drag/swipe
## @param drag_tool_idx Variant|null — if provided, restricts action to this tool_idx (int) or -1 (no action)
## @return Dictionary|null
func resolve(farm: Node2D, gs: Node, tap_t: Vector2i, player_t = null, is_drag: bool = false, drag_tool_idx = null) -> Dictionary:
	var tx := tap_t.x
	var ty := tap_t.y

	# Helper to enforce drag intent
	var check_result = func(res: Dictionary) -> Dictionary:
		if drag_tool_idx != null:
			if typeof(drag_tool_idx) == TYPE_INT and drag_tool_idx == -1:
				return {}
			if res.get("tool_idx", -1) != drag_tool_idx:
				return {}
		return res

	# 1. Special objects
	var obj: String = farm.get_object(tx, ty)
	if obj != "" and SPECIAL_OBJECTS.has(obj):
		return check_result.call({
			"action":    SPECIAL_OBJECTS[obj],
			"tool_idx":  0,  # Hands
			"target_t":  tap_t,
			"walk_to":   true,
			"seed_type": "",
		})

	# 2. Get tile state
	var tile: Dictionary = farm.get_tile(tx, ty)
	if tile.is_empty():
		return {}  # Out of bounds
	var state: String = tile.get("state", "")

	# Intent Filter: For non-obstacles, if it's a far tap (not a drag), treat as pure movement
	var is_tool_action := (state == "cleared" or state == "tilled" or state == "seeded" or state == "growing")
	if is_tool_action and not is_drag and player_t != null:
		var pt: Vector2i = player_t
		var dist := absi(pt.x - tx) + absi(pt.y - ty)
		if dist > 1:
			return {}

	# 3. Obstacle clearing → correct tool
	if state == "obstacle_rock":
		return check_result.call({ "action": "clear_rock", "tool_idx": 2, "target_t": tap_t, "walk_to": true, "seed_type": "" })
	if state == "obstacle_log":
		return check_result.call({ "action": "clear_log",  "tool_idx": 1, "target_t": tap_t, "walk_to": true, "seed_type": "" })
	if state == "obstacle_weed":
		return check_result.call({ "action": "clear_weed", "tool_idx": 0, "target_t": tap_t, "walk_to": true, "seed_type": "" })

	# 4. Ready crop → harvest
	if state == "ready":
		return check_result.call({ "action": "harvest", "tool_idx": 0, "target_t": tap_t, "walk_to": true, "seed_type": "" })

	# 5. Tilled → plant active seed
	if state == "tilled":
		var seed_type: String = gs.selected_seed_type
		if gs.seeds.get(seed_type, 0) > 0:
			return check_result.call({ "action": "plant", "tool_idx": 5, "target_t": tap_t, "walk_to": true, "seed_type": seed_type })
		return {}

	# 6. Cleared → till OR plant object
	if state == "cleared":
		var seed_type: String = gs.selected_seed_type
		if gs.seeds.get(seed_type, 0) > 0 and CropDefs.TYPES.get(seed_type, {}).get("is_object", false):
			return check_result.call({ "action": "plant", "tool_idx": 5, "target_t": tap_t, "walk_to": true, "seed_type": seed_type })
		if gs.energy >= Tools.get_energy_cost("till"):
			return check_result.call({ "action": "till", "tool_idx": 3, "target_t": tap_t, "walk_to": true, "seed_type": "" })
		return {}

	# 7. Seeded / Growing and not yet watered today → water
	if (state == "seeded" or state == "growing") and not tile.get("watered_today", true):
		if gs.watering_can_charges > 0 and gs.energy >= Tools.get_energy_cost("water"):
			return check_result.call({ "action": "water", "tool_idx": 4, "target_t": tap_t, "walk_to": true, "seed_type": "" })
		return {}

	return {}


## Why a tap on a workable tile produced no action — "" when there was genuinely
## nothing to do there.
##
## Found in the first real session trace ever read (2026-08-28): after tilling a
## tile with an empty seed pouch, eight taps in four seconds produced absolute
## silence. The 2026-08-27 refusal feedback fixed the *sim* layer — an action the
## sim rejects now says so — but this is the layer above it: when resolve()
## declines to produce an action at all, there is nothing for the sim to refuse,
## so nothing ever speaks. Every `return {}` below that is caused by a missing
## resource needs a voice, or a pre-reader is left tapping a tile that will never
## answer (S-7).
##
## Mirrors resolve()'s guards deliberately rather than sharing code with them:
## resolve answers "what happens", this answers "why not", and collapsing the two
## would make resolve return a reason it does not need on every successful call.
func blocked_reason(farm: Node2D, gs: Node, tap_t: Vector2i) -> String:
	var tile: Dictionary = farm.get_tile(tap_t.x, tap_t.y)
	if tile.is_empty():
		return ""
	var state: String = String(tile.get("state", ""))
	var seed_type: String = gs.selected_seed_type

	if state == "tilled":
		if gs.seeds.get(seed_type, 0) <= 0:
			return "no seeds"
		return ""
	if state == "cleared":
		if gs.energy < Tools.get_energy_cost("till"):
			return "too tired"
		return ""
	if state == "seeded" or state == "growing":
		if tile.get("watered_today", false):
			return ""  # already watered — nothing to do, not a refusal
		if gs.watering_can_charges <= 0:
			return "watering can empty"
		if gs.energy < Tools.get_energy_cost("water"):
			return "too tired"
	return ""


## True when a tile is one the player could work *at all*, ignoring whether they
## currently hold the seeds, water or energy to do it.
##
## resolve() deliberately returns nothing when a resource is missing, which is
## right for "what happens on tap" but wrong for "how do I walk there": running
## out of seeds made her walk on top of the tile instead of up to it, because the
## approach logic could no longer tell it was a farmable square.
func is_workable(farm: Node2D, tap_t: Vector2i) -> bool:
	var obj: String = farm.get_object(tap_t.x, tap_t.y)
	if obj != "" and SPECIAL_OBJECTS.has(obj):
		return true
	var tile: Dictionary = farm.get_tile(tap_t.x, tap_t.y)
	if tile.is_empty():
		return false
	return String(tile.get("state", "")) in [
		"obstacle_rock", "obstacle_log", "obstacle_weed",
		"cleared", "tilled", "seeded", "growing", "ready",
	]


## Returns a Color for the tile cursor based on what action would be performed.
func get_cursor_color(farm: Node2D, gs: Node, tap_t: Vector2i, player_t = null, is_drag: bool = false) -> Color:
	var result := resolve(farm, gs, tap_t, player_t, is_drag)
	if not result.is_empty() and result.get("action", "") != "":
		return Color(0.2, 0.9, 0.3, 0.6)  # Green — valid action
	var state: String = farm.get_tile(tap_t.x, tap_t.y).get("state", "")
	if state == "border" or state.begins_with("obstacle"):
		return Color(0.9, 0.3, 0.2, 0.6)  # Red — blocked
	return Color(0.9, 0.85, 0.3, 0.6)     # Yellow — neutral

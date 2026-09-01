# action_router.gd — Context-sensitive action resolver autoload
# Mirrors src/action_router.lua in the LÖVE2D build.
# Given a farm, game_state, and a tapped tile, returns the best action to
# perform automatically — no manual tool selection required for basic actions.
extends Node

## T-27 (box 3): the objects a tap that achieved nothing may be *rescued* to.
##
## **The cot only**, deliberately. The mechanism is written so the shipping bin
## and the well can join it whenever the designer says so — they are the other
## two things in the yard worth a fat finger — but wiring one object is the
## smallest change that answers the evidence, and every extra entry here is a
## tile that silently stops meaning what it says.
const HALO_OBJECTS := { "cot": true }

const SPECIAL_OBJECTS := {
	"cot":          "sleep",
	"well":         "refill",
	"seed_box":     "open_shop",
	"shipping_bin": "sell",
	"egg":          "collect",
	"scarecrow":    "collect",
	# T-30 (Q-48). Resolved here, in the object table, which settles the ordering
	# question it raises: acorns are dropped on **cleared** ground, so the same tap
	# could mean "pick that up" or "till this". The object wins — block 1 runs
	# before the tile's state is even read — and that is the rule the egg has
	# always had (an egg laid on tilled soil is collected, not planted into).
	# Picking a thing up off a square is what a hand does with that square first.
	"acorn":        "collect",
	"tool_axe":     "take_tool",
	"tool_pickaxe": "take_tool",
}

# T-9 (Q-34): which tool an obstacle needs. A tool she has not acquired yields no
# action at all — the tap becomes pure movement and she walks up to the obstacle
# and stops, which is the wordless "not yet". By layout construction she should
# rarely meet one, since locked-tool obstacles live behind closed gates; this is
# the honest answer for the cases the layout does not cover.
const OBSTACLE_TOOLS := {
	"obstacle_weed": "hands",
	"obstacle_log":  "axe",
	"obstacle_tree": "axe",
	"obstacle_rock": "pickaxe",
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
		# A placed tool she has not yet earned is a promise, not a prize. Q-46's
		# strawman proof decides when it becomes collectable; until then the tap
		# resolves to nothing here, so she walks over, looks at it, and stops.
		# That is the same "not yet" the hedge gives, and it needs no words.
		if SPECIAL_OBJECTS[obj] == "take_tool":
			var entry := _tool_entry_for(obj)
			if entry.is_empty() or not SimWorld.tool_proof_met(entry, gs):
				return {}
		return check_result.call({
			"action":    SPECIAL_OBJECTS[obj],
			"tool_idx":  0,  # Hands
			"target_t":  tap_t,
			"walk_to":   true,
			"seed_type": "",
			"tool":      String(_tool_entry_for(obj).get("tool", "")),
		})

	# 1b. A critter underfoot answers before the ground does — the stomp
	# (P-10 / `design/04` §4; M2.5 WI-8a). It resolves to the *hands* clear, the
	# verb she already uses to pull a weed up, so the sim needed no new word and a
	# bot answering a scout does exactly what a child's tap does (ground rule 1).
	#
	# Asked of the **registry**, the way `main.gd` asks it which tile the hen is
	# standing on before it clucks: where an actor is standing is sim truth, and a
	# second scout answers here for free. It is asked before the tile's own state
	# because the ant is the thing on the square that wants dealing with — and the
	# gateway makes sure the stomp leaves the ground alone, so tapping an ant that
	# is sitting on a row of wheat costs her the ant and not the wheat.
	var world = farm.get("sim")
	if world != null and world.stompable_at(tap_t):
		# Far taps stay pure movement, exactly as they do for a workable tile
		# below: she walks over, and the tap that lands when she is there stomps.
		if not is_drag and player_t != null:
			var pt0: Vector2i = player_t
			if absi(pt0.x - tx) + absi(pt0.y - ty) > 1:
				return {}
		return check_result.call({
			"action": "clear_weed", "tool_idx": 0, "target_t": tap_t,
			"walk_to": true, "seed_type": "",
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

	# 3. Obstacle clearing → correct tool, if she has it (T-9)
	if state == "obstacle_rock" and _owns_for(gs, state):
		return check_result.call({ "action": "clear_rock", "tool_idx": 2, "target_t": tap_t, "walk_to": true, "seed_type": "" })
	if state == "obstacle_log" and _owns_for(gs, state):
		return check_result.call({ "action": "clear_log",  "tool_idx": 1, "target_t": tap_t, "walk_to": true, "seed_type": "" })
	if state == "obstacle_tree" and _owns_for(gs, state):
		return check_result.call({ "action": "clear_tree", "tool_idx": 1, "target_t": tap_t, "walk_to": true, "seed_type": "" })
	if state == "obstacle_weed" and _owns_for(gs, state):
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


## resolve(), plus the refusal-aware tap halo — T-27 (box 3), T-18's philosophy
## applied to *where* a tap landed rather than to what it found there.
##
## The evidence (2026-08-30, 5m04–10s): four consecutive `no_energy` refusals on
## (2,2), one tile below the cot at (2,1), every one of them a tap meant for the
## cot and resolved as till-with-hoe. Nothing was broken — she missed by one tile,
## four times, and the game answered "you cannot till that" four times.
##
## **The tapped tile always wins when it produces a real world change.** Only a
## tap that produced nothing at all is rescued, and only to a high-value
## interactable orthogonally adjacent to it. Four guards keep that promise narrow:
##
##  1. a non-empty resolution is returned untouched — a till is a till;
##  2. a drag is never rescued: a stroke is a deliberate line, and rescuing one
##     would make a swipe along a row sleep her when it reached the cot's column;
##  3. only a tap she is standing on or beside is rescued — a far tap already has
##     an honest answer (she walks toward it), and rescuing one would put her to
##     sleep from across the farm;
##  4. a tile that answers *yes-done* is never rescued (Q-42): "already watered"
##     is an answer, and the halo must not talk over it.
##
## The rescue re-resolves as if she had tapped the object itself, so everything
## downstream — the approach, the walk, the tap indicator, the sim Action — is the
## ordinary cot tap it was meant to be. `halo_from` carries the tile the finger
## actually hit so the trace can still record the miss (that evidence is the whole
## reason this exists).
##
## Sim untouched: this is intent resolution, layer 3, and it produces no verb the
## player did not already have.
func resolve_with_halo(farm: Node2D, gs: Node, tap_t: Vector2i, player_t = null,
		is_drag: bool = false, drag_tool_idx = null) -> Dictionary:
	var direct := resolve(farm, gs, tap_t, player_t, is_drag, drag_tool_idx)
	if not direct.is_empty():
		return direct                                    # guard 1
	if is_drag or player_t == null:
		return direct                                    # guard 2
	var pt: Vector2i = player_t
	if absi(pt.x - tap_t.x) + absi(pt.y - tap_t.y) > 1:
		return direct                                    # guard 3
	if satisfied_reason(farm, gs, tap_t) != "":
		return direct                                    # guard 4

	# Fixed order (N, S, W, E) so the rule is reproducible if two haloed objects
	# ever end up beside the same tile.
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = tap_t + d
		if not HALO_OBJECTS.has(farm.get_object(n.x, n.y)):
			continue
		var rescued := resolve(farm, gs, n, player_t, is_drag, drag_tool_idx)
		if not rescued.is_empty():
			rescued["halo_from"] = tap_t
			return rescued
	return direct


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
			return "no_seeds"
		return ""
	if state == "cleared":
		if gs.energy < Tools.get_energy_cost("till"):
			return "no_energy"
		return ""
	if state == "seeded" or state == "growing":
		if tile.get("watered_today", false):
			return ""  # already watered — satisfied_reason() answers this one
		if gs.watering_can_charges <= 0:
			return "no_water"
		if gs.energy < Tools.get_energy_cost("water"):
			return "no_energy"
	return ""


## Why a tap produced no action because the target is **already in a good
## state** — the game's third state, which until now had no voice at all.
##
## T-18/T-19, Q-42 (2026-08-29). The game has three answers: *did it* (squash +
## sound), *cannot* (wobble + nope), and *nothing to do* — and the third was
## silence, which a four-year-old reads as a broken tile. The 2026-08-28 session
## measured it: 20 dead taps held the watering can over crops already watered
## that day, and all five stuck tiles had the shape *worked five times, then
## dead*. Q-42 ruled the fix: the tile answers **yes-done, never no**.
##
## Deliberately a sibling of blocked_reason() rather than a merge with it. They
## answer different questions — "why could you not" versus "why did you not need
## to" — and the answers get opposite feedback, so collapsing them would be one
## boolean away from wobbling at a finished tile, which is the exact thing Q-42
## forbids.
##
## Pure read: touches no state, mutates nothing.
func satisfied_reason(farm: Node2D, gs: Node, tap_t: Vector2i) -> String:
	var obj: String = farm.get_object(tap_t.x, tap_t.y)
	if obj == "well":
		if gs.watering_can_charges >= gs.max_watering_can_charges:
			return "can_full"
		return ""
	if obj == "shipping_bin":
		for count in gs.crops.values():
			if int(count) > 0:
				return ""
		return "basket_empty"
	var tile: Dictionary = farm.get_tile(tap_t.x, tap_t.y)
	if tile.is_empty():
		return ""
	var state: String = String(tile.get("state", ""))
	if (state == "seeded" or state == "growing") and tile.get("watered_today", false):
		return "already_watered"
	return ""


## True when a tile is one the player could work *at all*, ignoring whether they
## currently hold the seeds, water or energy to do it.
##
## resolve() deliberately returns nothing when a resource is missing, which is
## right for "what happens on tap" but wrong for "how do I walk there": running
## out of seeds made her walk on top of the tile instead of up to it, because the
## approach logic could no longer tell it was a farmable square.
##
## **`WorldLayout.YARD` is absent from this list on purpose (T-32).** The yard is
## home, not field: there is nothing to do to it, so it is not workable, so a tap
## on it takes the same route a tap on plain grass takes — she walks over and
## stands on it. That is T-18's rule holding by construction rather than by a
## special case: yard is not a tile the router refuses, it is a tile the router
## has no opinion about, and the only answer left for one of those is movement.
func is_workable(farm: Node2D, tap_t: Vector2i) -> bool:
	var obj: String = farm.get_object(tap_t.x, tap_t.y)
	if obj != "" and SPECIAL_OBJECTS.has(obj):
		return true
	var tile: Dictionary = farm.get_tile(tap_t.x, tap_t.y)
	if tile.is_empty():
		return false
	return String(tile.get("state", "")) in [
		"obstacle_rock", "obstacle_log", "obstacle_tree", "obstacle_weed",
		"cleared", "tilled", "seeded", "growing", "ready",
	]


func _owns_for(gs: Node, state: String) -> bool:
	var key: String = OBSTACLE_TOOLS.get(state, "")
	if key == "":
		return true
	return gs.owns_tool(key)


func _tool_entry_for(obj: String) -> Dictionary:
	for e in WorldLayout.tools():
		if String(e.get("object", "")) == obj:
			return e
	return {}


## Returns a Color for the tile cursor based on what action would be performed.
func get_cursor_color(farm: Node2D, gs: Node, tap_t: Vector2i, player_t = null, is_drag: bool = false) -> Color:
	var result := resolve(farm, gs, tap_t, player_t, is_drag)
	if not result.is_empty() and result.get("action", "") != "":
		return Color(0.2, 0.9, 0.3, 0.6)  # Green — valid action
	var state: String = farm.get_tile(tap_t.x, tap_t.y).get("state", "")
	if state == "border" or state.begins_with("obstacle"):
		return Color(0.9, 0.3, 0.2, 0.6)  # Red — blocked
	return Color(0.9, 0.85, 0.3, 0.6)     # Yellow — neutral

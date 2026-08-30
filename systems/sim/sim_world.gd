# sim_world.gd — Grid-truth simulation state (S-5, M2)
# Owns the farm's tile/object grids and every mutation of them; apply_action()
# is the single gateway every actor (player, crow, chicken, later bots) uses
# to change the world (S-3).
# Layer-2 rules (docs/ARCHITECTURE.md): no Node inheritance, no rendering,
# no autoload access, no Input — only SimRng (seeded) and CropDefs/Tools (data).
class_name SimWorld
extends RefCounted

const MAP_WIDTH := 32
const MAP_HEIGHT := 20

# T-8 / Q-34: the world is parcels now. Where the land is and what opens it is
# data in systems/world_layout.gd; this file only knows how to fill a region
# definition. The old uniform 25% sprinkle and the two hard-coded onboarding
# tile constants are gone with it — obstacle *type* is now a property of the
# parcel a tile belongs to, so a rock the player cannot break is a legible
# future behind a hedge rather than noise in her yard.
var layout: Dictionary = WorldLayout.DEFAULT

# T-2 / design/13 §4: the first session contains no threat at all.
#
# The spawner used to fire every 10 s from day 1 whenever more than one crop
# existed, so a four-year-old could meet a pest before she had ever met a
# harvest — which makes the crow a threat rather than the joke Q-10 rules it
# must be. Readiness is gated on evidence rather than the calendar: she must
# have completed the loop at least once, and have enough planted that losing one
# is affordable. The day floor is a backstop, not the mechanism.
# Counted in *play-days*, not absolute days: the cold open (T-13) spends real
# days before the player owns anything, so anchoring on `day` would let a crow
# arrive on her first morning. See GameState.play_day().
const CROW_MIN_DAY := 3
const CROW_MIN_HARVESTS := 1
const CROW_MIN_PLANTED := 3

# T-20, ruled 2026-08-28: a crow gets exactly one chance per day.
#
# The spawner used to fire on a 10-second wall-clock timer, so once the readiness
# conditions were met a crow arrived roughly six times a minute for as long as the
# app was open — dozens in a short session, which makes shooing a chore rather than
# a win. Each crow now gets a single scheduled arrival, expressed as a point in the
# day's *action clock*: shooed or fed, it is done, because it never had a second
# arrival to make.
#
# Measuring the day in actions rather than seconds has a property the timer could
# not: pressure follows productivity. A player who wanders, pokes at the chicken
# and plants nothing is never visited, while a busy farm draws birds — which is
# both fairer and the right fiction.
#
# CROWS_PER_DAY is the flock dial that phase 2 turns up (design/13, Q-39).
const CROWS_PER_DAY := 1
const CROW_EARLIEST_ACTION := 4   # never in the first few actions of a day


# Arrival points for one day, as action counts. Seeded, so a replay sees the same
# birds arrive at the same moments. `day` is a **play-day** (see CROW_MIN_DAY).
static func roll_crow_schedule(day: int) -> Array[int]:
	var out: Array[int] = []
	if day < CROW_MIN_DAY:
		return out
	# Derived, not drawn: see SimRng.stateless(). A per-day value taken from the
	# shared stream desyncs replays, because entity noise advances that stream
	# between actions.
	for i in CROWS_PER_DAY:
		out.append(CROW_EARLIEST_ACTION + SimRng.stateless(day, i) % 20)
	out.sort()
	return out


# Pure so it can be tested without a scene tree; the caller (main.gd) owns the
# timer, this owns the rule. `day` is a **play-day** (see CROW_MIN_DAY).
static func may_spawn_crow(day: int, total_harvests: int, planted: int) -> bool:
	return day >= CROW_MIN_DAY \
		and total_harvests >= CROW_MIN_HARVESTS \
		and planted >= CROW_MIN_PLANTED


# Fixed object positions (0-indexed tile coords)
const OBJECT_POSITIONS: Array[Dictionary] = [
	{ "type": "cot",          "tx": 2, "ty": 1 },
	{ "type": "shipping_bin", "tx": 4, "ty": 1 },
	{ "type": "well",         "tx": 6, "ty": 1 },
	{ "type": "seed_box",     "tx": 8, "ty": 1 },
]

# Tile data: tiles[y][x] = { state, crop_type, growth_stage, watered_today }
var tiles: Array[Array] = []
var objects: Array[Array] = []  # objects[y][x] = "" or object type string


func generate(with_layout: Dictionary = WorldLayout.DEFAULT) -> void:
	layout = with_layout
	tiles.clear()
	objects.clear()

	# 1. Bare ground inside the map border. Every later step overwrites; nothing
	#    below reads a tile it has not written, so the fill order is the only
	#    thing determinism depends on.
	for ty in MAP_HEIGHT:
		var row: Array[Dictionary] = []
		var obj_row: Array[String] = []
		for tx in MAP_WIDTH:
			if ty == 0 or ty == MAP_HEIGHT - 1 or tx == 0 or tx == MAP_WIDTH - 1:
				row.append(_create_tile("border"))
			else:
				row.append(_create_tile("cleared"))
			obj_row.append("")
		tiles.append(row)
		objects.append(obj_row)

	# 2. Each parcel's own obstacle, at its own density — this is the whole of
	#    T-8. One new obstacle type per parcel (design/13 §5, Valve principle 4);
	#    the wood is the single exception, and only because a standing tree is
	#    where a log comes from (Q-39).
	for p in WorldLayout.parcels(layout):
		var obstacle := String(p.get("obstacle", ""))
		var density := float(p.get("density", 0.0))
		var extra := String(p.get("extra_obstacle", ""))
		var extra_density := float(p.get("extra_density", 0.0))
		if obstacle == "" and extra == "":
			continue
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					if not _inside(tx, ty):
						continue
					var roll := SimRng.randf()
					if extra != "" and roll < extra_density:
						tiles[ty][tx] = _create_tile(extra)
					elif obstacle != "" and roll < extra_density + density:
						tiles[ty][tx] = _create_tile(obstacle)

	# 3. The boundaries, which are the design's real content: "not yet" expressed
	#    as land she can see rather than as a message she cannot read.
	for b in WorldLayout.boundaries(layout):
		var kind := String(b.get("kind", WorldLayout.FENCE))
		for r in b.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					if _inside(tx, ty):
						tiles[ty][tx] = _create_tile(kind)

	# 4. Gates, all closed. Closed becomes open is the cheapest celebration in the
	#    game and needs no words (design/13 §4a).
	for p in WorldLayout.parcels(layout):
		var g: Vector2i = p.get("gate", Vector2i(-1, -1))
		if g.x >= 0 and _inside(g.x, g.y):
			tiles[g.y][g.x] = _create_tile(WorldLayout.GATE_CLOSED)

	# 5. Fixed objects, on cleared ground with cleared shoulders.
	for obj in OBJECT_POSITIONS:
		var tx: int = obj.tx
		var ty: int = obj.ty
		tiles[ty][tx] = _create_tile("cleared")
		objects[ty][tx] = obj.type
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := tx + dx
				var ny := ty + dy
				if _inside(nx, ny) and objects[ny][nx] == "" \
						and not WorldLayout.is_boundary_state(String(tiles[ny][nx].state)):
					tiles[ny][nx] = _create_tile("cleared")

	# 6. The tools, lying at their gates from the first moment she can see them.
	#    Q-46 STRAWMAN — the mechanism is in DESIGNER_QUEUE, not settled here.
	for e in WorldLayout.tools(layout):
		var at: Vector2i = e.get("at", Vector2i(-1, -1))
		if _inside(at.x, at.y):
			tiles[at.y][at.x] = _create_tile("cleared")
			objects[at.y][at.x] = String(e.get("object", ""))

	# 7. A finite acorn stock near the trees (T-15 / Q-39). No regeneration in
	#    phase 1: the stock running down IS the difficulty ramp, and a ramp that
	#    refills is not a ramp. Walkable like an egg, so it can never trap anyone.
	_place_acorns()

	# 8. The neighbour's plot, in its state *before* the cold open runs. Her own
	#    actions and the world sleeps produce the takeover row, so what the player
	#    inherits is real world state rather than a picture of some.
	_place_neighbour_plot()


func _inside(tx: int, ty: int) -> bool:
	return tx >= 1 and tx <= MAP_WIDTH - 2 and ty >= 1 and ty <= MAP_HEIGHT - 2


func _place_acorns() -> void:
	var spec: Dictionary = layout.get("acorns", {})
	if spec.is_empty():
		return
	var rect: Rect2i = spec.get("rect", Rect2i())
	var want := int(spec.get("count", 0))
	var candidates: Array[Vector2i] = []
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if _inside(tx, ty) and tiles[ty][tx].state == "cleared" and objects[ty][tx] == "":
				candidates.append(Vector2i(tx, ty))
	# Seeded draw without replacement: swap-and-shrink so the same seed always
	# picks the same tiles in the same order.
	for i in want:
		if candidates.is_empty():
			return
		var idx: int = SimRng.randi() % candidates.size()
		var t: Vector2i = candidates[idx]
		candidates.remove_at(idx)
		objects[t.y][t.x] = "acorn"


# The layout contract WI-4's vignette derives its beats from. Placed here rather
# than scripted at runtime so that a fresh world is already a coherent story even
# if nothing ever animates: cleared → tilled → seeded → growing → ready, read
# left to right, is environmental storytelling that cannot be skipped.
func _place_neighbour_plot() -> void:
	var plot: Dictionary = layout.get("neighbour_plot", {})
	if plot.is_empty():
		return
	var crop := String(plot.get("crop", "wheat"))
	for t in plot.get("cleared", []):
		tiles[t.y][t.x] = _create_tile("cleared")
	for t in plot.get("tilled", []):
		tiles[t.y][t.x] = _create_tile("tilled")
	var demo: Vector2i = plot.get("cleared_for_demo", Vector2i(-1, -1))
	if demo.x >= 0:
		tiles[demo.y][demo.x] = _create_tile("cleared")
	for t in plot.get("seeded", []):
		tiles[t.y][t.x] = _create_tile("seeded")
		tiles[t.y][t.x].crop_type = crop
	for e in plot.get("growing", []):
		var at: Vector2i = e.get("at", Vector2i(-1, -1))
		tiles[at.y][at.x] = _create_tile("growing")
		tiles[at.y][at.x].crop_type = crop
		tiles[at.y][at.x].growth_stage = int(e.get("stage", 1))
	for t in plot.get("second_row", []):
		tiles[t.y][t.x] = _create_tile("tilled")


func _create_tile(state: String) -> Dictionary:
	return {
		"state": state,
		"crop_type": "",
		"growth_stage": 0,
		"watered_today": false,
	}


func get_tile(tx: int, ty: int) -> Dictionary:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		return tiles[ty][tx]
	return {}


func get_crop_type(tx: int, ty: int) -> String:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return ""
	return tile.get("crop_type", "")


func get_object(tx: int, ty: int) -> String:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		if objects[ty][tx] != "":
			return objects[ty][tx]
		# Check if the tile below has a tall object
		if ty + 1 < MAP_HEIGHT and objects[ty + 1][tx] in ["cot", "well", "seed_box"]:
			return objects[ty + 1][tx]
	return ""


func set_object(tx: int, ty: int, obj_type: String) -> void:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		objects[ty][tx] = obj_type


# Tiles holding a crop at any stage — what a crow could target, and the measure
# of whether the player has enough planted to afford losing one.
func count_planted() -> int:
	var n := 0
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			var st: String = tiles[ty][tx].get("state", "")
			if st == "seeded" or st == "growing" or st == "ready":
				n += 1
	return n


func is_protected_by_scarecrow(tx: int, ty: int) -> bool:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var nx := tx + dx
			var ny := ty + dy
			if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
				if objects[ny][nx] == "scarecrow":
					return true
	return false


func is_walkable(tx: int, ty: int) -> bool:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return false
	var state: String = tile.state
	if state == "border":
		return false
	if state.begins_with("obstacle"):
		return false
	# T-8: a boundary is land, and land is what says "not yet". An open gate is
	# ordinary ground — that transition is the whole reward.
	if WorldLayout.is_boundary_state(state):
		return false
	var obj := get_object(tx, ty)
	if obj != "" and obj != "egg" and obj != "acorn":
		return false
	return true


# Parcels are open when their gate is (or they never had one). Derived from the
# grid, so it survives saves and replays with no flag of its own.
func is_parcel_open(parcel: Dictionary) -> bool:
	var g: Vector2i = parcel.get("gate", Vector2i(-1, -1))
	if g.x < 0:
		return true
	return String(get_tile(g.x, g.y).get("state", "")) == WorldLayout.GATE_OPEN


# Q-46: the proof that makes a placed tool collectable. Thresholds ruled
# 2026-08-29 (5 harvests for the axe, 3 logs for the pickaxe); they still live in
# WorldLayout as named constants so they stay tunable. Pure, so the router can ask
# it and a test can drive it.
static func tool_proof_met(entry: Dictionary, gs) -> bool:
	return tool_proof_progress(entry, gs).get("met", false)


# The same rule, with its working shown — how far along she is, for the playtest
# readout. Deliberately the *source* of tool_proof_met rather than a parallel
# implementation, so the number on screen can never disagree with the gate.
static func tool_proof_progress(entry: Dictionary, gs) -> Dictionary:
	var proof := String(entry.get("proof", ""))
	var need := int(entry.get("threshold", 0))
	var have := 0
	if gs != null:
		match proof:
			"harvests":
				have = gs.total_harvests()
			"clear_log", "clear_rock", "clear_weed", "clear_tree":
				have = int(gs.clear_counts.get(proof, 0))
			_:
				return { "proof": proof, "have": 0, "need": need, "met": false }
	return { "proof": proof, "have": have, "need": need, "met": gs != null and have >= need }


# T-15 / Q-39: what a crow goes for. **Any acorn beats any crop** — that is the
# whole mechanic, and it is behaviour rather than the scripted mercy T-2 used, so
# a four-year-old can watch the rule instead of experiencing a bird that
# inexplicably left. The rule lives here; the caller supplies the draw, exactly
# as may_spawn_crow() splits rule from timer.
func choose_crow_target(prefer_seed: int) -> Dictionary:
	var acorns: Array[Vector2i] = []
	var crops: Array[Vector2i] = []
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			if objects[ty][tx] == "acorn":
				acorns.append(Vector2i(tx, ty))
				continue
			var st: String = tiles[ty][tx].get("state", "")
			if st == "seeded" or st == "growing" or st == "ready":
				crops.append(Vector2i(tx, ty))
	if not acorns.is_empty():
		return { "kind": "acorn", "tile": acorns[posmod(prefer_seed, acorns.size())] }
	if not crops.is_empty():
		return { "kind": "crop", "tile": crops[posmod(prefer_seed, crops.size())] }
	return { "kind": "none", "tile": Vector2i(-1, -1) }


func count_acorns() -> int:
	var n := 0
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			if objects[ty][tx] == "acorn":
				n += 1
	return n


func set_tile_state(tx: int, ty: int, new_state: String, crop_type: String = "") -> void:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return
	tile.state = new_state
	if crop_type != "":
		tile.crop_type = crop_type
	if new_state == "cleared" or new_state == "tilled":
		tile.crop_type = ""
		tile.growth_stage = 0
		tile.watered_today = false
	elif new_state == "seeded":
		tile.growth_stage = 0
		tile.watered_today = false


func water_tile(tx: int, ty: int) -> void:
	var tile := get_tile(tx, ty)
	if not tile.is_empty() and (tile.state == "seeded" or tile.state == "growing"):
		tile.watered_today = true


# --- Action gateway (S-3) -----------------------------------------------------
# action: { verb: String, target: Vector2i, seed_type: String, actor: String }
# gs: GameState (player/economy state) — required for verbs that touch it.
# Returns { ok: bool, reason: String, ...verb extras }. Mutation happens only
# on ok. Guards mirror the pre-M2 player checks exactly (no new validation yet).
# Verbs that can change milestone inputs (harvest counts, gold); other verbs
# skip the check — it dominated fast-forward throughput when run per action.
const MILESTONE_VERBS := { "harvest": true, "collect": true, "sell": true, "sleep": true, "buy_seed": true }


# Verbs that do not advance the day's clock: sleep ends it, and the shop and bin
# are errands rather than farm work. Everything else the player successfully does
# is one tick of the action clock T-20 schedules crows against.
const NON_WORK_VERBS := { "sleep": true, "sell": true, "buy_seed": true, "refill": true }

# **Every actor has its own energy meter** (designer, 2026-08-29). The player's
# meter happens to also be the clock — spending it is what advances the time of
# day (Q-38) — but that is a property of *her* meter, not a reason for everybody
# else to work for free. An NPC just gets tired, in its own pocket, and starts
# fresh when the day turns.
#
# The cold open (T-13) is why this had to be settled: there is one GameState, so
# without a per-actor meter the neighbour would have tilled, planted and watered
# her own row out of the player's energy, and the player would have woken on day
# 1 already tired. The first version of this fix simply made non-player actors
# free, which was wrong in the same way for the opposite reason.
#
# Only energy is metered per actor. Seeds and water are not modelled for NPCs —
# they bring their own, off screen — because an NPC seed pouch buys nothing in
# phase 1 and would be state to save, replay and keep coherent for no gain.
#
# Soft floor, exactly as Q-11 gives the player: an exhausted actor clamps at 0
# and its action still resolves. Nothing in phase 1 is a wall.
const ACTOR_MAX_ENERGY := 20  # [Playtest]

# actor name -> energy remaining. Sim truth: saved, restored and replayed, so an
# NPC's tiredness survives a reload and a replay reproduces it exactly. Absent
# means "has not worked yet", which reads as full.
var actor_energy: Dictionary = {}


static func _is_player(actor: String) -> bool:
	# "" is the player: plenty of call sites (and tests) omit the actor entirely,
	# and the player is the only actor anything ever forgot to name.
	return actor == "" or actor == "player"


func energy_of(actor: String) -> int:
	if _is_player(actor):
		return -1  # the player's meter is GameState's, not the world's
	return int(actor_energy.get(actor, ACTOR_MAX_ENERGY))


func is_exhausted(actor: String) -> bool:
	return not _is_player(actor) and energy_of(actor) <= 0


func spend_actor_energy(actor: String, cost: int) -> void:
	if _is_player(actor) or cost <= 0:
		return
	actor_energy[actor] = maxi(0, energy_of(actor) - cost)


func apply_action(action: Dictionary, gs = null) -> Dictionary:
	var result := _apply(action, gs)
	if result.get("ok", false) and gs != null \
			and String(action.get("actor", "")) == "player" \
			and not NON_WORK_VERBS.has(action.get("verb", "")) \
			and "actions_today" in gs:
		gs.actions_today += 1
	# Milestones are capability proofs (P-4) — sim truth, so replays earn them too
	if result.get("ok", false) and gs != null and MILESTONE_VERBS.has(action.get("verb", "")) \
			and gs.has_method("check_milestones"):
		gs.check_milestones()
	return result


func _apply(action: Dictionary, gs) -> Dictionary:
	var verb: String = action.get("verb", "")
	var target: Vector2i = action.get("target", Vector2i(-1, -1))

	match verb:
		# -- special-object verbs (no energy cost, pre-M2 behavior) --
		# These two are the only verbs whose failure means "there was nothing to
		# do", not "you cannot do that". A full watering can and an empty basket
		# are both perfectly fine states. Found in a real session (2026-08-28):
		# eight taps on the well and nine on the shipping bin, every one refused
		# with no reason at all — 17 of the session's 27 refusals.
		"sell":
			if gs == null: return _fail("no_state")
			if not gs.sell_crops_to_bin():
				return _fail("nothing_to_sell")
			return { "ok": true }
		"refill":
			if gs == null: return _fail("no_state")
			if not gs.refill_watering_can():
				return _fail("can_already_full")
			return { "ok": true }
		"buy_seed":
			if gs == null: return _fail("no_state")
			return { "ok": gs.buy_seed(action.get("seed_type", "")) }
		"collect":
			if gs == null: return _fail("no_state")
			var obj := get_object(target.x, target.y)
			if obj == "egg":
				set_object(target.x, target.y, "")
				gs.crops["egg"] = gs.crops.get("egg", 0) + 1
				gs.harvest_counts["egg"] = gs.harvest_counts.get("egg", 0) + 1
				return { "ok": true, "collected": "egg" }
			if obj == "scarecrow":
				set_object(target.x, target.y, "")
				gs.seeds["scarecrow"] = gs.seeds.get("scarecrow", 0) + 1
				return { "ok": true, "collected": "scarecrow" }
			return _fail("nothing_to_collect")

		# -- day transition --
		"sleep":
			if gs == null: return _fail("no_state")
			gs.start_new_day()
			if action.has("weather"):  # replay override: reproduce the logged roll
				gs.weather = action.weather
				gs.weather_changed.emit(gs.weather)
			advance_day(gs.weather)
			gs.process_shipping_bin()
			# Q-12/P-4: silent capability proof, measured at sleep; the flag
			# flips once, and the result tells presentation to celebrate
			var newly_complete := false
			if not gs.phase1_complete and _phase1_proof_met(gs):
				gs.phase1_complete = true
				newly_complete = true
			return { "ok": true, "day": gs.day, "weather": gs.weather, "phase1_complete_now": newly_complete }

		# -- land and tools (T-8/T-9, Q-34) --
		# Closed becomes open. Applied by the neighbour at the end of the cold
		# open (actor "neighbour") and by tool acquisition (actor "world") — both
		# recorded, so a replay opens the same gates at the same moments.
		"open_gate":
			var gtile := get_tile(target.x, target.y)
			if gtile.is_empty(): return _fail("out_of_bounds")
			if String(gtile.get("state", "")) != WorldLayout.GATE_CLOSED:
				return _fail("not_a_closed_gate")
			set_tile_state(target.x, target.y, WorldLayout.GATE_OPEN)
			# The cold open's gate is where the player's own day 1 begins, so the
			# day-keyed rules re-anchor here rather than on the absolute day
			# counter. Set inside the sim so a replay earns the same anchor.
			var opened := _parcel_with_gate(target)
			if gs != null and String(opened.get("opened_by", "")) == WorldLayout.OPENED_BY_COLD_OPEN \
					and "takeover_day" in gs:
				gs.takeover_day = gs.day
				# Whatever the cold open's own days rolled is not hers; play-day 1
				# starts now, and play-day 1 has no crows in it by construction.
				gs.actions_today = 0
				gs.crow_schedule = roll_crow_schedule(1)
			return { "ok": true, "opened": String(opened.get("id", "")) }

		# Picking a tool up off the ground. The proof gate lives in the router
		# (an unproven tool simply resolves as movement — she walks up to it and
		# stops, which is the wordless "not yet"); this guard is the sim's own
		# backstop, and it is never the path a player reaches by tapping.
		"take_tool":
			if gs == null: return _fail("no_state")
			var want := String(action.get("tool", ""))
			var placed := get_object(target.x, target.y)
			if placed == "" or not placed.begins_with("tool_"):
				return _fail("no_tool_here")
			if want != "" and placed != "tool_" + want:
				return _fail("wrong_tool")
			set_object(target.x, target.y, "")
			gs.tools_owned[placed.substr(5)] = true
			return { "ok": true, "tool": placed.substr(5) }

		# -- entity verbs --
		# T-15 / Q-39: the crow's preferred meal. An entity-only verb like
		# eat_crop, and like eat_crop it gives the bird no capability the player
		# could not exercise by hand (she can pick things up; she simply has no
		# reason to pick up an acorn in phase 1).
		"eat_acorn":
			if get_object(target.x, target.y) != "acorn": return _fail("no_acorn")
			set_object(target.x, target.y, "")
			return { "ok": true }
		"eat_crop":
			var tile := get_tile(target.x, target.y)
			if tile.is_empty(): return _fail("out_of_bounds")
			if tile.state in ["growing", "ready", "seeded"]:
				set_tile_state(target.x, target.y, "tilled")
				return { "ok": true }
			return _fail("no_crop")
		"lay_egg":
			if get_object(target.x, target.y) != "": return _fail("occupied")
			set_object(target.x, target.y, "egg")
			return { "ok": true }
		"crow_scared":
			# Player-caused scare event; feeds the Q-12 capability proof
			if gs == null: return _fail("no_state")
			gs.crows_scared += 1
			return { "ok": true }

		# -- energy-costed tile verbs --
		"clear_weed", "clear_log", "clear_rock", "clear_tree", "till", "plant", "water", "harvest":
			if gs == null: return _fail("no_state")
			var tile := get_tile(target.x, target.y)
			if tile.is_empty() or tile.get("state", "") == "": return _fail("out_of_bounds")
			var cost: int = Tools.get_energy_cost(verb)
			var actor := String(action.get("actor", ""))
			var charged: bool = _is_player(actor)
			# Q-11 soft floor: in phase 1 an empty tank never blocks the action,
			# it just stays at 0 (presentation slows the farmer as the nudge)
			if charged and gs.hard_energy and gs.energy < cost: return _fail("no_energy")
			var seed_type: String = action.get("seed_type", "")
			if charged and verb == "water" and gs.watering_can_charges <= 0: return _fail("no_water")
			if charged and verb == "plant" and gs.seeds.get(seed_type, 0) <= 0: return _fail("no_seeds")

			# The player's energy is also the clock, so hers goes through the setter,
			# not the field: set_energy() clamps identically and emits
			# energy_changed, which is what T-14's daylight tint listens to. A direct
			# write left the sky frozen until the next day turned over. Everyone
			# else spends from their own meter, which drives nothing but themselves.
			if charged:
				gs.set_energy(gs.energy - cost)
			else:
				spend_actor_energy(actor, cost)
			match verb:
				"clear_weed", "clear_log", "clear_rock", "clear_tree":
					set_tile_state(target.x, target.y, "cleared")
					# Accrued in the gateway so a replay earns the same counts.
					# Feeds T-10 ("has she ever cleared one of these?") and Q-46's
					# pickaxe proof, and costs one dictionary write per clear.
					if charged and "clear_counts" in gs:
						gs.clear_counts[verb] = int(gs.clear_counts.get(verb, 0)) + 1
				"till":
					set_tile_state(target.x, target.y, "tilled")
				"plant":
					var is_obj: bool = CropDefs.TYPES.get(seed_type, {}).get("is_object", false)
					if is_obj:
						set_object(target.x, target.y, seed_type)
					else:
						set_tile_state(target.x, target.y, "seeded", seed_type)
					if charged:
						gs.seeds[seed_type] -= 1
				"water":
					water_tile(target.x, target.y)
					if charged:
						gs.watering_can_charges -= 1
				"harvest":
					var crop_type := get_crop_type(target.x, target.y)
					if crop_type != "":
						gs.crops[crop_type] = gs.crops.get(crop_type, 0) + 1
						gs.harvest_counts[crop_type] = gs.harvest_counts.get(crop_type, 0) + 1
						set_tile_state(target.x, target.y, "cleared")
						return { "ok": true, "crop_type": crop_type }
			return { "ok": true }

	return _fail("unknown_verb")


func _fail(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason }


# Q-12 phase-1 proof thresholds — provisional, fine-tuned at playtest
const PHASE1_SHIPPED_TARGET := 20
const PHASE1_SCARED_TARGET := 3


# The tidy-farm half of the proof counts **opened parcels only**. Before T-8 it
# scanned the whole map, which was right when every tile was reachable from the
# first frame; with land behind gates it would make phase 1 impossible to finish
# without the pickaxe, and phase 1 completion is not supposed to require the last
# tool. Derived from gate state, so it needs no flag and survives replays.
func _phase1_proof_met(gs) -> bool:
	var p := phase1_progress(gs)
	return p.get("met", false)


# Obstacles still standing in parcels she can actually reach. O(map), so callers
# must not run it every frame (the playtest readout throttles it).
func count_obstacles_in_open_parcels() -> int:
	var n := 0
	for p in WorldLayout.parcels(layout):
		if not is_parcel_open(p):
			continue
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					if not _inside(tx, ty):
						continue
					if String(tiles[ty][tx].get("state", "")).begins_with("obstacle"):
						n += 1
	return n


# The phase-1 capability proof with its working shown. Same reason as
# tool_proof_progress: the readout must not be able to disagree with the gate, so
# the gate is defined in terms of this rather than beside it.
func phase1_progress(gs) -> Dictionary:
	var shipped := int(gs.total_shipped) if gs != null else 0
	var scared := int(gs.crows_scared) if gs != null else 0
	var left := count_obstacles_in_open_parcels()
	return {
		"shipped": shipped, "shipped_target": PHASE1_SHIPPED_TARGET,
		"scared": scared, "scared_target": PHASE1_SCARED_TARGET,
		"obstacles_left": left,
		"met": shipped >= PHASE1_SHIPPED_TARGET and scared >= PHASE1_SCARED_TARGET and left == 0,
	}


func _parcel_with_gate(gate: Vector2i) -> Dictionary:
	for p in WorldLayout.parcels(layout):
		if p.get("gate", Vector2i(-1, -1)) == gate:
			return p
	return {}


func advance_day(weather: String) -> void:
	# Everyone wakes rested, the player included (GameState.start_new_day does
	# hers). An NPC's tiredness is a within-day thing, same as the farmer's.
	for actor in actor_energy.keys():
		actor_energy[actor] = ACTOR_MAX_ENERGY
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			var tile: Dictionary = tiles[ty][tx]
			if tile.watered_today and (tile.state == "seeded" or tile.state == "growing"):
				tile.growth_stage += 1
				if tile.state == "seeded":
					tile.state = "growing"
				if CropDefs.is_ready(tile.crop_type, tile.growth_stage):
					tile.state = "ready"
			tile.watered_today = false

			if weather == "rainy" and tile.state in ["tilled", "seeded", "growing"]:
				tile.watered_today = true

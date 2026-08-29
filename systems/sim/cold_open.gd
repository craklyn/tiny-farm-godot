# cold_open.gd — The neighbour's last two days on her farm (T-13, Q-37/Q-45)
#
# Layer 2 (pure): static functions over SimWorld + GameState. No Node, no
# autoload, no rendering, no Input, no timers. Presentation paces the scene; this
# decides what she does next, and it decides it from world state alone.
#
# **She is not a cutscene system, she is one more actor.** Her till/plant/water go
# through apply_action with `actor: "neighbour"`, exactly as the crow and chicken
# do (S-3), so the opening is replayable, deterministic and produces *real* world
# state rather than scripted fakery. That reframing is the whole reason this is
# cheap: no new subsystem to keep in sync with the sim, and the single-gateway
# rule is honoured instead of carved around.
#
# **The player is never not in control.** She starts inside her own fenced yard
# with the chicken (the toy, not a chore — design/13 §4a) and may watch, wander
# or ignore everything. The restriction is spatial, which is the Half-Life method
# of holding attention with geometry rather than a camera cut, and it is why
# Valve's "never take control away" objection does not apply here.
#
# **Because it is derived, quitting mid-scene and reloading resumes correctly for
# free** — there are no flags to lose. `next_action` returns {} exactly when the
# gate is open, which is also why Continue never replays the opening.
class_name ColdOpen

# Q-45: time visibly passes, so the player watches a seed become food rather than
# being told that it did. Two world-sleeps is the least that shows a growth step
# twice; it is also what makes the takeover row read as a finished chain.
# [Playtest] — the cost is time-to-first-harvest, and the pen has to stay
# interesting for all of it.
const COLD_OPEN_DAYS := 2

# A stuck neighbour must never block the game. If the derived action keeps being
# refused, the scene gives up and opens the gate anyway.
const MAX_FAILURES := 3
const MAX_STEPS := 64


static func gate(world: SimWorld) -> Vector2i:
	for p in WorldLayout.parcels(world.layout):
		if String(p.get("opened_by", "")) == WorldLayout.OPENED_BY_COLD_OPEN:
			return p.get("gate", Vector2i(-1, -1))
	return Vector2i(-1, -1)


static func is_done(world: SimWorld) -> bool:
	var g := gate(world)
	if g.x < 0:
		return true
	return String(world.get_tile(g.x, g.y).get("state", "")) == WorldLayout.GATE_OPEN


# The next thing the neighbour does, or {} when the scene is over.
#
# The order below is the script, and it is derived rather than stepped: water
# what is dry, sleep when everything is watered, and once the days have passed,
# demonstrate the full till → plant → water cycle on one tile before waving and
# leaving the gate open. Q-37 ruled three verbs rather than one — three is not a
# cutscene when the player is free to move throughout.
static func next_action(world: SimWorld, gs) -> Dictionary:
	if is_done(world):
		return {}
	var plot: Dictionary = world.layout.get("neighbour_plot", {})
	if plot.is_empty():
		return { "verb": "open_gate", "target": gate(world), "actor": "neighbour" }

	var days_passed: int = maxi(0, gs.day - 1)
	var demo: Vector2i = plot.get("cleared_for_demo", Vector2i(-1, -1))

	if days_passed < COLD_OPEN_DAYS:
		var dry := _first_dry(world, plot, demo)
		if dry.x >= 0:
			return { "verb": "water", "target": dry, "actor": "neighbour" }
		# Everything she can do today is done, so the day turns. A world sleep is
		# a real `sleep` action: the crops grow because a day passed, not because
		# a script said so.
		return { "verb": "sleep", "actor": "world" }

	# The days have passed; now the demonstration itself, on one tile, in order.
	if demo.x >= 0:
		var st := String(world.get_tile(demo.x, demo.y).get("state", ""))
		if st == "cleared":
			return { "verb": "till", "target": demo, "actor": "neighbour" }
		if st == "tilled":
			return { "verb": "plant", "target": demo, "actor": "neighbour",
				"seed_type": String(plot.get("crop", "wheat")) }

	var dry_last := _first_dry(world, plot, demo)
	if dry_last.x >= 0:
		return { "verb": "water", "target": dry_last, "actor": "neighbour" }

	# She waves and goes, and the gate is left open. Closed becomes open is the
	# cheapest celebration in the game and a pre-reader reads it instantly.
	return { "verb": "open_gate", "target": gate(world), "actor": "neighbour" }


# Her tiles, in a fixed left-to-right order so the scene is deterministic and
# reads as one person working along a row.
static func her_tiles(plot: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var demo: Vector2i = plot.get("cleared_for_demo", Vector2i(-1, -1))
	if demo.x >= 0:
		out.append(demo)
	for t in plot.get("seeded", []):
		out.append(t)
	for e in plot.get("growing", []):
		out.append(e.get("at", Vector2i(-1, -1)))
	out.sort_custom(func(a, b): return (a.x + a.y * 100) < (b.x + b.y * 100))
	return out


static func _first_dry(world: SimWorld, plot: Dictionary, _demo: Vector2i) -> Vector2i:
	for t in her_tiles(plot):
		if t.x < 0:
			continue
		var tile := world.get_tile(t.x, t.y)
		var st := String(tile.get("state", ""))
		if (st == "seeded" or st == "growing") and not tile.get("watered_today", false):
			return t
	return Vector2i(-1, -1)


# Fast-forward the whole scene through a gateway (the farm in the running game,
# the SimWorld itself in a headless test), so the cold open is exercised
# end-to-end by exactly one code path.
#
# The failure bound is the point: a scene that cannot finish must still hand the
# player her farm. Whatever happens, this returns with the gate open.
static func run(gateway, world: SimWorld, gs, max_steps: int = MAX_STEPS) -> Dictionary:
	var applied := 0
	var failures := 0
	for _i in max_steps:
		var a := next_action(world, gs)
		if a.is_empty():
			return { "ok": true, "steps": applied, "aborted": false }
		var r: Dictionary = gateway.apply_action(a, gs)
		if r.get("ok", false):
			applied += 1
			failures = 0
		else:
			failures += 1
			if failures >= MAX_FAILURES:
				break
	var g := gate(world)
	if g.x >= 0 and not is_done(world):
		gateway.apply_action({ "verb": "open_gate", "target": g, "actor": "neighbour" }, gs)
	return { "ok": false, "steps": applied, "aborted": true }

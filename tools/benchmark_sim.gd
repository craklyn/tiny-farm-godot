# benchmark_sim.gd — Headless sim fast-forward benchmark
# (M2 step 6; **travel modelled** by M2.5 WI-12)
#
# Run: godot --headless --path . --script res://tools/benchmark_sim.gd
#
# Two measurements, run one after the other and reported together.
#
# **1. A day's work, walked.** Until WI-12 this file applied a plot's worth of
# Actions from nowhere: one actor id, no position, no clock, no travel — finding
# F-5's "the benchmark's actor teleports, so fast-forward cannot model travel".
# The worker is now a **real registered bot** (`BotBrain.deploy`, WI-9's one call)
# that *walks* to every tile it works, at the speed its species row declares,
# through the movement engine (WI-4) and the tick clock (WI-1). The plot and the
# verb sequence are unchanged, so the work is the same work; what is new is that
# reaching each tile costs ticks, and that everything else on the farm — the hen,
# and any other actor a future version puts here — lives through those ticks.
# `test_bots`'s benchmark block is the proof that the *registration* is free
# (four days of this exact verb sequence, unregistered worker vs. deployed bot,
# identical grids and identical state), so any movement in these numbers against
# the pre-WI-12 baseline is travel and nothing else.
#
# **2. One busy actor against eight.** Ground rule 8 says per-tick cost scales
# with active actors and pending events, never with elapsed ticks or map area.
# That is a claim about a slope, so it is measured as one: the same world, the
# same tick budget, benched with no bots, one, and eight, and the ratio printed.
# Circle bots around a standing farmer are the honest shape for it (WI-9's
# handoff): they walk every tick they are awake, they never re-plan around a
# moving owner, and there is nothing else in the run for them to be confused
# with. Eight idle shoo bots are benched beside them as the other end — a fleet
# with nothing to chase, which is what a farm full of parked machines costs.
#
# **Every run below is sequential, each from its own reseed** — never
# interleaved. A day's weather comes off the shared RNG stream, so two runs
# taking turns would each roll the other's weather and a rainy farm would be
# compared against a sunny one (the trap WI-9's deviation 8 cost half an hour to
# find).
#
# The exit code is the contract CI consumes (`.github/workflows/tests.yml`,
# "Sim benchmark (smoke)"): 0 when the run is healthy, non-zero when it is not.
# See FLOOR_TICKS_PER_SEC for what "not" means, and the frame budget beside it
# for the target that is reported but deliberately does not fail the build.
extends SceneTree

const DAYS := 1000
const NOMINAL_DAY_SECONDS := 600.0  # ~10 min of real play per in-game day
const SEED := 1234

# The plot the worker sweeps — 10 columns by 8 rows from (12,4), unchanged since
# M2 step 6 so the numbers stay comparable. Its east column is the hedge, which
# has no verb, so 72 of the 80 tiles are worked each day.
const PLOT_X0 := 12
const PLOT_X1 := 22
const PLOT_Y0 := 4
const PLOT_Y1 := 12

const BOT := "bot"
# Whom the worker follows: nobody. Its *policy* is this file — the stand-in for
# P-8's option-picker and for whatever drives an overnight training run — so its
# brain must not also be steering it. A follow bot with no owner registered polls
# and defers (`BotBrain._follow` → `_wait`), which leaves the route this file
# planned alone and still pays the poll, honestly, on the clock. Deploying it on
# the player instead would have it walk to a station beside her — and she stands
# in the yard, behind the cold open's closed gate, so it would clear its route
# every poll and never reach her.
const NOBODY := "nobody"

# --- the scaling run -----------------------------------------------------------
# 10,000 ticks is a quarter of an hour of sim time: long enough that the per-tick
# work dwarfs the fixed cost of generating a world (the ratios below repeat to
# within a hundredth across runs), short enough that four of these are still a
# benchmark rather than a test suite.
const SCALE_TICKS := 10000
const SCALE_FLEET := 8
const SCALE_ORBIT := 2
# Where the fleet orbits: the middle of the meadow, with the tiles under the ring
# cleared first. A weed on the ring would make a bot skip round it, and this run
# is meant to measure eight actors walking, not eight actors pathing round
# terrain that only one of the three configurations would meet.
const SCALE_CENTRE := Vector2i(10, 13)
const SCALE_CLEAR := 3

# --- what makes this run a failure ---------------------------------------------
# Two numbers, and they answer different questions.
#
# **1. The regression floor — the cheap alarm, and it is what fails the process.**
# An order of magnitude under the measured throughput, counted in ticks of sim
# time per wall-second. It exists to catch the catastrophic class of mistake this
# file was written for — per-tick work, a heartbeat, a per-map pass inside a
# brain's think — and it is deliberately crude: CI runs this on a shared cloud
# runner several times slower than any desktop, so a threshold tuned to a desktop
# would make red builds about somebody else's machine. Nothing honest about
# hardware reaches a factor of eight.
#
# The unit is ticks per wall-second on purpose. Until 2026-09-19 this was
# x-realtime, and x-realtime has a denominator the *designer* can move: the CEO
# ruled on 2026-09-06 that the mark-1 walks at two thirds the farmer's pace, and
# the same benchmark — same seed, same 62,000 tiles walked — went from 186,000
# ticks of travel to 310,000 and the headline number fell by a quarter. The sim
# had got *faster* per tick of work. A measure that reports a design ruling as an
# engineering regression is the wrong measure; ticks per second is the work
# actually simulated, and a walking speed cannot touch it.
const FLOOR_TICKS_PER_SEC := 5000.0

# **2. The frame budget — the number that means something in the game.** This is
# the target, and it is not a round number picked for headroom: it is what the
# live game asks of the sim in its worst frame, which is a thing the player can
# feel go wrong.
#
# `main.gd`'s pump converts wall time into ticks and will hand the sim up to
# `SimClock.MAX_TICKS_PER_FRAME` of them in a single frame. So the worst case is
# that many ticks landing inside one frame, with a farm's worth of machines awake
# in them. If that does not fit in the sim's slice of a frame, she sees a hitch —
# a stutter as the fleet thinks — and that is the failure this target names.
#
# The budget, taken apart:
#   a frame at 60 fps                                      16.67 ms
#   × the sim's share of it (the rest is drawing and UI)    ~25%
#   ÷ the ticks one frame may absorb (SimClock)             ÷ 4
#   ÷ how much slower the tablet is than this desktop       ÷ 8
# The first three are facts about the game. The fourth is **an assumption, not a
# measurement** — a mid-range Android running GDScript against this desktop —
# and it is the one number here still owed a real figure. Measuring it needs the
# tablet awake and on the network (`tools/profile_android.sh`, which builds a
# profile APK under its own package name so the real game and its saves are never
# touched); it was unreachable the night this was written. It is held as one
# constant so replacing it with a measured value is a one-line change.
const FRAME_SECONDS := 1.0 / 60.0
const SIM_SHARE_OF_FRAME := 0.25
const DEVICE_FACTOR := 8.0

# Which run the budget is judged against: the eight busy machines, because that is
# the farm phase 1 is walking her toward — work delegated to a fleet — and they
# are awake and moving every tick. The parked fleet is measured beside it and
# reported against the same budget, but it does not decide the verdict: no shoo
# bot ships (its debut is Q-56), so a farm cannot hold eight of them yet.
const BUDGET_SUBJECT := "%d busy machines" % SCALE_FLEET


func _init() -> void:
	var work := _work_run()
	# Sequential, each from its own reseed — see the header.
	var idle := _fleet_run(0, "")
	var one := _fleet_run(1, BotBrain.CONFIG_CIRCLE)
	var many := _fleet_run(SCALE_FLEET, BotBrain.CONFIG_CIRCLE)
	var parked := _fleet_run(SCALE_FLEET, BotBrain.CONFIG_SHOO)
	quit(_report(work, idle, one, many, parked))


# --- 1. a day's work, walked ---------------------------------------------------

func _work_run() -> Dictionary:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(SEED)
	var world := SimWorld.new()
	world.generate()

	# The worker: a real actor, with a species, a speed, a meter and a position.
	BotBrain.deploy(world, BOT, BotBrain.CONFIG_FOLLOW, _start_tile(world),
		{ "owner": NOBODY })

	var actions := 0
	var tiles_walked := 0
	var travel_ticks := 0
	var unreachable := 0
	var t0 := Time.get_ticks_usec()

	for _d in DAYS:
		# A generous day's work over the plot: clear/till/plant/water/harvest.
		gs.energy = 1000000
		gs.watering_can_charges = 1000000
		gs.seeds["wheat"] = 1000000
		for ty in range(PLOT_Y0, PLOT_Y1):
			# Serpentine, not row-major: a worker walks the rows and turns at the
			# end of one, it does not walk back to the near edge to start the
			# next. The pre-travel benchmark sweep was row-major because nothing
			# was walking anywhere; kept that way it would have spent half its
			# travel on a nine-tile trudge home eight times a day, and measured
			# that as the cost of farming.
			var back := (ty - PLOT_Y0) % 2 == 1
			for i in range(PLOT_X0, PLOT_X1):
				var tx: int = (PLOT_X1 - 1) - (i - PLOT_X0) if back else i
				var target := Vector2i(tx, ty)
				var verb := _verb_for(world, target)
				if verb == "":
					continue
				# Walk there first, and this is the whole of WI-12: a tile is
				# not worked because the loop reached it, it is worked because
				# the worker did.
				var walk := _reach(world, gs, target)
				if not walk["ok"]:
					unreachable += 1
					continue
				tiles_walked += int(walk["steps"])
				travel_ticks += int(walk["ticks"])
				var action := { "verb": verb, "target": target, "actor": BOT }
				if verb == "plant":
					action["seed_type"] = "wheat"
				world.apply_action(action, gs)
				actions += 1
		world.apply_action({ "verb": "sleep", "actor": "world" }, gs)
		actions += 1

	var elapsed := (Time.get_ticks_usec() - t0) / 1000000.0
	var out := {
		"elapsed": elapsed,
		"actions": actions,
		"tiles_walked": tiles_walked,
		"travel_ticks": travel_ticks,
		"unreachable": unreachable,
		"end_tick": world.clock.tick,
	}
	gs.free()
	return out


# The verb this tile is asking for, or "" for one that is not (the hedge column,
# a tile whose crop is not ready). Unchanged from the pre-travel benchmark.
# `tests/test_runner.gd:_benchmark_day` holds a copy, deliberately still
# row-major and still applying from nowhere: what it tests is that *registering*
# the worker changes nothing, which is the fact this file's numbers rest on.
func _verb_for(world: SimWorld, t: Vector2i) -> String:
	match String(world.get_tile(t.x, t.y).get("state", "")):
		"obstacle_rock": return "clear_rock"
		"obstacle_log": return "clear_log"
		"obstacle_weed": return "clear_weed"
		"cleared": return "till"
		"tilled": return "plant"
		"seeded", "growing": return "water"
		"ready": return "harvest"
	return ""


# Walk the worker into range of `target`, advancing the clock as it goes: one
# step per `Movement.ticks_per_tile`, and `advance_to_tick` between steps so
# every *other* actor's brain gets the ticks it is owed. This is ground rule 8
# from the caller's side — the clock is jumped from event to event and the ticks
# in between cost nothing, which is why a three-tile stride is nine ticks of sim
# time and three dictionary writes of work.
#
# **In range is Q-30's range**, and that is a fidelity decision worth stating
# plainly, because it is worth about half of all the walking in the run. The game
# does not put the farmer *on* the tile she works: she routes at it and stops the
# moment she is beside it, from whichever side the route brought her
# (`Pathfinding.find_path_toward`, `player.gd`'s approach block). A worker that
# stepped onto every tile would be modelling travel this game does not have, and
# a row of nine tiles would cost nine strides instead of the four or five a
# player actually walks. So the rule here is the player's rule: already adjacent
# (or standing on it) means already in range, and a walk stops on adjacency
# rather than on arrival.
func _reach(world: SimWorld, gs, target: Vector2i) -> Dictionary:
	var here := world.actor_pos(BOT)
	if _manhattan(here, target) <= 1:
		return { "ok": true, "steps": 0, "ticks": 0 }
	# Routed at the tile itself, exactly as Q-30 describes — except for one a
	# walker cannot stand on at all (a rock, a log, a weed), which has no route
	# *to* it and is approached by routing at the nearest tile beside it.
	if not Movement.plan(world, BOT, target):
		var planned := false
		for t in _beside(here, target):
			if Movement.plan(world, BOT, t):
				planned = true
				break
		if not planned:
			return { "ok": false, "steps": 0, "ticks": 0 }

	var start_tick := world.clock.tick
	var steps := 0
	while _manhattan(world.actor_pos(BOT), target) > 1:
		if Movement.step(world, BOT, world.clock.tick) != Movement.MOVED:
			break
		steps += 1
		# The engine set the next wake from the species row. Read it *now*: the
		# bot's own brain polls during the advance and writes the same field.
		var wake := int(world.actor(BOT)["extra"].get("wake", world.clock.tick + 1))
		world.advance_to_tick(wake, gs)
	Movement.clear_route(world, BOT)
	return { "ok": true, "steps": steps, "ticks": world.clock.tick - start_tick }


# The four neighbours of a tile, nearest to `from` first, ties broken by
# `Movement.DIRS` order so the same farm is always worked in the same order.
func _beside(from: Vector2i, t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Movement.DIRS:
		out.append(t + d)
	var sorted: Array[Vector2i] = []
	while not out.is_empty():
		var best := 0
		for i in range(1, out.size()):
			if _manhattan(out[i], from) < _manhattan(out[best], from):
				best = i
		sorted.append(out[best])
		out.remove_at(best)
	return sorted


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# Where the worker starts its first day: the first tile of the plot it can stand
# on, so it begins inside its own work and never has to cross a gate it has no
# way to open.
func _start_tile(world: SimWorld) -> Vector2i:
	for ty in range(PLOT_Y0, PLOT_Y1):
		for tx in range(PLOT_X0, PLOT_X1):
			if world.is_walkable(tx, ty):
				return Vector2i(tx, ty)
	return WorldLayout.spawn()


# --- 2. one busy actor against eight -------------------------------------------

# The same world and the same tick budget, with `count` bots on it. `config` is
# empty for the floor run, which is the farm's own cost: the hen thinking, the
# clock turning, and nothing else.
func _fleet_run(count: int, config: String) -> Dictionary:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(SEED)
	var world := SimWorld.new()
	world.generate()

	# A clean patch to orbit in, and the owner standing still in the middle of
	# it. She is where she is put here rather than where she spawns: a ring drawn
	# round the yard would run half of it into the map border.
	for dy in range(-SCALE_CLEAR, SCALE_CLEAR + 1):
		for dx in range(-SCALE_CLEAR, SCALE_CLEAR + 1):
			world.set_tile_state(SCALE_CENTRE.x + dx, SCALE_CENTRE.y + dy, "cleared")
	world.set_actor_pos(SimWorld.ACTOR_PLAYER, SCALE_CENTRE)

	var ring := BotBrain.ring_tiles(SCALE_CENTRE, SCALE_ORBIT)
	var stride := ring.size() / maxi(count, 1)
	for i in count:
		BotBrain.deploy(world, "bot_%d" % i, config, ring[(i * stride) % ring.size()],
			{ "radius": SCALE_ORBIT if config == BotBrain.CONFIG_CIRCLE else BotBrain.SHOO_RADIUS })

	var t0 := Time.get_ticks_usec()
	var taken := world.advance_ticks(SCALE_TICKS, gs)
	var elapsed := (Time.get_ticks_usec() - t0) / 1000000.0

	var moved := 0
	for i in count:
		moved += 1 if world.actor_pos("bot_%d" % i) != ring[(i * stride) % ring.size()] else 0
	# A fleet on a fixed-period orbit can lap back to its exact start on the
	# final tick — at the 2026-09-07 speed (0.2 tiles/tick, 5 ticks a tile) a
	# 16-tile ring is an 80-tick lap and 10,000 ticks is exactly 125 of them,
	# which read here as "the fleet did not move". A second look a prime number
	# of ticks later (outside the timed window, so the measurement is untouched)
	# tells a finished marathon from a frozen fleet.
	if moved == 0 and count > 0 and config == BotBrain.CONFIG_CIRCLE:
		world.advance_ticks(7, gs)
		for i in count:
			moved += 1 if world.actor_pos("bot_%d" % i) != ring[(i * stride) % ring.size()] else 0
	gs.free()
	return { "count": count, "config": config, "elapsed": elapsed,
		"actions": taken.size(), "moved": moved }


# --- the report ----------------------------------------------------------------

func _report(work: Dictionary, idle: Dictionary, one: Dictionary, many: Dictionary,
		parked: Dictionary) -> int:
	var elapsed: float = work["elapsed"]
	var actions: int = work["actions"]
	var travel: int = work["travel_ticks"]
	var days_per_sec := DAYS / elapsed
	var x_realtime := days_per_sec * NOMINAL_DAY_SECONDS
	var ticks: int = int(work["end_tick"])
	var sim_seconds := float(ticks) / float(SimClock.RATE)
	# The headline, and the one the floor is judged on: work simulated per second
	# of wall clock. See FLOOR_TICKS_PER_SEC for why it is not x-realtime.
	var ticks_per_sec := float(ticks) / elapsed

	print("=== Sim fast-forward benchmark (travel modelled — M2.5 WI-12) ===")
	print("days simulated:     %d" % DAYS)
	print("actions applied:    %d" % actions)
	print("tiles walked:       %d (%d ticks of travel)" % [work["tiles_walked"], travel])
	print("unreachable tiles:  %d" % work["unreachable"])
	print("elapsed:            %.3f s" % elapsed)
	print("days/sec:           %.1f" % days_per_sec)
	print("actions/sec:        %.0f" % (actions / elapsed))
	print("actions/travel tick:%.3f (%.1f ticks of walking per action)"
		% [float(actions) / maxf(1.0, float(travel)), float(travel) / float(actions)])
	print("sim time advanced:  %.0f s in %.3f s wall" % [sim_seconds, elapsed])
	print("throughput:         %.0f ticks/sec (%d ticks simulated)"
		% [ticks_per_sec, ticks])
	# Kept for continuity with every figure recorded in ROADMAP.md before
	# 2026-09-19, and labelled so nobody reads a verdict into it: its denominator
	# is a nominal day, so it moves whenever a species' walking speed moves.
	print("x-realtime:         %.0fx (context only — moves with walking speeds)"
		% x_realtime)

	# Ground rule 8, as a slope. The floor is what the farm costs with nobody on
	# it but the hen; the interesting number is what each *additional* busy actor
	# costs, which is the difference over the floor rather than the total.
	var floor_ms: float = idle["elapsed"]
	var one_over := maxf(one["elapsed"] - floor_ms, 0.000001)
	var many_over := maxf(many["elapsed"] - floor_ms, 0.000001)
	print("\n--- per-tick cost vs. active actors (%d ticks each, sequential runs) ---"
		% SCALE_TICKS)
	print("0 bots (farm floor):  %.3f s" % floor_ms)
	print("1 circle bot:         %.3f s  (+%.3f s over the floor)"
		% [one["elapsed"], one["elapsed"] - floor_ms])
	print("%d circle bots:        %.3f s  (+%.3f s over the floor)"
		% [SCALE_FLEET, many["elapsed"], many["elapsed"] - floor_ms])
	print("%d idle shoo bots:     %.3f s  (a parked fleet, %d Actions)"
		% [SCALE_FLEET, parked["elapsed"], parked["actions"]])
	print("ratio, total:         %.2fx for %dx the actors" % [
		many["elapsed"] / maxf(one["elapsed"], 0.000001), SCALE_FLEET])
	print("ratio, actor work:    %.2fx (cost over the floor, %dx the actors)" % [
		many_over / one_over, SCALE_FLEET])

	# --- the verdicts -----------------------------------------------------------
	var travelled: bool = travel > 0 and int(work["tiles_walked"]) > 0
	var worked: bool = actions > 0 and int(work["unreachable"]) == 0
	var orbiting: bool = int(many["moved"]) == SCALE_FLEET and int(one["moved"]) == 1
	print("\ntravel modelled:    %s (%d tiles walked, %.1f ticks per action)"
		% ["yes" if travelled else "NO", work["tiles_walked"],
			float(travel) / float(maxi(actions, 1))])

	# The frame budget, worked out in the open so a reader can check it rather
	# than take it. `budget` is what one tick of the sim may cost on this machine
	# for the worst frame the live game can ask for to still fit on the tablet.
	var budget_usec := FRAME_SECONDS * SIM_SHARE_OF_FRAME \
		/ float(SimClock.MAX_TICKS_PER_FRAME) / DEVICE_FACTOR * 1000000.0
	var busy_usec: float = many["elapsed"] / float(SCALE_TICKS) * 1000000.0
	var parked_usec: float = parked["elapsed"] / float(SCALE_TICKS) * 1000000.0
	var within_budget: bool = busy_usec <= budget_usec
	print("regression floor (>=%d ticks/sec):  %s (%.0f ticks/sec)"
		% [int(FLOOR_TICKS_PER_SEC),
			"PASS" if ticks_per_sec >= FLOOR_TICKS_PER_SEC else "FAIL", ticks_per_sec])
	print("frame budget (<=%.0f us/tick, %s):  %s (%.0f us/tick)"
		% [budget_usec, BUDGET_SUBJECT, "PASS" if within_budget else "FAIL", busy_usec])
	print("  the worst frame it stands for: %d ticks at once = %.2f ms here, %.2f ms on a tablet %dx slower, against %.2f ms of a 60 fps frame"
		% [SimClock.MAX_TICKS_PER_FRAME,
			busy_usec * SimClock.MAX_TICKS_PER_FRAME / 1000.0,
			busy_usec * SimClock.MAX_TICKS_PER_FRAME * DEVICE_FACTOR / 1000.0,
			int(DEVICE_FACTOR), FRAME_SECONDS * 1000.0])
	print("  a parked fleet, for reference: %.0f us/tick (%s the same budget — not the verdict, no shoo bot ships)"
		% [parked_usec, "within" if parked_usec <= budget_usec else "OVER"])

	var failures: Array[String] = []
	if not travelled:
		failures.append("nothing walked anywhere — the worker is teleporting again")
	if not worked:
		failures.append("the day's work did not happen (%d actions, %d tiles unreachable)"
			% [actions, work["unreachable"]])
	if not orbiting:
		failures.append("the fleet did not move, so the scaling run measured nothing")
	if ticks_per_sec < FLOOR_TICKS_PER_SEC:
		failures.append("%.0f ticks/sec is under the %d ticks/sec regression floor"
			% [ticks_per_sec, int(FLOOR_TICKS_PER_SEC)])
	# The frame budget deliberately does not join this list. It is an absolute
	# wall-clock figure, so on CI's shared cloud runner it would fail for reasons
	# that have nothing to do with the code — the same argument that keeps the
	# floor crude. It is judged where the machine is known: HQ's Engineering page,
	# which runs this on the desktop and shows the verdict.
	for f in failures:
		printerr("BENCHMARK FAILED: %s" % f)
	return 1 if not failures.is_empty() else 0

# pretrain_mk3.gd — The studio's starting brain for the Mark III, trained before it ships (Q-128)
#
# Run:
#   godot --headless --path . --script res://tools/pretrain_mk3.gd                 # train and write (about two minutes)
#   godot --headless --path . --script res://tools/pretrain_mk3.gd -- --evaluate   # the shipped brain on held-out farms
#   godot --headless --path . --script res://tools/pretrain_mk3.gd -- --choose --mode=average --judge=24
#                                                     # one way to train, on the choosing farms (--mode=blank for scale)
#
# `--evaluate` plays 24 farms four ways and three arms each (about six minutes);
# `--only=<part of a heading>` or `--only=swap` plays one table of it.
#
# Daniel ruled on Q-128 that a bigger brain waits until a pretrained starting
# brain exists — "Let's add an option now to upgrade to use a pretrained model."
# This file is that starting brain's whole pipeline: it trains one, writes it
# under `assets/brains/`, and then measures it on farms it never saw.
#
# **What "pretrained" means here, in v1.** The Mark III's mind is one linear
# softmax with fixed inputs (`Policy`, `Observation`). The starting brain is
# those same weights, learned in advance: a blank robot is set down on each of
# 96 generated farms and plays a week there, with the exact nightly update a
# robot runs on her farm (`BotBrain._sleep_on_it`, the day-size charge of S-26
# included), and the brain is the average of the 96 robots it ends with. Nothing about the
# robot's shape changes and nothing extra runs on the tablet, so the on-device
# budget in `ARCHITECTURE.md` is untouched — this is the first and weakest
# version of that file's "frozen base", with nothing frozen yet: the nights go on
# changing every weight, as they do for a robot that started blank.
#
# **The farms are varied on purpose.** The demo's week (`demo_learning_robot.gd`)
# stages the same field on every seed: the same sown block, the same ripe row,
# the robot set down on the same square — the seed only changes the meadow around
# it and the draws. A brain trained on that one field could learn "walk to
# (18, 9)", which is worth nothing on her farm. So every training farm here has
# its own layout drawn from its seed: where the sown block is and how big, where
# the ripe row is, where the robot is set down, and on half of them the robot is
# given two-thirds of the block as its squares (S-26). The robot sees its own
# position and the direction of the bin, so a layout that never moved would be a
# layout it could memorise.
#
# **Three disjoint sets of seeds.** Training farms, farms the training method was
# chosen on, and held-out farms the result is reported on. None of them is the
# learning gate's eight (`LearningRobot.GATE_SEEDS`) or the demo's two dozen,
# which run from `LearningRobot.SEED` up.
#
# **Determinism.** Everything is a function of the seeds and the code: the same
# run writes the same weights, and so the same file name, since the file is
# named after the hash of its weights (`StarterBrains`). The unit suite trains a
# tiny brain twice and checks exactly that (`test_starter_brain`).
extends SceneTree

const LearningRobot := preload("res://tools/demo_learning_robot.gd")

# The three sets of farms. Far from the demo's seeds (20260909 upward) and from
# each other, so no farm is ever in two of them.
const TRAIN_BASE := 41000000
const CHOOSE_BASE := 42000000
const HELD_OUT_BASE := 43000000

# The draws a layout is made from, under their own salt (`_pick`).
const LAYOUT_SALT := 128128

# **How the shipped brain is trained: the average** (`MODE_AVERAGE`). Every
# training farm trains its own robot from blank for a week, and the brain is the
# mean of their weights. Chosen on the choosing farms by the rule written down
# before the runs — the best whole first week, learning — though every method
# but one landed within half a point of the others and of a blank robot. The
# table is in `docs/design/06-bots-and-training.md` ("A starting brain from the
# studio"); `--choose` reprints any row of it.
const MODE_AVERAGE := "average"
# One robot carried from farm to farm, a week on each. **It collapses**: after a
# few dozen farms it is deciding every second of the day (300 decisions where a
# blank robot makes about 110), never waits, and on new farms earns almost nothing.
const MODE_SEQUENTIAL := "sequential"
# Rounds: a batch of farms each plays a week from the shared brain, and the
# brain becomes the average of where they ended — then the next batch.
const MODE_ROUNDS := "rounds"
const MODES := [MODE_SEQUENTIAL, MODE_AVERAGE, MODE_ROUNDS]
const ROUND_BATCH := 8

# The shipped configuration: 96 farms, a week each. About two minutes.
const TRAIN_FARMS := 96
const DAYS := 7

# How many farms the choice and the report are made over.
const CHOOSE_FARMS := 12
const HELD_OUT_FARMS := 24

# The layout's bounds: the demo's cleared plot, and the sizes a sown block and a
# ripe row may take inside it.
const BLOCK_W := [3, 7]
const BLOCK_H := [2, 4]
const RIPE_W := [2, 5]

# The share of training farms on which the robot is given squares (S-26).
const ASSIGNED_EVERY := 2


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var code := 0
	if "--choose" in args:
		code = _choose()
	elif "--evaluate" in args:
		code = _evaluate(StarterBrains.current(StarterBrains.MK3), _arg_int(args, "--farms", HELD_OUT_FARMS),
			_arg_str(args, "--only", ""))
	else:
		var farms := _arg_int(args, "--farms", TRAIN_FARMS)
		var brain := train(MODE_AVERAGE, seeds_from(TRAIN_BASE, farms), DAYS)
		var sha := write(brain, MODE_AVERAGE, farms)
		print("Trained on %d farms; their last quarter averaged %.1f points a day."
			% [farms, float(brain["tail_score"])])
		print("Wrote %s" % StarterBrains.path_of(StarterBrains.MK3, sha))
		print("To ship it, set StarterBrains.CURRENT[MK3] to \"%s\", then run --evaluate." % sha)
	quit(code)


static func _arg_int(args: PackedStringArray, name: String, fallback: int) -> int:
	for a in args:
		if a.begins_with(name + "="):
			return int(a.get_slice("=", 1))
	return fallback


static func _arg_str(args: PackedStringArray, name: String, fallback: String) -> String:
	for a in args:
		if a.begins_with(name + "="):
			return a.get_slice("=", 1)
	return fallback


static func seeds_from(base: int, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(base + i)
	return out


# --- the farms ------------------------------------------------------------------

# One draw in [lo, hi] for this farm: FNV-1a over the seed and the draw's number
# (`Policy.salt_of`), so a layout depends on nothing but its farm's seed — not on
# `SimRng`'s global seed, which is whatever the last farm left it at.
static func _pick(farm_seed: int, k: int, lo: int, hi: int) -> int:
	return lo + Policy.salt_of("layout:%d:%d:%d" % [LAYOUT_SALT, farm_seed, k]) % (hi - lo + 1)


# The demo's own field: the layout every gate and table has been measured on.
static func canonical_layout() -> Dictionary:
	var mine: Array = []
	for y in range(LearningRobot.MINE.position.y, LearningRobot.MINE.end.y):
		for x in range(LearningRobot.MINE.position.x, LearningRobot.MINE.end.x):
			mine.append(Vector2i(x, y))
	return { "block": LearningRobot.BLOCK, "ripe": LearningRobot.RIPE,
		"spot": LearningRobot.SPOT, "mine": mine }


# A field of this farm's own: a sown block, a ripe row clear of it, and a square to
# set the robot down on that is on neither and not right beside the block. All
# inside the demo's cleared plot, so the rest of the staging is the demo's.
static func random_layout(farm_seed: int) -> Dictionary:
	var plot: Rect2i = LearningRobot.PLOT
	var bw := _pick(farm_seed, 1, BLOCK_W[0], BLOCK_W[1])
	var bh := _pick(farm_seed, 2, BLOCK_H[0], BLOCK_H[1])
	var block := Rect2i(_pick(farm_seed, 3, plot.position.x, plot.end.x - bw),
		_pick(farm_seed, 4, plot.position.y, plot.end.y - bh), bw, bh)
	var ripe := Rect2i()
	var k := 10
	while true:
		var rw := _pick(farm_seed, k, RIPE_W[0], RIPE_W[1])
		ripe = Rect2i(_pick(farm_seed, k + 1, plot.position.x, plot.end.x - rw),
			_pick(farm_seed, k + 2, plot.position.y, plot.end.y - 1), rw, 1)
		k += 3
		if not ripe.grow(1).intersects(block):
			break
	var spot := Vector2i()
	while true:
		spot = Vector2i(_pick(farm_seed, k, plot.position.x, plot.end.x - 1),
			_pick(farm_seed, k + 1, plot.position.y, plot.end.y - 1))
		k += 2
		if not block.grow(2).has_point(spot) and not ripe.grow(1).has_point(spot):
			break
	# Its squares, when it is given some: the block from the west, column by
	# column, up to two-thirds of it and never more than one robot can hold — the
	# demo's `MINE` is this rule applied to its own block.
	var mine: Array = []
	var cap := mini(BotBrain.ASSIGN_LIMIT, maxi(1, (bw * bh * 2) / 3))
	for x in range(block.position.x, block.end.x):
		for y in range(block.position.y, block.end.y):
			if mine.size() < cap:
				mine.append(Vector2i(x, y))
	return { "block": block, "ripe": ripe, "spot": spot, "mine": mine }


# The demo's staging with this layout's block, ripe row and robot square.
static func _stage(world: SimWorld, gs, layout: Dictionary) -> void:
	var plot: Rect2i = LearningRobot.PLOT
	for y in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			world.set_tile_state(x, y, "cleared")
			world.set_object(x, y, "")
	var block: Rect2i = layout["block"]
	for y in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			world.set_tile_state(x, y, "seeded", LearningRobot.CROP)
			world.get_tile(x, y).watered_today = false
	var ripe: Rect2i = layout["ripe"]
	for y in range(ripe.position.y, ripe.end.y):
		for x in range(ripe.position.x, ripe.end.x):
			world.set_tile_state(x, y, "ready", LearningRobot.CROP)
			world.get_tile(x, y).watered_today = false
	gs.pouch[LearningRobot.CROP] = LearningRobot.SEED_STOCK
	gs.day = LearningRobot.START_DAY
	gs.harvest_counts[LearningRobot.CROP] = maxi(1, int(gs.harvest_counts.get(LearningRobot.CROP, 0)))
	for raw in world.actors:
		var id := String(raw)
		if id == SimWorld.ACTOR_PLAYER:
			continue
		if plot.has_point(world.actor_pos(id)):
			world.set_actor_pos(id, LearningRobot.PARKING)


# A farm with a Mark III bought and set down on it, and given its squares when
# `assign` is on. Bought and placed through the gateway, exactly as the demo does.
static func farm(farm_seed: int, layout: Dictionary, assign: bool) -> Dictionary:
	var gs = load("res://systems/game_state.gd").new()
	gs.reset()
	SimRng.reseed(farm_seed)
	var world := SimWorld.new()
	world.generate()
	Observation.forget_bin()
	_stage(world, gs, layout)
	gs.gold = LearningRobot.PURSE
	world.earn(SimWorld.RUNG_MK2_WORKED)
	world.earn(SimWorld.RUNG_DESK_PLACED)
	world.apply_action({ "verb": "buy_machine", "item": "bot_mk3", "actor": "player" }, gs)
	var placed: Dictionary = world.apply_action({ "verb": "place", "target": layout["spot"],
		"item": "bot_mk3", "actor": "player" }, gs)
	var robot := String(placed.get("machine", ""))
	if robot != "" and assign:
		var flat: Array = []
		for t in layout["mine"]:
			flat.append(t.x)
			flat.append(t.y)
		world.apply_action({ "verb": "assign_tiles", "target": layout["mine"][0],
			"machine": robot, "tiles": flat, "actor": "player" }, gs)
	return { "gs": gs, "world": world, "robot": robot }


# One day, a second at a time, closed with the night — `measure_wider_view`'s day,
# which is the demo's. With `learn` off the night still runs and its weights are
# put back, which is the demo's control.
static func play_day(f: Dictionary, learn := true) -> float:
	var gs = f["gs"]
	var world: SimWorld = f["world"]
	var robot: String = f["robot"]
	var extra: Dictionary = world.actor(robot)["extra"]
	var kept: Array = (extra["weights"] as Array).duplicate()
	gs.actions_today = 0
	gs.crow_schedule = SimWorld.roll_crow_schedule(gs.play_day())
	gs.pouch[LearningRobot.CROP] = LearningRobot.SEED_STOCK
	for second in LearningRobot.DAY_SECONDS:
		gs.actions_today = (second * LearningRobot.DAY_ACTIONS) / LearningRobot.DAY_SECONDS
		world._send_due_crows(gs)
		world.advance_to_tick(world.clock.tick + SimClock.RATE, gs)
	var score := float(world.actor(robot)["extra"].get("score", 0.0))
	gs.weather = LearningRobot.WEATHER
	world.apply_action({ "verb": "sleep", "actor": "world", "weather": LearningRobot.WEATHER }, gs)
	if not learn:
		world.actor(robot)["extra"]["weights"] = kept
	return score


# The part of a robot a training run carries from one farm to the next.
static func brain_of(extra: Dictionary) -> Dictionary:
	return { "weights": (extra["weights"] as Array).duplicate(),
		"baseline": float(extra.get("baseline", 0.0)), "days": int(extra.get("days", 0)) }


# ...and putting it into a robot that has just been set down. A tool writing a
# robot's `extra` is staging, like the demo's field; the game's own way in is the
# shelf's `buy_upgrade` Action, which the evaluation uses.
static func give(f: Dictionary, brain: Dictionary) -> void:
	var extra: Dictionary = f["world"].actor(f["robot"])["extra"]
	extra["weights"] = (brain["weights"] as Array).duplicate()
	extra["baseline"] = float(brain.get("baseline", 0.0))
	extra["days"] = int(brain.get("days", 0))


# A workbench bought and set down in the yard, through the gateway, so the shelf's
# Action can be used at it. The first yard square with room for it, found the way
# the unit suite's `_yard_square` finds one. Returns the bench's square.
static func add_bench(f: Dictionary) -> Vector2i:
	var world: SimWorld = f["world"]
	for ty in range(1, WorldLayout.PAGE_ROWS - 1):
		for tx in range(1, SimWorld.MAP_WIDTH - 2):
			var here := Vector2i(tx, ty)
			if String(world.get_tile(tx, ty).get("state", "")) != WorldLayout.YARD:
				continue
			if world.get_object(tx, ty) != "" or world.get_object(tx, ty - 1) != "":
				continue
			if not world.placeable_at(here) or not world.placeable_at(here + Vector2i(1, 0)):
				continue
			world.apply_action({ "verb": "buy_machine", "item": "workbench", "actor": "player" }, f["gs"])
			var placed: Dictionary = world.apply_action({ "verb": "place", "target": here,
				"item": "workbench", "actor": "player" }, f["gs"])
			if placed.get("ok", false):
				return here
	return Vector2i(-1, -1)


# --- training ---------------------------------------------------------------------

# The layout and the assignment of training farm `i`.
static func _training_farm(farm_seed: int, i: int) -> Dictionary:
	return farm(farm_seed, random_layout(farm_seed), i % ASSIGNED_EVERY == 1)


# One week on one farm from `brain` (blank if empty). Returns the robot as it
# ended and the week's scores.
static func _week_from(farm_seed: int, i: int, brain: Dictionary, days: int) -> Dictionary:
	var f := _training_farm(farm_seed, i)
	if not brain.is_empty():
		give(f, brain)
	var scores: Array = []
	for _d in days:
		scores.append(play_day(f))
	var out := { "brain": brain_of(f["world"].actor(f["robot"])["extra"]), "scores": scores }
	f["gs"].free()
	return out


# The mean of several robots' weights, rounded as every weight is.
static func _average(brains: Array) -> Dictionary:
	var n := float(brains.size())
	var w: Array = []
	w.resize((brains[0]["weights"] as Array).size())
	w.fill(0.0)
	var baseline := 0.0
	var days := 0
	for b in brains:
		Policy.add_into(w, b["weights"], 1.0 / n)
		baseline += float(b["baseline"]) / n
		days = maxi(days, int(b["days"]))
	for i in w.size():
		w[i] = Policy.round6(float(w[i]))
	return { "weights": w, "baseline": Policy.round6(baseline), "days": days }


# Train a starting brain on `seeds`, `days` a farm. Returns the brain and the mean
# day score over the last quarter of the farms it was trained on.
static func train(mode: String, seeds: Array, days: int) -> Dictionary:
	var brain := {}
	var tail: Array = []
	var tail_from := (seeds.size() * 3) / 4
	match mode:
		MODE_SEQUENTIAL:
			for i in seeds.size():
				var wk := _week_from(int(seeds[i]), i, brain, days)
				brain = wk["brain"]
				if i >= tail_from:
					tail.append(LearningRobot.mean_of_days(wk["scores"], 1, days))
		MODE_AVERAGE:
			var ends: Array = []
			for i in seeds.size():
				var wk := _week_from(int(seeds[i]), i, {}, days)
				ends.append(wk["brain"])
				if i >= tail_from:
					tail.append(LearningRobot.mean_of_days(wk["scores"], 1, days))
			brain = _average(ends)
		MODE_ROUNDS:
			var i := 0
			while i < seeds.size():
				var ends: Array = []
				for j in range(i, mini(i + ROUND_BATCH, seeds.size())):
					var wk := _week_from(int(seeds[j]), j, brain, days)
					ends.append(wk["brain"])
					if j >= tail_from:
						tail.append(LearningRobot.mean_of_days(wk["scores"], 1, days))
				brain = _average(ends)
				i += ROUND_BATCH
	brain["tail_score"] = LearningRobot.mean_of_days(tail, 1, tail.size())
	return brain


# Write the brain as a file named after its weights, with where it came from.
# Returns the hash.
static func write(brain: Dictionary, mode: String, farms: int) -> String:
	var spec := Observation.spec_default()
	var n_in := Observation.size(spec)
	var micros := StarterBrains.to_micros(brain["weights"])
	var sha := StarterBrains.hash_of(StarterBrains.MK3, n_in, BotBrain.LEARN_ACTIONS, micros)
	var commit := []
	OS.execute("git", ["rev-parse", "--short=12", "HEAD"], commit)
	var data := {
		"format": StarterBrains.FORMAT,
		"key": StarterBrains.MK3,
		"sha": sha,
		"n_in": n_in,
		"n_out": BotBrain.LEARN_ACTIONS,
		"spec": spec,
		# What the robot expects a day to be worth when it starts from this brain:
		# the running mean of the training robot's days. Installed with the weights
		# so its first night is measured against what this brain usually earns.
		"baseline": float(brain.get("baseline", 0.0)),
		"provenance": {
			"tool": "tools/pretrain_mk3.gd",
			"mode": mode,
			"farms": farms,
			"days_per_farm": DAYS,
			"seeds": "%d to %d" % [TRAIN_BASE, TRAIN_BASE + farms - 1],
			"layouts": "random per farm (random_layout); squares given on every second farm",
			"learn_rate": BotBrain.LEARN_RATE,
			"day_ref": BotBrain.LEARN_DAY_REF,
			"reward_table": Rewards.TABLE,
			"last_quarter_points_a_day": Policy.round6(float(brain.get("tail_score", 0.0))),
			"commit": String(commit[0]).strip_edges() if not commit.is_empty() else "",
			"godot": Engine.get_version_info().get("string", ""),
		},
		"weights_micros": micros,
	}
	var path := ProjectSettings.globalize_path(StarterBrains.path_of(StarterBrains.MK3, sha))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false) + "\n")
	f.close()
	return sha


# --- evaluation -------------------------------------------------------------------

# The four kinds of farm the brain is judged on: the demo's field and a field of
# the farm's own, each on open ground and with squares given.
const CONDITIONS := [
	{ "name": "demo field, open ground", "random": false, "assign": false },
	{ "name": "demo field, her squares", "random": false, "assign": true },
	{ "name": "own field, open ground", "random": true, "assign": false },
	{ "name": "own field, her squares", "random": true, "assign": true },
]

# How each week is played: a blank robot learning (what she has today), the
# starting brain learning (the upgrade), and the starting brain with its nights
# switched off (to show whether learning still adds to it).
const ARM_FRESH := "blank"
const ARM_STARTER := "starting brain"
const ARM_FROZEN := "starting brain, no nights"
const ARMS := [ARM_FRESH, ARM_STARTER, ARM_FROZEN]


# One held-out week. The starting brain goes in through the real Action, so what
# is measured is what a player's purchase does.
static func eval_week(farm_seed: int, cond: Dictionary, arm: String, sha: String) -> Array:
	var layout: Dictionary = random_layout(farm_seed) if bool(cond["random"]) else canonical_layout()
	var f := farm(farm_seed, layout, bool(cond["assign"]))
	# Every arm gets the bench, so the three weeks are played on the identical farm.
	var bench := add_bench(f)
	if arm != ARM_FRESH:
		var r: Dictionary = f["world"].apply_action({ "verb": "buy_upgrade", "actor": "player",
			"target": bench, "machine": f["robot"], "item": StarterBrains.SHELF_KEY,
			"sha": sha }, f["gs"])
		if not r.get("ok", false):
			push_error("the starting brain was refused: %s" % str(r))
	var scores: Array = []
	for _d in DAYS:
		scores.append(play_day(f, arm != ARM_FROZEN))
	f["gs"].free()
	return scores


# A robot that has learned a week on its own, then either keeps going or is given
# the starting brain — the evidence for whether the upgrade should be allowed on a
# robot that has already learned.
static func swap_weeks(farm_seed: int, sha: String) -> Dictionary:
	var out := {}
	for arm in ["kept", "swapped"]:
		var f := farm(farm_seed, canonical_layout(), false)
		add_bench(f)
		for _d in DAYS:
			play_day(f)
		if arm == "swapped":
			# Not through the Action: the gateway refuses the brain to a robot that
			# has already had a night, on the strength of this very table. The same
			# function the Action calls, so what is measured is what it would do.
			BotBrain.install_brain(f["world"].actor(f["robot"])["extra"],
				StarterBrains.load_brain(StarterBrains.MK3, sha), StarterBrains.MK3, sha)
		var scores: Array = []
		for _d in DAYS:
			scores.append(play_day(f))
		out[arm] = scores
		f["gs"].free()
	return out


func _evaluate(brain: Dictionary, farms: int, only: String) -> int:
	if brain.is_empty():
		printerr("No starting brain to evaluate: StarterBrains.CURRENT names no readable file.")
		return 1
	var sha := StarterBrains.hash_of(StarterBrains.MK3, int(brain["n_in"]), int(brain["n_out"]),
		StarterBrains.to_micros(brain["weights"]))
	var seeds := seeds_from(HELD_OUT_BASE, farms)
	print("")
	print("=== The Mark III's starting brain %s on %d farms it never trained on ===" % [sha, farms])
	print("Each farm is played for a week three ways: a blank robot that learns each night")
	print("(what a Mark III is today), a robot given the starting brain that learns each night")
	print("(the upgrade), and the starting brain with its nights switched off. Points a day,")
	print("mean over the farms; \"beat blank\" counts the farms whose whole week beat the")
	print("same farm's blank week.")
	for cond in CONDITIONS:
		if only != "" and only != "swap" and not String(cond["name"]).contains(only):
			continue
		if only == "swap":
			continue
		var rows := {}
		for arm in ARMS:
			rows[arm] = []
			for s in seeds:
				rows[arm].append(eval_week(int(s), cond, arm, sha))
		print("")
		print("--- %s ---" % cond["name"])
		print("%-26s %9s %9s %9s %11s" % ["", "days 1-3", "days 5-7", "week", "beat blank"])
		for arm in ARMS:
			var early := 0.0
			var late := 0.0
			var whole := 0.0
			var beat := 0
			for k in seeds.size():
				var wk: Array = rows[arm][k]
				early += LearningRobot.mean_of_days(wk, 1, 3)
				late += LearningRobot.mean_of_days(wk, DAYS - 2, DAYS)
				var w := LearningRobot.mean_of_days(wk, 1, DAYS)
				whole += w
				if w > LearningRobot.mean_of_days(rows[ARM_FRESH][k], 1, DAYS):
					beat += 1
			var n := float(seeds.size())
			var versus := "—" if arm == ARM_FRESH else "%d / %d" % [beat, seeds.size()]
			print("%-26s %9.1f %9.1f %9.1f %11s" % [arm, early / n, late / n, whole / n, versus])
	if only == "" or only == "swap":
		var kept := 0.0
		var swapped := 0.0
		var better := 0
		for s in seeds:
			var sw := swap_weeks(int(s), sha)
			var k := LearningRobot.mean_of_days(sw["kept"], 1, DAYS)
			var w := LearningRobot.mean_of_days(sw["swapped"], 1, DAYS)
			kept += k
			swapped += w
			if w > k:
				better += 1
		print("")
		print("--- a robot that already learned a week on the demo field, second week ---")
		print("kept its own learning         %.1f points a day" % (kept / float(seeds.size())))
		print("given the starting brain      %.1f points a day (%d / %d farms better)"
			% [swapped / float(seeds.size()), better, seeds.size()])
	return 0



# --- choosing how to train --------------------------------------------------------

# A week from `brain` (blank if empty) on each choosing farm, twice — on a field
# of the farm's own, open and with squares — learning or not. Returns the mean of
# days 1-3, of days 5-7 and of the whole week.
static func _trial(brain: Dictionary, seeds: Array, learn: bool) -> Array:
	var early := 0.0
	var late := 0.0
	var whole := 0.0
	var n := 0
	for s in seeds:
		for assign in [false, true]:
			var f := farm(int(s), random_layout(int(s)), assign)
			if not brain.is_empty():
				give(f, { "weights": brain["weights"], "baseline": brain["baseline"], "days": 0 })
			var wk: Array = []
			for _d in DAYS:
				wk.append(play_day(f, learn))
			f["gs"].free()
			early += LearningRobot.mean_of_days(wk, 1, 3)
			late += LearningRobot.mean_of_days(wk, DAYS - 2, DAYS)
			whole += LearningRobot.mean_of_days(wk, 1, DAYS)
			n += 1
	return [early / n, late / n, whole / n]


# One way to train, judged on the choosing farms by what a robot given its brain
# earns in its first week, with its nights and without. `--mode=blank` prints the
# blank robot on the same farms, for scale.
func _choose() -> int:
	var args := OS.get_cmdline_user_args()
	var farms := _arg_int(args, "--farms", 48)
	var days := _arg_int(args, "--days", DAYS)
	var count := _arg_int(args, "--judge", CHOOSE_FARMS)
	var mode := _arg_str(args, "--mode", MODE_SEQUENTIAL)
	var seeds := seeds_from(CHOOSE_BASE, count)
	var line := "%-34s %8s %9s %9s %9s"
	if mode == "blank":
		for learn in [true, false]:
			var b := _trial({}, seeds, learn)
			print(line % ["blank, " + ("learning" if learn else "no nights"), "",
				"%.1f" % b[0], "%.1f" % b[1], "%.1f" % b[2]])
		return 0
	var brain := train(mode, seeds_from(TRAIN_BASE, farms), days)
	var label := "%s %dx%d" % [mode, farms, days]
	if "--no-position" in args:
		brain = forget_position(brain)
		label += " no-pos"
	for learn in [true, false]:
		var r := _trial(brain, seeds, learn)
		print(line % [label + (", learning" if learn else ", no nights"),
			"%.1f" % float(brain["tail_score"]), "%.1f" % r[0], "%.1f" % r[1], "%.1f" % r[2]])
	return 0


# The brain with what it learned about *where on the map* it stands wiped: the two
# weights per action on the robot's own position. Every other input is about the
# robot or what is around it, and means the same on any farm; the position means
# "this farm's layout", which is the one thing a farm it has never seen does not share.
static func forget_position(brain: Dictionary) -> Dictionary:
	var out := brain.duplicate(true)
	var n_in := Observation.size(Observation.spec_default())
	var w: Array = out["weights"]
	for j in BotBrain.LEARN_ACTIONS:
		w[j * (n_in + 1)] = 0.0
		w[j * (n_in + 1) + 1] = 0.0
	return out

# generated_games.gd — Many generated games, each checked against its own replay
#
# Daniel's question (2026-10-09): can we make new games and check they replay
# exactly? This is the answer. Each game is a generated farm on its own seed,
# played by a random but legal player for a few days, recorded the way the live
# game records a session, and checked the way `tools/verify_replay.gd` checks a
# tablet session: at every save, the recording is replayed into a fresh world and
# the result has to be the save, exactly.
#
# **Why at sim level and not through the real game.** Every replay break play has
# found so far lived in the sim, the save or the recording rules — a refused robot
# action (cc288db9), a save that forgot where the farm's dice had got to
# (c09dfb16), a barn that could not load (d8f66ca5) — and none in drawing or
# input. The robot session already drives the real game end to end once; this
# plays dozens of games in the time that one takes, which is what finding the
# next break needs. The recording here mirrors `world/farm.gd` line for line
# (`apply_action`, `advance_sim`, `note_player_walk`), and a Continue mirrors
# `main.gd`'s, so a game here is a session the real game could have recorded.
#
# **The player's choices come from her own dice**, a `RandomNumberGenerator`
# seeded from the game's seed, never from `SimRng`: the replay does not run the
# player, so anything she drew from the farm's stream would be a draw the replay
# never makes.
#
# What a game can contain, all of it chosen by the seed: a fresh farm through the
# cold open, or one staged the way the robot session stages its farm (a purse, the
# robot ladder climbed, the barn unlocked) and rebased; tilling, planting,
# watering, harvesting, clearing, selling, refilling; buying and placing every
# machine in the shop, the barn and its cows, a mark-1 taught a round and sent, a
# Mark III given squares, tuned, paced and set to practise on worms; doors; walks;
# nights; actions the gateway refuses; and saving part-way through the day or at
# night, then going on from the save on disk the way the Continue button does.
extends RefCounted

const GameStateScript := preload("res://systems/game_state.gd")

# The seeds CI plays. Fixed so a push never goes red from luck (Daniel's rule:
# routine work must not turn the suite red with a newly found failure). Add a seed
# here when a random run finds a break worth keeping; never take one out to make
# the suite pass.
const FIXED_SEEDS: Array[int] = [
	# Picked on 2026-10-09 from 150 random games so that between them they reach
	# everything that has broken before: a Mark III given squares, tuned, paced,
	# sold the starter brain and set to practise; a mark-1 taught and sent; hens
	# laying and refused; crows; worms; a barn's cows making cheese; nights; and
	# Continue mid-day and in the morning.
	916611627, 765668099, 937296070, 643819335, 1102423728, 1192673136,
	1432438107, 1049957844, 922372480, 762069975, 743160575, 865559722,
	1523783905, 1158924694,
	# Two more that reach the workbench's shelf and buy a Mark III the starter
	# brain (from 300 random games; worm practice and pace were still reached by
	# 922372480 alone).
	1725051930, 1635315767,
	# Each of these caught a break when it was put back on purpose (the PR that
	# added this file lists which): a Mark III sowing a different seed when two
	# kinds were tied in her box —
	968703266,
	# — and a planted egg that half-changed a square and stopped the gateway.
	1964907053, 218902606,
	# The first list, kept: cheap, and every seed is a different farm.
	101, 202, 303, 404, 505, 606, 707, 808, 909, 1010, 1111, 1212,
]

# How many days a game lasts, at most; the seed picks within it.
const MAX_DAYS := 4
const MIN_DAYS := 2
# A day is this many of her choices; a choice is an action, a walk, or a stretch
# of sim time passing. The seed picks within it.
const MIN_STEPS := 40
const MAX_STEPS := 90
# The longest single stretch of sim time between two of her choices, in ticks
# (`SimClock.RATE` ticks a second).
const MAX_WAIT_TICKS := 300

# The folder a game writes its save and recording into, like a save slot. Kept
# after a failure so `tools/verify_replay.gd -- <folder>` can be pointed at it.
const ROOT := "user://generated_games"


# One game in progress: the live farm, its recording, and her dice.
class Game:
	var seed_value: int
	var world: SimWorld
	var gs
	var log: ReplayLog
	var rng := RandomNumberGenerator.new()
	var dir: String
	var save_path: String
	var replay_path: String
	# What happened, for the report and for deciding the game covered something.
	var notes: Array[String] = []
	var counts := {}
	# How the recording now being written began: on a fresh farm, from the save on
	# disk (Continue), or from a save of the farm in memory (rebase).
	var segment := "a fresh farm"
	# A break put in on purpose, so the unit suite can show this check catches one
	# (`persistence_tests.gd`): "" plays honestly; "unrecorded_action" leaves one
	# of her successful actions out of the recording; "dice_not_saved" continues a
	# farm from the start of its seed's stream, as the game did before c09dfb16;
	# "replay_draws_extra" has every replay draw one more number than the game did.
	var plant := ""
	var planted := false

	func _init(s: int) -> void:
		seed_value = s
		rng.seed = hash("generated game %d" % s)
		dir = ROOT.path_join(str(s))
		save_path = dir.path_join(SaveSlots.SAVE_FILE)
		replay_path = dir.path_join(SaveSlots.REPLAY_FILE)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for path in [save_path, replay_path]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	func count(key: String, n: int = 1) -> void:
		counts[key] = int(counts.get(key, 0)) + n

	# `world/farm.gd:apply_action`: the gateway, then the recording of what it said
	# yes to, stamped with the clock as it stands after the Action resolved.
	func apply_action(action: Dictionary, _gs = null) -> Dictionary:
		var r := world.apply_action(action, gs)
		if r.get("ok", false) and plant == "unrecorded_action" and not planted \
				and String(action.get("verb", "")) == "till":
			planted = true
			return r
		if r.get("ok", false):
			log.record(action, r, world.clock.tick)
			count("ok " + String(action.get("verb", "")))
		elif String(action.get("actor", "")) == "player":
			count("refused")
		return r

	# `world/farm.gd:advance_sim`: sim time passing, and every brain decision in it
	# recorded with the tick it was made on. A hen's decision that emitted no
	# successful Action is recorded too; any other refusal is not.
	func tick(n: int) -> void:
		for taken in world.advance_ticks(n, gs):
			var action: Dictionary = taken["action"]
			if action.is_empty() or not taken["result"].get("ok", false):
				if log.record_decisions \
						and String(taken.get("actor", "")) == SimWorld.ACTOR_CHICKEN:
					log.record_brain_decision(taken)
				if not action.is_empty():
					var refused_who := String(action.get("actor", ""))
					var refused_kind := world.machine_key_of(refused_who)
					if refused_kind == "":
						refused_kind = world.species_of(refused_who)
					count("brain refused %s %s (%s)" % [refused_kind,
						action.get("verb", ""), taken["result"].get("reason", "")])
				continue
			log.record(action, taken["result"], int(taken["tick"]), true)
			count("brain " + String(action.get("verb", "")))
			var who := String(action.get("actor", ""))
			var kind := world.machine_key_of(who)
			if kind == "":
				kind = world.species_of(who)
			if kind == "" and who.begins_with("crow"):
				kind = "crow"
			if kind != "":
				count("by " + kind)

	# `world/farm.gd:note_player_walk`: her registry entry and the recording,
	# written together.
	func walk(event: String, dir_name: String, at: Vector2i) -> void:
		world.set_actor_pos(SimWorld.ACTOR_PLAYER, at, dir_name)
		log.record_walk(event, dir_name, at, world.clock.tick)
		count("walk")

	# `main.gd:persist_session`: the save and the recording, written together at
	# the same sim time. Returns the save as the file holds it.
	func persist() -> Dictionary:
		SaveGame.save_to(save_path, world, gs)
		log.mark_tick(world.clock.tick)
		log.flush_to(replay_path)
		return SaveGame.load_dict(save_path)

	# `main.gd:_ready` taking the Continue path: a new world and new game state
	# restored from the save on disk, back on the farm's own seed and its place in
	# that seed's stream, with a recording that starts from that save. Returns ""
	# or why continuing went wrong.
	func continue_from_disk() -> String:
		var save_data := SaveGame.load_dict(save_path)
		var before := SaveGame.capture_canonical(world, gs)
		var stream_at_save := SimRng.current_state()
		var world2 := SimWorld.new()
		var gs2 = GameStateScript.new()
		gs2.reset()
		if not SaveGame.restore(save_data, world2, gs2):
			gs2.free()
			return "the save would not load (Continue would have failed)"
		if world2.gen_seed != 0:
			if plant == "dice_not_saved":
				SimRng.reseed(world2.gen_seed)
			else:
				SaveGame.resume_stream(save_data, world2.gen_seed)
		var dice := _dice_after_continue(stream_at_save)
		# Continuing must not change the farm. Compared before play goes on, so a
		# save that drops something is named here rather than as a replay that
		# agrees with the damaged farm it was started from.
		var after := SaveGame.capture_canonical(world2, gs2)
		gs.free()
		world = world2
		gs = gs2
		_start_log_from(save_data)
		segment = "the save on disk (Continue), day %d tick %d" % [gs.day, world.clock.tick]
		count("continue")
		if after != before:
			return "the farm changed when it was continued from its save — first difference: %s" \
				% SaveGame._first_difference(JSON.parse_string(after), JSON.parse_string(before))
		return dice

	# ...and its dice have to come back exactly where they were, or the continued
	# farm draws different numbers from the ones it would have drawn had she never
	# quit (c09dfb16: the hen wandered somewhere else). The replay cannot catch this
	# on its own: it starts from the same save as the continued game, so it agrees
	# with whatever the save forgot.
	#
	# Not checked: that a continued farm then plays out tick for tick as the farm in
	# memory would have. It does not, on purpose — a loaded farm wakes everybody
	# once to rebuild its clock, so a hen who was mid-walk takes her next step a
	# tick or two early (`ReplayLog._decision_fingerprint` says the same).
	func _dice_after_continue(stream_at_save: String) -> String:
		if SimRng.current_state() == stream_at_save:
			return ""
		return "the farm's dice did not come back where they were when it saved " \
			+ "(saved at %s, continued at %s)" % [stream_at_save, SimRng.current_state()]

	# `tools/robot_session.gd`'s way, used once at the start of a staged game: the
	# farm goes on in memory, and the recording starts again from a save of it taken
	# now, so the staging is in the replay's starting farm.
	func rebase() -> void:
		var base = JSON.parse_string(JSON.stringify(SaveGame.capture(world, gs)))
		SaveGame.resume_stream(base, world.gen_seed)
		_start_log_from(base)
		segment = "a save of the staged farm in memory"
		count("rebase")

	func _start_log_from(save_data: Dictionary) -> void:
		log = ReplayLog.new()
		log.start_from_save(save_data, world.gen_seed)
		log.record_decisions = true
		if FileAccess.file_exists(replay_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(replay_path))

	func done() -> void:
		if gs != null:
			gs.free()
			gs = null


# Play one game and check it at every save. Returns:
# { ok, seed, failure, where, days, checks, counts, notes, dir }.
# `failure` is "" when every check matched; otherwise the first one that did not,
# in one line, and `where` says which save of the game it was.
static func play(seed_value: int, plant := "") -> Dictionary:
	var g := Game.new(seed_value)
	g.plant = plant
	var out := { "ok": true, "seed": seed_value, "failure": "", "where": "",
		"days": 0, "counts": g.counts, "notes": g.notes, "dir": g.dir }

	# A fresh farm, as `main.gd` starts one.
	Observation.forget_bin()
	g.gs = GameStateScript.new()
	g.gs.reset()
	SimRng.reseed(seed_value)
	g.world = SimWorld.new()
	g.world.generate()
	g.log = ReplayLog.new()
	g.log.start(seed_value)
	g.log.record_decisions = true

	var staged := g.rng.randf() < 0.75
	if staged:
		_stage(g)
		g.rebase()
		g.notes.append("staged farm")
	else:
		g.notes.append("fresh farm")
	# The cold open, played through the same recorder, as the robot session does.
	ColdOpen.run(g, g.world, g.gs)

	var days := g.rng.randi_range(MIN_DAYS, MAX_DAYS)
	out["days"] = days
	var checks := 0
	for day in days:
		var steps := g.rng.randi_range(MIN_STEPS, MAX_STEPS)
		# Somewhere in some days the tablet is put down: a save mid-day, and the
		# game picked up again from it (Android pauses the app; `main.gd` saves).
		var pause_at := g.rng.randi_range(0, steps - 1) if g.rng.randf() < 0.35 else -1
		for step in steps:
			_choose(g)
			if step == pause_at:
				checks += 1
				var failed := _check(g, "day %d, mid-day save" % (day + 1))
				if failed != "":
					return _fail(out, g, failed, "day %d, mid-day save (check %d)" % [day + 1, checks])
				var refused := g.continue_from_disk()
				if refused != "":
					return _fail(out, g, refused, "day %d, continued mid-day" % (day + 1))
		_go_to_bed(g)
		g.apply_action({ "verb": "sleep", "actor": "player" })
		checks += 1
		var failed := _check(g, "night %d" % (day + 1))
		if failed != "":
			return _fail(out, g, failed, "after night %d (check %d)" % [day + 1, checks])
		# Some mornings she had quit after bed and taps Continue.
		if g.rng.randf() < 0.4:
			var refused := g.continue_from_disk()
			if refused != "":
				return _fail(out, g, refused, "morning %d, continued" % (day + 2))
	# One last stretch of the farm getting on with it, then the last save.
	g.tick(g.rng.randi_range(1, MAX_WAIT_TICKS * 4))
	checks += 1
	var last := _check(g, "end")
	if last != "":
		return _fail(out, g, last, "at the end (check %d)" % checks)
	out["checks"] = checks
	g.done()
	_remove_dir(g.dir)
	return out


# `tools/verify_replay.gd`, on the files this game wrote: the recording replayed
# into a fresh world has to recompute every brain decision it recorded and land on
# the save exactly. Returns "" or the first thing that differed.
#
# **The farm's dice are the live game's, and the replay borrows them.** There is
# one `SimRng`, and `ReplayLog.apply_to` reseeds it and draws from it, so without
# putting it back the live game would carry on from wherever the replay left off.
# A replay that drew one number more or fewer than the game did would then hand
# its own position to the rest of the game, every later check would agree with
# it, and the break would never show. So the position is put back afterwards, and
# a replay that finishes anywhere other than where the game stood is a failure of
# its own — the save leaves the dice out of the comparison (`rng_state` is
# stripped from the canonical capture), so nothing else would notice.
static func _check(g: Game, _label: String) -> String:
	var save := g.persist()
	if save.is_empty():
		return "the save could not be read back"
	var rlog := ReplayLog.load_from(g.replay_path)
	if rlog == null:
		return "the recording could not be read back"
	var dice_seed := SimRng.current_seed()
	var dice_at := SimRng.current_state()
	var dice_revision := SimRng.stateless_revision
	var report := SaveGame.replay_report(rlog, save)
	if g.plant == "replay_draws_extra":
		SimRng.randi()
	var replay_dice_at := SimRng.current_state()
	SimRng.resume(dice_seed, dice_at, dice_revision)
	if report.get("matched", false):
		if replay_dice_at != dice_at:
			return ("the replay rebuilt the farm but drew a different amount from its dice " \
				+ "than the game did (the game stood at %s, the replay ended at %s)") \
				% [dice_at, replay_dice_at]
		return ""
	if not report.get("applied", false):
		return "the replay could not start: %s" % report.get("divergence", "")
	if not report.get("restored", false):
		return "the save would not load for comparison"
	if String(report.get("divergence", "")) != "":
		return "a brain decided differently on replay — %s" % report["divergence"]
	return "the replayed farm differs from the save — first difference: %s" \
		% report.get("state_difference", "")


static func _fail(out: Dictionary, g: Game, failure: String, where: String) -> Dictionary:
	out["ok"] = false
	out["failure"] = failure
	out["where"] = "%s; the recording began from %s" % [where, g.segment]
	g.done()
	return out


static func _remove_dir(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var d := DirAccess.open(abs)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(abs)


# The robot session's staging, with the seed choosing how far along the farm is.
# Done before the recording is rebased, so the replay starts from exactly this.
static func _stage(g: Game) -> void:
	g.gs.gold = g.rng.randi_range(400, 4000)
	if g.rng.randf() < 0.7:
		g.world.earn(SimWorld.RUNG_MK2_WORKED)
		g.world.earn(SimWorld.RUNG_DESK_PLACED)
		g.notes.append("robot ladder climbed")
	if g.rng.randf() < 0.6:
		g.gs.harvest_counts["egg"] = 10
		g.notes.append("barn unlocked")
	if g.rng.randf() < 0.5:
		g.world.story_nights_told[SimWorld.STORY_NIGHT_CROW] = true
		g.world.story_nights_told[SimWorld.STORY_NIGHT_ROBOT] = true
	for crop in ["wheat", "tomato", "pea"]:
		if CropDefs.is_plantable(crop):
			g.gs.pouch[crop] = int(g.gs.pouch.get(crop, 0)) + g.rng.randi_range(0, 12)


# --- her choices --------------------------------------------------------------
#
# Weighted, so a few days reach the interesting parts of the farm, and loose, so
# a good share of what she asks for is refused — which is the half of play the
# recording never sees and the replay has to agree about anyway.

static func _choose(g: Game) -> void:
	var r := g.rng.randf()
	if r < 0.30:
		g.tick(g.rng.randi_range(1, MAX_WAIT_TICKS))
	elif r < 0.45:
		_walk(g)
	elif r < 0.75:
		_work_a_square(g)
	elif r < 0.85:
		_shop(g)
	elif r < 0.97:
		_machine(g)
	else:
		_door(g)


const DIRS := { "left": Vector2i(-1, 0), "right": Vector2i(1, 0),
	"up": Vector2i(0, -1), "down": Vector2i(0, 1) }


# A few squares' walk in one direction, a crossing at a time, the way the pixel
# walker reports them.
static func _walk(g: Game) -> void:
	var names: Array = DIRS.keys()
	var dir_name: String = names[g.rng.randi_range(0, names.size() - 1)]
	var at := g.world.actor_pos(SimWorld.ACTOR_PLAYER)
	var event := "begin"
	for _i in g.rng.randi_range(1, 6):
		var next: Vector2i = at + DIRS[dir_name]
		if not g.world.is_walkable(next.x, next.y):
			break
		at = next
		g.walk(event, dir_name, at)
		event = "step"
	if event == "step":
		g.walk("stop", dir_name, at)


# A square near her, or anywhere on the farm.
static func _square(g: Game, radius := 4) -> Vector2i:
	if g.rng.randf() < 0.75:
		var p := g.world.actor_pos(SimWorld.ACTOR_PLAYER)
		return Vector2i(
			clampi(p.x + g.rng.randi_range(-radius, radius), 0, _width(g) - 1),
			clampi(p.y + g.rng.randi_range(-radius, radius), 0, _height(g) - 1))
	return Vector2i(g.rng.randi_range(0, _width(g) - 1), g.rng.randi_range(0, _height(g) - 1))


static func _width(g: Game) -> int:
	return (g.world.objects[0] as Array).size()


static func _height(g: Game) -> int:
	return g.world.objects.size()


const CLEARS := { "weed": "clear_weed", "log": "clear_log", "rock": "clear_rock",
	"tree": "clear_tree" }
const ANY_TILE_VERB := ["till", "plant", "water", "harvest", "clear_weed", "collect",
	"clear_rock", "clear_log", "clear_tree"]


# The verb the square asks for, most of the time; any verb at all the rest.
static func _work_a_square(g: Game) -> void:
	var t := _square(g)
	var tile := g.world.get_tile(t.x, t.y)
	var state := String(tile.get("state", ""))
	var obj := g.world.get_object(t.x, t.y)
	var verb := ""
	if g.rng.randf() < 0.85:
		if CLEARS.has(obj):
			verb = CLEARS[obj]
		elif obj in ["egg", "scarecrow"]:
			verb = "collect"
		elif obj == "well":
			verb = "refill"
		elif obj == "shipping_bin":
			verb = "sell"
		elif state == "cleared":
			verb = "till"
		elif state == "tilled":
			verb = "plant"
		elif state == "ready":
			verb = "harvest"
		elif state in ["seeded", "growing"]:
			verb = "water"
	if verb == "":
		verb = ANY_TILE_VERB[g.rng.randi_range(0, ANY_TILE_VERB.size() - 1)]
	var action := { "verb": verb, "target": t, "actor": "player" }
	if verb == "plant":
		action["seed_type"] = _a_seed(g)
	g.apply_action(action)


static func _a_seed(g: Game) -> String:
	var held: Array = []
	for crop in CropDefs.TYPES:
		if CropDefs.is_plantable(crop) and g.gs.held_count(crop) > 0:
			held.append(crop)
	if held.is_empty() or g.rng.randf() < 0.1:
		var all: Array = CropDefs.TYPES.keys()
		return String(all[g.rng.randi_range(0, all.size() - 1)])
	return String(held[g.rng.randi_range(0, held.size() - 1)])


# The seed box: seeds, machines, a cow — and putting down whatever she holds.
static func _shop(g: Game) -> void:
	var r := g.rng.randf()
	if r < 0.25:
		# What the seed box sells, mostly; now and then a name it does not.
		var crops: Array = CropDefs.ORDER if g.rng.randf() < 0.9 else CropDefs.TYPES.keys()
		g.apply_action({ "verb": "buy_seed", "actor": "player",
			"seed_type": String(crops[g.rng.randi_range(0, crops.size() - 1)]) })
	elif r < 0.55:
		# Half the time the next thing on the way up — a stall and a mark-1, a coop,
		# the barn, a Mark III and the bench that works on it — and the rest of the
		# time anything at all, which is mostly refused for want of gold or a rung.
		var keys: Array = MachineDefs.ORDER
		var key := String(keys[g.rng.randi_range(0, keys.size() - 1)])
		if g.rng.randf() < 0.5:
			for want in WISHLIST:
				if not _owns(g, want):
					key = want
					break
		g.apply_action({ "verb": "buy_machine", "item": key, "actor": "player" })
	elif r < 0.62:
		g.apply_action({ "verb": "buy_cow", "actor": "player" })
	else:
		_place_something(g)


# Whatever machine she is holding, set down. A robot goes into a stall bay when
# there is one; anything else is tried on a few squares until one takes, as a
# child tries a few spots before the shop's ghost turns green.
static func _place_something(g: Game) -> void:
	var held: Array = []
	for key in MachineDefs.TYPES:
		if g.gs.held_count(key) > 0:
			held.append(key)
	if held.is_empty():
		return
	var key := String(held[g.rng.randi_range(0, held.size() - 1)])
	var spots: Array[Vector2i] = []
	if key in ["bot_mk1", "bot_mk2"]:
		var stall := g.world.find_object(WorldLayout.ROBOT_STALL)
		if stall.x >= 0:
			spots.append(stall)
			spots.append(stall + Vector2i(1, 0))
	for _i in 12:
		spots.append(_square(g, 6))
	for t in spots:
		var r := g.apply_action({ "verb": "place", "target": t, "item": key,
			"actor": "player" })
		if r.get("ok", false):
			return


const WISHLIST := ["stall", "bot_mk1", "coop", "industrial_barn", "bot_mk3", "workbench",
	"sprinkler", "nest_box"]


# Whether she has one of these standing on the farm or in her hands.
static func _owns(g: Game, key: String) -> bool:
	if g.gs.held_count(key) > 0:
		return true
	if not _robots_by(g, key).is_empty():
		return true
	var obj := MachineDefs.object_of(key)
	return obj != "" and g.world.find_object(obj).x >= 0


static func _machines(g: Game) -> Array[String]:
	var out: Array[String] = []
	for raw in g.world.actors:
		var id := String(raw)
		if g.world.machine_key_of(id) != "":
			out.append(id)
	out.sort()
	return out


static func _robots_by(g: Game, key: String) -> Array[String]:
	var out: Array[String] = []
	for id in _machines(g):
		if g.world.machine_key_of(id) == key:
			out.append(id)
	return out


# Telling a machine what to do: a dial, a mark-1's round and its send, a Mark
# III's squares, its rewards, its pace and its practice.
static func _machine(g: Game) -> void:
	var all := _machines(g)
	if all.is_empty():
		_shop(g)
		return
	var id := all[g.rng.randi_range(0, all.size() - 1)]
	var key := g.world.machine_key_of(id)
	var at := g.world.actor_pos(id)
	var bench := g.world.find_object(WorldLayout.WORKBENCH)
	var r := g.rng.randf()
	match key:
		"bot_mk1":
			if r < 0.6:
				for _i in g.rng.randi_range(1, 4):
					g.apply_action({ "verb": "teach", "machine": id, "target": _square(g, 5),
						"actor": "player" })
			else:
				g.apply_action({ "verb": "activate", "target": at, "actor": "player" })
		"bot_mk3":
			if r < 0.35:
				_assign(g, id)
			elif r < 0.55:
				g.apply_action({ "verb": "tune", "target": at, "actor": "player",
					"row": String(Rewards.KEYS[g.rng.randi_range(0, Rewards.KEYS.size() - 1)]),
					"value": snappedf(g.rng.randf(), 0.25) })
			elif r < 0.75:
				var shelf: Array = ShelfDefs.ORDER
				var item := String(shelf[g.rng.randi_range(0, shelf.size() - 1)])
				var buy := { "verb": "buy_upgrade", "target": bench, "machine": id,
					"item": item, "actor": "player" }
				if item == StarterBrains.SHELF_KEY:
					buy["sha"] = String(StarterBrains.CURRENT.get(StarterBrains.MK3, ""))
				g.apply_action(buy)
			elif r < 0.85:
				var pace := g.rng.randi_range(0, BotBrain.PACE_SCALES.size() - 1)
				g.apply_action({ "verb": "buy_pace" if g.rng.randf() < 0.5 else "set_pace",
					"target": bench, "machine": id, "pace": pace, "actor": "player" })
			else:
				g.apply_action({ "verb": "practice", "machine": id, "practice": "worm",
					"on": g.rng.randf() < 0.7, "size": g.rng.randi_range(1, 8),
					"actor": "player" })
		_:
			var configs: Array = MachineDefs.configs_of(key)
			if not configs.is_empty():
				g.apply_action({ "verb": "configure", "target": at, "actor": "player",
					"config": String(configs[g.rng.randi_range(0, configs.size() - 1)]) })
			else:
				g.apply_action({ "verb": "activate", "target": at, "actor": "player" })


# A Mark III given the squares around it that a machine could work — or all of
# them taken back.
static func _assign(g: Game, id: String) -> void:
	var flat: Array = []
	if g.rng.randf() < 0.9:
		var near := g.world.actor_pos(id)
		var limit := g.rng.randi_range(1, BotBrain.ASSIGN_LIMIT)
		for _i in limit * 3:
			var t := Vector2i(near.x + g.rng.randi_range(-4, 4), near.y + g.rng.randi_range(-4, 4))
			if flat.size() / 2 >= limit:
				break
			if g.world.teachable_at(t):
				flat.append(t.x)
				flat.append(t.y)
	g.apply_action({ "verb": "assign_tiles", "target": g.world.actor_pos(id),
		"machine": id, "tiles": flat, "actor": "player" })


# Through a door: her front door from outside, the doorway from inside, or any
# room's doorway.
static func _door(g: Game) -> void:
	var doors: Array[Vector2i] = []
	for name in [WorldLayout.HOUSE_DOOR, WorldLayout.HOME_DOORWAY, WorldLayout.ROOM_DOORWAY]:
		var t := g.world.find_object(name)
		if t.x >= 0:
			doors.append(t)
	if doors.is_empty():
		return
	g.apply_action({ "verb": "use_door", "actor": "player",
		"target": doors[g.rng.randi_range(0, doors.size() - 1)] })


# Most nights she goes indoors to bed first, which is what the machines' morning
# waits on; some nights she falls asleep wherever she is.
static func _go_to_bed(g: Game) -> void:
	if g.rng.randf() < 0.3:
		return
	var p := g.world.actor_pos(SimWorld.ACTOR_PLAYER)
	if g.world.page_of(p) == 0:
		var door := g.world.find_object(WorldLayout.HOUSE_DOOR)
		if door.x >= 0:
			g.apply_action({ "verb": "use_door", "target": door, "actor": "player" })

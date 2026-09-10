# bot_brain.gd — One machine, three settings (M2.5 WI-9; `design/06`, P-8/P-9)
#
# Layer 2 (pure): no Node, no autoload, no rendering, no Input, no engine clock.
#
# **This is P-9's first inhabitant.** "Any entity may carry the full player verb
# set (S-3 guarantees the sim doesn't care who acts)" has been true since the
# gateway existed and had nobody to be true *of*; `SpeciesDefs.BOT` carries
# `PLAYER_VERBS` itself — the same array, so a verb she gains is a verb it gains
# — and this file is what decides for it. Ground rule 1's other direction comes
# free: there is no verb here the player lacks, because there is no verb list
# here at all.
#
# **One brain, three configs, because a bot line is a product line.** Which
# behaviour a bot has is `extra.config`, a string on the actor:
#
#   follow  trail the player at a couple of tiles, out from under her feet.
#   circle  orbit her at a fixed radius, stepping tile to tile.
#   shoo    hold a patch, chase birds out of it, come back.
#
# Three brains would have made them three kinds of thing and would have needed
# three species rows (a row names exactly one brain), which would have said in
# the one file a reader checks first that a farm with two settings of the same
# machine has two species on it. It has one, twice. And the config being *data on
# the actor* is what makes it savable, replayable, comparable and re-settable —
# and is the shape phase 4 replaces: P-8 has a learned policy picking **options**
# at ~1 Hz over deterministic controllers, and these three are options, written by
# hand. The first learned bot swaps `step()`'s dispatch for a policy and keeps
# everything below it.
#
# **Nothing acquires one** (Q-56, ruled 2026-08-31: the debut waits for at least
# M3 so the sprinkler is the first automation the player meets, with the shoo
# config as the candidate when it comes). `deploy()` below is the only way a bot
# enters a world, and only tests call it — the sprinkler's standing, and the
# bestiary's.
#
# Movement is the engine's, per WI-4's handoff: `Movement.plan` for where, `match
# Movement.step` for the next tile, and not one line of pathing here. Every draw
# is `SimRng`, inside `step()` (ground rule 3). Per-actor state is in the registry
# entry's `extra`, JSON-plain, so a save taken mid-chase restores a bot still
# chasing.
class_name BotBrain
extends Brain

# --- the settings, in two tiers ------------------------------------------------
#
# **The mark-1 does not decide anything** (designer, 2026-09-03: *"Mark-1 should
# take exact orders from you — you show it a certain set of tiles to be watered,
# and it waters those once per day. It is intentionally low capabilities."*). Its
# whole program is a list of tiles the player tapped, and its whole day is
# walking that list once. It has no target selection, no radius, no notion of
# where she is; a tile that has gone out of reach is skipped rather than reasoned
# about.
#
# The three below it — follow, circle, shoo — decide *for themselves* where to be
# and what to answer, and are therefore a **mark-2** machine's settings. Keeping
# them in this file rather than deleting them is the point: the capability ladder
# is the design, and the mark-2 is the rung above, not a rewrite.
#
# And the rung above *that* is the **mark-3**, whose one setting is `learn`: the
# mark-2's three behaviours were written by hand in this file, and a mark-3's is
# written by its own days — a policy over what it can see, nudged every night
# towards whatever earned that day (P-14, `design/06` "The ladder's third rung").
# So the ladder reads, in one file, as three answers to the same question: she
# decides (mark-1), we decided for it (mark-2), it works it out (mark-3).
const CONFIG_ORDERS := "orders"

# **A machine you have just put down is waiting, not already deciding** (from
# play, 2026-09-07: *"I accidentally put mark 2 in motion first time I
# interacted with it"*). Placing one used to deploy it straight into its default
# behaviour, so the first thing a new owner saw was a robot that had chosen its
# own job and set off — and with all three settings active, there was no way to
# tell it to stop short of picking it up.
#
# Idle is therefore two things at once: what a mark-2 is until she picks a job,
# and the job called "stand still". It is also the fallback for an unset config,
# which used to be `follow` — an unreadable field should mean a machine that does
# nothing, never a machine that starts trailing her.
const CONFIG_IDLE := "idle"

const CONFIG_FOLLOW := "follow"
const CONFIG_CIRCLE := "circle"
const CONFIG_SHOO := "shoo"

# **The mark-3's only setting, and it is not a dial** (v0.2.1 WI-3, P-14). A
# mark-2 is *set* to one of three behaviours and can be set to another; a mark-3
# has one thing it is, the way a mark-1 has one thing it is. So `learn` sits with
# `orders` in `ALL_CONFIGS` and out of `CONFIGS` — and because its catalogue row
# offers no configs either, the `configure` verb refuses a Mark III outright
# (`sim_world.gd`'s dial). That refusal is worth having rather than working
# around: turning the dial rebuilds `extra` from scratch, so a settable mark-3
# would be a machine whose weeks of learning she could wipe by tapping the wrong
# row of a menu.
const CONFIG_LEARN := "learn"

# The mark-2's three. Named as they always were, because the zoo, the tests and
# `MachineDefs` all mean *these* by "the configs a bot can be set to".
const CONFIGS: Array[String] = [CONFIG_FOLLOW, CONFIG_CIRCLE, CONFIG_SHOO]
# ...and every config the brain answers for, mark-1 and mark-3 included.
const ALL_CONFIGS: Array[String] = [CONFIG_ORDERS, CONFIG_IDLE,
		CONFIG_FOLLOW, CONFIG_CIRCLE, CONFIG_SHOO, CONFIG_LEARN]

# How many tiles a mark-1 will hold. **A capability limit, and the main one** —
# the machine is meant to retire a corner of the watering round, not the round.
# Eight is a third of a 20-action day spent watering, which leaves the job
# visibly shared. [Playtest]
const ORDER_LIMIT := 8

# How often a mark-1 with nothing to do looks up. It has genuinely nothing to
# watch for — it is waiting to be *sent*, and being sent is a verb that wakes it
# on the spot (`SimWorld`'s `activate`) — so this is a safety net rather than a
# poll, and it is long on purpose (ground rule 8).
const IDLE_SECONDS := 30.0

# --- the numbers, all [Playtest] ----------------------------------------------

# How far behind her a follow bot wants to be, and how much of that it will let
# slide before it moves. Two tiles is close enough to read as *hers* and far
# enough that it is never the thing she is looking at; the slack is what keeps it
# from twitching after every single step she takes.
const FOLLOW_TILES := 2
const FOLLOW_SLACK := 1

# The orbit, in tiles: the square ring a circle bot walks round her. Square
# rather than diamond because consecutive tiles of a square ring are orthogonally
# adjacent, so an orbit is a *walk* rather than a series of diagonal hops.
const ORBIT_RADIUS := 2

# How far round the ring it may skip when the next tile is blocked. A bot that
# gave up at the first obstacle would stall on the corner of a fence forever;
# one that could skip the whole ring would teleport round obstacles.
const MAX_ORBIT_SKIP := 4

# How far from its home tile a shoo bot considers its business, in tiles.
const SHOO_RADIUS := 6.0

# How long it leaves alone something it chased and could not budge — the
# songbird, and anything else with nothing to say about being chased. Long enough
# that a bot is not a machine hounding a small bird, short enough that it is
# clearly still doing its job.
const GIVE_UP_SECONDS := 20.0

# The pause between legs of a patrol. Short: this is a sentry, not an animal, and
# a nap is a window a crow can perch in.
const PATROL_IDLE := [0.4, 1.2]

# How often a bot with nothing to do looks up. It is a poll and it is meant to be
# one — watching is the job, so this is the cost of the job rather than a
# heartbeat (ground rule 8 is about actors that will *never* act again). At 0.4 s
# it is under three thinks a second for one actor, and a bot that is walking is
# paced by its own steps instead.
const POLL_SECONDS := 0.4

# How many stations it will try before deciding there is nowhere to stand. Each
# try is a route search, so this is the bound on what one think can cost.
const MAX_STATION_TRIES := 4

const STATE_PATROL := "patrolling"
const STATE_CHASE := "chasing"
const STATE_RETURN := "returning"


# --- the mark-3's eight actions, and its numbers -------------------------------
#
# **An action is what a tap is for her** (Q-100, ruled 2026-09-09; v0.2.1 WI-9b).
# When the player taps a square the game walks her there and does the verb, and
# that whole thing is one action at her granularity. The first Mark III was given
# single steps instead — finer than a tap — and the chains that led to a reward
# were correspondingly long: four separate lucky choices to cross a field and a
# fifth to water it. So a mark-3's action is now a **verb**, and the square is
# picked the way `ActionRouter` picks hers: the nearest tile in its own view where
# that verb is legal, walked to by the movement engine at the bot's pace, then put
# through the gateway with her cue. Nothing in view that the verb answers is a
# decision spent and nothing done — the same answer the router gives a tap on the
# wrong thing.
#
# **The order is the policy's index and is therefore permanent.** Row j of a
# robot's weights is action j, and those weights are saved, replayed and compared
# — so reordering this list would not break a build, it would quietly turn every
# robot anybody has ever trained into a robot that hoes when it means to ship.
# Add to the end or not at all. The list *was* reordered once, here, and only
# because Q-100 changed the observation from 128 numbers to 207 in the same
# breath: no robot's weights could survive that anyway, so there was one free
# moment to put the list in the order the design reads in and this is it.
const LEARN_TILL := 0
const LEARN_PLANT := 1
const LEARN_WATER := 2
const LEARN_HARVEST := 3
const LEARN_SHIP := 4
const LEARN_SHOO := 5
const LEARN_WANDER := 6
const LEARN_WAIT := 7
const LEARN_ACTIONS := 8

# Which verb each of the first six puts through the gateway. A table rather than
# six `match` arms so that "the actions" and "the verbs" cannot drift apart, and
# so the two lists are visibly the same length.
#
# `sell` and `crow_scared` are the two that are not named after their action:
# shipping is `sell`, the verb her own tap on the bin resolves to, and shooing
# emits the *crow's* own report exactly as a mark-2 does — the bot gains no verb
# by arriving next to a bird.
const LEARN_VERBS := {
	LEARN_TILL: "till",
	LEARN_PLANT: "plant",
	LEARN_WATER: "water",
	LEARN_HARVEST: "harvest",
	LEARN_SHIP: "sell",
	LEARN_SHOO: "crow_scared",
}

# Which tool each verb is held in, so the brain can ask the one table the player's
# tap is answered from whether this square takes that verb at all
# (`systems/tools.gd`, and `_legal_at` for why). Keys rather than indices, because
# an index is a position in a list a designer may reorder.
const HOE_KEY := "hoe"
const SEEDS_KEY := "seeds"
const HANDS_KEY := "hands"

# Which way a wander goes. `Movement.DIRS` rather than four Vector2is of this
# file's own, because it already is that list in that order (up, down, left,
# right) and the engine's own comment forbids reordering it for the same
# determinism reason this list cannot be reordered. One definition, one order.
const LEARN_STEPS := Movement.DIRS

# How far the wander's own draw is pushed away from the action's. The two are
# taken on the same decision number, so without a second salt they would be the
# same number and a wandering robot would always walk the same way.
const WANDER_SALT := 104729

# How far a mark-3 will follow a bird before it decides that one got away, in
# tiles. The mark-2's patch radius, and the same idea: a chase is a piece of work
# with an edge to it, not a machine hounding a crow across the farm. A bird in the
# air is faster than the bot by half again, so in practice this is the number that
# says "the ones you catch are the ones that landed".
const SHOO_CHASE_TILES := 6

# How hard a night pushes the weights. Any rate at all is only safe because the
# update is divided by the day's decisions before it is applied (`_sleep_on_it`):
# the trace is cumulative, so an un-normalised night grows with the *square* of
# how busy the day was, and WI-2's bandit locked onto the wrong arm at 0.05 with
# twenty decisions in it. A robot's day has several hundred.
#
# **0.03, chosen on the whole farm** (v0.2.1 WI-9b). Every earlier number in this
# comment was measured on a different machine and none of them survives: 0.03 on
# six actions penned inside a fence, 0.12 on a robot that spent thirty units on
# every hoe stroke that changed nothing, 0.06 on a robot whose whole job was
# watering. Q-100 changed both halves of the arithmetic at once — a decision is a
# whole errand now, so a day holds about a hundred of them rather than three
# hundred, and the day's score runs to twenty-odd points rather than five, because
# a crop in the bin is worth ten. Both of those move the size of a night's step,
# so the rate was measured again from scratch and the old tables are gone rather
# than argued with.
#
# The sweep, 24 farms over a week, read as the day's score. The control is the
# same 24 farms with the night switched off, and it is one row rather than one per
# rate because a robot that never learns cannot be affected by how hard a night
# would have pushed it. It rises on its own — the *field* improves whatever the
# robot understands, since soil opened yesterday is still open this morning and a
# square sown on Monday is ripe by Thursday — so the rate is chosen on the gap,
# never on the rise.
#
#     rate    days 1-3   days 5-7   weeks that rose
#     0.015      15.8       20.7        20 / 24
#     0.03       16.1       24.2        20 / 24
#     0.06       16.4       22.6        18 / 24
#     0.12       14.3       15.7        15 / 24
#     none       15.4       17.5        14 / 24   the control
#
# 0.03 is the widest gap and ties for the most farms improved. 0.12 is the row
# worth reading twice: it ends the week **below** a robot that never learned at
# all, because a night that pushes hard on a day whose score is dominated by one
# ten-point sale teaches the robot to repeat whatever it was doing when that sale
# happened. The bigger the biggest row of the reward table, the gentler the night
# has to be. Reproduce it with `tools/demo_learning_robot.gd`, which prints the
# 24-farm week under its table on every run.
#
# **A week on one farm is luck as much as learning, which is why the gate is not
# one.** On open ground a single week's rise flips with the rate for no reason
# but the draw, and the control's own weeks rise nearly as often, so
# `test_learning_robot` asks the question the demo asks: over a fixed list of
# farms, is a week of nights worth more than the same week without them.
# [Playtest]
const LEARN_RATE := 0.03

# How far apart two days' draws are pushed. Any odd stride would do; a prime is
# the cheap way to keep one robot's second day out of another robot's first.
const LEARN_DAY_STRIDE := 7919

# How long a robot with an empty meter stands still. An hour of sim time, which
# is well past dusk — in practice it means "until the day turns", and the day
# turn re-arms it (`SimWorld.schedule_all_brains`). Long rather than clever,
# because a machine that has nothing left to spend must cost nothing at all
# (ground rule 8).
const LEARN_PARKED_SECONDS := 3600.0


# --- deployment ----------------------------------------------------------------
#
# **The only way a bot enters a world.** Not a verb: a spawn is not a thing an
# actor does (SimWorld's registry block), and not an acquisition either — Q-56
# holds the debut, so the callers are the tests and whatever M3 builds.
#
# `params` is the configuration, and everything in it lands in `extra` where it
# is saved, replayed and compared like any other per-actor state. Defaults are the
# constants above, so `deploy(world, "bot", CONFIG_SHOO, tile)` is a working
# machine and the parameters are for the tests and for tuning.
static func deploy(world: SimWorld, actor_id: String, config: String, at: Vector2i,
		params: Dictionary = {}) -> Dictionary:
	var extra: Dictionary = {
		"config": config,
		# Who it belongs to. A registry id rather than "the player", because a bot
		# following the neighbour is the same brain and one string — and because
		# nothing in layer 2 should assume there is exactly one person.
		"owner": String(params.get("owner", SimWorld.ACTOR_PLAYER)),
		"state": STATE_PATROL,
		"goal_x": -1, "goal_y": -1,
	}
	match config:
		CONFIG_ORDERS:
			# The program, flat, because `extra` goes through JSON in the save and
			# a Vector2i does not survive that round trip (Brain's rule). Stored as
			# [x1, y1, x2, y2, ...], the shape a worm's `body` already uses.
			extra["orders"] = params.get("orders", [])
			# Out on its round right now / has already been out today / how far
			# down the list it has got. All three are cleared by `on_new_day`.
			extra["sent"] = false
			extra["ran_today"] = false
			extra["at_order"] = 0
			# **Where it lives, if it was set down somewhere that is a home**
			# (the stall, CEO 2026-09-06). The same two fields the shoo config
			# uses for the middle of its patch, on purpose: a mark-1 in a stall
			# and a mark-2 holding a patch are both machines with a place they
			# belong to, and one concept gets one name. A bot put down on open
			# ground has no home and neither field is written — `_home` answers
			# (-1,-1) and every behaviour below it is the one that shipped.
			if world.is_stall_tile(at):
				extra["home_x"] = at.x
				extra["home_y"] = at.y
		CONFIG_LEARN:
			# **The senses are written here, not on the catalogue row** (v0.2.1
			# WI-3). `MachineDefs` is layer 1 and may not import the sim, so it
			# could not name an observation spec even if it wanted to — and it
			# should not want to: P-14's promise is that a robot's inputs are an
			# *adjustable* spec, which means the adjustable copy belongs on the
			# robot. A machine bought today keeps the senses it was born with even
			# after a later build widens the default, so its weights can never be
			# reinterpreted against a vector it never learned on.
			var spec := Observation.spec_default()
			extra["spec"] = spec
			var width := Observation.size(spec)
			# Zeros, so a robot out of the box is uniform over its eight actions:
			# it wanders on day one, which is what P-14 says day one should look
			# like.
			extra["weights"] = Policy.new_weights(width, LEARN_ACTIONS)
			# The day's three running sums: what it has done (`trace`), what that
			# earned (`acc`), and what the baseline is charged against
			# (`base_trace`) — the same trace again, each decision weighted by how
			# much of the meter was still in its arms when it made it. All three
			# are zeroed every night; `_sleep_on_it` says why the third exists.
			extra["trace"] = Policy.new_weights(width, LEARN_ACTIONS)
			extra["acc"] = Policy.new_weights(width, LEARN_ACTIONS)
			extra["base_trace"] = Policy.new_weights(width, LEARN_ACTIONS)
			# What a day has been worth so far, what the last one was worth, and
			# the running mean of every day before it. The panel reads `days` and
			# `last_score`; nothing outside this file reads the weights (Q-97).
			extra["score"] = 0.0
			extra["last_score"] = 0.0
			extra["baseline"] = 0.0
			extra["days"] = 0
			extra["decisions"] = 0
			# The same day's score, split by which row of `Rewards.TABLE` earned
			# it — one number per row, in `Rewards.KEYS` order (v0.2.1 WI-9b).
			# **It is a report, not an input**: nothing the robot decides with
			# reads it, and the policy would be exactly the same policy without
			# it. It is here because "the machine is learning" is a claim, and a
			# claim about a farm with eight ways to earn on it needs to say
			# *which* of the eight a week actually reached — which is a question
			# only the brain can answer, since the outcome of a stroke is gone by
			# the time the gateway has replied. An array rather than a dictionary
			# because it rides in `extra` through JSON (ground rule 4) and an
			# array's order is written down.
			extra["earned"] = _new_split()
			# Its own number, folded from its id rather than hashed with the
			# engine's `hash()` — see `Policy.salt_of` for why that distinction is
			# worth a function.
			extra["salt"] = Policy.salt_of(actor_id)
			# **What the thing it is doing right now would earn, if the gateway
			# says yes** — the name of a row of `Rewards.TABLE`, or "" for a
			# decision with nothing owing. Remembered across the one beat between
			# reaching for a square and the gateway answering, because by then the
			# square is wet, or open, or cut, and what it *was* is gone. See
			# `on_result`.
			extra["pending"] = ""
			# **The job it is walking to**: the verb, the square it is for, and
			# the bird it is after if it is a chase. An action is a tap now, and a
			# tap is a walk and then a verb — so between the decision and the deed
			# there are several seconds in which the robot is committed and does
			# not think (`_carry_on`). Empty strings and -1s are "nothing on".
			extra["job"] = ""
			extra["job_x"] = -1
			extra["job_y"] = -1
			extra["job_target"] = ""
			# **What is in its hands, as a word** (v0.2.1 WI-9a, Q-100): the crop
			# type it is carrying, or "" for empty. A machine's harvest goes here
			# rather than into her basket and comes out again at the bin, both
			# through the gateway — so a robot that never gets there is a robot
			# standing in a field holding a wheat, which is exactly what a player
			# should be able to see it doing. A String, because `extra` is
			# JSON-plain all the way down (ground rule 4).
			extra["carrying"] = ""
		CONFIG_CIRCLE:
			extra["radius"] = int(params.get("radius", ORBIT_RADIUS))
		CONFIG_SHOO:
			extra["home_x"] = int(params.get("home_x", at.x))
			extra["home_y"] = int(params.get("home_y", at.y))
			extra["radius"] = float(params.get("radius", SHOO_RADIUS))
			# **What it is looking for is a class, not a list of names**
			# (`SpeciesDefs.class_of`). "bird" is the crow and the songbird today
			# and is whatever else grows wings later, with no edit here.
			extra["quarry"] = String(params.get("quarry", SpeciesDefs.CLASS_BIRD))
			extra["target"] = ""
			extra["ignore"] = ""
			extra["ignore_until"] = 0
		_:
			extra["distance"] = int(params.get("distance", FOLLOW_TILES))
	return world.spawn_actor(actor_id, SpeciesDefs.BOT, at, extra)


# --- one bot's think -----------------------------------------------------------

func step(world: SimWorld, actor_id: String, tick: int, gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]
	# **The machines wait for her day to start** (CEO, 2026-09-07, from play):
	# no bot lifts a tool while the player is still in the house. Every config,
	# because the rule is about the farm's rhythm, not one setting. Sim-pure and
	# deterministic — her tile is registry truth, its page is grid arithmetic,
	# and her crossings are recorded and replayed. A player who never leaves is
	# a farm where nothing happens, which is exactly what it looks like.
	if world.page_of(world.actor_pos(SimWorld.ACTOR_PLAYER)) == 1:
		extra["wake"] = tick + ticks(IDLE_SECONDS)
		return {}
	match String(extra.get("config", CONFIG_IDLE)):
		CONFIG_ORDERS:
			return _orders(world, actor_id, extra, tick)
		CONFIG_LEARN:
			return _learn(world, actor_id, extra, tick, gs)
		CONFIG_CIRCLE:
			_circle(world, actor_id, extra, tick)
		CONFIG_SHOO:
			return _shoo(world, actor_id, extra, tick)
		CONFIG_FOLLOW:
			_follow(world, actor_id, extra, tick)
		_:
			# Idle, and anything unrecognised with it. A long wake rather than a
			# tight one: it is waiting to be *told*, and being told is a verb that
			# wakes it on the spot (`SimWorld`'s `configure`).
			extra["wake"] = tick + ticks(IDLE_SECONDS)
	return {}


# --- the mark-1: exact orders, once a day --------------------------------------
#
# The list is `extra.orders`; the position in it is `extra.at_order`; whether it
# is out is `extra.sent`. There is nothing else, and that is the design.
#
# **It never re-decides.** It walks to order N, works order N — tilling it if the
# ground is bare and watering it if it is soil (see `order_verb`) — moves to
# order N+1, and stops at the end of the list. A tile it cannot reach — she fenced it
# off, a hen is parked on it and will not move, she tore the plot up after
# teaching it — is *skipped*, not queued, not retried, not replaced with a
# nearer one. That is what "exact orders" means from the machine's side, and it
# is what makes a mark-1 legibly stupid rather than mysteriously stuck: the
# failure mode a player sees is "it missed that one", which is a thing she can
# fix by teaching it again.
# **What the square is asking for**, out of the two things a mark-1 does
# (designer, 2026-09-07: *"make the robot till if it's grass, and water if it's
# soil — basically, reset after a harvest"*).
#
# Harvesting sets a tile back to `cleared`, so a round taught over a crop row
# becomes a round over bare ground the moment she picks the crop. Watering bare
# ground is not refused — it is simply nothing, because `water_tile` only wets
# soil — so before this the machine walked its whole list and achieved nothing
# the day after a harvest, which is precisely the silent trap `TEACHABLE_STATES`
# was written to keep out of the teaching menu and quietly let in here.
#
# It is still not deciding in the mark-2's sense: she chose every square, and the
# square itself says which of the two it needs. What the machine has gained is a
# way to be *useful* on the list she already gave it.
static func order_verb(world: SimWorld, t: Vector2i) -> String:
	var tile := world.get_tile(t.x, t.y)
	if tile.is_empty():
		return ""
	if String(tile.get("state", "")) == "cleared":
		return "till"
	# **Only a square that can take water gets watered**, and only if it has not
	# had any (CEO, from play on a rainy morning, 2026-09-07: *"it went out and
	# watered the already-watered tiles. Instead, it should go out and look at
	# the tiles but not water if already watered."*). Rain wets every soil square
	# at dawn, so on a wet day the whole round used to be strokes that changed
	# nothing at all. The set is `SimWorld.WETTABLE_STATES` rather than a list of
	# its own, so the squares the machine offers to water and the squares water
	# actually shows on can never drift apart.
	#
	# The empty string is "walk here, look, and move on". It still walks: the
	# round is a patrol, and a machine that stayed home on a wet day would give
	# her nothing to look at and no sign it had understood the weather.
	if String(tile.get("state", "")) in SimWorld.WETTABLE_STATES \
			and not bool(tile.get("watered_today", false)):
		return "water"
	return ""


func _orders(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	if not bool(extra.get("sent", false)):
		extra["wake"] = tick + ticks(IDLE_SECONDS)
		return {}
	var list := orders_of(extra)
	var at := int(extra.get("at_order", 0))
	if at < 0 or at >= list.size():
		return _round_done(world, actor_id, extra, tick)

	var goal: Vector2i = list[at]
	var here := world.actor_pos(actor_id)
	if here == goal:
		# Standing on it: water it and move down the list. The index advances
		# **before** the gateway has answered, deliberately — a refused order (the
		# ground changed, it is out of energy) is still an order it has been
		# through, and a machine that retried would stand on a rock all day.
		extra["at_order"] = at + 1
		_paced(world, actor_id, extra, tick)
		return _work(world, actor_id, goal)

	if Movement.has_route(world, actor_id) and _goal(extra) == goal:
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				if world.actor_pos(actor_id) == goal:
					extra["at_order"] = at + 1
					_paced(world, actor_id, extra, tick)
					return _work(world, actor_id, goal)
				return {}
			_:
				Movement.clear_route(world, actor_id)
	if _set_out(world, actor_id, extra, tick, goal) == "":
		# No way there at all. Skip it, and look at the next one on the next
		# think rather than in this one, so a list of eight unreachable tiles
		# costs eight thinks instead of eight route searches in one.
		extra["at_order"] = at + 1
		_wait(extra, tick)
	return {}


# The action for the square it is standing on, or none at all. Written as one
# place so "arrive, look, move on" cannot drift apart from "arrive, work, move
# on" — the index has already advanced either way, because a square it has looked
# at is a square it has been through.
func _work(world: SimWorld, actor_id: String, goal: Vector2i) -> Dictionary:
	var verb := order_verb(world, goal)
	if verb == "":
		return {}
	return { "verb": verb, "target": goal, "actor": actor_id }


# Is there anything on this machine's list worth walking to today?
#
# **A round that would achieve nothing is declined rather than walked** (Q-93,
# ruled 2026-09-07). The machine does not harvest — the designer's call, and the
# reason machines stay in the labour-saving column rather than filling her stores
# without her hand on it — so on a rainy morning, with nothing gone bare, every
# square on its list already needs nothing. It would walk eight squares and come
# home having done not one thing. That is honest and it looks broken, which is
# the worse of the two, so the panel says so instead and she keeps the turn.
#
# Pure, and asked of the same `order_verb` the round itself uses, so the panel
# and the machine can never disagree about whether there is work.
static func round_has_work(world: SimWorld, extra: Dictionary) -> bool:
	for t in orders_of(extra):
		if order_verb(world, t) != "":
			return true
	return false


# Is every machine on the farm standing still because she has not come outside?
# The rule lives in `step`; this is the same question asked from the menu, so the
# panel can say what is true instead of guessing (`ui/menus.gd`).
static func waiting_for_player(world: SimWorld) -> bool:
	return world.page_of(world.actor_pos(SimWorld.ACTOR_PLAYER)) == 1


# The end of the round — but not the end of the errand, if it has somewhere to be.
#
# **A machine that lives somewhere goes back there** (the stall, CEO 2026-09-06).
# Without a home it stops on the last tile of its list and stands in the crop row
# it just watered, which is what shipped and is still exactly what a bot on open
# ground does. With one, the round is not over until it is parked: the list runs
# out, it walks home on the same engine its orders walk on, and only when it
# arrives is it no longer out.
#
# It stays `sent` for the walk home, deliberately: it *is* still out, the menu says
# "Out working…" while it crosses the yard, and a player who sends it and watches
# it come back sees one errand rather than two.
func _round_done(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	var home := _home(extra)
	if home.x >= 0 and world.actor_pos(actor_id) != home:
		return _walk_home(world, actor_id, extra, tick, home)
	return _park(world, actor_id, extra, tick)


# One step of the way back to the stall. The orders' own shape (plan once, step
# while the route holds, re-plan when it does not), because it is the same
# journey: a tile it must be on, walked to at its own pace.
func _walk_home(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		home: Vector2i) -> Dictionary:
	if Movement.has_route(world, actor_id) and _goal(extra) == home:
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				if world.actor_pos(actor_id) == home:
					return _park(world, actor_id, extra, tick)
				return {}
			_:
				Movement.clear_route(world, actor_id)
	if _set_out(world, actor_id, extra, tick, home) == "":
		# It cannot get back — she fenced the stall off, something is standing in
		# its bay, the ground changed while it was out. It parks where it stands,
		# which is the mark-1's answer to everything it cannot do: stop, visibly,
		# somewhere she can see it and pick it up.
		return _park(world, actor_id, extra, tick)
	if world.actor_pos(actor_id) == home:
		return _park(world, actor_id, extra, tick)
	return {}


# Standing down for the day: it is not out any more, and it has had its turn.
func _park(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	extra["sent"] = false
	extra["at_order"] = 0
	Movement.clear_route(world, actor_id)
	_aim(extra, Vector2i(-1, -1))
	extra["wake"] = tick + ticks(IDLE_SECONDS)
	return {}


# --- the order list, as the rest of the game sees it ---------------------------
#
# Stored flat and JSON-plain; handed out as tiles. Static so the gateway's `teach`
# verb, the menu and the renderer all read the one encoding rather than three.
static func orders_of(extra: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var flat: Array = extra.get("orders", [])
	var i := 0
	while i + 1 < flat.size():
		out.append(Vector2i(int(flat[i]), int(flat[i + 1])))
		i += 2
	return out


static func set_orders(extra: Dictionary, tiles: Array[Vector2i]) -> void:
	var flat: Array = []
	for t in tiles:
		flat.append(t.x)
		flat.append(t.y)
	extra["orders"] = flat


# --- follow --------------------------------------------------------------------
#
# **It reads her live registry position**, which is sim truth as of WI-6 and was
# not before it: until her tile crossings were written into the registry (and
# recorded as free-walk entries a replay applies back), a sim-side follower would
# have trailed the tile she spawned on for the whole session. That is why this
# config could not have been written one work item earlier, and it is why a
# recorded session is the honest test of it.
#
# It re-plans **as she moves**: the station it is walking to is the ring of tiles
# at the right distance from wherever she is *now*, so a station that has gone
# stale (she turned a corner) is thrown away rather than walked to. That makes a
# follow bot the most expensive brain in the game — one route search per tile it
# steps while she is moving — and it is still per *decision*, never per tick
# (ground rule 8): a bot at its station costs one poll.
func _follow(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	var her := _owner_tile(world, extra)
	if her.x < 0:
		_wait(extra, tick)
		return
	var here := world.actor_pos(actor_id)
	var keep := maxi(1, int(extra.get("distance", FOLLOW_TILES)))
	var gap := _manhattan(here, her)

	# Station kept. **Her tile is never one**: `here != her` is what gets it out
	# from under her feet if she walks onto it, and the ring below cannot pick her
	# tile in the first place, so "never blocks her" is true by construction
	# rather than by a check that could be forgotten.
	if here != her and absi(gap - keep) <= FOLLOW_SLACK:
		Movement.clear_route(world, actor_id)
		_wait(extra, tick)
		return

	if Movement.has_route(world, actor_id) and not _station_stale(extra, her, keep):
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				return  # the engine set the next wake from the speed row
			_:
				# Arrived, or the ground changed under it. Either way the answer is
				# a fresh station, which is the next thing this function does.
				Movement.clear_route(world, actor_id)
	_take_station(world, actor_id, extra, tick, her, keep)


# Has the tile it is walking to stopped being a station? Cheap, and it is what
# keeps the re-planning bounded: while she walks in a straight line the station
# drifts one tile at a time and stays inside the slack for a step or two.
func _station_stale(extra: Dictionary, her: Vector2i, keep: int) -> bool:
	var goal := _goal(extra)
	if goal.x < 0:
		return true
	return absi(_manhattan(goal, her) - keep) > FOLLOW_SLACK


# The nearest tile it could stand on at exactly `keep` tiles from her. Nearest to
# *itself*, so a bot cuts the corner she cut rather than walking round her.
func _take_station(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		her: Vector2i, keep: int) -> void:
	var here := world.actor_pos(actor_id)
	var tried := 0
	for t in _nearest_first(_stations(world, actor_id, her, keep), here):
		tried += 1
		if tried > MAX_STATION_TRIES:
			break
		if _set_out(world, actor_id, extra, tick, t) != "":
			return
	# Nowhere to stand at that distance, or no way to get there — a farmer in a
	# doorway, a bot on the wrong side of a fence. It waits and asks again, which
	# is the honest answer for a machine whose whole job is her.
	Movement.clear_route(world, actor_id)
	_aim(extra, Vector2i(-1, -1))
	_wait(extra, tick)


# The diamond of tiles at exactly `keep` Manhattan tiles from her that this actor
# could stand on. Built in a fixed scan order; her own tile is not in it.
func _stations(world: SimWorld, actor_id: String, her: Vector2i, keep: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var mode := Movement.mode_of(world.species_of(actor_id))
	for dy in range(-keep, keep + 1):
		var dx := keep - absi(dy)
		for sx in ([0] if dx == 0 else [-dx, dx]):
			var t := her + Vector2i(int(sx), dy)
			if Movement.can_stop(world, mode, t) and Movement.can_enter(world, actor_id, t):
				out.append(t)
	return out


# --- circle --------------------------------------------------------------------
#
# The same reading of her position, spent differently: instead of a station it
# takes the **next tile round the ring** every time it arrives on one. The ring is
# centred on wherever she is now, so it travels with her, and a bot orbiting a
# walking farmer keeps going the way it was going rather than starting its circle
# again from wherever she stopped.
func _circle(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	var her := _owner_tile(world, extra)
	if her.x < 0:
		_wait(extra, tick)
		return
	if Movement.has_route(world, actor_id):
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				return
			_:
				Movement.clear_route(world, actor_id)

	var r := maxi(1, int(extra.get("radius", ORBIT_RADIUS)))
	var ring := ring_tiles(her, r)
	if ring.is_empty():
		_wait(extra, tick)
		return
	var mode := Movement.mode_of(world.species_of(actor_id))
	# **The phase is read off its position, not remembered.** A bot standing on
	# the ring goes to the next tile round it — which is adjacent, so that is one
	# step and the orbit is a walk. A bot that is *not* on the ring (it was just
	# deployed, or she moved and took the ring with her) joins at the nearest tile
	# of it. Deriving rather than storing is what stops the two from disagreeing:
	# a remembered index would send a displaced bot marching across her to a tile
	# a quarter of the way round, which is what the first version did.
	var here := world.actor_pos(actor_id)
	var idx := ring.find(here)
	var hop_from := 1
	if idx < 0:
		idx = _nearest_index(ring, here)
		hop_from = 0
	# The next tile round, and the one after that if the next is a rock. Skipping
	# is the `_wriggle` answer (WI-8e) for a mover that has somewhere it must be
	# rather than a route it must take: go round, up to a bounded number of tries,
	# and never stand still because one tile of the ring is a hedge.
	for hop in range(hop_from, MAX_ORBIT_SKIP + 1):
		var at: int = posmod(idx + hop, ring.size())
		var t: Vector2i = ring[at]
		if t == her or not Movement.can_stop(world, mode, t) \
				or not Movement.can_enter(world, actor_id, t):
			continue
		if _set_out(world, actor_id, extra, tick, t) != "":
			return
	_wait(extra, tick)


# The square ring of radius `r` about `c`, clockwise from its top-left corner.
# **Consecutive tiles are orthogonally adjacent** (including the wrap), which is
# what makes an orbit a sequence of single steps; a Manhattan ring would have the
# bot hopping diagonally between tiles it cannot walk between. Static and pure so
# the shape can be asserted without a world.
static func ring_tiles(c: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if r <= 0:
		return out
	for dx in range(-r, r + 1):
		out.append(c + Vector2i(dx, -r))
	for dy in range(-r + 1, r + 1):
		out.append(c + Vector2i(r, dy))
	for dx in range(r - 1, -r - 1, -1):
		out.append(c + Vector2i(dx, r))
	for dy in range(r - 1, -r, -1):
		out.append(c + Vector2i(-r, dy))
	return out


# --- shoo ----------------------------------------------------------------------
#
# Patrol a patch, chase what does not belong in it, come back. The three
# interesting decisions are all about **what "chase" is allowed to mean**:
#
#   *what it looks for* is a class (`extra.quarry`), asked of the registry
#     (`SimWorld.actors_of_class`) rather than of a list of species names in this
#     file. A new bird is chased by a bot that shipped before it existed.
#   *what counts as being there* is `Movement.occupied_tiles`, not `actor_pos` —
#     WI-8d/8e's handoff, and the difference between answering a four-tile animal
#     and answering its head (it is a bird today; it will not always be).
#   *what reaching it does* is the crow's own `crow_scared` report, unchanged:
#     the visit ends exactly the way it ends when she walks over herself, because
#     it is the same event with a different cause (`by`, which the gateway reads
#     to tell a person's fright from a machine's — and which since Q-66 was ruled
#     no longer decides whose proof it is: the scare counts for her either way.
#     See `SimWorld._apply`).
#
# And the fourth, which is the honest one: **the songbird has nothing to say
# about being chased.** It has no verbs, no flee and no visit to end, so a bot
# that reaches one gets no answer — see `_reached`.
func _shoo(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	var state := String(extra.get("state", STATE_PATROL))
	if state == STATE_CHASE:
		return _chase(world, actor_id, extra, tick, String(extra.get("target", "")))

	# The watch, first and on every think that is not already a chase — the
	# grazer's fright check in the other direction, and for the same reason: the
	# whole point of the machine is that it interrupts what it was doing.
	var found := _quarry_near(world, actor_id, extra, tick)
	if found != "":
		extra["target"] = found
		extra["state"] = STATE_CHASE
		Movement.clear_route(world, actor_id)
		_aim(extra, Vector2i(-1, -1))
		return _chase(world, actor_id, extra, tick, found)

	if state == STATE_RETURN:
		_go_home(world, actor_id, extra, tick)
	else:
		_patrol(world, actor_id, extra, tick)
	return {}


# The nearest thing of its quarry class standing inside its radius, or "".
#
# Cost is one pass over the registry per think — four to six entries in any farm
# this game has ever had — and never over the map. Ids come back sorted and are
# kept on a **strictly** smaller distance, so two equidistant birds resolve the
# same way on every machine and in every replay.
func _quarry_near(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> String:
	var home := _home(extra)
	var radius := float(extra.get("radius", SHOO_RADIUS))
	var ignore := String(extra.get("ignore", ""))
	var ignore_until := int(extra.get("ignore_until", 0))
	var best := ""
	var best_d := INF
	for id in world.actors_of_class(String(extra.get("quarry", SpeciesDefs.CLASS_BIRD))):
		if id == actor_id:
			continue
		if id == ignore and tick < ignore_until:
			continue
		var d := _distance_to(world, id, home)
		if d <= radius and d < best_d:
			best_d = d
			best = id
	return best


func _chase(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		target: String) -> Dictionary:
	if target == "" or not world.has_actor(target):
		# It left on its own — a crow that finished its visit, a songbird that
		# drifted off the map. Nothing to chase, and nothing to feel about it.
		return _stand_down(world, actor_id, extra, tick)
	var tiles := Movement.occupied_tiles(world, target)
	if tiles.is_empty() or _distance_to(world, target, _home(extra)) \
			> float(extra.get("radius", SHOO_RADIUS)):
		# Out of the patch. **Not its business any more**, which is what makes a
		# patrol radius a radius rather than a starting pistol.
		return _stand_down(world, actor_id, extra, tick)

	if world.actor_pos(actor_id) in tiles:
		return _reached(world, actor_id, extra, tick, target)

	var head: Vector2i = tiles[0]
	if Movement.has_route(world, actor_id) and _goal(extra) == head:
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				if world.actor_pos(actor_id) in Movement.occupied_tiles(world, target):
					return _reached(world, actor_id, extra, tick, target)
				return {}
			_:
				Movement.clear_route(world, actor_id)
	# Re-aim at where it is now. Once per step it takes, not once per tick — a
	# bird in the air moves every tick and a machine walking after it does not get
	# to think faster than it walks.
	if _set_out(world, actor_id, extra, tick, head) == "":
		# A bird where a walker cannot follow: perched over a hedge, eating an
		# acorn behind a gate she has not opened. The machine's honest answer is
		# that this one is not for it.
		return _give_up(world, actor_id, extra, tick, target)
	if world.actor_pos(actor_id) in Movement.occupied_tiles(world, target):
		return _reached(world, actor_id, extra, tick, target)
	return {}


# It is standing on the thing it chased. What happens next is the *quarry's*
# answer, not the bot's, and that is the whole of this function:
#
#   **a crow** has `crow_scared` on its species row — a report, not a capability
#     (`SpeciesDefs.ENTITY_VERBS`) — so the bot files it and the visit ends
#     exactly as it ends when the player walks over: `Brains.flee`, the same
#     state, the same feathers. The bot gains no verb by doing this; it causes a
#     bird to say a thing the bird could always say.
#
#   **a songbird** has no verbs at all. There is no Action either of them can
#     take, nothing in the sim to change, and inventing something — a despawn, a
#     flee it has no state for, a verb — would be the special case the songbird
#     exists to prove the system does not need (WI-8g). So the honest outcome is
#     *nothing happened*, and the only thing the bot may honestly do about it is
#     stop: it marks the bird as one it cannot budge, leaves it alone for
#     `GIVE_UP_SECONDS`, and goes home. A machine that kept chasing a bird that
#     does not care would be a heartbeat with a mission statement.
func _reached(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		target: String) -> Dictionary:
	if not SpeciesDefs.may(world.species_of(target), "crow_scared"):
		return _give_up(world, actor_id, extra, tick, target)
	_stand_down(world, actor_id, extra, tick)
	return {
		"verb": "crow_scared",
		"target": world.actor_pos(target),
		"actor": target,
		# Who did the frightening. The gateway reads it for the *kind* of cause
		# (a person or a machine) rather than for whose proof it is — Q-66 is
		# ruled and the credit is hers either way — and it is what makes a bot's
		# work legible in the replay corpus phase 4 trains on: "this bird left
		# because that machine arrived".
		"by": actor_id,
	}


# The chase is over, however it ended. Home, and back on watch when it gets there.
func _stand_down(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	extra["target"] = ""
	extra["state"] = STATE_RETURN
	Movement.clear_route(world, actor_id)
	_aim(extra, Vector2i(-1, -1))
	_go_home(world, actor_id, extra, tick)
	return {}


# ...and this one is out of reach or out of answers, so it is left alone for a
# while. Per-target and time-boxed rather than permanent: an id can be reused (a
# second songbird takes the first one's name), and a bird that was behind a fence
# may not be in twenty seconds.
func _give_up(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		target: String) -> Dictionary:
	extra["ignore"] = target
	extra["ignore_until"] = tick + ticks(GIVE_UP_SECONDS)
	return _stand_down(world, actor_id, extra, tick)


func _go_home(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	var home := _home(extra)
	var here := world.actor_pos(actor_id)
	if here == home:
		extra["state"] = STATE_PATROL
		_rest(extra, tick)
		return
	if Movement.has_route(world, actor_id) and _goal(extra) == home:
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				return
			Movement.BLOCKED:
				Movement.clear_route(world, actor_id)
			_:
				extra["state"] = STATE_PATROL
				_rest(extra, tick)
				return
	if _set_out(world, actor_id, extra, tick, home) == "":
		# It cannot get back to the middle of its patch — the ground changed, or
		# somebody fenced it out. It patrols from where it is, because a sentry
		# that cannot reach its post is still a sentry.
		extra["state"] = STATE_PATROL
		_rest(extra, tick)


# A leg of the patrol: somewhere inside the radius, walked to, then a beat's
# pause. The beat is short on purpose (see PATROL_IDLE) — the watch happens in
# `_shoo` before this is ever reached, so a resting bot is a bot that is not
# looking, and a crow perches for a few seconds.
func _patrol(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	extra["state"] = STATE_PATROL
	if Movement.has_route(world, actor_id):
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				return
			_:
				Movement.clear_route(world, actor_id)
				_rest(extra, tick)
				return
	var beat := _patrol_tile(world, actor_id, extra)
	if beat.x < 0 or _set_out(world, actor_id, extra, tick, beat) == "":
		_rest(extra, tick)


# Somewhere inside the patch it could get to, in its own mode. The draw is the
# grazer's `_random_reachable` narrowed to the radius: `Movement.reachable`
# answers in the engine's fixed breadth-first order, so the same seed picks the
# same tile in a replay as it did live.
func _patrol_tile(world: SimWorld, actor_id: String, extra: Dictionary) -> Vector2i:
	var home := _home(extra)
	var radius := float(extra.get("radius", SHOO_RADIUS))
	var mode := Movement.mode_of(world.species_of(actor_id))
	var inside: Array[Vector2i] = []
	for t in Movement.reachable(world, mode, world.actor_pos(actor_id)):
		if Vector2(t - home).length() <= radius and Movement.can_stop(world, mode, t):
			inside.append(t)
	if inside.is_empty():
		return Vector2i(-1, -1)
	return inside[SimRng.randi() % inside.size()]


# --- the mark-3: one decision an errand, and one lesson a night ----------------
#
# **Everything above this line was written by hand. This is the rung where that
# stops** (P-14; `design/06`, "The ladder's third rung"). A mark-3 has no orders,
# no station, no patch and no rule about where to be. It looks at what is around
# it, picks one of eight things with a linear policy, and does it: open bare
# ground, sow a seed out of her box, water something thirsty, cut something ripe,
# carry what it is holding to the bin, chase a bird off, take a step for no
# reason, or stand still.
#
# **A decision is a whole errand, because that is what her tap is** (Q-100). It
# does not choose a direction and then choose again a second later; it chooses a
# *verb*, and the square is then found and walked to exactly the way the router
# finds and walks hers — the nearest tile in view where that verb is legal, by
# the same `systems/tools.gd` table her tap is answered from. While it walks it
# does not think, which is what makes a robot's day legible: it is going
# somewhere for a reason, and a player can see which.
#
# **It is paid for outcomes, never for gestures** (`systems/rewards.gd`). A crop
# that reaches the bin is worth ten; a bird caught mid-meal three; a crop cut, a
# plant watered and a seed sown one each; opening ground and wetting empty soil a
# tenth. Watering ground that is already wet earns exactly what walking into a
# fence earns, which is nothing, and the machine has to work out the difference
# for itself.
#
# **A day is a wander and a night is the lesson** (P-14's second rule). During the
# day the only things that change are the two running sums; the weights the day
# is being played on are not touched until `on_new_day` closes it. That is what
# makes a day a fair sample of one policy rather than a smear of several, and it
# is why a player watching a mark-3 sees it behave consistently between mornings.
#
# **Nothing here is recorded.** The draw is `Policy.draw_u` off (seed, this
# robot, today, decision number), so a replay recomputes every choice of the day
# from the log's one `sleep` entry rather than reading it back (Q-53, ground
# rule 3). Cost per decision is one observation, one policy evaluation, one scan
# of a 5×5 patch and at most one route search (ground rule 8) — and a decision is
# now an errand rather than a step, so a busy day holds fewer of them than it did.
func _learn(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		gs = null) -> Dictionary:
	# **An empty meter is a machine standing in the field, not a machine thinking
	# about standing in the field** (P-14's "a day's energy like hers"). There is
	# nothing left for the costed verbs to spend, so it stops deciding until the
	# morning refills it. The day turn re-arms every brain, which makes this wake
	# a backstop rather than an appointment — and a long one, because a robot with
	# nothing to spend must cost nothing at all.
	if world.is_exhausted(actor_id):
		_drop_job(world, actor_id, extra)
		extra["pending"] = ""
		extra["wake"] = tick + ticks(LEARN_PARKED_SECONDS)
		return {}

	# Mid-errand: walking, and therefore not deciding. The wake was set by the
	# movement engine's own step, so this costs one think per tile crossed and
	# nothing at all per tick.
	if String(extra.get("job", "")) != "":
		return _carry_on(world, actor_id, extra, tick, gs)

	# Her stores go in with the world (v0.2.1 WI-9a): the seed box is one of the
	# robot's inputs, and it is the one thing it can see that is not grid truth.
	var obs := Observation.build(world, actor_id, extra.get("spec", {}), gs)
	var n_in := obs.size()
	var chances := Policy.probs(Policy.logits(extra["weights"], n_in, LEARN_ACTIONS, obs))
	var decisions := int(extra.get("decisions", 0))
	# The day is part of the salt so that a robot which has learned nothing yet
	# does not repeat yesterday's exact wander today; the decision number is the
	# index, so consecutive decisions are consecutive draws. `draw_u` rather than
	# a bare `SimRng.stateless` — see the long note on that function for what
	# happens without the scramble.
	var salt: int = int(extra.get("salt", 0)) ^ (int(extra.get("days", 0)) * LEARN_DAY_STRIDE)
	var choice := Policy.sample(chances, Policy.draw_u(salt, decisions))
	extra["decisions"] = decisions + 1
	# The eligibility trace, one term per decision. Credit for a reward is spread
	# back over everything the robot did before earning it, which is the only way
	# *walking towards the bin* is ever learned when only the sale pays.
	var grad := Policy.grad_log_prob(obs, chances, choice, n_in, LEARN_ACTIONS)
	Policy.add_into(extra["trace"], grad, 1.0)
	# **And the same term again, scaled by how much of the day is left in its
	# arms.** This is the trace the night charges the baseline against, and the
	# whole reason it is a second sum: a decision made on a full meter still has a
	# day's worth of work ahead of it, while one made on the last thirty units has
	# almost nothing ahead of it and should be measured against almost nothing.
	# Read before the action, because the action is what spends it.
	Policy.add_into(extra["base_trace"], grad,
		float(world.energy_of(actor_id)) / float(SimWorld.ACTOR_MAX_ENERGY))

	extra["pending"] = ""
	var action := _begin(world, actor_id, extra, tick, choice, gs)
	# Written last, after anything that moved it, so nothing can outlive it —
	# except an errand, which sets its own pace from the movement engine and is
	# the one thing that is *meant* to outlive the decision that started it.
	if String(extra.get("job", "")) == "":
		extra["wake"] = tick + SimClock.RATE
	return action


# What the chosen action does with the world it finds itself in: pick the square,
# start walking, or discover there is nothing to do.
#
# **A decision with no legal square is spent, and that is deliberate** — not a
# mask on the policy and not a re-roll. The robot has to learn *when* a verb is
# worth choosing, which is the whole of what the `bare`, `ripe`, `crow` and
# `needs_water` channels are for; a policy that could not choose wrongly would
# have nothing to learn from those channels at all.
func _begin(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		choice: int, gs) -> Dictionary:
	match choice:
		LEARN_WAIT:
			# A second of standing there. The cheapest thing it can do and the
			# only one that is never refused.
			return {}
		LEARN_WANDER:
			# One tile, taken directly — and deliberately **not** `Movement.plan`
			# followed by `Movement.step`. A route planned to an adjacent tile it
			# cannot enter comes back as having *arrived* there, and stepping a
			# route writes a path and a wake of its own into `extra`; either would
			# make a refused move indistinguishable from a taken one. A move it
			# cannot make is simply a move it did not make: nothing happens,
			# nothing is earned, and the decision is spent.
			#
			# A second draw, on the same decision number under a different salt,
			# because the first one is spoken for by the action itself.
			var salt: int = int(extra.get("salt", 0)) ^ (int(extra.get("days", 0)) * LEARN_DAY_STRIDE)
			var u := Policy.draw_u(salt ^ WANDER_SALT, int(extra.get("decisions", 0)))
			var step: Vector2i = LEARN_STEPS[mini(LEARN_STEPS.size() - 1,
					int(u * float(LEARN_STEPS.size())))]
			var to := world.actor_pos(actor_id) + step
			if Movement.can_enter(world, actor_id, to):
				Movement.place_on_tile(world, actor_id, to)
			return {}
		LEARN_SHOO:
			var bird := _bird_in_view(world, actor_id, extra)
			if bird == "":
				return {}
			extra["job"] = String(LEARN_VERBS[LEARN_SHOO])
			extra["job_target"] = bird
			return _chase_bird(world, actor_id, extra, tick)
		LEARN_SHIP:
			# The bin is a landmark, not something it has to find: the same two
			# numbers the observation already puts in its head
			# (`Observation.bin_tile`), so shipping is the one errand that can
			# take it right across the farm.
			if String(extra.get("carrying", "")) == "":
				return {}
			var bin := Observation.bin_tile(world)
			if bin.x < 0:
				return {}
			return _set_job(world, actor_id, extra, tick, LEARN_SHIP, bin,
				_beside(world, actor_id, bin), gs)
		_:
			var square := _nearest_legal(world, actor_id, extra, choice, gs)
			if square.x < 0:
				return {}
			return _set_job(world, actor_id, extra, tick, choice, square, square, gs)


# Take the errand on: stand on the square already, or set out for it.
#
# `at` is the square the verb is *for* and `stand` is the square the robot has to
# be on to do it. They are the same tile for the four that are done underfoot and
# they differ for shipping, where the bin cannot be walked onto.
func _set_job(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		choice: int, at: Vector2i, stand: Vector2i, gs) -> Dictionary:
	if stand.x < 0:
		return {}
	var verb := String(LEARN_VERBS[choice])
	if world.actor_pos(actor_id) == stand:
		# Already there: no errand is recorded at all, so `extra` never carries a
		# square the robot is not on its way to.
		return _do_job(world, actor_id, extra, verb, at, gs)
	# The mark-1's plumbing, unchanged: plan once, take the first step in the same
	# think, and let the engine's own pacing decide when this machine next looks
	# up. A square with no route to it is an errand that never starts.
	if _set_out(world, actor_id, extra, tick, stand) == "":
		return {}
	extra["job"] = verb
	extra["job_x"] = at.x
	extra["job_y"] = at.y
	if world.actor_pos(actor_id) == stand:
		return _arrive(world, actor_id, extra, tick, gs)
	return {}


# One tile of the walk. Every config above does this the same way — step while the
# route holds, throw it away when it does not — and the mark-3's only addition is
# that the errand ends when the walk does, one way or the other.
func _carry_on(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		gs) -> Dictionary:
	if String(extra.get("job", "")) == String(LEARN_VERBS[LEARN_SHOO]):
		return _chase_bird(world, actor_id, extra, tick)
	var stand := _goal(extra)
	if world.actor_pos(actor_id) == stand:
		return _arrive(world, actor_id, extra, tick, gs)
	if Movement.has_route(world, actor_id):
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				if world.actor_pos(actor_id) == stand:
					return _arrive(world, actor_id, extra, tick, gs)
				return {}   # the engine set the next wake from the speed row
			_:
				Movement.clear_route(world, actor_id)
	# Blocked or out of route with the square still out of reach — a hen parked in
	# the gateway, ground that changed while it was walking. The errand is
	# abandoned rather than retried, which is the mark-1's answer to the same
	# thing: the decision is gone, and the next one is a fresh look at the farm.
	return _abandon(world, actor_id, extra, tick)


# It is standing where the errand wanted it. Do the verb and go back to thinking.
func _arrive(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		gs) -> Dictionary:
	var verb := String(extra.get("job", ""))
	var at := Vector2i(int(extra.get("job_x", -1)), int(extra.get("job_y", -1)))
	_drop_job(world, actor_id, extra)
	extra["wake"] = tick + SimClock.RATE
	return _do_job(world, actor_id, extra, verb, at, gs)


# The errand is over without a verb: nothing emitted, nothing earned, and a fresh
# decision a second from now. The decision itself was spent when it was taken.
func _abandon(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
	_drop_job(world, actor_id, extra)
	extra["wake"] = tick + SimClock.RATE
	return {}


func _drop_job(world: SimWorld, actor_id: String, extra: Dictionary) -> void:
	extra["job"] = ""
	extra["job_x"] = -1
	extra["job_y"] = -1
	extra["job_target"] = ""
	Movement.clear_route(world, actor_id)
	_aim(extra, Vector2i(-1, -1))


# --- doing the thing ------------------------------------------------------------

# The Action itself, and the one fact only the brain holds: what this stroke would
# be worth if the gateway says yes.
#
# **Legality is asked again here, one beat before the verb goes out.** The square
# was chosen when the decision was taken and the walk took seconds; a hen may have
# eaten the acorn, the rain may have wetted the soil, she may have harvested the
# row herself. A square that has stopped answering the verb is an errand that ends
# quietly, exactly as a mark-1's round walks to a tile and finds nothing to do.
#
# **What it would earn is read *before* the stroke, never after it.** By the time
# the gateway has answered, the tile is wet either way, open either way, cut
# either way — a robot scored on the state afterwards would be a robot scored for
# the gesture (P-14's first rule).
func _do_job(world: SimWorld, actor_id: String, extra: Dictionary, verb: String,
		at: Vector2i, gs) -> Dictionary:
	var state := String(world.get_tile(at.x, at.y).get("state", ""))
	match verb:
		"till":
			# **A robot swings the hoe where she could swing it, and nowhere else
			# — the same answer the router gives her.** Her tap is resolved by
			# `Tools.get_action(tool, tile_state)`, and that table lets the hoe act
			# on `cleared` ground and on nothing else, so there is no tap in the
			# game that hoes sown wheat back into mud. The gateway is looser than
			# the table — it refuses `till` only on the yard and the home's floor
			# — so a robot that asked it directly could undo a crop the player has
			# no practical way to undo, which is a machine behaving unlike the
			# hands that taught it.
			if Tools.get_action(Tools.index_of_key(HOE_KEY), state) != "till":
				return {}
			extra["pending"] = "tilled"
		"plant":
			var seed := _best_seed(gs)
			if seed == "" or Tools.get_action(Tools.index_of_key(SEEDS_KEY), state) != "plant":
				return {}
			extra["pending"] = "planted"
			return { "verb": verb, "target": at, "actor": actor_id, "seed_type": seed }
		"water":
			# Asked through `order_verb` so the mark-1's idea of a square that
			# wants water and the mark-3's cannot drift apart.
			if order_verb(world, at) != "water":
				return {}
			# **Two rows for one stroke** (Q-100). Water onto something growing is
			# worth ten times water onto empty soil, because the first keeps a crop
			# alive and the second only leaves the ground one step better placed.
			# Nobody owns the square: a plant she sowed and one the robot sowed pay
			# exactly the same.
			extra["pending"] = "watered_plant" if world.has_crop(at.x, at.y) \
					or world.has_seed(at.x, at.y) else "watered_soil"
		"harvest":
			# Hands, on a ripe square, with nothing in them already — the router's
			# rule and the gateway's refusal, asked before the walk was worth
			# anything and again now.
			if Tools.get_action(Tools.index_of_key(HANDS_KEY), state) != "harvest" \
					or String(extra.get("carrying", "")) != "":
				return {}
			extra["pending"] = "harvested"
		"sell":
			if String(extra.get("carrying", "")) == "":
				return {}
			extra["pending"] = "shipped"
		_:
			return {}
	# The bin's own square goes out with a `sell` even though the gateway never
	# reads it, because it is what her tap sends (`ActionRouter.SPECIAL_OBJECTS`)
	# and because it is where a watching player should see and hear the crop
	# change hands (`world/farm.gd`'s verb cues).
	return { "verb": verb, "target": at, "actor": actor_id }


# The nearest square in view this verb is legal on, or (-1, -1).
#
# **The router's rule, the router's reach and the router's tie-break.** Manhattan
# distance, a fixed scan order from the top-left of the patch, and a candidate is
# only taken on a **strictly** smaller distance — so two squares the same distance
# away resolve the same way on every machine and in every replay. The patch is the
# robot's own vision radius, which is the same 5×5 it is given as numbers, so
# there is never a square it acts on that it could not see.
func _nearest_legal(world: SimWorld, actor_id: String, extra: Dictionary,
		choice: int, gs) -> Vector2i:
	var here := world.actor_pos(actor_id)
	var r := _view_radius(extra)
	# Her box is asked once for the whole patch, not once per square: it is a fact
	# about the farm rather than about the tile, and twenty-five walks down a
	# dictionary inside one think is exactly the per-decision cost ground rule 8
	# is about.
	var seed := _best_seed(gs) if choice == LEARN_PLANT else ""
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d: int = absi(dx) + absi(dy)
			if d >= best_d:
				continue
			var t := here + Vector2i(dx, dy)
			if not _legal_at(world, extra, choice, t, seed):
				continue
			best_d = d
			best = t
	return best


# Would her tap on this square resolve to this action's verb?
#
# One table, `systems/tools.gd`, asked exactly as `ActionRouter` asks it — plus
# the two facts the router reads off her instead of off the ground: whether there
# is a seed in the box (`seed`, already looked up by the caller) and whether the
# hands are already full.
func _legal_at(world: SimWorld, extra: Dictionary, choice: int, t: Vector2i,
		seed: String) -> bool:
	var state := String(world.get_tile(t.x, t.y).get("state", ""))
	if state == "":
		return false   # off the map, or a square nobody generated
	match choice:
		LEARN_TILL:
			return Tools.get_action(Tools.index_of_key(HOE_KEY), state) == "till"
		LEARN_PLANT:
			# Her tap offers the seed only when she has one, and so does this: an
			# empty box is a `plant` with no legal square anywhere, which is the
			# same spent decision as a hoe with no bare ground in sight.
			return seed != "" \
					and Tools.get_action(Tools.index_of_key(SEEDS_KEY), state) == "plant"
		LEARN_WATER:
			return order_verb(world, t) == "water"
		LEARN_HARVEST:
			return Tools.get_action(Tools.index_of_key(HANDS_KEY), state) == "harvest" \
					and String(extra.get("carrying", "")) == ""
	return false


# A square the robot can stand on next to the bin, nearest first. The bin has an
# object on it, so it is the one errand whose destination is not the square the
# verb is about — she reaches for it from beside it too.
func _beside(world: SimWorld, actor_id: String, at: Vector2i) -> Vector2i:
	var here := world.actor_pos(actor_id)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var mode := Movement.mode_of(world.species_of(actor_id))
	for d in LEARN_STEPS:
		var t: Vector2i = at + d
		if not Movement.can_stop(world, mode, t) or not Movement.can_enter(world, actor_id, t):
			continue
		var dist := _manhattan(t, here)
		if dist < best_d:
			best_d = dist
			best = t
	return best


# Which seed comes out of her box: the one she has most of, ties going to the
# order the box itself is written in. **Not a thing the robot learns** — the
# design gives it one number for the box ("is there anything to sow"), and which
# kind is the brain's business, exactly as which square is.
static func _best_seed(gs) -> String:
	if gs == null or not ("seeds" in gs):
		return ""
	var best := ""
	var most := 0
	for key in gs.seeds.keys():
		var n := int(gs.seeds[key])
		if n > most:
			most = n
			best = String(key)
	return best


# --- the chase ------------------------------------------------------------------

# The nearest bird standing inside the robot's own patch, or "".
#
# A pass over the birds in the registry rather than over the patch: there is at
# most one crow in a day of phase 1, and the registry is a short list whatever the
# size of the farm (ground rule 8). Ids come back sorted and a bird is only taken
# on a **strictly** smaller distance, so two equidistant birds resolve the same
# way every time. The class is the same one the `crow` channel is drawn from, so
# what the robot can see and what it may chase are one list.
func _bird_in_view(world: SimWorld, actor_id: String, extra: Dictionary) -> String:
	var here := world.actor_pos(actor_id)
	var r := _view_radius(extra)
	var best := ""
	var best_d := 1 << 30
	for id in world.actors_of_class(SpeciesDefs.CLASS_BIRD):
		if id == actor_id:
			continue
		var at: Vector2i = world.actor_pos(id)
		if absi(at.x - here.x) > r or absi(at.y - here.y) > r:
			continue
		var d := _manhattan(at, here)
		if d < best_d:
			best_d = d
			best = id
	return best


# Walking a bird down. The mark-2's `_chase` with its patch radius swapped for a
# chase length: this machine has no patch, so what bounds the errand is how far it
# will follow rather than where it is allowed to be.
func _chase_bird(world: SimWorld, actor_id: String, extra: Dictionary,
		tick: int) -> Dictionary:
	var target := String(extra.get("job_target", ""))
	if target == "" or not world.has_actor(target):
		return _abandon(world, actor_id, extra, tick)   # it left on its own
	var tiles := Movement.occupied_tiles(world, target)
	if tiles.is_empty():
		return _abandon(world, actor_id, extra, tick)
	if world.actor_pos(actor_id) in tiles:
		return _reach_bird(world, actor_id, extra, tick, target)
	var head: Vector2i = tiles[0]
	if _manhattan(head, world.actor_pos(actor_id)) > SHOO_CHASE_TILES:
		# That one got away. A crow in the air is half again as fast as the bot,
		# so this is the ordinary end of a chase that started while it was still
		# coming in — and the reason the birds a mark-3 actually catches are the
		# ones that have landed.
		return _abandon(world, actor_id, extra, tick)
	if Movement.has_route(world, actor_id) and _goal(extra) == head:
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				if world.actor_pos(actor_id) in Movement.occupied_tiles(world, target):
					return _reach_bird(world, actor_id, extra, tick, target)
				return {}
			_:
				Movement.clear_route(world, actor_id)
	# Re-aim at where it is now. Once per step it takes, not once per tick — a
	# bird in the air moves every tick and a machine walking after it does not get
	# to think faster than it walks. Re-aiming is not a decision: no draw is taken
	# and no reward can come of it, so the day's arithmetic never sees it.
	if _set_out(world, actor_id, extra, tick, head) == "":
		return _abandon(world, actor_id, extra, tick)
	if world.actor_pos(actor_id) in Movement.occupied_tiles(world, target):
		return _reach_bird(world, actor_id, extra, tick, target)
	return {}


# It is standing on the bird. What happens next is the **quarry's** answer, not
# the bot's — `_reached` above says the whole of why — so this files the crow's
# own `crow_scared` report and the visit ends exactly as it ends when the player
# walks over. The bot gains no verb by doing it.
#
# Two birds get nothing out of this and both are honest: a songbird has no report
# to make (it has no verbs at all), and a crow already on its way out cannot be
# frightened twice. The second is the one worth stating, because it is the
# difference between a reward and a way to farm one: a bird that is leaving is a
# bird somebody has already scared.
func _reach_bird(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		target: String) -> Dictionary:
	_drop_job(world, actor_id, extra)
	extra["wake"] = tick + SimClock.RATE
	if not SpeciesDefs.may(world.species_of(target), "crow_scared"):
		return {}
	var state := String(world.actor(target).get("extra", {}).get("state", ""))
	if state == "leaving":
		return {}
	# **Three points for a bird caught eating and one for a bird turned back**
	# (Q-100), read at the moment of the scare because the report is what ends the
	# visit — a beat later this bird's state is "leaving" whatever it was doing.
	extra["pending"] = "crow_eating" if state == "eating" else "crow_flying"
	return {
		"verb": "crow_scared",
		"target": world.actor_pos(target),
		"actor": target,
		# Who did the frightening. The gateway reads it for the *kind* of cause
		# (a person or a machine) rather than for whose proof it is — Q-66 is
		# ruled and the credit is hers either way — and it is what makes a bot's
		# work legible in the replay corpus phase 4 trains on.
		"by": actor_id,
	}


# --- small shared answers --------------------------------------------------------

# How far this robot can see, in tiles. Off its own spec, never off the default:
# a machine keeps the senses it was born with (see `deploy`), so a later build
# that widens the patch must not widen the reach of a robot trained on the old one.
func _view_radius(extra: Dictionary) -> int:
	var spec: Dictionary = extra.get("spec", {})
	return maxi(0, int(spec.get("vision", Observation.DEFAULT_VISION)))


# A day's score split by row, all zeros. One place that knows how many rows there
# are, and it is the reward table.
static func _new_split() -> Array:
	var out: Array = []
	out.resize(Rewards.KEYS.size())
	out.fill(0.0)
	return out


# The night: one update, and a clean slate for the morning.
#
# `w += rate · (acc − baseline · base_trace) / decisions`, and **the division is
# load-bearing**. The trace is cumulative, so the accumulator grows with roughly
# the square of how many decisions were in the day; without dividing, a busy day
# would push the weights hundreds of times harder than a quiet one and the robot
# would lock onto whatever it happened to be doing when it first got lucky. WI-2
# measured exactly that on a twenty-decision bandit; a robot's day has several
# hundred.
#
# The baseline is the running mean of every day before this one. Subtracting it
# is what stops a robot that scores the same every day from being shoved harder
# and harder in whatever direction it took first: once a day is only average, it
# teaches nothing.
#
# **What it is charged against is `base_trace`, not `trace`, and that fix is the
# difference between a robot that learns and one that gives up** (v0.2.1 WI-6).
# `acc` credits each decision with the rewards that came *after* it, so a
# decision taken on the last of the meter is credited with nearly nothing —
# correctly, because there was nearly nothing left to earn. Charging every
# decision the whole day's mean anyway made the late half of every day look like
# a failure, so the average decision was pushed away from itself by about half
# the baseline, and the only thing holding off a robot that settled on standing
# still was a rate small enough to make the whole night barely count. `base_trace`
# weights each decision's charge by the meter it had left, which is roughly what
# it could still have earned, so a decision is now measured against its own share
# of an average day rather than against all of one.
func _sleep_on_it(extra: Dictionary) -> void:
	var weights: Array = extra.get("weights", [])
	var per_decision := 1.0 / float(maxi(1, int(extra.get("decisions", 0))))
	var days := int(extra.get("days", 0))
	var baseline := float(extra.get("baseline", 0.0))
	var score := float(extra.get("score", 0.0))
	extra["weights"] = Policy.night_update(weights,
		_scaled(extra.get("acc", []), per_decision),
		_scaled(extra.get("base_trace", []), per_decision),
		baseline, LEARN_RATE)
	extra["baseline"] = (baseline * float(days) + score) / float(days + 1)
	# What the panel shows her, and the only two learned numbers anything outside
	# this file reads (Q-97: the night's surface is panel numbers, no scene).
	extra["last_score"] = score
	extra["days"] = days + 1
	# ...and the slate. A day's sums belong to that day.
	extra["score"] = 0.0
	extra["decisions"] = 0
	extra["trace"] = _scaled(weights, 0.0)
	extra["acc"] = _scaled(weights, 0.0)
	extra["base_trace"] = _scaled(weights, 0.0)
	extra["earned"] = _new_split()
	extra["pending"] = ""


# `source * k`, as a fresh plain Array of float — the shape the night needs and
# the shape `extra` keeps. With `k` of 0 it is also how the two running sums are
# zeroed back to the right length, so there is one place that knows how long they
# are and it is the weights.
static func _scaled(source: Array, k: float) -> Array:
	var out: Array = []
	out.resize(source.size())
	out.fill(0.0)
	Policy.add_into(out, source, k)
	return out


# A new morning gives a mark-1 its turn back (2026-09-03). Also stands down a
# round that never finished — she went to bed with it halfway along its list —
# because "once per day" has to mean the day it was sent, not a queue that
# survives the night.
# **The morning routine, which is the whole point of the stall** (CEO, 2026-09-06:
# a robot she buys, parks, teaches, and which then *works*). A mark-1 that lives in
# a stall and has been taught a round is sent out as the day turns, with nobody
# tapping anything: the machine has an address, a list and a turn it has not used,
# and those three facts are the instruction.
#
# **A bot on open ground is untouched.** It still needs the daily "send it out" tap
# it has always needed — which is what the stall is *for*, and is why an 80g shed
# is worth buying at all.
#
# It decides nothing (P-13 holds): it repeats the list she taught it, in her order,
# and stops. The Action is the `activate` verb she taps herself, put through the
# same gateway, so a bot gets no capability the player lacks — and being an Action
# at the day turn is what makes it **recomputed rather than recorded** (Q-53, the
# sprinkler's seat): a replay re-applies the one `sleep` entry, this runs inside
# it, and the corpus does not grow a verb nobody performed.
func day_actions(world: SimWorld, actor_id: String, _gs = null) -> Array[Dictionary]:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return []
	var extra: Dictionary = e["extra"]
	if String(extra.get("config", "")) != CONFIG_ORDERS:
		return []
	# Its turn is spent, or it is already out — either way the morning has nothing
	# to add. (`on_new_day` has already run by the time `advance_day` gets here, so
	# on an ordinary morning both of these are false.)
	if bool(extra.get("sent", false)) or bool(extra.get("ran_today", false)):
		return []
	if orders_of(extra).is_empty():
		return []
	# A home, and it has to be a stall: `home_x`/`home_y` is also the middle of a
	# shoo bot's patch, and a patch is not an employer. Read off the grid, so a
	# stall she picked up (which v1 cannot do) or a save from before it existed
	# leaves the machine on the manual routine rather than in a routine with no
	# building behind it.
	var home := _home(extra)
	if home.x < 0 or not world.is_stall_tile(home):
		return []
	# Aimed at where it is *standing*, not at its stall: it may have been caught out
	# in the field at bedtime, and a machine that failed to get home last night
	# still has a job this morning. `activate` finds the machine under the tile.
	return [{ "verb": "activate", "target": world.actor_pos(actor_id), "actor": actor_id }]


func on_new_day(world: SimWorld, actor_id: String) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	var extra: Dictionary = e["extra"]
	# The mark-3's night, **before** the mark-1's early return below rather than
	# after it: this hook is the one moment in the day when a learning robot's
	# weights change, and a guard written for the config that shipped first would
	# have quietly meant "and no other config has a night" (v0.2.1 WI-4).
	if String(extra.get("config", "")) == CONFIG_LEARN:
		_sleep_on_it(extra)
		# ...and the errand it was halfway through when she went to bed is over
		# too. A morning is a fresh look at the farm: the square it was walking to
		# may have been harvested, watered or fenced off overnight, and a machine
		# that resumed yesterday's walk would be acting on a farm that no longer
		# exists (the mark-1's round is stood down for the same reason, below).
		_drop_job(world, actor_id, extra)
		return
	if String(extra.get("config", "")) != CONFIG_ORDERS:
		return
	extra["ran_today"] = false
	extra["sent"] = false
	extra["at_order"] = 0
	Movement.clear_route(world, actor_id)


# --- what the gateway made of it ------------------------------------------------

# The one Action a bot in the mark-2's three configs ever takes is the shoo's
# report, and the only way it fails is a world without a GameState in it. Either
# way the chase is over and the machine is already on its way home (`_reached`
# stood it down before the Action left), so there is nothing to undo. A mark-1's
# waterings are the same: the index has already moved on, and a refused order is
# still an order it has been through.
#
# **The mark-3 is the one bot that cares what the gateway said**, because for a
# machine that learns, the answer *is* the lesson. It is scored on the outcome and
# not on the stroke (P-14, `systems/rewards.gd`), and the outcome is two facts
# together: what the square (or the bird) was one beat *before* the verb went out,
# which only the brain still knows, and whether the gateway then said yes.
#
# The first is `extra["pending"]` — the name of the row of `Rewards.TABLE` this
# errand was reaching for, written by `_do_job` just before the Action left. By
# the time this function runs the tile is wet, or open, or cut, and the bird is
# leaving, so nothing here could work it out from the world. The second is
# `result.ok`. Watering wet ground, hoeing the yard, selling with empty hands,
# reaching a bird that had already been frightened: every one of them is worth
# what waiting is worth, which is nothing.
#
# Nothing here special-cases where a robot may work — that rule is the gateway's
# and the router's, and it binds a machine exactly as it binds her (ground rule 1).
#
# The reward is folded into the accumulator against the **whole trace so far**,
# not against this one decision. That is what pays the walk that got it there —
# and with a decision now being a whole errand, the walk *is* most of the day.
func on_result(world: SimWorld, actor_id: String, action: Dictionary,
		result: Dictionary) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	var extra: Dictionary = e["extra"]
	if String(extra.get("config", "")) != CONFIG_LEARN:
		return
	var pending := String(extra.get("pending", ""))
	extra["pending"] = ""
	if pending == "" or not bool(result.get("ok", false)):
		return
	# A harvest of a square with nothing on it is accepted by the gateway and cuts
	# nothing at all — `crop_type` is what says a crop actually came up, and it is
	# the same fact `world/farm.gd` uses to decide whether to play the sound.
	if String(action.get("verb", "")) == "harvest" and not result.has("crop_type"):
		return
	var earned := Rewards.of(pending)
	if earned == 0.0:
		return
	Policy.add_into(extra["acc"], extra["trace"], earned)
	extra["score"] = float(extra.get("score", 0.0)) + earned
	# ...and the same point again in its own column, so a week can say which of
	# the eight rows it actually reached. Report only; nothing decides on it.
	var split: Array = extra.get("earned", [])
	var slot := Rewards.index_of(pending)
	if slot >= 0 and slot < split.size():
		split[slot] = float(split[slot]) + earned


# --- shared plumbing ------------------------------------------------------------

# Where the actor this bot belongs to is standing. **Her live registry tile**,
# which is sim truth since WI-6 — the whole line depends on that and on nothing
# else about her.
func _owner_tile(world: SimWorld, extra: Dictionary) -> Vector2i:
	var owner := String(extra.get("owner", SimWorld.ACTOR_PLAYER))
	if not world.has_actor(owner):
		return Vector2i(-1, -1)
	return world.actor_pos(owner)


# How far another actor is from a point, measured over **every tile it occupies**
# rather than its registry position (WI-8d/8e's handoff: `actor_pos` would miss
# two thirds of a worm). One tile for everything with wings, which is what makes
# this free for the case that exists today.
func _distance_to(world: SimWorld, actor_id: String, from: Vector2i) -> float:
	var best := INF
	for t in Movement.occupied_tiles(world, actor_id):
		best = minf(best, Vector2(t - from).length())
	return best


# Candidates nearest first, ties broken by the order they were found in — a
# selection pass rather than `sort_custom`, because the tie-break is what makes a
# station the *same* station in a replay and Godot's sort makes no such promise.
func _nearest_first(tiles: Array[Vector2i], from: Vector2i) -> Array[Vector2i]:
	var pool: Array[Vector2i] = tiles.duplicate()
	var out: Array[Vector2i] = []
	while not pool.is_empty():
		var best := 0
		for i in range(1, pool.size()):
			if _manhattan(pool[i], from) < _manhattan(pool[best], from):
				best = i
		out.append(pool[best])
		pool.remove_at(best)
	return out


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# Which entry of a fixed list is nearest a tile. First one wins a tie, which is
# the ring's own order and therefore the same answer everywhere.
func _nearest_index(tiles: Array[Vector2i], from: Vector2i) -> int:
	var best := 0
	for i in range(1, tiles.size()):
		if _manhattan(tiles[i], from) < _manhattan(tiles[best], from):
			best = i
	return best


# The tile it is currently walking to. Kept in `extra` because the engine holds a
# route rather than a destination, and every config here has to be able to ask
# "is where I am going still where I want to go".
func _goal(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("goal_x", -1)), int(extra.get("goal_y", -1)))


func _aim(extra: Dictionary, t: Vector2i) -> void:
	extra["goal_x"] = t.x
	extra["goal_y"] = t.y


func _home(extra: Dictionary) -> Vector2i:
	return Vector2i(int(extra.get("home_x", -1)), int(extra.get("home_y", -1)))


# Plan a route and **take its first step in the same think**. Returns
# `Movement.MOVED` / `BLOCKED`, or `""` when there is no route at all.
#
# The immediate step is not an optimisation, it is the difference between a
# follow bot and a bot that stands still watching her leave. Every other brain in
# the game plans on one think and steps on the next, which costs a beat and costs
# nothing else — their goals do not move. A bot's goal is a person: by the time
# the next think came round she had walked on, the station had gone stale, and it
# re-planned instead of stepping. Written that way first, and it produced a
# machine that pointed at her very accurately from a great distance.
func _set_out(world: SimWorld, actor_id: String, extra: Dictionary, tick: int,
		goal: Vector2i) -> String:
	if not Movement.plan(world, actor_id, goal):
		return ""
	_aim(extra, goal)
	var result := Movement.step(world, actor_id, tick)
	if result != Movement.MOVED:
		# Blocked on the first tile of a route it just planned — something walked
		# into it. Try again at its own pace rather than spinning.
		_paced(world, actor_id, extra, tick)
	return result


# The pace of a step, from the species' own speed — the grazer's line, and it
# must stay this rather than `tick + 1`: `Movement.step` moves a tile whenever it
# is called, so the wake *is* the speed.
func _paced(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> void:
	extra["wake"] = tick + Movement.ticks_per_tile(world.species_of(actor_id))


func _wait(extra: Dictionary, tick: int) -> void:
	extra["wake"] = tick + ticks(POLL_SECONDS)


func _rest(extra: Dictionary, tick: int) -> void:
	extra["wake"] = tick + ticks(SimRng.randf_range(float(PATROL_IDLE[0]), float(PATROL_IDLE[1])))

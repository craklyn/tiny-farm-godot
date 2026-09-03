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
const CONFIG_ORDERS := "orders"

const CONFIG_FOLLOW := "follow"
const CONFIG_CIRCLE := "circle"
const CONFIG_SHOO := "shoo"
# The mark-2's three. Named as they always were, because the zoo, the tests and
# `MachineDefs` all mean *these* by "the configs a bot can be set to".
const CONFIGS: Array[String] = [CONFIG_FOLLOW, CONFIG_CIRCLE, CONFIG_SHOO]
# ...and every config the brain answers for, mark-1 included.
const ALL_CONFIGS: Array[String] = [CONFIG_ORDERS, CONFIG_FOLLOW, CONFIG_CIRCLE, CONFIG_SHOO]

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

func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return {}
	var extra: Dictionary = e["extra"]
	match String(extra.get("config", CONFIG_FOLLOW)):
		CONFIG_ORDERS:
			return _orders(world, actor_id, extra, tick)
		CONFIG_CIRCLE:
			_circle(world, actor_id, extra, tick)
		CONFIG_SHOO:
			return _shoo(world, actor_id, extra, tick)
		_:
			_follow(world, actor_id, extra, tick)
	return {}


# --- the mark-1: exact orders, once a day --------------------------------------
#
# The list is `extra.orders`; the position in it is `extra.at_order`; whether it
# is out is `extra.sent`. There is nothing else, and that is the design.
#
# **It never re-decides.** It walks to order N, waters order N, moves to order
# N+1, and stops at the end of the list. A tile it cannot reach — she fenced it
# off, a hen is parked on it and will not move, she tore the plot up after
# teaching it — is *skipped*, not queued, not retried, not replaced with a
# nearer one. That is what "exact orders" means from the machine's side, and it
# is what makes a mark-1 legibly stupid rather than mysteriously stuck: the
# failure mode a player sees is "it missed that one", which is a thing she can
# fix by teaching it again.
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
		return { "verb": "water", "target": goal, "actor": actor_id }

	if Movement.has_route(world, actor_id) and _goal(extra) == goal:
		match Movement.step(world, actor_id, tick):
			Movement.MOVED:
				if world.actor_pos(actor_id) == goal:
					extra["at_order"] = at + 1
					_paced(world, actor_id, extra, tick)
					return { "verb": "water", "target": goal, "actor": actor_id }
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


# The end of the round: it is not out any more, and it has had its turn today.
func _round_done(world: SimWorld, actor_id: String, extra: Dictionary, tick: int) -> Dictionary:
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


# A new morning gives a mark-1 its turn back (2026-09-03). Also stands down a
# round that never finished — she went to bed with it halfway along its list —
# because "once per day" has to mean the day it was sent, not a queue that
# survives the night.
func on_new_day(world: SimWorld, actor_id: String) -> void:
	var e: Dictionary = world.actor(actor_id)
	if e.is_empty():
		return
	var extra: Dictionary = e["extra"]
	if String(extra.get("config", "")) != CONFIG_ORDERS:
		return
	extra["ran_today"] = false
	extra["sent"] = false
	extra["at_order"] = 0
	Movement.clear_route(world, actor_id)


# --- what the gateway made of it ------------------------------------------------

# The one Action a bot in these three configs ever takes is the shoo's report, and
# the only way it fails is a world without a GameState in it. Either way the chase
# is over and the machine is already on its way home (`_reached` stood it down
# before the Action left), so there is nothing to undo — this exists to say that
# out loud, because every other brain in the game corrects itself here and a
# reader will look.
func on_result(_world: SimWorld, _actor_id: String, _action: Dictionary,
		_result: Dictionary) -> void:
	pass


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

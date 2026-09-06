# vignette.gd — the wordless onboarding beats (T-3/T-4/T-5, Q-33; Q-9 originally)
#
# Progress is derived purely from world + GameState — **no saved fields, no
# flags**: the farm IS the tutorial's memory, so it survives relaunches, saves
# and replays for free. That property is load-bearing; if a beat cannot be
# derived cheaply from world state, that is a design smell rather than a reason
# to add a flag.
#
# What changed at M1.5 (Q-33): the old vignette opened on a **weed** — a chore,
# and the least motivating verb in the game — and taught three verbs and zero
# goals. A player who finished it had learned which pixels respond, not what the
# game is for. The chain is now taught **backwards from the harvest**: day 1
# opens on a ripe crop the neighbour left behind, so the player is paid before
# she is asked for anything, and every later beat answers a question she now
# actually has ("where do more of those come from?").
#
# Days are counted in **play-days** (GameState.play_day()), not absolute days:
# the cold open spends real days before she owns anything.
class_name VignetteState

# Day 1: harvest → plant → water → sleep. Day 2: harvest again → plant the row
# together → till one new tile. Then silence, for good.
const LAST_TAUGHT_PLAY_DAY := 2


static func _gate(world: SimWorld) -> Vector2i:
	for p in WorldLayout.parcels(world.layout):
		if String(p.get("opened_by", "")) == WorldLayout.OPENED_BY_COLD_OPEN:
			return p.get("gate", Vector2i(-1, -1))
	return Vector2i(-1, -1)


static func _gate_open(world: SimWorld) -> bool:
	var g := _gate(world)
	if g.x < 0:
		return false
	return String(world.get_tile(g.x, g.y).get("state", "")) == WorldLayout.GATE_OPEN


# The rows a scan is allowed to look at: **the page she is standing on**, or the
# whole grid when there is no position to scope by (2026-09-06, the door).
#
# The world is two maps stacked in one grid now, and a scan that ignored that
# would let a beat point through a wall — an arrow pinned to the edge of the
# screen aiming at a ripe crop on the farm while she is standing in her bedroom,
# or a highlight glowing in a room nobody is in. Half-open, `[y, y)`, so it drops
# straight into a `range`.
static func page_rows(world: SimWorld, player_t: Vector2i) -> Vector2i:
	if player_t.x < 0:
		return Vector2i(0, SimWorld.MAP_HEIGHT)
	var page: int = world.page_of(player_t)
	return Vector2i(page * SimWorld.PAGE_ROWS, (page + 1) * SimWorld.PAGE_ROWS)


static func _all_with_state(world: SimWorld, want: String, rows: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in range(rows.x, rows.y):
		for tx in SimWorld.MAP_WIDTH:
			if String(world.tiles[ty][tx].get("state", "")) == want:
				out.append(Vector2i(tx, ty))
	return out


static func _dry_crops(world: SimWorld, rows: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in range(rows.x, rows.y):
		for tx in SimWorld.MAP_WIDTH:
			var t: Dictionary = world.tiles[ty][tx]
			var st := String(t.get("state", ""))
			if (st == "seeded" or st == "growing") and not t.get("watered_today", false):
				out.append(Vector2i(tx, ty))
	return out


static func _has_seeds(gs) -> bool:
	for c in gs.seeds.values():
		if int(c) > 0:
			return true
	return false


# The beats, as an array of tiles — an array because day 2's whole point is that
# several tiles glow **together**, which is the first honest read on whether
# swipe-chaining a row feels right (the open sub-question left over from Q-30).
#
# `player_t` is live position, not saved state: it is only used to tell whether
# she is standing home-side, which arms beat 0 — but only until the first
# crossing. That completion is the one fact the world cannot re-derive (where
# she has *ever* stood is history, not state), so it lives as a latch on her
# sim registry entry (`SimWorld.player_left_yard`, T-35) — the same place her
# position does — rather than as a flag here.
static func target_tiles(world: SimWorld, gs, player_t: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	# While the cold open is still running, the neighbour is the show.
	if not _gate_open(world):
		return none

	var play: int = gs.play_day() if gs.has_method("play_day") else gs.day
	if play > LAST_TAUGHT_PLAY_DAY:
		return none

	# Every scan below is over the page she is on and no other (see `page_rows`).
	var rows := page_rows(world, player_t)

	# Beat 0 — the handoff. The gate she has not yet walked through is the only
	# target; the ripe crop beyond it is the reason to.
	#
	# T-35: **and it latches.** "Has she walked through it" used to be read off
	# her current tile — standing home-side meant the beat re-armed, so at her
	# first prompted bedtime the gate outglowed the cot and pointed her out of
	# the yard (playtests/2026-08-31_233943). The latch is sim truth on her
	# registry entry (set where her tile is written), so it survives saves and
	# reproduces in replays; once she has ever left the yard, this beat is
	# complete forever and the yard is allowed to ask her to bed.
	if player_t.x >= 0 and not world.player_left_yard():
		var here: Dictionary = WorldLayout.parcel_at(player_t, world.layout)
		if String(here.get("id", "")) == "yard":
			var g := _gate(world)
			if g.x >= 0:
				var gate_only: Array[Vector2i] = [g]
				return gate_only

	# Beat 1 / beat 5 — a ripe crop, and it cannot fail, cannot be refused and
	# costs nothing but a tap. The safest possible room (Valve principle 2).
	var ready := _all_with_state(world, "ready", rows)
	if not ready.is_empty():
		var first_ready: Array[Vector2i] = [ready[0]]
		return first_ready

	var tilled := _all_with_state(world, "tilled", rows)
	var dry := _dry_crops(world, rows)

	if play == 1:
		# Beat 2 — plant. Fires only while the neighbour's single seeded tile is
		# the only one there is; the moment the player adds hers, the beat is
		# spent. Derived from the takeover contract rather than from a counter,
		# which is what keeps this state machine flag-free — and it is honest
		# about being an *authored opening* rather than a general rule.
		var seeded := _all_with_state(world, "seeded", rows)
		if seeded.size() <= 1 and not tilled.is_empty() and _has_seeds(gs):
			var one_tilled: Array[Vector2i] = [tilled[0]]
			return one_tilled
		# Beat 3 — water the thing she just planted.
		if not dry.is_empty():
			var one_dry: Array[Vector2i] = [dry[0]]
			return one_dry
		# Beat 4 — bed, once nothing else is asking. T-4: this is what turns "I did
		# some things" into "I did some things *and then something happened*", and
		# the day-1 phase ends by **sleeping** rather than by the day counter
		# reaching a magic number.
		#
		# **The way to bed, not the bed** (2026-09-06). The cot is in a room now, so
		# from the yard the beat points at the front door and from inside it points
		# at the bed — one answer, asked of the sim (`way_to_bed`), shared with the
		# dusk glow and the HUD's bed button so the three cannot drift apart. This
		# is also what keeps T-35's promise intact under the move: asked from the
		# yard at bedtime, the beat still says "go to bed" and never re-arms the
		# gate. A caller with no position to offer is answered from the farm, which
		# is where every other beat lives.
		var bed_way := world.way_to_bed(player_t if player_t.x >= 0 else Vector2i(0, 0))
		if bed_way.x >= 0:
			var bed_only: Array[Vector2i] = [bed_way]
			return bed_only
		return none

	# Play-day 2 — the payoff. Day 1 taught four gestures; today reveals that
	# they were one causal chain.
	# Beat 6 — the half-prepared row, highlighted **together** rather than one at
	# a time: the first invitation to chain a swipe along a row.
	if tilled.size() >= 2 and _has_seeds(gs):
		return tilled
	# Beat 7 — and then water what she just planted, again as a group.
	if not dry.is_empty():
		return dry
	# Beat 8 — one new verb, and only one: till. The chain extends one link
	# backwards, cleared → tilled → seeded → ripe.
	var plot: Dictionary = world.layout.get("neighbour_plot", {})
	for t in plot.get("cleared", []):
		if String(world.get_tile(t.x, t.y).get("state", "")) == "cleared":
			var one_cleared: Array[Vector2i] = [t]
			return one_cleared
	return none


static func is_active(world: SimWorld, gs, player_t: Vector2i = Vector2i(-1, -1)) -> bool:
	return not target_tiles(world, gs, player_t).is_empty()

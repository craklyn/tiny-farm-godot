# sim_world.gd — Grid-truth simulation state (S-5, M2)
# Owns the farm's tile/object grids and every mutation of them; apply_action()
# is the single gateway every actor (player, crow, chicken, later bots) uses
# to change the world (S-3).
# Layer-2 rules (docs/ARCHITECTURE.md): no Node inheritance, no rendering,
# no autoload access, no Input — only SimRng (seeded) and CropDefs/Tools (data).
class_name SimWorld
extends RefCounted

const MAP_WIDTH := 32
# Two pages of 20 rows (2026-09-06). The farm is page 0 and every coordinate it
# has ever had is unmoved; the home interior is page 1. See WorldLayout's page
# block: a door is the only way between them, and it is a verb.
const MAP_HEIGHT := 40

# How tall a page is, read from the layout data that defines it so the two
# cannot drift. A page is a map: it has its own border ring, its own walls, and
# nothing walks off the bottom of one onto the top of the next. `page_of()`,
# below, is the only page arithmetic anything outside this file should need.
const PAGE_ROWS := WorldLayout.PAGE_ROWS

# T-8 / Q-34: the world is parcels now. Where the land is and what opens it is
# data in systems/world_layout.gd; this file only knows how to fill a region
# definition. The old uniform 25% sprinkle and the two hard-coded onboarding
# tile constants are gone with it — obstacle *type* is now a property of the
# parcel a tile belongs to, so a rock the player cannot break is a legible
# future behind a hedge rather than noise in her yard.
# **The composed world** since 2026-09-06 (the door): the farm on page 0 and the
# home on page 1, built by `WorldLayout.compose()` from the same DEFAULT and HOME
# the tests and the debug screen still generate on their own. A world that is
# restored rather than generated keeps this, which is what lets an old save —
# one farm page and nothing else — answer a question about the parcel a tile is
# in exactly as it always did.
var layout: Dictionary = WorldLayout.WORLD

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


# Pure so it can be tested without a scene tree. It was always the rule half of a
# split whose other half — the timer — lived in `main.gd`; since M2.5 WI-3 both
# halves are sim-side (`_send_due_crows` reaches the appointment, `CrowBrain.send`
# asks this whether a bird may come). `day` is a **play-day** (see CROW_MIN_DAY).
static func may_spawn_crow(day: int, total_harvests: int, planted: int) -> bool:
	return day >= CROW_MIN_DAY \
		and total_harvests >= CROW_MIN_HARVESTS \
		and planted >= CROW_MIN_PLANTED


# --- Ant raids (design/04 §1 and §3, P-10; M2.5 WI-8a/8b) ---------------------
#
# The crow's schedule, worn by a second kind of pest, and for the same reasons:
# an arrival is a point in the day's **action clock** (T-20 — pressure follows
# productivity), it is consumed whether the raid happens or not, and the draw is
# `SimRng.stateless` so a replay sees the same raid at the same moment.
#
# **`ANT_RAIDS_PER_DAY` is 0, and that is the shipping value.** The whole raid
# lifecycle exists — scheduled, gated, spawned, columned and despawned — and
# nothing in the live game has ever contained an ant, exactly as `M2_5_PLAN.md`
# §4 requires ("none of these spawn in the live game yet; *when* each debuts is
# designer content sequencing"). A test hands `gs.ant_schedule` a number and the
# whole path runs; turning it on for players is one integer and a designer's
# ruling.
const ANT_RAIDS_PER_DAY := 0
const ANT_EARLIEST_ACTION := 6   # never in the first few actions of a day
const ANT_MIN_DAY := 4           # a play-day, like CROW_MIN_DAY
const ANT_MIN_PLANTED := 4       # something worth raiding, and losing one is affordable

# How many foragers a completed trail summons, and how many ticks apart they
# leave the nest. The size is what bounds a raid's cost — one crop each, so a
# column can take at most this many — and per `design/04` §1 it is deliberately
# **not** the difficulty dial: that is the trail's half-life. [Playtest].
const ANT_COLUMN_SIZE := 3
const ANT_COLUMN_STAGGER := 12


static func roll_ant_schedule(day: int) -> Array[int]:
	var out: Array[int] = []
	if day < ANT_MIN_DAY:
		return out
	for i in ANT_RAIDS_PER_DAY:
		out.append(ANT_EARLIEST_ACTION + SimRng.stateless(day, 5000 + i) % 20)
	out.sort()
	return out


# May a raid start at all? The crow's readiness gate (T-2) without the harvest
# clause: a column that eats three plants needs there to *be* plants, and the day
# floor is the backstop rather than the mechanism. Pure, so it can be tested
# without a world, exactly like `may_spawn_crow`.
static func may_start_raid(day: int, planted: int) -> bool:
	return day >= ANT_MIN_DAY and planted >= ANT_MIN_PLANTED


# --- The visitors' appointment book (M2.5 WI-8c/8f/8g) ------------------------
#
# The crow's schedule and the raid's, worn by three more species, and written
# **once** instead of three more times. Each of the two above is a `*_SCHEDULE`
# field on GameState, a `roll_*` function, a `_send_due_*` loop and a pair of
# lines in `save_game.gd`; a third copy would have been forgivable and a fifth
# would not, so the rule each visiting species differs by is a row in this table
# and everything around it is shared. **A future critter is a row here** (the
# mole, the worm, WI-9's bots if their debut is ever scheduled) rather than a
# field, a roll, a loop and a save key.
#
# The two older books are deliberately **not** migrated into it: they are shipped,
# tested and saved under their own names, and rewriting a format to tidy it is how
# a save file stops loading. See §9 of `M2_5_PLAN.md`.
#
# Per row: `min_day` is a **play-day** floor (the T-2 backstop), `min_planted` is
# the "there is something worth coming for, and losing it is affordable" gate,
# `earliest` keeps an arrival out of the first few actions of a day, and `salt`
# separates this species' `SimRng.stateless` draws from every other species'.
#
# **Every `per_day` is 0, and that is the shipping value.** The whole lifecycle —
# scheduled, gated, spawned, fed and gone — exists and is tested; no real game has
# ever contained a rabbit, a kangaroo or a songbird. Turning one on is one integer
# and a designer's ruling (the Q-56 pattern).
const RABBIT_VISITS_PER_DAY := 0
const KANGAROO_VISITS_PER_DAY := 0
const SONGBIRDS_PER_DAY := 0
# ...and the last two of tier 1 (M2.5 WI-8d/8e), which added two rows to the table
# below and nothing else: no field, no roll, no loop, no save key.
const MOLE_VISITS_PER_DAY := 0
const WORM_VISITS_PER_DAY := 0

# How many crops one visiting grazer takes before it has had its fill and leaves.
# This is the daily-loss identity's new term (T-15/T-20, plan §4): a visit costs
# at most this, because the count is kept in the actor's own `extra` and the brain
# goes home when it reaches it. [Playtest].
const GRAZER_BITES := 2

# The same bound, for the same reason, for the last two mouths (M2.5 WI-8d/8e).
# Each is a count in the animal's own `extra`, re-checked every time it goes
# looking for another meal, so a visit that is interrupted cannot buy itself
# thirds (the lesson of WI-8c deviation 4).
#
# **A mole's term is denominated in seeds**, not in grown crops: it only ever
# targets a `seeded` tile (`has_seed` below), and a stolen seed is a unit of
# `count_planted()` exactly as a ripe head is — the same currency the daily-loss
# identity has always been measured in, and one the player paid gold for. It is a
# strict subset of that identity rather than a new kind of loss, which is why the
# formula gains a term rather than a footnote. [Playtest].
const MOLE_STEALS := 2
const WORM_MEALS := 3

# Built on first use rather than as a `const`, so the table can name species
# constants without asking GDScript to resolve two class initialisers into each
# other — `Brains._table()`'s reason, and its shape.
static var _visitors: Dictionary = {}


static func visitors() -> Dictionary:
	if _visitors.is_empty():
		_visitors = {
			SpeciesDefs.RABBIT: {
				"per_day": RABBIT_VISITS_PER_DAY,
				"min_day": 4, "min_planted": 3, "earliest": 5, "salt": 7000,
			},
			SpeciesDefs.KANGAROO: {
				"per_day": KANGAROO_VISITS_PER_DAY,
				"min_day": 6, "min_planted": 4, "earliest": 5, "salt": 8000,
			},
			# It eats nothing, so it needs no farm to raid and no mercy rule: a
			# songbird may turn up on a bare field on the first morning.
			SpeciesDefs.SONGBIRD: {
				"per_day": SONGBIRDS_PER_DAY,
				"min_day": 1, "min_planted": 0, "earliest": 2, "salt": 9000,
			},
			# It comes for *seeds*, so the honest mercy rule would be about how
			# many are in the ground rather than how much is growing.
			# `min_planted` is the nearest question this table asks, and the brain
			# answers the rest by leaving again when it finds nothing sown
			# (M2.5 WI-8d).
			SpeciesDefs.MOLE: {
				"per_day": MOLE_VISITS_PER_DAY,
				"min_day": 5, "min_planted": 3, "earliest": 4, "salt": 10000,
			},
			# The slowest visitor there is, so it comes early in the day and to a
			# farm with barely anything on it (M2.5 WI-8e).
			SpeciesDefs.WORM: {
				"per_day": WORM_VISITS_PER_DAY,
				"min_day": 3, "min_planted": 2, "earliest": 4, "salt": 11000,
			},
		}
	return _visitors


# Arrival points for one species on one day, as action counts — `roll_crow_schedule`
# generalised. Derived from (seed, day, species salt) rather than drawn from the
# shared stream, for the reason `crow_brain.gd` spells out at length: entity noise
# advances that stream between the player's actions and a replay's is not advanced
# the same way. `day` is a **play-day**.
static func roll_visitor_schedule(species: String, day: int) -> Array[int]:
	var out: Array[int] = []
	var rule: Dictionary = visitors().get(species, {})
	if rule.is_empty() or day < int(rule["min_day"]):
		return out
	for i in int(rule["per_day"]):
		out.append(int(rule["earliest"]) + SimRng.stateless(day, int(rule["salt"]) + i) % 20)
	out.sort()
	return out


# Every visiting species' schedule for a fresh day, in one dictionary — what
# `GameState.start_new_day` stores and `SaveGame` carries. Keyed by species, so a
# reader can tell what is owed to whom.
static func roll_visitor_schedules(day: int) -> Dictionary:
	var out := {}
	for species in visitors().keys():
		out[String(species)] = roll_visitor_schedule(String(species), day)
	return out


# May this species come at all? The crow's readiness gate (T-2) with its numbers
# read out of the table instead of written into the function. Pure, so it tests
# without a world, exactly like `may_spawn_crow` and `may_start_raid`.
static func may_visit(species: String, day: int, planted: int) -> bool:
	var rule: Dictionary = visitors().get(species, {})
	if rule.is_empty():
		return false
	return day >= int(rule["min_day"]) and planted >= int(rule["min_planted"])


# Fixed object positions (0-indexed tile coords)
const OBJECT_POSITIONS: Array[Dictionary] = [
	# T-32, the designer 2026-09-01: *"lower the cot by 3 tiles so it's somewhat
	# centered vertically, and left-aligned, in the initial space."* It sat at
	# (2,1), in the corner with the three stations, where it was one of four
	# things in a row and the least legible of them. Its footprint is (2,4) and
	# its 16x32 sprite rises into (2,3) — rows 3 and 4 of the yard's rows 1..6 —
	# so it reads as the middle of the room, with the stations still along the top.
	{ "type": "cot",          "tx": 2, "ty": 4 },
	{ "type": "shipping_bin", "tx": 4, "ty": 1 },
	{ "type": "well",         "tx": 6, "ty": 1 },
	{ "type": "seed_box",     "tx": 8, "ty": 1 },
]

# Tile data: tiles[y][x] = { state, crop_type, growth_stage, watered_today }
var tiles: Array[Array] = []
var objects: Array[Array] = []  # objects[y][x] = "" or object type string

# The sim's tick clock (D-9 / Q-53, M2.5 WI-1). Sim truth, exactly like the grids:
# owned here, saved with the world, and the only time anything in layer 2 is
# allowed to read. Since M2.5 WI-3 the brains ride on it: every clock-driven actor
# has exactly one pending "think" event, and `advance_ticks()` is what turns sim
# time into decisions. Nothing in here reads a frame delta or an engine clock
# (plan §1 rule 7) — converting wall time into ticks is `main.gd`'s job, at the
# same boundary its per-run `randi()` seed sits on.
var clock := SimClock.new()

# The scent layer (P-10, M2.5 WI-7). Sim truth like the grids and the clock: owned
# here, saved with the world, washed away by the `water` verb below. It holds a
# cell only where something has written one — no per-tile pass, on any tick, ever
# (P-10's guardrail) — so on a farm nobody has marked it is an empty dictionary.
# **Nothing writes it yet**: WI-8's ant pair is the first writer, and until then
# the wash in the gateway is exact and unexercised.
var scent := Scent.new()

# The seed this world was generated from (M2.5 WI-5). Sim truth, and the one
# piece of it that was missing: `SimRng.stateless()` derives every per-day draw
# from the *current* seed — the crow schedule most visibly — so a world that
# cannot say which seed it came from cannot be continued or replayed faithfully.
# Recorded here at generation, carried through the save, and reseeded from by
# whoever owns the session (`main.gd` after a restore, `ReplayLog.apply_to()`
# before it replays). 0 means "unknown", which is what every save written before
# this field existed says, and those keep their old behaviour.
var gen_seed: int = 0


func generate(with_layout: Dictionary = WorldLayout.WORLD) -> void:
	layout = with_layout
	tiles.clear()
	objects.clear()
	gen_seed = SimRng.current_seed()
	# A regenerated world is a new world, so its timeline starts over. Matters for
	# replay: `apply_to()` regenerates from seed, and a replayed session must count
	# its ticks from the same zero the recorded one did. The scent layer goes with
	# it: a new world has been marked by nobody (M2.5 WI-7).
	clock.reset()
	scent.clear()

	# 1. Bare ground inside the map border. Every later step overwrites; nothing
	#    below reads a tile it has not written, so the fill order is the only
	#    thing determinism depends on.
	#
	#    **The border is per page** (2026-09-06). It used to be the edge of the
	#    one map there was; now it is the edge of each of them, which is what
	#    keeps page 0 the map it has always been — the farm's bottom row is still
	#    a border rather than a row of field that appeared when the grid got
	#    taller — and what stops anybody walking off the bottom of the farm into
	#    the home's ceiling.
	for ty in MAP_HEIGHT:
		var row: Array[Dictionary] = []
		var obj_row: Array[String] = []
		var page_y := ty % PAGE_ROWS
		for tx in MAP_WIDTH:
			if page_y == 0 or page_y == PAGE_ROWS - 1 or tx == 0 or tx == MAP_WIDTH - 1:
				row.append(_create_tile("border"))
			else:
				row.append(_create_tile("cleared"))
			obj_row.append("")
		tiles.append(row)
		objects.append(obj_row)

	# 1b. The dark, over everything on a page that no parcel claims (2026-09-06).
	#     Laid **before** the room so the room can be cut out of it: a parcel's
	#     own tiles are spared here and filled by the ordinary steps below, which
	#     is why an interior needed no new generator step of its own — it is still
	#     ground, boundaries and objects, with darkness where the walls end.
	#
	#     **No draw**, exactly like the yard's fill in 5b: a fill is not a
	#     decision, so every seeded placement after it lands where it always did.
	_fill_void()

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

	# 5. Fixed objects, on cleared ground with cleared shoulders. A layout may
	#    carry its own `objects` list (T-37, the home's bed); the farm's default
	#    layout does not, so the module constant stays the farm's truth.
	for obj in layout.get("objects", OBJECT_POSITIONS):
		var tx: int = obj.tx
		var ty: int = obj.ty
		objects[ty][tx] = obj.type
		# **A `bare` object keeps the land it stands on** (2026-09-06). The
		# clearing below exists because a fat finger misses onto the tiles around
		# a station (T-27 box 3), and it is right for everything that stands *on*
		# ground. The home's doorway is not one of those: it is the hole cut in
		# the south wall, with darkness on the far side, and clearing it would
		# both fill in the hole and lay three tiles of walkable floor outside the
		# house.
		if bool(obj.get("bare", false)):
			continue
		tiles[ty][tx] = _create_tile("cleared")
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := tx + dx
				var ny := ty + dy
				if _inside(nx, ny) and objects[ny][nx] == "" \
						and not WorldLayout.is_boundary_state(String(tiles[ny][nx].state)):
					tiles[ny][nx] = _create_tile("cleared")

	# 5b. The ground a parcel says it is made of — today only the yard's (T-32).
	#     **After step 5, and that ordering is the design.** Step 5 clears a
	#     shoulder around every fixed object, so laying the yard before it would
	#     punch a ring of ordinary tillable field around the cot, the bin, the
	#     well and the seed box — which are precisely the tiles a fat finger
	#     misses onto (T-27 box 3's evidence: four `no_energy` refusals one tile
	#     off the cot). The yard has the last word on the yard.
	#
	#     Only the parcel's *plain* ground is replaced. An obstacle, a boundary or
	#     a gate inside such a parcel keeps itself, so this stays a statement about
	#     ground rather than a bulldozer; the yard happens to hold none of them.
	#
	#     **No draw.** A fill is not a decision, so the RNG stream is untouched and
	#     every seeded placement after this one lands where it always did.
	for p in WorldLayout.parcels(layout):
		var ground := WorldLayout.ground_of(p)
		if ground == "":
			continue
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					if _inside(tx, ty) and String(tiles[ty][tx].state) == "cleared":
						tiles[ty][tx] = _create_tile(ground)

	# 6. The tools, lying at their gates from the first moment she can see them.
	#    Q-46 STRAWMAN — the mechanism is in DESIGNER_QUEUE, not settled here.
	for e in WorldLayout.tools(layout):
		var at: Vector2i = e.get("at", Vector2i(-1, -1))
		if _inside(at.x, at.y):
			tiles[at.y][at.x] = _create_tile("cleared")
			objects[at.y][at.x] = String(e.get("object", ""))

	# 6b. A handful of rocks and logs through the parcels that declare a scatter —
	#     today the meadow, the one field parcel that is open from the first
	#     morning (the designer, 2026-09-01). **After** the fixed objects, the
	#     yard's ground and the tools, so it can see what they claimed and place
	#     around it, and before the acorns, which are in a different parcel and
	#     draw from candidates of their own.
	_place_scatter()

	# 7. A finite acorn stock near the trees (T-15 / Q-39). No regeneration in
	#    phase 1: the stock running down IS the difficulty ramp, and a ramp that
	#    refills is not a ramp. Walkable like an egg, so it can never trap anyone.
	_place_acorns()

	# 8. The neighbour's plot, in its state *before* the cold open runs. Her own
	#    actions and the world sleeps produce the takeover row, so what the player
	#    inherits is real world state rather than a picture of some.
	_place_neighbour_plot()

	# 9. The cast (M2.5 WI-2, D-9/Q-53). Who is in the world and where they stand
	#    is decided here — from the seed, with the grids — rather than by whichever
	#    renderer happens to spawn nodes. The hen's tile used to be drawn in
	#    `main.gd` after generation, which is exactly why she landed somewhere new
	#    every time a save was loaded (finding F-7c). Last in the sequence, so
	#    every draw above it keeps the stream position it has always had.
	spawn_default_actors(true)


# Inside the *page's* border ring — the tiles generation is allowed to write.
# Page-local since 2026-09-06 and identical to what it always answered while
# there was one page: row 19 is the farm's bottom border, and no parcel, gate,
# tool or object may be laid into it.
func _inside(tx: int, ty: int) -> bool:
	if tx < 1 or tx > MAP_WIDTH - 2 or ty < 0 or ty >= MAP_HEIGHT:
		return false
	var page_y := ty % PAGE_ROWS
	return page_y >= 1 and page_y <= PAGE_ROWS - 2


# Step 1b: darkness over a page, minus the rooms cut out of it. The rect comes
# from the layout (`void_fill`) and is clamped here, so a layout may say "the
# whole page" without knowing how wide the map is.
func _fill_void() -> void:
	var spec = layout.get("void_fill", null)
	if spec == null:
		return
	var rect: Rect2i = spec
	for ty in range(maxi(rect.position.y, 0), mini(rect.end.y, MAP_HEIGHT)):
		for tx in range(maxi(rect.position.x, 0), mini(rect.end.x, MAP_WIDTH)):
			if WorldLayout.parcel_at(Vector2i(tx, ty), layout).is_empty():
				tiles[ty][tx] = _create_tile(WorldLayout.VOID)


# Sparse rocks and logs through a parcel that is already open (the designer,
# 2026-09-01: *"We should include sparse rocks and logs in the un-blocked
# sections. Once those items are available, then the player can do a superior job
# clearing that space."*). Which parcels, and how many, is layout data — this is
# only the placing.
#
# Three rules, and each one is a thing that would otherwise go wrong:
#
#   * **It never lands on anything.** Candidates are plain `cleared` ground with
#     no object on it and no object anywhere in its shoulders, so the ring step 5
#     deliberately cleared around the cot, the bin, the well, the seed box and the
#     two tools stays clear — those shoulders exist because a fat finger misses
#     onto them (T-27 box 3). Tiles beside a gate are spared for the same reason:
#     the way in reads as a way in.
#   * **It never cuts the field in two.** Every placement is checked with a flood
#     fill and reverted unless the walkable area shrank by exactly the one tile it
#     filled. A seeded draw is deterministic, not careful — without this, one seed
#     in some number of them would wall off a corner of the meadow, and the player
#     who found it would have no idea it was supposed to be reachable.
#   * **It is a seeded draw without replacement**, the same swap-and-shrink
#     `_place_acorns` uses, so the same seed always lays the same field and a
#     replay regenerates it exactly.
func _place_scatter() -> void:
	for p in WorldLayout.parcels(layout):
		var spec: Dictionary = WorldLayout.scatter_of(p)
		var kinds: Array = spec.get("kinds", [])
		var want := int(spec.get("count", 0))
		if kinds.is_empty() or want <= 0:
			continue
		var candidates: Array[Vector2i] = []
		for r in p.get("rects", []):
			var rect: Rect2i = r
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					if _scatter_candidate(tx, ty):
						candidates.append(Vector2i(tx, ty))
		if candidates.is_empty():
			continue
		var placed := 0
		while placed < want and not candidates.is_empty():
			var idx: int = SimRng.randi() % candidates.size()
			var t: Vector2i = candidates[idx]
			candidates.remove_at(idx)
			var kind := String(kinds[placed % kinds.size()])
			var was: Dictionary = tiles[t.y][t.x]
			tiles[t.y][t.x] = _create_tile(kind)
			if _keeps_ground_connected(t):
				placed += 1
			else:
				tiles[t.y][t.x] = was  # it would have sealed something off


# Does the ground on all sides of this newly-blocked tile still hang together?
#
# Asked of the tile's own neighbours rather than of the whole map, which is both
# cheaper and exactly the right question: filling one tile can only separate
# ground that used to route *through* it, so if everything that touched it can
# still reach everything else that touched it, nothing anywhere was cut off.
func _keeps_ground_connected(t: Vector2i) -> bool:
	var open_sides: Array[Vector2i] = []
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if is_walkable(t.x + d.x, t.y + d.y):
			open_sides.append(t + d)
	if open_sides.size() <= 1:
		return true
	var seen := {}
	for reached in reachable_from(open_sides[0]):
		seen[reached] = true
	for i in range(1, open_sides.size()):
		if not seen.has(open_sides[i]):
			return false
	return true


# Ground a scattered obstacle may land on: plain field, nothing on it, nothing
# beside it that a finger aims at.
func _scatter_candidate(tx: int, ty: int) -> bool:
	if not _inside(tx, ty):
		return false
	if String(tiles[ty][tx].state) != "cleared" or objects[ty][tx] != "":
		return false
	# Somewhere to stand while clearing it, or it is scenery forever.
	var approachable := false
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if is_walkable(tx + d.x, ty + d.y):
			approachable = true
	if not approachable:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := tx + dx
			var ny := ty + dy
			if nx < 0 or ny < 0 or nx >= MAP_WIDTH or ny >= MAP_HEIGHT:
				continue
			if objects[ny][nx] != "":
				return false
			var st := String(tiles[ny][nx].state)
			if st == WorldLayout.GATE_CLOSED or st == WorldLayout.GATE_OPEN:
				return false
	return true


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


# The objects that stand two tiles high, so the tile above one reads as occupied.
# A constant rather than the array literal that used to sit in the `in` test
# below: `is_walkable` calls this function for every neighbour of every node of
# every route the sim plans, and a literal there allocated a three-string array on
# each of them (Q-67). Same list, same answer, no allocation.
const TALL_OBJECTS: Array[String] = ["cot", "well", "seed_box"]

# The objects a foot may land on. An object on a tile normally means "something is
# standing here, go round" — the well, the cot, the shipping bin — and these are
# the exceptions: things that lie on the ground (the egg, the acorn) and, since
# 2026-09-06, the two bays of a robot stall, which are open-fronted by design and
# exist in order to be stood in.
#
# A dictionary rather than a chain of `!=`, for `is_walkable`'s reason (Q-67): it
# is asked about every neighbour of every node of every route the sim plans, so the
# test is one hash rather than one comparison per exception.
const OPEN_OBJECTS := {
	"egg": true, "acorn": true,
	WorldLayout.ROBOT_STALL: true, WorldLayout.ROBOT_STALL_SLOT: true,
}

# The catalogue row a stall is bought from, and where its second bay lands
# relative to the tile she tapped: one tile to the **right**, always, because two
# bays side by side is the shape of the shed and v1 does not rotate (P-13).
const STALL_ITEM := "stall"
const STALL_SLOT_OFFSET := Vector2i(1, 0)


func get_object(tx: int, ty: int) -> String:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		var here: String = objects[ty][tx]
		if here != "":
			return here
		# Check if the tile below has a tall object
		if ty + 1 < MAP_HEIGHT:
			var below: String = objects[ty + 1][tx]
			if below in TALL_OBJECTS:
				return below
	return ""


func set_object(tx: int, ty: int, obj_type: String) -> void:
	if ty >= 0 and ty < MAP_HEIGHT and tx >= 0 and tx < MAP_WIDTH:
		objects[ty][tx] = obj_type


# Is there something growing on this tile? **The one definition**, used by the
# `eat_crop` verb's guard and by every mouth that goes looking for one (M2.5
# WI-8): a crop is a crop whether it is a seed in the ground or a ripe head, and
# an ant that could smell a tile the gateway then refused to let it eat would be
# a bug wearing a design's clothes. Out of bounds is honestly "no".
func has_crop(tx: int, ty: int) -> bool:
	var tile := get_tile(tx, ty)
	if tile.is_empty():
		return false
	var st: String = tile.get("state", "")
	return st == "seeded" or st == "growing" or st == "ready"


# Is there a *seed* in this ground — sown, and not yet come up? The narrower half
# of `has_crop`, and the mole's whole diet (M2.5 WI-8d): it steals what the player
# has just planted rather than what she is about to harvest, which is why its
# damage is measured in seeds. One definition, here, for the same reason `has_crop`
# is one definition: the brain that goes looking and the test that checks what it
# took must not be able to disagree about what a seed is.
#
# `eat_crop` needs no special case for it — the verb has always accepted this state
# and always left the soil `tilled` behind it, which is exactly what a stolen seed
# looks like from the ground's side.
func has_seed(tx: int, ty: int) -> bool:
	return String(get_tile(tx, ty).get("state", "")) == "seeded"


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


# **The hottest read in the sim** (Q-67): every neighbour of every node of every
# route every brain plans comes through here, ~1.8 million times in a thousand
# benchmark days. So the bounds test, the tile fetch and the object lookup are
# written out rather than composed out of `get_tile` and `get_object` — same
# questions in the same order, same answers, two fewer calls and one fewer bounds
# check per read. The tall-object clause is `get_object`'s, kept beside it and
# reading the same `TALL_OBJECTS`; a walkability test that disagreed with
# `get_object` would be a walker standing inside the well.
func is_walkable(tx: int, ty: int) -> bool:
	if ty < 0 or ty >= MAP_HEIGHT or tx < 0 or tx >= MAP_WIDTH:
		return false
	var tile: Dictionary = tiles[ty][tx]
	if tile.is_empty():
		return false
	var state: String = tile.state
	if state == "border":
		return false
	# The dark outside a room is not land (2026-09-06). Checked beside the border
	# because that is what it is: the edge of the map, drawn on the inside of a
	# page rather than around it.
	if state == WorldLayout.VOID:
		return false
	if state.begins_with("obstacle"):
		return false
	# T-8: a boundary is land, and land is what says "not yet". An open gate is
	# ordinary ground — that transition is the whole reward.
	if WorldLayout.is_boundary_state(state):
		return false
	var obj: String = objects[ty][tx]
	if obj == "" and ty + 1 < MAP_HEIGHT:
		var below: String = objects[ty + 1][tx]
		if below in TALL_OBJECTS:
			obj = below
	if obj != "" and not OPEN_OBJECTS.has(obj):
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
# inexplicably left. The rule lives here; the caller supplies the draw — which
# since M2.5 WI-3 is `CrowBrain.send`, and it supplies a **stateless** one, so
# the same bird makes the same choice on replay.
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


# Which map a tile is on — rows 0-19 are the farm, 20-39 are the home. The
# camera clamps to it, the vignette scopes its scans to it, and `way_to_bed`
# below asks it whether she is already in the room the bed is in.
func page_of(t: Vector2i) -> int:
	return t.y / PAGE_ROWS


# Where the one of something is, or (-1,-1). Scanned rather than remembered: an
# object's tile is grid truth, and a cached copy of it is a thing that can be
# wrong after a save, a replay, or a `collect`. O(map) and called by hand — at
# dusk, when the HUD asks the way to bed — never per frame.
func find_object(type: String) -> Vector2i:
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			if objects[ty][tx] == type:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


# **The way to bed, from wherever she is standing** (2026-09-06).
#
# The cot moved indoors, which broke a chain of things that all quietly assumed
# the bed was a tile she could walk to: the dusk glow, the vignette's bedtime
# beat, the teaching focus and the HUD's bed button. Every one of them now asks
# this instead, so there is exactly one answer to "where do I point her" and it
# cannot go stale in four places independently.
#
# The rule is one sentence: **the bed if she is on the bed's page, otherwise the
# door that leads to it.** Outside at dusk the house door glows and the nudge
# points at it; inside, the bed does. Two taps to sleep rather than one, which is
# the honest cost of the bed being in a room (and it is what a house is for).
#
# Returns (-1,-1) when the world has no bed at all — a layout that never placed
# one, which the caller must be able to say nothing about rather than point at
# the origin.
func way_to_bed(player_tile: Vector2i) -> Vector2i:
	var bed := find_object("cot")
	if bed.x < 0:
		return bed
	var here := page_of(player_tile)
	if here == page_of(bed):
		return bed
	var fallback := Vector2i(-1, -1)
	for d in WorldLayout.doors(layout):
		var at: Vector2i = d.get("at", Vector2i(-1, -1))
		if at.x < 0 or page_of(at) != here:
			continue
		if page_of(d.get("to", Vector2i(-1, -1))) == page_of(bed):
			return at  # this one opens onto the room the bed is in
		if fallback.x < 0:
			fallback = at
	return fallback if fallback.x >= 0 else bed


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
		# **Planting into wet ground keeps it wet.** This used to force the tile
		# dry, so planting on a rainy day threw the rain away and the soil visibly
		# went from wet to dry under her hands — reported from play 2026-08-30 as
		# "when planting when it's raining, the wetness of soil goes to dry", and
		# read at the time as not being able to plant on a rainy day at all.
		#
		# The only thing that can wet a *tilled* tile is rain (the router offers
		# watering on seeded/growing only), so preserving it means exactly one
		# thing: rain waters what you plant that day. Which is what rain is for.


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
const MILESTONE_VERBS := { "harvest": true, "collect": true, "sell": true, "sleep": true,
		"buy_seed": true, "buy_machine": true }


# Verbs that do not advance the day's clock: sleep ends it, and the shop and bin
# are errands rather than farm work. Everything else the player successfully does
# is one tick of the action clock T-20 schedules crows against.
const NON_WORK_VERBS := { "sleep": true, "sell": true, "buy_seed": true, "refill": true,
		# The machine counter is the seed counter (2026-09-03), and turning a dial
		# on a machine she already owns is a setting, not a stroke of work — it
		# costs no energy and must not tick the clock the crows are scheduled
		# against. **Placing** one is absent on purpose: carrying a sprinkler out
		# to the far corner and setting it down is work, and it is charged as such.
		"buy_machine": true, "configure": true,
		# Teaching a mark-1 and sending it out are instructions, not strokes of
		# work (2026-09-03). Charging the day's clock for pointing at eight tiles
		# would make delegating the round cost more than doing it.
		"teach": true, "activate": true,
		# Walking through her own front door is not work (2026-09-06). It costs no
		# energy and does not tick the clock the crows are scheduled against, for
		# the same reason crossing the yard does not: going somewhere is how you
		# reach the thing you are going to do.
		"use_door": true }

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
#
# T-29 scaled this with the player's: an NPC's day is the same 600 fine units
# hers is, so "a day's work" means the same amount of work for everybody and a
# bot gets no more clock than the farmer does (S-3). Derived from `Tools` rather
# than restated, so the two can never drift.
const ACTOR_MAX_ENERGY := Tools.DAY_UNITS  # [Playtest]


# --- Actor registry (D-9 / Q-53, M2.5 WI-2) -----------------------------------
#
# **Who is in the world, and where, is sim truth.** D-9 said actor position was
# presentation's business; Q-53 settled it the other way, and this is that
# settlement. Before it, no actor position was saved, recorded or replayed
# (finding F-5): the hen's tile was drawn in `main.gd` *after* generation, so she
# landed somewhere new on every load (F-7c), and entities existed only because
# main happened to spawn nodes, so every other renderer of the same sim silently
# showed an empty farm (F-3).
#
# Entry shape — `actors[actor_id] = { species, pos, facing, energy, extra }`:
#   species  a row in `systems/species_defs.gd`
#   pos      Vector2i tile coordinates. Sim truth, saved and replayed.
#   facing   "down"/"up"/"left"/"right" — the one presentation fact worth keeping
#            sim-side, because a renderer that joins late has to draw *something*
#   energy   this actor's own meter (below). The player's is GameState's, so hers
#            reads -1 here and is never spent
#   extra    per-species scratch, saved with the entry; WI-3's brains keep their
#            per-actor state here rather than growing the registry a field per
#            critter. The sim itself writes exactly one key, on the player only:
#            `left_yard` (T-35, latched in set_actor_pos)
#
# **The registry holds residents and visits alike** since M2.5 WI-3: the player,
# the neighbour while her cold open is live, the chicken — and a crow, for as long
# as its visit lasts. A crow's species row says `persistent: false`, which is what
# keeps it out of the *save*: a save is a snapshot of a farm, and a bird halfway
# across the sky is not part of one (see `SaveGame._capture_actors`).
#
# **Positions move under the clock now** (WI-3), for actors whose brain is on it:
# the hen's wander is a tick-stepped sim process, the crow's flight likewise. The
# player's and the neighbour's are still presentation's — they walk in pixels and
# join sim truth with the movement engine (WI-4), which is also when
# `capture_canonical` gets to compare positions again (see the note there).
#
# Spawn and despawn are sim functions rather than verbs. A verb is a thing an
# actor *does*; nobody does a spawn. Brain-driven arrivals (a crow's visit, an
# ant column) schedule against the clock from inside the gateway.
#
# **Iteration order is not truth.** A generated world holds actors in spawn
# order; a restored one holds them in the order `JSON.stringify` sorted them
# (alphabetically — it sorts keys by default, which is also why
# `capture_canonical` compares equal across the two). Nothing may depend on the
# order, and everything here is written not to: refills are per entry, lookups
# are by id, and a renderer that needs a stable draw order must sort on
# something real, like position.
var actors: Dictionary = {}

# The ids the registry knows by name. Actor ids are still species names in
# phase 1 — there is one hen and she is called "chicken", one crow and it is
# called "crow" — and a second of either needs an id of its own (the registry
# takes one happily; `CrowBrain.send` refuses a second bird because
# CROWS_PER_DAY is 1).
const ACTOR_PLAYER := "player"
const ACTOR_NEIGHBOUR := "neighbour"
const ACTOR_CHICKEN := "chicken"
const ACTOR_CROW := "crow"
# The raid (M2.5 WI-8a/8b). One scout per raid, so it takes the species name;
# the foragers are numbered from this prefix (`ant_forager_0`…), because a column
# is the first time the game has had more than one of anything.
const ACTOR_ANT_SCOUT := "ant_scout"
const ACTOR_ANT_FORAGER := "ant_forager"


static func _is_player(actor: String) -> bool:
	# "" is the player: plenty of call sites (and tests) omit the actor entirely,
	# and the player is the only actor anything ever forgot to name.
	return actor == "" or actor == ACTOR_PLAYER


func spawn_actor(actor_id: String, species: String, at: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var entry := {
		"species": species,
		"pos": at,
		"facing": "down",
		# The player's meter is GameState's, and hers is also the clock (Q-38).
		# -1 is the same "she has no world-side meter" that energy_of() returns,
		# stored so every row has the same shape.
		"energy": -1 if _is_player(actor_id) else ACTOR_MAX_ENERGY,
		"extra": extra.duplicate(true),
	}
	actors[actor_id] = entry
	# A newly arrived actor starts thinking on the next tick. Nothing happens
	# until something advances the clock, so this is free in a headless
	# fast-forward that never does.
	_schedule_brain(actor_id, clock.tick + 1)
	return entry


func despawn_actor(actor_id: String) -> bool:
	if _brain_events.has(actor_id):
		clock.cancel(int(_brain_events[actor_id]))
		_brain_events.erase(actor_id)
	return actors.erase(actor_id)


func has_actor(actor_id: String) -> bool:
	return actors.has(actor_id)


# The live entry (mutable — callers hold the sim's own dictionary), or {}.
func actor(actor_id: String) -> Dictionary:
	return actors.get(actor_id, {})


func species_of(actor_id: String) -> String:
	return String(actor(actor_id).get("species", ""))


func actor_pos(actor_id: String) -> Vector2i:
	return actor(actor_id).get("pos", Vector2i(-1, -1))


# Sim-side movement, for the movement engine (WI-4) and the brains that drive it
# (WI-3). Presentation must not call this: a node writing its wall-clock position
# into sim truth is exactly the desync the registry exists to prevent.
#
# **One sanctioned exception, and it is the player's** (M2.5 WI-6). She keeps
# continuous pixel motion, so her tile is written here from
# `world/farm.gd:note_player_walk` when she crosses a boundary — and the crossing
# is *recorded* in the same call, as a free-walk entry a replay applies back. That
# is what makes it not a desync: the write is a discrete event both a live session
# and its replay agree on, rather than a frame's worth of pixels leaking in. A
# renderer that wrote any other actor's position here would still be the bug this
# comment is about, because nothing would be recording it.
func set_actor_pos(actor_id: String, at: Vector2i, facing: String = "") -> void:
	var e: Dictionary = actor(actor_id)
	if e.is_empty():
		return
	e["pos"] = at
	if facing != "":
		e["facing"] = facing
	# T-35: the moment the player first stands on a non-yard tile, the fact is
	# latched — in her registry entry, so it rides saves and replays with her
	# position. The vignette's handoff beat (walk through the gate) reads this
	# to stay finished: derived from her *current* tile it re-armed every time
	# she came home, which is what pointed her at the gate at bedtime
	# (playtests/2026-08-31_233943, 1m47s–2m20s). Written here because this is
	# the one sanctioned write point for her tile, live and in replay alike.
	if actor_id == ACTOR_PLAYER and not bool(e["extra"].get("left_yard", false)) \
			and String(WorldLayout.parcel_at(at, layout).get("id", "")) != "yard":
		e["extra"]["left_yard"] = true


# T-35's predicate: has she ever been outside the yard? True forever once the
# latch above fires. An old save (or a hand-built world) that never recorded it
# reads false, which re-offers the gate beat at worst — the pre-T-35 behaviour.
func player_left_yard() -> bool:
	return bool(actor(ACTOR_PLAYER).get("extra", {}).get("left_yard", false))


func actors_of_species(species: String) -> Array[String]:
	var out: Array[String] = []
	for id in actors:
		if String(actors[id].get("species", "")) == species:
			out.append(String(id))
	return out


# Everybody of a *class* — birds, today (M2.5 WI-9). The registry's answer to
# "what kind of things are in this world", for a bot that was told to chase a
# class rather than a list of species names (`SpeciesDefs.class_of`).
#
# **Sorted**, for `spook_source_near`'s reason two functions down: the answer
# feeds a decision, and a bot that picked "whichever the registry happened to
# list first" would chase a different bird in a replay than it did live.
func actors_of_class(cls: String) -> Array[String]:
	var out: Array[String] = []
	if cls == "":
		return out
	for id in actors:
		if SpeciesDefs.class_of(String(actors[id].get("species", ""))) == cls:
			out.append(String(id))
	out.sort()
	return out


# --- who frightens whom: finding F-7b, alive at last (M2.5 WI-8c) -------------
#
# **The scan the crow was written to do and never could.** `entities/crow.gd` used
# to look for "other entities with a `spook_radius`" and the answer was always the
# player, because she was the only thing that had one *and* the only thing whose
# position a node could see — so WI-3 deleted the scan rather than porting it, and
# recorded the reason (F-7b: dead code that could only ever find one answer). What
# was missing was not the loop, it was sim truth: nobody's live position was in
# the registry. Since WI-6 the player's is, so the loop can be written honestly,
# here, where it reads the registry instead of the scene tree.
#
# The radius belongs to the **frightener** (`senses.spook_radius`, the player's
# row since WI-2 — she is what is three tiles scary), and noticing belongs to the
# frightened (`senses.flees_spook_radius`, the crow's row and now both grazers').
# Returns the id of the nearest thing worth running from, or "".
#
# Cost is one pass over the registry per decision — four to six entries in any
# farm this game has ever had — and never over the map. Ids are visited in sorted
# order and kept on a **strictly** smaller distance, so two equidistant
# frighteners resolve the same way on every machine and in every replay (the
# registry-iteration-order rule, a few blocks up).
func spook_source_near(t: Vector2i, ignore: String = "") -> String:
	var best := ""
	var best_d := INF
	var ids: Array = actors.keys()
	ids.sort()
	for raw in ids:
		var id := String(raw)
		if id == ignore:
			continue
		var radius := float(SpeciesDefs.senses_of(species_of(id)).get("spook_radius", 0.0))
		if radius <= 0.0:
			continue
		var d := Vector2(actor_pos(id) - t).length()
		if d < radius and d < best_d:
			best_d = d
			best = id
	return best


# --- the stomp (P-10 / design/04 §4; M2.5 WI-8a) ------------------------------
#
# **A tap answers a critter, and it does it with a verb she already has.** A
# scout standing on a tile is what a clear-class action (`clear_weed` and its
# siblings — the same tap that pulls a weed up) resolves to; the intent layer
# asks `stompable_at` first and the gateway does the rest inside the verb it
# already implements. No new verb, no new UI, and therefore nothing a future bot
# gets that the player lacks (ground rule 1).
#
# Which species answer a boot is a field in the species table, so the hen can
# never be one by accident. Nothing stompable exists in the live game — the ant
# pair is the only such row and nothing spawns one — so this is inert in a
# shipping build, which is also why it costs a tap nothing: a registry with four
# actors in it is a four-entry scan.
func stompable_at(t: Vector2i) -> bool:
	return not _stompable_ids_at(t).is_empty()


# --- placed machines (2026-09-03, the placeholder acquisition rule) -----------
#
# A machine the player bought is an ordinary registry actor, so everything the
# registry already does — saving, replaying, `capture_canonical` comparison,
# `sync_actors` giving it a sprite in any farm — applies to it with no new
# machinery. These three functions are the whole of what "placing" needed: where
# one may go, whether one is here, and what to call it.


# May a machine be set down on this tile?
#
# **Walkable ground with nobody on it.** Walkable is the same question the movers
# ask (border, obstacles, boundaries and objects are all out), which means a
# machine can never be placed into a hedge, on top of the well, or in the parcel
# she has not opened yet — T-8's wordless "not yet" holds for machines for free.
# The occupancy clause is what stops her stacking two sprinklers on one square,
# and it reads the registry rather than a flag, so a hen standing there blocks the
# placement exactly as another machine does.
#
# The player herself is deliberately **not** an obstacle: she is standing next to
# the tile she taps, and on the tiles she does stand on, a machine set down at her
# feet is a perfectly ordinary thing to want. Pure — the router asks it before any
# action exists.
#
# **`item` is what she is carrying, and it is the second half of the question**
# (2026-09-06). Until the stall existed, "may a machine go there" was a fact about
# the *square* alone; a stall bay is a square that takes a robot and nothing else,
# so the answer now depends on what is in her hand. Everything that asks about
# ordinary ground may go on omitting it and gets exactly the answer it always got:
# a bay with no item named is not placeable, which is the safe direction — an
# unaware caller refuses a bay rather than dropping a sprinkler into one.
func placeable_at(t: Vector2i, item: String = "") -> bool:
	if not is_walkable(t.x, t.y):
		return false
	# A bay is for robots. A second stall, a sprinkler or a bare `placeable_at`
	# is refused here, and the emptiness of the bay is the actor loop below.
	if is_stall_tile(t):
		if MachineDefs.species_of(item) != SpeciesDefs.BOT:
			return false
	# ...and a stall itself is two tiles wide, so both of them have to be free
	# ground. The companion is on the same row and therefore on the same page by
	# construction; off the right-hand edge of the map is `is_walkable`'s answer.
	elif item == STALL_ITEM and not placeable_at(t + STALL_SLOT_OFFSET):
		return false
	for raw in actors:
		var id := String(raw)
		if id == ACTOR_PLAYER:
			continue
		if t in Movement.occupied_tiles(self, id):
			return false
	return true


# Is this tile one of a stall's two bays? Read off the grid rather than off
# `get_object`, deliberately: `get_object` answers with a *tall* object standing on
# the tile below, and the tile above a stall is ordinary ground that ordinary
# things happen to — it is only the shed's roof that leans over it.
func is_stall_tile(t: Vector2i) -> bool:
	if t.y < 0 or t.y >= MAP_HEIGHT or t.x < 0 or t.x >= MAP_WIDTH:
		return false
	return WorldLayout.is_stall_object(objects[t.y][t.x])


# The machine standing on this tile, or "". Sorted so that two machines sharing a
# tile — which `placeable_at` prevents, but a save from a future layout might not
# — always answer the same one, the registry block's iteration-order rule.
func machine_at(t: Vector2i) -> String:
	var found: Array[String] = []
	for raw in actors:
		var id := String(raw)
		if machine_key_of(id) == "":
			continue
		if t in Movement.occupied_tiles(self, id):
			found.append(id)
	if found.is_empty():
		return ""
	found.sort()
	return found[0]


# Which catalogue row a placed machine came from.
#
# **Read off the actor, not guessed from its species**, because two rows can
# share a species: the two robot marks are one `SpeciesDefs.BOT` with different
# settings, so "what species is it" cannot answer "which one did she buy". `place`
# stamps `extra.model`; this reads it, and falls back to the species lookup for a
# machine that has none — a sprinkler in a save written before the marks existed,
# or a bot a test deployed directly.
func machine_key_of(actor_id: String) -> String:
	var e: Dictionary = actor(actor_id)
	if e.is_empty():
		return ""
	var model := String(e.get("extra", {}).get("model", ""))
	if model != "" and MachineDefs.has(model):
		return model
	return MachineDefs.key_for_species(String(e.get("species", "")))


# May a mark-1 be *taught* this tile? (2026-09-03)
#
# Two halves, and both are about honesty rather than about permission. It has to
# be able to **stand** there, because its whole method is to walk onto a tile and
# water it — so a rock, a hedge, the well and the unopened parcel are all out, by
# the same `is_walkable` every mover already asks. And the square has to be one
# where watering could ever mean something, so that a taught order is never a
# tile the machine will visit and do nothing on. Teaching a patch of yard would
# be a silent trap; refusing it is a wobble she can read.
const TEACHABLE_STATES := {
	"cleared": true, "tilled": true, "seeded": true, "growing": true, "ready": true,
}


func teachable_at(t: Vector2i) -> bool:
	if not is_walkable(t.x, t.y):
		return false
	# ...including the square the machine parks on (2026-09-06). A stall bay is
	# walkable and may well be standing on soil, but the gateway refuses every
	# energy-costed verb there, so teaching one would be exactly the silent trap
	# the paragraph above is about: an order it walks to and can do nothing with.
	if is_stall_tile(t):
		return false
	return TEACHABLE_STATES.has(String(get_tile(t.x, t.y).get("state", "")))


# The id a newly placed machine gets: the machine key, then the lowest free
# index — "bot", "bot_2", "bot_3".
#
# **A pure function of the registry, which is what makes it replayable.** Nothing
# random, nothing counted up in a field that a save would have to carry: place
# three bots and pick the middle one up, and the next one placed is "bot_2" again,
# in a live session and in a replay of it alike. The first one keeps the bare key
# so the ids the tests and `BotBrain.deploy`'s own docs already use ("bot",
# "sprinkler") stay the ones the game produces.
func next_machine_id(key: String) -> String:
	if not actors.has(key):
		return key
	var n := 2
	while actors.has("%s_%d" % [key, n]):
		n += 1
	return "%s_%d" % [key, n]


# Everything a boot on this tile would answer, sorted by id. **All of them, not
# the first one found**: ants do not claim tiles (`tile_exclusive` is false on
# both rows), so two can share one, and "whichever the registry happened to list
# first" is exactly the kind of iteration-order dependency the registry block
# forbids.
#
# Two clauses beyond "is it stompable and is it here", both added by M2.5 WI-8d/8e
# for their own critter and both general:
#
#   **Under the ground is out of reach.** A burrower's registry tile is where it
#   is *travelling*, not where it can be answered, so a mole beneath a row of
#   wheat is not standing on it in any sense a boot can act on — and the tap falls
#   through to the ordinary clear, which is what the player expects from a tile
#   with nothing visible on it. It is what makes the mole's counterplay *timing*:
#   the answer to one is the second or two it is up.
#
#   **A long actor answers on any tile it occupies.** `Movement.occupied_tiles`
#   is the whole footprint (head first) and falls back to the single position for
#   everybody else, so a tap on a worm's tail is a tap on the worm, and nothing
#   changes for the four species that are one tile big.
func _stompable_ids_at(t: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for raw in actors:
		var id := String(raw)
		if not SpeciesDefs.is_stompable(String(actors[id].get("species", ""))):
			continue
		if Movement.is_under(self, id):
			continue
		if t in Movement.occupied_tiles(self, id):
			out.append(id)
	out.sort()
	return out


# ...and gone. Returns how many went, so the caller can tell a stomp from a swing
# at nothing.
func _stomp(t: Vector2i) -> int:
	var doomed := _stompable_ids_at(t)
	for id in doomed:
		despawn_actor(id)
	return doomed.size()


# An actor that acts without having been spawned still gets a meter. Since M2.5
# WI-3 spawned the crow properly, nothing in the running game takes this path —
# only tests that name an actor out of thin air, and whatever the next milestone
# forgets to register. Since ids are species names in phase 1, an id that names a
# species is registered as one; anything else gets a species-less entry at
# (-1, -1), which is the honest record of "something acted here and nobody
# spawned it".
func _ensure_actor(actor_id: String) -> Dictionary:
	if not actors.has(actor_id):
		spawn_actor(actor_id, actor_id if SpeciesDefs.has(actor_id) else "", Vector2i(-1, -1))
	return actors[actor_id]


func energy_of(actor_id: String) -> int:
	if _is_player(actor_id):
		return -1  # the player's meter is GameState's, not the world's
	var e: Dictionary = actors.get(actor_id, {})
	if e.is_empty():
		return ACTOR_MAX_ENERGY  # nobody on record reads as rested, as it always did
	return int(e.get("energy", ACTOR_MAX_ENERGY))


func is_exhausted(actor_id: String) -> bool:
	return not _is_player(actor_id) and energy_of(actor_id) <= 0


func set_actor_energy(actor_id: String, value: int) -> void:
	if _is_player(actor_id):
		return
	_ensure_actor(actor_id)["energy"] = maxi(0, value)


func spend_actor_energy(actor_id: String, cost: int) -> void:
	if _is_player(actor_id) or cost <= 0:
		return
	var e := _ensure_actor(actor_id)
	e["energy"] = maxi(0, int(e.get("energy", ACTOR_MAX_ENERGY)) - cost)


# The cast a world contains when nothing on record says otherwise: worldgen's
# step 9, and a load whose save predates the registry.
#
# `from_stream` is the whole difference between those two callers. Worldgen may
# draw the hen's tile from the shared RNG stream, because `generate()` is one
# deterministic sequence that a replay repeats exactly. A **load must not draw at
# all**: consuming the stream inside `restore()` would shift every later draw of
# the session that continues from it, which is precisely the desync
# `SimRng.stateless()` was invented for. So a legacy load places her by rule.
func spawn_default_actors(from_stream: bool = false) -> void:
	actors.clear()
	_brain_events.clear()
	var start := _start_tile()
	spawn_actor(ACTOR_PLAYER, SpeciesDefs.PLAYER, start)
	# She is in the world exactly while her scene is: an unopened cold-open gate
	# is the same evidence `ColdOpen.is_done()` reads, so a save restored
	# mid-scene brings her back and one restored after it does not.
	if not ColdOpen.is_done(self):
		var plot: Dictionary = layout.get("neighbour_plot", {})
		spawn_actor(ACTOR_NEIGHBOUR, SpeciesDefs.NEIGHBOUR, plot.get("wave_at", start))
	spawn_actor(ACTOR_CHICKEN, SpeciesDefs.CHICKEN, _chicken_tile(start, from_stream))


# Where the cast stands when nobody is on record: the layout's spawn, unless
# **this world disagrees with the layout it is being read against** (2026-09-06).
#
# A generated world never disagrees. A *restored* one can: an autosave written
# before the door still has the cot standing out in the yard, on the very tile
# the composed world now starts her on, and the legacy load path would have put
# her — and then the hen, drawn from the tiles reachable from her — inside the
# furniture. So the start tile steps aside to the nearest walkable one.
#
# By rule and never by a draw, for `spawn_default_actors`' reason: a load must
# not consume the shared RNG stream. Nearest first, then row-major, so the answer
# is the same on every machine and in every replay.
func _start_tile() -> Vector2i:
	var start := WorldLayout.spawn(layout)
	if is_walkable(start.x, start.y):
		return start
	var best := start
	var best_d := MAP_WIDTH * MAP_HEIGHT
	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			if not is_walkable(tx, ty):
				continue
			var d := absi(tx - start.x) + absi(ty - start.y)
			if d < best_d:
				best_d = d
				best = Vector2i(tx, ty)
	return best


func _chicken_tile(start: Vector2i, from_stream: bool) -> Vector2i:
	var reachable := reachable_from(start)
	if reachable.is_empty():
		return start
	if from_stream:
		return reachable[SimRng.randi() % reachable.size()]
	# By rule, for the no-draw path: the first tile the flood fill reaches that is
	# not the spawn point itself, so a pre-registry save wakes with the hen beside
	# the player rather than under her.
	for t in reachable:
		if t != start:
			return t
	return reachable[0]


# Ground-mode pathing, over sim truth, with no autoload in sight — the
# `Pathfinding` autoload is presentation's wrapper (it takes a `Node2D` farm) and
# layer 2 may not touch it. **Since M2.5 WI-4 both of these are one line**: the
# search itself lives in `systems/sim/movement.gd`, per movement capability, and
# these are the ground-mode names worldgen, the hen's brain and the tests already
# call. WI-3 wrote them as the deliberate ground-only special case and said the
# general function was WI-4's deliverable; this is that, and the special case is
# now a default argument.
func reachable_from(start: Vector2i) -> Array[Vector2i]:
	return Movement.reachable(self, SpeciesDefs.GROUND, start)


# The waypoints from `start` to `goal` (excluding `start`), or [] when there is
# no walkable route.
func path_between(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	return Movement.path(self, SpeciesDefs.GROUND, start, goal)


# --- Sim time: the brains ride the clock (M2.5 WI-3) ---------------------------
#
# **A brain is `step(world, actor, tick) -> action | null`** (see
# `systems/sim/brains/brain.gd`), and this is where they get stepped. Each
# clock-driven actor holds exactly one pending event; when it dispatches, that
# actor's brain decides, whatever it returns goes through `apply_action` like
# anybody else's Action, and the brain is rescheduled for whenever it said it
# next wants to think.
#
# **Cost is per decision, never per tick** (plan §1 rule 8): a dozing hen who
# asked to be woken in four seconds costs one heap entry for those forty ticks,
# and a world with nobody in it costs nothing at all. `next_event_tick()` is what
# lets this jump rather than count.
#
# **Nothing in here reads wall-clock time.** Somebody has to convert frames into
# ticks and that somebody is `main.gd` — the same boundary its per-run `randi()`
# seed lives on, and for the same reason (rule 7). Fast-forward paths advance the
# clock explicitly instead.
const BRAIN_EVENT := "brain"


# Advance sim time to `target_tick`, letting brains decide along the way.
# Returns every Action they took, in dispatch order, as
# `[{ "action": {...}, "result": {...}, "tick": n }]` — the caller's record of
# what the world did while it was not looking. `world/farm.gd` is what turns that
# into replay entries and trace lines; the sim does not know those exist.
#
# The tick is in there because it is half of what the Action means (M2.5 WI-5):
# a replay's dual-record net compares a recomputed brain Action against the
# recorded one, and "the same verb on the same tile three seconds late" is a
# desync, not a match.
func advance_to_tick(target_tick: int, gs = null) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	if target_tick <= clock.tick:
		return taken
	while true:
		var next := clock.next_event_tick()
		if next < 0 or next > target_tick:
			break
		# Dispatched a whole tick at a time, and the events are *collected* before
		# any of them is handled: a brain that spawns or reschedules during its own
		# step must not be able to perturb the queue it is being read out of.
		for e in clock.advance_to(next):
			_dispatch(e, gs, taken)
	clock.advance_to(target_tick)
	return taken


func advance_ticks(ticks: int, gs = null) -> Array[Dictionary]:
	return advance_to_tick(clock.tick + maxi(0, ticks), gs)


func _dispatch(event: Dictionary, gs, taken: Array[Dictionary]) -> void:
	if String(event.get("kind", "")) != BRAIN_EVENT:
		return
	var actor_id := String(event.get("actor", ""))
	if not actors.has(actor_id):
		return  # despawned since it was scheduled; its event is not its ghost
	var brain := Brains.of_actor(self, actor_id)
	var action := brain.step(self, actor_id, clock.tick, gs)
	if not action.is_empty():
		var result := apply_action(action, gs)
		brain.on_result(self, actor_id, action, result)
		taken.append({ "action": action, "result": result, "tick": clock.tick })
	# The brain may have despawned itself (a crow leaving the map), or been
	# despawned by its own Action's consequences (the neighbour opening the gate).
	if actors.has(actor_id):
		_schedule_brain(actor_id, int(actors[actor_id]["extra"].get("wake", clock.tick + 1)))


# One pending think per actor: the previous event is cancelled rather than left
# to fire twice, so a day turn or a spawn can wake somebody without doubling them
# up. Kept **beside** the registry rather than inside an entry, because a
# scheduling handle is not a fact about an actor: it is not saved, not replayed,
# and not part of what "the same registry" means (which is also what lets the unit
# suite compare two registries entry for entry).
var _brain_events: Dictionary = {}  # actor_id -> pending SimClock event id


func _schedule_brain(actor_id: String, at_tick: int) -> void:
	if not actors.has(actor_id) or not Brains.of_actor(self, actor_id).on_clock():
		return
	if _brain_events.has(actor_id):
		clock.cancel(int(_brain_events[actor_id]))
	_brain_events[actor_id] = clock.schedule(
		maxi(at_tick, clock.tick + 1), { "kind": BRAIN_EVENT, "actor": actor_id })


# Everybody thinks again. Called after a load (a restored registry never went
# through `spawn_actor`, so without this a reloaded farm would stand perfectly
# still) and at the day turn, so a morning lands on the morning rather than
# whenever the hen next happened to be due.
#
# **Cancel before forgetting** — the handles are dropped by cancelling them, not
# by clearing the map. Clearing it first left every previously scheduled think in
# the clock's heap with nothing left holding its id, so a day turn added a think
# instead of moving one: after three sleeps the hen woke four times on the same
# tick and pottered four times as fast, and after ten days, eleven. **Found by
# WI-5's dual-record net** — a continued session's hen ended up on a different
# tile than her replay's, because a restored world starts with an empty queue and
# a played one had been accumulating ghosts since morning. It is the invariant
# this file already claimed two comments up ("one pending think per actor"), now
# actually held.
func schedule_all_brains() -> void:
	for id in _brain_events.keys():
		clock.cancel(int(_brain_events[id]))
	_brain_events.clear()
	for id in actors.keys():
		_schedule_brain(id, clock.tick + 1)


func apply_action(action: Dictionary, gs = null) -> Dictionary:
	var result := _apply(action, gs)
	if result.get("ok", false) and gs != null \
			and String(action.get("actor", "")) == "player" \
			and not NON_WORK_VERBS.has(action.get("verb", "")) \
			and "actions_today" in gs:
		gs.actions_today += 1
		# T-20's action clock has just moved, which is the only thing that can
		# bring a crow. Decided here rather than in `main.gd` (M2.5 WI-3) so a
		# replay and a headless fast-forward see the same birds arrive at the same
		# moments as the session that recorded them — the spawner's readiness gate,
		# target choice and entry draws were the last gameplay decisions living in
		# presentation.
		_send_due_crows(gs)
		# ...and the same appointment book, for the raid (M2.5 WI-8a). A no-op in
		# every real game: `ANT_RAIDS_PER_DAY` is 0, so the schedule is empty on
		# every day of it.
		_send_due_ants(gs)
		# ...and everyone in the visitors' table (M2.5 WI-8c/8f/8g), whose books
		# are empty in every real game for the same reason.
		_send_due_visitors(gs)
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
		# The placeholder acquisition rule (2026-09-03): everything the studio
		# introduces to the farm is bought here until a richer story exists. A
		# sibling of `buy_seed` rather than a generalisation of it, deliberately —
		# `buy_seed` is written into every replay log on disk and into the demo
		# replay, and those are phase 4's training corpus (S-3). A new verb costs
		# one match arm; reinterpreting an old one costs the archive.
		"buy_machine":
			if gs == null: return _fail("no_state")
			return { "ok": gs.buy_machine(String(action.get("item", ""))) }
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
			# T-30 (Q-48): the same verb, on the acorn the crow was going to eat.
			# **This is the ramp in her own hands** — the stock is finite and does
			# not regenerate (T-15), so every acorn she pockets is one fewer meal
			# between the crows and her crops, and a player who wants the Q-12
			# proof sooner can bring the pests forward herself. The proof and the
			# acorn design are otherwise untouched; nothing here refills anything.
			#
			# Free, like the egg: `collect` is a special-object verb and costs no
			# energy. It still advances the day's action clock, exactly as picking
			# up an egg does (see NON_WORK_VERBS) — bending down is work.
			if obj == "acorn":
				set_object(target.x, target.y, "")
				gs.acorns += 1
				return { "ok": true, "collected": "acorn" }
			# **A machine is picked back up with the same verb** (2026-09-03), the
			# egg's and the scarecrow's rule applied to the thing that walks: what
			# a hand does with a square first is pick up what is on it. No new
			# verb, no new UI, and a future bot tidying the farm needs nothing the
			# player lacks (S-3, ground rule 1).
			#
			# Asked after the objects, because an egg laid at a sprinkler's feet is
			# the smaller, more perishable thing and is what a tap plainly means.
			var machine_id := machine_at(target)
			if machine_id != "":
				var machine_key := machine_key_of(machine_id)
				despawn_actor(machine_id)
				gs.machines[machine_key] = int(gs.machines.get(machine_key, 0)) + 1
				return { "ok": true, "collected": machine_key, "machine": machine_id }
			return _fail("nothing_to_collect")

		# -- the door (2026-09-06) --------------------------------------------
		#
		# **Going indoors is an Action.** The farm and the home are two pages of
		# one grid (see WorldLayout's page block), and the only way between them
		# is this verb — not a scene swap, not a presentation teleport. It is a
		# verb because it changes where an actor is, and where an actor is has
		# been sim truth since Q-53: a save knows which room she is in, a replay
		# puts her back through the same door at the same point in the stream, and
		# the phase-4 corpus records the transition like everything else she does.
		#
		# **Player-only, deliberately** — the one place the ground rule ("a bot
		# gets no verb the player lacks") is knowingly held from the other side.
		# Nothing else in the game has business indoors in phase 1: a hen that
		# wandered through the door would be standing in a room nobody is looking
		# at, and no brain has any notion of pages. When something else is meant
		# to follow her in, this guard is the one line that has to change.
		#
		# **It refuses rather than guesses.** A world with no door table — every
		# save written before today, migrated to v3 as one farm page and a page of
		# darkness — has no pair to look up, so the verb fails cleanly and an old
		# farm keeps playing exactly as it did.
		"use_door":
			if not _is_player(String(action.get("actor", ""))):
				return _fail("not_the_player")
			if not WorldLayout.is_door_object(get_object(target.x, target.y)):
				return _fail("no_door_here")
			var pair := WorldLayout.door_at(target, layout)
			if pair.is_empty():
				return _fail("door_leads_nowhere")
			# Adjacency is the special-object idiom (`Pathfinding.find_path_toward`
			# walks her to a neighbouring tile and stops): she stands beside the
			# door and reaches for it. Manhattan ≤ 1 rather than = 1, so standing
			# *on* one — which nothing can do today, since a door blocks — is not
			# a refusal some future layout would have to work around.
			var from := actor_pos(ACTOR_PLAYER)
			if absi(from.x - target.x) + absi(from.y - target.y) > 1:
				return _fail("too_far")
			var dest: Vector2i = pair.get("to", Vector2i(-1, -1))
			if not is_walkable(dest.x, dest.y):
				return _fail("door_is_blocked")
			var face := String(pair.get("face", "down"))
			# The same write a walk makes (M2.5 WI-6's one sanctioned exception),
			# so her tile is sim truth on the far side too. Presentation reads
			# `dest` off the result and puts her body there — a teleport is not a
			# crossing, which is spawn's rule.
			set_actor_pos(ACTOR_PLAYER, dest, face)
			return { "ok": true, "dest": dest, "face": face }

		# -- machines (2026-09-03) --------------------------------------------
		#
		# Both are verbs rather than sim functions because both change the world:
		# `place` puts a new actor in it, `configure` changes what an actor does.
		# A spawn is not normally a verb (see the registry block) — this one is,
		# because it is *a thing the player does*, with her hands, out of a crate
		# she paid for, and everything downstream depends on it being recorded:
		# the replay, the autosave, and the bot that will one day place machines
		# itself with the same word she used.
		"place":
			if gs == null: return _fail("no_state")
			var item := String(action.get("item", ""))
			if not MachineDefs.has(item): return _fail("unknown_machine")
			var ptile := get_tile(target.x, target.y)
			if ptile.is_empty() or ptile.get("state", "") == "": return _fail("out_of_bounds")
			# **What she is holding is part of the question** (2026-09-06): a stall
			# needs the square beside it as well, and a robot is the one thing that
			# may be set down *in* a stall.
			if not placeable_at(target, item): return _fail("occupied")
			var placer := String(action.get("actor", ""))
			var placer_charged: bool = _is_player(placer)
			if placer_charged and int(gs.machines.get(item, 0)) <= 0: return _fail("no_machine")
			var place_cost: int = Tools.get_energy_cost("place")
			if placer_charged and gs.hard_energy and gs.energy < place_cost: return _fail("no_energy")
			if placer_charged:
				gs.set_energy(gs.energy - place_cost)
			else:
				spend_actor_energy(placer, place_cost)
			# **A structure is put down, not deployed** (the stall, 2026-09-06). It
			# spawns nobody: two objects go onto the grid, the crate loses one, and
			# setting it down costs exactly what setting a machine down costs — the
			# work is in her arms, not in what she built. The same verb because it is
			# the same act, which is what keeps a future bot able to build one with
			# nothing new to learn (S-3, ground rule 1).
			if not MachineDefs.spawns_actor(item):
				set_object(target.x, target.y, WorldLayout.ROBOT_STALL)
				var slot := target + STALL_SLOT_OFFSET
				set_object(slot.x, slot.y, WorldLayout.ROBOT_STALL_SLOT)
				if placer_charged:
					gs.machines[item] = int(gs.machines.get(item, 0)) - 1
				return { "ok": true, "structure": item, "slot": slot }
			var machine_id := next_machine_id(item)
			var config := String(action.get("config", MachineDefs.default_config(item)))
			if not config in MachineDefs.configs_of(item):
				config = MachineDefs.default_config(item)
			# The bot has one door into a world and this is it: `BotBrain.deploy`
			# is what builds a valid `extra` for a config, and routing around it
			# would be the second place that knowledge lives. Every other machine
			# is a plain registry row.
			if MachineDefs.species_of(item) == SpeciesDefs.BOT:
				BotBrain.deploy(self, machine_id, config, target,
					{ "owner": placer if placer != "" else ACTOR_PLAYER })
			else:
				spawn_actor(machine_id, MachineDefs.species_of(item), target)
			# Which row it was bought from, stamped on the actor. The two robot
			# marks share a species, so without this a picked-up mark-1 could go
			# back into the crate as a mark-2 (see `machine_key_of`).
			actors[machine_id]["extra"]["model"] = item
			if placer_charged:
				gs.machines[item] = int(gs.machines.get(item, 0)) - 1
			return { "ok": true, "machine": machine_id, "config": config }

		# Turning the dial on a machine that is already down. Free, and off the
		# action clock (NON_WORK_VERBS): it is a setting, not a stroke of work.
		#
		# Implemented as a re-deploy at the same tile so that a config's `extra`
		# is built by exactly one piece of code — a shoo bot switched to circle
		# must not keep a stale `home_x` that nothing reads and a save still
		# carries. The one thing carried across is its **energy**, because a
		# machine that could be rested by twiddling its dial would be a free day's
		# work (Q-11's meter, `spend_actor_energy`).
		"configure":
			var target_id := machine_at(target)
			if target_id == "": return _fail("no_machine_here")
			var target_key := machine_key_of(target_id)
			var wanted := String(action.get("config", ""))
			if not wanted in MachineDefs.configs_of(target_key): return _fail("bad_config")
			var before: Dictionary = actor(target_id)
			var kept_energy: int = int(before.get("energy", ACTOR_MAX_ENERGY))
			var kept_owner := String(before.get("extra", {}).get("owner", ACTOR_PLAYER))
			BotBrain.deploy(self, target_id, wanted, actor_pos(target_id), { "owner": kept_owner })
			actors[target_id]["energy"] = kept_energy
			actors[target_id]["extra"]["model"] = target_key
			return { "ok": true, "machine": target_id, "config": wanted }

		# **Teaching a mark-1 a tile** (designer, 2026-09-03). One tap, one entry in
		# the machine's list, one recorded Action — so a session in which she
		# taught a robot replays into a robot that knows the same eight squares.
		#
		# A *toggle*, because that is what a list she is building with her finger
		# wants: tapping a taught tile takes it back off, which is the only undo a
		# tap-only interface can offer without inventing a second gesture.
		#
		# It costs nothing and does not tick the day's action clock: pointing at
		# eight tiles is one instruction, not eight strokes of work, and charging
		# for it would make teaching the machine cost more of the day than doing
		# the watering herself.
		#
		# The machine is named in the Action rather than found under the target,
		# because the tile she is pointing at is a crop row and the machine is
		# somewhere else entirely.
		"teach":
			var taught_id := String(action.get("machine", ""))
			if not actors.has(taught_id): return _fail("no_machine_here")
			var taught_extra: Dictionary = actors[taught_id]["extra"]
			if String(taught_extra.get("config", "")) != BotBrain.CONFIG_ORDERS:
				return _fail("not_teachable_machine")
			if not teachable_at(target): return _fail("not_teachable")
			var taught := BotBrain.orders_of(taught_extra)
			var known := taught.find(target)
			if known >= 0:
				taught.remove_at(known)
				BotBrain.set_orders(taught_extra, taught)
				return { "ok": true, "machine": taught_id, "taught": false,
					"orders": taught.size() }
			if taught.size() >= BotBrain.ORDER_LIMIT: return _fail("orders_full")
			taught.append(target)
			BotBrain.set_orders(taught_extra, taught)
			return { "ok": true, "machine": taught_id, "taught": true,
				"orders": taught.size() }

		# **Sending a mark-1 out for the day.** It walks its list once and stops;
		# tomorrow morning it may be sent again (`BotBrain.on_new_day`). The
		# once-a-day limit is the machine's capability ceiling, not a cooldown —
		# a mark-1 retires one round of watering, and the rest of the day is
		# still hers.
		#
		# Free and off the action clock, like the teaching: giving an instruction
		# is not labour. What the machine then spends is its **own** energy meter,
		# one water at a time, exactly as every other actor does.
		"activate":
			var sent_id := machine_at(target)
			if sent_id == "": return _fail("no_machine_here")
			var sent_extra: Dictionary = actors[sent_id]["extra"]
			if String(sent_extra.get("config", "")) != BotBrain.CONFIG_ORDERS:
				return _fail("not_sendable")
			if BotBrain.orders_of(sent_extra).is_empty(): return _fail("no_orders")
			if bool(sent_extra.get("ran_today", false)): return _fail("already_sent")
			sent_extra["sent"] = true
			sent_extra["ran_today"] = true
			sent_extra["at_order"] = 0
			# It is standing still with a long idle wake on it (see the brain's
			# IDLE_SECONDS): being sent has to wake it now, or she would tap "send"
			# and watch it do nothing for half a minute.
			_schedule_brain(sent_id, clock.tick + 1)
			return { "ok": true, "machine": sent_id,
				"orders": BotBrain.orders_of(sent_extra).size() }

		# -- day transition --
		"sleep":
			if gs == null: return _fail("no_state")
			gs.start_new_day()
			if action.has("weather"):  # replay override: reproduce the logged roll
				gs.weather = action.weather
				gs.weather_changed.emit(gs.weather)
			advance_day(gs.weather, gs)
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
			var by_cold_open := String(opened.get("opened_by", "")) == WorldLayout.OPENED_BY_COLD_OPEN
			# She leaves the world as well as the farm (M2.5 WI-2). Spawn and
			# despawn are sim facts, so her departure is one: it happens in the
			# gateway, which is what makes a replay and a reload agree about when
			# the registry stops containing her. It keeps one invariant true from
			# both directions — the neighbour is registered exactly while her gate
			# is closed, whether this world was generated, restored or replayed to
			# here. Her *node* still leaves on its own (entities/neighbour.gd);
			# renderers stop being the authority on who exists in WI-6.
			if by_cold_open:
				despawn_actor(ACTOR_NEIGHBOUR)
			if gs != null and by_cold_open and "takeover_day" in gs:
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
		# could not exercise by hand — which since T-30 (Q-48) she literally has:
		# the same acorn answers her `collect`, and the tile ends up empty either
		# way. Two verbs because the outcomes differ (hers goes in a pocket), not
		# because the bird can reach something she cannot.
		"eat_acorn":
			if get_object(target.x, target.y) != "acorn": return _fail("no_acorn")
			set_object(target.x, target.y, "")
			return { "ok": true }
		"eat_crop":
			var tile := get_tile(target.x, target.y)
			if tile.is_empty(): return _fail("out_of_bounds")
			# `has_crop` is the one definition of "there is something growing
			# here" (M2.5 WI-8): the guard and the mouths that go looking for a
			# meal read the same function, so a critter can never smell a tile the
			# gateway would then refuse it.
			if has_crop(target.x, target.y):
				set_tile_state(target.x, target.y, "tilled")
				return { "ok": true }
			return _fail("no_crop")
		"lay_egg":
			if get_object(target.x, target.y) != "": return _fail("occupied")
			set_object(target.x, target.y, "egg")
			return { "ok": true }
		"crow_scared":
			# Player-caused scare event; feeds the Q-12 capability proof.
			# It is a *report*, not a capability (see SpeciesDefs.ENTITY_VERBS):
			# the bird tells the sim it was frightened, and the sim ends its visit.
			# Proximity to the player is still measured presentation-side, because
			# where she is standing is not sim truth until the movement engine lands
			# (WI-4/WI-6) — but the report is an Action through the one gateway, so
			# it is recorded, and a replay ends the visit at the same point in the
			# stream that the session did.
			#
			# **Who caused it is part of the report** (M2.5 WI-9). `by` is the actor
			# that did the frightening, and **absent means the player** — which is
			# every report the game has ever written, because `entities/crow.gd`
			# names nobody and never needed to. A shoo-bot names itself.
			#
			# **A machine's scare counts as hers** (`[Designer]` Q-66, ruled
			# 2026-08-31: *credit flows up*). WI-9 shipped the conservative half —
			# a bot ended the visit but did not fill in the Q-12 proof — and the
			# designer ruled the delegation reading instead: by phase 4 the whole
			# game is "the farm runs without you", she built and placed the machine,
			# and a proof that refused her the work her fleet did would be the game
			# disagreeing with its own thesis. So `gs.crows_scared` counts the
			# scare whoever caused it, and `by` stays on the report because *which*
			# machine did it is still worth knowing (and is what the reason below
			# is drawn from).
			if gs == null: return _fail("no_state")
			var by := String(action.get("by", ACTOR_PLAYER))
			var by_player := _is_player(by)
			gs.crows_scared += 1
			# The *kind* of cause, not the id: the reason string is what a renderer
			# matches on to pick a noise (`entities/crow.gd:_announce_departure`),
			# and it wants "a person did this" / "a machine did this", not a
			# registry key.
			Brains.flee(self, String(action.get("actor", "")), "player" if by_player else "bot")
			return { "ok": true, "by": by }

		# -- energy-costed tile verbs --
		"clear_weed", "clear_log", "clear_rock", "clear_tree", "till", "plant", "water", "harvest":
			if gs == null: return _fail("no_state")
			var tile := get_tile(target.x, target.y)
			if tile.is_empty() or tile.get("state", "") == "": return _fail("out_of_bounds")
			# The dark outside a room is not land, so nothing can be done to it
			# (2026-09-06). Named as what it is rather than given a refusal of its
			# own: a void tile is the edge of the map, drawn on the inside of a page.
			# Nobody can tap one — nothing walks there and the router offers nothing
			# on it — so this is the gateway's backstop, exactly like the yard's rule
			# below.
			if String(tile.get("state", "")) == WorldLayout.VOID:
				return _fail("out_of_bounds")
			# T-32: the yard is home, not field, and its ground is the one thing a
			# hoe never opens. Stated at the gateway rather than in the router so it
			# binds the neighbour, a crow and a phase-4 bot exactly as it binds her
			# (S-3, ground rule 1) — a bot gets no verb the player lacks, and no
			# ground the player cannot work either.
			#
			# **T-18 is untouched by this refusal, because a tap can never reach
			# it.** `yard` is in no tool's `can_act_on` and in no `is_workable`
			# state, so `ActionRouter.resolve` produces nothing for a yard tile and
			# the tap degrades to plain movement — she walks there and stands on it.
			# The only things that arrive here are a direct Action: a replay
			# recorded on an older worldgen, or a test asking the question.
			# T-37 extends the same rule to the home's floor: home ground, indoors
			# or out, is the ground a hoe never opens.
			# A shed is standing here (2026-09-06). A stall bay is walkable — it is
			# a building she and her robots step into — so it is the one kind of
			# square where "there is soil under my feet" and "there is a structure
			# on this tile" are both true, and the gateway has to say which wins.
			# The structure does: no tilling the floor of the shed, no planting in
			# it, no watering it. Stated for every actor at once, like the yard's
			# rule below, so a bot is bound by it exactly as she is.
			if is_stall_tile(target):
				return _fail("occupied")
			if verb == "till" and String(tile.get("state", "")) in [WorldLayout.YARD, WorldLayout.FLOOR]:
				return _fail("not_tillable")
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
					# **A critter underfoot is what the clear answers** (P-10's
					# "stomp scouts", `design/04` §4; M2.5 WI-8a). The stomp takes
					# precedence over the ground and *leaves the tile alone*: the
					# verb means "deal with the small thing on this square", and an
					# ant on a row of wheat must not cost the player the wheat.
					# Deliberately not its own verb — a bot answering a scout does
					# exactly what a child's tap does (ground rule 1), and nothing
					# in the router or the sim had to learn a new word.
					#
					# It does not count as clearing an obstacle: T-10 and Q-46 ask
					# "has she ever cleared one of *these*", and a stomped ant is
					# not evidence about a rock.
					if _stomp(target) > 0:
						return { "ok": true, "stomped": true }
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
					# P-10's counterplay, with no new verb and no new UI: water on a
					# tile washes **every** scent channel off it, so a trail through
					# a watered tile is broken rather than weakened (M2.5 WI-7).
					# Wired at the one place the verb resolves, so a bot watering and
					# a child tapping do the same thing to a trail.
					#
					# Unconditional, and deliberately not limited to the soil states
					# `water_tile` wets: what wets a crop is a fact about soil, what
					# washes a trail is a fact about water. No shipping species writes
					# scent yet, so today this always erases nothing.
					scent.wash(target)
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


# T-20: each crow has a single scheduled arrival, given as a point in the day's
# action clock, and **it is consumed whether the bird gets fed, gets shooed, or
# never comes at all** — so chasing one off is a win for the day rather than a
# ten-second reprieve. The rule that decides whether a bird actually arrives is
# `may_spawn_crow` (T-2) and it lives with the rest of the crow's brain
# (`CrowBrain.send`); this is only the clock reaching the appointment.
func _send_due_crows(gs) -> void:
	if gs == null or not ("crow_schedule" in gs):
		return
	while not gs.crow_schedule.is_empty() and int(gs.actions_today) >= int(gs.crow_schedule[0]):
		var arrival := int(gs.crow_schedule[0])
		gs.crow_schedule.remove_at(0)
		CrowBrain.send(self, gs, arrival)


# The same clock reaching a raid's appointment (M2.5 WI-8a). Consumed whether a
# raid actually starts or not, exactly as T-20 rules for the crow: a farm gets
# one raid's chance a day, and stomping the scout is a win for the day rather
# than a pause. The rule about whether one *may* start is `may_start_raid`, and
# the arrival itself is `AntScoutBrain.send`.
func _send_due_ants(gs) -> void:
	if gs == null or not ("ant_schedule" in gs):
		return
	while not gs.ant_schedule.is_empty() and int(gs.actions_today) >= int(gs.ant_schedule[0]):
		var arrival := int(gs.ant_schedule[0])
		gs.ant_schedule.remove_at(0)
		AntScoutBrain.send(self, gs, arrival)


# ...and the same clock reaching everybody else's (M2.5 WI-8c/8f/8g). One loop
# over the visitors' table instead of a `_send_due_*` per species: what differs
# between a rabbit and a songbird is a row in `visitors()` and a brain, and
# neither of those is a copy of this function.
#
# The appointment is consumed whether anything comes of it or not — T-20's rule,
# which is why it is spelled the same way here as it is two functions up. Which
# species the arriving actor is *is* the dispatch: `Brains.of_species(...).arrive`
# means the gateway never learns what a rabbit is.
#
# **Empty in every real game**: every `per_day` in the table is 0, so
# `GameState.start_new_day` rolls an empty book for each of them on every day of
# every session, and this loop finds nothing to do.
func _send_due_visitors(gs) -> void:
	if gs == null or not ("visitor_schedules" in gs):
		return
	for raw in visitors().keys():
		var species := String(raw)
		# The live array, not a copy: consuming an appointment has to actually
		# spend it, and Godot arrays are references.
		var book: Array = gs.visitor_schedules.get(species, [])
		while not book.is_empty() and int(gs.actions_today) >= int(book[0]):
			var arrival := int(book[0])
			book.remove_at(0)
			Brains.of_species(species).arrive(self, gs, species, arrival)


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


# `gs` is optional and is only needed by the machines below (M2.5 WI-10): a day
# turn without a GameState is a test fixture arranging a grid, not a farm waking
# up, and the sleep verb — the only caller in the running game — always has one.
func advance_day(weather: String, gs = null) -> void:
	# Everyone wakes rested, the player included (GameState.start_new_day does
	# hers). An NPC's tiredness is a within-day thing, same as the farmer's.
	# Every *registered* actor, which since M2.5 WI-2 is the same set that used to
	# be "everyone with a meter on record" plus the ones who have not worked yet
	# and were already reading as full.
	for id in actors:
		if _is_player(id):
			continue  # hers is GameState's, and hers is also the clock
		actors[id]["energy"] = ACTOR_MAX_ENERGY
	# A new morning is a fact each brain acts on the *next time it thinks*, never
	# inside the day turn itself (M2.5 WI-3). The hen's egg is the case that makes
	# the rule: a replay re-applies the sleep but does not run brains, so a coin
	# flip taken here would be taken twice — once recorded live, once re-rolled on
	# replay. So the day turn only tells them, and wakes them, and what they do
	# about it arrives as an ordinary recorded Action.
	Brains.on_new_day(self)
	schedule_all_brains()
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

			# **Rain falls on ripe soil too.** This list used to be the growth
			# pass's list — seeded and growing, the states water *does* something
			# to — plus bare tilled ground, which is why a ripe crop stood on dry
			# soil while the row beside it was wet. Reported from play 2026-09-01:
			# "when weather is rainy and corn was ready to collect, the ground drew
			# as dry instead of wet under it. Unripe corn still had wet ground."
			# Confirmed against this loop rather than guessed: a tile that ripens
			# is set dry two lines up and then skipped here, so it is dry in the
			# sim and no renderer could have drawn it otherwise.
			#
			# **Mechanically inert, deliberately.** Every reader of the flag —
			# this growth pass, `water_tile`, the router's water offer and its
			# already-watered answer, the vignette's dry-crop beat, the cold open's
			# brain — is gated on seeded/growing, so a wet ripe tile changes
			# nothing that happens and only changes what is drawn (a test asserts
			# it: a ripe tile left in the rain does not grow).
			if weather == "rainy" and tile.state in ["tilled", "seeded", "growing", "ready"]:
				tile.watered_today = true

	# ...and the rain does to a trail what her watering can does to one tile of it
	# (`[Designer]` Q-58, ruled 2026-08-31: **rain washes everything**). Water is
	# water: the sky is not a second rule about scent, it is the same rule over the
	# whole farm, so a raid's trail does not survive a wet night.
	#
	# **Every channel, not the pest trail alone** — `Scent.wash` made that choice
	# for the bucket and this is the same choice for the same reason. It is a loop
	# over the *written cells* and never over the map (P-10's guardrail), so a farm
	# nobody has marked pays nothing for a rainy morning. Deterministic because the
	# weather is: the day's roll is sim state, and a replay re-applies it.
	if weather == "rainy":
		scent.wash_all()

	# The machines, last (M2.5 WI-10). **After** the pass above, deliberately: it
	# has just harvested yesterday's water and cleared every tile, so watering here
	# is watering the morning the farm is turning into — which is what "the tiles in
	# its radius wake watered" means, and it is the same seat rain takes two lines
	# up. Watering before it would pour into a bucket the growth pass then empties.
	#
	# These are ordinary Actions through the ordinary gateway, so a sprinkler is
	# measured against ground rule 1 like any other actor and gets no capability the
	# player lacks. They are **recomputed on replay** rather than recorded (Q-53):
	# a replay re-applies the `sleep` that turned this day, and this runs inside it.
	# Empty on every farm in the game today — nothing places a machine (Q-15).
	if gs != null:
		for action in Brains.day_actions(self, gs):
			apply_action(action, gs)

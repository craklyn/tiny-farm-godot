# zoo.gd — the Zoo's roster, its field, and how each species gets into it (T-33)
#
# The designer, 2026-09-01: *"Some sort of way for us to experience the new
# entities in the game. Either a debug world (like our sound debug) or another
# 'zoo' of the entities we've created, and a way to select or add them in a
# useful way just to see them doing their thing in action."*
#
# The whole bestiary ships behind `PER_DAY := 0` dials (M2.5, `species_defs.gd`
# passim): every critter's lifecycle is built, scheduled and tested, and no live
# game has ever contained one. So the *only* way anybody has seen a rabbit is by
# reading a test's assertions. This is the door that fixes that.
#
# **The roster is enumerated, never listed.** `roster()` is `SpeciesDefs.ids()`
# minus the farmer, in the table's own order, and that is load-bearing rather than
# tidy: a bestiary that grows by one row a work item cannot have a hand-written
# panel beside it, because the row that gets forgotten is exactly the one nobody
# has looked at. Add a species row and it appears here, with its sprite, on the
# next run. `test_zoo` asserts the identity so it can never quietly drift.
#
# **Nothing in `systems/sim/` changed for this.** The zoo *consumes* the sim: it
# generates a world from its own layout, stocks it through the ordinary tile API,
# and puts each species in through the same entry point its real lifecycle uses —
# `CrowBrain.send`, `AntScoutBrain.send`, `AntForagerBrain.raise_column`,
# `Brain.arrive`, `BotBrain.deploy`, or a plain `spawn_actor` for the three that
# are simply placed. That is the point of a zoo: if an animal cannot be got into
# it with the game's own machinery, the zoo is showing you a lie.
#
# Layer note: no Node, no autoload, no rendering, no `Input`. It reads and writes
# a `SimWorld` the way a brain does, and it lives outside `systems/sim/` because
# it is a *tool* over the sim rather than part of it.
class_name Zoo
extends RefCounted

# Her row is in the table and she is not in the panel: the farmer is scenery here
# (the thing a follow-bot follows and a rabbit bolts from), not an exhibit, and
# there is exactly one of her. Everything else in the table is a button.
const EXCLUDED: Array[String] = [SpeciesDefs.PLAYER]

# The seed the zoo's world runs on. Its own, never the session's: the zoo shares
# the `SimRng` static with everything else, so it announces a seed on entry
# rather than inheriting whatever the title screen's attract loop left behind.
# Determinism stakes are zero here — nothing is recorded and nothing is compared —
# but house rules are house rules, and a zoo that laid out its field differently
# every visit would be harder to compare a critter against, not easier.
const SEED := 20260901

# The zoo's calendar. High enough that every readiness gate in `visitors()` is
# already satisfied (the strictest is the kangaroo's `min_day: 6`) and the crow's
# T-2 gate too, so a tap spawns the animal instead of silently spending an
# appointment on a farm that was not ready for it.
const DAY := 12
const HARVESTS := 5   # CROW_MIN_HARVESTS is 1; five is "she has clearly been farming"


# --- the field -----------------------------------------------------------------
#
# One parcel, no obstacles, no boundaries, no gates, no tools: a flat open field
# with nothing in the way of a walk, a hop, a burrow or a flight. It is a
# `WorldLayout`-shaped dictionary and nothing more, which is the whole reason
# `sim_world.gd:generate()` takes one (T-8's note: "do not reintroduce a computed
# distance-from-spawn").
#
# The four fixed objects (cot, bin, well, seed box) are `SimWorld.OBJECT_POSITIONS`
# and land here whatever the layout says. Left alone deliberately — a farm with
# its furniture in it is the farm these animals were designed against.
const LAYOUT := {
	"spawn": Vector2i(8, 10),
	"parcels": [
		{
			"id": "zoo",
			"rects": [Rect2i(1, 1, 30, 18)],
			"obstacle": "",
			"density": 0.0,
			"boundary": "",
			"gate": Vector2i(-1, -1),
			"opened_by": WorldLayout.OPENED_BY_START,
		},
	],
	"boundaries": [],
	"tools": [],
	# Placed by hand below instead, so the crow's larder is somewhere known rather
	# than wherever the seeded draw put it.
	"acorns": {},
	# No cold open, so `ColdOpen.is_done()` is true from the first frame and
	# `spawn_default_actors` never registers the neighbour. She arrives from the
	# roster like everybody else.
	"neighbour_plot": {},
}

# What the field is stocked with. Enough of each thing that every mouth in the
# bestiary finds its own food: grown crops for a grazer and a worm, seed in the
# ground for a mole, acorns for a crow (any acorn beats any crop — T-15/Q-39), and
# bare tilled soil for a sprinkler to have something to wet.
const PATCH := Rect2i(12, 8, 6, 3)                  # mixed growing / ready wheat
const SOWN: Array[Vector2i] = [                     # mole bait: seed in the ground
	Vector2i(12, 12), Vector2i(13, 12), Vector2i(14, 12), Vector2i(15, 12),
]
const TILLED: Array[Vector2i] = [Vector2i(16, 12), Vector2i(17, 12)]
const ACORNS: Array[Vector2i] = [Vector2i(24, 6), Vector2i(25, 12)]

# Where a placed machine goes. Cycled by tap count so a second sprinkler is a
# second machine rather than a second machine standing inside the first.
const SPRINKLER_TILES: Array[Vector2i] = [
	Vector2i(13, 13), Vector2i(16, 13), Vector2i(19, 9), Vector2i(11, 9),
]

# Where a thing that is simply *put somewhere* goes: near the farmer, spiralling
# out so the tenth hen is not on top of the first. Fixed order, so two visits to
# the zoo arrange themselves the same way.
const NEAR: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(2, 1), Vector2i(1, 2), Vector2i(-2, 1), Vector2i(-1, -2),
	Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(0, -3),
]


# --- the roster -----------------------------------------------------------------

## Every species with a button, in the species table's own order. **Derived from
## `SpeciesDefs.ids()`** — see the header: this is the claim that a new critter
## cannot be missed, and `test_zoo` holds it.
static func roster() -> Array[String]:
	var out: Array[String] = []
	for raw in SpeciesDefs.ids():
		var id := String(raw)
		if id in EXCLUDED:
			continue
		out.append(id)
	return out


## Which cell of its own sheet a species wears on its button. The *texture* is not
## here — it is read off the renderer `world/farm.gd` already binds to the species
## (`ACTOR_RENDERERS` → the entity script's `SPRITES`), so the zoo cannot end up
## showing a picture from a sheet the game does not draw that animal from. Only
## "which cell reads as this animal standing still" is a judgement, and that is
## what this table holds.
##
## A species with no renderer has no cell either, and gets a wordless-rule
## exemption: a text-only button, which is the honest state for art that has not
## landed. `test_zoo` asserts the two tables agree exactly.
const ICON_CELL := {
	# neighbour.png / bot.png are 4x4 sheets of 48px cells laid out
	# [down, up, left, right] x [idle, walk, walk, walk]; cell (0,0) is standing.
	SpeciesDefs.NEIGHBOUR: Rect2(0, 0, 48, 48),
	SpeciesDefs.BOT: Rect2(0, 0, 48, 48),
	# Every other species has its own one-row sheet (split 2026-09-06), so the
	# standing-still cell is the first — except the mole, whose first cell is a
	# bare mound; "surfaced" (cell 2) is the one that reads as the animal.
	SpeciesDefs.CHICKEN: Rect2(0, 0, 16, 16),
	SpeciesDefs.CROW: Rect2(0, 0, 16, 16),
	SpeciesDefs.SPRINKLER: Rect2(0, 0, 16, 16),
	SpeciesDefs.ANT_SCOUT: Rect2(0, 0, 16, 16),
	SpeciesDefs.ANT_FORAGER: Rect2(0, 0, 16, 16),
	SpeciesDefs.RABBIT: Rect2(0, 0, 16, 16),
	SpeciesDefs.MOLE: Rect2(2 * 16, 0, 16, 16),
	SpeciesDefs.WORM: Rect2(0, 0, 16, 16),
	SpeciesDefs.KANGAROO: Rect2(0, 0, 16, 16),
	SpeciesDefs.SONGBIRD: Rect2(0, 0, 16, 16),
}


## Which sprite script the farm would build for each species — `world/farm.gd`'s
## own `ACTOR_RENDERERS`, read rather than restated. Separated from `icon_of` so a
## test can check the tables agree without compiling an entity script (they name
## autoloads, which the unit suite has none of).
static func renderers() -> Dictionary:
	return load("res://world/farm.gd").ACTOR_RENDERERS


## Does the game have a picture of this species at all? Both halves must be true:
## a renderer the farm binds to it, and a cell of that renderer's sheet chosen as
## its portrait.
static func has_art(species: String) -> bool:
	return ICON_CELL.has(species) and renderers().has(species)


## `[texture, region]` for a species' button, or `[]` when its art has not landed.
## The texture comes from the renderer the farm would build for it, so there is one
## answer to "what does this animal look like" and this is not a second copy of it.
static func icon_of(species: String) -> Array:
	if not has_art(species):
		return []
	var path := String(renderers().get(species, ""))
	if path == "":
		return []
	var renderer: GDScript = load(path)
	if renderer == null:
		return []
	var sheet = renderer.get_script_constant_map().get("SPRITES", null)
	# A script that renders several species (the ants, the grazers) holds one
	# sheet per species; pick this one's.
	if sheet is Dictionary:
		sheet = sheet.get(species, null)
	if sheet == null:
		return []
	return [sheet, ICON_CELL[species]]


## The short label under the picture — the species row's own name, so a row
## renamed in the table is renamed here.
static func label_of(species: String) -> String:
	return String(SpeciesDefs.row(species).get("name", species))


# --- building the world ----------------------------------------------------------

## Generate the zoo's field into `world` and stock it, and set `gs` to the calendar
## every readiness gate wants. `gs` must be a **detached** GameState — see
## `ui/zoo_screen.gd`'s header for the incident that rule comes from.
static func furnish(world: SimWorld, gs) -> void:
	SimRng.reseed(SEED)
	world.generate(LAYOUT)
	stock(world)

	# Everybody but the farmer goes, so the census starts at zero and every sprite
	# on screen is one somebody asked for. She stays: she is the follow-bot's owner
	# and the grazers' `spook_radius`, and both of those are things to watch.
	for raw in world.actors.keys():
		if String(raw) != SimWorld.ACTOR_PLAYER:
			world.despawn_actor(String(raw))

	if gs == null:
		return
	gs.day = DAY
	gs.takeover_day = 1
	gs.harvest_counts["wheat"] = HARVESTS
	# The appointment books stay empty. Arrivals here are taps, not the day's
	# action clock, so nothing may turn up on its own and surprise a census.
	# (Cleared in place: these are typed `Array[int]` on GameState, and a bare `[]`
	# is an untyped array GDScript refuses to assign into one.)
	gs.crow_schedule.clear()
	gs.ant_schedule.clear()
	gs.visitor_schedules.clear()


## The field's larder, laid (and re-laid) in one pass: a crop patch in mixed
## states so a mouth finds something at every stage, seed in the ground for a
## mole, bare tilled soil for a sprinkler, acorns for a crow. Separate from
## `furnish` because the zoo's residents genuinely eat the place empty — every
## grazer, worm and raid takes crops out of the ground — and an emptied field
## quietly turns the arrival gates off (a scout wants `ANT_MIN_PLANTED`, the
## crow `CROW_MIN_PLANTED`). The panel's Re-sow button calls this to mend that.
static func stock(world: SimWorld) -> void:
	var n := 0
	for ty in range(PATCH.position.y, PATCH.end.y):
		for tx in range(PATCH.position.x, PATCH.end.x):
			n += 1
			if n % 3 == 0:
				world.set_tile_state(tx, ty, "ready", "wheat")
				world.tiles[ty][tx]["growth_stage"] = 3
			else:
				world.set_tile_state(tx, ty, "growing", "wheat")
				world.tiles[ty][tx]["growth_stage"] = 1 + (n % 2)
	for t in SOWN:
		world.set_tile_state(t.x, t.y, "seeded", "wheat")
	for t in TILLED:
		world.set_tile_state(t.x, t.y, "tilled")
	for t in ACORNS:
		world.set_object(t.x, t.y, "acorn")


## Why a tap on this species' button produced nobody, in words — the live-world
## half of its arrival gate, which the zoo's calendar cannot pre-satisfy the way
## it does the day floors (the residents eat the crops the gates count). "" when
## no gate this file knows about is the reason; the caller supplies the generic
## "its real arrival said no" for that case.
static func decline_reason(world: SimWorld, species: String) -> String:
	var planted := world.count_planted()
	if species == SpeciesDefs.ANT_SCOUT and planted < SimWorld.ANT_MIN_PLANTED:
		return "a raid wants %d+ crops in the ground (%d now) — Re-sow" \
			% [SimWorld.ANT_MIN_PLANTED, planted]
	if species == SpeciesDefs.CROW and planted < SimWorld.CROW_MIN_PLANTED:
		return "the crow wants %d+ crops in the ground (%d now) — Re-sow" \
			% [SimWorld.CROW_MIN_PLANTED, planted]
	return ""


## Everything the zoo added, gone. The farmer stays, because she is the field
## rather than an exhibit. Returns how many actors were removed.
static func clear(world: SimWorld) -> int:
	var gone := 0
	for raw in world.actors.keys():
		if String(raw) == SimWorld.ACTOR_PLAYER:
			continue
		world.despawn_actor(String(raw))
		gone += 1
	return gone


## `{species: count}` for everything in the world, in roster order, skipping the
## species nobody has spawned. The panel's live readout.
static func census(world: SimWorld) -> Dictionary:
	var out: Dictionary = {}
	for species in roster():
		var n := world.actors_of_species(species).size()
		if n > 0:
			out[species] = n
	return out


# --- getting an animal in ----------------------------------------------------------
#
# **Each species enters the way it really enters.** The alternative — one
# `spawn_actor` with a hand-written `extra` per species — would be a second copy of
# every brain's initial state, in a debug file, drifting quietly from the real one
# until the zoo showed animals that behave like nothing in the game.
#
# The one thing the real entry points will not do is spawn a *second* of anything:
# `CrowBrain.send` refuses while a crow is registered, `GrazerBrain.arrive` while
# that species is, `AntScoutBrain.send` while any ant is. That is correct for a
# farm — a mob is a design nobody asked for — and wrong for a zoo, where "one more"
# is the whole interaction.
#
# So the ones already here are **parked**: lifted out of the registry, the real
# entry point called into the gap they leave, the newcomer renamed off the
# canonical id if it landed on a parked one, and the parked entries put back.
# Everybody is then rescheduled through the sim's own `schedule_all_brains()`,
# which is the public "the registry moved, think again" hook the day turn already
# uses. It touches `world.actors` and nothing else, and it is confined to this
# function: no brain, no gateway and no species row knows the zoo exists.
static func spawn(world: SimWorld, gs, species: String, nth: int = 0) -> Array[String]:
	var parked: Dictionary = {}
	for blocked in _blockers(species):
		for raw in world.actors_of_species(blocked):
			var id := String(raw)
			parked[id] = world.actors[id]
			world.actors.erase(id)

	var born := _invite(world, gs, species, nth)

	var out: Array[String] = []
	for id in born:
		if id == "" or not world.has_actor(id):
			continue
		var final_id := id
		if parked.has(id):
			final_id = _free_id(world, parked, id)
			world.actors[final_id] = world.actors[id]
			world.actors.erase(id)
		out.append(final_id)

	for id in parked:
		world.actors[id] = parked[id]
	world.schedule_all_brains()
	return out


# Who has to be out of the way for this species' own entry point to say yes. The
# ants are the only pair — `AntScoutBrain.raid_is_live` counts both castes, because
# one raid at a time is a fact about the raid rather than about the scout.
static func _blockers(species: String) -> Array[String]:
	if species == SpeciesDefs.ANT_SCOUT or species == SpeciesDefs.ANT_FORAGER:
		return [SpeciesDefs.ANT_SCOUT, SpeciesDefs.ANT_FORAGER]
	return [species]


# The real entry point for this species, called once. Returns whatever ids it
# created — usually one, three for an ant column.
static func _invite(world: SimWorld, gs, species: String, nth: int) -> Array[String]:
	var out: Array[String] = []
	match species:
		# The bird's own arrival: readiness gate, target choice, entry edge and
		# exit direction, all of it. `PER_DAY` does not apply because there is no
		# appointment book here — the tap *is* the appointment.
		SpeciesDefs.CROW:
			var bird := CrowBrain.send(world, gs, nth)
			if bird != "":
				out.append(bird)
		# One scout, and the raid unfolds on its own: it searches, finds a crop,
		# walks home laying trail, and `AntForagerBrain.raise_column` puts three
		# foragers on it. Watching that happen is most of why this door exists.
		SpeciesDefs.ANT_SCOUT:
			var scout := AntScoutBrain.send(world, gs, nth)
			if scout != "":
				out.append(scout)
		# A column with no scout in front of it — the other half of the raid, for
		# looking at a forager without waiting for one. It follows whatever trail
		# is on the ground — which may be none, in which case all three disperse
		# (despawn, Q-62's ruling) within seconds of arriving. That is the
		# mechanic seen from its failure side, and it reads on screen as a flash
		# of ants that vanish; whether this button should do more (seed a starter
		# trail, say) is Q-82.
		SpeciesDefs.ANT_FORAGER:
			var nest := AntScoutBrain.nest_tile(world, SimRng.stateless(DAY, 6000 + nth))
			if nest.x >= 0:
				out.append_array(AntForagerBrain.raise_column(world, "", nest, world.clock.tick))
		# **One machine, three settings** (M2.5 WI-9), so repeat taps cycle rather
		# than pile up identical bots: follow, then circle, then shoo.
		SpeciesDefs.BOT:
			var config: String = BotBrain.CONFIGS[nth % BotBrain.CONFIGS.size()]
			BotBrain.deploy(world, SpeciesDefs.BOT, config, _near_farmer(world, nth))
			out.append(SpeciesDefs.BOT)
		_:
			# Everybody in the visitors' table arrives through the `Brain.arrive`
			# hook — edge tile, home, bite count and all — which is one call for
			# five species precisely because the hook was written to be one.
			if SimWorld.visitors().has(species):
				var guest := Brains.of_species(species).arrive(world, gs, species, nth)
				if guest != "":
					out.append(guest)
			else:
				# The three that are simply *placed*: a machine is carried
				# somewhere (a `static` row does not travel), and the hen and the
				# neighbour have no arrival of their own — worldgen puts them down.
				world.spawn_actor(species, species, _placement(world, species, nth))
				out.append(species)
	return out


static func _placement(world: SimWorld, species: String, nth: int) -> Vector2i:
	if species == SpeciesDefs.SPRINKLER:
		# On the crops, so the morning it waters is a morning you can see.
		return SPRINKLER_TILES[nth % SPRINKLER_TILES.size()]
	return _near_farmer(world, nth)


static func _near_farmer(world: SimWorld, nth: int) -> Vector2i:
	var her := world.actor_pos(SimWorld.ACTOR_PLAYER)
	if her.x < 0:
		her = WorldLayout.spawn(world.layout)
	for i in NEAR.size():
		var t: Vector2i = her + NEAR[(nth + i) % NEAR.size()]
		if world.is_walkable(t.x, t.y):
			return t
	return her


# An id nothing holds — neither the live registry nor the entries about to be put
# back into it. `_z2`, `_z3`… so a zoo id is visibly a zoo id in a census.
static func _free_id(world: SimWorld, parked: Dictionary, base: String) -> String:
	var n := 2
	var candidate := "%s_z%d" % [base, n]
	while world.has_actor(candidate) or parked.has(candidate):
		n += 1
		candidate = "%s_z%d" % [base, n]
	return candidate

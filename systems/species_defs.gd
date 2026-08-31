# species_defs.gd — What a kind of actor *is* (M2.5 WI-2; plan §3.4 and §4)
#
# Layer 1 (data), the same shape as `systems/tools.gd` and `crops/crop_defs.gd`:
# rows and lookups, no behaviour and no state. A row answers four questions about
# a species — what it may do, how it moves, how fast, what it can notice — and
# names the brain that decides for it.
#
# **Movement capability is data, not code** (plan §3.4, finding F-6). The crow has
# always flown over fences that a walker paths around, but that fact lived inside
# `entities/crow.gd`'s straight-line `_process`, where nothing else could read it
# and no other species could have it. Here it is one field. The designer confirmed
# the behaviour was always the intent ("birds and flyers not hitting obstacles"),
# so this is not a new rule — it is the existing rule, written down where WI-4's
# movement engine can act on it for everybody.
#
# **The table is append-only.** WI-8's critters are one row each, added at the
# bottom without touching the rows above; that is what makes them parallel work.
# The verification checklist (§8.B) requires every row to carry a movement
# capability, and `movement_of()` deliberately has no default: a row that forgot
# to answer the question must fail the test rather than quietly walk.
#
# **Brain ids bind to `systems/sim/brains/`** (M2.5 WI-3): each string below is
# looked up by `Brains.of_species()` and answers `step(world, actor, tick) -> action`.
# A row is complete when it names one, and a typo fails in the unit suite rather
# than producing a critter that silently never acts.
class_name SpeciesDefs
extends RefCounted

# --- movement modes (plan §3.4) -----------------------------------------------
# WI-4 implements all four; only `ground` and `fly` have inhabitants today.
const GROUND := "ground"   # paths around obstacles on sim truth
const FLY := "fly"         # straight line, ignores obstacles — the crow's row
const BURROW := "burrow"   # moves under the grid, surfaces at targets (WI-8d)
const HOP := "hop"         # ground, but crosses barrier-class tiles (WI-8f)
# A machine does not travel (M2.5 WI-10). This is the honest way to say so rather
# than a `ground` row with `speed: 0`, which would be a claim that it walks very
# slowly: `Movement.passable` refuses every tile in this mode, so a route cannot
# be planned for a sprinkler at all, and `step()` answers that it is already where
# it is going. A machine that is *carried* somewhere is a placement, not a walk.
const STATIC := "static"
const MODES: Array[String] = [GROUND, FLY, BURROW, HOP, STATIC]

# Species ids. Actor *ids* are still species names in phase 1 (there is one hen,
# and she is called "chicken"); WI-3 is where a second one needs "chicken_2".
const PLAYER := "player"
const NEIGHBOUR := "neighbour"
const CHICKEN := "chicken"
const CROW := "crow"
const SPRINKLER := "sprinkler"
# The bestiary's first pair (M2.5 WI-8a/8b, `design/04` §1). Two species because
# they are two *mechanics*: one marks, the other follows.
const ANT_SCOUT := "ant_scout"
const ANT_FORAGER := "ant_forager"
# The tier-1 visitors (M2.5 WI-8c/8f/8g, `design/04` §4 and §5). Two mouths that
# answer to a footstep and one bird that answers to nothing.
const RABBIT := "rabbit"
const KANGAROO := "kangaroo"
const SONGBIRD := "songbird"

# **"world" is not a species.** `{ "actor": "world" }` is the sim acting on its own
# behalf — the day turning, a gate opening because a proof was met — and it holds
# no registry entry, no meter and no position. It appears in replay logs as an
# actor because *something* has to own those actions; it is not a thing in the
# world.

# The pixel size a tile is drawn at, and the divisor in the speed conversion
# below. Presentation's own constant, repeated here because the conversion is
# arithmetic on it and the arithmetic has to be checkable.
const TILE_PX := 16.0

# Speeds are **tiles per tick**, converted from the pixels-per-second the
# presentation nodes move at today (`entities/*.gd`, `player/player.gd`):
#
#     tiles/tick = px_per_second ÷ 16 px per tile ÷ 10 ticks per second
#
# with the 10 being `SimClock.RATE`. `SimClock.tiles_per_tick()` is that division,
# and `test_actor_registry` asserts every row against it from the px/s figure in
# its comment — so raising the tick rate cannot silently leave this table saying
# something it no longer means.
#
# Nothing reads `speed` yet: WI-4's movement engine is what turns it into motion.
# Until then it is a recorded fact about each species, not a dial anyone has
# tuned. [Playtest] once anything moves on it.

# Verbs the player's own taps produce (`systems/action_router.gd` plus the shop
# and the cot). Ground rule 1 measures every future bot against this list: a bot
# gets no verb the player lacks (P-9), so WI-9 spawns with exactly these.
const PLAYER_VERBS: Array[String] = [
	"clear_weed", "clear_log", "clear_rock", "clear_tree",
	"till", "plant", "water", "harvest",
	"collect", "sell", "refill", "buy_seed", "take_tool", "sleep",
]

# Verbs that appear in a row below but not in the player's list, each with its
# reason for not being a capability she lacks (ground rule 1):
#   eat_crop, eat_acorn — she can pull up a crop or pick a thing off the ground
#     by hand; she simply has no reason to eat either.
#   lay_egg — the hen's one contribution. Nothing the player would want.
#   crow_scared — a report, not a capability: the bird tells the sim it was
#     frightened, which is what feeds the Q-12 proof.
#   open_gate — hers too, but issued as `actor: "world"` when a tool proof lands
#     (`player/player.gd`), because the gate opens as a consequence of what she
#     did rather than as a thing she does.
# WI-8's critters reuse these (`eat_crop` for every mouth, `water` for washing a
# trail away); adding to this set is a design decision, not a convenience.
const ENTITY_VERBS: Array[String] = ["eat_crop", "eat_acorn", "lay_egg", "crow_scared", "open_gate"]

static var ROWS: Dictionary = {
	# The farmer. Her brain is the ActionRouter — a person, not a policy — and it
	# is named here so the registry has no special case for her. Her meter is
	# GameState's (it is also the clock, Q-38), which is why the registry stores
	# -1 for her energy and never spends it.
	PLAYER: {
		"name": "Farmer",
		"brain": "player_input",
		"verbs": PLAYER_VERBS,
		# 3 tiles/sec (player.gd MOVE_SPEED = 3 * 16 = 48 px/s).
		"speed": 0.3,
		"movement": { "mode": GROUND, "body_len": 1, "tile_exclusive": false },
		# The radius at which she startles skittish things. Read by the crow
		# today (`entities/crow.gd` looks it up on the player node, in pixels);
		# WI-8c's rabbit is the second consumer, which is what finally kills
		# finding F-7b. 48 px = 3 tiles.
		"senses": { "spook_radius": 3.0 },
		"persistent": true,
	},

	# The departing child (T-13, Q-37/Q-45). Registered only while her cold open
	# is live: she leaves the registry when she opens the gate, because that is
	# the moment she leaves the farm.
	NEIGHBOUR: {
		"name": "Neighbour",
		"brain": "cold_open",  # systems/sim/cold_open.gd — already a pure sim brain (F-1)
		"verbs": ["till", "plant", "water", "open_gate"],
		# 26 px/s (neighbour.gd SPEED) — a shade quicker than the hen, slower
		# than the player, which is what reads as "someone else working".
		"speed": 0.1625,
		"movement": { "mode": GROUND, "body_len": 1, "tile_exclusive": false },
		"senses": {},
		"persistent": true,
	},

	# The toy, not a chore (design/13 §4a). Wanders, and lays an egg on a coin
	# flip at the day turn.
	CHICKEN: {
		"name": "Chicken",
		"brain": "chicken_wander",
		"verbs": ["lay_egg"],
		# 20 px/s (chicken.gd SPEED).
		"speed": 0.125,
		"movement": { "mode": GROUND, "body_len": 1, "tile_exclusive": false },
		"senses": {},
		"persistent": true,
	},

	# The joke, not the threat (Q-10). Flies in, prefers acorns to crops (T-15 /
	# Q-39), leaves when anything frightens it.
	#
	# `persistent: false` is what keeps a visit out of a **save**: the crow is a
	# registered actor for as long as its visit lasts (WI-3 moved its lifecycle
	# into the sim, where "when does a crow exist" is answered by the T-20
	# schedule rather than by a node), but a bird halfway across the sky on the
	# frame the autosave timer fired is not part of a snapshot of a farm. See
	# `SaveGame._capture_actors`.
	CROW: {
		"name": "Crow",
		"brain": "crow_visit",
		"verbs": ["eat_crop", "eat_acorn", "crow_scared"],
		# 60 px/s inbound (crow.gd `flying_in`; it leaves at 80, which is a
		# flourish rather than a species fact and does not survive as data).
		"speed": 0.375,
		# Finding F-6, as one field: this is the flight that ignores fences.
		"movement": { "mode": FLY, "body_len": 1, "tile_exclusive": false },
		# It has no radius of its own — it reacts to other actors' spook_radius
		# and to scarecrows. Recorded as senses because that is what the crow's
		# `_spook_cause()` scan actually is, and WI-3 moves that scan sim-side.
		"senses": { "flees_spook_radius": true, "flees_scarecrow": true },
		"persistent": false,
	},

	# The first machine (design/03, M2.5 WI-10). **"A sprinkler waters; it does
	# nothing the watering can couldn't"** — which is the whole design, and why
	# this row's verb list is one verb the player already owns and the work item
	# added no gateway code whatsoever.
	#
	# It is an actor rather than a placed object because it *decides*: at the day
	# turn its brain says which tiles to water, and those are ordinary Actions
	# through the one gateway (ground rule 1). Which tile it stands on, how far it
	# reaches and what it costs to keep are `design/03` §3–§4's questions; the
	# radius is a `[Playtest]` constant in `sprinkler_brain.gd` and upkeep is
	# deliberately unbuilt (plan §4).
	#
	# **Nothing places one.** Acquisition is Q-15's ruling and the plan leaves it
	# open, so a sprinkler exists only behind `spawn_actor` and the tests; the
	# live game has never contained one, and it has no renderer until WI-6.
	SPRINKLER: {
		"name": "Sprinkler",
		"brain": "sprinkler_day",
		"verbs": ["water"],
		# It has no speed because it has nowhere to be. See STATIC above: the mode
		# is what makes that a fact the movement engine enforces rather than a
		# number a future edit could nudge off zero.
		"speed": 0.0,
		"movement": { "mode": STATIC, "body_len": 1, "tile_exclusive": false },
		"senses": {},
		"persistent": true,
	},

	# --- the bestiary, tier 1 (M2.5 WI-8) -------------------------------------
	#
	# **The ant pair is the scent layer's first consumer** (`design/04` §1, P-10):
	# scouts mark, foragers follow, success reinforces, decay erases. Neither row
	# adds a verb — the scout has *none at all* (it walks and it deposits, and a
	# deposit is a consequence of walking rather than a thing anybody does), and
	# the forager's one verb is `eat_crop`, the mouth every critter in the game
	# already shares with the crow.
	#
	# Their **counterplay is the player's existing hands**: a clear-class tap on
	# the tile an ant is standing on stomps it (`stompable` below), and the
	# `water` verb washes the trail off a tile (`SimWorld._apply` → `Scent.wash`,
	# wired by WI-7). No new verb, no new UI, on either side. P-10 says difficulty
	# is the decay constant rather than the spawn count, so the dial that makes
	# ants hard is `Scent.CHANNELS[TRAIL].half_life`, not this table.
	#
	# **Nothing spawns one.** `SimWorld.ANT_RAIDS_PER_DAY` is 0: the raid
	# lifecycle is built, scheduled and tested, and the live game has never
	# contained an ant. *When* they debut is designer content sequencing (the
	# Q-56 pattern), not this work item's to decide — the same standing the
	# sprinkler ships with.

	# The one that goes looking. Wanders, finds a crop, and walks home laying
	# trail — which is the whole of it, and the reason a raid is answerable:
	# stomp the scout and the column that would have followed never exists.
	ANT_SCOUT: {
		"name": "Ant Scout",
		"brain": "ant_scout",
		# **No verbs.** It changes the world only by moving and by depositing, and
		# a deposit is not an Action (see `ant_scout_brain.gd`'s header for why
		# that is the same rule the hen's walk follows, not an exception to it).
		"verbs": [],
		# 10 px/s — half the hen's pace, and 1.6 s per tile. Small and slow is the
		# readability requirement (Q-17: a forming raid must be *seen*); a fast ant
		# is a raid that is over before a child has looked up. [Playtest].
		"speed": 0.0625,
		"movement": { "mode": GROUND, "body_len": 1, "tile_exclusive": false },
		# How far it notices food. Small on purpose: a scout with a big nose walks
		# straight lines and stops looking like a search. [Playtest].
		"senses": { "crop_sense": 3.0 },
		# A raid is minutes of ground-level event with a *saved* trail behind it
		# (`world.scent`), so unlike the crow's flight it is part of a snapshot of
		# a farm — see the note in `save_game.gd:_capture_actors`.
		"persistent": true,
		# The counterplay, as data: a clear-class tap on this actor's tile answers
		# it. See `SimWorld.stompable_at` and the `clear_*` branch of the gateway.
		"stompable": true,
	},

	# The one that follows. Reads the gradient, takes exactly one crop, carries it
	# home reinforcing the trail, and is gone. One crop each is what bounds a
	# raid's cost (see `SimWorld.ANT_COLUMN_SIZE` and the daily-loss test).
	ANT_FORAGER: {
		"name": "Ant Forager",
		"brain": "ant_forager",
		# `eat_crop` — the crow's verb, and no new one. She can pull a crop up by
		# hand; she simply has no reason to eat it (see ENTITY_VERBS above).
		"verbs": ["eat_crop"],
		# 8 px/s: 2 s per tile, a shade slower than the scout, because a column is
		# a procession and a laden ant is a slow ant. [Playtest].
		"speed": 0.05,
		"movement": { "mode": GROUND, "body_len": 1, "tile_exclusive": false },
		"senses": {},
		"persistent": true,
		"stompable": true,
	},

	# --- the three that came next (M2.5 WI-8c/8f/8g) --------------------------
	#
	# **Two of these rows are the same animal.** The rabbit and the kangaroo name
	# the *same brain* (`graze`) and differ by four numbers, one of which — the
	# movement mode — is the entire kangaroo. That is plan §4's "exists to prove
	# capability data beats code" stated as data rather than as a claim: nothing in
	# `grazer_brain.gd` says `if kangaroo`, and nothing needs to, because a fence is
	# a question the movement engine answers out of this table (WI-4).
	#
	# **They are the first consumers of `spook_radius`, which kills finding F-7b.**
	# The player's row has carried the sense since WI-2 and nothing has been able to
	# read it: the crow's version measured pixels off a node, and its "other actors
	# with a spook_radius" scan was dead code deleted in WI-3 because the player's
	# position was not sim truth. It is sim truth now (WI-6), so a grazer asks
	# `SimWorld.spook_source_near()` and gets a real answer from the registry. The
	# radius lives on the *frightener's* row, not the frightened one's — she is what
	# is 3 tiles scary, and `flees_spook_radius` is what notices, exactly as the
	# crow's row says it.
	#
	# **Nothing spawns any of them.** `SimWorld.RABBIT_VISITS_PER_DAY`,
	# `KANGAROO_VISITS_PER_DAY` and `SONGBIRDS_PER_DAY` are all 0, so no schedule in
	# any real game holds an appointment. The debut is content sequencing (the Q-56
	# pattern), which is the standing the sprinkler and the ants already ship with.

	# The garden thief with an ear on the door. Wanders, notices a crop within a
	# few tiles, walks onto it and takes a bite; **bolts the moment the player is
	# near, and comes back to grazing when she has gone**. That last clause is the
	# whole design: the counterplay is *walking over*, which is the only verb a
	# two-year-old has, and no tap is required at all.
	RABBIT: {
		"name": "Rabbit",
		"brain": "graze",
		# `eat_crop` — the crow's mouth, the ants' mouth, reused a third time. No
		# new verb (P-9 / ground rule 1).
		"verbs": ["eat_crop"],
		# 30 px/s: quicker than the hen, slower than the farmer, so she can catch
		# up to it if she means to and it looks unhurried if she does not.
		# [Playtest].
		"speed": 0.1875,
		"movement": { "mode": GROUND, "body_len": 1, "tile_exclusive": false },
		# It notices food further off than an ant does — it is bigger and it is
		# looking for a meal rather than for a route. [Playtest].
		"senses": { "crop_sense": 5.0, "flees_spook_radius": true },
		# A visit that lasts minutes and stands on the ground is part of a snapshot
		# of a farm — the ants' argument, not the crow's (see `_capture_actors`).
		"persistent": true,
		# **Deliberately not stompable.** The stomp answers a scout, whose whole
		# threat is that it gets home; a rabbit's answer is her footsteps. Adding a
		# boot here would make the flee sense decorative.
	},

	# The same animal, over the fence. Its brain is the rabbit's, its senses are
	# the rabbit's, and the one field that differs is `mode: HOP` — which the
	# movement engine reads as "ground pathing, plus exactly the barrier class"
	# (fence, hedge, closed gate; `Movement.is_barrier`). A crop a rabbit can smell
	# and never reach is a crop this one is standing on.
	#
	# **Q-57 is filed and unruled** (`DESIGNER_QUEUE.md`): the barrier class
	# includes closed gates, so a hopper can be in a parcel the player has not
	# earned. Nothing is blocked — `KANGAROO_VISITS_PER_DAY` is 0, so no kangaroo
	# has ever been in anybody's quarry.
	KANGAROO: {
		"name": "Kangaroo",
		"brain": "graze",  # the rabbit's, unchanged — that is the point of the row
		"verbs": ["eat_crop"],
		# 45 px/s. It covers ground in bounds, which is what makes a fence look
		# incidental rather than absent. [Playtest].
		"speed": 0.28125,
		"movement": { "mode": HOP, "body_len": 1, "tile_exclusive": false },
		"senses": { "crop_sense": 5.0, "flees_spook_radius": true },
		"persistent": true,
	},

	# **The one that does nothing at all** (`design/04` §5: harmless fauna, "charm,
	# eggs, ambient life for the kid layer"). It drifts across the farm, perches a
	# while, drifts again, and goes. It has **no verbs**, and its brain has no
	# branch that could return an Action — which is the claim plan §4 asks this
	# species to prove: the system carries a pure-charm actor with no special case
	# anywhere. It is a species row, a brain and a sprite, like everybody else, and
	# the replay log never mentions it because there is nothing to mention.
	#
	# (`design/04` §5 also notes the other reason to have one: a phase-4 bot needs
	# negative examples — things not to chase — and the hen cannot be the only one.)
	SONGBIRD: {
		"name": "Songbird",
		"brain": "songbird_ambient",
		"verbs": [],
		# 35 px/s: flitting rather than the crow's purposeful 60. [Playtest].
		"speed": 0.21875,
		# `fly`, so it goes over everything and perches wherever it likes — a fence
		# post is a fine place for a small bird, and `Movement.can_stop` says yes
		# for the same reason it says no to a kangaroo.
		"movement": { "mode": FLY, "body_len": 1, "tile_exclusive": false },
		# It notices nothing. Not an oversight: a bird that fled the player would be
		# a second mechanic on an actor whose mechanic is that it has none.
		"senses": {},
		# Unlike the crow, it is *here* rather than raiding: it belongs to the farm
		# the way the hen does, so a snapshot of the farm contains it. It is also
		# what makes the zero-verb claim checkable — its whole visit is recomputed
		# and compared by WI-5's net, with no Actions in it to compare.
		"persistent": true,
	},
}


static func has(species: String) -> bool:
	return ROWS.has(species)


static func row(species: String) -> Dictionary:
	return ROWS.get(species, {})


static func ids() -> Array:
	return ROWS.keys()


# {} for an unknown species — and, deliberately, for a row that shipped without
# one. The checklist's "every species def carries a movement capability" is a
# test over this returning non-empty, so silence is not an option (§8.B).
static func movement_of(species: String) -> Dictionary:
	return row(species).get("movement", {})


static func mode_of(species: String) -> String:
	return String(movement_of(species).get("mode", ""))


static func speed_of(species: String) -> float:
	return float(row(species).get("speed", 0.0))


static func verbs_of(species: String) -> Array:
	return row(species).get("verbs", [])


static func senses_of(species: String) -> Dictionary:
	return row(species).get("senses", {})


static func brain_of(species: String) -> String:
	return String(row(species).get("brain", ""))


# Does this species have this verb at all? The sim does not gate on it yet —
# `apply_action` validates the world, not the actor's job description (D-8) — so
# this is a data question the tests and WI-3's brains ask, not a new guard in the
# gateway.
static func may(species: String, verb: String) -> bool:
	return verb in verbs_of(species)


# Registry v1 holds persistent actors; a visit (the crow) is still node-owned
# this milestone. See SimWorld's registry block.
static func is_persistent(species: String) -> bool:
	return bool(row(species).get("persistent", false))


# Does a clear-class tap on this thing's tile answer it? (M2.5 WI-8a, P-10's
# "stomp scouts" counterplay.) Data rather than a list in the gateway, so the
# critter that wants stomping says so in its own row — and so the default is
# **no**: the hen must never be answerable by tapping her.
static func is_stompable(species: String) -> bool:
	return bool(row(species).get("stompable", false))

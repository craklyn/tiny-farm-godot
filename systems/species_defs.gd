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

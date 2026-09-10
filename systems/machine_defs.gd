# machine_defs.gd — What the shop sells that is not a seed (static data, layer 1)
#
# **The placeholder acquisition rule** (designer, 2026-09-03): *"As a placeholder
# to a richer experience, for now make everything we introduce to the farm a
# purchasable item from the shop."* Until a richer story exists — blueprints,
# crafting, a neighbour's gift, a quest reward — anything the player can own is
# bought here for gold. That ruling supersedes the holds that had kept both
# machines out of her hands: Q-15's sprinkler acquisition and Q-56's bot debut
# (see `docs/DESIGNER_QUEUE.md`).
#
# **Why this file exists rather than another row in `CropDefs`.** The scarecrow is
# defined as a crop with `is_object: true`, because the shop only knew how to sell
# seeds. That bend worked once and would have to be repeated for every machine,
# tower and structure that follows — a sprinkler is not a crop, has no growth
# stages, no sell price and is not planted into soil. So the shop now reads two
# catalogues: `CropDefs.ORDER` for things that go in the ground, and this for
# things that get **placed** and start acting on their own. Adding a purchasable
# machine is one row here plus a species row; nothing else has to learn about it.
#
# Layer 1 (`docs/ARCHITECTURE.md`): plain definitions, no logic. The config names
# below are the strings `systems/sim/brains/bot_brain.gd` matches on, written out
# rather than imported so this file stays free of layer-2 dependencies — with a
# unit test (`test_machine_defs`) pinning the two lists together so they cannot
# drift apart silently.
class_name MachineDefs
extends RefCounted

# The catalogue. `species` is the row in `systems/species_defs.gd` that a placed
# one becomes; `configs` is what the player may choose between once it is down
# (empty when the machine has nothing to decide).
#
# **A row may name no species at all** (2026-09-06, the stall). What the shop
# sells is "a thing that gets placed", and the two halves of that turn out to be
# separable: a machine becomes an *actor* and starts deciding, a structure becomes
# an *object* on the grid and never thinks. `species: ""` is what says which — and
# `place` reads it, so a structure costs the gateway one branch rather than a
# second catalogue.
static var TYPES: Dictionary = {
	# The first automation the player meets — `design/03`'s "watch your old job
	# happen without you". Priced above every seed and below the robot: a day of
	# good tomatoes buys one, which makes it the natural first purchase after the
	# scarecrow rather than a project.  [Playtest]
	# --- fencing (Q-92, ruled 2026-09-07) --------------------------------------
	#
	# In the crate with the machines because that is what the crate is: things she
	# has bought and not yet put down. `GameState.machines` has said so since it
	# was written — "a tower, a fence or a hopper joins this dictionary with no
	# new field" — so this is that sentence coming true rather than a new home.
	#
	# `terrain` is what separates it from everything else here: it lays a kind of
	# ground rather than putting an actor on the farm, so the gateway sends it to
	# `build` and refuses it to `place`. Sold in tens because a fence is a run of
	# posts and buying twenty squares one card at a time is not a decision, it is
	# an errand.
	"fence": {
		"name": "Fencing ×10",
		"price": 40,
		"species": "",
		"terrain": WorldLayout.FENCE_BUILT,
		"bundle": 10,
		"configs": [],
		"default_config": "",
		"unlock_requirement": null,
		# The fence cell the world's own fences are drawn from: the designer's
		# ruling is that the picture is already right, because the hedge is what
		# says "not yours yet" and the fence already says "yours".
		"icon": { "sheet": "res://assets/sprites/generated/fence.png",
			"region": Rect2(0, 0, 16, 16) },
	},
	"sprinkler": {
		"name": "Sprinkler",
		"price": 120,
		"species": SpeciesDefs.SPRINKLER,
		"configs": [],
		"default_config": "",
		"unlock_requirement": null,
		# Its own world sprite, so the shop card, the HUD pill and the thing that
		# appears on the grass are visibly one object. sprinkler.png cell 0 is
		# the idle frame `entities/sprinkler.gd` draws.
		"icon": { "sheet": "res://assets/sprites/generated/sprinkler.png",
			"region": Rect2(0, 0, 16, 16) },
	},
	# --- the stall (CEO, 2026-09-06) -------------------------------------------
	#
	# *"A robot stall holds two robots. The player buys a robot, leaves it in the
	# stall, teaches it, and after teaching it works productively growing crops."*
	# So the stall is the robot's **address**: a bot parked in one comes home to it
	# at the end of its round and is sent out again the next morning without being
	# asked, which is the difference between owning a machine and employing one.
	#
	# **It is a shed, not a machine**, and that is why it sits here above the bots
	# rather than below them: it has no species, becomes no actor, decides nothing
	# and thinks never — `place` writes two objects onto the grid and stops. Priced
	# under the sprinkler (80g) because it is the cheapest thing on this list to
	# build and because it is worth nothing on its own: an empty stall does not
	# water a single tile, so what she is really buying is the day her robot stops
	# needing to be told.
	#
	# **Deliberately weak first version** (P-13). Two bays, fixed, side by side; it
	# cannot be picked back up, moved, upgraded or extended. Every one of those is a
	# thing a later tier can be, and a first version that already did them would
	# leave the tier above it with nothing to be.
	"stall": {
		"name": "Robot Stall",
		"price": 80,
		# No species: nothing is spawned, so there is nothing for a species row to
		# describe. See `SimWorld._apply`'s `place`.
		"species": "",
		"program": "",
		"configs": [],
		"default_config": "",
		"unlock_requirement": null,
		# The whole 32x32 sheet, which is also exactly what is drawn on the farm:
		# its bottom half is the two open bays standing on the two tiles, its top
		# half the shed rising behind them. One picture in the shop card, the HUD
		# pill and the yard.
		"icon": { "sheet": "res://assets/sprites/generated/robot_stall.png",
			"region": Rect2(0, 0, 32, 32) },
	},
	# --- the robot, in two marks (designer, 2026-09-03) ------------------------
	#
	# *"Mark-1 should take exact orders from you… It is intentionally low
	# capabilities."* The ladder is the design: the first machine you can own that
	# **walks** does nothing you did not spell out, and the machine that decides
	# for itself is the rung above it. Both are the same species and the same
	# brain (`design/06`: a product line is one machine with a setting); what the
	# mark buys is which settings the machine will answer to.
	#
	# `program` is the row's own word for what its menu is about: a mark-1 is
	# taught and sent, a mark-2 is set to one of three standing behaviours.
	"bot_mk1": {
		"name": "Robot Mk I",
		"price": 150,
		"species": SpeciesDefs.BOT,
		"program": "orders",
		# No behaviour to choose between: what it does is the list of tiles she
		# taught it. The menu offers *teach* and *send out* instead.
		"configs": [],
		"default_config": "orders",
		"unlock_requirement": null,
		# bot.png cell (0,0): the down-facing standing idle, which is the frame
		# `entities/bot.gd` shows a bot that is not walking.
		"icon": { "sheet": "res://assets/sprites/generated/bot.png",
			"region": Rect2(0, 0, 48, 48) },
	},
	# The scripted line (M2.5 WI-9, `design/06`) — the machine that decides where
	# to be. Priced well above the mark-1: autonomy is the thing you save up for,
	# and the gap is what makes the cheap one worth owning first. [Playtest]
	"bot_mk2": {
		"name": "Robot Mk II",
		"price": 400,
		"species": SpeciesDefs.BOT,
		"program": "configs",
		# Order matters: it is the order the machine menu lists them in, and the
		# first entry is what a freshly placed one starts as. Shoo leads because
		# it is the config that does a job on its own — Q-56 named it the debut
		# candidate for exactly that reason.
		# "idle" is last because the three jobs are the point of the machine, and it
		# sits beside "Pick up" where the two ways to stop it belong together.
		"configs": ["shoo", "follow", "circle", "idle"],
		# ...but it is what a freshly placed one *is*, so putting a machine down
		# is never the same thing as starting it (from play, 2026-09-07).
		"default_config": "idle",
		"unlock_requirement": null,
		"icon": { "sheet": "res://assets/sprites/generated/bot_mk2.png",
			"region": Rect2(0, 0, 48, 48) },
	},
	# The learning line (v0.2.1, `design/06` "The ladder's third rung"; P-14). The
	# mark-2's three behaviours were written by hand; this one's is written by its
	# own days — it wanders, waters, and is nudged every night towards whatever
	# earned. Priced at twice the mark-2 because that is the whole arc of the
	# game in one shelf: the more of the farm a machine takes off her hands, the
	# longer she saves for it. [Playtest]
	"bot_mk3": {
		"name": "Robot Mk III",
		"price": 800,
		"species": SpeciesDefs.BOT,
		# Neither a taught list nor a dial: what this machine does is a policy it
		# is still working out. The menu shows what it has learned, not what to
		# set it to (Q-97).
		"program": "policy",
		# **No configs, on purpose.** `configure` rebuilds a bot's `extra` from
		# scratch, so a settable mark-3 would be a machine whose weeks of learning
		# she could wipe by tapping a menu row. An empty list is what makes the
		# gateway refuse the dial outright (`SimWorld`'s `configure`).
		"configs": [],
		"default_config": "learn",
		"unlock_requirement": null,
		# **The mark-2's sheet, borrowed.** WI-6 of the v0.2.1 plan generates a
		# third one and replaces this line; until it does, a Mark III is drawn as
		# a mark-2 — honest about the family, wrong about the machine.
		"icon": { "sheet": "res://assets/sprites/generated/bot_mk2.png",
			"region": Rect2(0, 0, 48, 48) },
	},
}

# Display order — and, because the shop iterates it, the list of what is actually
# for sale. `CropDefs.ORDER`'s role, for machines.
# **Adding a row to `TYPES` is not adding a thing for sale.** The shop walks this
# list, not the table, so a row missing from here exists to every rule in the game
# and cannot be bought by anybody — which is how fencing shipped on 2026-09-07
# with a verb, a state, a refund and 23 passing assertions, and no way to get any.
# Fencing leads: it is the cheapest thing on the shelf and the only one that is
# not a machine.
static var ORDER: Array[String] = ["fence", "sprinkler", "stall", "bot_mk1", "bot_mk2",
		"bot_mk3"]


static func has(key: String) -> bool:
	return TYPES.has(key)


static func price_of(key: String) -> int:
	return int(TYPES.get(key, {}).get("price", 0))


static func species_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("species", ""))


static func name_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("name", key))


# The ground a crate item lays down, or "" for the ones that put an actor on the
# farm instead. This is what tells `build` from `place` — see the gateway.
static func terrain_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("terrain", ""))


static func configs_of(key: String) -> Array:
	return TYPES.get(key, {}).get("configs", [])


static func default_config(key: String) -> String:
	return String(TYPES.get(key, {}).get("default_config", ""))


# The machine key a placed actor came from, or "".
#
# **A fallback, not the answer.** Two rows can share a species — the two robot
# marks do — so a placed machine records the row it was bought from in
# `extra.model`, and `SimWorld.machine_key_of` reads that first. This is what
# answers for a machine with no `model` on it: a sprinkler from a save written
# before the marks existed, or a bot a test deployed directly.
static func key_for_species(species: String) -> String:
	if species == "":
		# A structure names no species (the stall), so "no species" is not a
		# question this can answer — without this guard the first speciesless row
		# in ORDER would answer for every actor that has lost its own.
		return ""
	for key in ORDER:
		if species_of(key) == species:
			return key
	return ""


# Does placing this row put an **actor** in the world, or an object on the grid?
# The stall is the second kind (2026-09-06): a shed decides nothing, so it needs
# no species, no brain and no registry entry. One question, asked by `place` and
# by the tests that hold this catalogue to account.
static func spawns_actor(key: String) -> bool:
	return species_of(key) != ""


# What this row's menu is about: "orders" (taught a list of tiles, then sent out)
# or "configs" (set to one of several standing behaviours). "" for a machine with
# no menu at all, which is the sprinkler.
static func program_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("program", ""))


# Nothing is gated today; the hook is here because the seeds have one
# (`CropDefs.is_seed_unlocked`) and a tower that wants a proof behind it should
# not have to invent the mechanism.
static func is_unlocked(key: String, harvest_counts: Dictionary) -> bool:
	var def: Dictionary = TYPES.get(key, {})
	if def.is_empty():
		return false
	var req = def.get("unlock_requirement")
	if req == null:
		return true
	return harvest_counts.get(req.crop, 0) >= req.count


# The shop card's and the HUD pill's picture, built from the row above. Returns
# null for a key with no icon, which every caller already has to handle (a seed
# without an `icon_col` shows no picture either).
static func icon_of(key: String) -> AtlasTexture:
	var icon: Dictionary = TYPES.get(key, {}).get("icon", {})
	if icon.is_empty():
		return null
	var tex: Texture2D = load(String(icon.sheet))
	if tex == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = icon.region
	return atlas

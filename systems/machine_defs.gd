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
static var TYPES: Dictionary = {
	# The first automation the player meets — `design/03`'s "watch your old job
	# happen without you". Priced above every seed and below the robot: a day of
	# good tomatoes buys one, which makes it the natural first purchase after the
	# scarecrow rather than a project.  [Playtest]
	"sprinkler": {
		"name": "Sprinkler",
		"price": 120,
		"species": SpeciesDefs.SPRINKLER,
		"configs": [],
		"default_config": "",
		"unlock_requirement": null,
		# Its own world sprite, so the shop card, the HUD pill and the thing that
		# appears on the grass are visibly one object. objects.png row 1 col 5 is
		# the idle frame `entities/sprinkler.gd` draws.
		"icon": { "sheet": "res://assets/sprites/generated/objects.png",
			"region": Rect2(5 * 16, 16, 16, 16) },
	},
	# The scripted line (M2.5 WI-9, `design/06`). One machine with a setting, so
	# it is one shop item and the three configs are a decision she makes *after*
	# placing it — which is also why placing one opens its menu straight away.
	#
	# Roughly twice the sprinkler: it is the more capable machine and should feel
	# like the farm's second big purchase, not an impulse.  [Playtest]
	"bot": {
		"name": "Robot",
		"price": 250,
		"species": SpeciesDefs.BOT,
		# Order matters: it is the order the machine menu lists them in, and the
		# first entry is what a freshly placed one starts as. Shoo leads because
		# it is the config that does a job on its own — Q-56 named it the debut
		# candidate for exactly that reason.
		"configs": ["shoo", "follow", "circle"],
		"default_config": "shoo",
		"unlock_requirement": null,
		# bot.png cell (0,0): the down-facing standing idle, which is the frame
		# `entities/bot.gd` shows a bot that is not walking.
		"icon": { "sheet": "res://assets/sprites/generated/bot.png",
			"region": Rect2(0, 0, 48, 48) },
	},
}

# Display order — and, because the shop iterates it, the list of what is actually
# for sale. `CropDefs.ORDER`'s role, for machines.
static var ORDER: Array[String] = ["sprinkler", "bot"]


static func has(key: String) -> bool:
	return TYPES.has(key)


static func price_of(key: String) -> int:
	return int(TYPES.get(key, {}).get("price", 0))


static func species_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("species", ""))


static func name_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("name", key))


static func configs_of(key: String) -> Array:
	return TYPES.get(key, {}).get("configs", [])


static func default_config(key: String) -> String:
	return String(TYPES.get(key, {}).get("default_config", ""))


# The machine key a placed actor came from, or "" — the inverse of `species_of`,
# which is what lets `collect` put the right thing back in the crate and the
# machine menu know which configs to offer.
static func key_for_species(species: String) -> String:
	for key in ORDER:
		if species_of(key) == species:
			return key
	return ""


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
# without a `sprite_row` shows no picture either).
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

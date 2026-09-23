# crop_defs.gd — Crop type definitions and growth logic (static utility)
# Mirrors the Love2D crops.lua exactly
class_name CropDefs
extends RefCounted

# Crop definitions
static var TYPES: Dictionary = {
	"wheat": {
		"name": "Wheat",
		"days_to_grow": 3,
		"sell_price": 15,
		"seed_price": 5,
		"stages": 4,
		"unlock_requirement": null,
		"icon_col": 0,
		# **The crop she already has** (S-18/S-19/S-20, 2026-09-23). A harvested plant is
		# the seed for the next one, so the farm she is given feeds itself and
		# needs no money to keep running — which is what a starter crop means and
		# why this one is not on the shop's shelf. `seed_price` stays, because the
		# `buy_seed` verb and every replay that recorded one still have to parse.
		"starter": true,
	},
	"tomato": {
		"name": "Tomato",
		"days_to_grow": 5,
		"sell_price": 30,
		"seed_price": 10,
		"stages": 4,
		"unlock_requirement": { "crop": "wheat", "count": 1 },
		"icon_col": 1,
	},
	# Q-55, ruled 2026-08-31: **the pea ships now as an ordinary crop** (M2.5
	# WI-10); the shooters, towers, storage and delivery economy it is eventually
	# the raw material for is designed at M3 alongside `design/03`/`design/05`. So
	# there is nothing special about this row, and that is the point of it: the
	# ammo economy finds its crop already grown, tested and balanced instead of
	# arriving with one.
	#
	# Balance is deliberately conservative and `[Playtest]`: three days like wheat
	# (a crop the ammo economy will want a lot of should not be a five-day
	# commitment) and priced between wheat and tomato, so growing peas for money is
	# a fine choice and never the obvious one. Nothing is tuned against a peashooter
	# that does not exist yet.
	#
	# **The shop does not sell pea seeds** — it is absent from ORDER below, which
	# is what every shop, HUD and seed-selection path iterates. When a player first
	# meets the pea, and what teaches her, is content sequencing and the designer's
	# (the Q-56 pattern), not this work item's.
	"pea": {
		"name": "Pea",
		"days_to_grow": 3,      # [Playtest]
		"sell_price": 20,       # [Playtest]
		"seed_price": 8,        # [Playtest]
		"stages": 4,
		"unlock_requirement": { "crop": "wheat", "count": 1 },
		# pea.png — four growth stages in the same order and cell shape as wheat
		# and tomato (WI-11 drew it; the 2026-09-06 split gave it its own sheet).
		# Bound to the renderer in `world/farm.gd`'s crop_regions, exactly as
		# those two are.
		#
		# **Trap for whoever puts the pea in the shop:** column 3 of
		# shop_icons.png is the **coin** (T-12), so a pea in the shop today would
		# be priced with a picture of a coin. Debuting it means drawing a pea
		# packet into the icon row and pointing this number at it.
		"icon_col": 3,
	},
	"egg": {
		"name": "Egg",
		"sell_price": 10,
	},
	"scarecrow": {
		"name": "Scarecrow",
		"seed_price": 50,
		"is_object": true,
		"stages": 1,
		"unlock_requirement": null,
		"icon_col": 2, # Shop icon column in shop_icons.png (see menus.gd)
	},
}

# Display order for the HUD and seed picker, and the shop's candidate rows;
# `is_on_shelf` hides the starter wheat. The **pea is deliberately absent**
# (Q-55/M2.5 WI-10): the crop ships, the shop does not sell it yet, and adding it
# here is the one-line change that debuts it when the designer says so.
static var ORDER: Array[String] = ["wheat", "tomato", "scarecrow"]


static func is_ready(crop_type: String, growth_stage: int) -> bool:
	var def: Dictionary = TYPES.get(crop_type, {})
	if def.is_empty():
		return false
	return growth_stage >= def.days_to_grow


static func get_visual_stage(crop_type: String, growth_stage: int) -> int:
	var def: Dictionary = TYPES.get(crop_type, {})
	if def.is_empty():
		return 0
	if growth_stage <= 0:
		return 0  # seed
	if is_ready(crop_type, growth_stage):
		return 3  # ready
	var progress: float = float(growth_stage) / float(def.days_to_grow)
	if progress < 0.5:
		return 1  # sprout
	return 2  # mid-growth


# Is this a thing the `plant` verb can put in the ground? An egg is not, and
# since the inventory also holds eggs and scarecrows (S-18/S-19/S-20), everything that
# asks "has she anything to sow" has to ask it here rather than counting items.
static func is_plantable(seed_type: String) -> bool:
	var def: Dictionary = TYPES.get(seed_type, {})
	return def.has("days_to_grow") and not bool(def.get("is_object", false))


# Is this a thing the shipping bin pays for? A scarecrow is not; it stays in
# noncrop inventory when a deposit takes carried crops and eggs.
static func is_sellable(crop_type: String) -> bool:
	return TYPES.get(crop_type, {}).has("sell_price")


# A crop the farm is given rather than bought (S-18/S-19/S-20). Harvest returns its seed,
# so the shop does not sell one — see `is_on_shelf`.
static func is_starter(seed_type: String) -> bool:
	return bool(TYPES.get(seed_type, {}).get("starter", false))


# Does the seed shelf stock this? **The one definition**, read by the shop that
# draws the cards and by the gateway that takes the money, so a bot can never buy
# a packet the player cannot see on the shelf (S-3, ground rule 1).
static func is_on_shelf(seed_type: String) -> bool:
	return ORDER.has(seed_type) and TYPES.get(seed_type, {}).has("seed_price") \
		and not is_starter(seed_type)


static func is_seed_unlocked(seed_type: String, harvest_counts: Dictionary) -> bool:
	var def: Dictionary = TYPES.get(seed_type, {})
	if def.is_empty():
		return false
	var req = def.get("unlock_requirement")
	if req == null:
		return true
	return harvest_counts.get(req.crop, 0) >= req.count

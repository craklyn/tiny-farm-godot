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
	# --- the chicken coop (2026-09-11) -----------------------------------------
	#
	# **The first thing on the shelf that does nothing.** Every other row here buys
	# labour: a sprinkler retires the watering can, a stall retires the sending-out,
	# a robot retires the round. This buys a place for the hen to be, and that is
	# the whole of it — no species, no brain, no verb, no yield. On a wet morning
	# she walks into it and sits the rain out; on a dry one it is a hut with a
	# chicken near it.
	#
	# **Priced at 25** — under the fencing, which makes it the cheapest thing in
	# the game and the first purchase a player can afford on day one. That is
	# deliberate: the shelf's other lesson is "save up for the machine that works
	# for you", and a cheap ornament at the bottom of it is what makes the prices
	# above read as a ladder rather than as a wall. It also means the first thing a
	# new player buys can be one they bought because they liked it.  [Playtest]
	#
	# **Two by two**, which is new — the stall is two tiles side by side and the
	# bench is one. The `footprint` field below is what says so, and it is why the
	# gateway now puts any structure down by walking a block of cells rather than
	# by naming the stall's second bay (see `SimWorld`'s `place`).
	#
	# **Deliberately weak first version** (P-13): it cannot be picked up, moved or
	# upgraded, it holds no hen of its own, and nothing is laid in it. A coop that
	# fed the flock, sheltered more than one bird or turned eggs into something is
	# what a tier above this one can be.
	"coop": {
		"name": "Chicken Coop",
		"price": 25,
		"species": "",
		"program": "",
		"configs": [],
		"default_config": "",
		"unlock_requirement": null,
		# What `place` puts on the grid, and what the other three cells of the
		# block become.
		"object": WorldLayout.CHICKEN_COOP,
		"part": WorldLayout.CHICKEN_COOP_PART,
		# Two wide and two deep, anchored at the cell she taps, which is the
		# **front-left** corner: the block runs one square right and one square
		# back. v1 does not rotate, for the stall's reason (P-13).
		"footprint": Vector2i(2, 2),
		# 32x48: the bottom 32 pixels stand on the four cells, the 16 above them
		# are the roof rising behind. The same picture in the shop card, the HUD
		# pill and the yard, which is the rule every placed thing follows.
		"icon": { "sheet": "res://assets/sprites/generated/chicken_coop.png",
			"region": Rect2(0, 0, 32, 48) },
	},
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
		# Its two bays, as catalogue data (2026-09-11). The gateway used to name
		# both of these itself, because the stall was the only multi-cell structure
		# in the game; the coop made that a chain of `if item ==` waiting to happen,
		# so the shape of a structure is a fact about its row now. Same two objects,
		# same two tiles, one fewer branch in the sim.
		"object": WorldLayout.ROBOT_STALL,
		"part": WorldLayout.ROBOT_STALL_SLOT,
		"footprint": Vector2i(2, 1),
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
		# **And its first bird earns the bench** (S-12). See `earns_of` below: the
		# first time one of these completes its job, the training bench joins the
		# shelf. Named here rather than in the sim so the next reactive mark that
		# should open the same rung is one line in this table.
		"earns": "mk2_worked",
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
	#
	# **The top rung, and it is earned rather than saved for** (S-12): it joins the
	# shelf the moment a training bench is standing on the farm, and not before.
	# Until then its card is on the shelf **darkened**, the way a locked seed packet
	# is — the game's one word for "you can see it, not yet yours" (Q-46a) — so the
	# machine the whole game is about is a promise she can see from day one and the
	# bench is visibly what buys it. What a player who reads nothing sees is the
	# picture going bright the first evening a bench stands in her yard, which is
	# also the night the game plays her the robot's story (P-15).  [Playtest]
	"bot_mk3": {
		"name": "Robot Mk III",
		"price": 800,
		# The rung below it. `SimWorld.RUNG_DESK_PLACED`, written out for the
		# layer-1 reason at the top of this file and pinned by a unit test.
		"earned_by": "desk_placed",
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
		# Its own sheet: the Mark I's chassis in teal-green with an antenna and a lit
		# bead — the one outline change that survives at 48px (generated 2026-09-09,
		# provenance in CREDITS.md). Same layout as bot.png, so entities/bot.gd draws it.
		"icon": { "sheet": "res://assets/sprites/generated/bot_mk3.png",
			"region": Rect2(0, 0, 48, 48) },
	},
	# --- the workbench (Q-101, ruled 2026-09-10) -------------------------------
	#
	# *"Build the whole workbench, as a bench you buy and set down."* So it is a
	# row here for the same reason everything else is: until a richer story
	# exists, anything new that enters the farm is bought (the placeholder
	# acquisition rule at the top of this file).
	#
	# **A structure, like the stall** — no species, no brain, no registry entry,
	# nothing to decide. Where it differs from the stall is that the stall's two
	# object types are written into the gateway by name; this row carries its
	# object instead, in the new `object` field, so the structure after it is a
	# row here and nothing else.
	#
	# **Priced at 300** — above the stall and the mark-1, below the mark-2. The
	# bench is worth nothing without a learning robot to put on it and a mark-3
	# costs 800, so it is never the thing she saves for first: it is what she buys
	# once she owns the machine it is about. A strawman for the CEO.  [Playtest]
	#
	# **Earned by a mark-2's first bird** (S-12). The bench is the rung between the
	# machine that reacts and the machine that learns, so it is not on the shelf
	# until a reactive machine has actually worked — chased one crow. Before that
	# its card is darkened like a locked seed packet, so what a player who reads
	# nothing sees is: she sets a mark-2 to shoo, it runs a bird off her tomatoes,
	# and the next time she opens the seed box the bench has come up bright. The
	# lesson is taught by the shelf rather than by a sentence.  [Playtest]
	"workbench": {
		"name": "Workbench",
		"price": 300,
		# The rung it needs, and the rung it opens. Both are
		# `SimWorld.RUNG_*`, written out for the layer-1 reason at the top of
		# this file and pinned by a unit test.
		"earned_by": "mk2_worked",
		"earns": "desk_placed",
		"species": "",
		"program": "",
		"configs": [],
		"default_config": "",
		"unlock_requirement": null,
		# What `place` puts on the grid. Absent on every other row, which is what
		# tells one kind of bought structure from another at the gateway.
		"object": WorldLayout.WORKBENCH,
		# Its own world sprite, 16x32, hung from its bottom edge like the well —
		# so the shop card and the thing standing in the yard are one picture.
		"icon": { "sheet": "res://assets/sprites/generated/workbench.png",
			"region": Rect2(0, 0, 16, 32) },
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
static var ORDER: Array[String] = ["coop", "fence", "sprinkler", "stall", "bot_mk1",
		"bot_mk2", "bot_mk3", "workbench"]


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


# The object a placed structure leaves on the grid, or "" for a row that puts an
# actor there instead (v0.2.2, the workbench). This is what `place` reads to know
# *which* structure it is putting down: the stall's two object types are written
# into the gateway by name, and a second structure would otherwise have been a
# second branch there rather than a row in the catalogue.
static func object_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("object", ""))


# The object the **other** cells of a multi-cell structure become — the stall's
# second bay, the coop's other three squares — or "" for a structure that stands
# on one tile. Never drawn: the renderer hangs the whole picture off the anchor
# and skips these, so they exist to be real to the sim and invisible to the eye.
static func part_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("part", ""))


# How many cells of ground a structure stands on, as width by depth. `Vector2i(1, 1)`
# for everything that stands on the square she tapped and nothing more, which is
# every row that does not say otherwise.
static func footprint_of(key: String) -> Vector2i:
	return TYPES.get(key, {}).get("footprint", Vector2i(1, 1))


# The cells a structure of this row would stand on if it were set down at `anchor`
# — the anchor first, then the rest in a fixed order so that two callers, a save
# and a replay can never disagree about which cell is which.
#
# **The anchor is the front-left corner**: the block runs to the **right** and
# **back** (up the screen, which is -y). That is where the stall's `+1, 0` second
# bay already was, and it is the direction the renderer already draws in — a
# picture is hung from its bottom edge, so the tile she taps is the one the
# structure's feet are on.
static func footprint_cells(key: String, anchor: Vector2i) -> Array[Vector2i]:
	var size := footprint_of(key)
	var out: Array[Vector2i] = []
	for dy in maxi(1, size.y):
		for dx in maxi(1, size.x):
			out.append(anchor + Vector2i(dx, -dy))
	return out


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


# --- the robot ladder, as two fields (S-12) -----------------------------------
#
# The rung a row needs climbed before it is for sale, or "" for a row that is on
# the shelf from day one. The names are `SimWorld`'s `RUNG_*` constants, and the
# question "is this for sale on *this* farm" is `SimWorld.offers` — a row cannot
# answer it alone, because what has been earned is a fact about a farm.
static func earned_by(key: String) -> String:
	return String(TYPES.get(key, {}).get("earned_by", ""))


# ...and the rung a row climbs the first time it is put to use: for a machine,
# the first job it completes; for a structure, being set down, because a bench has
# no job of its own. "" for everything that proves nothing, which is most of the
# shelf. The gateway reads this at those two moments (`SimWorld`'s `crow_scared`
# and `place`).
static func earns_of(key: String) -> String:
	return String(TYPES.get(key, {}).get("earns", ""))


# Has the farm grown enough of something to be sold this? The seeds' own mechanism
# (`CropDefs.is_seed_unlocked`), for machines — nothing uses it today, and it is
# **not** the ladder above: a tally of harvests is a different kind of proof from a
# rung. `SimWorld.offers` asks both.
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

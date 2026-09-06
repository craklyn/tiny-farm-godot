# world_layout.gd — Where the land is, and what opens it (T-8 / Q-34, M1.5)
#
# Layer 1 (data): region definitions and trivial accessors, no logic. The
# generator in systems/sim/sim_world.gd reads this and fills the grid; nothing
# here knows how to fill anything.
#
# **"Ring" was a placeholder and the arrangement is a free design parameter**
# (designer, 2026-08-29). That is why this file exists at all: the generator
# takes a *region definition* rather than computing a distance from spawn, so
# rings, a valley, terraces, hedged fields and linked plots are all expressible
# by editing the data below and nothing else. Do not reintroduce a computed
# distance-from-spawn — the placeholder would silently become the design.
#
# The doc-and-code word is **parcel**: a bounded piece of land that opens when a
# capability is earned. It carries no shape with it, which is the point.
#
# What the arrangement must satisfy, whatever shape it takes (design/13 §5):
#   - the boundary is visible and wordless — a fence, a hedge, a treeline
#   - crossing it is gated by capability, never by a refusal message
#   - each newly-opened parcel introduces exactly one new obstacle type
#   - each parcel is a fresh saturation (Q-32): more work than one sitting
#   - a tap beyond the boundary still answers — she walks to the edge and stops
#
# Everything below marked [Playtest] is a number to tune on device, not a design.
class_name WorldLayout
extends RefCounted

# Tile states this file introduces. Boundaries are not walkable; an open gate is.
const FENCE := "fence"
const HEDGE := "hedge"
const GATE_CLOSED := "gate_closed"
const GATE_OPEN := "gate_open"

# T-37, the designer 2026-09-01: *"create an indoor space representing the
# player's home. The home should have the bed, windows, and very few
# furnishings initially."*
#
# An interior is not a new kind of world — it is another layout: FLOOR is a
# ground the way YARD is (walkable, never tillable), and WALL/WINDOW are
# boundaries the way FENCE and HEDGE are (visible, never walkable, laid as
# rects). The generator needed nothing new to lay them; a window is a wall
# that happens to show the sky.
const WALL := "wall"
const WINDOW := "window"

# T-32, the designer 2026-09-01: *"create a separate form of ground that cannot
# be tilled, and fill the initial fenced space with it."*
#
# **The yard is home, not field.** Walkable exactly like the field ground — she
# crosses it without noticing it is there — and the one state a hoe can never
# open. Everything else is indifferent to it: a hen walks it, a scent washes off
# it, an egg lands on it, a crow flies over it, and nothing in the sim asks
# whether a tile is yard except the `till` guard in the gateway.
#
# It lives here, beside FENCE, because *which land is yard* is a layout fact of
# exactly the same kind as *where the fence runs*: a parcel declares the ground
# it is made of and the generator lays it. Nothing computes it.
const YARD := "yard"

# T-37: the home's ground. Walkable like the yard, untillable like the yard —
# the yard's rule, indoors, on wood.
const FLOOR := "floor"

# The dark a room is cut out of (2026-09-06, the door).
#
# Two maps that are one grid need something between them, and "grass she cannot
# reach" is not it: a page of ordinary ground below the farm would read as land
# with an inexplicable wall around it. VOID is the honest answer — not walkable,
# not tillable, no verb applies to it, and drawn near-black — so the home page is
# a lit room in darkness and the two pages are never foot-connected.
#
# It is deliberately **not** a boundary state (`is_boundary_state` below). A
# boundary is a promise — a fence she will one day open, land that says "not yet"
# — and the void promises nothing. Everything that asks "is this a boundary"
# is asking about that promise; `is_walkable` refuses the void on its own line.
const VOID := "void"

# --- Pages: how two maps live in one grid (2026-09-06) ------------------------
#
# The world is one `SimWorld` whose rows are stacked in pages of PAGE_ROWS: page
# 0 is the farm (rows 0–19, every coordinate the game has ever had, unmoved),
# page 1 is the home interior (rows 20–39). A door is the only way between them
# (`doors` below and the `use_door` verb), which is what keeps saves, replays and
# the Action record indifferent to there being more than one map: a transition is
# an Action like any other, and every tile in the game still has one address.
#
# The number lives here rather than in the sim because it is a fact about how
# *layouts* are laid out — `compose()` shifts the home's rects by exactly one
# page — and layer 2 reads it from here (`SimWorld.PAGE_ROWS`).
const PAGE_ROWS := 20

# Page 1's origin. The home layout is written in its own coordinates (T-37, the
# debug screen still generates it that way); the composed world is that layout
# moved down one page, and nothing else.
const HOME_ORIGIN := Vector2i(0, PAGE_ROWS)

# The farmhouse, and the two ends of the door it holds. Object types rather than
# tile states: the house is a thing standing on the yard, the way the well is.
const HOUSE_WALL := "house_wall"
const HOUSE_DOOR := "house_door"
const HOME_DOORWAY := "home_doorway"

# The robot stall (CEO, 2026-09-06), which is two tiles of one shed: the left cell
# is the one that is *drawn* and the right cell is its second bay. Two object types
# rather than one repeated, because they answer different questions — the renderer
# hangs the 32x32 picture off the left one and draws nothing at all for the right —
# and because a stall that lost its second cell to a save, a layout or a bug is
# then a visible half-shed rather than two sheds standing in each other.
#
# **Neither of them blocks walking.** The stall is open-fronted and its whole
# purpose is to be stood in: a bot walks home into a bay, and the farmer can walk
# through it as she can walk over an egg (`SimWorld.OPEN_OBJECTS`).
const ROBOT_STALL := "robot_stall"
const ROBOT_STALL_SLOT := "robot_stall_slot"

# Who opens a gate, as recorded on the parcel. "start" means no gate at all.
const OPENED_BY_START := "start"
const OPENED_BY_COLD_OPEN := "cold_open"

# The default arrangement. **Placeholder data**: the shape is deliberately the
# cheapest one that satisfies the constraints above, and the designer is expected
# to replace it. The generator does not care what shape this is.
#
#   x: 0                   11        21              31
#   y  +--------------------+---------+---------------+
#   1  |     bin well box   |neighbour|  wood (P2)    |   <- gate (11,4) cold open
#   4  |  cot   YARD (P0)   |  (P0b)  |  logs + trees |   <- gate (21,4) axe
#   7  +====fence===========+ meadow  |               |
#   8  |                    (parcel 1)|               |
#   9  |      weeds                   +===hedge=======+
#   18 |                              |  quarry (P3)  |   <- gate (21,14) pickaxe
#      +------------------------------+---------------+
#
# The yard is fenced on two sides and bounded by the map border on the other two,
# so parcel 0 is genuinely enclosed and the gate is the only way out. Both tool
# gates sit on the same hedge column, so both promises are visible from the open
# meadow rather than one being hidden behind the other.
#
# T-32: parcel 0's ground is YARD rather than field, and the cot sits at (2,4)
# rather than up in the corner — left-aligned, its two-tile sprite filling rows
# 3–4 of the yard's rows 1–6, which is as vertically centred as an even span
# allows. The stations keep the top row: the cot is the object she must find, and
# it now has the middle of the room to itself.
const DEFAULT := {
	"spawn": Vector2i(2, 2),
	"parcels": [
		{
			"id": "yard",
			"rects": [Rect2i(1, 1, 10, 6)],
			"obstacle": "",              # the safe room: nothing to clear, one toy
			# T-32: and now nothing to *till* either, structurally rather than by
			# the accident of there being nothing here. The only parcel with a
			# ground of its own; every other one is field.
			"ground": YARD,
			"boundary": FENCE,
			"density": 0.0,
			"gate": Vector2i(-1, -1),
			"opened_by": OPENED_BY_START,
		},
		{
			"id": "neighbour",
			"rects": [Rect2i(12, 1, 9, 6)],
			"obstacle": "",              # her plot; content is the takeover contract
			"boundary": FENCE,
			"density": 0.0,
			"gate": Vector2i(11, 4),
			"opened_by": OPENED_BY_COLD_OPEN,
		},
		{
			"id": "meadow",
			"rects": [Rect2i(1, 8, 20, 11), Rect2i(12, 7, 9, 1)],
			"obstacle": "obstacle_weed",
			"density": 0.30,             # [Playtest]
			"boundary": "",              # contiguous with the neighbour's plot
			"gate": Vector2i(-1, -1),
			"opened_by": OPENED_BY_START,
			# The designer, 2026-09-01: *"We should include sparse rocks and logs in
			# the un-blocked sections. Once those items are available, then the
			# player can do a superior job clearing that space."* So the field she
			# starts in holds a few things she cannot do anything about yet — the
			# axe and the pickaxe stop being keys to two rooms and become tools that
			# improve ground she already walks on every day.
			#
			# **Sparse, and it must stay sparse**: this is a promise, not a chore.
			# The parcel's *introduction* is still the weed and only the weed (T-10
			# reads `obstacle`/`extra_obstacle`, never this), so "one new obstacle
			# type per parcel" is intact — a scattered boulder is scenery until she
			# has the tool, and the moment she does it is work she chose.
			#
			# The yard gets none: T-32 made it home rather than field, and a rock in
			# the living room is not a promise. The neighbour's plot gets none
			# either — it is the takeover contract, and every tile of it is read as
			# a sentence.
			"scatter": { "kinds": ["obstacle_rock", "obstacle_log"], "count": 6 },  # [Playtest]
		},
		{
			"id": "wood",
			"rects": [Rect2i(22, 1, 9, 8)],
			"obstacle": "obstacle_log",
			"density": 0.22,             # [Playtest]
			"extra_obstacle": "obstacle_tree",
			"extra_density": 0.10,       # [Playtest] — trees are where logs come from
			"boundary": HEDGE,
			"gate": Vector2i(21, 4),
			"opened_by": "axe",
		},
		{
			"id": "quarry",
			"rects": [Rect2i(22, 10, 9, 9)],
			"obstacle": "obstacle_rock",
			"density": 0.28,             # [Playtest]
			"boundary": HEDGE,
			"gate": Vector2i(21, 14),
			"opened_by": "pickaxe",
		},
	],
	# Boundary tiles, listed rather than derived: a boundary is a design object
	# ("this is where the hedge runs"), not a by-product of a rectangle.
	"boundaries": [
		{ "kind": FENCE, "rects": [Rect2i(11, 1, 1, 7), Rect2i(1, 7, 10, 1)] },
		{ "kind": HEDGE, "rects": [Rect2i(21, 1, 1, 18), Rect2i(22, 9, 9, 1)] },
	],
	# Q-46 STRAWMAN, not a ruling (see DESIGNER_QUEUE). Each tool lies on the
	# ground beside the gate it opens, visible from the moment she leaves the
	# yard — a promise she can see and cannot yet take. It becomes collectable
	# when a capability proof fires, and taking it opens the gate.
	# Both thresholds are [Playtest] and this is the one place they live.
	"tools": [
		{
			"tool": "axe",
			"object": "tool_axe",
			"at": Vector2i(20, 4),
			"gate": Vector2i(21, 4),
			"proof": "harvests",
			"threshold": 5,              # [Playtest]
		},
		{
			"tool": "pickaxe",
			"object": "tool_pickaxe",
			"at": Vector2i(20, 14),
			"gate": Vector2i(21, 14),
			"proof": "clear_log",
			"threshold": 3,              # [Playtest]
		},
	],
	# T-15 / Q-39: a finite acorn stock near the trees, no regeneration in phase 1
	# (depletion is the difficulty ramp, and it is meant to be monotonic).
	"acorns": { "rect": Rect2i(22, 1, 9, 8), "count": 8 },  # [Playtest]
	# The takeover contract (WI-4): what the neighbour's plot must read as once
	# the cold open has run. Generation places the *pre*-cold-open state; the
	# neighbour's own actions and the world sleeps produce the rest, so the row is
	# real world state rather than a picture of one.
	"neighbour_plot": {
		"row_y": 4,
		"cleared": [Vector2i(13, 4)],
		"tilled": [Vector2i(14, 4)],
		"cleared_for_demo": Vector2i(15, 4),   # she tills → plants → waters this
		"seeded": [Vector2i(16, 4)],           # stage 0 at generation
		"growing": [{ "at": Vector2i(17, 4), "stage": 1 }],
		"second_row": [Vector2i(14, 5), Vector2i(15, 5), Vector2i(16, 5)],
		"wave_at": Vector2i(12, 4),
		"crop": "wheat",
	},
}


# T-37: the player's home, as its own layout. One room of floor inside a ring
# of wall, two windows in the north wall, an open doorway in the south wall,
# and the bed — deliberately little else ("very few furnishings initially.
# We'll add those later" — the designer, 2026-09-01). The `objects` key
# overrides the farm's fixed stations (generation falls back to
# SimWorld.OBJECT_POSITIONS when a layout does not carry one), which is the
# first step of the multi-map plan: object placement becoming layout data.
#
# Reached from the title screen's debug row (the Zoo's precedent) — nothing in
# the live game leads here yet; wiring the home into play (a door on the farm,
# the cot moving indoors) is content sequencing on the ruled onboarding flow
# and stays the designer's call.
const HOME := {
	"spawn": Vector2i(15, 9),
	"parcels": [
		{
			"id": "home",
			"rects": [Rect2i(11, 6, 10, 7)],
			"obstacle": "",
			"ground": FLOOR,
			"boundary": WALL,
			"density": 0.0,
			"gate": Vector2i(-1, -1),
			"opened_by": OPENED_BY_START,
		},
	],
	"boundaries": [
		# The shell first, then the openings punched into it: later entries
		# overwrite earlier tiles, so the windows and the doorway are literally
		# holes cut in the wall.
		{ "kind": WALL, "rects": [
			Rect2i(10, 5, 12, 1),   # north wall
			Rect2i(10, 13, 12, 1),  # south wall
			Rect2i(10, 6, 1, 7),    # west wall
			Rect2i(21, 6, 1, 7),    # east wall
		] },
		# Two-tile windows (2026-09-07, the designer: bigger windows) — each a
		# side-by-side pair, symmetric about the doorway below.
		{ "kind": WINDOW, "rects": [Rect2i(13, 5, 2, 1), Rect2i(17, 5, 2, 1)] },
		{ "kind": GATE_OPEN, "rects": [Rect2i(15, 13, 1, 1)] },  # the doorway
	],
	# The bed, and nothing else. Its 16x32 sprite rises into (12,6), the top
	# floor row, so the headboard stands against the north wall.
	"objects": [
		{ "type": "cot", "tx": 12, "ty": 7 },
	],
	# Empty on purpose, the Zoo's pattern: no tools, no acorns, and an empty
	# neighbour plot keeps the cold open done and the neighbour unspawned.
	"tools": [],
	"acorns": {},
	"neighbour_plot": {},
}


# --- WORLD: the farm and the home, in one grid (2026-09-06) -------------------
#
# The CEO, 2026-09-06: *"the player can see an entrance to their house from the
# outdoor space, and going inside enters a new map with their bed; a door leads
# back outside."*
#
# This is that, and it is also the ruling the multi-map project was parked on:
# **maps connect in play as door-linked pages of one SimWorld.** Not a second
# world object, not a scene swap — one grid, two pages, and a verb between them.
# Everything the sim already does (saving, replaying, the actor registry, the
# Action record phase 4 trains on) works on it unchanged, because as far as any
# of them can tell the world simply got taller.
#
# DEFAULT and HOME above are untouched and stay the source: DEFAULT is still the
# farm on its own (the tests' plain world), HOME is still the home on its own
# (the title screen's debug room). WORLD is **composed** from them by the pure
# function below rather than written out a third time, so a fence moved in
# DEFAULT or a window cut in HOME lands in the live game with no second edit.
#
# What compose() does, in one sentence each:
#   * everything DEFAULT has — parcels, boundaries, tools, acorns, the
#     neighbour's plot — kept exactly as it is, on page 0;
#   * the farm's fixed objects, minus the cot (it has moved indoors) and plus
#     the farmhouse: five wall tiles and the door in the middle of them;
#   * she wakes at (2,4), the cot's old spot, because (2,2) is now the door;
#   * the home, moved down one page: its room, its walls, its windows, its
#     doorway and its bed, every rect translated by +20y and nothing else;
#   * VOID over the rest of page 1, so the room stands in darkness and row 20
#     is a solid line nobody can walk across;
#   * and the two ends of the door, as a table the `use_door` verb reads.
static func compose() -> Dictionary:
	var world: Dictionary = DEFAULT.duplicate(true)
	# The cot was the thing she had to find in the yard (T-32); it is now the
	# thing she has to go *inside* to find, so she wakes where it used to stand.
	world["spawn"] = Vector2i(2, 4)
	# The farm's own parcels and boundaries are already here, deep-copied by the
	# duplicate above; the home's are appended, one page down. Copies throughout,
	# so nothing the generator or a test does to the composed world can reach back
	# into the two constants it was made from.
	world["parcels"] = (world["parcels"] as Array) + _shifted_parcels(parcels(HOME), HOME_ORIGIN)
	world["boundaries"] = (world["boundaries"] as Array) \
		+ _shifted_boundaries(boundaries(HOME), HOME_ORIGIN)
	world["objects"] = farm_objects() \
		+ _shifted_objects(HOME.get("objects", []), HOME_ORIGIN) \
		+ [
			# The doorway is a hole cut in the home's south wall, and this object
			# is what makes the hole tappable. `bare` because everything else the
			# generator places gets cleared ground and a cleared shoulder around
			# it (T-27 box 3's fat-finger rule) — which here would fill in the
			# hole and punch a ring of walkable floor into the dark outside.
			{ "type": HOME_DOORWAY, "tx": 15, "ty": 13 + PAGE_ROWS, "bare": true },
		]
	# The whole of page 1, laid before the room is: the generator writes VOID
	# over every tile of this rect that no parcel claims. Wider than the map on
	# purpose — the generator clamps, and a fill that had to know the map's width
	# would be a third place that number lives.
	world["void_fill"] = Rect2i(0, PAGE_ROWS, 64, PAGE_ROWS)
	world["doors"] = doors_of_world()
	return world


# The two ends of the one door, as data.
#
# `at` is the tile you tap (an object stands on it, so nobody walks through a
# door by accident); `to` is where you come out, which is always a tile beside
# the door on the far side; `face` is which way you are looking when you get
# there — into the room going in, out into the yard coming back.
#
# A table rather than a pair of hard-coded tiles because the second door was
# free once the first one was data, and because a save whose world has no such
# table must refuse the verb rather than teleport somebody into the dark
# (`SimWorld._apply`'s `door_leads_nowhere`).
static func doors_of_world() -> Array:
	return [
		{ "at": Vector2i(2, 2), "to": Vector2i(15, 12 + PAGE_ROWS), "face": "up",
			"object": HOUSE_DOOR },
		{ "at": Vector2i(15, 13 + PAGE_ROWS), "to": Vector2i(2, 3), "face": "down",
			"object": HOME_DOORWAY },
	]


# The farm's fixed objects in the composed world: the three stations exactly
# where `SimWorld.OBJECT_POSITIONS` has always put them, the cot **gone** (it is
# indoors now, and it arrives with the home's own object list), and the farmhouse
# it went into — a 3x2 facade whose bottom-centre cell is the door.
#
# Written out rather than read from the sim's constant because layer 1 does not
# import layer 2; a test pins the two together so they cannot drift.
static func farm_objects() -> Array:
	return [
		{ "type": "shipping_bin", "tx": 4, "ty": 1 },
		{ "type": "well",         "tx": 6, "ty": 1 },
		{ "type": "seed_box",     "tx": 8, "ty": 1 },
		{ "type": HOUSE_WALL, "tx": 1, "ty": 1 },
		{ "type": HOUSE_WALL, "tx": 2, "ty": 1 },
		{ "type": HOUSE_WALL, "tx": 3, "ty": 1 },
		{ "type": HOUSE_WALL, "tx": 1, "ty": 2 },
		{ "type": HOUSE_WALL, "tx": 3, "ty": 2 },
		{ "type": HOUSE_DOOR, "tx": 2, "ty": 2 },
	]


# Built once, when this class is first touched. A `const` cannot call a
# function, and composing per generation would be work done over and over for an
# answer that cannot change — the inputs are two constants.
static var WORLD: Dictionary = compose()


# The translations, and they are the whole of "the home is on page 1": pure
# Rect2i/Vector2i arithmetic over copies, so HOME itself is never touched and the
# debug home screen keeps generating the room at its own coordinates.
static func _shifted_rects(rects: Array, by: Vector2i) -> Array:
	var out: Array = []
	for r in rects:
		var rect: Rect2i = r
		out.append(Rect2i(rect.position + by, rect.size))
	return out


static func _shifted_parcels(list: Array, by: Vector2i) -> Array:
	var out: Array = []
	for raw in list:
		var p: Dictionary = (raw as Dictionary).duplicate(true)
		p["rects"] = _shifted_rects(p.get("rects", []), by)
		var g: Vector2i = p.get("gate", Vector2i(-1, -1))
		if g.x >= 0:
			p["gate"] = g + by
		out.append(p)
	return out


static func _shifted_boundaries(list: Array, by: Vector2i) -> Array:
	var out: Array = []
	for raw in list:
		var b: Dictionary = (raw as Dictionary).duplicate(true)
		b["rects"] = _shifted_rects(b.get("rects", []), by)
		out.append(b)
	return out


static func _shifted_objects(list: Array, by: Vector2i) -> Array:
	var out: Array = []
	for raw in list:
		var o: Dictionary = (raw as Dictionary).duplicate(true)
		o["tx"] = int(o.get("tx", 0)) + by.x
		o["ty"] = int(o.get("ty", 0)) + by.y
		out.append(o)
	return out


static func parcels(layout: Dictionary = DEFAULT) -> Array:
	return layout.get("parcels", [])


static func boundaries(layout: Dictionary = DEFAULT) -> Array:
	return layout.get("boundaries", [])


static func tools(layout: Dictionary = DEFAULT) -> Array:
	return layout.get("tools", [])


static func spawn(layout: Dictionary = DEFAULT) -> Vector2i:
	return layout.get("spawn", Vector2i(2, 2))


static func plot(layout: Dictionary = DEFAULT) -> Dictionary:
	return layout.get("neighbour_plot", {})


# The parcel a tile belongs to, or {} for a boundary/border tile.
static func parcel_at(t: Vector2i, layout: Dictionary = DEFAULT) -> Dictionary:
	for p in parcels(layout):
		for r in p.get("rects", []):
			if (r as Rect2i).has_point(t):
				return p
	return {}


# The gate that opens a parcel; (-1,-1) when it has none (open from the start).
static func gate_of(parcel_id: String, layout: Dictionary = DEFAULT) -> Vector2i:
	for p in parcels(layout):
		if String(p.get("id", "")) == parcel_id:
			return p.get("gate", Vector2i(-1, -1))
	return Vector2i(-1, -1)


# The tool entry whose gate this is, or {}.
static func tool_for_gate(gate: Vector2i, layout: Dictionary = DEFAULT) -> Dictionary:
	for e in tools(layout):
		if e.get("gate", Vector2i(-1, -1)) == gate:
			return e
	return {}


# The gate a tool opens when she picks it up.
static func gate_for_tool(tool_key: String, layout: Dictionary = DEFAULT) -> Vector2i:
	for e in tools(layout):
		if String(e.get("tool", "")) == tool_key:
			return e.get("gate", Vector2i(-1, -1))
	return Vector2i(-1, -1)


# --- Doors (2026-09-06) -------------------------------------------------------

# Every door this layout has, or [] for a layout that has none — which is every
# layout but WORLD, and every save written before doors existed. A world with no
# doors refuses `use_door` instead of moving anybody, which is what keeps an old
# farm playable rather than dangerous.
static func doors(layout: Dictionary = DEFAULT) -> Array:
	return layout.get("doors", [])


# The door standing on this tile, or {}.
static func door_at(t: Vector2i, layout: Dictionary = DEFAULT) -> Dictionary:
	for d in doors(layout):
		if d.get("at", Vector2i(-1, -1)) == t:
			return d
	return {}


# Is this object one you can go through? The router asks it to decide that a tap
# on a door means the door rather than the ground under it, and the gateway asks
# it as the verb's own guard.
static func is_door_object(obj: String) -> bool:
	return obj == HOUSE_DOOR or obj == HOME_DOORWAY


# Is this object one of a stall's two bays? Asked wherever "a robot may be parked
# here, and nothing may be farmed here" is the question — `SimWorld.is_stall_tile`
# is the one that reads it off the grid.
static func is_stall_object(obj: String) -> bool:
	return obj == ROBOT_STALL or obj == ROBOT_STALL_SLOT


static func is_boundary_state(state: String) -> bool:
	return state == FENCE or state == HEDGE or state == GATE_CLOSED \
		or state == WALL or state == WINDOW


# The ground a parcel is made of, or "" for the ordinary field ground the
# generator lays everywhere by default (T-32). A parcel that names one has its
# plain ground replaced with it; obstacles, boundaries and anything else already
# written into those tiles are left exactly as they are.
static func ground_of(parcel: Dictionary) -> String:
	return String(parcel.get("ground", ""))


# The handful of already-there obstacles a parcel scatters through itself, or {}
# for the parcels that declare none (the designer, 2026-09-01). Separate from
# `obstacle`/`density`, which is what the parcel is *made of* and what T-10
# introduces it with; this is what it merely *contains*.
static func scatter_of(parcel: Dictionary) -> Dictionary:
	return parcel.get("scatter", {})

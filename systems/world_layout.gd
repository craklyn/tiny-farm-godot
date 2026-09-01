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
		{ "kind": WINDOW, "rects": [Rect2i(13, 5, 1, 1), Rect2i(18, 5, 1, 1)] },
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

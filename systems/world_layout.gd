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

# Who opens a gate, as recorded on the parcel. "start" means no gate at all.
const OPENED_BY_START := "start"
const OPENED_BY_COLD_OPEN := "cold_open"

# The default arrangement. **Placeholder data**: the shape is deliberately the
# cheapest one that satisfies the constraints above, and the designer is expected
# to replace it. The generator does not care what shape this is.
#
#   x: 0                   11        21              31
#   y  +--------------------+---------+---------------+
#   1  |  yard (parcel 0)   |neighbour|  wood (P2)    |   <- gate (11,4) cold open
#   6  |  cot bin well box  |  (P0b)  |  logs + trees |   <- gate (21,4) axe
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
const DEFAULT := {
	"spawn": Vector2i(2, 2),
	"parcels": [
		{
			"id": "yard",
			"rects": [Rect2i(1, 1, 10, 6)],
			"obstacle": "",              # the safe room: nothing to clear, one toy
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
	return state == FENCE or state == HEDGE or state == GATE_CLOSED

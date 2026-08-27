# autotile.gd — neighbour-mask maths for the tilled-soil autotile.
#
# Presentation-layer only (docs/ARCHITECTURE.md layer 5): pure functions over
# booleans, no Node/sim/autoload access, so the headless suite can test them.
#
# The sheet (assets/sprites/generated/terrain_dirt.png, built by
# tools/gen_terrain_autotile.py) carries one tile per mask, so the lookup is the
# identity below rather than a hand-maintained table. The previous table mapped
# 256 masks onto 13 tiles and drew the wrong edges for 35 of the 47 reachable
# neighbour configurations.
class_name Autotile
extends RefCounted

const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128

const GRID := 16  # tiles per row/column within one variant block
const WATERED_COL_OFFSET := 16


# A diagonal only matters when both of its adjacent sides are also members —
# otherwise a lone corner neighbour would notch an edge that is fully open.
static func compute_mask(n: bool, ne: bool, e: bool, se: bool,
		s: bool, sw: bool, w: bool, nw: bool) -> int:
	var mask := 0
	if n: mask |= N
	if e: mask |= E
	if s: mask |= S
	if w: mask |= W
	if n and e and ne: mask |= NE
	if e and s and se: mask |= SE
	if s and w and sw: mask |= SW
	if w and n and nw: mask |= NW
	return mask


static func atlas_coord(mask: int, watered: bool = false) -> Vector2i:
	var cx: int = mask % GRID
	var cy: int = mask / GRID
	if watered:
		cx += WATERED_COL_OFFSET
	return Vector2i(cx, cy)


# True when a tile state participates in the tilled-soil region.
static func is_soil(state: String) -> bool:
	return state in ["tilled", "seeded", "growing", "ready"]

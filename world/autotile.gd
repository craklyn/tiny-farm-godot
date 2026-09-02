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


# True when soil should be *drawn* wet — the picture rule, not the sim's flag.
#
# Two things can wet the picture:
#
# - `watered_today`, the sim's flag. Bare `tilled` ground counts since the Q-52
#   ruling (2026-09-02) reversed its playtest-night hide: hiding it hid a
#   genuine "plant here and it is already watered" signal (planting keeps the
#   wetness). The 2026-08-30 confusion the hide answered — wet empty ground
#   reading as waterable — is answered instead by the wetness *animating in*
#   (farm.gd's soak), so it reads as something the rain did, not an invitation.
#
# - `raining`, the sky right now. The sim marks rain's water only at the day
#   turn, so ground tilled in the middle of a rainy day stays dry in the sim
#   until tomorrow — but a sky pouring on open soil that stays bone-dry would
#   be the picture lying the other way, and it is the exact case the ruling
#   describes ("when a tile is tilled/hoed, show it dry and animate it
#   progressively wetter"). Mechanically inert: every reader of the flag is
#   gated on seeded/growing (see `advance_day`'s rain pass), so wetting the
#   picture ahead of the flag changes nothing that happens.
#
# `ready` is deliberately *present*. It was missing, so a ripe crop on a rainy
# day stood on dry ground between wet rows (reported 2026-09-01). A ripe crop's
# soil is still soil with a plant in it; the sim's rain pass was fixed to mark it
# in the same change, and this is the rule that draws it.
#
# Here rather than in the renderer's `_draw` so the headless suite can hold the
# rule to account without a viewport — this file is presentation, but it is the
# pure half of it.
static func draws_wet(state: String, watered_today: bool, raining: bool = false) -> bool:
	if not is_soil(state):
		return false
	return watered_today or raining

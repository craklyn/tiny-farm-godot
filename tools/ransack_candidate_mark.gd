# ransack_candidate_mark.gd — draws one Q-110 candidate on one raided square, for
# tools/capture_ransack_candidates.gd. Not a game script: nothing in `world/` or
# `main.tscn` loads it, and it exists only so three marks that have not been
# picked yet can be photographed on the real farm without being put into the
# renderer first.
#
# It stands in the same place the shipping mark does (`world/ransack_mark.gd`),
# reads the same farm and draws into the same tile, so a plate taken through this
# and a plate taken through the shipping node differ only in the picture.
extends Node2D

const TILE := 16

# "clods_v2", "feather", "stalk" — or "" to draw nothing, which is how the plate
# of the shipping mark is taken.
var variant := ""
var at := Vector2i(-1, -1)
var farm: Node2D = null

# Option (c): the same three clods in the same three places, sat down on the soil
# instead of lifting off it, and darkened until they are unmistakably a hole in
# the ground rather than a lighter patch of it. On screen the soil renders about
# (161, 140, 132); the shipping tint leaves the clods at (140, 108, 85), which is
# under a step of the dirt ramp away from it, and this lands them near (86, 65,
# 49) — two clear steps down, the difference between a scuff and a scratch.
const SEATED_TINT := Color(0.42, 0.33, 0.26, 1.0)

var _feather: Texture2D = preload("res://assets/sprites/generated/feather.png")
var _stalk: Texture2D = preload("res://assets/sprites/generated/tomato_stripped.png")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if farm == null or variant == "":
		return
	var corner := Vector2(at.x * TILE, at.y * TILE)
	match variant:
		"clods_v2":
			if farm.dirt_texture == null:
				return
			# The shipping list, with the lift taken back out of it: the same three
			# spots and the same three patches of the dirt sheet, each put back on
			# the resting line its own spot names. Derived from the shipping
			# geometry rather than copied, so a change to where the clods sit
			# reaches this candidate too.
			var spots: Array = farm.RANSACK_SPOTS
			var list: Array = farm.ransack_clods(at, 0.0)
			for i in list.size():
				var mark: Dictionary = list[i]
				var spot: Vector2 = spots[(i + at.x + at.y) % spots.size()]
				var rect: Rect2 = mark["rect"]
				rect.position.y = at.y * TILE + spot.y
				draw_texture_rect_region(
					farm.dirt_texture, rect, mark["region"], SEATED_TINT)
		"feather":
			draw_texture_rect(_feather, Rect2(corner, Vector2(TILE, TILE)), false)
		"stalk":
			draw_texture_rect(_stalk, Rect2(corner, Vector2(TILE, TILE)), false)

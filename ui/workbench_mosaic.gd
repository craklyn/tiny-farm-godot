# workbench_mosaic.gd — plate 5 of 5: the weights themselves, folded into a picture
#
# **A stub, and deliberately so** (v0.2.2 WI-2). See `ui/workbench_dials.gd` for
# why the five pages were built as empty Controls first.
#
# The page proper is v0.2.2 WI-6: eight columns, one per thing the robot can do,
# and thirteen rows, one per group of numbers it looks at — each cell the sum of
# the weights joining them, warm for "makes me do this" and cool for "puts me
# off". Read-only (P-13): looking at the brain is this release, painting it is not.
extends Control

## The farm to read through, and the robot to read. `""` means the player owns no
## learning robot, and the page draws its empty state.
var farm: Node2D = null
var actor_id: String = ""


func show_robot(farm_node: Node2D, id: String) -> void:
	farm = farm_node
	actor_id = id
	queue_redraw()


func _draw() -> void:
	if actor_id == "":
		Workbench.draw_empty_dash(self)
		return
	# WI-6 fills this in.
	Workbench.draw_empty_dash(self)

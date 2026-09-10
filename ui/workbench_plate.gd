# workbench_plate.gd — plate 3 of 5: the maker's plate on the side of the machine
#
# **A stub, and deliberately so** (v0.2.2 WI-2). See `ui/workbench_dials.gd` for
# why the five pages were built as empty Controls first.
#
# The page proper is v0.2.2 WI-6: five lines of brass saying what the machine
# actually is — how many numbers it looks at, how many it can decide between, how
# fast it learns, how many nights it has had, how undecided it still is — every
# one of them computed from the robot rather than typed, so the plate cannot go
# stale when the code moves under it.
#
# **The one page with words on it**, which is the trade `design/14` makes: a plate
# is a thing you read.
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

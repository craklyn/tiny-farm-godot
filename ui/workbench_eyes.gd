# workbench_eyes.gd — plate 2 of 5: what the robot can see, and what it decided
#
# **A stub, and deliberately so** (v0.2.2 WI-2). See `ui/workbench_dials.gd` for
# why the five pages were built as empty Controls first.
#
# The page proper is v0.2.2 WI-4: the 5x5 patch it observes with each tile's eight
# channels lit or dark, the scalars it also reads (where it is, its energy, what
# it carries, where the bin is), and the thinking strip — eight bars of
# probability with the decision it actually took lit.
#
# **A snapshot, not a feed** (ground rule 7): the world holds while a menu is
# open, so what this page shows is the robot's view at the moment she opened the
# bench, recomputed whenever the bench refreshes.
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
	# WI-4 fills this in.
	Workbench.draw_empty_dash(self)

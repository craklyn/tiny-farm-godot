# workbench_dials.gd — plate 1 of 5: what each thing the robot does is worth
#
# **A stub, and deliberately so** (v0.2.2 WI-2). The bench's shell was built
# first, with all five pages as empty Controls that know how to be handed a robot
# and how to say they have nothing yet — so the five pages could then be filled in
# parallel without any of them touching `ui/workbench.gd` or each other.
#
# The page proper is v0.2.2 WI-3: eight rows in `Rewards.KEYS` order, each with
# its colour bar, its pip, its value, the ten-rung ladder, and a minus and a plus
# that emit a `tune` Action through the gateway.
#
# Everything a page draws lives inside `Workbench.BODY_RECT`; the shell owns the
# screen above it. Coordinates are absolute against the game's 800x600 screen,
# which is why this is a full-rect Control rather than a child of the body.
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
	# WI-3 fills this in. Until then the page is honest about being empty rather
	# than drawing a frame around nothing.
	Workbench.draw_empty_dash(self)

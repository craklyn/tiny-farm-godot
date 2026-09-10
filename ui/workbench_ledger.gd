# workbench_ledger.gd — plate 4 of 5: the days it has had, and how they went
#
# **A stub, and deliberately so** (v0.2.2 WI-2). See `ui/workbench_dials.gd` for
# why the five pages were built as empty Controls first.
#
# The page proper is v0.2.2 WI-5: the machine panel's own scorecard, at the size
# this page has room for, and four small cards beside it — what it expected of the
# day against what it got, how undecided it was, how far last night moved it, and
# how many of its decisions came to nothing.
#
# **The chart is the panel's chart** (ground rule 8): one `BotScorecard`, drawn by
# one file, so the bench and the machine panel can never tell the player two
# different stories about the same week.
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
	# WI-5 fills this in.
	Workbench.draw_empty_dash(self)

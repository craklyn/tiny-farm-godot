# The picture on a square a crow emptied (Q-105, design/04): three clods of
# scattered earth lifting one after another on a slow loop, until she works the
# square again. Its own node rather than part of the farm's `_draw`, because the
# farm only redraws while a reaction is in flight and a ransacked square can
# stand for days — a mark that stirs every frame has to pay for its own frames,
# and this way the cost is three tiny rects per marked square, not the map.
# What it draws is `farm.ransack_clods`, the same list the integration suite
# holds to account; the farm creates and frees these in `_sync_ransack_marks`.
extends Node2D

var at := Vector2i(-1, -1)
var farm: Node2D = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if farm == null or farm.dirt_texture == null:
		return
	for mark in farm.ransack_clods(at, Time.get_ticks_msec() / 1000.0):
		draw_texture_rect_region(farm.dirt_texture, mark["rect"], mark["region"], farm.RANSACK_TINT)

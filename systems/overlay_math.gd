# overlay_math.gd — pure geometry for the world overlay (T-25 / Q-36)
#
# Layer 1 (data/maths): no Node, no autoload, no rendering. It exists so the
# arrow's geometry can be unit-tested headlessly — the drawing in main.gd is then
# only "put this triangle at this angle", which is the part a test cannot check
# and a person can see at a glance.
class_name OverlayMath


# Where to draw an arrow pointing at `target`, given what the camera can see.
#
# Q-36 rejected the whole hint-escalation ladder and kept exactly one thing: when
# the highlighted target is off screen, point at it. The camera follows the
# farmer, so a target can leave the view entirely — at which point the highlight
# is drawing to nobody and there is no other cue at all.
#
# Returns { visible, pos, angle }:
#   visible — false when the target is already on screen, and then nothing should
#             be drawn. An arrow pointing at something you can see is noise.
#   pos     — a point on the inset edge of the view, on the line from the view's
#             centre toward the target. Inset by `margin` so the arrow is drawn
#             *inside* the screen rather than half off it.
#   angle   — radians, from the arrow's position toward the target, so the caller
#             can rotate a triangle by it directly.
static func edge_arrow(view: Rect2, target: Vector2, margin: float = 10.0) -> Dictionary:
	var hidden := { "visible": false, "pos": Vector2.ZERO, "angle": 0.0 }
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return hidden
	if view.has_point(target):
		return hidden

	var centre := view.position + view.size / 2.0
	var dir := target - centre
	if dir.length() < 0.0001:
		return hidden

	# Shrink the view by the margin first, then find where the ray from the centre
	# leaves that smaller box. Scaling the ray by the *tighter* of the two axis
	# limits is what keeps the result on the box rather than past a corner.
	var half := view.size / 2.0 - Vector2(margin, margin)
	half.x = maxf(half.x, 1.0)
	half.y = maxf(half.y, 1.0)

	var scale := INF
	if absf(dir.x) > 0.0001:
		scale = minf(scale, half.x / absf(dir.x))
	if absf(dir.y) > 0.0001:
		scale = minf(scale, half.y / absf(dir.y))
	if scale == INF:
		return hidden

	return {
		"visible": true,
		"pos": centre + dir * scale,
		"angle": dir.angle(),
	}

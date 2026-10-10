# worm.gd — the worm, drawn — all of it (`design/04`; M2.5 WI-8e, WI-6)
#
# **Presentation only.** How long the worm is, where its body lies and what it is
# heading for is `systems/sim/brains/worm_brain.gd` and the movement engine, on
# the tick clock, in the sim. This node draws what
# `Movement.occupied_tiles(world, id)` says is worm.
#
# **This is the first renderer in the game that draws more than one cell for one
# actor**, which is WI-6's handoff to it ("a multi-tile body draws from
# `Movement.occupied_tiles` (head first) rather than from one position"). The
# consequences are small and worth stating:
#   * there is one node, not one per segment — the actor is one actor, and the
#     registry has one entry for it;
#   * `position` is the **head**, so the farm's y-sorted render queue treats a
#     worm as being where its head is;
#   * and it is drawn as **one tube through the tiles it occupies**, not as one
#     sliding sprite per segment (2026-10-09, below).
#
# worm.png is head / body / tail / vertical body / elbow: five cells, and the
# renderer stretches them over every orientation a path can take (designer
# directive, 2026-09-01 — the worm used to draw a sideways head when crawling
# vertically and a broken body at bends):
#   * the directional cells (head, tail, horizontal body) mirror for leftward
#     travel and rotate 90° for vertical travel;
#   * a bend draws the elbow cell (tools/gen_worm_elbow.py, derived 2026-09-07
#     from the body's own slice after the knuckle read as a break in HQ's
#     zoomed preview), rotated to face the two runs it connects.
#
# **How it crawls (2026-10-09).** It used to slide every segment's sprite from the
# tile it was leaving to the tile it was entering while drawing each one in the
# shape of the tile it was *entering*. A worm crawls nearly all the time (2.7 s a
# tile), so on Daniel's tablet (day 19 of the 2026-10-09 session, replayed from its
# log) it spent nearly all its visit in loose pieces: gaps at every bend and
# corners facing the wrong way. Two pictures cannot both be right mid-step, so it
# now draws what a real worm does:
#   * every tile strictly inside the body keeps the joined-up shape it has at
#     rest, and does not move;
#   * the head slides out of the tile behind it into its new tile, trimmed at that
#     tile's centre so it never pokes backwards past a bend;
#   * the tail slides out of the tile it is leaving, trimmed the same way, and the
#     tile ahead of it gives up exactly the strip the tail now covers;
#   * a tail rounding a corner keeps the direction it came in on until its tip
#     reaches the corner's centre, then turns, so it never swings round in one frame;
#   * and each of those pieces takes its place in the farm's depth order by its own
#     row, so a body lying south of its head is not hidden behind the crops and
#     bed edges of rows the head has not reached.
# `pieces()` is that drawing as data — the draw function only walks it — and the
# integration suite rasterises it to check the worm is one connected shape on every
# frame of a crawl through bends (`tools/test_runner.gd`, Scenario U).
#
# Worms visit the live game on one eligible day in ten (`SimWorld.WORM_VISIT_DAY_RATE`).
extends Node2D

const TILE_SIZE := 16
const HALF := 8

# worm.png (CREDITS.md, the 2026-08-31 art bench; split to its own sheet
# 2026-09-06). Every cell faces right and is mirrored for the other direction,
# as the other critters' are.
const SPRITES := preload("res://assets/sprites/generated/worm.png")
const SHEET_ROW := 0
const CELL_HEAD := 0
const CELL_BODY := 1
const CELL_TAIL := 2
const CELL_BODY_VERTICAL := 3
# The derived corner cell; as drawn it opens left and down, and segment_draws
# rotates it for the other three bend orientations.
const CELL_ELBOW := 4
const CELL_JOINT := CELL_ELBOW

var actor_id: String = SpeciesDefs.WORM
var farm: Node2D = null

# Tiles crawled per second, off the species row and the clock, so the drawing
# finishes a step exactly when the sim is ready to take the next one.
var tiles_per_sec: float = 0.37

# What the drawing remembers between frames about the sim's last step.
var _tiles: Array[Vector2i] = []
# How far the head is into its newest tile, and the tail out of the tile it is
# leaving: 0 when the step happens, 1 when the drawing has caught up.
var _head_f: float = 1.0
var _tail_f: float = 1.0
# The direction of the head's last crawl (only needed while it is one tile long).
var _head_dir: Vector2i = Vector2i.RIGHT
# The tile the tail is crawling out of, and the direction the body entered it
# from; `_has_vacated` is false before the first step or after a jump.
var _vacated: Vector2i = Vector2i.ZERO
var _vacated_from: Vector2i = Vector2i.ZERO
var _has_vacated: bool = false


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.WORM) -> void:
	farm = farm_ref
	actor_id = id
	tiles_per_sec = float(SimClock.RATE) / float(
		Movement.ticks_per_tile(farm.sim.species_of(actor_id)))
	_tiles = segment_tiles()
	_head_f = 1.0
	_tail_f = 1.0
	_has_vacated = false
	_place()


# The sim's answer, in tiles, head first. The renderer asks this and nothing else
# about where the worm is.
func segment_tiles() -> Array[Vector2i]:
	return Movement.occupied_tiles(farm.sim, actor_id)


# What each tile looks like **at rest**, head to tail: the cell, a rotation
# (radians), and whether to mirror. `pieces()` builds the moving drawing from
# the same rules; this is the per-tile summary the tests and tooling read.
#   * head/tail point along the path (their cells face right on the sheet):
#     mirrored when the path runs left, rotated ±90° when it runs vertically;
#   * an interior segment reads its net flow (the tile before minus the tile
#     after): straight column → vertical body, straight row → horizontal body
#     (mirrored leftward), and a diagonal net flow is a **bend** → the joint.
func segment_draws() -> Array[Dictionary]:
	var tiles := segment_tiles()
	var n := tiles.size()
	var out: Array[Dictionary] = []
	for i in n:
		if n == 1:
			out.append({"cell": CELL_HEAD, "rot": 0.0, "flip": _head_dir.x < 0})
		elif i == 0:
			out.append(_end_draw(CELL_HEAD, tiles[0] - tiles[1]))
		elif i == n - 1:
			out.append(_end_draw(CELL_TAIL, tiles[n - 2] - tiles[n - 1]))
		else:
			out.append(_joint_draw(tiles[i - 1], tiles[i], tiles[i + 1]))
	return out


# The cells alone, head to tail — the view the tests and any tooling read.
func segment_cells() -> Array[int]:
	var out: Array[int] = []
	for o in segment_draws():
		out.append(o.cell)
	return out


# A head or tail cell pointing along `d` (one tile step).
static func _end_draw(cell: int, d: Vector2i) -> Dictionary:
	var rot := 0.0
	var flip := false
	if d.y < 0:
		rot = -PI / 2
	elif d.y > 0:
		rot = PI / 2
	elif d.x < 0:
		flip = true
	return {"cell": cell, "rot": rot, "flip": flip}


# The piece for a tile with neighbours on both sides: straight, or the elbow.
static func _joint_draw(prev: Vector2i, at: Vector2i, next: Vector2i) -> Dictionary:
	var d := prev - next
	if d.x != 0 and d.y != 0:
		# The elbow opens left and down as drawn; turn it toward the two
		# neighbours this bend actually connects.
		var to_prev := prev - at
		var to_next := next - at
		var opens_left: bool = to_prev.x < 0 or to_next.x < 0
		var opens_up: bool = to_prev.y < 0 or to_next.y < 0
		var rot := 0.0
		if opens_left and opens_up:
			rot = PI / 2
		elif opens_up:
			rot = PI          # up and right
		elif not opens_left:
			rot = -PI / 2     # right and down
		return {"cell": CELL_JOINT, "rot": rot, "flip": false}
	if d.x == 0:
		return {"cell": CELL_BODY_VERTICAL, "rot": 0.0, "flip": false}
	return {"cell": CELL_BODY, "rot": 0.0, "flip": d.x < 0}


static func _centre(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE_SIZE + HALF, t.y * TILE_SIZE + HALF)


# Everything on the far side of the line through `p` across `dir`: ahead of it
# when `ahead`, behind it otherwise. A rectangle, because every clip here is.
static func _half(p: Vector2, dir: Vector2i, ahead: bool) -> Rect2:
	const FAR := 100000.0
	var lo := Vector2(-FAR, -FAR)
	var hi := Vector2(FAR, FAR)
	var toward := dir if ahead else -dir
	if toward.x > 0: lo.x = p.x
	elif toward.x < 0: hi.x = p.x
	if toward.y > 0: lo.y = p.y
	elif toward.y < 0: hi.y = p.y
	return Rect2(lo, hi - lo)


# The drawing, as data: one entry per piece, each a sheet cell placed by its
# centre, turned and mirrored, and trimmed to a world-space rectangle. Pixel
# offsets are whole pixels, so nothing shimmers between frames.
func pieces() -> Array[Dictionary]:
	# Caught up with the sim first: in a frame where the sim stepped after this
	# node's own `_process`, drawing the new tiles with last step's slide would
	# put the body in pieces for that one frame.
	_sync()
	var tiles := segment_tiles()
	var n := tiles.size()
	var out: Array[Dictionary] = []
	if n == 0:
		return out
	var hf := roundi(_head_f * TILE_SIZE)
	var tf := roundi(_tail_f * TILE_SIZE)
	var behind_head: Vector2i = tiles[1] if n > 1 else tiles[0] - _head_dir
	var head_dir: Vector2i = tiles[0] - behind_head
	var head_centre: Vector2 = _centre(behind_head) + Vector2(head_dir * hf)
	if n == 1:
		out.append(_piece(_end_draw(CELL_HEAD, head_dir), head_centre, null))
		return out

	# The body: every tile with a neighbour on both sides — and the last tile
	# counts as one when the tail is still crawling out of the tile behind it.
	var path := tiles.duplicate()
	if _has_vacated:
		path.append(_vacated)
	var last := n - 1
	var tail_dir: Vector2i = tiles[last - 1] - tiles[last]
	var tail_centre: Vector2 = _centre(tiles[last])
	var tail_clip = null
	var rounding := false
	if _has_vacated:
		tail_dir = tiles[last] - _vacated
		rounding = _vacated_from != tail_dir and tf < HALF
		if rounding:
			tail_dir = _vacated_from
		tail_centre = _centre(_vacated) + Vector2(tail_dir * tf)
		tail_clip = _half(_centre(_vacated) if rounding else _centre(tiles[last]),
			tail_dir, false)
	for i in range(1, path.size() - 1):
		var clip = null
		if _has_vacated and i == last and not rounding:
			# The tail covers this tile's back strip as it arrives — up to the
			# centre — so the body gives that strip up rather than hiding the taper.
			var back := _centre(tiles[last]) - Vector2(tail_dir * HALF)
			clip = _half(back + Vector2(tail_dir * mini(tf, HALF)), tail_dir, true)
		out.append(_piece(_joint_draw(path[i - 1], path[i], path[i + 1]),
			_centre(path[i]), clip))
	if rounding:
		# The corner the tail is coming round: the elbow, less the leg the tail
		# is still lying in.
		var corner := _joint_draw(_vacated - _vacated_from, _vacated, tiles[last])
		var cut := _centre(_vacated) - Vector2(_vacated_from * 4)
		out.append(_piece(corner, _centre(_vacated), _half(cut, _vacated_from, true)))
	out.append(_piece(_end_draw(CELL_TAIL, tail_dir), tail_centre, tail_clip))
	# The head last, trimmed at the centre of the tile behind it, so it can turn
	# a corner without its back half sticking out past the bend.
	out.append(_piece(_end_draw(CELL_HEAD, head_dir), head_centre,
		_half(_centre(behind_head), head_dir, true)))
	return out


func _piece(draw: Dictionary, centre: Vector2, clip) -> Dictionary:
	var sx := -1.0 if draw.flip else 1.0
	var xf := Transform2D(draw.rot, Vector2(sx, 1.0), 0.0, centre)
	# The part of the cell inside the clip, in the cell's own frame (centred,
	# facing right). Rotations are quarter turns, so the rectangle stays one.
	var local := Rect2(-8, -8, TILE_SIZE, TILE_SIZE)
	if clip != null:
		var inv := xf.affine_inverse()
		var r: Rect2 = clip
		var a: Vector2 = inv * r.position
		var b: Vector2 = inv * r.end
		# Snapped to whole pixels: a quarter turn's sine is not exactly 1.
		var lo := a.min(b).round()
		var c := Rect2(lo, a.max(b).round() - lo)
		local = local.intersection(c)
	return {
		"cell": draw.cell, "rot": draw.rot, "flip": draw.flip, "centre": centre,
		"xf": xf, "local": local, "y": centre.y - HALF,
	}


# Where the sim's tiles moved since last frame. A crawl is the head stepping
# onto a neighbouring tile with the body following it — the tail either leaving
# its tile or, after a meal, staying put while the worm grows. Anything else (a
# first look, a despawned segment) is drawn where the sim says, with no slide.
func _sync() -> void:
	var now := segment_tiles()
	if now == _tiles:
		return
	var old := _tiles
	_tiles = now
	var n := now.size()
	var crawled := not old.is_empty() and n >= 1 and n >= old.size() \
		and n <= old.size() + 1 \
		and absi(now[0].x - old[0].x) + absi(now[0].y - old[0].y) == 1 \
		and now.slice(1) == old.slice(0, n - 1)
	if not crawled:
		_head_f = 1.0
		_tail_f = 1.0
		_has_vacated = false
		if n > 1:
			_head_dir = now[0] - now[1]
		return
	_head_dir = now[0] - old[0]
	_head_f = 0.0
	if n == old.size():
		# The tail left its tile; remember which way the body came into it.
		var from: Vector2i = _head_dir
		if _has_vacated:
			from = old[old.size() - 1] - _vacated
		elif old.size() > 1:
			from = old[old.size() - 2] - old[old.size() - 1]
		_vacated = old[old.size() - 1]
		_vacated_from = from
		_has_vacated = true
		_tail_f = 0.0
	# A meal: the worm grew a tile at the head, and the tail stays as it was.


func _place() -> void:
	var p := pieces()
	if not p.is_empty():
		position = p[p.size() - 1].centre - Vector2(HALF, HALF)


func _process(delta: float) -> void:
	if farm == null:
		return
	# Full, bored, stomped, or curled up in its own body with nowhere left to go —
	# every one of those is the sim dropping the actor, and the sprite goes with it.
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return
	_sync()
	_head_f = minf(1.0, _head_f + tiles_per_sec * delta)
	_tail_f = minf(1.0, _tail_f + tiles_per_sec * delta)
	_place()
	queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	# One entry per piece, each sorted by its own row, so a body lying south of
	# its head goes in front of what is north of it, as anything else on that
	# row would. `position` is still the head, for the farm's page cull.
	for p in pieces():
		render_queue.append({
			"y": p.y,
			"draw": func():
				var local: Rect2 = p.local
				if local.size.x <= 0.0 or local.size.y <= 0.0:
					return
				# draw_set_transform bleeds into every later draw on this canvas
				# unless reset — reset it.
				canvas.draw_set_transform_matrix(p.xf)
				canvas.draw_texture_rect_region(SPRITES, local, Rect2(
					p.cell * TILE_SIZE + 8 + local.position.x, SHEET_ROW * TILE_SIZE + 8 + local.position.y,
					local.size.x, local.size.y))
				canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		})

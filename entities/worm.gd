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
#   * and each segment slides toward its own tile at the species' own speed, so a
#     growing worm's new segment grows out of the tail rather than appearing.
#
# critters.png row 3 is head / body / tail / vertical body: four cells, and the
# renderer stretches them over every orientation a path can take (designer
# directive, 2026-09-01 — the worm used to draw a sideways head when crawling
# vertically and a broken body at bends):
#   * the directional cells (head, tail, horizontal body) mirror for leftward
#     travel and rotate 90° for vertical travel;
#   * a bend draws the vertical-body cell as a joint — it is the one symmetric
#     cell on the row, so it reads as a knuckle connecting the two runs rather
#     than a break in the animal.
# A dedicated corner cell is still one more cell whenever the art bench comes
# back; the joint reads fine at 16 px.
#
# **Nothing spawns one in the live game** (`SimWorld.WORM_VISITS_PER_DAY` is 0, and
# the debut is a designer's content-sequencing call), so this is exercised in a
# detached farm by the integration suite — the sprinkler's standing, and for the
# sprinkler's reason.
extends Node2D

const TILE_SIZE := 16

# worm.png (CREDITS.md, the 2026-08-31 art bench; split to its own sheet
# 2026-09-06). Every cell faces right and is mirrored for the other direction,
# as the other critters' are.
const SPRITES := preload("res://assets/sprites/generated/worm.png")
const SHEET_ROW := 0
const CELL_HEAD := 0
const CELL_BODY := 1
const CELL_TAIL := 2
const CELL_BODY_VERTICAL := 3
# The one symmetric cell doubles as the bend joint (see the header comment).
const CELL_JOINT := CELL_BODY_VERTICAL

# A long frame must not teleport it — the hen's cap.
const MAX_STEP := TILE_SIZE * 0.5

var actor_id: String = SpeciesDefs.WORM
var farm: Node2D = null

# Pixels per second off the species row, so the sprite crawls at exactly the speed
# the sim crawls the worm and cannot drift as the row is tuned.
var speed_px: float = 6.0

var facing_left: bool = false
# Where each segment's sprite is *now*, chasing where the sim says that segment
# is. Index 0 is the head, as `Movement.occupied_tiles` orders them.
var seg_px: Array[Vector2] = []


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.WORM) -> void:
	farm = farm_ref
	actor_id = id
	speed_px = SpeciesDefs.speed_of(farm.sim.species_of(actor_id)) * TILE_SIZE * float(SimClock.RATE)
	_sync_segments()
	for i in seg_px.size():
		seg_px[i] = _tile_px(segment_tiles()[i])
	if not seg_px.is_empty():
		position = seg_px[0]


# The sim's answer, in tiles, head first. The renderer asks this and nothing else
# about where the worm is.
func segment_tiles() -> Array[Vector2i]:
	return Movement.occupied_tiles(farm.sim, actor_id)


# What each segment draws, head to tail: the cell, a rotation (radians), and
# whether to mirror. Orientation is read from the tile path, never from pixel
# positions, so a segment mid-slide keeps the orientation of the step it is on.
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
		var cell := CELL_BODY
		var rot := 0.0
		var flip := false
		var d := Vector2i.ZERO
		if n == 1:
			cell = CELL_HEAD
			flip = facing_left
		elif i == 0:
			cell = CELL_HEAD
			d = tiles[0] - tiles[1]
		elif i == n - 1:
			cell = CELL_TAIL
			d = tiles[n - 2] - tiles[n - 1]
		else:
			d = tiles[i - 1] - tiles[i + 1]
			if d.x != 0 and d.y != 0:
				cell = CELL_JOINT
			elif d.x == 0:
				cell = CELL_BODY_VERTICAL
			else:
				cell = CELL_BODY
				flip = d.x < 0
		if cell == CELL_HEAD or cell == CELL_TAIL:
			if d.y < 0:
				rot = -PI / 2
			elif d.y > 0:
				rot = PI / 2
			elif d.x < 0:
				flip = true
		out.append({"cell": cell, "rot": rot, "flip": flip})
	return out


# The cells alone, head to tail — the view the tests and any tooling read.
func segment_cells() -> Array[int]:
	var out: Array[int] = []
	for o in segment_draws():
		out.append(o.cell)
	return out


func _tile_px(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE_SIZE, t.y * TILE_SIZE)


# Keep one sprite position per segment the sim says exists. A worm that has just
# eaten is one segment longer, and the new one starts where the old tail is so it
# crawls out of it rather than appearing a tile away.
func _sync_segments() -> void:
	var want := segment_tiles().size()
	while seg_px.size() < want:
		seg_px.append(seg_px[seg_px.size() - 1] if not seg_px.is_empty() else Vector2.ZERO)
	if seg_px.size() > want:
		seg_px.resize(want)


func _process(delta: float) -> void:
	if farm == null:
		return
	# Full, bored, stomped, or curled up in its own body with nowhere left to go —
	# every one of those is the sim dropping the actor, and the sprite goes with it.
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	_sync_segments()
	var tiles := segment_tiles()
	var step := minf(speed_px * delta, MAX_STEP)
	for i in tiles.size():
		var goal := _tile_px(tiles[i])
		if i == 0:
			if goal.x < seg_px[0].x:
				facing_left = true
			elif goal.x > seg_px[0].x:
				facing_left = false
		seg_px[i] = seg_px[i].move_toward(goal, step)
	if not seg_px.is_empty():
		position = seg_px[0]
	queue_redraw()


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		# The head's row is where a worm is, as far as the y-sort is concerned.
		"y": position.y,
		"draw": func():
			var draws := segment_draws()
			# Tail first, so the head is drawn over the segment behind it.
			for i in range(draws.size() - 1, -1, -1):
				if i >= seg_px.size():
					continue
				var at: Vector2 = seg_px[i]
				var o: Dictionary = draws[i]
				var src := Rect2(o.cell * 16, SHEET_ROW * 16, 16, 16)
				if o.rot != 0.0:
					# Rotate about the cell's centre. draw_set_transform bleeds into
					# every later draw on this canvas unless reset — reset it.
					canvas.draw_set_transform(at + Vector2(8, 8), o.rot, Vector2.ONE)
					canvas.draw_texture_rect_region(
						SPRITES, Rect2(-8, -8, TILE_SIZE, TILE_SIZE), src)
					canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					var dest := Rect2(at.x, at.y, TILE_SIZE, TILE_SIZE)
					if o.flip:
						dest = Rect2(at.x + TILE_SIZE, at.y, -TILE_SIZE, TILE_SIZE)
					canvas.draw_texture_rect_region(SPRITES, dest, src)
	})

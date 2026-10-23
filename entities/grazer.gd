# grazer.gd — the rabbit and the kangaroo, drawn (`design/04`; M2.5 WI-8c/8f, WI-6)
#
# **Presentation only, and one file for both.** Where a grazer is, what it eats,
# when it runs and where it goes is `systems/sim/brains/grazer_brain.gd`, on the
# tick clock, in the sim. This node slides a sprite toward the tile the registry
# holds and animates the hop — the hen's job, with the hen's stalled-frame cap.
#
# The two species share a script for the same reason they share a brain: they
# differ by which row of `critters.png` they draw and how fast they move, and both
# of those are read off `SpeciesDefs` rather than written here. A renderer per
# species would have been two copies of `entities/ant.gd`, which is already one
# copy of the hen — and it would have been the one place in the codebase where the
# kangaroo was a special case, which is exactly what WI-8f exists to disprove.
#
# **Nothing spawns either in the live game** (every `per_day` in
# `SimWorld.visitors()` is 0, and the debut is a designer's content-sequencing
# call), so this is exercised in a detached farm by the integration suite — the
# sprinkler's standing, and for the sprinkler's reason: the renderer is the half a
# sim-only work item cannot write, and it should exist for the day the species is
# turned on.
extends Node2D

const TILE_SIZE := 16

# One sheet per species (CREDITS.md, the 2026-08-30 art bench; split 2026-09-06):
# each is its four-frame hop in one row. Every cell faces right and is mirrored
# for the other direction, as the ants' are — the flip is a negative width on
# the destination rect, because unlike the hen's sheet these do not carry their
# own left-facing frames.
const SPRITES := {
	SpeciesDefs.RABBIT: preload("res://assets/sprites/generated/rabbit.png"),
	SpeciesDefs.KANGAROO: preload("res://assets/sprites/generated/kangaroo.png"),
	SpeciesDefs.COW: preload("res://assets/sprites/generated/cow.png"),
}
const HOP_FRAMES := 4
const FRAME_TIME := 0.13

# A long frame must not teleport it — the hen's cap, for the report her comment
# records (a stalled frame used to carry her a whole tile in one step).
const MAX_STEP := TILE_SIZE * 0.5

var actor_id: String = SpeciesDefs.RABBIT
var farm: Node2D = null

var sprites: Texture2D = SPRITES[SpeciesDefs.RABBIT]
# Pixels per second, derived from the species' own tiles-per-tick rather than
# written down again here: the sprite then moves at exactly the speed the sim
# moves the animal, so it trails by less than a tile and cannot drift as the row
# is tuned. It is also the only place the kangaroo visibly differs from the
# rabbit, and it differs by arithmetic on the table.
var speed_px: float = 30.0

var facing_left: bool = false
var hop_frame: int = 0
var coat_row: int = 0
var is_cow: bool = false
# A sheep is drawn as a cow is, from the sim clock, from her own sheet: the row is
# her look and her coat (`SheepArt`, docs/design/18-sheep.md).
var is_sheep: bool = false
var waddling: bool = false
var sheep_gait: Dictionary = {}
# A sheep stopped for good does more than wiggle (design/18, "Stuck for good";
# `SheepGags`): the neck stretch frame she shows instead (-1 for none) and which way
# she strains, and the bird on her back ({} for none). Read off the sim tick.
var stretch_frame: int = -1
var stretch_left: bool = false
var bird: Dictionary = {}
const BIRD_SHEET := preload("res://assets/sprites/generated/songbird.png")
# Cosmetic, and the only die roll in this file: two animals in one field should
# not hop in lockstep. `CosmeticRng`, never the sim's seeded stream — see
# systems/cosmetic_rng.gd, and the unit test that reads this directory for the
# name of that stream and fails on a hit.
var _frame_timer: float = CosmeticRng.randf_range(0.0, FRAME_TIME)


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.RABBIT) -> void:
	farm = farm_ref
	actor_id = id
	var species: String = farm.sim.species_of(actor_id)
	is_sheep = species == SpeciesDefs.SHEEP
	sprites = SheepArt.sheet() if is_sheep else SPRITES.get(species, SPRITES[SpeciesDefs.RABBIT])
	speed_px = SpeciesDefs.speed_of(species) * TILE_SIZE * float(SimClock.RATE)
	is_cow = species == SpeciesDefs.COW or is_sheep
	position = sim_position()


func sim_position() -> Vector2:
	# `Movement.float_pos` falls back to the registry tile for anybody without a
	# continuous position, so the path that draws a flying crow draws a hopping
	# rabbit without knowing which it has (WI-4's handoff).
	var at := Movement.float_pos(farm.sim, actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)


func _process(delta: float) -> void:
	if farm == null:
		return
	# Full, bored, or safely back through the hedge — every one of those is the
	# sim dropping the actor, and the sprite goes with it.
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	# **A cow is drawn from the sim clock, not this frame's delta** (design/17;
	# the barn plan's "Connect barn animation to simulation state"). Her walk
	# into the barn, through its door and into a stall is read off her saved
	# step and the tick (`BarnPresentation.cow_pose`), so a paused game or a
	# reloaded save draws her exactly where that tick puts her.
	if is_cow:
		var pose := BarnPresentation.cow_pose(farm.sim, actor_id, farm.sim.clock.tick)
		var at: Vector2 = pose.get("pos", Vector2.ZERO) * TILE_SIZE
		var frame := int(pose.get("frame", 0))
		var left := bool(pose.get("facing_left", false))
		var row := SheepArt.row_of(SheepArt.look_of(actor_id), Wool.coat_of(farm.sim, actor_id)) if is_sheep else 0
		var waddle := is_sheep and bool(pose.get("waddling", false))
		var gags_changed := is_sheep and _read_gags(farm.sim.clock.tick)
		if at != position or frame != hop_frame or left != facing_left or row != coat_row or waddle != waddling or gags_changed:
			position = at
			hop_frame = frame
			facing_left = left
			coat_row = row
			waddling = waddle
			sheep_gait = pose.get("gait", {})
			queue_redraw()
		return

	var goal := sim_position()
	if not position.is_equal_approx(goal):
		_frame_timer += delta
		if _frame_timer >= FRAME_TIME:
			_frame_timer -= FRAME_TIME
			hop_frame = (hop_frame + 1) % HOP_FRAMES
		if goal.x < position.x:
			facing_left = true
		elif goal.x > position.x:
			facing_left = false
		position = ActorMotion.follow(farm.sim, position, goal, minf(speed_px * delta, MAX_STEP), TILE_SIZE)
		queue_redraw()
	elif hop_frame != 0:
		# A sitting rabbit sits: frame 0 is the resting pose, which is also what
		# the player sees for the second or two it is chewing.
		hop_frame = 0
		queue_redraw()


# The stretch and the bird, from the tick. True when either changed since the last
# frame, so a stuck sheep redraws only when something about her picture moved.
func _read_gags(tick: int) -> bool:
	var frame := -1
	var left := facing_left
	var visit := {}
	if SheepGags.is_stuck_outside(farm.sim, actor_id):
		visit = SheepGags.bird(actor_id, tick)
		if SheepArt.has_stretch():
			var target := SheepGags.stretch_target(farm.sim, actor_id)
			if not target.is_empty():
				frame = SheepGags.stretch_frame(actor_id, tick)
				left = bool(target["left"])
	var changed := frame != stretch_frame or (frame >= 0 and left != stretch_left) or visit != bird
	stretch_frame = frame
	stretch_left = left
	bird = visit
	return changed


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			var rows := SheepArt.ROWS if is_sheep else 1
			var cell := cell_size(sprites, rows)
			if stretch_frame >= 0:
				canvas.draw_texture_rect_region(sprites, cell_dest(sprites, position, stretch_left, rows),
					SheepArt.stretch_rect(SheepArt.look_of(actor_id), stretch_frame))
			elif waddling and SheepArt.has_waddle():
				_draw_waddle(canvas)
			else:
				canvas.draw_texture_rect_region(sprites, cell_dest(sprites, position, facing_left, rows),
					Rect2(hop_frame * cell.x, coat_row * cell.y, cell.x, cell.y))
			if not bird.is_empty():
				_draw_bird(canvas)
	})


# The shoulders and hips move with the fleece; planted hooves stay at fixed
# world coordinates. All four limbs go behind the coat, so wool hides the upper
# joints and the far legs instead of adding a row of exposed feet along her belly.
func _draw_waddle(canvas: CanvasItem) -> void:
	for leg in sheep_gait.get("legs", []):
		var ink := Color("2f2b3d") if bool(leg["near"]) else Color("4f4e5d")
		canvas.draw_line(leg["root"].round(), leg["joint"].round(), ink, 1.0, false)
		canvas.draw_line(leg["joint"].round(), leg["hoof"].round(), ink, 1.0, false)
		canvas.draw_rect(Rect2(leg["hoof"].round() + Vector2(-1, 0), Vector2(2, 1)), ink)
	var body_at := position - Vector2(0.0, float(sheep_gait.get("body_lift", 0.0)))
	canvas.draw_texture_rect_region(sprites, cell_dest(sprites, body_at, facing_left, SheepArt.ROWS),
		SheepArt.waddle_rect(SheepArt.look_of(actor_id), 0))


# The songbird on her back, and her heart when it lands. Its offsets are drawn for a
# sheep facing right and mirrored with her, as her own frames are.
func _draw_bird(canvas: CanvasItem) -> void:
	var mirror := -1.0 if (stretch_left if stretch_frame >= 0 else facing_left) else 1.0
	var foot := position + Vector2(TILE_SIZE / 2.0, TILE_SIZE)
	var at: Vector2 = foot + Vector2(bird["pos"].x * mirror, bird["pos"].y)
	var col := 0 if not bool(bird["flying"]) else 1 + int(bird["flap"])
	var left := bool(bird["left"]) != (mirror < 0.0)
	# A negative width mirrors the cell in place, as `cell_dest` relies on.
	canvas.draw_texture_rect_region(BIRD_SHEET, Rect2(at.x - 8.0, at.y - 13.0, -16.0 if left else 16.0, 16.0),
		Rect2(col * 16, 0, 16, 16))
	var since := float(bird["heart"])
	var sheet := SheepArt.gag_sheet()
	if since >= 0.0 and sheet != null:
		var heart := SheepArt.gag_rect("heart")
		var rise := since / SheepGags.HEART_SECONDS
		canvas.draw_texture_rect_region(sheet,
			Rect2(foot + Vector2(6.0 * mirror - heart.size.x / 2.0, -34.0 - 8.0 * rise), heart.size),
			heart, Color(1, 1, 1, 1.0 - rise * rise))


# A sheet is its four frames in one row, so a cell is a quarter of its width and
# all of its height — or, for the sheep's five coats, a fifth of it.
static func cell_size(sheet: Texture2D, rows: int = 1) -> Vector2:
	if rows == SheepArt.ROWS and sheet == SheepArt.sheet():
		return Vector2(SheepArt.cell_size())
	return Vector2(sheet.get_width() / HOP_FRAMES, sheet.get_height() / rows)


# Where one frame lands for an animal whose square's corner is `at`. A cell larger
# than a square (the cow's, design/17 "How big a cow is") stands on the middle of the
# square's bottom edge and overhangs it sideways and upward, as the farmer's own
# picture does; a 16px cell lands exactly on the square. A negative width flips the
# cell, which is how a right-facing sheet draws an animal moving left.
static func cell_dest(sheet: Texture2D, at: Vector2, flip: bool, rows: int = 1) -> Rect2:
	var cell := cell_size(sheet, rows)
	var corner := Vector2(at.x + (TILE_SIZE - cell.x) / 2.0, at.y + TILE_SIZE - cell.y)
	if flip:
		return Rect2(corner.x, corner.y, -cell.x, cell.y)
	return Rect2(corner, cell)

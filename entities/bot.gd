# bot.gd — the bot, drawn (M2.5 WI-9; `design/06`)
#
# **Presentation only.** What a bot is doing — follow, circle, shoo — is
# `systems/sim/brains/bot_brain.gd`, on the tick clock, in the sim. This node
# slides a sprite toward the tile the registry has it on and animates the walk,
# which is the whole of a renderer's job (plan §1 rule 7).
#
# **It is the player's draw path, verbatim, and that is why `bot.png` looks like
# that.** WI-6's handoff put the sheet at 192x192, 4x4 cells of 48 px in
# `characters.png`'s exact layout — rows down / up / left / right, frame 0 the
# standing idle — so a bot renderer could reuse `player/player.gd`'s
# `_load_sprites` / `queue_render` pair with the texture swapped and nothing else
# changed. The only real difference is where the position comes from: the farmer
# is driven by *input*, and a bot is a **registry mirror** — it walks toward
# `world.actor_pos()` the way the hen does, because sim truth is the only thing it
# is allowed to know (WI-6's handoff, and the reason `sync_actors` can build one
# for any farm, including a farm nobody is playing).
#
# Cosmetic dice are `CosmeticRng`, never the sim's seeded stream — there is a unit
# test that reads this directory and fails on a hit.
extends Node2D

const TILE_SIZE := 16

# 4x4 of 48 px: rows are down / up / left / right, columns are the walk cycle with
# frame 0 the standing idle (CREDITS.md, the 2026-08-30 art bench).
const SPRITES := preload("res://assets/sprites/generated/bot.png")
const CELL := 48
const WALK_FRAMES := 4
const FRAME_TIME := 0.14  # the 4-frame walk budget in docs/design/09, as the hen's

# Its own row's speed, in px/s, so the sprite walks between the sim's tiles at the
# pace the sim moves it — read off `SpeciesDefs` rather than written down again,
# so it cannot drift as the row is tuned (the ant renderer's rule).
var speed_px: float = 48.0

# A long frame must not teleport it: `_process` is handed real frame time, and one
# stalled frame — a shader compile, a menu rebuild — would otherwise carry it a
# whole tile in a step. The hen's cap, for the hen's reason.
const MAX_STEP := TILE_SIZE * 0.75

var actor_id: String = SpeciesDefs.BOT
var farm: Node2D = null

var facing: String = "down"
var walk_frame: int = 0
var _frame_timer: float = 0.0


# The renderer contract every actor sprite answers (M2.5 WI-6).
func init_actor(farm_ref: Node2D, id: String = SpeciesDefs.BOT) -> void:
	farm = farm_ref
	actor_id = id
	speed_px = SpeciesDefs.speed_of(farm.sim.species_of(actor_id)) * TILE_SIZE * float(SimClock.RATE)
	position = sim_position()
	facing = String(farm.sim.actor(actor_id).get("facing", "down"))
	# Cosmetic, and the only die roll in this file: two bots off the same line
	# should not march in lockstep.
	_frame_timer = CosmeticRng.randf_range(0.0, FRAME_TIME)


# Where the sim says it is, in pixels. `Movement.float_pos` falls back to the
# registry tile for anybody without a continuous position, so the one code path
# that draws a flying crow draws a walking machine too (WI-4's handoff).
func sim_position() -> Vector2:
	var at := Movement.float_pos(farm.sim, actor_id)
	return Vector2(at.x * TILE_SIZE, at.y * TILE_SIZE)


func _process(delta: float) -> void:
	if farm == null:
		return
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	var goal := sim_position()
	var moving := not position.is_equal_approx(goal)
	if moving:
		_frame_timer += delta
		if _frame_timer >= FRAME_TIME:
			_frame_timer -= FRAME_TIME
			# Frame 0 is the standing idle, so the walk cycle is the other three:
			# a bot that walked through frame 0 would bob to a halt every stride.
			walk_frame = 1 + ((walk_frame) % (WALK_FRAMES - 1))
			queue_redraw()
		position = position.move_toward(goal, minf(speed_px * delta, MAX_STEP))
		queue_redraw()
	elif walk_frame != 0:
		walk_frame = 0
		queue_redraw()

	# The facing is the sim's — `Movement.place_on_tile` writes it from the
	# direction of travel, so the sprite cannot end up facing a way the actor is
	# not going.
	var says := String(farm.sim.actor(actor_id).get("facing", ""))
	if says != "" and says != facing:
		facing = says
		queue_redraw()


# Which cell of the sheet this frame draws, for the tests to read without a
# canvas — `characters.png`'s layout, so this arithmetic is the player's.
func cell_region() -> Rect2:
	var row := ["down", "up", "left", "right"].find(facing)
	if row < 0:
		row = 0
	return Rect2(walk_frame * CELL, row * CELL, CELL, CELL)


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	# The player's own offset, applied to the same place she applies it: her node
	# sits at the *centre* of her tile and draws at (-24, -32) from there — half a
	# cell across, and high enough that the feet stand on the tile rather than the
	# head. This node sits at the tile's corner like every other actor renderer, so
	# the centre is spelled out and the two numbers are hers
	# (`player/player.gd:queue_render`).
	var centre := position + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var draw_pos := centre + Vector2(-CELL / 2.0, -CELL * 2.0 / 3.0)
	var region := cell_region()
	render_queue.append({
		"y": position.y,
		"draw": func():
			canvas.draw_texture_rect_region(
				SPRITES, Rect2(draw_pos, Vector2(CELL, CELL)), region)
	})

# crow.gd — the crow, drawn (Q-10; M2.5 WI-3)
#
# **Presentation only.** The visit itself — when a crow comes (T-20's action
# clock), whether it may (T-2's readiness gate), what it goes for (T-15's
# acorn preference), how it flies, when it eats and when it leaves — is
# `systems/sim/brains/crow_brain.gd`, on the tick clock, in the sim. This node
# draws a bird at the position the registry holds and makes the noises.
#
# That is finding F-4 dead: the eat used to land *when this sprite arrived*, at
# whatever frame rate the device managed, racing the player's taps. It lands at a
# tick now.
#
# **One thing is still measured here**, and deliberately: how close the player is
# standing. Her position is not sim truth until the movement engine lands
# (WI-4/WI-6), so the proximity check stays where it can see her — and the answer
# goes back through the one gateway as the `crow_scared` verb, exactly as it
# always did. That means it is a recorded Action, so a replay still ends the visit
# where the session did. Scarecrows, which *are* sim truth, are noticed by the
# brain instead.
extends Node2D

const TILE_SIZE := 16

const SPRITES := preload("res://assets/sprites/generated/crow.png")

# Inbound and outbound flight speeds in px/s. The sim moves the bird in tiles per
# tick at the same rates (`SpeciesDefs` and `CrowBrain.EXIT_PX_PER_SECOND`); these
# are what walks the sprite between the sim's ten-per-second positions, so the two
# agree and the sprite trails by less than a tile.
const FLY_IN_SPEED := 60.0
const FLY_OUT_SPEED := 80.0
const MAX_STEP := TILE_SIZE * 1.5  # a stalled frame must not fling it across the farm

# --- the meal, animated (designer, 2026-09-10) --------------------------------
#
# "When a crow has landed on a crop and is eating it, we need to add an animation
# that draws attention to it and indicates things are not going well. At a
# minimum, bird turning left and right, and waving its wings."
#
# A bird on the food used to be one still cell held for the whole five seconds of
# the meal (`CrowBrain.EAT_SECONDS`), which is the alarm backwards: the most
# expensive thing on the farm was the only thing on screen not moving. So a
# feeding crow flaps on a quick beat and turns on a slower one — three flaps to a
# turn, so the two beats read as one bird rather than two loops running side by
# side — and the wings-up frame rides a pixel high, which is what keeps it a bird
# pecking and flapping instead of two pictures swapping.
#
# Presentation only, and time only: no die is rolled here (a flock would have to be
# desynced, and there is one crow a day — `SimWorld.CROWS_PER_DAY`) and nothing is
# written to the sim. How long the meal lasts, what it is eating and how it ends
# all stay the brain's.
const EAT_FLAP_TIME := 0.3
const EAT_TURN_TIME := 0.9
const EAT_BOB_PX := 1.0

var actor_id: String = SimWorld.ACTOR_CROW
var farm: Node2D = null
var player: Node2D = null

var flap_timer: float = 0.0
var flap_state: int = 0

var _eat_flap_timer: float = 0.0
var _eat_turn_timer: float = 0.0
var _eat_wings_up := false
# Mirrored the way every other critter renderer in this directory mirrors — the
# sheet faces one way and a negative width draws the other (`ant.gd`,
# `songbird.gd`, `grazer.gd`). For those it is a direction of travel; here the bird
# is standing still on the crop, so it is the turn itself.
var facing_left: bool = false

var _last_state := ""
var _scared_reported := false


# The renderer contract every actor sprite answers (M2.5 WI-6). The farmer is
# found *through* the farm rather than passed in, because every farm renderer has
# one at the same path and this node must not care which scene it is in — the
# title screen's attract loop drives a farm with a sibling literally named Player
# for exactly that reason (design/11's coupling note).
func init_actor(f: Node2D, id: String = SimWorld.ACTOR_CROW) -> void:
	farm = f
	player = f.player_node() if f.has_method("player_node") else null
	actor_id = id
	position = sim_position()
	_last_state = _state()
	# Cosmetic, and the only die roll in this file: a flock should not flap in
	# unison. `CosmeticRng`, never the sim's seeded stream — see
	# systems/cosmetic_rng.gd for which is which and why.
	flap_timer = CosmeticRng.randf_range(0.0, 0.1)


func _extra() -> Dictionary:
	return farm.sim.actor(actor_id).get("extra", {})


func _state() -> String:
	return String(_extra().get("state", ""))


# Where the sim says the bird is, in pixels. The brain keeps a continuous
# tile-space position in `extra` (the registry tile is the rounded version of it),
# which is what makes a smooth flight possible from a ten-hertz truth.
func sim_position() -> Vector2:
	var e := _extra()
	if e.has("fx"):
		return Vector2(float(e["fx"]) * TILE_SIZE, float(e["fy"]) * TILE_SIZE)
	var t: Vector2i = farm.sim.actor_pos(actor_id)
	return Vector2(t.x * TILE_SIZE + TILE_SIZE / 2.0, t.y * TILE_SIZE + TILE_SIZE / 2.0)


func _process(delta: float) -> void:
	if farm == null:
		return
	if not farm.sim.has_actor(actor_id):
		queue_free()
		return

	var state := _state()

	# Animation
	flap_timer += delta
	if flap_timer > 0.1:
		flap_timer = 0.0
		flap_state = (flap_state + 1) % 2
		queue_redraw()

	# The player half of the crow's `senses` row, the half that cannot be sim truth
	# yet. Reported through the gateway, which is what ends the visit.
	if state == "flying_in" or state == "eating":
		if _player_is_near():
			_report_scare()
			state = _state()  # the gateway ends the visit synchronously

	if state != _last_state:
		if state == "leaving":
			_announce_departure(String(_extra().get("leaving_because", "")))
		_last_state = state

	# The meal's two beats, taken after the scare report above so a bird frightened
	# this frame is out of the eating pose in the same frame it turns around.
	if state == "eating":
		_eat_flap_timer += delta
		if _eat_flap_timer >= EAT_FLAP_TIME:
			_eat_flap_timer -= EAT_FLAP_TIME
			_eat_wings_up = not _eat_wings_up
			queue_redraw()
		_eat_turn_timer += delta
		if _eat_turn_timer >= EAT_TURN_TIME:
			_eat_turn_timer -= EAT_TURN_TIME
			facing_left = not facing_left
			queue_redraw()
	elif _eat_wings_up or facing_left or _eat_flap_timer > 0.0 or _eat_turn_timer > 0.0:
		# The meal is over — a mouthful, a fright, a scarecrow, or the mercy crow's
		# perch running out. However it ended, the bird leaves in the pose every
		# other state has always drawn: no half-open wing, no leftover mirror, no
		# pixel of bob.
		_eat_flap_timer = 0.0
		_eat_turn_timer = 0.0
		_eat_wings_up = false
		facing_left = false
		queue_redraw()

	var speed: float = FLY_OUT_SPEED if state == "leaving" else FLY_IN_SPEED
	position = position.move_toward(sim_position(), minf(speed * delta, MAX_STEP))


# 3 tiles by default, read off the player node in pixels, exactly as before. The
# radius is also written down as a species sense (`SpeciesDefs.senses_of`), where
# WI-8c's rabbit becomes its second consumer and finding F-7b finally dies.
func _player_is_near() -> bool:
	if not is_instance_valid(player):
		# Resolved late as well as early: a farm renderer builds its sprites as
		# the registry gains actors, which can be before the farmer's node has
		# been added to the scene (M2.5 WI-6).
		player = farm.player_node() if farm != null and farm.has_method("player_node") else null
	if player == null:
		return false
	var sr = player.get("spook_radius")
	if sr == null:
		sr = SpeciesDefs.senses_of(SpeciesDefs.PLAYER).get("spook_radius", 3.0) * TILE_SIZE
	return position.distance_to(player.position) < float(sr)


# Q-10 juice + Q-12 proof: squawk and feathers on any scare; only a player-caused
# scare counts toward the capability proof, and it counts by being an Action.
func _report_scare() -> void:
	if _scared_reported:
		return
	_scared_reported = true
	# The farm's own state, not the `GameState` autoload: a second farm rendering
	# a second world (the attract loop) must never spend the player's real one —
	# the T-16 hazard, and now reachable from here because a crow can fly in a
	# farm nobody is playing (M2.5 WI-6).
	farm.apply_action({ "verb": "crow_scared", "actor": actor_id }, farm.state())
	_puff("squawk")
	# The report is what turned the bird around, so the departure it causes is
	# already announced — don't squawk twice for one fright.
	_last_state = _state()


# The visit ended for a reason the sim decided (a scarecrow, a finished perch, a
# mouthful) rather than one this node caused. Each has always had its own noise.
func _announce_departure(reason: String) -> void:
	match reason:
		# "bot": a shoo-bot walked it off (M2.5 WI-9). The same noise as her own
		# fright, because it is the same fright — what differs is who caused it,
		# and that difference is the sim's business (Q-12's proof) rather than the
		# feathers'.
		"scarecrow", "player", "bot":
			_puff("squawk")
		"perched":
			# T-2's mercy crow: it leaves empty-beaked, and the sim never heard
			# about this visit at all. One squawk, no feathers — it was not scared.
			_sfx("squawk")
		"ate":
			_sfx("till")


func _puff(sound: String) -> void:
	if get_tree():
		var main = get_tree().get_first_node_in_group("Main")
		if main and main.has_method("spawn_particles"):
			main.spawn_particles("feathers", position)
	_sfx(sound)


func _sfx(name: String) -> void:
	# A muted farm is one nobody is playing (the title screen's backdrop), and it
	# must not squawk into a menu — the same rule its tile feedback already keeps.
	if farm != null and farm.mute_feedback:
		return
	if get_tree() and get_tree().root.has_node("AudioManager"):
		get_tree().root.get_node("AudioManager").play_sfx(name)


# Which cell of the sheet this frame draws, named rather than worked out inline so
# a test can read the pose without a canvas (`bot.gd`'s idiom).
#
# crow.png cells: 0 perched, 1 wings up, 2 wings down. The meal alternates perched
# and wings-up, the two that share a standing body — the wings-down cell is a bird
# in flight and on the ground it reads as taking off. The flight keeps the two it
# has always flown with.
func cell_region() -> Rect2:
	var cell := 0
	if _state() == "eating":
		cell = 1 if _eat_wings_up else 0
	else:
		cell = 1 if flap_state == 0 else 2
	return Rect2(cell * 16, 0, 16, 16)


# How high off its tile this frame draws it: a pixel on the wings-up beat of the
# meal, nothing otherwise. Only ever non-zero while eating, because the flag is
# cleared the moment the state changes.
func bob_px() -> float:
	return EAT_BOB_PX if _eat_wings_up else 0.0


func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	render_queue.append({
		"y": position.y,
		"draw": func():
			var dest := Rect2(position.x - TILE_SIZE / 2.0,
				position.y - TILE_SIZE / 2.0 - bob_px(), TILE_SIZE, TILE_SIZE)
			if facing_left:
				# A negative width flips the cell, which is how a right-facing sheet
				# draws a bird that has turned to look the other way.
				dest = Rect2(dest.position.x + TILE_SIZE, dest.position.y,
					-TILE_SIZE, TILE_SIZE)
			canvas.draw_texture_rect_region(SPRITES, dest, cell_region())
	})

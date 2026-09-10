# workbench_eyes.gd — plate 2 of 5: what the robot can see, and what it decided
#
# **The page that answers "why did it do that?"** A Mark III decides from a flat
# list of numbers and nothing else (`systems/sim/observation.gd`), so the honest
# way to show its reasons is to show that list: the square of ground around it
# with each thing it can notice lit or dark, the five numbers it also carries,
# and the eight chances it weighed before it moved.
#
# **A snapshot, not a feed** (v0.2.2 ground rule 7). The world holds while a menu
# is open, so this page shows the robot's view at the moment she opened the bench.
# The policy is evaluated once per `show_robot` — a linear layer over ~200 numbers,
# well under a millisecond — and never per frame: `_draw` only reads what
# `show_robot` already worked out.
#
# **It reads and never writes.** `Observation.build` and `Policy.probs` are pure
# functions of layer 2, which is why a presentation file may call them; nothing
# here touches the robot's `extra`, and the bench's one write (a reward value)
# goes through the gateway from another page entirely.
#
# Geometry is the mockup's (`docs/design/mockups/workbench/workbench_eyes.png`),
# absolute against the game's fixed 800x600 screen — see `ui/workbench.gd` for why
# a page may write those numbers as they are written.
extends Control

# --- the patch ----------------------------------------------------------------
#
# Five cells of 68 with 4 between them, from the mockup. A robot with wider eyes
# than the one that ships gets more, smaller cells in the same square rather than
# a patch that grows off the page — the picture is "everything it can see", and
# that has to stay one shape whatever the radius is.
const PATCH_ORIGIN := Vector2(28, 192)
const PATCH_SPAN := 356.0        # 5 * 68 + 4 * 4
const CELL_GAP := 4.0
const CELL_REFERENCE := 68.0     # the cell the mark sizes below are drawn for

# A channel is a 10x10 mark, four to a row. Eight of them make two rows in the
# middle of the cell; a spec with fewer makes fewer rows, in the same place.
const MARK := 10.0
const MARK_GAP := 5.0
const MARK_COLUMNS := 4

# The key, in its own cell beside the patch: every mark lit, so a player can find
# out which square means water without tapping anything.
const LEGEND_RECT := Rect2(408, 192, 68, 68)

# --- the five numbers it carries besides the ground ---------------------------
const SCALAR_X := 407.0
const SCALAR_W := 154.0
const SCALAR_Y0 := 283.0
const SCALAR_H := 34.0
const SCALAR_STRIDE := 46.0
const SCALAR_GLYPH := 18.0
const VALUE_SIZE := 14

# --- the thinking strip -------------------------------------------------------
const STRIP_RECT := Rect2(577, 185, 196, 387)
const BAR_X0 := 587.0
const BAR_W := 16.0
const BAR_STRIDE := 24.0
const BAR_TOP := 202.0           # a bar at 100%
const BAR_BASE := 502.0          # the line they all stand on
const GLYPH_Y := 506.0
const GLYPH_SIZE := 16.0
const ENTROPY_RECT := Rect2(587, 550, 184, 10)

# --- inks ---------------------------------------------------------------------
#
# The channel colours are the bench's (`Workbench.CHANNEL_COLOURS`), so a blue
# square here is the same blue as the row it feeds on the ledger. What is left is
# the furniture: a tile face, a darker face for ground that is not there, and the
# grey a bar is drawn in before it is the one that was chosen.
const TILE_FACE := Color("2a2a3a")
const TILE_OFF := Color("1a1a24")
const CARD_FACE := Color("2b2b3c")
const TILE_EDGE := Color(0.62, 0.64, 0.74, 0.14)
const MARK_OFF_ALPHA := 0.16
const BAR_INK := Color(0.55, 0.58, 0.70, 0.75)
const TRACK_INK := Color(0.62, 0.64, 0.74, 0.16)

## The farm to read through, and the robot to read. `""` means the player owns no
## learning robot, and the page draws its empty state.
var farm: Node2D = null
var actor_id: String = ""

## The patch as the robot's own vector has it: one entry per tile of the
## `(2r+1)²` square, row-major from the top-left corner, each entry the channels
## of that tile in the spec's own order. Twenty-five entries of eight for the spec
## that ships. Exposed because it is what the page is claiming on screen, and a
## test that could only read pixels could not tell a right picture from a wrong one.
var patch: Array = []

## What the robot would decide from that view: eight chances, summing to one.
## Empty when the robot has no policy to evaluate.
var probs: Array = []

## The numbers it carries that are not about the ground: where it is, how much
## energy is left, whether its hands are full, how much is in her seed box, and
## which way the bin is. Denormalised back to what they mean — the vector holds
## them as fractions, and a fraction is not a thing a player can read.
var scalars: Dictionary = {}

# What `show_robot` worked out, kept for `_draw` rather than recomputed in it.
var _spec: Dictionary = {}
var _channels: Array = []
var _radius: int = 0
var _last_action: int = -1
var _entropy: float = 0.0
var _portrait: Texture2D = null


## Point the page at a robot, and think its thought once.
##
## Everything expensive on this page happens here: one observation built, one
## linear layer evaluated. Both are pure reads of the sim, and the world is paused
## behind the bench, so what comes out is exactly what the robot saw at the moment
## she opened it.
func show_robot(farm_node: Node2D, id: String) -> void:
	farm = farm_node
	actor_id = id
	patch = []
	probs = []
	scalars = {}
	_spec = {}
	_channels = []
	_radius = 0
	_last_action = -1
	_entropy = 0.0
	_portrait = null
	if farm != null and id != "" and farm.get("sim") != null and farm.sim.has_actor(id):
		var extra: Dictionary = farm.sim.actor(id).get("extra", {})
		# A learner always carries both (`SimWorld.learners()` is defined by the
		# weights), but a page that crashed on a robot with an odd record would
		# take the whole bench down with it, so the missing case reads as a spec
		# with no policy behind it rather than as an error.
		_spec = extra.get("spec", Observation.spec_default())
		_channels = _spec.get("channels", Observation.CHANNELS)
		_radius = maxi(0, int(_spec.get("vision", Observation.DEFAULT_VISION)))
		_last_action = int(extra.get("last_action", -1))
		_portrait = MachineDefs.icon_of(_model_of(id))

		var obs: Array = Observation.build(farm.sim, id, _spec, GameState)
		var n_in: int = Observation.size(_spec)
		var weights: Array = extra.get("weights", [])
		if weights.size() == BotBrain.LEARN_ACTIONS * (n_in + 1):
			probs = Policy.probs(
				Policy.logits(weights, n_in, BotBrain.LEARN_ACTIONS, obs))
			_entropy = Policy.entropy_bits(probs)
		_read_vector(obs)
	queue_redraw()


# The vector, cut back into the things it is made of.
#
# **The layout is asked for, never re-derived.** `Observation.input_groups` says
# which slots of the vector are which channel of which tile and which are the
# scalars; a second copy of that arithmetic in a drawing file is a picture that
# goes quietly wrong the day a spec grows a channel (the same rule the mosaic is
# built on).
func _read_vector(obs: Array) -> void:
	var groups: Array = Observation.input_groups(_spec)
	var nch: int = _channels.size()
	var side: int = 2 * _radius + 1
	for t in side * side:
		var tile: Array = []
		for k in nch:
			var indices: Array = groups[k].get("indices", [])
			tile.append(float(obs[int(indices[t])]) if t < indices.size() else 0.0)
		patch.append(tile)

	# The head of the vector, by name. Each is turned back into the number it
	# stands for: energy out of a full meter, seeds out of "plenty", the bin's
	# offset out of the page it was divided by.
	var at: Vector2i = farm.sim.actor_pos(actor_id)
	for gi in range(nch, groups.size()):
		var group: Dictionary = groups[gi]
		var indices: Array = group.get("indices", [])
		match String(group.get("name", "")):
			"position":
				scalars["x"] = at.x
				scalars["y"] = at.y
			"energy":
				scalars["energy"] = int(round(
					float(obs[int(indices[0])]) * float(SimWorld.ACTOR_MAX_ENERGY)))
			"carrying":
				scalars["carrying"] = float(obs[int(indices[0])])
			"seeds":
				scalars["seeds"] = int(round(
					float(obs[int(indices[0])]) * Observation.SEEDS_FULL))
			"bin":
				# The two offsets were divided by different numbers — the map's
				# width and one page's height — so they are multiplied back before
				# either the arrow or the distance is taken from them. A direction
				# read off the raw fractions would point at the wrong corner of the
				# farm on a tall map.
				var dx: int = int(round(
					float(obs[int(indices[0])]) * float(SimWorld.MAP_WIDTH)))
				var dy: int = int(round(
					float(obs[int(indices[1])]) * float(SimWorld.PAGE_ROWS)))
				scalars["bin_dx"] = dx
				scalars["bin_dy"] = dy
				scalars["bin_distance"] = absi(dx) + absi(dy)


# Which robot this is, for its portrait. The shell works this out too but keeps it
# private, and a page may not edit the shell — so it is re-derived here, from the
# same two places (`extra["model"]`, then the registry's own key).
func _model_of(id: String) -> String:
	var extra: Dictionary = farm.sim.actor(id).get("extra", {})
	var model := String(extra.get("model", ""))
	if model != "":
		return model
	return String(farm.sim.machine_key_of(id))


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if actor_id == "" or patch.is_empty():
		Workbench.draw_empty_dash(self)
		return
	_draw_patch()
	_draw_legend()
	_draw_scalars()
	_draw_thinking()


# The ground around it, one cell per tile.
#
# A tile off the edge of the map is a dash on a darker face: the vector reads it
# as all zeros, and eight dark marks would say "nothing here is true", which a
# player would fairly read as "nothing here is happening" — a farm, not a void.
func _draw_patch() -> void:
	var side: int = 2 * _radius + 1
	var cell: float = (PATCH_SPAN - CELL_GAP * float(side - 1)) / float(side)
	var at: Vector2i = farm.sim.actor_pos(actor_id)
	for dy in side:
		for dx in side:
			var origin := PATCH_ORIGIN + Vector2(float(dx), float(dy)) * (cell + CELL_GAP)
			var rect := Rect2(origin, Vector2(cell, cell))
			var tx: int = at.x + dx - _radius
			var ty: int = at.y + dy - _radius
			if tx < 0 or tx >= SimWorld.MAP_WIDTH or ty < 0 or ty >= SimWorld.MAP_HEIGHT:
				draw_rect(rect, TILE_OFF)
				draw_rect(Rect2(origin + Vector2(cell * 0.29, cell * 0.47),
					Vector2(cell * 0.42, maxf(3.0, cell * 0.09))), Workbench.INK_DIM)
				continue
			draw_rect(rect, TILE_FACE)
			draw_rect(rect, TILE_EDGE, false, 1.0)
			if dx == _radius and dy == _radius:
				# The middle of the patch is the robot itself. Its own square's
				# channels are in `patch` like every other tile's — this is the one
				# cell where the picture is worth more than the eight marks, because
				# "this is you, and everything around it is what you see" is the
				# whole sentence the page is trying to say.
				draw_rect(rect, Workbench.BRASS_LIT, false, 2.0)
				if _portrait != null:
					draw_texture_rect(_portrait,
						Rect2(origin + Vector2(cell * 0.12, cell * 0.12),
							Vector2(cell, cell) * 0.76), false)
				continue
			_draw_marks(origin, cell, patch[dy * side + dx])


# One tile's channels. Lit is the channel's own colour at full strength; unlit is
# the same colour at a whisper, so an empty square still says *which* eight things
# it is empty of.
func _draw_marks(origin: Vector2, cell: float, values: Array) -> void:
	for k in _channels.size():
		var colour: Color = Workbench.CHANNEL_COLOURS.get(String(_channels[k]), Workbench.INK)
		var lit: bool = k < values.size() and float(values[k]) >= 0.5
		var rect := _mark_rect(origin, cell, k)
		draw_rect(rect, colour if lit else Color(colour, MARK_OFF_ALPHA))
		if k == _highlight():
			# The mosaic has asked for one channel to be findable. An outline
			# rather than a colour change: the colour is the channel's name here,
			# and a page that recoloured it to mean "this one" would be saying two
			# things with one ink.
			draw_rect(rect.grow(2.0), Workbench.INK, false, 2.0)


func _mark_rect(origin: Vector2, cell: float, k: int) -> Rect2:
	var unit: float = cell / CELL_REFERENCE
	var m: float = MARK * unit
	var g: float = MARK_GAP * unit
	var rows: int = int(ceil(float(_channels.size()) / float(MARK_COLUMNS)))
	var block := Vector2(
		float(MARK_COLUMNS) * m + float(MARK_COLUMNS - 1) * g,
		float(rows) * m + float(rows - 1) * g)
	var corner := origin + (Vector2(cell, cell) - block) / 2.0
	return Rect2(corner + Vector2(float(k % MARK_COLUMNS), float(k / MARK_COLUMNS)) * (m + g),
		Vector2(m, m))


# The channel the mosaic asked the eyes to outline, or -1. It lives on the shell
# because it is a conversation between two pages; a page opened on its own (a
# capture tool, a test) has no shell and simply has no highlight.
func _highlight() -> int:
	var bench := get_parent() as Workbench
	return bench.highlight_channel if bench != null else -1


# The key: one cell with everything lit, in the same order the tiles use.
func _draw_legend() -> void:
	draw_rect(LEGEND_RECT, TILE_FACE)
	draw_rect(LEGEND_RECT, Workbench.BRASS_LIT, false, 2.0)
	var all_lit: Array = []
	for k in _channels.size():
		all_lit.append(1.0)
	_draw_marks(LEGEND_RECT.position, LEGEND_RECT.size.x, all_lit)


# --- the five numbers ---------------------------------------------------------

func _draw_scalars() -> void:
	var row := 0
	if scalars.has("x"):
		var r := _scalar_card(row)
		_draw_crosshair(Vector2(r.position.x + 8.0, r.position.y + 8.0), SCALAR_GLYPH)
		_value("%d, %d" % [int(scalars["x"]), int(scalars["y"])], r)
		row += 1
	if scalars.has("energy"):
		var r := _scalar_card(row)
		_draw_bolt(Vector2(r.position.x + 8.0, r.position.y + 8.0), SCALAR_GLYPH)
		_track(r, float(scalars["energy"]) / float(SimWorld.ACTOR_MAX_ENERGY))
		_value(str(int(scalars["energy"])), r)
		row += 1
	if scalars.has("carrying"):
		var r := _scalar_card(row)
		var full: bool = float(scalars["carrying"]) >= 0.5
		if full:
			# Its hands, said with the picture the scorecard already uses for a cut
			# crop — one basket on the whole bench, meaning one thing.
			BotScorecard.draw_pip(self, "harvested",
				Vector2(r.position.x + 8.0, r.position.y + 8.0), SCALAR_GLYPH,
				BotScorecard.LINE_COLOURS["harvested"])
		else:
			draw_rect(Rect2(r.position.x + 9.0, r.position.y + 9.0,
				SCALAR_GLYPH - 2.0, SCALAR_GLYPH - 2.0), Workbench.INK_DIM, false, 2.0)
		_track(r, 1.0 if full else 0.0)
		_value("1" if full else "0", r)
		row += 1
	if scalars.has("seeds"):
		var r := _scalar_card(row)
		Workbench.draw_action_glyph(self, BotBrain.LEARN_PLANT,
			Vector2(r.position.x + 8.0, r.position.y + 8.0), SCALAR_GLYPH)
		_track(r, float(scalars["seeds"]) / Observation.SEEDS_FULL)
		_value(str(int(scalars["seeds"])), r)
		row += 1
	if scalars.has("bin_distance"):
		var r := _scalar_card(row)
		Workbench.draw_action_glyph(self, BotBrain.LEARN_SHIP,
			Vector2(r.position.x + 8.0, r.position.y + 8.0), SCALAR_GLYPH)
		# **A direction, not a bar.** The bin is usually far outside the patch, so
		# what the robot is carrying about it is "that way, this far" — an arrow
		# and a count say that; a bar of some fraction of the map would not.
		_draw_arrow(Vector2(r.position.x + 44.0, r.position.y + SCALAR_H / 2.0),
			Vector2(float(scalars["bin_dx"]), float(scalars["bin_dy"])), 14.0)
		_value(str(int(scalars["bin_distance"])), r)


func _scalar_card(row: int) -> Rect2:
	var r := Rect2(SCALAR_X, SCALAR_Y0 + SCALAR_STRIDE * float(row), SCALAR_W, SCALAR_H)
	draw_rect(r, CARD_FACE)
	draw_rect(r, TILE_EDGE, false, 1.0)
	return r


func _track(card: Rect2, fraction: float) -> void:
	var track := Rect2(card.position.x + 34.0, card.position.y + SCALAR_H / 2.0 - 3.0,
		62.0, 6.0)
	draw_rect(track, TRACK_INK)
	draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(fraction, 0.0, 1.0),
		track.size.y)), Workbench.CHANNEL_COLOURS["walkable"])


func _value(text: String, card: Rect2) -> void:
	_numeral(text, Vector2(card.end.x - 8.0, card.position.y + SCALAR_H / 2.0 + 5.0),
		1, VALUE_SIZE, Workbench.INK)


# Where it is standing: two crossing lines and a dot, which is the plainest thing
# that could mean a coordinate.
func _draw_crosshair(at: Vector2, size: float) -> void:
	var c := at + Vector2(size, size) / 2.0
	var arm := size * 0.42
	draw_line(Vector2(c.x - arm, c.y), Vector2(c.x + arm, c.y), Workbench.INK_DIM, 2.0)
	draw_line(Vector2(c.x, c.y - arm), Vector2(c.x, c.y + arm), Workbench.INK_DIM, 2.0)
	draw_circle(c, size * 0.16, Workbench.CHANNEL_COLOURS["bin"])


# Its energy: a bolt, the one picture the HUD already uses for a meter running down.
func _draw_bolt(at: Vector2, size: float) -> void:
	var s := size
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(s * 0.55, s * 0.05), at + Vector2(s * 0.22, s * 0.55),
		at + Vector2(s * 0.45, s * 0.55), at + Vector2(s * 0.35, s * 0.95),
		at + Vector2(s * 0.78, s * 0.42), at + Vector2(s * 0.52, s * 0.42),
	]), Workbench.BRASS_LIT)


func _draw_arrow(centre: Vector2, offset: Vector2, length: float) -> void:
	var dir := offset.normalized() if offset.length() > 0.0001 else Vector2(1, 0)
	var tip := centre + dir * length
	var tail := centre - dir * length
	draw_line(tail, tip, Workbench.CHANNEL_COLOURS["bin"], 2.0)
	var side := Vector2(-dir.y, dir.x)
	var head := length * 0.45
	draw_colored_polygon(PackedVector2Array([
		tip, tip - dir * head + side * head * 0.7, tip - dir * head - side * head * 0.7,
	]), Workbench.CHANNEL_COLOURS["bin"])


# --- what it decided ----------------------------------------------------------
#
# Eight bars, one per thing it can do, at the chance it gave each of them — and
# the one it actually took lit. **Nothing is lit at -1**, which is a robot that
# has not decided anything yet: a lit bar there would be the page inventing a
# decision the robot never made.
func _draw_thinking() -> void:
	draw_rect(STRIP_RECT, Color(0.106, 0.106, 0.157))
	draw_rect(STRIP_RECT, TILE_EDGE, false, 1.0)
	var span := BAR_BASE - BAR_TOP
	for a in BotBrain.LEARN_ACTIONS:
		var p: float = float(probs[a]) if a < probs.size() else 0.0
		var x := BAR_X0 + BAR_STRIDE * float(a)
		var h: float = maxf(2.0, span * clampf(p, 0.0, 1.0))
		var bar := Rect2(x, BAR_BASE - h, BAR_W, h)
		var lit: bool = a == _last_action
		draw_rect(bar, Workbench.BRASS_LIT if lit else BAR_INK)
		if lit:
			draw_rect(bar.grow(2.0), Workbench.BRASS_LIT, false, 2.0)
		_numeral(str(int(round(p * 100.0))), Vector2(x + BAR_W / 2.0, bar.position.y - 4.0),
			0, BotScorecard.NUMERAL_SIZE, Workbench.INK if lit else BotScorecard.AXIS_INK)
		Workbench.draw_action_glyph(self, a,
			Vector2(x + BAR_W / 2.0 - GLYPH_SIZE / 2.0, GLYPH_Y), GLYPH_SIZE)

	# **How undecided it was**, in bits, against the most it could be — three bits
	# is eight actions it cannot tell apart, and a bar creeping down from there is
	# a robot making its mind up. Both ends carry a numeral because neither number
	# means anything without the other.
	var ceiling: float = log(float(BotBrain.LEARN_ACTIONS)) / log(2.0)
	draw_rect(ENTROPY_RECT, TRACK_INK)
	draw_rect(Rect2(ENTROPY_RECT.position,
		Vector2(ENTROPY_RECT.size.x * clampf(_entropy / ceiling, 0.0, 1.0),
			ENTROPY_RECT.size.y)), Workbench.INK)
	var below := ENTROPY_RECT.end.y + BotScorecard.NUMERAL_SIZE + 2.0
	_numeral("%.2f" % _entropy, Vector2(ENTROPY_RECT.position.x, below), -1,
		BotScorecard.NUMERAL_SIZE, Workbench.INK)
	_numeral("%.2f" % ceiling, Vector2(ENTROPY_RECT.end.x, below), 1,
		BotScorecard.NUMERAL_SIZE, BotScorecard.AXIS_INK)


# A number, aligned left (-1), centred (0) or right (1) on `at`. The scorecard's
# own numeral, made to take an alignment: the bench puts numbers under bars and at
# the right-hand end of cards, and the panel only ever needed two of the three.
func _numeral(text: String, at: Vector2, align: int, size: int, ink: Color) -> void:
	var f := get_theme_font("font", "Label")
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = at.x
	if align == 0:
		x -= w / 2.0
	elif align > 0:
		x -= w
	draw_string(f, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)

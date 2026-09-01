# zoo_scent_overlay.gd — the pest trail, made visible (T-33)
#
# A raid is the one mechanic in the game whose whole substance is invisible: the
# scout's payload is a *field*, and without a way to see it the column reads as
# three ants walking in a suspiciously straight line for no reason. So the zoo can
# tint the trail, in **magenta** — `design/09`'s reserved pest-pheromone hue, which
# exists precisely because no ambient tile in the game is that colour.
#
# **Zoo-only.** Q-17 asks when (and whether) the player is ever taught the overlay,
# and this is not that: it is a debug tint behind a debug door, and it draws the
# raw channel value rather than anything a design has chosen to say.
#
# **It never scans the map** — P-10's guardrail, which binds a debug surface too
# (a per-frame 640-tile sweep on the tablet would be the first thing anybody
# noticed). The tile list is the scent field's *written cells*, read through
# `Scent.to_save()` and refreshed on a throttle; the per-frame work is one
# `Scent.read()` per marked tile, which is a `pow()` each and is O(marks). A farm
# nobody has walked on costs an empty dictionary.
#
# It draws through the farm's own render queue rather than as a node above it: a
# child of `farm.actors_node` with a `queue_render()` is picked up by
# `world/farm.gd:_draw`, and a `y` below every real entry puts the tint under the
# ants that laid it instead of over them. That is also why `world/farm.gd` needed
# no change to carry this.
extends Node2D

# Under everything: the render queue sorts by `y`, and real entries are tile pixel
# coordinates, which are never negative.
const UNDER_EVERYTHING := -1000000.0

const CHANNEL := Scent.TRAIL

# `design/09`: magenta is reserved for the pest pheromone and appears nowhere in
# the ambient palette, so a tinted tile reads instantly against grass or soil.
const TINT := Color(0.98, 0.15, 0.85)
const ALPHA_MIN := 0.14
const ALPHA_MAX := 0.62

# What counts as "as strong as it gets" for the tint, in channel units. **Not the
# channel's cap** (100): a scout lays `AntScoutBrain.DEPOSIT` = 10 per tile and a
# forager reinforces by 6, so a real raid's trail lives in the teens and scaling
# against the cap would draw the whole thing at the palest alpha there is. Two and
# a bit deposits is the top of the range you can actually watch. [Playtest].
const STRONG := 24.0

# How often the *list* of marked tiles is rebuilt, in seconds. The values decay
# every frame and are read every frame; which tiles exist changes only when
# somebody deposits on a new one or washes an old one away, and a fifth of a
# second late on that is invisible.
const REFRESH_SECONDS := 0.2

var farm: Node2D = null
var enabled := false

var _tiles: Array[Vector2i] = []
var _timer := 0.0

# How many times the tint block has run to completion. A draw callback that throws
# part way through prints a red line and fails nothing, so a test's witness has to
# be a counter incremented at the *end* — Scenario X's pattern.
var draws := 0


func init_overlay(farm_ref: Node2D) -> void:
	farm = farm_ref
	_refresh()


## The tiles the tint currently knows about — the field's written cells as of the
## last refresh, which is the whole of what this node scans.
func marked() -> Array[Vector2i]:
	return _tiles


func _process(delta: float) -> void:
	if not enabled or farm == null:
		return
	_timer += delta
	if _timer < REFRESH_SECONDS:
		return
	_timer = 0.0
	_refresh()


# The written cells, from the field's own serialization — flat `[x, y, value,
# tick, ...]` quads, which is the only enumeration `Scent` offers and is O(marks)
# rather than O(map). Deliberately not a new accessor on the sim: T-33 may consume
# the sim, not grow it, and this was already enough.
func _refresh() -> void:
	_tiles.clear()
	if farm == null or farm.sim == null:
		return
	var flat = farm.sim.scent.to_save().get(CHANNEL, [])
	if typeof(flat) != TYPE_ARRAY:
		return
	var i := 0
	while i + 3 < flat.size():
		_tiles.append(Vector2i(int(flat[i]), int(flat[i + 1])))
		i += 4


# One render-queue entry for the whole overlay, not one per tile: the queue is
# sorted every frame and N dictionaries a frame is a cost the tint does not need.
func queue_render(canvas: CanvasItem, render_queue: Array) -> void:
	if not enabled or _tiles.is_empty() or farm == null:
		return
	var tiles := _tiles
	var scent = farm.sim.scent
	var tick: int = farm.sim.clock.tick
	var full := STRONG
	render_queue.append({
		"y": UNDER_EVERYTHING,
		"draw": func():
			for t in tiles:
				var v: float = scent.read(CHANNEL, t, tick)
				if v <= 0.0:
					continue
				var a: float = ALPHA_MIN + (ALPHA_MAX - ALPHA_MIN) * minf(1.0, v / full)
				canvas.draw_rect(
					Rect2(t.x * 16, t.y * 16, 16, 16),
					Color(TINT.r, TINT.g, TINT.b, a))
			draws += 1
	})

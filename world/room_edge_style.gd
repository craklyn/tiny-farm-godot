# room_edge_style.gd — how the thin boundary of an edge-walled room is drawn
#
# The Spiral Tower's room keeps every cell walkable and draws its boundary on the
# cells' outer edge (design/15 §3, §4a). Until 2026-09-29 that boundary was a 2px
# grey line. Daniel asked for "visual styles for creating a barrier separating an
# indoor from an outdoor space that doesn't take up a tile (just narrowly around
# the perimeter)", and the four candidates below are that ask, pending his pick
# (the decision card is Q-135; captures in docs/design/mockups/thin_walls/).
#
# **Presentation only.** Nothing here reads or writes the sim beyond the room's
# rectangle and its door, and nothing is saved: the VOID around the room is still
# what blocks movement. Changing the style changes pixels and nothing else.
#
# **Every style lives in a narrow band on the edge.** In room pixels (one pixel of
# the floor's own art): one pixel over the floor and two or three over the yard
# beyond it, a one-pixel cast shadow on the floor under the north and west runs,
# and door posts that stand one pixel taller. A cell is sixteen of these pixels, so
# no style ever covers a square.
#
# **Irregular, never periodic** (design/09: a repeat the eye can predict reads as
# wallpaper). Stone lengths, post spacing, hedge clumps and plaster chips all come
# from `CropPresentation.hash01` of the pixel's position along its own edge — pure,
# so a screenshot and a replay land on the same wall, with no beat in it.
#
# **The doorway is framed, not merely skipped.** Each style ends the south run on
# either side of the door with a heavier piece — a jamb stone, a post, a rounded
# hedge end, a plaster pillar — so the gap reads as a way through rather than as a
# missing stretch of wall.
#
# **Switching without a code edit.** `current()` is the one read. `override` is
# for capture tools (`tools/capture_thin_walls.gd`); `--room-edge=<style>` after
# `--` on the command line picks one for a play session, e.g.
#   godot --path . -- --room-edge=stone
# The default stays the plain line, so nothing changes for players until the pick.
class_name RoomEdgeStyle
extends RefCounted

const STYLES := ["plain", "stone", "timber", "hedge", "plaster"]
const DEFAULT := "plain"

## Set by a capture tool; empty means "use the command line, then the default".
static var override := ""
static var _from_cmdline := "?"

# Colours are the shipped sprites' own (design/09's measured anchors): the tower's
# stone ramp, the fence's and coop's browns, the hedge's greens, the farmhouse's
# plaster.
const PLAIN_INK := Color("6f6862")
const SHADOW := Color(0.16, 0.10, 0.08, 0.28)

const STONE_HI := Color("dcd4c7")
const STONE_TONES := [Color("b0ab9e"), Color("bdb8ab"), Color("95918a")]
const STONE_LO := Color("727676")
const STONE_MORTAR := Color("445457")

const WOOD_HI := Color("c39a6c")
const WOOD := Color("a97959")
const WOOD_LO := Color("90625d")
const WOOD_DARK := Color("6f4a45")

const LEAF_HI := Color("8db15d")
const LEAF_MID := Color("78a158")
const LEAF := Color("4e6e3a")
const LEAF_LO := Color("3d6e2a")
const LEAF_DARK := Color("2a6022")

const PLASTER_HI := Color("f9f4e5")
const PLASTER := Color("efe4cf")
const PLASTER_LO := Color("b48968")
const PLASTER_STAIN := Color("dcd4c7")
const PLASTER_BRICK := Color("bd936a")


static func current() -> String:
	if override in STYLES:
		return override
	if _from_cmdline == "?":
		_from_cmdline = ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--room-edge="):
				var s := arg.trim_prefix("--room-edge=")
				if s in STYLES:
					_from_cmdline = s
	return _from_cmdline if _from_cmdline != "" else DEFAULT


## Draw the boundary of `box` (room pixels) with a one-cell doorway on its south
## edge starting at `gap_x`, `gap_w` wide.
static func draw(canvas: CanvasItem, box: Rect2, gap_x: float, gap_w: float,
		style: String = "") -> void:
	if style == "":
		style = current()
	if style not in STYLES or style == "plain":
		_draw_plain(canvas, box, gap_x, gap_w)
		return
	for piece in pieces(box, gap_x, gap_w, style):
		canvas.draw_rect(piece[0], piece[1])


# The last room's pieces, kept: the wall is a pure function of the room's rectangle,
# its door and the style, so it is built once per room rather than every frame.
static var _cache_key := ""
static var _cache: Array = []

## Every rectangle a style draws, as [Rect2, Color] pairs in painting order. Pure:
## the same room, door and style always give the same list (the unit suite holds
## each style to its band with it). Empty for the plain line, which is lines.
static func pieces(box: Rect2, gap_x: float, gap_w: float, style: String) -> Array:
	var key := "%s|%s|%s|%s" % [style, str(box), gap_x, gap_w]
	if key == _cache_key:
		return _cache
	var out: Array = []
	match style:
		"stone":
			_draw_style(out, box, gap_x, gap_w, 3, 1, _stone_run, _stone_jamb)
		"timber":
			_draw_style(out, box, gap_x, gap_w, 3, 1, _timber_run, _timber_jamb)
		"hedge":
			_draw_style(out, box, gap_x, gap_w, 3, 1, _hedge_run, _hedge_jamb)
		"plaster":
			_draw_style(out, box, gap_x, gap_w, 2, 1, _plaster_run, _plaster_jamb)
	_cache_key = key
	_cache = out
	return out


# Today's line, unchanged: 2px, centred on the edge.
static func _draw_plain(canvas: CanvasItem, box: Rect2, gap_x: float, gap_w: float) -> void:
	canvas.draw_line(box.position, Vector2(box.end.x, box.position.y), PLAIN_INK, 2.0)
	canvas.draw_line(box.position, Vector2(box.position.x, box.end.y), PLAIN_INK, 2.0)
	canvas.draw_line(Vector2(box.end.x, box.position.y), box.end, PLAIN_INK, 2.0)
	canvas.draw_line(Vector2(box.position.x, box.end.y), Vector2(gap_x, box.end.y), PLAIN_INK, 2.0)
	canvas.draw_line(Vector2(gap_x + gap_w, box.end.y), box.end, PLAIN_INK, 2.0)


# The shared layout. A *run* is one straight stretch of band, described in its own
# frame: `u` along the edge, `v` across it with 0 at the band's top/left side (so
# the light, from the top-left, always lands on small `v`). `side` keys the hash,
# so the four edges never share a sequence.
static func _draw_style(out: Array, box: Rect2, gap_x: float, gap_w: float,
		outside: int, inside: int, run: Callable, jamb: Callable) -> void:
	var x0 := int(box.position.x)
	var y0 := int(box.position.y)
	var x1 := int(box.end.x)
	var y1 := int(box.end.y)
	var t := outside + inside
	var gx := int(gap_x) - x0
	var gw := int(gap_w)
	# The cast shadow, on the floor below the north run and right of the west.
	out.append([Rect2(x0 + inside, y0 + inside, x1 - x0 - inside * 2, 1), SHADOW])
	out.append([Rect2(x0 + inside, y0 + inside + 1, 1, y1 - y0 - inside * 2 - 1), SHADOW])
	# West and east first, between the north and south runs' ends, so the
	# horizontal runs sit over the corners.
	run.call(out, false, Vector2i(x0 - outside, y0 + inside), 0, y1 - y0 - inside * 2, t, 1)
	run.call(out, false, Vector2i(x1 - inside, y0 + inside), 0, y1 - y0 - inside * 2, t, 2)
	run.call(out, true, Vector2i(x0 - outside, y0 - outside), 0, x1 - x0 + outside * 2, t, 0)
	run.call(out, true, Vector2i(x0 - outside, y1 - inside), 0, gx + outside, t, 3)
	run.call(out, true, Vector2i(x0 + gx + gw, y1 - inside), gx + gw + outside,
		x1 - x0 - gx - gw + outside, t, 3)
	# The door posts: one pixel taller than the run, which in this view is one
	# pixel further up the screen — the only place any style reaches two pixels
	# over the floor — and never wider than the stretch of wall they end.
	jamb.call(out, _post_rect(x0 + gx, y1 - inside, t, -1, gx + outside, 5), -1)
	jamb.call(out, _post_rect(x0 + gx + gw, y1 - inside, t, 1,
		x1 - x0 - gx - gw + outside, 5), 1)


static func _post_rect(x: int, y: int, t: int, dir: int, avail: int, w: int) -> Rect2i:
	w = mini(w, avail)
	return Rect2i(x - w if dir < 0 else x, y - 1, w, t + 1)


# A shaded block: lit top row, dark right column and bottom row.
static func _block(out: Array, b: Rect2i, fill: Color, hi: Color, lo: Color) -> void:
	out.append([Rect2(b), fill])
	out.append([Rect2(b.position.x, b.position.y, b.size.x, 1), hi])
	out.append([Rect2(b.end.x - 1, b.position.y + 1, 1, b.size.y - 1), lo])
	out.append([Rect2(b.position.x, b.end.y - 1, b.size.x, 1), lo])


# One rectangle in a run's frame, placed in room pixels.
static func _r(out: Array, horiz: bool, o: Vector2i, u: int, v: int,
		du: int, dv: int, c: Color) -> void:
	if du <= 0 or dv <= 0:
		return
	if horiz:
		out.append([Rect2(o.x + u, o.y + v, du, dv), c])
	else:
		out.append([Rect2(o.x + v, o.y + u, dv, du), c])


# Where a piece that stands a pixel proud of the band goes, in the run's `v`:
# always away from the floor (north and west runs: before the band; east and
# south: after it), so nothing proud ever lands on a square.
static func _proud_v(_horiz: bool, side: int, t: int) -> int:
	return -1 if side <= 1 else t


# A number in [0, 1) for position `u` of edge `side`; `seed` names which draw.
static func _h(u: int, side: int, seed: int) -> float:
	return CropPresentation.hash01(Vector2i(u, side * 997 + 13), seed)


# The pieces of a run, `min_len..max_len` long each, cut where the hash says.
# `key0` is where this run starts in its edge's own sequence, so the two halves of
# the south wall continue one sequence rather than restarting it.
static func _pieces(length: int, key0: int, side: int, min_len: int, max_len: int) -> Array:
	var out: Array = []
	var u := 0
	while u < length:
		var n := min_len + int(_h(key0 + u, side, 1) * float(max_len - min_len + 1))
		if length - u - n < min_len:
			n = length - u     # never leave a sliver at the end
		out.append(Vector2i(u, n))
		u += n
	return out


# --- Stone: a low dry-stone course in the tower's own greys -------------------

static func _stone_run(out: Array, horiz: bool, o: Vector2i, key0: int,
		length: int, t: int, side: int) -> void:
	for p: Vector2i in _pieces(length, key0, side, 3, 6):
		var u: int = p.x
		var n: int = p.y - 1           # one pixel of mortar after each stone
		var k := key0 + u
		# Some stones sit a pixel lower or stand a pixel proud of the course, so
		# the silhouette wanders the way laid stone does.
		var top := 1 if _h(k, side, 2) < 0.28 else 0
		var bot := 1 if _h(k, side, 3) < 0.22 else 0
		var tone: Color = STONE_TONES[int(_h(k, side, 4) * 3.0)]
		_r(out, horiz, o, u + n, 1, 1, t - 2, STONE_MORTAR)
		_r(out, horiz, o, u, top, n, t - top - bot, tone)
		_r(out, horiz, o, u, top, n - 1, 1, STONE_HI)
		_r(out, horiz, o, u, t - bot - 1, n, 1, STONE_LO)
		_r(out, horiz, o, u + n - 1, top + 1, 1, t - top - bot - 2, STONE_LO)


static func _stone_jamb(out: Array, b: Rect2i, _dir: int) -> void:
	# One big squared stone either side of the door.
	_block(out, b, STONE_TONES[0], STONE_HI, STONE_MORTAR)
	out.append([Rect2(b.position.x, b.end.y - 2, b.size.x - 1, 1), STONE_LO])


# --- Timber: a post-and-rail in the fence's browns ----------------------------

static func _timber_run(out: Array, horiz: bool, o: Vector2i, key0: int,
		length: int, t: int, side: int) -> void:
	# The rail: two pixels through the middle of the band.
	var rv := 1
	_r(out, horiz, o, 0, rv, length, 1, WOOD_HI)
	_r(out, horiz, o, 0, rv + 1, length, 1, WOOD_LO)
	# Grain: a darker streak on the rail's lit face here and there.
	for p: Vector2i in _pieces(length, key0, side, 4, 9):
		if _h(key0 + p.x, side, 5) < 0.45:
			_r(out, horiz, o, p.x + 1, rv, 2, 1, WOOD)
	# Posts at the ends and at irregular steps between. A post is the band's
	# full depth plus, sometimes, a pixel more.
	var posts: Array = [0]
	var u := 0
	while true:
		u += 8 + int(_h(key0 + u, side, 6) * 7.0)
		if u > length - 7:
			break
		posts.append(u)
	posts.append(length - 3)
	for pu: int in posts:
		var proud := 1 if _h(key0 + pu, side, 7) < 0.35 else 0
		_timber_post(out, horiz, o, pu, t, proud if _proud_v(horiz, side, t) < 0 else 0)


static func _timber_post(out: Array, horiz: bool, o: Vector2i, u: int,
		t: int, proud: int) -> void:
	_r(out, horiz, o, u, -proud, 3, t + proud, WOOD)
	_r(out, horiz, o, u, -proud, 3, 1, WOOD_HI)
	_r(out, horiz, o, u + 2, -proud + 1, 1, t + proud - 1, WOOD_DARK)
	_r(out, horiz, o, u, t - 1, 2, 1, WOOD_DARK)


static func _timber_jamb(out: Array, b: Rect2i, _dir: int) -> void:
	# The gate posts: wider than the rest.
	_block(out, b, WOOD, WOOD_HI, WOOD_DARK)


# --- Hedge: a clipped hedge in the boundary hedge's greens --------------------

static func _hedge_run(out: Array, horiz: bool, o: Vector2i, key0: int,
		length: int, t: int, side: int) -> void:
	_r(out, horiz, o, 0, 0, length, t, LEAF)
	for p: Vector2i in _pieces(length, key0, side, 3, 5):
		var u: int = p.x
		var n: int = p.y
		var k := key0 + u
		# A notch between clumps, and some clumps bulge a pixel past the
		# clipped line on the yard side.
		_r(out, horiz, o, u, 0, 1, 1, LEAF_LO)
		if _h(k, side, 8) < 0.4 and n >= 3:
			var bv := _proud_v(horiz, side, t)
			_r(out, horiz, o, u + 1, bv, n - 2, 1, LEAF)
			_r(out, horiz, o, u + 1, bv, 1, 1, LEAF_MID)
		# Leaves catching the light: up to three lit pixels scattered over the
		# clump, brightest on its top row.
		for j in 3:
			if _h(k, side, 20 + j) < 0.7:
				var lu := u + int(_h(k, side, 30 + j) * float(n))
				var lv := int(_h(k, side, 40 + j) * float(t - 1))
				_r(out, horiz, o, lu, lv, 1, 1, LEAF_HI if lv == 0 else LEAF_MID)
		# Shade under the clump.
		_r(out, horiz, o, u, t - 1, n, 1, LEAF_LO)
		if _h(k, side, 11) < 0.5:
			_r(out, horiz, o, u + int(_h(k, side, 12) * float(n)), t - 1, 1, 1, LEAF_DARK)


static func _hedge_jamb(out: Array, b: Rect2i, dir: int) -> void:
	# A fuller end either side of the gap, its top corner on the gap side left
	# off, which is what rounds it.
	out.append([Rect2(b.position.x, b.position.y + 1, b.size.x, b.size.y - 1), LEAF])
	var top_x := b.position.x if dir < 0 else b.position.x + 1
	out.append([Rect2(top_x, b.position.y, b.size.x - 1, 1), LEAF])
	out.append([Rect2(top_x, b.position.y, 1, 1), LEAF_HI])
	out.append([Rect2(b.position.x, b.position.y + 1, b.size.x, 1), LEAF_MID])
	out.append([Rect2(b.position.x, b.end.y - 1, b.size.x, 1), LEAF_LO])


# --- Plaster: a whitewashed lip in the farmhouse's cream ----------------------

static func _plaster_run(out: Array, horiz: bool, o: Vector2i, key0: int,
		length: int, t: int, side: int) -> void:
	_r(out, horiz, o, 0, 0, length, 1, PLASTER_HI)
	_r(out, horiz, o, 0, 1, length, t - 2, PLASTER)
	_r(out, horiz, o, 0, t - 1, length, 1, PLASTER_LO)
	# Wear, at irregular places: a grey stain, or plaster flaked off to the brick.
	for p: Vector2i in _pieces(length, key0, side, 4, 11):
		var k := key0 + p.x
		var roll := _h(k, side, 13)
		var u: int = p.x + int(_h(k, side, 14) * float(maxi(1, p.y - 2)))
		if roll < 0.30:
			_r(out, horiz, o, u, 1, 2, 1, PLASTER_STAIN)
		elif roll < 0.48:
			_r(out, horiz, o, u, 0, 1, 2, PLASTER_BRICK)
			_r(out, horiz, o, u + 1, 1, 1, 1, PLASTER_BRICK)


static func _plaster_jamb(out: Array, b: Rect2i, _dir: int) -> void:
	# A squared pillar either side of the door.
	_block(out, b, PLASTER, PLASTER_HI, PLASTER_LO)
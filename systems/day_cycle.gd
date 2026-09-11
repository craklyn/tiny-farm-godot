# day_cycle.gd — Day transition with fade animation
# Mirrors the Love2D day_cycle.lua
extends CanvasLayer

var state: String = "idle"  # "idle", "tucking", "fading_out", "loop_in", "loop_playing", "loop_out", "hold", "fading_in"
var alpha: float = 0.0
var timer: float = 0.0
var day_display: int = 1

# T-27 (box 1): the anticipation beat. The transition now *opens* on the lit
# world with the farmer lying on her cot, and only then fades.
#
# **This does not delay the sim by a frame, and must not (D-8).** The sleep Action
# is applied by `main.gd` at the instant the tap resolves, before `start_sleep()`
# is even called — so the world is already in the new day for the whole of the
# sequence below, and every phase here is presentation that could be skipped
# entirely without the sim noticing. D-8 names the one variant that would be a
# sim change ("a wind-up before the effect") and this is deliberately not it: the
# effect has already happened, and what she is watching is its acknowledgement.
#
# Long enough to register as an answer to her tap, short enough that it never
# reads as a wait. [Playtest]
const TUCK_TIME := 0.45
const FADE_OUT_TIME := 0.5
const HOLD_TIME := 0.5
const FADE_IN_TIME := 0.5

# P-15 ("The overnight is where the farm tells its stories"): on a night the sim
# names a threshold, the hold plays that threshold's Animation Lab loop once
# before the Day-N card. The fade's own colour becomes the Lab's sky rather than
# pure black, so the loop's canvas never shows as a box against it — every phase
# below fades through this same colour, story night or not.
#
# design/09 "Where the Lab's loops play" and "How a loop is shown — first
# version" are the spec this follows: centred at the sheet's own largest
# whole-number scale, nearest-neighbour filtering, fade up ~0.4s, whole loops
# until at least 3s have played, fade down, then the Day-N card as always.
const SKY_COLOUR := Color8(33, 31, 32)
const LOOP_FADE_SEC := 0.4
const LOOP_MIN_PLAY_SEC := 3.0

# Which loop a story night plays. This is presentation's own lookup, not a
# second opinion of the trigger — the fact itself (which night, or none) is read
# fresh off the sim every time (`farm.sim.story_night`) and never recomputed
# here; this dictionary only names the loop that fact points at.
const STORY_NIGHT_LOOPS := {
	SimWorld.STORY_NIGHT_CROW: "crow_gorge",
	SimWorld.STORY_NIGHT_ROBOT: "seeder_bot",
}

# A 4×4 ordered-dither (Bayer) matrix, used to stipple a loop's canvas edge into
# the sky colour rather than cut it off with a hard line — see `_dither_edge_band`.
const BAYER4 := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

var _on_new_day: Callable
var _new_day_fired: bool = false

# The farm this transition presents. Set once by `main.gd` once both exist.
# Read only for the one fact above (`farm.sim.story_night`) — nothing here ever
# calls `apply_action`; the sim items own that (main.gd, ColdOpen).
var farm: Node2D = null

# UI elements
var overlay: ColorRect
var day_label: Label

# The loop sprite — built only for a night that has one, drawn between the fade
# and the Day-N card (tree order: overlay, loop sprite, day_label).
var _loop_sprite: Sprite2D = null
var _loop_frames: Array[Texture2D] = []
var _loop_ms_per_frame: float = 90.0
var _loop_elapsed: float = 0.0
var _loop_play_total: float = 0.0
var _frame_cache: Dictionary = {}  # slug -> Array[Texture2D], dither already baked in

# What played on the last hold, "" for a plain night — read by tools and tests,
# not by any game logic.
var last_story_loop: String = ""


func _ready() -> void:
	layer = 100  # Draw on top of everything

	overlay = ColorRect.new()
	overlay.color = Color(SKY_COLOUR.r, SKY_COLOUR.g, SKY_COLOUR.b, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_loop_sprite = Sprite2D.new()
	_loop_sprite.name = "OvernightLoop"
	_loop_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixels stay square, never smoothed
	_loop_sprite.visible = false
	_loop_sprite.modulate = Color(1, 1, 1, 0)
	add_child(_loop_sprite)  # after the fade, before the day card (added next)

	day_label = Label.new()
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	day_label.set_anchors_preset(Control.PRESET_CENTER)
	day_label.add_theme_font_size_override("font_size", 24)
	day_label.add_theme_color_override("font_color", Color.WHITE)
	day_label.visible = false
	add_child(day_label)


## `tuck` asks for T-27's anticipation beat before the fade. The player's own
## sleep passes it; the cold open's world sleep does not — nobody is lying on
## anything there, and holding a lit world for half a second to show that would be
## a pause with nothing in it (T-26 asks the opposite question of that transition,
## and it is still open).
func start_sleep(on_new_day: Callable, tuck: bool = false) -> void:
	if state != "idle":
		return
	state = "tucking" if tuck else "fading_out"
	timer = 0.0
	alpha = 0.0
	_on_new_day = on_new_day
	_new_day_fired = false
	last_story_loop = ""
	if _loop_sprite != null:
		_loop_sprite.visible = false
		_loop_sprite.modulate = Color(1, 1, 1, 0)


func is_active() -> bool:
	return state != "idle"


func set_day_display(day: int) -> void:
	day_display = day


func _process(delta: float) -> void:
	if state == "idle":
		return

	timer += delta

	match state:
		"tucking":
			# The world stays lit and unfaded: this beat exists to be *seen*.
			alpha = 0.0
			if timer >= TUCK_TIME:
				state = "fading_out"
				timer = 0.0
		"fading_out":
			alpha = minf(1.0, timer / FADE_OUT_TIME)
			if timer >= FADE_OUT_TIME:
				_enter_hold_phase()
		"loop_in":
			# Frame 0 holds still through the fade-up, so the loop's clock starts
			# on its first frame and the fade-down lands on a loop boundary —
			# design/09's "plays whole loops" is measured from here.
			alpha = 1.0
			_loop_sprite.modulate.a = minf(1.0, timer / LOOP_FADE_SEC)
			if timer >= LOOP_FADE_SEC:
				state = "loop_playing"
				timer = 0.0
				_loop_elapsed = 0.0
		"loop_playing":
			alpha = 1.0
			_loop_sprite.modulate.a = 1.0
			_step_loop_frame(delta)
			if timer >= _loop_play_total:
				state = "loop_out"
				timer = 0.0
		"loop_out":
			alpha = 1.0
			_loop_sprite.modulate.a = 1.0 - minf(1.0, timer / LOOP_FADE_SEC)
			_step_loop_frame(delta)
			if timer >= LOOP_FADE_SEC:
				_loop_sprite.visible = false
				state = "hold"
				timer = 0.0
		"hold":
			alpha = 1.0
			if timer >= HOLD_TIME:
				state = "fading_in"
				timer = 0.0
		"fading_in":
			alpha = 1.0 - minf(1.0, timer / FADE_IN_TIME)
			if timer >= FADE_IN_TIME:
				state = "idle"
				alpha = 0.0

	overlay.color = Color(SKY_COLOUR.r, SKY_COLOUR.g, SKY_COLOUR.b, alpha)

	# Show day text during hold
	if state == "hold" and alpha >= 0.9:
		day_label.text = "Day %d" % day_display
		day_label.visible = true
	else:
		day_label.visible = false


# The single entry into everything that follows the fade: fires the sleep's own
# callback (T-27 box 1/D-8's exact moment — the first frame the screen is fully
# the sky colour) and only then decides whether tonight has a story to tell.
#
# The order matters for one reason beyond D-8: the cold open's world sleep
# applies its Action *inside* this callback rather than before `start_sleep` was
# called (main.gd), so `farm.sim.story_night` is only trustworthy once the
# callback below has run — reading it any earlier would catch last night's fact.
func _enter_hold_phase() -> void:
	if not _new_day_fired and _on_new_day.is_valid():
		_on_new_day.call()
	_new_day_fired = true

	last_story_loop = ""
	var night := ""
	if farm != null and is_instance_valid(farm) and farm.sim != null:
		night = String(farm.sim.story_night)
	var slug: String = STORY_NIGHT_LOOPS.get(night, "")
	var already_shown: bool = GameState.story_loops_shown.get(night, false)

	if slug != "" and not already_shown and _prepare_loop(slug):
		# Marked the moment the loop is chosen, not once it finishes: once per
		# farm, no skip — a session cut short mid-loop must never offer a second
		# showing on reload (the flag rides the save, `save_game.gd`).
		GameState.story_loops_shown[night] = true
		last_story_loop = slug
		state = "loop_in"
		timer = 0.0
		return

	state = "hold"
	timer = 0.0


# Loads the manifest, builds (and caches) the loop's frames, sizes and centres
# the sprite at the largest whole-number scale that fits the screen, and starts
# it invisible for `loop_in` to fade up. False on any failure (missing asset,
# empty manifest) — the caller falls back to a plain hold, never a broken frame.
func _prepare_loop(slug: String) -> bool:
	var manifest := _load_anim_manifest(slug)
	if manifest.is_empty():
		return false
	var frames := _frames_for_slug(slug, manifest)
	if frames.is_empty():
		return false

	_loop_frames = frames
	_loop_ms_per_frame = float(manifest.get("ms_per_frame", 90.0))
	if _loop_ms_per_frame <= 0.0:
		return false
	var loop_dur: float = frames.size() * _loop_ms_per_frame / 1000.0
	var repeats: int = maxi(1, ceili(LOOP_MIN_PLAY_SEC / loop_dur))
	_loop_play_total = repeats * loop_dur
	_loop_elapsed = 0.0

	var cw := int(manifest.get("cell_width", 0))
	var ch := int(manifest.get("cell_height", 0))
	if cw <= 0 or ch <= 0:
		return false
	# `CanvasLayer` has no `get_viewport_rect()` of its own (that is a Control/
	# Node2D convenience) — go through the viewport itself, same value.
	var viewport := get_viewport().get_visible_rect().size
	var loop_scale: int = maxi(1, mini(int(viewport.x / cw), int(viewport.y / ch)))

	_loop_sprite.texture = frames[0]
	_loop_sprite.scale = Vector2(loop_scale, loop_scale)
	_loop_sprite.position = viewport / 2.0
	_loop_sprite.modulate = Color(1, 1, 1, 0)
	_loop_sprite.visible = true
	return true


func _step_loop_frame(delta: float) -> void:
	if _loop_frames.is_empty():
		return
	var frame_dur: float = _loop_ms_per_frame / 1000.0
	_loop_elapsed += delta
	var i: int = int(_loop_elapsed / frame_dur) % _loop_frames.size()
	_loop_sprite.texture = _loop_frames[i]


func _load_anim_manifest(slug: String) -> Dictionary:
	var path := "res://assets/anim/%s/manifest.json" % slug
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


# The sheet is one horizontal strip, `frame_count` cells of `cell_width` ×
# `cell_height` each (the export step's own layout, `19d18a2`) — the same
# atlas-region pattern `ui/hud.gd`'s watering inset already cuts frames with.
#
# A manifest with `edge: "dissolve"` gets its whole sheet dithered once, before
# slicing: the band is the same at every cell (it only depends on where a pixel
# sits inside its own frame), so baking it into the shared sheet image and then
# atlas-slicing as usual costs one pass over the sheet instead of one per frame.
func _frames_for_slug(slug: String, manifest: Dictionary) -> Array[Texture2D]:
	if _frame_cache.has(slug):
		return _frame_cache[slug]
	var out: Array[Texture2D] = []
	var sheet_path := "res://assets/anim/%s/%s" % [slug, String(manifest.get("sheet", "sheet.png"))]
	var sheet: Texture2D = load(sheet_path)
	if sheet == null:
		return out
	var cw := int(manifest.get("cell_width", 0))
	var ch := int(manifest.get("cell_height", 0))
	var count := int(manifest.get("frame_count", 0))
	if cw <= 0 or ch <= 0 or count <= 0:
		return out

	var atlas_source: Texture2D = sheet
	if String(manifest.get("edge", "clean")) == "dissolve":
		var sky_arr: Array = manifest.get("sky_colour", [33, 31, 32])
		var sky := Color8(int(sky_arr[0]), int(sky_arr[1]), int(sky_arr[2]))
		var img: Image = sheet.get_image()
		if img != null:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
			var band := maxi(4, int(cw * 0.12))
			for i in count:
				_dither_edge_band(img, i * cw, cw, ch, band, sky)
			atlas_source = ImageTexture.create_from_image(img)

	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = atlas_source
		atlas.region = Rect2(i * cw, 0, cw, ch)
		out.append(atlas)
	_frame_cache[slug] = out
	return out


# design/09: "a loop whose manifest says edge=dissolve gets a short ordered-
# dither band at its left and right canvas edges in the sky colour, so the
# ground dissolves into the night instead of stopping at a line." A hard alpha
# gradient would be smoothing — the one thing a nearest-neighbour loop must
# never show — so this instead *replaces* pixels outright, more of them as the
# canvas edge gets closer, in the fixed 4×4 pattern above: a stipple, not a
# blur. The outermost column (`depth == 0`) always replaces, which is what
# guarantees the frame's own edge is never a visible line.
func _dither_edge_band(img: Image, ox: int, cw: int, ch: int, band: int, sky: Color) -> void:
	for y in ch:
		for depth in band:
			var edge_frac: float = 1.0 - float(depth) / float(band)
			var threshold: float = (BAYER4[y % 4][depth % 4] + 0.5) / 16.0
			if threshold < edge_frac:
				img.set_pixel(ox + depth, y, sky)
				img.set_pixel(ox + cw - 1 - depth, y, sky)

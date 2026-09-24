# title_screen.gd — boot screen: three farms, pick one (S-14).
#
# Each card answers "where was I?" before committing to a tap, and each one is a
# whole farm of its own: the game keeps three, so two people can play without
# taking turns with the same land. A card that holds a farm shows what that farm
# has done; an empty one starts a new farm when it is tapped.
#
# **A card has to be recognisable without reading it.** The game is played by a
# pre-reader (S-7), so a farm is found by its colour and its shape — green
# circle, rose triangle, blue square — and the words on the card are there for
# whoever is reading over her shoulder. The one destructive control, starting
# over on a farm that already exists, is deliberately the small one in the
# corner, and it asks first: nothing a four-year-old can tap should destroy
# progress silently.
extends Control

const CARD_W := 340
const SLOT_CARD_H := 92

const SHAPE_CIRCLE := 0
const SHAPE_TRIANGLE := 1
const SHAPE_SQUARE := 2

# Green circle, rose triangle, blue square (S-14). Colour and shape together,
# never colour alone, so a card is still hers in the dark or on a washed-out
# tablet screen. Index 0 is slot 1.
const SLOT_LOOKS := [
	{
		"bg": Color(0.18, 0.42, 0.22), "border": Color(1.00, 0.72, 0.15),
		"hover": Color(0.24, 0.52, 0.28), "emblem": Color(1.00, 0.84, 0.36),
		"shape": SHAPE_CIRCLE,
	},
	{
		"bg": Color(0.44, 0.20, 0.28), "border": Color(1.00, 0.58, 0.64),
		"hover": Color(0.54, 0.26, 0.35), "emblem": Color(1.00, 0.66, 0.72),
		"shape": SHAPE_TRIANGLE,
	},
	{
		"bg": Color(0.16, 0.28, 0.46), "border": Color(0.50, 0.76, 1.00),
		"hover": Color(0.21, 0.36, 0.56), "emblem": Color(0.62, 0.84, 1.00),
		"shape": SHAPE_SQUARE,
	},
]

# Q-103 ("the flower is the splash"), amended by the designer on 2026-09-15:
# the picture the engine holds while the game loads is the **app icon** — the
# farmer with the drone off her hat — and the bloom plays only once the game is
# live under it. It used to be the bloom's own first frame, so the first thing
# anyone saw was a still of an animation that had not started: a frozen
# animation reads as a hang, because the eye is waiting for it to move, where a
# still icon is just a logo and the same wait looks like nothing at all. This
# scene opens on that same plate — `tools/gen_icon.py` writes it, so it cannot
# drift from the icon the player tapped — holds it until the frames are cheap
# again, and dissolves it off the bloom. design/09 §"The boot".
const BOOT_PLATE := "res://assets/icon/boot_splash.png"
const PLATE_DISSOLVE_SEC := 0.45
# Both bounds are read off the process clock rather than this scene's, so the
# time the engine already spent holding this same picture counts toward them:
# on a slow tablet there is usually nothing left to wait for, and on a fast
# desktop this is what keeps the plate from flashing past unseen.
const PLATE_MIN_MSEC := 900
const PLATE_MAX_MSEC := 8000           # a device that never settles still gets its bloom
const PLATE_FRAME_BUDGET_MSEC := 40.0  # a frame this cheap is a frame nobody is waiting on
const PLATE_SMOOTH_FRAMES := 3         # ...and three of them in a row is the load being over

# The Lab's sky, which the bloom is drawn on and the plate dissolves to reveal.
const BOOT_SKY_COLOUR := Color8(33, 31, 32)
# The farm's own edge-blend colour (unchanged from before this work): a bright
# green rectangle beside a real farm reads as a hole, so the backdrop darkens
# toward it once the farm is what is showing. Applied by the reveal now
# instead of the moment the attract loop starts, since the bloom plays against
# the sky colour above in the meantime.
const ATTRACT_EDGE_COLOUR := Color(0.13, 0.28, 0.17)

const BLOOM_MANIFEST := "res://assets/anim/sunflower_bloom/manifest.json"
const BLOOM_SHEET := "res://assets/anim/sunflower_bloom/sheet.png"
const BLOOM_SCALE := 5
const BLOOM_HOLD_SEC := 0.4       # a beat of stillness on the bud, after the icon, before it rises
# The designer, 2026-09-15: "make the flower animation linger about 50% longer
# before transitioning to main landing page." The rise itself is left at the rate
# the Lab drew it — design/09 is explicit that a loop plays at its own rate — so
# the extra time is a hold on the last bloomed frame instead. Hold plus rise was
# 1.84 s; this takes the flower's whole moment to about 2.76 s. The chime is cut
# to the same length (`tools/gen_sfx.py` reads this number out of this file), so
# it rings out over the linger rather than finishing early and leaving silence.
const BLOOM_LINGER_SEC := 0.9
const BLOOM_TITLE_FADE_SEC := 0.5 # the title and menu settling in, not appearing
const BLOOM_FARM_FADE_SEC := 1.0  # the attract farm fading up beneath the menu
# The flower leaves faster than the farm arrives, and the menu waits for it to
# be gone. Everything used to cross-fade on one clock, which put the Continue
# card on screen over a half-dissolved sunflower for about half a second — two
# subjects sharing the middle of the screen, which is what made the hand-off
# read as muddy rather than as a fade. Now it is one thing at a time: the flower
# dissolves into the farm, and only then does the menu settle onto it.
const BLOOM_FADE_OUT_SEC := 0.7   # the flower going, on its own
const BLOOM_MENU_DELAY_SEC := 0.55
# Q-107 (2026-09-11): "add a bit more pause after that synthesized chime
# finishes before we ramp into the main game's music" — the music used to
# start its own fade-up the instant the chime did, finishing within a beat of
# each other, which read as racing rather than one answering the other. Now
# the music waits out the chime's own length (read off the stream, so a
# regenerated chime keeps this in sync) plus this pause before it starts.
const POST_CHIME_PAUSE_SEC := 0.4
const MUSIC_FADE_UP_SEC := 1.0    # how long the music's fade-up itself takes, once it starts
const TAP_FADE_OUT_SEC := 0.3     # start_game: title scene fading to the sky colour
# The other half — main.gd fading the sky colour away once the farm is there
# — is `main.gd`'s own BOOT_FADE_IN_SEC, since it runs in a different scene.

# Alternate takes awaiting a verdict; empty once one is promoted or dropped.
# P-15 p1 (Q-107, ruled 2026-09-11): the shipped picks are `peck`,
# `seeder_tread`, `seeder_servo`, `seeder_scatter` and `bloom_chime` in
# AudioManager's own table (`systems/audio_manager.gd`) — these are what did
# not get wired instead. `seeder_servo` ships two takes as alternating
# variants now, so only its one remaining unwired take is listed here.
# `peck_synth` is generated by tools/gen_sfx.py --alt; the rest are CC0 pulls
# (tools/fetch_sfx_candidates.py, CREDITS.md has every source).
const SFX_CANDIDATES := [
	"peck_synth",
	"seeder_tread_cc0_425271", "seeder_tread_cc0_415565",
	"seeder_servo_cc0_740244",
	"seeder_scatter_cc0_348954", "seeder_scatter_cc0_348955",
	"bloom_chime_cc0_333694", "bloom_chime_cc0_333695", "bloom_chime_cc0_333696",
]

# Where the three farms are read from and written to. Overridable for the same
# reason GameState's three paths are: a suite that instantiates this screen must
# be able to look at farms of its own rather than at a real player's.
var slots_root: String = SaveSlots.ROOT

# One entry per slot, in slot order: { "slot": 1, "has_farm": true, "summary": {...} }.
var _slots: Array[Dictionary] = []
# Which farm a tap on the backdrop resumes (Q-8), or 0 when there is none yet.
var _resume_slot := 0
var _confirm_open := false
var _confirm_slot := 0  # which farm the open confirmation is about
var _confirm_layer: Control = null


const DEMO_REPLAY_PATH := "res://assets/demo/demo_replay.json"
var _attract: Node2D = null

# The bloom (Q-103). Null headless, where the whole sequence is skipped.
var _bloom: Sprite2D = null
var _bloom_frames: int = 16
var _bloom_ms_per_frame: int = 90
var _bloom_cell := Vector2i(64, 104)
var _bloom_reveal_frames: int = 16
var _bloom_idle_frame: int = 15
var _menu_root: Control = null
var _intro_shield: Control = null  # swallows taps until the menu has settled in
var _plate: TextureRect = null     # the icon, held over everything until the game is live


func _ready() -> void:
	# The backdrop under everything is the bloom's own sky, not the flat green:
	# the plate covers it until the game is live, and what the plate dissolves
	# into has to be the sky the bloom is drawn on, or the loop's canvas would
	# show as a box. Headless never paints it, so it is left alone there.
	if _boot_bloom_due():
		var back := get_node_or_null("ColorRect")
		if back != null:
			back.color = BOOT_SKY_COLOUR

	# Before anything reads a farm: a build that predates slots wrote its farm
	# straight into `user://`, and that farm belongs in slot 1 (S-14). Done here
	# because this is the game's entry scene, and skipped headless because the
	# only headless callers are the suites and the tools, which bring farms of
	# their own and must never move a developer's.
	if DisplayServer.get_name() != "headless":
		SaveSlots.migrate_legacy(slots_root)

	# The slots are read before the attract loop starts, because the farm playing
	# behind the menu is the one a tap would resume (T-16/Q-40).
	#
	# **Reading the farms changes nothing global.** `GameState` is pointed at a
	# slot when a card is actually chosen (`choose_slot`) and not a moment
	# earlier — otherwise merely building this screen, which the integration
	# suite does half a dozen times to check a button exists, would silently
	# redirect the played session's autosave.
	_read_slots()
	_start_attract()
	# Tree order end to end: backdrop, attract farm, the bloom, the icon plate,
	# the menu — the bloom sits between the farm it will reveal and the menu
	# that settles in over both of them, and the plate covers all three until
	# the game behind it is running.
	if _boot_bloom_due():
		_build_boot_bloom()
		_build_boot_plate()
		_build_ui()
		_arm_intro_shield()
		GameState.boot_bloom_played = true
		_play_boot_bloom()
	else:
		# Headless, or a return to this screen from the pause menu, the zoo or
		# the home screen: the boot has already played this launch, so the menu
		# and the farm behind it are simply there.
		_build_ui()
		_settle_without_bloom()


# T-16 (Q-40): the menu sits over a real farm being played. Everything about
# what it plays and how is in `ui/attract_loop.gd`; this only decides whether to.
func _start_attract() -> void:
	var AttractScript = load("res://ui/attract_loop.gd")
	if not AttractScript.ATTRACT_ENABLED:
		return
	# Headless has nothing to render into and no reason to spend the frames.
	if DisplayServer.get_name() == "headless":
		return
	# The farm a tap would resume is the farm that plays behind the menu — read
	# from the slot itself rather than from `GameState`, which this screen does
	# not touch until a card is chosen.
	var own_replay := SaveSlots.replay_path(
		_resume_slot if _resume_slot > 0 else SaveSlots.last_played(slots_root), slots_root)
	var replay: ReplayLog = AttractScript.choose_replay(own_replay, DEMO_REPLAY_PATH)
	if replay == null:
		return  # first boot on a fresh install: keep the flat backdrop

	var loop = AttractScript.new()
	loop.name = "AttractLoop"
	# Draw order is tree order, and `_ready` runs this *before* `_build_ui`, so the
	# farm lands after the backdrop and before the menu: backdrop, farm, buttons.
	# It is a Node2D and takes no input, so every tap still reaches the menu above
	# it and tap-anywhere-to-continue still reaches the title screen itself.
	add_child(loop)
	if not loop.begin(replay):
		loop.queue_free()
		return
	_attract = loop

	# Q-103: the farm used to darken the backdrop and show itself the instant
	# it started. Now the bloom plays against the sky colour first, and both
	# the farm's own fade-up and its backdrop darken (the flat backdrop stays
	# as the thing *behind* the farm rather than being deleted — the drifting
	# layer need not cover every pixel, but a bright green rectangle beside a
	# real farm reads as a hole) happen together in `_play_boot_bloom`'s reveal.
	loop.modulate.a = 0.0 if _boot_bloom_due() else 1.0

	# One moving thing at a time — the build hash would otherwise sit over a
	# moving farm, and it is a developer's label rather than part of the picture.
	# Restored in _exit_tree: BuildOverlay is an autoload and outlives this scene,
	# so hiding it without putting it back would silently remove it from the game
	# itself, which is the one place it is actually useful.
	_hide_build_overlay(true)


func _build_overlay() -> CanvasLayer:
	return get_tree().root.get_node_or_null("BuildOverlay") as CanvasLayer


func _hide_build_overlay(hidden: bool) -> void:
	var overlay := _build_overlay()
	if overlay != null:
		overlay.visible = not hidden


func _exit_tree() -> void:
	_hide_build_overlay(false)


# Anything that opens a panel over the title pauses the farm behind it: one
# moving thing at a time, which is the same rule the vignette follows.
func _set_attract_paused(value: bool) -> void:
	if _attract != null and is_instance_valid(_attract):
		_attract.paused = value


# --- The boot: the icon, then the bloom (Q-103, amended 2026-09-15) -----------
#
# Two pictures, in this order. The **icon plate** is what the engine holds
# through the load (project.godot's `boot_splash/*`) and what this scene redraws
# over its own first frame, so the swap from the held picture to the live one
# has nothing in it. The **bloom** is underneath it from the start, built and
# placed before anything is animated, and is revealed by the plate dissolving
# once the game is running. Only the *playing* of it is skipped headless.
#
# design/09 §"The boot" is explicit that the loop is drawn from the Lab's
# exported sheet as it is, never re-authored here — this steps through
# `sheet.png`'s cells by the numbers in `manifest.json`, nothing more.

# The bloom is the boot, not the title screen: it plays on the first entry of a
# launch and never on a return from the pause menu, the zoo or the home screen —
# those land on the settled menu, with the music where it was. Headless never
# plays it at all.
func _boot_bloom_due() -> bool:
	return DisplayServer.get_name() != "headless" and not GameState.boot_bloom_played


# What the screen looks like once the bloom has done its work, reached directly
# when the bloom does not play: the farm (if any) visible over the darkened
# backdrop, the menu fully drawn, nothing shielding taps.
func _settle_without_bloom() -> void:
	if _menu_root != null:
		_menu_root.modulate.a = 1.0
	var back := get_node_or_null("ColorRect")
	if back != null and _attract != null and is_instance_valid(_attract):
		back.color = ATTRACT_EDGE_COLOUR


func _build_boot_bloom() -> void:
	if not _boot_bloom_due():
		return  # nothing to render into, or already played this launch
	var manifest := _load_bloom_manifest()
	_bloom_frames = int(manifest.get("frame_count", _bloom_frames))
	_bloom_reveal_frames = int(manifest.get("reveal_frames", _bloom_frames))
	_bloom_idle_frame = int(manifest.get("idle_frame", _bloom_reveal_frames - 1))
	_bloom_ms_per_frame = int(manifest.get("ms_per_frame", _bloom_ms_per_frame))
	_bloom_cell = Vector2i(
		int(manifest.get("cell_width", _bloom_cell.x)),
		int(manifest.get("cell_height", _bloom_cell.y)))

	_bloom = Sprite2D.new()
	_bloom.name = "BootBloom"
	_bloom.texture = load(BLOOM_SHEET)
	_bloom.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixels stay square
	_bloom.region_enabled = true
	_bloom.region_rect = Rect2(0, 0, _bloom_cell.x, _bloom_cell.y)  # the closed bud it opens from
	_bloom.scale = Vector2(BLOOM_SCALE, BLOOM_SCALE)
	# Centred on the sky at ×5, which is where design/09 §"How a loop is shown"
	# puts every one of the Lab's loops — the boot is not a special case.
	_bloom.position = get_viewport_rect().size / 2.0
	add_child(_bloom)  # after the attract farm, before the menu (`_build_ui` next)


# The plate the engine's own splash was already showing, drawn again by the
# scene so the hand-off between the two has nothing in it: same picture, same
# size, same place, so the swap from a held image to a live one is invisible.
# Null when the file is missing, which only means the boot opens the way it did
# before this existed.
func _build_boot_plate() -> void:
	if not _boot_bloom_due():
		return
	var tex: Texture2D = load(BOOT_PLATE)
	if tex == null:
		return
	_plate = TextureRect.new()
	_plate.name = "BootPlate"
	_plate.texture = tex
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixels stay square
	_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate.stretch_mode = TextureRect.STRETCH_SCALE
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the intro shield does the swallowing
	add_child(_plate)


# Holds the icon until the game is actually running under it, then dissolves it
# off the bloom. "Running" is measured rather than guessed at with a fixed
# sleep: three consecutive frames inside a cheap budget means the replay has
# been decoded, the farm behind has been built and is drawing, and nothing is
# about to hitch — which is exactly the moment the bloom can start without
# stuttering on its first frames. The ceiling is there because a device that
# never gets there should still see its flower.
func _hold_plate_until_live() -> void:
	var smooth := 0
	var last := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		if not is_instance_valid(self) or _plate == null:
			return
		var now := Time.get_ticks_msec()
		smooth = smooth + 1 if float(now - last) <= PLATE_FRAME_BUDGET_MSEC else 0
		last = now
		if now >= PLATE_MAX_MSEC:
			break
		if now >= PLATE_MIN_MSEC and smooth >= PLATE_SMOOTH_FRAMES:
			break

	var dissolve := create_tween()
	dissolve.tween_property(_plate, "modulate:a", 0.0, PLATE_DISSOLVE_SEC)
	await dissolve.finished
	if not is_instance_valid(self):
		return
	_drop_boot_plate()


func _drop_boot_plate() -> void:
	if _plate != null:
		_plate.queue_free()
		_plate = null


func _load_bloom_manifest() -> Dictionary:
	var f := FileAccess.open(BLOOM_MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


# Swallows every tap — the menu's buttons included — until the menu has
# actually settled in. Without it, a tap landing on a button's hit area while
# it is still invisible starts the game before the player has seen anything.
func _arm_intro_shield() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_intro_shield = Control.new()
	_intro_shield.name = "IntroInputShield"
	_intro_shield.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_intro_shield)  # last child: topmost, so it catches every tap first


func _drop_intro_shield() -> void:
	if _intro_shield != null:
		_intro_shield.queue_free()
		_intro_shield = null


# Hold the icon until the game is live, dissolve it onto the bloom's first
# frame, hold a beat there, rise through the loop once with the chime under it,
# then settle the title and menu in and reveal whatever is behind the bloom.
# The music's own fade-up runs on its own clock, starting only once
# the chime has finished (`_fade_bgm_in_after_chime`), so it does not race the
# visual reveal below. Headless (and any run that could not build the sprite)
# skips straight to the settled state, same as the attract loop already does.
func _play_boot_bloom() -> void:
	if _bloom == null:
		_drop_boot_plate()
		_drop_intro_shield()
		if _menu_root != null:
			_menu_root.modulate.a = 1.0
		return

	# Silent through the hold too, not just the rise — AudioManager's bgm is
	# already playing at -10 dB by this point (its own `_ready`, an autoload,
	# runs before this scene's), and cutting it to silence only once the rise
	# starts would be an audible stutter rather than a fade up from nothing.
	AudioManager.bgm_player.volume_db = -80.0

	# The icon holds the screen until the game is live under it. The bloom's
	# own hold below is a beat of stillness before the chime, not a loading
	# screen, and this is what keeps it from having to be one.
	if _plate != null:
		await _hold_plate_until_live()
		if not is_instance_valid(self):
			return

	await get_tree().create_timer(BLOOM_HOLD_SEC).timeout
	if not is_instance_valid(self):
		return

	# P-15 p1: a soft rising chime under the seeds' climb. Q-107: the music
	# now waits for the chime to finish (plus a pause) rather than fading up
	# beneath it — see `_fade_bgm_in_after_chime`.
	AudioManager.play_sfx("bloom_chime")
	_fade_bgm_in_after_chime()

	for i in _bloom_reveal_frames:
		if not is_instance_valid(self) or _bloom == null:
			return
		_bloom.region_rect = Rect2(i * _bloom_cell.x, 0, _bloom_cell.x, _bloom_cell.y)
		await get_tree().create_timer(_bloom_ms_per_frame / 1000.0).timeout
		if not is_instance_valid(self):
			return

	# The last seed has landed. The flower holds there, bloomed, while the chime
	# rings out — the moment the boot is actually for — and only then does the
	# screen start becoming the menu. The shield stays up through it, because
	# the menu underneath is still invisible and a tap on a button nobody can
	# see would start the game.
	await get_tree().create_timer(BLOOM_LINGER_SEC).timeout
	if not is_instance_valid(self):
		return

	# The title and menu settle in rather than appear, and whatever is behind
	# the bloom takes its place — in that order, not at once. The menu's own
	# tween opens with the wait, so the card lands on a farm rather than on a
	# flower that has not finished leaving.
	_drop_intro_shield()
	if _menu_root != null:
		var menu_tween := create_tween()
		menu_tween.tween_interval(BLOOM_MENU_DELAY_SEC)
		menu_tween.tween_property(_menu_root, "modulate:a", 1.0, BLOOM_TITLE_FADE_SEC)

	if _attract != null and is_instance_valid(_attract):
		var back := get_node_or_null("ColorRect")
		var reveal := create_tween()
		reveal.set_parallel(true)
		reveal.tween_property(_attract, "modulate:a", 1.0, BLOOM_FARM_FADE_SEC)
		reveal.tween_property(_bloom, "modulate:a", 0.0, BLOOM_FADE_OUT_SEC)
		if back != null:
			reveal.tween_property(back, "color", ATTRACT_EDGE_COLOUR, BLOOM_FARM_FADE_SEC)
	else:
		# First boot, no session to play behind the menu yet: keep the
		# fully bloomed pose. Replaying the reveal would repeatedly erase her.
		_hold_bloom_idle()


# Q-107: waits out the chime's own length (its `AudioStream.get_length()`, so
# a regenerated chime never drifts out of sync with this) plus
# `POST_CHIME_PAUSE_SEC` of continued silence, then ramps the music up to its
# usual volume over `MUSIC_FADE_UP_SEC`. Runs uncoupled from the bloom's own
# visual timeline (the hold, the seed climb, the menu settling in) — none of
# that changes; only when the music answers it does.
func _fade_bgm_in_after_chime() -> void:
	var chime_dur := 0.0
	var chime_stream = AudioManager.sfx_streams.get("bloom_chime", [null])[0]
	if chime_stream != null:
		chime_dur = chime_stream.get_length()
	await get_tree().create_timer(chime_dur + POST_CHIME_PAUSE_SEC).timeout
	if not is_instance_valid(self):
		return
	var bgm_tween := create_tween()
	bgm_tween.tween_property(AudioManager.bgm_player, "volume_db", -10.0, MUSIC_FADE_UP_SEC)


func _hold_bloom_idle() -> void:
	if _bloom != null:
		_bloom.region_rect = Rect2(_bloom_idle_frame * _bloom_cell.x, 0, _bloom_cell.x, _bloom_cell.y)


# --- The three farms ----------------------------------------------------------

# What each slot holds, and which one a tap on the backdrop resumes. A save this
# build cannot parse counts as no farm: a card that offers to continue something
# that will not load is worse than a card that offers a fresh start.
func _read_slots() -> void:
	_slots.clear()
	for n in range(1, SaveSlots.COUNT + 1):
		var summary := SaveGame.summarize(
			SaveGame.load_dict(SaveSlots.save_path(n, slots_root)))
		_slots.append({ "slot": n, "has_farm": not summary.is_empty(), "summary": summary })

	# Q-8's tap-anywhere still resumes a farm. The last one played is the one it
	# means; if that slot is empty the lowest-numbered farm stands in, so a tap
	# never does nothing while there is a farm on the screen to resume.
	_resume_slot = 0
	var last := SaveSlots.last_played(slots_root)
	if _slot_has_farm(last):
		_resume_slot = last
	else:
		for entry in _slots:
			if entry["has_farm"]:
				_resume_slot = int(entry["slot"])
				break


func _slot_has_farm(n: int) -> bool:
	for entry in _slots:
		if int(entry["slot"]) == n:
			return bool(entry["has_farm"])
	return false


func _slot_summary(n: int) -> Dictionary:
	for entry in _slots:
		if int(entry["slot"]) == n:
			return entry["summary"]
	return {}


# What a tap on a card decides, split from `start_game` so the choice can be
# made — and checked — without a scene change riding on it.
func choose_slot(n: int) -> void:
	GameState.use_slot(n, slots_root)
	SaveSlots.remember(n, slots_root)


func _play_slot(n: int) -> void:
	choose_slot(n)
	start_game(_slot_has_farm(n))


func _build_ui() -> void:
	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_CENTER)
	root_box.anchor_left = 0.5
	root_box.anchor_top = 0.5
	root_box.anchor_right = 0.5
	root_box.anchor_bottom = 0.5
	root_box.offset_left = -CARD_W / 2.0
	# Three cards instead of one puts the column at roughly 460px, so it starts
	# higher than the single card's -150 did — otherwise the credits line and the
	# debug row below it fall off the bottom of an 800x600 screen.
	root_box.offset_top = -234
	root_box.offset_right = CARD_W / 2.0
	root_box.offset_bottom = 234
	root_box.add_theme_constant_override("separation", 12)
	root_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_box)
	_menu_root = root_box
	# Q-103: the menu settles in once the bloom lands rather than appearing on
	# this frame — `_play_boot_bloom` tweens this back to 1. Headless skips the
	# whole sequence and never dims it, so every existing headless assertion
	# that finds a button by name still finds one built and ready.
	if _boot_bloom_due():
		root_box.modulate.a = 0.0

	var title := Label.new()
	title.text = tr("Tiny Farm")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(title)

	# The three farms, stacked, each the full width of the column (S-14).
	var slots_box := VBoxContainer.new()
	slots_box.name = "SlotCards"
	slots_box.add_theme_constant_override("separation", 10)
	slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(slots_box)
	for n in range(1, SaveSlots.COUNT + 1):
		slots_box.add_child(_make_slot_card(n))

	# Deliberately NOT debug-gated: the bundled music is CC BY 4.0 and *requires*
	# an attribution line in the shipped credits (CREDITS.md). Until this existed
	# the game showed credits nowhere, so shipping it publicly would have breached
	# that licence — found on the way to the first release. Small and low-contrast
	# so it does not compete with the one button a pre-reader needs.
	root_box.add_child(_make_credits_button())

	# Debug builds only, so a public release never shows it (the Android export
	# we deploy is --export-debug, so it is present on the test tablet).
	if OS.is_debug_build():
		# One literal row for all three debug doors. They used to stack, and the
		# third one pushed the menu off the bottom of the tablet's screen —
		# reported from the device the night the Zoo landed. Three across at 104px
		# fits the 340px column with the row's two 10px separations to spare.
		# T-37 briefly made it four (a 2x2 grid); the Look Lab's door came back
		# out on 2026-09-02 and it is a single row again — see the note below.
		var debug_row := HBoxContainer.new()
		debug_row.add_theme_constant_override("separation", 10)
		debug_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		debug_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_box.add_child(debug_row)
		# The doors are things to *look at*: the Sound Test plays a sound, the Zoo
		# runs a farm full of entities, the Home (T-37) opens the house. Each one
		# shows you the thing itself when you open it.
		#
		# The Look Lab's door used to sit here and no longer does. It was a panel
		# of buttons, one per draft, and opening it showed nothing — every look it
		# switched between only appears under conditions the title screen does not
		# have (dusk, a crop in the basket, a station never used). The designer's
		# verdict, 2026-09-02: *"The text overfills the buttons, and I don't know
		# what it means... Each step should draw a scenario under specific
		# conditions, and then quiz me."* All three of its questions were ruled on
		# 2026-09-01 and ship as the defaults, so nothing is waiting on it. The
		# switches themselves are unchanged and still in the pause menu, where the
		# farm is what you are looking at when one flips (`ui/menus.gd`), and the
		# registry behind them is still `systems/look_lab.gd`. What replaces the
		# door is a staged scenario, not a menu — Q-86 in `docs/DESIGNER_QUEUE.md`.
		# The Home door came out on the designer's word, 2026-09-15: "remove the
		# 'home' button from the main landing page menu." `ui/home_screen.tscn`
		# itself stays — it is a detached preview of the indoor room (T-37) and
		# the integration suite still instantiates and renders it — but nothing
		# on this menu opens it any more, and its button is gone with it.
		for b in [_make_sound_test_button(), _make_zoo_button()]:
			b.custom_minimum_size = Vector2(104, 34)
			debug_row.add_child(b)


func _big_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _style_button(btn: Button, bg: Color, border: Color, hover: Color) -> void:
	btn.add_theme_stylebox_override("normal", _big_button_style(bg, border))
	btn.add_theme_stylebox_override("hover", _big_button_style(hover, border))
	btn.add_theme_stylebox_override("pressed", _big_button_style(border, border))
	btn.add_theme_stylebox_override("focus", _big_button_style(hover, border))


# --- A farm's card ------------------------------------------------------------
#
# One card per farm, all three the same size and all three the full width of the
# column: this is a menu, so the cards are big stacked targets rather than rows.
# The colour and the emblem are the farm's identity (S-14) and carry more of the
# work than the words do, because the player this game is designed for cannot
# read them (S-7).

func _make_slot_card(n: int) -> Button:
	var look: Dictionary = SLOT_LOOKS[SaveSlots.clamp_slot(n) - 1]
	var has_farm := _slot_has_farm(n)

	var btn := Button.new()
	btn.name = "SlotCard%d" % n
	btn.custom_minimum_size = Vector2(CARD_W, SLOT_CARD_H)
	# An empty card is quieter than a farm that exists: same shape and the same
	# target, drawn back so the eye lands on the farms first.
	var bg: Color = look["bg"] if has_farm else Color(look["bg"]).darkened(0.45)
	var border: Color = look["border"] if has_farm else Color(look["border"]).darkened(0.35)
	_style_button(btn, bg, border, look["hover"])
	btn.pressed.connect(func(): _play_slot(n))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	btn.add_child(row)

	var emblem := SlotEmblem.new()
	emblem.name = "SlotEmblem%d" % n
	emblem.shape = int(look["shape"])
	emblem.tint = look["emblem"] if has_farm else Color(look["emblem"]).darkened(0.25)
	emblem.filled = has_farm
	emblem.custom_minimum_size = Vector2(52, 52)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(emblem)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	row.add_child(box)

	if has_farm:
		_fill_farm_card(box, n)
		# The one destructive control on this screen, and the only small target on
		# it on purpose: it replaces a farm, and it asks first.
		btn.add_child(_make_slot_new_farm_button(n))
	else:
		_fill_empty_card(box, look)
	return btn


# Left-aligned, unlike the empty card's centred invitation: the corner control
# sits in the card's top right, and a centred headline runs into it.
func _fill_farm_card(box: VBoxContainer, n: int) -> void:
	var summary := _slot_summary(n)

	var day := Label.new()
	day.text = tr("Day %d") % summary.get("day", 1)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	day.add_theme_font_size_override("font_size", 24)
	day.add_theme_color_override("font_color", Color.WHITE)
	day.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(day)

	var stats := Label.new()
	stats.text = tr("%dg    %d shipped    %d crows shooed") % [
		summary.get("gold", 0), summary.get("shipped", 0), summary.get("scared", 0)]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats.add_theme_font_size_override("font_size", 13)
	stats.add_theme_color_override("font_color", Color(0.90, 0.95, 0.88))
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)

	var progress := Label.new()
	if summary.get("phase1", false):
		progress.text = tr("Homestead complete")
		progress.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	else:
		# Same two counters the sim uses for the phase-1 proof (Q-12), so the
		# card shows real progression rather than a decorative number.
		progress.text = tr("Homestead %d/%d crops %d/%d crows") % [
			min(summary.get("shipped", 0), SimWorld.PHASE1_SHIPPED_TARGET),
			SimWorld.PHASE1_SHIPPED_TARGET,
			min(summary.get("scared", 0), SimWorld.PHASE1_SCARED_TARGET),
			SimWorld.PHASE1_SCARED_TARGET]
		progress.add_theme_color_override("font_color", Color(0.80, 0.88, 0.78))
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	progress.add_theme_font_size_override("font_size", 12)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(progress)


func _fill_empty_card(box: VBoxContainer, look: Dictionary) -> void:
	var plus := Label.new()
	plus.text = "+"
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.add_theme_font_size_override("font_size", 30)
	plus.add_theme_color_override("font_color", Color(look["emblem"]))
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(plus)

	var word := Label.new()
	word.text = tr("New farm")
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_font_size_override("font_size", 14)
	word.add_theme_color_override("font_color", Color(0.86, 0.90, 0.86))
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(word)


# Corner control, over the card rather than inside its row, so the farm's own
# figures keep the full width of the card to be read in.
func _make_slot_new_farm_button(n: int) -> Button:
	var btn := Button.new()
	btn.name = "SlotNewFarm%d" % n
	btn.text = tr("New farm")
	btn.add_theme_font_size_override("font_size", 11)
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -96
	btn.offset_top = 6
	btn.offset_right = -8
	btn.offset_bottom = 34
	btn.mouse_filter = Control.MOUSE_FILTER_STOP  # the card underneath must not also fire
	_style_button(btn, Color(0.10, 0.14, 0.12, 0.85), Color(0.62, 0.66, 0.60),
		Color(0.18, 0.22, 0.19, 0.95))
	btn.pressed.connect(func(): _open_confirm(n))
	return btn


# The shape half of a farm's identity: filled while the farm exists, an outline
# while the slot is empty. Drawn rather than drawn from art, because three flat
# shapes are what the recognition needs and a sprite would be three more files to
# keep in step with the palette above.
class SlotEmblem extends Control:
	var shape: int = 0
	var tint: Color = Color.WHITE
	var filled: bool = true

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.42
		var mid: Vector2 = size / 2.0
		var pts := PackedVector2Array()
		match shape:
			1:  # triangle, point up
				for i in 3:
					var a: float = -PI / 2.0 + TAU * i / 3.0
					pts.append(mid + Vector2(cos(a), sin(a)) * r * 1.15)
			2:  # square
				var h: float = r * 0.9
				pts.append(mid + Vector2(-h, -h))
				pts.append(mid + Vector2(h, -h))
				pts.append(mid + Vector2(h, h))
				pts.append(mid + Vector2(-h, h))
			_:  # circle
				for i in 28:
					var a: float = TAU * i / 28.0
					pts.append(mid + Vector2(cos(a), sin(a)) * r)
		if filled:
			draw_colored_polygon(pts, tint)
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, tint, 3.0, true)


# --- Credits (all builds; a licence obligation, not a nicety) -----------------

# Kept in one place and sourced from CREDITS.md, which is the provenance record.
# If an asset's licence changes, both must change together.
const CREDITS_TEXT := """Tiny Farm

Made with Godot Engine — MIT License
godotengine.org

MUSIC
"Wholesome" by Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0
creativecommons.org/licenses/by/4.0/

SOUND
Original effects synthesized for this project.
Harvest sounds by Valenspire (Freesound), CC0 1.0.

ART
Pixel art generated with Retro Diffusion
and post-processed for this project.

Full provenance for every asset is recorded in
CREDITS.md in the project repository."""


func _make_credits_button() -> Button:
	var btn := Button.new()
	btn.name = "CreditsButton"
	btn.text = tr("Credits")
	btn.custom_minimum_size = Vector2(110, 30)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 12)
	_style_button(btn, Color(0.12, 0.26, 0.15), Color(0.42, 0.55, 0.40), Color(0.17, 0.33, 0.20))
	btn.pressed.connect(_open_credits)
	return btn


func _open_credits() -> void:
	if _confirm_open:
		return
	_confirm_open = true  # also blocks tap-anywhere while the panel is up
	_set_attract_paused(true)

	_confirm_layer = Control.new()
	_confirm_layer.name = "CreditsLayer"
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.09, 0.07, 1.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_layer.add_child(dim)

	# Scrolled, because the text outgrows a phone screen in portrait and an
	# attribution nobody can reach is not an attribution.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_top = 16
	scroll.offset_right = -24
	scroll.offset_bottom = -60
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_confirm_layer.add_child(scroll)

	var body := Label.new()
	body.text = CREDITS_TEXT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.90, 0.95, 0.88))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var back := Button.new()
	back.name = "CreditsBackButton"
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(150, 40)
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.offset_left = -75
	back.offset_top = -50
	back.offset_right = 75
	back.offset_bottom = -10
	back.add_theme_font_size_override("font_size", 16)
	_style_button(back, Color(0.18, 0.42, 0.22), Color(1.0, 0.72, 0.15), Color(0.24, 0.52, 0.28))
	back.pressed.connect(_close_confirm)
	_confirm_layer.add_child(back)

	back.grab_focus()


# --- Sound test (debug builds) ------------------------------------------------

func _make_sound_test_button() -> Button:
	var btn := Button.new()
	btn.name = "SoundTestButton"
	btn.text = tr("Sound Test")
	btn.custom_minimum_size = Vector2(130, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 13)
	_style_button(btn, Color(0.13, 0.24, 0.30), Color(0.45, 0.62, 0.70), Color(0.18, 0.32, 0.40))
	btn.pressed.connect(_open_sound_test)
	return btn


func _open_sound_test() -> void:
	if _confirm_open:
		return
	_confirm_open = true  # also blocks tap-anywhere while the panel is up
	_set_attract_paused(true)

	_confirm_layer = Control.new()
	_confirm_layer.name = "SoundTestLayer"
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.09, 0.07, 1.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_layer.add_child(dim)

	# The list outgrew a fixed-height box, which left the last entries off screen
	# with no way to reach them on a tablet. Scroll it instead.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 20
	scroll.offset_top = 16
	scroll.offset_right = -20
	scroll.offset_bottom = -16
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_confirm_layer.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	var head := Label.new()
	head.text = tr("Sound Test")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	box.add_child(head)

	var hint := Label.new()
	hint.text = tr("Tap a sound to hear it.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.78, 0.86, 0.76))
	box.add_child(hint)

	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	# Driven off AudioManager's own table so this list cannot drift from the game.
	var names: Array = AudioManager.sfx_streams.keys()
	names.sort()
	for n in names:
		var b := Button.new()
		b.text = String(n)
		b.custom_minimum_size = Vector2(184, 42)
		b.add_theme_font_size_override("font_size", 16)
		_style_button(b, Color(0.16, 0.34, 0.20), Color(0.62, 0.76, 0.58), Color(0.22, 0.44, 0.26))
		b.pressed.connect(func(): AudioManager.play_sfx(String(n)))
		grid.add_child(b)

	# Candidate takes, played straight off disk so the game's own table stays
	# clean. Listed explicitly rather than by scanning res://, which is not
	# reliable for imported assets inside an exported build.
	if not SFX_CANDIDATES.is_empty():
		var cand_player := AudioStreamPlayer.new()
		_confirm_layer.add_child(cand_player)
		var sep := Label.new()
		sep.text = tr("candidates (A/B against the above)")
		sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sep.add_theme_font_size_override("font_size", 12)
		sep.add_theme_color_override("font_color", Color(0.70, 0.80, 0.86))
		box.add_child(sep)

		var cgrid := GridContainer.new()
		cgrid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cgrid.columns = 2
		cgrid.add_theme_constant_override("h_separation", 8)
		cgrid.add_theme_constant_override("v_separation", 8)
		box.add_child(cgrid)

		for cand in SFX_CANDIDATES:
			var cb := Button.new()
			cb.text = String(cand)
			cb.custom_minimum_size = Vector2(184, 40)
			cb.add_theme_font_size_override("font_size", 15)
			_style_button(cb, Color(0.13, 0.24, 0.30), Color(0.45, 0.62, 0.70), Color(0.18, 0.32, 0.40))
			cb.pressed.connect(func():
				var stream = load("res://assets/audio/sfx/%s.wav" % cand)
				if stream != null:
					cand_player.stream = stream
					cand_player.play())
			cgrid.add_child(cb)

	var music := Button.new()
	music.name = "MusicToggle"
	music.text = tr("Music: on")
	music.custom_minimum_size = Vector2(184, 36)
	music.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	music.add_theme_font_size_override("font_size", 14)
	_style_button(music, Color(0.13, 0.24, 0.30), Color(0.45, 0.62, 0.70), Color(0.18, 0.32, 0.40))
	music.pressed.connect(func():
		# Mute the bed so a short SFX can be judged on its own.
		var p: AudioStreamPlayer = AudioManager.bgm_player
		if p == null:
			return
		if p.playing:
			p.stop()
			music.text = tr("Music: off")
		else:
			p.play()
			music.text = tr("Music: on"))
	box.add_child(music)

	var back := Button.new()
	back.name = "SoundTestBackButton"
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(150, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 16)
	_style_button(back, Color(0.18, 0.42, 0.22), Color(1.0, 0.72, 0.15), Color(0.24, 0.52, 0.28))
	back.pressed.connect(_close_confirm)
	box.add_child(back)

	back.grab_focus()


# --- The zoo (debug builds) ---------------------------------------------------
#
# T-33, the designer 2026-09-01: *"Some sort of way for us to experience the new
# entities in the game... a 'zoo' of the entities we've created, and a way to
# select or add them in a useful way just to see them doing their thing."*
#
# The whole bestiary ships behind `PER_DAY := 0`, so nobody has ever seen a rabbit
# outside a test's assertions. This is that door, and it is deliberately the Sound
# Test's own door — same gate, same row, same corner — because there is one
# place in this game where things go to be looked at.
#
# It changes scene rather than opening a panel: the zoo is a second farm with a
# clock of its own, and the attract loop is already running one behind this menu.

func _make_zoo_button() -> Button:
	var btn := Button.new()
	btn.name = "ZooButton"
	btn.text = tr("Zoo")
	btn.custom_minimum_size = Vector2(130, 34)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 13)
	_style_button(btn, Color(0.13, 0.24, 0.30), Color(0.45, 0.62, 0.70), Color(0.18, 0.32, 0.40))
	btn.pressed.connect(_open_zoo)
	return btn


func _open_zoo() -> void:
	if _confirm_open:
		return
	InputManager.has_click = false
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://ui/zoo_screen.tscn")


# T-37: the home, a scene-changing door on the Zoo's pattern.
# --- New Farm confirmation ----------------------------------------------------
#
# One dialog, asked about one farm: the slot it was opened from is the slot it
# replaces, and it says which farm that is in the only terms the screen has —
# what day it had reached.

func _open_confirm(n: int) -> void:
	if _confirm_open:
		return
	_confirm_open = true
	_confirm_slot = n
	_set_attract_paused(true)  # one moving thing at a time

	_confirm_layer = Control.new()
	_confirm_layer.name = "ConfirmLayer"
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow taps behind it
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_layer.add_child(dim)

	# Solid card behind the prompt: dimming alone left the farm's card bleeding
	# through the words, which is the last place we want a legibility problem.
	# Taller than it was by the height of the emblem below, which names the farm
	# being replaced before the sentence does.
	var backing := Panel.new()
	backing.set_anchors_preset(Control.PRESET_CENTER)
	backing.anchor_left = 0.5
	backing.anchor_top = 0.5
	backing.anchor_right = 0.5
	backing.anchor_bottom = 0.5
	backing.offset_left = -190
	backing.offset_top = -128
	backing.offset_right = 190
	backing.offset_bottom = 128
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing_style := StyleBoxFlat.new()
	backing_style.bg_color = Color(0.09, 0.16, 0.11, 0.98)
	backing_style.border_color = Color(0.55, 0.68, 0.52)
	backing_style.set_border_width_all(2)
	backing_style.set_corner_radius_all(12)
	backing.add_theme_stylebox_override("panel", backing_style)
	_confirm_layer.add_child(backing)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -170
	box.offset_top = -110
	box.offset_right = 170
	box.offset_bottom = 110
	box.add_theme_constant_override("separation", 10)
	_confirm_layer.add_child(box)

	# Which farm this is about, in the terms the cards taught: its own colour and
	# its own shape, before any of the words.
	var look: Dictionary = SLOT_LOOKS[SaveSlots.clamp_slot(_confirm_slot) - 1]
	var emblem := SlotEmblem.new()
	emblem.name = "ConfirmEmblem"
	emblem.shape = int(look["shape"])
	emblem.tint = look["emblem"]
	emblem.custom_minimum_size = Vector2(44, 44)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(emblem)

	var warn := Label.new()
	warn.text = tr("Start a new farm?")
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.add_theme_font_size_override("font_size", 24)
	warn.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(warn)

	var detail := Label.new()
	detail.text = tr("Your Day %d farm will be replaced.") % _slot_summary(_confirm_slot).get("day", 1)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	box.add_child(detail)

	var keep := Button.new()
	keep.name = "KeepFarmButton"
	keep.text = tr("Keep my farm")
	keep.custom_minimum_size = Vector2(220, 46)
	keep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	keep.add_theme_font_size_override("font_size", 18)
	_style_button(keep, Color(0.18, 0.42, 0.22), Color(1.0, 0.72, 0.15), Color(0.24, 0.52, 0.28))
	keep.pressed.connect(_close_confirm)
	box.add_child(keep)

	var wipe := Button.new()
	wipe.name = "ConfirmNewFarmButton"
	wipe.text = tr("Yes, start over")
	wipe.custom_minimum_size = Vector2(180, 36)
	wipe.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wipe.add_theme_font_size_override("font_size", 14)
	_style_button(wipe, Color(0.38, 0.18, 0.14), Color(0.72, 0.42, 0.34), Color(0.46, 0.22, 0.17))
	wipe.pressed.connect(_on_new_farm)
	box.add_child(wipe)

	keep.grab_focus()  # the safe option is the default


func _close_confirm() -> void:
	_confirm_open = false
	_set_attract_paused(false)
	if _confirm_layer:
		_confirm_layer.queue_free()
		_confirm_layer = null


func _gui_input(event: InputEvent) -> void:
	# Tap-anywhere still resumes a farm (the kid-friendly default from Q-8's
	# ruling) — the last one played, which is also the one showing behind the
	# menu. Never while the confirmation is up, and never when all three slots
	# are empty, where a tap has no farm to mean.
	if _confirm_open or _resume_slot <= 0:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_play_slot(_resume_slot)
	elif event is InputEventScreenTouch and event.pressed:
		accept_event()
		_play_slot(_resume_slot)
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		_play_slot(_resume_slot)


func _on_new_farm() -> void:
	# Park the farm being replaced first: an accidental new farm would otherwise
	# destroy it at the first sleep. The copies stay inside that farm's own
	# directory, so the other two slots are untouched and a rescue is a rename.
	var n := _confirm_slot
	choose_slot(n)
	if _slot_has_farm(n):
		DirAccess.copy_absolute(GameState.save_path, GameState.save_path + ".bak")
		if FileAccess.file_exists(GameState.replay_path):
			DirAccess.copy_absolute(GameState.replay_path, GameState.replay_path + ".bak")
	start_game(false)


func start_game(load_save: bool) -> void:
	print("Starting game... (continue=%s)" % load_save)
	GameState.pending_load = load_save
	if not load_save:
		GameState.reset()
	InputManager.has_click = false
	AudioManager.play_sfx("click")

	# Q-103 item 5: a bare scene change cuts; this fades to the sky colour
	# first (main.gd fades the other half of it away once the farm is
	# there — `GameState.pending_boot_fade`). Headless has nothing to show a
	# fade on and no reason to wait on one.
	if DisplayServer.get_name() != "headless":
		GameState.pending_boot_fade = true
		var cover := ColorRect.new()
		cover.name = "TapFadeCover"
		cover.color = BOOT_SKY_COLOUR
		cover.color.a = 0.0
		cover.set_anchors_preset(Control.PRESET_FULL_RECT)
		cover.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(cover)
		var tw := create_tween()
		tw.tween_property(cover, "color:a", 1.0, TAP_FADE_OUT_SEC)
		await tw.finished
		if not is_instance_valid(self):
			return

	var err = get_tree().change_scene_to_file("res://main.tscn")
	if err != OK:
		print("Failed to change scene! Error code: ", err)

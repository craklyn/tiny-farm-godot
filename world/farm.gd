# farm.gd — Renderer + facade over SimWorld (M2)
# Grid truth lives in systems/sim/sim_world.gd; this node draws it with
# sprite atlases and forwards the old farm API to the sim so call sites
# (player, entities, ActionRouter, Pathfinding, tests) are unchanged.
extends Node2D

const TILE_SIZE := 16
const EGG_SIZE := TILE_SIZE / 2.0  # half a tile, centred (see the egg draw below)
const MAP_WIDTH := SimWorld.MAP_WIDTH
const MAP_HEIGHT := SimWorld.MAP_HEIGHT

var sim: SimWorld = SimWorld.new()
var replay: ReplayLog = null  # set via start_replay_log(); records every ok action
var trace: SessionTrace = null  # diagnostic stream; records refusals too (see systems/session_trace.gd)

# Failures that are not the player's mistake and must not be answered as one.
# They are still recorded in the trace — knowing she tapped the well eight times
# is useful — they simply do not wobble or play the nope sound.
const BENIGN_FAILURES := { "can_already_full": true, "nothing_to_sell": true }
var generate_on_ready := true  # main disables this when a save restore is pending

# The state this farm belongs to. Defaults to the GameState autoload lazily, the
# same as `player.gd`'s, and for the same reason: the title screen's attract loop
# (T-16 / Q-40) renders a second farm that must not touch the player's real
# state. `advance_day()` read the live autoload's weather through the scene root,
# which is one of the four couplings finding F-4 named — this closes it.
var gs: Node = null

# Silences the feedback cues. The attract farm must not tick, beep or play the
# nope sound into a title screen the player is not playing.
var mute_feedback := false

# Facade views over sim truth (same Array references — in-place mutation works)
var tiles: Array[Array]:
	get:
		return sim.tiles
var objects: Array[Array]:
	get:
		return sim.objects

# Sprite resources
var tileset_texture: Texture2D
var crops_texture: Texture2D

# Quad regions (Rect2 for atlas lookups)
var tile_regions: Dictionary = {}     # state_name -> Rect2
var crop_regions: Dictionary = {}     # crop_type -> { stage -> Rect2 }
var object_regions: Dictionary = {}   # object_name -> Rect2
var glyph_regions: Dictionary = {}    # T-28 glyph key -> [texture, Rect2]

# T-27 box 5, treatment C: which of the cot's two cells to draw — the made bed or
# the turned-down one. Pushed in rather than worked out here, because this file
# has no GameState and must not gain one (finding F-4); `main.gd` sets it from the
# same daylight update the sky's tint comes from. Default false, so every other
# renderer of a farm (the attract loop, the replay viewer) draws the made bed
# without knowing this exists.
var cot_turned_down: bool = false

# T-27 (box 1), the ground's half: **the field she fell asleep in, held until the
# screen is black.**
#
# The sleep Action lands at the tap and must (D-8) — `main.gd` applies it before a
# single frame of the transition is drawn — so `advance_day` has already washed
# every watered flag off the farm and moved every crop on a day while she is still
# watching a lit world. Reported from play 2026-09-01: *"when you go to sleep, the
# ground re-renders as dry BEFORE the fade out. Should wait until screen is
# black."* The sky already had exactly this treatment (`main.gd`'s
# `_freeze_daylight`, M2_5_PLAN §9), and for exactly this reason.
#
# So the *picture* of the tiles is frozen while the *sim* thaws underneath it: a
# snapshot taken at the tap, drawn for the length of the fade, dropped under the
# black. Nothing here delays, gates or reorders anything the sim does — it is a
# copy of four fields per tile, taken once per day transition and never per frame,
# and any renderer that never asks for it (the attract loop, the replay viewer)
# behaves exactly as before.
var _held_tiles: Array = []


## Hold the current tile picture. Called at the sleep tap, alongside the sky's
## freeze; harmless to call twice (the first snapshot is the one she saw).
func hold_tile_look() -> void:
	if not _held_tiles.is_empty():
		return
	var snap: Array = []
	for ty in MAP_HEIGHT:
		var row: Array = []
		for tx in MAP_WIDTH:
			row.append(tiles[ty][tx].duplicate())
		snap.append(row)
	_held_tiles = snap
	queue_redraw()


## Let the ground catch up with the sim. Called under the black.
func release_tile_look() -> void:
	if _held_tiles.is_empty():
		return
	_held_tiles = []
	queue_redraw()


func is_tile_look_held() -> bool:
	return not _held_tiles.is_empty()


# What the *player* is currently looking at on this tile: the held snapshot while
# a day transition is fading out, sim truth every other frame of the game's life.
func tile_look(tx: int, ty: int) -> Dictionary:
	if _held_tiles.is_empty():
		return tiles[ty][tx]
	return _held_tiles[ty][tx]


func _ready() -> void:
	_load_textures()
	actors_node = Node2D.new()
	actors_node.name = "Entities"
	add_child(actors_node)
	if generate_on_ready:
		sim.generate()
	sync_actors()


# --- Actors, drawn from the registry (M2.5 WI-6) ------------------------------
#
# **Finding F-3 dies here.** Until now a hen existed because `main.gd` built a
# node, so every *other* renderer of the same sim — the title screen's attract
# loop, most obviously — showed a farm where the tiles tilled themselves and
# nobody was there. The registry has been sim truth since WI-2 and the brains
# have moved actors since WI-3; what was missing was a renderer that reads it.
# This is that: any farm node, in any scene, gives every registered actor a
# sprite and takes it away again when the sim says it has gone.
#
# **The player is the one exception and stays one.** Her node is the input device
# and the camera anchor, so `main.gd` still owns it and the render queue still
# finds it at `../Player`; her *position* joins sim truth from the other
# direction (tile-crossing events, see `note_player_walk` below).
#
# A species with no row here is simply not drawn — which is the honest state for
# anything whose art has not landed, and it is one line to change when it does.
const ACTOR_RENDERERS := {
	SpeciesDefs.NEIGHBOUR: "res://entities/neighbour.gd",
	SpeciesDefs.CHICKEN: "res://entities/chicken.gd",
	SpeciesDefs.CROW: "res://entities/crow.gd",
	SpeciesDefs.SPRINKLER: "res://entities/sprinkler.gd",
	# Both ants, one script: they differ by which cells of critters.png they draw
	# and how fast they walk, and both of those come off the species row
	# (M2.5 WI-8a/8b).
	SpeciesDefs.ANT_SCOUT: "res://entities/ant.gd",
	SpeciesDefs.ANT_FORAGER: "res://entities/ant.gd",
	# The rabbit and the kangaroo share a script as well as a brain: they differ
	# by a row of critters.png and a speed, and both come off the species row
	# (M2.5 WI-8c/8f).
	SpeciesDefs.RABBIT: "res://entities/grazer.gd",
	SpeciesDefs.KANGAROO: "res://entities/grazer.gd",
	SpeciesDefs.SONGBIRD: "res://entities/songbird.gd",
	# The mole draws one of three cells depending on whether it is under the farm,
	# and the worm draws one cell per tile of itself — the first actor in the game
	# whose sprite is not a sprite (M2.5 WI-8d/8e).
	SpeciesDefs.MOLE: "res://entities/mole.gd",
	SpeciesDefs.WORM: "res://entities/worm.gd",
	# One species, three configs — so one line, whichever setting a bot is on
	# (M2.5 WI-9). It draws from `bot.png`, which is `characters.png`'s layout on
	# purpose: a bot reuses the player's draw path verbatim.
	SpeciesDefs.BOT: "res://entities/bot.gd",
}

var actors_node: Node2D = null            # the sprites' parent, named "Entities"
var actor_nodes: Dictionary = {}          # actor_id -> Node2D


# Sprites for the actors the sim has, and no sprites for the actors it has not.
# Cheap and idempotent (it is O(registered actors), never O(map)), so callers
# pump it per frame rather than trying to catch every registry change: `main.gd`
# and `ui/attract_loop.gd` both do, and `advance_sim` does it for whoever else
# lets sim time pass.
func sync_actors() -> void:
	if actors_node == null:
		return
	for id in sim.actors.keys():
		var actor_id := String(id)
		if is_instance_valid(actor_nodes.get(actor_id, null)):
			continue
		var script_path: String = ACTOR_RENDERERS.get(sim.species_of(actor_id), "")
		if script_path == "":
			continue
		var node = load(script_path).new()
		node.name = "%s_%s" % [sim.species_of(actor_id), actor_id]
		node.init_actor(self, actor_id)
		actors_node.add_child(node)
		actor_nodes[actor_id] = node
	for id in actor_nodes.keys():
		var node = actor_nodes[id]
		if not is_instance_valid(node):
			actor_nodes.erase(id)
			continue
		if sim.has_actor(id):
			continue
		# The actor left the registry, so its sprite goes with it — unless the
		# sprite is still finishing an exit the sim has already recorded. The
		# neighbour is the case: she leaves the registry the instant the gate
		# opens (WI-2 deviation 3), and then walks off the map edge, which is the
		# whole visible payoff of the cold open. She frees herself when she gets
		# there.
		if node.has_method("is_departing") and node.is_departing():
			continue
		node.queue_free()
		actor_nodes.erase(id)


# Every sprite, gone now — for a renderer that is starting the world over (the
# attract loop's loop round). Removed from the tree rather than only queued, so a
# resync in the same frame cannot draw two of anybody.
func clear_actors() -> void:
	for id in actor_nodes.keys():
		var node = actor_nodes[id]
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	actor_nodes.clear()


# The farmer's node, for the sprites that have to notice her (the crow's spook
# radius). Looked up by path rather than injected because *every* farm renderer
# has one at this path, which is what makes an entity work in the attract loop
# and in the game without knowing which it is in (design/11's coupling note).
func player_node() -> Node2D:
	return get_node_or_null("../Player")


var dirt_texture: Texture2D
# T-32: the yard's ground. Same 3x3 sheet as the grass, same noise pattern, three
# different colours (tools/gen_yard_ground.py) — so the fence line reads as a
# boundary between two kinds of land rather than as a seam in one.
var yard_texture: Texture2D
var biomes_texture: Texture2D
var furniture_texture: Texture2D
var chest_texture: Texture2D
var animals_texture: Texture2D
var tool_icons_texture: Texture2D

func _load_textures() -> void:
	# Generated sheets (see CREDITS.md — AI-generated via Retro Diffusion).
	# terrain_grass: 3x3 of the seamless grass tile; draw code reads (16,16).
	# terrain_dirt: one tile per neighbour mask (world/autotile.gd), watered at +16 cols.
	tileset_texture = load("res://assets/sprites/generated/terrain_grass.png")
	dirt_texture = load("res://assets/sprites/generated/terrain_dirt.png")
	# terrain_yard: terrain_grass's own pattern in the yard's colours (T-32).
	yard_texture = load("res://assets/sprites/generated/terrain_yard.png")
	crops_texture = load("res://assets/sprites/generated/crops.png")
	biomes_texture = load("res://assets/sprites/generated/obstacles.png")
	furniture_texture = load("res://assets/sprites/generated/objects.png")
	chest_texture = furniture_texture
	animals_texture = load("res://assets/sprites/generated/animals.png")
	tool_icons_texture = load("res://assets/sprites/tool_icons.png")

	# Tile regions (obstacles.png: rock, log, weed, tree, fence, hedge, gates)
	tile_regions["obstacle_rock"] = Rect2(0 * 16, 0, 16, 16)
	tile_regions["obstacle_log"] = Rect2(1 * 16, 0, 16, 16)
	tile_regions["obstacle_weed"] = Rect2(2 * 16, 0, 16, 16)
	tile_regions["border"] = Rect2(2 * 16, 0, 16, 16)
	# T-8 (Q-34): the boundary is the design's real content, so it has to be a
	# thing she can see. Closed and open gates are different pictures, because
	# "closed became open" is the cheapest celebration in the game.
	tile_regions["obstacle_tree"] = Rect2(3 * 16, 0, 16, 16)
	tile_regions[WorldLayout.FENCE] = Rect2(4 * 16, 0, 16, 16)
	tile_regions[WorldLayout.HEDGE] = Rect2(5 * 16, 0, 16, 16)
	tile_regions[WorldLayout.GATE_CLOSED] = Rect2(6 * 16, 0, 16, 16)
	tile_regions[WorldLayout.GATE_OPEN] = Rect2(7 * 16, 0, 16, 16)

	# Crop regions (crops.png: row 0 wheat, row 1 tomato, row 3 pea, 4 visual
	# stages each; row 2 is the shop iconography — see menus.gd). The pea ships as
	# an ordinary crop (Q-55, M2.5 WI-10) and nothing plants one yet, so this cell
	# binding is what stops the first thing that does from growing invisibly.
	crop_regions["wheat"] = {}
	crop_regions["tomato"] = {}
	crop_regions["pea"] = {}
	for stage in 4: crop_regions["wheat"][stage] = Rect2(stage * 16, 0 * 16, 16, 16)
	for stage in 4: crop_regions["tomato"][stage] = Rect2(stage * 16, 1 * 16, 16, 16)
	for stage in 4: crop_regions["pea"][stage] = Rect2(stage * 16, 3 * 16, 16, 16)

	# Object regions map (objects.png: cot, well, seed_box 16x32; bin 16x16)
	# Format: object_name -> [texture, rect]
	object_regions["cot"] = [furniture_texture, Rect2(0 * 16, 0, 16, 32)]
	# T-27 box 5, treatment C. Not an object the sim knows about — no verb, no
	# footprint, nothing in `OBJECT_POSITIONS`: it is cell 0 with its blanket
	# pulled back, and `cot_turned_down` chooses between the two below.
	object_regions["cot_turned_down"] = [furniture_texture, Rect2(7 * 16, 0, 16, 32)]
	object_regions["well"] = [furniture_texture, Rect2(1 * 16, 0, 16, 32)]
	object_regions["shipping_bin"] = [chest_texture, Rect2(3 * 16, 16, 16, 16)]
	object_regions["seed_box"] = [furniture_texture, Rect2(2 * 16, 0, 16, 32)]
	object_regions["scarecrow"] = [crops_texture, Rect2(2 * 16, 2 * 16, 16, 16)]
	object_regions["acorn"] = [furniture_texture, Rect2(4 * 16, 16, 16, 16)]
	# T-9: a tool lying at its gate is drawn with the icon the HUD already uses
	# for it, so what she picks up and what she then holds are the same picture.
	# No new art needed for either.
	object_regions["tool_axe"] = [tool_icons_texture, Rect2(1 * 16, 0, 16, 16)]
	object_regions["tool_pickaxe"] = [tool_icons_texture, Rect2(2 * 16, 0, 16, 16)]

	# T-28's pictograms, resolved from `StationPresentation.GLYPH_ATLAS` — which
	# is pure data, so the table can be asserted headlessly and the two renderers
	# that need these (the world overlay and the HUD) cannot disagree about which
	# cell a droplet is. Three of the five are pictures the game already spoke in:
	# the coin is T-12's shop icon, the can and the seed packet are the refusal
	# table's own (F-5). Only the droplet and the empty basket are new.
	for key in StationPresentation.GLYPH_ATLAS.keys():
		var entry: Dictionary = StationPresentation.GLYPH_ATLAS[key]
		var r: Array = entry["rect"]
		glyph_regions[key] = [
			tool_icons_texture if entry["sheet"] == "tools" else crops_texture,
			Rect2(r[0], r[1], r[2], r[3]),
		]


## `[texture, region]` for one of T-28's glyph keys, or `[]`.
func glyph(key: String) -> Array:
	return glyph_regions.get(key, [])


# --- Facade: forwards the old farm API to SimWorld ---------------------------

func start_replay_log(gen_seed: int) -> void:
	replay = ReplayLog.new()
	replay.start(gen_seed)


# `seed_value` is the seed the continued session runs under — the restored
# world's own `gen_seed` (M2.5 WI-5). Without it a replay of a continued session
# reproduces it under whatever seed the verifying process holds, which is not the
# one the player played.
func start_replay_log_from_save(save_data: Dictionary, seed_value: int = 0) -> void:
	replay = ReplayLog.new()
	replay.start_from_save(save_data, seed_value)


func start_trace(gen_seed: int, from_save: bool) -> void:
	trace = SessionTrace.new()
	trace.start(gen_seed, from_save)


# Let sim time pass, and record what the brains did with it (M2.5 WI-3).
#
# The sim decides; this turns the decisions into the same replay entries, trace
# lines and tile reactions that a tap through `apply_action` produces, so an
# action a crow took at tick 4,182 is in the log exactly as it would have been
# when its node took it. Recording stays here on purpose: layer 2 has never known
# that a `ReplayLog` exists, and it is not learning now.
#
# **Only the live game calls this** (`main.gd`'s clock pump). A replay must not:
# it advances the clock itself, through the ticks its entries are stamped with,
# and compares what the brains decide there against what was recorded (M2.5 WI-5,
# `ReplayLog._apply_v2`). Fast-forward tools advance the clock explicitly too.
func advance_sim(ticks: int, gs = null) -> void:
	if ticks <= 0:
		sync_actors()
		return
	for taken in sim.advance_ticks(ticks, gs):
		# **The dispatch tick, not the clock's** — this loop runs after the whole
		# advance has finished, so `sim.clock.tick` is already up to four ticks
		# past where the hen actually decided, and a replay recomputing her would
		# land on the earlier one and be called a divergence. The sim hands the
		# tick back with the Action for exactly this reason (M2.5 WI-5).
		#
		# `from_brain`: a tick-driven brain decided this, so a v2 replay
		# recomputes it rather than re-applying it — and asserts it got the same
		# answer. The recorded copy is Phase A's half of the net; Phase B is when
		# these stop being written at all.
		_record(taken["action"], taken["result"], int(taken["tick"]), true)
	# A brain may have spawned or despawned somebody in there — a crow arriving, a
	# crow leaving the map — so the sprites follow the registry before the frame
	# this ran in gets drawn.
	sync_actors()
	queue_redraw()


func apply_action(action: Dictionary, gs = null) -> Dictionary:
	var result := sim.apply_action(action, gs)
	_record(action, result, sim.clock.tick)
	return result


# The player's tile crossings, which are the one thing about her no rule can
# recompute (M2.5 WI-6, plan §3.3).
#
# Her pixel motion is deliberately untouched — D-8's spirit, and the plan's §4
# says her feel is not the movement engine's to change — so what joins sim truth
# is **tile occupancy, updated when she crosses a boundary**. Each crossing writes
# her registry entry and is recorded as a free-walk event, the shape WI-5 fixed
# and every reader already tolerates; `ReplayLog._apply_v2` applies them back, so
# a replay's registry lands where the session's did and `capture_canonical` can
# compare her like anybody else.
#
# Facing is written **only** from here, never from the many places presentation
# turns her to look at something: a turn taken while standing still is not a fact
# a replay could reproduce, and writing one would fail comparisons for a reason
# that says nothing about the farm.
func note_player_walk(event: String, dir: String, at: Vector2i) -> void:
	sim.set_actor_pos(SimWorld.ACTOR_PLAYER, at, dir)
	if replay != null:
		replay.record_walk(event, dir, at, sim.clock.tick)


# The bookkeeping every resolved action gets, whoever asked for it: the trace,
# the player's feedback, the replay entry and the tile's reaction. Split out of
# `apply_action` so that an action a brain took inside `advance_sim` lands in the
# log identically to one a tap produced (M2.5 WI-3).
func _record(action: Dictionary, result: Dictionary, at_tick: int,
		from_brain: bool = false) -> void:
	# Recorded whether or not it succeeded: a refused action is the interesting
	# half, and it is exactly what ReplayLog cannot carry.
	if trace != null:
		var t = action.get("target", Vector2i(-1, -1))
		trace.act(t if t is Vector2i else Vector2i(-1, -1),
			String(action.get("actor", "?")), String(action.get("verb", "?")),
			result.get("ok", false), String(result.get("reason", "")))
	# Not every failure is a refusal. A full watering can and an empty basket mean
	# "nothing to do here", and answering those with the nope sound and a wobble
	# teaches that a perfectly normal state is a malfunction — the opposite of the
	# problem the refusal feedback was added to solve.
	#
	# Staying quiet was the 2026-08-28 fix and it was only half right: T-18 (Q-42)
	# says the third state should *speak*, positively. So a benign failure now
	# acknowledges instead of either wobbling or saying nothing.
	if not result.get("ok", false) and String(action.get("actor", "")) == "player":
		var rt = action.get("target", null)
		var reason := String(result.get("reason", ""))
		if rt is Vector2i:
			if BENIGN_FAILURES.has(reason):
				acknowledge_at(rt, reason)
			else:
				refuse_at(rt, reason)

	if result.get("ok", false):
		if replay != null:
			# Stamped with the sim time it resolved at (format v2, M2.5 WI-5).
			# The clock is the sim's, not the frame's: this is the one number that
			# lets a replay put the world back in the state the actor decided
			# from, rather than in whatever state the action stream happened to
			# leave it in.
			replay.record(action, result, at_tick, from_brain)
		# D-8 tier (a): the tile reacts so a tap has a visible consequence.
		# Presentation only — it runs *after* the action has already resolved and
		# can be dropped without touching sim truth or replay fidelity (S-3/S-5).
		if action.has("target"):
			react_at(action["target"])
		if String(action.get("verb", "")) == "sleep":
			_notify_day_turn()
		queue_redraw()


# A morning happened. Machines act *inside* the day turn (`Brain.day_actions`,
# M2.5 WI-10), so there is no tick for a renderer to notice one on — the sprinkler
# would water nine tiles and never be seen doing it. Told here, from the one place
# every resolved Action passes through, so it works whether the sleep came from a
# cot, from the cold open's day fade or from a replay's action stream.
func _notify_day_turn() -> void:
	for id in actor_nodes.keys():
		var node = actor_nodes[id]
		if is_instance_valid(node) and node.has_method("on_day_turn"):
			node.on_day_turn()


# --- Verb reactions (D-8 tier (a) prototype) ---------------------------------

const REACT_MS := 240.0
var _reactions: Dictionary = {}  # Vector2i -> start time in msec

# Refusals: a shake plus a floating picture of whatever she is missing. Wordless
# on purpose — the player who most needs this cannot read (S-7).
const REFUSE_MS := 620.0
var _refusals: Dictionary = {}  # Vector2i -> { "t": msec, "why": String }

# T-18/T-19 (Q-42): the third state's voice. A finished tile answers "yes, done"
# — a soft tick and a rising sparkle, never the refusal wobble, because wobbling
# at a good state teaches that success looks like failure.
const ACK_MS := 520.0
# [Playtest] T-28 treatment A's noun, in world pixels — a shade under a tile, so
# it reads as a label on the answer rather than as a second object in the farm.
const ACK_NOUN := 12.0
var _acks: Dictionary = {}  # Vector2i -> { "t": msec, "why": String }


func refuse_at(t: Vector2i, why: String) -> void:
	if mute_feedback:
		return
	_refusals[t] = { "t": Time.get_ticks_msec(), "why": why }
	set_process(true)
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("AudioManager"):
		Engine.get_main_loop().root.get_node("AudioManager").play_sfx("nope")


# Sideways wobble, decaying — deliberately unlike the success squash, which is
# vertical, so the two read as different answers rather than different amounts.
func _refuse_dx(tx: int, ty: int) -> float:
	var key := Vector2i(tx, ty)
	if not _refusals.has(key):
		return 0.0
	var e: float = (Time.get_ticks_msec() - _refusals[key]["t"]) / REFUSE_MS
	if e >= 1.0:
		return 0.0
	return sin(e * PI * 6.0) * 2.2 * (1.0 - e)


# What she is missing, drawn above the tile: the seed pouch, the watering can,
# or the bed. Anything else refuses without a picture (the shake still plays).
#
# Finding F-5 (2026-08-29): this used to match the sim's snake_case codes while
# ActionRouter.blocked_reason() returned human phrases ("no seeds", "watering can
# empty", "too tired"), so the two never met and **every router-level refusal
# lost its picture** — the wordless half of the feedback dropped on exactly the
# path built to end silent refusals. The router now speaks the sim's vocabulary
# and the table lives here as data, so the unit suite can assert that every code
# either side can emit has an icon and the mismatch cannot come back.
const REFUSE_ICONS := {
	"no_seeds":  { "sheet": "tools",   "rect": [5 * 16, 0, 16, 16] },
	"no_water":  { "sheet": "tools",   "rect": [4 * 16, 0, 16, 16] },
	"no_energy": { "sheet": "objects", "rect": [0, 0, 16, 32] },
}


func _refuse_icon(why: String) -> Array:
	var entry: Dictionary = REFUSE_ICONS.get(why, {})
	if entry.is_empty():
		return []
	var r: Array = entry["rect"]
	var tex: Texture2D = tool_icons_texture if entry["sheet"] == "tools" else furniture_texture
	return [tex, Rect2(r[0], r[1], r[2], r[3])]


# T-18: a small positive cue on a tile that is already in the state she wanted.
# Visually distinct from BOTH the success squash (vertical, on the tile itself)
# and the refusal wobble (sideways, with the nope sound): this is a soft ring and
# a rising sparkle, and its sound is the quiet UI tick rather than the harvest
# chime — deliberately non-rewarding, so repeated tapping is answered rather than
# farmed for stimulation.
#
# T-19 uses the same cue at completion time (`with_sound = false`, because the
# verb's own sound is already playing): the moment a tile becomes done for the
# day, it says so where she is looking.
func acknowledge_at(t, why: String, with_sound: bool = true) -> void:
	if not (t is Vector2i):
		return
	if mute_feedback:
		return
	_acks[t] = { "t": Time.get_ticks_msec(), "why": why }
	set_process(true)
	if with_sound and Engine.get_main_loop() and Engine.get_main_loop().root.has_node("AudioManager"):
		Engine.get_main_loop().root.get_node("AudioManager").play_sfx("click")


func react_at(t) -> void:
	if t is Vector2i:
		_reactions[t] = Time.get_ticks_msec()
		set_process(true)


func _process(_delta: float) -> void:
	# Only runs while a reaction is in flight; cost scales with acted tiles, not
	# map area (ARCHITECTURE guardrail).
	if _reactions.is_empty() and _refusals.is_empty() and _acks.is_empty():
		set_process(false)
		return
	var now := Time.get_ticks_msec()
	for key in _reactions.keys():
		if now - _reactions[key] > REACT_MS:
			_reactions.erase(key)
	for key in _refusals.keys():
		if now - _refusals[key]["t"] > REFUSE_MS:
			_refusals.erase(key)
	for key in _acks.keys():
		if now - _acks[key]["t"] > ACK_MS:
			_acks.erase(key)
	queue_redraw()


# 0 at rest, rising to 1 mid-reaction and back — a single squash-and-settle.
func _react_k(tx: int, ty: int) -> float:
	var key := Vector2i(tx, ty)
	if not _reactions.has(key):
		return 0.0
	var e: float = (Time.get_ticks_msec() - _reactions[key]) / REACT_MS
	if e >= 1.0:
		return 0.0
	return sin(e * PI)


# Squash horizontally and settle vertically, keeping the tile's base planted.
func _react_rect(px: int, py: int, k: float, h: float = TILE_SIZE, dx: float = 0.0) -> Rect2:
	if k <= 0.0:
		return Rect2(px + dx, py + (TILE_SIZE - h), TILE_SIZE, h)
	var w := TILE_SIZE * (1.0 + 0.22 * k)
	var nh := h * (1.0 - 0.14 * k)
	return Rect2(px + dx - (w - TILE_SIZE) / 2.0, py + (TILE_SIZE - nh), w, nh)


func get_tile(tx: int, ty: int) -> Dictionary:
	return sim.get_tile(tx, ty)


func get_crop_type(tx: int, ty: int) -> String:
	return sim.get_crop_type(tx, ty)


func get_object(tx: int, ty: int) -> String:
	return sim.get_object(tx, ty)


func is_protected_by_scarecrow(tx: int, ty: int) -> bool:
	return sim.is_protected_by_scarecrow(tx, ty)


func is_walkable(tx: int, ty: int) -> bool:
	return sim.is_walkable(tx, ty)


func set_tile_state(tx: int, ty: int, new_state: String, crop_type: String = "") -> void:
	sim.set_tile_state(tx, ty, new_state, crop_type)
	queue_redraw()


func water_tile(tx: int, ty: int) -> void:
	sim.water_tile(tx, ty)
	queue_redraw()


func advance_day() -> void:
	var weather := "sunny"
	var state := _state()
	if state != null:
		weather = String(state.weather)
	# The state goes through too, so this facade's day turn is the gateway's day
	# turn: machines fire at the day turn and they act through `apply_action`,
	# which needs it (M2.5 WI-10).
	sim.advance_day(weather, state)
	_notify_day_turn()
	sync_actors()
	queue_redraw()


# The GameState this farm belongs to — the injected one, or the autoload. Public
# because the entity renderers need it: a crow reporting its fright to the
# `GameState` *autoload* would spend the player's real farm from the title
# screen's attract loop, which is the T-16 hazard scenario K exists to catch.
func state() -> Node:
	return _state()


func _state() -> Node:
	if gs != null:
		return gs
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("GameState"):
		return Engine.get_main_loop().root.get_node("GameState")
	return null


# Out-of-bounds counts as not-soil, so plots edge correctly against the map border.
func _is_soil_at(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= MAP_WIDTH or ty >= MAP_HEIGHT:
		return false
	return Autotile.is_soil(tile_look(tx, ty).state)


func _draw() -> void:
	var render_queue: Array[Dictionary] = []

	for ty in MAP_HEIGHT:
		for tx in MAP_WIDTH:
			# Held while a day transition fades out, live every other frame — see
			# `hold_tile_look()`. Everything below reads the picture through this,
			# so the ground, its edges and the crops standing on it can never
			# disagree about which day they are showing.
			var tile: Dictionary = tile_look(tx, ty)
			var px := tx * TILE_SIZE
			var py := ty * TILE_SIZE
			var k := _react_k(tx, ty)
			var shake := _refuse_dx(tx, ty)

			# Draw the ground background always. Grass everywhere, except the yard,
			# which is made of its own ground (T-32) and draws the same 16x16 cell
			# from its own sheet — no autotiling, no edge cases: two flat noise
			# tiles that happen to meet at the fence.
			var ground_tex: Texture2D = yard_texture if tile.state == WorldLayout.YARD else tileset_texture
			draw_texture_rect_region(ground_tex, Rect2(px, py, TILE_SIZE, TILE_SIZE), Rect2(16, 16, 16, 16))

			# Draw tilled soil, edge-matched to its neighbours (see world/autotile.gd)
			if Autotile.is_soil(tile.state):
				var mask := Autotile.compute_mask(
					_is_soil_at(tx, ty - 1), _is_soil_at(tx + 1, ty - 1),
					_is_soil_at(tx + 1, ty), _is_soil_at(tx + 1, ty + 1),
					_is_soil_at(tx, ty + 1), _is_soil_at(tx - 1, ty + 1),
					_is_soil_at(tx - 1, ty), _is_soil_at(tx - 1, ty - 1))
				# Which soil is drawn wet is `Autotile.draws_wet` — the picture rule,
				# stated once, in the pure file the headless suite can hold to
				# account (Q-52 for why bare tilled ground is dry even when the rain
				# has marked it; the 2026-09-01 report for why `ready` is wet).
				var coord := Autotile.atlas_coord(mask,
					Autotile.draws_wet(tile.state, tile.watered_today))
				# Ground stays flush: squashing it opens seams to the grass beneath.
				# Only things standing on the soil react (crops, obstacles).
				draw_texture_rect_region(dirt_texture, Rect2(px + shake, py, TILE_SIZE, TILE_SIZE),
					Rect2(coord.x * 16, coord.y * 16, 16, 16))

			# Queue obstacles and boundaries
			if tile.state in ["border", "obstacle_rock", "obstacle_log", "obstacle_weed",
					"obstacle_tree", WorldLayout.FENCE, WorldLayout.HEDGE,
					WorldLayout.GATE_CLOSED, WorldLayout.GATE_OPEN]:
				var region: Rect2 = tile_regions.get(tile.state, Rect2())
				if region.size.x > 0:
					var ob_rect := _react_rect(px, py, k, TILE_SIZE, shake)
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(biomes_texture, ob_rect, region)
					})

			# Queue crops
			if tile.state in ["seeded", "growing", "ready"]:
				# `CropDefs.get_visual_stage()` maps however many growth days a crop
				# takes onto the four cells the sheet actually has. This used to
				# clamp by hand and only for wheat, so a **tomato** — which takes
				# five days and is ready at stage 5 — drew nothing at all from
				# stage 4 onward: an invisible plant that could still be watered
				# and eventually harvested. Reported from play 2026-08-30 as "a
				# couple tiles didn't show anything planted, but they were
				# waterable, and eventually they were harvested".
				var stage: int = CropDefs.get_visual_stage(tile.crop_type, tile.growth_stage)
				var region: Rect2 = crop_regions.get(tile.crop_type, {}).get(stage, Rect2())
				if region.size.x > 0:
					var crop_rect := _react_rect(px, py, k, TILE_SIZE, shake)
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(crops_texture, crop_rect, region)
					})

				# T-28, satisfied treatment B: **the state shows before the tap.**
				# Thirteen of the eighteen "already done" taps in the gate session
				# were the watering can over a crop that had already had its water,
				# and the only way to find that out was to ask. A crop that has been
				# watered today wears a droplet, so the answer is on the tile before
				# the question is. Also a candidate answer to T-18's open box
				# ("watered soil legible without tapping"), which is why it is drawn
				# on the *crop* rather than on the soil: rain marks bare tilled
				# ground watered too, and that is exactly the lie the 2026-08-30
				# session caught.
				if StationPresentation.satisfied == StationPresentation.SATISFIED_CHIP \
						and tile.watered_today and tile.state != "ready":
					var wart: Array = glyph(StationPresentation.GLYPH_DROPLET)
					if not wart.is_empty():
						var wrect := Rect2(px + TILE_SIZE - 7.0 + shake, py + 0.5, 6.0, 6.0)
						render_queue.append({
							"y": py + 0.5,
							"draw": func(): draw_texture_rect_region(
								wart[0], wrect, wart[1], Color(1, 1, 1, 0.92))
						})

			# Queue objects
			var obj: String = objects[ty][tx]
			if obj == "egg" or obj == "acorn":
				# Drawn at half a tile and centred: at full tile size it read as
				# boulder-sized next to the chicken that laid it. The tap target is
				# unaffected — taps resolve by tile coordinate, not by sprite bounds,
				# so this shrinks the picture without shrinking what she can hit.
				var egg_rect := Rect2(
					px + (TILE_SIZE - EGG_SIZE) / 2.0,
					py + (TILE_SIZE - EGG_SIZE) / 2.0,
					EGG_SIZE, EGG_SIZE)
				var small_data: Array = object_regions.get(obj, [animals_texture, Rect2(11 * 16, 0, 16, 16)])
				var small_tex: Texture2D = small_data[0]
				var small_reg: Rect2 = small_data[1]
				render_queue.append({
					"y": py,
					"draw": func():
						draw_texture_rect_region(small_tex, egg_rect, small_reg)
				})
			elif obj != "":
				# T-27 box 5 (treatment C): the same object, in its other state.
				# Only the picture changes — the tile still holds "cot", so taps,
				# saves, replays and `TALL_OBJECTS` are all untouched.
				var key: String = obj
				if obj == "cot" and cot_turned_down:
					key = "cot_turned_down"
				var obj_data = object_regions.get(key)
				if obj_data:
					var tex: Texture2D = obj_data[0]
					var region: Rect2 = obj_data[1]
					render_queue.append({
						"y": py,
						"draw": func(): draw_texture_rect_region(tex, Rect2(px, py - (region.size.y - TILE_SIZE), region.size.x, region.size.y), region)
					})

	# The done-tick, drawn above everything for the same reason the refusal icon
	# is: a soft ring opening outward with three sparkles rising off it. No shake,
	# no squash, no nope — the shapes say "yes" rather than "no" (Q-42).
	for key in _acks.keys():
		var ak: Vector2i = key
		var ae: float = (Time.get_ticks_msec() - _acks[key]["t"]) / ACK_MS
		if ae >= 1.0:
			continue
		var acx := ak.x * TILE_SIZE + TILE_SIZE / 2.0
		var acy := ak.y * TILE_SIZE + TILE_SIZE / 2.0
		var arad: float = 3.0 + 5.0 * ae
		var aa: float = 0.85 * (1.0 - ae)
		render_queue.append({
			"y": 100000.0,
			"draw": func():
				draw_arc(Vector2(acx, acy), arad, 0.0, TAU, 20,
					Color(0.62, 0.90, 1.0, aa), 1.4)
				for i in 3:
					var ang: float = -PI / 2.0 + (i - 1) * 0.7
					var d: float = 5.0 + 6.0 * ae
					var sp := Vector2(acx + cos(ang) * d, acy + sin(ang) * d - 3.0 * ae)
					draw_rect(Rect2(sp - Vector2(1.1, 1.1), Vector2(2.2, 2.2)),
						Color(0.95, 1.0, 1.0, aa))
		})

		# T-28, satisfied treatment A: **the answer names itself.** Same ring,
		# same sparkles, same tick, same volume — Q-42's judgement that a good
		# state is answered *less* rewardingly than a harvest is not up for
		# revision, and the designer's complaint is legibility, not loudness. What
		# it gains is a noun and a check: the can at the well, the empty basket at
		# the bin, the droplet on a crop that has had its water. The cue stops
		# saying only "yes" and starts saying "yes, *this*".
		if StationPresentation.satisfied == StationPresentation.SATISFIED_NOUN:
			var noun: String = StationPresentation.noun_for(String(_acks[key].get("why", "")))
			var nart: Array = glyph(noun)
			if not nart.is_empty():
				var nx := acx
				var ny: float = acy - ACK_NOUN - 2.0 - 3.0 * ae
				# The noun holds, then fades (the designer's condition on the T-28
				# pick, 2026-09-01: "okay if it shows then fades"). It used to ride
				# the ring's own envelope, which decays from the first frame — so
				# the one part of the cue that must be *recognized* spent most of
				# its life translucent. The ring and sparkles keep that envelope:
				# they are the motion, this is the message.
				var na: float = clampf((1.0 - ae) / 0.35, 0.0, 1.0)
				render_queue.append({
					"y": 100000.0,
					"draw": func():
						draw_texture_rect_region(nart[0],
							Rect2(nx - ACK_NOUN / 2.0, ny - ACK_NOUN / 2.0,
								ACK_NOUN, ACK_NOUN),
							nart[1], Color(1, 1, 1, na))
						# The check, in the cue's own blue-white. Two strokes, and
						# they are the constant of this grammar: whatever noun it
						# is beside, a tick means "already so" (the shop's ✕ is the
						# precedent for a glyph carrying a whole word — S-7 forbids
						# required reading, not marks).
						var tick := Vector2(nx + ACK_NOUN * 0.34, ny + ACK_NOUN * 0.30)
						var col := Color(0.72, 0.97, 1.0, na)
						draw_line(tick + Vector2(-2.6, -0.4), tick + Vector2(-0.9, 1.6), col, 1.4)
						draw_line(tick + Vector2(-0.9, 1.6), tick + Vector2(2.6, -2.4), col, 1.4)
				})

	# The missing-thing picture rides above everything, including the farmer —
	# it is the whole message, so it must never be the thing that gets occluded.
	for key in _refusals.keys():
		var rk: Vector2i = key
		var icon: Array = _refuse_icon(String(_refusals[key]["why"]))
		if icon.is_empty():
			continue
		var e: float = (Time.get_ticks_msec() - _refusals[key]["t"]) / REFUSE_MS
		if e >= 1.0:
			continue
		var tex: Texture2D = icon[0]
		var reg: Rect2 = icon[1]
		var rise := 6.0 * e
		var fade: float = 1.0 - max(0.0, (e - 0.55) / 0.45)
		var iw := 14.0
		var ih := iw * (reg.size.y / reg.size.x)
		var ix := rk.x * TILE_SIZE + (TILE_SIZE - iw) / 2.0
		var iy := rk.y * TILE_SIZE - ih - 3.0 - rise
		render_queue.append({
			"y": 100000.0,  # always last
			"draw": func(): draw_texture_rect_region(tex, Rect2(ix, iy, iw, ih), reg,
				Color(1, 1, 1, fade))
		})

	# Insert player into render queue if player exists
	var player = get_node_or_null("../Player")
	if player and player.has_method("queue_render"):
		player.queue_render(self, render_queue)

	# Insert every registered actor's sprite into the render queue (M2.5 WI-6).
	# These are this farm's own children now rather than a sibling node some other
	# scene happened to build, which is what makes the attract loop show a
	# populated farm without knowing anything about entities (finding F-3).
	if actors_node != null:
		for child in actors_node.get_children():
			if child.has_method("queue_render"):
				child.queue_render(self, render_queue)

	# Inject insertion order for stable sorting
	for i in range(render_queue.size()):
		if not render_queue[i].has("order"):
			render_queue[i]["order"] = i

	# Sort by Y-coordinate (using order as tie-breaker)
	render_queue.sort_custom(func(a, b): 
		if a.y == b.y:
			return a.order < b.order
		return a.y < b.y
	)

	# Execute drawing commands
	for entity in render_queue:
		entity.draw.call()



# sheep_gags.gd — what a stuck sheep does with forever (docs/design/18-sheep.md,
# "Stuck for good")
#
# Presentation only: everything here is read off the sim at its tick and decides
# nothing the sim keeps. Three gags make "she is stuck there for good" obvious:
#
#   * **The bald ring.** She grazes everything she can reach. Her own square and the
#     eight round it go to stubble one by one during her first day stopped
#     (`GRAZE_SECONDS` apart, from `content_since`), and to bare earth once she has
#     stood there a night (`nights_content`, counted by her brain at the day turn).
#     Only plain field grass is grazed: never a crop bed, the yard, a fence, a
#     building, or anything standing on a square. The picture is a 48px disc over
#     the three-by-three, cut square by square (`ring_pieces`), so where two rings
#     overlap the two discs simply join.
#   * **The neck stretch.** Once her ring is bare, every `STRETCH_EVERY_SECONDS` or
#     so her happy wiggle gives way to a happy reach toward a tuft just past it (a real
#     grass square two out, `stretch_target`), which gets her nowhere, and she
#     settles back looking smug (`stretch_frame`).
#   * **Birds perch on her.** A songbird drops in now and then, sits on her fleece a
#     while as if she were a cloud, and flies off; she gets a little heart when it
#     lands (`bird`). Cosmetic, the songbird's own sprite: not the sim's songbird
#     (which never visits a live farm) and not a crow (a pest she would not welcome).
#
# Every beat is a pure function of the sim tick and her id, so a paused game holds
# still, a replay shows the same moment at the same tick, and two stuck sheep never
# move in step. Nothing here walks the map: the only squares looked at are the nine
# round each stuck sheep and a handful beyond them.
class_name SheepGags
extends RefCounted

const STUBBLE := 1
const BARE := 2
const STAGE_NAMES := { STUBBLE: "stubble", BARE: "bare" }
const TILE_SIZE := 16

# [Tunable] Sim seconds between squares of her first day's grazing: her own square
# first, then round the ring from a side picked by her id, so all nine are stubble
# about four minutes after she stops.
const GRAZE_SECONDS := 25.0
# [Tunable] A happy reach for the tuft, a forward lick, then a small settling
# wiggle and the unchanged smug hold. Each reach is held; nothing shakes.
const STRETCH_EVERY_SECONDS := 14.0
const STRETCH_BEAT := [
	[SheepArt.STRETCH_REACH, 0.3], [SheepArt.STRETCH_FULL, 0.4],
	[SheepArt.STRETCH_LICK, 0.8], [SheepArt.STRETCH_REACH, 0.2],
	[SheepArt.STRETCH_SMUG, 1.5],
]
# [Tunable] Birds: a visit comes round every `BIRD_EVERY_SECONDS` a sheep, flies in
# and out over `BIRD_FLY_SECONDS`, and sits for between the two `BIRD_PERCH_SECONDS`.
# Her heart shows for `HEART_SECONDS` after it lands.
const BIRD_EVERY_SECONDS := 40.0
const BIRD_FLY_SECONDS := 1.6
const BIRD_PERCH_SECONDS := [12.0, 22.0]
const HEART_SECONDS := 1.4
# Where on her fleece a bird sits, in pixels from the middle of her square's bottom
# edge, facing right (mirrored with her), and where it comes from and goes to.
const PERCH := Vector2(-2.0, -27.0)
const BIRD_FAR := Vector2(70.0, -60.0)

# **Cues, for the video tools only** (`tools/record_video_shots.gd`). A cue starts one
# sheep's beat ("stretch" or "bird") at a given tick instead of at her own place in
# the cycle, so a shot can have it on demand. The game never sets one; it is
# presentation state, never saved, and cleared with `clear_cues`.
static var _cues := {}

const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]


static func ticks(seconds: float) -> int:
	return maxi(1, int(round(seconds * float(SimClock.RATE))))


## Is this a sheep stopped for good out on the farm (not in a stall, not in a room)?
static func is_stuck_outside(world: SimWorld, actor_id: String) -> bool:
	if not world.has_actor(actor_id) or world.species_of(actor_id) != SpeciesDefs.SHEEP:
		return false
	if String(world.actor(actor_id).get("extra", {}).get("state", "")) != "content":
		return false
	var at := world.actor_pos(actor_id)
	return at.y >= 0 and at.y < WorldLayout.PAGE_ROWS and world.room_of_cell(at) == ""


static func cue(actor_id: String, gag: String, tick: int) -> void:
	_cues["%s:%s" % [actor_id, gag]] = tick


static func clear_cues() -> void:
	_cues.clear()


# Where in a beat's cycle of `period` ticks she is: her own place, from her id, or
# from a tool's cue.
static func _phase(actor_id: String, gag: String, tick: int, period: int, shift: int) -> int:
	var key := "%s:%s" % [actor_id, gag]
	if _cues.has(key):
		return tick - int(_cues[key])   # negative until the cue: nothing yet
	return tick + posmod(actor_id.hash() >> shift, period)


## Every sheep stopped for good on the farm, by id.
static func stuck_sheep(world: SimWorld) -> Array[String]:
	var out: Array[String] = []
	for id in world.actors:
		if is_stuck_outside(world, String(id)):
			out.append(String(id))
	out.sort()
	return out


## Plain field grass with nothing on it: the only ground she grazes.
static func grazable(world: SimWorld, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= SimWorld.MAP_WIDTH or cell.y >= WorldLayout.PAGE_ROWS:
		return false
	return String(world.get_tile(cell.x, cell.y).get("state", "")) == "cleared" \
		and world.get_object(cell.x, cell.y) == "" and world.room_of_cell(cell) == ""


## Her square, then the eight round it in the order she grazes them.
static func ring_order(actor_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i.ZERO]
	var start := posmod(actor_id.hash(), NEIGHBOURS.size())
	for i in NEIGHBOURS.size():
		out.append(NEIGHBOURS[(start + i) % NEIGHBOURS.size()])
	return out


static func ring_is_bare(world: SimWorld, actor_id: String) -> bool:
	return int(world.actor(actor_id).get("extra", {}).get("nights_content", 0)) >= 1


## How far one of her squares is grazed at `tick`: 0, STUBBLE or BARE. `index` is
## its place in `ring_order`.
static func ring_stage(world: SimWorld, actor_id: String, index: int, tick: int) -> int:
	if ring_is_bare(world, actor_id):
		return BARE
	var since := int(world.actor(actor_id).get("extra", {}).get("content_since", tick))
	return STUBBLE if tick - since >= index * ticks(GRAZE_SECONDS) else 0


## Every grazed square on the farm at `tick`, as {cell, centre, stage}: stubble first,
## then bare, so where two rings overlap the barer one is drawn over the other.
static func ring_pieces(world: SimWorld, tick: int) -> Array[Dictionary]:
	var stubble: Array[Dictionary] = []
	var bare: Array[Dictionary] = []
	for id in stuck_sheep(world):
		var centre := world.actor_pos(id)
		var order := ring_order(id)
		for i in order.size():
			var cell: Vector2i = centre + order[i]
			if not grazable(world, cell):
				continue
			var stage := ring_stage(world, id, i, tick)
			if stage == STUBBLE:
				stubble.append({ "cell": cell, "centre": centre, "stage": stage })
			elif stage == BARE:
				bare.append({ "cell": cell, "centre": centre, "stage": stage })
	return stubble + bare


## Is this square inside any stuck sheep's ring?
static func in_a_ring(world: SimWorld, cell: Vector2i) -> bool:
	for id in stuck_sheep(world):
		var d := cell - world.actor_pos(id)
		if absi(d.x) <= 1 and absi(d.y) <= 1:
			return true
	return false


## The tuft she strains toward once her ring is bare: a grass square just past the
## ring, on the side she faces if there is one, else the other side. {} if there is
## no grass two squares out either way. Returns {cell, left} — `left` is the way she
## faces while she strains.
static func stretch_target(world: SimWorld, actor_id: String) -> Dictionary:
	if not is_stuck_outside(world, actor_id) or not ring_is_bare(world, actor_id):
		return {}
	var at := world.actor_pos(actor_id)
	var left := String(world.actor(actor_id).get("facing", "")) == "left"
	for side in ([-1, 1] if left else [1, -1]):
		for dy in [0, -1, 1]:
			var cell := at + Vector2i(2 * side, dy)
			if grazable(world, cell) and not in_a_ring(world, cell):
				return { "cell": cell, "left": side < 0 }
	return {}


## Which frame of the neck stretch she shows at `tick`, or -1 for her ordinary wiggle.
## Every sheep has her own place in the cycle, from her id.
static func stretch_frame(actor_id: String, tick: int) -> int:
	var period := ticks(STRETCH_EVERY_SECONDS)
	var phase := _phase(actor_id, "stretch", tick, period, 3)
	if phase < 0:
		return -1
	var t := posmod(phase, period)
	for beat in STRETCH_BEAT:
		var length := ticks(float(beat[1]))
		if t < length:
			return int(beat[0])
		t -= length
	return -1


## The bird visiting her at `tick`, or {} when none is. {pos: pixels from the middle
## of her square's bottom edge, facing right; flying; flap (0/1); heart: seconds since
## it landed while her heart shows, else -1}. A visit's length and the side it comes
## from vary visit to visit, from her id and the visit's number.
static func bird(actor_id: String, tick: int) -> Dictionary:
	var period := ticks(BIRD_EVERY_SECONDS)
	var shifted := _phase(actor_id, "bird", tick, period, 7)
	if shifted < 0:
		return {}
	var visit := floori(float(shifted) / float(period))
	var t := shifted - visit * period
	var roll := posmod(hash("%s:%d" % [actor_id, visit]), 1000)
	var perch_low := ticks(float(BIRD_PERCH_SECONDS[0]))
	var perch_high := ticks(float(BIRD_PERCH_SECONDS[1]))
	var perch := perch_low + roll % (perch_high - perch_low + 1)
	var fly := ticks(BIRD_FLY_SECONDS)
	var far := BIRD_FAR * Vector2(-1.0 if roll % 2 == 0 else 1.0, 1.0)
	var flap := posmod(tick, 2)
	if t < fly:
		var k := float(t) / float(fly)
		# In on a falling curve: fast at first, settling gently on her.
		return { "pos": far.lerp(PERCH, 1.0 - pow(1.0 - k, 2.0)), "flying": true, "flap": flap,
			"heart": -1.0, "left": far.x > 0.0 }
	t -= fly
	if t < perch:
		var since := float(t) / float(SimClock.RATE)
		# Now and then it turns round on her back.
		var turned := (t / ticks(3.0) + roll) % 3 == 0
		return { "pos": PERCH, "flying": false, "flap": 0,
			"heart": since if since < HEART_SECONDS else -1.0, "left": turned }
	t -= perch
	if t < fly:
		var k := float(t) / float(fly)
		var away := Vector2(-far.x, far.y)
		return { "pos": PERCH.lerp(away, k * k), "flying": true, "flap": flap,
			"heart": -1.0, "left": away.x < 0.0 }
	return {}

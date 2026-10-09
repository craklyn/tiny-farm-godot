# barn_presentation.gd — what the Industrial Barn looks like at a given sim tick
# (design/17; INDUSTRIAL_BARN_ENGINEERING_PLAN, "Connect barn animation to
# simulation state")
#
# **Presentation only, and a pure function of saved state.** Every moving part
# of the barn — the cow walking in, the milk pulse in the pipe, the warming vat,
# the cutter and rake carriages, the drain drip, the presses and the outfeed
# belt — is computed here from two things: the saved barn and cow records, and
# the sim clock's tick. Nothing reads the wall clock, so a paused game, a slow
# frame or a save loaded an hour later all draw the same barn for the same tick,
# and the motion stops when the sim stops.
#
# Nothing here writes. A batch's position comes from its saved `entry_tick` and
# `ready_tick`; when its station is done and the next one is busy, its progress
# holds at 1 and the machine stands still, waiting, as the line does. Only the
# gateway's line Actions move a batch on — an animation reaching its end never
# does.
#
# The state is a plain dictionary so a test can compare two of them, and the
# renderer (`farm.gd`) draws from it without asking the sim anything else.
class_name BarnPresentation
extends RefCounted

const TILE := 16

# Kit-space pixel positions (`industrial_barn_interior_kit.png`, 96x64, one 16px
# cell per room cell). Measured off the picture, which is why they are numbers.
const PIPE_Y := 12                  # the stall pipe into the receiver
const PIPE_FROM_X := 46
const PIPE_TO_X := 67
const RECEIVER_LIGHT := Vector2(75, 6)
const VAT := Rect2(81, 5, 14, 9)
const CUTTER_TRACK := Rect2(83, 19, 10, 6)
const RAKE_TRACK := Rect2(67, 23, 10, 4)
const DRAIN_DRIP_X := 78
const DRAIN_DRIP_Y := 40
const PRESS_XS: Array[int] = [82, 87, 92]
const PRESS_TOP_Y := 35
const BELT_Y := 57
const BELT_FROM_X := 82
const BELT_TO_X := 90
const STORE := Vector2(82, 52)

const COW_STATES_CROSSING: Array[String] = ["crossing_in", "crossing_out"]
const HOP_FRAMES := 4

const STEEL_DARK := Color("2f2b3d")
const MILK := Color("f8f4e6")
const LIGHT_ON := Color("ff6a4a")
const WARM := Color("c9a06b")
const CURD := Color("e9e178")
const CHEESE := Color("f0cf5a")
const WHEY := Color("d6e2c8")


# Everything the renderer draws for one barn at `tick`. Empty when the barn or
# its room is gone.
static func drawn_state(world: SimWorld, barn_id: String, tick: int) -> Dictionary:
	if world == null or not world.barns.has(barn_id) or not world.rooms.has(barn_id):
		return {}
	var barn: Dictionary = world.barns[barn_id]
	var room: Dictionary = world.rooms[barn_id]
	var stations: Dictionary = barn.get("stations", {})

	var stalls: Array = []
	for stall in barn.get("stalls", []):
		var cow_id := String(stall.get("cow_id", ""))
		var giving := false
		if cow_id != "" and world.has_actor(cow_id):
			giving = String(world.actor(cow_id).get("extra", {}).get("state", "")) == "giving"
		stalls.append({ "index": int(stall.get("index", -1)),
			"cell": [int(stall["cell"][0]), int(stall["cell"][1])],
			"cow_id": cow_id, "giving": giving })

	# The receiver holds the queue; its head is the unit arriving through the pipe.
	var receiver: Array = barn.get("receiver", [])
	var arriving := progress(receiver[0], tick) if not receiver.is_empty() else -1.0

	var line := {}
	for station in SimWorld.BARN_STATIONS:
		var batch = stations.get(station)
		line[station] = null if batch == null else {
			"batch_id": int(batch.get("batch_id", -1)), "progress": progress(batch, tick) }

	# The cows this barn is drawing: whoever holds a stall here, is on her way
	# out of it, or is standing in the room. Sorted for a stable comparison.
	var cows := {}
	var ids: Array = world.actors.keys()
	ids.sort()
	for raw in ids:
		var cow_id := String(raw)
		if world.species_of(cow_id) != SpeciesDefs.COW:
			continue
		var extra: Dictionary = world.actor(cow_id).get("extra", {})
		var mine := String(extra.get("barn_id", "")) == barn_id \
			or String(extra.get("leaving_barn_id", "")) == barn_id \
			or world.room_of_cell(world.actor_pos(cow_id)) == barn_id
		if mine:
			cows[cow_id] = cow_pose(world, cow_id, tick)
	var crossing: Array = []
	for cow_id in cows:
		if String(world.actor(cow_id)["extra"].get("state", "")) in COW_STATES_CROSSING:
			crossing.append(cow_id)

	return {
		"barn_id": barn_id,
		"origin": [Vector2i(room["origin"]).x, Vector2i(room["origin"]).y],
		"tick": tick,
		# Design/17: the livestock doors stay open. What moves through them is a cow.
		"door": { "open": true, "crossing": crossing },
		"stalls": stalls,
		"receiver": { "count": receiver.size(), "arriving": arriving,
			"light": not receiver.is_empty() and posmod(tick / 5, 2) == 0 },
		"line": line,
		"tools": _tools(line, tick),
		"finished": int(barn.get("finished_cheese_count", 0)),
		"cows": cows,
	}


# How far a batch is through its station, 0 to 1, from its saved ticks alone.
static func progress(batch: Dictionary, tick: int) -> float:
	var entry := int(batch.get("entry_tick", tick))
	var ready := int(batch.get("ready_tick", entry))
	if ready <= entry:
		return 1.0
	return clampf(float(tick - entry) / float(ready - entry), 0.0, 1.0)


# There and back once as `t` runs 0 to 1: a carriage crossing the vat and
# returning, a press lowering and rising.
static func there_and_back(t: float) -> float:
	return 1.0 - absf(1.0 - 2.0 * clampf(t, 0.0, 1.0))


static func _tools(line: Dictionary, tick: int) -> Dictionary:
	var out := {
		"vat_warm": -1,    # warming frame, or -1 when the vat is empty
		"cutter_x": -1.0,  # carriage offset across the vat, 0..1, or -1 parked
		"rake_x": -1.0,
		"drip_y": -1,      # whey drop below the drain table, or -1
		"press_y": 0,      # how far the press heads have lowered, in pixels
		"belt_x": -1.0,    # the wheel's way along the outfeed, 0..1, or -1
	}
	if line["set_vat"] != null:
		out["vat_warm"] = posmod(tick / 5, 2) if float(line["set_vat"]["progress"]) < 1.0 else 0
	if line["cutter"] != null:
		out["cutter_x"] = there_and_back(float(line["cutter"]["progress"]))
	if line["rake"] != null:
		# Twice across: stirring is slower work than a single cut.
		out["rake_x"] = there_and_back(fposmod(float(line["rake"]["progress"]) * 2.0, 1.0)) \
			if float(line["rake"]["progress"]) < 1.0 else 0.0
	if line["drain"] != null and float(line["drain"]["progress"]) < 1.0:
		out["drip_y"] = posmod(tick / 2, 3)
	if line["press"] != null:
		out["press_y"] = roundi(3.0 * there_and_back(float(line["press"]["progress"])))
	if line["outfeed"] != null:
		out["belt_x"] = float(line["outfeed"]["progress"])
	return out


# Where a cow is drawn at `tick`, in tile units, and which frame of her walk.
#
# A tile-stepped mover arrives on each square at the tick `Movement.step` puts
# her there and is due to step again at `wake`. Between the two she is drawn
# walking in from the square behind her (the one her facing came from), so the
# picture trails sim truth by less than a tile — the same lag the sliding
# sprites have — but measured in ticks, not frames. Standing, giving milk or
# waiting, she is on her square on frame 0.
static func cow_pose(world: SimWorld, cow_id: String, tick: int) -> Dictionary:
	var e: Dictionary = world.actor(cow_id)
	if e.is_empty():
		return {}
	var at := world.actor_pos(cow_id)
	var facing := String(e.get("facing", ""))
	var extra: Dictionary = e.get("extra", {})
	var pose := { "pos": Vector2(at), "frame": 0, "facing_left": facing == "left" }
	if String(extra.get("state", "")) != "moving" or int(extra.get("step", 0)) < 1:
		return pose
	var per_tile := maxi(1, Movement.ticks_per_tile(SpeciesDefs.COW))
	var stepped := int(extra.get("wake", tick)) - per_tile
	var since := tick - stepped
	if since < 0 or since >= per_tile:
		return pose
	# Steps are one square in one of four directions (`Movement.DIRS`), and her
	# facing is the direction of the last one, so it names the square behind her.
	var came := _facing_vector(facing)
	if came == Vector2i.ZERO:
		return pose
	var t := float(since) / float(per_tile)
	pose["pos"] = Vector2(at - came).lerp(Vector2(at), t)
	# Frame 0 is her standing pose; a step runs once through the other three.
	pose["frame"] = 1 + since * (HOP_FRAMES - 1) / per_tile
	return pose


static func _facing_vector(facing: String) -> Vector2i:
	match facing:
		"left": return Vector2i(-1, 0)
		"right": return Vector2i(1, 0)
		"up": return Vector2i(0, -1)
		"down": return Vector2i(0, 1)
	return Vector2i.ZERO


# Draw one barn's interior and its moving parts from a `drawn_state`. The kit
# fills the room; everything after it is a small mark at a measured spot.
static func draw(canvas: CanvasItem, kit: Texture2D, state: Dictionary) -> void:
	if state.is_empty():
		return
	var o := Vector2(int(state["origin"][0]) * TILE, int(state["origin"][1]) * TILE)
	if kit != null:
		canvas.draw_texture(kit, o)
	var receiver: Dictionary = state["receiver"]
	if float(receiver["arriving"]) >= 0.0 and float(receiver["arriving"]) < 1.0:
		var x := lerpf(PIPE_FROM_X, PIPE_TO_X - 2, float(receiver["arriving"]))
		canvas.draw_rect(Rect2(o + Vector2(roundf(x), PIPE_Y - 1), Vector2(2, 2)), MILK, true)
	for stall in state["stalls"]:
		if bool(stall["giving"]):
			# A drop at the stall's end of its pipe: this cow is giving now.
			var cell := Vector2(int(stall["cell"][0]), int(stall["cell"][1])) * TILE
			canvas.draw_rect(Rect2(cell + Vector2(12, 11), Vector2(2, 2)), MILK, true)
	if bool(receiver["light"]):
		canvas.draw_rect(Rect2(o + RECEIVER_LIGHT, Vector2(2, 1)), LIGHT_ON, true)
	var tools: Dictionary = state["tools"]
	if int(tools["vat_warm"]) >= 0:
		var glow := Color(WARM.r, WARM.g, WARM.b, 0.55 if int(tools["vat_warm"]) == 0 else 0.8)
		canvas.draw_rect(Rect2(o + VAT.position, VAT.size), glow, true)
	for key in ["cutter_x", "rake_x"]:
		if float(tools[key]) >= 0.0:
			var track: Rect2 = CUTTER_TRACK if key == "cutter_x" else RAKE_TRACK
			var x := roundf(track.position.x + float(tools[key]) * (track.size.x - 1))
			canvas.draw_line(o + Vector2(x, track.position.y - 3), o + Vector2(x, track.end.y), STEEL_DARK, 1.0)
			if key == "rake_x":
				canvas.draw_rect(Rect2(o + Vector2(x - 1, track.end.y - 1), Vector2(3, 1)), STEEL_DARK, true)
			else:
				canvas.draw_rect(Rect2(o + Vector2(x - 2, track.position.y + 1), Vector2(1, 4)), CURD, true)
	if int(tools["drip_y"]) >= 0:
		canvas.draw_rect(Rect2(o + Vector2(DRAIN_DRIP_X, DRAIN_DRIP_Y + int(tools["drip_y"])), Vector2(1, 1)), WHEY, true)
	if state["line"]["press"] != null:
		for px in PRESS_XS:
			canvas.draw_rect(Rect2(o + Vector2(px, PRESS_TOP_Y + int(tools["press_y"])), Vector2(6, 2)), STEEL_DARK, true)
	if float(tools["belt_x"]) >= 0.0:
		var bx := roundf(lerpf(BELT_FROM_X, BELT_TO_X, float(tools["belt_x"])))
		canvas.draw_rect(Rect2(o + Vector2(bx, BELT_Y), Vector2(4, 3)), CHEESE, true)
	for i in mini(int(state["finished"]), SimWorld.FINISHED_CHEESE_CAPACITY):
		canvas.draw_rect(Rect2(o + STORE + Vector2((i % 4) * 4, -(i / 4) * 3), Vector2(3, 2)), CHEESE, true)

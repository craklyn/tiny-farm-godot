# The coop's built-in wall shelf. Derived from its room, including old saves.
# No grid object, floor space, inventory or saved field is added for the shop.
class_name CoopShop
extends RefCounted

const ITEMS: Array[String] = ["nest_box", "chicken_dispenser"]

static func shelf_rect(world: SimWorld, room_id: String) -> Rect2i:
	if world.room_kind(room_id) != "coop": return Rect2i()
	var room: Dictionary = world.rooms[room_id]
	var origin: Vector2i = room.get("origin", Vector2i.ZERO)
	var size: Vector2i = room.get("size", Vector2i.ZERO)
	if size.x < 4 or size.y < 3: return Rect2i()
	return Rect2i(origin + Vector2i((size.x - 2) / 2, 0), Vector2i(2, 1))

static func room_at(world: SimWorld, tile: Vector2i) -> String:
	var room := world.room_of_cell(tile)
	return room if shelf_rect(world, room).has_point(tile) else ""

static func current_room(world: SimWorld, actor_id: String = "player") -> String:
	if actor_id == "": actor_id = "player"
	if not world.has_actor(actor_id): return ""
	var room := world.room_of_cell(world.actor_pos(actor_id))
	return room if world.room_kind(room) == "coop" else ""

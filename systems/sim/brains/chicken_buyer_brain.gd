# A persistent visiting farmer collects only the gateway-confirmed sale (design/16).
# Sale membership, payment and removal stay exclusively in Poultry.apply.
class_name ChickenBuyerBrain
extends Brain


func step(world: SimWorld, actor_id: String, tick: int, _gs = null) -> Dictionary:
	var actor := world.actor(actor_id)
	if actor.is_empty():
		return {}
	var extra: Dictionary = actor["extra"]
	var sale: Dictionary = extra.get("sale", {})
	extra["wake"] = tick + SimClock.RATE
	if sale.is_empty():
		return {}
	if bool(sale.get("collected", false)):
		var exit_raw: Array = sale.get("exit", [])
		if exit_raw.size() != 2:
			return {}
		var exit := Vector2i(int(exit_raw[0]), int(exit_raw[1]))
		if world.actor_pos(actor_id) == exit:
			PoultryNavigation.clear(world, actor_id)
			return {"actor": actor_id, "verb": "depart_chicken_sale", "target": exit,
				"params": {"sale_id": actor_id}}
		return PoultryNavigation.toward(world, actor_id, exit, tick)
	var ids: Array = sale.get("ids", [])
	if ids.is_empty():
		return {}
	var chicken_id := String(ids[0])
	if not world.has_actor(chicken_id):
		# A stale/canceled sale is not permission to choose another bird.
		PoultryNavigation.clear(world, actor_id)
		return {}
	var target := world.actor_pos(chicken_id)
	var here := world.actor_pos(actor_id)
	if world.space_of(here) == world.space_of(target) and Vector2(here).distance_to(Vector2(target)) <= 1.5:
		PoultryNavigation.clear(world, actor_id)
		return {"actor": actor_id, "verb": "collect_chicken_sale", "target": target,
			"params": {"sale_id": actor_id}}
	return PoultryNavigation.toward(world, actor_id, target, tick)


func on_result(world: SimWorld, actor_id: String, _action: Dictionary, result: Dictionary) -> void:
	var actor := world.actor(actor_id)
	if actor.is_empty():
		return
	PoultryNavigation.clear(world, actor_id)
	# A separated pair, blocked door or changed target is a safe retry, never
	# authority for this brain to pay, despawn or change confirmed participants.
	actor["extra"]["wake"] = world.clock.tick + (1 if bool(result.get("ok", false)) else SimClock.RATE)

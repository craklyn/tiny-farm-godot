# vignette.gd — Q-9 wordless onboarding state (M1)
# Progress is derived purely from world state — no saved fields, no flags:
# the farm IS the tutorial's memory, so it survives relaunches and replays
# for free. Active only on day 1; sleeping past it simply ends it.
class_name VignetteState

# Steps: 0 = clear the weed, 1 = plant the tilled tile, 2 = water it, 3 = done


static func current_step(world: SimWorld) -> int:
	if world.get_tile(SimWorld.VIGNETTE_WEED.x, SimWorld.VIGNETTE_WEED.y).get("state", "") == "obstacle_weed":
		return 0
	var plant_tile := world.get_tile(SimWorld.VIGNETTE_PLANT.x, SimWorld.VIGNETTE_PLANT.y)
	var st: String = plant_tile.get("state", "")
	if st == "tilled" or st == "cleared":
		return 1
	if st == "seeded" and not plant_tile.get("watered_today", false):
		return 2
	return 3


static func is_active(world: SimWorld, day: int) -> bool:
	return day == 1 and current_step(world) < 3


static func target_tile(world: SimWorld) -> Vector2i:
	match current_step(world):
		0:
			return SimWorld.VIGNETTE_WEED
		1, 2:
			return SimWorld.VIGNETTE_PLANT
	return Vector2i(-1, -1)

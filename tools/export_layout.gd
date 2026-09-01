# export_layout.gd — dump WorldLayout.DEFAULT as JSON for Tiny Farm HQ's map
# editor (hq/static/map.js). Run headless:
#   godot --headless --path . --script res://tools/export_layout.gd
# Vector2i becomes [x, y]; Rect2i becomes [x, y, w, h]. The HQ editor edits
# layout *definitions* (the seeded generator's input), never generated worlds.
extends SceneTree


func _jsonify(v):
	if v is Vector2i:
		return [v.x, v.y]
	if v is Rect2i:
		return [v.position.x, v.position.y, v.size.x, v.size.y]
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _jsonify(v[k])
		return out
	if v is Array:
		var arr := []
		for e in v:
			arr.append(_jsonify(e))
		return arr
	return v


func _init() -> void:
	var doc := {
		"name": "default",
		"source": "systems/world_layout.gd WorldLayout.DEFAULT",
		"grid": [SimWorld.MAP_WIDTH, SimWorld.MAP_HEIGHT],
		"layout": _jsonify(WorldLayout.DEFAULT),
	}
	var f := FileAccess.open("res://hq/data/maps/default.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("exported WorldLayout.DEFAULT -> hq/data/maps/default.json")
	quit()

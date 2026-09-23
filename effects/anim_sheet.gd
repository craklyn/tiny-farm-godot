# Reads Animation Lab exports used by the watering inset and story nights.
extends RefCounted


static func load_manifest(slug: String) -> Dictionary:
	var path := "res://assets/anim/%s/manifest.json" % slug
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func load_sheet(slug: String, manifest: Dictionary) -> Texture2D:
	var path := "res://assets/anim/%s/%s" % [slug, String(manifest.get("sheet", "sheet.png"))]
	return load(path) as Texture2D


# Exports are horizontal strips of frame_count cells. A caller may supply a
# prepared sheet (the overnight's edge dither) before the same atlas slicing.
static func load_frames(slug: String, manifest: Dictionary, source: Texture2D = null) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var sheet: Texture2D = source if source != null else load_sheet(slug, manifest)
	if sheet == null:
		return out
	var cw := int(manifest.get("cell_width", 0))
	var ch := int(manifest.get("cell_height", 0))
	var count := int(manifest.get("frame_count", 0))
	if cw <= 0 or ch <= 0 or count <= 0:
		return out
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * cw, 0, cw, ch)
		out.append(atlas)
	return out

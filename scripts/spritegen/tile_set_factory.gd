class_name TileSetFactory
extends RefCounted
## Builds a TileSet from the tiles PNG + JSON, at runtime.
##
## The mirror of SpriteFramesFactory, and for the same reason: committing a .tres TileSet
## would weld the art pipeline to Godot's resource format and make a fresh clone depend on
## import order - a TileSet pointing at a texture that has not been imported yet fails in a
## way that looks like missing art. A PNG and a JSON file always load.
##
## Collision comes from the `solid` flag in the JSON, so which tiles block movement is an
## art-data decision, not something the world code hardcodes.

const PHYSICS_LAYER := 0


static func build(texture: Texture2D, meta: Dictionary) -> TileSet:
	if texture == null:
		push_error("TileSetFactory: no texture")
		return null
	var size := int(meta.get("tile_size", 0))
	if size <= 0:
		push_error("TileSetFactory: tile_size missing from the tiles metadata")
		return null

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(size, size)
	tileset.add_physics_layer()

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(size, size)
	tileset.add_source(source, 0)

	var full := PackedVector2Array([
		Vector2(-size / 2.0, -size / 2.0),
		Vector2(size / 2.0, -size / 2.0),
		Vector2(size / 2.0, size / 2.0),
		Vector2(-size / 2.0, size / 2.0),
	])

	for entry: Variant in meta.get("tiles", []) as Array:
		var e: Dictionary = entry
		var coords := Vector2i(int(e.get("index", 0)), 0)
		source.create_tile(coords)
		if not bool(e.get("solid", false)):
			continue
		var data := source.get_tile_data(coords, 0)
		data.add_collision_polygon(PHYSICS_LAYER)
		# Tile collision polygons are expressed around the tile's centre, not its corner.
		data.set_collision_polygon_points(PHYSICS_LAYER, 0, full)
	return tileset


## tile id -> atlas coordinates, so a map file can name "wall" instead of a column number.
static func coords_by_id(meta: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in meta.get("tiles", []) as Array:
		var e: Dictionary = entry
		out[str(e.get("id", ""))] = Vector2i(int(e.get("index", 0)), 0)
	return out


static func solid_ids(meta: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in meta.get("tiles", []) as Array:
		var e: Dictionary = entry
		if bool(e.get("solid", false)):
			out.append(str(e.get("id", "")))
	return out

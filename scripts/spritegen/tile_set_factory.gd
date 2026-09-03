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

	var solid_by_id := {}
	for entry: Variant in meta.get("tiles", []) as Array:
		var e: Dictionary = entry
		var coords := Vector2i(int(e.get("index", 0)), 0)
		source.create_tile(coords)
		solid_by_id[str(e.get("id", ""))] = bool(e.get("solid", false))
		if not bool(e.get("solid", false)):
			continue
		var data := source.get_tile_data(coords, 0)
		data.add_collision_polygon(PHYSICS_LAYER)
		# Tile collision polygons are expressed around the tile's centre, not its corner.
		data.set_collision_polygon_points(PHYSICS_LAYER, 0, full)

	# Every shape in an edge block IS its block's tile - water with a grass bank drawn along one
	# side is still water - so it blocks exactly what that tile blocks. Without this the pond
	# keeps its middle and opens up all the way round its rim, which reads as the collision
	# being broken rather than as the edges being new.
	for entry: Variant in meta.get("edges", []) as Array:
		var block: Dictionary = entry
		var blocks_movement := bool(solid_by_id.get(str(block.get("tile", "")), false))
		var first := int(block.get("first", 0))
		for i in int(block.get("count", 0)):
			var shape_at := Vector2i(first + i, 0)
			source.create_tile(shape_at)
			if not blocks_movement:
				continue
			var shape_data := source.get_tile_data(shape_at, 0)
			shape_data.add_collision_polygon(PHYSICS_LAYER)
			shape_data.set_collision_polygon_points(PHYSICS_LAYER, 0, full)
	return tileset


## tile id -> atlas coordinates, so a map file can name "wall" instead of a column number.
static func coords_by_id(meta: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in meta.get("tiles", []) as Array:
		var e: Dictionary = entry
		out[str(e.get("id", ""))] = Vector2i(int(e.get("index", 0)), 0)
	return out


## The edge blocks each tile owns, by tile id - empty for a tile with hard edges, which is what
## lets MapBuilder ask the same question of every cell and get the old answer for most of them.
static func edges_by_id(meta: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in meta.get("edges", []) as Array:
		var block: Dictionary = entry
		var id := str(block.get("tile", ""))
		if not out.has(id):
			out[id] = []
		(out[id] as Array).append(block)
	return out


static func solid_ids(meta: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in meta.get("tiles", []) as Array:
		var e: Dictionary = entry
		if bool(e.get("solid", false)):
			out.append(str(e.get("id", "")))
	return out

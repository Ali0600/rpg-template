class_name MapBuilder
extends RefCounted
## Turns a MapData into live nodes: tile layers, collision, spawns and a y-sorted world.
##
## The layer arrangement is the part worth reading. Ground is a plain layer underneath
## everything; decor and every actor share ONE y-sorted parent, which is what lets a
## character walk behind a bush and in front of the next one. Y-sorting compares node
## origins, and a SpriteView's origin is its feet - so the sort is by where things stand,
## which is exactly what "behind" means in a top-down view.

const GROUND_LAYER_NAME := "Ground"
const SORTED_LAYER_NAME := "Sorted"
const DECOR_LAYER_NAME := "Decor"

## What a built map hands back. The caller needs the root to add, and the rest to place the
## player and wire up interaction.
class Built:
	var root: Node2D
	var sorted: Node2D
	var ground: TileMapLayer
	var decor: TileMapLayer
	var data: MapData
	var tile_size: int
	var problems: Array[String] = []

	func ok() -> bool:
		return problems.is_empty()


static func build(data: MapData, style: SpriteStyle, tiles_texture: Texture2D, tiles_meta: Dictionary) -> Built:
	var built := Built.new()
	built.data = data
	built.tile_size = style.tile_size

	var known: Array[String] = TileSetFactory.solid_ids(tiles_meta)
	for key: Variant in TileSetFactory.coords_by_id(tiles_meta).keys():
		if not known.has(str(key)):
			known.append(str(key))
	built.problems = data.problems(known, TileSetFactory.solid_ids(tiles_meta))
	if not built.problems.is_empty():
		return built

	var tileset := TileSetFactory.build(tiles_texture, tiles_meta)
	if tileset == null:
		built.problems.append("could not build a TileSet from the tiles metadata")
		return built
	var coords := TileSetFactory.coords_by_id(tiles_meta)
	var edges := TileSetFactory.edges_by_id(tiles_meta)

	built.root = Node2D.new()
	built.root.name = "Map_" + String(data.id)

	built.ground = _layer(GROUND_LAYER_NAME, tileset)
	built.root.add_child(built.ground)

	# One y-sorted parent holds the decor tiles AND the actors, so they sort against each
	# other. Two separate sorted layers would each sort internally and then stack wholesale -
	# every character always in front of, or always behind, every bush.
	built.sorted = Node2D.new()
	built.sorted.name = SORTED_LAYER_NAME
	built.sorted.y_sort_enabled = true
	built.root.add_child(built.sorted)

	built.decor = _layer(DECOR_LAYER_NAME, tileset)
	built.decor.y_sort_enabled = true
	built.sorted.add_child(built.decor)

	var bounds := data.size()
	for y in bounds.y:
		for x in bounds.x:
			var at := Vector2i(x, y)
			var ground_tile := data.ground_at(at)
			if coords.has(ground_tile):
				var plain: Vector2i = coords[ground_tile]
				built.ground.set_cell(at, 0, Vector2i(TerrainEdges.cell_index(
					edges.get(ground_tile, []) as Array, _around(data, at), plain.x), 0))
			var decor_tile := data.decor_at(at)
			if coords.has(decor_tile):
				built.decor.set_cell(at, 0, coords[decor_tile])
	return built


## The eight ground tiles around one cell, in TerrainEdges' own order. Off the map comes back
## as "", which MapData answers deliberately - so a pond against the border does not grow a
## shoreline into the wall, and a cell in the corner needs no special case.
static func _around(data: MapData, at: Vector2i) -> PackedStringArray:
	var out := PackedStringArray()
	for offset in TerrainEdges.OFFSETS:
		out.append(data.ground_at(at + offset))
	return out


static func _layer(layer_name: String, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	return layer


## Camera limits for a map, in pixels. Returns an empty rect when the map is smaller than
## the viewport in a dimension: clamping a camera inside a box smaller than its own view
## pushes the map off-centre, so that axis is left free and the map is centred instead.
static func camera_limits(data: MapData, tile_size: int) -> Rect2i:
	var bounds := data.size()
	return Rect2i(0, 0, bounds.x * tile_size, bounds.y * tile_size)


## Where an actor stands, in world pixels, for a named spawn. Returns a sentinel for an
## unknown spawn so the caller reports the missing entry rather than dropping the player at
## the map's corner, which looks like a movement bug.
static func spawn_position(data: MapData, spawn_id: StringName, tile_size: int) -> Vector2:
	var at := data.spawn(spawn_id)
	if at == Vector2i(-1, -1):
		return Vector2(-1.0, -1.0)
	return MapData.tile_to_world(at, tile_size)

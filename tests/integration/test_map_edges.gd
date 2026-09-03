extends GdUnitTestSuite
## A built map, painted with the shapes its own neighbours ask for.
##
## test_terrain_edges.gd proves the scheme decides correctly and test_tile_bank.gd proves the
## atlas is laid out the way the meta says. Neither can see the step between them: what the
## WORLD actually puts in a cell. That is one line in MapBuilder, and if it painted the plain
## column for everything - which is what it did until this milestone - every test above it
## would still pass and no shoreline would ever appear.
##
## The bank here is synthetic because no shipped bank has a ring yet: the demo's art comes in
## the milestone after this one, and a gate that could only run once the content existed would
## have nothing to fail on today.

const TILE := 16
const TICKS_TO_SETTLE := 3

var _style: SpriteStyle
var _built: MapBuilder.Built
var _root: Node2D
var _config: GameConfig


func before_test() -> void:
	Router.reset()
	_config = load("res://data/game_config.tres").duplicate() as GameConfig
	_style = ArtFixtures.style(&"gb16").duplicate() as SpriteStyle
	_style.tile_size = TILE


func after_test() -> void:
	Router.reset()
	if is_instance_valid(_root):
		_root.queue_free()


func _row(tone: String) -> Array:
	var rows: Array[String] = []
	for i in TILE:
		rows.append(tone.repeat(TILE))
	return rows


## Every piece of the ring, clear along its top row so a composed edge is visibly not the plain
## tile. Which piece lands where is decided and proven elsewhere; here it only has to differ.
func _ring() -> Dictionary:
	var rows: Array[String] = []
	for i in TILE:
		rows.append("." .repeat(TILE) if i == 0 else "2".repeat(TILE))
	var ring := {}
	for key in TerrainEdges.RING_KEYS:
		ring[key] = {"rows": rows}
	return ring


## Grass, a walled border, and water that draws an edge against the grass.
func _bank() -> TileBank:
	return TileBank.from_dictionary({"id": "edged", "tile": TILE, "tiles": [
		{"id": "grass", "ramp": "terrain_grass", "rows": _row("1")},
		{"id": "water", "ramp": "terrain_water", "solid": true, "rows": _row("2"),
			"ring": _ring(), "over": [["grass"]]},
		{"id": "wall", "ramp": "stone", "solid": true, "rows": _row("3")},
	]})


func _build(ground: Array) -> Dictionary:
	var bank := _bank()
	assert_array(bank.problems()).override_failure_message(str(bank.problems())).is_empty()
	var built := TileGen.build(_style, bank)
	var meta: Dictionary = built["meta"]
	var texture := ImageTexture.create_from_image(built["image"] as Image)
	var data := MapData.from_dictionary({
		"id": "edges", "style": "gb16",
		"legend": {".": "grass", "~": "water", "#": "wall"},
		"ground": ground,
		"spawns": {"start": [1, 1]},
	})
	_built = MapBuilder.build(data, _style, texture, meta)
	assert_array(_built.problems).override_failure_message(str(_built.problems)).is_empty()
	_root = _built.root
	add_child(_root)
	return meta


## Where the block of shapes for `water` over grass begins.
func _first(meta: Dictionary) -> int:
	var edges: Array = meta["edges"]
	assert_int(edges.size()).override_failure_message(
		"the fixture bank produced no edge block, so this suite proves nothing").is_equal(1)
	return int((edges[0] as Dictionary)["first"])


func _at(x: int, y: int) -> int:
	return _built.ground.get_cell_atlas_coords(Vector2i(x, y)).x


func _spawn_player() -> ActorBody:
	var body := ActorBody.new()
	body.setup(_config, FileSpriteSource.create(&"gb16"), &"hero")
	_built.sorted.add_child(body)
	body.global_position = MapBuilder.spawn_position(_built.data, &"start", _built.tile_size)
	return body


func _tick(body: ActorBody, input: Vector2, ticks: int) -> void:
	for i in ticks:
		body.apply(input)
		await get_tree().physics_frame


# -- what lands in a cell --------------------------------------------------------------------

func test_a_lone_pool_is_drawn_open_on_all_four_sides() -> void:
	var meta := _build([
		"#####",
		"#...#",
		"#.~.#",
		"#...#",
		"#####",
	])
	var first := _first(meta)
	assert_int(_at(2, 2)).override_failure_message(
		"the pool cell drew column %d; its four sides are grass, so it wants %d"
		% [_at(2, 2), first + TerrainEdges.index_of(
			TerrainEdges.N | TerrainEdges.E | TerrainEdges.S | TerrainEdges.W)]) \
		.is_equal(first + TerrainEdges.index_of(
			TerrainEdges.N | TerrainEdges.E | TerrainEdges.S | TerrainEdges.W))

func test_a_tile_with_no_ring_keeps_the_column_it_always_had() -> void:
	var meta := _build([
		"#####",
		"#...#",
		"#.~.#",
		"#...#",
		"#####",
	])
	var coords := TileSetFactory.coords_by_id(meta)
	assert_int(_at(1, 1)).override_failure_message(
		"a grass cell moved off its own column, so every map's plain ground moved with it") \
		.is_equal((coords["grass"] as Vector2i).x)
	assert_int(_at(0, 0)).is_equal((coords["wall"] as Vector2i).x)

func test_a_pond_one_tile_tall_is_open_north_and_south_at_once() -> void:
	# The case that chose quarter composition over LPC's thirteen whole pieces: the village
	# pond is one row of water, so its cells need a north edge AND a south edge in one tile.
	var meta := _build([
		"######",
		"#....#",
		"#.~~.#",
		"#....#",
		"######",
	])
	var first := _first(meta)
	assert_int(_at(2, 2)).override_failure_message(
		"the west end of a one-tall pond wants north, south and west open") \
		.is_equal(first + TerrainEdges.index_of(
			TerrainEdges.N | TerrainEdges.S | TerrainEdges.W))
	assert_int(_at(3, 2)).is_equal(first + TerrainEdges.index_of(
		TerrainEdges.N | TerrainEdges.S | TerrainEdges.E))

func test_the_middle_of_a_wide_pond_is_the_plain_shape() -> void:
	# And the shape at `first` IS the flat tile, so an interior cell is exactly what it was.
	var meta := _build([
		"######",
		"#....#",
		"#.~~.#",
		"#.~~.#",
		"#....#",
		"######",
	])
	assert_int(_at(2, 2)).is_not_equal(_first(meta))
	var wide := _build([
		"#######",
		"#.....#",
		"#.~~~.#",
		"#.~~~.#",
		"#.~~~.#",
		"#.....#",
		"#######",
	])
	assert_int(_at(3, 3)).override_failure_message(
		"a cell with water on every side is not the interior shape").is_equal(_first(wide))

func test_water_against_the_map_border_does_not_grow_a_shore_into_the_wall() -> void:
	# Off the map answers "", which is in nobody's over list. Without that a pond at the edge
	# would be fringed against nothing and the fringe would be drawn over the wall.
	var meta := _build([
		"#####",
		"#~~.#",
		"#...#",
		"#####",
	])
	var first := _first(meta)
	# (1,1) has wall to the north and west, the map's own border beyond them, water to the east
	# and grass only to the south - so exactly one side is open.
	assert_int(_at(1, 1)).override_failure_message(
		"the corner pool cell read the wall or the void as open ground") \
		.is_equal(first + TerrainEdges.index_of(TerrainEdges.S))
	assert_int(_at(2, 1)).override_failure_message(
		"the cell beside it is open south and east, and its corner between them") \
		.is_equal(first + TerrainEdges.index_of(
			TerrainEdges.S | TerrainEdges.E | TerrainEdges.SE))


# -- and what it does to a body ---------------------------------------------------------------

func test_a_shore_cell_stops_the_player_exactly_as_a_plain_one_would() -> void:
	# Every shape in a block IS its block's tile - water with a bank drawn on it is still water.
	# Without collision on the composed cells a pond keeps its middle and opens up all the way
	# round its rim, which reads as the physics breaking rather than as the edges being new.
	_build([
		"#######",
		"#.....#",
		"#..~..#",
		"#.....#",
		"#######",
	])
	var body := _spawn_player()
	await get_tree().physics_frame
	body.global_position = MapData.tile_to_world(Vector2i(1, 2), TILE)
	await _tick(body, Vector2.ZERO, TICKS_TO_SETTLE)
	var pool_edge := float(3 * TILE)
	await _tick(body, Vector2(1.0, 0.0), 240)
	assert_float(body.global_position.x).override_failure_message(
		"the player walked to %.1f; the pool starts at %.1f and every one of its cells is a "
		% [body.global_position.x, pool_edge] + "shore cell, so none of them has a plain tile "
		+ "to have stopped them") \
		.is_less(pool_edge)

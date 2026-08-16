extends GdUnitTestSuite
## Maps are hand-authored text, so every fault they can carry is a typo that builds
## something plausible.
##
## A ragged row, a legend entry naming a tile that does not exist, a spawn outside the map,
## an unwalled edge - none of these error, and all of them present as "the game is broken"
## rather than as "line 6 of a data file is wrong". Each one is reported with coordinates.

const FIXTURES := "res://tests/fixtures/maps/"

func _known_tiles() -> Array[String]:
	return TileGen.ids()

func _solid_tiles() -> Array[String]:
	return TileGen.solid_ids()

func test_the_shipped_map_is_valid() -> void:
	var map := MapData.load_from("res://data/maps/demo_town.json")
	assert_bool(map.ok).override_failure_message(map.error).is_true()
	assert_array(map.problems(_known_tiles(), _solid_tiles())).override_failure_message(
		str(map.problems(_known_tiles(), _solid_tiles()))).is_empty()

func test_the_shipped_map_is_walled_in() -> void:
	# The bug this caught for real: one row of the demo map was a character short of its east
	# wall, and the player simply walked out of the world. Nothing errored - the smoke test
	# reported the player still moving where it should have stopped.
	var map := MapData.load_from("res://data/maps/demo_town.json")
	assert_array(map.open_edges(_solid_tiles())).is_empty()

func test_a_ragged_row_is_reported_with_its_row_number() -> void:
	var map := MapData.load_from(FIXTURES + "ragged.json")
	var problems := map.problems(_known_tiles())
	assert_int(problems.size()).is_greater(0)
	assert_str(str(problems)).contains("wide, expected")

func test_a_legend_naming_an_unknown_tile_is_reported() -> void:
	# Draws nothing at all, and an empty patch of map looks exactly like a patch nobody
	# filled in.
	var map := MapData.load_from(FIXTURES + "bad_legend.json")
	assert_str(str(map.problems(_known_tiles()))).contains("unknown tile")

func test_a_character_the_legend_does_not_define_is_reported_with_coordinates() -> void:
	var map := MapData.load_from(FIXTURES + "bad_legend.json")
	assert_str(str(map.problems(_known_tiles()))).contains("does not define")

func test_a_spawn_outside_the_map_is_reported() -> void:
	# Spawning out of bounds drops the player into empty space, which reads as a movement bug.
	var map := MapData.load_from(FIXTURES + "bad_spawn.json")
	assert_str(str(map.problems(_known_tiles()))).contains("outside the")

func test_a_map_with_no_spawns_is_reported() -> void:
	var map := MapData.load_from(FIXTURES + "no_spawn.json")
	assert_str(str(map.problems(_known_tiles()))).contains("no spawns")

func test_an_open_edge_is_reported_when_solid_tiles_are_known() -> void:
	var map := MapData.load_from(FIXTURES + "open_edge.json")
	assert_array(map.open_edges(_solid_tiles())).is_not_empty()
	assert_str(str(map.problems(_known_tiles(), _solid_tiles()))).contains("edge is open")

func test_an_open_edge_with_a_warp_on_it_is_allowed() -> void:
	# A deliberately open edge is expressed by putting a warp there, so "you can leave here"
	# is stated in the data rather than left as an absence.
	var map := MapData.load_from(FIXTURES + "open_edge_with_warp.json")
	assert_array(map.open_edges(_solid_tiles())).is_empty()

func test_a_missing_map_file_is_an_error_not_an_empty_map() -> void:
	var map := MapData.load_from("res://data/maps/nope.json")
	assert_bool(map.ok).is_false()
	assert_str(str(map.problems(_known_tiles()))).contains("did not load")

func test_tiles_convert_to_world_positions_at_their_centre() -> void:
	# Actors stand on tile centres. A caller doing its own multiply is a caller that will
	# forget the half-tile offset and leave everything a few pixels up and to the left.
	assert_vector(MapData.tile_to_world(Vector2i(0, 0), 16)).is_equal(Vector2(8.0, 8.0))
	assert_vector(MapData.tile_to_world(Vector2i(3, 2), 16)).is_equal(Vector2(56.0, 40.0))

func test_world_positions_convert_back_to_the_tile_they_are_in() -> void:
	assert_vector(MapData.world_to_tile(Vector2(8.0, 8.0), 16)).is_equal(Vector2i(0, 0))
	assert_vector(MapData.world_to_tile(Vector2(15.9, 0.1), 16)).is_equal(Vector2i(0, 0))
	assert_vector(MapData.world_to_tile(Vector2(16.0, 16.0), 16)).is_equal(Vector2i(1, 1))
	# Negative coordinates must floor, not truncate toward zero: -1px is the tile to the
	# LEFT, and int() would call it tile 0 and put an out-of-bounds actor back on the map.
	assert_vector(MapData.world_to_tile(Vector2(-1.0, -1.0), 16)).is_equal(Vector2i(-1, -1))

func test_reading_a_tile_outside_the_map_is_empty_not_an_error() -> void:
	# Callers ask about neighbours at the edges constantly.
	var map := MapData.load_from("res://data/maps/demo_town.json")
	assert_str(map.ground_at(Vector2i(-1, 0))).is_equal("")
	assert_str(map.ground_at(Vector2i(9999, 0))).is_equal("")

func test_an_unknown_spawn_returns_a_sentinel_rather_than_the_origin() -> void:
	# Returning (0,0) would drop the player in the map's corner, which looks like a movement
	# bug rather than a missing data entry.
	var map := MapData.load_from("res://data/maps/demo_town.json")
	assert_vector(map.spawn(&"nowhere")).is_equal(Vector2i(-1, -1))
	assert_vector(map.spawn(&"start")).is_not_equal(Vector2i(-1, -1))

func test_a_warp_is_found_by_the_tile_it_sits_on() -> void:
	# Looked up by tile rather than by proximity, so stepping ONTO the door is the whole
	# rule - a radius would fire while the player is still visibly beside it.
	var map := MapData.load_from("res://data/maps/demo_town.json")
	var warp := map.warp_at(Vector2i(19, 6))
	assert_bool(warp.is_empty()).override_failure_message(
		"the town's east gate has no warp on it").is_false()
	assert_str(String(warp["map"])).is_equal("demo_cave")
	assert_str(String(warp["spawn"])).is_equal("west_gate")

func test_a_tile_with_no_warp_reports_none() -> void:
	var map := MapData.load_from("res://data/maps/demo_town.json")
	assert_bool(map.warp_at(Vector2i(4, 6)).is_empty()).is_true()

func test_both_shipped_maps_are_valid_and_their_doors_line_up() -> void:
	# A warp naming a map that does not exist, or a spawn that map does not have, sends the
	# player nowhere - and "nowhere" renders as a black screen, not as an error.
	for map_id in ["demo_town", "demo_cave"]:
		var map := MapData.load_from("res://data/maps/%s.json" % map_id)
		assert_array(map.problems(_known_tiles(), _solid_tiles())).override_failure_message(
			"%s: %s" % [map_id, map.problems(_known_tiles(), _solid_tiles())]).is_empty()
		for entry: Variant in map.warps:
			var warp: Dictionary = entry
			var destination := MapData.load_from("res://data/maps/%s.json" % warp["map"])
			assert_bool(destination.ok).override_failure_message(
				"%s warps to '%s', which does not exist" % [map_id, warp["map"]]).is_true()
			assert_vector(destination.spawn(StringName(str(warp["spawn"])))) \
				.override_failure_message("%s warps to spawn '%s' of '%s', which has no such spawn"
					% [map_id, warp["spawn"], warp["map"]]).is_not_equal(Vector2i(-1, -1))

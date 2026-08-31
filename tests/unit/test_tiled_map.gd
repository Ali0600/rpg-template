extends GdUnitTestSuite
## Writing this template's maps out to Tiled and reading them back.
##
## THE PROOF IS THE SIX MAPS THE GAME ALREADY SHIPS, round-tripped: write one out, read it back,
## and require what comes back to describe the same map. No fixture is invented, so there is no
## chance of the test agreeing with the translator because both were written by the same hand on
## the same afternoon - the input is content that existed before either direction did, with real
## warps, patrol paths, formations, a locked door and a legend.
##
## Comparison is on the RESOLVED map rather than the raw text. A `.tmj` carries no legend, so the
## importer assigns characters as it meets tiles; two legends can spell the same map differently
## and be equally correct. What must survive is which tile is at which coordinate, and every
## record intact.

const MAP_DIR := "res://data/maps"
const TILE_SIZE := 16

## The tile bank in index order, which is what a GID means. Read from the generated tiles.json
## because that is the file the coupling actually runs through - a test with its own list would
## prove the translator against a bank nobody paints with.
func _tile_ids(style: String) -> PackedStringArray:
	var file := JsonFile.read("res://assets/generated/%s/tiles.json" % style)
	assert_bool(file.ok).override_failure_message(
		"no generated tile table for '%s', so no GID in this suite means anything" % style).is_true()
	var out := PackedStringArray()
	for entry: Variant in file.data.get("tiles", []):
		out.append(str((entry as Dictionary).get("id", "")))
	return out

func _native_of(path: String) -> Dictionary:
	var file := JsonFile.read(path)
	assert_bool(file.ok).is_true()
	var out := file.data.duplicate(true)
	# `_readme` is prose for whoever opens the file and describes nothing the game reads, so it is
	# not carried through Tiled and not compared.
	out.erase("_readme")
	return out

## What a map MEANS, flattened: the tile at every coordinate on both layers, plus every record.
##
## This is what the round-trip has to preserve, and it is deliberately not the file's bytes. The
## legend is a spelling choice; `#` and `w` are the same wall.
func _resolved(native: Dictionary) -> Dictionary:
	var legend: Dictionary = native.get("legend", {})
	var out := {}
	for layer: String in ["ground", "decor"]:
		var rows := JsonFile.to_string_array(native.get(layer, []))
		var cells: Array[String] = []
		for y in rows.size():
			for x in rows[y].length():
				var ch := rows[y][x]
				if ch != " ":
					cells.append("%d,%d=%s" % [x, y, str(legend.get(ch, "?"))])
		out[layer] = cells
	for key: String in ["id", "style", "music", "spawns", "npcs", "warps", "objects", "enemies"]:
		if native.has(key):
			out[key] = native[key]
	return out

## Whole floats as ints, recursively, on both sides of the comparison.
##
## JSON HAS NO INTEGERS: a coordinate read off disk is 5.0 and the same coordinate built in code
## is 5, and every reader in this project casts one to the other - `JsonFile.to_int_array` exists
## for exactly that. So comparing them raw would fail on a difference the game cannot see, and
## normalising is narrower than it looks: only the numeric TYPE moves, never a value. A float that
## is not whole is left alone, so a genuine 0.5 could still fail the comparison.
func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if is_equal_approx(value, roundf(value)) else value
		TYPE_ARRAY:
			var out: Array = []
			for entry: Variant in value:
				out.append(_plain(entry))
			return out
		TYPE_DICTIONARY:
			var made := {}
			for key: Variant in value:
				made[str(key)] = _plain(value[key])
			return made
	return value

func _maps() -> PackedStringArray:
	return ContentScan.files_of(MAP_DIR, "json")

func test_there_is_something_to_check() -> void:
	# A loop over an empty directory validates nothing and reports success.
	assert_int(_maps().size()).is_greater(3)

func test_every_shipped_map_survives_a_trip_through_tiled() -> void:
	var checked := 0
	for path in _maps():
		var native := _native_of(path)
		var ids := _tile_ids(str(native.get("style", "gb16")))
		var tiled := TiledMap.from_native(native, ids, TILE_SIZE)
		var back := TiledMap.to_native(tiled, ids, TILE_SIZE)
		var was := _resolved(native)
		var now := _resolved(back)
		for key: Variant in was:
			assert_that(_plain(now.get(key))).override_failure_message(
				"'%s' came back from Tiled with a different '%s':\n  went in: %s\n  came out: %s"
				% [path.get_file(), key, str(_plain(was[key])), str(_plain(now.get(key)))]) \
				.is_equal(_plain(was[key]))
		checked += 1
	assert_int(checked).override_failure_message(
		"no map was round-tripped, so the loop above proved nothing").is_greater(3)

func test_a_map_that_came_back_is_still_a_map_the_game_can_read() -> void:
	# The other half: equal to the original is necessary and not sufficient, because both could be
	# wrong in the same way. This one asks MapData itself - the class the game loads maps with -
	# whether what came back parses, and whether the things a fight and a walk depend on are where
	# they were.
	for path in _maps():
		var native := _native_of(path)
		var ids := _tile_ids(str(native.get("style", "gb16")))
		var back := TiledMap.to_native(TiledMap.from_native(native, ids, TILE_SIZE), ids, TILE_SIZE)
		var before := MapData.load_from(path)
		var after := MapData.from_dictionary(back)
		assert_bool(after.ok).override_failure_message(
			"'%s' did not parse after a trip through Tiled: %s" % [path, after.error]).is_true()
		assert_vector(after.size()).override_failure_message(
			"'%s' changed size" % path).is_equal(before.size())
		for y in before.size().y:
			for x in before.size().x:
				var at := Vector2i(x, y)
				assert_str(after.ground_at(at)).override_failure_message(
					"'%s' has a different tile at %s" % [path, at]).is_equal(before.ground_at(at))
				assert_str(after.decor_at(at)).is_equal(before.decor_at(at))

func test_a_map_painted_against_another_bank_is_refused() -> void:
	# THE COUPLING, and the reason it is checked rather than trusted. A GID is an index, so a map
	# painted against one bank and read against another is not a broken file - it is a map full of
	# the wrong tiles, and nothing else in this project would notice.
	var ids := _tile_ids("dusk16")
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	assert_array(TiledMap.problems(tiled, &"dusk16", ids)).override_failure_message(
		"a map painted against the bank it is being read with was refused").is_empty()
	var shorter := ids.duplicate()
	shorter.remove_at(shorter.size() - 1)
	assert_array(TiledMap.problems(tiled, &"dusk16", shorter)).override_failure_message(
		"the bank lost a tile and the map was accepted anyway - every id past the change is now "
		+ "a different tile").is_not_empty()

func test_a_map_painted_against_another_style_is_refused() -> void:
	var ids := _tile_ids("dusk16")
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	assert_array(TiledMap.problems(tiled, &"gb16", ids)).override_failure_message(
		"a map painted for one style was read as another without complaint").is_not_empty()

func test_an_infinite_map_is_refused() -> void:
	# Tiled will happily make one, and a template map has a fixed size - `MapData.size()` is the
	# width of row zero. An infinite map has no rows at all in the same sense.
	var ids := _tile_ids("dusk16")
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	tiled["infinite"] = true
	assert_array(TiledMap.problems(tiled, &"dusk16", ids)).is_not_empty()

func test_a_map_with_two_tilesets_is_refused() -> void:
	var ids := _tile_ids("dusk16")
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	var sets: Array = tiled["tilesets"]
	sets.append({"firstgid": 100, "name": "other", "tilecount": 4})
	assert_array(TiledMap.problems(tiled, &"dusk16", ids)).override_failure_message(
		"a map painted from two banks was accepted, and only one of them can be resolved") \
		.is_not_empty()

func test_a_structured_field_survives_as_more_than_a_string() -> void:
	# Tiled has no array property, so a patrol path and a formation travel as JSON behind a marker.
	# The shipped maps carry both, and this is the assertion that says they came back as DATA
	# rather than as the text of some data.
	var native := {
		"id": "t", "style": "dusk16", "music": "", "legend": {".": "grass"}, "ground": ["."],
		"decor": [" "], "spawns": {},
		"npcs": [{"tile": [0, 0], "id": "walker", "behavior": "patrol",
			"path": [[1, 2], [3, 4]], "loop": true, "dwell": 30}],
		"warps": [], "objects": [], "enemies": [],
	}
	var ids := _tile_ids("dusk16")
	var back := TiledMap.to_native(TiledMap.from_native(native, ids, TILE_SIZE), ids, TILE_SIZE)
	var npc: Dictionary = (back["npcs"] as Array)[0]
	assert_that(_plain(npc.get("path"))).override_failure_message(
		"a patrol path came back as %s" % [npc.get("path")]).is_equal([[1, 2], [3, 4]])
	assert_bool(npc.get("loop")).is_true()
	assert_int(npc.get("dwell")).is_equal(30)
	assert_str(str(npc.get("behavior"))).is_equal("patrol")

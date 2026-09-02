extends GdUnitTestSuite
## Writing this template's maps out to Tiled and reading them back.
##
## THE PROOF IS THE SIX MAPS THE GAME ALREADY SHIPS, round-tripped: write one out, read it back,
## and require what comes back to describe the same map. No fixture is invented, so there is no
## chance of the test agreeing with the translator because both were written by the same hand on
## the same afternoon - the input is content that existed before either direction did, with real
## warps, patrol paths, formations, a locked door and a legend.
##
## Comparison goes through `MapData.differences()`, which is the ONE place this project asks
## whether two maps are the same one - the LDtk round-trip and `map_io.gd --verify` ask it there
## too. It compares the GAME's reading rather than the text, which it has to: a `.tmj` carries no
## legend, so the importer assigns characters as it meets tiles, and two legends can spell the
## same map differently and be equally correct. What must survive is which tile is at which
## coordinate, and every record intact.

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

func _maps() -> PackedStringArray:
	return ContentScan.files_of(MAP_DIR, "json")

## The style the shipped maps are actually drawn in, read from the first of them. Named here
## rather than written out, because the demo has changed style once already and a style spelled
## into this suite goes stale as a REFUSAL: every coupling check would report every map as
## painted against the wrong bank, which looks like the translator failing rather than the
## fixture being out of date.
func _shipped_style() -> String:
	return str(_native_of(_maps()[0]).get("style", ""))

func test_there_is_something_to_check() -> void:
	# A loop over an empty directory validates nothing and reports success.
	assert_int(_maps().size()).is_greater(3)

func test_every_shipped_map_survives_a_trip_through_tiled() -> void:
	# Compared through MapData.differences(), which is the ONE place this project asks whether two
	# maps are the same one - the LDtk round-trip and `map_io.gd --verify` ask it there too, and
	# three copies of "same map" is three gates that eventually disagree about what a map is. It
	# compares the GAME's reading, so the rebuilt legend is not a difference; test_map_data proves
	# it detects real ones, which is what stops this loop being vacuous.
	var checked := 0
	for path in _maps():
		var native := _native_of(path)
		var ids := _tile_ids(str(native.get("style", "gb16")))
		var tiled := TiledMap.from_native(native, ids, TILE_SIZE)
		var back := TiledMap.to_native(tiled, ids, TILE_SIZE)
		var faults := MapData.differences(MapData.load_from(path), MapData.from_dictionary(back))
		assert_array(faults).override_failure_message(
			"'%s' came back from Tiled as a different map:\n  %s"
			% [path.get_file(), "\n  ".join(faults)]).is_empty()
		checked += 1
	assert_int(checked).override_failure_message(
		"no map was round-tripped, so the loop above proved nothing").is_greater(3)

func test_a_map_that_came_back_is_still_a_map_the_game_can_read() -> void:
	# Equal to the original is necessary and not sufficient, because both could be wrong in the
	# same way. This one asks whether MapData - the class the game loads maps with - can still
	# PARSE what came back and validate it, which comparing two parsed maps cannot tell you.
	for path in _maps():
		var native := _native_of(path)
		var ids := _tile_ids(str(native.get("style", "gb16")))
		var back := TiledMap.to_native(TiledMap.from_native(native, ids, TILE_SIZE), ids, TILE_SIZE)
		var after := MapData.from_dictionary(back)
		assert_bool(after.ok).override_failure_message(
			"'%s' did not parse after a trip through Tiled: %s" % [path, after.error]).is_true()
		assert_vector(after.size()).override_failure_message(
			"'%s' changed size" % path).is_equal(MapData.load_from(path).size())

func test_a_map_painted_against_another_bank_is_refused() -> void:
	# THE COUPLING, and the reason it is checked rather than trusted. A GID is an index, so a map
	# painted against one bank and read against another is not a broken file - it is a map full of
	# the wrong tiles, and nothing else in this project would notice.
	var ids := _tile_ids(_shipped_style())
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	assert_array(TiledMap.problems(tiled, StringName(_shipped_style()), ids)).override_failure_message(
		"a map painted against the bank it is being read with was refused").is_empty()
	var shorter := ids.duplicate()
	shorter.remove_at(shorter.size() - 1)
	assert_array(TiledMap.problems(tiled, StringName(_shipped_style()), shorter)).override_failure_message(
		"the bank lost a tile and the map was accepted anyway - every id past the change is now "
		+ "a different tile").is_not_empty()

func test_a_map_painted_against_another_style_is_refused() -> void:
	var ids := _tile_ids(_shipped_style())
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	assert_array(TiledMap.problems(tiled, &"gb16", ids)).override_failure_message(
		"a map painted for one style was read as another without complaint").is_not_empty()

func test_an_infinite_map_is_refused() -> void:
	# Tiled will happily make one, and a template map has a fixed size - `MapData.size()` is the
	# width of row zero. An infinite map has no rows at all in the same sense.
	var ids := _tile_ids(_shipped_style())
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	tiled["infinite"] = true
	assert_array(TiledMap.problems(tiled, StringName(_shipped_style()), ids)).is_not_empty()

func test_a_map_with_two_tilesets_is_refused() -> void:
	var ids := _tile_ids(_shipped_style())
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	var sets: Array = tiled["tilesets"]
	sets.append({"firstgid": 100, "name": "other", "tilecount": 4})
	assert_array(TiledMap.problems(tiled, StringName(_shipped_style()), ids)).override_failure_message(
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
	assert_that(MapData.plain_numbers(npc.get("path"))).override_failure_message(
		"a patrol path came back as %s" % [npc.get("path")]).is_equal([[1, 2], [3, 4]])
	assert_bool(npc.get("loop")).is_true()
	assert_int(npc.get("dwell")).is_equal(30)
	assert_str(str(npc.get("behavior"))).is_equal("patrol")

func test_a_map_says_which_bank_it_was_painted_against() -> void:
	# What `map_io.gd` asks a file before importing it, and the reason it asks the FILE rather than
	# taking a --style argument: two sources for one fact is how a map ends up read against a bank
	# it disagrees with, and that disagreement is silent - every cell resolves to some tile, just
	# the wrong one.
	var native := _native_of(_maps()[0])
	var ids := _tile_ids(str(native.get("style", "gb16")))
	var tiled := TiledMap.from_native(native, ids, TILE_SIZE)
	assert_str(TiledMap.style_of(tiled)).is_equal(str(native.get("style", "")))

func test_a_file_naming_no_style_is_not_guessed_at() -> void:
	# Empty, never a default. A guessed bank is the exact failure problems() exists to refuse, so
	# handing it a plausible answer here would walk straight past that check.
	assert_str(TiledMap.style_of({})).is_empty()

func test_the_tileset_image_is_named_beside_the_map() -> void:
	# FOUND BY OPENING ONE IN TILED, which is the only place it could have been found. The first
	# export wrote a bare "tiles.png"; Tiled resolves that relative to the .tmj, the atlas is not
	# there, and every tile opens BLANK. Nothing here could see it: the round trip never reads the
	# image, only an editor does. `map_io.gd` copies the sheet in under this name.
	var native := _native_of(_maps()[0])
	var style := str(native.get("style", "gb16"))
	var made := TiledMap.from_native(native, _tile_ids(style), TILE_SIZE)
	var image := str((((made["tilesets"] as Array)[0]) as Dictionary)["image"])
	assert_str(image).override_failure_message(
		"the tileset image is '%s', which does not name the style it belongs to" % image
		).is_equal(TiledMap.atlas_name(style))
	assert_str(image).override_failure_message(
		"the image path climbs out of the map's own directory, so an export is not portable"
		).not_contains("/")

func test_two_styles_do_not_collide_on_one_atlas_name() -> void:
	# One export directory may hold maps drawn from different banks. A single shared name would
	# mean the second copy overwrites the first and half the maps open wearing the wrong art.
	assert_str(TiledMap.atlas_name("gb16")).is_not_equal(TiledMap.atlas_name("dusk16"))

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

## The size that bank's indices are drawn at, from the same generated table. Read rather than
## written down for `_shipped_style()`'s reason one unit along: a size spelled into this suite is
## handed to BOTH directions of the round trip, where a wrong one cancels itself out and comes
## back the same map. `tools/map_io.gd` held a literal 16 through four milestones that way, and
## every export it wrote declared a 16px grid over a 32px atlas.
func _tile_size(style: String) -> int:
	var file := JsonFile.read("res://assets/generated/%s/tiles.json" % style)
	assert_bool(file.ok).override_failure_message(
		"no generated tile table for '%s', so no coordinate here means anything" % style).is_true()
	return int(file.data.get("tile_size", 0))

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
		var tiled := TiledMap.from_native(native, ids, _tile_size(str(native.get("style", "gb16"))))
		var back := TiledMap.to_native(tiled, ids, _tile_size(str(native.get("style", "gb16"))))
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
		var size := _tile_size(str(native.get("style", "gb16")))
		var back := TiledMap.to_native(TiledMap.from_native(native, ids, size), ids, size)
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
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, _tile_size(_shipped_style()))
	assert_array(TiledMap.problems(tiled, StringName(_shipped_style()), ids)).override_failure_message(
		"a map painted against the bank it is being read with was refused").is_empty()
	var shorter := ids.duplicate()
	shorter.remove_at(shorter.size() - 1)
	assert_array(TiledMap.problems(tiled, StringName(_shipped_style()), shorter)).override_failure_message(
		"the bank lost a tile and the map was accepted anyway - every id past the change is now "
		+ "a different tile").is_not_empty()

## The first tile layer's data array, so a single cell can be given a bad value.
func _poked(tiled: Dictionary, gid: int) -> Dictionary:
	for entry: Variant in (tiled["layers"] as Array):
		var layer: Dictionary = entry
		if str(layer.get("type", "")) == "tilelayer":
			var data: Array = layer["data"]
			data[0] = gid
			layer["data"] = data
			return tiled
	fail("the exported map has no tile layer to poke")
	return tiled


func test_a_tile_the_bank_does_not_have_is_named_rather_than_quietly_emptied() -> void:
	# It used to be SILENT: a GID the tileset does not have resolved to "" and the cell became a
	# space, so a map painted against a wider bank came back with holes in it and the round trip
	# reported a different map three layers downstream with no cause attached.
	#
	# One past the end is exactly what a map painted against the whole atlas carries - the
	# composed transition shapes sit in the columns immediately after the paintable tiles.
	var ids := _tile_ids(_shipped_style())
	var size := _tile_size(_shipped_style())
	var clean := TiledMap.from_native(_native_of(_maps()[0]), ids, size)
	assert_array(TiledMap.problems(clean, StringName(_shipped_style()), ids)) \
		.override_failure_message("an untouched export was refused").is_empty()
	var faults := TiledMap.problems(
		_poked(clean, ids.size() + 1), StringName(_shipped_style()), ids)
	assert_str("\n".join(faults)).contains("would come back as an empty cell")


func test_a_flipped_tile_is_told_apart_from_a_tile_that_is_not_there() -> void:
	# Tiled's top four bits carry the flips and the hex rotation, so a rotated tile's GID lands far
	# past any tileset. Reported as what it is, because rotating a tile is a real thing a person
	# does in the editor and "not one of the tiles in this bank" is a confusing way to hear it.
	var ids := _tile_ids(_shipped_style())
	var clean := TiledMap.from_native(
		_native_of(_maps()[0]), ids, _tile_size(_shipped_style()))
	var faults := "\n".join(TiledMap.problems(
		_poked(clean, 1 + TiledMap.FLIP_BITS), StringName(_shipped_style()), ids))
	assert_str(faults).contains("flipped or rotated")
	assert_str(faults).override_failure_message(
		"a flip was also reported as a tile the bank does not have").not_contains(
		"would come back as an empty cell")


func test_a_map_painted_on_another_grid_is_refused() -> void:
	# THE COUPLING IN ANOTHER UNIT. Every coordinate in a Tiled file is in PIXELS - an object is
	# written at `tile * tile_size` and read back by dividing - so a file painted on one grid and
	# read on another puts every record at a fraction of its own tile, on a map that still parses.
	# It cannot be caught by a round trip, because both directions are handed the same number.
	var style := _shipped_style()
	var ids := _tile_ids(style)
	var size := _tile_size(style)
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, size)
	assert_array(TiledMap.problems(tiled, StringName(style), ids, size)).override_failure_message(
		"a map read at the size it was painted on was refused").is_empty()
	assert_array(TiledMap.problems(tiled, StringName(style), ids, size * 2)) \
		.override_failure_message("a map painted at %dpx was accepted at %dpx; every record on it "
		% [size, size * 2] + "would land at half its tile").is_not_empty()
	assert_array(TiledMap.problems(tiled, StringName(style), ids)).override_failure_message(
		"a caller with no table to hand should get no size complaint, and got one").is_empty()

func test_a_map_painted_against_another_style_is_refused() -> void:
	var ids := _tile_ids(_shipped_style())
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, _tile_size(_shipped_style()))
	var other := ArtFixtures.some_other_style(StringName(_shipped_style()))
	assert_array(TiledMap.problems(tiled, other, ids)).override_failure_message(
		"a map painted for %s was read as %s without complaint" % [_shipped_style(), other]
		).is_not_empty()

func test_an_infinite_map_is_refused() -> void:
	# Tiled will happily make one, and a template map has a fixed size - `MapData.size()` is the
	# width of row zero. An infinite map has no rows at all in the same sense.
	var ids := _tile_ids(_shipped_style())
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, _tile_size(_shipped_style()))
	tiled["infinite"] = true
	assert_array(TiledMap.problems(tiled, StringName(_shipped_style()), ids)).is_not_empty()

func test_a_map_with_two_tilesets_is_refused() -> void:
	var ids := _tile_ids(_shipped_style())
	var tiled := TiledMap.from_native(_native_of(_maps()[0]), ids, _tile_size(_shipped_style()))
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
	var size := _tile_size("dusk16")
	var back := TiledMap.to_native(TiledMap.from_native(native, ids, size), ids, size)
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
	var tiled := TiledMap.from_native(native, ids, _tile_size(str(native.get("style", "gb16"))))
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
	var made := TiledMap.from_native(native, _tile_ids(style), _tile_size(style))
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


# -- the shapes the game draws, and a brush that paints them -----------------------------------

## The generator's own list of composed blocks: which column is which shape. Read, never written
## here, for `_tile_ids`' reason.
func _edges(style: String) -> Array:
	var file := JsonFile.read("res://assets/generated/%s/tiles.json" % style)
	assert_bool(file.ok).is_true()
	return file.data.get("edges", []) as Array

## How wide the generator says the sheet is - an independent statement of what every declared
## count in the export must equal.
func _columns(style: String) -> int:
	var file := JsonFile.read("res://assets/generated/%s/tiles.json" % style)
	assert_bool(file.ok).is_true()
	return int(file.data.get("columns", 0))

func _layer(tiled: Dictionary, name: String) -> Dictionary:
	for entry: Variant in (tiled["layers"] as Array):
		if str((entry as Dictionary).get("name", "")) == name:
			return entry
	fail("the export has no '%s' layer" % name)
	return {}

func _tileset(tiled: Dictionary) -> Dictionary:
	return (tiled["tilesets"] as Array)[0]

func _exported(style: String) -> Dictionary:
	return TiledMap.from_native(_native_of(_maps()[0]), _tile_ids(style), _tile_size(style),
		_edges(style))

func test_every_shipped_map_survives_a_trip_through_tiled_wearing_its_shorelines() -> void:
	var composed := 0
	for path in _maps():
		var native := _native_of(path)
		var style := str(native.get("style", "gb16"))
		var ids := _tile_ids(style)
		var size := _tile_size(style)
		var tiled := TiledMap.from_native(native, ids, size, _edges(style))
		for gid: Variant in _layer(tiled, "ground")["data"]:
			if int(gid) - 1 >= ids.size():
				composed += 1
		var back := TiledMap.to_native(tiled, ids, size, _edges(style))
		var faults := MapData.differences(MapData.load_from(path), MapData.from_dictionary(back))
		assert_array(faults).override_failure_message(
			"'%s' came back from Tiled as a different map:\n  %s"
			% [path.get_file(), "\n  ".join(faults)]).is_empty()
	assert_int(composed).override_failure_message(
		"no cell on any shipped map was written as a composed shape, so nothing was folded") \
		.is_greater(0)

func test_a_ground_cell_is_exported_as_the_shape_the_game_draws_there() -> void:
	var shored := 0
	for path in _maps():
		var native := _native_of(path)
		var style := str(native.get("style", "gb16"))
		var edges := _edges(style)
		if edges.is_empty():
			continue
		var ids := _tile_ids(style)
		var map := MapData.load_from(path)
		var by_tile := TileSetFactory.edges_by_id({"edges": edges})
		var data: Array = _layer(TiledMap.from_native(native, ids, _tile_size(style), edges),
			"ground")["data"]
		var wide := map.size().x
		for y in map.size().y:
			for x in wide:
				var tile := map.ground_at(Vector2i(x, y))
				if tile.is_empty():
					continue
				var want := TerrainEdges.cell_index(by_tile.get(tile, []) as Array,
					map.around(Vector2i(x, y)), ids.find(tile))
				assert_int(int(data[y * wide + x]) - 1).override_failure_message(
					"%s (%d,%d) is %s and the game draws column %d there; the export wrote %d"
					% [path.get_file(), x, y, tile, want, int(data[y * wide + x]) - 1]) \
					.is_equal(want)
				if want >= ids.size():
					shored += 1
	assert_int(shored).override_failure_message(
		"no shipped cell draws a composed shape, so this compared plain columns only").is_greater(0)

func test_the_tileset_declares_every_column_of_the_sheet() -> void:
	var style := _shipped_style()
	assert_int(_columns(style)).override_failure_message(
		"the shipped sheet has no composed columns, so this would compare the plain width with "
		+ "itself").is_greater(_tile_ids(style).size())
	var set_one := _tileset(_exported(style))
	assert_int(int(set_one["tilecount"])).is_equal(_columns(style))
	assert_int(int(set_one["columns"])).is_equal(_columns(style))
	assert_int(int(set_one["imagewidth"])).is_equal(_columns(style) * _tile_size(style))

func test_a_composed_tile_is_accepted_and_only_a_tile_past_the_whole_sheet_is_refused() -> void:
	var style := _shipped_style()
	var ids := _tile_ids(style)
	var size := _tile_size(style)
	var edges := _edges(style)
	var tiled := _exported(style)
	assert_array(TiledMap.problems(tiled, StringName(style), ids, size, edges)) \
		.override_failure_message("an untouched export was refused").is_empty()
	# GIDs start at 1, so the last column of the sheet is GID `columns`.
	assert_array(TiledMap.problems(_poked(tiled, _columns(style)), StringName(style), ids, size,
		edges)).override_failure_message("the last shape on the sheet was refused").is_empty()
	assert_str("\n".join(TiledMap.problems(_poked(tiled, _columns(style) + 1), StringName(style),
		ids, size, edges))).contains("would come back as an empty cell")

func test_a_composed_tile_comes_back_as_the_tile_its_shape_belongs_to() -> void:
	# What painting a shoreline in the editor does to a cell. Whichever shape it wears, the map
	# that comes back holds that shape's tile - here the LAST block, so the fold has to search.
	var style := _shipped_style()
	var ids := _tile_ids(style)
	var size := _tile_size(style)
	var edges := _edges(style)
	var block: Dictionary = edges[edges.size() - 1]
	var tiled := _poked(_exported(style), int(block["first"]) + 5 + 1)
	var back := MapData.from_dictionary(TiledMap.to_native(tiled, ids, size, edges))
	assert_str(back.ground_at(Vector2i(0, 0))).override_failure_message(
		"a cell wearing a '%s' shape came back as '%s'" % [block["tile"], back.ground_at(Vector2i(0, 0))]) \
		.is_equal(str(block["tile"]))

func test_every_edge_block_is_a_brush_holding_its_tiles() -> void:
	var style := _shipped_style()
	var ids := _tile_ids(style)
	var edges := _edges(style)
	var sets: Array = _tileset(_exported(style))["wangsets"]
	assert_int(sets.size()).is_equal(edges.size())
	for i in edges.size():
		var block: Dictionary = edges[i]
		var brush: Dictionary = sets[i]
		assert_str(str(brush["type"])).is_equal("mixed")
		var colors: Array = brush["colors"]
		var over := JsonFile.to_string_array(block["over"])
		assert_int(colors.size()).is_equal(2)
		assert_str(str((colors[0] as Dictionary)["name"])).is_equal(str(block["tile"]))
		assert_str(str((colors[1] as Dictionary)["name"])).is_equal(over[0])
		var want: Array[int] = [ids.find(str(block["tile"]))]
		for ground_id in over:
			want.append(ids.find(ground_id))
		for k in int(block["count"]):
			want.append(int(block["first"]) + k)
		want.sort()
		var got: Array[int] = []
		for entry: Variant in brush["wangtiles"]:
			got.append(int((entry as Dictionary)["tileid"]))
		got.sort()
		assert_array(got).override_failure_message(
			"brush '%s' holds the wrong tiles" % brush["name"]).is_equal(want)

func _wang_id(tiled: Dictionary, brush_index: int, tile: int) -> Array:
	var brush: Dictionary = (_tileset(tiled)["wangsets"] as Array)[brush_index]
	for entry: Variant in brush["wangtiles"]:
		if int((entry as Dictionary)["tileid"]) == tile:
			return (entry as Dictionary)["wangid"]
	fail("brush %d holds no tile %d" % [brush_index, tile])
	return []

func test_a_shape_is_coloured_ground_wherever_it_touches_ground() -> void:
	# Tiled's order runs clockwise from the top, and INNER is 1, GROUND is 2. Written out as
	# literals, so neither a rotation nor the corner rule can be argued with.
	var style := _shipped_style()
	var tiled := _exported(style)
	var edges := _edges(style)
	var first := int((edges[0] as Dictionary)["first"])
	var TE := TerrainEdges
	assert_array(_wang_id(tiled, 0, first + TE.index_of(TE.N))).is_equal([2, 2, 1, 1, 1, 1, 1, 2])
	assert_array(_wang_id(tiled, 0, first + TE.index_of(TE.NE))).is_equal([1, 2, 1, 1, 1, 1, 1, 1])
	assert_array(_wang_id(tiled, 0, first + TE.index_of(TE.E + TE.S))).is_equal(
		[1, 2, 2, 2, 2, 2, 1, 1])
	assert_array(_wang_id(tiled, 0, first + TE.index_of(0))).is_equal([1, 1, 1, 1, 1, 1, 1, 1])
	assert_array(_wang_id(tiled, 0, first + TE.index_of(TE.SIDES_MASK))).is_equal(
		[2, 2, 2, 2, 2, 2, 2, 2])

func test_the_brush_never_picks_a_tile_that_means_what_another_one_does() -> void:
	# Both kinds were measured: a one-colour shape tied with a plain tile and was scattered at
	# random, and a ground variant was painted where plain ground was asked for.
	var style := _shipped_style()
	var ids := _tile_ids(style)
	var edges := _edges(style)
	var painted := {}
	for entry: Variant in edges:
		var block: Dictionary = entry
		painted[ids.find(str(block["tile"]))] = true
		painted[ids.find(JsonFile.to_string_array(block["over"])[0])] = true
	var want := {}
	for entry: Variant in edges:
		var block: Dictionary = entry
		want[int(block["first"]) + TerrainEdges.index_of(0)] = true
		want[int(block["first"]) + TerrainEdges.index_of(TerrainEdges.SIDES_MASK)] = true
		var over := JsonFile.to_string_array(block["over"])
		for k in range(1, over.size()):
			if not painted.has(ids.find(over[k])):
				want[ids.find(over[k])] = true
	assert_int(want.size()).override_failure_message(
		"the shipped bank has no ground variant, so the second kind is never exercised") \
		.is_greater(2 * edges.size())
	var expected: Array[int] = []
	for key: Variant in want.keys():
		expected.append(int(key))
	expected.sort()
	var got: Array[int] = []
	for entry: Variant in _tileset(_exported(style)).get("tiles", []):
		if float((entry as Dictionary)["probability"]) == 0.0:
			got.append(int((entry as Dictionary)["id"]))
	got.sort()
	assert_array(got).is_equal(expected)


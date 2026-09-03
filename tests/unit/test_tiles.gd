extends GdUnitTestSuite
## Terrain: generated from the same palette, and carrying the one property the world needs.
##
## Which tiles block movement is an art-data decision here, not something the world code
## hardcodes - so a style that adds a cliff makes it solid in its own data and the movement
## system never learns the word "cliff".

func _bank(style_id: StringName) -> TileBank:
	return ArtFixtures.tile_bank_for(ArtFixtures.style(style_id))

func _tiles_meta(style_id: StringName) -> Dictionary:
	var file := JsonFile.read("res://assets/generated/%s/tiles.json" % style_id)
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	return file.data

func test_the_generator_draws_every_tile_it_declares() -> void:
	var style := ArtFixtures.style(&"gb16")
	var built := TileGen.build(style, _bank(&"gb16"))
	var image: Image = built["image"]
	var meta: Dictionary = built["meta"]
	assert_int((meta["tiles"] as Array).size()).is_equal(_bank(&"gb16").ids().size())
	# Three readings of one answer, pinned against each other: the strip's width, the number the
	# meta declares, and the layout function both are supposed to come from. A bank with rings
	# grows past its id count, so the id count on its own stopped being the whole statement.
	var columns := TileGen.cell_count(_bank(&"gb16"))
	assert_int(image.get_width()).is_equal(style.tile_size * columns)
	assert_int(int(meta["columns"])).is_equal(columns)
	assert_int(image.get_height()).is_equal(style.tile_size)

func test_no_tile_is_a_flat_block_of_one_colour() -> void:
	# A tile that came out as a single fill means its texturing pass did nothing - it still
	# renders, and the world just looks like coloured paper. True of a CUT tile too, where the
	# usual cause is picking the middle of a transition block: LPC's ground sheets have a plain
	# fill cell in them, and it is one colour.
	for style_id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(style_id)
		var bank := ArtFixtures.tile_bank_for(style)
		var built := TileGen.build(style, bank, ArtFixtures.tile_images_for(bank))
		var image: Image = built["image"]
		for i in bank.ids().size():
			var seen: Array[int] = []
			for y in style.tile_size:
				for x in style.tile_size:
					var v := image.get_pixel(i * style.tile_size + x, y).to_rgba32()
					if not seen.has(v):
						seen.append(v)
			assert_int(seen.size()).override_failure_message(
				"%s tile '%s' uses only %d colour(s)"
				% [style_id, bank.ids()[i], seen.size()]).is_greater(1)

func test_ground_tiles_are_fully_opaque_and_decor_tiles_are_not() -> void:
	# A transparent hole in the FLOOR shows the background colour through the world. A decor
	# tile is the opposite case: it stands on the floor, so anything outside its shape must
	# stay clear or the bush arrives as a dark square cut into the grass.
	var style := ArtFixtures.style(&"gb16")
	var built := TileGen.build(style, _bank(&"gb16"))
	var image: Image = built["image"]
	var decor := _bank(&"gb16").decor_ids()
	for i in _bank(&"gb16").ids().size():
		var id := _bank(&"gb16").ids()[i]
		var clear := 0
		for y in style.tile_size:
			for x in style.tile_size:
				if image.get_pixel(i * style.tile_size + x, y).a == 0.0:
					clear += 1
		if decor.has(id):
			assert_int(clear).override_failure_message(
				"decor tile '%s' is a solid block; it would cut a square into the ground" % id).is_greater(0)
		else:
			assert_int(clear).override_failure_message(
				"ground tile '%s' has %d transparent pixels" % [id, clear]).is_equal(0)

func test_the_bank_has_an_example_of_every_solid_and_decor_combination() -> void:
	# The collision test below walks whatever the bank happens to contain, so a combination
	# with no example is a case it silently stops checking rather than a case it fails on.
	# decor-and-walkable had no example until a rug was authored: every decor tile shipped
	# was also solid, so "a decor tile that does not block" was an untested claim.
	var bank := _bank(&"gb16")
	var seen: Array[String] = []
	for i in bank.size():
		var e := bank.at(i)
		seen.append("%s/%s" % [bool(e.get("solid", false)), bool(e.get("decor", false))])
	for wanted in ["true/true", "true/false", "false/true", "false/false"]:
		assert_bool(seen.has(wanted)).override_failure_message(
			"no tile is solid/decor = %s, so the collision test cannot check that case" % wanted).is_true()

func test_the_tileset_gives_collision_to_exactly_the_solid_tiles() -> void:
	var style := ArtFixtures.style(&"gb16")
	var meta := _tiles_meta(&"gb16")
	var texture := load("res://assets/generated/gb16/tiles.png") as Texture2D
	var tileset := TileSetFactory.build(texture, meta)
	assert_object(tileset).is_not_null()
	assert_vector(tileset.tile_size).is_equal(Vector2i(style.tile_size, style.tile_size))

	var source := tileset.get_source(0) as TileSetAtlasSource
	var solid := TileSetFactory.solid_ids(meta)
	assert_array(solid).is_not_empty()
	for entry: Variant in meta["tiles"] as Array:
		var e: Dictionary = entry
		var data := source.get_tile_data(Vector2i(int(e["index"]), 0), 0)
		assert_object(data).override_failure_message("tile '%s' is missing" % e["id"]).is_not_null()
		var polygons := data.get_collision_polygons_count(TileSetFactory.PHYSICS_LAYER)
		if bool(e["solid"]):
			assert_int(polygons).override_failure_message(
				"solid tile '%s' has no collision" % e["id"]).is_equal(1)
		else:
			assert_int(polygons).override_failure_message(
				"walkable tile '%s' blocks movement" % e["id"]).is_equal(0)

func test_an_edge_shape_blocks_exactly_what_its_own_tile_blocks() -> void:
	# Every shape in a block IS its block's tile, so it blocks what that tile blocks. Vacuous
	# over the shipped banks until the demo's ground grows a ring, so the meta is written here
	# by hand: one solid tile with a block of shapes, and one walkable tile with another.
	var texture := load("res://assets/generated/gb16/tiles.png") as Texture2D
	var meta := {
		"tile_size": 16,
		"tiles": [
			{"id": "water", "index": 0, "solid": true},
			{"id": "path", "index": 1, "solid": false},
		],
		"edges": [
			{"tile": "water", "over": ["grass"], "first": 2, "count": 3},
			{"tile": "path", "over": ["grass"], "first": 5, "count": 3},
		],
	}
	var source := TileSetFactory.build(texture, meta).get_source(0) as TileSetAtlasSource
	for i in 3:
		var shore := source.get_tile_data(Vector2i(2 + i, 0), 0)
		assert_object(shore).override_failure_message(
			"shape %d of the water block was never created, so a shoreline cell is empty" % i) \
				.is_not_null()
		assert_int(shore.get_collision_polygons_count(TileSetFactory.PHYSICS_LAYER)) \
			.override_failure_message("a water shore cell lets the player walk into the pond") \
			.is_equal(1)
		var verge := source.get_tile_data(Vector2i(5 + i, 0), 0)
		assert_object(verge).is_not_null()
		assert_int(verge.get_collision_polygons_count(TileSetFactory.PHYSICS_LAYER)) \
			.override_failure_message("the edge of a path blocks movement").is_equal(0)

func test_the_edge_blocks_are_looked_up_by_the_tile_that_owns_them() -> void:
	var by_id := TileSetFactory.edges_by_id({"edges": [
		{"tile": "water", "over": ["grass"], "first": 12, "count": 47},
		{"tile": "water", "over": ["path"], "first": 59, "count": 47},
		{"tile": "path", "over": ["grass"], "first": 106, "count": 47},
	]})
	assert_int((by_id["water"] as Array).size()).override_failure_message(
		"a tile with two edges kept one; the other material would never be drawn against") \
			.is_equal(2)
	assert_int((by_id["path"] as Array).size()).is_equal(1)
	assert_bool(by_id.has("grass")).override_failure_message(
		"a tile that owns no block was given one").is_false()
	assert_dict(TileSetFactory.edges_by_id({})).is_empty()

func test_every_shipped_style_declares_its_edge_blocks() -> void:
	# Always present, even as an empty list: a reader that has to tell "no edges" from "an older
	# table that predates them" is a branch nobody writes, and the drift gate would not see it.
	for style_id in ArtFixtures.style_ids():
		var meta := _tiles_meta(style_id)
		assert_bool(meta.has("edges")).override_failure_message(
			"%s/tiles.json names no edges at all" % style_id).is_true()
		var declared := TileGen.edge_blocks(ArtFixtures.tile_bank_for(ArtFixtures.style(style_id)))
		assert_int((meta["edges"] as Array).size()).override_failure_message(
			"%s declares %d edge blocks and its bank asks for %d"
			% [style_id, (meta["edges"] as Array).size(), declared.size()]) \
				.is_equal(declared.size())

func test_tiles_can_be_looked_up_by_name() -> void:
	# Map files name tiles, never column numbers: inserting a tile must not renumber a map.
	var coords := TileSetFactory.coords_by_id(_tiles_meta(&"gb16"))
	for id in _bank(&"gb16").ids():
		assert_bool(coords.has(id)).override_failure_message("no coords for tile '%s'" % id).is_true()

func test_a_tileset_without_a_tile_size_is_refused() -> void:
	var texture := load("res://assets/generated/gb16/tiles.png") as Texture2D
	assert_object(TileSetFactory.build(texture, {"tiles": []})).is_null()

func test_every_style_produces_the_same_tile_vocabulary() -> void:
	# Different palettes, different pixel SOURCES, same world vocabulary - otherwise a map
	# written for one style would not load under another, and the style swap would stop at the
	# characters. Over every style on disk rather than a named pair, because the pair goes stale
	# the moment a third one arrives, silently and while still passing.
	var first := PackedStringArray()
	var named := ""
	for style_id in ArtFixtures.style_ids():
		var ids := PackedStringArray(TileSetFactory.coords_by_id(_tiles_meta(style_id)).keys())
		ids.sort()
		assert_int(ids.size()).override_failure_message(
			"%s has no tiles at all" % style_id).is_greater(0)
		if named.is_empty():
			first = ids
			named = String(style_id)
			continue
		assert_array(ids).override_failure_message(
			"%s and %s do not paint from the same vocabulary" % [named, style_id]).is_equal(first)
	assert_int(ArtFixtures.style_ids().size()).is_greater(1)

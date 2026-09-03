extends GdUnitTestSuite
## Proves terrain is validated, not merely parsed - the sibling of test_rig_and_style.
##
## Tiles became authored text in M16, which means they inherited every failure mode a rig
## has: a ragged row, a typo'd pixel, a tile that is not the size it claims. All of them
## draw SOMETHING, so a bank that is merely parsed produces ground that is subtly wrong.
##
## The one fault a rig cannot have is a hole in the floor. A character is transparent almost
## everywhere; ground is opaque by definition, and a transparent pixel in it shows the
## window's background through the world.

const BAD_DIR := "res://tests/fixtures/spritegen/"

func _bank(style_id: StringName) -> TileBank:
	return ArtFixtures.tile_bank_for(ArtFixtures.style(style_id))

func test_the_shipped_banks_are_valid() -> void:
	for style_id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(style_id)
		var bank := ArtFixtures.tile_bank_for(style)
		assert_array(bank.problems()).override_failure_message(
			"%s tile bank: %s" % [style_id, bank.problems()]).is_empty()
		var images := ArtFixtures.tile_images_for(bank)
		var faults := TileGen.problems(bank, style, images)
		assert_array(faults).override_failure_message(
			"%s against its bank: %s" % [style_id, faults]).is_empty()
		assert_str(String(bank.id)).override_failure_message(
			"the '%s' bank calls itself '%s'; source_path() builds a directory out of that name"
			% [style.tile_bank_id, bank.id]).is_equal(String(style.tile_bank_id))

func test_a_ragged_tile_row_is_reported() -> void:
	var bank := TileBank.load_from(BAD_DIR + "tiles_ragged.json")
	assert_bool(bank.ok).is_true()
	assert_str(str(bank.problems())).contains("wide, expected")

func test_an_unknown_pixel_character_is_reported() -> void:
	# '4' is not a tone. Left unchecked it draws as nothing and quietly deletes pixels.
	var bank := TileBank.load_from(BAD_DIR + "tiles_bad_pixel.json")
	assert_str(str(bank.problems())).contains("unknown pixel")

func test_a_hole_in_a_ground_tile_is_reported() -> void:
	# Invisible while authoring: the tile looks right on its own, and only shows as a gap
	# once it is laid down in a map.
	var bank := TileBank.load_from(BAD_DIR + "tiles_holed.json")
	assert_str(str(bank.problems())).contains("transparent")

func test_a_decor_tile_may_be_transparent() -> void:
	# The near miss for the rule above. A rule that fires on everything gets disabled by
	# the next person, so the shipped bush - transparent almost everywhere - must be clean.
	var bank := _bank(&"gb16")
	assert_array(bank.decor_ids()).is_not_empty()
	assert_array(bank.problems()).is_empty()

func test_two_tiles_answering_to_one_name_are_reported() -> void:
	# A map names a tile by id, so a duplicate does not draw twice - it makes one of the two
	# unreachable, and which one loses is a property of the file's order.
	var bank := TileBank.load_from(BAD_DIR + "tiles_dupe_id.json")
	assert_str(str(bank.problems())).contains("declared twice")

func test_a_tile_that_is_not_the_banks_size_is_reported() -> void:
	var bank := TileBank.load_from(BAD_DIR + "tiles_wrong_size.json")
	assert_str(str(bank.problems())).contains("rows tall, expected")

func test_a_missing_bank_file_is_an_error_not_an_empty_bank() -> void:
	var bank := TileBank.load_from("res://data/tiles/does_not_exist.json")
	assert_bool(bank.ok).is_false()
	assert_str(str(bank.problems())).contains("did not load")

func test_a_style_whose_tile_size_disagrees_with_its_bank_is_reported() -> void:
	# Scaling pixel art is how a template starts looking like a mistake, so the mismatch is
	# refused rather than resized.
	var style := ArtFixtures.style(&"gb16")
	var odd := style.duplicate() as SpriteStyle
	odd.tile_size = style.tile_size + 8
	assert_str(str(TileGen.problems(_bank(&"gb16"), odd))).contains("authored at")

func test_a_tile_takes_its_ramp_from_the_bank_unless_the_style_overrides_it() -> void:
	# The default is what stops a new tile from being a mandatory edit to every style. The
	# override is what lets one style colour a tile differently, and nothing shipped uses it
	# today - so without this test the branch would rot.
	var style := ArtFixtures.style(&"gb16")
	var bank := _bank(&"gb16")
	var first := str(bank.at(0).get("id", ""))
	assert_str(bank.ramp_for(0, style)).is_equal(str(bank.at(0).get("ramp", "")))

	var repainted := style.duplicate() as SpriteStyle
	repainted.tile_ramps = {first: "stone"}
	assert_str(bank.ramp_for(0, repainted)).is_equal("stone")

func test_an_overridden_ramp_actually_changes_the_pixels() -> void:
	# ramp_for() returning a name is the proxy; the drawn tile is the outcome.
	var style := ArtFixtures.style(&"gb16")
	var bank := _bank(&"gb16")
	var repainted := style.duplicate() as SpriteStyle
	repainted.tile_ramps = {str(bank.at(0).get("id", "")): "stone"}
	var plain: Image = TileGen.build(style, bank)["image"]
	var swapped: Image = TileGen.build(repainted, bank)["image"]
	assert_str(Hashing.image_digest(plain)).is_not_equal(Hashing.image_digest(swapped))

func test_the_outline_character_draws_the_styles_outline_colour() -> void:
	# Terrain shares the rig's alphabet, which means it shares 'o'. Nothing shipped uses it
	# yet, so this fixture is the only thing keeping the branch honest - and the colour is
	# already inside palette_rgba32(), so an outlined tile passes the palette gate.
	var style := ArtFixtures.style(&"gb16")
	var bank := TileBank.load_from(BAD_DIR + "tiles_outlined.json")
	assert_array(bank.problems()).is_empty()
	var image: Image = TileGen.build(style, bank)["image"]
	assert_int(image.get_pixel(0, 0).to_rgba32()).is_equal(style.outline_color().to_rgba32())
	assert_int(image.get_pixel(8, 8).to_rgba32()).is_not_equal(style.outline_color().to_rgba32())

# -- a bank that cuts its pixels out of somebody's art -------------------------------------------
#
# Written against synthetic banks and one painted image rather than fixture files, because every
# rule below is about a PAIR of fields, and a fixture per pair is a directory nobody reads. The
# image is three cells by two, each a flat distinct colour with one darker pixel in it, so a cut
# that lands on the wrong cell - or swaps column for row - says so by colour.

const CUT_SIZE := 32
const CELL_COLOURS: Array = [
	Color8(200, 40, 40), Color8(40, 200, 40), Color8(40, 40, 200),
	Color8(200, 200, 40), Color8(200, 40, 200), Color8(40, 200, 200),
]

## Three cells across, two down, painted one colour each. `holed` punches the middle of cell
## (2,1) transparent - a hole that is invisible on the sheet and a gap in the world.
func _painted(holed := false, format := Image.FORMAT_RGBA8) -> Image:
	var img := Image.create_empty(3 * CUT_SIZE, 2 * CUT_SIZE, false, Image.FORMAT_RGBA8)
	for row in 2:
		for col in 3:
			var base: Color = CELL_COLOURS[row * 3 + col]
			for y in CUT_SIZE:
				for x in CUT_SIZE:
					# Never one flat colour: a tile that is would fail the shipped-art gate, and a
					# fixture that cannot tell "drew the cell" from "filled with its first pixel"
					# proves less than it looks.
					var c := base.darkened(0.4) if (x + y) % 8 == 0 else base
					img.set_pixel(col * CUT_SIZE + x, row * CUT_SIZE + y, c)
	if holed:
		img.set_pixel(2 * CUT_SIZE + 5, CUT_SIZE + 7, Color(0, 0, 0, 0))
	if format != Image.FORMAT_RGBA8:
		img.convert(format)
	return img

func _cut_bank(tiles: Array, files: Variant = null) -> TileBank:
	var credited: Array = files if files != null else [{
		"file": "art.png", "authors": ["Someone"], "licenses": ["CC-BY-SA 3.0"],
		"urls": ["https://example.invalid/art"],
	}]
	return TileBank.from_dictionary({
		"id": "cut", "tile": CUT_SIZE, "pixels_from": "files", "files": credited, "tiles": tiles,
	})

func _cut_style(licenses: Array[String] = ["CC0", "CC-BY", "OGA-BY", "CC-BY-SA"]) -> SpriteStyle:
	var style := SpriteStyle.new()
	style.id = &"cut32"
	style.tile_size = CUT_SIZE
	style.licenses = licenses
	return style

func _one_tile(cell: Array, decor := false) -> Array:
	return [{"id": "ground", "from": "art.png", "cell": cell, "solid": false, "decor": decor}]

func test_a_cut_lands_on_its_own_cell_and_a_column_is_not_a_row() -> void:
	# The mutant this is aimed at swaps x for y, which is invisible on a square sheet and on any
	# cell where column happens to equal row - so the cell under test is (2,1), whose transpose
	# (1,2) is off the bottom of the image entirely.
	var bank := _cut_bank(_one_tile([2, 1]))
	var images := {"art.png": _painted()}
	assert_array(TileGen.problems(bank, _cut_style(), images)).is_empty()
	var built := TileGen.build(_cut_style(), bank, images)
	var strip: Image = built["image"]
	assert_int(strip.get_pixel(1, 1).to_rgba32()).override_failure_message(
		"the cut came out %s, and cell (2,1) is %s"
		% [strip.get_pixel(1, 1), CELL_COLOURS[5]]).is_equal(CELL_COLOURS[5].to_rgba32())

func test_a_cut_tile_carries_no_ramp() -> void:
	# The colours are the artist's. A ramp name on an imported tile would read as a claim that
	# the style recoloured it, which is exactly what did not happen.
	var built := TileGen.build(_cut_style(), _cut_bank(_one_tile([0, 0])), {"art.png": _painted()})
	var entry: Dictionary = ((built["meta"] as Dictionary)["tiles"] as Array)[0]
	assert_str(str(entry["ramp"])).is_empty()
	assert_int(int(entry["index"])).is_equal(0)

func test_a_hole_in_a_cut_ground_tile_is_refused_by_tile_name() -> void:
	var bank := _cut_bank(_one_tile([2, 1]))
	var faults := TileGen.problems(bank, _cut_style(), {"art.png": _painted(true)})
	assert_str("\n".join(faults)).contains("'ground'")
	assert_str("\n".join(faults)).contains("transparent")

func test_a_cut_decor_tile_may_be_transparent() -> void:
	# The near miss. Most of these sheets are mostly transparent by design, so a rule that fired
	# on every one of them would be turned off by the next person to add a bush.
	var bank := _cut_bank(_one_tile([2, 1], true))
	assert_array(TileGen.problems(bank, _cut_style(), {"art.png": _painted(true)})).is_empty()

func test_art_that_decodes_without_an_alpha_channel_still_reaches_the_strip() -> void:
	# An opaque PNG decodes as RGB8, and the strip is RGBA8. `blit_rect` refuses a format it does
	# not share, so without a conversion the cut silently does not land and the tile comes out
	# EMPTY - which is why the assertion here is the pixel that arrived rather than the format it
	# arrived in. The same conversion is what stops the hole check reading alpha that is not there.
	var bank := _cut_bank(_one_tile([1, 0]))
	var flat := _painted(false, Image.FORMAT_RGB8)
	assert_array(TileGen.problems(bank, _cut_style(), {"art.png": flat})).override_failure_message(
		"an opaque sheet was refused, so the check is reading alpha that is not there").is_empty()
	var strip: Image = TileGen.build(_cut_style(), bank, {"art.png": flat})["image"]
	assert_int(strip.get_pixel(1, 1).to_rgba32()).override_failure_message(
		"cell (1,0) is %s and the strip holds %s - an opaque sheet never landed"
		% [CELL_COLOURS[1], strip.get_pixel(1, 1)]).is_equal(CELL_COLOURS[1].to_rgba32())

func test_a_cell_outside_the_image_is_refused_with_the_size_that_is_there() -> void:
	var faults := TileGen.problems(_cut_bank(_one_tile([3, 0])), _cut_style(),
		{"art.png": _painted()})
	assert_str("\n".join(faults)).contains("3 by 2 cells")

func test_art_that_is_not_on_disk_is_refused_by_the_path_it_was_looked_for_at() -> void:
	var faults := TileGen.problems(_cut_bank(_one_tile([0, 0])), _cut_style(), {})
	assert_str("\n".join(faults)).contains("data/imports/tiles/cut/art.png")

func test_a_file_licensed_outside_the_style_is_refused_by_name() -> void:
	var bank := _cut_bank(_one_tile([0, 0]), [{
		"file": "art.png", "authors": ["Someone"], "licenses": ["GPL 3.0"],
	}])
	var credit_only := _cut_style(["CC0", "CC-BY", "OGA-BY"] as Array[String])
	assert_str("\n".join(TileGen.problems(bank, credit_only, {"art.png": _painted()}))) \
		.contains("art.png").contains("GPL")
	# One accepted family is enough, and share-alike is not a longer spelling of CC-BY: the
	# credit-only style must still refuse it where the full one accepts it.
	var both := _cut_bank(_one_tile([0, 0]), [{
		"file": "art.png", "authors": ["Someone"], "licenses": ["GPL 3.0", "CC-BY-SA 3.0"],
	}])
	assert_array(TileGen.problems(both, _cut_style(), {"art.png": _painted()})).is_empty()
	assert_array(TileGen.problems(both, credit_only, {"art.png": _painted()})).is_not_empty()

func test_a_tile_cut_from_art_the_bank_does_not_credit_is_refused() -> void:
	# The one failure that cannot be fixed after release: art shipping with nobody named.
	var bank := _cut_bank([{"id": "ground", "from": "elsewhere.png", "cell": [0, 0]}])
	assert_str("\n".join(bank.problems())).contains("does not credit")

func test_a_credited_file_with_no_licence_or_no_author_is_refused() -> void:
	var bank := _cut_bank(_one_tile([0, 0]), [{"file": "art.png", "authors": [], "licenses": []}])
	assert_str("\n".join(bank.problems())).contains("names no licence")
	assert_str("\n".join(bank.problems())).contains("credits no author")

func test_a_bank_that_cuts_its_pixels_and_credits_nobody_is_refused() -> void:
	var bank := _cut_bank(_one_tile([0, 0]), [])
	assert_str("\n".join(bank.problems())).contains("credits none")

func test_the_two_shapes_cannot_be_mixed_in_one_tile() -> void:
	# Stated as a PAIR in both directions, because "it has no rows, so it must be a cut" is the
	# decode nobody remembers - and a bank halfway between the two draws something either way.
	var cutting := _cut_bank([{"id": "ground", "from": "art.png", "cell": [0, 0],
		"rows": [".".repeat(CUT_SIZE)]}])
	assert_str("\n".join(cutting.problems())).contains("authored in rows")
	var drawing := TileBank.from_dictionary({"id": "d", "tile": 2, "tiles": [
		{"id": "ground", "from": "art.png", "cell": [0, 0], "rows": ["22", "22"]}]})
	assert_str("\n".join(drawing.problems())).contains("draws its own rows")

func test_a_cell_must_be_a_column_and_a_row() -> void:
	for bad: Array in [[0], [-1, 0], [0, -1], []]:
		assert_str("\n".join(_cut_bank(_one_tile(bad)).problems())).override_failure_message(
			"cell %s was accepted" % [bad]).contains("wants a column and a row")

func test_an_unknown_pixel_source_is_refused_by_name() -> void:
	# A typo that silently read as `rows` would be a bank whose art never arrives, standing beside
	# a credits list nothing consumes - and both halves look right on their own.
	var bank := TileBank.from_dictionary({"id": "t", "tile": 2, "pixels_from": "flies",
		"tiles": [{"id": "ground", "rows": ["22", "22"]}]})
	assert_str("\n".join(bank.problems())).contains("'flies'")
	assert_bool(bank.imports()).is_false()


# -- a bank whose tiles have EDGES ---------------------------------------------------------------
#
# The ring is twelve pieces plus an optional centre, and `over` says what the edge is drawn
# against. Both halves are synthetic here for _cut_bank's own reason: every rule below is about a
# PAIR of fields, and the shipped bank can only ever show the one arrangement that is correct.

const RING_SIZE := 4

## Every piece of a ring, cut from the same cell. Enough to satisfy the shape rules; WHICH piece
## reaches which quarter is test_terrain_edges.gd's question, over images it paints itself.
func _ring_cells(cell: Array = [0, 0]) -> Dictionary:
	var ring := {}
	for key in TerrainEdges.RING_KEYS:
		ring[key] = {"cell": cell}
	return ring

## The same for an authored bank: `clear_rows` rows of transparent, then the tile's own tone.
func _ring_rows(clear_rows := 1) -> Dictionary:
	var rows: Array[String] = []
	for i in RING_SIZE:
		rows.append(".".repeat(RING_SIZE) if i < clear_rows else "2".repeat(RING_SIZE))
	var ring := {}
	for key in TerrainEdges.RING_KEYS:
		ring[key] = {"rows": rows}
	return ring

## A two-tile authored bank: plain ground, and a material that draws an edge against it.
func _rows_bank_with_ring(ring: Variant = null, over: Variant = null,
		extra: Dictionary = {}) -> TileBank:
	var solid := {"id": "water", "ramp": "terrain_water", "rows": ["2222", "2222", "2222", "2222"]}
	solid["ring"] = _ring_rows() if ring == null else ring
	solid["over"] = [["grass"]] if over == null else over
	solid.merge(extra, true)
	return TileBank.from_dictionary({"id": "edged", "tile": RING_SIZE, "tiles": [
		{"id": "grass", "ramp": "terrain_grass", "rows": ["1111", "1111", "1111", "1111"]},
		solid,
	]})

func _rows_style() -> SpriteStyle:
	var style := ArtFixtures.style(&"gb16").duplicate() as SpriteStyle
	style.tile_size = RING_SIZE
	return style

func test_a_ring_and_what_it_lies_over_are_required_together() -> void:
	# Either alone is a tile that looks finished and draws nothing: a ring with nothing to be an
	# edge against is never reached, and an over with no ring names a neighbour it has no pixels
	# for. Stated in both directions, because half of this is the half that ships.
	assert_str("\n".join(_rows_bank_with_ring(_ring_rows(), []).problems())) \
		.contains("names nothing for it to be an edge against")
	assert_str("\n".join(_rows_bank_with_ring({}, [["grass"]]).problems())) \
		.contains("names no ring to draw there")
	assert_array(_rows_bank_with_ring().problems()).override_failure_message(
		"a correctly ringed bank was refused").is_empty()

func test_a_tile_with_no_ring_at_all_is_left_alone() -> void:
	# The near miss, and the shape every shipped bank was in until this milestone: no ring, no
	# over, and nothing to say about either.
	var plain := TileBank.from_dictionary({"id": "flat", "tile": RING_SIZE, "tiles": [
		{"id": "grass", "ramp": "terrain_grass", "rows": ["1111", "1111", "1111", "1111"]}]})
	assert_array(plain.problems()).is_empty()
	assert_bool(plain.has_ring(0)).is_false()
	assert_dict(plain.piece_of(0, "n")).override_failure_message(
		"a tile with no ring answered with a piece").is_empty()

func test_a_decor_tile_may_not_carry_a_ring() -> void:
	# Decor stands ON the ground and keeps its own transparency, so it has no boundary with
	# anything - and composing one would put a bush-shaped hole over a shoreline.
	var faults := _rows_bank_with_ring(null, null, {"decor": true}).problems()
	assert_str("\n".join(faults)).contains("is decor and carries a ring")

func test_a_ring_key_that_is_not_a_piece_is_refused_by_name() -> void:
	# A typo'd key is a piece that is simply never drawn: the quarter falls back to fill, the
	# cell reads as ground, and nothing else anywhere complains.
	var ring := _ring_rows()
	ring["nw_inn"] = ring["nw_in"]
	assert_str("\n".join(_rows_bank_with_ring(ring).problems())).contains("'nw_inn'")

func test_a_missing_piece_is_refused_by_the_name_of_the_piece() -> void:
	for missing in TerrainEdges.RING_KEYS:
		var ring := _ring_rows()
		ring.erase(missing)
		assert_str("\n".join(_rows_bank_with_ring(ring).problems())).override_failure_message(
			"a ring with no '%s' was accepted" % missing).contains("ring has no '%s' piece" % missing)

func test_the_centre_piece_is_the_one_a_ring_need_not_name() -> void:
	# It defaults to the tile's own plain art, so an interior cell comes out exactly as it did
	# before the tile had a ring - which is what leaves a map with no shorelines untouched.
	assert_array(_rows_bank_with_ring().problems()).is_empty()
	var ring := _ring_rows()
	ring[TerrainEdges.CENTRE_KEY] = {"rows": ["2222", "2222", "2222", "2222"]}
	assert_array(_rows_bank_with_ring(ring).problems()).is_empty()

func test_a_piece_may_be_transparent_where_a_tile_may_not() -> void:
	# The clear half of a piece is the whole reason an edge composes over the ground beside it
	# rather than replacing it. A rule that fired here would be turned off by the first shoreline.
	assert_array(_rows_bank_with_ring(_ring_rows(RING_SIZE - 1)).problems()).override_failure_message(
		"a ring piece was reported as a hole in the ground").is_empty()
	# The near miss in the other direction: the TILE itself still may not be.
	var holed := _rows_bank_with_ring(null, null, {"rows": ["..22", "2222", "2222", "2222"]})
	assert_str("\n".join(holed.problems())).contains("transparent")

func test_a_ragged_piece_is_still_refused_and_says_which_piece() -> void:
	var ring := _ring_rows()
	ring["se"] = {"rows": ["222", "2222", "2222", "2222"]}
	var faults := "\n".join(_rows_bank_with_ring(ring).problems())
	assert_str(faults).contains("ring 'se'").contains("wide, expected")

func test_a_tile_cannot_draw_an_edge_against_itself_or_a_stranger() -> void:
	assert_str("\n".join(_rows_bank_with_ring(null, [["water"]]).problems())) \
		.contains("is listed among the tiles it draws an edge against")
	assert_str("\n".join(_rows_bank_with_ring(null, [["lava"]]).problems())) \
		.contains("this bank has no tile for")
	assert_str("\n".join(_rows_bank_with_ring(null, [[]]).problems())) \
		.contains("empty group")

func test_a_tile_may_not_draw_an_edge_against_decor() -> void:
	# The edge is composed over the other tile's plain art, and decor has none to lie on - it is
	# a shape standing on somebody else's ground.
	var bank := TileBank.from_dictionary({"id": "edged", "tile": RING_SIZE, "tiles": [
		{"id": "bush", "ramp": "terrain_bush", "decor": true,
			"rows": ["1111", "1111", "1111", "1111"]},
		{"id": "water", "ramp": "terrain_water", "rows": ["2222", "2222", "2222", "2222"],
			"ring": _ring_rows(), "over": [["bush"]]},
	]})
	assert_str("\n".join(bank.problems())).contains("has no ").contains("ground of its own")

func test_one_neighbour_may_not_sit_in_two_groups() -> void:
	# Which edge the cell draws would then depend on which group was read first, and both
	# readings are defensible - so it is refused rather than resolved.
	var faults := _rows_bank_with_ring(null, [["grass"], ["grass"]]).problems()
	assert_str("\n".join(faults)).contains("in more than one group")

func test_a_cut_ring_piece_outside_its_sheet_is_refused_by_the_piece() -> void:
	var ring := _ring_cells()
	ring["n"] = {"cell": [9, 9]}
	var bank := _cut_bank([{"id": "ground", "from": "art.png", "cell": [0, 0],
		"ring": ring, "over": [["other"]]},
		{"id": "other", "from": "art.png", "cell": [1, 0]}])
	var faults := "\n".join(TileGen.problems(bank, _cut_style(), {"art.png": _painted()}))
	assert_str(faults).contains("ring 'n'").contains("3 by 2 cells")

func test_a_cut_ring_piece_defaults_to_the_art_its_tile_is_cut_from() -> void:
	# Naming the sheet twelve times per tile is twelve chances to name it differently once.
	var bank := _cut_bank([{"id": "ground", "from": "art.png", "cell": [0, 0],
		"ring": _ring_cells(), "over": [["other"]]},
		{"id": "other", "from": "art.png", "cell": [1, 0]}])
	assert_str(str(bank.piece_of(0, "n").get("from", ""))).is_equal("art.png")
	assert_array(TileGen.problems(bank, _cut_style(), {"art.png": _painted()})).is_empty()


# -- the atlas those edges ask for ---------------------------------------------------------------

func test_the_atlas_grows_a_block_of_shapes_for_every_edge_a_tile_draws() -> void:
	var bank := _rows_bank_with_ring()
	assert_int(TileGen.cell_count(bank)).override_failure_message(
		"two tiles and one edge should be 2 + 47 columns").is_equal(2 + TerrainEdges.MASKS.size())
	var blocks := TileGen.edge_blocks(bank)
	assert_int(blocks.size()).is_equal(1)
	assert_int(int((blocks[0] as Dictionary)["first"])).override_failure_message(
		"the shapes must start after the plain tiles, or a map's own tile ids move") \
		.is_equal(bank.size())
	var built := TileGen.build(_rows_style(), bank)
	var meta: Dictionary = built["meta"]
	assert_int(int(meta["columns"])).is_equal(2 + TerrainEdges.MASKS.size())
	assert_int((built["image"] as Image).get_width()).override_failure_message(
		"the strip is not as wide as the meta says it is") \
		.is_equal(RING_SIZE * (2 + TerrainEdges.MASKS.size()))
	var edges: Array = meta["edges"]
	assert_int(edges.size()).is_equal(1)
	var block: Dictionary = edges[0]
	assert_str(str(block["tile"])).is_equal("water")
	assert_int(int(block["count"])).is_equal(TerrainEdges.MASKS.size())
	assert_array(JsonFile.to_string_array(block["over"])).is_equal(["grass"] as Array[String])

func test_a_bank_with_no_rings_is_the_atlas_it_always_was() -> void:
	for style_id in ArtFixtures.style_ids():
		var bank := ArtFixtures.tile_bank_for(ArtFixtures.style(style_id))
		if TileGen.edge_blocks(bank).is_empty():
			assert_int(TileGen.cell_count(bank)).override_failure_message(
				"%s has no rings and asked for more columns than it has tiles" % style_id) \
				.is_equal(bank.size())

func test_the_first_shape_in_a_block_is_the_plain_tile_itself() -> void:
	# The cell with nothing open, so an interior cell of a ringed material needs no special case
	# anywhere downstream - it draws the shape at `first` and that shape IS the flat tile.
	var built := TileGen.build(_rows_style(), _rows_bank_with_ring())
	var strip: Image = built["image"]
	var first := int(((built["meta"] as Dictionary)["edges"] as Array)[0]["first"])
	for y in RING_SIZE:
		for x in RING_SIZE:
			assert_int(strip.get_pixel(first * RING_SIZE + x, y).to_rgba32()) \
				.override_failure_message("the interior shape differs from its tile at %d,%d"
					% [x, y]).is_equal(strip.get_pixel(1 * RING_SIZE + x, y).to_rgba32())

func test_an_atlas_too_wide_for_a_texture_is_refused_with_both_numbers() -> void:
	# A ring costs 47 columns a group, so this is a ceiling somebody reaches by authoring rather
	# than a theoretical one - and the atlas is a single strip, so width is what runs out first.
	var huge := 512
	var bank := TileBank.from_dictionary({"id": "vast", "tile": huge, "tiles": [
		{"id": "grass", "ramp": "terrain_grass"},
		{"id": "water", "ramp": "terrain_water", "ring": _ring_rows(), "over": [["grass"]]},
	]})
	var style := ArtFixtures.style(&"gb16").duplicate() as SpriteStyle
	style.tile_size = huge
	var faults := "\n".join(TileGen.problems(bank, style, {}))
	assert_str(faults).contains("%d" % TileGen.MAX_ATLAS_WIDTH).contains("columns")

func test_an_odd_tile_size_cannot_be_quartered_into_edges() -> void:
	# An edge is four quarters of a tile, so an odd size divides into halves that do not cover
	# it - and the seam would run down the middle of every shoreline.
	var bank := TileBank.from_dictionary({"id": "odd", "tile": 3, "tiles": [
		{"id": "grass", "ramp": "terrain_grass"},
		{"id": "water", "ramp": "terrain_water", "ring": _ring_rows(), "over": [["grass"]]},
	]})
	var style := ArtFixtures.style(&"gb16").duplicate() as SpriteStyle
	style.tile_size = 3
	assert_str("\n".join(TileGen.problems(bank, style, {}))).contains("needs an even size")

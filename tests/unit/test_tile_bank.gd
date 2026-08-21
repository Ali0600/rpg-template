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
		assert_array(TileGen.problems(bank, style)).override_failure_message(
			"%s against its bank: %s" % [style_id, TileGen.problems(bank, style)]).is_empty()

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

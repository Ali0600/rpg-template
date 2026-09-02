extends GdUnitTestSuite
## Proves the hand-authored data files are validated, not merely parsed.
##
## A rig and a style are text a person edits. The failure modes are therefore ragged ASCII
## rows, typo'd pixel characters, a ramp with two tones instead of three, a part placed
## where it hangs off the cell - and every one of them draws SOMETHING. A generator that
## accepts them produces art that is subtly wrong, which is far more expensive than art that
## fails to build.

const BAD_RIG_DIR := "res://tests/fixtures/spritegen/"

func test_the_shipped_rigs_and_styles_are_valid() -> void:
	for style_id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(style_id)
		assert_array(style.problems()).override_failure_message(
			"%s: %s" % [style_id, style.problems()]).is_empty()
		if style.imports():
			continue  # no rig to load; test_imported_art.gd gates its sheets
		var rig := ArtFixtures.rig_for(style)
		assert_array(rig.problems()).override_failure_message(
			"%s rig: %s" % [style_id, rig.problems()]).is_empty()

func test_a_ragged_part_row_is_reported() -> void:
	# The commonest authoring mistake: one row a character short. It composes fine and puts
	# a notch in the sprite.
	var rig := Rig.load_from(BAD_RIG_DIR + "rig_ragged.json")
	assert_bool(rig.ok).is_true()
	var problems := rig.problems()
	assert_int(problems.size()).is_greater(0)
	assert_str(str(problems)).contains("wide, expected")

func test_an_unknown_pixel_character_is_reported() -> void:
	# '4' is not a tone. Left unchecked it draws as transparent and quietly deletes pixels.
	var rig := Rig.load_from(BAD_RIG_DIR + "rig_bad_pixel.json")
	assert_str(str(rig.problems())).contains("unknown pixel")

func test_a_part_hanging_off_the_cell_is_reported() -> void:
	# Silently clipped, and reads as a missing limb rather than a placement mistake.
	var rig := Rig.load_from(BAD_RIG_DIR + "rig_offcell.json")
	assert_str(str(rig.problems())).contains("outside the")

func test_a_missing_rig_file_is_an_error_not_an_empty_rig() -> void:
	var rig := Rig.load_from("res://data/rigs/does_not_exist.json")
	assert_bool(rig.ok).is_false()
	assert_str(str(rig.problems())).contains("did not load")

func test_frame_map_lets_four_walk_frames_share_three_drawings() -> void:
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var f0 := rig.stamp("shoes_basic", &"front", 0)
	var f1 := rig.stamp("shoes_basic", &"front", 1)
	var f2 := rig.stamp("shoes_basic", &"front", 2)
	var f3 := rig.stamp("shoes_basic", &"front", 3)
	# 0 and 2 are the same passing pose; 1 and 3 are the two contact poses.
	assert_array(f0["rows"]).is_equal(f2["rows"])
	assert_array(f1["rows"]).is_not_equal(f3["rows"])
	assert_array(f1["rows"]).is_not_equal(f0["rows"])

func test_a_view_a_part_does_not_draw_returns_nothing_rather_than_failing() -> void:
	# The face has no back view, and that is a legitimate answer, not an error.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	assert_array(rig.stamp("face_dots", &"back", 0)["rows"]).is_empty()
	assert_array(rig.stamp("face_dots", &"front", 0)["rows"]).is_not_empty()

func test_a_style_with_a_two_tone_ramp_is_reported() -> void:
	var style := ArtFixtures.style(&"gb16").duplicate() as SpriteStyle
	var ramps := style.ramps.duplicate(true)
	ramps["broken"] = ["#000000", "#ffffff"]
	style.ramps = ramps
	assert_str(str(style.problems())).contains("expected 3")

func test_a_style_whose_bob_does_not_match_its_frame_count_is_reported() -> void:
	# A bob array one entry short reads the wrong offset on the last frame - a one-pixel
	# stutter that is genuinely hard to see and impossible to un-see afterwards.
	var style := ArtFixtures.style(&"gb16").duplicate() as SpriteStyle
	style.walk_frames = 6
	assert_str(str(style.problems())).contains("bob_offsets")

func test_slots_that_must_share_a_colour_do() -> void:
	# Bare hands are the same skin as the face; sleeves are the same cloth as the body. If
	# this drifts, a randomised dark-skinned villager gets pale hands.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	for seed_value in [1, 5, 12, 30, 77]:
		var spec := CharacterSpec.new()
		spec.style_id = &"gb16"
		spec.seed = seed_value
		var ramps: Dictionary = spec.resolve(rig, style)["ramps"]
		assert_str(str(ramps["hands"])).override_failure_message(
			"seed %d: hands do not match the head" % seed_value).is_equal(str(ramps["head"]))
		assert_str(str(ramps["arms"])).override_failure_message(
			"seed %d: sleeves do not match the body" % seed_value).is_equal(str(ramps["body"]))

func test_an_explicit_ramp_beats_the_shared_colour_rule() -> void:
	# The alias fills a blank; it does not overrule an author who wanted gloves.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var spec := CharacterSpec.new()
	spec.style_id = &"gb16"
	spec.seed = 3
	spec.ramps = {"hands": "leather", "head": "skin_dark"}
	var ramps: Dictionary = spec.resolve(rig, style)["ramps"]
	assert_str(str(ramps["hands"])).is_equal("leather")

func test_a_character_naming_an_unknown_part_is_reported() -> void:
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var spec := CharacterSpec.new()
	spec.id = &"broken"
	spec.style_id = &"gb16"
	spec.parts = {"hair": "hair_mohawk"}
	assert_str(str(spec.problems(rig, style))).contains("unknown part")

func test_a_character_putting_a_part_in_the_wrong_slot_is_reported() -> void:
	# Boots in the hair slot draw at the boots' own position, so the sprite looks fine and
	# is simply missing its hair.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var spec := CharacterSpec.new()
	spec.id = &"broken"
	spec.style_id = &"gb16"
	spec.parts = {"hair": "shoes_basic"}
	assert_str(str(spec.problems(rig, style))).contains("in slot")

func test_every_slot_a_view_draws_has_at_least_one_part() -> void:
	# A slot in the draw order with nothing to fill it is a silently invisible layer.
	for style_id in ArtFixtures.rig_style_ids():
		var rig := ArtFixtures.rig_for(ArtFixtures.style(style_id))
		for slot in rig.slots():
			assert_array(rig.part_ids_for_slot(slot)).override_failure_message(
				"slot '%s' has no parts" % slot).is_not_empty()

func _imported_style() -> SpriteStyle:
	var s := SpriteStyle.new()
	s.id = &"lab"
	s.sheets_from = SpriteStyle.SHEETS_FROM_LPC
	s.cell_size = Vector2i(64, 64)
	s.tile_size = 32
	s.rig_id = &""
	s.licenses = JsonFile.to_string_array(["CC0", "CC-BY-SA"])
	s.ramps = {"x": ["#000000", "#777777", "#ffffff"]}
	return s

func test_a_valid_imported_style_reports_nothing() -> void:
	assert_array(_imported_style().problems()).is_empty()

func test_an_unknown_sheet_source_is_reported() -> void:
	# The save_policy rule: a typo'd axis value fails the build rather than silently reading
	# as the default, where a style that meant "import" would generate from a rig it never named.
	var style := _imported_style()
	style.sheets_from = &"psd"
	assert_str("\n".join(style.problems())).contains("sheets_from 'psd'")

func test_an_imported_style_may_not_name_a_rig() -> void:
	var style := _imported_style()
	style.rig_id = &"gb16"
	assert_str("\n".join(style.problems())).contains("names rig 'gb16'")

func test_a_style_drawn_at_no_scale_at_all_is_refused() -> void:
	# A zero here is a window of no size and a layer scaled to nothing - a game that boots to
	# a blank screen with every gate green, because every screen would still lay itself out
	# correctly inside a world nobody can see.
	var style := _imported_style()
	style.world_scale = 0
	assert_str("\n".join(style.problems())).contains("world_scale must be at least 1")
	style.world_scale = 1
	assert_array(style.problems()).is_empty()


func test_an_imported_style_must_list_its_licences() -> void:
	# An empty list would mean "anything" or "nothing", and a licence policy must not be a guess.
	var style := _imported_style()
	style.licenses = JsonFile.to_string_array([])
	assert_str(str(style.problems())).contains("licence families")

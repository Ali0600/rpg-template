extends GdUnitTestSuite
## Same inputs, same pixels - and different inputs, different pixels.
##
## Every other guarantee in the generator rests on this. Without reproducibility the drift
## gate cannot mean anything ("the art changed" would always be true), a golden hash is
## noise, and a bug report about one NPC cannot be reproduced by anyone else. The second
## half matters just as much: a generator that ignores its seed is perfectly reproducible
## and completely useless, and it passes the first test.

func test_the_same_spec_produces_identical_pixels_every_time() -> void:
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var spec := ArtFixtures.characters_of(&"gb16")[0]
	var first := SheetBuilder.build(rig, style, spec)
	var second := SheetBuilder.build(rig, style, spec)
	assert_str(Hashing.image_digest(first["image"])).is_equal(Hashing.image_digest(second["image"]))

func test_a_different_seed_produces_different_pixels() -> void:
	# The seed must actually reach the drawing. A generator whose randomised slots silently
	# always pick the first option would pass every determinism check ever written.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var digests: Array[String] = []
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var spec := CharacterSpec.new()
		spec.id = StringName("seeded_%d" % seed_value)
		spec.style_id = &"gb16"
		spec.seed = seed_value
		var built := SheetBuilder.build(rig, style, spec)
		var digest := Hashing.image_digest(built["image"])
		if not digests.has(digest):
			digests.append(digest)
	# Not every seed must differ - with a handful of parts, collisions are expected and fine.
	# What matters is that the seed moves the result at all, and moves it more than once.
	assert_int(digests.size()).is_greater(2)

func test_resolution_is_stable_across_calls() -> void:
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var spec := CharacterSpec.new()
	spec.style_id = &"gb16"
	spec.seed = 99
	assert_dict(spec.resolve(rig, style)).is_equal(spec.resolve(rig, style))

func test_adding_a_slot_choice_does_not_reshuffle_the_others() -> void:
	# Each slot draws from its own derived stream. If they shared one, adding a hat - or one
	# more shirt colour - would restyle every existing NPC, and a template whose whole cast
	# changes when you add an option is not one anybody can build on.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var spec := CharacterSpec.new()
	spec.style_id = &"gb16"
	spec.seed = 44
	var before: Dictionary = spec.resolve(rig, style)["ramps"]

	var widened := style.duplicate() as SpriteStyle
	var choices := widened.ramp_choices.duplicate(true)
	choices["legs"] = ["pants_brown", "pants_blue", "pants_grey", "cloth_red", "cloth_green"]
	widened.ramp_choices = choices
	var after: Dictionary = spec.resolve(rig, widened)["ramps"]

	for slot: Variant in before.keys():
		if str(slot) == "legs":
			continue
		assert_str(str(after.get(slot, ""))) \
			.override_failure_message("slot '%s' changed when only 'legs' gained options" % slot) \
			.is_equal(str(before[slot]))

func test_committed_art_matches_what_the_generator_produces_now() -> void:
	# The drift gate, as a test as well as a build step. Generated art is build output, and
	# build output that no longer matches its source is the quiet failure: someone edits a
	# rig, forgets to regenerate, and the game ships the old sprites while the repo
	# describes the new ones.
	for style_id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(style_id)
		var rig := ArtFixtures.rig_for(style)
		for spec in ArtFixtures.characters_of(style_id):
			var path := ArtFixtures.generated_texture_path(style_id, spec.id)
			var committed := ImageFile.read_png(path)
			assert_object(committed).override_failure_message(
				"%s is missing - run tools/gen_sprites.gd" % path).is_not_null()
			var fresh: Image = SheetBuilder.build(rig, style, spec)["image"]
			assert_str(Hashing.image_digest(committed)).override_failure_message(
				"%s is out of date - re-run tools/gen_sprites.gd and commit the result" % path) \
				.is_equal(Hashing.image_digest(fresh))

func test_committed_tiles_match_the_generator() -> void:
	for style_id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(style_id)
		var path := "res://assets/generated/%s/tiles.png" % style_id
		var committed := ImageFile.read_png(path)
		assert_object(committed).is_not_null()
		var fresh: Image = TileGen.build(style, ArtFixtures.tile_bank_for(style))["image"]
		assert_str(Hashing.image_digest(committed)).override_failure_message(
			"%s is out of date - re-run tools/gen_sprites.gd" % path) \
			.is_equal(Hashing.image_digest(fresh))

extends GdUnitTestSuite
## The PNG + JSON contract, and the factory that turns it into playable animations.
##
## This is the seam the whole template hangs on: as long as an art source writes this pair,
## the game does not care whether the pixels came from the procedural rig, a downloaded
## pack or an AI generator. So the contract is tested from both sides - that what the
## generator writes is complete, and that what the factory accepts is validated.

const CLIPS := ["idle", "walk"]

func _meta_for(style_id: StringName, character_id: StringName) -> SheetMeta:
	var file := JsonFile.read(ArtFixtures.generated_meta_path(style_id, character_id))
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	return SheetMeta.from_dict(file.data)

func test_every_committed_sheet_describes_itself_correctly() -> void:
	# sheet_ids_of, not characters_of: an imported sheet is a committed pair the game loads
	# exactly like a generated one, and a contract over "every pair" that skipped them would be
	# a contract over some.
	for style_id in ArtFixtures.style_ids():
		for id in ArtFixtures.sheet_ids_of(style_id):
			var meta := _meta_for(style_id, id)
			var texture := load(ArtFixtures.generated_texture_path(style_id, id)) as Texture2D
			assert_object(texture).is_not_null()
			assert_array(meta.problems(texture.get_size())).override_failure_message(
				"%s/%s: %s" % [style_id, id, meta.problems(texture.get_size())]).is_empty()

func test_rows_are_in_canonical_direction_order() -> void:
	# The single most damaging thing that can silently drift. Asserted against a literal
	# list, not against Dir.ALL, so a change to the constant cannot make this agree with it.
	for style_id in ArtFixtures.style_ids():
		for id in ArtFixtures.sheet_ids_of(style_id):
			var meta := _meta_for(style_id, id)
			assert_int(meta.row_of(Dir.D.DOWN)).is_equal(0)
			assert_int(meta.row_of(Dir.D.LEFT)).is_equal(1)
			assert_int(meta.row_of(Dir.D.RIGHT)).is_equal(2)
			assert_int(meta.row_of(Dir.D.UP)).is_equal(3)

func test_a_freshly_built_sheet_uses_canonical_row_order() -> void:
	# The test above reads what is committed; this one reads what the builder produces right
	# now. Both are needed: the first catches art that shipped wrong, the second catches a
	# builder that would write it wrong next time.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var meta: SheetMeta = SheetBuilder.build(rig, style, ArtFixtures.characters_of(&"gb16")[0])["meta"]
	assert_int(meta.row_of(Dir.D.DOWN)).is_equal(0)
	assert_int(meta.row_of(Dir.D.LEFT)).is_equal(1)
	assert_int(meta.row_of(Dir.D.RIGHT)).is_equal(2)
	assert_int(meta.row_of(Dir.D.UP)).is_equal(3)

func test_a_freshly_built_sheet_measures_its_anchor_from_the_pixels() -> void:
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var meta: SheetMeta = SheetBuilder.build(rig, style, ArtFixtures.characters_of(&"gb16")[0])["meta"]
	assert_int(meta.anchor.y).is_equal(style.cell_size.y - 1)

func test_the_factory_builds_every_clip_in_every_direction() -> void:
	# Eight animations, not seven. A factory that quietly drops one produces a character who
	# cannot face a direction, which looks like a movement bug rather than an art one.
	var texture := load(ArtFixtures.generated_texture_path(&"gb16", &"hero")) as Texture2D
	var meta := _meta_for(&"gb16", &"hero")
	var frames := SpriteFramesFactory.build(texture, meta)
	assert_object(frames).is_not_null()
	for clip in CLIPS:
		for dir: int in Dir.ALL:
			var name := Dir.anim_name(StringName(clip), dir)
			assert_bool(frames.has_animation(name)).override_failure_message(
				"missing animation '%s'" % name).is_true()
			assert_int(frames.get_frame_count(name)).is_greater(0)
	assert_int(frames.get_animation_names().size()).is_equal(CLIPS.size() * Dir.ALL.size())

func test_the_factory_drops_the_placeholder_default_animation() -> void:
	# SpriteFrames is born holding an animation nobody asked for; leaving it makes
	# has_animation answer true for a clip that does not exist.
	var texture := load(ArtFixtures.generated_texture_path(&"gb16", &"hero")) as Texture2D
	var frames := SpriteFramesFactory.build(texture, _meta_for(&"gb16", &"hero"))
	assert_bool(frames.has_animation(&"default")).is_false()

func test_walk_frames_come_from_the_right_row() -> void:
	# Proves the row->direction mapping reaches the atlas regions, not just the names.
	var texture := load(ArtFixtures.generated_texture_path(&"gb16", &"hero")) as Texture2D
	var meta := _meta_for(&"gb16", &"hero")
	var frames := SpriteFramesFactory.build(texture, meta)
	for dir: int in Dir.ALL:
		var atlas := frames.get_frame_texture(Dir.anim_name(&"walk", dir), 0) as AtlasTexture
		assert_object(atlas).is_not_null()
		assert_int(int(atlas.region.position.y)).override_failure_message(
			"'%s' reads row %d" % [Dir.anim_name(&"walk", dir), int(atlas.region.position.y) / meta.cell.y]) \
			.is_equal(meta.row_of(dir) * meta.cell.y)

func test_a_sheet_labelled_with_compass_names_still_lands_in_canonical_rows() -> void:
	# What an outside source most often looks like. The aliases exist so a pack can describe
	# itself in its own vocabulary without anybody hand-editing its metadata.
	var file := JsonFile.read("res://tests/fixtures/spritegen/external_meta_compass.json")
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	var meta := SheetMeta.from_dict(file.data)
	assert_array(meta.problems()).is_empty()
	# This fixture lists its rows north, east, south, west - a different order AND a
	# different vocabulary. Both must resolve.
	assert_int(meta.row_of(Dir.D.UP)).is_equal(0)
	assert_int(meta.row_of(Dir.D.RIGHT)).is_equal(1)
	assert_int(meta.row_of(Dir.D.DOWN)).is_equal(2)
	assert_int(meta.row_of(Dir.D.LEFT)).is_equal(3)

func test_a_sheet_whose_metadata_disagrees_with_its_image_is_rejected() -> void:
	# Fail closed. A factory that trusts the metadata builds regions that run off the
	# texture, and the result is invisible frames rather than an error.
	var texture := load(ArtFixtures.generated_texture_path(&"gb16", &"hero")) as Texture2D
	var meta := _meta_for(&"gb16", &"hero")
	meta.columns = meta.columns + 3
	assert_array(meta.problems(texture.get_size())).is_not_empty()
	assert_object(SpriteFramesFactory.build(texture, meta)).is_null()

func test_metadata_faults_are_all_reported() -> void:
	var meta := SheetMeta.new()
	meta.cell = Vector2i(16, 24)
	meta.columns = 4
	meta.rows = 2
	meta.directions = [Dir.D.DOWN, Dir.D.DOWN]  # duplicated, and too few for four rows
	meta.animations = {"walk": {"frames": [0, 9], "fps": 0, "loop": true}}
	meta.anchor = Vector2i(8, 99)
	var problems := meta.problems()
	# A validator that stops at the first fault turns four data bugs into four round trips.
	assert_int(problems.size()).is_greater_equal(4)

func test_an_unknown_direction_label_is_named_not_silently_dropped() -> void:
	var meta := SheetMeta.from_dict({
		"version": 1, "cell": [16, 24], "columns": 4, "rows": 1,
		"directions": ["sideways"],
		"animations": {"walk": {"frames": [0], "fps": 8, "loop": true}},
		"anchor": [8, 23],
	})
	var problems := meta.problems()
	assert_int(problems.size()).is_greater(0)
	assert_str(problems[0]).contains("unrecognised direction")

func test_the_anchor_sits_on_the_ground_row() -> void:
	# Other systems place a character's feet using this value, so it has to be measured
	# from the pixels rather than declared - a stated anchor drifts the moment the rig does.
	for style_id in ArtFixtures.style_ids():
		var style := ArtFixtures.style(style_id)
		for spec in ArtFixtures.characters_of(style_id):
			var meta := _meta_for(style_id, spec.id)
			assert_int(meta.anchor.y).is_equal(style.cell_size.y - 1)
			assert_int(meta.anchor.x).is_equal(style.cell_size.x / 2)

func test_the_file_source_reads_what_the_generator_wrote() -> void:
	# End to end across the contract: bytes on disk in, playable animations out.
	var source := FileSpriteSource.create(&"gb16")
	var frames := source.sprite_frames(&"hero")
	assert_object(frames).is_not_null()
	assert_bool(frames.has_animation(&"walk_down")).is_true()

func test_the_procedural_source_produces_the_same_contract_without_files() -> void:
	# The swappable-source promise, demonstrated: a different implementation, same output.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var source := ProceduralSpriteSource.create(style, rig, ArtFixtures.characters_of(&"gb16"))
	var frames := source.sprite_frames(&"hero")
	assert_object(frames).is_not_null()
	assert_array(frames.get_animation_names()).is_equal(
		SpriteFramesFactory.build(
			load(ArtFixtures.generated_texture_path(&"gb16", &"hero")),
			_meta_for(&"gb16", &"hero")).get_animation_names())

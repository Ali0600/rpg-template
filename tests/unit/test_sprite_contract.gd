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
	meta.portrait = Rect2i(2, 1, 12, 12)
	var problems := meta.problems()
	# A validator that stops at the first fault turns four data bugs into four round trips.
	assert_int(problems.size()).is_greater_equal(4)

func test_an_unknown_direction_label_is_named_not_silently_dropped() -> void:
	var meta := SheetMeta.from_dict({
		"version": SheetMeta.VERSION, "cell": [16, 24], "columns": 4, "rows": 1,
		"directions": ["sideways"],
		"animations": {"walk": {"frames": [0], "fps": 8, "loop": true}},
		"anchor": [8, 23], "portrait": [2, 1, 12, 12],
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


func test_a_generated_sheet_carries_a_face_measured_from_its_own_pixels() -> void:
	# The rig arm's half of the portrait rule, over every character of every rig style rather
	# than one - a measurement that is right for the hero and wrong for the child body is exactly
	# what a fixed offset would give, and it is invisible until somebody looks at a menu.
	var seen := 0
	for style_id in ArtFixtures.rig_style_ids():
		var style := ArtFixtures.style(style_id)
		for character in ArtFixtures.characters_of(style_id):
			var meta := _meta_for(style_id, character.id)
			assert_int(meta.portrait.size.x).override_failure_message(
				"%s/%s has no face" % [style_id, character.id]).is_equal(style.portrait_size)
			# Inside its cell, and around the column the character stands in. Both are in
			# problems() too; asserted here as well because this is the suite that reads the
			# COMMITTED files, and a sheet regenerated wrongly would still satisfy its own
			# metadata.
			assert_bool(Rect2i(Vector2i.ZERO, meta.cell).encloses(meta.portrait)) \
				.override_failure_message("%s/%s has a face outside its cell"
				% [style_id, character.id]).is_true()
			assert_int(meta.portrait.position.x).is_less_equal(meta.anchor.x)
			assert_int(meta.portrait.end.x).is_greater(meta.anchor.x)
			seen += 1
	assert_int(seen).override_failure_message(
		"no generated character was measured, so this proved nothing").is_greater(3)

func test_a_face_is_not_a_square_of_nothing() -> void:
	# Containment is one-sided: an empty rect and a rect over the character's feet are both
	# inside the cell. This is the constraint in the units the design declares - there are drawn
	# pixels in there, and they are the ones at the TOP of the character.
	for style_id in ArtFixtures.rig_style_ids():
		for character in ArtFixtures.characters_of(style_id):
			var meta := _meta_for(style_id, character.id)
			var img := ImageFile.read_png(
				ArtFixtures.generated_texture_path(StringName(style_id), character.id))
			assert_object(img).is_not_null()
			img.convert(Image.FORMAT_RGBA8)
			var row := meta.row_of(Dir.D.DOWN)
			var cut := img.get_region(Rect2i(
				meta.portrait.position + Vector2i(0, row * meta.cell.y), meta.portrait.size))
			assert_int(SpriteCompositor.top_row(cut)).override_failure_message(
				"%s/%s: the face is a square of nothing" % [style_id, character.id]) \
				.is_greater_equal(0)
			assert_int(SpriteCompositor.top_row(cut)).override_failure_message(
				"%s/%s: the face starts %d rows below the top of the square, so it was measured "
				% [style_id, character.id, SpriteCompositor.top_row(cut)]
				+ "off some other frame").is_equal(0)


func _face_meta() -> SheetMeta:
	# A sheet that is correct in every way except the one each test below breaks.
	var meta := SheetMeta.new()
	meta.cell = Vector2i(16, 24)
	meta.columns = 4
	meta.rows = 4
	meta.directions = Dir.ALL.duplicate()
	meta.animations = {"idle": {"frames": [0], "fps": 4, "loop": true}}
	meta.anchor = Vector2i(8, 23)
	meta.portrait = Rect2i(2, 1, 12, 12)
	return meta

func test_the_face_fixture_is_otherwise_clean() -> void:
	# The control every refusal below rests on. Without it each of them could be passing because
	# of some other fault in the fixture, and the check it names could be gone.
	assert_array(_face_meta().problems()).is_empty()

func test_a_sheet_with_no_face_is_refused() -> void:
	var meta := _face_meta()
	meta.portrait = Rect2i()
	assert_str("\n".join(meta.problems())).override_failure_message(
		"a sheet with no face at all is accepted, and every menu draws an empty square"
	).contains("no portrait")

func test_a_face_that_is_not_square_is_refused() -> void:
	var meta := _face_meta()
	meta.portrait = Rect2i(2, 1, 12, 8)
	assert_str("\n".join(meta.problems())).contains("not square")

func test_a_face_outside_its_own_cell_is_refused() -> void:
	# An atlas region past the cell samples whatever is drawn under it, which is the same
	# character facing somewhere else - a portrait of the back of somebody's head.
	var meta := _face_meta()
	meta.portrait = Rect2i(2, 20, 12, 12)
	assert_str("\n".join(meta.problems())).contains("outside")

func test_a_face_that_does_not_straddle_the_character_is_refused() -> void:
	# The one that catches a face measured off the WRONG FRAME rather than a mistyped number.
	# Every other check here passes for a square cut from the corner of the cell; only this one
	# knows where the character actually stands.
	var meta := _face_meta()
	meta.portrait = Rect2i(0, 1, 4, 4)
	assert_str("\n".join(meta.problems())).override_failure_message(
		"a face beside the character rather than over them is accepted"
	).contains("not centred")

func test_a_generated_face_is_cut_from_the_standing_frame() -> void:
	# Built rather than read: the tests above this read COMMITTED sheets, so a generator that
	# started cutting faces out of a walking frame would not move them until somebody regenerated.
	# The bob raises the upper body a pixel on the passing frames, so the standing pose and the
	# stride genuinely differ - which is what makes this an assertion.
	var style := ArtFixtures.style(&"gb16")
	var rig := ArtFixtures.rig_for(style)
	var spec := ArtFixtures.characters_of(&"gb16")[0]
	var built := SheetBuilder.build(rig, style, spec)
	var meta: SheetMeta = built["meta"]
	var standing := SpriteCompositor.compose(rig, style, spec.resolve(rig, style), Dir.D.DOWN, 0)
	assert_int(meta.portrait.position.y).override_failure_message(
		"the face starts at y=%d where the standing frame's pixels start at %d"
		% [meta.portrait.position.y, SpriteCompositor.top_row(standing)]) \
		.is_equal(SpriteCompositor.top_row(standing))

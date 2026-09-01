extends GdUnitTestSuite
## The gates an IMPORTED style answers to, over the real files.
##
## The consistency gates draw every frame through the rig and cannot draw an import, so an
## imported style leaves them (ArtFixtures.rig_style_ids) and enters here. What can be asked of
## art the template did not draw: that every input has committed output which describes
## itself, that the cast stands on one ground line, that every layer is credited under a
## licence the style accepts, and that the inputs are not shipped. A palette rule would be
## meaningless - these pixels are the artists', not the style's.

func _meta(style_id: StringName, id: StringName) -> SheetMeta:
	var file := JsonFile.read(ArtFixtures.generated_meta_path(style_id, id))
	assert_bool(file.ok).override_failure_message(file.error).is_true()
	return SheetMeta.from_dict(file.data)

func test_every_imported_character_has_output_that_describes_itself() -> void:
	var checked := 0
	for style_id in ArtFixtures.imported_style_ids():
		var ids := ArtFixtures.imported_characters_of(style_id)
		assert_array(ids).override_failure_message(
			"%s imports its sheets and has nothing under data/imports/%s" % [style_id, style_id]).is_not_empty()
		for id in ids:
			var texture := load(ArtFixtures.generated_texture_path(style_id, id)) as Texture2D
			assert_object(texture).override_failure_message(
				"%s/%s has no committed sheet - run tools/gen_sprites.gd" % [style_id, id]).is_not_null()
			var meta := _meta(style_id, id)
			assert_array(meta.problems(texture.get_size())).override_failure_message(
				"%s/%s: %s" % [style_id, id, meta.problems(texture.get_size())]).is_empty()
			assert_str(meta.source).is_equal("lpc")
			# Canonical rows, against literals: the re-cut is the whole point of the importer.
			assert_int(meta.row_of(Dir.D.DOWN)).is_equal(0)
			assert_int(meta.row_of(Dir.D.LEFT)).is_equal(1)
			assert_int(meta.row_of(Dir.D.RIGHT)).is_equal(2)
			assert_int(meta.row_of(Dir.D.UP)).is_equal(3)
			checked += 1
	# The template ships one imported style, so an empty run here is the gate not looking.
	assert_int(checked).override_failure_message("no imported character was measured").is_greater(0)

func test_an_imported_cast_stands_on_one_ground_line() -> void:
	for style_id in ArtFixtures.imported_style_ids():
		var rows: Array[int] = []
		for id in ArtFixtures.imported_characters_of(style_id):
			var meta := _meta(style_id, id)
			# Inside the cell and below its middle: feet, not a hat.
			assert_int(meta.anchor.y).is_greater(meta.cell.y / 2)
			assert_int(meta.anchor.y).is_less(meta.cell.y)
			if not rows.has(meta.anchor.y):
				rows.append(meta.anchor.y)
		assert_int(rows.size()).override_failure_message(
			"%s characters stand on %d different rows: %s" % [style_id, rows.size(), rows]).is_equal(1)

func test_every_layer_is_credited_under_a_licence_the_style_accepts() -> void:
	for style_id in ArtFixtures.imported_style_ids():
		var style := ArtFixtures.style(style_id)
		var summary := JsonFile.read("%s/%s/credits.json" % [ArtFixtures.GENERATED_ROOT, style_id])
		assert_bool(summary.ok).override_failure_message(summary.error).is_true()
		var credited: Array[String] = []
		for entry: Dictionary in summary.data["files"] as Array:
			credited.append(str(entry["file"]))
		for id in ArtFixtures.imported_characters_of(style_id):
			var recipe := JsonFile.read("%s/character.json" % ArtFixtures.import_dir(style_id, id))
			assert_bool(recipe.ok).override_failure_message(recipe.error).is_true()
			var files := LpcImport.credits_of(recipe.data)
			assert_array(files).override_failure_message("%s/%s credits nobody" % [style_id, id]).is_not_empty()
			for c: Dictionary in files:
				assert_array(credited).override_failure_message(
					"%s/%s uses %s, which credits.json does not name" % [style_id, id, c["file"]]) \
					.contains([str(c["file"])])
				var allowed := false
				for l in JsonFile.to_string_array(c["licenses"]):
					if LpcImport.license_allowed(l, style):
						allowed = true
				assert_bool(allowed).override_failure_message(
					"%s/%s: %s is licensed %s, outside %s" % [style_id, id, c["file"], c["licenses"], style.licenses]) \
					.is_true()
		assert_bool(FileAccess.file_exists("%s/%s/LICENSE.txt" % [ArtFixtures.GENERATED_ROOT, style_id])) \
			.override_failure_message("%s ships imported art with no licence notice beside it" % style_id).is_true()

func test_committed_imports_match_what_the_importer_produces_now() -> void:
	# The drift gate as a test, on test_determinism's terms: an input edited without
	# regenerating would ship the old sprite while the repository described the new one. The
	# same check that makes any mutant of the converter visible here, since the committed
	# output was made by the unmutated one.
	var checked := 0
	for style_id in ArtFixtures.imported_style_ids():
		var style := ArtFixtures.style(style_id)
		for id in ArtFixtures.imported_characters_of(style_id):
			var folder := ArtFixtures.import_dir(style_id, id)
			var image := ImageFile.read_png(folder + "/" + ArtFixtures.IMPORT_SHEET)
			var recipe := JsonFile.read(folder + "/character.json")
			assert_object(image).is_not_null()
			assert_bool(recipe.ok).is_true()
			assert_array(LpcImport.problems(image, recipe.data, style)).is_empty()
			var built := LpcImport.build(image, recipe.data, style, String(id))
			var path := ArtFixtures.generated_texture_path(style_id, id)
			var committed := ImageFile.read_png(path)
			assert_object(committed).override_failure_message("%s is missing" % path).is_not_null()
			assert_str(Hashing.image_digest(committed)).override_failure_message(
				"%s is out of date - re-run tools/gen_sprites.gd and commit the result" % path) \
				.is_equal(Hashing.image_digest(built["image"]))
			var meta: SheetMeta = built["meta"]
			assert_str(JSON.stringify(_meta(style_id, id).to_dict())).is_equal(JSON.stringify(meta.to_dict()))
			checked += 1
	assert_int(checked).is_greater(0)

func test_the_inputs_are_kept_out_of_the_editor_and_the_pack() -> void:
	# A .gdignore is what stops the importer turning every 832x3456 input into a texture and
	# the exporter packing it. pack_check.sh proves the outcome; this pins the mechanism.
	assert_bool(FileAccess.file_exists(ArtFixtures.IMPORT_ROOT + "/.gdignore")).is_true()

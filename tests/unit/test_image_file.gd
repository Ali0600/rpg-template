extends GdUnitTestSuite
## Reading a committed PNG as pixels, without the import system.
##
## The reader exists to keep `Image.load_from_file`'s export warning out of the build log - it
## fired 21 times per art-drift run, and a log people learn to skim is a log where the next
## real warning goes unread. But swapping how a gate READS its inputs is exactly the kind of
## change that can quietly make it read nothing, so the reader gets its own suite: a decoder
## that returned null for everything would leave the drift gate comparing absence to absence.

const SHEETS := "res://assets/generated/dusk16"


func test_there_is_something_to_check() -> void:
	assert_int(ContentScan.files(SHEETS, ["png"]).size()).is_greater(0)


func test_a_committed_sheet_reads_at_the_size_its_metadata_declares() -> void:
	# Measured against the sheet's OWN json rather than against numbers typed here, so this
	# keeps meaning something after a style changes its cell size - and it ties the reader to
	# real shipped art instead of a fixture that can drift away from it.
	var checked := 0
	for path in ContentScan.files(SHEETS, ["png"]):
		var meta_path := path.get_basename() + ".sheet.json"
		if not FileAccess.file_exists(meta_path):
			continue  # tiles.png and the contact sheet have no sheet metadata
		var file := JsonFile.read(meta_path)
		var cell := JsonFile.to_int_array(file.data.get("cell", []))
		if cell.size() != 2:
			continue
		var image := ImageFile.read_png(path)
		assert_object(image).override_failure_message(
			"%s did not read at all" % path).is_not_null()
		assert_int(image.get_width()).override_failure_message(
			"%s is %d wide, its metadata says %d columns of %d"
			% [path, image.get_width(), int(file.data.get("columns", 0)), cell[0]]
		).is_equal(int(file.data.get("columns", 0)) * cell[0])
		assert_int(image.get_height()).is_equal(int(file.data.get("rows", 0)) * cell[1])
		checked += 1
	assert_int(checked).override_failure_message(
		"no sheet was actually measured, so this proved nothing").is_greater(0)


func test_the_pixels_are_real_and_not_a_blank_of_the_right_size() -> void:
	# The control that matters for a decoder: an all-transparent image of the correct
	# dimensions would satisfy every assertion above, and would make the art-drift gate agree
	# that every sprite matches every other.
	var image := ImageFile.read_png(SHEETS + "/quest_wanderer.png")
	assert_object(image).is_not_null()
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				opaque += 1
	assert_int(opaque).override_failure_message(
		"the sheet decoded to nothing but empty pixels").is_greater(0)


func test_a_file_that_is_not_there_reads_as_nothing() -> void:
	# Null rather than a crash, because the callers have something better to say: the drift
	# gate names the file it could not read, which a crash inside here would lose.
	assert_object(ImageFile.read_png(SHEETS + "/no_such_character.png")).is_null()


func test_a_file_that_is_not_a_png_reads_as_nothing() -> void:
	var json_beside_it := SHEETS + "/quest_wanderer.sheet.json"
	assert_bool(FileAccess.file_exists(json_beside_it)).override_failure_message(
		"the not-a-png fixture is missing, so this test proves nothing").is_true()
	assert_object(ImageFile.read_png(json_beside_it)).is_null()

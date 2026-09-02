extends GdUnitTestSuite
## Does every shipped line FIT in the box that draws it?
##
## This gate exists because the answer was no and nothing said so. A RichTextLabel with
## scrolling off does not wrap past its height, does not scroll and does not complain - it
## CLIPS. So a line written one word too long is a fact that never reaches the player, on a
## screen that looks perfectly normal. Four shipped nodes were doing exactly that when this
## suite was written, three of them lines added to tell the player where to go.
##
## It measures with the REAL font at the REAL width rather than counting characters, because
## proportional glyphs make a character count a guess: "MMMM" and "iiii" are not the same line.
##
## Every number comes from DialogBox itself. A gate holding its own copy of the box's capacity
## is two sources of truth for one question, and the day they drift is the day the overflow
## goes quiet again.

const DIALOG_DIR := "res://data/dialog"


func _font() -> Font:
	return ThemeDB.fallback_font


## The width the box is BUILT with, which is the design size at every world scale - not the
## live viewport, which doubles for a 32px style while the box's own constants do not.
func _viewport_width() -> int:
	return UiScale.DESIGN_SIZE.x


func _lines_used(text: String, width: float) -> int:
	if text.is_empty():
		return 0
	var size := _font().get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, width, DialogBox.FONT_SIZE)
	return int(round(size.y / float(DialogBox.LINE_HEIGHT)))


func test_there_is_something_to_check() -> void:
	# A loop over an empty directory validates nothing and reports success.
	assert_int(ContentScan.files(DIALOG_DIR, ["json"]).size()).is_greater(0)


func test_the_font_is_the_one_the_box_was_measured_against() -> void:
	# The whole gate rests on this. If a project theme ever replaces the default font, every
	# measurement below becomes a statement about a font nobody sees - so it is asserted here
	# rather than assumed, and this is the test that fails first when it changes.
	var label := Label.new()
	add_child(label)
	assert_object(label.get_theme_font(&"font")).override_failure_message(
		"the box is drawn in a font this gate does not measure").is_equal(_font())
	assert_int(int(_font().get_height(DialogBox.FONT_SIZE))).override_failure_message(
		"DialogBox.LINE_HEIGHT no longer matches the font it describes"
	).is_equal(DialogBox.LINE_HEIGHT)
	label.free()


func test_every_shipped_line_fits_the_window_that_draws_it() -> void:
	var width := DialogBox.text_width(_viewport_width())
	var faults: Array[String] = []
	for path in ContentScan.files(DIALOG_DIR, ["json"]):
		var file := JsonFile.read(path)
		var nodes := file.get_dict("nodes")
		for node_id: Variant in nodes.keys():
			var node: Dictionary = nodes[node_id]
			var used := _lines_used(str(node.get("text", "")), width)
			if used > DialogBox.TEXT_LINES:
				faults.append("%s/%s uses %d lines, the box shows %d - split it with `next`"
					% [path.get_file(), node_id, used, DialogBox.TEXT_LINES])
	assert_array(faults).override_failure_message(
		"lines that will be silently cut off:\n  " + "\n  ".join(faults)).is_empty()


func test_every_shipped_choice_fits_its_row() -> void:
	# A choice is one Label on one row - it cannot wrap at all, so an over-long one is cut
	# mid-word with no ellipsis. The cursor and its padding eat into the width, so they are
	# measured as part of the string rather than hand-waved.
	var width := DialogBox.text_width(_viewport_width()) - 4.0
	var faults: Array[String] = []
	for path in ContentScan.files(DIALOG_DIR, ["json"]):
		var file := JsonFile.read(path)
		var nodes := file.get_dict("nodes")
		for node_id: Variant in nodes.keys():
			var node: Dictionary = nodes[node_id]
			var choices: Array = node.get("choices", [])
			if choices.size() > DialogBox.MAX_CHOICES:
				faults.append("%s/%s offers %d choices, the box draws %d"
					% [path.get_file(), node_id, choices.size(), DialogBox.MAX_CHOICES])
			for choice: Variant in choices:
				var label := "> " + str((choice as Dictionary).get("text", ""))
				if _lines_used(label, width) > 1:
					faults.append("%s/%s choice '%s' is wider than its row"
						% [path.get_file(), node_id, label])
	assert_array(faults).override_failure_message(
		"choices that will be cut off:\n  " + "\n  ".join(faults)).is_empty()


func test_a_line_written_too_long_is_caught() -> void:
	# The control, and the proof this gate can fail: a line nobody would write, measured the
	# same way. Without it a gate that always returned zero faults would look identical.
	var width := DialogBox.text_width(_viewport_width())
	var wall := "The key went west into the hollow under the roots of the one bush that grows down there, and what nests beside it now is the reason nobody has ever fetched it back."
	assert_int(_lines_used(wall, width)).override_failure_message(
		"the measurement cannot tell a long line from a short one").is_greater(DialogBox.TEXT_LINES)
	assert_int(_lines_used("Short enough.", width)).is_equal(1)


func test_the_box_makes_room_for_what_it_is_asked_to_draw() -> void:
	# The layout arithmetic, without a scene: choices get a band of their own BELOW every line
	# of text, and the box grows to hold them rather than drawing them over the story.
	assert_int(DialogBox.CHOICE_Y).override_failure_message(
		"the choice band starts inside the text area, which is the overlap this fixed"
	).is_greater_equal(DialogBox.TEXT_Y + DialogBox.TEXT_LINES * DialogBox.LINE_HEIGHT)
	assert_int(DialogBox.height_for(0)).is_equal(DialogBox.BOX_HEIGHT)
	var counts: Array[int] = [1, 2, 3, DialogBox.MAX_CHOICES]
	for count in counts:
		var last_row: int = DialogBox.CHOICE_Y + (count - 1) * DialogBox.CHOICE_PITCH + DialogBox.LINE_HEIGHT
		assert_int(DialogBox.height_for(count)).override_failure_message(
			"with %d choices the last row falls outside the box" % count).is_greater_equal(last_row)
		assert_int(DialogBox.height_for(count)).override_failure_message(
			"a box with %d choices is not taller than one with none" % count
		).is_greater(DialogBox.BOX_HEIGHT)

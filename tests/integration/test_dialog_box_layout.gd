extends GdUnitTestSuite
## Where the box actually PUTS things, measured off the nodes it built.
##
## The fit gate next door proves a line fits the window. This proves the window and the choice
## list are not the same pixels - which is a different claim, and the one that shipped broken:
## choices were positioned under where one line of text would end, so the moment a line wrapped
## the first choice was drawn on top of it. Every headless gate passed throughout, because
## pressing through a conversation never looks at it.
##
## So it asserts RECTS, not constants. A test that re-derived the positions from the same
## arithmetic the box uses would agree with it while both were wrong.

const STYLE := "res://data/styles/dusk16.tres"
const VIEWPORT := Vector2i(320, 180)

var _box: DialogBox


func before_test() -> void:
	_box = DialogBox.new()
	add_child(_box)
	_box.setup(load(STYLE) as SpriteStyle, VIEWPORT)


func after_test() -> void:
	if _box != null and is_instance_valid(_box):
		_box.free()
	_box = null


## A conversation whose one line WRAPS and which then asks a question - the exact shape that
## broke. Built here rather than loaded so the test keeps meaning something after a writer
## shortens the shipped line that used to break it.
func _wrapping_choice_dialog() -> DialogRunner:
	return DialogRunner.from_dict({
		"id": "fixture", "start": "ask",
		"nodes": {
			"ask": {
				"speaker": "Warden",
				"text": "The key went west, into the hollow - under the roots of the one bush that grows down there.",
				"choices": [
					{"text": "I'll go and look.", "next": "yes"},
					{"text": "Sounds like your problem.", "next": "no"}]},
			"yes": {"speaker": "Warden", "text": "Good."},
			"no": {"speaker": "Warden", "text": "Fair."}}})


func _panel() -> ColorRect:
	return SceneHelpers.find_all_by_class(_box, "ColorRect")[0] as ColorRect


func _text_label() -> RichTextLabel:
	return SceneHelpers.find_all_by_class(_box, "RichTextLabel")[0] as RichTextLabel


func _visible_choices() -> Array[Label]:
	var out: Array[Label] = []
	for node in SceneHelpers.find_all_by_class(_box, "Label"):
		var label := node as Label
		# The speaker is a Label too, and it is always visible - the choices are the ones the
		# box turns on for a line that has them.
		if label.visible and label.position.y >= DialogBox.CHOICE_Y:
			out.append(label)
	return out


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## One real press, released. The typewriter runs on idle frames, so this waits on those too -
## a reveal that has not finished swallows the press that would have chosen something.
func _press() -> void:
	var down := InputEventAction.new()
	down.action = &"interact"
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(2)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)
	await await_idle_frame()
	await _steps(1)


func test_a_choice_is_never_drawn_over_the_text() -> void:
	# The bug, as geometry: two rectangles that must not intersect.
	assert_bool(_box.open(_wrapping_choice_dialog())).is_true()
	await _steps(2)
	var text := _text_label()
	var text_rect := Rect2(text.position, text.size)
	var choices := _visible_choices()
	assert_int(choices.size()).override_failure_message(
		"the line asked a question and no choice was drawn").is_equal(2)
	for i in choices.size():
		var row := Rect2(choices[i].position, Vector2(10.0, float(DialogBox.LINE_HEIGHT)))
		assert_bool(text_rect.intersects(row)).override_failure_message(
			"choice %d is drawn inside the text area (text %s, choice %s)"
			% [i, text_rect, row]).is_false()


func test_every_choice_fits_inside_the_box() -> void:
	# The other half: moving the choices below the text is only a fix if the box grew to hold
	# them. Off the bottom edge is as unreadable as on top of the story.
	_box.open(_wrapping_choice_dialog())
	await _steps(2)
	var panel_height := _panel().size.y
	for label in _visible_choices():
		assert_float(label.position.y + float(DialogBox.LINE_HEIGHT)).override_failure_message(
			"a choice row runs off the bottom of a %dpx box" % int(panel_height)
		).is_less_equal(panel_height)


func test_the_text_area_is_as_tall_as_the_lines_it_promises() -> void:
	# It was 22px against a 12px line, so the box could only ever really show one - and the
	# second line of every two-line node was cut in half with nothing reporting it.
	var text := _text_label()
	assert_float(text.size.y).override_failure_message(
		"the text area cannot show the %d lines the fit gate allows" % DialogBox.TEXT_LINES
	).is_greater_equal(float(DialogBox.TEXT_LINES * DialogBox.LINE_HEIGHT))


func test_the_box_only_takes_the_room_it_needs() -> void:
	# It grows for a decision and gives the world back afterwards. The control matters: a box
	# that were always tall enough for choices would pass the two tests above and cover a
	# quarter of the screen for every line of small talk.
	_box.open(_wrapping_choice_dialog())
	await _steps(2)
	var asking := _panel().size.y
	var asking_top := _panel().position.y

	# Answer it; the reply has no choices. TWO presses, and that is the box's own rule rather
	# than padding: the first press on a still-revealing line completes the text, and only a
	# press on a fully-revealed choice line picks anything.
	await _press()
	await _press()

	assert_float(_panel().size.y).override_failure_message(
		"the box stayed choice-sized after the choice was made").is_less(asking)
	assert_float(_panel().position.y).override_failure_message(
		"the box grew downward, off the bottom of the screen").is_greater(asking_top)

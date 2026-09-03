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
## The same conversation with a face on it, and one without - the pair every assertion about the
## portrait column needs, because a box that always reserved the column would pass a test that
## only ever looked at a line with a speaker.
func _faced_dialog(face := "quest_warden") -> DialogRunner:
	return DialogRunner.from_dict({
		"id": "faces", "start": "one",
		"nodes": {
			"one": {"speaker": "Warden", "portrait": face,
				"text": "Something took the keep.", "next": "two"},
			"two": {"speaker": "The well", "text": "It is deep, and it is dry."}}})


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


## The window itself. By CLASS since M42 rather than "the first ColorRect", which the box's own
## header band became the moment it was a frame - and a 10px band is a box every choice runs off
## the bottom of.
func _panel() -> Panel:
	return SceneHelpers.find_all_by_class(_box, "Panel")[0] as Panel


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


func _face() -> TextureRect:
	var found := SceneHelpers.find_all_by_class(_box, "TextureRect")
	return null if found.is_empty() else found[0] as TextureRect


func test_the_speaker_is_named_in_the_window_s_own_band() -> void:
	# Persona puts the name in a tab above the box's corner; at 320x180 there is nowhere for a tab
	# to sit, so it goes in the header band - which is the adaptation GENRE_CONVENTIONS S6 states.
	# Either way it is not a line of the text, which is where it used to be.
	_box.open(_faced_dialog(), FileSpriteSource.create(&"dusk16"))
	await _steps(2)
	var bands := SceneHelpers.find_all_by_class(_box, "ColorRect")
	var header: ColorRect = null
	for node in bands:
		if UiChrome.kind_of(node) == UiChrome.HEADER:
			header = node as ColorRect
	assert_object(header).override_failure_message(
		"the box has no header band, so the speaker is a line of the conversation").is_not_null()
	var named := false
	for node in SceneHelpers.find_all_by_class(header, "Label"):
		named = named or (node as Label).text == "WARDEN"
	assert_bool(named).override_failure_message(
		"the band does not name the speaker").is_true()

func test_a_speaker_with_a_face_is_drawn_with_it() -> void:
	_box.open(_faced_dialog(), FileSpriteSource.create(&"dusk16"))
	await _steps(2)
	var face := _face()
	assert_object(face).override_failure_message("nobody's face was drawn").is_not_null()
	assert_bool(face.visible).override_failure_message(
		"the warden names a portrait and none is shown").is_true()
	assert_float(face.size.x).is_equal(UiChrome.portrait_span(_box._style))

func test_a_line_nobody_is_credited_with_shows_no_face_and_takes_the_whole_width() -> void:
	# The other half, and the one that makes the first an assertion: a box that always reserved
	# the column would pass every test above while narrowing a well's own words for no reason.
	var box := _box
	box.open(_faced_dialog(), FileSpriteSource.create(&"dusk16"))
	await _steps(2)
	var faced := box._text.position.x
	var narrow := box._text.size.x
	# The second node is the well, which names no portrait.
	box._runner.advance()
	box._show_line()
	await _steps(2)
	var face := _face()
	assert_bool(face == null or not face.visible).override_failure_message(
		"a well is drawn with somebody's face").is_true()
	assert_float(box._text.position.x).override_failure_message(
		"an unattributed line is still indented past a face that is not there").is_less(faced)
	assert_float(box._text.size.x).override_failure_message(
		"an unattributed line does not get the room the missing face frees").is_greater(narrow)

func test_a_face_that_cannot_be_drawn_costs_the_line_no_room() -> void:
	# A portrait naming a character with no sheet under the running style. The content gate
	# refuses that in shipped data; this is what the box does if one reaches it anyway, and the
	# answer is the same as no portrait at all rather than an indent around an empty square.
	_box.open(_faced_dialog("nobody_drew_this"), FileSpriteSource.create(&"dusk16"))
	await _steps(2)
	var face := _face()
	assert_bool(face == null or not face.visible).is_true()
	assert_float(_box._text.position.x).is_equal(float(DialogBox.PADDING))

func test_the_cursor_covers_the_answer_it_is_on() -> void:
	# What replaced the "> " that used to be written into the front of a choice's own text - and
	# then stripped back off with substr(2) to redraw it.
	_box.open(_wrapping_choice_dialog())
	await _steps(2)
	var choices := _visible_choices()
	assert_int(choices.size()).is_equal(2)
	assert_bool(_box._select.visible).override_failure_message(
		"a question is up and no answer is marked").is_true()
	var bar := Rect2(_box._select.position, _box._select.size)
	assert_bool(bar.has_point(choices[0].position)).override_failure_message(
		"the cursor does not reach the answer it is on").is_true()
	assert_bool(bar.has_point(choices[1].position)).override_failure_message(
		"the cursor covers BOTH answers, so it says nothing about which is chosen").is_false()

	# And it MOVES. Covering the first answer is true before anybody has chosen anything, so a
	# bar parked there passes every assertion above while saying nothing - which is what a
	# surviving mutant said about the version of this test that stopped here.
	_box._choice_index = 1
	_box._paint_choices()
	var moved := Rect2(_box._select.position, _box._select.size)
	assert_bool(moved.has_point(choices[1].position)).override_failure_message(
		"the cursor moved to the second answer and the bar stayed on the first").is_true()
	assert_bool(moved.has_point(choices[0].position)).is_false()

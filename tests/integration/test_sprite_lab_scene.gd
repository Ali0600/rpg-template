extends GdUnitTestSuite
## Sprite Lab shows an IMPORTED style from its committed sheets, and still shows a rig style
## live - driven by the keys a person would press, because the lab is where the first
## hand-drawn character is judged and a lab that could not reach it would be judged empty.

const LAB_SCENE := "res://scenes/sprite_lab/sprite_lab.tscn"

## Press and release through the input pipeline, the way Qa.press does: parse_input_event
## reaches _unhandled_input where action_press would only set polled state. A queued event lands
## a frame or two later than the await that sent it, so a press is ENDED by watching `label`
## change - bounded - rather than by counting frames; the first draft counted, sent presses the
## lab had not seen yet, and read the style two steps past the one it meant.
func _press(action: StringName, label: Label) -> void:
	var before := label.text
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await await_idle_frame()
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	for i in 10:
		if label.text != before:
			return
		await await_idle_frame()
	assert_str(label.text).override_failure_message(
		"pressing %s changed nothing within 10 frames" % action).is_not_equal(before)

func _lab() -> Node2D:
	var lab: Node2D = auto_free(load(LAB_SCENE).instantiate())
	add_child(lab)
	await await_idle_frame()
	return lab

## Cycles styles with the down key until the title names `style_id`, bounded: a lab that never
## reaches it fails here rather than looping.
func _reach(lab: Node2D, style_id: String) -> void:
	for i in 8:
		if String(lab._title.text).begins_with(style_id + " / "):
			return
		await _press(&"move_down", lab._title)
	assert_str(String(lab._title.text)).override_failure_message(
		"the lab never reached style '%s'" % style_id).starts_with(style_id + " / ")

func test_the_lab_opens_on_a_rig_style_showing_a_character() -> void:
	var lab := await _lab()
	# Styles are sorted; dusk16 comes first and has a cast.
	assert_str(String(lab._title.text)).starts_with("dusk16 / ")
	for i in Dir.ALL.size():
		assert_str(String(lab._views[i].current_animation())) \
			.is_equal(String(Dir.anim_name(&"walk", Dir.ALL[i])))

func test_an_imported_style_is_shown_from_its_committed_sheets() -> void:
	var lab := await _lab()
	await _reach(lab, "lpc32")
	assert_str(String(lab._title.text)).is_equal("lpc32 / hero")
	assert_str(String(lab._detail.text)).contains("imported")
	for i in Dir.ALL.size():
		var view: SpriteView = lab._views[i]
		assert_str(String(view.current_animation())).is_equal(String(Dir.anim_name(&"walk", Dir.ALL[i])))
		# Eight strides, not nine: the standing pose stayed out of the cycle on the way in.
		assert_int(view._sprite.sprite_frames.get_frame_count(view.current_animation())).is_equal(8)
	# Four 64px cells fit the strip at 1x; at the rig styles' 2x they would run off the screen.
	var last: SpriteView = lab._views[Dir.ALL.size() - 1]
	assert_float(last.position.x + 64.0 * last.scale.x).is_less_equal(float(lab.STRIP_WIDTH))
	# And the idle toggle still answers.
	await _press(&"interact", lab._detail)
	assert_str(String(lab._views[0].current_animation())).is_equal("idle_down")

func test_cycling_past_the_imported_style_returns_to_a_rig_one() -> void:
	var lab := await _lab()
	await _reach(lab, "lpc32")
	await _press(&"move_down", lab._title)
	assert_str(String(lab._title.text)).starts_with("nes16 / ")
	assert_str(String(lab._views[0].current_animation())).is_equal("walk_down")

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
	# The first character by NAME, which is what the list is sorted by - with twelve of them,
	# an unsorted list cycled in whatever order the filesystem answered in.
	assert_str(String(lab._title.text)).is_equal("lpc32 / inn_keeper")
	assert_str(String(lab._detail.text)).contains("imported")
	for i in Dir.ALL.size():
		var view: SpriteView = lab._views[i]
		assert_str(String(view.current_animation())).is_equal(String(Dir.anim_name(&"walk", Dir.ALL[i])))
		# Eight strides, not nine: the standing pose stayed out of the cycle on the way in.
		assert_int(view._sprite.sprite_frames.get_frame_count(view.current_animation())).is_equal(8)
	# The strip is world space, so it has the style's own world to fit into: 64px cells at 2x
	# inside 560 world pixels, which is the same 280 DESIGN pixels the rig styles get. That is
	# the whole point of the scale - the lab shows an imported cast at the size it is played at
	# rather than shrinking it to fit a window built for 16px art.
	var last: SpriteView = lab._views[Dir.ALL.size() - 1]
	assert_float(last.scale.x).override_failure_message(
		"the imported cast is being previewed at 1x, which is not how it is played").is_equal(2.0)
	assert_float(last.position.x + 64.0 * last.scale.x).is_less_equal(
		float(lab.STRIP_WIDTH * UiScale.scale_of(lab._style)))
	assert_vector(lab.get_viewport_rect().size).override_failure_message(
		"the lab is showing a 64px cast in a 320x180 window").is_equal(Vector2(640.0, 360.0))
	# And the idle toggle still answers.
	await _press(&"interact", lab._detail)
	assert_str(String(lab._views[0].current_animation())).is_equal("idle_down")

func test_cycling_past_the_imported_style_returns_to_a_rig_one() -> void:
	var lab := await _lab()
	await _reach(lab, "lpc32")
	await _press(&"move_down", lab._title)
	assert_str(String(lab._title.text)).starts_with("nes16 / ")
	assert_str(String(lab._views[0].current_animation())).is_equal("walk_down")


func test_the_lab_draws_its_backdrop_in_the_style_it_is_showing() -> void:
	# It did not until M42: the colour was a literal in sprite_lab.tscn - gb16's own panel - so
	# every style was previewed on a gb16 backdrop, and the file's class comment claiming no
	# colour is typed here was true only because the literal had moved somewhere the lint cannot
	# look. tools/lint_rules.gd walks `.gd` files and nothing else.
	var lab := await _lab()
	var background := lab.get_node_or_null("Background") as ColorRect
	assert_object(background).override_failure_message(
		"the lab has no backdrop, so this measured nothing").is_not_null()
	assert_that(background.color).override_failure_message(
		"the lab draws %s behind a style whose panel is %s"
		% [background.color, lab._style.ui_color("panel")]).is_equal(
		lab._style.ui_color("panel"))

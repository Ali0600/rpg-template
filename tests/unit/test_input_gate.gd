extends GdUnitTestSuite
## The guard that lets a handler act on each event exactly once - and the reason it is not
## a plain identity check.
##
## Both halves of this cost a real bug. Without any guard, a toggle handler fed the same
## event twice returns to where it started and the key looks dead. With an identity-only
## guard, the engine's reuse of event instances between frames makes every genuine repeated
## press look like a duplicate, and the button dies after working exactly once - which is
## strictly worse, because it works long enough to look correct.

func test_the_same_event_is_accepted_once_per_frame() -> void:
	var gate := InputGate.new()
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	assert_bool(gate.accept(event)).is_true()
	assert_bool(gate.accept(event)).override_failure_message(
		"the same event was acted on twice in one frame").is_false()
	assert_bool(gate.accept(event)).is_false()

func test_the_same_event_object_is_accepted_again_on_a_later_frame() -> void:
	# The engine REUSES event instances, so this is not a hypothetical: an identity-only
	# guard swallows every repeated press of the same key forever.
	var gate := InputGate.new()
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	assert_bool(gate.accept(event)).is_true()
	await await_idle_frame()
	assert_bool(gate.accept(event)).override_failure_message(
		"a second press of the same key on a later frame was swallowed").is_true()

func test_a_different_event_in_the_same_frame_is_accepted() -> void:
	var gate := InputGate.new()
	var first := InputEventAction.new()
	first.action = &"interact"
	var second := InputEventAction.new()
	second.action = &"cancel"
	assert_bool(gate.accept(first)).is_true()
	assert_bool(gate.accept(second)).is_true()

func test_alternating_events_are_all_accepted() -> void:
	# Press and release arrive in the same frame and are different objects; neither may be
	# mistaken for a duplicate of the other.
	var gate := InputGate.new()
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	var release := InputEventAction.new()
	release.action = &"interact"
	release.pressed = false
	assert_bool(gate.accept(press)).is_true()
	assert_bool(gate.accept(release)).is_true()
	assert_bool(gate.accept(press)).is_true()


func _stick(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = value
	return e


func test_a_stick_press_is_acted_on_once_until_it_lets_go() -> void:
	# A held stick sends one event per value change, so a cursor that answered each of them would
	# walk to the bottom of its list on a wobble.
	var gate := InputGate.new()
	assert_bool(gate.pressed(_stick(-0.6), &"move_up")).is_true()
	assert_bool(gate.pressed(_stick(-0.8), &"move_up")).override_failure_message(
		"a held stick pressed again on its next motion event").is_false()
	assert_bool(gate.pressed(_stick(-1.0), &"move_up")).is_false()
	assert_bool(gate.pressed(_stick(0.0), &"move_up")).is_false()
	assert_bool(gate.pressed(_stick(-0.7), &"move_up")).is_true()


func test_a_stick_pushed_up_is_not_a_press_down() -> void:
	# is_action() matches a stick by its AXIS alone, so the naive read sends an up-push down the
	# move_down branch - which is the branch every screen here tests first.
	var gate := InputGate.new()
	var up := _stick(-1.0)
	assert_bool(gate.pressed(up, &"move_down")).override_failure_message(
		"a stick pushed up was read as a press down").is_false()
	assert_bool(gate.pressed(up, &"move_up")).is_true()


func test_a_stick_short_of_the_engines_toggle_point_is_not_a_press() -> void:
	# 0.3 is past the map's deadzone, so it walks, and short of the engine's 0.5, so it is not a
	# button. Neither number is written in this project.
	var gate := InputGate.new()
	assert_bool(gate.pressed(_stick(-0.3), &"move_up")).is_false()


func test_a_key_a_pad_button_and_a_harness_action_press_the_frame_they_go_down() -> void:
	var gate := InputGate.new()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	assert_bool(gate.pressed(key, &"move_up")).is_true()
	key.pressed = false
	assert_bool(gate.pressed(key, &"move_up")).is_false()
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_DPAD_UP
	button.pressed = true
	assert_bool(gate.pressed(button, &"move_up")).is_true()
	var action := InputEventAction.new()
	action.action = &"move_up"
	action.pressed = true
	assert_bool(gate.pressed(action, &"move_up")).is_true()
	# The same object pressed again is a press again: the latch is for sticks alone.
	assert_bool(gate.pressed(action, &"move_up")).is_true()


func test_a_motion_event_always_passes_the_top_guard_so_a_release_can_reach_the_latch() -> void:
	assert_bool(InputGate.is_press(_stick(0.0))).is_true()
	var key := InputEventKey.new()
	key.pressed = false
	assert_bool(InputGate.is_press(key)).is_false()
	key.pressed = true
	assert_bool(InputGate.is_press(key)).is_true()
	key.echo = true
	assert_bool(InputGate.is_press(key)).override_failure_message("an echo passed the guard").is_false()

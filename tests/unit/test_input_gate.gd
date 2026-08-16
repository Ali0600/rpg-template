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

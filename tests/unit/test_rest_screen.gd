extends GdUnitTestSuite
## The night, stepped by hand.
##
## The play session proves a night happens and that the player wakes up whole. It cannot see
## the two things this file is for: that the screen actually DARKENS, and that it says it is
## over exactly once. Both are invisible to a script that only reads game state, and the first
## is the entire reason this screen exists rather than the heal simply landing.

const STYLE := "res://data/styles/dusk16.tres"

var _screen: RestScreen

func after_test() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null


func _night(fade: int, hold: int) -> RestScreen:
	_screen = RestScreen.new()
	add_child(_screen)
	_screen.setup(load(STYLE) as SpriteStyle, Vector2i(160, 144), fade, hold, "The night passes.")
	return _screen


func _shade() -> ColorRect:
	for child in _screen.get_children():
		if child is ColorRect:
			return child as ColorRect
	return null


func test_the_night_darkens_and_lifts_again() -> void:
	var night := _night(4, 2)
	assert_float(_shade().color.a).override_failure_message(
		"the screen was already dark before anyone slept").is_equal_approx(0.0, 0.01)
	for i in 4:
		night.step()
	assert_float(_shade().color.a).override_failure_message(
		"four frames of a four-frame fade did not reach full dark").is_equal_approx(1.0, 0.01)
	night.step()
	night.step()
	assert_float(_shade().color.a).override_failure_message(
		"the hold did not stay dark").is_equal_approx(1.0, 0.01)
	for i in 4:
		night.step()
	assert_float(_shade().color.a).override_failure_message(
		"morning never came; the screen is still dark").is_equal_approx(0.0, 0.01)


func test_the_dark_arrives_gradually_rather_than_at_once() -> void:
	# The mid-fade sample is what separates a fade from a cut. Taken at a fixed frame against a
	# fixed fade length, so it is a real number rather than a value derived from the thing it
	# is measuring.
	var night := _night(4, 2)
	night.step()
	assert_float(_shade().color.a).override_failure_message(
		"one frame into a four-frame fade the screen was not a quarter dark").is_equal_approx(0.25, 0.01)
	night.step()
	assert_float(_shade().color.a).is_equal_approx(0.5, 0.01)


func test_a_night_ends_exactly_once() -> void:
	# Stepped well past the end. An "it is over" that repeats every frame is a bug waiting for
	# a listener that cannot take it twice - and the world's is one: it frees this screen.
	var night := _night(2, 1)
	var count := [0]
	night.finished.connect(func() -> void: count[0] += 1)
	for i in 20:
		night.step()
	assert_int(count[0]).override_failure_message(
		"the night announced itself %d times" % count[0]).is_equal(1)
	assert_bool(night.is_done()).is_true()


func test_a_night_of_no_length_still_ends() -> void:
	# A config of zero would divide by nothing; the screen floors it at one frame rather than
	# refusing, because a one-frame night is legible where a crash is not.
	var night := _night(0, 0)
	var count := [0]
	night.finished.connect(func() -> void: count[0] += 1)
	for i in 10:
		night.step()
	assert_int(count[0]).is_equal(1)

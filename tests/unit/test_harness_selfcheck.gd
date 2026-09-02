extends GdUnitTestSuite
## Proves the test runner itself reports pass AND fail correctly.
##
## A suite that has only ever been green cannot distinguish "my code works" from "the
## runner is not running my code". This asserts both directions once, so every later suite
## in this repo inherits a trustworthy instrument.

## A suite that binds a 32px style resizes the ROOT WINDOW, which outlives it exactly as an
## autoload does. One that forgot to put it back would silently re-scale every layout gate that
## ran afterwards, and those failures would read as the layout's fault rather than as a suite
## leaving its furniture out.
func test_the_window_is_the_design_size_when_a_run_begins() -> void:
	assert_vector(get_tree().root.get_viewport().get_visible_rect().size).override_failure_message(
		"a suite left the window at another style's size").is_equal(Vector2(UiScale.DESIGN_SIZE))


func test_runner_reports_success() -> void:
	assert_int(2 + 2).is_equal(4)

func test_runner_evaluates_assertions() -> void:
	# If assertions were being skipped, this negative check would also "pass" silently.
	assert_bool(1 == 2).is_false()
	assert_str("rpg-template").contains("template")

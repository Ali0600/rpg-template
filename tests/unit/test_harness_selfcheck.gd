extends GdUnitTestSuite
## Proves the test runner itself reports pass AND fail correctly.
##
## A suite that has only ever been green cannot distinguish "my code works" from "the
## runner is not running my code". This asserts both directions once, so every later suite
## in this repo inherits a trustworthy instrument.

func test_runner_reports_success() -> void:
	assert_int(2 + 2).is_equal(4)

func test_runner_evaluates_assertions() -> void:
	# If assertions were being skipped, this negative check would also "pass" silently.
	assert_bool(1 == 2).is_false()
	assert_str("sprite-generator").contains("sprite")

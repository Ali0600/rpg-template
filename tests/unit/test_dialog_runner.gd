extends GdUnitTestSuite
## Conversations, walked as data rather than clicked through.
##
## Keeping the rules out of the view is what makes this possible: branching, choices, flags
## and endings are all decided here, so they can be checked by walking a script and reading
## the result instead of by pressing a button and watching a box.

const DIALOG_DIR := "res://data/dialog/"

func _sample(known_flags: Dictionary = {}) -> DialogRunner:
	return DialogRunner.from_dict({
		"id": "sample",
		"start": "greet",
		"nodes": {
			"greet": {"speaker": "A", "text": "hello", "next": "ask"},
			"ask": {"speaker": "A", "text": "well?", "choices": [
				{"text": "yes", "next": "yes", "set_flag": "agreed"},
				{"text": "no", "next": "no"},
				{"text": "secret", "next": "yes", "requires_flag": "knows_secret"},
			]},
			"yes": {"speaker": "A", "text": "good"},
			"no": {"speaker": "A", "text": "shame"},
		},
	}, known_flags)

func test_every_shipped_dialog_is_valid() -> void:
	var dir := DirAccess.open(DIALOG_DIR)
	assert_object(dir).is_not_null()
	var count := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension() == "json":
			count += 1
			var runner := DialogRunner.load_from(DIALOG_DIR + name)
			assert_array(runner.problems()).override_failure_message(
				"%s: %s" % [name, runner.problems()]).is_empty()
		name = dir.get_next()
	dir.list_dir_end()
	# A loop over an empty directory validates nothing and reports success.
	assert_int(count).is_greater(0)

func test_a_conversation_walks_line_by_line() -> void:
	var runner := _sample()
	assert_bool(runner.begin()).is_true()
	assert_str(runner.line().text).is_equal("hello")
	assert_bool(runner.advance()).is_true()
	assert_str(runner.line().text).is_equal("well?")

func test_the_end_of_a_conversation_is_reported_not_guessed() -> void:
	# The caller hands control back on this signal, so it has to be explicit - checking
	# whether the next line happens to be empty would end a conversation on a blank line.
	var runner := _sample()
	runner.begin()
	runner.advance()
	runner.choose(1)
	assert_str(runner.line().text).is_equal("shame")
	assert_bool(runner.advance()).is_false()
	assert_bool(runner.is_finished()).is_true()
	assert_object(runner.line()).is_null()

func test_a_line_with_choices_does_not_advance_on_its_own() -> void:
	# Advancing past a choice would pick for the player - exactly what a held confirm button
	# would do otherwise.
	var runner := _sample()
	runner.begin()
	runner.advance()
	var before := runner.current_id()
	assert_bool(runner.advance()).is_true()
	assert_str(runner.current_id()).is_equal(before)

func test_choosing_follows_the_branch() -> void:
	var runner := _sample()
	runner.begin()
	runner.advance()
	assert_bool(runner.choose(0)).is_true()
	assert_str(runner.line().text).is_equal("good")

func test_an_out_of_range_choice_is_refused_not_clamped() -> void:
	# Clamping turns a UI bug into a plausible wrong answer that nobody notices.
	var runner := _sample()
	runner.begin()
	runner.advance()
	var before := runner.current_id()
	assert_bool(runner.choose(9)).is_false()
	assert_bool(runner.choose(-1)).is_false()
	assert_str(runner.current_id()).is_equal(before)
	assert_bool(runner.is_finished()).is_false()

func test_a_choice_the_player_cannot_take_is_hidden_not_offered() -> void:
	# The menu never shows something it would then reject.
	assert_int(_line_choices(_sample()).size()).is_equal(2)
	assert_int(_line_choices(_sample({"knows_secret": true})).size()).is_equal(3)

func _line_choices(runner: DialogRunner) -> Array[String]:
	runner.begin()
	runner.advance()
	return runner.line().choices

func test_a_hidden_choice_shifts_the_indices_it_hides_behind() -> void:
	# The index the player picks refers to what they can SEE. If choose() counted hidden
	# entries too, the second visible option would run the third branch - and it would look
	# like a writing mistake rather than an off-by-one.
	var runner := _sample()
	runner.begin()
	runner.advance()
	assert_bool(runner.choose(1)).is_true()
	assert_str(runner.line().text).is_equal("shame")

func test_flags_are_collected_and_never_written() -> void:
	# A pure runner cannot reach the game state, and that is the right shape: the caller
	# applies them once the line has actually been shown, so an abandoned conversation
	# leaves no promises behind.
	var runner := _sample()
	runner.begin()
	runner.advance()
	assert_array(runner.flags_to_set()).is_empty()
	runner.choose(0)
	assert_array(runner.flags_to_set()).contains([&"agreed"])

func test_a_conversation_abandoned_before_the_flag_earns_nothing() -> void:
	var runner := _sample()
	runner.begin()
	runner.advance()
	runner.choose(1)
	assert_array(runner.flags_to_set()).is_empty()

func test_a_dialog_that_starts_nowhere_is_refused() -> void:
	var runner := DialogRunner.from_dict({"id": "broken", "start": "missing", "nodes": {
		"greet": {"text": "hello"},
	}})
	assert_bool(runner.begin()).is_false()
	assert_str(str(runner.problems())).contains("which does not exist")

func test_a_next_pointing_nowhere_is_reported() -> void:
	# Left unchecked, the conversation just ends early and reads as if it was written that way.
	var runner := DialogRunner.from_dict({"id": "broken", "start": "a", "nodes": {
		"a": {"text": "hello", "next": "b"},
	}})
	# Asserted on the entry rather than on str(array): an array's string form escapes the
	# quotes inside it, so a `contains` against the readable message silently never matches.
	assert_int(runner.problems().size()).is_equal(1)
	assert_str(runner.problems()[0]).contains("continues to")
	assert_str(runner.problems()[0]).contains("does not exist")

func test_an_unreachable_node_is_reported() -> void:
	# It was written, it is in the file, and no player will ever see it.
	var runner := DialogRunner.from_dict({"id": "orphan", "start": "a", "nodes": {
		"a": {"text": "hello"},
		"lost": {"text": "nobody gets here"},
	}})
	assert_str(str(runner.problems())).contains("unreachable")

func test_a_missing_dialog_file_is_an_error() -> void:
	var runner := DialogRunner.load_from("res://data/dialog/nope.json")
	assert_bool(runner.ok).is_false()
	assert_str(str(runner.problems())).contains("did not load")

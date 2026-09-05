extends GdUnitTestSuite
## The options page's rules: two rows, a wrapping cursor, and what a press on each one means.
##
## Pure - no tree, no font, no singleton. What this cannot answer is whether a row FITS, which is
## test_options_layout.gd's job with the real font; the two together are the whole gate.

func _menu() -> OptionsMenu:
	return OptionsMenu.of("Normal", "Parchment")


func test_the_cursor_opens_on_the_first_row() -> void:
	assert_int(_menu().index()).is_equal(OptionsMenu.Row.SOUND)


func test_both_rows_say_what_the_setting_currently_is() -> void:
	# A row reading only "Sound" is a row a player has to press to learn anything from. Both
	# carry their value, which is also what makes the page readable without a cursor on it.
	var menu := _menu()
	assert_str(menu.label(OptionsMenu.Row.SOUND)).is_equal("Sound: Normal")
	assert_str(menu.label(OptionsMenu.Row.WINDOW)).is_equal("Window: Parchment")


func test_a_row_told_nothing_still_draws_its_name() -> void:
	# A blank label renders as an empty line, which reads as a page that failed to draw rather
	# than as a setting with no value.
	var menu := OptionsMenu.of("", "")
	for at in menu.size():
		assert_str(menu.label(at)).override_failure_message(
			"row %d drew nothing at all" % at).is_not_empty()


func test_new_words_arrive_without_moving_the_cursor() -> void:
	# The whole reason refresh exists rather than rebuilding: confirming changes a value and
	# leaves the page up, and a player comparing window colours presses that row repeatedly.
	# Rebuilding would send them back to the top row every time.
	var menu := _menu()
	menu.move(1)
	menu.refresh("Loud", "Mint")
	assert_int(menu.index()).is_equal(OptionsMenu.Row.WINDOW)
	assert_str(menu.label(OptionsMenu.Row.WINDOW)).is_equal("Window: Mint")


func test_the_cursor_wraps_both_ways() -> void:
	var menu := _menu()
	assert_bool(menu.move(-1)).is_true()
	assert_int(menu.index()).override_failure_message(
		"moving up from the first row did not wrap to the last").is_equal(menu.size() - 1)
	assert_bool(menu.move(1)).is_true()
	assert_int(menu.index()).is_equal(0)


func test_a_move_of_nothing_reports_that_it_did_nothing() -> void:
	# So the view can stay silent. A noise for a press that changed nothing is the same lie as a
	# cursor on a page with no verb.
	assert_bool(_menu().move(0)).is_false()


func test_every_row_answers_a_kind_of_its_own() -> void:
	# Walked rather than counted. A test asserting "there are two rows" goes red the day a third
	# legitimately arrives while saying nothing about the rule, which is that each row means
	# something different - two rows answering the same Kind is one of them doing nothing.
	var menu := _menu()
	var seen: Array[int] = []
	for at in menu.size():
		while menu.index() != at:
			menu.move(1)
		var kind := menu.confirm().kind
		assert_int(kind).override_failure_message(
			"row %d answers NONE, so pressing it does nothing at all" % at
			).is_not_equal(OptionsMenu.Kind.NONE)
		assert_bool(seen.has(kind)).override_failure_message(
			"two rows both answer kind %d, so one of them is unreachable" % kind).is_false()
		seen.append(kind)
	assert_int(seen.size()).is_equal(menu.size())


func test_cancel_asks_to_leave_from_any_row() -> void:
	# From any row, because cancel is not about what the cursor is on - a page that only closed
	# from its first row would trap a player who had moved down.
	var menu := _menu()
	for at in menu.size():
		while menu.index() != at:
			menu.move(1)
		assert_int(menu.cancel().kind).override_failure_message(
			"cancel on row %d did not ask to leave" % at).is_equal(OptionsMenu.Kind.LEAVE)


func test_the_page_never_answers_for_a_row_it_does_not_have() -> void:
	assert_str(_menu().label(OptionsMenu.Row.size())).is_empty()
	assert_str(_menu().label(-1)).is_empty()

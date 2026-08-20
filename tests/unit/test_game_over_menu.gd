extends GdUnitTestSuite
## The end-of-run menu's rules, with no screen in the way.
##
## Almost a PauseMenu, and the differences are the whole reason it is its own class: cancel on
## the top page resumes NOTHING, and Continue with an empty slot list is refused rather than
## opening a page of rows that all do nothing. Both are tested against controls that succeed.

func _slots(filled: Array[int], count := 3) -> Array[SaveData]:
	var out: Array[SaveData] = []
	for i in count:
		if not filled.has(i):
			out.append(null)
			continue
		var data := SaveData.new()
		data.game = &"quest"
		data.map = &"quest_village"
		data.play_seconds = 754.0
		out.append(data)
	return out

func test_a_fresh_menu_opens_on_continue() -> void:
	var menu := GameOverMenu.of(_slots([0]))
	assert_int(menu.page()).is_equal(GameOverMenu.Page.TOP)
	assert_int(menu.index()).is_equal(GameOverMenu.Row.CONTINUE)
	assert_int(menu.size()).is_equal(2)

func test_the_cursor_wraps_both_ways() -> void:
	var menu := GameOverMenu.of(_slots([0]))
	assert_bool(menu.move(-1)).is_true()
	assert_int(menu.index()).is_equal(GameOverMenu.Row.NEW_GAME)
	assert_bool(menu.move(1)).is_true()
	assert_int(menu.index()).is_equal(GameOverMenu.Row.CONTINUE)

func test_opening_the_slot_list_asks_for_nothing() -> void:
	# Changing what is on screen is not a decision the world has to act on - the PauseMenu rule.
	var menu := GameOverMenu.of(_slots([1]))
	assert_int(menu.confirm().kind).is_equal(GameOverMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(GameOverMenu.Page.LOAD)
	assert_int(menu.index()).is_equal(0)

func test_continuing_with_nothing_saved_is_refused() -> void:
	# Refused here rather than opening a list of three empty rows, which would invite three
	# more presses that also do nothing.
	var menu := GameOverMenu.of(_slots([]))
	assert_int(menu.confirm().kind).is_equal(GameOverMenu.Kind.NONE)
	assert_int(menu.page()).override_failure_message(
		"a player with no saves was shown a list of nothing").is_equal(GameOverMenu.Page.TOP)

func test_continuing_with_a_save_opens_the_list() -> void:
	# The control. A menu that refused every Continue would pass the test above.
	var menu := GameOverMenu.of(_slots([2]))
	menu.confirm()
	assert_int(menu.page()).is_equal(GameOverMenu.Page.LOAD)

func test_loading_an_empty_slot_is_refused() -> void:
	var menu := GameOverMenu.of(_slots([2]))
	menu.confirm()
	assert_int(menu.confirm().kind).override_failure_message(
		"an empty slot was loaded, or nudged to a neighbouring one").is_equal(GameOverMenu.Kind.NONE)

func test_loading_a_filled_slot_is_taken() -> void:
	# The control for the refusal above, and the one that proves the slot is reported rather
	# than assumed: the save is in slot 2, and a menu answering 0 would load the wrong file.
	var menu := GameOverMenu.of(_slots([2]))
	menu.confirm()
	menu.move(GameOverMenu.Row.NEW_GAME)
	menu.move(1)
	var pick := menu.confirm()
	assert_int(pick.kind).is_equal(GameOverMenu.Kind.LOAD)
	assert_int(pick.slot).is_equal(2)

func test_starting_again_needs_no_saves_at_all() -> void:
	var menu := GameOverMenu.of(_slots([]))
	menu.move(GameOverMenu.Row.NEW_GAME)
	assert_int(menu.confirm().kind).is_equal(GameOverMenu.Kind.NEW_GAME)

func test_backing_out_of_the_slot_list_returns_to_the_top() -> void:
	var menu := GameOverMenu.of(_slots([0]))
	menu.confirm()
	assert_int(menu.cancel().kind).is_equal(GameOverMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(GameOverMenu.Page.TOP)
	assert_int(menu.index()).is_equal(GameOverMenu.Row.CONTINUE)

func test_backing_out_of_the_top_page_does_nothing() -> void:
	# The one real difference from a pause menu. Backing out of a pause resumes; there is
	# nothing here to resume into, and answering RESUME would drop a dead player into the world.
	var menu := GameOverMenu.of(_slots([0]))
	assert_int(menu.cancel().kind).is_equal(GameOverMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(GameOverMenu.Page.TOP)

func test_continue_says_when_there_is_nothing_to_continue_from() -> void:
	# "Continue" over three empty slots is a promise the menu cannot keep.
	assert_str(GameOverMenu.of(_slots([])).top_label(GameOverMenu.Row.CONTINUE)).contains("nothing")
	assert_str(GameOverMenu.of(_slots([1])).top_label(GameOverMenu.Row.CONTINUE)).is_equal("Continue")

func test_refreshing_keeps_the_cursor_where_it_was() -> void:
	var menu := GameOverMenu.of(_slots([0, 1, 2]))
	menu.confirm()
	menu.move(1)
	menu.refresh(_slots([0, 2]))
	assert_int(menu.index()).is_equal(1)

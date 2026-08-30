extends GdUnitTestSuite
## The title's rules, with no screen in the way.
##
## Almost a game-over menu - they share a base class for exactly that reason - and the two
## places they differ are the two things worth testing here: the words, and where the cursor
## opens.

## Slots by index: the ones named in `filled` hold a save, the ones in `damaged` hold a file
## that cannot be read, and the rest are empty. Three states because the menus now draw three -
## a damaged slot used to be indistinguishable from an empty one here and on screen.
func _slots(filled: Array[int], count := 3, damaged: Array[int] = []) -> Array[SlotSummary]:
	var out: Array[SlotSummary] = []
	for i in count:
		if damaged.has(i):
			out.append(SlotSummary.broken())
			continue
		if not filled.has(i):
			out.append(SlotSummary.empty())
			continue
		var data := SaveData.new()
		data.game = &"quest"
		data.map = &"quest_village"
		data.play_seconds = 754.0
		out.append(SlotSummary.of(data))
	return out


func test_a_title_with_nothing_saved_opens_on_new_game() -> void:
	# The whole argument for the pressable-row rule: a player's FIRST press of the game should
	# not be one that bounces off a refusal explained by a label they have not read yet.
	var menu := TitleMenu.of(_slots([]))
	assert_int(menu.index()).is_equal(TitleMenu.Row.NEW_GAME)


func test_a_title_with_a_save_opens_on_continue() -> void:
	var menu := TitleMenu.of(_slots([1]))
	assert_int(menu.index()).override_failure_message(
		"a player with a save was not offered it first").is_equal(TitleMenu.Row.CONTINUE)


func test_continue_is_still_the_first_row_either_way() -> void:
	# The ORDER is the genre's and does not move with the cursor. Two different facts, and a
	# menu that reordered itself by availability would move a row out from under a player who
	# had learnt where it was.
	assert_str(TitleMenu.of(_slots([])).top_label(TitleMenu.Row.CONTINUE)).contains("Continue")
	assert_str(TitleMenu.of(_slots([1])).top_label(TitleMenu.Row.CONTINUE)).contains("Continue")


func test_continue_says_when_there_is_nothing_to_continue_from() -> void:
	assert_str(TitleMenu.of(_slots([])).top_label(TitleMenu.Row.CONTINUE)) \
		.is_equal("Continue (nothing saved)")
	assert_str(TitleMenu.of(_slots([0])).top_label(TitleMenu.Row.CONTINUE)).is_equal("Continue")


func test_the_title_says_new_game_where_a_game_over_says_start_again() -> void:
	# The one thing that differs between the two screens, and the reason the split is a base
	# class plus two words rather than two copies of every rule.
	assert_str(TitleMenu.of(_slots([])).top_label(TitleMenu.Row.NEW_GAME)).is_equal("New game")
	assert_str(GameOverMenu.of(_slots([])).top_label(TitleMenu.Row.NEW_GAME)).is_equal("Start again")


func test_confirming_new_game_asks_to_start_one() -> void:
	var menu := TitleMenu.of(_slots([]))
	menu.move(TitleMenu.Row.NEW_GAME - menu.index())
	assert_int(menu.confirm().kind).is_equal(TitleMenu.Kind.NEW_GAME)


func test_continue_with_nothing_saved_is_refused_rather_than_opening_an_empty_list() -> void:
	var menu := TitleMenu.of(_slots([]))
	menu.move(TitleMenu.Row.CONTINUE - menu.index())
	assert_int(menu.confirm().kind).is_equal(TitleMenu.Kind.NONE)
	assert_int(menu.page()).override_failure_message(
		"a page of rows that all do nothing was opened").is_equal(TitleMenu.Page.TOP)


func test_continue_with_a_save_opens_the_slot_list() -> void:
	var menu := TitleMenu.of(_slots([1]))
	menu.move(TitleMenu.Row.CONTINUE - menu.index())
	assert_int(menu.confirm().kind).is_equal(TitleMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(TitleMenu.Page.LOAD)
	assert_int(menu.size()).is_equal(3)


func test_loading_a_filled_slot_is_taken_and_an_empty_one_is_refused() -> void:
	var menu := TitleMenu.of(_slots([1]))
	menu.move(TitleMenu.Row.CONTINUE - menu.index())
	menu.confirm()
	assert_int(menu.confirm().kind).override_failure_message(
		"slot 0 is empty and loading it was accepted").is_equal(TitleMenu.Kind.NONE)
	menu.move(1)
	var pick := menu.confirm()
	assert_int(pick.kind).is_equal(TitleMenu.Kind.LOAD)
	assert_int(pick.slot).is_equal(1)


func test_cancel_on_the_slot_list_goes_back_rather_than_out() -> void:
	var menu := TitleMenu.of(_slots([1]))
	menu.move(TitleMenu.Row.CONTINUE - menu.index())
	menu.confirm()
	assert_int(menu.cancel().kind).is_equal(TitleMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(TitleMenu.Page.TOP)


func test_cancel_on_the_title_does_nothing_at_all() -> void:
	# There is nothing behind a title to back out into. A quit belongs to a game that has one.
	var menu := TitleMenu.of(_slots([]))
	assert_int(menu.cancel().kind).is_equal(TitleMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(TitleMenu.Page.TOP)


func test_the_title_has_no_third_way_on() -> void:
	# The game over has a Title row; a title cannot offer a route to itself. Asserted rather
	# than assumed, because the row count is what the view builds its labels from.
	assert_int(TitleMenu.of(_slots([])).row_count()).is_equal(2)
	assert_int(GameOverMenu.of(_slots([])).row_count()).is_equal(3)

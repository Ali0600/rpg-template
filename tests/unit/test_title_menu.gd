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


func test_the_title_offers_no_route_to_itself() -> void:
	# The game over has a Title row and the title cannot: there is nothing to go back to.
	#
	# Asserted over EVERY row rather than through the row count, which is what this test used to
	# do. A count is a proxy - it was 2, M43 made it 3 by adding Credits, and the count changing
	# said nothing about whether the rule had broken. The rule is about what a row ANSWERS, so
	# that is what is read, and the next row to arrive is covered without an edit.
	# top_pick answers null for the Continue row - "that one is not mine" - so a null is a row
	# that is definitionally not a route to the title, and skipping it is reading the contract
	# rather than working around it.
	var title := TitleMenu.of(_slots([]))
	for at in title.row_count():
		var pick := title.top_pick(at)
		if pick == null:
			continue
		assert_int(pick.kind).override_failure_message(
			"title row %d answers TITLE, which is a route to the screen it is on" % at
			).is_not_equal(TitleMenu.Kind.TITLE)
	var over := GameOverMenu.of(_slots([]))
	var routes := 0
	for at in over.row_count():
		var pick := over.top_pick(at)
		if pick != null and pick.kind == GameOverMenu.Kind.TITLE:
			routes += 1
	assert_int(routes).override_failure_message(
		"the game over offers no way back to the title").is_equal(1)


func test_every_way_on_is_reachable_from_a_row_of_its_own() -> void:
	# MEMBERSHIP, compared whole against a list written here, which is the only place the code
	# under test cannot reach. A per-row property check passes happily while a whole row is
	# unreachable: give Options the same index as Credits and every row still answers something,
	# every row still has a word on it, and the title quietly stops offering a page. That mutant
	# survived a full sweep until this test existed.
	#
	# It fails in BOTH directions - a way on that stopped being offered, and one nobody declared.
	var offered: Array[int] = []
	var title := TitleMenu.of(_slots([0]))
	for at in title.row_count():
		var pick := title.top_pick(at)
		if pick == null:
			# The Continue row, which SlotMenu answers for. Not a way on of the subclass's own.
			continue
		assert_bool(offered.has(pick.kind)).override_failure_message(
			"two rows both answer kind %d, so one of them cannot be reached" % pick.kind).is_false()
		offered.append(pick.kind)
	offered.sort()
	# LOAD is deliberately not here: it is what the Continue row's page answers, not what a top
	# row answers, and top_pick returns null for that row so SlotMenu keeps the rule in one place.
	var declared: Array[int] = [TitleMenu.Kind.NEW_GAME, TitleMenu.Kind.CREDITS,
		TitleMenu.Kind.OPTIONS]
	declared.sort()
	assert_array(offered).override_failure_message(
		"the title offers %s where it should offer %s" % [offered, declared]).is_equal(declared)


func test_each_row_is_worded_as_the_thing_it_actually_does() -> void:
	# The pair to the test above and the half it cannot see: a row can be reachable and still be
	# labelled as its neighbour. Asserted as a PAIRING rather than as two lists, because the two
	# are answered by different functions - top_label and top_pick - and nothing else requires
	# them to agree about which row is the third one.
	var title := TitleMenu.of(_slots([0]))
	var words := {
		TitleMenu.Kind.CREDITS: "Credits",
		TitleMenu.Kind.OPTIONS: "Options",
		TitleMenu.Kind.NEW_GAME: "New game",
	}
	for at in title.row_count():
		var pick := title.top_pick(at)
		if pick == null or not words.has(pick.kind):
			continue
		assert_str(title.top_label(at)).override_failure_message(
			"row %d does %d and says '%s'" % [at, pick.kind, title.top_label(at)]
			).is_equal(str(words[pick.kind]))


func test_each_screen_builds_labels_for_every_row_it_has() -> void:
	# The count is still worth pinning, for the reason the old test named: the view sizes its
	# label pool from it, so a row past the pool is a row drawn nowhere. Pinned as "every row is
	# worded" rather than as a literal, which is the same fact and does not go stale.
	for menu: SlotMenu in [TitleMenu.of(_slots([])), GameOverMenu.of(_slots([]))]:
		assert_int(menu.row_count()).is_greater(1)
		for at in menu.row_count():
			assert_str(menu.top_label(at)).override_failure_message(
				"row %d of %s has no words on it" % [at, menu]).is_not_empty()

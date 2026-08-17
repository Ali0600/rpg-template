extends GdUnitTestSuite
## The cursor rules for choosing a game, read as results rather than driven through a screen.
##
## Two of them are load-bearing in a way that is invisible at the line where they are written.
## A relative move WRAPS, because a list this short is navigated by tapping one key and a
## cursor that stops dead reads as a dropped input. An absolute select REFUSES, because the
## plausible-looking wrong answer here is booting the wrong game - which is the exact failure
## GameSelect was built to refuse, and clamping would hand it back.

func _game(id: StringName, title: String) -> GameManifest:
	var manifest := GameManifest.new()
	manifest.id = id
	manifest.title = title
	return manifest

func _three() -> Array[GameManifest]:
	var out: Array[GameManifest] = []
	out.append(_game(&"alpha", "Alpha"))
	out.append(_game(&"beta", "Beta"))
	out.append(_game(&"gamma", "Gamma"))
	return out

func test_a_fresh_menu_points_at_the_first_entry() -> void:
	var menu := GameMenu.of(_three())
	assert_int(menu.index()).is_equal(0)
	assert_int(menu.size()).is_equal(3)

func test_opening_over_a_running_game_points_at_it() -> void:
	# Both what a player expects and where cancelling would land anyway, so it falls out of
	# the same field rather than needing a second one.
	var items := _three()
	var menu := GameMenu.of(items, items[2])
	assert_int(menu.index()).is_equal(2)

func test_opening_over_a_game_that_is_not_listed_leaves_the_cursor_alone() -> void:
	# index_of misses with -1, and select refuses it. Without the refusal the cursor would
	# land out of range and selected() would start returning null.
	var menu := GameMenu.of(_three(), _game(&"elsewhere", "Elsewhere"))
	assert_int(menu.index()).is_equal(0)
	assert_object(menu.selected()).is_not_null()

func test_the_cursor_wraps_both_ways() -> void:
	var menu := GameMenu.of(_three())
	assert_bool(menu.move(-1)).is_true()
	assert_int(menu.index()).is_equal(2)
	assert_bool(menu.move(1)).is_true()
	assert_int(menu.index()).is_equal(0)

func test_moving_past_the_end_comes_back_round() -> void:
	var menu := GameMenu.of(_three())
	menu.move(1)
	menu.move(1)
	menu.move(1)
	assert_int(menu.index()).is_equal(0)

func test_a_single_entry_does_not_move() -> void:
	var one: Array[GameManifest] = []
	one.append(_game(&"only", "Only"))
	var menu := GameMenu.of(one)
	assert_bool(menu.move(1)).is_false()
	assert_int(menu.index()).is_equal(0)

func test_an_out_of_range_selection_is_refused_rather_than_clamped() -> void:
	var menu := GameMenu.of(_three())
	assert_bool(menu.select(3)).is_false()
	assert_bool(menu.select(-1)).is_false()
	assert_int(menu.index()).is_equal(0)

func test_a_selection_in_range_is_taken() -> void:
	# The control: without it, a select() that refused everything would pass the test above.
	var menu := GameMenu.of(_three())
	assert_bool(menu.select(2)).is_true()
	assert_int(menu.index()).is_equal(2)

func test_confirm_returns_the_game_under_the_cursor() -> void:
	var menu := GameMenu.of(_three())
	menu.move(1)
	assert_str(String(menu.confirm().id)).is_equal("beta")

func test_cancelling_at_boot_returns_nothing_to_go_back_to() -> void:
	# The whole boot case, expressed as data rather than as a mode flag: nothing was running,
	# so there is nothing to return to, so cancel does nothing.
	assert_object(GameMenu.of(_three()).cancel()).is_null()

func test_cancelling_mid_play_returns_the_game_that_was_running() -> void:
	var items := _three()
	var menu := GameMenu.of(items, items[1])
	menu.move(1)
	assert_str(String(menu.cancel().id)).is_equal("beta")

func test_the_item_list_handed_out_is_a_copy() -> void:
	# A view that could clear the menu's own list by tidying up its own would be a bug found
	# once, in the dark.
	var menu := GameMenu.of(_three())
	var taken := menu.items()
	taken.clear()
	assert_int(menu.size()).is_equal(3)

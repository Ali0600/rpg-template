extends GdUnitTestSuite
## The pause menu's rules, with no screen in the way.
##
## The two that matter are refusals: loading an empty slot does nothing, and backing out of
## the top page resumes rather than falling through to the world by some other route. Both are
## the kind of rule that a scene test would confirm by accident.

## Slots with saves at the given indices. 754 seconds so a label reads 12:34 - a time nobody
## could produce by accident.
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

func test_a_fresh_menu_opens_on_resume() -> void:
	var menu := PauseMenu.of(_slots([]))
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)
	assert_int(menu.index()).is_equal(PauseMenu.Row.RESUME)
	assert_int(menu.size()).is_equal(4)

func test_the_top_cursor_wraps_both_ways() -> void:
	var menu := PauseMenu.of(_slots([]))
	assert_bool(menu.move(-1)).is_true()
	assert_int(menu.index()).is_equal(PauseMenu.Row.LOAD)
	assert_bool(menu.move(1)).is_true()
	assert_int(menu.index()).is_equal(PauseMenu.Row.RESUME)

func test_confirming_resume_resumes() -> void:
	var menu := PauseMenu.of(_slots([]))
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.RESUME)
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)

func test_opening_the_save_page_asks_for_nothing() -> void:
	# Changing what is on screen is not a decision the world has to act on. If opening a page
	# answered SAVE, arriving at the list would write slot 0.
	var menu := PauseMenu.of(_slots([]))
	# Named rather than counted: a row inserted above Save must move this test, not silently
	# retarget it at whatever now sits one step down.
	menu.move(PauseMenu.Row.SAVE)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.SAVE)
	assert_int(menu.index()).is_equal(0)
	assert_int(menu.size()).is_equal(3)

func test_opening_the_load_page_asks_for_nothing() -> void:
	var menu := PauseMenu.of(_slots([0]))
	menu.move(PauseMenu.Row.LOAD)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.LOAD)

func test_an_empty_slot_can_still_be_saved_into() -> void:
	# Save and Load are not symmetric: an empty slot is exactly where a save goes.
	var menu := PauseMenu.of(_slots([]))
	menu.move(PauseMenu.Row.SAVE)
	menu.confirm()
	menu.move(1)
	var pick := menu.confirm()
	assert_int(pick.kind).is_equal(PauseMenu.Kind.SAVE)
	assert_int(pick.slot).is_equal(1)

func test_loading_an_empty_slot_is_refused() -> void:
	# Refused, not nudged to the nearest filled one - the clamp would load a game the player
	# did not ask for, which is the failure that looks like a bug in the game itself.
	var menu := PauseMenu.of(_slots([1]))
	menu.move(PauseMenu.Row.LOAD)
	menu.confirm()
	var pick := menu.confirm()
	assert_int(pick.kind).override_failure_message("an empty slot offered to load").is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.LOAD)

func test_loading_a_filled_slot_is_taken() -> void:
	# The control. A menu that refused every load would pass the test above.
	var menu := PauseMenu.of(_slots([1]))
	menu.move(PauseMenu.Row.LOAD)
	menu.confirm()
	menu.move(1)
	var pick := menu.confirm()
	assert_int(pick.kind).is_equal(PauseMenu.Kind.LOAD)
	assert_int(pick.slot).is_equal(1)

func test_cancel_on_the_top_page_resumes() -> void:
	assert_int(PauseMenu.of(_slots([])).cancel().kind).is_equal(PauseMenu.Kind.RESUME)

func test_cancel_on_a_slot_page_goes_back_rather_than_out() -> void:
	# Escape twice leaves the menu; escape once leaves the page. A cancel that resumed from
	# the slot list would make the pause menu impossible to browse.
	var menu := PauseMenu.of(_slots([]))
	menu.move(PauseMenu.Row.LOAD)
	menu.confirm()
	var pick := menu.cancel()
	assert_int(pick.kind).override_failure_message("backing out of the slot list resumed the game").is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)
	assert_int(menu.index()).override_failure_message(
		"the cursor did not return to the row that opened the page").is_equal(PauseMenu.Row.LOAD)

func test_the_slot_cursor_wraps_over_the_slot_count() -> void:
	var menu := PauseMenu.of(_slots([], 4))
	menu.move(PauseMenu.Row.SAVE)
	menu.confirm()
	assert_bool(menu.move(-1)).is_true()
	assert_int(menu.index()).is_equal(3)

func test_refreshing_keeps_the_cursor_where_it_was() -> void:
	# Called after a save, so the row the player is looking at shows what they just wrote.
	var menu := PauseMenu.of(_slots([]))
	menu.move(PauseMenu.Row.SAVE)
	menu.confirm()
	menu.move(2)
	menu.refresh(_slots([2]))
	assert_int(menu.page()).is_equal(PauseMenu.Page.SAVE)
	assert_int(menu.index()).is_equal(2)
	assert_object(menu.slot(2)).is_not_null()

func test_a_game_with_no_slots_cannot_open_the_slot_pages() -> void:
	# A page with no rows is a screen that answers nothing and has to be escaped from.
	var menu := PauseMenu.of(_slots([], 0))
	menu.move(PauseMenu.Row.SAVE)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)

func test_a_clock_reads_as_minutes_until_it_reads_as_hours() -> void:
	assert_str(PauseMenu.clock(0.0)).is_equal("00:00")
	assert_str(PauseMenu.clock(754.0)).is_equal("12:34")
	assert_str(PauseMenu.clock(3661.0)).is_equal("1:01:01")

func test_a_slot_label_names_the_map_and_the_time_or_says_empty() -> void:
	var filled := _slots([0])
	assert_str(PauseMenu.slot_label(0, null)).is_equal("Slot 1: empty")
	assert_str(PauseMenu.slot_label(1, filled[0])).is_equal("Slot 2: quest_village  12:34")


func _bag(entries: Array) -> Array:
	var out: Array = []
	for entry: Array in entries:
		out.append(PauseMenu.ItemRow.of(entry[0], entry[1], entry[2], entry[3] if entry.size() > 3 else ""))
	return out


func test_opening_the_item_list_asks_for_nothing() -> void:
	var menu := PauseMenu.of(_slots([]), _bag([[&"gate_key", "Gate key", 1]]))
	menu.move(PauseMenu.Row.ITEMS)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.ITEMS)
	assert_int(menu.index()).is_equal(0)
	assert_int(menu.size()).is_equal(1)


func test_an_empty_bag_still_has_a_row_to_stand_on() -> void:
	# A page with no rows is one the cursor cannot occupy and, with nothing painted, one the
	# player cannot tell from a menu that failed to draw.
	var menu := PauseMenu.of(_slots([]), [])
	menu.move(PauseMenu.Row.ITEMS)
	menu.confirm()
	assert_int(menu.page()).is_equal(PauseMenu.Page.ITEMS)
	assert_int(menu.size()).is_equal(1)
	assert_object(menu.item(0)).is_null()
	assert_str(PauseMenu.item_label(menu.item(0))).is_equal("(nothing carried)")


func test_the_item_page_opens_even_when_a_game_has_no_save_slots() -> void:
	# The slot pages refuse to open with nothing in them; an empty bag is a fact worth showing.
	var menu := PauseMenu.of([], _bag([[&"gate_key", "Gate key", 1]]))
	menu.move(PauseMenu.Row.ITEMS)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.ITEMS)


func test_confirming_an_item_does_nothing_yet() -> void:
	# There is no "use" verb. Answering anything here would be the world acting on a press
	# that has no meaning.
	var menu := PauseMenu.of(_slots([]), _bag([[&"gate_key", "Gate key", 1]]))
	menu.move(PauseMenu.Row.ITEMS)
	menu.confirm()
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.ITEMS)


func test_cancel_on_the_item_list_returns_to_the_items_row() -> void:
	# Not to the top of the menu: the player is where they left off, which is the same rule
	# the slot pages follow.
	var menu := PauseMenu.of(_slots([]), _bag([[&"gate_key", "Gate key", 1]]))
	menu.move(PauseMenu.Row.ITEMS)
	menu.confirm()
	assert_int(menu.cancel().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)
	assert_int(menu.index()).override_failure_message(
		"backing out of the bag landed the cursor on the wrong row").is_equal(PauseMenu.Row.ITEMS)


func test_the_bag_is_listed_in_the_order_it_was_filled() -> void:
	var menu := PauseMenu.of(_slots([]), _bag([[&"gate_key", "Gate key", 1], [&"lamp_oil", "Lamp oil", 2]]))
	menu.move(PauseMenu.Row.ITEMS)
	menu.confirm()
	assert_str(menu.item(0).name).is_equal("Gate key")
	assert_str(menu.item(1).name).is_equal("Lamp oil")
	assert_int(menu.size()).is_equal(2)


func test_an_item_row_names_it_and_counts_it_only_when_there_is_more_than_one() -> void:
	# "Gate key x1" reads as a spreadsheet; a count earns its place once there are two.
	assert_str(PauseMenu.item_label(PauseMenu.ItemRow.of(&"gate_key", "Gate key", 1))).is_equal("Gate key")
	assert_str(PauseMenu.item_label(PauseMenu.ItemRow.of(&"lamp_oil", "Lamp oil", 3))).is_equal("Lamp oil x3")


func test_refreshing_keeps_the_bag_and_the_cursor() -> void:
	var menu := PauseMenu.of(_slots([]), _bag([[&"gate_key", "Gate key", 1], [&"lamp_oil", "Lamp oil", 1]]))
	menu.move(PauseMenu.Row.ITEMS)
	menu.confirm()
	menu.move(1)
	menu.refresh(_slots([]), _bag([[&"gate_key", "Gate key", 1], [&"lamp_oil", "Lamp oil", 4]]))
	assert_int(menu.page()).is_equal(PauseMenu.Page.ITEMS)
	assert_int(menu.index()).is_equal(1)
	assert_int(menu.item(1).count).is_equal(4)


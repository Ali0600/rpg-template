extends GdUnitTestSuite
## The save point's rules, with no screen in the way.
##
## There is one rule here and it is a NEGATIVE of the rule every other slot list in this project
## follows: an empty slot is not refused. PauseMenu and SlotMenu both guard against a row with
## no data behind it, because both are about LOADING - and the same guard on a save page is the
## bug, since a first save is aimed at exactly the row those two turn away.

## Slots by index: the ones named in `filled` hold a save, the ones in `damaged` hold a file
## that cannot be read, and the rest are empty. The three states the wording draws.
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

func test_a_fresh_menu_opens_on_the_first_slot() -> void:
	var menu := SaveMenu.of(_slots([]))
	assert_int(menu.index()).is_equal(0)
	assert_int(menu.size()).is_equal(3)

func test_the_cursor_wraps_both_ways() -> void:
	var menu := SaveMenu.of(_slots([]))
	assert_bool(menu.move(-1)).is_true()
	assert_int(menu.index()).is_equal(2)
	assert_bool(menu.move(1)).is_true()
	assert_int(menu.index()).is_equal(0)

func test_a_single_slot_list_does_not_move() -> void:
	# One row is a list with nowhere to go, and a cursor that appeared to move on it would be
	# reporting a change the screen cannot draw.
	var menu := SaveMenu.of(_slots([], 1))
	assert_bool(menu.move(1)).is_false()
	assert_int(menu.index()).is_equal(0)

func test_an_empty_slot_is_a_legal_place_to_save() -> void:
	# THE rule. Every other menu here refuses a row with nothing behind it; this one must not,
	# or a new game can never write its first save.
	var menu := SaveMenu.of(_slots([]))
	assert_int(menu.confirm()).is_equal(0)

func test_a_damaged_slot_can_be_written_over() -> void:
	# save() parks whatever it is about to overwrite, so pointing at a broken file is a
	# recoverable act rather than a destructive one - and refusing it would strand a player
	# whose only slot went bad.
	var menu := SaveMenu.of(_slots([], 3, [0]))
	assert_int(menu.confirm()).is_equal(0)

func test_confirm_answers_the_row_the_cursor_is_on() -> void:
	var menu := SaveMenu.of(_slots([0]))
	menu.move(2)
	assert_int(menu.confirm()).is_equal(2)

func test_a_list_with_no_slots_at_all_refuses() -> void:
	# Unreachable through a valid config - problems() refuses save_slots below one - and armed
	# anyway, because the day a game ships zero slots is the day a screen with no rows would
	# otherwise answer "write slot -1".
	var menu := SaveMenu.of(_slots([], 0))
	assert_int(menu.confirm()).is_equal(-1)

func test_a_refresh_shows_what_was_just_written_and_keeps_the_cursor() -> void:
	# What makes a save leave the screen OPEN worth doing: the row the player is looking at has
	# to change, or the press reads as one the game dropped.
	var menu := SaveMenu.of(_slots([]))
	menu.move(1)
	assert_bool(menu.summary(1).has_save()).is_false()
	menu.refresh(_slots([1]))
	assert_int(menu.index()).is_equal(1)
	assert_bool(menu.summary(1).has_save()).is_true()

func test_a_refresh_onto_a_shorter_list_keeps_the_cursor_on_a_row() -> void:
	var menu := SaveMenu.of(_slots([], 3))
	menu.move(2)
	menu.refresh(_slots([], 1))
	assert_int(menu.index()).is_equal(0)

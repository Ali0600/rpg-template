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
	# Derived from the enum, not typed as a number: a literal here has to be found and changed
	# every time a row is added, and the version that is merely WRONG still passes for a while.
	assert_int(menu.size()).is_equal(PauseMenu.Row.size())

func test_the_top_cursor_wraps_both_ways() -> void:
	var menu := PauseMenu.of(_slots([]))
	assert_bool(menu.move(-1)).is_true()
	# Backwards from the top lands on the LAST row, whichever that now is.
	assert_int(menu.index()).is_equal(PauseMenu.Row.size() - 1)
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


func test_confirming_gear_in_the_bag_does_nothing_now_that_it_has_a_page() -> void:
	# M19 answered EQUIP here; M20 moved the verb to a page of its own, which is where every
	# game this is modelled on keeps it. The bag is a list of what is carried and nothing more,
	# so a confirm on a sword is as inert as a confirm on a key.
	var menu := PauseMenu.of(_slots([]),
		[PauseMenu.ItemRow.of(&"sword", "Sword", 1, "", &"weapon")])
	# Named, never counted - the suite's own rule.
	menu.move(PauseMenu.Row.ITEMS)
	menu.confirm()
	assert_int(menu.confirm().kind).override_failure_message(
		"the bag still equips, so two screens own one verb").is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.ITEMS)

func test_an_equipped_row_is_marked() -> void:
	var worn := PauseMenu.ItemRow.of(&"sword", "Sword", 1, "", &"weapon", true)
	assert_str(PauseMenu.item_label(worn)).override_failure_message(
		"nothing in the list says which sword is the one you are holding").contains("(E)")
	var spare := PauseMenu.ItemRow.of(&"sword", "Sword", 1, "", &"weapon", false)
	assert_str(PauseMenu.item_label(spare)).not_contains("(E)")

func test_the_marker_survives_a_stack_count() -> void:
	# The near miss: two swords, one worn, must read as both marked AND counted.
	var row := PauseMenu.ItemRow.of(&"sword", "Sword", 2, "", &"weapon", true)
	var label := PauseMenu.item_label(row)
	assert_str(label).contains("(E)")
	assert_str(label).contains("x2")

func test_confirming_a_carried_thing_still_does_nothing() -> void:
	# There is still no general "use" verb - a potion heals in every RPG ever written, where
	# "use the rope on the well" is a puzzle. Only equipment answers here; a slotless row
	# answering anything would be the world acting on a press that has no meaning.
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



func test_confirming_the_sound_row_asks_for_the_next_step() -> void:
	var menu := PauseMenu.of(_slots([]), [], "Normal")
	menu.move(PauseMenu.Row.SOUND)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.SOUND)


func test_the_sound_row_works_in_a_game_with_no_save_slots() -> void:
	# The row has nothing to do with saves, and a game configured without them must still be
	# able to turn the sound down. It is exempt from the empty-slot guard the way Items is -
	# and that exemption is the whole reason this test exists, because the guard sits between
	# the cursor and every row below Resume.
	# Zero slots, not three empty ones: the guard fires on the LIST being empty.
	var menu := PauseMenu.of(_slots([], 0), [], "Loud")
	menu.move(PauseMenu.Row.SOUND)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.SOUND)
	# The control: a slot row in the same menu still refuses, so this is not just "nothing is
	# guarded any more".
	menu.move(PauseMenu.Row.SAVE - PauseMenu.Row.SOUND)
	assert_int(menu.index()).is_equal(PauseMenu.Row.SAVE)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)


func test_the_sound_row_says_what_the_setting_is() -> void:
	# Carried as text rather than read: the menu may not ask an autoload, so the world hands it
	# the words the way it hands over slot summaries.
	assert_str(PauseMenu.of(_slots([]), [], "Quiet").sound_label()).is_equal("Sound: Quiet")


func test_a_menu_told_nothing_about_sound_still_draws_the_row() -> void:
	# A blank label would render as an empty line, which reads as a menu that failed to draw.
	assert_str(PauseMenu.of(_slots([])).sound_label()).is_not_empty()


# --- the equipment pages ------------------------------------------------------------------
#
# The verb the bag used to answer lives here now: a list of slots, each opening the carried
# gear that fits it. Slot-first because that is what every reference game does, and because
# "what am I wearing" should be a glance rather than a scan of the whole bag.


func _gear(entries: Array) -> Array:
	var out: Array = []
	for entry: Array in entries:
		out.append(PauseMenu.GearRow.of(entry[0], entry[1],
			entry[2] if entry.size() > 2 else "", entry[3] if entry.size() > 3 else ""))
	return out


func _dressed() -> PauseMenu:
	# A weapon slot holding a sword, an empty armour slot, and a bag with one candidate for
	# each plus something that fits neither.
	return PauseMenu.of(_slots([]), [
			PauseMenu.ItemRow.of(&"sword", "Sword", 1, "", &"weapon", true),
			PauseMenu.ItemRow.of(&"vest", "Vest", 1, "", &"armor"),
			PauseMenu.ItemRow.of(&"gate_key", "Gate key", 1),
		], "", "", _gear([
			[&"weapon", "Weapon", "Sword", "Take off: Atk -3  (now Atk +0 Def +0)"],
			[&"armor", "Armor"],
		]), "Atk 5+3  Def 1+0")


func test_confirming_the_equipment_row_opens_the_slot_list() -> void:
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.EQUIP)
	assert_int(menu.index()).is_equal(0)
	assert_int(menu.size()).override_failure_message(
		"the slot list is not one row per slot").is_equal(2)


func test_the_equipment_page_opens_in_a_game_with_no_save_slots() -> void:
	# The Items and Sound exemption, for the same reason: dressing yourself has nothing to do
	# with saves. Its control is below - Save still refuses.
	var menu := PauseMenu.of([], [], "", "", _gear([[&"weapon", "Weapon"]]))
	menu.move(PauseMenu.Row.EQUIP)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.EQUIP)


func test_a_game_with_no_save_slots_still_cannot_save() -> void:
	# The control for the test above: the exemption is for three named rows, not a hole.
	var menu := PauseMenu.of([], [], "", "", _gear([[&"weapon", "Weapon"]]))
	menu.move(PauseMenu.Row.SAVE)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)


func test_confirming_a_slot_opens_its_candidates_and_asks_for_nothing() -> void:
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.EQUIP_PICK)
	assert_str(String(menu.pick_slot())).is_equal("weapon")


func test_the_candidate_list_holds_only_what_fits_the_slot() -> void:
	# The bag has a sword, a vest and a key. The weapon page offers the sword and the row that
	# takes it off - never the vest, and never the key.
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.confirm()
	assert_int(menu.size()).override_failure_message(
		"the weapon page is offering things that are not weapons").is_equal(2)
	assert_str(menu.pick_row(0).name).is_equal("Sword")
	assert_object(menu.pick_row(1)).override_failure_message(
		"the last row is a candidate, so there is no way to take gear off").is_null()


func test_the_take_off_row_answers_with_the_slot() -> void:
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.confirm()
	menu.move(1)
	var pick := menu.confirm()
	assert_int(pick.kind).override_failure_message(
		"the take-off row is decoration and gear is forever").is_equal(PauseMenu.Kind.UNEQUIP)
	assert_str(String(pick.gear)).is_equal("weapon")


func test_taking_off_an_empty_slot_is_refused() -> void:
	# Refused rather than shrugged at, the empty-save-slot rule: a menu that accepts a press
	# and does nothing reads as a menu that broke.
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.move(1)  # the armour slot, which is bare
	menu.confirm()
	assert_int(menu.size()).is_equal(2)
	menu.move(1)  # past the vest, onto the take-off row
	assert_int(menu.confirm().kind).override_failure_message(
		"taking nothing off was accepted").is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).override_failure_message(
		"a refusal left the page anyway").is_equal(PauseMenu.Page.EQUIP_PICK)


func test_confirming_a_candidate_equips_it_and_returns_to_the_slots() -> void:
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.move(1)  # the armour slot
	menu.confirm()
	var pick := menu.confirm()
	assert_int(pick.kind).is_equal(PauseMenu.Kind.EQUIP)
	assert_str(String(pick.item)).is_equal("vest")
	assert_int(menu.page()).override_failure_message(
		"equipping stranded the cursor on the candidate list").is_equal(PauseMenu.Page.EQUIP)
	assert_int(menu.index()).override_failure_message(
		"the cursor came back to the wrong slot").is_equal(1)


func test_cancel_on_the_candidates_returns_to_the_slot_it_was_asked_about() -> void:
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.move(1)
	menu.confirm()
	assert_int(menu.cancel().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.EQUIP)
	assert_int(menu.index()).is_equal(1)


func test_cancel_on_the_slot_list_returns_to_the_equipment_row() -> void:
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	assert_int(menu.cancel().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)
	assert_int(menu.index()).override_failure_message(
		"backing out of the wardrobe landed on the wrong row").is_equal(PauseMenu.Row.EQUIP)


func test_a_slot_says_what_is_in_it_and_says_when_it_is_bare() -> void:
	assert_str(PauseMenu.gear_label(PauseMenu.GearRow.of(&"weapon", "Weapon", "Sword"))) \
		.is_equal("Weapon: Sword")
	assert_str(PauseMenu.gear_label(PauseMenu.GearRow.of(&"armor", "Armor"))) \
		.override_failure_message("a bare slot draws a blank, which reads as a failed draw") \
		.is_equal("Armor: (nothing)")


func test_the_take_off_row_is_worded_as_a_verb() -> void:
	assert_str(PauseMenu.pick_label(null)).is_equal("(take off)")
	assert_str(PauseMenu.pick_label(PauseMenu.ItemRow.of(&"sword", "Sword", 1))) \
		.is_equal("Sword")


func test_the_stats_readout_is_whatever_the_world_worded() -> void:
	# The menu does not compose it: naming a stat means asking what the game calls one.
	assert_str(_dressed().stats_label()).is_equal("Atk 5+3  Def 1+0")
	assert_str(PauseMenu.of(_slots([])).stats_label()).override_failure_message(
		"a menu told nothing about stats invented some").is_equal("")


func test_refreshing_keeps_the_equipment_page_and_clamps_a_shrunken_list() -> void:
	# The bag can change under the page - a fight, a hook, a load. The cursor must land on a
	# row that exists rather than past the end of one that no longer does.
	var menu := _dressed()
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.confirm()
	menu.move(1)
	menu.refresh(_slots([]), [], "", "", _gear([[&"weapon", "Weapon"]]), "Atk 5+0  Def 1+0")
	assert_int(menu.page()).is_equal(PauseMenu.Page.EQUIP_PICK)
	assert_int(menu.size()).is_equal(1)
	assert_int(menu.index()).override_failure_message(
		"the cursor is past the end of the list it is drawn over").is_equal(0)


# --- the status page ----------------------------------------------------------------------
#
# The genre's fourth standard command, and the one a player opens the menu FOR: how hurt am I,
# how close to the next level. Read-only - every line is worded by the world, because knowing
# what a game calls a level means knowing whether it has one.


func test_confirming_the_status_row_opens_the_page() -> void:
	var menu := PauseMenu.of(_slots([]), [], "", "", [], "",
		["Level 3", "HP 12/24", "XP 40  (next in 10)"] as Array[String])
	menu.move(PauseMenu.Row.STATUS)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.STATUS)
	assert_int(menu.size()).is_equal(3)
	assert_str(menu.status_line(0)).is_equal("Level 3")


func test_the_status_page_opens_in_a_game_with_no_save_slots() -> void:
	# The Items, Equipment and Sound exemption, for the same reason: asking how you are has
	# nothing to do with saves.
	var menu := PauseMenu.of([], [], "", "", [], "", ["Level 1"] as Array[String])
	menu.move(PauseMenu.Row.STATUS)
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.STATUS)


func test_there_is_nothing_on_the_status_page_to_press() -> void:
	# A readout. A page that DID something on confirm would be a different screen, and a menu
	# that accepts a press and does nothing reads as one that broke.
	var menu := PauseMenu.of(_slots([]), [], "", "", [], "", ["Level 3"] as Array[String])
	menu.move(PauseMenu.Row.STATUS)
	menu.confirm()
	assert_int(menu.confirm().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).override_failure_message(
		"a press on the status page left it").is_equal(PauseMenu.Page.STATUS)


func test_a_status_with_nothing_to_say_still_says_so() -> void:
	# The empty-bag rule: a page of blanks reads as a page that failed to draw. A game with no
	# fighting in it has no level and no HP, and that is a fact rather than an error.
	var menu := PauseMenu.of(_slots([]), [], "", "", [], "", [] as Array[String])
	menu.move(PauseMenu.Row.STATUS)
	menu.confirm()
	assert_int(menu.size()).is_equal(1)
	assert_str(menu.status_line(0)).is_equal("(nothing to report)")


func test_cancel_on_the_status_page_returns_to_the_status_row() -> void:
	var menu := PauseMenu.of(_slots([]), [], "", "", [], "", ["Level 3"] as Array[String])
	menu.move(PauseMenu.Row.STATUS)
	menu.confirm()
	assert_int(menu.cancel().kind).is_equal(PauseMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)
	assert_int(menu.index()).override_failure_message(
		"backing out of the status page landed on the wrong row").is_equal(PauseMenu.Row.STATUS)


# --- the member step ------------------------------------------------------------------------

func _members() -> Array:
	return [{"id": "", "name": "You"}, {"id": "rook", "name": "Rook"}]

func test_with_one_member_equipment_opens_its_page_directly() -> void:
	# The control every counting session depends on: with nobody else in the party, the flow is
	# exactly the one that shipped and the presses are the presses those files recorded.
	var menu := PauseMenu.of([], [], "", "", [PauseMenu.GearRow.of(&"weapon", "Weapon")])
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	assert_int(menu.page()).is_equal(PauseMenu.Page.EQUIP)

func test_with_a_party_equipment_asks_whose_first() -> void:
	var menu := PauseMenu.of([], [], "", "", [PauseMenu.GearRow.of(&"weapon", "Weapon")], "",
		[], _members())
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	assert_int(menu.page()).override_failure_message(
		"a party opened somebody's equipment without asking whose").is_equal(PauseMenu.Page.MEMBER)
	assert_int(menu.size()).is_equal(2)

func test_with_a_party_status_asks_whose_first() -> void:
	var menu := PauseMenu.of([], [], "", "", [], "", ["Level 1"], _members())
	menu.move(PauseMenu.Row.STATUS)
	menu.confirm()
	assert_int(menu.page()).is_equal(PauseMenu.Page.MEMBER)

func test_choosing_a_member_asks_the_world_to_word_their_page() -> void:
	# The menu decides WHO and never learns what a level is - the _status and _stats shape.
	var menu := PauseMenu.of([], [], "", "", [PauseMenu.GearRow.of(&"weapon", "Weapon")], "",
		[], _members())
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.move(1)
	var pick := menu.confirm()
	assert_int(pick.kind).is_equal(PauseMenu.Kind.MEMBER)
	assert_str(String(pick.gear)).override_failure_message(
		"the menu asked the world about the wrong member").is_equal("rook")
	assert_int(menu.page()).override_failure_message(
		"choosing a member did not open the page it was standing in front of") \
		.is_equal(PauseMenu.Page.EQUIP)

func test_the_member_page_names_who_it_is_asking_about() -> void:
	var menu := PauseMenu.of([], [], "", "", [], "", ["Level 1"], _members())
	menu.move(PauseMenu.Row.STATUS)
	menu.confirm()
	assert_str(menu.member_label(0)).is_equal("You")
	assert_str(menu.member_label(1)).is_equal("Rook")

func test_backing_out_of_a_members_page_returns_to_the_member_list() -> void:
	# The player is changing their mind about WHOSE page they wanted, not about wanting one.
	var menu := PauseMenu.of([], [], "", "", [PauseMenu.GearRow.of(&"weapon", "Weapon")], "",
		[], _members())
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.move(1)
	menu.confirm()
	menu.cancel()
	assert_int(menu.page()).override_failure_message(
		"backing out of a member's page left the menu entirely").is_equal(PauseMenu.Page.MEMBER)
	assert_int(menu.index()).override_failure_message(
		"the member list came back with the cursor somewhere else").is_equal(1)

func test_backing_out_of_the_member_list_returns_to_the_row_that_opened_it() -> void:
	var menu := PauseMenu.of([], [], "", "", [], "", ["Level 1"], _members())
	menu.move(PauseMenu.Row.STATUS)
	menu.confirm()
	menu.cancel()
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)
	assert_int(menu.index()).override_failure_message(
		"the member list backed out onto the wrong row").is_equal(PauseMenu.Row.STATUS)

func test_with_one_member_backing_out_of_equipment_still_leaves_it() -> void:
	# The other half of the control: no member step means nothing to come back to, so cancel
	# behaves exactly as it always did.
	var menu := PauseMenu.of([], [], "", "", [PauseMenu.GearRow.of(&"weapon", "Weapon")])
	menu.move(PauseMenu.Row.EQUIP)
	menu.confirm()
	menu.cancel()
	assert_int(menu.page()).is_equal(PauseMenu.Page.TOP)

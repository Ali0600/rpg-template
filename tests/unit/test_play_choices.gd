extends GdUnitTestSuite
## What a game offers a player about how it plays, and which value is in effect (M51).
##
## Pure - no world, no settings file. The wiring (a row on the page, a press writing the choice, the
## next fight opening the screen it names) is test_world_play_choices'.

const GAME := "res://data/games/quest.tres"


func _quest() -> GameManifest:
	return load(GAME) as GameManifest


func test_a_game_that_can_fight_offers_every_fight_style_and_one_that_cannot_offers_none() -> void:
	assert_array(PlayChoices.offered(_quest(), PlayChoices.FIGHTS)).contains_exactly(CombatDef.STYLES)
	var peaceful := _quest().duplicate() as GameManifest
	peaceful.combat = null
	assert_array(PlayChoices.offered(peaceful, PlayChoices.FIGHTS)).override_failure_message(
		"a game with no combat offers a choice about how to fight").is_empty()


func test_movement_and_saving_are_offered_both_ways_to_a_game_with_a_config() -> void:
	assert_array(PlayChoices.offered(_quest(), PlayChoices.MOVEMENT)).contains_exactly(
		[PlayChoices.MOVE_FREE, PlayChoices.MOVE_GRID])
	assert_array(PlayChoices.offered(_quest(), PlayChoices.SAVING)).contains_exactly(
		GameConfig.SAVE_POLICIES)
	var unconfigured := _quest().duplicate() as GameManifest
	unconfigured.config = null
	assert_array(PlayChoices.offered(unconfigured, PlayChoices.MOVEMENT)).is_empty()
	assert_array(PlayChoices.offered(null, PlayChoices.FIGHTS)).is_empty()
	assert_array(PlayChoices.offered(_quest(), &"no_such_axis")).is_empty()


func test_the_movement_words_are_the_scaffolds_own() -> void:
	# Two lists of one fact drift. The settings file and `new_game.sh --movement=` say it one way.
	assert_array([String(PlayChoices.MOVE_FREE), String(PlayChoices.MOVE_GRID)]).contains_exactly(
		GameScaffold.MOVEMENTS)


func test_what_a_game_declares_is_what_a_player_who_never_chose_gets() -> void:
	var quest := _quest()
	assert_str(String(PlayChoices.declared(quest, PlayChoices.FIGHTS))).is_equal(
		String(quest.combat.style))
	assert_str(String(PlayChoices.declared(quest, PlayChoices.MOVEMENT))).is_equal(
		String(PlayChoices.MOVE_FREE))
	assert_str(String(PlayChoices.declared(quest, PlayChoices.SAVING))).is_equal(
		String(quest.config.save_policy))
	# The other side of each, so an answer that ignored the data would be caught.
	var other := quest.duplicate() as GameManifest
	other.combat = quest.combat.duplicate() as CombatDef
	other.combat.style = CombatDef.STYLE_ARENA
	other.config = quest.config.duplicate() as GameConfig
	other.config.grid_step = true
	other.config.save_policy = GameConfig.SAVE_AT_POINT
	assert_str(String(PlayChoices.declared(other, PlayChoices.FIGHTS))).is_equal("arena")
	assert_str(String(PlayChoices.declared(other, PlayChoices.MOVEMENT))).is_equal("grid")
	assert_str(String(PlayChoices.declared(other, PlayChoices.SAVING))).is_equal("at_point")


func test_a_chosen_value_applies_only_when_the_game_offers_it() -> void:
	var styles: Array[StringName] = [CombatDef.STYLE_TURNS, CombatDef.STYLE_ARENA]
	assert_str(String(PlayChoices.effective(&"arena", styles, &"turns"))).is_equal("arena")
	assert_str(String(PlayChoices.effective(&"", styles, &"turns"))).override_failure_message(
		"no choice at all did not fall back to the game's own").is_equal("turns")
	assert_str(String(PlayChoices.effective(&"realtime", styles, &"arena"))).override_failure_message(
		"a word nobody offers took effect").is_equal("arena")
	var nothing: Array[StringName] = []
	assert_str(String(PlayChoices.effective(&"arena", nothing, &""))).is_empty()


func test_one_press_turns_a_row_to_the_next_value_and_round() -> void:
	var styles: Array[StringName] = [CombatDef.STYLE_TURNS, CombatDef.STYLE_ARENA]
	assert_str(String(PlayChoices.next(styles, &"turns"))).is_equal("arena")
	assert_str(String(PlayChoices.next(styles, &"arena"))).override_failure_message(
		"the last value did not wrap round to the first").is_equal("turns")
	assert_str(String(PlayChoices.next(styles, &"realtime"))).is_equal("turns")
	var nothing: Array[StringName] = []
	assert_str(String(PlayChoices.next(nothing, &"turns"))).is_equal("turns")


func test_a_row_takes_two_values_to_be_a_choice() -> void:
	# A row cycling among one value is a key that does nothing.
	var none: Array[StringName] = []
	var one: Array[StringName] = [CombatDef.STYLE_TURNS]
	var two: Array[StringName] = [CombatDef.STYLE_TURNS, CombatDef.STYLE_ARENA]
	assert_bool(PlayChoices.choosable(none)).is_false()
	assert_bool(PlayChoices.choosable(one)).override_failure_message(
		"a row with one value to cycle through counts as a choice").is_false()
	assert_bool(PlayChoices.choosable(two)).is_true()


func test_every_value_any_axis_offers_has_a_word_on_the_page() -> void:
	# A value with no word draws as its raw id - "at_point" - on a page where every other row is words.
	var checked := 0
	for axis: StringName in PlayChoices.AXES:
		for value: StringName in PlayChoices.offered(_quest(), axis):
			assert_bool(PlayChoices.WORDS.has(value)).override_failure_message(
				"'%s' on the %s row has no word" % [value, axis]).is_true()
			checked += 1
	assert_int(checked).override_failure_message(
		"almost nothing was offered, so this proves nothing").is_greater(5)
	assert_str(PlayChoices.word(CombatDef.STYLE_ARENA)).is_equal("Sword")
	assert_str(PlayChoices.word(&"unheard_of")).is_equal("unheard_of")

extends GdUnitTestSuite
## The tuning file's own validation.
##
## Every number here is one a designer edits in a text field, so every one of them has a value
## that breaks the game quietly. `problems()` is where that is said out loud, at load, instead
## of showing up as a character who cannot move.

func test_a_game_with_no_save_slots_is_reported() -> void:
	# Zero slots is a pause menu whose Save and Load pages have nothing on them - a screen
	# that opens onto nothing reads as a broken menu, not as a configuration choice.
	var config := GameConfig.new()
	config.save_slots = 0
	assert_str(", ".join(config.problems())).contains("save_slots")

func test_the_shipped_config_offers_at_least_one_slot() -> void:
	# The control: a validator that complained about everything would pass the test above and
	# fail the game.
	var config := load("res://data/game_config.tres") as GameConfig
	assert_object(config).is_not_null()
	assert_int(config.save_slots).is_greater_equal(1)
	assert_array(config.problems()).is_empty()

func test_a_save_policy_nobody_implements_is_reported() -> void:
	# A typo'd policy FAILS THE BUILD rather than falling back, the npc `behavior` rule and for
	# its reason: silently reading as "anywhere" is a save point nobody can find beside a Save
	# row nobody removed, and both halves look correct on their own.
	var config := GameConfig.new()
	config.save_policy = &"at-point"
	assert_str(", ".join(config.problems())).contains("save_policy")

func test_both_shipped_save_policies_are_accepted() -> void:
	# The control the refusal above needs: a validator that rejected everything would pass that
	# test and fail every game.
	for policy: StringName in GameConfig.SAVE_POLICIES:
		var config := GameConfig.new()
		config.save_policy = policy
		assert_array(config.problems()).override_failure_message(
			"the config refused '%s', which is one of its own legal policies" % policy).is_empty()

func test_a_config_that_says_nothing_saves_anywhere() -> void:
	# The default is what every game recorded before this field existed was playing, so a
	# config written then must still mean the same thing now.
	assert_str(String(GameConfig.new().save_policy)).is_equal(String(GameConfig.SAVE_ANYWHERE))

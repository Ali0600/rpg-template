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

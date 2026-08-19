extends GdUnitTestSuite
## The precedence that decides which game boots, proven over literal lists.
##
## It is tested through the pure choose() rather than by arranging a filesystem and a project
## setting, because the four surfaces that must agree - editor, exported web build,
## `-s tools/x.gd`, and a QA run - cannot all be staged from a test. What CAN be pinned is the
## rule itself, in one place, which is the only reason those four agree at all.
##
## The case that matters is the one this repo cannot reach: more than one game and nothing
## choosing must REFUSE. One game ships today, so `ONE` is the live path and `TWO` is the rule
## kept armed for the day a second is added - picking the first one would not present as a
## selection bug, it would present as the game you meant to run behaving strangely.

const TWO: Array[String] = ["quest", "sequel"]
const ONE: Array[String] = ["quest"]

## A PackedStringArray is not a constant expression, so this is a function rather than a const.
func _no_args() -> PackedStringArray:
	return PackedStringArray([])


func test_the_command_line_wins_over_the_project_setting() -> void:
	# The QA harness has no other way in: the setting is committed, and a script that wants
	# a different game cannot edit project.godot on its way past.
	var args := PackedStringArray(["--game=quest"])
	assert_str(GameSelect.choose(TWO, args, "sequel")).is_equal("quest")


func test_the_argument_is_read_from_anywhere_on_the_command_line() -> void:
	# It arrives after `--` for a QA run and before it for a tool run, so both are one list.
	var args := PackedStringArray(["--headless", "--qa-script=res://x.json", "--game=quest"])
	assert_str(GameSelect.choose(TWO, args, "")).is_equal("quest")


func test_the_project_setting_chooses_when_the_command_line_does_not() -> void:
	assert_str(GameSelect.choose(TWO, _no_args(), "quest")).is_equal("quest")


func test_a_single_game_needs_no_setting_at_all() -> void:
	# A template someone has just cloned has exactly one game and should simply run.
	assert_str(GameSelect.choose(ONE, _no_args(), "")).is_equal("quest")


func test_two_games_and_no_choice_is_a_refusal_rather_than_a_guess() -> void:
	assert_str(GameSelect.choose(TWO, _no_args(), "")).is_empty()


func test_no_games_at_all_is_a_refusal() -> void:
	var none: Array[String] = []
	assert_str(GameSelect.choose(none, _no_args(), "")).is_empty()


func test_an_unknown_name_is_returned_so_the_error_can_name_it() -> void:
	# choose() does not validate; resolve() reports "no game with id 'typo'". Swallowing it
	# here would turn a typo into the ambiguity message, which sends you to the wrong file.
	var args := PackedStringArray(["--game=typo"])
	assert_str(GameSelect.choose(TWO, args, "quest")).is_equal("typo")


func test_the_shipped_project_boots_a_game() -> void:
	# The pure cases above say nothing about whether this project is wired up: if every manifest
	# were missing, all of them would still pass. One game ships, so resolving is the whole of
	# being wired up - there is no menu to fall back on and no default to guess.
	assert_bool(GameSelect.ids().is_empty()).is_false()
	assert_object(GameSelect.resolve()).override_failure_message(
		"the project ships games but resolves none of them").is_not_null()

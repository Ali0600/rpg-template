extends GdUnitTestSuite
## The precedence that decides which game boots, proven over literal lists.
##
## It is tested through the pure choose() rather than by arranging a filesystem and a project
## setting, because the four surfaces that must agree - editor, exported web build,
## `-s tools/x.gd`, and a QA run - cannot all be staged from a test. What CAN be pinned is the
## rule itself, in one place, which is the only reason those four agree at all.
##
## The last case is the one that matters: two games and nothing choosing must REFUSE. Picking
## the first one does not present as a selection bug - it presents as the game you meant to
## run behaving strangely, and you go and debug that instead.

const TWO: Array[String] = ["demo", "quest"]
const ONE: Array[String] = ["demo"]

## A PackedStringArray is not a constant expression, so this is a function rather than a const.
func _no_args() -> PackedStringArray:
	return PackedStringArray([])


func test_the_command_line_wins_over_the_project_setting() -> void:
	# The QA harness has no other way in: the setting is committed, and a script that wants
	# a different game cannot edit project.godot on its way past.
	var args := PackedStringArray(["--game=quest"])
	assert_str(GameSelect.choose(TWO, args, "demo")).is_equal("quest")


func test_the_argument_is_read_from_anywhere_on_the_command_line() -> void:
	# It arrives after `--` for a QA run and before it for a tool run, so both are one list.
	var args := PackedStringArray(["--headless", "--qa-script=res://x.json", "--game=quest"])
	assert_str(GameSelect.choose(TWO, args, "")).is_equal("quest")


func test_the_project_setting_chooses_when_the_command_line_does_not() -> void:
	assert_str(GameSelect.choose(TWO, _no_args(), "quest")).is_equal("quest")


func test_a_single_game_needs_no_setting_at_all() -> void:
	# A template someone has just cloned has exactly one game and should simply run.
	assert_str(GameSelect.choose(ONE, _no_args(), "")).is_equal("demo")


func test_two_games_and_no_choice_is_a_refusal_rather_than_a_guess() -> void:
	assert_str(GameSelect.choose(TWO, _no_args(), "")).is_empty()


func test_no_games_at_all_is_a_refusal() -> void:
	var none: Array[String] = []
	assert_str(GameSelect.choose(none, _no_args(), "")).is_empty()


func test_an_unknown_name_is_returned_so_the_error_can_name_it() -> void:
	# choose() does not validate; resolve() reports "no game with id 'typo'". Swallowing it
	# here would turn a typo into the ambiguity message, which sends you to the wrong file.
	var args := PackedStringArray(["--game=typo"])
	assert_str(GameSelect.choose(TWO, args, "demo")).is_equal("typo")


func test_the_shipped_project_resolves_to_a_game() -> void:
	# The four pure cases above say nothing about whether this project is wired up. If the
	# setting were misspelt or the manifest missing, every test above would still pass.
	var game := GameSelect.resolve()
	assert_object(game).is_not_null()
	assert_bool(GameSelect.ids().is_empty()).is_false()

func test_an_explicit_choice_leaves_nothing_for_a_human_to_resolve() -> void:
	# unresolved() is what the picker is built on, and it must stay OUT of the way whenever
	# the precedence already answered - which is what keeps every scripted play session, all
	# of which pass --game=, running straight into a world.
	assert_bool(GameSelect.ids().size() > 1).override_failure_message(
		"this test needs the repo to ship more than one game").is_true()
	assert_array(GameSelect.unresolved()).is_empty()

func test_a_switch_is_offered_whenever_there_is_more_than_one_game() -> void:
	# Unlike unresolved(), the precedence is irrelevant here: the player asked, which overrules
	# whatever the command line or the setting said at boot.
	assert_int(GameSelect.switchable().size()).is_equal(GameSelect.ids().size())

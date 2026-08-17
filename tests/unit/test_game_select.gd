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


func test_the_shipped_project_either_boots_a_game_or_offers_a_menu() -> void:
	# The four pure cases above say nothing about whether this project is wired up: if every
	# manifest were missing, all of them would still pass. Since the boot setting is empty on
	# purpose, "resolves" is no longer the whole of being wired up - offering a choice is the
	# other half, and exactly one of the two must be true.
	assert_bool(GameSelect.ids().is_empty()).is_false()
	var boots := GameSelect.resolve() != null
	var asks := not GameSelect.unresolved().is_empty()
	assert_bool(boots or asks).override_failure_message(
		"the project neither boots a game nor offers one to choose").is_true()

func test_an_explicit_choice_leaves_nothing_for_a_human_to_resolve() -> void:
	# The rule the picker is built on, over literal inputs: the process a test runs in has its
	# own command line and its own project setting and neither can be staged, but the rule they
	# feed can be. This is what keeps every scripted play session - all of which pass --game= -
	# running straight into a world instead of into a menu.
	assert_bool(GameSelect.should_ask(TWO, PackedStringArray(["--game=quest"]), "")).is_false()
	assert_bool(GameSelect.should_ask(TWO, _no_args(), "demo")).is_false()

func test_nothing_choosing_between_two_games_is_what_summons_the_picker() -> void:
	assert_bool(GameSelect.should_ask(TWO, _no_args(), "")).is_true()

func test_a_single_game_never_stops_to_ask() -> void:
	# A freshly cloned template has one game and should simply run. A picker with one row is a
	# worse answer than no picker at all.
	assert_bool(GameSelect.should_ask(ONE, _no_args(), "")).is_false()

func test_no_games_at_all_is_an_error_rather_than_an_empty_menu() -> void:
	# The case the size guard is actually for, and the reason a mutant caught that the ONE-game
	# case does not need it: choose() already answers "demo" when there is only demo. With no
	# games there is nothing for it to answer, and a picker showing an empty list would be a
	# worse report of "this project has no games" than the error resolve() raises.
	var none: Array[String] = []
	assert_bool(GameSelect.should_ask(none, _no_args(), "")).is_false()

func test_the_shipped_project_asks_rather_than_guesses() -> void:
	# The wiring, as opposed to the rule: the boot setting is empty on purpose and two games
	# ship, so this repo really does put a human in front of the choice. If the setting were
	# ever filled in again the picker would stop appearing, and this is what would say so.
	assert_bool(GameSelect.ids().size() > 1).override_failure_message(
		"this test needs the repo to ship more than one game").is_true()
	assert_int(GameSelect.unresolved().size()).is_equal(GameSelect.ids().size())

func test_a_switch_is_offered_whenever_there_is_more_than_one_game() -> void:
	# Unlike unresolved(), the precedence is irrelevant here: the player asked, which overrules
	# whatever the command line or the setting said at boot.
	assert_int(GameSelect.switchable().size()).is_equal(GameSelect.ids().size())

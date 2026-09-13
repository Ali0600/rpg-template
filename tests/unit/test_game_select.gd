extends GdUnitTestSuite
## The precedence that decides which game boots, proven over literal lists.
##
## It is tested through the pure choose() rather than by arranging a filesystem and a project
## setting, because the four surfaces that must agree - editor, exported web build,
## `-s tools/x.gd`, and a QA run - cannot all be staged from a test. What CAN be pinned is the
## rule itself, in one place, which is the only reason those four agree at all.
##
## The case that matters: more than one game and nothing choosing must never pick the first -
## that would not present as a selection bug, it would present as the game you meant to run behaving
## strangely. choose() answers "nothing chose", should_ask() says a person has to, and the world
## offers the games on the title (M50).

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


func test_one_game_never_asks() -> void:
	# A template someone has just cloned has one game, and a menu with one row in it is a question
	# whose answer it already has.
	assert_bool(GameSelect.should_ask(ONE, _no_args(), "")).is_false()


func test_two_games_ask_only_when_nothing_else_chose() -> void:
	assert_bool(GameSelect.should_ask(TWO, _no_args(), "")).is_true()
	# Every scripted session names its game, which is why none of them meets the Switch game row.
	assert_bool(GameSelect.should_ask(TWO, PackedStringArray(["--game=quest"]), "")).is_false()
	assert_bool(GameSelect.should_ask(TWO, _no_args(), "quest")).is_false()


func test_the_shipped_project_boots_a_game_or_offers_them() -> void:
	# The pure cases above say nothing about whether this project is wired up: if every manifest
	# were missing, all of them would still pass. Wired up is one of two things - a game resolves,
	# or a person is offered every game there is - and resolve() is asked only when nobody is
	# offered anything, because otherwise it would print the refusal it exists to make.
	assert_bool(GameSelect.ids().is_empty()).is_false()
	var offered := GameSelect.unresolved()
	if offered.is_empty():
		assert_object(GameSelect.resolve()).override_failure_message(
			"the project ships games but neither boots one nor offers them").is_not_null()
	else:
		assert_int(offered.size()).is_equal(GameSelect.ids().size())

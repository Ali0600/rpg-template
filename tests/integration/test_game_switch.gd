extends GdUnitTestSuite
## Switching games in a running process, driven directly with no menu in the way.
##
## This is the first suite in the repo to instantiate the world scene at all, and it exists
## because world_scene builds four things ONCE - the player, the dialog box, the hint and the
## camera - and every one of those guards is right for a warp and silently wrong across games.
## Nothing errors when they misbehave: the second game just quietly wears the first game's
## sprite, walks at its speed, and reaches as far as its config said.
##
## The assertions below are one-to-one with those guards plus the state that outlives them,
## and three mutants hang off this file. Without it they are unkillable, because the only
## other thing that drives world_scene is the QA play gate and mutate_check.sh takes a gdUnit
## suite, not a JSON script.

const DEMO := "res://data/games/demo.tres"
const QUEST := "res://data/games/quest.tres"

var _world: Node2D

func before_test() -> void:
	# Autoloads outlive a suite, and this one moves both of them harder than any other.
	GameState.reset()
	Router.reset()

func after_test() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()

## Boots the world and puts a named game in it. start_game is called explicitly rather than
## leaning on _ready, so this suite says what it is testing regardless of what the project
## setting happens to say about which game boots.
func _boot(manifest_path: String) -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(load(manifest_path) as GameManifest)).override_failure_message(
		"the world would not start %s" % manifest_path).is_true()
	return _world

func test_the_game_that_was_asked_for_is_the_one_running() -> void:
	_boot(DEMO)
	assert_str(String(GameState.current_map)).is_equal("demo_town")
	_world.start_game(load(QUEST) as GameManifest)
	assert_str(String(GameState.current_map)).is_equal("quest_village")
	assert_str(String(_world.map_data().id)).is_equal("quest_village")

func test_the_player_is_rebuilt_with_the_new_games_config() -> void:
	# The sharpest of the four. `if _player == null:` means setup() runs once ever, so without
	# a teardown the second game keeps the first game's character sheet AND its GameConfig -
	# walk speed, body size, interact reach - with nothing anywhere saying so.
	_boot(DEMO)
	# Explicitly typed: _world is a Node2D here, so player() gives back an untyped value and
	# `:=` has nothing to infer from.
	var before: ActorBody = _world.player()
	assert_str(String(before.config.id)).is_equal("default")

	_world.start_game(load(QUEST) as GameManifest)
	assert_bool(is_instance_valid(before)).override_failure_message(
		"the first game's player is still alive after the switch").is_false()
	assert_object(_world.player()).is_not_null()
	var after: ActorBody = _world.player()
	assert_str(String(after.config.id)).is_equal("quest")

func test_the_flags_of_the_game_before_do_not_carry_over() -> void:
	# GameState.reset() has existed since M3 with no caller. A switch is what it was for:
	# one game's flags must not unlock another's gate, and `seen` is keyed "<map>/<object>",
	# which two games are free to collide on.
	_boot(DEMO)
	GameState.set_flag(&"carried_over", true)
	GameState.mark_seen("demo_town/well_sign")

	_world.start_game(load(QUEST) as GameManifest)
	assert_bool(GameState.has_flag(&"carried_over")).is_false()
	assert_bool(GameState.was_seen("demo_town/well_sign")).is_false()

func test_the_rebuilt_dialog_box_is_still_listened_to() -> void:
	# The quietest way this could break. A DialogBox whose `closed` nobody hears leaves Router
	# in DIALOG after the first conversation of the new game and the player never moves again -
	# and the box hides itself, so on screen the conversation looks like it ended normally.
	_boot(DEMO)
	_world.start_game(load(QUEST) as GameManifest)

	Router.open_overlay(Router.State.DIALOG)
	assert_str(Router.state_name()).is_equal("dialog")
	_world.dialog_box().closed.emit([])
	assert_str(Router.state_name()).override_failure_message(
		"closing a conversation in the switched-to game did not give control back").is_equal("world")

func test_a_conversations_flags_still_land_after_a_switch() -> void:
	# The same connection, carrying its payload rather than just firing.
	_boot(DEMO)
	_world.start_game(load(QUEST) as GameManifest)
	_world.dialog_box().closed.emit(["promised_after_switch"])
	assert_bool(GameState.has_flag(&"promised_after_switch")).is_true()

func test_switching_back_and_forth_stays_correct() -> void:
	# Teardown has to be safe when something IS built, twice, and leave nothing behind that
	# the next start_game trips over.
	_boot(DEMO)
	_world.start_game(load(QUEST) as GameManifest)
	_world.start_game(load(DEMO) as GameManifest)
	assert_str(String(GameState.current_map)).is_equal("demo_town")
	var back: ActorBody = _world.player()
	assert_str(String(back.config.id)).is_equal("default")
	assert_object(_world.dialog_box()).is_not_null()

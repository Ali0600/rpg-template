extends GdUnitTestSuite
## Starting a game over a running one, driven directly.
##
## One game ships now, so nobody switches games from the menu any more - but start_game() is
## still what a load, a restart and the boot all go through, and world_scene builds four things
## ONCE: the player, the dialog box, the hint and the camera. Every one of those guards is right
## for a warp and silently wrong for a second start_game. Nothing errors when they misbehave -
## the newly started game quietly wears the previous one's sprite, walks at its speed, and
## reaches as far as its config said.
##
## The assertions below are one-to-one with those guards plus the state that outlives them,
## and three mutants hang off this file. Without it they are unkillable, because the only
## other thing that drives world_scene is the QA play gate and mutate_check.sh takes a gdUnit
## suite, not a JSON script.

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
## The shipped game, re-pointed at a different map and given a config only this suite hands
## over. Built here rather than shipped: a second manifest in data/ purely so a test can switch
## to it would be content nobody plays, and every assertion below is about what start_game does
## with what it is HANDED, not about what happens to be on disk.
func _other_game() -> GameManifest:
	var manifest := (load(QUEST) as GameManifest).duplicate() as GameManifest
	var config := (manifest.config as GameConfig).duplicate() as GameConfig
	config.id = &"switched"
	manifest.id = &"switched"
	manifest.config = config
	manifest.start_map = &"quest_keep"
	manifest.start_spawn = &"from_village"
	return manifest

func _boot(manifest_path: String) -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(load(manifest_path) as GameManifest)).override_failure_message(
		"the world would not start %s" % manifest_path).is_true()
	return _world

func test_the_game_that_was_asked_for_is_the_one_running() -> void:
	_boot(QUEST)
	assert_str(String(GameState.current_map)).is_equal("quest_village")
	# Which game is running is state, not just a private field on the world: a save has to
	# name the game it belongs to, and this is where that name comes from.
	assert_str(String(GameState.game)).is_equal("quest")
	_world.start_game(_other_game())
	assert_str(String(GameState.current_map)).is_equal("quest_keep")
	assert_str(String(_world.map_data().id)).is_equal("quest_keep")
	assert_str(String(GameState.game)).override_failure_message(
		"the world still says the previous game is running").is_equal("switched")

func test_the_player_is_rebuilt_with_the_new_games_config() -> void:
	# The sharpest of the four. `if _player == null:` means setup() runs once ever, so without
	# a teardown the newly started game keeps the previous one's character sheet AND its
	# GameConfig - walk speed, body size, interact reach - with nothing anywhere saying so.
	_boot(QUEST)
	# Explicitly typed: _world is a Node2D here, so player() gives back an untyped value and
	# `:=` has nothing to infer from.
	var before: ActorBody = _world.player()
	assert_str(String(before.config.id)).is_equal("default")

	_world.start_game(_other_game())
	assert_bool(is_instance_valid(before)).override_failure_message(
		"the previous player is still alive after the restart").is_false()
	assert_object(_world.player()).is_not_null()
	var after: ActorBody = _world.player()
	assert_str(String(after.config.id)).is_equal("switched")

func test_the_flags_of_the_game_before_do_not_carry_over() -> void:
	# GameState.reset() has existed since M3 with no caller. Starting a game is what it was for:
	# a previous run's flags must not unlock this one's gate, and `seen` is keyed
	# "<map>/<object>", which two runs are free to collide on.
	_boot(QUEST)
	GameState.set_flag(&"carried_over", true)
	GameState.mark_seen("quest_village/village_well")

	_world.start_game(_other_game())
	assert_bool(GameState.has_flag(&"carried_over")).is_false()
	assert_bool(GameState.was_seen("quest_village/village_well")).is_false()

func test_the_rebuilt_dialog_box_is_still_listened_to() -> void:
	# The quietest way this could break. A DialogBox whose `closed` nobody hears leaves Router
	# in DIALOG after the first conversation of the new run and the player never moves again -
	# and the box hides itself, so on screen the conversation looks like it ended normally.
	_boot(QUEST)
	_world.start_game(_other_game())

	Router.open_overlay(Router.State.DIALOG)
	assert_str(Router.state_name()).is_equal("dialog")
	_world.dialog_box().closed.emit([])
	assert_str(Router.state_name()).override_failure_message(
		"closing a conversation in the restarted game did not give control back").is_equal("world")

func test_a_conversations_flags_still_land_after_a_restart() -> void:
	# The same connection, carrying its payload rather than just firing.
	_boot(QUEST)
	_world.start_game(_other_game())
	_world.dialog_box().closed.emit(["promised_after_switch"])
	assert_bool(GameState.has_flag(&"promised_after_switch")).is_true()

func test_starting_back_and_forth_stays_correct() -> void:
	# Teardown has to be safe when something IS built, twice, and leave nothing behind that
	# the next start_game trips over.
	_boot(QUEST)
	_world.start_game(_other_game())
	_world.start_game(load(QUEST) as GameManifest)
	assert_str(String(GameState.current_map)).is_equal("quest_village")
	var back: ActorBody = _world.player()
	assert_str(String(back.config.id)).is_equal("default")
	assert_object(_world.dialog_box()).is_not_null()

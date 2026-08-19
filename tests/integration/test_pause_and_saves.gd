extends GdUnitTestSuite
## Pausing, saving and loading in a running world.
##
## Two things can only be answered here. First, PAUSED has to actually take control away - the
## Router says so, but the player is a physics body driven by a separate loop, and "the state
## changed" is not the same claim as "the character stopped". Second, loading has to put the
## player back where they STOOD, which no spawn describes and no unit test can observe.
##
## Driven through open_pause() and the screen's signals rather than through simulated input:
## gdUnit delivers each simulated event twice on purpose, and this suite is about what the
## world does with an answer, not about how the answer was typed.

const GAME := "res://data/games/quest.tres"
const TEST_DIR := "user://test_saves"

var _world: Node2D

func before_test() -> void:
	GameState.reset()
	Router.reset()
	# Without this the suite writes into the real user://saves/quest/ - a developer's own
	# progress, overwritten by running the tests.
	SaveManager.base_dir = TEST_DIR
	SaveDirs.clear(TEST_DIR)

func after_test() -> void:
	# Polled input is global and outlives the test that pressed it.
	Input.action_release(&"move_right")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	SaveDirs.clear(TEST_DIR)
	SaveManager.base_dir = SaveManager.DEFAULT_DIR
	GameState.reset()
	Router.reset()

## A perfectly good save, built without going through the live state.
func _good_save() -> SaveData:
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_village"
	data.position = MapData.tile_to_world(Vector2i(3, 3), 16)
	data.facing = Dir.D.DOWN
	return data


## Resume, Save, Load: two down and in, then two more down to the third slot. Written out
## rather than looped so the count is a fact about the menu's shape, not a search for a row.
func _to_the_third_slot() -> void:
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	await _press(&"move_down")
	await _press(&"move_down")


func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(load(GAME) as GameManifest)).override_failure_message(
		"the world would not start the game").is_true()
	return _world

## Physics frames, which is the clock the player moves on. The tree's own signal rather than a
## millisecond sleep: under load - a mutation run, say - a 1ms wait spans no physics frame at
## all, and "the player did not move" becomes a property of how busy the machine is.
func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## One real keypress, the way the QA harness delivers them: an InputEventAction through
## parse_input_event, which is what _unhandled_input sees. Most of this suite drives the world
## by signal, but anything about the SCREEN's own input handling - a latch, a guard, a page it
## has to be on - can only be asked through the thing that sets it.
func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(2)
	# Released as well, the way the QA harness does it: an action left held is still held on
	# the next press, and the second one lands on an engine that thinks nothing changed.
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)
	# A load defers its commit by a frame, so a press that asked for one is not finished when
	# the physics frames are.
	await await_idle_frame()
	await _steps(1)

func test_pausing_takes_control_away_and_resuming_gives_it_back() -> void:
	_boot()
	var player: ActorBody = _world.player()
	assert_bool(_world.open_pause()).is_true()
	assert_str(Router.state_name()).is_equal("paused")
	assert_bool(_world.open_pause()).override_failure_message(
		"a second pause built another screen over the first").is_false()

	var held := player.global_position
	Input.action_press(&"move_right")
	await _steps(6)
	assert_vector(player.global_position).override_failure_message(
		"the player kept walking while the game was paused").is_equal(held)

	_world.pause_screen().resumed.emit()
	await _steps(6)
	assert_str(Router.state_name()).is_equal("world")
	# The control: without it, a player frozen by something else entirely would pass above.
	assert_float(player.global_position.x).override_failure_message(
		"the player never started moving again").is_greater(held.x)
	assert_object(_world.pause_screen()).is_null()

func test_saving_from_the_menu_writes_this_games_slot() -> void:
	_boot()
	var player: ActorBody = _world.player()
	var spot := player.global_position + Vector2(32.0, 0.0)
	player.place(spot, Dir.D.RIGHT)
	await _steps(2)

	_world.open_pause()
	_world.pause_screen().save_requested.emit(0)
	assert_bool(SaveManager.has_slot(&"quest", 0)).is_true()

	var written := SaveManager.peek(&"quest", 0)
	assert_object(written).is_not_null()
	assert_str(String(written.game)).is_equal("quest")
	assert_str(String(written.map)).is_equal("quest_village")
	assert_vector(written.position).is_equal_approx(spot, Vector2(1.0, 1.0))
	# Saving is not leaving. The menu stays up so the row shows what was just written.
	assert_object(_world.pause_screen()).override_failure_message(
		"the menu closed itself after a save").is_not_null()

func test_loading_puts_the_player_back_where_they_saved() -> void:
	_boot()
	var player: ActorBody = _world.player()
	var saved_at := player.global_position + Vector2(32.0, 0.0)
	player.place(saved_at, Dir.D.RIGHT)
	await _steps(2)
	_world.open_pause()
	_world.pause_screen().save_requested.emit(0)
	_world.pause_screen().resumed.emit()
	await _steps(2)

	# Walk somewhere else, so landing back on the mark cannot be an accident of never moving.
	var elsewhere := saved_at + Vector2(0.0, 24.0)
	player.place(elsewhere, Dir.D.DOWN)
	await _steps(2)

	_world.open_pause()
	var screen: PauseScreen = _world.pause_screen()
	screen.load_requested.emit(0)
	await await_idle_frame()
	await _steps(4)

	assert_str(Router.state_name()).is_equal("world")
	assert_vector(_world.player().global_position).override_failure_message(
		"the load did not put the player back where the save was made").is_equal_approx(saved_at, Vector2(1.0, 1.0))
	assert_object(_world.pause_screen()).is_null()
	assert_bool(is_instance_valid(screen)).override_failure_message(
		"the pause screen survived the load it asked for").is_false()

func test_a_save_made_in_another_map_restores_into_that_map() -> void:
	# A save records a map as well as a position, and the game has five. Restoring into the one
	# the player is already standing in would pass every position assertion above.
	_boot()
	var data := SaveData.new()
	data.game = &"quest"
	data.map = &"quest_keep"
	data.position = MapData.tile_to_world(Vector2i(4, 4), 16)
	data.facing = Dir.D.DOWN
	assert_bool(SaveManager.save(1, data)).is_true()

	_world.open_pause()
	_world.pause_screen().load_requested.emit(1)
	await await_idle_frame()
	await _steps(4)

	assert_str(String(_world.map_data().id)).is_equal("quest_keep")
	assert_str(String(GameState.current_map)).is_equal("quest_keep")
	assert_str(Router.state_name()).is_equal("world")

func test_another_games_save_is_never_even_offered() -> void:
	# Fail closed at the first opportunity: another game's save sitting in this game's slot
	# read back, so the row says "empty" and Load refuses it. Nothing is parked, because
	# nothing tried to load it - listing the slots is a silent read.
	_boot()
	var stranger := SaveData.new()
	stranger.game = &"other"
	stranger.map = &"quest_village"
	stranger.position = Vector2(64.0, 64.0)
	assert_bool(SaveManager.save(2, stranger)).is_true()
	SaveDirs.write_raw(&"quest", 2, FileAccess.get_file_as_string(SaveManager.slot_path(&"other", 2)))

	assert_bool(_world.open_pause()).is_true()
	await _to_the_third_slot()
	await _press(&"interact")

	assert_str(Router.state_name()).override_failure_message(
		"a save from another game was loaded").is_equal("paused")
	assert_str(String(_world.map_data().id)).is_equal("quest_village")
	assert_bool(FileAccess.file_exists(SaveManager.corrupt_path(&"quest", 2))).override_failure_message(
		"looking at the slot list parked a file").is_false()

func test_a_slot_that_goes_bad_while_the_menu_is_open_is_refused_and_the_menu_lives() -> void:
	# The one way a load can be asked for and come back nothing: the row was readable when the
	# menu drew it and is not by the time the player presses the button. It is also the only
	# case that exercises the screen's latch - it stops answering the moment it sends an answer
	# to the world, so a refusal has to un-latch it, or the menu sits there looking perfectly
	# normal with every key dead and the only way out is killing the game.
	_boot()
	assert_bool(SaveManager.save(2, _good_save())).is_true()

	assert_bool(_world.open_pause()).is_true()
	await _to_the_third_slot()
	# The file changes under the open menu.
	SaveDirs.write_raw(&"quest", 2, "{ truncated half way throu")
	await _press(&"interact")

	assert_str(Router.state_name()).override_failure_message(
		"an unreadable save was loaded anyway").is_equal("paused")
	assert_str(String(_world.map_data().id)).is_equal("quest_village")
	assert_object(_world.pause_screen()).override_failure_message(
		"the menu closed on a load that never happened").is_not_null()
	assert_str(FileAccess.get_file_as_string(SaveManager.corrupt_path(&"quest", 2))).override_failure_message(
		"the unreadable bytes were not preserved").is_equal("{ truncated half way throu")

	# Still answering: escape leaves the slot list, escape again leaves the menu.
	await _press(&"cancel")
	assert_str(Router.state_name()).override_failure_message(
		"the menu went deaf after refusing a load").is_equal("paused")
	await _press(&"cancel")
	assert_str(Router.state_name()).is_equal("world")

func test_starting_another_game_closes_the_pause_menu() -> void:
	# The menu lists ONE game's slots. Left standing over a game that has just been started it
	# would offer to load saves that cannot load, and to write slots belonging to a game nobody
	# is playing.
	_boot()
	_world.open_pause()
	var screen: PauseScreen = _world.pause_screen()
	var other := (load(GAME) as GameManifest).duplicate() as GameManifest
	other.id = &"switched"
	_world.start_game(other)
	assert_bool(is_instance_valid(screen)).override_failure_message(
		"the pause menu outlived the game it was opened over").is_false()
	assert_object(_world.pause_screen()).is_null()
	assert_str(Router.state_name()).is_equal("world")

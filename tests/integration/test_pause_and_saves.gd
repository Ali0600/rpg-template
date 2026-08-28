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


## Resume, Items, Equipment, Save, Load: FOUR down and in, then two more down to the third
## slot. Written out rather than looped so the count is a fact about the menu's shape, not a
## search for a row - and so that inserting a row above Load moves this deliberately rather
## than silently retargeting the whole test at Save, where every press below would write a
## slot. M20 inserted Equipment and this is where that was paid for, on purpose.
func _to_the_third_slot() -> void:
	await _press(&"move_down")
	await _press(&"move_down")
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
	# The game opens with the warden's conversation on screen now. Every test below is about
	# something else, so getting past it belongs here rather than in each of them.
	await _dismiss_opening()
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
	await _boot()
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
	await _boot()
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
	await _boot()
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
	await _boot()
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
	await _boot()
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
	await _boot()
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
	await _boot()
	_world.open_pause()
	var screen: PauseScreen = _world.pause_screen()
	var other := (load(GAME) as GameManifest).duplicate() as GameManifest
	other.id = &"switched"
	_world.start_game(other)
	assert_bool(is_instance_valid(screen)).override_failure_message(
		"the pause menu outlived the game it was opened over").is_false()
	assert_object(_world.pause_screen()).is_null()
	# The new game opens its own story, the way any new game does - so the state to expect
	# here is that one rather than the world, and PAUSED is gone either way.
	assert_str(Router.state_name()).override_failure_message(
		"the pause state survived a game being started under it").is_not_equal("paused")
	await _dismiss_opening()
	assert_str(Router.state_name()).is_equal("world")


func test_the_menu_lists_what_the_player_is_carrying() -> void:
	# Read off the LABELS, not off the menu object: the bag reaching the pure cursor and the
	# bag reaching the screen are different claims, and only the second is what a player sees.
	await _boot()
	GameState.give_item(&"gate_key")
	GameState.give_item(&"lamp_oil", 2)
	assert_bool(_world.open_pause()).is_true()
	await _press(&"move_down")
	await _press(&"interact")

	var drawn: Array[String] = []
	for node in SceneHelpers.find_all_by_class(_world.pause_screen(), "Label"):
		var label := node as Label
		if label.visible:
			drawn.append(label.text)
	var all_text := " | ".join(drawn)
	assert_str(all_text).override_failure_message(
		"the bag was not drawn: %s" % all_text).contains("Gate key")
	# The name comes from the item's own file, and the count from the inventory - so this also
	# says the id was resolved rather than printed raw.
	assert_str(all_text).contains("Lamp oil x2")
	assert_str(all_text).not_contains("gate_key")

## The game now opens with the warden's conversation on screen, so every suite that boots it
## has to get past that before it can test anything else. Bounded and asserted rather than a
## fixed number of presses: the box reveals text a character at a time, so how many presses a
## conversation takes depends on how long its lines are - and a "press until it goes away"
## loop with no cap is how a suite hangs instead of failing.
func _dismiss_opening() -> void:
	for i in 12:
		if Router.state_name() != "dialog":
			return
		await _press(&"interact")
	fail("the opening conversation would not close")


func test_the_sound_row_is_drawn_with_the_current_setting_on_it() -> void:
	# Asserted on the RENDERED text, not on the menu's answer. The menu returning the right
	# label proves nothing about the screen putting it on screen: the row could draw the
	# static blank that sits in its place in the label table, which renders as an empty line
	# and reads as a menu that failed to draw.
	await _boot()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	var drawn := _drawn_rows()
	assert_array(drawn).override_failure_message("the pause screen drew nothing").is_not_empty()
	var found := ""
	for text in drawn:
		if text.contains("Sound"):
			found = text
	assert_str(found).override_failure_message(
		"no row said anything about sound; the screen drew %s" % [drawn]).is_not_empty()
	assert_str(found).override_failure_message(
		"the sound row does not say what the setting IS: '%s'" % found).contains(":")


## Every non-empty label the pause screen is currently showing.
func _drawn_rows() -> Array[String]:
	var out: Array[String] = []
	for child in _world.pause_screen().get_children():
		var label := child as Label
		if label != null and label.visible and not label.text.strip_edges().is_empty():
			out.append(label.text)
	return out


func test_the_equipment_row_is_drawn_on_the_menu() -> void:
	# On the RENDERED text, the sound row's rule: a row's label lives in a table the view
	# indexes by the enum, so a row inserted in one and not the other draws as a blank line
	# and pushes every label below it onto the wrong row.
	await _boot()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	var drawn := _drawn_rows()
	var found := ""
	for text in drawn:
		if text.contains("Equipment"):
			found = text
	assert_str(found).override_failure_message(
		"no row offered equipment; the screen drew %s" % [drawn]).is_not_empty()


func test_the_slot_page_draws_a_row_for_every_slot() -> void:
	# The page is built from the template's own vocabulary rather than from what the player
	# happens to be carrying, so an empty slot is a row that says so.
	await _boot()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	var drawn := _drawn_rows()
	var slots := 0
	for text in drawn:
		if text.contains("Weapon:") or text.contains("Armor:"):
			slots += 1
	assert_int(slots).override_failure_message(
		"the slot list drew %d of 2 rows: %s" % [slots, drawn]).is_equal(2)

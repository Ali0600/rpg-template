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
	data.tile = Vector2(3.5, 3.5)
	data.facing = Dir.D.DOWN
	return data


## Resume, Items, Equipment, Status, Save, Load: FIVE down and in, then two more down to the
## third slot. Written out rather than looped so the count is a fact about the menu's shape,
## not a search for a row - and so that inserting a row above Load moves this deliberately
## rather than silently retargeting the whole test at Save, where every press below would
## write a slot. M20 inserted Equipment and then Status, and this is where both were paid
## for, on purpose.
func _to_the_third_slot() -> void:
	await _press(&"move_down")
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

	var written := SaveManager.peek(&"quest", 0).data
	assert_object(written).is_not_null()
	assert_str(String(written.game)).is_equal("quest")
	assert_str(String(written.map)).is_equal("quest_village")
	assert_vector(written.tile).is_equal_approx(spot / float(GameState.tile_size), Vector2(0.1, 0.1))
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
	data.tile = Vector2(4.5, 4.5)
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
	stranger.tile = Vector2(4.0, 4.0)
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


func test_the_equipment_page_draws_what_the_numbers_are() -> void:
	# The readout is the whole reason a preview is a preview: "Atk +3" against nothing is a
	# number, and against "Atk 5+0" it is a decision. Asserted on the RENDERED label, because
	# the world composing the string proves nothing about the screen showing it - and the
	# mutation harness found exactly that hole, with the world's wording fully tested.
	await _boot()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	var on_top := _drawn_rows()
	for text in on_top:
		assert_str(text).override_failure_message(
			"the stats readout is drawn on the top page, where it means nothing") \
			.not_contains("Atk")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	var found := ""
	for text in _drawn_rows():
		if text.contains("Atk"):
			found = text
	assert_str(found).override_failure_message(
		"the equipment page says nothing about the player's numbers; it drew %s"
		% [_drawn_rows()]).is_not_empty()
	assert_str(found).override_failure_message(
		"the readout does not separate the gear from the level: '%s'" % found).contains("+")


func test_the_status_page_is_drawn_with_the_players_numbers_on_it() -> void:
	# On the RENDERED text: the world composing a line proves nothing about the screen showing
	# it, which is exactly the hole the mutation harness found in the equipment readout.
	await _boot()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	var drawn := _drawn_rows()
	var found := ""
	for text in drawn:
		if text.contains("Level"):
			found = text
	assert_str(found).override_failure_message(
		"the status page says nothing about the player; it drew %s" % [drawn]).is_not_empty()
	var hp := ""
	for text in drawn:
		if text.contains("HP "):
			hp = text
	assert_str(hp).override_failure_message(
		"nothing on the page says how hurt the player is; it drew %s" % [drawn]).is_not_empty()


# --- the save point -------------------------------------------------------------------------

func test_a_save_point_opens_over_the_world_after_the_conversation_ends() -> void:
	# The DEFERRAL, which is the whole reason the effect exists rather than a direct call:
	# _on_dialog_closed applies effects and THEN pops the dialog overlay, so a screen opened
	# inline is the one that pop closes. Driven through _apply_effects for that reason - an
	# open_save() call here would pass either way.
	await _boot()
	_world._apply_effects([{"op": GameContext.OP_SAVE}])
	await _steps(2)
	assert_object(_world.save_screen()).override_failure_message(
		"the save point never opened, or opened and was closed by the dialog's own pop"
		).is_not_null()
	assert_str(Router.state_name()).is_equal("saving")
	# An overlay like every other: the world is still behind it and the player cannot walk out.
	assert_bool(Router.player_can_move()).is_false()

func test_a_save_point_writes_the_slot_it_was_pointed_at() -> void:
	# The outcome store, not the screen's own report: what makes a save a save is a file on
	# disk that reads back, which is the one thing a signal cannot prove.
	await _boot()
	var player: ActorBody = _world.player()
	var spot := player.global_position + Vector2(16.0, 0.0)
	player.place(spot)
	_world._apply_effects([{"op": GameContext.OP_SAVE}])
	await _steps(2)
	assert_bool(SaveManager.has_slot(&"quest", 1)).override_failure_message(
		"slot 1 already held a save before this test wrote one").is_false()

	var screen: SaveScreen = _world.save_screen()
	await _press(&"move_down")
	await _press(&"interact")
	assert_bool(SaveManager.has_slot(&"quest", 1)).override_failure_message(
		"the save point reported a write that reached no file").is_true()
	var read := SaveManager.load_slot(&"quest", 1)
	assert_object(read).is_not_null()
	assert_vector(read.tile).override_failure_message(
		"the save point wrote a save of somewhere the player was not standing"
		).is_equal(spot / float(GameState.tile_size))
	# It STAYS open and the row now says what it holds - the pause menu's rule for the same
	# press, and what stops a save reading as a press the game swallowed.
	assert_object(_world.save_screen()).override_failure_message(
		"the save point closed itself on a write").is_not_null()
	assert_bool(screen.menu().summary(1).has_save()).override_failure_message(
		"the row the player is looking at still says the slot is empty").is_true()

func test_a_save_point_writes_nothing_on_the_way_out() -> void:
	# Cancel is a whole verb here: a save point a player walked into and thought better of must
	# leave the disk alone, and "no file appeared" is the only assertion that says so.
	await _boot()
	_world._apply_effects([{"op": GameContext.OP_SAVE}])
	await _steps(2)
	await _press(&"cancel")
	assert_object(_world.save_screen()).override_failure_message(
		"the save point would not close").is_null()
	assert_str(Router.state_name()).is_equal("world")
	for slot in 3:
		assert_bool(SaveManager.has_slot(&"quest", slot)).override_failure_message(
			"leaving a save point wrote slot %d anyway" % slot).is_false()

func test_a_save_point_survives_the_dialog_close_that_asked_for_it() -> void:
	# THE deferral, staged the way production reaches it and the only way that can tell a
	# deferred open from an inline one. _on_dialog_closed applies the effects and THEN pops the
	# dialog's overlay: opened inline, the save screen pushes SAVING over DIALOG and that pop
	# takes it straight back off - the state lands on `dialog`, the screen is orphaned behind a
	# closed conversation, and nothing errors. The suite's other save-point tests all pass
	# either way, because none of them has a dialog open to be popped.
	await _boot()
	assert_bool(_world._open_dialog(&"elder")).is_true()
	await _steps(1)
	assert_str(Router.state_name()).is_equal("dialog")
	_world._on_dialog_closed([{"op": GameContext.OP_SAVE}])
	await _steps(3)
	assert_str(Router.state_name()).override_failure_message(
		"asking for a save point from a conversation left the machine in '%s'"
		% Router.state_name()).is_equal("saving")
	assert_object(_world.save_screen()).is_not_null()
	# And the conversation it came from is gone, rather than waiting underneath.
	assert_int(Router.overlay_depth()).override_failure_message(
		"the dialog is still on the stack under the save point").is_equal(1)

## The shipped game with its save policy changed, and NOTHING else. A duplicate rather than a
## second .tres, the flow model's `_manifest()` precedent: a fixture game that varied anything
## more than the one field under test would make every difference a suspected defect.
func _at_point_manifest() -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	var config := manifest.config.duplicate() as GameConfig
	config.save_policy = GameConfig.SAVE_AT_POINT
	manifest.config = config
	return manifest

func _boot_at_point() -> void:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(_at_point_manifest())).is_true()
	await _dismiss_opening()

func test_a_save_at_point_game_draws_no_save_row_on_its_pause_menu() -> void:
	# On the RENDERED text, the sound row's rule and for its reason: the menu answering
	# correctly proves nothing about the screen, whose labels live in a table indexed by the
	# enum - so a row hidden in one and not the other draws "Save" over the row that now
	# answers Load, and every press below it lands one row out.
	await _boot_at_point()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	var drawn := _drawn_rows()
	for text in drawn:
		# The cursor prefix comes off first. Every row is drawn as "> Label" or "  Label", so
		# a begins_with("Save") here can never be true and the assertion would be decoration -
		# which is exactly what the first draft of this test was, and what the fail-first run
		# caught by surviving the sabotage it was written to kill.
		assert_str(text.strip_edges().trim_prefix(">").strip_edges()).override_failure_message(
			"a save-at-point game drew a Save row: %s" % [drawn]).is_not_equal("Save")
	# The control, and the half "no Save row" cannot see: everything else is still there, so a
	# menu that simply failed to draw would not pass this.
	var joined := " | ".join(drawn)
	for expected in ["Resume", "Items", "Equipment", "Status", "Load"]:
		assert_str(joined).override_failure_message(
			"hiding Save also took '%s' with it: %s" % [expected, drawn]).contains(expected)

func test_the_shipped_game_still_draws_its_save_row() -> void:
	# The other direction, on the same surface. Without it, a screen that drew no rows at all
	# would pass the test above - and the shipped game is the one every recorded session plays.
	await _boot()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	assert_str(" | ".join(_drawn_rows())).contains("Save")

func test_a_save_at_point_game_can_still_save_at_a_point() -> void:
	# The axis is about WHERE, not whether. A policy that removed the row and left no way to
	# write a save would pass every assertion above and be unplayable.
	await _boot_at_point()
	_world._apply_effects([{"op": GameContext.OP_SAVE}])
	await _steps(2)
	assert_object(_world.save_screen()).is_not_null()
	await _press(&"interact")
	assert_bool(SaveManager.has_slot(&"quest", 0)).override_failure_message(
		"a save-at-point game could not write a save at its save point").is_true()

func test_a_save_at_point_game_can_still_load() -> void:
	# The policy governs WRITING only. Loading stays a menu verb under both, so the Load row has
	# to survive - and a hidden-row bug that took its neighbour with it would land here.
	#
	# Driven by real keys, through the front door, because the claim is about which row the
	# CURSOR reaches: the menu's own answer is already pinned in test_pause_menu, and this is
	# the layer where the screen's labels and the menu's mapping have to agree.
	#
	# Resume, Items, Equipment, Status, Load, Sound - FOUR down lands on Load, because this
	# game has no Save row between Status and it. That count is written out rather than looped
	# for the reason _to_the_third_slot's is: inserting a row moves it deliberately.
	await _boot_at_point()
	assert_bool(SaveManager.save(0, _good_save())).is_true()
	assert_bool(_world.open_pause()).is_true()
	await _steps(2)
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"move_down")
	await _press(&"interact")
	await _press(&"interact")
	# The save carries no flags, so arriving in the village greets the player exactly as a
	# first visit does - the quest's content firing correctly, not the load misbehaving.
	await _dismiss_opening()
	assert_str(Router.state_name()).override_failure_message(
		"loading from a save-at-point menu left the machine in '%s'"
		% Router.state_name()).is_equal("world")
	assert_vector(_world.player().global_position).override_failure_message(
		"the load did not put the player where the save said").is_equal_approx(
		MapData.tile_to_world(Vector2i(3, 3), 16), Vector2(1.0, 1.0))

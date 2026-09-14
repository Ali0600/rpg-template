extends GdUnitTestSuite
## The title's Switch game row, against the real world node.
##
## Two games are offered from memory - duplicates of the shipped one with their own id, name and
## theme - through offer_games, the start_game seam's reason: a second manifest in data/ purely so a
## suite could switch to it would be content nobody plays. What is proven is the whole of the switch
## a player sees: the row is there exactly when there is somewhere to go, a press brings up the next
## game's own name, music and saves with the cursor still on the row, and New game after a switch
## starts the game that was showing.

const GAME := "res://data/games/quest.tres"
const TEST_DIR := "user://test_saves"

var _world: Node2D


func before_test() -> void:
	GameState.reset()
	Router.reset()
	SaveManager.base_dir = TEST_DIR
	SaveDirs.clear(TEST_DIR)


func after_test() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	SaveDirs.clear(TEST_DIR)
	SaveManager.base_dir = SaveManager.dir_for(GameSelect.args())
	GameState.reset()
	Router.reset()


func _game(id: StringName, title: String, music: StringName) -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	manifest.id = id
	manifest.title = title
	manifest.title_music = music
	return manifest


func _two() -> Array[GameManifest]:
	var games: Array[GameManifest] = [_game(&"quest", "Road A", &"barred_gate"),
		_game(&"quest_b", "Road B", &"vigil")]
	return games


func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## A real press and release, with an IDLE frame after each: a parsed event is delivered when the
## engine next flushes input, which is once a process frame, and several physics frames can pass
## inside one process frame on a headless run. Waiting on physics frames alone let a second press
## arrive a frame after the assertion that was waiting for it.
func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(2)
	await await_idle_frame()
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)
	await await_idle_frame()
	await _steps(1)


func _title() -> TitleScreen:
	return _world.title_screen() as TitleScreen


func test_the_switch_row_is_there_exactly_when_there_is_another_game() -> void:
	_boot()
	assert_bool(_world.offer_games(_two())).is_true()
	assert_int(_title().menu().row_count()).override_failure_message(
		"two games offered, and the title has no Switch game row").is_equal(TitleMenu.ROW_GAME + 1)
	assert_str(_title()._heading.text).is_equal("Road A")
	var one: Array[GameManifest] = [_game(&"quest", "Road A", &"barred_gate")]
	assert_bool(_world.offer_games(one)).is_true()
	assert_int(_title().menu().row_count()).override_failure_message(
		"one game offered, and the title offers to switch anyway").is_equal(TitleMenu.ROW_OPTIONS + 1)

func test_pressing_switch_game_brings_up_the_next_game_and_back_again() -> void:
	_boot()
	_world.offer_games(_two())
	var first := _title()
	# Reached by asking the menu where the cursor is rather than by counting presses, and pressed
	# through the real key.
	for i in first.menu().row_count():
		if first.menu().index() == TitleMenu.ROW_GAME:
			break
		first.menu().move(1)
	assert_int(first.menu().index()).is_equal(TitleMenu.ROW_GAME)
	await _press(&"interact")
	var second := _title()
	assert_object(second).override_failure_message(
		"Switch game was pressed and the same title stayed up").is_not_same(first)
	assert_str(second._heading.text).is_equal("Road B")
	assert_str(String(AudioBus.music_id())).is_equal("vigil")
	assert_int(second.menu().index()).override_failure_message(
		"the cursor left the row that switched").is_equal(TitleMenu.ROW_GAME)
	await _press(&"interact")
	var third := _title()
	assert_object(third).override_failure_message(
		"the second press of Switch game did not rebuild the title").is_not_same(second)
	assert_str(third._heading.text).override_failure_message(
		"switching twice with two games did not come back to the first: the title says '%s'"
		% third._heading.text).is_equal("Road A")

func test_the_title_reads_the_saves_of_the_game_that_is_showing() -> void:
	_boot()
	var data := SaveData.new()
	data.game = &"quest_b"
	data.map = &"quest_town"
	data.tile = Vector2(4.5, 6.5)
	data.facing = Dir.D.DOWN
	data.party = {"hp": 7, "xp": 30, "level": 2}
	assert_bool(SaveManager.save(0, data)).is_true()
	_world.offer_games(_two())
	assert_str(_title().menu().top_label(TitleMenu.Row.CONTINUE)).is_equal("Continue (nothing saved)")
	_world._commit_switch_game()
	await _steps(1)
	assert_str(_title().menu().top_label(TitleMenu.Row.CONTINUE)).override_failure_message(
		"Road B has a save and its title says nothing is saved").is_equal("Continue")

func test_new_game_after_a_switch_starts_the_game_that_was_showing() -> void:
	_boot()
	_world.offer_games(_two())
	_world._commit_switch_game()
	await _steps(1)
	_world._commit_new_game_from_title()
	await _steps(1)
	assert_str(String(GameState.game)).is_equal("quest_b")

func test_with_one_game_the_switch_changes_nothing() -> void:
	_boot()
	var one: Array[GameManifest] = [_game(&"quest", "Road A", &"barred_gate")]
	_world.offer_games(one)
	var screen := _title()
	_world._commit_switch_game()
	await _steps(1)
	assert_object(_title()).override_failure_message(
		"a build with one game rebuilt its title to switch to itself").is_same(screen)

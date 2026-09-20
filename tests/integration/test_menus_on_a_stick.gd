extends GdUnitTestSuite
## A menu cursor driven by a real stick, through the input map, the way a pad delivers it.
##
## Every suite that drives a menu presses an InputEventAction, which names the action and skips
## the map, so nothing here had ever seen what a joypad motion event does to a cursor: it matches
## an action by AXIS alone, so a push UP took the move_down branch, and a held stick sends one
## event per value change, so a wobble walked the cursor down the list. Both are engine facts
## test_engine_assumptions pins; this is the screen reading them right.
##
## It boots the fixture yard for test_options_palette's reason: the shipped maps are content.

const GAME := "res://data/games/quest.tres"
const FIXTURE_MAPS := "res://tests/fixtures/maps"

var _world: Node2D


func before_test() -> void:
	GameState.reset()
	Router.reset()


func after_test() -> void:
	_stick(0.0)
	_stick(0.0, JOY_AXIS_LEFT_X)
	await _steps(1)
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	MapData.root = MapData.MAP_DIR
	GameState.reset()
	Router.reset()


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _manifest() -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	manifest.start_map = &"lpc32_yard"
	manifest.start_spawn = &"start"
	manifest.party = []
	manifest.hooks = null
	return manifest


## The fixture root is moved AFTER instantiating, never before - _ready boots the shipped game and
## would hunt for its start map in the fixture directory, leaving a half-built map behind.
func _boot() -> Node2D:
	MapData.root = MapData.MAP_DIR
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	MapData.root = FIXTURE_MAPS
	assert_bool(_world.start_game(_manifest())).is_true()
	await _steps(1)
	return _world


## One real motion event through the input map, the way the pad delivers it.
func _stick(value: float, axis: JoyAxis = JOY_AXIS_LEFT_Y) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _dpad(button: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


func _pause_menu() -> PauseMenu:
	var screen: PauseScreen = _world.pause_screen()
	assert_object(screen).is_not_null()
	return screen._menu


func test_a_stick_pushed_up_moves_the_pause_cursor_up_once() -> void:
	var world := await _boot()
	assert_bool(world.open_pause()).is_true()
	await _steps(1)
	var menu := _pause_menu()
	assert_int(menu.index()).is_equal(0)
	_stick(-1.0)
	await _steps(2)
	# Up from the top row wraps onto the last one - the one deliberate press CLAUDE.md prefers.
	assert_int(menu.index()).override_failure_message(
		"a stick pushed UP moved the cursor to row %d, not to the last row (%d)" % [
			menu.index(), menu.size() - 1]).is_equal(menu.size() - 1)


func test_a_held_stick_moves_the_cursor_one_row_not_one_per_event() -> void:
	var world := await _boot()
	assert_bool(world.open_pause()).is_true()
	await _steps(1)
	var menu := _pause_menu()
	for value in [0.6, 0.8, 1.0]:
		_stick(float(value))
		await _steps(1)
	assert_int(menu.index()).override_failure_message(
		"three motion events of one held push moved the cursor %d rows" % menu.index()).is_equal(1)
	_stick(0.0)
	await _steps(1)
	_stick(1.0)
	await _steps(2)
	assert_int(menu.index()).override_failure_message(
		"a second push after letting go did not count").is_equal(2)


func test_the_d_pad_moves_the_cursor_one_row() -> void:
	var world := await _boot()
	assert_bool(world.open_pause()).is_true()
	await _steps(1)
	var menu := _pause_menu()
	_dpad(JOY_BUTTON_DPAD_DOWN, true)
	await _steps(1)
	_dpad(JOY_BUTTON_DPAD_DOWN, false)
	await _steps(1)
	assert_int(menu.index()).is_equal(1)

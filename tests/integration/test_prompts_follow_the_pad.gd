extends GdUnitTestSuite
## Every word on screen follows the device in the player's hands, and it is asserted as
## MEMBERSHIP over whatever layers are up - never a list of the screens that need it.
##
## The recolour's own lesson: it shipped as a list, and the title was not on it. So this opens
## screens, makes a real pad speak through the input map, and reads every visible Label on every
## CanvasLayer for a keyboard tell-word - "WASD", "W/S", "Esc" - and then the reverse for the pad's.
## Single letters are not tells: "A" and "E" are in every sentence.
##
## It boots the fixture yard for test_options_palette's reason: the shipped maps are content.

const GAME := "res://data/games/quest.tres"
const FIXTURE_MAPS := "res://tests/fixtures/maps"
const KEYBOARD_TELLS := ["WASD", "W/S", "Esc"]
const PAD_TELLS := ["Stick", "D-pad", "Menu"]

var _world: Node2D


func before_test() -> void:
	GameState.reset()
	Router.reset()


func after_test() -> void:
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


func _instantiate() -> Node2D:
	MapData.root = MapData.MAP_DIR
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world


## The fixture root is moved AFTER instantiating, never before - _ready boots the shipped game and
## would hunt for its start map in the fixture directory, leaving a half-built map behind.
func _boot() -> Node2D:
	_instantiate()
	MapData.root = FIXTURE_MAPS
	assert_bool(_world.start_game(_manifest())).is_true()
	await _steps(1)
	return _world


## A real pad button through the input map, pressed and released, the way a pad delivers it.
func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)
		await _steps(1)


## A real key through the input map: W by position, which is move_up.
func _key() -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = KEY_W
		e.pressed = down
		Input.parse_input_event(e)
		await _steps(1)


## Every Label a player could be reading right now: visible, on a CanvasLayer of the world.
func _visible_lines(world: Node2D) -> Array[String]:
	var out: Array[String] = []
	for child in world.get_children():
		var layer := child as CanvasLayer
		if layer == null:
			continue
		for node in SceneHelpers.find_all_by_class(layer, "Label"):
			var label := node as Label
			if label.is_visible_in_tree() and not label.text.is_empty():
				out.append(label.text)
	return out


func _assert_words(world: Node2D, forbidden: Array, expected: Array, where: String) -> void:
	var lines := _visible_lines(world)
	assert_int(lines.size()).override_failure_message("nothing is drawn %s" % where).is_greater(0)
	var tells := 0
	for line in lines:
		for word: String in forbidden:
			assert_bool(line.contains(word)).override_failure_message(
				"%s: '%s' still says '%s'" % [where, line, word]).is_false()
		for word: String in expected:
			if line.contains(word):
				tells += 1
	assert_int(tells).override_failure_message(
		"%s: no line names %s, so nothing here proved a word changed - drawn: %s" % [
			where, expected, lines]).is_greater(0)


func test_every_layer_up_when_the_pad_speaks_is_reworded_and_the_press_still_lands() -> void:
	var world := await _boot()
	assert_that(world._device).is_equal(Prompts.Device.KEYBOARD)
	assert_bool(world.open_pause()).is_true()
	await _steps(1)
	_assert_words(world, PAD_TELLS, KEYBOARD_TELLS, "at boot, over the pause menu")
	# D-pad DOWN: a button the pause menu READS, so the same press that rewords the screen has
	# to move its cursor - which is what proves _input consumed nothing and touched no gate.
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_that(world._device).is_equal(Prompts.Device.PAD)
	assert_int(world.pause_screen()._menu.index()).override_failure_message(
		"the pad press that reworded the screen never reached it").is_equal(1)
	_assert_words(world, KEYBOARD_TELLS, PAD_TELLS, "after the pad spoke")
	assert_str(world.controls_hint().text()).override_failure_message(
		"the hint was not reworded: '%s'" % world.controls_hint().text()).contains("Stick")
	await _key()
	assert_that(world._device).is_equal(Prompts.Device.KEYBOARD)
	_assert_words(world, PAD_TELLS, KEYBOARD_TELLS, "after the keyboard spoke again")
	assert_str(world.controls_hint().text()).contains("WASD")


func test_a_screen_opened_after_the_switch_opens_in_the_pads_words() -> void:
	# A screen built after the device changed is handed the device at mount, with no call site
	# per screen anywhere in the world - the same opener list test_world_scale walks.
	var world := await _boot()
	await _pad(JOY_BUTTON_X)  # bound to nothing: it speaks, and nothing hears it
	assert_that(world._device).is_equal(Prompts.Device.PAD)
	var opened := 0
	for opener: Callable in [
		func() -> bool: return world.open_pause(),
		func() -> bool: return world.open_save(),
		func() -> bool: return world.open_shop(&"smith_shop"),
		func() -> bool: return world.open_game_over(),
		func() -> bool: return world.open_options(true),
	]:
		assert_bool(opener.call()).is_true()
		await _steps(1)
		opened += 1
		_assert_words(world, KEYBOARD_TELLS, PAD_TELLS, "screen %d opened after the switch" % opened)
	assert_int(opened).is_greater(3)


func test_over_the_title_too() -> void:
	var world := _instantiate()
	await _steps(1)
	_assert_words(world, PAD_TELLS, KEYBOARD_TELLS, "over the title at boot")
	await _pad(JOY_BUTTON_X)
	_assert_words(world, KEYBOARD_TELLS, PAD_TELLS, "over the title after the pad spoke")
	assert_bool(world.open_options()).is_true()
	await _steps(1)
	_assert_words(world, KEYBOARD_TELLS, PAD_TELLS, "options opened over the title")


func test_a_harness_action_does_not_move_the_device() -> void:
	# The scripted sessions press actions, which name no device: a session that flipped every
	# word to the keyboard's on its first press could never show the pad's.
	var world := await _boot()
	await _pad(JOY_BUTTON_X)
	assert_that(world._device).is_equal(Prompts.Device.PAD)
	for down in [true, false]:
		var e := InputEventAction.new()
		e.action = &"interact"
		e.pressed = down
		Input.parse_input_event(e)
		await _steps(1)
	assert_that(world._device).is_equal(Prompts.Device.PAD)


func test_a_stick_inside_the_deadzone_says_nothing_and_past_it_speaks() -> void:
	var world := await _boot()
	for value in [0.1, 0.0]:
		var drift := InputEventJoypadMotion.new()
		drift.axis = JOY_AXIS_LEFT_X
		drift.axis_value = float(value)
		Input.parse_input_event(drift)
		await _steps(1)
	assert_that(world._device).override_failure_message(
		"a resting stick's drift flipped every word to the pad's").is_equal(Prompts.Device.KEYBOARD)
	for value in [0.8, 0.0]:
		var push := InputEventJoypadMotion.new()
		push.axis = JOY_AXIS_LEFT_X
		push.axis_value = float(value)
		Input.parse_input_event(push)
		await _steps(1)
	assert_that(world._device).is_equal(Prompts.Device.PAD)


func test_recolouring_does_not_lose_the_pads_words() -> void:
	# A recolour rebuilds the title and the options page; a rebuilt screen reads the device
	# the world holds, not a default.
	var world := await _boot()
	await _pad(JOY_BUTTON_X)
	assert_bool(world.open_pause()).is_true()
	await _steps(1)
	world._rebind_style()
	await _steps(1)
	_assert_words(world, KEYBOARD_TELLS, PAD_TELLS, "after a recolour")

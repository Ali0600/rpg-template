extends GdUnitTestSuite
## The words a help line prints for a device, and the map they are claims about.
##
## The binding gate is the reason this suite exists: a word on screen says "this key does this",
## and tools/setup_input_map.gd - the file that wrote the map - can never be run again (it
## strips every comment from project.godot). So Prompts.STANDS_FOR names, for every word, the
## event it stands for, and this holds each row against InputMap. A pad word that stands for an
## event no pad can send fails here by name; so does a joypad binding written for one pad.

const UI_DIR := "res://scripts/ui"


func _events(action: StringName) -> Array[InputEvent]:
	assert_bool(InputMap.has_action(action)).override_failure_message(
		"no action '%s' in the map" % action).is_true()
	return InputMap.action_get_events(action)


func _bound(row: Array) -> bool:
	var action: StringName = row[0]
	for event in _events(action):
		match int(row[1]):
			Prompts.Bind.KEY:
				var key := event as InputEventKey
				if key != null and key.physical_keycode == int(row[2]):
					return true
			Prompts.Bind.BUTTON:
				var button := event as InputEventJoypadButton
				if button != null and button.button_index == int(row[2]):
					return true
			Prompts.Bind.AXIS:
				var motion := event as InputEventJoypadMotion
				if motion != null and motion.axis == int(row[2]) \
						and signf(motion.axis_value) == float(row[3]):
					return true
	return false


func test_every_word_is_bound_where_it_says_on_the_map() -> void:
	var faults: Array[String] = []
	for device: Prompts.Device in Prompts.WORDS:
		for verb: Prompts.Verb in Prompts.WORDS[device]:
			var word := Prompts.word(verb, device)
			for row: Array in Prompts.STANDS_FOR[word]:
				if not _bound(row):
					faults.append("'%s' (%s) says %s does something, and the map does not bind it" % [
						word, Prompts.Device.keys()[device], row[0]])
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()


func test_every_joypad_binding_answers_any_pad() -> void:
	# InputMap::_find_event fires a stored event only for its own device index or for -1: the
	# map shipped with 0 on every pad line, and one pad at index 0 could never show it.
	var faults: Array[String] = []
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			if (event is InputEventJoypadButton or event is InputEventJoypadMotion) \
					and event.device != Prompts.ANY_PAD:
				faults.append("%s: a pad binding written for pad %d alone" % [action, event.device])
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()


func test_every_verb_has_a_word_on_every_device_and_every_word_stands_for_something() -> void:
	for device: Prompts.Device in Prompts.Device.values():
		for verb: Prompts.Verb in Prompts.Verb.values():
			var word := Prompts.word(verb, device)
			assert_str(word).is_not_empty()
			assert_bool(Prompts.STANDS_FOR.has(word)).override_failure_message(
				"'%s' stands for nothing in the map" % word).is_true()
			assert_int(Prompts.STANDS_FOR[word].size()).is_greater(0)


func test_every_button_a_session_can_name_is_bound_to_something() -> void:
	# The harness's half of the table: a session presses these through the map, so a button
	# nothing hears is a step that silently does nothing.
	for name: String in Prompts.BUTTONS:
		var heard := false
		for action in InputMap.get_actions():
			for event in InputMap.action_get_events(action):
				var button := event as InputEventJoypadButton
				if button != null and button.button_index == int(Prompts.BUTTONS[name]):
					heard = true
		assert_bool(heard).override_failure_message(
			"the pad's '%s' is bound to no action" % name).is_true()


func test_the_keyboard_lines_are_the_ones_that_shipped() -> void:
	# The byte-identical claim: every keyboard help line reads exactly as it did before there
	# were tokens, so no layout audit and no session sees a change on a keyboard.
	var k := Prompts.Device.KEYBOARD
	assert_str(Prompts.fill("{choose} to choose    {confirm} to pick    {back} to resume", k)) \
		.is_equal("W/S to choose    E to pick    Esc to resume")
	assert_str(Prompts.fill("{move} to move    {confirm} to swing", k)).is_equal("WASD to move    E to swing")
	assert_str(Prompts.fill("{choose} to choose    {confirm} to take    {back} to go back", k)) \
		.is_equal("W/S to choose    E to take    Esc to go back")
	assert_str(Prompts.fill("{confirm}: change    {back}: back", k)).is_equal("E: change    Esc: back")
	assert_str(Prompts.fill("{confirm} on the !", k)).is_equal("E on the !")


func test_the_pad_lines_name_the_pads_own_letters() -> void:
	var p := Prompts.Device.PAD
	assert_str(Prompts.fill("{choose} to choose    {confirm} to pick    {back} to resume", p)) \
		.is_equal("D-pad to choose    A to pick    B to resume")
	assert_str(Prompts.fill("{move} to walk    {confirm} to look    {pause} to pause", p)) \
		.is_equal("Stick to walk    A to look    Menu to pause")


func test_an_unknown_token_is_left_as_typed_and_named() -> void:
	var line := "{confirm} to {frobnicate} the {thing}"
	assert_str(Prompts.fill(line, Prompts.Device.PAD)).is_equal("A to {frobnicate} the {thing}")
	assert_array(Prompts.unknown_tokens(line)).contains_exactly(["frobnicate", "thing"])
	assert_array(Prompts.tokens_of(line)).contains_exactly(["confirm", "frobnicate", "thing"])


func test_a_template_with_no_token_names_none() -> void:
	assert_array(Prompts.tokens_of("WASD to walk")).is_empty()
	assert_array(Prompts.unknown_tokens("")).is_empty()
	assert_str(Prompts.fill("plain words", Prompts.Device.PAD)).is_equal("plain words")


func _motion(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = value
	return e


func test_a_key_says_keyboard_a_button_says_pad_and_a_stick_only_past_the_deadzone() -> void:
	var key := InputEventKey.new()
	assert_bool(Prompts.speaks(key, 0.2)).is_true()
	assert_that(Prompts.device_of(key)).is_equal(Prompts.Device.KEYBOARD)
	var button := InputEventJoypadButton.new()
	assert_bool(Prompts.speaks(button, 0.2)).is_true()
	assert_that(Prompts.device_of(button)).is_equal(Prompts.Device.PAD)
	assert_bool(Prompts.speaks(_motion(0.1), 0.2)).override_failure_message(
		"a resting stick's drift counted as the pad speaking").is_false()
	assert_bool(Prompts.speaks(_motion(-0.5), 0.2)).is_true()
	assert_that(Prompts.device_of(_motion(-0.5))).is_equal(Prompts.Device.PAD)


func test_a_harness_action_and_the_mouse_say_nothing() -> void:
	var action := InputEventAction.new()
	action.action = &"interact"
	action.pressed = true
	assert_bool(Prompts.speaks(action, 0.2)).override_failure_message(
		"a scripted press counted as a device - every session would flip to the keyboard's words").is_false()
	assert_bool(Prompts.speaks(InputEventMouseButton.new(), 0.2)).is_false()


func test_every_screen_reads_its_cursor_through_the_gate() -> void:
	# A stick matches an action by AXIS through is_action(), so a cursor read that way sends an
	# up-push down. InputGate.pressed is the one reading, and this is what keeps the next screen
	# on it. The sprite lab is a dev scene and reads raw actions on purpose.
	var faults: Array[String] = []
	var files := ContentScan.files(UI_DIR, ["gd"])
	assert_int(files.size()).is_greater(5)
	for path in files:
		if path.ends_with("sprite_lab.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		var line_no := 0
		for line in text.split("\n"):
			line_no += 1
			if line.contains("is_action(&\"move_") or line.contains("is_action_pressed(&\"move_"):
				faults.append("%s:%d reads a cursor past the gate: %s" % [path, line_no, line.strip_edges()])
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()

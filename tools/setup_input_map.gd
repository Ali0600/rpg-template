extends SceneTree
## Writes the project's input actions into project.godot.
##
## Authoring these by script instead of by hand means no keycode integers are ever typed
## from memory, and this file doubles as the readable spec for the control scheme. It is
## also a hard requirement for the scene tests: gdUnit4's
## `simulate_action_press("move_right")` can only press an action that exists in
## project.godot, so the map is committed, not generated at boot.
##
## Re-run after changing bindings:
##
##     Godot --headless --path . -s tools/setup_input_map.gd

const DEADZONE := 0.2


func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	# physical_keycode, not keycode: this binds the key's POSITION, so WASD stays under the
	# same fingers on AZERTY and Dvorak.
	e.physical_keycode = keycode
	return e


func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _action(name: String, events: Array) -> void:
	ProjectSettings.set_setting("input/" + name, {"deadzone": DEADZONE, "events": events})


func _init() -> void:
	# --- movement: four directions, three input devices each ---
	_action("move_up", [_key(KEY_W), _key(KEY_UP), _button(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_down", [_key(KEY_S), _key(KEY_DOWN), _button(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _button(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _button(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])

	# --- core verbs ---
	# interact talks to NPCs, reads signs and advances dialog: one button for "yes, this".
	_action("interact", [_key(KEY_SPACE), _key(KEY_ENTER), _key(KEY_E), _button(JOY_BUTTON_A)])
	_action("cancel", [_key(KEY_ESCAPE), _key(KEY_X), _button(JOY_BUTTON_B)])
	_action("menu", [_key(KEY_TAB), _button(JOY_BUTTON_START)])

	# --- dev ---
	_action("debug_toggle", [_key(KEY_F1)])

	var err := ProjectSettings.save()
	if err != OK:
		push_error("Failed to save project settings: %d" % err)
		quit(1)
		return
	print("Input map written: 8 actions")
	quit(0)

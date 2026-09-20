extends SceneTree
## The readable SPEC of the project's input actions - and a writer that is never run.
##
## Authoring these by script means no keycode integer is ever typed from memory, and the scene
## tests need the map COMMITTED, not generated at boot: gdUnit4's simulate_action_press can only
## press an action project.godot already has.
##
## DO NOT RE-RUN IT. ProjectSettings.save() writes the whole file back through the engine's own
## serializer, which drops every comment line project.godot carries (docs/learnings.md: the day it
## ran it also removed a hand-typed stretch setting). A binding is changed by editing the [input]
## section's TEXT by hand, and this file beside it so the two still agree; tests/unit/test_prompts.gd
## holds every printed word to the map, which is the drift gate this file's output never had.
##
## The one thing to know about its output: a joypad event's `device` must be ANY_PAD, InputMap's
## "all devices" sentinel, or the binding fires for pad index 0 alone (InputMap::_find_event, at the
## 4.7.1 tag). It shipped as 0 from the first commit until M52, unnoticed by a single Bluetooth pad
## and by every test, because the harness presses actions rather than buttons.
##
##     Godot --headless --path . -s tools/setup_input_map.gd     # spec only - see above

const DEADZONE := 0.2
## InputMap::ALL_DEVICES, which GDScript cannot name. Prompts.ANY_PAD is the same number.
const ANY_PAD := -1


func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	# physical_keycode, not keycode: this binds the key's POSITION, so WASD stays under the
	# same fingers on AZERTY and Dvorak.
	e.physical_keycode = keycode
	return e


func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = ANY_PAD
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = ANY_PAD
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

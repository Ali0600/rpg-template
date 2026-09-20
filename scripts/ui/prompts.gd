class_name Prompts
extends RefCounted
## The words a help line uses for the keys in the player's hands, and what each word stands for.
##
## Every screen here names its keys - a help line at the foot of each window, and a hint on the
## map - because a shop once told the player to press a key nothing binds. Those words were
## keyboard literals, and a player holding an Xbox pad was told to press E. So a help line is a
## TEMPLATE now, "{confirm} to pick    {back} to go back", and fill() writes the word for the
## device in hand: E or A, Esc or B. Words rather than glyphs, because this game draws one pixel
## font and a glyph set is art the template would be choosing for every game built on it - and
## words are what the manuals and the signs of the reference games use (docs/GENRE_CONVENTIONS.md
## §17). Xbox letters only, since Godot's own JoyButton constants are the Xbox layout; a
## PlayStation or Switch table keyed by Input.get_joy_name is the hook (docs/DECISIONS.md, M52).
##
## Which device is "in hand" is the last one that spoke - speaks() and device_of() classify an
## event by its CLASS, never by its device id (a key is device 16 since 4.7, a pad is 0 and up).
## A harness InputEventAction speaks for no device at all.
##
## STANDS_FOR is the binding gate. A word on screen is a claim about the input map, and this table
## says exactly which event, on which action, each word claims; tests/unit/test_prompts.gd holds
## every row against the map. It replaces the keyboard-only check the arena's help line carried,
## and it is the drift gate tools/setup_input_map.gd never had - that tool strips every comment
## from project.godot when run, so the map is edited by hand and this table is what keeps a
## printed word honest.
##
## Pure and autoload-free: the world, every screen and GameManifest.problems() read it, and a
## view naming an autoload leaves the per-file parse gate.

enum Device { KEYBOARD, PAD }
enum Verb { MOVE, CHOOSE, CONFIRM, BACK, PAUSE }
enum Bind { KEY, BUTTON, AXIS }

## InputMap::ALL_DEVICES, which GDScript cannot name: the device every joypad binding carries, or
## it fires for pad index 0 alone. tools/setup_input_map.gd's ANY_PAD is the same number.
const ANY_PAD := -1

## A `{token}` in a help template or a manifest's controls_hint, by the name a writer types.
const TOKENS := {
	"move": Verb.MOVE, "choose": Verb.CHOOSE, "confirm": Verb.CONFIRM,
	"back": Verb.BACK, "pause": Verb.PAUSE,
}

## The word per verb per device. PAUSE is the one verb whose ACTION differs by device: Esc is on
## `cancel`, the pad's Menu button on `menu`, and the world opens the pause menu on either.
const WORDS := {
	Device.KEYBOARD: {
		Verb.MOVE: "WASD", Verb.CHOOSE: "W/S", Verb.CONFIRM: "E", Verb.BACK: "Esc",
		Verb.PAUSE: "Esc",
	},
	Device.PAD: {
		Verb.MOVE: "Stick", Verb.CHOOSE: "D-pad", Verb.CONFIRM: "A", Verb.BACK: "B",
		Verb.PAUSE: "Menu",
	},
}

## What each printed word stands for in the input map: rows of [action, kind, value] and, for an
## axis, its sign. Physical keycodes, because that is how the map binds a key.
const STANDS_FOR := {
	"WASD": [
		[&"move_up", Bind.KEY, KEY_W], [&"move_left", Bind.KEY, KEY_A],
		[&"move_down", Bind.KEY, KEY_S], [&"move_right", Bind.KEY, KEY_D]],
	"W/S": [[&"move_up", Bind.KEY, KEY_W], [&"move_down", Bind.KEY, KEY_S]],
	"E": [[&"interact", Bind.KEY, KEY_E]],
	"Esc": [[&"cancel", Bind.KEY, KEY_ESCAPE]],
	"Stick": [
		[&"move_up", Bind.AXIS, JOY_AXIS_LEFT_Y, -1], [&"move_down", Bind.AXIS, JOY_AXIS_LEFT_Y, 1],
		[&"move_left", Bind.AXIS, JOY_AXIS_LEFT_X, -1], [&"move_right", Bind.AXIS, JOY_AXIS_LEFT_X, 1]],
	"D-pad": [[&"move_up", Bind.BUTTON, JOY_BUTTON_DPAD_UP], [&"move_down", Bind.BUTTON, JOY_BUTTON_DPAD_DOWN]],
	"A": [[&"interact", Bind.BUTTON, JOY_BUTTON_A]],
	"B": [[&"cancel", Bind.BUTTON, JOY_BUTTON_B]],
	"Menu": [[&"menu", Bind.BUTTON, JOY_BUTTON_START]],
}

## The pad's buttons by the word a scripted session names them with - the harness's half of the
## table, so a session and a help line cannot call one button two things.
const BUTTONS := {
	"A": JOY_BUTTON_A, "B": JOY_BUTTON_B, "Menu": JOY_BUTTON_START,
	"D-pad up": JOY_BUTTON_DPAD_UP, "D-pad down": JOY_BUTTON_DPAD_DOWN,
	"D-pad left": JOY_BUTTON_DPAD_LEFT, "D-pad right": JOY_BUTTON_DPAD_RIGHT,
}


static func word(verb: Verb, device: Device) -> String:
	return str(WORDS[device][verb])


## Every `{token}` in the template replaced by the device's word. An unknown token is left as it
## was typed - GameManifest.problems() refuses it upstream, where the writer can be named.
static func fill(template: String, device: Device) -> String:
	var out := template
	for token: String in TOKENS:
		out = out.replace("{%s}" % token, word(TOKENS[token], device))
	return out


## Every `{name}` the template carries, known or not, in order.
static func tokens_of(template: String) -> Array[String]:
	var out: Array[String] = []
	var pattern := RegEx.new()
	pattern.compile("\\{([a-z_]+)\\}")
	for found in pattern.search_all(template):
		out.append(found.get_string(1))
	return out


## The tokens a template names that no device has a word for.
static func unknown_tokens(template: String) -> Array[String]:
	var out: Array[String] = []
	for token in tokens_of(template):
		if not TOKENS.has(token):
			out.append(token)
	return out


## Whether this event is a device speaking: a key, a pad button, or a stick pushed past the map's
## deadzone. A harness action, the mouse and a resting stick say nothing, so a scripted session
## stays on whatever last really spoke, and a stick's drift never flips the words.
static func speaks(event: InputEvent, stick_deadzone: float) -> bool:
	if event is InputEventKey or event is InputEventJoypadButton:
		return true
	var motion := event as InputEventJoypadMotion
	return motion != null and absf(motion.axis_value) >= stick_deadzone


## Which device an event that speaks came from - by its class, never its device id.
static func device_of(event: InputEvent) -> Device:
	return Device.KEYBOARD if event is InputEventKey else Device.PAD

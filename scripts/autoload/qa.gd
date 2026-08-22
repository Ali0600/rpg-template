extends Node
## Drives the running game from a script file, so behaviour can be checked without hands.
##
##     Godot --path . -- --qa-script=res://tests/fixtures/qa/demo/walk_into_wall.json
##
## This exists because `-s tools/some_tool.gd` CANNOT load a scene whose script names an
## autoload: in that mode the singletons are not registered as identifiers and the script
## fails to compile. Anything that needs the real game - the world, the player, the router -
## has to be driven from inside it, which is what this is.
##
## It is also the headless smoke gate in tools/check.sh, and the way screenshots of the
## world get taken. Scripts live in tests/fixtures/qa/<game>/ and check.sh runs each with
## `--game=<that directory>`, so a game's scripts drive that game and adding one needs no
## edit to the gate.
##
## Ops: wait · hold · release · release_all · press · press_until_state · assert_state ·
## assert_map · assert_flag · assert_item · assert_position · assert_hp · assert_xp ·
## assert_level · sound_mark · assert_sound · assert_audio_ready · mark · assert_moved ·
## screenshot · note.
## An unrecognised op FAILS rather than being skipped - a typo in a script must not read as
## a passing check that never ran.
##
## Everything is measured in PHYSICS frames, never seconds and never idle frames. A
## wall-clock wait is slow when it passes and flaky when it fails; and headless, with no
## display pacing anything, _process runs as fast as the machine allows while physics stays
## at 60Hz - so counting idle frames would make "hold right for 30 frames" mean a different
## distance on every machine. Movement happens in _physics_process, so this counts the same
## clock the thing under test does.

const ARG_PREFIX := GameSelect.QA_ARG

var _steps: Array = []
var _index := 0
var _held: Array[StringName] = []
var _failures: Array[String] = []
var _log: Array[String] = []
var _marks: Dictionary = {}
var _frames_left := 0
var _active := false

## A running press_until_state. It owns the step machine until it resolves, so that an
## assertion written after it observes the state it was waiting for rather than racing it.
var _until_active := false
var _until_holding := false
var _until_action: StringName = &""
var _until_state := ""
var _until_limit := 0
var _until_presses := 0
var _finished := false


func _ready() -> void:
	var path := _script_path()
	if path.is_empty():
		# Inert without the flag. A QA harness that does anything at all in a normal run is a
		# harness that will eventually do something in front of a player.
		set_physics_process(false)
		return
	var file := JsonFile.read(path)
	if not file.ok:
		printerr("qa: %s" % file.error)
		get_tree().quit(1)
		return
	_steps = file.get_array("steps")
	if _steps.is_empty():
		printerr("qa: %s has no steps - an empty script would report success having tested nothing" % path)
		get_tree().quit(1)
		return
	_active = true
	_log.append("script %s (%d steps)" % [path, _steps.size()])


func is_active() -> bool:
	return _active


func _script_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(ARG_PREFIX):
			return arg.substr(ARG_PREFIX.length())
	return ""


func _physics_process(_delta: float) -> void:
	if not _active or _finished:
		return
	if _frames_left > 0:
		_frames_left -= 1
		return
	# A press_until_state in flight holds the machine here. Without this the step after it
	# runs immediately and asserts against a state its own presses have not produced yet.
	if _until_active:
		_tick_press_until()
		return
	if _index >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_index]
	_index += 1
	_run(step)


func _run(step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	match op:
		"wait":
			_frames_left = int(step.get("frames", 1))
		"hold":
			# Held through the engine's own input state, so the code under test reads it
			# exactly as it would a real key - not through a back door that bypasses the
			# input map and would keep passing after a rebind broke the game.
			var action := StringName(str(step.get("action", "")))
			_press(action)
			_frames_left = int(step.get("frames", 1))
		"release":
			_release(StringName(str(step.get("action", ""))))
		"release_all":
			_release_all()
		"press":
			var action := StringName(str(step.get("action", "")))
			_press(action)
			_frames_left = 1
			_steps.insert(_index, {"op": "release", "action": String(action)})
		"press_until_state":
			_press_until_state(step)
		"assert_state":
			var wanted := str(step.get("state", ""))
			if Router.state_name() != wanted:
				_fail("expected flow state '%s', found '%s'" % [wanted, Router.state_name()])
		"assert_map":
			var wanted_map := str(step.get("map", ""))
			if String(GameState.current_map) != wanted_map:
				_fail("expected to be in map '%s', found '%s'" % [wanted_map, GameState.current_map])
			else:
				_log.append("in map '%s'" % wanted_map)
		"sound_mark":
			# Clears the window an assert_sound looks at, so a script asks "since I pressed
			# this" rather than "at some point in the whole run".
			AudioBus.clear_requests()
			_log.append("listening from here")
		"assert_sound":
			# The id that was REQUESTED, never that audio was audible: this runs headless on a
			# dummy driver, and a gate that claims to hear something is a gate proving nothing.
			var cue := StringName(str(step.get("id", "")))
			var want := bool(step.get("expect", true))
			var heard := AudioBus.requested().has(cue)
			if heard != want:
				_fail("expected sound '%s' to be %s since the last mark, heard: %s"
					% [cue, "asked for" if want else "silent", AudioBus.requested()])
			else:
				_log.append("sound '%s' %s" % [cue, "played" if heard else "stayed quiet"])
		"assert_audio_ready":
			# Not "was a sound asked for" - assert_sound answers that, and it answers it the
			# same way whether the file exists or not, on purpose. This asks whether the voice
			# can actually PLAY what the template names.
			#
			# In the source tree it is nearly free and always passes. Against an exported pack
			# it is the whole point: an artifact built without its audio boots, walks, talks and
			# requests every cue exactly as it should, and is silent. That was measured, not
			# imagined - excluding the cues from the pack left every other assertion green.
			var absent := AudioBus.missing_cues()
			if not absent.is_empty():
				_fail("the voice cannot play %d cue(s) it names: %s" % [absent.size(), absent])
			else:
				_log.append("every cue the template names is playable")
		"assert_flag":
			# The one assertion that can tell "the quest advanced" from "something moved the
			# player". A gate opening is evidence a warp fired; the flag is evidence the
			# chest is what opened it.
			var key := StringName(str(step.get("key", "")))
			var wanted := bool(step.get("expect", true))
			var actual := GameState.has_flag(key)
			if actual != wanted:
				_fail("expected flag '%s' to be %s, it is %s" % [key, wanted, actual])
			else:
				_log.append("flag '%s' is %s" % [key, actual])
		"assert_item":
			# An EXACT count, not "at least": a lantern that drank the oil and a lantern that
			# did not are one and zero, and "at least zero" cannot tell them apart.
			var item := StringName(str(step.get("id", "")))
			var expected := int(step.get("count", 1))
			var carried := GameState.item_count(item)
			if carried != expected:
				_fail("expected %d of item '%s', found %d" % [expected, item, carried])
			else:
				_log.append("carrying %d of '%s'" % [carried, item])
		"assert_hp", "assert_xp", "assert_level":
			_assert_party(op, step)
		"assert_position":
			_assert_position(step)
		"mark":
			_marks[str(step.get("name", "here"))] = _player_position()
			_log.append("mark '%s' at %s" % [step.get("name", "here"), _player_position()])
		"assert_moved":
			_assert_moved(step)
		"screenshot":
			_screenshot(str(step.get("path", "user://qa.png")))
		"note":
			_log.append(str(step.get("text", "")))
		_:
			_fail("unknown step '%s'" % op)


## Presses an action until the flow state changes, up to a limit.
##
## The alternative - counting presses - ties the gate to how many LINES a writer happened to
## put in the conversation, so adding a sentence breaks a test about control handover. Worse,
## over-pressing re-opens the dialog the moment it closes and the gate reports the state it
## was trying to leave. Bounded, never unbounded: an unreachable state must fail loudly
## rather than spin.
## Starts a press_until_state. It runs as FRAMES, not as a coroutine, and that is the whole
## point of the rewrite.
##
## It used to `await` inside the step - but the step machine that called it does not await, so
## the next step ran on the very next frame while the presses were still going. Every
## assertion written directly after a press_until_state was therefore racing it, and a race
## reports a PASS as readily as a failure: `assert_state world` immediately afterwards passed
## because the conversation had not opened yet. The demo's scripts happened to have a `wait`
## in that spot, which is why nothing noticed until a second game did not.
##
## It also awaited idle frames while everything else here counts physics frames.
func _press_until_state(step: Dictionary) -> void:
	_until_action = StringName(str(step.get("action", "interact")))
	_until_state = str(step.get("state", "world"))
	_until_limit = int(step.get("limit", 40))
	_until_presses = 0
	_until_holding = false
	_until_active = true


## One frame of a running press_until_state: release what was pressed last frame, otherwise
## check the state and press again. Returns while it still owns the step machine.
func _tick_press_until() -> void:
	if _until_holding:
		_release(_until_action)
		_until_holding = false
		return
	if Router.state_name() == _until_state:
		_log.append("reached '%s' after %d press(es)" % [_until_state, _until_presses])
		_until_active = false
		return
	if _until_presses >= _until_limit:
		_fail("pressed '%s' %d times and never reached state '%s' (still '%s')"
			% [_until_action, _until_limit, _until_state, Router.state_name()])
		_until_active = false
		return
	_press(_until_action)
	_until_presses += 1
	_until_holding = true


## Asserts one of the player's fight numbers, EXACTLY, for the same reason assert_item is
## exact: "at least 12 hp" cannot tell a fight that was survived from one that was not fought.
##
## All three verbs share a function because they differ only in which field they read - three
## copies of the same eight lines is where the fourth one goes wrong.
func _assert_party(op: String, step: Dictionary) -> void:
	var expected := int(step.get("value", 0))
	var actual := 0
	match op:
		"assert_hp":
			actual = GameState.player_hp
		"assert_xp":
			actual = GameState.player_xp
		_:
			actual = GameState.player_level
	if actual != expected:
		_fail("expected %s %d, found %d" % [op.trim_prefix("assert_"), expected, actual])
	else:
		_log.append("%s is %d" % [op.trim_prefix("assert_"), actual])


func _assert_position(step: Dictionary) -> void:
	var pos := _player_position()
	var raw := JsonFile.to_int_array(step.get("tile", []))
	if raw.size() != 2:
		_fail("assert_position needs a tile")
		return
	var tile_size := int(step.get("tile_size", 16))
	var actual := MapData.world_to_tile(pos, tile_size)
	var wanted := Vector2i(raw[0], raw[1])
	if actual != wanted:
		_fail("expected the player on tile %s, found %s (world %s)" % [wanted, actual, pos])
	else:
		_log.append("player is on tile %s" % actual)


## Asserts movement along an axis since a named mark. This is the shape most QA assertions
## want: not an exact coordinate - which would pin the test to a speed value someone will
## tune next week - but "it went that way", and later "and then it stopped".
func _assert_moved(step: Dictionary) -> void:
	var axis := str(step.get("axis", "x"))
	var expect := str(step.get("expect", "increase"))
	var mark_name := str(step.get("since", "here"))
	if not _marks.has(mark_name):
		_fail("assert_moved refers to mark '%s', which was never set" % mark_name)
		return
	var origin: Vector2 = _marks[mark_name]
	var before: float = origin.x if axis == "x" else origin.y
	var pos := _player_position()
	var now: float = pos.x if axis == "x" else pos.y
	var delta := now - before
	var moved := absf(delta) > 0.5
	match expect:
		"increase":
			if delta <= 0.5:
				_fail("expected %s to increase, it moved %+.1f" % [axis, delta])
		"decrease":
			if delta >= -0.5:
				_fail("expected %s to decrease, it moved %+.1f" % [axis, delta])
		"unchanged":
			if moved:
				_fail("expected %s to hold still, it moved %+.1f" % [axis, delta])
		_:
			_fail("unknown expect '%s'" % expect)
	_log.append("%s moved %+.1f (%s)" % [axis, delta, expect])


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.save_png(path) != OK:
		_fail("could not write screenshot to " + path)
		return
	_log.append("screenshot " + path)


func _player_position() -> Vector2:
	return GameState.player_position


## Presses through parse_input_event, not action_press.
##
## They are not interchangeable: action_press only sets the Input singleton's STATE, which is
## enough for code that polls (Input.get_axis, which is how movement reads) and invisible to
## code that handles EVENTS (_unhandled_input, which is how interacting and menus read). A
## harness that only did the first would move the player around perfectly and never be able
## to press a button - and the failure looks like the button being broken, not like the
## harness being half-connected.
func _press(action: StringName) -> void:
	if String(action).is_empty() or not InputMap.has_action(action):
		_fail("no such input action '%s'" % action)
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	if not _held.has(action):
		_held.append(action)


func _release(action: StringName) -> void:
	if InputMap.has_action(action):
		var event := InputEventAction.new()
		event.action = action
		event.pressed = false
		Input.parse_input_event(event)
	_held.erase(action)


func _release_all() -> void:
	for action in _held.duplicate():
		_release(action)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	_finished = true
	_release_all()
	# Every session, not just the ones that assert a sound. AudioBus warns once about an id it
	# does not have, into a log nobody is reading, in a build that has already shipped - so a
	# misspelled cue is exactly the kind of defect that survives to release. Checking it here
	# turns that warning into a red gate across all nine scripted play sessions for free.
	for unknown in AudioBus.unknown_requests():
		_fail("something asked for the sound '%s', which no cue is called" % unknown)
	for line in _log:
		print("qa: " + line)
	if _failures.is_empty():
		print("qa: OK (%d steps)" % _steps.size())
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("qa: FAIL " + f)
	printerr("qa: %d failure(s)" % _failures.size())
	get_tree().quit(1)

extends Node
## Drives the running game from a script file, so behaviour can be checked without hands.
##
##     Godot --path . -- --qa-script=res://tests/fixtures/qa/walk_into_wall.json
##
## This exists because `-s tools/some_tool.gd` CANNOT load a scene whose script names an
## autoload: in that mode the singletons are not registered as identifiers and the script
## fails to compile. Anything that needs the real game - the world, the player, the router -
## has to be driven from inside it, which is what this is.
##
## It is also the headless smoke gate in tools/check.sh, and the way screenshots of the
## world get taken.
##
## Everything is measured in PHYSICS frames, never seconds and never idle frames. A
## wall-clock wait is slow when it passes and flaky when it fails; and headless, with no
## display pacing anything, _process runs as fast as the machine allows while physics stays
## at 60Hz - so counting idle frames would make "hold right for 30 frames" mean a different
## distance on every machine. Movement happens in _physics_process, so this counts the same
## clock the thing under test does.

const ARG_PREFIX := "--qa-script="

var _steps: Array = []
var _index := 0
var _held: Array[StringName] = []
var _failures: Array[String] = []
var _log: Array[String] = []
var _marks: Dictionary = {}
var _frames_left := 0
var _active := false
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
		"assert_state":
			var wanted := str(step.get("state", ""))
			if Router.state_name() != wanted:
				_fail("expected flow state '%s', found '%s'" % [wanted, Router.state_name()])
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


func _press(action: StringName) -> void:
	if String(action).is_empty() or not InputMap.has_action(action):
		_fail("no such input action '%s'" % action)
		return
	Input.action_press(action)
	if not _held.has(action):
		_held.append(action)


func _release(action: StringName) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)
	_held.erase(action)


func _release_all() -> void:
	for action in _held.duplicate():
		_release(action)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	_finished = true
	_release_all()
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

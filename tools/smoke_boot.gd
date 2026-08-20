extends SceneTree
## Boots the project for real and checks the things a standalone parse cannot see.
##
## check.sh skips autoload-referencing scripts when parsing files one at a time, because a
## singleton does not exist in a standalone script run. This is the gate that covers them:
## it starts the tree, waits a frame so every autoload has run _ready, and asserts the
## systems are actually there and answering.
##
## Failures are collected rather than returned at the first one - "which of the six broke"
## is the useful output, and bailing early hides the rest.
##
##     Godot --headless --path . -s tools/smoke_boot.gd

func _init() -> void:
	await process_frame

	var failures: Array[String] = []

	for name in ["EventBus", "Registry", "GameState", "SaveManager", "Router", "AudioBus", "Qa"]:
		if root.get_node_or_null(NodePath(name)) == null:
			failures.append("autoload missing: " + name)

	# The input map is committed, not generated at boot. A missing action means someone
	# edited project.godot by hand, and the scene tests that press it would fail with a
	# far less obvious message.
	for action in ["move_up", "move_down", "move_left", "move_right", "interact", "cancel", "menu"]:
		if not InputMap.has_action(action):
			failures.append("input action missing: " + action + " (run tools/setup_input_map.gd)")

	if root.get_node_or_null(^"Registry") != null:
		var registry := root.get_node(^"Registry")
		if not bool(registry.call(&"is_loaded")):
			failures.append("Registry never finished loading")
		var dupes: Array = registry.call(&"duplicate_ids")
		for d: String in dupes:
			failures.append("duplicate content id: " + d)

	# The same question Registry answers, asked of sound: two files answering to one name means
	# one of them is unreachable, and WHICH one depends on directory order. Every shipped voice
	# is then checked end to end - a voice that cannot play a cue the template asks for is a
	# game that boots fine and goes quiet at the moment it should not.
	if root.get_node_or_null(^"AudioBus") != null:
		var audio := root.get_node(^"AudioBus")
		for d: StringName in (audio.call(&"duplicate_ids") as Array):
			failures.append("more than one file answers to sound '%s'" % d)
		for res in ContentScan.resources("res://data/sounds", ["tres"] as Array[String]):
			var voice := res as SoundStyle
			if voice == null:
				continue
			audio.call(&"use_style", voice)
			for cue: StringName in (audio.call(&"missing_cues") as Array):
				failures.append("voice '%s' has no sound for '%s'" % [voice.id, cue])
		audio.call(&"use_style", null)

	if root.get_node_or_null(^"GameState") != null:
		var state := root.get_node(^"GameState")
		state.call(&"new_game", &"smoke_game", &"smoke", Vector2(8.0, 8.0), 0)
		state.call(&"set_flag", &"smoke_flag", true)
		if not bool(state.call(&"has_flag", &"smoke_flag")):
			failures.append("GameState did not keep a flag it was just given")
		state.call(&"reset")
		if bool(state.call(&"has_flag", &"smoke_flag")):
			failures.append("GameState.reset left a flag behind - tests would leak state")

	# Which game boots is data, and the resolution runs before anything is on screen - so when
	# it fails, it fails as an empty window rather than as an error anyone reads.
	if GameSelect.resolve() == null:
		failures.append("GameSelect resolved no game to boot (%s)" % GameSelect.SETTING)
	# EVERY shipped game, not just the one that boots - `--game=` reaches any of them, and a
	# game nothing validates is a game that breaks the day someone runs it.
	for manifest in GameSelect.manifests():
		for p in manifest.problems():
			failures.append("game '%s': %s" % [manifest.id, p])

	# Pixel-art presentation is a project setting, and a setting nobody asserts is a
	# setting an editor session can quietly change.
	if int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)) != 0:
		failures.append("default_texture_filter is not Nearest - pixel art would be blurred")
	if str(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) != "integer":
		failures.append("stretch scale_mode is not integer - pixels would be uneven sizes")

	if failures.is_empty():
		print("smoke_boot: OK")
		quit(0)
		return
	for f in failures:
		printerr("smoke_boot: " + f)
	quit(1)

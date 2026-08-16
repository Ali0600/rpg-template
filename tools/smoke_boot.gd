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

	for name in ["EventBus", "Registry", "GameState"]:
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

	if root.get_node_or_null(^"GameState") != null:
		var state := root.get_node(^"GameState")
		state.call(&"new_game", &"smoke", Vector2(8.0, 8.0), 0)
		state.call(&"set_flag", &"smoke_flag", true)
		if not bool(state.call(&"has_flag", &"smoke_flag")):
			failures.append("GameState did not keep a flag it was just given")
		state.call(&"reset")
		if bool(state.call(&"has_flag", &"smoke_flag")):
			failures.append("GameState.reset left a flag behind - tests would leak state")

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

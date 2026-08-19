class_name SaveDirs
extends RefCounted
## Save-directory chores for the suites that write real files.
##
## Slots live under `<base>/<game>/slot_N.json`, so "empty the test directory" is no longer a
## flat listing: a walk that only removes files leaves every game's subdirectory behind, and
## the next test inherits whatever was in it. That is exactly the kind of leftover that makes
## a suite pass alone and fail in a run, so the recursion lives here rather than being
## re-hand-rolled per suite.

## Removes every file in `dir` and in each of its immediate subdirectories, then the
## subdirectories themselves. One level deep, which is the depth the layout has.
static func clear(dir: String) -> void:
	var root := DirAccess.open(dir)
	if root == null:
		return
	for game in root.get_directories():
		var sub := DirAccess.open(dir.path_join(game))
		if sub == null:
			continue
		for file in sub.get_files():
			sub.remove(file)
		root.remove(game)
	for file in root.get_files():
		root.remove(file)


## Puts arbitrary bytes in a slot, which is what a hand-edited, truncated or copied-in file
## looks like. Goes through SaveManager.slot_path so a test cannot disagree with the layout
## it is testing.
static func write_raw(game: StringName, slot: int, text: String) -> void:
	var path := SaveManager.slot_path(game, slot)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()

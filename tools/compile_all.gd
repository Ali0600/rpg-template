extends SceneTree
## Compiles every project .gd together, so cross-script type errors surface here.
##
## `--check-only -s <file>` parses ONE script without resolving types that come from other
## scripts, so a function typed `Dir.D` handed a plain int passes that per-file check and
## fails only when something loads both - which first happens inside the test runner, where
## it appears as a crash rather than as an error.
##
## Scripts naming an autoload are skipped for the same reason check.sh skips them: a
## singleton only exists in a real project run. tools/smoke_boot.gd covers those instead.
## The autoload list is READ FROM project.godot rather than typed here, because a
## hand-maintained copy of it goes stale the day a new singleton is added and the file that
## uses it silently stops being compiled by this gate.
##
##     Godot --headless --path . -s tools/compile_all.gd

## The roots come from LintCore.SOURCE_ROOTS rather than a copy here, for the same reason the
## autoload list below is read from project.godot: a second hand-maintained copy of "what
## this project contains" goes stale the day a directory is added, and the file that stopped
## being compiled says nothing about it.


func _init() -> void:
	var autoloads := autoload_names()
	if autoloads.is_empty():
		printerr("compile_all: found no autoloads in project.godot - the skip list is broken")
		quit(1)
		return

	var failures: Array[String] = []
	var checked := 0
	var skipped := 0
	var skipped_self := false
	var self_path: String = (get_script() as Script).resource_path

	for root: String in LintCore.SOURCE_ROOTS:
		for path: String in _all_gd(root):
			if _names_an_autoload(path, autoloads):
				skipped += 1
				continue
			if path == self_path:
				# Reloading the script that is currently executing returns ERR_BUSY. It is
				# running, which is proof enough that it compiled.
				skipped_self = true
				continue
			checked += 1
			var script := load(path) as GDScript
			if script == null:
				failures.append(path + " (load returned null)")
				continue
			# load() hands back a partially-built script even when compilation failed, so
			# the null check alone is not enough - reload() reports the real status.
			var err := script.reload()
			if err != OK:
				failures.append("%s (reload error %d)" % [path, err])

	print("compile_all: %d compiled, %d skipped (autoload-dependent)%s"
		% [checked, skipped, ", self running" if skipped_self else ""])
	if failures.is_empty():
		print("compile_all: OK")
		quit(0)
		return
	for f in failures:
		printerr("compile_all: " + f)
	quit(1)


## Autoload singleton names, read from the live ProjectSettings. Shared with smoke_boot so
## both gates agree on what exists.
static func autoload_names() -> Array[String]:
	var out: Array[String] = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var name := str(prop.get("name", ""))
		if name.begins_with("autoload/"):
			out.append(name.trim_prefix("autoload/"))
	return out


## True only if the script actually *uses* a singleton (`GameState.foo`), not merely
## mentions one in prose. Comments are stripped first and a trailing dot is required: a
## skipped file is an uncompiled file, so this errs toward compiling too much.
static func _names_an_autoload(path: String, autoloads: Array[String]) -> bool:
	var code := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var hash_at := line.find("#")
		code += (line if hash_at == -1 else line.substr(0, hash_at)) + "\n"
	for name: String in autoloads:
		if code.contains(name + "."):
			return true
	return false


func _all_gd(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := root.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_all_gd(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out

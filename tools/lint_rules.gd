extends SceneTree
## Walks the repo's source and reports every LintCore violation.
##
## The rules themselves live in scripts/util/lint_core.gd, as pure functions over text, so
## the suite can prove each one fires on a known-bad input. This file only supplies files:
## a `SceneTree` tool cannot be exercised by a test, so it holds no logic worth testing.
##
##     Godot --headless --path . -s tools/lint_rules.gd

## The roots come from LintCore, not from a copy here: this file, tools/compile_all.gd and
## check.sh's parse gate each used to keep their own list, and a directory missing from one
## of them is a directory nobody lints.
const SKIP_DIRS: Array[String] = ["addons", ".godot", ".git"]


func _init() -> void:
	var hits: Array[String] = []
	var scanned := 0
	for root in LintCore.lint_roots():
		for path in _all_gd(root):
			scanned += 1
			hits.append_array(LintCore.scan_text(path, FileAccess.get_file_as_string(path)))

	# A scan that visited nothing is a broken scan, not a clean repo. Without this, a
	# renamed directory turns the gate into a green light wired to nothing.
	if scanned == 0:
		printerr("lint_rules: scanned 0 files - the scan is broken, not the project")
		quit(1)
		return

	if hits.is_empty():
		print("lint_rules: %d files scanned, %d rules, no violations" % [scanned, LintCore.rule_names().size()])
		quit(0)
		return

	for h in hits:
		printerr("lint_rules: " + h)
	printerr("lint_rules: %d violation(s) across %d files" % [hits.size(), scanned])
	quit(1)


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
			if not name.begins_with(".") and not SKIP_DIRS.has(name):
				out.append_array(_all_gd(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out

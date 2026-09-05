extends SceneTree
## Writes a new game: a manifest, a first room, somebody standing in it, and a play session that
## proves it boots.
##
##   tools/new_game.sh --id=my_game
##   tools/new_game.sh --id=my_game --style=gb16 --movement=grid --hooks
##   tools/new_game.sh --id=my_game --out=user://somewhere    (anywhere but the project)
##
## Every decision is made by GameScaffold, which is pure and tested without a disk; this reads what
## the project has, hands it over, writes what comes back, and then LOADS the manifest it just
## wrote and runs its problems() - because a wizard whose output the game refuses is worse than no
## wizard, and the only way to know is to ask the game.
##
## WRITE EVERY FLAG AS `--flag=value`. The space form is refused out loud rather than ignored: a
## value written after a space lands in a positional slot while the option keeps its default, so
## the run reports on a configuration nobody chose.
##
## It never edits project.godot. ProjectSettings.save() strips every comment out of that file, and
## two of them are load-bearing. So the last thing this prints is the line to add by hand, or the
## flag to run with instead.

const VALUES: Array[String] = ["id", "title", "style", "character", "npc", "sound",
	"movement", "save", "combat", "out"]
const SWITCHES: Array[String] = ["hooks"]

var _options := {}
var _out := "res://"


func _init() -> void:
	for arg in OS.get_cmdline_args():
		var name := arg.trim_prefix("--")
		if SWITCHES.has(name):
			_options[name] = true
		elif VALUES.has(name):
			# The 2026-08-04 lesson, made loud.
			_fail("write --%s=<value>, not --%s <value> - the space form sets nothing" % [name, name])
			return
		else:
			for flag in VALUES:
				if arg.begins_with("--%s=" % flag):
					_options[flag] = arg.trim_prefix("--%s=" % flag)

	_out = _resolve(str(_options.get("out", "res://")))
	var known := GameScaffold.known_from_disk()

	var problems := GameScaffold.problems(_options, known)
	if not problems.is_empty():
		for problem in problems:
			printerr("new_game: " + problem)
		_fail("nothing was written")
		return

	var want := GameScaffold.resolved(_options, known)
	var planned := GameScaffold.plan(_options, known, _out)
	if planned.is_empty():
		# A generator that wrote nothing must not report success - lint_rules.gd's rule.
		_fail("planned no files at all")
		return

	# Every path first, then every write. A refusal half way through leaves a game that is neither
	# there nor absent, and the id is already taken by the half of it that landed.
	for path: Variant in planned.keys():
		if FileAccess.file_exists(_at(str(path))):
			_fail("%s is already there - pick another --id, or delete it" % _at(str(path)))
			return
	for path: Variant in planned.keys():
		if not _write(_at(str(path)), str(planned[path])):
			return

	print("new_game: wrote %d file(s) for '%s'" % [planned.size(), want["id"]])
	for path: Variant in planned.keys():
		print("  " + _at(str(path)))
	print("new_game: %s, drawn in %s, played by %s, greeted by %s, speaking in %s"
		% [want["title"], want["style"], want["character"], want["npc"], want["sound"]])

	# The gate the game itself applies, run on what was just written. smoke_boot and
	# test_game_manifest do exactly this to every manifest in data/games, so anything reported here
	# is a build failure waiting to happen rather than a warning.
	var manifest := ResourceLoader.load(_at("data/games/%s.tres" % want["id"]), "",
		ResourceLoader.CACHE_MODE_IGNORE) as GameManifest
	if manifest == null:
		_fail("the manifest that was just written does not load as a GameManifest")
		return
	# Pointed at wherever this run wrote, because a manifest names its start map by id and
	# MapData.root is what turns that into a path. Without this the check is only meaningful for
	# --out=res:// - which is the one case where it would also be least likely to be run.
	var was := MapData.root
	MapData.root = _at("data/maps")
	var faults := manifest.problems()
	MapData.root = was
	if not faults.is_empty():
		for fault in faults:
			printerr("new_game: " + fault)
		_fail("the game was written and the game refuses it")
		return

	print("")
	print("new_game: it will not boot until something chooses it. More than one game with nothing")
	print("          picking between them is a REFUSAL rather than a guess. Either:")
	print("")
	print('  add   application/config/game="%s"   to project.godot' % want["id"])
	print("  or run the game with   --game=%s" % want["id"])
	print("")
	print("          (this tool does not edit project.godot: ProjectSettings.save() strips every")
	print("           comment out of it, and some of them are the only record of a decision.)")
	quit(0)


## A path under wherever this run is writing. `res://` already ends in a separator and a directory
## does not, and getting that wrong writes to `res:/data`, which is a real and very confusing path.
func _at(path: String) -> String:
	return _out + path if _out.ends_with("/") else "%s/%s" % [_out, path]


## Resolved BEFORE anything runs, map_io's rule: a bare `build/games` is relative to whatever
## directory the engine was launched from, which is not what anybody means by it.
static func _resolve(path: String) -> String:
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://") \
			or path.begins_with("/"):
		return path
	return "res://" + path


func _write(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	return true


func _fail(message: String) -> void:
	printerr("new_game: " + message)
	quit(1)

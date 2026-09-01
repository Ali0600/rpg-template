extends SceneTree
## Takes every shipped map out to a visual editor, and brings one back.
##
##     Godot --headless --path . -s tools/map_io.gd --out=tiled --dir=build/maps
##     Godot --headless --path . -s tools/map_io.gd --out=ldtk  --dir=build/maps
##     Godot --headless --path . -s tools/map_io.gd --in=build/maps/quest_village.tmj
##     Godot --headless --path . -s tools/map_io.gd --verify
##
## BUILD-TIME, and the committed artifact stays the native JSON. A map authored in Tiled or LDtk
## comes back as the same legend-and-ASCII file every other map is, so it still diffs as a picture
## in a pull request and nothing new ships. The editor file is a WORKING file: written on demand,
## edited, read back, thrown away. It is deliberately not committed, because a second committed
## description of one map is two files that eventually disagree.
##
## THE TRANSLATORS ARE PURE AND TESTED; THIS IS THE PART THAT WAS NOT. `TiledMap` and `LdtkMap`
## are Dictionary-to-Dictionary and have round-tripped the six shipped maps in a unit suite since
## M38. None of that touches a path, a directory, an extension or an argument - so `--verify`
## round-trips every map THROUGH REAL FILES and compares what returns, which is the only thing
## that can catch this file being wrong. The gate proves the COMMAND, the suite proves the
## translation, and neither substitutes for the other.
##
## WRITE EVERY FLAG AS `--flag=value`. The space form is accepted by no parser here and is
## refused out loud rather than ignored, because a flag that silently does nothing is a run that
## reports on a configuration nobody chose.

const MAP_DIR := "res://data/maps"
const TILE_TABLE := "res://assets/generated/%s/tiles.json"
const TILE_SIZE := 16
## Where --verify does its round trip. Under user:// so a checkout stays clean and a sandbox with
## a read-only project directory can still run the gate.
const SCRATCH := "user://map_io_verify"

## The formats, and everything that differs between them. Adding a third editor is a row here
## plus a translator - never a branch in the code below, which is the whole point of both
## translators answering the same two function names.
const FORMATS := {
	"tiled": {"ext": "tmj", "class": "TiledMap"},
	"ldtk": {"ext": "ldtk", "class": "LdtkMap"},
}

var _out := ""
var _in := ""
var _to := ""
var _dir := ""
var _verify := false
var _problems: Array[String] = []


func _init() -> void:
	for arg in OS.get_cmdline_args():
		if arg == "--verify":
			_verify = true
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--in="):
			_in = arg.trim_prefix("--in=")
		elif arg.begins_with("--to="):
			_to = arg.trim_prefix("--to=")
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
		elif arg in ["--out", "--in", "--to", "--dir"]:
			# The 2026-08-04 lesson, made loud: an option whose value was written after a space
			# leaves the value in a positional slot and the option at its default, so the run
			# reports on a configuration nobody asked for.
			_fail("write %s=<value>, not %s <value> - the space form sets nothing" % [arg, arg])
			return

	# Resolved BEFORE anything runs. A bare `build/maps` is relative to whatever directory the
	# engine was launched from, which is not what anybody means by it - and the repo has already
	# paid for that once, when a relative path handed to --main-pack stopped resolving and
	# presented as a hang rather than as a missing file.
	_dir = _resolve(_dir)
	_in = _resolve(_in)
	_to = _resolve(_to)

	if _verify:
		_run_verify()
		return
	if not _in.is_empty():
		_run_import()
		return
	if not _out.is_empty():
		_run_export()
		return
	_fail("nothing to do: pass --out=<format>, --in=<file> or --verify")


## A path as this tool means it: `res://`, `user://` and absolute paths are already answers, and
## anything else is relative to the PROJECT, which is what a person typing `build/maps` means.
static func _resolve(path: String) -> String:
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://") \
			or path.begins_with("/"):
		return path
	return "res://" + path


# -- exporting ----------------------------------------------------------------------------------


func _run_export() -> void:
	if not FORMATS.has(_out):
		_fail("unknown format '%s'; this knows %s" % [_out, ", ".join(FORMATS.keys())])
		return
	if _dir.is_empty():
		_fail("--out needs --dir=<path> to write into")
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir)) != OK \
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)):
		_fail("could not make '%s'" % _dir)
		return
	var written := 0
	for path in _maps():
		var out_path := "%s/%s.%s" % [_dir.rstrip("/"), path.get_file().get_basename(),
			str((FORMATS[_out] as Dictionary)["ext"])]
		if not _write_one(path, out_path, _out):
			return
		written += 1
	# The atlas goes WITH the maps. Both editors resolve their tileset image relative to the map
	# file, so a directory of maps without it opens with every tile blank - which is what the
	# first export did, and what no gate here could ever have seen: the round trip never reads
	# the image, only the editor does.
	for style: String in _styles_used():
		if not _copy_atlas(style):
			return
	if written == 0:
		# A generator that wrote nothing must not report success - lint_rules.gd's rule, and the
		# same failure: an empty scan reads as a clean one.
		_fail("no maps found in %s" % MAP_DIR)
		return
	print("map_io: wrote %d map(s) to %s as %s" % [written, _dir, _out])
	quit(0)


func _write_one(native_path: String, out_path: String, format: String) -> bool:
	var native := _native_of(native_path)
	if native.is_empty():
		return false
	var ids := _tile_ids(str(native.get("style", "gb16")))
	if ids.is_empty():
		return false
	var made := _to_editor(format, native, ids)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		_fail("could not write '%s': %s" % [out_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(made, "\t", false))
	file.close()
	return true


## Puts a style's tile sheet beside the exported maps, under the name both translators write
## into their tileset entry. One file per style, so a directory holding maps from two banks does
## not collide.
func _copy_atlas(style: String) -> bool:
	return _copy_atlas_to(_dir, style)


func _copy_atlas_to(into: String, style: String) -> bool:
	var from := "res://assets/generated/%s/tiles.png" % style
	var to := "%s/%s" % [into.rstrip("/"), TiledMap.atlas_name(style)]
	if not FileAccess.file_exists(from):
		_fail("no generated tile sheet for '%s' - run gen_sprites.gd first" % style)
		return false
	var bytes := FileAccess.get_file_as_bytes(from)
	var file := FileAccess.open(to, FileAccess.WRITE)
	if file == null:
		_fail("could not write '%s'" % to)
		return false
	file.store_buffer(bytes)
	file.close()
	return true


# -- importing ----------------------------------------------------------------------------------


func _run_import() -> void:
	var format := _format_of(_in)
	if format.is_empty():
		_fail("cannot tell what '%s' is; expected one of %s" % [_in, _extensions()])
		return
	var file := JsonFile.read(_in)
	if not file.ok:
		_fail("could not read '%s': %s" % [_in, file.error])
		return
	var native := _from_editor(format, file.data, _in)
	if native.is_empty():
		return
	var target := _to if not _to.is_empty() \
		else "%s/%s.json" % [MAP_DIR, _in.get_file().get_basename()]
	# Refused rather than written, because the thing being overwritten is a hand-authored map and
	# the reader that produced this had nothing to check it against.
	var checked := MapData.from_dictionary(native)
	if not checked.ok:
		_fail("'%s' converts to a map the game cannot read: %s" % [_in, checked.error])
		return
	if JsonFile.write(target, native) != OK:
		_fail("could not write '%s'" % target)
		return
	print("map_io: wrote %s from %s" % [target, _in])
	quit(0)


# -- the gate -----------------------------------------------------------------------------------


func _run_verify() -> void:
	# Through REAL FILES, in both directions, for every shipped map and every format. The unit
	# suites already prove the translators; what only this can prove is that the command around
	# them resolves a path, picks an extension, makes a directory and parses its own arguments.
	var root := ProjectSettings.globalize_path(SCRATCH)
	DirAccess.make_dir_recursive_absolute(root)
	var checked := 0
	for format: String in FORMATS.keys():
		for path in _maps():
			var native := _native_of(path)
			if native.is_empty():
				return
			var ids := _tile_ids(str(native.get("style", "gb16")))
			if ids.is_empty():
				return
			var scratch_path := "%s/%s.%s" % [SCRATCH, path.get_file().get_basename(),
				str((FORMATS[format] as Dictionary)["ext"])]
			# Through the EXPORT command's own writer, not a second copy of it: a gate that
			# reimplements the thing it is checking can only ever prove itself.
			if not _write_one(path, scratch_path, format):
				return

			var read_back := JsonFile.read(scratch_path)
			if not read_back.ok:
				_fail("%s wrote a %s file it cannot read back: %s"
					% [path.get_file(), format, read_back.error])
				return
			var came_back := _from_editor(format, read_back.data, scratch_path)
			if came_back.is_empty():
				return
			var faults := MapData.differences(MapData.load_from(path),
				MapData.from_dictionary(came_back))
			if not faults.is_empty():
				_problems.append("%s came back from %s as a different map:\n    %s"
					% [path.get_file(), format, "\n    ".join(faults)])
			checked += 1
	if checked == 0:
		_fail("no maps were round-tripped, so this checked nothing")
		return
	# The sheet the maps point at. Asserted HERE because it is the difference between a
	# directory an editor can open and one where every tile is blank - and no round trip can
	# see it, since the translators never read the image.
	for style: String in _styles_used():
		if not _copy_atlas_to(SCRATCH, style):
			return
		var beside := "%s/%s" % [SCRATCH, TiledMap.atlas_name(style)]
		if not FileAccess.file_exists(beside):
			_problems.append("no tile sheet landed beside the maps for '%s'; every tile would "
				% style + "open blank in an editor")
	_sweep(root)
	if not _problems.is_empty():
		for p in _problems:
			printerr("map_io: " + p)
		printerr("map_io: %d map(s) do not survive a trip through an editor." % _problems.size())
		quit(1)
		return
	print("map_io: %d round trip(s) through real files came back the same map" % checked)
	quit(0)


## The scratch files, gone. A gate that leaves its workings behind means the next run can read a
## file the current one did not write - which is how a green result comes to describe a tree
## nobody has.
func _sweep(root: String) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()


# -- shared -------------------------------------------------------------------------------------


## The one place a format name becomes a translator call. Both translators answer the same two
## names, so this is a lookup rather than a branch - and a third editor never touches this file's
## logic.
func _to_editor(format: String, native: Dictionary, ids: PackedStringArray) -> Dictionary:
	if format == "ldtk":
		return LdtkMap.from_native(native, ids, TILE_SIZE,
			_chrome_of(str(native.get("style", ""))))
	return TiledMap.from_native(native, ids, TILE_SIZE)


## The running style's own UI palette, handed to the LDtk exporter so a map opens in the editor
## looking like the game it belongs to. Resolved HERE because a translator may not load a
## resource - the same reason it is handed its tile ids rather than reading them.
func _chrome_of(style: String) -> Dictionary:
	var found := load("res://data/styles/%s.tres" % style) as SpriteStyle
	if found == null:
		return {}
	var out := {}
	for role: String in ["panel", "dim", "text"]:
		out[role] = "#" + found.ui_color(role).to_html(false)
	return out


func _from_editor(format: String, raw: Dictionary, where: String) -> Dictionary:
	var style := StringName(_style_of(format, raw))
	var ids := _tile_ids(String(style))
	if ids.is_empty():
		return {}
	var faults := LdtkMap.problems(raw, style, ids) if format == "ldtk" \
		else TiledMap.problems(raw, style, ids)
	if not faults.is_empty():
		_fail("'%s' is not fit to import:\n    %s" % [where, "\n    ".join(faults)])
		return {}
	return LdtkMap.to_native(raw, ids, TILE_SIZE) if format == "ldtk" \
		else TiledMap.to_native(raw, ids, TILE_SIZE)


## Which tile bank a file was painted against, asked of the file itself. Both translators answer
## it, so this command holds no knowledge of either format's shape.
func _style_of(format: String, raw: Dictionary) -> String:
	return LdtkMap.style_of(raw) if format == "ldtk" else TiledMap.style_of(raw)


func _format_of(path: String) -> String:
	for name: String in FORMATS.keys():
		if path.get_extension() == str((FORMATS[name] as Dictionary)["ext"]):
			return name
	return ""


func _extensions() -> String:
	var out: Array[String] = []
	for name: String in FORMATS.keys():
		out.append("." + str((FORMATS[name] as Dictionary)["ext"]))
	return ", ".join(out)


## Every tile bank the shipped maps are painted from. Derived rather than listed, so a map added
## on a new style needs no edit here.
func _styles_used() -> Array:
	var out := {}
	for path in _maps():
		out[str(_native_of(path).get("style", "gb16"))] = true
	return out.keys()


func _maps() -> PackedStringArray:
	return ContentScan.files_of(MAP_DIR, "json")


func _native_of(path: String) -> Dictionary:
	var file := JsonFile.read(path)
	if not file.ok:
		_fail("could not read '%s': %s" % [path, file.error])
		return {}
	var out := file.data.duplicate(true)
	# Prose for whoever opens the file. It describes nothing the game reads, so it does not travel
	# to an editor and is not compared on the way back.
	out.erase("_readme")
	return out


## The bank in index order, which is what a tile index MEANS. Read from the generated table
## because that is the file the coupling actually runs through - a list of our own would check
## the translators against a bank nobody paints with.
func _tile_ids(style: String) -> PackedStringArray:
	var file := JsonFile.read(TILE_TABLE % style)
	if not file.ok:
		_fail("no generated tile table for '%s' - run gen_sprites.gd first" % style)
		return PackedStringArray()
	var out := PackedStringArray()
	for entry: Variant in file.data.get("tiles", []):
		out.append(str((entry as Dictionary).get("id", "")))
	if out.is_empty():
		_fail("the tile table for '%s' is empty" % style)
	return out


func _fail(message: String) -> void:
	printerr("map_io: " + message)
	quit(1)

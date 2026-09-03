extends GdUnitTestSuite
## Running `tools/map_io.gd` as a COMMAND, which is the only way to check what it decides.
##
## The translators are pure and unit-tested; `--verify` round-trips through real files. Neither
## can see a number the command chooses and hands to BOTH directions - a wrong one cancels itself
## out, comes back the same map, and is only wrong in the file an editor opens. That is exactly
## what happened: this tool held `const TILE_SIZE := 16` through the demo's move to 32px tiles, so
## every export declared a 16px grid over a 384x32 atlas. Tiled would have sliced it into quarter
## tiles and put every object at half its cell.
##
## So this spawns the engine and reads what the command WROTE. `tests/unit/test_ci_paths.gd`
## already spawns bash for the same reason - a rule whose only witness is a step inside check.sh
## has no suite for a mutant to be judged by.

const SCRATCH := "user://map_io_test"
const MAP_DIR := "res://data/maps"

## No --fixed-fps here: map_io quits in its first frame, and tools/_engine.sh says the flag is for
## things driven by frames.
func _run(args: Array) -> void:
	var argv: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tools/map_io.gd"]
	argv.append_array(args)
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), argv, out, true)
	assert_int(code).override_failure_message(
		"map_io.gd %s exited %d:\n%s" % [args, code, "\n".join(PackedStringArray(out))]).is_equal(0)

func _exported(name: String) -> Dictionary:
	var file := JsonFile.read("%s/%s" % [SCRATCH, name])
	assert_bool(file.ok).override_failure_message(
		"map_io wrote no %s: %s" % [name, file.error]).is_true()
	return file.data

## The first shipped map and the size its style is drawn at, from the generated table - never a
## number of this suite's own, which would be the very mistake under test.
func _first_map() -> Dictionary:
	var maps := ContentScan.files_of(MAP_DIR, "json")
	assert_int(maps.size()).override_failure_message(
		"there are no maps to export, so this suite would prove nothing").is_greater(3)
	var native := JsonFile.read(maps[0])
	var style := str(native.data.get("style", ""))
	var table := JsonFile.read("res://assets/generated/%s/tiles.json" % style)
	assert_bool(table.ok).is_true()
	return {
		"name": maps[0].get_file().get_basename(),
		"style": style,
		"tile_size": int(table.data.get("tile_size", 0)),
		# The PAINTABLE tiles, not `columns` - the atlas grew a block of composed transition
		# shapes after them, and an editor is shown only the ids a map may name.
		"tiles": (table.data.get("tiles", []) as Array).size(),
	}

func after_test() -> void:
	var dir := DirAccess.open(ProjectSettings.globalize_path(SCRATCH))
	if dir == null:
		return
	dir.list_dir_begin()
	var found := dir.get_next()
	while found != "":
		if not dir.current_is_dir():
			dir.remove(found)
		found = dir.get_next()
	dir.list_dir_end()

func test_an_exported_tiled_map_is_drawn_on_the_styles_own_grid() -> void:
	var map := _first_map()
	assert_int(int(map["tile_size"])).override_failure_message(
		"the generated table names no tile size, so there is nothing to compare against"
		).is_greater(0)
	_run(["--out=tiled", "--dir=%s" % SCRATCH])
	var raw := _exported("%s.tmj" % map["name"])
	assert_int(int(raw.get("tilewidth", 0))).override_failure_message(
		"'%s' is drawn at %dpx and was exported on a %spx grid"
		% [map["style"], int(map["tile_size"]), raw.get("tilewidth", 0)]).is_equal(map["tile_size"])
	assert_int(int(raw.get("tileheight", 0))).is_equal(map["tile_size"])
	var set_one: Dictionary = (raw["tilesets"] as Array)[0]
	assert_int(int(set_one.get("tilewidth", 0))).override_failure_message(
		"the tileset says its tiles are %spx" % set_one.get("tilewidth", 0)).is_equal(map["tile_size"])
	# The atlas is one row of the whole bank, so its declared width says the same thing again in
	# another unit - a size that is right on the map and wrong here still opens as sliced art.
	assert_int(int(set_one.get("imagewidth", 0))).is_equal(int(map["tile_size"]) * int(map["tiles"]))
	assert_int(int(set_one.get("imageheight", 0))).is_equal(map["tile_size"])

func test_an_exported_ldtk_project_is_drawn_on_the_styles_own_grid() -> void:
	var map := _first_map()
	_run(["--out=ldtk", "--dir=%s" % SCRATCH])
	var raw := _exported("%s.ldtk" % map["name"])
	assert_int(int(raw.get("defaultGridSize", 0))).override_failure_message(
		"'%s' is drawn at %dpx and was exported on a %spx grid"
		% [map["style"], int(map["tile_size"]), raw.get("defaultGridSize", 0)]) \
		.is_equal(map["tile_size"])
	var set_one: Dictionary = ((raw["defs"] as Dictionary)["tilesets"] as Array)[0]
	assert_int(int(set_one.get("tileGridSize", 0))).is_equal(map["tile_size"])
	assert_int(int(set_one.get("pxWid", 0))).is_equal(int(map["tile_size"]) * int(map["tiles"]))

func test_the_atlas_lands_beside_the_exported_maps() -> void:
	# Found by opening one in Tiled and findable nowhere else: both editors resolve the tileset
	# image relative to the map file, so a directory without it opens with every tile blank.
	var map := _first_map()
	_run(["--out=tiled", "--dir=%s" % SCRATCH])
	var beside := "%s/%s" % [SCRATCH, TiledMap.atlas_name(str(map["style"]))]
	assert_bool(FileAccess.file_exists(beside)).override_failure_message(
		"no tile sheet landed at %s; every tile would open blank" % beside).is_true()

func test_the_atlas_that_travels_holds_only_the_tiles_a_map_may_name() -> void:
	# The generated sheet carries the composed transition shapes after the paintable tiles, and
	# both translators tell the editor there are exactly `tilecount` of them. A sheet wider than
	# that opens as a tileset full of shapes a map cannot legally spell - and the round trip
	# never reads the image, so only this can see it.
	var map := _first_map()
	_run(["--out=tiled", "--dir=%s" % SCRATCH])
	var beside := ImageFile.read_png("%s/%s" % [SCRATCH, TiledMap.atlas_name(str(map["style"]))])
	assert_object(beside).is_not_null()
	assert_int(beside.get_width()).override_failure_message(
		"the exported sheet is %d wide; %d tiles at %dpx is %d"
		% [beside.get_width(), int(map["tiles"]), int(map["tile_size"]),
			int(map["tiles"]) * int(map["tile_size"])]) \
		.is_equal(int(map["tiles"]) * int(map["tile_size"]))
	assert_int(beside.get_height()).is_equal(int(map["tile_size"]))

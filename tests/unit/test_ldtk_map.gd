extends GdUnitTestSuite
## Writing this template's maps out to LDtk and reading them back.
##
## THE PROOF IS THE SIX MAPS THE GAME ALREADY SHIPS, round-tripped, exactly as the Tiled suite
## does it - real warps, patrol paths, formations, a locked door and a legend, all authored before
## either direction of this translator existed. Compared through `MapData.differences()`, the one
## place this project asks whether two maps are the same one.
##
## WHAT THIS SUITE CANNOT PROVE, said plainly here because a green suite is persuasive: LDtk is
## not installed on this machine, so nothing here has ever opened a generated file in the editor.
## A round trip proves this reader understands this writer. The nearest independent check that
## WAS made is a one-off validation of all six generated files against LDtk's own published
## 1.5.3 JSON schema (0 errors) - not repeated in the gate, because it needs a Python package the
## runner would have to fetch on every run, and a gate that reaches an external index is a flaky
## gate. To repeat it:
##
##     Godot --headless --path . -s tools/map_io.gd --out=ldtk --dir=user://ldtk_out
##     python3 -m pip install jsonschema
##     # then validate each file against https://ldtk.io/files/JSON_SCHEMA.json
##
## Opening one file in LDtk once would close the gap properly, and that needs a person.

const MAP_DIR := "res://data/maps"
const TILE_SIZE := 16

## The tile bank in index order, which is what a tile index MEANS. Read from the generated table
## because that is the file the coupling runs through - a list of our own would prove the
## translator against a bank nobody paints with.
func _tile_ids(style: String) -> PackedStringArray:
	var file := JsonFile.read("res://assets/generated/%s/tiles.json" % style)
	assert_bool(file.ok).override_failure_message(
		"no generated tile table for '%s', so no tile index here means anything" % style).is_true()
	var out := PackedStringArray()
	for entry: Variant in file.data.get("tiles", []):
		out.append(str((entry as Dictionary).get("id", "")))
	return out

func _native_of(path: String) -> Dictionary:
	var file := JsonFile.read(path)
	assert_bool(file.ok).is_true()
	var out := file.data.duplicate(true)
	# Prose for whoever opens the file; it describes nothing the game reads, so it does not travel.
	out.erase("_readme")
	return out

func _maps() -> PackedStringArray:
	return ContentScan.files_of(MAP_DIR, "json")

func _exported(path: String) -> Dictionary:
	var native := _native_of(path)
	return LdtkMap.from_native(native, _tile_ids(str(native.get("style", "gb16"))), TILE_SIZE)

func test_there_is_something_to_check() -> void:
	# A loop over an empty directory validates nothing and reports success.
	assert_int(_maps().size()).is_greater(3)

func test_every_shipped_map_survives_a_trip_through_ldtk() -> void:
	var checked := 0
	for path in _maps():
		var native := _native_of(path)
		var ids := _tile_ids(str(native.get("style", "gb16")))
		var back := LdtkMap.to_native(LdtkMap.from_native(native, ids, TILE_SIZE), ids, TILE_SIZE)
		var faults := MapData.differences(MapData.load_from(path), MapData.from_dictionary(back))
		assert_array(faults).override_failure_message(
			"'%s' came back from LDtk as a different map:\n  %s"
			% [path.get_file(), "\n  ".join(faults)]).is_empty()
		checked += 1
	assert_int(checked).override_failure_message(
		"no map was round-tripped, so the loop above proved nothing").is_greater(3)

func test_a_map_that_came_back_is_still_a_map_the_game_can_read() -> void:
	for path in _maps():
		var native := _native_of(path)
		var ids := _tile_ids(str(native.get("style", "gb16")))
		var back := LdtkMap.to_native(LdtkMap.from_native(native, ids, TILE_SIZE), ids, TILE_SIZE)
		var after := MapData.from_dictionary(back)
		assert_bool(after.ok).override_failure_message(
			"'%s' did not parse after a trip through LDtk: %s" % [path, after.error]).is_true()
		assert_vector(after.size()).override_failure_message(
			"'%s' changed size" % path).is_equal(MapData.load_from(path).size())

func test_a_tile_lands_where_ldtk_says_it_should() -> void:
	# The arithmetic, pinned against LDtk's own documented meanings rather than against this
	# translator's opinion of them: `px` is PIXEL coordinates in the layer and `src` is PIXEL
	# coordinates into the atlas. Getting either wrong produces a file that round-trips here
	# perfectly and draws a scrambled map in the editor - the one failure this suite could
	# otherwise never see.
	# Deliberately NOT the first tile in the bank. The first draft of this test painted grass,
	# which is index 0 - so `src` was [0,0] and a mutant replacing the whole calculation with
	# [0,0] SURVIVED. An assertion whose expected value is the degenerate one proves nothing;
	# `wall` is index 4, so the arithmetic has somewhere to be wrong.
	var native := {
		"id": "t", "style": "dusk16", "music": "", "legend": {"#": "wall"},
		"ground": ["##", "##"], "decor": ["  ", "  "], "spawns": {},
		"npcs": [], "warps": [], "objects": [], "enemies": [],
	}
	var ids := _tile_ids("dusk16")
	assert_int(ids.find("wall")).override_failure_message(
		"this test needs a tile that is NOT index 0, or it cannot see a wrong src").is_greater(0)
	var made := LdtkMap.from_native(native, ids, TILE_SIZE)
	var level: Dictionary = (made["levels"] as Array)[0]
	var ground: Dictionary = (level["layerInstances"] as Array)[0]
	assert_str(str(ground["__identifier"])).is_equal("ground")
	var tiles: Array = ground["gridTiles"]
	assert_int(tiles.size()).override_failure_message(
		"a two-by-two map of grass drew %d tiles" % tiles.size()).is_equal(4)
	var at := ids.find("wall")
	for entry: Variant in tiles:
		var tile: Dictionary = entry
		assert_int(int(tile["t"])).override_failure_message(
			"a wall cell points at tile %s rather than %d" % [tile["t"], at]).is_equal(at)
		var src := JsonFile.to_int_array(tile["src"])
		assert_int(src[0]).override_failure_message(
			"src is not pixels into the atlas: %s" % [src]).is_equal(at * TILE_SIZE)
		assert_int(src[1]).is_equal(0)
	# The bottom-right cell of a 2x2 map at 16px sits at (16, 16), in pixels.
	var corners: Array = []
	for entry: Variant in tiles:
		corners.append(JsonFile.to_int_array((entry as Dictionary)["px"]))
	assert_bool(corners.has([16, 16])).override_failure_message(
		"no tile was drawn at pixel (16,16); the layer holds %s" % [corners]).is_true()

func test_every_field_a_record_carries_is_declared() -> void:
	# LDtk resolves a field instance through its `defUid`, and reading its own source says an
	# unmatched one is dropped in the kind way and a CRASH in the unkind way. So the definitions
	# are derived from the records rather than hand-listed - a game may put anything on an npc,
	# and a fixed list would silently drop whatever the template did not know about.
	var native := _native_of(_maps()[0])
	var made := LdtkMap.from_native(native, _tile_ids(str(native.get("style", "gb16"))), TILE_SIZE)
	var declared := {}
	for entry: Variant in (made["defs"] as Dictionary)["entities"]:
		var def: Dictionary = entry
		for field: Variant in def["fieldDefs"]:
			declared[int((field as Dictionary)["uid"])] = true
	var seen := 0
	for entry: Variant in ((made["levels"] as Array)[0] as Dictionary)["layerInstances"]:
		var layer: Dictionary = entry
		for thing: Variant in layer.get("entityInstances", []):
			for field: Variant in (thing as Dictionary)["fieldInstances"]:
				var uid := int((field as Dictionary)["defUid"])
				assert_bool(declared.has(uid)).override_failure_message(
					"field '%s' points at definition %d, which nothing declares"
					% [(field as Dictionary)["__identifier"], uid]).is_true()
				seen += 1
	assert_int(seen).override_failure_message(
		"no field instance was written at all, so this checked nothing").is_greater(3)

func test_every_layer_carries_the_arrays_ldtk_reads_without_guarding() -> void:
	# Measured from LDtk's own loader rather than from its schema: it walks `gridTiles`,
	# `entityInstances` and `intGridCsv` RAW, with no null check and no default, so a layer
	# missing any of them aborts the whole file load. They are written on every layer whatever
	# its type, and this is the assertion that keeps them there.
	var made := _exported(_maps()[0])
	var layers: Array = ((made["levels"] as Array)[0] as Dictionary)["layerInstances"]
	assert_int(layers.size()).is_greater(3)
	for entry: Variant in layers:
		var layer: Dictionary = entry
		for key: String in ["gridTiles", "entityInstances", "intGridCsv"]:
			assert_bool(layer.has(key)).override_failure_message(
				"layer '%s' has no '%s', which stops LDtk opening the file at all"
				% [layer.get("__identifier", "?"), key]).is_true()

func test_the_same_map_exports_the_same_bytes_twice() -> void:
	# A drift gate cannot survive an id drawn fresh on every run, and LDtk wants a UUID on the
	# project, the level, every layer and every entity. They are derived from the map's own names
	# instead, which is what makes this true.
	var path := _maps()[0]
	assert_str(JSON.stringify(_exported(path))).is_equal(JSON.stringify(_exported(path)))

func test_every_id_it_writes_is_its_own() -> void:
	# Duplicated iids are ACCEPTED by LDtk and silently collapse entity references onto one
	# object - no warning, no repair. Derived ids make that a real risk rather than a
	# theoretical one, so it is asserted.
	var made := _exported(_maps()[0])
	var seen := {}
	_collect_iids(made, seen)
	assert_int(seen.size()).override_failure_message(
		"the file carries fewer distinct iids than iids").is_greater(5)

func _collect_iids(value: Variant, seen: Dictionary) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		for key: Variant in dict:
			if str(key) == "iid":
				var id := str(dict[key])
				assert_bool(seen.has(id)).override_failure_message(
					"iid '%s' is used twice, which silently corrupts entity references" % id
					).is_false()
				seen[id] = true
			else:
				_collect_iids(dict[key], seen)
	elif value is Array:
		for entry: Variant in value:
			_collect_iids(entry, seen)

func test_a_map_painted_against_another_bank_is_refused() -> void:
	# THE COUPLING. A tile is stored as an INDEX, so a map painted against one bank and read
	# against another is not a broken file - it is a map full of the wrong tiles, and nothing
	# else in this project would notice.
	var ids := _tile_ids("dusk16")
	var made := LdtkMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	assert_array(LdtkMap.problems(made, &"dusk16", ids)).override_failure_message(
		"a map painted against the bank it is being read with was refused").is_empty()
	var shorter := ids.duplicate()
	shorter.remove_at(shorter.size() - 1)
	assert_array(LdtkMap.problems(made, &"dusk16", shorter)).override_failure_message(
		"the bank lost a tile and the map was accepted anyway").is_not_empty()

func test_a_map_painted_against_another_style_is_refused() -> void:
	var ids := _tile_ids("dusk16")
	var made := LdtkMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	assert_array(LdtkMap.problems(made, &"gb16", ids)).override_failure_message(
		"a map painted for one style was read as another without complaint").is_not_empty()

func test_a_project_keeping_its_levels_elsewhere_is_refused() -> void:
	# LDtk can split levels into `.ldtkl` files beside the project. This reads them inline, so a
	# split project would present as a map with no layers rather than as an unsupported file.
	var ids := _tile_ids("dusk16")
	var made := LdtkMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	made["externalLevels"] = true
	assert_array(LdtkMap.problems(made, &"dusk16", ids)).is_not_empty()

func test_a_project_with_two_tilesets_is_refused() -> void:
	var ids := _tile_ids("dusk16")
	var made := LdtkMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	var sets: Array = (made["defs"] as Dictionary)["tilesets"]
	sets.append({"identifier": "other", "uid": 99, "__cWid": 4, "__cHei": 1, "tileGridSize": 16})
	assert_array(LdtkMap.problems(made, &"dusk16", ids)).override_failure_message(
		"a map painted from two banks was accepted, and only one of them can be resolved") \
		.is_not_empty()

func test_a_project_holding_more_than_one_level_is_refused() -> void:
	var ids := _tile_ids("dusk16")
	var made := LdtkMap.from_native(_native_of(_maps()[0]), ids, TILE_SIZE)
	var levels: Array = made["levels"]
	levels.append(levels[0])
	assert_array(LdtkMap.problems(made, &"dusk16", ids)).is_not_empty()

func test_a_structured_field_survives_as_more_than_a_string() -> void:
	# LDtk has no type describing an array of tile PAIRS, which is what a patrol path is, so those
	# travel as JSON behind a marker - the same answer Tiled gets, for a different reason. This is
	# the assertion that says they come back as DATA rather than as the text of some data.
	var native := {
		"id": "t", "style": "dusk16", "music": "", "legend": {".": "grass"}, "ground": ["."],
		"decor": [" "], "spawns": {},
		"npcs": [{"tile": [0, 0], "id": "walker", "behavior": "patrol",
			"path": [[1, 2], [3, 4]], "loop": true, "dwell": 30}],
		"warps": [], "objects": [], "enemies": [],
	}
	var ids := _tile_ids("dusk16")
	var back := LdtkMap.to_native(LdtkMap.from_native(native, ids, TILE_SIZE), ids, TILE_SIZE)
	var npc: Dictionary = (back["npcs"] as Array)[0]
	assert_that(MapData.plain_numbers(npc.get("path"))).override_failure_message(
		"a patrol path came back as %s" % [npc.get("path")]).is_equal([[1, 2], [3, 4]])
	assert_bool(npc.get("loop")).is_true()
	assert_int(npc.get("dwell")).is_equal(30)
	assert_str(str(npc.get("behavior"))).is_equal("patrol")

func test_a_field_the_records_disagree_about_stays_lossless() -> void:
	# One definition describes a FIELD, not one value of it, so records that disagree about a
	# key's type force it to String - and the non-strings among them then have to survive anyway.
	# Picking a winner here would silently rewrite somebody's data.
	var native := {
		"id": "t", "style": "dusk16", "music": "", "legend": {".": "grass"}, "ground": ["."],
		"decor": [" "], "spawns": {},
		"npcs": [{"tile": [0, 0], "id": "a", "note": 7}, {"tile": [0, 0], "id": "b", "note": "hi"}],
		"warps": [], "objects": [], "enemies": [],
	}
	var ids := _tile_ids("dusk16")
	var back := LdtkMap.to_native(LdtkMap.from_native(native, ids, TILE_SIZE), ids, TILE_SIZE)
	var npcs: Array = back["npcs"]
	assert_that(MapData.plain_numbers((npcs[0] as Dictionary).get("note"))).override_failure_message(
		"a number under a disagreed-about field came back as %s"
		% [(npcs[0] as Dictionary).get("note")]).is_equal(7)
	assert_str(str((npcs[1] as Dictionary).get("note"))).is_equal("hi")

func test_a_map_says_which_bank_it_was_painted_against() -> void:
	var native := _native_of(_maps()[0])
	var made := LdtkMap.from_native(native, _tile_ids(str(native.get("style", "gb16"))), TILE_SIZE)
	assert_str(LdtkMap.style_of(made)).is_equal(str(native.get("style", "")))

func test_a_file_naming_no_style_is_not_guessed_at() -> void:
	# Empty, never a default: a guessed bank is the exact failure problems() exists to refuse.
	assert_str(LdtkMap.style_of({})).is_empty()
	assert_str(LdtkMap.style_of({"levels": []})).is_empty()

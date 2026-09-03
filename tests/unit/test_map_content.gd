extends GdUnitTestSuite
## What the maps of a game must agree about, and what a map's own records must be able to see.
##
## Both checks here answer a question no single file can: a map names a style and an NPC names a
## character, and whether that pairing has any art is a fact about the two together. Each is the
## shape of test_battle_content's enemy check, which has covered exactly that for enemies since
## M13 and has never had a companion for the people standing still.

const GAMES := "res://data/games"


func _games() -> Array[GameManifest]:
	var out: Array[GameManifest] = []
	for res in ContentScan.resources(GAMES):
		var manifest := res as GameManifest
		if manifest != null:
			out.append(manifest)
	return out


## The world scales a set of maps is drawn at, as style id -> scale. Takes the maps rather than
## reaching for them, so the gate below can be shown a pair that must fail.
func _scales_of(maps: Array) -> Dictionary:
	var out := {}
	for entry: Variant in maps:
		var map: MapData = entry
		var style := load("res://data/styles/%s.tres" % map.style_id) as SpriteStyle
		if style == null:
			continue
		out[map.style_id] = UiScale.scale_of(style)
	return out


func test_every_map_a_game_can_be_played_into_is_drawn_at_one_size() -> void:
	# The window is sized when a style is bound, and a style is bound per MAP. Two scales in
	# one game is therefore a window that resizes under the player as they walk through a door
	# - and every screen, measured against the design size, would be correct on both sides of
	# it, so nothing else here could see it.
	var checked := 0
	for manifest in _games():
		var maps: Array = []
		for map_id: Variant in WarpGraph.reachable(manifest).keys():
			var map := MapData.load_from(MapData.path_of(StringName(str(map_id))))
			if map.ok:
				maps.append(map)
		assert_int(maps.size()).override_failure_message(
			"game '%s' reaches no maps at all, so this proved nothing" % manifest.id).is_greater(0)
		var scales := _scales_of(maps)
		assert_int(scales.values().size()).is_greater(0)
		var distinct := {}
		for value: Variant in scales.values():
			distinct[value] = true
		assert_int(distinct.size()).override_failure_message(
			"game '%s' can be walked between maps drawn at different sizes: %s"
			% [manifest.id, scales]).is_equal(1)
		checked += 1
	assert_int(checked).override_failure_message(
		"no game was checked, so this proved nothing").is_greater(0)


func test_the_walk_reaches_every_map_the_game_ships() -> void:
	# A membership assertion, not a per-map property: the shipped maps all name one style, so
	# the size check above is satisfied by ANY walk, including one that never leaves the first
	# room. Comparing the whole set against what is on disk is what makes the walk evidence -
	# and it fails in both directions, so a map that stops being reachable is caught too.
	var on_disk := {}
	for path in ContentScan.files_of(MapData.root, "json"):
		var map := MapData.load_from(path)
		if map.ok:
			on_disk[map.id] = true
	assert_int(on_disk.size()).is_greater(1)
	var reached := WarpGraph.reachable(load("res://data/games/quest.tres") as GameManifest)
	var reached_ids := {}
	for key: Variant in reached.keys():
		reached_ids[StringName(str(key))] = true
	assert_array(reached_ids.keys()).override_failure_message(
		"the walk reaches %s of the %s maps this game ships"
		% [reached_ids.size(), on_disk.size()]).contains_exactly_in_any_order(on_disk.keys())


func test_the_size_check_notices_two_maps_that_disagree() -> void:
	# Fail-first, over maps built here rather than shipped: the shipped game agrees with itself
	# by construction, so without this the check above could be reading the wrong field, or no
	# field at all, and still pass forever.
	var narrow := MapData.from_dictionary({"id": "narrow", "style": "dusk16",
		"legend": {".": "grass"}, "ground": ["."]}, "narrow")
	var wide := MapData.from_dictionary({"id": "wide", "style": "lpc32",
		"legend": {".": "grass"}, "ground": ["."]}, "wide")
	var scales := _scales_of([narrow, wide])
	assert_int(int(scales.get(&"dusk16", 0))).is_equal(1)
	assert_int(int(scales.get(&"lpc32", 0))).override_failure_message(
		"lpc32 is not being read as a bigger world at all").is_equal(2)


func test_every_person_a_map_places_has_art_in_that_map_s_style() -> void:
	# The enemy half of this has existed since M13; the NPC half never has. A character with no
	# sheet under the map's style is not an error a player sees as one: the body is still
	# there, still solid, still stops them walking north - and invisible.
	var checked := 0
	for path in ContentScan.files_of(MapData.root, "json"):
		var map := MapData.load_from(path)
		for entry: Variant in map.npcs:
			var npc: Dictionary = entry
			var character := StringName(str(npc.get("character", "")))
			assert_bool(_has_art(map.style_id, character)).override_failure_message(
				"map '%s' places '%s', whose character '%s' has no generated art for style '%s'"
				% [map.id, npc.get("id", "?"), character, map.style_id]).is_true()
			checked += 1
	assert_int(checked).override_failure_message(
		"no shipped map places an NPC, so the loop above proved nothing").is_greater(0)


func test_the_art_check_notices_a_person_nobody_drew() -> void:
	assert_bool(_has_art(&"dusk16", &"quest_warden")).is_true()
	assert_bool(_has_art(&"dusk16", &"nobody_at_all")).override_failure_message(
		"the art check finds a sheet for a character that does not exist").is_false()
	# And it is the STYLE that decides, not the character: the wanderer is drawn in both, the
	# warden in only one, which is exactly what a half-converted cast looks like.
	assert_bool(_has_art(&"lpc32", &"quest_wanderer")).is_true()


func test_every_face_a_conversation_names_has_art_in_the_game_s_style() -> void:
	# The dialog half of the same rule, and the same failure: a `portrait` naming a character with
	# no sheet is not an error a player sees as one - the face is simply absent and the box lays
	# out as though the line were unattributed. The two halves live in different directories and
	# are joined by a bare string, which is the shape S13b's element check has: a typo on either
	# side is a pairing that silently never fires while both files stay individually valid.
	var seen := 0
	for manifest_path in ContentScan.files("res://data/games", ["tres"]):
		var manifest := load(manifest_path) as GameManifest
		if manifest == null:
			continue
		var style := MapData.load_from(MapData.path_of(manifest.start_map)).style_id
		for path in ContentScan.files("res://data/dialog", ["json"]):
			var file := JsonFile.read(path)
			for node_id: Variant in file.get_dict("nodes").keys():
				var node: Dictionary = file.get_dict("nodes")[node_id]
				var face := StringName(str(node.get("portrait", "")))
				if String(face).is_empty():
					continue
				seen += 1
				assert_bool(_has_art(style, face)).override_failure_message(
					"%s/%s draws '%s', who has no generated art for style '%s'"
					% [path.get_file(), node_id, face, style]).is_true()
	assert_int(seen).override_failure_message(
		"no conversation names a face, so this proved nothing").is_greater(3)

func test_the_face_check_notices_a_speaker_nobody_drew() -> void:
	# The control. Without it the loop above passes on a game whose dialog names nobody.
	assert_bool(_has_art(&"lpc32", &"nobody_drew_this")).is_false()
	assert_bool(_has_art(&"lpc32", &"quest_warden")).is_true()


func _has_art(style_id: StringName, character: StringName) -> bool:
	if String(character).is_empty():
		return false
	return FileAccess.file_exists(
		"res://assets/generated/%s/%s.sheet.json" % [style_id, character])

extends GdUnitTestSuite
## The files a new game is made of, decided with no disk in sight.
##
## Every rule is checked against the TEXT the planner produces, parsed back through the same
## readers the game uses - MapData, DialogRunner, LintCore - rather than against the dictionary it
## was built from. A scaffold that produces something only its own author can read is a scaffold
## that fails on the first run, in front of the person least able to diagnose it.

const KNOWN := {
	"styles": ["gb16", "lpc32"],
	"characters_by_style": {
		"gb16": ["hero", "npc_elder", "npc_kid", "npc_smith"],
		"lpc32": ["inn_keeper", "quest_gloom"],
	},
	"voices": ["dusk16", "gb16", "nes16"],
	"existing_ids": ["quest"],
}

const BASE := {"id": "proof", "style": "gb16"}


func _plan(extra: Dictionary = {}) -> Dictionary:
	var options := BASE.duplicate()
	for key: Variant in extra.keys():
		options[key] = extra[key]
	return GameScaffold.plan(options, KNOWN)


func _map_of(planned: Dictionary, id: String = "proof") -> MapData:
	var parsed: Variant = JSON.parse_string(str(planned["data/maps/%s_start.json" % id]))
	assert_object(parsed).override_failure_message(
		"the scaffolded map is not valid JSON at all").is_not_null()
	return MapData.from_dictionary(parsed as Dictionary, "%s_start" % id)


## The tile vocabulary the running game would judge this map against - derived the way
## MapBuilder.build derives it, out of the generated table, rather than listed here.
func _vocabulary(style_id: String) -> Array:
	var meta := JsonFile.read("res://assets/generated/%s/tiles.json" % style_id).data
	var solid: Array[String] = TileSetFactory.solid_ids(meta)
	var known: Array[String] = solid.duplicate()
	for key: Variant in TileSetFactory.coords_by_id(meta).keys():
		if not known.has(str(key)):
			known.append(str(key))
	return [known, solid]


func test_a_scaffolded_map_is_one_the_running_game_would_accept() -> void:
	var vocabulary := _vocabulary("gb16")
	var map := _map_of(_plan())
	assert_bool(map.ok).override_failure_message(map.error).is_true()
	assert_array(map.problems(vocabulary[0], vocabulary[1])).is_empty()
	# And it is the room the manifest sends the player to: a start_map naming a file that exists
	# and a start_spawn naming a place inside it are two different facts.
	assert_vector(map.spawn(&"start")).is_not_equal(Vector2i(-1, -1))


func test_the_room_is_walled_because_an_open_edge_is_a_map_you_walk_out_of() -> void:
	# Fail-first, inside the test: MapData's edge rule only fires when it is handed the solid ids,
	# so without this the assertion above could be checking nothing and still pass. Knock one tile
	# out of the south wall and the same call must refuse.
	var vocabulary := _vocabulary("gb16")
	var parsed: Dictionary = JSON.parse_string(str(_plan()["data/maps/proof_start.json"]))
	var ground: Array = parsed["ground"]
	var last := int(ground.size()) - 1
	ground[last] = str(ground[last]).substr(1).insert(0, ".")
	parsed["ground"] = ground
	var breached := MapData.from_dictionary(parsed, "proof_start")
	assert_str("\n".join(breached.problems(vocabulary[0], vocabulary[1]))
		).override_failure_message("a hole in the wall is not refused, so the walling proves nothing"
		).contains("edge is open")


func test_a_scaffolded_conversation_is_one_the_runner_will_walk() -> void:
	var parsed: Variant = JSON.parse_string(str(_plan()["data/dialog/proof_hello.json"]))
	var runner := DialogRunner.from_dict(parsed as Dictionary)
	assert_bool(runner.ok).override_failure_message(runner.error).is_true()
	assert_array(runner.problems()).is_empty()
	# The map's greeter names it, so the two halves are joined rather than each valid alone.
	var npc: Dictionary = _map_of(_plan()).npcs[0]
	assert_str(str(npc.get("dialog", ""))).is_equal("proof_hello")


func test_the_greeter_is_drawn_facing_whoever_walks_up_to_them() -> void:
	# The facing is a real direction word in a data file, and the planner may not spell one: it
	# comes from Dir, which is what the linter enforces everywhere in this project.
	var npc: Dictionary = _map_of(_plan()).npcs[0]
	assert_str(str(npc.get("facing", ""))).is_equal(String(Dir.name_of(Dir.D.LEFT)))
	var tile: Array = npc["tile"]
	assert_int(int(tile[0])).override_failure_message(
		"the greeter is not beside the spawn, so a session would have to count tiles to reach them"
		).is_equal(GameScaffold.SPAWN.x + 1)
	assert_int(int(tile[1])).is_equal(GameScaffold.SPAWN.y)


func test_a_scaffolded_hooks_file_obeys_the_rules_game_code_obeys() -> void:
	var planned := _plan({"hooks": true})
	var path := "games/proof/proof_hooks.gd"
	assert_bool(planned.has(path)).override_failure_message(
		"--hooks planned no hooks file: %s" % str(planned.keys())).is_true()
	# Linted at the path it will LIVE at, because two of the four rules only apply under games/ -
	# a scaffolded hook that named an autoload would drop itself out of two gates on day one.
	assert_array(LintCore.scan_text("res://" + path, str(planned[path]),
		LintCore.autoload_names())).is_empty()


func test_a_game_with_no_code_gets_no_code() -> void:
	for path: Variant in _plan().keys():
		assert_bool(str(path).begins_with("games/")).override_failure_message(
			"a game that asked for no hooks was given %s" % path).is_false()


func test_a_game_that_varies_nothing_shares_the_templates_own_tuning() -> void:
	# The control-instance rule as code. A second game whose config differs for no reason its
	# design asked for turns every difference a player feels into a suspected defect.
	assert_bool(_plan().has("data/config/proof.tres")).override_failure_message(
		"a game varying no axis was handed a config of its own").is_false()
	assert_str(str(_plan()["data/games/proof.tres"])).contains(
		'path="res://data/game_config.tres"')


func test_a_game_that_moves_an_axis_says_so_in_a_config_of_its_own() -> void:
	# Both directions, because "shares it" and "gets its own" are one rule and a test of half of
	# it passes on a planner that always answers the same way.
	for axis in [{"movement": "grid"}, {"save": "at_point"}]:
		var planned := _plan(axis as Dictionary)
		assert_bool(planned.has("data/config/proof.tres")).override_failure_message(
			"a game that asked for %s is still on the template's config" % axis).is_true()
		assert_str(str(planned["data/games/proof.tres"])).contains(
			'path="res://data/config/proof.tres"')
	assert_str(str(_plan({"movement": "grid"})["data/config/proof.tres"])).contains(
		"grid_step = true")
	assert_str(str(_plan({"save": "at_point"})["data/config/proof.tres"])).contains(
		'save_policy = &"at_point"')


func test_a_fighting_game_gets_a_curve_because_an_empty_one_is_refused() -> void:
	assert_bool(_plan().has("data/combat/proof.tres")).is_false()
	var planned := _plan({"combat": "turns"})
	var text := str(planned["data/combat/proof.tres"])
	assert_str(text).contains("xp_curve = Array[int](")
	assert_str(str(planned["data/games/proof.tres"])).contains(
		'path="res://data/combat/proof.tres"')


func test_the_new_game_joins_the_play_gate_the_day_it_is_made() -> void:
	# check.sh runs every tests/fixtures/qa/<dir>/*.json with --game=<dir>. A scaffolded game with
	# no session is a game nothing ever boots, and the gate would not notice its absence.
	var planned := _plan()
	assert_bool(planned.has("tests/fixtures/qa/proof/boots.json")).override_failure_message(
		"nothing plays the game that was just made: %s" % str(planned.keys())).is_true()
	var session: Dictionary = JSON.parse_string(str(planned["tests/fixtures/qa/proof/boots.json"]))
	var asserted: Array[String] = []
	for entry: Variant in (session["steps"] as Array):
		var step: Dictionary = entry
		asserted.append(str(step.get("op", "")))
	for op in ["assert_state", "assert_map", "assert_position"]:
		assert_bool(asserted.has(op)).override_failure_message(
			"the scaffolded session never uses %s, so it proves the game boots into nothing" % op
			).is_true()


func test_every_planned_path_is_somewhere_this_project_keeps_that_kind_of_file() -> void:
	var roots := ["data/games/", "data/maps/", "data/dialog/", "data/config/", "data/combat/",
		"games/", "tests/fixtures/qa/"]
	for path: Variant in _plan({"hooks": true, "combat": "turns", "save": "at_point"}).keys():
		var placed := false
		for root in roots:
			if str(path).begins_with(root):
				placed = true
		assert_bool(placed).override_failure_message(
			"%s is not under any directory this project keeps content in" % path).is_true()
		assert_bool(str(path).begins_with("/") or str(path).contains("..")).override_failure_message(
			"%s escapes the directory it was planned into" % path).is_false()


func test_the_defaults_name_a_character_the_chosen_style_actually_draws() -> void:
	var want := GameScaffold.resolved({"id": "proof", "style": "lpc32"}, KNOWN)
	var cast: Array = KNOWN["characters_by_style"]["lpc32"]
	assert_bool(cast.has(str(want["character"]))).is_true()
	assert_bool(cast.has(str(want["npc"]))).is_true()
	assert_str(str(want["character"])).override_failure_message(
		"the player and the greeter default to the same person").is_not_equal(str(want["npc"]))
	# lpc32 has no voice of its own, so it falls back rather than asking for one that is not there.
	assert_str(str(want["sound"])).is_equal(GameScaffold.VOICE_FALLBACK)
	assert_str(str(GameScaffold.resolved({"id": "p", "style": "gb16"}, KNOWN)["sound"])
		).override_failure_message("a style with a voice of its own is not speaking in it"
		).is_equal("gb16")
	assert_str(str(GameScaffold.resolved({"id": "two_words"}, KNOWN)["title"])).is_equal("Two Words")


func test_it_refuses_what_it_cannot_make() -> void:
	var cases := {
		"": "a game needs an id",
		"Proof": "snake_case",
		"quest": "already a game",
	}
	for id: Variant in cases.keys():
		assert_str("\n".join(GameScaffold.problems({"id": str(id), "style": "gb16"}, KNOWN))
			).override_failure_message("id '%s' was accepted" % id).contains(str(cases[id]))
	assert_array(GameScaffold.problems(BASE, KNOWN)).override_failure_message(
		"the ordinary case is refused, so every refusal above proves nothing").is_empty()


func test_it_refuses_art_and_sound_this_project_does_not_have() -> void:
	assert_str("\n".join(GameScaffold.problems({"id": "proof", "style": "nope"}, KNOWN))
		).contains("no art style 'nope'")
	assert_str("\n".join(GameScaffold.problems(
		{"id": "proof", "style": "gb16", "character": "quest_gloom"}, KNOWN))
		).override_failure_message("a character drawn in another style was accepted"
		).contains("has no art in style 'gb16'")
	assert_str("\n".join(GameScaffold.problems(
		{"id": "proof", "style": "gb16", "sound": "lpc32"}, KNOWN))
		).contains("no voice 'lpc32'")


func test_it_refuses_an_axis_set_to_something_that_is_not_one_of_the_two() -> void:
	# The save_policy shape: a value checked against a list, refused by name. A typo'd axis that
	# silently read as the default would be a game quietly not doing what its author asked.
	for axis: Variant in [{"movement": "sideways"}, {"save": "sometimes"}, {"combat": "realtime"}]:
		var options := BASE.duplicate()
		for key: Variant in (axis as Dictionary).keys():
			options[key] = (axis as Dictionary)[key]
		assert_int(GameScaffold.problems(options, KNOWN).size()).override_failure_message(
			"%s was accepted" % axis).is_greater(0)


func test_what_this_project_currently_has_is_read_off_the_disk() -> void:
	# The one impure function, and the one the wizard and the boot gate share. Asserted against
	# facts that are true of the shipped project rather than against a copy of its own answer.
	var known := GameScaffold.known_from_disk()
	assert_array(known["styles"]).contains(["gb16", "lpc32"])
	assert_array(known["voices"]).contains(["dusk16"])
	assert_bool((known["voices"] as Array).has("lpc32")).override_failure_message(
		"lpc32 is being offered as a voice, and it has no generated cues at all").is_false()
	assert_array(known["existing_ids"]).contains(["quest"])
	var cast: Array = (known["characters_by_style"] as Dictionary)["gb16"]
	assert_array(cast).contains(["hero"])
	assert_bool(cast.has("hero.sheet")).override_failure_message(
		"the sheet suffix is being carried into the character id").is_false()

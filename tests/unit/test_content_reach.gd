extends GdUnitTestSuite
## The two rules that used to be written as though one game shipped.
##
## Driven over THREE fixture maps and TWO manifests, on purpose. With the one game that ships,
## "the union over every manifest" and "quest.tres, hardcoded" return the same dictionary, and
## "the conversations this game can reach" and "every conversation in the repo" return the same
## list - so a mutant reverting either would survive against the shipped content while saying
## nothing at all about the rule. The production data equalises the versions; a fixture that
## breaks that property is the only thing that can tell them apart.
##
## MapData.root is a shared static, so it is put back in after_test and asserted in each test
## before anything leans on it - a suite that walked data/maps here would be measuring the
## demo and reporting on the fixture.

const ROOT := "user://content_reach_test"
const QUEST_HOOKS := "res://games/quest/quest_hooks.gd"


func before_test() -> void:
	_write_fixture()
	MapData.root = ROOT


func after_test() -> void:
	MapData.root = MapData.MAP_DIR
	var dir := DirAccess.open(ProjectSettings.globalize_path(ROOT))
	if dir == null:
		return
	dir.list_dir_begin()
	var found := dir.get_next()
	while found != "":
		if not dir.current_is_dir():
			dir.remove(found)
		found = dir.get_next()
	dir.list_dir_end()


## Two maps joined by a warp, and one standing apart - which is what a second game looks like to
## the first game's walk.
func _write_fixture() -> void:
	JsonFile.write("%s/one.json" % ROOT, {
		"id": "one", "style": "gb16",
		"legend": {".": "grass", "#": "wall"},
		"ground": ["####", "#..#", "####"],
		"spawns": {"start": [1, 1]},
		"npcs": [{"id": "greeter", "character": "hero", "tile": [2, 1],
			"dialog": "one_greets"}],
		"warps": [{"tile": [1, 1], "map": "two", "spawn": "start",
			"requires_flag": "a_flag", "locked_dialog": "one_refuses"}],
	})
	JsonFile.write("%s/two.json" % ROOT, {
		"id": "two", "style": "gb16",
		"legend": {".": "grass", "#": "wall"},
		"ground": ["####", "#..#", "####"],
		"spawns": {"start": [1, 1]},
		"objects": [{"id": "sign", "tile": [2, 1], "dialog": "two_reads"}],
	})
	JsonFile.write("%s/apart.json" % ROOT, {
		"id": "apart", "style": "gb16",
		"legend": {".": "grass", "#": "wall"},
		"ground": ["####", "#..#", "####"],
		"spawns": {"start": [1, 1]},
	})


func _manifest(id: StringName, start: StringName, hooks: Script = null) -> GameManifest:
	var made := GameManifest.new()
	made.id = id
	made.start_map = start
	made.hooks = hooks
	return made


func test_the_union_is_every_games_walk_rather_than_the_first_ones() -> void:
	assert_str(MapData.root).override_failure_message(
		"the fixture is not what this suite is walking").is_equal(ROOT)
	var alone: Array[GameManifest] = [_manifest(&"first", &"one")]
	# The control, and the reason the case below is evidence: one game's walk stops where its
	# warps do, and `apart` is a real map on disk that it never reaches.
	assert_array(ContentReach.reachable_union(alone).keys()).contains_exactly_in_any_order(
		[&"one", &"two"])

	var both: Array[GameManifest] = [_manifest(&"first", &"one"), _manifest(&"second", &"apart")]
	assert_array(ContentReach.reachable_union(both).keys()).override_failure_message(
		"the union answers for the first game only, so a second game's rooms are orphans"
		).contains_exactly_in_any_order([&"one", &"two", &"apart"])


func test_a_game_reaches_the_conversations_its_maps_name() -> void:
	assert_str(MapData.root).is_equal(ROOT)
	# Both keys, from all three record kinds: an npc's `dialog`, a warp's `locked_dialog` and an
	# object's `dialog`. A refusal is a conversation like any other - it is shown, it names a
	# face, and it has to be drawn in the style of the game that shows it.
	assert_array(ContentReach.dialogs_of(_manifest(&"first", &"one"), [&"one", &"two"])
		).contains_exactly_in_any_order([&"one_greets", &"one_refuses", &"two_reads"])


func test_a_game_also_reaches_the_conversations_only_its_own_code_opens() -> void:
	assert_str(MapData.root).is_equal(ROOT)
	# The warden says three of her four lines from on_interact and nothing in any map names
	# them, so a walk over map records alone declares them ownerless. Measured 2026-09-05:
	# 19 files in data/dialog, 16 named by maps, and exactly these three left over.
	var reached := ContentReach.dialogs_of(
		_manifest(&"first", &"one", load(QUEST_HOOKS) as Script), [&"one"])
	for owed in [&"warden_asks", &"warden_has_key", &"warden_thanks", &"warden_keeper_down"]:
		assert_bool(reached.has(owed)).override_failure_message(
			"a conversation the hooks open is not counted as the game's: %s" % owed).is_true()
	# And the map half is still there beside it, so the two are joined rather than swapped.
	assert_bool(reached.has(&"one_greets")).is_true()


func test_a_game_with_no_hooks_at_all_is_a_legal_shape() -> void:
	assert_str(MapData.root).is_equal(ROOT)
	# new_hooks() answers null for a game with no code, which is most of them. Reading dialog
	# ids off that null is the crash this pins.
	assert_array(ContentReach.dialogs_of(_manifest(&"first", &"apart"), [&"apart"])).is_empty()

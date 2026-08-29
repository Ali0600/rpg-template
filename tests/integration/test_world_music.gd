extends GdUnitTestSuite
## What the world asks for as the player moves through it.
##
## The unit suites prove a tune renders and a track binds. This proves the two places that
## decide WHEN one plays: the title, and every map entry.

const GAME := "res://data/games/quest.tres"

var _world: Node2D

func before_test() -> void:
	GameState.reset()
	Router.reset()
	AudioBus.clear_requests()

func after_test() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	AudioBus.stop_music()
	GameState.reset()
	Router.reset()

func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	return _world

func _manifest() -> GameManifest:
	return (load(GAME) as GameManifest).duplicate() as GameManifest


func test_the_title_plays_the_theme_the_manifest_names() -> void:
	var world := _boot()
	assert_array(AudioBus.music_requested()).override_failure_message(
		"the title is silent; it asked for %s" % [AudioBus.music_requested()]).contains(
		[_manifest().title_music])
	assert_object(world.title_screen()).is_not_null()


func test_a_game_with_no_theme_opens_a_silent_title() -> void:
	# Silence is a legal shape, the way a null CombatDef is a game that cannot fight - and the
	# guard matters: play_music("") would put an empty id in the log for nothing.
	var world := _boot()
	var quiet := _manifest()
	quiet.title_music = &""
	# _ready has already opened one with the shipped game's theme, and open_title refuses a
	# second - so this closes that one and reopens over the silent manifest.
	world._close_title()
	world._offered = quiet
	AudioBus.clear_requests()
	assert_bool(world.open_title()).is_true()
	assert_array(AudioBus.music_requested()).override_failure_message(
		"a game with no theme still asked for one").is_empty()


func test_a_map_that_names_a_theme_asks_for_it_on_arrival() -> void:
	var world := _boot()
	assert_bool(world.start_game(_manifest())).is_true()
	await get_tree().physics_frame
	AudioBus.clear_requests()
	assert_bool(world.enter_map(&"quest_town", &"start")).is_true()
	assert_array(AudioBus.music_requested()).contains([&"barred_gate"])


func test_a_map_that_names_none_stops_what_was_playing() -> void:
	# Stated, never inherited: a map that said nothing would sound like whichever door the
	# player came through, so the cave would be quiet or loud depending on the route.
	var world := _boot()
	assert_bool(world.start_game(_manifest())).is_true()
	await get_tree().physics_frame
	assert_bool(world.enter_map(&"quest_town", &"start")).is_true()
	assert_str(String(AudioBus.music_id())).is_equal("barred_gate")
	assert_bool(world.enter_map(&"quest_cave", &"west_gate")).is_true()
	assert_str(String(AudioBus.music_id())).override_failure_message(
		"the dungeon inherited the town's theme").is_empty()


func test_walking_between_two_maps_that_share_a_theme_does_not_restart_it() -> void:
	# The town and the village play the same tune, and crossing between them must not start it
	# again - which is the bug a player notices immediately and a log cannot see, because the
	# request is made either way.
	var world := _boot()
	assert_bool(world.start_game(_manifest())).is_true()
	await get_tree().physics_frame
	assert_bool(world.enter_map(&"quest_town", &"start")).is_true()
	var started := AudioBus.music_starts()
	assert_bool(world.enter_map(&"quest_village", &"start")).is_true()
	assert_int(AudioBus.music_starts()).override_failure_message(
		"the theme started again crossing between two maps that share it").is_equal(started)
	assert_str(String(AudioBus.music_id())).is_equal("barred_gate")

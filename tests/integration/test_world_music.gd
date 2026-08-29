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


func test_the_title_can_actually_play_the_theme_it_asks_for() -> void:
	# The bug this test was written for: the title asked for its theme before anything had bound
	# the game's VOICE, so the bus had no such track and the title was silent - on every
	# platform, since the day it shipped.
	#
	# Every gate said otherwise, and each was asking a question one step short of the truth.
	# assert_music reads the request LOG, and the request is made either way. music_id() was set
	# whether or not the track could be played. And assert_audio_ready reads missing_tracks(),
	# which reload() only fills in when a voice IS bound - so the one check built to catch a
	# silent artifact reported green precisely because nothing could make a sound.
	#
	# So this asks the only question none of them did: can the thing that was asked for be
	# played by the voice that is bound right now.
	var world := _boot()
	var wanted := _manifest().title_music
	assert_str(String(AudioBus.style_id())).override_failure_message(
		"the title is playing into a bus with no voice bound at all").is_not_empty()
	assert_bool(AudioBus.has_sound(wanted)).override_failure_message(
		"the title asked for '%s' and the bound voice has no such track" % wanted).is_true()
	assert_str(String(AudioBus.music_id())).is_equal(String(wanted))
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


# -- fights --------------------------------------------------------------------------------

## A fight the world can stage anywhere, so the music arms can be driven without walking to an
## enemy's tile. open_battle_with takes the definition, which is what makes this possible.
func _foe() -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"test_foe"
	out.name = "Test Foe"
	out.character = &"quest_warden"
	out.max_hp = 1
	out.attack = 1
	out.defense = 0
	out.xp = 0
	out.moves = [{"name": "Clout", "power": 0}]
	return out

## A world standing in the town, which names a theme - so what a fight DISPLACES is a real tune
## rather than the silence a cave would give, and the hand-back has something to hand back to.
func _in_the_town() -> Node2D:
	var world := _boot()
	assert_bool(world.start_game(_manifest())).is_true()
	await get_tree().physics_frame
	assert_bool(world.enter_map(&"quest_town", &"start")).is_true()
	assert_str(String(AudioBus.music_id())).override_failure_message(
		"the fixture map is silent, so a fight here could not displace anything") \
		.is_equal("barred_gate")
	return world

func test_a_fight_takes_the_room_over() -> void:
	var world := await _in_the_town()
	assert_bool(world.open_battle_with(_foe(), "quest_town/foe")).is_true()
	assert_str(String(AudioBus.music_id())).override_failure_message(
		"the town's theme played on through a fight").is_equal("skirmish")

func test_a_win_stings_and_then_gives_the_room_back() -> void:
	var world := await _in_the_town()
	world.open_battle_with(_foe(), "quest_town/foe")
	world._on_battle_finished(BattleLogic.Outcome.VICTORY, [])
	assert_str(String(AudioBus.music_id())).override_failure_message(
		"a win went straight back to the map without a sting").is_equal("triumph")
	# The hand-back is the bus's own clock; the world only has to have armed it. Proven from
	# both sides in test_audio_bus - here it is that the world chained to the MAP's tune and
	# not to something else.
	for i in ceili(AudioBus.stream_for(&"triumph").get_length() * 60.0) + 3:
		await get_tree().physics_frame
	assert_str(String(AudioBus.music_id())).override_failure_message(
		"the fanfare ended somewhere other than the map it was won in").is_equal("barred_gate")

func test_running_away_gives_the_room_back_at_once() -> void:
	# No sting, because nothing was won - and no waiting either.
	var world := await _in_the_town()
	world.open_battle_with(_foe(), "quest_town/foe")
	world._on_battle_finished(BattleLogic.Outcome.FLED, [])
	assert_str(String(AudioBus.music_id())).override_failure_message(
		"running away played the victory fanfare").is_equal("barred_gate")

func test_losing_stops_the_music() -> void:
	var world := await _in_the_town()
	world.open_battle_with(_foe(), "quest_town/foe")
	world._on_battle_finished(BattleLogic.Outcome.DEFEAT, [])
	assert_str(String(AudioBus.music_id())).override_failure_message(
		"the fight's theme played on over the game-over screen").is_empty()

func test_a_game_that_names_no_battle_theme_sounds_exactly_as_it_did() -> void:
	# THE control, and the reason both fields default to empty: a game that names neither must
	# go through a whole fight with nothing touched. Counted starts rather than the log, because
	# the log cannot tell a theme that kept playing from one that was restarted onto itself.
	var world := _boot()
	var quiet := _manifest()
	quiet.battle_music = &""
	quiet.victory_music = &""
	assert_bool(world.start_game(quiet)).is_true()
	await get_tree().physics_frame
	assert_bool(world.enter_map(&"quest_town", &"start")).is_true()
	var started := AudioBus.music_starts()
	world.open_battle_with(_foe(), "quest_town/foe")
	world._on_battle_finished(BattleLogic.Outcome.VICTORY, [])
	assert_int(AudioBus.music_starts()).override_failure_message(
		"a game with no battle theme still had its music moved by a fight").is_equal(started)
	assert_str(String(AudioBus.music_id())).is_equal("barred_gate")

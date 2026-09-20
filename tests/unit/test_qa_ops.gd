extends GdUnitTestSuite
## That the play harness's assertions can FAIL.
##
## Every scripted session is green, which is the point of them and also the problem: an op whose
## check never fires reads exactly like an op whose check always passes, and a session built on
## one proves nothing while looking like proof. The sessions cannot test this themselves - a
## broken assertion makes them pass harder.
##
## So each op here is driven twice, through Qa's own dispatcher: once where it must be quiet and
## once where it must complain. Only the pair says the instrument works.

func before_test() -> void:
	AudioBus.stop_music()
	Qa._failures.clear()

func after_test() -> void:
	AudioBus.stop_music()
	# The voice is global and outlives this suite, so a test that unbinds it has to put it
	# back - otherwise the next suite in the run inherits a silent bus and fails somewhere
	# that has nothing to do with audio.
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	Qa._failures.clear()
	GameState.reset()


## Runs one step and answers whether it complained.
func _complains(step: Dictionary) -> bool:
	Qa._failures.clear()
	Qa._run(step)
	return not Qa._failures.is_empty()


func test_a_position_is_read_in_the_tiles_of_the_map_that_is_running() -> void:
	# The harness used to divide by a literal 16. On a 32px map that reads every position as
	# twice the tile it is - and a session asserting the tile a door is on would keep passing
	# while pointing somewhere else entirely.
	GameState.reset()
	GameState.tile_size = 32
	GameState.set_player(Vector2(80.0, 112.0), Dir.D.DOWN)
	assert_bool(_complains({"op": "assert_position", "tile": [2, 3]})).override_failure_message(
		"a player 80px into a 32px map is not being read as standing on tile 2").is_false()
	assert_bool(_complains({"op": "assert_position", "tile": [5, 7]})).override_failure_message(
		"the position assertion is still dividing by sixteen").is_true()
	GameState.reset()


func test_asserting_what_is_playing_right_now_can_fail() -> void:
	# The "now" mode reads the live track rather than the request log, and it is the only way a
	# session can say SILENCE - so a session's silence gate is worth exactly what this pair is.
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	AudioBus.play_music(&"barred_gate")
	assert_bool(_complains({"op": "assert_music", "id": "barred_gate", "now": true})) \
		.override_failure_message("the right answer was called wrong").is_false()
	assert_bool(_complains({"op": "assert_music", "id": "skirmish", "now": true})) \
		.override_failure_message("a track that is not playing passed as playing").is_true()

func test_asserting_silence_right_now_can_fail() -> void:
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	AudioBus.play_music(&"barred_gate")
	assert_bool(_complains({"op": "assert_music", "id": "", "now": true})) \
		.override_failure_message("music was playing and a silence gate passed").is_true()
	AudioBus.stop_music()
	assert_bool(_complains({"op": "assert_music", "id": "", "now": true})) \
		.override_failure_message("nothing was playing and the silence gate still failed") \
		.is_false()

func test_asserting_audio_is_ready_fails_when_there_is_no_voice_at_all() -> void:
	# The gate that exists to catch a silent artifact used to pass BECAUSE the artifact was
	# silent. missing_cues() and missing_tracks() are filled by reload() only when a voice is
	# bound, so with none bound both lists are empty and "every cue is playable" came back
	# green having asked about nothing. That is what let a title playing into an unbound bus
	# ship, and it is the shape of every gate that reports on a set it never populated.
	AudioBus.use_style(null)
	assert_bool(_complains({"op": "assert_audio_ready"})).override_failure_message(
		"a bus with no voice bound at all passed the readiness gate").is_true()

	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	assert_bool(_complains({"op": "assert_audio_ready"})).override_failure_message(
		"a fully bound voice failed the readiness gate").is_false()

func test_asserting_what_was_asked_for_still_reads_the_log() -> void:
	# The control for the mode switch: adding "now" must not have taken the old behaviour away.
	# The log remembers a track that has since stopped, which is the whole difference.
	AudioBus.use_style(load("res://data/sounds/dusk16.tres") as SoundStyle)
	AudioBus.clear_requests()
	AudioBus.play_music(&"barred_gate")
	AudioBus.stop_music()
	assert_bool(_complains({"op": "assert_music", "id": "barred_gate"})).override_failure_message(
		"the log forgot a track that played and ended").is_false()
	assert_bool(_complains({"op": "assert_music", "id": "barred_gate", "now": true})) \
		.override_failure_message("'now' answered from the log instead of from the device") \
		.is_true()


func test_asserting_a_companions_numbers_can_fail() -> void:
	GameState.reset()
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	assert_bool(_complains({"op": "assert_hp", "member": "scrapper", "value": 11})) \
		.override_failure_message("a correct companion assertion complained").is_false()
	assert_bool(_complains({"op": "assert_hp", "member": "scrapper", "value": 12})) \
		.override_failure_message("a wrong companion assertion passed").is_true()
	GameState.reset()


func test_asserting_a_number_of_somebody_who_has_not_joined_fails() -> void:
	# The default that would have hidden this: reading a missing companion as nought would make
	# "the person is not here" and "the number is nought" the same finding, and a session
	# recruiting nobody would still assert its way to green.
	#
	# Asserted by the WORDING, not merely by "it complained": with the guard gone, a missing
	# companion reads as a record of no numbers and the value comparison below it complains
	# anyway - a masking path that makes a green mutant look like a covered rule.
	GameState.reset()
	assert_bool(_complains({"op": "assert_hp", "member": "scrapper", "value": 0})) \
		.override_failure_message("a companion who never joined answered an assertion").is_true()
	assert_str("\n".join(Qa._failures)).override_failure_message(
		"the harness complained about the NUMBER when the person was the thing missing") \
		.contains("has not joined")
	Qa._failures.clear()


func test_the_leaders_numbers_are_still_what_a_bare_assertion_reads() -> void:
	# The control every session written before M27 depends on: with no member named, nothing
	# about these ops moved.
	GameState.reset()
	GameState.set_party(20, 0, 1, 8)
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	assert_bool(_complains({"op": "assert_hp", "value": 20})) \
		.override_failure_message("a bare hp assertion stopped reading the leader").is_false()
	GameState.reset()


func test_asking_a_member_for_the_purse_fails() -> void:
	# One purse for the whole party, in every reference game and here - so a member on a gold
	# assertion is a question with no answer rather than a different answer, and answering it
	# would be the harness inventing a per-member economy nobody built.
	GameState.reset()
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	assert_bool(_complains({"op": "assert_gold", "member": "scrapper", "value": 0})) \
		.override_failure_message("the harness answered a per-member gold question").is_true()
	GameState.reset()


func _broken() -> GameManifest:
	var manifest := GameManifest.new()
	manifest.id = &"broken"
	return manifest


func _shipped(game_id: StringName) -> GameManifest:
	for manifest in GameSelect.manifests():
		if manifest.id == game_id:
			return manifest
	return null


func test_a_session_is_judged_by_the_problems_of_the_game_it_ran() -> void:
	# The shipped game is clean, which makes it the control: without that, every refusal below would
	# prove nothing.
	var quest := _shipped(&"quest")
	assert_object(quest).is_not_null()
	assert_array(Qa._running_game_faults(&"quest", GameSelect.manifests())).override_failure_message(
		"the shipped game reports problems, so every refusal below proves nothing").is_empty()
	var carried: Array[GameManifest] = [quest, _broken()]
	assert_str("\n".join(Qa._running_game_faults(&"broken", carried))).override_failure_message(
		"a running game whose manifest has problems was passed").contains("names no start_map")
	# Judged by the game that RAN, not by whichever manifest the build happens to list first.
	var broken_first: Array[GameManifest] = [_broken(), quest]
	assert_array(Qa._running_game_faults(&"quest", broken_first)).override_failure_message(
		"the session was judged by another game's manifest").is_empty()
	# A session that ends on the title started no game, and is not judged by one.
	assert_array(Qa._running_game_faults(&"", carried)).is_empty()
	assert_str("\n".join(Qa._running_game_faults(&"not_a_game", GameSelect.manifests()))
		).override_failure_message("a game this build carries no manifest for was passed"
		).contains("not_a_game")


func test_every_session_ends_by_asking_the_running_game_for_its_problems() -> void:
	# Through the function _finish calls, because _finish quits the tree. A game id no manifest
	# answers to is the one failure the shipped data lets a suite stage, and it is asserted by its
	# wording because AudioBus's unknown requests pile up across the whole run.
	GameState.game = &"not_a_game"
	Qa._failures.clear()
	Qa._end_of_session_checks()
	assert_str("\n".join(Qa._failures)).override_failure_message(
		"the end of a session did not ask about the game that ran").contains("not_a_game")


func test_asserting_which_game_is_running_can_fail() -> void:
	GameState.game = &"quest_arena"
	assert_bool(_complains({"op": "assert_game", "id": "quest_arena"})).is_false()
	assert_bool(_complains({"op": "assert_game", "id": "quest"})).override_failure_message(
		"a session asserting the wrong game passed").is_true()


func test_the_harness_plays_the_arena_the_way_the_driver_s_perfect_does() -> void:
	# The harness cannot name ArenaDriver - tests/ is not in the exported pack, and a shipped autoload
	# naming a class that is not there fails to load - so it states PERFECT's choice again. This holds
	# the two to one answer over every branch the choice takes. Floor units: MID is (1280, 768), and a
	# player facing right there reaches x 1360 to 1552 with the sword.
	var combat := CombatDef.new()
	combat.id = &"agreement"
	combat.xp_curve = [10]
	combat.arena_tiles = Vector2i(10, 6)
	# [what it is, player, facing, foe, what happens first: 0 nothing, 1 a swing, 2 a still frame]
	var cases := [
		["far away and off the line", Vector2i(256, 256), Dir.D.RIGHT, Vector2i(2048, 1280), 0],
		["in reach", Vector2i(1280, 768), Dir.D.RIGHT, Vector2i(1480, 768), 0],
		["about to be touched", Vector2i(1280, 768), Dir.D.RIGHT, Vector2i(1116, 768), 0],
		["lined up but out of reach", Vector2i(1280, 768), Dir.D.UP, Vector2i(1296, 200), 0],
		["mid-swing", Vector2i(1280, 768), Dir.D.RIGHT, Vector2i(1480, 768), 1],
		["shoved by a touch", Vector2i(1280, 768), Dir.D.RIGHT, Vector2i(1300, 768), 2],
	]
	for entry: Variant in cases:
		var c: Array = entry
		var foe := EnemyDef.new()
		foe.id = &"agree"
		foe.name = "Agree"
		foe.character = &"quest_slink"
		foe.max_hp = 99
		foe.attack = 3
		foe.moves = [{"name": "Bump", "power": 0}]
		foe.speed_tiles_per_second = 2.0
		foe.chase_every_frames = 5
		var sim := ArenaSim.of(combat, [foe], [BattleHelpers.leader(combat)], "map/foe", 7,
			GameConfig.new())
		var spots: Array[Vector2i] = [c[3]]
		sim.stage(c[1], c[2], spots)
		if int(c[4]) > 0:
			sim.tick(Vector2.ZERO, int(c[4]) == 1)
		var expected := ArenaDriver.choose(sim, ArenaDriver.Policy.PERFECT)
		var actual := Qa._arena_choice(sim)
		assert_vector(actual["move"] as Vector2).override_failure_message(
			"%s: the harness moves %s where PERFECT moves %s" % [c[0], actual["move"], expected.move]
			).is_equal(expected.move)
		assert_bool(bool(actual["swing"])).override_failure_message(
			"%s: the harness swings %s where PERFECT swings %s" % [c[0], actual["swing"], expected.swing]
			).is_equal(expected.swing)


## A foe of a stated health, for the two fault readers below. Named for what varies: the point of
## every case here is that two foes with DIFFERENT health are told apart.
func _a_foe(id: StringName, hp: int) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = id
	out.name = String(id).capitalize()
	out.character = &"quest_slink"
	out.max_hp = hp
	out.attack = 3
	out.moves = [{"name": "Bump", "power": 0}]
	return out


func test_a_foe_health_step_that_forgot_its_expect_is_refused_by_name() -> void:
	# The refusal is ordered BEFORE any screen is looked for, and that is the only reason this can
	# be proven here: a suite has no fight in the tree, so an op that reached for one first would
	# complain about the missing fight and this would pass without the guard existing at all. So
	# the WORDING is the assertion, the has-not-joined shape above.
	#
	# What it prevents: a missing expect read as nought, which is "assert this foe is down" - a
	# silent default that passes on any foe already down, in the one op whose whole job is the
	# size of a number.
	assert_bool(_complains({"op": "assert_foe_hp", "foe": 0})).override_failure_message(
		"a foe health step with nothing to compare against was accepted").is_true()
	assert_str("\n".join(Qa._failures)).override_failure_message(
		"the step was judged as 'there is no fight' rather than as incomplete") \
		.contains("needs an expect")
	Qa._failures.clear()


func test_a_status_step_says_which_kind_of_fight_it_needs() -> void:
	# An arena has no statuses at all - the word appears nowhere in ArenaSim - so "outside a
	# battle" is a lie in the one case that is now reachable: standing in one. The wording IS the
	# fix. A branch naming the arena would need a findable ArenaScreen, which no suite here can
	# stage and no session can assert a refusal from: a permanently untested branch to say what one
	# sentence says for free.
	assert_bool(_complains({"op": "assert_status", "member": 0, "expect": ""})).is_true()
	assert_str("\n".join(Qa._failures)).override_failure_message(
		"the refusal still reads as 'no battle', where an arena IS a battle") \
		.contains("needs a turn fight")
	Qa._failures.clear()


func test_a_foes_health_is_read_out_of_the_arenas_own_rules() -> void:
	# The WIRING - finding an arena screen in the tree - needs a real play session, and
	# fall_at_the_keep_by_the_sword.json is where that is proven. This is the arithmetic under it,
	# which a staged ArenaSim can drive with no scene tree at all.
	#
	# Two foes with DIFFERENT health, because "it read a number" and "it read the foe it was asked
	# about" are different answers and only a pair can tell them apart.
	var combat := CombatDef.new()
	combat.id = &"agreement"
	combat.xp_curve = [10]
	combat.arena_tiles = Vector2i(10, 6)
	var sim := ArenaSim.of(combat, [_a_foe(&"small", 4), _a_foe(&"big", 9)],
		[BattleHelpers.leader(combat)], "map/foe", 7, GameConfig.new())
	assert_str(Qa._arena_foe_fault(sim, 0, 4)).is_empty()
	assert_str(Qa._arena_foe_fault(sim, 1, 9)).is_empty()
	assert_str(Qa._arena_foe_fault(sim, 1, 4)).override_failure_message(
		"every foe answered with the first one's health").contains("found 9")
	# ArenaSim.foe_hp indexes its bodies with no guard, so without these two a session naming a foe
	# nobody is standing in is an engine error mid-run rather than a refusal with the op's name on it.
	assert_str(Qa._arena_foe_fault(sim, 2, 9)).contains("this fight has 2")
	assert_str(Qa._arena_foe_fault(sim, -1, 9)).contains("this fight has 2")


func test_a_foes_health_is_read_out_of_the_turn_fights_own_rules() -> void:
	# The twin, and the bounds hole on this side is older than the arena: BattleLogic.enemy_hp
	# indexes its foes with no guard either, and nothing had ever asked it for one that was not there.
	var combat := CombatDef.new()
	combat.id = &"agreement"
	combat.xp_curve = [10]
	var logic := BattleHelpers.against(combat, [_a_foe(&"small", 4), _a_foe(&"big", 9)])
	assert_str(Qa._turn_foe_fault(logic, 0, 4)).is_empty()
	assert_str(Qa._turn_foe_fault(logic, 1, 9)).is_empty()
	assert_str(Qa._turn_foe_fault(logic, 1, 4)).override_failure_message(
		"every foe answered with the first one's health").contains("found 9")
	assert_str(Qa._turn_foe_fault(logic, 2, 9)).contains("this fight has 2")
	assert_str(Qa._turn_foe_fault(logic, -1, 9)).contains("this fight has 2")


func test_pressing_a_pad_button_nobody_named_fails() -> void:
	assert_bool(_complains({"op": "pad_press", "button": "Z"})).override_failure_message(
		"a typo'd button read as a press").is_true()
	assert_bool(_complains({"op": "pad_press", "button": "A"})).is_false()
	Qa._release_all()
	Qa._steps.clear()


func test_a_key_nobody_can_name_is_refused() -> void:
	assert_bool(_complains({"op": "key_press", "key": "Frobnicate"})).is_true()
	assert_bool(_complains({"op": "key_press", "key": "Escape"})).is_false()
	Qa._release_all()
	Qa._steps.clear()


func test_a_prompt_assertion_can_fail_both_ways() -> void:
	# No world in this suite, so nothing is drawn: "a line says X" must complain and "no line
	# says X" must be quiet. The pair is what says the instrument reads the screen at all.
	assert_bool(_complains({"op": "assert_prompt", "contains": "A to pick"})).is_true()
	assert_bool(_complains({"op": "assert_prompt", "contains": "A to pick", "expect": false})).is_false()
	assert_bool(_complains({"op": "assert_prompt"})).override_failure_message(
		"an assert_prompt with nothing to look for passed").is_true()

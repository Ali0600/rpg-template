extends GdUnitTestSuite
## Who is in the party, in a running world.
##
## BattleLogic proves what a party DOES; this proves who it is. The three facts that only exist
## out here: membership is derived from a flag rather than recorded, a companion becomes real
## on their own curve the first time somebody asks for them, and a fight's result reaches the
## right person - a companion's numbers must not be written over the leader's.

const GAME := "res://data/games/quest.tres"
const TEST_DIR := "user://test_saves"

var _world: Node2D

func before_test() -> void:
	GameState.reset()
	Router.reset()
	SaveManager.base_dir = TEST_DIR
	SaveDirs.clear(TEST_DIR)

func after_test() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	SaveDirs.clear(TEST_DIR)
	SaveManager.base_dir = SaveManager.DEFAULT_DIR
	GameState.reset()
	Router.reset()

func _combat() -> CombatDef:
	var out := CombatDef.new()
	out.id = &"test_combat"
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 5
	out.attack_per_level = 2
	out.base_defense = 1
	out.defense_per_level = 1
	out.base_mp = 6
	out.mp_per_level = 3
	out.xp_curve = [10, 12]
	out.attack_cue_frames = 4
	out.defend_cue_frames = 4
	out.timed_window_frames = 2
	out.message_frames = 2
	return out

## A companion whose curve is deliberately NOT the game's, so "grew on their own curve" and
## "grew on the player's" cannot agree by accident.
func _member(flag := &"rook_joins") -> PartyMemberDef:
	var out := PartyMemberDef.new()
	out.id = &"rook"
	out.name = "Rook"
	out.character = &"quest_warden"
	out.joins_on_flag = flag
	var curve := _combat()
	curve.id = &"rook_combat"
	curve.base_hp = 13
	curve.base_mp = 2
	out.combat = curve
	return out

## The shipped game with combat attached, duplicated: a loaded resource is one instance shared
## with every other suite, so assigning to it here would follow them out of this file.
func _manifest(party: Array[PartyMemberDef] = []) -> GameManifest:
	var manifest := (load(GAME) as GameManifest).duplicate() as GameManifest
	manifest.combat = _combat()
	manifest.party = party
	return manifest

func _boot(party: Array[PartyMemberDef] = []) -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(_manifest(party))).override_failure_message(
		"the world would not start the game").is_true()
	await get_tree().physics_frame
	return _world

# --- membership is derived --------------------------------------------------------------

func test_a_game_with_no_roster_fights_with_one_member() -> void:
	# The control the whole milestone rests on: nothing declared, one member, and it is the
	# leader the manifest names rather than anybody invented.
	await _boot()
	var members: Array = _world._battle_members()
	assert_int(members.size()).is_equal(1)
	var leader: BattleLogic.Fighter = members[0]
	assert_str(String(leader.id)).override_failure_message(
		"the synthesized leader was given an id, which the sink routes companions by").is_equal("")
	assert_str(leader.name).is_equal("You")

func test_a_companion_is_absent_until_their_flag_is_set() -> void:
	await _boot([_member()])
	assert_int((_world._battle_members() as Array).size()).override_failure_message(
		"somebody joined the party before the game said they had").is_equal(1)

func test_setting_the_flag_puts_them_in_the_party() -> void:
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	var members: Array = _world._battle_members()
	assert_int(members.size()).override_failure_message(
		"the flag was set and nobody joined").is_equal(2)
	assert_str((members[1] as BattleLogic.Fighter).name).is_equal("Rook")

func test_a_member_with_no_flag_is_in_the_party_from_the_start() -> void:
	# Final Fantasy I's shape: a cast fixed before the game begins.
	await _boot([_member(&"")])
	assert_int((_world._battle_members() as Array).size()).is_equal(2)

# --- becoming real ------------------------------------------------------------------------

func test_a_companion_arrives_full_on_their_own_curve() -> void:
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	_world._battle_members()
	var numbers := GameState.companion(&"rook")
	assert_int(int(numbers.get("hp", 0))).override_failure_message(
		"a companion arrived on somebody else's curve").is_equal(13)
	assert_int(int(numbers.get("mp", -1))).is_equal(2)
	assert_int(int(numbers.get("level", 0))).is_equal(1)

func test_a_companion_who_is_already_real_is_not_refilled() -> void:
	# The _ensure_party rule: the fill happens once, or every fight would open by healing
	# everybody and the damage in the last one would never have happened.
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	GameState.set_companion(&"rook", 4, 0, 1, 0)
	_world._battle_members()
	assert_int(int(GameState.companion(&"rook").get("hp", 0))).override_failure_message(
		"a wounded companion was quietly healed on the way into a fight").is_equal(4)

func test_a_companion_joining_above_level_one_arrives_with_the_experience_that_bought_it() -> void:
	# Otherwise their next fight levels them a second time for xp they were given rather than
	# earned - the same lie handing an old save full magic would be.
	var member := _member()
	member.join_level = 2
	await _boot([member])
	GameState.set_flag(&"rook_joins", true)
	_world._battle_members()
	var numbers := GameState.companion(&"rook")
	assert_int(int(numbers.get("level", 0))).is_equal(2)
	assert_int(int(numbers.get("xp", -1))).override_failure_message(
		"a member who joined at level two arrived with nothing to show for it").is_equal(10)

# --- whose spells, whose gear ---------------------------------------------------------------

func test_a_companion_only_knows_the_spells_their_own_list_names() -> void:
	var member := _member()
	member.spells = [&"mend"]
	await _boot([member])
	GameState.set_flag(&"rook_joins", true)
	var members: Array = _world._battle_members()
	var rook: BattleLogic.Fighter = members[1]
	for row: BattleLogic.SpellRow in rook.spells:
		assert_str(String(row.id)).override_failure_message(
			"a companion was offered '%s', which is not on their list" % row.id).is_equal("mend")

func test_a_companion_with_no_list_knows_nothing() -> void:
	# Dragon Quest II's hero exactly, and the default: most companions in the genre are not
	# casters, so an empty list has to mean none rather than all.
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	var members: Array = _world._battle_members()
	assert_array((members[1] as BattleLogic.Fighter).spells).override_failure_message(
		"a companion with no spell list was handed the whole game's magic").is_empty()

func test_the_leader_still_knows_everything_their_level_has_reached() -> void:
	# The M25 rule, untouched: the leader's magic is derived from level over everything the
	# game ships, which is what keeps the spell session's assertions true.
	await _boot([_member()])
	var members: Array = _world._battle_members()
	assert_bool((members[0] as BattleLogic.Fighter).spells.size() > 0).override_failure_message(
		"the leader stopped knowing the spells their level had reached").is_true()

func test_gear_reaches_the_member_wearing_it() -> void:
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	GameState.give_item(&"bronze_sword")
	GameState.equip(&"weapon", &"bronze_sword", &"rook")
	var members: Array = _world._battle_members()
	assert_int((members[0] as BattleLogic.Fighter).attack_mod).override_failure_message(
		"the leader was credited with a sword the companion is wearing").is_equal(0)
	assert_bool((members[1] as BattleLogic.Fighter).attack_mod > 0).override_failure_message(
		"a companion's own sword did not reach the fight").is_true()

# --- the result reaches the right person -----------------------------------------------------

func test_a_fight_result_writes_each_member_to_their_own_record() -> void:
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	GameState.set_party(20, 0, 1, 6)
	GameState.set_companion(&"rook", 13, 0, 1, 2)
	_world._apply_effects([{
		"op": GameContext.OP_PARTY,
		"members": [
			{"id": "", "hp": 11, "xp": 5, "level": 1, "mp": 3},
			{"id": "rook", "hp": 7, "xp": 5, "level": 1, "mp": 1},
		],
	}])
	assert_int(GameState.player_hp).override_failure_message(
		"the leader's own result did not reach them").is_equal(11)
	assert_int(int(GameState.companion(&"rook").get("hp", 0))).override_failure_message(
		"a companion's result was written somewhere other than their own record").is_equal(7)

func test_a_rest_puts_the_whole_party_back_up() -> void:
	# EarthBound's hospital and Dragon Quest's priest, through the inn this template already
	# has: full is full for everybody, and a fallen member is exactly what it undoes.
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	GameState.set_party(3, 0, 1, 0)
	GameState.set_companion(&"rook", 0, 0, 1, 0)
	_world._apply_effects([{"op": GameContext.OP_REST}])
	assert_int(GameState.player_hp).override_failure_message(
		"the leader did not wake up whole").is_equal(20)
	var rook := GameState.companion(&"rook")
	assert_int(int(rook.get("hp", 0))).override_failure_message(
		"a fallen companion was left on the floor by a full night's sleep").is_equal(13)
	assert_int(int(rook.get("mp", -1))).override_failure_message(
		"a companion's magic did not come back with their health").is_equal(2)

# --- the demo's own companion, and the member step ----------------------------------------

func test_the_shipped_game_has_a_companion_nobody_has_recruited_yet() -> void:
	# The demo's party is OPT-IN, which is what leaves the sixteen sessions written before M27
	# fighting alone with the press counts they recorded. Their fights are still solo because
	# the flag is not set, not because the party does not exist.
	var manifest := load(GAME) as GameManifest
	assert_array(manifest.party).override_failure_message(
		"the shipped game declares no party at all").is_not_empty()
	assert_array(manifest.problems()).is_empty()

func test_a_solo_game_is_never_asked_which_member_it_means() -> void:
	# An empty member list rather than a list of one, so the menu's "is there a step" question
	# answers no without having to count to two.
	await _boot()
	assert_array(_world._member_rows()).override_failure_message(
		"a game with no party was given a member list").is_empty()

func test_a_party_of_one_is_still_no_member_step() -> void:
	# The roster exists and nobody has joined, which is the demo's own state for most of a run.
	await _boot([_member()])
	assert_array(_world._member_rows()).override_failure_message(
		"the leader alone was offered as a list to choose from").is_empty()

func test_once_somebody_joins_the_menu_has_a_list() -> void:
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	var rows: Array = _world._member_rows()
	assert_int(rows.size()).is_equal(2)
	assert_str(str((rows[0] as Dictionary).get("id", "x"))).override_failure_message(
		"the leader is not first in the member list").is_equal("")
	assert_str(str((rows[1] as Dictionary).get("name", ""))).is_equal("Rook")

func test_the_status_page_describes_the_member_it_was_asked_about() -> void:
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	GameState.set_party(20, 0, 1, 6)
	_world._battle_members()
	var leader_lines: Array = _world._status_lines()
	var rook_lines: Array = _world._status_lines(&"rook")
	var leader := "\n".join(leader_lines)
	var rook := "\n".join(rook_lines)
	assert_str(leader).contains("HP 20/20")
	assert_str(rook).override_failure_message(
		"the companion's page described the player instead").contains("HP 13/13")

func test_gear_is_put_on_the_member_the_menu_is_about() -> void:
	# Driven with the pause screen OPEN, because that is the only state the member selection
	# can be made from - the handler refreshes the menu, and a test calling it with no menu up
	# is testing a state the game cannot be in.
	await _boot([_member()])
	GameState.set_flag(&"rook_joins", true)
	GameState.give_item(&"bronze_sword")
	assert_bool(_world.open_pause()).override_failure_message(
		"the pause menu would not open").is_true()
	await get_tree().physics_frame
	_world._on_member_selected(&"rook")
	_world._on_equip_requested(&"bronze_sword")
	assert_str(str(GameState.equipped(&"weapon", &"rook"))).override_failure_message(
		"gear chosen on a companion's page went onto the leader").is_equal("bronze_sword")
	assert_str(str(GameState.equipped(&"weapon"))).is_equal("")

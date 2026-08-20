extends GdUnitTestSuite
## Which cue a fight asks for, and when.
##
## The queue is separate from the effect list on purpose, and this suite is where that pays:
## effects are applied once at the end and are DISCARDED on defeat, but losing is exactly when
## the defeat sting has to play. A fight makes noise all the way through.

const CUE := 30
const DEFEND_CUE := 40
const WINDOW := 6
const MESSAGE := 10


func _combat() -> CombatDef:
	var out := CombatDef.new()
	out.id = &"test_combat"
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 5
	out.attack_per_level = 2
	out.base_defense = 1
	out.defense_per_level = 1
	var curve: Array[int] = [10, 12]
	out.xp_curve = curve
	out.attack_cue_frames = CUE
	out.defend_cue_frames = DEFEND_CUE
	out.timed_window_frames = WINDOW
	out.message_frames = MESSAGE
	return out


func _enemy(hp := 10, attack := 3, xp := 5) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"test_enemy"
	out.name = "Test Enemy"
	out.character = &"quest_warden"
	out.max_hp = hp
	out.attack = attack
	out.defense = 1
	out.xp = xp
	out.moves = [{"name": "Scratch", "power": 0}]
	return out


func _fight(enemy: EnemyDef = null, hp := 20, xp := 0, level := 1) -> BattleLogic:
	var foe := enemy if enemy != null else _enemy()
	return BattleLogic.of(_combat(), foe, hp, xp, level, [], "map/foe", 7)


## Ticks a cue down to exactly `at` frames remaining, so a press lands on a known frame.
func _tick_to(battle: BattleLogic, at: int) -> void:
	for i in 500:
		if battle.count() <= at:
			return
		battle.tick()
	fail("the cue never reached %d frames remaining" % at)


func _until_leaves(battle: BattleLogic, from: BattleLogic.Phase, bound := 400) -> void:
	for i in bound:
		if battle.phase() != from:
			return
		battle.tick()
	fail("the fight never left phase %d within %d frames" % [from, bound])


func test_a_clean_hit_and_a_late_one_do_not_sound_the_same() -> void:
	# The whole point of the timing mechanic is that landing it FEELS different. If both asked
	# for the same cue, the only feedback would be a number in a line of text.
	var timed := _fight()
	timed.press()
	_tick_to(timed, WINDOW - 1)
	timed.take_sounds()
	timed.press()
	_until_leaves(timed, BattleLogic.Phase.PLAYER_ACT)
	assert_array(timed.take_sounds()).contains([Sfx.id_of(Sfx.Cue.TIMED_HIT)])

	var late := _fight()
	late.press()
	late.take_sounds()
	_until_leaves(late, BattleLogic.Phase.PLAYER_ACT)
	var heard := late.take_sounds()
	assert_array(heard).contains([Sfx.id_of(Sfx.Cue.HIT)])
	assert_array(heard).not_contains([Sfx.id_of(Sfx.Cue.TIMED_HIT)])


func test_blocking_and_being_hit_do_not_sound_the_same() -> void:
	var blocked := _fight()
	blocked.press()
	_until_leaves(blocked, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(blocked, BattleLogic.Phase.MESSAGE)
	_tick_to(blocked, WINDOW - 1)
	blocked.take_sounds()
	blocked.press()
	_until_leaves(blocked, BattleLogic.Phase.ENEMY_ACT)
	assert_array(blocked.take_sounds()).contains([Sfx.id_of(Sfx.Cue.BLOCK)])

	var hurt := _fight()
	hurt.press()
	_until_leaves(hurt, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(hurt, BattleLogic.Phase.MESSAGE)
	hurt.take_sounds()
	_until_leaves(hurt, BattleLogic.Phase.ENEMY_ACT)
	assert_array(hurt.take_sounds()).contains([Sfx.id_of(Sfx.Cue.HURT)])


func test_winning_and_levelling_both_sound_in_the_same_frame() -> void:
	# Two cues land together, which is why the view DRAINS a list rather than reading a "last
	# sound" field. A single field would drop one of them, and it would be the level-up.
	var fight := _fight(_enemy(1, 3, 50))
	fight.press()
	_until_leaves(fight, BattleLogic.Phase.PLAYER_ACT)
	var heard := fight.take_sounds()
	assert_array(heard).contains([Sfx.id_of(Sfx.Cue.VICTORY)])
	assert_array(heard).contains([Sfx.id_of(Sfx.Cue.LEVEL_UP)])


func test_a_win_that_does_not_level_says_so_by_staying_quieter() -> void:
	# The control for the test above: if LEVEL_UP fired on every victory it would be noise
	# rather than information, and the test above would pass without meaning anything.
	var fight := _fight(_enemy(1, 3, 1))
	fight.press()
	_until_leaves(fight, BattleLogic.Phase.PLAYER_ACT)
	var heard := fight.take_sounds()
	assert_array(heard).contains([Sfx.id_of(Sfx.Cue.VICTORY)])
	assert_array(heard).not_contains([Sfx.id_of(Sfx.Cue.LEVEL_UP)])


func test_losing_still_makes_a_noise() -> void:
	# Defeat effects are discarded entirely by the world, so a cue riding on the effect list
	# would be silent at exactly the moment the player most needs to be told what happened.
	var fight := _fight(_enemy(200, 500), 1)
	for i in 400:
		fight.tick()
		if fight.finished():
			break
		if fight.phase() == BattleLogic.Phase.MENU:
			fight.press()
	assert_int(fight.outcome()).is_equal(BattleLogic.Outcome.DEFEAT)
	assert_array(fight.take_sounds()).contains([Sfx.id_of(Sfx.Cue.DEFEAT)])


func test_draining_empties_the_queue() -> void:
	# A view that drains every frame must not hear the same cue on the next one - which would
	# turn a single hit into a stutter for as long as the fight lasted.
	var fight := _fight()
	fight.move(1)
	assert_array(fight.take_sounds()).is_not_empty()
	assert_array(fight.take_sounds()).is_empty()


func test_moving_the_cursor_blips_and_a_cursor_that_cannot_move_does_not() -> void:
	var fight := _fight()
	fight.take_sounds()
	assert_bool(fight.move(1)).is_true()
	assert_array(fight.take_sounds()).is_equal([Sfx.id_of(Sfx.Cue.MENU_MOVE)] as Array[StringName])
	# During a cue there is no cursor to move, so the press is a TIMING press and must not
	# blip - a menu noise mid-swing would read as the menu still being open.
	fight.press()
	fight.take_sounds()
	assert_bool(fight.move(1)).is_false()
	assert_array(fight.take_sounds()).is_empty()

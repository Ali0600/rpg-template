extends GdUnitTestSuite
## The rules of a fight, with no screen in the way.
##
## Two families matter here. The REFUSALS - a boss cannot be fled, an empty item page cannot be
## confirmed, mashing does not re-arm a timing window - each come paired with a control that
## succeeds, because a battle that refused everything would pass every refusal test on its own.
## And the TIMING, which is pinned at literal frame counts rather than at the constants under
## test: a probe written as `press(combat.timed_window_frames)` moves with the value it is
## meant to be checking and can never see it change.

## Deliberately not the shipped numbers. A fight built from data/combat/ would re-test the
## content every time the designer retuned it, and would stop testing the rule.
const CUE := 30
const DEFEND_CUE := 40
const WINDOW := 6
const MESSAGE := 10

func _combat(curve: Array[int] = [10, 12]) -> CombatDef:
	var out := CombatDef.new()
	out.id = &"test_combat"
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 5
	out.attack_per_level = 2
	out.base_defense = 1
	out.defense_per_level = 1
	out.xp_curve = curve
	out.attack_cue_frames = CUE
	out.defend_cue_frames = DEFEND_CUE
	out.timed_window_frames = WINDOW
	out.message_frames = MESSAGE
	return out

func _enemy(hp := 10, attack := 3, defense := 1, xp := 5, boss := false,
		gold := 0) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"test_enemy"
	out.name = "Test Enemy"
	out.character = &"quest_warden"
	out.max_hp = hp
	out.attack = attack
	out.defense = defense
	out.xp = xp
	out.gold = gold
	out.boss = boss
	out.moves = [{"name": "Scratch", "power": 0}, {"name": "Lunge", "power": 2}]
	return out

func _fight(enemy: EnemyDef = null, hp := 20, xp := 0, level := 1, items: Array = [],
		curve: Array[int] = [10, 12], attack_mod := 0, defense_mod := 0) -> BattleLogic:
	var foe := enemy if enemy != null else _enemy()
	return BattleLogic.of(_combat(curve), foe, hp, xp, level, items, "map/foe", 7,
		attack_mod, defense_mod)

func _tonic(count := 1, heal := 10) -> BattleLogic.ItemRow:
	return BattleLogic.ItemRow.of(&"tonic", "Tonic", count, heal)

## Runs frames until the fight leaves `from`, or the bound runs out. BOUNDED on purpose: a
## "tick until it changes" loop over a machine that can stall is how a test hangs a whole run
## instead of failing, and the assertion is what turns "never arrived" into a failure.
func _until_leaves(battle: BattleLogic, from: BattleLogic.Phase, bound := 400) -> void:
	for i in bound:
		if battle.phase() != from:
			return
		battle.tick()
	fail("the fight never left phase %d within %d frames" % [from, bound])

## Ticks a cue down to exactly `at` frames remaining, so a press lands on a known frame.
func _tick_to(battle: BattleLogic, at: int) -> void:
	for i in 500:
		if battle.count() <= at:
			return
		battle.tick()
	fail("the cue never reached %d frames remaining" % at)


# -- the arithmetic ------------------------------------------------------------------------

func test_a_hit_never_deals_nothing() -> void:
	# Armour that matches an attacker exactly must still take a point off. At zero, two such
	# fighters swing forever and the battle never ends - which reads as a frozen game.
	assert_int(BattleLogic.damage(5, 5)).is_equal(1)
	assert_int(BattleLogic.damage(3, 99)).is_equal(1)

func test_a_hit_takes_defense_off() -> void:
	assert_int(BattleLogic.damage(9, 2)).is_equal(7)


# -- the command menu ----------------------------------------------------------------------

func test_a_fresh_fight_waits_on_attack() -> void:
	var battle := _fight()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.index()).is_equal(BattleLogic.Row.ATTACK)
	assert_int(battle.size()).is_equal(3)
	assert_int(battle.outcome()).is_equal(BattleLogic.Outcome.NONE)
	assert_bool(battle.finished()).is_false()

func test_the_command_cursor_wraps_both_ways() -> void:
	var battle := _fight()
	assert_bool(battle.move(-1)).is_true()
	assert_int(battle.index()).is_equal(BattleLogic.Row.FLEE)
	assert_bool(battle.move(1)).is_true()
	assert_int(battle.index()).is_equal(BattleLogic.Row.ATTACK)

func test_the_cursor_does_not_move_during_a_cue() -> void:
	# A press during a cue is a timing press. If the stick still moved the cursor, a player
	# defending themselves would be choosing a menu row at the same time.
	var battle := _fight()
	battle.press()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.PLAYER_ACT)
	assert_bool(battle.move(1)).is_false()
	assert_int(battle.index()).is_equal(BattleLogic.Row.ATTACK)


# -- timing --------------------------------------------------------------------------------

func test_a_press_inside_the_window_is_timed() -> void:
	var battle := _fight()
	battle.press()
	_tick_to(battle, WINDOW)
	assert_bool(battle.cue_on()).is_true()
	battle.press()
	assert_bool(battle.pressed_in_time()).is_true()

func test_a_press_one_frame_early_is_not() -> void:
	# The control for the test above, and the edge itself: 7 frames out on a 6-frame window.
	# Written as a literal so that widening the window has to move this number by hand.
	var battle := _fight()
	battle.press()
	_tick_to(battle, WINDOW + 1)
	assert_bool(battle.cue_on()).is_false()
	battle.press()
	assert_bool(battle.pressed_in_time()).is_false()

func test_a_timed_hit_doubles_the_damage() -> void:
	var battle := _fight()
	var before := battle.enemy_hp()
	battle.press()
	_tick_to(battle, WINDOW)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	# level 1: attack 5 - defense 1 = 4, doubled.
	assert_int(before - battle.enemy_hp()).is_equal(8)

func test_an_untimed_hit_does_not() -> void:
	var battle := _fight()
	var before := battle.enemy_hp()
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	assert_int(before - battle.enemy_hp()).is_equal(4)

func test_mashing_cannot_re_arm_the_window() -> void:
	# The whole point of the mechanic. Without the first-press-only rule, holding the button
	# lands a press in every window and "timing" means "press a lot".
	var battle := _fight()
	var before := battle.enemy_hp()
	battle.press()
	battle.press()  # far too early, and it is the one that counts
	_tick_to(battle, WINDOW)
	battle.press()  # perfectly timed, and ignored
	assert_bool(battle.pressed_in_time()).is_false()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	assert_int(before - battle.enemy_hp()).is_equal(4)

func test_a_first_press_inside_the_window_still_counts() -> void:
	# The control for the mash test: the rule is "only the first press", not "an early press
	# poisons the cue" and not "presses never count".
	var battle := _fight()
	battle.press()
	_tick_to(battle, WINDOW - 1)
	battle.press()
	assert_bool(battle.pressed_in_time()).is_true()

## An enemy with ONE move, so what it does on its turn is a fixed number rather than whichever
## of two the seed drew. A range assertion over two possible moves cannot tell a halved hit
## from an unhalved one - the halved big move and the unhalved small one are the same figure.
func _one_move_enemy(hp := 99, attack := 9) -> EnemyDef:
	var out := _enemy(hp, attack)
	out.moves = [{"name": "Clout", "power": 0}]
	return out

func test_a_blocked_enemy_hit_is_halved() -> void:
	var battle := _fight(_one_move_enemy())
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ENEMY_ACT)
	var before := battle.player_hp()
	_tick_to(battle, WINDOW)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	# Clout is 9 - 1 defense = 8, halved to 4. Exact, so a block that did nothing reads as 8.
	assert_int(before - battle.player_hp()).is_equal(4)

func test_an_unblocked_enemy_hit_is_not() -> void:
	var battle := _fight(_one_move_enemy())
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var before := battle.player_hp()
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	assert_int(before - battle.player_hp()).is_equal(8)

func test_a_blocked_hit_still_takes_something_off() -> void:
	# The floor, from the other side: blocking a hit that was only worth one point must not
	# round down to a fight where defending is free.
	var battle := _fight(_one_move_enemy(99, 2))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var before := battle.player_hp()
	_tick_to(battle, WINDOW)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	assert_int(before - battle.player_hp()).is_equal(1)


# -- turn order ----------------------------------------------------------------------------

func test_a_round_runs_player_then_enemy_then_back_to_the_menu() -> void:
	var battle := _fight(_enemy(99))
	battle.press()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MESSAGE)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ENEMY_ACT)
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.index()).is_equal(BattleLogic.Row.ATTACK)


# -- items ---------------------------------------------------------------------------------

func test_a_tonic_heals_and_costs_the_turn() -> void:
	var battle := _fight(_enemy(99), 10, 0, 1, [_tonic()])
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ITEMS)
	battle.press()
	assert_int(battle.player_hp()).is_equal(20)
	# Straight to the enemy's turn: no free drink.
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ENEMY_ACT)

func test_a_tonic_cannot_overheal() -> void:
	var battle := _fight(_enemy(99), 18, 0, 1, [_tonic()])
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	battle.press()
	assert_int(battle.player_hp()).is_equal(20)

func test_using_a_tonic_asks_for_exactly_one_to_be_taken() -> void:
	var battle := _fight(_enemy(99), 10, 0, 1, [_tonic(2)])
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	battle.press()
	var takes: Array[Dictionary] = []
	for effect: Dictionary in battle.effects():
		if effect.get("op") == GameContext.OP_TAKE_ITEM:
			takes.append(effect)
	assert_int(takes.size()).is_equal(1)
	assert_int(int(takes[0].get("count", 0))).is_equal(1)
	assert_str(str(takes[0].get("id", ""))).is_equal("tonic")

func test_the_last_tonic_leaves_the_list() -> void:
	var battle := _fight(_enemy(99), 10, 0, 1, [_tonic(1)])
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	battle.press()
	assert_int(battle.item_rows().size()).is_equal(0)

func test_an_empty_item_page_refuses_a_confirm() -> void:
	var battle := _fight(_enemy(99), 10)
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ITEMS)
	assert_int(battle.size()).is_equal(1)
	battle.press()
	# Still standing there, turn not spent, nothing collected.
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ITEMS)
	assert_int(battle.effects().size()).is_equal(0)

func test_cancel_backs_out_of_the_item_page() -> void:
	# The control for the refusal above: an empty page must still be escapable.
	var battle := _fight(_enemy(99), 10)
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	assert_bool(battle.cancel()).is_true()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.index()).is_equal(BattleLogic.Row.ITEM)

func test_cancel_cannot_leave_a_fight() -> void:
	var battle := _fight()
	assert_bool(battle.cancel()).is_false()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MENU)
	assert_bool(battle.finished()).is_false()


# -- fleeing -------------------------------------------------------------------------------

func test_fleeing_an_ordinary_enemy_works() -> void:
	var battle := _fight()
	battle.move(BattleLogic.Row.FLEE)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_bool(battle.finished()).is_true()
	assert_int(battle.outcome()).is_equal(BattleLogic.Outcome.FLED)

func test_something_fled_from_is_not_marked_beaten() -> void:
	# The rule that makes fleeing cost something: the enemy is still standing on that tile.
	var battle := _fight()
	battle.move(BattleLogic.Row.FLEE)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	for effect: Dictionary in battle.effects():
		assert_str(str(effect.get("op"))).is_not_equal(String(GameContext.OP_SEEN))

func test_a_boss_cannot_be_fled_and_the_attempt_costs_the_turn() -> void:
	var battle := _fight(_enemy(99, 3, 1, 5, true))
	battle.move(BattleLogic.Row.FLEE)
	battle.press()
	assert_bool(battle.finished()).is_false()
	assert_int(battle.outcome()).is_equal(BattleLogic.Outcome.NONE)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ENEMY_ACT)


# -- winning -------------------------------------------------------------------------------

func test_winning_ends_the_fight_and_marks_the_enemy_beaten() -> void:
	var battle := _fight(_enemy(4))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_bool(battle.finished()).is_true()
	assert_int(battle.outcome()).is_equal(BattleLogic.Outcome.VICTORY)
	var seen: Array[Dictionary] = []
	for effect: Dictionary in battle.effects():
		if effect.get("op") == GameContext.OP_SEEN:
			seen.append(effect)
	assert_int(seen.size()).is_equal(1)
	assert_str(str(seen[0].get("key", ""))).is_equal("map/foe")

func test_a_weapon_adds_to_every_blow() -> void:
	# Stats are DERIVED from level here, so gear can only ever be a modifier on that
	# derivation - and this is the site that proves the modifier arrives.
	var bare := _fight(_enemy(99))
	var armed := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 4, 0)
	bare.press()
	armed.press()
	_until_leaves(bare, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(armed, BattleLogic.Phase.PLAYER_ACT)
	assert_int(armed.enemy_hp()).override_failure_message(
		"a sword changed nothing: bare left %d, armed left %d" % [bare.enemy_hp(), armed.enemy_hp()]) \
		.is_less(bare.enemy_hp())
	assert_int(armed.attack_mod()).is_equal(4)

func test_armour_takes_the_edge_off_every_hit() -> void:
	var bare := _fight(_enemy(99, 20))
	var plated := _fight(_enemy(99, 20), 20, 0, 1, [], [10, 12], 0, 3)
	for battle in [bare, plated]:
		battle.press()
		_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
		_until_leaves(battle, BattleLogic.Phase.MESSAGE)
		_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	assert_int(plated.player_hp()).override_failure_message(
		"armour changed nothing: bare %d hp, plated %d hp" % [bare.player_hp(), plated.player_hp()]) \
		.is_greater(bare.player_hp())
	assert_int(plated.defense_mod()).is_equal(3)

func test_winning_drops_the_enemys_coin() -> void:
	var battle := _fight(_enemy(4, 3, 1, 5, false, 7))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var paid := 0
	for effect: Dictionary in battle.effects():
		if effect.get("op") == GameContext.OP_GOLD:
			paid += int(effect.get("amount", 0))
	assert_int(paid).override_failure_message(
		"a won fight paid %d, not the enemy's 7" % paid).is_equal(7)

func test_an_enemy_with_no_coin_appends_no_gold_at_all() -> void:
	# The near miss for the rule above. A zero-gold effect would be harmless downstream -
	# give_gold refuses it - but an effect list that carries entries meaning nothing is how
	# a list stops being readable.
	var battle := _fight(_enemy(4))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	for effect: Dictionary in battle.effects():
		assert_str(str(effect.get("op"))).is_not_equal(String(GameContext.OP_GOLD))

func test_losing_pays_nothing() -> void:
	# A defeat's effects are discarded wholesale by the world, but the list itself must not
	# claim a payout either - the fight never writes, and that includes what it says it did.
	var battle := _fight(_enemy(99, 40, 0, 5, false, 7), 3)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.outcome()).override_failure_message(
		"the fight did not end in defeat, so this proves nothing about a loss") \
		.is_equal(BattleLogic.Outcome.DEFEAT)
	for effect: Dictionary in battle.effects():
		assert_str(str(effect.get("op"))).is_not_equal(String(GameContext.OP_GOLD))

func test_winning_reports_the_party_it_leaves_behind() -> void:
	var battle := _fight(_enemy(4))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var party := {}
	for effect: Dictionary in battle.effects():
		if effect.get("op") == GameContext.OP_PARTY:
			party = effect
	assert_int(int(party.get("xp", -1))).is_equal(5)
	assert_int(int(party.get("level", -1))).is_equal(1)
	assert_int(int(party.get("hp", -1))).is_equal(20)

func test_nine_xp_is_not_a_level_and_ten_is() -> void:
	# The threshold from both sides, at literal values, against a curve of [10, 12].
	var below := _fight(_enemy(4, 3, 1, 9))
	below.press()
	_until_leaves(below, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(below, BattleLogic.Phase.MESSAGE)
	assert_int(below.player_level()).is_equal(1)

	var exact := _fight(_enemy(4, 3, 1, 10))
	exact.press()
	_until_leaves(exact, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(exact, BattleLogic.Phase.MESSAGE)
	assert_int(exact.player_level()).is_equal(2)

func test_a_level_restores_the_player_completely() -> void:
	# The loop the whole design rests on: ambient fights are what make the boss survivable.
	var battle := _fight(_enemy(4, 3, 1, 10), 6)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.player_level()).is_equal(2)
	assert_int(battle.player_hp()).is_equal(24)

func test_winning_without_a_level_does_not_heal() -> void:
	# The control: the heal belongs to the level-up, not to winning.
	var battle := _fight(_enemy(4, 3, 1, 5), 6)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.player_level()).is_equal(1)
	assert_int(battle.player_hp()).is_equal(6)


# -- losing --------------------------------------------------------------------------------

func test_the_player_can_actually_lose() -> void:
	var battle := _fight(_enemy(99, 40), 3)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_bool(battle.finished()).is_true()
	assert_int(battle.outcome()).is_equal(BattleLogic.Outcome.DEFEAT)
	assert_int(battle.player_hp()).is_equal(0)

func test_a_defeat_leaves_nothing_to_carry_out() -> void:
	# A lost fight is discarded by the world, so nothing durable may be collected - above all
	# not the seen key, which would delete an enemy that just won.
	var battle := _fight(_enemy(99, 40), 3)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	for effect: Dictionary in battle.effects():
		assert_str(str(effect.get("op"))).is_not_equal(String(GameContext.OP_SEEN))
		assert_str(str(effect.get("op"))).is_not_equal(String(GameContext.OP_PARTY))


# -- the collected list --------------------------------------------------------------------

func test_a_fight_in_progress_has_earned_nothing() -> void:
	var battle := _fight(_enemy(99))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	assert_int(battle.effects().size()).is_equal(0)

func test_reading_the_effects_cannot_change_them() -> void:
	var battle := _fight(_enemy(4))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var taken := battle.effects()
	taken.clear()
	assert_int(battle.effects().size()).is_greater(0)

func test_ticking_past_the_end_cannot_award_a_fight_twice() -> void:
	# The failure a view emitting twice would otherwise produce: xp paid out per visit to the
	# end of the fight rather than per fight.
	var battle := _fight(_enemy(4))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var earned := battle.effects().size()
	for i in 120:
		battle.tick()
		battle.press()
	assert_int(battle.effects().size()).is_equal(earned)


# -- content coverage ----------------------------------------------------------------------

func test_an_enemy_with_two_moves_uses_both_across_seeds() -> void:
	# A perfect driver only visits the branches perfect play reaches, and an enemy that only
	# ever used its first move would look completely healthy from the outside - every fight
	# still won, every message still printed. This walks a BOUNDED set of seeds and fails if
	# any move never came up, because the absence of a move is the finding.
	var enemy := _enemy(999)
	var names := {}
	for seed_value in 40:
		var battle := BattleLogic.of(_combat(), enemy, 999, 0, 1, [], "map/foe", seed_value)
		battle.press()
		_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
		_until_leaves(battle, BattleLogic.Phase.MESSAGE)
		_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
		for move: Dictionary in enemy.moves:
			if battle.message().contains(str(move.get("name", ""))):
				names[str(move.get("name", ""))] = true
	assert_int(names.size()).override_failure_message(
		"only %s of the enemy's %d moves were ever drawn across 40 seeds - a move nothing can roll is content that ships unreachable"
			% [names.keys(), enemy.moves.size()]
	).is_equal(enemy.moves.size())

func test_the_same_seed_replays_the_same_fight() -> void:
	var first := ""
	var second := ""
	for pass_index in 2:
		var battle := BattleLogic.of(_combat(), _enemy(999), 999, 0, 1, [], "map/foe", 11)
		var log := ""
		for round_index in 4:
			battle.press()
			_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
			_until_leaves(battle, BattleLogic.Phase.MESSAGE)
			_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
			log += battle.message() + "|"
			_until_leaves(battle, BattleLogic.Phase.MESSAGE)
		if pass_index == 0:
			first = log
		else:
			second = log
	assert_str(second).is_equal(first)

func test_a_different_seed_draws_differently() -> void:
	# The control. A generator that ignores its seed replays perfectly and is useless.
	var logs := {}
	for seed_value in 12:
		var battle := BattleLogic.of(_combat(), _enemy(999), 999, 0, 1, [], "map/foe", seed_value)
		var log := ""
		for round_index in 4:
			battle.press()
			_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
			_until_leaves(battle, BattleLogic.Phase.MESSAGE)
			_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
			log += battle.message() + "|"
			_until_leaves(battle, BattleLogic.Phase.MESSAGE)
		logs[log] = true
	assert_int(logs.size()).is_greater(1)

func test_a_cue_reports_its_own_full_length() -> void:
	# The view draws the wind-up as a fraction of this rather than keeping its own copy of the
	# frame counts. Asked of the logic so that a retune moves the animation with the rule -
	# the lean IS the anticipation, and the `!` only lights once the window is already open.
	var battle := _fight()
	battle.press()
	assert_int(battle.cue_span()).override_failure_message(
		"the player's wind-up does not report its own length").is_equal(CUE)
	# Forward through the impact and the line it prints, until the enemy's own swing is up.
	# Bounded, and it asserts it arrived: a "drive until you see X" loop over a machine that
	# can stall is how a suite hangs instead of failing.
	var reached := false
	for i in 500:
		battle.tick()
		if battle.phase() == BattleLogic.Phase.ENEMY_ACT:
			reached = true
			break
	assert_bool(reached).override_failure_message(
		"the enemy never took its turn").is_true()
	assert_int(battle.cue_span()).override_failure_message(
		"the enemy's swing reports the player's wind-up length, so the two read alike"
	).is_equal(DEFEND_CUE)

func test_outside_a_cue_the_span_is_safe_to_divide_by() -> void:
	# One, not zero: every caller divides by this, and a phase with no wind-up should read as
	# "finished" rather than take the frame down with it.
	var battle := _fight()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.cue_span()).is_equal(1)

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
	out.base_mp = 8
	out.mp_per_level = 3
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
		curve: Array[int] = [10, 12], attack_mod := 0, defense_mod := 0, mp := 8,
		spells: Array = []) -> BattleLogic:
	var foe := enemy if enemy != null else _enemy()
	return BattleHelpers.solo(_combat(curve), foe, hp, xp, level, items, attack_mod,
		defense_mod, mp, spells)

## Two on the player's side, for the rules that only exist once there is somebody else: the
## ally cursor, who the enemy aims at, a round of declarations, and a fight that survives one
## of them falling.
func _party_fight(enemy: EnemyDef = null, leader_hp := 20, friend_hp := 16, items: Array = [],
		leader_spells: Array = [], friend_spells: Array = [], seed_value := 7) -> BattleLogic:
	var foe := enemy if enemy != null else _enemy()
	var curve := _combat()
	return BattleLogic.of(curve, foe, [
		BattleHelpers.leader(curve, leader_hp, 0, 1, 8, 0, 0, leader_spells),
		BattleHelpers.companion(&"rook", curve, "Rook", friend_hp, 0, 1, 4, 0, 0, friend_spells),
	], items, "map/foe", seed_value)

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

## Attacks with whoever has the turn and carries the fight through to whoever gets it next.
##
## A party fight only reaches the second member's menu THROUGH the first member's swing, so a
## test that wants to read what member 1 is offered has to let member 0 act. Asserts it arrived
## rather than assuming: landing somewhere else - the enemy's turn, a won fight - would otherwise
## have the test read member 0's page a second time and pass for the wrong reason.
func _to_the_next_member(battle: BattleLogic, who := 1) -> void:
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.commander()).override_failure_message(
		"the turn did not reach member %d after a swing" % who).is_equal(who)

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
	# Attack, Magic, Item, Flee. A literal rather than Row.size(), which is what size() returns -
	# an assertion written against the thing under test agrees with it however it changes.
	assert_int(battle.size()).is_equal(4)
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
	var before := battle.member_hp(0)
	_tick_to(battle, WINDOW)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	# Clout is 9 - 1 defense = 8, halved to 4. Exact, so a block that did nothing reads as 8.
	assert_int(before - battle.member_hp(0)).is_equal(4)

func test_an_unblocked_enemy_hit_is_not() -> void:
	var battle := _fight(_one_move_enemy())
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var before := battle.member_hp(0)
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	assert_int(before - battle.member_hp(0)).is_equal(8)

func test_a_blocked_hit_still_takes_something_off() -> void:
	# The floor, from the other side: blocking a hit that was only worth one point must not
	# round down to a fight where defending is free.
	var battle := _fight(_one_move_enemy(99, 2))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var before := battle.member_hp(0)
	_tick_to(battle, WINDOW)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	assert_int(before - battle.member_hp(0)).is_equal(1)


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


# -- magic ---------------------------------------------------------------------------------

func _spell(kind: int, cost := 3, power := 7, turns := 0, name := "Ember") -> BattleLogic.SpellRow:
	return BattleLogic.SpellRow.of(StringName(name.to_lower()), name, cost, kind, power, turns)

## Opens the spell page. Named rather than counted, the whole reason Row is an enum.
func _to_the_spells(battle: BattleLogic) -> void:
	battle.move(BattleLogic.Row.MAGIC)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"the Magic command did not open the spell page").is_equal(BattleLogic.Phase.SPELLS)

func test_the_magic_command_opens_the_spell_page() -> void:
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.ATTACK)])
	_to_the_spells(battle)
	assert_int(battle.index()).is_equal(0)
	assert_int(battle.size()).is_equal(1)

func test_a_player_who_knows_nothing_still_has_a_page_to_read() -> void:
	# The empty-bag rule: a page with no rows is one the cursor cannot stand on. It must also
	# not be pressable, or the confirm falls through to whatever a null row would do.
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 8, [])
	_to_the_spells(battle)
	assert_int(battle.size()).is_equal(1)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"pressing an empty spell page did something").is_equal(BattleLogic.Phase.SPELLS)
	assert_int(battle.member_mp(0)).is_equal(8)

func test_casting_an_attack_spends_the_magic_and_ignores_armour() -> void:
	# Flat damage is what gives magic a job beside a stronger swing. Asserted against an enemy
	# with real armour, because against a defenceless one "flat" and "attack minus defense"
	# agree and the test would prove nothing.
	var battle := _fight(_enemy(99, 3, 5), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.ATTACK, 3, 7)])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.enemy_hp()).override_failure_message(
		"the enemy's armour took something off a spell").is_equal(92)
	assert_int(battle.member_mp(0)).is_equal(5)

func test_casting_costs_the_turn() -> void:
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.ATTACK)])
	_to_the_spells(battle)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).override_failure_message(
		"a cast was free - the enemy never got its turn").is_equal(BattleLogic.Phase.ENEMY_ACT)

func test_an_attack_spell_can_finish_a_fight() -> void:
	var battle := _fight(_enemy(4, 3, 5), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.ATTACK, 3, 7)])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.outcome()).override_failure_message(
		"a killing blow from a spell did not win the fight") \
		.is_equal(BattleLogic.Outcome.VICTORY)

func test_a_heal_spell_restores_and_cannot_overheal() -> void:
	var battle := _fight(_enemy(99), 5, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.HEAL, 4, 8, 0, "Mend")])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.member_hp(0)).is_equal(13)
	assert_int(battle.member_mp(0)).is_equal(4)

	var full := _fight(_enemy(99), 18, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.HEAL, 4, 8, 0, "Mend")])
	_to_the_spells(full)
	full.press()
	assert_int(full.member_hp(0)).is_equal(20)

func test_a_spell_beyond_the_purse_is_refused_and_costs_nothing() -> void:
	# Refused, SAID, and not the turn either - money's precedent. The MP is the assertion that
	# matters: a refusal that charged would be worse than one that cast.
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 2,
		[_spell(SpellDef.Kind.ATTACK, 3, 7)])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.member_mp(0)).override_failure_message(
		"a refused cast still took the magic").is_equal(2)
	assert_int(battle.enemy_hp()).override_failure_message(
		"a refused cast still hit something").is_equal(99)
	assert_str(battle.message()).contains("Not enough")
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).override_failure_message(
		"a refused cast cost the turn").is_equal(BattleLogic.Phase.SPELLS)

func test_exactly_enough_magic_casts() -> void:
	# The control for the refusal above, one point away from it: a check written as `<` rather
	# than `<=` refuses the spell a player has saved up exactly enough for.
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 3,
		[_spell(SpellDef.Kind.ATTACK, 3, 7)])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.member_mp(0)).is_equal(0)
	assert_int(battle.enemy_hp()).is_equal(92)

func test_a_sleeping_enemy_loses_its_turns_and_then_wakes() -> void:
	# Two turns means two turns, counted where they are taken. The wake-up is the half that
	# matters: a sleep that never ended would end the fight, not shape it.
	var battle := _fight(_enemy(99, 3, 0), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.SLEEP, 5, 0, 2, "Lull")])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.enemy_asleep_turns()).is_equal(2)

	# The cast's own line, and then the skipped turn's, run back to back - _until_leaves walks
	# both, because leaving a message is what opens the next one. The fight lands back on the
	# menu having never run an enemy cue at all.
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).override_failure_message(
		"a sleeping enemy still telegraphed a blow").is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.enemy_asleep_turns()).is_equal(1)
	assert_int(battle.member_hp(0)).override_failure_message(
		"a sleeping enemy hit the player anyway").is_equal(20)

	# Swing, and it sleeps through that turn too - the second of the two it was promised.
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.enemy_asleep_turns()).is_equal(0)
	assert_int(battle.member_hp(0)).is_equal(20)

	# Swing again: awake now, and it acts. Without this the test could not tell a sleep from an
	# enemy that simply never gets a turn.
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).override_failure_message(
		"the enemy never woke up").is_equal(BattleLogic.Phase.ENEMY_ACT)
	_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	assert_int(battle.member_hp(0)).override_failure_message(
		"the enemy woke and still did nothing").is_less(20)

func test_cancel_backs_out_of_the_spell_page_onto_its_own_row() -> void:
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.ATTACK)])
	_to_the_spells(battle)
	assert_bool(battle.cancel()).is_true()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.index()).override_failure_message(
		"backing out of the spells landed the cursor somewhere else") \
		.is_equal(BattleLogic.Row.MAGIC)

func test_what_the_screen_may_dim_is_what_the_press_will_refuse() -> void:
	# One function answers both, so a spell drawn as reachable and refused on press - or the
	# reverse, which is worse - cannot happen.
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 3,
		[_spell(SpellDef.Kind.ATTACK, 3, 7), _spell(SpellDef.Kind.HEAL, 4, 8, 0, "Mend")])
	_to_the_spells(battle)
	assert_bool(battle.can_afford(battle.spell_row(0))).is_true()
	assert_bool(battle.can_afford(battle.spell_row(1))).is_false()
	assert_bool(battle.can_afford(battle.spell_row(9))).override_failure_message(
		"a row that does not exist reported as castable").is_false()

## What one member's record in the sealed party effect says. The leader is the empty id, which
## is the id a solo fight's only member carries.
func _sealed(battle: BattleLogic, member := &"") -> Dictionary:
	for effect: Dictionary in battle.effects():
		if effect.get("op") != GameContext.OP_PARTY:
			continue
		for who: Variant in effect.get("members", []):
			var record: Dictionary = who
			if StringName(str(record.get("id", ""))) == member:
				return record
	return {}

func test_magic_spent_in_a_fight_is_what_the_fight_hands_back() -> void:
	var battle := _fight(_enemy(4, 3, 5), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.ATTACK, 3, 7)])
	_to_the_spells(battle)
	battle.press()
	var party := _sealed(battle)
	assert_int(int(party.get("mp", -1))).override_failure_message(
		"the fight reported magic it had already spent").is_equal(5)


# -- items ---------------------------------------------------------------------------------

func test_a_tonic_heals_and_costs_the_turn() -> void:
	var battle := _fight(_enemy(99), 10, 0, 1, [_tonic()])
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ITEMS)
	battle.press()
	assert_int(battle.member_hp(0)).is_equal(20)
	# Straight to the enemy's turn: no free drink.
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ENEMY_ACT)

func test_a_tonic_cannot_overheal() -> void:
	var battle := _fight(_enemy(99), 18, 0, 1, [_tonic()])
	battle.move(BattleLogic.Row.ITEM)
	battle.press()
	battle.press()
	assert_int(battle.member_hp(0)).is_equal(20)

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
	assert_int(armed.attack_mod(0)).is_equal(4)

func test_armour_takes_the_edge_off_every_hit() -> void:
	var bare := _fight(_enemy(99, 20))
	var plated := _fight(_enemy(99, 20), 20, 0, 1, [], [10, 12], 0, 3)
	for battle in [bare, plated]:
		battle.press()
		_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
		_until_leaves(battle, BattleLogic.Phase.MESSAGE)
		_until_leaves(battle, BattleLogic.Phase.ENEMY_ACT)
	assert_int(plated.member_hp(0)).override_failure_message(
		"armour changed nothing: bare %d hp, plated %d hp" % [bare.member_hp(0), plated.member_hp(0)]) \
		.is_greater(bare.member_hp(0))
	assert_int(plated.defense_mod(0)).is_equal(3)

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
	var party := _sealed(battle)
	assert_int(int(party.get("xp", -1))).is_equal(5)
	assert_int(int(party.get("level", -1))).is_equal(1)
	assert_int(int(party.get("hp", -1))).is_equal(20)
	# Magic is reported alongside them or the world writes zero over whatever the player had -
	# a key the sink reads with a default of nought is a key that must always be written.
	assert_int(int(party.get("mp", -1))).override_failure_message(
		"the fight sealed without saying what magic it left behind").is_equal(8)

func test_a_fight_hands_back_the_magic_it_was_given() -> void:
	# Nothing spends MP yet, so this is the whole rule: a fight must not be a place magic goes
	# missing. It is asserted at a value that is neither empty nor full, because a fight that
	# sealed max_mp and one that sealed the player's own number agree at both ends.
	var battle := _fight(_enemy(4), 20, 0, 1, [], [10, 12], 0, 0, 5)
	assert_int(battle.member_mp(0)).is_equal(5)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	var party := _sealed(battle)
	assert_int(int(party.get("mp", -1))).is_equal(5)

func test_more_magic_than_the_level_allows_is_clamped_to_the_curve() -> void:
	# A hand-edited save describing a player the curve cannot produce. The fight is not the
	# place to argue with it - hp is clamped on the way in for the same reason.
	var battle := _fight(_enemy(4), 20, 0, 1, [], [10, 12], 0, 0, 99)
	assert_int(battle.member_max_mp(0)).is_equal(8)
	assert_int(battle.member_mp(0)).is_equal(8)

func test_levelling_up_restores_the_magic_as_well_as_the_health() -> void:
	# "Completely" has to mean completely once there is magic. A level that refilled hp and left
	# the caster empty would make the reward read as half-broken.
	var battle := _fight(_enemy(4, 3, 1, 10), 5, 0, 1, [], [10, 12], 0, 0, 1)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.member_level(0)).override_failure_message(
		"the fight did not level anyone, so this proves nothing about levelling").is_equal(2)
	# Level 2 of an 8 + 3 curve.
	assert_int(battle.member_mp(0)).is_equal(11)

func test_nine_xp_is_not_a_level_and_ten_is() -> void:
	# The threshold from both sides, at literal values, against a curve of [10, 12].
	var below := _fight(_enemy(4, 3, 1, 9))
	below.press()
	_until_leaves(below, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(below, BattleLogic.Phase.MESSAGE)
	assert_int(below.member_level(0)).is_equal(1)

	var exact := _fight(_enemy(4, 3, 1, 10))
	exact.press()
	_until_leaves(exact, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(exact, BattleLogic.Phase.MESSAGE)
	assert_int(exact.member_level(0)).is_equal(2)

func test_a_level_restores_the_player_completely() -> void:
	# The loop the whole design rests on: ambient fights are what make the boss survivable.
	var battle := _fight(_enemy(4, 3, 1, 10), 6)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.member_level(0)).is_equal(2)
	assert_int(battle.member_hp(0)).is_equal(24)

func test_winning_without_a_level_does_not_heal() -> void:
	# The control: the heal belongs to the level-up, not to winning.
	var battle := _fight(_enemy(4, 3, 1, 5), 6)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.member_level(0)).is_equal(1)
	assert_int(battle.member_hp(0)).is_equal(6)


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
	assert_int(battle.member_hp(0)).is_equal(0)

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
		var battle := BattleHelpers.solo(_combat(), enemy, 999, 0, 1, [], 0, 0, 8, [], seed_value)
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
		var battle := BattleHelpers.solo(_combat(), _enemy(999), 999, 0, 1, [], 0, 0, 8, [], 11)
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
		var battle := BattleHelpers.solo(_combat(), _enemy(999), 999, 0, 1, [], 0, 0, 8, [], seed_value)
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


# -- a party ---------------------------------------------------------------------------------
#
# Everything below only exists once somebody else is standing. The rules a solo fight already
# proved are not repeated here; what is proved is the round, the cursor, and what falling means.

func test_a_solo_fight_asks_one_member_and_swings_at_once() -> void:
	# The control the whole milestone rests on: with one member, choosing Attack goes straight
	# into the cue exactly as it did before there was a round to declare.
	var battle := _fight(_enemy(99))
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"a solo Attack stopped going straight into its cue").is_equal(BattleLogic.Phase.PLAYER_ACT)

func test_a_member_swings_the_moment_they_choose() -> void:
	# The rule this milestone is named for. Choosing Attack SWINGS - the second member is not
	# asked first. Playing the shipped round, a player read the pause as the game ignoring them.
	var battle := _party_fight(_enemy(99))
	assert_int(battle.commander()).is_equal(0)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"the first member's Attack did not swing when it was chosen") \
		.is_equal(BattleLogic.Phase.PLAYER_ACT)
	assert_int(battle.acting_member()).override_failure_message(
		"somebody other than the member who chose is swinging").is_equal(0)

func test_the_menu_passes_to_the_next_member_after_the_swing() -> void:
	# AFTER, and the enemy's health is what proves it. Asserting only "the menu reached member 1"
	# passes against a round that asks everybody first and swings later - the shipped shape this
	# test exists to reject - because the cursor arrives there either way.
	var battle := _party_fight(_enemy(99))
	var before := battle.enemy_hp()
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.enemy_hp()).override_failure_message(
		"the second member was asked before the first member's blow had landed").is_less(before)
	assert_int(battle.phase()).override_failure_message(
		"the second member was never asked").is_equal(BattleLogic.Phase.MENU)
	assert_int(battle.commander()).override_failure_message(
		"the menu went to the wrong member").is_equal(1)

func test_the_enemy_waits_for_every_member() -> void:
	# The half of the old round that survives: the party still goes in order and the enemy
	# still goes last. Only the asking moved.
	var battle := _party_fight(_enemy(99))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	battle.press()
	assert_int(battle.acting_member()).override_failure_message(
		"the second member did not swing after the first").is_equal(1)
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).override_failure_message(
		"the enemy did not take its turn once the whole party had gone") \
		.is_equal(BattleLogic.Phase.ENEMY_ACT)

func test_a_cancel_on_the_menu_is_refused_mid_round_too() -> void:
	# There is nothing to take back any more: the previous member's act already happened, and a
	# cancel that unwound it would be undoing damage the enemy has already been dealt. So the
	# pre-party rule holds for everybody - a fight is left by winning, losing or fleeing.
	var battle := _party_fight(_enemy(99))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.commander()).is_equal(1)
	assert_bool(battle.cancel()).override_failure_message(
		"cancel unwound an act that had already landed").is_false()

func test_a_solo_cancel_on_the_menu_is_still_refused() -> void:
	# The control, and now the same rule rather than a coincidence of having nobody to take an
	# order back from.
	var battle := _fight(_enemy(99))
	assert_bool(battle.cancel()).is_false()

func test_a_heal_asks_who_when_there_is_somebody_to_ask_about() -> void:
	var battle := _party_fight(_enemy(99), 20, 16, [],
		[_spell(SpellDef.Kind.HEAL, 3, 8, 0, "Mend")])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"a heal in a party did not open the ally cursor").is_equal(BattleLogic.Phase.ALLY)
	assert_int(battle.size()).override_failure_message(
		"the ally cursor did not offer both standing members").is_equal(2)

func test_a_solo_heal_never_asks() -> void:
	# A cursor with one row is a screen asking a question whose answer it already has - and it
	# is what would have moved every press count in every session recorded before M27.
	var battle := _fight(_enemy(99), 20, 0, 1, [], [10, 12], 0, 0, 8,
		[_spell(SpellDef.Kind.HEAL, 3, 8, 0, "Mend")])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"a solo heal opened a cursor with one row on it").is_not_equal(BattleLogic.Phase.ALLY)

func test_an_offense_spell_never_asks_who() -> void:
	# Still no ENEMY cursor: fights here are one foe, so the question has one answer.
	var battle := _party_fight(_enemy(99), 20, 16, [], [_spell(SpellDef.Kind.ATTACK)])
	_to_the_spells(battle)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"an offense spell asked which enemy").is_not_equal(BattleLogic.Phase.ALLY)

func test_the_heal_lands_on_the_member_the_cursor_chose() -> void:
	var battle := _party_fight(_enemy(99), 20, 8, [],
		[_spell(SpellDef.Kind.HEAL, 3, 8, 0, "Mend")])
	_to_the_spells(battle)
	battle.press()
	# The cursor opens on the caster; one step moves it to the wounded companion.
	battle.move(1)
	battle.press()
	# Second member declares an attack, then the round runs.
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.member_hp(1)).override_failure_message(
		"the heal did not land on the member the cursor was on").is_equal(16)

func test_cancelling_the_ally_cursor_goes_back_to_the_spell_page() -> void:
	var battle := _party_fight(_enemy(99), 20, 16, [],
		[_spell(SpellDef.Kind.HEAL, 3, 8, 0, "Mend")])
	_to_the_spells(battle)
	battle.press()
	assert_bool(battle.cancel()).is_true()
	assert_int(battle.phase()).override_failure_message(
		"cancelling the ally cursor did not return to the page it came from") \
		.is_equal(BattleLogic.Phase.SPELLS)
	assert_int(battle.member_mp(0)).override_failure_message(
		"backing out of a target cost magic anyway").is_equal(8)

func test_each_member_casts_from_their_own_spell_list() -> void:
	var battle := _party_fight(_enemy(99), 20, 16, [],
		[_spell(SpellDef.Kind.ATTACK, 3, 7, 0, "Ember")],
		[_spell(SpellDef.Kind.HEAL, 4, 8, 0, "Mend")])
	assert_int(battle.spell_rows().size()).is_equal(1)
	assert_str((battle.spell_row(0) as BattleLogic.SpellRow).name).override_failure_message(
		"the first member was offered somebody else's spells").is_equal("Ember")
	_to_the_next_member(battle)
	assert_str((battle.spell_row(0) as BattleLogic.SpellRow).name).override_failure_message(
		"the second member was offered the first member's spells").is_equal("Mend")

func test_affordability_follows_whoever_is_choosing() -> void:
	# One function decides what the screen dims and what the press refuses, so with two members
	# it has to be reading the RIGHT member's purse.
	var battle := _party_fight(_enemy(99), 20, 16, [],
		[_spell(SpellDef.Kind.ATTACK, 6, 7, 0, "Ember")],
		[_spell(SpellDef.Kind.ATTACK, 6, 7, 0, "Ember")])
	assert_bool(battle.can_afford(battle.spell_row(0))).override_failure_message(
		"the leader could not afford a spell they had the magic for").is_true()
	_to_the_next_member(battle)
	# The companion carries 4 mp against a cost of 6.
	assert_bool(battle.can_afford(battle.spell_row(0))).override_failure_message(
		"a spell the companion cannot pay for was offered as affordable").is_false()

func test_one_member_falling_does_not_end_the_fight() -> void:
	# The rule in every reference game: the survivors fight on, and the fallen stay down.
	var battle := _party_fight(_enemy(99, 40), 20, 1)
	# Played by mashing: press whenever somebody is being asked, tick otherwise. With every
	# choice acting on the spot, a loop that only ticks stalls forever on the next member's menu
	# and nobody ever gets hit - the fight would look peaceful rather than fail.
	for i in 600:
		if battle.finished() or battle.member_down(0) or battle.member_down(1):
			break
		if battle.phase() == BattleLogic.Phase.MENU:
			battle.press()
		else:
			battle.tick()
	assert_bool(battle.member_down(0) or battle.member_down(1)).override_failure_message(
		"nobody fell in a fight against something that hits for forty").is_true()
	# Ticked PAST the line rather than read at the moment of the blow: a fight that is ending
	# spends the message frames in MESSAGE either way, so finished() answers false for both a
	# fight that goes on and one that is already over. The outcome is the thing that differs.
	for i in 200:
		if battle.phase() != BattleLogic.Phase.MESSAGE:
			break
		battle.tick()
	assert_int(battle.outcome()).override_failure_message(
		"the fight was lost when one of two members fell").is_equal(BattleLogic.Outcome.NONE)
	assert_bool(battle.finished()).override_failure_message(
		"the fight ended when one of two members fell").is_false()

func test_the_fight_is_lost_only_when_everybody_is_down() -> void:
	var battle := _party_fight(_enemy(99, 40), 1, 1)
	for i in 2000:
		if battle.finished():
			break
		battle.press()
		battle.tick()
	assert_int(battle.outcome()).override_failure_message(
		"a party wiped out did not lose the fight").is_equal(BattleLogic.Outcome.DEFEAT)

func test_a_fallen_member_earns_nothing_and_the_standing_earn_everything() -> void:
	# Dragon Quest's rule: every living member takes the full award, and nobody divides it.
	# The fallen earn nothing, which is both series' rule.
	var curve := _combat()
	var battle := BattleLogic.of(curve, _enemy(4), [
		BattleHelpers.leader(curve, 20, 0, 1, 8),
		BattleHelpers.companion(&"rook", curve, "Rook", 0, 0, 1, 4),
	], [], "map/foe", 7)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.outcome()).is_equal(BattleLogic.Outcome.VICTORY)
	assert_int(_sealed(battle).get("xp", -1)).override_failure_message(
		"the member who was standing did not earn the full award").is_equal(5)
	assert_int(_sealed(battle, &"rook").get("xp", -1)).override_failure_message(
		"a member who was down through the whole fight earned experience").is_equal(0)

func test_a_fallen_member_is_never_asked_for_an_order() -> void:
	var curve := _combat()
	var battle := BattleLogic.of(curve, _enemy(99), [
		BattleHelpers.leader(curve, 20, 0, 1, 8),
		BattleHelpers.companion(&"rook", curve, "Rook", 0, 0, 1, 4),
	], [], "map/foe", 7)
	assert_int(battle.commander()).is_equal(0)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"the round waited for an order from somebody who is down") \
		.is_equal(BattleLogic.Phase.PLAYER_ACT)

func test_the_seal_carries_every_member_by_id() -> void:
	# The leader's swing ends it before the companion is ever asked, which is the sharper case:
	# a member who did nothing this fight still has to come back in the sealed party, or the
	# world would write them out of existence on the way home.
	var battle := _party_fight(_enemy(4))
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.outcome()).is_equal(BattleLogic.Outcome.VICTORY)
	assert_dict(_sealed(battle)).override_failure_message(
		"the leader was left out of the sealed party").is_not_empty()
	assert_dict(_sealed(battle, &"rook")).override_failure_message(
		"the companion was left out of the sealed party").is_not_empty()

func test_the_enemy_aims_at_somebody_who_is_standing() -> void:
	var battle := _party_fight(_enemy(99))
	_to_the_next_member(battle)
	battle.press()
	_until_leaves(battle, BattleLogic.Phase.PLAYER_ACT)
	_until_leaves(battle, BattleLogic.Phase.MESSAGE)
	assert_int(battle.phase()).is_equal(BattleLogic.Phase.ENEMY_ACT)
	var aimed := battle.target_member()
	assert_bool(aimed >= 0 and aimed < 2).override_failure_message(
		"the enemy aimed at member %d, which is not in the party" % aimed).is_true()
	assert_bool(battle.member_down(aimed)).override_failure_message(
		"the enemy aimed at somebody who was already down").is_false()

func test_the_same_seed_aims_the_enemy_the_same_way() -> void:
	# The whole determinism story, extended to the one new draw a party adds.
	var first: Array[int] = []
	var second: Array[int] = []
	for run in 2:
		var battle := _party_fight(_enemy(999), 200, 200, [], [], [], 5)
		for i in 900:
			if battle.finished():
				break
			battle.press()
			if battle.phase() == BattleLogic.Phase.ENEMY_ACT and battle.target_member() >= 0:
				var into := first if run == 0 else second
				if into.is_empty() or into[into.size() - 1] != battle.target_member():
					into.append(battle.target_member())
			battle.tick()
	assert_array(second).override_failure_message(
		"the same seed aimed the enemy differently on a replay").is_equal(first)
	assert_bool(first.size() > 1).override_failure_message(
		"the replay compared fewer than two draws, so it proves nothing").is_true()

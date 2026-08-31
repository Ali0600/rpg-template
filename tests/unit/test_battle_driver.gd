extends GdUnitTestSuite
## What the balance gate's drivers DO, as opposed to what the fights they play come out as.
##
## `test_battle_content.gd` asserts over shipped content, which is the right place for "every
## item is used somewhere" - and it is the wrong place for a rule the shipped content cannot
## distinguish. Two of this driver's rules are exactly that: with a bag of three tonics and three
## loaves, a driver that always reaches for the first row still empties the first stack and moves
## on to the second, and a driver that drinks when nobody is hurt still stops once the bag is
## gone. Both mutants SURVIVED the content suite for that reason, and neither is dead code - the
## content just happens to mask them. So the rules are pinned here, against a bag that outlasts
## the fight.

const CUE := 12
const WINDOW := 6
const MESSAGE := 6

func _combat(curve: Array[int] = [10, 12]) -> CombatDef:
	var out := CombatDef.new()
	out.id = &"drive_combat"
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 5
	out.attack_per_level = 2
	out.base_defense = 1
	out.base_mp = 0
	out.xp_curve = curve
	out.attack_cue_frames = CUE
	out.defend_cue_frames = CUE
	out.timed_window_frames = WINDOW
	out.message_frames = MESSAGE
	return out

func _enemy(hp := 40, power := 3) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"drive_foe"
	out.name = "Drive Foe"
	out.character = &"quest_slink"
	out.max_hp = hp
	out.attack = 6
	out.defense = 0
	out.moves = [{"name": "Swipe", "power": power}]
	return out

## A bag that OUTLASTS the fight - which is the whole point of this suite. The content's bag
## empties, and an emptied bag makes "reach for the first row" and "reach for the next row" the
## same driver: the first stack runs out and the second is all that is left.
func _deep_bag() -> Array:
	return [
		BattleLogic.ItemRow.of(&"tonic", "Tonic", 99, 4),
		BattleLogic.ItemRow.of(&"waybread", "Waybread", 99, 2),
	]

func _fight(items: Array, foe_power := 3, hp := 20) -> BattleLogic:
	var curve := _combat()
	return BattleLogic.of(curve, [_enemy(40, foe_power)],
		[BattleHelpers.leader(curve, hp, 0, 1, 0, 0, 0, [])], items, "map/foe", 7)

func test_the_drinker_walks_the_whole_bag_rather_than_the_first_row() -> void:
	# Against a bag deep enough that no stack ever runs out, "the first row" and "the next row"
	# come apart - and a driver that only ever reached for the strongest tonic would exercise one
	# row of the bag while reporting on all of it. That is the same blindness the policy itself
	# exists to fix, one level down.
	var report := BattleDriver.play(_fight(_deep_bag()), BattleDriver.Policy.DRINKER)
	assert_str(report.fault).is_empty()
	assert_int(report.used.size()).override_failure_message(
		"the drinker never used anything, so the rotation below is untested").is_greater(1)
	# The CONSECUTIVE pair is the assertion, not the set. "Both were used eventually" is satisfied
	# by a driver that empties the first stack and then has nowhere else to go - measured: against
	# 99 tonics it drank all 99 before touching the bread, because this fight outlasts them. What
	# distinguishes reaching for the next row from reaching for the first is that the SECOND use
	# differs from the first.
	assert_str(String(report.used[1])).override_failure_message(
		"the drinker reached for '%s' twice running out of a bag with two things in it"
		% [report.used[0]]).is_not_equal(String(report.used[0]))
	var seen := {}
	for id: StringName in report.used:
		seen[id] = true
	assert_int(seen.size()).override_failure_message(
		"the drinker used only %s out of a bag with two things in it" % [seen.keys()]).is_equal(2)

func test_the_drinker_leaves_the_bag_alone_when_nobody_is_hurt() -> void:
	# An item used on somebody already whole spends the turn and heals nought, so the guard is
	# what keeps the driver swinging at all.
	#
	# Asserted on the DECISION rather than on how a whole fight comes out, because a fight cannot
	# stage "nobody is ever hurt": a move with zero power still lands the enemy's attack stat, so
	# there is no harmless foe to fight. A first draft tried one and the party took five a turn.
	var whole := _fight(_deep_bag())
	assert_bool(BattleDriver._will_drink(whole, BattleDriver.Policy.DRINKER)) \
		.override_failure_message("the drinker reached for the bag with everybody whole").is_false()
	assert_int(BattleDriver._row_to_choose(whole, BattleDriver.Policy.DRINKER)) \
		.override_failure_message("an untouched party opened the bag instead of swinging") \
		.is_equal(BattleLogic.Row.ATTACK)

func test_the_drinker_reaches_for_the_bag_once_somebody_is_hurt() -> void:
	# The other half, and the control: without it the test above passes just as well against a
	# driver that never drinks at all, which is a rule about nothing.
	var hurt := _fight(_deep_bag(), 3, 8)
	assert_bool(BattleDriver._will_drink(hurt, BattleDriver.Policy.DRINKER)) \
		.override_failure_message("a wounded party was not offered its own bag").is_true()
	assert_int(BattleDriver._row_to_choose(hurt, BattleDriver.Policy.DRINKER)) \
		.is_equal(BattleLogic.Row.ITEM)

func test_only_the_drinker_is_offered_the_bag() -> void:
	# The guard's other half: `_will_drink` gates on the POLICY as well as on the party, so a
	# wounded party under any other driver still swings.
	var hurt := _fight(_deep_bag(), 3, 8)
	for policy in [BattleDriver.Policy.PERFECT, BattleDriver.Policy.MASH,
			BattleDriver.Policy.CASTER]:
		assert_bool(BattleDriver._will_drink(hurt, policy)).override_failure_message(
			"policy %d was offered the bag" % policy).is_false()

func test_the_drinker_swings_when_the_bag_is_empty() -> void:
	# The fallback, and the reason the row is chosen at the MENU rather than coped with after the
	# page opens: a cancel is refused for everybody, so a driver that opened an empty bag would
	# press a dead row until the cap.
	var report := BattleDriver.play(_fight([]), BattleDriver.Policy.DRINKER)
	assert_str(report.fault).is_empty()
	assert_bool(report.ended).override_failure_message(
		"a drinker with no bag never finished the fight").is_true()
	assert_array(report.used).is_empty()

func test_the_caster_is_refused_the_bag_and_the_drinker_the_spell_page() -> void:
	# Each verb policy adds exactly ONE page, and the other stays a fault. Without this the two
	# could quietly merge into one do-everything driver, and a report would no longer be about
	# the verb it is named for.
	var casting := BattleDriver.play(_fight(_deep_bag()), BattleDriver.Policy.CASTER)
	assert_array(casting.used).override_failure_message(
		"the casting policy drank: %s" % [casting.used]).is_empty()
	assert_str(casting.fault).override_failure_message(
		"the casting driver was let into the bag").is_empty()
	var drinking := BattleDriver.play(_fight(_deep_bag()), BattleDriver.Policy.DRINKER)
	assert_array(drinking.casts).override_failure_message(
		"the drinking policy cast: %s" % [drinking.casts]).is_empty()

func test_the_two_aiming_policies_point_opposite_ways() -> void:
	# Aim is a policy axis, and it is the axis M34 found bounding coverage: with every driver
	# finishing the weakest foe first, a boss behind two mooks is never the target of anything.
	# Asserted on the ROWS the two helpers choose, because the fight resolves them the same frame.
	var curve := _combat()
	var small := _enemy(4)
	var big := _enemy(40)
	big.id = &"drive_big"
	big.name = "Drive Big"
	var battle := BattleLogic.of(curve, [small, big],
		[BattleHelpers.leader(curve, 20, 0, 1, 0, 0, 0, [])], [], "map/foe", 7)
	battle.press()
	assert_int(battle.phase()).override_failure_message(
		"a formation of two did not open the foe cursor").is_equal(BattleLogic.Phase.FOE)
	assert_int(BattleDriver._weakest_row(battle)).is_equal(0)
	assert_int(BattleDriver._toughest_row(battle)).override_failure_message(
		"the two aiming policies chose the same foe, so the axis does not exist").is_equal(1)

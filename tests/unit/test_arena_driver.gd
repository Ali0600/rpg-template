extends GdUnitTestSuite
## ArenaDriver's two policies, in arenas small enough to reason about.
##
## The driver is the balance gate's instrument, so what it does has to be pinned before anything
## is concluded from it: a PERFECT that swings at air or walks into what it is fighting would make
## every shipped fight look harder than it is, and a CHARGE that never swings would make them all
## look unwinnable by an unskilled player for a reason that has nothing to do with the fight.

const U := ArenaSim.UNITS_PER_TILE
const D := Dir.D


func _combat() -> CombatDef:
	var out := CombatDef.new()
	out.id = &"arena_driver_test"
	out.base_hp = 20
	out.base_attack = 5
	out.base_defense = 1
	out.xp_curve = [10, 20]
	out.swing_frames = 6
	out.hurt_frames = 20
	out.foe_hurt_frames = 10
	out.push_frames = 4
	out.arena_tiles = Vector2i(10, 6)
	return out


func _foe(hp := 12, attack := 3, speed := 0.0, chase := 0) -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"dummy"
	out.name = "Dummy"
	out.character = &"quest_slink"
	out.max_hp = hp
	out.attack = attack
	out.defense = 1
	out.moves = [{"name": "Bump", "power": 0}]
	out.speed_tiles_per_second = speed
	out.chase_every_frames = chase
	return out


func _sim(foe: EnemyDef) -> ArenaSim:
	var combat := _combat()
	return ArenaSim.of(combat, [foe], [BattleHelpers.leader(combat, 20)], "map/foe", 7,
		GameConfig.new())


func test_perfect_beats_a_foe_that_stands_still_without_a_touch_or_a_wasted_swing() -> void:
	var report := ArenaDriver.play(_sim(_foe(12)), ArenaDriver.Policy.PERFECT, 3000)
	assert_bool(report.ended).is_true()
	assert_int(report.outcome).is_equal(BattleLogic.Outcome.VICTORY)
	assert_int(report.touches).is_equal(0)
	# 12 health at 4 a blow is three blows, and PERFECT only swings when the blade will land.
	assert_int(report.hits).is_equal(3)
	assert_int(report.swings).is_equal(report.hits)

func test_perfect_steps_away_from_a_foe_about_to_touch_it() -> void:
	var sim := _sim(_foe(12, 3, 2.0, 5))
	# The player's box starts at 1200. A foe at 1116 ends at 1196, and one frame of its stride
	# (2 tiles a second is 8 units, plus one) reaches past 1200: it could touch next frame. The
	# player faces away from it, so the blade does not reach it.
	sim.stage(Vector2i(5 * U, 3 * U), D.RIGHT, [Vector2i(1116, 3 * U)])
	var choice := ArenaDriver.choose(sim, ArenaDriver.Policy.PERFECT)
	assert_bool(choice.swing).is_false()
	assert_vector(choice.move).is_equal(Vector2(1.0, 0.0))

func test_charge_walks_straight_at_a_foe_that_is_far_away() -> void:
	# Spawned below it and in line with it: straight up, and nothing to swing at yet.
	var choice := ArenaDriver.choose(_sim(_foe(999, 1)), ArenaDriver.Policy.CHARGE)
	assert_bool(choice.swing).is_false()
	assert_vector(choice.move).is_equal(Vector2(0.0, -1.0))

func test_charge_swings_at_whatever_is_close_whichever_way_it_faces() -> void:
	var sim := _sim(_foe(999, 1))
	# The foe overlaps the player from the left while the player faces right. CHARGE swings anyway,
	# into the air, and takes the touch it walked into.
	sim.stage(Vector2i(1280, 768), D.RIGHT, [Vector2i(1260, 768)])
	var report := ArenaDriver.play(sim, ArenaDriver.Policy.CHARGE, 1)
	assert_int(report.swings).is_equal(1)
	assert_int(report.hits).is_equal(0)
	assert_int(report.touches).is_equal(1)

func test_charge_does_not_swing_until_it_has_walked_into_the_foe() -> void:
	# Swinging a moment before a touch is using the sword's reach, and reach is exactly the skill the
	# balance gate needs CHARGE to lack. The player's box runs from 1200 to 1360; a foe standing at
	# 1480 starts at 1400, forty units clear of it, with the blade able to land from here.
	var sim := _sim(_foe(999, 1))
	sim.stage(Vector2i(1280, 768), D.RIGHT, [Vector2i(1480, 768)])
	assert_bool(sim.sword_reaches(0)).override_failure_message(
		"the staging no longer puts the foe inside the blade's reach, so this proves nothing").is_true()
	var choice := ArenaDriver.choose(sim, ArenaDriver.Policy.CHARGE)
	assert_bool(choice.swing).override_failure_message(
		"CHARGE swung at a foe it had not walked into, so it is using the sword's reach").is_false()
	assert_vector(choice.move).is_equal(Vector2(1.0, 0.0))

func test_a_fight_stopped_at_its_cap_says_it_did_not_end() -> void:
	var report := ArenaDriver.play(_sim(_foe(999)), ArenaDriver.Policy.PERFECT, 5)
	assert_bool(report.ended).is_false()
	assert_int(report.frames).is_equal(5)

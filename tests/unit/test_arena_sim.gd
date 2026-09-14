extends GdUnitTestSuite
## The arena's rules, one at a time and with no scene: ArenaSim is pure, so a frame is a call.
##
## Positions are in the sim's own units, 256ths of a tile, and every expected number is a literal
## worked out in a comment beside it, never read back from the sim - an expectation taken from the
## thing under test agrees with it by construction.
##
## The fixture's floor is 10 by 6 tiles. The player's body is the template's own, 0.625 by 0.375
## tiles (160 by 96 units), and so is every foe's. MID is the middle of the floor, so the player's
## box there runs x 1200-1360 and y 720-816, and facing right the sword covers x 1360-1552,
## y 688-848.

const U := ArenaSim.UNITS_PER_TILE
const D := Dir.D
const MID := Vector2i(1280, 768)
## A foe in front of a player at MID facing right: inside the sword's box (1400-1560), clear of the
## player's (which ends at 1360).
const IN_REACH := Vector2i(1480, 768)
## A foe overlapping the player's box on the right (1220-1380), and one overlapping it on the left
## (1180-1340) - the second clear of a right-facing sword, which starts at 1360.
const TOUCHING := Vector2i(1300, 768)
const TOUCHING_LEFT := Vector2i(1260, 768)


func _combat() -> CombatDef:
	var out := CombatDef.new()
	out.id = &"arena_test"
	out.base_hp = 20
	out.hp_per_level = 4
	out.base_attack = 5
	out.attack_per_level = 2
	out.base_defense = 1
	out.defense_per_level = 1
	out.xp_curve = [10, 20]
	out.swing_frames = 6
	out.swing_reach_tiles = 0.75
	out.hurt_frames = 20
	out.foe_hurt_frames = 10
	out.push_tiles = 1.0
	out.foe_push_tiles = 1.0
	out.push_frames = 4
	out.wander_min_frames = 5
	out.wander_max_frames = 9
	out.arena_tiles = Vector2i(10, 6)
	return out


func _foe(hp := 10, attack := 3, speed := 0.0, chase := 0, foe_name := "Dummy") -> EnemyDef:
	var out := EnemyDef.new()
	out.id = StringName(foe_name.to_lower())
	out.name = foe_name
	out.character = &"quest_slink"
	out.max_hp = hp
	out.attack = attack
	out.defense = 1
	out.xp = 5
	out.gold = 2
	out.moves = [{"name": "Bump", "power": 0}]
	out.speed_tiles_per_second = speed
	out.chase_every_frames = chase
	return out


func _sim(foes: Array, combat: CombatDef = null, members: Array = [], seed_value := 7) -> ArenaSim:
	var curve := combat if combat != null else _combat()
	var party := members if not members.is_empty() else [BattleHelpers.leader(curve, 20)]
	return ArenaSim.of(curve, foes, party, "map/foe", seed_value, GameConfig.new())


# -- the clock and the stream ------------------------------------------------------------------


func _trace(seed_value: int) -> Array:
	var sim := _sim([_foe(10, 3, 2.0, 0, "Slink"), _foe(10, 3, 1.5, 12, "Gloom")], null, [],
		seed_value)
	var out: Array = []
	for f in 600:
		var sideways := 1.0 if (f / 40) % 2 == 0 else -1.0
		var down := 1.0 if (f / 90) % 2 == 0 else 0.0
		sim.tick(Vector2(sideways, down), f % 25 == 0)
		out.append([sim.player_pos(), sim.foe_pos(0), sim.foe_pos(1), sim.take_sounds()])
		if sim.finished():
			break
	return out

func test_the_same_seed_and_the_same_inputs_are_the_same_fight() -> void:
	assert_array(_trace(7)).is_equal(_trace(7))
	# The control: a different seed wanders differently, so the equality above is not two runs
	# that ignore the seed altogether.
	assert_bool(_trace(7) != _trace(8)).is_true()

func test_the_arena_draws_from_a_stream_of_its_own() -> void:
	var combat := _combat()
	for seed_value: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		var sim := _sim([_foe(10, 3, 2.0)], combat, [], seed_value)
		var stream := SeededRng.new(seed_value).derive("arena")
		var countdown := stream.next_int(combat.wander_min_frames, combat.wander_max_frames)
		var heading := ArenaSim.WANDER_HEADINGS[stream.next_int(0, ArenaSim.WANDER_HEADINGS.size() - 1)]
		sim.tick(Vector2.ZERO, false)
		assert_int(sim.foe_countdown(0)).is_equal(countdown)
		assert_vector(sim.foe_heading(0)).is_equal(heading)

func test_the_arena_counts_seconds_at_the_project_s_own_tick_rate() -> void:
	assert_int(ArenaSim.TICKS_PER_SECOND).is_equal(
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)))

func test_a_second_of_walking_covers_the_walk_speed_and_a_diagonal_is_not_faster() -> void:
	var straight := _sim([_foe()])
	straight.stage(Vector2i(U, U), D.RIGHT, [Vector2i(9 * U, 5 * U)])
	for f in 60:
		straight.tick(Vector2(1.0, 0.0), false)
	# The template's own walk is 3 tiles a second: 768 units in 60 frames, to the unit.
	assert_int(straight.player_pos().x - U).is_equal(768)
	var diagonal := _sim([_foe()])
	diagonal.stage(Vector2i(U, U), D.RIGHT, [Vector2i(9 * U, 5 * U)])
	for f in 60:
		diagonal.tick(Vector2(1.0, 1.0), false)
	# 768 * 181 / 256 is 543 on each axis.
	assert_vector(diagonal.player_pos() - Vector2i(U, U)).is_equal(Vector2i(543, 543))

func test_an_input_counts_once_pushed_half_way_and_a_tie_goes_sideways() -> void:
	assert_vector(ArenaSim.heading_of(Vector2(0.3, -1.0), true)).is_equal(Vector2i(0, -1))
	assert_vector(ArenaSim.heading_of(Vector2(1.0, 1.0), true)).is_equal(Vector2i(1, 1))
	assert_vector(ArenaSim.heading_of(Vector2(1.0, 1.0), false)).is_equal(Vector2i(1, 0))
	assert_vector(ArenaSim.heading_of(Vector2(-0.6, 0.9), false)).is_equal(Vector2i(-1, 0))

func test_two_boxes_that_only_share_an_edge_do_not_touch() -> void:
	# Rect2i.intersects is strict, and every box test in the sim leans on it: a foe flush against
	# the player is beside them, not on them.
	assert_bool(Rect2i(0, 0, 10, 10).intersects(Rect2i(10, 0, 10, 10))).is_false()
	assert_bool(Rect2i(0, 0, 10, 10).intersects(Rect2i(9, 0, 10, 10))).is_true()

func test_nobody_starts_within_reach_of_anybody() -> void:
	var sim := _sim([_foe(), _foe(10, 3, 0.0, 0, "Two"), _foe(10, 3, 0.0, 0, "Three")])
	assert_int(sim.threat()).is_equal(-1)
	for i in 3:
		assert_bool(sim.sword_reaches(i)).is_false()

func test_nobody_leaves_the_floor() -> void:
	var sim := _sim([_foe(10, 3, 3.0)])
	for f in 400:
		sim.tick(Vector2(-1.0, 1.0), false)
		assert_bool(sim.floor_rect().encloses(sim.player_box())).is_true()
		assert_bool(sim.floor_rect().encloses(sim.foe_box(0))).is_true()
	# Pressed into the bottom-left corner: half the body in from each wall.
	assert_vector(sim.player_pos()).is_equal(Vector2i(80, 6 * U - 48))

func test_a_formation_is_lettered_and_announced_by_its_ids() -> void:
	var sim := _sim([_foe(10, 3, 0.0, 0, "Slink"), _foe(10, 3, 0.0, 0, "Slink")])
	assert_str(sim.foe_name(0)).is_equal("Slink A")
	assert_str(sim.foe_name(1)).is_equal("Slink B")
	assert_int(sim.foe_ids().size()).is_equal(2)
	assert_str(String(sim.foe_ids()[1])).is_equal("slink")


# -- the sword ---------------------------------------------------------------------------------


func test_a_swing_begins_on_request_and_not_again_until_it_ends() -> void:
	var sim := _sim([_foe()])
	sim.tick(Vector2.ZERO, true)
	assert_bool(sim.swinging()).is_true()
	assert_array(sim.take_sounds()).contains([&"swing"])
	# swing_frames is 6: live on frames 1 to 6, so asking again on frames 2 to 6 starts nothing.
	for f in 5:
		sim.tick(Vector2.ZERO, true)
	assert_int(sim.swings()).is_equal(1)
	sim.tick(Vector2.ZERO, true)
	assert_int(sim.swings()).is_equal(2)

func test_the_player_is_rooted_and_facing_locked_while_the_sword_is_out() -> void:
	var sim := _sim([_foe()])
	sim.stage(MID, D.UP, [Vector2i(U, U)])
	sim.tick(Vector2.ZERO, true)
	sim.tick(Vector2(1.0, 0.0), false)
	sim.tick(Vector2(1.0, 0.0), false)
	assert_vector(sim.player_pos()).is_equal(MID)
	assert_int(sim.player_facing()).is_equal(D.UP)
	for f in 10:
		sim.tick(Vector2(1.0, 0.0), false)
	assert_int(sim.player_pos().x).is_greater(MID.x)
	assert_int(sim.player_facing()).is_equal(D.RIGHT)

func test_the_blade_deals_the_fight_s_own_damage() -> void:
	var combat := _combat()
	var sim := _sim([_foe(10)], combat, [BattleHelpers.leader(combat, 20, 0, 1, 8, 2)])
	sim.stage(MID, D.RIGHT, [IN_REACH])
	sim.tick(Vector2.ZERO, true)
	# Attack 5 at level 1 and 2 from gear, against defense 1: 6 off, so 10 becomes 4.
	assert_int(sim.foe_hp(0)).is_equal(4)
	assert_array(sim.take_sounds()).contains([&"hit"])

func test_one_swing_lands_once_on_a_foe_even_when_its_flash_is_shorter_than_the_swing() -> void:
	var combat := _combat()
	combat.foe_hurt_frames = 1
	combat.push_frames = 1
	combat.foe_push_tiles = 0.0
	var sim := _sim([_foe(99)], combat)
	sim.stage(MID, D.RIGHT, [IN_REACH])
	sim.tick(Vector2.ZERO, true)
	# The flash is over after frame 1; the swing is live until frame 6 and must not land again.
	for f in 5:
		sim.tick(Vector2.ZERO, false)
	assert_int(sim.hits()).is_equal(1)

func test_a_foe_still_flashing_from_a_blow_is_not_struck_again() -> void:
	var combat := _combat()
	combat.foe_push_tiles = 0.0
	var sim := _sim([_foe(99)], combat)
	sim.stage(MID, D.RIGHT, [IN_REACH])
	sim.tick(Vector2.ZERO, true)
	for f in 5:
		sim.tick(Vector2.ZERO, false)
	# Frame 7: the first swing (6 frames) is over, the foe's flash (10) is not.
	sim.tick(Vector2.ZERO, true)
	assert_int(sim.swings()).is_equal(2)
	assert_int(sim.hits()).is_equal(1)

func test_a_struck_foe_is_shoved_its_distance_over_the_push_frames() -> void:
	var sim := _sim([_foe(99)])
	sim.stage(MID, D.RIGHT, [IN_REACH])
	sim.tick(Vector2.ZERO, true)
	# One tile (256) over 4 frames is 64 a frame, starting on the frame of the blow.
	assert_int(sim.foe_pos(0).x).is_equal(IN_REACH.x + 64)
	for f in 5:
		sim.tick(Vector2.ZERO, false)
	assert_vector(sim.foe_pos(0)).is_equal(Vector2i(IN_REACH.x + 256, IN_REACH.y))

func test_a_foe_shoved_into_a_wall_can_be_struck_again_at_once() -> void:
	var sim := _sim([_foe(99)])
	# The right wall is at 2560, so a foe pressed to it stands at 2480.
	sim.stage(Vector2i(2280, 768), D.RIGHT, [Vector2i(2480, 768)])
	sim.tick(Vector2.ZERO, true)
	assert_int(sim.hits()).is_equal(1)
	assert_int(sim.foe_hurt(0)).is_equal(0)


# -- being touched -----------------------------------------------------------------------------


func test_touching_a_foe_hurts_once_and_not_again_until_the_protection_ends() -> void:
	var combat := _combat()
	combat.push_tiles = 0.0
	combat.push_frames = 1
	var sim := _sim([_foe(99, 3)], combat)
	sim.stage(MID, D.LEFT, [TOUCHING])
	sim.tick(Vector2.ZERO, false)
	# Attack 3 against defense 1 at level 1: 2 off.
	assert_int(sim.leader_hp()).is_equal(18)
	assert_array(sim.take_sounds()).contains([&"hurt"])
	for f in 19:
		sim.tick(Vector2.ZERO, false)
	assert_int(sim.touches()).is_equal(1)
	# hurt_frames is 20: touched on frame 1, touchable again on frame 21.
	sim.tick(Vector2.ZERO, false)
	assert_int(sim.touches()).is_equal(2)
	assert_int(sim.leader_hp()).is_equal(16)

func test_a_foe_flashing_from_a_blow_cannot_bite() -> void:
	var combat := _combat()
	combat.foe_push_tiles = 0.0
	var sim := _sim([_foe(99)], combat)
	# Overlapping the player AND inside the sword's box, so the blade and the touch meet one frame.
	sim.stage(MID, D.RIGHT, [TOUCHING])
	sim.tick(Vector2.ZERO, true)
	assert_int(sim.hits()).is_equal(1)
	assert_int(sim.touches()).is_equal(0)

func test_a_wall_ends_a_shove_and_the_protection_that_came_with_it() -> void:
	var sim := _sim([_foe(99, 3)])
	# Pressed to the left wall (half the body in, 80), a foe overlapping from the right.
	sim.stage(Vector2i(80, 768), D.RIGHT, [Vector2i(200, 768)])
	sim.tick(Vector2.ZERO, false)
	assert_int(sim.touches()).is_equal(1)
	# Frame 2: the shove meets the wall at once, so the protection ends with it and the same foe
	# touches again.
	sim.tick(Vector2.ZERO, false)
	assert_int(sim.touches()).is_equal(2)

func test_being_touched_takes_the_sword_away() -> void:
	var combat := _combat()
	combat.push_tiles = 0.0
	var sim := _sim([_foe(99, 3)], combat)
	sim.stage(MID, D.RIGHT, [TOUCHING_LEFT])
	sim.tick(Vector2.ZERO, true)
	assert_int(sim.touches()).is_equal(1)
	assert_bool(sim.swinging()).is_false()


# -- the foes ----------------------------------------------------------------------------------


func test_a_wanderer_turns_round_at_a_wall() -> void:
	var sim := _sim([_foe(10, 3, 4.0)])
	sim.stage(MID, D.UP, [Vector2i(10 * U - 80, 3 * U)])
	sim.steer(0, Vector2i(1, 0), 100)
	sim.tick(Vector2.ZERO, false)
	assert_vector(sim.foe_heading(0)).is_equal(Vector2i(-1, 0))

func test_a_chaser_turns_toward_the_player_on_its_period_offset_by_its_slot() -> void:
	var sim := _sim([_foe(10, 3, 0.0, 10, "Gloom"), _foe(10, 3, 0.0, 10, "Gloom")])
	sim.stage(Vector2i(U, 3 * U), D.UP, [Vector2i(8 * U, 3 * U), Vector2i(8 * U, 4 * U)])
	for f in 8:
		sim.tick(Vector2.ZERO, false)
	assert_vector(sim.foe_heading(0)).is_equal(Vector2i.ZERO)
	assert_vector(sim.foe_heading(1)).is_equal(Vector2i.ZERO)
	# Frame 9: slot 1 re-aims, because 9 + 1 is a multiple of 10; slot 0 waits for frame 10.
	sim.tick(Vector2.ZERO, false)
	assert_vector(sim.foe_heading(1)).is_equal(Vector2i(-1, 0))
	assert_vector(sim.foe_heading(0)).is_equal(Vector2i.ZERO)
	sim.tick(Vector2.ZERO, false)
	assert_vector(sim.foe_heading(0)).is_equal(Vector2i(-1, 0))

func test_a_wander_countdown_is_drawn_between_its_bounds() -> void:
	var drawn := {}
	for seed_value: int in range(1, 41):
		var sim := _sim([_foe(10, 3, 1.0)], null, [], seed_value)
		sim.tick(Vector2.ZERO, false)
		var countdown := sim.foe_countdown(0)
		assert_int(countdown).is_between(5, 9)
		drawn[countdown] = true
	# Forty draws over five values: a countdown stuck on one number is not a draw.
	assert_int(drawn.size()).is_greater(1)


# -- the verdict -------------------------------------------------------------------------------


func test_falling_loses_the_fight_and_nothing_moves_after() -> void:
	var sim := _sim([_foe(99, 99)])
	sim.stage(MID, D.LEFT, [TOUCHING])
	sim.tick(Vector2.ZERO, false)
	assert_bool(sim.finished()).is_true()
	assert_int(sim.outcome()).is_equal(BattleLogic.Outcome.DEFEAT)
	assert_array(sim.take_sounds()).contains([&"defeat"])
	assert_array(sim.effects()).is_empty()
	sim.tick(Vector2(1.0, 0.0), false)
	assert_int(sim.frame()).is_equal(1)

func test_winning_pays_every_member_still_standing_and_marks_the_foe_beaten() -> void:
	var combat := _combat()
	var leader := BattleHelpers.leader(combat, 20)
	var rook := BattleHelpers.companion(&"rook", combat, "Rook", 10)
	var ash := BattleHelpers.companion(&"ash", combat, "Ash", 0)
	var sim := _sim([_foe(1)], combat, [leader, rook, ash])
	sim.stage(MID, D.RIGHT, [IN_REACH])
	sim.tick(Vector2.ZERO, true)
	assert_int(sim.outcome()).is_equal(BattleLogic.Outcome.VICTORY)
	assert_array(sim.take_sounds()).contains([&"victory"])
	var effects := sim.effects()
	assert_int(effects.size()).is_equal(3)
	assert_dict(effects[0]).is_equal({"op": GameContext.OP_SEEN, "key": "map/foe"})
	var members: Array = effects[1]["members"]
	var lead: Dictionary = members[0]
	var second: Dictionary = members[1]
	var fallen: Dictionary = members[2]
	# The foe was worth 5: the leader and Rook earn it, and Ash is down and earns nothing. Rook
	# fought nothing and took nothing, so Rook's health is what it was.
	assert_int(int(lead["xp"])).is_equal(5)
	assert_int(int(second["xp"])).is_equal(5)
	assert_int(int(second["hp"])).is_equal(10)
	assert_int(int(fallen["xp"])).is_equal(0)
	assert_dict(effects[2]).is_equal({"op": GameContext.OP_GOLD, "amount": 2})

func test_the_bar_follows_the_blow_and_then_the_nearest() -> void:
	var combat := _combat()
	combat.foe_push_tiles = 0.0
	var sim := _sim([_foe(99, 3, 0.0, 0, "Near"), _foe(8, 3, 0.0, 0, "Far")], combat)
	# Near stands behind the player, 220 away; Far in front and in reach, 240 away.
	sim.stage(MID, D.RIGHT, [Vector2i(MID.x - 220, MID.y), Vector2i(IN_REACH.x + 40, MID.y)])
	assert_int(sim.shown_foe()).is_equal(0)
	sim.tick(Vector2.ZERO, true)
	assert_int(sim.shown_foe()).is_equal(1)
	# Frame 12: the swing is long over and Far's flash too, so the second blow fells it.
	for f in 10:
		sim.tick(Vector2.ZERO, false)
	sim.tick(Vector2.ZERO, true)
	assert_bool(sim.foe_down(1)).is_true()
	assert_int(sim.shown_foe()).is_equal(0)

func test_a_cue_is_handed_over_once() -> void:
	var sim := _sim([_foe()])
	sim.tick(Vector2.ZERO, true)
	assert_array(sim.take_sounds()).is_not_empty()
	assert_array(sim.take_sounds()).is_empty()


func test_a_swing_steps_through_its_pictures_and_answers_none_once_the_sword_is_away() -> void:
	# The screen shows a swing as pictures and the rules count it in frames. A 13-frame swing is
	# painted on 12 of them - the countdown runs at the end of the tick that started it - so six
	# pictures spread over those twelve are two frames each.
	var combat := _combat()
	combat.swing_frames = 13
	var sim := _sim([_foe()], combat)
	var far: Array[Vector2i] = [Vector2i(256, 256)]
	sim.stage(MID, D.RIGHT, far)
	assert_int(sim.swing_step(6)).is_equal(-1)
	var seen: Array[int] = []
	sim.tick(Vector2.ZERO, true)
	while sim.swinging() and seen.size() < 40:
		seen.append(sim.swing_step(6))
		sim.tick(Vector2.ZERO, false)
	assert_str(str(seen)).is_equal("[0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5]")
	assert_int(sim.swing_step(6)).override_failure_message(
		"a sword put away still names a picture").is_equal(-1)

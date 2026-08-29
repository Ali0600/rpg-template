extends GdUnitTestSuite
## The stat curve, and what it refuses.
##
## The curve is walked rather than divided, so the test walks a THREE-step one: a curve tested
## with a single step cannot tell "adds up the entries in order" apart from "multiplies by the
## first", and those diverge the moment a designer makes level 3 cost more than level 2.

func _combat(curve: Array[int] = [10, 12, 20]) -> CombatDef:
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
	out.attack_cue_frames = 30
	out.defend_cue_frames = 40
	out.timed_window_frames = 6
	out.message_frames = 10
	return out

func test_level_one_is_the_base_line() -> void:
	var combat := _combat()
	assert_int(combat.max_hp(1)).is_equal(20)
	assert_int(combat.attack_at(1)).is_equal(5)
	assert_int(combat.defense_at(1)).is_equal(1)
	assert_int(combat.max_mp(1)).is_equal(8)

func test_each_level_adds_its_gain() -> void:
	var combat := _combat()
	assert_int(combat.max_hp(3)).is_equal(28)
	assert_int(combat.attack_at(3)).is_equal(9)
	assert_int(combat.defense_at(3)).is_equal(3)
	# 8 + 3 + 3. A curve read as "base times level" would say 24 and pass at level 1.
	assert_int(combat.max_mp(3)).is_equal(14)

func test_the_thresholds_are_cumulative() -> void:
	# Against [10, 12, 20]: level 2 at 10, level 3 at 22, level 4 at 42. A curve read as
	# "each entry is the next threshold" would put level 3 at 12 and pass a one-step test.
	var combat := _combat()
	assert_int(combat.level_for(0)).is_equal(1)
	assert_int(combat.level_for(9)).is_equal(1)
	assert_int(combat.level_for(10)).is_equal(2)
	assert_int(combat.level_for(21)).is_equal(2)
	assert_int(combat.level_for(22)).is_equal(3)
	assert_int(combat.level_for(42)).is_equal(4)

func test_the_curve_ends_rather_than_extrapolating() -> void:
	# The maximum level is a fact of the data. Extrapolating past the last entry would make
	# "how long is this game" unanswerable from the file.
	var combat := _combat()
	assert_int(combat.level_for(9999)).is_equal(4)

func test_the_next_threshold_is_reported_until_the_cap() -> void:
	var combat := _combat()
	assert_int(combat.xp_for_next(1)).is_equal(10)
	assert_int(combat.xp_for_next(3)).is_equal(42)
	assert_int(combat.xp_for_next(4)).is_equal(-1)

func test_a_valid_definition_has_nothing_wrong_with_it() -> void:
	# The control for every refusal below. A problems() that reported a fault on everything
	# would pass all of them and fail the build on correct data.
	assert_array(_combat().problems()).is_empty()

func test_an_empty_curve_is_refused() -> void:
	var combat := _combat([])
	assert_array(combat.problems()).is_not_empty()

func test_a_free_level_is_refused() -> void:
	var combat := _combat([10, 0])
	assert_array(combat.problems()).is_not_empty()

func test_a_window_as_long_as_a_cue_is_refused() -> void:
	# Every press would be perfect, which reads in play as a timing mechanic that does not
	# work rather than as one that is switched off.
	var combat := _combat()
	combat.timed_window_frames = combat.attack_cue_frames
	assert_array(combat.problems()).is_not_empty()

func test_a_player_with_no_health_is_refused() -> void:
	var combat := _combat()
	combat.base_hp = 0
	assert_array(combat.problems()).is_not_empty()

func test_negative_magic_is_refused() -> void:
	var combat := _combat()
	combat.base_mp = -1
	assert_array(combat.problems()).is_not_empty()
	combat.base_mp = 8
	combat.mp_per_level = -1
	assert_array(combat.problems()).is_not_empty()

func test_a_game_with_no_magic_at_all_is_allowed() -> void:
	# The control that keeps the magic check from being written as "must be positive". Zero is
	# the DEFAULT and it means a game that ships no spells - which stays a legal shape forever,
	# the way a manifest with no CombatDef is a game that cannot fight.
	var combat := _combat()
	combat.base_mp = 0
	combat.mp_per_level = 0
	assert_array(combat.problems()).is_empty()
	assert_int(combat.max_mp(4)).is_equal(0)

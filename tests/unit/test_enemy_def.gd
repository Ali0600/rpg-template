extends GdUnitTestSuite
## What an enemy file has to say before a fight will use it.
##
## Every refusal here is paired against the valid enemy that `_enemy()` builds, so a
## problems() that reported a fault on everything - which would pass all the refusals - fails
## the first test in the file.

func _enemy() -> EnemyDef:
	var out := EnemyDef.new()
	out.id = &"test_enemy"
	out.name = "Test Enemy"
	out.character = &"quest_warden"
	out.max_hp = 10
	out.attack = 3
	out.defense = 1
	out.xp = 5
	out.moves = [{"name": "Scratch", "power": 0}]
	return out

func test_a_valid_enemy_has_nothing_wrong_with_it() -> void:
	assert_array(_enemy().problems()).is_empty()

func test_an_enemy_with_no_id_is_refused() -> void:
	var enemy := _enemy()
	enemy.id = &""
	assert_array(enemy.problems()).is_not_empty()

func test_an_enemy_with_no_character_is_refused() -> void:
	# Without one there is nothing to draw, and the battle screen would open on a blank space
	# where the thing fighting you is meant to be.
	var enemy := _enemy()
	enemy.character = &""
	assert_array(enemy.problems()).is_not_empty()

func test_an_enemy_with_no_moves_is_refused() -> void:
	# It would reach its turn with nothing to do, which presents as a battle that stops rather
	# than as a broken file.
	var enemy := _enemy()
	enemy.moves = []
	assert_array(enemy.problems()).is_not_empty()

func test_a_move_with_no_name_is_refused() -> void:
	var enemy := _enemy()
	enemy.moves = [{"power": 2}]
	assert_array(enemy.problems()).is_not_empty()

func test_a_move_that_heals_the_player_is_refused() -> void:
	var enemy := _enemy()
	enemy.moves = [{"name": "Blunder", "power": -5}]
	assert_array(enemy.problems()).is_not_empty()

func test_an_enemy_that_cannot_survive_being_started_is_refused() -> void:
	var enemy := _enemy()
	enemy.max_hp = 0
	assert_array(enemy.problems()).is_not_empty()

func test_zero_xp_is_allowed() -> void:
	# A fight can be an obstacle rather than a reward. This is the control that keeps the xp
	# check from being written as "must be positive".
	var enemy := _enemy()
	enemy.xp = 0
	assert_array(enemy.problems()).is_empty()

# -- resistances ------------------------------------------------------------------------------

func test_an_enemy_that_answers_no_element_is_fine() -> void:
	# The default, and the control for every refusal below: an empty map is what every enemy
	# shipped before resistances existed carries, so a check that refused it would fail them all.
	var enemy := _enemy()
	assert_array(enemy.resistances.keys()).is_empty()
	assert_array(enemy.problems()).is_empty()

func test_a_weakness_and_a_resistance_are_both_allowed() -> void:
	var enemy := _enemy()
	enemy.resistances = {&"fire": 200, &"ice": 50}
	assert_array(enemy.problems()).is_empty()

func test_immunity_is_allowed() -> void:
	# Zero is a real answer - untouched by it - and the control that keeps the percent check from
	# being written as "must be positive", which would refuse the genre's own immunities.
	var enemy := _enemy()
	enemy.resistances = {&"fire": 0}
	assert_array(enemy.problems()).is_empty()

func test_an_answer_of_exactly_a_hundred_percent_is_refused() -> void:
	# It reads like a decision and changes nothing, so it is either a typo for a real number or a
	# note that belongs in a comment. Saying so beats letting a designer believe they wrote one.
	var enemy := _enemy()
	enemy.resistances = {&"fire": 100}
	assert_array(enemy.problems()).is_not_empty()

func test_an_answer_that_would_heal_the_enemy_is_refused() -> void:
	var enemy := _enemy()
	enemy.resistances = {&"fire": -50}
	assert_array(enemy.problems()).is_not_empty()

func test_an_element_with_no_name_is_refused() -> void:
	var enemy := _enemy()
	enemy.resistances = {&"": 200}
	assert_array(enemy.problems()).is_not_empty()

func test_a_percent_that_is_not_a_number_is_refused() -> void:
	# A hand-edited .tres can hold anything. A string reads back through int() as ZERO, which is
	# immunity - so the failure is a fight that feels wrong rather than a file that looks broken.
	var enemy := _enemy()
	enemy.resistances = {&"fire": "weak"}
	assert_array(enemy.problems()).is_not_empty()

func test_an_unnamed_element_is_answered_at_face_value() -> void:
	var enemy := _enemy()
	enemy.resistances = {&"fire": 200}
	assert_int(enemy.resistance_to(&"ice")).is_equal(100)

func test_a_spell_made_of_nothing_is_answered_at_face_value() -> void:
	# Checked in resistance_to rather than at the call site, so the fight's arithmetic stays one
	# line. An enemy weak to fire is not weak to a spell that is made of nothing.
	var enemy := _enemy()
	enemy.resistances = {&"fire": 200}
	assert_int(enemy.resistance_to(&"")).is_equal(100)

func test_a_named_element_is_answered_by_its_own_number() -> void:
	var enemy := _enemy()
	enemy.resistances = {&"fire": 200, &"ice": 50}
	assert_int(enemy.resistance_to(&"fire")).is_equal(200)
	assert_int(enemy.resistance_to(&"ice")).is_equal(50)

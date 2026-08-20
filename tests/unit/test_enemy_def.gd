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

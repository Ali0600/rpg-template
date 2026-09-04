extends GdUnitTestSuite
## The movement rules, tested with no scene at all.
##
## Everything that makes four-direction movement feel right or wrong is decided here, so it
## can all be pinned without physics: how a diagonal is normalised, which way a tie faces,
## whether letting go of the keys spins the character back to front. What the node adds is
## only `move_and_slide`.

const D := Dir.D

## The template's OWN defaults at its own reference tile, not the demo's file. Two reasons, and
## the second is the rule: the numbers below were written against a 16px tile, and a suite that
## named the size the DEMO is drawn at would go stale as a refusal the day its art changes -
## which is exactly what test_grid_movement already argues at the top of its own before_test.
const TILE := 16

var _config: GameConfig

func before_test() -> void:
	_config = GameConfig.new().at(TILE)

func test_walking_right_moves_right_at_the_configured_speed() -> void:
	var step := Locomotion.step(Vector2(1.0, 0.0), D.DOWN, _config)
	assert_vector(step.velocity).is_equal(Vector2(_config.walk_speed_px(), 0.0))
	assert_int(step.facing).is_equal(D.RIGHT)
	assert_str(String(step.clip)).is_equal("walk")

func test_a_diagonal_is_not_faster_than_a_straight_line() -> void:
	# The classic bug in every hand-rolled movement system, and it survives playtesting
	# because moving diagonally 41% faster feels good.
	var straight := Locomotion.step(Vector2(1.0, 0.0), D.DOWN, _config)
	var diagonal := Locomotion.step(Vector2(1.0, 1.0), D.DOWN, _config)
	assert_float(diagonal.velocity.length()).is_equal_approx(straight.velocity.length(), 0.01)

func test_a_partial_stick_deflection_is_not_scaled_up() -> void:
	# Only vectors LONGER than one are normalised: a gamepad held gently must still walk
	# gently, or every analogue stick becomes a digital one.
	var gentle := Locomotion.step(Vector2(0.4, 0.0), D.DOWN, _config)
	assert_float(gentle.velocity.length()).is_equal_approx(_config.walk_speed_px() * 0.4, 0.01)

func test_releasing_the_keys_keeps_the_facing() -> void:
	# Otherwise the character snaps back to front-facing every time you stop, which reads as
	# a twitch and makes it impossible to talk to anything you are not below.
	var step := Locomotion.step(Vector2.ZERO, D.UP, _config)
	assert_int(step.facing).is_equal(D.UP)
	assert_str(String(step.clip)).is_equal("idle")
	assert_vector(step.velocity).is_equal(Vector2.ZERO)

func test_a_perfect_diagonal_faces_sideways() -> void:
	assert_int(Locomotion.step(Vector2(1.0, 1.0), D.UP, _config).facing).is_equal(D.RIGHT)
	assert_int(Locomotion.step(Vector2(-1.0, -1.0), D.UP, _config).facing).is_equal(D.LEFT)

func test_four_way_mode_refuses_diagonals_entirely() -> void:
	# The stricter feel of the earliest top-down RPGs, as a config flag rather than a fork.
	_config.allow_diagonal = false
	var step := Locomotion.step(Vector2(1.0, 1.0), D.UP, _config)
	assert_vector(step.velocity).is_equal(Vector2(_config.walk_speed_px(), 0.0))
	assert_int(step.facing).is_equal(D.RIGHT)

func test_four_way_mode_still_picks_the_dominant_axis() -> void:
	_config.allow_diagonal = false
	var step := Locomotion.step(Vector2(0.3, -0.9), D.RIGHT, _config)
	assert_vector(step.velocity).is_equal(Vector2(0.0, -_config.walk_speed_px()))
	assert_int(step.facing).is_equal(D.UP)

func test_a_speed_below_the_epsilon_is_standing_still() -> void:
	# Without a threshold, floating-point drift keeps the walk animation twitching after the
	# keys are released.
	_config.idle_tiles_per_second = 10.0 / float(TILE)
	var step := Locomotion.step(Vector2(0.1, 0.0), D.DOWN, _config)
	assert_str(String(step.clip)).is_equal("idle")

func test_the_interaction_point_is_in_front_of_the_facing() -> void:
	var origin := Vector2(100.0, 100.0)
	assert_vector(Locomotion.interact_point(origin, D.UP, _config)) \
		.is_equal(origin + Vector2(0.0, -_config.interact_reach_px()))
	assert_vector(Locomotion.interact_point(origin, D.RIGHT, _config)) \
		.is_equal(origin + Vector2(_config.interact_reach_px(), 0.0))

func test_the_interaction_point_works_while_standing_still() -> void:
	# Derived from the facing, never from the velocity: a character standing in front of a
	# sign still has a front, and deriving it from movement would make it impossible to talk
	# to anything without walking into it.
	var origin := Vector2.ZERO
	var idle := Locomotion.step(Vector2.ZERO, D.LEFT, _config)
	assert_vector(Locomotion.interact_point(origin, idle.facing, _config)) \
		.is_equal(Vector2(-_config.interact_reach_px(), 0.0))

func test_the_shipped_config_is_sane() -> void:
	assert_array(_config.problems()).is_empty()

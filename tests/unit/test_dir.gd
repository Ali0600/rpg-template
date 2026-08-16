extends GdUnitTestSuite
## Pins the direction contract: order, names, aliases and the facing rule.
##
## Row order is the one thing in this project that is wrong silently. A sheet written
## down/left/right/up and read down/right/left/up produces a character who walks east while
## facing west, with no error anywhere - so the order is asserted as a literal list here,
## not derived from the constant it is checking.

const D := Dir.D

func test_canonical_order_is_down_left_right_up() -> void:
	# Written out by hand on purpose: quoting Dir.ALL to test Dir.ALL proves nothing.
	assert_int(Dir.ALL.size()).is_equal(4)
	assert_int(Dir.ALL[0]).is_equal(D.DOWN)
	assert_int(Dir.ALL[1]).is_equal(D.LEFT)
	assert_int(Dir.ALL[2]).is_equal(D.RIGHT)
	assert_int(Dir.ALL[3]).is_equal(D.UP)

func test_names_match_the_order() -> void:
	var names: Array[String] = []
	for d: int in Dir.ALL:
		names.append(String(Dir.name_of(d)))
	assert_array(names).is_equal(["down", "left", "right", "up"])

func test_compass_aliases_resolve_to_canonical_directions() -> void:
	# An external sheet may label its rows in its own vocabulary; the factory maps them.
	assert_int(Dir.from_name("south")).is_equal(D.DOWN)
	assert_int(Dir.from_name("WEST")).is_equal(D.LEFT)
	assert_int(Dir.from_name(" east ")).is_equal(D.RIGHT)
	assert_int(Dir.from_name("north")).is_equal(D.UP)
	assert_int(Dir.from_name("front")).is_equal(D.DOWN)

func test_unknown_direction_is_rejected_not_defaulted() -> void:
	# Returning DOWN for junk would file every unreadable row as front-facing and look fine.
	assert_int(Dir.from_name("diagonal")).is_equal(-1)
	assert_int(Dir.from_name("")).is_equal(-1)

func test_views_collapse_left_and_right_to_one_side() -> void:
	assert_int(Dir.view_of(D.LEFT)).is_equal(Dir.View.SIDE)
	assert_int(Dir.view_of(D.RIGHT)).is_equal(Dir.View.SIDE)
	assert_int(Dir.view_of(D.DOWN)).is_equal(Dir.View.FRONT)
	assert_int(Dir.view_of(D.UP)).is_equal(Dir.View.BACK)

func test_vectors_use_screen_space_with_y_growing_downward() -> void:
	assert_vector(Dir.vector_of(D.DOWN)).is_equal(Vector2(0.0, 1.0))
	assert_vector(Dir.vector_of(D.UP)).is_equal(Vector2(0.0, -1.0))
	assert_vector(Dir.vector_of(D.LEFT)).is_equal(Vector2(-1.0, 0.0))
	assert_vector(Dir.vector_of(D.RIGHT)).is_equal(Vector2(1.0, 0.0))

func test_facing_prefers_the_dominant_axis() -> void:
	assert_int(Dir.facing_from_vector(Vector2(0.9, 0.2), D.DOWN)).is_equal(D.RIGHT)
	assert_int(Dir.facing_from_vector(Vector2(-0.9, 0.2), D.DOWN)).is_equal(D.LEFT)
	assert_int(Dir.facing_from_vector(Vector2(0.2, 0.9), D.LEFT)).is_equal(D.DOWN)
	assert_int(Dir.facing_from_vector(Vector2(0.2, -0.9), D.LEFT)).is_equal(D.UP)

func test_a_perfect_diagonal_faces_sideways() -> void:
	# The tie rule. Sideways is the pose with the clearest silhouette, and a player holding
	# two keys should not see the sprite flicker between two equally valid answers.
	assert_int(Dir.facing_from_vector(Vector2(1.0, 1.0), D.UP)).is_equal(D.RIGHT)
	assert_int(Dir.facing_from_vector(Vector2(-1.0, -1.0), D.UP)).is_equal(D.LEFT)
	assert_int(Dir.facing_from_vector(Vector2(-1.0, 1.0), D.UP)).is_equal(D.LEFT)

func test_standing_still_keeps_the_previous_facing() -> void:
	# Releasing every key must not spin the character back to front-facing.
	assert_int(Dir.facing_from_vector(Vector2.ZERO, D.UP)).is_equal(D.UP)
	assert_int(Dir.facing_from_vector(Vector2.ZERO, D.LEFT)).is_equal(D.LEFT)

func test_animation_names_are_clip_underscore_direction() -> void:
	assert_str(String(Dir.anim_name(&"walk", D.DOWN))).is_equal("walk_down")
	assert_str(String(Dir.anim_name(&"idle", D.UP))).is_equal("idle_up")

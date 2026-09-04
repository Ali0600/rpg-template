extends GdUnitTestSuite
## Grid stepping, decided as a result rather than driven through a scene.
##
## Physics is faked by a closure: the walker asks "could I move by this?" and the test answers
## from a list of blocked motions, then advances the position by whatever velocity the walker
## asked for. That one seam is what makes a blocked step, an aborted step and a diagonal
## sliding along a wall all testable with no scene tree and no map.
##
## The invariant every case is really checking: **the actor is on a cell centre whenever no
## step is in flight.** Everything downstream - warps firing on arrival, an interact reaching
## exactly one tile - is only true if that holds.

const CELL := 16
## Small enough that a step takes many frames, so an overshoot has somewhere to happen.
const DELTA := 1.0 / 60.0

var _config: GameConfig
## Motions the fake physics refuses. Keyed by the rounded motion vector.
var _blocked: Array[Vector2i] = []
## Set true to let a step latch and THEN refuse to move, which is what a body walking into
## something that arrived after the check looks like.
var _frozen := false
## Per-axis multiplier on whatever velocity the walker asks for. (1,0) is a body whose x is
## blocked mid-step while its y is still free - the case abandon()'s per-axis rule exists for,
## and one _latch can never produce because it refuses a blocked step up front.
var _axis_scale := Vector2.ONE

func before_test() -> void:
	_config = (load("res://data/game_config.tres") as GameConfig).at(CELL)
	# The one line that turns the mode on. It is a flag now rather than a distance, because a
	# bound config already knows how big a tile is.
	_config.grid_step = true
	_blocked = []
	_frozen = false
	_axis_scale = Vector2.ONE

func _is_free(motion: Vector2) -> bool:
	return not _blocked.has(Vector2i(motion.round()))

func _walker() -> GridWalker:
	return GridWalker.new(_config)

func _centre(tile: Vector2i) -> Vector2:
	return MapData.tile_to_world(tile, CELL)

## Runs the walker until it is between steps, moving by whatever velocity it asks for. Bounded:
## a step that never ends is a hang, and a hang reads as an environment problem rather than a
## test failure.
func _run(walker: GridWalker, input: Vector2, at: Vector2, limit: int = 200) -> Vector2:
	var pos := at
	var facing := Dir.D.DOWN
	for i in limit:
		var step := walker.plan(input, pos, facing, _is_free)
		facing = step.facing
		if not _frozen:
			pos += step.velocity * _axis_scale * DELTA
		pos = walker.settle(pos)
		if not walker.stepping():
			return pos
	assert_bool(false).override_failure_message("a step never finished").is_true()
	return pos

func test_a_press_steps_to_the_next_cell_centre_and_stops() -> void:
	# Exact, not approximate. "Near the centre" accumulates, and a warp that fires on arriving
	# at a tile stops firing once the actor is a pixel short of one.
	var at := _run(_walker(), Vector2.RIGHT, _centre(Vector2i(2, 2)))
	assert_vector(at).is_equal(_centre(Vector2i(3, 2)))

func test_a_tapped_key_still_buys_the_whole_tile() -> void:
	# The defining difference from free movement: the step is committed, not held.
	var walker := _walker()
	var pos := _centre(Vector2i(2, 2))
	var first := walker.plan(Vector2.RIGHT, pos, Dir.D.DOWN, _is_free)
	pos = walker.settle(pos + first.velocity * DELTA)
	assert_bool(walker.stepping()).is_true()
	# Key released from here on.
	assert_vector(_run(walker, Vector2.ZERO, pos)).is_equal(_centre(Vector2i(3, 2)))

func test_every_frame_of_a_step_is_the_walking_pose() -> void:
	# The pose comes from "a step is in flight", never from a velocity magnitude - so a step
	# cannot play the standing animation while it slides.
	var walker := _walker()
	var pos := _centre(Vector2i(2, 2))
	for i in 200:
		var step := walker.plan(Vector2.RIGHT, pos, Dir.D.DOWN, _is_free)
		assert_str(String(step.clip)).is_equal("walk")
		pos = walker.settle(pos + step.velocity * DELTA)
		if not walker.stepping():
			return
	assert_bool(false).override_failure_message("a step never finished").is_true()

func test_a_key_pressed_mid_step_does_not_turn_the_character() -> void:
	# Turning early would let the player talk to something they are walking away from.
	var walker := _walker()
	var pos := _centre(Vector2i(2, 2))
	var first := walker.plan(Vector2.RIGHT, pos, Dir.D.DOWN, _is_free)
	pos = walker.settle(pos + first.velocity * DELTA)
	var mid := walker.plan(Vector2.UP, pos, first.facing, _is_free)
	assert_int(mid.facing).is_equal(Dir.D.RIGHT)

func test_a_step_into_a_blocked_cell_is_refused_and_turns_to_face_it() -> void:
	# Refused BEFORE committing, so walking into a wall stands and looks at it rather than
	# sliding a few pixels and snapping back every step.
	_blocked = [Vector2i(CELL, 0)]
	var walker := _walker()
	var at := _centre(Vector2i(2, 2))
	var step := walker.plan(Vector2.RIGHT, at, Dir.D.DOWN, _is_free)
	assert_bool(walker.stepping()).is_false()
	assert_vector(step.velocity).is_equal(Vector2.ZERO)
	assert_str(String(step.clip)).is_equal("idle")
	assert_int(step.facing).is_equal(Dir.D.RIGHT)

func test_a_diagonal_whose_x_is_walled_takes_its_y() -> void:
	# move_and_slide slides for free movement, and a grid mode that stopped dead in a corner
	# would read as a bug rather than as a style. The slid-to position is itself a centre.
	_blocked = [Vector2i(CELL, CELL), Vector2i(CELL, 0)]
	var at := _run(_walker(), Vector2(1.0, 1.0), _centre(Vector2i(2, 2)))
	assert_vector(at).is_equal(_centre(Vector2i(2, 3)))

func test_a_diagonal_whose_y_is_walled_takes_its_x() -> void:
	_blocked = [Vector2i(CELL, CELL), Vector2i(0, CELL)]
	var at := _run(_walker(), Vector2(1.0, 1.0), _centre(Vector2i(2, 2)))
	assert_vector(at).is_equal(_centre(Vector2i(3, 2)))

func test_a_blocked_diagonal_breaks_its_tie_horizontally() -> void:
	# Only the diagonal itself is walled, so both single axes are available and the tie rule
	# decides. Dir sends ties sideways; this must agree or the two disagree at a corner.
	_blocked = [Vector2i(CELL, CELL)]
	var at := _run(_walker(), Vector2(1.0, 1.0), _centre(Vector2i(2, 2)))
	assert_vector(at).is_equal(_centre(Vector2i(3, 2)))

func test_a_clear_diagonal_moves_both_axes() -> void:
	var at := _run(_walker(), Vector2(1.0, 1.0), _centre(Vector2i(2, 2)))
	assert_vector(at).is_equal(_centre(Vector2i(3, 3)))

func test_four_way_mode_never_produces_a_diagonal_step() -> void:
	# allow_diagonal is honoured by quoting Locomotion rather than by a second implementation.
	_config.allow_diagonal = false
	var at := _run(_walker(), Vector2(1.0, 1.0), _centre(Vector2i(2, 2)))
	assert_vector(at).is_equal(_centre(Vector2i(3, 2)))

func test_a_step_stopped_after_it_started_ends_on_a_cell_centre() -> void:
	# is_free was right when asked and wrong a frame later - an NPC stepped into the path, or
	# the tile bodies had not been built yet. The step must end rather than push forever.
	var walker := _walker()
	var origin := _centre(Vector2i(2, 2))
	var pos := origin
	var first := walker.plan(Vector2.RIGHT, pos, Dir.D.DOWN, _is_free)
	pos = walker.settle(pos + first.velocity * DELTA)
	assert_bool(walker.stepping()).is_true()
	_frozen = true
	assert_vector(_run(walker, Vector2.RIGHT, pos)).is_equal(origin)

func test_abandoning_a_step_ends_it_on_a_cell_centre() -> void:
	# What halt() does when a dialog opens mid-step.
	var walker := _walker()
	var origin := _centre(Vector2i(2, 2))
	var first := walker.plan(Vector2.RIGHT, origin, Dir.D.DOWN, _is_free)
	var pos := walker.settle(origin + first.velocity * DELTA)
	assert_vector(walker.abandon(pos)).is_equal(origin)
	assert_bool(walker.stepping()).is_false()

func test_abandoning_when_no_step_is_in_flight_changes_nothing() -> void:
	# halt() is called every frame a conversation is open, so this is the common case.
	var stray := _centre(Vector2i(2, 2)) + Vector2(3.0, 0.0)
	assert_vector(_walker().abandon(stray)).is_equal(stray)

func test_cancelling_a_step_leaves_the_position_to_the_caller() -> void:
	# A teleport: resolving the step would resolve it against a cell in the map being left.
	var walker := _walker()
	var pos := _centre(Vector2i(2, 2))
	walker.plan(Vector2.RIGHT, pos, Dir.D.DOWN, _is_free)
	walker.cancel()
	assert_bool(walker.stepping()).is_false()

func test_a_diagonal_step_takes_the_time_its_longer_path_needs() -> void:
	# It covers 22.6px at the same speed, so it takes 1.41x as long. The alternative is the
	# 41%-faster diagonal Locomotion exists to prevent.
	var straight := _frames_for(Vector2.RIGHT)
	var diagonal := _frames_for(Vector2(1.0, 1.0))
	assert_float(float(diagonal) / float(straight)).is_equal_approx(sqrt(2.0), 0.1)

func _frames_for(input: Vector2) -> int:
	var walker := _walker()
	var pos := _centre(Vector2i(2, 2))
	for i in 200:
		var step := walker.plan(input, pos, Dir.D.DOWN, _is_free)
		pos = walker.settle(pos + step.velocity * DELTA)
		if not walker.stepping():
			return i + 1
	return -1

func test_a_step_crosses_a_cell_at_walk_speed_when_no_duration_is_set() -> void:
	# Zero means "derive it", so both movement modes cross a tile at the same rate unless a
	# designer says otherwise.
	_config.grid_step_seconds = 0.0
	_assert_takes_about(_config.walk_speed_px())

func test_a_duration_overrides_the_speed() -> void:
	# 16px in 0.1s is 160px/s, a bit over three times the shipped walk speed.
	_config.grid_step_seconds = 0.1
	_assert_takes_about(float(CELL) / 0.1)

## Asserts a straight step takes the number of frames a speed implies, allowing the ONE extra
## frame the design documents: with no clock, a step ends on the frame that reaches its target,
## so its duration quantises up. The exact count is not pinned on purpose - Vector2 is float32,
## so 20 frames of 0.8px land a hair under 16.0 and a 21st is needed. Pinning 21 would pin an
## accumulation artifact rather than the contract, and the contract is "one cell at this speed".
func _assert_takes_about(speed: float) -> void:
	var ideal := int(ceil(float(CELL) / (speed * DELTA)))
	var frames := _frames_for(Vector2.RIGHT)
	assert_int(frames).is_greater_equal(ideal)
	assert_int(frames).is_less_equal(ideal + 1)

func test_a_diagonal_stopped_on_one_axis_keeps_the_axis_that_arrived() -> void:
	# A diagonal in flight whose x jams while its y completes: the actor keeps the y it earned
	# and gives back the x it did not, landing on the cell it slid into. _latch cannot produce
	# this - it refuses a blocked step before committing - so only a mid-flight stop reaches it.
	var walker := _walker()
	var origin := _centre(Vector2i(2, 2))
	var first := walker.plan(Vector2(1.0, 1.0), origin, Dir.D.DOWN, _is_free)
	var pos := walker.settle(origin + first.velocity * DELTA)
	assert_bool(walker.stepping()).is_true()
	_axis_scale = Vector2(0.0, 1.0)
	assert_vector(_run(walker, Vector2(1.0, 1.0), pos)).is_equal(_centre(Vector2i(2, 3)))

func test_a_step_ends_on_the_frame_it_arrives_not_the_one_after() -> void:
	# Arriving is its own branch, and this is the only thing that can tell it apart from the
	# stopped-making-progress branch: both land on the same pixel, one just takes a frame
	# longer. The numbers are chosen to be exact in float32 - 8px a frame, twice - so the
	# assertion is about the branch and not about accumulated error.
	_config.grid_step_seconds = float(CELL) / 32.0
	var walker := _walker()
	var pos := _centre(Vector2i(2, 2))
	var frames := 0
	for i in 10:
		var step := walker.plan(Vector2.RIGHT, pos, Dir.D.DOWN, _is_free)
		pos += step.velocity * 0.25
		pos = walker.settle(pos)
		frames += 1
		if not walker.stepping():
			break
	assert_int(frames).is_equal(2)
	assert_vector(pos).is_equal(_centre(Vector2i(3, 2)))

func test_the_shipped_config_is_still_free_movement() -> void:
	# The whole promise of this milestone: nothing anyone can play changes.
	var shipped := load("res://data/game_config.tres") as GameConfig
	assert_bool(shipped.grid_step).is_false()
	assert_array(shipped.problems()).is_empty()

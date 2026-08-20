extends GdUnitTestSuite
## The footstep cadence. Pure arithmetic over distance, so it is tested by handing it numbers.


func test_a_foot_lands_once_the_stride_is_covered() -> void:
	var meter := StepMeter.new(10.0)
	assert_bool(meter.advance(4.0)).is_false()
	assert_bool(meter.advance(4.0)).is_false()
	assert_bool(meter.advance(4.0)).is_true()


func test_the_leftover_pays_into_the_next_step() -> void:
	# Zeroing instead of subtracting would make the cadence depend on frame rate: the same walk
	# would sound different on a machine that renders in bigger or smaller pieces.
	var meter := StepMeter.new(10.0)
	assert_bool(meter.advance(19.0)).is_true()
	assert_float(meter.carried()).is_equal_approx(9.0, 0.001)
	assert_bool(meter.advance(1.0)).is_true()


func test_one_long_frame_still_lands_a_foot() -> void:
	# A stalled frame can cover several strides at once. It must not swallow the footfall
	# entirely - a hitch you can hear is worse than one you can only measure.
	var meter := StepMeter.new(10.0)
	assert_bool(meter.advance(35.0)).is_true()


func test_a_stride_of_zero_switches_footsteps_off() -> void:
	# Zero is a MODE, the way GameConfig.grid_step_pixels at zero means free movement - so a
	# game with silent feet says so in data rather than needing code.
	var meter := StepMeter.new(0.0)
	for i in 100:
		assert_bool(meter.advance(50.0)).is_false()


func test_standing_still_never_lands_a_foot() -> void:
	var meter := StepMeter.new(10.0)
	assert_bool(meter.advance(0.0)).is_false()
	assert_bool(meter.advance(-5.0)).is_false()


func test_being_put_down_somewhere_is_not_a_stride() -> void:
	# A spawn, a warp or a load would otherwise count the distance across a whole map as ground
	# the player walked, and land a footstep the moment they arrive.
	var meter := StepMeter.new(10.0)
	meter.advance(9.0)
	meter.reset()
	assert_float(meter.carried()).is_equal(0.0)
	assert_bool(meter.advance(9.0)).is_false()

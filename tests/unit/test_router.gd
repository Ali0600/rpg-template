extends GdUnitTestSuite
## The game-flow state machine: one owner of "can the player move right now?"
##
## The failure this design exists to prevent is two systems each keeping their own
## `can_move` boolean. A dialog sets one, a menu sets the other, and the player ends up
## frozen after a conversation that visibly closed - with each system certain it released
## control, and nothing anywhere reporting a fault.

func before_test() -> void:
	# An autoload outlives every suite in the run, so state left by one test is present in
	# the next unless something resets it.
	Router.reset()

func after_test() -> void:
	Router.reset()

func test_the_player_moves_only_in_the_world_state() -> void:
	Router.set_state(Router.State.WORLD)
	assert_bool(Router.player_can_move()).is_true()
	for blocked: int in [Router.State.TITLE, Router.State.DIALOG, Router.State.PAUSED]:
		Router.set_state(blocked)
		assert_bool(Router.player_can_move()).override_failure_message(
			"the player can move in the %s state" % Router.state_name()).is_false()

func test_an_overlay_returns_to_what_it_covered() -> void:
	# Not to WORLD, to whatever was underneath. A menu opened from a dialog must leave the
	# dialog reachable when it closes.
	Router.set_state(Router.State.WORLD)
	Router.open_overlay(Router.State.DIALOG)
	assert_str(Router.state_name()).is_equal("dialog")
	Router.open_overlay(Router.State.PAUSED)
	assert_str(Router.state_name()).is_equal("paused")
	Router.close_overlay()
	assert_str(Router.state_name()).is_equal("dialog")
	Router.close_overlay()
	assert_str(Router.state_name()).is_equal("world")

func test_every_open_is_balanced_by_a_close() -> void:
	Router.set_state(Router.State.WORLD)
	assert_int(Router.overlay_depth()).is_equal(0)
	Router.open_overlay(Router.State.DIALOG)
	assert_int(Router.overlay_depth()).is_equal(1)
	Router.close_overlay()
	assert_int(Router.overlay_depth()).is_equal(0)

func test_closing_nothing_falls_back_to_the_world_rather_than_sticking() -> void:
	# The safer failure of the two: a stuck overlay state means the game stops responding
	# entirely, with no way out short of a restart.
	Router.set_state(Router.State.DIALOG)
	Router.close_overlay()
	assert_str(Router.state_name()).is_equal("world")
	assert_bool(Router.player_can_move()).is_true()

func test_a_state_change_announces_itself() -> void:
	# Systems react to the change rather than polling for it, so an audio cue or a HUD fade
	# does not need its own copy of the state machine.
	var seen: Array[Dictionary] = []
	var handler := func(info: Dictionary) -> void: seen.append(info)
	EventBus.flow_changed.connect(handler)
	Router.set_state(Router.State.WORLD)
	Router.set_state(Router.State.DIALOG)
	EventBus.flow_changed.disconnect(handler)
	assert_int(seen.size()).is_equal(1)
	assert_int(int(seen[0]["from"])).is_equal(Router.State.WORLD)
	assert_int(int(seen[0]["to"])).is_equal(Router.State.DIALOG)

func test_setting_the_state_it_is_already_in_announces_nothing() -> void:
	# Otherwise every listener fires on every frame that re-asserts the current state.
	var count := 0
	var handler := func(_info: Dictionary) -> void: count += 1
	Router.set_state(Router.State.WORLD)
	EventBus.flow_changed.connect(handler)
	Router.set_state(Router.State.WORLD)
	EventBus.flow_changed.disconnect(handler)
	assert_int(count).is_equal(0)

func test_reset_clears_the_stack_not_just_the_state() -> void:
	# A reset that left the stack behind would send the next close_overlay somewhere
	# arbitrary - and it is exactly what tests and map transitions rely on.
	Router.open_overlay(Router.State.DIALOG)
	Router.open_overlay(Router.State.PAUSED)
	Router.reset()
	assert_int(Router.overlay_depth()).is_equal(0)
	assert_str(Router.state_name()).is_equal("world")

extends GdUnitTestSuite
## Items reaching live state, through the one sink.
##
## The pure suites prove what an effect list SAYS. This proves what carrying it out does - and
## in particular that a conversation's gift and a chest's gift are the same code path, because
## the day they are two paths is the day the second one forgets a rule the first one has.

const GAME := "res://data/games/quest.tres"

var _world: Node2D

func before_test() -> void:
	GameState.reset()
	Router.reset()

func after_test() -> void:
	Input.action_release(&"interact")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()

func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(load(GAME) as GameManifest)).is_true()
	return _world

func _give(id: StringName, n: int = 1) -> Dictionary:
	return {"op": GameContext.OP_GIVE_ITEM, "id": id, "count": n}

func _take(id: StringName, n: int = 1) -> Dictionary:
	return {"op": GameContext.OP_TAKE_ITEM, "id": id, "count": n}

## Physics frames, which is the clock the box reveals its text on.
func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## One real keypress, the way the QA harness delivers them, with its release.
func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)


func test_a_gift_survives_the_conversation_it_was_promised_in() -> void:
	# Driven through the BOX, not through its signal: the effects are read off the runner
	# inside _close(), so a test that emits `closed` itself proves the sink and nothing about
	# whether anything was ever handed to it.
	_boot()
	var runner := DialogRunner.from_dict({
		"id": "gift", "start": "ask",
		"nodes": {"ask": {"speaker": "Hermit", "text": "Oil?", "choices": [
			{"text": "Please.", "give_item": "lamp_oil", "set_flag": "took_oil"}]}},
	})
	assert_bool(_world.dialog_box().open(runner)).is_true()
	# Bounded: a conversation that will not close is a failure to report, not a test that
	# hangs until the runner is killed.
	for i in 30:
		if not _world.dialog_box().is_open():
			break
		await _press(&"interact")
	assert_bool(_world.dialog_box().is_open()).override_failure_message(
		"the conversation never ended").is_false()
	assert_int(GameState.item_count(&"lamp_oil")).override_failure_message(
		"the gift was promised in the conversation and never arrived").is_equal(1)
	assert_bool(GameState.has_flag(&"took_oil")).is_true()


func test_a_gift_from_a_conversation_reaches_the_inventory() -> void:
	# Through DialogBox.closed, which used to write flags directly and now goes through the
	# same sink as everything else.
	_boot()
	_world.dialog_box().closed.emit([_give(&"gate_key")])
	assert_int(GameState.item_count(&"gate_key")).override_failure_message(
		"a conversation's gift never reached the player").is_equal(1)

func test_a_conversation_can_still_set_a_flag() -> void:
	# The control for the rewritten sink: the old payload's job must still be done.
	_boot()
	_world.dialog_box().closed.emit([{"op": GameContext.OP_FLAG, "key": &"promised_elder", "value": true}])
	assert_bool(GameState.has_flag(&"promised_elder")).is_true()

func test_an_item_nothing_describes_is_refused() -> void:
	# An item with no data file cannot be drawn in a list or named to a player, so carrying it
	# would be a bag with an invisible thing in it.
	_boot()
	_world.dialog_box().closed.emit([_give(&"unobtainium")])
	assert_bool(GameState.inventory.is_empty()).override_failure_message(
		"an item no file describes was carried anyway").is_true()

func test_a_take_that_cannot_be_covered_takes_nothing() -> void:
	_boot()
	GameState.give_item(&"lamp_oil")
	_world.dialog_box().closed.emit([_take(&"lamp_oil", 2)])
	assert_int(GameState.item_count(&"lamp_oil")).override_failure_message(
		"a take that could not be covered still changed the count").is_equal(1)

func test_a_gift_and_a_take_in_one_list_both_land_in_order() -> void:
	_boot()
	_world.dialog_box().closed.emit([_give(&"lamp_oil"), _take(&"lamp_oil")])
	assert_int(GameState.item_count(&"lamp_oil")).is_equal(0)
	assert_bool(GameState.inventory.is_empty()).is_true()

func test_what_is_carried_survives_a_save_and_a_load() -> void:
	# The end to end of it: the world's own save path, not GameState in isolation.
	_boot()
	GameState.give_item(&"gate_key", 3)
	var data := GameState.to_save()
	GameState.reset()
	GameState.from_save(data)
	assert_int(GameState.item_count(&"gate_key")).is_equal(3)


# --- money out, and a night's sleep ---------------------------------------------------------
#
# The two ops an inn needs. Both go through the same sink every gift and every flag does, so a
# keeper and a chest cannot end up with two different ideas of what happens.


func test_a_spend_takes_the_money() -> void:
	var world := _boot()
	GameState.give_gold(20)
	assert_bool(world._apply_effects([{"op": GameContext.OP_SPEND_GOLD, "amount": 6}])).is_true()
	assert_int(GameState.gold).is_equal(14)


func test_a_spend_beyond_the_purse_moves_nothing() -> void:
	# The runner refuses it upstream, so this is the invariant behind that rather than a second
	# copy of it - and the purse is left alone rather than clamped to zero.
	var world := _boot()
	GameState.give_gold(5)
	world._apply_effects([{"op": GameContext.OP_SPEND_GOLD, "amount": 6}])
	assert_int(GameState.gold).override_failure_message(
		"an uncoverable spend still moved money").is_equal(5)


func test_a_rest_fills_the_player_up() -> void:
	var world := _boot()
	GameState.set_party(3, 0, 1)
	assert_bool(world._apply_effects([{"op": GameContext.OP_REST}])).is_true()
	var full: int = (load(GAME) as GameManifest).combat.max_hp(1)
	assert_int(GameState.player_hp).override_failure_message(
		"a night at the inn did not restore the player").is_equal(full)
	assert_int(full).override_failure_message(
		"the fixture starts full, so this test could not tell a rest from a no-op") \
		.is_greater(3)


func test_a_rest_leaves_the_level_and_the_experience_alone() -> void:
	# set_party carries all three because they are one fact, so a rest has to hand the other
	# two back unchanged - a night that reset the player's level would be a very bad night.
	var world := _boot()
	GameState.set_party(3, 42, 2)
	world._apply_effects([{"op": GameContext.OP_REST}])
	assert_int(GameState.player_xp).is_equal(42)
	assert_int(GameState.player_level).is_equal(2)

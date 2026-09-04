extends GdUnitTestSuite
## Sound reaching the bus through the real game, rather than through a function call.
##
## The pure suites prove which cue a rule ASKS for. This proves the asking actually happens
## when the player does the thing - walking, turning a page, opening a door - which is the half
## no pure test can see, because the emitters live in views and in the world loop.
##
## Every assertion is on the id that was REQUESTED. Headless runs on a dummy audio driver, so
## "it made a noise" is not a claim anything here can make, and pretending otherwise would be
## a gate that proves nothing.

const GAME := "res://data/games/quest.tres"

var _world: Node2D


func before_test() -> void:
	GameState.reset()
	Router.reset()
	AudioBus.set_enabled(true)


func after_test() -> void:
	Input.action_release(&"interact")
	Input.action_release(&"move_down")
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	GameState.reset()
	Router.reset()
	AudioBus.clear_requests()


func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(load(GAME) as GameManifest)).is_true()
	return _world


## The quest forces its opening line on a new run, so the player cannot move until it closes.
## Bounded: a conversation that will not close is a failure to report, not a hang.
func _dismiss_opening() -> void:
	for i in 12:
		if Router.state_name() != "dialog":
			return
		await _press(&"interact")
	fail("the opening conversation would not close")


func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


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


func test_the_game_boots_able_to_make_every_noise_it_will_ask_for() -> void:
	# The precondition every other test here rests on. Without it a suite could pass by
	# asserting that requests were MADE while none of them could ever have played.
	_boot()
	assert_array(AudioBus.missing_cues()).is_empty()
	assert_str(String(AudioBus.style_id())).is_equal("dusk16")


func test_walking_asks_for_footsteps_and_standing_still_does_not() -> void:
	# The control is the half that matters: a footstep fired every frame would also pass the
	# first assertion, and would be unlistenable.
	_boot()
	await _dismiss_opening()
	AudioBus.clear_requests()
	Input.action_press(&"move_down")
	await _steps(40)
	Input.action_release(&"move_down")
	await _steps(2)
	assert_array(AudioBus.requested()).override_failure_message(
		"walking for forty frames asked for no footstep").contains(
		[Sfx.id_of(Sfx.Cue.FOOTSTEP)])

	AudioBus.clear_requests()
	await _steps(40)
	assert_array(AudioBus.requested()).override_failure_message(
		"a player standing still is making footstep noises").not_contains(
		[Sfx.id_of(Sfx.Cue.FOOTSTEP)])


func test_a_body_put_down_somewhere_starts_its_stride_over() -> void:
	# The case that matters is a body teleported having ALMOST completed a stride: without the
	# reset, its very next frame of walking finishes that stride and lands a footstep on the
	# doorstep.
	#
	# Everything is measured on ONE body inside ONE frame, deliberately. move_and_slide picks
	# its own delta - the idle one out here - so a distance measured on a different body, or
	# across an await, is a distance from a different frame. A freshly added body's first move
	# is not representative either, which is what a naive version of this test got wrong.
	var stride := 200.0
	var body := _loose_body(stride)
	var walked := 0.0
	var frame := 0.0
	for i in 500:
		var before := body.global_position
		var fell := body.apply(Vector2.DOWN).footfall
		frame = before.distance_to(body.global_position)
		assert_bool(fell).override_failure_message(
			"a foot landed before the walk-up finished").is_false()
		walked += frame
		if walked + frame >= stride:
			break
	assert_float(walked).override_failure_message(
		"the body never got near a full stride, so nothing here is being measured"
	).is_greater(stride * 0.5)

	body.place(body.global_position + Vector2(0.0, 400.0), Dir.D.DOWN)

	# This frame would have completed the stride, had the teleport not ended it.
	assert_bool(body.apply(Vector2.DOWN).footfall).override_failure_message(
		"the distance walked before the teleport was still on the clock afterwards").is_false()


## A body with nothing around it, so it can walk as far as a test needs - the village stops the
## player against geometry inside one tile.
func _loose_body(stride: float) -> ActorBody:
	# Bound at the 16px tile the dusk16 art is drawn at, so the stride stays the PIXEL distance
	# every assertion below is written in.
	var config := (load("res://data/game_config.tres") as GameConfig).at(16)
	config.footstep_tiles = stride / 16.0
	var body := ActorBody.new()
	assert_bool(body.setup(config, FileSpriteSource.create(&"dusk16"), &"quest_wanderer")).is_true()
	add_child(body)
	auto_free(body)
	return body


func test_turning_a_page_of_dialog_is_audible() -> void:
	_boot()
	var runner := DialogRunner.from_dict({
		"id": "chat", "start": "one",
		"nodes": {"one": {"speaker": "Warden", "text": "Well now.", "next": "two"},
			"two": {"speaker": "Warden", "text": "Off you go."}},
	})
	assert_bool(_world.dialog_box().open(runner)).is_true()
	await _steps(2)
	AudioBus.clear_requests()
	await _press(&"interact")
	assert_array(AudioBus.requested()).contains([Sfx.id_of(Sfx.Cue.PAGE)])


func test_a_line_being_typed_out_is_audible() -> void:
	_boot()
	var runner := DialogRunner.from_dict({
		"id": "chat", "start": "one",
		"nodes": {"one": {"speaker": "Warden", "text": "A reasonably long line of speech."}},
	})
	assert_bool(_world.dialog_box().open(runner)).is_true()
	AudioBus.clear_requests()
	await _steps(30)
	assert_array(AudioBus.requested()).contains([Sfx.id_of(Sfx.Cue.TALK)])


func test_a_door_that_refuses_says_so_out_loud() -> void:
	# WALKED into, not called: the cue lives in the arrival check rather than in enter_map,
	# precisely because enter_map is also the first spawn and a save restore - neither of which
	# is a door. Driving it any other way would test a path the player never takes.
	#
	# The barred gate is the game's own locked warp, east of the village start, so this is the
	# real refusal rather than a fixture shaped like one.
	_boot()
	await _dismiss_opening()
	AudioBus.clear_requests()
	Input.action_press(&"move_right")
	# Held until geometry stops the player, never for a computed number of tiles.
	for i in 200:
		await get_tree().physics_frame
		if AudioBus.requested().has(Sfx.id_of(Sfx.Cue.LOCKED)):
			break
	Input.action_release(&"move_right")
	await _steps(2)
	assert_array(AudioBus.requested()).override_failure_message(
		"walking into the barred gate made no refusal sound").contains(
		[Sfx.id_of(Sfx.Cue.LOCKED)])

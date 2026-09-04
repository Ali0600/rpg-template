extends GdUnitTestSuite
## NPCs that move, through the real world scene.
##
## The brain is unit-tested on its own; what cannot be tested there is the wiring - that a
## brain actually reaches a body, that the body walks through the same Locomotion the player
## does, and above all that the town STOPS when the player does. The freeze is one line's
## placement in `_physics_process`, and a test that drives the brain directly would prove
## nothing about it: it would enter below the layer that does the freezing.
##
## Every NPC the demo game ships is `static`, so these suites build their own movers into a
## duplicated manifest rather than editing the shipped maps - several QA sessions use the
## shipped NPC bodies as walls, and a wandering warden would break them.

const GAME := "res://data/games/quest.tres"

var _world: Node2D

func before_test() -> void:
	GameState.reset()

func after_test() -> void:
	if _world != null:
		_world.queue_free()
		_world = null

func _manifest() -> GameManifest:
	# A duplicate, never an edit: Godot hands every caller the same loaded resource, so
	# assigning here would leave the change set for every other suite in the run.
	return (load(GAME) as GameManifest).duplicate() as GameManifest

func _boot() -> Node2D:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	_world = scene.instantiate() as Node2D
	add_child(_world)
	assert_bool(_world.start_game(_manifest())).override_failure_message(
		"the world would not start the game").is_true()
	await _dismiss_opening()
	return _world

func _steps(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

## The game opens with the warden talking. Every test here is about something else.
func _dismiss_opening() -> void:
	for i in 40:
		if Router.state() == Router.State.WORLD:
			break
		await _press(&"interact")
	await _steps(2)

func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(2)
	# The matching release is not optional: an action left held is still held at the next
	# press, and the engine sees no change at all.
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)

## Replaces the running map's NPCs with one mover, and returns its body. Reaching into the
## world's record is deliberate: the alternative is a whole fixture game, and what is under
## test is the DRIVER, not map loading.
func _add_mover(behavior: String, extra: Dictionary = {}) -> ActorBody:
	var npcs: Dictionary = _world._npcs
	var first: Dictionary = npcs.values()[0]
	var body := first.get("body") as ActorBody
	var record := first.duplicate()
	record["behavior"] = behavior
	record.merge(extra, true)
	# The RUNNING map's tile size. It was 16 here and 16 where the waypoints are worked out, so
	# the pair cancelled and the tests passed against a world drawn at neither size.
	var brain := NpcBrain.of(record, body.global_position, GameState.tile_size,
		SeededRng.new(SeededRng.hash_seed(0, "test:%s" % behavior)))
	first["brain"] = brain
	return body

func test_a_wandering_npc_actually_moves() -> void:
	await _boot()
	var body := _add_mover("wander", {"range": 2, "dwell_min": 0, "dwell_max": 1})
	var was := body.global_position
	await _steps(120)
	assert_float(was.distance_to(body.global_position)).override_failure_message(
		"the wanderer never left %s" % was).is_greater(0.5)

func test_a_static_npc_does_not_move_at_all() -> void:
	# The control for the test above. Without it, "the wanderer moved" could be true of any
	# NPC - and every NPC the demo ships is static, holding up seven QA sessions as walls.
	await _boot()
	var npcs: Dictionary = _world._npcs
	var first: Dictionary = npcs.values()[0]
	var body := first.get("body") as ActorBody
	assert_bool(first.has("brain")).override_failure_message(
		"a shipped NPC was given a brain; every one of them is static").is_false()
	var was := body.global_position
	await _steps(120)
	assert_vector(body.global_position).override_failure_message(
		"a static NPC drifted from %s" % was).is_equal(was)

func test_the_town_holds_still_while_a_dialog_is_up() -> void:
	# The reason the driver sits below the player_can_move() gate. A speaker who wanders off
	# mid-sentence takes her dialog box with her, and the one-shot turn-to-face done when the
	# conversation opened silently stops being true.
	await _boot()
	var body := _add_mover("wander", {"range": 3, "dwell_min": 0, "dwell_max": 0})
	await _steps(30)

	Router.open_overlay(Router.State.DIALOG)
	await _steps(2)
	var during := body.global_position
	await _steps(90)
	assert_vector(body.global_position).override_failure_message(
		"an NPC kept walking while the dialog box was up").is_equal(during)

	Router.close_overlay()
	await _steps(60)
	assert_float(during.distance_to(body.global_position)).override_failure_message(
		"the NPC never started again after the conversation").is_greater(0.5)

func test_a_patrolling_npc_walks_toward_its_first_waypoint() -> void:
	await _boot()
	var npcs: Dictionary = _world._npcs
	var first: Dictionary = npcs.values()[0]
	var body := first.get("body") as ActorBody
	var home := MapData.world_to_tile(body.global_position, GameState.tile_size)
	var away := home + Vector2i(0, 2)
	_add_mover("patrol", {"path": [[away.x, away.y], [home.x, home.y]],
		"dwell_min": 0, "dwell_max": 0})
	var was := body.global_position
	await _steps(90)
	var moved := body.global_position - was
	assert_float(moved.y).override_failure_message(
		"asked to patrol south, moved %s" % moved).is_greater(0.0)


## Holds an action down for a stretch of frames, then releases it. _press is a tap; a carry
## only shows up while the player is actually moving against her.
func _hold(action: StringName, frames: int) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _steps(frames)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _steps(1)

func test_an_npc_walking_into_the_player_is_not_carried_sideways() -> void:
	# A player found this one. The engine's default motion mode is GROUNDED, which is a
	# platformer contract: an NPC touching the player from above is "standing on" him, and a
	# body standing on a MOVING body inherits its velocity. She was dragged at 0.8px a frame -
	# exactly the walk speed - until she was two tiles off her route.
	#
	# It has to be staged through the real world scene. Driving apply() by hand from a
	# coroutine moves bodies outside a physics frame, where the server tracks no velocity for
	# them, so the mechanism cannot occur there however the bodies are arranged.
	await _boot()
	var npcs: Dictionary = _world._npcs
	var first: Dictionary = npcs.values()[0]
	var body := first.get("body") as ActorBody
	var home := MapData.world_to_tile(body.global_position, GameState.tile_size)
	_add_mover("patrol", {"path": [[home.x, home.y + 3], [home.x, home.y]],
		"dwell_min": 0, "dwell_max": 0})

	# Directly in her way, one body-height below, so she walks down into him and stays there.
	# Derived from the body rather than written out: the demo's actors are twice the size they
	# were when this said 10px, and at that number the two of them now OVERLAP - the physics
	# server shoves her aside, and the reading becomes about collision separation rather than
	# about a moving floor carrying anybody.
	var player := _world._player as ActorBody
	var gap := player.config.body_size_px().y * 5.0 / 3.0
	player.place(body.global_position + Vector2(0.0, gap), Dir.D.UP)
	await _steps(30)

	var her_x := body.global_position.x
	await _hold(&"move_right", 45)
	assert_float(body.global_position.x).override_failure_message(
		"she was dragged %.1fpx sideways by the player walking past her"
			% [body.global_position.x - her_x]).is_equal_approx(her_x, 0.5)

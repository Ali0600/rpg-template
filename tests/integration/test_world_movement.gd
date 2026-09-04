extends GdUnitTestSuite
## Movement against real physics: a built map, a real collider, real physics ticks.
##
## The pure Locomotion tests prove what the rules decide. They cannot prove that the tiles
## grew collision shapes, that the player's box is where it should be, or that a wall
## actually stops anything - and those need the physics server, which does run headless.
##
## Two things this suite is careful about. Collision bodies for a TileMapLayer appear on its
## first physics update, so nothing is asserted before a couple of ticks have passed. And
## everything advances in PHYSICS frames, never wall-clock time.

const FIXTURE_MAP := "res://tests/fixtures/maps/wall_east.json"
const TICKS_TO_SETTLE := 3

var _config: GameConfig
var _style: SpriteStyle
var _built: MapBuilder.Built
var _root: Node2D

func before_test() -> void:
	Router.reset()
	# Bound to the 16px tile this suite's gb16 world is drawn at - a body's box is in pixels.
	_config = (load("res://data/game_config.tres") as GameConfig).at(16)
	_style = load("res://data/styles/gb16.tres") as SpriteStyle
	var meta := JsonFile.read("res://assets/generated/gb16/tiles.json")
	assert_bool(meta.ok).override_failure_message(meta.error).is_true()
	var texture := load("res://assets/generated/gb16/tiles.png") as Texture2D
	var data := MapData.load_from(FIXTURE_MAP)
	_built = MapBuilder.build(data, _style, texture, meta.data)
	assert_array(_built.problems).override_failure_message(str(_built.problems)).is_empty()
	_root = _built.root
	add_child(_root)

func after_test() -> void:
	Router.reset()
	if is_instance_valid(_root):
		_root.queue_free()

func _spawn_player() -> ActorBody:
	var body := ActorBody.new()
	body.setup(_config, FileSpriteSource.create(&"gb16"), &"hero")
	_built.sorted.add_child(body)
	body.global_position = MapBuilder.spawn_position(_built.data, &"start", _built.tile_size)
	return body

func _tick(body: ActorBody, input: Vector2, ticks: int) -> void:
	for i in ticks:
		body.apply(input)
		await await_millis(1)


## Walks until the body stops making progress, and asserts it actually arrived somewhere
## rather than running out of attempts. Counting ticks instead would bake in the physics
## delta and the walk speed - two numbers that are meant to be tunable - so the loop watches
## the OUTCOME and is merely bounded, never unbounded.
func _walk_until_blocked(body: ActorBody, input: Vector2, max_ticks: int = 600) -> Vector2:
	var last := body.global_position
	var still := 0
	for i in max_ticks:
		body.apply(input)
		await await_millis(1)
		if body.global_position.distance_to(last) < 0.01:
			still += 1
			if still >= 3:
				return body.global_position
		else:
			still = 0
		last = body.global_position
	assert_bool(false).override_failure_message(
		"walked %d ticks without ever being blocked (ended at %s)" % [max_ticks, body.global_position]) \
		.is_true()
	return body.global_position

func test_the_map_builds_tile_layers_with_a_y_sorted_parent() -> void:
	# Decor and actors must share ONE y-sorted parent or a character is permanently in front
	# of, or behind, every bush - two sorted layers each sort internally and then stack whole.
	assert_bool(_built.sorted.y_sort_enabled).is_true()
	assert_object(_built.ground).is_not_null()
	assert_bool(_built.decor.get_parent() == _built.sorted).override_failure_message(
		"decor is not inside the y-sorted layer, so actors cannot sort against it").is_true()

func test_the_players_collision_box_sits_on_its_feet() -> void:
	# A top-down character occupies the FLOOR it stands on. A box the size of the drawing
	# would stop its head against a wall the feet are nowhere near.
	var body := _spawn_player()
	await await_idle_frame()
	var shape := SceneHelpers.find_by_class(body, "CollisionShape2D") as CollisionShape2D
	assert_object(shape).is_not_null()
	var rect := shape.shape as RectangleShape2D
	assert_vector(rect.size).is_equal(_config.body_size_px())
	# Above the origin, not centred on it: the origin is the feet, so a centred box would put
	# half the collider through the floor.
	assert_float(shape.position.y).is_less(0.0)
	assert_float(absf(shape.position.y)).is_equal_approx(_config.body_size_px().y / 2.0, 0.01)

func test_the_player_moves_when_told_to() -> void:
	var body := _spawn_player()
	await await_idle_frame()
	var before := body.global_position
	await _tick(body, Vector2(1.0, 0.0), 5)
	assert_float(body.global_position.x).override_failure_message(
		"the player did not move east").is_greater(before.x)
	assert_float(body.global_position.y).is_equal_approx(before.y, 0.01)

func test_a_wall_stops_the_player() -> void:
	# The whole reason tiles carry collision. Nothing here knows which tile is a wall - that
	# came from the tiles' own data, through the TileSet, into the physics server.
	var body := _spawn_player()
	await await_idle_frame()
	await _tick(body, Vector2.ZERO, TICKS_TO_SETTLE)
	var blocked: Vector2 = await _walk_until_blocked(body, Vector2(1.0, 0.0))
	var at_wall := blocked.x
	await _tick(body, Vector2(1.0, 0.0), 30)
	assert_float(body.global_position.x).override_failure_message(
		"the player pushed through the wall (%.1f -> %.1f)" % [at_wall, body.global_position.x]) \
		.is_equal_approx(at_wall, 0.01)
	# And it is stopped INSIDE the map, not at some arbitrary distance beyond it.
	var bounds := _built.data.size()
	assert_float(at_wall).is_less(float(bounds.x * _built.tile_size))

func test_a_wall_does_not_trap_the_player() -> void:
	# Sliding into a wall must not stick: the failure mode of a badly-shaped collider is a
	# character who arrives and can never leave.
	var body := _spawn_player()
	await await_idle_frame()
	var blocked: Vector2 = await _walk_until_blocked(body, Vector2(1.0, 0.0))
	await _tick(body, Vector2(-1.0, 0.0), 10)
	assert_float(body.global_position.x).is_less(blocked.x)

## How far a body pressed diagonally into a wall slides along it, and over how many frames.
## A MEASURED literal, and the reason it exists is below.
## 20 frames of a normalised diagonal at the template's own 48px/s. GROUNDED covers 11.31px
## here and FLOATING 14.96, because GROUNDED calls a north wall a CEILING and handles it
## differently from a wall - so this literal is also the fail-first proof that the pin can tell
## the two motion modes apart, which `is_greater` could not.
const SLIDE_FRAMES := 20
const SLIDE_PX := 14.96


func test_walking_into_a_wall_diagonally_slides_along_it() -> void:
	# Axis-separated resolution is what makes a top-down game feel good: pressing into a
	# corner should still move you along the wall rather than stopping you dead.
	#
	# The DISTANCE is pinned, not just the direction, and that is what this test was missing.
	# `is_greater` passes under BOTH of the engine's motion modes - they both slide - so a
	# setting governing how every body in the game meets every wall sat unexamined for eleven
	# milestones behind the one test written to watch it. A test that cannot tell two answers
	# apart is not watching the thing it names.
	#
	# Driven by PHYSICS frames rather than await_millis: move_and_slide picks its own delta -
	# the idle one outside a physics frame - so a distance measured against the idle clock is a
	# fact about how busy the machine is, not about the game.
	var body := _spawn_player()
	await await_idle_frame()
	var against_top: Vector2 = await _walk_until_blocked(body, Vector2(0.0, -1.0))
	var from := body.global_position.x
	for i in SLIDE_FRAMES:
		body.apply(Vector2(1.0, -1.0))
		await get_tree().physics_frame
	var slid := body.global_position.x - from
	assert_float(slid).override_failure_message(
		"pressed into the top wall, the body slid %.2fpx in %d physics frames rather than %.2f"
		% [slid, SLIDE_FRAMES, SLIDE_PX]).is_equal_approx(SLIDE_PX, 0.5)
	assert_float(body.global_position.x).override_failure_message(
		"pressing into the top wall stopped all movement instead of sliding").is_greater(against_top.x)

func test_the_player_faces_the_way_it_walks() -> void:
	var body := _spawn_player()
	await await_idle_frame()
	await _tick(body, Vector2(0.0, 1.0), 2)
	assert_int(body.facing).is_equal(Dir.D.DOWN)
	assert_str(String(body.view.current_animation())).is_equal("walk_down")
	await _tick(body, Vector2.ZERO, 2)
	# Standing still keeps the facing, and only the clip changes.
	assert_int(body.facing).is_equal(Dir.D.DOWN)
	assert_str(String(body.view.current_animation())).is_equal("idle_down")

func test_halting_stops_the_body_dead() -> void:
	# Used whenever control is taken away. Without it the character slides on through the
	# frames where nobody is driving it.
	var body := _spawn_player()
	await await_idle_frame()
	await _tick(body, Vector2(1.0, 0.0), 5)
	body.halt()
	assert_vector(body.velocity).is_equal(Vector2.ZERO)
	assert_str(String(body.view.current_animation())).is_equal("idle_right")

func test_an_actor_stands_on_the_centre_of_its_spawn_tile() -> void:
	var body := _spawn_player()
	await await_idle_frame()
	var tile := _built.data.spawn(&"start")
	assert_vector(body.global_position).is_equal(MapData.tile_to_world(tile, _built.tile_size))
	assert_vector(body.tile(_built.tile_size)).is_equal(tile)


## Two bodies in contact - the first test in this repo to stage that at all.
##
## Seven QA sessions lean on an NPC body stopping the player, yet no suite ever put two
## ActorBodies together, so "a body blocks a body" was load-bearing and unpinned. The
## CARRYING half of that story cannot be tested here - driving apply() from a coroutine
## moves bodies outside a physics frame, where the server tracks no velocity for them and
## the platform mechanism cannot occur at all. It lives in test_world_npcs, through the
## real world scene. This is the half this harness can hold: they still collide.
func _spawn_body_at(at: Vector2) -> ActorBody:
	var body := ActorBody.new()
	body.setup(_config, FileSpriteSource.create(&"gb16"), &"hero")
	_built.sorted.add_child(body)
	body.global_position = at
	return body


## Drives both bodies for a while in the ORDER world_scene uses - the player resolves its
## move_and_slide first, then the NPCs - because that order is what hands an NPC the
## player's freshly-settled velocity.
func _tick_pair(blocker: ActorBody, blocker_input: Vector2, walker: ActorBody,
		walker_input: Vector2, ticks: int) -> void:
	for i in ticks:
		blocker.apply(blocker_input)
		walker.apply(walker_input)
		await get_tree().physics_frame

func test_a_body_still_stops_another_body() -> void:
	# The control for both tests above: they would also pass if the bodies simply stopped
	# colliding, which would silently break every QA session that walks into an NPC until
	# her body stops it.
	var blocker := _spawn_body_at(MapBuilder.spawn_position(_built.data, &"start", _built.tile_size))
	var walker := _spawn_body_at(blocker.global_position + Vector2(0.0, -10.0))
	await await_idle_frame()

	await _tick_pair(blocker, Vector2.ZERO, walker, Vector2(0.0, 1.0), 30)

	assert_float(walker.global_position.y).override_failure_message(
		"the walker passed through the body that should have stopped it").is_less(blocker.global_position.y)

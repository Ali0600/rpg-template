extends GdUnitTestSuite
## Grid stepping against real physics: a built map, real colliders, a real ActorBody.
##
## The unit suite proves what the walker decides. It cannot prove that the decision survives
## move_and_slide, that test_move sees the tiles' collision bodies, or that an actor driven
## through the same apply() the game calls lands on a cell centre - and those need the physics
## server, which does run headless.
##
## The invariant every case comes back to: **the actor is on a cell centre whenever no step is
## in flight.** Assertions are exact, because "near the centre" is what accumulates.

const FIXTURE_MAP := "res://tests/fixtures/maps/wall_east.json"
const CELL := 16
const TICKS_TO_SETTLE := 3

var _config: GameConfig
var _style: SpriteStyle
var _built: MapBuilder.Built
var _root: Node2D

func before_test() -> void:
	Router.reset()
	# The template's OWN defaults rather than the demo's file: this suite builds a 16px world,
	# and the shipped game is drawn at 32px now - its walk speed and its body are sized for
	# that. A 20px-wide body in a 16px corridor stops a tile early, which reads as the grid
	# walker refusing a step it should have taken.
	_config = GameConfig.new().at(CELL)
	# The one line that turns the mode on - a flag now rather than a distance, because a bound
	# config already knows how big a tile is and cannot be told a step that is not one.
	_config.grid_step = true
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

func _spawn() -> ActorBody:
	var body := ActorBody.new()
	body.setup(_config, FileSpriteSource.create(&"gb16"), &"hero")
	_built.sorted.add_child(body)
	body.place(MapBuilder.spawn_position(_built.data, &"start", _built.tile_size))
	return body

func _centre(tile: Vector2i) -> Vector2:
	return MapData.tile_to_world(tile, CELL)

## Runs a body until it is between steps, so an assertion lands on a cell centre rather than
## in the middle of one. Bounded and outcome-watching, never a tick count: a count would bake
## in walk_speed, which is meant to be tunable. Deliberately NOT _walk_until_blocked, whose
## "three still ticks means blocked" heuristic cannot tell a wall from a step that has not
## started yet.
func _finish_step(body: ActorBody, input: Vector2, max_ticks: int = 200) -> Vector2:
	for i in max_ticks:
		body.apply(input)
		await await_millis(1)
		if not body.stepping():
			return body.global_position
	assert_bool(false).override_failure_message("a step never finished").is_true()
	return body.global_position

## Tile collision bodies appear on the TileMapLayer's first physics update, so nothing may be
## asserted - and test_move cannot see a wall - before a couple of ticks have passed.
func _settle() -> void:
	for i in TICKS_TO_SETTLE:
		await await_millis(1)

func test_one_press_moves_exactly_one_tile_and_lands_on_its_centre() -> void:
	await _settle()
	var body := _spawn()
	var start := body.global_position
	var at := await _finish_step(body, Vector2.RIGHT)
	assert_vector(at).is_equal(start + Vector2(float(CELL), 0.0))
	assert_vector(at).is_equal(_centre(MapData.world_to_tile(at, CELL)))

func test_a_released_key_still_finishes_the_step() -> void:
	await _settle()
	var body := _spawn()
	var start := body.global_position
	body.apply(Vector2.RIGHT)
	await await_millis(1)
	assert_bool(body.stepping()).is_true()
	var at := await _finish_step(body, Vector2.ZERO)
	assert_vector(at).is_equal(start + Vector2(float(CELL), 0.0))

func test_five_steps_east_never_leave_the_actor_between_tiles() -> void:
	await _settle()
	var body := _spawn()
	var start := body.global_position
	for i in 5:
		var at := await _finish_step(body, Vector2.RIGHT)
		assert_vector(at).override_failure_message(
			"step %d ended between tiles at %s" % [i + 1, at]).is_equal(
				_centre(MapData.world_to_tile(at, CELL)))
	assert_vector(body.global_position).is_equal(start + Vector2(float(CELL) * 5.0, 0.0))

func test_a_wall_refuses_the_step_and_leaves_the_actor_on_a_centre() -> void:
	# The map is 8 wide with a wall at x=7, so the actor runs out of floor at tile 6.
	await _settle()
	var body := _spawn()
	for i in 8:
		await _finish_step(body, Vector2.RIGHT)
	var at := body.global_position
	assert_vector(at).is_equal(_centre(Vector2i(6, 2)))
	# And pressing again changes nothing at all - no jitter, no sliding into the wall.
	body.apply(Vector2.RIGHT)
	await await_millis(1)
	assert_vector(body.global_position).is_equal(at)
	assert_bool(body.stepping()).is_false()

func test_walking_into_a_wall_still_turns_to_face_it() -> void:
	await _settle()
	var body := _spawn()
	for i in 8:
		await _finish_step(body, Vector2.RIGHT)
	body.apply(Vector2.RIGHT)
	await await_millis(1)
	assert_int(body.facing).is_equal(Dir.D.RIGHT)
	assert_str(String(body.view.current_animation())).is_equal("idle_right")

func test_halting_mid_step_puts_the_actor_back_on_a_cell() -> void:
	# What a dialog opening does, every frame it is open.
	await _settle()
	var body := _spawn()
	var start := body.global_position
	body.apply(Vector2.RIGHT)
	await await_millis(1)
	assert_bool(body.stepping()).is_true()
	body.halt()
	assert_vector(body.global_position).is_equal(start)
	assert_bool(body.stepping()).is_false()
	assert_vector(body.velocity).is_equal(Vector2.ZERO)
	# And it stays put while the conversation is open.
	for i in 5:
		body.halt()
		await await_millis(1)
	assert_vector(body.global_position).is_equal(start)

func test_placing_mid_step_lands_exactly_where_it_was_told() -> void:
	# A warp. Cancel-then-assign, so the abandoned step cannot drag the actor back to a cell
	# in the map it just left.
	await _settle()
	var body := _spawn()
	body.apply(Vector2.RIGHT)
	await await_millis(1)
	assert_bool(body.stepping()).is_true()
	var destination := _centre(Vector2i(1, 3))
	body.place(destination, Dir.D.UP)
	assert_vector(body.global_position).is_equal(destination)
	assert_bool(body.stepping()).is_false()
	assert_int(body.facing).is_equal(Dir.D.UP)

func test_free_movement_is_still_what_the_shipped_config_does() -> void:
	# The promise of the whole milestone, asserted through a real body: with the shipped file
	# nothing steps, and moving is the pixel-at-a-time slide it always was.
	await _settle()
	var free_config := load("res://data/game_config.tres") as GameConfig
	assert_bool(free_config.grid_step).is_false()
	var body := ActorBody.new()
	body.setup(free_config, FileSpriteSource.create(&"gb16"), &"hero")
	_built.sorted.add_child(body)
	body.place(MapBuilder.spawn_position(_built.data, &"start", _built.tile_size))
	var start := body.global_position
	body.apply(Vector2.RIGHT)
	await await_millis(1)
	assert_bool(body.stepping()).is_false()
	assert_float(body.global_position.x).is_greater(start.x)
	assert_float(body.global_position.x).is_less(start.x + float(CELL))

extends GdUnitTestSuite
## Who the player is talking to, decided as geometry rather than by a physics ray.
##
## A ray reports whichever collider it hit first, and for two NPCs standing shoulder to
## shoulder that is whichever the engine inserted first - not the one the player is looking
## at. Doing it as pure geometry over a list also means these cases can be DESCRIBED rather
## than built: no scene, no bodies, no spawn positions.

const D := Dir.D

## The template's OWN defaults at its own reference tile, not the demo's file. Two reasons, and
## the second is the rule: the numbers below were written against a 16px tile, and a suite that
## named the size the DEMO is drawn at would go stale as a refusal the day its art changes -
## which is exactly what test_grid_movement already argues at the top of its own before_test.
const TILE := 16

var _config: GameConfig

func before_test() -> void:
	_config = GameConfig.new().at(TILE)

func _target(id: String, at: Vector2) -> Interactor.Target:
	return Interactor.Target.new(StringName(id), at, _config.body_size_px())

func test_nothing_in_front_means_nothing_happens() -> void:
	var targets: Array[Interactor.Target] = []
	assert_object(Interactor.find(Vector2.ZERO, D.RIGHT, _config, targets)).is_null()

func test_the_thing_directly_in_front_is_chosen() -> void:
	var targets: Array[Interactor.Target] = [_target("ahead", Vector2(14.0, 0.0))]
	var found := Interactor.find(Vector2.ZERO, D.RIGHT, _config, targets)
	assert_object(found).is_not_null()
	assert_str(String(found.id)).is_equal("ahead")

func test_something_behind_is_ignored() -> void:
	# The most obvious failure of a distance-only check: turning your back on someone and
	# still talking to them.
	var targets: Array[Interactor.Target] = [_target("behind", Vector2(-14.0, 0.0))]
	assert_object(Interactor.find(Vector2.ZERO, D.RIGHT, _config, targets)).is_null()

func test_facing_decides_which_of_two_neighbours_is_chosen() -> void:
	var targets: Array[Interactor.Target] = [
		_target("east", Vector2(14.0, 0.0)),
		_target("west", Vector2(-14.0, 0.0)),
	]
	assert_str(String(Interactor.find(Vector2.ZERO, D.RIGHT, _config, targets).id)).is_equal("east")
	assert_str(String(Interactor.find(Vector2.ZERO, D.LEFT, _config, targets).id)).is_equal("west")

func test_the_nearer_of_two_in_the_same_direction_wins() -> void:
	var targets: Array[Interactor.Target] = [
		_target("far", Vector2(20.0, 0.0)),
		_target("near", Vector2(10.0, 0.0)),
	]
	assert_str(String(Interactor.find(Vector2.ZERO, D.RIGHT, _config, targets).id)).is_equal("near")

func test_the_order_of_the_list_does_not_decide() -> void:
	# The exact thing a physics ray gets wrong. Same situation, reversed list, same answer.
	var forwards: Array[Interactor.Target] = [_target("far", Vector2(20.0, 0.0)), _target("near", Vector2(10.0, 0.0))]
	var backwards: Array[Interactor.Target] = [_target("near", Vector2(10.0, 0.0)), _target("far", Vector2(20.0, 0.0))]
	assert_str(String(Interactor.find(Vector2.ZERO, D.RIGHT, _config, forwards).id)) \
		.is_equal(String(Interactor.find(Vector2.ZERO, D.RIGHT, _config, backwards).id))

func test_standing_just_out_of_reach_still_works() -> void:
	# Without the fallback, being one pixel too far away does nothing at all - and to a
	# player that is indistinguishable from the button being broken.
	var just_past := _config.interact_reach_px() + _config.body_size_px().x - 1.0
	var targets: Array[Interactor.Target] = [_target("ahead", Vector2(just_past, 0.0))]
	assert_object(Interactor.find(Vector2.ZERO, D.RIGHT, _config, targets)).is_not_null()

func test_far_away_is_still_out_of_reach() -> void:
	# The fallback is generous, not unlimited: shouting across the map is not interacting.
	var targets: Array[Interactor.Target] = [_target("distant", Vector2(200.0, 0.0))]
	assert_object(Interactor.find(Vector2.ZERO, D.RIGHT, _config, targets)).is_null()

func test_it_works_in_all_four_directions() -> void:
	for dir: int in Dir.ALL:
		var at := Dir.vector_of(dir) * 14.0
		var targets: Array[Interactor.Target] = [_target("neighbour", at)]
		assert_object(Interactor.find(Vector2.ZERO, dir, _config, targets)) \
			.override_failure_message("nothing found facing %s" % Dir.name_of(dir)).is_not_null()

func test_a_targets_box_sits_above_its_feet() -> void:
	# The same rule as the collision box: a character's position is where it STANDS, so its
	# body occupies the space above that point.
	var target := _target("someone", Vector2(0.0, 0.0))
	assert_float(target.rect().end.y).is_equal_approx(0.0, 0.01)
	assert_float(target.rect().position.y).is_equal_approx(-_config.body_size_px().y, 0.01)

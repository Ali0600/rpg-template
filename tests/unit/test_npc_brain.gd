extends GdUnitTestSuite
## What an NPC decides, with no world, no bodies and no clock.
##
## NpcBrain is pure for the same reason Locomotion and GridWalker are: "a wanderer stays near
## home" and "a patrol walks its path in order" are rules, and a rule tested through a scene
## is a rule tested through three other things at once.
##
## Every sample point here is a LITERAL. Deriving a probe from the constant under test makes
## the test move with the mutation it is supposed to catch - the loop bound that follows its
## own constant to zero and asserts nothing.

const TILE := 16

func _rng(label: String) -> SeededRng:
	return SeededRng.new(SeededRng.hash_seed(0, label))

func _brain(record: Dictionary, at_tile: Vector2i, label: String = "npc") -> NpcBrain:
	return NpcBrain.of(record, MapData.tile_to_world(at_tile, TILE), TILE, _rng(label))

## Runs the brain for a number of frames, MOVING toward whatever it asks for, and returns
## every position visited. A real body is not needed: the contract is an intent vector, and
## walking it by hand is what keeps this suite free of the scene tree.
func _walk(brain: NpcBrain, from: Vector2i, frames: int, speed: float = 4.0) -> Array[Vector2]:
	var at := MapData.tile_to_world(from, TILE)
	var seen: Array[Vector2] = [at]
	for i in frames:
		var want := brain.intent(at)
		at += want * speed
		seen.append(at)
	return seen

func test_a_static_npc_never_asks_to_move() -> void:
	# The control for this whole file, and the shipped default: every NPC the demo game has
	# is static, and several QA sessions use their bodies as walls.
	var brain := _brain({"behavior": "static"}, Vector2i(4, 4))
	for i in 200:
		assert_vector(brain.intent(Vector2(64.0, 64.0))).is_equal(Vector2.ZERO)

func test_an_absent_behavior_is_static() -> void:
	# A map written before behaviours existed must keep working unchanged.
	assert_int(_brain({}, Vector2i(1, 1)).kind).is_equal(NpcBrain.Kind.STATIC)

func test_an_unknown_behavior_name_is_refused_not_guessed() -> void:
	assert_int(NpcBrain.kind_from_name("wonder")).is_less(0)
	assert_int(NpcBrain.kind_from_name("wander")).is_equal(NpcBrain.Kind.WANDER)

func test_a_wanderer_stays_within_its_range_of_home() -> void:
	# The bound is the point of the behaviour: a shopkeeper who leaves the shop is a bug the
	# player reads as the game losing track of her.
	var home := Vector2i(8, 8)
	var brain := _brain({"behavior": "wander", "range": 2, "dwell_min": 0, "dwell_max": 2}, home)
	for at in _walk(brain, home, 900):
		var tile := MapData.world_to_tile(at, TILE)
		assert_int(absi(tile.x - home.x)).override_failure_message(
			"wandered to %s, home is %s" % [tile, home]).is_less_equal(2)
		assert_int(absi(tile.y - home.y)).override_failure_message(
			"wandered to %s, home is %s" % [tile, home]).is_less_equal(2)

func test_a_wanderer_actually_moves() -> void:
	# The near miss for the bound above: a brain that never left home would satisfy it.
	var home := Vector2i(8, 8)
	var brain := _brain({"behavior": "wander", "range": 2, "dwell_min": 0, "dwell_max": 2}, home)
	var seen := _walk(brain, home, 300)
	assert_float(seen[0].distance_to(seen[seen.size() - 1])).is_greater(0.0)

func test_the_same_seed_decides_the_same_walk() -> void:
	var home := Vector2i(5, 5)
	var opts := {"behavior": "wander", "range": 3, "dwell_min": 1, "dwell_max": 4}
	var a := _walk(_brain(opts, home, "same"), home, 400)
	var b := _walk(_brain(opts, home, "same"), home, 400)
	assert_array(a).is_equal(b)

func test_a_different_seed_decides_a_different_walk() -> void:
	# Without this, the equality above would also pass for a brain that ignores its rng.
	var home := Vector2i(5, 5)
	var opts := {"behavior": "wander", "range": 3, "dwell_min": 1, "dwell_max": 4}
	var a := _walk(_brain(opts, home, "one"), home, 400)
	var b := _walk(_brain(opts, home, "two"), home, 400)
	assert_array(a).is_not_equal(b)

func test_a_patrol_visits_its_waypoints_in_the_authored_order() -> void:
	# Asserted by waypoint VALUE, never by an index count: inserting a point must not quietly
	# re-aim this test at whatever now sits at position 1.
	var path := [[2, 2], [5, 2], [5, 6]]
	# Placed OFF the path on purpose. An NPC standing on its first waypoint has already
	# arrived there - correct, and self-correcting after one dwell - but it means the first
	# target a probe can observe is the SECOND point, which is not what this test is about.
	var brain := _brain({"behavior": "patrol", "path": path, "dwell_min": 0, "dwell_max": 0},
		Vector2i(1, 1))
	var wanted: Array[Vector2] = []
	for pt: Variant in path:
		var pair := JsonFile.to_int_array(pt)
		wanted.append(MapData.tile_to_world(Vector2i(pair[0], pair[1]), TILE))

	var order: Array[Vector2] = []
	var at := MapData.tile_to_world(Vector2i(1, 1), TILE)
	for i in 2000:
		var want := brain.intent(at)
		if brain.has_target() and not order.has(brain.target()):
			order.append(brain.target())
		at += want * 4.0
		if order.size() == wanted.size():
			break
	assert_array(order).is_equal(wanted)

func test_arriving_is_measured_in_tiles_so_a_bigger_world_is_not_a_shuffle() -> void:
	# What "close enough" means is set by how far a body travels in a frame, and that doubles
	# with the world. A flat 1.5px at 32px tiles is under two frames of walking, so a patroller
	# would arrive, overshoot, turn round and shuffle on the spot forever.
	#
	# Literals on both sides, and the pair is the test: 2px short is arrival on a 32px map and
	# is NOT arrival on a 16px one. A single sample could be satisfied by any constant at all.
	# Dwell zero, or the first intent is the brain standing about and this measures that
	# instead - the margin is only reachable once it is actually walking somewhere.
	var record := {"behavior": "patrol", "path": [[4, 4], [8, 4]], "dwell_min": 0, "dwell_max": 0}
	var wide := NpcBrain.of(record, MapData.tile_to_world(Vector2i(4, 4), 32), 32, _rng("wide"))
	var narrow := NpcBrain.of(record, MapData.tile_to_world(Vector2i(4, 4), TILE), TILE, _rng("narrow"))
	var short_by_2 := func(brain: NpcBrain, tile: int) -> Vector2:
		return brain.intent(MapData.tile_to_world(Vector2i(4, 4), tile) - Vector2(2.0, 0.0))
	assert_vector(short_by_2.call(wide, 32)).override_failure_message(
		"two pixels short of a waypoint on a 32px map is still being walked at"
		).is_equal(Vector2.ZERO)
	assert_vector(short_by_2.call(narrow, TILE)).override_failure_message(
		"two pixels short of a waypoint on a 16px map counts as arrived, which is the margin"
		+ " every shipped session was recorded against").is_not_equal(Vector2.ZERO)


func test_a_patrol_with_no_path_stands_still_rather_than_spinning() -> void:
	var brain := _brain({"behavior": "patrol", "path": []}, Vector2i(3, 3))
	for i in 60:
		assert_vector(brain.intent(Vector2(48.0, 48.0))).is_equal(Vector2.ZERO)

func test_dwelling_counts_frames_and_ends() -> void:
	# Frames, never wall-clock: under load a millisecond spans no physics frame at all, and
	# "the NPC waited" would become a fact about how busy the machine is.
	var brain := _brain({"behavior": "patrol", "path": [[4, 1], [6, 1]],
		"dwell_min": 5, "dwell_max": 5}, Vector2i(1, 1))
	var at := MapData.tile_to_world(Vector2i(1, 1), TILE)
	for i in 5:
		assert_vector(brain.intent(at)).override_failure_message(
			"frame %d should still be dwelling" % i).is_equal(Vector2.ZERO)
	assert_vector(brain.intent(at)).is_not_equal(Vector2.ZERO)

func test_a_blocked_patroller_gives_up_instead_of_pushing_forever() -> void:
	# Standing still against an obstruction: the brain sees no progress and eventually stops
	# asking. Two NPCs meeting in a corridor must not shove each other for the whole session.
	var brain := _brain({"behavior": "patrol", "path": [[1, 1], [6, 1]],
		"dwell_min": 0, "dwell_max": 0}, Vector2i(1, 1))
	var at := MapData.tile_to_world(Vector2i(1, 1), TILE)
	var asked := 0
	for i in NpcBrain.STUCK_FRAMES + 6:
		if brain.intent(at) != Vector2.ZERO:
			asked += 1
	assert_int(asked).override_failure_message(
		"kept pushing for all %d frames" % (NpcBrain.STUCK_FRAMES + 6)).is_less(NpcBrain.STUCK_FRAMES + 6)

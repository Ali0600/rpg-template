extends GdUnitTestSuite
## The walk planner and the shrinker, proven without a world.
##
## FlowWalk is deliberately pure — a walk is a list of edge indices — so everything about which
## steps a seed produces and which shorter walk a failure minimises to can be settled here, in
## milliseconds, against a synthetic model of three edges. The integration suite is then left
## with the one thing only it can do: actually driving the steps.

const MODEL := "res://tools/flow_model.json"


func _edges() -> Array:
	var file := JsonFile.read(MODEL)
	assert_bool(file.ok).override_failure_message(
		"the flow model could not be read: %s" % file.error).is_true()
	return file.data.get("edges", [])


## Three edges over three states: a there-and-back cycle, and one way out of it. Small enough
## that the right answer can be written down by hand, which is the point — a shrinker checked
## against a model nobody can hold in their head proves only that it returned something.
func _toy() -> Array:
	return [
		{"action": "go", "from": "a", "to": "b"},
		{"action": "back", "from": "b", "to": "a"},
		{"action": "finish", "from": "b", "to": "c"},
	]


## Four edges over two states, where each direction has a twin. A walk here is NOT periodic, so
## eliding different cycles yields genuinely different sequences - which is what it takes to
## generate more candidates than the shrinker is allowed to try.
func _forked_toy() -> Array:
	return [
		{"action": "out", "from": "a", "to": "b"},
		{"action": "home", "from": "b", "to": "a"},
		{"action": "out_again", "from": "a", "to": "b"},
		{"action": "home_again", "from": "b", "to": "a"},
	]


# --- the planner ---------------------------------------------------------------------------


func test_a_planned_walk_is_connected_end_to_end() -> void:
	# The load-bearing property. Every step must leave the state the step before it arrived in,
	# or the walk cannot be driven at all and a failure would say nothing about the game.
	var edges := _edges()
	for seed_value in 12:
		var walk := FlowWalk.plan(edges, "title", seed_value, 24)
		assert_bool(FlowWalk.is_a_walk(edges, "title", walk)).override_failure_message(
			"seed %d planned %s, which is not a connected walk from title"
			% [seed_value, FlowWalk.actions_of(edges, walk)]).is_true()


func test_a_walk_is_the_same_walk_every_time_for_one_seed() -> void:
	# A failure is worth reporting only if it can be re-run. Two plans from one seed that
	# differed would make every walk failure a story rather than a reproduction.
	var edges := _edges()
	assert_array(FlowWalk.plan(edges, "title", 7, 20)).is_equal(
		FlowWalk.plan(edges, "title", 7, 20))


func test_different_seeds_walk_differently() -> void:
	# The mirror of the test above, and not a formality: a planner that ignored its seed would
	# satisfy determinism perfectly while turning every walk in the suite into one walk.
	var edges := _edges()
	var seen: Array[String] = []
	for seed_value in 8:
		var walk := str(FlowWalk.plan(edges, "title", seed_value, 20))
		if not seen.has(walk):
			seen.append(walk)
	assert_int(seen.size()).override_failure_message(
		"eight seeds produced %d distinct walks" % seen.size()).is_greater(1)


func test_a_walk_never_spends_a_step_on_boot() -> void:
	# `boot` is the process opening on the title. It is a real row in the model and the per-edge
	# gate checks it, but a walk that takes it is a walk that stood still.
	var edges := _edges()
	for seed_value in 12:
		var walk := FlowWalk.plan(edges, "title", seed_value, 24)
		assert_array(Array(FlowWalk.actions_of(edges, walk))).override_failure_message(
			"seed %d spent a step on boot" % seed_value).not_contains(["boot"])


func test_a_walk_is_as_long_as_it_was_asked_for() -> void:
	# A short walk is the honest answer at a state nothing leaves, and the shipped model has no
	# such state - so a walk that comes back short here means the planner gave up somewhere it
	# should not have, and every seeded walk in the suite is quietly testing less than it says.
	var edges := _edges()
	assert_int(FlowWalk.plan(edges, "title", 3, 30).size()).is_equal(30)


func test_a_disconnected_walk_is_rejected() -> void:
	# The connectivity check is what the two tests above lean on, so it gets its own negative:
	# an instrument that cannot fail is not a check.
	var toy := _toy()
	assert_bool(FlowWalk.is_a_walk(toy, "a", [0, 2])).is_true()
	assert_bool(FlowWalk.is_a_walk(toy, "a", [0, 0])).override_failure_message(
		"two 'go' steps in a row leave state b twice, and were accepted").is_false()
	assert_bool(FlowWalk.is_a_walk(toy, "a", [1])).is_false()
	assert_bool(FlowWalk.is_a_walk(toy, "a", [99])).is_false()


# --- the shrinker --------------------------------------------------------------------------


## Runs a shrink to completion against a predicate, the way the integration suite does with a
## real world in place of the predicate.
func _shrink(edges: Array, start: String, failing: Array[int], fails: Callable) -> FlowWalk.Shrinker:
	var shrinker := FlowWalk.Shrinker.new(edges, start, failing)
	while shrinker.has_candidate():
		shrinker.report(bool(fails.call(shrinker.candidate())))
	return shrinker


func test_every_candidate_offered_is_itself_a_walk() -> void:
	# Cycle elision's whole claim. If a candidate were disconnected, its re-run would fail for a
	# reason that has nothing to do with the bug - and the shrinker would happily adopt it and
	# report a walk that never reproduced anything.
	var toy := _toy()
	var walk: Array[int] = [0, 1, 0, 1, 0, 2]
	for candidate: Array in FlowWalk.elisions(toy, "a", walk):
		var typed: Array[int] = []
		typed.assign(candidate)
		assert_bool(FlowWalk.is_a_walk(toy, "a", typed)).override_failure_message(
			"the shrinker offered %s, which is not a walk" % [typed]).is_true()
		assert_int(typed.size()).is_less(walk.size())


func test_a_failing_walk_shrinks_to_the_shortest_one_that_still_fails() -> void:
	# Six steps in, the failure is the last one; the three round trips before it are noise. The
	# answer is written down by hand rather than derived, because a shrinker checked against its
	# own arithmetic is a shrinker checked against nothing.
	var toy := _toy()
	var reaches_c := func(walk: Array) -> bool: return walk.has(2)
	var shrinker := _shrink(toy, "a", [0, 1, 0, 1, 0, 2], reaches_c)
	assert_array(shrinker.best()).override_failure_message(
		"six steps minimised to %s" % [FlowWalk.actions_of(toy, shrinker.best())]).is_equal([0, 2])


func test_a_walk_with_nothing_to_remove_is_reported_as_it_stands() -> void:
	# The other end. When no shorter walk reproduces the failure, the original IS the answer -
	# a shrinker that returned something shorter here would be reporting a walk that passes.
	var toy := _toy()
	var walk: Array[int] = [0, 1, 0, 1, 0, 2]
	var needs_every_step := func(candidate: Array) -> bool: return candidate.size() >= walk.size()
	var shrinker := _shrink(toy, "a", walk, needs_every_step)
	assert_array(shrinker.best()).is_equal(walk)
	assert_int(shrinker.tries()).override_failure_message(
		"nothing was tried, so the shrink proved nothing").is_greater(0)


func test_the_shrink_gives_up_rather_than_running_forever() -> void:
	# Each try drives a whole walk through a real world, so the budget is the difference between
	# a slow failure report and one nobody waits for. The walk that failed is reported either
	# way, minimised as far as the budget reached.
	var forked := _forked_toy()
	var walk := FlowWalk.plan(forked, "a", 5, 14)
	var never := func(_candidate: Array) -> bool: return false
	var shrinker := _shrink(forked, "a", walk, never)
	assert_int(FlowWalk.elisions(forked, "a", walk).size()).override_failure_message(
		"this fixture offers fewer candidates than the budget, so the cap was never reached"
	).is_greater(FlowWalk.Shrinker.MAX_TRIES)
	assert_int(shrinker.tries()).is_equal(FlowWalk.Shrinker.MAX_TRIES)
	assert_bool(shrinker.has_candidate()).is_false()


func test_the_shortest_candidate_is_offered_first() -> void:
	# Shortest-first is what makes one try usually enough. It also has to be a TOTAL order:
	# sort_custom is not stable, so two candidates of equal length must be separated by
	# something, or the walk this reports depends on the machine that ran it.
	var toy := _toy()
	var walk: Array[int] = [0, 1, 0, 1, 0, 2]
	var offered := FlowWalk.elisions(toy, "a", walk)
	assert_array(offered.front()).is_equal([0, 2])
	var lengths: Array[int] = []
	for candidate: Array in offered:
		lengths.append(candidate.size())
	var sorted_lengths := lengths.duplicate()
	sorted_lengths.sort()
	assert_array(lengths).override_failure_message(
		"candidates came back in the order %s" % [lengths]).is_equal(sorted_lengths)
	assert_array(FlowWalk.elisions(toy, "a", walk)).is_equal(offered)

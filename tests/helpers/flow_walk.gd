class_name FlowWalk
extends RefCounted
## Plans WALKS over the flow model, and minimises one that fails.
##
## tools/flow_model.json declares 17 edges and test_flow_model.gd drives each of them ONCE,
## from a world built fresh for it. That proves every edge is individually correct and is
## silent about every SEQUENCE of them — which is the shape of the bug the model was built
## after. Continue arrived at WORLD exactly as declared; it passed through the start map on
## the way, and the start map's entry hooks fired. No single edge was wrong.
##
## So this plans a connected sequence of edges from a seed, and the suite drives the whole
## sequence on ONE world that is never rebuilt between steps. An edge that behaves differently
## because of what came before it has nowhere left to hide.
##
## EVERYTHING HERE IS PURE. No tree, no world, no `await`, no engine state — a walk is a list
## of integers and a shrink is arithmetic over that list, so both are unit-testable without a
## scene and the integration suite is left with nothing to do but drive what it is handed.

## `boot` describes the process opening on the title rather than an action a player takes, so a
## walk never spends a step on it. It stays in the model because the per-edge gate checks it.
const NOT_WALKABLE: Array[String] = ["boot"]


## The indices of every edge that leaves `from` and is worth walking.
static func out_edges(edges: Array, from: String) -> Array[int]:
	var out: Array[int] = []
	for i in edges.size():
		var edge: Dictionary = edges[i]
		if NOT_WALKABLE.has(str(edge.get("action", ""))):
			continue
		if str(edge.get("from", "")) == from:
			out.append(i)
	return out


## A connected sequence of edge indices, drawn from a seed so the same seed is the same walk on
## every machine and in every re-run — which is what makes a failure something to reproduce
## rather than something to describe. SeededRng because the linter fails the build on anything
## that draws from the generator nobody seeded.
##
## Stops early at a state nothing leaves. That cannot happen in the shipped model
## (test_flow_model.gd fails on a trap outright) and returning a short walk is the honest answer
## if it ever does, rather than looping forever looking for an edge that is not there.
static func plan(edges: Array, start: String, seed_value: int, length: int) -> Array[int]:
	var rng := SeededRng.new(seed_value)
	var out: Array[int] = []
	var here := start
	for step in length:
		var options := out_edges(edges, here)
		if options.is_empty():
			break
		var chosen: int = options[rng.next_int(0, options.size() - 1)]
		out.append(chosen)
		var edge: Dictionary = edges[chosen]
		here = str(edge.get("to", ""))
	return out


## The states a walk passes through: one more entry than there are steps, because it includes
## where the walk started and where it ended.
static func path_of(edges: Array, start: String, sequence: Array[int]) -> Array[String]:
	var out: Array[String] = [start]
	var here := start
	for index in sequence:
		var edge: Dictionary = edges[index]
		here = str(edge.get("to", ""))
		out.append(here)
	return out


## Whether every step in a sequence actually leaves the state the one before it arrived in. The
## planner cannot produce a disconnected walk and neither can the shrinker, so this exists to
## PROVE that rather than to be believed — a shrink that quietly breaks connectivity would fail
## the re-run for a reason that has nothing to do with the bug being minimised.
##
## NOT `is_connected`, which every Object already has (it answers whether a signal is wired to a
## callable). A static method cannot shadow an inherited one, and the parse error names only the
## call site, so it reads as a missing function rather than as a collision with the engine.
static func is_a_walk(edges: Array, start: String, sequence: Array[int]) -> bool:
	var here := start
	for index in sequence:
		if index < 0 or index >= edges.size():
			return false
		var edge: Dictionary = edges[index]
		if str(edge.get("from", "")) != here:
			return false
		here = str(edge.get("to", ""))
	return true


## A walk in the model's own words, for a failure message. An index tells nobody anything.
static func actions_of(edges: Array, sequence: Array[int]) -> PackedStringArray:
	var out := PackedStringArray()
	for index in sequence:
		var edge: Dictionary = edges[index]
		out.append(str(edge.get("action", "")))
	return out


## Every shorter walk reachable by deleting one CYCLE — the steps between two positions that
## sit in the same state.
##
## Cycle elision is the whole shrinking strategy, and the reason is that it cannot produce an
## invalid candidate. Dropping an arbitrary step from a walk usually disconnects it (the step
## after it leaves a state the walk is no longer in), so a general delta-debugger over a graph
## walk spends most of its budget generating sequences that cannot be driven at all, and has to
## tell "this candidate does not reproduce the failure" apart from "this candidate is not a
## walk". Deleting a round trip leaves the two ends touching in the same state, so every
## candidate here is drivable by construction and a re-run failing means exactly one thing.
##
## Shortest first, ties broken by the order they were generated: sort_custom is not stable, so
## the comparator ranks by generation index rather than leaving equal-length candidates to
## whatever order the sort happens to leave them in. A shrink that reported a different walk on
## a different machine would be worse than no shrink.
static func elisions(edges: Array, start: String, sequence: Array[int]) -> Array[Array]:
	var path := path_of(edges, start, sequence)
	var found: Array[Array] = []
	for i in path.size():
		for j in range(i + 1, path.size()):
			if path[i] != path[j]:
				continue
			var shorter: Array[int] = []
			shorter.append_array(sequence.slice(0, i))
			shorter.append_array(sequence.slice(j))
			if not found.has(shorter):
				found.append(shorter)
	var order: Array[int] = []
	for k in found.size():
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool:
		var left: Array = found[a]
		var right: Array = found[b]
		if left.size() != right.size():
			return left.size() < right.size()
		return a < b)
	var out: Array[Array] = []
	for k in order:
		out.append(found[k])
	return out


## Minimises a failing walk, driven from OUTSIDE.
##
## The shrinker cannot run a walk — running one needs a world, a scene tree and a great many
## awaited frames. So it does not try to own the loop. It offers a candidate, is told whether
## that candidate still fails, and offers the next one:
##
##     var shrinker := FlowWalk.Shrinker.new(edges, start, failing)
##     while shrinker.has_candidate():
##         shrinker.report(await _walk_fails(shrinker.candidate()))
##     print(FlowWalk.actions_of(edges, shrinker.best()))
##
## Inverting the loop like this is what keeps the search pure: the decision of what to try next
## is arithmetic over integers, unit-tested against a synthetic predicate in milliseconds, while
## the expensive half stays in the suite that already knows how to drive an edge.
class Shrinker extends RefCounted:
	## A ceiling on re-runs, because each one drives a whole walk through a real world. A
	## shrink that never finishes is a failure report nobody ever reads: the walk that failed
	## is always reported, minimised as far as the budget got.
	const MAX_TRIES := 24

	var _edges: Array = []
	var _start := ""
	var _best: Array[int] = []
	var _queue: Array[Array] = []
	var _current: Array[int] = []
	var _tries := 0

	func _init(edges: Array, start: String, failing: Array[int]) -> void:
		_edges = edges
		_start = start
		_best = failing.duplicate()
		_queue = FlowWalk.elisions(_edges, _start, _best)

	func has_candidate() -> bool:
		return _tries < MAX_TRIES and not _queue.is_empty()

	func candidate() -> Array[int]:
		_current = _queue.pop_front()
		_tries += 1
		return _current

	## `still_fails` is about the CANDIDATE, not about the original: true means the shorter walk
	## reproduced the failure and becomes the new best, which re-opens the search from there
	## because a walk that just lost a cycle may well have another.
	func report(still_fails: bool) -> void:
		if still_fails:
			_best = _current
			_queue = FlowWalk.elisions(_edges, _start, _best)

	func best() -> Array[int]:
		return _best

	func tries() -> int:
		return _tries

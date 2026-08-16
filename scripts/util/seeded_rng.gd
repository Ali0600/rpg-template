class_name SeededRng
extends RefCounted
## A random source that must be handed a seed, so any result can be reproduced.
##
## Godot's global `randi()`/`randf()`/`Array.pick_random()`/`Array.shuffle()` draw from a
## process-wide generator nobody seeds. A sprite generated with them looks fine and is
## different on the next run, which breaks the golden-hash gate, the "same seed, same
## bytes" promise, and any bug report that says "the NPC in the corner looks wrong".
## tools/lint_rules.gd fails the build on those calls; this is the replacement.

var _rng := RandomNumberGenerator.new()
var _seed: int = 0


func _init(seed_value: int = 0) -> void:
	_seed = seed_value
	_rng.seed = seed_value


func seed_value() -> int:
	return _seed


## A child generator whose stream is derived from this one's seed and a label. Deriving
## per-purpose streams means adding a new randomised feature cannot shift the numbers an
## existing one already drew: hair colour keeps its sequence when clothing gains a variant.
func derive(label: String) -> SeededRng:
	return SeededRng.new(hash_seed(_seed, label))


static func hash_seed(base: int, label: String) -> int:
	return hash("%d:%s" % [base, label])


func next_int(from: int, to_inclusive: int) -> int:
	return _rng.randi_range(from, to_inclusive)


func next_float(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func chance(probability: float) -> bool:
	return _rng.randf() < probability


## Picks one element without touching the global generator. Returns the fallback for an
## empty array rather than erroring, because content lists are data and a missing entry is
## a data bug the caller reports with its own context.
func pick(options: Array, fallback: Variant = null) -> Variant:
	if options.is_empty():
		return fallback
	return options[_rng.randi_range(0, options.size() - 1)]


## Fisher-Yates against the seeded stream. A copy is returned; shuffling in place would
## make the caller's data order depend on how many times it had been read.
func shuffled(options: Array) -> Array:
	var out := options.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out

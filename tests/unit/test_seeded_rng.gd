extends GdUnitTestSuite
## Proves the generator is reproducible, seed-sensitive, and stream-isolated.
##
## "Same seed, same sprite" is the promise the golden-hash gate and every regenerate-and-
## diff check rest on. Derived streams matter for a subtler reason: if hair and clothing
## drew from one sequence, adding a clothing variant would shift every existing character's
## hair, and a template whose NPCs all change when you add a feature is not usable.

func test_the_same_seed_replays_the_same_numbers() -> void:
	assert_array(_draw(11)).is_equal(_draw(11))

func test_a_different_seed_draws_differently() -> void:
	assert_array(_draw(11)).is_not_equal(_draw(12))

func _draw(seed_value: int) -> Array[int]:
	var rng := SeededRng.new(seed_value)
	var out: Array[int] = []
	for i in 8:
		out.append(rng.next_int(0, 999))
	return out

func test_derived_streams_are_independent_of_each_other() -> void:
	# Drawing from "hair" must give the same answer whether or not "cloth" was drawn first.
	var a := SeededRng.new(5)
	var hair_first := a.derive("hair").next_int(0, 999)
	var b := SeededRng.new(5)
	b.derive("cloth").next_int(0, 999)
	assert_int(b.derive("hair").next_int(0, 999)).is_equal(hair_first)

func test_derived_streams_differ_by_label() -> void:
	var rng := SeededRng.new(5)
	assert_int(rng.derive("hair").next_int(0, 999999)).is_not_equal(rng.derive("cloth").next_int(0, 999999))

func test_pick_is_reproducible_and_bounded() -> void:
	var options := ["a", "b", "c", "d"]
	assert_str(str(SeededRng.new(3).pick(options))).is_equal(str(SeededRng.new(3).pick(options)))
	assert_bool(options.has(SeededRng.new(3).pick(options))).is_true()

func test_pick_on_an_empty_list_returns_the_fallback() -> void:
	assert_str(str(SeededRng.new(1).pick([], "none"))).is_equal("none")

func test_shuffled_returns_a_copy_and_keeps_every_element() -> void:
	var source := [1, 2, 3, 4, 5, 6]
	var rng := SeededRng.new(9)
	var out := rng.shuffled(source)
	assert_array(source).is_equal([1, 2, 3, 4, 5, 6])
	var sorted_out := out.duplicate()
	sorted_out.sort()
	assert_array(sorted_out).is_equal([1, 2, 3, 4, 5, 6])
	assert_array(SeededRng.new(9).shuffled(source)).is_equal(out)

func test_chance_is_reproducible() -> void:
	var a: Array[bool] = []
	var b: Array[bool] = []
	var ra := SeededRng.new(42)
	var rb := SeededRng.new(42)
	for i in 10:
		a.append(ra.chance(0.5))
		b.append(rb.chance(0.5))
	assert_array(a).is_equal(b)

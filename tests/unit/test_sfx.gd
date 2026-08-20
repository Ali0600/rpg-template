extends GdUnitTestSuite
## The cue vocabulary. Small, and worth pinning precisely because it is the thing that makes a
## misspelled sound impossible: if the enum and the id table can drift apart, the compile-time
## guarantee they exist to provide is gone and nothing else in the project would notice.


func test_every_cue_has_an_id() -> void:
	for cue: int in Sfx.Cue.values():
		assert_str(String(Sfx.id_of(cue))).override_failure_message(
			"cue %d has no id" % cue).is_not_empty()


func test_the_table_covers_the_enum_exactly() -> void:
	# The failure this catches is a cue added to the enum and forgotten in IDS, which would
	# resolve to "" and then to no sound at all - silently, which is the whole problem.
	assert_int(Sfx.IDS.size()).is_equal(Sfx.Cue.values().size())
	assert_int(Sfx.ids().size()).is_equal(Sfx.Cue.values().size())


func test_no_two_cues_share_an_id() -> void:
	var seen: Array[StringName] = []
	for id in Sfx.ids():
		assert_bool(seen.has(id)).override_failure_message(
			"'%s' is the id of two different cues" % id).is_false()
		seen.append(id)


func test_a_name_round_trips_back_to_its_cue() -> void:
	for cue: int in Sfx.Cue.values():
		assert_int(Sfx.of(Sfx.id_of(cue))).override_failure_message(
			"'%s' did not resolve back to cue %d" % [Sfx.id_of(cue), cue]).is_equal(cue)


func test_a_name_no_cue_has_is_refused_rather_than_guessed() -> void:
	# What content validation leans on. Returning some near-match would put a plausible wrong
	# noise where a reported content error belongs.
	assert_int(Sfx.of(&"footstepp")).is_equal(-1)
	assert_int(Sfx.of(&"")).is_equal(-1)


func test_a_value_outside_the_enum_resolves_to_no_sound() -> void:
	assert_str(String(Sfx.id_of(9999 as Sfx.Cue))).is_empty()

extends GdUnitTestSuite
## A tune, read as data. No synth, no style, no files beyond the shipped ones.

func _track(bars: Array, instrument := {"wave": "tone"}) -> MusicTrack:
	var track := MusicTrack.new()
	track.id = &"probe"
	track.instruments = {&"lead": instrument}
	track._read_voices([{"instrument": "lead", "bars": bars}])
	return track


func test_the_shipped_tunes_have_nothing_wrong_with_them() -> void:
	var count := 0
	for id in MusicTrack.ids():
		var track := MusicTrack.load_from(id)
		assert_array(track.problems()).override_failure_message(
			"track '%s': %s" % [id, track.problems()]).is_empty()
		count += 1
	# A loop over an empty directory validates nothing and reports success.
	assert_int(count).is_greater(0)


func test_a_bar_that_does_not_add_up_is_refused() -> void:
	# A short bar renders short and every bar after it walks off the beat, which sounds like a
	# broken synthesiser rather than a typo in a string.
	assert_array(_track(["A4:4 C5:4 E5:4"]).problems()).override_failure_message(
		"a bar of twelve steps in a sixteen-step tune passed").is_not_empty()
	assert_array(_track(["A4:4 C5:4 E5:8"]).problems()).is_empty()


func test_two_bars_that_cancel_each_other_out_are_still_refused() -> void:
	# One short, one long, summing correctly over the tune - and everything between them is off
	# the beat. Checked per bar for exactly this.
	assert_array(_track(["A4:4 C5:4 E5:4", "A4:4 C5:4 E5:4 D5:4 C5:4"]).problems()).is_not_empty()


func test_voices_of_different_lengths_are_refused() -> void:
	var track := MusicTrack.new()
	track.id = &"probe"
	track.instruments = {&"lead": {"wave": "tone"}, &"bass": {"wave": "tone"}}
	track._read_voices([
		{"instrument": "lead", "bars": ["A4:16", "C5:16"]},
		{"instrument": "bass", "bars": ["A2:16"]},
	])
	assert_array(track.problems()).override_failure_message(
		"one voice stops halfway and the tune was accepted").is_not_empty()


func test_a_hit_on_a_pitched_instrument_is_refused() -> void:
	assert_array(_track(["x:16"]).problems()).is_not_empty()


func test_a_note_on_an_instrument_with_no_pitch_is_refused() -> void:
	assert_array(_track(["A4:16"], {"wave": "noise"}).problems()).is_not_empty()


func test_a_token_the_reader_does_not_understand_is_refused() -> void:
	# Rather than rendered as silence: a mistyped note that plays nothing still sums correctly,
	# so the bar check cannot see it.
	assert_array(_track(["H4:16"]).problems()).is_not_empty()
	assert_array(_track(["A#4:16"]).problems()).is_empty()


func test_a_track_named_after_a_cue_is_refused() -> void:
	# One table holds both in AudioBus, which is what lets a game override either by dropping a
	# file in. A track called 'victory' would shadow the fanfare.
	var track := _track(["A4:16"])
	track.id = &"victory"
	assert_array(track.problems()).override_failure_message(
		"a track named after a cue was accepted and would shadow it").is_not_empty()


func test_a_track_past_the_length_cap_is_refused() -> void:
	# The cost of music here is bytes, three voices at a time, and every addition is
	# individually reasonable.
	var bars: Array = []
	for i in 40:
		bars.append("A4:16")
	assert_float(_track(bars).seconds()).is_greater(MusicTrack.MAX_SECONDS)
	assert_array(_track(bars).problems()).is_not_empty()


func test_a_notes_start_comes_from_its_absolute_step() -> void:
	# A sixteenth at 22050 and 120bpm is 2756.25 samples. Rounding per step and adding walks the
	# last bar off the beat by however much the error accumulated; rounding once from the
	# absolute step never does.
	var track := _track(["A4:16", "A4:16", "A4:16", "A4:16"])
	assert_int(track.sample_at(64, 22050)).is_equal(176400)
	assert_int(track.total_samples(22050)).is_equal(176400)
	for step in 64:
		var exact := float(step) * 22050.0 * 60.0 / (120.0 * 4.0)
		assert_float(absf(float(track.sample_at(step, 22050)) - exact)).override_failure_message(
			"step %d lands more than a sample from the beat" % step).is_less(1.0)


func test_a_rest_is_a_length_rather_than_an_absence() -> void:
	var track := _track(["A4:8 -:8"])
	assert_array(track.problems()).is_empty()
	var notes: Array[MusicTrack.Note] = track.voices[0]["notes"]
	assert_int(notes.size()).is_equal(2)
	assert_int(notes[1].semitone).is_equal(MusicTrack.REST)
	assert_int(notes[1].step).is_equal(8)

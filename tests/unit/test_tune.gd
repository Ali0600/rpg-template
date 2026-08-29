extends GdUnitTestSuite
## Notes turned into samples. The music half of test_synth.gd, and it asks the same questions:
## is it deterministic, does a voice change it, and does it end where a loop can use it.

func _style(id: StringName, tone: StringName, quantise := 0) -> SoundStyle:
	var style := SoundStyle.new()
	style.id = id
	style.bank_id = &"gb16"
	style.mix_rate = 22050
	style.gain = 0.8
	style.pitch_scale = 1.0
	style.tone = tone
	style.quantise_steps = quantise
	return style


func _rng() -> SeededRng:
	return SeededRng.new(SeededRng.hash_seed(0, "probe"))


func _track(bars: Array, instrument := {"wave": "tone", "gain": 0.5}) -> MusicTrack:
	var track := MusicTrack.new()
	track.id = &"probe"
	track.instruments = {&"lead": instrument}
	track._read_voices([{"instrument": "lead", "bars": bars}])
	return track


func test_a_is_four_hundred_and_forty() -> void:
	# The whole point of the integer table: concert pitch, without ever calling pow.
	assert_float(Tune.hz_of(57)).is_equal_approx(440.0, 0.001)
	assert_float(Tune.hz_of(48)).is_equal_approx(261.626, 0.001)


func test_an_octave_is_exactly_a_doubling() -> void:
	# EXACT equality, not approximate, and that is the claim: octaves are applied by doubling,
	# which is exact in binary, so the same note an octave apart cannot drift between machines.
	for semitone in 60:
		assert_float(Tune.hz_of(semitone + 12)).override_failure_message(
			"an octave above semitone %d is not exactly twice it" % semitone).is_equal(
			Tune.hz_of(semitone) * 2.0)


func test_rendering_the_same_tune_twice_gives_the_same_bytes() -> void:
	var track := MusicTrack.load_from(MusicTrack.ids()[0])
	var style := _style(&"probe", &"square")
	var first := Synth.to_pcm16(Tune.render(track, style, _rng()))
	var second := Synth.to_pcm16(Tune.render(track, style, _rng()))
	assert_str(Hashing.sha256_bytes(first)).override_failure_message(
		"the tune rendered differently the second time").is_equal(Hashing.sha256_bytes(second))


func test_two_voices_over_one_tune_do_not_sound_the_same() -> void:
	# The claim the whole style split exists to make, for music: if a voice changed nothing,
	# rendering per style would be three copies of one file.
	var track := MusicTrack.load_from(MusicTrack.ids()[0])
	var square := Synth.to_pcm16(Tune.render(track, _style(&"a", &"square"), _rng()))
	var triangle := Synth.to_pcm16(Tune.render(track, _style(&"b", &"triangle"), _rng()))
	assert_str(Hashing.sha256_bytes(square)).override_failure_message(
		"a square voice and a triangle one played the tune identically").is_not_equal(
		Hashing.sha256_bytes(triangle))


func test_a_tune_ends_on_silence_so_the_loop_seam_is_flat() -> void:
	# Not by a fade - a track loops, and a ramp to zero at the end is a dip on every pass. The
	# note release lands the last note on zero instead.
	var samples := Tune.render(_track(["A4:16"]), _style(&"probe", &"square"), _rng())
	assert_int(samples.size()).is_greater(0)
	assert_float(samples[samples.size() - 1]).is_equal_approx(0.0, 0.001)
	assert_float(samples[0]).is_equal_approx(0.0, 0.05)


func test_a_held_note_does_not_decay() -> void:
	# The cue envelope decays across the whole cue, which is right for a blip and would turn
	# every half note into a pluck. Sampled a quarter and half way through one long note.
	var samples := Tune.render(_track(["A4:16"]), _style(&"probe", &"saw"), _rng())
	var quarter := 0.0
	var half := 0.0
	for i in range(int(samples.size() * 0.2), int(samples.size() * 0.3)):
		quarter = maxf(quarter, absf(samples[i]))
	for i in range(int(samples.size() * 0.45), int(samples.size() * 0.55)):
		half = maxf(half, absf(samples[i]))
	assert_float(half).override_failure_message(
		"the note faded from %f to %f across its own length" % [quarter, half]).is_greater(
		quarter * 0.9)


func test_no_sample_can_leave_the_representable_range() -> void:
	# Three voices summing is the whole reason this needs saying: a mix past full scale must
	# clamp, because to_pcm16 would otherwise wrap it to the opposite sign - a loud chord
	# turning into a crack.
	var track := MusicTrack.new()
	track.id = &"loud"
	track.instruments = {&"lead": {"wave": "tone", "gain": 1.0}}
	track._read_voices([
		{"instrument": "lead", "bars": ["A4:16"]},
		{"instrument": "lead", "bars": ["C5:16"]},
		{"instrument": "lead", "bars": ["E5:16"]},
	])
	for v in Tune.render(track, _style(&"probe", &"square"), _rng()):
		assert_float(absf(v)).is_less_equal(1.0)


func test_the_bit_crush_is_applied_to_the_mix_rather_than_to_each_voice() -> void:
	# Crushing per voice and then summing gives strictly more distinct levels than the style
	# asked for, which defeats the setting silently rather than loudly.
	var track := MusicTrack.new()
	track.id = &"crushed"
	track.instruments = {&"lead": {"wave": "tone", "gain": 0.4}}
	track._read_voices([
		{"instrument": "lead", "bars": ["A4:16"]},
		{"instrument": "lead", "bars": ["E5:16"]},
	])
	var levels := {}
	for v in Tune.render(track, _style(&"probe", &"square", 4), _rng()):
		levels[snappedf(v, 0.0001)] = true
	assert_int(levels.size()).override_failure_message(
		"a four-step crush produced %d distinct levels" % levels.size()).is_less_equal(9)


func test_a_note_too_high_for_the_voice_is_reported_rather_than_rendered() -> void:
	# The pair check, the way TileGen.problems(bank, style) is: a style's pitch_scale moves
	# every note, so whether a tune fits is a question neither file answers alone.
	var style := _style(&"fast", &"square")
	style.pitch_scale = 40.0
	assert_array(Tune.problems(_track(["A6:16"]), style)).is_not_empty()
	assert_array(Tune.problems(_track(["A4:16"]), _style(&"probe", &"square"))).is_empty()

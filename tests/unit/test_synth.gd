extends GdUnitTestSuite
## The sample maths. Pure, so it is tested with no tree, no files and no engine audio at all.
##
## The assertions that matter here are not "does it sound right" - nothing headless can answer
## that - but the ones that make the drift gate trustworthy: a fixed length for a fixed
## duration, a value that cannot escape [-1, 1], and a quantisation that happens exactly once.


func _style(tone: StringName = &"square", quantise: int = 0) -> SoundStyle:
	var style := SoundStyle.new()
	style.id = &"probe"
	style.bank_id = &"gb16"
	style.mix_rate = 22050
	style.gain = 1.0
	style.pitch_scale = 1.0
	style.tone = tone
	style.quantise_steps = quantise
	return style


func _rng() -> SeededRng:
	return SeededRng.new(1234)


func test_a_cue_is_as_many_samples_as_its_duration_asks_for() -> void:
	var style := _style()
	var samples := Synth.render({"ms": 100.0, "hz": 440.0}, style, _rng())
	# 100ms at 22050Hz is 2205 samples. Stated as the arithmetic rather than as 2205 so the
	# assertion still says something if the rate ever moves.
	assert_int(samples.size()).is_equal(int(100.0 * 22050.0 / 1000.0))


func test_the_rate_the_style_asks_for_is_the_rate_used() -> void:
	var style := _style()
	style.mix_rate = 8000
	var samples := Synth.render({"ms": 100.0}, style, _rng())
	assert_int(samples.size()).is_equal(800)


func test_no_sample_can_leave_the_representable_range() -> void:
	# A shape asking for everything at once. If a partial or a gain could push past 1.0 the
	# 16-bit conversion would WRAP, and a wrap is a loud click with the opposite sign - the
	# kind of defect no spectrum-blind assertion would ever see.
	var style := _style()
	style.gain = 1.0
	var samples := Synth.render(
		{"ms": 60.0, "hz": 400.0, "hz_end": 200.0, "wave": &"both", "gain": 1.0},
		style, _rng())
	for i in samples.size():
		assert_float(samples[i]).override_failure_message(
			"sample %d is %f, outside [-1, 1]" % [i, samples[i]]).is_between(-1.0, 1.0)


func test_the_conversion_to_pcm_clamps_instead_of_wrapping() -> void:
	# Handed values that should be impossible, because the guard is what makes them impossible.
	# Without it, int16 WRAPS: 1.2 scaled and stored comes back as a large NEGATIVE number, so
	# the loudest moment of a cue becomes a click with the opposite sign.
	#
	# The two negative cases differ on purpose and the difference is the point. Full scale is
	# 32767, so -1.0 lands on -32767; the clamp's floor is -32768 because that value IS
	# representable and refusing it would be inventing a limit the format does not have.
	var wild := PackedFloat32Array([2.0, -2.0, 1.0, -1.0, 0.0])
	var bytes := Synth.to_pcm16(wild)
	assert_int(bytes.decode_s16(0)).is_equal(32767)
	assert_int(bytes.decode_s16(2)).is_equal(-32768)
	assert_int(bytes.decode_s16(4)).is_equal(32767)
	assert_int(bytes.decode_s16(6)).is_equal(-32767)
	assert_int(bytes.decode_s16(8)).is_equal(0)


func test_a_cue_ends_on_silence() -> void:
	# A waveform cut off mid-cycle steps to zero, and a step is a click the player hears on
	# every single play - far more audible than the cue itself.
	# EXACTLY zero, not approximately. The envelope alone already ends near zero - one part in
	# a few thousand - so an approximate assertion passes whether the fade is there or not, and
	# would be decoration. Only the fade makes the last sample land on zero itself.
	var samples := Synth.render({"ms": 80.0, "hz": 440.0}, _style(), _rng())
	assert_float(samples[samples.size() - 1]).is_equal(0.0)


func test_a_cue_decays_rather_than_holding() -> void:
	var samples := Synth.render({"ms": 200.0, "hz": 440.0}, _style(), _rng())
	var early := 0.0
	var late := 0.0
	for i in samples.size():
		var loudness := absf(samples[i])
		if i < samples.size() / 4:
			early = maxf(early, loudness)
		elif i > samples.size() * 3 / 4:
			late = maxf(late, loudness)
	assert_float(late).override_failure_message(
		"the tail (%f) is not quieter than the head (%f)" % [late, early]).is_less(early)


func test_quantising_limits_how_many_distinct_levels_come_out() -> void:
	# The bit-crush is a palette for sound, and a palette that does not reduce the set is not
	# one. Counted rather than eyeballed, the way the art gate counts colours.
	var loud := _style(&"triangle", 0)
	var crushed := _style(&"triangle", 4)
	var shape := {"ms": 120.0, "hz": 300.0, "gain": 1.0}
	assert_int(_levels(Synth.render(shape, crushed, _rng()))).is_less(
		_levels(Synth.render(shape, loud, _rng())))


func test_a_stream_is_mono_sixteen_bit_at_the_styles_rate() -> void:
	# What the importer and AudioStreamWAV.save_to_wav are handed. A stereo or 8-bit cue would
	# still play, which is exactly why it needs asserting rather than noticing.
	var style := _style()
	var wav := Synth.stream(Synth.render({"ms": 50.0}, style, _rng()), style.mix_rate)
	assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_bool(wav.stereo).is_false()
	assert_int(wav.mix_rate).is_equal(22050)
	assert_int(wav.data.size()).is_equal(int(50.0 * 22050.0 / 1000.0) * 2)


func test_a_bad_shape_is_reported_rather_than_rendered() -> void:
	assert_array(Synth.problems(&"x", {"wave": &"kazoo"})).is_not_empty()
	assert_array(Synth.problems(&"x", {"ms": 0.0})).is_not_empty()
	assert_array(Synth.problems(&"x", {"hz": 0.0})).is_not_empty()
	assert_array(Synth.problems(&"x", {"hz_end": 999999.0})).is_not_empty()
	assert_array(Synth.problems(&"x", {"gain": 3.0})).is_not_empty()
	assert_array(Synth.problems(&"x", {"ms": 50.0, "hz": 440.0, "gain": 0.5})).is_empty()


## How many distinct sample values a rendering produced.
func _levels(samples: PackedFloat32Array) -> int:
	var seen: Dictionary = {}
	for i in samples.size():
		seen[roundi(samples[i] * 10000.0)] = true
	return seen.size()

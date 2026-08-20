extends GdUnitTestSuite
## Same style, same cue, same bytes - on every machine, forever.
##
## This is what the drift gate rests on. The gate runs on macOS here and on Ubuntu in CI, so a
## generator that is merely deterministic PER MACHINE would turn every merge red for a reason
## nobody could reproduce locally, and a gate that flaps is a gate that gets switched off.
##
## The reason it holds is a constraint stated in synth.gd: no transcendental function is called
## anywhere in the render path. IEEE-754 pins + - * / to identical results everywhere; libm's
## sin and pow are pinned by nothing.


func _source(style_id: StringName, tone: StringName) -> ProceduralSoundSource:
	return ProceduralSoundSource.new(_voice(style_id, tone), SoundBank.load_from(&"gb16"))


func test_rendering_the_same_cue_twice_gives_the_same_bytes() -> void:
	var source := _source(&"probe", &"square")
	for cue in Sfx.ids():
		var first := Synth.to_pcm16(source.samples(cue))
		var second := Synth.to_pcm16(source.samples(cue))
		assert_str(Hashing.sha256_bytes(first)).override_failure_message(
			"'%s' rendered differently the second time" % cue).is_equal(
			Hashing.sha256_bytes(second))


func test_two_voices_over_one_bank_do_not_sound_the_same() -> void:
	# The claim the whole two-file split exists to make. If a voice changed nothing, the bank
	# would be the only real file and one of them should be deleted.
	var square := _source(&"a", &"square")
	var triangle := _source(&"b", &"triangle")
	var differed := 0
	for cue in Sfx.ids():
		if Hashing.sha256_bytes(Synth.to_pcm16(square.samples(cue))) \
				!= Hashing.sha256_bytes(Synth.to_pcm16(triangle.samples(cue))):
			differed += 1
	assert_int(differed).override_failure_message(
		"no cue differed between a square voice and a triangle one").is_greater(0)


func test_a_cues_noise_does_not_depend_on_what_was_rendered_before_it() -> void:
	# Streams are derived from the cue NAME, not drawn from one running generator. Otherwise
	# adding a seventeenth cue would re-roll the noise in all sixteen already committed, and
	# every future cue would rewrite the whole bank on the drift gate.
	var source := _source(&"probe", &"square")
	var alone := Hashing.sha256_bytes(Synth.to_pcm16(source.samples(Sfx.id_of(Sfx.Cue.DEFEAT))))
	var fresh := _source(&"probe", &"square")
	for cue in Sfx.ids():
		fresh.samples(cue)
	var after := Hashing.sha256_bytes(Synth.to_pcm16(fresh.samples(Sfx.id_of(Sfx.Cue.DEFEAT))))
	assert_str(after).is_equal(alone)


func test_a_cue_the_bank_does_not_have_renders_nothing() -> void:
	# Nothing, rather than a plausible blip: a stand-in noise for a missing cue is exactly the
	# failure the completeness gate exists to make impossible, and it must not be papered over
	# one layer down.
	assert_array(_source(&"probe", &"square").samples(&"kazoo")).is_empty()
	assert_object(_source(&"probe", &"square").cue(&"kazoo")).is_null()


func test_two_cues_with_the_same_shape_still_get_their_own_noise() -> void:
	# Rendered from an IDENTICAL shape under two names, so the ONLY thing that can make the
	# output differ is the stream being derived from the cue name. Comparing two real cues
	# would prove nothing - they already differ in length and gain.
	var bank := SoundBank.load_from(&"gb16")
	var shape := {"wave": &"noise", "ms": 60.0, "gain": 0.5}
	bank.cues[&"twin_a"] = shape
	bank.cues[&"twin_b"] = shape
	var source := ProceduralSoundSource.new(_voice(&"probe", &"square"), bank)
	assert_str(_digest(source, &"twin_a")).override_failure_message(
		"two differently-named cues drew the same noise").is_not_equal(
		_digest(source, &"twin_b"))


func test_one_cue_sounds_different_in_two_voices_even_when_it_is_pure_noise() -> void:
	# A noise cue has no waveform to tell voices apart, so this is the assertion that pins the
	# per-STYLE half of the seed. Without it every voice would share one noise bed.
	var bank := SoundBank.load_from(&"gb16")
	var shape := {"wave": &"noise", "ms": 60.0, "gain": 0.5}
	bank.cues[&"twin_a"] = shape
	var first := ProceduralSoundSource.new(_voice(&"one", &"square"), bank)
	var second := ProceduralSoundSource.new(_voice(&"two", &"square"), bank)
	assert_str(_digest(first, &"twin_a")).override_failure_message(
		"two voices drew identical noise").is_not_equal(_digest(second, &"twin_a"))


## The voice half of _source, for tests that need to build their own bank.
func _voice(style_id: StringName, tone: StringName) -> SoundStyle:
	var style := SoundStyle.new()
	style.id = style_id
	style.bank_id = &"gb16"
	style.mix_rate = 22050
	style.gain = 0.7
	style.pitch_scale = 1.0
	style.tone = tone
	return style


func _digest(source: ProceduralSoundSource, cue: StringName) -> String:
	return Hashing.sha256_bytes(Synth.to_pcm16(source.samples(cue)))

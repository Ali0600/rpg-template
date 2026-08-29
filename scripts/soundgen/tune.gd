class_name Tune
extends RefCounted
## Turns a track into samples. The Synth of music: pure maths, no nodes, no files, no clock.
##
## ## Why the pitch table is integers
##
## Everything synth.gd says about sin, pow and exp applies here and one step harder, because
## pitch is exactly where a naive implementation reaches for pow(2, n/12). libm is pinned by
## nothing between this Mac and the Ubuntu runner that gates every merge, and one bit moves a
## sample, which moves the file, which fails the drift gate for a reason nobody can reproduce.
##
## So the twelve ratios below are INTEGERS. Not decimal float literals either: a decimal literal
## leans on strtod being correctly rounded on both platforms, which is the same class of
## assumption this pipeline refuses to make about libm, one layer down. An integer literal is
## parsed exactly by any parser there has ever been.

## round(2^(n/12) * 2^20), one octave of ratios. Accurate to about 0.0007 of a cent, which is
## four orders of magnitude below anything a person or a spectrogram can tell apart.
const SEMITONE_Q20: Array[int] = [
	1048576,  # C
	1110928,  # C#
	1176987,  # D
	1246974,  # D#
	1321123,  # E
	1399681,  # F
	1482910,  # F#
	1571089,  # G
	1664511,  # G#
	1763488,  # A
	1868350,  # A#
	1979448,  # B
]

## C0 in the same fixed point, which puts A4 at 440.0001 Hz. There is no tuning field and that
## is the point: a tuning knob is a thing no chiptune needs, and it would cost the exactness
## below for a setting nobody would turn.
const C0_Q20 := 17145893

## 2^40, as a float. The product above reaches 3.4e13 at most - well inside a double's 53 exact
## bits - and dividing by a power of two is exact, so hz_of is bit-identical on every machine.
const Q40 := 1099511627776.0


## The frequency of a semitone above C0. The octave is applied by DOUBLING rather than by a
## bigger table, because doubling is exact in binary - which is also why the table only needs
## twelve entries to cover every octave a game could ask for.
static func hz_of(semitone: int) -> float:
	var rem := posmod(semitone, 12)
	var octave := (semitone - rem) / 12
	var hz := float(C0_Q20 * SEMITONE_Q20[rem]) / Q40
	for i in octave:
		hz *= 2.0
	return hz


## The whole track, mixed, in [-1, 1].
static func render(track: MusicTrack, style: SoundStyle, rng: SeededRng) -> PackedFloat32Array:
	var rate := maxi(style.mix_rate, 1)
	var mix := PackedFloat32Array()
	# Zeroed, so anything past the last note is silence rather than whatever was there - which
	# is half of what makes the loop seam land on zero.
	mix.resize(maxi(track.total_samples(rate), 1))
	for voice: Dictionary in track.voices:
		_voice_into(mix, track, voice, style, rng)
	var level := clampf(style.gain, 0.0, 1.0)
	for i in mix.size():
		var v := mix[i] * level
		# Quantised over the MIX and not per voice, deliberately: crushing each voice and then
		# summing them gives strictly more distinct levels than the style asked for, which
		# defeats the bit-crush silently rather than loudly.
		if style.quantise_steps > 0:
			v = Synth.quantise(v, style.quantise_steps)
		mix[i] = clampf(v, -1.0, 1.0)
	# No fade tail, unlike a cue. A track LOOPS, and a ramp to zero at the end is a dip every
	# pass - audible as a pulse once it has gone round twice. The note release already lands the
	# last note on zero.
	return mix


static func _voice_into(mix: PackedFloat32Array, track: MusicTrack, voice: Dictionary,
		style: SoundStyle, rng: SeededRng) -> void:
	var rate := maxi(style.mix_rate, 1)
	var shape: Dictionary = track.instruments.get(StringName(str(voice.get("instrument", ""))), {})
	var wave := StringName(str(shape.get("wave", &"tone")))
	var gain := clampf(float(shape.get("gain", 0.3)), 0.0, 1.0)
	var attack := maxi(int(float(shape.get("attack_ms", 4.0)) * float(rate) / 1000.0), 1)
	var release := maxi(int(float(shape.get("release_ms", 40.0)) * float(rate) / 1000.0), 1)
	var phase := 0.0
	for note: MusicTrack.Note in voice.get("notes", []) as Array[MusicTrack.Note]:
		if note.semitone == MusicTrack.REST:
			continue
		var from := track.sample_at(note.step, rate)
		var to := mini(track.sample_at(note.step + note.steps, rate), mix.size())
		var count := to - from
		if count < 1:
			continue
		var hz := 0.0
		if note.semitone >= 0:
			hz = maxf(hz_of(note.semitone) * style.pitch_scale, 1.0)
		# The phase is reset per note rather than carried: a note is a new sound, and carrying
		# the angle across a pitch change is the buzz synth.gd's own comment warns about.
		phase = 0.0
		for i in count:
			phase += hz / float(rate)
			phase -= floorf(phase)
			var v := Synth.wave_at(wave, style.tone, phase, rng)
			v *= Synth.note_envelope(i, count, attack, release)
			mix[from + i] += v * gain


## Everything wrong with playing THIS track in THIS voice - the pair, the way
## TileGen.problems(bank, style) and CharacterSpec.problems(rig, style) take theirs. A style's
## pitch_scale moves every note, so whether a tune fits inside what can be reproduced is a
## question neither file can answer alone.
static func problems(track: MusicTrack, style: SoundStyle) -> Array[String]:
	var out: Array[String] = []
	var ceiling := float(maxi(style.mix_rate, 1)) * 0.5
	for voice: Dictionary in track.voices:
		for note: MusicTrack.Note in voice.get("notes", []) as Array[MusicTrack.Note]:
			if note.semitone < 0:
				continue
			var hz := hz_of(note.semitone) * style.pitch_scale
			if hz <= 0.0 or hz >= ceiling:
				out.append("track '%s' in voice '%s' asks for %.1f Hz, which %s cannot sound"
					% [track.id, style.id, hz, style.id])
				return out
	return out

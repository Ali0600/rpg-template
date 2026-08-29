class_name Synth
extends RefCounted
## Turns a cue's shape into samples. Pure maths, no nodes, no files, no clock.
##
## ## Why there is no sine wave here
##
## Everything below is built from +, -, *, / and comparisons, and deliberately calls NO
## transcendental function - no sin, no pow, no exp. IEEE-754 pins those four operations to
## the same rounded result on every machine; the libm functions are pinned by nothing, and can
## differ in the last bit between macOS on arm64 and the Ubuntu x86_64 runner that gates every
## merge. One bit is enough to move a sample, which moves the file, which fails the drift gate
## on a machine nobody can reproduce.
##
## So the drift gate is deterministic BY CONSTRUCTION rather than by luck. It costs nothing:
## square, triangle and saw are what a chiptune voice is made of anyway, and a Game Boy never
## had a sine either.
##
## Noise comes from SeededRng as INTEGERS scaled to a float, for the same reason - integer
## arithmetic cannot disagree across platforms, and the alternative is a global generator this
## project bans outright.

## Waveforms a bank may ask for. `tone` means "whatever this style's voice is", which is what
## lets one bank sound like three different machines.
const WAVES: Array[StringName] = [&"tone", &"noise", &"both"]

## The voices a style may choose between.
const TONES: Array[StringName] = [&"square", &"triangle", &"saw"]

## Full scale for signed 16-bit PCM. 32767 rather than 32768 so a sample at +1.0 and one at
## -1.0 are both representable after rounding.
const PEAK := 32767.0

## Every cue is faded out over its last few samples. A waveform cut off mid-cycle steps
## straight to zero, and a step is a click - which is audible on every single play, unlike the
## cue itself.
const TAIL_SAMPLES := 24


## The samples for one cue, in [-1, 1]. `shape` is a bank entry; `style` is the voice.
##
## Both are needed to answer even the first sample, which is why this takes the pair rather
## than a merged "cue" object: the bank is shared between styles and must stay unaware of them.
static func render(shape: Dictionary, style: SoundStyle, rng: SeededRng) -> PackedFloat32Array:
	var rate := maxi(style.mix_rate, 1)
	var ms := maxf(_num(shape, "ms", 100.0), 1.0)
	var count := maxi(int(ms * float(rate) / 1000.0), 1)

	var wave := StringName(str(shape.get("wave", &"tone")))
	var hz_from := maxf(_num(shape, "hz", 440.0) * style.pitch_scale, 1.0)
	var hz_to := maxf(_num(shape, "hz_end", _num(shape, "hz", 440.0)) * style.pitch_scale, 1.0)
	var steps := int(_num(shape, "steps", 0.0))
	var attack := maxi(int(_num(shape, "attack_ms", 2.0) * float(rate) / 1000.0), 1)
	var cue_gain := clampf(_num(shape, "gain", 0.6), 0.0, 1.0)
	var level := cue_gain * clampf(style.gain, 0.0, 1.0)

	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var u := float(i) / float(count)
		var hz := _sweep(hz_from, hz_to, u, steps)
		# Phase carries the sweep with it. Recomputing the angle from the current frequency
		# each sample would jump the waveform every time the pitch moved, which is a buzz
		# rather than a slide.
		phase += hz / float(rate)
		phase -= floorf(phase)
		var v := wave_at(wave, style.tone, phase, rng)
		v *= _envelope(i, count, attack)
		v *= level
		if style.quantise_steps > 0:
			v = quantise(v, style.quantise_steps)
		out[i] = clampf(v, -1.0, 1.0)
	_fade_tail(out)
	return out


## Signed 16-bit little-endian PCM, which is what AudioStreamWAV.FORMAT_16_BITS expects.
##
## The rounding is done ONCE, here, and never anywhere else: a value computed in floats does
## not survive a narrower store unchanged, and two places rounding "the same" number their own
## way is how a generated artifact stops matching the gate that checks it.
static func to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var q := clampi(roundi(samples[i] * PEAK), -32768, 32767)
		bytes.encode_s16(i * 2, q)
	return bytes


## A ready-to-save stream. Mono on purpose: every cue here is a UI or world blip with no
## position, and a stereo file would be twice the bytes saying the same thing twice.
static func stream(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = maxi(rate, 1)
	wav.stereo = false
	wav.data = to_pcm16(samples)
	return wav


## Everything wrong with one bank entry, named by its cue. All of them, not the first.
static func problems(cue: StringName, shape: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var wave := StringName(str(shape.get("wave", &"tone")))
	if not WAVES.has(wave):
		out.append("cue '%s' asks for wave '%s', which is not one of %s" % [cue, wave, WAVES])
	if _num(shape, "ms", 100.0) <= 0.0:
		out.append("cue '%s' is %f ms long" % [cue, _num(shape, "ms", 100.0)])
	# 20000 Hz is past hearing, and anything above half the mix rate aliases into a different
	# pitch than the one written down - a cue that sounds wrong for a reason invisible in data.
	for key in ["hz", "hz_end"]:
		var hz := _num(shape, key, 440.0)
		if hz <= 0.0 or hz > 20000.0:
			out.append("cue '%s' has %s of %f" % [cue, key, hz])
	var gain := _num(shape, "gain", 0.6)
	if gain <= 0.0 or gain > 1.0:
		out.append("cue '%s' has a gain of %f" % [cue, gain])
	if _num(shape, "steps", 0.0) < 0.0:
		out.append("cue '%s' has a negative step count" % cue)
	return out


## The pitch at a point through the cue. `steps` above zero holds it on discrete rungs instead
## of gliding, which is the difference between a siren and an arpeggio.
static func _sweep(from_hz: float, to_hz: float, u: float, steps: int) -> float:
	var t := u
	if steps > 0:
		t = floorf(u * float(steps)) / float(steps)
	return from_hz + (to_hz - from_hz) * t


static func wave_at(wave: StringName, tone: StringName, phase: float, rng: SeededRng) -> float:
	match wave:
		&"noise":
			return noise(rng)
		&"both":
			# Half and half: the tone carries the pitch, the noise gives it an edge. A hit
			# that is pure tone reads as a menu blip, and one that is pure noise has no pitch
			# to tell a big hit from a small one.
			return _tone_at(tone, phase) * 0.5 + noise(rng) * 0.5
		_:
			return _tone_at(tone, phase)


static func _tone_at(tone: StringName, phase: float) -> float:
	match tone:
		&"triangle":
			return 4.0 * absf(phase - 0.5) - 1.0
		&"saw":
			return 2.0 * phase - 1.0
		_:
			return 1.0 if phase < 0.5 else -1.0


## Integer noise scaled to a float, never a float drawn directly: the integer stream is
## identical on every platform, and the division by a power of two is exact.
static func noise(rng: SeededRng) -> float:
	return float(rng.next_int(-32768, 32767)) / 32768.0


## Linear attack, linear decay. Linear rather than exponential because exp is exactly the kind
## of function this file refuses to call, and over 60 milliseconds nobody can hear the curve.
static func _envelope(i: int, count: int, attack: int) -> float:
	if i < attack:
		return float(i + 1) / float(attack + 1)
	var left := count - i
	var span := maxi(count - attack, 1)
	return float(left) / float(span)


## A NOTE's envelope: attack in, flat through the body, release out.
##
## Deliberately not the cue envelope above, which decays across the WHOLE cue - right for a blip
## and wrong for a held note, where it would turn every half note into a pluck and make a run of
## eighths saw. Linear for the same reason the cue's is: exp is a function this file does not
## call.
##
## The release is what makes a loop safe. The last note lands on zero and the samples past it
## are silence, so the seam is 0 to 0 by construction rather than by a fade nobody hears the
## first time and everybody hears the tenth.
static func note_envelope(i: int, count: int, attack: int, release: int) -> float:
	if i < attack:
		return float(i + 1) / float(attack + 1)
	var fall := count - i
	if fall <= release:
		return float(fall) / float(maxi(release, 1))
	return 1.0


## Rounds a sample onto `steps` rungs between -1 and 1.
##
## Public, with wave_at and noise, so a tune is built from the SAME waveforms a cue is. A second
## copy of a square wave in another file would be a second thing to keep in step with a style's
## `tone`, and the first divergence would be a game whose music and menus disagree about what
## the machine sounds like.
static func quantise(v: float, steps: int) -> float:
	var half := float(steps) * 0.5
	return clampf(roundf(v * half) / half, -1.0, 1.0)


## Ramps the last few samples to silence so the file ends ON zero.
static func _fade_tail(samples: PackedFloat32Array) -> void:
	var n := mini(TAIL_SAMPLES, samples.size())
	var first := samples.size() - n
	for i in n:
		samples[first + i] *= float(n - i - 1) / float(n)


## A number out of a JSON dictionary. JSON has no integers and a missing key is not an error
## here - a bank entry states what it cares about and inherits the rest.
static func _num(shape: Dictionary, key: String, fallback: float) -> float:
	if not shape.has(key):
		return fallback
	return float(shape[key])

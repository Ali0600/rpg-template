class_name ProceduralSoundSource
extends SoundSource
## Renders cues from a bank and a style, in memory, deterministically.
##
## The same seed always produces the same bytes: the noise stream is derived per cue from the
## style and cue names, so adding a cue cannot shift the samples of one that already exists -
## the identical rule the sprite generator follows for its per-slot streams.

var _style: SoundStyle
var _bank: SoundBank


func _init(style: SoundStyle, bank: SoundBank) -> void:
	_style = style
	_bank = bank


func cue(cue_id: StringName) -> AudioStreamWAV:
	var samples := samples(cue_id)
	if samples.is_empty():
		return null
	return Synth.stream(samples, _style.mix_rate)


## The raw samples, which is what the determinism suite and the drift gate compare.
func samples(cue_id: StringName) -> PackedFloat32Array:
	if _style == null or _bank == null or not _bank.has_cue(cue_id):
		return PackedFloat32Array()
	return Synth.render(_bank.shape(cue_id), _style, _rng_for(cue_id))


## A stream of its own per cue, per style. Derived from the NAMES rather than from a counter,
## so the numbers a cue draws do not depend on how many cues were rendered before it.
func _rng_for(cue_id: StringName) -> SeededRng:
	var base := SeededRng.hash_seed(0, String(_style.id))
	return SeededRng.new(base).derive(String(cue_id))

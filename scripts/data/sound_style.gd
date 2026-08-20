class_name SoundStyle
extends Resource
## How a game SOUNDS - the audio half of SpriteStyle, and the same idea.
##
## SpriteStyle holds a palette and points at a rig; this holds a voice and points at a bank.
## The bank (data/banks/<bank_id>.json) says what a cue is SHAPED like - how long a footstep
## is, which way its pitch moves. This says what it is PLAYED on. Three styles over one bank is
## the same arrangement the art side already ships: dusk16, gb16 and nes16 all draw the one
## gb16 rig and look nothing alike.
##
## A game names one of these on its manifest, and a manifest with no sound style is a SILENT
## game - the same legal shape as a manifest with no CombatDef being a game that cannot fight.

## Used by Registry as this resource's key, and as the directory generated cues are written to.
@export var id: StringName = &""

## Which bank of cue shapes to render. `data/banks/<bank_id>.json`.
@export var bank_id: StringName = &""

## Samples per second. 22050 is the chiptune range and half the file size of 44100; every cue
## here is a short blip where the difference is inaudible.
@export var mix_rate: int = 22050

## Master level for every cue in this style, before the player's own volume setting.
@export var gain: float = 0.7

## Multiplies every pitch in the bank. The cheapest way to make one voice read as bigger or
## smaller than another without re-authoring a single cue.
@export var pitch_scale: float = 1.0

## The waveform a cue is played on where the bank asks for a tone. See Synth.TONES.
@export var tone: StringName = &"square"

## Bit-crush: rounds each sample to this many levels, 0 for off. A real Game Boy had four bits
## of amplitude, and quantising is what gives that crunch - it is a palette for sound.
@export var quantise_steps: int = 0


## Everything wrong with this style. All of them, not the first.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("sound style has no id")
	if String(bank_id).is_empty():
		out.append("sound style '%s' names no bank" % id)
	# 8000 is the floor where a bright cue starts aliasing audibly; 48000 is past what any of
	# this needs. Both ends are stated so a typo in a .tres reads as an error rather than as a
	# file that takes a minute to render or comes out as a click.
	if mix_rate < 8000 or mix_rate > 48000:
		out.append("sound style '%s' has a mix_rate of %d" % [id, mix_rate])
	if gain <= 0.0 or gain > 1.0:
		out.append("sound style '%s' has a gain of %f" % [id, gain])
	if pitch_scale <= 0.0:
		out.append("sound style '%s' has a pitch_scale of %f" % [id, pitch_scale])
	if not Synth.TONES.has(tone):
		out.append("sound style '%s' has tone '%s', which is not one of %s"
			% [id, tone, Synth.TONES])
	# Two levels is a square wave whatever the source was, and one is silence. Below three the
	# setting stops being a character and starts being a bug.
	if quantise_steps != 0 and quantise_steps < 3:
		out.append("sound style '%s' quantises to %d levels" % [id, quantise_steps])
	return out

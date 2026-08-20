class_name SoundSource
extends RefCounted
## Where a cue's audio comes from - the seam that keeps the game independent of it.
##
## The exact shape of SpriteSource, and for the same reason. Two implementations ship:
## ProceduralSoundSource renders from the bank in memory (used by the tests, so nothing has to
## be on disk to be checked), and FileSoundSource reads the committed WAV (used by the game, so
## startup does no synthesis).
##
## A third - a recorded pack, or a generated one bought from somewhere - needs no change here:
## produce a WAV per cue name, or subclass this and answer `cue()`. AudioBus already prefers a
## hand-dropped file in data/audio over a generated one, so a pack can also replace cues one at
## a time rather than all at once.

## The stream for one cue, or null - with the reason pushed as an error by the implementation.
func cue(_cue_id: StringName) -> AudioStreamWAV:
	push_error("SoundSource.cue is abstract; use ProceduralSoundSource or FileSoundSource")
	return null

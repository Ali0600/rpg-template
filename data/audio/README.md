# Audio

**This directory is for a game's OWN sound.** It is empty on purpose, and it is no longer the
only way to get audio: the template GENERATES a full set of cues from `data/banks/*.json` and
a voice in `data/sounds/*.tres`, the same way it generates sprites from a rig and a style.

Drop an `.ogg`, `.wav` or `.mp3` here and it wins. A file called `hit.wav` replaces the
generated `hit` cue for every game using this directory, with no code change anywhere — and
without deleting anything under `assets/generated/`, which the drift gate would put straight
back. Files may sit in subdirectories; the id is the file name.

Two things are reported rather than left to chance:

- an override is printed once at boot, so replacing a cue is visible rather than mysterious
- two files answering to one name is an error, because the loser is invisible and which one
  loses depends on the filesystem

This directory previously held the argument that a template should ship no audio at all —
*"a placeholder beep committed to a template is a placeholder beep shipped in somebody's
game."* That was right about beeps and wrong about generators, which is the same answer the
art pipeline reached: the template does not ship an art pack either. It ships something a game
re-skins. A game that wants recordings puts them here and the generator gets out of the way.

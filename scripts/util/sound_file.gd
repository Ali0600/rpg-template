class_name SoundFile
extends RefCounted
## Reads a WAV straight off disk as samples, with the import system left out of it.
##
## The sibling of ImageFile, and it exists for the identical reason. A `res://*.wav` in a
## shipped build is not a WAV any more - the importer has turned it into an AudioStreamWAV
## resource and the original file is not packed - so this works in a tool and would fail on a
## player's machine. Nothing here ships: every caller is build-time tooling comparing the
## COMMITTED file against what the generator produces now. The runtime asks AudioBus, which
## uses load() and gets the imported resource like everything else.


## The stream at `path`, or null if it is missing or is not a readable WAV.
##
## `path` is a res:// path and is globalized here, because this deliberately reads a FILE
## rather than a resource - the whole point is to see the committed bytes rather than whatever
## the importer made of them.
##
## Null rather than an error, for the reason ImageFile returns null: the drift gate has
## something better to say than a crash would, namely which file it could not read.
static func read_wav(path: String) -> AudioStreamWAV:
	var absolute := ProjectSettings.globalize_path(path)
	# This guard looks like the one ImageFile deliberately does NOT have, and it is the
	# opposite case. `get_file_as_bytes` returns an empty array for a missing file SILENTLY,
	# so the equivalent check there was dead code and a mutant deleting it survived.
	# `load_from_file` also answers null - but pushes two engine errors first, per file, and
	# the drift gate calls this once per cue. Without the guard, a style whose output has not
	# been generated yet buries its own clean "missing or unreadable" line under a wall of red.
	# So it is kept for the log, not for the answer, and carries no mutant because it cannot
	# change one.
	if not FileAccess.file_exists(absolute):
		return null
	return AudioStreamWAV.load_from_file(absolute)


## The PCM of the file at `path`, or an empty array. What the drift gate compares.
##
## Samples, never encoded file bytes: a container carries a header this project does not
## control, and comparing headers would make the gate fail on a file whose SOUND is identical.
## The art side compares raw pixels rather than PNG bytes for exactly the same reason.
static func samples_of(path: String) -> PackedByteArray:
	var wav := read_wav(path)
	if wav == null:
		return PackedByteArray()
	return wav.data

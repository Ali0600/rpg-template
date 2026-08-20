class_name ImageFile
extends RefCounted
## Reads a PNG straight off disk as pixels, with the import system left out of it.
##
## `Image.load_from_file` does the same job and WARNS on every call - "this will not work on
## export" - which is correct advice aimed at the wrong code. A `res://*.png` in a shipped
## build is not a PNG any more: the importer has turned it into a compressed texture, and the
## original bytes are not packed, so a game that read files this way would work in the editor
## and fail on a player's machine.
##
## Nothing here ships. Every caller is build-time tooling whose whole purpose is comparing the
## COMMITTED file's pixels against what the generator produces now - the drift gate and the
## determinism suite - and `tools/` is excluded from the export. The runtime asks for art
## through `FileSpriteSource`, which uses `load()` and gets the imported resource like
## everything else.
##
## So the warning was 21 lines of noise per verify run, and noise is not free: a log people
## learn to skim is a log where the next real warning goes unread.


## The image at `path`, or null if it is missing or is not a PNG.
##
## Null rather than an error, because the callers already have something better to say: the
## drift gate reports which file it could not read, and a crash inside the reader would lose
## that. Reading the bytes ourselves is also what avoids the import system entirely - there is
## no resource here, just a decode.
##
## There is deliberately no `file_exists` check in front of this. `get_file_as_bytes` returns
## an empty array for a file that is not there, silently, so the guard could never change an
## outcome - a mutant deleting it survived, which is the tell. That behaviour is pinned in
## test_engine_assumptions.gd rather than assumed here.
static func read_png(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image

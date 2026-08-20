extends SceneTree
## Generates every sound cue under assets/generated/<style>/sfx/.
##
##     Godot --headless --path . -s tools/gen_sounds.gd            # write
##     Godot --headless --path . -s tools/gen_sounds.gd --verify   # compare, write nothing
##
## The sibling of gen_sprites.gd, deliberately down to the shape of this file: --verify is the
## drift gate check.sh runs, and it fails if what is committed differs from what the generator
## makes now. Generated audio is build output, and build output that no longer matches its
## source is the quiet failure - someone retunes a cue, forgets to regenerate, and the game
## ships the old noise while the repo describes the new one.
##
## Comparison is over PCM SAMPLES, never encoded file bytes: a WAV carries a container header
## this project does not author, and comparing headers would fail a file that sounds identical.
## The art gate compares raw pixels rather than PNG bytes for exactly the same reason.

const OUT_ROOT := "res://assets/generated"
const STYLE_DIR := "res://data/sounds"
const SFX_SUBDIR := "sfx"

var _verify := false
var _problems: Array[String] = []
var _written := 0
var _compared := 0
var _drifted: Array[String] = []


func _init() -> void:
	for arg in OS.get_cmdline_args():
		if arg == "--verify":
			_verify = true

	var styles := ContentScan.resources(STYLE_DIR, ["tres"] as Array[String])
	# A generator that renders nothing must not report success. The same rule lint_rules.gd
	# follows: a clean scan of zero files is a broken scan, not a clean one.
	if styles.is_empty():
		_fail("no sound styles found in %s" % STYLE_DIR)
		return

	for style_res in styles:
		var style := style_res as SoundStyle
		if style == null:
			continue
		_run_style(style)

	if not _problems.is_empty():
		for p in _problems:
			printerr("gen_sounds: " + p)
		printerr("gen_sounds: %d problem(s)" % _problems.size())
		quit(1)
		return

	if _verify:
		if not _drifted.is_empty():
			for d in _drifted:
				printerr("gen_sounds: OUT OF DATE  " + d)
			printerr("gen_sounds: %d generated file(s) differ from what the generator produces now."
				% _drifted.size())
			printerr("gen_sounds: re-run without --verify and commit the result.")
			quit(1)
			return
		print("gen_sounds: %d generated file(s) match the generator" % _compared)
		quit(0)
		return

	print("gen_sounds: wrote %d file(s) to %s" % [_written, OUT_ROOT])
	quit(0)


func _run_style(style: SoundStyle) -> void:
	for p in style.problems():
		_problems.append(p)
	var bank := SoundBank.load_from(style.bank_id)
	for p in bank.problems():
		_problems.append("style '%s': %s" % [style.id, p])
	if not _problems.is_empty():
		return

	var dir := "%s/%s/%s" % [OUT_ROOT, style.id, SFX_SUBDIR]
	if not _verify:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var source := ProceduralSoundSource.new(style, bank)
	# Sfx.ids() is the work list, not the bank's keys: the vocabulary decides what must exist,
	# and SoundBank.problems() has already refused a bank that cannot answer all of it.
	for cue in Sfx.ids():
		_emit(("%s/%s.wav" % [dir, cue]), source.samples(cue), style)


## Writes one cue, or - in verify mode - compares it with what is on disk.
func _emit(path: String, samples: PackedFloat32Array, style: SoundStyle) -> void:
	if samples.is_empty():
		_problems.append("%s rendered no samples" % path)
		return
	var pcm := Synth.to_pcm16(samples)

	if not _verify:
		var wav := Synth.stream(samples, style.mix_rate)
		var err := wav.save_to_wav(path)
		if err != OK:
			# A generator that reports success while failing to write is worse than one that
			# crashes: the next run compares against whatever stale file is still there.
			_problems.append("could not write %s (error %d)" % [path, err])
			return
		_written += 1
		return

	_compared += 1
	var existing := SoundFile.read_wav(path)
	if existing == null:
		_drifted.append(path + " (missing or unreadable)")
		return
	if existing.mix_rate != style.mix_rate:
		_drifted.append("%s (committed %d Hz, style asks for %d Hz)"
			% [path, existing.mix_rate, style.mix_rate])
		return
	if existing.data.size() != pcm.size():
		_drifted.append("%s (committed %d bytes, generator makes %d)"
			% [path, existing.data.size(), pcm.size()])
		return
	if Hashing.sha256_bytes(existing.data) != Hashing.sha256_bytes(pcm):
		_drifted.append(path + " (samples differ)")
		return
	_check_imported(path, pcm)


## The committed FILE matching the generator is only half of it. What the game plays is the
## IMPORTED resource, and the importer is free to transcode on its way there - its default for
## WAV is QOA, which is lossy. So the file could match perfectly while every player hears
## something else, and nothing anyone looks at would say so.
##
## This compares the thing the running game actually gets. It also catches a .wav committed
## without its .import sidecar, which is a file that works here and is missing from an export.
func _check_imported(path: String, pcm: PackedByteArray) -> void:
	if not ResourceLoader.exists(path):
		_drifted.append(path + " (not imported - is the .import file committed?)")
		return
	var imported := load(path) as AudioStreamWAV
	if imported == null:
		_drifted.append(path + " (imports as something that is not an AudioStreamWAV)")
		return
	if imported.format != AudioStreamWAV.FORMAT_16_BITS:
		_drifted.append("%s (imports as format %d, not 16-bit PCM - check compress/mode)"
			% [path, imported.format])
		return
	if Hashing.sha256_bytes(imported.data) != Hashing.sha256_bytes(pcm):
		_drifted.append(path + " (the imported stream differs from the committed samples)")


func _fail(message: String) -> void:
	printerr("gen_sounds: " + message)
	quit(1)

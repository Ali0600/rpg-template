extends SceneTree
## Generates every sprite sheet and tile sheet under assets/generated/.
##
##     Godot --headless --path . -s tools/gen_sprites.gd            # write
##     Godot --headless --path . -s tools/gen_sprites.gd --verify   # compare, write nothing
##
## --verify is the drift gate check.sh runs: it regenerates everything in memory and fails
## if what is committed differs. Generated art is build output, and build output that no
## longer matches its source is the quiet failure - someone edits a rig, forgets to
## regenerate, and the game ships the old sprites while the repo describes the new ones.
##
## Comparison is over raw pixels (Image.get_data()), never encoded PNG bytes: a PNG carries
## encoder details that can differ between platforms for a picture that is pixel-identical,
## which would make the gate flap in CI.

const OUT_ROOT := "res://assets/generated"
const STYLE_DIR := "res://data/styles"
const RIG_DIR := "res://data/rigs"
const CHARACTER_DIR := "res://data/characters"

var _verify := false
var _problems: Array[String] = []
var _written := 0
var _compared := 0
var _drifted: Array[String] = []


func _init() -> void:
	for arg in OS.get_cmdline_args():
		if arg == "--verify":
			_verify = true

	var styles := _load_all(STYLE_DIR)
	if styles.is_empty():
		_fail("no styles found in %s" % STYLE_DIR)
		return
	var specs := _load_all(CHARACTER_DIR)
	if specs.is_empty():
		_fail("no characters found in %s" % CHARACTER_DIR)
		return

	for style_res in styles:
		var style := style_res as SpriteStyle
		if style == null:
			continue
		_run_style(style, specs)

	if not _problems.is_empty():
		for p in _problems:
			printerr("gen_sprites: " + p)
		printerr("gen_sprites: %d problem(s)" % _problems.size())
		quit(1)
		return

	if _verify:
		if not _drifted.is_empty():
			for d in _drifted:
				printerr("gen_sprites: OUT OF DATE  " + d)
			printerr("gen_sprites: %d generated file(s) differ from what the generator produces now."
				% _drifted.size())
			printerr("gen_sprites: re-run without --verify and commit the result.")
			quit(1)
			return
		print("gen_sprites: %d generated file(s) match the generator" % _compared)
		quit(0)
		return

	print("gen_sprites: wrote %d file(s) to %s" % [_written, OUT_ROOT])
	quit(0)


func _run_style(style: SpriteStyle, all_specs: Array) -> void:
	for p in style.problems():
		_problems.append("style '%s': %s" % [style.id, p])

	var rig := Rig.load_from("%s/%s.json" % [RIG_DIR, style.rig_id])
	for p in rig.problems():
		_problems.append("rig '%s': %s" % [style.rig_id, p])
	if not _problems.is_empty():
		return

	var dir := "%s/%s" % [OUT_ROOT, style.id]
	if not _verify:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var mine: Array[CharacterSpec] = []
	for res in all_specs:
		var spec := res as CharacterSpec
		if spec == null or String(spec.style_id) != String(style.id):
			continue
		for p in spec.problems(rig, style):
			_problems.append(p)
		mine.append(spec)
	if not _problems.is_empty():
		return

	# Sorted so the contact sheet is stable: an unordered directory listing would reshuffle
	# the strip between machines and make the drift gate report a change that is not one.
	mine.sort_custom(func(a: CharacterSpec, b: CharacterSpec) -> bool: return String(a.id) < String(b.id))

	for spec in mine:
		var built := SheetBuilder.build(rig, style, spec)
		var meta: SheetMeta = built["meta"]
		for p in meta.problems((built["image"] as Image).get_size()):
			_problems.append("character '%s': %s" % [spec.id, p])
		_emit_image("%s/%s.png" % [dir, spec.id], built["image"])
		_emit_json("%s/%s.sheet.json" % [dir, spec.id], meta.to_dict())

	var tiles := TileGen.build(style)
	_emit_image("%s/tiles.png" % dir, tiles["image"])
	_emit_json("%s/tiles.json" % dir, tiles["meta"])

	_emit_image("%s/_contact.png" % dir, SheetBuilder.contact_sheet(rig, style, mine))


## Writes the image, or - in verify mode - compares it with what is on disk.
func _emit_image(path: String, img: Image) -> void:
	if not _verify:
		var err := img.save_png(path)
		if err != OK:
			# A generator that reports success while failing to write is worse than one that
			# crashes: the next run compares against whatever stale file is still there.
			_problems.append("could not write %s (error %d)" % [path, err])
			return
		_written += 1
		return

	_compared += 1
	if not FileAccess.file_exists(path):
		_drifted.append(path + " (missing)")
		return
	var existing := ImageFile.read_png(path)
	if existing == null:
		_drifted.append(path + " (unreadable)")
		return
	if existing.get_size() != img.get_size():
		_drifted.append("%s (committed %s, generator makes %s)" % [path, existing.get_size(), img.get_size()])
		return
	if Hashing.image_digest(existing) != Hashing.image_digest(img):
		_drifted.append(path + " (pixels differ)")


func _emit_json(path: String, value: Dictionary) -> void:
	var text := JSON.stringify(value, "\t") + "\n"
	if not _verify:
		var err := JsonFile.write(path, value)
		if err != OK:
			_problems.append("could not write %s (error %d)" % [path, err])
			return
		_written += 1
		return

	_compared += 1
	if not FileAccess.file_exists(path):
		_drifted.append(path + " (missing)")
		return
	if FileAccess.get_file_as_string(path) != text:
		_drifted.append(path + " (metadata differs)")


## Recursive and sorted, via the same walk Registry uses. It was neither, which meant a spec
## in a subdirectory was registered by Registry and never generated here - the drift gate
## then compared nothing and reported green.
func _load_all(dir_path: String) -> Array:
	var exts: Array[String] = ["tres"]
	return ContentScan.resources(dir_path, exts)


func _fail(message: String) -> void:
	printerr("gen_sprites: " + message)
	quit(1)

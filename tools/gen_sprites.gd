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
const TILE_DIR := "res://data/tiles"
const CHARACTER_DIR := "res://data/characters"
## The import arm's input: one folder per character, holding the generator's own two files.
const IMPORT_ROOT := "res://data/imports"
const IMPORT_SHEET := "sheet.png"
const IMPORT_RECIPE := "character.json"

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

	var bank := TileBank.load_from("%s/%s.json" % [TILE_DIR, style.tile_bank_id])
	for p in bank.problems():
		_problems.append("tile bank '%s': %s" % [style.tile_bank_id, p])
	var tile_art := _tile_images(bank)
	for p in TileGen.problems(bank, style, tile_art):
		_problems.append(p)
	if not _problems.is_empty():
		return

	var dir := "%s/%s" % [OUT_ROOT, style.id]
	if not _verify:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	# Two arms, one generator: the sheets are composed from the rig or converted from an
	# import, and the tiles below are made the same way for both - so a style that imports its
	# cast still gets terrain, and --verify gates every kind of art in one run.
	var recipes: Array = []
	if style.imports():
		recipes = _run_imported(style, dir)
	else:
		_run_rig(style, all_specs, dir)
	if not _problems.is_empty():
		return

	var tiles := TileGen.build(style, bank, tile_art)
	_emit_image("%s/tiles.png" % dir, tiles["image"])
	_emit_json("%s/tiles.json" % dir, tiles["meta"])

	# A bank that cuts its pixels is one more recipe, so the artists who drew the ground land in
	# the same credits file as the ones who drew the cast. Emitted HERE rather than in the import
	# arm, because a style can draw its own characters and still stand on somebody else's ground:
	# the file exists exactly when something imported went into it.
	if bank.imports():
		recipes.append({"credits": bank.files()})
	if not recipes.is_empty():
		_emit_json("%s/credits.json" % dir, LpcImport.credits_summary(style, recipes))
		_emit_text("%s/LICENSE.txt" % dir, LpcImport.license_notice(style, recipes))


## The art an imported bank cuts from, by file name. A file that will not read is left OUT rather
## than defaulted, so TileGen.problems() reports it against the tile that wanted it.
func _tile_images(bank: TileBank) -> Dictionary:
	var out := {}
	if not bank.imports():
		return out
	for name in bank.file_names():
		var img := ImageFile.read_png(bank.source_path(name))
		if img != null:
			out[name] = img
	return out


func _run_rig(style: SpriteStyle, all_specs: Array, dir: String) -> void:
	var rig := Rig.load_from("%s/%s.json" % [RIG_DIR, style.rig_id])
	for p in rig.problems():
		_problems.append("rig '%s': %s" % [style.rig_id, p])
	if not _problems.is_empty():
		return

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

	_emit_image("%s/_contact.png" % dir, SheetBuilder.contact_sheet(rig, style, mine))


## The import arm. Every folder under data/imports/<style>/ is one character - the generator's
## sheet.png and character.json, converted by LpcImport - and the folder's name is the character
## id, exactly as a CharacterSpec's id names a rig character. The cast's credits are merged into
## one credits.json beside the sheets (what a credits screen reads) and LICENSE.txt states the
## terms the composed art is under; both are written deterministically so --verify compares them.
## The recipes it converted, for the credits the caller writes.
func _run_imported(style: SpriteStyle, dir: String) -> Array:
	var root := "%s/%s" % [IMPORT_ROOT, style.id]
	var exts: Array[String] = ["png"]
	var sheets := ContentScan.files(root, exts)
	if sheets.is_empty():
		_problems.append("style '%s' imports its sheets, but there is nothing under %s" % [style.id, root])
		return []
	var recipes: Array = []
	for png in sheets:
		var folder := png.get_base_dir()
		var character := folder.get_file()
		if png.get_file() != IMPORT_SHEET:
			_problems.append("%s: an import folder holds one %s; found %s" % [folder, IMPORT_SHEET, png.get_file()])
			continue
		var image := ImageFile.read_png(png)
		if image == null:
			_problems.append("%s: could not read %s" % [folder, IMPORT_SHEET])
			continue
		var doc := JsonFile.read("%s/%s" % [folder, IMPORT_RECIPE])
		if not doc.ok:
			_problems.append("%s: %s" % [folder, doc.error])
			continue
		var faults := LpcImport.problems(image, doc.data, style)
		if not faults.is_empty():
			for p in faults:
				_problems.append("%s/%s: %s" % [style.id, character, p])
			continue
		var built := LpcImport.build(image, doc.data, style, character)
		var meta: SheetMeta = built["meta"]
		for p in meta.problems((built["image"] as Image).get_size()):
			_problems.append("character '%s': %s" % [character, p])
		_emit_image("%s/%s.png" % [dir, character], built["image"])
		_emit_json("%s/%s.sheet.json" % [dir, character], meta.to_dict())
		recipes.append(doc.data)
	return recipes


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


## Plain text, on _emit_json's terms: written, or compared byte for byte.
func _emit_text(path: String, text: String) -> void:
	if not _verify:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_problems.append("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
			return
		f.store_string(text)
		f.close()
		_written += 1
		return

	_compared += 1
	if not FileAccess.file_exists(path):
		_drifted.append(path + " (missing)")
		return
	if FileAccess.get_file_as_string(path) != text:
		_drifted.append(path + " (text differs)")


## Recursive and sorted, via the same walk Registry uses. It was neither, which meant a spec
## in a subdirectory was registered by Registry and never generated here - the drift gate
## then compared nothing and reported green.
func _load_all(dir_path: String) -> Array:
	var exts: Array[String] = ["tres"]
	return ContentScan.resources(dir_path, exts)


func _fail(message: String) -> void:
	printerr("gen_sprites: " + message)
	quit(1)

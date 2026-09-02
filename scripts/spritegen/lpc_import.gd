class_name LpcImport
extends RefCounted
## Turns a Universal LPC Spritesheet Character Generator export into this template's sheet.
##
## The generator (github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator)
## composes hand-drawn layers in a browser and downloads two files: the whole 832x3456
## "universal" sheet as a PNG, and a JSON export naming every layer and its credits. Those two
## files are the INPUT, committed under data/imports/<style>/<character>/; this class is the
## converter tools/gen_sprites.gd runs over them, and the PNG + sheet.json it emits is committed
## and drift-gated exactly like the procedural output. The map importer's shape: the tool is
## the editor, the artifact that ships is ours, and a gate proves the two still agree.
##
## Everything known about LPC's layout is a constant here, measured from the generator's own
## source (sources/state/constants.ts, renderer.ts) rather than remembered:
##	 - a frame is 64x64 and the sheet is 13 frames wide and 54 rows tall, always;
##	 - every animation sits at a FIXED row whatever else was enabled - the walk cycle is
##	   always rows 8-11 - so a sheet is addressed, never searched;
##	 - within a block the rows run up, left, down, right: NOT this template's order, which is
##	   why the walk block is re-cut into canonical rows rather than merely relabelled;
##	 - walk frame 0 is the standing pose and frames 1-8 are the cycle. Idle is that standing
##	   frame, exactly as the procedural rig's is: the generator's own idle rows exist only for
##	   assets that have been redrawn for them, and a hat that vanishes the moment a character
##	   stops walking is worse than no breathing.
##
## Licences are a GATE, not a note. Every layer file the export names carries the licences
## its artist chose; a file offering none of the families the style accepts fails the build,
## naming the file and the licence, because the alternative is art whose terms nobody read
## shipping in somebody's game.

const FRAME := 64
const SHEET_COLUMNS := 13
## The first of the four walk rows on the universal sheet.
const WALK_ROW := 8
## Columns the walk block occupies: the standing pose plus the eight-frame cycle.
const WALK_FRAMES := 9
const WALK_CYCLE: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
## Row order INSIDE an LPC animation block, top to bottom.
const LPC_ROW_ORDER: Array[int] = [Dir.D.UP, Dir.D.LEFT, Dir.D.DOWN, Dir.D.RIGHT]
const SOURCE := "lpc"
const GENERATOR_URL := "https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator"
## Where the terrain comes from. A second route into the same credits file, so the notice can
## name both without a caller having to say which kind of art it handed over.
const TILESET_URL := "https://github.com/OpenGameArt/LiberatedPixelCup"
const SHARE_ALIKE := "CC-BY-SA"


## "CC-BY-SA 3.0" -> "CC-BY-SA", "OGA-BY 3.0+" -> "OGA-BY", "CC0" -> "CC0". The generator's
## strings are a family, a space and a version; a style lists FAMILIES, so the version is
## dropped here and nowhere else. A prefix match would be wrong: "CC-BY" is a prefix of
## "CC-BY-SA", and share-alike is exactly the term a prefix would wave through.
static func license_family(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	return text.split(" ", false)[0].trim_suffix("+")


static func license_allowed(raw: String, style: SpriteStyle) -> bool:
	return style.licenses.has(license_family(raw))


## The credits the export carries, one entry per layer file - an empty array when it has none.
## Tolerates both spellings the generator has used for the file name.
static func credits_of(recipe: Dictionary) -> Array:
	var raw: Variant = recipe.get("credits", [])
	if not raw is Array:
		return []
	var out: Array = []
	for entry: Variant in raw as Array:
		if not entry is Dictionary:
			continue
		var e: Dictionary = entry
		out.append({
			"file": str(e.get("file", e.get("fileName", ""))),
			"authors": JsonFile.to_string_array(e.get("authors", [])),
			"licenses": JsonFile.to_string_array(e.get("licenses", [])),
			"urls": JsonFile.to_string_array(e.get("urls", [])),
		})
	return out


## Everything that would make this export unusable, naming what to fix. A sheet exported with
## Walk switched off, or one layer whose artist chose a licence the style does not accept, are
## both files that look complete and would ship wrong.
static func problems(image: Image, recipe: Dictionary, style: SpriteStyle) -> Array[String]:
	var out: Array[String] = []
	if not style.imports():
		out.append("style '%s' does not import sheets (sheets_from is '%s')" % [style.id, style.sheets_from])
	if style.cell_size != Vector2i(FRAME, FRAME):
		out.append("style '%s' has cell_size %s; LPC frames are %dx%d" % [style.id, style.cell_size, FRAME, FRAME])
	if image == null:
		out.append("no image")
	else:
		var needed_wide := WALK_FRAMES * FRAME
		var needed_tall := (WALK_ROW + LPC_ROW_ORDER.size()) * FRAME
		if image.get_width() < needed_wide:
			out.append("sheet is %d px wide; the walk cycle is %d frames of %d px"
				% [image.get_width(), WALK_FRAMES, FRAME])
		if image.get_height() < needed_tall:
			out.append("sheet is %d px tall; the walk cycle is LPC rows %d-%d, which end at %d px"
				% [image.get_height(), WALK_ROW, WALK_ROW + LPC_ROW_ORDER.size() - 1, needed_tall])
		if image.get_width() >= needed_wide and image.get_height() >= needed_tall:
			for i in LPC_ROW_ORDER.size():
				if _block_ground(image, WALK_ROW + i) < 0:
					out.append("walk row %d (%s) is blank - was the sheet exported with Walk enabled?"
						% [WALK_ROW + i, Dir.name_of(LPC_ROW_ORDER[i])])
	var credits := credits_of(recipe)
	if credits.is_empty():
		out.append("the export carries no credits list; every LPC layer must be credited")
	for c: Dictionary in credits:
		var file := str(c["file"])
		var licenses := JsonFile.to_string_array(c["licenses"])
		if licenses.is_empty():
			out.append("credit for '%s' names no licence" % file)
			continue
		var allowed := false
		for l in licenses:
			if license_allowed(l, style):
				allowed = true
		if not allowed:
			out.append("'%s' is licensed %s; style '%s' accepts %s" % [file, licenses, style.id, style.licenses])
	return out


## {"image": Image, "meta": SheetMeta, "credits": Array} - the same pair SheetBuilder.build
## returns, plus the credits that must travel with it. Call problems() first; this trusts its
## input the way the compositor does.
static func build(image: Image, recipe: Dictionary, style: SpriteStyle, character_id: String) -> Dictionary:
	var src := image.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var cell := Vector2i(FRAME, FRAME)
	var rows := Dir.ALL.size()
	var sheet := Image.create_empty(cell.x * WALK_FRAMES, cell.y * rows, false, Image.FORMAT_RGBA8)

	var ground := -1
	for row in rows:
		# The output row is canonical; the input row is wherever LPC keeps that direction.
		var lpc_row := WALK_ROW + LPC_ROW_ORDER.find(Dir.ALL[row])
		for col in WALK_FRAMES:
			var from := Rect2i(col * cell.x, lpc_row * cell.y, cell.x, cell.y)
			# blit_rect is exact here for SheetBuilder's reason: the destination is untouched
			# transparent space, so there is no lower layer for the source's alpha to erase.
			sheet.blit_rect(src, from, Vector2i(col * cell.x, row * cell.y))
			ground = maxi(ground, SpriteCompositor.ground_row(src.get_region(from)))

	var meta := SheetMeta.new()
	meta.cell = cell
	meta.columns = WALK_FRAMES
	meta.rows = rows
	meta.directions = Dir.ALL.duplicate()
	# Measured, not declared - SheetBuilder's rule. LPC bodies stand a few rows above the
	# bottom of the frame, and a shadow layer, if one was exported, stands lower still.
	meta.anchor = Vector2i(cell.x / 2, ground)
	meta.animations = {
		"idle": {"frames": [0], "fps": style.idle_fps, "loop": true},
		"walk": {"frames": WALK_CYCLE.duplicate(), "fps": style.walk_fps, "loop": true},
	}
	meta.source = SOURCE
	meta.style = String(style.id)
	meta.character = character_id
	meta.seed = 0
	return {"image": sheet, "meta": meta, "credits": merged_credits(recipe)}


## One entry per layer file, in one order whatever order the export listed them in - the
## drift gate compares this text, so it may not depend on how a browser happened to walk a
## selection. A file named twice is kept once.
static func merged_credits(recipe: Dictionary) -> Array:
	var by_file: Dictionary = {}
	for c: Dictionary in credits_of(recipe):
		var file := str(c["file"])
		if by_file.has(file):
			continue
		var authors := JsonFile.to_string_array(c["authors"])
		authors.sort()
		var licenses := JsonFile.to_string_array(c["licenses"])
		licenses.sort()
		var urls := JsonFile.to_string_array(c["urls"])
		urls.sort()
		by_file[file] = {"file": file, "authors": authors, "licenses": licenses, "urls": urls}
	var files: Array = by_file.keys()
	files.sort()
	var out: Array = []
	for f: Variant in files:
		out.append(by_file[f])
	return out


## The credits of a whole cast, merged across every character's export, for the credits screen
## and for anyone reading the repository. `authors` and `licenses` are the flat lists a one-line
## credit needs; `files` is the full accounting.
static func credits_summary(style: SpriteStyle, recipes: Array) -> Dictionary:
	var by_file: Dictionary = {}
	for recipe: Dictionary in recipes:
		for c: Dictionary in merged_credits(recipe):
			if not by_file.has(c["file"]):
				by_file[c["file"]] = c
	# `names`, not `files`, so the sort here and the one in merged_credits stay two different
	# lines: a mutant aimed at either must not be able to land on the other.
	var names: Array = by_file.keys()
	names.sort()
	var entries: Array = []
	var authors: Array[String] = []
	var licenses: Array[String] = []
	for f: Variant in names:
		var c: Dictionary = by_file[f]
		entries.append(c)
		for a in JsonFile.to_string_array(c["authors"]):
			if not authors.has(a):
				authors.append(a)
		for l in JsonFile.to_string_array(c["licenses"]):
			var family := license_family(l)
			if not licenses.has(family):
				licenses.append(family)
	authors.sort()
	licenses.sort()
	return {
		"style": String(style.id),
		"source": "Liberated Pixel Cup (LPC) art: character sheets composed with the Universal "
			+ "LPC Spritesheet Character Generator, terrain cut from the LPC tileset",
		"generator": GENERATOR_URL,
		"tileset": TILESET_URL,
		"authors": authors,
		"licenses": licenses,
		"files": entries,
	}


## The terms the composed sheets are under, as text beside them. Share-alike is contagious:
## one CC-BY-SA layer makes the composed sheet CC-BY-SA, and the notice says so rather than
## leaving a reader to work it out from the file list.
static func license_notice(style: SpriteStyle, recipes: Array) -> String:
	var summary := credits_summary(style, recipes)
	var lines: Array[String] = []
	lines.append("The art in this directory (style '%s') is Liberated Pixel Cup (LPC) work." % style.id)
	lines.append("Character sheets were composed with the Universal LPC Spritesheet Character")
	lines.append("Generator; terrain was cut from the LPC tileset.")
	lines.append("  %s" % GENERATOR_URL)
	lines.append("  %s" % TILESET_URL)
	lines.append("")
	lines.append("Every file, its artists, licences and source URLs are listed in credits.json")
	lines.append("beside this file. Artists: %s." % ", ".join(JsonFile.to_string_array(summary["authors"])))
	lines.append("")
	lines.append("Licences carried by the layers: %s." % ", ".join(JsonFile.to_string_array(summary["licenses"])))
	if JsonFile.to_string_array(summary["licenses"]).has(SHARE_ALIKE):
		lines.append("Because some layers are CC-BY-SA, the composed sheets here are distributed under")
		lines.append("CC-BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/")
	else:
		lines.append("The composed sheets here are distributed under the same terms; credit the artists.")
	lines.append("")
	lines.append("The template's own code is not covered by this notice.")
	return "\n".join(lines) + "\n"


## The lowest row with an opaque pixel anywhere across one LPC row's walk frames, or -1 when
## the whole row is blank.
static func _block_ground(image: Image, lpc_row: int) -> int:
	var ground := -1
	for col in WALK_FRAMES:
		var cell := image.get_region(Rect2i(col * FRAME, lpc_row * FRAME, FRAME, FRAME))
		ground = maxi(ground, SpriteCompositor.ground_row(cell))
	return ground

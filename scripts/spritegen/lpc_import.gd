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
##	 - the slash is rows 12-15, six frames, and is cut into the columns after the walk ONLY when
##	   a sheet draws it: a character composed walk-only imports exactly as it always did;
##	 - a swing the generator draws on BIGGER frames is a block under the universal sheet, and is
##	   cut from there onto a grid of its own when the export records where (custom_slash_of);
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
const SHEET_ROWS := 54
## The first of the four walk rows on the universal sheet.
const WALK_ROW := 8
## Columns the walk block occupies: the standing pose plus the eight-frame cycle.
const WALK_FRAMES := 9
const WALK_CYCLE: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
## The first of the four slash rows, and its frames: the generator's own `slash` animation config
## (sources/state/constants.ts ANIMATION_CONFIGS: row 12, cycle 0-5, at the pinned commit).
const SLASH_ROW := 12
const SLASH_FRAMES := 6
## The one animation a swing block below the sheet may be, as LpcCompose records it.
const SLASH_CLIP := "slash"
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


## The record of a swing drawn below the universal sheet, as LpcCompose writes it into the export -
## {"name", "clip", "frameSize", "x", "y", "columns", "rows"} - or empty when there is none. The
## browser's own export never says where it drew one, which is why problems() refuses a sheet past
## the universal size that carries no record rather than guessing.
static func custom_slash_of(recipe: Dictionary) -> Dictionary:
	var raw: Variant = recipe.get("customAnimations", [])
	if not raw is Array or (raw as Array).is_empty():
		return {}
	var first: Variant = (raw as Array)[0]
	if not first is Dictionary:
		return {}
	return first as Dictionary


## The rectangle of the sheet a record's block covers.
static func block_rect(record: Dictionary) -> Rect2i:
	var size := int(record.get("frameSize", 0))
	return Rect2i(int(record.get("x", 0)), int(record.get("y", 0)),
		size * int(record.get("columns", 0)), size * int(record.get("rows", 0)))


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
			if has_slash(image):
				for i in LPC_ROW_ORDER.size():
					if _block_ground(image, SLASH_ROW + i, SLASH_FRAMES) < 0:
						out.append("slash row %d (%s) is blank - a sheet that draws a slash draws it facing all four ways"
							% [SLASH_ROW + i, Dir.name_of(LPC_ROW_ORDER[i])])
		out.append_array(_block_problems(image, recipe))
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


## Whether a sheet draws the slash: anything at all on its four slash rows. A sheet too short to
## reach them draws none. The size guard changes no answer - reading past the end of an image hands
## back nothing, which reads as blank - and exists so a walk-only sheet asks without the engine
## printing an error for every cell, which is why no mutant is aimed at it.
static func has_slash(image: Image) -> bool:
	var reaches := image.get_height() >= (SLASH_ROW + LPC_ROW_ORDER.size()) * FRAME
	if not reaches or image.get_width() < SLASH_FRAMES * FRAME:
		return false
	for i in LPC_ROW_ORDER.size():
		if _block_ground(image, SLASH_ROW + i, SLASH_FRAMES) >= 0:
			return true
	return false


## {"image": Image, "meta": SheetMeta, "credits": Array} - the same pair SheetBuilder.build
## returns, plus the credits that must travel with it. Call problems() first; this trusts its
## input the way the compositor does.
static func build(image: Image, recipe: Dictionary, style: SpriteStyle, character_id: String) -> Dictionary:
	var src := image.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var cell := Vector2i(FRAME, FRAME)
	var rows := Dir.ALL.size()
	# A swing drawn below the universal sheet, when the export records one, is cut from there; rows
	# 12-15 then hold the unarmed body the generator draws as well, and are not read.
	var record := custom_slash_of(recipe)
	var slashes := record.is_empty() and has_slash(src)
	var columns := WALK_FRAMES + (SLASH_FRAMES if slashes else 0)
	var sheet := Image.create_empty(cell.x * columns, cell.y * rows, false, Image.FORMAT_RGBA8)

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

	# The slash, when the sheet draws one, goes in the columns after the walk, in the same canonical
	# rows. Nothing is MEASURED from it: a lunge, or a blade held below the feet, must not move the
	# ground line the whole cast is placed by - the anchor stays the walk's.
	var swing: Array[int] = []
	if slashes:
		for row in rows:
			var slash_row := SLASH_ROW + LPC_ROW_ORDER.find(Dir.ALL[row])
			for col in SLASH_FRAMES:
				var cut := Rect2i(col * cell.x, slash_row * cell.y, cell.x, cell.y)
				sheet.blit_rect(src, cut, Vector2i((WALK_FRAMES + col) * cell.x, row * cell.y))
		for col in SLASH_FRAMES:
			swing.append(WALK_FRAMES + col)
	elif not record.is_empty():
		# On a grid of its own below the walk, so the frames count along that grid.
		swing.assign(range(SLASH_FRAMES))

	var meta := SheetMeta.new()
	meta.cell = cell
	meta.columns = columns
	meta.rows = rows
	meta.directions = Dir.ALL.duplicate()
	# Measured, not declared - SheetBuilder's rule. LPC bodies stand a few rows above the
	# bottom of the frame, and a shadow layer, if one was exported, stands lower still.
	meta.anchor = Vector2i(cell.x / 2, ground)
	# Cut from the sheet just built rather than from the export, so both arms measure the same
	# thing: the frame this character faces the camera on, standing still. Frame 0 of the
	# canonical DOWN row - LPC's own standing pose, and the one `idle` plays.
	meta.portrait = SpriteCompositor.portrait_rect(
		sheet.get_region(Rect2i(0, Dir.ALL.find(Dir.D.DOWN) * cell.y, cell.x, cell.y)),
		meta.anchor.x, style.portrait_size)
	meta.animations = {
		"idle": {"frames": [0], "fps": style.idle_fps, "loop": true},
		"walk": {"frames": WALK_CYCLE.duplicate(), "fps": style.walk_fps, "loop": true},
	}
	if not swing.is_empty():
		# Played once: a swing that looped would read as the blade still out after it was put away.
		meta.animations["slash"] = {"frames": swing, "fps": style.slash_fps, "loop": false}
	meta.source = SOURCE
	meta.style = String(style.id)
	meta.character = character_id
	meta.seed = 0
	if not slashes and not swing.is_empty():
		sheet = _drawn_below(sheet, src, record, meta)
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


## What stops a swing block being cut. A sheet past the universal size with no record says nothing
## about where its extra art is - the browser's own download, whose export never says; a record of
## something other than a slash is not this importer's; a block the wrong shape or outside the sheet
## cannot be read; and a swing blank facing one way is a hero who swings at nothing a quarter of the
## time.
static func _block_problems(image: Image, recipe: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var record := custom_slash_of(recipe)
	if record.is_empty():
		if image.get_width() > SHEET_COLUMNS * FRAME or image.get_height() > SHEET_ROWS * FRAME:
			out.append("sheet is %s, past the universal %dx%d, and the export does not say what is drawn there; a swing below the sheet needs a customAnimations record"
				% [image.get_size(), SHEET_COLUMNS * FRAME, SHEET_ROWS * FRAME])
		return out
	var block := block_rect(record)
	var size := int(record.get("frameSize", 0))
	if str(record.get("clip", "")) != SLASH_CLIP:
		out.append("the export's '%s' block is drawn as '%s'; this importer reads a slash"
			% [record.get("name", ""), record.get("clip", "")])
	elif int(record.get("columns", 0)) != SLASH_FRAMES or int(record.get("rows", 0)) != LPC_ROW_ORDER.size():
		out.append("the export's swing block is %s by %s; a swing block is %d frames on %d rows"
			% [record.get("columns", 0), record.get("rows", 0), SLASH_FRAMES, LPC_ROW_ORDER.size()])
	elif not block.has_area() or not Rect2i(Vector2i.ZERO, image.get_size()).encloses(block):
		out.append("the export puts its swing at %s, outside the %s sheet" % [block, image.get_size()])
	else:
		for i in LPC_ROW_ORDER.size():
			var strip := image.get_region(Rect2i(block.position.x, block.position.y + i * size, block.size.x, size))
			if not strip.get_used_rect().has_area():
				out.append("swing row %d (%s) of the export's block is blank - a swing is drawn facing all four ways"
					% [i, Dir.name_of(LPC_ROW_ORDER[i])])
	return out


## The swing cut from the export's block onto a grid of its own below the walk, cropped to the
## smallest box holding everything any of its 24 frames draws. Cropped because the arena makes room
## for how far a clip's cell reaches past the feet, and an uncropped 128px cell asks for a floor wider
## than the screen; nothing drawn is lost, since the box is measured from the pixels. The anchor is the
## walk's, moved by the generator's centring of a 64px frame in the bigger cell and then by the crop.
static func _drawn_below(sheet: Image, src: Image, record: Dictionary, meta: SheetMeta) -> Image:
	var size := int(record.get("frameSize", FRAME))
	var block := block_rect(record)
	var crop := Rect2i()
	for block_rank in LPC_ROW_ORDER.size():
		for col in SLASH_FRAMES:
			var corner := block.position + Vector2i(col * size, block_rank * size)
			var used := src.get_region(Rect2i(corner, Vector2i(size, size))).get_used_rect()
			if not used.has_area():
				continue
			crop = used if not crop.has_area() else crop.merge(used)
	var below := sheet.get_height()
	var out := Image.create_empty(maxi(sheet.get_width(), SLASH_FRAMES * crop.size.x),
		below + LPC_ROW_ORDER.size() * crop.size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(sheet, Rect2i(Vector2i.ZERO, sheet.get_size()), Vector2i.ZERO)
	for row in Dir.ALL.size():
		var block_row := LPC_ROW_ORDER.find(Dir.ALL[row])
		for col in SLASH_FRAMES:
			var frame := Rect2i(block.position + Vector2i(col * size, block_row * size) + crop.position, crop.size)
			out.blit_rect(src, frame, Vector2i(col * crop.size.x, below + row * crop.size.y))
	var pad := (size - FRAME) / 2
	var clip: Dictionary = meta.animations[SLASH_CLIP]
	clip["cell"] = [crop.size.x, crop.size.y]
	clip["origin"] = [0, below]
	clip["anchor"] = [meta.anchor.x + pad - crop.position.x, meta.anchor.y + pad - crop.position.y]
	return out


## The lowest row with an opaque pixel anywhere across the first `columns` frames of one LPC row,
## or -1 when they are all blank.
static func _block_ground(image: Image, lpc_row: int, columns := WALK_FRAMES) -> int:
	var ground := -1
	for col in columns:
		var cell := image.get_region(Rect2i(col * FRAME, lpc_row * FRAME, FRAME, FRAME))
		ground = maxi(ground, SpriteCompositor.ground_row(cell))
	return ground

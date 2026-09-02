class_name TileGen
extends RefCounted
## Draws the terrain strip from an authored TileBank, in a style's colours.
##
## Sharing the palette is the whole point: a cast drawn in one set of colours standing on
## ground drawn in another looks pasted on, and it is the most common way a game made of
## mixed assets betrays itself. Because the tiles take their tones from the style, swapping
## the style re-skins the world and the characters together.
##
## This used to hold the tiles themselves - a const array of six, drawn by five hardcoded
## procedural routines. That was the one place this template kept art in code, and it had a
## cost a reader can see: no routine could draw a door, so the quest's cave was built out of
## grass-world tiles. The pixels now come from data/tiles/<id>.json and this file is only the
## compositor, which is the same division SheetBuilder has with the rig.
##
## A bank that IMPORTS its pixels is the other arm: each tile is a cell CUT from art an artist
## drew, so the palette argument above does not apply to it and neither does the style's ramp -
## what you get is what they painted. `images` maps a file name to its Image; the caller reads
## them, because nothing in spritegen touches a file.


## {"image": Image, "meta": Dictionary} - a horizontal strip plus the JSON that describes it.
##
## The meta is the contract every consumer downstream reads: TileSetFactory takes `solid`
## from it and MapBuilder resolves a map's legend against `id`. Neither has ever known where
## the pixels came from, which is why moving them cost nothing outside this file.
static func build(style: SpriteStyle, bank: TileBank, images: Dictionary = {}) -> Dictionary:
	var size := style.tile_size
	var strip := Image.create_empty(maxi(size * bank.size(), 1), maxi(size, 1), false, Image.FORMAT_RGBA8)
	var entries: Array = []

	for index in bank.size():
		var entry := bank.at(index)
		var tile_id := str(entry.get("id", ""))
		var ramp_name := "" if bank.imports() else bank.ramp_for(index, style)
		var tile: Image = null
		if bank.imports():
			# problems() has already refused a missing image and a cell outside it, which is why
			# this can read them straight - LpcImport's rule, and for its reason: a builder that
			# also validates ends up with two half-checks and no whole one.
			tile = _cut(images.get(bank.source_of(index)) as Image, bank.cell_of(index), size)
		else:
			var tones := style.ramp(ramp_name)
			if tones.size() != 3:
				push_error("TileGen: style '%s' has no ramp for tile '%s'" % [style.id, tile_id])
				continue
			tile = _draw(bank.rows_of(index), tones, style.outline_color(), size)
		if tile == null:
			continue
		# blit, not blend: blending would mix a decor tile's transparent margin with the
		# strip's own transparency as floats and land off the palette.
		strip.blit_rect(tile, Rect2i(0, 0, size, size), Vector2i(index * size, 0))
		entries.append({
			"id": tile_id,
			"index": index,
			"solid": bool(entry.get("solid", false)),
			"decor": bool(entry.get("decor", false)),
			"ramp": ramp_name,
		})

	return {
		"image": strip,
		"meta": {
			"version": 1,
			"tile_size": size,
			"columns": bank.size(),
			"rows": 1,
			"style": String(style.id),
			"tiles": entries,
		},
	}


## What a bank and a style disagree about. Separate from TileBank.problems() for the reason
## CharacterSpec.problems(rig, style) is separate from Rig.problems(): a bank is wrong on its
## own terms or it is wrong against a particular style, and only the second needs both.
static func problems(bank: TileBank, style: SpriteStyle, images: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if not bank.ok:
		return out
	if bank.tile != style.tile_size:
		out.append("style '%s' has tile_size %d, but its tile bank is authored at %d"
			% [style.id, style.tile_size, bank.tile])
	if bank.imports():
		_licence_problems(bank, style, out)
		for index in bank.size():
			_cut_problems(bank, index, images, out)
		return out
	for index in bank.size():
		var ramp_name := bank.ramp_for(index, style)
		if style.ramp(ramp_name).size() != 3:
			out.append("style '%s' has no ramp '%s' for tile '%s'"
				% [style.id, ramp_name, bank.at(index).get("id", "")])
	return out


## Whether every file this bank cuts from is offered under a licence the style accepts. Through
## `LpcImport.license_allowed`, which is the ONE place that question is answered here - a second
## opinion about licence families is how a share-alike layer ships as credit-only, since CC-BY is
## a prefix of CC-BY-SA and a prefix test waves it through.
static func _licence_problems(bank: TileBank, style: SpriteStyle, out: Array[String]) -> void:
	for entry: Variant in bank.files():
		var record: Dictionary = entry
		var file := str(record.get("file", ""))
		var licences := JsonFile.to_string_array(record.get("licenses", []))
		var allowed := false
		for licence in licences:
			if LpcImport.license_allowed(licence, style):
				allowed = true
		if not allowed:
			out.append("'%s' is licensed %s; style '%s' accepts %s"
				% [file, licences, style.id, style.licenses])


## Whether one tile's cut can be made, and whether what comes out is fit to stand on.
static func _cut_problems(bank: TileBank, index: int, images: Dictionary, out: Array[String]) -> void:
	var tile_id := str(bank.at(index).get("id", ""))
	var from := bank.source_of(index)
	if not images.has(from):
		out.append("tile '%s' is cut from '%s', which is not at %s"
			% [tile_id, from, bank.source_path(from)])
		return
	var image := _rgba(images[from] as Image)
	var size := bank.tile
	var cell := bank.cell_of(index)
	var rect := Rect2i(cell.x * size, cell.y * size, size, size)
	if cell.x < 0 or cell.y < 0 or rect.end.x > image.get_width() or rect.end.y > image.get_height():
		out.append("tile '%s' wants cell %s of '%s', which is only %d by %d cells"
			% [tile_id, str(cell), from, image.get_width() / size, image.get_height() / size])
		return
	if bool(bank.at(index).get("decor", false)):
		return
	# The hole rule, measured rather than read: a ground tile with a transparent pixel shows the
	# window's background through the world, and the cut looks perfectly fine on the sheet it
	# came from - most of these sheets are mostly transparent by design.
	var cut := image.get_region(rect)
	for y in size:
		for x in size:
			if cut.get_pixel(x, y).a < 1.0:
				out.append("tile '%s' is cut from %s of '%s', which is transparent at %d,%d - "
					% [tile_id, str(cell), from, x, y] + "only a decor tile may be")
				return


## One tile, cut out of somebody's art. Null only where problems() has already spoken.
static func _cut(image: Image, cell: Vector2i, size: int) -> Image:
	if image == null or cell.x < 0 or cell.y < 0:
		return null
	return _rgba(image).get_region(Rect2i(cell.x * size, cell.y * size, size, size))


## The same image in RGBA8. An opaque PNG decodes as RGB8, where every alpha reads 1.0 - so the
## hole check above would pass anything - and `blit_rect` refuses a format it does not share with
## its destination. Converted in ONE place, so no caller can forget which it was handed.
static func _rgba(image: Image) -> Image:
	if image.get_format() == Image.FORMAT_RGBA8:
		return image
	var out := image.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	return out


## One tile, from its authored rows. set_pixel only, never blend_rect - blending produces
## colours between the ramp's tones, and the palette gate is there to catch exactly that.
static func _draw(rows: Array[String], tones: PackedColorArray, outline: Color, size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in mini(rows.size(), size):
		var row := rows[y]
		for x in mini(row.length(), size):
			var ch := row[x]
			if ch == TileBank.TRANSPARENT_CHAR:
				continue
			if ch == TileBank.OUTLINE_CHAR:
				img.set_pixel(x, y, outline)
				continue
			var tone := TileBank.TONE_CHARS.find(ch)
			if tone >= 0:
				img.set_pixel(x, y, tones[tone])
	return img
